/// Everything a player can do (rulebook: "Your Turn"), plus answers to decisions: the unit of
/// replay and of lockstep sync. A match is its seed plus its ordered moves.
library;

import 'package:tcg_core/tcg_core.dart';

sealed class PMove extends TcgMove {
  const PMove(this.seat);
  @override
  final int seat;

  static PMove fromJson(Map<String, dynamic> j) {
    final p = j['p'] as int? ?? -1;
    return switch (j['t'] as String) {
      'start' => StartMove([for (final d in j['decks'] as List) (d as List).cast<String>()], firstPlayer: j['first'] as int?),
      'answer' => AnswerMove(p, (j['a'] as List).cast<int>()),
      'basic' => PlayBasicMove(p, j['c'] as int),
      'evolve' => EvolveMove(p, j['c'] as int, j['o'] as int),
      'energy' => AttachEnergyMove(p, j['c'] as int, j['o'] as int),
      'trainer' => TrainerMove(p, j['c'] as int, target: j['o'] as int?),
      'retreat' => RetreatMove(p, j['o'] as int),
      'ability' => AbilityMove(p, j['c'] as int, j['i'] as int),
      'attack' => AttackMove(p, j['i'] as int),
      'end' => EndTurnMove(p),
      'concede' => ConcedeMove(p),
      final t => throw ArgumentError('Unknown move $t'),
    };
  }

  @override
  String toString() => toJson().toString();
}

/// Deals the match: one deck (card keys) per seat. [firstPlayer] fixes who goes first;
/// otherwise a coin flip from the seed decides who chooses.
class StartMove extends PMove {
  const StartMove(this.decks, {this.firstPlayer}) : super(-1);
  final List<List<String>> decks;
  final int? firstPlayer;
  @override
  Map<String, dynamic> toJson() => {'t': 'start', 'decks': decks, if (firstPlayer != null) 'first': firstPlayer};
}

class AnswerMove extends PMove {
  const AnswerMove(super.seat, this.answer);
  final List<int> answer;
  @override
  Map<String, dynamic> toJson() => {'t': 'answer', 'p': seat, 'a': answer};
}

/// Put a Basic Pokémon from your hand onto your Bench.
class PlayBasicMove extends PMove {
  const PlayBasicMove(super.seat, this.card);
  final int card;
  @override
  Map<String, dynamic> toJson() => {'t': 'basic', 'p': seat, 'c': card};
}

/// Evolve [target] with [card] from your hand.
class EvolveMove extends PMove {
  const EvolveMove(super.seat, this.card, this.target);
  final int card, target;
  @override
  Map<String, dynamic> toJson() => {'t': 'evolve', 'p': seat, 'c': card, 'o': target};
}

/// Attach an Energy card from your hand (once per turn).
class AttachEnergyMove extends PMove {
  const AttachEnergyMove(super.seat, this.card, this.target);
  final int card, target;
  @override
  Map<String, dynamic> toJson() => {'t': 'energy', 'p': seat, 'c': card, 'o': target};
}

/// Play a Trainer card; a Pokémon Tool goes onto [target].
class TrainerMove extends PMove {
  const TrainerMove(super.seat, this.card, {this.target});
  final int card;
  final int? target;
  @override
  Map<String, dynamic> toJson() => {'t': 'trainer', 'p': seat, 'c': card, if (target != null) 'o': target};
}

/// Retreat your Active Pokémon, switching it with [to] from your Bench.
class RetreatMove extends PMove {
  const RetreatMove(super.seat, this.to);
  final int to;
  @override
  Map<String, dynamic> toJson() => {'t': 'retreat', 'p': seat, 'o': to};
}

class AbilityMove extends PMove {
  const AbilityMove(super.seat, this.card, this.index);
  final int card, index;
  @override
  Map<String, dynamic> toJson() => {'t': 'ability', 'p': seat, 'c': card, 'i': index};
}

/// Attack with your Active Pokémon (ends your turn).
class AttackMove extends PMove {
  const AttackMove(super.seat, this.index);
  final int index;
  @override
  Map<String, dynamic> toJson() => {'t': 'attack', 'p': seat, 'i': index};
}

class EndTurnMove extends PMove {
  const EndTurnMove(super.seat);
  @override
  Map<String, dynamic> toJson() => {'t': 'end', 'p': seat};
}

class ConcedeMove extends PMove {
  const ConcedeMove(super.seat);
  @override
  Map<String, dynamic> toJson() => {'t': 'concede', 'p': seat};
}
