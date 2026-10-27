part of 'ir.dart';

// The general grammar's part of the IR (parser/general.dart reads text into these;
// game/general.dart executes them). Each family has an abstract base class so the core
// switches need one line each.

// ---------------------------------------------------------------------------------------------
// Costs
// ---------------------------------------------------------------------------------------------

/// A cost other than Energy, Power, exhausting or killing the source.
abstract class CostPart {
  const CostPart();
  String describe();
}

/// "Discard N" / "Discard a gear" (CR 423.3: it must be possible to pay).
class DiscardCost extends CostPart {
  const DiscardCost(this.n, {this.filter});
  final int n;

  /// Only cards matching this (a gear).
  final Filter? filter;
  @override
  String describe() => 'discard $n${filter == null ? '' : ' ${filter!.describe()}'}';
}

/// "Recycle N from your trash" / "Recycle a unit from your trash" (CR 417.3).
class RecycleTrashCost extends CostPart {
  const RecycleTrashCost(this.n, {this.filter});
  final int n;
  final Filter? filter;
  @override
  String describe() => 'recycle $n from trash${filter == null ? '' : ' (${filter!.describe()})'}';
}

/// "Kill a friendly unit or gear" as a cost.
class KillCost extends CostPart {
  const KillCost(this.filter);
  final Filter filter;
  @override
  String describe() => 'kill ${filter.describe()}';
}

/// "Exhaust a unit you control" as a cost.
class ExhaustCost extends CostPart {
  const ExhaustCost(this.filter);
  final Filter filter;
  @override
  String describe() => 'exhaust ${filter.describe()}';
}

/// "Spend my buff" (CR 703: remove my buff counter).
class SpendMyBuffCost extends CostPart {
  const SpendMyBuffCost();
  @override
  String describe() => 'spend my buff';
}

// ---------------------------------------------------------------------------------------------
// Players
// ---------------------------------------------------------------------------------------------

/// Which player(s) an effect is about.
sealed class PRef {
  const PRef();
}

class PYou extends PRef {
  const PYou();
}

/// "An opponent" in a duel: the other player (CR 487).
class POpponent extends PRef {
  const POpponent();
}

/// "Each player", starting with the controller (turn order).
class PEach extends PRef {
  const PEach();
}

/// The player chosen in [slot] ("choose a player. They …").
class PChosen extends PRef {
  const PChosen(this.slot);
  final int slot;
}

/// The controller (or owner) of the object in [target] ("its controller draws 2").
class PControllerOf extends PRef {
  const PControllerOf(this.target, {this.owner = false});
  final Target target;
  final bool owner;
}

/// The player a trigger is about ("that player channels 1 rune", "they may…").
class PEvent extends PRef {
  const PEvent();
}

// ---------------------------------------------------------------------------------------------
// Targets
// ---------------------------------------------------------------------------------------------

abstract class GenTarget extends Target {
  const GenTarget();
  String describe();
}

/// "Up to N …", "two … each", "any number of …": choices in slots [slot] to [slot]+[max]-1.
class ChooseMany extends GenTarget {
  const ChooseMany(this.filter, {required this.slot, required this.max, this.min = 0, this.sameLocation = false, this.totalMightMax});
  final Filter filter;
  final int slot, max, min;

  /// "At the same location".
  final bool sameLocation;

  /// "With total Might N or less".
  final int? totalMightMax;
  @override
  String describe() => '${min == max ? '$max' : '$min–$max'} ${filter.describe()}';
}

/// Everything chosen in slots [slot] to [slot]+[n]-1 ("them", "those units").
class ChosenAll extends GenTarget {
  const ChosenAll(this.slot, this.n);
  final int slot, n;
  @override
  String describe() => 'them';
}

/// The controller's legend ("ready your legend"; not a target, CR 355.10.g).
class YourLegend extends GenTarget {
  const YourLegend();
  @override
  String describe() => 'your legend';
}

/// A legend chosen as it's played ("ready or exhaust a legend").
class ChooseLegend extends GenTarget {
  const ChooseLegend(this.slot, {this.side = Side.any});
  final int slot;
  final Side side;
  @override
  String describe() => 'a ${side == Side.any ? '' : '${side.name} '}legend';
}

/// "Something else that's exhausted" / "something besides me": a unit, gear, rune or legend.
class ChooseAnything extends GenTarget {
  const ChooseAnything(this.slot, {this.exhausted, this.notMe = false, this.side = Side.friendly});
  final int slot;
  final bool? exhausted;
  final bool notMe;
  final Side side;
  @override
  String describe() => 'something${notMe ? ' else' : ''}${exhausted == true ? ' exhausted' : ''}';
}

/// A battlefield chosen as it's played (its board object is stored in [slot]).
class ChooseBf extends GenTarget {
  const ChooseBf(this.slot, {this.withYourUnits = false, this.youControl = false});
  final int slot;
  final bool withYourUnits, youControl;
  @override
  String describe() => 'a battlefield${withYourUnits ? ' with your units' : ''}${youControl ? ' you control' : ''}';
}

/// The unit that died, was played … in a trigger, when [EventUnit] doesn't fit (gear too).
class EventObj extends GenTarget {
  const EventObj();
  @override
  String describe() => 'that';
}

/// A player chosen as it's played ("choose a player"); the slot holds the player's index.
class ChoosePlayer extends GenTarget {
  const ChoosePlayer(this.slot, {this.opponent = false});
  final int slot;
  final bool opponent;
  @override
  String describe() => 'a${opponent ? 'n opponent' : ' player'}';
}

/// A choice with no effect of its own ("Choose a friendly unit."): later sentences use it.
class ChooseOnly extends GenEffect {
  const ChooseOnly(this.chosen);
  final List<Target> chosen;
  @override
  List<Target> get targets => chosen;
  @override
  String describe() => 'choose ${chosen.map(describeTargetGen).join(' and ')}';
}

