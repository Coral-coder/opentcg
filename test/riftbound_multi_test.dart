// Riftbound's multiplayer modes in the app: the mode picker on the menu, a War table with three
// computers (opponents' panels, everyone's units at the battlefields, choices between opponents),
// and a 2v2 table with a teammate.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentcg/riftbound/riftbound_deck_choice.dart';
import 'package:opentcg/riftbound/riftbound_home.dart';
import 'package:opentcg/riftbound/riftbound_store.dart';
import 'package:opentcg/riftbound/riftbound_table.dart';
import 'package:opentcg/riftbound/riftbound_theme.dart';
import 'package:riftbound/riftbound.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_app/tcg_app.dart';
import 'package:tcg_core/tcg_core.dart' show SeededRng;

/// Lets the computers' timed moves run.
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

  testWidgets('the menu picks a mode and starts a War game against three computers', (tester) async {
    tester.view.physicalSize = const Size(780, 2800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final store = RiftboundStore.shared;
    await tester.runAsync(() => store.init());
    await tester.pumpWidget(MaterialApp(home: const RiftboundHome()));
    await tester.pump();
    await tester.pump();
    for (final m in RMode.values) {
      expect(find.text(m.label), findsOneWidget);
    }
    await tester.tap(find.text(RMode.ffa4.label));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('4 players, one device'), 300);
    expect(find.text('4 players, one device'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('score 8 points'), 300);
    await tester.scrollUntilVisible(find.text('Play the computers'), -300);
    expect(find.text('Play the computers'), findsOneWidget);
    await tester.tap(find.text('Play the computers'));
    await tester.pump(const Duration(milliseconds: 300));
    final s = store.session!;
    expect(s.match.state.players, hasLength(4));
    expect(s.match.state.mode, RMode.ffa4);
    expect(s.match.state.bfs, hasLength(3));
    store.endSession();
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });

  testWidgets('a War table shows every opponent, and the computers play their turns', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = RiftboundStore.shared;
    await tester.runAsync(() => store.init());
    final decks = riftboundDecksFor(RMode.ffa4, buildDeck(store.db, store.db[store.legendNames.first]!), SeededRng(3));
    final s = store.newGame(names: const ['You', 'Computer 1', 'Computer 2', 'Computer 3'], decks: decks, seed: 7, hotseat: false, mode: RMode.ffa4)..botDelay = 10;
    await tester.pumpWidget(riftboundScope(MaterialApp(theme: riftboundTheme.material(), home: const RiftboundTable())));
    await settle(tester, rounds: 3);
    // One panel per opponent, with their points out of 8.
    for (final n in const ['Computer 1', 'Computer 2', 'Computer 3']) {
      expect(find.bySemanticsLabel(RegExp('^$n, \\d+ of 8 points')), findsOneWidget, reason: n);
    }
    expect(find.textContaining('First to 8 · you 0'), findsOneWidget);
    // Play on: answer what's asked with the first choice, and end turns, until the computers
    // have had their turns.
    for (var step = 0; step < 300 && s.match.state.turn < 6 && !s.match.over; step++) {
      await settle(tester, rounds: 3);
      final d = s.match.pending?.decision;
      if (d != null && d.player == s.localSeat) {
        s.perform(AnswerMove(s.localSeat, Game.defaultAnswer(d)));
        continue;
      }
      if (!s.isLocalTurn) continue;
      final moves = s.match.legalMoves(s.localSeat);
      final m = moves.whereType<PassMove>().firstOrNull ?? moves.whereType<EndTurnMove>().firstOrNull;
      if (m != null) s.perform(m);
    }
    expect(s.match.state.turn, greaterThanOrEqualTo(6), reason: 'everyone took turns');
    expect(tester.takeException(), isNull);
    // Tapping another opponent shows their base (once no question of ours is open).
    while (s.match.pending?.decision.player == s.localSeat) {
      s.perform(AnswerMove(s.localSeat, Game.defaultAnswer(s.match.pending!.decision)));
      await settle(tester, rounds: 2);
    }
    if (find.byType(RiftboundDecisionDialog).evaluate().isNotEmpty) {
      Navigator.of(tester.element(find.byType(RiftboundDecisionDialog))).pop();
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(find.bySemanticsLabel(RegExp('^Computer 2, ')));
    await tester.pump();
    expect(find.text('COMPUTER 2'), findsOneWidget);
    store.endSession();
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });

  testWidgets('a 2v2 table marks the teammate and shows the team score to 11', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = RiftboundStore.shared;
    await tester.runAsync(() => store.init());
    final decks = riftboundDecksFor(RMode.teams, buildDeck(store.db, store.db[store.legendNames.first]!), SeededRng(5));
    final s = store.newGame(names: const ['You', 'Rival 1', 'Ally', 'Rival 2'], decks: decks, seed: 9, hotseat: false, mode: RMode.teams)..botDelay = 10;
    await tester.pumpWidget(riftboundScope(MaterialApp(theme: riftboundTheme.material(), home: const RiftboundTable())));
    await settle(tester, rounds: 3);
    expect(find.bySemanticsLabel(RegExp('^Ally, your teammate')), findsOneWidget);
    expect(find.textContaining('First team to 11'), findsOneWidget);
    expect(s.match.state.allied(0, 2), isTrue);
    store.endSession();
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });

  testWidgets('a choice between opponents is offered by name', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = RiftboundStore.shared;
    await tester.runAsync(() => store.init());
    final decks = riftboundDecksFor(RMode.ffa3, buildDeck(store.db, store.db[store.legendNames.first]!), SeededRng(2));
    final s = store.newGame(names: const ['You', 'Ana', 'Ben'], decks: decks, seed: 4, hotseat: true, mode: RMode.ffa3);
    await tester.pumpWidget(
      riftboundScope(
        MaterialApp(
          theme: riftboundTheme.material(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<List<int>>(
                    context: context,
                    builder: (_) => riftboundScope(
                      RiftboundDecisionDialog(
                        session: s,
                        decision: const Decision(kind: DecisionKind.option, player: 0, prompt: 'Burn: which opponent burns?', labels: ['Ana', 'Ben']),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Burn: which opponent burns?'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Ben'), findsOneWidget);
    store.endSession();
  });
}
