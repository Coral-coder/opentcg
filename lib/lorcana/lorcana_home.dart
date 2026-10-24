import 'dart:math';

import 'package:flutter/material.dart' hide Ink;
import 'package:lorcana/lorcana.dart';
import 'package:tcg_core/tcg_core.dart' show SeededRng;
import 'package:tcg_app/tcg_app.dart';

import 'lorcana_card.dart';
import 'lorcana_store.dart';
import 'lorcana_table.dart';

/// Lorcana's menu: play the computer or a friend on this device, with decks of the inks you pick.
class LorcanaHome extends StatefulWidget {
  const LorcanaHome({super.key});
  @override
  State<LorcanaHome> createState() => _LorcanaHomeState();
}

class _LorcanaHomeState extends State<LorcanaHome> {
  final store = LorcanaStore.shared;
  Set<Ink> mine = {Ink.amber, Ink.steel};
  Set<Ink> theirs = {Ink.ruby, Ink.sapphire};
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
    final decks = [randomDeck(store.db, mine, rng), randomDeck(store.db, theirs, rng)];
    store.newGame(names: hotseat ? const ['Player 1', 'Player 2'] : const ['You', 'Computer'], decks: decks, seed: seed, hotseat: hotseat);
    _openTable();
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
    Widget inkPicker(String label, Set<Ink> sel, void Function(Set<Ink>) set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: t.style(14, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final ink in Ink.values)
              FilterChip(
                label: Text(ink.label),
                selected: sel.contains(ink),
                selectedColor: inkColors[ink]!.withValues(alpha: 0.6),
                avatar: CircleAvatar(backgroundColor: inkColors[ink], radius: 7),
                onSelected: (on) {
                  final next = {...sel};
                  if (on) {
                    if (next.length == 2) next.remove(next.first);
                    next.add(ink);
                  } else if (next.length > 1) {
                    next.remove(ink);
                  }
                  setState(() => set(next));
                },
              ),
          ]),
        ]);
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
            inkPicker('Your deck’s inks', mine, (s) => mine = s),
            const SizedBox(height: 14),
            inkPicker('Opponent’s inks', theirs, (s) => theirs = s),
            const SizedBox(height: 18),
            ThemedButton('Play the computer', tall: true, icon: Icons.smart_toy, onPressed: () => _start(hotseat: false)),
            const SizedBox(height: 10),
            ThemedButton('Two players, one device', tall: true, icon: Icons.people, outlined: true, onPressed: () => _start(hotseat: true)),
            const SizedBox(height: 18),
            ThemedPanel(child: Text('$ok of $total cards fully supported. Decks are 60 random supported cards of the chosen inks.', style: t.small)),
          ]),
        ),
      ),
    );
  }
}
