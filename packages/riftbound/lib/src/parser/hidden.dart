part of 'parser.dart';

/// Rules text for Hidden, Ambush and the cards around them (CR 811, 822): facedown play,
/// extra places to play units, moving enemy units, control changes, replacement effects. Each
/// method is tried before the general parser's own and returns null when it isn't one of these.
extension _HiddenLine on _Line {
  bool get _unit => card.type == CardType.unit;

  /// Whole lines: abilities whose text spans sentences the general parser reads one at a time,
  /// and lines with two trigger conditions (CR 382: one ability per condition).
  List<Ability>? _hLine(String t, String line) {
    // A keyword printed without its brackets.
    if (t == 'Hidden' && card.isMainDeck) return [KeywordAb(line, Kw.hidden)];
    if (t == 'Lose control of that unit and recall it at end of turn.' && card.text.contains('Take control of')) return [Static(line, const ControlEndsAtEot())];
    var m = RegExp(r'^When you play me or I attack, (.+)$').firstMatch(t);
    if (m != null && _unit) {
      final e = _effects(_Line._cap(m[1]!));
      return e == null ? null : [Triggered(line, const When(On.played), e), Triggered(line, const When(On.attack), e)];
    }
    m = RegExp(r"^When I defend or I'm played from \[Hidden\], reveal the top (\d+) cards of your Main Deck\. Deal 1 to (an enemy unit here) for each card with \[Hidden\], then recycle them\.$").firstMatch(t);
    if (m != null && _unit) {
      final target = _target(m[2]!);
      if (target == null) return null;
      final e = [RevealHiddenDamage(int.parse(m[1]!), target)];
      return [Triggered(line, const When(On.defend), e), Triggered(line, const HWhen(On.playedFaceDown), e)];
    }
    m = RegExp(r"^Once each turn, when an enemy unit dies while I'm at a battlefield, (.+)$").firstMatch(t);
    if (m != null && _unit) {
      _eventUnit = true;
      final e = _effects(_Line._cap(m[1]!));
      return e == null ? null : [Triggered(line, const HWhen(On.enemyUnitDies, whileAtBattlefield: true, oncePerTurn: true), e)];
    }
    if (t == 'When you play me, you may choose a friendly unit. Move me to its location and it to my original location.' && _unit) {
      final other = Choose(const Filter(side: Side.friendly, other: true), slot: _slotCounter[0]++, upTo: true);
      return [Triggered(line, const When(On.played), [SwapPlaces(const Me(), other)])];
    }
    m = RegExp(r'^When you play me, play (two|three|\d+) Reflection unit tokens here\. They become copies of me\.$').firstMatch(t);
    if (m != null && _unit) {
      final n = _num(m[1]!);
      return n == null ? null : [Triggered(line, const When(On.played), [CopyMe(n)])];
    }
    // A spell whose second sentence changes the first.
    m = RegExp(r"^Deal (\d+) to (.+)\. If it's attacking, deal (\d+) to it instead\.$").firstMatch(t);
    if (m != null && _isSpell) {
      final target = _target(m[2]!);
      return target == null ? null : [SpellBody(line, [DealOr(int.parse(m[1]!), int.parse(m[3]!), target)])];
    }
    if (_isSpell && t == 'Choose a battlefield. An opponent reveals their hand. You may choose a unit from it. They play that unit to that battlefield, ignoring any and all costs. When they do, [Stun] it.') {
      return [SpellBody(line, [OpponentPlaysUnit(ChooseBf(_slotCounter[0]++))])];
    }
    return null;
  }

  When? _hWhen(String s) {
    final perm = card.isPermanent || card.type == CardType.legend;
    return switch (s) {
      'When you play me from face down' when _unit => const HWhen(On.playedFaceDown),
      'When you play me from face down on your turn' when _unit => const HWhen(On.playedFaceDown, yourTurn: true),
      "When I'm played from [Hidden]" when _unit => const HWhen(On.playedFaceDown),
      'When you play me to a battlefield' when _unit => const HWhen(On.played, toBattlefield: true),
      'When you play a card from [Hidden]' when perm => const When(On.youPlayFromHidden),
      'When an opponent scores' when perm => const When(On.opponentScores),
      _ => null,
    };
  }

