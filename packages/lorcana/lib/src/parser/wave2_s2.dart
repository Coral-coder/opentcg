part of 'parser.dart';

/// Wave 2, slice 2 (Gruesome And Grim … Mirabel Madrigal): the templates those cards need, tried
/// after (or, for whole texts, before) the general grammar, so what it already reads keeps its
/// meaning. The IR is in ir_wave2_s2.dart, the engine side in game/wave2_s2.dart.
extension _W2S2 on _CardParser {
  static const _inks = 'amber|amethyst|emerald|ruby|sapphire|steel';

  // -------------------------------------------------------------------------------------------
  // Paragraphs
  // -------------------------------------------------------------------------------------------

  /// "If its card type is: - character, …" reads as a story name; it continues the paragraph
  /// before it (Jack-Jack Parr).
  List<Paragraph> _w2Paragraphs(List<Paragraph> ps) {
    final out = <Paragraph>[];
    for (final p in ps) {
      if (out.isNotEmpty && !p.keyword && p.name.toLowerCase() == 'if its card type is') {
        final prev = out.removeLast();
        out.add(Paragraph(prev.name, '${prev.body} ${p.name}: ${p.body}'));
        continue;
      }
      out.add(p);
    }
    return out;
  }

  /// An action with a triggered ability of its own: "Deal 2 damage to chosen character. During
  /// your turn, when you discard this card, you may play it from your discard."
  List<Ability>? _w2Action(Paragraph p) {
    final t = _lower(p.body);
    final m = rx(t, r'(.+?)\. (during your turn, when you discard this card, .+)');
    if (m == null) return null;
    final e = effects(m[1], _Ctx());
    final trig = _triggered(p.printed, m[2]);
    if (e == null || trig == null) return null;
    return [ActionEffect(p.printed, e), ...trig];
  }

