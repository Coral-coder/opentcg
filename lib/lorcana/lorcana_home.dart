import 'dart:math';

import 'package:flutter/material.dart' hide Ink;
import 'package:lorcana/lorcana.dart';
import 'package:tcg_core/tcg_core.dart' show SeededRng;
import 'package:tcg_app/tcg_app.dart';

import 'lorcana_cards_screen.dart';
import 'lorcana_deck_choice.dart';
import 'lorcana_decks_screen.dart';
import 'lorcana_lobbies.dart';
import 'lorcana_store.dart';
import 'lorcana_table.dart';

/// Lorcana's menu: play the computer or a friend on this device with saved, starter or random
/// decks; build decks and browse the cards.
class LorcanaHome extends StatefulWidget {
  const LorcanaHome({super.key});
  @override
  State<LorcanaHome> createState() => _LorcanaHomeState();
}

class _LorcanaHomeState extends State<LorcanaHome> {
  final store = LorcanaStore.shared;
  DeckChoice mine = const DeckChoice.random({Ink.amber, Ink.steel});
  DeckChoice theirs = const DeckChoice.random({Ink.ruby, Ink.sapphire});
  String? error;

  @override
  void initState() {
    super.initState();
    store.init().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object e) {
      if (mounted) setState(() => error = '$e');
    });
  }

  void _start({required bool hotseat}) {
    final seed = Random().nextInt(1 << 30);
    final rng = SeededRng(seed);
    final a = mine.cards(store, rng), b = theirs.cards(store, rng);
    if (a == null || b == null || mine.problem(store) != null || theirs.problem(store) != null) return;
    final decks = [a, b];
    store.newGame(names: hotseat ? const ['Player 1', 'Player 2'] : const ['You', 'Computer'], decks: decks, seed: seed, hotseat: hotseat);
    _openTable();
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openTable() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LorcanaTable())).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    if (error != null) return Scaffold(body: Center(child: Text('Could not load the cards: $error')));
    if (!store.ready) return Scaffold(backgroundColor: t.bg, body: const Center(child: CircularProgressIndicator()));
    final (ok, total) = store.coverage;
    final saved = store.savedGame;
    final playable = mine.problem(store) == null && theirs.problem(store) == null;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Disney Lorcana'), backgroundColor: t.panel),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (saved != null) ...[
              ThemedButton('Resume game', subtitle: 'Turn ${saved['turn'] ?? '?'} · ${(saved['names'] as List).join(' vs ')}', tall: true, icon: Icons.play_circle, onPressed: () {
                if (store.resume() != null) _openTable();
              }),
              const SizedBox(height: 16),
            ],
            DeckChooser(label: 'Your deck', value: mine, onChanged: (c) => setState(() => mine = c)),
            const SizedBox(height: 14),
            DeckChooser(label: 'Opponent’s deck', value: theirs, onChanged: (c) => setState(() => theirs = c)),
            const SizedBox(height: 18),
            ThemedButton('Play the computer', tall: true, icon: Icons.smart_toy, onPressed: playable ? () => _start(hotseat: false) : null),
            const SizedBox(height: 10),
            ThemedButton('Play online with a code', subtitle: 'Browser or phone, anywhere', tall: true, icon: Icons.public, color: t.accent2, onPressed: () => _push(LorcanaRemoteLobby(deck: mine))),
            const SizedBox(height: 10),
            if (nearbyPlaySupported) ...[
              ThemedButton('Play nearby', subtitle: 'Wi‑Fi or Bluetooth', tall: true, icon: Icons.wifi_tethering, color: t.accent2, onPressed: () => _push(LorcanaLocalLobby(deck: mine))),
              const SizedBox(height: 10),
            ],
            ThemedButton('Two players, one device', tall: true, icon: Icons.people, outlined: true, onPressed: playable ? () => _start(hotseat: true) : null),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: ThemedButton('Decks', icon: Icons.style, outlined: true, onPressed: () => _push(const LorcanaDecksScreen()))),
              const SizedBox(width: 10),
              Expanded(child: ThemedButton('Cards', icon: Icons.collections, outlined: true, onPressed: () => _push(const LorcanaCardsScreen()))),
            ]),
            const SizedBox(height: 18),
            ThemedPanel(child: Text('$ok of $total cards fully supported. Only supported cards can be played.', style: t.small)),
          ]),
        ),
      ),
    );
  }
}
