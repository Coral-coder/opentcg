/// Prints the log of one chaos game (same seeds and decks as bin/chaos.dart).
///
///     dart run tool/show_game.dart <game number> [--seed 1] [--db ../../data/pokemon-cards.json]
library;

import 'dart:convert';
import 'dart:io';

import 'package:pokemon/pokemon.dart';
import 'package:tcg_core/tcg_core.dart';

void main(List<String> args) {
  var dbPath = '../../data/pokemon-cards.json';
  var seed = 1;
  final pos = <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--db':
        dbPath = args[++i];
      case '--seed':
        seed = int.parse(args[++i]);
      default:
        pos.add(args[i]);
    }
  }
  final want = int.parse(pos.first);
  final db = PCardDb.fromJson(jsonDecode(File(dbPath).readAsStringSync()) as Map<String, dynamic>);
  final rng = SeededRng(seed);
  for (var n = 0; n <= want; n++) {
    final gameSeed = rng.nextInt(1 << 30);
    final picks = [deckTypes[rng.nextInt(deckTypes.length)], deckTypes[rng.nextInt(deckTypes.length)]];
    final decks = [for (final t in picks) randomDeck(db, t, rng)];
    if (n != want) continue;
    final g = Game(db, players: ['P0 ${picks[0].label}', 'P1 ${picks[1].label}'], seed: gameSeed);
    g.apply(StartMove(decks));
    runBots(g, [PokemonBot(0, seed: gameSeed), PokemonBot(1, seed: gameSeed + 1)], maxMoves: 4000);
    for (final l in g.state.log) {
      stdout.writeln(l.text);
    }
  }
}
