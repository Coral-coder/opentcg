import 'dart:convert';

import 'package:lorcana/lorcana.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_core/tcg_core.dart' show SeededRng, StableSort;

/// A saved Lorcana deck: a name and its card list (full names, one entry per copy).
class LorcanaDeck {
  LorcanaDeck({required this.id, required this.name, required List<String> cards}) : cards = List.of(cards);
  final String id;
  String name;
  final List<String> cards;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'cards': cards};

  static LorcanaDeck fromJson(Map<String, dynamic> j) => LorcanaDeck(id: j['id'] as String, name: j['name'] as String, cards: (j['cards'] as List).cast<String>());

  /// Copies of each full name, in the order first added.
  Map<String, int> get counts {
    final out = <String, int>{};
    for (final c in cards) {
      out[c] = (out[c] ?? 0) + 1;
    }
    return out;
  }

  int count(String name) => cards.where((c) => c == name).length;

  /// Sets the copies of [name] to [n] (0 removes it).
  void setCount(String name, int n) {
    cards.removeWhere((c) => c == name);
    for (var i = 0; i < n; i++) {
      cards.add(name);
    }
  }
}

/// The player's saved decks, kept in SharedPreferences as JSON.
class LorcanaDeckBook {
  static const _key = 'lorcana.decks';
  SharedPreferences? _prefs;
  final List<LorcanaDeck> decks = [];
  int _nextId = 1;

  void load(SharedPreferences prefs) {
    _prefs = prefs;
    decks.clear();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      for (final d in jsonDecode(raw) as List) {
        decks.add(LorcanaDeck.fromJson((d as Map).cast<String, dynamic>()));
      }
    } catch (_) {
      decks.clear();
    }
    for (final d in decks) {
      final n = int.tryParse(d.id.replaceFirst('d', '')) ?? 0;
      if (n >= _nextId) _nextId = n + 1;
    }
  }

  void save() => _prefs?.setString(_key, jsonEncode([for (final d in decks) d.toJson()]));

  LorcanaDeck? byId(String id) {
    for (final d in decks) {
      if (d.id == id) return d;
    }
    return null;
  }

  LorcanaDeck create(String name, [List<String> cards = const []]) {
    final d = LorcanaDeck(id: 'd${_nextId++}', name: name, cards: cards);
    decks.add(d);
    save();
    return d;
  }

  LorcanaDeck duplicate(LorcanaDeck d) => create('${d.name} (copy)', d.cards);

  void delete(LorcanaDeck d) {
    decks.removeWhere((x) => x.id == d.id);
    save();
  }
}

/// Inks used by [cards] (in ink order).
List<Ink> deckInks(LCardDb db, Iterable<String> cards) {
  final s = <Ink>{};
  for (final n in cards) {
    s.addAll(db[n]?.inks ?? const []);
  }
  return [for (final i in Ink.values) if (s.contains(i)) i];
}

/// "4 Name - Version" lines, by cost then name.
String formatDeckList(LCardDb db, List<String> cards) {
  final counts = <String, int>{};
  for (final c in cards) {
    counts[c] = (counts[c] ?? 0) + 1;
  }
  final names = counts.keys.toList()
    ..sortStable((a, b) {
      final ca = db[a]?.cost ?? 99, cb = db[b]?.cost ?? 99;
      return ca != cb ? ca - cb : a.compareTo(b);
    });
  return [for (final n in names) '${counts[n]} $n'].join('\n');
}

/// Reads a deck list: one card per line as "4 Name - Version", "4x Name", or just "Name" (one
/// copy). Names match case-insensitively, and an en/em dash or a missing space around the dash
/// is accepted. Returns the cards and a message for each line that couldn't be read.
(List<String>, List<String>) parseDeckList(LCardDb db, String text) {
  final cards = <String>[];
  final errors = <String>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;
    final m = RegExp(r'^(\d+)\s*[xX]?\s+(.+)$').firstMatch(line);
    final n = m == null ? 1 : int.parse(m.group(1)!);
    final name = (m == null ? line : m.group(2)!).trim();
    // The name/version separator may come as an en or em dash, or a hyphen with a space on
    // either side; hyphens inside names ("Hard-Nosed") stay.
    final dashed = name.replaceAll(RegExp(r'\s*[–—]\s*|\s+-\s*|\s*-\s+'), ' - ');
    LCard? find(String n) => db[n] ?? db[n.replaceAll('’', "'")] ?? db[n.replaceAll("'", '’')];
    final c = find(name) ?? find(dashed);
    if (c == null) {
      errors.add('Unknown card: $name');
      continue;
    }
    for (var i = 0; i < n; i++) {
      cards.add(c.fullName);
    }
  }
  return (cards, errors);
}

/// Every pair of inks, in ink order.
List<Set<Ink>> allInkPairs() => [
      for (var i = 0; i < Ink.values.length; i++)
        for (var j = i + 1; j < Ink.values.length; j++) {Ink.values[i], Ink.values[j]},
    ];

String inkPairName(Set<Ink> inks) => [for (final i in Ink.values) if (inks.contains(i)) i.label].join('/');

/// A starter deck for [inks]: 60 supported cards, the same every time (seeded by the pair).
List<String> starterDeck(LCardDb db, Set<Ink> inks) {
  var seed = 17;
  for (final i in Ink.values) {
    seed = seed * 31 + (inks.contains(i) ? i.index + 1 : 0);
  }
  return randomDeck(db, inks, SeededRng(seed));
}
