part of 'ir.dart';

// Wave 2, slice 3 (Rek'Sai, Swarm Queen to Zilean, Time Mage): rules the families don't cover,
// mostly one card each. parser/w2s3.dart reads text into these; game/w2s3.dart executes them.
// Each kind has an abstract base so the core switches need one line each.

// ---------------------------------------------------------------------------------------------
// Effects
// ---------------------------------------------------------------------------------------------

abstract class W3Effect extends Effect {
  const W3Effect();

  /// Choices made as it's played (CR 355), by the general chooser; this file's own choices
  /// (a battlefield, a named tag's unit, a Shadow Clone) are made by game/w2s3.dart.
  List<Target> get targets => const [];
  String describe();
}

/// "Reveal the top N cards of your Main Deck. You may play one. Then recycle the rest." Playing it
/// pays its cost (CR 420.3: no timing restrictions). [may]: "you may reveal"; [hereIfUnit]: "If
/// the played card is a unit, you may play it here" (the source's battlefield).
class W3RevealPlay extends W3Effect {
  const W3RevealPlay(this.n, {this.may = false, this.hereIfUnit = false});
  final int n;
  final bool may, hereIfUnit;
  @override
  String describe() => '${may ? 'may ' : ''}reveal top $n, may play one${hereIfUnit ? ' (a unit here)' : ''}, recycle the rest';
}

/// "[Add] {N}. Spend this Energy only to play units or activated abilities of units." (Renekton):
/// Energy kept apart from the rest of the pool (CR 165) and used only for those.
class W3UnitAdd extends AddRes {
  const W3UnitAdd(int energy) : super(energy: energy);
}

/// "Choose a friendly unit and a spell. Counter that spell and give that unit +{M} equal to that
/// spell's Energy cost this turn."
class W3CounterGive extends W3Effect {
  const W3CounterGive(this.unit, this.spell);
  final Choose unit;
  final ChooseSpell spell;
  @override
  List<Target> get targets => [unit, spell];
  @override
  String describe() => 'counter a spell, give a friendly unit +its Energy cost Might';
}

/// "Deal N to it unless its controller has you draw M": the unit's controller decides as it
/// resolves.
class W3DealUnless extends W3Effect {
  const W3DealUnless(this.n, this.target, this.draw);
  final int n, draw;
  final Target target;
  @override
  String describe() => 'deal $n to ${describeTarget(target)} unless its controller has you draw $draw';
}

/// "Each opponent must kill one of their units."
class W3OppKillsOne extends W3Effect {
  const W3OppKillsOne();
  @override
  String describe() => 'each opponent kills one of their units';
}

/// "Choose a friendly unit in your base (#[unitSlot]). Deal damage equal to its Might to all enemy
/// units at a battlefield (#[bfSlot], chosen as it's played), then move your unit there."
class W3Stormbringer extends W3Effect {
  const W3Stormbringer(this.unitSlot, this.bfSlot);
  final int unitSlot, bfSlot;
  @override
  String describe() => 'deal #$unitSlot Might to all enemy units at a battlefield, then move it there';
}

/// "The attacker and defender each [Add] {N}."
class W3AddCombatants extends W3Effect {
  const W3AddCombatants(this.energy);
  final int energy;
  @override
  String describe() => 'attacker and defender each add {$energy}';
}

/// "Move any number of enemy units with the same controller and a total Might of N or less to a
/// single location." The location is chosen as it's played and kept in [destSlot] (0 for a base,
/// else the battlefield's object).
class W3MoveMany extends W3Effect {
  const W3MoveMany(this.units, this.destSlot);
  final ChooseMany units;
  final int destSlot;
  @override
  List<Target> get targets => [units];
  @override
  String describe() => 'move ${units.describe()} (total Might ≤ ${units.totalMightMax}) to one location';
}

/// Twisted Fate, Gambler: reveal the top rune of your rune deck, recycle it, then by its domain:
/// Fury deal 2 to an enemy unit here and 1 to the others there; Mind draw 1; Order stun an enemy unit.
class W3RuneGamble extends W3Effect {
  const W3RuneGamble();
  @override
  String describe() => 'reveal and recycle the top rune: Fury deal 2+1 here / Mind draw 1 / Order stun';
}

/// "The next time it dies this turn, you may pay {[power]} to recall it exhausted instead."
class W3SaveForPay extends W3Effect {
  const W3SaveForPay(this.target, this.power);
  final Target target;
  final Domain power;
  @override
  List<Target> get targets => [target];
  @override
  String describe() => 'the next time ${describeTarget(target)} dies this turn, may pay {${power.letter}} to recall it exhausted instead';
}

/// "Starting with the next player, each player may return a unit to its owner's hand."
class W3Whirlwind extends W3Effect {
  const W3Whirlwind();
  @override
  String describe() => 'each player, starting with the next, may return a unit to its owner’s hand';
}

/// "Move me and a Shadow Clone you control (#[slot]) to each other's locations."
class W3SwapClone extends W3Effect {
  const W3SwapClone(this.slot);
  final int slot;
  @override
  String describe() => 'swap places with a Shadow Clone you control';
}

