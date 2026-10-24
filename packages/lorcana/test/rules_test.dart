import 'package:lorcana/lorcana.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Setup (CR 2.2)', () {
    test('2.2.1.4 each player draws 7; 2.2.2 hands are altered in turn order', () {
      final g = Game(db, players: ['A', 'B'], seed: 3);
      g.apply(StartMove([deckOf(vanilla), deckOf(vanilla2)], firstPlayer: 1));
      expect(g.state.firstPlayer, 1);
      expect(g.pending!.decision.player, 1, reason: 'the starting player alters first');
      final put = g.pending!.decision.options.take(2).toList();
      answer(g, put, player: 1);
      expect(g.pending!.decision.player, 0);
      answer(g, [], player: 0);
      expect(g.state.player(1).hand.length, 7, reason: 'drew back up to 7');
      expect(g.state.player(1).altered, isTrue);
      expect(g.state.player(0).altered, isFalse);
      expect(g.state.player(1).deck.length, 53);
    });

    test('3.2.3.1 the starting player skips their first draw; the other player draws', () {
      final g = Game(db, players: ['A', 'B'], seed: 3);
      g.apply(StartMove([deckOf(vanilla), deckOf(vanilla2)], firstPlayer: 0));
      answer(g, []);
      answer(g, []);
      expect(g.state.turn, 1);
      expect(g.state.player(0).hand.length, 7);
      g.apply(const EndTurnMove(0));
      expect(g.state.active, 1);
      expect(g.state.player(1).hand.length, 8);
    });

    test('the first player comes from the seeded generator when not given', () {
      int first(int seed) {
        final g = Game(db, players: ['A', 'B'], seed: seed);
        g.apply(StartMove([deckOf(vanilla), deckOf(vanilla2)]));
        return g.state.firstPlayer;
      }

      expect(first(11), first(11));
      expect({for (var s = 1; s < 20; s++) first(s)}, {0, 1});
    });
  });

  group('Ink a card (CR 4.2)', () {
    test('4.2.3 once per turn', () {
      final g = emptyGame();
      final a = g.addCard(vanilla, 0, Place.hand);
      final b = g.addCard(vanilla, 0, Place.hand);
      g.apply(InkMove(0, a));
      expect(g.state.player(0).inkwell, [a]);
      expect(g.state.obj(a).exerted, isFalse, reason: '4.2.1.3 enters ready');
      expect(illegal(g, InkMove(0, b)), isTrue);
    });

    test('4.2.1.1 only cards with the inkwell symbol', () {
      final g = emptyGame();
      final name = db.cards.firstWhere((c) => !c.inkable && c.type == CardType.character).fullName;
      final id = g.addCard(name, 0, Place.hand);
      expect(illegal(g, InkMove(0, id)), isTrue);
    });
  });

  group('Play a card (CR 4.3)', () {
    test('4.3.2.4 the cost is paid by exerting ready ink', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final id = g.addCard(vanilla2, 0, Place.hand);
      g.apply(PlayMove(0, id));
      expect(g.state.obj(id).zone, Place.play);
      expect(g.inkReady(0), 1);
      expect(g.state.obj(id).dry, isFalse, reason: 'a character played this turn is drying');
    });

    test('not enough ink', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final id = g.addCard(vanilla, 0, Place.hand);
      expect(illegal(g, PlayMove(0, id)), isTrue);
      expect(g.whyNot(PlayMove(0, id)), isNotNull);
    });

    test('4.3.3.2 an action resolves and goes to the discard', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final id = g.addCard('Finders Keepers', 0, Place.hand);
      g.apply(PlayMove(0, id));
      expect(g.state.obj(id).zone, Place.discard);
      expect(g.state.player(0).hand.length, 3);
    });

    test('only the active player acts', () {
      final g = emptyGame();
      g.addInk(1, 3);
      final id = g.addCard(vanilla2, 1, Place.hand);
      expect(illegal(g, PlayMove(1, id)), isTrue);
    });
  });

  group('Quest (CR 4.5)', () {
    test('4.5.1.3-4 exert and gain lore', () {
      final g = emptyGame();
      final id = g.addCard(vanilla, 0, Place.play);
      g.apply(QuestMove(0, id));
      expect(g.state.obj(id).exerted, isTrue);
      expect(g.state.player(0).lore, 2);
      expect(illegal(g, QuestMove(0, id)), isTrue, reason: 'exerted characters can\'t quest');
    });

    test('1.7.5 / 3.2.2.1 a drying character can\'t quest', () {
      final g = emptyGame();
      final id = g.addCard(vanilla, 0, Place.play, drying: true);
      expect(illegal(g, QuestMove(0, id)), isTrue);
      g.apply(const EndTurnMove(0));
      g.apply(const EndTurnMove(1));
      g.apply(QuestMove(0, id));
      expect(g.state.player(0).lore, 2);
    });

    test('1.8.1.1 a player with 20 lore wins', () {
      final g = emptyGame();
      final id = g.addCard(vanilla, 0, Place.play);
      g.state.player(0).lore = 18;
      g.apply(QuestMove(0, id));
      expect(g.over, isTrue);
      expect(g.state.winner, 0);
    });
  });

  group('Challenge (CR 4.6)', () {
    test('4.6.4.2 only exerted characters can be challenged', () {
      final g = emptyGame();
      final a = g.addCard(vanilla, 0, Place.play);
      final d = g.addCard(vanilla2, 1, Place.play);
      expect(illegal(g, ChallengeMove(0, a, d)), isTrue);
    });

    test('4.6.6.2 damage is dealt simultaneously; 1.8.1.4 banished at willpower', () {
      final g = emptyGame();
      final a = g.addCard(vanilla, 0, Place.play); // 3/2
      final d = g.addCard(vanilla2, 1, Place.play, exerted: true); // 2/3
      g.apply(ChallengeMove(0, a, d));
      expect(g.state.obj(a).zone, Place.discard, reason: '2 damage on willpower 2');
      expect(g.state.obj(d).zone, Place.discard, reason: '3 damage on willpower 3');
    });

    test('damage stays on a surviving character', () {
      final g = emptyGame();
      final a = g.addCard(vanilla2, 0, Place.play); // 2/3
      final d = g.addCard(vanilla2, 1, Place.play, exerted: true);
      g.apply(ChallengeMove(0, a, d));
      expect(g.state.obj(a).damage, 2);
      expect(g.state.obj(d).damage, 2);
      expect(g.state.obj(a).exerted, isTrue, reason: '4.6.4.4');
    });

    test('4.6.4.1 a drying character can\'t challenge', () {
      final g = emptyGame();
      final a = g.addCard(vanilla, 0, Place.play, drying: true);
      final d = g.addCard(vanilla2, 1, Place.play, exerted: true);
      expect(illegal(g, ChallengeMove(0, a, d)), isTrue);
    });

    test('4.6.8 locations can be challenged at any time and deal no damage', () {
      final g = emptyGame();
      final a = g.addCard(vanilla, 0, Place.play);
      final loc = g.addCard('De Vil Manor - Cruella\'s Estate', 1, Place.play); // willpower 4
      g.apply(ChallengeMove(0, a, loc));
      expect(g.state.obj(loc).damage, 3);
      expect(g.state.obj(a).damage, 0);
    });
  });

  group('Move a character (CR 4.7) and locations (CR 5.6)', () {
    test('4.7.3.4 pay the move cost; 3.2.2.2 locations give lore at the start of your turn', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final c = g.addCard(vanilla, 0, Place.play);
      final loc = g.addCard('McDuck Manor - Scrooge\'s Mansion', 0, Place.play); // move 1, lore 2
      g.apply(MoveMove(0, c, loc));
      expect(g.state.obj(c).at, loc);
      expect(g.inkReady(0), 0);
      g.apply(const EndTurnMove(0));
      g.apply(const EndTurnMove(1));
      expect(g.state.player(0).lore, 2);
    });

    test('4.7.1 characters can\'t move to opposing locations', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final c = g.addCard(vanilla, 0, Place.play);
      final loc = g.addCard('McDuck Manor - Scrooge\'s Mansion', 1, Place.play);
      expect(illegal(g, MoveMove(0, c, loc)), isTrue);
    });

    test('a character leaving play leaves its location', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final c = g.addCard(vanilla, 0, Place.play);
      final loc = g.addCard('McDuck Manor - Scrooge\'s Mansion', 0, Place.play);
      g.apply(MoveMove(0, c, loc));
      g.moveToForTest(c, Place.discard);
      expect(g.state.obj(c).at, isNull);
    });
  });

  group('Items (CR 5.5)', () {
    test('5.5.4 an item\'s ability can be used the turn it is played', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final c = g.addCard(vanilla2, 0, Place.play, damage: 2);
      final item = g.addCard('Amber Chromicon', 0, Place.hand);
      g.apply(PlayMove(0, item));
      g.apply(ActivateMove(0, item, 0));
      expect(g.state.obj(c).damage, 1);
      expect(g.state.obj(item).exerted, isTrue);
      expect(illegal(g, ActivateMove(0, item, 0)), isTrue, reason: 'already exerted');
    });
  });

  group('Songs (CR 5.4.4)', () {
    test('5.4.4.2 a character with cost N or more can exert to sing for free', () {
      final g = emptyGame();
      final singer = g.addCard('Abu - Bold Helmsman', 0, Place.play); // cost 5
      final song = g.addCard('He Hurled His Thunderbolt', 0, Place.hand); // cost 4
      final t = g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, song, mode: PlayMode.sing, singers: [singer]));
      answer(g, [t]);
      expect(g.state.obj(singer).exerted, isTrue);
      expect(g.state.obj(t).zone, Place.discard);
      expect(g.state.obj(song).zone, Place.discard);
    });

    test('a character with too low a cost can\'t sing', () {
      final g = emptyGame();
      final singer = g.addCard(vanilla, 0, Place.play); // cost 3
      final song = g.addCard('He Hurled His Thunderbolt', 0, Place.hand);
      expect(illegal(g, PlayMove(0, song, mode: PlayMode.sing, singers: [singer])), isTrue);
    });

    test('1.7.5 a drying character can\'t sing', () {
      final g = emptyGame();
      final singer = g.addCard('Abu - Bold Helmsman', 0, Place.play, drying: true);
      final song = g.addCard('He Hurled His Thunderbolt', 0, Place.hand);
      g.addCard(vanilla, 1, Place.play);
      expect(g.whyNot(PlayMove(0, song, mode: PlayMode.sing, singers: [singer])), isNotNull);
    });
  });

  group('The bag (CR 7.7)', () {
    test('7.7.4.2 the active player chooses which of their triggers resolves first', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final puppies = g.addCard('99 Puppies', 0, Place.hand);
      g.apply(PlayMove(0, puppies));
      final j = g.addCard('Jasmine - Rebellious Princess', 0, Place.play);
      g.state.player(1).lore = 3;
      g.apply(QuestMove(0, j));
      final d = g.pending!.decision;
      expect(d.kind, DecisionKind.option);
      expect(d.player, 0);
      expect(d.labels.length, 2);
      answer(g, [0]);
      expect(g.pending, isNull);
      expect(g.state.player(0).lore, 2 + 1);
      expect(g.state.player(1).lore, 2);
    });

    test('6.2.7.1 a floating trigger ends with the turn', () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.apply(PlayMove(0, g.addCard('99 Puppies', 0, Place.hand)));
      g.apply(const EndTurnMove(0));
      g.apply(const EndTurnMove(1));
      final c = g.addCard(vanilla, 0, Place.play);
      g.apply(QuestMove(0, c));
      expect(g.state.player(0).lore, 2);
    });

    test('a triggered ability on play resolves', () {
      final g = emptyGame();
      g.addInk(0, 3);
      g.state.player(1).lore = 4;
      g.apply(PlayMove(0, g.addCard('Kakamora - Menacing Sailor', 0, Place.hand)));
      expect(g.state.player(1).lore, 3);
    });
  });

  group('Game end (CR 1.8, 2.3.3)', () {
    test('1.8.1.2 a player whose turn ends with an empty deck loses', () {
      final g = emptyGame(deck: 0);
      g.apply(const EndTurnMove(0));
      expect(g.over, isTrue);
      expect(g.state.winner, 1);
    });

    test('conceding ends the game, even with a decision pending', () {
      final g = Game(db, players: ['A', 'B'], seed: 3);
      g.apply(StartMove([deckOf(vanilla), deckOf(vanilla2)], firstPlayer: 0));
      expect(g.pending, isNotNull);
      g.apply(const ConcedeMove(0));
      expect(g.over, isTrue);
      expect(g.state.winner, 1);
    });

    test('no moves after the game is over', () {
      final g = emptyGame(deck: 0);
      g.apply(const EndTurnMove(0));
      expect(g.legalMoves(), isEmpty);
      expect(illegal(g, const EndTurnMove(1)), isTrue);
    });
  });
}
