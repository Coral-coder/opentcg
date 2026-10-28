part of 'parser.dart';

// Equipment (CR 150, 716–725, 818 Equip, 819 Quick-Draw, 821 Weaponmaster) and the cards built
// around it: their rules text, and the Effect Text (CR 136) an Equipment gives its unit.

/// One line, read by the family grammars (this file's included) and the core first, and by the
/// general grammar only if they can't (parser/general.dart).
List<Ability>? _eqParseLine(RCard c, List<int> slots, String line, {bool effectText = false}) {
  final trace = RiftboundParser.trace;
  final slot = slots[0];
  final traced = trace?.length ?? 0;
  final a = _EqLine(c, slots, effectText: effectText, general: false).parse(line);
  if (a != null) return a;
  slots[0] = slot;
  trace?.removeRange(traced, trace.length);
  return _EqLine(c, slots, effectText: effectText).parse(line);
}

/// The Effect Text of an Equipment, read as abilities of the unit it's attached to ("I", "me"),
/// with "this" meaning the Equipment (CR 136.2.c–d). Lines it can't read go to [unsupported].
List<Ability> _eqEffectAbilities(RCard c, List<String> unsupported) {
  if (c.effect.isEmpty) return const [];
  final asUnit = RCard(name: c.name, type: CardType.unit, domains: c.domains, might: 0, text: c.effect);
  final slots = [0];
  final out = <Ability>[];
  for (final line in c.effect.split('\n')) {
    if (line.trim().isEmpty) continue;
    final a = _eqParseLine(asUnit, slots, line.trim(), effectText: true);
    if (a == null) {
      unsupported.add('(Effect Text) ${line.trim()}');
    } else {
      out.addAll(a);
    }
  }
  return out;
}

/// Abilities a card gives other objects, which game/equip.dart puts on the chain by index
/// (ParsedCard.extra): its Effect Text, then abilities its rules text grants.
List<Ability> _eqExtra(RCard c, List<Ability> abilities, List<String> unsupported) {
  final out = [..._eqEffectAbilities(c, unsupported)];
  void walk(List<Effect> es) {
    for (final e in es) {
      switch (e) {
        case EqGrantThisTurn(:final ability):
          out.add(ability);
        case May(:final effects) || If(:final effects):
          walk(effects);
        default:
          break;
      }
    }
  }

  for (final a in abilities) {
    switch (a) {
      case Static(passive: EqGrantLegends(:final ability)):
        out.add(ability);
      case Static(passive: EqGrantWeaponmaster(:final ability)):
        out.add(ability);
      case Static(passive: EqGrantQuickDraw(:final ability)):
        out.add(ability);
      case SpellBody(:final effects) || Triggered(:final effects) || Activated(:final effects):
        walk(effects);
      default:
        break;
    }
  }
  return out;
}

bool _isEquipment(RCard c) => c.type == CardType.gear && c.hasTag('Equipment');

class _EqLine extends _Line {
  _EqLine(super.card, super._slotCounter, {this.effectText = false, super.general});

  /// Reading an Equipment's Effect Text: "this" is the Equipment.
  final bool effectText;

  /// The unit and Equipment slots of "Choose a unit and an Equipment …" and "Move a friendly
  /// unit." ("that unit", "that Equipment").
  int _unitSlot = -1, _equipSlot = -1;

