// Additional costs of XP and buffs, played-to places and delayed abilities: the Empower / XP /
// buff cards that needed the Hidden and Ambush rules (CR 356.3 additional costs).
import 'package:riftbound/riftbound.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('356.3 additional costs paid in XP or buffs', () {
    test('Wallop: "you may spend a buff as an additional cost. If you do, ignore this spell\'s cost"', () {
      final g = emptyGame();
      final u = g.addCard('Daring Poro', 0, zone: Zone.board, exhausted: true);
      final w = g.addCard('Wallop', 0);
      // No runes and no buff: it can't be paid for.
      expect(g.whyNot(PlayMove(0, w)), isNotNull);
      g.state.obj(u).buffed = true;
      expect(g.whyNot(PlayMove(0, w)), isNull);
      g.apply(PlayMove(0, w));
      // The only buff is spent, as the only way to pay; the only unit is chosen.
      while (g.pending != null) {
        answer(g, [u]);
      }
      passAll(g);
      expect(g.state.obj(u).buffed, isFalse);
      expect(g.state.obj(u).exhausted, isFalse);
      expect(g.state.obj(w).zone, Zone.trash);
    });

    test('Call to Glory: declining the buff, its cost is paid as usual', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 3);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      g.state.obj(u).buffed = true;
      final m = g.might(u);
      g.apply(PlayMove(0, g.addCard('Call to Glory', 0)));
      answer(g, [0]); // don't spend the buff
      if (g.pending != null) answer(g, [u]);
      passAll(g);
      expect(g.state.obj(u).buffed, isTrue);
      expect(g.might(u), m + 3);
      expect(g.state.player(0).runes.where((r) => !g.state.obj(r).exhausted), isEmpty);
    });

    test('Poppy, Defender of the Meek: "spend 3 XP as an additional cost … If you do, I cost {3} less"', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 4);
      final p = g.addCard('Poppy, Defender of the Meek', 0); // {6}{Y}
      expect(g.whyNot(PlayMove(0, p)), isNotNull, reason: 'no XP: {6} with 4 runes');
      g.state.player(0).pw.xp = 3;
      expect(g.whyNot(PlayMove(0, p)), isNull);
      g.apply(PlayMove(0, p));
      // Spending the XP is the only way to pay, so it isn't asked (CR 356).
      while (g.pending != null) {
        answer(g, Game.defaultAnswer(g.pending!.decision));
      }
      passAll(g);
      expect(g.state.obj(p).zone, Zone.board);
      expect(g.state.player(0).pw.xp, 0);
    });

    test('Kraken Hunter: "spend any number of buffs … Reduce my cost by {O} for each buff you spend"', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 3);
      final a = g.addCard('Daring Poro', 0, zone: Zone.board);
      final b = g.addCard('Daring Poro', 0, zone: Zone.board);
      g.state.obj(a).buffed = true;
      g.state.obj(b).buffed = true;
      final k = g.addCard('Kraken Hunter', 0); // {3}{O}{O}
      g.apply(PlayMove(0, k));
      answer(g, [a]);
      answer(g, [b]);
      // At most one buff per {O} in its cost: no third question; Accelerate can't be afforded.
      while (g.pending != null) {
        answer(g, Game.defaultAnswer(g.pending!.decision));
      }
      passAll(g);
      expect(g.state.obj(k).zone, Zone.board);
      expect(g.state.obj(a).buffed || g.state.obj(b).buffed, isFalse);
      expect(g.state.player(0).runes.length, 3, reason: 'no rune recycled for Power');
    });

    test('Safety Inspector: "If you paid my additional cost, you don\'t kill a unit this way"', () {
      for (final paid in [true, false]) {
        final g = emptyGame();
        g.addRunes(0, Domain.order, 6);
        g.state.player(0).pw.xp = 3;
        final mine = g.addCard('Daring Poro', 0, zone: Zone.board);
        final theirs = g.addCard('Daring Poro', 1, zone: Zone.board);
        g.apply(PlayMove(0, g.addCard('Safety Inspector', 0)));
        answer(g, [paid ? 1 : 0]);
        for (var i = 0; g.pending != null && i < 10; i++) {
          final d = g.pending!.decision;
          answer(g, [if (d.options.contains(mine)) mine else if (d.options.contains(theirs)) theirs else ...Game.defaultAnswer(d)]);
          passAll(g);
        }
        passAll(g);
        expect(g.state.objOrNull(theirs)?.zone, isNot(Zone.board));
        expect(g.state.obj(mine).zone == Zone.board, paid, reason: paid ? 'paid: you kill nothing' : 'unpaid: you kill one');
        expect(g.state.player(0).pw.xp, paid ? 0 : 3);
      }
    });

    test('Conscription: "with 3 {M} or less. If you paid the additional cost, choose any enemy unit … instead"', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 7);
      final big = g.addCard('Arachnoid Horror', 1, zone: Zone.board, loc: 0); // 6 Might
      final c = g.addCard('Conscription', 0);
      expect(g.whyNot(PlayMove(0, c)), contains('No legal target'));
      final small = g.addCard('Recruit', 1, zone: Zone.board, loc: 1);
      g.state.player(0).pw.xp = 5;
      g.apply(PlayMove(0, c));
      answer(g, [1]); // spend 5 XP
      expect(g.pending!.decision.options, [big, small]..sort());
      answer(g, [big]);
      passAll(g);
      final o = g.state.obj(big);
      expect(o.controller, 0);
      expect(o.exhausted, isTrue);
      expect((o.zone, o.loc), (Zone.board, base));
      expect(g.state.player(0).pw.xp, 0);
    });
  });

  group('playing to an occupied battlefield', () {
    test('Arachnoid Horror: "I can be played to an occupied battlefield if an enemy unit is alone there"', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 7);
      g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
      g.setControl(0, 1);
      g.addCard('Daring Poro', 1, zone: Zone.board, loc: 1);
      g.addCard('Daring Poro', 1, zone: Zone.board, loc: 1);
      g.setControl(1, 1);
      g.apply(PlayMove(0, g.addCard('Arachnoid Horror', 0)));
      final d = g.pending!.decision;
      expect(d.labels.length, 2, reason: 'its base, and the battlefield with one enemy unit: ${d.labels}');
    });

    test('Arachnoid Horror: "Friendly units can be played to an occupied battlefield if an enemy unit is alone there"', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 2);
      g.addCard('Arachnoid Horror', 0, zone: Zone.board);
      final enemy = g.addCard('Recruit', 1, zone: Zone.board, loc: 0);
      g.setControl(0, 1);
      final u = g.addCard('Daring Poro', 0);
      g.apply(PlayMove(0, u));
      expect(g.pending!.decision.labels.length, 2);
      answer(g, [1]);
      passAll(g);
      expect(g.state.obj(u).loc == 0 || g.state.objOrNull(enemy)?.zone != Zone.board, isTrue);
    });
  });

  test('390 Nami, Headstrong: "When I hold, the next time you play a unit this turn, ready it and [Buff] it"', () {
    final g = emptyGame();
    final n = g.addCard('Nami, Headstrong', 0, zone: Zone.board, loc: 0);
    g.setControl(0, 0);
    g.stackDeck(0, 'Daring Poro', 3);
    g.stackDeck(1, 'Daring Poro', 3);
    g.apply(EndTurnMove(0));
    passAll(g);
    g.apply(EndTurnMove(1));
    passAll(g);
    expect(g.state.active, 0);
    expect(g.state.obj(n).loc, 0);
    g.addRunes(0, Domain.order, 4);
    final a = g.addCard('Daring Poro', 0);
    final b = g.addCard('Daring Poro', 0);
    for (final u in [a, b]) {
      g.apply(PlayMove(0, u));
      if (g.pending != null) answer(g, [0]); // to its base
      passAll(g);
    }
    expect(g.state.obj(a).buffed, isTrue);
    expect(g.state.obj(a).exhausted, isFalse);
    expect(g.state.obj(b).buffed, isFalse, reason: 'only the next unit');
  });
}
