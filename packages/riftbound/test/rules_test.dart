import 'package:riftbound/riftbound.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Playing cards and paying (CR 143, 164, 353–359, 805)', () {
    test('143.4 a unit enters exhausted; 164 Energy from exhausting runes, Power from recycling', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 4);
      final jinx = g.addCard('Jinx, Demolitionist', 0); // {3} + 1 Fury, Accelerate
      g.apply(PlayMove(0, jinx));
      // Accelerate is offered (CR 805): decline.
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
      answer(g, [0]);
      final o = g.state.obj(jinx);
      expect(o.zone, Zone.board);
      expect(o.loc, base);
      expect(o.exhausted, isTrue);
      // 3 runes exhausted for Energy, one of them then recycled for the Power: one ready rune left.
      expect(g.state.player(0).runes, hasLength(3));
      expect([for (final r in g.state.player(0).runes) if (!g.state.obj(r).exhausted) r], hasLength(1));
      expect(g.state.player(0).runeDeck, hasLength(1));
    });

    test('805 Accelerate: pay {1}{C} more and the unit enters ready', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 4);
      final r = g.addCard('Legion Rearguard', 0); // {2}, Accelerate
      g.apply(PlayMove(0, r));
      answer(g, [1]);
      expect(g.state.obj(r).exhausted, isFalse);
      expect(g.state.player(0).runes, hasLength(3), reason: '{3} Energy and one Fury Power');
    });

    test('a card that can’t be paid for can’t be played', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 2);
      final c = g.addCard('Jinx, Demolitionist', 0);
      expect(g.whyNot(PlayMove(0, c)), contains('Not enough'));
    });

    test('355.2.a units are played to base or a battlefield you control', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 3);
      g.setControl(1, 0);
      final a = g.addCard('Faithful Manufactor', 0); // {3} Order: play a Recruit here
      g.apply(PlayMove(0, a));
      expect(g.pending?.decision.labels, ['base', 'Zaun Warrens']);
      answer(g, [1]);
      expect(g.state.obj(a).loc, 1);
      // Its play trigger made a Recruit "here" (CR 187.1).
      final recruits = [for (final u in g.unitsAt(1, player: 0)) if (g.card(u).name == 'Recruit') u];
      expect(recruits, hasLength(1));
    });
  });

  group('Moving, showdowns and conquering (CR 144, 344–348, 471)', () {
    test('144 a Standard Move exhausts; an empty battlefield is conquered after a showdown', () {
      final g = emptyGame();
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      g.apply(MoveUnitsMove(0, [u], 0));
      expect(g.state.obj(u).exhausted, isTrue);
      expect(g.state.obj(u).loc, 0);
      expect(g.state.bfs[0].controller, 0);
      expect(g.state.player(0).points, 1);
      expect(g.state.showdown, isNull);
    });

    test('144.4 from base to a battlefield, back to base, never battlefield to battlefield without Ganking', () {
      final g = emptyGame();
      final u = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 0);
      expect(g.moveDestinations(u), [base]);
      final r = g.addCard('Rengar, Unseen', 0, zone: Zone.board, loc: 0); // Ganking (CR 810)
      expect(g.moveDestinations(r), [base, 1]);
    });

    test('473.1.b the final point from a Conquer needs every battlefield scored this turn', () {
      final g = emptyGame();
      g.stackDeck(0, 'Daring Poro', 3);
      g.state.player(0).points = 7;
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      g.apply(MoveUnitsMove(0, [u], 0));
      expect(g.state.player(0).points, 7, reason: 'Zaun Warrens was not scored this turn');
      expect(g.state.player(0).hand, hasLength(1), reason: 'draws a card instead');
      expect(g.over, isFalse);
    });
  });

  group('Combat (CR 461–468)', () {
    test('467 Might is assigned as damage; 807 Assault and 814 Shield count; Tank first; 468 the winner conquers', () {
      final g = emptyGame();
      g.setControl(0, 1);
      final def = g.addCard('Sunlit Guardian', 1, zone: Zone.board, loc: 0); // 3 Might, Shield, Tank
      final att = g.addCard('Petty Officer', 0, zone: Zone.board); // 5 Might, Assault
      g.apply(MoveUnitsMove(0, [att], 0));
      // 6 (5 + Assault) kills the 4-Might (3 + Shield) defender; 4 doesn't kill the attacker.
      expect(g.state.obj(def).zone, Zone.trash);
      expect(g.state.obj(att).zone, Zone.board);
      expect(g.state.obj(att).damage, 0, reason: 'units heal in the combat cleanup (CR 468.1)');
      expect(g.state.bfs[0].controller, 0);
      expect(g.state.player(0).points, 1);
    });

    test('468.1 attackers are recalled if defenders survive too; 424 stunned units deal no combat damage', () {
      final g = emptyGame();
      g.setControl(0, 1);
      final def = g.addCard('Zephyr Sage', 1, zone: Zone.board, loc: 0); // 6 Might, Shield
      g.state.obj(def).stunned = true;
      final att = g.addCard('Daring Poro', 0, zone: Zone.board); // 2 Might, Assault
      g.apply(MoveUnitsMove(0, [att], 0));
      expect(g.state.obj(att).zone, Zone.board);
      expect(g.state.obj(att).loc, base, reason: 'recalled');
      expect(g.state.obj(def).zone, Zone.board);
      expect(g.state.bfs[0].controller, 1);
      expect(g.state.player(0).points, 0);
    });

    test('815 Tank must be assigned lethal damage first', () {
      final g = emptyGame();
      g.setControl(0, 1);
      final plain = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0); // 2 Might
      final tank = g.addCard('Horns of the Dragon', 1, zone: Zone.board, loc: 0); // 6 Might, Tank
      final att = g.addCard('Zephyr Sage', 0, zone: Zone.board); // 6 Might
      g.apply(MoveUnitsMove(0, [att], 0));
      expect(g.state.obj(tank).zone, Zone.trash, reason: '6 damage goes to the Tank first');
      expect(g.state.obj(plain).zone, Zone.board);
    });

    test('347 Focus: the defender plays an Action in the showdown; 340 the chain resolves before damage', () {
      final g = emptyGame();
      g.setControl(0, 1);
      g.addRunes(1, Domain.calm, 2);
      final def = g.addCard('Stalwart Poro', 1, zone: Zone.board, loc: 0); // 2 Might, Shield
      final pump = g.addCard('Discipline', 1); // [Reaction] +2 Might, draw 1
      g.stackDeck(1, 'Daring Poro', 2);
      final att = g.addCard('Petty Officer', 0, zone: Zone.board); // 5 Might, Assault
      g.apply(MoveUnitsMove(0, [att], 0));
      // The attacker had nothing to play and passed; the defender has Focus.
      expect(g.state.showdown?.combat, isTrue);
      expect(g.toAct, 1);
      expect(g.might(att), 6, reason: 'Assault while attacking');
      expect(g.might(def), 3, reason: 'Shield while defending');
      g.apply(PlayMove(1, pump));
      answer(g, [def]);
      // Discipline resolved (+2 Might, draw 1); Focus passed back; everyone passed; damage.
      expect(g.state.obj(pump).zone, Zone.trash);
      expect(g.state.player(1).hand, hasLength(1));
      // 5 Might defender vs 6: it dies; the attacker takes 5 of its 6.
      expect(g.state.obj(def).zone, Zone.trash);
      expect(g.state.obj(att).zone, Zone.board);
    });
  });

  group('The chain (CR 327–340, 426, 813)', () {
    test('813 a Reaction answers a spell; 426 Counter stops it', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 6);
      g.addRunes(1, Domain.calm, 5);
      final target = g.addCard('Daring Poro', 1, zone: Zone.board);
      final kill = g.addCard('Vengeance', 0); // {4} + 2 Order: kill a unit
      final wall = g.addCard('Wind Wall', 1); // [Reaction] counter a spell
      // The only legal target is chosen without asking.
      g.apply(PlayMove(0, kill));
      // Player 1 holds Priority with a legal Reaction.
      expect(g.toAct, 1);
      expect(g.state.chain, hasLength(1));
      g.apply(PlayMove(1, wall));
      expect(g.state.chain, isEmpty);
      expect(g.state.obj(target).zone, Zone.board);
      expect(g.state.obj(kill).zone, Zone.trash);
      expect(g.state.obj(wall).zone, Zone.trash);
    });

    test('a player with Priority but nothing to play passes automatically', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 6);
      final target = g.addCard('Daring Poro', 1, zone: Zone.board);
      final kill = g.addCard('Vengeance', 0);
      g.apply(PlayMove(0, kill));
      expect(g.state.chain, isEmpty);
      expect(g.state.obj(target).zone, Zone.trash);
      expect(g.toAct, 0);
    });

    test('809 Deflect: a spell choosing an enemy Deflect unit costs {A} more', () {
      // One rune pays Hextech Ray ({1}, then recycled for its Fury), but not the extra {A}.
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 1);
      g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
      expect(g.whyNot(PlayMove(0, g.addCard('Hextech Ray', 0))), isNull);
      final g1 = emptyGame();
      g1.addRunes(0, Domain.fury, 1);
      g1.addCard('Pouty Poro', 1, zone: Zone.board, loc: 0); // Deflect
      expect(() => g1.apply(PlayMove(0, g1.addCard('Hextech Ray', 0))), throwsA(isA<RiftboundError>()));
      final g2 = emptyGame();
      g2.addRunes(0, Domain.fury, 2);
      final poro2 = g2.addCard('Pouty Poro', 1, zone: Zone.board, loc: 0);
      g2.apply(PlayMove(0, g2.addCard('Hextech Ray', 0)));
      expect(g2.state.obj(poro2).zone, Zone.trash);
      expect(g2.state.player(0).runes, isEmpty, reason: 'both runes recycled for Power');
    });
  });

  group('Abilities (CR 808, 812, 816, 817)', () {
    test('808 Deathknell triggers when it dies', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 6);
      g.stackDeck(1, 'Daring Poro', 2);
      final sentry = g.addCard('Watchful Sentry', 1, zone: Zone.board); // Deathknell: draw 1
      g.apply(PlayMove(0, g.addCard('Vengeance', 0)));
      expect(g.state.obj(sentry).zone, Zone.trash);
      expect(g.state.player(1).hand, hasLength(1));
    });

    test('812 Legion: only after playing another card this turn', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 6);
      final a = g.addCard('Trifarian Gloryseeker', 0); // Legion: buff me
      g.apply(PlayMove(0, a));
      expect(g.state.obj(a).buffed, isFalse);
      final b = g.addCard('Trifarian Gloryseeker', 0);
      g.apply(PlayMove(0, b));
      expect(g.state.obj(b).buffed, isTrue);
      expect(g.might(b), 3, reason: 'a buff is +1 Might (CR 703)');
    });

    test('816 Temporary: killed at the start of its controller’s turn', () {
      final g = emptyGame();
      g.stackDeck(0, 'Daring Poro', 3);
      g.stackDeck(1, 'Daring Poro', 3);
      g.addRunes(0, Domain.mind, 5);
      g.apply(PlayMove(0, g.addCard('Sprite Burst', 0))); // two ready Sprites with Temporary
      final sprites = [for (final u in g.units(player: 0)) if (g.card(u).name == 'Sprite') u];
      expect(sprites, hasLength(2));
      expect(g.state.obj(sprites.first).exhausted, isFalse);
      g.apply(const EndTurnMove(0));
      g.apply(const EndTurnMove(1));
      expect(g.units(player: 0), isEmpty);
      expect(g.state.obj(sprites.first).zone, Zone.gone, reason: 'tokens cease to exist (CR 186.1)');
    });

    test('817 Vision: look at the top card and choose whether to recycle it', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 2);
      g.stackDeck(0, 'Watchful Sentry', 1);
      g.stackDeck(0, 'Daring Poro', 1); // top
      final poro = g.addCard('Mystic Poro', 0); // {2}, Vision
      g.apply(PlayMove(0, poro));
      expect(g.pending?.decision.prompt, startsWith('Predict'));
      final top = g.state.player(0).deck.first;
      answer(g, [top]);
      expect(g.state.player(0).deck.last, top);
    });
  });

  group('Turn structure and scoring (CR 315–317, 432, 471.2)', () {
    test('471.2 hold at the start of your turn, then channel 2 and draw 1', () {
      final g = emptyGame();
      g.stackDeck(0, 'Daring Poro', 5);
      g.stackDeck(1, 'Daring Poro', 5);
      g.addCard('Daring Poro', 0, zone: Zone.board, loc: 0);
      g.setControl(0, 0);
      g.state.player(0).runeDeck.addAll([for (var i = 0; i < 4; i++) g.addCard('Fury Rune', 0, zone: Zone.runeDeck)]);
      g.apply(const EndTurnMove(0));
      g.apply(const EndTurnMove(1));
      expect(g.state.active, 0);
      expect(g.state.player(0).points, 1);
      // Grove of the God-Willow: "When you hold here, draw 1", plus the Draw Phase.
      expect(g.state.player(0).hand, hasLength(2));
      expect(g.state.player(0).runes, hasLength(2));
    });

    test('432 Burn Out: an empty deck recycles the trash and the opponent gains a point', () {
      final g = emptyGame();
      g.addCard('Daring Poro', 1, zone: Zone.trash);
      g.addCard('Daring Poro', 1, zone: Zone.trash);
      g.apply(const EndTurnMove(0));
      expect(g.state.player(0).points, 1);
      expect(g.state.player(1).hand, hasLength(1));
      expect(g.state.player(1).deck, hasLength(1));
    });

    test('194.2 eight points wins', () {
      final g = emptyGame();
      g.stackDeck(0, 'Daring Poro', 3);
      g.state.player(0).points = 7;
      g.state.player(0).scored = [1];
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      g.apply(MoveUnitsMove(0, [u], 0));
      expect(g.over, isTrue);
      expect(g.state.winner, 0);
    });
  });

  group('Setup (CR 110–118, 487)', () {
    test('116–117 each player draws 4 and may replace up to 2; 487.7 the second player channels 3 first', () {
      final g = Game(db, players: ['A', 'B'], seed: 5);
      g.apply(StartMove([starter(0), starter(1)], firstPlayer: 0));
      expect(g.pending?.decision.max, 2);
      final two = g.state.player(0).hand.take(2).toList();
      answer(g, two, player: 0);
      answer(g, const [], player: 1);
      expect(g.state.player(0).hand, hasLength(5), reason: '4, then the Draw Phase');
      expect(two.every((id) => g.state.player(0).deck.contains(id)), isTrue, reason: 'recycled');
      expect(g.state.player(0).runes, hasLength(2));
      expect(g.state.bfs, hasLength(2));
      expect(g.state.player(0).champion, isNotNull, reason: 'the Chosen Champion waits in its zone');
      g.apply(const EndTurnMove(0));
      expect(g.state.player(1).runes, hasLength(3));
    });

    test('every playable legend has a legal, fully supported starter deck', () {
      final legends = playableLegends(db);
      expect(legends.length, greaterThanOrEqualTo(8));
      for (final l in legends) {
        expect(validateDeck(db, buildDeck(db, l)), isEmpty, reason: l.name);
      }
    });
  });
}
