import 'package:flutter/material.dart' hide Ink;
import 'package:lorcana/lorcana.dart';
import 'package:tcg_app/tcg_app.dart';
import 'package:tcg_core/tcg_core.dart' show SeededRng;

import 'lorcana_card.dart';
import 'lorcana_decks.dart';
import 'lorcana_store.dart';
import 'lorcana_theme.dart';

enum DeckSource { saved, starter, random }

/// Which deck a seat plays: a saved deck, a starter deck, or random cards of two inks.
class DeckChoice {
  const DeckChoice.random(this.inks)
      : source = DeckSource.random,
        deckId = null;
  const DeckChoice.starter(this.inks)
      : source = DeckSource.starter,
        deckId = null;
  const DeckChoice.saved(String this.deckId)
      : source = DeckSource.saved,
        inks = const {};

  final DeckSource source;
  final String? deckId;
  final Set<Ink> inks;

  /// The cards to play with (random decks draw from [rng]); null if a saved deck is gone.
  List<String>? cards(LorcanaStore store, SeededRng rng) => switch (source) {
        DeckSource.saved => store.decks.byId(deckId!)?.cards,
        DeckSource.starter => starterDeck(store.db, inks),
        DeckSource.random => randomDeck(store.db, inks, rng),
      };

  /// Why it can't be played, or null. Only supported cards may be used in games.
  String? problem(LorcanaStore store) {
    if (source != DeckSource.saved) return null;
    final d = store.decks.byId(deckId!);
    if (d == null) return 'That deck was deleted.';
    final p = validateDeck(store.db, d.cards);
    return p.isEmpty ? null : p.first;
  }

  String label(LorcanaStore store) => switch (source) {
        DeckSource.saved => store.decks.byId(deckId!)?.name ?? 'Deleted deck',
        DeckSource.starter => 'Starter: ${inkPairName(inks)}',
        DeckSource.random => 'Random: ${inkPairName(inks)}',
      };
}

/// Picks a [DeckChoice]: a dropdown of saved and starter decks, and random decks with ink chips.
class DeckChooser extends StatelessWidget {
  const DeckChooser({super.key, required this.label, required this.value, required this.onChanged});
  final String label;
  final DeckChoice value;
  final void Function(DeckChoice) onChanged;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final store = LorcanaStore.shared;
    // Dropdown entries by key: 'random', 'starter:<pair>', 'saved:<id>'.
    String keyOf(DeckChoice c) => switch (c.source) {
          DeckSource.random => 'random',
          DeckSource.starter => 'starter:${inkPairName(c.inks)}',
          DeckSource.saved => 'saved:${c.deckId}',
        };
    final pairs = allInkPairs();
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'random', child: Text('Random cards of two inks')),
      for (final d in store.decks.decks) DropdownMenuItem(value: 'saved:${d.id}', child: Text(d.name, overflow: TextOverflow.ellipsis)),
      for (final p in pairs) DropdownMenuItem(value: 'starter:${inkPairName(p)}', child: Text('Starter: ${inkPairName(p)}')),
    ];
    final current = keyOf(value);
    final problem = value.problem(store);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      EnchantedTitle(label, size: 16),
      DropdownButton<String>(
        isExpanded: true,
        dropdownColor: const Color(0xFF221E5C),
        style: t.style(14),
        value: items.any((i) => i.value == current) ? current : 'random',
        items: items,
        onChanged: (k) {
          if (k == null) return;
          if (k == 'random') {
            onChanged(DeckChoice.random(value.inks.length == 2 ? value.inks : {Ink.amber, Ink.steel}));
          } else if (k.startsWith('saved:')) {
            onChanged(DeckChoice.saved(k.substring(6)));
          } else {
            onChanged(DeckChoice.starter(pairs.firstWhere((p) => 'starter:${inkPairName(p)}' == k)));
          }
        },
      ),
      if (value.source == DeckSource.random)
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final ink in Ink.values)
            FilterChip(
              label: Text(ink.label),
              selected: value.inks.contains(ink),
              selectedColor: inkColors[ink]!.withValues(alpha: 0.6),
              avatar: InkBlot(inks: [ink], size: 18),
              onSelected: (on) {
                final next = {...value.inks};
                if (on) {
                  if (next.length == 2) next.remove(next.first);
                  next.add(ink);
                } else if (next.length > 1) {
                  next.remove(ink);
                }
                onChanged(DeckChoice.random(next));
              },
            ),
        ]),
      if (problem != null) Text('Can’t play this deck yet: $problem', style: t.style(12, color: t.danger)),
    ]);
  }
}
