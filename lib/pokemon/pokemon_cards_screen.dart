import 'package:flutter/material.dart';
import 'package:pokemon/pokemon.dart';
import 'package:tcg_app/tcg_app.dart';

import 'pokemon_card.dart';
import 'pokemon_store.dart';
import 'pokemon_theme.dart';

/// What the card browser shows.
class PokemonCardQuery {
  const PokemonCardQuery({this.text = '', this.type, this.supertype, this.supportedOnly = false});
  final String text;
  final PType? type;
  final Supertype? supertype;
  final bool supportedOnly;
}

/// The cards matching [q], in database order.
List<PCard> filterPokemonCards(PCardDb db, PokemonCardQuery q) {
  final words = q.text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  return [
    for (final c in db.cards)
      if ((q.type == null || c.types.contains(q.type) || c.energyType == q.type) &&
          (q.supertype == null || c.supertype == q.supertype) &&
          (!q.supportedOnly || PokemonParser.parse(c).supported) &&
          words.every(
            (w) =>
                c.name.toLowerCase().contains(w) ||
                c.attacks.any((a) => a.name.toLowerCase().contains(w) || a.text.toLowerCase().contains(w)) ||
                c.abilities.any((a) => a.name.toLowerCase().contains(w) || a.text.toLowerCase().contains(w)) ||
                c.text.toLowerCase().contains(w),
          ))
        c,
  ];
}

/// Browse every Standard card: search, filter by type and kind, and see which are supported.
class PokemonCardsScreen extends StatefulWidget {
  const PokemonCardsScreen({super.key});
  @override
  State<PokemonCardsScreen> createState() => _PokemonCardsScreenState();
}

class _PokemonCardsScreenState extends State<PokemonCardsScreen> {
  var query = const PokemonCardQuery();

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final db = PokemonStore.shared.db;
    final cards = filterPokemonCards(db, query);
    PokemonCardQuery q({String? text, PType? type, bool clearType = false, Supertype? supertype, bool clearSuper = false, bool? supportedOnly}) => PokemonCardQuery(
      text: text ?? query.text,
      type: clearType ? null : (type ?? query.type),
      supertype: clearSuper ? null : (supertype ?? query.supertype),
      supportedOnly: supportedOnly ?? query.supportedOnly,
    );
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: Text('Cards', style: t.display(24)),
        backgroundColor: t.accent,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search names, attacks and text',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => query = q(text: v)),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                FilterChip(
                  label: const Text('Supported only'),
                  selected: query.supportedOnly,
                  onSelected: (v) => setState(() => query = q(supportedOnly: v)),
                ),
                const SizedBox(width: 6),
                for (final s in Supertype.values) ...[
                  ChoiceChip(
                    label: Text(switch (s) {
                      Supertype.pokemon => 'Pokémon',
                      Supertype.trainer => 'Trainers',
                      Supertype.energy => 'Energy',
                    }),
                    selected: query.supertype == s,
                    onSelected: (on) => setState(() => query = on ? q(supertype: s) : q(clearSuper: true)),
                  ),
                  const SizedBox(width: 6),
                ],
                for (final ty in PType.values) ...[
                  ChoiceChip(
                    avatar: TypePip(ty, size: 18),
                    label: Text(ty.label),
                    selected: query.type == ty,
                    selectedColor: typeColors[ty]!.withValues(alpha: 0.5),
                    onSelected: (on) => setState(() => query = on ? q(type: ty) : q(clearType: true)),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${cards.length} cards', style: t.small),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 150, childAspectRatio: 63 / 100, mainAxisSpacing: 8, crossAxisSpacing: 8),
              itemCount: cards.length,
              itemBuilder: (context, i) {
                final c = cards[i];
                final ok = PokemonParser.parse(c).supported;
                return GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => pokemonScope(PokemonCardDetail(card: c)))),
                  child: Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, box) => PokemonCardView(card: c, width: box.maxWidth),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(ok ? Icons.check_circle : Icons.block, size: 13, color: ok ? t.ok : t.danger),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              ok ? c.name : 'Not supported yet',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.style(11, weight: FontWeight.w700, color: ok ? null : t.danger),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One card, large, with its text and whether the game can play it.
class PokemonCardDetail extends StatelessWidget {
  const PokemonCardDetail({super.key, required this.card});
  final PCard card;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final parsed = PokemonParser.parse(card);
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: Text(card.name, style: t.display(22)),
        backgroundColor: t.accent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: PokemonCardView(card: card, width: 260, large: true)),
          const SizedBox(height: 12),
          ThemedPanel(child: PokemonCardText(card: card)),
          const SizedBox(height: 12),
          ThemedPanel(
            title: parsed.supported ? 'Fully supported' : 'Not supported yet',
            color: parsed.supported ? t.ok : t.danger,
            child: parsed.supported
                ? Text('The game plays every part of this card, so it can go in decks.', style: t.body)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('The game can’t play this text yet, so the card stays out of decks:', style: t.body),
                      for (final u in parsed.unsupported)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('• $u', style: t.style(13, color: t.muted)),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          Text([for (final p in card.printings) '${p.set} ${p.number} · ${p.rarity}'].join('\n'), style: t.small),
        ],
      ),
    );
  }
}