/// A spell on the chain chosen as it's played ("counter a spell that…").
class ChooseSpell extends GenTarget {
  const ChooseSpell(this.slot, {this.enemy = false, this.abilities = false, this.choosingFriendly = false, this.choosingSlot});
  final int slot;
  final bool enemy;

  /// Spells or abilities.
  final bool abilities;

  /// "That chooses a friendly unit or gear".
  final bool choosingFriendly;

  /// "That chooses it (the unit in this slot) and no other friendly unit".
  final int? choosingSlot;
  @override
  String describe() => 'a ${enemy ? 'enemy ' : ''}spell${abilities ? ' or ability' : ''}';
}

// ---------------------------------------------------------------------------------------------
// Amounts
// ---------------------------------------------------------------------------------------------

abstract class GenAmount extends Amount {
  const GenAmount();
  String describe();
}

/// "For each …": [per] times the number of matching objects (plus [plus]).
class CountOf extends GenAmount {
  const CountOf(this.filter, {this.per = 1, this.plus = 0});
  final Filter filter;
  final int per, plus;
  @override
  String describe() => '${plus == 0 ? '' : '$plus+'}$per×#(${filter.describe()})';
}

/// The Might (or Energy cost) of the object in a target.
class MightOf extends GenAmount {
  const MightOf(this.target, {this.cost = false});
  final Target target;
  final bool cost;
  @override
  String describe() => '${cost ? 'cost' : 'Might'} of ${describeTargetGen(target)}';
}

/// A number about a player: points, cards in trash, runes, battlefields controlled …
class PlayerStat extends GenAmount {
  const PlayerStat(this.stat, {this.per = 1, this.plus = 0});
  final Stat stat;
  final int per, plus;
  @override
  String describe() => '${plus == 0 ? '' : '$plus+'}$per×${stat.name}';
}

enum Stat { points, trash, runes, battlefields, tagsAmongUnits, mightyUnits, excess }

/// The amount chosen or paid earlier in the ability ("that much").
class ThatMuch extends GenAmount {
  const ThatMuch();
  @override
  String describe() => 'that much';
}

String describeTargetGen(Target t) => switch (t) {
  Me() => 'me',
  Choose(:final filter) => 'a ${filter.describe()}',
  Chosen() => 'it',
  Each(:final filter) => 'each ${filter.describe()}',
  EventUnit() => 'that unit',
  GenTarget() => t.describe(),
};

// ---------------------------------------------------------------------------------------------
// Effects
// ---------------------------------------------------------------------------------------------

abstract class GenEffect extends Effect {
  const GenEffect();

  /// Choices made as it's played, in text order: targets, then [dests].
  List<Target> get targets => const [];

  /// Effects inside this one (their choices are made with it).
  List<List<Effect>> get nested => const [];
  String describe();
}

/// "Deal N to …" with any amount, or "deal damage equal to its Might".
class DealAmt extends GenEffect {
  const DealAmt(this.amount, this.target, {this.source});
  final Amount amount;
  final Target target;

  /// The unit dealing it ("it deals damage equal to its Might to …"), for Bonus Damage and kills.
  final Target? source;
  @override
  List<Target> get targets => [?source, target];
  @override
  String describe() => 'deal ${amount is N ? (amount as N).n : (amount is GenAmount ? (amount as GenAmount).describe() : 'my Might')} to ${describeTargetGen(target)}';
}

/// Two units deal damage equal to their Mights to each other (CR 418.6.b.3).
class Fight extends GenEffect {
  const Fight(this.a, this.b);
  final Target a, b;
  @override
  List<Target> get targets => [a, b];
  @override
  String describe() => '${describeTargetGen(a)} and ${describeTargetGen(b)} fight';
}

/// "Give … +N {M} this turn" for an amount ("for each", "equal to its Might", "double").
class GiveMightAmt extends GenEffect {
  const GiveMightAmt(this.amount, this.target, {this.negative = false});
  final Amount amount;
  final Target target;
  final bool negative;
  @override
  List<Target> get targets => [target];
  @override
  String describe() => 'give ${describeTargetGen(target)} ${negative ? '-' : '+'}${amount is GenAmount ? (amount as GenAmount).describe() : '?'} Might this turn';
}

/// "Double …'s Might this turn" (CR 433).
class DoubleMight extends GenEffect {
  const DoubleMight(this.target);
  final Target target;
  @override
  List<Target> get targets => [target];
  @override
  String describe() => 'double ${describeTargetGen(target)} Might this turn';
}

/// Where a move goes.
enum Dest {
  /// Its base.
  base,

  /// Chosen as it's played: any other location it may be at.
  any,

  /// A battlefield chosen as it's played.
  battlefield,

  /// Its owner's base? No: a battlefield you control.
  yourBattlefield,

  /// The source's location ("here", "this battlefield").
  here,

  /// The location of the object in [Move.destSlot] (a chosen battlefield or unit).
  slot,

  /// The battlefield the trigger is about ("that battlefield").
  event,

  /// A battlefield other than its current one.
  otherBattlefield,
}

/// "Move … [to …]" (CR 421, 447–455). The destination is chosen as it's played (CR 355.4),
/// stored in [destSlot] (0 for a base, else the battlefield's object).
class Move extends GenEffect {
  const Move(this.target, this.dest, {required this.destSlot, this.refSlot});
  final Target target;
  final Dest dest;
  final int destSlot;

  /// For [Dest.slot]: the slot whose object's location is the destination.
  final int? refSlot;
  @override
  List<Target> get targets => [target];
  @override
  String describe() => 'move ${describeTargetGen(target)} to ${dest.name}${refSlot == null ? '' : ' #$refSlot'}';
}

/// "Banish …" (CR 428) from the board.
class Banish extends GenEffect {
  const Banish(this.target);
  final Target target;
  @override
  List<Target> get targets => [target];
  @override
  String describe() => 'banish ${describeTargetGen(target)}';
}

