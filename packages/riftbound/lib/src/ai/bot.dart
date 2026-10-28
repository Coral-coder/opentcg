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
import 'bot_costs.dart';

part 'bot_equip.dart';

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
    // Choosing only reads the game (legality is tried on copies).
    return g.readOnly(() => _choose(g, _Legal(g, seat, _failed)));
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

  // The choice is made over the legal moves, but checking a move tries it on a copy of the game,
  // so each step below checks only the moves it looks at, in the order it looks at them. The
  // choices (and the random draws) are the same as filtering the whole list first.
  RMove _choose(Game g, _Legal legal) {
    final s = g.state;
    RMove passOrEnd() => legal.first((m) => m is PassMove || m is EndTurnMove) ?? legal.all.last;
    // In a showdown or with the chain open: removal and pump only, when it matters.
    if (s.chain.isNotEmpty || s.showdown != null) {
      final hit = legal.first((m) => m is PlayMove && _isInteraction(g, g.card(m.card)));
      if (hit != null) return hit;
      // Ambush and Reaction units join a combat now and then.
      if (s.showdown?.combat ?? false) {
        final joined = legal.first((m) => m is PlayMove && g.card(m.card).type == CardType.unit, then: (_) => _rng.nextInt(2) == 0);
        if (joined != null) return joined;
      }
      return passOrEnd();
    }
    // Hide a card with Hidden now and then: it can be played free on a later turn.
    final hide = legal.first((m) => m is HideMove);
    if (hide != null && _rng.nextInt(3) == 0) return hide;
    // Main phase: play the most expensive card it can.
    final play = legal.firstIn(legal.candidates.whereType<PlayMove>().toList()..sortStable((a, b) => g.card(b.card).energy - g.card(a.card).energy));
    if (play != null) return play;
    final equip = _equipMove(g, legal);
    if (equip != null) return equip;
    final act = legal.first((m) => m is ActivateMove && !_wasteful(g, m));
    if (act != null && _rng.nextInt(2) == 0) return act;
    final move = _attack(g);
    if (move != null && legal.first((m) => m is MoveUnitsMove) != null) return move;
    return passOrEnd();
  }

  /// Adding resources with nothing to spend them on wastes them.
  bool _wasteful(Game g, ActivateMove m) {
    final a = g.abilityOfMove(m);
    return a is Activated && a.effects.every((e) => e is AddRes);
  }

  bool _isInteraction(Game g, RCard c) {
    if (c.type != CardType.spell) return false;
    final abs = RiftboundParser.parse(c).abilities;
    bool hits(Effect e) => e is Deal || e is Kill || e is Stun || e is GiveMight || e is Counter || e is Fight || e is CounterByCost || e is StealOrCounter || e is KillThenReplay || e is IfElse || (e is Modes && e.modes.any((m) => m.any(hits)));
    return abs.any((a) => a is SpellBody && a.effects.any(hits));
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
    final eq = _equipAnswer(g, d);
    if (eq != null) return eq;
    switch (d.kind) {
      case DecisionKind.yesNo:
        return const [1];
      case DecisionKind.option:
        // Where to play a unit: a battlefield it controls if there is one (it helps hold).
        if (d.prompt.contains('where?')) return [d.labels.length - 1];
        if (d.prompt.endsWith('choose a mode')) return [costsMode(g, seat, d.labels)];
        // "Pay any amount of {A}": as much as it can.
        if (d.prompt.endsWith('pay how many {A}?')) return [d.labels.length - 1];
        return const [0];
      case DecisionKind.cards:
        final p = d.prompt.toLowerCase();
        final x = costsCards(g, seat, d);
        if (x != null) return x;
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
        // Combat damage: lethal to the weakest first (offered first), killing as many as it can.
        if (p.startsWith('combat damage')) return [d.options.first];
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

/// The legal moves for [seat], checked one at a time as the bot asks about them (in the order of
/// [Game.candidateMoves], skipping moves that failed this turn), each at most once.
class _Legal {
  _Legal(this.g, this.seat, this.failed) : candidates = g.candidateMoves(seat);
  final Game g;
  final int seat;
  final Set<String> failed;
  final List<RMove> candidates;
  final Map<RMove, bool> _ok = Map.identity();

  bool ok(RMove m) => _ok[m] ??= !failed.contains(m.toString()) && (m is PassMove || m is EndTurnMove || g.whyNot(m) == null);

  /// The first legal candidate passing [test] (checked before legality) and then [then] (asked
  /// only of legal ones, in order: it may draw from the bot's random numbers).
  RMove? first(bool Function(RMove m) test, {bool Function(RMove m)? then}) {
    for (final m in candidates) {
      if (test(m) && ok(m) && (then == null || then(m))) return m;
    }
    return null;
  }

  /// The first of [moves] (candidates, reordered) that is legal.
  RMove? firstIn(List<RMove> moves) {
    for (final m in moves) {
      if (ok(m)) return m;
    }
    return null;
  }

  /// Every legal candidate.
  List<RMove> get all => [for (final m in candidates) if (ok(m)) m];
}
