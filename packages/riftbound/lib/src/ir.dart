/// What card text means to the engine: abilities, triggers, costs, effects and targets.
/// LorcanaParser-style: the parser turns each line of rules text into these, and the engine only
/// ever executes these.
library;

import 'cards/card.dart';
import 'describe.dart';

part 'ir_general.dart';

part 'ir_equip.dart';
part 'ir_costs.dart';
part 'ir_power.dart';
part 'ir_hidden.dart';
part 'ir_w2s3.dart';

/// Keyword abilities (CR 805–826) the engine implements.
enum Kw {
  accelerate,
  action,
  reaction,
  assault,
  shield,
  tank,
  ganking,
  deflect,
  temporary,
  vision,
  backline,

  /// CR 811: may be hidden facedown at a battlefield you control and played from there later.
  hidden,

  /// CR 822: may be played to a battlefield where you control units, with Reaction while so.
  ambush,

  /// CR 825: a deck can hold only one copy.
  unique,
}

/// Who an effect's units belong to.
enum Side { any, friendly, enemy }

/// Where a unit must be for a filter.
enum Where {
  anywhere,
  here,
  battlefield,
  base,

  /// "At a different location" from the source.
  elsewhere,
}

/// A description of units (or gear) on the board: "an enemy unit at a battlefield with 3 {M} or
/// less". The fields after [buffed] come from the general grammar (parser/general.dart).
class Filter {
  const Filter({this.side = Side.any, this.where = Where.anywhere, this.gear = false, this.mightMax, this.mightMin, this.other = false, this.exhausted, this.attacking = false, this.defending = false, this.tag, this.buffed, this.types, this.zone = FZone.board, this.tags = const [], this.domain, this.token, this.notTag, this.stunned, this.damaged, this.mighty, this.withKw, this.withoutKw, this.costMax, this.lessMightThanMe = false, this.inCombat = false, this.atSlot, this.myBf = false, this.pw});
  final Side side;
  final Where where;

  /// Gear rather than units.
  final bool gear;
  final int? mightMax, mightMin;

  /// "Another", "other": not the source.
  final bool other;
  final bool? exhausted;
  final bool attacking, defending;
  final String? tag;
  final bool? buffed;

  /// Card types when it isn't just units or just gear ("a unit or gear", "a card", "a spell");
  /// overrides [gear].
  final Set<CardType>? types;

  /// Where the objects are: on the board, or cards in a trash or hand ([side] then means whose).
  final FZone zone;

  /// Any of these tags ("a Bird, Cat, Dog, or Poro").
  final List<String> tags;
  final Domain? domain;
  final bool? token;

  /// "Non-Recruit", "a non-Dragon unit": not of this tag.
  final String? notTag;
  final bool? stunned, damaged;

  /// Might 5 or more (CR 708).
  final bool? mighty;
  final Kw? withKw, withoutKw;

  /// Energy cost at most.
  final int? costMax;

  /// "With less Might than me".
  final bool lessMightThanMe;

  /// In a combat (at the battlefield of the combat in progress).
  final bool inCombat;

  /// At the location of the object chosen in this slot (a battlefield, or a unit's location).
  final int? atSlot;

  /// "At my battlefield": the source's location, which must be a battlefield.
  final bool myBf;

  Set<CardType> get cardTypes => types ?? {gear ? CardType.gear : CardType.unit};

