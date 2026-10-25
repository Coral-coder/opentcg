/// Raw bulk card list (api.lorcana-api.com/bulk/cards) → compact database + coverage.
///
///     dart run bin/build_db.dart ../../data/lorcana-cards.raw.json ../../data [../../data/lorcast-cards.json]
///
/// The optional Lorcast card list (api.lorcast.com, all sets) fills what the bulk data lacks:
/// locations' move costs and the text of a few actions. lorcana-overrides.json in the output
/// directory, when there, corrects texts by hand.
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
  final bulk = LCardDb.fromRaw(raw, version: '${raw.length}', fill: fill);
  final alt = LCardDb.fromRaw(raw, version: '${raw.length}', fill: fill, preferFill: true);
  var switched = 0;
  var db = LCardDb([
    for (final c in bulk.cards)
      if (!LorcanaParser.parseUncached(c).supported && alt[c.fullName] != null && alt[c.fullName]!.text != c.text && LorcanaParser.parseUncached(alt[c.fullName]!).supported) (() {
        switched++;
        return alt[c.fullName]!;
      })()
      else c,
  ], version: bulk.version);
  if (switched > 0) stdout.writeln('$switched cards use Lorcast\'s wording');
  // Texts both sources get wrong (lost costs, missing abilities, typos), corrected by hand from
  // the printed card: data/lorcana-overrides.json, keyed by full name, each with why.
  final overrides = File('$out/lorcana-overrides.json');
  if (overrides.existsSync()) {
    final o = (jsonDecode(overrides.readAsStringSync()) as Map).cast<String, dynamic>();
    for (final name in o.keys) {
      final c = db[name];
      if (c == null) throw StateError('Override for unknown card $name');
      final j = c.toJson()..['x'] = (o[name] as Map)['text'] as String;
      db = LCardDb([for (final x in db.cards) x.fullName == name ? LCard.fromJson(j) : x], version: db.version);
    }
    stdout.writeln('${o.length} texts from lorcana-overrides.json');
  }
  LorcanaParser.clearCache();
  File('$out/lorcana-cards.json').writeAsStringSync(jsonEncode(db.toJson()));
  final cov = Coverage();
  for (final c in db.cards) {
    cov.add(c, LorcanaParser.parse(c).unsupported);
  }
  File('$out/lorcana-coverage.json').writeAsStringSync(jsonEncode(cov.toJson()));
  stdout.writeln('${db.length} cards, ${cov.supported} fully supported (${(100 * cov.supported / db.length).toStringAsFixed(1)}%) → $out');
}
