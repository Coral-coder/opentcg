/// The computer player's answers to the decisions of game/costs.dart: additional costs, modes,
/// and which card to play, kill or recycle.
library;

import 'package:tcg_core/tcg_core.dart';

import '../game/game.dart';
import '../game/state.dart';

int _value(Game g, ObjId id) {
  final o = g.state.objOrNull(id);
  if (o == null) return 0;
  if (o.zone != Zone.board) return g.card(id).energy;
  return g.isUnit(id) ? g.might(id) * 10 + (o.loc == base ? 0 : 5) : 3;
}

/// Picks a mode by what it does: answers to the opponent's spells, removal, then card draw.
int costsMode(Game g, int seat, List<String> labels) {
  final enemySpell = g.state.chain.any((it) => it.isSpell && it.controller != seat);
  int score(String l) {
    final s = l.toLowerCase();
    if (s.startsWith('counter')) return enemySpell ? 9 : 0;
    var n = 1;
    if (s.contains('kill')) n = 6;
    if (s.contains('deal')) n = 5;
    if (s.contains('stun')) n = 4;
    if (s.contains('enemy')) n += 1;
    if (s.contains('draw') || s.contains('play ')) n = 3;
    if (s.contains('return a friendly')) n = 0;
    return n;
  }

  var best = 0;
  for (var i = 1; i < labels.length; i++) {
    if (score(labels[i]) > score(labels[best])) best = i;
  }
  return best;
}

/// Answers to card choices of game/costs.dart, or null to use the bot's usual rules.
List<int>? costsCards(Game g, int seat, Decision d) {
  final p = d.prompt.toLowerCase();
  List<int> cheapest(int n) => (List.of(d.options)..sortStable((a, b) => _value(g, a) - _value(g, b))).take(n).toList();
  List<int> dearest(int n) => (List.of(d.options)..sortStable((a, b) => _value(g, b) - _value(g, a))).take(n).toList();
  // Costs are paid with what's worth least; optional "any number" costs aren't paid.
  if (p.startsWith('cost:')) return cheapest(d.min);
  if (p.startsWith('kill one of your units')) return cheapest(1);
  if (p.contains('choose a unit to recycle')) return cheapest(1);
  if (p.startsWith('play which') || p.contains('choose a card to play')) return dearest(d.min > 0 ? d.min : 1);
  if (p.contains('to recycle') && p.contains('opponents')) return d.options.take(d.max).toList();
  if (p.startsWith('choose units to move')) return List.of(d.options);
  return null;
}
