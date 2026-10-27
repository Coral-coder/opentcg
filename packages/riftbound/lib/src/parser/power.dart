part of 'parser.dart';

// Reading Empower (CR 827–828), XP (CR 728), Hunt (CR 823), Level (CR 824), buffs (CR 427, 701)
// and Flow (CR 829) text. Each function is reached from one hook in parser.dart and returns null
// when the text isn't one of these forms, so the core parser carries on as before.

/// "It" in an "instead" line of a spell means the unit chosen on the line before (Combat
/// Experience); set while such a line is parsed.
int? _powerItSlot;

extension _PowerLine on _Line {
  bool get _isLegend => card.type == CardType.legend;
  bool get _isGear => card.type == CardType.gear;
  bool get _isUnit => card.type == CardType.unit;

  /// The slot "it" refers to on this line, or null.
  int? get _itSlot => _powerItSlot ?? (_slotCounter[0] > _first ? _slotCounter[0] - 1 : null);

  static String _trimDots(String s) {
    var t = s.trim();
    while (t.endsWith('..')) {
      t = t.substring(0, t.length - 1);
    }
    return t;
  }

  /// Whole lines: [Hunt], [Flow], [Empower], [Empowered][>], [Level N][>], "While …" and the
  /// statics of these cards. Null if [t] isn't one of them.
  List<Ability>? _powerLine(String t0, String line) {
    final t = _trimDots(t0);
    // [Hunt] / [Hunt N] (CR 823.1.c.1): "When I conquer or hold, gain N XP" — one trigger each.
    var m = RegExp(r'^\[Hunt(?: (\d+))?\]$').firstMatch(t);
    if (m != null) {
      if (!_isUnit) return null;
      final n = int.tryParse(m[1] ?? '') ?? 1;
      return [Triggered(line, const When(On.conquer), [GainXp(N(n))]), Triggered(line, const When(On.hold), [GainXp(N(n))])];
    }
    // [Flow] {cost} (CR 829).
    m = RegExp(r'^\[Flow\] ((?:\{[0-9A-Z]+\})+)$').firstMatch(t);
    if (m != null) {
      if (!_isSpell) return null;
      final c = _cost(m[1]!);
      if (c == null || c.exhaust || c.extra.isNotEmpty) return null;
      return [Static(line, Flow(c.energy, c.power))];
    }
    // [Empower] {cost} / [Empower] - cost [or cost] [. This ability costs …] (CR 827).
    m = t.startsWith('[Empower] costs') ? null : RegExp(r'^\[Empower\](?: -)? (.+?)(?:\. This ability costs \{(\d+)\} less (if you control (\d+) or fewer runes|for each rune you control))?\.?$').firstMatch(t);
    if (m != null) {
      if (!(card.isPermanent || _isLegend)) return null;
      final less = m[2] == null ? null : (m[3]!.startsWith('for each') ? EnergyLess(int.parse(m[2]!), perRune: true) : EnergyLess(int.parse(m[2]!), ifRunesAtMost: int.parse(m[4]!)));
      final out = <Ability>[];
      for (final alt in m[1]!.split(' or ')) {
        final c = _powerCostOf(alt.trim());
        if (c == null) return null;
        out.add(Activated(line, less == null ? c : Cost(energy: c.energy, power: c.power, exhaust: c.exhaust, killMe: c.killMe, extra: [...c.extra, less]), const [EmpowerMe()]));
      }
      return out;
    }
    // [Empowered][>] X (CR 828), with an optional [>>] before a nested keyword.
    m = RegExp(r'^\[Empowered\]\[>\]\s*(?:\[>>\]\s*)?(.+)$').firstMatch(t);
    if (m != null) return _gated(m[1]!, const EmpoweredGate(), line);
    // [Level N][>] X (CR 824).
    m = RegExp(r'^\[Level (\d+)\]\[>\]\s*(?:\[>>\]\s*)?(.+)$').firstMatch(t);
    if (m != null) return _gated(m[2]!, LevelGate(int.parse(m[1]!)), line);
    // "While I'm buffed, …" / "While I'm [Empowered] three times, …" / "If you've gained XP this
    // turn, …": statics of the card itself.
    m = RegExp(r"^While I'm buffed, I have (.+)$").firstMatch(t);
    if (m != null && _isUnit) return _selfStatics(m[1]!, const BuffedGate(), line);
    m = RegExp(r"^While I'm \[Empowered\] (two|three|four) times, I have (.+)$").firstMatch(t);
    if (m != null && card.isPermanent) return _selfStatics(m[2]!, EmpoweredGate(_num(m[1]!)!), line);
    m = RegExp(r"^If you've gained XP this turn, I have (.+)$").firstMatch(t);
    if (m != null && _isUnit) return _selfStatics(m[1]!, const XpGainedGate(), line);
    if (t == 'Look at the top 5 cards of your Main Deck. You may banish a unit or gear from among them and play it, reducing its Energy cost by {5}. Recycle the rest. Then you may do this: Empower it.' && _isSpell) {
      return [SpellBody(line, const [LookBanishPlay(5, energyLess: 5, empowerAfter: true)])];
    }
    // Two events on one trigger: "When I'm played and when I conquer, …", "When you play me or
    // when I hold, …".
    m = RegExp(r"^When (I'm played|you play me) (?:and|or) when I (conquer|hold), (.+)$").firstMatch(t);
    if (m != null && _isUnit) {
      final e = _effects(_Line._cap(m[3]!));
      if (e == null) return null;
      return [Triggered(line, const When(On.played), e), Triggered(line, When(m[2] == 'conquer' ? On.conquer : On.hold), e)];
    }
    // Two linked statics: "Your units have +1 {M}. If I'm [Empowered], they have +2 {M} instead."
    m = RegExp(r"^Your units have \+(\d+) \{M\}\. If I'm \[Empowered\], they have \+(\d+) \{M\} instead\.?$").firstMatch(t);
    if (m != null && card.isPermanent) {
      const f = Filter(side: Side.friendly);
      return [Static(line, PowerAnthem(int.parse(m[1]!), f), gate: const EmpoweredGate(0)), Static(line, PowerAnthem(int.parse(m[2]!), f), gate: const EmpoweredGate())];
    }
    m = RegExp(r"^Opponents' spells cost \{(\d+)\} more\. If this is \[Empowered\], they cost \{(\d+)\}((?:\{A\})*) more instead\.?$").firstMatch(t);
    if (m != null && card.isPermanent) {
      return [
        Static(line, SpellCostMod(int.parse(m[1]!), 0, yours: false), gate: const EmpoweredGate(0)),
        Static(line, SpellCostMod(int.parse(m[2]!), '{A}'.allMatches(m[3]!).length, yours: false), gate: const EmpoweredGate()),
      ];
    }
    // "[Reaction][>] {E}: [Add] {1}. If this is [Empowered], [Add] {2} instead." — two abilities.
    m = RegExp(r"^\[Reaction\]\[>\] \{E\}: \[Add\] \{(\d+)\}\. If this is \[Empowered\], \[Add\] \{(\d+)\} instead\.?$").firstMatch(t);
    if (m != null && _isGear) {
      return [
        Activated(line, const Cost(exhaust: true), [AddRes(energy: int.parse(m[1]!))], timing: Timing.reaction, gate: const EmpoweredGate(0)),
        Activated(line, const Cost(exhaust: true), [AddRes(energy: int.parse(m[2]!))], timing: Timing.reaction, gate: const EmpoweredGate()),
      ];
    }
    // Additional costs of XP or buffs (CR 356.3).
    m = RegExp(r'^You may spend (\d+) XP as an additional cost to play (?:me|this)(?:\. If you do, I cost \{(\d+)\} less)?\.?$').firstMatch(t);
    if (m != null && card.isMainDeck) return [Static(line, AddCost(XPay.xp, n: int.parse(m[1]!), discount: int.tryParse(m[2] ?? '') ?? 0))];
    m = RegExp(r"^As you play this, you may spend a buff as an additional cost\. If you do, ignore this spell's cost\.?$").firstMatch(t);
    if (m != null && _isSpell) return [Static(line, const AddCost(XPay.spendBuff, ignoreCost: true))];
    m = RegExp(r'^As you play me, you may spend any number of buffs as an additional cost\. Reduce my cost by \{([A-Z])\} for each buff you spend\.?$').firstMatch(t);
    if (m != null && _isUnit) {
      final d = Domain.values.where((d) => d.letter == m![1]).firstOrNull;
      return d == null ? null : [Static(line, AddCost(XPay.spendBuff, anyNumber: true, discountEach: d))];
    }
    m = RegExp(r"^When you play me, each player must kill one of their units\. If you paid my additional cost, you don't kill a unit this way\.?$").firstMatch(t);
    if (m != null && _isUnit && card.text.contains('as an additional cost')) return [Triggered(line, const When(On.played), const [EachKillsOne(notYouIfPaid: true)])];
    m = RegExp(r'^Choose an enemy unit at a battlefield with (\d+) \{M\} or less\. If you paid the additional cost, choose any enemy unit at a battlefield instead\. (Take control of it, exhaust it, and recall it)\.?$').firstMatch(t);
    if (m != null && _isSpell && card.text.contains('as an additional cost')) {
      final e = _effects('Choose an enemy unit at a battlefield. Take control of it. Exhaust it. Recall it.');
      if (e == null || e.isEmpty || e.first is! Pick) return null;
      final pick = e.first as Pick;
      if (pick.targets.length != 1 || pick.targets.first is! Choose) return null;
      final ch = pick.targets.first as Choose;
      final f = ch.filter;
      final nf = Filter(side: f.side, where: f.where, pw: PowerFilter(mightMaxUnlessPaid: int.parse(m[1]!)));
      return [SpellBody(line, [Pick([Choose(nf, slot: ch.slot, upTo: ch.upTo)]), ...e.skip(1)])];
    }
    final p = _powerStatic(t);
    if (p != null) return [Static(line, p)];
    return null;
  }

