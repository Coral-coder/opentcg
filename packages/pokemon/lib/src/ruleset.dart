/// The Pokémon TCG as a ruleset of the shared card-game core (package:tcg_core).
library;

import 'package:tcg_core/tcg_core.dart';

import 'ai/bot.dart';
import 'cards/card_db.dart';
import 'game/game.dart';
import 'game/moves.dart';
import 'parser/parser.dart';

class PokemonRuleset implements TcgRuleset {
  const PokemonRuleset(this.db);
  final PCardDb db;

  @override
  String get id => 'pokemon';

  @override
  int get engineVersion => pokemonEngineVersion;

  @override
  Game newMatch(List<String> playerNames, int seed) => Game(db, players: playerNames, seed: seed);

  @override
  StartMove deal(List<List<String>> decks, Map<String, dynamic>? options) => StartMove(decks, firstPlayer: options?['first'] as int?);

  @override
  PMove moveFromJson(Map<String, dynamic> json) => PMove.fromJson(json);

  @override
  ConcedeMove concede(int seat) => ConcedeMove(seat);

  @override
  PokemonBot bot(int seat, int seed) => PokemonBot(seat, seed: seed);
}
