import 'package:riftbound/riftbound.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Wave 2, slice 1: the one-off cards from Acceleration Gate to Fiora, Peerless, played for real.

/// Ends player 0's turn and player 1's, back to player 0's Main Phase (default answers).
void nextOwnTurn(Game g) {
  g.apply(const EndTurnMove(0));
  while (g.pending != null) {
    answer(g, Game.defaultAnswer(g.pending!.decision));
  }
  passAll(g);
  g.apply(const EndTurnMove(1));
  while (g.pending != null) {
    answer(g, Game.defaultAnswer(g.pending!.decision));
  }
  passAll(g);
}

/// Answers every pending decision with its default, passing open chains, until nothing waits.
void settle(Game g) {
  for (var i = 0; i < 40 && !g.over; i++) {
    if (g.pending != null) {
      answer(g, Game.defaultAnswer(g.pending!.decision));
      continue;
    }
    if (g.state.chain.isEmpty && g.state.showdown == null) return;
    g.apply(PassMove(g.toAct!));
  }
}

ObjId runeInDeck(Game g, int p, Domain d) {
  final id = g.addCard('${d.label} Rune', p, zone: Zone.runeDeck);
  g.state.player(p).runeDeck.add(id);
  return id;
}

void main() {
  group('Spells', () {
    test('Acceleration Gate readies up to 4 units, gear and/or runes, anyone’s (CR 355.5)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 4);
      final mine = g.addCard('Daring Poro', 0, zone: Zone.board, exhausted: true);
      final theirs = g.addCard('Stalwart Poro', 1, zone: Zone.board, exhausted: true);
      g.addRunes(0, Domain.body, 1);
      final rune = g.state.player(0).runes.last;
      g.state.obj(rune).exhausted = true;
      g.apply(PlayMove(0, g.addCard('Acceleration Gate', 0)));
      final d = g.pending!.decision;
      expect(d.options, containsAll([mine, theirs, rune]));
      expect(d.max, 3, reason: 'up to 4, but only 3 are exhausted');
      answer(g, [mine, rune]);
      passAll(g);
      expect(g.state.obj(mine).exhausted, isFalse);
      expect(g.state.obj(rune).exhausted, isFalse);
      expect(g.state.obj(theirs).exhausted, isTrue);
    });

    test('801.3.a.3 Blood Rush gives [Assault 2] with no duration: it lasts while the unit stays', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 1);
      final u = g.addCard('Vanguard Sergeant', 0, zone: Zone.board);
      g.apply(PlayMove(0, g.addCard('Blood Rush', 0)));
      if (g.pending?.decision.kind == DecisionKind.yesNo) answer(g, [0]); // no Repeat
      if (g.pending != null) answer(g, [u]);
      passAll(g);
      expect(g.state.gen.lasting['o$u:kw${Kw.assault.index}'], 2);
      nextOwnTurn(g);
      expect(g.state.gen.lasting['o$u:kw${Kw.assault.index}'], 2, reason: 'still there next turn');
    });

    test('Call to Battle: an opponent then moves a unit of theirs to the same battlefield', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 3);
      g.setControl(0, 0);
      g.addCard('Vanguard Sergeant', 0, zone: Zone.board, loc: 0);
      final mine = g.addCard('Zephyr Sage', 0, zone: Zone.board); // 6
      final theirs = g.addCard('Stalwart Poro', 1, zone: Zone.board);
      final stays = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 1); // a second unit of theirs: they choose
      g.apply(PlayMove(0, g.addCard('Call to Battle', 0)));
      while (g.pending != null && g.pending!.decision.player == 0) {
        final d = g.pending!.decision;
        answer(g, d.kind == DecisionKind.cards ? [mine] : [0]);
      }
      passAll(g);
      expect(g.pending?.decision.player, 1, reason: 'the opponent chooses their unit');
      answer(g, [theirs]);
      settle(g);
      expect(g.state.obj(mine).loc, 0);
      expect(g.state.obj(theirs).zone, Zone.trash, reason: 'it moved there and lost the combat');
      expect(g.state.obj(stays).loc, 1);
    });

    test('Catalyst of Aeons draws when it can’t channel both runes', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 4);
      runeInDeck(g, 0, Domain.body);
      g.stackDeck(0, 'Daring Poro', 2);
      g.apply(PlayMove(0, g.addCard('Catalyst of Aeons', 0)));
      passAll(g);
      expect(g.state.player(0).runes, hasLength(5));
      expect(g.state.obj(g.state.player(0).runes.last).exhausted, isTrue, reason: 'channeled exhausted');
      expect(g.state.player(0).hand, hasLength(1), reason: 'only 1 of 2 channeled: draw 1');
      // With two runes left in the rune deck it doesn't draw.
      final g2 = emptyGame();
      g2.addRunes(0, Domain.body, 4);
      runeInDeck(g2, 0, Domain.body);
      runeInDeck(g2, 0, Domain.body);
      g2.stackDeck(0, 'Daring Poro', 2);
      g2.apply(PlayMove(0, g2.addCard('Catalyst of Aeons', 0)));
      passAll(g2);
      expect(g2.state.player(0).hand, isEmpty);
    });

    test('Convergent Mutation raises a friendly unit’s Might to another friendly unit’s', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 3);
      final small = g.addCard('Daring Poro', 0, zone: Zone.board); // 2
      g.addCard('Vanguard Sergeant', 0, zone: Zone.board); // 4
      g.apply(PlayMove(0, g.addCard('Convergent Mutation', 0)));
      answer(g, [small]);
      expect(g.pending, isNull, reason: 'the only other friendly unit is chosen without asking');
      passAll(g);
      expect(g.might(small), 4);
      nextOwnTurn(g);
      expect(g.might(small), 2, reason: 'this turn only');
    });

    test('Crescent Strike: 4 to the chosen enemy unit, 1 to each other enemy unit there', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 4);
      final x = g.addCard('Zephyr Sage', 1, zone: Zone.board, loc: 0); // 6
      final y = g.addCard('Zephyr Sage', 1, zone: Zone.board, loc: 0);
      final z = g.addCard('Zephyr Sage', 1, zone: Zone.board, loc: 1);
      g.addCard('Zephyr Sage', 1, zone: Zone.board); // at base: not a choice
      g.apply(PlayMove(0, g.addCard('Crescent Strike', 0)));
      expect(g.pending!.decision.options, unorderedEquals([x, y, z]));
      answer(g, [x]);
      passAll(g);
      expect(g.state.obj(x).damage, 4);
      expect(g.state.obj(y).damage, 1);
      expect(g.state.obj(z).damage, 0);
    });

    test('712 Dancing Grenade: its target’s controller may play it again for {A}, with 1 Bonus Damage per earlier hit', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 3);
      g.addRunes(1, Domain.fury, 1);
      final mine = g.addCard('Vanguard Sergeant', 0, zone: Zone.board); // 4
      final theirs = g.addCard('Zephyr Sage', 1, zone: Zone.board); // 6
      final grenade = g.addCard('Dancing Grenade', 0);
      g.apply(PlayMove(0, grenade));
      answer(g, [theirs]);
      passAll(g);
      expect(g.state.obj(theirs).damage, 2);
      expect(g.pending?.decision.player, 1, reason: 'the damaged unit’s controller may play it again');
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
      answer(g, [1]);
      if (g.pending?.decision.kind == DecisionKind.cards) answer(g, [mine]);
      passAll(g);
      expect(g.state.obj(mine).damage, 3, reason: '2 + 1 Bonus Damage (it had dealt damage once)');
      expect(g.state.player(0).trash, contains(grenade), reason: 'its owner’s trash');
    });

    test('Deathgrip kills a friendly unit to give another its Might this turn, then draws', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 2);
      g.stackDeck(0, 'Daring Poro', 1);
      final victim = g.addCard('Vanguard Sergeant', 0, zone: Zone.board); // 4
      final other = g.addCard('Daring Poro', 0, zone: Zone.board); // 2
      g.apply(PlayMove(0, g.addCard('Deathgrip', 0)));
      answer(g, [victim]);
      passAll(g);
      expect(g.state.obj(victim).zone, Zone.trash);
      expect(g.might(other), 6);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Decree of Focus needs a friendly unit facing Fury: in combat with an enemy Fury unit', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 1);
      final decree = g.addCard('Decree of Focus', 0);
      final att = g.addCard('Vanguard Sergeant', 0, zone: Zone.board); // 4
      expect(g.whyNot(PlayMove(0, decree)), isNotNull, reason: 'nothing faces Fury');
      g.setControl(0, 1);
      final draven = g.addCard('Draven, Vanquisher', 1, zone: Zone.board, loc: 0); // Fury, 4
      g.apply(MoveUnitsMove(0, [att], 0));
      expect(g.state.showdown?.combat, isTrue);
      expect(g.toAct, 0);
      g.apply(PlayMove(0, decree));
      passAll(g);
      settle(g);
      expect(g.state.obj(draven).zone, Zone.trash);
      expect(g.state.obj(att).zone, Zone.board, reason: '8 Might against 4');
    });

    test('Divine Judgment: each player keeps 2 units, gear, runes and hand cards and recycles the rest', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 9);
      final us = [for (var i = 0; i < 3; i++) g.addCard('Daring Poro', 0, zone: Zone.board)];
      final them = [for (var i = 0; i < 3; i++) g.addCard('Stalwart Poro', 1, zone: Zone.board)];
      g.addRunes(1, Domain.calm, 3);
      for (var i = 0; i < 3; i++) {
        g.addCard('Daring Poro', 1);
      }
      g.apply(PlayMove(0, g.addCard('Divine Judgment', 0)));
      settle(g);
      expect([for (final u in us) if (g.state.obj(u).zone == Zone.board) u], hasLength(2));
      expect([for (final u in them) if (g.state.obj(u).zone == Zone.board) u], hasLength(2));
      expect(g.state.player(1).runes, hasLength(2));
      expect(g.state.player(1).hand, hasLength(2));
      expect(g.state.player(0).runes.length, lessThanOrEqualTo(2));
      expect(g.state.player(1).deck, hasLength(2), reason: 'a unit and a card recycled');
    });

    test('Dominus doubles a unit’s Might and gives it “{A}{A}: Ready me.” this turn', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 6);
      final u = g.addCard('Vanguard Sergeant', 0, zone: Zone.board, exhausted: true);
      g.apply(PlayMove(0, g.addCard('Dominus', 0)));
      passAll(g);
      expect(g.might(u), 8);
      final ready = isA<ActivateMove>().having((m) => m.source, 'source', u).having((m) => m.index, 'index', 1000);
      expect(g.legalMoves(0), contains(ready));
      g.apply(ActivateMove(0, u, 1000));
      passAll(g);
      expect(g.state.obj(u).exhausted, isFalse);
      nextOwnTurn(g);
      expect(g.might(u), 4);
      expect(g.legalMoves(0), isNot(contains(ready)), reason: 'this turn only');
    });

    test('Fading Memories gives a unit at a battlefield [Temporary]: it dies at its controller’s next turn (CR 816)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 5);
      final there = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
      final home = g.addCard('Daring Poro', 1, zone: Zone.board);
      g.addCard('Daring Poro', 0, zone: Zone.board, loc: 1);
      g.apply(PlayMove(0, g.addCard('Fading Memories', 0)));
      expect(g.pending!.decision.options, contains(there));
      expect(g.pending!.decision.options, isNot(contains(home)), reason: 'units in a base aren’t choices');
      answer(g, [there]);
      passAll(g);
      g.stackDeck(1, 'Stalwart Poro', 2);
      g.apply(const EndTurnMove(0));
      settle(g);
      expect(g.state.obj(there).zone, Zone.trash);
      expect(g.state.obj(home).zone, Zone.board);
    });
  });
}
