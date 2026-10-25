import 'dart:io';

import 'package:lorcana/lorcana.dart';
import 'package:tcg_core/tcg_core.dart' show SeededRng;
import 'package:test/test.dart';

import 'helpers.dart';

/// Wave 2, slice 4 (Scrooge … Zipper): each card's new template, played out.

/// Answers every remaining decision with the default answer.
void drain(Game g) {
  for (var i = 0; i < 60 && g.pending != null; i++) {
    final d = g.pending!.decision;
    g.apply(AnswerMove(d.player, g.defaultAnswer(d)));
  }
}

/// Puts a new [name] card facedown under [host] (as Boost would, CR 8.4.2).
CardId under(Game g, CardId host, String name) {
  final o = g.state.obj(host);
  final id = g.addCard(name, o.owner, Place.deck);
  final u = g.state.obj(id);
  g.state.player(o.owner).deck.remove(id);
  u.zone = Place.play;
  u.faceDown = true;
  o.under.insert(0, id);
  return id;
}

/// The first ability of [card] of type [T] in play, by index.
int abilityIndex<T>(Game g, CardId card) => g.abilitiesOf(card).indexWhere((a) => a is T);

const knight = 'Sir Kay, Unruly Knight'; // 2 cost, 2/2, Knight
const big = 'Goofy - Knight for a Day'; // 9 cost, 10/10, Knight
const dragon = "Mushu - Braggin' Dragon";

