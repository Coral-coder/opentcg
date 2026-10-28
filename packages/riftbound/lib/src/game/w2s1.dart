part of 'game.dart';

/// Wave 2, slice 1 (ir_w2s1.dart): choosing, resolving and the rules hooks for the one-off cards
/// from Acceleration Gate to Fiora, Peerless. State lives in [GenState] ("o12:s1…" keys are
/// forgotten when the object leaves the board) and [GameState.marks] ("s1:…").
extension GameS1 on Game {
  // -------------------------------------------------------------------------------------------
  // Choosing (CR 355.5)
  // -------------------------------------------------------------------------------------------

  /// This slice's choices for [e] as it's played: [got] reads a slot chosen so far, [set] fills
  /// one. Mandatory choices with no option are an error unless [optional] (a trigger).
  void _s1Choose(S1Effect e, int p, ObjId source, int loc, int Function(int) got, void Function(int, int) set, {required bool optional}) {
    bool ok(ObjId id) => !_unchoosable(id, p) && !_genUntargetable(id, p);
    List<int> one(List<ObjId> options, String prompt, {bool upTo = false}) {
      if (options.isEmpty) {
        if (upTo || optional) return const [];
        throw RiftboundError('No legal target for ${nameOf(source)}');
      }
      return ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: $prompt', options: options, min: upTo ? 0 : 1, max: 1, source: source));
    }

    for (final k in e.picks) {
      switch (k.kind) {
        case S1PickKind.readyables:
          final options = [
            for (final o in state.objects.values)
              if (o.exhausted && ((o.zone == Zone.board && (card(o.id).type == CardType.unit || card(o.id).type == CardType.gear) && ok(o.id)) || o.zone == Zone.runes)) o.id,
          ];
          final a = options.isEmpty ? const <int>[] : ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: choose up to ${k.n} to ready', options: options, min: 0, max: k.n < options.length ? k.n : options.length, source: source));
          for (var i = 0; i < k.n; i++) {
            set(k.slot + i, i < a.length ? a[i] : -1);
          }
        case S1PickKind.friendlyUnit:
          final not = k.other >= 0 ? got(k.other) : -1;
          final a = one([for (final u in units(player: p)) if (u != not && ok(u)) u], k.other >= 0 ? 'choose another friendly unit' : 'choose a friendly unit');
          set(k.slot, a.isEmpty ? -1 : a.first);
        case S1PickKind.enemyUnitAtBfWithBf:
          final a = one([for (final u in enemyUnits(p)) if (state.obj(u).loc != base && ok(u)) u], 'choose an enemy unit at a battlefield');
          set(k.slot, a.isEmpty ? -1 : a.first);
          set(k.slot + 1, a.isEmpty ? -1 : state.obj(a.first).loc);
        case S1PickKind.furyThreatened:
          final a = one([for (final u in units(player: p)) if (ok(u) && _s1FuryThreatened(u, p)) u], 'choose a friendly unit facing Fury');
          set(k.slot, a.isEmpty ? -1 : a.first);
        case S1PickKind.unitAtBfOrGear:
          final options = [
            for (final o in state.objects.values)
              if (o.zone == Zone.board && ok(o.id) && ((card(o.id).type == CardType.unit && o.loc != base) || card(o.id).type == CardType.gear)) o.id,
          ];
          final a = one(options, 'choose a unit at a battlefield or a gear');
          set(k.slot, a.isEmpty ? -1 : a.first);
        case S1PickKind.enemyPerLocation:
          final enemy = enemyUnits(p);
          var i = 0;
          for (final at in [base, for (var b = 0; b < state.bfs.length; b++) b]) {
            if (i >= k.n) break;
            final options = [for (final u in enemy) if (state.obj(u).loc == at && ok(u)) u];
            if (options.isEmpty) continue;
            final a = one(options, 'choose up to one enemy unit at ${locName(at, p)}', upTo: true);
            set(k.slot + i, a.isEmpty ? -1 : a.first);
            i++;
          }
          for (; i < k.n; i++) {
            set(k.slot + i, -1);
          }
        case S1PickKind.anyUnit:
          final what = e is S1DoubleAndGrant ? 'choose a unit to give +Might (doubled)' : 'choose a unit to deal ${e is S1Grenade ? e.n : ''} to';
          final a = one([for (final u in units()) if (ok(u)) u], what);
          set(k.slot, a.isEmpty ? -1 : a.first);
      }
    }
  }

