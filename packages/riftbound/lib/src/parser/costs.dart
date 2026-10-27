part of 'parser.dart';

/// Costs, modes and playing cards from elsewhere (ir_costs.dart): additional and alternative
/// costs, cost changes, "Choose one" lists, and "play … from your trash". Each method returns null
/// for text it doesn't know, so the general parser carries on.
extension _XLine on _Line {
  static const _tagList = r'(?:a |an )?([A-Z][a-z]+(?:, [A-Z][a-z]+)*,? or [A-Z][a-z]+)';

  List<String> _tagsOf(String s) => [for (final t in s.replaceAll(RegExp(r',? or '), ', ').split(', ')) if (t.trim().isNotEmpty) t.trim()];

  /// "{1}{R}" → Energy and Power, or null.
  (int, List<Domain?>)? _res(String s) {
    final c = _cost(s);
    if (c == null || c.exhaust || c.killMe || c.extra.isNotEmpty) return null;
    return (c.energy, c.power);
  }

  bool get _isUnit => card.type == CardType.unit;
  bool get _playable => card.isMainDeck;

  // -------------------------------------------------------------------------------------------
  // Whole lines
  // -------------------------------------------------------------------------------------------

  List<Ability>? _xLine(String t, String line) {
    // "[Repeat] - {1} / {A} / {1}{A}": one Repeat cost per option, each paid or not (CR 820.1.c.2).
    var m = RegExp(r'^\[Repeat\] - ((?:\{[0-9A-Z]+\})+(?: / (?:\{[0-9A-Z]+\})+)+)$').firstMatch(t);
    if (m != null) {
      if (!_isSpell) return null;
      final out = <Ability>[];
      for (final part in m[1]!.split(' / ')) {
        final c = _cost(part);
        if (c == null) return null;
        out.add(RepeatCost(line, c));
      }
      return out;
    }
    final add = _addCostLine(t, line);
    if (add != null) return add;
    final p = _xPassiveLine(t);
    if (p != null) return [Static(line, p)];
    return _xTriggerLine(t, line);
  }

