/// The computer player: heuristic and deterministic (its only randomness is its own seeded
/// generator). It fills its Bench, evolves, attaches Energy to the Pokémon that needs it,
/// plays Trainers and Abilities, retreats a Pokémon that can't attack, and attacks with the
/// strongest attack it can pay for.
library;

import 'package:tcg_core/tcg_core.dart';

import '../game/game.dart';
import '../game/moves.dart';
import '../game/state.dart';

class PokemonBot implements TcgBot {
  PokemonBot(this.seat, {int seed = 1}) : _rng = SeededRng(seed);
  final int seat;
  final SeededRng _rng;

  /// Moves that failed this turn (so it doesn't retry them). Only looked up, never iterated.
  final Set<String> _failed = {};
  int _turnSeen = -1;

  /// The next move for this seat, or null if it isn't this seat's to make.
  PMove? next(Game g) {
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
      if (m is AnswerMove) g.apply(AnswerMove(seat, g.defaultAnswer(g.pending!.decision)));
    }
    return true;
  }

  /// How much the bot wants [id] in the Active Spot.
  int _strength(Game g, CardId id) {
    final c = g.card(id);
    var v = c.hp - g.state.obj(id).damage + g.state.obj(id).energy.length * 30;
    for (var i = 0; i < c.attacks.length; i++) {
      if (g.hasEnergyFor(id, i)) v += c.attacks[i].damage + 20;
    }
    return v;
  }

  List<int> answer(Game g, Decision d) {
    switch (d.kind) {
      case DecisionKind.yesNo:
        return const [1];
      case DecisionKind.option:
        // "Go first", or the most cards to draw.
        return d.prompt.startsWith('You won') ? const [0] : [d.labels.length - 1];
      case DecisionKind.cards:
        final opts = List.of(d.options);
        final p = d.prompt;
        if (p.contains('Active Pokémon')) {
          opts.sortStable((a, b) => _strength(g, b) - _strength(g, a));
          return [opts.first];
        }
        if (p.startsWith('Switch in which of your opponent')) {
          // Bring up the weakest.
          opts.sortStable((a, b) => _strength(g, a) - _strength(g, b));
          return [opts.first];
        }
        _rng.shuffle(opts);
        // Discarding and paying: as few as allowed; searching and benching: as many.
        final few = p.startsWith('Discard') || p.contains('Damage') || p.contains('damage');
        final k = few ? d.min : d.max;
        return opts.take(k).toList();
    }
  }

  PMove _choose(Game g, List<PMove> legal) {
    final s = g.state;
    final pl = s.player(seat);
    final active = pl.active;
    PMove? pick(bool Function(PMove) f) {
      for (final m in legal) {
        if (f(m)) return m;
      }
      return null;
    }

    // Bench Basics (up to 4, keeping room), then evolve.
    final basic = pick((m) => m is PlayBasicMove);
    if (basic != null && pl.bench.length < 4) return basic;
    final evolve = pick((m) => m is EvolveMove);
    if (evolve != null) return evolve;
    // Energy: to the Active if it still needs some for its best attack, else the Bench.
    final energies = [for (final m in legal) if (m is AttachEnergyMove) m];
    if (energies.isNotEmpty) {
      final needy = [for (final m in energies) if (_needsEnergy(g, m.target)) m];
      final toActive = [for (final m in needy) if (m.target == active) m];
      if (toActive.isNotEmpty) return toActive.first;
      if (needy.isNotEmpty) return needy[_rng.nextInt(needy.length)];
      return energies.first;
    }
    final ability = pick((m) => m is AbilityMove);
    if (ability != null) return ability;
    final trainers = [for (final m in legal) if (m is TrainerMove) m];
    if (trainers.isNotEmpty && _rng.nextInt(4) != 0) return trainers[_rng.nextInt(trainers.length)];
    // Retreat a Pokémon that can't attack for one that can.
    if (active != null && !_canAttack(g, active)) {
      for (final m in legal) {
        if (m is RetreatMove && _canAttack(g, m.to)) return m;
      }
    }
    // Attack with the attack doing the most printed damage.
    final attacks = [for (final m in legal) if (m is AttackMove) m];
    if (attacks.isNotEmpty && active != null) {
      final c = g.card(active);
      attacks.sortStable((a, b) => c.attacks[b.index].damage - c.attacks[a.index].damage);
      return attacks.first;
    }
    return legal.firstWhere((m) => m is EndTurnMove, orElse: () => EndTurnMove(seat));
  }

  bool _canAttack(Game g, CardId id) {
    for (var i = 0; i < g.card(id).attacks.length; i++) {
      if (g.hasEnergyFor(id, i)) return true;
    }
    return false;
  }

  bool _needsEnergy(Game g, CardId id) {
    final atk = g.card(id).attacks;
    if (atk.isEmpty) return false;
    var most = 0;
    for (final a in atk) {
      if (a.cost.length > most) most = a.cost.length;
    }
    return g.state.obj(id).energy.length < most;
  }
}

/// Plays [g] with [bots] (one per seat) until it ends or [maxMoves] moves are made. Returns
/// whether it ended.
bool runBots(Game g, List<PokemonBot> bots, {int maxMoves = 3000}) {
  for (var i = 0; i < maxMoves && !g.over; i++) {
    final seat = g.toAct;
    if (seat == null) break;
    if (!bots[seat].step(g)) break;
  }
  return g.over;
}
