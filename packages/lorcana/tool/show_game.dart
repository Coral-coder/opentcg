import 'dart:convert';
import 'dart:io';

import 'package:lorcana/lorcana.dart';
import 'package:tcg_core/tcg_core.dart';

void main(List<String> args) {
  final db = LCardDb.fromJson(jsonDecode(File('../../data/lorcana-cards.json').readAsStringSync()) as Map<String, dynamic>);
  final rng = SeededRng(int.parse(args[0]));
  final decks = [randomDeck(db, inkPairs.values.first, rng), randomDeck(db, inkPairs.values.elementAt(4), rng)];
  final g = Game(db, players: ['Ann', 'Bob'], seed: 5);
  g.apply(StartMove(decks));
  runBots(g, [LorcanaBot(0, seed: 1), LorcanaBot(1, seed: 2)]);
  for (final l in g.state.log.take(int.parse(args[1]))) {
    print(l.text);
  }
}
