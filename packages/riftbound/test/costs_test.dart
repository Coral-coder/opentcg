import 'package:riftbound/riftbound.dart';
import 'package:tcg_core/tcg_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Runes of [p] still ready.
int readyRunes(Game g, int p) => g.state.player(p).runes.where((r) => !g.state.obj(r).exhausted).length;

/// Answers every pending decision of [g] with its first option / yes, up to [limit] times.
void answerAll(Game g, {int limit = 10}) {
  for (var i = 0; i < limit && g.pending != null; i++) {
    final d = g.pending!.decision;
    answer(g, switch (d.kind) {
      DecisionKind.yesNo => const [1],
      DecisionKind.option => const [0],
      DecisionKind.cards => d.options.take(d.min == 0 ? 1 : d.min).toList(),
    });
  }
}

void main() {
  group('Modes (CR 355.3, 820.2)', () {
    test('355.3 the mode is chosen as the spell is played; only that mode resolves', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 2);
      final mine = g.addCard('Shipyard Skulker', 0, zone: Zone.board);
      final theirs = g.addCard('Vanguard Sergeant', 1, zone: Zone.board);
      final m = g.addCard('Mesmerize', 0);
      g.apply(PlayMove(0, m));
      expect(g.pending?.decision.kind, DecisionKind.option);
      expect(g.pending?.decision.labels, hasLength(2));
      answer(g, [1]); // Give an enemy unit -2 Might
      // The only enemy unit is chosen without asking.
      passAll(g);
      expect(g.might(theirs), 2);
      expect(g.state.obj(mine).zone, Zone.board);
    });

    test('355.8 a mode whose choices are impossible isn’t offered', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 2);
      final mine = g.addCard('Shipyard Skulker', 0, zone: Zone.board);
      final m = g.addCard('Mesmerize', 0);
      g.apply(PlayMove(0, m)); // no enemy unit: only "return a friendly unit"
      passAll(g);
      expect(g.state.obj(mine).zone, Zone.hand);
    });

    test('820.2.a each Repeat execution chooses again; "one you haven’t already chosen"', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 6);
      g.stackDeck(0, 'Shipyard Skulker', 3);
      final enemy = g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 0); // at a battlefield
      final cc = g.addCard('Curtain Call', 0); // {4}, Repeat {1} / {A} / {1}{A}
      g.apply(PlayMove(0, cc));
      answer(g, [1]); // Repeat {1}: yes
      answer(g, [0]); // Repeat {A}: no
      answer(g, [0]); // Repeat {1}{A}: no
      // First execution: Draw 1; second: the same mode isn't offered again.
      expect(g.pending?.decision.labels.first, startsWith('Draw'));
      answer(g, [0]);
      expect(g.pending?.decision.labels, isNot(contains(startsWith('Draw'))));
      answer(g, [0]); // Deal 2 to a unit at a battlefield (the enemy, only choice)
      passAll(g);
      expect(g.state.player(0).hand, hasLength(1));
      expect(g.state.obj(enemy).damage, 2);
    });

    test('820.2.a Rocket Barrage may choose the same mode twice with different targets', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 10);
      final a = g.addCard('Gold', 1, zone: Zone.board);
      final b = g.addCard('Gold', 1, zone: Zone.board);
      final rb = g.addCard('Rocket Barrage', 0);
      g.apply(PlayMove(0, rb));
      answer(g, [1]); // pay Repeat
      // Deal 4 to a unit in a base has no target, so only "Kill a gear" is offered: it's not asked.
      answer(g, [a]);
      answer(g, [b]);
      passAll(g);
      expect(g.state.obj(a).zone, Zone.gone);
      expect(g.state.obj(b).zone, Zone.gone);
    });

    test('Flurry of Feathers: Counter keeps its own slot apart from the mode', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 6);
      g.addRunes(1, Domain.fury, 5);
      final rocket = g.addCard('Super Mega Death Rocket!', 1);
      final target = g.addCard('Shipyard Skulker', 0, zone: Zone.board);
      final flurry = g.addCard('Flurry of Feathers', 0);
      g.state.active = 1;
      g.apply(PlayMove(1, rocket));
      g.apply(PlayMove(0, flurry));
      expect(g.pending?.decision.kind, DecisionKind.option);
      answer(g, [0]); // Counter a spell (the Rocket, the only one)
      passAll(g);
      expect(g.state.obj(rocket).zone, Zone.trash);
      expect(g.state.obj(target).damage, 0);
    });

    test('Udyr: "choose one you’ve not chosen this turn" — a mode used is gone until next turn', () {
      final g = emptyGame();
      final u = g.addCard('Udyr, Wildman', 0, zone: Zone.board, exhausted: true);
      g.state.obj(u).buffed = true;
      final i = g.parsed(u).abilities.indexWhere((a) => a is Activated);
      g.apply(ActivateMove(0, u, i));
      final labels = g.pending!.decision.labels;
      answer(g, [labels.indexWhere((l) => l.startsWith('Ready me'))]);
      passAll(g);
      expect(g.state.obj(u).exhausted, isFalse);
      expect(g.state.obj(u).buffed, isFalse, reason: 'Spend my buff');
      // Only "Give me [Ganking]" is left that can be chosen (no unit at a battlefield): it's taken
      // without asking.
      g.state.obj(u).buffed = true;
      g.apply(ActivateMove(0, u, i));
      expect(g.pending, isNull);
      passAll(g);
      expect(g.hasKw(u, Kw.ganking), isTrue);
    });

    test('Jayce, Hammer in Hand: "When I become ready" triggers as the turn awakens (CR 315.1)', () {
      final g = emptyGame();
      final j = g.addCard('Jayce, Hammer in Hand', 0, zone: Zone.board, exhausted: true);
      g.apply(const EndTurnMove(0));
      g.apply(const EndTurnMove(1));
      expect(g.pending?.decision.kind, DecisionKind.option);
      answer(g, [2]); // Ganking
      passAll(g);
      expect(g.hasKw(j, Kw.ganking), isTrue);
    });
  });

  group('Additional costs (CR 204.2, 355.1.a, 356.2, 357.2)', () {
    test('356.2.b an optional additional cost; "if you paid the additional cost" (CR 383.2.a.1)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 4);
      final enemy = g.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 0);
      final cadet = g.addCard('Blast Corps Cadet', 0); // {2}, may pay {1}{R}
      g.apply(PlayMove(0, cadet));
      expect(g.pending?.decision.prompt, contains('additional cost'));
      answer(g, [1]);
      passAll(g);
      expect(g.state.obj(enemy).damage, 2);
      expect(g.state.player(0).runes, hasLength(3), reason: '{3} and a Fury Power: one rune recycled');

      final g2 = emptyGame();
      g2.addRunes(0, Domain.fury, 4);
      final e2 = g2.addCard('Vanguard Sergeant', 1, zone: Zone.board, loc: 0);
      g2.apply(PlayMove(0, g2.addCard('Blast Corps Cadet', 0)));
      answer(g2, [0]);
      passAll(g2);
      expect(g2.state.obj(e2).damage, 0);
      expect(g2.state.chain, isEmpty);
    });

    test('356.2.a.1 a mandatory additional cost: Cruel Patron needs a friendly unit to kill', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 4);
      final cp = g.addCard('Cruel Patron', 0);
      expect(g.whyNot(PlayMove(0, cp)), isNotNull);
      final poro = g.addCard('Shipyard Skulker', 0, zone: Zone.board);
      g.apply(PlayMove(0, cp));
      expect(g.state.obj(poro).zone, Zone.trash);
      expect(g.state.obj(cp).zone, Zone.board);
    });

    test('356.4 a discount from an additional cost: Brazen Buccaneer, discarding, costs {4}', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 4);
      final junk = g.addCard('Shipyard Skulker', 0);
      final bb = g.addCard('Brazen Buccaneer', 0); // {6}
      expect(g.whyNot(PlayMove(0, bb)), isNull, reason: 'affordable only by discarding');
      g.apply(PlayMove(0, bb));
      // The discard is the only way to pay, so it isn't optional now (CR 357.3); the card is
      // the only one to discard.
      expect(g.state.obj(junk).zone, Zone.trash);
      expect(g.state.obj(bb).zone, Zone.board);
      expect(readyRunes(g, 0), 0);
    });

    test('356.1.b Call to Glory: spend a buff and its cost is ignored', () {
      final g = emptyGame();
      final u = g.addCard('Shipyard Skulker', 0, zone: Zone.board);
      g.state.obj(u).buffed = true;
      final cg = g.addCard('Call to Glory', 0); // {3}
      g.apply(PlayMove(0, cg));
      answerAll(g);
      passAll(g);
      expect(g.state.obj(u).buffed, isFalse);
      expect(g.might(u), 6, reason: '+3 this turn, the buff spent');
    });

    test('Commander Ledros: kill any number of friendly units, {Y} less each', () {
      final g = emptyGame();
      // Fury runes pay the {6}; no Order Power at all, so all four {Y} must be discounted.
      g.addRunes(0, Domain.fury, 6);
      final a = g.addCard('Shipyard Skulker', 0, zone: Zone.board);
      final b = g.addCard('Shipyard Skulker', 0, zone: Zone.board);
      final c = g.addCard('Shipyard Skulker', 0, zone: Zone.board);
      final l = g.addCard('Commander Ledros', 0); // {6} + 4 Order
      expect(g.whyNot(PlayMove(0, l)), isNotNull, reason: 'three units can only take off {Y}{Y}{Y}');
      final d = g.addCard('Shipyard Skulker', 0, zone: Zone.board);
      expect(g.whyNot(PlayMove(0, l)), isNull);
      // All four must be killed: with only four to choose from, that isn't asked.
      g.apply(PlayMove(0, l));
      expect(g.state.obj(l).zone, Zone.board);
      expect([a, b, c, d].every((u) => g.state.obj(u).zone == Zone.trash), isTrue);
    });

    test('Atakhan: the killed unit’s costs come off (CR 206)', () {
      final g = emptyGame();
      // {10} + 3 Order can't be paid with 7 runes; killing a {4} unit makes it {6} + 3 Order.
      g.addRunes(0, Domain.order, 7);
      final big = g.addCard('Vanguard Sergeant', 0, zone: Zone.board); // {4}
      final at = g.addCard('Atakhan', 0);
      g.apply(PlayMove(0, at)); // the kill is the only way to pay, with the only unit there is
      expect(g.state.obj(at).zone, Zone.board);
      expect(g.state.obj(big).zone, Zone.trash);
    });

    test('Meditation: "If you do, draw 2. Otherwise, draw 1."', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 2);
      g.stackDeck(0, 'Shipyard Skulker', 3);
      g.addCard('Shipyard Skulker', 0, zone: Zone.board);
      g.apply(PlayMove(0, g.addCard('Meditation', 0)));
      answer(g, [1]);
      passAll(g);
      expect(g.state.player(0).hand, hasLength(2));
      final g2 = emptyGame();
      g2.addRunes(0, Domain.calm, 2);
      g2.stackDeck(0, 'Shipyard Skulker', 3);
      g2.addCard('Shipyard Skulker', 0, zone: Zone.board);
      g2.apply(PlayMove(0, g2.addCard('Meditation', 0)));
      answer(g2, [0]);
      passAll(g2);
      expect(g2.state.player(0).hand, hasLength(1));
    });

    test('Ruthless Strike: 5 damage instead of 3 with the cost paid', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 3);
      g.addCard('Shipyard Skulker', 0);
      final enemy = g.addCard('Playful Phantom', 1, zone: Zone.board, loc: 0);
      g.apply(PlayMove(0, g.addCard('Ruthless Strike', 0)));
      answer(g, [1]); // discard 1 (the only other card)
      passAll(g);
      expect(g.state.obj(enemy).zone, Zone.trash, reason: '5 damage kills a 5 Might unit');
    });
  });

  group('Cost changes (CR 356.3–356.6)', () {
    test('356.4.e Battering Ram: {1} less per card played this turn, to a minimum of {1}', () {
      final g = emptyGame();
      g.state.player(0).playedThisTurn = 9;
      g.addRunes(0, Domain.fury, 1);
      final r = g.addCard('Battering Ram', 0);
      expect(g.playCost(0, r).energy, 1);
      g.apply(PlayMove(0, r));
      expect(g.state.obj(r).zone, Zone.board);
    });

    test('356.4.g variable discounts: Rhasa, Production Surge, Find Your Center', () {
      final g = emptyGame();
      for (var i = 0; i < 4; i++) {
        g.addCard('Shipyard Skulker', 0, zone: Zone.trash);
      }
      expect(g.playCost(0, g.addCard('Rhasa the Sunderer', 0)).energy, 6);
      final ps = g.addCard('Production Surge', 0);
      expect(g.playCost(0, ps).energy, 4);
      g.addCard('Mega-Mech', 0, zone: Zone.board);
      expect(g.playCost(0, ps).energy, 2);
      final fyc = g.addCard('Find Your Center', 0);
      expect(g.playCost(0, fyc).energy, 3);
      g.state.player(1).points = 5;
      expect(g.playCost(0, fyc).energy, 1);
    });

    test('Monch costs {2} less and enters ready while an opponent has a stunned unit', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 4);
      final m = g.addCard('Monch', 0); // {6}
      expect(g.whyNot(PlayMove(0, m)), isNotNull);
      final e = g.addCard('Shipyard Skulker', 1, zone: Zone.board);
      g.state.obj(e).stunned = true;
      g.apply(PlayMove(0, m));
      expect(g.state.obj(m).exhausted, isFalse);
    });

    test('other cards: Herald of Scales (Dragons), Eager Apprentice, Raging Firebrand, Vaults of Helia', () {
      final g = emptyGame();
      final drake = g.addCard('Mountain Drake', 0); // {9} Dragon
      expect(g.playCost(0, drake).energy, 9);
      g.addCard('Herald of Scales', 0, zone: Zone.board);
      expect(g.playCost(0, drake).energy, 7);
      final rocket = g.addCard('Super Mega Death Rocket!', 0); // {4}
      final ea = g.addCard('Eager Apprentice', 0, zone: Zone.board);
      expect(g.playCost(0, rocket).energy, 4, reason: 'only while it is at a battlefield');
      g.state.obj(ea).loc = 0;
      expect(g.playCost(0, rocket).energy, 3);
      // Discounts apply in the order that helps most: Eager Apprentice's minimum is its own
      // (CR 356.4.d–e), so {4} → {3} → {0}.
      g.state.marks['t:x:0:nextSpell'] = 5;
      expect(g.playCost(0, rocket).energy, 0);
      g.state.marks['t:x:0:unitsMore'] = 1;
      expect(g.playCost(0, drake).energy, 8);
    });

    test('Ornn’s Forge: the first friendly non-token gear each turn costs {1} less', () {
      final g = emptyGame(battlefields: const ['Ornn\'s Forge', 'Zaun Warrens']);
      g.setControl(0, 0);
      final gear = g.addCard('Garbage Grabber', 0); // {2}
      expect(g.playCost(0, gear).energy, 1);
      g.state.marks['t:x:0:gearPlayed'] = 1;
      expect(g.playCost(0, gear).energy, 2);
    });

    test('Sky Splitter costs {1} less per Might of your mightiest unit', () {
      final g = emptyGame();
      final s = g.addCard('Sky Splitter', 0); // {8}
      g.addCard('Playful Phantom', 0, zone: Zone.board); // 5 Might
      expect(g.playCost(0, s).energy, 3);
    });
  });

  group('Alternative costs and playing from elsewhere (CR 356.1.a, 420.3)', () {
    test('Jhin, Meticulous Killer: for {B} once you’ve spent {4} on a spell this turn', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 1);
      final j = g.addCard('Jhin, Meticulous Killer', 0); // {4}
      expect(g.whyNot(PlayMove(0, j)), isNotNull);
      g.state.marks['t:x:0:spellSpent'] = 4;
      g.apply(PlayMove(0, j));
      expect(g.state.obj(j).zone, Zone.board);
    });

    test('Undying Legion: [Legion] — play me from your trash for {3}{R}', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 4);
      final u = g.addCard('Undying Legion', 0, zone: Zone.trash);
      expect(g.legalMoves(0).whereType<PlayMove>().any((m) => m.card == u), isFalse, reason: 'Legion: no card played yet');
      g.state.player(0).playedThisTurn = 1;
      expect(g.legalMoves(0).whereType<PlayMove>().any((m) => m.card == u), isTrue);
      g.apply(PlayMove(0, u));
      expect(g.state.obj(u).zone, Zone.board);
      expect(g.state.player(0).trash, isEmpty);
    });

    test('The Harrowing plays a unit from the trash ignoring its Energy cost (CR 356.1.b.2)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 8);
      final big = g.addCard('Mega-Mech', 0, zone: Zone.trash); // {7}
      g.apply(PlayMove(0, g.addCard('The Harrowing', 0)));
      passAll(g);
      answerAll(g);
      expect(g.state.obj(big).zone, Zone.board);
    });

    test('Fizz, Trickster plays a spell from the trash, then it is recycled', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 5);
      final strike = g.addCard('Ruthless Strike', 0, zone: Zone.trash); // {3}: Energy {3} or less
      g.addCard('Super Mega Death Rocket!', 0, zone: Zone.trash); // {4}: too dear
      final enemy = g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 0);
      g.apply(PlayMove(0, g.addCard('Fizz, Trickster', 0)));
      answer(g, [1]); // play a spell from the trash: Ruthless Strike, the only one
      passAll(g); // nothing to discard for its optional cost; the enemy is the only target
      expect(g.state.obj(enemy).zone, Zone.trash);
      expect(g.state.obj(strike).zone, Zone.mainDeck, reason: 'recycled after it was played');
    });

    test('Death from Below: a small enough unit lets it be played again for {A}', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 6);
      final a = g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 0);
      final b = g.addCard('Shipyard Skulker', 1, zone: Zone.board, loc: 1);
      final dfb = g.addCard('Death from Below', 0);
      g.apply(PlayMove(0, dfb));
      answer(g, [a]);
      passAll(g);
      expect(g.pending?.decision.prompt, contains('again'));
      answer(g, [1]);
      passAll(g);
      expect(g.state.obj(a).zone, Zone.trash);
      expect(g.state.obj(b).zone, Zone.trash);
    });

    test('Immortal Phoenix triggers from the trash when you kill a unit with a spell (CR 383.2.c.1)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 8);
      final ph = g.addCard('Immortal Phoenix', 0, zone: Zone.trash);
      final enemy = g.addCard('Shipyard Skulker', 1, zone: Zone.board);
      g.apply(PlayMove(0, g.addCard('Super Mega Death Rocket!', 0)));
      passAll(g);
      expect(g.state.obj(enemy).zone, Zone.trash);
      answerAll(g);
      passAll(g);
      expect(g.state.obj(ph).zone, Zone.board);
    });
  });

  group('Counters and new choices (CR 206, 426, 750)', () {
    test('Defy counters only spells with printed cost {4} and one Power or less (CR 206)', () {
      final g = emptyGame(active: 1);
      g.addRunes(1, Domain.fury, 10);
      g.addRunes(0, Domain.calm, 2);
      final rocket = g.addCard('Super Mega Death Rocket!', 1);
      g.addCard('Shipyard Skulker', 0, zone: Zone.board);
      final defy = g.addCard('Defy', 0);
      g.apply(PlayMove(1, rocket));
      g.apply(PlayMove(0, defy));
      passAll(g);
      expect(g.state.obj(rocket).zone, Zone.trash);
      expect(g.state.player(0).trash, contains(defy));
    });

    test('Rebuttal: pay {A} to take control of a spell and make new choices', () {
      final g = emptyGame(active: 1);
      g.addRunes(1, Domain.fury, 10);
      g.addRunes(0, Domain.mind, 4);
      final mine = g.addCard('Shipyard Skulker', 0, zone: Zone.board);
      final theirs = g.addCard('Vanguard Sergeant', 1, zone: Zone.board);
      final rocket = g.addCard('Super Mega Death Rocket!', 1);
      final rebuttal = g.addCard('Rebuttal', 0);
      g.apply(PlayMove(1, rocket));
      answer(g, [mine]);
      g.apply(PlayMove(0, rebuttal));
      passAll(g);
      answer(g, [1]); // pay {A}
      answer(g, [1]); // new choices
      answer(g, [theirs]);
      passAll(g);
      expect(g.state.obj(theirs).zone, Zone.trash);
      expect(g.state.obj(mine).zone, Zone.board);
    });
  });

  group('Other effects of the family', () {
    test('Clash of Giants: two units deal damage equal to their Mights to each other', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 8);
      final a = g.addCard('Shipyard Skulker', 1, zone: Zone.board);
      final b = g.addCard('Playful Phantom', 1, zone: Zone.board);
      g.apply(PlayMove(0, g.addCard('Clash of Giants', 0)));
      answer(g, [a]);
      passAll(g);
      expect(g.state.obj(a).zone, Zone.trash);
      expect(g.state.obj(b).damage, 3);
    });

    test('Dr. Mundo: +1 Might per card in your trash; recycles 3 at the start of your turn', () {
      final g = emptyGame();
      final m = g.addCard('Dr. Mundo, Expert', 0, zone: Zone.board);
      for (var i = 0; i < 4; i++) {
        g.addCard('Shipyard Skulker', 0, zone: Zone.trash);
      }
      expect(g.might(m), 10);
      g.apply(const EndTurnMove(0));
      g.apply(const EndTurnMove(1));
      answerAll(g);
      passAll(g);
      expect(g.state.player(0).trash, hasLength(1));
    });

    test('Temporal Portal: the next spell gets Repeat equal to its cost', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 12);
      final tp = g.addCard('Temporal Portal', 0, zone: Zone.board);
      g.apply(ActivateMove(0, tp, g.parsed(tp).abilities.indexWhere((a) => a is Activated)));
      passAll(g);
      final a = g.addCard('Shipyard Skulker', 1, zone: Zone.board);
      final b = g.addCard('Vanguard Sergeant', 1, zone: Zone.board);
      g.apply(PlayMove(0, g.addCard('Super Mega Death Rocket!', 0)));
      answer(g, [1]); // Repeat
      answer(g, [a]);
      answer(g, [b]);
      passAll(g);
      expect(g.state.obj(a).zone, Zone.trash);
      expect(g.state.obj(b).zone, Zone.trash);
    });

    test('Decree of Insight ignores Deflect, and chooses only a unit of the Body domain', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 1);
      final body = g.addCard('Mountain Drake', 1, zone: Zone.board); // Body
      g.addCard('Shipyard Skulker', 1, zone: Zone.board); // Chaos
      g.apply(PlayMove(0, g.addCard('Decree of Insight', 0)));
      passAll(g);
      expect(g.might(body), 5);
    });

    test('Void Rush plays one revealed card cheaper and draws the rest', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 4);
      g.stackDeck(0, 'Vanguard Sergeant', 1);
      g.stackDeck(0, 'Shipyard Skulker', 1);
      g.apply(PlayMove(0, g.addCard('Void Rush', 0))); // {2} + 1
      passAll(g);
      expect(g.pending?.decision.prompt, startsWith('Play which'));
      final skulker = g.pending!.decision.options.firstWhere((id) => g.nameOf(id) == 'Shipyard Skulker');
      answer(g, [skulker]); // {3} - {2}
      passAll(g);
      expect(g.state.obj(skulker).zone, Zone.board);
      expect(g.state.player(0).hand.map(g.nameOf), ['Vanguard Sergeant']);
    });
  });

  group('More additional costs (CR 356.2, 356.4.c, 359.2.b)', () {
    test('Kraken Hunter: each buff spent takes off one {O}', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 3); // {3}; no Body Power at all
      final a = g.addCard('Shipyard Skulker', 0, zone: Zone.board)..toString();
      final b = g.addCard('Shipyard Skulker', 0, zone: Zone.board);
      g.state.obj(a).buffed = true;
      final k = g.addCard('Kraken Hunter', 0); // {3} + 2 Body
      expect(g.whyNot(PlayMove(0, k)), isNotNull, reason: 'one buff takes off only one {O}');
      g.state.obj(b).buffed = true;
      g.apply(PlayMove(0, k));
      answerAll(g);
      expect(g.state.obj(k).zone, Zone.board);
      expect(g.state.obj(a).buffed || g.state.obj(b).buffed, isFalse);
    });

    test('Sea Monkey / Zed: "if you paid the additional cost" triggers only when paid', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 3);
      final m = g.addCard('Sea Monkey', 0);
      g.apply(PlayMove(0, m));
      answer(g, [1]);
      passAll(g);
      expect(g.state.obj(m).buffed, isTrue);
      final g2 = emptyGame();
      g2.addRunes(0, Domain.fury, 5);
      g2.addCard('Shipyard Skulker', 0);
      g2.apply(PlayMove(0, g2.addCard('Zed, From the Shadows', 0)));
      answer(g2, [1]); // discard 1 (the only other card)
      passAll(g2);
      expect(g2.units(player: 0).map(g2.nameOf), contains('Shadow Clone'));
    });

    test('Clockwork Keeper: "If you do, draw 1" as it is played; Crescent Guardian enters ready', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 3);
      g.stackDeck(0, 'Shipyard Skulker', 1);
      g.apply(PlayMove(0, g.addCard('Clockwork Keeper', 0)));
      answer(g, [1]);
      expect(g.state.player(0).hand, hasLength(1));
      final g2 = emptyGame();
      g2.addRunes(0, Domain.chaos, 5);
      final cg = g2.addCard('Crescent Guardian', 0);
      g2.state.marks['t:x:0:spells'] = 1;
      g2.apply(PlayMove(0, cg));
      answer(g2, [1]);
      expect(g2.state.obj(cg).exhausted, isFalse);
    });

    test('Legion Quartermaster returns a friendly gear; Sacrifice needs a Mighty unit', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 3);
      final lq = g.addCard('Legion Quartermaster', 0);
      expect(g.whyNot(PlayMove(0, lq)), isNotNull);
      final gear = g.addCard('Garbage Grabber', 0, zone: Zone.board);
      g.apply(PlayMove(0, lq));
      expect(g.state.obj(gear).zone, Zone.hand);
      final g2 = emptyGame();
      g2.addRunes(0, Domain.order, 1);
      final s = g2.addCard('Sacrifice', 0);
      g2.addCard('Shipyard Skulker', 0, zone: Zone.board);
      expect(g2.whyNot(PlayMove(0, s)), isNotNull, reason: 'a 3 Might unit isn’t Mighty (CR 708)');
      g2.addCard('Playful Phantom', 0, zone: Zone.board);
      expect(g2.whyNot(PlayMove(0, s)), isNull);
    });

    test('Heedless Resurrection plays a unit no dearer than the killed one, free', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 3);
      final sac = g.addCard('Vanguard Sergeant', 0, zone: Zone.board); // {4}
      g.addCard('Mega-Mech', 0, zone: Zone.trash); // {7}: too dear
      final back = g.addCard('Shipyard Skulker', 0, zone: Zone.trash); // {3}
      g.apply(PlayMove(0, g.addCard('Heedless Resurrection', 0)));
      passAll(g);
      answerAll(g);
      expect(g.state.obj(sac).zone, Zone.trash);
      expect(g.state.player(0).trash.where((id) => g.state.obj(id).zone == Zone.board), isEmpty);
      expect([back, sac].any((id) => g.state.obj(id).zone == Zone.board), isTrue);
    });

    test('Rampage: +2 if paid, then the two fight', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 5);
      final mine = g.addCard('Shipyard Skulker', 0, zone: Zone.board); // 3
      final theirs = g.addCard('Playful Phantom', 1, zone: Zone.board); // 5
      g.apply(PlayMove(0, g.addCard('Rampage', 0)));
      answer(g, [1]);
      passAll(g);
      expect(g.state.obj(theirs).zone, Zone.trash, reason: '5 damage from a 5 Might unit');
      expect(g.state.obj(mine).zone, Zone.trash, reason: '5 damage to a 5 Might unit');
    });

    test('Dragon Roost: pay {A}{A} more to play a Dragon there', () {
      final g = emptyGame(battlefields: const ['Dragon Roost', 'Zaun Warrens']);
      g.addRunes(0, Domain.body, 11);
      final d = g.addCard('Mountain Drake', 0);
      g.apply(PlayMove(0, d));
      expect(g.pending?.decision.prompt, contains('Dragon Roost'));
      answer(g, [1]);
      expect(g.state.obj(d).loc, 0);
    });

    test('Ezreal makes optional additional costs {1} or {A} cheaper (CR 356.4.c)', () {
      final g = emptyGame();
      g.addCard('Ezreal, Prodigy', 0, zone: Zone.board);
      g.addRunes(0, Domain.body, 2);
      final m = g.addCard('Sea Monkey', 0); // {2}, may pay {1}
      g.apply(PlayMove(0, m));
      expect(g.pending?.decision.prompt, contains('additional cost'), reason: 'its {1} is free now');
      answer(g, [1]);
      passAll(g);
      expect(g.state.obj(m).buffed, isTrue);
    });
  });

  group('Cost changes from other cards', () {
    test('Irelia: your spells that choose her cost {1} or {A} less (decided once chosen)', () {
      final g = emptyGame();
      final ir = g.addCard('Irelia, Graceful', 0, zone: Zone.board);
      g.addRunes(0, Domain.order, 2);
      final cg = g.addCard('Call to Glory', 0); // {3}: {2} when it chooses Irelia
      g.apply(PlayMove(0, cg)); // nothing to spend a buff from; Irelia is the only unit
      passAll(g);
      expect(g.might(ir), 7);
      expect(readyRunes(g, 0), 0);
    });

    test('Irelia (CR 356): only targets that leave the spell affordable are offered', () {
      final g = emptyGame();
      final ir = g.addCard('Irelia, Graceful', 0, zone: Zone.board);
      final poro = g.addCard('Daring Poro', 0, zone: Zone.board);
      g.addRunes(0, Domain.order, 2);
      final cg = g.addCard('Call to Glory', 0);
      expect(g.whyNot(PlayMove(0, cg)), isNull);
      // With two runes only Irelia keeps it at {2}: the Poro isn't offered.
      g.apply(PlayMove(0, cg));
      expect(g.pending, isNull);
      passAll(g);
      expect(g.might(ir), 7);
      expect(g.might(poro), g.card(poro).might!);
      // With three runes either may be chosen.
      final g2 = emptyGame();
      g2.addCard('Irelia, Graceful', 0, zone: Zone.board);
      final poro2 = g2.addCard('Daring Poro', 0, zone: Zone.board);
      g2.addRunes(0, Domain.order, 3);
      g2.apply(PlayMove(0, g2.addCard('Call to Glory', 0)));
      expect(g2.pending?.decision.options, hasLength(2));
      answer(g2, [poro2]);
      passAll(g2);
      expect(g2.might(poro2), g2.card(poro2).might! + 3);
      expect(readyRunes(g2, 0), 0);
    });

    test('Mystic Vortex: Reactions cost {A} more in showdowns there', () {
      final g = emptyGame(battlefields: const ['Mystic Vortex', 'Zaun Warrens']);
      final m = g.addCard('Meditation', 0);
      expect(g.playCost(0, m).power, isEmpty);
      g.state.showdown = Showdown(bf: 0, combat: false, attacker: 0, focus: 0);
      expect(g.playCost(0, m).power, hasLength(1));
    });

    test('Shadowblade Lurker, Spoils of War, Needlessly Large Yordle, Plaza Guardian, Jaull-Fish', () {
      final g = emptyGame();
      g.addCard('Shadowblade Lurker', 0, zone: Zone.trash);
      expect(g.playCost(0, g.addCard('Shadowblade Lurker', 0)).energy, 3);
      final sw = g.addCard('Spoils of War', 0);
      expect(g.playCost(0, sw).energy, 4);
      final e = g.addCard('Shipyard Skulker', 1, zone: Zone.board);
      g.state.obj(e).damage = 9;
      g.settleForTest();
      expect(g.playCost(0, sw).energy, 2);
      final ny = g.addCard('Needlessly Large Yordle', 0);
      g.state.marks['t:x:0:holdPts'] = 2;
      final c = g.playCost(0, ny);
      expect(c.energy, 6);
      expect(c.power, hasLength(1));
      g.addCard('Garbage Grabber', 0, zone: Zone.board);
      expect(g.playCost(0, g.addCard('Plaza Guardian', 0)).energy, 9);
      g.addCard('Playful Phantom', 0, zone: Zone.board);
      expect(g.playCost(0, g.addCard('Jaull-Fish', 0)).energy, 5);
    });

    test('Void Drone costs {2} less only when played from elsewhere', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 8);
      final vd = g.addCard('Void Drone', 0, zone: Zone.trash);
      expect(g.playCost(0, g.addCard('Void Drone', 0)).energy, 3);
      g.apply(PlayMove(0, g.addCard('The Harrowing', 0)));
      passAll(g);
      answerAll(g);
      expect(g.state.obj(vd).zone, Zone.board);
    });

    test('Lillia: the Sprite ability costs {1} less per friendly Temporary unit', () {
      final g = emptyGame();
      final l = g.addCard('Lillia, Bashful Bloom', 0, zone: Zone.legend);
      g.addRunes(0, Domain.calm, 3);
      final i = g.parsed(l).abilities.indexWhere((a) => a is Activated);
      expect(g.whyNot(ActivateMove(0, l, i)), isNotNull);
      g.addCard('Sprite', 0, zone: Zone.board);
      g.apply(ActivateMove(0, l, i));
      passAll(g);
      expect(g.units(player: 0).where((u) => g.nameOf(u) == 'Sprite'), hasLength(2));
    });
  });

  group('Triggers of this family', () {
    test('Lux, Yordle Explorer, Nasus: "when you play" with costs (printed costs, CR 206)', () {
      final g = emptyGame();
      g.addCard('Lux, Lady of Luminosity', 0, zone: Zone.legend);
      g.addRunes(0, Domain.fury, 10);
      g.stackDeck(0, 'Shipyard Skulker', 2);
      g.addCard('Shipyard Skulker', 1, zone: Zone.board);
      g.apply(PlayMove(0, g.addCard('Firestorm', 0))); // {6}
      passAll(g);
      expect(g.state.player(0).hand, hasLength(1), reason: 'Lux drew 1');
      final g2 = emptyGame();
      g2.addCard('Nasus, Curator of the Sands', 0, zone: Zone.legend);
      g2.addRunes(0, Domain.body, 9);
      g2.apply(PlayMove(0, g2.addCard('Mega-Mech', 0))); // {7}
      answerAll(g2);
      passAll(g2);
      expect(readyRunes(g2, 0), 4, reason: '2 left, then 2 readied');
    });

    test('Astral Heron: your first card each turn makes the next {2}{A}{A} cheaper', () {
      final g = emptyGame();
      g.addCard('Astral Heron', 0, zone: Zone.board, loc: 0);
      g.addRunes(0, Domain.order, 2);
      g.apply(PlayMove(0, g.addCard('Daring Poro', 0)));
      passAll(g);
      expect(g.state.marks['t:x:0:nextCardE'], 2);
      expect(g.playCost(0, g.addCard('Vanguard Sergeant', 0)).energy, 2);
    });

    test('Super Mega Death Rocket! returns from the trash when you conquer', () {
      final g = emptyGame();
      final r = g.addCard('Super Mega Death Rocket!', 0, zone: Zone.trash);
      g.addCard('Shipyard Skulker', 0);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      g.apply(MoveUnitsMove(0, [u], 0));
      answerAll(g);
      passAll(g);
      expect(g.state.obj(r).zone, Zone.hand);
    });

    test('Minah Swiftfoot: a mode as it moves to a battlefield (Each player draws 1)', () {
      final g = emptyGame();
      g.stackDeck(0, 'Shipyard Skulker', 1);
      g.stackDeck(1, 'Shipyard Skulker', 1);
      final m = g.addCard('Minah Swiftfoot', 0, zone: Zone.board);
      g.apply(MoveUnitsMove(0, [m], 0));
      answer(g, [1]);
      passAll(g);
      expect(g.state.player(0).hand, hasLength(1));
      expect(g.state.player(1).hand, hasLength(1));
    });
  });

  group('Looking at and playing from the deck', () {
    test('Reinforce: banish a unit from the top 5 and play it {5} cheaper', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 7);
      g.stackDeck(0, 'Shipyard Skulker', 4);
      g.stackDeck(0, 'Mega-Mech', 1);
      g.apply(PlayMove(0, g.addCard('Reinforce', 0)));
      passAll(g);
      final mech = g.pending!.decision.options.firstWhere((id) => g.nameOf(id) == 'Mega-Mech');
      answer(g, [mech]);
      expect(g.state.obj(mech).zone, Zone.board);
      expect(g.state.player(0).deck, hasLength(4));
    });

    test('Nocturne: seen on top of the deck, it may be played for {A}', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 6);
      final n = g.addCard('Nocturne, Horrifying', 0, zone: Zone.mainDeck);
      g.apply(PlayMove(0, g.addCard('Fate Weaver', 0)));
      passAll(g);
      expect(g.pending?.decision.prompt, contains('Nocturne'));
      answer(g, [1]);
      passAll(g);
      expect(g.state.obj(n).zone, Zone.board);
    });

    test('Promising Future: each player plays one of their top 5, ignoring its Energy cost', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 6);
      g.stackDeck(0, 'Mega-Mech', 2);
      g.stackDeck(1, 'Mountain Drake', 2);
      g.apply(PlayMove(0, g.addCard('Promising Future', 0)));
      passAll(g);
      answerAll(g);
      passAll(g);
      expect(g.units(player: 0).map(g.nameOf), contains('Mega-Mech'));
      expect(g.units(player: 1).map(g.nameOf), contains('Mountain Drake'));
    });

    test('Blind Fury plays the top of the opponent’s deck for free, under your control', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 6);
      g.stackDeck(1, 'Mega-Mech', 1);
      g.apply(PlayMove(0, g.addCard('Blind Fury', 0)));
      passAll(g);
      answerAll(g);
      final mech = g.units(player: 0).firstWhere((u) => g.nameOf(u) == 'Mega-Mech');
      expect(g.state.obj(mech).owner, 1);
    });

    test('Cursed Sarcophagus banishes your trash’s units and plays them back', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 10);
      final u = g.addCard('Shipyard Skulker', 0, zone: Zone.trash);
      final cs = g.addCard('Cursed Sarcophagus', 0);
      g.apply(PlayMove(0, cs));
      passAll(g);
      expect(g.state.obj(u).zone, Zone.banish);
      g.apply(ActivateMove(0, cs, g.parsed(cs).abilities.indexWhere((a) => a is Activated)));
      passAll(g);
      answerAll(g);
      expect(g.state.obj(u).zone, Zone.board);
    });
  });

  group('Activated ability costs', () {
    test('Vi: "Recycle 1 from your trash" can’t be paid with an empty trash (CR 417.3)', () {
      final g = emptyGame();
      final vi = g.addCard('Vi, Destructive', 0, zone: Zone.board);
      final i = g.parsed(vi).abilities.indexWhere((a) => a is Activated);
      expect(g.whyNot(ActivateMove(0, vi, i)), isNotNull);
      final t = g.addCard('Shipyard Skulker', 0, zone: Zone.trash);
      g.apply(ActivateMove(0, vi, i));
      passAll(g);
      expect(g.state.obj(t).zone, Zone.mainDeck);
      expect(g.might(vi), 4);
    });
  });

  test('bot games with this family’s cards replay to the same fingerprint', () {
    var played = 0;
    for (var seed = 1; seed <= 12; seed++) {
      final rng = SeededRng(seed * 7919);
      final decks = [randomDeck(db, rng), randomDeck(db, rng)];
      final g = Game(db, players: ['A', 'B'], seed: seed);
      g.apply(StartMove(decks));
      runBots(g, [RiftboundBot(0, seed: seed), RiftboundBot(1, seed: seed + 1)], maxMoves: 4000);
      final r = Game(db, players: ['A', 'B'], seed: seed);
      for (final m in g.actions) {
        r.apply(m);
      }
      expect(r.fingerprint, g.fingerprint);
      played += g.actions.length;
    }
    expect(played, greaterThan(100));
  });
}
