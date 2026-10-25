import 'dart:convert';

import 'package:pokemon/pokemon.dart';
import 'package:tcg_core/tcg_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Game play(int seed) {
  final rng = SeededRng(seed);
  final decks = [for (var p = 0; p < 2; p++) randomDeck(db, deckTypes[rng.nextInt(deckTypes.length)], rng)];
  final g = Game(db, players: ['A', 'B'], seed: seed);
  g.apply(StartMove(decks));
  runBots(g, [PokemonBot(0, seed: seed), PokemonBot(1, seed: seed + 1)], maxMoves: 4000);
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
        r.apply(PMove.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>));
      }
      expect(r.fingerprint, g.fingerprint, reason: 'seed $seed');
      expect(r.state.digest(), g.state.digest());
    }
  });

  test('different seeds give different games', () {
    expect(play(1).fingerprint, isNot(play(2).fingerprint));
  });

  test('random decks are legal', () {
    final rng = SeededRng(11);
    for (final t in deckTypes) {
      expect(validateDeck(db, randomDeck(db, t, rng)), isEmpty, reason: t.label);
    }
  });

  test('the ruleset implements the tcg_core contract', () {
    final rs = PokemonRuleset(db);
    expect(rs.id, 'pokemon');
    expect(rs.engineVersion, pokemonEngineVersion);
    final rng = SeededRng(3);
    final decks = [randomDeck(db, PType.fire, rng), randomDeck(db, PType.water, rng)];
    final m = rs.newMatch(['A', 'B'], 9);
    m.apply(rs.deal(decks, {'first': 1}));
    expect(m.toAct, isNotNull);
    expect(m.state.firstPlayer, 1, reason: 'deal options: first');
    final bots = [rs.bot(0, 1), rs.bot(1, 2)];
    for (var i = 0; i < 4000 && !m.over; i++) {
      final seat = m.toAct;
      if (seat == null || !bots[seat].step(m)) break;
    }
    expect(m.over, isTrue);
    final again = rs.newMatch(['A', 'B'], 9);
    for (final mv in m.moves) {
      again.apply(rs.moveFromJson(jsonDecode(jsonEncode(mv.toJson())) as Map<String, dynamic>));
    }
    expect(again.fingerprint, m.fingerprint);
  });

  test('a pending decision is part of the fingerprint', () {
    final a = Game(fixtures, players: ['A', 'B'], seed: 4)..apply(StartMove([deckOf('T Sprout', n: 20), deckOf('T Ember', n: 20)], firstPlayer: 0));
    final before = a.fingerprint;
    expect(a.pending, isNotNull);
    answer(a, a.defaultAnswer(a.pending!.decision));
    expect(a.fingerprint, isNot(before));
  });

  test('a refused answer leaves the game as it was', () {
    final a = Game(fixtures, players: ['A', 'B'], seed: 4)..apply(StartMove([deckOf('T Sprout', n: 20), deckOf('T Ember', n: 20)], firstPlayer: 0));
    final before = a.fingerprint;
    expect(() => a.apply(AnswerMove(0, const [999])), throwsA(isA<PokemonError>()));
    expect(a.fingerprint, before);
  });
}