  Filter copyWith({
    Side? side,
    Where? where,
    bool? other,
    bool? exhausted,
    bool? buffed,
    Set<CardType>? types,
    FZone? zone,
    List<String>? tags,
    bool? token,
    bool? stunned,
    bool? damaged,
    bool? mighty,
    Kw? withKw,
    Kw? withoutKw,
    int? atSlot,
    bool? myBf,
    bool? attacking,
    bool? defending,
    bool? inCombat,
    int? mightMax,
    int? mightMin,
  }) => Filter(
    side: side ?? this.side,
    where: where ?? this.where,
    gear: gear,
    mightMax: mightMax ?? this.mightMax,
    mightMin: mightMin ?? this.mightMin,
    other: other ?? this.other,
    exhausted: exhausted ?? this.exhausted,
    attacking: attacking ?? this.attacking,
    defending: defending ?? this.defending,
    tag: tag,
    buffed: buffed ?? this.buffed,
    types: types ?? this.types,
    zone: zone ?? this.zone,
    tags: tags ?? this.tags,
    domain: domain,
    token: token ?? this.token,
    notTag: notTag,
    stunned: stunned ?? this.stunned,
    damaged: damaged ?? this.damaged,
    mighty: mighty ?? this.mighty,
    withKw: withKw ?? this.withKw,
    withoutKw: withoutKw ?? this.withoutKw,
    costMax: costMax,
    lessMightThanMe: lessMightThanMe,
    inCombat: inCombat ?? this.inCombat,
    atSlot: atSlot ?? this.atSlot,
    myBf: myBf ?? this.myBf,
    pw: pw,
  );

  /// Empowered, "something", Might comparisons (ir_power.dart).
  final PowerFilter? pw;

  String describe() => [
        if (side != Side.any) side.name,
        if (other) 'other',
        if (exhausted == true) 'exhausted',
        if (exhausted == false) 'ready',
        if (buffed == true) 'buffed',
        if (stunned == true) 'stunned',
        if (damaged == true) 'damaged',
        if (mighty == true) 'mighty',
        if (token == true) 'token',
        if (token == false) 'non-token',
        if (attacking) 'attacking',
        if (defending) 'defending',
        if (inCombat) 'in combat',
        ?tag,
        if (tags.isNotEmpty) tags.join('/'),
        if (notTag != null) 'non-$notTag',
        if (domain != null) domain!.label,
        types == null ? (gear ? 'gear' : 'unit') : types!.map((t) => t.name).join('/'),
        if (zone != FZone.board) 'in ${zone.name}',
        if (where != Where.anywhere) '@${where.name}',
        if (myBf) '@my battlefield',
        if (atSlot != null) '@location of #$atSlot',
        if (mightMax != null) 'M≤$mightMax',
        if (mightMin != null) 'M≥$mightMin',
        if (costMax != null) 'cost≤$costMax',
        if (lessMightThanMe) 'M<mine',
        if (withKw != null) 'with ${withKw!.name}',
        if (withoutKw != null) 'without ${withoutKw!.name}',
        if (pw != null) pw!.describe(),
      ].join(' ');
}

/// Where a filter's objects are.
enum FZone { board, trash, hand }

/// What an effect acts on.
sealed class Target {
  const Target();
}

/// The card with the ability ("me", "this").
class Me extends Target {
  const Me();
}

/// One unit (or gear) the controller chooses as the effect is played (CR 355.5–355.9). [slot]
/// remembers it for "it" later in the text.
class Choose extends Target {
  const Choose(this.filter, {this.slot = 0, this.upTo = false});
  final Filter filter;
  final int slot;

  /// "Up to one": may choose nothing.
  final bool upTo;
}

/// The unit chosen earlier in the same text ("it", "that unit").
class Chosen extends Target {
  const Chosen(this.slot);
  final int slot;
}

/// Every unit matching [filter] ("all enemy units here").
class Each extends Target {
  const Each(this.filter);
  final Filter filter;
}

/// The unit a trigger is about ("it" in "When a friendly unit dies, …").
class EventUnit extends Target {
  const EventUnit();
}

/// Numbers that can depend on the board.
sealed class Amount {
  const Amount();
}

class N extends Amount {
  const N(this.n);
  final int n;
}

/// "Equal to my Might".
class MyMight extends Amount {
  const MyMight();
}

sealed class Effect {
  const Effect();
}

/// "Deal N to …" (CR 418).
class Deal extends Effect {
  const Deal(this.amount, this.target);
  final Amount amount;
  final Target target;
}