  /// Additional costs on the card being played (CR 204.2): "You may pay {1}{R} as an additional
  /// cost to play me.", "As an additional cost to play me, kill a friendly unit.", …
  List<Ability>? _addCostLine(String t, String line) {
    if (!_playable) return null;
    final self = _isSpell ? 'this' : 'me';
    // "If you've played a spell this turn, you may pay {P} as an additional cost to play me. If
    // you do, I enter ready."
    var m = RegExp(r"^If you've played a spell this turn, you may pay ((?:\{[0-9A-Z]+\})+) as an additional cost to play me\. If you do, I enter ready\.$").firstMatch(t);
    if (m != null && _isUnit) {
      final r = _res(m[1]!);
      return r == null ? null : [Static(line, AddCost(XPay.resources, energy: r.$1, power: r.$2, ifSpellPlayed: true, entersReady: true))];
    }
    // "You may pay {1}{R} as an additional cost to play me." / "As you play this, you may pay {O}
    // as an additional cost." / "As you play me, you may pay {G} as an additional cost. If you do,
    // draw 1."
    m = RegExp('^(?:You may pay ((?:\\{[0-9A-Z]+\\})+) as an additional cost to play $self|As you play $self, you may pay ((?:\\{[0-9A-Z]+\\})+) as an additional cost)\\.(?: If you do, (.+))?\$').firstMatch(t);
    if (m != null) {
      final r = _res(m[1] ?? m[2]!);
      if (r == null) return null;
      var then = const <Effect>[];
      if (m[3] != null) {
        final e = _effects(_Line._cap(m[3]!));
        if (e == null || _isSpell) return null;
        then = e;
      }
      return [Static(line, AddCost(XPay.resources, energy: r.$1, power: r.$2, then: then))];
    }
    // "You may discard 1 as an additional cost to play me." / "As you play me, you may discard 1
    // as an additional cost. If you do, reduce my cost by {2}." / "As an additional cost to play
    // this, you may discard 1."
    m = RegExp('^(?:You may discard (\\d+) as an additional cost to play $self|As you play $self, you may discard (\\d+) as an additional cost|As an additional cost to play $self, you may discard (\\d+))\\.(?: If you do, reduce my cost by \\{(\\d+)\\}\\.)?\$').firstMatch(t);
    if (m != null) {
      return [Static(line, AddCost(XPay.discard, n: int.parse(m[1] ?? m[2] ?? m[3]!), discount: int.tryParse(m[4] ?? '') ?? 0))];
    }
    // "As you play this, you may spend a buff as an additional cost. If you do, ignore this
    // spell's cost."
    if (t == "As you play this, you may spend a buff as an additional cost. If you do, ignore this spell's cost." && _isSpell) {
      return [Static(line, const AddCost(XPay.spendBuff, ignoreCost: true))];
    }
    // "As you play me, you may spend any number of buffs as an additional cost. Reduce my cost by
    // {O} for each buff you spend."
    m = RegExp(r'^As you play me, you may spend any number of buffs as an additional cost\. Reduce my cost by \{([A-Z])\} for each buff you spend\.$').firstMatch(t);
    if (m != null && _isUnit) {
      final d = Domain.byName(m[1]!);
      return d == null ? null : [Static(line, AddCost(XPay.spendBuff, anyNumber: true, discountEach: d))];
    }
    // "As you play me, you may kill any number of friendly units as an additional cost. Reduce my
    // cost by {Y} for each killed this way."
    m = RegExp(r'^As you play me, you may kill any number of friendly units as an additional cost\. Reduce my cost by \{([A-Z])\} for each killed this way\.$').firstMatch(t);
    if (m != null && _isUnit) {
      final d = Domain.byName(m[1]!);
      return d == null ? null : [Static(line, AddCost(XPay.kill, anyNumber: true, discountEach: d))];
    }
    // "You may kill a friendly unit as an additional cost to play me. If you do, I cost {1} less
    // for each Energy it costs and {Y} less for each Power it costs."
    m = RegExp(r'^You may kill a friendly unit as an additional cost to play me\. If you do, I cost \{1\} less for each Energy it costs and \{([A-Z])\} less for each Power it costs\.$').firstMatch(t);
    if (m != null && _isUnit) {
      final d = Domain.byName(m[1]!);
      return d == null ? null : [Static(line, AddCost(XPay.kill, discountByKilled: d))];
    }
    // "You may kill a friendly gear as an additional cost to play me."
    if (t == 'You may kill a friendly gear as an additional cost to play me.' && _isUnit) {
      return [Static(line, const AddCost(XPay.kill, filter: Filter(side: Side.friendly, gear: true)))];
    }
    // "You may exhaust your legend as an additional cost to play me."
    if (t == 'You may exhaust your legend as an additional cost to play me.' && _isUnit) return [Static(line, const AddCost(XPay.exhaustLegend))];
    // "As an additional cost to play me, kill a friendly unit." / "… kill a friendly [Mighty] unit."
    m = RegExp('^As an additional cost to play $self, kill a friendly (\\[Mighty\\] )?unit\\.\$').firstMatch(t);
    if (m != null) return [Static(line, AddCost(XPay.kill, optional: false, mighty: m[1] != null))];
    // "As an additional cost to play me, return a friendly gear to its owner's hand."
    if (t == "As an additional cost to play me, return a friendly gear to its owner's hand." && _isUnit) {
      return [Static(line, const AddCost(XPay.returnGear, optional: false, filter: Filter(side: Side.friendly, gear: true)))];
    }
    // "As an additional cost to play this, you may exhaust a friendly unit. If you do, draw 2.
    // Otherwise, draw 1." (the rest is the spell's instructions)
    m = RegExp(r'^As an additional cost to play this, you may exhaust a friendly unit\. If you do, (.+?)\. Otherwise, (.+)$').firstMatch(t);
    if (m != null && _isSpell) {
      final a = _effects(_Line._cap(m[1]!));
      final b = _effects(_Line._cap(m[2]!));
      if (a == null || b == null) return null;
      return [Static(line, const AddCost(XPay.exhaustUnit)), SpellBody(line, [IfElse(const PaidCost(), a, b)])];
    }
    return null;
  }

