part of 'ir.dart';

// Hidden, Ambush and the cards around them (CR 811, 822): facedown cards, playing units to more
// battlefields, moving enemy units, control changes and replacement effects. Each family of IR
// here hangs off one sealed type ([HEffect], [HTarget], [HCond], [HPassive]) so the engine's and
// the describer's switches each need one line for all of it.

// -------------------------------------------------------------------------------------------
// Targets
// -------------------------------------------------------------------------------------------

sealed class HTarget extends Target {
  const HTarget();
  String describe();
}

/// "Choose a battlefield [you control]": a battlefield, chosen as the spell or ability is played
/// (its object id is remembered in [slot]).
class ChooseBf extends HTarget {
  const ChooseBf(this.slot, {this.mine = false, this.withFriendlyUnits = false});
  final int slot;
  final bool mine;

  /// "Friendly units at a battlefield": only battlefields where you have units.
  final bool withFriendlyUnits;
  @override
  String describe() => 'a${mine ? ' controlled' : ''} battlefield';
}

/// A unit chosen in relation to an earlier choice [rel]: at the same location as it ([same]), or
/// at a different one ("at the same battlefield", "at a different location").
class ChooseRel extends HTarget {
  const ChooseRel(this.filter, this.slot, this.rel, {required this.same});
  final Filter filter;
  final int slot, rel;
  final bool same;
  @override
  String describe() => 'a ${filter.describe()} ${same ? 'with' : 'away from'} #$rel';
}

/// "Another friendly gear, unit, or [Hidden] card" (a permanent, or a card facedown at a
/// battlefield).
class ChooseOwnCard extends HTarget {
  const ChooseOwnCard(this.slot);
  final int slot;
  @override
  String describe() => 'another friendly gear, unit or facedown card';
}

/// The token this effect just played ("You may pay {Y} to ready it").
class LastMade extends HTarget {
  const LastMade();
  @override
  String describe() => 'the token';
}

// -------------------------------------------------------------------------------------------
// Effects
// -------------------------------------------------------------------------------------------

sealed class HEffect extends Effect {
  const HEffect();

  /// Targets this chooses as it's played (CR 355.5), in text order.
  List<Target> get choices => const [];

  /// Effects inside this one (their targets are chosen as it's played too).
  List<Effect> get nested => const [];

  /// The player may decline it as it resolves ("you may pay …"): its targets aren't mandatory.
  bool get optional => false;

  String describe(String Function(Effect) effect, String Function(Target) target);
}

/// "Choose a unit and …": the choices a later sentence refers to ("it", "that unit"); does
/// nothing itself.
class Pick extends HEffect {
  const Pick(this.targets);
  final List<Target> targets;
  @override
  List<Target> get choices => targets;
  @override
  String describe(effect, target) => 'choose ${targets.map(target).join(' and ')}';
}

/// Where a moved unit goes (CR 451.1: the effect decides).
enum MoveDest {
  /// Any other location (its controller's base or a battlefield), chosen as it resolves.
  anywhere,

  /// To the source's location ("to my battlefield").
  myLocation,

  /// "To a location where there's a unit with the same controller".
  sameController,

  /// To the battlefield chosen earlier ([MoveTo.bfSlot]).
  chosenBf,

  /// To its controller's base ("from a battlefield to its base"), remembering where it was.
  base,

  /// "To an occupied enemy battlefield if my Might is greater than the total Might of enemy units
  /// there".
  weakerEnemyBf,
}

/// "Move an enemy unit [to …]" (CR 451): a Move, so it contests where it arrives (CR 452).
class MoveTo extends HEffect {
  const MoveTo(this.target, this.dest, {this.bfSlot = -1});
  final Target target;
  final MoveDest dest;
  final int bfSlot;
  @override
  List<Target> get choices => [target];
  @override
  String describe(effect, target) => 'move ${target(this.target)} to ${dest.name}';
}

/// "Move me to its location and it to my original location" / "move each to the other's
/// location" ([needTemporary]: only if at least one of them has [Temporary]).
class SwapPlaces extends HEffect {
  const SwapPlaces(this.a, this.b, {this.needTemporary = false});
  final Target a, b;
  final bool needTemporary;
  @override
  List<Target> get choices => [a, b];
  @override
  String describe(effect, target) => 'swap the places of ${target(a)} and ${target(b)}${needTemporary ? ' if one is Temporary' : ''}';
}

