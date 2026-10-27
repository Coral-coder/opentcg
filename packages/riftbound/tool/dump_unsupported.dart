/// Prints every unsupported card (optionally skipping those with a line matching --exclude):
/// name, type, cost, might, tags, then its text with unread lines marked "✗".
///
///     dart run tool/dump_unsupported.dart [cards.json] [--exclude REGEX] [--all]
library;

import 'dart:convert';
import 'dart:io';

import 'package:riftbound/riftbound.dart';

void main(List<String> argv) {
  String? opt(String f) => argv.contains(f) && argv.indexOf(f) + 1 < argv.length ? argv[argv.indexOf(f) + 1] : null;
  final pos = [
    for (var i = 0; i < argv.length; i++)
      if (!argv[i].startsWith('--') && (i == 0 || !const {'--exclude'}.contains(argv[i - 1]))) argv[i],
  ];
  final db = RCardDb.fromJson(jsonDecode(File(pos.isNotEmpty ? pos[0] : '../../data/riftbound-cards.json').readAsStringSync()) as Map<String, dynamic>);
  final ex = opt('--exclude') == null ? null : RegExp(opt('--exclude')!);
  for (final c in db.cards) {
    final p = RiftboundParser.parseUncached(c);
    if (p.supported && !argv.contains('--all')) continue;
    if (ex != null && p.unsupported.any(ex.hasMatch)) continue;
    stdout.writeln(
      '## ${c.name} [${c.type.name}${c.token ? ' token' : ''}] {${c.energy}}${'P' * c.power} ${c.domains.map((d) => d.letter).join()}${c.might == null ? '' : ' M${c.might}'}${c.tags.isEmpty ? '' : ' (${c.tags.join(', ')})'}',
    );
    for (final l in c.text.split('\n')) {
      if (l.trim().isEmpty) continue;
      stdout.writeln('${p.unsupported.contains(l.trim()) ? '✗' : ' '} $l');
    }
  }
}
