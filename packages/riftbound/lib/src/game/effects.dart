part of 'game.dart';

/// Who is resolving: controller, source, the source's location ("here"), and chosen targets.
class _Ctx {
  _Ctx({required this.controller, required this.source, required this.loc, required this.targets, this.event = -1, this.ability = -2});
  final int controller;
  final ObjId source;
  final int loc;
  final List<int> targets;

  /// The unit a trigger is about, or -1.
  final int event;

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
  List<int> _chooseTargets(List<Effect> effects, int p, ObjId source, int loc, {bool optional = false, int repeats = 0}) {
    final out = <int>[];
    void set(int slot, int v) {
      while (out.length <= slot) {
        out.add(-1);
      }
      out[slot] = v;
    }

    void walk(List<Effect> es) {
      for (final e in es) {
        switch (e) {
          case May(:final effects):
            walk(effects);
          case Modes(:final modes):
            for (final m in modes) {
              walk(m);
            }
          case If(:final effects):
            walk(effects);
          case Counter():
            final spells = [for (final it in state.chain) if (it.isSpell && it.source != source) it.source];
            if (spells.isEmpty) {
              if (optional) return;
              throw RiftboundError('No spell to counter');
            }
            set(0, ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Counter which spell?', options: spells, source: source)).first);
          default:
            if (e is GenEffect) {
              _genChoose(e, p, source, loc, out, set, walk, optional: optional);
              continue;
            }
            final t = _targetOf(e);
            if (t is GenTarget) {
              _genChooseOne(ChooseOnly([t]), t, p, source, loc, out, set, optional: optional);
              continue;
            }
            if (t is Choose) {
              final options = _genTargetable(matching(t.filter, controller: p, source: source, here: loc, slots: out), p, source);
              if (options.isEmpty) {
                if (t.upTo || optional) {
                  set(t.slot, -1);
                  continue;
                }
                throw RiftboundError('No legal target for ${nameOf(source)}');
              }
              final a = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: choose ${_describeChoice(e, t)}', options: options, min: t.upTo ? 0 : 1, max: 1, source: source));
              set(t.slot, a.isEmpty ? -1 : a.first);
            }
        }
      }
    }

    walk(effects);
    _genChosen(out, p, source);
    return out;
  }

  /// Does a mandatory choice have no target (a trigger then doesn't go on the chain)?
  bool _mandatoryTargetsMissing(List<Effect> effects, List<int> targets) {
    for (final e in effects) {
      if (e is May) continue;
      if (e is GenEffect) {
        if (_genMissing(e, targets)) return true;
        continue;
      }
      final t = _targetOf(e);
      if (t is GenTarget && _genMissing(ChooseOnly([t]), targets)) return true;
      if (t is Choose && !t.upTo && (t.slot >= targets.length || targets[t.slot] < 0)) return true;
    }
    return false;
  }

  Target? _targetOf(Effect e) => switch (e) {
        Deal(:final target) || Buff(:final target) || Ready(:final target) || Exhaust(:final target) || Stun(:final target) || Kill(:final target) => target,
        GiveMight(:final target) || GiveKw(:final target) || ToBase(:final target) || ToHand(:final target) || Heal(:final target) || ToOrFromBase(:final target) => target,
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
        return o != null && o.zone == Zone.board ? [ctx.source] : const [];
      case Choose(:final slot, :final filter):
        if (slot >= ctx.targets.length) return const [];
        final id = ctx.targets[slot];
        if (id < 0) return const [];
        return matches(filter, id, controller: ctx.controller, source: ctx.source, here: ctx.loc) ? [id] : const [];
      case Chosen(:final slot):
        if (slot >= ctx.targets.length) return const [];
        final id = ctx.targets[slot];
        return id >= 0 && state.objOrNull(id)?.zone == Zone.board ? [id] : const [];
      case Each(:final filter):
        return matching(filter, controller: ctx.controller, source: ctx.source, here: ctx.loc);
      case EventUnit():
        final id = ctx.event;
        return id >= 0 && state.objOrNull(id)?.zone == Zone.board ? [id] : const [];
      case GenTarget():
        return _genResolveTarget(t, ctx);
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
        final n = switch (amount) {
          N(:final n) => n,
          MyMight() => state.objOrNull(ctx.source)?.zone == Zone.board ? mightUsed(ctx.source) : 0,
          GenAmount() => _genAmount(amount, ctx),
        };
        for (final id in _resolveTarget(target, ctx)) {
          final d = _genDeal(id, n, ctx);
          if (d > 0) log('${nameOf(ctx.source)} deals $d to ${nameOf(id)}.', player: p, card: id, kind: 'damage', amount: d);
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
          if (!isUnit(id)) continue;
          if (state.obj(id).buffed) {
            // "I can have any number of buffs" (CR 427.1.b.2).
            if (!_genSelfRestricted(id, RKind.manyBuffs)) continue;
            _gen.setL('o$id:buffs', _gen.getL('o$id:buffs') + 1);
          }
          state.obj(id).buffed = true;
          log('${nameOf(id)} is buffed.', player: p, card: id, kind: 'buff');
          _genBuffed(id, p);
        }
      case Ready(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          if (!_genCanReady(id, p)) continue;
          final was = state.obj(id).exhausted;
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
          if (!isUnit(id) || state.obj(id).stunned) continue;
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
          if (!isUnit(id)) continue;
          var delta = n;
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
          if (asMove) {
            _moveUnits([id], base, p);
          } else {
            o.loc = base;
            log('${nameOf(id)} is recalled.', player: p, card: id, kind: 'move');
          }
        }
      case ToHand(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          log('${nameOf(id)} returns to its owner’s hand.', player: p, card: id, kind: 'move');
          _leaveBoard(id, toHand: true);
        }
      case ToOrFromBase(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          final o = state.obj(id);
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
        final loc = here && src != null && src.zone == Zone.board ? src.loc : base;
        for (var i = 0; i < count; i++) {
          final id = _newObj(token, p, Zone.board);
          _enterBoard(id, p, loc, ready: ready || db[token]!.type == CardType.gear);
        }
        log('${playerName(p)} plays $count $token token${count == 1 ? '' : 's'}.', player: p, kind: 'play');
      case GainPoints(:final n):
        state.player(p).points += n;
        log('${playerName(p)} gains $n point${n == 1 ? '' : 's'}.', player: p, kind: 'point', amount: n);
      case Predict(:final n):
        final deck = state.player(p).deck;
        final top = deck.take(n).toList();
        if (top.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Predict: choose cards to recycle (the rest stay on top)', options: top, min: 0, max: top.length, source: ctx.source));
        for (final id in pick) {
          deck.remove(id);
          deck.add(id);
        }
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
      case Modes(:final modes):
        final a = ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Choose one', labels: [for (final m in modes) m.map(describeEffect).join(', then ')], source: ctx.source));
        for (final x in modes[a.first]) {
          _resolve(x, ctx);
        }
      case GenEffect():
        _genResolve(e, ctx);
    }
  }

  bool _cond(Cond c, _Ctx ctx) => switch (c) {
        HandAtMost(:final n) => state.player(ctx.controller).hand.length <= n,
        UnitsThere(:final n) => ctx.loc >= 0 && ctx.loc < state.bfs.length && unitsAt(ctx.loc, player: ctx.controller).length >= n,
        GenCond() => _genCond(c, ctx),
      };

  String _mayPrompt(List<Effect> effects) => effects.map(describeEffect).join(', then ');
}