  @override
  List<Ability>? parse(String line) {
    var t = line;
    // "Equip {O}" is printed without its brackets on a few cards.
    if (t.startsWith('Equip ') || t.startsWith('Equip -')) t = '[Equip]${t.substring(5)}';
    switch (t) {
      case '[Weaponmaster]' when card.type == CardType.unit:
        return [EqWeaponmaster(line)];
      case '[Quick-Draw]' when _isEquipment(card):
        return [EqQuickDraw(line)];
    }
    var m = RegExp(r'^\[Equip\](?: -)? (.+?)(\. This ability.s Energy cost is reduced by the Might of the unit you choose\.)?$').firstMatch(t);
    if (m != null) {
      if (!_isEquipment(card)) return null;
      final cost = _cost(m[1]!);
      if (cost == null) return null;
      final e = cost is EqCost ? cost : EqCost(energy: cost.energy, power: cost.power, exhaust: cost.exhaust, extra: cost.extra);
      if (e.exhaust || e.banishMe || cost.killMe) return null;
      return [EqEquip(line, m[2] == null ? e : EqCost(energy: e.energy, power: e.power, extra: e.extra, lessByTargetMight: true))];
    }
    // Hunt (CR 823): "When I conquer or hold, my controller gains N XP".
    m = RegExp(r'^\[Hunt(?: (\d+))?\]$').firstMatch(t);
    if (m != null && effectText) {
      final n = int.tryParse(m[1] ?? '') ?? 1;
      return [Triggered(line, const When(On.conquer), [GainXp(N(n))]), Triggered(line, const When(On.hold), [GainXp(N(n))])];
    }
    // Level (CR 824): "While you have N or more XP, …".
    m = RegExp(r'^\[Level (\d+)\]\[>\] I have an additional \+(\d+) \{M\}\.$').firstMatch(t);
    if (m != null && effectText) return [Static(line, EqMightIf(int.parse(m[2]!), EqLevel(int.parse(m[1]!))))];
    // "When I conquer or hold, …": one ability, two trigger conditions.
    m = RegExp(r'^When I conquer or hold, (.+)$').firstMatch(t);
    if (m != null && card.type == CardType.unit) {
      final e = _effects(_Line._cap(m[1]!));
      return e == null ? null : [Triggered(line, const When(On.conquer), e), Triggered(line, const When(On.hold), e)];
    }
    return super.parse(t == line ? line : t);
  }

  @override
  Ability? _ability(String t, String line) {
    final unit = card.type == CardType.unit;
    final lp = card.type == CardType.legend || card.isPermanent;
    var m = RegExp(r'^The first time I conquer each turn, (.+)$').firstMatch(t);
    if (m != null && unit) {
      final e = _effects(_Line._cap(m[1]!));
      return e == null ? null : Triggered(line, const EqWhen(EqEvent.firstConquer), e);
    }
    m = RegExp(r'^When I conquer an open battlefield, (.+)$').firstMatch(t);
    if (m != null && unit) {
      final e = _effects(_Line._cap(m[1]!));
      return e == null ? null : Triggered(line, const EqWhen(EqEvent.conquerOpen), e);
    }
    m = RegExp(r'^When you attach an Equipment to me, (.+)$').firstMatch(t);
    if (m != null && unit) {
      final body = m[1]!;
      // Aphelios: the same as "Choose one you've not chosen this turn" (CR 355.3).
      final mm = RegExp(r"^choose one that hasn't been chosen this turn - (• .+)$").firstMatch(body);
      if (mm != null) {
        final e = _effects("Choose one you've not chosen this turn - ${mm[1]}");
        return e == null ? null : Triggered(line, const EqWhen(EqEvent.attachedToMe), e);
      }
      final e = _effects(_Line._cap(body));
      return e == null ? null : Triggered(line, const EqWhen(EqEvent.attachedToMe), e);
    }
    // "{1}, {E}: … Use only if you've played an Equipment this turn."
    const onlyIf = " Use only if you've played an Equipment this turn.";
    if (t.endsWith(onlyIf)) {
      final a = super._ability(t.substring(0, t.length - onlyIf.length), line);
      if (a is! Activated) return null;
      return EqActivated(line, a.cost, a.effects, timing: a.timing, oncePerTurn: a.oncePerTurn, legion: a.legion, onlyIfPlayedEquipment: true);
    }
    m = RegExp(r'^While you control this battlefield, friendly legends have "(.+)"\.?$').firstMatch(t);
    if (m != null && _isBattlefield) {
      final legend = RCard(name: card.name, type: CardType.legend, domains: card.domains, text: m[1]!);
      final a = _eqParseLine(legend, [0], m[1]!);
      if (a == null || a.length != 1 || a.first is! Activated) return null;
      return Static(line, EqGrantLegends(a.first as Activated));
    }
    m = RegExp(r'^Your ([A-Z][a-z]+(?: [A-Z][a-z]+)?)s have \[Weaponmaster\]\.$').firstMatch(t);
    if (m != null && lp) return Static(line, EqGrantWeaponmaster(m[1]!, EqWeaponmaster(line)));
    if (t == 'Each Equipment in your hand has [Quick-Draw].' && lp) return Static(line, EqGrantQuickDraw(EqQuickDraw(line)));
    m = RegExp(r'^Your Equipment each give \[([A-Za-z]+)(?: (\d+))?\]\.$').firstMatch(t);
    if (m != null && lp) {
      final kw = _kwNames[m[1]!.toLowerCase()];
      if (kw == null || !const {Kw.assault, Kw.shield, Kw.tank, Kw.ganking, Kw.deflect}.contains(kw)) return null;
      return Static(line, EqEquipmentGive(kw, int.tryParse(m[2] ?? '') ?? 1));
    }
    m = RegExp(r'^I have \+(\d+) \{M\} for each friendly gear\.$').firstMatch(t);
    if (m != null && unit) return Static(line, EqMightPerGear(int.parse(m[1]!)));
    if (t == 'Each Equipment attached to me gives double its base Might bonus.' && unit) return Static(line, const EqDoubleBonus());
    if (_isEquipment(card)) {
      if (t == 'As this is attached to a unit, choose another friendly unit. The equipped unit becomes a copy of that unit for as long as this is attached to it.') return Static(line, const EqCopyAsAttached());
      if (t == "As this is attached to a unit, copy that unit's text to this Equipment's effect text for as long as this is attached to it.") return Static(line, const EqCopyTextAsAttached());
    }
    if (effectText) {
      m = RegExp(r"^I have \+(\d+) \{M\} while I'm at a battlefield with exactly one other unit you control\.$").firstMatch(t);
      if (m != null) return Static(line, EqMightIf(int.parse(m[1]!), const EqWithOneOther()));
      m = RegExp(r'^If this was attached to me this turn, I have an additional \+(\d+) \{M\}\.$').firstMatch(t);
      if (m != null) return Static(line, EqMightIf(int.parse(m[1]!), const EqAttachedThisTurn()));
      m = RegExp(r'^I am an? ([A-Z][a-z]+)\.$').firstMatch(t);
      if (m != null) return Static(line, EqHasTag(m[1]!));
      if (t == "I can't be moved by enemy spells and abilities.") return Static(line, const EqUnmovable());
      m = RegExp(r'^Your spells and abilities deal (\d+) Bonus Damage\.$').firstMatch(t);
      if (m != null) return Static(line, Restrict(RKind.bonusDamage, n: int.parse(m[1]!)));
      if (t == 'My hold effects are also conquer effects, and vice versa.') return Static(line, const EqHoldIsConquer());
      m = RegExp(r'^Your units here have \[([A-Za-z]+)(?: (\d+))?\]\.$').firstMatch(t);
      if (m != null) {
        final kw = _kwNames[m[1]!.toLowerCase()];
        if (kw == null || !const {Kw.shield, Kw.assault, Kw.tank, Kw.ganking, Kw.deflect}.contains(kw)) return null;
        return Static(line, KwAnthem(kw, int.tryParse(m[2] ?? '') ?? 1, const Filter(side: Side.friendly, where: Where.here)));
      }
      if (RegExp(r'^If I would die, kill .+ instead\. Heal me, exhaust me, and recall me\.$').hasMatch(t) && t.contains('kill ${card.name} instead')) return Static(line, const EqDieInstead());
    }
    final a = super._ability(t, line);
    // An activated ability with a cost the core can't pay ("Banish this").
    if (a is Activated && a is! EqActivated && a.cost is EqCost) return EqActivated(line, a.cost, a.effects, timing: a.timing, oncePerTurn: a.oncePerTurn, legion: a.legion);
    return a;
  }

