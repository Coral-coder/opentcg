import 'package:lorcana/lorcana.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The trigger of [name]'s first triggered ability, as printed by describeAbility.
String trig(String name) => describeAbility(LorcanaParser.parse(db[name]!).abilities.whereType<Triggered>().first);

void main() {
  group('Parsing trigger conditions (CR 6.2.1)', () {
    test('inkwell, damage removed, cards under, shifting, discarding', () {
      expect(trig('Steel Coil'), startsWith('TRIG inked(any by yours) during your turn →'));
      expect(trig('Chicha - Dedicated Mother'), startsWith('TRIG inked(any by yours #2) during your turn →'));
      expect(trig('Alma Madrigal - Keeper of the Flame'), startsWith('TRIG damageRemoved(your character by yours ≥1) →'));
      expect(trig('Cheshire Cat - Inexplicable'), startsWith('TRIG putUnder(this) →'));
      expect(trig('Grandma Wu - Wise Grandmother'), startsWith('TRIG shiftedOnto(this) →'));
      expect(trig('Sheriff of Nottingham - Corrupt Official'), startsWith('TRIG discarded(your character/action/item/location by yours) →'));
      expect(trig("Babyhead - Leader of Sid's Toys"), startsWith('TRIG inkPaid(any by yours ≤2) →'));
      expect(trig('Ink Amplifier'), startsWith('TRIG opposing draw #2 in their turn →'));
    });

    test('challenges with a condition on the challenged character', () {
      expect(trig('Brom Bones - Burly Bully'), startsWith('TRIG this challenges character'));
      expect(trig('Shenzi - Head Hyena'), startsWith('TRIG your Hyena character challenges damaged character →'));
    });

    test('6.2.6 one ability with two trigger conditions triggers on either', () {
      final abs = LorcanaParser.parse(db['Merlin - Crab']!).abilities.whereType<Triggered>().map(describeAbility).toList();
      expect(abs, hasLength(2));
      expect(abs[0], startsWith('TRIG on play'));
      expect(abs[1], startsWith('TRIG leftPlay(this)'));
    });

    test('"while here" location triggers and pronouns that mean the event card', () {
      expect(trig('The Library - A Gift for Belle'), startsWith('TRIG character banished here →'));
      expect(trig('Te Ka - Elemental Terror'), 'TRIG opposing character exerted during your turn → banish event card');
      // "Ready this character. He can't quest": he is this character.
      expect(trig('Rama - Vigilant Father'), contains('IF did it THEN this cantQuest'));
    });
  });

  group('Trigger events', () {
    test('7.5 a card put into your inkwell triggers; the second one this turn too', () {
      final g = emptyGame();
      g.addCard('Chicha - Dedicated Mother', 0, Place.play);
      g.apply(InkMove(0, g.addCard(vanilla, 0, Place.hand)));
      expect(g.pending, isNull, reason: 'only the second card');
      // A second card this turn (as if by an effect).
      final g2 = emptyGame();
      g2.addCard('Chicha - Dedicated Mother', 0, Place.play);
      g2.state.player(0).inkPutThisTurn = 1;
      g2.apply(InkMove(0, g2.addCard(vanilla, 0, Place.hand)));
      expect(g2.pending?.decision.kind, DecisionKind.yesNo);
      final hand = g2.state.player(0).hand.length;
      answer(g2, [1], player: 0);
      expect(g2.state.player(0).hand.length, hand + 1);
    });

    test('3.2.1.4 "whenever you ready this character" triggers in the Ready step', () {
      final g = emptyGame();
      g.addCard('Bolt - Superdog', 0, Place.play, exerted: true);
      g.addCard(vanilla, 0, Place.play);
      g.apply(EndTurnMove(0));
      g.apply(EndTurnMove(1));
      expect(g.state.active, 0);
      expect(g.state.player(0).lore, 1, reason: 'one other undamaged character');
    });

    test('8.4 Boost puts a card under this character, which triggers', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final cat = g.addCard('Cheshire Cat - Inexplicable', 0, Place.play);
      final boost = g.parsed(cat).abilities.indexWhere((a) => a is KeywordAbility && a.keyword.kw == Kw.boost);
      g.apply(ActivateMove(0, cat, boost));
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
      expect(g.pending?.decision.source, cat);
    });

    test('7.4.3 "when this character leaves play" triggers from outside play', () {
      final g = emptyGame();
      final gadget = g.addCard('Gadget Hackwrench - Finder of Lost Parts', 1, Place.play, exerted: true); // 0/4
      g.addCard('Steel Coil', 1, Place.discard);
      final a = g.addCard('Brom Bones - Burly Bully', 0, Place.play); // 5/4
      g.apply(ChallengeMove(0, a, gadget));
      expect(g.state.obj(gadget).zone, Place.discard);
      expect(g.pending?.decision.player, 1);
      expect(g.pending?.decision.source, gadget);
    });

    test('a challenge trigger checks the challenged character', () {
      final g = emptyGame();
      g.state.player(1).lore = 3;
      final brom = g.addCard('Brom Bones - Burly Bully', 0, Place.play);
      final weak = g.addCard(vanilla2, 1, Place.play, exerted: true); // 2 strength
      g.apply(ChallengeMove(0, brom, weak));
      expect(g.state.player(1).lore, 2);
      final g2 = emptyGame();
      g2.state.player(1).lore = 3;
      final brom2 = g2.addCard('Brom Bones - Burly Bully', 0, Place.play);
      final strong = g2.addCard(vanilla, 1, Place.play, exerted: true); // 3 strength
      g2.apply(ChallengeMove(0, brom2, strong));
      expect(g2.state.player(1).lore, 3);
    });

    test('"whenever an opposing character becomes exerted" (CR 5.1.1.2)', () {
      final g = emptyGame();
      g.addInk(0, 4);
      g.addCard('Grimorum Arcanorum', 0, Place.play);
      final target = g.addCard(vanilla, 1, Place.play);
      final isis = g.addCard('Isis Vanderchill - Ice Queen of St. Canard', 0, Place.hand);
      g.apply(PlayMove(0, isis));
      if (g.pending != null) answer(g, [target], player: 0);
      expect(g.state.obj(target).exerted, isTrue);
      expect(g.state.player(0).lore, 1);
    });

    test('"banish them": the event card, not this one', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final teka = g.addCard('Te Ka - Elemental Terror', 0, Place.play);
      final target = g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Isis Vanderchill - Ice Queen of St. Canard', 0, Place.hand)));
      if (g.pending != null) answer(g, [target], player: 0);
      expect(g.state.obj(target).zone, Place.discard);
      expect(g.state.obj(teka).zone, Place.play);
    });

    test('discarding: each card discarded triggers "whenever you discard a card"', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final sheriff = g.addCard('Sheriff of Nottingham - Corrupt Official', 0, Place.play);
      final target = g.addCard(vanilla2, 1, Place.play); // 2/3
      g.apply(PlayMove(0, g.addCard('Ransack', 0, Place.hand))); // draw 2, discard 2
      for (var i = 0; i < 2; i++) {
        expect(g.pending?.decision.source, sheriff);
        answer(g, [1], player: 0);
        if (g.pending?.decision.kind == DecisionKind.cards) answer(g, [target], player: 0);
      }
      expect(g.state.obj(target).damage, 2);
    });

    test('a second action in a turn', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final minnie = g.addCard('Minnie Mouse - Wide-Eyed Diver', 0, Place.play);
      final lore = g.chars(minnie).lore;
      g.apply(PlayMove(0, g.addCard('Dangerous Plan', 0, Place.hand)));
      expect(g.chars(minnie).lore, lore);
      g.apply(PlayMove(0, g.addCard('Dangerous Plan', 0, Place.hand)));
      expect(g.chars(minnie).lore, lore + 2);
    });

    test('paying 2 ink or less to play a card', () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.addCard("Babyhead - Leader of Sid's Toys", 0, Place.play);
      g.apply(PlayMove(0, g.addCard(vanilla2, 0, Place.hand))); // costs 2
      expect(g.pending?.decision.kind, DecisionKind.cards);
      answer(g, [g.pending!.decision.options.first], player: 0);
      expect(g.pending, isNull);
      g.apply(PlayMove(0, g.addCard(vanilla, 0, Place.hand))); // costs 3
      expect(g.pending, isNull);
    });

    test('8.10 shifting a character on top of this one triggers it from under the stack', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final wu = g.addCard('Grandma Wu - Wise Grandmother', 0, Place.play);
      final baymax = g.addCard('Baymax - Giant Robot', 0, Place.hand);
      g.apply(PlayMove(0, baymax, mode: PlayMode.shift, onto: wu));
      // Baymax's own "if you used Shift" trigger fires too, so the bag asks which goes first (CR 7.7.4).
      while (g.pending != null) {
        final d = g.pending!.decision;
        answer(g, switch (d.kind) { DecisionKind.yesNo => [1], DecisionKind.option => [0], _ => [d.options.first] });
      }
      expect(g.state.obj(baymax).under, contains(wu));
      expect(g.state.player(0).lore, 1);
    });

    test('6.1.4 an opponent choosing this character triggers', () {
      final g = emptyGame(active: 1);
      g.addInk(1, 4);
      final owl = g.addCard('Archimedes - Exceptional Owl', 0, Place.play);
      g.apply(PlayMove(1, g.addCard('Stitch - Team Underdog', 1, Place.hand)));
      answer(g, [1], player: 1);
      answer(g, [owl], player: 1);
      expect(g.pending?.decision.player, 0);
      expect(g.pending?.decision.source, owl);
    });

    test('a character banished while at this location', () {
      final g = emptyGame(active: 1);
      final lib = g.addCard('The Library - A Gift for Belle', 0, Place.play);
      final mine = g.addCard(vanilla2, 0, Place.play, exerted: true);
      g.state.obj(mine).at = lib;
      final a = g.addCard('Brom Bones - Burly Bully', 1, Place.play);
      g.apply(ChallengeMove(1, a, mine));
      expect(g.state.obj(mine).zone, Place.discard);
      expect(g.pending?.decision.player, 0);
      expect(g.pending?.decision.source, lib);
    });
  });
}
