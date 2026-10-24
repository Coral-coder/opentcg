# lorcana

The Disney Lorcana rules engine for OpenTCG: pure Dart and deterministic. It implements
tcg_core's `TcgMatch`, `TcgMove`, `TcgRuleset` and `TcgBot`. Rule numbers in comments and tests
refer to the Comprehensive Rules 2.2.0 (`docs/lorcana-comprehensive-rules-2.2.0.txt`).

- `lib/src/cards`: the card model and database. `bin/build_db.dart` turns the raw bulk file into
  `data/lorcana-cards.json` and `data/lorcana-coverage.json`.
- `lib/src/ir.dart`, `lib/src/parser`: the ability IR and the rules-text parser. Text the parser
  can't read is recorded per card (`ParsedCard.unsupported`), and decks only use fully supported cards.
- `lib/src/game`: the engine (`Game`), its state, moves, the bag and effects.
- `lib/src/ai/bot.dart`: a seeded heuristic computer player.

Checks (run before every push):

    dart analyze --fatal-warnings
    dart test
    dart run bin/chaos.dart --games 200
    tool/xplat_check.sh ../../data/lorcana-cards.json 40

Tools: `dart run bin/card.dart "<name>"` prints a card's parse, `dart run bin/gaps.dart` ranks
unsupported text by how many cards it would unlock.