/// "Then choose another enemy unit at its destination. They deal damage equal to their Mights to
/// each other." The second unit is chosen as it resolves.
class FightAtDest extends HEffect {
  const FightAtDest(this.moved);
  final Target moved;
  @override
  String describe(effect, target) => '${target(moved)} and another enemy unit there deal damage to each other';
}

/// "Move any number of friendly units at a battlefield to their base."
class AnyToBase extends HEffect {
  const AnyToBase(this.bf);
  final Target bf;
  @override
  List<Target> get choices => [bf];
  @override
  String describe(effect, target) => 'move any friendly units at ${target(bf)} to base';
}

/// "Kill any number of units at a battlefield with total Might N or less."
class KillTotal extends HEffect {
  const KillTotal(this.bf, this.total);
  final Target bf;
  final int total;
  @override
  List<Target> get choices => [bf];
  @override
  String describe(effect, target) => 'kill units at ${target(bf)} with total Might ≤ $total';
}

/// "Its controller draws N" (the unit chosen in [slot]).
class ControllerDraws extends HEffect {
  const ControllerDraws(this.slot, this.n);
  final int slot, n;
  @override
  String describe(effect, target) => 'its controller draws $n';
}

/// "Deal N to a unit at a battlefield. If it's attacking, deal M to it instead."
class DealOr extends HEffect {
  const DealOr(this.n, this.attacking, this.target);
  final int n, attacking;
  final Target target;
  @override
  List<Target> get choices => [target];
  @override
  String describe(effect, target) => 'deal $n ($attacking if attacking) to ${target(this.target)}';
}

/// "Swap the Might of two units … this turn."
class SwapMight extends HEffect {
  const SwapMight(this.a, this.b);
  final Target a, b;
  @override
  List<Target> get choices => [a, b];
  @override
  String describe(effect, target) => 'swap the Might of ${target(a)} and ${target(b)}';
}

/// "Take control of an enemy unit" (CR 190.3.a.2: it contests its battlefield); with [untilEot],
/// "lose control of that unit and recall it at end of turn".
class TakeControl extends HEffect {
  const TakeControl(this.target, {this.untilEot = false});
  final Target target;
  final bool untilEot;
  @override
  List<Target> get choices => [target];
  @override
  String describe(effect, target) => 'take control of ${target(this.target)}${untilEot ? ' until end of turn' : ''}';
}

/// "Banish a unit, then its owner plays it to the same location [to any battlefield], ignoring
/// its cost."
class Blink extends HEffect {
  const Blink(this.target, {this.anyBattlefield = false});
  final Target target;
  final bool anyBattlefield;
  @override
  List<Target> get choices => [target];
  @override
  String describe(effect, target) => 'banish ${target(this.target)} and replay it ${anyBattlefield ? 'to any battlefield' : 'there'}';
}

/// "Move any number of your units to an open battlefield."
class GatherAtOpen extends HEffect {
  const GatherAtOpen();
  @override
  String describe(effect, target) => 'move any of your units to an open battlefield';
}

/// "Reveal the top N cards of your Main Deck. Deal 1 to [target] for each card with [Hidden],
/// then recycle them."
class RevealHiddenDamage extends HEffect {
  const RevealHiddenDamage(this.n, this.target);
  final int n;
  final Target target;
  @override
  List<Target> get choices => [target];
  @override
  String describe(effect, target) => 'reveal top $n, deal 1 per Hidden card to ${target(this.target)}';
}

/// "Return up to N cards with [Hidden] from your trash to your hand."
class HiddenFromTrash extends HEffect {
  const HiddenFromTrash(this.n);
  final int n;
  @override
  String describe(effect, target) => 'return up to $n Hidden cards from trash';
}

/// "You can hide cards ignoring costs this turn."
class FreeHide extends HEffect {
  const FreeHide();
  @override
  String describe(effect, target) => 'hide for free this turn';
}

/// "Play a card with [Hidden] from your hand here, ignoring its cost."
class PlayHiddenHere extends HEffect {
  const PlayHiddenHere();
  @override
  String describe(effect, target) => 'play a Hidden card from hand here for free';
}

