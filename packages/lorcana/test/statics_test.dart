import 'package:lorcana/lorcana.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Static abilities (CR 6.4), Shift variants (8.10.8), Sing Together (8.12) and the effects whose
/// choices the text limits.
void main() {
  LChars ch(Game g, CardId id) => g.chars(id);

  group('Shift variants (CR 8.10.8)', () {
    test('8.10.8.3 Duo Shift goes on top of two characters, one for each name', () {
      final g = emptyGame();
      final mickey = g.addCard('Mickey Mouse - True Friend', 0, Place.play, damage: 1);
      final minnie = g.addCard('Minnie Mouse - Always Classy', 0, Place.play, exerted: true, damage: 2);
      final duo = g.addCard('Mickey Mouse & Minnie Mouse - Adventuring Duo', 0, Place.hand);
      final moves = g.legalMoves().whereType<PlayMove>().where((m) => m.card == duo && m.mode == PlayMode.shift).toList();
      expect(moves.map((m) => {m.onto, m.onto2}), [
        {mickey, minnie},
      ]);
      g.apply(moves.single);
      final o = g.state.obj(duo);
      expect(o.zone, Place.play);
      expect(o.under.toSet(), {mickey, minnie});
      expect(o.exerted, isTrue, reason: '8.10.4.2 exerted if either was');
      expect(o.damage, 3, reason: '8.10.6 keeps the damage of both');
      expect(g.state.player(0).play, [duo]);
    });

    test('8.10.8.4 Combo Shift can also go on top of just one of them', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final sulley = g.addCard('Sulley - Strategic Scarer', 0, Place.play);
      final combo = g.addCard('Sulley & Boo - Scare Buddies', 0, Place.hand);
      expect(g.whyNot(PlayMove(0, combo, mode: PlayMode.shift, onto: sulley)), isNull);
      g.apply(PlayMove(0, combo, mode: PlayMode.shift, onto: sulley));
      expect(g.state.obj(combo).under, [sulley]);
    });

    test('8.10.8.5 Temporary Shift returns to hand at the end of the turn, leaving the card under it', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final wise = g.addCard('Grandma Wu - Wise Grandmother', 0, Place.play);
      final fierce = g.addCard('Grandma Wu - Fierce Red Panda', 0, Place.hand);
      g.apply(PlayMove(0, fierce, mode: PlayMode.shift, onto: wise));
      g.state.obj(fierce).damage = 2;
      expect(g.state.player(0).play, [fierce]);
      g.apply(const EndTurnMove(0));
      expect(g.state.obj(fierce).zone, Place.hand);
      expect(g.state.obj(wise).zone, Place.play);
      expect(g.state.obj(wise).damage, 0, reason: 'all damage is removed first');
    });

    test('8.10.8.6 Potato Shift goes on top of an item named Potato', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final potato = g.addCard('Potato', 0, Place.play);
      final posey = g.addCard('Posey - Vampire Potato', 0, Place.hand);
      expect(g.shiftTargets(0, posey), [potato]);
      g.apply(PlayMove(0, posey, mode: PlayMode.shift, onto: potato));
      expect(g.state.obj(posey).under, [potato]);
    });

    test('8.10.1 "Shift: Discard a location card" pays by discarding instead of ink', () {
      final g = emptyGame();
      final base = g.addCard(vanilla2, 0, Place.play); // Aladdin - Fearless Navigator
      final rescuer = g.addCard('Aladdin - Brave Rescuer', 0, Place.hand);
      expect(g.whyNot(PlayMove(0, rescuer, mode: PlayMode.shift, onto: base)), isNotNull, reason: 'no location to discard');
      final loc = g.addCard('Agrabah - Marketplace', 0, Place.hand);
      g.apply(PlayMove(0, rescuer, mode: PlayMode.shift, onto: base));
      if (g.pending != null) answer(g, [loc]);
      expect(g.state.obj(loc).zone, Place.discard);
      expect(g.state.obj(rescuer).under, [base]);
    });

    test('8.10.1 "counts as being named King Candy for Shift"', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final turbo = g.addCard('Turbo - Royal Hack', 0, Place.play);
      final candy = g.addCard('King Candy - Sweet Abomination', 0, Place.hand);
      expect(g.shiftTargets(0, candy), [turbo]);
    });
  });

  group('Conditions of static abilities (CR 6.4.2)', () {
    test('2.2.1 "if this is your first turn and you\'re not the first player"', () {
      final g = emptyGame();
      g.state.firstPlayer = 1;
      g.addInk(0, 1);
      final angel = g.addCard('Angel - Siren Singer', 0, Place.hand);
      expect(g.whyNot(PlayMove(0, angel)), isNull);
      g.state.turn = 3;
      expect(g.whyNot(PlayMove(0, angel)), isNotNull, reason: 'not the first turn any more');
    });

    test('"while this character has no damage"', () {
      final g = emptyGame();
      final l = g.addCard('Lawrence - Jealous Manservant', 0, Place.play);
      expect(ch(g, l).strength, 4);
      g.state.obj(l).damage = 1;
      expect(ch(g, l).strength, 0);
    });

    test('"while this character has 10 {s} or more" sees its own changes', () {
      final g = emptyGame();
      final alice = g.addCard('Alice - Growing Girl', 0, Place.play);
      expect(ch(g, alice).lore, 1);
      g.state.timed.add(Timed(ts: 0, controller: 0, source: alice, cards: [alice], stat: Stat.strength, amount: 9, lasting: Lasting.thisTurn, turn: g.state.turn));
      expect(ch(g, alice).lore, 5);
    });

    test('"while you have 5 or more cards in your inkwell"', () {
      final g = emptyGame();
      final boo = g.addCard('Boo - Human Child', 0, Place.play);
      g.addInk(0, 4);
      expect(ch(g, boo).lore, 1);
      g.addInk(0, 1);
      expect(ch(g, boo).lore, 3);
    });

    test('8.4 "while there\'s a card under this character"', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final herc = g.addCard('Hercules - Spectral Demigod', 0, Place.play);
      expect(ch(g, herc).strength, 0);
      final boost = g.parsed(herc).abilities.indexWhere((a) => a is KeywordAbility && a.keyword.kw == Kw.boost);
      g.apply(ActivateMove(0, herc, boost));
      expect(ch(g, herc).strength, 3);
    });

    test('"while this character has a card under him, he gets +3 {s}, +3 {w}, and +3 {l}"', () {
      final g = emptyGame();
      final m = g.addCard('Mickey Mouse - Brave Little Prince', 0, Place.play);
      g.state.obj(m).under = [g.addCard(vanilla2, 0, Place.deck)];
      final c = ch(g, m);
      expect([c.strength, c.willpower, c.lore], [5, 5, 4]);
    });

    test('"if a character was banished this turn"', () {
      final g = emptyGame();
      final gothel = g.addCard('Mother Gothel - Underhanded Schemer', 0, Place.play);
      final a = g.addCard(vanilla, 0, Place.play);
      final d = g.addCard(vanilla2, 1, Place.play, exerted: true, damage: 1);
      expect(ch(g, gothel).strength, 2);
      g.apply(ChallengeMove(0, a, d));
      expect(g.state.obj(d).zone, Place.discard);
      expect(ch(g, gothel).strength, 4);
      g.apply(const EndTurnMove(0));
      expect(ch(g, gothel).strength, 2, reason: 'a new turn');
    });

    test('"during your turn, if no other character has quested this turn"', () {
      final g = emptyGame();
      final isa = g.addCard('Isabela Madrigal - Golden Child', 0, Place.play);
      final other = g.addCard(vanilla2, 0, Place.play);
      expect(ch(g, isa).lore, 4);
      g.apply(QuestMove(0, other));
      expect(ch(g, isa).lore, 1);
    });

    test('4.3.6 "if you\'ve played 3 or more actions this turn, you may play this character for free"', () {
      final g = emptyGame();
      final lilo = g.addCard('Lilo - Causing an Uproar', 0, Place.hand);
      expect(g.whyNot(PlayMove(0, lilo)), isNotNull);
      g.state.player(0).actionsThisTurn = 3;
      expect(g.whyNot(PlayMove(0, lilo)), isNull);
    });

    test('4.3.6 "for each card in your inkwell, you pay 1 {i} less"', () {
      final g = emptyGame();
      g.addInk(0, 6);
      final tala = g.addCard('Gramma Tala - Connected to Nature', 0, Place.hand);
      expect(g.whyNot(PlayMove(0, tala)), isNull, reason: '12 - 6 = 6');
    });
  });

  group('Rules a static changes', () {
    test('4.6.4.2 exception: "can challenge ready characters"', () {
      final g = emptyGame();
      final shang = g.addCard('Li Shang - Newly Promoted', 0, Place.play);
      final plain = g.addCard(vanilla, 0, Place.play);
      final ready = g.addCard(vanilla2, 1, Place.play);
      expect(g.whyNot(ChallengeMove(0, plain, ready)), isNotNull);
      expect(g.whyNot(ChallengeMove(0, shang, ready)), isNull);
    });

    test('"can challenge ready damaged characters" only damaged ones', () {
      final g = emptyGame();
      final giz = g.addCard('Gizmoduck - Suited Up', 0, Place.play);
      final ready = g.addCard(vanilla2, 1, Place.play);
      expect(g.whyNot(ChallengeMove(0, giz, ready)), isNotNull);
      g.state.obj(ready).damage = 1;
      expect(g.whyNot(ChallengeMove(0, giz, ready)), isNull);
    });

    test('4.5.1 exception: "can quest the turn he\'s played"', () {
      final g = emptyGame();
      final dash = g.addCard('Dash Parr - Lava Runner', 0, Place.play, drying: true);
      final plain = g.addCard(vanilla, 0, Place.play, drying: true);
      expect(g.whyNot(QuestMove(0, plain)), isNotNull);
      expect(g.whyNot(QuestMove(0, dash)), isNull);
    });

    test('"this character can\'t gain Evasive"', () {
      final g = emptyGame();
      final buzz = g.addCard('Buzz Lightyear - Grounded', 0, Place.play);
      g.state.timed.add(Timed(ts: 0, controller: 0, source: buzz, cards: [buzz], keyword: const Keyword(Kw.evasive), lasting: Lasting.thisTurn, turn: g.state.turn));
      expect(ch(g, buzz).has(Kw.evasive), isFalse);
    });

    test('8.12 "can\'t sing songs without Sing Together"', () {
      final g = emptyGame();
      final meilin = g.addCard('Meilin Lee - Lead Vocalist', 0, Place.play);
      final song = g.addCard('Friends on the Other Side', 0, Place.hand);
      expect(g.whyNot(PlayMove(0, song, mode: PlayMode.sing, singers: [meilin])), isNotNull);
    });

    test('"your characters with 7 {s} or more can\'t be dealt damage"', () {
      final g = emptyGame();
      g.addCard('Baloo - Ol\' Iron Paws', 0, Place.play);
      final maui = g.addCard('Maui - Whale', 0, Place.play, exerted: true); // 8 {s}
      final a = g.addCard(vanilla, 1, Place.play);
      g.state.active = 1;
      g.apply(ChallengeMove(1, a, maui));
      expect(g.state.obj(maui).damage, 0);
    });

    test('4.6.6.1 "your characters deal damage with their {w} instead of their {s}"', () {
      final g = emptyGame();
      g.addCard('Dale - Ready for His Shot', 0, Place.play);
      final a = g.addCard(vanilla2, 0, Place.play); // 2/3
      final d = g.addCard('Mickey Mouse - Tiny Tim\'s Father', 1, Place.play, exerted: true); // 6/7
      g.apply(ChallengeMove(0, a, d));
      expect(g.state.obj(d).damage, 3);
    });

    test('"can\'t ready at the start of your turn"', () {
      final g = emptyGame();
      final maui = g.addCard('Maui - Whale', 0, Place.play, exerted: true);
      g.apply(const EndTurnMove(0));
      g.apply(const EndTurnMove(1));
      expect(g.state.obj(maui).exerted, isTrue);
    });
  });

  group('Challenges (CR 4.6)', () {
    test('4.6.4.3 "can\'t be challenged by Pirate characters"', () {
      final g = emptyGame();
      final pirate = g.addCard('Billy Bones - Keeper of the Map', 0, Place.play);
      final plain = g.addCard(vanilla, 0, Place.play);
      final amelia = g.addCard('Captain Amelia - Commander of the Legacy', 1, Place.play, exerted: true);
      expect(g.whyNot(ChallengeMove(0, pirate, amelia)), isNotNull);
      expect(g.whyNot(ChallengeMove(0, plain, amelia)), isNull);
    });

    test('4.6.4.3 "damaged characters can\'t challenge your characters"', () {
      final g = emptyGame();
      final hurt = g.addCard(vanilla, 0, Place.play, damage: 1);
      final fine = g.addCard(vanilla, 0, Place.play);
      g.addCard('King of Hearts - Picky Ruler', 1, Place.play);
      final d = g.addCard(vanilla2, 1, Place.play, exerted: true);
      expect(g.whyNot(ChallengeMove(0, hurt, d)), isNotNull);
      expect(g.whyNot(ChallengeMove(0, fine, d)), isNull);
    });

    test('4.6.4.5 "while being challenged, this character gets +2 {s}"', () {
      final g = emptyGame();
      final a = g.addCard('Mickey Mouse - Tiny Tim\'s Father', 0, Place.play); // 6/7
      final e = g.addCard('Enchantress - Unexpected Judge', 1, Place.play, exerted: true); // 1/1
      expect(ch(g, e).strength, 1);
      g.apply(ChallengeMove(0, a, e));
      expect(g.state.obj(a).damage, 3);
    });

    test('4.6.4.5 "while being challenged, the challenging character gets -1 {s}"', () {
      final g = emptyGame();
      final a = g.addCard(vanilla, 0, Place.play); // 3/2
      final louie = g.addCard('Louie - One Cool Duck', 1, Place.play, exerted: true); // 2/3
      g.apply(ChallengeMove(0, a, louie));
      expect(g.state.obj(louie).damage, 2);
      expect(g.state.obj(louie).zone, Place.play);
      expect(ch(g, a).strength, 3, reason: 'only during the challenge');
    });

    test('4.6.4.5 "while challenging a damaged character, this character gets +2 {s}"', () {
      final g = emptyGame();
      final shenzi = g.addCard('Shenzi - Scar\'s Accomplice', 0, Place.play); // 2/3
      final d = g.addCard('Mickey Mouse - Tiny Tim\'s Father', 1, Place.play, exerted: true, damage: 1);
      g.apply(ChallengeMove(0, shenzi, d));
      expect(g.state.obj(d).damage, 5);
    });
  });

  test('1.11.1 "opponents need 25 lore to win the game"', () {
    final g = emptyGame();
    g.addCard('Donald Duck - Flustered Sorcerer', 1, Place.play);
    final q = g.addCard(vanilla, 0, Place.play);
    g.state.player(0).lore = 19;
    g.apply(QuestMove(0, q));
    expect(g.state.player(0).lore, 21);
    expect(g.state.over, isFalse);
    expect(g.loreToWin(1), 20);
  });

  test('"opposing items enter play exerted"; "cards enter opponents\' inkwells exerted"', () {
    final g = emptyGame();
    g.addCard('Figaro - Tuxedo Cat', 1, Place.play);
    g.addCard('Daisy Duck - Paranormal Investigator', 1, Place.play, exerted: true);
    g.addInk(0, 2);
    final item = g.addCard('Microbots', 0, Place.hand);
    g.apply(PlayMove(0, item));
    expect(g.state.obj(item).exerted, isTrue);
    final ink = g.addCard(vanilla, 0, Place.hand);
    g.apply(InkMove(0, ink));
    expect(g.state.obj(ink).exerted, isTrue);
  });

  test('6.7.9 "this character may enter play exerted to deal 3 damage to chosen damaged character"', () {
    final g = emptyGame();
    g.addInk(0, 5);
    final d = g.addCard(vanilla2, 1, Place.play, damage: 1);
    final mac = g.addCard('Lord MacGuffin - Clever Swordsman', 0, Place.hand);
    g.apply(PlayMove(0, mac));
    expect(g.pending!.decision.kind, DecisionKind.yesNo);
    answer(g, [1]);
    while (g.pending != null) {
      answer(g, [d]);
    }
    expect(g.state.obj(mac).exerted, isTrue);
    expect(g.state.obj(d).zone, Place.discard);
  });

  test('"your Prince, Princess, King, and Queen characters get +1 {s}"; locations and characters at them', () {
    final g = emptyGame();
    g.addCard('Grand Duke - Advisor to the King', 0, Place.play);
    final eric = g.addCard('Prince Eric - Noble Swordsman', 0, Place.play);
    final plain = g.addCard(vanilla, 0, Place.play);
    expect(ch(g, eric).strength, 7);
    expect(ch(g, plain).strength, 3);
    g.addCard('Vault Door', 0, Place.play);
    expect(ch(g, plain).n(Kw.resist), 0);
    final loc = g.addCard('Agrabah - Marketplace', 0, Place.play);
    expect(ch(g, loc).n(Kw.resist), 1);
    g.state.obj(plain).at = loc;
    expect(ch(g, plain).n(Kw.resist), 1);
  });

  test('1.10.1.1 exception: "you may have up to 99 copies" / "any number of cards named"', () {
    expect(validateDeck(db, deckOf('Dalmatian Puppy - Tail Wagger')).where((e) => e.contains('copies')), isEmpty);
    expect(validateDeck(db, deckOf('Microbots')).where((e) => e.contains('copies')), isEmpty);
    expect(validateDeck(db, deckOf(vanilla)).where((e) => e.contains('copies')), isNotEmpty);
  });

  test('8.12 Sing Together is offered as a move with several singers', () {
    final g = emptyGame();
    final a = g.addCard(vanilla, 0, Place.play); // cost 3
    final b = g.addCard(vanilla, 0, Place.play); // cost 3
    final song = g.addCard('A Pirate\'s Life', 0, Place.hand); // Sing Together 6
    final sings = g.legalMoves().whereType<PlayMove>().where((m) => m.card == song && m.mode == PlayMode.sing).toList();
    expect(sings.map((m) => m.singers.toSet()), [
      {a, b},
    ]);
    g.apply(sings.single);
    expect(g.state.player(0).lore, 2);
  });

  test('6.1.3 "move up to 1 damage" may move none', () {
    final g = emptyGame();
    final alma = g.addCard('Alma Madrigal - Heart of the Family', 0, Place.play);
    final mine = g.addCard(vanilla2, 0, Place.play, damage: 1);
    final theirs = g.addCard(vanilla2, 1, Place.play);
    g.apply(QuestMove(0, alma));
    var asked = false;
    while (g.pending != null) {
      final d = g.pending!.decision;
      if (d.kind == DecisionKind.option) {
        asked = true;
        expect(d.labels, ['Move 1', 'Move 0']);
        answer(g, [1]);
      } else {
        answer(g, [d.options.contains(mine) ? mine : theirs]);
      }
    }
    expect(asked, isTrue);
    expect(g.state.obj(mine).damage, 1);
    expect(g.state.obj(theirs).damage, 0);
  });

  test('"look at the top 5 cards. Put one into your hand" must take one', () {
    final g = emptyGame();
    g.addInk(0, 2);
    final vision = g.addCard('Vision of the Future', 0, Place.hand);
    g.apply(PlayMove(0, vision));
    final d = g.pending!.decision;
    expect(d.kind, DecisionKind.cards);
    expect([d.min, d.max], [1, 1]);
  });

  test('"put one into your hand and the other into your inkwell facedown and exerted"', () {
    final g = emptyGame();
    g.addInk(0, 4);
    final song = g.addCard('How Far I\'ll Go', 0, Place.hand);
    final top = g.state.player(0).deck.take(2).toList();
    g.apply(PlayMove(0, song));
    final d = g.pending!.decision;
    expect(d.min, 1);
    answer(g, [top.first]);
    expect(g.state.obj(top.first).zone, Place.hand);
    expect(g.state.obj(top.last).zone, Place.inkwell);
    expect(g.state.obj(top.last).exerted, isTrue);
  });
}
