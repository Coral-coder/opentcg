/// Lorcana as a ruleset of the shared card-game core (package:tcg_core).
library;

import 'package:tcg_core/tcg_core.dart';

import 'ai/bot.dart';
import 'cards/card_db.dart';
import 'game/game.dart';
import 'game/moves.dart';
import 'parser/parser.dart';

class LorcanaRuleset implements TcgRuleset {
  const LorcanaRuleset(this.db);
  final LCardDb db;

  @override
  String get id => 'lorcana';

  @override
  int get engineVersion => lorcanaEngineVersion;

  @override
  Game newMatch(List<String> playerNames, int seed) => Game(db, players: playerNames, seed: seed);

  @override
  StartMove deal(List<List<String>> decks, Map<String, dynamic>? options) => StartMove(decks, firstPlayer: options?['first'] as int?);

  @override
  LMove moveFromJson(Map<String, dynamic> json) => LMove.fromJson(json);

  @override
  ConcedeMove concede(int seat) => ConcedeMove(seat);

  @override
  LorcanaBot bot(int seat, int seed) => LorcanaBot(seat, seed: seed);
}
