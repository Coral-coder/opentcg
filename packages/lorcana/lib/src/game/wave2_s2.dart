part of 'game.dart';

/// Wave 2, slice 2 (Gruesome And Grim … Mirabel Madrigal): resolving the IR of
/// ir_wave2_s2.dart. Per-card notes kept on [Obj.usedOn] use negative keys (ability indexes are
/// never negative), so they are part of the digest like everything else.
extension GameW2S2 on Game {
  /// The challenged card while challenge damage is dealt ("unless he's being challenged").
  static CardId? _challenged;

  /// Static-granted triggered abilities of a card as it last left play: (its zcc after, abilities).
  /// Set every time a card leaves play, read by the events that follow it.
  static final Map<CardId, (int, List<Triggered>)> _lkiGrants = {};

  static const _putUnderKey = -5, _challengedKey = -6, _hadUnderKey = -7, _wasUnderKey = -8, _wasUnderZccKey = -9, _firstDamageKey = -11;

  // -------------------------------------------------------------------------------------------
  // Effects
  // -------------------------------------------------------------------------------------------

  void _w2Resolve(W2Effect e, _Ctx ctx) {
    final s = state;
    final p = ctx.controller;
    switch (e) {
      case W2PlayFree(:final filter, :final from, :final slot, :final sameNameAsCost, :final bottomAfter):
        var cands = [
          for (final id in matching(filter, controller: p, source: ctx.source, place: from, whose: Owner.yours))
            if (id != ctx.source && _w2PlayBlock(p, id) == null) id,
        ];
        if (sameNameAsCost) {
          final names = {for (final id in ctx.slots[w2CostSlot] ?? const <CardId>[]) ...db[s.obj(id).card]!.names.map((n) => n.toLowerCase())};
          cands = [
            for (final id in cands)
              if (db[s.obj(id).card]!.names.any((n) => names.contains(n.toLowerCase()))) id,
          ];
        }
        if (cands.isEmpty) {
          ctx.didIt = false;
          return;
        }
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Play one for free', options: cands, min: 1, max: 1, source: ctx.source)).first;
        if (slot != null) ctx.slots[slot] = [pick];
        _w2PlayFreeCard(p, pick, bottomAfter: bottomAfter);
        ctx.didIt = true;
      case W2PlayThis(:final from, :final exerted):
        final o = s.objOrNull(ctx.source);
        ctx.didIt = o != null && o.zone == from && o.owner == p && _w2PlayPaying(p, ctx.source, exerted: exerted);
      case W2PlayRemembered(:final slot, :final filter):
        final ids = [
          for (final id in ctx.slots[slot] ?? const <CardId>[])
            if (s.obj(id).zone != Place.play && _w2CardIs(filter, id, p) && _w2PlayBlock(p, id) == null) id,
        ];
        if (ids.isEmpty) return;
        _w2PlayFreeCard(p, ids.first);
        ctx.didIt = true;
      case W2PlayTop():
        final deck = s.player(p).deck;
        if (deck.isEmpty) return;
        final top = deck.first;
        log('${s.player(p).name} reveals ${nameOf(top)}.', player: p, card: top);
        if (_w2PlayWays(p, top).isNotEmpty && askYesNo(p, 'Play ${nameOf(top)} as if it were in your hand?', source: ctx.source)) {
          _w2PlayPaying(p, top);
        } else {
          _moveTo(top, Place.discard);
        }
      case W2EachRevealPlay(:final filter):
        for (final q in _players(Who.each, ctx)) {
          final pl = s.player(q);
          s.rng.shuffle(pl.deck);
          s.version++;
          if (pl.deck.isEmpty) continue;
          final top = pl.deck.first;
          log('${pl.name} shuffles and reveals ${nameOf(top)}.', player: q, card: top);
          if (_w2CardIs(filter, top, q) && _w2PlayBlock(q, top) == null && askYesNo(q, 'Play ${nameOf(top)} for free?', source: ctx.source)) {
            _enterPlay(q, top, free: true);
          } else {
            pl.deck.remove(top);
            pl.deck.add(top);
            s.version++;
          }
        }
      case W2Choose(:final target):
        ctx.didIt = _resolveTargets(target, ctx).isNotEmpty;
      case W2UnlessTuck(:final slot, :final effect):
        final ids = [
          for (final id in ctx.slots[slot] ?? const <CardId>[])
            if (s.obj(id).zone == Place.play) id,
        ];
        if (ids.isNotEmpty) {
          final id = ids.first;
          final owner = s.obj(id).owner;
          if (askYesNo(owner, 'Put ${nameOf(id)} on the bottom of your deck? If you don’t, ${s.player(p).name} draws.', source: ctx.source)) {
            log('${s.player(owner).name} puts ${nameOf(id)} on the bottom of their deck.', player: owner, card: id, kind: 'return');
            _leavePlay(id, Place.deck, bottom: true);
            return;
          }
        }
        _resolveEffect(effect, ctx);
      case W2HandToInkwell(:final exerted):
        final hand = List.of(s.player(p).hand);
        for (final id in hand) {
          _moveTo(id, Place.inkwell, exerted: exerted);
        }
        if (hand.isNotEmpty) log('${s.player(p).name} puts ${hand.length} card${hand.length == 1 ? '' : 's'} from their hand into their inkwell.', player: p, kind: 'ink');
        ctx.didIt = true;
      case W2SearchDeck(:final filters, :final dest, :final reveal):
        final pl = s.player(p);
        final cands = [
          for (final id in pl.deck)
            if (filters.any((f) => _w2CardIs(f, id, p))) id,
        ];
        final pick = cands.isEmpty ? const <CardId>[] : ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Search your deck: choose a card', options: cands, min: 0, max: 1, source: ctx.source));
        if (pick.isNotEmpty && reveal) log('${pl.name} reveals ${nameOf(pick.first)}.', player: p, card: pick.first);
        if (pick.isNotEmpty && dest == ZoneDest.hand) _send(pick.first, ZoneDest.hand, p, ctx);
        if (pick.isNotEmpty) pl.deck.remove(pick.first);
        s.rng.shuffle(pl.deck);
        if (pick.isNotEmpty && dest == ZoneDest.top) pl.deck.insert(0, pick.first);
        s.version++;
        log('${pl.name} shuffles their deck.', player: p);
        ctx.didIt = pick.isNotEmpty;
      case W2HandToDeck(:final n, :final top):
        final pl = s.player(p);
        final k = n < pl.hand.length ? n : pl.hand.length;
        if (k == 0) return;
        final where = top ? 'top' : 'bottom';
        var pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose $k card${k == 1 ? '' : 's'} to put on the $where of your deck', options: List.of(pl.hand), min: k, max: k, source: ctx.source));
        if (pick.length > 1) pick = ask(Decision(kind: DecisionKind.order, player: p, prompt: 'Order them for the $where of your deck (first = ${top ? 'top' : 'highest'})', options: pick, source: ctx.source));
        for (final id in top ? pick.reversed : pick) {
          _moveTo(id, Place.deck, bottom: !top);
        }
        log('${pl.name} puts $k card${k == 1 ? '' : 's'} from their hand on the $where of their deck.', player: p);
      case W2RemoveTotal(:final filter, :final n):
        final removed = <CardId, int>{};
        var left = n;
        while (left > 0) {
          final cands = [
            for (final id in matching(filter, controller: p, source: ctx.source, whose: Owner.yours))
              if (s.obj(id).damage > 0) id,
          ];
          if (cands.isEmpty) break;
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Remove 1 damage ($left left): choose a character, or none to stop', options: cands, min: 0, max: 1, source: ctx.source));
          if (pick.isEmpty) break;
          s.obj(pick.first).damage--;
          removed[pick.first] = (removed[pick.first] ?? 0) + 1;
          left--;
        }
        for (final id in removed.keys) {
          final k = removed[id]!;
          _noteDamageRemoved(id, k);
          log('${nameOf(id)}: $k damage removed.', card: id, kind: 'heal', amount: k);
          _emit(_Ev(kind: _EvKind.damageRemoved, card: id, player: p, amount: k));
        }
        ctx.slots[w2RemovedSlot] = [n - left];
        s.version++;
      case W2OtherPlayerDraws(:final n):
        final others = [
          for (final q in s.opponents(p))
            if (!s.player(q).lost) q,
        ];
        if (others.isEmpty) return;
        final q = others.length == 1 ? others.first : others[ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Choose another player', labels: [for (final x in others) s.player(x).name], source: ctx.source)).first];
        for (var i = 0; i < n; i++) {
          _draw(q);
        }
      case W2ExertInkwell(:final who):
        for (final q in _players(who, ctx)) {
          for (final id in s.player(q).inkwell) {
            s.obj(id).exerted = true;
          }
          log('${s.player(q).name} exerts their inkwell.', player: q, kind: 'exert');
        }
        s.version++;
      case W2TrimInkwell(:final who, :final n):
        for (final q in _players(who, ctx)) {
          final pl = s.player(q);
          var k = 0;
          while (pl.inkwell.length > n) {
            _moveTo(pl.inkwell[s.rng.nextInt(pl.inkwell.length)], Place.hand);
            k++;
          }
          if (k > 0) log('${pl.name} returns $k card${k == 1 ? '' : 's'} from their inkwell to their hand.', player: q, kind: 'return');
        }
      case W2MillBranch(:final types, :final branches):
        final deck = s.player(p).deck;
        if (deck.isEmpty) return;
        final top = deck.first;
        _moveTo(top, Place.discard);
        log('${s.player(p).name} puts ${nameOf(top)} into their discard.', player: p, card: top);
        final type = db[s.obj(top).card]!.type;
        for (var i = 0; i < types.length; i++) {
          if (types[i].contains(type)) {
            _resolveEffect(branches[i], ctx);
            break;
          }
        }
      case W2DiscardTrack(:final discard):
        final hand = s.player(p).hand;
        ctx.slots[w2DiscardSlot] = const [];
        ctx.didIt = false;
        if (hand.isEmpty || _w2NoDiscard(p)) return;
        final n = _evalAmount(discard.amount, ctx).clamp(0, hand.length);
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose $n card${n == 1 ? '' : 's'} to discard', options: List.of(hand), min: n, max: n, source: ctx.source));
        _discardCards(p, pick);
        ctx.slots[w2DiscardSlot] = pick;
        ctx.didIt = pick.isNotEmpty;
      case W2Repeat(:final times, :final effect):
        final n = _evalAmount(times, ctx);
        for (var i = 0; i < n && !s.over; i++) {
          final before = ctx.slots.keys.toSet();
          _resolveEffect(effect, ctx);
          ctx.slots.removeWhere((k, _) => !before.contains(k));
        }
      case W2OpponentsCantPlay(:final filter):
        _w2AddTimed(ctx, null, Lasting.untilYourNextTurn, 'w2:cantPlay:${filter.types.map((t) => t.name).join(',')}');
      case W2GrantAbility(:final target, :final quote, :final duration):
        final ids = _resolveTargets(target, ctx);
        if (ids.isNotEmpty) _w2AddTimed(ctx, ids, duration, 'w2:grant|${nameOf(ctx.source)}|$quote');
      case W2GrantClass(:final target, :final classification, :final duration):
        final ids = _resolveTargets(target, ctx);
        if (ids.isNotEmpty) _w2AddTimed(ctx, ids, duration, 'w2:class:$classification');
      case W2LoseKeyword(:final target, :final kw, :final duration):
        final ids = _resolveTargets(target, ctx);
        if (ids.isNotEmpty) _w2AddTimed(ctx, ids, duration, 'w2:lose:${kw.name}');
      case W2ReadyLimit(:final n):
        for (final q in _players(Who.opponents, ctx)) {
          _w2AddTimed(ctx, null, Lasting.theirNextTurn, 'w2:readyLimit:$n:$q');
        }
      case W2PutTopUnder(:final target):
        final ids = _resolveTargets(target, ctx);
        final deck = s.player(p).deck;
        if (ids.isEmpty || deck.isEmpty) return;
        _w2PutUnder(p, deck.first, ids.first);
        ctx.didIt = true;
      case W2MoveFormerUnder(:final target):
        final src = s.objOrNull(ctx.source);
        if (src == null) return;
        final cards = [
          for (final pl in s.players)
            for (final id in pl.discard)
              if (s.obj(id).usedOn[_wasUnderKey] == ctx.source && s.obj(id).usedOn[_wasUnderZccKey] == src.zcc) id,
        ];
        if (cards.isEmpty) return;
        final hosts = _resolveTargets(target, ctx);
        if (hosts.isEmpty) return;
        for (final id in cards) {
          _w2PutUnder(p, id, hosts.first);
        }
        ctx.didIt = true;
      case W2DrawBottom():
        final pl = s.player(p);
        if (pl.deck.isEmpty) return;
        final id = pl.deck.last;
        pl.deck.remove(id);
        pl.deck.insert(0, id);
        _draw(p);
      case W2ShiftFromDiscard():
        _w2ShiftFromDiscard(p, ctx);
      case W2RevealInHand(:final filter):
        final cands = [
          for (final id in s.player(p).hand)
            if (_w2CardIs(filter, id, p)) id,
        ];
        ctx.didIt = false;
        if (cands.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Reveal a card from your hand', options: cands, min: 1, max: 1, source: ctx.source));
        log('${s.player(p).name} reveals ${nameOf(pick.first)}.', player: p, card: pick.first);
        ctx.didIt = true;
      case W2DiscardEither(:final who, :final n, :final alt):
        for (final q in _players(who, ctx)) {
          final hand = s.player(q).hand;
          if (hand.isEmpty || _w2NoDiscard(q)) continue;
          final alts = [
            for (final id in hand)
              if (_w2CardIs(alt, id, q)) id,
          ];
          final labels = ['Discard $n cards', if (alts.isNotEmpty) 'Discard 1 ${alt.describe()} card'];
          final i = labels.length == 1 ? 0 : ask(Decision(kind: DecisionKind.option, player: q, prompt: 'Discard either $n cards or 1 ${alt.describe()} card', labels: labels, source: ctx.source)).first;
          final opts = i == 0 ? List.of(hand) : alts;
          final k = i == 0 ? (n < hand.length ? n : hand.length) : 1;
          final pick = ask(Decision(kind: DecisionKind.cards, player: q, prompt: 'Choose $k card${k == 1 ? '' : 's'} to discard', options: opts, min: k, max: k, source: ctx.source));
          _discardCards(q, pick);
        }
        ctx.didIt = true;
      case W2ShuffleFromAnyDiscard():
        final cands = [for (final q in _turnOrderFrom(p)) ...s.player(q).discard];
        if (cands.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose a card from any discard to shuffle into its player’s deck', options: cands, min: 1, max: 1, source: ctx.source)).first;
        final owner = s.obj(pick).owner;
        _moveTo(pick, Place.deck);
        s.rng.shuffle(s.player(owner).deck);
        log('${nameOf(pick)} is shuffled into ${s.player(owner).name}’s deck.', player: p, card: pick);
        ctx.didIt = true;
      case W2WithSingers(:final effect):
        ctx.slots[w2SingersSlot] = ctx.singers;
        _resolveEffect(effect, ctx);
      case W2TrackRemoved(:final effect):
        int total() => s.players.fold<int>(0, (a, pl) => a + pl.turnStats[TurnStat.removedDamage.index]);
        final before = total();
        _resolveEffect(effect, ctx);
        ctx.slots[w2RemovedSlot] = [total() - before];
    }
  }

  void _w2AddTimed(_Ctx ctx, List<CardId>? ids, Lasting d, String label) {
    state.timed.add(Timed(ts: state.nextTs++, controller: ctx.controller, source: ctx.source, lasting: d, turn: state.turn, cards: ids, label: label));
    state.version++;
  }

  /// Puts [card] (the top of a deck, or one in a discard) facedown under [host] (CR 8.4.2).
  void _w2PutUnder(int p, CardId card, CardId host) {
    final s = state;
    final o = s.obj(card);
    if (o.zone == Place.discard) {
      // Leaving the discard is an event ("whenever a card leaves your discard").
      s.player(o.owner).discard.remove(card);
      _w2LeftDiscard(o.owner, card);
    } else {
      _moveTo(card, Place.discard);
      s.player(o.owner).discard.remove(card);
    }
    o.zone = Place.play;
    o.faceDown = true;
    s.obj(host).under.insert(0, card);
    s.version++;
    log('A card goes facedown under ${nameOf(host)}.', player: p, card: host, kind: 'ability');
    _emit(_Ev(kind: _EvKind.putUnder, card: host, player: p));
  }

  /// Plays [id] for free (CR 6.1.7); an action played this way goes to the bottom of its deck
  /// afterwards when [bottomAfter] (CR 6.1.7: "instead of into your discard").
  void _w2PlayFreeCard(int p, CardId id, {bool bottomAfter = false, bool exerted = false}) {
    final s = state;
    final c = db[s.obj(id).card]!;
    if (c.type != CardType.action || !bottomAfter) {
      _enterPlay(p, id, free: true, exerted: exerted);
      return;
    }
    log('${s.player(p).name} plays ${c.fullName}.', player: p, card: id, kind: 'play');
    _moveTo(id, Place.play);
    final n = ++s.player(p).actionsThisTurn;
    _emit(_Ev(kind: _EvKind.played, card: id, player: p, amount: n));
    final eff = LorcanaParser.parse(c).abilities.whereType<ActionEffect>().firstOrNull;
    if (eff != null) _resolveEffect(eff.effect, _Ctx(this, controller: p, source: id, isAction: true));
    if (s.obj(id).zone == Place.play) {
      _moveTo(id, Place.deck, bottom: true);
      log('${c.fullName} goes to the bottom of ${s.player(p).name}’s deck.', player: p, card: id);
    }
  }

  /// The ways [p] can pay to play [id] from where it is (CR 4.3.2.2): its ink cost, Shift onto
  /// one of their characters, or singing it with one character.
  List<(String, void Function())> _w2PlayWays(int p, CardId id, {bool exerted = false}) {
    if (_w2PlayBlock(p, id) != null) return const [];
    final c = db[state.obj(id).card]!;
    final out = <(String, void Function())>[];
    final cost = _w2InkCost(p, id);
    if (_inkReady(p) >= cost) {
      out.add((
        'Pay $cost ink',
        () {
          _payInk(p, cost);
          _w2UseReduction(p, id);
          _emit(_Ev(kind: _EvKind.inkPaid, card: id, player: p, amount: cost));
          _enterPlay(p, id, exerted: exerted);
        },
      ));
    }
    final k = _shiftOf(id);
    if (k != null && k.shiftDiscard == null && k.shiftVariant != ShiftVariant.duo && _inkReady(p) >= _shiftCost(p, id, k)) {
      for (final onto in shiftTargets(p, id)) {
        out.add((
          'Shift onto ${nameOf(onto)}',
          () {
            final n = _shiftCost(p, id, k);
            _payInk(p, n);
            _w2UseReduction(p, id);
            _emit(_Ev(kind: _EvKind.inkPaid, card: id, player: p, amount: n));
            _enterPlay(p, id, shiftOnto: onto, how: PlayMode.shift);
            if (k.shiftVariant == ShiftVariant.temporary && state.obj(id).zone == Place.play) state.obj(id).temporaryShift = true;
          },
        ));
      }
    }
    if (c.isSong) {
      for (final singer in state.player(p).play) {
        if (!_canExertToPay(p, singer) || chars(singer).rules.contains(Rule.cantSing) || chars(singer).rules.contains(Rule.singsOnlyTogether) || _singCost(singer) < c.cost) continue;
        out.add((
          'Sing with ${nameOf(singer)}',
          () {
            _exertCard(singer);
            _enterPlay(p, id, singers: [singer], how: PlayMode.sing);
          },
        ));
      }
    }
    return out;
  }

  /// Plays [id] from outside the hand paying its costs; false if it can't be paid.
  bool _w2PlayPaying(int p, CardId id, {bool exerted = false}) {
    final ways = _w2PlayWays(p, id, exerted: exerted);
    if (ways.isEmpty) return false;
    final i = ways.length == 1 ? 0 : ask(Decision(kind: DecisionKind.option, player: p, prompt: 'How do you play ${nameOf(id)}?', labels: [for (final w in ways) w.$1], source: id)).first;
    ways[i].$2();
    return true;
  }

  /// [playCost] for a card wherever it is.
  int _w2InkCost(int p, CardId id) {
    final o = state.obj(id);
    final c = db[o.card]!;
    var cost = c.cost;
    final ctx = _Ctx(this, controller: p, source: id);
    for (final a in LorcanaParser.parse(c).abilities) {
      if (a is Static && a.inHand && a.effect is CostReduction) {
        if (a.condition != null && !_evalCond(a.condition!, ctx)) continue;
        cost -= _evalAmount((a.effect as CostReduction).amount, ctx);
      }
    }
    for (final (src, st, ctl) in _statics()) {
      final e = st.effect;
      if (e is! CostReduction || e.self || ctl != p) continue;
      if (st.condition != null && !_evalCond(st.condition!, _Ctx(this, controller: ctl, source: src))) continue;
      if (!matches(e.filter, id, controller: p, source: src, place: o.zone)) continue;
      cost -= _evalAmount(e.amount, _Ctx(this, controller: ctl, source: src));
    }
    for (final r in state.reductions) {
      if (r.player == p && matches(r.filter, id, controller: p, place: o.zone)) {
        cost -= r.n;
        break;
      }
    }
    return cost < 0 ? 0 : cost;
  }

  void _w2UseReduction(int p, CardId id) {
    final i = state.reductions.indexWhere((r) => r.player == p && matches(r.filter, id, controller: p, place: state.obj(id).zone));
    if (i >= 0) state.reductions.removeAt(i);
  }

  /// "Shift a character from your discard for free" (CR 8.10): a character card there with Shift
  /// goes on top of one of yours it can shift onto.
  void _w2ShiftFromDiscard(int p, _Ctx ctx) {
    final s = state;
    final cands = [
      for (final id in s.player(p).discard)
        if (db[s.obj(id).card]!.type == CardType.character && _w2PlayBlock(p, id) == null && (shiftTargets(p, id).isNotEmpty || duoShiftTargets(p, id).isNotEmpty)) id,
    ];
    if (cands.isEmpty) return;
    final id = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Shift a character from your discard for free', options: cands, min: 1, max: 1, source: ctx.source)).first;
    final singles = shiftTargets(p, id);
    final pairs = duoShiftTargets(p, id);
    final labels = [for (final t in singles) nameOf(t), for (final (a, b) in pairs) '${nameOf(a)} and ${nameOf(b)}'];
    final i = labels.length == 1 ? 0 : ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Shift ${nameOf(id)} onto', labels: labels, source: ctx.source)).first;
    final (onto, onto2) = i < singles.length ? (singles[i], null) : pairs[i - singles.length];
    _enterPlay(p, id, shiftOnto: onto, shiftOnto2: onto2, how: PlayMode.shift);
    if (_shiftOf(id)?.shiftVariant == ShiftVariant.temporary && s.obj(id).zone == Place.play) s.obj(id).temporaryShift = true;
    ctx.didIt = true;
  }

  // -------------------------------------------------------------------------------------------
  // Conditions and amounts
  // -------------------------------------------------------------------------------------------

  bool _w2EvalCond(W2Cond c, _Ctx ctx) {
    final s = state;
    final src = s.objOrNull(ctx.source);
    switch (c) {
      case W2SingersCond(:final n):
        return ctx.singers.length >= n;
      case W2PlayedThisTurn(:final filter):
        return s.player(ctx.controller).playedThisTurn.any((id) => _w2CardIs(filter, id, ctx.controller));
      case W2OpponentHas(:final filter, :final n):
        final all = matching(filter, controller: ctx.controller, source: ctx.source, whose: Owner.opposing);
        return s.opponents(ctx.controller).any((q) => !s.player(q).lost && all.where((id) => s.obj(id).owner == q).length >= n);
      case W2DiscardedIs(:final filter):
        return (ctx.slots[w2DiscardSlot] ?? const []).any((id) => _w2CardIs(filter, id, ctx.controller));
      case W2RemovedAny():
        return (ctx.slots[w2RemovedSlot] ?? const [0]).first > 0;
      case W2SlotIs(:final slot, :final filter):
        return (ctx.slots[slot] ?? const []).any((id) => _w2CardIs(filter, id, ctx.controller));
      case W2SlotHasUnder(:final slot):
        return (ctx.slots[slot] ?? const []).any((id) => s.obj(id).zone == Place.play && s.obj(id).under.isNotEmpty);
      case W2PutUnderThisTurn():
        return src != null && src.usedOn[_putUnderKey] == s.turn;
      case W2HadUnder():
        return src != null && src.usedOn[_hadUnderKey] == src.zcc;
      case W2DiscardedThisTurn():
        return s.player(ctx.controller).turnStats[TurnStat.discarded.index] > 0;
    }
  }

  int _w2Amount(W2Amount a, _Ctx ctx) => switch (a) {
    W2EventAmount() => ctx.event?.amount ?? 0,
    W2CostOf(:final target) => () {
      final ids = _resolveTargets(target, ctx);
      return ids.isEmpty ? 0 : chars(ids.first).cost;
    }(),
    W2RemovedAmount() => (ctx.slots[w2RemovedSlot] ?? const [0]).first,
  };

  /// Does the card [id], in any zone, match [f] by its printed characteristics?
  bool _w2CardIs(Filter f, CardId id, int controller) {
    final o = state.obj(id);
    final c = db[o.card]!;
    if (!f.types.contains(c.type)) return false;
    if (f.song != null && c.isSong != f.song) return false;
    if (f.owner == Owner.yours && o.owner != controller) return false;
    if (f.owner == Owner.opposing && o.owner == controller) return false;
    if (f.classes.isNotEmpty && !f.classes.any(c.hasClass)) return false;
    if (f.named != null && !c.names.any((n) => n.toLowerCase() == f.named!.toLowerCase())) return false;
    if (f.costMax != null && c.cost > f.costMax!) return false;
    if (f.costMin != null && c.cost < f.costMin!) return false;
    if (f is W2Filter && f.ink != null && !c.inks.contains(f.ink)) return false;
    return true;
  }

  // -------------------------------------------------------------------------------------------
  // Filters and characteristics
  // -------------------------------------------------------------------------------------------

  /// The [W2Filter] conditions, for a card in [place].
  bool _w2Matches(W2Filter f, CardId id, int controller, CardId? source, Place place) {
    final o = state.obj(id);
    if (f.ink != null && !db[o.card]!.inks.contains(f.ink)) return false;
    if (f.hasUnder != null && o.under.isNotEmpty != f.hasUnder) return false;
    if (f.challengedThisTurn && o.usedOn[_challengedKey] != state.turn) return false;
    if (f.costAtMostSourceStrength) {
      final src = source == null ? null : state.objOrNull(source);
      if (src == null || src.zone != Place.play || db[o.card]!.cost > chars(source!).strength) return false;
    }
    return true;
  }

  /// A card that left play, matched as it was ([_triggerMatches]): its ink.
  bool _w2LeftPlayMatches(Filter f, LCard c) => f is! W2Filter || f.ink == null || c.inks.contains(f.ink);

  /// "Give chosen character of yours the Hunny classification".
  bool _w2HasClass(CardId id, String cls) {
    for (final t in state.timed) {
      if (t.label.startsWith('w2:class:') && t.cards != null && t.cards!.contains(id) && t.label.substring(9).toLowerCase() == cls.toLowerCase()) return true;
    }
    return false;
  }

  /// Keyword counts and keywords lost for a while (called from [chars] for a card in play).
  void _w2ApplyStatics(CardId id, LChars ch) {
    for (final a in LorcanaParser.parse(ch.card).abilities) {
      if (a is! Static || a.effect is! W2KeywordPer) continue;
      final ctx = _Ctx(this, controller: ch.owner, source: id);
      if (a.condition != null && !_evalCond(a.condition!, ctx)) continue;
      final e = a.effect as W2KeywordPer;
      final n = _evalAmount(e.count, ctx);
      if (n > 0) ch.addKeyword(Keyword(e.kw, n: n));
    }
    for (final t in state.timed) {
      if (!t.label.startsWith('w2:lose:') || t.cards == null || !t.cards!.contains(id)) continue;
      final kw = Kw.values.where((k) => k.name == t.label.substring(8)).firstOrNull;
      if (kw != null) ch.keywords.remove(kw);
    }
  }

  /// Statics in play of type [T] whose condition holds: (source, effect, controller).
  Iterable<(CardId, T, int)> _w2Active<T extends W2Static>() sync* {
    for (final (src, st, ctl) in _statics()) {
      if (st.effect is! T) continue;
      if (st.condition != null && !_evalCond(st.condition!, _Ctx(this, controller: ctl, source: src))) continue;
      yield (src, st.effect as T, ctl);
    }
  }

  // -------------------------------------------------------------------------------------------
  // Rules the statics change
  // -------------------------------------------------------------------------------------------

  /// Why [p] can't play [id] at all now ("you can't play this character unless …", "opponents
  /// can't play actions or items"), or null.
  String? _w2PlayBlock(int p, CardId id) {
    final c = db[state.obj(id).card]!;
    for (final a in LorcanaParser.parse(c).abilities) {
      if (a is Static && a.effect is W2CantPlayThis && (a.condition == null || _evalCond(a.condition!, _Ctx(this, controller: p, source: id)))) return 'You can’t play ${c.name} now';
    }
    for (final t in state.timed) {
      if (!t.label.startsWith('w2:cantPlay:') || t.controller == p) continue;
      if (t.label.substring(12).split(',').contains(c.type.name)) return '${state.player(t.controller).name}’s ${nameOf(t.source)}: you can’t play ${c.type.name}s now';
    }
    return null;
  }

  W2AltCost? _w2AltCostOf(CardId id, bool shift) {
    for (final a in LorcanaParser.parse(db[state.obj(id).card]!).abilities) {
      if (a is Static && a.effect is W2AltCost && (a.effect as W2AltCost).shift == shift) return a.effect as W2AltCost;
    }
    return null;
  }

  List<CardId> _w2AltCards(int p, CardId id, W2AltCost alt) => [
    for (final x in state.player(p).discard)
      if (x != id && _w2CardIs(alt.filter, x, p)) x,
  ];

  /// Can [m] be paid with the card's alternate cost instead of ink (CR 1.5.5)?
  bool _w2CanAltPay(PlayMove m) {
    final alt = _w2AltCostOf(m.card, m.mode == PlayMode.shift);
    return alt != null && _w2AltCards(m.seat, m.card, alt).length >= alt.count;
  }

  /// Pays [m] with the alternate cost if the player chooses it (or must); true if paid.
  bool _w2AltPaid(PlayMove m) {
    if (!_w2CanAltPay(m)) return false;
    final p = m.seat;
    final alt = _w2AltCostOf(m.card, m.mode == PlayMode.shift)!;
    final inkCost = m.mode == PlayMode.shift ? _shiftCost(p, m.card, _shiftOf(m.card)!) : playCost(p, m.card);
    final what = '${alt.count} ${alt.filter.describe()} card${alt.count == 1 ? '' : 's'}';
    if (_inkReady(p) >= inkCost && !askYesNo(p, 'Put $what from your discard on the bottom of your deck instead of paying $inkCost ink?', source: m.card)) return false;
    final opts = _w2AltCards(p, m.card, alt);
    var pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose $what to put on the bottom of your deck', options: opts, min: alt.count, max: alt.count, source: m.card));
    if (pick.length > 1) pick = ask(Decision(kind: DecisionKind.order, player: p, prompt: 'Order them for the bottom of your deck (first = highest)', options: pick, source: m.card));
    for (final id in pick) {
      _moveTo(id, Place.deck, bottom: true);
    }
    log('${state.player(p).name} puts $what from their discard on the bottom of their deck.', player: p);
    return true;
  }

  /// "All cards in your hand count as having {IW}".
  bool _w2Inkable(int p, CardId id) => state.obj(id).zone == Place.hand && _w2Active<W2HandInkable>().any((x) => x.$3 == p);

  /// The ink to move [character] to [location] after "may move here for free" and "you pay 1 {i}
  /// less to move your characters to a location".
  int _w2MoveCost(int p, CardId character, CardId location, int cost) {
    var n = cost;
    for (final (src, e, ctl) in _w2Active<W2MoveCost>()) {
      if (ctl != p || !matches(e.filter, character, controller: ctl, source: src)) continue;
      if (e.here && src == location) return 0;
      if (!e.here) n -= e.less;
    }
    return n < 0 ? 0 : n;
  }

  /// "Once during your turn" activated abilities (CR 6.1.13.2).
  String? _w2ActivateProblem(Obj o, int index, Activated a) => a is W2OnceActivated && o.usedOn[index] == state.turn ? 'Only once per turn' : null;

  /// The ink an activated ability costs: none for "you may use this item's Shapeshift ability
  /// for free" (CR 6.1.7.1; {e} is still paid).
  int _w2AbilityInk(CardId id, Activated a) {
    for (final (src, e, _) in _w2Active<W2FreeAbility>()) {
      if (src == id && a.text.toLowerCase().startsWith(e.name.toLowerCase())) return 0;
    }
    return a.cost.ink;
  }

  /// "If an effect would cause you to discard one or more cards, you don't discard".
  bool _w2NoDiscard(int p) => _w2Active<W2NoDiscard>().any((x) => x.$3 == p);

  /// "You can't lose lore".
  bool _w2NoLoseLore(int p) => _w2Active<W2NoLoseLore>().any((x) => x.$3 == p);

  /// Damage replaced or prevented: "can't be dealt damage unless he's being challenged", "the first
  /// time this character would take damage, she takes no damage instead" (CR 6.5).
  int _w2Damage(CardId id, int dmg, CardId source, bool challenge) {
    if (dmg <= 0) return dmg;
    for (final (src, e, ctl) in _w2Active<W2NoDamageUnlessChallenged>()) {
      final applies = e.affected == null ? src == id : matches(e.affected!, id, controller: ctl, source: src);
      if (applies && !(challenge && _challenged == id)) return 0;
    }
    for (final (src, _, _) in _w2Active<W2FirstDamagePrevented>()) {
      if (src != id || state.obj(id).usedOn[_firstDamageKey] == state.turn) continue;
      state.obj(id).usedOn[_firstDamageKey] = state.turn;
      log('${nameOf(id)} takes no damage.', card: id);
      return 0;
    }
    return dmg;
  }

  /// "If this character would be banished, put them into your inkwell facedown and exerted
  /// instead" (CR 6.5): true when the banishing was replaced.
  bool _w2BanishInstead(CardId id) {
    final o = state.objOrNull(id);
    if (o == null || o.zone != Place.play) return false;
    if (!_w2Active<W2BanishToInkwell>().any((x) => x.$1 == id)) return false;
    log('${nameOf(id)} goes into ${state.player(o.owner).name}’s inkwell instead of being banished.', player: o.owner, card: id, kind: 'ink');
    _leavePlay(id, Place.inkwell, exerted: true);
    return true;
  }

  /// "Opponents must choose this character for actions and abilities if able": when [cands]
  /// include such a character of an opponent of the chooser, the choice must take it. Null when no
  /// such character is among them.
  List<CardId>? _w2ForcedPick(List<CardId> cands, int count, bool upTo, bool word, _Ctx ctx, String prompt) {
    if (!word) return null;
    final forced = [
      for (final id in cands)
        if (state.obj(id).owner != ctx.controller && LorcanaParser.parse(db[state.obj(id).card]!).abilities.any((a) => a is Static && a.effect is W2MustBeChosen)) id,
    ];
    if (forced.isEmpty) return null;
    if (count == 1) return ask(Decision(kind: DecisionKind.cards, player: ctx.controller, prompt: prompt, options: forced, min: upTo ? 0 : 1, max: 1, source: ctx.source));
    final first = forced.take(count).toList();
    final rest = [
      for (final id in cands)
        if (!first.contains(id)) id,
    ];
    final more = count - first.length;
    final extra = rest.isEmpty || more == 0
        ? const <CardId>[]
        : ask(Decision(kind: DecisionKind.cards, player: ctx.controller, prompt: prompt, options: rest, min: upTo ? 0 : (more < rest.length ? more : rest.length), max: more < rest.length ? more : rest.length, source: ctx.source));
    return [...first, ...extra];
  }

  /// "Each opponent can't ready more than 1 of their characters at the start of their next
  /// turn": the characters [p] keeps exerted in this Ready step (their choice of which ready).
  Set<CardId> _w2ReadyHeld(int p) {
    final s = state;
    final limits = [
      for (final t in s.timed)
        if (t.label.startsWith('w2:readyLimit:') && t.label.endsWith(':$p') && t.turn < s.turn) t,
    ];
    if (limits.isEmpty) return const {};
    s.timed.removeWhere(limits.contains);
    final n = limits.map((t) => int.parse(t.label.split(':')[2])).reduce((a, b) => a < b ? a : b);
    final readying = [
      for (final id in s.player(p).play)
        if (s.obj(id).exerted && chars(id).type == CardType.character && !chars(id).rules.contains(Rule.cantReady) && !s.timed.any((t) => t.rule == Rule.cantReady && t.lasting == Lasting.theirNextTurn && t.turn < s.turn && (t.cards?.contains(id) ?? false))) id,
    ];
    if (readying.length <= n) return const {};
    final keep = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose $n character${n == 1 ? '' : 's'} to ready', options: readying, min: n, max: n));
    return {for (final id in readying) if (!keep.contains(id)) id};
  }

  /// "Each player plays with the top card of their deck face up": that card's name, or null.
  String? faceUpTop(int p) {
    if (!_w2Active<W2TopCardFaceUp>().any((_) => true)) return null;
    final deck = state.player(p).deck;
    return deck.isEmpty ? null : nameOf(deck.first);
  }

  // -------------------------------------------------------------------------------------------
  // Events and triggers
  // -------------------------------------------------------------------------------------------

  /// What this slice remembers about the turn (called for every event).
  void _w2Track(_Ev e) {
    final s = state;
    switch (e.kind) {
      case _EvKind.putUnder:
        if (e.card != null) s.obj(e.card!).usedOn[_putUnderKey] = s.turn;
      case _EvKind.isChallenged:
        if (e.card != null) s.obj(e.card!).usedOn[_challengedKey] = s.turn;
      case _EvKind.discarded:
        if (e.player != null) s.player(e.player!).turnStats[TurnStat.discarded.index]++;
      default:
    }
  }

  /// A card leaves play: whether it had cards under it, and which (CR 6.7.7, "if he had a card
  /// under him", "all cards that were under him").
  void _w2LeavingPlay(Obj o) {
    // Granted by statics as it leaves ("your characters named Jetsam gain "When this character is
    // banished in a challenge, …""), for its own leaves-play triggers (CR 6.7.7).
    _lkiGrants[o.id] = (o.zcc + 1, [
      for (final (src, st, ctl) in _statics())
        if (st.effect is W2StaticTrigger && (st.condition == null || _evalCond(st.condition!, _Ctx(this, controller: ctl, source: src))))
          if ((st.effect as W2StaticTrigger).affected == null ? src == o.id : matches((st.effect as W2StaticTrigger).affected!, o.id, controller: ctl, source: src)) (st.effect as W2StaticTrigger).ability,
    ]);
    if (o.under.isEmpty) return;
    o.usedOn[_hadUnderKey] = o.zcc + 1;
    for (final u in o.under) {
      state.obj(u).usedOn[_wasUnderKey] = o.id;
      state.obj(u).usedOn[_wasUnderZccKey] = o.zcc + 1;
    }
  }

  void _w2LeftDiscard(int owner, CardId id) => _emit(_Ev(kind: _EvKind.w2LeftDiscard, card: id, player: owner));

  bool _w2TriggerMatches(W2Trigger t, _Ev e, CardId src, int you) {
    switch (t) {
      case W2LeavesDiscard():
        return e.kind == _EvKind.w2LeftDiscard && e.player == you;
      case W2EntersExerted(:final subject):
        if (e.kind != _EvKind.played || e.card == null) return false;
        final o = state.obj(e.card!);
        return o.zone == Place.play && o.exerted && matches(subject, e.card!, controller: you, source: src);
    }
  }

  /// Triggered abilities granted for a while ("your Hero characters gain "…" this turn") or by a
  /// static ("she gains "…""), added to the bag like the card's own (CR 7.7.3).
  void _w2EmitGranted(_Ev e, EventInfo info) {
    final s = state;
    final grants = [
      for (final t in s.timed)
        if (t.label.startsWith('w2:grant|') && t.cards != null) t,
    ];
    final statics = [
      for (final x in _statics())
        if (x.$2.effect is W2StaticTrigger) x,
    ];
    final lki = e.card != null && _selfOutsidePlay.union(const {_EvKind.banished, _EvKind.banishedInChallenge}).contains(e.kind) ? _lkiGrants[e.card!] : null;
    if (grants.isEmpty && statics.isEmpty && (lki == null || lki.$2.isEmpty)) return;
    for (final p in _turnOrder()) {
      final pl = s.player(p);
      final sources = [...pl.play];
      final leaving = (e.kind == _EvKind.banished || e.kind == _EvKind.banishedInChallenge || _selfOutsidePlay.contains(e.kind)) && e.card != null && s.obj(e.card!).owner == p ? e.card : null;
      if (leaving != null && !sources.contains(leaving)) sources.add(leaving);
      for (final src in sources) {
        final gone = src == leaving && !pl.play.contains(src);
        final abilities = <Triggered>[
          if (gone && lki != null && lki.$1 == s.obj(src).zcc) ...lki.$2,
          for (final t in grants)
            if (t.cards!.contains(src) && _w2Granted(t.label) != null) _w2Granted(t.label)!,
          for (final (from, st, ctl) in statics)
            if (!gone)
            if (st.condition == null || _evalCond(st.condition!, _Ctx(this, controller: ctl, source: from)))
              if ((st.effect as W2StaticTrigger).affected == null ? from == src : matches((st.effect as W2StaticTrigger).affected!, src, controller: ctl, source: from)) (st.effect as W2StaticTrigger).ability,
        ];
        for (final a in abilities) {
          if (src == leaving && !pl.play.contains(src) && !_isLeavesTrigger(a.trigger)) continue;
          if (src != leaving && s.obj(src).zone != Place.play) continue;
          if (!_triggerMatches(a.trigger, e, src, p, info: info)) continue;
          if (a.during != null && !_evalCond(a.during!, _Ctx(this, controller: p, source: src))) continue;
          _addToBag(p, src, a, info, -1);
        }
      }
    }
  }

  static final Map<String, Triggered?> _grantCache = {};

  /// The ability a "w2:grant|card|quote" label names: found in that card's parsed text.
  Triggered? _w2Granted(String label) => _grantCache.putIfAbsent(label, () {
    final parts = label.split('|');
    final card = db[parts[1]];
    if (card == null) return null;
    final quote = parts.sublist(2).join('|');
    Triggered? find(Effect e) => switch (e) {
      W2GrantAbility(quote: final q, :final ability) when q == quote => ability,
      Seq(:final steps) => steps.map(find).nonNulls.firstOrNull,
      May(e: final x) => find(x),
      If(:final then, :final otherwise) => find(then) ?? (otherwise == null ? null : find(otherwise)),
      ChooseOne(:final options) => options.map(find).nonNulls.firstOrNull,
      _ => null,
    };
    for (final a in LorcanaParser.parse(card).abilities) {
      final e = switch (a) {
        Triggered(:final effect) || Activated(:final effect) || ActionEffect(:final effect) => effect,
        _ => null,
      };
      final r = e == null ? null : find(e);
      if (r != null) return r;
    }
    return null;
  });

  // -------------------------------------------------------------------------------------------
  // The computer player
  // -------------------------------------------------------------------------------------------

  /// Answers for this slice's decisions where the general heuristics would choose badly, or null.
  List<int>? w2BotAnswer(int seat, Decision d) {
    int value(CardId id) {
      final c = db[state.obj(id).card]!;
      return c.cost * 3 + (c.type == CardType.character ? (c.lore ?? 0) * 4 + (c.strength ?? 0) + (c.willpower ?? 0) : 0);
    }

    final p = d.prompt;
    // Keep the character: the opponent draws instead.
    if (d.kind == DecisionKind.yesNo && p.startsWith('Put ') && p.contains('on the bottom of your deck? If you don')) return const [0];
    if (d.kind == DecisionKind.cards && p.contains('on the top of your deck')) {
      final opts = List.of(d.options)..sortStable((a, b) => value(a) - value(b));
      return opts.take(d.min).toList();
    }
    // Ready the best characters.
    if (d.kind == DecisionKind.cards && p.contains('to ready')) {
      final opts = List.of(d.options)..sortStable((a, b) => value(b) - value(a));
      return opts.take(d.min).toList();
    }
    return null;
  }
}
