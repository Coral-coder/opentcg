part of 'game.dart';

/// What an effect resolves with: who generated it (CR 1.4.3.1), its source, the triggering
/// event, choices made so far ("them"), and whether the last optional part happened.
class _Ctx {
  _Ctx(this.game, {required this.controller, required this.source, this.event, this.isAction = false});
  final Game game;
  final int controller;
  final CardId source;
  final EventInfo? event;
  final bool isAction;
  final Map<int, List<CardId>> slots = {};
  bool didIt = false;

  /// Numbers an effect notes as it resolves (game/wave2_s4.dart: "the lore lost", "sung").
  final Map<String, int> s4 = {};
  int? chosenOpponent;
  int? sourceStrength;

  /// "Chosen player" and "name a card" (game/zones.dart).
  int? chosenPlayer;
  String? named;

  /// The characters singing the song being resolved (CR 5.4.4; wave2_s2).
  List<CardId> singers = const [];
}

extension GameEffects on Game {
  // -------------------------------------------------------------------------------------------
  // Amounts and conditions
  // -------------------------------------------------------------------------------------------

  int _evalAmount(Amount a, _Ctx ctx) => switch (a) {
    Fixed(:final n) => n,
    CountOf(:final filter, :final place, :final whose, :final per) => per * matching(filter, controller: ctx.controller, source: ctx.source, place: place, whose: whose).length,
    StatOf(:final target, :final stat) => _statOf(target, stat, ctx),
    HandSize(:final who, :final per) => per * _players(who, ctx).fold<int>(0, (s, p) => s + state.player(p).hand.length),
    DamageOn() => _boardAmount(a, ctx),
    W2Amount() => _w2Amount(a, ctx),
    DamageOnSelf(:final per, :final times) => times * ((state.objOrNull(ctx.source)?.damage ?? 0) ~/ per),
    UnderSelf(:final times) => times * (state.objOrNull(ctx.source)?.under.length ?? 0),
    S3Amount() => _s3Amount(a, ctx),
    S4Amount() => _s4Amount(a, ctx),
    W1Amount() => _w1Amount(a, ctx),
  };

  int _statOf(Target t, Stat stat, _Ctx ctx) {
    final ids = _resolveTargets(t, ctx, choose: false);
    if (ids.isEmpty) {
      if (t is This && ctx.sourceStrength != null && stat == Stat.strength) return ctx.sourceStrength!;
      if (t is EventCard && ctx.event != null && stat == Stat.strength) return ctx.event!.strength;
      return 0;
    }
    final c = chars(ids.first);
    return switch (stat) {
      Stat.strength => c.strengthAtLeast0,
      Stat.willpower => c.willpower,
      Stat.lore => c.loreAtLeast0,
    };
  }

  bool _evalCond(Cond c, _Ctx ctx) {
    bool cmp(int v, Cmp k, int n) => switch (k) {
      Cmp.ge => v >= n,
      Cmp.le => v <= n,
      Cmp.eq => v == n,
      Cmp.gt => v > n,
      Cmp.lt => v < n,
    };
    switch (c) {
      case CountCond(:final filter, cmp: final k, :final n, :final place, :final whose):
        return cmp(matching(filter, controller: ctx.controller, source: ctx.source, place: place, whose: whose).length, k, n);
      case SelfState(:final exerted, :final atLocation, :final damaged):
        final o = state.objOrNull(ctx.source);
        if (o == null || o.zone != Place.play) return false;
        if (exerted != null && o.exerted != exerted) return false;
        if (atLocation != null && (o.at != null) != atLocation) return false;
        if (damaged != null && (o.damage > 0) != damaged) return false;
        return true;
      case YourTurn():
        return state.active == ctx.controller;
      case HandCond(:final who, cmp: final k, :final n):
        return _players(who, ctx).any((p) => cmp(state.player(p).hand.length, k, n));
      case LoreCond(:final who, cmp: final k, :final n):
        return _players(who, ctx).any((p) => cmp(state.player(p).lore, k, n));
      case Not(c: final inner):
        return !_evalCond(inner, ctx);
      case AllConds(:final conds):
        return conds.every((x) => _evalCond(x, ctx));
      case DidIt():
        return ctx.didIt;
      case TargetIs(:final target, :final filter):
        final ids = _resolveTargets(target, ctx, choose: target is Chosen);
        return ids.isNotEmpty && matches(filter, ids.first, controller: ctx.controller, source: ctx.source);
      case ZoneCond():
        return _evalZoneCond(c, ctx);
      case TurnStatCond() || ShiftedCond() || HandCompare() || SelfDamage() || StrongestCond():
        return _evalBoardCond(c, ctx);
      case S3Cond():
        return _s3Cond(c, ctx);
      case W1Cond():
        return _evalW1Cond(c, ctx);
      case W2Cond():
        return _w2EvalCond(c, ctx);
      default:
        return _evalMoreCond(c, ctx);
    }
  }

