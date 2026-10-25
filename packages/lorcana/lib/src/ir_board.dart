part of 'ir.dart';

// Board effects: what players choose of their own, lore races, moving to locations, and the
// "this turn" conditions about the board (CR 6.1, 6.7, 4.6, 4.7).

/// "Each opponent chooses one of their characters and deals 2 damage to them", "each opponent
/// chooses and banishes one of their characters": each player in [who] picks one of their own
/// cards matching [filter] (no "chosen", so Ward doesn't apply, CR 8.15.1); [then] acts on it as
/// [Remembered] [slot].
class PlayerChooses extends Effect {
  const PlayerChooses(this.who, this.filter, this.slot, this.then);
  final Who who;
  final Filter filter;
  final int slot;
  final Effect then;
}

/// "Chosen character and all other characters with the same name": makes the choice, then
/// remembers in [into] every other card matching [others] that shares a name with it.
class SameNameAs extends Effect {
  const SameNameAs(this.chosen, this.others, this.into);
  final Target chosen;
  final Filter others;
  final int into;
}

/// "Each opponent with more lore than you loses N lore."
class LoseLoreRicher extends Effect {
  const LoseLoreRicher(this.amount);
  final Amount amount;
}

/// Move characters to a location for free (CR 4.7): "move him to one of your locations for
/// free", "move one of your other characters to that location for free" ([toEventLocation]),
/// "move him and one of your other characters to the same location for free".
class MoveToLocation extends Effect {
  const MoveToLocation(this.characters, {this.toEventLocation = false});
  final List<Target> characters;
  final bool toEventLocation;
}

/// The damage counters on a card ("equal to the damage on chosen character").
class DamageOn extends Amount {
  const DamageOn(this.target);
  final Target target;
}

/// What happened this turn, per player (CR 3: "this turn" means the current turn).
enum TurnStat { charactersPlayed, cardsPlayed, songsPlayed, quested, challenged, damaged, removedDamage, banished, banishedInChallenge, discarded }

/// "If you played another character this turn", "if a character was banished in a challenge
/// this turn", "if one of your characters was damaged this turn". [excludeSource]: "another".
class TurnStatCond extends Cond {
  const TurnStatCond(this.stat, this.who, this.cmp, this.n, {this.excludeSource = false});
  final TurnStat stat;
  final Who who;
  final Cmp cmp;
  final int n;
  final bool excludeSource;
}

/// "If you used Shift to play him" (CR 8.10): the card with the ability entered play by Shift.
class ShiftedCond extends Cond {
  const ShiftedCond();
}

/// "If an opponent (chosen opponent) has more cards in their hand than you".
class HandCompare extends Cond {
  const HandCompare({this.chosen = false});
  final bool chosen;
}

/// "If this character has N or more damage".
class SelfDamage extends Cond {
  const SelfDamage(this.min);
  final int min;
}

/// "If you have a character in play with more strength than each opposing character".
class StrongestCond extends Cond {
  const StrongestCond();
}