/// "An opponent reveals their hand. You may choose a unit from it. They play that unit to that
/// battlefield, ignoring any and all costs. When they do, [Stun] it."
class OpponentPlaysUnit extends HEffect {
  const OpponentPlaysUnit(this.bf);
  final Target bf;
  @override
  List<Target> get choices => [bf];
  @override
  String describe(effect, target) => 'an opponent plays a unit of your choice to ${target(bf)}, stunned';
}

/// "Friendly units enter ready this turn."
class EnterReadyThisTurn extends HEffect {
  const EnterReadyThisTurn();
  @override
  String describe(effect, target) => 'friendly units enter ready this turn';
}

/// "Buffs give an additional +1 {M} to friendly units this turn."
class BuffBonusThisTurn extends HEffect {
  const BuffBonusThisTurn();
  @override
  String describe(effect, target) => 'buffs give +1 more this turn';
}

/// "Double all damage that would be dealt to it this turn."
class DoubleDamage extends HEffect {
  const DoubleDamage(this.target);
  final Target target;
  @override
  List<Target> get choices => [target];
  @override
  String describe(effect, target) => 'double damage to ${target(this.target)} this turn';
}

/// "Play N Reflection unit tokens here. They become copies of me."
class CopyMe extends HEffect {
  const CopyMe(this.n);
  final int n;
  @override
  String describe(effect, target) => 'play $n copies of me here';
}

/// "Put a [tag] unit you own into your hand from your Champion Zone or the board."
class FetchToHand extends HEffect {
  const FetchToHand(this.tag);
  final String tag;
  @override
  String describe(effect, target) => 'put a $tag unit you own into your hand';
}

/// "Return another friendly gear, unit, or [Hidden] card to its owner's hand."
class ReturnOwn extends HEffect {
  const ReturnOwn(this.target);
  final Target target;
  @override
  List<Target> get choices => [target];
  @override
  String describe(effect, target) => 'return ${target(this.target)} to hand';
}

/// "Deal damage to a unit equal to the damage marked on it."
class DealMarked extends HEffect {
  const DealMarked(this.target);
  final Target target;
  @override
  List<Target> get choices => [target];
  @override
  String describe(effect, target) => 'deal ${target(this.target)} its marked damage again';
}

/// "You may pay [cost] to [effects]": asked as it resolves (only if it can be paid).
class MayPay extends HEffect {
  const MayPay(this.cost, this.effects);
  final Cost cost;
  final List<Effect> effects;
  @override
  List<Effect> get nested => effects;
  @override
  bool get optional => true;
  @override
  String describe(effect, target) => 'you may pay ${cost.describe()} to ${effects.map(effect).join(', ')}';
}

// -------------------------------------------------------------------------------------------
// Conditions
// -------------------------------------------------------------------------------------------

sealed class HCond extends Cond {
  const HCond();
  String describe();
}

/// "If you played this from your hand" (not from facedown, CR 811).
class FromHand extends HCond {
  const FromHand();
  @override
  String describe() => 'played from hand';
}

/// "If you paid the additional cost".
class PaidExtra extends HCond {
  const PaidExtra();
  @override
  String describe() => 'paid the additional cost';
}

/// "If there's an enemy unit alone at that battlefield" (where the unit in [slot] was moved from).
class AloneAtOrigin extends HCond {
  const AloneAtOrigin(this.slot);
  final int slot;
  @override
  String describe() => 'an enemy unit is alone where it was';
}

/// "If an enemy unit is alone here".
class EnemyAloneHere extends HCond {
  const EnemyAloneHere();
  @override
  String describe() => 'an enemy unit is alone here';
}

// -------------------------------------------------------------------------------------------
// Passives
// -------------------------------------------------------------------------------------------

sealed class HPassive extends Passive {
  const HPassive();
  String describe();
}

/// "I can't be chosen by enemy spells and abilities [unless I'm in combat]."
class CantBeChosen extends HPassive {
  const CantBeChosen({this.unlessInCombat = false});
  final bool unlessInCombat;
  @override
  String describe() => 'can’t be chosen by enemies${unlessInCombat ? ' unless in combat' : ''}';
}

/// "Your units here with less Might than me can't be chosen by enemy spells and abilities."
class ShieldsWeakerHere extends HPassive {
  const ShieldsWeakerHere();
  @override
  String describe() => 'your weaker units here can’t be chosen by enemies';
}

/// "I have [Shield 3] while I'm at a battlefield with exactly one other unit you control."
class KwWithOnePartner extends HPassive {
  const KwWithOnePartner(this.kw, this.n);
  final Kw kw;
  final int n;
  @override
  String describe() => '${kw.name} $n with exactly one partner';
}