  /// "I have +2 {M} and [Ganking]" / "[Deflect 3] and [Ganking]" / "an additional +1 {M}" →
  /// statics of the card, each under [gate].
  List<Ability>? _selfStatics(String text, Gate? gate, String line) {
    final out = <Ability>[];
    for (final part0 in _trimDots(text).replaceAll(RegExp(r'\.$'), '').split(RegExp(r', and |, | and '))) {
      final part = part0.trim();
      var m = RegExp(r'^(?:an additional )?\+(\d+) \{M\}$').firstMatch(part);
      if (m != null) {
        out.add(Static(line, SelfMight(int.parse(m[1]!)), gate: gate));
        continue;
      }
      m = RegExp(r'^\[([A-Za-z]+)(?: (\d+))?\]$').firstMatch(part);
      if (m != null) {
        final kw = _kwNames[m[1]!.toLowerCase()];
        if (kw == null || !const {Kw.assault, Kw.shield, Kw.tank, Kw.ganking, Kw.deflect}.contains(kw)) return null;
        out.add(Static(line, SelfKw(kw, int.tryParse(m[2] ?? '') ?? 1), gate: gate));
        continue;
      }
      if (part == 'enter ready' && _isUnit) {
        out.add(Static(line, const EntersReady(), gate: gate));
        continue;
      }
      if (RegExp(r"^can't be dealt damage unless I'm in combat$").hasMatch(part) && _isUnit) {
        out.add(Static(line, const NoDamageOutsideCombat(), gate: gate));
        continue;
      }
      return null;
    }
    return out.isEmpty ? null : out;
  }