  /// "In combat with an enemy Fury unit or … being chosen by an enemy Fury spell".
  bool _s1FuryThreatened(ObjId u, int p) {
    final o = state.obj(u);
    final sd = state.showdown;
    if (sd != null && sd.combat && sd.bf == o.loc && enemyUnits(p, bf: o.loc).any((e) => card(e).domains.contains(Domain.fury))) return true;
    for (final it in state.chain) {
      if (it.isSpell && !state.allied(it.controller, p) && db[it.card]!.domains.contains(Domain.fury) && it.targets.contains(u)) return true;
    }
    return false;
  }

  /// Notes that a spell or a unit's ability chose an enemy unit or gear (Ezreal, Prodigal
  /// Explorer): once per choosing.
  void _s1Chosen(List<int> chosen, int p, ObjId source) {
    if (_probe) return;
    final s = state.objOrNull(source);
    if (s == null) return;
    final t = card(source).type;
    if (t != CardType.spell && t != CardType.unit) return;
    for (final id in chosen.toSet()) {
      if (id <= 0 || id >= _chainRef) continue;
      final o = state.objOrNull(id);
      if (o == null || o.zone != Zone.board || state.allied(o.controller, p)) continue;
      final ct = card(id).type;
      if (ct == CardType.unit || ct == CardType.gear) {
        _gen.add('p$p:s1choseEnemy');
        return;
      }
    }
  }

  int _s1Slot(_Ctx ctx, int slot) => slot < ctx.targets.length ? ctx.targets[slot] : -1;

  bool _s1OnBoard(int id) => id >= 0 && state.objOrNull(id)?.zone == Zone.board;

  // -------------------------------------------------------------------------------------------
  // Resolving
  // -------------------------------------------------------------------------------------------

