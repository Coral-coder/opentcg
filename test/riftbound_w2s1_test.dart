// Widget tests for wave 2, slice 1 on the Riftbound table: Bandle Tree's second facedown card
// shows at its battlefield, and Endless Riches' plays from the trash are offered and marked.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentcg/riftbound/riftbound_session.dart';
import 'package:opentcg/riftbound/riftbound_store.dart';
import 'package:opentcg/riftbound/riftbound_table.dart';
import 'package:opentcg/riftbound/riftbound_theme.dart';
import 'package:riftbound/riftbound.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_app/tcg_app.dart';

/// A hotseat game past both mulligans, in its active player's Main Phase, seen by that player.
Future<RiftboundSession> _game(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = RiftboundStore.shared;
  await tester.runAsync(() => store.init());
  final db = store.db;
  final legends = store.legendNames;
  final s = store.newGame(names: const ['You', 'Them'], decks: [buildDeck(db, db[legends[0]]!), buildDeck(db, db[legends[1]]!)], seed: 4, hotseat: true);
  for (var i = 0; i < 10 && s.match.pending != null; i++) {
    s.perform(AnswerMove(s.match.pending!.decision.player, const []));
  }
  s.localSeat = s.match.state.active;
  return s;
}

void main() {
  setUp(() {
    Console.available = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('both facedown cards at a battlefield show (Bandle Tree holds two)', (tester) async {
    final s = await _game(tester);
    final g = s.match;
    final me = s.localSeat;
    g.setControl(0, me);
    g.addCard('Vanguard Sergeant', me, zone: Zone.board, loc: 0);
    for (final name in ['Pakaa Cub', 'Consult the Past']) {
      final id = g.addCard(name, me, zone: Zone.facedown, loc: 0);
      g.state.obj(id)
        ..controller = me
        ..loc = 0;
    }
    await tester.pumpWidget(riftboundScope(MaterialApp(theme: riftboundTheme.material(), home: const RiftboundTable())));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('^Facedown Pakaa Cub')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Facedown Consult the Past')), findsOneWidget);
    RiftboundStore.shared.endSession();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with Endless Riches, cards in the trash can be played and are marked TRASH, not Flow', (tester) async {
    final s = await _game(tester);
    final g = s.match;
    final me = s.localSeat;
    g.addCard('Endless Riches', me, zone: Zone.board);
    g.addRunes(me, Domain.order, 2);
    final poro = g.addCard('Daring Poro', me, zone: Zone.trash);
    expect(g.legalMoves(me).whereType<PlayMove>().map((m) => m.card), contains(poro));
    await tester.pumpWidget(riftboundScope(MaterialApp(theme: riftboundTheme.material(), home: const RiftboundTable())));
    await tester.pump();
    final card = find.bySemanticsLabel(RegExp(r'^Daring Poro, playable from the trash$'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);
    expect(find.text('TRASH'), findsOneWidget);
    await tester.tap(card);
    await tester.pumpAndSettle();
    final play = find.textContaining('Play Daring Poro from the trash');
    expect(play, findsOneWidget);
    await tester.tap(play);
    await tester.pumpAndSettle();
    expect(g.state.obj(poro).zone, Zone.board);
    RiftboundStore.shared.endSession();
    await tester.pumpWidget(const SizedBox());
  });
}
