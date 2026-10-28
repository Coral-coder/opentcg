part of 'game.dart';

/// Cleanups (CR 318–324), showdowns (CR 341–348), combat (CR 461–468) and scoring (CR 469–474).
extension GameCombat on Game {
  /// One cleanup (CR 323). Returns true if anything changed (another cleanup follows, CR 322).
  bool _cleanup() {
    var changed = false;
    // 1. Victory (CR 323.1).
    _checkWin();
    if (state.over) return false;
    // 3a. Units with lethal damage die (CR 142.4, 323.4).
    for (final o in state.objects.values.toList()) {
      if (o.zone != Zone.board || card(o.id).type != CardType.unit) continue;
      if (_genLethal(o.id)) {
        log('${nameOf(o.id)} dies.', player: o.controller, card: o.id, kind: 'die');
        _kill(o.id);
        changed = true;
      }
    }
    if (_eqCleanup()) changed = true;
    if (_genCleanup()) changed = true;
    _powerCleanup();
    // 4. Control is lost of battlefields without your units (open state, no showdown there; CR 323.5).
    if (state.chain.isEmpty) {
      for (var i = 0; i < state.bfs.length; i++) {
        final b = state.bfs[i];
        if (b.controller != null && state.showdown?.bf != i && unitsAt(i, player: b.controller).isEmpty) {
          log('${playerName(b.controller!)} loses control of ${nameOf(b.obj)}.', player: b.controller, kind: 'info');
          b.controller = null;
          changed = true;
        }
      }
    }
    // 5a. Facedown cards at battlefields their controller lost (CR 323.6.a).
    if (_hCleanup()) changed = true;
    // 8. Contested status ends where the contesting player has no units and nothing is going on
    // (CR 190.3.b.1, 323.10).
    for (var i = 0; i < state.bfs.length; i++) {
      final b = state.bfs[i];
      if (b.contestedBy != null && state.showdown?.bf != i && unitsAt(i, player: b.contestedBy).isEmpty) {
        b.contestedBy = null;
        changed = true;
      }
    }
    _xAfterCleanup();
    return changed;
  }

  void _checkWin() {
    if (state.over) return;
    // CR 194.2: at or above the Victory Score and more points than every opponent.
    for (var p = 0; p < state.players.length; p++) {
      final pts = state.player(p).points;
      if (pts >= _genVictoryScore() && pts > state.player(state.other(p)).points) {
        _win(p);
        return;
      }
    }
  }

  /// Opens a staged showdown or combat in a Neutral Open state (CR 323.11–323.12). The lowest
  /// battlefield first when there are several (the turn player chooses, CR 463.1).
  bool _openStaged() {
    for (var i = 0; i < state.bfs.length; i++) {
      final b = state.bfs[i];
      final c = b.contestedBy;
      if (c == null) continue;
      final mine = unitsAt(i, player: c);
      if (mine.isEmpty) continue;
      final theirs = unitsAt(i, player: state.other(c));
      final combat = theirs.isNotEmpty;
      state.showdown = Showdown(bf: i, combat: combat, attacker: c, focus: c);
      if (combat) {
        log('Combat at ${nameOf(b.obj)}: ${playerName(c)} attacks.', player: c, kind: 'attack');
        // Start of combat: attack and defend triggers (CR 466.2.b–d), attacker's first.
        for (final u in mine) {
          _fireUnit(u, const {On.attack, On.attackOrDefend});
        }
        for (final u in theirs) {
          _fireUnit(u, const {On.defend, On.attackOrDefend});
        }
        // "When an enemy unit attacks a battlefield you control" — once per attacking unit.
        final def = state.other(c);
        if (b.controller == def) {
          for (final u in mine) {
            _fire(On.enemyAttacksYourBf, player: def, bf: i, event: u);
          }
        }
        _genCombatStart(i, c, mine, theirs);
      } else {
        log('Showdown at ${nameOf(b.obj)}.', player: c, kind: 'showdown');
        _genEvent(GEv.showdownHere, player: c, loc: i);
      }
      return true;
    }
    return false;
  }

  void _fireUnit(ObjId u, Set<On> ons) {
    final abs = parsed(u).abilities;
    for (var i = 0; i < abs.length; i++) {
      final a = abs[i];
      if (a is Triggered && (ons.contains(a.on.on) || ons.any((on) => _genAlsoOn(a.on, on)))) _queue(u, i, state.obj(u).controller);
    }
    _eqFireUnit(u, ons);
  }

