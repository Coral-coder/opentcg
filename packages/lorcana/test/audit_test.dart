import 'package:lorcana/lorcana.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Says yes to every pending question and picks the first option of every other.
void yesToAll(Game g) {
  while (g.pending != null) {
    final d = g.pending!.decision;
    answer(g, d.kind == DecisionKind.yesNo ? [1] : [d.options.isEmpty ? 0 : d.options.first]);
  }
}

/// Regression tests from auditing supported cards against their text: each plays the real card
/// and checks the effect does what the card says.
void main() {
  group('Counting and filters', () {
    test('Bolt - Superdog counts only other undamaged characters (CR 6.2, 4.3)', () {
      final g = emptyGame();
      g.addCard('Bolt - Superdog', 0, Place.play, exerted: true);
      g.addCard(vanilla, 0, Place.play);
      g.addCard(vanilla, 0, Place.play, damage: 1);
      g.apply(const EndTurnMove(0));
      g.apply(const EndTurnMove(1));
      expect(g.state.player(0).lore, 1, reason: 'the damaged one doesn\'t count');
    });

    test('Huey - Savvy Nephew needs your own Dewey and Louie', () {
      final g = emptyGame();
      final huey = g.addCard('Huey - Savvy Nephew', 0, Place.play);
      g.addCard('Dewey - Showy Nephew', 1, Place.play);
      g.addCard('Louie - One Cool Duck', 1, Place.play);
      g.apply(QuestMove(0, huey));
      yesToAll(g);
      expect(g.state.player(0).hand, isEmpty, reason: 'the opponent\'s nephews are not "you have"');
      final g2 = emptyGame();
      final huey2 = g2.addCard('Huey - Savvy Nephew', 0, Place.play);
      g2.addCard('Dewey - Showy Nephew', 0, Place.play);
      g2.addCard('Louie - One Cool Duck', 0, Place.play);
      g2.apply(QuestMove(0, huey2));
      yesToAll(g2);
      expect(g2.state.player(0).hand, hasLength(3));
    });
  });

  group('"You may" (CR 6.1.5.1)', () {
    test('Dr. Facilier - Remarkable Gentleman: looking at the top 2 cards is optional', () {
      final g = emptyGame();
      g.addInk(0, 7);
      g.addCard('Dr. Facilier - Remarkable Gentleman', 0, Place.play);
      final top = g.state.player(0).deck.first;
      g.apply(PlayMove(0, g.addCard("Don't Let the Frostbite Bite", 0, Place.hand)));
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
      answer(g, [0], player: 0);
      expect(g.state.player(0).deck.first, top, reason: 'declined: the deck is untouched');
    });
  });

  group('Pronouns after a group mean that group (CR 6.1.3)', () {
    test('Don\'t Let the Frostbite Bite: "ready all your characters. They can\'t quest"', () {
      final g = emptyGame();
      g.addInk(0, 7);
      final a = g.addCard(vanilla, 0, Place.play, exerted: true);
      final b = g.addCard(vanilla2, 0, Place.play, exerted: true);
      g.apply(PlayMove(0, g.addCard("Don't Let the Frostbite Bite", 0, Place.hand)));
      expect(g.state.obj(a).exerted, isFalse);
      expect(illegal(g, QuestMove(0, a)), isTrue);
      expect(illegal(g, QuestMove(0, b)), isTrue);
    });

    test('We\'ve Got Company!: your readied characters gain Reckless', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final a = g.addCard(vanilla, 0, Place.play, exerted: true);
      g.apply(PlayMove(0, g.addCard("We've Got Company!", 0, Place.hand)));
      expect(g.chars(a).has(Kw.reckless), isTrue);
    });

    test('Moana - Of Motunui: the readied Princesses can\'t quest, Moana still could have', () {
      final g = emptyGame();
      final moana = g.addCard('Moana - Of Motunui', 0, Place.play);
      final p = g.addCard('Aurora - Regal Princess', 0, Place.play, exerted: true);
      g.apply(QuestMove(0, moana));
      answer(g, [1], player: 0);
      expect(g.state.obj(p).exerted, isFalse);
      expect(illegal(g, QuestMove(0, p)), isTrue);
    });

    test('Sleepy Hollow - The Bridge gives the questing character Evasive, not the location', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final loc = g.addCard('Sleepy Hollow - The Bridge', 0, Place.play);
      final c = g.addCard(vanilla, 0, Place.play);
      g.apply(MoveMove(0, c, loc));
      g.apply(QuestMove(0, c));
      answer(g, [1], player: 0);
      expect(g.state.obj(loc).zone, Place.discard);
      expect(g.state.player(0).lore, 4, reason: '2 from questing, 2 from the bridge');
      expect(g.chars(c).has(Kw.evasive), isTrue);
    });

    test('Medallion Weights: "whenever they challenge" means the chosen character (CR 6.2.7.1)', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final w = g.addCard('Medallion Weights', 0, Place.play);
      final c = g.addCard(vanilla, 0, Place.play);
      final target = g.addCard(vanilla2, 1, Place.play, exerted: true);
      g.apply(ActivateMove(0, w, 0));
      if (g.pending?.decision.kind == DecisionKind.cards) answer(g, [c], player: 0);
      final hand = g.state.player(0).hand.length;
      g.apply(ChallengeMove(0, c, target));
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
      answer(g, [1], player: 0);
      expect(g.state.player(0).hand.length, hand + 1);
    });

    test('Candy Drift banishes the chosen character at the end of the turn', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final c = g.addCard(vanilla, 0, Place.play);
      g.apply(PlayMove(0, g.addCard('Candy Drift', 0, Place.hand)));
      if (g.pending?.decision.kind == DecisionKind.cards) answer(g, [c], player: 0);
      expect(g.chars(c).strength, 8);
      g.apply(const EndTurnMove(0));
      yesToAll(g);
      expect(g.state.obj(c).zone, Place.discard);
    });
  });

  group('"That location" (CR 5.6)', () {
    test('Peter Pan - Lost Boy Leader gains the location\'s lore', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final pp = g.addCard('Peter Pan - Lost Boy Leader', 0, Place.play);
      final loc = g.addCard("McDuck Manor - Scrooge's Mansion", 0, Place.play); // 2 lore
      g.apply(MoveMove(0, pp, loc));
      expect(g.state.player(0).lore, 2);
    });

    test('I\'ve Got A Dream gains the location\'s lore, not the character\'s', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final loc = g.addCard("McDuck Manor - Scrooge's Mansion", 0, Place.play); // 2 lore
      final c = g.addCard(vanilla2, 0, Place.play); // 1 lore
      g.apply(MoveMove(0, c, loc));
      g.state.obj(c).exerted = true;
      g.apply(PlayMove(0, g.addCard("I've Got A Dream", 0, Place.hand)));
      if (g.pending?.decision.kind == DecisionKind.cards) answer(g, [c], player: 0);
      expect(g.state.obj(c).exerted, isFalse);
      expect(g.state.player(0).lore, 2);
    });

    test('The Game\'s Afoot!: the location gains Resist +2', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final loc = g.addCard("McDuck Manor - Scrooge's Mansion", 0, Place.play);
      final c = g.addCard(vanilla, 0, Place.play);
      g.apply(PlayMove(0, g.addCard("The Game's Afoot!", 0, Place.hand)));
      while (g.pending != null) {
        final d = g.pending!.decision;
        answer(g, d.kind == DecisionKind.cards ? (d.options.contains(c) ? [c] : [loc]) : [d.options.isEmpty ? 0 : d.options.first]);
      }
      expect(g.state.obj(c).at, loc);
      expect(g.chars(loc).n(Kw.resist), 2);
      expect(g.chars(c).n(Kw.resist), 0);
    });
  });

  group('Instead (CR 6.5)', () {
    test('Darkwing\'s Gas Device: -2 with Darkwing Duck, -1 without', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final dev = g.addCard("Darkwing's Gas Device", 0, Place.play);
      final t = g.addCard(vanilla, 1, Place.play);
      g.apply(ActivateMove(0, dev, 0));
      if (g.pending?.decision.kind == DecisionKind.cards) answer(g, [t], player: 0);
      expect(g.chars(t).strength, 2);
      final g2 = emptyGame();
      g2.addInk(0, 1);
      g2.addCard('Darkwing Duck - Crime Fighter', 0, Place.play);
      final dev2 = g2.addCard("Darkwing's Gas Device", 0, Place.play);
      final t2 = g2.addCard(vanilla, 1, Place.play);
      g2.apply(ActivateMove(0, dev2, 0));
      if (g2.pending?.decision.kind == DecisionKind.cards) answer(g2, [t2], player: 0);
      expect(g2.chars(t2).strength, 1, reason: 'the card is chosen even when the replacement applies');
    });

    test('Demona - Scourge of the Wyvern Clan: each player draws up to 3 cards', () {
      final g = emptyGame();
      g.addInk(0, 6);
      for (var i = 0; i < 2; i++) {
        g.addCard(vanilla2, 1, Place.hand);
      }
      g.apply(PlayMove(0, g.addCard('Demona - Scourge of the Wyvern Clan', 0, Place.hand)));
      expect(g.state.player(0).hand.length, 3);
      expect(g.state.player(1).hand.length, 3);
    });

    test('Amethyst Chromicon: each player may draw (CR 6.1.5.1)', () {
      final g = emptyGame();
      final chrom = g.addCard('Amethyst Chromicon', 0, Place.play);
      g.apply(ActivateMove(0, chrom, 0));
      yesToAll(g);
      expect(g.state.player(0).hand.length, 1);
      expect(g.state.player(1).hand.length, 1);
    });
  });

  group('Other cards checked', () {
    test('Coldstone counts Gargoyles in your discard only', () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.addCard('Goliath - Guardian of Castle Wyvern', 1, Place.discard);
      g.addCard('Goliath - Guardian of Castle Wyvern', 1, Place.discard);
      g.apply(PlayMove(0, g.addCard('Coldstone - Reincarnated Cyborg', 0, Place.hand)));
      expect(g.state.player(0).lore, 0);
      final g2 = emptyGame();
      g2.addInk(0, 5);
      g2.addCard('Goliath - Guardian of Castle Wyvern', 0, Place.discard);
      g2.addCard('Goliath - Guardian of Castle Wyvern', 0, Place.discard);
      g2.apply(PlayMove(0, g2.addCard('Coldstone - Reincarnated Cyborg', 0, Place.hand)));
      expect(g2.state.player(0).lore, 2);
    });

    test('Cheshire Cat - Not All There banishes the challenger, not itself again (CR 4.6)', () {
      final g = emptyGame(active: 1);
      final cat = g.addCard('Cheshire Cat - Not All There', 0, Place.play, exerted: true);
      final brom = g.addCard('Brom Bones - Burly Bully', 1, Place.play);
      g.apply(ChallengeMove(1, brom, cat));
      yesToAll(g);
      expect(g.state.obj(cat).zone, Place.discard);
      expect(g.state.obj(brom).zone, Place.discard);
    });

    test('Kuzco\'s Palace banishes the character that challenged one here', () {
      final g = emptyGame(active: 1);
      final palace = g.addCard("Kuzco's Palace - Home of the Emperor", 0, Place.play);
      final mine = g.addCard(vanilla2, 0, Place.play, exerted: true);
      g.state.obj(mine).at = palace;
      final brom = g.addCard('Brom Bones - Burly Bully', 1, Place.play);
      g.apply(ChallengeMove(1, brom, mine));
      yesToAll(g);
      expect(g.state.obj(mine).zone, Place.discard);
      expect(g.state.obj(brom).zone, Place.discard);
    });

    test('Potion of Might: +4 for a Villain instead of +3', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final potion = g.addCard('Potion of Might', 0, Place.play);
      final villain = g.addCard('Demona - Scourge of the Wyvern Clan', 0, Place.play); // 5 strength
      g.apply(ActivateMove(0, potion, 0));
      if (g.pending?.decision.kind == DecisionKind.cards) answer(g, [villain], player: 0);
      expect(g.chars(villain).strength, 9);
    });

    test('Bullseye - Loyal Horse: "named Woody or Jessie" takes either', () {
      final g = emptyGame();
      g.addInk(0, 2);
      g.addCard('Jessie - Lively Cowgirl', 0, Place.play);
      final b = g.addCard('Bullseye - Loyal Horse', 0, Place.hand);
      g.apply(PlayMove(0, b));
      expect(g.state.obj(b).zone, Place.play, reason: 'costs 2 instead of 3');
    });

    test('Wrong Lever!: put Pull the Lever! on the bottom to put chosen character on the bottom', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final lever = g.addCard('Pull the Lever!', 0, Place.discard);
      final t = g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Wrong Lever!', 0, Place.hand)));
      answer(g, [1], player: 0); // the second mode
      while (g.pending != null) {
        final d = g.pending!.decision;
        answer(g, d.kind == DecisionKind.yesNo ? [1] : [d.options.contains(t) ? t : d.options.first]);
      }
      expect(g.state.player(0).deck.last, lever);
      expect(g.state.player(1).deck.last, t);
    });

    test('Ambush! needs a ready character of yours to exert (CR 6.1.10)', () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.addCard(vanilla, 0, Place.play, exerted: true);
      final t = g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Ambush!', 0, Place.hand)));
      yesToAll(g);
      expect(g.state.obj(t).damage, 0);
    });

    test('The Terror That Flaps in the Night: 3 damage instead with Darkwing Duck (CR 6.5)', () {
      final g = emptyGame();
      g.addInk(0, 2);
      g.addCard('Darkwing Duck - Crime Fighter', 0, Place.play);
      final t = g.addCard('Mulan - Armored Fighter', 1, Place.play); // 6 willpower
      g.apply(PlayMove(0, g.addCard('The Terror That Flaps in the Night', 0, Place.hand)));
      if (g.pending?.decision.kind == DecisionKind.cards) answer(g, [t], player: 0);
      expect(g.state.obj(t).damage, 3);
    });
  });
}
