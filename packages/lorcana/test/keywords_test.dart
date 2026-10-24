import 'package:lorcana/lorcana.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('8.2 Alert: can challenge as if it had Evasive', () {
    final g = emptyGame();
    final alert = g.addCard('Sina - Vigilant Parent', 0, Place.play);
    final plain = g.addCard(vanilla, 0, Place.play);
    final ev = g.addCard('Daisy Duck - Spotless Food-Fighter', 1, Place.play, exerted: true);
    expect(g.whyNot(ChallengeMove(0, plain, ev)), isNotNull);
    expect(g.whyNot(ChallengeMove(0, alert, ev)), isNull);
  });

  group('8.3 Bodyguard', () {
    test('8.3.2 may enter play exerted', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final bg = g.addCard('Fergus - King of DunBroch', 0, Place.hand);
      g.apply(PlayMove(0, bg));
      expect(g.pending!.decision.kind, DecisionKind.yesNo);
      answer(g, [1]);
      expect(g.state.obj(bg).exerted, isTrue);
    });

    test('8.3.3 an opposing challenger must choose a Bodyguard if able', () {
      final g = emptyGame();
      final a = g.addCard(vanilla, 0, Place.play);
      final bg = g.addCard('Fergus - King of DunBroch', 1, Place.play, exerted: true);
      final other = g.addCard(vanilla2, 1, Place.play, exerted: true);
      expect(g.whyNot(ChallengeMove(0, a, other)), isNotNull);
      expect(g.whyNot(ChallengeMove(0, a, bg)), isNull);
      // A ready Bodyguard can't be challenged, so it doesn't protect.
      g.state.obj(bg).exerted = false;
      expect(g.whyNot(ChallengeMove(0, a, other)), isNull);
    });
  });

  test('8.4 Boost: once a turn, pay to put the top card of the deck facedown under it', () {
    final g = emptyGame();
    g.addInk(0, 2);
    final genie = g.addCard('Genie - Magical Researcher', 0, Place.play);
    final boost = g.parsed(genie).abilities.indexWhere((a) => a is KeywordAbility && a.keyword.kw == Kw.boost);
    final top = g.state.player(0).deck.first;
    g.apply(ActivateMove(0, genie, boost));
    expect(g.state.obj(genie).under, [top]);
    expect(g.state.obj(top).faceDown, isTrue);
    expect(illegal(g, ActivateMove(0, genie, boost)), isTrue, reason: 'once during your turn');
  });

  group('8.5 Challenger', () {
    test('8.5.1 +N strength while challenging', () {
      final g = emptyGame();
      final a = g.addCard('Dr. Facilier - Charlatan', 0, Place.play); // 0/4, Challenger +2
      final d = g.addCard(vanilla2, 1, Place.play, exerted: true); // 2/3
      g.apply(ChallengeMove(0, a, d));
      expect(g.state.obj(d).damage, 2);
    });

    test('8.5.2 no bonus while being challenged', () {
      final g = emptyGame();
      final a = g.addCard(vanilla2, 0, Place.play);
      final d = g.addCard('Dr. Facilier - Charlatan', 1, Place.play, exerted: true);
      g.apply(ChallengeMove(0, a, d));
      expect(g.state.obj(a).damage, 0);
    });
  });

  test('8.6 Evasive: only Evasive characters can challenge it', () {
    final g = emptyGame();
    final plain = g.addCard(vanilla, 0, Place.play);
    final ev = g.addCard('Basil - Hypnotized Mouse', 0, Place.play);
    final target = g.addCard('Daisy Duck - Spotless Food-Fighter', 1, Place.play, exerted: true);
    expect(g.whyNot(ChallengeMove(0, plain, target)), isNotNull);
    expect(g.whyNot(ChallengeMove(0, ev, target)), isNull);
  });

  group('8.7 Reckless', () {
    test('8.7.2 can\'t quest', () {
      final g = emptyGame();
      final r = g.addCard('Arthur - Novice Sparrow', 0, Place.play);
      expect(illegal(g, QuestMove(0, r)), isTrue);
    });

    test('8.7.3 the turn can\'t end while it is ready and can challenge', () {
      final g = emptyGame();
      final r = g.addCard('Arthur - Novice Sparrow', 0, Place.play); // 2/3
      final d = g.addCard(vanilla2, 1, Place.play, exerted: true);
      expect(illegal(g, const EndTurnMove(0)), isTrue);
      g.apply(ChallengeMove(0, r, d));
      g.apply(const EndTurnMove(0));
      expect(g.state.active, 1);
    });

    test('nothing to challenge: the turn can end', () {
      final g = emptyGame();
      g.addCard('Arthur - Novice Sparrow', 0, Place.play);
      g.apply(const EndTurnMove(0));
      expect(g.state.active, 1);
    });
  });

  test('8.8 Resist: damage dealt is reduced by N', () {
    final g = emptyGame();
    final a = g.addCard(vanilla, 0, Place.play); // 3 strength
    final d = g.addCard('Beast - Thick-Skinned', 1, Place.play, exerted: true); // 2/3, Resist +1
    g.apply(ChallengeMove(0, a, d));
    expect(g.state.obj(d).zone, Place.play);
    expect(g.state.obj(d).damage, 2);
  });

  test('8.9 Rush: can challenge the turn it is played', () {
    final g = emptyGame();
    g.addInk(0, 3);
    final h = g.addCard('Hercules - Clumsy Kid', 0, Place.hand);
    final d = g.addCard(vanilla2, 1, Place.play, exerted: true);
    g.apply(PlayMove(0, h));
    expect(g.whyNot(QuestMove(0, h)), isNotNull, reason: 'Rush doesn\'t allow questing');
    expect(g.whyNot(ChallengeMove(0, h, d)), isNull);
  });

  group('8.10 Shift', () {
    test('8.10.1 pay the Shift cost to play it on a same-named character; 8.10.4/8.10.6 dry and damage stay', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final base = g.addCard('Li Shang - General\'s Son', 0, Place.play, damage: 1);
      final top = g.addCard('Li Shang - Valiant Leader', 0, Place.hand);
      expect(g.whyNot(PlayMove(0, top)), isNotNull, reason: 'cost 7 with 4 ink');
      g.apply(PlayMove(0, top, mode: PlayMode.shift, onto: base));
      final o = g.state.obj(top);
      expect(o.zone, Place.play);
      expect(o.under, [base]);
      expect(o.damage, 1);
      expect(o.dry, isTrue);
      expect(g.inkReady(0), 0);
      g.apply(QuestMove(0, top));
      expect(g.state.player(0).lore, 2);
    });

    test('8.10.7 when it leaves play, its stack goes with it', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final base = g.addCard('Li Shang - General\'s Son', 0, Place.play);
      final top = g.addCard('Li Shang - Valiant Leader', 0, Place.hand);
      g.apply(PlayMove(0, top, mode: PlayMode.shift, onto: base));
      g.moveToForTest(top, Place.discard);
      expect(g.state.obj(base).zone, Place.discard);
    });

    test('a different name can\'t be shifted onto', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final base = g.addCard(vanilla, 0, Place.play);
      final top = g.addCard('Li Shang - Valiant Leader', 0, Place.hand);
      expect(illegal(g, PlayMove(0, top, mode: PlayMode.shift, onto: base)), isTrue);
    });
  });

  test('8.11 Singer N: counts as cost N to sing songs', () {
    final g = emptyGame();
    final bianca = g.addCard('Miss Bianca - Rescue Aid Society Agent', 0, Place.play); // cost 2, Singer 4
    final song = g.addCard('He Hurled His Thunderbolt', 0, Place.hand); // cost 4
    final t = g.addCard(vanilla, 1, Place.play);
    g.apply(PlayMove(0, song, mode: PlayMode.sing, singers: [bianca]));
    answer(g, [t]);
    expect(g.state.obj(t).zone, Place.discard);
    expect(g.chars(bianca).cost, 2, reason: '8.11.2 its ink cost doesn\'t change');
  });

  test('8.13 Support: add its strength to another chosen character this turn', () {
    final g = emptyGame();
    final basil = g.addCard('Basil - Of Baker Street', 0, Place.play); // 2 strength
    final other = g.addCard(vanilla2, 0, Place.play); // 2 strength
    g.apply(QuestMove(0, basil));
    while (g.pending != null) {
      final d = g.pending!.decision;
      answer(g, d.kind == DecisionKind.cards ? [other] : [1]);
    }
    expect(g.chars(other).strength, 4);
    g.apply(const EndTurnMove(0));
    expect(g.chars(other).strength, 2, reason: 'this turn only');
  });

  test('8.14 Vanish: banished when an opponent chooses it for an action', () {
    final g = emptyGame();
    g.addInk(0, 1);
    final rajah = g.addCard('Rajah - Ghostly Tiger', 1, Place.play);
    final other = g.addCard(vanilla, 1, Place.play);
    g.apply(PlayMove(0, g.addCard('Control Your Temper!', 0, Place.hand)));
    expect(g.pending!.decision.options, containsAll([rajah, other]));
    answer(g, [rajah]);
    expect(g.state.obj(rajah).zone, Place.discard);
  });

  group('8.15 Ward', () {
    test('8.15.1 opponents can\'t choose it', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final ward = g.addCard('Duke Weaselton - Small-Time Crook', 1, Place.play);
      final other = g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('And Then Along Came Zeus', 0, Place.hand)));
      final opts = g.pending?.decision.options ?? const <int>[];
      expect(opts, isNot(contains(ward)));
      expect(g.state.obj(other).zone, Place.discard, reason: 'the only legal choice is made for the player');
    });

    test('its controller can still choose it', () {
      final g = emptyGame(active: 1);
      g.addInk(1, 1);
      final ward = g.addCard('Duke Weaselton - Small-Time Crook', 1, Place.play);
      g.addCard(vanilla, 0, Place.play);
      g.apply(PlayMove(1, g.addCard('Rahr!', 1, Place.hand)));
      expect(g.pending!.decision.options, contains(ward));
    });

    test('8.15.2 still affected by effects that don\'t choose', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final ward = g.addCard('Duke Weaselton - Small-Time Crook', 1, Place.play); // 2 willpower
      g.apply(PlayMove(0, g.addCard('Grab Your Sword', 0, Place.hand)));
      expect(g.state.obj(ward).zone, Place.discard);
    });
  });
}
