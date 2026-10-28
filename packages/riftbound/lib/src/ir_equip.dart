part of 'ir.dart';

// Equipment (CR 150, 716–725, 818, 819, 821) and the cards built around it: what parser/equip.dart
// reads and game/equip.dart executes.

/// Equipment events a unit's triggered abilities can wait for (with [On.eq]).
enum EqEvent {
  /// "When you attach an Equipment to me".
  attachedToMe,

  /// "The first time I conquer each turn".
  firstConquer,

  /// "When I conquer an open battlefield" (open: unoccupied and uncontrolled, CR 170.11.c).
  conquerOpen,
}

class EqWhen extends When {
  const EqWhen(this.event) : super(On.eq);
  final EqEvent event;
}

/// A cost with parts beyond Energy, Power and exhausting (CR 202, 818.1.c.3).
class EqCost extends Cost {
  const EqCost({super.energy, super.power, super.exhaust, super.extra, this.lessByTargetMight = false, this.banishMe = false});

  /// "This ability's Energy cost is reduced by the Might of the unit you choose."
  final bool lessByTargetMight;

  /// "Banish this".
  final bool banishMe;

  @override
  bool get isFree => super.isFree && !banishMe;

  @override
  String describe() => [
        super.describe(),
        if (lessByTargetMight) '(less by its Might)',
        if (banishMe) 'banish this',
      ].where((s) => s.isNotEmpty).join(', ');
}

/// [Equip] (CR 818): "[Cost]: Attach this gear to a unit you control."
class EqEquip extends Activated {
  const EqEquip(String text, EqCost cost) : super(text, cost, const [EqAttachMe(Choose(Filter(side: Side.friendly)))]);
  EqCost get eqCost => cost as EqCost;
}

/// An activated ability with a restriction or cost the core doesn't know.
class EqActivated extends Activated {
  const EqActivated(super.text, super.cost, super.effects, {super.timing, super.oncePerTurn, super.legion, this.onlyIfPlayedEquipment = false});

  /// "Use only if you've played an Equipment this turn."
  final bool onlyIfPlayedEquipment;
}

/// [Weaponmaster] (CR 821): "When you play me, you may choose an Equipment you control and pay its
/// Equip cost, reduced by [A], to attach it to me."
class EqWeaponmaster extends Triggered {
  const EqWeaponmaster(String text) : super(text, const When(On.played), const [EqWeaponmasterAttach()]);
}

/// [Quick-Draw] (CR 819): [Reaction] and "When you play this, attach it to a unit you control."
class EqQuickDraw extends Triggered {
  const EqQuickDraw(String text) : super(text, const When(On.played), const [EqAttachMe(Choose(Filter(side: Side.friendly)))]);
}

// ---------------------------------------------------------------------------------------------
// Targets
// ---------------------------------------------------------------------------------------------

sealed class EqTarget extends Target {
  const EqTarget();
  String describe();
}

/// "This" in Effect Text: the attached card, not the unit it's attached to (CR 136.2.d).
class EqThis extends EqTarget {
  const EqThis();
  @override
  String describe() => 'this';
}

/// A choice with conditions a [Filter] can't say: "an equipped friendly unit", "an attached
/// Equipment", "an Equipment with the same controller" (as the object in slot [sameControllerAs]).
class EqChoose extends Choose {
  const EqChoose(super.filter, {super.slot, super.upTo, this.equipped, this.attached, this.sameControllerAs = -1});
  final bool? equipped, attached;
  final int sameControllerAs;
}

// ---------------------------------------------------------------------------------------------
// Amounts and conditions
// ---------------------------------------------------------------------------------------------

sealed class EqAmount extends Amount {
  const EqAmount();
  String describe();
}

/// "N for each Equipment attached to me".
class EqPerEquipment extends EqAmount {
  const EqPerEquipment(this.n);
  final int n;
  @override
  String describe() => '$n per Equipment on me';
}

sealed class EqCond extends Cond {
  const EqCond();
  String describe();
}

/// "If I didn't conquer this turn".
class EqDidntConquer extends EqCond {
  const EqDidntConquer();
  @override
  String describe() => 'I didn’t conquer this turn';
}

/// "If you assigned N or more excess damage" (in the combat that led to this conquest).
class EqExcessAtLeast extends EqCond {
  const EqExcessAtLeast(this.n);
  final int n;
  @override
  String describe() => 'assigned $n+ excess damage';
}

/// "If it's an Equipment" (the object chosen in [slot]).
class EqIsEquipment extends EqCond {
  const EqIsEquipment(this.slot);
  final int slot;
  @override
  String describe() => 'it’s an Equipment';
}

/// "While I'm at a battlefield with exactly one other unit you control".
class EqWithOneOther extends EqCond {
  const EqWithOneOther();
  @override
  String describe() => 'at a battlefield with exactly one other friendly unit';
}

/// "If this was attached to me this turn".
class EqAttachedThisTurn extends EqCond {
  const EqAttachedThisTurn();
  @override
  String describe() => 'this was attached this turn';
}

