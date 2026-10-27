/// The computer player: heuristic and deterministic (its only randomness is its own seeded
/// generator). It plays its most expensive affordable card, sends units to battlefields it can
/// take, answers in showdowns with removal, and ends its turn.
library;

import 'package:tcg_core/tcg_core.dart';

import '../cards/card.dart';
import '../game/game.dart';
import '../game/moves.dart';
import '../game/state.dart';
import '../ir.dart';
import '../parser/parser.dart';

class RiftboundBot implements TcgBot {
  RiftboundBot(this.seat, {int seed = 1}) : _rng = SeededRng(seed);
  final int seat;
  final SeededRng _rng;

  /// Moves that failed this turn (so it doesn't retry them). Only looked up, never iterated.
  final Set<String> _failed = {};
  int _turnSeen = -1;

  /// The next move for this seat, or null if it isn't this seat's to make.
  RMove? next(Game g) {
    final s = g.state;
    if (s.over) return null;
    final d = g.pending?.decision;
    if (d != null) return d.player == seat ? AnswerMove(seat, answer(g, d)) : null;
    if (g.toAct != seat) return null;
    if (_turnSeen != s.turn) {
      _turnSeen = s.turn;
      _failed.clear();
    }
    final legal = [
      for (final m in g.legalMoves(seat))
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
        g.apply(AnswerMove(seat, Game.defaultAnswer(g.pending!.decision)));
      } else if (g.toAct == seat && g.pending == null) {
        // Fall back to passing or ending the turn.
        final fallback = g.legalMoves(seat).where((x) => x is PassMove || x is EndTurnMove).firstOrNull;
        if (fallback != null) g.apply(fallback);
      }
    }
    return true;
  }

  RMove _choose(Game g, List<RMove> legal) {
    final s = g.state;
    final passOrEnd = legal.where((m) => m is PassMove || m is EndTurnMove).firstOrNull ?? legal.last;
    // In a showdown or with the chain open: removal and pump only, when it matters.
    if (s.chain.isNotEmpty || s.showdown != null) {
      for (final m in legal) {
        if (m is PlayMove && _isInteraction(g, g.card(m.card))) return m;
      }
      // Ambush and Reaction units join a combat now and then.
      if (s.showdown?.combat ?? false) {
        for (final m in legal) {
          if (m is PlayMove && g.card(m.card).type == CardType.unit && _rng.nextInt(2) == 0) return m;
        }
      }
      return passOrEnd;
    }
    // Hide a card with Hidden now and then: it can be played free on a later turn.
    final hides = legal.whereType<HideMove>().toList();
    if (hides.isNotEmpty && _rng.nextInt(3) == 0) return hides.first;
    // Main phase: play the most expensive card it can.
    final plays = legal.whereType<PlayMove>().toList()..sortStable((a, b) => g.card(b.card).energy - g.card(a.card).energy);
    if (plays.isNotEmpty) return plays.first;
    final acts = legal.whereType<ActivateMove>().where((m) => !_wasteful(g, m)).toList();
    if (acts.isNotEmpty && _rng.nextInt(2) == 0) return acts.first;
    final move = _attack(g);
    if (move != null && legal.any((m) => m is MoveUnitsMove)) return move;
    return passOrEnd;
  }

  /// Adding resources with nothing to spend them on wastes them.
  bool _wasteful(Game g, ActivateMove m) {
    if (m.index < 0) return false;
    final a = g.parsed(m.source).abilities[m.index];
    return a is Activated && a.effects.every((e) => e is AddRes);
  }

  bool _isInteraction(Game g, RCard c) {
    if (c.type != CardType.spell) return false;
    final abs = RiftboundParser.parse(c).abilities;
    return abs.any((a) => a is SpellBody && a.effects.any((e) => e is Deal || e is Kill || e is Stun || e is GiveMight || e is Counter));
  }

  /// Sends ready units from base to the battlefield it can best take or hold.
  RMove? _attack(Game g) {
    final s = g.state;
    final ready = [for (final u in g.unitsAt(base, player: seat)) if (!s.obj(u).exhausted) u]..sortStable((a, b) => g.might(b) - g.might(a));
    if (ready.isEmpty) return null;
    final total = ready.fold<int>(0, (t, u) => t + g.mightUsed(u));
    int? best;
    var bestScore = -1000000;
    for (var i = 0; i < s.bfs.length; i++) {
      final enemy = g.unitsAt(i, player: s.other(seat)).fold<int>(0, (t, u) => t + g.mightUsed(u));
      final controlled = s.bfs[i].controller == seat;
      if (controlled && enemy == 0) continue;
      if (total <= enemy) continue;
      final score = (controlled ? 0 : 10) - enemy;
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    if (best == null) return null;
    final enemy = g.unitsAt(best, player: s.other(seat)).fold<int>(0, (t, u) => t + g.mightUsed(u));
    final group = <ObjId>[];
    var sum = 0;
    for (final u in ready) {
      group.add(u);
      sum += g.mightUsed(u);
      if (sum > enemy + 1) break;
    }
    return MoveUnitsMove(seat, group, best);
  }

  /// Answers a decision the way a reasonable player would.
  List<int> answer(Game g, Decision d) {
    final s = g.state;
    switch (d.kind) {
      case DecisionKind.yesNo:
        return const [1];
      case DecisionKind.option:
        // Where to play a unit: a battlefield it controls if there is one (it helps hold).
        if (d.prompt.contains('where?')) return [d.labels.length - 1];
        return const [0];
      case DecisionKind.cards:
        final p = d.prompt.toLowerCase();
        if (p.startsWith('mulligan')) {
          final expensive = [for (final id in d.options) if (g.card(id).energy >= 6) id];
          return expensive.take(d.max).toList();
        }
        if (p.startsWith('predict')) {
          final runes = s.player(seat).runes.length;
          return [for (final id in d.options) if (g.card(id).energy > runes + 2) id];
        }
        if (p.startsWith('discard')) {
          final byCost = List.of(d.options)..sortStable((a, b) => g.card(b).energy - g.card(a).energy);
          return byCost.take(d.min).toList();
        }
        if (p.contains('counter')) return [d.options.first];
        // Costs paid with its own units: the least valuable.
        if (p.contains('to sacrifice')) {
          final byValue = List.of(d.options)..sortStable((a, b) => _value(g, a) - _value(g, b));
          return byValue.take(d.min > 0 ? d.min : 1).toList();
        }
        // "Buff up to N": as many of its own units as allowed.
        if (p.contains('up to') && p.contains('to buff')) {
          final mine = [for (final id in d.options) if (s.objOrNull(id)?.controller == seat) id];
          return mine.take(d.max).toList();
        }
        // Kill more units only if they're the opponent's; pay a kill cost with the weakest.
        if (p.startsWith('kill another')) {
          final theirs = [for (final id in d.options) if (s.objOrNull(id)?.controller != seat) id];
          return theirs.take(d.max).toList();
        }
        if (p.startsWith('kill a')) {
          final weakest = List.of(d.options)..sortStable((a, b) => _value(g, a) - _value(g, b));
          return weakest.take(d.min).toList();
        }
        // Buffs, readying, healing and "+N Might" or a keyword go on its own units; the rest at the opponent's.
        final friendlyWanted = p.contains('to buff') || p.contains('to ready') || p.contains('to heal') || p.contains('give +') || RegExp(r'to give [A-Z]').hasMatch(d.prompt);
        final mine = [for (final id in d.options) if (s.objOrNull(id)?.controller == seat) id];
        final theirs = [for (final id in d.options) if (s.objOrNull(id)?.controller != seat) id];
        final pool = friendlyWanted ? (mine.isNotEmpty ? mine : theirs) : (theirs.isNotEmpty ? theirs : mine);
        final n = d.min > 0 ? d.min : (d.max > 0 ? 1 : 0);
        final ranked = List.of(pool)..sortStable((a, b) => _value(g, b) - _value(g, a));
        final pick = ranked.take(n).toList();
        return pick.length < d.min ? d.options.take(d.min).toList() : pick;
    }
  }

  int _value(Game g, ObjId id) {
    final o = g.state.objOrNull(id);
    if (o == null || o.zone != Zone.board) return 0;
    return g.isUnit(id) ? g.might(id) * 10 + (o.loc == base ? 0 : 5) : 3;
  }
}

/// Lets [bots] play [g] until it's over (or [maxMoves]); true if the game finished.
bool runBots(Game g, List<RiftboundBot> bots, {int maxMoves = 3000}) {
  for (var i = 0; i < maxMoves && !g.over; i++) {
    final seat = g.toAct;
    if (seat == null) break;
    if (!bots[seat].step(g)) break;
  }
  return g.over;
}