  /// Passive abilities about costs and playing cards.
  Passive? _xPassiveLine(String t) {
    final perm = card.isPermanent || card.type == CardType.legend;
    // Discounts on the card itself (CR 356.4).
    final selfWord = _isSpell ? '(?:This|I)' : 'I';
    var m = RegExp('^$selfWord costs? \\{(\\d+)\\} less to play from anywhere other than your hand\\.\$').firstMatch(t);
    if (m != null && _playable) return SelfCost(energy: int.parse(m[1]!), elsewhere: true);
    m = RegExp(r"^I cost \{(\d+)\} less for each card you've played this turn, to a minimum of \{(\d+)\}\.$").firstMatch(t);
    if (m != null && _playable) return SelfCost(energy: int.parse(m[1]!), per: XPer.cardsPlayedThisTurn, min: int.parse(m[2]!));
    m = RegExp(r'^I cost ((?:\{[0-9A-Z]+\})+) less for each (.+)\.$').firstMatch(t);
    if (m != null && _playable) {
      final r = _res(m[1]!);
      final per = switch (m[2]!) {
        'of your [Mighty] units' => XPer.mightyUnits,
        'gear you control' => XPer.gearYouControl,
        'card in your trash' => XPer.cardsInTrash,
        'card with my name in your trash' => XPer.sameNameInTrash,
        'point you scored from holding this turn' => XPer.holdPointsThisTurn,
        _ => null,
      };
      if (r == null || per == null) return null;
      return SelfCost(energy: r.$1, power: r.$2, per: per);
    }
    m = RegExp(r'^(?:I|This) costs? ((?:\{[0-9A-Z]+\})+) less if (.+)\.$').firstMatch(t);
    if (m != null && _playable) {
      final r = _res(m[1]!);
      if (r == null) return null;
      final tags = RegExp('^you choose $_tagList\$').firstMatch(m[2]!);
      if (tags != null) return _isSpell ? SelfCost(energy: r.$1, power: r.$2, choosesTags: _tagsOf(tags[1]!)) : null;
      final c = _xCond(m[2]!);
      return c == null ? null : SelfCost(energy: r.$1, power: r.$2, cond: c);
    }
    m = RegExp(r'^If (.+), (?:this|I) costs? ((?:\{[0-9A-Z]+\})+) less( and enters? ready)?\.$').firstMatch(t);
    if (m != null && _playable) {
      final r = _res(m[2]!);
      final c = _xCond(m[1]!);
      if (r == null || c == null || (m[3] != null && !_isUnit)) return null;
      return SelfCost(energy: r.$1, power: r.$2, cond: c, entersReady: m[3] != null);
    }
    if (_isSpell && t == "This spell's Energy cost is reduced by the highest Might among units you control.") return const SelfCost(energy: 1, per: XPer.highestMight);
    m = RegExp(r'^Reduce my cost by \{(\d+)\} for each of the following tags among your units - (.+)\.$').firstMatch(t);
    if (m != null && _playable) return SelfCost(energy: int.parse(m[1]!), per: XPer.tagKinds, perTags: _tagsOf(m[2]!.replaceAll(', and ', ', ')));
    if (_isSpell && t == "Ignore [Deflect] while paying this spell's cost.") return const IgnoreDeflect();
    if (perm && t == "While I'm at a battlefield, the Energy costs for spells you play is reduced by {1}, to a minimum of {1}.") return const CostMod(XWho.spellsWhileAtBattlefield, energy: 1, min: 1);
    m = RegExp(r"^Your ([A-Z][a-z]+)s' Energy costs are reduced by \{(\d+)\}, to a minimum of \{(\d+)\}\.$").firstMatch(t);
    if (m != null && perm) return CostMod(XWho.yourTagged, energy: int.parse(m[2]!), min: int.parse(m[3]!), tag: m[1]);
    m = RegExp(r'^When you look at cards from the top of your deck and see me, you may play me for ((?:\{[0-9A-Z]+\})+)\.$').firstMatch(t);
    if (m != null && _playable) {
      final r = _res(m[1]!);
      return r == null ? null : SeeMePlay(r.$1, r.$2);
    }
    // Alternative costs (CR 356.1.a): "If you've spent {4} or more to play a spell this turn, you
    // may play me for {B}." / "[Legion][>] You may play me from your trash for {3}{R}."
    m = RegExp(r'^If (.+), you may play me for ((?:\{[0-9A-Z]+\})+)\.$').firstMatch(t);
    if (m != null && _playable) {
      final r = _res(m[2]!);
      final c = _xCond(m[1]!);
      return r == null || c == null ? null : AltCost(r.$1, r.$2, cond: c);
    }
    m = RegExp(r'^(\[Legion\]\[>\] )?You may play me from your trash for ((?:\{[0-9A-Z]+\})+)\.$').firstMatch(t);
    if (m != null && _playable) {
      final r = _res(m[2]!);
      return r == null ? null : AltCost(r.$1, r.$2, fromTrash: true, legion: m[1] != null);
    }
    // Cost changes from other permanents, legends and battlefields.
    if (_isBattlefield) {
      if (t == 'Players ignore [Deflect] while paying for spells and abilities choosing something here.') return const IgnoreDeflect(here: true);
      if (t == 'While you control this battlefield, the first friendly non-token gear played each turn costs {1} less.') return const CostMod(XWho.firstGear, energy: 1, whileControlled: true);
      if (t == 'While you control this battlefield, the first friendly gear activated ability played each turn costs {1} less.') return const CostMod(XWho.firstGearAbility, energy: 1, whileControlled: true);
      if (t == 'While you control this battlefield, friendly [Repeat] costs cost {1} less.') return const CostMod(XWho.repeatCosts, energy: 1, whileControlled: true);
      if (t == 'During showdowns here, cards with [Reaction] cost {A} more to play.') return const CostMod(XWho.reactionsInShowdownHere, power: [null], more: true);
      if (t == 'Each spell that chooses one or more units here that are friendly to it costs {A} less.') return const CostMod(XWho.spellsChoosingFriendlyHere, power: [null]);
      m = RegExp(r'^Any player may pay ((?:\{[0-9A-Z]+\})+) as an additional cost to play an? ([A-Z][a-z]+)\. If they do, they play it to this battlefield\.$').firstMatch(t);
      if (m != null) {
        final r = _res(m[1]!);
        return r == null || r.$1 != 0 ? null : RoostCost(m[2]!, r.$2);
      }
      return null;
    }
    if (_isUnit && t == 'Your spells that choose me cost {1} or {A} less.') return const CostMod(XWho.spellsChoosingMe, energy: 1, orPower: true);
    if (_isUnit && t == "While I'm in combat, friendly spells cost {1}{A} less to a minimum of {1}, and enemy spells cost {1}{A} more.") {
      return const CostMod(XWho.friendlySpellsInCombat, energy: 1, power: [null], min: 1);
    }
    if (perm && t == 'Optional additional costs you pay cost {1} or {A} less.') return const CostMod(XWho.optionalCosts, energy: 1, orPower: true);
    if (_isUnit && t == 'Friendly units played from anywhere other than a player\'s hand have [Accelerate].') return const ElsewhereAccelerate();
    // Might.
    if (_isUnit && t == 'My Might is increased by the number of cards in your trash.') return const XMight(perTrashCard: true);
    m = RegExp(r"^If you've spent \{(\d+)\} or more to play a spell this turn, I have \+(\d+) \{M\}\.$").firstMatch(t);
    if (m != null && _isUnit) return XMight(n: int.parse(m[2]!), cond: SpentOnSpell(int.parse(m[1]!)));
    m = RegExp(r"^As I'm revealed from your deck, \[Add\] \{(\d+)\}\.$").firstMatch(t);
    if (m != null && _playable) return RevealAdd(int.parse(m[1]!));
    // "Your Mechs each have [Assault]."
    m = RegExp(r'^Your ([A-Z][a-z]+)s each have \[([A-Za-z]+)(?: (\d+))?\]\.$').firstMatch(t);
    if (m != null && perm) {
      final kw = _kwNames[m[2]!.toLowerCase()];
      if (kw == null || !const {Kw.shield, Kw.assault, Kw.tank, Kw.ganking, Kw.deflect}.contains(kw)) return null;
      return KwAnthem(kw, int.tryParse(m[3] ?? '') ?? 1, Filter(side: Side.friendly, tag: m[1]));
    }
    return null;
  }

