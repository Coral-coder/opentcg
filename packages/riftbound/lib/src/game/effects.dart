part of 'game.dart';

/// Who is resolving: controller, source, the source's location ("here"), and chosen targets.
class _Ctx {
  _Ctx({required this.controller, required this.source, required this.loc, required this.targets, this.event = -1, this.paid = 0, this.costRef = -1, this.ability = -2, this.via = -1});
  final int controller;
  final ObjId source;
  final int loc;
  final List<int> targets;

  /// The unit a trigger is about, or -1.
  final int event;

  /// The attached card whose Effect Text this ability is ("this"), or -1 (game/equip.dart).
  final int via;
  /// How the spell was played ([PlayFlags]) and what its additional cost killed (game/costs.dart).
  final int paid;
  final int costRef;

  /// The ability resolving (-1: a spell's instructions; -2: unknown).
  final int ability;

  /// What the general effects noted while resolving ("paid", "that", "lkMight"; general.dart).
  final Map<String, int> scratch = {};
}

/// Choosing targets (CR 355.5–355.10) and executing instructions (CR 158, 359.3.e).
extension GameEffects on Game {
  /// Walks [effects] in text order and asks for every [Choose] (by slot). Mandatory targets
  /// with no legal choice: an error for a spell or ability being played (it can't be played),
  /// -1 for a trigger ([optional]; it then fails to go on the chain).
  ///
  /// [restrictBf]: a card played from facedown there chooses there (CR 811.1.d).
  List<int> _chooseTargets(List<Effect> effects, int p, ObjId source, int loc, {bool optional = false, int repeats = 0, int restrictBf = -1}) {
    final out = <int>[];
    _powerTargetsOf[this] = out;
    final asked = <int>{};
    // Each execution of a Repeat chooses in its own range of slots (CR 820.2).
    var offset = 0;
    void set(int slot, int v) {
      final i = slot + offset;
      while (out.length <= i) {
        out.add(-1);
      }
      out[i] = v;
    }

    final chosenNow = <int>[];
    void pick(Effect e, Target? t, {bool mayDecline = false, List<int> exclude = const []}) {
      if (t is HTarget) {
        final h = _hOptions(t, p, source, loc, offset == 0 ? out : out.sublist(offset < out.length ? offset : out.length));
        if (h == null) return;
        final options = [for (final id in _hNarrow(h.options, t, p, restrictBf)) if (!_unchoosable(id, p) && _xAllowed(out, h.slot + offset, id)) id];
        if (options.isEmpty) {
          if (h.upTo || optional || mayDecline) {
            set(h.slot, -1);
            return;
          }
          throw RiftboundError('No legal target for ${nameOf(source)}');
        }
        final a = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: ${h.prompt}', options: options, min: h.upTo ? 0 : 1, max: 1, source: source));
        set(h.slot, a.isEmpty ? -1 : a.first);
        return;
      }
      if (t is! Choose || !asked.add(t.slot + offset)) return;
      final options = [for (final id in _hNarrow(matching(t.filter, controller: p, source: source, here: loc, slots: out), t, p, restrictBf)) if (!_unchoosable(id, p) && !_genUntargetable(id, p) && !exclude.contains(id) && _xAllowed(out, t.slot + offset, id) && _eqChoosable(t, id, out)) id];
      if (options.isEmpty) {
        if (t.upTo || optional || mayDecline) {
          set(t.slot, -1);
          return;
        }
        throw RiftboundError('No legal target for ${nameOf(source)}');
      }
      final a = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: choose ${_describeChoice(e, t)}', options: options, min: t.upTo ? 0 : 1, max: 1, source: source));
      set(t.slot, a.isEmpty ? -1 : a.first);
      if (a.isNotEmpty) chosenNow.add(a.first);
    }

    final usedModes = <int, List<int>>{};
    void walk(List<Effect> es, {bool mayDecline = false}) {
      for (final e in es) {
        switch (e) {
          case HEffect():
            for (final t in e.choices) {
              pick(e, t, mayDecline: mayDecline || e.optional);
            }
            walk(e.nested, mayDecline: mayDecline || e.optional);
          case May(:final effects):
            walk(effects, mayDecline: mayDecline);
          case Modes(:final modes, :final slot) when slot >= 0:
            // The mode is chosen as it's played (CR 355.3).
            final i = _xChooseMode(e, p, source, loc, usedModes[slot] ?? const [], optional: optional || mayDecline);
            if (i < 0) {
              if (optional || mayDecline) {
                set(slot, -1);
                continue;
              }
              throw RiftboundError('No mode of ${nameOf(source)} can be chosen');
            }
            set(slot, i);
            (usedModes[slot] ??= []).add(i);
            walk(modes[i], mayDecline: mayDecline);
          case Modes(:final modes):
            for (final m in modes) {
              walk(m, mayDecline: mayDecline);
            }
          case If(:final effects):
            walk(effects, mayDecline: mayDecline);
          case PowerEffect() when _powerInner(e) != null:
            walk(_powerInner(e)!, mayDecline: mayDecline);
          case GenEffect():
            _genChoose(e, p, source, loc, out, set, (es) => walk(es, mayDecline: mayDecline), optional: optional || mayDecline, restrictBf: restrictBf);
          case Counter():
            final spells = [for (final it in state.chain) if (it.isSpell && it.source != source && !_cantBeCountered(it.controller)) it.source];
            if (spells.isEmpty) {
              if (optional) return;
              throw RiftboundError('No spell to counter');
            }
            set(0, ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Counter which spell?', options: spells, source: source)).first);
          case EqMayPay(:final effects):
            walk(effects, mayDecline: mayDecline);
          case EqEffect():
            for (final t in e.targets) {
              pick(e, t, mayDecline: mayDecline);
            }
          case XEffect():
            _xChooseFor(e, p, source, loc, optional || mayDecline, set, (e, t, exclude) => pick(e, t, mayDecline: mayDecline, exclude: exclude), (es) => walk(es, mayDecline: mayDecline), () => List.of(chosenNow), (slot, id) => _xAllowed(out, slot + offset, id));
          default:
            final t = _targetOf(e);
            if (t is GenTarget) {
              _genChooseOne(ChooseOnly([t]), t, p, source, loc, out, set, optional: optional || mayDecline, restrictBf: restrictBf);
            } else {
              pick(e, t, mayDecline: mayDecline);
            }
        }
      }
    }

    final per = repeats > 0 ? _xSlotCount(effects) : 0;
    for (var r = 0; r <= repeats; r++) {
      offset = r * per;
      chosenNow.clear();
      walk(effects);
    }
    _genChosen(out, p, source);
    return out;
  }

  /// Does a mandatory choice have no target (a trigger then doesn't go on the chain)?
  bool _mandatoryTargetsMissing(List<Effect> effects, List<int> targets) {
    for (final e in effects) {
      if (e is May || (e is HEffect && e.optional)) continue;
      if (e is EqEffect) {
        if (_eqMissing(e, targets)) return true;
        continue;
      }
      if (e is Modes && e.slot >= 0) {
        final i = e.slot < targets.length ? targets[e.slot] : -1;
        if (i < 0 || _mandatoryTargetsMissing(e.modes[i], targets)) return true;
        continue;
      }
      if (e is GenEffect) {
        if (_genMissing(e, targets)) return true;
        continue;
      }
      final t0 = _targetOf(e);
      if (t0 is GenTarget && _genMissing(ChooseOnly([t0]), targets)) return true;
      for (final t in e is HEffect ? e.choices : [?t0]) {
        final slot = switch (t) {
          Choose(:final slot, :final upTo) when !upTo => slot,
          ChooseBf(:final slot) || ChooseRel(:final slot) || ChooseOwnCard(:final slot) => slot,
          _ => -1,
        };
        if (slot >= 0 && (slot >= targets.length || targets[slot] < 0)) return true;
      }
    }
    return false;
  }

  Target? _targetOf(Effect e) => switch (e) {
        Deal(:final target) || Buff(:final target) || Ready(:final target) || Exhaust(:final target) || Stun(:final target) || Kill(:final target) => target,
        GiveMight(:final target) || GiveKw(:final target) || ToBase(:final target) || ToHand(:final target) || Heal(:final target) || ToOrFromBase(:final target) => target,
        PowerEffect() => _powerTargetOf(e),
        _ => null,
      };

  String _describeChoice(Effect e, Choose t) {
    final what = switch (e) {
      Deal(:final amount) => 'something to deal ${amount is N ? amount.n : 'damage'} to',
      Buff() => 'a unit to buff',
      Ready() => 'something to ready',
      Exhaust() => 'something to exhaust',
      Stun() => 'a unit to stun',
      Kill() => 'something to kill',
      GiveMight(:final n) => 'a unit to give ${n >= 0 ? '+' : ''}$n Might',
      GiveKw(:final kw) => 'a unit to give ${kwLabel(kw)}',
      ToBase() => 'a unit to send to base',
      ToOrFromBase() => 'a unit to move to or from base',
      ToHand() => 'something to return to hand',
      Heal() => 'a unit to heal',
      _ => 'a target',
    };
    return what;
  }

  /// The objects an effect acts on as it resolves; illegal targets are skipped (CR 359.3.e).
  List<ObjId> _resolveTarget(Target t, _Ctx ctx) {
    switch (t) {
      case Me():
        final o = state.objOrNull(ctx.source);
        return o != null && (o.zone == Zone.board || o.zone == Zone.legend) ? [ctx.source] : const [];
      case Choose(:final slot, :final filter):
        if (slot >= ctx.targets.length) return const [];
        final id = ctx.targets[slot];
        if (id < 0) return const [];
        _powerTargetsOf[this] = ctx.targets;
        return matches(filter, id, controller: ctx.controller, source: ctx.source, here: ctx.loc) && _eqChoosable(t, id, ctx.targets) ? [id] : const [];
      case Chosen(:final slot):
        if (slot >= ctx.targets.length) return const [];
        final id = ctx.targets[slot];
        return id >= 0 && state.objOrNull(id)?.zone == Zone.board ? [id] : const [];
      case Each(:final filter):
        return matching(filter, controller: ctx.controller, source: ctx.source, here: ctx.loc);
      case EventUnit():
        final id = ctx.event;
        return id >= 0 && state.objOrNull(id)?.zone == Zone.board ? [id] : const [];
      case EqTarget():
        return _eqResolveTarget(t, ctx);
      case GenTarget():
        return _genResolveTarget(t, ctx);
      case HTarget():
        return _hResolveTarget(t, ctx);
    }
  }

  void _resolveEffects(List<Effect> effects, _Ctx ctx, {int rep = 0}) {
    for (final e in effects) {
      if (state.over) return;
      _resolve(e, ctx);
    }
  }

  void _resolve(Effect e, _Ctx ctx) {
    final p = ctx.controller;
    switch (e) {
      case Deal(:final amount, :final target):
        final n = _amount(amount, ctx);
        for (final id in _resolveTarget(target, ctx)) {
          if (!isUnit(id) || _noDamage(id)) continue;
          _hDeal(id, n, ctx);
          _xDamaged(p, id);
        }
      case Draw(:final n):
        _draw(p, n);
      case Discard(:final n):
        final hand = state.player(p).hand;
        if (hand.isEmpty) return;
        final k = n < hand.length ? n : hand.length;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Discard $k', options: List.of(hand), min: k, max: k, source: ctx.source));
        for (final id in pick) {
          hand.remove(id);
          state.obj(id).zone = Zone.trash;
          state.player(p).trash.add(id);
        }
        log('${playerName(p)} discards ${pick.map(nameOf).join(', ')}.', player: p, kind: 'discard');
        _genDiscarded(p, pick);
      case Buff(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          if (isUnit(id)) _buffUnit(id, p);
        }
      case Ready(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          if (_hCantReady(id) || !_genCanReady(id, p)) continue;
          final was = state.obj(id).exhausted;
          if (was) _xBecameReady(id);
          state.obj(id).exhausted = false;
          if (was && isUnit(id)) _genReadied(id, p);
        }
      case Exhaust(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          state.obj(id).exhausted = true;
        }
      case Stun(:final target):
        var enemy = false;
        for (final id in _resolveTarget(target, ctx)) {
          if (!isUnit(id) || state.obj(id).stunned || _harmReplaced(id, target, p)) continue;
          state.obj(id).stunned = true;
          if (state.obj(id).controller != p) enemy = true;
          log('${nameOf(id)} is stunned.', player: p, card: id, kind: 'stun');
          _genEvent(GEv.stunned, player: p, obj: id);
        }
        if (enemy) _fire(On.youStunEnemy, player: p);
      case Kill(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          log('${nameOf(id)} is killed.', player: p, card: id, kind: 'die');
          _genNoteHit(id, ctx);
          _kill(id);
        }
      case GiveMight(:final n, :final target, :final min):
        for (final id in _resolveTarget(target, ctx)) {
          if (!isUnit(id) || (n < 0 && _harmReplaced(id, target, p))) continue;
          var delta = n + _extraMinus(n, target, p);
          // "To a minimum of N": the decrease stops at N, fixed now (CR 479.4.b).
          if (min != null && delta < 0) {
            final now = might(id);
            final floor = now <= min ? 0 : min - now;
            if (delta < floor) delta = floor;
          }
          state.obj(id).mightMod += delta;
          log('${nameOf(id)} gets ${n >= 0 ? '+' : ''}$n Might this turn.', player: p, card: id, kind: 'buff');
        }
      case GiveKw(:final kw, :final n, :final target):
        for (final id in _resolveTarget(target, ctx)) {
          if (!isUnit(id)) continue;
          final m = state.obj(id).kwMod;
          m[kw.index] = (m[kw.index] ?? 0) + n;
        }
      case ToBase(:final target, :final asMove):
        for (final id in _resolveTarget(target, ctx)) {
          final o = state.obj(id);
          if (o.loc == base) continue;
          if (asMove && _eqUnmovable(id, p)) continue;
          if (asMove) {
            _moveUnits([id], base, p);
          } else {
            o.loc = base;
            log('${nameOf(id)} is recalled.', player: p, card: id, kind: 'move');
          }
        }
      case ToHand(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          if (_harmReplaced(id, target, p)) continue;
          log('${nameOf(id)} returns to its owner’s hand.', player: p, card: id, kind: 'move');
          _leaveBoard(id, toHand: true);
        }
      case ToOrFromBase(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          final o = state.obj(id);
          if (_eqUnmovable(id, p)) continue;
          if (o.loc != base) {
            _moveUnits([id], base, p);
          } else if (state.bfs.isNotEmpty) {
            final i = ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Move ${nameOf(id)} to which battlefield?', labels: [for (final b in state.bfs) nameOf(b.obj)], source: ctx.source)).first;
            _moveUnits([id], i, p);
          }
        }
      case ReadyRunes(:final n):
        var left = n;
        for (final r in state.player(p).runes) {
          if (left == 0) break;
          if (state.obj(r).exhausted) {
            state.obj(r).exhausted = false;
            left--;
          }
        }
      case If(:final cond, :final effects):
        if (_cond(cond, ctx)) {
          for (final x in effects) {
            _resolve(x, ctx);
          }
        }
      case Heal(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          state.obj(id).damage = 0;
        }
      case Channel(:final n, :final exhausted):
        _channel(p, n, exhausted: exhausted);
      case PlayToken(:final token, :final count, :final here, :final ready):
        final src = state.objOrNull(ctx.source);
        final loc = _hTokenLoc(ctx) ?? (here && src != null && src.zone == Zone.board ? src.loc : base);
        for (var i = 0; i < count; i++) {
          final id = _newObj(token, p, Zone.board);
          _enterBoard(id, p, loc, ready: ready || db[token]!.type == CardType.gear);
          _eqTokenPlayed(id, p);
          _hs.lastMade = id;
        }
        log('${playerName(p)} plays $count $token token${count == 1 ? '' : 's'}.', player: p, kind: 'play');
      case GainPoints(:final n):
        _genGainPoints(p, n);
      case Predict(:final n):
        final deck = state.player(p).deck;
        final top = deck.take(n).toList();
        if (top.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Predict: choose cards to recycle (the rest stay on top)', options: top, min: 0, max: top.length, source: ctx.source));
        for (final id in pick) {
          deck.remove(id);
          deck.add(id);
        }
        if (pick.isNotEmpty) _recycled(p);
        log('${playerName(p)} predicts${pick.isEmpty ? '' : ' and recycles ${pick.length}'}.', player: p, kind: 'info');
      case Counter():
        if (ctx.targets.isEmpty) return;
        final victim = ctx.targets[0];
        final i = state.chain.indexWhere((it) => it.isSpell && it.source == victim);
        if (i < 0) return;
        ctx.scratch['counteredCtl'] = state.chain[i].controller;
        if (_genCantBeCountered(victim)) {
          log('${nameOf(victim)} can’t be countered.', player: p, card: victim, kind: 'info');
          return;
        }
        state.chain.removeAt(i);
        final o = state.obj(victim)..zone = Zone.trash;
        state.player(o.owner).trash.add(victim);
        ctx.scratch['countered'] = victim;
        log('${nameOf(victim)} is countered.', player: p, card: victim, kind: 'info');
      case Ws2PowerToEnergy() || Ws2RestrictedAdd():
        _ws2ResolveAdd(e as AddRes, ctx);
      case AddRes(:final energy, :final anyPower, :final power):
        final pl = state.player(p);
        pl.energyPool += energy;
        pl.anyPool += anyPower;
        for (final d in power) {
          pl.powerPool[d.index]++;
        }
      case May(:final effects):
        if (askYesNo(p, '${nameOf(ctx.source)}: ${_mayPrompt(effects)}?', source: ctx.source)) {
          ctx.scratch['paid'] = 1;
          for (final x in effects) {
            _resolve(x, ctx);
          }
        }
      case Modes(:final modes, :final slot) when slot >= 0:
        // The mode chosen as it was played (CR 355.3).
        final i = slot < ctx.targets.length ? ctx.targets[slot] : -1;
        if (i < 0 || i >= modes.length) return;
        for (final x in modes[i]) {
          _resolve(x, ctx);
        }
      case HEffect():
        _hResolve(e, ctx);
      case Modes(:final modes):
        final a = ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Choose one', labels: [for (final m in modes) m.map(describeEffect).join(', then ')], source: ctx.source));
        for (final x in modes[a.first]) {
          _resolve(x, ctx);
        }
      case EqEffect():
        _eqResolve(e, ctx);
      case XEffect():
        _xResolve(e, ctx);
      case GenEffect():
        _genResolve(e, ctx);
      case PowerEffect():
        _resolvePower(e, ctx);
    }
  }

  bool _cond(Cond c, _Ctx ctx) => switch (c) {
        HandAtMost(:final n) => state.player(ctx.controller).hand.length <= n,
        UnitsThere(:final n) => ctx.loc >= 0 && ctx.loc < state.bfs.length && unitsAt(ctx.loc, player: ctx.controller).length >= n,
        EqCond() => _eqCond(c, ctx),
        GenCond() => _genCond(c, ctx),
        PowerCond() => _powerCondEval(c, ctx),
        HCond() => _hCond(c, ctx),
        XCond() => _xCondNow(ctx.controller, c, source: ctx.source),
      };

  String _mayPrompt(List<Effect> effects) => effects.map(describeEffect).join(', then ');
}
