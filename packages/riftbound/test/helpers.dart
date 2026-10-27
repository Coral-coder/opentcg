import 'dart:convert';
import 'dart:io';

import 'package:riftbound/riftbound.dart';

final RCardDb db = RCardDb.fromJson(jsonDecode(File('../../data/riftbound-cards.json').readAsStringSync()) as Map<String, dynamic>);

/// Player 0's turn, Main Phase, two battlefields (Grove of the God-Willow, Zaun Warrens), no cards.
Game emptyGame({int active = 0, List<String> battlefields = const ['Grove of the God-Willow', 'Zaun Warrens']}) => Game(db, players: ['A', 'B'], seed: 1)..setUpEmpty(battlefields: battlefields, active: active);

/// Answers the pending decision (for [player], default whoever is asked).
void answer(Game g, List<int> a, {int? player}) => g.apply(AnswerMove(player ?? g.pending!.decision.player, a));

/// Passes until nothing is open (both players pass every chain item and showdown).
void passAll(Game g, {int limit = 20}) {
  for (var i = 0; i < limit && !g.over; i++) {
    final s = g.state;
    if (g.pending != null) return;
    if (s.chain.isEmpty && s.showdown == null) return;
    g.apply(PassMove(g.toAct!));
  }
}

/// A legal 1v1 deck for the first playable legend (a starter deck).
List<String> starter([int i = 0]) => buildDeck(db, playableLegends(db)[i]);
