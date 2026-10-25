# pokemon

A Pokémon TCG rules engine in pure Dart. It has no UI. It's deterministic and implements the
`tcg_core` contract (`TcgMatch`, `TcgMove`, `TcgRuleset`, `TcgBot`), the same as
`packages/lorcana`. A match is its seed plus its moves, so the VM and JavaScript builds reach
the same fingerprint.

- **Rules:** see `docs/pokemon-rules.md`. The format is Standard: regulation marks H, I and J.
- **Cards:** `data/pokemon-cards.json`, built from [pokemon-tcg-data](https://github.com/PokemonTCG/pokemon-tcg-data).
  Download that repo's `cards/en/<set>.json` files into a directory, then run:

      dart run bin/build_db.dart <that dir> ../../data [H,I,J]

  This writes the card file and `data/pokemon-coverage.json`.
- **Images:** each printing links `https://images.pokemontcg.io/<set>/<number>_hires.png`.
  That server sends `Access-Control-Allow-Origin: *`, so a web app can load the images
  cross-origin. The images aren't copied into this repository. Pokémon card names, text and
  art belong to The Pokémon Company, Nintendo, Creatures and GAME FREAK; this project isn't
  affiliated with them.

## Using it

```dart
final db = PCardDb.fromJson(jsonDecode(json));
final rules = PokemonRuleset(db);
final g = rules.newMatch(['Ash', 'Misty'], seed) as Game;
g.apply(rules.deal([deck0, deck1], {'first': 0}));   // or no 'first': a coin flip decides
while (!g.over) {
  final d = g.pending?.decision;              // a question for d.player (cards / yesNo / option)
  if (d != null) { g.apply(AnswerMove(d.player, answer)); continue; }
  final moves = g.legalMoves();               // for the player in g.state.active
  g.apply(chosen);                             // throws PokemonError if illegal; state unchanged
}
```

**Moves:**

| Move | Meaning |
|---|---|
| `PlayBasicMove(card)` | Put a Basic Pokémon onto the Bench |
| `EvolveMove(card, target)` | Evolve `target` with `card` |
| `AttachEnergyMove(card, target)` | Attach an Energy (once per turn) |
| `TrainerMove(card, target:)` | Play a Trainer; `target` is the Pokémon for a Tool |
| `RetreatMove(to)` | Retreat the Active Pokémon for `to` |
| `AbilityMove(card, index)` | Use an Ability |
| `AttackMove(index)` | Attack (ends the turn) |
| `EndTurnMove` | End the turn |
| `ConcedeMove` | Concede |
| `AnswerMove(answer)` | Answer the pending decision |

Every move round-trips through `toJson()` and `PMove.fromJson()`.

**For the table:**
- `g.state`: players, with deck, hand, discard, prizes, active and bench as card ids.
- `g.state.obj(id)`: a card's damage, conditions, attached energy and tool, and the cards under it.
- `g.card(id)`: the printed card, with its `image`.
- `g.maxHp(id)`, `g.retreatCost(id)`, `g.energyOf(id)`, `g.hasEnergyFor(id, i)`.
- `g.whyNot(move)`: why a move is illegal, or null if it's legal.
- `g.state.log`: what happened. Each entry has a `kind` (attack, damage, ko, prize, coin, …) for animations.
- `g.fingerprint`: the state hash, for lockstep sync between players.

## Checks

    dart analyze --fatal-warnings
    dart test
    dart run bin/chaos.dart --games 200      # random bot games, replayed from moves and JSON
    tool/xplat_check.sh                      # same games on the VM and as JavaScript
    dart run bin/gaps.dart                   # what the parser can't read yet, by cards held back
    dart run bin/card.dart "Pikachu ex"      # one card's parse
