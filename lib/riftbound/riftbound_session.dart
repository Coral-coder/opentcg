import 'dart:async';

import 'package:riftbound/riftbound.dart';
import 'package:tcg_core/tcg_core.dart' show TcgError, TcgMove;
import 'package:tcg_app/tcg_app.dart';

import 'riftbound_room.dart';

/// A Riftbound match on this device: the shared [MatchSession] plus the log entries each change
/// added (for the table's event line and sounds).
class RiftboundSession extends MatchSession<Game> {
  RiftboundSession.local({required super.ruleset, required super.mode, required super.playerNames, required super.seed, required super.decks, super.options}) : room = null, super.local();

  /// Linked to another device: the LockstepMatch owns the match.
  RiftboundSession.linked({required super.link})
      : room = null,
        super.linked(playerNames: [for (final p in (link.game! as Game).state.players) p.name]) {
    _lastLog = state.log.length;
  }

  /// At an online table of 2–4 seats: the [RiftboundRoom] owns the match, and moves go through it
  /// (to the host, and back to everyone in order).
  RiftboundSession.room({required RiftboundRoom this.room})
      : super.local(
          ruleset: room.ruleset,
          mode: SessionMode.linked,
          playerNames: [for (final p in room.game!.state.players) p.name],
          seed: room.game!.state.seed,
          decks: const [],
          options: {'mode': room.mode.id},
        ) {
    match = room!.game!;
    localSeat = room!.localSeat;
    _lastLog = state.log.length;
    _roomSub = room!.events.listen((e) {
      final r = room!;
      if (e == 'action' || e == 'start') {
        if (!identical(match, r.game) && r.game != null) {
          match = r.game!;
          localSeat = r.localSeat;
          resets++;
          afterMoves(remote: true, reset: true);
        } else {
          afterMoves(remote: true);
        }
        lastError = null;
        notifyListeners();
      } else if (e == 'reject' || e == 'error' || e == 'desync') {
        lastError = r.error ?? r.notice;
        notifyListeners();
      } else if (e == 'sent' || e == 'lobby') {
        notifyListeners();
      }
    });
  }

  final RiftboundRoom? room;
  StreamSubscription<String>? _roomSub;

  @override
  bool get isLinked => super.isLinked || room != null;

  /// Online with a room: the move goes to the room (the host applies it and broadcasts it).
  @override
  bool perform(TcgMove move) {
    final r = room;
    if (r == null) return super.perform(move);
    try {
      r.perform(move);
      lastError = null;
      notifyListeners();
      return true;
    } on TcgError catch (e) {
      lastError = e.message;
      Console.shared.play(Fx.deny);
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    super.dispose();
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

  /// The mode (and any other rules options) is saved with the game, so it resumes as it was.
  @override
  Map<String, dynamic> saveExtras() => {if (options != null) 'rules': options};

  @override
  int pauseAfter(TcgMove? move) => switch (move) {
    PlayMove() || MoveUnitsMove() || ActivateMove() => botDelay + 300,
    _ => botDelay ~/ 2 + 100,
  };
}
