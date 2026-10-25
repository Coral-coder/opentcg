part of 'parser.dart';

/// Wave 2, slice 1: abilities in quotes granted to other cards, searching decks, choices other
/// players make, and the paragraphs the general grammar splits or reads wrongly. Hooked into
/// `_paragraph`, `_action`, [_CardParser.effects], `clause`, `condition`, `_triggerHead`,
/// `_staticEffect` and `filter`; resolved in game/wave2_s1.dart.
extension _Wave2S1 on _CardParser {
  static const _inkWords = r'amber|amethyst|emerald|ruby|sapphire|steel';
  static const _allTypes = {CardType.character, CardType.action, CardType.item, CardType.location};

  // -------------------------------------------------------------------------------------------
  // Whole paragraphs
  // -------------------------------------------------------------------------------------------

  List<Ability>? _w1Paragraph(Paragraph p, String t) {
    final printed = p.printed;
    // A story name that swallowed the cost ("Cybernetic Armor - Banish this item: Chosen…") or the
    // trigger ("ROLL WITH IT When you play this character, choose one: - …").
    var m = RegExp(r'^(.+?) - (banish this (?:item|character|location))$', caseSensitive: false).firstMatch(p.name);
    if (m != null) return _paragraph(Paragraph(m.group(1)!, '${m.group(2)} - ${p.body}'));
    m = RegExp(r'^(.*?)\b((?:When|Whenever) .+)$').firstMatch(p.name);
    if (m != null && p.body.startsWith('- ')) return _paragraph(Paragraph(m.group(1)!.trim(), '${m.group(2)}: ${p.body}'));

    // "During each opponent's turn, whenever…" (CR 6.1.13.1).
    m = RegExp(r"^during (?:each opponent's turn|opponents' turns), (whenever .+)$").firstMatch(t);
    if (m != null) {
      final r = _triggered(printed, "during an opponent's turn, ${m.group(1)}");
      if (r != null) return r;
    }
    // "While this character is at a location, whenever…": checked as it triggers (CR 6.1.13.6).
    m = RegExp(r'^while this character is at a location, (whenever .+)$').firstMatch(t);
    if (m != null) {
      final r = _triggered(printed, m.group(1)!);
      if (r == null) return null;
      return [
        for (final a in r)
          a is Triggered ? Triggered(a.text, a.trigger, a.effect, condition: a.condition, during: _and(a.during, const SelfState(atLocation: true)), oncePerTurn: a.oncePerTurn, fromDiscard: a.fromDiscard) : a,
      ];
    }
    // "[Trigger], if X, A. Otherwise, B": one effect with both branches (CR 6.2.4).
    m = RegExp(r'^((?:when|whenever|at the (?:start|end)) [^,]+), (if .+?\. otherwise, .+)$').firstMatch(t);
    if (m != null) {
      final heads = _quiet(() => _triggerHead(m!.group(1)!));
      if (heads != null) {
        final e = effects(m.group(2)!, _Ctx(event: true, eventOther: heads.every((tr) => _aboutOtherCard(tr.$1))));
        if (e != null) return [for (final tr in heads) Triggered(printed, tr.$1, e, during: tr.$2, fromDiscard: tr.$3)];
      }
    }

    List<String>? r;
    // "Once during your turn, you may X [to Y]": an ability the player uses, once a turn (CR 6.3,
    // 6.1.13.2).
    r = rx(t, r'once during your turn, you pay (\d+) ink less for the next (.+?) you play this turn');
    if (r != null) {
      final f = filter(r[2], Owner.yours, cardTypes: true);
      if (f == null) return null;
      return [Static(printed, W1FirstDiscount(f, int.parse(r[1])))];
    }
    r = rx(t, r'once during your turn, you may (.+)');
    if (r != null && !RegExp(r'^(?:when|whenever) ').hasMatch(r[1])) {
      final to = RegExp(r'^choose and discard (?:a|one) card to (.+)$').firstMatch(r[1]);
      final e = effects(to?.group(1) ?? r[1], _Ctx());
      if (e == null) return null;
      return [W1Activated(printed, Cost(discard: to == null ? 0 : 1), e, oncePerTurn: true, yourTurn: true)];
    }
    // An alternate cost from the hand (CR 4.3.2.2).
    r = rx(t, r'during your turn, you may banish (?:chosen|one of your|an?) (.+?) to play this character for free');
    if (r != null) {
      final f = filter(r[1], Owner.yours, cardTypes: true);
      if (f == null) return null;
      return [Static(printed, W1BanishToPlay(f.copyWith(owner: Owner.yours)), inHand: true)];
    }
    r = rx(t, r'if you used shift to play this character, you may draw (\w+) cards? when (?:he|she|they|it) enters play');
    if (r != null) {
      final n = numWord(r[1]);
      if (n == null) return null;
      return [Triggered(printed, const OnPlay(), May(Draw(Who.you, Fixed(n))), condition: const ShiftedCond())];
    }
    // "{e}, 2 {i}, Banish 2 of your items - …".
    r = rx(t, r'(.+?), banish (two|three|\d+) of your (.+?) - (.+)');
    if (r != null) {
      final cost = _cost(r[1]);
      final n = numWord(r[2]);
      final f = filter(_plural(r[3]), Owner.yours, cardTypes: true);
      final e = effects(r[4], _Ctx());
      if (cost == null || n == null || f == null || e == null) return null;
      return [W1Activated(printed, cost, e, banish: f.copyWith(owner: Owner.yours), banishCount: n)];
    }
    if (rx(t, r'whenever one of your other characters? would be dealt damage, put that many damage counters on this character instead') != null) {
      return [Static(printed, const W1RedirectDamage(Filter(owner: Owner.yours, other: true)))];
    }
    r = rx(t, r"at the end of each player's turn, if they have more than (\d+) cards in their hand, they choose and discard cards until they have (\d+)\. if they have fewer than (\d+) cards in their hand, they draw until they have (\d+)");
    if (r != null && {r[1], r[2], r[3], r[4]}.length == 1) {
      return [Triggered(printed, const TurnStep(start: false, yours: false), W1HandToSize(int.parse(r[1])))];
    }
    // "…is challenged and banished, banish the challenging character": the other card.
    r = rx(t, r'(whenever .+? is challenged and banished), banish the challenging character');
    if (r != null) {
      final heads = _quiet(() => _triggerHead(r![1]));
      if (heads == null) return null;
      return [for (final tr in heads) Triggered(printed, tr.$1, const Banish(EventCard(other: true)), during: tr.$2)];
    }
    if (rx(t, r'whenever you use the boost ability of (?:a|one of your) characters?, you may put the top card of your deck under (?:them|him|her|it) facedown') != null) {
      return [Triggered(printed, const W1Boosted(), const May(W1TopUnder(EventCard())))];
    }
    r = rx(t, r"whenever this character is challenged, the challenging player may choose and discard a card\. if they don't, you gain (\d+) lore");
    if (r != null) {
      return [Triggered(printed, const CardEvent(Event.isChallenged), EachMay(Who.challenger, const Discard(Who.you, Fixed(1)), lorePerRefusal: int.parse(r[1])))];
    }
    // "While you have only 1 character here, they get +2 {w} and +1 {l}".
    r = rx(t, r'while you have only (\d+|one) characters? here, they (gets? .+)');
    if (r != null) {
      const here = Filter(owner: Owner.yours, atThisLocation: true);
      final es = _predicate(r[2].replaceFirst(RegExp(r'^get '), 'gets '), here);
      if (es == null) return null;
      return [for (final e in es) Static(printed, e, condition: CountCond(here, Cmp.eq, numWord(r[1])!))];
    }
    // Abilities in quotes (CR 6.4): "your characters with Reckless gain '{e} - Gain 1 lore'".
    r = rx(t, r'(?:while (.+?), )?(.+?) gains? "(.+?)"( while here)?');
    if (r != null) {
      Cond? cond;
      if (r[1].isNotEmpty) {
        cond = condition(r[1]);
        if (cond == null) return null;
      }
      var f = _groupFilter(r[2]);
      if (f == null) return null;
      if (r[4].isNotEmpty) f = f.copyWith(atThisLocation: true);
      final quoted = RegExp(r'"(.+?)"').firstMatch(printed);
      final a = quoted == null ? null : _w1Quoted(quoted.group(1)!);
      if (a == null) return null;
      return [Static(printed, W1GrantAbility(f, a), condition: cond)];
    }
    return null;
  }

