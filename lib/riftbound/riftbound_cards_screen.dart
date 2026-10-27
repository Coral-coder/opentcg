import 'package:flutter/material.dart';
import 'package:riftbound/riftbound.dart';
import 'package:tcg_app/tcg_app.dart';

import 'riftbound_card.dart';
import 'riftbound_store.dart';
import 'riftbound_theme.dart';

/// What the card browser shows.
class RiftboundCardQuery {
  const RiftboundCardQuery({this.text = '', this.type, this.domain, this.supportedOnly = false});
  final String text;
  final CardType? type;
  final Domain? domain;
  final bool supportedOnly;
}

/// The cards matching [q], in database order.
List<RCard> filterRiftboundCards(RCardDb db, RiftboundCardQuery q) {
  final words = q.text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  return [
    for (final c in db.cards)
      if ((q.type == null || c.type == q.type) &&
          (q.domain == null || c.domains.contains(q.domain)) &&
          (!q.supportedOnly || RiftboundParser.parse(c).supported) &&
          words.every((w) => c.name.toLowerCase().contains(w) || c.text.toLowerCase().contains(w) || c.tags.any((x) => x.toLowerCase().contains(w))))
        c,
  ];
}

/// Browse every card: search, filter by type and domain, and see which are supported.
class RiftboundCardsScreen extends StatefulWidget {
  const RiftboundCardsScreen({super.key});
  @override
  State<RiftboundCardsScreen> createState() => _RiftboundCardsScreenState();
}

class _RiftboundCardsScreenState extends State<RiftboundCardsScreen> {
  var query = const RiftboundCardQuery();

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final db = RiftboundStore.shared.db;
    final cards = filterRiftboundCards(db, query);
    RiftboundCardQuery q({String? text, CardType? type, bool clearType = false, Domain? domain, bool clearDomain = false, bool? supportedOnly}) => RiftboundCardQuery(
      text: text ?? query.text,
      type: clearType ? null : (type ?? query.type),
      domain: clearDomain ? null : (domain ?? query.domain),
      supportedOnly: supportedOnly ?? query.supportedOnly,
    );
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: Text('Cards', style: t.display(24, color: t.accent))),
      body: Stack(
        children: [
          const Positioned.fill(child: HextechBackdrop()),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: TextField(
                  decoration: const InputDecoration(hintText: 'Search names, text and tags', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
                  onChanged: (v) => setState(() => query = q(text: v)),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  children: [
                    FilterChip(label: const Text('Supported only'), selected: query.supportedOnly, onSelected: (v) => setState(() => query = q(supportedOnly: v))),
                    const SizedBox(width: 6),
                    for (final ty in const [CardType.unit, CardType.spell, CardType.gear, CardType.legend, CardType.battlefield])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(ty.name[0].toUpperCase() + ty.name.substring(1)),
                          selected: query.type == ty,
                          onSelected: (on) => setState(() => query = on ? q(type: ty) : q(clearType: true)),
                        ),
                      ),
                    for (final d in Domain.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          avatar: DomainPip(d, size: 14),
                          label: Text(d.label),
                          selected: query.domain == d,
                          onSelected: (on) => setState(() => query = on ? q(domain: d) : q(clearDomain: true)),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(alignment: Alignment.centerLeft, child: Text('${cards.length} cards', style: t.small)),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, childAspectRatio: 0.6, mainAxisSpacing: 8, crossAxisSpacing: 8),
                  itemCount: cards.length,
                  itemBuilder: (context, i) {
                    final c = cards[i];
                    final ok = RiftboundParser.parse(c).supported;
                    return GestureDetector(
                      onTap: () => _detail(context, c),
                      child: Column(
                        children: [
                          Expanded(child: FittedBox(child: RiftboundCardView(card: c, width: 120))),
                          Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.style(11, weight: FontWeight.w700)),
                          Text(ok ? 'Supported' : 'Not yet', style: t.style(10, color: ok ? t.ok : t.muted)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _detail(BuildContext context, RCard c) {
    final p = RiftboundParser.parse(c);
    showDialog<void>(
      context: context,
      builder: (d) => riftboundScope(
        Builder(
          builder: (d) {
            final t = GameTheme.of(d);
            return Dialog(
              backgroundColor: riftboundTheme.surface,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: RiftboundCardView(card: c, width: 240)),
                    const SizedBox(height: 10),
                    Text(c.name, style: t.display(20, color: t.accent)),
                    Text('${c.type.name}${c.tags.isEmpty ? '' : ' · ${c.tags.join(', ')}'}${c.isMainDeck ? ' · ${c.energy} Energy${c.power > 0 ? ' + ${c.power} Power' : ''}' : ''}${c.might == null ? '' : ' · ${c.might} Might'}', style: t.small),
                    const SizedBox(height: 6),
                    Text(c.text.isEmpty ? '(No rules text.)' : c.text, style: t.style(14, weight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Text(p.supported ? 'Fully supported.' : 'Not supported yet: ${p.unsupported.join(' / ')}', style: t.style(12, color: p.supported ? t.ok : t.danger)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
