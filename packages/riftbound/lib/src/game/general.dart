part of 'game.dart';

/// Objects whose Might or keywords are being computed: a passive that checks Might while Might is
/// being computed (Fiora: "While I'm [Mighty], I have [Shield]") sees it without itself.
final Set<int> _genBusy = {};

/// Chain items chosen as targets are stored as this plus their id.
const _chainRef = 1000000;

/// The general effects (ir_general.dart): choosing, resolving, matching, passives, events and
/// delayed abilities.
extension GameGeneral on Game {
  GenState get _gen => state.gen;

  // -------------------------------------------------------------------------------------------
  // Choices as a spell or ability is played (CR 355)
  // -------------------------------------------------------------------------------------------

  void _genChoose(GenEffect e, int p, ObjId source, int loc, List<int> out, void Function(int, int) set, void Function(List<Effect>) walk, {required bool optional}) {
    for (final t in e.targets) {
      _genChooseOne(e, t, p, source, loc, out, set, optional: optional);
    }
    if (e is Move) _genChooseDest(e, p, source, loc, out, set, optional: optional);
    // Delayed abilities and "do this" effects choose when they happen.
    if (e is Delay || e is LookTop) return;
    for (final n in e.nested) {
      walk(n);
    }
  }

  /// Objects [p]'s spell or ability from [source] may choose (CR 355.9.b).
  List<ObjId> _genTargetable(List<ObjId> ids, int p, ObjId source) => [
    for (final id in ids)
      if (!_genUntargetable(id, p)) id,
  ];

  bool _genUntargetable(ObjId id, int p) {
    final o = state.objOrNull(id);
    if (o == null || o.zone != Zone.board || o.controller == p) return false;
    for (final a in parsed(id).abilities) {
      if (a is Static && a.passive is Restrict) {
        final r = a.passive as Restrict;
        if (r.kind == RKind.untargetable && (r.cond == null || _genPassiveCond(r.cond!, id))) return true;
      }
    }
    for (final (src, pa) in _passives()) {
      if (pa is! UntargetableOthers || src == id) continue;
      final so = state.obj(src);
      if (so.zone != Zone.board || so.controller == p) continue;
      if (matches(pa.filter, id, controller: so.controller, source: src, here: so.loc)) return true;
    }
    return false;
  }

