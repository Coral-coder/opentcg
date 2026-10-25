import 'package:flutter/material.dart' hide Ink;
import 'package:lorcana/lorcana.dart';
import 'package:tcg_app/tcg_app.dart';

import 'lorcana_card.dart';
import 'lorcana_store.dart';

/// What the card browser shows.
class CardQuery {
  CardQuery({this.text = '', Set<Ink>? inks, Set<CardType>? types, Set<int>? costs, this.set, this.rarity, this.inkable, this.supportedOnly = false})
      : inks = inks ?? {},
        types = types ?? {},
        costs = costs ?? {};

  /// Matched against the name, rules text and classifications.
  String text;

  /// Any of these inks (empty: all).
  Set<Ink> inks;
  Set<CardType> types;

  /// Costs; 9 means 9 or more.
  Set<int> costs;
  String? set, rarity;
  bool? inkable;
  bool supportedOnly;
}

bool _supported(LCard c) => LorcanaParser.parse(c).supported;

/// Cards matching [q], by name.
List<LCard> filterCards(LCardDb db, CardQuery q) {
  final words = q.text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  return [
    for (final c in db.cards)
      if ((q.inks.isEmpty || c.inks.any(q.inks.contains)) &&
          (q.types.isEmpty || q.types.contains(c.type)) &&
          (q.costs.isEmpty || q.costs.contains(c.cost >= 9 ? 9 : c.cost)) &&
          (q.set == null || c.printings.any((p) => p.set == q.set)) &&
          (q.rarity == null || c.printings.any((p) => p.rarity == q.rarity)) &&
          (q.inkable == null || c.inkable == q.inkable) &&
          (!q.supportedOnly || _supported(c)) &&
          words.every((w) => '${c.fullName} ${c.text} ${c.classifications.join(' ')}'.toLowerCase().contains(w)))
        c,
  ];
}

/// Set codes and rarities in the database, for the filters.
(List<String>, List<String>) setsAndRarities(LCardDb db) {
  final sets = <String>{}, rarities = <String>{};
  for (final c in db.cards) {
    for (final p in c.printings) {
      sets.add(p.set);
      rarities.add(p.rarity);
    }
  }
  return (sets.toList()..sort(), rarities.toList()..sort());
}

/// Browse and search every card. With [onPick], tapping a card offers to add it (deck editor).
class LorcanaCardsScreen extends StatefulWidget {
  const LorcanaCardsScreen({super.key, this.onPick, this.title = 'Cards', this.initial});
  final void Function(LCard card)? onPick;
  final String title;
  final CardQuery? initial;

  @override
  State<LorcanaCardsScreen> createState() => _LorcanaCardsScreenState();
}