  void _s1Resolve(S1Effect e, _Ctx ctx) {
    final p = ctx.controller;
    final pl = state.player(p);
    switch (e) {
      case S1ReadyPicked(:final pick):
        for (var i = 0; i < pick.n; i++) {
          final id = _s1Slot(ctx, pick.slot + i);
          final o = id < 0 ? null : state.objOrNull(id);
          if (o == null || !o.exhausted) continue;
          if (o.zone == Zone.runes) {
            o.exhausted = false;
          } else if (o.zone == Zone.board && !_hCantReady(id) && _genCanReady(id, p)) {
            _xBecameReady(id);
            o.exhausted = false;
            if (isUnit(id)) _genReadied(id, p);
          } else {
            continue;
          }
          log('${nameOf(id)} is readied.', player: p, card: id, kind: 'info');
        }
      case S1HandToDeck():
        if (pl.hand.isEmpty) return;
        final id = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Put a card from your hand on your Main Deck', options: List.of(pl.hand), min: 1, max: 1, source: ctx.source)).first;
        final top = ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Put ${nameOf(id)} on the top or the bottom?', labels: const ['Top', 'Bottom'], source: ctx.source)).first == 0;
        pl.hand.remove(id);
        state.obj(id).zone = Zone.mainDeck;
        if (top) {
          pl.deck.insert(0, id);
        } else {
          pl.deck.add(id);
        }
        log('${pl.name} puts a card on the ${top ? 'top' : 'bottom'} of their Main Deck.', player: p, kind: 'info');
      case S1BanishUntilHold():
        final q = state.multi ? chooseOpponent(p, '${nameOf(ctx.source)}: which opponent reveals their hand?') : state.other(p);
        final hand = state.player(q).hand;
        log('${playerName(q)} reveals their hand${hand.isEmpty ? ' (empty)' : ': ${hand.map(nameOf).join(', ')}'}.', player: q, kind: 'info');
        if (hand.isEmpty) return;
        final id = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose a card of ${playerName(q)} to banish until they hold', options: List.of(hand), min: 1, max: 1, source: ctx.source)).first;
        hand.remove(id);
        state.obj(id)
          ..zone = Zone.banish
          ..banishedBy = ctx.source;
        state.player(q).banish.add(id);
        state.marks['s1:untilHold:$id'] = 1;
        log('${nameOf(id)} is banished until ${playerName(q)} holds.', player: p, card: id, kind: 'info');
      case S1GiveKw(:final kw, :final n, :final target, :final pick):
        final ids = pick == null ? _resolveTarget(target, ctx) : [if (_s1OnBoard(_s1Slot(ctx, pick.slot))) _s1Slot(ctx, pick.slot)];
        for (final id in ids) {
          if (state.objOrNull(id)?.zone != Zone.board) continue;
          // As long as it stays on the board (CR 801.3.a.3).
          _gen.setL('o$id:kw${kw.index}', _gen.getL('o$id:kw${kw.index}') + n);
          log('${nameOf(id)} gains ${kwLabel(kw)}${n > 1 ? ' $n' : ''}.', player: p, card: id, kind: 'buff');
        }
      case S1KillManyTo(:final n, :final effects):
        final options = [
          for (final o in _boardOf(p))
            if (o.id != ctx.source && (card(o.id).type == CardType.unit || card(o.id).type == CardType.gear)) o.id,
        ];
        if (options.length < n) return;
        if (!askYesNo(p, '${nameOf(ctx.source)}: kill $n other friendly units and/or gear to ${effects.map(describeEffect).join(', ')}?', source: ctx.source)) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose $n to sacrifice', options: options, min: n, max: n, source: ctx.source));
        for (final id in pick) {
          log('${nameOf(id)} is killed.', player: p, card: id, kind: 'die');
          _kill(id);
        }
        _resolveEffects(effects, ctx);
      case S1OpponentFollows(:final destSlot):
        final bf = _genSlotLoc(destSlot, ctx.targets);
        if (bf == null || bf < 0 || bf >= state.bfs.length) return;
        final bfObj = state.bfs[bf].obj;
        final q = state.multi ? chooseOpponent(p, '${nameOf(ctx.source)}: which opponent moves a unit there?') : state.other(p);
        final options = [for (final u in units(player: q)) if (state.obj(u).loc != bf && !_eqUnmovable(u, q)) u];
        if (options.isEmpty) return;
        final u = ask(Decision(kind: DecisionKind.cards, player: q, prompt: 'Move one of your units to ${nameOf(bfObj)}', options: options, min: 1, max: 1, source: ctx.source)).first;
        _moveUnits([u], bf, q);
      case S1GoldForAll():
        if (askYesNo(p, '${nameOf(ctx.source)}: play a Gold gear token exhausted?', source: ctx.source)) _genTokens(p, 'Gold', 1, base);
        // Each other player, in turn order.
        for (final q in [for (var i = 1; i < state.players.length; i++) if (state.inGame((p + i) % state.players.length)) (p + i) % state.players.length]) {
          if (askYesNo(q, '${nameOf(ctx.source)}: play a Gold gear token exhausted? (${playerName(p)} then plays another)', source: ctx.source)) {
            _genTokens(q, 'Gold', 1, base);
            _genTokens(p, 'Gold', 1, base);
          }
        }
      case S1ChannelElseDraw(:final n, :final draw):
        final before = pl.runes.length;
        _channel(p, n, exhausted: true);
        if (pl.runes.length - before < n) _draw(p, draw);
      case S1RaiseMight(:final first, :final second):
        final a = _s1Slot(ctx, first.slot), b = _s1Slot(ctx, second.slot);
        if (!_s1OnBoard(a) || !_s1OnBoard(b) || a == b || !isUnit(a) || !isUnit(b)) return;
        if (state.obj(a).controller != p || state.obj(b).controller != p) return;
        final up = might(b) - might(a);
        if (up <= 0) return;
        state.obj(a).mightMod += up;
        log('${nameOf(a)}’s Might rises to ${might(a)} this turn.', player: p, card: a, kind: 'buff');
      case S1StrikeThere(:final pick, :final n, :final others):
        final u = _s1Slot(ctx, pick.slot), bf = _s1Slot(ctx, pick.slot + 1);
        if (bf < 0 || bf >= state.bfs.length) return;
        if (_s1OnBoard(u) && isUnit(u) && !state.allied(state.obj(u).controller, p) && state.obj(u).loc == bf) _hDeal(u, n, ctx);
        for (final x in enemyUnits(p, bf: bf)) {
          if (x != u) _hDeal(x, others, ctx);
        }
      case S1Grenade(:final pick, :final n):
        final u = _s1Slot(ctx, pick.slot);
        final src = ctx.source;
        // "This deals 1 additional Bonus Damage for each time this spell has dealt damage this
        // turn" — only for the copy played again (CR 712).
        final again = state.marks.remove('s1:grenadeAgain:$src') != null;
        if (!_s1OnBoard(u) || !isUnit(u)) return;
        final ctl = state.obj(u).controller;
        final was = ctx.scratch['bonus'] ?? 0;
        if (again) ctx.scratch['bonus'] = was + _gen.get('o$src:s1dealt');
        final hp = state.obj(u).damage;
        _hDeal(u, n, ctx);
        ctx.scratch['bonus'] = was;
        if (state.objOrNull(u)?.zone != Zone.board || state.obj(u).damage > hp) _gen.add('o$src:s1dealt');
        // Its controller may play it again once it has finished (game/w2s1.dart, _s1AfterSpell).
        state.marks['s1:grenadeOffer:$src'] = ctl + 1;
      case S1RevealPlayUnit():
        final revealed = <ObjId>[];
        ObjId? unit;
        while (pl.deck.isNotEmpty) {
          final id = pl.deck.removeAt(0);
          revealed.add(id);
          _xRevealed(id);
          if (card(id).type == CardType.unit) {
            unit = id;
            break;
          }
        }
        log('${pl.name} reveals ${revealed.isEmpty ? 'nothing' : revealed.map(nameOf).join(', ')}.', player: p, kind: 'info');
        if (unit != null) {
          final via = XPlay(effect: true, ignoreAll: true, elsewhere: true);
          if (_xCanPlayNow(p, unit, via)) {
            revealed.remove(unit);
            _xPlayAsEffect(p, unit, via);
          }
        }
        // The rest are recycled (CR 417.5: in random order).
        _recycleCards(p, revealed);
      case S1KillToGive(:final victim, :final receiver):
        final a = _s1Slot(ctx, victim.slot), b = _s1Slot(ctx, receiver.slot);
        if (!_s1OnBoard(a) || !isUnit(a) || state.obj(a).controller != p) return;
        final lk = mightUsed(a);
        log('${nameOf(a)} is killed.', player: p, card: a, kind: 'die');
        _kill(a);
        if (a != b && _s1OnBoard(b) && isUnit(b) && state.obj(b).controller == p && lk > 0) {
          state.obj(b).mightMod += lk;
          log('${nameOf(b)} gets +$lk Might this turn.', player: p, card: b, kind: 'buff');
        }
      case S1GiveMightPicked(:final pick, :final n):
        final u = _s1Slot(ctx, pick.slot);
        if (!_s1OnBoard(u) || !isUnit(u) || state.obj(u).controller != p) return;
        state.obj(u).mightMod += n;
        log('${nameOf(u)} gets +$n Might this turn.', player: p, card: u, kind: 'buff');
      case S1RevealDrawSpell():
        if (pl.deck.isEmpty) return;
        final top = pl.deck.first;
        _xRevealed(top);
        log('${pl.name} reveals ${nameOf(top)}.', player: p, card: top, kind: 'info');
        if (card(top).type == CardType.spell) _draw(p, 1);
      case S1Judgment(:final n):
        for (var i = 0; i < state.players.length; i++) {
          _s1Judge((p + i) % state.players.length, n, ctx.source);
        }
      case S1DoubleAndGrant(:final pick, :final ability):
        final u = _s1Slot(ctx, pick.slot);
        if (!_s1OnBoard(u) || !isUnit(u)) return;
        state.obj(u).mightMod += might(u);
        final key = _eqCardKey(ctx.source);
        final i = RiftboundParser.parse(db[key]!).extra.indexOf(ability);
        if (i >= 0) _gen.turn['o$u:s1grant:${1000 + i}:$key'] = 1;
        log('${nameOf(u)}’s Might is doubled and it has “${ability.text}” this turn.', player: p, card: u, kind: 'buff');
      case S1OpponentScores(:final n):
        _genGainPoints(state.multi ? chooseOpponent(p, '${nameOf(ctx.source)}: which opponent scores?') : state.other(p), n);
      case S1RecycleMeTo(:final effects):
        final o = state.objOrNull(ctx.source);
        if (o == null || o.zone != Zone.trash || !state.player(o.owner).trash.contains(o.id)) return;
        _recycleCards(o.owner, [o.id]);
        log('${nameOf(o.id)} is recycled.', player: p, card: o.id, kind: 'info');
        _resolveEffects(effects, ctx);
      case S1ReadyRunes():
        for (final r in pl.runes) {
          state.obj(r).exhausted = false;
        }
        log('${pl.name} readies their runes.', player: p, kind: 'info');
      case S1DealPerLocation(:final pick, :final n):
        for (var i = 0; i < pick.n; i++) {
          final u = _s1Slot(ctx, pick.slot + i);
          if (_s1OnBoard(u) && isUnit(u) && !state.allied(state.obj(u).controller, p)) _hDeal(u, n, ctx);
        }
      case S1PayReturnForToken(:final energy, :final token):
        final bf = ctx.loc;
        if (bf < 0 || bf >= state.bfs.length) return;
        final here = unitsAt(bf, player: p);
        if (here.isEmpty || !canPay(p, energy, const [])) return;
        if (!askYesNo(p, '${nameOf(ctx.source)}: pay {$energy} and return a unit here to its owner’s hand to play a $token here?', source: ctx.source)) return;
        final u = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose a unit to return to its owner’s hand', options: here, min: 1, max: 1, source: ctx.source)).first;
        _pay(p, energy, const []);
        _genSpent(p, energy);
        log('${nameOf(u)} returns to its owner’s hand.', player: p, card: u, kind: 'move');
        _leaveBoard(u, toHand: true);
        _genTokens(p, token, 1, bf);
      case S1BanishHandAndTrash():
        final cards = [...pl.hand, ...pl.trash];
        pl.hand.clear();
        pl.trash.clear();
        for (final id in cards) {
          state.obj(id).zone = Zone.banish;
          pl.banish.add(id);
        }
        log('${pl.name} banishes their hand and trash (${cards.length} cards).', player: p, kind: 'info');
      case S1NameSpell():
        final names = _s1SpellNames();
        if (names.isEmpty) return;
        // Spells the opponent has shown first (their trash, newest first), then all by name.
        final shown = <int>[];
        for (final q in state.opponents(p)) {
          for (final id in state.player(q).trash.reversed) {
            final k = names.indexOf(card(id).name);
            if (k >= 0 && !shown.contains(k)) shown.add(k);
          }
        }
        final order = [...shown, for (var k = 0; k < names.length; k++) if (!shown.contains(k)) k];
        final a = ask(Decision(kind: DecisionKind.option, player: p, prompt: '${nameOf(ctx.source)}: name a spell', labels: [for (final k in order) names[k]], source: ctx.source)).first;
        _gen.setL('o${ctx.source}:s1named', order[a] + 1);
        log('${pl.name} names ${names[order[a]]}.', player: p, card: ctx.source, kind: 'info');
      case S1DoubleThisCombat():
        final src = ctx.source;
        if (!_s1OnBoard(src) || !isUnit(src)) return;
        final d = mightUsed(src);
        if (d <= 0) return;
        state.obj(src).mightMod += d;
        _gen.add('o$src:s1combatMight', d);
        log('${nameOf(src)}’s Might is doubled this combat.', player: p, card: src, kind: 'buff');
    }
  }

