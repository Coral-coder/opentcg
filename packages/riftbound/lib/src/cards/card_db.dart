/// The card database: built from Riftcodex's card list (bin/build_db.dart), stored as compact
/// JSON, looked up by card name.
library;

import 'package:tcg_core/tcg_core.dart';

import 'card.dart';

class RCardDb {
  RCardDb(List<RCard> cards, {this.version = ''}) : cards = List.unmodifiable(cards) {
    for (final c in cards) {
      _byKey[c.key] = c;
    }
    for (final t in tokens) {
      _byKey.putIfAbsent(t.key, () => t);
    }
  }

  final List<RCard> cards;
  final String version;
  final Map<String, RCard> _byKey = {};

  RCard? operator [](String key) => _byKey[key];

  Map<String, dynamic> toJson() => {'v': 1, 'version': version, 'cards': [for (final c in cards) c.toJson()]};

  static RCardDb fromJson(Map<String, dynamic> j) => RCardDb([for (final c in j['cards'] as List) RCard.fromJson(c as Map<String, dynamic>)], version: (j['version'] as String?) ?? '');

  /// The token objects of CR 187, by name. "Recruit" etc. are what card text plays.
  static final List<RCard> tokens = [
    const RCard(name: 'Recruit', type: CardType.unit, token: true, might: 1, tags: ['Recruit']),
    const RCard(name: 'Sprite', type: CardType.unit, token: true, might: 3, tags: ['Fae'], text: '[Temporary]'),
    const RCard(name: 'Sand Soldier', type: CardType.unit, token: true, might: 2, tags: ['Shurima']),
    const RCard(name: 'Mech', type: CardType.unit, token: true, might: 3, tags: ['Mech']),
    const RCard(name: 'Reflection', type: CardType.unit, token: true, might: 0),
    const RCard(name: 'Bird', type: CardType.unit, token: true, might: 1, tags: ['Bird'], text: '[Deflect]'),
    const RCard(name: 'Tentacle', type: CardType.unit, token: true, might: 1, tags: ['Bilgewater']),
    const RCard(name: 'Shadow Clone', type: CardType.unit, token: true, might: 0, text: 'When I attack, you may banish a unit from your trash. If you do, give me [Assault 4] this turn.'),
    const RCard(name: 'Gold', type: CardType.gear, token: true, text: '[Reaction] Kill this, {E}: [Add] {A}.'),
  ];

  /// From Riftcodex card objects (https://api.riftcodex.com/cards, all pages). Alternate-art and
  /// overnumbered printings are left out; the printings of one name become one card, with its
  /// text from its main-set, non-signature printing.
  static RCardDb fromRaw(List<Map<String, dynamic>> raw, {String version = ''}) {
    final groups = <String, List<Map<String, dynamic>>>{};
    final order = <String>[];
    for (final c in raw) {
      final m = (c['metadata'] as Map?) ?? const {};
      if (m['alternate_art'] == true || m['overnumbered'] == true) continue;
      final name = cardName(c['name'] as String);
      if (!groups.containsKey(name)) order.add(name);
      groups.putIfAbsent(name, () => []).add(c);
    }
    // Variant printings with the same text are the same card: "Jinx, Loose Cannon (Metal)",
    // "Annie, Dark Child (Starter)", and legends listed by subtitle only ("Butcher of the Sands").
    String textOf(String n) => normaliseText(((groups[n]!.first['text'] as Map?)?['rich'] as String?) ?? '');
    String typeOf(String n) => ((groups[n]!.first['classification'] as Map)['type'] as String).toLowerCase();
    for (final n in List.of(order)) {
      String? into;
      final v = RegExp(r'^(.+) \([^)]+\)$').firstMatch(n);
      if (v != null && groups.containsKey(v[1]) && v[1] != n) {
        into = v[1];
      } else if (!n.contains(', ')) {
        into = order.where((o) => o != n && o.endsWith(', $n')).firstOrNull;
      }
      if (into == null || textOf(into) != textOf(n) || typeOf(into) != typeOf(n)) continue;
      groups[into]!.addAll(groups.remove(n)!);
      order.remove(n);
    }
    final cards = <RCard>[];
    for (final name in order) {
      final g = groups[name]!.toList()..sortStable((a, b) => _rank(a) - _rank(b));
      final c = g.first;
      final cl = c['classification'] as Map<String, dynamic>;
      final at = c['attributes'] as Map<String, dynamic>;
      final type = switch ((cl['type'] as String).toLowerCase()) {
        'unit' => CardType.unit,
        'spell' => CardType.spell,
        'gear' => CardType.gear,
        'legend' => CardType.legend,
        'battlefield' => CardType.battlefield,
        _ => CardType.rune,
      };
      final sup = (cl['supertype'] as String?)?.toLowerCase();
      if (sup == 'token') continue; // Tokens are built in (CR 187).
      cards.add(RCard(
        name: name,
        type: type,
        champion: sup == 'champion',
        signature: sup == 'signature',
        domains: [for (final d in (cl['domain'] as List?) ?? const []) ?Domain.byName(d as String)],
        energy: (at['energy'] as int?) ?? 0,
        power: (at['power'] as int?) ?? 0,
        might: type == CardType.unit ? (at['might'] as int?) ?? 0 : null,
        tags: [for (final t in (c['tags'] as List?) ?? const []) t as String],
        text: normaliseText(((c['text'] as Map?)?['rich'] as String?) ?? ''),
        printings: [
          for (final p in g)
            Printing(((p['set'] as Map)['set_id'] as String).toUpperCase(), '${p['collector_number'] ?? ''}', ((p['media'] as Map?)?['image_url'] as String?) ?? ''),
        ],
      ));
    }
    cards.sortStable((a, b) => a.key.compareTo(b.key));
    return RCardDb(cards, version: version);
  }

