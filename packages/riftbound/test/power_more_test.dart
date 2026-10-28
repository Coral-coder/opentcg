// More cards of the Empower / XP / buff / Flow family (power_test.dart has the core rules).
import 'package:riftbound/riftbound.dart';
import 'package:test/test.dart';

import 'helpers.dart';

int ab(Game g, int id, bool Function(Ability) f) => g.parsed(id).abilities.indexWhere(f);

bool isEmpower(Ability a) => a is Activated && a.effects.any((e) => e is EmpowerMe);

void main() {
  test('390 a delayed ability this turn: Rally the Troops buffs each friendly unit played', () {
    final g = emptyGame();
    g.addRunes(0, Domain.order, 4);
    g.stackDeck(0, 'Daring Poro', 1);
    g.apply(PlayMove(0, g.addCard('Rally the Troops', 0)));
    passAll(g);
    final u = g.addCard('Daring Poro', 0);
    g.apply(PlayMove(0, u));
    passAll(g);
    expect(g.state.obj(u).buffed, isTrue);
  });

  test('Grim Resolve: "When it wins a combat this turn, gain 2 XP"', () {
    final g = emptyGame();
    g.addRunes(0, Domain.body, 2);
    final u = g.addCard('Daring Poro', 0, zone: Zone.board);
    g.addCard('Recruit', 1, zone: Zone.board, loc: 0);
    g.setControl(0, 1);
    g.apply(PlayMove(0, g.addCard('Grim Resolve', 0)));
    passAll(g);
    g.apply(MoveUnitsMove(0, [u], 0));
    passAll(g);
    expect(g.state.bfs[0].controller, 0);
    expect(g.state.player(0).pw.xp, 2);
  });

  test('Red Brambleback: conquer effects for conquering here trigger an additional time', () {
    final g = emptyGame();
    final rb = g.addCard('Red Brambleback', 0, zone: Zone.board);
    final p = g.addCard('Daring Poro', 0, zone: Zone.board);
    g.apply(MoveUnitsMove(0, [rb], 0));
    // Each trigger chooses as it goes on the chain (CR 355.5.b): one each.
    final picks = [rb, p];
    for (var i = 0; g.pending != null; i++) {
      answer(g, [picks[i % 2]]);
    }
    passAll(g);
    expect(g.state.obj(rb).buffed && g.state.obj(p).buffed, isTrue, reason: '"When I conquer, buff a friendly unit" twice');
  });

  test('Master Yi, Wuju Master: Level 6 "Your units have +1 {M}", Level 11 "Your units enter ready"', () {
    final g = emptyGame();
    g.addCard('Master Yi, Wuju Master', 0, zone: Zone.legend);
    g.addRunes(0, Domain.order, 2);
    g.state.player(0).pw.xp = 11;
    final u = g.addCard('Daring Poro', 0);
    g.apply(PlayMove(0, u));
    expect(g.state.obj(u).exhausted, isFalse);
    expect(g.might(u), g.db['Daring Poro']!.might! + 1);
  });

  test('Bandle Soldier: "[Level 3][>] I enter ready"', () {
    for (final xp in [0, 3]) {
      final g = emptyGame();
      g.state.player(0).pw.xp = xp;
      g.addRunes(0, Domain.order, 5);
      final u = g.addCard('Bandle Soldier', 0);
      g.apply(PlayMove(0, u));
      expect(g.state.obj(u).exhausted, xp < 3);
    }
  });

  test('Glowstone: "Disempower this, {E}: Choose a player. They gain control of this and recall it."', () {
    final g = emptyGame();
    final gs = g.addCard('Glowstone', 0, zone: Zone.board);
    g.state.obj(gs).pw.empowered = 1;
    g.apply(ActivateMove(0, gs, 1));
    passAll(g);
    answer(g, [1]);
    expect(g.state.obj(gs).controller, 1);
    expect(g.state.obj(gs).pw.empowered, 0);
  });

  test('Twilight Shroud: a unit that can\'t be chosen by enemy spells this turn', () {
    final g = emptyGame();
    g.addRunes(0, Domain.calm, 1);
    final u = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 0);
    g.apply(PlayMove(0, g.addCard('Twilight Shroud', 0)));
    passAll(g);
    expect(g.state.obj(u).pw.untargetableTurn, g.state.turn);
    // The opponent's Shock Blast now has nothing to choose.
    g.state.active = 1;
    g.addRunes(1, Domain.mind, 4);
    expect(g.whyNot(PlayMove(1, g.addCard('Shock Blast', 1))), contains('No legal target'));
  });

  test('Kennen, Storm of Shuriken: conquering gives a spell in the trash Flow equal to its cost this turn', () {
    final g = emptyGame();
    final k = g.addCard('Kennen, Storm of Shuriken', 0, zone: Zone.board);
    final s = g.addCard('Guttural Roar', 0, zone: Zone.trash); // {2}, no Flow of its own
    g.addCard('Daring Poro', 0, zone: Zone.board);
    expect(g.legalMoves(0).any((m) => m is PlayMove && m.card == s), isFalse);
    g.apply(MoveUnitsMove(0, [k], 0));
    passAll(g);
    g.addRunes(0, Domain.body, 2);
    expect(g.legalMoves(0).any((m) => m is PlayMove && m.card == s), isTrue);
    g.apply(PlayMove(0, s));
    if (g.pending != null) answer(g, [g.pending!.decision.options.first]);
    passAll(g);
    expect(g.state.obj(s).zone, Zone.banish);
  });

  test('Profiteer: disempower something to empower a legend', () {
    final g = emptyGame();
    g.addRunes(0, Domain.body, 4);
    final legend = g.addCard('Akali, Rogue Assassin', 0, zone: Zone.legend);
    final tome = g.addCard('Questionable Tome', 0, zone: Zone.board);
    g.state.obj(tome).pw.empowered = 1;
    g.apply(PlayMove(0, g.addCard('Profiteer', 0)));
    while (g.pending != null) {
      final d = g.pending!.decision;
      answer(g, d.kind == DecisionKind.cards ? [d.options.contains(legend) ? legend : tome] : (d.kind == DecisionKind.yesNo ? [1] : [0]));
    }
    passAll(g);
    expect(g.state.obj(tome).pw.empowered, 0);
    expect(g.state.obj(legend).pw.empowered, 1);
  });

  test('Tail-Cloaked Matriarch: play a cheap unit from your trash to base, ignoring its cost', () {
    final g = emptyGame();
    g.addRunes(0, Domain.chaos, 3);
    final m = g.addCard('Tail-Cloaked Matriarch', 0, zone: Zone.board);
    final cheap = g.addCard('Daring Poro', 0, zone: Zone.trash); // {2}, no Power
    g.addCard('Bandle Soldier', 0, zone: Zone.trash); // {4}: too expensive
    g.apply(ActivateMove(0, m, ab(g, m, isEmpower)));
    passAll(g);
    answer(g, [1]);
    expect(g.pending?.decision.options, [cheap]);
    answer(g, [cheap]);
    passAll(g);
    expect(g.state.obj(cheap).zone, Zone.board);
    expect(g.state.obj(cheap).loc, base);
  });

  test('Lacerate: disempower an Empowered unit, then kill it if it has 3 {M} or less', () {
    final g = emptyGame();
    g.addRunes(0, Domain.order, 3);
    final small = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
    g.state.obj(small).pw.empowered = 1;
    g.addCard('Bandle Soldier', 1, zone: Zone.board, loc: 0);
    g.apply(PlayMove(0, g.addCard('Lacerate', 0)));
    answer(g, [small]);
    passAll(g);
    expect(g.state.obj(small).zone, Zone.trash);
  });

  test('Public Execution: kill an enemy unit with less Might than the friendly unit chosen', () {
    final g = emptyGame();
    g.addRunes(0, Domain.body, 3);
    final mine = g.addCard('Brutal Hunter', 0, zone: Zone.board); // 4
    final weak = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0); // 2
    final strong = g.addCard('Bandle Soldier', 1, zone: Zone.board, loc: 0); // 5: not a choice
    g.apply(PlayMove(0, g.addCard('Public Execution', 0)));
    // One friendly unit and one enemy unit with less Might: both chosen without asking (CR 355).
    expect(mine, isPositive);
    expect(g.pending, isNull);
    passAll(g);
    expect(g.state.obj(weak).zone, Zone.trash);
    expect(g.state.obj(strong).zone, Zone.board);
  });

  test('Shadow Dash: move an enemy unit to a battlefield where you have units; exactly two of yours there get +1 {M}', () {
    final g = emptyGame();
    g.addRunes(0, Domain.calm, 3);
    final a = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 1);
    final b = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 1);
    final e = g.addCard('Recruit', 1, zone: Zone.board, loc: 0);
    g.apply(PlayMove(0, g.addCard('Shadow Dash', 0)));
    while (g.pending != null) {
      final d = g.pending!.decision;
      // The enemy to move, then (in the combat that follows) where its 1 damage goes.
      answer(g, d.kind == DecisionKind.cards ? [d.options.contains(e) ? e : d.options.first] : [0]);
    }
    passAll(g);
    expect(g.state.obj(a).mightMod, 1);
    expect(g.state.obj(b).mightMod, 1);
  });

  test('Lee Sin, Centered and Sett, Kingpin count buffed friendly units at their battlefield', () {
    final g = emptyGame();
    g.addCard('Lee Sin, Centered', 0, zone: Zone.board, loc: 0);
    final sett = g.addCard('Sett, Kingpin', 0, zone: Zone.board, loc: 0);
    final u = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 0);
    g.state.obj(u).buffed = true;
    expect(g.might(u), g.db['Daring Poro']!.might! + 1 + 2, reason: 'buff and Lee Sin');
    expect(g.might(sett), 5 + 1, reason: 'one buffed friendly unit there');
    // In base, "at my battlefield" counts nothing.
    final g2 = emptyGame();
    g2.addCard('Lee Sin, Centered', 0, zone: Zone.board);
    final u2 = g2.addCard('Daring Poro', 0, zone: Zone.board);
    g2.state.obj(u2).buffed = true;
    expect(g2.might(u2), g2.db['Daring Poro']!.might! + 1);
  });

  test('Spirit\'s Refuge: friendly buffed units have [Deflect] if they didn\'t already', () {
    final g = emptyGame();
    g.addCard('Spirit\'s Refuge', 0, zone: Zone.board);
    final u = g.addCard('Daring Poro', 0, zone: Zone.board);
    expect(g.hasKw(u, Kw.deflect), isFalse);
    g.state.obj(u).buffed = true;
    expect(g.hasKw(u, Kw.deflect), isTrue);
  });

  test('Valley of Idols: "When a player plays a unit here, they may pay {1} to [Buff] it"', () {
    final g = emptyGame(battlefields: const ['Valley of Idols', 'Zaun Warrens']);
    g.setControl(0, 0);
    g.addRunes(0, Domain.order, 3);
    final u = g.addCard('Daring Poro', 0);
    g.apply(PlayMove(0, u));
    answer(g, [1]); // play it to the Valley
    passAll(g);
    expect(g.pending?.decision.kind, DecisionKind.yesNo);
    answer(g, [1]);
    passAll(g);
    expect(g.state.obj(u).buffed, isTrue);
  });

  test('Mel, Newly Awakened: your spells can\'t be countered while it\'s Empowered', () {
    final g = emptyGame();
    final mel = g.addCard('Mel, Newly Awakened', 0, zone: Zone.board);
    g.state.obj(mel).pw.empowered = 1;
    g.addRunes(0, Domain.body, 2);
    g.addRunes(1, Domain.calm, 5);
    g.addCard('Daring Poro', 0, zone: Zone.board);
    final wall = g.addCard('Wind Wall', 1); // [Reaction] Counter a spell.
    final m = g.might(mel);
    g.apply(PlayMove(0, g.addCard('Guttural Roar', 0)));
    answer(g, [mel]);
    // The opponent can't counter it, so it resolves at once (they pass automatically).
    expect(g.state.chain, isEmpty);
    expect(g.might(mel), m + 4, reason: '+4: Mel is Empowered');
    expect(g.state.player(1).hand, contains(wall));
    // Not Empowered: the opponent gets the chance to counter.
    final g2 = emptyGame();
    final mel2 = g2.addCard('Mel, Newly Awakened', 0, zone: Zone.board);
    g2.addRunes(0, Domain.body, 2);
    g2.addRunes(1, Domain.calm, 5);
    final wall2 = g2.addCard('Wind Wall', 1);
    g2.apply(PlayMove(0, g2.addCard('Guttural Roar', 0)));
    expect(g2.pending, isNull, reason: 'Mel is the only unit');
    expect(mel2, isPositive);
    expect(g2.state.chain, hasLength(1));
    expect(g2.whyNot(PlayMove(1, wall2)), isNull);
  });

  test('Alpha Strike: a friendly unit\'s Might split among enemy units at battlefields; XP for each kill', () {
    final g = emptyGame();
    g.addRunes(0, Domain.calm, 4);
    final big = g.addCard('Bandle Soldier', 0, zone: Zone.board); // 5
    final a = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0); // 2
    final b = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 1); // 2
    g.apply(PlayMove(0, g.addCard('Alpha Strike', 0))); // the only friendly unit: chosen without asking
    expect(big, isPositive);
    passAll(g);
    // The player splits the 5 damage point by point (CR 355.14): 2 to each, the last anywhere.
    final given = <int, int>{};
    while (g.pending != null) {
      final pick = (given[a] ?? 0) < 2 ? a : b;
      given[pick] = (given[pick] ?? 0) + 1;
      answer(g, [pick]);
    }
    expect(g.state.obj(a).zone, Zone.trash);
    expect(g.state.obj(b).zone, Zone.trash);
    expect(g.state.player(0).pw.xp, 2);
  });

  test('Stare Down: enemy units at the chosen battlefield with less Might than the chosen unit go to their base', () {
    final g = emptyGame();
    g.addRunes(0, Domain.body, 2);
    final mine = g.addCard('Brutal Hunter', 0, zone: Zone.board); // 4
    final weak = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0); // 2
    final strong = g.addCard('Bandle Soldier', 1, zone: Zone.board, loc: 0); // 5
    g.apply(PlayMove(0, g.addCard('Stare Down', 0))); // the only friendly unit: chosen without asking
    expect(mine, isPositive);
    // The battlefield is chosen as the spell is played (CR 355.4), before anyone can respond.
    expect(g.state.chain, isEmpty);
    answer(g, [g.state.bfs[0].obj]);
    passAll(g);
    expect(g.state.obj(weak).loc, base);
    expect(g.state.obj(strong).loc, 0);
    expect(g.state.player(0).pw.xp, 1);
  });

  test('Ivern, Nurturer: reveal a Poro from the top 3, draw it, and buff a friendly unit', () {
    final g = emptyGame();
    g.addRunes(0, Domain.calm, 6);
    g.stackDeck(0, 'Bandle Soldier', 2);
    g.stackDeck(0, 'Daring Poro', 1); // a Poro on top
    final ivern = g.addCard('Ivern, Nurturer', 0);
    g.apply(PlayMove(0, ivern));
    passAll(g);
    final poro = g.pending!.decision.options.firstWhere((id) => g.nameOf(id) == 'Daring Poro');
    answer(g, [poro]);
    passAll(g);
    if (g.pending != null) answer(g, [ivern]);
    passAll(g);
    expect(g.state.player(0).hand, contains(poro));
    expect(g.state.obj(ivern).buffed, isTrue);
  });

  test('Akali, Rogue Assassin: in a showdown on your turn, move a friendly unit there to base and ready it while Empowered', () {
    final g = emptyGame();
    final legend = g.addCard('Akali, Rogue Assassin', 0, zone: Zone.legend);
    g.state.obj(legend).pw.empowered = 1;
    final u = g.addCard('Daring Poro', 0, zone: Zone.board);
    g.addCard('Bandle Soldier', 1, zone: Zone.board, loc: 0);
    g.setControl(0, 1);
    g.apply(MoveUnitsMove(0, [u], 0));
    expect(g.state.showdown?.combat, isTrue);
    g.apply(ActivateMove(0, legend, 1));
    passAll(g);
    final o = g.state.obj(u);
    expect(o.loc, base);
    expect(o.exhausted, isFalse);
  });
}
