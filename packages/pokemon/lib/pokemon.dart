/// Pokémon Trading Card Game rules engine (pure Dart, deterministic), on the shared tcg_core
/// contract.
library;

export 'src/cards/card.dart';
export 'src/cards/card_db.dart';
export 'src/ir.dart';
export 'src/parser/parser.dart' show PokemonParser, ParsedCard, pokemonEngineVersion;
export 'src/coverage.dart';
export 'src/game/game.dart';
export 'src/game/moves.dart';
export 'src/game/state.dart';
export 'src/ai/bot.dart';
export 'src/decks.dart';
export 'src/ruleset.dart';
