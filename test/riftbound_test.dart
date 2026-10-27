// Widget tests for Riftbound: the picker entry, the menu with its bundled cards and the fan
// notice, a game against the computer played by tapping the table (playing cards and moving
// units), the decision dialog for each kind of question, the card browser, and the image keys.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentcg/main.dart';
import 'package:opentcg/riftbound/riftbound_card.dart';
import 'package:opentcg/riftbound/riftbound_cards_screen.dart';
import 'package:opentcg/riftbound/riftbound_home.dart';
import 'package:opentcg/riftbound/riftbound_playable.dart';
import 'package:opentcg/riftbound/riftbound_store.dart';
import 'package:opentcg/riftbound/riftbound_table.dart';
import 'package:opentcg/riftbound/riftbound_theme.dart';
import 'package:riftbound/riftbound.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_app/tcg_app.dart';

/// Lets the computer's timed moves run.
Future<void> settle(WidgetTester tester, {int rounds = 40}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUp(() {
    Console.available = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the picker lists Riftbound', (tester) async {
    await tester.pumpWidget(const OpenTcgApp());
    expect(find.text('Riftbound'), findsOneWidget);
  });

  testWidgets('the menu loads the cards, lists the legends, shows coverage and the notice, and starts a game', (tester) async {
    tester.view.physicalSize = const Size(780, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final store = RiftboundStore.shared;
    await tester.runAsync(() => store.init());
    await tester.pumpWidget(MaterialApp(home: const RiftboundHome()));
    await tester.pump();
    await tester.pump();
    final (ok, total) = store.coverage;
    expect(ok, greaterThan(100));
    expect(store.legendNames.length, greaterThanOrEqualTo(8));
    expect(find.text(store.db[store.legendNames.first]!.shortName), findsWidgets);
    await tester.scrollUntilVisible(find.textContaining('Legal Jibber Jabber'), 200);
    expect(find.textContaining('$ok of $total cards fully supported'), findsOneWidget);
    expect(find.textContaining('Not endorsed by Riot Games'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Play the computer'), -200);
    await tester.tap(find.text('Play the computer'));
    await tester.pump(const Duration(milliseconds: 300));
    final s = store.session!;
    expect(s.match.state.bfs, hasLength(2));
    store.endSession();
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });

  testWidgets('a game against the computer is played by tapping the table', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = RiftboundStore.shared;
    await tester.runAsync(() => store.init());
    final db = store.db;
    final legends = store.legendNames;
    final decks = [buildDeck(db, db[legends[0]]!), buildDeck(db, db[legends[1]]!)];
    final s = store.newGame(names: const ['You', 'Computer'], decks: decks, seed: 11, hotseat: false)..botDelay = 10;
    await tester.pumpWidget(riftboundScope(MaterialApp(theme: riftboundTheme.material(), home: const RiftboundTable())));
    var plays = 0, moves = 0, turnsEnded = 0;
    for (var step = 0; step < 200 && turnsEnded < 5 && !s.match.over; step++) {
      await settle(tester, rounds: 5);
      final d = s.match.pending?.decision;
      if (d != null && d.player == s.localSeat) {
        // The dialog opens by itself: answer it by tapping.
        expect(find.byType(RiftboundDecisionDialog), findsOneWidget, reason: d.prompt);
        switch (d.kind) {
          case DecisionKind.option:
            await tester.tap(find.text(d.labels.first).last);
          case DecisionKind.yesNo:
            await tester.tap(find.text('Yes'));
          case DecisionKind.cards:
            for (var i = 0; i < d.min; i++) {
              await tester.tap(find.bySemanticsLabel(RegExp('^Option: ')).at(i));
              await tester.pump();
            }
            await tester.tap(find.text('Confirm'));
        }
        await tester.pump();
        continue;
      }
      if (!s.isLocalTurn || s.match.pending != null) continue;
      final before = s.match.moves.length;
      // Play a glowing hand card through its sheet.
      final playable = find.bySemanticsLabel(RegExp(r', playable$'));
      if (playable.evaluate().isNotEmpty && plays < 10) {
        await tester.tap(playable.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 50));
        final button = find.byWidgetPredicate((w) => w is ThemedButton && w.label.startsWith('Play '));
        await tester.tap(button.first);
        await tester.pump();
        if (s.match.moves.length > before) plays++;
        continue;
      }
      // Move a unit that can act to a battlefield.
      final actor = find.bySemanticsLabel(RegExp(r', can act$'));
      if (actor.evaluate().isNotEmpty && moves < 6) {
        await tester.tap(actor.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 50));
        final button = find.byWidgetPredicate((w) => w is ThemedButton && w.label.startsWith('Move ') && !w.label.contains('your base'));
        if (button.evaluate().isNotEmpty) {
          await tester.tap(button.first);
          await tester.pump();
          if (s.match.moves.length > before) moves++;
          continue;
        }
        Navigator.of(tester.element(find.byType(RiftboundTable))).pop();
        await tester.pump(const Duration(milliseconds: 300));
      }
      final pass = find.text('Pass');
      if (pass.evaluate().isNotEmpty) {
        await tester.tap(pass);
        await tester.pump();
        continue;
      }
      await tester.tap(find.text('End turn'));
      turnsEnded++;
      await tester.pump();
    }
    expect(plays, greaterThan(0), reason: 'played cards by tapping them');
    expect(moves, greaterThan(0), reason: 'moved units by tapping them');
    expect(s.match.state.turn, greaterThan(4), reason: 'the computer took its turns');
    store.endSession();
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });

  testWidgets('what glows is exactly what the engine allows', (tester) async {
    final store = RiftboundStore.shared;
    await tester.runAsync(() => store.init());
    final db = store.db;
    final s = store.newGame(names: const ['A', 'B'], decks: [buildDeck(db, db[store.legendNames[2]]!), buildDeck(db, db[store.legendNames[3]]!)], seed: 4, hotseat: true);
    // Through the mulligans into the first turn.
    while (s.match.pending != null) {
      s.perform(AnswerMove(s.match.pending!.decision.player, const []));
    }
    final g = s.match;
    final me = g.toAct!;
    final p = RiftboundPlayable.of(g, me);
    expect([for (final m in p.all) m.toString()], [for (final m in g.legalMoves(me)) m.toString()]);
    for (final id in g.state.player(me).hand) {
      expect(p.canPlay(id), g.whyNot(PlayMove(me, id)) == null, reason: g.nameOf(id));
    }
    expect(p.canEndTurn, isTrue);
    expect(RiftboundPlayable.of(g, 1 - me).all, isEmpty, reason: 'not their move');
    store.endSession();
  });

  testWidgets('the decision dialog answers cards, yes/no and option questions', (tester) async {
    final store = RiftboundStore.shared;
    await tester.runAsync(() => store.init());
    final db = store.db;
    final s = store.newGame(names: const ['A', 'B'], decks: [buildDeck(db, db[store.legendNames[0]]!), buildDeck(db, db[store.legendNames[1]]!)], seed: 7, hotseat: true);
    final hand = s.match.state.player(0).deck.take(3).toList();
    List<int>? answer;
    Future<void> ask(Decision d) async {
      answer = null;
      await tester.pumpWidget(
        riftboundScope(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async => answer = await showDialog<List<int>>(context: context, builder: (_) => riftboundScope(RiftboundDecisionDialog(session: s, decision: d))),
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
    }

    await ask(const Decision(kind: DecisionKind.yesNo, player: 0, prompt: 'Pay for Accelerate?'));
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(answer, [0]);

    await ask(const Decision(kind: DecisionKind.option, player: 0, prompt: 'Play it where?', labels: ['base', 'Zaun Warrens']));
    await tester.tap(find.text('Zaun Warrens'));
    await tester.pumpAndSettle();
    expect(answer, [1]);

    await ask(Decision(kind: DecisionKind.cards, player: 0, prompt: 'Discard 2', options: hand, min: 2, max: 2));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(answer, isNull, reason: 'Confirm is off until 2 are chosen');
    final options = find.bySemanticsLabel(RegExp('^Option: '));
    await tester.tap(options.at(0));
    await tester.pump();
    await tester.tap(options.at(2));
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(answer, [hand[0], hand[2]]);

    await ask(Decision(kind: DecisionKind.cards, player: 0, prompt: 'Mulligan', options: hand, min: 0, max: 2));
    await tester.tap(find.text('Look at the table'));
    await tester.pumpAndSettle();
    expect(answer, isNull, reason: 'looking at the table answers nothing');
    store.endSession();
  });

  testWidgets('the card browser searches and filters', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = RiftboundStore.shared;
    await tester.runAsync(() => store.init());
    final db = store.db;
    expect(filterRiftboundCards(db, const RiftboundCardQuery()).length, db.cards.length);
    final supported = filterRiftboundCards(db, const RiftboundCardQuery(supportedOnly: true));
    expect(supported, isNotEmpty);
    expect(supported.every((c) => RiftboundParser.parse(c).supported), isTrue);
    final fury = filterRiftboundCards(db, const RiftboundCardQuery(type: CardType.unit, domain: Domain.fury));
    expect(fury.every((c) => c.type == CardType.unit && c.domains.contains(Domain.fury)), isTrue);
    expect(filterRiftboundCards(db, const RiftboundCardQuery(text: 'jinx')).any((c) => c.name == 'Jinx, Demolitionist'), isTrue);
    await tester.pumpWidget(riftboundScope(MaterialApp(theme: riftboundTheme.material(), home: const RiftboundCardsScreen())));
    await tester.pump();
    expect(find.textContaining('${db.cards.length} cards'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'jinx');
    await tester.pump();
    expect(find.textContaining('${db.cards.length} cards'), findsNothing);
  });

  test('image keys match tool/riftbound_images.py', () {
    // Values printed by the Python tool's key().
    expect(riftboundImageKey('Jinx, Demolitionist'), '753dc830');
    expect(riftboundImageKey("Kai'Sa, Survivor"), 'd387623f');
  });
}