/// Cards from a zone to their owner's hand ("return a unit from your trash to your hand").
class CardToHand extends GenEffect {
  const CardToHand(this.target);
  final Target target;
  @override
  List<Target> get targets => [target];
  @override
  String describe() => 'return ${describeTargetGen(target)} to hand';
}

/// "Draw N" / "draw N for each …" for a player.
class DrawAmt extends GenEffect {
  const DrawAmt(this.amount, {this.who = const PYou()});
  final Amount amount;
  final PRef who;
  @override
  String describe() => 'draw ${amount is N ? (amount as N).n : (amount as GenAmount).describe()}${who is PYou ? '' : ' (${who.runtimeType})'}';
}

/// A player discards ("They discard 1", "Each player discards their hand").
class DiscardP extends GenEffect {
  const DiscardP(this.n, this.who, {this.hand = false});
  final int n;
  final PRef who;
  final bool hand;
  @override
  String describe() => 'discard ${hand ? 'hand' : '$n'}';
}

/// A player channels ("each player channels 1 rune exhausted"), with "if you couldn't, draw".
class ChannelP extends GenEffect {
  const ChannelP(this.n, this.who, {this.exhausted = false, this.elseDraw = 0});
  final int n;
  final PRef who;
  final bool exhausted;
  final int elseDraw;
  @override
  String describe() => 'channel $n${exhausted ? ' exhausted' : ''}${elseDraw > 0 ? ' else draw $elseDraw' : ''}';
}

/// A player scores ([GainPoints] for someone else, or "you win the game").
class ScoreP extends GenEffect {
  const ScoreP(this.n, this.who, {this.win = false});
  final int n;
  final PRef who;
  final bool win;
  @override
  String describe() => win ? 'win the game' : 'score $n';
}

/// Play tokens for a player ("They play a 1 {M} Bird", "Play four Gold gear tokens").
class TokenP extends GenEffect {
  const TokenP(this.token, this.count, this.who, {this.ready = false, this.where = TokenAt.base, this.kws = const []});
  final String token;
  final int count;
  final PRef who;
  final bool ready;
  final TokenAt where;
  final List<Kw> kws;
  @override
  String describe() => 'play $count $token${ready ? ' ready' : ''} @${where.name}';
}

enum TokenAt { base, here, there, event }

/// Look at (or reveal) the top [n]: pick up to [pick] matching [filter] to hand (or to play),
/// the rest go to [rest].
class LookTop extends GenEffect {
  const LookTop(
    this.n, {
    this.pick = 0,
    this.filter,
    this.mayPick = true,
    this.rest = Rest.recycle,
    this.play = false,
    this.costLess = 0,
    this.restToHand = false,
    this.revealed = false,
    this.reorder = false,
    this.picked = const [],
  });
  final int n, pick;
  final Filter? filter;
  final bool mayPick;
  final Rest rest;

  /// Play the picked card (ignoring its cost unless [costLess] > 0, which reduces it instead).
  final bool play;
  final int costLess;

  /// "Draw any you did not play this way".
  final bool restToHand;
  final bool revealed;

  /// "Put those you don't back in any order": the rest go back on top.
  final bool reorder;

  /// Effects if a card was picked ("then if you revealed a Bird…, do this").
  final List<Effect> picked;
  @override
  List<List<Effect>> get nested => [picked];
  @override
  String describe() => 'look at top $n: ${pick > 0 ? '${mayPick ? 'may ' : ''}${play ? 'play' : 'take'} $pick${filter == null ? '' : ' ${filter!.describe()}'}' : ''} rest→${rest.name}';
}

enum Rest { recycle, trash, top }

/// "Reveal the top card. If it's a [filter], [yes]. Otherwise, [no]."
class RevealTop extends GenEffect {
  const RevealTop(this.filter, this.yes, this.no);
  final Filter filter;
  final RevealDo yes, no;
  @override
  String describe() => 'reveal top: ${filter.describe()} → ${yes.name} else ${no.name}';
}

enum RevealDo { hand, recycle, trash, trashAndMight2 }

/// "Put the top N cards of your Main Deck into your trash" / [Burn N] (CR 441).
class Mill extends GenEffect {
  const Mill(this.n, {this.who = const PYou()});
  final int n;
  final PRef who;
  @override
  String describe() => 'burn $n';
}

/// "Recycle N from your trash" (an effect: as many as possible, CR 417.4).
class RecycleTrash extends GenEffect {
  const RecycleTrash(this.n);
  final int n;
  @override
  String describe() => 'recycle $n from trash';
}

/// "Recycle one of your runes".
class RecycleRune extends GenEffect {
  const RecycleRune();
  @override
  String describe() => 'recycle a rune';
}

/// "Each player kills one of their units/gear", "Each player chooses a unit they control. Kill the rest."
class EachKills extends GenEffect {
  const EachKills(this.filter, {this.keepOne = false});
  final Filter filter;
  final bool keepOne;
  @override
  String describe() => keepOne ? 'each player keeps one ${filter.describe()}, kill the rest' : 'each player kills one ${filter.describe()}';
}

/// Play a card from a zone ("play a unit from your trash, ignoring its Energy cost").
class PlayFrom extends GenEffect {
  const PlayFrom(this.target, {this.ignoreAll = false, this.payPower = true, this.to = TokenAt.base, this.free = true});
  final Target target;

  /// Ignoring all costs, or only the Energy cost (Power still due).
  final bool ignoreAll;
  final bool payPower;
  final TokenAt to;
  final bool free;
  @override
  List<Target> get targets => [target];
  @override
  String describe() => 'play ${describeTargetGen(target)}${ignoreAll ? ' free' : ' ignoring energy'}';
}

/// "Banish a friendly unit, then its owner plays it [to …], ignoring its cost."
class Blink extends GenEffect {
  const Blink(this.target, {this.to = Dest.base});
  final Target target;
  final Dest to;
  @override
  List<Target> get targets => [target];
  @override
  String describe() => 'banish and replay ${describeTargetGen(target)}';
}

