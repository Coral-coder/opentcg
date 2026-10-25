import 'package:lorcana/lorcana.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const song = 'Friend Like Me'; // a song card
const item = 'Amethyst Chromicon'; // an item card

/// Puts [names] on top of [p]'s deck, the first one on top.
List<CardId> stack(Game g, int p, List<String> names) => [for (final n in names.reversed) g.addCard(n, p, Place.deck)].reversed.toList();

/// Answers a "Name a card" decision with the name part of [name] (not its version).
void name(Game g, String name) {
  final d = g.pending!.decision;
  expect(d.kind, DecisionKind.option);
  final base = name.split(' - ').first;
  expect(d.labels, contains(base));
  answer(g, [d.labels.indexOf(base)]);
}

void main() {
  group('Look at the top of the deck (CR 7.2, 7.1.4)', () {
    test('Develop Your Brain: put one into your hand and the other on the bottom', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final top = stack(g, 0, [vanilla, item]);
      g.apply(PlayMove(0, g.addCard('Develop Your Brain', 0, Place.hand)));
      final d = g.pending!.decision;
      expect(d.kind, DecisionKind.cards);
      expect(d.options, top);
      expect((d.min, d.max), (1, 1), reason: 'not optional');
      answer(g, [top[1]]);
      expect(g.state.player(0).hand, [top[1]]);
      expect(g.state.player(0).deck.last, top[0]);
    });

    test('Be Our Guest: 7.1.4 may fail to find; the rest go to the bottom in an order you pick', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final top = stack(g, 0, [item, vanilla, item, song]);
      g.apply(PlayMove(0, g.addCard('Be Our Guest', 0, Place.hand)));
      final d = g.pending!.decision;
      expect(d.options, [top[1]], reason: 'only the character card can be taken');
      expect(d.min, 0);
      answer(g, []);
      expect(g.pending!.decision.kind, DecisionKind.order);
      answer(g, [top[3], top[2], top[1], top[0]]);
      final deck = g.state.player(0).deck;
      expect(deck.sublist(deck.length - 4), [top[3], top[2], top[1], top[0]]);
      expect(g.state.player(0).hand, isEmpty);
    });

    test('Water Has Memory: chosen player\'s deck, one on top and the rest on the bottom', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final top = stack(g, 1, [vanilla, vanilla, item, song]);
      g.apply(PlayMove(0, g.addCard('Water Has Memory', 0, Place.hand)));
      expect(g.pending!.decision.kind, DecisionKind.option, reason: 'choose a player');
      answer(g, [1]);
      answer(g, [top[2]], player: 0);
      answer(g, [top[0], top[1], top[3]], player: 0);
      final deck = g.state.player(1).deck;
      expect(deck.first, top[2]);
      expect(deck.sublist(deck.length - 3), [top[0], top[1], top[3]]);
    });

    test('Aurelian Gyrosensor: put it on either the top or the bottom', () {
      final g = emptyGame();
      g.addCard('Aurelian Gyrosensor', 0, Place.play);
      final c = g.addCard(vanilla, 0, Place.play);
      final top = stack(g, 0, [item]).first;
      g.apply(QuestMove(0, c));
      final d = g.pending!.decision;
      expect(d.labels, ['Top', 'Bottom']);
      answer(g, [1]);
      expect(g.state.player(0).deck.last, top);
    });

    test('Mad Hatter: put it on top of their deck or into their discard', () {
      final g = emptyGame();
      final c = g.addCard('Mad Hatter - Eccentric Host', 0, Place.play);
      final top = stack(g, 1, [item]).first;
      g.apply(QuestMove(0, c));
      answer(g, [1]); // chosen player: the opponent
      expect(g.pending!.decision.labels, ['Top', 'Discard']);
      answer(g, [1]);
      expect(g.state.player(1).discard, [top]);
    });
  });

  group('Reveal the top card (CR 6.1.14)', () {
    test('Monterey Jack: if it\'s a character card you may put it into your hand', () {
      final g = emptyGame();
      g.addInk(0, 10);
      final top = stack(g, 0, [vanilla]).first;
      g.apply(PlayMove(0, g.addCard('Monterey Jack - Watchful Ranger', 0, Place.hand)));
      answer(g, [1]); // you may reveal
      answer(g, [top]);
      expect(g.state.player(0).hand, [top]);
      expect(g.state.log.any((l) => l.text.contains('reveals')), isTrue);
    });

    test('Monterey Jack: otherwise, put it on the bottom of your deck', () {
      final g = emptyGame();
      g.addInk(0, 10);
      final top = stack(g, 0, [item]).first;
      g.apply(PlayMove(0, g.addCard('Monterey Jack - Watchful Ranger', 0, Place.hand)));
      answer(g, [1]);
      expect(g.pending, isNull, reason: 'nothing to take');
      expect(g.state.player(0).deck.last, top);
      expect(g.state.player(0).hand, isEmpty);
    });

    test('Bruno Madrigal: name a card, then reveal; the named card goes to hand and gains 3 lore', () {
      final g = emptyGame();
      final bruno = g.addCard('Bruno Madrigal - Undetected Uncle', 0, Place.play);
      final top = stack(g, 0, [vanilla]).first;
      g.apply(ActivateMove(0, bruno, 1));
      name(g, vanilla);
      expect(g.state.player(0).hand, [top]);
      expect(g.state.player(0).lore, 3);
    });

    test('Bruno Madrigal: a wrong name leaves the card on the top', () {
      final g = emptyGame();
      final bruno = g.addCard('Bruno Madrigal - Undetected Uncle', 0, Place.play);
      final top = stack(g, 0, [vanilla]).first;
      g.apply(ActivateMove(0, bruno, 1));
      name(g, vanilla2);
      expect(g.state.player(0).deck.first, top);
      expect(g.state.player(0).lore, 0);
    });
  });

  group('Naming and the discard (CR 7.6)', () {
    test('Blast From Your Past returns all character cards with the name', () {
      final g = emptyGame();
      g.addInk(0, 6);
      final a = g.addCard(vanilla, 0, Place.discard);
      final b = g.addCard(vanilla, 0, Place.discard);
      final other = g.addCard(vanilla2, 0, Place.discard);
      g.apply(PlayMove(0, g.addCard('Blast From Your Past', 0, Place.hand)));
      name(g, vanilla);
      expect(g.state.player(0).hand, unorderedEquals([a, b]));
      expect(g.state.player(0).discard, contains(other));
    });

    test('Chernabog shuffles the character cards from the discard into the deck', () {
      final g = emptyGame();
      g.addInk(0, 10);
      final a = g.addCard(vanilla, 0, Place.discard);
      final i = g.addCard(item, 0, Place.discard);
      g.apply(PlayMove(0, g.addCard('Chernabog - Evildoer', 0, Place.hand)));
      expect(g.state.obj(a).zone, Place.deck);
      expect(g.state.obj(i).zone, Place.discard);
    });

    test('All Is Found: up to 2 cards from the discard into the inkwell exerted (7.5.6)', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final a = g.addCard(vanilla, 0, Place.discard);
      final b = g.addCard(item, 0, Place.discard);
      g.addCard(vanilla2, 0, Place.discard);
      g.apply(PlayMove(0, g.addCard('All Is Found', 0, Place.hand)));
      final d = g.pending!.decision;
      expect((d.min, d.max), (0, 2));
      answer(g, [a, b]);
      expect(g.state.obj(a).zone, Place.inkwell);
      expect(g.state.obj(b).exerted, isTrue);
      expect(g.state.player(0).inkwell.length, 7);
    });

    test('Gazelle: you may put a song card from your discard on the top of your deck', () {
      final g = emptyGame();
      g.addInk(0, 10);
      final s = g.addCard(song, 0, Place.discard);
      g.addCard(vanilla, 0, Place.discard);
      g.apply(PlayMove(0, g.addCard('Gazelle - Ballad Singer', 0, Place.hand)));
      answer(g, [1]);
      if (g.pending != null) answer(g, [s]);
      expect(g.state.player(0).deck.first, s);
    });
  });

  group('Hands (CR 7.3)', () {
    test('The Bare Necessities: the opponent reveals their hand and you choose a non-character card', () {
      final g = emptyGame();
      g.addInk(0, 2);
      g.addCard(vanilla, 1, Place.hand);
      final i = g.addCard(item, 1, Place.hand);
      final s = g.addCard(song, 1, Place.hand);
      g.apply(PlayMove(0, g.addCard('The Bare Necessities', 0, Place.hand)));
      final d = g.pending!.decision;
      expect(d.player, 0, reason: 'of your choice');
      expect(d.options, unorderedEquals([i, s]));
      answer(g, [i]);
      expect(g.state.player(1).discard, [i]);
    });

    test('Anastasia: the challenging player chooses and discards a card', () {
      final g = emptyGame(active: 1);
      final a = g.addCard('Anastasia - Bossy Stepsister', 0, Place.play, exerted: true);
      final att = g.addCard(vanilla, 1, Place.play);
      final h1 = g.addCard(vanilla, 1, Place.hand);
      g.addCard(vanilla2, 1, Place.hand);
      g.apply(ChallengeMove(1, att, a));
      answer(g, [h1], player: 1);
      expect(g.state.player(1).discard, contains(h1));
    });

    test('A Whole New World: each player discards their hand and draws 7', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final h = g.addCard(vanilla, 1, Place.hand);
      g.apply(PlayMove(0, g.addCard('A Whole New World', 0, Place.hand)));
      expect(g.state.player(1).discard, [h]);
      expect(g.state.player(0).hand.length, 7);
      expect(g.state.player(1).hand.length, 7);
    });

    test('Dangerous Plan: draw 2, then discard a card at random (seeded)', () {
      final g = emptyGame();
      g.addInk(0, 1);
      g.apply(PlayMove(0, g.addCard('Dangerous Plan', 0, Place.hand)));
      expect(g.pending, isNull, reason: 'random, not chosen');
      expect(g.state.player(0).hand.length, 1);
      expect(g.state.player(0).discard.length, 2, reason: 'the action and the random card');
    });

    test('Remember Who You Are: 6.1.8.1 draw until you have the same number', () {
      final g = emptyGame();
      g.addInk(0, 4);
      for (var i = 0; i < 5; i++) {
        g.addCard(vanilla, 1, Place.hand);
      }
      g.addCard(vanilla, 0, Place.hand);
      g.apply(PlayMove(0, g.addCard('Remember Who You Are', 0, Place.hand)));
      expect(g.state.player(0).hand.length, 5);
    });
  });

  group('Each player decides (CR 6.1.4)', () {
    test('Amethyst Chromicon: each player may draw a card', () {
      final g = emptyGame();
      final c = g.addCard(item, 0, Place.play);
      g.apply(ActivateMove(0, c, 0));
      answer(g, [1], player: 0);
      answer(g, [0], player: 1);
      expect(g.state.player(0).hand.length, 1);
      expect(g.state.player(1).hand, isEmpty);
    });

    test('Sign the Scroll: you gain 2 lore for each opponent who doesn\'t discard', () {
      final g = emptyGame();
      g.addInk(0, 3);
      g.addCard(vanilla, 1, Place.hand);
      g.apply(PlayMove(0, g.addCard('Sign the Scroll', 0, Place.hand)));
      answer(g, [0], player: 1);
      expect(g.state.player(0).lore, 2);
    });

    test('Sign the Scroll: an opponent who discards gives no lore', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final h = g.addCard(vanilla, 1, Place.hand);
      g.apply(PlayMove(0, g.addCard('Sign the Scroll', 0, Place.hand)));
      answer(g, [1], player: 1);
      if (g.pending != null) answer(g, [h], player: 1);
      expect(g.state.player(1).discard, [h]);
      expect(g.state.player(0).lore, 0);
    });
  });

  group('Inkwells (CR 7.5)', () {
    test('Friend Like Me: each player puts the top 3 cards of their deck into their inkwell exerted', () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.apply(PlayMove(0, g.addCard(song, 0, Place.hand)));
      expect(g.state.player(0).inkwell.length, 8);
      expect(g.state.player(1).inkwell.length, 3);
      expect(g.state.player(1).inkwell.every((id) => g.state.obj(id).exerted), isTrue);
    });

    test('Belle & Beast: whenever this character quests, ready all cards in your inkwell', () {
      final g = emptyGame();
      g.addInk(0, 3);
      for (final id in g.state.player(0).inkwell) {
        g.state.obj(id).exerted = true;
      }
      final b = g.addCard('Belle & Beast - Certain as the Sun', 0, Place.play);
      g.apply(QuestMove(0, b));
      expect(g.inkReady(0), 3);
    });

    test('HeiHei: only if an opponent has more cards in their inkwell', () {
      for (final more in [true, false]) {
        final g = emptyGame();
        g.addInk(0, 3);
        g.addInk(1, more ? 4 : 2);
        g.apply(PlayMove(0, g.addCard('HeiHei - Bumbling Rooster', 0, Place.hand)));
        if (more) answer(g, [1]);
        expect(g.state.player(0).inkwell.length, more ? 4 : 3);
      }
    });
  });

  group('Cards under others (Boost, CR 8.4)', () {
    test('Emily Quackfaster puts the top card under a character with Boost; Alice takes them into hand', () {
      final g = emptyGame();
      g.addInk(0, 10);
      final alice = g.addCard('Alice - Well-Read Whisper', 0, Place.play);
      final top = stack(g, 0, [vanilla]).first;
      g.apply(PlayMove(0, g.addCard('Emily Quackfaster - Level-Headed Librarian', 0, Place.hand)));
      answer(g, [1]);
      if (g.pending != null) answer(g, [alice]);
      expect(g.state.obj(top).zone, isNot(Place.deck));
      g.apply(QuestMove(0, alice));
      expect(g.state.player(0).hand, contains(top));
    });
  });

  group('Paying ink in an effect (CR 6.1.5.1)', () {
    test('Aladdin: pay 1 ink to banish chosen item', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final i = g.addCard(item, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Aladdin - Doing His Part', 0, Place.hand)));
      answer(g, [1]);
      if (g.pending != null) answer(g, [i]);
      expect(g.state.obj(i).zone, Place.discard);
      expect(g.inkReady(0), 0);
    });

    test('Aladdin: without the ink, nothing happens (6.1.4.1)', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final i = g.addCard(item, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Aladdin - Doing His Part', 0, Place.hand)));
      if (g.pending != null) answer(g, [1]);
      expect(g.pending, isNull);
      expect(g.state.obj(i).zone, Place.play);
    });

    test('Anna: you may pay 2 ink to choose one', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final h = g.addCard(vanilla, 1, Place.hand);
      g.apply(PlayMove(0, g.addCard('Anna - Diplomatic Queen', 0, Place.hand)));
      answer(g, [1]);
      expect(g.pending!.decision.kind, DecisionKind.option);
      answer(g, [0]); // each opponent chooses and discards a card
      if (g.pending != null) answer(g, [h], player: 1);
      expect(g.state.player(1).discard, [h]);
      expect(g.inkReady(0), 0);
    });
  });

  test('every new effect is described', () {
    for (final n in ['Develop Your Brain', 'Sign the Scroll', 'Blast From Your Past', 'Mad Hatter - Eccentric Host', 'Alice - Well-Read Whisper']) {
      final p = LorcanaParser.parse(db[n]!);
      expect(p.supported, isTrue, reason: n);
      expect(p.abilities.map(describeAbility).join(), isNot(contains('?')), reason: n);
    }
  });
}
