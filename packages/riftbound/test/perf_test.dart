import 'package:riftbound/riftbound.dart';
import 'package:tcg_core/tcg_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The engine's speed-ups must not change what it does: probe copies of the state skip the log's
/// entries but keep its count, and answers given under [Game.readOnly] (one scan of the passives)
/// match the ones given without it.
void main() {
  Game midGame(int seed, int steps) {
    final rng = SeededRng(seed);
    final g = Game(db, players: ['A', 'B'], seed: seed);
    g.apply(StartMove([randomDeck(db, rng), randomDeck(db, rng)]));
    final bots = [RiftboundBot(0, seed: seed), RiftboundBot(1, seed: seed + 1)];
    for (var i = 0; i < steps && !g.over; i++) {
      final seat = g.toAct;
      if (seat == null || !bots[seat].step(g)) break;
    }
    return g;
  }

  test('a probe copy has the same digest and log count as a full copy', () {
    final g = midGame(3, 60);
    expect(g.state.log, isNotEmpty);
    final full = g.state.clone(), probe = g.state.clone(probe: true);
    expect(probe.log, isEmpty);
    expect(probe.logCount, g.state.logCount);
    expect(probe.digest(), full.digest());
    expect(full.digest(), g.state.digest());
  });

  test('Might, keywords and legal moves are the same under readOnly', () {
    for (final seed in [1, 2, 5]) {
      final g = midGame(seed, 50);
      final units = [for (final o in g.state.objects.values) if (o.zone == Zone.board && g.isUnit(o.id)) o.id];
      final plain = [for (final u in units) (g.might(u), g.hasKw(u, Kw.assault), g.hasKw(u, Kw.shield))];
      final cached = g.readOnly(() => [for (final u in units) (g.might(u), g.hasKw(u, Kw.assault), g.hasKw(u, Kw.shield))]);
      expect(cached, plain, reason: 'seed $seed');
      final seat = g.toAct;
      if (seat == null || g.pending != null) continue;
      final moves = g.legalMoves(seat).map((m) => m.toString()).toList();
      expect(g.readOnly(() => g.legalMoves(seat)).map((m) => m.toString()).toList(), moves, reason: 'seed $seed');
      final digest = g.state.digest();
      g.legalMoves(seat);
      expect(g.state.digest(), digest, reason: 'checking moves must not change the game');
    }
  });
}