  /// [inner] parsed as abilities, each made dependent on [gate].
  List<Ability>? _gated(String inner0, Gate gate, String line) {
    final inner = _trimDots(inner0);
    if (_isSpell) {
      // A spell's line: its instructions happen only if the condition holds as it resolves;
      // "… instead" replaces the line before (merged by _powerPost).
      final lv = gate is LevelGate ? gate.n : null;
      if (lv == null) return null;
      final cost = RegExp(r'^This costs \{(\d+)\} less( instead)?\.?$').firstMatch(inner);
      if (cost != null) return [Static(line, SpellCostLess(int.parse(cost[1]!)), gate: gate)];
      final instead = RegExp(r'^(.+) instead\.?$').firstMatch(inner);
      if (instead != null) {
        _powerItSlot = _slotCounter[0] > 0 ? _slotCounter[0] - 1 : null;
        try {
          final e = _effects(_Line._cap(instead[1]!));
          if (e == null) return null;
          return [SpellBody(line, [InsteadIf(HasXp(lv), const [], e)])];
        } finally {
          _powerItSlot = null;
        }
      }
      final e = _effects(inner);
      return e == null ? null : [SpellBody(line, [If(HasXp(lv), e)])];
    }
    // "I have …" statics.
    final have = RegExp(r'^I have (.+)$').firstMatch(inner);
    if (have != null && card.isPermanent) {
      final s = _selfStatics(have[1]!, gate, line);
      if (s != null) return s;
    }
    if (inner == 'I enter ready.' || inner == 'I enter ready') {
      return _isUnit ? [Static(line, const EntersReady(), gate: gate)] : null;
    }
    final abs = parse(inner);
    if (abs == null || abs.isEmpty) return null;
    final out = <Ability>[];
    for (final a in abs) {
      switch (a) {
        case Triggered():
          if (a.gate != null) return null;
          out.add(Triggered(line, a.on, a.effects, legion: a.legion, gate: gate));
        case Activated():
          if (a.gate != null) return null;
          out.add(Activated(line, a.cost, a.effects, timing: a.timing, oncePerTurn: a.oncePerTurn, legion: a.legion, gate: gate));
        case Static():
          if (a.gate != null) return null;
          out.add(Static(line, a.passive, gate: gate));
        case KeywordAb():
          if (!const {Kw.assault, Kw.shield, Kw.tank, Kw.ganking, Kw.deflect}.contains(a.kw) || !card.isPermanent) return null;
          out.add(Static(line, SelfKw(a.kw, a.n), gate: gate));
        default:
          return null;
      }
    }
    return out;
  }

  /// Statics of this family that aren't gated.
  Passive? _powerStatic(String t) {
    var m = RegExp(r'^I can be \[Empowered\] up to (two|three|four) times\.?$').firstMatch(t);
    if (m != null && card.isPermanent) return EmpowerTimes(_num(m[1]!)!);
    m = RegExp(r"^I have \+(\d+) \{M\} for each time I'm \[Empowered\]\.?$").firstMatch(t);
    if (m != null && _isUnit) return SelfMight(int.parse(m[1]!), perEmpowered: true);
    if (t == 'I can have any number of buffs.' && _isUnit) return const ManyBuffs();
    m = RegExp(r'^I get \+(\d+) \{M\} for each buffed friendly unit at my battlefield\.?$').firstMatch(t);
    if (m != null && _isUnit) return SelfMight(int.parse(m[1]!), perBuffedFriendlyHere: true);
    m = RegExp(r'^Other buffed friendly units at my battlefield have \+(\d+) \{M\}\.?$').firstMatch(t);
    if (m != null && _isUnit) return PowerAnthem(int.parse(m[1]!), const Filter(side: Side.friendly, other: true, buffed: true, where: Where.here, pw: PowerFilter(atBattlefieldOnly: true)));
    if (t == "Friendly buffed units have [Deflect] if they didn't already." && card.isPermanent) {
      return const PowerAnthem(1, Filter(side: Side.friendly, buffed: true), kw: Kw.deflect);
    }
    m = RegExp(r'^Your units that are \[Empowered\] have \+(\d+) \{M\}\.?$').firstMatch(t);
    if (m != null && (card.isPermanent || _isLegend)) return PowerAnthem(int.parse(m[1]!), const Filter(side: Side.friendly, pw: PowerFilter(empowered: true)));
    m = RegExp(r'^Your units have \+(\d+) \{M\}\.?$').firstMatch(t);
    if (m != null && (card.isPermanent || _isLegend)) return PowerAnthem(int.parse(m[1]!), const Filter(side: Side.friendly));
    if (t == 'Your units enter ready.' && (card.isPermanent || _isLegend)) return const UnitsEnterReady();
    m = RegExp(r'^I cost \{(\d+)\}((?:\{[A-Z]\})*) less(?: instead)?\.?$').firstMatch(t);
    if (m != null && card.isMainDeck) {
      final c = _cost('{${m[1]}}${m[2]}');
      return c == null ? null : CostLessPower(c.energy, c.power);
    }
    m = RegExp(r'^Your spells cost \{(\d+)\}((?:\{A\})*) less, to a minimum of \{(\d+)\}\.?$').firstMatch(t);
    if (m != null && (card.isPermanent || _isLegend)) return SpellCostMod(-int.parse(m[1]!), -'{A}'.allMatches(m[2]!).length, yours: true, minEnergy: int.parse(m[3]!));
    m = RegExp(r'^Spells with \[Flow\] you play from your trash cost \{(\d+)\} less, to a minimum of \{(\d+)\}\.?$').firstMatch(t);
    if (m != null && (card.isPermanent || _isLegend)) return FlowCostLess(int.parse(m[1]!), minEnergy: int.parse(m[2]!));
    m = RegExp(r"^This costs \{(\d+)\} less if you control something that's \[Empowered\]\.?$").firstMatch(t);
    if (m != null && _isSpell) return SpellCostLess(int.parse(m[1]!), ifControlEmpowered: true);
    if (t == 'Units here have "{E}: Gain 1 XP."' && _isBattlefield) return const GrantXpAbility();
    if (t == '[Empower] costs of your units here cost {1} or {A} less.' && _isBattlefield) return const EmpowerCostLessHere();
    if (t == 'If a spell or ability that chooses me would stun me, give me -{M}, or return me to hand, give me +3 {M} instead.' && _isUnit) return const ChosenHarmToMight(3);
    if (t == "Your spells and abilities can't be countered. If a spell or ability you control would give -{M} to a unit it chooses, it gives an additional -1 {M}." && card.isPermanent) return const MelAwakened();
    if (t == 'I can be played to an occupied battlefield if an enemy unit is alone there.' && _isUnit) return const PlayToLoneEnemy();
    if (t == 'Friendly units can be played to an occupied battlefield if an enemy unit is alone there.' && card.isPermanent) return const PlayToLoneEnemy(friendly: true);
    if (t == "I can't be chosen by enemy spells and abilities." && _isUnit) return const CantBeChosen();
    if (t == 'Your conquer effects for conquering here trigger an additional time.' && _isUnit) return const ConquerTwiceHere();
    if (t == 'When a buffed unit you control would die, you may pay {A} and exhaust me to spend its buff and recall it exhausted instead.' && _isLegend) return const SaveBuffed();
    return null;
  }

