import 'dart:io';

import 'package:riftbound/riftbound.dart';
import 'package:test/test.dart';

import 'helpers.dart';

String read(String name) => RiftboundParser.parse(db[name]!).abilities.map(describeAbility).join(' | ');

void main() {
  test('text is normalised: one ability per line, reminder text gone, symbols as {…}', () {
    final c = db['Jinx, Demolitionist']!;
    expect(c.text, '[Accelerate]\n[Assault 2]\nWhen you play me, discard 2.');
    expect(c.domains, [Domain.fury]);
    expect((c.energy, c.power, c.might), (3, 1, 4));
    expect(RCardDb.normaliseText('<p>[Accelerate] (You may pay :rb_energy_1::rb_rune_fury: as an additional cost.)<br />Deal 2 to a unit.</p>'), '[Accelerate]\nDeal 2 to a unit.');
  });

  test('variant printings with the same text are one card (CR 132)', () {
    expect(db['Jinx, Loose Cannon (Metal)'], isNull);
    expect(db['Jinx, Loose Cannon'], isNotNull);
    expect(db['Annie, Dark Child (Starter)'], isNull);
  });

  test('keywords, triggers, activated abilities and spells', () {
    expect(read('Rengar, Unseen'), 'KW accelerate | KW assault 2 | KW deflect | KW ganking');
    expect(read('Yasuo, Remorseful'), 'TRIG attack → deal my Might to a enemy unit @here');
    expect(read('Lee Sin, Blind Monk'), 'ACT [{1} {E}] → buff a friendly unit');
    expect(read('Firestorm'), 'SPELL → deal 3 to each enemy unit @battlefield');
    expect(read('Darius, Hand of Noxus'), 'ACT [{E}] reaction legion → add {1}');
    expect(read('Garen, Might of Demacia'), 'TRIG youConquer → [if 4+ units there] draw 2', reason: 'a condition right after the trigger is part of it (CR 383.2.a.1)');
    expect(read('Ahri, Nine-Tailed Fox'), 'TRIG enemyAttacksYourBf → give that unit -1 Might this turn (min 1)');
    expect(read('Gust'), 'KW reaction | SPELL → return a unit @battlefield M≤3 to hand');
  });

  test('a card is supported only if every line is understood', () {
    // Hidden (CR 811) isn't implemented yet: cards with it stay unsupported.
    final hidden = db.cards.firstWhere((c) => c.text.split('\n').contains('[Hidden]'));
    final p = RiftboundParser.parse(hidden);
    expect(p.supported, isFalse);
    expect(p.unsupported, contains('[Hidden]'));
    final made = RCard(name: 'Test Spell', type: CardType.spell, text: 'Deal 2 to a unit. Juggle the moon.');
    expect(RiftboundParser.parseUncached(made).supported, isFalse);
  });

  test('coverage never shrinks below the recorded floor', () {
    final floor = int.parse(File('test/fixtures/coverage-floor.txt').readAsStringSync().trim());
    final ok = db.cards.where((c) => RiftboundParser.parse(c).supported).length;
    expect(ok, greaterThanOrEqualTo(floor));
  });

  test('parsing is deterministic', () {
    for (final c in db.cards.take(200)) {
      expect(RiftboundParser.parseUncached(c).abilities.map(describeAbility).join('|'), RiftboundParser.parse(c).abilities.map(describeAbility).join('|'));
    }
  });
}
