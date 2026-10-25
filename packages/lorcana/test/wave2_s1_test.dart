import 'package:lorcana/lorcana.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Wave 2, slice 1 ("A Very Merry Unbirthday" to "Graveyard of Christmas Future"): granted
/// abilities, searching, other players' choices, and the cost and play rules these cards change.
void main() {
  /// The index of [id]'s ability whose text starts with [name] (granted ones included).
  int ability(Game g, CardId id, String name) {
    final abs = g.abilitiesOf(id);
    final i = abs.indexWhere((a) => a.text.toLowerCase().startsWith(name.toLowerCase()));
    if (i < 0) throw StateError('No ability $name on ${g.nameOf(id)}: ${abs.map((a) => a.text)}');
    return i;
  }

  /// Answers yes to every yes/no question and the only choice to every forced one.
  void yesToAll(Game g) {
    while (g.pending != null) {
      final d = g.pending!.decision;
      answer(g, switch (d.kind) {
        DecisionKind.yesNo => [1],
        DecisionKind.option => [0],
        DecisionKind.order => List.of(d.options),
        DecisionKind.cards => d.options.take(d.min == 0 ? 1 : d.min).toList(),
      });
    }
  }

  test('every card of the slice is fully supported', () {
    const names = [
      'A Very Merry Unbirthday', 'Aladdin & Genie - Mischievous Pals', 'Aladdin - Barreling Through', 'Alma Madrigal - Accepting Grandmother',
      'Alma Madrigal - Family Matriarch', "Andy's Room - Home Base", 'Angel - Experiment 624', 'Angela - Night Warrior', 'Anna - Heir to Arendelle',
      'Anna - Soothing Sister', 'Antonio Madrigal - Animal Doctor', 'Antonio Madrigal - Friend to All', 'Atlantica - Concert Hall', 'Aurora - Lore Guardian',
      'Bad-Anon - Villain Support Center', 'Baloo - Carefree Bear', 'Bambi - Ethereal Fawn', 'Basil - Disguised Detective', 'Basil - Great Mouse Detective',
      'Baymax - Armored Companion', "Baymax's Healthcare Chip", 'Beast - Frustrated Designer', 'Beast - Selfless Protector', 'Beast - Snowfield Troublemaker',
      'Beast - Tragic Hero', "Beast's Castle - Winter Gardens", 'Belle - Always Reading', 'Belle - Apprentice Inventor', 'Belle - Mechanic Extraordinaire',
      'Belle - Snowfield Strategist', 'Beyond the Horizon', 'Bibbidi Bobbidi Boo', 'Big Book of Hunny', 'Blessed Bagpipes', 'Bruno Madrigal - Out of the Shadows',
      'Bunch of Balloons', 'Buzz Lightyear - On the Way', 'Calhoun - Battle-Tested', "Can't Hold It Back Anymore", 'Carl Fredricksen - On the Move',
      "Carl's House - Flying High", 'Chernabog - Unnatural Force', 'Chief Bogo - Calling the Shots', 'Chip - Retrieval Expert', 'Chip - Team Player',
      'Christopher Robin - Hunny Sage', 'Cinderella - Dream Come True', 'Cleansing Rainwater', 'Cogsworth - Talking Clock', 'Colors of the Wind',
      'Containment Unit', 'Daisy Duck - Multitalented Pirate', 'Daisy Duck - Sapphire Champion', 'Dale - Mischievous Ranger',
      'Darkwing Duck - Cool Under Pressure', 'Darkwing Tower - Icy Headquarters', 'Dash Parr & Violet Parr - Super Siblings', 'Dash Parr - Super Fast',
      'Della Duck - Returning Mother', 'Desperate Plan', "Detective's Badge", 'Diablo - Devoted Herald', 'Discarded Armor', 'Divebomb',
      'Do You Want to Build A Snowman?', 'Doc - Taking Notes', "Don't Be Nervous", 'Donald Duck - Coin Collector', 'Donald Duck - Fred Honeywell',
      'Donald Duck - Ruby Champion', 'Dumbo - Ninth Wonder of the Universe', 'Eeyore - In the Way', 'Elisa Maza - Transformed Gargoyle', 'Elsa - Ice Maker',
      "Elsa's Ice Palace - Place of Solitude", 'Emerald Chromicon', 'Escape Plan', "Everybody's Got a Weakness", 'Fairy Godmother - Magical Benefactor',
      'Fairy Godmother - Mystic Armorer', 'Falling Down The Rabbit Hole', 'Fantastical and Magical', 'Fergus - Outpost Builder', 'Firefly Swarm',
      'Fishbone Quill', 'Flotilla - Coconut Armada', 'Flotsam - Ursula\'s "Baby"', 'Flynn Rider - Breaking and Entering', 'Flynn Rider - High-Climbing Rogue',
      'Food Fight!', 'Forest Duel', 'Fred - Giant-Sized', 'Friar Tuck - Priest of Nottingham', 'Game Preserve - Protected Land',
      'Gantu - Experienced Enforcer', 'Gaston - Arrogant Showoff', 'Genie - Wonderful Trickster', 'Geppetto - Skilled Craftsman',
      'Gizmoduck - Duckburg Defender', 'Gizmosuit', 'Goliath - Clan Leader', 'Goofy - Emerald Champion', 'Goofy - Ghost of Jacob Marley',
      'Goofy - Groundbreaking Chef', 'Grandmother Willow - Ancient Advisor', 'Graveyard of Christmas Future - Lonely Resting Place',
    ];
    expect(names, hasLength(106));
    for (final n in names) {
      expect(LorcanaParser.parse(db[n]!).unsupported, isEmpty, reason: n);
    }
  });

  group('data corrections', () {
    test('Falling Down The Rabbit Hole reads "exerted" (data/lorcana-overrides.json)', () {
      expect(db['Falling Down The Rabbit Hole']!.text, contains('facedown and exerted'));
    });

    test("Baymax's Healthcare Chip and Bibbidi Bobbidi Boo use Lorcast's wording (the bulk text lost the {e} and misprints 'yours')", () {
      expect(db["Baymax's Healthcare Chip"]!.text, contains('{E}'));
      expect(db['Bibbidi Bobbidi Boo']!.text, contains('of yours'));
    });
  });

  group('7 zones: decks, hands and discards', () {
    test('A Very Merry Unbirthday: each opponent puts the top 2 cards of their deck into their discard', () {
      final g = emptyGame();
      g.addInk(0, 1);
      g.apply(PlayMove(0, g.addCard('A Very Merry Unbirthday', 0, Place.hand)));
      expect(g.state.player(1).discard, hasLength(2));
      expect(g.state.player(1).deck, hasLength(8));
      expect(g.state.player(0).deck, hasLength(10));
    });

    test('Aladdin & Genie: cards from the hand to the bottom, then draw that many plus 1', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final a = g.addCard(vanilla, 0, Place.hand), b = g.addCard(vanilla, 0, Place.hand);
      g.addCard(vanilla, 0, Place.hand);
      g.apply(PlayMove(0, g.addCard('Aladdin & Genie - Mischievous Pals', 0, Place.hand)));
      answer(g, [a, b], player: 0);
      answer(g, [b, a], player: 0); // the order on the bottom
      expect(g.state.player(0).hand, hasLength(4), reason: '1 kept + 3 drawn');
      expect(g.state.player(0).deck.sublist(g.state.player(0).deck.length - 2), [b, a]);
    });

    test('Aladdin & Genie: putting no cards draws none ("if you do", CR 6.1.5.1)', () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.addCard(vanilla, 0, Place.hand);
      g.apply(PlayMove(0, g.addCard('Aladdin & Genie - Mischievous Pals', 0, Place.hand)));
      answer(g, [], player: 0);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Alma Madrigal - Family Matriarch: the Madrigal card found goes on top after the shuffle (CR 7.2)', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final antonio = g.addCard('Antonio Madrigal - Animal Doctor', 0, Place.deck);
      g.apply(PlayMove(0, g.addCard('Alma Madrigal - Family Matriarch', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.player(0).deck.first, antonio);
      expect(g.state.player(0).deck, hasLength(11));
    });

    test('Antonio Madrigal - Friend to All: singing finds a character with cost 3 or less, once a turn', () {
      final g = emptyGame();
      g.addCard('Antonio Madrigal - Friend to All', 0, Place.play);
      final singer = g.addCard(vanilla2, 0, Place.play);
      final cheap = g.addCard(vanilla, 0, Place.deck);
      g.addCard('Belle - Mechanic Extraordinaire', 0, Place.deck); // costs 9: not a choice
      g.apply(PlayMove(0, g.addCard('A Very Merry Unbirthday', 0, Place.hand), mode: PlayMode.sing, singers: [singer]));
      answer(g, [1], player: 0);
      answer(g, [cheap], player: 0);
      expect(g.state.obj(cheap).zone, Place.hand);
    });

    test("Don't Be Nervous: search for a Princess, shuffle, then 2 Seven Dwarfs draw 2 and gain 2", () {
      final g = emptyGame();
      g.addInk(0, 5);
      final belle = g.addCard('Belle - Always Reading', 0, Place.deck);
      g.addCard('Doc - Taking Notes', 0, Place.play);
      g.addCard('Doc - Taking Notes', 0, Place.play);
      g.apply(PlayMove(0, g.addCard("Don't Be Nervous", 0, Place.hand)));
      expect(g.state.obj(belle).zone, Place.hand);
      expect(g.state.player(0).hand, hasLength(3));
      expect(g.state.player(0).lore, 2);
    });

    test('Christopher Robin: a Hunny card from the deck, revealed, into the hand', () {
      final g = emptyGame();
      g.addInk(0, 6);
      final book = g.addCard('Big Book of Hunny', 0, Place.deck);
      g.apply(PlayMove(0, g.addCard('Christopher Robin - Hunny Sage', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.obj(book).zone, Place.hand);
    });

    test('Christopher Robin: other Hunny characters may be of any ink (CR 1.10.1.1)', () {
      final hunny = db.cards.firstWhere((c) => c.type == CardType.character && c.hasClass('Hunny') && c.inks.length == 1 && c.inks.first == Ink.amber);
      final base = [...deckOf('Christopher Robin - Hunny Sage', 4), ...deckOf(hunny.fullName, 4)];
      final filler = db.cards.where((c) => c.inks.length == 1 && c.inks.first == Ink.sapphire && c.type == CardType.character && LorcanaParser.parse(c).supported && !c.hasClass('Hunny')).take(13).toList();
      final deck = [...base, for (final c in filler) ...deckOf(c.fullName, 4)];
      expect(validateDeck(db, deck).where((p) => p.contains('ink')), isEmpty);
      final other = db.cards.firstWhere((c) => c.inks.length == 1 && c.inks.first == Ink.ruby && c.type == CardType.character && LorcanaParser.parse(c).supported && !c.hasClass('Hunny'));
      expect(validateDeck(db, [...deck.take(56), ...deckOf(other.fullName, 4)]).where((p) => p.contains('ink')), isNotEmpty);
    });

    test('Big Book of Hunny: a Hunny card on top goes to the hand, anything else to the bottom', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final book = g.addCard('Big Book of Hunny', 0, Place.play);
      final hunny = g.addCard('Christopher Robin - Hunny Sage', 0, Place.deck);
      g.state.player(0).deck
        ..remove(hunny)
        ..insert(0, hunny);
      g.apply(ActivateMove(0, book, ability(g, book, 'invoke hunny')));
      expect(g.state.obj(hunny).zone, Place.hand);
    });

    test('Anna - Soothing Sister: Shift 0 only after a card left a discard this turn', () {
      final g = emptyGame();
      final old = g.addCard('Anna - Heir to Arendelle', 0, Place.play);
      final anna = g.addCard('Anna - Soothing Sister', 0, Place.hand);
      expect(g.whyNot(PlayMove(0, anna, mode: PlayMode.shift, onto: old)), isNotNull);
      final gone = g.addCard(vanilla, 1, Place.discard);
      g.moveToForTest(gone, Place.hand);
      expect(g.whyNot(PlayMove(0, anna, mode: PlayMode.shift, onto: old)), isNull);
      g.apply(PlayMove(0, anna, mode: PlayMode.shift, onto: old));
      expect(g.state.obj(anna).under, [old]);
    });

    test('Anna - Soothing Sister: questing gains the {l} of a character card in the discard, which goes to the bottom', () {
      final g = emptyGame();
      final anna = g.addCard('Anna - Soothing Sister', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.discard); // 2 lore
      g.apply(QuestMove(0, anna));
      answer(g, [abu], player: 0);
      expect(g.state.player(0).lore, 1 + 2);
      expect(g.state.player(0).deck.last, abu);
    });

    test('Colors of the Wind: draw a card for each different ink among the revealed cards', () {
      final g = emptyGame();
      g.addInk(0, 4);
      g.addCard('Abu - Mischievous Monkey', 1, Place.deck); // ruby, on the bottom
      final top0 = g.addCard('Antonio Madrigal - Friend to All', 0, Place.deck); // amber and amethyst
      g.state.player(0).deck
        ..remove(top0)
        ..insert(0, top0);
      g.apply(PlayMove(0, g.addCard('Colors of the Wind', 0, Place.hand)));
      // Player 1's top card is Aladdin (ruby): amber, amethyst and ruby.
      expect(g.state.player(0).hand, hasLength(3));
    });

    test('Fred - Giant-Sized: reveal until a Floodborn character, take it, shuffle the rest', () {
      final g = emptyGame();
      final fred = g.addCard('Fred - Giant-Sized', 0, Place.play);
      final flood = g.addCard('Basil - Great Mouse Detective', 0, Place.deck);
      g.apply(QuestMove(0, fred));
      expect(g.state.obj(flood).zone, Place.hand);
      expect(g.state.player(0).deck, hasLength(10));
    });

    test('Genie - Wonderful Trickster: at the end of your turn the whole hand goes to the bottom', () {
      final g = emptyGame();
      g.addCard('Genie - Wonderful Trickster', 0, Place.play);
      final a = g.addCard(vanilla, 0, Place.hand), b = g.addCard(vanilla2, 0, Place.hand);
      g.apply(EndTurnMove(0));
      answer(g, [a, b], player: 0);
      expect(g.state.player(0).hand, isEmpty);
      expect(g.state.player(0).deck.sublist(10), [a, b]);
    });

    test('Goliath - Clan Leader: each player ends their turn with 2 cards', () {
      final g = emptyGame();
      g.addCard('Goliath - Clan Leader', 0, Place.play);
      for (var i = 0; i < 4; i++) {
        g.addCard(vanilla, 0, Place.hand);
      }
      g.apply(EndTurnMove(0));
      answer(g, g.state.player(0).hand.take(2).toList(), player: 0);
      expect(g.state.player(0).hand, hasLength(2));
      // Player 1 drew 1 at the start of their turn; they draw to 2 at its end.
      g.apply(EndTurnMove(1));
      expect(g.state.player(1).hand, hasLength(2));
    });

    test('Friar Tuck: the player with the most cards in hand discards one', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final theirs = [for (var i = 0; i < 3; i++) g.addCard(vanilla, 1, Place.hand)];
      g.addCard(vanilla, 0, Place.hand);
      g.apply(PlayMove(0, g.addCard('Friar Tuck - Priest of Nottingham', 0, Place.hand)));
      answer(g, [theirs.first], player: 1);
      expect(g.state.player(1).hand, hasLength(2));
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Desperate Plan: an empty hand draws to 3; otherwise discard any number and draw as many', () {
      final g = emptyGame();
      g.addInk(0, 6);
      g.apply(PlayMove(0, g.addCard('Desperate Plan', 0, Place.hand)));
      expect(g.state.player(0).hand, hasLength(3));
      final keep = g.state.player(0).hand.first;
      final toss = g.state.player(0).hand.sublist(1);
      g.apply(PlayMove(0, g.addCard('Desperate Plan', 0, Place.hand)));
      answer(g, toss, player: 0);
      expect(g.state.player(0).hand, hasLength(3));
      expect(g.state.player(0).hand, contains(keep));
    });

    test('Beyond the Horizon: the chosen players discard their hands and draw 3', () {
      final g = emptyGame();
      g.addInk(0, 7);
      g.addCard(vanilla, 0, Place.hand);
      g.addCard(vanilla, 1, Place.hand);
      g.apply(PlayMove(0, g.addCard('Beyond the Horizon', 0, Place.hand)));
      answer(g, [0], player: 0); // not me
      answer(g, [1], player: 0); // the opponent
      expect(g.state.player(0).hand, hasLength(1));
      expect(g.state.player(1).hand, hasLength(3));
      expect(g.state.player(1).discard, hasLength(1));
    });

    test('Geppetto: discard any number of items for 1 lore each', () {
      final g = emptyGame();
      final gep = g.addCard('Geppetto - Skilled Craftsman', 0, Place.play);
      final items = [g.addCard('Gizmosuit', 0, Place.hand), g.addCard('Fishbone Quill', 0, Place.hand)];
      g.addCard(vanilla, 0, Place.hand);
      g.apply(QuestMove(0, gep));
      answer(g, [1], player: 0);
      answer(g, items, player: 0);
      expect(g.state.player(0).lore, 2 + 2);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Belle - Mechanic Extraordinaire: up to 3 items from the discard to the bottom, 1 lore each', () {
      final g = emptyGame();
      final belle = g.addCard('Belle - Mechanic Extraordinaire', 0, Place.play);
      final a = g.addCard('Gizmosuit', 0, Place.discard), b = g.addCard('Fishbone Quill', 0, Place.discard);
      g.apply(QuestMove(0, belle));
      answer(g, [1], player: 0);
      answer(g, [a, b], player: 0);
      answer(g, [a, b], player: 0); // order on the bottom
      expect(g.state.player(0).lore, 3 + 2);
    });
  });

  group('6.4 abilities in quotes, granted to other cards', () {
    test('Cogsworth: characters with Reckless gain "{e} - Gain 1 lore"', () {
      final g = emptyGame();
      g.addCard('Cogsworth - Talking Clock', 0, Place.play);
      final aladdin = g.addCard('Aladdin - Barreling Through', 0, Place.play); // Reckless
      final other = g.addCard(vanilla, 0, Place.play);
      expect(g.abilitiesOf(other).whereType<Activated>(), isEmpty);
      final i = ability(g, aladdin, '{e} - gain 1 lore');
      expect(g.legalMoves(), contains(predicate<LMove>((m) => m is ActivateMove && m.card == aladdin && m.index == i)));
      g.apply(ActivateMove(0, aladdin, i));
      expect(g.state.player(0).lore, 1);
      expect(g.state.obj(aladdin).exerted, isTrue);
    });

    test('Aladdin - Barreling Through: only while there is a card under him (Boost, CR 8.4)', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final aladdin = g.addCard('Aladdin - Barreling Through', 0, Place.play);
      expect(g.abilitiesOf(aladdin).whereType<Activated>(), isEmpty);
      g.apply(ActivateMove(0, aladdin, g.abilitiesOf(aladdin).indexWhere((a) => a is KeywordAbility && a.keyword.kw == Kw.boost)));
      g.apply(ActivateMove(0, aladdin, ability(g, aladdin, '{e} - gain 1 lore')));
      expect(g.state.player(0).lore, 1);
    });

    test('Dumbo: other characters with Evasive gain "{e}, 1 {i} - Draw a card and gain 1 lore"', () {
      final g = emptyGame();
      g.addInk(0, 1);
      g.addCard('Dumbo - Ninth Wonder of the Universe', 0, Place.play);
      final dash = g.addCard('Dash Parr - Super Fast', 0, Place.play); // Evasive
      g.apply(ActivateMove(0, dash, ability(g, dash, '{e}, 1 {i}')));
      expect(g.state.player(0).lore, 1);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Bad-Anon: a Villain here plays a character with its name from the hand for free', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final loc = g.addCard('Bad-Anon - Villain Support Center', 0, Place.play);
      final gaston = g.addCard('Gaston - Arrogant Showoff', 0, Place.play);
      final other = g.addCard('Gaston - Arrogant Showoff', 0, Place.hand);
      expect(g.abilitiesOf(gaston).whereType<Activated>(), isEmpty, reason: 'not there yet');
      g.state.obj(gaston).at = loc;
      g.apply(ActivateMove(0, gaston, ability(g, gaston, '{e}, 3')));
      // Gaston's own "you may banish one of your items" has no item to banish.
      yesToAll(g);
      expect(g.state.obj(other).zone, Place.play);
      expect(g.state.player(0).inkwell.where((id) => !g.state.obj(id).exerted), isEmpty);
    });

    test('Donald Duck - Coin Collector: the others gain "{e} - Draw a card" this turn only', () {
      final g = emptyGame();
      g.addInk(0, 8);
      final abu = g.addCard(vanilla, 0, Place.play);
      final donald = g.addCard('Donald Duck - Coin Collector', 0, Place.hand);
      g.apply(PlayMove(0, donald));
      expect(g.abilitiesOf(donald).whereType<Activated>(), isEmpty, reason: '"other"');
      final i = ability(g, abu, '{e} - draw a card');
      g.apply(ActivateMove(0, abu, i));
      expect(g.state.player(0).hand, hasLength(1));
      g.apply(EndTurnMove(0));
      expect(g.abilitiesOf(abu).whereType<Activated>(), isEmpty, reason: 'CR 6.1.13.4');
    });

    test('Food Fight!: your characters gain "{e}, 1 {i} - Deal 1 damage to chosen character" this turn', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final abu = g.addCard(vanilla, 0, Place.play);
      final foe = g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Food Fight!', 0, Place.hand)));
      g.apply(ActivateMove(0, abu, ability(g, abu, '{e}, 1 ink')));
      answer(g, [foe], player: 0);
      expect(g.state.obj(foe).damage, 1);
    });

    test('Flotsam: Jetsam gains "When this character is banished in a challenge, return this card to your hand"', () {
      final g = emptyGame(active: 1);
      g.addCard('Flotsam - Ursula\'s "Baby"', 0, Place.play);
      final jetsam = g.addCard('Jetsam - Ursula\'s "Baby"', 0, Place.play, exerted: true); // 2/4
      final a = g.addCard('Goliath - Clan Leader', 1, Place.play); // 6/5
      g.apply(ChallengeMove(1, a, jetsam));
      expect(g.state.obj(jetsam).zone, Place.hand);
    });

    test('Bruno Madrigal: the chosen character may return to the hand if banished in a challenge this turn', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final abu = g.addCard(vanilla, 0, Place.play); // 3/2
      final foe = g.addCard('Goliath - Clan Leader', 1, Place.play, exerted: true);
      g.apply(PlayMove(0, g.addCard('Bruno Madrigal - Out of the Shadows', 0, Place.hand)));
      answer(g, [abu], player: 0);
      g.apply(ChallengeMove(0, abu, foe));
      answer(g, [1], player: 0);
      expect(g.state.obj(abu).zone, Place.hand);
    });

    test('Forest Duel: Challenger +2 and the return ability, this turn', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final abu = g.addCard(vanilla, 0, Place.play); // 3/2
      final foe = g.addCard('Goliath - Clan Leader', 1, Place.play, exerted: true); // 6/5
      g.apply(PlayMove(0, g.addCard('Forest Duel', 0, Place.hand)));
      g.apply(ChallengeMove(0, abu, foe));
      expect(g.state.obj(foe).zone, Place.discard, reason: '3 + Challenger 2 banishes it');
      expect(g.state.obj(abu).zone, Place.hand);
    });

    test('Fairy Godmother - Mystic Armorer: questing gives your characters Challenger +3 and the return ability', () {
      final g = emptyGame();
      final fg = g.addCard('Fairy Godmother - Mystic Armorer', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      g.apply(QuestMove(0, fg));
      expect(g.chars(abu).n(Kw.challenger), 3);
      expect(g.abilitiesOf(abu).whereType<Triggered>(), hasLength(1));
    });

    test('Chief Bogo: your other characters have the Detective classification', () {
      final g = emptyGame();
      final abu = g.addCard(vanilla, 0, Place.play);
      final foe = g.addCard(vanilla, 1, Place.play);
      const detective = Filter(classes: ['Detective']);
      expect(g.matches(detective, abu, controller: 0), isFalse);
      final bogo = g.addCard('Chief Bogo - Calling the Shots', 0, Place.play);
      expect(g.matches(detective, abu, controller: 0), isTrue);
      expect(g.matches(detective, bogo, controller: 0), isFalse);
      expect(g.matches(detective, foe, controller: 0), isFalse);
    });

    test("Detective's Badge: Resist +1 and the Detective classification until the start of your next turn", () {
      final g = emptyGame();
      g.addInk(0, 1);
      final badge = g.addCard("Detective's Badge", 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      g.apply(ActivateMove(0, badge, ability(g, badge, 'protect and serve'))); // Abu is the only choice
      expect(g.chars(abu).n(Kw.resist), 1);
      expect(g.matches(const Filter(classes: ['Detective']), abu, controller: 0), isTrue);
      g.apply(EndTurnMove(0));
      expect(g.matches(const Filter(classes: ['Detective']), abu, controller: 0), isTrue);
      g.apply(EndTurnMove(1));
      expect(g.matches(const Filter(classes: ['Detective']), abu, controller: 0), isFalse);
      expect(g.chars(abu).has(Kw.resist), isFalse);
    });

    test('Angela: Gargoyles lose Stone by Day (Elisa Maza readies with 3 cards in hand)', () {
      Game setup({required bool angela}) {
        final g = emptyGame(active: 1);
        if (angela) g.addCard('Angela - Night Warrior', 0, Place.play);
        g.addCard('Elisa Maza - Transformed Gargoyle', 0, Place.play, exerted: true);
        for (var i = 0; i < 3; i++) {
          g.addCard(vanilla, 0, Place.hand);
        }
        g.apply(EndTurnMove(1));
        return g;
      }

      final without = setup(angela: false);
      expect(without.state.obj(without.state.player(0).play.last).exerted, isTrue, reason: 'Stone by Day');
      final withAngela = setup(angela: true);
      expect(withAngela.state.obj(withAngela.state.player(0).play.last).exerted, isFalse);
    });
  });

  group('6.1 targets and choices', () {
    test("Aurora: opponents can't choose your items", () {
      final g = emptyGame(active: 1);
      g.addInk(1, 2);
      g.addCard('Aurora - Lore Guardian', 0, Place.play);
      final suit = g.addCard('Gizmosuit', 0, Place.play);
      final theirs = g.addCard('Fishbone Quill', 1, Place.play);
      g.apply(PlayMove(1, g.addCard('Break', 1, Place.hand)));
      expect(g.state.obj(suit).zone, Place.play);
      expect(g.state.obj(theirs).zone, Place.discard, reason: 'the only item they could choose');
    });

    test('Aurora: {e} one of your items - look at the top card, top or bottom', () {
      final g = emptyGame();
      final aurora = g.addCard('Aurora - Lore Guardian', 0, Place.play);
      final suit = g.addCard('Gizmosuit', 0, Place.play);
      final top = g.state.player(0).deck.first;
      g.apply(ActivateMove(0, aurora, ability(g, aurora, 'royal inventory')));
      expect(g.state.obj(suit).exerted, isTrue);
      answer(g, [1], player: 0); // bottom
      expect(g.state.player(0).deck.last, top);
    });

    test('Anna - Heir to Arendelle: with Elsa in play the chosen opposing character skips its next ready', () {
      final g = emptyGame();
      g.addInk(0, 4);
      g.addCard('Elsa - Snow Queen', 0, Place.play);
      final foe = g.addCard(vanilla, 1, Place.play, exerted: true);
      g.addCard(vanilla2, 1, Place.play, exerted: true);
      g.apply(PlayMove(0, g.addCard('Anna - Heir to Arendelle', 0, Place.hand)));
      answer(g, [foe], player: 0);
      g.apply(EndTurnMove(0));
      expect(g.state.obj(foe).exerted, isTrue);
      expect(g.state.player(1).play.where((id) => g.state.obj(id).exerted), [foe]);
    });

    test('Anna - Heir to Arendelle: no Elsa, nothing to choose', () {
      final g = emptyGame();
      g.addInk(0, 4);
      g.addCard(vanilla, 1, Place.play, exerted: true);
      g.apply(PlayMove(0, g.addCard('Anna - Heir to Arendelle', 0, Place.hand)));
      expect(g.pending, isNull);
    });

    test("Eeyore: for each opponent, a character of theirs that can't ready next turn", () {
      final g = emptyGame();
      g.addInk(0, 9);
      final foe = g.addCard(vanilla, 1, Place.play, exerted: true);
      g.apply(PlayMove(0, g.addCard('Eeyore - In the Way', 0, Place.hand)));
      answer(g, [foe], player: 0);
      g.apply(EndTurnMove(0));
      expect(g.state.obj(foe).exerted, isTrue);
    });

    test('Containment Unit: the chosen character can\'t quest or challenge while the item is in play', () {
      final g = emptyGame(active: 1);
      g.addInk(1, 2);
      final mine = g.addCard(vanilla, 0, Place.play);
      g.addCard(vanilla2, 1, Place.play);
      final unit = g.addCard('Containment Unit', 1, Place.hand);
      g.apply(PlayMove(1, unit));
      answer(g, [mine], player: 1);
      g.apply(EndTurnMove(1));
      expect(g.whyNot(QuestMove(0, mine)), isNotNull);
      g.moveToForTest(unit, Place.discard);
      expect(g.whyNot(QuestMove(0, mine)), isNull);
    });

    test('Bunch of Balloons: the location has Evasive while the item is in play', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final loc = g.addCard("Carl's House - Flying High", 0, Place.play);
      final balloons = g.addCard('Bunch of Balloons', 0, Place.hand);
      g.apply(PlayMove(0, balloons));
      expect(g.chars(loc).has(Kw.evasive), isTrue);
      g.moveToForTest(balloons, Place.hand);
      expect(g.chars(loc).has(Kw.evasive), isFalse);
    });

    test("Elsa's Ice Palace: the exerted character doesn't ready while the location is in play", () {
      final g = emptyGame();
      g.addInk(0, 3);
      final foe = g.addCard(vanilla, 1, Place.play, exerted: true);
      final palace = g.addCard("Elsa's Ice Palace - Place of Solitude", 0, Place.hand);
      g.apply(PlayMove(0, palace));
      g.apply(EndTurnMove(0));
      expect(g.state.obj(foe).exerted, isTrue);
      g.apply(EndTurnMove(1));
      g.apply(EndTurnMove(0));
      expect(g.state.obj(foe).exerted, isTrue, reason: 'still, every turn');
      g.moveToForTest(palace, Place.discard);
      g.apply(EndTurnMove(1));
      g.apply(EndTurnMove(0));
      expect(g.state.obj(foe).exerted, isFalse);
    });

    test('Do You Want to Build A Snowman?: the chosen opponent picks (NO! puts their own character on the bottom)', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final foe = g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Do You Want to Build A Snowman?', 0, Place.hand)));
      expect(g.pending!.decision.player, 1);
      answer(g, [1], player: 1);
      expect(g.state.player(1).deck.last, foe);
      final g2 = emptyGame();
      g2.addInk(0, 3);
      g2.apply(PlayMove(0, g2.addCard('Do You Want to Build A Snowman?', 0, Place.hand)));
      answer(g2, [0], player: 1);
      expect(g2.state.player(0).lore, 3);
    });

    test('Daisy Duck - Multitalented Pirate: a card put into your inkwell makes the opponent return a character, once a turn', () {
      final g = emptyGame();
      g.addCard('Daisy Duck - Multitalented Pirate', 0, Place.play);
      final a = g.addCard(vanilla, 1, Place.play), b = g.addCard(vanilla2, 1, Place.play);
      g.apply(InkMove(0, g.addCard(vanilla, 0, Place.hand)));
      answer(g, [b], player: 1);
      expect(g.state.obj(b).zone, Place.hand);
      expect(g.state.obj(a).zone, Place.play);
    });

    test("Flynn Rider - High-Climbing Rogue: an opponent who chooses him discards a card", () {
      final g = emptyGame(active: 1);
      final flynn = g.addCard('Flynn Rider - High-Climbing Rogue', 0, Place.play);
      g.addCard(vanilla, 1, Place.play);
      final card = g.addCard(vanilla, 1, Place.hand);
      final suit = g.addCard('Gizmosuit', 1, Place.play);
      g.apply(ActivateMove(1, suit, ability(g, suit, 'cybernetic armor')));
      answer(g, [flynn], player: 1);
      expect(g.state.obj(card).zone, Place.discard);
      expect(g.chars(flynn).n(Kw.resist), 2);
    });
  });

  group('4.3 playing cards: costs and permissions', () {
    test('Atlantica: characters here count as +2 cost to sing (CR 8.11)', () {
      final g = emptyGame();
      final loc = g.addCard('Atlantica - Concert Hall', 0, Place.play);
      final singer = g.addCard(vanilla2, 0, Place.play); // cost 2
      final song = g.addCard("Can't Hold It Back Anymore", 0, Place.hand); // cost 4
      final sing = PlayMove(0, song, mode: PlayMode.sing, singers: [singer]);
      expect(g.whyNot(sing), isNotNull);
      g.state.obj(singer).at = loc;
      expect(g.whyNot(sing), isNull);
    });

    test('Belle - Always Reading and Belle - Mechanic Extraordinaire: Shift costs less (CR 8.10)', () {
      final g = emptyGame();
      final reading = g.addCard('Belle - Always Reading', 0, Place.play);
      g.addCard('Gizmosuit', 0, Place.discard);
      g.addCard('Fishbone Quill', 0, Place.discard);
      final mech = g.addCard('Belle - Mechanic Extraordinaire', 0, Place.hand); // Shift 7
      g.addInk(0, 3);
      final shift = PlayMove(0, mech, mode: PlayMode.shift, onto: reading);
      expect(g.whyNot(shift), isNotNull, reason: '7 - 2 items - 1 = 4');
      g.addInk(0, 1);
      expect(g.whyNot(shift), isNull);
      g.apply(shift);
      expect(g.inkReady(0), 0);
    });

    test('Belle - Apprentice Inventor: banish an item of yours to play her for free', () {
      final g = emptyGame();
      final suit = g.addCard('Gizmosuit', 0, Place.play);
      final belle = g.addCard('Belle - Apprentice Inventor', 0, Place.hand);
      expect(g.whyNot(PlayMove(0, belle)), isNull, reason: 'no ink, but an item');
      g.apply(PlayMove(0, belle));
      expect(g.state.obj(belle).zone, Place.play);
      expect(g.state.obj(suit).zone, Place.discard);
      final g2 = emptyGame();
      expect(g2.whyNot(PlayMove(0, g2.addCard('Belle - Apprentice Inventor', 0, Place.hand))), isNotNull);
    });

    test('Belle - Apprentice Inventor: with the ink, the player may still pay', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final suit = g.addCard('Gizmosuit', 0, Place.play);
      g.apply(PlayMove(0, g.addCard('Belle - Apprentice Inventor', 0, Place.hand)));
      answer(g, [0], player: 0);
      expect(g.state.obj(suit).zone, Place.play);
      expect(g.inkReady(0), 0);
    });

    test('Gantu: actions and items cost 2 more for everyone; singing is free of it', () {
      final g = emptyGame();
      g.addCard('Gantu - Experienced Enforcer', 1, Place.play);
      final suit = g.addCard('Gizmosuit', 0, Place.hand);
      final song = g.addCard('A Very Merry Unbirthday', 0, Place.hand);
      expect(g.playCost(0, suit), 5);
      expect(g.playCost(0, song), 3);
      expect(g.playCost(0, g.addCard(vanilla, 0, Place.hand)), 3);
      final singer = g.addCard(vanilla2, 0, Place.play);
      expect(g.whyNot(PlayMove(0, song, mode: PlayMode.sing, singers: [singer])), isNull);
    });

    test("Gantu: characters can't exert to sing until the start of your next turn", () {
      final g = emptyGame();
      g.addInk(0, 4);
      final singer = g.addCard(vanilla2, 0, Place.play);
      final theirs = g.addCard(vanilla2, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Gantu - Experienced Enforcer', 0, Place.hand)));
      final song = g.addCard('A Very Merry Unbirthday', 0, Place.hand);
      expect(g.whyNot(PlayMove(0, song, mode: PlayMode.sing, singers: [singer])), isNotNull);
      g.apply(EndTurnMove(0));
      expect(g.whyNot(PlayMove(1, g.addCard('A Very Merry Unbirthday', 1, Place.hand), mode: PlayMode.sing, singers: [theirs])), isNotNull);
      g.apply(EndTurnMove(1));
      expect(g.whyNot(PlayMove(0, song, mode: PlayMode.sing, singers: [singer])), isNull);
    });

    test("Gizmoduck: while you have no cards in hand, opponents can't play actions with cost 4 or more", () {
      final g = emptyGame(active: 1);
      g.addInk(1, 5);
      g.addCard('Gizmoduck - Duckburg Defender', 0, Place.play);
      final big = g.addCard("Don't Be Nervous", 1, Place.hand); // 5
      final small = g.addCard('Divebomb', 1, Place.hand); // 3
      expect(g.whyNot(PlayMove(1, big)), isNotNull);
      expect(g.whyNot(PlayMove(1, small)), isNull);
      g.addCard(vanilla, 0, Place.hand);
      expect(g.whyNot(PlayMove(1, big)), isNull);
    });

    test("Escape Plan: only after 2 cards were put into your discard this turn; each player inks 2 characters", () {
      final g = emptyGame();
      g.addInk(0, 5);
      final plan = g.addCard('Escape Plan', 0, Place.hand);
      expect(g.whyNot(PlayMove(0, plan)), isNotNull);
      g.moveToForTest(g.addCard(vanilla, 0, Place.hand), Place.discard);
      g.moveToForTest(g.addCard(vanilla, 0, Place.hand), Place.discard);
      final mine = [g.addCard(vanilla, 0, Place.play), g.addCard(vanilla2, 0, Place.play)];
      final theirs = [g.addCard(vanilla, 1, Place.play), g.addCard(vanilla2, 1, Place.play), g.addCard(vanilla2, 1, Place.play)];
      g.apply(PlayMove(0, plan));
      answer(g, theirs.take(2).toList(), player: 1);
      for (final id in [...mine, ...theirs.take(2)]) {
        expect(g.state.obj(id).zone, Place.inkwell);
        expect(g.state.obj(id).exerted, isTrue);
      }
      expect(g.state.obj(theirs.last).zone, Place.play);
    });

    test('Falling Down The Rabbit Hole: each player inks one of their characters, exerted', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final mine = g.addCard(vanilla, 0, Place.play);
      final theirs = g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Falling Down The Rabbit Hole', 0, Place.hand)));
      expect(g.state.obj(mine).zone, Place.inkwell);
      expect(g.state.obj(theirs).zone, Place.inkwell);
      expect(g.state.obj(theirs).exerted, isTrue);
    });

    test('Grandmother Willow: the next character this turn costs 1 less, once a turn', () {
      final g = emptyGame();
      g.addCard('Grandmother Willow - Ancient Advisor', 0, Place.play);
      final a = g.addCard(vanilla, 0, Place.hand), b = g.addCard(vanilla, 0, Place.hand);
      expect(g.playCost(0, a), 2);
      expect(g.playCost(0, g.addCard('Gizmosuit', 0, Place.hand)), 3, reason: 'characters only');
      g.addInk(0, 2);
      g.apply(PlayMove(0, a));
      expect(g.playCost(0, b), 3);
      g.apply(EndTurnMove(0));
      g.apply(EndTurnMove(1));
      expect(g.playCost(0, b), 2);
    });

    test('Bibbidi Bobbidi Boo: return a character of yours to play another with the same cost or less for free', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final abu = g.addCard(vanilla, 0, Place.play); // cost 3
      final cheap = g.addCard(vanilla2, 0, Place.hand); // cost 2
      g.addCard('Goliath - Clan Leader', 0, Place.hand); // cost 6
      g.apply(PlayMove(0, g.addCard('Bibbidi Bobbidi Boo', 0, Place.hand)));
      expect(g.state.obj(abu).zone, Place.hand);
      expect(g.state.obj(cheap).zone, Place.play);
    });

    test('Dash Parr - Super Fast: the revealed card may be played, paying its cost; otherwise it is discarded', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final dash = g.addCard('Dash Parr - Super Fast', 0, Place.play);
      final top = g.state.player(0).deck.first; // Aladdin, cost 2
      g.apply(QuestMove(0, dash));
      answer(g, [1], player: 0); // reveal
      answer(g, [1], player: 0); // play it
      expect(g.state.obj(top).zone, Place.play);
      expect(g.inkReady(0), 0);
      g.apply(EndTurnMove(0));
      g.apply(EndTurnMove(1));
      final next = g.state.player(0).deck.first;
      g.state.player(0).inkwell.clear();
      g.apply(QuestMove(0, dash));
      answer(g, [1], player: 0);
      expect(g.state.obj(next).zone, Place.discard, reason: "can't pay");
    });
  });

  group('1.9 damage and 4.6 challenges', () {
    test('Beast - Selfless Protector: damage to your other characters becomes counters on him (CR 6.5)', () {
      final g = emptyGame(active: 1);
      g.addCard('Beast - Selfless Protector', 0, Place.play);
      final beast = g.state.player(0).play.single;
      final abu = g.addCard(vanilla, 0, Place.play, exerted: true);
      final a = g.addCard('Goliath - Clan Leader', 1, Place.play);
      g.apply(ChallengeMove(1, a, abu));
      expect(g.state.obj(abu).zone, Place.play);
      expect(g.state.obj(abu).damage, 0);
      expect(g.state.obj(beast).damage, 6);
      expect(g.state.obj(a).damage, 3, reason: 'Abu still deals his damage');
    });

    test("Beast - Snowfield Troublemaker: at a location, he takes no damage from his challenge", () {
      final g = emptyGame();
      final loc = g.addCard("Carl's House - Flying High", 0, Place.play);
      final beast = g.addCard('Beast - Snowfield Troublemaker', 0, Place.play); // 3/1
      final foe = g.addCard(vanilla, 1, Place.play, exerted: true);
      g.state.obj(beast).at = loc;
      g.apply(ChallengeMove(0, beast, foe));
      expect(g.state.obj(beast).zone, Place.play);
      expect(g.state.obj(foe).zone, Place.discard);
    });

    test("Beast's Castle: a character here that challenges gains 1 lore", () {
      final g = emptyGame();
      final loc = g.addCard("Beast's Castle - Winter Gardens", 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      final foe = g.addCard(vanilla2, 1, Place.play, exerted: true);
      g.state.obj(abu).at = loc;
      g.apply(ChallengeMove(0, abu, foe));
      expect(g.state.player(0).lore, 1);
    });

    test('Beast - Tragic Hero: undamaged at the start of your turn, draw; damaged, +4 {s} this turn', () {
      final g = emptyGame(active: 1);
      final beast = g.addCard('Beast - Tragic Hero', 0, Place.play);
      g.apply(EndTurnMove(1));
      expect(g.state.player(0).hand, hasLength(2), reason: 'the ability and the draw step');
      g.state.obj(beast).damage = 1;
      g.apply(EndTurnMove(0));
      g.apply(EndTurnMove(1));
      expect(g.chars(beast).strength, 3 + 4);
      expect(g.state.player(0).hand, hasLength(3));
    });

    test('Darkwing Duck: can challenge a ready Villain, not another ready character (CR 4.6.4)', () {
      final g = emptyGame();
      final dw = g.addCard('Darkwing Duck - Cool Under Pressure', 0, Place.play);
      final villain = g.addCard('Gaston - Arrogant Showoff', 1, Place.play);
      final other = g.addCard(vanilla, 1, Place.play);
      expect(g.whyNot(ChallengeMove(0, dw, villain)), isNull);
      expect(g.whyNot(ChallengeMove(0, dw, other)), isNotNull);
    });

    test('Blessed Bagpipes: a character of yours with a card under it is challenged, gain 1 lore', () {
      final g = emptyGame(active: 1);
      g.addCard('Blessed Bagpipes', 0, Place.play);
      final bambi = g.addCard('Bambi - Ethereal Fawn', 0, Place.play, exerted: true);
      final plain = g.addCard(vanilla2, 0, Place.play, exerted: true);
      final a = g.addCard(vanilla, 1, Place.play), b = g.addCard(vanilla, 1, Place.play);
      g.apply(ChallengeMove(1, a, plain));
      expect(g.state.player(0).lore, 0);
      final under = g.state.player(0).deck.removeAt(0);
      g.state.obj(under).zone = Place.play;
      g.state.obj(bambi).under.add(under);
      g.apply(ChallengeMove(1, b, bambi));
      expect(g.state.player(0).lore, 1);
    });

    test('Goofy - Emerald Champion: another Emerald character challenged and banished banishes the challenger; they have Ward', () {
      final g = emptyGame(active: 1);
      g.addCard('Goofy - Emerald Champion', 0, Place.play);
      final emerald = g.addCard('Diablo - Devoted Herald', 0, Place.play, exerted: true); // emerald, 2/2, Evasive
      final flynn = g.addCard('Flynn Rider - Breaking and Entering', 0, Place.play); // emerald
      expect(g.chars(flynn).has(Kw.ward), isTrue);
      final a = g.addCard('Dash Parr - Super Fast', 1, Place.play); // Evasive 4/4
      g.apply(ChallengeMove(1, a, emerald));
      expect(g.state.obj(emerald).zone, Place.discard);
      expect(g.state.obj(a).zone, Place.discard);
    });

    test("Flynn Rider - Breaking and Entering: the challenger discards, or you gain 2 lore", () {
      final g = emptyGame(active: 1);
      final flynn = g.addCard('Flynn Rider - Breaking and Entering', 0, Place.play, exerted: true);
      final a = g.addCard(vanilla2, 1, Place.play);
      final card = g.addCard(vanilla, 1, Place.hand);
      g.apply(ChallengeMove(1, a, flynn));
      answer(g, [0], player: 1);
      expect(g.state.player(0).lore, 2);
      expect(g.state.obj(card).zone, Place.hand);
    });

    test('Baymax - Armored Companion: lore for each damage removed this way', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final abu = g.addCard(vanilla, 0, Place.play, damage: 1);
      g.apply(PlayMove(0, g.addCard('Baymax - Armored Companion', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.obj(abu).damage, 0);
      expect(g.state.player(0).lore, 1, reason: 'only 1 damage was there');
    });

    test('Antonio Madrigal - Animal Doctor: the top card is inked only if damage was removed', () {
      final g = emptyGame();
      g.addInk(0, 4);
      g.addCard(vanilla, 0, Place.play);
      g.apply(PlayMove(0, g.addCard('Antonio Madrigal - Animal Doctor', 0, Place.hand)));
      answer(g, [1], player: 0);
      answer(g, [g.pending!.decision.options.first], player: 0);
      expect(g.state.player(0).inkwell, hasLength(4));
      final g2 = emptyGame();
      g2.addInk(0, 4);
      final hurt = g2.addCard(vanilla, 0, Place.play, damage: 1);
      g2.apply(PlayMove(0, g2.addCard('Antonio Madrigal - Animal Doctor', 0, Place.hand)));
      answer(g2, [1], player: 0);
      answer(g2, [hurt], player: 0);
      expect(g2.state.player(0).inkwell, hasLength(5));
      expect(g2.state.obj(g2.state.player(0).inkwell.last).exerted, isTrue);
    });

    test("Can't Hold It Back Anymore: exert, then all other characters' damage moves to it", () {
      final g = emptyGame();
      g.addInk(0, 4);
      final foe = g.addCard('Goliath - Clan Leader', 1, Place.play);
      final a = g.addCard(vanilla2, 0, Place.play, damage: 2);
      final b = g.addCard(vanilla2, 1, Place.play, damage: 1);
      g.apply(PlayMove(0, g.addCard("Can't Hold It Back Anymore", 0, Place.hand)));
      answer(g, [foe], player: 0);
      expect(g.state.obj(foe).exerted, isTrue);
      expect(g.state.obj(foe).damage, 3);
      expect(g.state.obj(a).damage + g.state.obj(b).damage, 0);
    });

    test("Everybody's Got a Weakness: 1 damage from each of yours to them, draw that many", () {
      final g = emptyGame();
      g.addInk(0, 4);
      g.addCard(vanilla2, 0, Place.play, damage: 2);
      g.addCard(vanilla2, 0, Place.play, damage: 1);
      g.addCard(vanilla2, 0, Place.play);
      final foe = g.addCard('Goliath - Clan Leader', 1, Place.play);
      g.apply(PlayMove(0, g.addCard("Everybody's Got a Weakness", 0, Place.hand)));
      expect(g.state.obj(foe).damage, 2);
      expect(g.state.player(0).hand, hasLength(2));
    });

    test("Elisa Maza: your characters' {s} can't go below the printed value", () {
      final g = emptyGame();
      g.addInk(0, 4);
      g.addCard('Elisa Maza - Transformed Gargoyle', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      final foe = g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Dale - Mischievous Ranger', 0, Place.hand)));
      answer(g, [1], player: 0);
      answer(g, [abu], player: 0);
      expect(g.chars(abu).strength, 3);
      final g2 = emptyGame();
      g2.addInk(0, 4);
      g2.addCard('Elisa Maza - Transformed Gargoyle', 0, Place.play);
      final theirs = g2.addCard(vanilla, 1, Place.play);
      g2.apply(PlayMove(0, g2.addCard('Dale - Mischievous Ranger', 0, Place.hand)));
      answer(g2, [1], player: 0);
      answer(g2, [theirs], player: 0);
      expect(g2.chars(theirs).strength, 0);
      expect(foe, isNonZero);
    });

    test('Calhoun: discard a card to give -3 {s}; with an empty hand nothing happens (CR 6.1.5.1)', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final foe = g.addCard(vanilla, 1, Place.play);
      g.addCard(vanilla2, 0, Place.hand);
      g.apply(PlayMove(0, g.addCard('Calhoun - Battle-Tested', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.chars(foe).strength, 0);
      final g2 = emptyGame();
      g2.addInk(0, 3);
      final foe2 = g2.addCard(vanilla, 1, Place.play);
      g2.apply(PlayMove(0, g2.addCard('Calhoun - Battle-Tested', 0, Place.hand)));
      answer(g2, [1], player: 0);
      expect(g2.chars(foe2).strength, 3);
    });

    test('Divebomb: banish your Reckless character to banish a chosen one with less {s}', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final aladdin = g.addCard('Aladdin - Barreling Through', 0, Place.play); // 4 strength, Reckless
      final weak = g.addCard(vanilla, 1, Place.play); // 3
      final strong = g.addCard('Goliath - Clan Leader', 1, Place.play); // 6
      g.apply(PlayMove(0, g.addCard('Divebomb', 0, Place.hand)));
      expect(g.state.obj(aladdin).zone, Place.discard);
      expect(g.state.obj(weak).zone, Place.discard, reason: 'the only one with less than 4');
      expect(g.state.obj(strong).zone, Place.play);
    });

    test('Gaston - Arrogant Showoff: banish one of your items to give +2 {s}', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final suit = g.addCard('Gizmosuit', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      final gaston = g.addCard('Gaston - Arrogant Showoff', 0, Place.hand);
      g.apply(PlayMove(0, gaston));
      answer(g, [1], player: 0);
      answer(g, [abu], player: 0);
      expect(g.state.obj(suit).zone, Place.discard);
      expect(g.chars(abu).strength, 5);
    });

    test('Beast - Frustrated Designer: {e}, 2 {i}, banish 2 of your items - deal 5 damage', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final beast = g.addCard('Beast - Frustrated Designer', 0, Place.play);
      final i = ability(g, beast, "i've had it");
      g.addCard('Gizmosuit', 0, Place.play);
      expect(g.whyNot(ActivateMove(0, beast, i)), isNotNull, reason: 'one item');
      g.addCard('Fishbone Quill', 0, Place.play);
      final foe = g.addCard('Goliath - Clan Leader', 1, Place.play);
      g.apply(ActivateMove(0, beast, i));
      answer(g, [foe], player: 0);
      expect(g.state.player(0).play, [beast]);
      expect(g.state.obj(foe).zone, Place.discard);
    });

    test('Angel: once during your turn, discard a card to deal 2 damage', () {
      final g = emptyGame();
      final angel = g.addCard('Angel - Experiment 624', 0, Place.play);
      final foe = g.addCard('Goliath - Clan Leader', 1, Place.play);
      g.addCard(vanilla, 0, Place.hand);
      g.addCard(vanilla, 0, Place.hand);
      final i = ability(g, angel, 'good aim');
      g.apply(ActivateMove(0, angel, i));
      answer(g, [g.state.player(0).hand.first], player: 0);
      answer(g, [foe], player: 0);
      expect(g.state.obj(foe).damage, 2);
      expect(g.whyNot(ActivateMove(0, angel, i)), isNotNull, reason: 'once');
      expect(g.state.obj(angel).exerted, isFalse);
    });

    test('Buzz Lightyear - On the Way: paying 2 or less for a non-character loots; for a character pings', () {
      final g = emptyGame();
      g.addInk(0, 4);
      g.addCard('Buzz Lightyear - On the Way', 0, Place.play);
      final foe = g.addCard(vanilla, 1, Place.play, damage: 1);
      g.apply(PlayMove(0, g.addCard('Detective\'s Badge', 0, Place.hand)));
      expect(g.state.player(0).discard, hasLength(1), reason: 'drew a card, then discarded it');
      expect(g.state.obj(foe).damage, 1);
      g.apply(PlayMove(0, g.addCard(vanilla2, 0, Place.hand)));
      expect(g.state.obj(foe).zone, Place.discard, reason: '1 more damage on a 2-willpower character');
    });
  });

  group('6.2 triggered abilities', () {
    test('Alma Madrigal - Accepting Grandmother: the characters that sang are readied (CR 5.4.4)', () {
      final g = emptyGame();
      g.addCard('Alma Madrigal - Accepting Grandmother', 0, Place.play);
      final singer = g.addCard(vanilla2, 0, Place.play);
      g.apply(PlayMove(0, g.addCard('A Very Merry Unbirthday', 0, Place.hand), mode: PlayMode.sing, singers: [singer]));
      answer(g, [1], player: 0);
      expect(g.state.obj(singer).exerted, isFalse);
    });

    test('Fantastical and Magical: a card and a lore for each character that sang it (Sing Together, CR 8.12)', () {
      final g = emptyGame();
      final singers = [g.addCard('Goliath - Clan Leader', 0, Place.play), g.addCard('Belle - Snowfield Strategist', 0, Place.play)]; // 6 + 4
      g.apply(PlayMove(0, g.addCard('Fantastical and Magical', 0, Place.hand), mode: PlayMode.sing, singers: singers));
      expect(g.state.player(0).hand, hasLength(2));
      expect(g.state.player(0).lore, 2);
    });

    test('Basil - Disguised Detective: inking pays 1 to make chosen opponent discard', () {
      final g = emptyGame();
      g.addInk(0, 1);
      g.addCard('Basil - Disguised Detective', 0, Place.play);
      final card = g.addCard(vanilla, 1, Place.hand);
      g.apply(InkMove(0, g.addCard(vanilla, 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.obj(card).zone, Place.discard);
      expect(g.inkReady(0), 1, reason: 'one paid, the new one ready');
    });

    test('Basil - Great Mouse Detective: draws 2 only when shifted', () {
      final g = emptyGame();
      g.addInk(0, 6);
      final old = g.addCard('Basil - Disguised Detective', 0, Place.play);
      g.apply(PlayMove(0, g.addCard('Basil - Great Mouse Detective', 0, Place.hand), mode: PlayMode.shift, onto: old));
      answer(g, [1], player: 0);
      expect(g.state.player(0).hand, hasLength(2));
      final g2 = emptyGame();
      g2.addInk(0, 6);
      g2.apply(PlayMove(0, g2.addCard('Basil - Great Mouse Detective', 0, Place.hand)));
      expect(g2.pending, isNull);
    });

    test('Bambi: exerting during your turn reveals one card per card under him; characters to the hand', () {
      final g = emptyGame();
      final bambi = g.addCard('Bambi - Ethereal Fawn', 0, Place.play);
      for (var i = 0; i < 2; i++) {
        final u = g.state.player(0).deck.removeAt(g.state.player(0).deck.length - 1);
        g.state.obj(u).zone = Place.play;
        g.state.obj(bambi).under.add(u);
      }
      final item = g.addCard('Gizmosuit', 0, Place.deck);
      g.apply(QuestMove(0, bambi));
      expect(g.state.player(0).hand, hasLength(1), reason: 'Aladdin taken, the item not');
      expect(g.state.player(0).deck.last, item);
    });

    test('Dash Parr & Violet Parr: questing draws a card for each card under them', () {
      final g = emptyGame();
      final dv = g.addCard('Dash Parr & Violet Parr - Super Siblings', 0, Place.play);
      final u = g.state.player(0).deck.removeAt(9);
      g.state.obj(u).zone = Place.play;
      g.state.obj(dv).under.add(u);
      g.apply(QuestMove(0, dv));
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Fairy Godmother - Magical Benefactor: Boost banishes; their player may play the top card if a character or item', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final fg = g.addCard('Fairy Godmother - Magical Benefactor', 0, Place.play);
      final foe = g.addCard('Goliath - Clan Leader', 1, Place.play);
      final top = g.state.player(1).deck.first;
      g.apply(ActivateMove(0, fg, g.abilitiesOf(fg).indexWhere((a) => a is KeywordAbility)));
      answer(g, [1], player: 0); // banish
      expect(g.state.obj(foe).zone, Place.discard);
      answer(g, [1], player: 1); // reveal
      answer(g, [top], player: 1); // play it
      expect(g.state.obj(top).zone, Place.play);
    });

    test('Donald Duck - Fred Honeywell: using Boost puts another card under; during opponents\' turns banished cards under it draw', () {
      final g = emptyGame();
      g.addInk(0, 2);
      g.addCard('Donald Duck - Fred Honeywell', 0, Place.play);
      final goofy = g.addCard('Goofy - Ghost of Jacob Marley', 0, Place.play); // Boost 2
      g.apply(ActivateMove(0, goofy, g.abilitiesOf(goofy).indexWhere((a) => a is KeywordAbility)));
      answer(g, [1], player: 0);
      expect(g.state.obj(goofy).under, hasLength(2));
      g.apply(EndTurnMove(0));
      g.state.obj(goofy).exerted = true;
      final a = g.addCard('Goliath - Clan Leader', 1, Place.play);
      for (var i = 0; i < 2; i++) {
        g.addCard(vanilla, 1, Place.hand);
      }
      final hand = g.state.player(0).hand.length;
      g.apply(ChallengeMove(1, a, goofy));
      // Two triggers: Goofy's own Grave Outcome (theirs to discard) and Donald's Well Wishes.
      while (g.pending != null) {
        final d = g.pending!.decision;
        answer(g, switch (d.kind) {
          DecisionKind.option => [0],
          DecisionKind.yesNo => [1],
          _ => d.options.take(d.min).toList(),
        });
      }
      expect(g.state.player(0).hand.length, hand + 2);
      expect(g.state.player(1).hand, hasLength(1), reason: 'Grave Outcome: 2 of their 3 cards discarded, one for each card under him');
    });

    test('Goofy - Groundbreaking Chef: remove 1 from each other character, ready those healed', () {
      final g = emptyGame();
      g.addCard('Goofy - Groundbreaking Chef', 0, Place.play);
      final hurt = g.addCard(vanilla2, 0, Place.play, exerted: true, damage: 2);
      final fine = g.addCard(vanilla, 0, Place.play, exerted: true);
      g.apply(EndTurnMove(0));
      answer(g, [1], player: 0);
      expect(g.state.obj(hurt).damage, 1);
      expect(g.state.obj(hurt).exerted, isFalse);
      expect(g.state.obj(fine).exerted, isTrue);
    });

    test('Graveyard of Christmas Future: moving a character here puts the top card under it', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final yard = g.addCard('Graveyard of Christmas Future - Lonely Resting Place', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      g.apply(MoveMove(0, abu, yard));
      expect(g.state.obj(yard).under, hasLength(1));
    });

    test("Carl Fredricksen - On the Move: a location played moves him and another; questing there draws its {l}", () {
      final g = emptyGame();
      g.addInk(0, 3);
      final carl = g.addCard('Carl Fredricksen - On the Move', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      final room = g.addCard("Andy's Room - Home Base", 0, Place.hand); // 1 lore
      g.apply(PlayMove(0, room));
      answer(g, [1], player: 0);
      answer(g, [abu], player: 0);
      expect(g.state.obj(carl).at, room);
      expect(g.state.obj(abu).at, room);
      g.apply(QuestMove(0, carl));
      expect(g.state.player(0).hand, hasLength(1));
    });

    test("Carl's House: once a turn, move a character from here to another location for free and gain 1 lore", () {
      final g = emptyGame();
      final house = g.addCard("Carl's House - Flying High", 0, Place.play);
      final room = g.addCard("Andy's Room - Home Base", 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      g.state.obj(abu).at = house;
      final i = ability(g, house, 'moving day');
      g.apply(ActivateMove(0, house, i));
      expect(g.state.obj(abu).at, room);
      expect(g.state.player(0).lore, 1);
      expect(g.whyNot(ActivateMove(0, house, i)), isNotNull);
    });

    test("Andy's Room: +2 {w} and +1 {l} while you have only 1 character here", () {
      final g = emptyGame();
      final room = g.addCard("Andy's Room - Home Base", 0, Place.play);
      final a = g.addCard(vanilla, 0, Place.play);
      final b = g.addCard(vanilla2, 0, Place.play);
      g.state.obj(a).at = room;
      expect(g.chars(a).willpower, 4);
      expect(g.chars(a).lore, 3);
      g.state.obj(b).at = room;
      expect(g.chars(a).willpower, 2);
    });

    test('Fergus - Outpost Builder: exerting plays a location with cost 4 or less from the discard for free', () {
      final g = emptyGame();
      final fergus = g.addCard('Fergus - Outpost Builder', 0, Place.play);
      final room = g.addCard("Andy's Room - Home Base", 0, Place.discard);
      g.apply(QuestMove(0, fergus));
      answer(g, [1], player: 0);
      // The only location that qualifies may be played without a separate choice.
      if (g.pending?.decision.kind == DecisionKind.cards) answer(g, [room], player: 0);
      expect(g.state.obj(room).zone, Place.play);
    });

    test('Fergus - Outpost Builder: at a location, a location challenged and banished lets you deal 4 damage', () {
      final g = emptyGame();
      final mine = g.addCard("Carl's House - Flying High", 0, Place.play);
      final fergus = g.addCard('Fergus - Outpost Builder', 0, Place.play);
      g.state.obj(fergus).at = mine;
      final theirs = g.addCard("Beast's Castle - Winter Gardens", 1, Place.play, damage: 5); // willpower 6
      final abu = g.addCard(vanilla, 0, Place.play);
      final foe = g.addCard('Goliath - Clan Leader', 1, Place.play);
      g.apply(ChallengeMove(0, abu, theirs));
      answer(g, [1], player: 0);
      answer(g, [foe], player: 0);
      expect(g.state.obj(foe).damage, 4);
    });

    test('Flotilla: with a character here, opponents lose 1 lore and you gain what they lost', () {
      final g = emptyGame(active: 1);
      final flotilla = g.addCard('Flotilla - Coconut Armada', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      g.state.obj(abu).at = flotilla;
      g.state.player(1).lore = 3;
      g.apply(EndTurnMove(1));
      expect(g.state.player(1).lore, 2);
      expect(g.state.player(0).lore, 1);
    });

    test('Game Preserve: Evasive while a character with Evasive is here', () {
      final g = emptyGame();
      final park = g.addCard('Game Preserve - Protected Land', 0, Place.play);
      final dash = g.addCard('Dash Parr - Super Fast', 0, Place.play);
      expect(g.chars(park).has(Kw.evasive), isFalse);
      g.state.obj(dash).at = park;
      expect(g.chars(park).has(Kw.evasive), isTrue);
    });

    test('Darkwing Tower: an opposing Villain banished during your turn readies a character here, who then can\'t quest', () {
      final g = emptyGame();
      final tower = g.addCard('Darkwing Tower - Icy Headquarters', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      final resting = g.addCard('Goliath - Clan Leader', 0, Place.play, exerted: true);
      g.state.obj(resting).at = tower;
      final villain = g.addCard('Gaston - Arrogant Showoff', 1, Place.play, exerted: true, damage: 3);
      g.apply(ChallengeMove(0, abu, villain));
      answer(g, [1], player: 0);
      expect(g.state.obj(resting).exerted, isFalse);
      expect(g.whyNot(QuestMove(0, resting)), isNotNull);
    });

    test('Chernabog - Unnatural Force: shuffle an opposing character away; that player may play one from their discard', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final foe = g.addCard('Goliath - Clan Leader', 1, Place.play);
      final back = g.addCard(vanilla, 1, Place.discard);
      g.apply(PlayMove(0, g.addCard('Chernabog - Unnatural Force', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.obj(foe).zone, Place.deck);
      expect(g.pending!.decision.player, 1);
      answer(g, [back], player: 1);
      expect(g.state.obj(back).zone, Place.play);
    });

    test('Chip: a character with 4 {w} or more back from the discard; draw with another such character', () {
      final g = emptyGame();
      g.addInk(0, 10);
      final tough = g.addCard('Goliath - Clan Leader', 0, Place.discard); // willpower 5
      g.addCard(vanilla, 0, Place.discard); // willpower 2
      g.apply(PlayMove(0, g.addCard('Chip - Retrieval Expert', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.obj(tough).zone, Place.hand);
      g.apply(PlayMove(0, g.addCard('Chip - Team Player', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.player(0).hand, hasLength(2), reason: 'Chip - Retrieval Expert has 4 willpower');
    });

    test('Doc - Taking Notes: another Seven Dwarfs character or a Princess draws a card', () {
      final g = emptyGame();
      g.addInk(0, 8);
      g.apply(PlayMove(0, g.addCard('Doc - Taking Notes', 0, Place.hand)));
      expect(g.state.player(0).hand, isEmpty, reason: '"another": not himself');
      g.addCard('Belle - Always Reading', 0, Place.play);
      g.apply(PlayMove(0, g.addCard('Doc - Taking Notes', 0, Place.hand)));
      expect(g.state.player(0).hand, hasLength(1));
    });

    test("Della Duck: ready a character with Boost, who can't quest or challenge this turn", () {
      final g = emptyGame();
      g.addInk(0, 4);
      final goofy = g.addCard('Goofy - Ghost of Jacob Marley', 0, Place.play, exerted: true);
      g.addCard(vanilla, 0, Place.play, exerted: true);
      g.apply(PlayMove(0, g.addCard('Della Duck - Returning Mother', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.obj(goofy).exerted, isFalse);
      expect(g.whyNot(QuestMove(0, goofy)), isNotNull);
    });

    test('Cinderella - Dream Come True: after playing a Princess, ink a card from the hand to draw', () {
      final g = emptyGame();
      g.addInk(0, 2);
      g.addCard('Cinderella - Dream Come True', 0, Place.play);
      g.apply(PlayMove(0, g.addCard('Belle - Always Reading', 0, Place.hand)));
      final card = g.addCard(vanilla, 0, Place.hand);
      g.apply(EndTurnMove(0));
      answer(g, [1], player: 0);
      expect(g.state.obj(card).zone, Place.inkwell);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Discarded Armor: only after you discarded a card this turn', () {
      final g = emptyGame();
      final armor = g.addCard('Discarded Armor', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      final i = ability(g, armor, 'found equipment');
      g.apply(ActivateMove(0, armor, i));
      expect(g.chars(abu).has(Kw.resist), isFalse);
      final g2 = emptyGame();
      g2.addInk(0, 3);
      final armor2 = g2.addCard('Discarded Armor', 0, Place.play);
      final abu2 = g2.addCard(vanilla, 0, Place.play);
      g2.addCard(vanilla2, 0, Place.hand);
      g2.apply(PlayMove(0, g2.addCard('Calhoun - Battle-Tested', 0, Place.hand)));
      answer(g2, [1], player: 0); // discards the only card (no opposing character to weaken)
      expect(g2.state.player(0).discard, hasLength(1));
      g2.apply(ActivateMove(0, armor2, i));
      answer(g2, [abu2], player: 0);
      expect(g2.chars(abu2).n(Kw.resist), 1);
    });

    test('Diablo - Devoted Herald: an opponent drawing on their turn while he is exerted lets you draw', () {
      final g = emptyGame();
      g.addCard('Diablo - Devoted Herald', 0, Place.play, exerted: true);
      g.apply(EndTurnMove(0));
      // Diablo readied? No: he is player 0's, and it is player 1's turn: player 1 drew.
      answer(g, [1], player: 0);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Emerald Chromicon: your character banished on an opponent\'s turn returns a chosen character', () {
      final g = emptyGame(active: 1);
      g.addCard('Emerald Chromicon', 0, Place.play);
      final mine = g.addCard(vanilla2, 0, Place.play, exerted: true);
      final a = g.addCard('Goliath - Clan Leader', 1, Place.play);
      g.apply(ChallengeMove(1, a, mine));
      answer(g, [1], player: 0);
      expect(g.state.obj(a).zone, Place.hand);
    });

    test('Belle - Snowfield Strategist: a banished character of yours may go into your inkwell, exerted', () {
      final g = emptyGame(active: 1);
      g.addCard('Belle - Snowfield Strategist', 0, Place.play);
      final mine = g.addCard(vanilla2, 0, Place.play, exerted: true);
      final a = g.addCard('Goliath - Clan Leader', 1, Place.play);
      g.apply(ChallengeMove(1, a, mine));
      answer(g, [1], player: 0);
      expect(g.state.obj(mine).zone, Place.inkwell);
      expect(g.state.obj(mine).exerted, isTrue);
    });

    test('Daisy Duck - Sapphire Champion: other Sapphire characters have Resist +1', () {
      final g = emptyGame();
      final daisy = g.addCard('Daisy Duck - Sapphire Champion', 0, Place.play);
      final sapphire = g.addCard('Belle - Always Reading', 0, Place.play);
      final ruby = g.addCard(vanilla, 0, Place.play);
      expect(g.chars(sapphire).n(Kw.resist), 1);
      expect(g.chars(ruby).has(Kw.resist), isFalse);
      expect(g.chars(daisy).has(Kw.resist), isFalse);
      g.apply(QuestMove(0, sapphire));
      final top = g.state.player(0).deck.first;
      answer(g, [1], player: 0);
      expect(g.state.player(0).deck.last, top);
    });

    test('Donald Duck - Ruby Champion: other Ruby characters get +1 {s}; with 7 {s} or more also +1 {l}', () {
      final g = emptyGame();
      g.addCard('Donald Duck - Ruby Champion', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play); // ruby 3
      final belle = g.addCard('Belle - Mechanic Extraordinaire', 0, Place.play); // ruby/sapphire 7
      expect(g.chars(abu).strength, 4);
      expect(g.chars(abu).lore, 2);
      expect(g.chars(belle).strength, 8);
      expect(g.chars(belle).lore, 4);
    });

    test('Firefly Swarm: the second mode needs 2 other cards put into your discard this turn', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final foe = g.addCard('Goliath - Clan Leader', 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Firefly Swarm', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.obj(foe).zone, Place.play);
      final g2 = emptyGame();
      g2.addInk(0, 3);
      final foe2 = g2.addCard('Goliath - Clan Leader', 1, Place.play);
      g2.moveToForTest(g2.addCard(vanilla, 0, Place.hand), Place.discard);
      g2.moveToForTest(g2.addCard(vanilla, 0, Place.hand), Place.discard);
      g2.apply(PlayMove(0, g2.addCard('Firefly Swarm', 0, Place.hand)));
      answer(g2, [1], player: 0);
      expect(g2.state.obj(foe2).zone, Place.discard);
    });

    test('Fishbone Quill and Cleansing Rainwater', () {
      final g = emptyGame();
      final quill = g.addCard('Fishbone Quill', 0, Place.play);
      final card = g.addCard(vanilla, 0, Place.hand);
      g.apply(ActivateMove(0, quill, ability(g, quill, 'go ahead')));
      expect(g.state.obj(card).zone, Place.inkwell);
      final rain = g.addCard('Cleansing Rainwater', 0, Place.play);
      final a = g.addCard('Goliath - Clan Leader', 0, Place.play, damage: 3);
      g.apply(ActivateMove(0, rain, ability(g, rain, 'ancient power')));
      expect(g.state.obj(a).damage, 1);
      expect(g.state.obj(rain).zone, Place.discard);
    });

    test("Baymax's Healthcare Chip: the bigger heal needs a Robot", () {
      final g = emptyGame();
      final chip = g.addCard("Baymax's Healthcare Chip", 0, Place.play);
      final a = g.addCard('Goliath - Clan Leader', 0, Place.play, damage: 4);
      g.apply(ActivateMove(0, chip, ability(g, chip, '10,000')));
      answer(g, [1], player: 0);
      expect(g.state.obj(a).damage, 4, reason: 'no Robot');
      g.addCard('Baymax - Armored Companion', 0, Place.play);
      g.state.obj(chip).exerted = false;
      g.apply(ActivateMove(0, chip, ability(g, chip, '10,000')));
      answer(g, [1], player: 0);
      answer(g, [a], player: 0);
      expect(g.state.obj(a).damage, 1);
    });

    test('Baloo - Carefree Bear: choose one, each player draws or each discards', () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.apply(PlayMove(0, g.addCard('Baloo - Carefree Bear', 0, Place.hand)));
      answer(g, [0], player: 0);
      expect(g.state.player(0).hand, hasLength(1));
      expect(g.state.player(1).hand, hasLength(1));
    });

    test("Elsa - Ice Maker: exert chosen character; with Anna in play it can't ready next turn", () {
      final g = emptyGame();
      final elsa = g.addCard('Elsa - Ice Maker', 0, Place.play);
      g.addCard('Anna - Heir to Arendelle', 0, Place.play);
      final foe = g.addCard(vanilla, 1, Place.play);
      g.apply(QuestMove(0, elsa));
      answer(g, [1], player: 0);
      answer(g, [foe], player: 0);
      expect(g.state.obj(foe).exerted, isTrue);
      g.apply(EndTurnMove(0));
      expect(g.state.obj(foe).exerted, isTrue);
    });
  });

  group('other cards the same templates now read', () {
    test('Mulan - Imperial General: "This character can challenge ready characters" granted in quotes', () {
      final g = emptyGame();
      final mulan = g.addCard('Mulan - Imperial General', 0, Place.play);
      final abu = g.addCard(vanilla, 0, Place.play);
      final ready = g.addCard(vanilla2, 1, Place.play);
      final exerted = g.addCard(vanilla2, 1, Place.play, exerted: true);
      expect(g.whyNot(ChallengeMove(0, abu, ready)), isNotNull);
      g.apply(ChallengeMove(0, mulan, exerted));
      expect(g.whyNot(ChallengeMove(0, abu, ready)), isNull);
    });

    test("Touch the Sky: draw cards equal to the {l} of the location the character moved to", () {
      final g = emptyGame();
      g.addInk(0, 2);
      final abu = g.addCard(vanilla, 0, Place.play);
      final room = g.addCard("Andy's Room - Home Base", 0, Place.play); // 1 lore
      g.apply(PlayMove(0, g.addCard('Touch the Sky', 0, Place.hand)));
      expect(g.state.obj(abu).at, room);
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Morgana Macawber: 1 damage from each other character moves to the chosen one', () {
      final g = emptyGame();
      g.addInk(0, 6);
      final foe = g.addCard('Goliath - Clan Leader', 1, Place.play);
      final a = g.addCard(vanilla2, 0, Place.play, damage: 2);
      final b = g.addCard(vanilla2, 1, Place.play, damage: 1);
      g.apply(PlayMove(0, g.addCard('Morgana Macawber - Reformed Spellcaster', 0, Place.hand)));
      answer(g, [1], player: 0);
      answer(g, [foe], player: 0);
      expect(g.state.obj(foe).damage, 2);
      expect(g.state.obj(a).damage, 1);
      expect(g.state.obj(b).damage, 0);
    });

    test("Moana - Born Leader: the others here are readied and can't quest this turn", () {
      final g = emptyGame();
      final loc = g.addCard("Carl's House - Flying High", 0, Place.play);
      final moana = g.addCard('Moana - Born Leader', 0, Place.play);
      final other = g.addCard(vanilla, 0, Place.play, exerted: true);
      final away = g.addCard(vanilla, 0, Place.play, exerted: true);
      g.state.obj(moana).at = loc;
      g.state.obj(other).at = loc;
      g.apply(QuestMove(0, moana));
      expect(g.state.obj(other).exerted, isFalse);
      expect(g.whyNot(QuestMove(0, other)), isNotNull);
      expect(g.state.obj(away).exerted, isTrue);
    });

    test('Roller Bob: Rush only if both character cards go from the discard to the deck', () {
      final g = emptyGame();
      g.addInk(0, 3);
      g.addCard(vanilla, 0, Place.discard);
      final bob = g.addCard("Roller Bob - Sid's Toy", 0, Place.hand);
      g.apply(PlayMove(0, bob));
      answer(g, [1], player: 0);
      expect(g.chars(bob).has(Kw.rush), isFalse);
      expect(g.state.player(0).discard, hasLength(1));
    });
  });
}