/// "Take control of it and recall it."
class TakeControl extends GenEffect {
  const TakeControl(this.target);
  final Target target;
  @override
  List<Target> get targets => [target];
  @override
  String describe() => 'take control of ${describeTargetGen(target)}';
}

/// "Its owner places it on the top or bottom of their Main Deck."
class ToDeck extends GenEffect {
  const ToDeck(this.target);
  final Target target;
  @override
  List<Target> get targets => [target];
  @override
  String describe() => 'put ${describeTargetGen(target)} on top or bottom of its deck';
}

/// Ready (or exhaust) a legend or something that isn't a unit.
class ReadyAny extends GenEffect {
  const ReadyAny(this.target, {this.exhaust = false, this.either = false});
  final Target target;
  final bool exhaust;

  /// "Ready or exhaust".
  final bool either;
  @override
  List<Target> get targets => [target];
  @override
  String describe() => '${either ? 'ready or exhaust' : (exhaust ? 'exhaust' : 'ready')} ${describeTargetGen(target)}';
}

/// "If [cond], [yes]. Otherwise, [no]" (also "… instead").
class IfElse extends GenEffect {
  const IfElse(this.cond, this.yes, this.no);
  final Cond cond;
  final List<Effect> yes, no;
  @override
  List<List<Effect>> get nested => [yes, no];
  @override
  String describe() => 'if ${describeCondGen(cond)}: ${yes.map(describeEffect).join(', ')}${no.isEmpty ? '' : ' else ${no.map(describeEffect).join(', ')}'}';
}

/// A triggered ability's condition (CR 383.2.a.1): checked as it triggers, not on resolution.
class TrigIf extends GenEffect {
  const TrigIf(this.cond, this.effects);
  final Cond cond;
  final List<Effect> effects;
  @override
  List<List<Effect>> get nested => [effects];
  @override
  String describe() => '[if ${describeCondGen(cond)}] ${effects.map(describeEffect).join(', ')}';
}

/// "You may pay {cost} [and exhaust me] to [effects]" / "You may [cost-action] to [effects]":
/// a cost within instructions (CR 355.10.c.1); the effects need it paid.
class PayTo extends GenEffect {
  const PayTo(this.effects, {this.energy = 0, this.power = const [], this.exhaustMe = false, this.parts = const [], this.anyAmount = false, this.optional = true});
  final List<Effect> effects;
  final int energy;
  final List<Domain?> power;
  final bool exhaustMe;
  final List<CostAction> parts;

  /// "Pay any amount of {A}": the amount paid is [ThatMuch].
  final bool anyAmount;
  final bool optional;
  @override
  List<List<Effect>> get nested => [effects];
  @override
  String describe() =>
      '${optional ? 'may ' : ''}pay ${[if (energy > 0) '{$energy}', for (final p in power) '{${p?.letter ?? 'A'}}', if (exhaustMe) 'exhaust me', if (anyAmount) 'X{A}', for (final x in parts) x.describe()].join(' ')} to ${effects.map(describeEffect).join(', ')}';
}

/// Actions used as costs inside instructions ("kill me to …", "spend a buff to …").
class CostAction {
  const CostAction(this.kind, {this.n = 1, this.filter});
  final CostKind kind;
  final int n;
  final Filter? filter;
  String describe() => '${kind.name}${n > 1 ? ' $n' : ''}${filter == null ? '' : ' ${filter!.describe()}'}';
}

enum CostKind { killMe, recycleMe, discard, burn, spendBuff, killOne, recycleUnit, killMany }

/// "Do this for each …" / "For each buff spent, …": repeat [effects] [times] times.
class Repeat extends GenEffect {
  const Repeat(this.times, this.effects);
  final Amount times;
  final List<Effect> effects;
  @override
  List<List<Effect>> get nested => [effects];
  @override
  String describe() => '${(times as GenAmount?)?.describe() ?? times}× ${effects.map(describeEffect).join(', ')}';
}

/// Several effects that all must be readable, run in order (used to group "and").
class Seq extends GenEffect {
  const Seq(this.effects);
  final List<Effect> effects;
  @override
  List<List<Effect>> get nested => [effects];
  @override
  String describe() => effects.map(describeEffect).join(' and ');
}

/// A "this turn" rule set up by a spell or ability: a delayed trigger or passive (CR 390–393).
class Delay extends GenEffect {
  const Delay(this.kind, {this.effects = const [], this.target, this.n = 0, this.filter});
  final DelayKind kind;

  /// What happens when it triggers (for delayed triggers).
  final List<Effect> effects;
  final Target? target;
  final int n;
  final Filter? filter;
  @override
  List<Target> get targets => [?target];
  @override
  List<List<Effect>> get nested => [effects];
  @override
  String describe() => 'this turn: ${kind.name}${target == null ? '' : ' ${describeTargetGen(target!)}'}${n == 0 ? '' : ' $n'}${effects.isEmpty ? '' : ' → ${effects.map(describeEffect).join(', ')}'}';
}

enum DelayKind {
  /// "When it dies this turn, …".
  whenDies,

  /// "When a friendly unit is played this turn, …".
  whenFriendlyPlayed,

  /// "Units you play this turn enter ready".
  unitsEnterReady,

  /// "The next unit you play this turn enters ready".
  nextUnitReady,

  /// "When any unit takes damage this turn, kill it".
  killDamaged,

  /// "Kill it the next time it takes damage this turn".
  killNextDamage,

  /// "Prevent the next N damage that would be dealt to it this turn" (N 0: all of the next).
  preventNext,

  /// "Prevent all spell and ability damage this turn".
  preventSpellDamage,

  /// "The next time it would die this turn, recall it exhausted (and heal it) instead".
  saveNextDeath,

  /// "If it would die this turn, banish it instead".
  banishIfDies,

  /// "The next spell you play this turn deals N Bonus Damage".
  nextSpellBonus,

