import 'package:lorcana/lorcana.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Cards Miracle Candle … Scrooge McDuck (wave 2, slice 3): costs in story names, abilities
/// used once a turn, effects for a challenge or until a later event, "this way" counts, free
/// plays from other zones, and the costs of inking, singing, moving, questing and challenging.
void main() {
  /// Answers every decision with [pick] (default: yes, the first option, the first cards).
  void settle(Game g, {List<int> Function(Decision d)? pick}) {
    for (var i = 0; i < 50 && g.pending != null; i++) {
      final d = g.pending!.decision;
      final a = pick?.call(d) ?? g.defaultAnswer(d);
      g.apply(AnswerMove(d.player, a));
    }
  }

  int act(Game g, CardId id) => g.parsed(id).abilities.indexWhere((a) => a is Activated);
  bool supported(String name) => LorcanaParser.parse(db[name]!).supported;

  test('every card of the slice is fully read', () {
    const names = [
      'Miracle Candle', 'Moana - Born Leader', 'Moana - Curious Explorer', 'Moana - Kakamora Leader', 'Monstro - Infamous Whale', //
      'Monterey Jack - Hypnotized by Cheese', "Mor'du - Savage Cursed Prince", 'Morgana Macawber - Reformed Spellcaster', 'Morph - Space Goo',
      'Morty Fieldmouse - Tiny Tim', 'Mother Gothel - Evil as Ever', "Mother Gothel - Knows What's Best", 'Mother Gothel - Unwavering Schemer',
      'Mowgli - Man Cub', 'Mr. Smee - Bumbling Mate', 'Mrs. Incredible - Created by the Vine', 'Mufasa - Ruler of Pride Rock', 'Mulan - Elite Archer',
      'Mulan - Imperial General', 'Mulan - Resourceful Recruit', 'Mulan - Standing Her Ground', 'Mushu - Majestic Dragon', 'Mystical Inkcaster',
      'Mystical Rose', "Mystical Tree - Mama Odie's Home", 'Namaari - Heir of Fang', 'Namaari - Resolute Daughter', "Nani's Payback", 'Narrow Escape',
      'Nathaniel Flint - Notorious Pirate', "Naveen's Ukulele", 'Next Stop, Olympus', 'Noi - Acrobatic Baby', "Nothing We Won't Do", 'Ohana Means Family',
      'Olaf - Carrot Enthusiast', 'Olympus Would Be That Way', 'Omnidroid - Ultimate Iteration', 'On Your Feet! Now!', 'One and Only',
      'Owl Island - Secluded Entrance', 'Pack Tactics', 'Panic - Immortal Sidekick', 'Pepa Madrigal - Weather Maker', 'Performance Review',
      'Pete - Games Referee', 'Pete - Ghost of Christmas Future', 'Pete - Space Pirate', "Peter Pan - Pirate's Bane", 'Piercing Attack', 'Pixie Dust',
      'Pizza Planet - Spaceport', 'Pluto - Clever Cluefinder', 'Pluto - Steel Champion', 'Pocahontas & Meeko - Adventurous Friends',
      'Pocahontas - Guiding the Tribe', 'Pocahontas - Peacekeeper', 'Pongo - Dear Old Dad', 'Pongo - Determined Father', 'Pot of Honey',
      'Powerline - Musical Superstar', "Powhatan's Staff", 'Pride Lands - Jungle Oasis', 'Prince Charming - Protector of the Realm',
      'Prince John - Gold Lover', 'Prince John - Greediest of All', "Prince John's Mirror", 'Prince Phillip - Dragonslayer',
      'Prince Phillip - Swordsman of the Realm', 'Priya Mangal - Serious Music Lover', 'Prophetic Vision', 'Quackerjack - Loony Toymaker',
      'RC - Remote-Controlled Car', 'RLS Legacy - Solar Galleon', 'Rafiki - Mystical Fighter', 'Raksha - Fearless Mother', 'Randall Boggs - Envious Coworker',
      'Randall Boggs - Scary Smart', 'Ranger Team-Up', 'Rapunzel & Flynn Rider - Unlikely Pair', 'Rapunzel - Escaping the Tower',
      'Rapunzel - Gifted with Healing', 'Rapunzel - Ready for Adventure', 'Ratigan - Greedy Genius', 'Ratigan - Very Large Mouse', 'Raya - Leader of Heart',
      'Record Player', 'Remote Inklands - Desert Ruins', 'Rescue Rangers Away!', 'Retro Evolution Device', 'Reuben - Sandwich Expert', 'Right Behind You',
      'Ring of Stones - Place of Legends', 'Robin Hood - Timely Contestant', "Roller Bob - Sid's Toy", 'Roo - Little Helper', 'Royal Tantrum',
      'Roz - Always Watching', 'Sail the Azurite Sea', 'Salvage Operation', 'Scar - Finally King', 'Scepter Of Arendelle', 'Scout Ahead', 'Scream Canister',
      'Scrooge McDuck - Cavern Prospector', 'Scrooge McDuck - Ebenezer Scrooge',
    ];
    expect(names, hasLength(106));
    expect([
      for (final n in names)
        if (!supported(n)) n,
    ], isEmpty);
  });

  group('Costs read as part of a story name (CR 6.3.1)', () {
    test('Miracle Candle: banish this item to gain 2 lore and heal a location', () {
      final g = emptyGame();
      final candle = g.addCard('Miracle Candle', 0, Place.play);
      for (var i = 0; i < 3; i++) {
        g.addCard(vanilla2, 0, Place.play);
      }
      final loc = g.addCard('Pizza Planet - Spaceport', 0, Place.play, damage: 3);
      g.apply(ActivateMove(0, candle, act(g, candle)));
      expect(g.state.obj(candle).zone, Place.discard);
      expect(g.state.player(0).lore, 2);
      expect(g.state.obj(loc).damage, 1);
    });

    test('Monstro: discard a card to ready him; he can\'t quest (CR 4.4)', () {
      final g = emptyGame();
      final monstro = g.addCard('Monstro - Infamous Whale', 0, Place.play, exerted: true);
      g.addCard(vanilla, 0, Place.hand);
      g.apply(ActivateMove(0, monstro, act(g, monstro)));
      expect(g.state.player(0).hand, isEmpty);
      expect(g.state.obj(monstro).exerted, isFalse);
      expect(g.whyNot(QuestMove(0, monstro)), isNotNull);
    });

    test('Pot of Honey and Scepter of Arendelle are activated abilities', () {
      for (final n in ['Pot of Honey', 'Scepter Of Arendelle', 'Mystical Rose', "Naveen's Ukulele", 'Pixie Dust']) {
        expect(LorcanaParser.parse(db[n]!).abilities.whereType<Activated>(), hasLength(1), reason: n);
      }
    });
  });

  group('Inking and the inkwell (CR 4.2, 7.5)', () {
    test('Moana - Curious Explorer: you can ink cards from your discard, still once a turn', () {
      final g = emptyGame();
      g.addCard('Moana - Curious Explorer', 0, Place.play);
      final inkable = db.cards.firstWhere((c) => c.inkable).fullName;
      final card = g.addCard(inkable, 0, Place.discard);
      expect(g.legalMoves().whereType<InkMove>().map((m) => m.card), contains(card));
      g.apply(InkMove(0, card));
      expect(g.state.obj(card).zone, Place.inkwell);
      final other = g.addCard(inkable, 0, Place.discard);
      expect(g.whyNot(InkMove(0, other)), isNotNull);
      final g2 = emptyGame();
      expect(g2.whyNot(InkMove(0, g2.addCard(inkable, 0, Place.discard))), isNotNull, reason: 'not without Moana');
    });

    test('Sail the Azurite Sea: an additional card into your inkwell this turn (CR 4.2.3)', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final inkable = db.cards.firstWhere((c) => c.inkable).fullName;
      g.apply(InkMove(0, g.addCard(inkable, 0, Place.hand)));
      g.apply(PlayMove(0, g.addCard('Sail the Azurite Sea', 0, Place.hand)));
      expect(g.whyNot(InkMove(0, g.addCard(inkable, 0, Place.hand))), isNull);
      g.apply(const EndTurnMove(0));
      g.apply(const EndTurnMove(1));
      g.apply(InkMove(0, g.addCard(inkable, 0, Place.hand)));
      expect(g.whyNot(InkMove(0, g.addCard(inkable, 0, Place.hand))), isNotNull, reason: 'only that turn');
    });

    test('Mufasa: exert all ink, then 2 cards at random from the inkwell to hand', () {
      final g = emptyGame();
      g.addInk(0, 9);
      final mufasa = g.addCard('Mufasa - Ruler of Pride Rock', 0, Place.hand);
      g.apply(PlayMove(0, mufasa));
      expect(g.state.player(0).inkwell, hasLength(7));
      expect(g.state.player(0).hand, hasLength(2));
      expect(g.state.player(0).inkwell.every((id) => g.state.obj(id).exerted), isTrue);
    });

    test('Scream Canister exerts the inkwell; Randall Boggs gets +2 lore while all ink is exerted', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final randall = g.addCard('Randall Boggs - Envious Coworker', 0, Place.play);
      expect(g.chars(randall).lore, 0);
      final can = g.addCard('Scream Canister', 0, Place.play);
      final weak = g.addCard(vanilla2, 1, Place.play);
      g.apply(ActivateMove(0, can, act(g, can)));
      settle(g);
      expect(g.state.player(0).inkwell.every((id) => g.state.obj(id).exerted), isTrue);
      expect(g.state.obj(weak).exerted, isTrue);
      expect(g.chars(randall).lore, 2);
    });

    test('Ratigan - Greedy Genius is banished at the end of a turn you inked nothing', () {
      final g = emptyGame();
      final rat = g.addCard('Ratigan - Greedy Genius', 0, Place.play);
      g.apply(const EndTurnMove(0));
      expect(g.state.obj(rat).zone, Place.discard);
      final g2 = emptyGame();
      final rat2 = g2.addCard('Ratigan - Greedy Genius', 0, Place.play);
      g2.apply(InkMove(0, g2.addCard(db.cards.firstWhere((c) => c.inkable).fullName, 0, Place.hand)));
      g2.apply(const EndTurnMove(0));
      expect(g2.state.obj(rat2).zone, Place.play);
    });

    test('Randall Boggs - Scary Smart gains 1 lore at the end of the turn if all ink is exerted', () {
      final g = emptyGame();
      g.addCard('Randall Boggs - Scary Smart', 0, Place.play);
      g.addInk(0, 2);
      g.apply(const EndTurnMove(0));
      expect(g.state.player(0).lore, 0);
      final g2 = emptyGame();
      g2.addCard('Randall Boggs - Scary Smart', 0, Place.play);
      g2.addInk(0, 0);
      g2.apply(const EndTurnMove(0));
      expect(g2.state.player(0).lore, 1, reason: 'no cards: all of them are exerted');
    });

    test('Pongo - Dear Old Dad plays a Puppy from the inkwell for free', () {
      final g = emptyGame();
      g.addCard('Pongo - Dear Old Dad', 0, Place.play);
      final puppy = db.cards.firstWhere((c) => c.hasClass('Puppy') && c.type == CardType.character).fullName;
      final id = g.addCard(puppy, 0, Place.inkwell);
      g.apply(const EndTurnMove(0));
      g.apply(const EndTurnMove(1));
      settle(g);
      expect(g.state.obj(id).zone, Place.play);
    });
  });

  group('Free plays and plays from the discard (CR 6.1.7, 4.3)', () {
    test('Mystical Inkcaster: the free character gains Rush and is banished at the end of the turn', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final caster = g.addCard('Mystical Inkcaster', 0, Place.play);
      final big = g.addCard(vanilla, 0, Place.hand);
      g.apply(ActivateMove(0, caster, act(g, caster)));
      settle(g);
      expect(g.state.obj(big).zone, Place.play);
      expect(g.chars(big).has(Kw.rush), isTrue);
      g.apply(const EndTurnMove(0));
      expect(g.state.obj(big).zone, Place.discard);
    });

    test('Mother Gothel - Evil as Ever: discarded during your turn, she may be played from the discard, paying', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final gothel = g.addCard('Mother Gothel - Evil as Ever', 0, Place.hand);
      g.apply(PlayMove(0, g.addCard('Ransack', 0, Place.hand))); // costs 2: draw 2, discard 2
      settle(g, pick: (d) => d.kind == DecisionKind.cards && d.prompt.contains('discard') ? [gothel, ...d.options.where((x) => x != gothel).take(d.min - 1)] : g.defaultAnswer(d));
      expect(g.state.obj(gothel).zone, Place.play);
      expect(g.inkReady(0), 1, reason: 'Ransack 2, then Gothel 2');
    });

    test('Rapunzel & Flynn Rider: a discarded character may be played from the discard', () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.addCard('Rapunzel & Flynn Rider - Unlikely Pair', 0, Place.play);
      final c = g.addCard(vanilla2, 0, Place.hand);
      g.apply(PlayMove(0, g.addCard('Ransack', 0, Place.hand)));
      settle(g, pick: (d) => d.kind == DecisionKind.cards && d.prompt.contains('discard') ? [c, ...d.options.where((x) => x != c).take(d.min - 1)] : g.defaultAnswer(d));
      expect(g.state.obj(c).zone, Place.play);
    });

    test('Pocahontas - Guiding the Tribe plays a character with cost exactly 1', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final one = db.cards.firstWhere((c) => c.type == CardType.character && c.cost == 1 && c.text.isEmpty).fullName;
      final a = g.addCard(one, 0, Place.hand);
      g.addCard(vanilla2, 0, Place.hand);
      g.apply(PlayMove(0, g.addCard('Pocahontas - Guiding the Tribe', 0, Place.hand)));
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
      answer(g, [1]);
      expect(g.pending, isNull, reason: 'only one card can be chosen: no question');
      expect(g.state.obj(a).zone, Place.play);
    });

    test('Prince John - Gold Lover plays an item from the discard, exerted', () {
      final g = emptyGame();
      final pj = g.addCard('Prince John - Gold Lover', 0, Place.play);
      final item = g.addCard('Pixie Dust', 0, Place.discard);
      g.apply(ActivateMove(0, pj, act(g, pj)));
      expect(g.state.obj(item).zone, Place.play);
      expect(g.state.obj(item).exerted, isTrue);
    });

    test('Pride Lands: only with 3 or more characters here, banish it to play a character from the discard', () {
      final g = emptyGame();
      final pl = g.addCard('Pride Lands - Jungle Oasis', 0, Place.play);
      final dead = g.addCard(vanilla, 0, Place.discard);
      final mine = [for (var i = 0; i < 3; i++) g.addCard(vanilla2, 0, Place.play)];
      expect(g.whyNot(ActivateMove(0, pl, act(g, pl))), isNotNull);
      for (final id in mine) {
        g.state.obj(id).at = pl;
      }
      g.apply(ActivateMove(0, pl, act(g, pl)));
      expect(g.state.obj(pl).zone, Place.discard);
      expect(g.state.obj(dead).zone, Place.play);
    });

    test('Retro Evolution Device: a character costing up to 2 more than the one banished', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final red = g.addCard('Retro Evolution Device', 0, Place.play);
      final two = g.addCard(vanilla2, 0, Place.play); // cost 2
      final three = g.addCard(vanilla, 0, Place.hand); // cost 3
      final big = g.addCard('Mufasa - Ruler of Pride Rock', 0, Place.hand); // cost 8
      g.apply(ActivateMove(0, red, act(g, red)));
      expect(g.state.obj(two).zone, Place.discard);
      expect(g.pending, isNull, reason: 'Mufasa costs too much: only one choice');
      expect(g.state.obj(three).zone, Place.play);
      expect(g.state.obj(big).zone, Place.hand);
    });

    test('Right Behind You plays a Seven Dwarfs character only with a Dwarf and a Princess in play', () {
      final dwarf = db.cards.firstWhere((c) => c.hasClass('Seven Dwarfs') && c.type == CardType.character && c.text.isEmpty).fullName;
      final princess = db.cards.firstWhere((c) => c.hasClass('Princess') && c.type == CardType.character && c.text.isEmpty).fullName;
      final g = emptyGame();
      g.addInk(0, 3);
      g.addCard(dwarf, 0, Place.play);
      g.addCard(princess, 0, Place.play);
      final free = g.addCard(dwarf, 0, Place.hand);
      g.apply(PlayMove(0, g.addCard('Right Behind You', 0, Place.hand)));
      settle(g, pick: (d) => d.kind == DecisionKind.cards ? [free] : g.defaultAnswer(d));
      expect(g.state.obj(free).zone, Place.play);
    });

    test('Prophetic Vision: an action on top may be played; otherwise lore moves', () {
      final g = emptyGame(deck: 0);
      g.addInk(0, 2);
      g.state.player(1).lore = 3;
      for (var i = 0; i < 3; i++) {
        g.addCard(vanilla2, 0, Place.deck);
      }
      g.apply(PlayMove(0, g.addCard('Prophetic Vision', 0, Place.hand)));
      expect(g.state.player(0).lore, 1);
      expect(g.state.player(1).lore, 2);
    });
  });

  group('Counting "this way" (CR 6.1.8)', () {
    test('Ohana Means Family draws a card for each damage removed', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final hurt = g.addCard('Mufasa - Ruler of Pride Rock', 0, Place.play, damage: 3);
      g.apply(PlayMove(0, g.addCard('Ohana Means Family', 0, Place.hand)));
      expect(g.state.obj(hurt).damage, 0);
      expect(g.state.player(0).hand, hasLength(3));
    });

    test('Rapunzel - Gifted with Healing removes up to 3 and draws for each', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final hurt = g.addCard('Mufasa - Ruler of Pride Rock', 0, Place.play, damage: 2);
      g.apply(PlayMove(0, g.addCard('Rapunzel - Gifted with Healing', 0, Place.hand)));
      answer(g, [hurt]);
      expect(g.state.obj(hurt).damage, 0);
      expect(g.state.player(0).hand, hasLength(2));
    });

    test('Reuben: each damage removed makes the next character 1 cheaper', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final reuben = g.addCard('Reuben - Sandwich Expert', 0, Place.play);
      g.addCard('Mufasa - Ruler of Pride Rock', 0, Place.play, damage: 2);
      g.apply(ActivateMove(0, reuben, act(g, reuben)));
      settle(g, pick: (d) => [d.options.last]);
      final c = g.addCard(vanilla, 0, Place.hand); // cost 3
      expect(g.playCost(0, c), 1);
    });

    test('Moana - Kakamora Leader gains 1 lore for each character moved', () {
      final g = emptyGame();
      g.addInk(0, 7);
      g.addCard('Pizza Planet - Spaceport', 0, Place.play);
      g.addCard(vanilla, 0, Place.play);
      g.addCard(vanilla2, 0, Place.play);
      g.apply(PlayMove(0, g.addCard('Moana - Kakamora Leader', 0, Place.hand)));
      settle(g, pick: (d) => d.kind == DecisionKind.cards ? d.options : g.defaultAnswer(d));
      expect(g.state.player(0).lore, 3, reason: 'Moana and both others');
    });

    test('Royal Tantrum draws a card for each item banished', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final items = [g.addCard('Pixie Dust', 0, Place.play), g.addCard('Miracle Candle', 0, Place.play)];
      g.apply(PlayMove(0, g.addCard('Royal Tantrum', 0, Place.hand)));
      answer(g, items);
      expect(g.state.player(0).hand, hasLength(2));
    });

    test('Quackerjack deals 1 damage for each item card milled', () {
      final g = emptyGame(deck: 0);
      g.addInk(0, 5);
      // Each card added goes on top: the top 4 are the last 4 here.
      for (final n in [vanilla, 'Pixie Dust', vanilla, 'Miracle Candle', vanilla]) {
        g.addCard(n, 0, Place.deck);
      }
      final target = g.addCard('Mufasa - Ruler of Pride Rock', 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Quackerjack - Loony Toymaker', 0, Place.hand)));
      settle(g, pick: (d) => d.kind == DecisionKind.cards ? [target] : g.defaultAnswer(d));
      expect(g.state.player(0).discard.where((id) => g.card(id).type == CardType.item), hasLength(2));
      expect(g.state.obj(target).damage, 2);
    });

    test('Scrooge McDuck - Ebenezer Scrooge draws for each lore lost; Foreclosure', () {
      final g = emptyGame();
      final scrooge = g.addCard('Scrooge McDuck - Ebenezer Scrooge', 0, Place.play);
      g.state.player(1).lore = 1;
      g.apply(QuestMove(0, scrooge));
      expect(g.state.player(1).lore, 0);
      expect(g.state.player(0).hand, hasLength(1));
      g.apply(QuestMove(0, g.addCard('Scrooge McDuck - Ebenezer Scrooge', 0, Place.play)));
      expect(g.state.player(0).hand, hasLength(1), reason: 'no lore lost, no card');
      final lore = g.state.player(0).lore;
      g.apply(const EndTurnMove(0));
      settle(g);
      expect(g.state.player(0).lore, lore + 2, reason: 'two Foreclosures: an opponent has 0 lore');
    });

    test('Prince John - Greediest of All draws a card for each card discarded', () {
      final g = emptyGame();
      g.addInk(0, 4);
      g.addCard('Prince John - Greediest of All', 0, Place.play);
      for (var i = 0; i < 3; i++) {
        g.addCard(vanilla, 1, Place.hand);
      }
      g.apply(PlayMove(0, g.addCard('Sudden Chill', 0, Place.hand)));
      settle(g);
      expect(g.state.player(1).hand, hasLength(2));
      expect(g.state.player(0).hand, hasLength(1));
    });
  });

  group('For the length of a challenge (CR 4.6)', () {
    test('Mushu: Resist +2 during that challenge only', () {
      final g = emptyGame();
      g.addCard('Mushu - Majestic Dragon', 0, Place.play);
      final a = g.addCard(vanilla, 0, Place.play); // 3/2
      final d = g.addCard(vanilla2, 1, Place.play, exerted: true); // 2/3
      g.apply(ChallengeMove(0, a, d));
      expect(g.state.obj(a).damage, 0, reason: '2 damage, Resist +2');
      expect(g.chars(a).has(Kw.resist), isFalse, reason: 'over after the challenge');
    });

    test("Peter Pan - Pirate's Bane takes no damage challenging a Pirate; Raya against a damaged character", () {
      final g = emptyGame();
      final pan = g.addCard("Peter Pan - Pirate's Bane", 0, Place.play);
      final pirate = g.addCard('Mr. Smee - Bumbling Mate', 1, Place.play, exerted: true);
      g.apply(ChallengeMove(0, pan, pirate));
      expect(g.state.obj(pan).damage, 0);
      final g2 = emptyGame();
      final raya = g2.addCard('Raya - Leader of Heart', 0, Place.play);
      final hurt = g2.addCard('Mufasa - Ruler of Pride Rock', 1, Place.play, exerted: true, damage: 1);
      g2.apply(ChallengeMove(0, raya, hurt));
      expect(g2.state.obj(raya).zone, Place.play);
      expect(g2.state.obj(raya).damage, 0);
    });

    test('Prince Phillip - Swordsman of the Realm readies after challenging a damaged character', () {
      final g = emptyGame();
      final ph = g.addCard('Prince Phillip - Swordsman of the Realm', 0, Place.play);
      final hurt = g.addCard(vanilla2, 1, Place.play, exerted: true, damage: 1);
      g.apply(ChallengeMove(0, ph, hurt));
      expect(g.state.obj(ph).exerted, isFalse);
    });

    test('Prince Phillip - Dragonslayer: challenges and is banished, may banish the challenged character', () {
      final g = emptyGame();
      final ph = g.addCard('Prince Phillip - Dragonslayer', 0, Place.play); // 3/3
      final big = g.addCard('Mufasa - Ruler of Pride Rock', 1, Place.play, exerted: true, damage: 6); // 4/9
      g.apply(ChallengeMove(0, ph, big));
      settle(g);
      expect(g.state.obj(ph).zone, Place.discard);
      expect(g.state.obj(big).zone, Place.discard);
      // Banished while being challenged: no trigger.
      final g2 = emptyGame(active: 1);
      final ph2 = g2.addCard('Prince Phillip - Dragonslayer', 0, Place.play, exerted: true);
      final big2 = g2.addCard('Mufasa - Ruler of Pride Rock', 1, Place.play);
      g2.apply(ChallengeMove(1, big2, ph2));
      settle(g2);
      expect(g2.state.obj(big2).zone, Place.play);
    });

    test('Mulan - Elite Archer deals the same damage to up to 2 other chosen characters', () {
      final g = emptyGame();
      final mulan = g.addCard('Mulan - Elite Archer', 0, Place.play); // 2/6
      final d = g.addCard('Mufasa - Ruler of Pride Rock', 1, Place.play, exerted: true);
      final x = g.addCard('Mufasa - Ruler of Pride Rock', 1, Place.play);
      final y = g.addCard('Mufasa - Ruler of Pride Rock', 1, Place.play);
      g.apply(ChallengeMove(0, mulan, d));
      expect(g.pending?.decision.options, isNot(contains(d)));
      expect(g.pending?.decision.options, isNot(contains(mulan)));
      answer(g, [x, y]);
      expect(g.state.obj(x).damage, 2);
      expect(g.state.obj(y).damage, 2);
    });

    test('Olympus Would Be That Way: +3 {s} while challenging a location', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final a = g.addCard(vanilla2, 0, Place.play); // 2 strength
      final loc = g.addCard('Pride Lands - Jungle Oasis', 1, Place.play); // 8 willpower
      final ch = g.addCard(vanilla2, 1, Place.play, exerted: true);
      g.apply(PlayMove(0, g.addCard('Olympus Would Be That Way', 0, Place.hand)));
      expect(g.chars(a).strength, 2);
      g.apply(ChallengeMove(0, a, loc));
      expect(g.state.obj(loc).damage, 5);
      final b = g.addCard(vanilla2, 0, Place.play);
      g.apply(ChallengeMove(0, b, ch));
      expect(g.state.obj(ch).damage, 2, reason: 'a character, not a location');
    });

    test('Noi takes no damage from challenges this turn after you play an action', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final noi = g.addCard('Noi - Acrobatic Baby', 0, Place.play);
      final d = g.addCard(vanilla, 1, Place.play, exerted: true);
      g.apply(PlayMove(0, g.addCard('Olympus Would Be That Way', 0, Place.hand)));
      g.apply(ChallengeMove(0, noi, d));
      expect(g.state.obj(noi).damage, 0);
    });

    test('Mulan - Standing Her Ground: no challenge damage after a card was put under one of yours', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final mulan = g.addCard('Mulan - Standing Her Ground', 0, Place.play); // 4/2
      final booster = g.addCard('Pete - Ghost of Christmas Future', 0, Place.play);
      final d = g.addCard(vanilla, 1, Place.play, exerted: true);
      g.apply(ActivateMove(0, booster, g.parsed(booster).abilities.indexWhere((a) => a is KeywordAbility && a.keyword.kw == Kw.boost)));
      g.apply(ChallengeMove(0, mulan, d));
      expect(g.state.obj(mulan).zone, Place.play);
      expect(g.state.obj(mulan).damage, 0);
    });
  });

  group('Waiting for a later event', () {
    test("Mother Gothel - Knows What's Best: banished in a challenge this turn, it returns to hand", () {
      final g = emptyGame();
      g.addInk(0, 2);
      final ally = g.addCard('Mufasa - Ruler of Pride Rock', 0, Place.play, damage: 6); // 4/9
      g.apply(PlayMove(0, g.addCard("Mother Gothel - Knows What's Best", 0, Place.hand)));
      settle(g);
      expect(g.state.obj(ally).damage, 8);
      expect(g.chars(ally).n(Kw.challenger), 1);
      final d = g.addCard(vanilla, 1, Place.play, exerted: true);
      g.apply(ChallengeMove(0, ally, d));
      settle(g);
      expect(g.state.obj(ally).zone, Place.hand);
    });

    test('Next Stop, Olympus: 2 cheaper with a 5 {s} character; the next challenge gains 1 lore', () {
      final g = emptyGame();
      final mor = g.addCard("Mor'du - Savage Cursed Prince", 0, Place.play, exerted: true); // 8 strength
      final card = g.addCard('Next Stop, Olympus', 0, Place.hand);
      expect(g.playCost(0, card), 0);
      g.apply(PlayMove(0, card));
      expect(g.state.obj(mor).exerted, isFalse);
      expect(g.whyNot(QuestMove(0, mor)), isNotNull);
      g.apply(ChallengeMove(0, mor, g.addCard(vanilla, 1, Place.play, exerted: true)));
      expect(g.state.player(0).lore, 1);
    });

    test('Rapunzel - Ready for Adventure: the character chosen for Support takes no damage the next time', () {
      final g = emptyGame();
      final rap = g.addCard('Rapunzel - Ready for Adventure', 0, Place.play);
      final friend = g.addCard(vanilla2, 0, Place.play);
      g.apply(QuestMove(0, rap));
      settle(g, pick: (d) => d.kind == DecisionKind.cards ? [friend] : g.defaultAnswer(d));
      g.apply(const EndTurnMove(0));
      g.state.obj(friend).exerted = true;
      g.apply(ChallengeMove(1, g.addCard(vanilla, 1, Place.play), friend));
      expect(g.state.obj(friend).damage, 0, reason: 'the first damage is prevented');
      g.apply(ChallengeMove(1, g.addCard(vanilla, 1, Place.play), friend));
      expect(g.state.obj(friend).zone, Place.discard, reason: 'only the next time');
    });

    test('Powhatan\'s Staff: the next character enters exerted with Bodyguard until your next turn', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final staff = g.addCard("Powhatan's Staff", 0, Place.play);
      g.apply(ActivateMove(0, staff, act(g, staff)));
      final c = g.addCard(vanilla, 0, Place.hand);
      g.apply(PlayMove(0, c));
      expect(g.state.obj(c).exerted, isTrue);
      expect(g.chars(c).has(Kw.bodyguard), isTrue);
      final c2 = g.addCard(vanilla2, 0, Place.hand);
      g.addInk(0, 2);
      g.apply(PlayMove(0, c2));
      expect(g.state.obj(c2).exerted, isFalse, reason: 'only the next one');
    });

    test('Pepa Madrigal: the exerted character can\'t ready unless at a location', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final d = g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Pepa Madrigal - Weather Maker', 0, Place.hand)));
      settle(g, pick: (x) => x.kind == DecisionKind.cards ? [d] : g.defaultAnswer(x));
      expect(g.state.obj(d).exerted, isTrue);
      g.apply(const EndTurnMove(0));
      expect(g.state.obj(d).exerted, isTrue);
      final g2 = emptyGame();
      g2.addInk(0, 5);
      final d2 = g2.addCard(vanilla, 1, Place.play);
      final loc = g2.addCard('Pizza Planet - Spaceport', 1, Place.play);
      g2.apply(PlayMove(0, g2.addCard('Pepa Madrigal - Weather Maker', 0, Place.hand)));
      settle(g2, pick: (x) => x.kind == DecisionKind.cards ? [d2] : g2.defaultAnswer(x));
      g2.state.obj(d2).at = loc;
      g2.apply(const EndTurnMove(0));
      expect(g2.state.obj(d2).exerted, isFalse);
    });
  });

  group('Playing, singing, questing, challenging and moving (CR 4.3–4.7)', () {
    test('Piercing Attack: Resist doesn\'t reduce it (CR 8.8); then Nathaniel Flint can be played', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final nat = g.addCard('Nathaniel Flint - Notorious Pirate', 0, Place.hand);
      expect(g.whyNot(PlayMove(0, nat)), isNotNull, reason: 'no opposing character was damaged this turn');
      final tough = g.addCard('Omnidroid - Ultimate Iteration', 1, Place.play); // Resist +2
      g.apply(PlayMove(0, g.addCard('Piercing Attack', 0, Place.hand)));
      expect(g.state.obj(tough).damage, 2);
      expect(g.whyNot(PlayMove(0, nat)), isNull);
    });

    test('Pete - Games Referee: opponents can\'t play actions until the start of your next turn', () {
      final g = emptyGame();
      g.addInk(0, 3);
      g.addInk(1, 3);
      g.apply(PlayMove(0, g.addCard('Pete - Games Referee', 0, Place.hand)));
      g.apply(const EndTurnMove(0));
      expect(g.whyNot(PlayMove(1, g.addCard('Scout Ahead', 1, Place.hand))), isNotNull);
      g.apply(const EndTurnMove(1));
      g.apply(const EndTurnMove(0));
      expect(g.whyNot(PlayMove(1, g.addCard('Scout Ahead', 1, Place.hand))), isNull);
    });

    test("Naveen's Ukulele: +3 cost to sing; Record Player: Stitch +1 (CR 5.4.4)", () {
      final g = emptyGame();
      g.addInk(0, 1);
      final uke = g.addCard("Naveen's Ukulele", 0, Place.play);
      final singer = g.addCard(vanilla2, 0, Place.play); // cost 2
      final song = db.cards.firstWhere((c) => c.isSong && c.cost == 5 && LorcanaParser.parse(c).supported).fullName;
      final s = g.addCard(song, 0, Place.hand);
      expect(g.whyNot(PlayMove(0, s, mode: PlayMode.sing, singers: [singer])), isNotNull);
      g.apply(ActivateMove(0, uke, act(g, uke)));
      expect(g.whyNot(PlayMove(0, s, mode: PlayMode.sing, singers: [singer])), isNull);
      final g2 = emptyGame();
      g2.addCard('Record Player', 0, Place.play);
      final stitch = db.cards.firstWhere((c) => c.name == 'Stitch' && c.type == CardType.character && c.cost == 4 && LorcanaParser.parse(c).supported).fullName;
      final st = g2.addCard(stitch, 0, Place.play);
      final song5 = g2.addCard(song, 0, Place.hand);
      expect(g2.whyNot(PlayMove(0, song5, mode: PlayMode.sing, singers: [st])), isNull);
    });

    test('Mrs. Incredible: 1 less for the next character you shift, not one you play', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final mrs = g.addCard('Mrs. Incredible - Created by the Vine', 0, Place.play);
      g.apply(QuestMove(0, mrs));
      final c = g.addCard(vanilla, 0, Place.hand);
      expect(g.playCost(0, c), 3);
      final under = g.addCard('Moana - Curious Explorer', 0, Place.play);
      final top = g.addCard('Moana - Born Leader', 0, Place.hand); // Shift 3
      g.apply(PlayMove(0, top, mode: PlayMode.shift, onto: under));
      expect(g.inkReady(0), 5 - 2);
    });

    test('RC - Remote-Controlled Car pays 1 ink to quest or challenge', () {
      final g = emptyGame();
      final rc = g.addCard('RC - Remote-Controlled Car', 0, Place.play);
      expect(g.whyNot(QuestMove(0, rc)), isNotNull);
      g.addInk(0, 1);
      g.apply(QuestMove(0, rc));
      expect(g.inkReady(0), 0);
      expect(g.state.player(0).lore, 2);
    });

    test('Prince Charming: each turn only one character can challenge', () {
      final g = emptyGame();
      g.addCard('Prince Charming - Protector of the Realm', 1, Place.play);
      final a = g.addCard(vanilla, 0, Place.play);
      final b = g.addCard(vanilla, 0, Place.play);
      final x = g.addCard(vanilla2, 1, Place.play, exerted: true);
      final y = g.addCard(vanilla2, 1, Place.play, exerted: true);
      g.apply(ChallengeMove(0, a, x));
      expect(g.whyNot(ChallengeMove(0, b, y)), isNotNull);
    });

    test('Monterey Jack can\'t quest unless you have a character with 4 {w} or more', () {
      final g = emptyGame();
      final mj = g.addCard('Monterey Jack - Hypnotized by Cheese', 0, Place.play);
      expect(g.whyNot(QuestMove(0, mj)), isNotNull);
      g.addCard('Mufasa - Ruler of Pride Rock', 0, Place.play);
      expect(g.whyNot(QuestMove(0, mj)), isNull);
    });

    test('Move costs: Pizza Planet free for Toys, Ring of Stones free when exerted, RLS Legacy 2 less, Raksha 1 less once', () {
      final g = emptyGame();
      final pizza = g.addCard('Pizza Planet - Spaceport', 0, Place.play);
      final toy = g.addCard('RC - Remote-Controlled Car', 0, Place.play);
      expect(g.whyNot(MoveMove(0, toy, pizza)), isNull);
      final ring = g.addCard('Ring of Stones - Place of Legends', 0, Place.play);
      final tired = g.addCard(vanilla, 0, Place.play, exerted: true);
      expect(g.whyNot(MoveMove(0, tired, ring)), isNull);
      expect(g.whyNot(MoveMove(0, g.addCard(vanilla, 0, Place.play), ring)), isNotNull);
      final rls = g.addCard('RLS Legacy - Solar Galleon', 0, Place.play); // move 3
      g.addInk(0, 1);
      final a = g.addCard(vanilla, 0, Place.play);
      expect(g.whyNot(MoveMove(0, a, rls)), isNotNull);
      g.state.obj(g.addCard(vanilla2, 0, Place.play)).at = rls;
      g.apply(MoveMove(0, a, rls));
      expect(g.inkReady(0), 0);
      final raksha = g.addCard('Raksha - Fearless Mother', 0, Place.play);
      g.addInk(0, 1);
      g.apply(MoveMove(0, raksha, pizza)); // 2 less 1
      expect(g.inkReady(0), 0);
      g.addInk(0, 2);
      g.apply(MoveMove(0, raksha, g.addCard('Remote Inklands - Desert Ruins', 0, Place.play)));
      expect(g.inkReady(0), 0, reason: 'once a turn');
    });

    test('Owl Island: the first action each turn costs 1 less for each character here', () {
      final g = emptyGame();
      final owl = g.addCard('Owl Island - Secluded Entrance', 0, Place.play);
      for (var i = 0; i < 2; i++) {
        g.state.obj(g.addCard(vanilla2, 0, Place.play)).at = owl;
      }
      g.addInk(0, 3);
      final a = g.addCard('Royal Tantrum', 0, Place.hand); // 4
      expect(g.playCost(0, a), 2);
      g.apply(PlayMove(0, g.addCard('Scout Ahead', 0, Place.hand)));
      expect(g.playCost(0, a), 4);
    });

    test('Namaari - Resolute Daughter and Robin Hood - Timely Contestant cost less', () {
      final g = emptyGame();
      final n = g.addCard('Namaari - Resolute Daughter', 0, Place.hand);
      final r = g.addCard('Robin Hood - Timely Contestant', 0, Place.hand);
      g.addCard(vanilla2, 1, Place.play, damage: 2);
      expect(g.playCost(0, r), 7);
      final a = g.addCard('Mufasa - Ruler of Pride Rock', 0, Place.play);
      g.apply(ChallengeMove(0, a, g.addCard(vanilla2, 1, Place.play, exerted: true)));
      expect(g.playCost(0, n), 7);
    });

    test('Pongo - Determined Father: once a turn, pay 2 to reveal the top card (like Boost, CR 8.4.1)', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final pongo = g.addCard('Pongo - Determined Father', 0, Place.play);
      g.apply(ActivateMove(0, pongo, act(g, pongo)));
      expect(g.state.player(0).hand, hasLength(1));
      expect(g.whyNot(ActivateMove(0, pongo, act(g, pongo))), isNotNull);
    });

    test('Rapunzel - Escaping the Tower: discard to get +1 {l} and Evasive', () {
      final g = emptyGame();
      final r = g.addCard('Rapunzel - Escaping the Tower', 0, Place.play);
      g.addCard(vanilla, 0, Place.hand);
      g.apply(ActivateMove(0, r, act(g, r)));
      expect(g.chars(r).lore, 2);
      expect(g.chars(r).has(Kw.evasive), isTrue);
      g.addCard(vanilla, 0, Place.hand);
      expect(g.whyNot(ActivateMove(0, r, act(g, r))), isNotNull);
    });

    test('Morph - Space Goo: any character with Shift can go on top (CR 8.10.1)', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final morph = g.addCard('Morph - Space Goo', 0, Place.play);
      final moana = g.addCard('Moana - Born Leader', 0, Place.hand);
      expect(g.shiftTargets(0, moana), contains(morph));
    });

    test('Roo puts herself under a character with Boost (CR 8.4.3)', () {
      final g = emptyGame();
      final roo = g.addCard('Roo - Little Helper', 0, Place.play);
      final pete = g.addCard('Pete - Ghost of Christmas Future', 0, Place.play);
      g.apply(ActivateMove(0, roo, act(g, roo)));
      expect(g.state.obj(pete).under, [roo]);
      expect(g.state.player(0).play, [pete]);
      expect(g.state.player(0).discardedThisTurn, 0);
    });
  });

  group('Groups and choices', () {
    test("Mor'du exerts your others and they can't ready", () {
      final g = emptyGame();
      g.addInk(0, 5);
      final a = g.addCard(vanilla, 0, Place.play);
      final m = g.addCard("Mor'du - Savage Cursed Prince", 0, Place.hand);
      g.apply(PlayMove(0, m));
      expect(g.state.obj(a).exerted, isTrue);
      expect(g.state.obj(m).exerted, isFalse);
      g.apply(const EndTurnMove(0));
      g.apply(const EndTurnMove(1));
      expect(g.state.obj(a).exerted, isTrue);
    });

    test('Morgana Macawber moves 1 damage from each other character to the chosen one', () {
      final g = emptyGame();
      g.addInk(0, 6);
      final mine = g.addCard(vanilla2, 0, Place.play, damage: 2);
      final theirs = g.addCard('Mufasa - Ruler of Pride Rock', 1, Place.play, damage: 1);
      final target = g.addCard('Mufasa - Ruler of Pride Rock', 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Morgana Macawber - Reformed Spellcaster', 0, Place.hand)));
      settle(g, pick: (d) => d.kind == DecisionKind.cards ? [target] : g.defaultAnswer(d));
      expect(g.state.obj(mine).damage, 1);
      expect(g.state.obj(theirs).damage, 0);
      expect(g.state.obj(target).damage, 2);
    });

    test('One and Only banishes the others with the same name', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final a = g.addCard(vanilla, 0, Place.play);
      final b = g.addCard(vanilla, 1, Place.play);
      final c = g.addCard(vanilla2, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('One and Only', 0, Place.hand)));
      answer(g, [a]);
      expect(g.state.obj(a).zone, Place.play);
      expect(g.state.obj(b).zone, Place.discard);
      expect(g.state.obj(c).zone, Place.play);
    });

    test('Mowgli: the opponent picks the non-character card they discard', () {
      final g = emptyGame();
      g.addInk(0, 2);
      g.addCard(vanilla, 1, Place.hand);
      final item = g.addCard('Pixie Dust', 1, Place.hand);
      g.apply(PlayMove(0, g.addCard('Mowgli - Man Cub', 0, Place.hand)));
      expect(g.pending, isNull, reason: 'one non-character card');
      expect(g.state.obj(item).zone, Place.discard);
    });

    test('Mother Gothel - Unwavering Schemer: each opponent returns a character of their choice', () {
      final g = emptyGame();
      g.addInk(0, 6);
      final a = g.addCard(vanilla, 1, Place.play);
      final b = g.addCard(vanilla2, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Mother Gothel - Unwavering Schemer', 0, Place.hand)));
      expect(g.pending?.decision.player, 1);
      answer(g, [b], player: 1);
      expect(g.state.obj(b).zone, Place.hand);
      expect(g.state.obj(a).zone, Place.play);
    });

    test('On Your Feet! Now! readies, deals 1 to each and stops them questing', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final a = g.addCard(vanilla, 0, Place.play, exerted: true);
      g.apply(PlayMove(0, g.addCard('On Your Feet! Now!', 0, Place.hand)));
      expect(g.state.obj(a).exerted, isFalse);
      expect(g.state.obj(a).damage, 1);
      expect(g.whyNot(QuestMove(0, a)), isNotNull);
    });

    test("Nothing We Won't Do: ready, no challenge damage, no questing", () {
      final g = emptyGame();
      g.addInk(0, 8);
      final a = g.addCard(vanilla, 0, Place.play, exerted: true);
      g.apply(PlayMove(0, g.addCard("Nothing We Won't Do", 0, Place.hand)));
      expect(g.state.obj(a).exerted, isFalse);
      expect(g.whyNot(QuestMove(0, a)), isNotNull);
      g.apply(ChallengeMove(0, a, g.addCard(vanilla, 1, Place.play, exerted: true)));
      expect(g.state.obj(a).damage, 0);
    });

    test('Moana - Born Leader readies the others at her location; they can\'t quest', () {
      final g = emptyGame();
      final loc = g.addCard('Pizza Planet - Spaceport', 0, Place.play);
      final moana = g.addCard('Moana - Born Leader', 0, Place.play);
      final other = g.addCard(vanilla, 0, Place.play, exerted: true);
      final away = g.addCard(vanilla, 0, Place.play, exerted: true);
      g.state.obj(moana).at = loc;
      g.state.obj(other).at = loc;
      g.apply(QuestMove(0, moana));
      expect(g.state.obj(other).exerted, isFalse);
      expect(g.state.obj(away).exerted, isTrue);
      expect(g.whyNot(QuestMove(0, other)), isNotNull);
    });

    test('Olaf gives your others +{s} equal to his; Ranger Team-Up +{s} equal to their {w}', () {
      final g = emptyGame();
      final olaf = g.addCard('Olaf - Carrot Enthusiast', 0, Place.play); // 1 strength
      final a = g.addCard(vanilla, 0, Place.play);
      g.apply(QuestMove(0, olaf));
      expect(g.chars(a).strength, 4);
      final g2 = emptyGame();
      g2.addInk(0, 2);
      final m = g2.addCard('Mufasa - Ruler of Pride Rock', 0, Place.play); // 4/9
      g2.apply(PlayMove(0, g2.addCard('Ranger Team-Up', 0, Place.hand)));
      expect(g2.chars(m).strength, 13);
    });

    test('Rescue Rangers Away! takes {s} equal to your characters', () {
      final g = emptyGame();
      g.addInk(0, 2);
      g.addCard(vanilla2, 0, Place.play);
      g.addCard(vanilla2, 0, Place.play);
      final t = g.addCard('Mufasa - Ruler of Pride Rock', 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Rescue Rangers Away!', 0, Place.hand)));
      answer(g, [t]);
      expect(g.chars(t).strength, 2);
    });

    test('Performance Review: exert to draw cards equal to its {l} (CR 6.1.5.1)', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final m = g.addCard('Mufasa - Ruler of Pride Rock', 0, Place.play); // 4 lore
      g.apply(PlayMove(0, g.addCard('Performance Review', 0, Place.hand)));
      expect(g.state.obj(m).exerted, isTrue);
      expect(g.state.player(0).hand, hasLength(4));
    });

    test("Nani's Payback: lore lost equal to the damage, at most 4", () {
      final g = emptyGame();
      g.addInk(0, 4);
      g.state.player(1).lore = 10;
      g.addCard('Mufasa - Ruler of Pride Rock', 0, Place.play, damage: 6);
      g.apply(PlayMove(0, g.addCard("Nani's Payback", 0, Place.hand)));
      expect(g.state.player(1).lore, 6);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Mulan - Resourceful Recruit gains lore equal to her {s}, at most 6', () {
      final g = emptyGame();
      final mulan = g.addCard('Mulan - Resourceful Recruit', 0, Place.play);
      g.state.timed.add(Timed(ts: 999, controller: 0, source: mulan, lasting: Lasting.thisTurn, turn: g.state.turn, cards: [mulan], stat: Stat.strength, amount: 9));
      g.apply(QuestMove(0, mulan));
      expect(g.state.player(0).lore, 6);
    });

    test('Pocahontas - Peacekeeper: shifted with no challenge this turn, nobody can challenge', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final under = g.addCard('Pocahontas - Guiding the Tribe', 0, Place.play);
      g.apply(PlayMove(0, g.addCard('Pocahontas - Peacekeeper', 0, Place.hand), mode: PlayMode.shift, onto: under));
      settle(g);
      g.apply(const EndTurnMove(0));
      final a = g.addCard(vanilla, 1, Place.play);
      expect(g.whyNot(ChallengeMove(1, a, g.addCard(vanilla2, 0, Place.play, exerted: true))), isNotNull);
    });

    test('Panic: your Villains can\'t be challenged while he is exerted and Pain is in play', () {
      final g = emptyGame(active: 1);
      final panic = g.addCard('Panic - Immortal Sidekick', 0, Place.play, exerted: true);
      final pain = db.cards.firstWhere((c) => c.name == 'Pain' && LorcanaParser.parse(c).supported).fullName;
      g.addCard(pain, 0, Place.play);
      final villain = g.addCard('Mother Gothel - Evil as Ever', 0, Place.play, exerted: true);
      final a = g.addCard(vanilla, 1, Place.play);
      expect(g.whyNot(ChallengeMove(1, a, villain)), isNotNull);
      g.state.obj(panic).exerted = false;
      expect(g.whyNot(ChallengeMove(1, a, villain)), isNull);
    });

    test('Pete - Space Pirate: while exerted, opponents can\'t sing and your Pirates gain Resist +1', () {
      final g = emptyGame();
      final pete = g.addCard('Pete - Space Pirate', 0, Place.play, exerted: true);
      final smee = g.addCard('Mr. Smee - Bumbling Mate', 0, Place.play);
      expect(g.chars(smee).n(Kw.resist), 1);
      expect(g.chars(pete).n(Kw.resist), 1);
      final singer = g.addCard('Mufasa - Ruler of Pride Rock', 1, Place.play);
      expect(g.chars(singer).rules, contains(Rule.cantSing));
    });

    test('Mr. Smee takes 1 damage at the end of your turn while exerted without a Captain', () {
      final g = emptyGame();
      final smee = g.addCard('Mr. Smee - Bumbling Mate', 0, Place.play, exerted: true);
      g.apply(const EndTurnMove(0));
      expect(g.state.obj(smee).damage, 1);
      final g2 = emptyGame();
      final smee2 = g2.addCard('Mr. Smee - Bumbling Mate', 0, Place.play, exerted: true);
      g2.addCard('Nathaniel Flint - Notorious Pirate', 0, Place.play); // a Captain
      g2.apply(const EndTurnMove(0));
      expect(g2.state.obj(smee2).damage, 0);
    });

    test('Pluto - Steel Champion: another Steel character played lets you banish an item', () {
      final g = emptyGame();
      g.addInk(0, 7);
      final pluto = g.addCard('Pluto - Steel Champion', 0, Place.hand);
      final item = g.addCard('Pixie Dust', 1, Place.play);
      g.apply(PlayMove(0, pluto));
      expect(g.pending, isNull, reason: 'not on Pluto himself (CR 6.1.6)');
      g.apply(PlayMove(0, g.addCard('Mr. Smee - Bumbling Mate', 0, Place.hand))); // Steel
      settle(g);
      expect(g.state.obj(item).zone, Place.discard);
    });

    test('Pluto - Clever Cluefinder: without a Detective the item goes on top of the deck', () {
      final g = emptyGame();
      final pluto = g.addCard('Pluto - Clever Cluefinder', 0, Place.play);
      final item = g.addCard('Pixie Dust', 0, Place.discard);
      g.apply(ActivateMove(0, pluto, act(g, pluto)));
      expect(g.state.player(0).deck.first, item);
    });

    test('Pocahontas & Meeko: return a cost-1 character to play a cost-1 character free', () {
      final g = emptyGame();
      final pm = g.addCard('Pocahontas & Meeko - Adventurous Friends', 0, Place.play);
      final one = db.cards.firstWhere((c) => c.type == CardType.character && c.cost == 1 && c.text.isEmpty).fullName;
      final back = g.addCard(one, 0, Place.play);
      final zcc = g.state.obj(back).zcc;
      g.apply(QuestMove(0, pm));
      settle(g);
      expect(g.state.obj(back).zone, Place.play, reason: 'returned, then played again for free');
      expect(g.state.obj(back).zcc, zcc + 2);
    });

    test('Prince John\'s Mirror: an opponent with more than 3 cards discards down to 3', () {
      final g = emptyGame(active: 1);
      g.addCard("Prince John's Mirror", 0, Place.play);
      for (var i = 0; i < 5; i++) {
        g.addCard(vanilla, 1, Place.hand);
      }
      g.apply(const EndTurnMove(1));
      answer(g, g.pending!.decision.options.take(2).toList(), player: 1);
      expect(g.state.player(1).hand, hasLength(3));
    });

    test('Priya Mangal gains 1 lore with a song in your discard', () {
      final g = emptyGame();
      g.addInk(0, 2);
      g.addCard("Nothing We Won't Do", 0, Place.discard);
      g.apply(PlayMove(0, g.addCard('Priya Mangal - Serious Music Lover', 0, Place.hand)));
      expect(g.state.player(0).lore, 1);
    });

    test('Scout Ahead and Salvage Operation', () {
      final g = emptyGame();
      g.addInk(0, 3);
      g.state.player(1).lore = 2;
      g.apply(PlayMove(0, g.addCard('Scout Ahead', 0, Place.hand)));
      expect(g.state.player(0).lore, 2);
      g.addCard('Mufasa - Ruler of Pride Rock', 0, Place.play);
      final item = g.addCard('Pixie Dust', 0, Place.discard);
      g.apply(PlayMove(0, g.addCard('Salvage Operation', 0, Place.hand)));
      expect(g.state.obj(item).zone, Place.hand);
      expect(g.state.player(0).lore, 3);
    });

    test('Powerline gains Rush this turn if you played a song', () {
      final g = emptyGame();
      final p = g.addCard('Powerline - Musical Superstar', 0, Place.play, drying: true);
      expect(g.chars(p).has(Kw.rush), isFalse);
      g.addInk(0, 8);
      g.apply(PlayMove(0, g.addCard("Nothing We Won't Do", 0, Place.hand)));
      expect(g.chars(p).has(Kw.rush), isTrue);
    });

    test('Scar - Finally King: draw equal to the Ally\'s {s}, then discard 2 and banish it', () {
      final g = emptyGame();
      final scar = g.addCard('Scar - Finally King', 0, Place.play, exerted: true);
      final ally = g.addCard('Monterey Jack - Hypnotized by Cheese', 0, Place.play); // 0 strength +1 from Scar
      g.apply(const EndTurnMove(0));
      settle(g);
      expect(g.state.obj(ally).zone, Place.discard);
      expect(g.state.obj(scar).zone, Place.play);
    });

    test('Morty Fieldmouse: a card under one of your other characters puts one under him too', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final morty = g.addCard('Morty Fieldmouse - Tiny Tim', 0, Place.play);
      final pete = g.addCard('Pete - Ghost of Christmas Future', 0, Place.play);
      g.apply(ActivateMove(0, pete, g.parsed(pete).abilities.indexWhere((a) => a is KeywordAbility && a.keyword.kw == Kw.boost)));
      expect(g.state.obj(morty).under, hasLength(1));
      expect(g.chars(morty).lore, 2);
    });

    test('Pete - Ghost of Christmas Future looks at as many cards as there are under him', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final pete = g.addCard('Pete - Ghost of Christmas Future', 0, Place.play);
      g.apply(ActivateMove(0, pete, g.parsed(pete).abilities.indexWhere((a) => a is KeywordAbility && a.keyword.kw == Kw.boost)));
      g.apply(QuestMove(0, pete));
      settle(g);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Scrooge McDuck - Cavern Prospector puts a card under a character played with Boost', () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.addCard('Scrooge McDuck - Cavern Prospector', 0, Place.play);
      final pete = g.addCard('Pete - Ghost of Christmas Future', 0, Place.hand);
      g.apply(PlayMove(0, pete));
      settle(g);
      expect(g.state.obj(pete).under, hasLength(1));
    });

    test('Omnidroid: when shifted, the cards under it may go to your hand', () {
      final g = emptyGame();
      g.addInk(0, 6);
      final under = g.addCard('Morph - Space Goo', 0, Place.play);
      g.apply(PlayMove(0, g.addCard('Omnidroid - Ultimate Iteration', 0, Place.hand), mode: PlayMode.shift, onto: under));
      settle(g);
      expect(g.state.obj(under).zone, Place.hand);
    });

    test('Mystical Tree moves 1 damage from a character here; Mama Odie here gains 1 lore', () {
      final g = emptyGame(active: 1);
      final tree = g.addCard("Mystical Tree - Mama Odie's Home", 0, Place.play);
      final here = g.addCard(vanilla2, 0, Place.play, damage: 1);
      g.state.obj(here).at = tree;
      final foe = g.addCard(vanilla2, 1, Place.play);
      g.apply(const EndTurnMove(1));
      settle(g);
      expect(g.state.obj(here).damage, 0);
      expect(g.state.obj(foe).damage, 1);
    });

    test('Roller Bob gets Rush only by putting exactly 2 character cards from the discard', () {
      final g = emptyGame();
      g.addInk(0, 3);
      g.addCard(vanilla, 0, Place.discard);
      final bob = g.addCard("Roller Bob - Sid's Toy", 0, Place.hand);
      g.apply(PlayMove(0, bob));
      settle(g);
      expect(g.chars(bob).has(Kw.rush), isFalse);
      expect(g.state.player(0).discard, hasLength(1));
    });

    test('Pack Tactics: 1 lore per damaged opposing character', () {
      final g = emptyGame();
      g.addInk(0, 4);
      g.addCard(vanilla, 1, Place.play, damage: 1);
      g.addCard(vanilla2, 1, Place.play, damage: 1);
      g.addCard(vanilla2, 0, Place.play, damage: 1);
      g.apply(PlayMove(0, g.addCard('Pack Tactics', 0, Place.hand)));
      expect(g.state.player(0).lore, 2);
    });

    test('Narrow Escape returns up to 2 cards with cost 2 or less', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final a = g.addCard(vanilla2, 1, Place.play);
      final b = g.addCard('Pixie Dust', 1, Place.play); // cost 4
      g.apply(PlayMove(0, g.addCard('Narrow Escape', 0, Place.hand)));
      settle(g, pick: (d) => d.options);
      expect(g.state.obj(a).zone, Place.hand);
      expect(g.state.obj(b).zone, Place.play);
    });

    test('Ratigan - Very Large Mouse readies one of yours (the data says "read")', () {
      expect(db['Ratigan - Very Large Mouse']!.text, contains('ready them'));
      final g = emptyGame();
      g.addInk(0, 5);
      final mine = g.addCard(vanilla, 0, Place.play, exerted: true);
      g.apply(PlayMove(0, g.addCard('Ratigan - Very Large Mouse', 0, Place.hand)));
      settle(g, pick: (d) => d.kind == DecisionKind.cards ? [d.options.contains(mine) ? mine : d.options.first] : g.defaultAnswer(d));
      expect(g.state.obj(mine).exerted, isFalse);
      expect(g.whyNot(QuestMove(0, mine)), isNotNull);
    });

    test('Mulan - Imperial General lets your others challenge ready characters this turn', () {
      final g = emptyGame();
      final mulan = g.addCard('Mulan - Imperial General', 0, Place.play);
      final other = g.addCard(vanilla, 0, Place.play);
      final ready = g.addCard(vanilla2, 1, Place.play);
      g.apply(ChallengeMove(0, mulan, g.addCard(vanilla2, 1, Place.play, exerted: true)));
      expect(g.whyNot(ChallengeMove(0, other, ready)), isNull);
    });

    test('Goofy - Emerald Champion banishes the challenging character, not the banished one', () {
      final g = emptyGame(active: 1);
      g.addCard('Goofy - Emerald Champion', 0, Place.play);
      final emerald = db.cards.firstWhere((c) => c.type == CardType.character && c.inks.contains(Ink.emerald) && c.text.isEmpty && (c.willpower ?? 9) <= 2).fullName;
      final e = g.addCard(emerald, 0, Place.play, exerted: true);
      final a = g.addCard('Mufasa - Ruler of Pride Rock', 1, Place.play);
      g.apply(ChallengeMove(1, a, e));
      settle(g);
      expect(g.state.obj(e).zone, Place.discard);
      expect(g.state.obj(a).zone, Place.discard);
    });
  });
}
