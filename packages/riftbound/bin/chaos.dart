/// Chaos harness: plays many bot games from random seeds and random decks of supported cards,
/// then replays each from its moves (and from their JSON) and checks the fingerprints match.
///
///     dart run bin/chaos.dart [--db ../../data/riftbound-cards.json] [--games 200] [--seed 1] [--mode duel|ffa3|ffa4|2v2] [--verbose] [--only N]
library;

import 'dart:convert';
import 'dart:io';

import 'package:riftbound/riftbound.dart';
import 'package:tcg_core/tcg_core.dart';

void main(List<String> args) {
  var dbPath = '../../data/riftbound-cards.json';
  var games = 200, seed = 1;
  var verbose = false;
  var mode = RMode.duel;
  int? only;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--db':
        dbPath = args[++i];
      case '--games':
        games = int.parse(args[++i]);
      case '--seed':
        seed = int.parse(args[++i]);
      case '--mode':
        mode = RMode.fromId(args[++i]);
      case '--verbose':
        verbose = true;
      case '--only':
        only = int.parse(args[++i]);
    }
  }
  final db = RCardDb.fromJson(jsonDecode(File(dbPath).readAsStringSync()) as Map<String, dynamic>);
  final rng = SeededRng(seed);
  var finished = 0, failures = 0, turns = 0, moves = 0;
  final n0 = mode.players;
  final wins = List.filled(n0 + 1, 0);
  final sw = Stopwatch()..start();
  for (var n = 0; n < games; n++) {
    final gameSeed = rng.nextInt(1 << 30);
    final decks = randomDecksFor(db, rng, mode);
    if (only != null && n != only) continue;
    final names = [for (var p = 0; p < n0; p++) 'P$p ${deckLegend(db, decks[p])!.name}'];
    final g = Game(db, players: names, seed: gameSeed);
    try {
      for (final d in decks) {
        final bad = validateDeck(db, d);
        if (bad.isNotEmpty) throw StateError('Illegal random deck: ${bad.join('; ')}');
      }
      g.apply(StartMove(decks, mode: mode));
      final done = runBots(g, [for (var p = 0; p < n0; p++) RiftboundBot(p, seed: gameSeed + p)], maxMoves: 4000 * n0 ~/ 2);
      final fp = g.fingerprint;
      final r = Game(db, players: names, seed: gameSeed);
      for (final m in g.actions) {
        r.apply(m);
      }
      if (r.fingerprint != fp) throw StateError('Replay fingerprint differs');
      final r2 = Game(db, players: names, seed: gameSeed);
      for (final m in g.actions) {
        r2.apply(RMove.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>));
      }
      if (r2.fingerprint != fp) throw StateError('JSON replay fingerprint differs');
      if (done) {
        finished++;
        wins[g.state.winner ?? n0]++;
      } else if (verbose) {
        stdout.writeln('  unfinished: toAct ${g.toAct} pending ${g.pending?.decision.prompt}');
      }
      turns += g.state.turn;
      moves += g.actions.length;
      if (verbose) {
        stdout.writeln('game $n seed $gameSeed ${names.join(' vs ')}: ${done ? 'won by ${g.state.winner ?? 'nobody'}' : 'unfinished'} on turn ${g.state.turn}, ${g.actions.length} moves, points ${g.state.players.map((p) => p.points).join('-')}');
      }
    } catch (e, st) {
      failures++;
      stderr.writeln('FAIL game $n seed $gameSeed ${names.join(' vs ')} after ${g.actions.length} moves, turn ${g.state.turn}: $e');
      if (verbose || failures <= 3) {
        stderr.writeln(st.toString().split('\n').take(12).join('\n'));
        final log = g.state.log;
        stderr.writeln(log.skip(log.length > 15 ? log.length - 15 : 0).map((l) => '   | ${l.text}').join('\n'));
      }
    }
  }
  final played = only == null ? games : 1;
  stdout.writeln(
    '${mode == RMode.duel ? '' : '${mode.id}: '}$played games: $finished finished (${[for (var p = 0; p < n0; p++) 'P$p ${wins[p]}'].join(', ')}, draws ${wins[n0]}), $failures failed, avg ${(turns / played).toStringAsFixed(1)} turns, ${(moves / played).toStringAsFixed(0)} moves, ${sw.elapsedMilliseconds} ms',
  );
  if (failures > 0 || finished < played) exitCode = 1;
}