  /// "At the end of this turn, …" / "at the start of your next Main Phase, …".
  atEndOfTurn,
  atNextMain,

  /// "Opponents can't play cards this turn" / "Its controller can't play spells this turn".
  noCards,
  noSpells,

  /// "They can't move it this turn".
  cantMove,
}

/// "Counter a spell unless its controller pays {N}", "… that chooses a friendly unit", "… if an
/// opponent has played another spell this turn", "Return it to its owner's hand instead".
class CounterIt extends GenEffect {
  const CounterIt(this.target, {this.unlessPay = 0, this.toHand = false, this.noSpells = false, this.giveMight});
  final Target target;
  final int unlessPay;
  final bool toHand;

  /// "Its controller can't play spells this turn".
  final bool noSpells;

  /// "And give that unit +{M} equal to that spell's Energy cost this turn".
  final Target? giveMight;
  @override
  List<Target> get targets => [target, ?giveMight];
  @override
  String describe() => 'counter ${describeTargetGen(target)}${unlessPay > 0 ? ' unless {$unlessPay}' : ''}${toHand ? ' to hand' : ''}';
}

/// "Choose an opponent. They reveal their hand. Choose a [filter] card from it, and they
/// [discard / recycle] that card." (The hand is revealed; the choice is made on resolution.)
class HandAttack extends GenEffect {
  const HandAttack({this.filter, this.recycle = false});
  final Filter? filter;
  final bool recycle;
  @override
  String describe() => 'look at their hand: ${recycle ? 'recycle' : 'discard'} a ${filter?.describe() ?? 'card'}';
}

/// "Look at the top N … you may recycle one or both … put those you don't back in any order".
class Predictish extends GenEffect {
  const Predictish(this.n);
  final int n;
  @override
  String describe() => 'look at top $n, recycle any';
}

/// "Spend any number of buffs. For each buff spent, …" / "Spend a buff to …" handled as costs;
/// this spends buffs as an effect and records how many ([ThatMuch]).
class SpendBuffs extends GenEffect {
  const SpendBuffs({this.any = true});
  final bool any;
  @override
  String describe() => 'spend buffs';
}

/// "Take a turn after this one."
class ExtraTurn extends GenEffect {
  const ExtraTurn();
  @override
  String describe() => 'take an extra turn';
}

/// "Give … [Temporary]" etc.: a lasting keyword (not just this turn).
class GiveKwLasting extends GenEffect {
  const GiveKwLasting(this.kw, this.target);
  final Kw kw;
  final Target target;
  @override
  List<Target> get targets => [target];
  @override
  String describe() => 'give ${describeTargetGen(target)} ${kw.name}';
}

/// "Give … [Keyword N] and [Keyword] this turn" with several keywords and Might.
class GiveMany extends GenEffect {
  const GiveMany(this.target, {this.might = 0, this.kws = const []});
  final Target target;
  final int might;
  final List<(Kw, int)> kws;
  @override
  List<Target> get targets => [target];
  @override
  String describe() => 'give ${describeTargetGen(target)}${might == 0 ? '' : ' ${might > 0 ? '+' : ''}$might Might'}${kws.map((k) => ' ${k.$1.name}${k.$2 > 1 ? ' ${k.$2}' : ''}').join()} this turn';
}

// ---------------------------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------------------------

abstract class GenCond extends Cond {
  const GenCond();
  String describe();
}

String describeCondGen(Cond c) => switch (c) {
  HandAtMost(:final n) => 'hand ≤ $n',
  UnitsThere(:final n) => '$n+ units there',
  GenCond() => c.describe(),
};

enum CmpOp { ge, le, eq, gt, lt }

/// Count of matching objects compared with a number ("if you control 2 or more gear").
class CountCond extends GenCond {
  const CountCond(this.filter, this.op, this.n);
  final Filter filter;
  final CmpOp op;
  final int n;
  @override
  String describe() => '#(${filter.describe()}) ${op.name} $n';
}

/// A player number compared ("if you control 4 or fewer runes", "7+ runes", hand size).
class StatCond extends GenCond {
  const StatCond(this.stat, this.op, this.n, {this.who = const PYou()});
  final PStat stat;
  final CmpOp op;
  final int n;
  final PRef who;
  @override
  String describe() => '${stat.name} ${op.name} $n';
}

enum PStat {
  runes,
  hand,
  trash,
  points,
  pointsToWin,
  unitsAtBattlefields,
  fewerRunesThanOpp,
  spentThisTurn,
  maxSpellSpend,
  discardedThisTurn,
  cardsPlayedThisTurn,
  spellsPlayedByOppThisTurn,
  turnNumber,
  controlsBattlefield,
  oppControlsBattlefield,
  powerSpentThisTurn,
  oppSpellsCast,
  choseEnemy,
}

/// Something about the object in a target ("if it is stunned", "if it had 3 {M} or less",
/// "if it was an enemy unit", "if I am at a battlefield").
class ObjCond extends GenCond {
  const ObjCond(this.target, this.filter, {this.negate = false});
  final Target target;
  final Filter filter;
  final bool negate;
  @override
  String describe() => '${negate ? 'not ' : ''}${describeTargetGen(target)} is ${filter.describe()}';
}

/// About the source unit's death or situation ("if I died alone", "if I was [Mighty]").
class SelfCond extends GenCond {
  const SelfCond(this.kind, {this.negate = false, this.n = 0});
  final SelfKind kind;
  final bool negate;
  final int n;
  @override
  String describe() => '${negate ? 'not ' : ''}${kind.name}${n == 0 ? '' : ' $n'}';
}

enum SelfKind { alone, mighty, buffed, atBattlefield, attackingWithAnother, attackingOrDefendingAlone, anotherHere, inShowdown, notDamagedThisTurn, inCombat, exactlyOneOtherHere, movedTwice }