  List<Ability>? _w2Paragraph(String printed, String t) {
    // "Once during your turn, you may pay 1 {i} to draw a card, then choose and discard a card":
    // an ability its player uses, once a turn (CR 6.1.13.2), paying the ink.
    var m = rx(t, r'once during your turn, you may pay (\d+) ink to (.+)');
    if (m != null) {
      final e = effects(m[2], _Ctx());
      if (e == null) return null;
      return [W2OnceActivated(printed, Cost(ink: int.parse(m[1])), e)];
    }
    // "At the start of your turn, if this card is in your discard, you may play her and she
    // enters play exerted" (works from the discard).
    m = rx(t, r'at the start of your turn, if this card is in your discard, you may play (?:her|him|them|it) and (?:she|he|they|it) enters? play exerted');
    if (m != null) return [Triggered(printed, const TurnStep(start: true), const May(W2PlayThis(exerted: true)), fromDiscard: true)];
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Triggers
  // -------------------------------------------------------------------------------------------

  _Head? _w2TriggerHead(String h) {
    // A typo: "whenever one of your other characters banished another character in a challenge".
    if (h.contains(' banished another character in a challenge')) {
      return _quiet(() => _triggerHead(h.replaceFirst(' banished another character', ' banishes another character')));
    }
    if (h == 'whenever a card leaves your discard') return [(const W2LeavesDiscard(), null, false)];
    if (rx(h, r'whenever (?:another character of yours|one of your other characters) enters play exerted') != null) {
      return [(const W2EntersExerted(Filter(owner: Owner.yours, other: true)), null, false)];
    }
    // "Whenever one of your actions deals damage to an opposing character": the damage's source
    // is the action as it resolves.
    final m = rx(h, r'whenever one of your actions deals damage to (an opposing character|a character)');
    if (m != null) {
      return [(CardEvent(Event.dealtDamage, subject: Filter(owner: m[1].contains('opposing') ? Owner.opposing : Owner.any), other: const Filter(types: {CardType.action}, owner: Owner.yours)), null, false)];
    }
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Static abilities
  // -------------------------------------------------------------------------------------------

  List<Ability>? _w2Static(String printed, String t) {
    List<Ability> one(StaticEffect e, {Cond? condition, bool inHand = false}) => [Static(printed, e, condition: condition, inHand: inHand)];
    if (rx(t, r'if an effect would cause you to discard one or more cards(?: from your hand)?, you don.t discard') != null) return one(const W2NoDiscard());
    if (rx(t, r"this character can't be dealt damage unless (?:he|she|they|it)(?:'s|'re| is| are) being challenged") != null) {
      return one(const W2NoDamageUnlessChallenged());
    }
    var m = rx(t, r"while this character is exerted, (your other .+?) can't be dealt damage unless they're being challenged");
    if (m != null) {
      final f = _groupFilter(m[1]);
      if (f == null) return null;
      return one(W2NoDamageUnlessChallenged(f), condition: const SelfState(exerted: true));
    }
    // "For each location you have in play, this character gains Resist +1 and gets +1 {l}".
    m = rx(t, r'for each ([^,]+), this character gains (resist|challenger) \+(\d+) and gets ([+-])(\d+) (strength|willpower|lore)');
    if (m != null) {
      final c = countOf(m[1]);
      if (c == null) return null;
      final kw = m[2] == 'resist' ? Kw.resist : Kw.challenger;
      return [
        Static(printed, W2KeywordPer(kw, CountOf(c.filter, place: c.place, whose: c.whose, per: int.parse(m[3])))),
        Static(printed, StaticMod(null, _stat(m[6]), CountOf(c.filter, place: c.place, whose: c.whose, per: int.parse(m[5])), negative: m[4] == '-')),
      ];
    }
    m = rx(t, r'(your .+?) may move here for free');
    if (m != null) {
      final f = _groupFilter(m[1]);
      if (f == null) return null;
      return one(W2MoveCost(f, here: true));
    }
    m = rx(t, r'you pay (\d+) ink less to move (your characters) to a location');
    if (m != null) return one(W2MoveCost(const Filter(owner: Owner.yours), less: int.parse(m[1])));
    if (t == 'opponents must choose this character for actions and abilities if able') return one(const W2MustBeChosen());
    // Alternate costs (CR 1.5.5): "you may put a Toy character card from your discard on the
    // bottom of your deck to play this character for free".
    m = rx(t, r'you may put (a|an|\d+) (.+?) from your discard on the bottom of your deck(?: in any order)? to (play|shift) this character for free');
    if (m != null) {
      final fs = _zoneFilters(m[2]);
      final n = numWord(m[1]);
      if (fs == null || fs.length != 1 || n == null) return null;
      return one(W2AltCost(fs.first, n, shift: m[3] == 'shift'), inHand: true);
    }
    if (t == 'each player plays with the top card of their deck face up') return one(const W2TopCardFaceUp());
    m = rx(t, r"if you have a character named (.+?) in play, you may use this item's (.+?) ability for free");
    if (m != null) return one(W2FreeAbility(m[2]), condition: CountCond(Filter(named: m[1]), Cmp.ge, 1));
    if (rx(t, r'if this character would be banished, put (?:them|him|her|it) into your inkwell facedown and exerted instead') != null) return one(const W2BanishToInkwell());
    return null;
  }

  List<StaticEffect>? _w2StaticEffect(String t) {
    if (rx(t, r'all cards in your hand count as having \{iw\}') != null) return const [W2HandInkable()];
    var m = rx(t, r'this character enters play exerted and (.+)');
    if (m != null) {
      final rest = _predicate(m[1], null);
      if (rest == null) return null;
      return [const EntersWith(exerted: true), ...rest];
    }
    if (rx(t, r'the first time this character would take damage, (?:she|he|they|it) takes? no damage instead') != null) return const [W2FirstDamagePrevented()];
    // "Your Floodborn characters that have a card under them gain Evasive and Ward" (the general
    // grammar would take "have" for the verb).
    m = rx(t, r'(.+? that have a card under them) ((?:gets?|gains?) .+)');
    if (m != null) {
      final f = _groupFilter(m[1]);
      final es = f == null ? null : _predicate(m[2], f);
      if (es == null) return null;
      return es;
    }
    if (t == "you can't lose lore") return const [W2NoLoseLore()];
    if (t == "you can't play this character") return const [W2CantPlayThis()];
    return null;
  }

  /// Predicates the general grammar doesn't read: a quoted ability ("gains "Whenever this
  /// character is challenged, …""), and a trailing "this turn" on a conditional static.
  List<StaticEffect>? _w2Predicate(String p, Filter? f) {
    var m = rx(p, r'gains? "(.+)"');
    if (m != null) {
      final q = _w2Quoted(m[1]);
      if (q == null) return null;
      if (q.$1 != null) return [W2StaticTrigger(f, q.$1!)];
      return [for (final r in q.$2!) StaticRule(f, r)];
    }
    m = rx(p, r'(.+) this turn');
    if (m != null) return _predicate(m[1], f);
    return null;
  }

  /// A quoted ability: a triggered one, or rules ("this character can challenge ready
  /// characters", "this character takes no damage from challenges").
  (Triggered?, List<Rule>?)? _w2Quoted(String q0) {
    var q = q0.trim();
    if (q.endsWith('.')) q = q.substring(0, q.length - 1);
    if (q == 'this character can challenge ready characters') return (null, const [Rule.canChallengeReady]);
    if (q == 'this character takes no damage from challenges') return (null, const [Rule.takesNoDamageFromChallenges]);
    final printed = q.isEmpty ? q : '${q[0].toUpperCase()}${q.substring(1)}';
    final t = _triggered(printed, q);
    if (t == null || t.length != 1 || t.first is! Triggered) return null;
    return (t.first as Triggered, null);
  }

  // -------------------------------------------------------------------------------------------
  // Conditions
  // -------------------------------------------------------------------------------------------

  Cond? _w2Condition(String s) {
    var m = rx(s, r'an opponent has (\d+) or more (.+?) in play');
    if (m != null) {
      final f = filter(_plural(m[2]), Owner.opposing);
      if (f == null) return null;
      return W2OpponentHas(f.copyWith(owner: Owner.opposing), int.parse(m[1]));
    }
    if (s == 'you played a song this turn' || s == "you've played a song this turn") return const TurnStatCond(TurnStat.songsPlayed, Who.you, Cmp.ge, 1);
    // Characters played this turn ("if you've played a character with cost 5 or more this turn").
    m = rx(s, r"you've played (?:a|an) (.+?) this turn");
    if (m != null) {
      final f = filter(m[1], Owner.yours);
      if (f == null || !f.types.every((t) => t == CardType.character)) return null;
      return W2PlayedThisTurn(f);
    }
    if (s == 'a character of yours challenged this turn') return const TurnStatCond(TurnStat.challenged, Who.you, Cmp.ge, 1);
    if (s == 'an opposing character was damaged this turn') return const TurnStatCond(TurnStat.damaged, Who.opponents, Cmp.ge, 1);
    // "If you have any in play with 10 {s} or more" (the general grammar reorders it to "you have
    // any with 10 strength or more in play").
    m = rx(s, r'you have any (?:in play with (\d+) strength or more|with (\d+) strength or more in play)');
    if (m != null) return CountCond(Filter(strengthMin: int.parse(m[1].isNotEmpty ? m[1] : m[2])), Cmp.ge, 1);
    if (s == 'you discarded a card this turn') return const W2DiscardedThisTurn();
    if (rx(s, r"you've put a card under (?:her|him|them|it|this character) this turn") != null) return const W2PutUnderThisTurn();
    if (rx(s, r'(?:he|she|they|this character) had a card under (?:him|her|them|it)') != null) return const W2HadUnder();
    m = rx(s, r'(\d+) or more characters sang this song');
    if (m != null) return W2SingersCond(int.parse(m[1]));
    if (s == 'you removed damage this way') return const W2RemovedAny();
    m = rx(s, r'(?:an? (.+?) card (?:is|was) discarded(?: this way)?|you discarded an? (.+?) card)');
    if (m != null) {
      final f = filter(m[1].isNotEmpty ? m[1] : m[2], Owner.any, cardTypes: true);
      if (f == null) return null;
      return W2DiscardedIs(f);
    }
    // "This character is exerted and none of your characters challenged this turn".
    final and = RegExp(r'^(.+?) and (.+)$').firstMatch(s);
    if (and != null) {
      final a = condition(and.group(1)!);
      final b = a == null ? null : condition(and.group(2)!);
      if (a != null && b != null) return AllConds([a, b]);
    }
    return null;
  }

  /// "If there's a card under that character", "if the banished item is named Maurice's
  /// Machine": about the card chosen earlier in the ability.
  Cond? _w2IfTarget(String s, _Ctx ctx) {
    if (ctx.nextSlot == 0) return null;
    if (s == "there's a card under that character") return W2SlotHasUnder(ctx.nextSlot - 1);
    final m = rx(s, r'the banished (item|character) is named (.+)');
    if (m != null) return W2SlotIs(ctx.nextSlot - 1, Filter(types: {m[1] == 'item' ? CardType.item : CardType.character}, named: m[2]));
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Effects
  // -------------------------------------------------------------------------------------------

  /// Whole effects whose sentences refer to each other.
  Effect? _w2Effects(String text, _Ctx ctx) {
    // "Play a character with cost 4 or less for free. They gain Rush. At the end of the turn,
    // banish them." (CR 6.1.7, 6.2.7.2).
    var m = rx(text, r'play (?:a|an) (.+?) for free\. (?:they|he|she) gains? (.+?)\. at the end of the turn, banish them');
    if (m != null) {
      final f = _w2CostFilter(m[1]);
      final kws = _keywordList(m[2]);
      if (f == null || kws == null) return null;
      final slot = ctx.nextSlot++;
      return Seq([W2PlayFree(f, slot: slot), for (final k in kws) GrantKeyword(Remembered(slot), k, Lasting.permanent), const Delayed(true, Banish(EventCard()))]);
    }
    // "You may choose an opposing character. If you do, draw 2 cards unless that character's
    // player puts that card on the bottom of their deck."
    m = rx(text, r"you may choose (.+?)\. if you do, (.+?) unless that character's player puts that card on the bottom of their deck");
    if (m != null) {
      final t = target(m[1], ctx);
      if (t is! Chosen) return null;
      final e = effects(m[2], ctx);
      if (e == null) return null;
      // Choosing is choosing, "chosen" or not (Ward, CR 8.15.1).
      return Seq([May(W2Choose(Chosen(t.filter, slot: t.slot))), If(const DidIt(), W2UnlessTuck(t.slot, e))]);
    }
    // "… If 2 or more characters sang this song, ready them. They can't quest for the rest of
    // this turn."
    m = rx(text, r"(.+?)\. if (\d+) or more characters sang this song, ready them\. they can't quest for the rest of this turn");
    if (m != null) {
      final e = effects(m[1], ctx);
      if (e == null) return null;
      const singers = Remembered(w2SingersSlot);
      return Seq([e, If(W2SingersCond(int.parse(m[2])), const W2WithSingers(Seq([Ready(singers), GrantRule(singers, Rule.cantQuest, Lasting.thisTurn)])))]);
    }
    // "You may put the top card of your deck into your discard. If its card type is: - character,
    // A. - action or item, B. - location, C."
    m = rx(text, r'(you may )?put the top card of your deck into your discard\. if its card type is:? (.+)');
    if (m != null) {
      final types = <Set<CardType>>[];
      final branches = <Effect>[];
      for (final part in m[2].split(RegExp(r'(?:^|\.\s*)[-•]\s*'))) {
        final b = part.trim().replaceAll(RegExp(r'\.$'), '');
        if (b.isEmpty) continue;
        final x = RegExp(r'^([a-z ,]+?), (.+)$').firstMatch(b);
        if (x == null) return null;
        final ts = <CardType>{};
        for (final w in x.group(1)!.split(RegExp(r',? or |, '))) {
          final ty = CardType.values.where((c) => c.name == w.trim()).firstOrNull;
          if (ty == null) return null;
          ts.add(ty);
        }
        final e = effects(x.group(2)!, ctx);
        if (e == null) return null;
        types.add(ts);
        branches.add(e);
      }
      if (types.isEmpty) return null;
      final e = W2MillBranch(types, branches);
      return m[1].isNotEmpty ? May(e) : e;
    }
    // "You may draw a card, then choose and discard a card. If an Illusion character card is
    // discarded this way, you may play that character for free."
    m = rx(text, r'you may draw a card, then choose and discard a card\. if an? (.+?) card is discarded this way, you may play that character for free');
    if (m != null) {
      final f = filter(m[1], Owner.any, cardTypes: true);
      if (f == null) return null;
      return Seq([
        const May(Seq([Draw(Who.you, Fixed(1)), W2DiscardTrack(Discard(Who.you, Fixed(1)))])),
        If(W2DiscardedIs(f), May(W2PlayRemembered(w2DiscardSlot, f))),
      ]);
    }
    // "You may draw a card, then choose and discard a card to deal 1 damage to chosen character
    // or location. If you discarded a Pirate character card, deal 3 damage instead."
    m = rx(text, r'you may draw a card, then choose and discard a card to deal (\d+) damage to (.+?)\. if you discarded an? (.+?) card, deal (\d+) damage instead');
    if (m != null) {
      final t = target(m[2], ctx);
      final f = filter(m[3], Owner.any, cardTypes: true);
      if (t == null || f == null) return null;
      return May(
        Seq([
          const Draw(Who.you, Fixed(1)),
          const W2DiscardTrack(Discard(Who.you, Fixed(1))),
          If(const DidIt(), If(W2DiscardedIs(f), DealDamage(t, Fixed(int.parse(m[4]))), DealDamage(t, Fixed(int.parse(m[1]))))),
        ]),
      );
    }
    // "For each of your characters named Maleficent in play, return a chosen opposing character,
    // item, or location with cost 3 or less to their player's hand": one choice each time.
    m = rx(text, r'for each of (your .+?) in play, (.+)');
    if (m != null) {
      final f = _groupFilter(m[1]);
      if (f == null) return null;
      final e = effects(m[2].replaceAll(RegExp(r'\ba chosen '), 'chosen '), ctx);
      if (e == null) return null;
      return W2Repeat(CountOf(f, whose: Owner.yours), e);
    }
    // "Each player exerts all the cards in their inkwell. Then each player with more than 3 cards
    // in their inkwell returns cards at random from their inkwell to their hand until they have 3
    // cards in their inkwell."
    m = rx(text, r'each player exerts all the cards in their inkwell\. then each player with more than (\d+) cards in their inkwell returns cards at random from their inkwell to their hand until they have (\d+) cards in their inkwell');
    if (m != null && m[1] == m[2]) return Seq([const W2ExertInkwell(Who.each), W2TrimInkwell(Who.each, int.parse(m[1]))]);
    // "Each player shuffles their deck and then reveals the top card. Each player who reveals a
    // character card may play that character for free. Otherwise, put the revealed cards on the
    // bottom of their player's deck."
    m = rx(text, r"each player shuffles their deck and then reveals the top card\. each player who reveals an? (.+?) card may play that (?:character|card) for free\. otherwise, put the revealed cards on the bottom of their player's deck");
    if (m != null) {
      final f = filter(m[1], Owner.any, cardTypes: true);
      if (f == null) return null;
      return W2EachRevealPlay(f);
    }
    if (text == 'reveal the top card of your deck. you may play it as if it were in your hand. otherwise, put it in your discard') return const W2PlayTop();
    // "You may remove up to 2 damage from another chosen character of yours. Gain 1 lore for each 1
    // damage removed this way."
    m = rx(text, r'(.+?)\. ((?:you )?gain 1 lore for each 1 damage removed this way)');
    if (m != null) {
      final a = effects(m[1], ctx);
      if (a == null) return null;
      return Seq([W2TrackRemoved(a), const GainLore(Who.you, W2RemovedAmount())]);
    }
    // "You may remove up to 2 damage from chosen character. If you removed damage this way, you
    // may draw a card."
    m = rx(text, r'(.+?)\. if you removed damage this way, (.+)');
    if (m != null) {
      final a = effects(m[1], ctx);
      final b = a == null ? null : effects(m[2], ctx);
      if (b == null) return null;
      return Seq([W2TrackRemoved(a!), If(const W2RemovedAny(), b)]);
    }
    // "Search your deck for an item card or a Robot character card and reveal it to all players.
    // Shuffle your deck and put that card on top of it."
    m = rx(text, r'(you may )?search your deck for (.+?) and reveal (?:it|that card) to all players\. shuffle your deck and put that card on top of it');
    if (m != null) {
      final fs = _zoneFilters(m[2]);
      if (fs == null) return null;
      final e = W2SearchDeck(fs, ZoneDest.top);
      return m[1].isNotEmpty ? May(e) : e;
    }
    return null;
  }

  /// "Character with cost 4 or less": what a free play may choose.
  Filter? _w2CostFilter(String s) => filter(s, Owner.yours, cardTypes: true);

  /// Templates over several sentences.
  (Effect, int)? _w2Span(List<String> ss, int i, _Ctx ctx) {
    final s = ss[i];
    String? at(int k) => i + k < ss.length ? ss[i + k] : null;
    // "Reveal the top 3 cards of your deck. You may put each character card with cost 2 or less
    // into your hand. Put the rest on the bottom of your deck in any order."
    var m = rx(s, r'reveal the top (\d+) cards of your deck');
    if (m != null && at(1) != null && at(2) != null) {
      final pick = rx(at(1)!, r'(you may )?put (?:each|revealed|all revealed) (.+?) into your hand');
      final rest = _restDest(at(2)!);
      if (pick == null || rest == null) return null;
      final fs = _zoneFilters(pick[2]);
      if (fs == null) return null;
      return (Peek(int.parse(m[1]), reveal: true, picks: [PeekPick(filters: fs, anyNumber: true, optional: pick[1].isNotEmpty)], rest: rest), 3);
    }
    // "Each player reveals the top card of their deck. If it's a character card, they may put it
    // into their hand. Otherwise, put it on the bottom of their deck."
    m = rx(s, r'each player reveals the top card of their deck');
    if (m != null) {
      final r = _revealFollowUp(ss, i + 1, who: Who.each);
      if (r == null) return null;
      return (r.$1, 1 + r.$2);
    }
    return null;
  }

  /// One action the general grammar doesn't read.
  Effect? _w2Clause(String c, _Ctx ctx) {
    List<String>? m;
    // Players choosing their own card ("each opponent chooses one of their characters and
    // returns that card to their hand / puts that card on the bottom of their deck").
    m = rx(c, r'(each opponent|each player|chosen opponent) chooses one of their (.+?) and (returns that card to their hand|puts that card on the bottom of their deck)');
    if (m != null) {
      final f = filter(_plural(m[2]), Owner.any, cardTypes: true);
      if (f == null) return null;
      final slot = ctx.nextSlot++;
      final r = Remembered(slot);
      return PlayerChooses(_who(m[1]), f, slot, m[3].startsWith('returns') ? ReturnToHand(r) : ToDeck(r, bottom: true));
    }
    // "Pay 2 {i} to have each opponent choose and discard a card", "pay 1 {i} to give chosen
    // character +2 {s} this turn" (CR 6.1.5.1).
    m = rx(c, r'pay (\d+) ink to (?:have )?(.+)');
    if (m != null) {
      final e = _clauses(m[2], ctx);
      if (e == null) return null;
      return Seq([PayInk(int.parse(m[1])), If(const DidIt(), e)]);
    }
    if (c == 'put all cards from your hand into your inkwell facedown and exerted') return const W2HandToInkwell();
    m = rx(c, r'deal that much damage to (.+)');
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return DealDamage(t, const W2EventAmount());
    }
    m = rx(c, r'put (a|one|two|three|\d+) cards? from your hand on the (top|bottom) of your deck(?: in any order)?');
    if (m != null) return W2HandToDeck(numWord(m[1])!, top: m[2] == 'top');
    m = rx(c, r'remove up to (\d+) damage total from any number of (your .+)');
    if (m != null) {
      final f = _groupFilter(m[2]);
      if (f == null) return null;
      return W2RemoveTotal(f, int.parse(m[1]));
    }
    if (rx(c, r'(?:you )?gain 1 lore for each 1 damage removed this way') != null) return const GainLore(Who.you, W2RemovedAmount());
    if (rx(c, r'(?:you )?gain 1 lore for each 1 damage removed') != null) return const GainLore(Who.you, W2EventAmount());
    m = rx(c, r'you and another chosen player each draw (a|one|two|three|\d+) cards?');
    if (m != null) {
      final n = numWord(m[1])!;
      return Seq([Draw(Who.you, Fixed(n)), W2OtherPlayerDraws(n)]);
    }
    m = rx(c, r"choose up to (\d+) cards from chosen opponent's discard and shuffle them into their deck");
    if (m != null) return FromDiscard(_Zones._anyCard, who: Who.chosenOpponent, count: int.parse(m[1]), upTo: true, dest: ZoneDest.shuffle);
    m = rx(c, r"opponents can't play (.+?) until the start of your next turn");
    if (m != null) {
      final f = filter(m[1], Owner.opposing, cardTypes: true);
      if (f == null) return null;
      return W2OpponentsCantPlay(f);
    }
    m = rx(c, r'each player may put up to (\d+) cards from their discard into their inkwell facedown( and exerted)?');
    if (m != null) return EachMay(Who.each, FromDiscard(_Zones._anyCard, count: int.parse(m[1]), upTo: true, dest: ZoneDest.inkwell, exerted: m[2].isNotEmpty));
    m = rx(c, r'chosen opponent may put the top card of their deck into their inkwell facedown( and exerted)?');
    if (m != null) return EachMay(Who.chosenOpponent, InkTopOfDeck(Who.you, exerted: m[1].isNotEmpty));
    m = rx(c, r'(each opponent|each player|chosen opponent) puts? the top (card|\d+ cards) of their deck into their discard');
    if (m != null) return Mill(_who(m[1]), m[2] == 'card' ? 1 : int.parse(m[2].split(' ').first));
    m = rx(c, r"put the top (\d+) cards of chosen player's deck into their discard");
    if (m != null) return Mill(Who.chosenPlayer, int.parse(m[1]));
    // "Each opponent chooses and discards either 2 cards or 1 action card".
    m = rx(c, r'(each opponent|chosen opponent) chooses and discards either (\w+) cards or (?:1|one|a|an) (.+?) cards?');
    if (m != null) {
      final n = numWord(m[2]);
      final f = filter(m[3], Owner.any, cardTypes: true);
      if (n == null || f == null) return null;
      return W2DiscardEither(_who(m[1]), n, f);
    }
    m = rx(c, r'return another (\w+) chosen (.+?) to your hand');
    if (m != null) {
      final n = numWord(m[1]);
      final f = filter(_plural(m[2]), Owner.any, cardTypes: true, chosenPhrase: true);
      if (n == null || f == null) return null;
      return ReturnToHand(Chosen(f.copyWith(other: true), count: n, slot: ctx.nextSlot++));
    }
    if (c == "shuffle a card from any discard into its player's deck") return const W2ShuffleFromAnyDiscard();
    m = rx(c, r"each opponent can't ready more than (\d+|one) of their characters at the start of their next turn");
    if (m != null) return W2ReadyLimit(numWord(m[1])!);
    m = rx(c, r"shuffle (all|a|an) (.+?) from (your|chosen player's) discard into (?:your|their) deck");
    if (m != null) {
      final fs = _zoneFilters(m[2]);
      if (fs == null || fs.length != 1) return null;
      return FromDiscard(fs.first, who: m[3] == 'your' ? Who.you : Who.chosenPlayer, all: m[1] == 'all', dest: ZoneDest.shuffle);
    }
    m = rx(c, r'(?:you )?gain lore equal to the cost of (.+)');
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return GainLore(Who.you, W2CostOf(t));
    }
    m = rx(c, r"return chosen (.+?) with cost equal to or less than this character's strength to its player's hand");
    if (m != null) {
      final f = filter(m[1], Owner.any, cardTypes: true, chosenPhrase: true);
      if (f == null) return null;
      return ReturnToHand(Chosen(W2Filter.of(f, costAtMostSourceStrength: true), slot: ctx.nextSlot++));
    }
    if (c == 'banish chosen character who was challenged this turn') return Banish(Chosen(const W2Filter(challengedThisTurn: true), slot: ctx.nextSlot++));
    // Timed changes with a quoted ability: "chosen character gains Challenger +3 and "When this
    // character is banished in a challenge, return this card to your hand" this turn".
    m = rx(c, r'(.+?) ((?:gets?|gains?) .*".+".*) (this turn|until the start of your next turn)');
    if (m != null) return _w2Grants(m[1], m[2], _lasting(m[3])!, ctx);
    m = rx(c, r'(.+?) gains? the (.+?) classification (this turn|until the start of your next turn)');
    if (m != null && knownClassifications.contains(m[2])) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return W2GrantClass(t, _cap(m[2]), _lasting(m[3])!);
    }
    m = rx(c, r'(.+?) gets? \+(\d+) (strength|willpower|lore) and loses (\w+) (this turn)');
    if (m != null) {
      final t = target(m[1], ctx);
      final k = Kw.values.where((x) => x.name == m![4]).firstOrNull;
      if (t == null || k == null) return null;
      return Seq([Modify(t, _stat(m[3]), Fixed(int.parse(m[2])), Lasting.thisTurn), W2LoseKeyword(t, k, Lasting.thisTurn)]);
    }
    // "Chosen opposing character loses {s} equal to this character's {l} until the start of your
    // next turn".
    m = rx(c, r"(.+?) loses (strength|willpower|lore) equal to (this character)'s (strength|willpower|lore) (this turn|until the start of your next turn)");
    if (m != null) {
      final t = target(m[1], ctx);
      final src = ref(m[3], ctx);
      if (t == null || src == null) return null;
      return Modify(t, _stat(m[2]), StatOf(src, _stat(m[4])), _lasting(m[5])!, negative: true);
    }
    // Playing cards (CR 6.1.7).
    m = rx(c, r'play (?:a|an) (character|item|location) with the same name as the banished (?:character|item|location) for free');
    if (m != null) return W2PlayFree(Filter(types: {CardType.values.firstWhere((t) => t.name == m![1])}, owner: Owner.yours), sameNameAsCost: true);
    m = rx(c, r'play (?:a|an) (.+?) from your discard for free, then put (?:it|that action card|that card|that song) on the bottom of your deck instead of into your discard');
    if (m != null) {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      if (f == null) return null;
      return W2PlayFree(f, from: Place.discard, bottomAfter: true);
    }
    if (rx(c, r'play (?:it|her|him|them) from your discard') != null) return const W2PlayThis();
    if (c == 'shift a character from your discard for free') return const W2ShiftFromDiscard();
    if (c == 'draw a card from the bottom of your deck') return const W2DrawBottom();
    if (c == 'put this card from your discard on the bottom of your deck') return const ToDeck(This(), bottom: true);
    if (c == 'search your deck for any card, put that card into your hand, then shuffle your deck') return const W2SearchDeck([_Zones._anyCard], ZoneDest.hand, reveal: false);
    // Cards under others (CR 8.4.2).
    m = rx(c, r'put the top card of your deck facedown under (him|her|them|it|this character)');
    if (m != null) {
      final t = ref(m[1], ctx);
      if (t == null) return null;
      return W2PutTopUnder(t);
    }
    m = rx(c, r'put all cards that were under (?:him|her|them|it) under (.+)');
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return W2MoveFormerUnder(t);
    }
    m = rx(c, r'reveal (?:a|an) (.+?) in your hand');
    if (m != null) {
      final fs = _zoneFilters(m[1]);
      if (fs == null || fs.length != 1) return null;
      return W2RevealInHand(fs.first);
    }
    return null;
  }

  /// Tried after the general grammar: choices, rewordings, "unless".
  Effect? _w2ClauseLast(String c, _Ctx ctx) {
    List<String>? m;
    // "Choose a character of yours and gain lore equal to their {l}".
    m = rx(c, r'choose (?:a|an) (.+?) and (gain lore equal to their (?:strength|willpower|lore))');
    if (m != null) {
      final f = filter(m[1], Owner.any, cardTypes: true, chosenPhrase: true);
      if (f == null) return null;
      final choice = W2Choose(Chosen(f, slot: ctx.nextSlot++));
      final gain = clause(m[2], ctx);
      if (gain == null) return null;
      return Seq([choice, gain]);
    }
    // Rewordings of what the general grammar reads.
    if (c.contains(' or less each from your discard')) return clause(c.replaceFirst(' or less each from your discard', ' or less from your discard'), ctx);
    if (c.contains('the exerted character')) return clause(c.replaceFirst('the exerted character', 'that character'), ctx);
    m = rx(c, r'also (.+)');
    if (m != null) return clause(m[1], ctx);
    // "Choose and discard a card unless you have a character named Darkwing Duck in play".
    m = rx(c, r'(.+?) unless (.+)');
    if (m != null) {
      final cond = condition(m[2]);
      if (cond == null) return null;
      final e = clause(m[1], ctx);
      if (e == null) return null;
      return If(Not(cond), e);
    }
    return null;
  }

  /// "[target] gains Challenger +3 and "…"", "[target] gets +2 {s} and gains "…"": one target,
  /// each part for [d].
  Effect? _w2Grants(String who, String preds, Lasting d, _Ctx ctx) {
    final save = ctx.save();
    final t = target(who, ctx);
    if (t == null) return null;
    final steps = <Effect>[];
    for (final part in preds.split(RegExp(r' and (?=(?:gets?|gains?) |")'))) {
      var p = part.trim();
      if (p.startsWith('"')) p = 'gains $p';
      final q = rx(p, r'gains? "(.+)"');
      if (q != null) {
        final x = _w2Quoted(q[1]);
        if (x == null) {
          ctx.restore(save);
          return null;
        }
        if (x.$1 != null) {
          steps.add(W2GrantAbility(t, q[1].replaceAll(RegExp(r'\.$'), ''), x.$1!, d));
        } else {
          for (final r in x.$2!) {
            steps.add(GrantRule(t, r, d));
          }
        }
        continue;
      }
      final e = _timedPredicate(p, t, d);
      if (e == null) {
        ctx.restore(save);
        return null;
      }
      steps.add(e);
    }
    return steps.length == 1 ? steps.first : Seq(steps);
  }

  // -------------------------------------------------------------------------------------------
  // Card phrases
  // -------------------------------------------------------------------------------------------

  /// "Amber characters", "other Amethyst character" (inks, CR 5.2.5), "Broom cards" (a
  /// classification with no type).
  Filter? _w2Filter(String s0, Owner owner) {
    final s = s0.trim();
    var m = RegExp('^((?:a |an |other |opposing )*)($_inks) (character|item|location)s?(?: cards?)?\$').firstMatch(s);
    if (m != null) {
      final pre = m.group(1)!;
      final type = CardType.values.firstWhere((t) => t.name == m!.group(3));
      return W2Filter(types: {type}, owner: pre.contains('opposing') ? Owner.opposing : owner, other: pre.contains('other'), ink: Ink.parse(m.group(2)!));
    }
    m = RegExp(r'^([a-z ]+?) cards?$').firstMatch(s);
    if (m != null && knownClassifications.contains(m.group(1)) && !const {'character', 'item', 'location', 'action', 'song'}.contains(m.group(1))) {
      return Filter(types: _allTypes, owner: owner, classes: [_cap(m.group(1)!)]);
    }
    return null;
  }

  /// "Floodborn characters that have a card under them".
  Filter? _w2Group(String s) {
    final m = rx(s, r'(.+?) that have a card under them');
    if (m == null) return null;
    final f = _groupFilter(m[1]);
    return f == null ? null : W2Filter.of(f, hasUnder: true);
  }

  /// "Character card with cost 3 or less or named Pocahontas": two alternatives sharing a type.
  List<Filter>? _w2ZoneFilters(String s) {
    final m = rx(s.trim(), r'(?:an? )?(character|item|location|action) card with cost (\d+) or less or named (.+)');
    if (m == null) return null;
    final type = CardType.values.firstWhere((t) => t.name == m[1]);
    return [Filter(types: {type}, costMax: int.parse(m[2])), Filter(types: {type}, named: m[3])];
  }
}
