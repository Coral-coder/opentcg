import 'package:riftbound/riftbound.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Correctness audit: supported cards that the engine read or ran differently from their text.
/// Each test plays the real card.
void main() {
  /// Three ready runes of every domain for [p].
  void runes(Game g, int p) {
    for (final d in Domain.values) {
      g.addRunes(p, d, 3);
    }
  }

  group('"There": units at a battlefield chosen earlier in the same spell (CR 355.3)', () {
    test('Moonfall: enemy units at the chosen battlefield get -2 {M}, including the one moved there', () {
      final g = emptyGame();
      runes(g, 0);
      final mine = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 1);
      final moved = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0); // 2 Might
      final there = g.addCard('Stalwart Poro', 1, zone: Zone.board, loc: 1); // 2 Might
      g.apply(PlayMove(0, g.addCard('Moonfall', 0)));
      // The only battlefield with a friendly unit is chosen; then the enemy to move, and yes.
      answer(g, [moved]);
      answer(g, [1]);
      // A combat follows at once: both enemies are at 0 {M} after -2, so both die (at 2 {M} they'd
      // have survived the 1 damage each); my Daring Poro takes none.
      passAll(g);
      expect(g.state.obj(moved).zone, Zone.trash);
      expect(g.state.obj(there).zone, Zone.trash);
      expect(g.state.obj(mine).damage, 0);
    });

    test('Siphon Power: +1 {M} to friendly units there and -1 {M} to enemy units there, nowhere else', () {
      final g = emptyGame();
      runes(g, 0);
      final mine = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 0);
      final enemy = g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 0);
      final elsewhere = g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 1);
      g.apply(PlayMove(0, g.addCard('Siphon Power', 0)));
      answer(g, [g.state.bfs[0].obj]);
      passAll(g);
      expect(g.state.obj(mine).mightMod, 1);
      expect(g.state.obj(enemy).mightMod, -1);
      expect(g.state.obj(elsewhere).mightMod, 0);
    });

    test('Bullet Time: asks how much {A} to pay and deals that much to each enemy unit at the chosen battlefield', () {
      final g = emptyGame();
      runes(g, 0);
      final a = g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 0);
      final b = g.addCard('Stalwart Poro', 1, zone: Zone.board, loc: 0);
      final away = g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 1);
      g.apply(PlayMove(0, g.addCard('Bullet Time', 0)));
      while (g.pending != null) {
        final d = g.pending!.decision;
        // Battlefield 0; then pay two {A} (the labels are 0, 1, 2, …).
        answer(g, d.kind == DecisionKind.cards ? [g.state.bfs[0].obj] : [2]);
      }
      passAll(g);
      expect(g.state.obj(a).damage, 2);
      expect(g.state.obj(b).zone, Zone.trash, reason: '2 damage kills a 2 Might unit');
      expect(g.state.obj(away).damage, 0);
    });

    test('Heroic Charge: stuns an enemy unit at the location of the chosen friendly unit', () {
      final g = emptyGame();
      runes(g, 0);
      final mine = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 0);
      final enemy = g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 0);
      g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 1);
      g.apply(PlayMove(0, g.addCard('Heroic Charge', 0)));
      // Daring Poro is the only friendly unit and the Sergeant at its battlefield the only enemy
      // there, so neither needs asking; before the fix the enemy was never found.
      while (g.pending != null) {
        answer(g, [g.pending!.decision.options.contains(enemy) ? enemy : mine]);
      }
      passAll(g);
      expect(g.state.obj(mine).mightMod, 1);
      expect(g.state.obj(enemy).stunned, isTrue);
    });

    test('Public Execution: kills an enemy unit with less Might than the chosen friendly unit', () {
      final g = emptyGame();
      runes(g, 0);
      final big = g.addCard('Vanguard Sergeant', 0, zone: Zone.board); // 4 Might
      final small = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0); // 2 Might
      g.apply(PlayMove(0, g.addCard('Public Execution', 0)));
      while (g.pending != null) {
        answer(g, [g.pending!.decision.options.contains(small) ? small : big]);
      }
      passAll(g);
      expect(g.state.obj(small).zone, Zone.trash);
    });
  });

  group('Tokens enter as the text says (CR 187)', () {
    for (final name in ['Wages of Pain', 'Bushwhack']) {
      test('$name: "Play a Gold gear token exhausted" plays it exhausted', () {
        final g = emptyGame();
        runes(g, 0);
        g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
        final before = g.state.objects.keys.toSet();
        g.apply(PlayMove(0, g.addCard(name, 0)));
        while (g.pending != null) {
          answer(g, g.pending!.decision.kind == DecisionKind.cards ? [g.pending!.decision.options.first] : [0]);
        }
        passAll(g);
        final gold = g.state.objects.values.where((o) => !before.contains(o.id) && o.card == 'Gold').toList();
        expect(gold, hasLength(1));
        expect(gold.single.exhausted, isTrue, reason: 'an exhausted Gold can’t be killed for {A} this turn');
      });
    }
  });

  group('Choosing where damage goes', () {
    test('467.2.c the attacker chooses which defender takes lethal damage first', () {
      final g = emptyGame();
      g.setControl(0, 1);
      final small = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0); // 2 Might
      final big = g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 0); // 3 Might
      final att = g.addCard('Vanguard Sergeant', 0, zone: Zone.board); // 4 Might
      g.apply(MoveUnitsMove(0, [att], 0));
      passAll(g);
      expect(g.pending?.decision.player, 0, reason: 'the attacker assigns first');
      expect(g.pending?.decision.options, [small, big], reason: 'the weakest is offered first');
      answer(g, [big]); // 3 lethal to the Skulker, the last 1 on the Poro
      while (g.pending != null) {
        answer(g, [g.pending!.decision.options.first]);
      }
      expect(g.state.obj(big).zone, Zone.trash);
      expect(g.state.obj(small).zone, Zone.board);
    });

    test('467.2.c.3 no question when the damage kills them all, and Tank still goes first', () {
      final g = emptyGame();
      g.setControl(0, 1);
      final tank = g.addCard('Sunlit Guardian', 1, zone: Zone.board, loc: 0); // [Tank]
      final other = g.addCard('Stalwart Poro', 1, zone: Zone.board, loc: 0);
      final att = g.addCard('Daring Poro', 0, zone: Zone.board); // 2 Might, [Assault]: 3 attacking
      g.apply(MoveUnitsMove(0, [att], 0));
      passAll(g);
      while (g.pending != null) {
        expect(g.pending!.decision.options, isNot(contains(other)), reason: 'Tank must take lethal first');
        answer(g, [g.pending!.decision.options.first]);
      }
      final hits = [for (final l in g.state.log) if (l.text.contains('combat damage')) l.text];
      expect(hits, contains('Sunlit Guardian takes 3 combat damage.'));
      expect(hits.where((h) => h.startsWith('Stalwart Poro takes')), isEmpty);
      expect(tank, isPositive);
    });

    test('355.14 Alpha Strike: the player splits the damage as they like', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 4);
      g.addCard('Bandle Soldier', 0, zone: Zone.board); // 5 Might
      final a = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0); // 2
      final b = g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 1); // 4
      g.apply(PlayMove(0, g.addCard('Alpha Strike', 0)));
      passAll(g);
      // All 5 on the Sergeant (the engine used to kill the Poro first).
      while (g.pending != null) {
        answer(g, [b]);
      }
      expect(g.state.obj(b).zone, Zone.trash);
      expect(g.state.obj(a).damage, 0);
      expect(g.state.player(0).pw.xp, 1, reason: '1 XP for the one kill');
    });
  });
}
