part of 'parser.dart';

/// Templates for the cards Miracle Candle … Scrooge McDuck (IR in ir_wave2_s3.dart): costs
/// printed into a story name, "once during your turn, you may pay …" abilities, effects that
/// last for a challenge or wait for a later event, "for each … this way" counts, free plays from
/// other zones, moving and singing costs, and more conditions. Each hook is tried before the
/// general grammar, so the patterns here are anchored and specific.
extension _S3 on _CardParser {
  // -------------------------------------------------------------------------------------------
  // Paragraphs
  // -------------------------------------------------------------------------------------------

  List<Ability>? _s3Paragraph(Paragraph p) {
    // "Abuela's Gift - Banish this item: …", "I'M STUCK! Banish this item - …": the cost was
    // read as part of the story name (CR 6.3.1).
    final split = _s3NameCost(p);
    if (split != null) return split;
    // "{e}- Chosen character gains Support this turn".
    final dash = RegExp(r'^\{e\}-\s+', caseSensitive: false).firstMatch(p.body);
    if (dash != null) return _paragraph(Paragraph(p.name, '{e} - ${p.body.substring(dash.end)}'));
    final t = _lower(p.body);
    final printed = p.printed;
    // Like Boost (CR 8.4.1): "once during your turn, you may pay 2 {i} to …" is used as an
    // activated ability.
    var m = rx(t, r'once (?:per turn|during your turn), you may (pay (\d+) ink|discard a card|choose and discard a card) to (.+)');
    if (m != null) {
      final e = effects(m[3], _Ctx());
      if (e == null) return null;
      final cost = m[2].isNotEmpty ? Cost(ink: int.parse(m[2])) : const Cost(discard: 1);
      return [Activated(printed, cost, OncePerTurn(e))];
    }
    m = rx(t, r'once during your turn, you may pay (\d+) ink less to move this character to a location');
    if (m != null) return [Static(printed, MoveCost(less: int.parse(m[1]), once: true))];
    // "While you have 3 or more characters here, you may banish this location to play …".
    m = rx(t, r'while (.+?), you may banish this (?:location|item|character) to (.+)');
    if (m != null) {
      final c = condition(m[1]);
      final e = c == null ? null : effects(m[2], _Ctx());
      if (e == null) return null;
      return [Activated(printed, const Cost(banishSelf: true), Gated(c!, e))];
    }
    m = rx(t, r"you can't play this (?:character|item|location|action) unless (.+)");
    if (m != null) {
      final c = condition(m[1]);
      return c == null ? null : [Static(printed, CantPlayUnless(c), inHand: true)];
    }
    m = rx(t, r"this character can't quest or challenge unless you pay (\d+) ink");
    if (m != null) return [Static(printed, PayToQuestOrChallenge(int.parse(m[1])))];
    // "For each character you have here, you pay 1 {i} less for the first action you play each
    // turn" (CR 4.3.6).
    m = rx(t, r'for each character you have here, you pay (\d+) ink less for the first action you play each turn');
    if (m != null) {
      return [
        Static(
          printed,
          CostReduction(const Filter(types: {CardType.action}, owner: Owner.yours), CountOf(const Filter(owner: Owner.yours, atThisLocation: true), per: int.parse(m[1]))),
          condition: const ThisTurnCond(TurnCount.actionsPlayed, Cmp.eq, 0),
        ),
      ];
    }
    // "While this character is exerted, if you have a character named Pain in play, …".
    m = rx(t, r'while (.+?), if (.+?), (.+)');
    if (m != null) {
      final a = condition(m[1]), b = condition(m[2]);
      final es = a == null || b == null ? null : _staticEffect(m[3]);
      if (es == null) return null;
      return [
        for (final e in es) Static(printed, e, condition: AllConds([a!, b!])),
      ];
    }
    // "While this character is exerted, opposing characters can't exert to sing songs and your
    // Pirate characters gain Resist +1": two statics with one condition.
    m = rx(t, r'while (.+?), ((?:your|opposing) .+? and (?:your|opposing) .+)');
    if (m != null) {
      final c = condition(m[1]);
      if (c == null) return null;
      for (final sep in RegExp(r' and (?=your |opposing )').allMatches(m[2])) {
        final a = _quietStatic(m[2].substring(0, sep.start)), b = _quietStatic(m[2].substring(sep.end));
        if (a != null && b != null) return [for (final e in [...a, ...b]) Static(printed, e, condition: c)];
      }
      return null;
    }
    // "When this character challenges and is banished, you may banish the challenged character":
    // the challenged character is the one that banished it.
    m = rx(t, r'when this character challenges and is banished, (you may )?banish the challenged character');
    if (m != null) {
      const e = Banish(EventCard(other: true));
      return [Triggered(printed, const CardEvent(Event.banishedInChallenge), m[1].isEmpty ? e : const May(e), during: const AsChallenger())];
    }
    return null;
  }