/// [Level N] (CR 824): while you have N or more XP.
class EqLevel extends EqCond {
  const EqLevel(this.n);
  final int n;
  @override
  String describe() => 'level $n';
}

// ---------------------------------------------------------------------------------------------
// Passive abilities
// ---------------------------------------------------------------------------------------------

sealed class EqPassive extends Passive {
  const EqPassive();
  String describe();
}

/// "Your Sand Soldiers have [Weaponmaster]."
class EqGrantWeaponmaster extends EqPassive {
  const EqGrantWeaponmaster(this.name, this.ability);
  final String name;
  final EqWeaponmaster ability;
  @override
  String describe() => 'your $name have Weaponmaster';
}

/// "Each Equipment in your hand has [Quick-Draw]."
class EqGrantQuickDraw extends EqPassive {
  const EqGrantQuickDraw(this.ability);
  final EqQuickDraw ability;
  @override
  String describe() => 'Equipment in your hand have Quick-Draw';
}

/// "Your Equipment each give [Assault]." (to the unit each is attached to)
class EqEquipmentGive extends EqPassive {
  const EqEquipmentGive(this.kw, this.n);
  final Kw kw;
  final int n;
  @override
  String describe() => 'your Equipment each give ${kw.name}${n > 1 ? ' $n' : ''}';
}

/// "I have +N {M} for each friendly gear."
class EqMightPerGear extends EqPassive {
  const EqMightPerGear(this.n);
  final int n;
  @override
  String describe() => '+$n Might per friendly gear';
}

/// "Each Equipment attached to me gives double its base Might bonus."
class EqDoubleBonus extends EqPassive {
  const EqDoubleBonus();
  @override
  String describe() => 'Equipment give double Might bonus';
}

/// "I have +N {M} while …" / "If …, I have an additional +N {M}."
class EqMightIf extends EqPassive {
  const EqMightIf(this.n, this.cond);
  final int n;
  final EqCond cond;
  @override
  String describe() => '+$n Might if ${cond.describe()}';
}

/// "I am a Mech." (CR 479.2: a tag)
class EqHasTag extends EqPassive {
  const EqHasTag(this.tag);
  final String tag;
  @override
  String describe() => 'is a $tag';
}

/// "I can't be moved by enemy spells and abilities."
class EqUnmovable extends EqPassive {
  const EqUnmovable();
  @override
  String describe() => 'can’t be moved by enemies';
}

/// "Your spells and abilities deal N Bonus Damage." (CR 712)
class EqBonusDamage extends EqPassive {
  const EqBonusDamage(this.n);
  final int n;
  @override
  String describe() => 'spells and abilities deal $n Bonus Damage';
}

/// "My hold effects are also conquer effects, and vice versa."
class EqHoldIsConquer extends EqPassive {
  const EqHoldIsConquer();
  @override
  String describe() => 'hold and conquer effects are the same';
}

/// Shady Spectacles: "As this is attached to a unit, choose another friendly unit. The equipped
/// unit becomes a copy of that unit for as long as this is attached to it."
class EqCopyAsAttached extends EqPassive {
  const EqCopyAsAttached();
  @override
  String describe() => 'its unit becomes a copy of another friendly unit';
}

/// Svellsongur: "As this is attached to a unit, copy that unit's text to this Equipment's effect
/// text for as long as this is attached to it."
class EqCopyTextAsAttached extends EqPassive {
  const EqCopyTextAsAttached();
  @override
  String describe() => 'copies its unit’s text as Effect Text';
}

/// Guardian Angel: "If I would die, kill Guardian Angel instead. Heal me, exhaust me, and recall me."
/// (a replacement effect, CR 380)
class EqDieInstead extends EqPassive {
  const EqDieInstead();
  @override
  String describe() => 'if I would die, kill this instead; heal, exhaust and recall me';
}

/// "While you control this battlefield, friendly legends have "[ability]"."
class EqGrantLegends extends EqPassive {
  const EqGrantLegends(this.ability);
  final Activated ability;
  @override
  String describe() => 'friendly legends have an ability';
}

// ---------------------------------------------------------------------------------------------
// Effects
// ---------------------------------------------------------------------------------------------

sealed class EqEffect extends Effect {
  const EqEffect();

  /// What it chooses as it's played, in order.
  List<Target> get targets => const [];
  String describe();
}

/// Attach this (the source) to [unit] (CR 435).
class EqAttachMe extends EqEffect {
  const EqAttachMe(this.unit);
  final Target unit;
  @override
  List<Target> get targets => [unit];
  @override
  String describe() => 'attach this to a friendly unit';
}

/// Weaponmaster's attach (CR 821.1.c).
class EqWeaponmasterAttach extends EqEffect {
  const EqWeaponmasterAttach();
  @override
  String describe() => 'you may pay an Equipment’s Equip cost less {A} to attach it to me';
}

