import 'package:lorcana/lorcana.dart';

/// What a card can do now, as the table shows it with a badge.
enum CardAction { play, shift, sing, ink, quest, challenge, move, ability }

/// What the player can do this moment, worked out once from the engine's legal moves (the table
/// never re-implements a rule): for each card, the moves it can make and the kinds of action
/// they are. A move is filed under the card that makes it; a card played from a discard or from
/// under another card is filed under the card that allows it, where the table shows it.
class Playable {
  Playable._(this.seat, this.moves, this.byCard, this.inkReady, this.inkTotal, this.canInk);

  /// Nothing to do: not this player's turn, or a choice is pending.
  Playable.none(this.seat)
      : moves = const [],
        byCard = const {},
        inkReady = 0,
        inkTotal = 0,
        canInk = false;

  final int seat;

  /// Every legal move except ending the turn.
  final List<LMove> moves;
  final Map<CardId, List<LMove>> byCard;
  final int inkReady, inkTotal;

  /// The once-per-turn inkwell action is still available, with a card that can go in.
  final bool canInk;

  bool get isEmpty => moves.isEmpty;

  /// The moves [id] can make.
  List<LMove> movesOf(CardId id) => byCard[id] ?? const [];

  /// The kinds of action [id] can take.
  Set<CardAction> actionsOf(CardId id) => {for (final m in movesOf(id)) actionOf(m)};

  /// Whether [id] can do anything at all.
  bool canAct(CardId id) => byCard.containsKey(id);

  /// Moves other than putting a card into the inkwell (playing, questing, challenging…).
  int get usefulCount => moves.where((m) => m is! InkMove).length;

  /// The cards a [kind] action from [id] can be aimed at: who to challenge, where to move, who
  /// sings, what to shift onto.
  Map<CardId, LMove> targetsOf(CardId id, CardAction kind) {
    final out = <CardId, LMove>{};
    for (final m in movesOf(id)) {
      final t = targetOf(m);
      if (t != null && actionOf(m) == kind) out[t] = m;
    }
    return out;
  }

  static CardAction actionOf(LMove m) => switch (m) {
        InkMove() => CardAction.ink,
        PlayMove(mode: PlayMode.shift) => CardAction.shift,
        PlayMove(mode: PlayMode.sing) => CardAction.sing,
        PlayMove() => CardAction.play,
        QuestMove() => CardAction.quest,
        ChallengeMove() => CardAction.challenge,
        MoveMove() => CardAction.move,
        _ => CardAction.ability,
      };

  /// The other card a move needs: the challenged card, the location, the (first) singer, the
  /// card shifted onto.
  static CardId? targetOf(LMove m) => switch (m) {
        ChallengeMove(:final target) => target,
        MoveMove(:final location) => location,
        PlayMove(mode: PlayMode.sing, :final singers) when singers.length == 1 => singers.first,
        PlayMove(mode: PlayMode.shift, :final onto, :final onto2) when onto2 == null => onto,
        _ => null,
      };
}

/// The [Playable] for [seat] in [g] now.
Playable playableActions(Game g, int seat) {
  if (g.over || g.pending != null || g.state.active != seat) return Playable.none(seat);
  final moves = [
    for (final m in g.legalMoves())
      if (m is! EndTurnMove) m,
  ];
  final by = <CardId, List<LMove>>{};
  for (final m in moves) {
    final owner = switch (m) {
      PlayMove(:final card) when g.state.obj(card).zone != Place.hand => g.playEnabler(card) ?? card,
      InkMove(:final card) || PlayMove(:final card) || QuestMove(:final card) || ActivateMove(:final card) || ChallengeMove(:final card) || MoveMove(:final card) => card,
      _ => null,
    };
    if (owner != null) (by[owner] ??= []).add(m);
  }
  final p = g.state.player(seat);
  return Playable._(seat, moves, by, g.inkReady(seat), p.inkwell.length, moves.any((m) => m is InkMove));
}

/// A one-line summary for the status bar: "Your turn — 3 of 5 ink ready · you can still ink a
/// card · 2 cards to play · 1 can quest".
String playableSummary(Playable p) {
  final parts = <String>['${p.inkReady} of ${p.inkTotal} ink ready'];
  if (p.canInk) parts.add('you can still ink a card');
  int count(CardAction a) => p.byCard.keys.where((id) => p.actionsOf(id).contains(a)).length;
  final play = count(CardAction.play) + count(CardAction.shift) + count(CardAction.sing);
  final quest = count(CardAction.quest);
  final challenge = count(CardAction.challenge);
  if (play > 0) parts.add('$play ${play == 1 ? 'card' : 'cards'} to play');
  if (quest > 0) parts.add('$quest can quest');
  if (challenge > 0) parts.add('$challenge can challenge');
  if (p.usefulCount == 0) parts.add(p.canInk ? 'nothing else to do' : 'nothing left to do — end your turn');
  return parts.join(' · ');
}
