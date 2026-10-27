part of 'game.dart';

/// Playing cards (CR 349–359), activating abilities (CR 376), the Standard Move (CR 144),
/// paying costs with runes (CR 160–168), triggered abilities and the chain (CR 327–340).
extension GamePlay on Game {
  // -------------------------------------------------------------------------------------------
  // Timing
  // -------------------------------------------------------------------------------------------

  /// May [p] play something with [timing] now (CR 308–313, 806, 813)?
  String? _timingProblem(int p, Timing timing) {
    if (state.chain.isNotEmpty) {
      if (state.priority != p) return 'You don’t have Priority';
      if (timing != Timing.reaction) return 'Only Reactions can be played while the chain is open';
      return null;
    }
    final sd = state.showdown;
    if (sd != null) {
      if (sd.focus != p) return 'You don’t have Focus';
      if (timing == Timing.normal) return 'Only Actions and Reactions can be played in a showdown';
      return null;
    }
    if (state.active != p || state.step != Step.main) return 'Only in your Main Phase';
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Paying costs (CR 201–206, 357; runes CR 164)
  // -------------------------------------------------------------------------------------------

  /// Can [p] pay [energy] Energy and the Power in [power] (null = any domain) from their pool
  /// and runes? Runes exhaust for Energy and recycle for Power of their domain; a rune can do both.
  bool canPay(int p, int energy, List<Domain?> power, {bool forSpell = false}) => _payPlanWithAdds(p, energy, power, forSpell: forSpell) != null;

  /// Abilities [p] could use to add resources while paying (CR 204.4.b.1, 357.1.a): Reaction
  /// abilities that only add, cost nothing but exhausting (or killing) their source, and whose
  /// conditions hold. In a stable order.
  List<(ObjId, int, AddRes)> _addSources(int p, {required bool forSpell}) {
    final out = <(ObjId, int, AddRes)>[];
    final pl = state.player(p);
    for (final src in [?pl.legend, for (final o in _boardOf(p)) o.id]) {
      final o = state.obj(src);
      final abs = parsed(src).abilities;
      for (var i = 0; i < abs.length; i++) {
        final a = abs[i];
        if (a is! Activated || !a.adds || a.timing != Timing.reaction) continue;
        if (a.cost.energy > 0 || a.cost.power.isNotEmpty) continue;
        if (a.cost.exhaust && o.exhausted) continue;
        if (a.oncePerTurn && o.usedThisTurn.contains(i)) continue;
        if (a.legion && pl.playedThisTurn < 1) continue;
        final add = a.effects.first as AddRes;
        if (add.spellsOnly && !forSpell) continue;
        out.add((src, i, add));
      }
    }
    return out;
  }

  /// A payment plan that may also use resource abilities, fewest first.
  ({List<ObjId> exhaust, List<ObjId> recycle, int poolEnergy, List<int> poolPower, int poolAny, List<(ObjId, int, AddRes)> adds})? _payPlanWithAdds(int p, int energy, List<Domain?> power, {bool forSpell = false}) {
    final sources = _addSources(p, forSpell: forSpell);
    for (var k = 0; k <= sources.length; k++) {
      final used = sources.take(k).toList();
      var e = 0, a = 0;
      for (final (_, _, add) in used) {
        e += add.energy;
        a += add.anyPower;
      }
      final plan = _payPlan(p, energy, power, extraEnergy: e, extraAny: a);
      if (plan != null) return (exhaust: plan.exhaust, recycle: plan.recycle, poolEnergy: plan.poolEnergy, poolPower: plan.poolPower, poolAny: plan.poolAny, adds: used);
    }
    return null;
  }

  /// Which runes to exhaust and recycle, or null if it can't be paid. Deterministic: rune order.
  ({List<ObjId> exhaust, List<ObjId> recycle, int poolEnergy, List<int> poolPower, int poolAny})? _payPlan(int p, int energy, List<Domain?> power, {int extraEnergy = 0, int extraAny = 0}) {
    final pl = state.player(p);
    var poolE = pl.energyPool + extraEnergy;
    final poolP = List.of(pl.powerPool);
    var poolA = pl.anyPool + extraAny;
    final usedE = poolE < energy ? poolE : energy;
    var needE = energy - usedE;
    poolE -= usedE;
    // Power from the pool first (specific domains before "any").
    final needs = <Domain?>[];
    final sorted = [...power.whereType<Domain>(), ...power.where((d) => d == null)];
    for (final d in sorted) {
      if (d != null && poolP[d.index] > 0) {
        poolP[d.index]--;
      } else if (poolA > 0) {
        poolA--;
      } else if (d == null) {
        final i = poolP.indexWhere((x) => x > 0);
        if (i >= 0) {
          poolP[i]--;
        } else {
          needs.add(d);
        }
      } else {
        needs.add(d);
      }
    }
    final runes = [for (final r in pl.runes) state.obj(r)];
    // Power: recycle runes of the needed domain (CR 164.2.b).
    final recycle = <ObjId>[];
    for (final d in needs) {
      Domain? want = d;
      if (want == null) {
        // Any domain: the domain we have most runes of (ties: domain order).
        final counts = List.filled(6, 0);
        for (final r in runes) {
          if (recycle.contains(r.id)) continue;
          final rd = runeDomain(db[r.card]!);
          if (rd != null) counts[rd.index]++;
        }
        var best = -1;
        for (var i = 0; i < 6; i++) {
          if (counts[i] > 0 && (best < 0 || counts[i] > counts[best])) best = i;
        }
        if (best < 0) return null;
        want = Domain.values[best];
      }
      final r = runes.where((r) => !recycle.contains(r.id) && runeDomain(db[r.card]!) == want).toList();
      if (r.isEmpty) return null;
      // Prefer runes already exhausted (or about to be, for Energy).
      r.sortStable((a, b) => (a.exhausted ? 0 : 1) - (b.exhausted ? 0 : 1));
      recycle.add(r.first.id);
    }
    // Energy: exhaust ready runes, runes being recycled first (CR 164.2.a).
    final exhaust = <ObjId>[];
    final ready = runes.where((r) => !r.exhausted).toList()..sortStable((a, b) => (recycle.contains(a.id) ? 0 : 1) - (recycle.contains(b.id) ? 0 : 1));
    for (final r in ready) {
      if (needE == 0) break;
      exhaust.add(r.id);
      needE--;
    }
    if (needE > 0) return null;
    return (exhaust: exhaust, recycle: recycle, poolEnergy: poolE, poolPower: poolP, poolAny: poolA);
  }

  void _pay(int p, int energy, List<Domain?> power, {bool forSpell = false}) {
    final plan = _payPlanWithAdds(p, energy, power, forSpell: forSpell);
    if (plan == null) throw RiftboundError('Not enough runes to pay');
    final pl = state.player(p);
    for (final (src, i, _) in plan.adds) {
      final a = parsed(src).abilities[i] as Activated;
      state.obj(src).usedThisTurn.add(i);
      log('${playerName(p)} uses ${nameOf(src)} to pay.', player: p, card: src, kind: 'ability');
      if (a.cost.exhaust) state.obj(src).exhausted = true;
      if (a.cost.killMe) _kill(src);
    }
    pl.energyPool = plan.poolEnergy;
    pl.powerPool = plan.poolPower;
    pl.anyPool = plan.poolAny;
    for (final r in plan.exhaust) {
      state.obj(r).exhausted = true;
    }
    if (plan.recycle.isNotEmpty) {
      for (final r in plan.recycle) {
        pl.runes.remove(r);
        final o = state.obj(r)
          ..zone = Zone.runeDeck
          ..exhausted = false;
        pl.runeDeck.add(o.id);
      }
    }
  }

  /// A card's Energy cost after its own discounts (CR 356.4), never below 0 (CR 356.6).
  int energyCost(int p, RCard c) {
    var e = c.energy;
    for (final a in RiftboundParser.parse(c).abilities) {
      if (a is Static && a.passive is CostLess) {
        final cl = a.passive as CostLess;
        if (!cl.legion || state.player(p).playedThisTurn >= 1) e -= cl.n;
      }
    }
    return e < 0 ? 0 : e;
  }

  // -------------------------------------------------------------------------------------------
  // Playing a card (CR 353–359)
  // -------------------------------------------------------------------------------------------

  /// Plays [id] (CR 353–359): from hand or the Champion Zone, or — with [via] — as part of an
  /// effect, from elsewhere, or with its cost replaced or ignored (game/costs.dart).
  void _playFromHand(int p, ObjId id, {XPlay? via}) {
    final pl = state.player(p);
    final o = state.objOrNull(id);
    if (o == null) throw RiftboundError('That card isn’t in your hand');
    final x = via ?? _xPlayFromMove(p, id);
    final c = card(id);
    final parsedCard = parsed(id);
    if (!parsedCard.supported) throw RiftboundError('${c.name} isn’t supported yet');
    if (!c.isMainDeck) throw RiftboundError('That can’t be played');
    final timing = c.type == CardType.spell ? parsedCard.timing : Timing.normal;
    final t = x.effect ? null : _timingProblem(p, timing);
    if (t != null) throw RiftboundError(t);
    if (!_xCanPay(p, id, x)) throw RiftboundError('Not enough runes (${_costLabel(c)})');
    // Make relevant choices (CR 355): optional and alternative costs first (CR 355.1.a).
    _xChooseCosts(p, id, x);
    var loc = base;
    if (c.type == CardType.unit && x.roostBf >= 0) {
      loc = x.roostBf;
    } else if (c.type == CardType.unit && !x.toBase) {
      final options = [base, for (var i = 0; i < state.bfs.length; i++) if (state.bfs[i].controller == p) i];
      if (options.length > 1) {
        final a = ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Play ${c.name} where?', labels: [for (final l in options) locName(l, p)], source: id));
        loc = options[a.first];
      }
    }
    final extraP = <Domain?>[];
    var accelerate = false;
    if (c.type == CardType.unit && (parsedCard.has(Kw.accelerate) || _xGrantsAccelerate(p, x))) {
      // Accelerate (CR 805): pay {1}{C} more to enter ready.
      final pw = c.domains.isEmpty ? null : c.domains.first;
      x.optional.add((1, [pw]));
      if (_xPayable(p, id, x) != null && askYesNo(p, 'Pay {1}${pw == null ? '{A}' : '{${pw.letter}}'} for Accelerate so ${c.name} enters ready?', source: id)) {
        accelerate = true;
      } else {
        x.optional.removeLast();
      }
    }
    var repeats = 0;
    for (final a in parsedCard.abilities.whereType<RepeatCost>()) {
      x.optional.add((_xRepeatEnergy(p, a.cost), a.cost.power));
      if (_xPayable(p, id, x) != null && askYesNo(p, 'Pay ${a.cost.describe()} to Repeat ${c.name}?', source: id)) {
        repeats++;
      } else {
        x.optional.removeLast();
      }
    }
    if (_xGrantedRepeat(p, id, x)) repeats++;
    final effects = [for (final a in parsedCard.abilities) if (a is SpellBody) ...a.effects];
    final targets = c.type == CardType.spell ? _chooseTargets(effects, p, id, base, repeats: repeats) : const <int>[];
    x.targets = targets;
    // Deflect (CR 809): spells that choose an opponent's Deflect object cost more Power.
    for (final tg in targets) {
      if (tg >= 0 && state.objOrNull(tg)?.zone == Zone.board && state.obj(tg).controller != p && !_xIgnoreDeflect(id, tg)) {
        for (var i = 0; i < _kw(tg, Kw.deflect); i++) {
          extraP.add(null);
        }
      }
    }
    // Pay (CR 357) and finalize (CR 359).
    final spent = _xPay(p, id, x, mandatory: extraP);
    _xLeaveOrigin(id);
    pl.playedThisTurn++;
    if (x.elsewhere) x.flags |= PlayFlags.elsewhere;
    if (x.recycleAfter) x.flags |= PlayFlags.recycleAfter;
    if (c.type == CardType.spell) {
      o.zone = Zone.chain;
      log('${pl.name} plays ${c.name}.', player: p, card: id, kind: 'play');
      _pushChain(ChainItem(id: state.nextChainId++, source: id, card: c.key, ability: -1, controller: p, targets: targets, repeats: repeats, paid: x.flags, costRef: x.costRef));
      if (state.showdown?.focus == p) state.showdown!.focusChain = true;
      _xAfterPlay(p, id, x, spent);
      return;
    }
    // A unit or gear resolves at once (CR 337.2).
    final passives = [for (final a in parsedCard.abilities) if (a is Static) a.passive];
    final ready = c.type == CardType.gear ? !passives.any((x) => x is EntersExhausted) : (accelerate || x.entersReady || passives.any((x) => x is EntersReady));
    _enterBoard(id, p, loc, ready: ready);
    state.obj(id).paidExtra = x.flags;
    log('${pl.name} plays ${c.name}${loc == base ? '' : ' to ${locName(loc, p)}'}.', player: p, card: id, kind: 'play');
    _firePlayed(id);
    if (c.type == CardType.unit) _fire(On.youPlayUnit, player: p);
    _xAfterPlay(p, id, x, spent);
  }

  String _costLabel(RCard c) => '{${c.energy}}${'{${c.domains.isEmpty ? 'A' : c.domains.first.letter}}' * c.power}';

  /// Puts a permanent on the board (CR 359.2). Units enter exhausted unless told otherwise (CR
  /// 143.4); gear enters ready in base (CR 149.1).
  void _enterBoard(ObjId id, int controller, int loc, {required bool ready}) {
    final o = state.obj(id);
    o.reset();
    o
      ..zone = Zone.board
      ..controller = controller
      ..loc = card(id).type == CardType.gear ? base : loc
      ..exhausted = !ready
      ..enteredTurn = state.turn;
    if (o.loc != base) _contest(o.loc, controller);
  }

  /// "When you play me" and Vision (CR 817) triggers of a permanent that just entered.
  void _firePlayed(ObjId id) {
    final p = state.obj(id).controller;
    final abs = parsed(id).abilities;
    for (var i = 0; i < abs.length; i++) {
      final a = abs[i];
      if (a is Triggered && a.on.on == On.played) {
        if (a.legion && state.player(p).playedThisTurn < 2) continue;
        _queue(id, i, p);
      }
      if (a is KeywordAb && a.kw == Kw.vision) _queue(id, i, p);
    }
  }

  // -------------------------------------------------------------------------------------------
  // Activated abilities (CR 376)
  // -------------------------------------------------------------------------------------------

  void _activate(int p, ObjId src, int index) {
    final o = state.objOrNull(src);
    if (o == null || o.controller != p || !(o.zone == Zone.board || (o.zone == Zone.legend))) throw RiftboundError('You don’t control that');
    final abs = parsed(src).abilities;
    if (index < 0 || index >= abs.length || abs[index] is! Activated) throw RiftboundError('No such ability');
    if (!parsed(src).supported) throw RiftboundError('${nameOf(src)} isn’t supported yet');
    final a = abs[index] as Activated;
    if (a.legion && state.player(p).playedThisTurn < 1) throw RiftboundError('Legion: play another card this turn first');
    final isAdd = a.adds;
    final t = isAdd ? null : _timingProblem(p, a.timing);
    if (t != null) throw RiftboundError(t);
    if (isAdd && a.timing != Timing.reaction && _timingProblem(p, Timing.normal) != null) throw RiftboundError('Not now');
    if (a.oncePerTurn && o.usedThisTurn.contains(index)) throw RiftboundError('Only once per turn');
    if (a.cost.exhaust && o.exhausted) throw RiftboundError('${nameOf(src)} is exhausted');
    final xp = _xCostProblem(p, src, a.cost);
    if (xp != null) throw RiftboundError(xp);
    final energy = _xAbilityEnergy(p, src, a);
    if (!canPay(p, energy, a.cost.power)) throw RiftboundError('Not enough runes (${a.cost.describe()})');
    final targets = _chooseTargets(a.effects, p, src, o.loc);
    final extraP = <Domain?>[];
    for (final tg in targets) {
      if (tg >= 0 && state.objOrNull(tg)?.zone == Zone.board && state.obj(tg).controller != p && !_xIgnoreDeflect(src, tg)) {
        for (var i = 0; i < _kw(tg, Kw.deflect); i++) {
          extraP.add(null);
        }
      }
    }
    _pay(p, energy, [...a.cost.power, ...extraP]);
    _xPayCostExtra(p, src, a);
    if (a.cost.exhaust) o.exhausted = true;
    o.usedThisTurn.add(index);
    final item = ChainItem(id: state.nextChainId++, source: src, card: o.card, ability: index, controller: p, targets: targets, loc: o.loc);
    if (a.cost.killMe) _kill(src);
    log('${playerName(p)} uses ${nameOf(src)}.', player: p, card: src, kind: 'ability');
    if (isAdd) {
      // Abilities that add resources resolve at once and can't be reacted to (CR 337.2).
      _resolveItem(item);
      return;
    }
    _pushChain(item);
    if (state.showdown?.focus == p) state.showdown!.focusChain = true;
  }

  // -------------------------------------------------------------------------------------------
  // The Standard Move (CR 144, 447–455)
  // -------------------------------------------------------------------------------------------

  void _standardMove(int p, List<ObjId> moving, int to) {
    if (!_neutralMain(p)) throw RiftboundError('Units move in your Main Phase, outside showdowns');
    if (moving.isEmpty || moving.toSet().length != moving.length) throw RiftboundError('Choose units to move');
    if (to != base && (to < 0 || to >= state.bfs.length)) throw RiftboundError('No such battlefield');
    for (final u in moving) {
      final o = state.objOrNull(u);
      if (o == null || !isUnit(u) || o.controller != p) throw RiftboundError('You can only move your units');
      if (o.exhausted) throw RiftboundError('${nameOf(u)} is exhausted');
      if (!moveDestinations(u).contains(to)) throw RiftboundError('${nameOf(u)} can’t move there');
    }
    for (final u in moving) {
      state.obj(u).exhausted = true;
    }
    _moveUnits(moving, to, p);
  }

  /// Moves units (a move, not a recall: CR 448) and applies Contested (CR 452).
  void _moveUnits(List<ObjId> moving, int to, int byPlayer) {
    for (final u in moving) {
      state.obj(u).loc = to;
    }
    log('${playerName(byPlayer)} moves ${moving.map(nameOf).join(', ')} to ${locName(to, byPlayer)}.', player: byPlayer, card: moving.first, kind: 'move');
    if (to != base) _contest(to, state.obj(moving.first).controller);
    for (final u in moving) {
      final abs = parsed(u).abilities;
      for (var i = 0; i < abs.length; i++) {
        final a = abs[i];
        if (a is Triggered && a.on.on == On.move && (!a.on.moveToBattlefield || to != base)) _queue(u, i, state.obj(u).controller);
      }
    }
  }

  /// Contested status (CR 190.3.a).
  void _contest(int bf, int p) {
    final b = state.bfs[bf];
    if (b.contestedBy == null && b.controller != p) b.contestedBy = p;
  }

  // -------------------------------------------------------------------------------------------
  // Triggered abilities and the chain
  // -------------------------------------------------------------------------------------------

  /// Queues ability [index] of [src] to go on the chain at the next chance (CR 382).
  void _queue(ObjId src, int index, int controller, {int loc = -2, int event = -1}) {
    final o = state.obj(src);
    state.waiting.add(ChainItem(id: 0, source: src, card: o.card, ability: index, controller: controller, loc: loc == -2 ? o.loc : loc, fromTrigger: true, event: event));
  }

  /// Triggers abilities of everything [player] controls (and their legend) for an event. [bf]:
  /// the battlefield it's about ("that battlefield"); [event]: the unit it's about ("it").
  void _fire(On on, {required int player, int bf = -2, int event = -1}) {
    final srcs = [?state.player(player).legend, for (final o in _boardOf(player)) o.id, ..._xTrashTriggerCards(player)];
    for (final s in srcs) {
      final abs = parsed(s).abilities;
      for (var i = 0; i < abs.length; i++) {
        final a = abs[i];
        if (a is Triggered && a.on.on == on && _xZoneOk(s, a.on)) _queue(s, i, player, loc: bf, event: event);
      }
    }
  }

  /// Puts a waiting trigger on the chain: its controller makes its choices now (CR 355.5.b).
  void _finalizeTrigger(ChainItem t) {
    final src = state.objOrNull(t.source);
    if (src == null) return;
    if (!_xTriggerOk(t)) return;
    final a = parsed(t.source).abilities[t.ability];
    final effects = switch (a) {
      Triggered() => a.effects,
      KeywordAb(kw: Kw.vision) => const <Effect>[Predict(1)],
      _ => const <Effect>[],
    };
    if (effects.isEmpty) return;
    final targets = _chooseTargets(effects, t.controller, t.source, t.loc, optional: true);
    if (_mandatoryTargetsMissing(effects, targets)) {
      log('${nameOf(t.source)}’s ability has no target.', card: t.source);
      return;
    }
    // Deflect (CR 809) applies to triggered abilities too: pay it, or the ability can't go on.
    final deflect = <Domain?>[];
    for (final tg in targets) {
      if (tg >= 0 && state.objOrNull(tg)?.zone == Zone.board && state.obj(tg).controller != t.controller && !_xIgnoreDeflect(t.source, tg)) {
        for (var i = 0; i < _kw(tg, Kw.deflect); i++) {
          deflect.add(null);
        }
      }
    }
    if (deflect.isNotEmpty) {
      if (!canPay(t.controller, 0, deflect)) {
        log('${nameOf(t.source)}’s ability can’t pay for Deflect.', card: t.source);
        return;
      }
      _pay(t.controller, 0, deflect);
    }
    _pushChain(ChainItem(id: state.nextChainId++, source: t.source, card: t.card, ability: t.ability, controller: t.controller, targets: targets, loc: t.loc, fromTrigger: true, event: t.event));
  }

  void _pushChain(ChainItem item) {
    state.chain.add(item);
    state.priority = item.controller;
    state.passes = 0;
  }

  /// Resolves the newest chain item (CR 340).
  void _resolveTop() {
    final item = state.chain.removeLast();
    _resolveItem(item);
  }

  void _resolveItem(ChainItem item) {
    final c = db[item.card]!;
    final List<Effect> effects;
    if (item.isSpell) {
      effects = [for (final a in RiftboundParser.parse(c).abilities) if (a is SpellBody) ...a.effects];
    } else {
      final a = RiftboundParser.parse(c).abilities[item.ability];
      effects = switch (a) {
        Triggered() => a.effects,
        Activated() => a.effects,
        KeywordAb(kw: Kw.vision) => const <Effect>[Predict(1)],
        _ => const <Effect>[],
      };
    }
    if (item.isSpell) _xBeforeSpell(item);
    // Each execution of a Repeat has its own choices (CR 820.2).
    final per = item.repeats > 0 ? _xSlotCount(effects) : 0;
    for (var r = 0; r <= item.repeats; r++) {
      final ctx = _Ctx(controller: item.controller, source: item.source, loc: item.loc, targets: per == 0 ? item.targets : _xSlice(item.targets, r, per), event: item.event, paid: item.paid, costRef: item.costRef);
      _resolveEffects(effects, ctx, rep: r);
    }
    if (item.isSpell) {
      final o = state.obj(item.source);
      if (!_xSpellDone(item) && o.zone == Zone.chain) {
        o.zone = Zone.trash;
        state.player(o.owner).trash.add(o.id);
        _xAfterSpellTrashed(item);
      }
      // Playing a spell is complete when it resolves (CR 420.4.a).
      _fire(On.youPlaySpell, player: item.controller);
    }
  }

  // -------------------------------------------------------------------------------------------
  // Zones
  // -------------------------------------------------------------------------------------------

  /// Draw [n] (CR 414); drawing from an empty deck burns out first (CR 432).
  void _draw(int p, int n) {
    final pl = state.player(p);
    for (var i = 0; i < n; i++) {
      if (pl.deck.isEmpty) {
        _burnOut(p);
        if (state.over || pl.deck.isEmpty) return;
      }
      final id = pl.deck.removeAt(0);
      state.obj(id).zone = Zone.hand;
      pl.hand.add(id);
    }
    if (n > 0) log('${pl.name} draws $n.', player: p, kind: 'draw', amount: n);
  }

  /// Burn Out (CR 432.2): shuffle the trash in as the deck, and the opponent gains 1 point.
  void _burnOut(int p) {
    final pl = state.player(p);
    final trash = List.of(pl.trash);
    pl.trash.clear();
    state.rng.shuffle(trash);
    for (final id in trash) {
      state.obj(id).zone = Zone.mainDeck;
      pl.deck.add(id);
    }
    final o = state.other(p);
    state.player(o).points++;
    log('${pl.name} burns out: ${playerName(o)} gains 1 point.', player: o, kind: 'point', amount: 1);
    _checkWin();
  }

  /// Recycle cards to the bottom of the Main Deck in random order (CR 417.5).
  void _recycleCards(int p, List<ObjId> ids) {
    final pl = state.player(p);
    final list = List.of(ids);
    state.rng.shuffle(list);
    for (final id in list) {
      final o = state.obj(id);
      pl.hand.remove(id);
      pl.trash.remove(id);
      o
        ..zone = Zone.mainDeck
        ..reset();
      pl.deck.add(id);
    }
  }

  /// Channel [n] runes (CR 431), ready unless [exhausted].
  void _channel(int p, int n, {bool exhausted = false}) {
    final pl = state.player(p);
    var done = 0;
    for (var i = 0; i < n && pl.runeDeck.isNotEmpty; i++) {
      final id = pl.runeDeck.removeAt(0);
      final o = state.obj(id)
        ..zone = Zone.runes
        ..exhausted = exhausted
        ..controller = p;
      pl.runes.add(o.id);
      done++;
    }
    if (done > 0) log('${pl.name} channels $done rune${done == 1 ? '' : 's'}.', player: p, kind: 'channel', amount: done);
  }

  /// Kill a permanent (CR 429): to its owner's trash (tokens cease to exist, CR 186.1).
  /// Deathknell triggers (CR 808) note the unit as it was.
  void _kill(ObjId id) {
    final o = state.obj(id);
    if (o.zone != Zone.board) return;
    _xOnKill(o);
    final abs = parsed(id).abilities;
    for (var i = 0; i < abs.length; i++) {
      final a = abs[i];
      if (a is Triggered && a.on.on == On.die) _queue(id, i, o.controller);
    }
    _leaveBoard(id, toHand: false);
  }

  void _leaveBoard(ObjId id, {required bool toHand}) {
    final o = state.obj(id);
    final c = card(id);
    o.reset();
    final pl = state.player(o.owner);
    if (c.token) {
      o.zone = Zone.gone;
      return;
    }
    if (toHand) {
      o.zone = Zone.hand;
      pl.hand.add(id);
    } else {
      o.zone = Zone.trash;
      pl.trash.add(id);
    }
  }

  /// "Base", "your base" or a battlefield's name, as [viewer] would say it.
  String locName(int loc, int viewer) => loc == base ? 'base' : nameOf(state.bfs[loc].obj);
}
