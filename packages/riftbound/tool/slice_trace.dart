/// For the cards listed in a dump_unsupported-style file ("## Name [type] …" headers), prints
/// how each parses now: supported cards with their abilities, others with the unreadable pieces.
///
///     dart run tool/slice_trace.dart SLICE_FILE [cards.json]
library;

import 'dart:convert';
import 'dart:io';

import 'package:riftbound/riftbound.dart';

void main(List<String> args) {
  final db = RCardDb.fromJson(jsonDecode(File(args.length > 1 ? args[1] : '../../data/riftbound-cards.json').readAsStringSync()) as Map<String, dynamic>);
  final names = File(args[0]).readAsLinesSync().where((l) => l.startsWith('## ')).map((l) => l.substring(3, l.indexOf(' [')));
  var ok = 0, total = 0;
  for (final n in names) {
    total++;
    final c = db.cards.firstWhere((c) => c.name == n);
    RiftboundParser.clearCache();
    RiftboundParser.trace = [];
    final p = RiftboundParser.parseUncached(c);
    if (p.supported) {
      ok++;
      stdout.writeln('OK $n');
      for (final a in p.abilities) {
        stdout.writeln('   = ${describeAbility(a)}');
      }
    } else {
      stdout.writeln('-- $n: ${p.unsupported.join(' | ')}');
      for (final t in RiftboundParser.trace!) {
        stdout.writeln('     $t');
      }
    }
  }
  RiftboundParser.trace = null;
  stdout.writeln('$ok of $total supported');
}
