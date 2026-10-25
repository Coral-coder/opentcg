import 'package:lorcana/lorcana.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Effects about characters, items, locations and lore: who chooses, what was done this turn,
/// "instead", moving, and grants that outlast the turn.
void main() {
  group('1.4.3 the opponent makes their own choice', () {
    test("Triton's Decree: each opponent picks one of their characters and deals it 2 damage", () {
      final g = emptyGame();
      g.addInk(0, 1);
      final a = g.addCard(vanilla, 1, Place.play);
      final b = g.addCard(vanilla2, 1, Place.play);
      g.apply(PlayMove(0, g.addCard("Triton's Decree", 0, Place.hand)));
      expect(g.pending!.decision.player, 1);
      answer(g, [b], player: 1);
      expect(g.state.obj(b).damage, 2);
      expect(g.state.obj(a).damage, 0);
    });

    test('Be King Undisputed: each opponent chooses and banishes one of their characters', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final a = g.addCard(vanilla, 1, Place.play);
      final b = g.addCard(vanilla2, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Be King Undisputed', 0, Place.hand)));
      answer(g, [a], player: 1);
      expect(g.state.obj(a).zone, Place.discard);
      expect(g.state.obj(b).zone, Place.play);
    });

    test("Chernabog: the exerted pick can't ready at the start of its next turn (1.4.3.2)", () {
      final g = emptyGame();
      g.addInk(0, 5);
      final a = g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Chernabog - Creature of the Night', 0, Place.hand)));
      expect(g.state.obj(a).exerted, isTrue, reason: 'their only ready character is picked');
      g.apply(EndTurnMove(0));
      expect(g.state.active, 1);
      expect(g.state.obj(a).exerted, isTrue);
    });
  });

  group('1.11 lore', () {
    test('Lady Tremaine: only opponents with more lore than you lose it', () {
      final g = emptyGame();
      g.addInk(0, 2);
      g.state.player(0).lore = 3;
      g.state.player(1).lore = 5;
      g.apply(PlayMove(0, g.addCard('Lady Tremaine - Overbearing Matriarch', 0, Place.hand)));
      expect(g.state.player(1).lore, 4);
      g.state.player(1).lore = 2;
      g.addInk(0, 2);
      g.apply(PlayMove(0, g.addCard('Lady Tremaine - Overbearing Matriarch', 0, Place.hand)));
      expect(g.state.player(1).lore, 2);
    });

    test("Most Everyone's Mad Here: gain lore equal to the damage on chosen character (1.9.1)", () {
      final g = emptyGame();
      g.addInk(0, 7);
      final d = g.addCard(vanilla2, 1, Place.play, damage: 2);
      g.apply(PlayMove(0, g.addCard("Most Everyone's Mad Here", 0, Place.hand)));
      if (g.pending != null) answer(g, [d]);
      expect(g.state.player(0).lore, 2);
      expect(g.state.obj(d).zone, Place.discard);
    });
  });

  group('6.1.15 conditions on what happened this turn', () {
    test('Card Advantage draws only after an opposing character was banished in a challenge', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final hand = g.state.player(0).hand.length;
      g.apply(PlayMove(0, g.addCard('Card Advantage', 0, Place.hand)));
      expect(g.state.player(0).hand.length, hand);
      final a = g.addCard(vanilla, 0, Place.play); // 3/2
      final d = g.addCard(vanilla2, 1, Place.play, exerted: true, damage: 1); // 2/3
      g.apply(ChallengeMove(0, a, d));
      expect(g.state.obj(d).zone, Place.discard);
      g.apply(PlayMove(0, g.addCard('Card Advantage', 0, Place.hand)));
      expect(g.state.player(0).hand.length, hand + 2);
    });

    test('Clarabelle: may draw only if an opponent has more cards in hand', () {
      final g = emptyGame();
      g.addInk(0, 6);
      final before = g.state.player(0).hand.length;
      g.apply(PlayMove(0, g.addCard('Clarabelle - Contented Wallflower', 0, Place.hand)));
      expect(g.pending, isNull, reason: 'equal hands: no draw offered');
      expect(g.state.player(0).hand.length, before);
      g.addCard(vanilla, 1, Place.hand);
      g.apply(PlayMove(0, g.addCard('Clarabelle - Contented Wallflower', 0, Place.hand)));
      answer(g, [1]);
      expect(g.state.player(0).hand.length, before + 1);
    });
  });

  group('6.5.1.1 "instead"', () {
    test('Potion of Might: a Villain gets +4 instead of +3', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final potion = g.addCard('Potion of Might', 0, Place.play);
      final villain = g.addCard('Lady Tremaine - Overbearing Matriarch', 0, Place.play);
      final hero = g.addCard(vanilla, 0, Place.play);
      final base = g.chars(villain).strength;
      g.apply(ActivateMove(0, potion, 0));
      answer(g, [villain]);
      expect(g.chars(villain).strength, base + 4);
      expect(g.chars(hero).strength, 3);
    });

    test('Potion of Might: anyone else gets +3', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final potion = g.addCard('Potion of Might', 0, Place.play);
      final hero = g.addCard(vanilla, 0, Place.play);
      g.apply(ActivateMove(0, potion, 0));
      if (g.pending != null) answer(g, [hero]);
      expect(g.chars(hero).strength, 6);
    });
  });

  group('4.6.4.2 challenging ready characters', () {
    test('Arthur: the chosen character can challenge a ready character this turn', () {
      final g = emptyGame();
      g.addInk(0, 7);
      final a = g.addCard(vanilla, 0, Place.play);
      final d = g.addCard(vanilla2, 1, Place.play);
      expect(g.whyNot(ChallengeMove(0, a, d)), isNotNull);
      g.apply(PlayMove(0, g.addCard('Arthur - King Victorius', 0, Place.hand)));
      answer(g, [a]);
      expect(g.chars(a).has(Kw.resist), isTrue);
      expect(g.whyNot(ChallengeMove(0, a, d)), isNull);
      g.apply(ChallengeMove(0, a, d));
      expect(g.state.obj(d).zone, Place.discard, reason: '3 + Challenger 2 against 3 willpower');
    });
  });

  test("6.1.13 Cobra Bubbles: can't challenge and must quest during their next turn if able", () {
    final g = emptyGame();
    final cobra = g.addCard('Cobra Bubbles - Dedicated Official', 0, Place.play);
    final d = g.addCard(vanilla2, 1, Place.play);
    final mine = g.addCard(vanilla, 0, Place.play, exerted: true);
    g.apply(QuestMove(0, cobra));
    if (g.pending != null) answer(g, [d]);
    g.apply(EndTurnMove(0));
    expect(g.state.active, 1);
    expect(g.whyNot(ChallengeMove(1, d, mine)), isNotNull);
    expect(g.whyNot(EndTurnMove(1)), isNotNull, reason: 'it can quest, so it must');
    g.apply(QuestMove(1, d));
    expect(g.whyNot(EndTurnMove(1)), isNull);
  });

  test('4.7 Goofy: when he moves to a location, another character of yours may follow for free', () {
    final g = emptyGame();
    g.addInk(0, 5);
    final goofy = g.addCard('Goofy - Set for Adventure', 0, Place.play);
    final a = g.addCard(vanilla, 0, Place.play);
    final loc = g.addCard("Leviathan's Lair - Dangerous Ground", 0, Place.play);
    g.apply(MoveMove(0, goofy, loc));
    final ink = g.state.player(0).inkwell.where((id) => !g.state.obj(id).exerted).length;
    final hand = g.state.player(0).hand.length;
    answer(g, [1]);
    if (g.pending != null) answer(g, [a]);
    expect(g.state.obj(a).at, loc);
    expect(g.state.player(0).inkwell.where((id) => !g.state.obj(id).exerted).length, ink, reason: 'for free');
    expect(g.state.player(0).hand.length, hand + 1, reason: 'if you do, draw a card');
  });

  group('5.3.6.1 same name', () {
    test('Sabotage banishes the chosen item and every other item with its name', () {
      final g = emptyGame();
      g.addInk(0, 6);
      final p1 = g.addCard('Potion of Might', 1, Place.play);
      final p2 = g.addCard('Potion of Might', 1, Place.play);
      final other = g.addCard("Baymax's Charging Station", 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Sabotage', 0, Place.hand)));
      answer(g, [p1]);
      expect(g.state.obj(p1).zone, Place.discard);
      expect(g.state.obj(p2).zone, Place.discard);
      expect(g.state.obj(other).zone, Place.play);
    });
  });

  group('6.1.5 "or" and pronouns', () {
    test('Break Free: they gain Rush and +1 strength this turn (1.4.3.2)', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final a = g.addCard(vanilla2, 0, Place.play, drying: true);
      g.apply(PlayMove(0, g.addCard('Break Free', 0, Place.hand)));
      if (g.pending != null) answer(g, [a]);
      expect(g.state.obj(a).damage, 1);
      expect(g.chars(a).has(Kw.rush), isTrue);
      expect(g.chars(a).strength, 3);
      g.apply(EndTurnMove(0));
      expect(g.chars(a).has(Kw.rush), isFalse);
    });


    test('Madam Mim: banish her or return another chosen character of yours', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final a = g.addCard(vanilla, 0, Place.play);
      final mim = g.addCard('Madam Mim - Snake', 0, Place.hand);
      g.apply(PlayMove(0, mim));
      expect(g.pending!.decision.kind, DecisionKind.option);
      answer(g, [1]);
      if (g.pending != null) answer(g, [a]);
      expect(g.state.obj(a).zone, Place.hand);
      expect(g.state.obj(mim).zone, Place.play);
      final mim2 = g.addCard('Madam Mim - Snake', 0, Place.hand);
      g.apply(PlayMove(0, mim2));
      answer(g, [0]);
      expect(g.state.obj(mim2).zone, Place.discard);
    });

    test('6.1.3 Ever as Before: remove up to 2 damage from any number of chosen characters', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final a = g.addCard(vanilla2, 0, Place.play, damage: 2);
      final b = g.addCard(vanilla2, 1, Place.play, damage: 1);
      final c = g.addCard(vanilla2, 0, Place.play, damage: 2);
      g.apply(PlayMove(0, g.addCard('Ever as Before', 0, Place.hand)));
      answer(g, [a, b]);
      while (g.pending != null) {
        answer(g, [g.pending!.decision.options.last]);
      }
      expect(g.state.obj(a).damage, 0);
      expect(g.state.obj(b).damage, 0);
      expect(g.state.obj(c).damage, 2);
    });

    test('Baymax: if you used Shift to play him, remove all damage from him', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final base = g.addCard(vanilla2, 0, Place.play, damage: 2);
      final baymax = g.addCard('Baymax - Giant Robot', 0, Place.hand);
      g.apply(PlayMove(0, baymax, mode: PlayMode.shift, onto: base));
      while (g.pending != null) {
        answer(g, [1]);
      }
      expect(g.state.obj(baymax).damage, 0);
    });

    test('6.2.7.2 Candy Drift banishes the chosen character at the end of your turn', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final a = g.addCard(vanilla2, 0, Place.play);
      g.apply(PlayMove(0, g.addCard('Candy Drift', 0, Place.hand)));
      if (g.pending != null) answer(g, [a]);
      expect(g.chars(a).strength, 7);
      g.apply(EndTurnMove(0));
      expect(g.state.obj(a).zone, Place.discard);
    });
  });
}
