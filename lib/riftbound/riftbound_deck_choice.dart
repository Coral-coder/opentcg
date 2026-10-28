import 'package:flutter/material.dart';
import 'package:riftbound/riftbound.dart';
import 'package:tcg_app/tcg_app.dart';
import 'package:tcg_core/tcg_core.dart' show SeededRng;

import 'riftbound_store.dart';
import 'riftbound_theme.dart';

/// Which deck a seat plays: a legend's starter deck (always the same cards) or fresh random
/// picks for a legend. Both use only fully supported cards.
class RiftboundDeckChoice {
  const RiftboundDeckChoice.starter(this.legend) : random = false;
  const RiftboundDeckChoice.random(this.legend) : random = true;

  /// The Champion Legend's name, or null for any legend (random).
  final String? legend;
  final bool random;

  /// The cards to play with; random picks come from [rng].
  List<String> cards(RiftboundStore store, SeededRng rng) {
    final db = store.db;
    final legends = [for (final n in store.legendNames) db[n]!];
    final l = legends.where((x) => x.name == legend).firstOrNull ?? legends[rng.nextInt(legends.length)];
    return buildDeck(db, l, rng: random ? rng : null);
  }

  String label(RiftboundStore store) => '${random ? 'Random' : 'Starter'}: ${legend ?? 'any legend'}';
}

/// Decks for every seat of [mode]: [mine] in seat 0 and starter decks of random legends for the
/// rest, never a teammate's legend in 2v2 (CR 491.8.h).
List<List<String>> riftboundDecksFor(RMode mode, List<String> mine, SeededRng rng) {
  final store = RiftboundStore.shared;
  final db = store.db;
  final decks = <List<String>>[mine];
  for (var p = 1; p < mode.players; p++) {
    final taken = {if (mode == RMode.teams && p >= 2) deckLegend(db, decks[p - 2])?.name};
    final legends = [for (final n in store.legendNames) if (!taken.contains(n)) db[n]!];
    decks.add(buildDeck(db, legends[rng.nextInt(legends.length)]));
  }
  return decks;
}

/// The Mode of Play: Duel, Skirmish, War or Magma Chamber (CR 486–491).
class RiftboundModePicker extends StatelessWidget {
  const RiftboundModePicker({super.key, required this.value, required this.onChanged});
  final RMode value;
  final void Function(RMode) onChanged;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    String blurb(RMode m) => switch (m) {
      RMode.duel => '1 v 1 · first to 8',
      RMode.ffa3 => '3 players · first to 8',
      RMode.ffa4 => '4 players · first to 8',
      RMode.teams => '2 v 2 · teams share points · first to 11',
    };
    return HexPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Mode', style: t.display(17, color: t.accent)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in RMode.values)
                ChoiceChip(
                  label: Text(m.label),
                  selected: value == m,
                  showCheckmark: false,
                  selectedColor: const Color(0x55C8AA6E),
                  side: BorderSide(color: value == m ? t.accent : const Color(0x33C8AA6E)),
                  onSelected: (_) => onChanged(m),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(blurb(value), style: t.style(12, color: t.muted)),
        ],
      ),
    );
  }
}

/// Picks a [RiftboundDeckChoice]: a legend, and its starter deck or random picks.
class RiftboundDeckChooser extends StatelessWidget {
  const RiftboundDeckChooser({super.key, required this.label, required this.value, required this.onChanged});
  final String label;
  final RiftboundDeckChoice value;
  final void Function(RiftboundDeckChoice) onChanged;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final store = RiftboundStore.shared;
    final legends = [for (final n in store.legendNames) store.db[n]!];
    RiftboundDeckChoice make(String? l, bool random) => random ? RiftboundDeckChoice.random(l) : RiftboundDeckChoice.starter(l);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: t.display(17, color: t.accent))),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: false, label: Text('Starter')),
                ButtonSegment(value: true, label: Text('Random')),
              ],
              selected: {value.random},
              onSelectionChanged: (s) => onChanged(make(value.legend, s.first)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final l in legends)
              ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final d in l.domains) Padding(padding: const EdgeInsets.only(right: 2), child: DomainPip(d, size: 13)),
                    const SizedBox(width: 3),
                    Text(l.shortName),
                  ],
                ),
                selected: value.legend == l.name,
                showCheckmark: false,
                selectedColor: const Color(0x55C8AA6E),
                side: BorderSide(color: value.legend == l.name ? t.accent : const Color(0x33C8AA6E)),
                onSelected: (_) => onChanged(make(l.name, value.random)),
              ),
          ],
        ),
      ],
    );
  }
}
