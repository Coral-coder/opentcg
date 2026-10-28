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
  final db = _corrected(RCardDb.fromRaw(raw, version: '${raw.length}', gallery: gallery), File('$out/riftbound-overrides.json'));
  File('$out/riftbound-cards.json').writeAsStringSync(jsonEncode(db.toJson()));
  final cov = coverageReport(db);
  File('$out/riftbound-coverage.json').writeAsStringSync(jsonEncode(cov));
  stdout.writeln('${db.cards.length} cards, ${cov['supported']} fully supported (${(100 * (cov['supported'] as int) / db.cards.length).toStringAsFixed(1)}%) → $out');
}

/// Applies the documented text corrections in [file] (riftbound-overrides.json, keyed by card
/// name, each with the corrected text and why).
RCardDb _corrected(RCardDb db, File file) {
  if (!file.existsSync()) return db;
  final o = (jsonDecode(file.readAsStringSync()) as Map).cast<String, dynamic>();
  for (final k in o.keys) {
    if (!k.startsWith('_') && db[k] == null) stderr.writeln('riftbound-overrides.json: no card named $k');
  }
  var n = 0;
  final cards = [
    for (final c in db.cards)
      if (o[c.name] case {'text': final String text}) (() {
        n++;
        return RCard.fromJson({...c.toJson(), 'x': text});
      })()
      else c,
  ];
  stdout.writeln('$n card${n == 1 ? '' : 's'} use corrected text from riftbound-overrides.json');
  return RCardDb(cards, version: db.version);
}
