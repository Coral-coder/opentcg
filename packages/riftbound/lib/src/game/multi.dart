part of 'game.dart';

/// Modes of Play with more than two players (CR 489–491): Skirmish, War and Magma Chamber (2v2).
/// A Duel never reaches the branches here that differ, so it plays exactly as before.
extension GameMulti on Game {
  /// [p] gains (or loses) [n] points; in 2v2 the team shares them (CR 491.8.d). Never below 0
  /// (CR 194.4).
  void _addPoints(int p, int n) {
    for (var q = 0; q < state.players.length; q++) {
      if (!state.allied(p, q)) continue;
      final pl = state.player(q);
      pl.points = pl.points + n < 0 ? 0 : pl.points + n;
    }
  }

  /// Enemy units (any opponent's) at [bf], or anywhere with [bf] null. In a Duel, the other
  /// player's units, in the same order.
  List<ObjId> enemyUnits(int p, {int? bf}) => [
        for (final u in (bf == null ? units() : unitsAt(bf)))
          if (!state.allied(state.obj(u).controller, p)) u,
      ];

  /// Whether any opponent of [p] matches [test].
  bool anyOpponent(int p, bool Function(int) test) => state.opponents(p).any(test);

  /// "An opponent": with one opponent, that one; with several, [chooser] picks (CR 485.2.b).
  int chooseOpponent(int p, String prompt, {int? chooser}) {
    final opps = state.opponents(p);
    if (opps.isEmpty) return state.other(p);
    if (opps.length == 1) return opps.first;
    final labels = [for (final o in opps) playerName(o)];
    final i = ask(Decision(kind: DecisionKind.option, player: chooser ?? p, prompt: prompt, labels: labels)).first;
    return opps[i];
  }

  /// The players with units at [bf] other than [p]'s side, in turn order after [p].
  List<int> _othersAt(int bf, int p) => [
        for (var i = 1; i < state.players.length; i++)
          if (!state.allied(p, (p + i) % state.players.length) && unitsAt(bf, player: (p + i) % state.players.length).isNotEmpty) (p + i) % state.players.length,
      ];

  /// The defender of a combat or showdown [att] begins at [bf]: the other player with units there
  /// (combat is between exactly two players, CR 464), else the battlefield's controller, else the
  /// next opponent.
  int _defenderAt(int bf, int att) {
    if (!state.multi) return state.other(att);
    final others = _othersAt(bf, att);
    if (others.isNotEmpty) return others.first;
    final c = state.bfs[bf].controller;
    if (c != null && !state.allied(c, att)) return c;
    return state.other(att);
  }

  /// Whether units [p] controls may move to (or be played at) [bf] (CR 449.2.a–b, 464.1–464.3):
  /// not where two other players are in (or have staged) combat, nor where a teammate's units are.
  bool _multiCanEnter(int p, int bf) {
    if (!state.multi || bf == base) return true;
    for (final q in state.teammates(p)) {
      if (unitsAt(bf, player: q).isNotEmpty) return false;
    }
    final others = _othersAt(bf, p);
    if (unitsAt(bf, player: p).isNotEmpty) return others.length <= 1;
    // Entering where someone else already is would start a combat with them; where two others
    // are fighting (or both present) it would make a three-way combat (CR 464.3).
    final sd = state.showdown;
    if (sd != null && sd.bf == bf && sd.combat && !state.allied(sd.attacker, p) && _defenderAt(bf, sd.attacker) != p) return false;
    return others.length <= 1;
  }

  /// In 2v2, battlefields a teammate controlled at the start of the turn's scoring step can't be
  /// scored by the team that turn (CR 315.2.b.3, 471.1.a, 491.8.b.1). Marked when the step begins.
  void _teamsScoringStep(int p) {
    if (state.mode != RMode.teams) return;
    for (var i = 0; i < state.bfs.length; i++) {
      final c = state.bfs[i].controller;
      if (c != null && c != p && state.allied(c, p)) state.marks['tdq:$i'] = 1;
    }
  }

  /// Whether [p]'s side already scored [bf] this turn (CR 472; once per team per turn, 491.8.b).
  bool _sideScored(int p, int bf) {
    if (state.mode != RMode.teams) return state.player(p).scored.contains(bf);
    if (state.marks.containsKey('tdq:$bf')) return true;
    for (var q = 0; q < state.players.length; q++) {
      if (state.allied(p, q) && state.player(q).scored.contains(bf)) return true;
    }
    return false;
  }

  /// How many battlefields count for the Final Point (CR 473.1.b): in 2v2 those a teammate
  /// occupied at the scoring step don't (CR 491.8.g.1).
  bool _scoredEvery(int p) {
    if (state.mode != RMode.teams) return state.player(p).scored.length >= state.bfs.length;
    for (var i = 0; i < state.bfs.length; i++) {
      if (state.marks.containsKey('tdq:$i')) continue;
      if (!_sideScored(p, i)) return false;
    }
    return true;
  }

  /// The end of a turn clears the 2v2 scoring marks.
  void _multiNewTurn() {
    if (state.mode != RMode.teams) return;
    state.marks.removeWhere((k, _) => k.startsWith('tdq:'));
  }

  /// Victory (CR 194.2, 323.1, 474): at or above the Victory Score and more points than every
  /// opponent. Teammates win together (CR 491.6.a).
  int? _multiWinner() {
    final vs = _genVictoryScore();
    for (var p = 0; p < state.players.length; p++) {
      if (!state.inGame(p)) continue;
      final pts = state.player(p).points;
      if (pts < vs) continue;
      if (state.opponents(p).every((o) => state.player(o).points < pts)) return p;
    }
    return null;
  }
}
