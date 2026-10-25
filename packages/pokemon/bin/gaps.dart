/// Ranks what the parser can't read yet by how many cards each gap alone holds back (cards
/// with exactly one unsupported text).
///
///     dart run bin/gaps.dart [../../data/pokemon-cards.json] [limit] [filter]
library;

import 'dart:convert';
import 'dart:io';

import 'package:pokemon/pokemon.dart';
import 'package:tcg_core/tcg_core.dart';

void main(List<String> args) {
  final db = PCardDb.fromJson(jsonDecode(File(args.isNotEmpty ? args[0] : '../../data/pokemon-cards.json').readAsStringSync()) as Map<String, dynamic>);
  final limit = args.length > 1 ? int.parse(args[1]) : 80;
  final filter = args.length > 2 ? args[2] : '';
  final only = <String, int>{};
  final keys = <String>[];
  final examples = <String, String>{};
  var ok = 0;
  for (final c in db.cards) {
    PokemonParser.clearCache();
    PokemonParser.diag = [];
    final p = PokemonParser.parse(c);
    final d = PokemonParser.diag!;
    PokemonParser.diag = null;
    if (p.supported) {
      ok++;
      continue;
    }
    if (p.unsupported.length != 1) continue;
    String norm(String s) => s.replaceAll(RegExp(r'\d+'), 'N');
    final k = d.isEmpty ? 'text: ${norm(p.unsupported.first)}' : norm(d.last);
    if (!only.containsKey(k)) keys.add(k);
    only[k] = (only[k] ?? 0) + 1;
    examples.putIfAbsent(k, () => c.key);
  }
  stdout.writeln('$ok/${db.cards.length} supported\n');
  final top = [for (final k in keys) if (filter.isEmpty || k.contains(filter)) k]..sortStable((a, b) => only[b]! - only[a]!);
  for (final k in top.take(limit)) {
    stdout.writeln('${only[k].toString().padLeft(5)} $k   [${examples[k]}]');
  }
}
