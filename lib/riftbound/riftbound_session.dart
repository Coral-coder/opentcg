import 'package:riftbound/riftbound.dart';
import 'package:tcg_core/tcg_core.dart' show TcgMove;
import 'package:tcg_app/tcg_app.dart';

/// A Riftbound match on this device: the shared [MatchSession] plus the log entries each change
/// added (for the table's event line and sounds).
class RiftboundSession extends MatchSession<Game> {
  RiftboundSession.local({required super.ruleset, required super.mode, required super.playerNames, required super.seed, required super.decks}) : super.local();

  /// Linked to another device: the LockstepMatch owns the match.
  RiftboundSession.linked({required super.link}) : super.linked(playerNames: [for (final p in (link.game! as Game).state.players) p.name]) {
    _lastLog = state.log.length;
  }

  /// What the last change added to the log (the computer's moves, coin flips, damage).
  List<LogEntry> recent = [];
  int _lastLog = 0;

  GameState get state => match.state;

  @override
  void afterMoves({required bool remote, bool reset = false}) {
    if (reset) {
      if (isLinked) {
        playerNames
          ..clear()
          ..addAll([for (final p in state.players) p.name]);
      }
      _lastLog = state.log.length;
      recent = [];
      return;
    }
    final fresh = state.log.length >= _lastLog ? state.log.sublist(_lastLog) : state.log.toList();
    _lastLog = state.log.length;
    if (fresh.isNotEmpty) recent = fresh;
    final kinds = {for (final e in fresh) e.kind};
    // One sound per kind of thing that happened, most telling first.
    for (final (kind, fx) in const [
      ('win', Fx.victory),
      ('lose', Fx.defeat),
      ('die', Fx.dies),
      ('attack', Fx.attack),
      ('damage', Fx.attack),
      ('conquer', Fx.victory),
      ('play', Fx.summon),
      ('channel', Fx.land),
      ('draw', Fx.draw),
      ('turn', Fx.turn),
    ]) {
      if (kinds.contains(kind)) {
        if (kind == 'win' || kind == 'lose') {
          final e = fresh.lastWhere((x) => x.kind == kind);
          Console.shared.play((kind == 'win') == (e.player == localSeat) ? Fx.victory : Fx.defeat);
        } else {
          Console.shared.play(fx);
        }
        break;
      }
    }
  }

  @override
  int pauseAfter(TcgMove? move) => switch (move) {
    PlayMove() || MoveUnitsMove() || ActivateMove() => botDelay + 300,
    _ => botDelay ~/ 2 + 100,
  };
}
