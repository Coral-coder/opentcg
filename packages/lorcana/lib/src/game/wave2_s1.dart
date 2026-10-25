part of 'game.dart';

/// Wave 2, slice 1 (ir_wave2_s1.dart): granted abilities, keywords, rules and classifications,
/// the payment and play rules some cards change, choices other players make, searching decks,
/// and the "this way" counts effects refer back to. Hooked into the engine with one-line calls.

/// What the effect so far did "this way" (CR 6.1.5.1), per resolution: the count, then the cards
/// damage was removed from.
final _w1Way = Expando<List<int>>('w1 this way');

/// Per card name: which kinds of wave 2 statics it has (see the bits below), so the hooks can
/// skip work when no such card is in play.
final Map<String, int> _w1Flags = {};

const _w1GrantAbilityBit = 1, _w1GrantClassBit = 2, _w1CharsBit = 4;

extension GameWave2S1 on Game {
  static bool _classGuard = false;

  int _w1FlagsOf(String card) => _w1Flags.putIfAbsent(card, () {
    var f = 0;
    for (final a in LorcanaParser.parse(db[card]!).abilities) {
      if (a is! Static) continue;
      final e = a.effect;
      if (e is W1GrantAbility) f |= _w1GrantAbilityBit;
      if (e is W1GrantClass) f |= _w1GrantClassBit;
      if (e is W1ModIfStrength || e is W1StrengthFloor) f |= _w1CharsBit;
    }
    return f;
  });

  bool _w1InPlay(int bit) {
    for (final p in state.players) {
      for (final id in p.play) {
        if (_w1FlagsOf(state.obj(id).card) & bit != 0) return true;
      }
    }
    return false;
  }

  /// Wave 2 statics of cards in play whose condition holds: (source, effect, controller).
  Iterable<(CardId, W1Static, int)> _w1Active() sync* {
    for (final (src, st, ctl) in _statics()) {
      final e = st.effect;
      if (e is! W1Static) continue;
      if (st.condition != null && !_evalCond(st.condition!, _Ctx(this, controller: ctl, source: src))) continue;
      yield (src, e, ctl);
    }
  }

  bool _w1NotedThisTurn(String key) => state.w1[key]?.firstOrNull == state.turn;

  // -------------------------------------------------------------------------------------------
  // Events and turns
  // -------------------------------------------------------------------------------------------

  /// Notes what later effects ask about: who sang the last song, who discarded this turn.
  void _w1Observe(_Ev e) {
    switch (e.kind) {
      case _EvKind.sings:
        final song = e.other, singer = e.card;
        if (song == null || singer == null) return;
        final cur = state.w1['sing'];
        state.w1['sing'] = cur != null && cur.isNotEmpty && cur.first == song ? [...cur, singer] : [song, singer];
      case _EvKind.discarded:
        if (e.player != null) state.w1['discarded${e.player}'] = [state.turn];
      default:
    }
  }

  /// A card left a discard (for "if a card left a player's discard this turn").
  void _w1LeftDiscard() => state.w1['leftDiscard'] = [state.turn];

  /// Start of turn: "until the start of your next turn" grants end (CR 6.1.13.3).
  void _w1StartTurn() {
    final s = state;
    s.w1Grants.removeWhere((g) => (g.lasting == Lasting.untilYourNextTurn && g.controller == s.active && g.turn < s.turn) || g.lasting == Lasting.thisTurn || !_w1Alive(g));
  }

  /// End of turn: "this turn" grants end (CR 3.4.1.2).
  void _w1EndTurn() => state.w1Grants.removeWhere((g) => g.lasting == Lasting.thisTurn || !_w1Alive(g));

  bool _w1Alive(W1Grant g) {
    if (g.whileSource) {
      final o = state.objOrNull(g.source);
      if (o == null || o.zone != Place.play || o.zcc != g.sourceZcc) return false;
    }
    for (var i = 0; i < g.cards.length; i++) {
      if (state.objOrNull(g.cards[i])?.zcc == g.zccs[i]) return true;
    }
    return false;
  }

  /// Is [g] on [id] now? [justLeft]: the card has just left play and its own "when this
  /// character is banished" grants still count (CR 7.4.3).
  bool _w1GrantOn(W1Grant g, CardId id, {bool justLeft = false}) {
    final i = g.cards.indexOf(id);
    if (i < 0) return false;
    final o = state.objOrNull(id);
    if (o == null) return false;
    if (o.zcc != g.zccs[i] && !(justLeft && o.zcc == g.zccs[i] + 1)) return false;
    if (g.whileSource) {
      final src = state.objOrNull(g.source);
      if (src == null || src.zone != Place.play || src.zcc != g.sourceZcc) return false;
    }
    return true;
  }

  // -------------------------------------------------------------------------------------------
  // Granted abilities and classifications
  // -------------------------------------------------------------------------------------------

