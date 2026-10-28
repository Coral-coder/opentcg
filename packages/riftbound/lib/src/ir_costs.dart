part of 'ir.dart';

// Costs, modes and playing cards from elsewhere (CR 201–206, 355–357, 420.3): what card text
// about costs means. The parser side is parser/costs.dart, the engine side game/costs.dart.

/// How a card was played, kept on its chain item ([ChainItem.paid]) and on the permanent it
/// became ([Obj.paidExtra]).
abstract final class PlayFlags {
  /// Its optional additional cost was paid ("if you paid the additional cost", "if you do";
  /// CR 356.4.f.1: paid even if a discount made it free).
  static const additional = 1;

  /// "Recycle that spell after you play it": recycled instead of going to the trash.
  static const recycleAfter = 2;

  /// Played from anywhere other than a player's hand.
  static const elsewhere = 4;
}

// ---------------------------------------------------------------------------------------------
// Costs of activated abilities (CR 204.1.b)
// ---------------------------------------------------------------------------------------------

/// "Recycle 3 from your trash", "Recycle a unit from your trash" (CR 417.3: all of them or it
/// can't be paid).
class RecycleTrash extends CostPart {
  const RecycleTrash(this.n, {this.unit = false});
  final int n;
  final bool unit;
}

// ---------------------------------------------------------------------------------------------
// Passives about playing cards
// ---------------------------------------------------------------------------------------------

sealed class XPassive extends Passive {
  const XPassive();
  String describe();
}

/// What an additional cost asks for (CR 204.2, 356.2, 357.2).
enum XPay {
  /// Energy and Power.
  resources,
  discard,

  /// Kill friendly permanents matching [AddCost.filter].
  kill,
  exhaustUnit,
  exhaustLegend,

  /// Remove buff counters from friendly units.
  spendBuff,

  /// Return a friendly gear to its owner's hand.
  returnGear,

  /// "Spend N XP" (CR 730.2; [AddCost.n]).
  xp,
}

/// "[You may] … as an additional cost to play me/this. [If you do, …]" — on the card being played.
class AddCost extends XPassive {
  const AddCost(
    this.pay, {
    this.optional = true,
    this.energy = 0,
    this.power = const [],
    this.n = 1,
    this.anyNumber = false,
    this.filter = const Filter(side: Side.friendly),
    this.tags = const [],
    this.mighty = false,
    this.ifSpellPlayed = false,
    this.discount = 0,
    this.discountEach,
    this.discountByKilled,
    this.ignoreCost = false,
    this.entersReady = false,
    this.then = const [],
    this.toItsBattlefield = false,
  });
  final XPay pay;
  final bool optional;
  final int energy;
  final List<Domain?> power;

  /// How many to discard, kill or spend; [anyNumber]: "any number of".
  final int n;
  final bool anyNumber;
  final Filter filter;

  /// "Kill a Bird, Cat, Dog, or Poro you control": any of these tags.
  final List<String> tags;

  /// "A friendly [Mighty] unit" (CR 708: Might 5 or more).
  final bool mighty;

  /// "If you've played a spell this turn, you may pay …".
  final bool ifSpellPlayed;

  /// "If you do, reduce my cost by {2}" / "I cost {3} less".
  final int discount;

  /// "Reduce my cost by {O} for each buff you spend" (a Power symbol per item).
  final Domain? discountEach;

  /// "I cost {1} less for each Energy it costs and {Y} less for each Power it costs" (Atakhan):
  /// the domain of the Power discount.
  final Domain? discountByKilled;

  /// "If you do, ignore this spell's cost" (CR 356.1.b).
  final bool ignoreCost;

  /// "If you do, I enter ready."
  final bool entersReady;

  /// "If you do, draw 1." — done as the permanent is played (CR 359.2.b).
  final List<Effect> then;

  /// "You may play me to its battlefield" (the killed unit's).
  final bool toItsBattlefield;

