/// Lists the cards the parser can't fully read yet, one per line: name, then the unread text.
///
///     dart run tool/unsupported.dart ../../data/lorcana-cards.json
library;

import 'dart:convert';
import 'dart:io';

import 'package:lorcana/lorcana.dart';

void main(List<String> args) {
  final db = LCardDb.fromJson(jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>);
  for (final c in db.cards) {
    final p = LorcanaParser.parse(c);
    if (!p.supported) stdout.writeln('${c.fullName}\t${p.unsupported.join(' | ').replaceAll('\n', ' / ')}');
  }
}