  List<StaticEffect>? _quietStatic(String t) {
    final d = LorcanaParser.diag;
    final n = d?.length ?? 0;
    final r = _staticEffect(t);
    if (r == null && d != null && d.length > n) d.removeRange(n, d.length);
    return r;
  }

  /// A story name that ends in a cost: re-reads it as "[name] [cost] - [effect]".
  List<Ability>? _s3NameCost(Paragraph p) {
    if (p.name.isEmpty) return null;
    final words = p.name.split(' ');
    for (var i = 1; i < words.length; i++) {
      var cost = words.skip(i).join(' ');
      if (cost.startsWith('- ')) cost = cost.substring(2);
      if (!RegExp(r'^(banish this|choose and discard|discard|\{e\}|\d+ \{i\})', caseSensitive: false).hasMatch(cost)) continue;
      if (_cost(_lower(cost)) == null) continue;
      var name = words.take(i).join(' ').trim();
      if (name.endsWith(' -')) name = name.substring(0, name.length - 2);
      return _paragraph(Paragraph(name, '$cost - ${p.body}'));
    }
    return null;
  }

  /// An action that starts with its own cost reduction ("If you have a character with 5 {s} or
  /// more in play, you pay 2 {i} less to play this action. Ready chosen character. …").
  List<Ability>? _s3Action(Paragraph p) {
    final t = _lower(p.body);
    final m = rx(t, r'if ([^.]+?), you pay (\d+) ink less to play this (?:action|song)\. (.+)');
    if (m == null) return null;
    final c = condition(m[1]);
    final e = c == null ? null : effects(m[3], _Ctx());
    if (e == null) return null;
    return [Static(p.printed, CostReduction(const Filter(), Fixed(int.parse(m[2])), self: true), condition: c, inHand: true), ActionEffect(p.printed, e)];
  }

  // -------------------------------------------------------------------------------------------
  // Static effects
  // -------------------------------------------------------------------------------------------

  List<StaticEffect>? _s3StaticEffect(String t) {
    if (t == 'you can ink cards from your discard') return const [InkFromDiscard()];
    if (t == 'you may play any character with shift on this character as if this character had any name') return const [ShiftName(null)];
    if (t == 'each turn, only one character can challenge') return const [OneChallengerPerTurn()];
    if (t == 'each opponent plays with the top card of their deck faceup') return const [TopCardFaceUp()];
    if (rx(t, r'this character takes no damage from challenges?') != null) return const [StaticRule(null, Rule.takesNoDamageFromChallenges)];
    var m = rx(t, r'this character gains (.+) this turn');
    if (m != null) {
      final kws = _keywordList(m[1]);
      return kws == null ? null : [for (final k in kws) StaticKeyword(null, k)];
    }
    m = rx(t, r'(.+?) counts? as having \+(\d+) cost to sing songs');
    if (m != null) {
      final f = _groupFilter(m[1]);
      return f == null ? null : [SingCost(f, int.parse(m[2]))];
    }
    m = rx(t, r'(.+?) can move here for free');
    if (m != null) {
      final f = _groupFilter(m[1]);
      return f == null ? null : [MoveCost(filter: f, here: true, free: true)];
    }
    m = rx(t, r'you pay (\d+) ink less to move (?:a character of yours|your characters) here');
    if (m != null) return [MoveCost(filter: const Filter(owner: Owner.yours), here: true, less: int.parse(m[1]))];
    m = rx(t, r'for each opposing character banished in a challenge this turn, you pay (\d+) ink less to play this character');
    if (m != null) return [CostReduction(const Filter(), BanishedInChallengeCount(Owner.opposing, per: int.parse(m[1])), self: true)];
    m = rx(t, r'for each 1 damage on opposing characters, you pay (\d+) ink less to play this character');
    if (m != null) return [CostReduction(const Filter(), DamageOnAll(const Filter(owner: Owner.opposing), per: int.parse(m[1])), self: true)];
    return null;
  }

