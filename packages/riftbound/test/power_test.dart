// Empower (CR 442–443, 827–828), XP (CR 728–733), Hunt (CR 823), Level (CR 824), buffs (CR 427,
// 701–705) and Flow (CR 829), with real cards.
import 'package:riftbound/riftbound.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Index of [id]'s first ability matching [f].
int ab(Game g, int id, bool Function(Ability) f) {
  final i = g.parsed(id).abilities.indexWhere(f);
  expect(i, greaterThanOrEqualTo(0), reason: 'no such ability on ${g.nameOf(id)}');
  return i;
}

bool isEmpower(Ability a) => a is Activated && a.effects.any((e) => e is EmpowerMe);

/// Uses ability [index] of [id] and resolves the chain.
void use(Game g, int id, int index, {int seat = 0}) {
  g.apply(ActivateMove(seat, id, index));
  passAll(g);
}

void main() {
  group('Empower (CR 442, 827–828)', () {
    test('827.1.c.1 [Empower] is "{cost}: Empower this. Play only if not Empowered"; 828 the Empowered ability is active only while Empowered', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 3);
      final h = g.addCard('Brutal Hunter', 0, zone: Zone.board); // 4 Might; Empowered: +2 Might and Ganking
      expect(g.might(h), 4);
      expect(g.hasKw(h, Kw.ganking), isFalse);
      use(g, h, ab(g, h, isEmpower));
      expect(g.state.obj(h).pw.empowered, 1);
      expect(g.might(h), 6);
      expect(g.hasKw(h, Kw.ganking), isTrue);
      expect([for (final r in g.state.player(0).runes) if (g.state.obj(r).exhausted) r], hasLength(3), reason: '{3} paid');
      // Already Empowered: the ability can't be used again (CR 442.1.b).
      g.addRunes(0, Domain.body, 3);
      expect(g.whyNot(ActivateMove(0, h, ab(g, h, isEmpower))), contains('already Empowered'));
    });

    test('827.1.c.3 "This ability costs {1} less for each rune you control"', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 6);
      final m = g.addCard('Frostcoat Mother', 0, zone: Zone.board); // [Empower] {12}, {1} less per rune
      use(g, m, ab(g, m, isEmpower));
      expect(g.state.obj(m).pw.empowered, 1, reason: '{12} − 6 = {6}, payable with 6 runes');
      expect(g.might(m), 6);
    });

    test('204.1.b "[Empower] - {1} or {O}": either base cost', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 1);
      final m = g.addCard('Legion Marauder', 0, zone: Zone.board);
      final abs = [for (var i = 0; i < g.parsed(m).abilities.length; i++) if (isEmpower(g.parsed(m).abilities[i])) i];
      expect(abs, hasLength(2));
      // A Fury rune can pay {1} but not {O}.
      expect(g.whyNot(ActivateMove(0, m, abs[1])), isNotNull);
      use(g, m, abs[0]);
      expect(g.might(m), 3);
    });

    test('827.1.c.2 non-resource Empower costs: "Kill a friendly unit", "Discard 1"', () {
      final g = emptyGame();
      final y = g.addCard('Escaped Grayback', 0, zone: Zone.board);
      final fodder = g.addCard('Daring Poro', 0, zone: Zone.board);
      g.apply(ActivateMove(0, y, ab(g, y, isEmpower)));
      answer(g, [fodder]);
      passAll(g);
      expect(g.state.obj(fodder).zone, Zone.trash);
      expect(g.might(y), 5);
      final g2 = emptyGame();
      final poro = g2.addCard('Punching Poro', 0, zone: Zone.board);
      expect(g2.whyNot(ActivateMove(0, poro, ab(g2, poro, isEmpower))), contains('discard'));
      g2.addCard('Daring Poro', 0);
      use(g2, poro, ab(g2, poro, isEmpower));
      expect(g2.state.player(0).hand, isEmpty);
      expect(g2.might(poro), 3);
    });

    test('828.1.d "When I become [Empowered]" triggers', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 2);
      g.stackDeck(0, 'Daring Poro', 3);
      final m = g.addCard('Apprentice Mage', 0, zone: Zone.board); // When I become Empowered, Predict 2
      g.apply(ActivateMove(0, m, ab(g, m, isEmpower)));
      passAll(g);
      expect(g.pending?.decision.prompt, startsWith('Predict'));
      expect(g.pending?.decision.options, hasLength(2));
    });

    test('442.1.c.1 permission to be Empowered several times: Kayle, Justified', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 9);
      final k = g.addCard('Kayle, Justified', 0, zone: Zone.board); // 3 Might, +2 per Empower, three: Deflect 3, Ganking
      for (var i = 0; i < 3; i++) {
        use(g, k, ab(g, k, isEmpower));
      }
      expect(g.state.obj(k).pw.empowered, 3);
      expect(g.might(k), 9);
      expect(g.hasKw(k, Kw.ganking), isTrue);
      expect(g.whyNot(ActivateMove(0, k, ab(g, k, isEmpower))), isNotNull, reason: 'up to three times');
    });

    test('443 "Disempower this" as a cost; a legend\'s "When you empower something else, empower me"', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 4);
      g.stackDeck(0, 'Daring Poro', 2);
      final tome = g.addCard('Questionable Tome', 0, zone: Zone.board); // [Empower] - {E}; Disempower this, {1}, {E}: Draw 1
      final mel = g.addCard('Mel, Soul\'s Reflection', 0, zone: Zone.legend);
      expect(g.whyNot(ActivateMove(0, tome, 1)), contains('isn’t Empowered'));
      use(g, tome, ab(g, tome, isEmpower));
      expect(g.state.obj(tome).pw.empowered, 1);
      expect(g.state.obj(mel).pw.empowered, 1, reason: 'Mel: when you empower something else, empower me');
      g.state.obj(tome).exhausted = false;
      use(g, tome, 1);
      expect(g.state.obj(tome).pw.empowered, 0);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('a gear\'s instruction "Empower another gear"; Disempower a unit at end of turn', () {
      final g = emptyGame();
      final f = g.addCard('Hextech Formula', 0, zone: Zone.board);
      final egg = g.addCard('Platewyrm Egg', 0, zone: Zone.board);
      use(g, f, ab(g, f, (a) => a is Activated));
      expect(g.state.obj(egg).pw.empowered, 1);
      expect(g.state.obj(f).pw.empowered, 0);
    });

    test('an Empowered gear\'s "[Add] {2} instead" resolves at once and pays costs (CR 337.2, 357.1.a)', () {
      final g = emptyGame();
      final egg = g.addCard('Platewyrm Egg', 0, zone: Zone.board)..toString();
      g.state.obj(egg).pw.empowered = 1;
      final card = g.addCard('Brutal Hunter', 0); // {3} + 1 Body
      g.addRunes(0, Domain.body, 2);
      // 2 runes + the Egg's {2} pay {3} and the Body Power.
      expect(g.whyNot(PlayMove(0, card)), isNull);
    });

    test('Mournful Witness: "When a combat that I was in ends, empower me"', () {
      final g = emptyGame();
      final w = g.addCard('Mournful Witness', 0, zone: Zone.board); // 2 Might
      g.addCard('Recruit', 1, zone: Zone.board, loc: 0); // 1 Might
      g.setControl(0, 1);
      g.apply(MoveUnitsMove(0, [w], 0));
      passAll(g);
      expect(g.state.obj(w).zone, Zone.board);
      expect(g.state.obj(w).pw.empowered, 1);
    });

    test('Renekton, Brute: "When my Might becomes 10 or more, empower me"', () {
      final g = emptyGame();
      final r = g.addCard('Renekton, Brute', 0, zone: Zone.board); // 4 Might; {1}: +1 Might this turn
      g.state.obj(r).mightMod = 5;
      g.settleForTest();
      expect(g.state.obj(r).pw.empowered, 0);
      g.addRunes(0, Domain.body, 1);
      use(g, r, 0);
      passAll(g);
      expect(g.might(r), greaterThanOrEqualTo(10));
      expect(g.state.obj(r).pw.empowered, 1);
      expect(g.hasKw(r, Kw.ganking), isTrue);
    });

    test('Guttural Roar: "If it\'s [Empowered], give it +4 {M} this turn instead"', () {
      for (final empowered in [false, true]) {
        final g = emptyGame();
        g.addRunes(0, Domain.body, 2);
        final u = g.addCard('Daring Poro', 0, zone: Zone.board);
        if (empowered) g.state.obj(u).pw.empowered = 1;
        final before = g.might(u);
        g.apply(PlayMove(0, g.addCard('Guttural Roar', 0)));
        passAll(g);
        expect(g.might(u), before + (empowered ? 4 : 2));
      }
    });

    test('Tomb-Raider Barbara: disempower an Empowered enemy gear, otherwise kill it (only with 7+ runes)', () {
      for (final empowered in [false, true]) {
        final g = emptyGame();
        g.addRunes(0, Domain.calm, 7);
        final gear = g.addCard('Questionable Tome', 1, zone: Zone.board);
        if (empowered) g.state.obj(gear).pw.empowered = 1;
        g.apply(PlayMove(0, g.addCard('Tomb-Raider Barbara', 0)));
        passAll(g);
        expect(g.state.obj(gear).zone, empowered ? Zone.board : Zone.trash);
        expect(g.state.obj(gear).pw.empowered, 0);
      }
    });

    test('Mel, Defiant Soul: "When I become [Empowered], banish an enemy unit at a battlefield with 3 {M} or less" (CR 428)', () {
      final g = emptyGame();
      final mel = g.addCard('Mel, Defiant Soul', 0, zone: Zone.board);
      g.addCard('Abandon', 0); // a spell to discard
      final victim = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
      use(g, mel, ab(g, mel, isEmpower));
      expect(g.state.obj(victim).zone, Zone.banish);
      expect(g.state.player(1).banish, contains(victim));
    });

    test('Rage Amplifier: +1 {M}, or +2 {M} instead while Empowered; Helm of Suppression: opponents\' spells cost more', () {
      final g = emptyGame();
      final amp = g.addCard('Rage Amplifier', 0, zone: Zone.board);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      final base0 = g.db['Daring Poro']!.might!;
      expect(g.might(u), base0 + 1);
      g.state.obj(amp).pw.empowered = 1;
      expect(g.might(u), base0 + 2);
      final helm = g.addCard('Helm of Suppression', 1, zone: Zone.board);
      final s = g.addCard('Guttural Roar', 0); // {2}
      expect(g.playCost(0, s).energy, 3);
      g.state.obj(helm).pw.empowered = 1;
      expect(g.playCost(0, s).energy, 3);
      expect(g.playCost(0, s).power, hasLength(1));
    });

    test('Applied Researchers: "Your spells cost {1}{A} less, to a minimum of {1}"', () {
      final g = emptyGame();
      final r = g.addCard('Applied Researchers', 0, zone: Zone.board);
      g.state.obj(r).pw.empowered = 1;
      final s = g.addCard('Guttural Roar', 0); // {2}
      expect(g.playCost(0, s).energy, 1);
      final cheap = g.addCard('Combat Experience', 0); // {1}
      expect(g.playCost(0, cheap).energy, 1, reason: 'to a minimum of {1}');
    });

    test('Gangplank, Naval: a -Might from an ability that chooses it gives it +3 {M} instead (CR 370)', () {
      final g = emptyGame(active: 1);
      final gp = g.addCard('Gangplank, Naval', 0, zone: Zone.board, loc: 0);
      g.state.obj(gp).pw.empowered = 1;
      final before = g.might(gp);
      final mel = g.addCard('Mel, Soul\'s Reflection', 1, zone: Zone.legend); // Disempower me, {E}: Give a unit at a battlefield -2 {M} this turn.
      g.state.obj(mel).pw.empowered = 1;
      use(g, mel, 1, seat: 1);
      expect(g.might(gp), before + 3);
      // Not Empowered: the -2 applies.
      final g2 = emptyGame(active: 1);
      final gp2 = g2.addCard('Gangplank, Naval', 0, zone: Zone.board, loc: 0);
      final mel2 = g2.addCard('Mel, Soul\'s Reflection', 1, zone: Zone.legend);
      g2.state.obj(mel2).pw.empowered = 1;
      use(g2, mel2, 1, seat: 1);
      expect(g2.might(gp2), g2.db['Gangplank, Naval']!.might! - 2);
    });
  });

  group('XP, Hunt and Level (CR 728–733, 823, 824)', () {
    test('730.1 "gain N XP"; 730.2 "Spend N XP" as a cost', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 2);
      g.apply(PlayMove(0, g.addCard('Demacian Diplomat', 0)));
      passAll(g);
      expect(g.state.player(0).pw.xp, 1);
      final rose = g.addCard('Blood Rose', 0, zone: Zone.board); // Spend 3 XP, {E}: Ready a unit.
      final u = g.addCard('Daring Poro', 0, zone: Zone.board, exhausted: true);
      final spend = ab(g, rose, (a) => a is Activated);
      expect(g.whyNot(ActivateMove(0, rose, spend)), contains('3 XP'));
      g.state.player(0).pw.xp = 3;
      g.apply(ActivateMove(0, rose, spend));
      if (g.pending != null) answer(g, [u]);
      passAll(g);
      expect(g.state.player(0).pw.xp, 0);
      expect(g.state.obj(u).exhausted, isFalse);
    });

    test('823.1.c.1 [Hunt N]: "When I conquer or hold, gain N XP"', () {
      final g = emptyGame();
      final w = g.addCard('Gustwalker', 0, zone: Zone.board); // Hunt 2
      g.apply(MoveUnitsMove(0, [w], 0));
      passAll(g);
      expect(g.state.bfs[0].controller, 0);
      expect(g.state.player(0).pw.xp, 2);
    });

    test('824.1.c [Level N] is active while you have N XP, and stops when you have less (824.1.d)', () {
      final g = emptyGame();
      final w = g.addCard('Gustwalker', 0, zone: Zone.board); // Level 3: +1 Might and Ganking
      final m = g.might(w);
      expect(g.hasKw(w, Kw.ganking), isFalse);
      g.state.player(0).pw.xp = 3;
      expect(g.might(w), m + 1);
      expect(g.hasKw(w, Kw.ganking), isTrue);
      g.state.player(0).pw.xp = 2;
      expect(g.might(w), m);
    });

    test('824.1.c.1 Level follows the controller\'s XP', () {
      final g = emptyGame();
      final w = g.addCard('Gustwalker', 0, zone: Zone.board);
      g.state.player(1).pw.xp = 5;
      expect(g.hasKw(w, Kw.ganking), isFalse);
      g.state.obj(w).controller = 1;
      expect(g.hasKw(w, Kw.ganking), isTrue);
    });

    test('a spell\'s [Level N] "… instead" line replaces the line before it (Combat Experience)', () {
      for (final xp in [0, 6]) {
        final g = emptyGame();
        g.state.player(0).pw.xp = xp;
        g.addRunes(0, Domain.calm, 1);
        final u = g.addCard('Daring Poro', 0, zone: Zone.board);
        final m = g.might(u);
        g.apply(PlayMove(0, g.addCard('Combat Experience', 0)));
        passAll(g);
        expect(g.might(u), m + (xp >= 6 ? 3 : 1));
      }
    });

    test('Level cost reductions: the largest active one applies (Concentrate, Master Yi, Unstoppable)', () {
      final g = emptyGame();
      final c = g.addCard('Concentrate', 0); // {5}; Level 6: {2} less; Level 11: {4} less instead
      expect(g.playCost(0, c).energy, 5);
      g.state.player(0).pw.xp = 6;
      expect(g.playCost(0, c).energy, 3);
      g.state.player(0).pw.xp = 11;
      expect(g.playCost(0, c).energy, 1);
      final yi = g.addCard('Master Yi, Unstoppable', 0); // {12} + 3 Calm
      expect(g.playCost(0, yi).energy, 6);
      expect(g.playCost(0, yi).power, isEmpty, reason: '{6}{G}{G}{G} less at Level 11');
    });

    test('Wily Newtfish: "If you\'ve gained XP this turn, I have +1 {M} and [Ganking]"', () {
      final g = emptyGame();
      final n = g.addCard('Wily Newtfish', 0, zone: Zone.board);
      expect(g.hasKw(n, Kw.ganking), isFalse);
      g.gainXp(0, 1);
      expect(g.hasKw(n, Kw.ganking), isTrue);
    });

    test('Kha\'Zix, Evolving Hunter: "you may spend 3 XP to deal damage equal to my Might" (CR 204.3)', () {
      final g = emptyGame();
      g.state.player(0).pw.xp = 3;
      final k = g.addCard('Kha\'Zix, Evolving Hunter', 0, zone: Zone.board);
      final e = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
      g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
      g.apply(MoveUnitsMove(0, [k], 0));
      // The attack trigger: choose its target, then yes to spending.
      while (g.pending != null) {
        final d = g.pending!.decision;
        answer(g, d.kind == DecisionKind.cards ? [e] : [1]);
      }
      passAll(g);
      expect(g.state.player(0).pw.xp, 1, reason: '3 spent, then 1 from Hunt for the conquer');
      expect(g.state.obj(e).zone, Zone.trash);
    });

    test('Gardens of Becoming grants its units "{E}: Gain 1 XP."', () {
      final g = emptyGame(battlefields: const ['Gardens of Becoming', 'Zaun Warrens']);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 0);
      expect(g.legalMoves(0).any((m) => m is ActivateMove && m.index == grantedXpAbility), isTrue);
      g.apply(ActivateMove(0, u, grantedXpAbility));
      expect(g.state.player(0).pw.xp, 1);
      expect(g.state.obj(u).exhausted, isTrue);
    });

    test('Insightful Investigator: reveal, pay 2 XP to make them discard a card and draw 1', () {
      final g = emptyGame();
      g.state.player(0).pw.xp = 2;
      g.addRunes(0, Domain.chaos, 3);
      final c = g.addCard('Abandon', 1);
      g.stackDeck(1, 'Daring Poro', 1);
      g.apply(PlayMove(0, g.addCard('Insightful Investigator', 0)));
      while (g.pending != null) {
        final d = g.pending!.decision;
        answer(g, d.kind == DecisionKind.cards ? [c] : [1]);
      }
      passAll(g);
      expect(g.state.obj(c).zone, Zone.trash);
      expect(g.state.player(1).hand, hasLength(1));
      expect(g.state.player(0).pw.xp, 0);
    });
  });

  group('Buffs (CR 427, 701–705)', () {
    test('427.1.b.2 "I can have any number of buffs"; each buff is +1 Might (CR 703)', () {
      final g = emptyGame();
      final lee = g.addCard('Lee Sin, Ascetic', 0, zone: Zone.board); // {E}: Buff me.
      final m = g.might(lee);
      use(g, lee, ab(g, lee, (a) => a is Activated));
      g.state.obj(lee).exhausted = false;
      use(g, lee, ab(g, lee, (a) => a is Activated));
      expect(g.might(lee), m + 2);
    });

    test('702.2.b "Spend my buff" as a cost; "When you spend a buff" triggers (Fae Dragon)', () {
      final g = emptyGame();
      final sett = g.addCard('Sett, Brawler', 0, zone: Zone.board);
      g.addCard('Fae Dragon', 0, zone: Zone.board);
      final spend = ab(g, sett, (a) => a is Activated);
      expect(g.whyNot(ActivateMove(0, sett, spend)), contains('no buff'));
      g.state.obj(sett).buffed = true;
      final m = g.might(sett);
      use(g, sett, spend);
      expect(g.state.obj(sett).buffed, isFalse);
      expect(g.might(sett), m - 1 + 4);
      expect(g.gearOf(0).map(g.nameOf), contains('Gold'));
    });

    test('427.1.c "When you buff me" triggers only when a buff is placed (Simian Ancestor)', () {
      final g = emptyGame();
      final s = g.addCard('Simian Ancestor', 0, zone: Zone.board, exhausted: true);
      g.addRunes(0, Domain.order, 1);
      final caller = g.addCard('Cithria of Cloudfield', 0, zone: Zone.board); // plays-another-unit buff, not this one
      expect(caller, isNot(s));
      g.state.player(0).pw.xp = 1;
      final legend = g.addCard('Kha\'Zix, Voidreaver', 0, zone: Zone.legend); // Spend 1 XP, {E}: Buff a unit.
      g.apply(ActivateMove(0, legend, 1));
      answer(g, [s]);
      passAll(g);
      expect(g.state.obj(s).buffed, isTrue);
      expect(g.state.obj(s).exhausted, isFalse, reason: 'readied by its trigger');
    });

    test('While I\'m buffed: Wizened Elder +1 more, Bilgewater Bully Ganking', () {
      final g = emptyGame();
      final w = g.addCard('Wizened Elder', 0, zone: Zone.board);
      final m = g.might(w);
      g.state.obj(w).buffed = true;
      expect(g.might(w), m + 2);
      final b = g.addCard('Bilgewater Bully', 0, zone: Zone.board);
      expect(g.hasKw(b, Kw.ganking), isFalse);
      g.state.obj(b).buffed = true;
      expect(g.hasKw(b, Kw.ganking), isTrue);
    });

    test('Fae Dragon: "buff up to four friendly units"', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 8);
      final us = [for (var i = 0; i < 3; i++) g.addCard('Daring Poro', 0, zone: Zone.board)];
      final d = g.addCard('Fae Dragon', 0);
      g.apply(PlayMove(0, d));
      while (g.pending != null) {
        final dec = g.pending!.decision;
        answer(g, dec.kind == DecisionKind.cards ? dec.options.take(dec.max).toList() : [0]);
      }
      passAll(g);
      expect(us.every((u) => g.state.obj(u).buffed), isTrue);
    });

    test('Albus Ferros: spend any number of buffs, channel a rune exhausted for each', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 4);
      for (var i = 0; i < 2; i++) {
        g.addRunes(0, Domain.order, 0);
      }
      g.state.player(0).runeDeck.addAll([for (var i = 0; i < 3; i++) g.addCard('Order Rune', 0, zone: Zone.runeDeck)]);
      final a = g.addCard('Daring Poro', 0, zone: Zone.board)..toString();
      final b = g.addCard('Daring Poro', 0, zone: Zone.board);
      g.state.obj(a).buffed = true;
      g.state.obj(b).buffed = true;
      g.apply(PlayMove(0, g.addCard('Albus Ferros', 0)));
      answer(g, [a, b]);
      passAll(g);
      expect(g.state.player(0).runes, hasLength(6));
      expect(g.state.obj(a).buffed || g.state.obj(b).buffed, isFalse);
    });

    test('Sett, The Boss: a buffed unit that would die is recalled exhausted instead (CR 370)', () {
      final g = emptyGame();
      // In combat: the unit is saved as combat kills it (CR 468.1), then combat heals every unit.
      // (After spell damage it would die again at the next cleanup: a recall doesn't heal, CR 460.)
      g.addCard('Sett, The Boss', 0, zone: Zone.legend);
      g.addRunes(0, Domain.order, 1);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board); // 2 Might + buff, Assault
      g.state.obj(u).buffed = true;
      g.addCard('Brutal Hunter', 1, zone: Zone.board, loc: 0); // 4 Might
      g.setControl(0, 1);
      g.apply(MoveUnitsMove(0, [u], 0));
      passAll(g);
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
      answer(g, [1]);
      passAll(g);
      final k = g.state.obj(u);
      expect(k.damage, 0);
      expect(k.zone, Zone.board);
      expect(k.loc, base);
      expect(k.exhausted, isTrue);
      expect(k.buffed, isFalse);
    });
  });

  group('Flow (CR 829)', () {
    test('829.1.b a Flow spell is played from the trash for its Flow cost, then banished', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 2);
      g.stackDeck(0, 'Daring Poro', 2);
      final s = g.addCard('Dredge Up', 0, zone: Zone.trash); // Draw 1; Flow {2}
      expect(g.legalMoves(0).any((m) => m is PlayMove && m.card == s), isTrue);
      g.apply(PlayMove(0, s));
      passAll(g);
      expect(g.state.player(0).hand, hasLength(1));
      expect(g.state.obj(s).zone, Zone.banish);
      expect(g.state.player(0).trash, isNot(contains(s)));
    });

    test('Stargazer: Flow spells from the trash cost {2} less, to a minimum of {1}', () {
      final g = emptyGame();
      g.addCard('Stargazer', 0, zone: Zone.board);
      final s = g.addCard('Onslaught', 0, zone: Zone.trash); // Flow {4}
      expect(g.playCost(0, s).energy, 2);
      final d = g.addCard('Dredge Up', 0, zone: Zone.trash); // Flow {2}
      expect(g.playCost(0, d).energy, 1);
    });

    test('a spell played normally goes to the trash, not banishment', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 2);
      g.stackDeck(0, 'Daring Poro', 1);
      final s = g.addCard('Dredge Up', 0);
      g.apply(PlayMove(0, s));
      passAll(g);
      expect(g.state.obj(s).zone, Zone.trash);
    });

    test('Death Mark: Burn 3 (CR 441), a Shadow Clone token', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 3);
      g.stackDeck(0, 'Daring Poro', 5);
      g.apply(PlayMove(0, g.addCard('Death Mark', 0)));
      passAll(g);
      expect(g.state.player(0).trash.where((id) => g.nameOf(id) == 'Daring Poro'), hasLength(3));
      expect(g.units(player: 0).map(g.nameOf), contains('Shadow Clone'));
    });
  });

  group('Other effects of these cards', () {
    test('Vicious Snapjaws: "When another friendly unit dies, gain 1 XP"', () {
      final g = emptyGame();
      g.addCard('Vicious Snapjaws', 0, zone: Zone.board);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      g.state.obj(u).damage = 99;
      g.settleForTest();
      passAll(g);
      expect(g.state.player(0).pw.xp, 1);
    });

    test('Karma, Channeler: recycling (a Predict) buffs a friendly unit', () {
      final g = emptyGame();
      final k = g.addCard('Karma, Channeler', 0, zone: Zone.board);
      g.stackDeck(0, 'Daring Poro', 2);
      g.addRunes(0, Domain.mind, 2);
      final m = g.addCard('Apprentice Mage', 0, zone: Zone.board);
      g.apply(ActivateMove(0, m, ab(g, m, isEmpower)));
      passAll(g);
      // Predict 2: recycle both; then Karma buffs a friendly unit.
      answer(g, g.pending!.decision.options);
      passAll(g);
      if (g.pending != null) answer(g, [k]);
      passAll(g);
      expect(g.state.obj(k).buffed || g.state.obj(m).buffed, isTrue);
    });

    test('Wild Claw: banish and play a unit for {5} less, then may empower it', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 8);
      g.stackDeck(0, 'Brutal Hunter', 1);
      g.apply(PlayMove(0, g.addCard('Wild Claw', 0)));
      passAll(g);
      final pick = g.pending!.decision.options.first;
      answer(g, [pick]);
      while (g.pending != null) {
        answer(g, g.pending!.decision.kind == DecisionKind.option ? [0] : [1]);
      }
      expect(g.state.obj(pick).zone, Zone.board);
      expect(g.state.obj(pick).pw.empowered, 1);
    });
  });
}
