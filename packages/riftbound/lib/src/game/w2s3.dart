part of 'game.dart';

/// Wave 2, slice 3 (ir_w2s3.dart): choosing, resolving, conditions, events and the passives of
/// the cards from Rek'Sai, Swarm Queen to Zilean, Time Mage. The core calls in with one line per
/// hook; state lives in [GameState.marks] ("t:w3:…" for this turn, "w3:…" until removed).
extension GameW2s3 on Game {
  // -------------------------------------------------------------------------------------------
  // Choices as it's played (CR 355)
  // -------------------------------------------------------------------------------------------

  void _w3Choose(W3Effect e, int p, ObjId source, int loc, List<int> out, void Function(int, int) set, {required bool optional}) {
    for (final t in e.targets) {
      _genChooseOne(ChooseOnly([t]), t, p, source, loc, out, set, optional: optional);
    }
    switch (e) {
      case W3Stormbringer(:final bfSlot):
        // "At a battlefield": which one is chosen as it's played (CR 355.4).
        if (state.bfs.isEmpty) {
          if (optional) return set(bfSlot, -1);
          throw RiftboundError('No battlefield to choose');
        }
        final a = ask(Decision(kind: DecisionKind.option, player: p, prompt: '${nameOf(source)}: choose a battlefield', labels: [for (final b in state.bfs) nameOf(b.obj)], source: source));
        set(bfSlot, state.bfs[a.first].obj);
      case W3MoveMany(:final units, :final destSlot):
        final chosen = [for (var i = units.slot; i < units.slot + units.max && i < out.length; i++) if (out[i] > 0) out[i]];
        if (chosen.isEmpty) return set(destSlot, -1);
        // "A single location": a battlefield, or their base.
        final options = [0, for (final b in state.bfs) b.obj];
        final a = ask(Decision(kind: DecisionKind.option, player: p, prompt: '${nameOf(source)}: move them where?', labels: [for (final o in options) o == 0 ? 'Their base' : nameOf(o)], source: source));
        set(destSlot, options[a.first]);
      case W3SwapClone(:final slot):
        final options = _genTargetable([for (final u in units(player: p)) if (card(u).name == 'Shadow Clone') u], p, source);
        if (options.isEmpty) {
          if (optional) return set(slot, -1);
          throw RiftboundError('No Shadow Clone to trade places with');
        }
        set(slot, ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: choose a Shadow Clone you control', options: options, source: source)).first);
      case W3NamedTagMight(:final slot):
        final tag = _w3NamedTag(source);
        final options = tag == null ? const <int>[] : _genTargetable([for (final u in units()) if (_w3HasTag(u, tag)) u], p, source);
        if (options.isEmpty) {
          if (optional) return set(slot, -1);
          throw RiftboundError(tag == null ? 'No tag was named' : 'No unit with the tag $tag');
        }
        set(slot, ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: choose a $tag unit', options: options, source: source)).first);
      default:
        break;
    }
  }

  /// Does a mandatory choice of [e] have nothing (a trigger then doesn't go on the chain)?
  bool _w3Missing(W3Effect e, List<int> targets) {
    if (_genMissing(ChooseOnly(e.targets), targets)) return true;
    final slot = switch (e) {
      W3Stormbringer(:final bfSlot) => bfSlot,
      W3SwapClone(:final slot) || W3NamedTagMight(:final slot) => slot,
      _ => -1,
    };
    return slot >= 0 && (slot >= targets.length || targets[slot] < 0);
  }

  // -------------------------------------------------------------------------------------------
  // Resolving
  // -------------------------------------------------------------------------------------------

  void _w3Resolve(W3Effect e, _Ctx ctx) {
    final p = ctx.controller;
    switch (e) {
      case W3RevealPlay(:final n, :final may, :final hereIfUnit):
        _w3RevealPlay(p, ctx, n, may: may, hereIfUnit: hereIfUnit);
      case W3CounterGive(:final unit, :final spell):
        // The spell's Energy cost, read before it leaves the chain.
        var cost = 0;
        if (spell.slot < ctx.targets.length && ctx.targets[spell.slot] >= _chainRef) {
          final it = state.chain.where((x) => x.id == ctx.targets[spell.slot] - _chainRef).firstOrNull;
          if (it != null) cost = db[it.card]!.energy;
        }
        _genCounter(CounterIt(spell), ctx);
        for (final id in _resolveTarget(unit, ctx)) {
          if (!isUnit(id) || cost == 0) continue;
          state.obj(id).mightMod += cost;
          log('${nameOf(id)} gets +$cost Might this turn.', player: p, card: id, kind: 'buff');
        }
      case W3DealUnless(:final n, :final target, :final draw):
        for (final id in _resolveTarget(target, ctx)) {
          final ctl = state.obj(id).controller;
          if (ctl != p && askYesNo(ctl, '${nameOf(ctx.source)}: let ${playerName(p)} draw $draw so ${nameOf(id)} isn’t dealt $n?', source: ctx.source)) {
            log('${playerName(ctl)} has ${playerName(p)} draw $draw.', player: ctl, kind: 'info');
            _draw(p, draw);
            continue;
          }
          if (!isUnit(id) || _noDamage(id)) continue;
          _hDeal(id, n, ctx);
          _xDamaged(p, id);
        }
      case W3OppKillsOne():
        for (var i = 1; i < state.players.length; i++) {
          final q = (p + i) % state.players.length;
          final mine = units(player: q);
          if (mine.isEmpty) continue;
          final pick = ask(Decision(kind: DecisionKind.cards, player: q, prompt: '${nameOf(ctx.source)}: kill one of your units', options: mine, source: ctx.source));
          log('${nameOf(pick.first)} is killed.', player: q, card: pick.first, kind: 'die');
          _kill(pick.first);
        }
      case W3Stormbringer(:final unitSlot, :final bfSlot):
        final u = unitSlot < ctx.targets.length ? ctx.targets[unitSlot] : -1;
        final bfObj = bfSlot < ctx.targets.length ? ctx.targets[bfSlot] : -1;
        final bf = state.bfs.indexWhere((b) => b.obj == bfObj);
        if (u < 0 || bf < 0 || !isUnit(u) || state.obj(u).controller != p) return;
        final amount = mightUsed(u);
        for (final x in unitsAt(bf)) {
          if (state.obj(x).controller == p || _noDamage(x)) continue;
          _hDeal(x, amount, ctx);
          _xDamaged(p, x);
        }
        if (isUnit(u) && state.obj(u).loc != bf && !_genCantMoveTo(u, bf) && !_eqUnmovable(u, p)) _moveUnits([u], bf, p);
      case W3AddCombatants(:final energy):
        final sd = state.showdown;
        if (sd == null || !sd.combat) return;
        for (final q in [sd.attacker, _defenderAt(sd.bf, sd.attacker)]) {
          state.player(q).energyPool += energy;
          log('${playerName(q)} adds {$energy}.', player: q, kind: 'info');
        }
      case W3MoveMany(:final units, :final destSlot):
        final dest = destSlot < ctx.targets.length ? ctx.targets[destSlot] : -1;
        if (dest < 0) return;
        final to = dest == 0 ? base : state.bfs.indexWhere((b) => b.obj == dest);
        if (dest != 0 && to < 0) return;
        final moving = [
          for (final u in _resolveTarget(units, ctx))
            if (isUnit(u) && state.obj(u).loc != to && !_genCantMoveTo(u, to) && !_eqUnmovable(u, p)) u,
        ];
        if (moving.isNotEmpty) _moveUnits(moving, to, p);
      case W3RuneGamble():
        _w3RuneGamble(p, ctx);
      case W3SaveForPay(:final target, :final power):
        for (final id in _resolveTarget(target, ctx)) {
          state.marks['t:w3:save:$id'] = p + 1;
          state.marks['t:w3:saveP:$id'] = power.index + 1;
          log('${nameOf(id)} may be saved the next time it dies this turn.', player: p, card: id, kind: 'info');
        }
      case W3Whirlwind():
        // "Starting with the next player" (turn order), ending with the controller.
        for (var i = 1; i <= state.players.length; i++) {
          final q = (p + i) % state.players.length;
          final all = units();
          if (all.isEmpty) break;
          final pick = ask(Decision(kind: DecisionKind.cards, player: q, prompt: '${nameOf(ctx.source)}: you may return a unit to its owner’s hand', options: all, min: 0, max: 1, source: ctx.source));
          if (pick.isEmpty) continue;
          log('${nameOf(pick.first)} returns to its owner’s hand.', player: q, card: pick.first, kind: 'move');
          _leaveBoard(pick.first, toHand: true);
        }
      case W3SwapClone(:final slot):
        final me = ctx.source;
        final clone = slot < ctx.targets.length ? ctx.targets[slot] : -1;
        if (!isUnit(me) || clone < 0 || !isUnit(clone) || state.obj(clone).controller != p) return;
        final a = state.obj(me).loc, b = state.obj(clone).loc;
        if (a == b) return;
        if (!_genCantMoveTo(me, b) && !_eqUnmovable(me, p)) _moveUnits([me], b, p);
        if (!_genCantMoveTo(clone, a) && !_eqUnmovable(clone, p)) _moveUnits([clone], a, p);
      case W3NamedTagMight(:final slot, :final n):
        final id = slot < ctx.targets.length ? ctx.targets[slot] : -1;
        final tag = _w3NamedTag(ctx.source);
        if (id < 0 || tag == null || !isUnit(id) || !_w3HasTag(id, tag)) return;
        _resolve(GiveMight(n, const Chosen(0)), _Ctx(controller: p, source: ctx.source, loc: ctx.loc, targets: [id], ability: ctx.ability));
      case W3MoveOtherHome():
        final bf = ctx.loc;
        if (bf < 0) return;
        final options = [
          for (final u in unitsAt(bf, player: p))
            if (u != ctx.event && !_genCantMoveTo(u, base) && !_eqUnmovable(u, p)) u,
        ];
        if (options.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: you may move another of your units here to its base', options: options, min: 0, max: 1, source: ctx.source));
        if (pick.isNotEmpty) _moveUnits(pick, base, p);
      case W3Follow():
        final me = ctx.source;
        final to = ctx.loc;
        if (!isUnit(me) || state.obj(me).loc == to || _genCantMoveTo(me, to) || _eqUnmovable(me, p)) return;
        if (askYesNo(p, '${nameOf(me)}: move with it to ${locName(to, p)}?', source: me)) _moveUnits([me], to, p);
    }
  }

  void _w3RevealPlay(int p, _Ctx ctx, int n, {required bool may, required bool hereIfUnit}) {
    if (may && !askYesNo(p, '${nameOf(ctx.source)}: reveal the top $n cards of your Main Deck?', source: ctx.source)) return;
    _w3BeforeReveal(p);
    final deck = state.player(p).deck;
    final top = deck.take(n).toList();
    if (top.isEmpty) return;
    log('${playerName(p)} reveals ${top.map(nameOf).join(', ')}.', player: p, kind: 'info');
    for (final id in top) {
      _xRevealed(id);
    }
    final seen = _xSeeMe(p, top);
    // "If the played card is a unit, you may play it here": the source's battlefield.
    final src = state.objOrNull(ctx.source);
    final here = hereIfUnit && src != null && src.zone == Zone.board && src.loc != base ? src.loc : null;
    bool playable(ObjId id) => _xCanPlayNow(p, id, XPlay(effect: true, elsewhere: true)) || (here != null && card(id).type == CardType.unit && _xCanPlayNow(p, id, XPlay(effect: true, elsewhere: true, at: here)));
    final options = [for (final id in seen) if (deck.contains(id) && playable(id)) id];
    final pick = options.isEmpty ? const <int>[] : ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: you may play one (the rest are recycled)', options: options, min: 0, max: 1, source: ctx.source));
    if (pick.isNotEmpty) {
      final id = pick.first;
      var via = XPlay(effect: true, elsewhere: true);
      if (here != null && card(id).type == CardType.unit) {
        final there = XPlay(effect: true, elsewhere: true, at: here);
        if (_xCanPlayNow(p, id, there) && (!_xCanPlayNow(p, id, via) || askYesNo(p, 'Play ${nameOf(id)} here at ${locName(here, p)}?', source: ctx.source))) via = there;
      }
      _xPlayAsEffect(p, id, via);
    }
    final rest = [for (final id in seen) if (!pick.contains(id) && deck.contains(id)) id];
    for (final id in rest) {
      deck.remove(id);
    }
    _recycleCards(p, rest);
  }

  void _w3RuneGamble(int p, _Ctx ctx) {
    final pl = state.player(p);
    _w3BeforeReveal(p, runes: true);
    if (pl.runeDeck.isEmpty) return;
    final r = pl.runeDeck.removeAt(0);
    pl.runeDeck.add(r);
    final d = runeDomain(card(r));
    log('${playerName(p)} reveals ${nameOf(r)} from their rune deck and recycles it.', player: p, card: r, kind: 'info');
    final src = state.objOrNull(ctx.source);
    final here = src != null && src.zone == Zone.board ? src.loc : ctx.loc;
    switch (d) {
      case Domain.fury:
        // "Deal 2 to an enemy unit here and 1 to all other enemy units here."
        final enemies = enemyUnits(p, bf: here);
        final options = _genTargetable(enemies, p, ctx.source);
        if (options.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: choose an enemy unit here to deal 2 to', options: options, source: ctx.source)).first;
        for (final u in enemies) {
          if (!isUnit(u) || _noDamage(u)) continue;
          _hDeal(u, u == pick ? 2 : 1, ctx);
          _xDamaged(p, u);
        }
      case Domain.mind:
        _draw(p, 1);
      case Domain.order:
        final options = _genTargetable(enemyUnits(p), p, ctx.source);
        if (options.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: choose an enemy unit to stun', options: options, source: ctx.source)).first;
        _resolve(const Stun(Chosen(0)), _Ctx(controller: p, source: ctx.source, loc: ctx.loc, targets: [pick], ability: ctx.ability));
      default:
        log('Nothing happens for that domain.', player: p, kind: 'info');
    }
  }

  // -------------------------------------------------------------------------------------------
  // Conditions
  // -------------------------------------------------------------------------------------------

  bool _w3Cond(W3Cond c, _Ctx ctx) {
    final p = ctx.controller;
    switch (c) {
      case W3PlayedUnitGearSpell():
        return (state.marks['t:w3:pu:$p'] ?? 0) > 0 && (state.marks['t:w3:pg:$p'] ?? 0) > 0 && (state.marks['t:w3:ps:$p'] ?? 0) > 0;
      case W3MightyHere():
        final bf = ctx.loc;
        return bf >= 0 && bf < state.bfs.length && unitsAt(bf, player: p).any((u) => might(u) >= 5);
    }
    return false;
  }

  /// A card [p] played (finalized, CR 359): Swain's "if you've played a non-token unit, a
  /// non-token gear, and a spell this turn".
  void _w3NotePlayed(int p, ObjId id) {
    final c = card(id);
    if (c.token) return;
    final k = switch (c.type) {
      CardType.unit => 'pu',
      CardType.gear => 'pg',
      CardType.spell => 'ps',
      _ => null,
    };
    if (k != null) state.marks['t:w3:$k:$p'] = 1;
  }

  // -------------------------------------------------------------------------------------------
  // Events: this file's triggers (W3When)
  // -------------------------------------------------------------------------------------------

  /// Abilities of [src] that trigger on [kind], by index.
  List<int> _w3Triggers(ObjId src, W3On kind) {
    final abs = parsed(src).abilities;
    return [
      for (var i = 0; i < abs.length; i++)
        if (abs[i] is Triggered && (abs[i] as Triggered).on is W3When && ((abs[i] as Triggered).on as W3When).kind == kind) i,
    ];
  }

  /// A unit at a battlefield is about to be returned to its owner's hand (Ripper's Bay).
  void _w3ReturnedToHand(ObjId id) {
    final o = state.obj(id);
    if (o.zone != Zone.board || o.loc < 0 || o.loc >= state.bfs.length || card(id).type != CardType.unit) return;
    final bf = state.bfs[o.loc].obj;
    for (final i in _w3Triggers(bf, W3On.returnedHere)) {
      _queue(bf, i, o.owner, loc: o.loc, event: id);
    }
  }

  /// A unit died (Shard of Undoing: the first friendly death in your Beginning Phase each turn).
  void _w3Died(ObjId id) {
    final ctl = _genLkController(id);
    if (ctl < 0 || state.step != Step.beginning || ctl != state.active) return;
    for (final o in _boardOf(ctl).toList()) {
      for (final i in _w3Triggers(o.id, W3On.friendlyDiesInBeginning)) {
        final k = 't:w3:first:${o.id}:$i';
        if ((state.marks[k] ?? 0) > 0) continue;
        state.marks[k] = 1;
        _queue(o.id, i, ctl, event: id);
      }
    }
  }

  /// A non-token unit was played by [p] (Star Spring: the first time each turn at it).
  void _w3UnitPlayed(ObjId id, int p) {
    final o = state.obj(id);
    if (card(id).token || o.zone != Zone.board || o.loc < 0 || o.loc >= state.bfs.length) return;
    final bf = state.bfs[o.loc].obj;
    for (final i in _w3Triggers(bf, W3On.firstUnitPlayedHere)) {
      final k = 't:w3:first:$bf:$i';
      if ((state.marks[k] ?? 0) > 0) continue;
      state.marks[k] = 1;
      _queue(bf, i, p, loc: o.loc, event: id);
    }
  }

  /// Units moved from [from] to [to] (Stealthy Pursuer follows friendly units leaving its location).
  void _w3Moved(List<ObjId> moving, List<int> from, int to) {
    for (final o in state.objects.values.toList()) {
      if (o.zone != Zone.board || moving.contains(o.id) || card(o.id).type != CardType.unit) continue;
      final ts = _w3Triggers(o.id, W3On.friendMovesFromMe);
      if (ts.isEmpty) continue;
      var k = -1;
      for (var j = 0; j < moving.length; j++) {
        if (from[j] == o.loc && from[j] != to && state.obj(moving[j]).controller == o.controller) {
          k = j;
          break;
        }
      }
      if (k < 0) continue;
      for (final i in ts) {
        _queue(o.id, i, o.controller, loc: to, event: moving[k]);
      }
    }
  }

  /// [p]'s spell or ability from [source] chose [chosen] (The Dreaming Tree: a player's first
  /// friendly unit chosen there with a spell each turn).
  void _w3Chosen(List<int> chosen, int p, ObjId source) {
    if (_probe) return;
    final s = state.objOrNull(source);
    if (s == null || card(source).type != CardType.spell) return;
    for (final id in chosen.toSet()) {
      if (id <= 0 || id >= _chainRef) continue;
      final o = state.objOrNull(id);
      if (o == null || o.zone != Zone.board || o.controller != p || card(id).type != CardType.unit || o.loc < 0 || o.loc >= state.bfs.length) continue;
      final bf = state.bfs[o.loc].obj;
      for (final i in _w3Triggers(bf, W3On.firstChosenHereBySpell)) {
        final k = 't:w3:first:$bf:$i:$p';
        if ((state.marks[k] ?? 0) > 0) continue;
        state.marks[k] = 1;
        _queue(bf, i, p, loc: o.loc, event: id);
      }
    }
  }

  // -------------------------------------------------------------------------------------------
  // Passives
  // -------------------------------------------------------------------------------------------

  Iterable<(ObjId, W3Passive)> _w3Passives() sync* {
    for (final (src, pa) in _passives()) {
      if (pa is W3Passive) yield (src, pa);
    }
  }

  /// Renata Glasc: the extra Energy [p]'s Gold adds while they're near the Victory Score.
  int _w3GoldExtra(ObjId src) {
    final o = state.objOrNull(src);
    if (o == null || card(src).name != 'Gold' || !card(src).token) return 0;
    var n = 0;
    for (final (s, pa) in _w3Passives()) {
      if (pa is W3GoldBonus && state.obj(s).controller == o.controller && _genVictoryScore() - state.player(o.controller).points <= pa.within) n += pa.energy;
    }
    return n;
  }

  /// [add] as Gold [src] adds it now (for paying with it).
  AddRes _w3AddRes(ObjId src, AddRes add) {
    final x = _w3GoldExtra(src);
    return x == 0 ? add : AddRes(energy: add.energy + x, anyPower: add.anyPower, spellsOnly: add.spellsOnly, power: add.power);
  }

  /// Renekton's Energy, for units and activated abilities of units only.
  int _w3UnitPool(int p) => state.marks['w3:unitE:$p'] ?? 0;

  void _w3AddUnitEnergy(int p, int n) {
    state.marks['w3:unitE:$p'] = _w3UnitPool(p) + n;
    log('${playerName(p)} adds {$n} for units and their abilities.', player: p, kind: 'info');
  }

  /// After paying for a unit or a unit's ability with [general] Energy in the pool (plus [adds]
  /// from resource abilities) and the restricted Energy: [remaining] is what's left of both.
  /// Restricted Energy is spent first; returns the general pool's new amount.
  int _w3SettleUnitPool(int p, int general, int adds, int remaining) {
    final r = _w3UnitPool(p);
    if (r == 0) return remaining;
    var keep = remaining - (general + adds);
    if (keep < 0) keep = 0;
    if (keep > r) keep = r;
    if (keep == 0) {
      state.marks.remove('w3:unitE:$p');
    } else {
      state.marks['w3:unitE:$p'] = keep;
    }
    return remaining - keep;
  }

  /// Rune pools empty (CR 165): the restricted Energy too.
  void _w3EmptyPools() => state.marks.removeWhere((k, _) => k.startsWith('w3:unitE:'));

  /// Sandstone Chimera: how many runes the Channel Phase channels.
  int _w3ChannelCount(int n) {
    for (final (src, pa) in _w3Passives()) {
      if (pa is W3ChannelOnly && isUnit(src) && state.obj(src).loc != base && pa.n < n) n = pa.n;
    }
    return n;
  }

  /// Shadow: "If you play me to a battlefield, I enter ready."
  bool _w3EntersReady(ObjId id, int loc) => loc != base && card(id).type == CardType.unit && parsed(id).abilities.any((a) => a is Static && a.passive is W3ReadyAtBattlefield);

  /// Soraka, Wanderer and Unlicensed Armory: replacements for a unit about to die (CR 367).
  bool _w3SaveFromDeath(ObjId id) {
    final o = state.obj(id);
    if (card(id).type != CardType.unit) return false;
    final payer = state.marks.remove('t:w3:save:$id');
    final dom = state.marks.remove('t:w3:saveP:$id');
    if (payer != null && dom != null) {
      final q = payer - 1;
      final power = [Domain.values[dom - 1]];
      if (canPay(q, 0, power) && askYesNo(q, 'Pay {${power.first.letter}} to recall ${nameOf(id)} exhausted instead of it dying?', source: id)) {
        _pay(q, 0, power);
        o
          ..exhausted = true
          ..loc = base;
        log('${nameOf(id)} is recalled exhausted instead of dying.', player: q, card: id, kind: 'move');
        return true;
      }
    }
    for (final (src, pa) in _w3Passives()) {
      if (pa is! W3SorakaSave || src == id || !isUnit(src)) continue;
      final s = state.obj(src);
      if (s.controller != o.controller || s.loc != o.loc || might(id) >= might(src)) continue;
      o
        ..damage = 0
        ..exhausted = true
        ..loc = base;
      log('${nameOf(src)} saves ${nameOf(id)}: it is healed, exhausted and recalled instead of dying.', player: o.controller, card: id, kind: 'move');
      return true;
    }
    return false;
  }

  /// Symbol of the Solari: [att]'s combat ended with both sides still there.
  bool _w3SolariTie(int att) {
    for (final (src, pa) in _w3Passives()) {
      if (pa is W3SolariTie && state.obj(src).zone == Zone.board && state.obj(src).controller == att) return true;
    }
    return false;
  }

  /// Syndra, Transcendent: [Repeat] costs [p]'s spells have now.
  List<RepeatCost> _w3GrantedRepeats(int p, ObjId id) {
    if (card(id).type != CardType.spell) return const [];
    final sd = state.showdown;
    if (sd == null) return const [];
    return [
      for (final (src, pa) in _w3Passives())
        if (pa is W3GrantRepeat && isUnit(src) && state.obj(src).controller == p && state.obj(src).loc == sd.bf) RepeatCost('[Repeat] ${pa.cost.describe()} (${nameOf(src)})', pa.cost),
    ];
  }

  /// Can [p] pay a [Repeat]'s costs beyond runes (Square Up: "[Repeat] - Discard 1") for [id]?
  bool _w3RepeatExtraOk(int p, ObjId id, RepeatCost a) {
    var discard = 0;
    for (final x in a.cost.extra) {
      if (x is DiscardCost) discard += x.n;
    }
    return discard == 0 || state.player(p).hand.where((h) => h != id).length >= discard;
  }

  /// Pays the [Repeat] costs beyond runes chosen as [id] was played.
  void _w3PayRepeatExtras(int p, ObjId id, List<RepeatCost> paid) {
    for (final a in paid) {
      for (final x in a.cost.extra) {
        if (x is! DiscardCost) continue;
        final hand = state.player(p).hand;
        final k = x.n < hand.length ? x.n : hand.length;
        if (k == 0) continue;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Discard $k to Repeat ${nameOf(id)}', options: List.of(hand), min: k, max: k, source: id));
        for (final h in pick) {
          hand.remove(h);
          state.obj(h).zone = Zone.trash;
          state.player(p).trash.add(h);
        }
        log('${playerName(p)} discards ${pick.map(nameOf).join(', ')}.', player: p, kind: 'discard');
        _genDiscarded(p, pick);
      }
    }
  }

  /// "As you play this, name a tag" (The List): asked as it enters the board.
  void _w3AsPlayed(int p, ObjId id) {
    if (!parsed(id).abilities.any((a) => a is Static && a.passive is W3NameTag)) return;
    final all = _w3AllTags();
    // Tags of units on the board first (most useful), then the rest; each list alphabetical.
    final onBoard = {for (final u in units()) ...card(u).tags}.toList()..sortStable((a, b) => a.compareTo(b));
    final order = [...onBoard.where(all.contains), ...all.where((t) => !onBoard.contains(t))];
    if (order.isEmpty) return;
    final a = ask(Decision(kind: DecisionKind.option, player: p, prompt: '${nameOf(id)}: name a tag', labels: order, source: id));
    state.marks['w3:tag:$id'] = all.indexOf(order[a.first]) + 1;
    log('${playerName(p)} names ${order[a.first]}.', player: p, card: id, kind: 'info');
  }

  /// Every tag on a unit card, alphabetical (a named tag is kept as its index here).
  List<String> _w3AllTags() {
    final out = <String>{};
    for (final c in db.cards) {
      if (c.type == CardType.unit) out.addAll(c.tags);
    }
    return out.toList()..sortStable((a, b) => a.compareTo(b));
  }

  String? _w3NamedTag(ObjId src) {
    final i = state.marks['w3:tag:$src'];
    if (i == null) return null;
    final all = _w3AllTags();
    return i - 1 < all.length ? all[i - 1] : null;
  }

  bool _w3HasTag(ObjId id, String tag) => card(id).hasTag(tag) || _eqHasTag(id, tag);

  /// Void Hatchling: "If you would reveal cards from a deck, look at the top card first. You may
  /// recycle it. Then reveal those cards." Called before [p] reveals from their Main Deck (or
  /// [runes] deck).
  void _w3BeforeReveal(int p, {bool runes = false}) {
    final has = _w3Passives().any((x) => x.$2 is W3PeekBeforeReveal && isUnit(x.$1) && state.obj(x.$1).controller == p);
    if (!has) return;
    final pl = state.player(p);
    final deck = runes ? pl.runeDeck : pl.deck;
    if (deck.isEmpty) return;
    final top = deck.first;
    if (!askYesNo(p, 'Void Hatchling: the top card is ${nameOf(top)}. Recycle it before revealing?')) return;
    deck.removeAt(0);
    if (runes) {
      deck.add(top);
      log('${pl.name} recycles the top rune of their rune deck.', player: p, kind: 'info');
    } else {
      _recycleCards(p, [top]);
      log('${pl.name} recycles the top card of their Main Deck.', player: p, kind: 'info');
    }
  }

  /// Zilean, Time Mage: a token unit [id] just entered for [p] at [loc]; once each turn while
  /// Zilean is at a battlefield, an additional copy of it may come too.
  void _w3Entered(ObjId id, int p, int loc, bool ready) {
    final c = card(id);
    if (!c.token || c.type != CardType.unit) return;
    for (final (src, pa) in _w3Passives()) {
      if (pa is! W3TokenCopy || src == id || !isUnit(src)) continue;
      final z = state.obj(src);
      if (z.controller != p || z.loc == base) continue;
      final k = 't:w3:zilean:$src';
      if ((state.marks[k] ?? 0) > 0) continue;
      state.marks[k] = 1;
      if (!askYesNo(p, '${nameOf(src)}: play an additional copy of ${c.name}?', source: src)) return;
      final copy = _newObj(state.obj(id).card, p, Zone.board);
      _enterBoard(copy, p, loc, ready: ready);
      state.obj(copy).kwMod = Map.of(state.obj(id).kwMod);
      log('${playerName(p)} plays an additional ${c.name}.', player: p, card: copy, kind: 'play');
      _genEvent(GEv.played, player: p, obj: copy);
      return;
    }
  }
}
