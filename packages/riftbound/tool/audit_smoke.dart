/// Plays every supported spell (and every unit or gear with a "when you play me" ability) on a
/// busy board and lists the ones whose play changed nothing but paying for them: abilities that
/// parse but do nothing. A listed card isn't necessarily wrong (a "may" the bot declined, a
/// condition the board doesn't meet), but each needs a look.
///
///     dart run tool/audit_smoke.dart [cards.json] [--only NAME]
library;

import 'dart:convert';
import 'dart:io';

import 'package:riftbound/riftbound.dart';

void main(List<String> argv) {
  final pos = [for (final a in argv) if (!a.startsWith('--')) a];
  final only = argv.contains('--only') ? argv[argv.indexOf('--only') + 1] : null;
  final db = RCardDb.fromJson(jsonDecode(File(pos.isNotEmpty && pos[0].endsWith('.json') ? pos[0] : '../../data/riftbound-cards.json').readAsStringSync()) as Map<String, dynamic>);
  var tried = 0, quiet = 0, unplayable = 0, errors = 0;
  for (final c in db.cards) {
    if (only != null && c.name != only) continue;
    final p = RiftboundParser.parseUncached(c);
    if (!p.supported) continue;
    final onPlay = p.abilities.any((a) => describeAbility(a).startsWith('TRIG played') || describeAbility(a).startsWith('TRIG legion played'));
    if (!(c.type == CardType.spell || ((c.type == CardType.unit || c.type == CardType.gear) && onPlay))) continue;
    tried++;
    final g = _board(db);
    final id = g.addCard(c.name, 0);
    if (g.whyNot(PlayMove(0, id)) != null) {
      unplayable++;
      stdout.writeln('UNPLAYABLE\t${c.name}\t${g.whyNot(PlayMove(0, id))}');
      continue;
    }
    final before = _sig(g, id);
    try {
      g.apply(PlayMove(0, id));
      _drive(g);
    } catch (e) {
      errors++;
      stdout.writeln('ERROR\t${c.name}\t$e');
      continue;
    }
    final after = _sig(g, id);
    final changed = [for (final k in before.keys) if (before[k] != after[k]) k, for (final k in after.keys) if (!before.containsKey(k)) k];
    if (changed.isEmpty) {
      quiet++;
      stdout.writeln('NO EFFECT\t${c.name}\t${c.text.replaceAll('\n', ' / ')}');
    } else if (changed.every((k) => k.startsWith('marks') || k.startsWith('gen'))) {
      stdout.writeln('ONLY MARKS\t${c.name}\t${changed.join(',')}\t${c.text.replaceAll('\n', ' / ')}');
    }
  }
  stdout.writeln('$tried cards tried: $quiet with no visible effect, $unplayable unplayable on the test board, $errors errors');
}

/// Player 0's turn with plenty of everything: units of both players at both battlefields and in
/// base (some buffed, exhausted, damaged, stunned), gear, cards in hands, decks and trashes.
Game _board(RCardDb db) {
  final g = Game(db, players: ['A', 'B'], seed: 1)..setUpEmpty(battlefields: ['Grove of the God-Willow', 'Zaun Warrens']);
  for (final p in [0, 1]) {
    for (final d in Domain.values) {
      g.addRunes(p, d, 4);
    }
    g.stackDeck(p, 'Daring Poro', 3);
    g.stackDeck(p, 'Discipline', 3);
    g.stackDeck(p, 'Heart of Dark Ice', 2);
    for (final k in ['Daring Poro', 'Discipline', 'Heart of Dark Ice', 'Vanguard Sergeant']) {
      g.addCard(k, p, zone: Zone.trash);
    }
    g.addCard('Daring Poro', p);
    g.addCard('Discipline', p);
    g.addCard('Heart of Dark Ice', p, zone: Zone.board);
    g.addCard('Vanguard Sergeant', p, zone: Zone.board);
    final a = g.addCard('Daring Poro', p, zone: Zone.board, loc: 0);
    g.addCard('Stalwart Poro', p, zone: Zone.board, loc: 0, exhausted: true);
    final b = g.addCard('Vanguard Sergeant', p, zone: Zone.board, loc: 1);
    g.state.obj(a).buffed = true;
    g.state.obj(b).damage = 1;
    g.state.player(p).pw.xp = 10;
  }
  final stunned = g.addCard('Daring Poro', 1, zone: Zone.board, loc: 1);
  g.state.obj(stunned).stunned = true;
  return g;
}

void _drive(Game g) {
  final bots = [RiftboundBot(0), RiftboundBot(1)];
  for (var i = 0; i < 300 && !g.over; i++) {
    final d = g.pending?.decision;
    if (d != null) {
      g.apply(AnswerMove(d.player, bots[d.player].answer(g, d)));
      continue;
    }
    if (g.state.chain.isEmpty && g.state.showdown == null) return;
    g.apply(PassMove(g.toAct!));
  }
}

/// What a card's effect could change, keyed by thing (the played card and runes left out).
Map<String, String> _sig(Game g, ObjId played) {
  final s = g.state;
  final out = <String, String>{};
  for (final o in s.objects.values) {
    if (o.id == played || o.zone == Zone.runes || o.zone == Zone.runeDeck) continue;
    out['obj${o.id}'] = '${o.card}|${o.zone}|${o.loc}|${o.controller}|${o.exhausted}|${o.damage}|${o.buffed}|${o.stunned}|${o.mightMod}|${g.might(o.id)}|${o.pw.digest()}';
  }
  for (var i = 0; i < s.players.length; i++) {
    final p = s.players[i];
    out['p$i'] = '${p.hand.where((x) => x != played).length}|${p.deck.length}|${p.trash.where((x) => x != played).length}|${p.banish.where((x) => x != played).length}|${p.points}|${p.pw.digest()}';
  }
  for (final b in s.bfs) {
    out['bf${b.obj}'] = b.digest();
  }
  out['eq'] = s.eq.digest();
  for (final e in s.marks.entries) {
    out['marks${e.key}'] = '${e.value}';
  }
  out['gen'] = s.gen.digest();
  out['victory'] = '${s.victoryScore}';
  return out;
}
