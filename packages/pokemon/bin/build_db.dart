/// Builds the card database from pokemon-tcg-data set files (github.com/PokemonTCG/pokemon-tcg-data,
/// cards/en/<set>.json): keeps the Standard pool (regulation marks H, I, J) plus Basic Energy,
/// merges reprints, and writes the compact database and its coverage report.
///
///     dart run bin/build_db.dart <dir with set json files> ../../data
library;

import 'dart:convert';
import 'dart:io';

import 'package:pokemon/pokemon.dart';
import 'package:tcg_core/tcg_core.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('usage: build_db <dir of cards/en/*.json> <out dir> [marks, default H,I,J]');
    exitCode = 64;
    return;
  }
  final marks = args.length > 2 ? args[2].split(',').toSet() : const {'H', 'I', 'J'};
  final files = Directory(args[0]).listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()..sortStable((a, b) => a.path.compareTo(b.path));
  final raw = <Map<String, dynamic>>[];
  for (final f in files) {
    try {
      raw.addAll((jsonDecode(f.readAsStringSync()) as List).cast<Map<String, dynamic>>());
    } catch (e) {
      stderr.writeln('skipping ${f.path}: $e');
    }
  }
  final db = PCardDb.fromRaw(raw, marks: marks, version: 'marks ${marks.join('')}');
  final out = Directory(args[1])..createSync(recursive: true);
  File('${out.path}/pokemon-cards.json').writeAsStringSync(jsonEncode(db.toJson()));
  final cov = coverageReport(db);
  File('${out.path}/pokemon-coverage.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(cov));
  stdout.writeln('${db.cards.length} cards (${raw.length} printings read), ${cov['supported']} fully supported → ${out.path}');
}