/// The outcome of what the ability just did ("if you do", "if this kills it", "if you
/// couldn't channel …", "if it was buffed this way").
class DidCond extends GenCond {
  const DidCond(this.kind, {this.negate = false});
  final DidKind kind;
  final bool negate;
  @override
  String describe() => '${negate ? 'not ' : ''}${kind.name}';
}

enum DidKind { paid, killed, channeledAll, picked }

/// "If a unit died this turn" / "If a friendly unit died during your Beginning Phase".
class TurnEventCond extends GenCond {
  const TurnEventCond(this.kind);
  final TurnEvent kind;
  @override
  String describe() => kind.name;
}

enum TurnEvent { unitDied, friendlyDiedInBeginning, isBeginningPhase, playedUnitGearSpell, assignedExcess3, assignedExcess5, afterAttack }

/// All of / any of.
class AndCond extends GenCond {
  const AndCond(this.conds);
  final List<Cond> conds;
  @override
  String describe() => conds.map(describeCondGen).join(' and ');
}

/// "Your units have all of the following tags among them - Bird, Cat, Dog, and Poro".
class TagsAmongCond extends GenCond {
  const TagsAmongCond(this.tags, {this.n = 0});
  final List<String> tags;

  /// How many of them (0: all).
  final int n;
  @override
  String describe() => 'tags among units: ${tags.join('/')}';
}

/// "If your other units have total Might N or more".
class TotalMightCond extends GenCond {
  const TotalMightCond(this.filter, this.n);
  final Filter filter;
  final int n;
  @override
  String describe() => 'total Might of ${filter.describe()} ≥ $n';
}

// ---------------------------------------------------------------------------------------------
// Triggers
// ---------------------------------------------------------------------------------------------

/// Events the general triggers listen for.
enum GEv {
  /// A unit dies ([GenWhen.filter]: which).
  dies,

  /// A unit, gear or card is played ([GenWhen.filter] on the played object; [GenWhen.by]).
  played,

  /// A spell is played (finished, CR 420.4).
  spellPlayed,

  /// You buff a unit ([GenWhen.filter]).
  buffed,

  /// A unit becomes ready.
  readied,

  /// A unit is chosen by a spell or ability ([GenWhen.by]: who chose).
  chosen,

  /// A card is discarded.
  discarded,

  /// A unit is stunned by you.
  stunned,

  /// A unit moves ([GenWhen.from]/[GenWhen.to] the source's location).
  moved,

  /// You conquer or hold.
  conquerOrHold,

  /// "When you defend here / at a battlefield".
  defend,

  /// "When combat starts here" / "When a showdown begins here".
  combatHere,
  showdownHere,

  /// At the start of each player's Beginning Phase (or only their first).
  startOfEachTurn,

  /// At the start of your Main Phase.
  startOfMain,

  /// You draw your second card in a turn.
  drawSecond,

  /// You recycle cards (or a rune).
  recycled,

  /// An opponent scores.
  oppScores,

  /// This leaves the board.
  leaves,

  /// You spend a buff.
  spentBuff,

  /// You use an activated ability of a gear.
  gearAbility,

  /// You kill a unit (with a spell; a stunned enemy unit).
  youKill,

  /// "When a unit you control becomes [Mighty]".
  becomesMighty,

  /// "When an opponent moves to a battlefield other than mine".
  oppMoves,

  /// "When a unit here is returned to a player's hand".
  returnedHere,

  /// A unit attacks or defends alone.
  aloneInCombat,

  /// "When you defend at a battlefield" (any battlefield; "there" is it).
  defendAnywhere,

  /// "When a player plays a spell" (anyone).
  anySpell,
}

class GenWhen extends When {
  const GenWhen(
    this.ev, {
    this.filter,
    this.by = Side.friendly,
    this.self = false,
    this.here = false,
    this.limit = 0,
    this.nth = 0,
    this.extra = const [],
    this.alsoOn = const [],
    this.firstOnly = false,
    this.oppTurn = false,
    this.inShowdown = false,
    this.withTrash = false,
  }) : super(On.general);
  final GEv ev;

  /// The object the event is about must match (null: anything).
  final Filter? filter;

  /// Whose action: friendly (you), enemy (an opponent), any.
  final Side by;

  /// The event is about the source itself ("when you buff me", "when I become ready").
  final bool self;

  /// At the source's location ("here").
  final bool here;

  /// "The first time … each turn" (1), "Once each turn" (1); 0: no limit.
  final int limit;

  /// "The third time I move in a turn": triggers on exactly this count.
  final int nth;

  /// Extra details (e.g. "spell" for "when you kill a unit with a spell").
  final List<String> extra;

  /// Core events that also trigger it ("When you play me or when I hold").
  final List<On> alsoOn;

  /// "Each player's first Beginning Phase".
  final bool firstOnly;

  /// "On an opponent's turn".
  final bool oppTurn;

  /// "During a showdown".
  final bool inShowdown;

  /// Active from the trash (CR 385.2).
  final bool withTrash;

  /// "It" means the event's object.
  bool get eventUnit => !self;
  String describe() =>
      '${ev.name}${self ? ' (me)' : ''}${filter == null ? '' : ' ${filter!.describe()}'}${by == Side.friendly ? '' : ' by ${by.name}'}${here ? ' here' : ''}${limit > 0 ? ' ×$limit/turn' : ''}${nth > 0 ? ' #$nth' : ''}${alsoOn.isEmpty ? '' : ' or ${alsoOn.map((o) => o.name).join('/')}'}';
}

// ---------------------------------------------------------------------------------------------
// Passives
// ---------------------------------------------------------------------------------------------

abstract class GenPassive extends Passive {
  const GenPassive();
  String describe();
}

/// "[Filter] have +N {M} / [Keywords]" with conditions on the source ("While I'm at a battlefield,
/// your other units here have [Deflect]"; "Units here have +1 {M}"; "Your token units have [Tank]").
class GAnthem extends GenPassive {
  const GAnthem(this.filter, {this.might = 0, this.kws = const [], this.cond, this.mightFloor, this.ifNotAlready = false});
  final Filter filter;
  final int might;
  final List<(Kw, int)> kws;
  final Cond? cond;

