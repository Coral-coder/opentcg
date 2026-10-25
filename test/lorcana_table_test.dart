// The Lorcana table shows what can be done without tapping: the playable-actions map is the
// engine's legal moves, and the cards wear a badge for each action (with a phone-size
// screenshot in build/screenshots/).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Ink;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lorcana/lorcana.dart';
import 'package:opentcg/lorcana/lorcana_playable.dart';
import 'package:opentcg/lorcana/lorcana_store.dart';
import 'package:opentcg/lorcana/lorcana_table.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_app/tcg_app.dart';
import 'package:tcg_core/tcg_core.dart' show SeededRng;

final db = LCardDb.fromJson(jsonDecode(File('data/lorcana-cards.json').readAsStringSync()) as Map<String, dynamic>);
final _shot = GlobalKey();

/// A dealt game past the mulligans, its first player to act.
Game _dealt(int seed) {
  final rng = SeededRng(seed);
  final g = Game(db, players: ['A', 'B'], seed: seed)..apply(StartMove([randomDeck(db, {Ink.amber, Ink.steel}, rng), randomDeck(db, {Ink.ruby, Ink.sapphire}, rng)]));
  while (g.pending != null) {
    g.apply(AnswerMove(g.pending!.decision.player, g.defaultAnswer(g.pending!.decision)));
  }
  return g;
}

