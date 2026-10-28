import 'package:riftbound/riftbound.dart';

/// What the local player can do right now, from the engine's legal moves (never re-deriving
/// rules in the UI): which cards can be played, which units can move and where, which abilities
/// can be used, and whether passing or ending the turn is possible.
class RiftboundPlayable {
  RiftboundPlayable._(this.all);

  /// Nothing to do (not this player's move, a decision is open, or the game is over).
  static final none = RiftboundPlayable._(const []);

  factory RiftboundPlayable.of(Game g, int seat) {
    if (g.over || g.pending != null || g.toAct != seat) return none;
    return RiftboundPlayable._(g.legalMoves(seat));
  }

  final List<RMove> all;

  late final Map<int, List<RMove>> _byObject = () {
    final m = <int, List<RMove>>{};
    for (final x in all) {
      final id = switch (x) {
        PlayMove(:final card) => card,
        ActivateMove(:final source) => source,
        MoveUnitsMove(:final units) => units.first,
        HideMove(:final card) => card,
        _ => null,
      };
      if (id != null) m.putIfAbsent(id, () => []).add(x);
    }
    return m;
  }();

  /// The moves that start from object [id] (play it, use it, move it).
  List<RMove> forObject(int id) => _byObject[id] ?? const [];

  bool canPlay(int id) => forObject(id).any((m) => m is PlayMove);
  bool canUse(int id) => forObject(id).any((m) => m is ActivateMove);
  bool canMove(int id) => forObject(id).any((m) => m is MoveUnitsMove);
  bool hasAny(int id) => forObject(id).isNotEmpty;

  bool get canPass => all.any((m) => m is PassMove);
  bool get canEndTurn => all.any((m) => m is EndTurnMove);

  int get playableCards => all.whereType<PlayMove>().length;
  int get movableUnits => {for (final m in all.whereType<MoveUnitsMove>()) m.units.first}.length;
  int get usableAbilities => all.whereType<ActivateMove>().length;
  int get hideableCards => all.whereType<HideMove>().length;

  /// Ready units of [seat] at [unit]'s location that can also make the same move (for "move
  /// together", CR 144.3).
  List<int> groupFor(Game g, int unit, int to) {
    final loc = g.state.obj(unit).loc;
    return [
      for (final m in all.whereType<MoveUnitsMove>())
        if (m.to == to && g.state.obj(m.units.first).loc == loc) m.units.first,
    ];
  }
}

/// One line on what the player can do, for the status bar.
String playableSummary(Game g, int seat, RiftboundPlayable p) {
  final pl = g.state.player(seat);
  final ready = pl.runes.where((r) => !g.state.obj(r).exhausted).length;
  final parts = <String>['$ready of ${pl.runes.length} runes ready'];
  if (p.playableCards > 0) parts.add('${p.playableCards} card${p.playableCards == 1 ? '' : 's'} to play');
  if (p.movableUnits > 0) parts.add('${p.movableUnits} unit${p.movableUnits == 1 ? '' : 's'} can move');
  if (p.usableAbilities > 0) parts.add('${p.usableAbilities} abilit${p.usableAbilities == 1 ? 'y' : 'ies'}');
  if (p.hideableCards > 0) parts.add('${p.hideableCards} to hide');
  return parts.join(' · ');
}
