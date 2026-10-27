part of 'state.dart';

/// Bookkeeping for the general effects (game/general.dart): what happened this turn, lasting
/// marks on objects, and delayed abilities (CR 390). Keys are strings so new uses need no new
/// fields; the digest sorts them.
class GenState {
  /// Counters reset as each turn begins: "p0:discarded", "o12:moves", "t:12:3" (a trigger's uses).
  Map<String, int> turn = {};

  /// Values that last until removed: "o12:buffs" (extra buff counters), "o12:temporary".
  Map<String, int> lasting = {};

  /// Delayed abilities, oldest first.
  List<Delayed> delayed = [];

  int get(String k) => turn[k] ?? 0;
  void add(String k, [int n = 1]) => turn[k] = (turn[k] ?? 0) + n;
  int getL(String k) => lasting[k] ?? 0;
  void setL(String k, int v) {
    if (v == 0) {
      lasting.remove(k);
    } else {
      lasting[k] = v;
    }
  }

  /// Forgets everything about object [id] (it left the board: a new object, CR 124.1).
  void forget(int id) {
    final p = 'o$id:';
    lasting.removeWhere((k, _) => k.startsWith(p));
    turn.removeWhere((k, _) => k.startsWith(p));
  }

  GenState clone() => GenState()
    ..turn = Map.of(turn)
    ..lasting = Map.of(lasting)
    ..delayed = List.of(delayed);

  String digest() {
    String m(Map<String, int> x) {
      final ks = x.keys.toList()..sortStable((a, b) => a.compareTo(b));
      return ks.map((k) => '$k=${x[k]}').join(',');
    }

    return '${m(turn)}/${m(lasting)}/${delayed.map((d) => d.digest()).join(';')}';
  }
}

/// A delayed ability (CR 390): what it is ([kind] is a [DelayKind] index), who controls it, the
/// card and ability it came from (to find its effects: [path] indexes nested effect lists), and
/// the objects it's about.
class Delayed {
  const Delayed({
    required this.kind,
    required this.controller,
    required this.source,
    required this.card,
    required this.ability,
    this.path = const [],
    this.targets = const [],
    this.obj = -1,
    this.n = 0,
    this.turn = 0,
    this.loc = -1,
  });
  final int kind;
  final int controller;
  final int source;
  final String card;
  final int ability;
  final List<int> path;
  final List<int> targets;
  final int obj;
  final int n;

  /// The turn it was made (most end with that turn).
  final int turn;
  final int loc;

  Delayed withN(int v) => Delayed(kind: kind, controller: controller, source: source, card: card, ability: ability, path: path, targets: targets, obj: obj, n: v, turn: turn, loc: loc);

  String digest() => '$kind|$controller|$source|${card.length}:$card|$ability|${path.join('.')}|${targets.join(',')}|$obj|$n|$turn|$loc';
}