  /// Every ability [id] has now: its own, then the ones granted to it (activated abilities are
  /// used by their index in this list).
  List<Ability> abilitiesOf(CardId id) {
    final base = LorcanaParser.parse(db[state.obj(id).card]!).abilities;
    final more = _w1Granted(id);
    return more.isEmpty ? base : [...base, ...more];
  }

  /// [abilitiesOf] for triggers: a card that just left play keeps what it had (CR 7.4.3).
  List<Ability> _w1Abilities(CardId id, {bool leaving = false}) {
    final base = LorcanaParser.parse(db[state.obj(id).card]!).abilities;
    final more = _w1Granted(id, justLeft: leaving && state.obj(id).zone != Place.play);
    return more.isEmpty ? base : [...base, ...more];
  }

  List<Ability> _w1Granted(CardId id, {bool justLeft = false}) {
    final s = state;
    final statics = _w1InPlay(_w1GrantAbilityBit);
    if (s.w1Grants.isEmpty && !statics) return const [];
    final out = <Ability>[];
    for (final g in s.w1Grants) {
      if (g.ability != null && _w1GrantOn(g, id, justLeft: justLeft)) out.add(g.ability!);
    }
    final o = s.obj(id);
    if (statics && (o.zone == Place.play || justLeft)) {
      for (final (src, e, ctl) in _w1Active()) {
        if (e is W1GrantAbility && matches(e.affected, id, controller: ctl, source: src, place: o.zone)) out.add(e.ability);
      }
    }
    return out;
  }

  /// Does [id] have classification [cls] by a grant, or the ink when [cls] is "ink:…"?
  bool _w1HasClass(CardId id, String cls) {
    final o = state.objOrNull(id);
    if (o == null) return false;
    final lc = cls.toLowerCase();
    if (lc.startsWith(w1InkClass)) {
      final ink = lc.substring(w1InkClass.length);
      return db[o.card]!.inks.any((i) => i.name == ink);
    }
    for (final g in state.w1Grants) {
      if (g.cls != null && g.cls!.toLowerCase() == lc && _w1GrantOn(g, id)) return true;
    }
    if (o.zone != Place.play || _classGuard || !_w1InPlay(_w1GrantClassBit)) return false;
    _classGuard = true;
    try {
      for (final (src, e, ctl) in _w1Active()) {
        if (e is W1GrantClass && e.cls.toLowerCase() == lc && matches(e.affected, id, controller: ctl, source: src)) return true;
      }
    } finally {
      _classGuard = false;
    }
    return false;
  }

  /// Keywords and rules granted for a while, and the statics judged on final values (CR 6.6).
  void _w1ApplyChars(CardId id, LChars ch) {
    for (final g in state.w1Grants) {
      if (g.keyword == null && g.rule == null) continue;
      if (!_w1GrantOn(g, id)) continue;
      if (g.keyword != null) ch.addKeyword(g.keyword!);
      if (g.rule != null) ch.rules.add(g.rule!);
    }
    // Granted static abilities about the card itself ("This character can challenge ready
    // characters").
    for (final a in _w1Granted(id)) {
      if (a is! Static) continue;
      if (a.condition != null && !_evalCond(a.condition!, _Ctx(this, controller: ch.owner, source: id))) continue;
      switch (a.effect) {
        case StaticMod(affected: null, :final stat, :final amount, :final negative):
          _addStat(ch, stat, _evalAmount(amount, _Ctx(this, controller: ch.owner, source: id)) * (negative ? -1 : 1));
        case StaticKeyword(affected: null, :final keyword):
          ch.addKeyword(keyword);
        case StaticRule(affected: null, :final rule):
          ch.rules.add(rule);
        default:
      }
    }
    if (!_w1InPlay(_w1CharsBit)) return;
    final printed = ch.card.strength ?? 0;
    final active = _w1Active().toList();
    for (final (src, e, ctl) in active) {
      if (e is W1StrengthFloor && ch.strength < printed && matches(e.affected, id, controller: ctl, source: src)) ch.strength = printed;
    }
    for (final (src, e, ctl) in active) {
      if (e is W1ModIfStrength && ch.strength >= e.min && matches(e.affected, id, controller: ctl, source: src)) _addStat(ch, e.stat, e.n);
    }
  }

  /// Drops the statics a "lose the X ability" effect takes away (CR 6.4).
  List<(CardId, Static, int)> _w1DropLost(List<(CardId, Static, int)> list) {
    final losers = [
      for (final x in list)
        if (x.$2.effect is W1LoseAbility) x,
    ];
    if (losers.isEmpty) return list;
    bool lost((CardId, Static, int) x) {
      for (final (src, st, ctl) in losers) {
        final e = st.effect as W1LoseAbility;
        if (!x.$2.text.toLowerCase().startsWith(e.name)) continue;
        final f = e.affected;
        final o = state.obj(x.$1);
        final c = db[o.card]!;
        if (!f.types.contains(c.type)) continue;
        if (f.owner == Owner.yours && o.owner != ctl) continue;
        if (f.owner == Owner.opposing && o.owner == ctl) continue;
        if (f.other && x.$1 == src) continue;
        if (f.classes.isNotEmpty && !f.classes.any(c.hasClass)) continue;
        return true;
      }
      return false;
    }

    return [
      for (final x in list)
        if (!lost(x)) x,
    ];
  }