/// "While there's a stunned enemy unit here, I have +N {M}."
class MightWhileStunnedEnemy extends HPassive {
  const MightWhileStunnedEnemy(this.n);
  final int n;
  @override
  String describe() => '+$n Might while a stunned enemy is here';
}

/// "I have +1 {M} for each other unit you control here with my name."
class MightPerNamesake extends HPassive {
  const MightPerNamesake();
  @override
  String describe() => '+1 Might per namesake here';
}

/// "Your deck can have any number of cards named …" (CR 103.2.c's copy limit doesn't apply).
class AnyNumberInDeck extends HPassive {
  const AnyNumberInDeck();
  @override
  String describe() => 'any number in a deck';
}

/// "Enemy units here with less Might than me don't deal combat damage."
class SilenceWeakerHere extends HPassive {
  const SilenceWeakerHere();
  @override
  String describe() => 'weaker enemies here deal no combat damage';
}

/// "I can't be readied."
class CantBeReadied extends HPassive {
  const CantBeReadied();
  @override
  String describe() => 'can’t be readied';
}

/// Extra places a unit may be played (CR 355.2.a is widened by these).
enum PlayPlace {
  /// "You may play me to an open battlefield" (CR 170.11.c: unoccupied and uncontrolled).
  open,

  /// "You may play me to an occupied enemy battlefield".
  occupiedEnemy,

  /// "I can be played to a battlefield you're attacking".
  attacking,

  /// "I can be played to a battlefield where there are enemy units" (with Ambush, CR 822.1.d).
  enemyUnits,
}

class PlayTo extends HPassive {
  const PlayTo(this.place);
  final PlayPlace place;
  @override
  String describe() => 'may be played to ${place.name} battlefields';
}

/// "Friendly units may be played to open battlefields."
class FriendlyToOpen extends HPassive {
  const FriendlyToOpen();
  @override
  String describe() => 'friendly units may be played to open battlefields';
}

/// "Your opponents' [Hidden] cards can't be revealed here."
class NoRevealHere extends HPassive {
  const NoRevealHere();
  @override
  String describe() => 'opponents’ facedown cards can’t be played here';
}

/// "You may pay {N} to hide a card with [Hidden] instead of {A}."
class HideForEnergy extends HPassive {
  const HideForEnergy(this.n);
  final int n;
  @override
  String describe() => 'hide for {$n} instead of {A}';
}

/// An additional cost to play me (CR 356.3): Power and Energy ([cost]), or killing a unit you
/// control with one of [killTags] ("You may play me to its battlefield": [toItsBattlefield]).
class ExtraCost extends HPassive {
  const ExtraCost({this.cost, this.killTags = const [], this.optional = true, this.toItsBattlefield = false, this.exhaustLegend = false});
  final Cost? cost;
  final List<String> killTags;
  final bool optional;
  final bool toItsBattlefield;

  /// "You may exhaust your legend as an additional cost".
  final bool exhaustLegend;
  @override
  String describe() => '${optional ? 'may pay' : 'must pay'} ${exhaustLegend ? 'exhausting your legend' : (cost?.describe() ?? 'kill a ${killTags.join('/')}')} more';
}

/// "The next time a friendly unit would die, kill this instead. Recall that unit exhausted."
/// (CR 369.1: it's healed, exhausted and recalled.)
class SavesFromDeath extends HPassive {
  const SavesFromDeath();
  @override
  String describe() => 'the next friendly unit that would die is recalled instead';
}

/// The second half of a control change ("Lose control of that unit and recall it at end of
/// turn."), carried out by [TakeControl].
class ControlEndsAtEot extends HPassive {
  const ControlEndsAtEot();
  @override
  String describe() => '(control ends at end of turn)';
}

// -------------------------------------------------------------------------------------------
// Triggers
// -------------------------------------------------------------------------------------------

/// A trigger with conditions on when it counts: "on your turn", "to a battlefield", "while I'm
/// at a battlefield", "once each turn".
class HWhen extends When {
  const HWhen(super.on, {this.yourTurn = false, this.toBattlefield = false, this.whileAtBattlefield = false, this.oncePerTurn = false});
  final bool yourTurn, toBattlefield, whileAtBattlefield, oncePerTurn;
}