  /// An ability in quotes, read as this card's own paragraph.
  Ability? _w1Quoted(String text) {
    final s = text.trim().replaceFirst(RegExp(r'\.$'), '');
    final list = _paragraph(Paragraph('', s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}.'));
    return list == null || list.length != 1 ? null : list.first;
  }

  List<Ability>? _w1Action(Paragraph p, String t) {
    final m = rx(t, r"you can't play this action unless (.+?)\. (.+)");
    if (m == null) return null;
    final c = condition(m[1]);
    final e = effects(m[2], _Ctx());
    if (c == null || e == null) return null;
    return [Static(p.printed, const W1PlayOnlyIf(), condition: c, inHand: true), ActionEffect(p.printed, e)];
  }

  // -------------------------------------------------------------------------------------------
  // Whole effects
  // -------------------------------------------------------------------------------------------

  Effect? _w1Effects(String text, _Ctx ctx) {
    // "Choose one: * A. * B." (a third kind of bullet).
    if (text.contains(': * ')) return effects(text.replaceFirst(': * ', ': • ').replaceAll('. * ', '. • '), ctx);
    List<String>? m;
    m = rx(text, r'(you may )?put any number of cards from your hand on the bottom of your deck in any order\. if you do, draw that number of cards plus (\d+)');
    if (m != null) return W1HandToBottom(drawPlus: int.parse(m[2]));
    // Searching the deck (CR 7.2).
    m = rx(text, r'(you may )?search your deck for (.+?) and reveal that card to all players\. shuffle your deck and put that card on top of it');
    if (m != null) return _w1May(m[1], _w1Search(m[2], W1SearchDest.topAfterShuffle));
    m = rx(text, r'(you may )?search your deck for (.+?) and reveal that card to all players\. put that card into your hand and shuffle your deck');
    if (m != null) return _w1May(m[1], _w1Search(m[2], W1SearchDest.hand));
    m = rx(text, r'(you may )?search your deck for (.+?), reveal it, and put it (?:in|into) your hand\. if you do, shuffle your deck');
    if (m != null) return _w1May(m[1], _w1Search(m[2], W1SearchDest.hand));
    m = rx(text, r'(you may )?gain lore equal to the lore of (?:a|an) (.+?) in your discard\. if you do, put that card on the bottom of your deck');
    if (m != null) {
      final f = filter(m[2], Owner.yours, cardTypes: true);
      return f == null ? null : W1LoreFromDiscard(f);
    }
    m = rx(text, r'reveal a number of cards from the top of your deck equal to the number of cards under (?:him|her|them|it|this character)\. put all revealed (.+?) into your hand\. put the rest on the bottom of your deck in any order');
    if (m != null) {
      final f = filter(_plural(m[1]), Owner.any, cardTypes: true);
      return f == null ? null : W1RevealTake(const UnderSelf(), f);
    }
    m = rx(text, r'(you may )?reveal the top card of your deck\. if you do, you may play it\. otherwise, put it into your discard');
    if (m != null) return _w1May(m[1], const W1RevealMayPlay());
    m = rx(text, r'reveal cards from the top of your deck until you reveal (?:a|an) (.+?)\. put that card into your hand and shuffle the rest into your deck');
    if (m != null) {
      final f = filter(m[1], Owner.any, cardTypes: true);
      return f == null ? null : W1RevealUntil(f);
    }
    m = rx(text, r'each player reveals the top card of their deck\. draw a card for each different ink symbol on cards revealed this way');
    if (m != null) return const W1InkSymbols();
    m = rx(text, r'choose any number of players\. they discard their hands and draw (\w+) cards each');
    if (m != null) {
      final n = numWord(m[1]);
      return n == null ? null : W1RefreshPlayers(n);
    }
    if (text == 'for each character that sang this song, draw a card and gain 1 lore') return const Seq([Draw(Who.you, W1Singers()), GainLore(Who.you, W1Singers())]);
    m = rx(text, r"for each opposing player, you may choose a character of theirs\. they can't ready at the start of their next turn");
    if (m != null) return const W1EachOpponentPick(Filter(), Rule.cantReady);
    // "Chosen opponent chooses YES! or NO!: - YES! A. - NO! B." (CR 6.1.5.2).
    m = rx(text, r'chosen opponent chooses ([a-z!]+) or ([a-z!]+): - (.+?)\. - (.+)');
    if (m != null && m[3].startsWith('${m[1]} ') && m[4].startsWith('${m[2]} ')) {
      final a = effects(m[3].substring(m[1].length + 1), ctx);
      final b = _w1TheyChoose(m[4].substring(m[2].length + 1), ctx);
      if (a == null || b == null) return null;
      return W1OpponentChooses([a, b], [_w1Label(m[3]), _w1Label(m[4])]);
    }
    // "…If you do, their player may reveal the top card of their deck. If that card is a character
    // or item card, they may play it for free. Otherwise, they put it on the bottom of their deck."
    m = rx(text, r'(.+?)\. if you do, their player may reveal the top card of their deck\. if that card is (?:a|an) (.+?), they may play it for free\. otherwise, they put it on the bottom of their deck');
    if (m != null) {
      final first = effects(m[1], ctx);
      final fs = _zoneFilters(m[2]);
      if (first == null || fs == null) return null;
      return Seq([
        first,
        If(const DidIt(), EachMay(Who.thatPlayer, Peek(1, reveal: true, picks: [PeekPick(filters: fs, dest: ZoneDest.play)], rest: ZoneDest.bottom))),
      ]);
    }
    return null;
  }

  Effect? _w1May(String may, Effect? e) => e == null || may.isEmpty ? e : May(e);

  Effect? _w1Search(String what, W1SearchDest dest) {
    final fs = _zoneFilters(what);
    return fs == null ? null : W1Search(fs, dest);
  }

  String _w1Label(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// "They choose a character of theirs and put that card on the bottom of their deck": the chosen
  /// opponent's own pick.
  Effect? _w1TheyChoose(String s, _Ctx ctx) {
    final m = rx(s, r'they choose (?:a|one) (.+?) of theirs and put that card on the bottom of their deck');
    if (m == null) return effects(s, ctx);
    final f = filter(m[1], Owner.any, cardTypes: true);
    if (f == null) return null;
    final slot = ctx.nextSlot++;
    return PlayerChooses(Who.chosenOpponent, f, slot, ToDeck(Remembered(slot), bottom: true));
  }

  // -------------------------------------------------------------------------------------------
  // Clauses
  // -------------------------------------------------------------------------------------------

  Effect? _w1Clause(String c, _Ctx ctx) {
    List<String>? m;
    m = rx(c, r'(each opponent|each player|chosen opponent) puts? the top (\d+|card) cards? of their deck into their discard');
    if (m != null) return Mill(_who(m[1]), m[2] == 'card' ? 1 : int.parse(m[2]));
    if (c == 'ready those characters') return const W1ReadySingers();
    if (c == 'look at the top card of your deck and put it on either the top or the bottom of your deck') return const Peek(1, rest: ZoneDest.topOrBottom);
    if (c == 'play a character with the same name as this character for free') return const W1PlaySameName();
    if (c == 'move chosen character from here to another location for free') return const W1MoveFromHere();
    if (c == "draw cards equal to that location's lore") return const Draw(Who.you, W1LocationLore());
    if (c == 'choose and discard any number of cards, then draw that many cards') return const W1DiscardAny(thenDraw: true);
    if (c == 'put any card from your hand into your inkwell facedown') return const InkFromHand();
    if (c == "characters can't exert to sing songs until the start of your next turn") return const W1RuleForAll(Filter(), Rule.cantSing, Lasting.untilYourNextTurn);
    if (c == 'put all the cards in your hand on the bottom of your deck in any order') return const W1HandToBottom(all: true);
    if (c == 'ready each character you removed damage from this way') return const W1ReadyHealed();
    if (c == 'draw a card for each damage counter moved this way') return const Draw(Who.you, W1ThisWay());
    if (c == 'shuffle your deck') return const W1Shuffle();
    if (c == 'put that card from your discard into your inkwell facedown and exerted' && ctx.event) return const ToInkwell(EventCard(), exerted: true);
    m = rx(c, r'pay (\d+) ink to have (.+)');
    if (m != null) {
      final b = clause(m[2], ctx);
      return b == null ? null : Seq([PayInk(int.parse(m[1])), If(const DidIt(), b)]);
    }
    m = rx(c, r'(he|she|they|this character) takes? no damage from the challenge');
    if (m != null) {
      final t = ref(m[1], ctx);
      return t == null ? null : GrantRule(t, Rule.takesNoDamageFromChallenges, Lasting.thisTurn);
    }
    if (c == 'play another character with the same cost or less for free' && ctx.nextSlot > 0) return W1PlayFreeCostOf(ctx.nextSlot - 1);
    // Abilities in quotes for a while: "your other characters gain '{e} - Draw a card' this turn",
    // "your characters gain Challenger +2 and 'When this character…' this turn".
    m = rx(c, r'(.+?) gains? (?:(.+?) and )?"(.+?)" (this turn|until the start of your next turn)');
    if (m != null) {
      final dur = m[4] == 'this turn' ? Lasting.thisTurn : Lasting.untilYourNextTurn;
      final t = target(m[1], ctx);
      final a = _w1Quoted(m[3]);
      if (t == null || a == null) return null;
      final same = t is Chosen ? Remembered(t.slot) : t;
      final steps = <Effect>[];
      if (m[2].isNotEmpty) {
        final k = _timedPredicate('gains ${m[2]}', t, dur);
        if (k == null) return null;
        steps.add(k);
      }
      steps.add(W1GrantTimed(steps.isEmpty ? t : same, dur, ability: a));
      return steps.length == 1 ? steps.first : Seq(steps);
    }
    m = rx(c, r'(.+?) gains? (.+?) and the (\w+) classification (this turn|until the start of your next turn)');
    if (m != null) {
      final dur = m[4] == 'this turn' ? Lasting.thisTurn : Lasting.untilYourNextTurn;
      final t = target(m[1], ctx);
      if (t == null) return null;
      final k = _timedPredicate('gains ${m[2]}', t, dur);
      if (k == null || !knownClassifications.contains(m[3])) return null;
      return Seq([k, W1GrantTimed(t is Chosen ? Remembered(t.slot) : t, dur, cls: _cap(m[3]))]);
    }
    m = rx(c, r'move all damage counters from all other characters to (.+)');
    if (m != null) {
      final t = target(m[1], ctx);
      return t == null ? null : W1MoveAllDamageTo(t);
    }
    m = rx(c, r'move (.+?) and up to (\w+) of your other characters to that location for free');
    if (m != null) {
      final a = target(m[1], ctx);
      final n = numWord(m[2]);
      if (a == null || n == null) return null;
      return MoveToLocation([a, Chosen(const Filter(owner: Owner.yours, other: true), count: n, upTo: true, slot: ctx.nextSlot++, word: false)], toEventLocation: true);
    }
    m = rx(c, r'(?:that player|their player|they) may play (?:a|an) (.+?) from their discard for free');
    if (m != null) {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      return f == null ? null : W1PlayFreeFrom(Who.thatPlayer, f, const [Place.discard]);
    }
    m = rx(c, r'play (?:a|an) (.+?) from your hand or discard(?: with cost (\d+) or less)? for free');
    if (m != null) {
      var f = filter(m[1], Owner.yours, cardTypes: true);
      if (f == null) return null;
      if (m[2].isNotEmpty) f = f.copyWith(costMax: int.parse(m[2]));
      return W1PlayFreeFrom(Who.you, f, const [Place.hand, Place.discard]);
    }
    m = rx(c, r'return a character card with (\d+) willpower or more from your discard to your hand');
    if (m != null) return W1ReturnByWillpower(int.parse(m[1]));
    // "Put a card from your hand into your inkwell facedown to draw a card": only with a card to
    // put (CR 6.1.5.1).
    m = rx(c, r'put a card from your hand into your inkwell facedown to (.+)');
    if (m != null) {
      final b = _clauses(m[1], ctx);
      return b == null ? null : If(const HandCond(Who.you, Cmp.ge, 1), Seq([const InkFromHand(), b]));
    }
    m = rx(c, r'(each opponent|each player|chosen opponent) chooses one of their (.+?) and returns that card to their hand');
    if (m != null) return clause('${m[1]} chooses one of their ${m[2]} and returns it to their hand', ctx);
    m = rx(c, r'draw a card for each card under (?:him|her|them|it|this character)');
    if (m != null) return const Draw(Who.you, UnderSelf());
    m = rx(c, r'draw a card for each card that was under (?:him|her|them|it)');
    if (m != null) return const Draw(Who.you, W1UnderEvent());
    m = rx(c, r'(each opponent|each player|chosen opponent) chooses and discards a card for each card that was under (?:him|her|them|it)');
    if (m != null) return Discard(_who(m[1]), const W1UnderEvent());
    m = rx(c, r'banish one of your (.+?) to banish chosen (.+?) with less strength than that character');
    if (m != null) {
      final a = filter(_plural(m[1]), Owner.yours, cardTypes: true);
      final b = filter(_plural(m[2]), Owner.any, cardTypes: true);
      if (a == null || b == null) return null;
      return W1BanishWeaker(a.copyWith(owner: Owner.yours), b);
    }
    m = rx(c, r'search your deck for (.+?),? (?:and )?reveal (?:that card|it) to all players,? and put (?:it|that card) (?:into|in) your hand');
    if (m != null) {
      final fs = _zoneFilters(m[1]);
      return fs == null ? null : W1Search(fs, W1SearchDest.hand, shuffle: false);
    }
    m = rx(c, r'ready (all .+?), they can.t quest for the rest of this turn');
    if (m != null) {
      final t = target(m[1], ctx);
      return t is! AllOf ? null : Seq([Ready(t), GrantRule(t, Rule.cantQuest, Lasting.thisTurn)]);
    }
    m = rx(c, r'move (\d+|a|one) damage(?: counters?)? from each other character to (them|him|her|it|that character)');
    if (m != null) {
      final t = ref(m[2], ctx);
      return t == null ? null : W1MoveDamageEach(const Filter(), t, numWord(m[1])!);
    }
    m = rx(c, r'move (\d+|a|one) damage(?: counters?)? from each (.+?) to (.+)');
    if (m != null) {
      final f = filter(m[2], Owner.yours, cardTypes: true);
      final t = target(m[3], ctx);
      if (f == null || t == null) return null;
      return W1MoveDamageEach(f, t, numWord(m[1])!);
    }
    m = rx(c, r'each player chooses (\w+) of their characters and puts them into their inkwell facedown and exerted');
    if (m != null) {
      final n = numWord(m[1]);
      if (n == null) return null;
      final slot = ctx.nextSlot++;
      final put = ToInkwell(Remembered(slot), exerted: true);
      return n == 1 ? PlayerChooses(Who.each, const Filter(), slot, put) : W1EachChoosesN(Who.each, const Filter(), n, slot, put);
    }
    m = rx(c, r'(?:all|each) opponents? loses? (\d+) lore and you gain lore equal to the lore lost this way');
    if (m != null) return W1StealLore(int.parse(m[1]));
    m = rx(c, r'(?:they|that player) chooses? and discards? (a|one|two|\d+) cards?');
    if (m != null) return Discard(Who.thatPlayer, Fixed(numWord(m[1])!));
    m = rx(c, r'the player or players with the most cards in their hand chooses? and discards? (a|one|\d+) cards?');
    if (m != null) return W1MostCardsDiscard(numWord(m[1])!);
    m = rx(c, r'choose and discard any number of (.+?) to gain (\d+) lore for each .+? discarded this way');
    if (m != null) {
      final f = filter(_plural(m[1]), Owner.any, cardTypes: true);
      if (f == null) return null;
      return Seq([W1DiscardAny(filter: f), GainLore(Who.you, W1ThisWay(per: int.parse(m[2])))]);
    }
    m = rx(c, r'(put .+? from your discard on the bottom of your deck(?: in any order)?) to gain (\d+) lore for each .+? moved this way');
    if (m != null) {
      final a = clause(m[1], ctx);
      if (a is! FromDiscard) return null;
      return Seq([W1Counted(a), GainLore(Who.you, W1ThisWay(per: int.parse(m[2])))]);
    }
    m = rx(c, r'gain (\d+) lore for each (\d+) damage removed this way');
    if (m != null && m[2] == '1') return GainLore(Who.you, W1ThisWay(per: int.parse(m[1])));
    m = rx(c, r'put the top card of your deck under (this location|this character|this item) facedown');
    if (m != null) return const W1TopUnder(This());
    m = rx(c, r"(.+?) doesn't ready at the start of (?:their|its|his|her) next turn");
    if (m != null) {
      final t = target(m[1], ctx);
      return t == null ? null : GrantRule(t, Rule.cantReady, Lasting.theirNextTurn);
    }
    // "While this item is in play, that location gains Evasive", "they can't challenge or quest
    // while this item is in play".
    m = rx(c, r'while this (?:item|location|character) is in play, (.+?) ((?:gains?|can.t) .+)') ?? rx(c, r'(.+?) ((?:gains?|can.t) .+?) while this (?:item|location|character) is in play');
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      final p = m[2];
      final out = <Effect>[];
      final kw = RegExp(r'^gains? (.+)$').firstMatch(p);
      if (kw != null) {
        final ks = _keywordList(kw.group(1)!);
        if (ks == null) return null;
        out.addAll([for (final k in ks) W1GrantTimed(t, Lasting.permanent, keyword: k, whileSource: true)]);
      } else {
        final rules = switch (p) {
          "can't challenge or quest" || "can't quest or challenge" => const [Rule.cantQuest, Rule.cantChallenge],
          "can't ready at the start of their turn" || "can't ready at the start of its turn" => const [Rule.cantReady],
          "can't quest" => const [Rule.cantQuest],
          "can't challenge" => const [Rule.cantChallenge],
          _ => null,
        };
        if (rules == null) return null;
        out.addAll([for (final r in rules) W1GrantTimed(t, Lasting.permanent, rule: r, whileSource: true)]);
      }
      return out.length == 1 ? out.first : Seq(out);
    }
    // "Choose a character": the choice, for "they" and "the chosen character" (CR 6.1.3).
    m = rx(c, r'choose (?:a|an) (.+)');
    if (m != null) {
      final f = filter(_plural(m[1]), Owner.any, cardTypes: true, chosenPhrase: true);
      return f == null ? null : W1Pick(Chosen(f, slot: ctx.nextSlot++));
    }
    // "X to give Y" (CR 6.1.5.1): Y only if X happened.
    m = rx(c, r'(.+?) to (give .+)');
    if (m != null) {
      final save = ctx.save();
      final a = clause(m[1], ctx);
      final b = a == null ? null : _clauses(m[2], ctx);
      if (a != null && b != null) {
        if (a is Discard && a.who == Who.you && a.amount is Fixed) return If(HandCond(Who.you, Cmp.ge, (a.amount as Fixed).n), Seq([a, b]));
        // "Put 2 character cards from your discard on the bottom of your deck to …": all of them.
        if (a is FromDiscard && a.who == Who.you && !a.upTo && !a.all && a.count > 1) return If(CountCond(a.filter, Cmp.ge, a.count, place: Place.discard), Seq([a, b]));
        return Seq([a, If(const DidIt(), b)]);
      }
      ctx.restore(save);
    }
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Conditions, triggers, statics and filters
  // -------------------------------------------------------------------------------------------

  Cond? _w1Condition(String s) {
    List<String>? m;
    if (s == "a card left a player's discard this turn") return const W1LeftDiscard();
    if (s == 'you discarded a card this turn') return const W1DiscardedThisTurn();
    if (s == 'you removed damage this way') return const W1DidSome();
    m = rx(s, r'you played (?:a|an) (.+?) this turn');
    if (m != null) {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      if (f != null && f.classes.isNotEmpty) return W1PlayedThisTurn(f);
    }
    m = rx(s, r'you have (another )?character with (\d+) willpower or more in play');
    if (m != null) return W1WillpowerCount(int.parse(m[2]), other: m[1].isNotEmpty);
    m = rx(s, r'you do and (.+)');
    if (m != null) {
      final c = condition(m[1]);
      return c == null ? null : AllConds([const DidIt(), c]);
    }
    if (rx(s, r"(?:he|she|they|it)(?:'s| is| are) at a location") != null) return const SelfState(atLocation: true);
    m = rx(s, r'you have (another |a |an )(.+?) or (?:a|an) (.+?) in play');
    if (m != null) {
      final a = condition('you have ${m[1]}${m[2]} in play');
      final b = condition('you have a ${m[3]} in play');
      if (a == null || b == null) return null;
      return Not(AllConds([Not(a), Not(b)]));
    }
    m = rx(s, r'(\d+) or more other cards were put into your discard this turn');
    if (m != null) return ThisTurnCond(TurnCount.putIntoDiscard, Cmp.ge, int.parse(m[1]));
    m = rx(s, r"there's a character with (evasive|ward|bodyguard|reckless|rush|support|challenger|resist|singer|boost) here");
    if (m != null) return CountCond(Filter(withKw: Kw.values.firstWhere((k) => k.name == m![1]), atThisLocation: true), Cmp.ge, 1, whose: Owner.any);
    return null;
  }

  List<(Trigger, Cond?, bool)>? _w1TriggerHead(String h) {
    var m = rx(h, r'whenever a character here (.+)');
    if (m != null) return _quiet(() => _triggerHead('whenever a character ${m![1]} while here'));
    m = rx(h, r'whenever you pay (\d+) ink or less to play (?:a|an) (.+)');
    if (m != null && m[2] != 'card') {
      final f = filter(m[2], Owner.yours, cardTypes: true);
      if (f == null) return null;
      return [(On(Happening.inkPaid, subject: f, by: Owner.yours, max: int.parse(m[1])), null, false)];
    }
    if (h == 'whenever one of your characters or locations with a card under them is challenged') return const [(W1ChallengedWithUnder(), null, false)];
    if (h == 'whenever they draw a card while this character is exerted') return const [(Draws(Owner.opposing, theirTurn: true), SelfState(exerted: true), false)];
    if (rx(h, r'whenever (?:this character|he|she|they) quests or challenges') != null) {
      return const [(CardEvent(Event.quests), null, false), (CardEvent(Event.challenges), null, false)];
    }
    return null;
  }

  List<StaticEffect>? _w1StaticEffect(String t) {
    List<String>? m;
    m = rx(t, r'(.+?) gains? the (\w+) classification');
    if (m != null && knownClassifications.contains(m[2])) {
      final f = _groupFilter(m[1]);
      return f == null ? null : [W1GrantClass(f, _cap(m[2]))];
    }
    m = rx(t, r'(.+?) loses? the (.+?) ability');
    if (m != null) {
      final f = _groupFilter(m[1]);
      return f == null ? null : [W1LoseAbility(f, m[2])];
    }
    m = rx(t, r'characters count as having \+(\d+) cost to sing songs while here');
    if (m != null) return [W1SingCost(const Filter(atThisLocation: true), int.parse(m[1]))];
    m = rx(t, r"opponents can't choose (your .+?) for abilities or effects");
    if (m != null) {
      final f = _groupFilter(m[1]);
      return f == null ? null : [W1Unchoosable(f)];
    }
    m = rx(t, r'you pay (\d+) ink less to shift a character on top of this character');
    if (m != null) return [W1ShiftOntoDiscount(int.parse(m[1]))];
    m = rx(t, r'for each (.+?), you pay (\d+) ink less to play this character using (?:her|his|their|its) shift ability');
    if (m != null) {
      final c = countOf(m[1], per: int.parse(m[2]));
      return c == null ? null : [W1ShiftDiscount(c)];
    }
    m = rx(t, r'this character gains shift (\d+)(?: ink)?');
    if (m != null) return [W1HandShift(Keyword(Kw.shift, n: int.parse(m[1])))];
    m = rx(t, r'you can have other (.+?) characters in your deck regardless of ink type');
    if (m != null && knownClassifications.contains(m[1])) return [W1InkException(m[1])];
    m = rx(t, r'this character can challenge ready (.+)');
    if (m != null) {
      final f = filter(_plural(m[1]), Owner.any, cardTypes: true);
      if (f != null && f.classes.isNotEmpty) return [W1ChallengeReady(f)];
    }
    m = rx(t, r'(.+?) with (\d+) strength or more gets? \+(\d+) (lore|willpower)');
    if (m != null) {
      final f = _groupFilter(m[1]);
      return f == null ? null : [W1ModIfStrength(f, int.parse(m[2]), _stat(m[4]), int.parse(m[3]))];
    }
    m = rx(t, r"(.+?)'s? strength can't be reduced below (?:their|its) printed values?");
    if (m != null) {
      final f = _groupFilter(m[1]);
      return f == null ? null : [W1StrengthFloor(f)];
    }
    m = rx(t, r"opponents can't play (.+)");
    if (m != null) {
      final f = filter(m[1], Owner.any, cardTypes: true);
      return f == null ? null : [W1OpponentsCantPlay(f)];
    }
    m = rx(t, r"each player pays (\d+) ink more to play (.+?)(?:\. this doesn't apply to singing songs\.?\)?)?");
    if (m != null) {
      final f = filter(m[2], Owner.any, cardTypes: true);
      return f == null ? null : [W1CostIncrease(f, int.parse(m[1]))];
    }
    return null;
  }

  /// Card phrases the general grammar doesn't read: inks ("Sapphire character"), "Hunny card",
  /// "non-character", "character here", "character with Boost".
  Filter? _w1Filter(String s0, Owner owner, bool cardTypes, bool chosenPhrase) {
    final s = s0.trim();
    var m = rx(s, '(other )?($_inkWords) characters?');
    if (m != null) return Filter(owner: owner, other: m[1].isNotEmpty, classes: ['$w1InkClass${m[2]}']);
    if (s == 'non-character' || s == 'non-character card') return Filter(types: const {CardType.action, CardType.item, CardType.location}, owner: owner);
    // "Here" is this location, or on a character the location it's at.
    m = rx(s, r'(.+) here');
    if (m != null) {
      final here = card.type == CardType.location;
      return filter(m[1], owner, cardTypes: cardTypes, chosenPhrase: chosenPhrase)?.copyWith(atThisLocation: here, atSourcesLocation: !here);
    }
    m = rx(s, r'(.+) with boost');
    if (m != null) return filter(m[1], owner, cardTypes: cardTypes, chosenPhrase: chosenPhrase)?.copyWith(withKw: Kw.boost);
    m = rx(s, r'([a-z ]+?) cards?');
    if (m != null && m[1] != 'song' && knownClassifications.contains(m[1])) return Filter(types: _allTypes, owner: owner, classes: [_cap(m[1])]);
    return null;
  }
}