  @override
  String describe() => '${optional ? 'may ' : ''}${switch (pay) {
        XPay.resources => 'pay ${energy > 0 || power.isEmpty ? '{$energy}' : ''}${power.map((d) => '{${d?.letter ?? 'A'}}').join()}',
        XPay.discard => 'discard $n',
        XPay.kill => 'kill ${anyNumber ? 'any number of' : n} ${mighty ? 'Mighty ' : ''}${tags.isEmpty ? filter.describe() : tags.join('/')}',
        XPay.exhaustUnit => 'exhaust a friendly unit',
        XPay.exhaustLegend => 'exhaust your legend',
        XPay.spendBuff => 'spend ${anyNumber ? 'any number of buffs' : 'a buff'}',
        XPay.returnGear => 'return a friendly gear to hand',
        XPay.xp => 'spend $n XP',
      }} as an additional cost${discount > 0 ? ': {$discount} less' : ''}${discountEach != null ? ': {${discountEach!.letter}} less each' : ''}${discountByKilled != null ? ': less by its cost' : ''}${ignoreCost ? ': ignore cost' : ''}${entersReady ? ': enters ready' : ''}${ifSpellPlayed ? ' (if you played a spell)' : ''}${toItsBattlefield ? ' (may play to its battlefield)' : ''}';
}

/// What a variable discount counts (CR 356.4.g: checked as the cost is determined).
enum XPer {
  cardsPlayedThisTurn,
  mightyUnits,
  gearYouControl,
  cardsInTrash,
  sameNameInTrash,
  holdPointsThisTurn,
  friendlyTemporaryUnits,

  /// "The highest Might among units you control".
  highestMight,

  /// "For each of the following tags among your units - Bird, Cat, Dog, and Poro" ([SelfCost.perTags]).
  tagKinds,
}

/// "I cost {2}{Y} less [for each …] [if …], [to a minimum of {1}]" — a discount on the card
/// itself (CR 356.4).
class SelfCost extends XPassive {
  const SelfCost({this.energy = 0, this.power = const [], this.per, this.cond, this.min = 0, this.elsewhere = false, this.entersReady = false, this.choosesTags = const [], this.perTags = const []});
  final int energy;
  final List<Domain?> power;
  final XPer? per;
  final Cond? cond;

  /// "To a minimum of {1}": applies only to this discount (CR 356.4.e).
  final int min;

  /// "To play from anywhere other than your hand".
  final bool elsewhere;

  /// "… and enter ready" (Monch).
  final bool entersReady;

  /// "If you choose a Bird, Cat, Dog, or Poro" (the card this spell plays).
  final List<String> choosesTags;

  /// The tags [XPer.tagKinds] counts.
  final List<String> perTags;

  @override
  String describe() => 'costs {$energy}${power.map((d) => '{${d?.letter ?? 'A'}}').join()} less${per == null ? '' : ' per ${per!.name}'}${cond == null ? '' : ' if ${describeXCond(cond!)}'}${elsewhere ? ' from elsewhere' : ''}${min > 0 ? ' (min {$min})' : ''}${entersReady ? ', enters ready' : ''}${choosesTags.isEmpty ? '' : ' if it chooses ${choosesTags.join('/')}'}';
}

/// "You may play me for {B}" when [cond] holds; [fromTrash]: "You may play me from your trash
/// for {3}{R}" (with [legion], only once you've played another card this turn).
class AltCost extends XPassive {
  const AltCost(this.energy, this.power, {this.cond, this.fromTrash = false, this.legion = false});
  final int energy;
  final List<Domain?> power;
  final Cond? cond;
  final bool fromTrash, legion;
  @override
  String describe() => '${fromTrash ? 'from trash ' : ''}for {$energy}${power.map((d) => '{${d?.letter ?? 'A'}}').join()}${legion ? ' (legion)' : ''}${cond == null ? '' : ' if ${describeXCond(cond!)}'}';
}

