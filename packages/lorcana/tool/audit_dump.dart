/// Dumps every supported card's text next to its parsed abilities, for auditing misreads.
/// With --flag, prints only cards whose text and parse disagree on simple signals (words the
/// parse should reflect, such as "may", "undamaged", "this turn", numbers).
///
///     dart run tool/audit_dump.dart ../../data/lorcana-cards.json [--flag]
library;

import 'dart:convert';
import 'dart:io';

import 'package:lorcana/lorcana.dart';
import 'package:lorcana/src/parser/text.dart';

void main(List<String> args) {
  final db = LCardDb.fromJson(jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>);
  final flag = args.contains('--flag');
  for (final c in db.cards) {
    final p = LorcanaParser.parse(c);
    if (!p.supported) continue;
    final text = normalizeText(c.text);
    final ir = [for (final a in p.abilities) describeAbility(a)];
    final irText = ir.join(' ').toLowerCase();
    final reasons = <String>[];
    if (flag) {
      final t = text.toLowerCase().replaceAll(RegExp(r'\([^)]*\)'), '');
      void check(String word, bool ok) {
        if (t.contains(word) && !ok) reasons.add(word);
      }

      check('undamaged', irText.contains('dmg') || irText.contains('damage') || irText.contains('undamaged'));
      check('damaged character', irText.contains('dmg') || irText.contains('damaged'));
      check(' may ', irText.contains('may') || irText.contains('up to') || irText.contains('optional'));
      check('this turn', irText.contains('turn'));
      check('opposing', irText.contains('opp'));
      check('each opponent', irText.contains('opp'));
      check(' if ', irText.contains('if') || irText.contains('when') || irText.contains('while'));
      check('while ', irText.contains('while') || irText.contains('if'));
      check('instead', irText.contains('instead') || irText.contains('else'));
      check('for each', irText.contains('#') || irText.contains('each') || irText.contains('×'));
      check('at random', irText.contains('random'));
      check('exerted', irText.contains('exert'));
      check("can't", irText.contains('cant') || irText.contains("can't") || irText.contains('rule'));
      for (final m in RegExp(r'\b(\d+)\b').allMatches(t)) {
        if (!irText.contains(m.group(1)!)) reasons.add('number ${m.group(1)}');
      }
      if (ir.isEmpty) reasons.add('no abilities');
      if (reasons.isEmpty) continue;
    }
    stdout.writeln('## ${c.fullName}${reasons.isEmpty ? '' : '   [${reasons.join(', ')}]'}\n  $text');
    for (final a in ir) {
      stdout.writeln('  = $a');
    }
  }
}