  /// Divine Judgment for player [q]: keep [n] units, gear, runes and hand cards; recycle the rest.
  void _s1Judge(int q, int n, ObjId source) {
    final pl = state.player(q);
    List<ObjId> keep(List<ObjId> all, String what) {
      if (all.length <= n) return all;
      return ask(Decision(kind: DecisionKind.cards, player: q, prompt: 'Choose $n $what to keep', options: all, min: n, max: n, source: source));
    }

    final us = [for (final o in _boardOf(q)) if (card(o.id).type == CardType.unit) o.id];
    final gs = [for (final o in _boardOf(q)) if (card(o.id).type == CardType.gear) o.id];
    final keptUnits = keep(us, 'units');
    final keptGear = keep(gs, 'gear');
    final keptRunes = keep(List.of(pl.runes), 'runes');
    final keptHand = keep(List.of(pl.hand), 'cards in hand');
    final board = [for (final id in [...us, ...gs]) if (!keptUnits.contains(id) && !keptGear.contains(id)) id];
    for (final id in board) {
      _s1RecycleFromBoard(id);
    }
    for (final r in List.of(pl.runes)) {
      if (!keptRunes.contains(r)) _genRecycleRune(q, r);
    }
    _recycleCards(q, [for (final id in pl.hand) if (!keptHand.contains(id)) id]);
    log('${pl.name} keeps ${keptUnits.length} units, ${keptGear.length} gear, ${keptRunes.length} runes and ${keptHand.length} cards; the rest are recycled.', player: q, kind: 'info');
  }