class Draw extends Effect {
  const Draw(this.n);
  final int n;
}

class Discard extends Effect {
  const Discard(this.n);
  final int n;
}

/// "Buff …" (CR 427): a +1 {M} buff counter if it has none.
class Buff extends Effect {
  const Buff(this.target);
  final Target target;
}

class Ready extends Effect {
  const Ready(this.target);
  final Target target;
}

class Exhaust extends Effect {
  const Exhaust(this.target);
  final Target target;
}

/// "Stun …" (CR 424): it doesn't deal combat damage; cleared at end of turn.
class Stun extends Effect {
  const Stun(this.target);
  final Target target;
}

class Kill extends Effect {
  const Kill(this.target);
  final Target target;
}

/// "Give … +N {M} this turn" (CR 479.4).
class GiveMight extends Effect {
  const GiveMight(this.n, this.target, {this.min});
  final int n;
  final Target target;

  /// "To a minimum of N {M}": a decrease stops there, fixed as it applies (CR 479.4.b).
  final int? min;
}

/// "Give … [Keyword] this turn".
class GiveKw extends Effect {
  const GiveKw(this.kw, this.n, this.target);
  final Kw kw;
  final int n;
  final Target target;
}

/// "Recall …" / "Move … to its base": to its controller's base (a recall isn't a move, CR 457;
/// [asMove] when the text says "move").
class ToBase extends Effect {
  const ToBase(this.target, {this.asMove = true});
  final Target target;
  final bool asMove;
}

/// "Return … to its owner's hand".
class ToHand extends Effect {
  const ToHand(this.target);
  final Target target;
}

class Heal extends Effect {
  const Heal(this.target);
  final Target target;
}

/// "Channel N rune(s) [exhausted]" (CR 431).
class Channel extends Effect {
  const Channel(this.n, {this.exhausted = false});
  final int n;
  final bool exhausted;
}

/// "Play N {M} Recruit unit token(s) [here / to your base]" (CR 179–187).
class PlayToken extends Effect {
  const PlayToken(this.token, this.count, {this.here = false, this.ready = false});
  final String token;
  final int count;

  /// At the source's location (else the controller's base).
  final bool here;
  final bool ready;
}

/// "You score N point(s)": gain points, not the Scoring process (CR 470.2).
class GainPoints extends Effect {
  const GainPoints(this.n);
  final int n;
}

/// "Predict N" (CR 437): look at the top N and recycle any of them.
class Predict extends Effect {
  const Predict(this.n);
  final int n;
}

/// "Counter a spell" (CR 426).
class Counter extends Effect {
  const Counter();
}

/// "[Add] {N}" / "[Add] {A}": Energy or Power into the Rune Pool (CR 165).
class AddRes extends Effect {
  const AddRes({this.energy = 0, this.anyPower = 0, this.spellsOnly = false, this.power = const []});
  final int energy, anyPower;

  /// Power of these domains ("[Add] {R}").
  final List<Domain> power;

  /// "Use only to play spells."
  final bool spellsOnly;
}

/// "Ready N runes".
class ReadyRunes extends Effect {
  const ReadyRunes(this.n);
  final int n;
}

/// "Move … to or from its base": from base to a battlefield (chosen as it resolves), else to base.
class ToOrFromBase extends Effect {
  const ToOrFromBase(this.target);
  final Target target;
}

/// "If [cond], [effects]" / "[effects] if [cond]".
class If extends Effect {
  const If(this.cond, this.effects);
  final Cond cond;
  final List<Effect> effects;
}

/// Conditions checked as an ability resolves.
sealed class Cond {
  const Cond();
}

/// "If you have one or fewer cards in your hand".
class HandAtMost extends Cond {
  const HandAtMost(this.n);
  final int n;
}

/// "If you have N+ units at that battlefield" (the battlefield the trigger is about).
class UnitsThere extends Cond {
  const UnitsThere(this.n);
  final int n;
}

