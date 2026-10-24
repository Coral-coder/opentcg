/// Ranks what the parser can't read yet by how many cards each gap alone holds back.
///
///     dart run bin/gaps.dart ../../data/lorcana-cards.json [limit] [filter]
library;

import 'dart:convert';
import 'dart:io';

import 'package:lorcana/lorcana.dart';
import 'package:tcg_core/tcg_core.dart';

void main(List<String> args) {
  final db = LCardDb.fromJson(jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>);
  final limit = args.length > 1 ? int.parse(args[1]) : 80;
  final filter = args.length > 2 ? args[2] : '';
  final only = <String, int>{};
  final examples = <String, String>{};
  var ok = 0;
  for (final c in db.cards) {
    LorcanaParser.clearCache();
    LorcanaParser.diag = [];
    final p = LorcanaParser.parse(c);
    final d = LorcanaParser.diag!;
    LorcanaParser.diag = null;
    if (p.supported) {
      ok++;
      continue;
    }
    if (p.unsupported.length != 1) continue;
    String norm(String s) => s.replaceAll(RegExp(r'\d+'), 'N');
    final keys = d.isEmpty ? {'paragraph: ${norm(p.unsupported.first)}'} : {norm(d.last)};
    for (final k in keys) {
      only[k] = (only[k] ?? 0) + 1;
      examples.putIfAbsent(k, () => c.fullName);
    }
  }
  stdout.writeln('$ok/${db.length} supported\n');
  final top = only.entries.where((e) => filter.isEmpty || e.key.contains(filter)).toList()..sortStable((a, b) => b.value - a.value);
  for (final e in top.take(limit)) {
    stdout.writeln('${e.value.toString().padLeft(5)} ${e.key}   [${examples[e.key]}]');
  }
}
