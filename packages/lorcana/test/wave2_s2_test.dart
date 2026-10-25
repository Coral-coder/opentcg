import 'package:lorcana/lorcana.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Wave 2, slice 2: Gruesome And Grim … Mirabel Madrigal.
const slice = [
  'Gruesome And Grim',
  'Gunther - Interior Designer',
  'Gustav the Giant - Terror of the Kingdom',
  'Hades - Double Dealer',
  'Hades - Looking for a Deal',
  "Hana's Inkcaster",
  "Hand-in-the-Box - Sid's Toy",
  'Hans - Brazen Manipulator',
  'HeiHei - Expanded Consciousness',
  'Hercules - Mighty Leader',
  'Hero Work',
  'Hidden Inkcaster',
  'Hiro Hamada - Armor Designer',
  'Hiro Hamada - Robotics Prodigy',
  'Honey Lemon - Chemical Genius',
  'Hydra - Deadly Serpent',
  'Hypnotic Deduction',
  "I'm Never Not by Your Side",
  'I2I',
  'Ichabod Crane - Bookish Schoolmaster',
  "If I Didn't Have You",
  'Infra-Pink Ultra Scan Specs',
  'Ink Geyser',
  'Invited to the Ball',
  'Isabela Madrigal - Caring Cultivator',
  'It Calls Me',
  'Jack-Jack Parr - Incredible Potential',
  'Jafar - High Sultan of Lorcana',
  'Jasmine - Fearless Princess',
  'John Silver - Greedy Treasure Seeker',
  'John Silver - Vengeful Pirate',
  'John Smith - Snow Tracker',
  'John Smith - Undaunted Protector',
  "John Smith's Compass",
  "Jolly Roger - Hook's Ship",
  'Julieta Madrigal - Excellent Cook',
  'Jumbo Pop',
  'Kakamora - Pirate Chief',
  'Keep the Ancient Ways',
  'Kida - Crystal Scion',
  'King Candy - Sweet Abomination',
  'Koda - Talkative Cub',
  'Kristoff - Icy Explorer',
  "Kristoff's Lute",
  'Kronk - Laid Back',
  'Kronk - Meat Hut Cook',
  'Kuzco - Impulsive Llama',
  'Lady - Miss Park Avenue',
  'Lady Tremaine - Sinister Socialite',
  'Last Stand',
  'Laugh Canister',
  'Launchpad - Trusty Sidekick',
  'Let The Storm Rage On',
  "Let's Get Dangerous",
  'Lilo - Best Explorer Ever',
  'Lilo - Bundled Up',
  'Lilo - Escape Artist',
  "Look What You've Done",
  'Lose the Way',
  'Lucifer - Cunning Cat',
  'Lucky - The 15th Puppy',
  'Lucky Dime',
  "Mad Hatter's Teapot",
  'Madam Mim - Hummingbird',
  'Madam Mim - Purple Dragon',
  'Madam Mim - Rival of Merlin',
  'Madame Medusa - Diamond Lover',
  'Magic Broom - Bucket Brigade',
  'Magic Broom - Swift Cleaner',
  'Magica De Spell - Cruel Sorceress',
  'Magica De Spell - Shadowy and Sinister',
  'Magica De Spell - The Midas Touch',
  'Magica De Spell - Thieving Sorceress',
  'Magical Aid',
  'Magical Hunny Staff',
  'Maleficent & Diablo - Evil Incarnate',
  'Maleficent - Formidable Queen',
  'Map of Treasure Planet',
  'Marshmallow - Cranky Climber',
  'Maui - Soaring Demigod',
  "Maui's Fish Hook",
  'Maurice - Unconventional Inventor',
  'Max Goof - Chart Topper',
  'Maximus - Relentless Stallion',
  'Maximus - Team Champion',
  'Megara - Secret Keeper',
  'Merida - Formidable Archer',
  'Merida - Wisp Conjurer',
  'Merlin - Completing His Research',
  'Merlin - Envisioning the Future',
  'Merlin - Intellectual Visionary',
  "Merlin's Cottage",
  'Merryweather - Good Fairy',
  'Metamorphosis',
  'Mickey Mouse & Minnie Mouse - Adventuring Duo',
  'Mickey Mouse - Amber Champion',
  'Mickey Mouse - Bob Cratchit',
  'Mickey Mouse - Pirate Captain',
  'Mike Wazowski - Heroic Climber',
  'Mike Wazowski - Well-Rounded Entertainer',
  'Ming Lee - Proud Parent',
  'Minnie Mouse - Amethyst Champion',
  'Minnie Mouse - Drum Major',
  'Minnie Mouse - Storyteller',
  'Mirabel Madrigal - Curious Child',
  'Mirabel Madrigal - Family Gatherer',
];

const pete = 'Pete - Freebooter'; // 3 cost, 5/2, Pirate
const gopher = "Gopher - Ship's Carpenter"; // 4 cost, 1/6, Pirate
const baBoom = 'Ba-Boom!'; // 2 cost action: deal 2 damage to chosen character or location
const felix = 'Felix Madrigal - Fun-Loving Family Man'; // Amber, 3 cost, 2/4
const antonio = 'Antonio Madrigal - Animal Expert'; // Amethyst, 3 cost, 3/4
const heroicOutlaw = 'Aladdin - Heroic Outlaw'; // Floodborn, Shift 5 onto an Aladdin

/// Answers whatever is pending with the first option, "no", or the fewest cards.
void settle(Game g) {
  while (g.pending != null) {
    final d = g.pending!.decision;
    answer(g, switch (d.kind) {
      DecisionKind.yesNo => [0],
      DecisionKind.option => [0],
      DecisionKind.order => d.options,
      DecisionKind.cards => d.options.take(d.min).toList(),
    });
  }
}

/// The index of [id]'s first ability matching [f] (its first activated one by default).
int ability(Game g, CardId id, [bool Function(Ability a)? f]) => g.parsed(id).abilities.indexWhere(f ?? (a) => a is Activated);

