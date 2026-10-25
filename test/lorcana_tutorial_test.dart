// The guided first game: the coach's script must still match the engine (same seed, decks and
// moves give the same game), every step must be doable, and the table must show it.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Ink;
import 'package:flutter_test/flutter_test.dart';
import 'package:lorcana/lorcana.dart';
import 'package:opentcg/lorcana/lorcana_card.dart';
import 'package:opentcg/lorcana/lorcana_store.dart';
import 'package:opentcg/lorcana/tutorial/rules_primer.dart';
import 'package:opentcg/lorcana/tutorial/tutorial_controller.dart';
import 'package:opentcg/lorcana/tutorial/tutorial_script.dart';
import 'package:opentcg/lorcana/tutorial/tutorial_table.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_app/tcg_app.dart';

final db = LCardDb.fromJson(jsonDecode(File('data/lorcana-cards.json').readAsStringSync()) as Map<String, dynamic>);

/// Plays the tutorial on the engine alone, doing what each step asks. Returns the finished game
/// and how many steps were completed, or throws with the step that couldn't be done.
(Game, int) playThrough(int seed, {bool log = false}) {
  final g = Game(db, players: TutorialScript.names, seed: seed);
  final opp = TutorialOpponent(1);
  final steps = TutorialScript.steps();
  g.apply(TutorialScript.start);
  var i = 0;
  void runOpponent() {
    var guard = 0;
    while (!g.state.over && opp.step(g)) {
      if (++guard > 200) throw StateError('opponent stuck');
    }
  }

  while (i < steps.length) {
    runOpponent();
    final st = steps[i];
    switch (st.kind) {
      case CoachKind.info:
        i++;
      case CoachKind.watch:
        if (g.state.active != 0 || g.pending != null) throw StateError('step $i (${st.title}): not back to the player');
        i++;
      case CoachKind.done:
        return (g, i);
      case CoachKind.move:
        final d = g.pending?.decision;
        final LMove m;
        if (d != null) {
          if (d.player != 0) throw StateError('step $i: waiting on the opponent');
          final minnie = [for (final o in d.options) if (g.state.objOrNull(o)?.card == TutorialScript.minnie) o];
          m = AnswerMove(0, d.kind == DecisionKind.cards && d.min == 0 && st.guardsAnswers ? const [] : (minnie.isNotEmpty ? [minnie.first] : g.defaultAnswer(d)));
        } else {
          final ok = [for (final x in g.legalMoves()) if (st.accepts!(g, x)) x];
          if (ok.isEmpty) throw StateError('step $i (${st.title}): no legal move does it');
          final glow = st.glow?.call(g) ?? const {};
          // Do it with a glowing card when there is one (what the player is shown).
          m = ok.firstWhere((x) => glow.isEmpty || glow.contains(CoachStep.endTurnButton) || glow.contains((x as dynamic).card), orElse: () => ok.first);
        }
        if (log) print('step $i ${st.title}: $m');
        if (!st.accepts!(g, m)) throw StateError('step $i: move not accepted');
        g.apply(m);
        // A decision the step caused (the song's choice) belongs to the next step.
        if (g.pending?.decision.player == 0 && steps[i + 1].accepts?.call(g, AnswerMove(0, const [])) == true) {
          i++;
          continue;
        }
        i++;
    }
  }
  return (g, i);
}

