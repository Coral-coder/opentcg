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
  final db = LCardDb.fromRaw(raw, version: '${raw.length}', fill: fill);
  File('$out/lorcana-cards.json').writeAsStringSync(jsonEncode(db.toJson()));
  final cov = Coverage();
  for (final c in db.cards) {
    cov.add(c, LorcanaParser.parse(c).unsupported);
  }
  File('$out/lorcana-coverage.json').writeAsStringSync(jsonEncode(cov.toJson()));
  stdout.writeln('${db.length} cards, ${cov.supported} fully supported (${(100 * cov.supported / db.length).toStringAsFixed(1)}%) → $out');
}