  /// "Opponents can't choose your items for abilities or effects".
  bool _w1Unchoosable(CardId id, int chooser) {
    final owner = state.obj(id).owner;
    if (owner == chooser) return false;
    for (final (src, e, ctl) in _w1Active()) {
      if (e is W1Unchoosable && ctl == owner && matches(e.affected, id, controller: ctl, source: src)) return true;
    }
    return false;
  }

  // -------------------------------------------------------------------------------------------
  // Paying and playing (CR 4.3)
  // -------------------------------------------------------------------------------------------

  /// Cost changes from other cards: "each player pays 2 {i} more to play actions or items",
  /// "once during your turn, you pay 1 {i} less for the next character you play".
  int _w1CostDelta(int p, CardId id) {
    var d = 0;
    final place = state.obj(id).zone;
    for (final (src, e, ctl) in _w1Active()) {
      if (e is W1CostIncrease && matches(e.filter, id, controller: p, source: src, place: place)) d += e.n;
      if (e is W1FirstDiscount && _w1FirstApplies(e, src, ctl, p, id)) d -= e.n;
    }
    return d;
  }

  bool _w1FirstApplies(W1FirstDiscount e, CardId src, int ctl, int p, CardId id) =>
      ctl == p && state.active == p && !_w1NotedThisTurn('first$src') && matches(e.filter.copyWith(owner: Owner.any), id, controller: p, source: src, place: state.obj(id).zone);

  /// After paying for [id] (still where it was played from): once-a-turn discounts are used.
  void _w1Paid(int p, CardId id) {
    for (final (src, e, ctl) in _w1Active().toList()) {
      if (e is W1FirstDiscount && _w1FirstApplies(e, src, ctl, p, id)) state.w1['first$src'] = [state.turn];
    }
  }

  /// Less to pay for Shift: from the card itself, the card it goes on, and once-a-turn discounts.
  int _w1ShiftDiscount(int p, CardId card, CardId? onto) {
    var d = 0;
    final ctx = _Ctx(this, controller: p, source: card);
    for (final a in LorcanaParser.parse(db[state.obj(card).card]!).abilities) {
      if (a is Static && a.effect is W1ShiftDiscount && (a.condition == null || _evalCond(a.condition!, ctx))) d += _evalAmount((a.effect as W1ShiftDiscount).amount, ctx);
    }
    if (onto != null && state.objOrNull(onto)?.zone == Place.play) {
      for (final a in LorcanaParser.parse(db[state.obj(onto).card]!).abilities) {
        if (a is Static && a.effect is W1ShiftOntoDiscount) d += (a.effect as W1ShiftOntoDiscount).n;
      }
    }
    for (final (src, e, ctl) in _w1Active()) {
      if (e is W1FirstDiscount && _w1FirstApplies(e, src, ctl, p, card)) d += e.n;
    }
    return d;
  }

  /// "If a card left a player's discard this turn, this character gains Shift 0" (in the hand).
  Keyword? _w1HandShift(CardId id) {
    final o = state.obj(id);
    if (o.zone != Place.hand) return null;
    final ctx = _Ctx(this, controller: o.owner, source: id);
    for (final a in LorcanaParser.parse(db[o.card]!).abilities) {
      if (a is Static && a.effect is W1HandShift && (a.condition == null || _evalCond(a.condition!, ctx))) return (a.effect as W1HandShift).keyword;
    }
    return null;
  }

  /// Why [id] can't be played now by these rules, or null.
  String? _w1PlayProblem(int p, CardId id) {
    final c = db[state.obj(id).card]!;
    final ctx = _Ctx(this, controller: p, source: id);
    for (final a in LorcanaParser.parse(c).abilities) {
      if (a is Static && a.effect is W1PlayOnlyIf && a.condition != null && !_evalCond(a.condition!, ctx)) return 'You can’t play ${c.name} now';
    }
    final place = state.obj(id).zone;
    for (final (src, e, ctl) in _w1Active()) {
      if (e is W1OpponentsCantPlay && ctl != p && matches(e.filter.copyWith(owner: Owner.any), id, controller: p, source: src, place: place)) return '${nameOf(src)}: ${c.name} can’t be played now';
    }
    return null;
  }

  List<CardId> _w1BanishOptions(int p, CardId id) {
    if (state.active != p) return const [];
    for (final a in LorcanaParser.parse(db[state.obj(id).card]!).abilities) {
      if (a is Static && a.effect is W1BanishToPlay) return matching((a.effect as W1BanishToPlay).filter, controller: p, source: id, whose: Owner.yours);
    }
    return const [];
  }

  bool _w1CanBanishToPlay(int p, CardId id) => _w1BanishOptions(p, id).isNotEmpty;

