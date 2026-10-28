/// Times the computer player: each bot step (choosing a move and playing it, as the app does)
/// over seeded games, with the median and slow cases. Compile it to JavaScript to see what a
/// browser sees, as tool/xplat_check.sh does with tool/xplat.dart:
///
///     dart compile js -O2 -o /tmp/speed.js tool/bot_speed.dart
///     node -e "globalThis.require = require; require(process.argv[1])" /tmp/speed.js [games]
///
/// (or `dart run tool/bot_speed.dart [games]` on the VM).
library;

import 'dart:convert';

import 'package:riftbound/riftbound.dart';
import 'package:tcg_core/tcg_core.dart';

import 'xplat_io.dart' if (dart.library.js_interop) 'xplat_js.dart';

void main(List<String> argv) {
  final args = programArgs(argv);
  final games = args.isNotEmpty ? int.parse(args[0]) : 40;
  final db = RCardDb.fromJson(jsonDecode(readText('../../data/riftbound-cards.json')) as Map<String, dynamic>);
  final rng = SeededRng(7);
  final times = <int>[];
  final total = Stopwatch()..start();
  for (var n = 0; n < games; n++) {
    final seed = rng.nextInt(1 << 30);
    final decks = [randomDeck(db, rng), randomDeck(db, rng)];
    final g = Game(db, players: ['A', 'B'], seed: seed);
    g.apply(StartMove(decks));
    final bots = [RiftboundBot(0, seed: seed), RiftboundBot(1, seed: seed + 1)];
    for (var i = 0; i < 4000 && !g.over; i++) {
      final seat = g.toAct;
      if (seat == null) break;
      final sw = Stopwatch()..start();
      final before = g.actions.length;
      if (!bots[seat].step(g)) break;
      final us = sw.elapsedMicroseconds;
      times.add(us);
      if (us > 60000) writeLine('slow ${us ~/ 1000} ms game $n turn ${g.state.turn}: ${[for (final m in g.actions.skip(before)) m.toJson()]} chain ${g.state.chain.length} board ${g.state.objects.values.where((o) => o.zone == Zone.board).length}');
    }
  }
  times.sort();
  int pct(double p) => times[(p * (times.length - 1)).round()];
  writeLine('$games games, ${times.length} steps, total ${total.elapsedMilliseconds} ms; per step ms: median ${(pct(0.5) / 1000).toStringAsFixed(2)}, p95 ${(pct(0.95) / 1000).toStringAsFixed(1)}, p99 ${(pct(0.99) / 1000).toStringAsFixed(1)}, max ${(times.last / 1000).toStringAsFixed(1)}');
}
