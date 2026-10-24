import 'dart:convert';
import 'dart:io';

import 'package:lorcana/src/parser/text.dart';

void main(List<String> args) {
  final raw = jsonDecode(File('../../data/lorcana-cards.raw.json').readAsStringSync()) as List;
  var i = 0;
  for (final c in raw) {
    final m = c as Map;
    if (i++ % (int.parse(args[0])) != 0) continue;
    final t = normalizeText((m['Body_Text'] as String?) ?? '');
    final ps = splitParagraphs(t, action: (m['Type'] as String).startsWith('Action'));
    print('${m['Name']}:');
    for (final p in ps) {
      print('   [${p.keyword ? 'KW' : p.name}] ${p.body}');
    }
  }
}