/// "Attach [equipment] to [unit]".
class EqAttachTo extends EqEffect {
  const EqAttachTo(this.equipment, this.unit);
  final Target equipment, unit;
  @override
  List<Target> get targets => [equipment, unit];
  @override
  String describe() => 'attach an Equipment to a unit';
}

/// Angle Shot: "Attach that Equipment to that unit or detach that Equipment from that unit."
class EqAttachOrDetach extends EqEffect {
  const EqAttachOrDetach(this.unit, this.equipment);
  final Target unit, equipment;
  @override
  List<Target> get targets => [unit, equipment];
  @override
  String describe() => 'attach the Equipment to the unit or detach it';
}

/// "Detach / unattach [equipment]" (CR 436).
class EqDetach extends EqEffect {
  const EqDetach(this.equipment);
  final Target equipment;
  @override
  List<Target> get targets => [equipment];
  @override
  String describe() => 'detach it';
}

/// "Detach an Equipment from [unit]" (chosen as it resolves).
class EqDetachFrom extends EqEffect {
  const EqDetachFrom(this.unit);
  final Target unit;
  @override
  List<Target> get targets => [unit];
  @override
  String describe() => 'detach an Equipment from it';
}

/// "Choose …": only makes a choice for what follows ("it").
class EqChooseOnly extends EqEffect {
  const EqChooseOnly(this.choice);
  final Target choice;
  @override
  List<Target> get targets => [choice];
  @override
  String describe() => 'choose ${choice is Choose ? (choice as Choose).filter.describe() : 'one'}';
}

/// Akshan: "Move [gear] to your base. You control it until I leave the board. If it's an
/// Equipment, attach it to me."
class EqTakeGear extends EqEffect {
  const EqTakeGear(this.gear);
  final Target gear;
  @override
  List<Target> get targets => [gear];
  @override
  String describe() => 'take an enemy gear until I leave; attach it if it’s an Equipment';
}

/// Strike Down: "[unit] deals damage equal to its Might to [victim]."
class EqUnitDeals extends EqEffect {
  const EqUnitDeals(this.unit, this.victim);
  final Target unit, victim;
  @override
  List<Target> get targets => [unit, victim];
  @override
  String describe() => 'it deals damage equal to its Might to an enemy unit';
}

/// Arise!: "Play a 2 {M} Sand Soldier unit token for each Equipment you control. Then ready two of them."
class EqTokensPerEquipment extends EqEffect {
  const EqTokensPerEquipment(this.token, this.ready);
  final String token;
  final int ready;
  @override
  String describe() => 'play a $token per Equipment you control, ready $ready of them';
}

/// Azir, Ascendant: "Move me to its location and it to my original location. If it's equipped,
/// you may attach one of its Equipment to me."
class EqSwapWith extends EqEffect {
  const EqSwapWith(this.unit);
  final Target unit;
  @override
  List<Target> get targets => [unit];
  @override
  String describe() => 'swap places with it';
}

/// "If it's equipped, you may attach one of its Equipment to me."
class EqTakeOneEquipment extends EqEffect {
  const EqTakeOneEquipment(this.unit);
  final Target unit;
  @override
  List<Target> get targets => [unit];
  @override
  String describe() => 'you may attach one of its Equipment to me';
}

/// "Move [unit]" to a location chosen as it resolves.
class EqMove extends EqEffect {
  const EqMove(this.unit);
  final Target unit;
  @override
  List<Target> get targets => [unit];
  @override
  String describe() => 'move it';
}

/// "This turn, [unit] has "[ability]"."
class EqGrantThisTurn extends EqEffect {
  const EqGrantThisTurn(this.unit, this.ability);
  final Target unit;
  final Triggered ability;
  @override
  List<Target> get targets => [unit];
  @override
  String describe() => 'it has "${ability.text}" this turn';
}

/// "You may pay [cost] to [effects]."
class EqMayPay extends EqEffect {
  const EqMayPay(this.cost, this.effects);
  final Cost cost;
  final List<Effect> effects;
  @override
  String describe() => 'you may pay ${cost.describe()}';
}

/// "Play a unit from your trash" (paying its costs).
class EqPlayFromTrash extends EqEffect {
  const EqPlayFromTrash();
  @override
  String describe() => 'play a unit from your trash';
}

/// Rell: "Play an Equipment with Energy cost no more than {N}, ignoring its cost, and attach it to me."
class EqPlayEquipmentFree extends EqEffect {
  const EqPlayEquipmentFree(this.maxEnergy);
  final int maxEnergy;
  @override
  String describe() => 'play an Equipment costing {$maxEnergy} or less free and attach it to me';
}

/// The Zero Drive's Effect Text: "[Deathknell] - Banish me." (with the unit "banished with this").
class EqBanishMe extends EqEffect {
  const EqBanishMe();
  @override
  String describe() => 'banish me';
}

/// The Zero Drive: "Play all units banished with this, ignoring their costs."
class EqPlayBanishedWith extends EqEffect {
  const EqPlayBanishedWith();
  @override
  String describe() => 'play all units banished with this free';
}