/// Which cards another permanent's cost change applies to.
enum XWho {
  /// "The first friendly non-token gear played each turn" (Ornn's Forge).
  firstGear,

  /// "The first friendly gear activated ability played each turn" (Piltovan Forge).
  firstGearAbility,

  /// "Friendly [Repeat] costs" (Marai Spire).
  repeatCosts,

  /// "Cards with [Reaction]" during showdowns here, any player's (Mystic Vortex).
  reactionsInShowdownHere,

  /// "Friendly spells cost … less, and enemy spells cost … more" while I'm in combat (Vex).
  friendlySpellsInCombat,

  /// "Your spells that choose me" (Irelia, Graceful).
  spellsChoosingMe,

  /// "Each spell that chooses one or more units here that are friendly to it" (Sandswept Tomb).
  spellsChoosingFriendlyHere,

  /// "Optional additional costs you pay" (Ezreal, Prodigy).
  optionalCosts,

  /// "While I'm at a battlefield, the Energy costs for spells you play" (Eager Apprentice).
  spellsWhileAtBattlefield,

  /// "Your Dragons' Energy costs" ([CostMod.tag]).
  yourTagged,
}

/// A cost increase ([more]) or discount from another permanent, legend or battlefield.
class CostMod extends XPassive {
  const CostMod(this.who, {this.energy = 0, this.power = const [], this.more = false, this.orPower = false, this.min = 0, this.whileControlled = false, this.tag});
  final XWho who;
  final int energy;
  final List<Domain?> power;
  final bool more;

  /// "{1} or {A} less": the payer takes whichever lets them pay.
  final bool orPower;
  final int min;

  /// "While you control this battlefield".
  final bool whileControlled;

  /// The tag of [XWho.yourTagged].
  final String? tag;
  @override
  String describe() => '${who.name} cost {$energy}${orPower ? ' or {A}' : power.map((d) => '{${d?.letter ?? 'A'}}').join()} ${more ? 'more' : 'less'}${min > 0 ? ' (min {$min})' : ''}${whileControlled ? ' while controlled' : ''}';
}

/// "Friendly units played from anywhere other than a player's hand have [Accelerate]."
class ElsewhereAccelerate extends XPassive {
  const ElsewhereAccelerate();
  @override
  String describe() => 'units played from elsewhere have accelerate';
}

/// "Any player may pay {A}{A} as an additional cost to play a Dragon. If they do, they play it
/// to this battlefield." (Dragon Roost)
class RoostCost extends XPassive {
  const RoostCost(this.tag, this.power);
  final String tag;
  final List<Domain?> power;
  @override
  String describe() => 'may pay ${power.map((d) => '{${d?.letter ?? 'A'}}').join()} to play a $tag here';
}

/// "My Might is increased by the number of cards in your trash" / "If you've spent {4} or more
/// to play a spell this turn, I have +4 {M}."
class XMight extends XPassive {
  const XMight({this.perTrashCard = false, this.n = 0, this.cond});
  final bool perTrashCard;
  final int n;
  final Cond? cond;
  @override
  String describe() => perTrashCard ? '+1 Might per card in trash' : '+$n Might if ${describeXCond(cond!)}';
}

/// "Ignore [Deflect] while paying this spell's cost." / "Players ignore [Deflect] while paying for
/// spells and abilities choosing something here." ([here]: on a battlefield).
class IgnoreDeflect extends XPassive {
  const IgnoreDeflect({this.here = false});
  final bool here;
  @override
  String describe() => here ? 'ignore Deflect for things chosen here' : 'ignore Deflect while paying';
}

/// "When you look at cards from the top of your deck and see me, you may play me for {A}."
class SeeMePlay extends XPassive {
  const SeeMePlay(this.energy, this.power);
  final int energy;
  final List<Domain?> power;
  @override
  String describe() => 'when seen on top of your deck, may play for {$energy}${power.map((d) => '{${d?.letter ?? 'A'}}').join()}';
}

