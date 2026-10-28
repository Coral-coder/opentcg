/// Riftbound as a ruleset of the shared card-game core (package:tcg_core).
library;

import 'package:tcg_core/tcg_core.dart';

import 'ai/bot.dart';
import 'cards/card_db.dart';
import 'game/game.dart';
import 'game/moves.dart';
import 'game/state.dart' show RMode;
import 'parser/parser.dart';

class RiftboundRuleset implements TcgRuleset {
  const RiftboundRuleset(this.db);
  final RCardDb db;

  @override
  String get id => 'riftbound';

  @override
  int get engineVersion => riftboundEngineVersion;

  @override
  Game newMatch(List<String> playerNames, int seed) => Game(db, players: playerNames, seed: seed);

  @override
  StartMove deal(List<List<String>> decks, Map<String, dynamic>? options) =>
      StartMove(decks, firstPlayer: options?['first'] as int?, mode: RMode.fromId(options?['mode'] as String?));

  @override
  RMove moveFromJson(Map<String, dynamic> json) => RMove.fromJson(json);

  @override
  ConcedeMove concede(int seat) => ConcedeMove(seat);

  @override
  RiftboundBot bot(int seat, int seed) => RiftboundBot(seat, seed: seed);
}
