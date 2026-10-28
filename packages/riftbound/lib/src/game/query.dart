part of 'game.dart';

/// Reading the board: Might, keywords, filters, and which moves are legal.
extension GameQuery on Game {
  /// Units and gear [p] controls on the board, oldest first.
  Iterable<Obj> _boardOf(int p) => state.objects.values.where((o) => o.zone == Zone.board && o.controller == p);

  /// Units on the board, oldest first; [at] a location (with [player]'s base for [base]).
  List<ObjId> unitsAt(int at, {int? player}) => [
        for (final o in state.objects.values)
          if (o.zone == Zone.board && card(o.id).type == CardType.unit && o.loc == at && (player == null || o.controller == player)) o.id,
      ];

  List<ObjId> units({int? player}) => [
        for (final o in state.objects.values)
          if (o.zone == Zone.board && card(o.id).type == CardType.unit && (player == null || o.controller == player)) o.id,
      ];

  List<ObjId> gearOf(int player) => [
        for (final o in state.objects.values)
          if (o.zone == Zone.board && card(o.id).type == CardType.gear && o.controller == player) o.id,
      ];

  bool isUnit(ObjId id) => state.obj(id).zone == Zone.board && card(id).type == CardType.unit;

  /// Attacker and defender designations (CR 466.2.c) during a combat.
  bool isAttacking(ObjId id) {
    final sd = state.showdown;
    final o = state.obj(id);
    return sd != null && sd.combat && o.zone == Zone.board && o.loc == sd.bf && o.controller == sd.attacker;
  }

  bool isDefending(ObjId id) {
    final sd = state.showdown;
    final o = state.obj(id);
    return sd != null && sd.combat && o.zone == Zone.board && o.loc == sd.bf && o.controller != sd.attacker;
  }

  /// A keyword's value on an object: printed plus given this turn (CR 801.3); Assault, Shield and
  /// Deflect sum (CR 807.2, 809.2, 814.2).
  int _kw(ObjId id, Kw k) => _memoPassives(() => _kwOf(id, k));

  int _kwOf(ObjId id, Kw k) {
    var n = (_eqInactive(id) ? 0 : parsed(id).kw(k)) + (state.obj(id).kwMod[k.index] ?? 0) + _eqKw(id, k);
    if (state.obj(id).zone == Zone.board) {
      for (final (src, passive) in _passives()) {
        if (passive is KwAnthem && passive.kw == k && matches(passive.filter, id, controller: state.obj(src).controller, source: src, here: state.obj(src).loc)) n += passive.n;
      }
      n += _genKw(id, k);
      n += _powerKw(id, k, n);
      n += _hKw(id, k);
    }
    return n;
  }

  /// Passive abilities in effect: those of permanents on the board and of legends (CR 363).
  Iterable<(ObjId, Passive)> _passives() => _passMemo ?? _scanPassives();

  /// Runs [f], a query that doesn't change the state, scanning the passives once for all of it
  /// rather than once per hook (Might and keyword values consult them several times each).
  T _memoPassives<T>(T Function() f) {
    if (_passMemo != null) return f();
    _passMemo = _scanPassives().toList();
    try {
      return f();
    } finally {
      _passMemo = null;
    }
  }

  Iterable<(ObjId, Passive)> _scanPassives() sync* {
    for (final o in state.objects.values) {
      if (o.zone != Zone.board && o.zone != Zone.legend && o.zone != Zone.battlefield) continue;
      if (_eqInactive(o.id)) continue;
      for (final a in parsed(o.id).abilities) {
        if (a is Static && _gateOk(o.id, a.gate)) yield (o.id, a.passive);
      }
    }
    yield* _eqPassives();
  }

  bool hasKw(ObjId id, Kw k) => _kw(id, k) > 0;

  /// Effective Might (CR 143.2.a): printed, buff (CR 703), this-turn changes, passives, Assault
  /// while attacking (CR 807) and Shield while defending (CR 814).
  int might(ObjId id) => _memoPassives(() => _mightOf(id));