  Passive? _hPassive(String t) {
    final legend = card.type == CardType.legend;
    switch (t) {
      case "I can't be chosen by enemy spells and abilities." when _unit:
        return const CantBeChosen();
      case "I can't be chosen by enemy spells and abilities unless I'm in combat." when _unit:
        return const CantBeChosen(unlessInCombat: true);
      case "Your units here with less Might than me can't be chosen by enemy spells and abilities." when _unit:
        return const ShieldsWeakerHere();
      case "I have +1 {M} for each other unit you control here with my name." when _unit:
        return const MightPerNamesake();
      case "Enemy units here with less Might than me don't deal combat damage." when _unit:
        return const SilenceWeakerHere();
      case "I can't be readied." when _unit:
        return const CantBeReadied();
      case 'You may play me to an open battlefield.' when _unit:
        return const PlayTo(PlayPlace.open);
      case 'You may play me to an occupied enemy battlefield.' when _unit:
        return const PlayTo(PlayPlace.occupiedEnemy);
      case "I can be played to a battlefield you're attacking." when _unit:
        return const PlayTo(PlayPlace.attacking);
      case 'I can be played to a battlefield where there are enemy units.' when _unit:
        return const PlayTo(PlayPlace.enemyUnits);
      case 'Friendly units may be played to open battlefields.' when card.isPermanent || legend:
        return const FriendlyToOpen();
      case "Your opponents' [Hidden] cards can't be revealed here." when _unit:
        return const NoRevealHere();
      case 'The next time a friendly unit would die, kill this instead. Recall that unit exhausted.' when card.type == CardType.gear:
        return const SavesFromDeath();
    }
    var m = RegExp(r'^I have \[([A-Za-z]+) (\d+)\] while I.m at a battlefield with exactly one other unit you control\.$').firstMatch(t);
    if (m != null && _unit) {
      final kw = _kwNames[m[1]!.toLowerCase()];
      return kw == null ? null : KwWithOnePartner(kw, int.parse(m[2]!));
    }
    m = RegExp(r"^While there's a stunned enemy unit here, I have \+(\d+) \{M\}\.$").firstMatch(t);
    if (m != null && _unit) return MightWhileStunnedEnemy(int.parse(m[1]!));
    m = RegExp(r'^Your deck can have any number of cards named (.+)\.$').firstMatch(t);
    if (m != null && m[1] == card.name) return const AnyNumberInDeck();
    m = RegExp(r'^You may pay \{(\d+)\} to hide a card with \[Hidden\] instead of \{A\}\.$').firstMatch(t);
    if (m != null && legend) return HideForEnergy(int.parse(m[1]!));
    m = RegExp(r'^You may pay ((?:\{[0-9A-Z]+\})+) as an additional cost to play me\.$').firstMatch(t);
    if (m != null && card.isMainDeck) {
      final cost = _cost(m[1]!);
      return cost == null ? null : ExtraCost(cost: cost);
    }
    if (t == 'You may exhaust your legend as an additional cost to play me.' && card.isMainDeck) return const ExtraCost(exhaustLegend: true);
    m = RegExp(r'^As an additional cost to play me, kill an? ((?:[A-Z][a-z]+, )*[A-Z][a-z]+,? or [A-Z][a-z]+) you control\. You may play me to its battlefield\.$').firstMatch(t);
    if (m != null && _unit) {
      final tags = m[1]!.split(RegExp(r',? or |, '));
      return ExtraCost(killTags: tags, optional: false, toItsBattlefield: true);
    }
    return null;
  }

  Cond? _hCond(String c) => switch (c) {
        'you played this from your hand' when _isSpell => const FromHand(),
        'you paid the additional cost' => card.text.contains('as an additional cost') ? const PaidExtra() : null,
        _ => null,
      };

  Target? _hTarget(String p) {
    switch (p) {
      case 'your units here':
        return const Each(Filter(side: Side.friendly, where: Where.here));
      case 'your other units here':
        return _unit ? const Each(Filter(side: Side.friendly, other: true, where: Where.here)) : null;
      case 'an enemy unit at a different location':
        return Choose(const Filter(side: Side.enemy, where: Where.elsewhere), slot: _slotCounter[0]++);
      case 'a battlefield you control':
        return ChooseBf(_slotCounter[0]++, mine: true);
    }
    final m = RegExp(r'^a non-([A-Z][a-z]+) unit$').firstMatch(p);
    if (m != null) return Choose(Filter(notTag: m[1]), slot: _slotCounter[0]++);
    return null;
  }

  /// A unit phrase that refers to an earlier choice ("another unit you control at a different
  /// location", "an enemy unit at the same battlefield").
  Target? _hRelTarget(String p, int rel) {
    final m = RegExp(r'^(?:a|an|another) (.+?) (at a different location|at the same battlefield)$').firstMatch(p);
    if (m == null) return null;
    var f = _filter(m[1]!, plural: false);
    if (f == null) return null;
    if (p.startsWith('another')) f = Filter(side: f.side, gear: f.gear, other: true, tag: f.tag);
    return ChooseRel(f, _slotCounter[0]++, rel, same: m[2] == 'at the same battlefield');
  }

