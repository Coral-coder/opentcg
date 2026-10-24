/// Everything a player can do (CR 4 turn actions, plus answers to decisions): the unit of replay
/// and of lockstep sync. A match is its seed plus its ordered moves.
library;

import 'package:tcg_core/tcg_core.dart';

sealed class LMove extends TcgMove {
  const LMove(this.seat);
  @override
  final int seat;

  static LMove fromJson(Map<String, dynamic> j) {
    final p = j['p'] as int? ?? -1;
    return switch (j['t'] as String) {
      'start' => StartMove([for (final d in j['decks'] as List) (d as List).cast<String>()], firstPlayer: j['first'] as int?),
      'answer' => AnswerMove(p, (j['a'] as List).cast<int>()),
      'ink' => InkMove(p, j['c'] as int),
      'play' => PlayMove(p, j['c'] as int, mode: PlayMode.values.byName(j['m'] as String? ?? 'ink'), onto: j['o'] as int?, singers: ((j['s'] as List?) ?? const []).cast<int>()),
      'quest' => QuestMove(p, j['c'] as int),
      'challenge' => ChallengeMove(p, j['c'] as int, j['d'] as int),
      'move' => MoveMove(p, j['c'] as int, j['l'] as int),
      'activate' => ActivateMove(p, j['c'] as int, j['i'] as int),
      'end' => EndTurnMove(p),
      'concede' => ConcedeMove(p),
      final t => throw ArgumentError('Unknown move $t'),
    };
  }

  @override
  String toString() => toJson().toString();
}

/// Deals the match: one deck per seat. [firstPlayer] fixes the starting player; otherwise it's
/// chosen at random from the seed (CR 2.2.1.1).
class StartMove extends LMove {
  const StartMove(this.decks, {this.firstPlayer}) : super(-1);
  final List<List<String>> decks;
  final int? firstPlayer;
  @override
  Map<String, dynamic> toJson() => {'t': 'start', 'decks': decks, if (firstPlayer != null) 'first': firstPlayer};
}

class AnswerMove extends LMove {
  const AnswerMove(super.seat, this.answer);
  final List<int> answer;
  @override
  Map<String, dynamic> toJson() => {'t': 'answer', 'p': seat, 'a': answer};
}

/// Ink a card (CR 4.2).
class InkMove extends LMove {
  const InkMove(super.seat, this.card);
  final int card;
  @override
  Map<String, dynamic> toJson() => {'t': 'ink', 'p': seat, 'c': card};
}

/// How a card is paid for (CR 4.3.2.2): ink, Shift onto [PlayMove.onto], or singing with
/// [PlayMove.singers] (one singer, or several for Sing Together).
enum PlayMode { ink, shift, sing }

/// Play a card (CR 4.3).
class PlayMove extends LMove {
  const PlayMove(super.seat, this.card, {this.mode = PlayMode.ink, this.onto, this.singers = const []});
  final int card;
  final PlayMode mode;
  final int? onto;
  final List<int> singers;
  @override
  Map<String, dynamic> toJson() => {'t': 'play', 'p': seat, 'c': card, if (mode != PlayMode.ink) 'm': mode.name, if (onto != null) 'o': onto, if (singers.isNotEmpty) 's': singers};
}

/// Quest (CR 4.5).
class QuestMove extends LMove {
  const QuestMove(super.seat, this.card);
  final int card;
  @override
  Map<String, dynamic> toJson() => {'t': 'quest', 'p': seat, 'c': card};
}

/// Challenge (CR 4.6): [card] challenges [target], an exerted opposing character or a location.
class ChallengeMove extends LMove {
  const ChallengeMove(super.seat, this.card, this.target);
  final int card, target;
  @override
  Map<String, dynamic> toJson() => {'t': 'challenge', 'p': seat, 'c': card, 'd': target};
}

/// Move a character to a location (CR 4.7).
class MoveMove extends LMove {
  const MoveMove(super.seat, this.card, this.location);
  final int card, location;
  @override
  Map<String, dynamic> toJson() => {'t': 'move', 'p': seat, 'c': card, 'l': location};
}

/// Use an activated ability (CR 4.4), or Boost (CR 8.4): [index] into the card's abilities.
class ActivateMove extends LMove {
  const ActivateMove(super.seat, this.card, this.index);
  final int card, index;
  @override
  Map<String, dynamic> toJson() => {'t': 'activate', 'p': seat, 'c': card, 'i': index};
}

/// Declare the end of the turn (CR 3.3.2).
class EndTurnMove extends LMove {
  const EndTurnMove(super.seat);
  @override
  Map<String, dynamic> toJson() => {'t': 'end', 'p': seat};
}

/// Concede (CR 2.3.3.4): allowed any time.
class ConcedeMove extends LMove {
  const ConcedeMove(super.seat);
  @override
  Map<String, dynamic> toJson() => {'t': 'concede', 'p': seat};
}