  int _mightOf(ObjId id) {
    final o = state.obj(id);
    final c = card(id);
    var m = (c.might ?? 0) + (o.buffed ? 1 : 0) + o.mightMod;
    if (o.zone == Zone.board) {
      for (final (src, passive) in _passives()) {
        final so = state.obj(src);
        switch (passive) {
          case Anthem(:final n, :final filter):
            if (matches(filter, id, controller: so.controller, source: src, here: so.loc)) m += n;
          case DefendsAlone(:final n):
            // "While a friendly unit defends alone, it gets +N" (only defender at its battlefield).
            if (o.controller == so.controller && isDefending(id) && unitsAt(o.loc, player: o.controller).length == 1) m += n;
          default:
            break;
        }
      }
      m += _eqMight(id);
      m += _powerMight(id);
      m += _hMight(id);
      m += _xMight(id);
      if (isAttacking(id)) m += _kw(id, Kw.assault);
      if (isDefending(id)) m += _kw(id, Kw.shield);
      m += _genMight(id, m);
    }
    return m;
  }

  /// Might as spells and combat use it: below 0 counts as 0 (CR 143.2.c).
  int mightUsed(ObjId id) => might(id) < 0 ? 0 : might(id);

  /// Does object [id] match [f], for an ability of [source] controlled by [controller]? [here] is
  /// the source's location.
  bool matches(Filter f, ObjId id, {required int controller, ObjId? source, int here = base, List<int>? slots}) {
    final o = state.objOrNull(id);
    final pw = f.pw;
    if (o == null) return false;
    if (f.zone != FZone.board) return _genMatchesCard(f, id, controller: controller, source: source);
    if (o.zone != Zone.board && !(o.zone == Zone.legend && (pw?.legends ?? false))) return false;
    final c = card(id);
    if (pw != null && pw.anyType) {
      if (!(c.type == CardType.unit || c.type == CardType.gear || (pw.legends && c.type == CardType.legend))) return false;
    } else if (!f.cardTypes.contains(c.type)) {
      return false;
    }
    if (f.side == Side.friendly && o.controller != controller) return false;
    if (f.side == Side.enemy && o.controller == controller) return false;
    if (f.other && id == source) return false;
    switch (f.where) {
      case Where.anywhere:
        break;
      case Where.here:
        // "Here" for a unit in its base is that base (CR 197).
        if (o.loc != here) return false;
        if (here == base && o.controller != (source == null ? controller : state.obj(source).controller)) return false;
      case Where.battlefield:
        if (o.loc == base) return false;
      case Where.base:
        if (o.loc != base) return false;
      case Where.elsewhere:
        // Two bases are different locations (CR 197).
        if (o.loc == here && (here != base || o.controller == (source == null ? controller : state.obj(source).controller))) return false;
    }
    if (f.exhausted != null && o.exhausted != f.exhausted) return false;
    if (f.buffed != null && o.buffed != f.buffed) return false;
    if (f.attacking && !isAttacking(id)) return false;
    if (f.defending && !isDefending(id)) return false;
    if (f.tag != null && !c.hasTag(f.tag!) && !_eqHasTag(id, f.tag!)) return false;
    if (f.notTag != null && c.hasTag(f.notTag!)) return false;
    if (f.mightMax != null && mightUsed(id) > f.mightMax!) return false;
    if (f.mightMin != null && mightUsed(id) < f.mightMin!) return false;
    if (pw != null && !_powerMatches(pw, id, controller: controller, source: source, here: here)) return false;
    return _genMatches(f, id, o, c, controller: controller, source: source, here: here, slots: slots);
  }

  /// Objects matching [f], oldest first (cards in trashes or hands: by owner, in zone order).
  List<ObjId> matching(Filter f, {required int controller, ObjId? source, int here = base, List<int>? slots}) => f.zone != FZone.board
      ? _genMatching(f, controller: controller, source: source)
      : [
        for (final o in state.objects.values)
          if ((o.zone == Zone.board || (o.zone == Zone.legend && (f.pw?.legends ?? false))) && matches(f, o.id, controller: controller, source: source, here: here, slots: slots)) o.id,
      ];