/// "You may [effect]": the controller decides as it resolves.
class May extends Effect {
  const May(this.effects);
  final List<Effect> effects;
}

/// "Choose one - • … • …" (CR 355.3): the mode is chosen as it's played (or as a trigger goes on
/// the chain) and kept in target slot [slot]. [distinct]: "one you haven't already chosen" (each
/// execution of a [Repeat] picks another); [perTurn]: "one you've not chosen this turn".
class Modes extends Effect {
  const Modes(this.modes, {this.slot = -1, this.distinct = false, this.perTurn = false});
  final List<List<Effect>> modes;
  final int slot;
  final bool distinct, perTurn;
}

sealed class Trigger {
  const Trigger();
}

/// Trigger events (CR 382).
enum On {
  /// "When you play me / this".
  played,
  attack,
  defend,
  attackOrDefend,

  /// "When I conquer" / "When I hold" (a unit at the scored battlefield).
  conquer,
  hold,

  /// "When you conquer" / "When you hold" (any battlefield; legends and permanents).
  youConquer,
  youHold,

  /// "When you conquer here" / "When you hold here" (a battlefield).
  conquerHere,
  holdHere,

  /// "When I move" / "When I move to a battlefield".
  move,

  /// [Deathknell] (CR 808): "When I die".
  die,

  /// "At the start of your turn" / "At start of your Beginning Phase".
  startOfTurn,

  /// "At the end of your turn".
  endOfTurn,

  /// "When you play a spell".
  youPlaySpell,

  /// "When I win a combat" / "When you win a combat".
  winCombat,
  youWinCombat,

  /// "When you play a unit".
  youPlayUnit,

  /// "When you stun one or more enemy units".
  youStunEnemy,

  /// "When an enemy unit attacks a battlefield you control" (once per attacking unit; "it" is it).
  enemyAttacksYourBf,

  /// A [GenWhen] (ir_general.dart): its own event.
  general,
  // Empower, XP and buffs (ir_power.dart, game/power.dart).
  /// "When I become [Empowered]".
  empowered,

  /// "When you empower something else".
  youEmpowerOther,

  /// "When you buff me" / "When you buff a friendly unit" ("it" is it).
  buffedMe,
  youBuffFriendly,

  /// "When you spend a buff".
  youSpendBuff,

  /// "When you play another unit".
  youPlayAnotherUnit,

  /// "When another friendly unit dies" / "When a buffed friendly unit dies" ("it" is it).
  anotherFriendlyDies,
  buffedFriendlyDies,

  /// "When a combat that I was in ends".
  combatEnds,

  /// "When my Might becomes 10 or more".
  mightTen,

  /// "When you recycle one or more cards".
  youRecycle,

  /// "When you banish a card you own".
  youBanishOwn,

  /// "When you play a card from anywhere other than your hand".
  youPlayNotFromHand,

  /// "When a player plays a unit here" (a battlefield; "it" is it).
  unitPlayedHere,
  /// "When you play me from face down" / "When I'm played from [Hidden]" (CR 811).
  playedFaceDown,

  /// "When you play a card from [Hidden]".
  youPlayFromHidden,

  /// "When an enemy unit dies" ("it" is that unit).
  enemyUnitDies,

  /// "When an opponent scores".
  opponentScores,
  /// Events of game/costs.dart, told apart by [XWhen.kind] (playing cards with a given cost,
  /// becoming ready, …).
  costsExt,

  /// Equipment events, told apart by [EqWhen.event] (ir_equip.dart).
  eq,

  /// Wave 2, slice 3's events, told apart by [W3When.kind] (ir_w2s3.dart).
  w2s3,
}

class When extends Trigger {
  const When(this.on, {this.moveToBattlefield = false});
  final On on;
  final bool moveToBattlefield;
}

/// What an activated ability costs (CR 204.1.b).
class Cost {
  const Cost({this.energy = 0, this.power = const [], this.exhaust = false, this.killMe = false, this.extra = const []});
  final int energy;

