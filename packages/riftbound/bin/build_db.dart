/// Builds the card database and coverage report from Riftcodex's card list.
///
///     dart run bin/build_db.dart ../../data/riftbound-cards.raw.json ../../data
///
/// The raw file is every page of https://api.riftcodex.com/cards?size=100 concatenated into one
/// JSON list (Riftcodex is an unofficial fan API; card data and images are Riot Games'). Riftcodex
/// leaves out Equipment's Effect Text and Might Bonus; riftbound-gallery.json beside the raw file
/// (tool/riftbound_gallery.py, from Riot's card gallery) adds them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:riftbound/riftbound.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: build_db.dart RAW.json [OUT_DIR]');
    exit(64);
  }
  final raw = (jsonDecode(File(args[0]).readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final out = args.length > 1 ? args[1] : '.';
  final galleryFile = File('${File(args[0]).parent.path}/riftbound-gallery.json');
  final gallery = galleryFile.existsSync() ? (jsonDecode(galleryFile.readAsStringSync()) as Map<String, dynamic>)['cards'] as Map<String, dynamic> : const <String, dynamic>{};
  final db = RCardDb.fromRaw(raw, version: '${raw.length}', gallery: gallery);
  File('$out/riftbound-cards.json').writeAsStringSync(jsonEncode(db.toJson()));
  final cov = coverageReport(db);
  File('$out/riftbound-coverage.json').writeAsStringSync(jsonEncode(cov));
  stdout.writeln('${db.cards.length} cards, ${cov['supported']} fully supported (${(100 * (cov['supported'] as int) / db.cards.length).toStringAsFixed(1)}%) → $out');
}
