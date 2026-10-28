part of 'parser.dart';

/// Wave 2, slice 3 (Rek'Sai, Swarm Queen to Zilean, Time Mage): whole lines and sentences the
/// families don't read, mostly one card each (ir_w2s3.dart). Tried before the other grammars;
/// each method returns null when the text isn't one of these.
extension _W2s3Line on _Line {
  bool get _w3Unit => card.type == CardType.unit;
  bool get _w3Gear => card.type == CardType.gear;
  bool get _w3Legend => card.type == CardType.legend;

  int _w3Slot() => _slotCounter[0]++;

  /// Whole lines.
  List<Ability>? _w3Line(String t, String line) {
    // Reveal the top cards and play one (Rek'Sai).
    var m = RegExp(r'^When I attack, you may reveal the top (\d+) cards of your Main Deck\. You may play one\. Then recycle the rest\. If the played card is a unit, you may play it here\.$').firstMatch(t);
    if (m != null && _w3Unit) return [Triggered(line, const When(On.attack), [W3RevealPlay(int.parse(m[1]!), may: true, hereIfUnit: true)])];
    m = RegExp(r'^When you conquer, you may exhaust me to reveal the top (\d+) cards of your Main Deck\. You may play one\. Then recycle the rest\.$').firstMatch(t);
    if (m != null && (_w3Legend || card.isPermanent)) {
      return [
        Triggered(line, const When(On.youConquer), [
          PayTo([W3RevealPlay(int.parse(m[1]!))], exhaustMe: true),
        ]),
      ];
    }
    m = RegExp(r'^While your score is within (\d+) points of the Victory Score, your Gold \[ADD\] an additional \{(\d+)\}\.$', caseSensitive: false).firstMatch(t);
    if (m != null && (_w3Legend || card.isPermanent)) return [Static(line, W3GoldBonus(int.parse(m[1]!), int.parse(m[2]!)))];
    // Restricted Energy (Renekton).
    m = RegExp(r'^\[Reaction\]\[>\] ([^:]+): \[Add\] \{(\d+)\}\. Spend this Energy only to play units or activated abilities of units\.$').firstMatch(t);
    if (m != null) {
      final cost = _cost(m[1]!);
      if (cost == null) return null;
      return [Activated(line, cost, [W3UnitAdd(int.parse(m[2]!))], timing: Timing.reaction)];
    }
    if (t == "Choose a friendly unit and a spell. Counter that spell and give that unit +{M} equal to that spell's Energy cost this turn." && _isSpell) {
      final u = _w3Slot();
      final s = _w3Slot();
      return [SpellBody(line, [W3CounterGive(Choose(const Filter(side: Side.friendly), slot: u), ChooseSpell(s))])];
    }
    m = RegExp(r"^When a unit here is returned to a player's hand, that player may pay \{(\d+)\} to channel (\d+) runes? exhausted\.$").firstMatch(t);
    if (m != null && _isBattlefield) {
      return [
        Triggered(line, const W3When(W3On.returnedHere), [
          PayTo([Channel(int.parse(m[2]!), exhausted: true)], energy: int.parse(m[1]!)),
        ]),
      ];
    }
    m = RegExp(r"^While I'm at a battlefield, players only channel (\d+) runes? at the start of their Channel Phase\.$").firstMatch(t);
    if (m != null && _w3Unit) return [Static(line, W3ChannelOnly(int.parse(m[1]!)))];
    m = RegExp(r'^When this is played, discarded, or killed, draw (\d+)\.$').firstMatch(t);
    if (m != null && card.isPermanent) {
      final e = [Draw(int.parse(m[1]!))];
      return [Triggered(line, const When(On.played), e), Triggered(line, const GenWhen(GEv.discarded, self: true), e), Triggered(line, const When(On.die), e)];
    }
    if (t == 'If you play me to a battlefield, I enter ready.' && _w3Unit) return [Static(line, const W3ReadyAtBattlefield())];
    m = RegExp(r'^The first time a friendly unit dies during your Beginning Phase each turn, each opponent must kill one of their units\.$').firstMatch(t);
    if (m != null && card.isPermanent) return [Triggered(line, const W3When(W3On.friendlyDiesInBeginning), const [W3OppKillsOne()])];
    m = RegExp(r"^While I'm at a battlefield, ready (\d+) friendly runes at the end of your turn\.$").firstMatch(t);
    if (m != null && _w3Unit) {
      return [
        Triggered(line, const When(On.endOfTurn), [
          TrigIf(const SelfCond(SelfKind.atBattlefield), [ReadyRunes(int.parse(m[1]!))]),
        ]),
      ];
    }
    if (t == 'If another unit you control here would die, if it has less Might than me, instead heal it, exhaust it, and recall it.' && _w3Unit) return [Static(line, const W3SorakaSave())];
    if (t == "[Deathknell][>] Repeat this gear's play effect." && _w3Gear) {
      // The play effect is this card's "When you play this, …" line.
      for (final other in card.text.split('\n')) {
        final p = RegExp(r'^When you play this, (.+)$').firstMatch(other.trim());
        if (p == null) continue;
        final e = _effects(_Line._cap(p[1]!));
        return e == null ? null : [Triggered(line, const When(On.die), e)];
      }
      return null;
    }
    m = RegExp(r'^\[Repeat\] - Discard (\d+)$').firstMatch(t);
    if (m != null && _isSpell) return [RepeatCost(line, Cost(extra: [DiscardCost(int.parse(m[1]!))]))];
    if (t == 'The first time a player plays a non-token unit here each turn, they may move another unit they control here to its base.' && _isBattlefield) {
      return [Triggered(line, const W3When(W3On.firstUnitPlayedHere), const [W3MoveOtherHome()])];
    }
    if (t == 'When a friendly unit moves from my location, I may be moved with it.' && _w3Unit) return [Triggered(line, const W3When(W3On.friendMovesFromMe), const [W3Follow()])];
    m = RegExp(r'^When you conquer here with one or more \[Mighty\] units, you may pay \{(\d+)\} to draw (\d+)\.$').firstMatch(t);
    if (m != null && _isBattlefield) {
      return [
        Triggered(line, const When(On.conquerHere), [
          TrigIf(const W3MightyHere(), [PayTo([Draw(int.parse(m[2]!))], energy: int.parse(m[1]!))]),
        ]),
      ];
    }
    m = RegExp(r"^When I conquer, if you've played a non-token unit, a non-token gear, and a spell this turn, you score (\d+) points?\.$").firstMatch(t);
    if (m != null && _w3Unit) {
      return [
        Triggered(line, const When(On.conquer), [
          TrigIf(const W3PlayedUnitGearSpell(), [GainPoints(int.parse(m[1]!))]),
        ]),
      ];
    }
    if (t == 'If a combat where you are the attacker ends in a tie, recall ALL units instead.' && card.isPermanent) return [Static(line, const W3SolariTie())];
    m = RegExp(r"^While I'm in a showdown, your spells have \[Repeat\] ((?:\{[0-9A-Z]+\})+)\.$").firstMatch(t);
    if (m != null && _w3Unit) {
      final cost = _cost(m[1]!);
      return cost == null ? null : [Static(line, W3GrantRepeat(cost))];
    }
    m = RegExp(r'^When a player chooses a friendly unit here with a spell for the first time each turn, they draw (\d+)\.$').firstMatch(t);
    if (m != null && _isBattlefield) return [Triggered(line, const W3When(W3On.firstChosenHereBySpell), [Draw(int.parse(m[1]!))])];
    if (t == 'As you play this, name a tag.' && card.isPermanent) return [Static(line, const W3NameTag())];
    if (t == 'When I attack, reveal the top rune of your rune deck, then recycle it. Do one of the following based on its domain: • {R} - Deal 2 to an enemy unit here and 1 to all other enemy units here. • {B} - Draw 1. • {Y} - Stun an enemy unit.' && _w3Unit) {
      return [Triggered(line, const When(On.attack), const [W3RuneGamble()])];
    }
    m = RegExp(r'^([^:]+): Choose a friendly unit\. The next time it dies this turn, you may pay \{([A-Z])\} to recall it exhausted instead\.$').firstMatch(t);
    if (m != null && card.isPermanent) {
      final cost = _cost(m[1]!) ?? (m[1] == 'Discard 1, {E}' ? const Cost(exhaust: true, extra: [DiscardCost(1)]) : null);
      final d = Domain.byName(m[2]!);
      if (cost == null || d == null) return null;
      return [Activated(line, cost, [W3SaveForPay(Choose(const Filter(side: Side.friendly), slot: _w3Slot()), d)])];
    }
    if (t == "When an opponent plays a unit while I'm at a battlefield, [Stun] it. They can't move it this turn." && _w3Unit) {
      return [
        Triggered(line, const GenWhen(GEv.played, filter: Filter(), by: Side.enemy, extra: ['meAtBf']), const [
          Stun(EventUnit()),
          Delay(DelayKind.cantMove, target: EventUnit()),
        ]),
      ];
    }
    if (t == 'If you would reveal cards from a deck, look at the top card first. You may recycle it. Then reveal those cards.' && _w3Unit) return [Static(line, const W3PeekBeforeReveal())];
    if (t == 'Starting with the next player, each player may return a unit to its owner\'s hand.' && _isSpell) return [SpellBody(line, const [W3Whirlwind()])];
    if (t == "Once each turn, if you would play a token unit while I'm at a battlefield, you may play that token and an additional copy of it instead." && _w3Unit) {
      return [Static(line, const W3TokenCopy())];
    }
    return null;
  }