  CountOf? _s3CountOf(String s, int per) {
    if (s == 'damaged character opponents have in play') return CountOf(const Filter(damaged: true, owner: Owner.opposing), whose: Owner.opposing, per: per);
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Triggers
  // -------------------------------------------------------------------------------------------

  List<(Trigger, Cond?, bool)>? _s3TriggerHead(String h) {
    // "Challenges another character": not a location (CR 4.6).
    if (rx(h, r'(?:when|whenever) (?:this character|he|she|they) challenges another character') != null) return [(const CardEvent(Event.challenges, other: Filter()), null, false)];
    // "Whenever you play another Steel character": not this one (CR 6.1.6).
    final m = rx(h, r'whenever you play another (.+)');
    if (m != null && !m[1].contains(' with ')) {
      final f = filter(m[1], Owner.any, cardTypes: true);
      if (f != null) return [(CardPlayed(f.copyWith(other: true)), null, false)];
    }
    return null;
  }

  /// A trigger about a character being challenged (CR 4.6).
  bool _s3Defending(Trigger t) => t is CardEvent && (t.event == Event.isChallenged || t.event == Event.banishedInChallenge);

  // -------------------------------------------------------------------------------------------
  // Conditions
  // -------------------------------------------------------------------------------------------

  Cond? _s3Condition(String s) {
    if (s == 'all cards in your inkwell are exerted') return const AllInkExerted();
    if (s == "you didn't put any cards into your inkwell this turn") return const InkedThisTurn(Cmp.eq, 0);
    if (s == 'an opponent has more lore than you') return const OpponentMoreLore();
    if (s == "you've put a card under one of your characters or locations this turn") return const PutUnderThisTurn();
    if (s == 'an opposing character was damaged this turn') return const OpposingDamagedThisTurn();
    if (s == "you've played a song this turn") return const TurnStatCond(TurnStat.songsPlayed, Who.you, Cmp.ge, 1);
    var m = rx(s, r'an opponent has (\d+) lore');
    if (m != null) return LoreCond(Who.opponents, Cmp.eq, int.parse(m[1]));
    m = rx(s, r"there's an? (.+?) in your discard");
    if (m != null) {
      final fs = _zoneFilters(m[1]);
      return fs == null || fs.length != 1 ? null : CountCond(fs.first, Cmp.ge, 1, place: Place.discard);
    }
    m = rx(s, r"you don't have (?:a|an|any) (.+?) in play");
    if (m != null) {
      final f = filter(_plural(m[1]), Owner.yours, cardTypes: true);
      return f == null ? null : CountCond(f, Cmp.eq, 0);
    }
    m = rx(s, r'you have (\d+) or more (.+?) here');
    if (m != null) {
      final f = filter(_plural(m[2]), Owner.yours);
      return f == null ? null : CountCond(f.copyWith(atThisLocation: true), Cmp.ge, int.parse(m[1]));
    }
    m = rx(s, r'you have (?:a|an) (.+?) and (?:a|an) (.+?) in play');
    if (m != null) {
      final a = filter(m[1], Owner.yours, cardTypes: true), b = filter(m[2], Owner.yours, cardTypes: true);
      if (a != null && b != null) return AllConds([CountCond(a, Cmp.ge, 1), CountCond(b, Cmp.ge, 1)]);
    }
    // "This character is exerted and you don't have a Captain character in play".
    for (final sep in RegExp(' and ').allMatches(s)) {
      final d = LorcanaParser.diag;
      final n = d?.length ?? 0;
      final a = condition(s.substring(0, sep.start));
      final b = a == null ? null : condition(s.substring(sep.end));
      if (a != null && b != null) return AllConds([a, b]);
      if (d != null && d.length > n) d.removeRange(n, d.length);
    }
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Templates over several sentences
  // -------------------------------------------------------------------------------------------

  (Effect, int)? _s3Span(List<String> ss, int i, _Ctx ctx) {
    final s = ss[i];
    String? at(int k) => i + k < ss.length ? ss[i + k] : null;
    // "Play a character with cost 5 or less for free. They gain Rush.": they are the card played.
    var m = rx(s, r'(you may )?play (?:a|an) (.+?)(?: with cost (\d+) or less)? for free');
    if (m != null && at(1) != null && RegExp(r'^(they|he|she|it) ').hasMatch(at(1)!)) {
      var f = filter(m[2], Owner.yours, cardTypes: true);
      if (f == null) return null;
      if (m[3].isNotEmpty) f = f.copyWith(costMax: int.parse(m[3]));
      final Effect e = PlayFreeFrom(f, slot: ctx.nextSlot++);
      return (m[1].isEmpty ? e : May(e), 1);
    }
    // "Choose a character. Banish all other characters with the same name as that character."
    if (s == 'choose a character' && at(1) == 'banish all other characters with the same name as that character') {
      final chosen = Chosen(const Filter(), slot: ctx.nextSlot++);
      final into = ctx.nextSlot++;
      return (Seq([SameNameAs(chosen, const Filter(), into), Banish(Remembered(into))]), 2);
    }
    // "Count the number of characters you have in play. Chosen character loses {s} equal to that
    // number until the start of your next turn."
    m = rx(s, r'count the number of (.+?)');
    if (m != null && at(1) != null) {
      final c = countOf(m[1]);
      final x = rx(at(1)!, r'(.+?) loses (strength|willpower|lore) equal to that number (this turn|until the start of your next turn)');
      if (c == null || x == null) return null;
      final t = target(x[1], ctx);
      if (t == null) return null;
      return (Modify(t, _stat(x[2]), c, x[3] == 'this turn' ? Lasting.thisTurn : Lasting.untilYourNextTurn, negative: true), 2);
    }
    // "Look at a number of cards from the top of your deck equal to the number of cards under
    // him. Put one into your hand and put the rest on the bottom of your deck in any order."
    m = rx(s, r'look at a number of cards from the top of your deck equal to the number of cards under (?:him|her|it|them|this character)');
    if (m != null && at(1) != null && rx(at(1)!, r'put one into your hand and (?:put )?the rest on the bottom of your deck(?: in any order)?') != null) {
      return (const PeekFor(UnderSelf(), Peek(0, picks: [PeekPick(optional: false)], rest: ZoneDest.bottom)), 2);
    }
    // "Look at the cards in your inkwell. You may play a Puppy character from there for free."
    if (s == 'look at the cards in your inkwell' && at(1) != null) {
      final x = rx(at(1)!, r'(you may )?play (?:a|an) (.+?) from there for free');
      final f = x == null ? null : filter(x[2], Owner.yours, cardTypes: true);
      if (f == null) return null;
      final Effect e = PlayFreeFrom(f, from: const [Place.inkwell]);
      return (x![1].isEmpty ? e : May(e), 2);
    }
    // "Shuffle your deck, then reveal the top card. If it's an action card, you may play it for
    // free. Otherwise, put it on the bottom of your deck, then …"
    if (s == 'shuffle your deck, then reveal the top card' && at(2) != null) {
      final x = rx(at(1)!, r"if it's an? (.+?) card, you may play it for free");
      final y = rx(at(2)!, r'otherwise, put it on the bottom of your deck, then (.+)');
      final f = x == null ? null : filter('${x[1]} card', Owner.yours, cardTypes: true);
      final rest = y == null ? null : _clauses(y[1], ctx);
      if (f == null || rest == null) return null;
      return (Seq([const ShuffleDeck(), RevealTopPlay(f, rest)]), 3);
    }
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Sentences that change the one before
  // -------------------------------------------------------------------------------------------

  bool _s3Step(String s, List<Effect> steps, _Ctx ctx) {
    if (steps.isEmpty) return false;
    final last = steps.last;
    void tally(Tallied what, Effect then) {
      steps
        ..removeLast()
        ..add(last is May ? May(Tally(last.e, what)) : Tally(last, what))
        ..add(then);
    }

    // "Draw a card for each 1 damage removed this way" (CR 6.1.8).
    if (s == 'draw a card for each 1 damage removed this way') {
      tally(Tallied.damageRemoved, const Draw(Who.you, TallyOf(Tallied.damageRemoved)));
      return true;
    }
    var m = rx(s, r'for each 1 damage removed this way, you pay (\d+) ink less for the next character you play this turn');
    if (m != null) {
      tally(Tallied.damageRemoved, NextCostLess(const Filter(), TallyOf(Tallied.damageRemoved, per: int.parse(m[1]))));
      return true;
    }
    m = rx(s, r'gain (\d+) lore for each character you moved');
    if (m != null) {
      tally(Tallied.movedCharacters, GainLore(Who.you, TallyOf(Tallied.movedCharacters, per: int.parse(m[1]))));
      return true;
    }
    if (s == 'draw a card for each 1 lore lost this way') {
      tally(Tallied.loreLostByOpponents, const Draw(Who.you, TallyOf(Tallied.loreLostByOpponents)));
      return true;
    }
    m = rx(s, r'(you may )?deal (\d+) damage to (.+?) for each item card put into your discard this way');
    if (m != null) {
      final t = target(m[3], ctx);
      if (t == null) return false;
      final Effect e = DealDamage(t, TallyOf(Tallied.itemsToDiscard, per: int.parse(m[2])));
      tally(Tallied.itemsToDiscard, m[1].isEmpty ? e : May(e));
      return true;
    }
    // "This damage can't be reduced by Resist."
    if (s == "this damage can't be reduced by resist" && last is DealDamage) {
      steps
        ..removeLast()
        ..add(IgnoreResist(last));
      return true;
    }
    // "Otherwise, put it on the top of your deck": the card from the discard the "if" was about.
    if (s == 'otherwise, put it on the top of your deck' && last is If && last.otherwise == null && last.then is FromDiscard) {
      final f = last.then as FromDiscard;
      steps
        ..removeLast()
        ..add(If(last.cond, f, FromDiscard(f.filter, who: f.who, count: f.count, upTo: f.upTo, dest: ZoneDest.top)));
      return true;
    }
    // "They can't quest for the rest of this turn" after "ready all your characters": they are
    // all of them.
    final all = _s3AllTarget(last);
    m = rx(s, r'(?:for the rest of this turn, )?they (.+?)(?: for the rest of this turn| this turn)?');
    if (all != null && m != null && (s.startsWith('for the rest of this turn') || s.endsWith('this turn'))) {
      final rules = <Effect>[];
      for (final part in m[1].split(' and ')) {
        final r = switch (part.trim()) {
          "can't quest" => Rule.cantQuest,
          "can't challenge" => Rule.cantChallenge,
          'take no damage from challenges' => Rule.takesNoDamageFromChallenges,
          _ => null,
        };
        if (r == null) return false;
        rules.add(GrantRule(all, r, Lasting.thisTurn));
      }
      steps.add(rules.length == 1 ? rules.first : Seq(rules));
      return true;
    }
    return false;
  }

  /// The group a "ready all your characters" step acted on.
  AllOf? _s3AllTarget(Effect e) => switch (e) {
    Ready(:final target) when target is AllOf => target,
    Exert(:final target) when target is AllOf => target,
    Seq(:final steps) when steps.isNotEmpty => _s3AllTarget(steps.first),
    _ => null,
  };

  // -------------------------------------------------------------------------------------------
  // Clauses
  // -------------------------------------------------------------------------------------------

  Effect? _s3Clause(String c, _Ctx ctx) {
    List<String>? m;
    // Inkwells.
    if (c == 'exert all cards in your inkwell') return const ExertInkwell(Who.you);
    m = rx(c, r'return (\d+|a|one|two) cards? at random from your inkwell to your hand');
    if (m != null) return InkwellToHand(numWord(m[1])!);
    if (c == 'this turn, you may put an additional card from your hand into your inkwell facedown') return const Mark(MarkKind.extraInk, Lasting.thisTurn);
    if (c == 'put the top card of your deck into your discard') return const Mill(Who.you, 1);

    // Rules for a while.
    if (c == "opponents can't play actions until the start of your next turn") return const Mark(MarkKind.noActions, Lasting.untilYourNextTurn);
    m = rx(c, r'you pay (\d+) ink less for the next character you shift this turn');
    if (m != null) return Mark(MarkKind.shiftLess, Lasting.thisTurn, amount: int.parse(m[1]));
    if (c == 'the next character you play this turn enters play exerted and gains bodyguard until the start of your next turn') {
      return const Mark(MarkKind.nextEntersExertedBodyguard, Lasting.thisTurn);
    }
    m = rx(c, r'your characters get \+(\d+) strength while challenging a location this turn');
    if (m != null) return Mark(MarkKind.challengingLocationBonus, Lasting.thisTurn, amount: int.parse(m[1]));
    m = rx(c, r"((?:your |opposing )?characters) can't (challenge|quest) (until the start of your next turn|this turn)");
    if (m != null) {
      final f = _groupFilter(m[1]);
      if (f == null) return null;
      return RuleForAll(f, m[2] == 'challenge' ? Rule.cantChallenge : Rule.cantQuest, m[3] == 'this turn' ? Lasting.thisTurn : Lasting.untilYourNextTurn);
    }
    m = rx(c, r'(.+?) counts? as having \+(\d+) cost to sing songs this turn');
    if (m != null) {
      final t = target(m[1], ctx);
      return t == null ? null : Mark(MarkKind.singBonus, Lasting.thisTurn, target: t, amount: int.parse(m[2]));
    }
    m = rx(c, r"(.+?) can't ready at the start of their next turn unless they're at a location");
    if (m != null) {
      final t = target(m[1], ctx);
      return t == null ? null : Mark(MarkKind.cantReadyUnlessAtLocation, Lasting.theirNextTurn, target: t);
    }
    m = rx(c, r'until the start of your next turn, the next time (they|he|she) would be dealt damage (?:they|he|she) takes? no damage instead');
    if (m != null) {
      final t = ref(m[1], ctx);
      return t == null ? null : Mark(MarkKind.damageShield, Lasting.untilYourNextTurn, target: t);
    }
    m = rx(c, r'the next time (they|he|she) challenges? (?:another|a) character this turn, gain (\d+) lore');
    if (m != null) {
      final t = ref(m[1], ctx);
      return t == null ? null : Mark(MarkKind.loreOnNextChallenge, Lasting.thisTurn, target: t, amount: int.parse(m[2]));
    }
    m = rx(c, r'ready (this character|him|her) after the challenge');
    if (m != null) return const Mark(MarkKind.readyAfterChallenge, Lasting.thisTurn, target: This());

    // During a challenge (CR 4.6).
    m = rx(c, r'(.+?) takes? no damage from the challenge');
    if (m != null) {
      final t = ref(m[1], ctx);
      return t == null ? null : ForChallenge(t, rule: Rule.takesNoDamageFromChallenges);
    }
    m = rx(c, r'(.+?) gains? (.+?) during (?:that|the) challenge');
    if (m != null) {
      final t = ref(m[1], ctx);
      final kws = _keywordList(m[2]);
      if (t == null || kws == null || kws.length != 1) return null;
      return ForChallenge(t, keyword: kws.first);
    }
    m = rx(c, r'(.+?) takes? no damage from challenges? (this turn|for the rest of this turn|until the start of your next turn)');
    if (m != null) {
      final t = target(m[1], ctx);
      return t == null ? null : GrantRule(t, Rule.takesNoDamageFromChallenges, m[2] == 'until the start of your next turn' ? Lasting.untilYourNextTurn : Lasting.thisTurn);
    }
    m = rx(c, r'(.+?) gains? "(?:this character|they) can challenge ready characters" (this turn)');
    if (m != null) {
      final t = target(m[1], ctx);
      return t == null ? null : GrantRule(t, Rule.canChallengeReady, Lasting.thisTurn);
    }

    // Stats for a while.
    m = rx(c, r"(.+?) gets? \+ ?(strength|willpower|lore) equal to (.+?)'?s? (strength|willpower|lore) (this turn|until the start of your next turn)");
    if (m != null) {
      final save = ctx.save();
      final t = target(m[1], ctx);
      final src = t == null ? null : ref(m[3], ctx);
      if (t != null && src != null) return Modify(t, _stat(m[2]), StatOf(src, _stat(m[4])), m[5] == 'this turn' ? Lasting.thisTurn : Lasting.untilYourNextTurn);
      ctx.restore(save);
    }
    m = rx(c, r'(.+?) gets? ([+-])(\d+) (strength|willpower|lore) and ([a-z +\d,]+?) (this turn|until the start of your next turn)');
    if (m != null) {
      final kws = _keywordList(m[5]);
      final save = ctx.save();
      final t = kws == null ? null : target(m[1], ctx);
      if (t != null) {
        final d = m[6] == 'this turn' ? Lasting.thisTurn : Lasting.untilYourNextTurn;
        return Seq([Modify(t, _stat(m[4]), Fixed(int.parse(m[3])), d, negative: m[2] == '-'), for (final k in kws!) GrantKeyword(t, k, d)]);
      }
      ctx.restore(save);
    }

    // Lore and cards.
    m = rx(c, r'(.+), to a maximum of (\d+) lore(?: each)?');
    if (m != null) {
      final e = clause(m[1], ctx);
      final cap = int.parse(m[2]);
      return switch (e) {
        GainLore(:final who, :final amount) => GainLore(who, Capped(amount, cap)),
        LoseLore(:final who, :final amount) => LoseLore(who, Capped(amount, cap)),
        _ => null,
      };
    }
    m = rx(c, r'(each opponent|chosen opponent) loses lore equal to the damage on (.+)');
    if (m != null) {
      final t = target(m[2], ctx);
      return t == null ? null : LoseLore(_who(m[1]), DamageOn(t));
    }
    if (c == 'draw a card for each card discarded') return const Draw(Who.you, EventAmount());
    m = rx(c, r"draw cards equal to (that character|this character|their|his|her|its)'?s? (strength|willpower|lore)");
    if (m != null) {
      final t = ref(m[1], ctx);
      return t == null ? null : Draw(Who.you, StatOf(t, _stat(m[2])));
    }
    m = rx(c, r'draw cards equal to the (strength|willpower|lore) of (.+)');
    if (m != null) {
      final t = target(m[2], ctx);
      return t == null ? null : Draw(Who.you, StatOfChosen(t, _stat(m[1])));
    }
    if (c == 'banish any number of your items, then draw a card for each item banished this way') {
      return Seq([
        Tally(
          Banish(
            Chosen(
              const Filter(types: {CardType.item}, owner: Owner.yours),
              count: 99,
              upTo: true,
              slot: ctx.nextSlot++,
              word: false,
            ),
          ),
          Tallied.itemsBanished,
        ),
        const Draw(Who.you, TallyOf(Tallied.itemsBanished)),
      ]);
    }
    m = rx(c, r'if they have more than (\d+) cards in their hand, they discard until they have (\d+) cards in their hand');
    if (m != null && m[1] == m[2]) return DiscardDownTo(Who.thatPlayer, int.parse(m[1]));
    m = rx(c, r"(chosen opponent|each opponent) reveals their hand and discards (?:a|an) (.+?) of their choice");
    if (m != null) {
      final fs = _zoneFilters(m[2]);
      return fs == null || fs.length != 1 ? null : RevealDiscardOwnChoice(_who(m[1]), fs.first);
    }

    // Damage.
    m = rx(c, r'deal the same amount of damage to (up to (\w+) other chosen characters|another chosen character)');
    if (m != null) {
      if (m[2].isEmpty) return const DealSameToOthers(1);
      final n = numWord(m[2]);
      return n == null ? null : DealSameToOthers(n, upTo: true);
    }
    m = rx(c, r'choose an? (.+?) and move (\d+) damage from each other character to (?:them|him|her|it)');
    if (m != null) {
      final f = filter(m[1], Owner.any);
      return f == null ? null : MoveDamageFromEach(Chosen(f, slot: ctx.nextSlot++), int.parse(m[2]));
    }
    m = rx(c, r'move (\d+) damage counters? from chosen character here to (.+)');
    if (m != null) {
      final from = Chosen(const Filter(atThisLocation: true), slot: ctx.nextSlot++);
      final to = target(m[2], ctx);
      return to == null ? null : MoveDamage(from, to, Fixed(int.parse(m[1])));
    }
    m = rx(c, r'(ready|exert) all other characters here(?:, they can.t quest for the rest of this turn)?');
    if (m != null) {
      const t = AllOf(Filter(other: true, atSourcesLocation: true));
      final Effect act = m[1] == 'ready' ? const Ready(t) : const Exert(t);
      return c.contains("can't quest") ? Seq([act, const GrantRule(t, Rule.cantQuest, Lasting.thisTurn)]) : act;
    }
    m = rx(c, r'(ready|exert) (all .+?) and deal (\d+) damage to each of them');
    if (m != null) {
      final t = target(m[2], ctx);
      if (t is! AllOf) return null;
      return Seq([m[1] == 'ready' ? Ready(t) : Exert(t), DealDamage(t, Fixed(int.parse(m[3])))]);
    }
    m = rx(c, r'choose (one of your .+?|an? .+?) and (ready|exert|banish) (?:them|him|her|it)');
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return switch (m[2]) {
        'ready' => Ready(t),
        'exert' => Exert(t),
        _ => Banish(t),
      };
    }

    // Moving cards.
    if (c.contains(' each to their player') || c.contains(' each to their hand')) return clause(c.replaceFirst(' each to their', ' to their'), ctx);
    m = rx(c, r'(each opponent|each player|chosen opponent) chooses one of their (.+?) and returns that card to their hand');
    if (m != null) return clause('${m[1]} chooses one of their ${m[2]} and returns them to their hand', ctx);
    m = rx(c, r'return all cards under (it|him|her|them|this character) to your hand');
    if (m != null) return const UnderTo(This(), ZoneDest.hand);
    m = rx(c, r'put the top card of your deck facedown under (.+)');
    if (m != null && !m[1].startsWith('one of your')) {
      final t = ref(m[1], ctx);
      return t == null ? null : PutTopUnder(t);
    }
    if (c == 'put this character facedown under one of your characters or locations with boost') {
      return const PutSelfUnder(Filter(types: {CardType.character, CardType.location}, owner: Owner.yours, withKw: Kw.boost));
    }
    m = rx(c, r'return chosen (.+?) with cost (\d+) to (?:your|their|their player.s) hand');
    if (m != null) {
      final f = filter(m[1], Owner.any, cardTypes: true);
      if (f == null) return null;
      final n = int.parse(m[2]);
      return ReturnToHand(
        Chosen(
          f.copyWith(costMin: n, costMax: n),
          slot: ctx.nextSlot++,
        ),
      );
    }

    // Playing cards.
    m = rx(c, r'play (this character|that character|that card|it) from your discard');
    if (m != null) {
      final t = ref(m[1], ctx);
      return t == null ? null : PlayPaying(t);
    }
    m = rx(c, r'play (?:a|an) (.+?) with cost (\d+) for free');
    if (m != null) {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      final n = int.parse(m[2]);
      return f == null ? null : PlayFreeFrom(f.copyWith(costMin: n, costMax: n));
    }
    m = rx(c, r'play (?:a|an) (.+?) from your hand or discard with cost (\d+) or less for free(, exerted)?');
    if (m != null) {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      return f == null
          ? null
          : PlayFreeFrom(
              f.copyWith(costMax: int.parse(m[2])),
              from: const [Place.hand, Place.discard],
              exerted: m[3].isNotEmpty,
            );
    }
    m = rx(c, r'play (?:a|an) (.+?) with cost up to (\d+) more than the banished character for free');
    if (m != null) {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      return f == null ? null : PlayFreeFrom(f, upToBanishedPlus: int.parse(m[2]));
    }

    // "X to give Y" (CR 6.1.5.1): "put 2 character cards from your discard on the bottom of your
    // deck to give this character Rush this turn".
    m = rx(c, r'(.+?) to give (.+)');
    if (m != null) {
      final save = ctx.save();
      var a = clause(m[1], ctx);
      final b = a == null ? null : _s3Give(m[2], ctx);
      if (a != null && b != null) {
        if ((a is FromDiscard && !a.upTo && !a.all && a.count > 1) || (a is Discard && a.who == Who.you && !a.all && !a.random)) a = Exactly(a);
        return Seq([a, If(const DidIt(), b)]);
      }
      ctx.restore(save);
    }
    return null;
  }

  /// "Give that character Challenger +1 and "When this character is banished in a challenge,
  /// return this card to your hand" this turn", "give this character Rush this turn".
  Effect? _s3Give(String s, _Ctx ctx) {
    final quoted = rx(s, r'(.+?) and "when this character is banished in a challenge, return this card to your hand" this turn');
    if (quoted != null) {
      final words = quoted[1].split(' ');
      for (var i = 1; i < words.length; i++) {
        final save = ctx.save();
        final t = target(words.take(i).join(' '), ctx);
        final kws = t == null ? null : _keywordList(words.skip(i).join(' '));
        if (t != null && kws != null) return Seq([for (final k in kws) GrantKeyword(t, k, Lasting.thisTurn), Mark(MarkKind.returnIfBanishedInChallenge, Lasting.thisTurn, target: t)]);
        ctx.restore(save);
      }
      return null;
    }
    return clause('give $s', ctx);
  }
}