void main() {
  test('every slice-4 card is fully read', () {
    final names = File('test/fixtures/wave2_s4_cards.txt').readAsLinesSync().where((l) => l.trim().isNotEmpty);
    final bad = [
      for (final n in names)
        if (!LorcanaParser.parse(db[n]!).supported) '$n: ${LorcanaParser.parse(db[n]!).unsupported}',
    ];
    expect(bad, isEmpty);
    expect(db['Swing Into Action']!.text, contains('gains Rush'), reason: 'corrected in data/lorcana-overrides.json');
    expect(db['The Boss Is On A Roll']!.text, contains('on the top or the bottom'));
  });

  group('Cards under others (CR 8.4)', () {
    test('Scrooge - Ghostly Ebenezer: +1 {s} and +1 {w} for each card under him', () {
      final g = emptyGame();
      final s = g.addCard('Scrooge McDuck - Ghostly Ebenezer', 0, Place.play);
      under(g, s, vanilla);
      under(g, s, vanilla);
      expect(g.chars(s).strength, 5);
      expect(g.chars(s).willpower, 5);
      final h = g.addCard("Scrooge's Counting House - Ebenezer's Office", 0, Place.play);
      under(g, h, vanilla);
      expect(g.chars(h).willpower, 5);
      expect(g.chars(h).lore, 2);
    });

    test('Scrooge - On the Right Track: only a character with a card under them can be chosen', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final a = g.addCard(vanilla, 0, Place.play);
      g.addCard(vanilla2, 0, Place.play);
      under(g, a, vanilla);
      g.apply(PlayMove(0, g.addCard('Scrooge McDuck - On the Right Track', 0, Place.hand)));
      expect(g.pending, isNull, reason: 'one possible choice');
      expect(g.chars(a).lore, 3);
    });

    test('Scrooge - Reformed Ebenezer: a card under each other character, and they gain Ward', () {
      final g = emptyGame();
      g.addInk(0, 6);
      final a = g.addCard(vanilla, 0, Place.play);
      final b = g.addCard(vanilla2, 0, Place.play);
      final s = g.addCard('Scrooge McDuck - Reformed Ebenezer', 0, Place.hand);
      g.apply(PlayMove(0, s));
      answer(g, [1], player: 0);
      expect(g.state.obj(a).under, hasLength(1));
      expect(g.state.obj(b).under, hasLength(1));
      expect(g.state.obj(s).under, isEmpty);
      expect(g.chars(a).has(Kw.ward), isTrue);
      g.apply(EndTurnMove(0));
      expect(g.chars(a).has(Kw.ward), isTrue, reason: 'until the start of your next turn');
      g.apply(EndTurnMove(1));
      expect(g.chars(a).has(Kw.ward), isFalse);
    });

    test('Visiting Christmas Past: cards from under yours into the inkwell, exerted', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final a = g.addCard(vanilla, 0, Place.play);
      final u1 = under(g, a, vanilla);
      final u2 = under(g, a, vanilla2);
      g.apply(PlayMove(0, g.addCard('Visiting Christmas Past', 0, Place.hand)));
      answer(g, [u1, u2], player: 0);
      expect(g.state.obj(a).under, isEmpty);
      expect(g.state.obj(u1).zone, Place.inkwell);
      expect(g.state.obj(u2).exerted, isTrue);
      expect(g.state.player(0).inkwell, hasLength(5));
    });

    test('Willie the Giant: can quest only after a card was put under him this turn (Boost)', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final w = g.addCard('Willie the Giant - Ghost of Christmas Present', 0, Place.play);
      expect(g.whyNot(QuestMove(0, w)), isNotNull);
      g.apply(ActivateMove(0, w, abilityIndex<KeywordAbility>(g, w)));
      expect(g.whyNot(QuestMove(0, w)), isNull);
    });

    test('Sulley & Boo: when banished, may play the character cards that were under them (CR 6.7.7)', () {
      final g = emptyGame(active: 1);
      final sb = g.addCard('Sulley & Boo - Scare Buddies', 0, Place.play, exerted: true);
      final c = under(g, sb, vanilla);
      final x = under(g, sb, 'Swing Into Action');
      g.apply(ChallengeMove(1, g.addCard(big, 1, Place.play), sb));
      expect(g.state.obj(sb).zone, Place.discard);
      answer(g, [1], player: 0);
      answer(g, [c], player: 0);
      expect(g.state.obj(c).zone, Place.play);
      expect(g.state.obj(x).zone, Place.discard);
    });

    test('Time to Go!: draw 3 instead if the banished character had a card under them', () {
      for (final withCard in [false, true]) {
        final g = emptyGame();
        g.addInk(0, 3);
        final a = g.addCard(vanilla, 0, Place.play);
        if (withCard) under(g, a, vanilla2);
        final hand = g.state.player(0).hand.length;
        g.apply(PlayMove(0, g.addCard('Time to Go!', 0, Place.hand)));
        expect(g.state.obj(a).zone, Place.discard);
        expect(g.state.player(0).hand.length, hand + (withCard ? 3 : 2));
      }
    });

    test('The Black Cauldron: a character card under it faceup, then played from under it (CR 6.1.12)', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final pot = g.addCard('The Black Cauldron', 0, Place.play);
      final c = g.addCard(vanilla, 0, Place.discard);
      g.apply(ActivateMove(0, pot, 0));
      expect(g.state.obj(pot).under, [c]);
      expect(g.state.obj(c).faceDown, isFalse);
      expect(g.legalMoves().whereType<PlayMove>().where((m) => m.card == c), isEmpty, reason: 'not yet allowed');
      g.state.obj(pot).exerted = false;
      g.apply(ActivateMove(0, pot, 1));
      expect(g.legalMoves().whereType<PlayMove>().where((m) => m.card == c), isNotEmpty);
      expect(g.playEnabler(c), pot);
      g.apply(PlayMove(0, c));
      expect(g.state.player(0).play, contains(c));
      expect(g.state.obj(pot).under, isEmpty);
      expect(g.inkReady(0), 0);
    });
  });

  group('Alternate costs and costs (CR 1.5.5, 4.3.2)', () {
    test('Scrooge - Resourceful Miser: exert 4 items of yours instead of paying ink', () {
      final g = emptyGame();
      final items = [for (var i = 0; i < 4; i++) g.addCard('Amber Chromicon', 0, Place.play)];
      final s = g.addCard('Scrooge McDuck - Resourceful Miser', 0, Place.hand);
      expect(g.whyNot(PlayMove(0, s)), isNull);
      g.apply(PlayMove(0, s));
      drain(g);
      expect(g.state.obj(s).zone, Place.play);
      expect(items.every((i) => g.state.obj(i).exerted), isTrue);
      // With the ink there too, the player chooses.
      final g2 = emptyGame();
      g2.addInk(0, 4);
      for (var i = 0; i < 4; i++) {
        g2.addCard('Amber Chromicon', 0, Place.play);
      }
      g2.apply(PlayMove(0, g2.addCard('Scrooge McDuck - Resourceful Miser', 0, Place.hand)));
      expect(g2.pending?.decision.kind, DecisionKind.yesNo);
      answer(g2, [0], player: 0);
      drain(g2);
      expect(g2.inkReady(0), 0, reason: 'paid ink');
      final g3 = emptyGame();
      for (var i = 0; i < 3; i++) {
        g3.addCard('Amber Chromicon', 0, Place.play);
      }
      expect(g3.whyNot(PlayMove(0, g3.addCard('Scrooge McDuck - Resourceful Miser', 0, Place.hand))), isNotNull);
    });

    test('Seeking the Half Crown: 1 less per Sorcerer, then draw 2 (CR 4.3.6)', () {
      final g = emptyGame();
      g.addInk(0, 3);
      g.addCard('Elsa - Queen Regent', 0, Place.play);
      g.addCard('Madam Mim - Up to No Good', 0, Place.play);
      final a = g.addCard('Seeking the Half Crown', 0, Place.hand);
      expect(g.playCost(0, a), 3);
      final hand = g.state.player(0).hand.length;
      g.apply(PlayMove(0, a));
      expect(g.state.player(0).hand.length, hand - 1 + 2);
    });

    test('Shere Khan - Fierce and Furious: 1 {i} and 1 damage to himself to ready him', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final k = g.addCard('Shere Khan - Fierce and Furious', 0, Place.play, exerted: true);
      g.apply(ActivateMove(0, k, abilityIndex<Activated>(g, k)));
      expect(g.state.obj(k).exerted, isFalse);
      expect(g.state.obj(k).damage, 1);
      expect(g.whyNot(QuestMove(0, k)), isNotNull);
    });

    test('The Queen - Disguised Peddler: gain lore equal to the discarded character\'s {l}', () {
      final g = emptyGame();
      final q = g.addCard('The Queen - Disguised Peddler', 0, Place.play);
      g.addCard('Swing Into Action', 0, Place.hand);
      final c = g.addCard(vanilla, 0, Place.hand); // 2 lore
      g.apply(ActivateMove(0, q, 0));
      expect(g.state.obj(c).zone, Place.discard, reason: 'the only character card');
      expect(g.state.player(0).lore, 2);
    });

    test('The Wardrobe: discard an item card to draw 2; no item, no ability', () {
      final g = emptyGame();
      final w = g.addCard('The Wardrobe - Perceptive Friend', 0, Place.play);
      g.addCard(vanilla, 0, Place.hand);
      expect(g.whyNot(ActivateMove(0, w, 0)), isNotNull);
      g.addCard('Amber Chromicon', 0, Place.hand);
      g.apply(ActivateMove(0, w, 0));
      expect(g.state.player(0).hand, hasLength(3));
    });

    test('Yokai - Intellectual Schemer: Shift costs 1 less', () {
      final g = emptyGame();
      g.addInk(0, 3);
      g.addCard('Yokai - Intellectual Schemer', 0, Place.play);
      final onto = g.addCard('Yokai - Professor Callaghan', 0, Place.play);
      final s = g.addCard('Yokai - Scientific Supervillain', 0, Place.hand); // Shift 6
      expect(g.whyNot(PlayMove(0, s, mode: PlayMode.shift, onto: onto)), isNotNull);
      g.addInk(0, 2);
      expect(g.whyNot(PlayMove(0, s, mode: PlayMode.shift, onto: onto)), isNull);
    });

    test('Yokai - Scientific Supervillain: Microbots for free; draw for each opposing character with 0 {s}', () {
      final g = emptyGame();
      final y = g.addCard('Yokai - Scientific Supervillain', 0, Place.play);
      final m = g.addCard('Microbots', 0, Place.hand);
      expect(g.playCost(0, m), 0);
      g.addCard('Little John - Camp Cook', 1, Place.play);
      g.addCard('Nala - Mischievous Cub', 1, Place.play);
      g.addCard(vanilla, 1, Place.play);
      final hand = g.state.player(0).hand.length;
      g.apply(QuestMove(0, y));
      expect(g.state.player(0).hand.length, hand + 2);
    });

    test('Zero to Hero: the next character costs 1 less per character you have (CR 4.3.6)', () {
      final g = emptyGame();
      g.addInk(0, 2);
      g.addCard(vanilla, 0, Place.play);
      g.addCard(vanilla2, 0, Place.play);
      g.apply(PlayMove(0, g.addCard('Zero to Hero', 0, Place.hand)));
      final c = g.addCard('Atitaya - Fang General', 0, Place.hand);
      expect(g.playCost(0, c), 5);
    });

    test('Yokai - Enigmatic Inventor: return an item to pay 2 less for the next item', () {
      final g = emptyGame();
      final y = g.addCard('Yokai - Enigmatic Inventor', 0, Place.play);
      final it = g.addCard('Amber Chromicon', 0, Place.play);
      g.apply(QuestMove(0, y));
      answer(g, [1], player: 0);
      expect(g.state.obj(it).zone, Place.hand);
      expect(g.playCost(0, g.addCard('The Sword Released', 0, Place.hand)), 1);
    });
  });

  group('Locations (CR 4.7, 5.6)', () {
    test("Seven Dwarfs' Mine: the first move here during your turn deals 1, 2 if a Knight", () {
      final g = emptyGame();
      g.addInk(0, 4);
      final mine = g.addCard("Seven Dwarfs' Mine - Secure Fortress", 0, Place.play);
      final k = g.addCard(knight, 0, Place.play);
      final o = g.addCard(big, 1, Place.play);
      g.apply(MoveMove(0, k, mine));
      answer(g, [1], player: 0);
      answer(g, [o], player: 0);
      expect(g.state.obj(o).damage, 2);
      g.apply(MoveMove(0, g.addCard(vanilla, 0, Place.play), mine));
      expect(g.pending, isNull, reason: 'only the first time (CR 6.1.13.2)');
    });

    test('Sherwood Forest: Robin Hood moves free; characters here gain Ward and an ability', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final f = g.addCard('Sherwood Forest - Outlaw Hideaway', 0, Place.play);
      final r = g.addCard('Robin Hood - Beloved Outlaw', 0, Place.play);
      expect(g.whyNot(MoveMove(0, r, f)), isNull, reason: 'no ink needed');
      g.apply(MoveMove(0, r, f));
      expect(g.inkReady(0), 1);
      expect(g.chars(r).has(Kw.ward), isTrue);
      final i = g.abilitiesOf(r).length - 1;
      expect(g.abilitiesOf(r)[i], isA<Activated>());
      final o = g.addCard(big, 1, Place.play, damage: 1);
      g.addCard(vanilla, 1, Place.play);
      g.apply(ActivateMove(0, r, i));
      expect(g.state.obj(o).damage, 3, reason: 'the only damaged character');
      expect(g.whyNot(MoveMove(0, g.addCard(vanilla, 0, Place.play), f)), isNotNull, reason: 'others pay 2');
    });

    test('The Sorcerer\'s Tower: Magic Brooms move here free; characters here get +1 {l}', () {
      final g = emptyGame();
      final t = g.addCard("The Sorcerer's Tower - Wondrous Workspace", 0, Place.play);
      final b = g.addCard('Magic Broom - Aerial Cleaner', 0, Place.play);
      final lore = g.chars(b).lore;
      g.apply(MoveMove(0, b, t));
      expect(g.chars(b).lore, lore + 1);
    });

    test('The Great Illuminary: characters here gain "{e} - Draw a card"', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final l = g.addCard('The Great Illuminary - Abandoned Laboratory', 0, Place.play);
      final c = g.addCard(vanilla, 0, Place.play);
      expect(g.abilitiesOf(c), isEmpty);
      g.apply(MoveMove(0, c, l));
      expect(g.legalMoves().whereType<ActivateMove>().where((m) => m.card == c), hasLength(1));
      final hand = g.state.player(0).hand.length;
      g.apply(ActivateMove(0, c, 0));
      expect(g.state.player(0).hand.length, hand + 1);
      expect(g.state.obj(c).exerted, isTrue);
    });

    test('Snuggly Duckling: 1 lore for a 3+ {s} challenger here, 3 instead at 6+', () {
      for (final (name, lore) in [(vanilla, 1), (big, 3)]) {
        final g = emptyGame();
        final pub = g.addCard('Snuggly Duckling - Disreputable Pub', 0, Place.play);
        final c = g.addCard(name, 0, Place.play);
        g.state.obj(c).at = pub;
        g.apply(ChallengeMove(0, c, g.addCard(vanilla2, 1, Place.play, exerted: true)));
        expect(g.state.player(0).lore, lore, reason: name);
      }
    });

    test('Sugar Rush Speedway - Finish Line: only a character moved here from another location (CR 4.7.2)', () {
      final g = emptyGame();
      g.addInk(0, 12);
      final fin = g.addCard('Sugar Rush Speedway - Finish Line', 0, Place.play);
      final start = g.addCard('Sugar Rush Speedway - Starting Line', 0, Place.play);
      final a = g.addCard(vanilla, 0, Place.play);
      g.apply(MoveMove(0, a, fin));
      expect(g.pending, isNull);
      final b = g.addCard(vanilla2, 0, Place.play);
      g.apply(MoveMove(0, b, start));
      g.apply(MoveMove(0, b, fin));
      answer(g, [1], player: 0);
      expect(g.state.obj(fin).zone, Place.discard);
      expect(g.state.player(0).lore, 3);
    });

    test('Sugar Rush Speedway - Starting Line: once per turn, exert and damage one here to move it', () {
      final g = emptyGame();
      final start = g.addCard('Sugar Rush Speedway - Starting Line', 0, Place.play);
      final other = g.addCard('Training Grounds - Impossible Pillar', 0, Place.play);
      final c = g.addCard(vanilla2, 0, Place.play);
      g.state.obj(c).at = start;
      g.apply(ActivateMove(0, start, 0));
      expect(g.state.obj(c).exerted, isTrue);
      expect(g.state.obj(c).damage, 1);
      expect(g.state.obj(c).at, other);
      expect(g.whyNot(ActivateMove(0, start, 0)), 'Once per turn');
    });

    test('The Bitterwood: once during your turn, a 5+ {s} character moved here draws a card', () {
      final g = emptyGame();
      g.addInk(0, 6);
      final w = g.addCard('The Bitterwood - Underground Forest', 0, Place.play);
      g.apply(MoveMove(0, g.addCard(vanilla, 0, Place.play), w));
      expect(g.pending, isNull, reason: '3 strength');
      g.apply(MoveMove(0, g.addCard(big, 0, Place.play), w));
      answer(g, [1], player: 0);
      g.apply(MoveMove(0, g.addCard(big, 0, Place.play), w));
      expect(g.pending, isNull, reason: 'once during your turn');
    });

    test('Vine Entrance: the first time a Floodborn character moves here each turn', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final v = g.addCard('Vine Entrance - Ominous Passageway', 0, Place.play);
      g.apply(MoveMove(0, g.addCard(vanilla, 0, Place.play), v));
      expect(g.pending, isNull);
      g.apply(MoveMove(0, g.addCard('Li Shang - Valiant Leader', 0, Place.play), v));
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
    });

    test('The Frozen Vine: back to the hand if an exerted character was here as it was banished', () {
      for (final exerted in [true, false]) {
        final g = emptyGame(active: 1);
        final v = g.addCard('The Frozen Vine - Monstrous Plant', 0, Place.play);
        final c = g.addCard(vanilla, 0, Place.play, exerted: exerted);
        g.state.obj(c).at = v;
        g.apply(ChallengeMove(1, g.addCard(big, 1, Place.play), v));
        expect(g.state.obj(v).zone, exerted ? Place.hand : Place.discard);
      }
    });

    test('Treasure Mountain: damage equal to the characters here; White Agony Plains: +1 {l} each', () {
      final g = emptyGame(active: 1);
      final m = g.addCard('Treasure Mountain - Azurite Sea Island', 0, Place.play);
      final p = g.addCard('White Agony Plains - Golden Lagoon', 0, Place.play);
      for (var i = 0; i < 2; i++) {
        g.state.obj(g.addCard(vanilla2, 0, Place.play)).at = m;
      }
      g.state.obj(g.addCard(vanilla2, 0, Place.play)).at = p;
      expect(g.chars(p).lore, 1);
      final o = g.addCard(big, 1, Place.play);
      g.apply(EndTurnMove(1));
      answer(g, [o], player: 0);
      expect(g.state.obj(o).damage, 2);
    });

    test('The Queen\'s Castle: at the start of your turn, draw up to one card per character here', () {
      final g = emptyGame(active: 1);
      final c = g.addCard("The Queen's Castle - Mirror Chamber", 0, Place.play);
      for (var i = 0; i < 2; i++) {
        g.state.obj(g.addCard(vanilla2, 0, Place.play)).at = c;
      }
      final hand = g.state.player(0).hand.length;
      g.apply(EndTurnMove(1));
      expect(g.pending?.decision.labels, ['Draw 2', 'Draw 1', 'Draw 0']);
      answer(g, [1], player: 0);
      expect(g.state.player(0).hand.length, hand + 1 + 1, reason: 'one from the ability, one from the Draw step');
    });

    test('Training Grounds: chosen character here gets +1 {s}', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final t = g.addCard('Training Grounds - Impossible Pillar', 0, Place.play);
      final c = g.addCard(vanilla, 0, Place.play);
      g.addCard(vanilla2, 0, Place.play);
      g.state.obj(c).at = t;
      g.apply(ActivateMove(0, t, 0));
      expect(g.chars(c).strength, 4);
    });

    test('Winter Camp: questing here removes 2 damage, 4 from a Hero', () {
      final g = emptyGame();
      final camp = g.addCard('Winter Camp - Medical Tent', 0, Place.play);
      final hero = g.addCard('Tod - Knows All the Tricks', 0, Place.play, damage: 5);
      final plain = g.addCard('Chef Louis - In Over His Head', 0, Place.play, damage: 5);
      g.state.obj(hero).at = camp;
      g.state.obj(plain).at = camp;
      g.apply(QuestMove(0, hero));
      g.apply(QuestMove(0, plain));
      expect(g.state.obj(hero).damage, 1);
      expect(g.state.obj(plain).damage, 3);
    });

    test('Touch the Sky: move to a location, draw cards equal to its {l}', () {
      final g = emptyGame();
      g.addInk(0, 2);
      g.addCard("The Queen's Castle - Mirror Chamber", 0, Place.play); // 2 lore
      g.addCard(vanilla, 0, Place.play);
      final hand = g.state.player(0).hand.length;
      g.apply(PlayMove(0, g.addCard('Touch the Sky', 0, Place.hand)));
      expect(g.state.player(0).hand.length, hand + 2);
    });

    test('Tuk Tuk: he and another move together; the other gets +2 {s}', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final loc = g.addCard('Training Grounds - Impossible Pillar', 0, Place.play);
      final o = g.addCard(vanilla, 0, Place.play);
      final t = g.addCard('Tuk Tuk - Lively Partner', 0, Place.hand);
      g.apply(PlayMove(0, t));
      answer(g, [1], player: 0);
      expect(g.state.obj(t).at, loc);
      expect(g.state.obj(o).at, loc);
      expect(g.chars(o).strength, 5);
    });

    test('Shenzi: while at a location, challenging draws a card', () {
      final g = emptyGame();
      final loc = g.addCard('Training Grounds - Impossible Pillar', 0, Place.play);
      final s = g.addCard('Shenzi - Hyena Pack Leader', 0, Place.play);
      g.apply(ChallengeMove(0, s, g.addCard(vanilla2, 1, Place.play, exerted: true)));
      expect(g.pending, isNull, reason: 'not at a location');
      final s2 = g.addCard('Shenzi - Hyena Pack Leader', 0, Place.play);
      g.state.obj(s2).at = loc;
      expect(g.chars(s2).strength, 3);
      g.apply(ChallengeMove(0, s2, g.addCard(vanilla2, 1, Place.play, exerted: true)));
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
    });
  });

  group('Statics (CR 6.4)', () {
    test('Snow White - Fair-hearted: Resist +1 for each other Knight (CR 8.8)', () {
      final g = emptyGame(active: 1);
      final s = g.addCard('Snow White - Fair-hearted', 0, Place.play, exerted: true);
      g.addCard(knight, 0, Place.play);
      g.addCard(knight, 0, Place.play);
      expect(g.chars(s).n(Kw.resist), 2);
      g.apply(ChallengeMove(1, g.addCard(vanilla, 1, Place.play), s));
      expect(g.state.obj(s).damage, 1);
    });

    test('Sulley - Protective Monster: exert the inkwell to gain Rush', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final s = g.addCard('Sulley - Protective Monster', 0, Place.hand);
      g.apply(PlayMove(0, s));
      answer(g, [1], player: 0);
      expect(g.chars(s).has(Kw.rush), isTrue);
      g.addInk(0, 1);
      expect(g.chars(s).has(Kw.rush), isFalse);
    });

    test('Tiana - Celebrating Princess: exerted with an empty hand, opponents can\'t play actions (CR 1.2.2)', () {
      final g = emptyGame(active: 1);
      g.addInk(1, 5);
      g.addCard('Tiana - Celebrating Princess', 0, Place.play, exerted: true);
      final act = g.addCard('Swing Into Action', 1, Place.hand);
      expect(g.whyNot(PlayMove(1, act)), isNotNull);
      g.addCard(vanilla, 0, Place.hand);
      expect(g.whyNot(PlayMove(1, act)), isNull);
    });

    test('The Thunderquack: opposing characters are Villains (CR 5.2.7)', () {
      final g = emptyGame();
      g.addCard('The Thunderquack', 0, Place.play);
      final o = g.addCard(vanilla, 1, Place.play);
      final mine = g.addCard(vanilla, 0, Place.play);
      expect(g.matches(const Filter(classes: ['Villain']), o, controller: 0), isTrue);
      expect(g.matches(const Filter(classes: ['Villain']), mine, controller: 0), isFalse);
    });

    test('The Horned King - Merciless Master: while exerted, characters from the discard, entering exerted', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final k = g.addCard('The Horned King - Merciless Master', 0, Place.play);
      final c = g.addCard(vanilla, 0, Place.discard);
      expect(g.whyNot(PlayMove(0, c)), isNotNull);
      g.state.obj(k).exerted = true;
      expect(g.legalMoves().whereType<PlayMove>().where((m) => m.card == c), hasLength(1));
      g.apply(PlayMove(0, c));
      expect(g.state.obj(c).zone, Place.play);
      expect(g.state.obj(c).exerted, isTrue);
    });

    test('The Horned King - Triumphant Ghoul: +2 {l} in your turn once a card left a discard', () {
      final g = emptyGame();
      final k = g.addCard('The Horned King - Triumphant Ghoul', 0, Place.play);
      final c = g.addCard(vanilla, 1, Place.discard);
      expect(g.chars(k).lore, 1);
      g.moveToForTest(c, Place.hand);
      expect(g.chars(k).lore, 3);
    });

    test('The Queen - Devious Disguise: opponents gain 2 if you draw; +2 {l} while behind', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final q = g.addCard('The Queen - Devious Disguise', 0, Place.hand);
      g.apply(PlayMove(0, q));
      answer(g, [1], player: 0);
      expect(g.state.player(1).lore, 2);
      expect(g.chars(q).lore, 3);
    });

    test('Winnie the Pooh & Piglet: +1 {l} per ink type among your characters', () {
      final g = emptyGame();
      final w = g.addCard('Winnie the Pooh & Piglet - Hunny Mages', 0, Place.play); // amethyst, sapphire
      g.addCard(vanilla, 0, Place.play); // ruby
      g.addCard(vanilla2, 0, Place.play); // ruby
      expect(g.chars(w).lore, 3);
    });

    test('Vision Slab: lore for a damaged opposing character; damage can\'t be removed (CR 1.9.2.3)', () {
      final g = emptyGame(active: 1);
      g.addCard('Vision Slab', 0, Place.play);
      final o = g.addCard(vanilla2, 1, Place.play, damage: 1);
      g.apply(EndTurnMove(1));
      expect(g.state.player(0).lore, 1);
      expect(g.state.obj(o).damage, 1);
      final mine = g.addCard(vanilla2, 0, Place.play, damage: 2);
      g.apply(ActivateMove(0, g.addCard('Cleansing Rainwater', 0, Place.play), 0));
      expect(g.state.obj(mine).damage, 2);
    });

    test('The Glass Slipper: only 2 copies in a deck (CR 1.10.1.1); search for a Princess', () {
      expect(validateDeck(db, [...List.filled(3, 'The Glass Slipper'), ...List.filled(57, vanilla)]).any((p) => p.contains('At most 2')), isTrue);
      final g = emptyGame();
      final s = g.addCard('The Glass Slipper', 0, Place.play);
      g.addCard('Aladdin - Fearless Navigator', 0, Place.play); // Prince
      final p = g.addCard('Aurora - Regal Princess', 0, Place.deck);
      g.apply(ActivateMove(0, s, abilityIndex<Activated>(g, s)));
      expect(g.state.obj(p).zone, Place.hand);
      expect(g.state.obj(s).zone, Place.discard);
    });
  });

  group('Triggers (CR 6.2)', () {
    test('Sisu - Uniting Dragon: reveal and keep Dragons until one isn\'t', () {
      final g = emptyGame();
      final s = g.addCard('Sisu - Uniting Dragon', 0, Place.play);
      final last = g.addCard(vanilla, 0, Place.deck);
      final d1 = g.addCard(dragon, 0, Place.deck);
      final d2 = g.addCard('Sisu - Wise Friend', 0, Place.deck);
      g.apply(QuestMove(0, s));
      expect(g.state.obj(d1).zone, Place.hand);
      expect(g.state.obj(d2).zone, Place.hand);
      expect(g.pending?.decision.labels, ['Top', 'Bottom']);
      answer(g, [1], player: 0);
      expect(g.state.player(0).deck.last, last);
    });

    test('Sneezy: this character or another Seven Dwarfs character played', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final o = g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Sneezy - Very Allergic', 0, Place.hand)));
      answer(g, [1], player: 0);
      answer(g, [o], player: 0);
      expect(g.chars(o).strength, 2);
      g.apply(PlayMove(0, g.addCard('Happy - Joyful Adventurer', 0, Place.hand)));
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
    });

    test('Source of the Vine: gain 1 lore unless the quester\'s player pays 1 {i} (CR 6.1.16)', () {
      for (final pays in [true, false]) {
        final g = emptyGame(active: 1);
        g.addInk(1, 1);
        g.addCard('Source of the Vine', 0, Place.play);
        g.apply(QuestMove(1, g.addCard(vanilla2, 1, Place.play)));
        expect(g.pending?.decision.player, 1);
        answer(g, [pays ? 1 : 0], player: 1);
        expect(g.state.player(0).lore, pays ? 0 : 1);
        expect(g.inkReady(1), pays ? 0 : 1);
      }
      // Without the ink, no choice.
      final g = emptyGame(active: 1);
      g.addCard('Source of the Vine', 0, Place.play);
      g.apply(QuestMove(1, g.addCard(vanilla2, 1, Place.play)));
      expect(g.state.player(0).lore, 1);
    });

    test('Tiana - Restaurant Owner: the challenger gets -3 {s} unless its player pays 3 {i}', () {
      final g = emptyGame(active: 1);
      g.addCard('Tiana - Restaurant Owner', 0, Place.play, exerted: true);
      final mine = g.addCard('Chef Louis - In Over His Head', 0, Place.play, exerted: true); // 6/8
      final a = g.addCard(vanilla, 1, Place.play); // 3 strength
      g.addInk(1, 3);
      g.apply(ChallengeMove(1, a, mine));
      answer(g, [0], player: 1);
      expect(g.state.obj(mine).damage, 0);
    });

    test('Stitch - Experiment 626: opponents ink their top card; from the discard, discard an inkable card to play him', () {
      final g = emptyGame();
      g.addInk(0, 3);
      g.apply(PlayMove(0, g.addCard('Stitch - Experiment 626', 0, Place.hand)));
      expect(g.state.player(1).inkwell, hasLength(1));
      expect(g.state.obj(g.state.player(1).inkwell.first).exerted, isTrue);
      final g2 = emptyGame(active: 1);
      final st = g2.addCard('Stitch - Experiment 626', 0, Place.discard);
      final ink = g2.addCard(vanilla, 0, Place.hand);
      g2.apply(EndTurnMove(1));
      answer(g2, [1], player: 0);
      expect(g2.state.obj(ink).zone, Place.discard);
      expect(g2.state.obj(st).zone, Place.play);
      expect(g2.state.obj(st).exerted, isTrue);
    });

    test('Tod - Knows All the Tricks: ready him when chosen for an action, twice a turn', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final t = g.addCard('Tod - Knows All the Tricks', 0, Place.play);
      g.addCard(vanilla, 0, Place.play);
      for (var i = 0; i < 3; i++) {
        g.state.obj(t).exerted = true;
        g.apply(PlayMove(0, g.addCard('Swing Into Action', 0, Place.hand)));
        answer(g, [t], player: 0);
        if (i < 2) {
          answer(g, [1], player: 0);
          expect(g.state.obj(t).exerted, isFalse);
        } else {
          drain(g);
          expect(g.state.obj(t).exerted, isTrue, reason: 'only twice');
        }
      }
    });

    test('Ursula - Deceiver of All: replay the song she sang, then it goes to the bottom of the deck', () {
      final g = emptyGame();
      final u = g.addCard('Ursula - Deceiver of All', 0, Place.play);
      final song = g.addCard('Zero to Hero', 0, Place.hand);
      g.apply(PlayMove(0, song, mode: PlayMode.sing, singers: [u]));
      answer(g, [1], player: 0);
      expect(g.state.player(0).deck.last, song);
      expect(g.state.player(0).actionsThisTurn, 2);
    });

    test('Ursula - Power Hungry: draw for each lore lost', () {
      final g = emptyGame();
      g.addInk(0, 7);
      g.state.player(1).lore = 1;
      final hand = g.state.player(0).hand.length;
      g.apply(PlayMove(0, g.addCard('Ursula - Power Hungry', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.player(1).lore, 0);
      expect(g.state.player(0).hand.length, hand + 1, reason: 'drew 1');
    });

    test('Ursula - Voice Stealer: play a song costing up to the exerted character\'s cost', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final o = g.addCard(vanilla, 1, Place.play); // cost 3
      final cheap = g.addCard('Zero to Hero', 0, Place.hand); // 2
      g.addCard('Second Star to the Right', 0, Place.hand); // 10
      g.apply(PlayMove(0, g.addCard('Ursula - Voice Stealer', 0, Place.hand)));
      expect(g.state.obj(o).exerted, isTrue);
      answer(g, [1], player: 0);
      expect(g.state.obj(cheap).zone, Place.discard, reason: 'the only song that qualifies, played');
    });

    test('Syndrome: return a Robot, then play it for free', () {
      final g = emptyGame();
      final s = g.addCard('Syndrome - Out for Revenge', 0, Place.play);
      final r = g.addCard('Omnidroid - V.8', 0, Place.discard);
      g.apply(QuestMove(0, s));
      answer(g, [1], player: 0);
      expect(g.state.obj(r).zone, Place.play);
    });

    test("Syndrome's Remote: when a Robot is banished, banish it to discard your hand and draw 2", () {
      final g = emptyGame(active: 1);
      g.addCard("Syndrome's Remote", 0, Place.play);
      final r = g.addCard('Omnidroid - V.8', 0, Place.play, exerted: true);
      g.addCard(vanilla, 0, Place.hand);
      g.apply(ChallengeMove(1, g.addCard(big, 1, Place.play), r));
      answer(g, [1], player: 0);
      expect(g.state.player(0).hand, hasLength(2));
      expect(g.state.player(0).discard, hasLength(3));
    });

    test('Wisdom of the Willow: this turn, questing draws', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final c = g.addCard(vanilla, 0, Place.play);
      g.apply(PlayMove(0, g.addCard('Wisdom of the Willow', 0, Place.hand)));
      g.apply(QuestMove(0, c));
      expect(g.pending?.decision.kind, DecisionKind.yesNo);
    });

    test('Wreck-It Ralph - Demolition Dude: readying him gains 1 lore per damage', () {
      final g = emptyGame(active: 1);
      g.addCard('Wreck-It Ralph - Demolition Dude', 0, Place.play, exerted: true, damage: 2);
      g.apply(EndTurnMove(1));
      expect(g.state.player(0).lore, 2);
    });

    test('Wreck-It Ralph - Raging Wrecker: banish all with {s} up to his last (CR 6.7.7)', () {
      final g = emptyGame(active: 1);
      final w = g.addCard('Wreck-It Ralph - Raging Wrecker', 0, Place.play, exerted: true);
      under(g, w, vanilla); // 4 strength
      final weak = g.addCard(vanilla, 1, Place.play); // 3
      final strong = g.addCard('Chef Louis - In Over His Head', 1, Place.play); // 6
      final mine = g.addCard(vanilla2, 0, Place.play); // 2
      g.apply(ChallengeMove(1, g.addCard(big, 1, Place.play), w));
      expect(g.state.obj(weak).zone, Place.discard);
      expect(g.state.obj(mine).zone, Place.discard);
      expect(g.state.obj(strong).zone, Place.play);
    });

    test('Zeus: + {s} equal to a chosen character\'s {s} when he challenges', () {
      final g = emptyGame();
      final z = g.addCard('Zeus - Mr. Lightning Bolts', 0, Place.play);
      final t = g.addCard(vanilla2, 1, Place.play, exerted: true);
      final b = g.addCard(big, 0, Place.play);
      g.apply(ChallengeMove(0, z, t));
      answer(g, [b], player: 0);
      expect(g.state.obj(t).zone, Place.discard);
    });

    test('Zipper: add his {w} to another chosen character\'s {s}', () {
      final g = emptyGame();
      final z = g.addCard('Zipper - Big Helper', 0, Place.play);
      final c = g.addCard(vanilla, 0, Place.play);
      g.apply(QuestMove(0, z));
      answer(g, [1], player: 0);
      expect(g.chars(c).strength, 9);
    });

    test('The Sword Released: an opponent loses 1 lore and you gain the lore lost', () {
      for (final theirs in [1, 0]) {
        final g = emptyGame(active: 1);
        g.addCard('The Sword Released', 0, Place.play);
        g.addCard(big, 0, Place.play);
        g.state.player(1).lore = theirs;
        g.apply(EndTurnMove(1));
        expect(g.state.player(0).lore, theirs);
        expect(g.state.player(1).lore, 0);
      }
    });

    test('The Queen - Conceited Ruler: discard a Princess or Queen to return a character card', () {
      final g = emptyGame(active: 1);
      g.addCard('The Queen - Conceited Ruler', 0, Place.play);
      final pr = g.addCard('Aurora - Regal Princess', 0, Place.hand);
      final back = g.addCard(vanilla, 0, Place.discard);
      g.apply(EndTurnMove(1));
      answer(g, [1], player: 0);
      expect(g.state.obj(pr).zone, Place.discard);
      answer(g, [back], player: 0);
      expect(g.state.obj(back).zone, Place.hand);
    });

    test('Widow Tweed: if the returned character is Tod, play him free; Wreck-It Ralph: 2 lore for a Princess', () {
      final g = emptyGame();
      g.addInk(0, 6);
      final tod = g.addCard('Tod - All Alone', 0, Place.discard);
      g.apply(PlayMove(0, g.addCard('Widow Tweed - Kindly Soul', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.obj(tod).zone, Place.play);
      final g2 = emptyGame();
      g2.addInk(0, 7);
      g2.addCard('Aurora - Regal Princess', 0, Place.discard);
      g2.apply(PlayMove(0, g2.addCard('Wreck-It Ralph - Admiral Underpants', 0, Place.hand)));
      expect(g2.state.player(0).lore, 2);
    });

    test('The Leviathan: banish chosen opposing characters with total {s} 10 or less', () {
      final g = emptyGame();
      g.addInk(0, 10);
      g.state.player(0).discardedThisTurn = 2;
      final a = g.addCard('Chef Louis - In Over His Head', 1, Place.play); // 6
      final b = g.addCard(vanilla, 1, Place.play); // 3
      final c = g.addCard(vanilla, 1, Place.play); // 3
      g.apply(PlayMove(0, g.addCard('The Leviathan - Guardian of Atlantis', 0, Place.hand)));
      answer(g, [1], player: 0);
      answer(g, [a], player: 0);
      answer(g, [b], player: 0);
      expect(g.pending, isNull, reason: 'the third would make 12');
      expect(g.state.obj(a).zone, Place.discard);
      expect(g.state.obj(b).zone, Place.discard);
      expect(g.state.obj(c).zone, Place.play);
    });
  });

  group('Actions and activated abilities', () {
    test('Search for Clues: the player with the most cards discards 2; a Detective gains 1 lore', () {
      final g = emptyGame();
      g.addInk(0, 4);
      g.addCard('Basil - Perceptive Investigator', 0, Place.play);
      for (var i = 0; i < 4; i++) {
        g.addCard(vanilla, 1, Place.hand);
      }
      g.apply(PlayMove(0, g.addCard('Search for Clues', 0, Place.hand)));
      final pick = g.state.player(1).hand.take(2).toList();
      answer(g, pick, player: 1);
      expect(g.state.player(1).hand, hasLength(2));
      expect(g.state.player(0).lore, 1);
    });

    test('Second Star to the Right and With a Few Good Friends: chosen player draws', () {
      final g = emptyGame();
      g.addInk(0, 16);
      g.apply(PlayMove(0, g.addCard('Second Star to the Right', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.player(1).hand, hasLength(5));
      g.addCard(vanilla, 0, Place.play); // ruby
      g.addCard(dragon, 0, Place.play); // amethyst
      g.apply(PlayMove(0, g.addCard('With a Few Good Friends', 0, Place.hand)));
      answer(g, [0], player: 0);
      expect(g.state.player(0).hand, hasLength(2));
    });

    test('Spooky Sight: every character with cost 3 or less into its player\'s inkwell, exerted', () {
      final g = emptyGame();
      g.addInk(0, 6);
      final a = g.addCard(vanilla, 0, Place.play);
      final b = g.addCard(vanilla2, 1, Place.play);
      final c = g.addCard(big, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Spooky Sight', 0, Place.hand)));
      expect(g.state.obj(a).zone, Place.inkwell);
      expect(g.state.player(1).inkwell, [b]);
      expect(g.state.obj(b).exerted, isTrue);
      expect(g.state.obj(c).zone, Place.play);
    });

    test('Sprout: discard an Alien or location card to deal 2 damage', () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.addCard(vanilla, 0, Place.hand);
      final loc = g.addCard('Training Grounds - Impossible Pillar', 0, Place.hand);
      final o = g.addCard(big, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Sprout - Experiment 509', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.obj(loc).zone, Place.discard);
      answer(g, [o], player: 0);
      expect(g.state.obj(o).damage, 2);
    });

    test('Stopped Chaos in Its Tracks: up to 2 characters with 3 {s} or less return', () {
      final g = emptyGame();
      g.addInk(0, 8);
      final a = g.addCard(vanilla, 1, Place.play);
      final b = g.addCard(vanilla2, 1, Place.play);
      g.addCard(big, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Stopped Chaos in Its Tracks', 0, Place.hand)));
      expect(g.pending!.decision.options, unorderedEquals([a, b]));
      answer(g, [a, b], player: 0);
      expect(g.state.player(1).hand, unorderedEquals([a, b]));
    });

    test('Stratos: gain lore equal to your Titans', () {
      final g = emptyGame();
      final s = g.addCard('Stratos - Tornado Titan', 0, Place.play);
      g.addCard('Arges - The Cyclops', 0, Place.play);
      g.apply(ActivateMove(0, s, abilityIndex<Activated>(g, s)));
      expect(g.state.player(0).lore, 2);
    });

    test('Sudden Scare: chosen opposing character and that player\'s top card into their inkwell', () {
      final g = emptyGame();
      g.addInk(0, 4);
      final o = g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Sudden Scare', 0, Place.hand)));
      expect(g.state.player(1).inkwell, hasLength(2));
      expect(g.state.obj(o).zone, Place.inkwell);
    });

    test('Super Relocation Program: draw 2 only for a returned Hero', () {
      for (final (name, draws) in [(vanilla2, 2), (vanilla, 0)]) {
        final g = emptyGame();
        g.addInk(0, 4);
        final c = g.addCard(name, 0, Place.play);
        final hand = g.state.player(0).hand.length;
        g.apply(PlayMove(0, g.addCard('Super Relocation Program', 0, Place.hand)));
        expect(g.state.obj(c).zone, Place.hand);
        expect(g.state.player(0).hand.length, hand + 1 + draws, reason: name);
      }
    });

    test('Super Suit: draw if you played a Hero this turn', () {
      final g = emptyGame();
      g.addInk(0, 6);
      final s = g.addCard('Super Suit', 0, Place.play);
      expect(g.state.player(0).hand, isEmpty);
      g.apply(ActivateMove(0, s, abilityIndex<Activated>(g, s)));
      expect(g.state.player(0).hand, isEmpty);
      g.state.obj(s).exerted = false;
      g.apply(PlayMove(0, g.addCard(vanilla2, 0, Place.hand)));
      g.apply(ActivateMove(0, s, abilityIndex<Activated>(g, s)));
      expect(g.state.player(0).hand, hasLength(1));
    });

    test('Swing Into Action: chosen character gains Rush (corrected text)', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final c = g.addCard(vanilla, 0, Place.play, drying: true);
      final t = g.addCard(vanilla2, 1, Place.play, exerted: true);
      expect(g.whyNot(ChallengeMove(0, c, t)), isNotNull);
      g.apply(PlayMove(0, g.addCard('Swing Into Action', 0, Place.hand)));
      answer(g, [c], player: 0);
      expect(g.whyNot(ChallengeMove(0, c, t)), isNull);
    });

    test('Sword In The Stone: +1 {s} for each damage on the chosen character', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final s = g.addCard('Sword In The Stone', 0, Place.play);
      final c = g.addCard(vanilla2, 0, Place.play, damage: 2);
      g.apply(ActivateMove(0, s, 0));
      expect(g.chars(c).strength, 4);
    });

    test('The Boss Is On A Roll: any number of the top 5 to the bottom, the rest on top; gain 1 lore', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final top = [for (var i = 0; i < 5; i++) g.addCard(vanilla, 0, Place.deck)].reversed.toList();
      g.apply(PlayMove(0, g.addCard('The Boss Is On A Roll', 0, Place.hand)));
      answer(g, [top[0], top[1]], player: 0);
      answer(g, [top[4], top[3], top[2]], player: 0);
      answer(g, [top[1], top[0]], player: 0);
      final deck = g.state.player(0).deck;
      expect(deck.take(3), [top[4], top[3], top[2]]);
      expect(deck.skip(deck.length - 2), [top[1], top[0]]);
      expect(g.state.player(0).lore, 1);
    });

    test('The Family Scattered: the opponent sends three of theirs to hand, bottom and top', () {
      final g = emptyGame();
      g.addInk(0, 8);
      final a = g.addCard(vanilla, 1, Place.play), b = g.addCard(vanilla2, 1, Place.play), c = g.addCard(big, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('The Family Scattered', 0, Place.hand)));
      answer(g, [c], player: 1); // to hand
      answer(g, [a], player: 1); // to the bottom
      expect(g.state.obj(c).zone, Place.hand);
      expect(g.state.player(1).deck.last, a);
      expect(g.state.player(1).deck.first, b);
    });

    test('The Headless Horseman: 2 damage for each action card discarded at random', () {
      final g = emptyGame();
      g.addInk(0, 8);
      for (var i = 0; i < 3; i++) {
        g.addCard('Swing Into Action', 0, Place.deck);
      }
      final o = g.addCard(big, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('The Headless Horseman - Cursed Rider', 0, Place.hand)));
      expect(g.state.player(0).hand, isEmpty);
      expect(g.state.player(1).hand, isEmpty);
      expect(g.state.obj(o).damage, 6);
    });

    test('The Islands I Pulled from the Sea and Yzma - On Edge: search the deck (then shuffle)', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final loc = g.addCard('Training Grounds - Impossible Pillar', 0, Place.deck);
      g.apply(PlayMove(0, g.addCard('The Islands I Pulled from the Sea', 0, Place.hand)));
      expect(g.state.obj(loc).zone, Place.hand);
      final g2 = emptyGame();
      g2.addInk(0, 6);
      g2.addCard('Pull the Lever!', 0, Place.discard);
      final w = g2.addCard('Wrong Lever!', 0, Place.deck);
      g2.apply(PlayMove(0, g2.addCard('Yzma - On Edge', 0, Place.hand)));
      answer(g2, [1], player: 0);
      expect(g2.state.obj(w).zone, Place.hand);
    });

    test('The Lamp: Jafar draws 2; Genie returns a character with cost 4 or less', () {
      final g = emptyGame();
      final l = g.addCard('The Lamp', 0, Place.play);
      g.addCard('Genie - Cramped in the lamp', 0, Place.play);
      final o = g.addCard(vanilla, 1, Place.play);
      g.apply(ActivateMove(0, l, 0));
      answer(g, [o], player: 0);
      expect(g.state.obj(o).zone, Place.hand);
      expect(g.state.player(0).hand, isEmpty, reason: 'no Jafar');
    });

    test('The Magic Feather: Evasive while the item stays in play', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final c = g.addCard(vanilla, 0, Place.play);
      final f = g.addCard('The Magic Feather', 0, Place.hand);
      g.apply(PlayMove(0, f));
      expect(g.chars(c).has(Kw.evasive), isTrue);
      g.apply(ActivateMove(0, f, abilityIndex<Activated>(g, f)));
      expect(g.state.obj(f).zone, Place.hand);
      expect(g.chars(c).has(Kw.evasive), isFalse);
    });

    test('The Most Diabolical Scheme: banish your Villain to banish chosen character', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final v = g.addCard('Black Heron - Real Bad Egg', 0, Place.play);
      final o = g.addCard(big, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('The Most Diabolical Scheme', 0, Place.hand)));
      expect(g.state.obj(v).zone, Place.discard);
      expect(g.state.obj(o).zone, Place.discard);
    });

    test('The Queen - Diviner: an item costing 3 or less may be played for free, exerted', () {
      final g = emptyGame();
      final q = g.addCard('The Queen - Diviner', 0, Place.play);
      final it = g.addCard('Super Suit', 0, Place.deck);
      g.apply(ActivateMove(0, q, 0));
      answer(g, [it], player: 0);
      answer(g, [1], player: 0);
      drain(g);
      expect(g.state.obj(it).zone, Place.play);
      expect(g.state.obj(it).exerted, isTrue);
    });

    test('The Queen - Jealous Beauty: 3 cards to the bottom of their deck; 4 lore with a Princess (CR 6.1.5.1)', () {
      final g = emptyGame();
      final q = g.addCard('The Queen - Jealous Beauty', 0, Place.play);
      final cards = [g.addCard('Aurora - Regal Princess', 1, Place.discard), g.addCard(vanilla, 1, Place.discard), g.addCard(vanilla, 1, Place.discard)];
      g.apply(ActivateMove(0, q, 0));
      drain(g);
      expect(g.state.player(1).deck.skip(10), unorderedEquals(cards));
      expect(g.state.player(0).lore, 4);
      final g2 = emptyGame();
      final q2 = g2.addCard('The Queen - Jealous Beauty', 0, Place.play);
      g2.addCard(vanilla, 1, Place.discard);
      g2.apply(ActivateMove(0, q2, 0));
      expect(g2.state.player(0).lore, 0, reason: 'fewer than 3 cards: no lore');
    });

    test('The Return of Hercules: each player may play a character from their hand for free', () {
      final g = emptyGame();
      g.addInk(0, 5);
      final a = g.addCard(big, 0, Place.hand);
      final b = g.addCard(vanilla, 1, Place.hand);
      g.apply(PlayMove(0, g.addCard('The Return of Hercules', 0, Place.hand)));
      answer(g, [1], player: 0);
      answer(g, [1], player: 1);
      expect(g.state.obj(a).zone, Place.play);
      expect(g.state.obj(b).zone, Place.play);
    });

    test('Tramp: draw a card per other character, then discard that many', () {
      final g = emptyGame();
      g.addInk(0, 5);
      g.addCard(vanilla, 0, Place.play);
      g.addCard(vanilla, 0, Place.play);
      final t = g.addCard('Tramp - Street-Smart Dog', 0, Place.hand);
      expect(g.playCost(0, t), 5);
      g.apply(PlayMove(0, t));
      answer(g, [1], player: 0);
      expect(g.state.player(0).hand, isEmpty);
      expect(g.state.player(0).discard, hasLength(2));
    });

    test("Triton's Trident: +1 {s} per card in your hand", () {
      final g = emptyGame();
      final t = g.addCard("Triton's Trident", 0, Place.play);
      final c = g.addCard(vanilla, 0, Place.play);
      g.addCard(vanilla, 0, Place.hand);
      g.addCard(vanilla, 0, Place.hand);
      g.apply(ActivateMove(0, t, 0));
      expect(g.chars(c).strength, 5);
    });

    test('Tug-Of-War and Windstorm: with and without Evasive', () {
      final g = emptyGame();
      g.addInk(0, 9);
      final plain = g.addCard(big, 1, Place.play);
      final ev = g.addCard('Bashful - Riding the Rails', 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Tug-Of-War', 0, Place.hand)));
      answer(g, [0], player: 0);
      expect(g.state.obj(plain).damage, 1);
      expect(g.state.obj(ev).damage, 0);
      final loc = g.addCard('Training Grounds - Impossible Pillar', 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Windstorm', 0, Place.hand)));
      expect(g.state.obj(plain).damage, 2);
      expect(g.state.obj(ev).damage, 3);
      expect(g.state.obj(loc).damage, 1);
    });

    test("Ursula's Plan and Ursula's Trickery", () {
      final g = emptyGame();
      g.addInk(0, 4);
      final o = g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, g.addCard("Ursula's Plan", 0, Place.hand)));
      expect(g.state.obj(o).exerted, isTrue);
      g.apply(EndTurnMove(0));
      expect(g.state.obj(o).exerted, isTrue, reason: "can't ready at the start of their next turn");
      final g2 = emptyGame();
      g2.addInk(0, 1);
      g2.addCard(vanilla, 1, Place.hand);
      g2.apply(PlayMove(0, g2.addCard("Ursula's Trickery", 0, Place.hand)));
      answer(g2, [0], player: 1);
      expect(g2.state.player(0).hand, hasLength(1));
    });

    test('Vine Pod: banish yours, play one with the same name for free', () {
      final g = emptyGame();
      g.addInk(0, 1);
      final pod = g.addCard('Vine Pod', 0, Place.play);
      final c = g.addCard(vanilla, 0, Place.play);
      final same = g.addCard(vanilla, 0, Place.hand);
      g.apply(ActivateMove(0, pod, abilityIndex<Activated>(g, pod)));
      answer(g, [1], player: 0);
      expect(g.state.obj(c).zone, Place.discard);
      expect(g.state.obj(same).zone, Place.play);
    });

    test('Walk the Plank!: Pirates gain "{e} - Banish chosen damaged character" this turn', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final p = g.addCard("Gopher - Ship's Carpenter", 0, Place.play);
      final o = g.addCard(vanilla2, 1, Place.play, damage: 1);
      g.apply(PlayMove(0, g.addCard('Walk the Plank!', 0, Place.hand)));
      final i = g.abilitiesOf(p).length - 1;
      g.apply(ActivateMove(0, p, i));
      expect(g.state.obj(o).zone, Place.discard);
      g.apply(EndTurnMove(0));
      expect(g.abilitiesOf(p), hasLength(i), reason: 'this turn only');
    });

    test('We Know The Way: same name revealed may be played free; else it goes to the hand', () {
      final g = emptyGame(deck: 0);
      g.addInk(0, 3);
      final d = g.addCard(vanilla, 0, Place.discard);
      for (var i = 0; i < 3; i++) {
        g.addCard(vanilla, 0, Place.deck);
      }
      g.apply(PlayMove(0, g.addCard('We Know The Way', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.player(0).play, hasLength(1));
      expect(g.state.obj(d).zone, isNot(Place.discard));
      final g2 = emptyGame();
      g2.addInk(0, 3);
      g2.addCard(vanilla, 0, Place.discard);
      g2.apply(PlayMove(0, g2.addCard('We Know The Way', 0, Place.hand)));
      expect(g2.state.player(0).hand, hasLength(1));
    });

    test("We'll Save Our Village and What Else Can I Do?", () {
      final g = emptyGame();
      g.addInk(0, 2);
      final c = g.addCard(vanilla, 0, Place.play);
      final l = g.addCard('Training Grounds - Impossible Pillar', 0, Place.play);
      g.apply(PlayMove(0, g.addCard("We'll Save Our Village", 0, Place.hand)));
      expect(g.chars(c).n(Kw.resist), 1);
      expect(g.chars(l).n(Kw.resist), 1);
      for (final sung in [true, false]) {
        final g2 = emptyGame();
        g2.addInk(0, 5);
        final s = g2.addCard(big, 0, Place.play);
        final song = g2.addCard('What Else Can I Do?', 0, Place.hand);
        g2.apply(sung ? PlayMove(0, song, mode: PlayMode.sing, singers: [s]) : PlayMove(0, song));
        drain(g2);
        expect(g2.chars(s).has(Kw.ward), sung);
      }
    });

    test('When You Need Help, Just Call: only if an opponent has more characters', () {
      final g = emptyGame();
      g.addInk(0, 3);
      g.addCard(vanilla, 1, Place.play);
      final c = g.addCard(vanilla, 0, Place.hand);
      g.apply(PlayMove(0, g.addCard('When You Need Help, Just Call', 0, Place.hand)));
      answer(g, [1], player: 0);
      expect(g.state.obj(c).zone, Place.play);
    });

    test('Wipe Out!: a character with Bodyguard or an item', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final bg = g.addCard('Bobby - Purple Pigeon', 1, Place.play);
      final it = g.addCard('Super Suit', 1, Place.play);
      g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Wipe Out!', 0, Place.hand)));
      expect(g.pending!.decision.options, unorderedEquals([bg, it]));
      answer(g, [it], player: 0);
      expect(g.state.obj(it).zone, Place.inkwell);
    });

    test('Woody - Town Sheriff: chosen opponent can\'t challenge and must quest until your next turn', () {
      final g = emptyGame();
      g.addInk(0, 3);
      final o = g.addCard(vanilla, 1, Place.play);
      g.apply(PlayMove(0, g.addCard('Woody - Town Sheriff', 0, Place.hand)));
      g.apply(EndTurnMove(0));
      expect(g.whyNot(EndTurnMove(1)), isNotNull);
      g.apply(QuestMove(1, o));
      expect(g.whyNot(EndTurnMove(1)), isNull);
    });

    test('Yzma - Conniving Chemist: draw up to 3 if fewer', () {
      final g = emptyGame();
      final y = g.addCard('Yzma - Conniving Chemist', 0, Place.play);
      g.addCard(vanilla, 0, Place.hand);
      g.apply(ActivateMove(0, y, 0));
      expect(g.state.player(0).hand, hasLength(3));
    });

    test('Sleepy\'s Flute: lore only after playing a song', () {
      final g = emptyGame();
      g.addInk(0, 2);
      final f = g.addCard("Sleepy's Flute", 0, Place.play);
      g.apply(ActivateMove(0, f, 0));
      expect(g.state.player(0).lore, 0);
      g.state.obj(f).exerted = false;
      g.apply(PlayMove(0, g.addCard('Zero to Hero', 0, Place.hand)));
      g.apply(ActivateMove(0, f, 0));
      expect(g.state.player(0).lore, 1);
    });

    test("Tiana - Celebrating Princess also stops playing an action for free (CR 1.2.2)", () {
      final g = emptyGame(active: 1);
      g.addInk(1, 5);
      g.addCard('Tiana - Celebrating Princess', 0, Place.play, exerted: true);
      g.addCard(vanilla, 0, Place.play);
      final song = g.addCard('Zero to Hero', 1, Place.hand);
      g.apply(PlayMove(1, g.addCard('Ursula - Voice Stealer', 1, Place.hand)));
      drain(g);
      expect(g.state.obj(song).zone, Place.hand);
    });
  });

  test('"here" on a character is the location it is at (Moana - Born Leader); "they" are the readied ones', () {
    final g = emptyGame();
    final loc = g.addCard('Training Grounds - Impossible Pillar', 0, Place.play);
    final m = g.addCard('Moana - Born Leader', 0, Place.play);
    final here = g.addCard(vanilla, 0, Place.play, exerted: true);
    final away = g.addCard(vanilla, 0, Place.play, exerted: true);
    g.state.obj(m).at = loc;
    g.state.obj(here).at = loc;
    g.apply(QuestMove(0, m));
    expect(g.state.obj(here).exerted, isFalse);
    expect(g.state.obj(away).exerted, isTrue);
    expect(g.whyNot(QuestMove(0, here)), isNotNull);
  });

  test('random and starter decks keep to a card\'s own copy limit (CR 1.10.1.1)', () {
    for (final inks in inkPairs.values) {
      for (var seed = 1; seed <= 3; seed++) {
        final deck = randomDeck(db, inks, SeededRng(seed));
        expect(deck.where((n) => n == 'The Glass Slipper').length, lessThanOrEqualTo(2));
        expect(validateDeck(db, deck), isEmpty);
      }
    }
  });

  test('the computer answers the slice\'s decisions and games with these cards finish', () {
    final names = File('test/fixtures/wave2_s4_cards.txt').readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
    for (var seed = 1; seed <= 6; seed++) {
      final deck = [for (var i = 0; i < 60; i++) names[(i * 7 + seed) % names.length]];
      final g = Game(db, players: ['A', 'B'], seed: seed)..apply(StartMove([deck, deck.reversed.toList()]));
      runBots(g, [LorcanaBot(0, seed: seed), LorcanaBot(1, seed: seed + 9)], maxMoves: 3000);
      expect(g.over || g.toAct != null, isTrue);
    }
  });
}