void main() {
  setUp(() {
    Console.available = false;
    SharedPreferences.setMockInitialValues({});
  });

  group('playableActions', () {
    test('files every legal move but ending the turn under the card that makes it', () {
      for (var seed = 1; seed <= 6; seed++) {
        final g = _dealt(seed);
        final seat = g.state.active;
        final p = playableActions(g, seat);
        final legal = g.legalMoves().where((m) => m is! EndTurnMove).toList();
        expect(p.moves.length, legal.length);
        expect(p.byCard.values.fold<int>(0, (n, l) => n + l.length), legal.length);
        for (final id in g.state.player(seat).hand) {
          final inkable = legal.any((m) => m is InkMove && m.card == id);
          expect(p.actionsOf(id).contains(CardAction.ink), inkable, reason: g.card(id).fullName);
          final canPlay = legal.any((m) => m is PlayMove && m.card == id && m.mode == PlayMode.ink);
          expect(p.actionsOf(id).contains(CardAction.play), canPlay, reason: g.card(id).fullName);
        }
        expect(p.canInk, legal.any((m) => m is InkMove));
        expect(playableActions(g, 1 - seat).isEmpty, isTrue, reason: 'not their turn');
      }
    });

    test('after inking, no card offers the inkwell any more (CR 4.2.3: once per turn)', () {
      final g = _dealt(3);
      final seat = g.state.active;
      final ink = playableActions(g, seat).moves.whereType<InkMove>().first;
      g.apply(ink);
      final p = playableActions(g, seat);
      expect(p.canInk, isFalse);
      expect(p.byCard.keys.any((id) => p.actionsOf(id).contains(CardAction.ink)), isFalse);
      expect(p.inkReady, 1);
      expect(playableSummary(p), startsWith('1 of 1 ink ready'));
    });

    test('a quest shows as a quest, and targets are found for challenges', () {
      final g = _dealt(5);
      final seat = g.state.active;
      // A ready, dry character of ours and an exerted one of theirs.
      final mine = g.state.player(seat).hand.firstWhere((id) => g.card(id).type == CardType.character);
      g.state.player(seat).hand.remove(mine);
      g.state.player(seat).play.add(mine);
      g.state.obj(mine)
        ..zone = Place.play
        ..dry = true;
      final theirs = g.state.player(1 - seat).hand.firstWhere((id) => g.card(id).type == CardType.character);
      g.state.player(1 - seat).hand.remove(theirs);
      g.state.player(1 - seat).play.add(theirs);
      g.state.obj(theirs)
        ..zone = Place.play
        ..dry = true
        ..exerted = true;
      g.state.version++;
      final p = playableActions(g, seat);
      expect(p.actionsOf(mine), containsAll({CardAction.quest, CardAction.challenge}));
      expect(p.targetsOf(mine, CardAction.challenge).keys, [theirs]);
      expect(p.actionsOf(theirs), isEmpty);
    });
  });

  testWidgets('the table badges what can be done, and inking from the card sheet works', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final store = LorcanaStore.shared;
    await tester.runAsync(() => store.init());
    final rng = SeededRng(11);
    final s = store.newGame(names: const ['Player 1', 'Player 2'], decks: [randomDeck(db, {Ink.amber, Ink.steel}, rng), randomDeck(db, {Ink.emerald, Ink.amethyst}, rng)], seed: 11, hotseat: true);
    while (s.match.pending != null) {
      final d = s.match.pending!.decision;
      s.perform(AnswerMove(d.player, s.match.defaultAnswer(d)));
    }
    await tester.pumpWidget(RepaintBoundary(key: _shot, child: ThemeScope(theme: Themes.classic, child: MaterialApp(theme: Themes.classic.material(), home: const LorcanaTable()))));
    await tester.pump();
    expect(s.isLocalTurn, isTrue);
    expect(find.byTooltip('Can go in your inkwell'), findsWidgets);
    expect(find.textContaining('ink ready'), findsOneWidget);
    expect(find.text('Your turn'), findsOneWidget);
    await tester.runAsync(() async {
      final boundary = _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/screenshots')..createSync(recursive: true);
      File('${dir.path}/lorcana-table.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    // Tap an inkable hand card: its sheet offers the inkwell.
    final pl = playableActions(s.match, s.localSeat);
    final inkable = s.match.state.player(s.localSeat).hand.firstWhere((id) => pl.actionsOf(id).contains(CardAction.ink));
    final before = s.match.state.player(s.localSeat).inkwell.length;
    await tester.tap(find.byKey(ValueKey(inkable)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Put in your inkwell'));
    await tester.pumpAndSettle();
    expect(s.match.state.player(s.localSeat).inkwell.length, before + 1);
    expect(find.byTooltip('Can go in your inkwell'), findsNothing, reason: 'once per turn');
    store.endSession();
  });

  testWidgets('a challenge with two targets lights them up, and tapping one challenges it', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final store = LorcanaStore.shared;
    await tester.runAsync(() => store.init());
    final rng = SeededRng(5);
    final s = store.newGame(names: const ['Player 1', 'Player 2'], decks: [randomDeck(db, {Ink.amber, Ink.steel}, rng), randomDeck(db, {Ink.emerald, Ink.amethyst}, rng)], seed: 5, hotseat: true);
    while (s.match.pending != null) {
      final d = s.match.pending!.decision;
      s.perform(AnswerMove(d.player, s.match.defaultAnswer(d)));
    }
    final g = s.match;
    final me = s.localSeat, opp = 1 - me;
    int put(int seat, bool Function(LCard) want, {bool exerted = false}) {
      final id = g.state.player(seat).deck.firstWhere((id) => want(g.card(id)));
      g.state.player(seat).deck.remove(id);
      g.state.player(seat).play.add(id);
      g.state.obj(id)
        ..zone = Place.play
        ..dry = true
        ..exerted = exerted;
      return id;
    }

    // A ready attacker of ours and two exerted characters of theirs.
    final attacker = put(me, (c) => c.type == CardType.character && (c.strength ?? 0) >= 3);
    final a = put(opp, (c) => c.type == CardType.character, exerted: true);
    final b = put(opp, (c) => c.type == CardType.character, exerted: true);
    g.state.version++;
    final pl = playableActions(g, me);
    expect(pl.targetsOf(attacker, CardAction.challenge).keys, containsAll([a, b]));

    await tester.pumpWidget(MaterialApp(home: const LorcanaTable()));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey(attacker)));
    await tester.pumpAndSettle();
    expect(find.text('Challenge…'), findsOneWidget);
    await tester.tap(find.text('Challenge…'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an exerted character or location to challenge'), findsOneWidget);
    // The two targets wear the challenge mark; the attacker is the one aiming.
    expect(find.byTooltip('Can challenge'), findsNWidgets(2));
    final before = g.actions.length;
    await tester.tap(find.byKey(ValueKey(b)));
    await tester.pumpAndSettle();
    expect(g.actions.length, before + 1);
    expect(g.actions.last, isA<ChallengeMove>().having((m) => m.target, 'target', b));
    expect(find.text('Choose an exerted character or location to challenge'), findsNothing);
    store.endSession();
  });
}