  /// "You may banish chosen item of yours to play this character for free": asked when the ink
  /// would do too; used when it wouldn't.
  bool _w1PayByBanishing(int p, CardId id, int cost) {
    final opts = _w1BanishOptions(p, id);
    if (opts.isEmpty) return false;
    if (_inkReady(p) >= cost && !askYesNo(p, 'Banish one of your items to play ${nameOf(id)} for free instead of paying $cost ink?', source: id)) return false;
    final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose an item to banish to play ${nameOf(id)} for free', options: opts, min: 1, max: 1, source: id));
    _banish(pick.first, by: id);
    return true;
  }

  /// "Characters count as having +2 cost to sing songs while here" (CR 8.11).
  int _w1SingBonus(CardId singer) {
    var n = 0;
    for (final (src, e, ctl) in _w1Active()) {
      if (e is W1SingCost && matches(e.affected, singer, controller: ctl, source: src)) n += e.n;
    }
    return n;
  }

  // -------------------------------------------------------------------------------------------
  // Damage, challenges, activated abilities, triggers
  // -------------------------------------------------------------------------------------------

  /// "Whenever one of your other characters would be dealt damage, put that many damage counters
  /// on this character instead" (CR 6.5): true when the damage went elsewhere.
  bool _w1Redirect(CardId id, int n, CardId source) {
    final o = state.obj(id);
    for (final (src, e, ctl) in _w1Active()) {
      if (e is! W1RedirectDamage || src == id || ctl != o.owner) continue;
      if (!matches(e.affected, id, controller: ctl, source: src)) continue;
      state.obj(src).damage += n;
      _lastDamageBy[src] = (source, false);
      state.version++;
      log('${nameOf(src)} takes $n damage counter${n == 1 ? '' : 's'} instead of ${nameOf(id)}.', card: src, kind: 'damage', amount: n);
      return true;
    }
    return false;
  }

  /// "This character can challenge ready Villain characters".
  bool _w1ChallengeReady(CardId attacker, CardId target) {
    final o = state.objOrNull(attacker);
    if (o == null || o.zone != Place.play) return false;
    final ctx = _Ctx(this, controller: o.owner, source: attacker);
    for (final a in LorcanaParser.parse(db[o.card]!).abilities) {
      if (a is! Static || a.effect is! W1ChallengeReady) continue;
      if (a.condition != null && !_evalCond(a.condition!, ctx)) continue;
      if (matches((a.effect as W1ChallengeReady).defenders, target, controller: o.owner, source: attacker)) return true;
    }
    return false;
  }

  String? _w1ActivateProblem(Activated a, Obj o, int index, int p) {
    if (a is! W1Activated) return null;
    if (a.yourTurn && state.active != p) return 'Only during your turn';
    if (a.oncePerTurn && o.usedOn[index] == state.turn) return 'Once during your turn';
    if (a.banish != null && matching(a.banish!, controller: p, source: o.id, whose: Owner.yours).where((x) => x != o.id).length < a.banishCount) return 'Not enough to banish for the cost';
    return null;
  }

  /// The parts of a cost beyond [Cost] (CR 4.4), paid with the rest.
  void _w1PayActivate(Activated a, int p, CardId id, int index) {
    if (a is! W1Activated) return;
    if (a.oncePerTurn) state.obj(id).usedOn[index] = state.turn;
    if (a.banish != null && a.banishCount > 0) {
      final opts = [
        for (final x in matching(a.banish!, controller: p, source: id, whose: Owner.yours))
          if (x != id) x,
      ];
      final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose ${a.banishCount} to banish for the cost', options: opts, min: a.banishCount, max: a.banishCount, source: id));
      for (final x in pick) {
        _banish(x, by: id);
      }
    }
  }

  bool _w1TriggerMatches(W1Trigger t, _Ev e, int you) {
    switch (t) {
      case W1Boosted():
        return e.kind == _EvKind.boosted && e.player == you;
      case W1ChallengedWithUnder():
        if (e.kind != _EvKind.isChallenged || e.card == null) return false;
        final o = state.objOrNull(e.card!);
        return o != null && o.zone == Place.play && o.owner == you && o.under.isNotEmpty && const {CardType.character, CardType.location}.contains(db[o.card]!.type);
    }
  }

  // -------------------------------------------------------------------------------------------
  // Amounts and conditions
  // -------------------------------------------------------------------------------------------

  int _w1Amount(W1Amount a, _Ctx ctx) {
    switch (a) {
      case W1ThisWay(:final per, :final plus):
        return per * (_w1Way[ctx]?.first ?? 0) + plus;
      case W1Singers():
        final l = state.w1['sing'];
        return l != null && l.isNotEmpty && l.first == ctx.source ? l.length - 1 : 0;
      case W1UnderEvent():
        return ctx.event?.amount ?? 0;
      case W1LocationLore():
        // The location the character chosen earlier ("move a character of yours to a location…
        // that location's {l}") or this character is at.
        final earlier = ctx.slots.isEmpty ? null : ctx.slots[ctx.slots.keys.first]!.firstOrNull;
        final at = state.objOrNull(earlier ?? ctx.source)?.at;
        return at == null || state.objOrNull(at)?.zone != Place.play ? 0 : chars(at).loreAtLeast0;
    }
  }

