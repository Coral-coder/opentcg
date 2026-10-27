import 'package:riftbound/riftbound.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Player 0 controls battlefield 0 with a 4 Might unit there; both decks have cards to draw.
Game heldGame() {
  final g = emptyGame();
  g.stackDeck(0, 'Shipyard Skulker', 6);
  g.stackDeck(1, 'Shipyard Skulker', 6);
  g.setControl(0, 0);
  g.addCard('Vanguard Sergeant', 0, zone: Zone.board, loc: 0);
  return g;
}

/// Ends player 0's turn and player 1's, back to player 0's Main Phase.
void nextOwnTurn(Game g) {
  g.apply(const EndTurnMove(0));
  if (g.pending != null) answer(g, Game.defaultAnswer(g.pending!.decision));
  g.apply(const EndTurnMove(1));
  if (g.pending != null) answer(g, Game.defaultAnswer(g.pending!.decision));
  // Start-of-turn triggers may wait on the chain (a facedown card can answer them).
  passAll(g);
}

List<int> ready(Game g, int p) => [for (final r in g.state.player(p).runes) if (!g.state.obj(r).exhausted) r];

void main() {
  group('Hidden (CR 811, 422, 323.6.a)', () {
    test('811.1.b hide for {A} at a battlefield you control; play it free from the next turn on, to that battlefield', () {
      final g = heldGame();
      g.addRunes(0, Domain.body, 1);
      final cub = g.addCard('Pakaa Cub', 0); // [Hidden], {3} Body, 3 Might
      expect(g.legalMoves(0), contains(isA<HideMove>()));
      g.apply(HideMove(0, cub));
      expect(g.state.obj(cub).zone, Zone.facedown);
      expect(g.state.obj(cub).loc, 0);
      expect(g.state.player(0).runes, isEmpty, reason: 'the {A} recycled a rune');
      expect(g.whyNot(PlayMove(0, cub)), contains('next turn'));
      nextOwnTurn(g);
      expect(g.whyNot(PlayMove(0, cub)), isNull, reason: 'its own cost is ignored');
      g.apply(PlayMove(0, cub));
      expect(g.state.obj(cub).zone, Zone.board);
      expect(g.state.obj(cub).loc, 0, reason: '811.1.d.1 a hidden permanent is played to its battlefield');
    });

    test('811.6 a facedown card has Reaction: played while the chain is open', () {
      final g = heldGame();
      g.addRunes(0, Domain.mind, 1);
      final consult = g.addCard('Consult the Past', 0); // [Hidden] [Reaction] Draw 2
      g.apply(HideMove(0, consult));
      g.apply(const EndTurnMove(0));
      // Player 1 plays a spell; player 0 answers from facedown.
      g.addRunes(1, Domain.order, 6);
      final kill = g.addCard('Vengeance', 1); // kill a unit
      g.apply(PlayMove(1, kill));
      expect(g.toAct, 0);
      final hand = g.state.player(0).hand.length;
      g.apply(PlayMove(0, consult));
      passAll(g);
      expect(g.state.player(0).hand.length, hand + 2);
    });

    test('811.1.d.2 a spell played from facedown chooses among options at its battlefield', () {
      final g = heldGame();
      g.addRunes(0, Domain.order, 1);
      final blade = g.addCard('Hidden Blade', 0); // kill a unit at a battlefield; its controller draws 2
      g.apply(HideMove(0, blade));
      nextOwnTurn(g);
      final here = g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 0);
      final there = g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 1);
      g.apply(PlayMove(0, blade));
      // Only the enemy at battlefield 0 and player 0's own unit there are offered.
      final d = g.pending?.decision;
      expect(d?.options, isNot(contains(there)));
      expect(d?.options, contains(here));
      answer(g, [here]);
      passAll(g);
      expect(g.state.obj(here).zone, Zone.trash);
      expect(g.state.obj(there).zone, Zone.board);
    });

    test('811.3 a card with Hidden can be played normally; Back Off draws only from hand', () {
      final g = heldGame();
      g.addRunes(0, Domain.calm, 4);
      final off = g.addCard('Back Off', 0); // [Hidden] [Action] Stun a unit; if from hand, draw 1
      final enemy = g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 1);
      final hand = g.state.player(0).hand.length;
      g.apply(PlayMove(0, off));
      answer(g, [enemy]);
      passAll(g);
      expect(g.state.obj(enemy).stunned, isTrue);
      expect(g.state.player(0).hand.length, hand, reason: 'played from hand (−1) and drew 1');
      // Hidden and played from facedown: no draw.
      final g2 = heldGame();
      g2.addRunes(0, Domain.calm, 1);
      final off2 = g2.addCard('Back Off', 0);
      g2.apply(HideMove(0, off2));
      nextOwnTurn(g2);
      final e2 = g2.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 0);
      final before = g2.state.player(0).hand.length;
      g2.apply(PlayMove(0, off2));
      answer(g2, [e2]);
      passAll(g2);
      expect(g2.state.obj(e2).stunned, isTrue);
      expect(g2.state.player(0).hand.length, before);
    });

    test('323.6.a losing the battlefield trashes the card hidden there', () {
      final g = emptyGame();
      g.setControl(0, 0);
      final guard = g.addCard('Shipyard Skulker', 0, zone: Zone.board, loc: 0);
      g.addRunes(0, Domain.body, 1);
      final cub = g.addCard('Pakaa Cub', 0);
      g.apply(HideMove(0, cub));
      // The guard leaves: player 0 loses control and the facedown card goes to the trash.
      g.apply(MoveUnitsMove(0, [guard], base));
      expect(g.state.bfs[0].controller, isNull);
      expect(g.state.obj(cub).zone, Zone.trash);
    });

    test('a hide needs an empty Facedown Zone (CR 107.3.b) and Teemo’s legend can pay {1} instead', () {
      final g = heldGame();
      g.addCard('Teemo, Swift Scout', 0, zone: Zone.legend);
      g.addRunes(0, Domain.chaos, 2);
      final a = g.addCard('Pakaa Cub', 0);
      final b = g.addCard('Teemo, Scout', 0);
      g.apply(HideMove(0, a));
      // Two ways to pay: {A} or {1}.
      expect(g.pending?.decision.labels, ['{A}', '{1}']);
      answer(g, [1]);
      expect(g.state.player(0).runes, hasLength(2), reason: '{1} exhausts a rune instead of recycling one');
      expect(g.whyNot(HideMove(0, b)), isNotNull, reason: 'one facedown card per battlefield');
    });

    test('Noxus Saboteur: opponents’ facedown cards there can’t be played', () {
      final g = heldGame();
      g.addRunes(0, Domain.body, 1);
      final cub = g.addCard('Pakaa Cub', 0);
      g.apply(HideMove(0, cub));
      nextOwnTurn(g);
      g.addCard('Noxus Saboteur', 1, zone: Zone.board, loc: 0);
      expect(g.whyNot(PlayMove(0, cub)), contains('Noxus Saboteur'));
    });

    test('Ember Monk and Evelynn: triggers for playing from facedown', () {
      final g = heldGame();
      g.addRunes(0, Domain.chaos, 1);
      final monk = g.addCard('Ember Monk', 0, zone: Zone.board);
      final eve = g.addCard('Evelynn, Entrancing', 0);
      g.apply(HideMove(0, eve));
      nextOwnTurn(g);
      final enemy = g.addCard('Shipyard Skulker', 1, zone: Zone.board);
      g.apply(PlayMove(0, eve));
      // Evelynn may move an enemy unit at a different location to her battlefield.
      while (g.pending != null) {
        final d = g.pending!.decision;
        answer(g, d.kind == DecisionKind.cards ? [enemy] : [1]);
      }
      passAll(g);
      expect(g.might(monk), 6, reason: 'Ember Monk +2 this turn');
      expect(g.state.obj(enemy).zone == Zone.trash || g.state.obj(enemy).loc == 0, isTrue, reason: 'moved to battlefield 0 (and fought there)');
    });
  });

  group('Ambush and where units are played (CR 355.2.a, 813.3.a, 822)', () {
    test('822.1.b Ambush: played as a Reaction to a battlefield where you have units, joining the combat', () {
      final g = emptyGame(active: 1);
      g.setControl(0, 0);
      g.addRunes(0, Domain.order, 3);
      final def = g.addCard('Shipyard Skulker', 0, zone: Zone.board, loc: 0); // 3 Might
      final spinner = g.addCard('Soulspinner', 0); // [Ambush] 3 Might
      final att = g.addCard('Vanguard Sergeant', 1, zone: Zone.board); // 4 Might
      g.apply(MoveUnitsMove(1, [att], 0));
      expect(g.state.showdown?.combat, isTrue);
      expect(g.toAct, 0, reason: 'the defender has Focus with an Ambush unit to play');
      g.apply(PlayMove(0, spinner));
      expect(g.state.obj(spinner).loc, 0);
      passAll(g);
      expect(g.state.obj(att).zone, Zone.trash, reason: '3 + 3 Might against 4');
      expect(g.state.obj(def).zone == Zone.board || g.state.obj(spinner).zone == Zone.board, isTrue);
    });

    test('822.3 without your units there, Ambush gives no such permission', () {
      final g = emptyGame(active: 1);
      g.addRunes(0, Domain.order, 3);
      final spinner = g.addCard('Soulspinner', 0);
      g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 1);
      g.state.showdown = Showdown(bf: 1, combat: false, attacker: 1, focus: 0);
      expect(g.whyNot(PlayMove(0, spinner)), isNotNull);
    });

    test('open battlefields (CR 170.11.c) and occupied enemy battlefields', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 3);
      final deckhand = g.addCard('Sneaky Deckhand', 0); // may be played to an open battlefield
      g.apply(PlayMove(0, deckhand));
      expect(g.pending?.decision.labels, hasLength(3), reason: 'base and both open battlefields');
      answer(g, [1]);
      passAll(g);
      expect(g.state.bfs[0].controller, 0, reason: 'it conquers the empty battlefield');
      final g2 = emptyGame();
      g2.addRunes(0, Domain.body, 5);
      g2.setControl(1, 1);
      final enemy = g2.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 1);
      final vanguard = g2.addCard('Dauntless Vanguard', 0); // 4 Might, may be played to an occupied enemy battlefield
      g2.apply(PlayMove(0, vanguard));
      expect(g2.pending?.decision.labels, ['base', 'Zaun Warrens']);
      answer(g2, [1]);
      passAll(g2);
      expect(g2.state.obj(enemy).zone, Zone.trash, reason: 'a combat it wins');
      expect(g2.state.bfs[1].controller, 0);
    });

    test('Stalking Wolf: kill a Cat, Dog, Bird or Poro of yours to play it, maybe to its battlefield', () {
      final g = emptyGame();
      g.stackDeck(0, 'Shipyard Skulker', 3);
      g.setControl(0, 0);
      g.addRunes(0, Domain.order, 5);
      final dog = g.addCard('Pakaa Cub', 0, zone: Zone.board, loc: 1); // a Cat
      g.addCard('Shipyard Skulker', 0, zone: Zone.board, loc: 0);
      final wolf = g.addCard('Stalking Wolf', 0);
      g.apply(PlayMove(0, wolf));
      expect(g.pending?.decision.labels, contains('Zaun Warrens'), reason: 'its battlefield');
      answer(g, [g.pending!.decision.labels.indexOf('Zaun Warrens')]);
      expect(g.state.obj(dog).zone, Zone.trash);
      expect(g.state.obj(wolf).loc, 1);
    });

    test('Pyke, Dockside Butcher: the additional {R} readies him with +2 Might', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 5);
      final pyke = g.addCard('Pyke, Dockside Butcher', 0);
      g.apply(PlayMove(0, pyke));
      answer(g, [1]); // pay {R} more
      passAll(g);
      expect(g.state.obj(pyke).exhausted, isFalse);
      expect(g.might(pyke), 4);
    });
  });

  group('Moving, choosing and control (CR 190.3.a.2, 355.6, 451)', () {
    test('451 Charm moves an enemy unit; a move to your battlefield contests it (CR 452)', () {
      final g = heldGame();
      g.addRunes(0, Domain.calm, 2);
      final enemy = g.addCard('Shipyard Skulker', 1, zone: Zone.board); // 3 Might, in its base
      final charm = g.addCard('Charm', 0);
      g.apply(PlayMove(0, charm));
      passAll(g);
      expect(g.pending?.decision.prompt, contains('where'));
      answer(g, [0]); // Grove of the God-Willow, held by player 0's 4 Might unit
      passAll(g);
      expect(g.state.obj(enemy).zone, Zone.trash, reason: 'it attacked into 4 Might and died');
    });

    test('Isolate: an enemy unit left alone where it was means a draw', () {
      final g = heldGame();
      g.addRunes(0, Domain.chaos, 2);
      final a = g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 1);
      g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 1);
      final isolate = g.addCard('Isolate', 0);
      final hand = g.state.player(0).hand.length;
      g.apply(PlayMove(0, isolate));
      answer(g, [a]);
      passAll(g);
      expect(g.state.obj(a).loc, base);
      expect(g.state.player(0).hand.length, hand, reason: 'played Isolate, drew 1');
    });

    test('355.6 a unit that can’t be chosen by enemies isn’t offered', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 6);
      final runner = g.addCard('Ruin Runner', 1, zone: Zone.board);
      final other = g.addCard('Shipyard Skulker', 1, zone: Zone.board);
      g.apply(PlayMove(0, g.addCard('Vengeance', 0)));
      // The only choosable unit was chosen without asking, and the spell resolved.
      expect(g.pending, isNull);
      expect(g.state.obj(other).zone, Zone.trash);
      expect(g.state.obj(runner).zone, Zone.board);
    });

    test('Hostile Takeover: control until end of turn, then back and recalled', () {
      final g = heldGame();
      g.addRunes(0, Domain.mind, 7);
      final enemy = g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 1);
      final take = g.addCard('Hostile Takeover', 0);
      g.apply(PlayMove(0, take));
      passAll(g);
      expect(g.state.obj(enemy).controller, 0);
      expect(g.state.obj(enemy).exhausted, isFalse);
      g.apply(const EndTurnMove(0));
      expect(g.state.obj(enemy).controller, 1);
      expect(g.state.obj(enemy).loc, base);
    });

    test('Tideturner swaps places with a friendly unit', () {
      final g = heldGame();
      g.addRunes(0, Domain.chaos, 2);
      final far = g.addCard('Shipyard Skulker', 0, zone: Zone.board, loc: 0);
      final tide = g.addCard('Tideturner', 0);
      g.apply(PlayMove(0, tide));
      answer(g, [0]); // to base
      passAll(g);
      while (g.pending != null) {
        answer(g, g.pending!.decision.kind == DecisionKind.cards ? [far] : [1]);
      }
      passAll(g);
      expect(g.state.obj(tide).loc, 0);
      expect(g.state.obj(far).loc, base);
    });
  });

  group('Replacement effects and passives (CR 367–369)', () {
    test('369.1 Zhonya’s Hourglass dies instead; the unit is healed, exhausted and recalled', () {
      final g = heldGame();
      g.addRunes(0, Domain.calm, 2);
      final glass = g.addCard('Zhonya\'s Hourglass', 0, zone: Zone.board);
      final unit = g.addCard('Shipyard Skulker', 0, zone: Zone.board, loc: 0);
      g.addRunes(1, Domain.order, 6);
      g.apply(const EndTurnMove(0));
      g.apply(PlayMove(1, g.addCard('Vengeance', 1)));
      answer(g, [unit]);
      passAll(g);
      expect(g.state.obj(unit).zone, Zone.board);
      expect(g.state.obj(unit).loc, base);
      expect(g.state.obj(unit).exhausted, isTrue);
      expect(g.state.obj(glass).zone, Zone.trash);
    });

    test('Lotus Trap doubles damage this turn; Sudden Storm deals 4 to an attacker', () {
      final g = heldGame();
      g.addRunes(0, Domain.fury, 5);
      final enemy = g.addCard('Mega-Mech', 1, zone: Zone.board, loc: 1); // 8 Might
      g.apply(PlayMove(0, g.addCard('Lotus Trap', 0)));
      answer(g, [enemy]);
      passAll(g);
      g.apply(PlayMove(0, g.addCard('Sudden Storm', 0)));
      answer(g, [enemy]);
      passAll(g);
      expect(g.state.obj(enemy).damage, 4, reason: '2 doubled');
    });

    test('Vilemaw: weaker enemy units there deal no combat damage', () {
      final g = emptyGame(active: 1);
      g.setControl(0, 0);
      final maw = g.addCard('Vilemaw', 0, zone: Zone.board, loc: 0); // 8 Might
      final att = g.addCard('Vanguard Sergeant', 1, zone: Zone.board);
      g.apply(MoveUnitsMove(1, [att], 0));
      passAll(g);
      expect(g.state.obj(maw).damage, 0);
      expect(g.state.obj(att).zone, Zone.trash);
    });

    test('Kennen: +2 Might while there’s a stunned enemy unit there; Spiderling counts its namesakes', () {
      final g = heldGame();
      final kennen = g.addCard('Kennen, Keeper of Balance', 0, zone: Zone.board, loc: 0);
      final enemy = g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 0);
      expect(g.might(kennen), 2);
      g.state.obj(enemy).stunned = true;
      expect(g.might(kennen), 4);
      final s1 = g.addCard('Spiderling', 0, zone: Zone.board, loc: 1);
      g.addCard('Spiderling', 0, zone: Zone.board, loc: 1);
      g.addCard('Spiderling', 0, zone: Zone.board, loc: 0);
      expect(g.might(s1), 2);
    });

    test('Disciple of Shen has Shield 3 with exactly one partner at a battlefield', () {
      final g = heldGame();
      final d = g.addCard('Disciple of Shen', 0, zone: Zone.board, loc: 0);
      expect(g.hasKw(d, Kw.shield), isTrue);
      g.addCard('Shipyard Skulker', 0, zone: Zone.board, loc: 0);
      expect(g.hasKw(d, Kw.shield), isFalse);
    });

    test('Bushwhack: friendly units enter ready this turn; Keeper of Masks’ copies stop existing when they die', () {
      final g = heldGame();
      g.addRunes(0, Domain.fury, 3);
      g.addRunes(0, Domain.mind, 2);
      g.apply(PlayMove(0, g.addCard('Bushwhack', 0)));
      passAll(g);
      final keeper = g.addCard('Keeper of Masks', 0);
      g.apply(PlayMove(0, keeper));
      answer(g, [1]); // to the battlefield
      passAll(g);
      final copies = [for (final u in g.units(player: 0)) if (g.nameOf(u) == 'Keeper of Masks' && u != keeper) u];
      expect(copies, hasLength(2));
      expect(g.state.obj(keeper).exhausted, isFalse);
      g.state.obj(copies.first).damage = 5;
      g.settleForTest();
      expect(g.state.obj(copies.first).zone, Zone.gone);
    });

    test('Fox-Fire kills units at a battlefield with total Might 4 or less', () {
      final g = heldGame();
      g.addRunes(0, Domain.calm, 3);
      final a = g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 1);
      final b = g.addCard('Pakaa Cub', 1, zone: Zone.board, loc: 1);
      g.apply(PlayMove(0, g.addCard('Fox-Fire', 0)));
      answer(g, [g.state.bfs[1].obj]);
      passAll(g);
      answer(g, [a]);
      expect(g.pending, isNull, reason: 'only 1 Might left: nothing more to choose');
      expect(g.state.obj(a).zone, Zone.trash);
      expect(g.state.obj(b).zone, Zone.board);
    });
  });

  group('Decks (CR 103.2.c, 825)', () {
    test('825.3.a Unique: one copy; Spiderling: any number', () {
      expect(copyLimit(db['Forgefire Cape']!), 1);
      expect(copyLimit(db['Spiderling']!), greaterThan(40));
      expect(copyLimit(db['Shipyard Skulker']!), 3);
    });
  });
}
