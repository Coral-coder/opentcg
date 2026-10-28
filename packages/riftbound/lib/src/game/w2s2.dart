part of 'game.dart';

/// [ActivateMove.index] of the {E} abilities Heimerdinger, Inventor has from other cards
/// (5000 + k, k into [GameWs2._ws2Borrowed]).
const ws2BorrowBase = 5000;

/// Wave 2, slice 2 (ir_w2s2.dart): one-off effects, conditions and passives, and the hooks the
/// core calls for them.
extension GameWs2 on Game {
  // -------------------------------------------------------------------------------------------
  // Choices as a spell or ability is played (CR 355)
  // -------------------------------------------------------------------------------------------

  /// Makes [e]'s choices; false if it has none of its own (the general walk then does them).
  bool _ws2Choose(GenEffect e, int p, ObjId source, void Function(int, int) set, {required bool optional}) {
    if (e is! Ws2StealSpell) return false;
    // "Gain control of a spell": any spell on the chain but this one (CR 750).
    final items = [
      for (final it in state.chain)
        if (it.isSpell && it.source != source && it.controller != p) it,
      for (final it in state.chain)
        if (it.isSpell && it.source != source && it.controller == p) it,
    ];
    if (items.isEmpty) {
      if (optional) {
        set(e.slot, -1);
        return true;
      }
      throw RiftboundError('No spell to take control of');
    }
    final a = ask(Decision(kind: DecisionKind.option, player: p, prompt: '${nameOf(source)}: gain control of which spell?', labels: [for (final it in items) db[it.card]!.name], source: source));
    set(e.slot, _chainRef + items[a.first].id);
    return true;
  }

  // -------------------------------------------------------------------------------------------
  // Effects
  // -------------------------------------------------------------------------------------------

