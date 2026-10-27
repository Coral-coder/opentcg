/// Coverage: which cards the engine fully supports, and which texts hold back the most.
library;

import 'package:tcg_core/tcg_core.dart';

import 'cards/card_db.dart';
import 'parser/parser.dart';

Map<String, dynamic> coverageReport(RCardDb db) {
  var ok = 0;
  final bySet = <String, List<int>>{};
  final byType = <String, List<int>>{};
  final missing = <String, int>{};
  for (final c in db.cards) {
    final p = RiftboundParser.parse(c);
    if (p.supported) ok++;
    for (final pr in c.printings.take(1)) {
      final v = bySet.putIfAbsent(pr.set, () => [0, 0]);
      v[1]++;
      if (p.supported) v[0]++;
    }
    final t = byType.putIfAbsent(c.type.name, () => [0, 0]);
    t[1]++;
    if (p.supported) t[0]++;
    for (final u in p.unsupported) {
      final k = u.replaceAll(RegExp(r'\d+'), 'N');
      missing[k] = (missing[k] ?? 0) + 1;
    }
  }
  final top = missing.entries.toList()..sortStable((a, b) => b.value != a.value ? b.value - a.value : a.key.compareTo(b.key));
  final sets = bySet.keys.toList()..sortStable((a, b) => a.compareTo(b));
  final types = byType.keys.toList()..sortStable((a, b) => a.compareTo(b));
  return {
    'total': db.cards.length,
    'supported': ok,
    'sets': {for (final s in sets) s: bySet[s]},
    'types': {for (final s in types) s: byType[s]},
    'missing': [for (final e in top.take(300)) [e.value, e.key]],
  };
}
