# Pokémon TCG: rules the engine follows

The engine (`packages/pokemon`) follows the official Pokémon TCG rulebook for the Scarlet &
Violet / Mega Evolution era. Code comments and tests cite its sections by name: "Setting Up",
"Your Turn", "Attacking", "Special Conditions", "Pokémon Checkup", "Knock Outs", "Winning",
"Building a Deck".

**The official rulebook PDF isn't in this repository yet.** pokemon.com serves it behind a
bot check that refused automated downloads, so it has to be added by hand. Download the
current rulebook from <https://www.pokemon.com/us/pokemon-tcg/rules> and save it as
`docs/pokemon-rulebook.pdf`. Until then, the rules below are written from the published rules
and haven't been checked line by line against the PDF.

## Format

**Standard, 2026 rotation:** regulation marks **H, I and J**, plus Basic Energy (which has no
mark). `bin/build_db.dart` takes the marks as an argument, so the pool can move with the next
rotation.

## Rules as implemented

**Building a Deck:**
- Exactly 60 cards.
- At most 4 cards with the same name, except Basic Energy.
- At most 1 ACE SPEC card.
- At least 1 Basic Pokémon.

**Setting Up:**
1. Each deck is shuffled. The winner of a coin flip chooses to go first or second.
2. Each player draws 7 cards. A hand with no Basic Pokémon is a mulligan: it's revealed, shuffled back and redrawn.
3. Each player puts down an Active Pokémon and up to 5 Benched Pokémon, then sets aside 6 Prize cards.
4. A player may draw 1 extra card for each extra mulligan their opponent took.

**Your Turn:**
- Draw a card. A player who can't draw at the start of their turn loses.
- Any number of times:
  - Put Basic Pokémon onto the Bench (up to 5).
  - Play Items.
  - Attach Pokémon Tools, 1 per Pokémon.
  - Use Abilities that say "Once during your turn" (once per Pokémon).
- Once per turn:
  - Attach 1 Energy from your hand.
  - Play 1 Supporter.
  - Play 1 Stadium. A Stadium with the same name as the one in play can't be played.
  - Retreat, discarding Energy equal to the Retreat Cost. An Asleep or Paralyzed Pokémon can't retreat.
- Evolve:
  - Not during your own first turn (either player).
  - Not a Pokémon that came into play or evolved this turn.
  - Evolving keeps damage and attached cards, and removes Special Conditions and lasting effects.
- The player going first can't attack or play a Supporter on their first turn.
- Attacking ends the turn.

**Attacking:**
1. The attack's Energy cost must be paid by the attached Energy. Colorless can be paid by any type.
2. If the attacker is Confused, flip a coin. On tails the attack doesn't happen and the attacker gets 3 damage counters.
3. Coin flips and damage modifiers are worked out first, then the damage is dealt, then the attack's other effects happen in printed order.
4. Damage to the Defending (Active) Pokémon is worked out in this order:
   1. Effects on the attacker ("does N less damage")
   2. Tool bonuses
   3. Weakness (×2)
   4. Resistance (−30, or the printed amount)
   5. Effects on the defender (Abilities, Tools, lasting effects)
5. Damage to Benched Pokémon skips Weakness and Resistance. Damage counters skip everything.
6. Tera Pokémon ex take no damage from attacks while on the Bench.

**Special Conditions and Pokémon Checkup:**
- Asleep, Confused and Paralyzed replace each other. Burned and Poisoned stack with them.
- At each Pokémon Checkup (between turns):
  - Poisoned: 1 damage counter.
  - Burned: 2 damage counters, then a flip; heads cures it.
  - Asleep: a flip; heads wakes it.
  - Paralyzed: ends after its owner's next turn.
- Moving to the Bench or evolving removes all Special Conditions.

**Knock Outs and Prize cards:**
- A Knocked Out Pokémon goes to the discard pile with everything attached to it.
- The opponent takes Prize cards from the front of the Prize list:
  - 1 for a Pokémon
  - 2 for a Pokémon ex
  - 3 for a Mega Evolution Pokémon ex
- A player with no Active Pokémon promotes one from the Bench. The player whose turn it isn't chooses first.

**Winning:**
- You win if you take your last Prize card, or your opponent has no Pokémon in play, or your opponent can't draw at the start of their turn.
- Conceding loses.
- If both players win at once, the game is a draw. Sudden Death isn't played.

## Not implemented yet

- **Stadiums:** they can be played and replace each other, but their effects aren't
  implemented. Every Stadium counts as unsupported, so random decks leave them out.
- **Card text the parser doesn't read:** see `data/pokemon-coverage.json`, or run
  `dart run bin/gaps.dart`. Cards with unsupported text can't be played. Their Pokémon can't
  use an attack or Ability that isn't understood.
- **Missing kinds of effects:**
  - "can't use <attack name>" during the next turn
  - effects that depend on the previous turn
  - looking at the top cards of a deck
  - evolving from the deck
  - Abilities that work on their own (triggered or passive), other than "takes N less damage"
- **Sudden Death and tournament rules:** time limits and best-of-three aren't implemented.
