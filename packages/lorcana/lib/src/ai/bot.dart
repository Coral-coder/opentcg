/// The computer player: heuristic and deterministic (its only randomness is its own seeded
/// generator). It inks a card each turn, plays the best cards it can afford, challenges when the
/// trade is good, quests with the rest, and answers every decision.
library;

import 'package:tcg_core/tcg_core.dart';

import '../cards/card.dart';
import '../game/game.dart';
import '../game/moves.dart';
import '../game/state.dart';
import '../ir.dart';

class LorcanaBot implements TcgBot {
  LorcanaBot(this.seat, {int seed = 1}) : _rng = SeededRng(seed);
  final int seat;
  final SeededRng _rng;

  /// Moves that failed this turn (so it doesn't retry them).
  final Set<String> _failed = {};
  int _turnSeen = -1;

  /// The next move for this seat, or null if it isn't this seat's to make.
  LMove? next(Game g) {
    final s = g.state;
    if (s.over) return null;
    final d = g.pending?.decision;
    if (d != null) return d.player == seat ? AnswerMove(seat, answer(g, d)) : null;
    if (s.phase != Phase.main || s.active != seat) return null;
    if (_turnSeen != s.turn) {
      _turnSeen = s.turn;
      _failed.clear();
    }
    final legal = [
      for (final m in g.legalMoves())
        if (!_failed.contains(m.toString())) m,
    ];
    return _choose(g, legal);
  }

  @override
  bool step(covariant Game g) {
    final m = next(g);
    if (m == null) return false;
    try {
      g.apply(m);
    } on TcgError {
      _failed.add(m.toString());
      if (m is AnswerMove) {
        g.apply(AnswerMove(seat, g.defaultAnswer(g.pending!.decision)));
      }
    }
    return true;
  }

  int _value(Game g, CardId id) {
    final c = g.db[g.state.obj(id).card]!;
    var v = c.cost * 3;
    if (c.type == CardType.character) v += (c.lore ?? 0) * 4 + (c.strength ?? 0) + (c.willpower ?? 0);
    return v;
  }

  LMove _choose(Game g, List<LMove> legal) {
    final s = g.state;
    final me = s.player(seat);
    // 1. Ink: once a turn while the inkwell is small or the hand is full.
    final inks = legal.whereType<InkMove>().toList();
    if (inks.isNotEmpty && (me.inkwell.length < 7 || me.hand.length > 4)) {
      inks.sortStable((a, b) {
        final d = _inkScore(g, a.card) - _inkScore(g, b.card);
        return d != 0 ? d : a.card - b.card;
      });
      return inks.first;
    }
    // 2. Play the most expensive card it can afford (ink first, then Shift, then singing).
    final plays = legal.whereType<PlayMove>().toList();
    if (plays.isNotEmpty) {
      plays.sortStable((a, b) {
        final ca = g.db[s.obj(a.card).card]!, cb = g.db[s.obj(b.card).card]!;
        final d = cb.cost - ca.cost;
        if (d != 0) return d;
        return a.mode.index - b.mode.index;
      });
      final best = plays.first;
      // Don't exert a character that could quest to sing a cheap song.
      if (best.mode != PlayMode.sing || g.db[s.obj(best.card).card]!.cost >= 3) return best;
    }
    // 3. Challenges that banish without losing the challenger, or that trade up.
    LMove? bestChallenge;
    var bestGain = 0;
    for (final m in legal.whereType<ChallengeMove>()) {
      final a = g.chars(m.card), d = g.chars(m.target);
      final ao = s.obj(m.card), dobj = s.obj(m.target);
      final dmg = a.strengthAtLeast0 + (a.has(Kw.challenger) ? a.n(Kw.challenger) : 0) - (d.has(Kw.resist) ? d.n(Kw.resist) : 0);
      final kills = dobj.damage + dmg >= d.willpower;
      final back = d.type == CardType.character ? d.strengthAtLeast0 - (a.has(Kw.resist) ? a.n(Kw.resist) : 0) : 0;
      final dies = ao.damage + back >= a.willpower;
      if (!kills) continue;
      final gain = _value(g, m.target) + (d.type == CardType.location ? d.lore * 4 : 0) - (dies ? _value(g, m.card) : 0) - (a.loreAtLeast0 * 3);
      if (gain > bestGain || (a.has(Kw.reckless) && bestChallenge == null)) {
        bestGain = gain;
        bestChallenge = m;
      }
    }
    if (bestChallenge != null) return bestChallenge;
    // Reckless characters must challenge before the turn can end.
    final end = legal.whereType<EndTurnMove>().firstOrNull;
    if (end == null) {
      final forced = legal.whereType<ChallengeMove>().firstOrNull;
      if (forced != null) return forced;
    }
    // 4. Quest with every character that can.
    final quests = legal.whereType<QuestMove>().toList();
    if (quests.isNotEmpty) return quests.first;
    // 5. Items and locations: use cheap activated abilities, move characters to locations.
    for (final m in legal.whereType<ActivateMove>()) {
      final c = g.chars(m.card);
      if (c.type != CardType.character && _rng.nextInt(3) > 0) return m;
    }
    final moves = legal.whereType<MoveMove>().toList();
    if (moves.isNotEmpty && _rng.nextInt(2) == 0) return moves.first;
    return end ?? legal.first;
  }

