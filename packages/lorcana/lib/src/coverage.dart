/// Coverage: which cards the engine fully supports, per set, and which texts block the most.
library;

import 'package:tcg_core/tcg_core.dart';

import 'cards/card.dart';

class Coverage {
  int total = 0;
  int supported = 0;
  final Map<String, (int, int)> bySet = {};
  final Map<String, int> missing = {};

  void add(LCard c, List<String> unsupported) {
    final ok = unsupported.isEmpty;
    total++;
    if (ok) supported++;
    for (final s in {for (final p in c.printings) p.set}) {
      final v = bySet[s] ?? (0, 0);
      bySet[s] = (v.$1 + (ok ? 1 : 0), v.$2 + 1);
    }
    for (final u in unsupported) {
      final key = u.replaceAll(RegExp(r'\d+'), 'N');
      missing[key] = (missing[key] ?? 0) + 1;
    }
  }

  Map<String, dynamic> toJson() {
    final top = missing.entries.toList()..sortStable((a, b) => b.value != a.value ? b.value - a.value : a.key.compareTo(b.key));
    final sets = bySet.keys.toList()..sortStable((a, b) => a.compareTo(b));
    return {
      'total': total,
      'supported': supported,
      'sets': {
        for (final s in sets) s: [bySet[s]!.$1, bySet[s]!.$2],
      },
      'missing': [
        for (final e in top.take(300)) [e.value, e.key],
      ],
    };
  }
}