  void _ws2Resolve(Ws2Effect e, _Ctx ctx) {
    final p = ctx.controller;
    final pl = state.player(p);
    switch (e) {
      case Ws2WinGame():
        log('${pl.name} meets ${nameOf(ctx.source)}’s condition.', player: p, card: ctx.source, kind: 'info');
        _win(p);
      case Ws2ReturnChampion(:final may):
        // The Chosen Champion (CR 103.3.a, 108.3), back to an empty Champion Zone.
        final id = state.marks['champ:$p'];
        if (id == null || pl.champion != null || !pl.trash.contains(id)) return;
        if (may && !askYesNo(p, '${nameOf(ctx.source)}: return ${nameOf(id)} to your Champion Zone?', source: ctx.source)) return;
        pl.trash.remove(id);
        state.obj(id)
          ..reset()
          ..zone = Zone.champion;
        pl.champion = id;
        log('${nameOf(id)} returns to ${pl.name}’s Champion Zone.', player: p, card: id, kind: 'move');
      case Ws2GiveKwCombat(:final kw, :final n, :final target):
        for (final id in _resolveTarget(target, ctx)) {
          if (!isUnit(id)) continue;
          _gen.turn['ws2ck:$id:${kw.index}'] = (_gen.get('ws2ckc:$id:${kw.index}') == _ws2CombatNow() ? _gen.get('ws2ck:$id:${kw.index}') : 0) + n;
          _gen.turn['ws2ckc:$id:${kw.index}'] = _ws2CombatNow();
          log('${nameOf(id)} gains ${kwLabel(kw)}${n > 1 ? ' $n' : ''} this combat.', player: p, card: id, kind: 'buff');
        }
      case Ws2GiveMyKeywords(:final target):
        final me = ctx.source;
        final onBoard = state.objOrNull(me)?.zone == Zone.board;
        final m = onBoard ? mightUsed(me) : _genLkMight(me);
        final kws = <(Kw, int)>[
          for (final k in Kw.values)
            if (!const {Kw.action, Kw.reaction, Kw.hidden, Kw.ambush, Kw.unique, Kw.accelerate}.contains(k))
              if ((onBoard ? _kw(me, k) : parsed(me).kw(k)) case final n when n > 0) (k, n),
        ];
        for (final id in _resolveTarget(target, ctx)) {
          if (!isUnit(id)) continue;
          final o = state.obj(id);
          o.mightMod += m < 0 ? 0 : m;
          for (final (k, n) in kws) {
            o.kwMod[k.index] = (o.kwMod[k.index] ?? 0) + n;
          }
          log('${nameOf(id)} gets ${nameOf(me)}’s keywords and +$m Might this turn.', player: p, card: id, kind: 'buff');
        }
      case Ws2Hwei():
        _draw(p, 1);
        if (pl.hand.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Discard 1', options: List.of(pl.hand), source: ctx.source));
        final d = pick.first;
        pl.hand.remove(d);
        state.obj(d).zone = Zone.trash;
        pl.trash.add(d);
        log('${pl.name} discards ${nameOf(d)}.', player: p, card: d, kind: 'discard');
        _genDiscarded(p, pick);
        switch (card(d).type) {
          case CardType.spell:
            _draw(p, 1);
          case CardType.gear:
            _resolve(const ReadyRunes(2), ctx);
          case CardType.unit:
            _resolve(const GiveMight(3, Me()), ctx);
          default:
            break;
        }
      case Ws2BurnBoost(:final n):
        // Burn (CR 441), and for each unit burned the reflexive "do this" (CR 388.4).
        for (var i = 0; i < n; i++) {
          if (pl.deck.isEmpty) {
            _burnOut(p);
            if (state.over || pl.deck.isEmpty) return;
          }
          final id = pl.deck.removeAt(0);
          state.obj(id).zone = Zone.trash;
          pl.trash.add(id);
          log('${pl.name} burns ${nameOf(id)}.', player: p, card: id, kind: 'info');
          if (card(id).type != CardType.unit) continue;
          final options = units(player: p);
          if (options.isEmpty) continue;
          final m = card(id).might ?? 0;
          final u = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: choose a friendly unit to give +$m Might', options: options, source: ctx.source)).first;
          state.obj(u).mightMod += m;
          log('${nameOf(u)} gets +$m Might this turn.', player: p, card: u, kind: 'buff');
        }
      case Ws2MoveToPaidLoc(:final target):
        final paid = state.marks['t:ws2paid:${ctx.source}'];
        if (paid == null || state.objOrNull(paid)?.zone != Zone.board) return;
        final to = state.obj(paid).loc;
        for (final id in _resolveTarget(target, ctx)) {
          if (!isUnit(id) || id == paid || state.obj(id).loc == to || _eqUnmovable(id, p)) continue;
          _moveUnits([id], to, p);
        }
      case Ws2PlayUnitReduced(:final n, :final may):
        // Played from facedown, its choices are made at that battlefield (CR 811.1.d).
        final fd = state.marks['t:fd:${ctx.source}'];
        final bfs = [
          for (var i = 0; i < state.bfs.length; i++)
            if (state.bfs[i].controller == p && (fd == null || fd == i)) i,
        ];
        if (bfs.isEmpty) return;
        final ok = [
          for (final id in pl.hand)
            if (card(id).type == CardType.unit && parsed(id).supported && _genPlayProblem(p, id) == null && bfs.any((b) => _xCanPay(p, id, XPlay(effect: true, reduceEnergy: n, at: b)))) id,
        ];
        if (ok.isEmpty) return;
        final picked = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: play which unit for {$n} less?', options: ok, min: may ? 0 : 1, source: ctx.source));
        if (picked.isEmpty) return;
        final id = picked.first;
        final where = [for (final b in bfs) if (_xCanPay(p, id, XPlay(effect: true, reduceEnergy: n, at: b))) b];
        final b = where.length == 1 ? where.first : where[ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Play ${nameOf(id)} where?', labels: [for (final i in where) nameOf(state.bfs[i].obj)], source: ctx.source)).first];
        _playFromHand(p, id, via: XPlay(effect: true, reduceEnergy: n, at: b));
      case Ws2Reflection(:final of):
        final what = _resolveTarget(of, ctx).firstOrNull;
        _ws2PlayReflection(p, base, what, ctx.source);
      case Ws2Deceiver():
        final me = state.objOrNull(ctx.source);
        final bf = ctx.loc;
        if (me == null || me.exhausted || pl.hand.isEmpty || bf < 0 || bf >= state.bfs.length) return;
        if (!askYesNo(p, '${nameOf(ctx.source)}: discard 1 and exhaust it to play a Reflection at ${nameOf(state.bfs[bf].obj)}?', source: ctx.source)) return;
        final d = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Discard 1', options: List.of(pl.hand), source: ctx.source)).first;
        pl.hand.remove(d);
        state.obj(d).zone = Zone.trash;
        pl.trash.add(d);
        log('${pl.name} discards ${nameOf(d)}.', player: p, card: d, kind: 'discard');
        _genDiscarded(p, [d]);
        me.exhausted = true;
        final token = _ws2PlayReflection(p, bf, null, ctx.source);
        // "Another unit there" is chosen as it becomes a copy (after the token is played).
        final others = [for (final u in unitsAt(bf)) if (u != token) u];
        if (others.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: choose a unit for the Reflection to copy', options: others, source: ctx.source)).first;
        _ws2BecomeCopy(token, pick);
      case Ws2StealSpell(:final slot):
        final ref = slot < ctx.targets.length ? ctx.targets[slot] : -1;
        if (ref < _chainRef) return;
        final i = state.chain.indexWhere((it) => it.id == ref - _chainRef);
        if (i < 0) return;
        final it = state.chain[i];
        var targets = it.targets;
        // New choices (CR 750–755): all of them remade, or none if there are no legal ones.
        if (askYesNo(p, 'Make new choices for ${db[it.card]!.name}?', source: ctx.source)) {
          final effects = [for (final a in RiftboundParser.parse(db[it.card]!).abilities) if (a is SpellBody) ...a.effects];
          try {
            targets = _chooseTargets(effects, p, it.source, it.loc, repeats: it.repeats, restrictBf: state.marks['t:fd:${it.source}'] ?? -1);
          } on RiftboundError {
            targets = it.targets;
          }
        }
        state.chain[i] = ChainItem(id: it.id, source: it.source, card: it.card, ability: it.ability, controller: p, targets: targets, repeats: it.repeats, loc: it.loc, fromTrigger: it.fromTrigger, legion: it.legion, event: it.event, paid: it.paid, costRef: it.costRef, via: it.via);
        log('${pl.name} gains control of ${db[it.card]!.name}.', player: p, card: it.source, kind: 'info');
      case Ws2PartyFavors():
        for (var k = 1; k < state.players.length; k++) {
          final q = (p + k) % state.players.length;
          final cards = ask(Decision(kind: DecisionKind.option, player: q, prompt: '${nameOf(ctx.source)}: choose', labels: const ['Cards: you and they each draw 1', 'Runes: you and they each channel 1 rune exhausted'], source: ctx.source)).first == 0;
          log('${playerName(q)} chooses ${cards ? 'Cards' : 'Runes'}.', player: q, kind: 'info');
          if (cards) {
            _draw(p, 1);
            _draw(q, 1);
          } else {
            _channel(p, 1, exhausted: true);
            _channel(q, 1, exhausted: true);
          }
        }
      case Ws2KingsEdict():
        final chosen = <ObjId>[];
        for (var k = 1; k < state.players.length; k++) {
          final q = (p + k) % state.players.length;
          final options = [for (final u in units()) if (state.obj(u).controller != p && !chosen.contains(u)) u];
          if (options.isEmpty) continue;
          chosen.add(ask(Decision(kind: DecisionKind.cards, player: q, prompt: 'Kill a unit for ${nameOf(ctx.source)}: choose one ${pl.name} doesn’t control', options: options, source: ctx.source)).first);
        }
        for (final u in chosen) {
          if (!isUnit(u)) continue;
          log('${nameOf(u)} is killed.', player: p, card: u, kind: 'die');
          _genNoteHit(u, ctx);
          _kill(u);
        }
      case Ws2ReplaceWithBrush():
        final me = state.objOrNull(ctx.source);
        final bf = ctx.loc;
        if (me == null || me.exhausted || bf < 0 || bf >= state.bfs.length) return;
        if (!askYesNo(p, '${nameOf(ctx.source)}: exhaust it to replace ${nameOf(state.bfs[bf].obj)} with a Brush?', source: ctx.source)) return;
        me.exhausted = true;
        final old = state.bfs[bf];
        final token = _newObj('Brush', p, Zone.battlefield);
        state.obj(token).loc = bf;
        state.obj(old.obj).zone = Zone.gone;
        state.bfs[bf] = Bf(token)
          ..controller = old.controller
          ..contestedBy = old.contestedBy;
        _gen.setL('o$token:ws2was', old.obj);
        log('${nameOf(old.obj)} is replaced with a Brush.', player: p, kind: 'info');
      case Ws2RestoreBf():
        final was = _gen.getL('o${ctx.source}:ws2was');
        final bf = state.bfs.indexWhere((b) => b.obj == ctx.source);
        if (was <= 0 || bf < 0) return;
        final cur = state.bfs[bf];
        state.obj(was)
          ..zone = Zone.battlefield
          ..loc = bf;
        state.obj(ctx.source).zone = Zone.gone;
        state.bfs[bf] = Bf(was)
          ..controller = cur.controller
          ..contestedBy = cur.contestedBy;
        log('${nameOf(ctx.source)} is replaced with ${nameOf(was)}.', player: p, kind: 'info');
      case Ws2BanishMeToBanish():
        final me = ctx.source;
        final it = ctx.event;
        if (state.objOrNull(me)?.zone != Zone.board || it < 0 || state.objOrNull(it)?.zone != Zone.board) return;
        if (!askYesNo(p, 'Banish ${nameOf(me)} to banish ${nameOf(it)}?', source: me)) return;
        _eqLeaving(me);
        _banishPermanent(me, p);
        _eqLeaving(it);
        _banishPermanent(it, p);
      case Ws2Jhin():
        final spell = ctx.event;
        final o = state.objOrNull(spell);
        if (o != null && o.zone == Zone.trash && askYesNo(p, 'Banish ${nameOf(spell)} with ${nameOf(ctx.source)}?', source: ctx.source)) {
          state.player(o.owner).trash.remove(spell);
          o
            ..zone = Zone.banish
            ..banishedBy = ctx.source;
          state.player(o.owner).banish.add(spell);
          log('${nameOf(spell)} is banished with ${nameOf(ctx.source)}.', player: p, card: spell, kind: 'info');
        }
        final withMe = [for (final b in state.objects.values) if (b.zone == Zone.banish && b.banishedBy == ctx.source && card(b.id).type == CardType.spell) b.id];
        if (withMe.length < 4) return;
        for (final id in withMe) {
          final b = state.obj(id);
          state.player(b.owner).banish.remove(id);
          b
            ..zone = Zone.trash
            ..banishedBy = -1;
          state.player(b.owner).trash.add(id);
        }
        log('${nameOf(ctx.source)}: the four spells go to the trash.', player: p, card: ctx.source, kind: 'info');
        _channel(p, 4);
        _draw(p, 1);
      case Ws2LegionKillNow(:final target):
        // Legion (CR 812.1.c): another card of yours was finalized this turn.
        if (pl.playedThisTurn < 2) return;
        for (final id in _resolveTarget(target, ctx)) {
          _gen.delayed.removeWhere((d) => d.kind == DelayKind.killNextDamage.index && d.obj == id && d.source == ctx.source && d.turn == state.turn);
          log('${nameOf(id)} is killed.', player: p, card: id, kind: 'die');
          _genNoteHit(id, ctx);
          _kill(id);
        }
      default:
        break;
    }
  }

  /// Plays a ready Reflection token (CR 187.6) for [p] at [loc], a copy of [of] if given, with
  /// [Temporary]. Returns it.
  ObjId _ws2PlayReflection(int p, int loc, ObjId? of, ObjId source) {
    final id = _newObj('Reflection', p, Zone.board);
    _enterBoard(id, p, loc, ready: true);
    if (of != null) _ws2BecomeCopy(id, of);
    _gen.setL('o$id:kw${Kw.temporary.index}', 1);
    log('${playerName(p)} plays a Reflection${of == null ? '' : ' of ${nameOf(of)}'}.', player: p, card: id, kind: 'play');
    _genEvent(GEv.played, player: p, obj: id);
    return id;
  }

  /// A copy effect (CR 479.1): [id] takes [of]'s copyable traits — its printed traits, or what
  /// it's a copy of (CR 479.1.b.1).
  void _ws2BecomeCopy(ObjId id, ObjId of) {
    state.obj(id).eq.copyOf = _eqCardKey(of);
    // A token copy still ceases to exist off the board (CR 186.1).
    state.marks['copy:$id'] = 1;
  }

  /// Hextech Anomaly and the restricted [Add]s (CR 166).
  void _ws2ResolveAdd(AddRes e, _Ctx ctx) {
    final p = ctx.controller;
    final pl = state.player(p);
    switch (e) {
      case Ws2PowerToEnergy():
        var max = 0;
        while (max < 12 && canPay(p, 0, List<Domain?>.filled(max + 1, null))) {
          max++;
        }
        if (max == 0) return;
        final n = ask(Decision(kind: DecisionKind.option, player: p, prompt: '${nameOf(ctx.source)}: pay how much {A} for Energy?', labels: [for (var i = 0; i <= max; i++) '$i'], source: ctx.source)).first;
        if (n == 0) return;
        _pay(p, 0, List<Domain?>.filled(n, null));
        pl.energyPool += n;
        log('${pl.name} converts $n Power into Energy.', player: p, kind: 'info');
      case Ws2RestrictedAdd(:final gear, :final energy, :final anyPower):
        final k = gear ? 't:ws2pool:g:$p' : 't:ws2pool:s:$p';
        state.marks[k] = (state.marks[k] ?? 0) + (gear ? anyPower : energy);
      default:
        break;
    }
  }

  // -------------------------------------------------------------------------------------------
  // Conditions
  // -------------------------------------------------------------------------------------------

  bool _ws2Cond(Ws2Cond c, _Ctx ctx) {
    final p = ctx.controller;
    switch (c) {
      case Ws2ControlsFacedown():
        return state.objects.values.any((o) => o.zone == Zone.facedown && o.controller == p);
      case Ws2ExactHandUnits(:final hand, :final units):
        return state.player(p).hand.length == hand && [for (final u in this.units(player: p)) if (state.obj(u).loc != base) u].length == units;
      case Ws2TagsAmong(:final tags):
        final mine = units(player: p);
        return tags.every((t) => mine.any((u) => card(u).hasTag(t) || _eqHasTag(u, t)));
      case Ws2ControlsThisBf():
        final i = state.bfs.indexWhere((b) => b.obj == ctx.source);
        return i >= 0 && state.bfs[i].controller == p;
      case Ws2All(:final conds):
        return conds.every((x) => _cond(x, ctx));
      case Ws2FirstGear():
        return _gen.get('p$p:ws2gear') == 1;
      default:
        return false;
    }
  }

  // -------------------------------------------------------------------------------------------
  // Hooks from the core
  // -------------------------------------------------------------------------------------------

  /// [p] hid card [id] (CR 811): "When you hide a card".
  void _ws2Hid(int p, ObjId id) => _genEvent(GEv.ws2Hid, player: p, obj: id);

  /// A permanent was just played: "As you play me" choices (CR 355), and non-token gear counted.
  void _ws2AsPlayed(ObjId id) {
    final o = state.obj(id);
    final c = card(id);
    if (c.type == CardType.gear && !c.token) _gen.add('p${o.controller}:ws2gear');
    for (final a in parsed(id).abilities) {
      if (a is Static && a.passive is Ws2ChooseTag) {
        final tags = (a.passive as Ws2ChooseTag).tags;
        final i = ask(Decision(kind: DecisionKind.option, player: o.controller, prompt: '${c.name}: choose a tag for it to gain', labels: tags, source: id)).first;
        _gen.setL('o$id:ws2tag', i + 1);
        log('${c.name} gains the ${tags[i]} tag.', player: o.controller, card: id, kind: 'info');
      }
    }
  }

  /// A tag [id] gained as it was played (Ivern, Friend to All).
  bool _ws2HasTag(ObjId id, String tag) {
    final i = _gen.getL('o$id:ws2tag');
    if (i <= 0 || state.objOrNull(id)?.zone != Zone.board) return false;
    for (final a in parsed(id).abilities) {
      if (a is Static && a.passive is Ws2ChooseTag) {
        final tags = (a.passive as Ws2ChooseTag).tags;
        return i <= tags.length && tags[i - 1].toLowerCase() == tag.toLowerCase();
      }
    }
    return false;
  }

  bool _ws2Has(ObjId id, bool Function(Passive) test) => !_eqInactive(id) && parsed(id).abilities.any((a) => a is Static && test(a.passive));

  /// Kayn, Unleashed: "If I have moved twice this turn, I don't take damage."
  bool _ws2NoDamage(ObjId id) => state.objOrNull(id)?.zone == Zone.board && _gen.get('o$id:moves') >= 2 && _ws2Has(id, (x) => x is Ws2NoDamageMovedTwice);

  /// LeBlanc, Everywhere At Once: a Temporary unit of hers at her battlefield doesn't die.
  bool _ws2TemporarySuppressed(ObjId id) {
    final o = state.obj(id);
    if (o.loc == base) return false;
    for (final l in state.objects.values) {
      if (l.zone == Zone.board && l.controller == o.controller && l.loc == o.loc && _ws2Has(l.id, (x) => x is Ws2NoTemporaryHere)) return true;
    }
    return false;
  }

  /// Mageseeker Investigator: [p] pays {A} per unit beyond the first moved to its battlefield.
  void _ws2MoveTax(int p, List<ObjId> moving, int to) {
    if (to == base || moving.length < 2) return;
    var n = 0;
    for (final o in state.objects.values) {
      if (o.zone == Zone.board && o.loc == to && o.controller != p && isUnit(o.id) && _ws2Has(o.id, (x) => x is Ws2MoveTax)) n += moving.length - 1;
    }
    if (n == 0) return;
    final power = List<Domain?>.filled(n, null);
    if (!canPay(p, 0, power)) throw RiftboundError('Moving ${moving.length} units there together costs ${'{A}' * n}');
    _pay(p, 0, power);
    log('${playerName(p)} pays ${'{A}' * n} to move ${moving.length} units together.', player: p, kind: 'info');
  }

  /// Otterpus: [p] would gain a point from scoring in their first or second turn: they draw 1
  /// instead (a replacement, CR 367). True if replaced.
  bool _ws2ScoreDraws(int p) {
    if (state.active != p || _gen.getL('p$p:turns') > 2) return false;
    final any = state.objects.values.any((o) => o.zone == Zone.board && _ws2Has(o.id, (x) => x is Ws2EarlyScoreDraws));
    if (!any) return false;
    log('${playerName(p)} draws instead of scoring a point.', player: p, kind: 'info');
    _draw(p, 1);
    return true;
  }

  /// A combat starts (CR 466): "this combat" effects count from here.
  void _ws2CombatStart() => _gen.add('ws2combat');

  int _ws2CombatNow() => _gen.get('ws2combat');

  /// Keywords given "this combat".
  int _ws2Kw(ObjId id, Kw k) {
    final n = _gen.get('ws2ck:$id:${k.index}');
    return n > 0 && _gen.get('ws2ckc:$id:${k.index}') == _ws2CombatNow() ? n : 0;
  }

  // -------------------------------------------------------------------------------------------
  // Heimerdinger, Inventor: the {E} abilities of friendly legends, units and gear
  // -------------------------------------------------------------------------------------------

  /// Abilities [src] borrows: (card key, index, ability), by move index [ws2BorrowBase] + k.
  List<(String, int, Activated)> _ws2Borrowed(ObjId src) {
    final o = state.objOrNull(src);
    if (o == null || o.zone != Zone.board || !_ws2Has(src, (x) => x is Ws2BorrowExhaustAbilities)) return const [];
    final out = <(String, int, Activated)>[];
    final seen = <String>{};
    for (final s in [?state.player(o.controller).legend, for (final x in _boardOf(o.controller)) x.id]) {
      if (s == src || _eqInactive(s)) continue;
      final key = _eqCardKey(s);
      final abs = parsed(s).abilities;
      for (var i = 0; i < abs.length; i++) {
        final a = abs[i];
        if (a is! Activated || !a.cost.exhaust || a is EqEquip) continue;
        if (seen.add('$key#$i')) out.add((key, i, a));
      }
    }
    return out;
  }

  List<RMove> _ws2Candidates(int seat) => [
        for (final u in units(player: seat))
          for (var k = 0; k < _ws2Borrowed(u).length; k++) ActivateMove(seat, u, ws2BorrowBase + k),
      ];

  Ability? _ws2AbilityOfMove(ActivateMove m) {
    final list = _ws2Borrowed(m.source);
    final k = m.index - ws2BorrowBase;
    return k >= 0 && k < list.length ? list[k].$3 : null;
  }

  /// Activates a borrowed ability, as [GamePlay._activate] does a printed one (CR 376): "me" and
  /// its {E} are Heimerdinger's.
  void _ws2ActivateBorrowed(int p, ObjId src, int index) {
    final list = _ws2Borrowed(src);
    final k = index - ws2BorrowBase;
    if (k < 0 || k >= list.length) throw RiftboundError('No such ability');
    final (key, i, a) = list[k];
    final o = state.obj(src);
    if (a.legion && state.player(p).playedThisTurn < 1) throw RiftboundError('Legion: play another card this turn first');
    final isAdd = a.adds;
    final t = isAdd ? null : _timingProblem(p, a.timing);
    if (t != null) throw RiftboundError(t);
    if (isAdd && a.timing != Timing.reaction && _timingProblem(p, Timing.normal) != null) throw RiftboundError('Not now');
    if (a.oncePerTurn && o.usedThisTurn.contains(index)) throw RiftboundError('Only once per turn');
    if (a.cost.exhaust && o.exhausted) throw RiftboundError('${nameOf(src)} is exhausted');
    final problem = _powerActivateProblem(p, src, index, a) ?? _xCostProblem(p, src, a.cost) ?? _genActivateProblem(a, src, p);
    if (problem != null) throw RiftboundError(problem);
    final ac = _activationCost(p, src, a);
    final energy = _xAbilityEnergy(p, src, a, ac.energy);
    if (!canPay(p, energy, ac.power)) throw RiftboundError('Not enough runes (${a.cost.describe()})');
    final targets = _chooseTargets(a.effects, p, src, o.loc);
    final extraP = <Domain?>[];
    for (final tg in targets) {
      if (tg >= 0 && tg < _chainRef && state.objOrNull(tg)?.zone == Zone.board && state.obj(tg).controller != p && !_xIgnoreDeflect(src, tg)) {
        for (var d = 0; d < _kw(tg, Kw.deflect); d++) {
          extraP.add(null);
        }
      }
    }
    _pay(p, energy, [...ac.power, ...extraP]);
    _genSpent(p, energy + ac.power.length + extraP.length, power: ac.power.length + extraP.length);
    _powerPayExtra(p, src, a);
    _xPayCostExtra(p, src, a);
    _genPayExtra(a, src, p, targets);
    if (a.cost.exhaust) o.exhausted = true;
    o.usedThisTurn.add(index);
    final item = ChainItem(id: state.nextChainId++, source: src, card: key, ability: i, controller: p, targets: targets, loc: o.loc);
    if (a.cost.killMe) _kill(src);
    log('${playerName(p)} uses ${nameOf(src)} (${db[key]!.name}’s ability).', player: p, card: src, kind: 'ability');
    if (isAdd) {
      _resolveItem(item);
      return;
    }
    _pushChain(item);
    if (state.showdown?.focus == p) state.showdown!.focusChain = true;
  }

  // -------------------------------------------------------------------------------------------
  // Forgotten Signpost's cost: exhaust a unit you control (not the one it moves)
  // -------------------------------------------------------------------------------------------

  String? _ws2CostProblem(Activated a, ObjId src, int p) {
    if (!a.cost.extra.any((x) => x is Ws2ExhaustUnitCost)) return null;
    final mine = units(player: p);
    final ready = [for (final u in mine) if (!state.obj(u).exhausted) u];
    // A ready unit to exhaust, and a different unit to move.
    if (ready.isEmpty || mine.length < 2) return 'Nothing to exhaust';
    return null;
  }

  void _ws2PayExtra(Activated a, ObjId src, int p, List<int> targets) {
    if (!a.cost.extra.any((x) => x is Ws2ExhaustUnitCost)) return;
    final options = [for (final u in units(player: p)) if (!state.obj(u).exhausted && !targets.contains(u)) u];
    if (options.isEmpty) throw RiftboundError('Nothing to exhaust');
    final u = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Exhaust one to pay', options: options, source: src)).first;
    state.obj(u).exhausted = true;
    state.marks['t:ws2paid:$src'] = u;
  }

  // -------------------------------------------------------------------------------------------
  // Restricted Energy and Power in the Rune Pool (CR 166): Lux's and Ornn's
  // -------------------------------------------------------------------------------------------

  /// Restricted Energy and {A} [p] may spend on this payment.
  (int, int) _ws2Restricted(int p, {required bool forSpell, required bool forGear}) => (forSpell ? state.marks['t:ws2pool:s:$p'] ?? 0 : 0, forGear ? state.marks['t:ws2pool:g:$p'] ?? 0 : 0);

  /// After a payment that could use restricted resources: they're spent first; what's left of
  /// them stays restricted. Returns how much of the remaining pool ([leftE], [leftA]) is.
  (int, int) _ws2AfterPay(int p, List<(ObjId, int, AddRes)> adds, int leftE, int leftA, {required bool forSpell, required bool forGear}) {
    final (re, ra) = _ws2Restricted(p, forSpell: forSpell, forGear: forGear);
    if (re == 0 && ra == 0) return (0, 0);
    final pl = state.player(p);
    var addE = 0, addA = 0;
    for (final (_, _, x) in adds) {
      addE += x.energy;
      addA += x.anyPower;
    }
    final usedE = pl.energyPool + re + addE - leftE;
    final usedA = pl.anyPool + ra + addA - leftA;
    final keepE = re - usedE > 0 ? re - usedE : 0;
    final keepA = ra - usedA > 0 ? ra - usedA : 0;
    if (forSpell) state.marks['t:ws2pool:s:$p'] = keepE;
    if (forGear) state.marks['t:ws2pool:g:$p'] = keepA;
    return (keepE, keepA);
  }

  /// Rune Pools empty (CR 167).
  void _ws2EmptyPools() => state.marks.removeWhere((k, _) => k.startsWith('t:ws2pool:'));
}
