/// The card database: distinct cards by full name, built from lorcana-api.com's bulk file.
library;

import 'package:tcg_core/tcg_core.dart';

import 'card.dart';

class LCardDb {
  LCardDb(Iterable<LCard> cards, {this.version = ''}) {
    for (final c in cards) {
      _byName[c.fullName] = c;
      _byLower[c.fullName.toLowerCase()] = c;
    }
  }

  final String version;
  final Map<String, LCard> _byName = {};
  final Map<String, LCard> _byLower = {};

  LCard? operator [](String fullName) => _byName[fullName] ?? _byLower[fullName.toLowerCase()];

  /// All cards, sorted by full name.
  List<LCard> get cards => _byName.values.toList()..sortStable((a, b) => a.fullName.compareTo(b.fullName));

  int get length => _byName.length;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'version': version,
    'cards': [for (final c in cards) c.toJson()],
  };

  static LCardDb fromJson(Map<String, dynamic> j) => LCardDb([for (final c in j['cards'] as List) LCard.fromJson(c as Map<String, dynamic>)], version: (j['version'] as String?) ?? '');

  /// Builds the database from the raw bulk list (one entry per printing). Printings of the same
  /// full name become one card; its rules text and stats come from the newest printing.
  /// [fill]: per full name, values from a second source for fields the bulk data lacks (a
  /// location's move cost, an action's text); used only where the bulk data has nothing.
  static LCardDb fromRaw(List<dynamic> raw, {String version = '', Map<String, ({int? moveCost, String text})> fill = const {}}) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in raw) {
      final m = (r as Map).cast<String, dynamic>();
      final name = _cleanName(m['Name'] as String);
      groups.putIfAbsent(name, () => []).add(m);
    }
    final out = <LCard>[];
    final names = groups.keys.toList()..sortStable((a, b) => a.compareTo(b));
    for (final name in names) {
      final ps = groups[name]!..sortStable((a, b) => '${a['Date_Modified'] ?? ''}${a['Unique_ID']}'.compareTo('${b['Date_Modified'] ?? ''}${b['Unique_ID']}'));
      final m = ps.last;
      final typeRaw = (m['Type'] as String? ?? '').toLowerCase();
      final type = typeRaw.startsWith('character')
          ? CardType.character
          : typeRaw.startsWith('action')
          ? CardType.action
          : typeRaw.startsWith('item')
          ? CardType.item
          : CardType.location;
      final classes = [
        for (final s in ((m['Classifications'] as String?) ?? '').split(','))
          if (s.trim().isNotEmpty) s.trim(),
      ];
      if (typeRaw.contains('song') && !classes.contains('Song')) classes.add('Song');
      int? n(String k) => (m[k] is int) ? m[k] as int : int.tryParse('${m[k] ?? ''}');
      out.add(
        LCard(
          fullName: name,
          type: type,
          cost: n('Cost') ?? 0,
          inkable: m['Inkable'] == true,
          inks: [
            for (final s in ((m['Color'] as String?) ?? '').split(','))
              if (Ink.parse(s) != null) Ink.parse(s)!,
          ],
          strength: type == CardType.character ? n('Strength') : null,
          willpower: type == CardType.character || type == CardType.location ? n('Willpower') : null,
          lore: type == CardType.character || type == CardType.location ? n('Lore') : null,
          moveCost: type == CardType.location ? (n('Move_Cost') ?? fill[name]?.moveCost) : null,
          classifications: classes,
          text: _hasRules((m['Body_Text'] as String?) ?? '') ? ((m['Body_Text'] as String?) ?? '').trim() : (fill[name]?.text ?? ((m['Body_Text'] as String?) ?? '').trim()),
          franchise: (m['Franchise'] as String?) ?? '',
          printings: [
            for (final p in ps)
              Printing(
                set: (p['Set_ID'] as String?) ?? '',
                number: (p['Card_Num'] is int) ? p['Card_Num'] as int : 0,
                rarity: (p['Rarity'] as String?) ?? '',
                image: (p['Image'] as String?) ?? '',
                artist: (p['Artist'] as String?) ?? '',
              ),
          ],
        ),
      );
    }
    return LCardDb(out, version: version);
  }

  /// Whether [text] says more than reminder text (some songs in the bulk data carry only their
  /// singing reminder, "- A character with cost N or more can {e} to sing this song for free.").
  static bool _hasRules(String text) {
    final t = text.replaceAll(RegExp(r'\([^)]*\)'), '').replaceAll(RegExp(r'^-? *A character with cost \d+ or more can \{e\} to sing this song for free\.?', multiLine: true, caseSensitive: false), '');
    return t.trim().isNotEmpty;
  }

  static String _cleanName(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').replaceAll(' – ', ' - ');
}