  @override
  Cost? _cost(String s) {
    final extra = <CostPart>[];
    var banishMe = false;
    final rest = <String>[];
    for (final part in s.split(', ')) {
      final r = RegExp(r'^Recycle (\d+) cards? from your trash$').firstMatch(part);
      if (part == 'Kill a friendly unit') {
        extra.add(const KillFriendly());
      } else if (part == 'Banish this' && card.isPermanent) {
        banishMe = true;
      } else if (r != null) {
        extra.add(RecycleTrash(int.parse(r[1]!)));
      } else {
        rest.add(part);
      }
    }
    if (extra.isEmpty && !banishMe) return super._cost(s);
    final base = rest.isEmpty ? const Cost() : super._cost(rest.join(', '));
    if (base == null) return null;
    if (!banishMe) return Cost(energy: base.energy, power: base.power, exhaust: base.exhaust, killMe: base.killMe, extra: [...extra, ...base.extra]);
    if (base.killMe) return null;
    return EqCost(energy: base.energy, power: base.power, exhaust: base.exhaust, extra: [...extra, ...base.extra], banishMe: true);
  }

  @override
  List<Effect>? _effects(String text) {
    // Akshan, Mischievous.
    if (text == "If you paid the additional cost, move an enemy gear to your base. You control it until I leave the board. If it's an Equipment, attach it to me.") {
      if (card.type != CardType.unit) return null;
      final g = _target('an enemy gear');
      return g == null ? null : [If(const PaidExtra(), [EqTakeGear(g)])];
    }
    // Arise!
    final m = RegExp(r'^Play a (\d+) \{M\} (Sand Soldier|Recruit) unit token for each Equipment you control\. Then ready (two|one|\d+) of them\.?$').firstMatch(text);
    if (m != null) {
      const mights = {'Recruit': 1, 'Sand Soldier': 2};
      if (mights[m[2]!] != int.parse(m[1]!)) return null;
      return [EqTokensPerEquipment(m[2]!, _num(m[3]!) ?? 0)];
    }
    return super._effects(text);
  }