  /// Recycles a permanent from the board to the bottom of its owner's Main Deck (CR 417).
  void _s1RecycleFromBoard(ObjId id) {
    final o = state.obj(id);
    _eqLeaving(id);
    _genLeaving(id);
    _gen.forget(id);
    if (card(id).token || _hIsCopy(id)) {
      o
        ..reset()
        ..zone = Zone.gone;
      return;
    }
    _recycleCards(o.owner, [id]);
  }

  /// Every spell's name, sorted (the cards that can be named, CR 762).
  List<String> _s1SpellNames() {
    final out = <String>{for (final c in db.cards) if (c.type == CardType.spell) c.name}.toList();
    out.sortStable((a, b) => a.compareTo(b));
    return out;
  }

  bool _s1Cond(S1Cond c, _Ctx ctx) {
    switch (c) {
      case S1ChoseEnemyTwice():
        return _gen.get('p${ctx.controller}:s1choseEnemy') >= 2;
      case S1OneOnOne():
        // CR 740.2.b: it and the enemy unit at its location are both alone.
        final src = ctx.source;
        if (!_s1OnBoard(src) || !isUnit(src)) return false;
        final o = state.obj(src);
        return o.loc != base && unitsAt(o.loc, player: o.controller).length == 1 && enemyUnits(o.controller, bf: o.loc).length == 1;
    }
    return false;
  }