/// "As I'm revealed from your deck, [Add] {2}." (Undertitan)
class RevealAdd extends XPassive {
  const RevealAdd(this.energy);
  final int energy;
  @override
  String describe() => 'add {$energy} as revealed';
}

// ---------------------------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------------------------

sealed class XCond extends Cond {
  const XCond();
}

/// "If you control a battlefield with exactly two units there".
class ControlBfWithUnits extends XCond {
  const ControlBfWithUnits(this.n);
  final int n;
}

/// "If an opponent controls a stunned unit".
class OpponentStunned extends XCond {
  const OpponentStunned();
}

/// "If an enemy unit has died this turn".
class EnemyDiedThisTurn extends XCond {
  const EnemyDiedThisTurn();
}

/// "If you've spent {4} or more to play a spell this turn".
class SpentOnSpell extends XCond {
  const SpentOnSpell(this.n);
  final int n;
}

/// "While your units have all 4 tags" (Bird, Cat, Dog and Poro).
class AllTags extends XCond {
  const AllTags(this.tags);
  final List<String> tags;
}

String describeXCond(Cond c) => switch (c) {
      ControlBfWithUnits(:final n) => 'control a battlefield with exactly $n units',
      OpponentStunned() => 'opponent has a stunned unit',
      EnemyDiedThisTurn() => 'an enemy unit died this turn',
      SpentOnSpell(:final n) => 'spent {$n}+ on a spell this turn',
      AllTags(:final tags) => 'your units have all of ${tags.join('/')}',
      PaidExtra() => 'paid',
      OpponentNearVictory(:final n) => 'opponent within $n of winning',
      ControlTag(:final tag) => 'you control a $tag',
      AtBattlefield() => 'I am at a battlefield',
      _ => '?',
    };

// ---------------------------------------------------------------------------------------------
// Triggers
// ---------------------------------------------------------------------------------------------

/// Events of game/costs.dart.
enum XOn {
  /// "When I become ready".
  becomeReady,

  /// "When you play a spell that costs {5} or more" ([XWhen.n]: minimum Energy cost).
  playSpell,

  /// "When you play a card with Power cost {A}{A} or more" ([XWhen.n]: minimum Power).
  playCardPower,

  /// "When you play a unit, gear, or activated ability with Energy cost {7} or more".
  playBig,

  /// "When you play your first card each turn".
  firstCard,

  /// "When you kill a unit with a spell" (CR 429.5).
  killWithSpell,
}

/// A trigger with a condition right after it (CR 383.2.a.1: checked as it triggers), and the
/// events of game/costs.dart ([kind], with [On.costsExt]). [fromTrash]: it works while its card
/// is in its owner's trash.
class XWhen extends When {
  const XWhen(super.on, {this.kind, this.n = 0, this.cond, this.fromTrash = false});
  final XOn? kind;
  final int n;
  final Cond? cond;
  final bool fromTrash;
}

// ---------------------------------------------------------------------------------------------
// Effects
// ---------------------------------------------------------------------------------------------

/// Effects of game/costs.dart (described by describe_costs.dart).
sealed class XEffect extends Effect {
  const XEffect();
}

/// "Each player draws 1" / "Each player discards 1".
class EachPlayer extends XEffect {
  const EachPlayer({this.draw = 0, this.discard = 0});
  final int draw, discard;
}

/// "They deal damage equal to their Mights to each other" (two chosen units).
class Fight extends XEffect {
  const Fight(this.a, this.b);
  final Target a, b;
}

/// "If …, [then] Otherwise, [otherwise]".
class IfElse extends XEffect {
  const IfElse(this.cond, this.then, this.otherwise);
  final Cond cond;
  final List<Effect> then, otherwise;
}

/// Where [PlayFrom] finds the card.
enum XZone { trash, hand, bannedByMe }

