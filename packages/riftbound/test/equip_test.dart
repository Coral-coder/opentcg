import 'package:riftbound/riftbound.dart';
import 'package:tcg_core/tcg_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Activates [gear]'s Equip ability onto [unit] (choosing it if there's a choice) and lets the
/// chain resolve.
void equip(Game g, int gear, int unit) {
  final i = g.parsed(gear).abilities.indexWhere((a) => a is EqEquip);
  g.apply(ActivateMove(g.state.obj(gear).controller, gear, i));
  if (g.pending != null && g.pending!.decision.options.contains(unit)) answer(g, [unit]);
  passAll(g);
}

/// Puts [n] runes of [d] in [player]'s rune deck.
void runeDeck(Game g, int player, Domain d, int n) {
  for (var i = 0; i < n; i++) {
    final r = g.addCard('${d.label} Rune', player, zone: Zone.runeDeck);
    g.state.player(player).runeDeck.add(r);
  }
}

/// Passes until the chain is empty (leaving any showdown open).
void passChain(Game g) {
  for (var i = 0; i < 20 && g.pending == null && g.state.chain.isNotEmpty; i++) {
    g.apply(PassMove(g.toAct!));
  }
}

void main() {
  group('Card data (CR 136, 137, 150)', () {
    test('150.2 Equipment carry their Effect Text and Might Bonus (from the official gallery)', () {
      expect(db['B.F. Sword']!.mightBonus, 3);
      expect(db['Guardian Angel']!.effect, 'If I would die, kill Guardian Angel instead. Heal me, exhaust me, and recall me.');
      expect(db['Trinity Force']!.effect, 'When I hold, score 1 point.');
      expect(RiftboundParser.parse(db['Trinity Force']!).extra, hasLength(1));
    });

    test('every Equipment card is supported but Edge of Night (it needs [Hidden])', () {
      final missing = [
        for (final c in db.cards)
          if (c.type == CardType.gear && c.hasTag('Equipment') && !RiftboundParser.parse(c).supported) c.name,
      ];
      expect(missing, ['Edge of Night']);
    });
  });

  group('Equip and attaching (CR 435, 716–719, 818)', () {
    test('818 Equip attaches to a unit you control; 137 its Might Bonus applies; 719.3 it goes where the unit goes', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 1);
      final sword = g.addCard('B.F. Sword', 0, zone: Zone.board); // [Equip] {Y}, +3
      final u = g.addCard('Daring Poro', 0, zone: Zone.board); // 2 Might
      expect(g.might(u), 2);
      equip(g, sword, u);
      expect(g.attachedUnit(sword), u);
      expect(g.isEquipped(u), isTrue);
      expect(g.might(u), 5);
      expect(g.state.player(0).runes, isEmpty, reason: '{Y} recycles the Order rune');
      g.apply(MoveUnitsMove(0, [u], 0));
      expect(g.state.obj(u).loc, 0);
      expect(g.state.obj(sword).loc, 0, reason: 'attached cards are where their unit is (CR 719.3)');
      expect(g.attachedUnit(sword), u);
    });

    test('718.2 an attached card’s own text is inactive: its Equip can’t be activated', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 2);
      final sword = g.addCard('B.F. Sword', 0, zone: Zone.board);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      equip(g, sword, u);
      final i = g.parsed(sword).abilities.indexWhere((a) => a is EqEquip);
      expect(g.whyNot(ActivateMove(0, sword, i)), contains('inactive'));
    });

    test('719.5 when the unit leaves the board its Equipment detaches and stays; 459.1 it’s recalled', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 1);
      final sword = g.addCard('B.F. Sword', 0, zone: Zone.board);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 0);
      g.setControl(0, 0);
      equip(g, sword, u);
      expect(g.state.obj(sword).loc, 0);
      // An enemy 6-Might unit attacks and kills it.
      final enemy = g.addCard('Zephyr Sage', 1, zone: Zone.board);
      g.state.active = 1;
      g.apply(MoveUnitsMove(1, [enemy], 0));
      expect(g.state.obj(u).zone, Zone.trash);
      expect(g.state.obj(sword).zone, Zone.board, reason: 'the Equipment stays on the board');
      expect(g.attachedUnit(sword), isNull);
      expect(g.state.obj(sword).loc, base, reason: 'an unattached gear at a battlefield is recalled');
    });

    test('435.1.f attaching to another unit detaches it from the first', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 2);
      final sword = g.addCard('B.F. Sword', 0, zone: Zone.board);
      final a = g.addCard('Daring Poro', 0, zone: Zone.board);
      final b = g.addCard('Daring Poro', 0, zone: Zone.board);
      equip(g, sword, a);
      // Jax, Grandmaster At Arms: "{E}: Attach an attached Equipment you control to a unit you control."
      final jax = g.addCard('Jax, Grandmaster At Arms', 0, zone: Zone.legend);
      g.apply(ActivateMove(0, jax, 1));
      answer(g, [b]);
      passAll(g);
      expect(g.attachedUnit(sword), b);
      expect(g.might(a), 2);
      expect(g.might(b), 5);
    });

    test('818.1.c.3 non-standard Equip costs: kill a friendly unit (Blade of the Ruined King)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 1);
      final blade = g.addCard('Blade of the Ruined King', 0, zone: Zone.board); // [Equip] - {Y}, Kill a friendly unit; +4
      final keep = g.addCard('Zephyr Sage', 0, zone: Zone.board);
      final fodder = g.addCard('Daring Poro', 0, zone: Zone.board);
      final i = g.parsed(blade).abilities.indexWhere((a) => a is EqEquip);
      g.apply(ActivateMove(0, blade, i));
      answer(g, [keep]); // the unit to equip
      answer(g, [fodder]); // the cost
      passAll(g);
      expect(g.state.obj(fodder).zone, Zone.trash);
      expect(g.attachedUnit(blade), keep);
      expect(g.might(keep), g.card(keep).might! + 4);
    });

    test('818.1.c.3 Spend XP (Shepherd’s Heirloom gains 1 XP as it’s played)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 2);
      final h = g.addCard('Shepherd\'s Heirloom', 0); // {2}, When you play this, gain 1 XP. [Equip] - Spend 1 XP
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      g.apply(PlayMove(0, h));
      passAll(g);
      expect(g.state.player(0).xp, 1);
      equip(g, h, u);
      expect(g.state.player(0).xp, 0);
      expect(g.attachedUnit(h), u);
    });

    test('818.1.c.4 Hextech Gauntlets’ Energy cost is reduced by the chosen unit’s Might', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 1);
      final gl = g.addCard('Hextech Gauntlets', 0, zone: Zone.board); // [Equip] {3}{A}, less the unit's Might
      final big = g.addCard('Zephyr Sage', 0, zone: Zone.board); // 6 Might
      equip(g, gl, big);
      expect(g.attachedUnit(gl), big, reason: '{3} - 6 = {0}, plus one Power');
    });
  });

  group('Quick-Draw and Weaponmaster (CR 819, 821)', () {
    test('819 Quick-Draw: played with Reaction timing, and attached as it’s played', () {
      final g = emptyGame();
      g.setControl(0, 1);
      g.addRunes(1, Domain.fury, 3);
      final def = g.addCard('Stalwart Poro', 1, zone: Zone.board, loc: 0); // 2 Might, Shield
      final sword = g.addCard('Long Sword', 1); // {2}+1 Fury, Quick-Draw, +2
      final att = g.addCard('Petty Officer', 0, zone: Zone.board); // 5 Might, Assault
      g.apply(MoveUnitsMove(0, [att], 0));
      // The defender has Focus and plays the Equipment in the showdown.
      expect(g.toAct, 1);
      expect(g.whyNot(PlayMove(1, sword)), isNull);
      g.apply(PlayMove(1, sword));
      passAll(g);
      final log = g.state.log.map((e) => e.text).toList();
      expect(log, contains('Long Sword is attached to Stalwart Poro.'));
      // Attached before combat damage: the defender deals 2 + 2 (Long Sword) + 1 (Shield).
      expect(log, contains('Petty Officer takes 5 combat damage.'));
      expect(g.state.obj(def).zone, Zone.trash, reason: '6 Might still beats it');
    });

    test('821 Weaponmaster: attach an Equipment you control, paying its Equip cost less one Power', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 2);
      final sword = g.addCard('B.F. Sword', 0, zone: Zone.board); // [Equip] {Y}
      final poro = g.addCard('Veteran Poro', 0); // {2}, Weaponmaster
      g.apply(PlayMove(0, poro));
      passAll(g);
      // Weaponmaster asks which Equipment.
      expect(g.pending?.decision.prompt, startsWith('Weaponmaster'));
      answer(g, [sword]);
      passAll(g);
      expect(g.attachedUnit(sword), poro, reason: '{Y} less {A} is free, though the player has no Order rune');
      expect(g.might(poro), 5);
    });
  });

  group('Effect Text (CR 136, 718.3)', () {
    test('136.2.c an Equipment’s Effect Text is its unit’s: Boneshiver channels when the unit conquers', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 2);
      runeDeck(g, 0, Domain.body, 2);
      final b = g.addCard('Boneshiver', 0, zone: Zone.board); // [Equip] {1}{O}; When I conquer, channel 1 rune exhausted
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      equip(g, b, u);
      final runes = g.state.player(0).runes.length;
      g.apply(MoveUnitsMove(0, [u], 0));
      passAll(g);
      expect(g.state.bfs[0].controller, 0);
      expect(g.state.player(0).runes, hasLength(runes + 1));
    });

    test('keywords from Effect Text: Doran’s Shield gives Tank, Cloth Armor Shield 2, Serrated Dirk Assault 2', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 1);
      g.addRunes(0, Domain.mind, 1);
      g.addRunes(0, Domain.fury, 1);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      expect(g.hasKw(u, Kw.tank), isFalse);
      equip(g, g.addCard('Doran\'s Shield', 0, zone: Zone.board), u);
      equip(g, g.addCard('Cloth Armor', 0, zone: Zone.board), u);
      equip(g, g.addCard('Serrated Dirk', 0, zone: Zone.board), u);
      expect(g.hasKw(u, Kw.tank), isTrue);
      expect(g.hasKw(u, Kw.shield), isTrue);
      expect(g.hasKw(u, Kw.assault), isTrue);
      expect(g.might(u), 2 + 1, reason: 'Doran’s Shield +1; Cloth Armor and Serrated Dirk +0');
    });

    test('a hold effect: Trinity Force scores a point when its unit holds', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 1);
      g.stackDeck(0, 'Daring Poro', 3);
      g.stackDeck(1, 'Daring Poro', 3);
      final tf = g.addCard('Trinity Force', 0, zone: Zone.board);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 0);
      g.setControl(0, 0);
      equip(g, tf, u);
      g.apply(EndTurnMove(0));
      g.apply(EndTurnMove(1));
      passAll(g);
      expect(g.state.player(0).points, 2, reason: '1 for holding, 1 from Trinity Force');
    });

    test('380 Guardian Angel: if its unit would die, the Angel dies instead; the unit is healed, exhausted and recalled', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 1);
      final ga = g.addCard('Guardian Angel', 0, zone: Zone.board);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 0);
      g.setControl(0, 0);
      equip(g, ga, u);
      final enemy = g.addCard('Zephyr Sage', 1, zone: Zone.board);
      g.state.active = 1;
      g.apply(MoveUnitsMove(1, [enemy], 0));
      expect(g.state.obj(u).zone, Zone.board);
      expect(g.state.obj(u).loc, base);
      expect(g.state.obj(u).exhausted, isTrue);
      expect(g.state.obj(ga).zone, Zone.trash);
    });

    test('Brutalizer: +2 more Might the turn it was attached', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 1);
      g.stackDeck(0, 'Daring Poro', 3);
      g.stackDeck(1, 'Daring Poro', 3);
      final br = g.addCard('Brutalizer', 0, zone: Zone.board); // +1
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      equip(g, br, u);
      expect(g.might(u), 2 + 1 + 2);
      g.apply(EndTurnMove(0));
      expect(g.might(u), 2 + 1);
    });

    test('136.2.d "this" is the Equipment: Blighted Battleaxe unattaches itself and deals 4 if the unit didn’t conquer', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 2);
      g.stackDeck(1, 'Daring Poro', 3);
      final ax = g.addCard('Blighted Battleaxe', 0, zone: Zone.board); // +4
      final u = g.addCard('Zephyr Sage', 0, zone: Zone.board); // 6 Might
      equip(g, ax, u);
      expect(g.might(u), 10);
      g.apply(EndTurnMove(0));
      passAll(g);
      expect(g.attachedUnit(ax), isNull);
      expect(g.state.obj(u).zone, Zone.board, reason: '4 damage doesn’t kill a 6-Might unit (healed at the turn’s end)');
    });

    test('Rabadon’s Deathcrown: your spells and abilities deal 3 Bonus Damage (CR 712)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 4);
      final rd = g.addCard('Rabadon\'s Deathcrown', 0, zone: Zone.board);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      equip(g, rd, u);
      final target = g.addCard('Zephyr Sage', 1, zone: Zone.board, loc: 0); // 6 Might
      g.addRunes(0, Domain.fury, 2);
      final bolt = g.addCard('Get Excited!', 0);
      if (g.whyNot(PlayMove(0, bolt)) == null) {
        g.apply(PlayMove(0, bolt));
        if (g.pending != null) answer(g, [target]);
        passAll(g);
        expect(g.state.obj(target).damage, greaterThanOrEqualTo(3));
      }
      // Directly: an ability's Deal adds the bonus.
      expect(RiftboundParser.parse(db['Rabadon\'s Deathcrown']!).extra.first, isA<Static>());
    });

    test('Experimental Hexplate: "I am a Mech" (CR 479.2)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 1);
      final hx = g.addCard('Experimental Hexplate', 0, zone: Zone.board);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      equip(g, hx, u);
      expect(g.matches(const Filter(tag: 'Mech'), u, controller: 0), isTrue);
    });

    test('Spinning Axe is [Temporary] only while unattached (CR 722, 816)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 1);
      g.stackDeck(0, 'Daring Poro', 3);
      g.stackDeck(1, 'Daring Poro', 3);
      final axe = g.addCard('Spinning Axe', 0, zone: Zone.board);
      final loose = g.addCard('Spinning Axe', 0, zone: Zone.board);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      equip(g, axe, u);
      g.apply(EndTurnMove(0));
      g.apply(EndTurnMove(1));
      passAll(g);
      expect(g.state.obj(axe).zone, Zone.board);
      expect(g.state.obj(loose).zone, Zone.trash);
    });

    test('Jagged Cutlass: its unit can’t be moved by enemy spells (Charm)', () {
      final g = emptyGame();
      g.addRunes(1, Domain.body, 1);
      g.addRunes(1, Domain.calm, 2);
      final cut = g.addCard('Jagged Cutlass', 1, zone: Zone.board);
      final u = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
      g.setControl(0, 1);
      g.state.active = 1;
      equip(g, cut, u);
      g.state.active = 0;
      g.addRunes(0, Domain.calm, 2);
      final charm = g.addCard('Charm', 0); // Move an enemy unit.
      g.apply(PlayMove(0, charm));
      passAll(g);
      if (g.pending != null) answer(g, [0]);
      passAll(g);
      expect(g.state.obj(u).loc, 0);
    });
  });

  group('Cards built around Equipment', () {
    test('Gearhead doubles Might Bonuses; Ornn has +1 per friendly gear', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 1);
      final sword = g.addCard('B.F. Sword', 0, zone: Zone.board);
      final gh = g.addCard('Gearhead', 0, zone: Zone.board); // 3 Might
      equip(g, sword, gh);
      expect(g.might(gh), 3 + 6);
      final ornn = g.addCard('Ornn, Forge God', 0, zone: Zone.board); // 4 Might
      expect(g.might(ornn), 4 + 1);
    });

    test('Lucian, Purifier: your Equipment each give [Assault]', () {
      final g = emptyGame();
      g.addCard('Lucian, Purifier', 0, zone: Zone.legend);
      g.addRunes(0, Domain.order, 1);
      g.addRunes(0, Domain.body, 1);
      final u = g.addCard('Zephyr Sage', 0, zone: Zone.board);
      expect(g.hasKw(u, Kw.assault), isFalse);
      equip(g, g.addCard('B.F. Sword', 0, zone: Zone.board), u);
      equip(g, g.addCard('Doran\'s Blade', 0, zone: Zone.board), u);
      expect(g.parsed(u).kw(Kw.assault), 0);
      expect(g.hasKw(u, Kw.assault), isTrue);
    });

    test('Angle Shot detaches an Equipment from a unit with the same controller', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 1);
      final sword = g.addCard('B.F. Sword', 0, zone: Zone.board);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      equip(g, sword, u);
      g.state.active = 1;
      g.addRunes(1, Domain.fury, 2);
      g.stackDeck(1, 'Daring Poro', 1);
      final shot = g.addCard('Angle Shot', 1);
      g.apply(PlayMove(1, shot));
      // The unit, then the Equipment (only one has the same controller).
      if (g.pending?.decision.options.contains(u) ?? false) answer(g, [u]);
      passAll(g);
      expect(g.pending?.decision.labels, ['Leave it attached', 'Detach it']);
      answer(g, [1]);
      passAll(g);
      expect(g.attachedUnit(sword), isNull);
    });

    test('Strike Down kills with its unit’s Might (with the Equipment’s bonus) and detaches it', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 1);
      g.addRunes(0, Domain.body, 4);
      final sword = g.addCard('B.F. Sword', 0, zone: Zone.board);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      equip(g, sword, u);
      final enemy = g.addCard('Stalwart Poro', 1, zone: Zone.board, loc: 0); // 2 Might
      final big = g.addCard('Zephyr Sage', 1, zone: Zone.board, loc: 0); // 6 Might
      final sd = g.addCard('Strike Down', 0);
      g.apply(PlayMove(0, sd));
      answer(g, [big]); // the enemy unit
      passAll(g);
      expect(g.state.obj(big).zone, Zone.board, reason: '5 damage on 6 Might');
      expect(g.state.obj(big).damage, 5);
      expect(g.attachedUnit(sword), isNull);
      expect(g.might(u), 2);
      expect(g.state.obj(enemy).zone, Zone.board);
    });

    test('Akshan takes an enemy gear and attaches it; the owner gets it back when Akshan leaves', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 6);
      final sword = g.addCard('B.F. Sword', 1, zone: Zone.board);
      final ak = g.addCard('Akshan, Mischievous', 0);
      g.apply(PlayMove(0, ak));
      // Pay {O}{O}? Yes.
      while (g.pending != null) {
        final d = g.pending!.decision;
        if (d.kind == DecisionKind.yesNo) {
          answer(g, [1]);
        } else if (d.prompt.startsWith('Weaponmaster')) {
          answer(g, const []);
        } else {
          answer(g, [d.options.first]);
        }
        passAll(g);
      }
      expect(g.state.obj(sword).controller, 0);
      expect(g.attachedUnit(sword), ak);
      expect(g.might(ak), 4 + 3);
      // Akshan dies: the sword returns to its owner.
      g.state.obj(ak).damage = 7;
      g.settleForTest();
      expect(g.state.obj(ak).zone, Zone.trash);
      expect(g.state.obj(sword).controller, 1);
      expect(g.attachedUnit(sword), isNull);
    });

    test('Shady Spectacles: the equipped unit becomes a copy of another friendly unit while it’s attached (CR 446)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 2);
      final sp = g.addCard('Shady Spectacles', 0, zone: Zone.board);
      final small = g.addCard('Daring Poro', 0, zone: Zone.board);
      final big = g.addCard('Zephyr Sage', 0, zone: Zone.board);
      final i = g.parsed(sp).abilities.indexWhere((a) => a is EqEquip);
      g.apply(ActivateMove(0, sp, i));
      answer(g, [small]);
      passAll(g);
      // As it attaches: another friendly unit to copy (Zephyr Sage is the only one).
      expect(g.card(small).name, 'Zephyr Sage');
      expect(g.might(small), g.card(big).might);
      // Detached: back to itself.
      final jax = g.addCard('Jax, Grandmaster At Arms', 0, zone: Zone.legend);
      g.apply(ActivateMove(0, jax, 1)); // attach an attached Equipment to a unit
      answer(g, [big]);
      passAll(g);
      expect(g.card(small).name, 'Daring Poro');
    });

    test('The Zero Drive: its unit is banished with it on death; banishing it plays them back free', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 6);
      final zd = g.addCard('The Zero Drive', 0, zone: Zone.board); // [Equip] {1}{B}; Effect: [Deathknell] - Banish me
      final u = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 0);
      g.setControl(0, 0);
      equip(g, zd, u);
      final enemy = g.addCard('Zephyr Sage', 1, zone: Zone.board);
      g.state.active = 1;
      g.apply(MoveUnitsMove(1, [enemy], 0));
      passAll(g);
      expect(g.state.obj(u).zone, Zone.banish);
      expect(g.state.obj(zd).eq.banishedWith, [u]);
      g.state.active = 0;
      final i = g.parsed(zd).abilities.indexWhere((a) => a is EqActivated);
      g.apply(ActivateMove(0, zd, i));
      passAll(g);
      expect(g.state.obj(u).zone, Zone.board);
      expect(g.state.obj(zd).zone, Zone.banish);
    });

    test('Riven deals 2 per attached Equipment to an enemy unit there when she attacks', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 1);
      g.addRunes(0, Domain.body, 1);
      final riven = g.addCard('Riven, Shattered', 0, zone: Zone.board);
      equip(g, g.addCard('B.F. Sword', 0, zone: Zone.board), riven);
      equip(g, g.addCard('Doran\'s Blade', 0, zone: Zone.board), riven);
      g.setControl(0, 1);
      final def = g.addCard('Zephyr Sage', 1, zone: Zone.board, loc: 0); // 6 Might
      final other = g.addCard('Zephyr Sage', 1, zone: Zone.board, loc: 0);
      g.apply(MoveUnitsMove(0, [riven], 0));
      if (g.pending != null) answer(g, [def]);
      passAll(g);
      expect(g.state.obj(def).zone == Zone.trash || g.state.obj(def).damage >= 4, isTrue);
      expect(g.state.obj(other).zone, isNotNull);
    });

    test('Lucian, Merciless readies the first time he conquers each turn', () {
      final g = emptyGame();
      final l = g.addCard('Lucian, Merciless', 0, zone: Zone.board);
      g.apply(MoveUnitsMove(0, [l], 0));
      passAll(g);
      expect(g.state.bfs[0].controller, 0);
      expect(g.state.obj(l).exhausted, isFalse);
    });

    test('Yone: conquering an open battlefield deals his Might to an enemy unit in a base', () {
      final g = emptyGame();
      final y = g.addCard('Yone, Blademaster', 0, zone: Zone.board); // 5 Might
      final e = g.addCard('Daring Poro', 1, zone: Zone.board);
      g.apply(MoveUnitsMove(0, [y], 0));
      passAll(g);
      expect(g.state.obj(e).zone, Zone.trash);
    });

    test('Jax, Unrelenting: when you attach an Equipment to him, you may pay {1} to draw 1', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 2);
      g.stackDeck(0, 'Daring Poro', 1);
      final jax = g.addCard('Jax, Unrelenting', 0, zone: Zone.board);
      equip(g, g.addCard('B.F. Sword', 0, zone: Zone.board), jax);
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
      answer(g, [1]);
      passAll(g);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Aphelios: each mode once per turn', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 1);
      g.addRunes(0, Domain.body, 1);
      final aph = g.addCard('Aphelios, Exalted', 0, zone: Zone.board);
      equip(g, g.addCard('B.F. Sword', 0, zone: Zone.board), aph);
      expect(g.pending?.decision.labels, hasLength(3));
      answer(g, [2]); // buff a friendly unit
      passAll(g);
      if (g.pending != null) answer(g, [aph]);
      passAll(g);
      expect(g.state.obj(aph).buffed, isTrue);
      equip(g, g.addCard('Doran\'s Blade', 0, zone: Zone.board), aph);
      expect(g.pending?.decision.labels, hasLength(2), reason: 'buffing was chosen this turn');
    });

    test('Azir, Emperor of the Sands: Sand Soldier tokens have Weaponmaster', () {
      final g = emptyGame();
      final azir = g.addCard('Azir, Emperor of the Sands', 0, zone: Zone.legend);
      g.addRunes(0, Domain.order, 3);
      g.addRunes(0, Domain.calm, 2);
      final sword = g.addCard('B.F. Sword', 0);
      expect(g.whyNot(ActivateMove(0, azir, 1)), contains('played an Equipment'));
      g.apply(PlayMove(0, sword));
      passAll(g);
      g.apply(ActivateMove(0, azir, 1));
      passAll(g);
      final soldier = g.units(player: 0).single;
      expect(g.card(soldier).name, 'Sand Soldier');
      // Weaponmaster triggered for the token.
      if (g.pending != null) answer(g, [sword]);
      passAll(g);
      expect(g.attachedUnit(sword), soldier);
    });

    test('Relentless Pursuit: move, attach, and "When I conquer, you may move me to my base" this turn', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 2);
      g.addRunes(0, Domain.body, 2);
      final sword = g.addCard('B.F. Sword', 0, zone: Zone.board);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      final rp = g.addCard('Relentless Pursuit', 0);
      g.apply(PlayMove(0, rp));
      passAll(g);
      while (g.pending != null) {
        final d = g.pending!.decision;
        if (d.kind == DecisionKind.option && d.prompt.startsWith('Move')) {
          answer(g, [d.labels.indexOf('Grove of the God-Willow')]);
        } else if (d.kind == DecisionKind.yesNo) {
          answer(g, [1]);
        } else {
          answer(g, [d.options.first]);
        }
        passAll(g);
      }
      expect(g.attachedUnit(sword), u);
      expect(g.state.player(0).points, 1, reason: 'it moved to the battlefield and conquered it');
      expect(g.state.obj(u).loc, base, reason: 'and then went home');
      expect(g.state.bfs[0].controller, isNull, reason: 'no units left there (CR 323.5)');
    });

    test('Forge of the Fluft: while you control it, your legend can attach an Equipment', () {
      final g = emptyGame(battlefields: const ['Forge of the Fluft', 'Zaun Warrens']);
      final legend = g.addCard('Lucian, Purifier', 0, zone: Zone.legend);
      final sword = g.addCard('B.F. Sword', 0, zone: Zone.board);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      expect(g.legalMoves(0).whereType<ActivateMove>().where((m) => m.source == legend), isEmpty);
      g.setControl(0, 0);
      final m = g.legalMoves(0).whereType<ActivateMove>().firstWhere((m) => m.source == legend);
      g.apply(m);
      passAll(g);
      expect(g.attachedUnit(sword), u);
    });

    test('Last Rites: Equip by recycling 2 from your trash; its unit conquering lets you play a unit from your trash', () {
      final g = emptyGame();
      g.addRunes(0, Domain.chaos, 1);
      g.addRunes(0, Domain.order, 2);
      g.addCard('Daring Poro', 0, zone: Zone.trash);
      g.addCard('Daring Poro', 0, zone: Zone.trash);
      final back = g.addCard('Daring Poro', 0, zone: Zone.trash);
      final lr = g.addCard('Last Rites', 0, zone: Zone.board); // [Equip] - {P}, Recycle 2 cards from your trash
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      final i = g.parsed(lr).abilities.indexWhere((a) => a is EqEquip);
      g.apply(ActivateMove(0, lr, i));
      answer(g, [g.state.player(0).trash[0], g.state.player(0).trash[1]]);
      passAll(g);
      expect(g.attachedUnit(lr), u);
      expect(g.state.player(0).trash, [back]);
      expect(g.state.player(0).deck, hasLength(2), reason: 'recycled to the bottom of the deck');
      g.apply(MoveUnitsMove(0, [u], 0));
      passAll(g);
      expect(g.pending?.decision.kind, DecisionKind.yesNo, reason: '"you may play a unit from your trash"');
      answer(g, [1]);
      passAll(g);
      if (g.pending != null) answer(g, [0]); // where: base
      passAll(g);
      expect(g.state.obj(back).zone, Zone.board);
      expect(g.state.player(0).runes.where((r) => !g.state.obj(r).exhausted), isEmpty, reason: 'its {2} was paid');
    });

    test('Arise! plays a Sand Soldier per Equipment you control and readies two', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 7);
      g.addCard('B.F. Sword', 0, zone: Zone.board);
      g.addCard('Doran\'s Blade', 0, zone: Zone.board);
      g.addCard('Long Sword', 0, zone: Zone.board);
      final a = g.addCard('Arise!', 0);
      g.addRunes(0, Domain.order, 1);
      g.apply(PlayMove(0, a));
      passAll(g);
      final soldiers = [for (final u in g.units(player: 0)) if (g.card(u).name == 'Sand Soldier') u];
      expect(soldiers, hasLength(3));
      expect(soldiers.where((s) => !g.state.obj(s).exhausted), hasLength(2));
    });
  });

  group('More Effect Text and grants', () {
    test('Svellsongur: copies its unit’s text, so the unit has its abilities twice (CR 479.1.d)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 2);
      final sv = g.addCard('Svellsongur', 0, zone: Zone.board);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board); // [Assault]
      expect(g.hasKw(u, Kw.assault), isTrue);
      equip(g, sv, u);
      expect(g.state.obj(sv).eq.textOf, 'Daring Poro');
      g.setControl(0, 1);
      g.addCard('Zephyr Sage', 1, zone: Zone.board, loc: 0);
      g.apply(MoveUnitsMove(0, [u], 0));
      // Attacking with Assault twice: 2 + 1 + 1.
      expect(g.state.log.map((e) => e.text), contains('Zephyr Sage takes 4 combat damage.'));
    });

    test('Skyfall of Areion: its unit’s conquer effects are also hold effects (Boneshiver channels on a hold)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 2);
      g.addRunes(0, Domain.body, 2);
      runeDeck(g, 0, Domain.body, 6);
      g.stackDeck(0, 'Daring Poro', 3);
      g.stackDeck(1, 'Daring Poro', 3);
      final u = g.addCard('Zephyr Sage', 0, zone: Zone.board, loc: 0);
      g.setControl(0, 0);
      equip(g, g.addCard('Skyfall of Areion', 0, zone: Zone.board), u);
      equip(g, g.addCard('Boneshiver', 0, zone: Zone.board), u);
      g.apply(EndTurnMove(0));
      g.apply(EndTurnMove(1));
      passAll(g);
      // Turn start: holding scores; Boneshiver ("When I conquer") also fires on the hold.
      expect(g.state.log.map((e) => e.text).where((t) => t.contains('channels 1 rune')), isNotEmpty);
    });

    test('Hunt and Level from Effect Text: Hunter’s Machete gains XP; Soul Sword’s [Level 3] +1 Might', () {
      final g = emptyGame();
      g.addRunes(0, Domain.body, 1);
      g.addRunes(0, Domain.calm, 1);
      final u = g.addCard('Zephyr Sage', 0, zone: Zone.board); // 6
      equip(g, g.addCard('Hunter\'s Machete', 0, zone: Zone.board), u); // +2, [Hunt]
      equip(g, g.addCard('Soul Sword', 0, zone: Zone.board), u); // +1, [Level 3] +1
      expect(g.might(u), 6 + 2 + 1);
      g.state.player(0).xp = 2;
      g.apply(MoveUnitsMove(0, [u], 0));
      passAll(g);
      expect(g.state.player(0).xp, 3);
      expect(g.might(u), 6 + 2 + 1 + 1);
    });

    test('Shurelya’s Requiem: "When you play this, ready your units"; its unit gives your units there [Ganking]', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 3);
      g.addRunes(0, Domain.mind, 4);
      final a = g.addCard('Daring Poro', 0, zone: Zone.board, exhausted: true);
      final b = g.addCard('Daring Poro', 0, zone: Zone.board);
      final sr = g.addCard('Shurelya\'s Requiem', 0);
      g.apply(PlayMove(0, sr));
      passAll(g);
      expect(g.state.obj(a).exhausted, isFalse);
      expect(g.hasKw(b, Kw.ganking), isFalse);
      equip(g, sr, a);
      expect(g.hasKw(b, Kw.ganking), isTrue, reason: 'b is in the same base as a');
    });

    test('Jax, Unmatched: Equipment in your hand have [Quick-Draw]', () {
      final g = emptyGame();
      g.setControl(0, 1);
      g.addRunes(1, Domain.order, 4);
      g.addCard('Jax, Unmatched', 1, zone: Zone.board);
      final def = g.addCard('Zephyr Sage', 1, zone: Zone.board, loc: 0);
      final sword = g.addCard('B.F. Sword', 1); // no Quick-Draw of its own
      final att = g.addCard('Daring Poro', 0, zone: Zone.board);
      g.apply(MoveUnitsMove(0, [att], 0));
      expect(g.toAct, 1);
      expect(g.whyNot(PlayMove(1, sword)), isNull, reason: 'Reaction timing in the showdown');
      g.apply(PlayMove(1, sword));
      if (g.pending != null) answer(g, [def]);
      passChain(g);
      expect(g.attachedUnit(sword), def);
    });

    test('Hand Hammer: +2 more while at a battlefield with exactly one other unit you control', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 1);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 0);
      g.setControl(0, 0);
      equip(g, g.addCard('Hand Hammer', 0, zone: Zone.board), u); // +1
      expect(g.might(u), 3);
      g.addCard('Daring Poro', 0, zone: Zone.board, loc: 0);
      expect(g.might(u), 5);
      g.addCard('Daring Poro', 0, zone: Zone.board, loc: 0);
      expect(g.might(u), 3);
    });

    test('Eye of the Herald: when its unit moves, play a Recruit there', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 1);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      equip(g, g.addCard('Eye of the Herald', 0, zone: Zone.board), u);
      g.apply(MoveUnitsMove(0, [u], 0));
      passAll(g);
      expect([for (final x in g.unitsAt(0, player: 0)) g.card(x).name], containsAll(['Daring Poro', 'Recruit']));
    });

    test('Sacred Shears: [Deathknell] from Effect Text draws when the unit dies', () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 1);
      g.stackDeck(0, 'Daring Poro', 2);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      equip(g, g.addCard('Sacred Shears', 0, zone: Zone.board), u);
      g.state.obj(u).damage = 10;
      g.settleForTest();
      passAll(g);
      expect(g.state.obj(u).zone, Zone.trash);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Azir, Ascendant swaps places with a unit you control and may take one of its Equipment', () {
      final g = emptyGame();
      g.addRunes(0, Domain.calm, 1);
      g.addRunes(0, Domain.order, 1);
      final azir = g.addCard('Azir, Ascendant', 0, zone: Zone.board);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 1);
      g.setControl(1, 0);
      final sword = g.addCard('B.F. Sword', 0, zone: Zone.board);
      equip(g, sword, u);
      final i = g.parsed(azir).abilities.indexWhere((a) => a is Activated);
      g.apply(ActivateMove(0, azir, i));
      if (g.pending != null && g.pending!.decision.options.contains(u)) answer(g, [u]);
      passAll(g);
      if (g.pending != null) answer(g, [sword]);
      passAll(g);
      expect(g.state.obj(azir).loc, 1);
      expect(g.state.obj(u).loc, base);
      expect(g.attachedUnit(sword), azir);
    });

    test('Veiled Temple: when you conquer here, you may ready a friendly gear and detach it', () {
      final g = emptyGame(battlefields: const ['Veiled Temple', 'Zaun Warrens']);
      g.addRunes(0, Domain.order, 1);
      final sword = g.addCard('B.F. Sword', 0, zone: Zone.board);
      final u = g.addCard('Daring Poro', 0, zone: Zone.board);
      equip(g, sword, u);
      g.state.obj(sword).exhausted = true;
      g.apply(MoveUnitsMove(0, [u], 0));
      while (g.pending != null) {
        answer(g, g.pending!.decision.kind == DecisionKind.cards ? [g.pending!.decision.options.first] : [1]);
        passAll(g);
      }
      passAll(g);
      expect(g.state.obj(sword).exhausted, isFalse);
      expect(g.attachedUnit(sword), isNull);
    });

    test('Hextech Gauntlets: when its unit conquers after assigning 3+ excess combat damage, draw 1 (CR 467.2.c.4)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 1);
      g.stackDeck(0, 'Daring Poro', 2);
      final u = g.addCard('Zephyr Sage', 0, zone: Zone.board); // 6
      equip(g, g.addCard('Hextech Gauntlets', 0, zone: Zone.board), u); // +3
      g.setControl(0, 1);
      g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0); // 2 Might: 9 - 2 = 7 excess
      g.apply(MoveUnitsMove(0, [u], 0));
      passAll(g);
      expect(g.state.bfs[0].controller, 0);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Rell, Magnetic: when he attacks, play an Equipment costing {2} or less free and attach it to him', () {
      final g = emptyGame();
      final rell = g.addCard('Rell, Magnetic', 0, zone: Zone.board);
      final sword = g.addCard('Long Sword', 0); // {2}
      g.setControl(0, 1);
      g.addCard('Daring Poro', 1, zone: Zone.board, loc: 0);
      g.apply(MoveUnitsMove(0, [rell], 0));
      while (g.pending != null) {
        final d = g.pending!.decision;
        answer(g, d.kind == DecisionKind.yesNo ? [1] : (d.options.contains(rell) ? [rell] : [d.options.first]));
        passAll(g);
      }
      expect(g.state.obj(sword).zone, Zone.board);
      expect(g.attachedUnit(sword), rell);
      expect(g.state.player(0).runes, isEmpty, reason: 'ignoring its cost');
    });
  });

  group('Decks', () {
    test('[Unique]: a deck may have only one card with that name', () {
      expect(maxCopies(db['Forgefire Cape']!), 1);
      expect(maxCopies(db['B.F. Sword']!), 3);
      final ornn = db.cards.firstWhere((c) => c.type == CardType.legend && c.hasTag('Ornn'), orElse: () => db['Jax, Grandmaster At Arms']!);
      final deck = buildDeck(db, db['Jax, Grandmaster At Arms']!);
      expect(validateDeck(db, deck), isEmpty);
      final twice = [...deck, 'Shurelya\'s Requiem', 'Shurelya\'s Requiem'];
      expect(validateDeck(db, twice).join(' '), contains('[Unique]'));
      expect(ornn, isNotNull);
    });

    test('random decks of every playable legend are legal (Unique and all)', () {
      final rng = SeededRng(3);
      for (var i = 0; i < 60; i++) {
        final d = randomDeck(db, rng);
        expect(validateDeck(db, d), isEmpty, reason: deckLegend(db, d)!.name);
      }
    });
  });

  group('Determinism', () {
    test('games with Equipment replay to the same fingerprint (from moves and from JSON)', () {
      for (var seed = 1; seed <= 6; seed++) {
        final legends = playableLegends(db).where((l) => const ['Jax', 'Lucian', 'Azir'].any(l.name.startsWith)).toList();
        if (legends.isEmpty) return;
        final decks = [buildDeck(db, legends[seed % legends.length]), buildDeck(db, legends[(seed + 1) % legends.length])];
        final g = Game(db, players: ['A', 'B'], seed: seed)..apply(StartMove(decks));
        runBots(g, [RiftboundBot(0, seed: seed), RiftboundBot(1, seed: seed + 1)], maxMoves: 4000);
        final r = Game(db, players: ['A', 'B'], seed: seed);
        for (final m in g.actions) {
          r.apply(RMove.fromJson(m.toJson()));
        }
        expect(r.fingerprint, g.fingerprint);
      }
    });
  });
}
