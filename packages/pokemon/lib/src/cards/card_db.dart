/// The card database: built from the pokemon-tcg-data set files (bin/build_db.dart), stored as
/// compact JSON, looked up by card key.
library;

import 'package:tcg_core/tcg_core.dart';

import 'card.dart';

class PCardDb {
  PCardDb(List<PCard> cards, {this.version = ''}) : cards = List.unmodifiable(cards) {
    for (final c in cards) {
      _byKey[c.key] = c;
    }
  }

  final List<PCard> cards;
  final String version;
  final Map<String, PCard> _byKey = {};

  PCard? operator [](String key) => _byKey[key];

  Map<String, dynamic> toJson() => {'v': 1, 'version': version, 'cards': [for (final c in cards) c.toJson()]};

  static PCardDb fromJson(Map<String, dynamic> j) => PCardDb([for (final c in j['cards'] as List) PCard.fromJson(c as Map<String, dynamic>)], version: (j['version'] as String?) ?? '');

  /// From pokemon-tcg-data card objects (any number of set files concatenated). Keeps cards
  /// whose regulation mark is in [marks], plus Basic Energy; reprints with the same game text
  /// become printings of one card.
  static PCardDb fromRaw(List<Map<String, dynamic>> raw, {Set<String> marks = const {'H', 'I', 'J'}, String version = ''}) {
    final groups = <String, List<Map<String, dynamic>>>{};
    final order = <String>[];
    for (final c in raw) {
      final basicEnergy = c['supertype'] == 'Energy' && ((c['subtypes'] as List?) ?? const []).contains('Basic');
      if (!basicEnergy && !marks.contains(c['regulationMark'])) continue;
      final sig = _signature(c);
      if (!groups.containsKey(sig)) order.add(sig);
      groups.putIfAbsent(sig, () => []).add(c);
    }
    // Names shared by different cards get their first printing in the key.
    final nameCount = <String, int>{};
    for (final sig in order) {
      final n = groups[sig]!.first['name'] as String;
      nameCount[n] = (nameCount[n] ?? 0) + 1;
    }
    final cards = <PCard>[];
    for (final sig in order) {
      final g = groups[sig]!;
      final c = g.first;
      final name = c['name'] as String;
      final key = nameCount[name]! > 1 ? '$name (${(c['id'] as String).replaceAll('-', ' ')})' : name;
      cards.add(_card(c, key, [for (final p in g) _printing(p)]));
    }
    cards.sortStable((a, b) => a.key.compareTo(b.key));
    return PCardDb(cards, version: version);
  }

  static String _signature(Map<String, dynamic> c) {
    String attacks() => [for (final a in (c['attacks'] as List?) ?? const []) '${a['name']}|${a['cost']}|${a['damage']}|${a['text']}'].join(';');
    String abilities() => [for (final a in (c['abilities'] as List?) ?? const []) '${a['name']}|${a['text']}'].join(';');
    return '${c['name']}|${c['supertype']}|${c['subtypes']}|${c['hp']}|${c['types']}|${c['evolvesFrom']}|${attacks()}|${abilities()}|${c['rules']}|${c['weaknesses']}|${c['resistances']}|${c['convertedRetreatCost']}';
  }

  static Printing _printing(Map<String, dynamic> c) {
    final id = c['id'] as String;
    final images = (c['images'] as Map?) ?? const {};
    return Printing(set: id.substring(0, id.lastIndexOf('-')), number: c['number']?.toString() ?? '', rarity: c['rarity'] as String? ?? '', image: images['large'] as String? ?? images['small'] as String? ?? '');
  }

  static PCard _card(Map<String, dynamic> c, String key, List<Printing> printings) {
    final sub = [for (final s in (c['subtypes'] as List?) ?? const []) s as String];
    final st = switch (c['supertype']) { 'Pokémon' => Supertype.pokemon, 'Trainer' => Supertype.trainer, _ => Supertype.energy };
    final rules = [for (final r in (c['rules'] as List?) ?? const []) (r as String).replaceAll(RegExp(r'\s+'), ' ').trim()];
    Stage? stage;
    if (st == Supertype.pokemon) stage = sub.contains('Stage 2') ? Stage.stage2 : (sub.contains('Stage 1') ? Stage.stage1 : Stage.basic);
    TrainerKind? trainer;
    if (st == Supertype.trainer) {
      trainer = sub.contains('Supporter') ? TrainerKind.supporter : (sub.contains('Stadium') ? TrainerKind.stadium : (sub.contains('Pokémon Tool') ? TrainerKind.tool : TrainerKind.item));
    }
    // A Trainer's or Special Energy's effect is its first rule text; the rest are reminders.
    var text = '';
    final rest = <String>[];
    if (st != Supertype.pokemon && rules.isNotEmpty) {
      text = rules.first;
      rest.addAll(rules.skip(1));
    } else {
      rest.addAll(rules);
    }
    int dmg(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    String mod(String s) => s.endsWith('+') ? '+' : ((s.endsWith('×') || s.endsWith('x')) ? '×' : (s.endsWith('-') ? '-' : ''));
    final weak = (c['weaknesses'] as List?)?.cast<Map>();
    final res = (c['resistances'] as List?)?.cast<Map>();
    return PCard(
      key: key,
      name: c['name'] as String,
      supertype: st,
      stage: stage,
      trainer: trainer,
      basicEnergy: st == Supertype.energy && sub.contains('Basic'),
      hp: int.tryParse(c['hp']?.toString() ?? '') ?? 0,
      types: [for (final t in (c['types'] as List?) ?? const []) ?PType.byLabel(t as String)],
      evolvesFrom: c['evolvesFrom'] as String?,
      abilities: [for (final a in (c['abilities'] as List?) ?? const []) PAbility(name: a['name'] as String, text: (a['text'] as String? ?? '').replaceAll(RegExp(r'\s+'), ' ').trim())],
      attacks: [
        for (final a in (c['attacks'] as List?) ?? const [])
          Attack(
            name: a['name'] as String,
            cost: [for (final t in (a['cost'] as List?) ?? const []) ?PType.byLabel(t as String)],
            damage: dmg(a['damage']?.toString() ?? ''),
            mod: mod(a['damage']?.toString() ?? ''),
            text: (a['text'] as String? ?? '').replaceAll(RegExp(r'\s+'), ' ').trim(),
          ),
      ],
      weakness: weak == null || weak.isEmpty ? null : PType.byLabel(weak.first['type'] as String),
      resistance: res == null || res.isEmpty ? null : PType.byLabel(res.first['type'] as String),
      resistanceAmount: res == null || res.isEmpty ? 30 : (int.tryParse((res.first['value'] as String).replaceAll(RegExp(r'[^0-9]'), '')) ?? 30),
      retreat: c['convertedRetreatCost'] as int? ?? ((c['retreatCost'] as List?)?.length ?? 0),
      ex: sub.contains('ex'),
      mega: sub.contains('MEGA'),
      tera: sub.contains('Tera'),
      aceSpec: sub.contains('ACE SPEC'),
      text: text,
      rules: rest,
      regulation: c['regulationMark'] as String? ?? '',
      printings: printings,
    );
  }
}