/// "Play a unit from your trash [that costs no more than …], ignoring its [Energy] cost [, then
/// recycle it]" (CR 420.3). The card is chosen as it resolves (CR 355.18), unless [slot] ≥ 0.
class PlayFrom extends XEffect {
  const PlayFrom(
    this.zone, {
    this.types = const {},
    this.tags = const [],
    this.maxEnergy,
    this.maxPower,
    this.lessThanPoints = false,
    this.maxOfKilled = false,
    this.ignoreEnergy = false,
    this.ignoreAll = false,
    this.toBase = false,
    this.recycleAfter = false,
    this.slot = -1,
  });
  final XZone zone;

  /// Unit, spell, gear (empty: any).
  final Set<CardType> types;
  final List<String> tags;
  final int? maxEnergy, maxPower;

  /// "With Energy cost less than your points".
  final bool lessThanPoints;

  /// "That costs no more Energy and no more Power than the killed unit".
  final bool maxOfKilled;
  final bool ignoreEnergy, ignoreAll;
  final bool toBase;
  final bool recycleAfter;
  final int slot;
}

/// "Choose up to 3 cards from opponents' trashes. Their owners recycle them."
class RecycleOpponentTrash extends XEffect {
  const RecycleOpponentTrash(this.n);
  final int n;
}

/// "Recycle 3 from your trash" as an instruction (CR 417.4: as many as possible).
class RecycleYourTrash extends XEffect {
  const RecycleYourTrash(this.n);
  final int n;
}

/// "Move any number of your units to an open battlefield" (CR 170.11.c).
class MoveToOpenBf extends XEffect {
  const MoveToOpenBf();
}

/// "[You may] banish a card/unit from [your/any] trash. If you do, [then]" / "… to [then]"
/// (a cost within instructions, CR 204.3).
class BanishTrashThen extends XEffect {
  const BanishTrashThen(this.then, {this.anyTrash = false, this.unit = false});
  final List<Effect> then;
  final bool anyTrash, unit;
}

/// "The defender must kill one of their units here" (Atakhan).
class DefenderKills extends XEffect {
  const DefenderKills();
}

/// "Kill [target]. Then, if it had 3 {M} or less, you may play this from your trash for {A}."
class KillThenReplay extends XEffect {
  const KillThenReplay(this.target, this.maxMight, this.power);
  final Target target;
  final int maxMight;
  final List<Domain?> power;
}

/// "Kill a gear with Energy cost no more than {1}" / "… no more than my Might" ([myMight]); the
/// gear is chosen in [slot]. [then]: "If you do, …".
class KillGearByCost extends XEffect {
  const KillGearByCost(this.slot, {this.max = 0, this.myMight = false, this.then = const []});
  final int slot;
  final int max;
  final bool myMight;
  final List<Effect> then;
}

/// "Kill a friendly gear. If you do, …" — [first] then [then] if [first] affected something.
class DoThen extends XEffect {
  const DoThen(this.first, this.then);
  final Effect first;
  final List<Effect> then;
}

/// Effects lasting until the end of the turn (turn marks, game/costs.dart).
enum XTurnFx {
  /// "The next spell you play this turn costs {5} less" ([TurnFx.energy]).
  nextSpellLess,

  /// "Your next card costs {2}{A}{A} less" ([TurnFx.energy], [TurnFx.power] any-domain symbols).
  nextCardLess,

  /// "Your non-token units cost {1} more to play this turn".
  unitsMore,

  /// "You may play a gear with Energy cost no more than {7} from hand this turn, ignoring its
  /// Energy cost".
  freeGear,

  /// "Give the next spell you play this turn [Repeat] equal to its cost".
  nextSpellRepeat,
}

class TurnFx extends XEffect {
  const TurnFx(this.fx, {this.energy = 0, this.power = 0});
  final XTurnFx fx;
  final int energy, power;
}

/// "Counter a spell that costs no more than {4} and no more than {A}" (CR 206: printed costs).
class CounterByCost extends XEffect {
  const CounterByCost(this.maxEnergy, this.maxPower);
  final int maxEnergy, maxPower;
}