  // -------------------------------------------------------------------------------------------
  // Legal moves
  // -------------------------------------------------------------------------------------------

  /// Every legal discretionary move for [seat] right now (pass and end turn included), in a
  /// stable order. Each was checked by trying it on a copy of the game.
  List<RMove> legalMoves(int seat) {
    if (state.over || pending != null || toAct != seat) return const [];
    final out = <RMove>[];
    for (final m in candidateMoves(seat)) {
      if (m is PassMove || m is EndTurnMove || whyNot(m) == null) out.add(m);
    }
    return out;
  }

  /// Moves worth trying (not yet checked).
  List<RMove> candidateMoves(int seat) {
    final out = <RMove>[];
    final pl = state.player(seat);
    for (final id in [...pl.hand, ?pl.champion, ..._xExtraPlayable(seat)]) {
      out.add(PlayMove(seat, id));
    }
    for (final src in [?pl.legend, for (final o in _boardOf(seat)) o.id]) {
      final abs = parsed(src).abilities;
      for (var i = 0; i < abs.length; i++) {
        if (abs[i] is Activated) out.add(ActivateMove(seat, src, i));
      }
    }
    out.addAll(_powerCandidates(seat));
    if (_neutralMain(seat)) {
      for (final u in units(player: seat)) {
        final o = state.obj(u);
        if (o.exhausted) continue;
        for (final to in moveDestinations(u)) {
          out.add(MoveUnitsMove(seat, [u], to));
        }
      }
    }
    out.addAll(_eqCandidates(seat));
    out.addAll(_hCandidates(seat));
    if (state.chain.isNotEmpty || state.showdown != null) out.add(PassMove(seat));
    if (_neutralMain(seat)) out.add(EndTurnMove(seat));
    return out;
  }

  /// Where unit [u] may go with its Standard Move (CR 144.4).
  List<int> moveDestinations(ObjId u) {
    final o = state.obj(u);
    if (o.loc == base) return _genMoveDests(u, [for (var i = 0; i < state.bfs.length; i++) i]);
    return _genMoveDests(u, [base, if (hasKw(u, Kw.ganking)) for (var i = 0; i < state.bfs.length; i++) if (i != o.loc) i]);
  }

  /// The reason [m] isn't legal now, or null if it is (tried on a copy of the game).
  String? whyNot(RMove m) {
    if (state.over) return 'The game is over';
    if (pending != null) return 'A decision is pending';
    if (m.seat != toAct) return 'Not your move';
    if (m is PlayMove) {
      // The first checks only read the state, so they run here without copying the game.
      try {
        _memoPassives(() => _playStart(m.seat, m.card));
      } on TcgError catch (e) {
        return e.message;
      }
    }
    if (m is ActivateMove) {
      final early = _memoPassives(() => _activateEarlyProblem(m.seat, m.source, m.index));
      if (early != null) return early;
    }
    final g = Game._probe(this);
    try {
      g._exec(m);
      return null;
    } on TcgError catch (e) {
      return e.message;
    } on NeedDecision {
      return null;
    }
  }

  /// Neutral Open state in [p]'s Main Phase (CR 310.1.a).
  bool _neutralMain(int p) => !state.over && state.phase == Phase.main && state.active == p && state.step == Step.main && state.chain.isEmpty && state.showdown == null;

  /// Can [p] add something to the open chain (a Reaction)?
  bool _canReact(int p) {
    if (_probe) return false;
    return _memoPassives(() {
      for (final m in candidateMoves(p)) {
        if (m is PlayMove || m is ActivateMove) {
          if (whyNot(m) == null) return true;
        }
      }
      return false;
    });
  }

  /// Runs [f], which must not change this game's state (it may try moves with [whyNot], which
  /// uses a copy), reading the passives in effect only once for all of it.
  T readOnly<T>(T Function() f) => _memoPassives(f);

  /// Can [p], with Focus, play or activate something (an Action or Reaction)?
  bool _canActInShowdown(int p) => _canReact(p);
}