class _LorcanaCardsScreenState extends State<LorcanaCardsScreen> {
  late final CardQuery q = widget.initial ?? CardQuery(supportedOnly: widget.onPick != null);
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.text = q.text;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final db = LorcanaStore.shared.db;
    final results = filterCards(db, q);
    final (sets, rarities) = setsAndRarities(db);
    Widget chip(String label, bool on, VoidCallback tap, {Color? color}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: FilterChip(
            label: Text(label),
            selected: on,
            selectedColor: (color ?? t.accent).withValues(alpha: 0.55),
            avatar: color == null ? null : CircleAvatar(backgroundColor: color, radius: 6),
            onSelected: (_) => setState(tap),
          ),
        );
    Widget row(List<Widget> kids) => SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, children: kids));
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: Text(widget.title), backgroundColor: t.panel),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Name, rules text or classification', isDense: true),
            onChanged: (v) => setState(() => q.text = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Column(children: [
            row([for (final ink in Ink.values) chip(ink.label, q.inks.contains(ink), () => q.inks.contains(ink) ? q.inks.remove(ink) : q.inks.add(ink), color: inkColors[ink])]),
            row([
              for (final ty in CardType.values) chip(_typeLabel(ty), q.types.contains(ty), () => q.types.contains(ty) ? q.types.remove(ty) : q.types.add(ty)),
              chip('Inkable', q.inkable == true, () => q.inkable = q.inkable == true ? null : true),
              chip('Not inkable', q.inkable == false, () => q.inkable = q.inkable == false ? null : false),
            ]),
            row([for (var c = 0; c <= 9; c++) chip(c == 9 ? '9+' : '$c', q.costs.contains(c), () => q.costs.contains(c) ? q.costs.remove(c) : q.costs.add(c))]),
            Row(children: [
              Expanded(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: q.set,
                  hint: const Text('Any set'),
                  items: [const DropdownMenuItem(value: null, child: Text('Any set')), for (final s in sets) DropdownMenuItem(value: s, child: Text(s))],
                  onChanged: (v) => setState(() => q.set = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: q.rarity,
                  hint: const Text('Any rarity'),
                  items: [const DropdownMenuItem(value: null, child: Text('Any rarity')), for (final r in rarities) DropdownMenuItem(value: r, child: Text(r))],
                  onChanged: (v) => setState(() => q.rarity = v),
                ),
              ),
            ]),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: q.supportedOnly,
              onChanged: (v) => setState(() => q.supportedOnly = v),
              title: Text('Fully supported only', style: t.body),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(alignment: Alignment.centerLeft, child: Text('${results.length} cards', style: t.small)),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, childAspectRatio: 5 / 7.6, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemCount: results.length,
            itemBuilder: (context, i) {
              final c = results[i];
              return GestureDetector(
                key: ValueKey(c.fullName),
                onTap: () => _open(context, c),
                child: Column(children: [
                  Expanded(child: FittedBox(child: LorcanaCardView(card: c, width: 120))),
                  Text(c.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.style(10, weight: FontWeight.w600)),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }

  void _open(BuildContext context, LCard c) {
    final pick = widget.onPick;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LorcanaCardDetail(card: c, onAdd: pick == null ? null : () => pick(c))));
  }
}

String _typeLabel(CardType t) => switch (t) { CardType.character => 'Character', CardType.action => 'Action', CardType.item => 'Item', CardType.location => 'Location' };

/// One card large: the whole image, its details, printings, and whether the engine plays it.
class LorcanaCardDetail extends StatelessWidget {
  const LorcanaCardDetail({super.key, required this.card, this.onAdd});
  final LCard card;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final parsed = LorcanaParser.parse(card);
    final c = card;
    final stats = [
      'Cost ${c.cost}${c.inkable ? ' (inkable)' : ''}',
      if (c.strength != null) 'Strength ${c.strength}',
      if (c.willpower != null) 'Willpower ${c.willpower}',
      if (c.lore != null) 'Lore ${c.lore}',
      if (c.moveCost != null) 'Move cost ${c.moveCost}',
    ].join(' · ');
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: Text(c.name), backgroundColor: t.panel),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Center(child: LorcanaCardView(card: c, width: 280)),
            const SizedBox(height: 12),
            Text(c.fullName, style: t.style(20, weight: FontWeight.w800)),
            Text(
              [_typeLabel(c.type), ...c.classifications].join(' · '),
              style: t.small,
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [for (final i in c.inks) Chip(avatar: CircleAvatar(backgroundColor: inkColors[i], radius: 6), label: Text(i.label))]),
            Text(stats, style: t.body),
            if (c.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(c.text, style: t.body)),
            const SizedBox(height: 12),
            ThemedPanel(
              title: parsed.supported ? 'Fully supported' : 'Not supported yet',
              color: parsed.supported ? t.ok : t.danger,
              child: parsed.supported
                  ? Text('The rules engine plays every ability on this card.', style: t.small)
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('The engine can’t read this text yet, so the card can’t be used in games:', style: t.small),
                      for (final u in parsed.unsupported) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $u', style: t.style(13, color: t.danger))),
                    ]),
            ),
            const SizedBox(height: 12),
            Text('Printings', style: t.style(15, weight: FontWeight.w700)),
            for (final p in c.printings) Text('${p.set} #${p.number} · ${p.rarity}${p.artist.isEmpty ? '' : ' · ${p.artist}'}', style: t.small),
            if (onAdd != null) ...[
              const SizedBox(height: 16),
              ThemedButton(parsed.supported ? 'Add to deck' : 'Not playable yet', icon: Icons.add, tall: true, onPressed: parsed.supported ? onAdd! : null),
            ],
          ]),
        ),
      ),
    );
  }
}