/// "Look at the top 4 cards of your Main Deck. You may reveal a spell with Energy cost {4} or
/// more from among them and draw it. Recycle the rest."
class LookDrawType extends XEffect {
  const LookDrawType(this.n, this.type, {this.minEnergy = 0});
  final int n;
  final CardType type;
  final int minEnergy;
}

/// "Each opponent reveals the top card of their Main Deck. Choose one and banish it, then play
/// it, ignoring its cost. Then recycle the rest."
class PlayOpponentsTop extends XEffect {
  const PlayOpponentsTop();
}

/// "Banish all units from your trash" (remembered as banished with this source, CR 428.3).
class BanishTrashUnits extends XEffect {
  const BanishTrashUnits();
}

/// "Recycle another friendly unit to play a Mech from your trash. Reduce its Energy cost by the
/// Might of the unit you recycled." (Rumble, Hotheaded; the unit is chosen in [slot]).
class RecycleToPlay extends XEffect {
  const RecycleToPlay(this.slot, this.tag);
  final int slot;
  final String tag;
}

/// "Exhaust me to ready up to 2 runes" (a cost within instructions).
class ExhaustMeThen extends XEffect {
  const ExhaustMeThen(this.then);
  final List<Effect> then;
}

/// "Return this from your trash to your hand", paid by discarding [discard] (a cost within
/// instructions).
class ReturnMeFromTrash extends XEffect {
  const ReturnMeFromTrash({this.discard = 0});
  final int discard;
}

/// "Pay {1}{R} to play me from your trash" (a cost within instructions).
class PayToPlayMe extends XEffect {
  const PayToPlayMe(this.energy, this.power);
  final int energy;
  final List<Domain?> power;
}

/// "This ability costs {1} less for each friendly unit with [Temporary]" — read by the engine as
/// it's activated; does nothing as it resolves.
class AbilityCostLess extends XEffect {
  const AbilityCostLess(this.n, this.per);
  final int n;
  final XPer per;
}

/// "Choose a spell with Energy cost no more than {4}. You may pay {A}. If you do, gain control of
/// it and you may make new choices for it (CR 750). Otherwise, counter it." The spell is in slot 0.
class StealOrCounter extends XEffect {
  const StealOrCounter(this.maxEnergy, this.energy, this.power);
  final int maxEnergy;
  final int energy;
  final List<Domain?> power;
}

/// "Give it +1 {M} this turn for each of the following tags among your units - Bird, Cat, Dog,
/// and Poro."
class MightPerTags extends XEffect {
  const MightPerTags(this.target, this.n, this.tags);
  final Target target;
  final int n;
  final List<String> tags;
}

/// "Look at the top 5 cards of your Main Deck. You may banish a unit from among them, then play
/// it, reducing its cost by {5}. Recycle the remaining cards." With [kill]: first "Kill a friendly
/// unit", and the unit played may have Might up to [mightPlus] more than it.
class LookPlay extends XEffect {
  const LookPlay(this.n, this.types, {this.reduceEnergy = 0, this.ignoreAll = false, this.kill, this.mightPlus = 0});
  final int n;
  final Set<CardType> types;
  final int reduceEnergy;
  final bool ignoreAll;
  final Target? kill;
  final int mightPlus;
}

/// "Reveal the top 2 cards of your Main Deck. You may play one of them, reducing its cost by {2}.
/// Draw any you did not play this way."
class RevealPlay extends XEffect {
  const RevealPlay(this.n, this.reduceEnergy);
  final int n, reduceEnergy;
}

/// "Each player looks at the top 5 cards of their Main Deck, chooses one, then recycles the rest.
/// Starting with the next player, each player plays those cards, ignoring Energy costs."
class EachPlayerLookPlay extends XEffect {
  const EachPlayerLookPlay(this.n);
  final int n;
}