  /// Other costs: discarding, recycling from the trash, killing a friendly unit… (ir_general.dart).
  final List<CostPart> extra;

  /// One entry per Power symbol: a domain, or null for {A} (any domain).
  final List<Domain?> power;
  final bool exhaust;

  /// "Kill this" (Gold).
  final bool killMe;

  bool get isFree => energy == 0 && power.isEmpty && !exhaust && !killMe && extra.isEmpty;
  String describe() => [if (energy > 0) '{$energy}', for (final p in power) '{${p?.letter ?? 'A'}}', for (final x in extra) describeCostPart(x), if (killMe) 'kill me', if (exhaust) '{E}'].join(' ');
}

/// When a spell or ability may be played (CR 806, 813).
enum Timing { normal, action, reaction }

sealed class Ability {
  const Ability(this.text);

  /// The line of text this came from.
  final String text;
}

class KeywordAb extends Ability {
  const KeywordAb(super.text, this.kw, [this.n = 1]);
  final Kw kw;
  final int n;
}

/// "When …, [effects]". [may]: "you may" — the controller decides as it resolves.
class Triggered extends Ability {
  const Triggered(super.text, this.on, this.effects, {this.legion = false, this.gate});
  final When on;
  final List<Effect> effects;

  /// [Legion] (CR 812): only while you've played another card this turn.
  final bool legion;

  /// Only while [gate] holds ([Empowered], [Level N]; ir_power.dart).
  final Gate? gate;
}

/// "Cost: effect" (CR 376).
class Activated extends Ability {
  const Activated(super.text, this.cost, this.effects, {this.timing = Timing.normal, this.oncePerTurn = false, this.legion = false, this.gate});
  final Cost cost;
  final List<Effect> effects;
  final Timing timing;
  final bool oncePerTurn;

  /// [Legion] (CR 812): usable only once you've played another card this turn.
  final bool legion;

  /// Only while [gate] holds (ir_power.dart).
  final Gate? gate;

  /// Abilities that add resources resolve at once (CR 337.2) and can pay costs (CR 357.1.a).
  bool get adds => effects.isNotEmpty && effects.every((e) => e is AddRes);
}

/// A spell's instructions (CR 158).
class SpellBody extends Ability {
  const SpellBody(super.text, this.effects);
  final List<Effect> effects;
}

/// Passive abilities (CR 363) the engine implements.
sealed class Passive {
  const Passive();
}

/// "Other friendly units have +N {M} [here]" / "Your Mechs have +N {M}".
class Anthem extends Passive {
  const Anthem(this.n, this.filter);
  final int n;
  final Filter filter;
}

/// "I enter ready." (Units enter exhausted otherwise, CR 143.4.)
class EntersReady extends Passive {
  const EntersReady();
}

/// "I don't deal combat damage."
class NoCombatDamage extends Passive {
  const NoCombatDamage();
}

/// "While a friendly unit defends alone, it gets +N {M}."
class DefendsAlone extends Passive {
  const DefendsAlone(this.n);
  final int n;
}

/// "Your Mechs have [Shield]": a keyword for matching units.
class KwAnthem extends Passive {
  const KwAnthem(this.kw, this.n, this.filter);
  final Kw kw;
  final int n;
  final Filter filter;
}

/// "This enters exhausted." (gear)
class EntersExhausted extends Passive {
  const EntersExhausted();
}

/// "[Legion] - I cost {N} less." (CR 356.4)
class CostLess extends Passive {
  const CostLess(this.n, {this.legion = false});
  final int n;
  final bool legion;
}

class Static extends Ability {
  const Static(super.text, this.passive, {this.gate});
  final Passive passive;

  /// Only while [gate] holds (ir_power.dart).
  final Gate? gate;
}

/// [Repeat] cost (CR 820): pay it as you play the spell to do its instructions again.
class RepeatCost extends Ability {
  const RepeatCost(super.text, this.cost);
  final Cost cost;
}
