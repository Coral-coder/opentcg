/// One card's parse: dart run bin/card.dart "Befuddle" [more names...]
library;

import 'dart:convert';
import 'dart:io';

import 'package:lorcana/lorcana.dart';
import 'package:lorcana/src/parser/text.dart';

void main(List<String> args) {
  final db = LCardDb.fromJson(jsonDecode(File('../../data/lorcana-cards.json').readAsStringSync()) as Map<String, dynamic>);
  for (final n in args) {
    final c = db[n] ?? db.cards.firstWhere((x) => x.fullName.toLowerCase().startsWith(n.toLowerCase()));
    LorcanaParser.diag = [];
    final p = LorcanaParser.parse(c);
    stdout.writeln('${c.fullName} (${c.type.name}, ${c.cost})\n  ${normalizeText(c.text)}');
    for (final a in p.abilities) {
      stdout.writeln('  = ${describeAbility(a)}');
    }
    stdout.writeln(p.supported ? '  SUPPORTED' : '  UNSUPPORTED: ${p.unsupported.join(' | ')}\n  diag: ${LorcanaParser.diag}');
  }
}
