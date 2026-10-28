part of 'parser.dart';

/// Wave 2, slice 2: the one-off wordings of Forgotten Library … Ravenbloom Prefect (and the
/// Brush battlefield token, CR 187.8). Each method returns null when the text isn't one of these.
extension _Ws2Line on _Line {
  bool get _ws2Unit => card.type == CardType.unit;
  bool get _ws2LegendOrPerm => card.type == CardType.legend || card.isPermanent;

  /// Whole lines (after any leading keywords).
  List<Ability>? _ws2Line(String t, String line) {
    // "[Assault 2], [Shield 2]": keywords separated by commas.
    var m = RegExp(r'^, (\[.+)$').firstMatch(t);
    if (m != null) return parse(m[1]!);
    // A keyword printed without its brackets.
    if (t == 'Ganking' && _ws2Unit) return [KeywordAb(line, Kw.ganking)];
    switch (t) {
      case 'I have all {E} abilities of all friendly legends, units, and gear.' when _ws2Unit:
        return [Static(line, const Ws2BorrowExhaustAbilities())];
      case "If I have moved twice this turn, I don't take damage." when _ws2Unit:
        return [Static(line, const Ws2NoDamageMovedTwice())];
      case "Your [Temporary] effects at my battlefield don't trigger." when _ws2Unit:
        return [Static(line, const Ws2NoTemporaryHere())];
      case 'Opponents must pay {A} for each unit beyond the first to move multiple units to my battlefield at the same time.' when _ws2Unit:
        return [Static(line, const Ws2MoveTax())];
      case 'If a player would score 1 point from conquering or holding during their first or second turn, they draw 1 instead.' when card.isPermanent:
        return [Static(line, const Ws2EarlyScoreDraws())];
      case 'As you play me, choose Bird, Cat, Dog, or Poro. I gain that tag.' when _ws2Unit:
        return [Static(line, const Ws2ChooseTag(['Bird', 'Cat', 'Dog', 'Poro']))];
      // The Brush battlefield token (CR 187.8).
      case 'Bird, Cat, Dog, Poro, and Ivern units here have +1 {M}.' when _isBattlefield:
        return [Static(line, const GAnthem(Filter(tags: ['Bird', 'Cat', 'Dog', 'Poro', 'Ivern'], where: Where.here), might: 1))];
      case 'When you score here, you may replace this with the battlefield it replaced.' when _isBattlefield:
        const e = [May([Ws2RestoreBf()])];
        return [Triggered(line, const When(On.conquerHere), e), Triggered(line, const When(On.holdHere), e)];
      case 'When an opponent plays a gear, you may banish me to banish it.' when _ws2Unit:
        return [Triggered(line, const GenWhen(GEv.played, filter: Filter(side: Side.enemy, gear: true), by: Side.enemy), const [Ws2BanishMeToBanish()])];
      case 'When you conquer or hold, you may exhaust me to replace that battlefield with a Brush battlefield token.' when card.type == CardType.legend:
        return [Triggered(line, const GenWhen(GEv.conquerOrHold), const [Ws2ReplaceWithBrush()])];
      case 'When you conquer or hold, you may discard 1 and exhaust me to play a ready Reflection unit token there. It becomes a copy of another unit there. Give it [Temporary].' when card.type == CardType.legend:
        return [Triggered(line, const GenWhen(GEv.conquerOrHold), const [Ws2Deceiver()])];
      case 'When you play a spell, if you spent {4} or more, you may banish it. Then, if there are four spells banished with me, put each in its trash, channel 4 runes, and draw 1.' when card.type == CardType.legend:
        return [Triggered(line, const GenWhen(GEv.spellPlayed), const [TrigIf(SpentOnThisSpell(4), [Ws2Jhin()])])];
      case 'While you control this battlefield, when you play a spell, if you spent {4} or more, [Predict].' when _isBattlefield:
        return [Triggered(line, const GenWhen(GEv.spellPlayed), const [TrigIf(Ws2All([Ws2ControlsThisBf(), SpentOnThisSpell(4)]), [Predict(1)])])];
      case 'When I move, draw 1, then discard 1. Then, do the following based on the discarded card\'s type: • Spell - Draw 1. • Gear - Ready up to 2 runes. • Unit - Give me +3 {M} this turn.' when _ws2Unit:
        return [Triggered(line, const When(On.move), const [Ws2Hwei()])];
      case 'Starting with the next player, each other player chooses a unit you don\'t control that hasn\'t been chosen for this spell. Kill those units.' when _isSpell:
        return [SpellBody(line, const [Ws2KingsEdict()])];
      case 'Each other player chooses Cards or Runes. For each player that chooses Cards, you and that player each draw 1. For each player that chooses Runes, you and that player each channel 1 rune exhausted.' when _isSpell:
        return [SpellBody(line, const [Ws2PartyFavors()])];
      case 'Gain control of a spell. You may make new choices for it.' when _isSpell:
        return [SpellBody(line, [Ws2StealSpell(_slotCounter[0]++)])];
      case 'Choose a unit. Play a ready Reflection unit token to your base. It becomes a copy of that unit. Give it [Temporary].' when _isSpell:
        final of = Choose(const Filter(), slot: _slotCounter[0]++);
        return [SpellBody(line, [ChooseOnly([of]), Ws2Reflection(Chosen(of.slot))])];
      case '[Legion] - Kill it now instead.' when _isSpell && _slotCounter[0] > 0:
        return [SpellBody(line, [Ws2LegionKillNow(Chosen(_slotCounter[0] - 1))])];
      case '{E}: [Reaction] - Pay any amount of {A} to [Add] that much Energy.' when card.type == CardType.gear:
        return [Activated(line, const Cost(exhaust: true), const [Ws2PowerToEnergy()], timing: Timing.reaction)];
      case '{E}: [Reaction] - [Add] {2}. Spend this Energy only to play spells.' when _ws2LegendOrPerm:
        return [Activated(line, const Cost(exhaust: true), const [Ws2RestrictedAdd(energy: 2)], timing: Timing.reaction)];
      case '{E}: [Reaction] - [Add] {A}. Use only to play gear or use gear abilities.' when _ws2LegendOrPerm:
        return [Activated(line, const Cost(exhaust: true), const [Ws2RestrictedAdd(anyPower: 1, gear: true)], timing: Timing.reaction)];
      case '[Action][>] Exhaust a unit you control, {E}: Move a different unit you control to the location of the unit you exhausted to pay for this ability.' when card.type == CardType.gear:
        final u = Choose(const Filter(side: Side.friendly), slot: _slotCounter[0]++);
        return [Activated(line, const Cost(exhaust: true, extra: [Ws2ExhaustUnitCost()]), [Ws2MoveToPaidLoc(u)], timing: Timing.action)];
    }
    // Gutter Palace (the Bird token has Deflect, CR 187.7).
    if (t == 'Discard 1, {E}: Play a 1 {M} Bird unit token with [Deflect].' && card.isPermanent) {
      return [Activated(line, const Cost(exhaust: true, extra: [DiscardCost(1)]), const [PlayToken('Bird', 1)])];
    }
    // Jayce, Brilliant Inventor: one ability, two trigger conditions (CR 382).
    m = RegExp(r'^When you play me or the first time you play a non-token gear each turn, (.+)$').firstMatch(t);
    if (m != null && _ws2Unit) {
      final e = _effects(_Line._cap(m[1]!));
      if (e == null) return null;
      return [Triggered(line, const When(On.played), e), Triggered(line, const GenWhen(GEv.played, filter: Filter(side: Side.friendly, gear: true, token: false)), [TrigIf(const Ws2FirstGear(), e)])];
    }
    // Forgotten Relic.
    m = RegExp(r"^When you play this or at the start of your Beginning Phase, \[Burn (\d+)\]\. When you burn a unit this way, do this: Give a friendly unit \+\{M\} equal to the burned card's Might this turn\.$").firstMatch(t);
    if (m != null && card.type == CardType.gear) {
      return [Triggered(line, const GenWhen(GEv.played, self: true, alsoOn: [On.startOfTurn]), [Ws2BurnBoost(int.parse(m[1]!))])];
    }
    return null;
  }

