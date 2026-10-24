import 'dart:convert';

import 'package:lorcana/lorcana.dart';
import 'package:tcg_core/tcg_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Game play(int seed) {
  final rng = SeededRng(seed);
  final pairs = inkPairs.keys.toList();
  final decks = [for (var p = 0; p < 2; p++) randomDeck(db, inkPairs[pairs[rng.nextInt(pairs.length)]]!, rng)];
  final g = Game(db, players: ['A', 'B'], seed: seed);
  g.apply(StartMove(decks));
  runBots(g, [LorcanaBot(0, seed: seed), LorcanaBot(1, seed: seed + 1)], maxMoves: 4000);
  return g;
}

void main() {
  test('bot games finish and replay to the same fingerprint, from moves and from JSON', () {
    for (final seed in [1, 2, 3, 4, 5]) {
      final g = play(seed);
      expect(g.over, isTrue, reason: 'seed $seed');
      expect(play(seed).fingerprint, g.fingerprint, reason: 'same seed, same game');
      final r = Game(db, players: ['A', 'B'], seed: seed);
      for (final m in g.moves) {
        r.apply(LMove.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>));
      }
      expect(r.fingerprint, g.fingerprint, reason: 'seed $seed');
      expect(r.state.digest(), g.state.digest());
    }
  });

  test('different seeds give different games', () {
    expect(play(1).fingerprint, isNot(play(2).fingerprint));
  });

  test('the ruleset implements the tcg_core contract', () {
    final rs = LorcanaRuleset(db);
    expect(rs.id, 'lorcana');
    final m = rs.newMatch(['A', 'B'], 9);
    final deck = deckOf(vanilla);
    m.apply(StartMove([deck, deck]));
    expect(m.toAct, isNotNull);
    expect(validateDeck(db, deck), isNotEmpty, reason: 'CR 1.10.1.1 at most 4 copies');
    final names = [
      for (final c in db.cards)
        if (c.type == CardType.character && c.text.isEmpty && c.inks.length == 1 && c.inks.first == Ink.amber) c.fullName,
    ].take(15).toList();
    final legal = [for (final n in names) ...List.filled(4, n)];
    expect(validateDeck(db, legal), isEmpty);
    expect(validateDeck(db, legal.sublist(1)), isNotEmpty, reason: 'at least 60 cards');
  });

  test('a decision pending is part of the fingerprint', () {
    final a = Game(db, players: ['A', 'B'], seed: 4)..apply(StartMove([deckOf(vanilla), deckOf(vanilla2)], firstPlayer: 0));
    final before = a.fingerprint;
    a.apply(AnswerMove(0, const []));
    expect(a.fingerprint, isNot(before));
  });
}
