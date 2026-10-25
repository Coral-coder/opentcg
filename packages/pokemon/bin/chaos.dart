/// Chaos harness: plays many bot games from random seeds and random decks of supported cards,
/// then replays each from its moves (and from their JSON) and checks the fingerprints match.
///
///     dart run bin/chaos.dart [--db ../../data/pokemon-cards.json] [--games 200] [--seed 1] [--verbose] [--only N]
library;

import 'dart:convert';
import 'dart:io';

import 'package:pokemon/pokemon.dart';
import 'package:tcg_core/tcg_core.dart';

void main(List<String> args) {
  var dbPath = '../../data/pokemon-cards.json';
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
  final db = PCardDb.fromJson(jsonDecode(File(dbPath).readAsStringSync()) as Map<String, dynamic>);
  final rng = SeededRng(seed);
  var finished = 0, failures = 0, turns = 0, moves = 0;
  final wins = [0, 0, 0];
  final sw = Stopwatch()..start();
  for (var n = 0; n < games; n++) {
    final gameSeed = rng.nextInt(1 << 30);
    final picks = [deckTypes[rng.nextInt(deckTypes.length)], deckTypes[rng.nextInt(deckTypes.length)]];
    final decks = [for (final t in picks) randomDeck(db, t, rng)];
    if (only != null && n != only) continue;
    final names = ['P0 ${picks[0].label}', 'P1 ${picks[1].label}'];
    final g = Game(db, players: names, seed: gameSeed);
    try {
      for (final d in decks) {
        final bad = validateDeck(db, d);
        if (bad.isNotEmpty) throw StateError('Illegal random deck: ${bad.join('; ')}');
      }
      g.apply(StartMove(decks));
      final done = runBots(g, [PokemonBot(0, seed: gameSeed), PokemonBot(1, seed: gameSeed + 1)], maxMoves: 4000);
      final fp = g.fingerprint;
      final r = Game(db, players: names, seed: gameSeed);
      for (final m in g.actions) {
        r.apply(m);
      }
      if (r.fingerprint != fp) throw StateError('Replay fingerprint differs');
      final r2 = Game(db, players: names, seed: gameSeed);
      for (final m in g.actions) {
        r2.apply(PMove.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>));
      }
      if (r2.fingerprint != fp) throw StateError('JSON replay fingerprint differs');
      if (done) {
        finished++;
        wins[g.state.winner ?? 2]++;
      }
      turns += g.state.turn;
      moves += g.actions.length;
      if (verbose) {
        stdout.writeln('game $n seed $gameSeed ${names.join(' vs ')}: ${done ? 'won by ${g.state.winner ?? 'nobody'}' : 'unfinished'} on turn ${g.state.turn}, ${g.actions.length} moves, prizes left ${g.state.players.map((p) => p.prizes.length).join('-')}');
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
    '$played games: $finished finished (P0 ${wins[0]}, P1 ${wins[1]}, draws ${wins[2]}), $failures failed, avg ${(turns / played).toStringAsFixed(1)} turns, ${(moves / played).toStringAsFixed(0)} moves, ${sw.elapsedMilliseconds} ms',
  );
  if (failures > 0) exitCode = 1;
}
