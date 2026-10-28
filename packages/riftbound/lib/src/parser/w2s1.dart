part of 'parser.dart';

/// Wave 2, slice 1: rules text the families don't read (Acceleration Gate to Fiora, Peerless).
/// Whole lines, tried before the families' own; each builds on their effects where it can.
extension _S1Line on _Line {
  bool get _s1Unit => card.type == CardType.unit;
  bool get _s1Perm => card.isPermanent || card.type == CardType.legend;

  /// A slot for one of this slice's choices.
  int _s1Slot([int n = 1]) {
    final s = _slotCounter[0];
    _slotCounter[0] += n;
    return s;
  }

  List<Ability>? _s1Line(String t, String line) {
    RegExpMatch? m;
    RegExpMatch? mt(String re) => m = RegExp('^$re\$').firstMatch(t);

    // Spells.
    if (_isSpell) {
      if (mt(r'Ready up to (\w+) units, gear, and/or runes\.') != null) {
        final n = _num(m![1]!);
        return n == null ? null : [SpellBody(line, [S1ReadyPicked(S1Pick(S1PickKind.readyables, _s1Slot(n), n: n))])];
      }
      if (t == 'Give a unit at a battlefield or a gear [Temporary].') {
        final s = _s1Slot();
        return [SpellBody(line, [S1GiveKw(Kw.temporary, 1, Chosen(s), pick: S1Pick(S1PickKind.unitAtBfOrGear, s))])];
      }
      // "Give a unit [Assault 2]." — a keyword with a value and no duration (CR 801.3.a.3); the
      // general grammar reads the ones without a value.
      if (mt(r'Give (.+?) \[(Assault|Shield|Deflect) (\d+)\]\.') != null) {
        final kw = _kwNames[m![2]!.toLowerCase()]!;
        final target = _target(m![1]!);
        return target == null ? null : [SpellBody(line, [S1GiveKw(kw, int.parse(m![3]!), target)])];
      }
      if (mt(r'Move a unit you control to a battlefield you control\. Then, choose an opponent\. They move a unit they control to the same battlefield\.') != null) {
        final first = _effects('Move a unit you control to a battlefield you control.');
        if (first == null || first.length != 1 || first.first is! Move) return null;
        return [SpellBody(line, [...first, S1OpponentFollows((first.first as Move).destSlot)])];
      }
      if (mt(r"Channel (\d+) runes exhausted\. If you couldn't channel (\d+) runes this way, draw (\d+)\.") != null && m![1] == m![2]) {
        return [SpellBody(line, [S1ChannelElseDraw(int.parse(m![1]!), int.parse(m![3]!))])];
      }
      if (t == 'Choose a friendly unit. This turn, increase its Might to the Might of another friendly unit.') {
        final a = _s1Slot(), b = _s1Slot();
        return [SpellBody(line, [S1RaiseMight(S1Pick(S1PickKind.friendlyUnit, a), S1Pick(S1PickKind.friendlyUnit, b, other: a))])];
      }
      if (mt(r'Choose a battlefield and an enemy unit there\. Deal (\d+) to that unit and (\d+) to each other enemy unit there\.') != null) {
        return [SpellBody(line, [S1StrikeThere(S1Pick(S1PickKind.enemyUnitAtBfWithBf, _s1Slot(2), n: 2), int.parse(m![1]!), int.parse(m![2]!))])];
      }
      if (mt(r'Deal (\d+) to a unit\. Its controller may play this spell again for \{A\}\. If they do, this deals 1 additional Bonus Damage for each time this spell has dealt damage this turn\.') != null) {
        return [SpellBody(line, [S1Grenade(S1Pick(S1PickKind.anyUnit, _s1Slot()), int.parse(m![1]!))])];
      }
      if (mt(r'Kill a friendly unit to give \+\{M\} equal to its Might to another friendly unit this turn\. Draw (\d+)\.') != null) {
        final a = _s1Slot(), b = _s1Slot();
        return [SpellBody(line, [S1KillToGive(S1Pick(S1PickKind.friendlyUnit, a), S1Pick(S1PickKind.friendlyUnit, b, other: a)), Draw(int.parse(m![1]!))])];
      }
      if (mt(r"Choose a friendly unit that's in combat with an enemy Fury unit or that's being chosen by an enemy Fury spell\. Give it \+(\d+) \{M\} this turn\.") != null) {
        return [SpellBody(line, [S1GiveMightPicked(S1Pick(S1PickKind.furyThreatened, _s1Slot()), int.parse(m![1]!))])];
      }
      if (mt(r'Each player chooses (\d+) units, (\d+) gear, (\d+) runes, and (\d+) cards in their hands\. Recycle the rest\.') != null) {
        final n = int.parse(m![1]!);
        if (m![2] != m![1] || m![3] != m![1] || m![4] != m![1]) return null;
        return [SpellBody(line, [S1Judgment(n)])];
      }
      if (mt(r'This turn, double a unit.s Might and give it "(.+)"') != null) {
        final granted = _s1GrantedActivated(m![1]!);
        return granted == null ? null : [SpellBody(line, [S1DoubleAndGrant(S1Pick(S1PickKind.anyUnit, _s1Slot()), granted)])];
      }
      return null;
    }

    // Triggered abilities.
    if (card.type == CardType.gear && mt(r'When a friendly unit dies, you may exhaust me to draw (\d+), then put a card from your hand on the top or bottom of your Main Deck\.') != null) {
      final on = _when('When a friendly unit dies');
      return on == null ? null : [Triggered(line, on, [PayTo([Draw(int.parse(m![1]!)), const S1HandToDeck()], exhaustMe: true)])];
    }
    if (_s1Unit && t == 'When you play me, choose an opponent. They reveal their hand. Choose a card revealed this way and banish it. When they hold, return it to their hand.') {
      return [Triggered(line, const When(On.played), const [S1BanishUntilHold()])];
    }
    if (_s1Perm && mt(r'When you play a card from face down, (.+)') != null) {
      final e = _effects(_Line._cap(m![1]!));
      return e == null ? null : [Triggered(line, const When(On.youPlayFromHidden), e)];
    }
    if (_s1Perm && mt(r'At the start of your Main Phase, you may kill (\w+) other friendly units and/or gear to score (\d+) points?\.') != null) {
      final n = _num(m![1]!);
      final on = _when('At the start of your Main Phase');
      return n == null || on == null ? null : [Triggered(line, on, [S1KillManyTo(n, [GainPoints(int.parse(m![2]!))])])];
    }
    if (_s1Unit && t == 'When you play me, you and each opponent may play a Gold gear token exhausted. For each opponent who did, you play a Gold gear token exhausted.') {
      return [Triggered(line, const When(On.played), const [S1GoldForAll()])];
    }
    if (_s1Perm && t == 'At the end of your turn, reveal cards from the top of your Main Deck until you reveal a unit. Play it, ignoring its cost, and recycle the rest.') {
      return [Triggered(line, const When(On.endOfTurn), const [S1RevealPlayUnit()])];
    }
    if (_s1Unit && mt(r"When a showdown begins here, you may pay \{(\d+)\}\. If you do, \[Predict\], then reveal the top card of your Main Deck\. If it's a spell, draw it\.") != null) {
      return [Triggered(line, const S1When(S1Ev.showdownHere, On.general), [PayTo(const [Predict(1), S1RevealDrawSpell()], energy: int.parse(m![1]!))])];
    }
    if (_s1Unit && mt(r'The first time I win a combat each turn, (.+)') != null) {
      final e = _effects(_Line._cap(m![1]!));
      return e == null ? null : [Triggered(line, const S1When(S1Ev.firstEachTurn, On.winCombat), e)];
    }
    if (_s1Unit && mt(r'When I die in combat, choose an opponent\. They score (\d+) points?\.') != null) {
      return [Triggered(line, const S1When(S1Ev.dieInCombat, On.die), [S1OpponentScores(int.parse(m![1]!))])];
    }
    // "When …, you may pay {cost}. If you do, …" (CR 355.10.c.1: a cost within instructions).
    if (mt(r'When ([^,]+), you may pay ((?:\{[0-9A-Z]\})+)\. If you do, (.+)') != null) {
      final on = _when(m![1]!.startsWith('When') ? m![1]! : 'When ${m![1]!}');
      final cost = _cost(m![2]!);
      final e = _effects(_Line._cap(m![3]!));
      if (on == null || cost == null || e == null || cost.exhaust || cost.extra.isNotEmpty) return null;
      return [Triggered(line, on, [PayTo(e, energy: cost.energy, power: cost.power)])];
    }
    if (_isBattlefield && mt(r'At the start of your Beginning Phase, you may kill a unit you control here to draw (\d+)\.') != null) {
      return [
        Triggered(line, const S1When(S1Ev.bfStartOfTurn, On.general), [
          PayTo([Draw(int.parse(m![1]!))], parts: const [CostAction(CostKind.killOne, filter: Filter(side: Side.friendly, where: Where.here))]),
        ]),
      ];
    }
    if (_s1Unit && t == '[Deathknell] - Recycle me to ready your runes.') {
      return [Triggered(line, const When(On.die), const [S1RecycleMeTo([S1ReadyRunes()])])];
    }
    if (_s1Unit && mt(r'When you play me, choose up to one enemy unit at each location\. Deal (\d+) to them\.') != null) {
      // One slot per location: both bases and up to six battlefields.
      return [Triggered(line, const When(On.played), [S1DealPerLocation(S1Pick(S1PickKind.enemyPerLocation, _s1Slot(8), n: 8), int.parse(m![1]!))])];
    }
    if (_isBattlefield && mt(r"When you conquer here, you may pay \{(\d+)\} and return a unit you control here to its owner's hand\. If you do, play a (\d+) \{M\} (Sand Soldier|Recruit|Sprite|Mech|Bird|Tentacle) unit token here\.") != null) {
      const mights = {'Recruit': 1, 'Sprite': 3, 'Sand Soldier': 2, 'Mech': 3, 'Bird': 1, 'Tentacle': 1};
      if (mights[m![3]!] != int.parse(m![2]!)) return null;
      return [Triggered(line, const When(On.conquerHere), [S1PayReturnForToken(int.parse(m![1]!), m![3]!)])];
    }
    if (card.type == CardType.gear && mt(r'When you play this, banish your hand and trash, then \[Burn (\d+)\]\.') != null) {
      return [Triggered(line, const When(On.played), [const S1BanishHandAndTrash(), Burn(int.parse(m![1]!))])];
    }
    if (_s1Unit && t == 'When you play me, name a spell.') return [Triggered(line, const When(On.played), const [S1NameSpell()])];
    if (_s1Unit && t == 'When I attack or defend one on one, double my Might this combat.') {
      return [Triggered(line, const When(On.attackOrDefend), const [TrigIf(S1OneOnOne(), [S1DoubleThisCombat()])])];
    }

    // Activated abilities.
    if (card.type == CardType.gear && t == '{E}: [Reaction] - Pay any amount of Energy to [Add] that much {A}.') {
      return [Activated(line, const Cost(exhaust: true), const [S1EnergyToPower()], timing: Timing.reaction)];
    }
    if (card.type == CardType.legend && mt(r'\[Reaction\]\[>\] \{E\}: \[Add\] \{(\d+)\}\. Spend this Energy only during showdowns\.') != null) {
      return [Activated(line, const Cost(exhaust: true), [S1ShowdownEnergy(int.parse(m![1]!))], timing: Timing.reaction)];
    }
    if (card.type == CardType.legend && mt(r"\{E\}: \[Reaction\] - Draw (\d+)\. Use only if you've chosen enemy units and/or gear twice this turn with spells or unit abilities\.") != null) {
      return [Activated(line, const Cost(exhaust: true), [UseOnly(const S1ChoseEnemyTwice(), [Draw(int.parse(m![1]!))])], timing: Timing.reaction)];
    }

    // Passives.
    if (_isBattlefield && mt(r'If a unit here would die during combat, its controller may pay ((?:\{A\})+) to heal it, exhaust it, and recall it instead\.') != null) {
      return [Static(line, S1CombatSave('{A}'.allMatches(m![1]!).length))];
    }
    if (_isBattlefield && t == 'You may hide an additional card here.') return [Static(line, const S1ExtraHide())];
    if (_isBattlefield && t == 'Units can move here from anywhere.') return [Static(line, const S1MoveHereFromAnywhere())];
    if (_s1Unit && t == "As you play me, add the Baron Pit battlefield token to the board if it's not there already. If you do, I enter there.") {
      return [Static(line, const S1BaronPit())];
    }
    if (card.type == CardType.gear) {
      if (t == 'Skip your Draw Phase.') return [Static(line, const S1SkipDraw())];
      if (t == 'You may play cards from your trash.') return [Static(line, const S1PlayFromTrash())];
      if (t == 'If a card would go to your trash from anywhere other than your Main Deck, banish it instead.') return [Static(line, const S1TrashIsBanish())];
    }
    if (_s1Unit && t == "While I'm at a battlefield, opponents can't play spells with that name.") return [Static(line, const S1NamedSpellBan())];
    return null;
  }

  /// A quoted activated ability given to a unit ("{A}{A}: Ready me."), read as the unit's own.
  Activated? _s1GrantedActivated(String text) {
    final asUnit = RCard(name: card.name, type: CardType.unit, domains: card.domains, might: 0, text: text);
    final a = _eqParseLine(asUnit, [0], text.endsWith('.') ? text : '$text.');
    if (a == null || a.length != 1 || a.first is! Activated) return null;
    return a.first as Activated;
  }

  /// Conditions the families don't read.
  Cond? _s1Cond(String c) {
    if (_s1Unit && c == "I haven't been dealt damage this turn") return const SelfCond(SelfKind.notDamagedThisTurn);
    return null;
  }
}