  /// Triggered abilities with conditions or events of their own.
  List<Ability>? _xTriggerLine(String t, String line) {
    final perm = card.isPermanent || card.type == CardType.legend;
    Triggered? trig(XWhen on, String body) {
      _eventUnit = false;
      _eventBf = false;
      final e = _effects(_Line._cap(body));
      return e == null ? null : Triggered(line, on, e);
    }

    // "When you play me, if you paid the additional cost, …" (CR 383.2.a.1).
    var m = RegExp(r'^When you play me, if you paid the additional cost, (.+)$').firstMatch(t);
    if (m != null && _isUnit) {
      final a = trig(const XWhen(On.played, cond: PaidCost()), m[1]!);
      return a == null ? null : [a];
    }
    m = RegExp(r'^When I become ready, (.+)$').firstMatch(t);
    if (m != null && _isUnit) {
      final a = trig(const XWhen(On.costsExt, kind: XOn.becomeReady), m[1]!);
      return a == null ? null : [a];
    }
    m = RegExp(r'^When you play a spell that costs \{(\d+)\} or more, (.+)$').firstMatch(t);
    if (m != null && perm) {
      final a = trig(XWhen(On.costsExt, kind: XOn.playSpell, n: int.parse(m[1]!)), m[2]!);
      return a == null ? null : [a];
    }
    m = RegExp(r'^When you play a card with Power cost ((?:\{A\})+) or more, (.+)$').firstMatch(t);
    if (m != null && perm) {
      final a = trig(XWhen(On.costsExt, kind: XOn.playCardPower, n: m[1]!.length ~/ 3), m[2]!);
      return a == null ? null : [a];
    }
    m = RegExp(r'^When you play a unit, gear, or activated ability with Energy cost \{(\d+)\} or more, (.+)$').firstMatch(t);
    if (m != null && perm) {
      final a = trig(XWhen(On.costsExt, kind: XOn.playBig, n: int.parse(m[1]!)), m[2]!);
      return a == null ? null : [a];
    }
    m = RegExp(r"^When you play your first card each turn, if I'm at a battlefield, (.+)$").firstMatch(t);
    if (m != null && _isUnit) {
      final a = trig(const XWhen(On.costsExt, kind: XOn.firstCard, cond: MeAtBattlefield()), m[1]!);
      return a == null ? null : [a];
    }
    // Triggers that work from the trash.
    m = RegExp(r'^When you kill a unit with a spell, you may pay ((?:\{[0-9A-Z]+\})+) to play me from your trash\.$').firstMatch(t);
    if (m != null && _isUnit) {
      final r = _res(m[1]!);
      return r == null ? null : [Triggered(line, const XWhen(On.costsExt, kind: XOn.killWithSpell, fromTrash: true), [May([PayToPlayMe(r.$1, r.$2)])])];
    }
    m = RegExp(r'^When you conquer, you may discard (\d+) to return this from your trash to your hand\.$').firstMatch(t);
    if (m != null && _playable) {
      return [Triggered(line, const XWhen(On.youConquer, fromTrash: true), [May([ReturnMeFromTrash(discard: int.parse(m[1]!))])])];
    }
    // "When I attack while your units have all 4 tags, …" (Bird, Cat, Dog and Poro).
    m = RegExp(r'^When I attack while your units have all 4 tags, (.+)$').firstMatch(t);
    if (m != null && _isUnit && card.text.contains('Bird, Cat, Dog, and Poro')) {
      final a = trig(const XWhen(On.attack, cond: AllTags(['Bird', 'Cat', 'Dog', 'Poro'])), m[1]!);
      return a == null ? null : [a];
    }
    // "At the start of your Beginning Phase, …" (Dr. Mundo, Expert; the same moment as "At start
    // of your Beginning Phase").
    m = RegExp(r'^At the start of your Beginning Phase, (.+)$').firstMatch(t);
    if (m != null && perm) {
      final a = trig(const XWhen(On.startOfTurn), m[1]!);
      return a == null ? null : [a];
    }
    return null;
  }

