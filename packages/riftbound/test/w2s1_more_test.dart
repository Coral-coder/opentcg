import 'package:riftbound/riftbound.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Wave 2, slice 1: units, gear, battlefields and legends from Acceleration Gate to Fiora.

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

/// Ends player 0's turn and player 1's, back to player 0's Main Phase (default answers).
void nextOwnTurn(Game g) {
  g.apply(const EndTurnMove(0));
  settle(g);
  g.apply(const EndTurnMove(1));
  settle(g);
}

int golds(Game g, int p) => [for (final o in g.state.objects.values) if (o.zone == Zone.board && g.nameOf(o.id) == 'Gold' && o.controller == p) o].length;

void main() {
  group('Units', () {
    test('Affectionate Poro draws when a combat it was in ends, if it wasn’t dealt damage this turn', () {
      final g = emptyGame();
      g.stackDeck(0, 'Daring Poro', 2);
      g.setControl(0, 1);
      final def = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0); // 2, stunned: deals nothing
      g.state.obj(def).stunned = true;
      final poro = g.addCard('Affectionate Poro', 0, zone: Zone.board); // 3
      g.apply(MoveUnitsMove(0, [poro], 0));
      settle(g);
      expect(g.state.obj(def).zone, Zone.trash);
      expect(g.state.player(0).hand, hasLength(1));
      // Dealt damage: no draw.
      final g2 = emptyGame();
      g2.stackDeck(0, 'Daring Poro', 2);
      g2.setControl(0, 1);
      g2.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
      final poro2 = g2.addCard('Affectionate Poro', 0, zone: Zone.board);
      g2.apply(MoveUnitsMove(0, [poro2], 0));
      settle(g2);
      expect(g2.state.player(0).hand, isEmpty);
    });

    test('Ashe, Focused banishes a card from the opponent’s revealed hand until they hold', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 6);
      final a = g.addCard('Daring Poro', 1);
      final b = g.addCard('Stalwart Poro', 1);
      g.apply(PlayMove(0, g.addCard('Ashe, Focused', 0)));
      passAll(g);
      expect(g.pending?.decision.options, unorderedEquals([a, b]));
      answer(g, [b]);
      settle(g);
      expect(g.state.obj(b).zone, Zone.banish);
      // They hold a battlefield at the start of their turn: it comes back.
      g.setControl(1, 1);
      g.addCard('Daring Poro', 1, zone: Zone.board, loc: 1);
      g.stackDeck(1, 'Daring Poro', 2);
      g.apply(const EndTurnMove(0));
      settle(g);
      expect(g.state.obj(b).zone, Zone.hand);
      expect(g.state.player(1).hand, contains(b));
    });

    test('Baron Nashor adds the Baron Pit and enters there; units can move to the Pit from anywhere', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 13);
      final walker = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 1);
      final baron = g.addCard('Baron Nashor', 0);
      g.apply(PlayMove(0, baron));
      settle(g);
      expect(g.state.bfs, hasLength(3));
      expect(g.nameOf(g.state.bfs[2].obj), 'Baron Pit');
      expect(g.state.obj(baron).loc, 2);
      expect(g.moveDestinations(walker), contains(2), reason: 'from a battlefield, without Ganking');
      expect(g.might(walker), 4, reason: 'Other friendly units have +2 {M}');
    });

    test('Black Market Broker plays an exhausted Gold when a card is played from face down', () {
      final g = emptyGame();
      g.stackDeck(0, 'Daring Poro', 4);
      g.stackDeck(1, 'Daring Poro', 4);
      g.setControl(0, 0);
      g.addCard('Vanguard Sergeant', 0, zone: Zone.board, loc: 0);
      g.addCard('Black Market Broker', 0, zone: Zone.board);
      g.addRunes(0, Domain.body, 1);
      final cub = g.addCard('Pakaa Cub', 0);
      g.apply(HideMove(0, cub));
      nextOwnTurn(g);
      g.apply(PlayMove(0, cub));
      settle(g);
      final gold = [for (final o in g.state.objects.values) if (o.zone == Zone.board && g.nameOf(o.id) == 'Gold' && o.controller == 0) o];
      expect(gold, hasLength(1));
      expect(gold.first.exhausted, isTrue);
    });

    test('Card Sharp: both may play a Gold; for each opponent who did, one more for you', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 3);
      g.apply(PlayMove(0, g.addCard('Card Sharp', 0)));
      passAll(g);
      expect(g.pending?.decision.player, 0);
      answer(g, [1]);
      expect(g.pending?.decision.player, 1);
      answer(g, [1]);
      settle(g);
      expect(golds(g, 0), 2);
      expect(golds(g, 1), 1);
    });

    test('Diana, Lunari: when a showdown begins here, pay {1} to Predict, then draw the top card if it’s a spell', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 1);
      g.stackDeck(0, 'Daring Poro', 1);
      g.stackDeck(0, 'Blood Rush', 1); // on top
      final diana = g.addCard('Diana, Lunari', 0, zone: Zone.board);
      g.apply(MoveUnitsMove(0, [diana], 0)); // an empty, uncontrolled battlefield: a showdown
      passAll(g);
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
      answer(g, [1]);
      expect(g.pending?.decision.prompt, contains('Predict'));
      answer(g, []); // keep it on top
      settle(g);
      expect([for (final id in g.state.player(0).hand) g.nameOf(id)], ['Blood Rush']);
    });

    test('Draven, Audacious scores the first time he wins a combat each turn; an opponent scores when he dies in combat', () {
      final g = emptyGame();
      g.setControl(0, 1);
      g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
      final draven = g.addCard('Draven, Audacious', 0, zone: Zone.board); // 6
      g.apply(MoveUnitsMove(0, [draven], 0));
      settle(g);
      expect(g.state.player(0).points, 2, reason: '1 for the conquer, 1 for Draven');
      final g2 = emptyGame();
      g2.setControl(0, 1);
      g2.addCard('Zephyr Sage', 1, zone: Zone.board, loc: 0);
      g2.addCard('Zephyr Sage', 1, zone: Zone.board, loc: 0);
      final d2 = g2.addCard('Draven, Audacious', 0, zone: Zone.board);
      g2.apply(MoveUnitsMove(0, [d2], 0));
      settle(g2);
      expect(g2.state.obj(d2).zone, Zone.trash);
      expect(g2.state.player(1).points, 1);
    });

    test('Draven, Vanquisher may pay {R} as he attacks for +2 {M}', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 1);
      g.setControl(0, 1);
      g.addCard('Zephyr Sage', 1, zone: Zone.board, loc: 0); // 6
      final draven = g.addCard('Draven, Vanquisher', 0, zone: Zone.board); // 4
      g.apply(MoveUnitsMove(0, [draven], 0));
      passAll(g);
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
      answer(g, [1]);
      settle(g);
      expect(g.state.log.map((l) => l.text), contains('Zephyr Sage takes 6 combat damage.'));
      expect(g.state.player(0).runes, isEmpty, reason: '{R} paid');
    });

    test('Ekko, Recurrent: Deathknell — recycle him from the trash to ready your runes', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 2);
      g.addRunes(0, Domain.mind, 3);
      for (final r in g.state.player(0).runes.skip(2)) {
        g.state.obj(r).exhausted = true;
      }
      g.stackDeck(0, 'Daring Poro', 2);
      final ekko = g.addCard('Ekko, Recurrent', 0, zone: Zone.board);
      g.addCard('Daring Poro', 0, zone: Zone.board);
      g.apply(PlayMove(0, g.addCard('Deathgrip', 0)));
      answer(g, [ekko]);
      settle(g);
      expect(g.state.obj(ekko).zone, Zone.mainDeck, reason: 'recycled');
      expect(g.state.player(0).runes.every((r) => !g.state.obj(r).exhausted), isTrue);
    });

    test('Elder Dragon deals 1 to up to one enemy unit at each location — and any of its damage kills', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 16);
      final atBase = g.addCard('Zephyr Sage', 1, zone: Zone.board);
      final atBf = g.addCard('Zephyr Sage', 1, zone: Zone.board, loc: 1);
      g.apply(PlayMove(0, g.addCard('Elder Dragon', 0)));
      passAll(g);
      expect(g.pending?.decision.min, 0, reason: 'up to one');
      answer(g, [atBase]);
      answer(g, [atBf]);
      settle(g);
      expect(g.state.obj(atBase).zone, Zone.trash);
      expect(g.state.obj(atBf).zone, Zone.trash);
    });

    test('762 Fallen Feline names a spell; while it’s at a battlefield opponents can’t play spells with that name', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 3);
      final feline = g.addCard('Fallen Feline', 0);
      g.apply(PlayMove(0, feline));
      passAll(g);
      final d = g.pending!.decision;
      answer(g, [d.labels.indexOf('Blood Rush')]);
      settle(g);
      g.addRunes(1, Domain.fury, 1);
      final rush = g.addCard('Blood Rush', 1);
      g.addCard('Daring Poro', 1, zone: Zone.board);
      g.stackDeck(1, 'Daring Poro', 2);
      g.apply(const EndTurnMove(0));
      settle(g);
      expect(g.whyNot(PlayMove(1, rush)), isNot(contains('Blood Rush')), reason: 'Fallen Feline is in its base');
      // At a battlefield it stops the named spell.
      g.state.obj(feline).loc = 0;
      expect(g.whyNot(PlayMove(1, rush)), contains('Blood Rush'));
    });

    test('740.2.b Fiora, Peerless doubles her Might in a one-on-one combat, for that combat only', () {
      final g = emptyGame();
      g.setControl(0, 1);
      final def = g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 0); // 4
      final fiora = g.addCard('Fiora, Peerless', 0, zone: Zone.board); // 3
      g.apply(MoveUnitsMove(0, [fiora], 0));
      settle(g);
      expect(g.state.obj(def).zone, Zone.trash, reason: '6 Might against 4');
      expect(g.state.obj(fiora).zone, Zone.board);
      expect(g.might(fiora), 3, reason: 'the doubling ends with the combat');
      // Not one on one: no doubling.
      final g2 = emptyGame();
      g2.setControl(0, 1);
      g2.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 0);
      g2.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
      final f2 = g2.addCard('Fiora, Peerless', 0, zone: Zone.board);
      g2.apply(MoveUnitsMove(0, [f2], 0));
      settle(g2);
      expect(g2.state.log.map((l) => l.text), isNot(contains('Fiora, Peerless’s Might is doubled this combat.')));
      expect(g2.state.obj(f2).zone, Zone.trash);
    });
  });

  group('Gear, battlefields and legends', () {
    test('Altar of Blood: a unit there about to die in combat may be healed, exhausted and recalled for {A}{A}{A}', () {
      final g = emptyGame(battlefields: const ['Altar of Blood', 'Zaun Warrens']);
      g.setControl(0, 1);
      g.addRunes(1, Domain.calm, 3);
      final def = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0); // 2
      final att = g.addCard('Vanguard Sergeant', 0, zone: Zone.board); // 4
      g.apply(MoveUnitsMove(0, [att], 0));
      passAll(g);
      expect(g.pending?.decision.player, 1);
      answer(g, [1]);
      settle(g);
      expect(g.state.obj(def).zone, Zone.board);
      expect(g.state.obj(def).loc, base);
      expect(g.state.obj(def).exhausted, isTrue);
      expect(g.state.obj(def).damage, 0);
      expect(g.state.player(1).runes, isEmpty, reason: 'three runes recycled for {A}{A}{A}');
    });

    test('Altar of Memories: when a friendly unit dies, exhaust it to draw, then put a card on top or bottom', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 2);
      g.stackDeck(0, 'Stalwart Poro', 1);
      g.stackDeck(0, 'Daring Poro', 2);
      final altar = g.addCard('Altar of Memories', 0, zone: Zone.board);
      final victim = g.addCard('Vanguard Sergeant', 0, zone: Zone.board);
      g.addCard('Daring Poro', 0, zone: Zone.board);
      final keep = g.addCard('Blood Rush', 0);
      g.apply(PlayMove(0, g.addCard('Deathgrip', 0)));
      answer(g, [victim]);
      passAll(g);
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
      answer(g, [1]);
      expect(g.pending?.decision.kind, DecisionKind.cards);
      answer(g, [keep]);
      expect(g.pending?.decision.labels, ['Top', 'Bottom']);
      answer(g, [1]);
      settle(g);
      expect(g.state.obj(altar).exhausted, isTrue);
      expect(g.state.player(0).deck.last, keep);
    });

    test('337.2 Ancient Henge turns any amount of Energy into that much Power of any domain, at once', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 3);
      final henge = g.addCard('Ancient Henge', 0, zone: Zone.board);
      g.apply(ActivateMove(0, henge, 0));
      expect(g.pending?.decision.labels, ['0', '1', '2', '3']);
      answer(g, [2]);
      expect(g.state.player(0).anyPool, 2);
      expect([for (final r in g.state.player(0).runes) if (g.state.obj(r).exhausted) r], hasLength(2));
      expect(g.state.chain, isEmpty);
    });

    test('Bandle Tree holds a second facedown card', () {
      final g = emptyGame(battlefields: const ['Bandle Tree', 'Zaun Warrens']);
      g.setControl(0, 0);
      g.addCard('Vanguard Sergeant', 0, zone: Zone.board, loc: 0);
      g.addRunes(0, Domain.body, 3);
      final a = g.addCard('Pakaa Cub', 0);
      final b = g.addCard('Pakaa Cub', 0);
      final c = g.addCard('Pakaa Cub', 0);
      g.apply(HideMove(0, a));
      g.apply(HideMove(0, b));
      expect(g.state.obj(a).zone, Zone.facedown);
      expect(g.state.obj(b).zone, Zone.facedown);
      expect(g.state.obj(b).loc, 0);
      expect(g.whyNot(HideMove(0, c)), isNotNull, reason: 'only one additional card');
    });

    test('Bottled Constellation: at the start of your Main Phase, kill 3 other friendly units and/or gear to score 1', () {
      final g = emptyGame();
      g.stackDeck(0, 'Daring Poro', 3);
      g.stackDeck(1, 'Daring Poro', 3);
      g.addCard('Bottled Constellation', 0, zone: Zone.board);
      final fodder = [g.addCard('Daring Poro', 0, zone: Zone.board), g.addCard('Daring Poro', 0, zone: Zone.board), g.addCard('Altar of Memories', 0, zone: Zone.board)];
      g.apply(const EndTurnMove(0));
      settle(g);
      g.apply(const EndTurnMove(1));
      passAll(g);
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
      answer(g, [1]);
      settle(g);
      expect(fodder.every((id) => g.state.obj(id).zone == Zone.trash), isTrue);
      expect(g.state.player(0).points, 1);
    });

    test('Dazzling Aurora: at the end of your turn, reveal until a unit, play it free, recycle the rest', () {
      final g = emptyGame();
      g.stackDeck(0, 'Daring Poro', 1);
      g.stackDeck(0, 'Zephyr Sage', 1);
      g.stackDeck(0, 'Blood Rush', 2); // two spells on top
      g.stackDeck(1, 'Daring Poro', 3);
      g.addCard('Dazzling Aurora', 0, zone: Zone.board);
      g.apply(const EndTurnMove(0));
      settle(g);
      final sage = g.state.objects.values.where((o) => g.nameOf(o.id) == 'Zephyr Sage').first;
      expect(sage.zone, Zone.board);
      expect(sage.controller, 0);
      final deck = [for (final id in g.state.player(0).deck) g.nameOf(id)];
      expect(deck.first, 'Daring Poro');
      expect(deck.where((n) => n == 'Blood Rush'), hasLength(2), reason: 'recycled to the bottom');
    });

    test('Diana, Scorn of the Moon adds Energy only during showdowns', () {
      final g = emptyGame();
      final diana = g.addCard('Diana, Scorn of the Moon', 0, zone: Zone.legend);
      expect(g.whyNot(ActivateMove(0, diana, 0)), contains('showdown'));
    });

    test('Dusk Rose Lab: at the start of your Beginning Phase, kill a unit you control there to draw 1', () {
      final g = emptyGame(battlefields: const ['Dusk Rose Lab', 'Zaun Warrens']);
      g.stackDeck(0, 'Daring Poro', 3);
      g.stackDeck(1, 'Daring Poro', 3);
      g.setControl(0, 0);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 0);
      g.apply(const EndTurnMove(0));
      settle(g);
      g.apply(const EndTurnMove(1));
      passAll(g);
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
      answer(g, [1]);
      settle(g);
      expect(g.state.obj(u).zone, Zone.trash);
      expect(g.state.player(0).hand, hasLength(2), reason: 'the Draw Phase and the Lab');
    });

    test('Emperor’s Dais: when you conquer it, pay {1} and return a unit there to play a Sand Soldier there', () {
      final g = emptyGame(battlefields: const ["Emperor's Dais", 'Zaun Warrens']);
      g.addRunes(0, Domain.order, 1);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      g.apply(MoveUnitsMove(0, [u], 0));
      settle(g);
      expect(g.state.bfs[0].controller, 0);
      expect(g.state.obj(u).zone, Zone.hand);
      final soldier = g.state.objects.values.where((o) => o.zone == Zone.board && g.nameOf(o.id) == 'Sand Soldier');
      expect(soldier, hasLength(1));
      expect(soldier.first.loc, 0);
    });

    test('Endless Riches: banish hand and trash, Burn 7; skip your draw; play from your trash; what would go to your trash is banished', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 7);
      g.stackDeck(0, 'Blood Rush', 3);
      g.stackDeck(0, 'Daring Poro', 6);
      g.stackDeck(1, 'Daring Poro', 4);
      final old = g.addCard('Daring Poro', 0, zone: Zone.trash);
      final inHand = g.addCard('Stalwart Poro', 0);
      g.apply(PlayMove(0, g.addCard('Endless Riches', 0)));
      settle(g);
      final pl = g.state.player(0);
      expect(pl.banish, containsAll([old, inHand]));
      expect(pl.trash, hasLength(7), reason: 'Burn 7 from the Main Deck stays in the trash');
      // A spell played from the trash is banished as it finishes.
      final rush = pl.trash.firstWhere((id) => g.nameOf(id) == 'Blood Rush');
      g.addCard('Daring Poro', 0, zone: Zone.board);
      expect(g.legalMoves(0).whereType<PlayMove>().map((m) => m.card), contains(rush));
      g.apply(PlayMove(0, rush));
      settle(g);
      expect(g.state.obj(rush).zone, Zone.banish);
      // The Draw Phase is skipped.
      final hand = pl.hand.length;
      nextOwnTurn(g);
      expect(g.state.player(0).hand.length, hand);
    });

    test('Ezreal, Prodigal Explorer draws once you’ve chosen enemy units twice this turn with spells', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 2);
      g.stackDeck(0, 'Daring Poro', 2);
      final ez = g.addCard('Ezreal, Prodigal Explorer', 0, zone: Zone.legend);
      final e1 = g.addCard('Zephyr Sage', 1, zone: Zone.board);
      expect(g.whyNot(ActivateMove(0, ez, 0)), isNotNull);
      for (var i = 0; i < 2; i++) {
        g.apply(PlayMove(0, g.addCard('Blood Rush', 0)));
        if (g.pending?.decision.kind == DecisionKind.yesNo) answer(g, [0]);
        if (g.pending != null) answer(g, [e1]);
        passAll(g);
      }
      expect(g.whyNot(ActivateMove(0, ez, 0)), isNull);
      g.apply(ActivateMove(0, ez, 0));
      passAll(g);
      expect(g.state.player(0).hand, hasLength(1));
    });
  });
}