  /// An Empower cost: "{2}{R}", "{E}", "{1}, {E}", "Kill a friendly unit", "Discard 1",
  /// "Discard a spell".
  Cost? _powerCostOf(String s) {
    if (s == 'Kill a friendly unit') return const Cost(extra: [KillFriendly()]);
    if (s == 'Discard 1') return const Cost(extra: [DiscardCost(1)]);
    if (s == 'Discard a spell') return const Cost(extra: [DiscardCost(1, spell: true)]);
    return _cost(s);
  }

  /// A part of an activated ability's cost the core parser doesn't know.
  CostPart? _powerCostPart(String part) {
    final m = RegExp(r'^Spend (\d+) XP$').firstMatch(part);
    if (m != null) return SpendXp(int.parse(m[1]!));
    if (part == 'Spend my buff' && _isUnit) return const SpendMyBuff();
    if ((part == 'Disempower me' && (_isUnit || _isLegend)) || (part == 'Disempower this' && _isGear)) return const DisempowerMe();
    return null;
  }

  When? _powerWhen(String s) {
    final perm = card.isPermanent;
    final legendOrPerm = perm || _isLegend;
    return switch (s) {
      'When I become [Empowered]' when perm => const When(On.empowered),
      'When you empower something else' when legendOrPerm => const When(On.youEmpowerOther),
      'When you buff me' when _isUnit => const When(On.buffedMe),
      'When you buff a friendly unit' when legendOrPerm => const When(On.youBuffFriendly),
      'When you spend a buff' when legendOrPerm => const When(On.youSpendBuff),
      'When you play another unit' when _isUnit => const When(On.youPlayAnotherUnit),
      'When another friendly unit dies' when _isUnit => const When(On.anotherFriendlyDies),
      'When a buffed friendly unit dies' when legendOrPerm => const When(On.buffedFriendlyDies),
      'When a combat that I was in ends' when _isUnit => const When(On.combatEnds),
      'When my Might becomes 10 or more' when _isUnit => const When(On.mightTen),
      'When you recycle one or more cards' when legendOrPerm => const When(On.youRecycle),
      'When you banish a card you own' when legendOrPerm => const When(On.youBanishOwn),
      'When you play a card from anywhere other than your hand' when legendOrPerm => const When(On.youPlayNotFromHand),
      'When a player plays a unit here' when _isBattlefield => const When(On.unitPlayedHere),
      _ => null,
    };
  }

  /// Is the trigger [on] about a unit ("it" means that unit)?
  static bool eventUnitTrigger(On on) => const {On.buffedMe, On.youBuffFriendly, On.anotherFriendlyDies, On.buffedFriendlyDies, On.unitPlayedHere}.contains(on);

  Cond? _powerCond(String c) {
    if (c == "I'm [Empowered]" || c == 'this is [Empowered]') return const IsEmpowered();
    if (c == "it's [Empowered]") {
      final it = _itSlot;
      return it == null ? null : IsEmpowered(slot: it);
    }
    if (c == "you control something that's [Empowered]") return const ControlEmpowered();
    if (c == "it's your turn") return const YourTurn();
    var m = RegExp(r'^you control (\d+) or more runes$').firstMatch(c);
    if (m != null) return RunesCount(int.parse(m[1]!));
    m = RegExp(r'^you control (a|an) ([A-Z][a-z]+)$').firstMatch(c);
    if (m != null) return ControlTag(m[2]!);
    m = RegExp(r"^an opponent's score is within (\d+) points of the Victory Score$").firstMatch(c);
    if (m != null) return OpponentNearVictory(int.parse(m[1]!));
    if (c == 'an enemy unit is alone here' && _isUnit) return const EnemyAloneHere();
    if ((c == 'I am at a battlefield' || c == "I'm at a battlefield") && _isUnit) return const AtBattlefield();
    m = RegExp(r'^you have exactly (two|three|\d+) units there$').firstMatch(c);
    if (m != null) {
      final it = _itSlot;
      return it == null ? null : ExactlyUnitsWithChosen(_num(m[1]!)!, it);
    }
    return null;
  }

