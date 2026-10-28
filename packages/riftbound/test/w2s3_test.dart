import 'package:riftbound/riftbound.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Answers every pending decision with [pick] (default answer when it returns null) and passes
/// open chains and showdowns, until nothing is left to do.
void settle(Game g, {List<int>? Function(Decision d)? pick, int limit = 60}) {
  for (var i = 0; i < limit && !g.over; i++) {
    final d = g.pending?.decision;
    if (d != null) {
      answer(g, pick?.call(d) ?? Game.defaultAnswer(d));
      continue;
    }
    if (g.state.chain.isEmpty && g.state.showdown == null) return;
    g.apply(PassMove(g.toAct!));
  }
}

/// Answers decisions whose prompt contains a key with its answer; others get the default.
List<int>? Function(Decision) by(Map<String, List<int>> answers) => (d) {
      for (final e in answers.entries) {
        if (d.prompt.contains(e.key)) return e.value;
      }
      return null;
    };

void addRuneDeck(Game g, int p, String rune, int n) {
  for (var i = 0; i < n; i++) {
    g.state.player(p).runeDeck.add(g.addCard(rune, p, zone: Zone.runeDeck));
  }
}

int indexOfAbility(Game g, ObjId id, bool Function(Ability) test) => g.parsed(id).abilities.indexWhere(test);