  /// Ancient Henge: "Pay any amount of Energy to [Add] that much {A}."
  void _s1EnergyToPower(_Ctx ctx) {
    final p = ctx.controller;
    var max = 0;
    while (max < 30 && canPay(p, max + 1, const [])) {
      max++;
    }
    if (max == 0) return;
    final x = ask(Decision(kind: DecisionKind.option, player: p, prompt: '${nameOf(ctx.source)}: pay how much Energy for that much {A}?', labels: [for (var i = 0; i <= max; i++) '$i'], source: ctx.source)).first;
    if (x <= 0) return;
    _pay(p, x, const []);
    _genSpent(p, x);
    state.player(p).anyPool += x;
    log('${playerName(p)} turns $x Energy into $x Power.', player: p, card: ctx.source, kind: 'ability');
  }

  // -------------------------------------------------------------------------------------------
  // Passives
  // -------------------------------------------------------------------------------------------

  Iterable<(ObjId, S1Passive)> _s1Passives() sync* {
    for (final (src, pa) in _passives()) {
      if (pa is S1Passive) yield (src, pa);
    }
  }

  bool _s1Has(ObjId id, bool Function(S1Passive) test) => parsed(id).abilities.any((a) => a is Static && a.passive is S1Passive && test(a.passive as S1Passive));

  /// Altar of Blood (a replacement, CR 369): a unit at it that would die during combat may be
  /// healed, exhausted and recalled instead for its controller's {A}{A}{A}. True if it was.
  bool _s1ReplaceDeath(ObjId id) {
    final o = state.obj(id);
    if (o.zone != Zone.board || card(id).type != CardType.unit || o.loc == base || o.loc >= state.bfs.length) return false;
    final sd = state.showdown;
    if (sd == null || !sd.combat || sd.bf != o.loc) return false;
    final bf = state.bfs[o.loc].obj;
    for (final a in parsed(bf).abilities) {
      if (a is! Static || a.passive is! S1CombatSave) continue;
      final cost = List<Domain?>.filled((a.passive as S1CombatSave).power, null);
      final p = o.controller;
      if (!canPay(p, 0, cost)) return false;
      if (!askYesNo(p, '${nameOf(bf)}: pay ${'{A}' * cost.length} to heal, exhaust and recall ${nameOf(id)} instead of it dying?', source: bf)) return false;
      _pay(p, 0, cost);
      _genSpent(p, cost.length, power: cost.length);
      o
        ..damage = 0
        ..exhausted = true
        ..loc = base;
      log('${nameOf(id)} is healed, exhausted and recalled instead of dying.', player: p, card: id, kind: 'move');
      return true;
    }
    return false;
  }

  /// Bandle Tree: a second facedown card may be hidden at battlefield [bf].
  bool _s1ExtraHide(int bf) {
    if (bf < 0 || bf >= state.bfs.length || !_s1Has(state.bfs[bf].obj, (x) => x is S1ExtraHide)) return false;
    return state.objects.values.where((o) => o.zone == Zone.facedown && o.loc == bf).length < 2;
  }

