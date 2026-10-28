/// Chaos games with decks full of a slice's cards (a dump_unsupported-style file of "## Name"
/// headers): each random deck has up to 24 of its main-deck cards swapped for them, its
/// battlefields swapped for the slice's, and every third game a legend from the slice. Replays
/// every game from its moves and from their JSON, and counts how often the slice's cards show up
/// in the logs.
///
///     dart run tool/slice_chaos.dart SLICE_FILE [--games 200] [--seed 1]
library;

import 'dart:convert';
import 'dart:io';

import 'package:riftbound/riftbound.dart';
import 'package:tcg_core/tcg_core.dart';

void main(List<String> args) {
  final db = RCardDb.fromJson(jsonDecode(File('../../data/riftbound-cards.json').readAsStringSync()) as Map<String, dynamic>);
  var games = 200, seed = 1;
  for (var i = 1; i < args.length; i++) {
    if (args[i] == '--games') games = int.parse(args[++i]);
    if (args[i] == '--seed') seed = int.parse(args[++i]);
  }
  final names = File(args[0]).readAsLinesSync().where((l) => l.startsWith('## ')).map((l) => l.substring(3, l.indexOf(' ['))).toList();
  final slice = [for (final n in names) db.cards.firstWhere((c) => c.name == n)];
  final main = [for (final c in slice) if (c.isMainDeck && RiftboundParser.parse(c).supported) c.key];
  final bfs = [for (final c in slice) if (c.type == CardType.battlefield) c.key];
  final legends = [for (final c in slice) if (c.type == CardType.legend) c.key];
  final rng = SeededRng(seed);
  final seen = <String, int>{for (final n in names) n: 0};
  var failures = 0, finished = 0;
  final sw = Stopwatch()..start();
  for (var n = 0; n < games; n++) {
    final gameSeed = rng.nextInt(1 << 30);
    List<String> deck() {
      final d = randomDeck(db, rng);
      final out = <String>[];
      var swapped = 0;
      for (final k in d) {
        final c = db[k]!;
        if (c.type == CardType.battlefield && bfs.isNotEmpty) {
          out.add(bfs[rng.nextInt(bfs.length)]);
        } else if (c.type == CardType.legend && legends.isNotEmpty && n % 3 == 0) {
          out.add(legends[rng.nextInt(legends.length)]);
        } else if (c.isMainDeck && !c.champion && swapped < 24 && main.isNotEmpty) {
          out.add(main[rng.nextInt(main.length)]);
          swapped++;
        } else {
          out.add(k);
        }
      }
      return out;
    }

    final decks = [deck(), deck()];
    final g = Game(db, players: ['A', 'B'], seed: gameSeed);
    try {
      g.apply(StartMove(decks));
      final done = runBots(g, [RiftboundBot(0, seed: gameSeed), RiftboundBot(1, seed: gameSeed + 1)], maxMoves: 4000);
      if (done) finished++;
      final r = Game(db, players: ['A', 'B'], seed: gameSeed);
      for (final m in g.actions) {
        r.apply(RMove.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>));
      }
      if (r.fingerprint != g.fingerprint) throw StateError('Replay fingerprint differs');
      for (final l in g.state.log) {
        for (final name in names) {
          if (l.text.contains(name)) seen[name] = seen[name]! + 1;
        }
      }
    } catch (e, st) {
      failures++;
      stderr.writeln('FAIL game $n seed $gameSeed after ${g.actions.length} moves: $e');
      if (failures <= 3) {
        stderr.writeln(st.toString().split('\n').take(10).join('\n'));
        final log = g.state.log;
        stderr.writeln(log.skip(log.length > 12 ? log.length - 12 : 0).map((l) => '   | ${l.text}').join('\n'));
      }
    }
  }
  stdout.writeln('$games games: $finished finished, $failures failed, ${sw.elapsedMilliseconds} ms');
  for (final e in seen.entries) {
    stdout.writeln('  ${e.value.toString().padLeft(5)}  ${e.key}');
  }
  if (failures > 0) exitCode = 1;
}
