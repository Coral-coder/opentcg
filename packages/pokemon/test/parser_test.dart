import 'package:pokemon/pokemon.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Eff? attack(String text, {int damage = 0, String mod = ''}) => PokemonParser.attackText(Attack(name: 'X', cost: const [], damage: damage, mod: mod, text: text));

void main() {
  test('Special Conditions', () {
    final e = attack("Your opponent's Active Pokémon is now Burned and Confused.");
    expect(e, isNotNull);
  });

  test('coin flips', () {
    final e = attack('Flip 2 coins. This attack does 30 damage for each heads.', mod: '×');
    expect(e, isNotNull);
    expect(attack('Flip a coin. If tails, this attack does nothing.'), isNotNull);
  });

  test('"×" damage needs a "for each"', () {
    expect(attack('', damage: 30, mod: '×'), isNull);
  });

  test('Trainers', () {
    expect(PokemonParser.effects('Draw 3 cards.', trainer: true), isA<Draw>());
    expect(PokemonParser.effects('Switch your Active Pokémon with 1 of your Benched Pokémon.', trainer: true), isA<Switch>());
  });

  test('conditions, self-mill, discard pile to hand, optional switch', () {
    expect(attack("If your opponent's Active Pokémon is Poisoned, this attack does 50 more damage."), isNotNull);
    expect(attack("If your opponent's Active Pokémon is an Evolution Pokémon, this attack does 60 more damage."), isNotNull);
    expect(attack('Discard the top 2 cards of your deck.'), isNotNull);
    expect(PokemonParser.effects('Put a Supporter card from your discard pile into your hand.'), isA<FromDiscard>());
    expect(attack('You may switch this Pokémon with 1 of your Benched Pokémon.'), isNotNull);
  });

  test('Tools and Abilities', () {
    expect(PokemonParser.toolText('The Pokémon this card is attached to gets +100 HP.'), isA<ToolHp>());
    expect(PokemonParser.ability('This Pokémon takes 30 less damage from attacks (after applying Weakness and Resistance).'), isA<TakesLess>());
  });

  test('unsupported text is recorded per card', () {
    const c = PCard(key: 'T Odd', name: 'T Odd', supertype: Supertype.pokemon, stage: Stage.basic, hp: 50, attacks: [
      Attack(name: 'Riddle', cost: [], damage: 0, text: 'Your opponent says a riddle aloud.'),
    ]);
    final p = PokemonParser.parse(c);
    expect(p.supported, isFalse);
    expect(p.unsupported.single, contains('Riddle'));
    expect(p.attacks.single, isNull);
  });

  test('the fixture cards are all understood (except the Stadium)', () {
    for (final c in fixtures.cards) {
      final p = PokemonParser.parse(c);
      expect(p.supported, c.trainer != TrainerKind.stadium, reason: '${c.key}: ${p.unsupported}');
    }
  });

  test('the real card pool: coverage report adds up', () {
    final r = coverageReport(db);
    expect(r['total'], db.cards.length);
    expect(r['supported'] as int, greaterThan(db.cards.length ~/ 3));
  });
}