/// "Give a unit with the named tag (#[slot]) -N {M} this turn" (The List).
class W3NamedTagMight extends W3Effect {
  const W3NamedTagMight(this.slot, this.n);
  final int slot, n;
  @override
  String describe() => 'give a unit with the named tag $n Might this turn';
}

/// Star Spring: "they may move another unit they control here to its base" (the played unit is
/// the event; chosen as it resolves).
class W3MoveOtherHome extends W3Effect {
  const W3MoveOtherHome();
  @override
  String describe() => 'they may move another unit they control here to its base';
}

/// Stealthy Pursuer: "I may be moved with it" (to the location in the trigger).
class W3Follow extends W3Effect {
  const W3Follow();
  @override
  String describe() => 'I may move with it';
}

// ---------------------------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------------------------

abstract class W3Cond extends Cond {
  const W3Cond();
  String describe();
}

/// "If you've played a non-token unit, a non-token gear, and a spell this turn" (Swain).
class W3PlayedUnitGearSpell extends W3Cond {
  const W3PlayedUnitGearSpell();
  @override
  String describe() => 'played a non-token unit, a non-token gear and a spell this turn';
}

/// "With one or more [Mighty] units": you have a Mighty unit at this battlefield (Sunken Temple).
class W3MightyHere extends W3Cond {
  const W3MightyHere();
  @override
  String describe() => 'a Mighty unit of yours here';
}

// ---------------------------------------------------------------------------------------------
// Triggers
// ---------------------------------------------------------------------------------------------

enum W3On {
  /// "When a unit here is returned to a player's hand" (a battlefield; its owner's trigger).
  returnedHere,

  /// "The first time a friendly unit dies during your Beginning Phase each turn".
  friendlyDiesInBeginning,

  /// "The first time a player plays a non-token unit here each turn" (a battlefield).
  firstUnitPlayedHere,

  /// "When a friendly unit moves from my location".
  friendMovesFromMe,

  /// "When a player chooses a friendly unit here with a spell for the first time each turn".
  firstChosenHereBySpell,
}

class W3When extends When {
  const W3When(this.kind) : super(On.w2s3);
  final W3On kind;
}

// ---------------------------------------------------------------------------------------------
// Passives
// ---------------------------------------------------------------------------------------------

abstract class W3Passive extends Passive {
  const W3Passive();
  String describe();
}

/// Renata Glasc: "While your score is within 3 points of the Victory Score, your Gold [Add] an
/// additional {1}."
class W3GoldBonus extends W3Passive {
  const W3GoldBonus(this.within, this.energy);
  final int within, energy;
  @override
  String describe() => 'your Gold adds {$energy} more while within $within points of victory';
}

/// Sandstone Chimera: "While I'm at a battlefield, players only channel N rune at the start of
/// their Channel Phase."
class W3ChannelOnly extends W3Passive {
  const W3ChannelOnly(this.n);
  final int n;
  @override
  String describe() => 'while I’m at a battlefield, players channel only $n in their Channel Phase';
}

/// Shadow: "If you play me to a battlefield, I enter ready."
class W3ReadyAtBattlefield extends W3Passive {
  const W3ReadyAtBattlefield();
  @override
  String describe() => 'enters ready if played to a battlefield';
}

/// Soraka, Wanderer: "If another unit you control here would die, if it has less Might than me,
/// instead heal it, exhaust it, and recall it."
class W3SorakaSave extends W3Passive {
  const W3SorakaSave();
  @override
  String describe() => 'saves weaker friendly units here from dying';
}

/// Symbol of the Solari: "If a combat where you are the attacker ends in a tie, recall ALL units
/// instead."
class W3SolariTie extends W3Passive {
  const W3SolariTie();
  @override
  String describe() => 'ties of your attacks recall all units';
}

/// Syndra, Transcendent: "While I'm in a showdown, your spells have [Repeat] {cost}."
class W3GrantRepeat extends W3Passive {
  const W3GrantRepeat(this.cost);
  final Cost cost;
  @override
  String describe() => 'while I’m in a showdown, your spells have Repeat ${cost.describe()}';
}

/// The List: "As you play this, name a tag."
class W3NameTag extends W3Passive {
  const W3NameTag();
  @override
  String describe() => 'names a tag as it’s played';
}

/// Void Hatchling: "If you would reveal cards from a deck, look at the top card first. You may
/// recycle it. Then reveal those cards."
class W3PeekBeforeReveal extends W3Passive {
  const W3PeekBeforeReveal();
  @override
  String describe() => 'before you reveal from a deck, may recycle its top card';
}

/// Zilean, Time Mage: "Once each turn, if you would play a token unit while I'm at a battlefield,
/// you may play that token and an additional copy of it instead."
class W3TokenCopy extends W3Passive {
  const W3TokenCopy();
  @override
  String describe() => 'once each turn, a token unit you play comes with a copy';
}