  When? _ws2When(String s) {
    final perm = _ws2LegendOrPerm;
    switch (s) {
      case 'When you play me or when I score' when _ws2Unit:
        // Scoring is conquering or holding (CR 470.3, 471).
        return const GenWhen(GEv.played, self: true, alsoOn: [On.conquer, On.hold]);
      case 'When you hide a card' when perm:
        return const GenWhen(GEv.ws2Hid);
      case 'When you play a card from face down' when perm:
        return const HWhen(On.youPlayFromHidden);
      case 'When an enemy unit here dies' || 'when an enemy unit here dies' when _ws2Unit:
        return const GenWhen(GEv.dies, filter: Filter(side: Side.enemy, where: Where.here), by: Side.any);
    }
    return null;
  }

  List<Effect>? _ws2Sentence(String s) {
    var m = RegExp(r'^It gains \[(Shield|Assault|Tank)(?: (\d+))?\] this combat$').firstMatch(s);
    if (m != null) {
      final t = _target('it');
      final kw = _kwNames[m[1]!.toLowerCase()]!;
      return t == null ? null : [Ws2GiveKwCombat(kw, int.tryParse(m[2] ?? '') ?? 1, t)];
    }
    if (s == 'Give a friendly unit my keywords and +{M} equal to my Might this turn' && _ws2Unit) {
      return [Ws2GiveMyKeywords(Choose(const Filter(side: Side.friendly), slot: _slotCounter[0]++))];
    }
    if (s == 'You win the game' || s == 'you win the game') return const [Ws2WinGame()];
    m = RegExp(r'^(You may r|R)eturn your Chosen Champion from your trash to your Champion Zone if it is empty$').firstMatch(s);
    if (m != null) return [Ws2ReturnChampion(may: m[1] != null)];
    m = RegExp(r'^(You may p|P)lay a unit from hand to a battlefield you control, reducing its cost by \{(\d+)\}$').firstMatch(s);
    if (m != null) return [Ws2PlayUnitReduced(int.parse(m[2]!), may: m[1] != null)];
    // "Play a {1} {M} Tentacle unit token from Bilgewater": the Tentacle token (CR 187.10).
    if (s == 'Play a {1} {M} Tentacle unit token from Bilgewater') return const [PlayToken('Tentacle', 1)];
    m = RegExp(r'^(.+) if your units have all of the following tags among them - (.+)$').firstMatch(s);
    if (m != null) {
      final tags = m[2]!.split(RegExp(r',? and |, ')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
      final e = _sentence(_Line._cap(m[1]!));
      return e == null || tags.isEmpty ? null : [If(Ws2TagsAmong(tags), e)];
    }
    return null;
  }

  Cond? _ws2Cond(String c) {
    if (c == 'you control a facedown card' || c == 'you control a facedown card at a battlefield') return const Ws2ControlsFacedown();
    final m = RegExp(r'^you have exactly (\d+) cards in hand and exactly (\d+) units at battlefields$').firstMatch(c);
    if (m != null) return Ws2ExactHandUnits(int.parse(m[1]!), int.parse(m[2]!));
    return null;
  }
}
