/// One card's parse: dart run bin/card.dart "Pikachu ex" [more names...]
library;

import 'dart:convert';
import 'dart:io';

import 'package:pokemon/pokemon.dart';

void main(List<String> args) {
  final db = PCardDb.fromJson(jsonDecode(File('../../data/pokemon-cards.json').readAsStringSync()) as Map<String, dynamic>);
  for (final n in args) {
    final c = db[n] ?? db.cards.firstWhere((x) => x.key.toLowerCase().startsWith(n.toLowerCase()));
    PokemonParser.diag = [];
    final p = PokemonParser.parse(c);
    stdout.writeln('${c.key} (${c.supertype.name}${c.stage == null ? '' : ', ${c.stage!.name}'}${c.hp > 0 ? ', ${c.hp} HP' : ''})');
    if (c.text.isNotEmpty) stdout.writeln('  ${c.text}');
    for (final a in c.abilities) {
      stdout.writeln('  Ability ${a.name}: ${a.text}');
    }
    for (final a in c.attacks) {
      stdout.writeln('  ${a.cost.map((t) => t.label[0]).join()} ${a.name} ${a.damage > 0 ? '${a.damage}${a.mod}' : ''}: ${a.text}');
    }
    stdout.writeln(p.supported ? '  SUPPORTED' : '  UNSUPPORTED: ${p.unsupported.join(' | ')}\n  diag: ${PokemonParser.diag}');
    PokemonParser.diag = null;
  }
}
