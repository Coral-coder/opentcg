import 'package:lorcana/lorcana.dart';
import 'package:test/test.dart';

import 'helpers.dart';

ParsedCard parse(String name) => LorcanaParser.parse(db[name]!);
List<String> describe(String name) => [for (final a in parse(name).abilities) describeAbility(a)];

void main() {
  test('CR 8 keywords with their values', () {
    expect(describe('Li Shang - Valiant Leader'), ['KW shift4']);
    expect(describe('Beast - Thick-Skinned'), ['KW resist1']);
    expect(describe('Jafar - Wicked Sorcerer'), ['KW challenger3']);
    expect(describe('Miss Bianca - Rescue Aid Society Agent'), ['KW singer4']);
    expect(describe('Rajah - Ghostly Tiger'), ['KW vanish0']);
  });

  test('a triggered ability (CR 6.2) and an activated one (CR 6.3)', () {
    expect(describe('Kakamora - Menacing Sailor'), ['TRIG on play → lose 1 lore (opponents)']);
    expect(describe('Jasmine - Rebellious Princess'), ['TRIG this quests → lose 1 lore (opponents)']);
    expect(describe('Amber Chromicon'), ['ACT [exert] → remove 1 damage from all your character']);
  });

  test('"a character with cost 2 or less" is one picked card, not all of them', () {
    expect(describe('Befuddle'), ['ACTION return chosen 1 character/item cost≤2 #0 to hand']);
  });

  test('a floating triggered ability (CR 6.2.7.1)', () {
    expect(describe('99 Puppies'), ['ACTION this turn: TRIG your character quests → gain 1 lore (you)']);
  });

  test('songs are actions with the Song classification (CR 5.4.4.1)', () {
    expect(db['He Hurled His Thunderbolt']!.isSong, isTrue);
    expect(db['Finders Keepers']!.isSong, isFalse);
  });

  test('a song whose bulk text is only its reminder takes its rules text from Lorcast', () {
    expect(db["I'm Still Here"]!.text, isNot(startsWith('- A character with cost')));
    expect(parse('A Very Merry Unbirthday').unsupported, isNot(contains('Action without its effect text in the data')));
  });

  test('unsupported text is recorded per card', () {
    // A made-up card, so this keeps testing the recording as real cards become supported.
    final p = LorcanaParser.parse(const LCard(fullName: 'Test Card - Unreadable', type: CardType.character, cost: 2, inkable: true, inks: [Ink.amber], strength: 1, willpower: 1, lore: 1, text: 'FROBNICATE Whenever the moon is full, rearrange the stars.'));
    expect(p.supported, isFalse);
    expect(p.unsupported.single, contains('rearrange the stars'));
  });

  test('parsing is deterministic', () {
    final a = [for (final c in db.cards) LorcanaParser.parse(c).abilities.map(describeAbility).join('\n')];
    final b = [for (final c in db.cards) LorcanaParser.parse(c).abilities.map(describeAbility).join('\n')];
    expect(a, b);
  });
}