  List<Effect>? _hSentence(String s) {
    // "You may pay {2} to [Stun] a unit": an optional cost as it resolves.
    var m = RegExp(r'^You may pay ((?:\{[0-9A-Z]+\})+) to (.+)$').firstMatch(s);
    if (m != null) {
      final cost = _cost(m[1]!);
      if (cost == null) return null;
      final body = m[2]!;
      // "ready it": the token just played.
      if (body == 'ready it' && card.text.contains('unit token')) return [MayPay(cost, const [Ready(LastMade())])];
      final e = _sentence(_Line._cap(body));
      return e == null ? null : [MayPay(cost, e)];
    }
    // "Ready me and give me +2 {M} this turn".
    m = RegExp(r'^(.+?) and (give .+)$').firstMatch(s);
    if (m != null && RegExp(r'^(Ready|Exhaust|Buff|Stun) (me|it)$').hasMatch(m[1]!)) {
      final a = _sentence(m[1]!);
      final b = _sentence(_Line._cap(m[2]!));
      return a == null || b == null ? null : [...a, ...b];
    }
    // "Give a unit [Shield 3] and [Tank] this turn".
    m = RegExp(r'^Give (.+?) \[([A-Za-z]+)(?: (\d+))?\] and \[([A-Za-z]+)(?: (\d+))?\] this turn$').firstMatch(s);
    if (m != null) {
      final k1 = _kwNames[m[2]!.toLowerCase()], k2 = _kwNames[m[4]!.toLowerCase()];
      final t = _target(m[1]!);
      if (k1 == null || k2 == null || t == null) return null;
      final again = t is Choose ? Chosen(t.slot) : t;
      return [GiveKw(k1, int.tryParse(m[3] ?? '') ?? 1, t), GiveKw(k2, int.tryParse(m[5] ?? '') ?? 1, again)];
    }
    // "Stun a friendly unit and an enemy unit at the same battlefield".
    m = RegExp(r'^\[?Stun\]? (a friendly unit) and (an enemy unit at the same battlefield)$').firstMatch(s);
    if (m != null) {
      final a = Choose(const Filter(side: Side.friendly, where: Where.battlefield), slot: _slotCounter[0]++);
      final b = _hRelTarget(m[2]!, a.slot);
      return b == null ? null : [Stun(a), Stun(b)];
    }
    // "Choose a battlefield you control and a unit you control at a different location".
    m = RegExp(r'^Choose (.+?) and (.+)$').firstMatch(s);
    if (m != null) {
      final first = _target(m[1]!);
      if (first == null) return null;
      final rel = switch (first) {
        Choose(:final slot) => slot,
        ChooseBf(:final slot) => slot,
        _ => -1,
      };
      if (rel < 0) return null;
      final second = _hRelTarget(m[2]!, rel);
      return second == null ? null : [Pick([first, second])];
    }
    // "Choose a unit." (the next sentence says what happens to it).
    m = RegExp(r'^Choose (a|an) (.+)$').firstMatch(s);
    if (m != null && _isSpell) {
      final t = _target('${m[1]} ${m[2]}');
      return t is Choose ? [Pick([t])] : null;
    }
    if (s == "Move that unit to that battlefield and give it +2 {M} this turn") {
      final c = _slotCounter[0];
      if (c - _first < 2) return null;
      return [MoveTo(Chosen(c - 1), MoveDest.chosenBf, bfSlot: c - 2), GiveMight(2, Chosen(c - 1))];
    }
    if (s == "If at least one of them has [Temporary], move each to the other's location") {
      final c = _slotCounter[0];
      if (c - _first < 2) return null;
      return [SwapPlaces(Chosen(c - 2), Chosen(c - 1), needTemporary: true)];
    }
    m = RegExp(r'^Swap the Might of two units at the same battlefield this turn$').firstMatch(s);
    if (m != null) {
      final a = Choose(const Filter(where: Where.battlefield), slot: _slotCounter[0]++);
      return [SwapMight(a, ChooseRel(const Filter(other: true), _slotCounter[0]++, a.slot, same: true))];
    }
    if (s == 'Double all damage that would be dealt to it this turn') {
      final t = _target('it');
      return t == null ? null : [DoubleDamage(t)];
    }
    // Moves (CR 451).
    m = RegExp(r'^Move (an enemy unit|a unit)( to a location where there.s a unit with the same controller)?$').firstMatch(s);
    if (m != null) {
      final t = _target(m[1]!);
      return t == null ? null : [MoveTo(t, m[2] == null ? MoveDest.anywhere : MoveDest.sameController)];
    }
    m = RegExp(r'^Move (.+?) from (a battlefield|here) to (?:its|their) base$').firstMatch(s);
    if (m != null) {
      final t = _target('${m[1]} ${m[2] == 'here' ? 'here' : 'at a battlefield'}');
      return t == null ? null : [MoveTo(t, MoveDest.base)];
    }
    m = RegExp(r'^Move (.+) to my battlefield$').firstMatch(s);
    if (m != null && _unit) {
      final t = _target(m[1]!);
      return t == null ? null : [MoveTo(t, MoveDest.myLocation)];
    }
    if (s == 'Move me to an occupied enemy battlefield if my Might is greater than the total Might of enemy units there' && _unit) {
      return const [MoveTo(Me(), MoveDest.weakerEnemyBf)];
    }
    m = RegExp(r"^Then, if there's an enemy unit alone at that battlefield, (.+)$").firstMatch(s);
    if (m != null) {
      final c = _slotCounter[0];
      final e = c > _first ? _sentence(_Line._cap(m[1]!)) : null;
      return e == null ? null : [If(AloneAtOrigin(c - 1), e)];
    }
    if (s == 'Then choose another enemy unit at its destination' && card.text.contains('They deal damage equal to their Mights to each other')) return const [];
    if (s == 'They deal damage equal to their Mights to each other' && card.text.contains('Then choose another enemy unit at its destination')) {
      final c = _slotCounter[0];
      return c > _first ? [FightAtDest(Chosen(c - 1))] : null;
    }
    if (s == 'Move any number of friendly units at a battlefield to their base') return [AnyToBase(ChooseBf(_slotCounter[0]++, withFriendlyUnits: true))];
    m = RegExp(r'^Kill any number of units at a battlefield with total Might (\d+) or less$').firstMatch(s);
    if (m != null) return [KillTotal(ChooseBf(_slotCounter[0]++), int.parse(m[1]!))];
    // Control and the like.
    m = RegExp(r'^Its controller draws (\d+)$').firstMatch(s);
    if (m != null && _slotCounter[0] > _first) return [ControllerDraws(_slotCounter[0] - 1, int.parse(m[1]!))];
    m = RegExp(r'^Take control of (.+)$').firstMatch(s);
    if (m != null && _isSpell) {
      final t = _target(m[1]!);
      return t == null ? null : [TakeControl(t, untilEot: card.text.contains('Lose control of that unit and recall it at end of turn.'))];
    }
    m = RegExp(r'^Banish (.+), then its owner plays it to (the same location|any battlefield), ignoring its cost$').firstMatch(s);
    if (m != null) {
      final t = _target(m[1]!);
      return t == null ? null : [Blink(t, anyBattlefield: m[2] == 'any battlefield')];
    }
    if (s == 'Move any number of your units to an open battlefield' && _unit) return const [GatherAtOpen()];
    m = RegExp(r'^Return up to (two|three|\d+) cards with \[Hidden\] from your trash to your hand$').firstMatch(s);
    if (m != null) {
      final n = _num(m[1]!);
      return n == null ? null : [HiddenFromTrash(n)];
    }
    if (s == 'You can hide cards ignoring costs this turn') return const [FreeHide()];
    if (s == 'Play a card with [Hidden] from your hand here, ignoring its cost' && _unit) return const [PlayHiddenHere()];
    if (s == 'Friendly units enter ready this turn') return const [EnterReadyThisTurn()];
    if (s == 'Buffs give an additional +1 {M} to friendly units this turn') return const [BuffBonusThisTurn()];
    m = RegExp(r'^Put an? ([A-Z][A-Za-z]+) unit you own into your hand from your Champion Zone or the board$').firstMatch(s);
    if (m != null) return [FetchToHand(m[1]!)];
    if (s == "Return another friendly gear, unit, or [Hidden] card to its owner's hand" && card.isPermanent) return [ReturnOwn(ChooseOwnCard(_slotCounter[0]++))];
    m = RegExp(r'^Deal damage to (.+) equal to the damage marked on it$').firstMatch(s);
    if (m != null) {
      final t = _target(m[1]!);
      return t == null ? null : [DealMarked(t)];
    }
    return null;
  }
}