  List<int> _players(Who w, _Ctx ctx) {
    final p = ctx.controller;
    switch (w) {
      case Who.you:
        return [p];
      case Who.opponents:
        return [
          for (final q in state.opponents(p))
            if (!state.player(q).lost) q,
        ];
      case Who.each:
        return [
          for (final q in _turnOrder())
            if (!state.player(q).lost) q,
        ];
      case Who.chosenOpponent:
        final ops = [
          for (final q in state.opponents(p))
            if (!state.player(q).lost) q,
        ];
        if (ops.length <= 1) return ops;
        return [
          ctx.chosenOpponent ??= ops[ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Choose an opponent', labels: [for (final q in ops) state.player(q).name])).first],
        ];
      case Who.thatPlayer:
        final chosen = [for (final k in ctx.slots.keys) if (k < groupSlots) k];
        final ids = chosen.isNotEmpty ? ctx.slots[chosen.last]! : const <CardId>[];
        if (ids.isNotEmpty) return [state.obj(ids.first).owner];
        final ev = ctx.event;
        if (ev?.player != null) return [ev!.player!];
        if (ev?.card != null) return [state.obj(ev!.card!).owner];
        return [p];
      case Who.chosenPlayer || Who.challenger:
        return _zonePlayers(w, ctx);
    }
  }

  // -------------------------------------------------------------------------------------------
  // Targets (CR 6.1.3, 6.7.3)
  // -------------------------------------------------------------------------------------------

  /// Cards [t] refers to. "Chosen" asks the controller (when [choose]); Ward protects from
  /// opponents' choices (CR 8.15), and Vanish banishes a character an opponent chose for an
  /// action (CR 8.14).
  List<CardId> _resolveTargets(Target t, _Ctx ctx, {bool choose = true, bool fromDiscard = false}) {
    bool here(CardId id) {
      final z = state.objOrNull(id)?.zone;
      return z == Place.play || (fromDiscard && z == Place.discard);
    }

    switch (t) {
      case This():
        return here(ctx.source) ? [ctx.source] : const [];
      case EventCard(:final other):
        final ev = ctx.event;
        final id = other ? ev?.other : ev?.card;
        if (id == null) return const [];
        return here(id) ? [id] : const [];
      case Remembered(:final slot):
        return [
          for (final id in ctx.slots[slot] ?? const <CardId>[])
            if (state.objOrNull(id)?.zone == Place.play) id,
        ];
      case LocationOf(:final of):
        final out = <CardId>[];
        for (final id in _resolveTargets(of, ctx, choose: false)) {
          final o = state.obj(id);
          final l = db[o.card]!.type == CardType.location ? id : o.at;
          if (l != null && here(l) && !out.contains(l)) out.add(l);
        }
        return out;
      case AllOf(:final filter, :final slot):
        final ids = matching(filter, controller: ctx.controller, source: ctx.source);
        if (slot != null) ctx.slots[slot] = ids;
        return ids;
      case Chosen(:final filter, :final count, :final upTo, :final slot, :final word):
        if (!choose) return ctx.slots[slot] ?? const [];
        // One choice per "chosen" in the ability, however many effects use it (CR 6.1.3).
        final already = ctx.slots[slot];
        if (already != null) {
          return [
            for (final id in already)
              if (state.objOrNull(id)?.zone == Place.play) id,
          ];
        }
        final cands = [
          for (final id in matching(filter, controller: ctx.controller, source: ctx.source))
            if (!(word && state.obj(id).owner != ctx.controller && chars(id).has(Kw.ward)) && !_w1Unchoosable(id, ctx.controller)) id,
        ];
        final min = upTo ? 0 : (count < cands.length ? count : cands.length);
        final max = count < cands.length ? count : cands.length;
        final pick = _w2ForcedPick(cands, count, upTo, word, ctx, 'Choose ${upTo ? 'up to ' : ''}$count ${filter.describe()}') ?? (cands.isEmpty
            ? const <CardId>[]
            : ask(
                Decision(kind: DecisionKind.cards, player: ctx.controller, prompt: 'Choose ${upTo ? 'up to ' : ''}$count ${filter.describe()}', options: cands, min: min, max: max, source: ctx.source),
              ));
        ctx.slots[slot] = pick;
        for (final id in pick) {
          final owner = state.obj(id).owner;
          if (slot == _supportSlot) _emit(_Ev(kind: _EvKind.supportChosen, card: id, player: owner));
          // "Whenever an opponent chooses this character for an action or ability".
          if (owner != ctx.controller) _emit(_Ev(kind: _EvKind.chosenByOpponent, card: id, player: ctx.controller));
          _s4Chosen(id, ctx);
        }
        if (ctx.isAction) {
          for (final id in pick) {
            if (state.obj(id).owner != ctx.controller && chars(id).has(Kw.vanish)) _emit(_Ev(kind: _EvKind.vanish, card: id, player: state.obj(id).owner));
          }
        }
        return pick;
    }
  }

  // -------------------------------------------------------------------------------------------
  // Resolving (CR 6.7)
  // -------------------------------------------------------------------------------------------

  void _resolveEffect(Effect e, _Ctx ctx) {
    if (state.over) return;
    switch (e) {
      case ZoneEffect():
        _resolveZone(e, ctx);
      case S3Effect():
        _resolveS3(e, ctx);
      case S4Effect():
        _resolveS4(e, ctx);
      case W1Effect():
        _resolveW1(e, ctx);
      case W2Effect():
        _w2Resolve(e, ctx);
      case Seq(:final steps):
        for (final s in steps) {
          _resolveEffect(s, ctx);
        }
      case May(e: final inner):
        if (askYesNo(ctx.controller, 'Do you want to: ${_describeEffect(inner)}?', source: ctx.source)) {
          ctx.didIt = true;
          _resolveEffect(inner, ctx);
        } else {
          ctx.didIt = false;
        }
      case If(:final cond, :final then, :final otherwise):
        if (_evalCond(cond, ctx)) {
          _resolveEffect(then, ctx);
        } else if (otherwise != null) {
          _resolveEffect(otherwise, ctx);
        }
      case ChooseOne(:final options, :final labels):
        final i = ask(Decision(kind: DecisionKind.option, player: ctx.controller, prompt: 'Choose one', labels: labels, source: ctx.source)).first;
        _resolveEffect(options[i], ctx);
      case Draw(:final who, :final amount, :final untilHandSize):
        for (final p in _players(who, ctx)) {
          final n = untilHandSize ? _evalAmount(amount, ctx) - state.player(p).hand.length : _evalAmount(amount, ctx);
          for (var i = 0; i < n; i++) {
            _draw(p);
          }
        }
        ctx.didIt = true;
      case Discard(:final who, :final amount, :final random, :final all):
        for (final p in _players(who, ctx)) {
          final hand = state.player(p).hand;
          if (hand.isEmpty || _w2NoDiscard(p)) continue;
          var n = all ? hand.length : _evalAmount(amount, ctx);
          if (n > hand.length) n = hand.length;
          List<CardId> pick;
          if (all) {
            pick = List.of(hand);
          } else if (random) {
            pick = [];
            final copy = List.of(hand);
            for (var i = 0; i < n; i++) {
              pick.add(copy.removeAt(state.rng.nextInt(copy.length)));
            }
          } else {
            pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose $n card${n == 1 ? '' : 's'} to discard', options: List.of(hand), min: n, max: n, source: ctx.source));
          }
          _discardCards(p, pick);
        }
        ctx.didIt = true;
      case GainLore(:final who, :final amount):
        for (final p in _players(who, ctx)) {
          _gainLore(p, _evalAmount(amount, ctx), source: ctx.source);
        }
      case LoseLore(:final who, :final amount):
        for (final p in _players(who, ctx)) {
          _loseLore(p, _evalAmount(amount, ctx));
        }
      case DealDamage(:final target, :final amount, :final put):
        final n = _evalAmount(amount, ctx);
        final ids = _resolveTargets(target, ctx);
        for (final id in ids) {
          _dealDamage(id, n, source: ctx.source, put: put);
        }
        ctx.didIt = ids.isNotEmpty;
      case RemoveDamage(:final target, :final amount, :final all):
        if (_s4NoDamageRemoval()) break;
        for (final id in _resolveTargets(target, ctx)) {
          final o = state.obj(id);
          final n = all ? o.damage : _evalAmount(amount, ctx).clamp(0, o.damage);
          o.damage -= n;
          _noteDamageRemoved(id, n);
          _w1CountHeal(ctx, id, n);
          if (n > 0) {
            log('${nameOf(id)}: $n damage removed.', card: id, kind: 'heal', amount: n);
            _emit(_Ev(kind: _EvKind.damageRemoved, card: id, player: ctx.controller, amount: n));
          }
        }
        state.version++;
      case MoveDamage(:final from, :final to, :final amount, :final upTo):
        if (_s4NoDamageRemoval()) break;
        final a = _resolveTargets(from, ctx);
        final b = _resolveTargets(to, ctx);
        if (a.isEmpty || b.isEmpty) return;
        var n = _evalAmount(amount, ctx).clamp(0, state.obj(a.first).damage);
        // "Up to N" lets the player move fewer, none included (CR 6.1.3).
        if (upTo && n > 0) {
          final labels = [for (var k = n; k >= 0; k--) 'Move $k'];
          n -= ask(Decision(kind: DecisionKind.option, player: ctx.controller, prompt: 'How much damage to move?', labels: labels, source: ctx.source)).first;
        }
        state.obj(a.first).damage -= n;
        state.obj(b.first).damage += n;
        state.version++;
      case Banish(:final target):
        final ids = _resolveTargets(target, ctx);
        for (final id in ids) {
          _banish(id, by: ctx.source);
        }
        ctx.didIt = ids.isNotEmpty;
      case ReturnToHand(:final target):
        // "Return this card to your hand" after it was banished (CR 6.1.12).
        final ids = _resolveTargets(target, ctx, fromDiscard: target is This || target is EventCard);
        for (final id in ids) {
          log('${nameOf(id)} returns to ${state.player(state.obj(id).owner).name}’s hand.', card: id, kind: 'return');
          final wasInPlay = state.obj(id).zone == Place.play;
          _leavePlay(id, Place.hand);
          if (wasInPlay) _emit(_Ev(kind: _EvKind.returnedToHand, card: id, player: state.obj(id).owner));
        }
        ctx.didIt = ids.isNotEmpty;
      case Exert(:final target):
        final ids = _resolveTargets(target, ctx);
        for (final id in ids) {
          log('${nameOf(id)} is exerted.', card: id, kind: 'exert');
          _exertCard(id);
        }
        ctx.didIt = ids.isNotEmpty;
        state.version++;
      case Ready(:final target):
        final ids = _resolveTargets(target, ctx);
        ctx.didIt = ids.isNotEmpty;
        for (final id in ids) {
          state.obj(id).exerted = false;
          log('${nameOf(id)} is readied.', card: id, kind: 'ready');
          _emit(_Ev(kind: _EvKind.readied, card: id, player: state.obj(id).owner));
        }
        state.version++;
      case ToDeck(:final target, :final bottom, :final top):
        for (final id in _resolveTargets(target, ctx, fromDiscard: target is This || target is EventCard)) {
          final owner = state.obj(id).owner;
          _leavePlay(id, Place.deck, bottom: bottom || !top);
          if (!bottom && !top) state.rng.shuffle(state.player(owner).deck);
        }
      case ToInkwell(:final target, :final exerted):
        for (final id in _resolveTargets(target, ctx, fromDiscard: target is This || target is EventCard)) {
          _leavePlay(id, Place.inkwell, exerted: exerted);
        }
      case InkTopOfDeck(:final who, :final exerted):
        for (final p in _players(who, ctx)) {
          final deck = state.player(p).deck;
          if (deck.isEmpty) continue;
          _moveTo(deck.first, Place.inkwell, exerted: exerted);
          log('${state.player(p).name} puts the top card of their deck into their inkwell.', player: p, kind: 'ink');
        }
        ctx.didIt = true;
      case InkFromHand(:final exerted):
        final hand = state.player(ctx.controller).hand;
        if (hand.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: ctx.controller, prompt: 'Put a card from your hand into your inkwell', options: List.of(hand), min: 1, max: 1, source: ctx.source));
        _moveTo(pick.first, Place.inkwell, exerted: exerted);
        ctx.didIt = true;
      case Modify(:final target, :final stat, :final amount, :final duration, :final negative):
        final ids = _resolveTargets(target, ctx);
        if (ids.isEmpty) return;
        _addTimed(ctx, ids, target, duration, stat: stat, amount: _evalAmount(amount, ctx) * (negative ? -1 : 1));
      case GrantKeyword(:final target, :final keyword, :final duration):
        final ids = _resolveTargets(target, ctx);
        if (ids.isEmpty) return;
        _addTimed(ctx, ids, target, duration, keyword: keyword);
      case GrantRule(:final target, :final rule, :final duration):
        final ids = _resolveTargets(target, ctx);
        if (ids.isEmpty) return;
        _addTimed(ctx, ids, target, duration, rule: rule);
      case FromDiscardToHand(:final filter, :final count, :final upTo):
        final cands = matching(filter, controller: ctx.controller, source: ctx.source, place: Place.discard, whose: Owner.yours);
        if (cands.isEmpty) return;
        final n = count < cands.length ? count : cands.length;
        final pick = ask(
          Decision(
            kind: DecisionKind.cards,
            player: ctx.controller,
            prompt: 'Return ${upTo ? 'up to ' : ''}$count ${filter.describe()} card${count == 1 ? '' : 's'} from your discard to your hand',
            options: cands,
            min: upTo ? 0 : n,
            max: n,
            source: ctx.source,
          ),
        );
        for (final id in pick) {
          _moveTo(id, Place.hand);
          log('${nameOf(id)} returns to ${state.player(ctx.controller).name}’s hand.', card: id, kind: 'return');
          _emit(_Ev(kind: _EvKind.returnedFromDiscard, card: id, player: ctx.controller));
        }
        ctx.didIt = pick.isNotEmpty;
      case LookTop(:final n, :final pick, :final pickCount, :final restBottom, :final reorderOnly, :final mustPick, :final restInk):
        _lookTop(ctx, n, pick, pickCount, restBottom, reorderOnly, mustPick: mustPick, restInk: restInk);
      case Mill(:final who, :final n):
        ctx.didIt = true;
        for (final p in _players(who, ctx)) {
          for (var i = 0; i < n && state.player(p).deck.isNotEmpty; i++) {
            _moveTo(state.player(p).deck.first, Place.discard);
          }
        }
      case NextCostReduction(:final filter, :final n):
        state.reductions.add(NextReduction(ctx.controller, filter, n, state.turn));
      case PlayFree(:final filter, :final from, :final entersExerted):
        final cands = [
          for (final id in matching(filter, controller: ctx.controller, source: ctx.source, place: from, whose: Owner.yours))
            if (id != ctx.source && _w2PlayBlock(ctx.controller, id) == null) id,
        ];
        if (cands.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: ctx.controller, prompt: 'Play one for free', options: cands, min: 1, max: 1, source: ctx.source));
        _enterPlay(ctx.controller, pick.first, free: true, exerted: entersExerted);
        ctx.didIt = true;
      case Floating(:final ability):
        state.lingering.add(Lingering(id: state.nextBagId++, controller: ctx.controller, source: ctx.source, ability: ability, turn: state.turn, remembered: [for (final k in ctx.slots.keys) if (k < groupSlots) ...ctx.slots[k]!]));
      case Delayed(:final effect):
        state.lingering.add(
          Lingering(
            id: state.nextBagId++,
            controller: ctx.controller,
            source: ctx.source,
            ability: Triggered('', const TurnStep(start: false), effect),
            turn: state.turn,
            delayedEnd: true,
            remembered: ctx.slots.values.expand((x) => x).toList(),
          ),
        );
      case PlayerChooses() || LoseLoreRicher() || MoveToLocation() || SameNameAs():
        _resolveBoard(e, ctx);
      case MoveFree(:final character):
        final ids = _resolveTargets(character, ctx);
        final loc = ctx.event?.location;
        if (ids.isEmpty || loc == null) return;
        _moveCharacter(ctx.controller, ids.first, loc, pay: false);
    }
  }

  void _addTimed(_Ctx ctx, List<CardId> ids, Target t, Lasting d, {Stat? stat, int amount = 0, Keyword? keyword, Rule? rule}) {
    state.timed.add(Timed(ts: state.nextTs++, controller: ctx.controller, source: ctx.source, lasting: d, turn: state.turn, cards: ids, stat: stat, amount: amount, keyword: keyword, rule: rule));
    state.version++;
  }

  void _lookTop(_Ctx ctx, int n, Filter? pick, int pickCount, bool restBottom, bool reorderOnly, {bool mustPick = false, bool restInk = false}) {
    final p = ctx.controller;
    final deck = state.player(p).deck;
    final seen = deck.take(n).toList();
    if (seen.isEmpty) return;
    var rest = List.of(seen);
    if (!reorderOnly && pick != null) {
      final ok = [
        for (final id in seen)
          if (matches(pick, id, controller: p, place: Place.deck)) id,
      ];
      if (ok.isNotEmpty) {
        final max = pickCount < ok.length ? pickCount : ok.length;
        final take = ask(Decision(kind: DecisionKind.cards, player: p, prompt: mustPick ? 'Put $max into your hand' : 'Put up to $max into your hand', options: ok, min: mustPick ? max : 0, max: max, source: ctx.source));
        for (final id in take) {
          _moveTo(id, Place.hand);
          rest.remove(id);
          log('${state.player(p).name} puts ${nameOf(id)} into their hand.', player: p, card: id, kind: 'draw');
        }
      }
    }
    if (restInk) {
      for (final id in rest) {
        _moveTo(id, Place.inkwell);
        state.obj(id).exerted = true;
      }
      state.version++;
      return;
    }
    if (rest.length > 1) {
      rest = ask(
        Decision(
          kind: DecisionKind.order,
          player: p,
          prompt: reorderOnly ? 'Put them back on top in any order (first = top)' : 'Put the rest on the ${restBottom ? 'bottom' : 'top'} in any order',
          options: rest,
          source: ctx.source,
        ),
      );
    }
    for (final id in rest) {
      deck.remove(id);
    }
    if (reorderOnly || !restBottom) {
      deck.insertAll(0, rest);
    } else {
      deck.addAll(rest);
    }
    state.version++;
  }

  // -------------------------------------------------------------------------------------------
  // Damage and banishing (CR 1.9, 1.8.1.4)
  // -------------------------------------------------------------------------------------------

  /// Deals damage (Resist reduces it, CR 8.8) or puts damage counters ([put]).
  void _dealDamage(CardId id, int n, {required CardId source, bool challenge = false, bool put = false}) {
    final o = state.objOrNull(id);
    if (o == null || o.zone != Place.play) return;
    var dmg = n;
    if (!put) {
      final c = chars(id);
      if (c.has(Kw.resist)) dmg -= c.n(Kw.resist);
      if (c.rules.contains(Rule.cantBeDealtDamage)) dmg = 0;
      dmg = _s3PreventDamage(id, dmg);
      dmg = _w2Damage(id, dmg, source, challenge);
    }
    if (dmg <= 0) return;
    if (!put && _w1Redirect(id, dmg, source)) return;
    o.damage += dmg;
    _lastDamageBy[id] = (source, challenge);
    state.version++;
    log('${nameOf(id)} takes $dmg damage.', card: id, kind: 'damage', amount: dmg);
    _emit(_Ev(kind: _EvKind.dealtDamage, card: id, other: source, player: o.owner, amount: dmg));
    if (challenge && state.objOrNull(source)?.zone == Place.play) {
      _emit(_Ev(kind: _EvKind.dealsChallengeDamage, card: source, other: id, player: state.obj(source).owner, amount: dmg));
    }
  }

  /// Banishes a card from play (it goes to the discard with its stack).
  void _banish(CardId id, {CardId? by, bool byDamage = false}) {
    final o = state.objOrNull(id);
    if (o == null || o.zone != Place.play || _w2BanishInstead(id)) return;
    final c = chars(id);
    final dmg = byDamage ? _lastDamageBy[id] : null;
    final inChallenge = dmg != null && dmg.$2;
    final banisher = dmg?.$1 ?? by;
    log('${c.card.fullName} is banished.', player: o.owner, card: id, kind: 'banish');
    // Where it was, for "whenever a character is banished while here".
    final info = EventInfo(card: id, other: banisher, player: o.owner, amount: o.under.length, strength: c.strength, location: o.at, under: List.of(o.under), hereExerted: _s4ExertedHere(id));
    _leavePlay(id, Place.discard);
    if (inChallenge && c.type == CardType.character) state.banishedInChallengeThisTurn++;
    state.banishedThisTurn.add('${c.card.fullName}|${o.owner}|${inChallenge ? 'c' : ''}');
    _emit(_Ev(kind: inChallenge ? _EvKind.banishedInChallenge : _EvKind.banished, card: id, other: banisher, player: o.owner, info: info, cardType: c.type));
    if (inChallenge && banisher != null && state.objOrNull(banisher)?.zone == Place.play) {
      _emit(_Ev(kind: _EvKind.banishesInChallenge, card: banisher, other: id, player: state.obj(banisher).owner));
    }
  }

  void _leavePlay(CardId id, Place to, {bool bottom = false, bool exerted = false}) {
    _lastDamageBy.remove(id);
    final o = state.obj(id);
    final wasInPlay = o.zone == Place.play && state.player(o.owner).play.contains(id);
    _moveTo(id, to, bottom: bottom, exerted: exerted);
    // "When this character leaves play" (CR 7.4.3).
    if (wasInPlay) _emit(_Ev(kind: _EvKind.leftPlay, card: id, player: o.owner));
  }

  String _describeEffect(Effect e) => switch (e) {
    Draw() => 'draw',
    Discard() => 'discard',
    GainLore() => 'gain lore',
    DealDamage() => 'deal damage',
    Banish() => 'banish',
    ReturnToHand() => 'return a card to hand',
    Exert() => 'exert',
    Ready() => 'ready',
    Modify() => 'boost a character',
    Seq(:final steps) => steps.map(_describeEffect).join(', then '),
    RemoveDamage() => 'remove damage',
    PlayFree() => 'play a card for free',
    InkTopOfDeck() || InkFromHand() || ToInkwell() => 'add to your inkwell',
    FromDiscardToHand() => 'return a card from your discard',
    _ => 'use this effect',
  };
}
