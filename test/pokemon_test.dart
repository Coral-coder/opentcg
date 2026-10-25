// Widget tests for Pokémon: the picker entry, the menu with its bundled cards, a game against the
// computer played by tapping the table, the decision dialog for each kind of question, and the
// card browser.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentcg/main.dart';
import 'package:opentcg/pokemon/pokemon_cards_screen.dart';
import 'package:opentcg/pokemon/pokemon_home.dart';
import 'package:opentcg/pokemon/pokemon_store.dart';
import 'package:opentcg/pokemon/pokemon_table.dart';
import 'package:opentcg/pokemon/pokemon_theme.dart';
import 'package:pokemon/pokemon.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_app/tcg_app.dart';
import 'package:tcg_core/tcg_core.dart' show SeededRng;

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

  testWidgets('the picker lists Pokémon, playable', (tester) async {
    await tester.pumpWidget(const OpenTcgApp());
    expect(find.text('Pokémon TCG'), findsOneWidget);
    expect(find.textContaining('Coming soon'), findsNothing);
  });

  testWidgets('the menu loads the cards, shows coverage and the notice, and starts a game', (tester) async {
    tester.view.physicalSize = const Size(780, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => PokemonStore.shared.init());
    await tester.pumpWidget(MaterialApp(home: const PokemonHome()));
    await tester.pump();
    final (ok, total) = PokemonStore.shared.coverage;
    expect(ok, greaterThan(0));
    expect(find.textContaining('$ok of $total Standard cards'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Not produced by'), 200);
    expect(find.textContaining('Not produced by, endorsed by'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Play the computer'), -200);
    await tester.tap(find.text('Play the computer'));
    await tester.pump(const Duration(milliseconds: 300));
    final s = PokemonStore.shared.session!;
    expect(s.match.state.players.length, 2);
    PokemonStore.shared.endSession();
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });

  testWidgets('a game against the computer is played by tapping the table', (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = PokemonStore.shared;
    await tester.runAsync(() => store.init());
    final rng = SeededRng(3);
    final decks = [randomDeck(store.db, PType.lightning, rng), randomDeck(store.db, PType.fire, rng)];
    final s = store.newGame(names: const ['Trainer', 'Computer'], decks: decks, seed: 11, hotseat: false)..botDelay = 10;
    await tester.pumpWidget(pokemonScope(MaterialApp(theme: pokemonTheme.material(), home: const PokemonTable())));
    var moves = 0, turnsEnded = 0;
    for (var step = 0; step < 120 && turnsEnded < 3 && !s.match.over; step++) {
      await settle(tester, rounds: 5);
      final d = s.match.pending?.decision;
      if (d != null && d.player == s.localSeat) {
        // The dialog opens by itself: answer it by tapping.
        expect(find.byType(PokemonDecisionDialog), findsOneWidget, reason: d.prompt);
        switch (d.kind) {
          case DecisionKind.option:
            await tester.tap(find.text(d.labels.first).last);
          case DecisionKind.yesNo:
            await tester.tap(find.text('Yes'));
          case DecisionKind.cards:
            if (d.min > 0 || d.options.isNotEmpty) {
              await tester.tap(find.bySemanticsLabel(RegExp('^Option: ')).first);
              await tester.pump();
            }
            await tester.tap(find.text('Confirm'));
        }
        await tester.pump();
        continue;
      }
      if (!s.isLocalTurn || s.match.pending != null) continue;
      // Play a glowing hand card through its sheet, or end the turn.
      final playable = find.bySemanticsLabel(RegExp(r'^Hand: .*\(playable\)$'));
      if (playable.evaluate().isNotEmpty && moves < 12) {
        final before = s.match.moves.length;
        await tester.tap(playable.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 50));
        final button = find.byWidgetPredicate((w) => w is ThemedButton && RegExp(r'^(Attach|Put onto|Evolve|Play |Use Ability)').hasMatch(w.label));
        if (button.evaluate().isNotEmpty) {
          await tester.tap(button.first);
          await tester.pump();
          if (s.match.moves.length > before) moves++;
        } else {
          Navigator.of(tester.element(find.byType(PokemonTable))).pop();
        }
        await tester.pump(const Duration(milliseconds: 300));
        continue;
      }
      await tester.tap(find.text('End turn'));
      turnsEnded++;
      await tester.pump();
    }
    expect(moves, greaterThan(0), reason: 'played cards by tapping them');
    expect(turnsEnded, greaterThan(0));
    expect(s.match.state.turn, greaterThan(2), reason: 'the computer took its turns');
    store.endSession();
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });

  testWidgets('the decision dialog answers cards, yes/no and option questions', (tester) async {
    final store = PokemonStore.shared;
    await tester.runAsync(() => store.init());
    final rng = SeededRng(5);
    final s = store.newGame(names: const ['A', 'B'], decks: [randomDeck(store.db, PType.water, rng), randomDeck(store.db, PType.grass, rng)], seed: 7, hotseat: true);
    final hand = s.match.state.player(0).deck.take(3).toList();
    List<int>? answer;
    Future<void> ask(Decision d) async {
      answer = null;
      await tester.pumpWidget(
        pokemonScope(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async => answer = await showDialog<List<int>>(
                  context: context,
                  builder: (_) => pokemonScope(PokemonDecisionDialog(session: s, decision: d)),
                ),
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
    }

    await ask(const Decision(kind: DecisionKind.yesNo, player: 0, prompt: 'Draw a card?'));
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(answer, [0]);

    await ask(const Decision(kind: DecisionKind.option, player: 0, prompt: 'Go first or second?', labels: ['Go first', 'Go second']));
    await tester.tap(find.text('Go second'));
    await tester.pumpAndSettle();
    expect(answer, [1]);

    await ask(Decision(kind: DecisionKind.cards, player: 0, prompt: 'Choose 2', options: hand, min: 2, max: 2));
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

    await ask(Decision(kind: DecisionKind.cards, player: 0, prompt: 'Up to 1', options: hand, min: 0, max: 1));
    await tester.tap(find.text('Look at the table'));
    await tester.pumpAndSettle();
    expect(answer, isNull, reason: 'looking at the table answers nothing');
    store.endSession();
  });

  testWidgets('the card browser searches and filters', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = PokemonStore.shared;
    await tester.runAsync(() => store.init());
    final db = store.db;
    expect(filterPokemonCards(db, const PokemonCardQuery()).length, db.cards.length);
    final supported = filterPokemonCards(db, const PokemonCardQuery(supportedOnly: true));
    expect(supported, isNotEmpty);
    expect(supported.every((c) => PokemonParser.parse(c).supported), isTrue);
    final fire = filterPokemonCards(db, const PokemonCardQuery(type: PType.fire, supertype: Supertype.pokemon));
    expect(fire.every((c) => c.isPokemon && c.types.contains(PType.fire)), isTrue);
    expect(filterPokemonCards(db, const PokemonCardQuery(text: 'pikachu')).any((c) => c.name == 'Pikachu'), isTrue);
    await tester.pumpWidget(pokemonScope(MaterialApp(theme: pokemonTheme.material(), home: const PokemonCardsScreen())));
    await tester.pump();
    expect(find.textContaining('${db.cards.length} cards'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'pikachu');
    await tester.pump();
    expect(find.textContaining('${db.cards.length} cards'), findsNothing);
  });
}
