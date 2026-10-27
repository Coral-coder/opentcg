// Widget test for Hidden (CR 811) on the Riftbound table: a card with Hidden glows in the hand,
// its sheet offers to hide it, and once hidden it shows facedown at the battlefield, face up
// only to its owner.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentcg/riftbound/riftbound_playable.dart';
import 'package:opentcg/riftbound/riftbound_store.dart';
import 'package:opentcg/riftbound/riftbound_table.dart';
import 'package:opentcg/riftbound/riftbound_theme.dart';
import 'package:riftbound/riftbound.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_app/tcg_app.dart';

void main() {
  setUp(() {
    Console.available = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a card with Hidden is hidden from its sheet and sits facedown at the battlefield', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = RiftboundStore.shared;
    await tester.runAsync(() => store.init());
    final db = store.db;
    final legends = store.legendNames;
    final s = store.newGame(names: const ['You', 'Them'], decks: [buildDeck(db, db[legends[0]]!), buildDeck(db, db[legends[1]]!)], seed: 4, hotseat: true);
    // Keep both opening hands, then reach a Main Phase.
    for (var i = 0; i < 10 && s.match.pending != null; i++) {
      s.perform(AnswerMove(s.match.pending!.decision.player, const []));
    }
    final g = s.match;
    final me = g.state.active;
    s.localSeat = me;
    // A battlefield to hide at, Power to pay, and a card with Hidden.
    g.setControl(0, me);
    g.addCard('Vanguard Sergeant', me, zone: Zone.board, loc: 0);
    g.addRunes(me, Domain.body, 1);
    final cub = g.addCard('Pakaa Cub', me);
    expect(RiftboundPlayable.of(g, me).forObject(cub), contains(isA<HideMove>()));
    await tester.pumpWidget(riftboundScope(MaterialApp(theme: riftboundTheme.material(), home: const RiftboundTable())));
    await tester.pump();
    final card = find.bySemanticsLabel(RegExp('^Pakaa Cub, (playable|can be hidden)'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
    final hide = find.textContaining('Hide Pakaa Cub');
    expect(hide, findsOneWidget);
    await tester.tap(hide);
    await tester.pumpAndSettle();
    expect(g.state.obj(cub).zone, Zone.facedown);
    expect(find.bySemanticsLabel(RegExp('^Facedown Pakaa Cub')), findsOneWidget);
    // The opponent sees only a card back.
    s.localSeat = g.state.other(me);
    s.notifyListeners();
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('^Facedown Pakaa Cub')), findsNothing);
    expect(find.bySemanticsLabel('A facedown card'), findsOneWidget);
    store.endSession();
    await tester.pumpWidget(const SizedBox());
  });
}