void main() {
  test('the guided game plays through with the fixed seed', () {
    final (g, i) = playThrough(TutorialScript.seed, log: true);
    final steps = TutorialScript.steps();
    expect(steps[i].kind, CoachKind.done);
    expect(g.state.player(0).lore, greaterThanOrEqualTo(4));
    expect(g.state.player(1).play.any((id) => g.state.obj(id).card == TutorialScript.goons), isFalse, reason: 'the Goons were banished');
    expect(g.state.player(0).play.where((id) => g.state.obj(id).card == TutorialScript.minnie).map((id) => g.state.obj(id).damage), [0], reason: 'Minnie was healed');
  });

  testWidgets('the guided game plays on the real table, by tapping what glows', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 932) * 2; // 390 wide overflows the table's player strip (not the tutorial's)
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => LorcanaStore.shared.init());
    await tester.pumpWidget(ThemeScope(
      theme: Themes.classic,
      child: MaterialApp(
        theme: Themes.classic.material(),
        home: Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => openLorcanaTutorial(c), child: const Text('go'))))),
      ),
    ));
    // The glow pulses forever, so step time instead of settling.
    Future<void> wait([int ms = 600]) async {
      for (var i = 0; i < ms ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.tap(find.text('go'));
    await wait();
    final c = tester.widget<TutorialTable>(find.byType(TutorialTable)).controller;
    c.session.botDelay = 20;
    final seen = <String>[];
    for (var guard = 0; guard < 300 && !c.finished; guard++) {
      final st = c.step;
      final g = c.game;
      if (seen.isEmpty || seen.last != st.title) seen.add(st.title);
      expect(find.text(st.title), findsWidgets, reason: 'the coach shows the step');
      switch (st.kind) {
        case CoachKind.info:
          await tester.tap(find.text('Next'));
        case CoachKind.watch:
          await wait(300);
        case CoachKind.done:
          break;
        case CoachKind.move:
          final d = g.pending?.decision;
          if (d != null) {
            final minnie = find.descendant(of: find.byType(AlertDialog), matching: find.byWidgetPredicate((w) => w is LorcanaCardView && w.card.fullName == TutorialScript.minnie));
            if (!st.guardsAnswers && minnie.evaluate().isNotEmpty) await tester.tap(minnie.first);
            await tester.pump();
            await tester.tap(find.text('Confirm'));
          } else {
            final ok = [for (final x in g.legalMoves()) if (st.accepts!(g, x)) x];
            expect(ok, isNotEmpty, reason: 'step ${st.title} can be done');
            final m = ok.first;
            if (m is EndTurnMove) {
              expect(find.byWidgetPredicate((w) => w is TutorialGlow && w.id == CoachStep.endTurnButton), findsOneWidget);
              await tester.tap(find.text('End turn'));
            } else {
              // Tap a glowing card, then the glowing button on its sheet.
              final glows = c.glows;
              expect(glows, isNotEmpty, reason: 'step ${st.title} points at something');
              final id = (ok.firstWhere((x) => glows.contains((x as dynamic).card), orElse: () => m) as dynamic).card as int;
              final card = find.byWidgetPredicate((w) => w is TutorialGlow && w.id == id);
              await tester.ensureVisible(card.first);
              await tester.tap(card.first);
              await wait(500);
              final button = find.byWidgetPredicate((w) => w is TutorialGlow && w.on);
              expect(button, findsOneWidget, reason: 'step ${st.title}: the move is lit on the sheet');
              await tester.tap(button);
            }
          }
      }
      await wait();
    }
    expect(c.finished, isTrue, reason: 'reached the end; steps seen: $seen');
    expect(find.text('You’ve learned the basics'), findsOneWidget);
    expect(c.game.state.player(0).lore, greaterThanOrEqualTo(4));
    await tester.tap(find.text('Keep playing this game'));
    await wait();
    expect(c.free, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rules primer pages through to the guided game', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => LorcanaStore.shared.init());
    var guided = false;
    await tester.pumpWidget(ThemeScope(
      theme: Themes.classic,
      child: MaterialApp(theme: Themes.classic.material(), home: Builder(builder: (c) => TextButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => LorcanaRulesPrimer(onGuidedGame: () => guided = true))), child: const Text('go')))),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Your turn'), findsOneWidget);
    await tester.tap(find.text('Try the guided game'));
    await tester.pumpAndSettle();
    expect(guided, isTrue);
  });

  test('find seeds', () {
    final ok = <int>[];
    for (var s = 1; s < 3000 && ok.length < 10; s++) {
      try {
        playThrough(s);
        ok.add(s);
      } catch (_) {}
    }
    print('seeds: $ok');
  }, skip: !Platform.environment.containsKey('TUTORIAL_SEEDS'));
}