  /// Baron Nashor being played: adds the Baron Pit if it isn't on the board and returns where it
  /// enters; null to play as usual.
  int? _s1PlayAt(int p, ObjId id) {
    if (card(id).type != CardType.unit || !_s1Has(id, (x) => x is S1BaronPit)) return null;
    for (var i = 0; i < state.bfs.length; i++) {
      if (card(state.bfs[i].obj).name == 'Baron Pit') return null;
    }
    final b = _newObj('Baron Pit', p, Zone.battlefield);
    state.obj(b).loc = state.bfs.length;
    state.bfs.add(Bf(b));
    log('${playerName(p)} adds the Baron Pit to the board.', player: p, card: b, kind: 'play');
    return state.obj(b).loc;
  }

  /// The Baron Pit: "Units can move here from anywhere."
  List<int> _s1MoveDests(ObjId u, List<int> dests) {
    final o = state.obj(u);
    final out = List.of(dests);
    for (var i = 0; i < state.bfs.length; i++) {
      if (i != o.loc && !out.contains(i) && _s1Has(state.bfs[i].obj, (x) => x is S1MoveHereFromAnywhere)) out.add(i);
    }
    return out;
  }

  bool _s1PlayerHas(int p, bool Function(S1Passive) test) => _s1Passives().any((x) => state.obj(x.$1).controller == p && state.obj(x.$1).zone == Zone.board && test(x.$2));

  /// Endless Riches: "Skip your Draw Phase."
  bool _s1SkipDraw(int p) => _s1PlayerHas(p, (x) => x is S1SkipDraw);

  /// Endless Riches: "You may play cards from your trash."
  bool _s1PlayFromTrash(int p) => _s1PlayerHas(p, (x) => x is S1PlayFromTrash);

  /// Fallen Feline: an opponent's unit at a battlefield naming [id]'s name stops it being played.
  String? _s1PlayProblem(int p, ObjId id) {
    if (card(id).type != CardType.spell) return null;
    final names = _s1SpellNames();
    for (final (src, pa) in _s1Passives()) {
      if (pa is! S1NamedSpellBan) continue;
      final o = state.obj(src);
      if (o.controller == p || o.zone != Zone.board || o.loc == base) continue;
      final k = _gen.getL('o$src:s1named') - 1;
      if (k >= 0 && k < names.length && names[k] == card(id).name) return '${nameOf(src)} stops spells named ${names[k]}';
    }
    return null;
  }

  /// Endless Riches (a replacement, CR 369): cards that went to its controller's trash from
  /// anywhere other than their Main Deck since the last cleanup are banished instead.
  void _s1Cleanup() {
    for (var q = 0; q < state.players.length; q++) {
      final pl = state.player(q);
      final active = _s1PlayerHas(q, (x) => x is S1TrashIsBanish);
      for (final id in List.of(pl.trash)) {
        final o = state.obj(id);
        final from = o.trashFrom;
        o.trashFrom = null;
        if (!active || from == null || from == Zone.mainDeck) continue;
        pl.trash.remove(id);
        o.zone = Zone.banish;
        o.trashFrom = null;
        pl.banish.add(id);
        log('${nameOf(id)} is banished instead of going to the trash.', player: q, card: id, kind: 'info');
      }
    }
  }

  // -------------------------------------------------------------------------------------------
  // Resource abilities
  // -------------------------------------------------------------------------------------------

  /// May this resource ability help pay now? (Ancient Henge's amount is chosen; Diana's Energy is
  /// for showdowns only.)
  bool _s1AddOk(AddRes add) => add is! S1EnergyToPower && (add is! S1ShowdownEnergy || state.showdown != null);