void main() {
  group('Parsing', () {
    test('every card of the slice is read in full, and every new effect is described', () {
      for (final n in slice) {
        final p = LorcanaParser.parse(db[n]!);
        expect(p.supported, isTrue, reason: '$n: ${p.unsupported}');
        expect(p.abilities.map(describeAbility).join(), isNot(contains('?')), reason: n);
      }
    });

    test('a capitalized story name followed by a cost is split from it (CR 6.3.1)', () {
      for (final n in ['Infra-Pink Ultra Scan Specs', 'Jasmine - Fearless Princess', 'Jumbo Pop']) {
        expect(LorcanaParser.parse(db[n]!).abilities.whereType<Activated>(), hasLength(1), reason: n);
      }
      // A story name with a hyphen in it ("Sad-Eyed Puppy - When …").
      expect(LorcanaParser.parse(db['Gunther - Interior Designer']!).abilities.single, isA<Triggered>());
    });

    test('mangled texts are fixed through the documented override table', () {
      expect(db['Let The Storm Rage On']!.text, contains('Deal 2 damage to chosen character'));
      expect(describeAbility(LorcanaParser.parse(db['Hiro Hamada - Robotics Prodigy']!).abilities.single), startsWith('ACT [exert, 2 ink]'));
    });

    test('Jack-Jack Parr: "If its card type is:" continues the ability', () {
      final abs = LorcanaParser.parse(db['Jack-Jack Parr - Incredible Potential']!).abilities;
      expect(abs, hasLength(1));
      expect(describeAbility(abs.single), contains('location → banish'));
    });
  });

  group('Playing cards (CR 4.3, 6.1.7)', () {
    test('Gruesome And Grim: a free character gains Rush and is banished at the end of the turn (CR 6.2.7.2)', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final abu = g.addCard(vanilla, 0, Place.hand);
      final target = g.addCard(gopher, 1, Place.play, exerted: true);
      g.apply(PlayMove(0, g.addCard('Gruesome And Grim', 0, Place.hand)));
      expect(g.state.obj(abu).zone, Place.play);
      expect(g.whyNot(ChallengeMove(0, abu, target)), isNull, reason: 'Rush (CR 8.9)');
      g.apply(EndTurnMove(0));
      expect(g.state.obj(abu).zone, Place.discard);
    });

    test('Hades - Double Dealer: banish one of your characters to play one with the same name for free (CR 4.4)', () {
      final g = emptyGame();
      final hades = g.addCard('Hades - Double Dealer', 0, Place.play);
      final fodder = g.addCard(vanilla2, 0, Place.play); // Aladdin
      final outlaw = g.addCard(heroicOutlaw, 0, Place.hand); // Aladdin, cost 7
      g.addCard(vanilla, 0, Place.hand);
      g.apply(ActivateMove(0, hades, ability(g, hades)));
      expect(g.state.obj(fodder).zone, Place.discard);
      expect(g.state.obj(outlaw).zone, Place.play);
      expect(g.inkReady(0), 0);
    });

    test('Hand-in-the-Box: an alternate cost from the discard (CR 1.5.5)', () {
      final g = emptyGame();
      final box = g.addCard("Hand-in-the-Box - Sid's Toy", 0, Place.hand);
      expect(g.whyNot(PlayMove(0, box)), isNotNull, reason: 'no ink, no Toy card in the discard');
      final toy = g.addCard('Bo Peep - Caring Shepherd', 0, Place.discard);
      expect(g.whyNot(PlayMove(0, box)), isNull);
      g.apply(PlayMove(0, box));
      expect(g.state.obj(box).zone, Place.play);
      expect(g.state.player(0).deck.last, toy);
      // With the ink as well, the player chooses (CR 4.3.2.2).
      final g2 = emptyGame();
      g2.addInk(0, 2);
      final box2 = g2.addCard("Hand-in-the-Box - Sid's Toy", 0, Place.hand);
      g2.addCard('Bo Peep - Caring Shepherd', 0, Place.discard);
      g2.apply(PlayMove(0, box2));
      expect(g2.pending?.decision.kind, DecisionKind.yesNo);
      answer(g2, [0], player: 0);
      expect(g2.inkReady(0), 0);
      expect(g2.state.player(0).discard, hasLength(1));
    });

    test('Maleficent & Diablo: five character cards from the discard pay for Shift (CR 1.5.5.2, 8.10)', () {
      final g = emptyGame();
      final mal = g.addCard('Maleficent - Sinister Visitor', 0, Place.play);
      final md = g.addCard('Maleficent & Diablo - Evil Incarnate', 0, Place.hand);
      final fodder = [for (var i = 0; i < 5; i++) g.addCard(vanilla, 0, Place.discard)];
      g.apply(PlayMove(0, md, mode: PlayMode.shift, onto: mal));
      expect(g.pending?.decision.kind, DecisionKind.order);
      answer(g, fodder, player: 0);
      expect(g.state.obj(md).under, contains(mal));
      expect(g.state.player(0).deck.sublist(g.state.player(0).deck.length - 5), fodder);
    });

    test("Mirabel Madrigal - Family Gatherer: can't be played without 5 characters in play", () {
      final g = emptyGame();
      g.addInk(0, 5);
      final m = g.addCard('Mirabel Madrigal - Family Gatherer', 0, Place.hand);
      for (var i = 0; i < 4; i++) {
        g.addCard(vanilla2, 0, Place.play);
      }
      expect(g.whyNot(PlayMove(0, m)), isNotNull);
      g.addCard(vanilla2, 0, Place.play);
      expect(g.whyNot(PlayMove(0, m)), isNull);
    });

    test("Keep the Ancient Ways: opponents can't play actions or items until the start of your next turn", () {
      final g = emptyGame();
      g.addInk(0, 2);
      g.addInk(1, 2);
      final item = g.addCard('Amber Chromicon', 1, Place.hand);
      final char = g.addCard(vanilla2, 1, Place.hand);
      g.apply(PlayMove(0, g.addCard('Keep the Ancient Ways', 0, Place.hand)));
      g.apply(EndTurnMove(0));
      expect(g.whyNot(PlayMove(1, item)), contains('can’t play'));
      expect(g.whyNot(PlayMove(1, char)), isNull);
      g.apply(EndTurnMove(1));
      expect(g.state.timed.where((t) => t.label.startsWith('w2:cantPlay')), isEmpty);
    });

    test('Lilo - Escape Artist plays from the discard at the start of your turn, exerted', () {
      final g = emptyGame(active: 1);
      g.addInk(0, 2);
      final lilo = g.addCard('Lilo - Escape Artist', 0, Place.discard);
      g.apply(EndTurnMove(1));
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
      answer(g, [1], player: 0);
      expect(g.state.obj(lilo).zone, Place.play);
      expect(g.state.obj(lilo).exerted, isTrue);
      expect(g.inkReady(0), 0, reason: 'she is paid for');
    });

    test("Look What You've Done: discarded during your turn, it may be played from the discard", () {
      final g = emptyGame();
      g.addInk(0, 3);
      final kronk = g.addCard('Kronk - Meat Hut Cook', 0, Place.play);
      final lwyd = g.addCard("Look What You've Done", 0, Place.hand);
      final target = g.addCard(gopher, 1, Place.play);
      final pickup = ability(g, kronk);
      g.apply(ActivateMove(0, kronk, pickup));
      answer(g, [lwyd], player: 0); // the discard
      answer(g, [1], player: 0); // play it from the discard
      answer(g, [target], player: 0);
      expect(g.state.obj(target).damage, 2);
      expect(g.inkReady(0), 0);
      // "Once during your turn" (CR 6.1.13.2).
      g.addInk(0, 1);
      expect(g.whyNot(ActivateMove(0, kronk, pickup)), 'Only once per turn');
    });

    test('Jafar: a discarded Illusion character may be played for free', () {
      final g = emptyGame();
      final jafar = g.addCard('Jafar - High Sultan of Lorcana', 0, Place.play);
      final rajah = g.addCard('Rajah - Ghostly Tiger', 0, Place.hand);
      g.apply(QuestMove(0, jafar));
      answer(g, [1], player: 0); // draw, then discard
      answer(g, [rajah], player: 0);
      answer(g, [1], player: 0); // play it
      expect(g.state.obj(rajah).zone, Place.play);
    });

    test("Kristoff's Lute: the revealed card is played as if from hand, paying its cost", () {
      final g = emptyGame();
      g.addInk(0, 5);
      final lute = g.addCard("Kristoff's Lute", 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.deck); // the top card
      g.apply(ActivateMove(0, lute, ability(g, lute)));
      answer(g, [1], player: 0);
      expect(g.state.obj(abu).zone, Place.play);
      expect(g.inkReady(0), 0);
      final g2 = emptyGame();
      g2.addInk(0, 5);
      final lute2 = g2.addCard("Kristoff's Lute", 0, Place.play);
      final abu2 = g2.addCard(vanilla, 0, Place.deck);
      g2.apply(ActivateMove(0, lute2, ability(g2, lute2)));
      answer(g2, [0], player: 0);
      expect(g2.state.obj(abu2).zone, Place.discard);
    });

    test("Let's Get Dangerous: each player may play their revealed character; otherwise it goes to the bottom", () {
      final g = emptyGame();
      g.addInk(0, 4);
      g.apply(PlayMove(0, g.addCard("Let's Get Dangerous", 0, Place.hand)));
      answer(g, [1], player: 0);
      final top1 = g.state.player(1).deck.first;
      answer(g, [0], player: 1);
      expect(g.state.player(0).play, hasLength(1));
      expect(g.state.player(1).deck.last, top1);
    });

    test('Max Goof: a song played from the discard goes to the bottom of the deck instead (CR 6.1.7)', () {
      final g = emptyGame();
      final max = g.addCard('Max Goof - Chart Topper', 0, Place.play);
      final song = g.addCard('Let The Storm Rage On', 0, Place.discard);
      final target = g.addCard(gopher, 1, Place.play);
      g.apply(QuestMove(0, max));
      answer(g, [1], player: 0);
      answer(g, [target], player: 0);
      expect(g.state.obj(target).damage, 2);
      expect(g.state.player(0).deck.last, song);
      expect(g.state.player(0).discard, isEmpty);
    });

    test('Metamorphosis: shift a character from your discard for free (CR 8.10)', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final aladdin = g.addCard(vanilla2, 0, Place.play);
      final outlaw = g.addCard(heroicOutlaw, 0, Place.discard);
      g.apply(PlayMove(0, g.addCard('Metamorphosis', 0, Place.hand)));
      expect(g.state.obj(outlaw).zone, Place.play);
      expect(g.state.obj(outlaw).under, contains(aladdin));
    });
  });

  group('Choices and decisions', () {
    test("Hades - Looking for a Deal: the chosen character's player decides", () {
      for (final tuck in [true, false]) {
        final g = emptyGame();
        g.addInk(0, 5);
        final target = g.addCard(vanilla, 1, Place.play);
        g.apply(PlayMove(0, g.addCard('Hades - Looking for a Deal', 0, Place.hand)));
        answer(g, [1], player: 0);
        answer(g, [tuck ? 1 : 0], player: 1);
        expect(g.state.obj(target).zone, tuck ? Place.deck : Place.play);
        expect(g.state.player(0).hand, hasLength(tuck ? 0 : 2));
      }
    });

    test('John Smith - Undaunted Protector: opponents must choose him if able', () {
      final g = emptyGame(active: 1);
      g.addInk(1, 2);
      final john = g.addCard('John Smith - Undaunted Protector', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      g.apply(PlayMove(1, g.addCard(baBoom, 1, Place.hand)));
      expect(g.state.obj(john).damage, 2);
      expect(g.state.obj(abu).damage, 0);
    });

    test("Lucifer: each opponent discards either 2 cards or 1 action card", () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.addCard(vanilla, 1, Place.hand);
      g.addCard(vanilla2, 1, Place.hand);
      final action = g.addCard(baBoom, 1, Place.hand);
      g.apply(PlayMove(0, g.addCard('Lucifer - Cunning Cat', 0, Place.hand)));
      expect(g.pending?.decision.labels, hasLength(2));
      answer(g, [1], player: 1);
      expect(g.state.obj(action).zone, Place.discard);
      expect(g.state.player(1).hand, hasLength(2));
    });

    test('Hypnotic Deduction: two cards from hand to the top of the deck in the chosen order', () {
      final g = emptyGame();
      g.addInk(0, 2);
      g.apply(PlayMove(0, g.addCard('Hypnotic Deduction', 0, Place.hand)));
      final hand = g.state.player(0).hand;
      answer(g, [hand[0], hand[1]], player: 0);
      final a = hand[0], b = hand[1];
      answer(g, [b, a], player: 0);
      expect(g.state.player(0).deck.take(2), [b, a]);
      expect(g.state.player(0).hand, hasLength(1));
    });
  });

  group('Damage (CR 1.9, 6.5)', () {
    test("Hercules - Mighty Leader can't be dealt damage unless he's being challenged", () {
      final g = emptyGame();
      g.addInk(0, 2);
      final herc = g.addCard('Hercules - Mighty Leader', 0, Place.play);
      g.apply(PlayMove(0, g.addCard(baBoom, 0, Place.hand)));
      expect(g.state.obj(herc).damage, 0);
      // Challenging isn't being challenged.
      final p = g.addCard(pete, 1, Place.play, exerted: true);
      g.apply(ChallengeMove(0, herc, p));
      expect(g.state.obj(herc).damage, 0);
      expect(g.state.obj(p).zone, Place.discard);
      final g2 = emptyGame(active: 1);
      final herc2 = g2.addCard('Hercules - Mighty Leader', 0, Place.play, exerted: true);
      g2.apply(ChallengeMove(1, g2.addCard(vanilla, 1, Place.play), herc2));
      expect(g2.state.obj(herc2).zone, Place.discard);
    });

    test('Hercules: while he is exerted, your other Hero characters are protected too', () {
      for (final exerted in [true, false]) {
        final g = emptyGame();
        g.addInk(0, 2);
        g.addCard('Hercules - Mighty Leader', 0, Place.play, exerted: exerted);
        final hero = g.addCard(vanilla2, 0, Place.play);
        g.apply(PlayMove(0, g.addCard(baBoom, 0, Place.hand)));
        answer(g, [hero], player: 0);
        expect(g.state.obj(hero).damage, exerted ? 0 : 2);
      }
    });

    test("Lilo - Bundled Up: the first damage in each opponent's turn is prevented", () {
      final g = emptyGame(active: 1);
      g.addInk(1, 4);
      final lilo = g.addCard('Lilo - Bundled Up', 0, Place.play);
      g.apply(PlayMove(1, g.addCard(baBoom, 1, Place.hand)));
      expect(g.state.obj(lilo).damage, 0);
      g.apply(PlayMove(1, g.addCard(baBoom, 1, Place.hand)));
      expect(g.state.obj(lilo).zone, Place.discard);
    });

    test('Hydra: deals the damage it was dealt to a chosen opposing character', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final hydra = g.addCard('Hydra - Deadly Serpent', 0, Place.play);
      final target = g.addCard(gopher, 1, Place.play);
      g.apply(PlayMove(0, g.addCard(baBoom, 0, Place.hand)));
      answer(g, [hydra], player: 0);
      expect(g.state.obj(target).damage, 2);
    });

    test('Merida - Formidable Archer: an action of yours that damages an opposing character deals 2 more', () {
      final g = emptyGame();
      g.addInk(0, 2);
      g.addCard('Merida - Formidable Archer', 0, Place.play);
      final target = g.addCard(gopher, 1, Place.play);
      g.apply(PlayMove(0, g.addCard(baBoom, 0, Place.hand)));
      answer(g, [target], player: 0);
      expect(g.state.obj(target).damage, 4);
    });

    test('Mickey Mouse & Minnie Mouse: put into the inkwell instead of being banished (CR 6.5)', () {
      final g = emptyGame(active: 1);
      final duo = g.addCard('Mickey Mouse & Minnie Mouse - Adventuring Duo', 0, Place.play, exerted: true);
      g.apply(ChallengeMove(1, g.addCard('Hydra - Deadly Serpent', 1, Place.play), duo));
      expect(g.state.obj(duo).zone, Place.inkwell);
      expect(g.state.obj(duo).exerted, isTrue);
    });

    test("I'm Never Not by Your Side: up to 4 damage in all, 1 lore each; Isabela gains as much", () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.addCard('Isabela Madrigal - Caring Cultivator', 0, Place.play);
      final a = g.addCard(vanilla2, 0, Place.play, damage: 2);
      final b = g.addCard(felix, 0, Place.play, damage: 2);
      g.apply(PlayMove(0, g.addCard("I'm Never Not by Your Side", 0, Place.hand)));
      for (final id in [a, a, b, b]) {
        answer(g, [id], player: 0);
      }
      expect(g.state.obj(a).damage + g.state.obj(b).damage, 0);
      expect(g.state.player(0).lore, 8);
    });

    test('Julieta Madrigal: draws only if damage was removed', () {
      for (final damaged in [true, false]) {
        final g = emptyGame();
        g.addInk(0, 3);
        final hurt = g.addCard(vanilla2, 0, Place.play, damage: damaged ? 1 : 0);
        g.apply(PlayMove(0, g.addCard('Julieta Madrigal - Excellent Cook', 0, Place.hand)));
        answer(g, [1], player: 0);
        answer(g, [hurt], player: 0);
        if (damaged) answer(g, [1], player: 0);
        expect(g.pending, isNull);
        expect(g.state.player(0).hand, hasLength(damaged ? 1 : 0));
      }
    });
  });

  group('Granted abilities (CR 6.6)', () {
    test('Hero Work: your Hero characters gain a triggered ability this turn', () {
      final g = emptyGame();
      g.addInk(0, 2);
      g.state.player(1).lore = 3;
      final hero = g.addCard(vanilla2, 0, Place.play);
      final target = g.addCard(gopher, 1, Place.play, exerted: true);
      g.apply(PlayMove(0, g.addCard('Hero Work', 0, Place.hand)));
      g.apply(ChallengeMove(0, hero, target));
      expect(g.state.obj(target).damage, 3, reason: '+1 {s}');
      expect(g.state.player(0).lore, 1);
      expect(g.state.player(1).lore, 2);
      g.apply(EndTurnMove(0));
      expect(g.state.timed.where((t) => t.label.startsWith('w2:grant')), isEmpty);
    });

    test('Magical Aid: banished in a challenge, the character returns to its hand', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final abu = g.addCard(vanilla, 0, Place.play);
      final p = g.addCard(pete, 1, Place.play, exerted: true);
      g.apply(PlayMove(0, g.addCard('Magical Aid', 0, Place.hand)));
      answer(g, [abu], player: 0);
      g.apply(ChallengeMove(0, abu, p));
      expect(g.state.obj(p).zone, Place.discard);
      expect(g.state.obj(abu).zone, Place.hand);
    });

    test('Megara: with a card under her, being challenged makes each opponent discard', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final meg = g.addCard('Megara - Secret Keeper', 0, Place.play);
      g.apply(ActivateMove(0, meg, ability(g, meg, (a) => a is KeywordAbility && a.keyword.kw == Kw.boost)));
      expect(g.chars(meg).lore, 2);
      g.apply(EndTurnMove(0));
      g.state.obj(meg).exerted = true;
      final hand = g.state.player(1).hand.length;
      g.apply(ChallengeMove(1, g.addCard(pete, 1, Place.play), meg));
      expect(g.state.player(1).hand, hasLength(hand - 1));
    });

    test('Lilo - Best Explorer Ever: the chosen Alien can challenge ready characters', () {
      final g = emptyGame();
      final lilo = g.addCard('Lilo - Best Explorer Ever', 0, Place.play);
      final alien = g.addCard('Billy Bones - Keeper of the Map', 0, Place.play);
      final ready = g.addCard(gopher, 1, Place.play);
      expect(g.whyNot(ChallengeMove(0, alien, ready)), isNotNull);
      g.apply(QuestMove(0, lilo));
      expect(g.whyNot(ChallengeMove(0, alien, ready)), isNull);
      expect(g.chars(alien).n(Kw.challenger), 2);
    });

    test('Mickey Mouse - Pirate Captain: the chosen Pirate takes no damage from challenges', () {
      final g = emptyGame();
      final mickey = g.addCard('Mickey Mouse - Pirate Captain', 0, Place.play);
      final p = g.addCard(pete, 0, Place.play);
      final target = g.addCard(gopher, 1, Place.play, exerted: true);
      g.apply(QuestMove(0, mickey));
      answer(g, [p], player: 0);
      g.apply(ChallengeMove(0, p, target));
      expect(g.state.obj(target).zone, Place.discard, reason: '7 strength');
      expect(g.state.obj(p).damage, 0);
    });

    test('Magical Hunny Staff: the Hunny classification for a while, once a turn', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final staff = g.addCard('Magical Hunny Staff', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      final gift = ability(g, staff);
      final spell = g.parsed(staff).abilities.lastIndexWhere((a) => a is Activated);
      expect(g.chars(abu).classes, isNot(contains('Hunny')));
      g.apply(ActivateMove(0, staff, gift));
      expect(g.whyNot(ActivateMove(0, staff, gift)), 'Only once per turn');
      g.apply(ActivateMove(0, staff, spell));
      expect(g.chars(abu).has(Kw.evasive), isTrue);
    });

    test('Maui - Soaring Demigod loses Reckless when HeiHei quests', () {
      final g = emptyGame();
      final maui = g.addCard('Maui - Soaring Demigod', 0, Place.play);
      final heihei = g.addCard('HeiHei - Boat Snack', 0, Place.play);
      expect(g.whyNot(QuestMove(0, maui)), isNotNull);
      g.apply(QuestMove(0, heihei));
      settle(g); // HeiHei's Support too
      expect(g.whyNot(QuestMove(0, maui)), isNull);
      expect(g.chars(maui).lore, 1);
    });
  });

  group('Statics (CR 6.4)', () {
    test('Hidden Inkcaster: cards in your hand count as having the inkwell symbol (CR 4.2)', () {
      final g = emptyGame();
      final hades = g.addCard('Hades - Looking for a Deal', 0, Place.hand);
      expect(g.whyNot(InkMove(0, hades)), isNotNull);
      g.addCard('Hidden Inkcaster', 0, Place.play);
      expect(g.whyNot(InkMove(0, hades)), isNull);
    });

    test("Kronk - Laid Back: effects can't make you discard; Magica only in opponents' turns", () {
      for (final protector in ['Kronk - Laid Back', 'Magica De Spell - Cruel Sorceress']) {
        final g = emptyGame(active: 1);
        g.addInk(1, 4);
        g.addCard(protector, 0, Place.play);
        g.addCard(vanilla, 0, Place.hand);
        g.apply(PlayMove(1, g.addCard('Honey Lemon - Chemical Genius', 1, Place.hand)));
        answer(g, [1], player: 1);
        expect(g.state.player(0).hand, hasLength(1), reason: protector);
      }
      final g = emptyGame();
      g.addInk(0, 1);
      g.addCard('Magica De Spell - Cruel Sorceress', 0, Place.play);
      final kronk = g.addCard('Kronk - Meat Hut Cook', 0, Place.play);
      g.apply(ActivateMove(0, kronk, ability(g, kronk)));
      expect(g.state.player(0).discard, hasLength(1), reason: 'her own turn');
    });

    test("Koda: you can't lose lore during opponents' turns", () {
      final g = emptyGame(active: 1);
      g.addInk(1, 2);
      g.state.player(0).lore = 5;
      g.addCard('Koda - Talkative Cub', 0, Place.play);
      final mine = g.addCard(gopher, 0, Place.play, exerted: true);
      final hero = g.addCard(vanilla2, 1, Place.play);
      g.apply(PlayMove(1, g.addCard('Hero Work', 1, Place.hand)));
      g.apply(ChallengeMove(1, hero, mine));
      expect(g.state.player(0).lore, 5);
      expect(g.state.player(1).lore, 1);
    });

    test('Jolly Roger: Pirates move here for free; Map of Treasure Planet: 1 less to move (CR 4.7)', () {
      final g = emptyGame();
      final ship = g.addCard("Jolly Roger - Hook's Ship", 0, Place.play);
      final p = g.addCard(pete, 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      expect(g.whyNot(MoveMove(0, p, ship)), isNull);
      expect(g.whyNot(MoveMove(0, abu, ship)), isNotNull);
      g.addInk(0, 1);
      expect(g.whyNot(MoveMove(0, abu, ship)), isNotNull, reason: 'costs 2');
      g.addCard('Map of Treasure Planet', 0, Place.play);
      expect(g.whyNot(MoveMove(0, abu, ship)), isNull);
    });

    test('John Silver - Greedy Treasure Seeker: Resist +1 and +1 lore for each location', () {
      final g = emptyGame();
      final js = g.addCard('John Silver - Greedy Treasure Seeker', 0, Place.play);
      g.addCard("Jolly Roger - Hook's Ship", 0, Place.play);
      g.addCard('Castle Wyvern - Above the Clouds', 0, Place.play);
      expect(g.chars(js).n(Kw.resist), 2);
      expect(g.chars(js).lore, 3);
    });

    test('Mickey Mouse - Amber Champion: inks in filters (CR 5.2.5)', () {
      final g = emptyGame();
      final mickey = g.addCard('Mickey Mouse - Amber Champion', 0, Place.play);
      final amber = g.addCard(felix, 0, Place.play);
      final amethyst = g.addCard(antonio, 0, Place.play);
      expect(g.chars(amber).willpower, 6);
      expect(g.chars(amethyst).willpower, 4);
      expect(g.chars(mickey).has(Kw.singer), isFalse);
      g.addCard('Agustin Madrigal - Clumsy Dad', 0, Place.play);
      expect(g.chars(mickey).n(Kw.singer), 8);
    });

    test('Minnie Mouse - Amethyst Champion: another Amethyst character banished in a challenge', () {
      final g = emptyGame(active: 1);
      g.addCard('Minnie Mouse - Amethyst Champion', 0, Place.play);
      final a = g.addCard(antonio, 0, Place.play, exerted: true);
      g.apply(ChallengeMove(1, g.addCard(pete, 1, Place.play), a));
      answer(g, [1], player: 0);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Hiro Hamada - Armor Designer: Floodborn characters with a card under them gain Evasive and Ward', () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.addCard('Hiro Hamada - Armor Designer', 0, Place.play);
      final aladdin = g.addCard(vanilla2, 0, Place.play);
      final outlaw = g.addCard(heroicOutlaw, 0, Place.hand);
      final alma = g.addCard('Alma Madrigal - Keeper of the Flame', 0, Place.play);
      g.apply(PlayMove(0, outlaw, mode: PlayMode.shift, onto: aladdin));
      expect(g.chars(outlaw).has(Kw.evasive) && g.chars(outlaw).has(Kw.ward), isTrue);
      expect(g.chars(alma).has(Kw.evasive), isFalse);
    });

    test("Maui's Fish Hook: with Maui in play, Shapeshift costs no ink (CR 6.1.7.1)", () {
      final g = emptyGame();
      final hook = g.addCard("Maui's Fish Hook", 0, Place.play);
      final shapeshift = ability(g, hook);
      expect(g.whyNot(ActivateMove(0, hook, shapeshift)), 'Not enough ink');
      g.addCard('Maui - Demigod', 0, Place.play);
      expect(g.whyNot(ActivateMove(0, hook, shapeshift)), isNull);
    });

    test('Gustav the Giant enters exerted, stays exerted, and readies when another banishes in a challenge', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final gustav = g.addCard('Gustav the Giant - Terror of the Kingdom', 0, Place.hand);
      g.apply(PlayMove(0, gustav));
      expect(g.state.obj(gustav).exerted, isTrue);
      g.apply(EndTurnMove(0));
      g.apply(EndTurnMove(1));
      expect(g.state.obj(gustav).exerted, isTrue, reason: "can't ready at the start of your turn");
      final billy = g.addCard('Billy Bones - Keeper of the Map', 0, Place.play); // 6/5
      g.apply(ChallengeMove(0, billy, g.addCard(vanilla2, 1, Place.play, exerted: true)));
      answer(g, [1], player: 0);
      expect(g.state.obj(gustav).exerted, isFalse);
    });

    test('Maximus - Relentless Stallion: after you discard, Challenger +2 and can challenge ready characters', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final max = g.addCard('Maximus - Relentless Stallion', 0, Place.play);
      final kronk = g.addCard('Kronk - Meat Hut Cook', 0, Place.play);
      expect(g.chars(max).has(Kw.challenger), isFalse);
      g.apply(ActivateMove(0, kronk, ability(g, kronk)));
      expect(g.chars(max).n(Kw.challenger), 2);
      expect(g.chars(max).rules, contains(Rule.canChallengeReady));
    });

    test('Last Stand: only a character that was challenged this turn', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final aladdin = g.addCard(vanilla2, 0, Place.play);
      final challenged = g.addCard(gopher, 1, Place.play, exerted: true);
      final other = g.addCard(vanilla, 1, Place.play);
      g.apply(ChallengeMove(0, aladdin, challenged));
      g.apply(PlayMove(0, g.addCard('Last Stand', 0, Place.hand)));
      expect(g.state.obj(challenged).zone, Place.discard);
      expect(g.state.obj(other).zone, Place.play);
    });

    test("Magica De Spell - Thieving Sorceress: an item with cost up to her strength", () {
      final g = emptyGame();
      final magica = g.addCard('Magica De Spell - Thieving Sorceress', 0, Place.play);
      final cheap = g.addCard('Amber Chromicon', 1, Place.play);
      final dear = g.addCard('Lucky Dime', 1, Place.play);
      g.apply(ActivateMove(0, magica, ability(g, magica)));
      expect(g.state.obj(cheap).zone, Place.hand);
      expect(g.state.obj(dear).zone, Place.play);
    });
  });

  group('Zones (CR 7)', () {
    test('HeiHei - Expanded Consciousness puts the whole hand into the inkwell, exerted', () {
      final g = emptyGame();
      g.addInk(0, 5);
      for (var i = 0; i < 3; i++) {
        g.addCard(vanilla, 0, Place.hand);
      }
      g.apply(PlayMove(0, g.addCard('HeiHei - Expanded Consciousness', 0, Place.hand)));
      expect(g.state.player(0).hand, isEmpty);
      expect(g.state.player(0).inkwell, hasLength(8));
      expect(g.inkReady(0), 0);
    });

    test('I2I sung together: both singers ready and can\'t quest (CR 8.12)', () {
      final g = emptyGame();
      final hydra = g.addCard('Hydra - Deadly Serpent', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      g.apply(PlayMove(0, g.addCard('I2I', 0, Place.hand), mode: PlayMode.sing, singers: [hydra, abu]));
      expect(g.state.obj(hydra).exerted || g.state.obj(abu).exerted, isFalse);
      expect(g.whyNot(QuestMove(0, hydra)), isNotNull);
      expect(g.state.player(0).lore, 2);
      expect(g.state.player(1).lore, 2);
      expect(g.state.player(1).hand, hasLength(2));
    });

    test('Ink Geyser: inkwells exerted, and down to 3 cards', () {
      final g = emptyGame();
      g.addInk(0, 8);
      g.addInk(1, 2);
      g.apply(PlayMove(0, g.addCard('Ink Geyser', 0, Place.hand)));
      expect(g.state.player(0).inkwell, hasLength(3));
      expect(g.state.player(0).hand, hasLength(5));
      expect(g.state.player(1).inkwell, hasLength(2));
      expect(g.inkReady(1), 0);
    });

    test('Jack-Jack Parr: the milled card\'s type decides', () {
      final g = emptyGame(active: 1);
      final jj = g.addCard('Jack-Jack Parr - Incredible Potential', 0, Place.play);
      g.addCard(vanilla, 0, Place.deck);
      g.apply(EndTurnMove(1));
      answer(g, [1], player: 0);
      expect(g.chars(jj).strength, 6);
      final g2 = emptyGame(active: 1);
      g2.addCard('Jack-Jack Parr - Incredible Potential', 0, Place.play);
      final victim = g2.addCard(gopher, 1, Place.play);
      g2.addCard('Castle Wyvern - Above the Clouds', 0, Place.deck);
      g2.apply(EndTurnMove(1));
      answer(g2, [1], player: 0);
      answer(g2, [victim], player: 0);
      expect(g2.state.obj(victim).zone, Place.discard);
    });

    test('Marshmallow: each opponent readies only 1 character next turn (CR 3.2.1)', () {
      final g = emptyGame();
      final marsh = g.addCard('Marshmallow - Cranky Climber', 0, Place.play);
      final theirs = [for (var i = 0; i < 3; i++) g.addCard(vanilla2, 1, Place.play, exerted: true)];
      g.apply(QuestMove(0, marsh));
      g.apply(EndTurnMove(0));
      expect(g.pending?.decision.player, 1);
      answer(g, [theirs[1]], player: 1);
      expect([for (final id in theirs) g.state.obj(id).exerted], [true, false, true]);
      expect(g.state.timed.where((t) => t.label.startsWith('w2:readyLimit')), isEmpty);
    });

    test('Kristoff - Icy Explorer: a card leaving your discard draws, once during your turn', () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.addCard('Kristoff - Icy Explorer', 0, Place.play);
      g.addCard('Magic Broom - Bucket Brigade', 0, Place.discard);
      g.addCard('Magic Broom - Bucket Brigade', 0, Place.discard);
      g.apply(PlayMove(0, g.addCard('Magic Broom - Swift Cleaner', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.player(0).discard, isEmpty);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Hiro Hamada - Robotics Prodigy: the found card ends on top of the shuffled deck', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final hiro = g.addCard('Hiro Hamada - Robotics Prodigy', 0, Place.play);
      final item = g.addCard('Amber Chromicon', 0, Place.deck);
      g.apply(ActivateMove(0, hiro, ability(g, hiro)));
      answer(g, [item], player: 0);
      expect(g.state.player(0).deck.first, item);
    });

    test('Merlin - Intellectual Visionary: shifted, he searches the deck for any card', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final under = g.addCard('Merlin - Envisioning the Future', 0, Place.play);
      final merlin = g.addCard('Merlin - Intellectual Visionary', 0, Place.hand);
      final abu = g.addCard(vanilla, 0, Place.deck);
      g.apply(PlayMove(0, merlin, mode: PlayMode.shift, onto: under));
      answer(g, [1], player: 0);
      answer(g, [abu], player: 0);
      expect(g.state.obj(abu).zone, Place.hand);
    });

    test('Merlin - Envisioning the Future: draws from the bottom; banished, he goes to the bottom of the deck', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final abu = g.addCard(vanilla, 0, Place.deck);
      g.state.player(0).deck
        ..remove(abu)
        ..add(abu);
      final merlin = g.addCard('Merlin - Envisioning the Future', 0, Place.hand);
      g.apply(PlayMove(0, merlin));
      answer(g, [1], player: 0);
      expect(g.state.obj(abu).zone, Place.hand);
      g.apply(EndTurnMove(0));
      g.state.obj(merlin).exerted = true;
      g.apply(ChallengeMove(1, g.addCard(pete, 1, Place.play), merlin));
      expect(g.state.player(0).deck.last, merlin);
    });

    test('Mickey Mouse - Bob Cratchit: the cards under him go under another of yours', () {
      final g = emptyGame();
      final bob = g.addCard('Mickey Mouse - Bob Cratchit', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      g.apply(QuestMove(0, bob));
      expect(g.state.obj(bob).under, hasLength(1));
      final card = g.state.obj(bob).under.first;
      g.apply(EndTurnMove(0));
      g.apply(ChallengeMove(1, g.addCard(pete, 1, Place.play), bob));
      answer(g, [1], player: 0);
      expect(g.state.obj(abu).under, [card]);
    });

    test('Merlin - Completing His Research: draws 2 only if he had a card under him (CR 6.7.7)', () {
      for (final boosted in [true, false]) {
        final g = emptyGame();
        g.addInk(0, 2);
        final merlin = g.addCard('Merlin - Completing His Research', 0, Place.play);
        if (boosted) g.apply(ActivateMove(0, merlin, ability(g, merlin, (a) => a is KeywordAbility && a.keyword.kw == Kw.boost)));
        g.apply(EndTurnMove(0));
        g.state.obj(merlin).exerted = true;
        g.apply(ChallengeMove(1, g.addCard(pete, 1, Place.play), merlin));
        expect(g.state.player(0).hand, hasLength(boosted ? 2 : 0));
      }
    });

    test('Lucky - The 15th Puppy: any revealed character cards with cost 2 or less', () {
      final g = emptyGame();
      final lucky = g.addCard('Lucky - The 15th Puppy', 0, Place.play);
      final big = g.addCard(vanilla, 0, Place.deck); // cost 3
      g.apply(ActivateMove(0, lucky, ability(g, lucky)));
      final d = g.pending!.decision;
      expect(d.options, isNot(contains(big)));
      expect(d.max, 2);
      answer(g, d.options, player: 0);
      expect(g.state.player(0).hand, hasLength(2));
      expect(g.state.player(0).deck.last, big);
    });

    test('Kakamora: discarding a Pirate deals 3 damage instead of 1', () {
      for (final pirate in [true, false]) {
        final g = emptyGame();
        final k = g.addCard('Kakamora - Pirate Chief', 0, Place.play);
        final discard = g.addCard(pirate ? pete : vanilla, 0, Place.hand);
        final target = g.addCard(gopher, 1, Place.play);
        g.apply(QuestMove(0, k));
        answer(g, [1], player: 0);
        answer(g, [discard], player: 0);
        answer(g, [target], player: 0);
        expect(g.state.obj(target).damage, pirate ? 3 : 1);
      }
    });

    test('Lady Tremaine: after a Boost, an action from the discard, then to the bottom of the deck', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final lady = g.addCard('Lady Tremaine - Sinister Socialite', 0, Place.play);
      final action = g.addCard(baBoom, 0, Place.discard);
      final target = g.addCard(gopher, 1, Place.play);
      g.apply(ActivateMove(0, lady, ability(g, lady, (a) => a is KeywordAbility && a.keyword.kw == Kw.boost)));
      g.apply(QuestMove(0, lady));
      answer(g, [1], player: 0);
      answer(g, [target], player: 0);
      expect(g.state.obj(target).damage, 2);
      expect(g.state.player(0).deck.last, action);
    });

    test('Merida - Wisp Conjurer: another character of yours entering play exerted draws', () {
      final g = emptyGame();
      g.addInk(0, 3);
      g.addCard('Merida - Wisp Conjurer', 0, Place.play);
      g.apply(PlayMove(0, g.addCard('Gustav the Giant - Terror of the Kingdom', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.player(0).hand, hasLength(1));
    });
  });

  group('Conditions', () {
    test('Ichabod Crane: inks the top card only after a 5-cost character this turn', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final ichabod = g.addCard('Ichabod Crane - Bookish Schoolmaster', 0, Place.play);
      g.apply(PlayMove(0, g.addCard('Hades - Looking for a Deal', 0, Place.hand)));
      answer(g, [0], player: 0);
      g.apply(QuestMove(0, ichabod));
      expect(g.state.player(0).inkwell, hasLength(6));
    });

    test('Hans - Brazen Manipulator: lore when an opponent has 2 or more ready characters', () {
      final g = emptyGame(active: 1);
      g.addCard('Hans - Brazen Manipulator', 0, Place.play);
      g.addCard(vanilla2, 1, Place.play);
      g.addCard(vanilla2, 1, Place.play);
      g.apply(EndTurnMove(1));
      expect(g.state.player(0).lore, 2);
    });

    test("John Smith's Compass: banished after a challenge; otherwise a look at the top card", () {
      final g = emptyGame();
      final compass = g.addCard("John Smith's Compass", 0, Place.play);
      g.apply(ChallengeMove(0, g.addCard(vanilla2, 0, Place.play), g.addCard(gopher, 1, Place.play, exerted: true)));
      g.apply(EndTurnMove(0));
      settle(g); // both abilities trigger; their conditions are checked as they resolve (CR 6.2.4)
      expect(g.state.obj(compass).zone, Place.discard);
      expect(g.state.player(0).hand, isEmpty, reason: 'YOUR PATH does nothing');
    });

    test('John Silver - Vengeful Pirate costs 2 less after an opposing character was damaged', () {
      final g = emptyGame();
      g.addInk(0, 8);
      final js = g.addCard('John Silver - Vengeful Pirate', 0, Place.hand);
      expect(g.playCost(0, js), 8);
      g.addCard(gopher, 1, Place.play);
      g.apply(PlayMove(0, g.addCard(baBoom, 0, Place.hand)));
      expect(g.playCost(0, js), 6);
    });
  });

  group('More of the slice', () {
    test('Gunther: challenged and banished, each opponent returns one of their characters to their hand', () {
      final g = emptyGame(active: 1);
      final gunther = g.addCard('Gunther - Interior Designer', 0, Place.play, exerted: true);
      final billy = g.addCard('Billy Bones - Keeper of the Map', 1, Place.play);
      final abu = g.addCard(vanilla, 1, Place.play);
      g.apply(ChallengeMove(1, billy, gunther));
      answer(g, [abu], player: 1);
      expect(g.state.obj(abu).zone, Place.hand);
    });

    test('Kuzco - Impulsive Llama: their chosen character to the bottom, then they may draw', () {
      final g = emptyGame();
      g.addInk(0, 7);
      final abu = g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Kuzco - Impulsive Llama', 0, Place.hand)));
      answer(g, [1], player: 1);
      expect(g.state.player(1).deck.last, abu);
      expect(g.state.player(1).hand, hasLength(1));
    });

    test('Lady - Miss Park Avenue: up to 2 character cards with cost 2 or less each', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final a = g.addCard(vanilla2, 0, Place.discard), b = g.addCard(vanilla2, 0, Place.discard);
      final abu = g.addCard(vanilla, 0, Place.discard);
      g.apply(PlayMove(0, g.addCard('Lady - Miss Park Avenue', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.pending!.decision.options, [a, b]);
      answer(g, [a, b], player: 0);
      expect(g.state.player(0).hand, [a, b]);
      expect(g.state.obj(abu).zone, Place.discard);
    });

    test('Launchpad: no discard with Darkwing Duck in play', () {
      for (final darkwing in [true, false]) {
        final g = emptyGame();
        final lp = g.addCard('Launchpad - Trusty Sidekick', 0, Place.play);
        if (darkwing) g.addCard('Darkwing Duck - Crime Fighter', 0, Place.play);
        g.apply(ActivateMove(0, lp, ability(g, lp)));
        expect(g.state.player(0).hand, hasLength(darkwing ? 1 : 0));
      }
    });

    test("Lose the Way: after the discard, the exerted character can't ready at the start of their next turn", () {
      final g = emptyGame();
      g.addInk(0, 2);
      final abu = g.addCard(vanilla, 1, Place.play);
      g.addCard(vanilla2, 0, Place.hand);
      g.apply(PlayMove(0, g.addCard('Lose the Way', 0, Place.hand)));
      answer(g, [1], player: 0);
      g.apply(EndTurnMove(0));
      expect(g.state.obj(abu).exerted, isTrue);
    });

    test('Laugh Canister: the chosen opponent may ink their top card too', () {
      final g = emptyGame();
      final can = g.addCard('Laugh Canister', 0, Place.play);
      g.apply(ActivateMove(0, can, ability(g, can)));
      answer(g, [1], player: 1);
      expect(g.state.player(0).inkwell, hasLength(1));
      expect(g.state.player(1).inkwell, hasLength(1));
      expect(g.inkReady(1), 0);
    });

    test('Kida - Crystal Scion: each player may ink up to 5 cards from their discard', () {
      final g = emptyGame();
      g.addInk(0, 8);
      final mine = [for (var i = 0; i < 3; i++) g.addCard(vanilla, 0, Place.discard)];
      for (var i = 0; i < 2; i++) {
        g.addCard(vanilla, 1, Place.discard);
      }
      g.apply(PlayMove(0, g.addCard('Kida - Crystal Scion', 0, Place.hand)));
      answer(g, [1], player: 0);
      answer(g, mine, player: 0);
      answer(g, [0], player: 1);
      expect(g.state.player(0).inkwell, hasLength(11));
      expect(mine.every((id) => g.state.obj(id).exerted), isTrue);
      expect(g.state.player(1).discard, hasLength(2));
    });

    test('Mike Wazowski - Heroic Climber: each player decides about their own revealed card', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final top0 = g.state.player(0).deck.first, top1 = g.state.player(1).deck.first;
      g.apply(PlayMove(0, g.addCard('Mike Wazowski - Heroic Climber', 0, Place.hand)));
      expect(g.pending!.decision.player, 0);
      answer(g, [top0], player: 0);
      answer(g, [], player: 1);
      expect(g.state.obj(top0).zone, Place.hand);
      expect(g.state.player(1).deck.last, top1);
    });

    test('Magica De Spell - The Midas Touch: lore equal to the cost of one of your items', () {
      final g = emptyGame();
      final magica = g.addCard('Magica De Spell - The Midas Touch', 0, Place.play);
      g.addCard('Amber Chromicon', 0, Place.play);
      final dime = g.addCard('Lucky Dime', 0, Place.play);
      g.apply(QuestMove(0, magica));
      answer(g, [dime], player: 0);
      expect(g.state.player(0).lore, 7);
    });

    test('Magic Broom - Bucket Brigade: a card from any discard back into its deck', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final abu = g.addCard(vanilla, 1, Place.discard);
      g.apply(PlayMove(0, g.addCard('Magic Broom - Bucket Brigade', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.player(1).deck, contains(abu));
    });

    test("Hana's Inkcaster: Resist +1 only with a card under the character", () {
      final g = emptyGame();
      final hana = g.addCard("Hana's Inkcaster", 0, Place.play);
      final t = g.addCard(vanilla2, 0, Place.play, damage: 2);
      final u = g.addCard(vanilla, 0, Place.discard);
      g.state.player(0).discard.remove(u);
      g.state.obj(u).zone = Place.play;
      g.state.obj(t).under.add(u);
      g.apply(ActivateMove(0, hana, ability(g, hana)));
      expect(g.state.obj(t).damage, 0);
      expect(g.chars(t).n(Kw.resist), 1);
    });

    test('Madam Mim - Purple Dragon: or return 2 other characters of yours', () {
      final g = emptyGame();
      g.addInk(0, 7);
      final a = g.addCard(vanilla2, 0, Place.play), b = g.addCard(vanilla2, 0, Place.play);
      final mim = g.addCard('Madam Mim - Purple Dragon', 0, Place.hand);
      g.apply(PlayMove(0, mim));
      answer(g, [1], player: 0);
      expect(g.state.player(0).hand, [a, b]);
      expect(g.state.obj(mim).zone, Place.play);
    });

    test('Maleficent - Formidable Queen: one return for each Maleficent, each its own choice', () {
      final g = emptyGame();
      g.addInk(0, 8);
      g.addCard('Maleficent - Sinister Visitor', 0, Place.play);
      final x = g.addCard(vanilla, 1, Place.play), y = g.addCard(vanilla2, 1, Place.play), z = g.addCard(gopher, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Maleficent - Formidable Queen', 0, Place.hand)));
      answer(g, [x], player: 0);
      expect(g.state.obj(x).zone, Place.hand);
      expect(g.state.obj(y).zone, Place.hand);
      expect(g.state.obj(z).zone, Place.play, reason: 'cost 4');
    });

    test("Madame Medusa: damage one of yours to mill 3 of chosen player's deck", () {
      final g = emptyGame();
      final medusa = g.addCard('Madame Medusa - Diamond Lover', 0, Place.play);
      final mine = g.addCard(gopher, 0, Place.play);
      g.apply(QuestMove(0, medusa));
      answer(g, [1], player: 0);
      answer(g, [1], player: 0); // player B
      expect(g.state.obj(mine).damage, 2);
      expect(g.state.player(1).discard, hasLength(3));
    });

    test('Mirabel Madrigal - Curious Child: lore only by revealing a song', () {
      for (final song in [true, false]) {
        final g = emptyGame();
        g.addInk(0, 1);
        if (song) g.addCard('A Very Merry Unbirthday', 0, Place.hand);
        g.apply(PlayMove(0, g.addCard('Mirabel Madrigal - Curious Child', 0, Place.hand)));
        answer(g, [1], player: 0);
        expect(g.state.player(0).lore, song ? 1 : 0);
      }
    });

    test('Ming Lee costs 1 less after a song this turn', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final ming = g.addCard('Ming Lee - Proud Parent', 0, Place.hand);
      expect(g.playCost(0, ming), 3);
      g.apply(PlayMove(0, g.addCard('A Very Merry Unbirthday', 0, Place.hand)));
      expect(g.playCost(0, ming), 2);
    });

    test('John Smith - Snow Tracker: lore at the end of the turn while exerted', () {
      for (final exerted in [true, false]) {
        final g = emptyGame();
        g.addCard('John Smith - Snow Tracker', 0, Place.play, exerted: exerted);
        g.apply(EndTurnMove(0));
        expect(g.state.player(0).lore, exerted ? 1 : 0);
      }
    });

    test("Infra-Pink, Mad Hatter's Teapot, Jumbo Pop, Jasmine: their activated abilities", () {
      final g = emptyGame();
      g.addInk(0, 1);
      final specs = g.addCard('Infra-Pink Ultra Scan Specs', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play, damage: 1);
      g.apply(ActivateMove(0, specs, ability(g, specs)));
      expect(g.state.obj(specs).zone, Place.discard);
      expect(g.chars(abu).has(Kw.alert), isTrue);
      final teapot = g.addCard("Mad Hatter's Teapot", 0, Place.play);
      g.apply(ActivateMove(0, teapot, ability(g, teapot)));
      expect(g.state.player(1).discard, hasLength(1));
      final pop = g.addCard('Jumbo Pop', 0, Place.play);
      g.apply(ActivateMove(0, pop, ability(g, pop)));
      expect(g.state.obj(abu).damage, 0);
      expect(g.state.player(0).hand, hasLength(1));
      final jas = g.addCard('Jasmine - Fearless Princess', 0, Place.play);
      g.apply(ActivateMove(0, jas, ability(g, jas)));
      expect(g.state.player(0).hand, isEmpty);
      expect(g.chars(jas).n(Kw.challenger), 3);
    });

    test('Honey Lemon: pay 2 to have each opponent choose and discard a card', () {
      final g = emptyGame();
      g.addInk(0, 4);
      g.addCard(vanilla, 1, Place.hand);
      g.apply(PlayMove(0, g.addCard('Honey Lemon - Chemical Genius', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.player(1).hand, isEmpty);
      expect(g.inkReady(0), 0);
    });

    test('King Candy: draw 2, then a card from hand to the bottom of the deck', () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.apply(PlayMove(0, g.addCard('King Candy - Sweet Abomination', 0, Place.hand)));
      answer(g, [1], player: 0);
      final put = g.state.player(0).hand.first;
      answer(g, [put], player: 0);
      expect(g.state.player(0).deck.last, put);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test("It Calls Me: up to 3 cards from chosen opponent's discard into their deck", () {
      final g = emptyGame();
      g.addInk(0, 1);
      final cards = [for (var i = 0; i < 4; i++) g.addCard(vanilla, 1, Place.discard)];
      g.apply(PlayMove(0, g.addCard('It Calls Me', 0, Place.hand)));
      answer(g, cards.take(3).toList(), player: 0);
      expect(g.state.player(1).discard, [cards[3]]);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test("If I Didn't Have You: you and another player draw 2", () {
      final g = emptyGame();
      g.addInk(0, 3);
      g.apply(PlayMove(0, g.addCard("If I Didn't Have You", 0, Place.hand)));
      expect(g.state.player(0).hand, hasLength(2));
      expect(g.state.player(1).hand, hasLength(2));
    });

    test('Invited to the Ball: revealed characters into the hand, the rest to the bottom', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final item = g.addCard('Amber Chromicon', 0, Place.deck);
      final abu = g.addCard(vanilla, 0, Place.deck);
      g.apply(PlayMove(0, g.addCard('Invited to the Ball', 0, Place.hand)));
      expect(g.state.obj(abu).zone, Place.hand);
      expect(g.state.player(0).deck.last, item);
    });

    test('Minnie Mouse - Drum Major: shifted, a character card from the deck to its top', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final under = g.addCard('Minnie Mouse - Storyteller', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.deck);
      g.state.player(0).deck
        ..remove(abu)
        ..add(abu);
      g.apply(PlayMove(0, g.addCard('Minnie Mouse - Drum Major', 0, Place.hand), mode: PlayMode.shift, onto: under));
      answer(g, [1], player: 0);
      answer(g, [abu], player: 0);
      expect(g.state.player(0).deck.first, abu);
    });

    test("Minnie Mouse - Storyteller: the chosen opposing character loses {s} equal to her {l}", () {
      final g = emptyGame();
      g.addInk(0, 2);
      final minnie = g.addCard('Minnie Mouse - Storyteller', 0, Place.play);
      final target = g.addCard(pete, 1, Place.play);
      g.apply(PlayMove(0, g.addCard(vanilla2, 0, Place.hand))); // +1 {l} this turn
      g.apply(QuestMove(0, minnie));
      expect(g.chars(target).strength, 4);
      g.apply(EndTurnMove(0));
      expect(g.chars(target).strength, 4, reason: 'until the start of your next turn');
    });

    test('Merryweather: pay 1 to give chosen character +2 {s}', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final abu = g.addCard(vanilla, 0, Place.play);
      g.apply(PlayMove(0, g.addCard('Merryweather - Good Fairy', 0, Place.hand)));
      answer(g, [1], player: 0);
      answer(g, [abu], player: 0);
      expect(g.chars(abu).strength, 5);
    });

    test("Maurice: banishing Maurice's Machine lets him banish a weak character too", () {
      final g = emptyGame();
      g.addInk(0, 4);
      g.addCard("Maurice's Machine", 0, Place.play);
      final small = g.addCard(vanilla2, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Maurice - Unconventional Inventor', 0, Place.hand)));
      answer(g, [1], player: 0);
      answer(g, [1], player: 0);
      expect(g.state.obj(small).zone, Place.discard);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test("Magica De Spell - Shadowy and Sinister: a card from chosen player's discard into their deck", () {
      final g = emptyGame();
      g.addInk(0, 3);
      final abu = g.addCard(vanilla, 1, Place.discard);
      g.apply(PlayMove(0, g.addCard('Magica De Spell - Shadowy and Sinister', 0, Place.hand)));
      answer(g, [1], player: 0);
      answer(g, [1], player: 0); // player B
      expect(g.state.player(1).deck, contains(abu));
    });
  });

  group('Cards of other slices the new templates also read', () {
    test('"banish the challenging character": the other card in the challenge (CR 4.6)', () {
      for (final (n, mine) in [('Cheshire Cat - Not All There', 'Cheshire Cat - Not All There'), ('Goofy - Emerald Champion', 'Baloo - Laid-Back Bear')]) {
        final g = emptyGame(active: 1);
        if (n != mine) g.addCard(n, 0, Place.play);
        final victim = g.addCard(mine, 0, Place.play, exerted: true);
        final billy = g.addCard('Billy Bones - Keeper of the Map', 1, Place.play); // 6/5
        g.apply(ChallengeMove(1, billy, victim));
        expect(g.state.obj(victim).zone, Place.discard, reason: n);
        expect(g.state.obj(billy).zone, Place.discard, reason: n);
      }
    });

    test('Flotsam: a Jetsam banished in a challenge returns to its hand (granted as it left play, CR 6.7.7)', () {
      final g = emptyGame(active: 1);
      g.addCard('Flotsam - Ursula\'s "Baby"', 0, Place.play);
      final jetsam = g.addCard('Jetsam - Riffraff', 0, Place.play, exerted: true);
      g.apply(ChallengeMove(1, g.addCard('Billy Bones - Keeper of the Map', 1, Place.play), jetsam));
      settle(g);
      expect(g.state.obj(jetsam).zone, Place.hand);
    });

    test('Pluto - Steel Champion: only Steel characters trigger "whenever you play another Steel character"', () {
      final g = emptyGame();
      g.addInk(0, 4);
      g.addCard('Pluto - Steel Champion', 0, Place.play);
      g.addCard('Amber Chromicon', 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Baloo - Laid-Back Bear', 0, Place.hand))); // Emerald
      expect(g.pending, isNull);
      g.apply(PlayMove(0, g.addCard('Akela - Wolf Pack Elder', 0, Place.hand))); // Steel
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
    });

    test('Baymax - Armored Companion: 1 lore for each 1 damage removed this way', () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.addCard(vanilla2, 0, Place.play, damage: 2);
      g.apply(PlayMove(0, g.addCard('Baymax - Armored Companion', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.player(0).lore, 2);
    });

    test("Powerline: Rush only after you've played a song this turn", () {
      final g = emptyGame();
      g.addInk(0, 1);
      final p = g.addCard('Powerline - Musical Superstar', 0, Place.play);
      expect(g.chars(p).has(Kw.rush), isFalse);
      g.apply(PlayMove(0, g.addCard('A Very Merry Unbirthday', 0, Place.hand)));
      expect(g.chars(p).has(Kw.rush), isTrue);
    });
  });

  test('"more {s} than each opposing character" holds with no opposing characters (and agrees in JavaScript)', () {
    // The "lowest" start used to be -1 << 30, which dart2js computes as a large positive number.
    final g = emptyGame();
    final faline = g.addCard('Faline - Playful Fawn', 0, Place.play);
    expect(g.chars(faline).lore, (db['Faline - Playful Fawn']!.lore ?? 0) + 2);
  });

  test('determinism: the same seed and moves give the same fingerprint with this slice\'s cards', () {
    String run() {
      final decks = [
        [for (var i = 0; i < 60; i++) slice[(i * 7) % slice.length]],
        [for (var i = 0; i < 60; i++) slice[(i * 11 + 3) % slice.length]],
      ];
      final g = Game(db, players: ['A', 'B'], seed: 42);
      g.apply(StartMove(decks, firstPlayer: 0));
      runBots(g, [LorcanaBot(0, seed: 5), LorcanaBot(1, seed: 6)], maxMoves: 1500);
      return g.fingerprint;
    }

    expect(run(), run());
  });
}
