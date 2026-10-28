/// Everything a player can do (CR 300s: Discretionary Actions), plus answers to decisions: the
/// unit of replay and of lockstep sync. A match is its seed plus its ordered moves.
library;

import 'package:tcg_core/tcg_core.dart';

import 'state.dart' show RMode;

sealed class RMove extends TcgMove {
  const RMove(this.seat);
  @override
  final int seat;

  static RMove fromJson(Map<String, dynamic> j) {
    final p = j['p'] as int? ?? -1;
    return switch (j['t'] as String) {
      'start' => StartMove([for (final d in j['decks'] as List) (d as List).cast<String>()], firstPlayer: j['first'] as int?, mode: RMode.fromId(j['mode'] as String?)),
      'answer' => AnswerMove(p, (j['a'] as List).cast<int>()),
      'play' => PlayMove(p, j['c'] as int),
      'activate' => ActivateMove(p, j['c'] as int, j['i'] as int),
      'move' => MoveUnitsMove(p, (j['u'] as List).cast<int>(), j['to'] as int),
      'hide' => HideMove(p, j['c'] as int),
      'pass' => PassMove(p),
      'end' => EndTurnMove(p),
      'concede' => ConcedeMove(p),
      final t => throw ArgumentError('Unknown move $t'),
    };
  }

  @override
  String toString() => toJson().toString();
}

/// Deals the match. Each deck lists card names: its Champion Legend, Chosen Champion,
/// battlefields, 12 runes and Main Deck, in any order (the engine sorts them by type; the first
/// champion unit matching the legend's tag is the Chosen Champion). [firstPlayer] fixes who
/// goes first; otherwise the seed decides (CR 115).
class StartMove extends RMove {
  const StartMove(this.decks, {this.firstPlayer, this.mode = RMode.duel}) : super(-1);
  final List<List<String>> decks;
  final int? firstPlayer;

  /// The Mode of Play (CR 485); a Duel leaves it out of the JSON.
  final RMode mode;
  @override
  Map<String, dynamic> toJson() => {'t': 'start', 'decks': decks, if (firstPlayer != null) 'first': firstPlayer, if (mode != RMode.duel) 'mode': mode.id};
}

class AnswerMove extends RMove {
  const AnswerMove(super.seat, this.answer);
  final List<int> answer;
  @override
  Map<String, dynamic> toJson() => {'t': 'answer', 'p': seat, 'a': answer};
}

/// Play a card from your hand or your Champion Zone (CR 349). Where a unit goes, optional costs
/// and targets are asked as it's played.
class PlayMove extends RMove {
  const PlayMove(super.seat, this.card);
  final int card;
  @override
  Map<String, dynamic> toJson() => {'t': 'play', 'p': seat, 'c': card};
}

/// Activate ability [index] (of the source's parsed abilities) of a legend, unit or gear.
class ActivateMove extends RMove {
  const ActivateMove(super.seat, this.source, this.index);
  final int source, index;
  @override
  Map<String, dynamic> toJson() => {'t': 'activate', 'p': seat, 'c': source, 'i': index};
}

/// The Standard Move (CR 144): exhaust [units] to move them together to [to] (base: -1, else a
/// battlefield's index).
class MoveUnitsMove extends RMove {
  const MoveUnitsMove(super.seat, this.units, this.to);
  final List<int> units;
  final int to;
  @override
  Map<String, dynamic> toJson() => {'t': 'move', 'p': seat, 'u': units, 'to': to};
}

/// Hide a card with [Hidden] facedown at a battlefield you control (CR 422, 811.1.b). The cost
/// and battlefield are asked if there's a choice. A facedown card is played with [PlayMove].
class HideMove extends RMove {
  const HideMove(super.seat, this.card);
  final int card;
  @override
  Map<String, dynamic> toJson() => {'t': 'hide', 'p': seat, 'c': card};
}

/// Pass Priority (with a chain open) or Focus (in a showdown).
class PassMove extends RMove {
  const PassMove(super.seat);
  @override
  Map<String, dynamic> toJson() => {'t': 'pass', 'p': seat};
}

class EndTurnMove extends RMove {
  const EndTurnMove(super.seat);
  @override
  Map<String, dynamic> toJson() => {'t': 'end', 'p': seat};
}

class ConcedeMove extends RMove {
  const ConcedeMove(super.seat);
  @override
  Map<String, dynamic> toJson() => {'t': 'concede', 'p': seat};
}

class RiftboundError extends TcgError {
  RiftboundError(super.message);
}