  /// Conditions of cost changes and alternative costs.
  Cond? _xCond(String c) => switch (c) {
        "an opponent's score is within 3 points of the Victory Score" => const OpponentNearWin(3),
        'you control a battlefield with exactly two units there' => const ControlBfWithUnits(2),
        'an opponent controls a stunned unit' => const OpponentStunned(),
        'an enemy unit has died this turn' => const EnemyDiedThisTurn(),
        _ => switch (RegExp(r"^you(?:'ve| have) spent \{(\d+)\} or more to play a spell this turn$").firstMatch(c)) {
            final m? => SpentOnSpell(int.parse(m[1]!)),
            _ => switch (RegExp(r'^you control an? ([A-Z][a-z]+)$').firstMatch(c)) {
                final m? => YouControlTag(m[1]!),
                _ => null,
              },
          },
      };

  /// Costs of activated abilities: "Spend my buff", "Recycle 3 from your trash".
  XCostPart? _xCostPart(String part) {
    if (part == 'Spend my buff' && _isUnit) return const SpendMyBuff();
    final m = RegExp(r'^Recycle (a unit|\d+) from your trash$').firstMatch(part);
    if (m != null) return m[1] == 'a unit' ? const RecycleTrash(1, unit: true) : RecycleTrash(int.parse(m[1]!));
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Instructions spanning several sentences
  // -------------------------------------------------------------------------------------------

  List<Effect>? _xEffects(String text) {
    // "Choose one - • A • B" (CR 355.3).
    var m = RegExp(r"^Choose one( you haven't already chosen| you've not chosen this turn| to give me this turn)? - • (.+)$").firstMatch(text);
    if (m != null) {
      final kind = m[1] ?? '';
      final modes = <List<Effect>>[];
      for (final raw in m[2]!.split(' • ')) {
        final mt = raw.trim();
        if (kind == ' to give me this turn') {
          final k = RegExp(r'^\[([A-Za-z]+)(?: (\d+))?\]$').firstMatch(mt);
          final kw = k == null ? null : _kwNames[k[1]!.toLowerCase()];
          if (kw == null || !_isUnit || !const {Kw.assault, Kw.shield, Kw.tank, Kw.ganking, Kw.deflect, Kw.backline}.contains(kw)) return null;
          modes.add([GiveKw(kw, int.tryParse(k![2] ?? '') ?? 1, const Me())]);
          continue;
        }
        final e = _effects(_Line._cap(mt));
        if (e == null) return null;
        modes.add(e);
      }
      if (modes.length < 2) return null;
      // Counter keeps its spell in slot 0; the mode's slot comes after it.
      if (_slotCounter[0] == 0 && modes.any((x) => x.any((e) => e is Counter))) _slotCounter[0] = 1;
      return [Modes(modes, slot: _slotCounter[0]++, distinct: kind == " you haven't already chosen", perTurn: kind == " you've not chosen this turn")];
    }
    if (text == "Choose up to 3 cards from opponents' trashes. Their owners recycle them.") return const [RecycleOpponentTrash(3)];
    m = RegExp(r'^Choose a unit\. Give it \+(\d+) \{M\} this turn for each of the following tags among your units - (.+)\.$').firstMatch(text);
    if (m != null) {
      final tg = Choose(const Filter(), slot: _slotCounter[0]++);
      return [MightPerTags(tg, int.parse(m[1]!), _tagsOf(m[2]!.replaceAll(', and ', ', ')))];
    }
    m = RegExp(r'^Look at the top (\d+) cards of your Main Deck\. You may banish a unit from among them, then play it, reducing its cost by \{(\d+)\}\. Recycle the remaining cards\.$').firstMatch(text);
    if (m != null) return [LookPlay(int.parse(m[1]!), const {CardType.unit}, reduceEnergy: int.parse(m[2]!))];
    m = RegExp(r'^Kill a friendly unit\. Look at the top (\d+) cards of your Main Deck\. You may banish a unit from among them that has Might up to (\d+) more than the killed unit and play it, ignoring its cost\. Then recycle the rest\.$').firstMatch(text);
    if (m != null) {
      final tg = _target('a friendly unit');
      return tg == null ? null : [LookPlay(int.parse(m[1]!), const {CardType.unit}, ignoreAll: true, kill: tg, mightPlus: int.parse(m[2]!))];
    }
    m = RegExp(r'^Reveal the top (\d+) cards of your Main Deck\. You may play one of them, reducing its cost by \{(\d+)\}\. Draw any you did not play this way\.$').firstMatch(text);
    if (m != null) return [RevealPlay(int.parse(m[1]!), int.parse(m[2]!))];
    m = RegExp(r'^Each player looks at the top (\d+) cards of their Main Deck, chooses one, then recycles the rest\. Starting with the next player, each player plays those cards, ignoring Energy costs\.$').firstMatch(text);
    if (m != null) return [EachPlayerLookPlay(int.parse(m[1]!))];
    // "Choose a spell with Energy cost no more than {4}. You may pay {A}. If you do, gain control of
    // it and you may make new choices for it. Otherwise, counter it." (CR 750)
    m = RegExp(r'^Choose a spell with Energy cost no more than \{(\d+)\}\. You may pay ((?:\{[0-9A-Z]+\})+)\. If you do, gain control of it and you may make new choices for it\. Otherwise, counter it\.$').firstMatch(text);
    if (m != null && _isSpell) {
      final r = _res(m[2]!);
      return r == null ? null : [StealOrCounter(int.parse(m[1]!), r.$1, r.$2)];
    }
    // "Deal 3 to a unit at a battlefield. If you paid the additional cost, deal 5 to it instead."
    m = RegExp(r'^Deal (\d+) to (.+)\. If you paid the additional cost, deal (\d+) to it instead\.$').firstMatch(text);
    if (m != null && _isSpell) {
      final tg = _target(m[2]!);
      if (tg is! Choose) return null;
      final it = Chosen(tg.slot);
      return [IfElse(const PaidCost(), [Deal(N(int.parse(m[3]!)), tg)], [Deal(N(int.parse(m[1]!)), it)])];
    }
    // "Choose a friendly unit and an enemy unit. If you paid the additional cost, give the
    // friendly unit +2 {M} this turn. They deal damage equal to their Mights to each other."
    m = RegExp(r'^Choose a friendly unit and an enemy unit\.(?: If you paid the additional cost, give the friendly unit \+(\d+) \{M\} this turn\.)? They deal damage equal to their Mights to each other\.$').firstMatch(text);
    if (m != null && _isSpell) {
      final a = Choose(const Filter(side: Side.friendly), slot: _slotCounter[0]++);
      final b = Choose(const Filter(side: Side.enemy), slot: _slotCounter[0]++);
      return [
        if (m[1] != null) If(const PaidCost(), [GiveMight(int.parse(m[1]!), Chosen(a.slot))]),
        Fight(a, b),
      ];
    }
    if (text == 'Choose two units. They deal damage equal to their Mights to each other.' && _isSpell) {
      final a = Choose(const Filter(), slot: _slotCounter[0]++);
      final b = Choose(const Filter(), slot: _slotCounter[0]++);
      return [Fight(a, b)];
    }
    // "Kill a unit at a battlefield. Then, if it had 3 {M} or less, you may play this from your
    // trash for {A}."
    m = RegExp(r'^Kill (.+)\. Then, if it had (\d+) \{M\} or less, you may play this from your trash for ((?:\{[0-9A-Z]+\})+)\.$').firstMatch(text);
    if (m != null && _isSpell) {
      final tg = _target(m[1]!);
      final r = _res(m[3]!);
      if (tg is! Choose || r == null || r.$1 != 0) return null;
      return [KillThenReplay(tg, int.parse(m[2]!), r.$2)];
    }
    // "Look at the top 4 cards of your Main Deck. You may reveal a spell with Energy cost {4} or
    // more from among them and draw it. Recycle the rest."
    m = RegExp(r'^Look at the top (\d+) cards of your Main Deck\. You may reveal an? (spell|unit|gear)(?: with Energy cost \{(\d+)\} or more)? from among them and draw it\. Recycle the rest\.$').firstMatch(text);
    if (m != null) {
      final type = switch (m[2]) { 'spell' => CardType.spell, 'unit' => CardType.unit, _ => CardType.gear };
      return [LookDraw(int.parse(m[1]!), type, minEnergy: int.tryParse(m[3] ?? '') ?? 0)];
    }
    if (text == 'Each opponent reveals the top card of their Main Deck. Choose one and banish it, then play it, ignoring its cost. Then recycle the rest.' && _isSpell) return const [PlayOpponentsTop()];
    // "You may play a spell from your trash with Energy cost no more than {3}, ignoring its Energy
    // cost. Recycle that spell after you play it." / "… with Energy cost less than your points
    // without paying its Energy cost. Then recycle it."
    m = RegExp(r'^You may play a spell from your trash with Energy cost (?:no more than \{(\d+)\}, ignoring its Energy cost\. Recycle that spell after you play it|less than your points without paying its Energy cost\. Then recycle it)\.$').firstMatch(text);
    if (m != null) {
      return [
        May([PlayFrom(XZone.trash, types: const {CardType.spell}, maxEnergy: int.tryParse(m[1] ?? ''), lessThanPoints: m[1] == null, ignoreEnergy: true, recycleAfter: true)]),
      ];
    }
    // "You may kill a gear with Energy cost no more than {1}. If you do, play a Gold gear token
    // exhausted."
    m = RegExp(r'^You may kill a gear with Energy cost no more than \{(\d+)\}\. If you do, (.+)$').firstMatch(text);
    if (m != null) {
      final slot = _slotCounter[0]++;
      final then = _effects(_Line._cap(m[2]!));
      return then == null ? null : [May([KillGearByCost(slot, max: int.parse(m[1]!), then: then)])];
    }
    // "You may kill a friendly gear. If you do, you may play a gear with Energy cost no more than
    // {7} from hand this turn, ignoring its Energy cost."
    m = RegExp(r'^You may kill a friendly gear\. If you do, you may play a gear with Energy cost no more than \{(\d+)\} from hand this turn, ignoring its Energy cost\.$').firstMatch(text);
    if (m != null) {
      final tg = _target('a friendly gear');
      if (tg == null) return null;
      return [May([DoThen(Kill(tg), [TurnFx(XTurnFx.freeGear, energy: int.parse(m[1]!))])])];
    }
    // "You may banish a unit from your trash. If you do, give me [Assault 4] this turn."
    m = RegExp(r'^You may banish a (unit|card) from (your|any) trash\. If you do, (.+)$').firstMatch(text);
    if (m != null) {
      final then = _effects(_Line._cap(m[3]!));
      return then == null ? null : [May([BanishTrashThen(then, unit: m[1] == 'unit', anyTrash: m[2] == 'any')])];
    }
    // "You may recycle another friendly unit to play a Mech from your trash. Reduce its Energy
    // cost by the Might of the unit you recycled."
    m = RegExp(r'^You may recycle another friendly unit to play an? ([A-Z][a-z]+) from your trash\. Reduce its Energy cost by the Might of the unit you recycled\.$').firstMatch(text);
    if (m != null && _isUnit) return [May([RecycleToPlay(_slotCounter[0]++, m[1]!)])];
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Single sentences
  // -------------------------------------------------------------------------------------------

  List<Effect>? _xSentence(String s) {
    // "Give an enemy Body unit -5 {M} this turn": a unit of a domain.
    var m = RegExp(r'^Give an? (friendly |enemy )?(Fury|Calm|Mind|Body|Chaos|Order) unit ([+-])(\d+) \{M\} this turn$').firstMatch(s);
    if (m != null) {
      final side = m[1] == 'friendly ' ? Side.friendly : (m[1] == 'enemy ' ? Side.enemy : Side.any);
      final n = int.parse(m[4]!) * (m[3] == '-' ? -1 : 1);
      return [GiveMight(n, Choose(Filter(side: side, tag: 'domain:${m[2]}'), slot: _slotCounter[0]++))];
    }
    if (s == 'Give the next spell you play this turn [Repeat] equal to its cost' || s == 'Give your next spell this turn [Repeat] equal to its base cost') return const [TurnFx(XTurnFx.nextSpellRepeat)];
    m = RegExp(r'^Each player (draws|discards) (\d+)$').firstMatch(s);
    if (m != null) return [m[1] == 'draws' ? EachPlayer(draw: int.parse(m[2]!)) : EachPlayer(discard: int.parse(m[2]!))];
    m = RegExp(r'^Give your other units \+(\d+) \{M\} this turn$').firstMatch(s);
    if (m != null && _isUnit) return [GiveMight(int.parse(m[1]!), const Each(Filter(side: Side.friendly, other: true)))];
    m = RegExp(r'^Play (four|three|two|a|an|\d+) 1 \{M\} Bird unit tokens? with \[Deflect\]$').firstMatch(s);
    if (m != null) {
      final n = _num(m[1]!) ?? (m[1] == 'four' ? 4 : null);
      return n == null ? null : [PlayToken('Bird', n)];
    }
    if (s == 'Play a 0 {M} Shadow Clone unit token' && _isUnit) return const [PlayToken('Shadow Clone', 1)];
    // Playing cards from the trash or hand as an effect (CR 420.3).
    if (s == 'Play a unit from your trash, ignoring its Energy cost') return const [PlayFrom(XZone.trash, types: {CardType.unit}, ignoreEnergy: true)];
    if (s == 'Play a unit from your trash that costs no more Energy and no more Power than the killed unit, ignoring its cost' && _isSpell) {
      return const [PlayFrom(XZone.trash, types: {CardType.unit}, maxOfKilled: true, ignoreAll: true)];
    }
    m = RegExp(r'^Play a unit (?:with cost|costing) no more than \{(\d+)\} and no more than ((?:\{A\})+) from your trash, ignoring its cost$').firstMatch(s);
    if (m != null) {
      // A spell whose cost depends on what it plays chooses it as it's played (CR 355.5, 356.4).
      final choose = _isSpell && card.text.contains('if you choose');
      return [PlayFrom(XZone.trash, types: const {CardType.unit}, maxEnergy: int.parse(m[1]!), maxPower: m[2]!.length ~/ 3, ignoreAll: true, slot: choose ? _slotCounter[0]++ : -1)];
    }
    if (s == 'Play a unit from your hand to your base, ignoring its Energy cost') return const [PlayFrom(XZone.hand, types: {CardType.unit}, ignoreEnergy: true, toBase: true)];
    if (s == 'Play a unit banished with this' && card.type == CardType.gear) return const [PlayFrom(XZone.bannedByMe, types: {CardType.unit})];
    if (s == 'Banish all units from your trash' && card.type == CardType.gear) return const [BanishTrashUnits()];
    m = RegExp(r'^Counter a spell that costs no more than \{(\d+)\} and no more than ((?:\{A\})+)$').firstMatch(s);
    if (m != null && _isSpell) return [CounterByCost(int.parse(m[1]!), m[2]!.length ~/ 3)];
    m = RegExp(r'^Recycle (\d+) from your trash$').firstMatch(s);
    if (m != null) return [RecycleYourTrash(int.parse(m[1]!))];
    if (s == 'The defender must kill one of their units here' && _isUnit) return const [DefenderKills()];
    m = RegExp(r'^Kill a gear with Energy cost no more than (my Might|\{(\d+)\})$').firstMatch(s);
    if (m != null) {
      if (m[2] == null && !_isUnit) return null;
      return [KillGearByCost(_slotCounter[0]++, max: int.tryParse(m[2] ?? '') ?? 0, myMight: m[2] == null)];
    }
    // Effects lasting the turn.
    m = RegExp(r'^The next spell you play this turn costs \{(\d+)\} less$').firstMatch(s);
    if (m != null) return [TurnFx(XTurnFx.nextSpellLess, energy: int.parse(m[1]!))];
    m = RegExp(r'^Your next card costs \{(\d+)\}((?:\{A\})*) less$').firstMatch(s);
    if (m != null) return [TurnFx(XTurnFx.nextCardLess, energy: int.parse(m[1]!), power: m[2]!.length ~/ 3)];
    m = RegExp(r'^Your non-token units cost \{(\d+)\} more to play this turn$').firstMatch(s);
    if (m != null) return [TurnFx(XTurnFx.unitsMore, energy: int.parse(m[1]!))];
    if (s == 'The next time you play a unit this turn, ready it and [Buff] it') return const [TurnFx(XTurnFx.nextUnitReadyBuff)];
    // Costs within instructions (CR 204.3).
    m = RegExp(r'^Banish a (card|unit) from (any|your) trash to (.+)$').firstMatch(s);
    if (m != null) {
      final then = _sentence(_Line._cap(m[3]!));
      return then == null ? null : [BanishTrashThen(then, unit: m[1] == 'unit', anyTrash: m[2] == 'any')];
    }
    m = RegExp(r'^Exhaust me to (.+)$').firstMatch(s);
    if (m != null && card.type == CardType.legend) {
      final rest = m[1]!;
      final r = RegExp(r'^ready up to (\d+) runes$').firstMatch(rest);
      if (r == null) return null;
      return [ExhaustMeThen([ReadyRunes(int.parse(r[1]!))])];
    }
    if (s == 'Move any number of your units to an open battlefield' && _isUnit) return const [MoveToOpenBf()];
    m = RegExp(r'^This ability costs \{(\d+)\} less for each friendly unit with \[Temporary\]$').firstMatch(s);
    if (m != null && !_isSpell) return [AbilityCostLess(int.parse(m[1]!), XPer.friendlyTemporaryUnits)];
    return null;
  }
}