  /// All players passed Focus: the showdown closes (CR 348).
  void _closeShowdown() {
    final sd = state.showdown!;
    final bf = sd.bf;
    final b = state.bfs[bf];
    final att = sd.attacker;
    final def = state.other(att);
    if (sd.combat) {
      final attackers = unitsAt(bf, player: att);
      final defenders = unitsAt(bf, player: def);
      if (attackers.isNotEmpty && defenders.isNotEmpty) _combatDamage(attackers, defenders);
      // Combat cleanup (CR 468.1): kill, heal all units, recall attackers if defenders remain.
      for (final o in state.objects.values.toList()) {
        if (o.zone == Zone.board && card(o.id).type == CardType.unit && _genLethal(o.id)) {
          log('${nameOf(o.id)} dies.', player: o.controller, card: o.id, kind: 'die');
          _kill(o.id);
        }
      }
      for (final o in state.objects.values) {
        if (o.zone == Zone.board) o.damage = 0;
      }
      _combatEnded([...attackers, ...defenders]);
      final defLeft = unitsAt(bf, player: def);
      var attLeft = unitsAt(bf, player: att);
      if (defLeft.isNotEmpty && attLeft.isNotEmpty) {
        for (final u in attLeft) {
          state.obj(u).loc = base;
        }
        log('${playerName(att)}’s attackers are recalled.', player: att, kind: 'move');
        attLeft = const [];
      }
      // Combat result (CR 468.3).
      final winner = attLeft.isNotEmpty && defLeft.isEmpty ? att : (defLeft.isNotEmpty && attLeft.isEmpty ? def : null);
      state.showdown = null;
      b.contestedBy = null;
      if (winner != null) {
        log('${playerName(winner)} wins the combat.', player: winner, kind: 'info');
        for (final u in unitsAt(bf, player: winner)) {
          _fireUnit(u, const {On.winCombat});
          _unitWon(u);
        }
        _fire(On.youWinCombat, player: winner);
        _establish(winner, bf);
      } else if (defLeft.isEmpty && attLeft.isEmpty) {
        b.controller = null;
      }
      return;
    }
    // A non-combat showdown (CR 348.2): the only player with units there establishes control.
    state.showdown = null;
    b.contestedBy = null;
    final present = [for (var p = 0; p < state.players.length; p++) if (unitsAt(bf, player: p).isNotEmpty) p];
    state.eq.openConquest = b.controller == null ? bf : -1;
    if (present.length == 1) _establish(present.first, bf);
    state.eq.openConquest = -1;
  }

  /// Gaining control of a battlefield is a Conquer if it wasn't scored this turn (CR 468.5).
  void _establish(int p, int bf) {
    final b = state.bfs[bf];
    if (b.controller == p) return;
    b.controller = p;
    log('${playerName(p)} takes control of ${nameOf(b.obj)}.', player: p, kind: 'conquer');
    _scoreBf(p, bf, conquer: true);
  }

  /// Scoring (CR 471–473): once per battlefield per turn; the Final Point needs every
  /// battlefield scored this turn when it comes from a Conquer (CR 473.1.b).
  void _scoreBf(int p, int bf, {required bool conquer}) {
    final pl = state.player(p);
    if (pl.scored.contains(bf)) return;
    pl.scored.add(bf);
    final b = state.bfs[bf];
    if (conquer) _gen.add('p$p:conquered$bf');
    if (_genCantScore(p, bf)) {
      log('${pl.name} ${conquer ? 'conquers' : 'holds'} ${nameOf(b.obj)} but can’t score.', player: p, kind: conquer ? 'conquer' : 'hold');
    } else if (conquer && pl.points >= _genVictoryScore() - 1 && pl.scored.length < state.bfs.length) {
      log('${pl.name} conquers ${nameOf(b.obj)} but needs every battlefield this turn for the final point, and draws instead.', player: p, kind: 'conquer');
      _draw(p, 1);
    } else {
      pl.points++;
      if (!conquer) _xHeld(p);
      _hScored(p);
      log('${pl.name} ${conquer ? 'conquers' : 'holds'} ${nameOf(b.obj)}: ${pl.points} point${pl.points == 1 ? '' : 's'}.', player: p, kind: conquer ? 'conquer' : 'hold', amount: 1);
    }
    // Score triggers (CR 473.2): the battlefield, units there, and "when you conquer / hold".
    final queuedFrom = state.waiting.length;
    final abs = parsed(b.obj).abilities;
    for (var i = 0; i < abs.length; i++) {
      final a = abs[i];
      if (a is Triggered && a.on.on == (conquer ? On.conquerHere : On.holdHere)) _queue(b.obj, i, p, loc: bf);
    }
    _eqScored(p, bf, conquer);
    for (final u in unitsAt(bf, player: p)) {
      _fireUnit(u, {conquer ? On.conquer : On.hold});
    }
    _fire(conquer ? On.youConquer : On.youHold, player: p, bf: bf);
    _genScored(p, bf, conquer, queuedFrom);
    if (conquer) _conquerAgain(p, bf, queuedFrom);
  }