  /// Lower is better to ink: duplicates and expensive cards it can't use soon.
  int _inkScore(Game g, CardId id) {
    final c = g.db[g.state.obj(id).card]!;
    final ink = g.state.player(seat).inkwell.length;
    return (c.cost <= ink + 1 ? 10 : 0) + _value(g, id) ~/ 4;
  }

  List<int> answer(Game g, Decision d) {
    final s = g.state;
    switch (d.kind) {
      case DecisionKind.cards:
        final p = d.prompt.toLowerCase();
        if (p.startsWith('alter your hand')) {
          final ink = d.options.where((id) => g.db[s.obj(id).card]!.inkable).length;
          return [
            for (final id in d.options)
              if (g.db[s.obj(id).card]!.cost >= 6 || (ink < 3 && !g.db[s.obj(id).card]!.inkable && g.db[s.obj(id).card]!.cost >= 4)) id,
          ];
        }
        final opts = List.of(d.options);
        final losing = p.contains('discard') || p.contains('bottom') || p.contains('banish one for the cost') || p.contains('exert one for the cost');
        if (losing) {
          opts.sortStable((a, b) => _value(g, a) - _value(g, b));
          return opts.take(d.min < 1 && d.max > 0 && !p.contains('alter') ? d.max.clamp(0, 1) : d.min).toList();
        }
        // Targets: harmful effects go to the opponent's best card, helpful ones to ours.
        final harmful = _harmful(g, d);
        int score(CardId id) {
          final mine = s.obj(id).owner == seat;
          final v = _value(g, id);
          return harmful ? (mine ? -1000 - v : v) : (mine ? v : -1000 - v);
        }

        opts.sortStable((a, b) => score(b) - score(a));
        final n = d.min == 0 ? (score(opts.first) > 0 ? 1 : 0).clamp(0, d.max) : d.min;
        return opts.take(n == 0 && d.min > 0 ? d.min : n).toList();
      case DecisionKind.yesNo:
        return const [1];
      case DecisionKind.option:
        return [_rng.nextInt(d.labels.length)];
      case DecisionKind.order:
        return List.of(d.options);
    }
  }

  bool _harmful(Game g, Decision d) {
    final src = d.source;
    if (src == null || g.state.objOrNull(src) == null) return true;
    final text = g.db[g.state.obj(src).card]!.text.toLowerCase();
    if (RegExp(r'(deal|banish|exert|return|-\d|can.t|shuffle|loses)').hasMatch(text)) return true;
    return !RegExp(r'(gets \+|gains|remove|ready|move)').hasMatch(text);
  }
}

/// Runs bots until the match ends, nobody can move, or [maxMoves] moves were made.
bool runBots(Game g, List<LorcanaBot> bots, {int maxMoves = 3000}) {
  for (var i = 0; i < maxMoves && !g.over; i++) {
    final p = g.toAct;
    if (p == null) return g.over;
    if (!bots[p].step(g)) return g.over;
  }
  return g.over;
}