  /// One sentence of instructions.
  List<Effect>? _w3Sentence(String s) {
    // "[Stun] an enemy unit attacking here" (Shadow).
    if (s == '[Stun] an enemy unit attacking here' && _w3Unit) return [Stun(Choose(const Filter(side: Side.enemy, attacking: true, where: Where.here), slot: _w3Slot()))];
    var m = RegExp(r'^Deal (\d+) to it unless its controller has you draw (\d+)$').firstMatch(s);
    if (m != null) {
      final it = _target('it');
      return it == null ? null : [W3DealUnless(int.parse(m[1]!), it, int.parse(m[2]!))];
    }
    if (s == 'Deal damage equal to its Might to all enemy units at a battlefield, then move your unit there' && _isSpell && _slotCounter[0] > _first) {
      final unit = _slotCounter[0] - 1;
      return [W3Stormbringer(unit, _w3Slot())];
    }
    m = RegExp(r'^The attacker and defender each \[Add\] \{(\d+)\}$').firstMatch(s);
    if (m != null && _isBattlefield) return [W3AddCombatants(int.parse(m[1]!))];
    m = RegExp(r'^Move any number of enemy units with the same controller and a total Might of (\d+) or less to a single location$').firstMatch(s);
    if (m != null && _isSpell) {
      const max = 12;
      final slot = _slotCounter[0];
      _slotCounter[0] += max + 1;
      return [W3MoveMany(ChooseMany(const Filter(side: Side.enemy), slot: slot, max: max, totalMightMax: int.parse(m[1]!)), slot + max)];
    }
    m = RegExp(r'^Give a unit with the named tag ([+-])(\d+) \{M\} this turn$').firstMatch(s);
    if (m != null && card.text.contains('name a tag')) return [W3NamedTagMight(_w3Slot(), int.parse(m[2]!) * (m[1] == '-' ? -1 : 1))];
    m = RegExp(r'^Give one of your other units here \+(\d+) \{M\} and \[Tank\] this turn$').firstMatch(s);
    if (m != null && _w3Unit) {
      return [
        GiveMany(Choose(const Filter(side: Side.friendly, other: true, where: Where.here), slot: _w3Slot()), might: int.parse(m[1]!), kws: const [(Kw.tank, 1)]),
      ];
    }
    if (s == 'Play a 0 {M} Shadow Clone unit token to your base') return const [PowerToken('Shadow Clone', 1)];
    if (s == "Move me and a Shadow Clone you control to each other's locations" && _w3Unit) return [W3SwapClone(_w3Slot())];
    return null;
  }
}
