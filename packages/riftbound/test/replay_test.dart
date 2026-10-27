import 'dart:convert';

import 'package:riftbound/riftbound.dart';
import 'package:tcg_core/tcg_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('a bot game replays to the same fingerprint, from moves and from JSON', () {
    for (final seed in [3, 11, 29]) {
      final rng = SeededRng(seed);
      final decks = [randomDeck(db, rng), randomDeck(db, rng)];
      final g = Game(db, players: ['A', 'B'], seed: seed);
      g.apply(StartMove(decks));
      expect(runBots(g, [RiftboundBot(0, seed: seed), RiftboundBot(1, seed: seed + 1)], maxMoves: 4000), isTrue);
      final r = Game(db, players: ['A', 'B'], seed: seed);
      for (final m in g.actions) {
        r.apply(RMove.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>));
      }
      expect(r.fingerprint, g.fingerprint);
      expect(r.state.winner, g.state.winner);
    }
  });

  test('the ruleset deals, plays and concedes through the shared contract', () {
    final rs = RiftboundRuleset(db);
    final g = rs.newMatch(['A', 'B'], 9);
    g.apply(rs.deal([starter(0), starter(1)], {'first': 1}));
    expect(g.toAct, 1, reason: 'the first player mulligans first');
    g.apply(rs.concede(0));
    expect(g.over, isTrue);
    expect(g.state.winner, 1);
  });
}