  void _genChooseOne(GenEffect e, Target t, int p, ObjId source, int loc, List<int> out, void Function(int, int) set, {required bool optional}) {
    switch (t) {
      case Choose(:final filter, :final slot, :final upTo):
        var options = _genTargetable(matching(filter, controller: p, source: source, here: loc, slots: out), p, source);
        if (e is DealOther && e.except < out.length) {
          options = [
            for (final x in options)
              if (x != out[e.except]) x,
          ];
        }
        if (e is Fight && e.a is Chosen) {
          final s = (e.a as Chosen).slot;
          if (s < out.length) {
            options = [
              for (final x in options)
                if (x != out[s]) x,
            ];
          }
        }
        if (options.isEmpty) {
          if (upTo || optional) {
            set(slot, -1);
            return;
          }
          throw RiftboundError('No legal target for ${nameOf(source)}');
        }
        final a = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: choose ${_genPromptFor(e, filter)}', options: options, min: upTo ? 0 : 1, max: 1, source: source));
        set(slot, a.isEmpty ? -1 : a.first);
      case ChooseOther(:final filter, :final slot, :final notSlot, :final upTo):
        final not = notSlot < out.length ? out[notSlot] : -1;
        final options = [
          for (final x in _genTargetable(matching(filter, controller: p, source: source, here: loc, slots: out), p, source))
            if (x != not) x,
        ];
        if (options.isEmpty) {
          if (upTo || optional) {
            set(slot, -1);
            return;
          }
          throw RiftboundError('No legal target for ${nameOf(source)}');
        }
        final a = ask(
          Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: choose another ${_genPromptFor(e, filter)}', options: options, min: upTo ? 0 : 1, max: 1, source: source),
        );
        set(slot, a.isEmpty ? -1 : a.first);
      case ChooseMany(:final filter, :final slot, :final max, :final min, :final sameLocation, :final totalMightMax):
        final options = _genTargetable(matching(filter, controller: p, source: source, here: loc, slots: out), p, source);
        for (var i = 0; i < max; i++) {
          set(slot + i, -1);
        }
        if (options.length < min) {
          if (optional) return;
          throw RiftboundError('Not enough targets for ${nameOf(source)}');
        }
        final a = ask(
          Decision(
            kind: DecisionKind.cards,
            player: p,
            prompt: '${nameOf(source)}: choose ${min == max ? '$max' : 'up to $max'} ${_genPromptFor(e, filter)}',
            options: options,
            min: min,
            max: max < options.length ? max : options.length,
            source: source,
          ),
        );
        if (sameLocation && a.map((id) => state.obj(id).loc).toSet().length > 1) throw RiftboundError('Choose units at the same location');
        if (totalMightMax != null && a.fold<int>(0, (s, id) => s + mightUsed(id)) > totalMightMax) throw RiftboundError('Their total Might must be $totalMightMax or less');
        if (filter.side == Side.enemy && totalMightMax != null && a.map((id) => state.obj(id).controller).toSet().length > 1) throw RiftboundError('Choose units with the same controller');
        for (var i = 0; i < a.length; i++) {
          set(slot + i, a[i]);
        }
      case ChooseLegend(:final slot, :final side):
        final options = [
          for (var q = 0; q < state.players.length; q++)
            if (state.player(q).legend != null && (side == Side.any || (side == Side.friendly) == (q == p))) state.player(q).legend!,
        ];
        if (options.isEmpty) {
          if (optional) return set(slot, -1);
          throw RiftboundError('No legend to choose');
        }
        set(slot, ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: choose a legend', options: options, source: source)).first);
      case ChooseAnything(:final slot, :final notMe):
        final options = [
          for (final o in state.objects.values)
            if (o.controller == p && o.exhausted && (o.zone == Zone.board || o.zone == Zone.runes || o.zone == Zone.legend) && (!notMe || o.id != source)) o.id,
        ];
        if (options.isEmpty) return set(slot, -1);
        set(slot, ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: choose something exhausted to ready', options: options, min: 0, source: source)).firstOrNull ?? -1);
      case ChooseBf(:final slot, :final withYourUnits, :final youControl):
        final options = [
          for (var i = 0; i < state.bfs.length; i++)
            if ((!withYourUnits || unitsAt(i, player: p).isNotEmpty) && (!youControl || state.bfs[i].controller == p)) state.bfs[i].obj,
        ];
        if (options.isEmpty) {
          if (optional) return set(slot, -1);
          throw RiftboundError('No battlefield to choose');
        }
        set(slot, ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: choose a battlefield', options: options, source: source)).first);
      case ChoosePlayer(:final slot, :final opponent):
        if (opponent) return set(slot, state.other(p));
        final a = ask(
          Decision(
            kind: DecisionKind.option,
            player: p,
            prompt: '${nameOf(source)}: choose a player',
            labels: [for (var q = 0; q < state.players.length; q++) q == p ? '${playerName(q)} (you)' : playerName(q)],
            source: source,
          ),
        );
        set(slot, a.first);
      case ChooseSpell(:final slot):
        final items = [
          for (final it in state.chain)
            if (_genSpellMatches(t, it, p, out)) it,
        ];
        if (items.isEmpty) {
          if (optional) return set(slot, -1);
          throw RiftboundError('Nothing to counter');
        }
        final a = ask(
          Decision(
            kind: DecisionKind.option,
            player: p,
            prompt: '${nameOf(source)}: counter which?',
            labels: [for (final it in items) it.isSpell ? db[it.card]!.name : '${db[it.card]!.name}’s ability'],
            source: source,
          ),
        );
        set(slot, _chainRef + items[a.first].id);
      default:
        break;
    }
  }

  bool _genSpellMatches(ChooseSpell t, ChainItem it, int p, List<int> out) {
    if (!it.isSpell && !t.abilities) return false;
    if (t.enemy && it.controller == p) return false;
    if (t.choosingFriendly) {
      final hit = it.targets.any((id) => id > 0 && id < _chainRef && state.objOrNull(id)?.zone == Zone.board && state.obj(id).controller == p);
      if (!hit) return false;
    }
    final cs = t.choosingSlot;
    if (cs != null) {
      if (cs >= out.length || out[cs] < 0) return false;
      final u = out[cs];
      if (!it.targets.contains(u)) return false;
      if (it.targets.any((id) => id > 0 && id != u && id < _chainRef && state.objOrNull(id)?.zone == Zone.board && state.obj(id).controller == p && isUnit(id))) return false;
    }
    return true;
  }

  String _genPromptFor(Effect e, Filter f) {
    final what = f.describe();
    return switch (e) {
      Fight() => '$what to fight',
      DealAmt() || ExceptDeal() || DealOther() => '$what to deal damage to',
      GiveMightAmt(:final negative) => negative ? '$what to weaken' : '$what to give +Might',
      GiveMany(:final might) => might < 0 ? '$what to weaken' : '$what to give +Might',
      DoubleMight() => '$what to give +Might',
      Move() => '$what to move',
      Banish() => '$what to banish',
      CardToHand() => '$what to return to hand',
      PlayFrom() || Blink() => '$what to play',
      TakeControl() || ToDeck() => '$what to take',
      ChooseOnly() => what,
      _ => what,
    };
  }

  /// The move's destination (CR 355.4): stored as 0 (a base) or a battlefield's object.
  void _genChooseDest(Move e, int p, ObjId source, int loc, List<int> out, void Function(int, int) set, {required bool optional}) {
    int? unit;
    final t = e.target;
    if (t is Choose) {
      unit = t.slot < out.length ? out[t.slot] : -1;
    } else if (t is Chosen) {
      unit = t.slot < out.length ? out[t.slot] : -1;
    } else if (t is Me) {
      unit = source;
    } else if (t is ChooseMany) {
      unit = t.slot < out.length ? out[t.slot] : -1;
    }
    switch (e.dest) {
      case Dest.base || Dest.here || Dest.event || Dest.slot:
        set(e.destSlot, -1);
        return;
      default:
        break;
    }
    if (unit == null || unit < 0 || state.objOrNull(unit)?.zone != Zone.board) {
      set(e.destSlot, -1);
      return;
    }
    final here = state.obj(unit).loc;
    final options = <int>[
      if (e.dest == Dest.any && here != base && !_genCantMoveTo(unit, base)) 0,
      for (var i = 0; i < state.bfs.length; i++)
        if (i != here && (e.dest != Dest.yourBattlefield || state.bfs[i].controller == p)) state.bfs[i].obj,
    ];
    if (options.isEmpty) {
      set(e.destSlot, -1);
      return;
    }
    final a = ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Move ${nameOf(unit)} where?', labels: [for (final o in options) o == 0 ? 'Base' : nameOf(o)], source: source));
    set(e.destSlot, options[a.first]);
  }

  bool _genMissing(GenEffect e, List<int> targets) {
    for (final t in e.targets) {
      final (slot, mandatory) = switch (t) {
        Choose(:final slot, :final upTo) || ChooseOther(:final slot, :final upTo) => (slot, !upTo),
        ChooseMany(:final slot, :final min) => (slot, min > 0),
        ChooseBf(:final slot) || ChooseLegend(:final slot) || ChooseSpell(:final slot) => (slot, true),
        _ => (-1, false),
      };
      if (mandatory && (slot >= targets.length || targets[slot] < 0)) return true;
    }
    if (e is ChooseOnly || e is IfElse || e is TrigIf || e is Seq) {
      for (final n in e.nested) {
        if (_mandatoryTargetsMissing(n, targets)) return true;
      }
    }
    return false;
  }

  // -------------------------------------------------------------------------------------------
  // Resolving targets, amounts and conditions
  // -------------------------------------------------------------------------------------------

  List<ObjId> _genResolveTarget(GenTarget t, _Ctx ctx) {
    List<ObjId> slots(int from, int n) => [
      for (var i = from; i < from + n && i < ctx.targets.length; i++)
        if (ctx.targets[i] > 0) ctx.targets[i],
    ];
    switch (t) {
      case ChooseMany(:final slot, :final max, :final filter):
        return [
          for (final id in slots(slot, max))
            if (matches(filter, id, controller: ctx.controller, source: ctx.source, here: ctx.loc, slots: ctx.targets)) id,
        ];
      case ChosenAll(:final slot, :final n):
        return [
          for (final id in slots(slot, n))
            if (state.objOrNull(id)?.zone == Zone.board) id,
        ];
      case YourLegend():
        final l = state.player(ctx.controller).legend;
        return l == null ? const [] : [l];
      case ChooseLegend(:final slot):
        return slots(slot, 1).where((id) => state.objOrNull(id)?.zone == Zone.legend).toList();
      case ChooseAnything(:final slot):
        return slots(slot, 1).where((id) => const {Zone.board, Zone.runes, Zone.legend}.contains(state.objOrNull(id)?.zone)).toList();
      case ChooseBf(:final slot):
        return slots(slot, 1);
      case EventObj():
        return ctx.event > 0 && state.objOrNull(ctx.event) != null ? [ctx.event] : const [];
      case ChooseOther(:final slot, :final filter):
        return [
          for (final id in slots(slot, 1))
            if (matches(filter, id, controller: ctx.controller, source: ctx.source, here: ctx.loc, slots: ctx.targets)) id,
        ];
      case SelfAny():
        final o = state.objOrNull(ctx.source);
        return o != null && (o.zone == Zone.board || o.zone == Zone.legend || o.zone == Zone.trash) ? [ctx.source] : const [];
      default:
        return const [];
    }
  }

  /// The first object [t] resolves to, or -1.
  ObjId _genFirst(Target t, _Ctx ctx) => _resolveTarget(t, ctx).firstOrNull ?? -1;

  /// The object chosen for [t] wherever it is now (it may have left the board), or -1.
  ObjId _genRaw(Target t, _Ctx ctx) {
    final slot = switch (t) {
      Choose(:final slot) || Chosen(:final slot) || ChooseOther(:final slot) => slot,
      _ => -1,
    };
    if (slot >= 0) return slot < ctx.targets.length ? ctx.targets[slot] : -1;
    if (t is EventUnit || t is EventObj) return ctx.event;
    if (t is Me) return ctx.source;
    return -1;
  }

  /// Controller and Might of [id] as it last was on the board.
  int _genLkController(ObjId id) => state.objOrNull(id)?.zone == Zone.board ? state.obj(id).controller : _gen.getL('lk:$id:ctl') - 1;
  int _genLkMight(ObjId id) => state.objOrNull(id)?.zone == Zone.board ? mightUsed(id) : _gen.getL('lk:$id:might') - 1;

  int _genAmount(GenAmount a, _Ctx ctx) {
    switch (a) {
      case CountOf(:final filter, :final per, :final plus):
        return plus + per * matching(filter, controller: ctx.controller, source: ctx.source, here: ctx.loc, slots: ctx.targets).length;
      case MightOf(:final target, :final cost):
        final id = _genFirst(target, ctx);
        if (id < 0) {
          final raw = _genRaw(target, ctx);
          if (raw > 0 && !cost) return _genLkMight(raw) < 0 ? 0 : _genLkMight(raw);
          return ctx.scratch['lkMight'] ?? 0;
        }
        return cost ? card(id).energy : mightUsed(id);
      case PlayerStat(:final stat, :final per, :final plus):
        return plus + per * _genStat(stat, ctx.controller);
      case ThatMuch():
        return ctx.scratch['that'] ?? 0;
      case DiscardedCost():
        return _gen.get('p${ctx.controller}:lastDiscardCost');
      case MyAssault():
        return state.objOrNull(ctx.source)?.zone == Zone.board ? _kw(ctx.source, Kw.assault) : 0;
      default:
        return 0;
    }
  }

  int _genStat(Stat s, int p) {
    final pl = state.player(p);
    switch (s) {
      case Stat.points:
        return pl.points;
      case Stat.trash:
        return pl.trash.length;
      case Stat.runes:
        return pl.runes.length;
      case Stat.battlefields:
        return state.bfs.where((b) => b.controller == p).length;
      case Stat.tagsAmongUnits:
        var n = 0;
        for (final tag in const ['Bird', 'Cat', 'Dog', 'Poro']) {
          if (units(player: p).any((u) => card(u).hasTag(tag))) n++;
        }
        return n;
      case Stat.mightyUnits:
        return units(player: p).where((u) => might(u) >= 5).length;
      case Stat.excess:
        return _gen.get('p$p:excess');
    }
  }

  bool _cmp(CmpOp op, int a, int b) => switch (op) {
    CmpOp.ge => a >= b,
    CmpOp.le => a <= b,
    CmpOp.eq => a == b,
    CmpOp.gt => a > b,
    CmpOp.lt => a < b,
  };

  List<int> _genPlayers(PRef r, _Ctx ctx) {
    switch (r) {
      case PYou():
        return [ctx.controller];
      case POpponent():
        return [state.other(ctx.controller)];
      case PEach():
        return [for (var i = 0; i < state.players.length; i++) (ctx.controller + i) % state.players.length];
      case PChosen(:final slot):
        return slot < ctx.targets.length && ctx.targets[slot] >= 0 ? [ctx.targets[slot]] : const [];
      case PControllerOf(:final target, :final owner):
        final id = _genRaw(target, ctx);
        if (id <= 0 || state.objOrNull(id) == null) return const [];
        if (owner) return [state.obj(id).owner];
        final c = _genLkController(id);
        return c < 0 ? const [] : [c];
      case PEvent():
        // A battlefield's trigger belongs to the player its event is about.
        return [ctx.controller];
    }
  }

  bool _genCond(GenCond c, _Ctx ctx) {
    final p = ctx.controller;
    switch (c) {
      case AloneCond(:final target):
        final id = _genFirst(target, ctx);
        if (id < 0) return false;
        final o = state.obj(id);
        return unitsAt(o.loc, player: o.controller).length == 1;
      case SpentOnSpell(:final n):
        return _gen.get('p$p:resolvingSpent') >= n;
      case CombatCond(:final excess, :final afterAttack):
        // The combat that just ended (CR 467.2.c.4 excess; an attack, CR 466).
        if (_gen.get('combat') <= 0) return false;
        if (excess > 0 && _gen.get('p$p:excess') < excess) return false;
        if (afterAttack && _gen.get('att:${ctx.source}') == 0) return false;
        return true;
      case CountCond(:final filter, :final op, :final n):
        return _cmp(op, matching(filter, controller: p, source: ctx.source, here: ctx.loc, slots: ctx.targets).length, n);
      case StatCond(:final stat, :final op, :final n, :final who):
        final q = _genPlayers(who, ctx).firstOrNull ?? p;
        return _cmp(op, _genPStat(stat, q), n);
      case ObjCond(:final target, :final filter, :final negate):
        final id = _genFirst(target, ctx);
        bool ok;
        if (id >= 0) {
          ok = matches(filter, id, controller: p, source: ctx.source, here: ctx.loc, slots: ctx.targets);
        } else {
          // It left the board: what it was (CR 383.2.c.3.b).
          final raw = _genRaw(target, ctx);
          final lkC = raw > 0 ? _genLkController(raw) : -1;
          ok = lkC >= 0;
          if (filter.side == Side.enemy) ok = ok && lkC != p;
          if (filter.side == Side.friendly) ok = ok && lkC == p;
          if (filter.mightMax != null) ok = ok && _genLkMight(raw) <= filter.mightMax!;
          if (filter.stunned == true) ok = ok && _gen.getL('lk:$raw:stunned') > 0;
        }
        return negate ? !ok : ok;
      case SelfCond(:final kind, :final negate):
        final ok = _genSelf(kind, ctx);
        return negate ? !ok : ok;
      case DidCond(:final kind, :final negate):
        var ok = (ctx.scratch[kind.name] ?? 0) > 0;
        if (kind == DidKind.killed) {
          // "If this kills it": the damage just dealt is lethal (or it's gone).
          final id = ctx.scratch['lastHit'] ?? -1;
          ok = id > 0 && (state.objOrNull(id)?.zone != Zone.board || _genLethal(id));
        }
        return negate ? !ok : ok;
      case TurnEventCond(:final kind):
        return switch (kind) {
          TurnEvent.unitDied => _gen.get('unitDied') > 0,
          TurnEvent.friendlyDiedInBeginning => _gen.get('p$p:diedBeginning') > 0,
          TurnEvent.isBeginningPhase => state.step == Step.beginning,
          _ => false,
        };
      case AndCond(:final conds):
        return conds.every((x) => _cond(x, ctx));
      case TagsAmongCond(:final tags):
        return tags.every((t) => units(player: p).any((u) => card(u).hasTag(t)));
      case TotalMightCond(:final filter, :final n):
        return matching(filter, controller: p, source: ctx.source, here: ctx.loc).fold<int>(0, (s, u) => s + mightUsed(u)) >= n;
      case NameInTrash():
        final name = state.objOrNull(ctx.source) == null ? '' : card(ctx.source).name;
        return state.player(p).trash.any((id) => card(id).name == name);
      default:
        return false;
    }
  }

  int _genPStat(PStat s, int q) {
    final pl = state.player(q);
    switch (s) {
      case PStat.runes:
        return pl.runes.length;
      case PStat.hand:
        return pl.hand.length;
      case PStat.trash:
        return pl.trash.length;
      case PStat.points:
        return pl.points;
      case PStat.pointsToWin:
        final left = _genVictoryScore() - pl.points;
        return left < 0 ? 0 : left;
      case PStat.unitsAtBattlefields:
        return units(player: q).where((u) => state.obj(u).loc != base).length;
      case PStat.fewerRunesThanOpp:
        return pl.runes.length < state.player(state.other(q)).runes.length ? 1 : 0;
      case PStat.spentThisTurn:
        return _gen.get('p$q:spent');
      case PStat.maxSpellSpend:
        return _gen.get('p$q:maxSpell');
      case PStat.discardedThisTurn:
        return _gen.get('p$q:discarded');
      case PStat.cardsPlayedThisTurn:
        return pl.playedThisTurn;
      case PStat.spellsPlayedByOppThisTurn:
        return _gen.get('p${state.other(q)}:spells');
      case PStat.turnNumber:
        return _gen.getL('p$q:turns');
      case PStat.controlsBattlefield:
        return state.bfs.where((b) => b.controller == q).length;
      case PStat.oppControlsBattlefield:
        return state.bfs.where((b) => b.controller == state.other(q)).length;
      case PStat.powerSpentThisTurn:
        return _gen.get('p$q:spentPower');
      case PStat.oppSpellsCast:
        return _gen.get('p${state.other(q)}:cast');
      case PStat.choseEnemy:
        return _gen.get('p$q:choseEnemy');
    }
  }

  bool _genSelf(SelfKind k, _Ctx ctx) {
    final id = ctx.source;
    final o = state.objOrNull(id);
    if (o == null) return false;
    final onBoard = o.zone == Zone.board;
    switch (k) {
      case SelfKind.alone:
        return _gen.getL('lk:$id:alone') > 0;
      case SelfKind.mighty:
        return onBoard ? might(id) >= 5 : _gen.getL('lk:$id:might') - 1 >= 5;
      case SelfKind.buffed:
        return onBoard && o.buffed;
      case SelfKind.atBattlefield:
        return onBoard && o.loc != base;
      case SelfKind.attackingWithAnother:
        return onBoard && isAttacking(id) && unitsAt(o.loc, player: o.controller).length > 1;
      case SelfKind.attackingOrDefendingAlone:
        return onBoard && (isAttacking(id) || isDefending(id)) && unitsAt(o.loc, player: o.controller).length == 1;
      case SelfKind.anotherHere:
        return onBoard && unitsAt(o.loc, player: o.controller).length > 1;
      case SelfKind.inShowdown:
        return onBoard && state.showdown != null && state.showdown!.bf == o.loc;
      case SelfKind.inCombat:
        return onBoard && state.showdown != null && state.showdown!.combat && state.showdown!.bf == o.loc;
      case SelfKind.notDamagedThisTurn:
        return _gen.get('o$id:damaged') == 0;
      case SelfKind.exactlyOneOtherHere:
        return onBoard && unitsAt(o.loc, player: o.controller).length == 2;
      case SelfKind.movedTwice:
        return _gen.get('o$id:moves') >= 2;
    }
  }

  /// A passive's condition, for its source.
  bool _genPassiveCond(Cond c, ObjId src) {
    final o = state.obj(src);
    return _cond(c, _Ctx(controller: o.controller, source: src, loc: o.loc, targets: const []));
  }

  // -------------------------------------------------------------------------------------------
  // Matching (query.dart's matches and matching call these)
  // -------------------------------------------------------------------------------------------

  /// The location an object in a slot names: a battlefield's index, a unit's location, or base.
  int? _genSlotLoc(int? slot, List<int>? slots) {
    if (slot == null || slots == null || slot >= slots.length) return null;
    final v = slots[slot];
    if (v == 0) return base;
    if (v < 0) return null;
    final o = state.objOrNull(v);
    if (o == null) return null;
    if (o.zone == Zone.battlefield) return state.bfs.indexWhere((b) => b.obj == v);
    return o.zone == Zone.board ? o.loc : null;
  }

  bool _genMatches(Filter f, ObjId id, Obj o, RCard c, {required int controller, ObjId? source, int here = base, List<int>? slots}) {
    if (f.tags.isNotEmpty && !f.tags.any(c.hasTag)) return false;
    if (f.domain != null && !c.domains.contains(f.domain)) return false;
    if (f.token != null && c.token != f.token) return false;
    if (f.notTag != null && c.hasTag(f.notTag!)) return false;
    if (f.stunned != null && o.stunned != f.stunned) return false;
    if (f.damaged != null && (o.damage > 0) != f.damaged) return false;
    if (f.mighty != null && (might(id) >= 5) != f.mighty) return false;
    if (f.withKw != null && !hasKw(id, f.withKw!)) return false;
    if (f.withoutKw != null && hasKw(id, f.withoutKw!)) return false;
    if (f.costMax != null && c.energy > f.costMax!) return false;
    if (f.lessMightThanMe) {
      if (source == null || state.objOrNull(source)?.zone != Zone.board || might(id) >= might(source)) return false;
    }
    if (f.inCombat) {
      final sd = state.showdown;
      if (sd == null || !sd.combat || o.loc != sd.bf) return false;
    }
    if (f.atSlot != null) {
      final l = _genSlotLoc(f.atSlot, slots);
      if (l == null || o.loc != l) return false;
    }
    if (f.myBf) {
      final s = source == null ? null : state.objOrNull(source);
      final at = s != null && s.zone == Zone.board ? s.loc : here;
      if (s == null || at == base || o.loc != at) return false;
    }
    return true;
  }

  /// Cards in a trash or hand matching [f] (owner: [Filter.side] relative to [controller]).
  bool _genMatchesCard(Filter f, ObjId id, {required int controller, ObjId? source}) {
    final o = state.obj(id);
    final want = f.zone == FZone.trash ? Zone.trash : Zone.hand;
    if (o.zone != want) return false;
    if (f.side == Side.friendly && o.owner != controller) return false;
    if (f.side == Side.enemy && o.owner == controller) return false;
    final c = card(id);
    if (!f.cardTypes.contains(c.type)) return false;
    if (f.tag != null && !c.hasTag(f.tag!)) return false;
    if (f.tags.isNotEmpty && !f.tags.any(c.hasTag)) return false;
    if (f.domain != null && !c.domains.contains(f.domain)) return false;
    if (f.notTag != null && c.hasTag(f.notTag!)) return false;
    if (f.mighty != null && ((c.might ?? 0) >= 5) != f.mighty) return false;
    if (f.costMax != null && c.energy > f.costMax!) return false;
    if (f.mightMax != null && (c.might ?? 0) > f.mightMax!) return false;
    if (f.other && id == source) return false;
    return true;
  }

  List<ObjId> _genMatching(Filter f, {required int controller, ObjId? source}) {
    final out = <ObjId>[];
    for (var q = 0; q < state.players.length; q++) {
      final pl = state.player(q);
      for (final id in f.zone == FZone.trash ? pl.trash : pl.hand) {
        if (_genMatchesCard(f, id, controller: controller, source: source)) out.add(id);
      }
    }
    return out;
  }

  // -------------------------------------------------------------------------------------------
  // Passives (CR 363)
  // -------------------------------------------------------------------------------------------

  /// Might from general passives, extra buffs and lasting effects, given Might [m] so far.
  int _genMight(ObjId id, int m) {
    if (!_genBusy.add(id)) return 0;
    try {
      final o = state.obj(id);
      var d = 0;
      final extraBuffs = _gen.getL('o$id:buffs');
      if (extraBuffs > 0) d += extraBuffs;
      int? floor;
      for (final (src, pa) in _passives()) {
        if (pa is! GenPassive) continue;
        final so = state.obj(src);
        switch (pa) {
          case GAnthem(:final filter, :final might, :final cond, :final mightFloor):
            if (might == 0) continue;
            if (cond != null && !_genPassiveCond(cond, src)) continue;
            if (!matches(filter, id, controller: so.controller, source: src, here: _genHereOf(src))) continue;
            d += might;
            if (mightFloor != null) floor = mightFloor;
          case SelfBoost(:final might, :final cond):
            if (src != id || might == null) continue;
            if (cond != null && !_genPassiveCond(cond, src)) continue;
            d += switch (might) {
              N(:final n) => n,
              GenAmount() => _genAmount(might, _Ctx(controller: so.controller, source: src, loc: so.loc, targets: const [])),
              _ => 0,
            };
          case Restrict(:final kind, :final n):
            if (kind == RKind.loneDefenderMinus && so.zone == Zone.battlefield) {
              final bf = state.bfs.indexWhere((b) => b.obj == src);
              if (o.loc == bf && isDefending(id) && unitsAt(bf, player: o.controller).length == 1) d -= n;
            }
          default:
            break;
        }
      }
      if (floor != null && m + d < floor && d < 0) {
        final total = m + d;
        if (total < floor) d = m > floor ? floor - m : (d < 0 ? 0 : d);
      }
      return d;
    } finally {
      _genBusy.remove(id);
    }
  }

  /// The location "here" means for a passive's source: a battlefield's own index, or where the
  /// permanent is.
  int _genHereOf(ObjId src) {
    final so = state.obj(src);
    if (so.zone == Zone.battlefield) return state.bfs.indexWhere((b) => b.obj == src);
    return so.loc;
  }

  /// Keyword value from general passives and lasting effects.
  int _genKw(ObjId id, Kw k) {
    var n = _gen.getL('o$id:kw${k.index}');
    if (!_genBusy.add(id)) return n;
    try {
      for (final (src, pa) in _passives()) {
        if (pa is! GenPassive) continue;
        final so = state.obj(src);
        switch (pa) {
          case GAnthem(:final filter, :final kws, :final cond, :final ifNotAlready):
            if (kws.isEmpty) continue;
            if (cond != null && !_genPassiveCond(cond, src)) continue;
            if (!matches(filter, id, controller: so.controller, source: src, here: _genHereOf(src))) continue;
            for (final (kw, v) in kws) {
              if (kw == k) n += ifNotAlready ? (parsed(id).kw(k) + (state.obj(id).kwMod[k.index] ?? 0) > 0 ? 0 : v) : v;
            }
          case SelfBoost(:final kws, :final cond, :final kwAmount):
            if (src != id) continue;
            if (cond != null && !_genPassiveCond(cond, src)) continue;
            for (final (kw, v) in kws) {
              if (kw == k) n += v;
            }
            if (kwAmount != null && kwAmount.$1 == k) n += _genAmount(kwAmount.$2 as GenAmount, _Ctx(controller: so.controller, source: src, loc: so.loc, targets: const []));
          default:
            break;
        }
      }
      return n;
    } finally {
      _genBusy.remove(id);
    }
  }

  /// Is a [RKind] restriction in effect from a passive matching [test]?
  bool _genRestricted(RKind k, {bool Function(ObjId src, Restrict r)? test}) {
    for (final (src, pa) in _passives()) {
      if (pa is Restrict && pa.kind == k && (pa.cond == null || _genPassiveCond(pa.cond!, src)) && (test == null || test(src, pa))) return true;
    }
    return false;
  }

  bool _genSelfRestricted(ObjId id, RKind k) {
    for (final a in parsed(id).abilities) {
      if (a is Static && a.passive is Restrict && (a.passive as Restrict).kind == k) return true;
    }
    return false;
  }

  /// May unit [u] move to [to] (move restrictions)?
  bool _genCantMoveTo(ObjId u, int to) {
    if (to != base) return false;
    if (_genSelfRestricted(u, RKind.cantMoveToBase)) return true;
    if (_genRestricted(RKind.noneMoveToBase)) return true;
    final from = state.obj(u).loc;
    if (from != base && _genRestricted(RKind.noneMoveFromHereToBase, test: (src, _) => _genHereOf(src) == from)) return true;
    return false;
  }

  List<int> _genMoveDests(ObjId u, List<int> dests) {
    if (_gen.getL('o$u:cantMove') > 0 || _gen.get('o$u:cantMove') > 0) return const [];
    return [
      for (final d in dests)
        if (!_genCantMoveTo(u, d)) d,
    ];
  }

  bool _genCanReady(ObjId id, int byPlayer) {
    final o = state.objOrNull(id);
    if (o == null) return false;
    if (o.zone == Zone.board && card(id).type == CardType.unit && _genSelfRestricted(id, RKind.cantBeReadied)) return false;
    if (o.zone == Zone.board && o.controller != byPlayer && _genRestricted(RKind.noReadyEnemies, test: (src, _) => state.obj(src).controller == byPlayer ? false : true)) {
      // "Spells and abilities can't ready enemy units and gear" (enemy to the restriction's controller).
    }
    for (final (src, pa) in _passives()) {
      if (pa is Restrict && pa.kind == RKind.noReadyEnemies && _genPassiveCond(const SelfCond(SelfKind.atBattlefield), src) && o.zone == Zone.board && o.controller != state.obj(src).controller) {
        return false;
      }
    }
    return true;
  }

  int _genVictoryScore() {
    var v = state.victoryScore;
    for (final (src, pa) in _passives()) {
      if (pa is Restrict && pa.kind == RKind.victoryPlus && state.obj(src).zone == Zone.battlefield) v += pa.n;
    }
    return v;
  }

  /// Energy cost changes from passives (CR 356).
  int _genEnergyCost(int p, RCard c, int e) {
    if (RiftboundParser.parse(c).abilities.any((a) => a is Static && a.passive is SelfCostByMight)) {
      var hi = 0;
      for (final u in units(player: p)) {
        final m = might(u);
        if (m > hi) hi = m;
      }
      e = e > hi ? e - hi : 0;
    }
    for (final (src, pa) in _passives()) {
      if (pa is! CostReduce) continue;
      final so = state.obj(src);
      if (so.controller != p) continue;
      if (pa.cond != null && !_genPassiveCond(pa.cond!, src)) continue;
      if (pa.spells ? c.type != CardType.spell : !(pa.filter != null && c.type == CardType.unit && (pa.filter!.tag == null || c.hasTag(pa.filter!.tag!)))) continue;
      if (e > pa.min) {
        e -= pa.n;
        if (e < pa.min) e = pa.min;
      }
    }
    return e;
  }

  // -------------------------------------------------------------------------------------------
  // Damage (CR 418, 438, 712)
  // -------------------------------------------------------------------------------------------

  /// Deals [n] to unit [id] from the spell or ability in [ctx] (or from [byUnit]); applies Bonus
  /// Damage and prevention. Returns the damage dealt.
  int _genDeal(ObjId id, int n, _Ctx ctx, {ObjId? byUnit}) {
    if (!isUnit(id)) return 0;
    final o = state.obj(id);
    final p = ctx.controller;
    var amt = n;
    if (byUnit == null && amt > 0) {
      // Bonus Damage (CR 712): "Your spells and abilities deal 1 Bonus Damage", "units here".
      for (final (src, pa) in _passives()) {
        if (pa is! Restrict) continue;
        if (pa.kind == RKind.bonusDamage && state.obj(src).controller == p) amt += pa.n;
        if (pa.kind == RKind.bonusDamageHere && _genHereOf(src) == o.loc && o.loc != base) amt += pa.n;
      }
      amt += ctx.scratch['bonus'] ?? 0;
    }
    if (amt <= 0) return 0;
    // Prevention (CR 438).
    if (byUnit == null) {
      for (final d in _gen.delayed) {
        if (d.kind == DelayKind.preventSpellDamage.index && d.turn == state.turn) return 0;
      }
      if (o.controller != p) {
        for (final a in parsed(id).abilities) {
          if (a is Static && a.passive is PreventEnemySpellDamage) {
            final c = (a.passive as PreventEnemySpellDamage).cond;
            if (c == null || _genPassiveCond(c, id)) {
              log('${nameOf(id)}: the damage is prevented.', card: id, kind: 'info');
              return 0;
            }
          }
        }
      }
    }
    for (var i = 0; i < _gen.delayed.length; i++) {
      final d = _gen.delayed[i];
      if (d.kind == DelayKind.preventNext.index && d.obj == id && d.turn == state.turn) {
        if (d.n == 0) {
          _gen.delayed.removeAt(i);
          log('${nameOf(id)}: the damage is prevented.', card: id, kind: 'info');
          return 0;
        }
        final stop = d.n < amt ? d.n : amt;
        amt -= stop;
        if (d.n - stop <= 0) {
          _gen.delayed.removeAt(i);
        } else {
          _gen.delayed[i] = d.withN(d.n - stop);
        }
        break;
      }
    }
    if (amt <= 0) return 0;
    o.damage += amt;
    ctx.scratch['lastHit'] = id;
    _gen.add('o$id:damaged');
    _genNoteHit(id, ctx, byUnit: byUnit);
    _genOnDamaged(id);
    return amt;
  }

  /// Who to credit if [id] dies of this damage (CR 429.5.c).
  void _genNoteHit(ObjId id, _Ctx ctx, {ObjId? byUnit}) {
    final spell = byUnit == null && state.objOrNull(ctx.source) != null && card(ctx.source).type == CardType.spell;
    _gen.setL('o$id:hitBy', ctx.controller + 1);
    _gen.setL('o$id:hitSpell', spell ? 1 : 0);
  }

  /// "When any unit takes damage this turn, kill it" / "Kill it the next time it takes damage".
  void _genOnDamaged(ObjId id) {
    for (var i = 0; i < _gen.delayed.length; i++) {
      final d = _gen.delayed[i];
      if (d.turn != state.turn) continue;
      if (d.kind == DelayKind.killDamaged.index || (d.kind == DelayKind.killNextDamage.index && d.obj == id)) {
        if (d.kind == DelayKind.killNextDamage.index) _gen.delayed.removeAt(i);
        _gen.add('o$id:killNow');
        return;
      }
    }
  }

  // -------------------------------------------------------------------------------------------
  // Effects
  // -------------------------------------------------------------------------------------------

  void _genResolve(GenEffect e, _Ctx ctx) {
    final p = ctx.controller;
    switch (e) {
      case ChooseOnly():
        break;
      case DealAmt(:final amount, :final target, :final source):
        final n = amount is N ? amount.n : (amount is GenAmount ? _genAmount(amount, ctx) : 0);
        final by = source == null ? null : _genFirst(source, ctx);
        if (source != null && (by == null || by < 0)) return;
        for (final id in _resolveTarget(target, ctx)) {
          final d = _genDeal(id, n, ctx, byUnit: by);
          if (d > 0) log('${nameOf(by ?? ctx.source)} deals $d to ${nameOf(id)}.', player: p, card: id, kind: 'damage', amount: d);
        }
      case ExceptDeal(:final n, :final filter, :final except):
        final skip = except < ctx.targets.length ? ctx.targets[except] : -1;
        for (final id in matching(filter, controller: p, source: ctx.source, here: ctx.loc, slots: ctx.targets)) {
          if (id == skip) continue;
          final d = _genDeal(id, n, ctx);
          if (d > 0) log('${nameOf(ctx.source)} deals $d to ${nameOf(id)}.', player: p, card: id, kind: 'damage', amount: d);
        }
      case DealOther(:final n, :final target, :final except):
        final skip = except < ctx.targets.length ? ctx.targets[except] : -1;
        for (final id in _resolveTarget(target, ctx)) {
          if (id == skip) continue;
          final d = _genDeal(id, n, ctx);
          if (d > 0) log('${nameOf(ctx.source)} deals $d to ${nameOf(id)}.', player: p, card: id, kind: 'damage', amount: d);
        }
      case Fight(:final a, :final b):
        final ua = _genFirst(a, ctx), ub = _genFirst(b, ctx);
        if (ua < 0 || ub < 0 || !isUnit(ua) || !isUnit(ub) || ua == ub) return;
        final ma = mightUsed(ua), mb = mightUsed(ub);
        final da = _genDeal(ub, ma, ctx, byUnit: ua);
        final db0 = _genDeal(ua, mb, ctx, byUnit: ub);
        log('${nameOf(ua)} and ${nameOf(ub)} deal $da and $db0 to each other.', player: p, card: ub, kind: 'damage', amount: da);
      case GiveMightAmt(:final amount, :final target, :final negative):
        final n = amount is N ? amount.n : (amount is GenAmount ? _genAmount(amount, ctx) : 0);
        for (final id in _resolveTarget(target, ctx)) {
          if (!isUnit(id)) continue;
          state.obj(id).mightMod += negative ? -n : n;
          log('${nameOf(id)} gets ${negative ? '-' : '+'}$n Might this turn.', player: p, card: id, kind: 'buff');
        }
      case DoubleMight(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          if (!isUnit(id)) continue;
          final m = might(id);
          state.obj(id).mightMod += m;
          log('${nameOf(id)}’s Might is doubled this turn.', player: p, card: id, kind: 'buff');
        }
      case GiveMany(:final target, :final might, :final kws):
        for (final id in _resolveTarget(target, ctx)) {
          if (!isUnit(id)) continue;
          final o = state.obj(id);
          o.mightMod += might;
          for (final (kw, v) in kws) {
            o.kwMod[kw.index] = (o.kwMod[kw.index] ?? 0) + v;
          }
          log(
            '${nameOf(id)} gets ${[if (might != 0) '${might > 0 ? '+' : ''}$might Might', for (final (kw, v) in kws) '${kwLabel(kw)}${v > 1 ? ' $v' : ''}'].join(' and ')} this turn.',
            player: p,
            card: id,
            kind: 'buff',
          );
        }
      case GiveKwLasting(:final kw, :final target):
        for (final id in _resolveTarget(target, ctx)) {
          if (state.objOrNull(id)?.zone != Zone.board) continue;
          _gen.setL('o$id:kw${kw.index}', 1);
          log('${nameOf(id)} gains ${kwLabel(kw)}.', player: p, card: id, kind: 'buff');
        }
      case Move(:final target, :final dest, :final destSlot, :final refSlot):
        for (final u in _resolveTarget(target, ctx)) {
          if (!isUnit(u)) continue;
          final o = state.obj(u);
          final to = switch (dest) {
            Dest.base => base,
            Dest.here => _genHereOfCtx(ctx),
            Dest.event => ctx.loc,
            Dest.slot => _genSlotLoc(refSlot, ctx.targets) ?? -9,
            _ => _genSlotLoc(destSlot, ctx.targets) ?? -9,
          };
          if (to == -9 || to == o.loc) continue;
          if (to != base && (to < 0 || to >= state.bfs.length)) continue;
          if (_genCantMoveTo(u, to)) continue;
          _moveUnits([u], to, p);
        }
      case Banish(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          log('${nameOf(id)} is banished.', player: p, card: id, kind: 'die');
          _genBanish(id);
        }
      case CardToHand(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          final o = state.obj(id);
          if (o.zone != Zone.trash) continue;
          state.player(o.owner).trash.remove(id);
          o.zone = Zone.hand;
          state.player(o.owner).hand.add(id);
          log('${nameOf(id)} returns to ${playerName(o.owner)}’s hand.', player: o.owner, card: id, kind: 'draw');
        }
      case DrawAmt(:final amount, :final who):
        final n = amount is N ? amount.n : (amount is GenAmount ? _genAmount(amount, ctx) : 0);
        for (final q in _genPlayers(who, ctx)) {
          _draw(q, n);
        }
      case DiscardP(:final n, :final who, :final hand):
        for (final q in _genPlayers(who, ctx)) {
          _gen.turn.remove('p$q:lastDiscardCost');
          _genDiscard(q, hand ? state.player(q).hand.length : n, ctx.source);
        }
      case ChannelP(:final n, :final who, :final exhausted, :final elseDraw):
        for (final q in _genPlayers(who, ctx)) {
          final before = state.player(q).runes.length;
          _channel(q, n, exhausted: exhausted);
          if (elseDraw > 0 && state.player(q).runes.length - before < n) _draw(q, elseDraw);
        }
      case ScoreP(:final n, :final who, :final win):
        for (final q in _genPlayers(who, ctx)) {
          if (win) {
            log('${playerName(q)} wins the game.', player: q, kind: 'win');
            _win(q);
            return;
          }
          _genGainPoints(q, n);
        }
      case TokenP(:final token, :final count, :final who, :final ready, :final where):
        for (final q in _genPlayers(who, ctx)) {
          final src = state.objOrNull(ctx.source);
          final loc = switch (where) {
            TokenAt.here => src != null && src.zone == Zone.board ? src.loc : base,
            TokenAt.event => ctx.loc >= 0 && ctx.loc < state.bfs.length ? ctx.loc : base,
            _ => base,
          };
          _genTokens(q, token, count, loc, ready: ready);
        }
      case LookTop():
        _genLookTop(e, ctx);
      case RevealTop(:final filter, :final yes, :final no):
        final deck = state.player(p).deck;
        if (deck.isEmpty) return;
        final top = deck.first;
        log('${playerName(p)} reveals ${nameOf(top)}.', player: p, card: top, kind: 'info');
        final hit = filter.cardTypes.contains(card(top).type);
        final what = hit ? yes : no;
        deck.removeAt(0);
        switch (what) {
          case RevealDo.hand:
            state.obj(top).zone = Zone.hand;
            state.player(p).hand.add(top);
          case RevealDo.recycle:
            state.obj(top).zone = Zone.mainDeck;
            deck.add(top);
          case RevealDo.trash || RevealDo.trashAndMight2:
            state.obj(top).zone = Zone.trash;
            state.player(p).trash.add(top);
            if (what == RevealDo.trashAndMight2 && state.objOrNull(ctx.source)?.zone == Zone.board) state.obj(ctx.source).mightMod += 2;
        }
      case Mill(:final n, :final who):
        for (final q in _genPlayers(who, ctx)) {
          _genBurn(q, n);
        }
      case RecycleTrash(:final n):
        final trash = state.player(p).trash;
        if (trash.isEmpty) return;
        final k = n < trash.length ? n : trash.length;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Recycle $k from your trash', options: List.of(trash), min: k, max: k, source: ctx.source));
        _recycleCards(p, pick);
      case RecycleRune():
        final runes = state.player(p).runes;
        if (runes.isEmpty) return;
        final r = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Recycle one of your runes', options: List.of(runes), source: ctx.source)).first;
        _genRecycleRune(p, r);
      case EachKills(:final filter, :final keepOne):
        for (final q in _genPlayers(const PEach(), _Ctx(controller: state.active, source: ctx.source, loc: ctx.loc, targets: const []))) {
          final mine = [
            for (final id in state.objects.values)
              if (id.zone == Zone.board && id.controller == q && filter.cardTypes.contains(card(id.id).type)) id.id,
          ];
          if (mine.isEmpty) continue;
          final pick = ask(
            Decision(kind: DecisionKind.cards, player: q, prompt: keepOne ? 'Choose one to keep' : 'Kill one of your ${filter.gear ? 'gear' : 'units'}', options: mine, source: ctx.source),
          );
          final kill = keepOne
              ? [
                  for (final x in mine)
                    if (!pick.contains(x)) x,
                ]
              : pick;
          for (final id in kill) {
            log('${nameOf(id)} is killed.', player: q, card: id, kind: 'die');
            _kill(id);
          }
        }
      case PlayFrom(:final target, :final ignoreAll):
        for (final id in _resolveTarget(target, ctx)) {
          _genPlayCard(p, id, ignoreAll: ignoreAll, source: ctx.source);
        }
      case Blink(:final target, :final to):
        for (final id in _resolveTarget(target, ctx)) {
          final owner = state.obj(id).owner;
          _genBanish(id);
          if (state.obj(id).zone != Zone.banish) continue; // a token ceases to exist (CR 428)
          // Its owner plays it: to base or a battlefield they control, or as the text says.
          var opts = <int>[
            if (to != Dest.battlefield) base,
            if (to != Dest.base)
              for (var i = 0; i < state.bfs.length; i++)
                if (to == Dest.battlefield || state.bfs[i].controller == owner) i,
          ];
          opts = _genPlayLocs(owner, id, opts);
          if (opts.isEmpty) continue;
          final where = opts.length == 1
              ? opts.first
              : opts[ask(
                  Decision(
                    kind: DecisionKind.option,
                    player: owner,
                    prompt: 'Play ${nameOf(id)} where?',
                    labels: [for (final l in opts) l == base ? 'Base' : nameOf(state.bfs[l].obj)],
                    source: ctx.source,
                  ),
                ).first];
          _genPlayCard(owner, id, ignoreAll: true, source: ctx.source, fromBanish: true, loc: where);
        }
      case TakeControl(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          final o = state.obj(id);
          o.controller = p;
          o.loc = base;
          log('${playerName(p)} takes control of ${nameOf(id)} and recalls it.', player: p, card: id, kind: 'move');
        }
      case ToDeck(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          final o = state.obj(id);
          final owner = o.owner;
          final top =
              ask(Decision(kind: DecisionKind.option, player: owner, prompt: 'Put ${nameOf(id)} on the top or bottom of your Main Deck?', labels: const ['Top', 'Bottom'], source: ctx.source)).first ==
              0;
          _leaveBoard(id, toHand: false);
          final pl = state.player(owner);
          if (o.zone == Zone.trash) {
            pl.trash.remove(id);
            o.zone = Zone.mainDeck;
            if (top) {
              pl.deck.insert(0, id);
            } else {
              pl.deck.add(id);
            }
          }
          log('${nameOf(id)} goes to the ${top ? 'top' : 'bottom'} of ${playerName(owner)}’s deck.', player: owner, card: id, kind: 'move');
        }
      case ReadyAny(:final target, :final exhaust, :final either):
        for (final id in _resolveTarget(target, ctx)) {
          var ex = exhaust;
          if (either) ex = ask(Decision(kind: DecisionKind.option, player: p, prompt: '${nameOf(id)}: ready or exhaust?', labels: const ['Ready', 'Exhaust'], source: ctx.source)).first == 1;
          if (!ex && !_genCanReady(id, p)) continue;
          final was = state.obj(id).exhausted;
          state.obj(id).exhausted = ex;
          if (!ex && was && isUnit(id)) _genReadied(id, p);
        }
      case IfElse(:final cond, :final yes, :final no):
        for (final x in _cond(cond, ctx) ? yes : no) {
          _resolve(x, ctx);
        }
      case TrigIf(:final effects) || Seq(:final effects):
        for (final x in effects) {
          _resolve(x, ctx);
        }
      case PayTo():
        _genPayTo(e, ctx);
      case Repeat(:final times, :final effects):
        final n = times is N ? times.n : (times is GenAmount ? _genAmount(times, ctx) : 0);
        for (var i = 0; i < n; i++) {
          for (final x in effects) {
            _resolve(x, ctx);
          }
        }
      case Delay():
        _genAddDelay(e, ctx);
      case CounterIt():
        _genCounter(e, ctx);
      case SpendBuffs():
        final buffed = [
          for (final u in units(player: p))
            if (state.obj(u).buffed) u,
        ];
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Spend any number of buffs', options: buffed, min: 0, max: buffed.length, source: ctx.source));
        for (final u in pick) {
          _genSpendBuff(u, p);
        }
        ctx.scratch['that'] = pick.length;
      case ExtraTurn():
        _gen.setL('p$p:extraTurns', _gen.getL('p$p:extraTurns') + 1);
        log('${playerName(p)} will take another turn.', player: p, kind: 'turn');
      case UseOnly(:final effects):
        for (final x in effects) {
          _resolve(x, ctx);
        }
      case HandPick(:final filter, :final recycle):
        final q = state.other(p);
        final hand = state.player(q).hand;
        if (hand.isEmpty) return;
        log('${playerName(q)} reveals their hand: ${hand.map(nameOf).join(', ')}.', player: q, kind: 'info');
        final options = [
          for (final id in hand)
            if (filter == null || _genMatchesCard(filter, id, controller: q)) id,
        ];
        if (options.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose a card for ${playerName(q)} to ${recycle ? 'recycle' : 'discard'}', options: options, source: ctx.source)).first;
        if (recycle) {
          log('${playerName(q)} recycles ${nameOf(pick)}.', player: q, card: pick, kind: 'discard');
          _recycleCards(q, [pick]);
        } else {
          hand.remove(pick);
          state.obj(pick).zone = Zone.trash;
          state.player(q).trash.add(pick);
          log('${playerName(q)} discards ${nameOf(pick)}.', player: q, card: pick, kind: 'discard');
          _genDiscarded(q, [pick]);
        }
      case BanishThis():
        _gen.turn['banishThis:${ctx.source}'] = 1;
      case BonusPerName(:final n, :final effects):
        final name = card(ctx.source).name;
        final k = state.player(p).trash.where((id) => card(id).name == name).length;
        final was = ctx.scratch['bonus'] ?? 0;
        ctx.scratch['bonus'] = was + n * k;
        for (final x in effects) {
          _resolve(x, ctx);
        }
        ctx.scratch['bonus'] = was;
      case DealSplit(:final n, :final filter):
        final options = matching(filter, controller: p, source: ctx.source, here: ctx.loc, slots: ctx.targets);
        if (options.isEmpty) return;
        final split = <ObjId, int>{};
        for (var i = 0; i < n; i++) {
          final a = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: assign 1 damage (${n - i} left)', options: options, source: ctx.source)).first;
          split[a] = (split[a] ?? 0) + 1;
        }
        for (final id in options) {
          final k = split[id];
          if (k == null) continue;
          final d = _genDeal(id, k, ctx);
          if (d > 0) log('${nameOf(ctx.source)} deals $d to ${nameOf(id)}.', player: p, card: id, kind: 'damage', amount: d);
        }
      case EachKeep(:final filter):
        _genResolve(EachKills(filter, keepOne: true), ctx);
      case SpendBuffsToReady():
        final buffed = [
          for (final u in units(player: p))
            if (state.obj(u).buffed) u,
        ];
        if (buffed.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Spend buffs to ready which units?', options: buffed, min: 0, max: buffed.length, source: ctx.source));
        for (final u in pick) {
          _genSpendBuff(u, p);
          if (state.obj(u).exhausted && _genCanReady(u, p)) {
            state.obj(u).exhausted = false;
            _genReadied(u, p);
          }
        }
      case ActivateConquer():
        final bf = _genHereOfCtx(ctx);
        if (bf < 0 || bf >= state.bfs.length) return;
        for (final u in unitsAt(bf)) {
          _fireUnit(u, const {On.conquer});
          _genEvent(GEv.conquerOrHold, player: state.obj(u).controller, obj: u, loc: bf, extra: 'conquer');
        }
      case RecycleTrashes(:final n):
        final all = [for (var q = 0; q < state.players.length; q++) ...state.player(q).trash];
        if (all.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Recycle up to $n cards from trashes', options: all, min: 0, max: n < all.length ? n : all.length, source: ctx.source));
        for (var q = 0; q < state.players.length; q++) {
          final mine = [
            for (final id in pick)
              if (state.obj(id).owner == q) id,
          ];
          if (mine.isNotEmpty) _recycleCards(q, mine);
        }
      case CounteredToHand():
        final id = ctx.scratch['countered'] ?? -1;
        if (id <= 0) return;
        final o = state.obj(id);
        if (o.zone != Zone.trash) return;
        state.player(o.owner).trash.remove(id);
        o.zone = Zone.hand;
        state.player(o.owner).hand.add(id);
        log('${nameOf(id)} returns to ${playerName(o.owner)}’s hand.', player: o.owner, card: id, kind: 'draw');
      default:
        break;
    }
  }

  int _genHereOfCtx(_Ctx ctx) {
    final o = state.objOrNull(ctx.source);
    if (o == null) return ctx.loc;
    if (o.zone == Zone.battlefield) return state.bfs.indexWhere((b) => b.obj == ctx.source);
    return o.zone == Zone.board ? o.loc : ctx.loc;
  }

  void _genDiscard(int q, int n, ObjId source) {
    final hand = state.player(q).hand;
    if (hand.isEmpty || n <= 0) return;
    final k = n < hand.length ? n : hand.length;
    final pick = ask(Decision(kind: DecisionKind.cards, player: q, prompt: 'Discard $k', options: List.of(hand), min: k, max: k, source: source));
    for (final id in pick) {
      hand.remove(id);
      state.obj(id).zone = Zone.trash;
      state.player(q).trash.add(id);
    }
    log('${playerName(q)} discards ${pick.map(nameOf).join(', ')}.', player: q, kind: 'discard');
    _genDiscarded(q, pick);
  }

  /// After [q] discards [ids]: counts and triggers ("when you discard one or more cards").
  void _genDiscarded(int q, List<ObjId> ids) {
    if (ids.isEmpty) return;
    _gen.add('p$q:discarded', ids.length);
    _gen.turn['p$q:lastDiscardCost'] = card(ids.last).energy;
    _genEvent(GEv.discarded, player: q, obj: ids.first);
    for (final id in ids.skip(1)) {
      _genEvent(GEv.discarded, player: q, obj: id, extra: 'more');
    }
  }

  void _genGainPoints(int q, int n) {
    if (n <= 0) return;
    if (_genCantScore(q, -1)) return;
    state.player(q).points += n;
    log('${playerName(q)} gains $n point${n == 1 ? '' : 's'}.', player: q, kind: 'point', amount: n);
    _genEvent(GEv.oppScores, player: q);
  }

  /// "Opponents can't score points" (while the source is at a battlefield); "Players can't score
  /// here until their third turn".
  bool _genCantScore(int q, int bf) {
    for (final (src, pa) in _passives()) {
      if (pa is! Restrict) continue;
      final so = state.obj(src);
      if (pa.kind == RKind.oppCantScore && so.controller != q && so.zone == Zone.board && so.loc != base) return true;
      if (pa.kind == RKind.noScoreBeforeTurn3 && bf >= 0 && _genHereOf(src) == bf && _gen.getL('p$q:turns') < 3) return true;
    }
    return false;
  }

  void _genTokens(int q, String token, int count, int loc, {bool ready = false}) {
    if (db[token] == null) return;
    final rdy = ready || _genEntersReadyOthers(q, db[token]!);
    for (var i = 0; i < count; i++) {
      final id = _newObj(token, q, Zone.board);
      _enterBoard(id, q, loc, ready: rdy);
      _genEvent(GEv.played, player: q, obj: id);
    }
    log('${playerName(q)} plays $count $token token${count == 1 ? '' : 's'}.', player: q, kind: 'play');
  }

  /// Burn [n] (CR 441): the top cards to the trash; burning out when the deck runs out.
  void _genBurn(int q, int n) {
    final pl = state.player(q);
    for (var i = 0; i < n; i++) {
      if (pl.deck.isEmpty) {
        _burnOut(q);
        if (state.over || pl.deck.isEmpty) return;
      }
      final id = pl.deck.removeAt(0);
      state.obj(id).zone = Zone.trash;
      pl.trash.add(id);
    }
    log('${pl.name} burns $n.', player: q, kind: 'info', amount: n);
  }

  void _genRecycleRune(int q, ObjId r) {
    final pl = state.player(q);
    pl.runes.remove(r);
    state.obj(r)
      ..zone = Zone.runeDeck
      ..exhausted = false;
    pl.runeDeck.add(r);
    log('${pl.name} recycles a rune.', player: q, kind: 'channel');
    _genEvent(GEv.recycled, player: q, extra: 'rune');
  }

  /// Banish a permanent from the board (CR 428).
  void _genBanish(ObjId id) {
    final o = state.obj(id);
    if (o.zone == Zone.trash) {
      state.player(o.owner).trash.remove(id);
      o.zone = Zone.banish;
      state.player(o.owner).banish.add(id);
      return;
    }
    if (o.zone != Zone.board) return;
    _genLeaving(id);
    final c = card(id);
    o.reset();
    _gen.forget(id);
    if (c.token) {
      o.zone = Zone.gone;
      return;
    }
    o.zone = Zone.banish;
    state.player(o.owner).banish.add(id);
  }

  void _genSpendBuff(ObjId u, int p) {
    final o = state.obj(u);
    if (_gen.getL('o$u:buffs') > 0) {
      _gen.setL('o$u:buffs', _gen.getL('o$u:buffs') - 1);
    } else {
      o.buffed = false;
    }
    log('${playerName(p)} spends ${nameOf(u)}’s buff.', player: p, card: u, kind: 'buff');
    _genEvent(GEv.spentBuff, player: p, obj: u);
  }

  /// Plays card [id] (in a trash, banishment or the deck) for [p] without paying its Energy cost
  /// (or any cost, [ignoreAll]); units and gear go to base (CR 420.3).
  void _genPlayCard(int p, ObjId id, {required bool ignoreAll, required ObjId source, bool fromBanish = false, int loc = base}) {
    final o = state.obj(id);
    final c = card(id);
    if (!RiftboundParser.parse(c).supported) return;
    if (!ignoreAll && c.power > 0) {
      if (!_canPayCard(p, c, extraEnergy: -energyCost(p, c))) return;
      _pay(p, 0, _powerOf(c, c.power));
    }
    final pl = state.player(o.owner);
    pl.trash.remove(id);
    pl.banish.remove(id);
    pl.deck.remove(id);
    pl.hand.remove(id);
    pl.playedThisTurn++;
    if (c.type == CardType.spell) {
      o.zone = Zone.chain;
      final effects = [
        for (final a in RiftboundParser.parse(c).abilities)
          if (a is SpellBody) ...a.effects,
      ];
      final targets = _chooseTargets(effects, p, id, base, optional: true);
      log('${playerName(p)} plays ${c.name}.', player: p, card: id, kind: 'play');
      _pushChain(ChainItem(id: state.nextChainId++, source: id, card: c.key, ability: -1, controller: p, targets: targets));
      return;
    }
    final passives = [
      for (final a in RiftboundParser.parse(c).abilities)
        if (a is Static) a.passive,
    ];
    var ready = c.type == CardType.gear ? !passives.any((x) => x is EntersExhausted) : passives.any((x) => x is EntersReady);
    ready = _genEntersReady(p, id, ready);
    _enterBoard(id, p, loc, ready: ready);
    log('${playerName(p)} plays ${c.name}${loc == base ? '' : ' to ${nameOf(state.bfs[loc].obj)}'}.', player: p, card: id, kind: 'play');
    _firePlayed(id);
    if (c.type == CardType.unit) _fire(On.youPlayUnit, player: p);
    _genEvent(GEv.played, player: p, obj: id);
  }

  void _genLookTop(LookTop e, _Ctx ctx) {
    final p = ctx.controller;
    final deck = state.player(p).deck;
    final top = deck.take(e.n).toList();
    if (top.isEmpty) return;
    var picked = <ObjId>[];
    if (e.pick > 0) {
      final options = [
        for (final id in top)
          if (e.filter == null || e.filter!.cardTypes.contains(card(id).type)) id,
      ];
      final k = e.pick < options.length ? e.pick : options.length;
      if (k > 0) {
        picked = ask(
          Decision(
            kind: DecisionKind.cards,
            player: p,
            prompt: e.play ? 'Choose a card to play' : 'Choose ${k == 1 ? 'a card' : '$k cards'} to put into your hand',
            options: options,
            min: e.mayPick ? 0 : k,
            max: k,
            source: ctx.source,
          ),
        );
      }
    }
    for (final id in picked) {
      deck.remove(id);
      if (e.revealed) log('${playerName(p)} reveals ${nameOf(id)}.', player: p, card: id, kind: 'info');
      state.obj(id).zone = Zone.hand;
      state.player(p).hand.add(id);
    }
    final rest = [
      for (final id in top)
        if (!picked.contains(id)) id,
    ];
    for (final id in rest) {
      deck.remove(id);
    }
    switch (e.rest) {
      case Rest.recycle:
        state.rng.shuffle(rest);
        for (final id in rest) {
          deck.add(id);
        }
      case Rest.trash:
        for (final id in rest) {
          state.obj(id).zone = Zone.trash;
          state.player(p).trash.add(id);
        }
      case Rest.top:
        deck.insertAll(0, rest);
    }
    log('${playerName(p)} looks at ${top.length} card${top.length == 1 ? '' : 's'}${picked.isEmpty ? '' : ' and takes ${picked.length}'}.', player: p, kind: 'draw');
    if (rest.isNotEmpty && e.rest == Rest.recycle) _genEvent(GEv.recycled, player: p);
    if (picked.isNotEmpty && e.picked.isNotEmpty) {
      ctx.scratch['picked'] = 1;
      _genResolveLater(e.picked, ctx);
    }
  }

  /// Resolves [effects] whose choices are made now (reflexive and delayed parts).
  void _genResolveLater(List<Effect> effects, _Ctx ctx) {
    final t = _chooseTargets(effects, ctx.controller, ctx.source, ctx.loc, optional: true);
    final merged = List.of(ctx.targets);
    for (var i = 0; i < t.length; i++) {
      while (merged.length <= i) {
        merged.add(-1);
      }
      if (t[i] != -1 || merged[i] == -1) merged[i] = t[i];
    }
    final c2 = _Ctx(controller: ctx.controller, source: ctx.source, loc: ctx.loc, targets: merged, event: ctx.event, ability: ctx.ability);
    c2.scratch.addAll(ctx.scratch);
    for (final x in effects) {
      _resolve(x, c2);
    }
  }

  void _genPayTo(PayTo e, _Ctx ctx) {
    final p = ctx.controller;
    final src = state.objOrNull(ctx.source);
    // What can be paid?
    if (e.exhaustMe && (src == null || src.exhausted || !(src.zone == Zone.board || src.zone == Zone.legend))) return;
    if (!canPay(p, e.energy, e.power)) return;
    for (final x in e.parts) {
      switch (x.kind) {
        case CostKind.killMe:
          if (src == null || src.zone != Zone.board) return;
        case CostKind.discard:
          if (state.player(p).hand.length < x.n) return;
        case CostKind.spendBuff:
          if (!units(player: p).any((u) => state.obj(u).buffed)) return;
        case CostKind.killOne:
          if (matching(x.filter!, controller: p, source: ctx.source, here: ctx.loc).isEmpty) return;
        default:
          break;
      }
    }
    if (e.optional && !askYesNo(p, '${nameOf(ctx.source)}: ${e.describe().replaceFirst('may ', '')}?', source: ctx.source)) return;
    _pay(p, e.energy, e.power);
    _genSpent(p, e.energy + e.power.length, power: e.power.length);
    if (e.exhaustMe) src!.exhausted = true;
    for (final x in e.parts) {
      switch (x.kind) {
        case CostKind.killMe:
          ctx.scratch['lkMight'] = mightUsed(ctx.source);
          _kill(ctx.source);
        case CostKind.discard:
          _genDiscard(p, x.n, ctx.source);
        case CostKind.burn:
          _genBurn(p, x.n);
        case CostKind.spendBuff:
          final buffed = [
            for (final u in units(player: p))
              if (state.obj(u).buffed) u,
          ];
          final u = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Spend a buff', options: buffed, source: ctx.source)).first;
          _genSpendBuff(u, p);
        case CostKind.killOne:
          final options = matching(x.filter!, controller: p, source: ctx.source, here: ctx.loc);
          final u = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Kill one to pay', options: options, source: ctx.source)).first;
          ctx.scratch['lkMight'] = isUnit(u) ? mightUsed(u) : 0;
          log('${nameOf(u)} is killed.', player: p, card: u, kind: 'die');
          _kill(u);
        default:
          break;
      }
    }
    ctx.scratch['paid'] = 1;
    _genResolveLater(e.effects, ctx);
  }

  /// Energy and Power spent this turn (for "if you've spent …").
  void _genSpent(int p, int n, {int power = 0}) {
    if (n > 0) _gen.add('p$p:spent', n);
    if (power > 0) _gen.add('p$p:spentPower', power);
  }

  // -------------------------------------------------------------------------------------------
  // Countering (CR 426)
  // -------------------------------------------------------------------------------------------

  void _genCounter(CounterIt e, _Ctx ctx) {
    final t = e.target;
    if (t is! ChooseSpell || t.slot >= ctx.targets.length) return;
    final ref = ctx.targets[t.slot];
    if (ref < _chainRef) return;
    final i = state.chain.indexWhere((it) => it.id == ref - _chainRef);
    if (i < 0) return;
    final it = state.chain[i];
    ctx.scratch['counteredCtl'] = it.controller;
    if (it.isSpell && _genCantBeCountered(it.source)) {
      log('${db[it.card]!.name} can’t be countered.', player: ctx.controller, kind: 'info');
      return;
    }
    if (e.unlessPay > 0 && canPay(it.controller, e.unlessPay, const [])) {
      if (askYesNo(it.controller, 'Pay {${e.unlessPay}} so ${db[it.card]!.name} isn’t countered?', source: ctx.source)) {
        _pay(it.controller, e.unlessPay, const []);
        log('${playerName(it.controller)} pays {${e.unlessPay}}.', player: it.controller, kind: 'info');
        return;
      }
    }
    state.chain.removeAt(i);
    if (it.isSpell) {
      final o = state.obj(it.source)..zone = Zone.trash;
      state.player(o.owner).trash.add(it.source);
      ctx.scratch['countered'] = it.source;
    }
    log('${db[it.card]!.name}${it.isSpell ? '' : '’s ability'} is countered.', player: ctx.controller, kind: 'info');
  }

  /// "This can't be countered."
  bool _genCantBeCountered(ObjId id) => parsed(id).abilities.any((a) => a is Static && a.passive is CantBeCountered);

  // -------------------------------------------------------------------------------------------
  // Delayed abilities (CR 390–393)
  // -------------------------------------------------------------------------------------------

  /// Where [target] sits in the effects of ability [ability] of [card]: indexes into nested lists.
  List<int>? _genPath(List<Effect> root, Effect target) {
    List<int>? walk(List<Effect> es, List<int> at) {
      for (var i = 0; i < es.length; i++) {
        final e = es[i];
        if (identical(e, target)) return [...at, i];
        final kids = switch (e) {
          May(:final effects) || If(:final effects) => [effects],
          Modes(:final modes) => modes,
          GenEffect() => e.nested,
          _ => const <List<Effect>>[],
        };
        for (var k = 0; k < kids.length; k++) {
          final r = walk(kids[k], [...at, i, k]);
          if (r != null) return r;
        }
      }
      return null;
    }

    return walk(root, const []);
  }

  List<Effect> _genRootEffects(String cardKey, int ability) {
    final abs = RiftboundParser.parse(db[cardKey]!).abilities;
    if (ability < 0) {
      return [
        for (final a in abs)
          if (a is SpellBody) ...a.effects,
      ];
    }
    if (ability >= abs.length) return const [];
    return switch (abs[ability]) {
      Triggered(:final effects) || Activated(:final effects) => effects,
      _ => const [],
    };
  }

  Effect? _genAt(List<Effect> root, List<int> path) {
    var es = root;
    Effect? e;
    for (var i = 0; i < path.length; i++) {
      if (path[i] >= es.length) return null;
      e = es[path[i]];
      if (i + 1 < path.length) {
        final kids = switch (e) {
          May(:final effects) || If(:final effects) => [effects],
          Modes(:final modes) => modes,
          GenEffect() => e.nested,
          _ => const <List<Effect>>[],
        };
        i++;
        if (path[i] >= kids.length) return null;
        es = kids[path[i]];
      }
    }
    return e;
  }

  void _genAddDelay(Delay e, _Ctx ctx) {
    final o = state.objOrNull(ctx.source);
    final cardKey = o?.card ?? '';
    final path = cardKey.isEmpty ? null : _genPath(_genRootEffects(cardKey, ctx.ability), e);
    final objs = e.target == null ? <ObjId>[e.kind == DelayKind.noSpells && e.n == 1 ? (ctx.scratch['counteredCtl'] ?? -1) : -1] : _resolveTarget(e.target!, ctx);
    for (final id in objs) {
      _gen.delayed.add(
        Delayed(
          kind: e.kind.index,
          controller: ctx.controller,
          source: ctx.source,
          card: cardKey,
          ability: ctx.ability,
          path: path ?? const [],
          targets: List.of(ctx.targets),
          obj: id,
          n: e.n,
          turn: state.turn,
          loc: ctx.loc,
        ),
      );
    }
  }

  /// Runs a delayed trigger's effects.
  void _genRunDelayed(Delayed d, {int event = -1, int? lkMight}) {
    final e = d.card.isEmpty ? null : _genAt(_genRootEffects(d.card, d.ability), d.path);
    if (e is! Delay) return;
    final ctx = _Ctx(controller: d.controller, source: d.source, loc: d.loc, targets: d.targets, event: event, ability: d.ability);
    if (lkMight != null) ctx.scratch['lkMight'] = lkMight;
    _genResolveLater(e.effects, ctx);
  }

  /// "At the end of this turn, …" delayed triggers (CR 317).
  void _genEndOfTurn() {
    for (final d in List.of(_gen.delayed)) {
      if (d.kind == DelayKind.atEndOfTurn.index && d.turn == state.turn) {
        _gen.delayed.remove(d);
        _genRunDelayed(d);
      }
    }
  }

  /// Expiration (CR 317.2): "this turn" delayed abilities end.
  void _genExpire() {
    _gen.delayed = [
      for (final d in _gen.delayed)
        if (d.kind == DelayKind.atNextMain.index || d.turn != state.turn) d,
    ];
  }

  /// A turn begins for [p]: per-turn counters reset, and [p]'s turns are counted.
  void _genNewTurn(int p) {
    _gen.turn = {};
    _gen.setL('p$p:turns', _gen.getL('p$p:turns') + 1);
  }

  /// "At the start of your Main Phase" triggers and delayed abilities.
  void _genMainStart(int p) {
    _genEvent(GEv.startOfMain, player: p);
    for (final d in List.of(_gen.delayed)) {
      if (d.kind == DelayKind.atNextMain.index && d.controller == p && d.turn < state.turn) {
        _gen.delayed.remove(d);
        _genRunDelayed(d);
      }
    }
  }

  /// Who takes the next turn: [p] again for an extra turn ("Take a turn after this one").
  int _genNextPlayer(int p) {
    final n = _gen.getL('p$p:extraTurns');
    if (n > 0) {
      _gen.setL('p$p:extraTurns', n - 1);
      return p;
    }
    return state.other(p);
  }

  /// A permanent entered the board: whether it's Mighty is noted silently (entering isn't
  /// "becoming" Mighty, CR 709).
  void _genEntered(ObjId id) {
    if (card(id).type == CardType.unit && might(id) >= 5) _gen.setL('o$id:mighty', 1);
  }

  /// A spell was put on the chain by [p] (chain item [itemId]) after spending [spent].
  void _genSpellCast(int p, int itemId, int spent) {
    if (spent > _gen.get('p$p:maxSpell')) _gen.turn['p$p:maxSpell'] = spent;
    _gen.add('p$p:cast');
    _gen.turn['spent:$itemId'] = spent;
    final i = _gen.delayed.indexWhere((d) => d.controller == p && d.turn == state.turn && d.kind == DelayKind.nextSpellBonus.index);
    if (i >= 0) {
      _gen.turn['bonus:$itemId'] = _gen.delayed[i].n;
      _gen.delayed.removeAt(i);
    }
  }

  void _genBeforeResolve(ChainItem item, _Ctx ctx) {
    if (item.isSpell) {
      _gen.turn['p${item.controller}:resolvingSpent'] = _gen.get('spent:${item.id}');
      final b = _gen.get('bonus:${item.id}');
      if (b > 0) ctx.scratch['bonus'] = b;
    }
  }

  /// A spell finished resolving: playing it is complete (CR 420.4).
  void _genSpellDone(ChainItem item) {
    if (_gen.get('banishThis:${item.source}') > 0) {
      _gen.turn.remove('banishThis:${item.source}');
      final o = state.obj(item.source);
      if (o.zone == Zone.trash) {
        state.player(o.owner).trash.remove(item.source);
        o.zone = Zone.banish;
        state.player(o.owner).banish.add(item.source);
        log('${nameOf(item.source)} is banished.', player: item.controller, card: item.source, kind: 'info');
      }
    }
    _gen.add('p${item.controller}:spells');
    _genEvent(GEv.spellPlayed, player: item.controller, obj: item.source);
    _genEvent(GEv.anySpell, player: item.controller, obj: item.source);
    _genEvent(GEv.played, player: item.controller, obj: item.source);
  }

  /// Units moved from [from] to [to] (by [byPlayer]'s action).
  void _genMoved(List<ObjId> moving, List<int> from, int to, int byPlayer) {
    for (var k = 0; k < moving.length; k++) {
      _gen.add('o${moving[k]}:moves');
      _genEvent(GEv.moved, player: byPlayer, obj: moving[k], from: from[k], loc: to);
    }
    if (to != base && moving.isNotEmpty) _genEvent(GEv.oppMoves, player: state.obj(moving.first).controller, obj: moving.first, loc: to);
  }

  /// A triggered ability's own condition (CR 383.2.a.1), checked as it triggers.
  bool _genTriggerOk(ObjId src, int index, int controller, int loc, int event) {
    final abs = parsed(src).abilities;
    if (index < 0 || index >= abs.length) return true;
    final a = abs[index];
    if (a is! Triggered || a.effects.length != 1 || a.effects.first is! TrigIf) return true;
    final t = a.effects.first as TrigIf;
    return _cond(t.cond, _Ctx(controller: controller, source: src, loc: loc, targets: const [], event: event, ability: index));
  }

  /// How many times a unit's Deathknell triggers ("Your [Deathknell] effects trigger an additional time").
  int _genDeathknellTimes(ObjId id) {
    final ctl = state.obj(id).controller;
    var n = 1;
    for (final (src, pa) in _passives()) {
      if (pa is Restrict && pa.kind == RKind.deathknellTwice && state.obj(src).controller == ctl && src != id) n++;
    }
    return n;
  }

  /// Combat begins at battlefield [bf]: attacker [att] with [mine] against [theirs].
  void _genCombatStart(int bf, int att, List<ObjId> mine, List<ObjId> theirs) {
    final def = state.other(att);
    _gen.turn.removeWhere((k, _) => k.startsWith('att:'));
    _gen.turn['combat'] = bf + 1;
    _gen.turn.remove('p$att:excess');
    _gen.turn.remove('p$def:excess');
    for (final u in mine) {
      _gen.turn['att:$u'] = 1;
    }
    _genEvent(GEv.defendAnywhere, player: def, loc: bf);
    _genEvent(GEv.combatHere, player: att, loc: bf);
    _genEvent(GEv.defend, player: def, loc: bf);
    if (mine.length == 1) _genEvent(GEv.aloneInCombat, player: att, obj: mine.first, loc: bf);
    if (theirs.length == 1) _genEvent(GEv.aloneInCombat, player: def, obj: theirs.first, loc: bf);
  }

  /// After [p] conquers or holds [bf]: general triggers, and "trigger an additional time".
  void _genScored(int p, int bf, bool conquer, int waitingBefore) {
    _genEvent(GEv.conquerOrHold, player: p, loc: bf);
    for (final u in unitsAt(bf, player: p)) {
      _genEvent(GEv.conquerOrHold, player: p, obj: u, loc: bf);
    }
    final twice = _genRestricted(
      conquer ? RKind.conquerTwiceHere : RKind.holdTwiceHere,
      test: (src, _) => state.obj(src).controller == p && state.obj(src).zone == Zone.board && state.obj(src).loc == bf,
    );
    if (twice) {
      final fresh = state.waiting.sublist(waitingBefore);
      state.waiting.addAll(fresh);
    }
  }

  /// Excess combat damage [p] assigns (CR 467.2.c.4): beyond lethal damage to every unit.
  void _genNoteExcess(int p, int amount, List<ObjId> targets) {
    var need = 0;
    for (final u in targets) {
      final m = might(u);
      final n = (m > 0 ? m : 1) - state.obj(u).damage;
      need += n < 1 ? 1 : n;
    }
    if (amount > need) _gen.turn['p$p:excess'] = amount - need;
  }

  /// Runes [p] recycled while paying (CR 164): "When you recycle a rune".
  void _genRunesRecycled(int p, int n) {
    for (var i = 0; i < n; i++) {
      _genEvent(GEv.recycled, player: p, extra: 'rune');
    }
  }

  /// "I don't deal combat damage unless I'm at a battlefield with exactly one other unit you control".
  bool _genDealsCombatDamage(ObjId u) {
    if (!_genSelfRestricted(u, RKind.noCombatDamageUnless)) return true;
    final o = state.obj(u);
    return o.loc != base && unitsAt(o.loc, player: o.controller).length == 2;
  }

  /// "You ignore [Tank] while assigning combat damage here".
  bool _genIgnoresTank(int p, int bf) => _genRestricted(RKind.ignoreTankHere, test: (src, _) => state.obj(src).controller == p && state.obj(src).zone == Zone.board && state.obj(src).loc == bf);

  /// Combat damage to [id] (CR 467), through prevention (CR 438.5).
  int _genCombatHit(ObjId id, int n) {
    final ctx = _Ctx(controller: state.other(state.obj(id).controller), source: id, loc: state.obj(id).loc, targets: const []);
    return _genDeal(id, n, ctx, byUnit: 0);
  }

  /// A unit about to die: replacement effects (CR 367). Returns true if the death is replaced.
  bool _genReplaceDeath(ObjId id) {
    for (var i = 0; i < _gen.delayed.length; i++) {
      final d = _gen.delayed[i];
      if (d.obj != id || d.turn != state.turn) continue;
      if (d.kind == DelayKind.saveNextDeath.index) {
        _gen.delayed.removeAt(i);
        final o = state.obj(id);
        if (d.n > 0) o.damage = 0;
        o
          ..exhausted = true
          ..loc = base;
        log('${nameOf(id)} is ${d.n > 0 ? 'healed, ' : ''}exhausted and recalled instead of dying.', player: o.controller, card: id, kind: 'move');
        return true;
      }
      if (d.kind == DelayKind.banishIfDies.index) {
        _gen.delayed.removeAt(i);
        log('${nameOf(id)} is banished instead.', player: d.controller, card: id, kind: 'die');
        _genBanish(id);
        return true;
      }
    }
    return false;
  }

  // -------------------------------------------------------------------------------------------
  // Events: general triggers (GenWhen)
  // -------------------------------------------------------------------------------------------

  /// Is [w] a trigger that also fires for core event [on]?
  bool _genAlsoOn(When w, On on) => w is GenWhen && w.alsoOn.contains(on);

  /// Fires the general triggers listening for [ev]. [player]: whose action it is; [obj]: the
  /// object it's about; [loc]: where.
  void _genEvent(GEv ev, {required int player, int obj = -1, int loc = -2, String extra = '', int from = -2}) {
    // A showdown without combat: no combat facts for the conquer it may bring.
    if (ev == GEv.showdownHere) _gen.turn.remove('combat');
    if (_probe) return;
    final sources = <ObjId>[];
    for (var q = 0; q < state.players.length; q++) {
      final pl = state.player(q);
      if (pl.legend != null) sources.add(pl.legend!);
    }
    for (final o in state.objects.values) {
      if (o.zone == Zone.board || o.zone == Zone.battlefield) sources.add(o.id);
    }
    if (ev == GEv.dies || ev == GEv.leaves || ev == GEv.discarded) {
      if (obj > 0 && !sources.contains(obj)) sources.add(obj);
    }
    for (final src in sources) {
      final so = state.obj(src);
      final abs = parsed(src).abilities;
      for (var i = 0; i < abs.length; i++) {
        final a = abs[i];
        if (a is! Triggered || a.on is! GenWhen) continue;
        final w = a.on as GenWhen;
        if (w.ev != ev && !(ev == GEv.readied && w.ev == GEv.chosen && w.extra.contains('orReady'))) continue;
        final isBf = so.zone == Zone.battlefield;
        final bfIndex = isBf ? state.bfs.indexWhere((b) => b.obj == src) : -1;
        // Whose trigger it is: a battlefield's belongs to the player it's about.
        final ctl = isBf ? player : (so.zone == Zone.trash ? so.owner : so.controller);
        if (!isBf && so.zone != Zone.board && so.zone != Zone.legend && !(src == obj && (ev == GEv.dies || ev == GEv.leaves || ev == GEv.discarded))) continue;
        if (!_genWhenMatches(w, src, ctl, ev, player: player, obj: obj, loc: loc, extra: extra, from: from, bfIndex: bfIndex)) continue;
        if (w.limit > 0) {
          final k = 't:$src:$i';
          if (_gen.get(k) >= w.limit) continue;
          _gen.add(k);
        }
        if (w.extra.contains('once')) {
          final k = 'once:$src:$i:${ev.index}:${state.log.length}';
          if (_gen.get(k) > 0) continue;
          _gen.add(k);
        }
        final evLoc = w.extra.contains('fromLoc') ? from : (loc != -2 ? loc : (isBf ? bfIndex : so.loc));
        _queue(src, i, ctl, loc: isBf ? bfIndex : evLoc, event: obj);
      }
    }
  }

  bool _genWhenMatches(GenWhen w, ObjId src, int ctl, GEv ev, {required int player, required int obj, required int loc, required String extra, required int from, required int bfIndex}) {
    final so = state.obj(src);
    switch (w.by) {
      case Side.friendly:
        if (player != ctl) return false;
      case Side.enemy:
        if (player == ctl) return false;
      case Side.any:
        break;
    }
    if (w.self && obj != src) return false;
    if (ev == GEv.discarded && extra == 'more' && !w.self) return false;
    if (ev == GEv.recycled && extra == 'rune' && !w.extra.contains('rune')) return false;
    if (ev == GEv.conquerOrHold && extra == 'conquer' && !w.self) return false;
    if (w.filter != null) {
      if (obj < 0) return false;
      final f = w.filter!;
      final oo = state.objOrNull(obj);
      if (oo == null) return false;
      if (oo.zone == Zone.board) {
        if (!matches(f, obj, controller: ctl, source: src, here: bfIndex >= 0 ? bfIndex : so.loc)) return false;
      } else {
        // It left the board (died): check what it was.
        if (!_genMatchedAsItWas(f, obj, ctl, src)) return false;
      }
    }
    if (w.here) {
      final at = bfIndex >= 0 ? bfIndex : so.loc;
      final where = loc != -2 ? loc : (obj > 0 && state.objOrNull(obj)?.zone == Zone.board ? state.obj(obj).loc : -3);
      if (where != at) return false;
    }
    if (w.oppTurn && state.active == ctl) return false;
    if (ev == GEv.oppMoves && (so.zone != Zone.board || loc == so.loc)) return false;
    // A player's conquer or hold isn't one of their units' ("When you conquer or hold").
    if (ev == GEv.conquerOrHold && !w.self && obj != -1) return false;
    if (w.inShowdown && state.showdown == null) return false;
    if (w.firstOnly && _gen.getL('p$player:turns') != 1) return false;
    if (w.nth > 0) {
      final count = switch (ev) {
        GEv.moved => _gen.get('o$obj:moves'),
        GEv.played => state.player(player).playedThisTurn,
        _ => 0,
      };
      if (count != w.nth) return false;
    }
    for (final x in w.extra) {
      switch (x) {
        case 'meAtBf':
          if (so.zone != Zone.board || so.loc == base) return false;
        case 'fromBf':
          if (from < 0) return false;
        case 'fromHere':
          if (bfIndex < 0 || from != bfIndex) return false;
        case 'byYou':
          if (player != ctl) return false;
        case 'spell':
          if (extra != 'spell') return false;
        case 'rune':
          if (extra != 'rune') return false;
        case 'attackOrDefendAlone':
          if (obj < 0 || state.objOrNull(obj)?.zone != Zone.board || unitsAt(state.obj(obj).loc, player: state.obj(obj).controller).length != 1) return false;
        default:
          break;
      }
    }
    return true;
  }

  /// Did the object that just left the board match [f] as it last existed?
  bool _genMatchedAsItWas(Filter f, ObjId id, int ctl, ObjId src) {
    final wasCtl = _gen.getL('lk:$id:ctl') - 1;
    if (f.side == Side.friendly && wasCtl != ctl) return false;
    if (f.side == Side.enemy && wasCtl == ctl) return false;
    if (f.other && id == src) return false;
    final c = card(id);
    if (!f.cardTypes.contains(c.type)) return false;
    if (f.buffed == true && _gen.getL('lk:$id:buffed') == 0) return false;
    if (f.stunned == true && _gen.getL('lk:$id:stunned') == 0) return false;
    if (f.notTag != null && c.hasTag(f.notTag!)) return false;
    if (f.tag != null && !c.hasTag(f.tag!)) return false;
    if (f.where == Where.here) {
      final s = state.obj(src);
      final at = s.zone == Zone.battlefield ? state.bfs.indexWhere((b) => b.obj == src) : s.loc;
      if (_gen.getL('lk:$id:loc') - 2 != at) return false;
    }
    return true;
  }

  // -------------------------------------------------------------------------------------------
  // Hooks from the core
  // -------------------------------------------------------------------------------------------

  /// A permanent is about to leave the board: note what it was, and "when this leaves" triggers.
  void _genLeaving(ObjId id) {
    final o = state.obj(id);
    _gen.setL('lk:$id:ctl', o.controller + 1);
    _gen.setL('lk:$id:buffed', o.buffed ? 1 : 0);
    _gen.setL('lk:$id:stunned', o.stunned ? 1 : 0);
    _gen.setL('lk:$id:loc', o.loc + 2);
    _gen.setL('lk:$id:might', isUnit(id) ? mightUsed(id) + 1 : 0);
    _gen.setL('lk:$id:alone', isUnit(id) && unitsAt(o.loc, player: o.controller).length == 1 ? 1 : 0);
    _gen.setL('lk:$id:hitBy', _gen.getL('o$id:hitBy'));
    _gen.setL('lk:$id:hitSpell', _gen.getL('o$id:hitSpell'));
    _genEvent(GEv.leaves, player: o.controller, obj: id);
  }

  /// A unit died: counts, triggers and "when it dies this turn" delayed abilities.
  void _genDied(ObjId id) {
    final ctl = _gen.getL('lk:$id:ctl') - 1;
    _gen.add('unitDied');
    if (state.step == Step.beginning && ctl == state.active) _gen.add('p$ctl:diedBeginning');
    _genEvent(GEv.dies, player: ctl, obj: id);
    final hitBy = _gen.getL('lk:$id:hitBy') - 1;
    if (hitBy >= 0) _genEvent(GEv.youKill, player: hitBy, obj: id, extra: _gen.getL('lk:$id:hitSpell') > 0 ? 'spell' : '');
    for (final d in List.of(_gen.delayed)) {
      if (d.kind == DelayKind.whenDies.index && d.obj == id && d.turn == state.turn) {
        _gen.delayed.remove(d);
        _genRunDelayed(d, event: id, lkMight: _gen.getL('lk:$id:might') - 1);
      }
    }
  }

  /// "I enter ready if …", "Other friendly units enter ready", "Units you play this turn enter ready".
  bool _genEntersReady(int p, ObjId id, bool ready) {
    if (ready) return true;
    final c = card(id);
    for (final a in parsed(id).abilities) {
      if (a is Static && a.passive is EnterReady) {
        final er = a.passive as EnterReady;
        if (er.others == null && (er.cond == null || _cond(er.cond!, _Ctx(controller: p, source: id, loc: base, targets: const [])))) return true;
      }
    }
    if (c.type == CardType.unit) {
      for (final d in _gen.delayed) {
        if (d.controller == p && d.turn == state.turn && d.kind == DelayKind.unitsEnterReady.index) return true;
      }
      final i = _gen.delayed.indexWhere((d) => d.controller == p && d.turn == state.turn && d.kind == DelayKind.nextUnitReady.index);
      if (i >= 0) {
        _gen.delayed.removeAt(i);
        return true;
      }
    }
    return _genEntersReadyOthers(p, c);
  }

  bool _genEntersReadyOthers(int p, RCard c) {
    for (final (src, pa) in _passives()) {
      if (pa is! EnterReady || pa.others == null || state.obj(src).controller != p || state.obj(src).zone != Zone.board) continue;
      final f = pa.others!;
      if (!f.cardTypes.contains(c.type)) continue;
      if (f.token != null && c.token != f.token) continue;
      return true;
    }
    return false;
  }

  /// Why [p] can't play [id] now (play restrictions), or null.
  String? _genPlayProblem(int p, ObjId id) {
    if (_genSelfRestricted(id, RKind.notBeforeTurn4) && _gen.getL('p$p:turns') < 4) return 'Not before your fourth turn';
    for (final d in _gen.delayed) {
      if (d.turn != state.turn) continue;
      if (d.kind == DelayKind.noSpells.index && d.n == 1) {
        if (d.obj == p && card(id).type == CardType.spell) return 'You can’t play spells this turn';
        continue;
      }
      if (d.controller == p) continue;
      if (d.kind == DelayKind.noCards.index) return 'Opponents can’t play cards this turn';
      if (d.kind == DelayKind.noSpells.index && card(id).type == CardType.spell) return 'You can’t play spells this turn';
    }
    return null;
  }

  /// Where [p] may play unit [id] (CR 355.2), after restrictions.
  List<int> _genPlayLocs(int p, ObjId id, List<int> options) {
    if (_genSelfRestricted(id, RKind.onlyToConquered)) {
      return [
        for (final l in options)
          if (l != base && _gen.get('p$p:conquered$l') > 0) l,
      ];
    }
    final out = <int>[];
    for (final l in options) {
      if (l != base && _genRestricted(RKind.noPlayHere, test: (src, _) => _genHereOf(src) == l)) continue;
      if (l != base) {
        var blocked = false;
        for (final (src, pa) in _passives()) {
          if (pa is Restrict && pa.kind == RKind.oppUnitsOnlyToBase && state.obj(src).controller != p && state.obj(src).zone == Zone.board && state.obj(src).loc != base) blocked = true;
        }
        if (blocked) continue;
      }
      out.add(l);
    }
    return out;
  }

  /// An activated ability's own restrictions ("Use my abilities only while I'm at a battlefield"),
  /// and whether its extra costs can be paid.
  String? _genActivateProblem(Activated a, ObjId src, int p) {
    final o = state.obj(src);
    if (a.effects.isNotEmpty && a.effects.first is UseOnly) {
      final u = a.effects.first as UseOnly;
      if (!_cond(u.cond, _Ctx(controller: p, source: src, loc: o.loc, targets: const []))) return 'Not now';
      if (u.once && o.usedThisTurn.contains(parsed(src).abilities.indexOf(a))) return 'Only once each turn';
    }
    if (_genSelfRestricted(src, RKind.abilitiesOnlyAtBf) && (o.zone != Zone.board || o.loc == base)) return 'Only while it’s at a battlefield';
    for (final x in a.cost.extra) {
      switch (x) {
        case DiscardCost(:final n, :final filter):
          final hand = state.player(p).hand;
          final ok = filter == null ? hand.length : hand.where((id) => filter.cardTypes.contains(card(id).type)).length;
          if (ok < n) return 'Not enough cards to discard';
        case RecycleTrashCost(:final n, :final filter):
          final trash = state.player(p).trash;
          final ok = filter == null ? trash.length : trash.where((id) => filter.cardTypes.contains(card(id).type)).length;
          if (ok < n) return 'Not enough cards in your trash';
        case KillCost(:final filter):
          if (matching(filter, controller: p, source: src).isEmpty) return 'Nothing to kill';
        case ExhaustCost(:final filter):
          if (matching(filter.copyWith(exhausted: false), controller: p, source: src).isEmpty) return 'Nothing to exhaust';
        case SpendMyBuffCost():
          if (!o.buffed && _gen.getL('o$src:buffs') == 0) return 'No buff to spend';
        default:
          break;
      }
    }
    return null;
  }

  /// Pays an activated ability's extra costs (after its targets are chosen).
  void _genPayExtra(Activated a, ObjId src, int p, List<int> targets) {
    for (final x in a.cost.extra) {
      switch (x) {
        case DiscardCost(:final n, :final filter):
          final hand = [
            for (final id in state.player(p).hand)
              if (filter == null || filter.cardTypes.contains(card(id).type)) id,
          ];
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Discard $n to pay', options: hand, min: n, max: n, source: src));
          for (final id in pick) {
            state.player(p).hand.remove(id);
            state.obj(id).zone = Zone.trash;
            state.player(p).trash.add(id);
          }
          log('${playerName(p)} discards ${pick.map(nameOf).join(', ')}.', player: p, kind: 'discard');
          _genDiscarded(p, pick);
        case RecycleTrashCost(:final n, :final filter):
          final trash = [
            for (final id in state.player(p).trash)
              if (filter == null || filter.cardTypes.contains(card(id).type)) id,
          ];
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Recycle $n from your trash to pay', options: trash, min: n, max: n, source: src));
          _recycleCards(p, pick);
        case KillCost(:final filter):
          final options = matching(filter, controller: p, source: src);
          final u = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Kill one to pay', options: options, source: src)).first;
          log('${nameOf(u)} is killed.', player: p, card: u, kind: 'die');
          _kill(u);
        case ExhaustCost(:final filter):
          final options = matching(filter.copyWith(exhausted: false), controller: p, source: src);
          final u = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Exhaust one to pay', options: options, source: src)).first;
          state.obj(u).exhausted = true;
        case SpendMyBuffCost():
          _genSpendBuff(src, p);
        default:
          break;
      }
    }
  }

  /// "When I become ready" / "When you ready a friendly unit".
  void _genReadied(ObjId id, int byPlayer) {
    _genEvent(GEv.readied, player: byPlayer, obj: id);
  }

  /// A unit was buffed by [p].
  void _genBuffed(ObjId id, int p) => _genEvent(GEv.buffed, player: p, obj: id);

  /// Units [p]'s spell or ability chose (targeting effects, CR 383.4.b).
  void _genChosen(List<int> chosen, int p, ObjId source) {
    if (_probe) return;
    final spell = state.objOrNull(source) != null && card(source).type == CardType.spell;
    for (final id in chosen.toSet()) {
      if (id <= 0 || id >= _chainRef || state.objOrNull(id)?.zone != Zone.board) continue;
      _gen.add('p$p:chose');
      if (state.obj(id).controller != p) _gen.add('p$p:choseEnemy');
      _genEvent(GEv.chosen, player: p, obj: id, extra: spell ? 'spell' : '');
    }
  }

  /// Cleanup step additions: deaths from "kill it when it takes damage", "becomes Mighty".
  bool _genCleanup() {
    var changed = false;
    for (final o in state.objects.values.toList()) {
      if (o.zone != Zone.board) continue;
      final id = o.id;
      if (_gen.get('o$id:killNow') > 0) {
        _gen.turn.remove('o$id:killNow');
        log('${nameOf(id)} is killed.', player: o.controller, card: id, kind: 'die');
        _kill(id);
        changed = true;
        continue;
      }
      if (card(id).type != CardType.unit) continue;
      final mighty = might(id) >= 5;
      final was = _gen.getL('o$id:mighty') > 0;
      if (mighty != was) {
        _gen.setL('o$id:mighty', mighty ? 1 : 0);
        if (mighty) _genEvent(GEv.becomesMighty, player: o.controller, obj: id);
      }
    }
    return changed;
  }

  /// Is unit [id] killed by this damage (CR 142.4; "any amount of your damage is enough")?
  bool _genLethal(ObjId id) {
    final o = state.obj(id);
    if (o.damage <= 0) return false;
    if (o.damage >= might(id)) return true;
    final by = _gen.getL('o$id:hitBy') - 1;
    if (by >= 0 && by != o.controller) {
      for (final (src, pa) in _passives()) {
        if (pa is Restrict && pa.kind == RKind.anyDamageKills && state.obj(src).controller == by) return true;
      }
    }
    return false;
  }
}