  @override
  List<Effect>? _sentence(String s0) {
    final s = s0;
    RegExpMatch? m;
    // "Here" is the battlefield it was hidden at: played from facedown, its choices are made there
    // (CR 811.1.d.3).
    if (s == 'Attach it to a unit you control here' && _isEquipment(card) && card.text.contains('from face down')) {
      final u = _target('a unit you control');
      return u == null ? null : [EqAttachMe(u)];
    }
    m = RegExp(r'^Play an Equipment with Energy cost no more than \{(\d+)\}, ignoring its cost, and attach it to me$').firstMatch(s);
    if (m != null && card.type == CardType.unit) return [EqPlayEquipmentFree(int.parse(m[1]!))];
    if (s == 'Banish me' && effectText) return [const EqBanishMe()];
    if (s == 'Play all units banished with this, ignoring their costs' && _isEquipment(card)) return [const EqPlayBanishedWith()];
    m = RegExp(r'^Unattach this and (.+)$').firstMatch(s);
    if (m != null && effectText) {
      final e = _sentence(_Line._cap(m[1]!));
      return e == null ? null : [const EqDetach(EqThis()), ...e];
    }
    if (s == 'Detach it') {
      final t = _target('it');
      return t == null ? null : [EqDetach(t)];
    }
    m = RegExp(r'^Detach an Equipment from (.+)$').firstMatch(s);
    if (m != null) {
      // "Choose an equipped friendly unit. It deals … to an enemy unit. Then detach an Equipment
      // from it.": "it" is the equipped unit.
      final t = m[1] == 'it' && _unitSlot >= 0 ? Chosen(_unitSlot) : _target(m[1]!);
      return t == null ? null : [EqDetachFrom(t)];
    }
    m = RegExp(r'^Deal (\d+) to (.+) for each Equipment attached to me$').firstMatch(s);
    if (m != null && card.type == CardType.unit) {
      final t = _target(m[2]!);
      return t == null ? null : [Deal(EqPerEquipment(int.parse(m[1]!)), t)];
    }
    // Strike Down: "Choose an equipped friendly unit. It deals damage equal to its Might to …".
    m = RegExp(r'^Choose an equipped (friendly|enemy) unit$').firstMatch(s);
    if (m != null) {
      final slot = _slotCounter[0]++;
      _unitSlot = slot;
      return [EqChooseOnly(EqChoose(Filter(side: m[1] == 'friendly' ? Side.friendly : Side.enemy), slot: slot, equipped: true))];
    }
    // Angle Shot: "Choose a unit and an Equipment with the same controller."
    if (s == 'Choose a unit and an Equipment with the same controller') {
      _unitSlot = _slotCounter[0]++;
      _equipSlot = _slotCounter[0]++;
      return [EqChooseOnly(Choose(const Filter(), slot: _unitSlot)), EqChooseOnly(EqChoose(const Filter(gear: true, tag: 'Equipment'), slot: _equipSlot, sameControllerAs: _unitSlot))];
    }
    if (s == 'Attach that Equipment to that unit or detach that Equipment from that unit' && _unitSlot >= 0) return [EqAttachOrDetach(Chosen(_unitSlot), Chosen(_equipSlot))];
    m = RegExp(r'^Attach an Equipment with the same controller to (it|that unit)$').firstMatch(s);
    if (m != null) {
      final u = _target(m[1]!);
      if (u is! Chosen) return null;
      if (_unitSlot < 0) _unitSlot = u.slot;
      final e = EqChoose(const Filter(gear: true, tag: 'Equipment'), slot: _slotCounter[0]++, upTo: true, sameControllerAs: u.slot);
      return [EqAttachTo(e, u)];
    }
    m = RegExp(r'^This turn, that unit has "(.+?)\.?"$').firstMatch(s);
    final that = m == null ? null : (_unitSlot >= 0 ? Chosen(_unitSlot) : _target('that unit'));
    if (m != null && that is Chosen) {
      final asUnit = RCard(name: card.name, type: CardType.unit, domains: card.domains, might: 0, text: m[1]!);
      final a = _eqParseLine(asUnit, [0], '${m[1]!}.');
      if (a == null || a.length != 1 || a.first is! Triggered) return null;
      return [EqGrantThisTurn(that, a.first as Triggered)];
    }
    if (s == 'Move me to its location and it to my original location' && card.type == CardType.unit) {
      final t = _target('it');
      return t == null ? null : [EqSwapWith(t)];
    }
    if (s == "If it's equipped, you may attach one of its Equipment to me" && card.type == CardType.unit) {
      final t = _target('it');
      return t == null ? null : [EqTakeOneEquipment(t)];
    }
    if (s == 'Move me to my base' && card.type == CardType.unit) return [const ToBase(Me())];
    // Jax, Grandmaster At Arms and Forge of the Fluft: "Attach a detached Equipment you control
    // to a unit you control."
    m = RegExp(r'^Attach an? (detached |attached )?Equipment you control to a unit you control$').firstMatch(s);
    if (m != null) {
      final e = EqChoose(const Filter(side: Side.friendly, gear: true, tag: 'Equipment'), slot: _slotCounter[0]++, attached: m[1] == null ? null : m[1] == 'attached ');
      final u = Choose(const Filter(side: Side.friendly), slot: _slotCounter[0]++);
      return [EqAttachTo(e, u)];
    }
    // Then the core and other families' forms, then this file's generic ones.
    final slot = _slotCounter[0];
    final core = super._sentence(s);
    if (core != null) return core;
    _slotCounter[0] = slot;
    return _eqSentenceLate(s);
  }