  /// Target phrases of this family; null to let the core parser try.
  Target? _powerTarget(String p) {
    if (p == 'it' && _powerItSlot != null) return Chosen(_powerItSlot!);
    if (p == 'me' && _isLegend) return const Me();
    if (p == 'this' && _isGear) return const Me();
    if (p == 'another friendly unit' && (_isGear || _isLegend)) return Choose(const Filter(side: Side.friendly), slot: _slotCounter[0]++);
    if (p == 'a friendly unit in a showdown') return Choose(const Filter(side: Side.friendly, pw: PowerFilter(inShowdown: true)), slot: _slotCounter[0]++);
    if (p == 'another gear' && _isGear) return Choose(const Filter(gear: true, other: true), slot: _slotCounter[0]++);
    if (p == 'something here' && _isUnit) return Choose(const Filter(where: Where.here, pw: PowerFilter(anyType: true)), slot: _slotCounter[0]++);
    if (p == 'something you control') return Choose(const Filter(side: Side.friendly, pw: PowerFilter(anyType: true, legends: true)), slot: _slotCounter[0]++);
    if (p == 'a legend, unit, or gear') return Choose(const Filter(pw: PowerFilter(anyType: true, legends: true)), slot: _slotCounter[0]++);
    var m = RegExp(r"^(a|an) (.+?) that's \[Empowered\]$").firstMatch(p);
    if (m != null) {
      final f = _filter(m[2]!, plural: false);
      return f == null ? null : Choose(_withPw(f, const PowerFilter(empowered: true)), slot: _slotCounter[0]++);
    }
    m = RegExp(r'^(a|an) (.+?) at a battlefield I moved to or from$').firstMatch(p);
    if (m != null && _isUnit) {
      final f = _filter(m[2]!, plural: false);
      return f == null ? null : Choose(_withPw(f, const PowerFilter(movedFromOrTo: true)), slot: _slotCounter[0]++);
    }
    m = RegExp(r'^(a|an) (.+?) with less Might than (me|it)$').firstMatch(p);
    if (m != null) {
      if (m[3] == 'me' && !_isUnit) return null;
      final it = _itSlot;
      if (m[3] == 'it' && it == null) return null;
      final f = _filter(m[2]!, plural: false);
      return f == null ? null : Choose(_withPw(f, m[3] == 'me' ? const PowerFilter(lessMightThanSource: true) : PowerFilter(lessMightThanChosen: it)), slot: _slotCounter[0]++);
    }
    m = RegExp(r'^all other friendly units there$').firstMatch(p);
    if (m != null && _isUnit) return const Each(Filter(side: Side.friendly, other: true, where: Where.here));
    m = RegExp(r'^your units here$').firstMatch(p);
    if (m != null && _isUnit) return const Each(Filter(side: Side.friendly, where: Where.here));
    m = RegExp(r'^(a|an) (exhausted friendly unit|friendly unit|unit) from a battlefield$').firstMatch(p);
    if (m != null) {
      final f = _filter(m[2]!, plural: false);
      return f == null ? null : Choose(Filter(side: f.side, exhausted: f.exhausted, where: Where.battlefield), slot: _slotCounter[0]++);
    }
    return null;
  }

  static Filter _withPw(Filter f, PowerFilter pw) =>
      Filter(side: f.side, where: f.where, gear: f.gear, mightMax: f.mightMax, mightMin: f.mightMin, other: f.other, exhausted: f.exhausted, attacking: f.attacking, defending: f.defending, tag: f.tag, buffed: f.buffed, pw: pw);

  /// Sentences that must be read before the core parser's "If …" rule.
  List<Effect>? _powerSentenceEarly(String s) {
    // "If I'm [Empowered], deal 2 instead" etc.: placeholders _powerMerge folds into the
    // sentence before.
    var m = RegExp(r"^If (I'm|it's|this is) \[Empowered\], (.+) instead$").firstMatch(s);
    if (m != null) {
      final cond = _powerCond("${m[1]} [Empowered]");
      if (cond == null) return null;
      final body = m[2]!;
      // "deal 2" (same target as before) is filled in by _powerMerge.
      final deal = RegExp(r'^deal (\d+)$').firstMatch(body);
      if (deal != null) return [InsteadIf(cond, const [], [Deal(N(int.parse(deal[1]!)), const Me())])];
      final e = _effectsWithIt(_Line._cap(body));
      return e == null ? null : [InsteadIf(cond, const [], e)];
    }
    m = RegExp(r'^Otherwise, (.+)$').firstMatch(s);
    if (m != null) {
      final e = _effectsWithIt(_Line._cap(m[1]!));
      return e == null ? null : [InsteadIf(const IsEmpowered(slot: -99), const [], e)];
    }
    m = RegExp(r'^If you do, (.+)$').firstMatch(s);
    if (m != null) {
      final e = _sentence(_Line._cap(m[1]!));
      return e == null ? null : [PayToDo(const PayKillGear(), e, optional: false)];
    }
    m = RegExp(r'^Then,? (?:if (.+?), )?(.+)$').firstMatch(s);
    if (m != null && !s.startsWith('Then for each') && !s.startsWith('Then you may do this')) {
      if (m[1] != null) {
        final c = _cond(m[1]!);
        final e = c == null ? null : _sentence(_Line._cap(m[2]!));
        return e == null ? null : [If(c!, e)];
      }
      return _sentence(_Line._cap(m[2]!));
    }
    return null;
  }

  List<Effect>? _effectsWithIt(String text) {
    final saved = _powerItSlot;
    _powerItSlot ??= _itSlot;
    try {
      return _effects(text);
    } finally {
      _powerItSlot = saved;
    }
  }

