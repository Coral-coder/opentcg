import 'package:flutter/material.dart';
import 'package:pokemon/pokemon.dart';
import 'package:tcg_app/tcg_app.dart';
import 'package:tcg_core/tcg_core.dart' show SeededRng;

import 'pokemon_store.dart';
import 'pokemon_theme.dart';

/// Which deck a seat plays: a starter deck of a type (always the same 60 cards) or fresh random
/// cards of a type. Both use only fully supported cards.
class PokemonDeckChoice {
  const PokemonDeckChoice.starter(this.type) : random = false;
  const PokemonDeckChoice.random(this.type) : random = true;

  final PType type;
  final bool random;

  /// The cards to play with; random decks draw from [rng].
  List<String> cards(PokemonStore store, SeededRng rng) => randomDeck(store.db, type, random ? rng : SeededRng(1000 + type.index));

  String label(PokemonStore store) => '${random ? 'Random' : 'Starter'}: ${type.label}';
}

/// Picks a [PokemonDeckChoice]: a type, and starter or random cards.
class PokemonDeckChooser extends StatelessWidget {
  const PokemonDeckChooser({super.key, required this.label, required this.value, required this.onChanged});
  final String label;
  final PokemonDeckChoice value;
  final void Function(PokemonDeckChoice) onChanged;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    PokemonDeckChoice make(PType ty, bool random) => random ? PokemonDeckChoice.random(ty) : PokemonDeckChoice.starter(ty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: t.style(15, weight: FontWeight.w800)),
            ),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: false, label: Text('Starter')),
                ButtonSegment(value: true, label: Text('Random')),
              ],
              selected: {value.random},
              onSelectionChanged: (s) => onChanged(make(value.type, s.first)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final ty in deckTypes)
              ChoiceChip(
                label: Text(ty.label),
                selected: value.type == ty,
                showCheckmark: false,
                selectedColor: typeColors[ty]!.withValues(alpha: 0.55),
                avatar: TypePip(ty, size: 18),
                onSelected: (_) => onChanged(make(ty, value.random)),
              ),
          ],
        ),
      ],
    );
  }
}