  /// Forms other families may also read: tried after them.
  List<Effect>? _eqSentenceLate(String s) {
    var m = RegExp(r'^Then (.+)$').firstMatch(s);
    if (m != null) return _sentence(_Line._cap(m[1]!));
    // Strike Down.
    // ("It" is the equipped unit chosen before; other cards are the general grammar's.)
    m = RegExp(r'^It deals damage equal to its Might to (.+)$').firstMatch(s);
    if (m != null && _unitSlot >= 0) {
      final v = _target(m[1]!);
      return v == null ? null : [EqUnitDeals(Chosen(_unitSlot), v)];
    }
    if (s == 'Ready your units') return [const Ready(Each(Filter(side: Side.friendly)))];
    if (s == 'Play a unit from your trash') return [const EqPlayFromTrash()];
    m = RegExp(r'^You may pay ((?:\{[0-9A-Z]+\})+) to (.+)$').firstMatch(s);
    if (m != null) {
      final cost = _cost(m[1]!);
      final e = cost == null || cost is EqCost ? null : _sentence(_Line._cap(m[2]!));
      return e == null ? null : [EqMayPay(cost!, e)];
    }
    // Relentless Pursuit.
    m = RegExp(r'^Move (a friendly unit|an enemy unit|a unit)$').firstMatch(s);
    if (m != null) {
      final t = _target(m[1]!);
      if (t is! Choose) return null;
      _unitSlot = t.slot;
      return [EqMove(t)];
    }
    // Azir, Ascendant.
    m = RegExp(r'^Choose (a unit you control|a friendly unit)$').firstMatch(s);
    if (m != null) {
      final t = _target(m[1]!);
      return t == null ? null : [EqChooseOnly(t)];
    }
    // Riven: "choose an enemy unit here".
    m = RegExp(r'^Choose (an enemy unit here|an enemy unit|a friendly unit here)$').firstMatch(s);
    if (m != null) {
      final t = _target(m[1]!);
      return t == null ? null : [EqChooseOnly(t)];
    }
    return null;
  }

  @override
  When? _when(String s) {
    // An Equipment played from [Hidden] (CR 811.1.d); its choices are made at that battlefield.
    if (s == 'When you play this from face down' && _isEquipment(card)) return const HWhen(On.playedFaceDown);
    return super._when(s);
  }

  @override
  Cond? _cond(String c) {
    if (c == "I didn't conquer this turn" && effectText) return const EqDidntConquer();
    if (c == "it's an Equipment" && _slotCounter[0] > _first) return EqIsEquipment(_slotCounter[0] - 1);
    return super._cond(c);
  }

  @override
  Target? _target(String p) {
    if (effectText && p.trim() == 'this') return const EqThis();
    return super._target(p);
  }
}