  /// "To a minimum of N {M}".
  final int? mightFloor;

  /// "If they didn't already" (the keyword isn't added twice).
  final bool ifNotAlready;
  @override
  String describe() =>
      '${cond == null ? '' : 'while ${describeCondGen(cond!)}: '}${filter.describe()} have${might == 0 ? '' : ' ${might > 0 ? '+' : ''}$might Might'}${kws.map((k) => ' ${k.$1.name}${k.$2 > 1 ? ' ${k.$2}' : ''}').join()}';
}

/// "I have +N {M} / [Keywords] while …", "My Might is increased by …", "I have [Assault] equal to …".
class SelfBoost extends GenPassive {
  const SelfBoost({this.might, this.kws = const [], this.cond, this.kwAmount});
  final Amount? might;
  final List<(Kw, int)> kws;
  final Cond? cond;

  /// A keyword whose value is an amount ("[Assault] equal to the number of …").
  final (Kw, Amount)? kwAmount;
  @override
  String describe() =>
      '${cond == null ? '' : 'while ${describeCondGen(cond!)}: '}I have${might == null ? '' : ' +${might is N ? (might as N).n : (might as GenAmount).describe()} Might'}${kws.map((k) => ' ${k.$1.name}').join()}${kwAmount == null ? '' : ' ${kwAmount!.$1.name}=${(kwAmount!.$2 as GenAmount).describe()}'}';
}

/// "I enter ready if …" / "If …, I enter ready." / "Other friendly units enter ready" / "Your
/// tokens enter ready".
class EnterReady extends GenPassive {
  const EnterReady({this.cond, this.others});
  final Cond? cond;

  /// Others that enter ready (null: me).
  final Filter? others;
  @override
  String describe() => '${others == null ? 'I' : others!.describe()} enter ready${cond == null ? '' : ' if ${describeCondGen(cond!)}'}';
}

/// Rules restrictions.
class Restrict extends GenPassive {
  const Restrict(this.kind, {this.cond, this.n = 0});
  final RKind kind;
  final Cond? cond;
  final int n;
  @override
  String describe() => '${kind.name}${n == 0 ? '' : ' $n'}${cond == null ? '' : ' while ${describeCondGen(cond!)}'}';
}

enum RKind {
  /// "I can't be chosen by enemy spells and abilities" ([Restrict.cond]: unless).
  untargetable,

  /// "I can't move to base."
  cantMoveToBase,

  /// "Units can't move to base." / "Units can't move from here to base."
  noneMoveToBase,
  noneMoveFromHereToBase,

  /// "I can't be readied."
  cantBeReadied,

  /// "Units can't be played here."
  noPlayHere,

  /// "I can't be played on your first, second, or third turns."
  notBeforeTurn4,

  /// "Play me only to a battlefield you conquered this turn."
  onlyToConquered,

  /// "Players can't score here until their third turn."
  noScoreBeforeTurn3,

  /// "While I'm at a battlefield, opponents can't score points."
  oppCantScore,

  /// "Increase the points needed to win the game by N."
  victoryPlus,

  /// "Your spells and abilities deal N Bonus Damage."
  bonusDamage,

  /// "Spells and abilities affecting units here each deal N Bonus Damage."
  bonusDamageHere,

  /// "I don't deal combat damage unless …".
  noCombatDamageUnless,

  /// "I can be played to a battlefield you're attacking."
  playToAttacked,

  /// "I can have any number of buffs."
  manyBuffs,

  /// "Use my abilities only while I'm at a battlefield."
  abilitiesOnlyAtBf,

  /// "You ignore [Tank] while assigning combat damage here."
  ignoreTankHere,

  /// "Your [Deathknell] effects trigger an additional time."
  deathknellTwice,

  /// "Your conquer/hold effects for conquering/holding here trigger an additional time."
  conquerTwiceHere,
  holdTwiceHere,

  /// "While I'm at a battlefield, opponents can only play units to their base."
  oppUnitsOnlyToBase,

  /// "While I'm at a battlefield, spells and abilities can't ready enemy units and gear."
  noReadyEnemies,

  /// "While a unit here is defending alone, it has -N {M}."
  loneDefenderMinus,

  /// "Any amount of your damage is enough to kill enemy units."
  anyDamageKills,

  /// "Stunned enemy units here have -N {M}, to a minimum of 1 {M}."
  stunnedMinus,

  /// "While I'm at a battlefield, players only channel N rune …"
  channelOnly,

  /// "Skip your Draw Phase."
  skipDraw,
}

/// "While I'm at a battlefield, the Energy costs for spells you play is reduced by {N}, to a
/// minimum of {M}" / "Your Dragons' Energy costs are reduced by {N}, to a minimum of {M}".
class CostReduce extends GenPassive {
  const CostReduce(this.n, this.min, {this.filter, this.spells = false, this.cond});
  final int n, min;
  final Filter? filter;
  final bool spells;
  final Cond? cond;
  @override
  String describe() => '${spells ? 'spells' : filter?.describe()} cost {$n} less (min $min)';
}

/// "Deal N to each other enemy unit there/here" (not the one chosen in slot [except]).
class ExceptDeal extends GenEffect {
  const ExceptDeal(this.n, this.filter, this.except);
  final int n;
  final Filter filter;
  final int except;
  @override
  String describe() => 'deal $n to each other ${filter.describe()}';
}

/// "Then deal N to up to one other unit" (not the one chosen in slot [except]).
class DealOther extends GenEffect {
  const DealOther(this.n, this.target, this.except);
  final int n;
  final Target target;
  final int except;
  @override
  List<Target> get targets => [target];
  @override
  String describe() => 'deal $n to ${describeTargetGen(target)} (not #$except)';
}

