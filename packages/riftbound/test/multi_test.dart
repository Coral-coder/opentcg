import 'package:riftbound/riftbound.dart';
import 'package:tcg_core/tcg_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Modes of Play with more than two players (CR 489–491) and what they change.
void main() {
  /// A hand-built Main Phase position for [mode]: [names.length] players, three battlefields.
  Game modeGame(RMode mode, {int active = 0}) {
    final g = Game(db, players: [for (var p = 0; p < mode.players; p++) 'P$p'], seed: 1)
      ..setUpEmpty(battlefields: const ['Grove of the God-Willow', 'Zaun Warrens', 'Amateur Recital'], active: active)
      ..setMode(mode);
    // Something to draw, so nobody burns out.
    for (var p = 0; p < mode.players; p++) {
      g.stackDeck(p, 'Daring Poro', 6);
    }
    return g;
  }

  /// A real deal of [mode] from random supported decks.
  Game dealt(RMode mode, {int first = 0, int seed = 3}) {
    final rng = SeededRng(seed);
    final g = Game(db, players: [for (var p = 0; p < mode.players; p++) 'P$p'], seed: seed);
    g.apply(StartMove(randomDecksFor(db, rng, mode), firstPlayer: first, mode: mode));
    // Everyone keeps their opening hand.
    while (g.pending != null) {
      answer(g, Game.defaultAnswer(g.pending!.decision));
    }
    return g;
  }

  group('Setup (CR 489.4–489.7, 490.4–490.7, 491.3–491.7)', () {
    test('Skirmish: three players, each brings one battlefield, Victory Score 8', () {
      final g = dealt(RMode.ffa3);
      expect(g.state.bfs.length, 3);
      expect({for (final b in g.state.bfs) g.state.obj(b.obj).owner}, {0, 1, 2});
      expect(g.state.victoryScore, 8);
    });

    test('War: the first player’s battlefields aren’t used (CR 490.4.b)', () {
      final g = dealt(RMode.ffa4, first: 2);
      expect(g.state.bfs.length, 3);
      expect([for (final b in g.state.bfs) g.state.obj(b.obj).owner], isNot(contains(2)));
    });

    test('Magma Chamber: Victory Score 11, first player’s battlefields not used (CR 491.3, 491.5.b)', () {
      final g = dealt(RMode.teams, first: 1);
      expect(g.state.victoryScore, 11);
      expect(g.state.bfs.length, 3);
      expect([for (final b in g.state.bfs) g.state.obj(b.obj).owner], isNot(contains(1)));
    });

    test('The first player doesn’t draw on their first turn (CR 489.7)', () {
      final g = dealt(RMode.ffa3);
      // Four cards in the opening hand, and no draw in the first Draw Phase.
      expect(g.state.player(0).hand.length, 4);
      expect(g.state.active, 0);
    });

    test('The player going last channels an extra rune on their first turn (CR 490.7)', () {
      final g = dealt(RMode.ffa4);
      for (var p = 0; p < 3; p++) {
        expect(g.state.active, p);
        expect(g.state.player(p).runes.length, 2, reason: 'seat $p channels 2');
        g.apply(EndTurnMove(p));
        while (g.pending != null) {
          answer(g, Game.defaultAnswer(g.pending!.decision));
        }
      }
      expect(g.state.active, 3);
      expect(g.state.player(3).runes.length, 3);
    });

    test('Teammates may not play the same Champion Legend (CR 491.8.h)', () {
      final rng = SeededRng(5);
      final decks = randomDecksFor(db, rng, RMode.teams);
      decks[2] = decks[0];
      final g = Game(db, players: const ['A', 'B', 'C', 'D'], seed: 5);
      expect(() => g.apply(StartMove(decks, firstPlayer: 0, mode: RMode.teams)), throwsA(isA<TcgError>()));
    });

    test('A mode needs its number of players', () {
      final g = Game(db, players: const ['A', 'B', 'C'], seed: 1);
      expect(() => g.apply(StartMove([starter(), starter(1), starter(2)], mode: RMode.ffa4)), throwsA(isA<TcgError>()));
    });

    test('The start move carries the mode through JSON; a Duel’s JSON is unchanged', () {
      final m = StartMove(const [], mode: RMode.teams);
      expect((RMove.fromJson(m.toJson()) as StartMove).mode, RMode.teams);
      expect(StartMove(const []).toJson().containsKey('mode'), isFalse);
    });
  });

  group('Turn order, Priority and Focus (CR 315, 338, 346, 491.5.c)', () {
    test('2v2 alternates teams: 0, 1, 2, 3 with seats 0 and 2 on one team', () {
      final g = modeGame(RMode.teams);
      expect([for (var p = 0; p < 4; p++) g.state.team(p)], [0, 1, 0, 1]);
      expect(g.state.nextSeat(0), 1);
      expect(g.state.nextSeat(3), 0);
      expect(g.state.opponents(0), [1, 3]);
      expect(g.state.teammates(0), [2]);
    });

    test('Ending a turn passes it to the next seat around the table', () {
      final g = dealt(RMode.ffa3, first: 1);
      expect(g.state.active, 1);
      g.apply(EndTurnMove(1));
      while (g.pending != null) {
        answer(g, Game.defaultAnswer(g.pending!.decision));
      }
      expect(g.state.active, 2);
    });

    test('A spell resolves only after every player passes Priority in turn (CR 338.1.b)', () {
      final g = modeGame(RMode.ffa3);
      for (final d in Domain.values) {
        g.addRunes(0, d, 3);
      }
      final enemy = g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 0);
      // Players 1 and 2 could respond, so each of them really holds Priority.
      for (final q in [1, 2]) {
        for (final d in Domain.values) {
          g.addRunes(q, d, 2);
        }
        g.addCard('Abandon', q);
      }
      final hand = g.addCard('Void Seeker', 0);
      g.apply(PlayMove(0, hand));
      while (g.pending != null) {
        final d = g.pending!.decision;
        answer(g, d.options.contains(enemy) ? [enemy] : Game.defaultAnswer(d));
      }
      final passers = <int>[];
      while (g.state.chain.isNotEmpty && g.pending == null) {
        passers.add(g.toAct!);
        g.apply(PassMove(g.toAct!));
      }
      // Player 0 has nothing to respond with and passes by itself; then 1 and 2, in turn order,
      // and only then does the spell resolve (Void Seeker's 4 damage kills the Sergeant).
      expect(passers, [1, 2]);
      expect(g.state.chain, isEmpty);
      expect(g.state.obj(enemy).zone, Zone.trash);
    });
  });

  group('Friendly, enemy and opponents (CR 485.2.b, 491.8.e)', () {
    test('A teammate’s unit is friendly; another team’s is an enemy', () {
      final g = modeGame(RMode.teams);
      final mate = g.addCard('Vanguard Sergeant', 2, zone: Zone.board);
      final foe = g.addCard('Vanguard Sergeant', 1, zone: Zone.board);
      expect(g.matches(const Filter(side: Side.friendly), mate, controller: 0), isTrue);
      expect(g.matches(const Filter(side: Side.enemy), mate, controller: 0), isFalse);
      expect(g.matches(const Filter(side: Side.enemy), foe, controller: 0), isTrue);
      expect(g.enemyUnits(0), [foe]);
    });

    test('In free-for-all every other player is an opponent', () {
      final g = modeGame(RMode.ffa4);
      expect(g.state.opponents(1), [2, 3, 0]);
      expect(g.state.teammates(1), isEmpty);
    });

    test('"An opponent" asks which one when there are several', () {
      final g = modeGame(RMode.ffa3);
      expect(() => g.chooseOpponent(0, 'Which?'), throwsA(isA<NeedDecision>()));
    });
  });

  group('Moving and playing to battlefields (CR 449.2, 464)', () {
    test('Units can’t move where two other players are (a combat there would be three-way)', () {
      final g = modeGame(RMode.ffa3);
      final mine = g.addCard('Vanguard Sergeant', 0, zone: Zone.board);
      g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 0);
      g.addCard('Vanguard Sergeant', 2, zone: Zone.board, loc: 0);
      expect(g.moveDestinations(mine), isNot(contains(0)));
      expect(g.moveDestinations(mine), containsAll([1, 2]));
    });

    test('Units can’t move to a battlefield their teammate occupies (CR 449.2.b)', () {
      final g = modeGame(RMode.teams);
      final mine = g.addCard('Vanguard Sergeant', 0, zone: Zone.board);
      g.addCard('Vanguard Sergeant', 2, zone: Zone.board, loc: 1);
      expect(g.moveDestinations(mine), isNot(contains(1)));
    });

    test('Moving into another player’s battlefield starts a combat with that player only (CR 464)', () {
      final g = modeGame(RMode.ffa3);
      final mine = g.addCard('Vanguard Sergeant', 0, zone: Zone.board);
      final theirs = g.addCard('Daring Poro', 2, zone: Zone.board, loc: 1);
      g.setControl(1, 2);
      final bystander = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 2);
      g.apply(MoveUnitsMove(0, [mine], 1));
      passAll(g);
      // Vanguard Sergeant (4 Might) beats Daring Poro; player 1 isn't involved.
      expect(g.state.log.any((l) => l.text.startsWith('Combat at') && l.text.contains('P0 attacks')), isTrue);
      expect(g.state.obj(theirs).zone, Zone.trash);
      expect(g.state.obj(bystander).damage, 0);
      expect(g.state.bfs[1].controller, 0);
    });
  });

  group('Scoring and winning (CR 194.2, 323.1, 491.8.b, 491.8.d)', () {
    test('Teams share points: holding gives both teammates the point (CR 491.8.d)', () {
      final g = modeGame(RMode.teams, active: 3);
      g.addCard('Vanguard Sergeant', 0, zone: Zone.board, loc: 0);
      g.setControl(0, 0);
      g.startTurnForTest(0);
      expect(g.state.player(0).points, 1);
      expect(g.state.player(2).points, 1);
      expect(g.state.player(1).points, 0);
    });

    test('A battlefield a teammate controlled at the scoring step can’t be scored by the team that turn (CR 491.8.b.1)', () {
      final g = modeGame(RMode.teams, active: 3);
      final mate = g.addCard('Daring Poro', 2, zone: Zone.board, loc: 1);
      g.setControl(1, 2);
      final mine = g.addCard('Vanguard Sergeant', 0, zone: Zone.board);
      g.startTurnForTest(0);
      // The teammate's unit leaves; then this player conquers the now-empty battlefield.
      g.state.obj(mate).loc = base;
      g.settleForTest();
      g.apply(MoveUnitsMove(0, [mine], 1));
      passAll(g);
      expect(g.state.bfs[1].controller, 0);
      expect(g.state.player(0).points, 0, reason: 'conquered, but disqualified this turn');
    });

    test('Winning needs the Victory Score and more points than every opponent (CR 194.2)', () {
      final g = modeGame(RMode.ffa3);
      g.state.player(0).points = 8;
      g.state.player(2).points = 8;
      g.settleForTest();
      expect(g.over, isFalse, reason: 'tied with an opponent');
      g.state.player(2).points = 7;
      g.settleForTest();
      expect(g.state.winner, 0);
    });

    test('2v2 is won at 11, together (CR 491.3, 491.6.a.3)', () {
      final g = modeGame(RMode.teams);
      g.state.player(1).points = 10;
      g.state.player(3).points = 10;
      g.settleForTest();
      expect(g.over, isFalse);
      g.state.player(1).points = 11;
      g.state.player(3).points = 11;
      g.settleForTest();
      expect(g.over, isTrue);
      expect(g.state.team(g.state.winner!), 1);
    });
  });

  group('Conceding (CR 649–652)', () {
    test('In free-for-all the game goes on without them; their units are banished (CR 651.2, 652.1)', () {
      final g = modeGame(RMode.ffa3);
      final u = g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 0);
      g.apply(ConcedeMove(1));
      expect(g.over, isFalse);
      expect(g.state.obj(u).zone, Zone.banish);
      expect(g.state.nextSeat(0), 2);
    });

    test('The last one standing wins (CR 651.1)', () {
      final g = modeGame(RMode.ffa3);
      g.apply(ConcedeMove(1));
      g.apply(ConcedeMove(2));
      expect(g.state.winner, 0);
    });

    test('In 2v2 a player conceding takes their teammate with them (CR 491.6.a.1, 651.4)', () {
      final g = modeGame(RMode.teams);
      g.apply(ConcedeMove(2));
      expect(g.over, isTrue);
      expect(g.state.team(g.state.winner!), 1);
    });
  });

  test('Bots finish every mode', () {
    for (final mode in [RMode.ffa3, RMode.ffa4, RMode.teams]) {
      final g = dealt(mode, seed: 11);
      final done = runBots(g, [for (var p = 0; p < mode.players; p++) RiftboundBot(p, seed: 11 + p)], maxMoves: 8000);
      expect(done, isTrue, reason: mode.id);
    }
  });

  test('Duel plays exactly as before multiplayer (fingerprints recorded at 7445f20)', () {
    // The first games of tool/xplat.dart (seed 7).
    const before = ['a6b427a21bb760dfc1e15ee2', 'fb3cb6f4b16cdc43f3a34856', 'ee27df61d574509022786b60'];
    final rng = SeededRng(7);
    for (var n = 0; n < before.length; n++) {
      final seed = rng.nextInt(1 << 30);
      final decks = randomDecksFor(db, rng, RMode.duel);
      final g = Game(db, players: const ['A', 'B'], seed: seed);
      g.apply(StartMove(decks));
      runBots(g, [RiftboundBot(0, seed: seed), RiftboundBot(1, seed: seed + 1)], maxMoves: 4000);
      expect(g.fingerprint, before[n]);
    }
  });
}
