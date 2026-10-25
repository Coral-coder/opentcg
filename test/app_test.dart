// Widget tests: the game picker, and Lorcana's menu with its bundled card database.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentcg/lorcana/lorcana_home.dart';
import 'package:opentcg/lorcana/lorcana_store.dart';
import 'package:opentcg/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_app/tcg_app.dart';

void main() {
  setUp(() {
    Console.available = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the picker lists Magic and Lorcana, both playable', (tester) async {
    await tester.pumpWidget(const OpenTcgApp());
    expect(find.text('Magic: The Gathering'), findsOneWidget);
    expect(find.text('Disney Lorcana'), findsOneWidget);
    expect(find.textContaining('Coming soon'), findsNothing);
  });

  testWidgets('Lorcana loads its cards and starts a game against the computer', (tester) async {
    // A tall phone, so the whole menu (with the online buttons) is laid out.
    tester.view.physicalSize = const Size(780, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => LorcanaStore.shared.init());
    await tester.pumpWidget(ThemeScope(theme: Themes.classic, child: MaterialApp(theme: Themes.classic.material(), home: const LorcanaHome())));
    await tester.pump();
    expect(find.textContaining('cards fully supported'), findsOneWidget);
    expect(find.text('Play online with a code'), findsOneWidget);
    await tester.tap(find.text('Play the computer'));
    await tester.pump(const Duration(milliseconds: 300));
    final s = LorcanaStore.shared.session!;
    expect(s.match.state.players.length, 2);
    expect(s.match.state.player(0).hand.length, 7);
    LorcanaStore.shared.endSession();
  });
}
