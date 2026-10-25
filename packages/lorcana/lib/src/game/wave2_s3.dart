part of 'game.dart';

/// What a [Tally] counted, per resolving effect (an identity map, so it never affects the order
/// of anything).
final _s3Tallies = Expando<Map<Tallied, int>>();

/// The cost of the character banished to pay for an activated ability ("cost up to 2 more than
/// the banished character").
final _s3Banished = Expando<int>();

/// The effects of ir_wave2_s3.dart and the rules they change: playing, inking, singing, moving,
/// questing and challenging. Effects that wait for something later ("the next time …", "after
/// the challenge") and what this turn has seen are kept as [Timed] marks labelled `s3:…`, so
/// they are part of the digest, are cloned with the state and end with their duration.
extension GameS3 on Game {
  // -------------------------------------------------------------------------------------------
  // Marks
  // -------------------------------------------------------------------------------------------

  Iterable<Timed> _marks(String kind) => state.timed.where((t) => t.label == 's3:$kind');

  void _mark(String kind, {required int controller, CardId source = 0, Lasting lasting = Lasting.thisTurn, List<CardId>? cards, int amount = 0, Keyword? keyword, Rule? rule, Filter? filter}) {
    state.timed.add(
      Timed(
        ts: state.nextTs++,
        controller: controller,
        source: source,
        lasting: lasting,
        turn: state.turn,
        cards: cards,
        amount: amount,
        keyword: keyword,
        rule: rule,
        filter: filter,
        label: 's3:$kind',
      ),
    );
    state.version++;
  }

  /// Active statics of type [T]: (source, effect, controller).
  List<(CardId, T, int)> _s3Statics<T extends StaticEffect>() => [
    for (final (src, e, ctl) in _activeStatics())
      if (e is T) (src, e, ctl),
  ];

  /// Keeps what this turn has seen for the conditions, and fires what waited for an event.
  void _s3OnEvent(_Ev e) {
    switch (e.kind) {
      case _EvKind.challenges:
        final a = e.card!, d = e.other!;
        _mark('inChallenge', controller: e.player!, cards: [a, d]);
        if (!_marks('challenger').any((t) => t.cards!.first == a)) _mark('challenger', controller: e.player!, cards: [a]);
        // "The next time they challenge another character this turn, gain 1 lore."
        for (final t in _marks(MarkKind.loreOnNextChallenge.name).toList()) {
          if (!t.cards!.contains(a) || db[state.obj(d).card]!.type != CardType.character) continue;
          state.timed.remove(t);
          _addToBag(
            t.controller,
            t.source,
            Triggered('Next challenge', const CardEvent(Event.challenges), GainLore(Who.you, Fixed(t.amount))),
            EventInfo(card: a, other: d, player: e.player),
            -1,
            floating: true,
          );
        }
      case _EvKind.putUnder:
        final p = e.player;
        if (p != null && !_marks('putUnder').any((t) => t.controller == p)) _mark('putUnder', controller: p);
      case _EvKind.dealtDamage:
        final p = e.player;
        if (p != null && e.card != null && db[state.obj(e.card!).card]!.type == CardType.character && !_marks('damaged').any((t) => t.controller == p)) _mark('damaged', controller: p);
      case _EvKind.banishedInChallenge:
        // A gained "When this character is banished in a challenge, return this card to your hand".
        for (final t in _marks(MarkKind.returnIfBanishedInChallenge.name).toList()) {
          if (!t.cards!.contains(e.card)) continue;
          final owner = state.obj(e.card!).owner;
          _addToBag(
            owner,
            e.card!,
            Triggered('Return to hand', const CardEvent(Event.banishedInChallenge), const ReturnToHand(This())),
            e.info ?? EventInfo(card: e.card, player: owner),
            -1,
            floating: true,
          );
        }
      default:
    }
  }

  // -------------------------------------------------------------------------------------------
  // Effects
  // -------------------------------------------------------------------------------------------

