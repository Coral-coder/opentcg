/// Lists the rules-text lines the parser can't read yet, most common first (numbers folded to
/// N), with how many cards each blocks and how many cards it alone blocks.
///
///     dart run tool/unsupported.dart [cards.json] [--exclude REGEX] [--cards] [--top N]
///
/// --exclude skips lines matching REGEX (and cards with any such line); --cards lists the cards
/// whose only unread lines are shown.
library;

import 'dart:convert';
import 'dart:io';

import 'package:riftbound/riftbound.dart';
import 'package:tcg_core/tcg_core.dart';

void main(List<String> argv) {
  String? opt(String f) => argv.contains(f) && argv.indexOf(f) + 1 < argv.length ? argv[argv.indexOf(f) + 1] : null;
  final pos = [
    for (var i = 0; i < argv.length; i++)
      if (!argv[i].startsWith('--') && (i == 0 || !const {'--exclude', '--top'}.contains(argv[i - 1]))) argv[i],
  ];
  final db = RCardDb.fromJson(jsonDecode(File(pos.isNotEmpty ? pos[0] : '../../data/riftbound-cards.json').readAsStringSync()) as Map<String, dynamic>);
  final ex = opt('--exclude') == null ? null : RegExp(opt('--exclude')!);
  final top = int.tryParse(opt('--top') ?? '') ?? 200;
  final count = <String, int>{}, alone = <String, int>{};
  final cardsOf = <String, List<String>>{};
  var cards = 0, kept = 0;
  for (final c in db.cards) {
    final p = RiftboundParser.parse(c);
    if (p.supported) continue;
    cards++;
    if (ex != null && p.unsupported.any(ex.hasMatch)) continue;
    kept++;
    final keys = {for (final u in p.unsupported) u.replaceAll(RegExp(r'\d+'), 'N')};
    for (final k in keys) {
      count[k] = (count[k] ?? 0) + 1;
      if (keys.length == 1) alone[k] = (alone[k] ?? 0) + 1;
      cardsOf.putIfAbsent(k, () => []).add(c.name);
    }
  }
  stdout.writeln('$cards unsupported cards, $kept after --exclude');
  final keys = count.keys.toList()..sortStable((a, b) => count[b] != count[a] ? count[b]! - count[a]! : a.compareTo(b));
  for (final k in keys.take(top)) {
    stdout.writeln('${count[k]}\t${alone[k] ?? 0}\t$k${argv.contains('--cards') ? '\t[${cardsOf[k]!.join(' | ')}]' : ''}');
  }
}
