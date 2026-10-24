import 'dart:convert';
import 'dart:io';

import 'package:lorcana/lorcana.dart';
import 'package:lorcana/src/parser/text.dart';

void main(List<String> args) {
  final db = LCardDb.fromJson(jsonDecode(File('../../data/lorcana-cards.json').readAsStringSync()) as Map<String, dynamic>);
  final every = int.parse(args[0]);
  final offset = args.length > 1 ? int.parse(args[1]) : 0;
  var i = 0;
  for (final c in db.cards) {
    final p = LorcanaParser.parse(c);
    if (!p.supported || c.text.isEmpty) continue;
    if (i++ % every != offset) continue;
    stdout.writeln('## ${c.fullName}: ${normalizeText(c.text)}');
    for (final a in p.abilities) {
      if (a is KeywordAbility) continue;
      stdout.writeln('   = ${describeAbility(a)}');
    }
  }
}