void main() {
  group('Reveal and play (CR 420.3, 417)', () {
    test('Rek’Sai, Swarm Queen: when she attacks, reveal 2, play a unit here, recycle the rest', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 3);
      final rek = g.addCard("Rek'Sai, Swarm Queen", 0, zone: Zone.board);
      final def = g.addCard('Void Hatchling', 1, zone: Zone.board, loc: 0); // 2 Might
      g.stackDeck(0, 'Incinerate', 1);
      g.stackDeck(0, 'Shipyard Skulker', 1); // {3} Chaos unit, on top
      final top = g.state.player(0).deck.take(2).toList();
      g.apply(MoveUnitsMove(0, [rek], 0));
      settle(g, pick: by({'reveal the top 2': [1], 'you may play one': [top.first], 'here at': [1]}));
      final skulker = g.state.obj(top.first);
      expect(skulker.zone, Zone.board);
      expect(skulker.loc, 0, reason: 'a unit may be played here');
      expect(g.state.player(0).deck.last, top[1], reason: 'the rest is recycled');
      expect(g.state.obj(def).zone, Zone.trash);
    });

    test('Rek’sai, Void Burrower: when you conquer, may exhaust it to reveal 2 and play one', () {
      final g = emptyGame();
      final legend = g.addCard("Rek'sai, Void Burrower", 0, zone: Zone.legend);
      g.addRunes(0, Domain.fury, 2);
      final u = g.addCard('Vanguard Sergeant', 0, zone: Zone.board);
      g.stackDeck(0, 'Shipyard Skulker', 1);
      g.stackDeck(0, 'Void Hatchling', 1); // {2}, on top
      final top = g.state.player(0).deck.first;
      g.apply(MoveUnitsMove(0, [u], 0));
      settle(g, pick: by({'exhaust me': [1], 'you may play one': [top]}));
      expect(g.state.bfs[0].controller, 0);
      expect(g.state.obj(legend).exhausted, isTrue);
      expect(g.state.obj(top).zone, Zone.board);
    });

    test('Void Hatchling: before revealing, look at the top card and you may recycle it', () {
      final g = emptyGame();
      g.addCard('Void Hatchling', 0, zone: Zone.board);
      g.addRunes(0, Domain.chaos, 3);
      final rek = g.addCard("Rek'Sai, Swarm Queen", 0, zone: Zone.board);
      g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 0);
      g.stackDeck(0, 'Incinerate', 2);
      g.stackDeck(0, 'Vanguard Sergeant', 1); // top: recycled by the Hatchling
      final sergeant = g.state.player(0).deck.first;
      final prompts = <String>[];
      g.apply(MoveUnitsMove(0, [rek], 0));
      settle(g, pick: (d) {
        prompts.add(d.prompt);
        if (d.prompt.contains('Recycle it before revealing')) return [1];
        if (d.prompt.contains('reveal the top 2')) return [1];
        return null;
      });
      expect(prompts.any((p) => p.contains('Vanguard Sergeant')), isTrue);
      expect(g.state.log.any((l) => l.text.contains('reveals Incinerate, Incinerate')), isTrue, reason: 'the Sergeant was recycled before the reveal');
      expect(g.state.player(0).deck, contains(sergeant));
    });
  });

  group('Resources (CR 165, 204.4)', () {
    test('Renata Glasc: near the Victory Score, Gold adds an additional {1}', () {
      final g = emptyGame();
      g.addCard('Renata Glasc, Chem-Baroness', 0, zone: Zone.legend);
      final gold = g.addCard('Gold', 0, zone: Zone.board);
      final i = indexOfAbility(g, gold, (a) => a is Activated);
      g.state.player(0).points = 2;
      g.apply(ActivateMove(0, gold, i));
      expect(g.state.player(0).energyPool, 0, reason: 'not within 3 points yet');
      final g2 = emptyGame();
      g2.addCard('Renata Glasc, Chem-Baroness', 0, zone: Zone.legend);
      final gold2 = g2.addCard('Gold', 0, zone: Zone.board);
      g2.state.player(0).points = 5;
      g2.apply(ActivateMove(0, gold2, i));
      expect(g2.state.player(0).anyPool, 1);
      expect(g2.state.player(0).energyPool, 1);
    });

    test('Renekton: its Energy pays only for units and activated abilities of units', () {
      final g = emptyGame();
      final ren = g.addCard('Renekton, Butcher of the Sands', 0, zone: Zone.legend);
      g.addRunes(0, Domain.fury, 2);
      final heap = g.addCard('Scrapheap', 0); // {2} gear
      final hatch = g.addCard('Void Hatchling', 0); // {2} unit
      g.apply(ActivateMove(0, ren, indexOfAbility(g, ren, (a) => a is Activated)));
      expect(g.state.player(0).runes, isEmpty, reason: '{A}{A} recycled both runes');
      expect(g.state.player(0).energyPool, 0);
      expect(g.whyNot(PlayMove(0, heap)), isNotNull, reason: 'not for a gear');
      expect(g.whyNot(PlayMove(0, hatch)), isNull);
      g.apply(PlayMove(0, hatch));
      settle(g);
      expect(g.state.obj(hatch).zone, Zone.board);
    });

    test('Threshold of the Gray: when combat starts here, the attacker and defender each add {1}', () {
      final g = emptyGame(battlefields: const ['Threshold of the Gray', 'Zaun Warrens']);
      final a = g.addCard('Vanguard Sergeant', 0, zone: Zone.board);
      g.addCard('Void Hatchling', 1, zone: Zone.board, loc: 0);
      g.apply(MoveUnitsMove(0, [a], 0));
      settle(g);
      expect(g.state.player(0).energyPool, 1);
      expect(g.state.player(1).energyPool, 1);
    });

    test('Sandstone Chimera: at a battlefield, players channel only 1 rune', () {
      final g = emptyGame();
      g.addCard('Sandstone Chimera', 0, zone: Zone.board, loc: 0);
      addRuneDeck(g, 1, 'Fury Rune', 5);
      g.state.turn = 3;
      g.apply(const EndTurnMove(0));
      settle(g);
      expect(g.state.active, 1);
      expect(g.state.player(1).runes, hasLength(1));
    });

    test('Sona, Harmonious: at a battlefield, ready 4 friendly runes at the end of your turn', () {
      final g = emptyGame();
      g.addCard('Sona, Harmonious', 0, zone: Zone.board, loc: 0);
      g.addRunes(0, Domain.calm, 5);
      for (final r in g.state.player(0).runes) {
        g.state.obj(r).exhausted = true;
      }
      g.apply(const EndTurnMove(0));
      settle(g);
      expect([for (final r in g.state.player(0).runes) if (!g.state.obj(r).exhausted) r], hasLength(4));
      // In base: nothing.
      final g2 = emptyGame();
      g2.addCard('Sona, Harmonious', 0, zone: Zone.board);
      g2.addRunes(0, Domain.calm, 2);
      for (final r in g2.state.player(0).runes) {
        g2.state.obj(r).exhausted = true;
      }
      g2.apply(const EndTurnMove(0));
      settle(g2);
      expect(g2.state.player(0).runes.every((r) => g2.state.obj(r).exhausted), isTrue);
    });
  });

  group('Countering, damage and choices', () {
    test('Riposte: counter a spell and give a friendly unit +{M} equal to its Energy cost', () {
      final g = emptyGame(active: 1);
      g.addRunes(1, Domain.order, 6);
      g.addRunes(0, Domain.body, 2);
      g.addRunes(0, Domain.order, 2);
      final mine = g.addCard('Vanguard Sergeant', 0, zone: Zone.board, loc: 0);
      final kill = g.addCard('Vengeance', 1); // {4}: kill a unit
      final riposte = g.addCard('Riposte', 0);
      g.apply(PlayMove(1, kill));
      if (g.pending != null) answer(g, [mine]);
      expect(g.toAct, 0);
      g.apply(PlayMove(0, riposte));
      settle(g, pick: by({'choose': [mine]}));
      expect(g.state.obj(mine).zone, Zone.board);
      expect(g.state.obj(kill).zone, Zone.trash);
      expect(g.might(mine), 4 + 4);
    });

    test('Shakedown: 6 damage unless its controller has you draw 2', () {
      for (final yes in [true, false]) {
        final g = emptyGame();
        g.addRunes(0, Domain.fury, 3);
        g.stackDeck(0, 'Incinerate', 3);
        final enemy = g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 1);
        final sd = g.addCard('Shakedown', 0);
        final hand = g.state.player(0).hand.length;
        g.apply(PlayMove(0, sd));
        settle(g, pick: by({'choose': [enemy], 'let A draw 2': [yes ? 1 : 0]}));
        if (yes) {
          expect(g.state.obj(enemy).zone, Zone.board);
          expect(g.state.player(0).hand.length, hand - 1 + 2);
        } else {
          expect(g.state.obj(enemy).zone, Zone.trash);
          expect(g.state.player(0).hand.length, hand - 1);
        }
      }
    });

    test('Stormbringer: a base unit’s Might to all enemy units at a battlefield, then it moves there', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 4);
      g.addRunes(0, Domain.body, 4);
      final u = g.addCard('Vanguard Sergeant', 0, zone: Zone.board); // 4 Might, in base
      final e1 = g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 1);
      final e2 = g.addCard('Void Hatchling', 1, zone: Zone.board, loc: 1);
      final far = g.addCard('Void Hatchling', 1, zone: Zone.board, loc: 0);
      final sb = g.addCard('Stormbringer', 0);
      g.apply(PlayMove(0, sb));
      settle(g, pick: (d) => d.kind == DecisionKind.option && d.prompt.contains('battlefield') ? [1] : (d.kind == DecisionKind.cards && d.options.contains(u) ? [u] : null));
      expect(g.state.obj(e1).zone, Zone.trash);
      expect(g.state.obj(e2).zone, Zone.trash);
      expect(g.state.obj(far).zone, Zone.board);
      expect(g.state.obj(u).loc, 1);
    });

    test('Twisted Fate, Gambler: the revealed rune’s domain decides (Fury: 2 and 1 here; Mind: draw)', () {
      final g = emptyGame();
      final tf = g.addCard('Twisted Fate, Gambler', 0, zone: Zone.board);
      addRuneDeck(g, 0, 'Fury Rune', 1);
      addRuneDeck(g, 0, 'Mind Rune', 1);
      final a = g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 0); // 3 Might
      final b = g.addCard('Void Hatchling', 1, zone: Zone.board, loc: 0); // 2 Might
      g.apply(MoveUnitsMove(0, [tf], 0));
      settle(g, pick: by({'deal 2': [b]}));
      expect(g.state.obj(b).zone, Zone.trash, reason: '2 to the Hatchling before combat');
      expect(g.state.player(0).runeDeck.map((r) => g.card(r).name).toList(), ['Mind Rune', 'Fury Rune'], reason: 'the Fury rune was recycled');
      expect(g.state.obj(a).zone, Zone.trash, reason: '1 + 4 combat damage');
      // Mind: draw 1.
      final g2 = emptyGame();
      final tf2 = g2.addCard('Twisted Fate, Gambler', 0, zone: Zone.board);
      addRuneDeck(g2, 0, 'Mind Rune', 1);
      g2.stackDeck(0, 'Incinerate', 1);
      g2.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 0);
      final hand = g2.state.player(0).hand.length;
      g2.apply(MoveUnitsMove(0, [tf2], 0));
      settle(g2);
      expect(g2.state.player(0).hand.length, hand + 1);
    });

    test('Tricksy Tentacles: enemy units with total Might 8 or less move to one location', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 5);
      final a = g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 0); // 3
      final b = g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 1); // 4
      final c = g.addCard('Sandstone Chimera', 1, zone: Zone.board); // 8, in base
      final t = g.addCard('Tricksy Tentacles', 0);
      g.apply(PlayMove(0, t));
      answer(g, [a, b]);
      answer(g, [0]); // their base
      settle(g);
      expect(g.state.obj(a).loc, base);
      expect(g.state.obj(b).loc, base);
      expect(g.state.obj(c).loc, base);
      // More than 8 total Might is refused.
      final g2 = emptyGame();
      g2.addRunes(0, Domain.calm, 5);
      final x = g2.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 0);
      final y = g2.addCard('Sandstone Chimera', 1, zone: Zone.board, loc: 1);
      final t2 = g2.addCard('Tricksy Tentacles', 0);
      g2.apply(PlayMove(0, t2));
      expect(() => answer(g2, [x, y]), throwsA(isA<RiftboundError>()));
    });

    test('Whirlwind and Ripper’s Bay: each player may return a unit; a unit leaving the Bay lets its owner pay {1} to channel', () {
      final g = emptyGame(battlefields: const ["Ripper's Bay", 'Zaun Warrens']);
      g.addRunes(0, Domain.chaos, 6);
      addRuneDeck(g, 0, 'Fury Rune', 2);
      final mine = g.addCard('Vanguard Sergeant', 0, zone: Zone.board, loc: 0);
      final theirs = g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 1);
      final w = g.addCard('Whirlwind', 0);
      g.apply(PlayMove(0, w));
      // Player 1 (the next player) returns player 0's unit at the Bay; player 0 returns player 1's.
      settle(g, pick: (d) {
        if (d.prompt.contains('return a unit')) return [d.player == 1 ? mine : theirs];
        if (d.prompt.contains('channel')) return [1];
        return null;
      });
      expect(g.state.obj(mine).zone, Zone.hand);
      expect(g.state.obj(theirs).zone, Zone.hand);
      // Whirlwind recycled 1 of the 6 runes; {1} exhausted one; 1 was channeled.
      expect(g.state.player(0).runes, hasLength(6));
      expect(g.state.log.any((l) => l.text == 'A channels 1 rune.'), isTrue);
    });
  });

  group('Triggers', () {
    test('Scrapheap: played, discarded or killed, draw 1', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 2);
      g.stackDeck(0, 'Incinerate', 5);
      final heap = g.addCard('Scrapheap', 0);
      final hand = g.state.player(0).hand.length;
      g.apply(PlayMove(0, heap));
      settle(g);
      expect(g.state.player(0).hand.length, hand, reason: 'played (−1), drew 1');
      // Discarded (paying Square Up's Repeat).
      final g2 = emptyGame();
      g2.addRunes(0, Domain.fury, 4);
      g2.stackDeck(0, 'Incinerate', 5);
      final unit = g2.addCard('Vanguard Sergeant', 0, zone: Zone.board, loc: 0);
      final heap2 = g2.addCard('Scrapheap', 0);
      final up = g2.addCard('Square Up', 0);
      g2.apply(PlayMove(0, up));
      settle(g2, pick: (d) => d.kind == DecisionKind.cards && d.options.contains(heap2) ? [heap2] : (d.kind == DecisionKind.cards && d.options.contains(unit) ? [unit] : null));
      expect(g2.state.obj(heap2).zone, Zone.trash);
      expect(g2.state.player(0).hand.length, 1, reason: 'Scrapheap drew 1 from the discard');
      expect(g2.state.obj(unit).kwMod[Kw.assault.index], 8, reason: 'Square Up repeated');
    });

    test('Shadow: played to a battlefield it enters ready; its ability stuns an enemy unit attacking here', () {
      final g = emptyGame();
      g.setControl(0, 0);
      g.addRunes(0, Domain.calm, 3);
      final shadow = g.addCard('Shadow', 0);
      g.apply(PlayMove(0, shadow));
      settle(g, pick: (d) => d.kind == DecisionKind.option ? [1] : null);
      expect(g.state.obj(shadow).loc, 0);
      expect(g.state.obj(shadow).exhausted, isFalse);
      // Player 1 attacks there: Shadow stuns the attacker.
      g.apply(const EndTurnMove(0));
      settle(g);
      g.addRunes(0, Domain.chaos, 2);
      final att = g.addCard('Vanguard Sergeant', 1, zone: Zone.board);
      g.apply(MoveUnitsMove(1, [att], 0));
      if (g.toAct == 1) g.apply(const PassMove(1));
      expect(g.toAct, 0);
      g.apply(ActivateMove(0, shadow, indexOfAbility(g, shadow, (a) => a is Activated)));
      settle(g, pick: by({'choose': [att]}));
      expect(g.state.obj(shadow).zone, Zone.board, reason: 'a stunned attacker deals no damage');
    });

    test('Shard of Undoing: a friendly unit dying in your Beginning Phase makes each opponent kill a unit', () {
      final g = emptyGame();
      g.addCard('Shard of Undoing', 0, zone: Zone.board);
      g.addCard('Sprite', 0, zone: Zone.board); // [Temporary]: dies as the turn begins
      final victim = g.addCard('Shipyard Skulker', 1, zone: Zone.board);
      g.apply(const EndTurnMove(0));
      settle(g);
      g.apply(const EndTurnMove(1));
      settle(g);
      expect(g.state.obj(victim).zone, Zone.trash);
    });

    test('Sprite Fountain: its Deathknell repeats its play effect', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 3);
      g.stackDeck(0, 'Incinerate', 4);
      g.stackDeck(1, 'Incinerate', 4);
      final f = g.addCard('Sprite Fountain', 0);
      g.apply(PlayMove(0, f));
      settle(g);
      int sprites() => g.units(player: 0).where((u) => g.card(u).name == 'Sprite').length;
      expect(sprites(), 1);
      g.apply(const EndTurnMove(0));
      settle(g);
      g.apply(const EndTurnMove(1));
      settle(g);
      expect(g.state.obj(f).zone, Zone.trash, reason: 'Temporary');
      expect(sprites(), 1, reason: 'the first Sprite died, the Deathknell made another');
    });

    test('Star Spring: the first non-token unit played here each turn lets them move another of theirs to base', () {
      final g = emptyGame(battlefields: const ['Star Spring', 'Zaun Warrens']);
      g.setControl(0, 0);
      g.addRunes(0, Domain.chaos, 6);
      final old = g.addCard('Vanguard Sergeant', 0, zone: Zone.board, loc: 0);
      final a = g.addCard('Shipyard Skulker', 0);
      final b = g.addCard('Shipyard Skulker', 0);
      g.apply(PlayMove(0, a));
      settle(g, pick: (d) => d.kind == DecisionKind.option ? [1] : (d.prompt.contains('move another') ? [old] : null));
      expect(g.state.obj(old).loc, base);
      final asked = <String>[];
      g.apply(PlayMove(0, b));
      settle(g, pick: (d) {
        asked.add(d.prompt);
        return d.kind == DecisionKind.option ? [1] : null;
      });
      expect(asked.any((p) => p.contains('move another')), isFalse, reason: 'only the first each turn');
    });

    test('Stealthy Pursuer: when a friendly unit moves from its location, it may move with it', () {
      final g = emptyGame();
      final p = g.addCard('Stealthy Pursuer', 0, zone: Zone.board);
      final u = g.addCard('Vanguard Sergeant', 0, zone: Zone.board);
      g.apply(MoveUnitsMove(0, [u], 1));
      settle(g, pick: by({'move with it': [1]}));
      expect(g.state.obj(p).loc, 1);
      expect(g.state.obj(p).exhausted, isFalse, reason: 'moved by its ability, not a Standard Move');
    });

    test('Sunken Temple: conquering here with a Mighty unit, you may pay {1} to draw 1', () {
      final g = emptyGame(battlefields: const ['Sunken Temple', 'Zaun Warrens']);
      g.addRunes(0, Domain.fury, 1);
      g.stackDeck(0, 'Incinerate', 2);
      final big = g.addCard('Swain, Visionary', 0, zone: Zone.board); // 6 Might
      final hand = g.state.player(0).hand.length;
      g.apply(MoveUnitsMove(0, [big], 0));
      settle(g, pick: by({'pay {1}': [1]}));
      expect(g.state.bfs[0].controller, 0);
      expect(g.state.player(0).hand.length, hand + 1);
      // Without a Mighty unit: no trigger.
      final g2 = emptyGame(battlefields: const ['Sunken Temple', 'Zaun Warrens']);
      g2.addRunes(0, Domain.fury, 1);
      g2.stackDeck(0, 'Incinerate', 2);
      final small = g2.addCard('Void Hatchling', 0, zone: Zone.board);
      g2.apply(MoveUnitsMove(0, [small], 0));
      settle(g2, pick: by({'pay {1}': [1]}));
      expect(g2.state.player(0).hand, isEmpty);
    });

    test('Swain, Visionary: after a non-token unit, gear and spell this turn, his conquer scores 1 more', () {
      Game play({required bool all}) {
        final g = emptyGame();
        g.addRunes(0, Domain.fury, 8);
        g.stackDeck(0, 'Incinerate', 3);
        final swain = g.addCard('Swain, Visionary', 0, zone: Zone.board);
        final target = g.addCard('Sandstone Chimera', 1, zone: Zone.board, loc: 0);
        if (all) {
          for (final k in ['Void Hatchling', 'Unlicensed Armory', 'Incinerate']) {
            final id = g.addCard(k, 0);
            g.apply(PlayMove(0, id));
            settle(g, pick: (d) => d.kind == DecisionKind.cards && d.options.contains(target) ? [target] : (d.kind == DecisionKind.option ? [0] : null));
          }
        }
        g.apply(MoveUnitsMove(0, [swain], 1));
        settle(g);
        return g;
      }

      expect(play(all: false).state.player(0).points, 1);
      expect(play(all: true).state.player(0).points, 2);
    });

    test('The Dreaming Tree: the first friendly unit there chosen by a spell each turn draws its chooser 1', () {
      final g = emptyGame(battlefields: const ['The Dreaming Tree', 'Zaun Warrens']);
      g.addRunes(0, Domain.calm, 4);
      g.stackDeck(0, 'Incinerate', 4);
      final u = g.addCard('Vanguard Sergeant', 0, zone: Zone.board, loc: 0);
      final d1 = g.addCard('Discipline', 0); // give a unit +2, draw 1
      final d2 = g.addCard('Discipline', 0);
      final hand = g.state.player(0).hand.length;
      g.apply(PlayMove(0, d1));
      settle(g, pick: by({'choose': [u]}));
      expect(g.state.player(0).hand.length, hand - 1 + 1 + 1, reason: 'Discipline draws 1, the Tree 1');
      g.apply(PlayMove(0, d2));
      settle(g, pick: by({'choose': [u]}));
      expect(g.state.player(0).hand.length, hand - 2 + 2 + 1, reason: 'only the first time each turn');
    });

    test('Vex, Apathetic: an opponent’s unit played while she’s at a battlefield is stunned and can’t move', () {
      final g = emptyGame(active: 1);
      g.addCard('Vex, Apathetic', 0, zone: Zone.board, loc: 0);
      g.addRunes(1, Domain.chaos, 3);
      final u = g.addCard('Shipyard Skulker', 1);
      g.apply(PlayMove(1, u));
      settle(g);
      expect(g.state.obj(u).stunned, isTrue);
      g.state.obj(u).exhausted = false;
      expect(g.moveDestinations(u), isEmpty);
    });

    test('Yuumi: when she attacks, another unit of yours there gets +3 {M} and [Tank]', () {
      final g = emptyGame();
      final y = g.addCard('Yuumi, Magical Cat', 0, zone: Zone.board);
      final u = g.addCard('Shipyard Skulker', 0, zone: Zone.board);
      g.addCard('Void Hatchling', 1, zone: Zone.board, loc: 0);
      g.apply(MoveUnitsMove(0, [y, u], 0));
      settle(g);
      expect(g.state.obj(u).mightMod, 3);
      expect(g.state.obj(u).kwMod[Kw.tank.index], 1);
    });

    test('Zed, Without a Sound: a Shadow Clone when he conquers; then he trades places with it', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 2);
      final zed = g.addCard('Zed, Without a Sound', 0, zone: Zone.board);
      g.apply(MoveUnitsMove(0, [zed], 0));
      settle(g);
      final clone = g.units(player: 0).firstWhere((u) => g.card(u).name == 'Shadow Clone');
      expect(g.state.obj(clone).loc, base);
      g.state.obj(zed).exhausted = false;
      g.apply(ActivateMove(0, zed, indexOfAbility(g, zed, (a) => a is Activated)));
      settle(g);
      expect(g.state.obj(zed).loc, base);
      expect(g.state.obj(clone).loc, 0);
    });

    test('Zilean, Time Mage: once each turn at a battlefield, a token unit comes with a copy', () {
      final g = emptyGame();
      g.addCard('Zilean, Time Mage', 0, zone: Zone.board, loc: 0);
      g.addRunes(0, Domain.mind, 6);
      final f1 = g.addCard('Sprite Fountain', 0);
      final f2 = g.addCard('Sprite Fountain', 0);
      g.apply(PlayMove(0, f1));
      settle(g, pick: by({'additional copy': [1]}));
      int sprites() => g.units(player: 0).where((u) => g.card(u).name == 'Sprite').length;
      expect(sprites(), 2);
      g.apply(PlayMove(0, f2));
      settle(g, pick: by({'additional copy': [1]}));
      expect(sprites(), 3, reason: 'once each turn');
    });
  });

  group('Replacements and passives (CR 367)', () {
    test('Soraka, Wanderer: a weaker friendly unit here is healed, exhausted and recalled instead of dying', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 8);
      g.addCard('Soraka, Wanderer', 0, zone: Zone.board, loc: 0); // 4 Might
      final weak = g.addCard('Shipyard Skulker', 0, zone: Zone.board, loc: 0); // 3
      final strong = g.addCard('Swain, Visionary', 0, zone: Zone.board, loc: 0); // 6
      final v1 = g.addCard('Vengeance', 0);
      g.apply(PlayMove(0, v1));
      settle(g, pick: by({'choose': [weak]}));
      expect(g.state.obj(weak).zone, Zone.board);
      expect(g.state.obj(weak).loc, base);
      expect(g.state.obj(weak).exhausted, isTrue);
      final v2 = g.addCard('Vengeance', 0);
      g.apply(PlayMove(0, v2));
      settle(g, pick: by({'choose': [strong]}));
      expect(g.state.obj(strong).zone, Zone.trash, reason: 'not less Might than Soraka');
    });

    test('Unlicensed Armory: the next time the chosen unit dies this turn, pay {R} to recall it exhausted', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 2);
      g.addRunes(0, Domain.order, 6);
      final armory = g.addCard('Unlicensed Armory', 0, zone: Zone.board);
      g.addCard('Incinerate', 0); // to discard
      final u = g.addCard('Vanguard Sergeant', 0, zone: Zone.board, loc: 0);
      g.apply(ActivateMove(0, armory, indexOfAbility(g, armory, (a) => a is Activated)));
      settle(g, pick: (d) => d.kind == DecisionKind.cards && d.options.contains(u) ? [u] : null);
      final v = g.addCard('Vengeance', 0);
      g.apply(PlayMove(0, v));
      settle(g, pick: by({'choose': [u], 'recall Vanguard Sergeant exhausted': [1]}));
      expect(g.state.obj(u).zone, Zone.board);
      expect(g.state.obj(u).loc, base);
      expect(g.state.obj(u).exhausted, isTrue);
    });

    test('Symbol of the Solari: a tie of your attack recalls ALL units', () {
      final g = emptyGame();
      g.setControl(0, 1);
      g.addCard('Symbol of the Solari', 0, zone: Zone.board);
      final a = g.addCard('Vanguard Sergeant', 0, zone: Zone.board);
      final d = g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 0);
      g.apply(MoveUnitsMove(0, [a], 0));
      // Both stunned: no combat damage, both still there (a tie).
      g.state.obj(a).stunned = true;
      g.state.obj(d).stunned = true;
      settle(g);
      expect(g.state.obj(a).loc, base);
      expect(g.state.obj(d).loc, base, reason: 'the defender is recalled too');
    });

    test('Syndra, Transcendent: in a showdown at her battlefield, your spells have [Repeat] {2}{P}', () {
      final g = emptyGame();
      g.addCard('Syndra, Transcendent', 0, zone: Zone.board, loc: 0);
      g.addRunes(0, Domain.fury, 2);
      g.addRunes(0, Domain.chaos, 3);
      final e1 = g.addCard('Void Hatchling', 1, zone: Zone.board, loc: 1);
      final e2 = g.addCard('Void Hatchling', 1, zone: Zone.board, loc: 1);
      final inc = g.addCard('Incinerate', 0); // [Action] Deal 2 to a unit at a battlefield
      g.state.showdown = Showdown(bf: 0, combat: false, attacker: 0, focus: 0);
      g.apply(PlayMove(0, inc));
      final chosen = <int>[];
      settle(g, pick: (d) {
        if (d.prompt.contains('to Repeat')) return [1];
        if (d.kind == DecisionKind.cards) {
          final x = d.options.firstWhere((o) => (o == e1 || o == e2) && !chosen.contains(o));
          chosen.add(x);
          return [x];
        }
        return null;
      });
      expect(g.state.obj(e1).zone, Zone.trash);
      expect(g.state.obj(e2).zone, Zone.trash, reason: 'repeated with its own choice');
    });

    test('The List: name a tag as it’s played; {E}: a unit with that tag gets -2 {M}', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 1);
      final pirate = g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 0); // Pirate
      final list = g.addCard('The List', 0);
      g.apply(PlayMove(0, list));
      final labels = g.pending!.decision.labels;
      answer(g, [labels.indexOf('Pirate')]);
      settle(g);
      g.apply(ActivateMove(0, list, indexOfAbility(g, list, (a) => a is Activated)));
      settle(g);
      expect(g.might(pirate), 1);
    });
  });
}