  /// Combat damage (CR 467): each side's total Might assigned among the other's units, Tank first
  /// and Backline last (CR 815, 826), lethal damage in full before the next unit (CR 467.2.c.3),
  /// then dealt at once. Each player chooses which unit takes lethal damage next when that choice
  /// matters (CR 467.2.c); the attacker assigns first.
  void _combatDamage(List<ObjId> attackers, List<ObjId> defenders) {
    int total(List<ObjId> us) {
      var t = 0;
      for (final u in us) {
        if (state.obj(u).stunned) continue;
        if (parsed(u).abilities.any((a) => a is Static && a.passive is NoCombatDamage)) continue;
        if (_hNoCombatDamage(u)) continue;
        if (!_genDealsCombatDamage(u)) continue;
        t += mightUsed(u);
      }
      return t;
    }

    final bf = state.obj(attackers.first).loc;
    final att = state.obj(attackers.first).controller;
    final toDefenders = _assign(total(attackers), defenders, ignoreTank: _genIgnoresTank(att, bf), chooser: att);
    final toAttackers = _assign(total(defenders), attackers, ignoreTank: _genIgnoresTank(state.other(att), bf), chooser: state.other(att));
    _genNoteExcess(att, total(attackers), defenders);
    _genNoteExcess(state.other(att), total(defenders), attackers);
    for (final e in [...toDefenders.entries, ...toAttackers.entries]) {
      if (e.value <= 0) continue;
      final d = _genCombatHit(e.key, e.value);
      if (d > 0) log('${nameOf(e.key)} takes $d combat damage.', player: state.obj(e.key).controller, card: e.key, kind: 'damage', amount: d);
    }
  }

  /// [amount] of damage among [targets]: Tank first and Backline last (CR 815, 826), each unit
  /// lethal damage in full before the next (CR 467.2.c.3), the excess on the last (467.2.c.4).
  /// Among units of the same rank [chooser] picks which is next whenever the damage can't kill
  /// them all; the weakest is offered first (and is what a player with no opinion picks).
  Map<ObjId, int> _assign(int amount, List<ObjId> targets, {bool ignoreTank = false, required int chooser}) {
    final out = <ObjId, int>{};
    if (amount <= 0 || targets.isEmpty) return out;
    int rank(ObjId u) => hasKw(u, Kw.tank) && !ignoreTank ? 0 : (hasKw(u, Kw.backline) ? 2 : 1);
    int need(ObjId u) {
      final m = might(u);
      final d = state.obj(u).damage;
      final n = (m > 0 ? m : 1) - d;
      return n < 1 ? 1 : n;
    }

    final remaining = List.of(targets)..sortStable((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : (need(a) != need(b) ? need(a) - need(b) : a - b));
    var left = amount;
    ObjId? last;
    while (left > 0 && remaining.isNotEmpty) {
      final r = rank(remaining.first);
      final group = [for (final u in remaining) if (rank(u) == r) u];
      var next = group.first;
      final needAll = group.fold<int>(0, (t, u) => t + need(u));
      if (group.length > 1 && left < needAll) {
        next = ask(Decision(kind: DecisionKind.cards, player: chooser, prompt: 'Combat damage ($left left): which unit gets lethal damage next?', options: group)).first;
      }
      final n = need(next);
      final give = left < n ? left : n;
      out[next] = give;
      left -= give;
      remaining.remove(next);
      last = next;
    }
    // Excess goes on the last unit assigned (CR 467.2.c.4).
    if (left > 0 && last != null) out[last] = (out[last] ?? 0) + left;
    return out;
  }
}
