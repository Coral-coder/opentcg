/// Raw bulk card list (api.lorcana-api.com/bulk/cards) → compact database + coverage.
///
///     dart run bin/build_db.dart ../../data/lorcana-cards.raw.json ../../data [../../data/lorcast-cards.json]
///
/// The optional Lorcast card list (api.lorcast.com, all sets) fills what the bulk data lacks:
/// locations' move costs and the text of a few actions.
library;

import 'dart:convert';
import 'dart:io';

import 'package:lorcana/lorcana.dart';

void main(List<String> args) {
  final raw = jsonDecode(File(args[0]).readAsStringSync()) as List;
  final out = args.length > 1 ? args[1] : '.';
  final fill = <String, ({int? moveCost, String text})>{};
  if (args.length > 2) {
    for (final c in jsonDecode(File(args[2]).readAsStringSync()) as List) {
      final m = (c as Map).cast<String, dynamic>();
      final version = m['version'] as String?;
      final name = version == null || version.isEmpty ? m['name'] as String : '${m['name']} - $version';
      fill[name.trim()] = (moveCost: m['move_cost'] as int?, text: ((m['text'] as String?) ?? '').trim());
    }
  }
  // Both sources transcribe the same printed text, but each mangles a few cards (merged lines,
  // lost symbols). Keep the bulk text, and switch a card to Lorcast's wording only when that's
  // the one the parser reads in full.
  // Documented corrections to the bulk text (data/lorcana-overrides.json, beside the bulk file).
  final overrides = _overrides(File('${File(args[0]).parent.path}/lorcana-overrides.json'));
  final bulk = _corrected(LCardDb.fromRaw(raw, version: '${raw.length}', fill: fill), overrides);
  final alt = LCardDb.fromRaw(raw, version: '${raw.length}', fill: fill, preferFill: true);
  var switched = 0;
  final db = LCardDb([
    for (final c in bulk.cards)
      if (!LorcanaParser.parseUncached(c).supported && alt[c.fullName] != null && alt[c.fullName]!.text != c.text && LorcanaParser.parseUncached(alt[c.fullName]!).supported) (() {
        switched++;
        return alt[c.fullName]!;
      })()
      else c,
  ], version: bulk.version);
  if (switched > 0) stdout.writeln('$switched cards use Lorcast\'s wording');
  LorcanaParser.clearCache();
  File('$out/lorcana-cards.json').writeAsStringSync(jsonEncode(db.toJson()));
  final cov = Coverage();
  for (final c in db.cards) {
    cov.add(c, LorcanaParser.parse(c).unsupported);
  }
  File('$out/lorcana-coverage.json').writeAsStringSync(jsonEncode(cov.toJson()));
  stdout.writeln('${db.length} cards, ${cov.supported} fully supported (${(100 * cov.supported / db.length).toStringAsFixed(1)}%) → $out');
}

/// Full name → corrected rules text.
Map<String, String> _overrides(File f) {
  if (!f.existsSync()) return const {};
  final cards = (jsonDecode(f.readAsStringSync()) as Map)['cards'] as Map;
  return {for (final e in cards.entries) e.key as String: ((e.value as Map)['text'] as String)};
}

LCardDb _corrected(LCardDb db, Map<String, String> overrides) {
  if (overrides.isEmpty) return db;
  for (final n in overrides.keys) {
    if (db[n] == null) stderr.writeln('Override for an unknown card: $n');
  }
  return LCardDb([
    for (final c in db.cards)
      overrides[c.fullName] == null
          ? c
          : LCard(
              fullName: c.fullName,
              type: c.type,
              cost: c.cost,
              inkable: c.inkable,
              inks: c.inks,
              strength: c.strength,
              willpower: c.willpower,
              lore: c.lore,
              moveCost: c.moveCost,
              classifications: c.classifications,
              text: overrides[c.fullName]!,
              printings: c.printings,
              franchise: c.franchise,
            ),
  ], version: db.version);
}