  /// Sentences the core parser doesn't know (tried after it).
  List<Effect>? _powerSentence(String s) {
    var m = RegExp(r'^Gain (\d+) XP$').firstMatch(s);
    if (m != null) return [GainXp(N(int.parse(m[1]!)))];
    m = RegExp(r'^Gain 1 XP for each friendly unit$').firstMatch(s);
    if (m != null) return const [GainXp(PerFriendlyUnit())];
    m = RegExp(r'^Disempower something you control to (.+)$').firstMatch(s);
    if (m != null) {
      final e = _sentence(_Line._cap(m[1]!));
      return e == null ? null : [PayToDo(const PayDisempower(), e, optional: false)];
    }
    m = RegExp(r'^Choose a unit in your trash with Energy cost no more than \{(\d+)\} and Power cost no more than ((?:\{A\})+)$').firstMatch(s);
    if (m != null) return [PlayFromTrash(maxEnergy: int.parse(m[1]!), maxPower: '{A}'.allMatches(m[2]!).length)];
    if (s == 'Choose a player') return const [];
    if (s == 'They gain control of this and recall it' && _isGear) return const [GiftMe()];
    m = RegExp(r"^Move (.+) to base and if I'm \[Empowered\], ready it$").firstMatch(s);
    if (m != null && _isLegend) {
      final t = _target(m[1]!);
      final it = _slotCounter[0] - 1;
      return t == null ? null : [ToBase(t), If(const IsEmpowered(), [Ready(Chosen(it))])];
    }
    m = RegExp(r'^(Empower|Disempower) (.+?)( at end of turn)?$').firstMatch(s);
    if (m != null) {
      final t = m[2] == 'it' ? (_itSlot == null ? null : Chosen(_itSlot!)) : _target(m[2]!);
      if (t == null) return null;
      if (m[3] != null) return [Delayed(m[1] == 'Empower' ? 'empowerAtEnd' : 'disempowerAtEnd', target: t)];
      return [Empower(t, off: m[1] == 'Disempower')];
    }
    m = RegExp(r'^\[?Buff\]? up to (two|three|four) (other )?friendly units$').firstMatch(s);
    if (m != null) {
      if (m[2] != null && !_isUnit) return null;
      return [BuffUpTo(_num(m[1]!)!, Filter(side: Side.friendly, other: m[2] != null))];
    }
    m = RegExp(r'^Pay \{(\d+)\} to (.+)$').firstMatch(s);
    if (m != null) {
      final e = _sentence(_Line._cap(m[2]!));
      return e == null ? null : [PayToDo(PayRunes(int.parse(m[1]!), const []), e, optional: false)];
    }
    m = RegExp(r'^Pay \{([A-Z])\} and exhaust this to (.+)$').firstMatch(s);
    if (m != null && _isGear) {
      final d = Domain.byName(m[1]!);
      final e = _sentence(_Line._cap(m[2]!));
      return d == null || e == null ? null : [PayToDo(PayRunes(0, [d], exhaustMe: true), e, optional: false)];
    }
    m = RegExp(r'^(They may pay|Pay) \{(\d+)\} to \[Buff\] it$').firstMatch(s);
    if (m != null) {
      final pay = PayToDo(PayRunes(int.parse(m[2]!), const []), const [Buff(EventUnit())], optional: false);
      return [if (m[1] == 'Pay') pay else May([pay])];
    }
    m = RegExp(r'^They may pay \{(\d+)\} to (.+)$').firstMatch(s);
    if (m != null && _isBattlefield) {
      final e = _sentence(_Line._cap(m[2]!));
      return e == null ? null : [May([PayToDo(PayRunes(int.parse(m[1]!), const []), e, optional: false)])];
    }
    m = RegExp(r'^Spend (\d+) XP to (.+)$').firstMatch(s);
    if (m != null) {
      final e = _sentence(_Line._cap(m[2]!));
      return e == null ? null : [PayToDo(PayXp(int.parse(m[1]!)), e, optional: false)];
    }
    m = RegExp(r'^Spend a buff to (.+)$').firstMatch(s);
    if (m != null) {
      final e = _sentence(_Line._cap(m[1]!));
      return e == null ? null : [PayToDo(const PayBuff(), e, optional: false)];
    }
    m = RegExp(r'^Disempower something you control to (.+)$').firstMatch(s);
    if (m != null) {
      final e = _sentence(_Line._cap(m[1]!));
      return e == null ? null : [PayToDo(const PayDisempower(), e, optional: false)];
    }
    if (s == 'Spend any number of buffs') return const [SpendBuffsEach([])];
    m = RegExp(r'^For each buff spent, (.+)$').firstMatch(s);
    if (m != null) {
      final e = _sentence(_Line._cap(m[1]!));
      return e == null ? null : [SpendBuffsEach(e)];
    }
    if (s == 'For each friendly unit, you may spend its buff to ready it') return const [SpendEachBuffToReady()];
    if (s == 'Spend my buff' && _isUnit) return const [SpendBuffOf(Me())];
    m = RegExp(r'^Draw (\d+) or buff me$').firstMatch(s);
    if (m != null && _isUnit) {
      return [
        OneOf([
          [Draw(int.parse(m[1]!))],
          const [Buff(Me())],
        ]),
      ];
    }
    // "X and Y" when both halves are instructions ("Ready me and gain 3 XP").
    final and = _splitAnd(s);
    if (and != null) return and;
    // "Choose a unit" / "Choose a friendly unit [here]": a target for the sentences after.
    m = RegExp(r'^Choose (a|an) (.+)$').firstMatch(s);
    if (m != null && !m[2]!.contains(' and a battlefield') && m[2] != 'opponent' && m[2] != 'player') {
      final t = _target('${m[1]} ${m[2]}');
      return t == null ? null : [PickIt(t)];
    }
    m = RegExp(r'^Choose a friendly unit and a battlefield$').firstMatch(s);
    if (m != null) {
      final t = _target('a friendly unit');
      return t == null ? null : [PickIt(t)];
    }
    if (s == 'Move all enemy units at that battlefield with less Might than the chosen unit to their base') {
      final it = _itSlot;
      return it == null ? null : [StareDown(it)];
    }
    m = RegExp(r'^Its base Might becomes (\d+) this turn$').firstMatch(s);
    if (m != null) {
      final it = _itSlot;
      return it == null ? null : [BaseMightBecomes(int.parse(m[1]!), Chosen(it))];
    }
    m = RegExp(r'^Increase my Might to its Might this turn$').firstMatch(s);
    if (m != null && _isUnit) {
      final it = _itSlot;
      return it == null ? null : [MightUpTo(it)];
    }
    m = RegExp(r'^(.+) if it has (\d+) \{M\} or less$').firstMatch(s);
    if (m != null) {
      final it = _itSlot;
      if (it == null) return null;
      final e = _sentence(m[1]!);
      return e == null ? null : [If(ChosenMightAtMost(int.parse(m[2]!), it), e)];
    }
    m = RegExp(r'^Move (.+) from a battlefield to its base$').firstMatch(s);
    if (m != null) {
      final t = _target('${m[1]} from a battlefield');
      return t == null ? null : [ToBase(t)];
    }
    m = RegExp(r'^Move (.+?)(?: to a battlefield( where you have units)?)?$').firstMatch(s);
    if (m != null && !s.contains(' to its base') && !s.contains(' to their base') && !s.contains(' or from ')) {
      final tgt = m[1] == 'it' ? (_itSlot == null ? null : Chosen(_itSlot!)) : _target(m[1]!);
      if (tgt == null) return null;
      return [MoveAny(tgt, toBattlefield: s.contains(' to a battlefield'), whereYouHaveUnits: m[2] != null)];
    }
    m = RegExp(r'^They each get \+(\d+) \{M\} this turn$').firstMatch(s);
    if (m != null) {
      final it = _itSlot;
      return it == null ? null : [GiveMightAll(int.parse(m[1]!), Filter(side: Side.friendly, pw: PowerFilter(withChosen: it)))];
    }
    m = RegExp(r"^It can't be chosen by enemy spells and abilities this turn$").firstMatch(s);
    if (m != null) {
      final it = _itSlot;
      return it == null ? null : [Untargetable(Chosen(it))];
    }
    m = RegExp(r'^Give (your units here|friendly units here) \[([A-Za-z]+)\] this turn$').firstMatch(s);
    if (m != null && _isUnit) {
      final kw = _kwNames[m[2]!.toLowerCase()];
      return kw == null ? null : [GiveKwAll(kw, 1, const Filter(side: Side.friendly, where: Where.here))];
    }
    m = RegExp(r'^Ready (\d+) gear$').firstMatch(s);
    if (m != null) return [ReadyGear(int.parse(m[1]!))];
    if (s == 'Banish a unit from your trash') return const [BanishFromTrash()];
    m = RegExp(r'^Banish (.+)$').firstMatch(s);
    if (m != null) {
      final t = _target(m[1]!);
      return t == null ? null : [Banish(t)];
    }
    m = RegExp(r'^\[Burn (\d+)\]$').firstMatch(s);
    if (m != null) return [Burn(int.parse(m[1]!))];
    m = RegExp(r'^They \[Burn (\d+)\]$').firstMatch(s);
    if (m != null) return [Burn(int.parse(m[1]!), opponent: true)];
    if (s == 'Choose an opponent') return const [];
    if (s == 'They reveal their hand') return const [RevealHand()];
    if (s == 'You can look at their facedown cards this turn') return const [];
    if (s == 'You may pay 2 XP to choose a card from their hand') return const [RevealHand(payXpDiscard: 2)];
    if (s == 'If you do, they discard that card and draw 1') return const [];
    m = RegExp(r'^(?:Then you may do this: )?Choose a unit in their trash and play it, ignoring its cost$').firstMatch(s);
    if (m != null) return [May(const [PlayFromTrash(opponentsTrash: true)])];
    m = RegExp(r'^Choose a unit in your trash with Energy cost no more than \{(\d+)\} and Power cost no more than ((?:\{A\})+)$').firstMatch(s);
    if (m != null) return [PlayFromTrash(maxEnergy: int.parse(m[1]!), maxPower: '{A}'.allMatches(m[2]!).length)];
    if (s == 'Play it to your base, ignoring its cost') return const [];
    m = RegExp(r'^Play a 0 \{M\} Shadow Clone unit token$').firstMatch(s);
    if (m != null) return const [PowerToken('Shadow Clone', 1)];
    m = RegExp(r'^Play (two|a|an) 1 \{M\} Tentacle unit tokens? from Bilgewater$').firstMatch(s);
    if (m != null) return [PlayToken('Tentacle', _num(m[1]!)!)];
    m = RegExp(r'^Look at the top (\d+) cards of your Main Deck$').firstMatch(s);
    if (m != null) return [LookDraw(int.parse(m[1]!))];
    m = RegExp(r'^You may (choose a card|reveal a unit) from among them and draw it$').firstMatch(s);
    if (m != null) return [LookDraw(0, unitsOnly: m[1] == 'reveal a unit', reveal: m[1] == 'reveal a unit')];
    if (s == 'Put the rest into your trash') return const [LookDraw(0, restToTrash: true)];
    if (s == 'Recycle the rest') return const [LookDraw(0)];
    m = RegExp(r'^Then if you revealed a (.+?), do this: (.+)$').firstMatch(s);
    if (m != null) {
      final tags = m[1]!.replaceAll(', or ', ', ').replaceAll(' or ', ', ').split(', ');
      final e = _sentence(_Line._cap(m[2]!));
      return e == null ? null : [LookDraw(0, thenIfTags: tags, then: e)];
    }
    m = RegExp(r'^Each player must kill one of their units$').firstMatch(s);
    if (m != null) return const [EachKillsOne()];
    if (s == 'Give a spell in your trash [Flow] equal to its cost this turn') return const [GrantFlow()];
    m = RegExp(r'^It deals damage equal to its Might split among enemy units at battlefields$').firstMatch(s);
    if (m != null) {
      final it = _itSlot;
      return it == null ? null : [SplitMightDamage(it)];
    }
    if (s == 'Then for each unit this kills, do this: Gain 1 XP') return const [SplitMightDamage(-1, xpPerKill: 1)];
    // Delayed abilities this turn.
    if (s == 'When a friendly unit is played this turn, buff it') return const [Delayed('buffPlayedThisTurn')];
    if (s == 'The next time you play a unit this turn, ready it and [Buff] it') return const [Delayed('nextUnitReadyBuff')];
    m = RegExp(r'^When it wins a combat this turn, gain (\d+) XP$').firstMatch(s);
    if (m != null) {
      final it = _itSlot;
      return it == null ? null : [Delayed('xpWhenItWins', target: Chosen(it), n: int.parse(m[1]!))];
    }
    m = RegExp(r'^Give (.+?) \+(\d+) \{M\} this turn and gain (\d+) XP$').firstMatch(s);
    if (m != null) {
      final t = _target(m[1]!);
      return t == null ? null : [GiveMight(int.parse(m[2]!), t), GainXp(N(int.parse(m[3]!)))];
    }
    m = RegExp(r'^Kill this and deal (\d+) to all units you control$').firstMatch(s);
    if (m != null && _isGear) return [Kill(const Me()), Deal(N(int.parse(m[1]!)), const Each(Filter(side: Side.friendly)))];
    m = RegExp(r'^Choose a player\. They gain control of this and recall it$').firstMatch(s);
    if (m != null && _isGear) return const [GiftMe()];
    return null;
  }

