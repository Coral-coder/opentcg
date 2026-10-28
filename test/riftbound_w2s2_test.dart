// The Riftbound table offers abilities a unit has from other cards (Heimerdinger, Inventor).
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

  testWidgets('Heimerdinger glows with a friendly gear’s {E} ability, and its sheet uses it', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = RiftboundStore.shared;
    await tester.runAsync(() => store.init());
    final db = store.db;
    final s = store.newGame(names: const ['A', 'B'], decks: [buildDeck(db, db[store.legendNames[0]]!), buildDeck(db, db[store.legendNames[1]]!)], seed: 3, hotseat: true);
    while (s.match.pending != null) {
      s.perform(AnswerMove(s.match.pending!.decision.player, const []));
    }
    final g = s.match;
    final me = g.toAct!;
    g.addCard('Heart of Dark Ice', me, zone: Zone.board); // {E}: Give a unit +3 {M} this turn.
    final heimer = g.addCard('Heimerdinger, Inventor', me, zone: Zone.board);
    final playable = RiftboundPlayable.of(g, me);
    // The legend's {E} abilities come first; the gear's is among them.
    final borrowed = playable.forObject(heimer).whereType<ActivateMove>().where((m) => m.index >= ws2BorrowBase);
    expect(borrowed.map((m) => (g.abilityOfMove(m)! as Activated).text), contains('{E}: Give a unit +3 {M} this turn.'));
    expect(playable.canUse(heimer), isTrue);

    await tester.pumpWidget(riftboundScope(MaterialApp(theme: riftboundTheme.material(), home: const RiftboundTable())));
    await tester.pump();
    final card = find.bySemanticsLabel(RegExp(r'^Heimerdinger, Inventor'));
    expect(card, findsWidgets);
    await tester.ensureVisible(card.first);
    await tester.pump();
    await tester.tap(card.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    final use = find.textContaining('give a unit +3 Might this turn');
    expect(use, findsWidgets);
    await tester.tap(use.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    // Choose Heimerdinger himself for the +3.
    if (s.match.pending != null) s.perform(AnswerMove(me, [heimer]));
    while (s.match.state.chain.isNotEmpty && s.match.pending == null) {
      s.perform(PassMove(s.match.toAct!));
    }
    expect(s.match.state.obj(heimer).exhausted, isTrue);
    expect(s.match.might(heimer), 6);
    store.endSession();
  });
}
