// Lorcana card browser and deck builder: filters, deck lists, legality, playing a saved deck,
// and phone-size screenshots of the screens (build/screenshots/; any overflow fails the test).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Ink;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lorcana/lorcana.dart';
import 'package:opentcg/lorcana/lorcana_cards_screen.dart';
import 'package:opentcg/lorcana/lorcana_decks.dart';
import 'package:opentcg/lorcana/lorcana_decks_screen.dart';
import 'package:opentcg/lorcana/lorcana_home.dart';
import 'package:opentcg/lorcana/lorcana_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_app/tcg_app.dart';

final _shot = GlobalKey();
final db = LCardDb.fromJson(jsonDecode(File('data/lorcana-cards.json').readAsStringSync()) as Map<String, dynamic>);

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(390, 844) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LorcanaStore.shared.init());
  await tester.pumpWidget(RepaintBoundary(key: _shot, child: ThemeScope(theme: Themes.classic, child: MaterialApp(theme: Themes.classic.material(), home: home))));
  await tester.pump();
}

Future<void> _save(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/screenshots')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUp(() {
    Console.available = false;
    SharedPreferences.setMockInitialValues({});
  });

  group('filters', () {
    test('ink, type, cost, inkable, text and supported-only narrow the list', () {
      final all = filterCards(db, CardQuery());
      expect(all.length, db.length);
      final amber = filterCards(db, CardQuery(inks: {Ink.amber}));
      expect(amber, isNotEmpty);
      expect(amber.every((c) => c.inks.contains(Ink.amber)), isTrue);
      final songs = filterCards(db, CardQuery(types: {CardType.action}, text: 'song'));
      expect(songs.every((c) => c.type == CardType.action), isTrue);
      final big = filterCards(db, CardQuery(costs: {9}));
      expect(big.every((c) => c.cost >= 9), isTrue);
      final notInkable = filterCards(db, CardQuery(inkable: false));
      expect(notInkable.every((c) => !c.inkable), isTrue);
      final supported = filterCards(db, CardQuery(supportedOnly: true));
      expect(supported.length, lessThanOrEqualTo(all.length));
      expect(supported.every((c) => LorcanaParser.parse(c).supported), isTrue);
      final mickey = filterCards(db, CardQuery(text: 'mickey mouse'));
      expect(mickey.every((c) => '${c.fullName} ${c.text}'.toLowerCase().contains('mickey')), isTrue);
      final (sets, rarities) = setsAndRarities(db);
      final inSet = filterCards(db, CardQuery(set: sets.first, rarity: rarities.first));
      expect(inSet.every((c) => c.printings.any((p) => p.set == sets.first) && c.printings.any((p) => p.rarity == rarities.first)), isTrue);
    });
  });

  group('deck lists', () {
    test('export then import gives the same deck', () {
      final deck = starterDeck(db, {Ink.amber, Ink.steel});
      expect(deck.length, 60);
      final text = formatDeckList(db, deck);
      expect(text.split('\n').first, matches(RegExp(r'^\d+ ')));
      final (back, errors) = parseDeckList(db, text);
      expect(errors, isEmpty);
      expect([...back]..sort(), [...deck]..sort());
    });

    test('import accepts "4x", dashes, case and comments, and reports unknown lines', () {
      final c = db.cards.firstWhere((c) => c.version.isNotEmpty);
      final weird = '# my deck\n2x ${c.name.toLowerCase()} – ${c.version}\n${c.fullName}\n3 Not A Real Card - Nope';
      final (cards, errors) = parseDeckList(db, weird);
      expect(cards, [c.fullName, c.fullName, c.fullName]);
      expect(errors, ['Unknown card: Not A Real Card - Nope']);
    });

    test('starter decks are legal and the same every time', () {
      for (final p in allInkPairs()) {
        final d = starterDeck(db, p);
        expect(validateDeck(db, d), isEmpty, reason: inkPairName(p));
        expect(starterDeck(db, p), d);
      }
    });

    test('the deck book saves, duplicates and deletes', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final book = LorcanaDeckBook()..load(prefs);
      final d = book.create('Test', ['A', 'B']);
      book.duplicate(d);
      final again = LorcanaDeckBook()..load(prefs);
      expect(again.decks.map((x) => x.name), ['Test', 'Test (copy)']);
      again.delete(again.decks.first);
      expect((LorcanaDeckBook()..load(prefs)).decks.map((x) => x.name), ['Test (copy)']);
    });
  });

  testWidgets('the editor says what makes a deck illegal (CR 1.10.1.1)', (tester) async {
    await _pump(tester, const SizedBox());
    final store = LorcanaStore.shared;
    final supported = [for (final c in db.cards) if (LorcanaParser.parse(c).supported) c];
    final a = supported.firstWhere((c) => c.inks.length == 1 && c.inks.first == Ink.amber);
    final b = supported.firstWhere((c) => c.inks.length == 1 && c.inks.first == Ink.ruby);
    final s = supported.firstWhere((c) => c.inks.length == 1 && c.inks.first == Ink.steel);
    final deck = store.decks.create('Bad', [for (var i = 0; i < 5; i++) a.fullName, b.fullName, s.fullName]);
    await tester.pumpWidget(ThemeScope(theme: Themes.classic, child: MaterialApp(theme: Themes.classic.material(), home: LorcanaDeckEditor(deck: deck))));
    await tester.pump();
    expect(find.textContaining('not legal yet'), findsOneWidget);
    expect(find.textContaining('at least 60 cards'), findsOneWidget);
    expect(find.textContaining('At most 4 copies of ${a.fullName}'), findsOneWidget);
    expect(find.textContaining('At most two ink types'), findsOneWidget);
    store.decks.delete(deck);
  });

  testWidgets('the browser filters as you tap', (tester) async {
    await _pump(tester, const LorcanaCardsScreen());
    expect(find.text('${db.length} cards'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Amber'));
    await tester.pump();
    final amber = filterCards(db, CardQuery(inks: {Ink.amber}));
    expect(find.text('${amber.length} cards'), findsOneWidget);
    await _save(tester, 'lorcana-cards');
    await tester.enterText(find.byType(TextField), 'zzzz-no-such-card');
    await tester.pump();
    expect(find.text('0 cards'), findsOneWidget);
  });

  testWidgets('a saved deck can be chosen and played against the computer', (tester) async {
    await _pump(tester, const SizedBox());
    final store = LorcanaStore.shared;
    final cards = starterDeck(db, {Ink.emerald, Ink.sapphire});
    final deck = store.decks.create('My Emerald/Sapphire', cards);
    await tester.pumpWidget(RepaintBoundary(key: _shot, child: ThemeScope(theme: Themes.classic, child: MaterialApp(theme: Themes.classic.material(), home: const LorcanaHome()))));
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Emerald/Sapphire').last);
    await tester.pumpAndSettle();
    await _save(tester, 'lorcana-home');
    await tester.tap(find.text('Play the computer'));
    await tester.pump(const Duration(milliseconds: 300));
    final s = store.session!;
    expect(s.decks.first, cards);
    expect(s.match.state.player(0).hand.length, 7);
    store.endSession();
    store.decks.delete(deck);
  });

  testWidgets('decks list, editor and card detail lay out at phone size', (tester) async {
    await _pump(tester, const SizedBox());
    final store = LorcanaStore.shared;
    final deck = store.decks.create('Starter: Amber/Steel', starterDeck(db, {Ink.amber, Ink.steel}));
    await tester.pumpWidget(RepaintBoundary(key: _shot, child: ThemeScope(theme: Themes.classic, child: MaterialApp(theme: Themes.classic.material(), home: const LorcanaDecksScreen()))));
    await tester.pump();
    expect(find.text('Starter: Amber/Steel'), findsOneWidget);
    expect(find.textContaining('ready to play'), findsOneWidget);
    await _save(tester, 'lorcana-decks');
    await tester.tap(find.text('Starter: Amber/Steel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Legal: 60 cards'), findsOneWidget);
    await _save(tester, 'lorcana-deck-editor');
    // Every printed card is supported, so show the page with a made-up one.
    final real = db.cards.first;
    final unsupported = LCard(
      fullName: 'Test Card - Not Real',
      type: real.type,
      cost: real.cost,
      inkable: real.inkable,
      inks: real.inks,
      strength: real.strength,
      willpower: real.willpower,
      lore: real.lore,
      moveCost: real.moveCost,
      classifications: real.classifications,
      text: 'Whenever the moon is full, shuffle the sky into your inkwell.',
      printings: real.printings,
      franchise: real.franchise,
    );
    await tester.pumpWidget(RepaintBoundary(key: _shot, child: ThemeScope(theme: Themes.classic, child: MaterialApp(key: const ValueKey('detail'), theme: Themes.classic.material(), home: LorcanaCardDetail(card: unsupported)))));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Not supported yet'), 300);
    expect(find.text('Not supported yet'), findsOneWidget);
    expect(find.textContaining(LorcanaParser.parse(unsupported).unsupported.first.split('\n').first.substring(0, 10)), findsWidgets);
    await _save(tester, 'lorcana-card-detail');
    store.decks.delete(deck);
  });
}
