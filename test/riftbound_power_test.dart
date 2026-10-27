// The Riftbound table shows XP, Empowered cards and spells playable from the trash with Flow.
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

  testWidgets('XP, the Empowered mark and Flow spells in the trash are on the table, and Flow plays from there', (tester) async {
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
    // A position: 3 XP, an Empowered unit, a Flow spell in the trash and runes to pay for it.
    g.state.player(me).pw.xp = 3;
    final u = g.addCard('Brutal Hunter', me, zone: Zone.board);
    g.state.obj(u).pw.empowered = 1;
    final flow = g.addCard('Dredge Up', me, zone: Zone.trash);
    g.addRunes(me, Domain.mind, 2);
    expect(RiftboundPlayable.of(g, me).canPlay(flow), isTrue);

    await tester.pumpWidget(riftboundScope(MaterialApp(theme: riftboundTheme.material(), home: const RiftboundTable())));
    await tester.pump();
    expect(find.text(' 3 XP'), findsWidgets);
    expect(find.byIcon(Icons.bolt), findsWidgets);
    expect(find.text('FLOW · trash'), findsOneWidget);
    final card = find.bySemanticsLabel(RegExp(r'Dredge Up, playable from the trash \(Flow\)$'));
    expect(card, findsOneWidget);

    // Tap it (scrolled into view at the end of the hand) and play it from its sheet.
    await tester.ensureVisible(card);
    await tester.pump();
    await tester.tap(card);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    final play = find.textContaining('Play Dredge Up');
    expect(play, findsOneWidget);
    await tester.tap(play);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    while (s.match.state.chain.isNotEmpty && s.match.pending == null) {
      s.perform(PassMove(s.match.toAct!));
    }
    expect(s.match.state.obj(flow).zone, Zone.banish);
    store.endSession();
  });

  testWidgets('a battlefield\'s granted "{E}: Gain 1 XP." is offered on its units', (tester) async {
    final store = RiftboundStore.shared;
    await tester.runAsync(() => store.init());
    final g = Game(store.db, players: const ['A', 'B'], seed: 1)..setUpEmpty(battlefields: const ['Gardens of Becoming', 'Zaun Warrens']);
    final u = g.addCard('Daring Poro', 0, zone: Zone.board, loc: 0);
    final p = RiftboundPlayable.of(g, 0);
    expect(p.forObject(u).whereType<ActivateMove>().map((m) => m.index), contains(grantedXpAbility));
  });
}