  String? _s1ActivateProblem(Activated a) {
    if (a.effects.any((e) => e is S1ShowdownEnergy) && state.showdown == null) return 'Only during showdowns';
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Triggers and events
  // -------------------------------------------------------------------------------------------

  /// A trigger's extra test as it triggers: "the first time … each turn", "in combat".
  bool _s1TriggerOk(ObjId src, int index, String key) {
    if (index < 0) return true;
    final a = _eqAbilityAt(db[key]!, index);
    if (a is! Triggered || a.on is! S1When) return true;
    final w = a.on as S1When;
    switch (w.ev) {
      case S1Ev.firstEachTurn:
        final k = 'o$src:s1first:$index';
        if (_gen.get(k) > 0) return false;
        _gen.add(k);
        return true;
      case S1Ev.dieInCombat:
        final sd = state.showdown;
        final o = state.obj(src);
        return sd != null && sd.combat && sd.bf == o.loc;
      case S1Ev.showdownHere || S1Ev.bfStartOfTurn:
        return true;
    }
  }

  /// The general events this slice listens to (called from _genEvent).
  void _s1Event(GEv ev, {required int player, int loc = -2}) {
    switch (ev) {
      case GEv.showdownHere || GEv.combatHere:
        // "When a showdown begins here": combat showdowns too (CR 316.8.a).
        for (final o in state.objects.values.toList()) {
          if (o.zone != Zone.board || o.loc != loc || loc < 0) continue;
          _s1QueueAll(o.id, S1Ev.showdownHere, o.controller, loc: loc);
        }
      case GEv.startOfEachTurn:
        for (var i = 0; i < state.bfs.length; i++) {
          if (state.bfs[i].controller == player) _s1QueueAll(state.bfs[i].obj, S1Ev.bfStartOfTurn, player, loc: i);
        }
      default:
        break;
    }
  }

  void _s1QueueAll(ObjId src, S1Ev ev, int controller, {required int loc}) {
    final abs = parsed(src).abilities;
    for (var i = 0; i < abs.length; i++) {
      final a = abs[i];
      if (a is Triggered && a.on is S1When && (a.on as S1When).ev == ev) _queue(src, i, controller, loc: loc);
    }
  }

  /// Ashe, Focused: when a player holds, their cards banished "until they hold" return to hand.
  void _s1Scored(int p, int bf, bool conquer) {
    if (conquer) return;
    final keys = state.marks.keys.where((k) => k.startsWith('s1:untilHold:')).toList()..sortStable((a, b) => a.compareTo(b));
    for (final k in keys) {
      final id = int.parse(k.substring('s1:untilHold:'.length));
      final o = state.objOrNull(id);
      if (o == null || o.owner != p) continue;
      state.marks.remove(k);
      final pl = state.player(p);
      if (o.zone != Zone.banish || !pl.banish.contains(id)) continue;
      pl.banish.remove(id);
      o
        ..zone = Zone.hand
        ..banishedBy = -1;
      pl.hand.add(id);
      log('${nameOf(id)} returns to ${pl.name}’s hand.', player: p, card: id, kind: 'move');
    }
  }

  /// Fiora: "double my Might this combat" ends with the combat.
  void _s1CombatEnded(List<ObjId> inCombat) {
    for (final u in inCombat) {
      final k = 'o$u:s1combatMight';
      final d = _gen.get(k);
      if (d == 0) continue;
      _gen.turn.remove(k);
      if (state.objOrNull(u)?.zone == Zone.board) state.obj(u).mightMod -= d;
    }
  }

  /// Dancing Grenade, once it has finished: its target's controller may play it again for {A}.
  void _s1AfterSpell(ChainItem item) {
    final src = item.source;
    final offer = state.marks.remove('s1:grenadeOffer:$src');
    if (offer == null) return;
    final q = offer - 1;
    final o = state.objOrNull(src);
    if (o == null || o.zone != Zone.trash || !state.player(o.owner).trash.contains(src)) return;
    final via = XPlay(effect: true, forCost: (0, const [null]), elsewhere: true);
    if (!_xCanPlayNow(q, src, via)) return;
    if (!askYesNo(q, 'Play ${nameOf(src)} again for {A}?', source: src)) return;
    state.marks['s1:grenadeAgain:$src'] = 1;
    _xPlayAsEffect(q, src, via);
  }

  /// Abilities a unit has this turn from Dominus ("give it "{A}{A}: Ready me.""), as
  /// (card, index, ability, unit) like attached cards' ([_eqAppended]).
  List<(String, int, Ability, ObjId)> _s1Granted(ObjId unit) {
    final pre = 'o$unit:s1grant:';
    final keys = _gen.turn.keys.where((k) => k.startsWith(pre)).toList()..sortStable((a, b) => a.compareTo(b));
    final out = <(String, int, Ability, ObjId)>[];
    for (final k in keys) {
      final rest = k.substring(pre.length);
      final colon = rest.indexOf(':');
      final index = int.parse(rest.substring(0, colon));
      final key = rest.substring(colon + 1);
      final c = db[key];
      if (c == null) continue;
      out.add((key, index, _eqAbilityAt(c, index), unit));
    }
    return out;
  }
}