  void _resolveS3(S3Effect e, _Ctx ctx) {
    final s = state;
    final me = ctx.controller;
    switch (e) {
      case ExertInkwell(:final who):
        for (final p in _players(who, ctx)) {
          for (final id in s.player(p).inkwell) {
            s.obj(id).exerted = true;
          }
          log('${s.player(p).name} exerts all cards in their inkwell.', player: p, kind: 'exert');
        }
        s.version++;
      case InkwellToHand(:final n):
        final ink = s.player(me).inkwell;
        var k = 0;
        for (; k < n && ink.isNotEmpty; k++) {
          _moveTo(ink[s.rng.nextInt(ink.length)], Place.hand);
        }
        if (k > 0) log('${s.player(me).name} returns $k card${k == 1 ? '' : 's'} at random from their inkwell to their hand.', player: me, kind: 'return');
      case Tally(:final effect, :final what):
        int n;
        if (what == Tallied.movedCharacters) {
          final before = {for (final id in s.player(me).play) id: s.obj(id).at};
          _resolveEffect(effect, ctx);
          n = s.player(me).play.where((id) => before.containsKey(id) && before[id] != s.obj(id).at).length;
        } else {
          final before = _s3Count(what, me);
          _resolveEffect(effect, ctx);
          n = before - _s3Count(what, me);
        }
        (_s3Tallies[ctx] ??= {})[what] = n < 0 ? 0 : n;
      case PlayFreeFrom(:final filter, :final from, :final slot, :final exerted, :final upToBanishedPlus):
        final maxCost = upToBanishedPlus == null ? null : (_s3Banished[ctx] ?? -100) + upToBanishedPlus;
        final cands = [
          for (final place in from)
            for (final id in matching(filter, controller: me, source: ctx.source, place: place, whose: Owner.yours))
              if (id != ctx.source && (maxCost == null || db[s.obj(id).card]!.cost <= maxCost)) id,
        ];
        ctx.didIt = false;
        if (cands.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: me, prompt: 'Play one for free', options: cands, min: 1, max: 1, source: ctx.source)).first;
        _enterPlay(me, pick, free: true, exerted: exerted);
        if (slot != null) ctx.slots[slot] = [pick];
        ctx.didIt = true;
      case PlayPaying(:final target):
        final id = switch (target) {
          This() => ctx.source,
          EventCard(:final other) => other ? ctx.event?.other : ctx.event?.card,
          _ => null,
        };
        ctx.didIt = false;
        if (id == null || s.objOrNull(id)?.zone != Place.discard || s.obj(id).owner != me) return;
        final cost = playCost(me, id);
        if (_inkReady(me) < cost) {
          log('${s.player(me).name} can’t pay for ${nameOf(id)}.', player: me, card: id);
          return;
        }
        _payInk(me, cost);
        _emit(_Ev(kind: _EvKind.inkPaid, card: id, player: me, amount: cost));
        _enterPlay(me, id);
        ctx.didIt = true;
      case MoveDamageFromEach(:final to, :final n):
        final dest = _resolveTargets(to, ctx);
        if (dest.isEmpty) return;
        var moved = 0;
        for (final p in _turnOrder()) {
          for (final id in s.player(p).play) {
            if (id == dest.first || chars(id).type != CardType.character) continue;
            final k = s.obj(id).damage < n ? s.obj(id).damage : n;
            s.obj(id).damage -= k;
            moved += k;
          }
        }
        s.obj(dest.first).damage += moved;
        s.version++;
        if (moved > 0) log('$moved damage moves to ${nameOf(dest.first)}.', card: dest.first, kind: 'damage', amount: moved);
      case RevealDiscardOwnChoice(:final who, :final filter):
        for (final p in _players(who, ctx)) {
          final pl = s.player(p);
          log(pl.hand.isEmpty ? '${pl.name} reveals an empty hand.' : '${pl.name} reveals their hand: ${pl.hand.map(nameOf).join(', ')}.', player: p);
          final cands = [
            for (final id in pl.hand)
              if (_zoneMatches(filter, id, ctx, Place.hand)) id,
          ];
          if (cands.isEmpty) continue;
          _discardCards(p, ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose a ${filter.describe()} card to discard', options: cands, min: 1, max: 1, source: ctx.source)));
        }
      case Mark(:final kind, :final lasting, :final target, :final amount):
        List<CardId>? ids;
        if (target != null) {
          ids = _resolveTargets(target, ctx);
          if (ids.isEmpty) return;
        }
        _mark(kind.name, controller: me, source: ctx.source, lasting: lasting, cards: ids, amount: amount);
      case ForChallenge(:final target, :final keyword, :final rule):
        final ids = _resolveTargets(target, ctx);
        if (ids.isNotEmpty) _mark('challenge', controller: me, source: ctx.source, cards: ids, keyword: keyword, rule: rule);
      case RuleForAll(:final filter, :final rule, :final lasting):
        _mark('all', controller: me, source: ctx.source, lasting: lasting, filter: filter, rule: rule);
      case PutTopUnder(:final target):
        final hosts = _resolveTargets(target, ctx);
        ctx.didIt = false;
        if (hosts.isEmpty || s.player(me).deck.isEmpty) return;
        _s3Tuck(s.player(me).deck.first, hosts.first, me);
        log('A card goes facedown under ${nameOf(hosts.first)}.', player: me, card: hosts.first, kind: 'ability');
        ctx.didIt = true;
      case PutSelfUnder(:final filter):
        final src = ctx.source;
        if (s.objOrNull(src)?.zone != Place.play) return;
        final cands = [
          for (final id in matching(filter, controller: me, source: src))
            if (id != src) id,
        ];
        if (cands.isEmpty) return;
        final host = ask(Decision(kind: DecisionKind.cards, player: me, prompt: 'Choose one to put ${nameOf(src)} under', options: cands, min: 1, max: 1, source: src)).first;
        _s3Tuck(src, host, me);
        _emit(_Ev(kind: _EvKind.leftPlay, card: src, player: me));
        log('${nameOf(src)} goes facedown under ${nameOf(host)}.', player: me, card: host, kind: 'ability');
      case PeekFor(:final n, :final peek):
        final k = _evalAmount(n, ctx);
        if (k > 0) _peek(Peek(k, who: peek.who, picks: peek.picks, rest: peek.rest, ownerDecides: peek.ownerDecides, reveal: peek.reveal), ctx);
      case DiscardDownTo(:final who, :final n):
        for (final p in _players(who, ctx)) {
          final hand = s.player(p).hand;
          final k = hand.length - n;
          if (k <= 0) continue;
          _discardCards(p, ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Discard $k card${k == 1 ? '' : 's'} (down to $n)', options: List.of(hand), min: k, max: k, source: ctx.source)));
        }
      case IgnoreResist(:final damage):
        final n = _evalAmount(damage.amount, ctx);
        final ids = _resolveTargets(damage.target, ctx);
        for (final id in ids) {
          final c = chars(id);
          _dealDamage(id, n + (c.has(Kw.resist) ? c.n(Kw.resist) : 0), source: ctx.source);
        }
        ctx.didIt = ids.isNotEmpty;
      case DealSameToOthers(:final count, :final upTo):
        final n = ctx.event?.amount ?? 0;
        final cands = [
          for (final id in matching(const Filter(), controller: me, source: ctx.source))
            if (id != ctx.source && id != ctx.event?.other && !(s.obj(id).owner != me && chars(id).has(Kw.ward))) id,
        ];
        if (cands.isEmpty || n <= 0) return;
        final max = count < cands.length ? count : cands.length;
        final pick = ask(
          Decision(kind: DecisionKind.cards, player: me, prompt: 'Choose ${upTo ? 'up to ' : ''}$max to deal $n damage to', options: cands, min: upTo ? 0 : max, max: max, source: ctx.source),
        );
        for (final id in pick) {
          if (s.obj(id).owner != me) _emit(_Ev(kind: _EvKind.chosenByOpponent, card: id, player: me));
        }
        for (final id in pick) {
          _dealDamage(id, n, source: ctx.source);
        }
        ctx.didIt = pick.isNotEmpty;
      case ShuffleDeck():
        s.rng.shuffle(s.player(me).deck);
        s.version++;
        log('${s.player(me).name} shuffles their deck.', player: me);
      case RevealTopPlay(:final filter, :final otherwise):
        final deck = s.player(me).deck;
        if (deck.isEmpty) return;
        final top = deck.first;
        log('${s.player(me).name} reveals ${nameOf(top)}.', player: me, card: top);
        if (_zoneMatches(filter, top, ctx, Place.deck)) {
          if (askYesNo(me, 'Play ${nameOf(top)} for free?', source: ctx.source)) _enterPlay(me, top, free: true);
        } else {
          deck
            ..remove(top)
            ..add(top);
          s.version++;
          _resolveEffect(otherwise, ctx);
        }
      case Exactly(effect: final inner):
        final (have, need) = switch (inner) {
          FromDiscard(:final filter, :final count) => (matching(filter, controller: me, source: ctx.source, place: Place.discard, whose: Owner.yours).length, count),
          Discard(:final amount) => (s.player(me).hand.length, _evalAmount(amount, ctx)),
          _ => (0, 1),
        };
        if (have < need) {
          ctx.didIt = false;
          return;
        }
        _resolveEffect(inner, ctx);
      case NextCostLess(:final filter, :final amount):
        final n = _evalAmount(amount, ctx);
        if (n > 0) s.reductions.add(NextReduction(me, filter, n, s.turn));
      case Gated(effect: final inner) || OncePerTurn(effect: final inner):
        _resolveEffect(inner, ctx);
    }
  }

  /// Puts [id] (the top of a deck, or a card in play) facedown under [host] (CR 8.4.2); it isn't
  /// in play or in the discard afterwards.
  void _s3Tuck(CardId id, CardId host, int p) {
    final o = state.obj(id);
    _moveTo(id, Place.discard);
    state.player(o.owner).discard.remove(id);
    state.player(o.owner).discardedThisTurn--;
    o
      ..zone = Place.play
      ..faceDown = true;
    state.obj(host).under.insert(0, id);
    state.version++;
    _emit(_Ev(kind: _EvKind.putUnder, card: host, player: p));
  }

  /// A number the [Tally]ed effect lowers by what it did.
  int _s3Count(Tallied what, int me) {
    final s = state;
    return switch (what) {
      Tallied.damageRemoved => s.players.fold<int>(0, (n, pl) => n + pl.play.fold<int>(0, (m, id) => m + s.obj(id).damage)),
      Tallied.itemsToDiscard => -s.player(me).discard.where((id) => db[s.obj(id).card]!.type == CardType.item).length,
      Tallied.itemsBanished => s.player(me).play.where((id) => db[s.obj(id).card]!.type == CardType.item).length,
      Tallied.loreLostByOpponents => s.opponents(me).fold<int>(0, (n, q) => n + s.player(q).lore),
      Tallied.movedCharacters => 0,
    };
  }

  // -------------------------------------------------------------------------------------------
  // Amounts and conditions
  // -------------------------------------------------------------------------------------------

  int _s3Amount(S3Amount a, _Ctx ctx) {
    final s = state;
    switch (a) {
      case EventAmount():
        return ctx.event?.amount ?? 0;
      case Capped(:final amount, :final max):
        final n = _evalAmount(amount, ctx);
        return n > max ? max : n;
      case TallyOf(:final what, :final per):
        return per * (_s3Tallies[ctx]?[what] ?? 0);
      case DamageOnAll(:final filter, :final per):
        return per * matching(filter, controller: ctx.controller, source: ctx.source).fold<int>(0, (n, id) => n + s.obj(id).damage);
      case BanishedInChallengeCount(:final whose, :final per):
        var n = 0;
        for (final b in s.banishedThisTurn) {
          final parts = b.split('|');
          if (parts[2] != 'c' || db[parts[0]]?.type != CardType.character) continue;
          final owner = int.parse(parts[1]);
          if (whose == Owner.opposing && owner == ctx.controller) continue;
          if (whose == Owner.yours && owner != ctx.controller) continue;
          n++;
        }
        return per * n;
      case StatOfChosen(:final target, :final stat):
        final ids = _resolveTargets(target, ctx);
        if (ids.isEmpty) return 0;
        final c = chars(ids.first);
        return switch (stat) {
          Stat.strength => c.strengthAtLeast0,
          Stat.willpower => c.willpower,
          Stat.lore => c.loreAtLeast0,
        };
    }
  }

  bool _s3Cond(S3Cond c, _Ctx ctx) {
    final s = state;
    final me = ctx.controller;
    switch (c) {
      case AllInkExerted():
        return s.player(me).inkwell.every((id) => s.obj(id).exerted);
      case InkedThisTurn(:final cmp, :final n):
        final v = s.player(me).inkPutThisTurn;
        return switch (cmp) {
          Cmp.eq => v == n,
          Cmp.ge => v >= n,
          Cmp.le => v <= n,
          Cmp.gt => v > n,
          Cmp.lt => v < n,
        };
      case OpponentMoreLore():
        return s.opponents(me).any((q) => !s.player(q).lost && s.player(q).lore > s.player(me).lore);
      case PutUnderThisTurn():
        return _marks('putUnder').any((t) => t.controller == me);
      case AsChallenger():
        return _marks('inChallenge').any((t) => t.cards!.first == ctx.source);
      case OpposingDamagedThisTurn():
        return _marks('damaged').any((t) => t.controller != me);
    }
  }

  // -------------------------------------------------------------------------------------------
  // Rules the marks and statics change
  // -------------------------------------------------------------------------------------------

  /// "The next time they would be dealt damage they take no damage instead."
  int _s3PreventDamage(CardId id, int dmg) {
    if (dmg <= 0) return dmg;
    final t = _marks(MarkKind.damageShield.name).where((t) => t.cards!.contains(id)).firstOrNull;
    if (t == null) return dmg;
    state.timed.remove(t);
    state.version++;
    log('${nameOf(id)} takes no damage.', card: id);
    return 0;
  }

  /// "Can't quest or challenge unless you pay 1 {i}": paid as the character quests or
  /// challenges.
  void _s3BeforeAction(LMove move) {
    final card = switch (move) {
      QuestMove(:final card) => card,
      ChallengeMove(:final card) => card,
      _ => null,
    };
    if (card == null) return;
    final n = _s3PayToAct(card);
    if (n > 0) {
      _payInk(move.seat, n);
      log('${state.player(move.seat).name} pays $n ink for ${nameOf(card)}.', player: move.seat, card: card, kind: 'ink');
    }
  }

  int _s3PayToAct(CardId card) => _s3Statics<PayToQuestOrChallenge>().where((x) => x.$1 == card).fold<int>(0, (n, x) => n + x.$2.n);

  String? _s3QuestProblem(int p, CardId card) {
    final n = _s3PayToAct(card);
    if (n > 0 && _inkReady(p) < n) return '${nameOf(card)} needs $n ink to quest';
    return null;
  }

  String? _s3ChallengeProblem(int p, CardId attacker, CardId target) {
    final n = _s3PayToAct(attacker);
    if (n > 0 && _inkReady(p) < n) return '${nameOf(attacker)} needs $n ink to challenge';
    // "Each turn, only one character can challenge."
    if (_s3Statics<OneChallengerPerTurn>().isNotEmpty && _marks('challenger').any((t) => t.cards!.first != attacker)) return 'Only one character can challenge each turn';
    return null;
  }

  String? _s3PlayProblem(PlayMove m) {
    final s = state;
    final o = s.objOrNull(m.card);
    if (o == null || o.zone != Place.hand) return null;
    final c = db[o.card]!;
    if (c.type == CardType.action && _marks(MarkKind.noActions.name).any((t) => t.controller != m.seat)) return 'Opponents can’t play actions until the start of their next turn';
    for (final a in LorcanaParser.parse(c).abilities) {
      if (a is Static && a.effect is CantPlayUnless && !_evalCond((a.effect as CantPlayUnless).cond, _Ctx(this, controller: m.seat, source: m.card))) return 'You can’t play ${c.name} yet';
    }
    return null;
  }

  bool _s3InkFromDiscard(int p) => _s3Statics<InkFromDiscard>().any((x) => x.$3 == p);

  List<CardId> _s3InkableFromDiscard(int p) => _s3InkFromDiscard(p)
      ? [
          for (final id in state.player(p).discard)
            if (db[state.obj(id).card]!.inkable) id,
        ]
      : const [];

  int _s3ExtraInk(int p) => _marks(MarkKind.extraInk.name).where((t) => t.controller == p).length;

  int _s3SingBonus(CardId singer) {
    var n = 0;
    for (final t in _marks(MarkKind.singBonus.name)) {
      if (t.cards!.contains(singer)) n += t.amount;
    }
    for (final (src, e, ctl) in _s3Statics<SingCost>()) {
      if (matches(e.filter, singer, controller: ctl, source: src)) n += e.n;
    }
    return n;
  }

  int _s3ShiftLess(int p) => _marks(MarkKind.shiftLess.name).where((t) => t.controller == p).fold<int>(0, (n, t) => n + t.amount);

  void _s3ShiftUsed(int p) {
    state.timed.removeWhere((t) => t.label == 's3:${MarkKind.shiftLess.name}' && t.controller == p);
  }

  /// "The next character you play this turn enters play exerted and gains Bodyguard until the
  /// start of your next turn."
  void _s3Entering(int p, CardId id) {
    if (db[state.obj(id).card]!.type != CardType.character) return;
    final marks = _marks(MarkKind.nextEntersExertedBodyguard.name).where((t) => t.controller == p).toList();
    if (marks.isEmpty) return;
    state.timed.removeWhere(marks.contains);
    state.obj(id).exerted = true;
    state.timed.add(Timed(ts: state.nextTs++, controller: p, source: marks.first.source, lasting: Lasting.untilYourNextTurn, turn: state.turn, cards: [id], keyword: const Keyword(Kw.bodyguard)));
    state.version++;
  }

  bool _s3CantReady(CardId id) => _marks(MarkKind.cantReadyUnlessAtLocation.name).any((t) => t.cards!.contains(id) && t.turn < state.turn && state.obj(id).at == null);

  /// "Your characters get +3 {s} while challenging a location this turn."
  void _s3Chars(CardId id, LChars ch) {
    final pair = _challengePair;
    if (pair == null || pair.$1 != id || db[state.obj(pair.$2).card]!.type != CardType.location) return;
    for (final t in _marks(MarkKind.challengingLocationBonus.name)) {
      if (t.controller == ch.owner) ch.strength += t.amount;
    }
  }

  /// The end of a challenge: "during that challenge" effects end, "after the challenge" ones
  /// happen.
  void _s3ChallengeOver() {
    final s = state;
    final ready = [for (final t in _marks(MarkKind.readyAfterChallenge.name)) ...t.cards!];
    s.timed.removeWhere((t) => t.label == 's3:inChallenge' || t.label == 's3:challenge' || t.label == 's3:${MarkKind.readyAfterChallenge.name}');
    s.version++;
    for (final id in ready) {
      if (s.objOrNull(id)?.zone != Place.play || !s.obj(id).exerted) continue;
      s.obj(id).exerted = false;
      log('${nameOf(id)} is readied.', card: id, kind: 'ready');
      _emit(_Ev(kind: _EvKind.readied, card: id, player: s.obj(id).owner));
    }
  }

  /// Ink less to move [character] to [location] (CR 4.7): free moves count as all of it.
  int _s3MoveLess(int p, CardId character, CardId location, {bool once = true}) {
    var n = 0;
    for (final (src, e, ctl) in _s3Statics<MoveCost>()) {
      if (e.once && (!once || _marks('moveOnce').any((t) => t.cards!.first == src))) continue;
      if (!_s3MoveApplies(e, src, ctl, p, character, location)) continue;
      n += e.free ? 1 << 20 : e.less;
    }
    return n;
  }

  bool _s3MoveApplies(MoveCost e, CardId src, int ctl, int p, CardId character, CardId location) {
    if (e.here && location != src) return false;
    return e.filter == null ? character == src : (ctl == p && matches(e.filter!, character, controller: ctl, source: src));
  }

  /// A "once during your turn" discount is used up when it lowered what was paid.
  void _s3Moved(int p, CardId character, CardId location) {
    final base = (db[state.obj(location).card]!.moveCost ?? 0) - _s3MoveLess(p, character, location, once: false);
    if (base <= 0) return;
    for (final (src, e, ctl) in _s3Statics<MoveCost>()) {
      if (!e.once || _marks('moveOnce').any((t) => t.cards!.first == src) || !_s3MoveApplies(e, src, ctl, p, character, location)) continue;
      _mark('moveOnce', controller: p, cards: [src]);
    }
  }

  String? _s3ActivateProblem(int p, CardId id, int index, Activated a) {
    var e = a.effect;
    while (true) {
      if (e is OncePerTurn) {
        if (state.obj(id).usedOn[index] == state.turn) return 'Once per turn';
        e = e.effect;
      } else if (e is Gated) {
        if (!_evalCond(e.cond, _Ctx(this, controller: p, source: id))) return 'Not now';
        e = e.effect;
      } else {
        return null;
      }
    }
  }

  void _s3Activating(CardId id, int index, Activated a) {
    if (a.effect is OncePerTurn) state.obj(id).usedOn[index] = state.turn;
  }

  void _s3CostBanished(_Ctx ctx, CardId id) => _s3Banished[ctx] = db[state.obj(id).card]!.cost;

  /// Whether the top card of [owner]'s deck is faceup ("each opponent plays with the top card of
  /// their deck faceup"), for the table to show.
  bool topCardFaceUp(int owner) => _s3Statics<TopCardFaceUp>().any((x) => x.$3 != owner);
}
