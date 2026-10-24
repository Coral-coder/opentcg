/// Chaos harness: plays many bot games from random seeds and random decks of supported cards,
/// then replays each from its moves (and from their JSON) and checks the fingerprints match.
///
///     dart run bin/chaos.dart [--db ../../data/lorcana-cards.json] [--games 200] [--seed 1] [--verbose] [--only N]
library;

import 'dart:convert';
import 'dart:io';

import 'package:lorcana/lorcana.dart';
import 'package:tcg_core/tcg_core.dart';

void main(List<String> args) {
  var dbPath = '../../data/lorcana-cards.json';
  var games = 200, seed = 1;
  var verbose = false;
  int? only;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--db':
        dbPath = args[++i];
      case '--games':
        games = int.parse(args[++i]);
      case '--seed':
        seed = int.parse(args[++i]);
      case '--verbose':
        verbose = true;
      case '--only':
        only = int.parse(args[++i]);
    }
  }
  final db = LCardDb.fromJson(jsonDecode(File(dbPath).readAsStringSync()) as Map<String, dynamic>);
  final pairs = inkPairs.keys.toList();
  final rng = SeededRng(seed);
  var finished = 0, failures = 0, turns = 0, moves = 0;
  final sw = Stopwatch()..start();
  for (var n = 0; n < games; n++) {
    final gameSeed = rng.nextInt(1 << 30);
    final picks = [pairs[rng.nextInt(pairs.length)], pairs[rng.nextInt(pairs.length)]];
    final decks = [for (final p in picks) randomDeck(db, inkPairs[p]!, rng)];
    if (only != null && n != only) continue;
    final g = Game(db, players: ['P0 ${picks[0]}', 'P1 ${picks[1]}'], seed: gameSeed);
    try {
      g.apply(StartMove(decks));
      final done = runBots(g, [LorcanaBot(0, seed: gameSeed), LorcanaBot(1, seed: gameSeed + 1)], maxMoves: 4000);
      final fp = g.fingerprint;
      final r = Game(db, players: [for (final p in g.state.players) p.name], seed: gameSeed);
      for (final m in g.actions) {
        r.apply(m);
      }
      if (r.fingerprint != fp) throw StateError('Replay fingerprint differs');
      final r2 = Game(db, players: [for (final p in g.state.players) p.name], seed: gameSeed);
      for (final m in g.actions) {
        r2.apply(LMove.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>));
      }
      if (r2.fingerprint != fp) throw StateError('JSON replay fingerprint differs');
      if (done) finished++;
      turns += g.state.turn;
      moves += g.actions.length;
      if (verbose) {
        stdout.writeln(
          'game $n seed $gameSeed ${picks.join(' vs ')}: ${done ? 'won by ${g.state.winner}' : 'unfinished'} on turn ${g.state.turn}, ${g.actions.length} moves, lore ${g.state.players.map((p) => p.lore).join('-')}',
        );
      }
    } catch (e, st) {
      failures++;
      stderr.writeln('FAIL game $n seed $gameSeed ${picks.join(' vs ')} after ${g.actions.length} moves, turn ${g.state.turn}: $e');
      if (verbose || failures <= 3) {
        stderr.writeln(st.toString().split('\n').take(12).join('\n'));
        final log = g.state.log;
        stderr.writeln(log.skip(log.length > 15 ? log.length - 15 : 0).map((l) => '   | ${l.text}').join('\n'));
      }
    }
  }
  final played = only == null ? games : 1;
  stdout.writeln('$played games: $finished finished, $failures failed, avg ${(turns / played).toStringAsFixed(1)} turns, ${(moves / played).toStringAsFixed(0)} moves, ${sw.elapsedMilliseconds} ms');
  if (failures > 0) exitCode = 1;
}
