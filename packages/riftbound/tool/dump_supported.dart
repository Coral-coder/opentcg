/// Prints every supported card: name, type, its text and what each ability was read as. For
/// checking the parser against the cards.
///
///     dart run tool/dump_supported.dart [cards.json]
library;

import 'dart:convert';
import 'dart:io';

import 'package:riftbound/riftbound.dart';

void main(List<String> argv) {
  final db = RCardDb.fromJson(jsonDecode(File(argv.isNotEmpty ? argv[0] : '../../data/riftbound-cards.json').readAsStringSync()) as Map<String, dynamic>);
  for (final c in db.cards) {
    final p = RiftboundParser.parseUncached(c);
    if (!p.supported) continue;
    stdout.writeln('## ${c.name} [${c.type.name}]');
    for (final l in c.text.split('\n')) {
      if (l.trim().isNotEmpty) stdout.writeln('  | $l');
    }
    for (final a in p.abilities) {
      stdout.writeln('  = ${describeAbility(a)}');
    }
  }
}