  /// Counts damage removed for "this way" (called by RemoveDamage).
  void _w1CountHeal(_Ctx ctx, CardId id, int n) {
    final l = _w1Way[ctx] ??= [0];
    l[0] += n;
    if (n > 0) l.add(id);
  }

  bool _evalW1Cond(W1Cond c, _Ctx ctx) => switch (c) {
    W1LeftDiscard() => _w1NotedThisTurn('leftDiscard'),
    W1DiscardedThisTurn() => _w1NotedThisTurn('discarded${ctx.controller}'),
    W1PlayedThisTurn(:final filter) => state.player(ctx.controller).playedThisTurn.any((id) {
      final cd = db[state.obj(id).card]!;
      return filter.types.contains(cd.type) && (filter.classes.isEmpty || filter.classes.any((x) => cd.hasClass(x) || _w1HasClass(id, x)));
    }),
    W1DidSome() => (_w1Way[ctx]?.first ?? 0) > 0,
    W1WillpowerCount(:final min, :final other) => matching(const Filter(), controller: ctx.controller, source: ctx.source, whose: Owner.yours).any((id) => (!other || id != ctx.source) && chars(id).willpower >= min),
  };

  // -------------------------------------------------------------------------------------------
  // Effects
  // -------------------------------------------------------------------------------------------

