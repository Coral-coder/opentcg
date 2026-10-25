// Rules tests. Section names are those of the Pokémon TCG rulebook (Scarlet & Violet era,
// Standard format); see docs/pokemon-rules.md.
import 'package:pokemon/pokemon.dart';
import 'package:test/test.dart';

import 'helpers.dart';

int countHp(Game g, CardId id) => g.maxHp(id) - g.state.obj(id).damage;

void main() {
  group('Setting Up', () {
    test('7-card hands, an Active Pokémon, 6 Prize cards; the first player draws on turn 1', () {
      final g = Game(fixtures, players: ['A', 'B'], seed: 3)..apply(StartMove([deckOf('T Sprout', n: 20), deckOf('T Ember', n: 20)], firstPlayer: 0));
      answerAll(g);
      final s = g.state;
      expect(s.phase, Phase.main);
      expect(s.turn, 1);
      for (var p = 0; p < 2; p++) {
        final pl = s.player(p);
        expect(pl.prizes.length, 6);
        expect(pl.active, isNotNull);
        final total = pl.deck.length + pl.hand.length + pl.prizes.length + pl.inPlay.length;
        expect(total, 60);
        // Default answers bench nobody: 7 cards minus the Active, plus the first player's draw.
        expect(pl.hand.length, p == 0 ? 7 : 6);
      }
    });

    test('a hand without a Basic Pokémon is a mulligan; the opponent may draw a card for each', () {
      // One Basic in 60 cards: mulligans are near certain.
      Game? found;
      for (var seed = 1; seed < 30 && found == null; seed++) {
        final g = Game(fixtures, players: ['A', 'B'], seed: seed)..apply(StartMove([deckOf('T Sprout', n: 1), deckOf('T Ember', n: 30)], firstPlayer: 0));
        answerAll(g);
        if (g.state.player(0).mulligans > 0) found = g;
      }
      expect(found, isNotNull);
      final g = found!;
      expect(g.state.player(0).hand.length + 1, 8, reason: 'player 0 still has a 7-card hand (+1 draw, −1 Active)');
      expect(g.state.log.any((l) => l.text.contains('mulligan')), isTrue);
    });

    test('a deck must have a Basic Pokémon; deck rules: 60 cards, 4 copies, 1 ACE SPEC', () {
      final g = Game(fixtures, players: ['A', 'B'], seed: 1);
      expect(() => g.apply(StartMove([List.filled(60, grassE), deckOf('T Ember')])), throwsA(isA<PokemonError>()));
      expect(validateDeck(fixtures, deckOf('T Sprout')), isEmpty);
      expect(validateDeck(fixtures, deckOf('T Sprout', n: 5)), isNotEmpty);
      expect(validateDeck(fixtures, deckOf('T Sprout').sublist(1)), isNotEmpty);
    });

    test('the coin flip winner chooses to go first or second', () {
      final g = Game(fixtures, players: ['A', 'B'], seed: 5)..apply(StartMove([deckOf('T Sprout', n: 20), deckOf('T Ember', n: 20)]));
      final d = g.pending!.decision;
      expect(d.kind, DecisionKind.option);
      answer(g, [1]);
      answerAll(g);
      expect(g.state.firstPlayer, 1 - d.player);
      expect(g.state.active, g.state.firstPlayer);
    });
  });

  group('Your Turn', () {
    test('1 Energy attachment per turn', () {
      final g = emptyGame();
      final a = g.addCard('T Sprout', 0, Place.active);
      g.addCard('T Ember', 1, Place.active);
      final e1 = g.addCard(grassE, 0, Place.hand), e2 = g.addCard(grassE, 0, Place.hand);
      g.apply(AttachEnergyMove(0, e1, a));
      expect(illegal(g, AttachEnergyMove(0, e2, a)), isTrue);
      expect(g.state.obj(a).energy, [e1]);
    });

    test('Basic Pokémon onto the Bench, at most 5', () {
      final g = emptyGame();
      g.addCard('T Sprout', 0, Place.active);
      g.addCard('T Ember', 1, Place.active);
      for (var i = 0; i < 5; i++) {
        g.apply(PlayBasicMove(0, g.addCard('T Sprout', 0, Place.hand)));
      }
      expect(illegal(g, PlayBasicMove(0, g.addCard('T Sprout', 0, Place.hand))), isTrue);
      expect(illegal(g, PlayBasicMove(0, g.addCard('T Bloom', 0, Place.hand))), isTrue, reason: 'only Basic Pokémon');
    });

    test('Evolving: not on your first turn, not a Pokémon put into play this turn; damage stays, conditions go', () {
      final first = emptyGame(turn: 1);
      final s0 = first.addCard('T Sprout', 0, Place.active);
      first.addCard('T Ember', 1, Place.active);
      expect(illegal(first, EvolveMove(0, first.addCard('T Bloom', 0, Place.hand), s0)), isTrue);
      final second = emptyGame(turn: 2, active: 1);
      second.addCard('T Sprout', 0, Place.active);
      final s1 = second.addCard('T Sprout', 1, Place.active);
      expect(illegal(second, EvolveMove(1, second.addCard('T Bloom', 1, Place.hand), s1)), isTrue, reason: 'the second player can’t evolve on their first turn either');

      final g = emptyGame();
      final a = g.addCard('T Sprout', 0, Place.active, damage: 30);
      g.addCard('T Ember', 1, Place.active);
      g.afflictForTest(a, Cond.poisoned);
      final fresh = g.addCard('T Sprout', 0, Place.hand);
      g.apply(PlayBasicMove(0, fresh));
      expect(illegal(g, EvolveMove(0, g.addCard('T Bloom', 0, Place.hand), fresh)), isTrue);
      final bloom = g.addCard('T Bloom', 0, Place.hand);
      g.apply(EvolveMove(0, bloom, a));
      expect(g.state.player(0).active, bloom);
      expect(g.state.obj(bloom).damage, 30);
      expect(g.state.obj(bloom).conds, isEmpty);
      expect(g.state.obj(bloom).under, [a]);
      expect(illegal(g, EvolveMove(0, g.addCard('T Sprout', 0, Place.hand), bloom)), isTrue, reason: 'wrong line');
    });

    test('Trainers: Items any number; 1 Supporter per turn; none for the first player on turn 1', () {
      final g = emptyGame();
      final a = g.addCard('T Sprout', 0, Place.active);
      g.addCard('T Sprout', 0, Place.bench);
      g.addCard('T Ember', 1, Place.active);
      g.apply(TrainerMove(0, g.addCard('T Switch', 0, Place.hand)));
      answerAll(g);
      g.apply(TrainerMove(0, g.addCard('T Switch', 0, Place.hand)));
      answerAll(g);
      expect(g.state.player(0).active, a, reason: 'switched twice');
      expect(g.state.player(0).discard.where((id) => g.card(id).name == 'T Switch').length, 2, reason: 'played Trainers go to the discard pile');
      final hand = g.state.player(0).hand.length;
      g.apply(TrainerMove(0, g.addCard('T Researcher', 0, Place.hand)));
      expect(g.state.player(0).hand.length, hand + 3);
      expect(illegal(g, TrainerMove(0, g.addCard('T Researcher', 0, Place.hand))), isTrue);

      final t1 = emptyGame(turn: 1);
      t1.addCard('T Sprout', 0, Place.active);
      t1.addCard('T Ember', 1, Place.active);
      expect(illegal(t1, TrainerMove(0, t1.addCard('T Researcher', 0, Place.hand))), isTrue);
      expect(illegal(t1, TrainerMove(0, t1.addCard('T Switch', 0, Place.hand))), isTrue, reason: 'no Benched Pokémon to switch with');
    });

    test('Pokémon Tools: 1 per Pokémon; +HP', () {
      final g = emptyGame();
      final a = g.addCard('T Sprout', 0, Place.active);
      g.addCard('T Ember', 1, Place.active);
      g.apply(TrainerMove(0, g.addCard('T Cape', 0, Place.hand), target: a));
      expect(g.maxHp(a), 160);
      expect(illegal(g, TrainerMove(0, g.addCard('T Cape', 0, Place.hand), target: a)), isTrue);
    });

    test('unsupported cards (here a Stadium) can’t be played', () {
      final g = emptyGame();
      g.addCard('T Sprout', 0, Place.active);
      g.addCard('T Ember', 1, Place.active);
      expect(PokemonParser.parse(fixtures['T Stadium']!).supported, isFalse);
      expect(illegal(g, TrainerMove(0, g.addCard('T Stadium', 0, Place.hand))), isTrue);
    });

    test('Retreat: once per turn, discard Energy equal to the cost; not while Asleep or Paralyzed', () {
      final g = emptyGame();
      final a = g.addCard('T Sprout', 0, Place.active);
      final b = g.addCard('T Ember', 0, Place.bench);
      g.addCard('T Ember', 1, Place.active);
      expect(illegal(g, RetreatMove(0, b)), isTrue, reason: 'no Energy for the Retreat Cost');
      g.attachNew(grassE, a);
      g.afflictForTest(a, Cond.poisoned);
      g.apply(RetreatMove(0, b));
      expect(g.state.player(0).active, b);
      expect(g.state.obj(a).energy, isEmpty);
      expect(g.state.obj(a).conds, isEmpty, reason: 'moving to the Bench removes Special Conditions');
      g.attachNew(fireE, b);
      expect(illegal(g, RetreatMove(0, a)), isTrue, reason: 'once per turn');

      final s = emptyGame();
      final x = s.addCard('T Sprout', 0, Place.active);
      final y = s.addCard('T Ember', 0, Place.bench);
      s.addCard('T Ember', 1, Place.active);
      s.attachNew(grassE, x);
      s.afflictForTest(x, Cond.asleep);
      expect(illegal(s, RetreatMove(0, y)), isTrue);
    });
  });

  group('Attacking', () {
    test('needs the Energy in the cost; Colorless is paid by any type', () {
      final g = emptyGame();
      final a = g.addCard('T Sprout', 0, Place.active);
      final d = g.addCard('T Puddle', 1, Place.active);
      expect(illegal(g, AttackMove(0, 0)), isTrue);
      g.attachNew(fireE, a);
      g.attachNew(grassE, a);
      expect(illegal(g, AttackMove(0, 1)), isTrue, reason: 'Vine needs 2 Grass');
      g.apply(AttackMove(0, 0));
      expect(g.state.obj(d).damage, 0, reason: 'Resistance −30 brings 20 to 0 (Puddle resists Grass)');
      expect(g.state.active, 1, reason: 'attacking ends the turn');
    });

    test('Weakness ×2, Resistance −30', () {
      final g = emptyGame();
      final a = g.addCard('T Ember', 0, Place.active);
      final d = g.addCard('T Sprout', 1, Place.active, damage: 0);
      g.addCard('T Sprout', 1, Place.bench);
      g.attachNew(fireE, a);
      g.apply(AttackMove(0, 0));
      expect(g.state.obj(d).zone, Place.discard, reason: '30 ×2 = 60 Knocks Out a 60-HP Sprout');

      final r = emptyGame();
      final s = r.addCard('T Bloom', 0, Place.active);
      final p = r.addCard('T Puddle', 1, Place.active);
      r.attachNew(grassE, s);
      r.apply(AttackMove(0, 0));
      expect(r.state.obj(p).damage, 20, reason: '50 − 30');
    });

    test('the player going first can’t attack on turn 1', () {
      final g = emptyGame(turn: 1);
      final a = g.addCard('T Sprout', 0, Place.active);
      g.addCard('T Ember', 1, Place.active);
      g.attachNew(grassE, a);
      expect(illegal(g, AttackMove(0, 0)), isTrue);
    });

    test('damage to Benched Pokémon applies no Weakness or Resistance', () {
      final g = emptyGame();
      final a = g.addCard('T Status', 0, Place.active);
      g.addCard('T Ember', 1, Place.active);
      final bench = g.addCard('T Puddle', 1, Place.bench);
      final tera = g.addCard('T Tera ex', 1, Place.bench);
      g.attachNew(grassE, a);
      g.apply(AttackMove(0, 4));
      expect(g.state.obj(bench).damage, 20);
      expect(g.state.obj(tera).damage, 0, reason: 'Tera: no damage from attacks on the Bench');
    });
  });

  group('Knock Outs and Prize cards', () {
    test('1 Prize, 2 for a Pokémon ex, 3 for a Mega Evolution Pokémon ex; a new Active is chosen', () {
      for (final (victim, prizes) in [('T Sprout', 1), ('T Big ex', 2), ('T Mega ex', 3)]) {
        final g = emptyGame();
        final a = g.addCard('T Mega ex', 0, Place.active);
        g.addCard(victim, 1, Place.active);
        final b = g.addCard('T Ember', 1, Place.bench);
        g.attachNew(grassE, a);
        final hand = g.state.player(0).hand.length;
        g.apply(AttackMove(0, 0));
        expect(g.state.player(0).prizes.length, 6 - prizes, reason: victim);
        expect(g.state.player(0).hand.length, hand + prizes);
        expect(g.state.player(1).active, b, reason: 'the only Benched Pokémon is promoted');
      }
    });

    test('the attacked Pokémon is discarded with its attached cards', () {
      final g = emptyGame();
      final a = g.addCard('T Big ex', 0, Place.active);
      final d = g.addCard('T Ember', 1, Place.active);
      g.addCard('T Ember', 1, Place.bench);
      final e = g.attachNew(fireE, d);
      g.attachNew(grassE, a);
      g.apply(AttackMove(0, 0));
      expect(g.state.player(1).discard, containsAll([d, e]));
    });
  });

  group('Winning', () {
    test('taking your last Prize card wins', () {
      final g = emptyGame();
      final a = g.addCard('T Big ex', 0, Place.active);
      g.addCard('T Big ex', 1, Place.active);
      g.addCard('T Ember', 1, Place.bench);
      g.attachNew(grassE, a);
      for (var i = 0; i < 4; i++) {
        g.knockOutsForTest();
        g.state.player(0).prizes.removeLast();
      }
      g.apply(AttackMove(0, 0));
      expect(g.over, isTrue);
      expect(g.state.winner, 0);
    });

    test('Knocking Out your opponent’s last Pokémon in play wins', () {
      final g = emptyGame();
      final a = g.addCard('T Big ex', 0, Place.active);
      g.addCard('T Ember', 1, Place.active);
      g.attachNew(grassE, a);
      g.apply(AttackMove(0, 0));
      expect(g.state.winner, 0);
    });

    test('a player who can’t draw at the start of their turn loses', () {
      final g = emptyGame(deck: 0);
      g.addCard('T Sprout', 0, Place.active);
      g.addCard('T Ember', 1, Place.active);
      g.apply(EndTurnMove(0));
      expect(g.state.winner, 0);
    });

    test('conceding', () {
      final g = emptyGame();
      g.addCard('T Sprout', 0, Place.active);
      g.addCard('T Ember', 1, Place.active);
      g.apply(ConcedeMove(1));
      expect(g.state.winner, 0);
    });
  });

  group('Special Conditions and Pokémon Checkup', () {
    Game duel() {
      final g = emptyGame();
      final a = g.addCard('T Status', 0, Place.active);
      g.addCard('T Puddle', 1, Place.active);
      g.attachNew(grassE, a);
      return g;
    }

    CardId defender(Game g) => g.state.player(1).active!;

    test('Poisoned: 1 damage counter at each Checkup', () {
      final g = duel();
      g.apply(AttackMove(0, 0));
      final d = defender(g);
      expect(g.state.obj(d).conds, [Cond.poisoned]);
      expect(g.state.obj(d).damage, 10, reason: 'checked up at the end of the attacking turn');
      g.apply(EndTurnMove(1));
      expect(g.state.obj(d).damage, 20);
    });

    test('Burned: 2 damage counters, then a flip to recover', () {
      final g = emptyGame();
      final a = g.addCard('T Ember', 0, Place.active);
      final d = g.addCard('T Puddle', 1, Place.active);
      g.attachNew(fireE, a);
      g.apply(AttackMove(0, 1));
      // 10 (Weakness doesn't apply: Puddle is weak to Lightning) + 20 Burned.
      expect(g.state.obj(d).damage, 30);
      final flips = g.state.log.where((l) => l.kind == 'coin').toList();
      expect(flips.last.text, contains('Burned'));
      expect(g.state.obj(d).conds.contains(Cond.burned), flips.last.amount == 0);
    });

    test('Asleep: can’t attack or retreat; a flip at Checkup wakes it', () {
      final g = duel();
      g.apply(AttackMove(0, 1));
      final d = defender(g);
      final slept = g.state.obj(d).conds.contains(Cond.asleep);
      if (slept) {
        g.attachNew(waterE, d);
        expect(illegal(g, AttackMove(1, 0)), isTrue);
      } else {
        expect(g.state.log.lastWhere((l) => l.kind == 'coin').amount, 1);
      }
    });

    test('Paralyzed: can’t attack; recovers at the end of its owner’s next turn', () {
      final g = duel();
      g.apply(AttackMove(0, 2));
      final d = defender(g);
      expect(g.state.obj(d).conds, [Cond.paralyzed]);
      g.attachNew(waterE, d);
      expect(illegal(g, AttackMove(1, 0)), isTrue);
      g.apply(EndTurnMove(1));
      expect(g.state.obj(d).conds, isEmpty);
    });

    test('Asleep, Confused and Paralyzed replace each other; Poisoned and Burned stack', () {
      final g = duel();
      final d = defender(g);
      g.afflictForTest(d, Cond.poisoned);
      g.afflictForTest(d, Cond.burned);
      g.afflictForTest(d, Cond.asleep);
      g.afflictForTest(d, Cond.confused);
      expect(g.state.obj(d).conds.toSet(), {Cond.poisoned, Cond.burned, Cond.confused});
    });

    test('Confused: tails puts 3 damage counters on itself and the attack does nothing', () {
      var sawTails = false, sawHeads = false;
      for (var seed = 1; seed < 20 && !(sawTails && sawHeads); seed++) {
        final g = Game(fixtures, players: ['A', 'B'], seed: seed)..startEmpty();
        g.fillDeck(0, grassE, 5);
        g.fillDeck(1, grassE, 5);
        final a = g.addCard('T Bloom', 0, Place.active);
        final d = g.addCard('T Puddle', 1, Place.active);
        g.attachNew(grassE, a);
        g.afflictForTest(a, Cond.confused);
        g.apply(AttackMove(0, 0));
        final heads = g.state.log.firstWhere((l) => l.kind == 'coin').amount == 1;
        if (heads) {
          sawHeads = true;
          expect(g.state.obj(d).damage, 20);
        } else {
          sawTails = true;
          expect(g.state.obj(a).damage, 30);
          expect(g.state.obj(d).damage, 0);
        }
      }
      expect(sawTails && sawHeads, isTrue);
    });
  });

  test('legal moves are exactly the moves the engine accepts', () {
    final g = emptyGame();
    final a = g.addCard('T Sprout', 0, Place.active);
    g.addCard('T Ember', 0, Place.bench);
    g.addCard('T Ember', 1, Place.active);
    g.addCard(grassE, 0, Place.hand);
    g.addCard('T Bloom', 0, Place.hand);
    g.attachNew(grassE, a);
    final legal = g.legalMoves();
    expect(legal.whereType<AttachEnergyMove>().length, 2);
    expect(legal.whereType<EvolveMove>().length, 1);
    expect(legal.whereType<RetreatMove>().length, 1);
    expect(legal.whereType<AttackMove>().map((m) => m.index), [0]);
    expect(legal.last, isA<EndTurnMove>());
    expect(countHp(g, a), 60);
  });
}
