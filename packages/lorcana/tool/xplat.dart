/// Plays seeded bot games and prints each game's fingerprint, one per line. The same program
/// runs on the Dart VM and compiled to JavaScript (tool/xplat_check.sh compares the two): a
/// browser and a phone in the same match must agree on every state.
///
///     dart run tool/xplat.dart [cards.json] [games] [--digest]
library;

import 'dart:convert';

import 'package:lorcana/lorcana.dart';
import 'package:tcg_core/tcg_core.dart';

import 'xplat_io.dart' if (dart.library.js_interop) 'xplat_js.dart';

void main(List<String> argv) {
  final args = programArgs(argv);
  final pos = [
    for (final a in args)
      if (!a.startsWith('--')) a,
  ];
  final db = LCardDb.fromJson(jsonDecode(readText(pos.isNotEmpty ? pos[0] : '../../data/lorcana-cards.json')) as Map<String, dynamic>);
  final games = pos.length > 1 ? int.parse(pos[1]) : 20;
  final pairs = inkPairs.keys.toList();
  final rng = SeededRng(7);
  for (var n = 0; n < games; n++) {
    final seed = rng.nextInt(1 << 30);
    final picks = [pairs[rng.nextInt(pairs.length)], pairs[rng.nextInt(pairs.length)]];
    final decks = [for (final p in picks) randomDeck(db, inkPairs[p]!, rng)];
    final g = Game(db, players: ['A', 'B'], seed: seed);
    try {
      g.apply(StartMove(decks));
      runBots(g, [LorcanaBot(0, seed: seed), LorcanaBot(1, seed: seed + 1)], maxMoves: 4000);
      writeLine('$n ${g.state.turn} ${g.actions.length} ${g.state.players.map((p) => p.lore).join('-')} ${g.fingerprint}');
      if (args.contains('--digest')) writeLine(g.state.digest());
    } catch (e) {
      writeLine('$n error after ${g.actions.length} moves: $e');
    }
  }
}