  /// "A and B" → both, when each half reads as an instruction.
  List<Effect>? _splitAnd(String s) {
    var i = s.indexOf(' and ');
    while (i > 0) {
      final a = s.substring(0, i);
      final b = s.substring(i + 5);
      if (b.isNotEmpty && RegExp(r'^(ready|buff|draw|gain|give|exhaust|stun|deal|recall|kill|channel|move|play|heal|\[buff\]|\[stun\])\b', caseSensitive: false).hasMatch(b)) {
        final saved = _slotCounter[0];
        final ea = _sentence(a);
        if (ea != null) {
          final eb = _effectsWithIt(_Line._cap(b));
          if (eb != null) return [...ea, ...eb];
        }
        _slotCounter[0] = saved;
      }
      i = s.indexOf(' and ', i + 5);
    }
    return null;
  }
}

/// Folds placeholder effects into the sentence before them ("… . If I'm [Empowered], deal 2
/// instead.", "… . If you do, …", "Spend any number of buffs. For each buff spent, …", the parts of
/// "look at the top N"). True: merged; false: a placeholder with nothing to fold into (the text
/// isn't understood); null: [next] isn't a placeholder (add it as it is).
bool? _powerMerge(List<Effect> out, List<Effect> next) {
  if (next.isEmpty) return true;
  final n = next.first;
  if (n is InsteadIf && n.normal.isEmpty) {
    if (out.isEmpty) return false;
    final last = out.removeLast();
    // "Otherwise, …" after "If it's [Empowered], …": the innermost If's opposite.
    if (n.cond is IsEmpowered && (n.cond as IsEmpowered).slot == -99) {
      Effect? otherwise(Effect e) {
        if (e is! If) return null;
        if (e.effects.isNotEmpty && e.effects.last is If && e.effects.any((x) => x is PickIt)) {
          final inner = otherwise(e.effects.last);
          return inner == null ? null : If(e.cond, [...e.effects.take(e.effects.length - 1), inner]);
        }
        return InsteadIf(e.cond, n.instead, e.effects);
      }

      final o = otherwise(last);
      if (o == null) return false;
      out.add(o);
      return true;
    }
    Effect fold(Effect e) {
      if (e is May) return May([for (final x in e.effects) fold(x)]);
      // "deal 2 instead": the same target as the Deal before.
      final inst = [for (final x in n.instead) (x is Deal && x.target is Me && e is Deal) ? Deal(x.amount, e.target) : x];
      return InsteadIf(n.cond, [e], inst);
    }

    out.add(fold(last));
    out.addAll(next.skip(1));
    return true;
  }
  if (n is PayToDo && n.pay is PayKillGear && !n.optional) {
    // "You may kill a gear. If you do, buff me."
    if (out.isEmpty || out.last is! May) return false;
    final may = out.removeLast() as May;
    if (may.effects.length != 1 || (may.effects.first is! Kill && may.effects.first is! BanishFromTrash)) return false;
    out.add(May([PayToDo(PayEffect(may.effects.first), n.effects, optional: false)]));
    return true;
  }
  if (n is SpendBuffsEach && n.effects.isNotEmpty) {
    if (out.isEmpty || out.last is! SpendBuffsEach || (out.last as SpendBuffsEach).effects.isNotEmpty) return false;
    out
      ..removeLast()
      ..add(n);
    return true;
  }
  if (n is LookDraw && n.n == 0) {
    if (out.isEmpty || out.last is! LookDraw) return false;
    final l = out.removeLast() as LookDraw;
    out.add(LookDraw(l.n, unitsOnly: l.unitsOnly || n.unitsOnly, reveal: l.reveal || n.reveal, restToTrash: l.restToTrash || n.restToTrash, thenIfTags: n.thenIfTags.isEmpty ? l.thenIfTags : n.thenIfTags, then: n.then.isEmpty ? l.then : n.then));
    return true;
  }
  if (n is RevealHand && n.payXpDiscard > 0) {
    if (out.isEmpty || out.last is! RevealHand) return false;
    out
      ..removeLast()
      ..add(n);
    return true;
  }
  if (n is GainXp && out.isNotEmpty && out.last is RevealHand && (out.last as RevealHand).xp == 0 && n.amount is N) {
    final r = out.removeLast() as RevealHand;
    out.add(RevealHand(payXpDiscard: r.payXpDiscard, xp: (n.amount as N).n));
    return true;
  }
  if (n is SplitMightDamage && n.slot < 0) {
    if (out.isEmpty || out.last is! SplitMightDamage) return false;
    final s = out.removeLast() as SplitMightDamage;
    out.add(SplitMightDamage(s.slot, xpPerKill: n.xpPerKill));
    return true;
  }
  // "If it's [Empowered], disempower it" after "if you control 7 or more runes, choose an enemy
  // gear": inside that If.
  if (out.isNotEmpty && out.last is If && (out.last as If).effects.any((x) => x is PickIt)) {
    final i = out.removeLast() as If;
    final inner = [...i.effects];
    final r = _powerMerge(inner, next);
    if (r == false) return false;
    if (r == null) inner.addAll(next);
    out.add(If(i.cond, inner));
    return true;
  }
  return null;
}

/// After all lines: "[Level N][>] … instead." on a spell replaces the line before it.
void _powerPost(RCard c, List<Ability> abilities) {
  if (c.type != CardType.spell) return;
  for (var i = 1; i < abilities.length; i++) {
    final a = abilities[i];
    if (a is! SpellBody || a.effects.length != 1) continue;
    final e = a.effects.first;
    if (e is! InsteadIf || e.normal.isNotEmpty) continue;
    final prev = abilities.lastIndexWhere((x) => x is SpellBody, i - 1);
    if (prev < 0) continue;
    final p = abilities[prev] as SpellBody;
    abilities[prev] = SpellBody(p.text, [InsteadIf(e.cond, p.effects, e.instead)]);
    abilities.removeAt(i);
    i--;
  }
}