/// My [Assault] value as an amount.
class MyAssault extends GenAmount {
  const MyAssault();
  @override
  String describe() => 'my Assault';
}

/// "I enter ready if you have a card with my name in your trash".
class NameInTrash extends GenCond {
  const NameInTrash();
  @override
  String describe() => 'a card with my name in your trash';
}

/// The source itself wherever it is (a legend, or a card in the trash: "play me", "ready me").
class SelfAny extends GenTarget {
  const SelfAny();
  @override
  String describe() => 'me';
}

/// "Use this ability only while I'm at a battlefield" / "Use only if …": an activated ability's
/// restriction, checked as it's activated; [effects] are what it does.
class UseOnly extends GenEffect {
  const UseOnly(this.cond, this.effects, {this.once = false});
  final Cond cond;
  final List<Effect> effects;
  final bool once;
  @override
  List<List<Effect>> get nested => [effects];
  @override
  String describe() => '[only if ${describeCondGen(cond)}${once ? ', once a turn' : ''}] ${effects.map(describeEffect).join('; ')}';
}

/// "Choose an opponent. They reveal their hand. Choose a [filter] card from it, and they
/// discard (or recycle) that card."
class HandPick extends GenEffect {
  const HandPick({this.filter, this.recycle = false});
  final Filter? filter;
  final bool recycle;
  @override
  String describe() => 'reveal their hand: ${recycle ? 'recycle' : 'discard'} a ${filter?.describe() ?? 'card'}';
}

/// "Banish this" at the end of a spell's instructions: it goes to banishment, not the trash.
class BanishThis extends GenEffect {
  const BanishThis();
  @override
  String describe() => 'banish this';
}

/// "This deals N Bonus Damage for each card with this name in your trash" (CR 712).
class BonusPerName extends GenEffect {
  const BonusPerName(this.n, this.effects);
  final int n;
  final List<Effect> effects;
  @override
  List<List<Effect>> get nested => [effects];
  @override
  String describe() => '+$n bonus damage per copy in trash: ${effects.map(describeEffect).join(', ')}';
}

/// "Deal N damage split among any number of [filter]" (one Deal action, CR 715.3).
class DealSplit extends GenEffect {
  const DealSplit(this.n, this.filter);
  final int n;
  final Filter filter;
  @override
  String describe() => 'deal $n split among ${filter.describe()}';
}

/// "Each player chooses a unit they control. Kill the rest." / "Each player kills one of their …".
class EachKeep extends GenEffect {
  const EachKeep(this.filter);
  final Filter filter;
  @override
  String describe() => 'each player keeps one ${filter.describe()}; kill the rest';
}

/// "For each friendly unit, you may spend its buff to ready it."
class SpendBuffsToReady extends GenEffect {
  const SpendBuffsToReady();
  @override
  String describe() => 'spend buffs to ready those units';
}

/// "Activate the conquer effects of units here" (CR 383.4.g).
class ActivateConquer extends GenEffect {
  const ActivateConquer();
  @override
  String describe() => 'activate conquer effects of units here';
}

/// "Recycle up to N cards from trashes".
class RecycleTrashes extends GenEffect {
  const RecycleTrashes(this.n);
  final int n;
  @override
  String describe() => 'recycle up to $n from trashes';
}

/// The Energy cost of the card just discarded ("Deal its Energy cost as damage").
class DiscardedCost extends GenAmount {
  const DiscardedCost();
  @override
  String describe() => 'discarded card\'s cost';
}

/// "If it is the only unit you control there".
class AloneCond extends GenCond {
  const AloneCond(this.target);
  final Target target;
  @override
  String describe() => '${describeTargetGen(target)} alone';
}

/// The current turn's combat facts: excess damage assigned, conquering after an attack.
class CombatCond extends GenCond {
  const CombatCond({this.excess = 0, this.afterAttack = false});
  final int excess;
  final bool afterAttack;
  @override
  String describe() => [if (afterAttack) 'after an attack', if (excess > 0) 'excess ≥ $excess'].join(', ');
}

/// "Opponents must pay …", "This can't be countered", and other rules about the card itself.
class CantBeCountered extends GenPassive {
  const CantBeCountered();
  @override
  String describe() => 'can\'t be countered';
}

/// "Prevent all damage that enemy spells and abilities would deal to me" while [cond].
class PreventEnemySpellDamage extends GenPassive {
  const PreventEnemySpellDamage(this.cond);
  final Cond? cond;
  @override
  String describe() => 'prevent enemy spell damage to me${cond == null ? '' : ' while ${describeCondGen(cond!)}'}';
}

/// "[Filter] can't be chosen by enemy spells and abilities" (others, e.g. "your units here with
/// less Might than me").
class UntargetableOthers extends GenPassive {
  const UntargetableOthers(this.filter);
  final Filter filter;
  @override
  String describe() => '${filter.describe()} can\'t be chosen by enemies';
}

/// "This spell's Energy cost is reduced by the highest Might among units you control."
class SelfCostByMight extends GenPassive {
  const SelfCostByMight();
  @override
  String describe() => 'costs less by your highest Might';
}

/// "Another …" chosen by a spell: a different object from the one in slot [notSlot].
class ChooseOther extends GenTarget {
  const ChooseOther(this.filter, {required this.slot, required this.notSlot, this.upTo = false});
  final Filter filter;
  final int slot, notSlot;
  final bool upTo;
  @override
  String describe() => 'another ${filter.describe()}';
}

/// "Return it to its owner's hand instead of putting it in their trash" after countering.
class CounteredToHand extends GenEffect {
  const CounteredToHand();
  @override
  String describe() => 'the countered card goes to its owner\'s hand';
}

/// "If you spent {N} or more" on the spell that triggered this (When you play a spell, …).
class SpentOnSpell extends GenCond {
  const SpentOnSpell(this.n);
  final int n;
  @override
  String describe() => 'spent ≥ $n on it';
}
