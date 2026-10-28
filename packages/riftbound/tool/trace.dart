/// Which pieces of text hold cards back: parses every unsupported card with tracing on and counts
/// the most specific unreadable piece of each line (numbers folded to N).
///
///     dart run tool/trace.dart [cards.json] [--exclude REGEX] [--top N] [--kind S|W|T|C|P|K] [--cards]
library;

import 'dart:convert';
import 'dart:io';

import 'package:riftbound/riftbound.dart';
import 'package:tcg_core/tcg_core.dart';

void main(List<String> argv) {
  String? opt(String f) => argv.contains(f) && argv.indexOf(f) + 1 < argv.length ? argv[argv.indexOf(f) + 1] : null;
  final pos = [
    for (var i = 0; i < argv.length; i++)
      if (!argv[i].startsWith('--') && (i == 0 || !const {'--exclude', '--top', '--kind'}.contains(argv[i - 1]))) argv[i],
  ];
  final db = RCardDb.fromJson(jsonDecode(File(pos.isNotEmpty ? pos[0] : '../../data/riftbound-cards.json').readAsStringSync()) as Map<String, dynamic>);
  final ex = opt('--exclude') == null ? null : RegExp(opt('--exclude')!);
  final top = int.tryParse(opt('--top') ?? '') ?? 150;
  final kind = opt('--kind');
  final count = <String, int>{};
  final cardsOf = <String, List<String>>{};
  var n = 0;
  for (final c in db.cards) {
    final p = RiftboundParser.parseUncached(c);
    if (p.supported) continue;
    if (ex != null && p.unsupported.any(ex.hasMatch)) continue;
    n++;
    RiftboundParser.trace = [];
    RiftboundParser.parseUncached(c);
    final t = RiftboundParser.trace!;
    RiftboundParser.trace = null;
    final keys = <String>{};
    for (final x in t.isEmpty ? ['?: ${p.unsupported.first}'] : t) {
      final k = x.replaceAll(RegExp(r'\d+'), 'N');
      if (kind != null && !k.startsWith('$kind:')) continue;
      keys.add(k);
    }
    for (final k in keys) {
      count[k] = (count[k] ?? 0) + 1;
      cardsOf.putIfAbsent(k, () => []).add(c.name);
    }
  }
  stdout.writeln('$n cards');
  final keys = count.keys.toList()..sortStable((a, b) => count[b] != count[a] ? count[b]! - count[a]! : a.compareTo(b));
  for (final k in keys.take(top)) {
    stdout.writeln('${count[k]}\t$k${argv.contains('--cards') ? '\t[${cardsOf[k]!.join(' | ')}]' : ''}');
  }
}
