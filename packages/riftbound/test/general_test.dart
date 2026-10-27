import 'package:riftbound/riftbound.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Real cards read by the general grammar (targets, filters, amounts, triggers, statics).
void main() {
  group('Choosing (CR 355)', () {
    test('355.5 "another unit" is a different unit from the one chosen first (Defiant Dance)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 2);
      final mine = g.addCard('Daring Poro', 0, zone: Zone.board);
      final theirs = g.addCard('Stalwart Poro', 1, zone: Zone.board);
      final third = g.addCard('Daring Poro', 1, zone: Zone.board);
      g.apply(PlayMove(0, g.addCard('Defiant Dance', 0)));
      answer(g, [mine]); // +2
      expect(g.pending?.decision.options, [theirs, third]);
      answer(g, [theirs]); // -2
      passAll(g);
      expect(g.might(mine), 4);
      expect(g.might(theirs), 0);
    });

    test('355.9.b units with less Might than Alpha Wildclaw can’t be chosen by enemy spells', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 2);
      final claw = g.addCard('Alpha Wildclaw', 1, zone: Zone.board, loc: 0);
      final poro = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
      final other = g.addCard('Stalwart Poro', 1, zone: Zone.board, loc: 1);
      g.apply(PlayMove(0, g.addCard('Consuming Curse', 0)));
      final options = g.pending!.decision.options;
      expect(options, containsAll([claw, other]));
      expect(options, isNot(contains(poro)));
    });
  });

  group('Damage (CR 418, 438, 712)', () {
    test('712 Bonus Damage for each card with this name in your trash (Consuming Curse)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 2);
      g.addCard('Consuming Curse', 0, zone: Zone.trash);
      g.addCard('Consuming Curse', 0, zone: Zone.trash);
      final sage = g.addCard('Zephyr Sage', 1, zone: Zone.board, loc: 0);
      g.apply(PlayMove(0, g.addCard('Consuming Curse', 0)));
      passAll(g);
      expect(g.state.obj(sage).damage, 4, reason: '2 + 1 Bonus Damage per copy in the trash');
    });

    test('438 Esteemed Hierophant prevents enemy spell damage while its controller has 7 runes', () {
      for (final (runes, damage) in [(7, 0), (6, 4)]) {
        final g = emptyGame();
        g.addRunes(0, Domain.fury, 2);
        g.addRunes(1, Domain.calm, runes);
        final h = g.addCard('Esteemed Hierophant', 1, zone: Zone.board, loc: 0);
        g.addCard('Consuming Curse', 0, zone: Zone.trash);
        g.addCard('Consuming Curse', 0, zone: Zone.trash);
        g.apply(PlayMove(0, g.addCard('Consuming Curse', 0)));
        passAll(g);
        expect(g.state.obj(h).damage, damage, reason: '$runes runes');
      }
    });

    test('418.6.a damage split among any number of units, one Deal (Volibear, Furious)', () {
      final g = emptyGame();
      g.setControl(0, 1);
      final a = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
      final b = g.addCard('Horns of the Dragon', 1, zone: Zone.board, loc: 0);
      final v = g.addCard('Volibear, Furious', 0, zone: Zone.board);
      g.apply(MoveUnitsMove(0, [v], 0));
      // The attack trigger asks for each point of damage.
      for (final id in [a, a, b, b, b]) {
        expect(g.pending?.decision.prompt, contains('assign 1 damage'));
        answer(g, [id]);
      }
      passAll(g);
      expect(g.state.obj(a).zone, Zone.trash, reason: '2 damage kills the 2-Might Poro');
      expect(g.state.obj(b).zone, Zone.trash, reason: '3 damage, then 9 combat damage');
      expect(g.state.bfs[0].controller, 0);
    });

    test('the discarded card’s Energy cost as damage (Get Excited!)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 2);
      final horns = g.addCard('Horns of the Dragon', 1, zone: Zone.board, loc: 0);
      final spell = g.addCard('Get Excited!', 0);
      final sage = g.addCard('Zephyr Sage', 0); // Energy cost 6
      g.apply(PlayMove(0, spell));
      passAll(g);
      expect(g.state.obj(sage).zone, Zone.trash);
      expect(g.state.obj(horns).zone, Zone.trash, reason: '6 damage to the 6-Might unit');
    });
  });

  group('Countering (CR 426)', () {
    test('Lilting Lullaby counters a spell and its controller can’t play spells this turn', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 4);
      g.addRunes(1, Domain.calm, 4);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      final pump = g.addCard('Discipline', 0);
      final lullaby = g.addCard('Lilting Lullaby', 1);
      g.apply(PlayMove(0, pump));
      expect(g.toAct, 1);
      g.apply(PlayMove(1, lullaby));
      passAll(g);
      expect(g.state.obj(pump).zone, Zone.trash);
      expect(g.might(u), 2);
      expect(g.whyNot(PlayMove(0, g.addCard('Discipline', 0))), contains('can’t play spells'));
    });

    test('Abandon returns the countered spell to its owner’s hand', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 4);
      g.addRunes(1, Domain.chaos, 4);
      g.stackDeck(1, 'Daring Poro', 2);
      g.addCard('Daring Poro', 0, zone: Zone.board);
      final pump = g.addCard('Discipline', 0);
      final abandon = g.addCard('Abandon', 1);
      g.apply(PlayMove(0, pump));
      g.apply(PlayMove(1, abandon));
      while (g.pending != null) {
        answer(g, const []); // Predict: keep the top card
      }
      passAll(g);
      expect(g.state.obj(pump).zone, Zone.hand);
      expect(g.state.player(0).hand, contains(pump));
    });

    test('Decree of Rage can’t be countered', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 2);
      g.addRunes(1, Domain.chaos, 4);
      g.stackDeck(1, 'Daring Poro', 2);
      final poro = g.addCard('Stalwart Poro', 1, zone: Zone.board); // Calm
      final decree = g.addCard('Decree of Rage', 0);
      final abandon = g.addCard('Abandon', 1);
      g.apply(PlayMove(0, decree));
      g.apply(PlayMove(1, abandon));
      while (g.pending != null) {
        answer(g, const []);
      }
      passAll(g);
      expect(g.state.obj(poro).zone, Zone.trash);
      expect(g.state.obj(decree).zone, Zone.trash);
    });
  });

  group('Resources and costs (CR 164, 356)', () {
    test('164 a Seal’s [Add] {R} pays a Fury Power cost', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 3);
      final seal = g.addCard('Seal of Rage', 0, zone: Zone.board);
      final jinx = g.addCard('Jinx, Demolitionist', 0); // {3} + 1 Fury
      expect(g.whyNot(PlayMove(0, jinx)), isNull);
      g.apply(PlayMove(0, jinx));
      if (g.pending?.decision.kind == DecisionKind.yesNo) answer(g, [0]); // no Accelerate
      expect(g.state.obj(jinx).zone, Zone.board);
      expect(g.state.obj(seal).exhausted, isTrue);
    });

    test('356 Sky Splitter costs less by the highest Might among your units', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 3);
      g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
      final spell = g.addCard('Sky Splitter', 0); // {8} + 1 Fury
      expect(g.whyNot(PlayMove(0, spell)), isNotNull);
      g.addCard('Zephyr Sage', 0, zone: Zone.board); // 6 Might
      expect(g.whyNot(PlayMove(0, spell)), isNull, reason: '{2} + 1 Fury');
    });

    test('an activated ability usable only while I’m at a battlefield (Caitlyn, Patrolling)', () {
      final g = emptyGame();
      final c = g.addCard('Caitlyn, Patrolling', 0, zone: Zone.board);
      g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
      final i = RiftboundParser.parse(g.card(c)).abilities.indexWhere((a) => a is Activated);
      expect(g.whyNot(ActivateMove(0, c, i)), isNotNull);
      g.state.obj(c).loc = 1;
      expect(g.whyNot(ActivateMove(0, c, i)), isNull);
    });
  });

  group('Hands, decks and zones', () {
    test('Mindsplitter: the opponent reveals their hand and discards the card you choose', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 9);
      final keep = g.addCard('Daring Poro', 1);
      final lose = g.addCard('Discipline', 1);
      g.apply(PlayMove(0, g.addCard('Mindsplitter', 0)));
      passAll(g);
      expect(g.pending?.decision.options, containsAll([keep, lose]));
      answer(g, [lose]);
      passAll(g);
      expect(g.state.obj(lose).zone, Zone.trash);
      expect(g.state.obj(keep).zone, Zone.hand);
    });

    test('Time Warp: banished after it resolves, and its controller takes the next turn too', () {
      final g = emptyGame();
      g.stackDeck(0, 'Daring Poro', 4);
      g.stackDeck(1, 'Daring Poro', 4);
      g.addRunes(0, Domain.mind, 14);
      final warp = g.addCard('Time Warp', 0);
      g.apply(PlayMove(0, warp));
      passAll(g);
      expect(g.state.obj(warp).zone, Zone.banish);
      g.apply(const EndTurnMove(0));
      expect(g.state.active, 0);
    });

    test('Mobilize: channel 1 rune exhausted, or draw 1 if you can’t', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 2);
      g.stackDeck(0, 'Daring Poro', 2);
      g.apply(PlayMove(0, g.addCard('Mobilize', 0)));
      passAll(g);
      expect(g.state.player(0).hand, hasLength(1), reason: 'an empty rune deck: no rune to channel');
    });
  });

  group('Triggers (CR 383)', () {
    test('467.2.c.4 excess combat damage: Yeti Brawler conquers after assigning 3 or more', () {
      final g = emptyGame();
      g.setControl(0, 1);
      g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0); // 2 Might: 4 excess
      final yeti = g.addCard('Yeti Brawler', 0, zone: Zone.board); // 6 Might
      g.apply(MoveUnitsMove(0, [yeti], 0));
      passAll(g);
      final gold = [
        for (final o in g.state.objects.values)
          if (o.zone == Zone.board && g.card(o.id).name == 'Gold') o,
      ];
      expect(gold, hasLength(2));
      expect(gold.every((o) => o.exhausted), isTrue);
    });

    test('467.2.c.4 exactly 3 excess: Yeti Brawler against a Shielded defender', () {
      final g = emptyGame();
      g.setControl(0, 1);
      g.addCard('Stalwart Poro', 1, zone: Zone.board, loc: 0); // 2 Might, Shield: 3 while defending
      final yeti = g.addCard('Yeti Brawler', 0, zone: Zone.board);
      g.apply(MoveUnitsMove(0, [yeti], 0));
      passAll(g);
      expect([
        for (final o in g.state.objects.values)
          if (o.zone == Zone.board && g.card(o.id).name == 'Gold') o,
      ], hasLength(2));
    });

    test('2 excess is not enough (Yeti Brawler against a 4-Might defender)', () {
      final g = emptyGame();
      g.setControl(0, 1);
      g.addCard('Jinx, Demolitionist', 1, zone: Zone.board, loc: 0); // 4 Might
      final yeti = g.addCard('Yeti Brawler', 0, zone: Zone.board);
      g.apply(MoveUnitsMove(0, [yeti], 0));
      passAll(g);
      expect(g.state.bfs[0].controller, 0, reason: 'it conquered');
      expect([
        for (final o in g.state.objects.values)
          if (o.zone == Zone.board && g.card(o.id).name == 'Gold') o,
      ], isEmpty);
    });

    test('When I move from a location: Lillia leaves a Sprite where she was', () {
      final g = emptyGame();
      g.setControl(0, 0);
      final l = g.addCard('Lillia, Fae Fawn', 0, zone: Zone.board, loc: 0);
      g.apply(MoveUnitsMove(0, [l], base));
      passAll(g);
      final sprites = [
        for (final u in g.unitsAt(0, player: 0))
          if (g.card(u).name == 'Sprite') u,
      ];
      expect(sprites, hasLength(1));
    });

    test('When you discard me: Mask Mother triggers from the trash', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 3);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      g.addCard('Horns of the Dragon', 1, zone: Zone.board, loc: 0);
      final mm = g.addCard('Mask Mother', 0);
      g.apply(PlayMove(0, g.addCard('Get Excited!', 0)));
      passAll(g);
      expect(g.state.obj(mm).zone, Zone.trash);
      // "You may pay {1}": yes; the only friendly unit was chosen as it triggered.
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
      answer(g, [1]);
      passAll(g);
      expect(g.might(u), 4);
    });
  });
}