  /// Main sets first, then promos; signature printings last.
  static int _rank(Map<String, dynamic> c) {
    final set = (((c['set'] as Map?)?['set_id'] as String?) ?? '').toUpperCase();
    final main = const ['OGN', 'SFD', 'UNL', 'VEN'].indexOf(set);
    final sig = ((c['metadata'] as Map?)?['signature'] == true) ? 100 : 0;
    return sig + (main < 0 ? 10 : main);
  }

  /// "Jinx - Demolitionist (Signature)" → "Jinx, Demolitionist" (CR 132.4).
  static String cardName(String raw) => raw.replaceAll(' (Signature)', '').replaceFirst(' - ', ', ').trim();

  /// Rich text → one ability per line, reminder text removed, symbols as {…} (see [RCard.text]).
  static String normaliseText(String rich) {
    // A bulleted list of modes stays on the line that introduces it: "Choose one - • A • B" (CR 355.3).
    var t = rich.replaceAll(RegExp(r'</p>\s*<ul>'), ' ').replaceAll('<ul>', ' ').replaceAll('</ul>', '\n').replaceAll('<li>', ' • ').replaceAll('</li>', '');
    t = t.replaceAll(RegExp(r'<br\s*/?>'), '\n').replaceAll('</p>', '\n').replaceAll(RegExp(r'<[^>]+>'), '');
    t = t.replaceAll('&gt;', '>').replaceAll('&lt;', '<').replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&#39;', "'").replaceAll('&#x27;', "'");
    t = t.replaceAllMapped(RegExp(r':rb_energy_(\d+):'), (m) => '{${m[1]}}');
    const runes = {'fury': 'R', 'calm': 'G', 'mind': 'B', 'body': 'O', 'chaos': 'P', 'order': 'Y', 'rainbow': 'A'};
    t = t.replaceAllMapped(RegExp(r':rb_rune_([a-z]+):'), (m) => '{${runes[m[1]] ?? '?'}}');
    t = t.replaceAll(':rb_might:', '{M}').replaceAll(':rb_exhaust:', '{E}');
    t = t.replaceAll('[S]', '{M}').replaceAll('[T]', '{E}');
    // Reminder text (CR 135.2.d) has no effect on play.
    for (var i = 0; i < 3; i++) {
      t = t.replaceAll(RegExp(r'\s*\([^()]*\)'), '');
    }
    t = t.replaceAll('’', "'").replaceAll('“', '"').replaceAll('”', '"').replaceAll('—', '-').replaceAll('–', '-');
    t = t.replaceAll('[NO TEXT]', '');
    final lines = [
      for (final l in t.split('\n'))
        if (l.trim().isNotEmpty) l.replaceAll(RegExp(r'[ \t]+'), ' ').trim(),
    ];
    return lines.join('\n');
  }
}
