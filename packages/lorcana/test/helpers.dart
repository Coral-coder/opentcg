import 'dart:convert';
import 'dart:io';

import 'package:lorcana/lorcana.dart';

LCardDb? _db;

/// The full card database (built by bin/build_db.dart).
LCardDb get db => _db ??= LCardDb.fromJson(jsonDecode(File('../../data/lorcana-cards.json').readAsStringSync()) as Map<String, dynamic>);

const vanilla = 'Abu - Mischievous Monkey'; // 3 cost, 3/2, 2 lore, no text
const vanilla2 = 'Aladdin - Fearless Navigator'; // 2 cost, 2/3, 1 lore

/// An empty game at player 0's main phase, with [deck] cards in each deck so nobody decks out.
Game emptyGame({int deck = 10, int active = 0}) {
  final g = Game(db, players: ['A', 'B'], seed: 1)..startEmpty(active: active);
  for (var p = 0; p < 2; p++) {
    for (var i = 0; i < deck; i++) {
      g.addCard(vanilla2, p, Place.deck);
    }
  }
  return g;
}

/// Answers the pending decision, checking it belongs to [player].
void answer(Game g, List<int> a, {int? player}) {
  final d = g.pending!.decision;
  if (player != null && d.player != player) throw StateError('Decision is for ${d.player}: ${d.prompt}');
  g.apply(AnswerMove(d.player, a));
}

/// Expects [m] to be illegal.
bool illegal(Game g, LMove m) {
  try {
    g.apply(m);
    return false;
  } on LorcanaError {
    return true;
  }
}

List<String> deckOf(String name, [int n = 60]) => [for (var i = 0; i < n; i++) name];
