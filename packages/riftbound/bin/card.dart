/// Prints how the engine reads cards: `dart run bin/card.dart "Jinx, Demolitionist" [more…]`,
/// or `--decks` for the playable legends and their starter decks.
library;

import 'dart:convert';
import 'dart:io';

import 'package:riftbound/riftbound.dart';

void main(List<String> args) {
  final db = RCardDb.fromJson(jsonDecode(File('../../data/riftbound-cards.json').readAsStringSync()) as Map<String, dynamic>);
  if (args.contains('--decks')) {
    final legends = playableLegends(db);
    stdout.writeln('${legends.length} playable legends');
    for (final l in legends) {
      final d = buildDeck(db, l);
      final problems = validateDeck(db, d);
      stdout.writeln('${l.name} [${l.domains.map((x) => x.label).join('/')}] champions: ${championsFor(db, l).map((c) => c.name).join(', ')}; pool ${poolFor(db, l).length}${problems.isEmpty ? '' : '  PROBLEMS: ${problems.join(' ')}'}');
    }
    return;
  }
  if (args.contains('--coverage')) {
    // "supported/total": what CI checks against test/fixtures/coverage-floor.txt.
    final ok = db.cards.where((c) => RiftboundParser.parse(c).supported).length;
    stdout.writeln('$ok/${db.cards.length} cards fully supported, ${playableLegends(db).length} legends with full decks');
    return;
  }
  if (args.contains('--dump')) {
    // Every supported card with text, next to how it's read (for auditing).
    for (final c in db.cards) {
      final p = RiftboundParser.parse(c);
      if (!p.supported || c.text.isEmpty) continue;
      stdout.writeln('${c.name} (${c.type.name}${c.might == null ? '' : ' ${c.might}M'}, {${c.energy}}+${c.power})');
      for (final l in c.text.split('\n')) {
        stdout.writeln('    $l');
      }
      for (final a in p.abilities) {
        stdout.writeln('  = ${describeAbility(a)}');
      }
      for (final l in c.effect.split('\n')) {
        if (l.isNotEmpty) stdout.writeln('    Effect: $l');
      }
      for (final a in p.extra) {
        stdout.writeln('  + ${describeAbility(a)}');
      }
    }
    return;
  }
  if (args.contains('--supported')) {
    for (final t in CardType.values) {
      final ok = [for (final c in db.cards) if (c.type == t && RiftboundParser.parse(c).supported) c];
      stdout.writeln('${t.name} (${ok.length}): ${ok.map((c) => '${c.name}${c.champion ? '*' : ''} [${c.domains.map((d) => d.letter).join()}${c.tags.isEmpty ? '' : ' ${c.tags.first}'}]').join('; ')}');
    }
    return;
  }
  if (args.contains('--legends')) {
    for (final l in db.cards.where((c) => c.type == CardType.legend)) {
      final p = RiftboundParser.parse(l);
      final champs = [for (final c in db.cards) if (c.type == CardType.unit && c.champion && l.tags.any(c.hasTag)) c];
      stdout.writeln('${p.supported ? 'OK ' : '-- '}${l.name} [${l.domains.map((d) => d.letter).join()}] ${l.tags} pool ${poolFor(db, l).length} champs: ${champs.map((c) => '${c.name}${RiftboundParser.parse(c).supported ? '✓' : '✗'}').join(', ')}${p.supported ? '' : '  ← ${p.unsupported.join(' | ')}'}');
    }
    return;
  }
  // "~text" matches every card whose name contains the text.
  final names = [
    for (final a in args)
      if (a.startsWith('~')) ...[for (final c in db.cards) if (c.name.toLowerCase().contains(a.substring(1).toLowerCase())) c.name] else a,
  ];
  for (final name in names) {
    final c = db[name];
    if (c == null) {
      stdout.writeln('No card named "$name"');
      continue;
    }
    final p = RiftboundParser.parse(c);
    stdout.writeln('${c.name} (${c.type.name}${c.champion ? ', champion' : ''}, ${c.domains.map((d) => d.label).join('/')}, {${c.energy}}+${c.power}P${c.might == null ? '' : ', ${c.might} Might'}) [${c.tags.join(', ')}]');
    for (final l in c.text.split('\n')) {
      stdout.writeln('  $l');
    }
    for (final a in p.abilities) {
      stdout.writeln('  = ${describeAbility(a)}');
    }
    // An Equipment's Effect Text and Might Bonus (CR 136–137), and abilities given to others.
    if (c.mightBonus != null) stdout.writeln('  Might Bonus: +${c.mightBonus}');
    for (final l in c.effect.split('\n')) {
      if (l.isNotEmpty) stdout.writeln('  Effect: $l');
    }
    for (final a in p.extra) {
      stdout.writeln('  + ${describeAbility(a)}');
    }
    stdout.writeln(p.supported ? '  SUPPORTED' : '  UNSUPPORTED: ${p.unsupported.join(' | ')}');
  }
}