  void _resolveW1(W1Effect e, _Ctx ctx) {
    final s = state;
    final c = ctx.controller;
    final me = s.player(c);
    switch (e) {
      case W1HandToBottom(:final all, :final drawPlus):
        if (me.hand.isEmpty) {
          ctx.didIt = false;
          return;
        }
        var pick = all
            ? List.of(me.hand)
            : ask(Decision(kind: DecisionKind.cards, player: c, prompt: 'Choose any number of cards to put on the bottom of your deck', options: List.of(me.hand), min: 0, max: me.hand.length, source: ctx.source));
        if (pick.isEmpty) {
          ctx.didIt = false;
          return;
        }
        if (pick.length > 1) pick = ask(Decision(kind: DecisionKind.order, player: c, prompt: 'Order them for the bottom of your deck (first = highest)', options: pick, source: ctx.source));
        for (final id in pick) {
          _moveTo(id, Place.deck, bottom: true);
        }
        log('${me.name} puts ${pick.length} card${pick.length == 1 ? '' : 's'} from their hand on the bottom of their deck.', player: c);
        ctx.didIt = true;
        _w1Way[ctx] = [pick.length];
        if (drawPlus != null) {
          for (var i = 0; i < pick.length + drawPlus; i++) {
            _draw(c);
          }
        }
      case W1ReadySingers():
        final l = s.w1['sing'];
        final song = ctx.event?.card;
        if (l == null || l.isEmpty || song == null || l.first != song) return;
        for (final id in l.skip(1)) {
          final o = s.objOrNull(id);
          if (o == null || o.zone != Place.play || o.owner != c) continue;
          o.exerted = false;
          log('${nameOf(id)} is readied.', card: id, kind: 'ready');
          _emit(_Ev(kind: _EvKind.readied, card: id, player: c));
        }
        s.version++;
      case W1Search(:final filters, :final dest, :final shuffle):
        final deck = me.deck;
        final cands = [
          for (final id in deck)
            if (filters.any((f) => _zoneMatches(f, id, ctx, Place.deck))) id,
        ]..sortStable((a, b) => a - b);
        if (cands.isEmpty) {
          if (shuffle || dest == W1SearchDest.topAfterShuffle) s.rng.shuffle(deck);
          log('${me.name} searches their deck and finds nothing.', player: c);
          s.version++;
          ctx.didIt = false;
          return;
        }
        final pick = ask(Decision(kind: DecisionKind.cards, player: c, prompt: 'Choose a card to reveal', options: cands, min: 1, max: 1, source: ctx.source)).first;
        log('${me.name} reveals ${nameOf(pick)}.', player: c, card: pick);
        if (dest == W1SearchDest.hand) {
          _moveTo(pick, Place.hand);
          if (shuffle) s.rng.shuffle(deck);
        } else {
          deck.remove(pick);
          s.rng.shuffle(deck);
          deck.insert(0, pick);
        }
        s.version++;
        ctx.didIt = true;
      case W1Shuffle():
        s.rng.shuffle(me.deck);
        s.version++;
      case W1Pick(:final target):
        ctx.didIt = _resolveTargets(target, ctx).isNotEmpty;
      case W1LoreFromDiscard(:final filter):
        final cands = [
          for (final id in me.discard)
            if (_zoneMatches(filter, id, ctx, Place.discard)) id,
        ];
        final pick = cands.isEmpty ? const <CardId>[] : ask(Decision(kind: DecisionKind.cards, player: c, prompt: 'Gain lore equal to the lore of one of these (it then goes under your deck)', options: cands, min: 0, max: 1, source: ctx.source));
        if (pick.isEmpty) {
          ctx.didIt = false;
          return;
        }
        _gainLore(c, db[s.obj(pick.first).card]!.lore ?? 0, source: ctx.source);
        _moveTo(pick.first, Place.deck, bottom: true);
        log('${nameOf(pick.first)} goes on the bottom of ${me.name}’s deck.', player: c, card: pick.first);
        ctx.didIt = true;
      case W1RevealTake(:final amount, :final take):
        final seen = me.deck.take(_evalAmount(amount, ctx)).toList();
        if (seen.isEmpty) return;
        log('${me.name} reveals ${seen.map(nameOf).join(', ')}.', player: c, card: seen.first);
        final rest = <CardId>[];
        for (final id in seen) {
          if (_zoneMatches(take, id, ctx, Place.deck)) {
            _moveTo(id, Place.hand);
            log('${me.name} puts ${nameOf(id)} into their hand.', player: c, card: id, kind: 'draw');
          } else {
            rest.add(id);
          }
        }
        _placeRest(rest, ZoneDest.bottom, c, c, ctx);
      case W1PlaySameName():
        final src = s.objOrNull(ctx.source);
        if (src == null) return;
        final names = {for (final n in db[src.card]!.names) n.toLowerCase()};
        final cands = [
          for (final id in me.hand)
            if (db[s.obj(id).card]!.type == CardType.character && db[s.obj(id).card]!.names.any((n) => names.contains(n.toLowerCase()))) id,
        ];
        if (cands.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: c, prompt: 'Play one for free', options: cands, min: 1, max: 1, source: ctx.source));
        _enterPlay(c, pick.first, free: true);
        ctx.didIt = true;
      case W1RefreshPlayers(:final n):
        final chosen = <int>[
          for (final q in _turnOrder())
            if (!s.player(q).lost && askYesNo(c, 'Choose ${s.player(q).name}? They discard their hand and draw $n cards.', source: ctx.source)) q,
        ];
        for (final q in chosen) {
          _discardCards(q, List.of(s.player(q).hand));
        }
        for (final q in chosen) {
          for (var i = 0; i < n; i++) {
            _draw(q);
          }
        }
      case W1PlayFreeCostOf(:final slot):
        final ids = ctx.slots[slot] ?? const <CardId>[];
        if (ids.isEmpty) return;
        final max = db[s.obj(ids.first).card]!.cost;
        final cands = [
          for (final id in me.hand)
            if (id != ids.first && db[s.obj(id).card]!.type == CardType.character && db[s.obj(id).card]!.cost <= max) id,
        ];
        if (cands.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: c, prompt: 'Play one for free', options: cands, min: 1, max: 1, source: ctx.source));
        _enterPlay(c, pick.first, free: true);
        ctx.didIt = true;
      case W1GrantTimed(:final target, :final lasting, :final ability, :final keyword, :final rule, :final cls, :final whileSource):
        final ids = _resolveTargets(target, ctx);
        if (ids.isEmpty) return;
        s.w1Grants.add(
          W1Grant(
            ts: s.nextTs++,
            controller: c,
            source: ctx.source,
            sourceZcc: s.objOrNull(ctx.source)?.zcc ?? 0,
            lasting: lasting,
            turn: s.turn,
            cards: ids,
            zccs: [for (final id in ids) s.obj(id).zcc],
            whileSource: whileSource,
            ability: ability,
            keyword: keyword,
            rule: rule,
            cls: cls,
          ),
        );
        s.version++;
      case W1MoveAllDamageTo(:final target):
        final t = _resolveTargets(target, ctx);
        if (t.isEmpty) return;
        var total = 0;
        for (final p in _turnOrder()) {
          for (final id in s.player(p).play) {
            if (id == t.first || chars(id).type != CardType.character) continue;
            total += s.obj(id).damage;
            s.obj(id).damage = 0;
          }
        }
        s.obj(t.first).damage += total;
        s.version++;
        if (total > 0) log('$total damage moves to ${nameOf(t.first)}.', card: t.first, kind: 'damage', amount: total);
      case W1MoveFromHere():
        final here = ctx.source;
        final movers = [
          for (final id in me.play)
            if (s.obj(id).at == here && chars(id).type == CardType.character) id,
        ];
        final locs = [
          for (final id in me.play)
            if (id != here && chars(id).type == CardType.location) id,
        ];
        if (movers.isEmpty || locs.isEmpty) {
          ctx.didIt = false;
          return;
        }
        final who = ask(Decision(kind: DecisionKind.cards, player: c, prompt: 'Choose a character to move from here', options: movers, min: 1, max: 1, source: ctx.source)).first;
        final to = ask(Decision(kind: DecisionKind.cards, player: c, prompt: 'Choose the location to move to', options: locs, min: 1, max: 1, source: ctx.source)).first;
        _moveCharacter(c, who, to, pay: false);
        ctx.didIt = true;
      case W1PlayFreeFrom(:final who, :final filter, :final from, :final optional):
        var any = false;
        for (final p in _players(who, ctx)) {
          final cands = <CardId>[
            for (final place in from)
              for (final id in matching(filter, controller: p, source: ctx.source, place: place, whose: Owner.yours))
                if (id != ctx.source) id,
          ];
          if (cands.isEmpty) continue;
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose a card to play for free', options: cands, min: optional ? 0 : 1, max: 1, source: ctx.source));
          if (pick.isEmpty) continue;
          _enterPlay(p, pick.first, free: true);
          any = true;
        }
        ctx.didIt = any;
      case W1ReturnByWillpower(:final min):
        final cands = [
          for (final id in me.discard)
            if (db[s.obj(id).card]!.type == CardType.character && (db[s.obj(id).card]!.willpower ?? 0) >= min) id,
        ];
        if (cands.isEmpty) {
          ctx.didIt = false;
          return;
        }
        final pick = ask(Decision(kind: DecisionKind.cards, player: c, prompt: 'Return one to your hand', options: cands, min: 1, max: 1, source: ctx.source)).first;
        _moveTo(pick, Place.hand);
        log('${nameOf(pick)} returns to ${me.name}’s hand.', card: pick, kind: 'return');
        _emit(_Ev(kind: _EvKind.returnedFromDiscard, card: pick, player: c));
        ctx.didIt = true;
      case W1InkSymbols():
        final inks = <Ink>{};
        for (final q in _turnOrder()) {
          final pl = s.player(q);
          if (pl.lost || pl.deck.isEmpty) continue;
          log('${pl.name} reveals ${nameOf(pl.deck.first)}.', player: q, card: pl.deck.first);
          inks.addAll(db[s.obj(pl.deck.first).card]!.inks);
        }
        for (var i = 0; i < inks.length; i++) {
          _draw(c);
        }
      case W1OpponentChooses(:final options, :final labels):
        final ops = _players(Who.chosenOpponent, ctx);
        if (ops.isEmpty) return;
        final i = ask(Decision(kind: DecisionKind.option, player: ops.first, prompt: 'Choose one', labels: labels, source: ctx.source)).first;
        _resolveEffect(options[i], ctx);
      case W1DiscardAny(:final filter, :final thenDraw):
        final cands = [
          for (final id in me.hand)
            if (filter == null || _zoneMatches(filter, id, ctx, Place.hand)) id,
        ];
        final pick = cands.isEmpty ? const <CardId>[] : ask(Decision(kind: DecisionKind.cards, player: c, prompt: 'Choose any number of cards to discard', options: cands, min: 0, max: cands.length, source: ctx.source));
        _discardCards(c, pick);
        _w1Way[ctx] = [pick.length];
        ctx.didIt = pick.isNotEmpty;
        if (thenDraw) {
          for (var i = 0; i < pick.length; i++) {
            _draw(c);
          }
        }
      case W1BanishWeaker(:final own, :final target):
        final mine = _resolveTargets(Chosen(own, slot: 90, word: false), ctx);
        if (mine.isEmpty) return;
        final strength = chars(mine.first).strength;
        _banish(mine.first, by: ctx.source);
        _resolveEffect(Banish(Chosen(target.copyWith(strengthMax: strength - 1), slot: 91)), ctx);
      case W1EachOpponentPick(:final filter, :final rule):
        for (final q in _players(Who.opponents, ctx)) {
          final cands = [
            for (final id in matching(filter, controller: c, source: ctx.source))
              if (s.obj(id).owner == q && !chars(id).has(Kw.ward) && !_w1Unchoosable(id, c)) id,
          ];
          if (cands.isEmpty) continue;
          final pick = ask(Decision(kind: DecisionKind.cards, player: c, prompt: 'You may choose a character of ${s.player(q).name}’s', options: cands, min: 0, max: 1, source: ctx.source));
          if (pick.isEmpty) continue;
          _emit(_Ev(kind: _EvKind.chosenByOpponent, card: pick.first, player: c));
          _addTimed(ctx, pick, const This(), Lasting.theirNextTurn, rule: rule);
        }
      case W1EachChoosesN(:final who, :final filter, :final n, :final slot, :final then):
        for (final p in _players(who, ctx)) {
          final cands = [
            for (final id in matching(filter, controller: c, source: ctx.source))
              if (s.obj(id).owner == p) id,
          ];
          if (cands.isEmpty) continue;
          final k = n < cands.length ? n : cands.length;
          ctx.slots[slot] = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose $k of your ${filter.describe()}s', options: cands, min: k, max: k, source: ctx.source));
          _resolveEffect(then, ctx);
        }
        ctx.didIt = true;
      case W1MoveDamageEach(:final from, :final to, :final n):
        final t = _resolveTargets(to, ctx);
        if (t.isEmpty) return;
        var moved = 0;
        for (final id in matching(from, controller: c, source: ctx.source, whose: from.owner)) {
          if (id == t.first) continue;
          final o = s.obj(id);
          final k = n < o.damage ? n : o.damage;
          if (k <= 0) continue;
          o.damage -= k;
          moved += k;
        }
        s.obj(t.first).damage += moved;
        s.version++;
        _w1Way[ctx] = [moved];
        if (moved > 0) log('$moved damage moves to ${nameOf(t.first)}.', card: t.first, kind: 'damage', amount: moved);
      case W1StealLore(:final n):
        var total = 0;
        for (final q in _players(Who.opponents, ctx)) {
          final lore = s.player(q).lore;
          total += n < lore ? n : lore;
          _loseLore(q, n);
        }
        _gainLore(c, total, source: ctx.source);
        _w1Way[ctx] = [total];
      case W1RevealUntil(:final filter):
        final seen = <CardId>[];
        CardId? found;
        for (final id in me.deck) {
          seen.add(id);
          if (_zoneMatches(filter, id, ctx, Place.deck)) {
            found = id;
            break;
          }
        }
        if (seen.isEmpty) return;
        log('${me.name} reveals ${seen.map(nameOf).join(', ')}.', player: c, card: seen.last);
        if (found != null) {
          _moveTo(found, Place.hand);
          log('${me.name} puts ${nameOf(found)} into their hand.', player: c, card: found, kind: 'draw');
        }
        s.rng.shuffle(me.deck);
        s.version++;
      case W1MostCardsDiscard(:final n):
        final alive = [
          for (final q in _turnOrder())
            if (!s.player(q).lost) q,
        ];
        final most = alive.fold<int>(0, (m, q) => s.player(q).hand.length > m ? s.player(q).hand.length : m);
        if (most == 0) return;
        for (final q in alive) {
          final hand = s.player(q).hand;
          if (hand.length != most) continue;
          final k = n < hand.length ? n : hand.length;
          _discardCards(q, ask(Decision(kind: DecisionKind.cards, player: q, prompt: 'Choose $k card${k == 1 ? '' : 's'} to discard', options: List.of(hand), min: k, max: k, source: ctx.source)));
        }
      case W1RuleForAll(:final filter, :final rule, :final lasting):
        s.timed.add(Timed(ts: s.nextTs++, controller: c, source: ctx.source, lasting: lasting, turn: s.turn, filter: filter, rule: rule));
        s.version++;
      case W1HandToSize(:final n):
        final p = ctx.event?.player ?? s.active;
        final hand = s.player(p).hand;
        if (hand.length > n) {
          final k = hand.length - n;
          _discardCards(p, ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose $k card${k == 1 ? '' : 's'} to discard', options: List.of(hand), min: k, max: k, source: ctx.source)));
        } else {
          while (hand.length < n && _draw(p)) {}
        }
      case W1ReadyHealed():
        final l = _w1Way[ctx];
        if (l == null) return;
        for (final id in l.skip(1)) {
          final o = s.objOrNull(id);
          if (o == null || o.zone != Place.play) continue;
          o.exerted = false;
          log('${nameOf(id)} is readied.', card: id, kind: 'ready');
          _emit(_Ev(kind: _EvKind.readied, card: id, player: o.owner));
        }
        s.version++;
      case W1TopUnder(:final target):
        for (final host in _resolveTargets(target, ctx)) {
          if (me.deck.isEmpty) break;
          final top = me.deck.removeAt(0);
          final t = s.obj(top);
          t.zone = Place.play;
          t.faceDown = true;
          t.zcc++;
          s.obj(host).under.insert(0, top);
          s.version++;
          log('A card goes facedown under ${nameOf(host)}.', player: c, card: host, kind: 'ability');
          _emit(_Ev(kind: _EvKind.putUnder, card: host, player: c));
          ctx.didIt = true;
        }
      case W1RevealMayPlay():
        if (me.deck.isEmpty) {
          ctx.didIt = false;
          return;
        }
        final top = me.deck.first;
        log('${me.name} reveals ${nameOf(top)}.', player: c, card: top);
        final cost = playCost(c, top);
        if (_inkReady(c) >= cost && _w1PlayProblem(c, top) == null && askYesNo(c, 'Play ${nameOf(top)} for $cost ink?', source: ctx.source)) {
          _payInk(c, cost);
          _emit(_Ev(kind: _EvKind.inkPaid, card: top, player: c, amount: cost));
          _w1Paid(c, top);
          _enterPlay(c, top);
        } else {
          _moveTo(top, Place.discard);
          log('${me.name} puts ${nameOf(top)} into their discard.', player: c, card: top);
        }
        ctx.didIt = true;
      case W1Counted(:final inner):
        final before = me.discard.length;
        _resolveEffect(inner, ctx);
        _w1Way[ctx] = [before - me.discard.length];
    }
  }
}
