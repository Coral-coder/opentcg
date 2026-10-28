import 'package:riftbound/riftbound.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Wave 2, slice 2: Forgotten Library … Ravenbloom Prefect, with real cards.

ObjId put(Game g, String key, int p, {int loc = base, bool exhausted = false}) => g.addCard(key, p, zone: Zone.board, loc: loc, exhausted: exhausted);

/// A facedown card of [p]'s at battlefield [bf] (CR 107.3).
ObjId facedown(Game g, String key, int p, int bf) {
  final id = g.addCard(key, p, zone: Zone.facedown);
  g.state.obj(id)
    ..loc = bf
    ..controller = p;
  return id;
}

/// Ends player 0's turn and player 1's, answering with defaults, back to player 0's Main Phase.
void roundTrip(Game g) {
  g.apply(const EndTurnMove(0));
  while (g.pending != null) {
    answer(g, Game.defaultAnswer(g.pending!.decision));
  }
  passAll(g);
  g.apply(const EndTurnMove(1));
  while (g.pending != null && g.pending!.decision.player == 1) {
    answer(g, Game.defaultAnswer(g.pending!.decision));
  }
  passAll(g);
}

ParsedCard read(String name) => RiftboundParser.parse(db[name]!);

void main() {
  test('every card of the slice is fully supported', () {
    const names = [
      'Forgotten Library', 'Forgotten Relic', 'Forgotten Signpost', 'Fortified Position', 'Garen, Rugged', 'Gutter Palace', 'Hallowed Tomb', 'Heimerdinger, Inventor', 'Here to Help', 'Hextech Anomaly', //
      'Hwei, Brooding Painter', 'Illaoi, Prophet of the Great Kraken', 'Ivern, Friend to All', 'Ivern, Green Father', 'Jayce, Brilliant Inventor', 'Jhin, Virtuoso', 'Katarina, Reckless', 'Kato the Arm', //
      'Kayn, Unleashed', "King's Edict", 'Laurent Bladekeeper', 'LeBlanc, Deceiver', 'LeBlanc, Everywhere At Once', 'Lux, Crownguard', 'Mageseeker Investigator', 'Mirror Image', 'Monster Harpoon', //
      'Mushroom Pouch', 'Mystic Reversal', 'Nasus, Guardian of Knowledge', 'Noxian Guillotine', 'Ornn, Fire Below the Mountain', 'Otterpus', 'Party Favors', 'Ravenbloom Prefect', 'Brush',
    ];
    for (final n in names) {
      final p = read(n);
      expect(p.unsupported, isEmpty, reason: n);
    }
  });

  group('Keywords (CR 807, 810, 814)', () {
    test('Garen, Rugged: "[Assault 2], [Shield 2]"; Laurent Bladekeeper: Ganking without brackets', () {
      final garen = read('Garen, Rugged');
      expect(garen.kw(Kw.assault), 2);
      expect(garen.kw(Kw.shield), 2);
      expect(read('Laurent Bladekeeper').has(Kw.ganking), isTrue);
    });
  });

  group('Facedown cards (CR 107.3, 811)', () {
    test('Monster Harpoon deals 4 instead of 2 while you control a facedown card', () {
      for (final hidden in [false, true]) {
        final g = emptyGame();
        g.setControl(0, 0);
        g.addRunes(0, Domain.fury, 2);
        final target = put(g, 'Vanguard Sergeant', 1, loc: 1); // 4 Might
        if (hidden) facedown(g, 'Pakaa Cub', 0, 0);
        final harpoon = g.addCard('Monster Harpoon', 0);
        g.apply(PlayMove(0, harpoon));
        if (g.pending != null) answer(g, [target]);
        passAll(g);
        expect(g.state.obj(target).zone, hidden ? Zone.trash : Zone.board, reason: hidden ? '4 damage kills it' : '2 damage doesn’t');
      }
    });

    test('Mushroom Pouch draws 1 at the start of your turn if you control a facedown card', () {
      final hands = <int>[];
      for (final hidden in [false, true]) {
        final g = emptyGame();
        g.stackDeck(0, 'Shipyard Skulker', 5);
        g.stackDeck(1, 'Shipyard Skulker', 5);
        g.setControl(0, 0);
        put(g, 'Mushroom Pouch', 0);
        put(g, 'Vanguard Sergeant', 0, loc: 0);
        if (hidden) facedown(g, 'Pakaa Cub', 0, 0);
        roundTrip(g);
        hands.add(g.state.player(0).hand.length);
      }
      expect(hands[1], hands[0] + 1);
    });

    test('Katarina, Reckless readies when you hide a card, and deals 2 when you play one from face down', () {
      final g = emptyGame();
      g.stackDeck(0, 'Shipyard Skulker', 5);
      g.stackDeck(1, 'Shipyard Skulker', 5);
      g.setControl(0, 0);
      g.addRunes(0, Domain.body, 1);
      put(g, 'Vanguard Sergeant', 0, loc: 0);
      final kat = put(g, 'Katarina, Reckless', 0, exhausted: true);
      final cub = g.addCard('Pakaa Cub', 0); // [Hidden]
      g.apply(HideMove(0, cub));
      passAll(g);
      expect(g.state.obj(kat).exhausted, isFalse, reason: 'When you hide a card, ready me');
      final enemy = put(g, 'Shipyard Skulker', 1, loc: 1); // 3 Might
      roundTrip(g);
      g.apply(PlayMove(0, cub));
      while (g.pending != null) {
        answer(g, g.pending!.decision.options.contains(enemy) ? [enemy] : Game.defaultAnswer(g.pending!.decision));
      }
      passAll(g);
      expect(g.state.obj(enemy).damage, 2);
    });
  });

  group('Winning, champions and battlefields', () {
    test('Gutter Palace: exactly 4 cards in hand and 4 units at battlefields at the start of your turn wins', () {
      final g = emptyGame();
      g.stackDeck(0, 'Shipyard Skulker', 5);
      g.stackDeck(1, 'Shipyard Skulker', 5);
      g.setControl(0, 0);
      put(g, 'Gutter Palace', 0);
      for (var i = 0; i < 4; i++) {
        put(g, 'Shipyard Skulker', 0, loc: 0);
        g.addCard('Shipyard Skulker', 0);
      }
      roundTrip(g);
      expect(g.over, isTrue);
      expect(g.state.winner, 0);
    });

    test('Gutter Palace: Discard 1, {E}: a 1 Might Bird token with Deflect (CR 187.7)', () {
      final g = emptyGame();
      final palace = put(g, 'Gutter Palace', 0);
      g.addCard('Shipyard Skulker', 0);
      g.apply(ActivateMove(0, palace, 1));
      passAll(g);
      final bird = g.units(player: 0).single;
      expect(g.nameOf(bird), 'Bird');
      expect(g.hasKw(bird, Kw.deflect), isTrue);
      expect(g.state.player(0).hand, isEmpty);
    });

    test('Hallowed Tomb returns your Chosen Champion from the trash when you hold it (CR 108.3)', () {
      final g = emptyGame(battlefields: const ['Hallowed Tomb', 'Zaun Warrens']);
      g.stackDeck(0, 'Shipyard Skulker', 5);
      g.stackDeck(1, 'Shipyard Skulker', 5);
      g.setControl(0, 0);
      put(g, 'Vanguard Sergeant', 0, loc: 0);
      final champ = g.addCard('Garen, Rugged', 0, zone: Zone.trash);
      g.state.marks['champ:0'] = champ;
      roundTrip(g);
      while (g.pending != null) {
        answer(g, const [1]);
        passAll(g);
      }
      expect(g.state.player(0).champion, champ);
      expect(g.state.obj(champ).zone, Zone.champion);
    });

    test('Ivern, Green Father replaces a battlefield with a Brush, and the Brush can put it back (CR 187.8)', () {
      final g = emptyGame();
      g.stackDeck(0, 'Shipyard Skulker', 5);
      g.stackDeck(1, 'Shipyard Skulker', 5);
      g.addCard('Ivern, Green Father', 0, zone: Zone.legend);
      final grove = g.state.bfs[0].obj;
      final u = put(g, 'Vanguard Sergeant', 0);
      g.apply(MoveUnitsMove(0, [u], 0)); // conquer the empty battlefield
      while (g.pending != null || g.state.chain.isNotEmpty) {
        if (g.pending != null) {
          answer(g, const [1]);
        } else {
          passAll(g);
        }
      }
      final brush = g.state.bfs[0].obj;
      expect(g.nameOf(brush), 'Brush');
      expect(g.state.obj(grove).zone, Zone.gone);
      expect(g.state.bfs[0].controller, 0);
      // "Bird, Cat, Dog, Poro, and Ivern units here have +1 {M}."
      final poro = put(g, 'Daring Poro', 0, loc: 0);
      expect(g.might(poro), 3);
      // Holding it next turn: "you may replace this with the battlefield it replaced".
      roundTrip(g);
      while (g.pending != null) {
        // Ivern's own trigger again: no; the Brush's: yes.
        answer(g, [g.pending!.decision.prompt.contains('exhaust it') ? 0 : 1]);
        passAll(g);
      }
      expect(g.state.bfs[0].obj, grove);
      expect(g.state.obj(grove).zone, Zone.battlefield);
    });

    test('Otterpus: a point from holding in your first or second turn is a draw instead', () {
      final points = <int>[], hands = <int>[];
      for (final otter in [false, true]) {
        final g = emptyGame();
        g.stackDeck(0, 'Shipyard Skulker', 5);
        g.stackDeck(1, 'Shipyard Skulker', 5);
        g.setControl(0, 0);
        if (otter) put(g, 'Otterpus', 1);
        put(g, 'Vanguard Sergeant', 0, loc: 0);
        roundTrip(g); // player 0's second turn: holds battlefield 0
        points.add(g.state.player(0).points);
        hands.add(g.state.player(0).hand.length);
      }
      expect(points, [1, 0]);
      expect(hands[1], hands[0] + 1);
    });
  });

  group('Abilities of other cards and resources (CR 166, 337.2, 376)', () {
    test('Heimerdinger, Inventor uses a friendly gear’s {E} ability, exhausting himself', () {
      final g = emptyGame();
      final ice = put(g, 'Heart of Dark Ice', 0); // {E}: Give a unit +3 {M} this turn.
      final heimer = put(g, 'Heimerdinger, Inventor', 0);
      final moves = g.legalMoves(0).whereType<ActivateMove>().where((m) => m.source == heimer).toList();
      expect(moves.map((m) => m.index), contains(ws2BorrowBase));
      expect(g.abilityOfMove(moves.first), isA<Activated>());
      g.apply(ActivateMove(0, heimer, ws2BorrowBase));
      if (g.pending != null) answer(g, [heimer]);
      passAll(g);
      expect(g.might(heimer), 6);
      expect(g.state.obj(heimer).exhausted, isTrue);
      expect(g.state.obj(ice).exhausted, isFalse);
    });

    test('Hextech Anomaly turns {A} into Energy at once (CR 337.2)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 2);
      final hex = put(g, 'Hextech Anomaly', 0);
      g.apply(ActivateMove(0, hex, 0));
      expect(g.pending?.decision.labels, ['0', '1', '2']);
      answer(g, const [2]);
      expect(g.state.chain, isEmpty);
      expect(g.state.player(0).energyPool, 2);
      expect(g.state.player(0).runes, isEmpty, reason: 'both runes recycled for Power');
    });

    test('Lux, Crownguard: her Energy pays only for spells (CR 166)', () {
      final g = emptyGame();
      put(g, 'Lux, Crownguard', 0);
      final unit = g.addCard('Daring Poro', 0); // {2} unit
      final spell = g.addCard('Monster Harpoon', 0); // {1}{R}
      put(g, 'Vanguard Sergeant', 1, loc: 1);
      expect(g.whyNot(PlayMove(0, unit)), isNotNull);
      g.addRunes(0, Domain.fury, 1);
      // {1} from Lux, {R} from the rune.
      expect(g.whyNot(PlayMove(0, spell)), isNull);
      g.state.player(0).runes.clear();
      g.addRunes(0, Domain.order, 1);
      expect(g.whyNot(PlayMove(0, unit)), isNotNull, reason: 'one rune and Lux’s spell-only Energy can’t pay {2}');
    });

    test('Ornn, Fire Below the Mountain: his {A} pays only for gear', () {
      final g = emptyGame();
      final ornn = g.addCard('Ornn, Fire Below the Mountain', 0, zone: Zone.legend);
      g.apply(ActivateMove(0, ornn, 0));
      expect(g.state.player(0).anyPool, 0, reason: 'restricted, held apart');
      expect(g.canPay(0, 0, const [null], use: PayFor.gear), isTrue);
      expect(g.canPay(0, 0, const [null]), isFalse);
      expect(g.canPay(0, 0, const [null], use: PayFor.spell), isFalse);
    });
  });

  group('Triggered abilities', () {
    test('Hwei draws 1 and discards 1 when he moves; a discarded spell draws 1 more', () {
      final g = emptyGame();
      g.stackDeck(0, 'Shipyard Skulker', 3);
      final hwei = put(g, 'Hwei, Brooding Painter', 0);
      final spell = g.addCard('Monster Harpoon', 0);
      g.apply(MoveUnitsMove(0, [hwei], 0));
      passAll(g);
      expect(g.pending?.decision.prompt, 'Discard 1');
      answer(g, [spell]);
      passAll(g);
      expect(g.state.obj(spell).zone, Zone.trash);
      expect(g.state.player(0).hand.length, 2, reason: 'drew 1, discarded the spell, drew 1');
    });

    test('Hwei: a discarded unit gives him +3 Might this turn', () {
      final g = emptyGame();
      g.stackDeck(0, 'Shipyard Skulker', 3);
      final hwei = put(g, 'Hwei, Brooding Painter', 0);
      g.apply(MoveUnitsMove(0, [hwei], 0));
      passAll(g); // the only card in hand is discarded without asking
      expect(g.state.player(0).trash.length, 1);
      expect(g.might(hwei), 8);
    });

    test('Illaoi plays a Tentacle when played and when she scores (CR 470.3)', () {
      final g = emptyGame();
      g.stackDeck(0, 'Shipyard Skulker', 5);
      g.stackDeck(1, 'Shipyard Skulker', 5);
      g.addRunes(0, Domain.chaos, 6);
      final illaoi = g.addCard('Illaoi, Prophet of the Great Kraken', 0);
      g.apply(PlayMove(0, illaoi));
      passAll(g);
      expect(g.units(player: 0).where((u) => g.nameOf(u) == 'Tentacle').length, 1);
      expect(g.might(illaoi), 5, reason: '+1 for the token unit');
      g.state.obj(illaoi).exhausted = false;
      g.apply(MoveUnitsMove(0, [illaoi], 0));
      passAll(g);
      expect(g.units(player: 0).where((u) => g.nameOf(u) == 'Tentacle').length, 2, reason: 'she conquered');
    });

    test('Ivern, Friend to All gains the tag chosen as he’s played, and scores 1 more with all four among your units', () {
      final g = emptyGame();
      g.stackDeck(0, 'Shipyard Skulker', 5);
      g.addRunes(0, Domain.order, 6);
      put(g, 'Daring Poro', 0); // Poro
      put(g, 'Crimson Pigeons', 0); // Bird
      put(g, 'Cemetery Attendant', 0); // Dog
      final ivern = g.addCard('Ivern, Friend to All', 0);
      g.apply(PlayMove(0, ivern));
      // As he's played: choose Bird, Cat, Dog, or Poro.
      while (g.pending != null && !g.pending!.decision.prompt.contains('tag')) {
        answer(g, Game.defaultAnswer(g.pending!.decision));
      }
      expect(g.pending?.decision.labels, ['Bird', 'Cat', 'Dog', 'Poro']);
      answer(g, const [1]); // Cat
      passAll(g);
      final at = g.units(player: 0).firstWhere((u) => g.nameOf(u) == 'Ivern, Friend to All');
      g.state.obj(at).exhausted = false;
      g.apply(MoveUnitsMove(0, [at], 0));
      passAll(g);
      expect(g.state.player(0).points, 2, reason: 'the conquest, and 1 for Bird, Cat, Dog and Poro');
    });

    test('Jayce, Brilliant Inventor: the first non-token gear each turn readies something', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 4);
      final tired = put(g, 'Vanguard Sergeant', 0, exhausted: true);
      put(g, 'Jayce, Brilliant Inventor', 0);
      g.apply(PlayMove(0, g.addCard("Doran's Blade", 0)));
      passAll(g);
      expect(g.pending, isNotNull);
      for (var i = 0; i < 6 && (g.pending != null || g.state.chain.isNotEmpty); i++) {
        if (g.pending == null) {
          passAll(g);
          continue;
        }
        final d = g.pending!.decision;
        answer(g, d.kind == DecisionKind.cards ? [tired] : const [1]);
      }
      expect(g.state.obj(tired).exhausted, isFalse);
      g.state.obj(tired).exhausted = true;
      g.apply(PlayMove(0, g.addCard("Doran's Ring", 0)));
      passAll(g);
      expect(g.pending, isNull, reason: 'the second gear this turn doesn’t trigger it');
      expect(g.state.obj(tired).exhausted, isTrue);
    });

    test('Jhin, Virtuoso banishes {4}+ spells; the fourth brings them back, channels 4 and draws 1', () {
      final g = emptyGame();
      g.stackDeck(0, 'Shipyard Skulker', 12);
      final jhin = g.addCard('Jhin, Virtuoso', 0, zone: Zone.legend);
      g.addRunes(0, Domain.mind, 20);
      for (var i = 0; i < 4; i++) {
        final s = g.addCard('Consult the Past', 0); // {4}: draw 2
        g.apply(PlayMove(0, s));
        passAll(g);
        expect(g.pending?.decision.kind, DecisionKind.yesNo);
        answer(g, const [1]);
        passAll(g);
        if (i < 3) expect(g.state.obj(s).zone, Zone.banish);
      }
      final banished = g.state.objects.values.where((o) => o.banishedBy == jhin).toList();
      expect(banished, isEmpty, reason: 'the four go to the trash');
      expect(g.state.player(0).trash.length, 4);
    });

    test('Kato the Arm gives a friendly unit his keywords and Might when he moves to a battlefield', () {
      final g = emptyGame();
      final kato = put(g, 'Kato the Arm', 0); // [Deflect], 3 Might
      final ally = put(g, 'Vanguard Sergeant', 0);
      g.apply(MoveUnitsMove(0, [kato], 0));
      if (g.pending != null) answer(g, [ally]);
      passAll(g);
      expect(g.might(ally), 7);
      expect(g.hasKw(ally, Kw.deflect), isTrue);
    });

    test('Nasus channels 1 rune exhausted when an enemy unit here dies, once each turn', () {
      final g = emptyGame();
      g.state.player(0).runeDeck.addAll([for (var i = 0; i < 3; i++) g.addCard('Mind Rune', 0, zone: Zone.runeDeck)]);
      put(g, 'Nasus, Guardian of Knowledge', 0, loc: 1);
      final a = put(g, 'Shipyard Skulker', 1, loc: 1);
      final b = put(g, 'Shipyard Skulker', 1, loc: 1);
      g.addRunes(0, Domain.order, 12);
      for (final v in [a, b]) {
        g.apply(PlayMove(0, g.addCard('Blast of Power', 0)));
        if (g.pending != null) answer(g, [v]);
        passAll(g);
      }
      final channelled = g.state.player(0).runes.where((r) => g.card(r).name == 'Mind Rune').toList();
      expect(channelled.length, 1);
      expect(g.state.obj(channelled.single).exhausted, isTrue);
    });

    test('Sivir, Battle Mistress readies when an enemy unit dies, not a friendly one (CR 382)', () {
      // The dying unit's controller is the event's player: an enemy death is the opponent's.
      for (final enemy in [true, false]) {
        final g = emptyGame();
        final sivir = put(g, 'Sivir, Battle Mistress', 0, exhausted: true);
        final victim = put(g, 'Shipyard Skulker', enemy ? 1 : 0, loc: 1);
        g.addRunes(0, Domain.order, 7);
        g.apply(PlayMove(0, g.addCard('Blast of Power', 0)));
        if (g.pending != null) answer(g, [victim]);
        passAll(g);
        expect(g.state.obj(victim).zone, Zone.trash);
        expect(g.state.obj(sivir).exhausted, !enemy, reason: 'enemy: $enemy');
      }
    });

    test('Ravenbloom Prefect may banish itself to banish a gear an opponent plays', () {
      final g = emptyGame(active: 1);
      final prefect = put(g, 'Ravenbloom Prefect', 0);
      g.addRunes(1, Domain.chaos, 2);
      final gear = g.addCard("Doran's Ring", 1);
      g.apply(PlayMove(1, gear));
      passAll(g);
      expect(g.pending?.decision.player, 0);
      answer(g, const [1]);
      passAll(g);
      expect(g.state.obj(prefect).zone, Zone.banish);
      expect(g.state.obj(gear).zone, Zone.banish);
    });

    test('Forgotten Library: you control it and spend {4}+ on a spell: [Predict]', () {
      final g = emptyGame(battlefields: const ['Forgotten Library', 'Zaun Warrens']);
      g.stackDeck(0, 'Shipyard Skulker', 5);
      g.setControl(0, 0);
      g.addRunes(0, Domain.mind, 4);
      g.apply(PlayMove(0, g.addCard('Consult the Past', 0)));
      passAll(g);
      expect(g.pending?.decision.prompt, startsWith('Predict'));
    });

    test('Forgotten Relic burns 1; a unit burned gives a friendly unit +its Might this turn', () {
      final g = emptyGame();
      g.stackDeck(0, 'Vanguard Sergeant', 2); // 4 Might
      g.addRunes(0, Domain.chaos, 5);
      final ally = put(g, 'Shipyard Skulker', 0);
      g.apply(PlayMove(0, g.addCard('Forgotten Relic', 0)));
      passAll(g);
      if (g.pending != null) answer(g, [ally]);
      expect(g.might(ally), 7);
      expect(g.state.player(0).trash.length, 1);
    });

    test('Forgotten Signpost moves another unit to the location of the unit exhausted to pay', () {
      final g = emptyGame();
      final sign = put(g, 'Forgotten Signpost', 0);
      final scout = put(g, 'Shipyard Skulker', 0, loc: 0);
      final mover = put(g, 'Vanguard Sergeant', 0);
      g.apply(ActivateMove(0, sign, 0));
      answer(g, [mover]); // the unit to move
      if (g.pending != null) answer(g, [scout]); // the unit to exhaust
      passAll(g);
      expect(g.state.obj(scout).exhausted, isTrue);
      expect(g.state.obj(mover).loc, 0);
    });

    test('Fortified Position: the chosen unit has Shield 2 this combat (CR 814)', () {
      final g = emptyGame(battlefields: const ['Fortified Position', 'Zaun Warrens'], active: 1);
      g.setControl(0, 0);
      final def = put(g, 'Shipyard Skulker', 0, loc: 0); // 3 Might
      final att = put(g, 'Vanguard Sergeant', 1); // 4 Might
      g.apply(MoveUnitsMove(1, [att], 0));
      for (var i = 0; i < 30 && (g.pending != null || g.state.showdown != null || g.state.chain.isNotEmpty); i++) {
        if (g.pending != null) {
          final d = g.pending!.decision;
          answer(g, d.options.contains(def) ? [def] : Game.defaultAnswer(d));
        } else {
          g.apply(PassMove(g.toAct!));
        }
      }
      expect(g.state.obj(def).zone, Zone.board, reason: '5 Might defending: survives 4');
      expect(g.state.obj(att).zone, Zone.trash);
    });
  });

  group('Passives', () {
    test('Kayn takes no damage once he has moved twice this turn', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 4);
      final kayn = put(g, 'Kayn, Unleashed', 0); // [Ganking]
      g.apply(MoveUnitsMove(0, [kayn], 0));
      passAll(g);
      g.state.obj(kayn).exhausted = false;
      g.apply(MoveUnitsMove(0, [kayn], 1));
      passAll(g);
      g.apply(PlayMove(0, g.addCard('Monster Harpoon', 0)));
      if (g.pending != null) answer(g, [kayn]);
      passAll(g);
      expect(g.state.obj(kayn).damage, 0);
    });

    test('LeBlanc, Everywhere At Once: your Temporary units at her battlefield don’t die', () {
      final g = emptyGame();
      g.stackDeck(0, 'Shipyard Skulker', 5);
      g.stackDeck(1, 'Shipyard Skulker', 5);
      g.setControl(0, 0);
      put(g, 'LeBlanc, Everywhere At Once', 0, loc: 0);
      final here = put(g, 'Keeper of Masks', 0, loc: 0); // [Temporary]
      final away = put(g, 'Keeper of Masks', 0);
      roundTrip(g);
      expect(g.state.obj(here).zone, Zone.board);
      expect(g.state.obj(away).zone, Zone.trash);
    });

    test('Mageseeker Investigator: opponents pay {A} per extra unit moved to its battlefield together', () {
      final g = emptyGame(active: 1);
      put(g, 'Mageseeker Investigator', 0, loc: 0);
      final a = put(g, 'Shipyard Skulker', 1);
      final b = put(g, 'Shipyard Skulker', 1);
      expect(g.whyNot(MoveUnitsMove(1, [a, b], 0)), contains('{A}'));
      expect(g.whyNot(MoveUnitsMove(1, [a], 0)), isNull);
      g.addRunes(1, Domain.chaos, 1);
      expect(g.whyNot(MoveUnitsMove(1, [a, b], 0)), isNull);
    });
  });

  group('Spells', () {
    test("Here to Help plays a unit from hand to a battlefield you control for {3} less", () {
      final g = emptyGame();
      g.setControl(0, 0);
      g.addRunes(0, Domain.body, 3);
      final skulker = g.addCard('Shipyard Skulker', 0); // {3}
      g.apply(PlayMove(0, g.addCard('Here to Help', 0)));
      passAll(g);
      answer(g, [skulker]);
      passAll(g);
      expect(g.state.obj(skulker).zone, Zone.board);
      expect(g.state.obj(skulker).loc, 0);
    });

    test("King's Edict: the opponent chooses one of their units; it's killed", () {
      final g = emptyGame();
      g.addRunes(0, Domain.order, 8);
      final a = put(g, 'Shipyard Skulker', 1);
      final b = put(g, 'Vanguard Sergeant', 1);
      final mine = put(g, 'Daring Poro', 0);
      g.apply(PlayMove(0, g.addCard("King's Edict", 0)));
      passAll(g);
      expect(g.pending?.decision.player, 1);
      expect(g.pending?.decision.options, unorderedEquals([a, b]));
      answer(g, [a]);
      passAll(g);
      expect(g.state.obj(a).zone, Zone.trash);
      expect(g.state.obj(b).zone, Zone.board);
      expect(g.state.obj(mine).zone, Zone.board);
    });

    test('Mirror Image: a ready Reflection in base that is a copy of the unit, with Temporary (CR 479.1)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.mind, 5);
      final model = put(g, 'Vanguard Sergeant', 1, loc: 1);
      g.apply(PlayMove(0, g.addCard('Mirror Image', 0)));
      if (g.pending != null) answer(g, [model]);
      passAll(g);
      final r = g.units(player: 0).single;
      expect(g.nameOf(r), 'Vanguard Sergeant');
      expect(g.might(r), 4);
      expect(g.state.obj(r).exhausted, isFalse);
      expect(g.state.obj(r).loc, base);
      expect(g.hasKw(r, Kw.temporary), isTrue);
    });

    test('LeBlanc, Deceiver: discard 1 and exhaust her for a Reflection copy of another unit there', () {
      final g = emptyGame();
      g.stackDeck(0, 'Shipyard Skulker', 5);
      final leblanc = g.addCard('LeBlanc, Deceiver', 0, zone: Zone.legend);
      g.addCard('Daring Poro', 0);
      final u = put(g, 'Vanguard Sergeant', 0);
      g.apply(MoveUnitsMove(0, [u], 0));
      for (var i = 0; i < 10 && (g.pending != null || g.state.chain.isNotEmpty); i++) {
        if (g.pending != null) {
          answer(g, g.pending!.decision.kind == DecisionKind.yesNo ? const [1] : Game.defaultAnswer(g.pending!.decision));
        } else {
          passAll(g);
        }
      }
      expect(g.state.obj(leblanc).exhausted, isTrue);
      final copies = g.unitsAt(0, player: 0).where((x) => x != u).toList();
      expect(copies.length, 1);
      expect(g.nameOf(copies.single), 'Vanguard Sergeant');
      expect(g.hasKw(copies.single, Kw.temporary), isTrue);
      expect(g.state.player(0).hand, isEmpty);
    });

    test('Mystic Reversal takes control of a spell (CR 750–755)', () {
      final g = emptyGame(active: 1);
      g.addRunes(1, Domain.fury, 2);
      g.addRunes(0, Domain.calm, 7);
      final mine = put(g, 'Shipyard Skulker', 0, loc: 0);
      final theirs = put(g, 'Shipyard Skulker', 1, loc: 1);
      final harpoon = g.addCard('Monster Harpoon', 1);
      final reversal = g.addCard('Mystic Reversal', 0);
      g.apply(PlayMove(1, harpoon));
      answer(g, [mine]);
      expect(g.toAct, 0);
      g.apply(PlayMove(0, reversal));
      passAll(g);
      // New choices: deal 2 to their unit instead.
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
      answer(g, const [1]);
      answer(g, [theirs]);
      passAll(g);
      expect(g.state.obj(theirs).damage, 2);
      expect(g.state.obj(mine).damage, 0);
    });

    test('Noxian Guillotine: with Legion it kills now instead (CR 812)', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 8);
      final target = put(g, 'Vanguard Sergeant', 1, loc: 1);
      g.apply(PlayMove(0, g.addCard('Daring Poro', 0))); // another card first
      passAll(g);
      g.apply(PlayMove(0, g.addCard('Noxian Guillotine', 0)));
      if (g.pending != null) answer(g, [target]);
      passAll(g);
      expect(g.state.obj(target).zone, Zone.trash);
    });

    test('Noxian Guillotine without Legion waits for damage', () {
      final g = emptyGame();
      g.addRunes(0, Domain.fury, 8);
      final target = put(g, 'Vanguard Sergeant', 1, loc: 1);
      g.apply(PlayMove(0, g.addCard('Noxian Guillotine', 0)));
      if (g.pending != null) answer(g, [target]);
      passAll(g);
      expect(g.state.obj(target).zone, Zone.board);
    });

    test('Party Favors: the opponent chooses Cards (both draw) or Runes (both channel exhausted)', () {
      final g = emptyGame();
      g.stackDeck(0, 'Shipyard Skulker', 3);
      g.stackDeck(1, 'Shipyard Skulker', 3);
      g.addRunes(0, Domain.calm, 3);
      g.apply(PlayMove(0, g.addCard('Party Favors', 0)));
      passAll(g);
      expect(g.pending?.decision.player, 1);
      answer(g, const [0]);
      passAll(g);
      expect(g.state.player(0).hand.length, 1);
      expect(g.state.player(1).hand.length, 1);
    });
  });
}
