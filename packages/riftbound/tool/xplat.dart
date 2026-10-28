/// Plays seeded bot games and prints each game's fingerprint, one per line. The same program
/// runs on the Dart VM and compiled to JavaScript (tool/xplat_check.sh compares the two): a
/// browser and a phone in the same match must agree on every state.
///
///     dart run tool/xplat.dart [cards.json] [games] [--digest] [--mode=ffa3|ffa4|2v2]
library;

import 'dart:convert';

import 'package:riftbound/riftbound.dart';
import 'package:tcg_core/tcg_core.dart';

import 'xplat_io.dart' if (dart.library.js_interop) 'xplat_js.dart';

void main(List<String> argv) {
  final args = programArgs(argv);
  final pos = [
    for (final a in args)
      if (!a.startsWith('--')) a,
  ];
  final db = RCardDb.fromJson(jsonDecode(readText(pos.isNotEmpty ? pos[0] : '../../data/riftbound-cards.json')) as Map<String, dynamic>);
  final games = pos.length > 1 ? int.parse(pos[1]) : 20;
  final mode = RMode.fromId(args.where((a) => a.startsWith('--mode=')).map((a) => a.substring(7)).firstOrNull);
  final rng = SeededRng(7);
  for (var n = 0; n < games; n++) {
    final seed = rng.nextInt(1 << 30);
    final decks = randomDecksFor(db, rng, mode);
    final g = Game(db, players: [for (var p = 0; p < mode.players; p++) String.fromCharCode(65 + p)], seed: seed);
    try {
      g.apply(StartMove(decks, mode: mode));
      runBots(g, [for (var p = 0; p < mode.players; p++) RiftboundBot(p, seed: seed + p)], maxMoves: 4000 * mode.players ~/ 2);
      writeLine('$n ${g.state.turn} ${g.actions.length} ${g.state.players.map((p) => p.points).join('-')} ${g.fingerprint}');
      if (args.contains('--digest')) writeLine(g.state.digest());
    } catch (e) {
      writeLine('$n error after ${g.actions.length} moves: $e');
    }
  }
}
