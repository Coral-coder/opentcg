/// One card's parse: dart run bin/card.dart "Befuddle" [more names...]
///                   dart run bin/card.dart --file names.txt   (one name per line)
library;

import 'dart:convert';
import 'dart:io';

import 'package:lorcana/lorcana.dart';
import 'package:lorcana/src/parser/text.dart';

void main(List<String> args) {
  final db = LCardDb.fromJson(jsonDecode(File('../../data/lorcana-cards.json').readAsStringSync()) as Map<String, dynamic>);
  final names = args.isNotEmpty && args.first == '--file' ? File(args[1]).readAsLinesSync().where((l) => l.trim().isNotEmpty).toList() : args;
  for (final n in names) {
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
