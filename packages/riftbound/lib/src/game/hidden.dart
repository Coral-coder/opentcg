part of 'game.dart';

/// What a resolving effect hands to the next one in the same text: the token it just made ("ready
/// it") and where moved units came from ("that battlefield"). It lives only while one move is
/// carried out (re-running the move re-creates it), so it isn't part of the state.
class _HScratch {
  ObjId? lastMade;
  final Map<ObjId, int> origins = {};
}

final _scratch = Expando<_HScratch>();

/// Hidden (CR 811, 422), Ambush (CR 822) and the cards around them: hiding and playing from
/// facedown, more places to play units, moving enemy units, control changes, and passives that
/// change Might, keywords, damage, readying and choosing. The rest of the engine calls the
/// `_h…` hooks here.
extension GameHidden on Game {
  _HScratch get _hs => _scratch[this] ??= _HScratch();

  /// Marks that last until the end of the turn start with "t:" (CR 317.2).
  bool _hMarked(String key) => state.marks.containsKey(key);

  /// Passives of permanents [p] controls and of their legend.
  Iterable<(ObjId, HPassive)> _hPassivesOf(int? p) sync* {
    for (final (src, passive) in _passives()) {
      if (passive is HPassive && (p == null || state.obj(src).controller == p)) yield (src, passive);
    }
  }

  bool _hHas(ObjId id, bool Function(HPassive) test) => parsed(id).abilities.any((a) => a is Static && a.passive is HPassive && test(a.passive as HPassive));

  // -------------------------------------------------------------------------------------------
  // Hiding (CR 422, 811.1.b)
  // -------------------------------------------------------------------------------------------

  /// Battlefields [p] controls with an empty Facedown Zone (CR 107.3.b: one card each).
  List<int> hideSpots(int p) => [
        for (var i = 0; i < state.bfs.length; i++)
          if (state.bfs[i].controller == p && facedownAt(i) == null) i,
      ];

  /// The card facedown at battlefield [bf], if any.
  ObjId? facedownAt(int bf) {
    for (final o in state.objects.values) {
      if (o.zone == Zone.facedown && o.loc == bf) return o.id;
    }
    return null;
  }

  /// "On your turn during an Open State" (CR 811.1.b): your turn, no chain, and either your Main
  /// Phase or a showdown where you hold Focus.
  bool _hHideTiming(int p) {
    if (state.over || state.phase != Phase.main || state.active != p || state.chain.isNotEmpty) return false;
    final sd = state.showdown;
    return sd == null ? state.step == Step.main : sd.focus == p;
  }

  /// What hiding costs [p]: nothing (an effect says so), {A}, or {N} with Teemo's legend.
  List<(int, List<Domain?>)> _hHideCosts(int p) {
    if (_hMarked('t:freeHide:$p')) return const [(0, <Domain?>[])];
    final out = <(int, List<Domain?>)>[(0, const <Domain?>[null])];
    for (final (_, passive) in _hPassivesOf(p)) {
      if (passive is HideForEnergy) out.add((passive.n, const <Domain?>[]));
    }
    return out;
  }

  void _hide(int p, ObjId id) {
    final pl = state.player(p);
    final o = state.objOrNull(id);
    if (o == null || o.owner != p || !(pl.hand.contains(id) || pl.champion == id)) throw RiftboundError('That card isn’t in your hand');
    final pc = parsed(id);
    if (!pc.supported) throw RiftboundError('${nameOf(id)} isn’t supported yet');
    if (!pc.has(Kw.hidden)) throw RiftboundError('Only cards with Hidden can be hidden');
    if (!_hHideTiming(p)) throw RiftboundError('Hide on your turn, with nothing on the chain');
    final spots = hideSpots(p);
    if (spots.isEmpty) throw RiftboundError('You need a battlefield you control with no facedown card');
    final costs = [for (final c in _hHideCosts(p)) if (canPay(p, c.$1, c.$2)) c];
    if (costs.isEmpty) throw RiftboundError('Hiding costs {A}');
    final cost = costs.length == 1
        ? costs.first
        : costs[ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Pay how to hide ${nameOf(id)}?', labels: [for (final c in costs) c.$1 > 0 ? '{${c.$1}}' : (c.$2.isEmpty ? 'Nothing' : '{A}')], source: id)).first];
    final bf = spots.length == 1 ? spots.first : spots[ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Hide ${nameOf(id)} at which battlefield?', labels: [for (final i in spots) nameOf(state.bfs[i].obj)], source: id)).first];
    _pay(p, cost.$1, cost.$2);
    pl.hand.remove(id);
    if (pl.champion == id) pl.champion = null;
    o
      ..reset()
      ..zone = Zone.facedown
      ..loc = bf
      ..controller = p
      ..enteredTurn = state.turn;
    log('${pl.name} hides a card at ${nameOf(state.bfs[bf].obj)}.', player: p, kind: 'play');
  }

  /// Why [p] can't play facedown card [o] now, or null (CR 811.1.b, 811.6).
  String? _hFacedownProblem(int p, Obj o) {
    if (o.controller != p) return 'That card isn’t yours';
    if (o.enteredTurn >= state.turn) return 'A hidden card can be played from the next turn on';
    // "Your opponents' [Hidden] cards can't be revealed here."
    for (final (src, passive) in _hPassivesOf(state.other(p))) {
      if (passive is NoRevealHere && state.obj(src).zone == Zone.board && state.obj(src).loc == o.loc) return '${nameOf(src)} stops facedown cards there';
    }
    return null;
  }

  /// Facedown cards at battlefields their controller no longer controls go to the trash
  /// (CR 323.6.a, 468.5.c). True if any did.
  bool _hCleanup() {
    var changed = false;
    for (final o in state.objects.values.toList()) {
      if (o.zone != Zone.facedown) continue;
      if (state.bfs[o.loc].controller == o.controller) continue;
      log('${playerName(o.controller)}’s facedown ${nameOf(o.id)} is revealed and trashed.', player: o.controller, card: o.id, kind: 'die');
      o
        ..reset()
        ..zone = Zone.trash;
      state.player(o.owner).trash.add(o.id);
      changed = true;
    }
    return changed;
  }

  /// After a card is played from facedown: its "played from [Hidden]" triggers and "when you
  /// play a card from [Hidden]".
  void _hPlayedFromHidden(ObjId id, int p) {
    if (state.obj(id).zone == Zone.board) {
      final abs = parsed(id).abilities;
      for (var i = 0; i < abs.length; i++) {
        final a = abs[i];
        if (a is Triggered && a.on.on == On.playedFaceDown) _queue(id, i, p);
      }
    }
    _fire(On.youPlayFromHidden, player: p);
  }

  /// Moves worth trying for [seat]: playing facedown cards, hiding cards with Hidden.
  List<RMove> _hCandidates(int seat) {
    final out = <RMove>[];
    for (final o in state.objects.values) {
      if (o.zone == Zone.facedown && o.controller == seat) out.add(PlayMove(seat, o.id));
    }
    if (_hHideTiming(seat) && hideSpots(seat).isNotEmpty) {
      final pl = state.player(seat);
      for (final id in [...pl.hand, ?pl.champion]) {
        if (parsed(id).has(Kw.hidden)) out.add(HideMove(seat, id));
      }
    }
    return out;
  }

  // -------------------------------------------------------------------------------------------
  // Where units may be played (CR 355.2.a, 813.3.a, 822)
  // -------------------------------------------------------------------------------------------

  /// Can [p] play [id] only because Ambush gives it Reaction (CR 822.1.b)?
  bool _hAmbushTiming(int p, ObjId id) => parsed(id).has(Kw.ambush) && _timingProblem(p, Timing.reaction) == null && _hAmbushPlaces(p, id).isNotEmpty;

  /// Battlefields Ambush lets [id] be played to: where [p] controls units, and with "I can be
  /// played to a battlefield where there are enemy units", there too (CR 822.1.d).
  List<int> _hAmbushPlaces(int p, ObjId id) {
    final enemyToo = _hHas(id, (x) => x is PlayTo && x.place == PlayPlace.enemyUnits);
    return [
      for (var i = 0; i < state.bfs.length; i++)
        if (unitsAt(i, player: p).isNotEmpty || (enemyToo && unitsAt(i, player: state.other(p)).isNotEmpty)) i,
    ];
  }

  /// Where [p] may play unit [id]: base and battlefields they control (CR 355.2.a), plus what
  /// its abilities and theirs allow. With [ambushOnly], only Ambush's places (it's being played
  /// as a Reaction). [extra]: a battlefield a cost opened up ("You may play me to its
  /// battlefield").
  List<int> _hDestinations(int p, ObjId id, {bool ambushOnly = false, int extra = base}) {
    if (ambushOnly) return _hAmbushPlaces(p, id);
    final out = <int>{base};
    final opp = state.other(p);
    bool has(PlayPlace place) => _hHas(id, (x) => x is PlayTo && x.place == place);
    final toOpen = has(PlayPlace.open) || _hPassivesOf(p).any((e) => e.$2 is FriendlyToOpen);
    for (var i = 0; i < state.bfs.length; i++) {
      final b = state.bfs[i];
      final mine = unitsAt(i, player: p), theirs = unitsAt(i, player: opp);
      final sd = state.showdown;
      if (b.controller == p) out.add(i);
      if (parsed(id).has(Kw.ambush) && (mine.isNotEmpty || (has(PlayPlace.enemyUnits) && theirs.isNotEmpty))) out.add(i);
      // Open: unoccupied and uncontrolled (CR 170.11.c).
      if (toOpen && b.controller == null && mine.isEmpty && theirs.isEmpty) out.add(i);
      if (has(PlayPlace.occupiedEnemy) && b.controller == opp && theirs.isNotEmpty) out.add(i);
      if (has(PlayPlace.attacking) && sd != null && sd.combat && sd.bf == i && sd.attacker == p) out.add(i);
      if (extra == i) out.add(i);
    }
    out.addAll(_powerDestinations(p, id));
    return out.toList()..sortStable((a, b) => a - b);
  }

  /// Timing a permanent is played with: [Reaction] on the card itself (CR 813.1.c.1).
  Timing _hPermanentTiming(ParsedCard pc) => pc.has(Kw.reaction) ? Timing.reaction : Timing.normal;

  // -------------------------------------------------------------------------------------------
  // Additional costs (CR 356.3)
  // -------------------------------------------------------------------------------------------

  /// Asks for [id]'s additional costs and returns what they add: Energy and Power to pay, a unit
  /// to kill, and whether one was paid. Throws if a mandatory one can't be.
  ({int energy, List<Domain?> power, ObjId? kill, bool paid}) _hExtraCost(int p, ObjId id, {bool free = false}) {
    for (final a in parsed(id).abilities) {
      if (a is! Static || a.passive is! ExtraCost) continue;
      final x = a.passive as ExtraCost;
      final cost = x.cost;
      if (x.exhaustLegend) {
        final legend = state.player(p).legend;
        if (legend != null && !state.obj(legend).exhausted && askYesNo(p, 'Exhaust your legend to play ${nameOf(id)} with its extra effect?', source: id)) {
          state.obj(legend).exhausted = true;
          return (energy: 0, power: const <Domain?>[], kill: null, paid: true);
        }
      } else if (cost != null) {
        if (_canPayCard(p, card(id), extraEnergy: cost.energy, extraPower: cost.power, free: free) && askYesNo(p, 'Pay ${cost.describe()} more to play ${nameOf(id)}?', source: id)) {
          return (energy: cost.energy, power: cost.power, kill: null, paid: true);
        }
        if (!x.optional) throw RiftboundError('${nameOf(id)} needs its additional cost');
      } else if (x.killTags.isNotEmpty) {
        final options = [
          for (final u in units(player: p))
            if (x.killTags.any(card(u).hasTag)) u,
        ];
        if (options.isEmpty) throw RiftboundError('${nameOf(id)} needs a ${x.killTags.join(', ')} of yours to kill');
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Kill a ${x.killTags.join('/')} to play ${nameOf(id)}', options: options, source: id)).first;
        return (energy: 0, power: const [], kill: pick, paid: true);
      }
    }
    return (energy: 0, power: const [], kill: null, paid: false);
  }

  // -------------------------------------------------------------------------------------------
  // Choosing (CR 355.5–355.10, 811.1.d)
  // -------------------------------------------------------------------------------------------

  /// Options for one of this file's targets as it's chosen, its slot, and whether it may be left
  /// empty; null if it isn't chosen. [chosen] are the choices so far, by slot.
  ({List<int> options, int slot, bool upTo, String prompt})? _hOptions(HTarget t, int p, ObjId source, int loc, List<int> chosen) {
    switch (t) {
      case ChooseBf(:final slot, :final mine, :final withFriendlyUnits):
        return (
          options: [
            for (var i = 0; i < state.bfs.length; i++)
              if ((!mine || state.bfs[i].controller == p) && (!withFriendlyUnits || unitsAt(i, player: p).isNotEmpty)) state.bfs[i].obj,
          ],
          slot: slot,
          upTo: false,
          prompt: 'choose a battlefield',
        );
      case ChooseRel(:final filter, :final slot, :final rel, :final same):
        final relId = rel < chosen.length ? chosen[rel] : -1;
        if (relId < 0) return (options: const [], slot: slot, upTo: false, prompt: '');
        final relLoc = state.obj(relId).zone == Zone.battlefield ? state.obj(relId).loc : state.obj(relId).loc;
        final relBase = state.obj(relId).zone == Zone.board && relLoc == base ? state.obj(relId).controller : null;
        bool sameLoc(ObjId u) => state.obj(u).loc == relLoc && (relLoc != base || state.obj(u).controller == relBase);
        return (
          options: [
            for (final u in matching(filter, controller: p, source: source, here: loc))
              if (u != relId && sameLoc(u) == same) u,
          ],
          slot: slot,
          upTo: false,
          prompt: 'choose ${filter.describe()} ${same ? 'at the same place' : 'somewhere else'}',
        );
      case ChooseOwnCard(:final slot):
        return (
          options: [
            for (final o in state.objects.values)
              if (o.id != source && o.controller == p && (o.zone == Zone.facedown || (o.zone == Zone.board && (card(o.id).type == CardType.unit || card(o.id).type == CardType.gear)))) o.id,
          ],
          slot: slot,
          upTo: false,
          prompt: 'choose a card to return to hand',
        );
      case LastMade():
        return null;
    }
  }

  /// Narrows options as they're chosen by [p]: things enemies can't choose (CR 355.6), and a
  /// card played from facedown at [restrictBf] choosing there (CR 811.1.d.2–811.1.d.4) unless
  /// [t] itself rules that out.
  List<int> _hNarrow(List<int> options, Target t, int p, int restrictBf) {
    var out = [for (final id in options) if (_hChooseable(id, p)) id];
    if (restrictBf >= 0) {
      final free = switch (t) {
        Choose(:final filter) => filter.where == Where.base || filter.where == Where.elsewhere,
        ChooseRel(:final same) => !same,
        ChooseOwnCard() => true,
        _ => false,
      };
      if (!free) {
        out = [
          for (final id in out)
            if (state.obj(id).zone == Zone.battlefield ? state.obj(id).loc == restrictBf : state.obj(id).loc == restrictBf) id,
        ];
      }
    }
    return out;
  }

  /// May [chooser] choose [id] (CR 355.6)? Not if it can't be chosen by enemy spells and
  /// abilities.
  bool _hChooseable(ObjId id, int chooser) {
    final o = state.objOrNull(id);
    if (o == null || o.zone != Zone.board || o.controller == chooser || !isUnit(id)) return true;
    for (final a in parsed(id).abilities) {
      if (a is Static && a.passive is CantBeChosen && _gateOk(id, a.gate)) {
        final c = a.passive as CantBeChosen;
        final sd = state.showdown;
        final inCombat = sd != null && sd.combat && sd.bf == o.loc;
        if (!(c.unlessInCombat && inCombat)) return false;
      }
    }
    for (final (src, passive) in _hPassivesOf(o.controller)) {
      if (passive is ShieldsWeakerHere && src != id && state.obj(src).zone == Zone.board && state.obj(src).loc == o.loc && might(id) < might(src)) return false;
    }
    return true;
  }

  /// The battlefield a card was played from facedown at, for its play effects' choices
  /// (CR 811.1.d.3), or -1.
  int _hPlayRestriction(ChainItem t) {
    final a = parsed(t.source).abilities[t.ability];
    if (a is! Triggered || (a.on.on != On.played && a.on.on != On.playedFaceDown)) return -1;
    return state.marks['t:fdplay:${t.source}'] ?? -1;
  }

  /// Are all the mandatory choices of [effects] possible for [p] right now?
  bool _hHasTargets(List<Effect> effects, int p, ObjId source) {
    for (final e in effects) {
      if (e is May || (e is HEffect && e.optional)) continue;
      final ts = e is HEffect ? e.choices : [?_targetOf(e)];
      for (final t in ts) {
        if (t is Choose && !t.upTo && matching(t.filter, controller: p, source: source).where((id) => _hChooseable(id, p)).isEmpty) return false;
      }
    }
    return true;
  }

  List<ObjId> _hResolveTarget(HTarget t, _Ctx ctx) {
    switch (t) {
      case ChooseBf(:final slot):
        final id = slot < ctx.targets.length ? ctx.targets[slot] : -1;
        return id >= 0 && state.objOrNull(id)?.zone == Zone.battlefield ? [id] : const [];
      case ChooseRel(:final slot, :final filter):
        final id = slot < ctx.targets.length ? ctx.targets[slot] : -1;
        return id >= 0 && matches(filter, id, controller: ctx.controller, source: ctx.source, here: ctx.loc) ? [id] : const [];
      case ChooseOwnCard(:final slot):
        final id = slot < ctx.targets.length ? ctx.targets[slot] : -1;
        final z = id < 0 ? null : state.objOrNull(id)?.zone;
        return z == Zone.board || z == Zone.facedown ? [id] : const [];
      case LastMade():
        final id = _hs.lastMade;
        return id != null && state.objOrNull(id)?.zone == Zone.board ? [id] : const [];
    }
  }

  // -------------------------------------------------------------------------------------------
  // Effects
  // -------------------------------------------------------------------------------------------

  /// Damage [id] would be dealt, after "double all damage that would be dealt to it this turn".
  int _hDamage(ObjId id, int n) => _hMarked('t:double:$id') ? n * 2 : n;

  void _hDeal(ObjId id, int n, _Ctx ctx) {
    if (!isUnit(id) || n <= 0) return;
    final d = _genDeal(id, n, ctx);
    if (d > 0) log('${nameOf(ctx.source)} deals $d to ${nameOf(id)}.', player: ctx.controller, card: id, kind: 'damage', amount: d);
  }

  int _bfIndex(ObjId bfObj) => state.obj(bfObj).loc;

  void _hResolve(HEffect e, _Ctx ctx) {
    final p = ctx.controller;
    switch (e) {
      case Pick():
        break;
      case MoveTo(:final target, :final dest, :final bfSlot):
        for (final id in _resolveTarget(target, ctx)) {
          if (!isUnit(id)) continue;
          final o = state.obj(id);
          final from = o.loc;
          final List<int> options;
          switch (dest) {
            case MoveDest.anywhere:
              options = [if (from != base) base, for (var i = 0; i < state.bfs.length; i++) if (i != from) i];
            case MoveDest.myLocation:
              final src = state.objOrNull(ctx.source);
              options = [if (src != null && src.zone == Zone.board && src.loc != from) src.loc];
            case MoveDest.sameController:
              options = [
                if (from != base && unitsAt(base, player: o.controller).isNotEmpty) base,
                for (var i = 0; i < state.bfs.length; i++)
                  if (i != from && unitsAt(i, player: o.controller).isNotEmpty) i,
              ];
            case MoveDest.chosenBf:
              final b = bfSlot < ctx.targets.length ? ctx.targets[bfSlot] : -1;
              options = [if (b >= 0 && _bfIndex(b) != from) _bfIndex(b)];
            case MoveDest.base:
              options = [if (from != base) base];
            case MoveDest.weakerEnemyBf:
              final opp = state.other(o.controller);
              options = [
                for (var i = 0; i < state.bfs.length; i++)
                  if (i != from && state.bfs[i].controller == opp && unitsAt(i, player: opp).isNotEmpty && mightUsed(id) > unitsAt(i, player: opp).fold<int>(0, (t, u) => t + mightUsed(u))) i,
              ];
          }
          if (options.isEmpty) continue;
          final to = options.length == 1 ? options.first : options[ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Move ${nameOf(id)} where?', labels: [for (final l in options) l == base ? '${playerName(o.controller)}’s base' : nameOf(state.bfs[l].obj)], source: ctx.source)).first];
          _hs.origins[id] = from;
          _moveUnits([id], to, p);
        }
      case SwapPlaces(:final a, :final b, :final needTemporary):
        final ra = _resolveTarget(a, ctx), rb = _resolveTarget(b, ctx);
        if (ra.isEmpty || rb.isEmpty) break;
        final x = ra.first, y = rb.first;
        if (!isUnit(x) || !isUnit(y) || x == y) break;
        if (needTemporary && !hasKw(x, Kw.temporary) && !hasKw(y, Kw.temporary)) break;
        final lx = state.obj(x).loc, ly = state.obj(y).loc;
        if (lx == ly) break;
        _moveUnits([x], ly, p);
        _moveUnits([y], lx, p);
      case FightAtDest(:final moved):
        final m = _resolveTarget(moved, ctx);
        if (m.isEmpty || !isUnit(m.first)) break;
        final a = m.first;
        final options = [
          for (final u in unitsAt(state.obj(a).loc))
            if (u != a && state.obj(u).controller != p && (state.obj(a).loc != base || state.obj(u).controller == state.obj(a).controller)) u,
        ];
        if (options.isEmpty) break;
        final b = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: choose another enemy unit there', options: options, source: ctx.source)).first;
        final ma = mightUsed(a), mb = mightUsed(b);
        _hDeal(b, ma, ctx);
        _hDeal(a, mb, ctx);
      case AnyToBase(:final bf):
        final r = _resolveTarget(bf, ctx);
        if (r.isEmpty) break;
        final options = unitsAt(_bfIndex(r.first), player: p);
        if (options.isEmpty) break;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Move which of your units there to base?', options: options, min: 0, max: options.length, source: ctx.source));
        if (pick.isNotEmpty) _moveUnits(pick, base, p);
      case KillTotal(:final bf, :final total):
        final r = _resolveTarget(bf, ctx);
        if (r.isEmpty) break;
        final at = _bfIndex(r.first);
        final picked = <ObjId>[];
        var left = total;
        while (true) {
          final options = [for (final u in unitsAt(at)) if (!picked.contains(u) && mightUsed(u) <= left) u];
          if (options.isEmpty) break;
          final a = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Kill another unit there (total Might $left or less left)?', options: options, min: 0, max: 1, source: ctx.source));
          if (a.isEmpty) break;
          picked.add(a.first);
          left -= mightUsed(a.first);
        }
        for (final u in picked) {
          log('${nameOf(u)} is killed.', player: p, card: u, kind: 'die');
          _kill(u);
        }
      case ControllerDraws(:final slot, :final n):
        final id = slot < ctx.targets.length ? ctx.targets[slot] : -1;
        final o = id < 0 ? null : state.objOrNull(id);
        if (o == null) break;
        _draw(o.zone == Zone.board ? o.controller : o.owner, n);
      case DealOr(:final n, :final attacking, :final target):
        for (final id in _resolveTarget(target, ctx)) {
          _hDeal(id, isAttacking(id) ? attacking : n, ctx);
        }
      case SwapMight(:final a, :final b):
        final ra = _resolveTarget(a, ctx), rb = _resolveTarget(b, ctx);
        if (ra.isEmpty || rb.isEmpty || ra.first == rb.first) break;
        final x = ra.first, y = rb.first;
        final mx = might(x), my = might(y);
        state.obj(x).mightMod += my - mx;
        state.obj(y).mightMod += mx - my;
        log('${nameOf(x)} and ${nameOf(y)} swap Might this turn.', player: p, card: x, kind: 'buff');
      case TakeControl(:final target, :final untilEot):
        for (final id in _resolveTarget(target, ctx)) {
          final o = state.obj(id);
          if (o.controller == p) continue;
          if (untilEot) state.marks['t:steal:$id'] = o.controller;
          o.controller = p;
          log('${playerName(p)} takes control of ${nameOf(id)}.', player: p, card: id, kind: 'info');
          // A unit changing controller at a battlefield contests it (CR 190.3.a.2).
          if (o.loc != base) {
            _contest(o.loc, p);
          }
        }
      case Blink(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          if (!isUnit(id)) continue;
          final o = state.obj(id);
          final loc = o.loc;
          final owner = o.owner;
          log('${nameOf(id)} is banished and played again.', player: owner, card: id, kind: 'play');
          if (card(id).token || state.marks.containsKey('copy:$id')) {
            _leaveBoard(id, toHand: false);
            continue;
          }
          o
            ..reset()
            ..zone = Zone.banish;
          var to = loc;
          if (e.anyBattlefield && state.bfs.isNotEmpty) {
            to = state.bfs.length == 1 ? 0 : ask(Decision(kind: DecisionKind.option, player: owner, prompt: 'Play ${nameOf(id)} to which battlefield?', labels: [for (final b in state.bfs) nameOf(b.obj)], source: ctx.source)).first;
          }
          _hPlayFree(owner, id, to, fromZone: Zone.banish);
        }
      case GatherAtOpen():
        final open = [
          for (var i = 0; i < state.bfs.length; i++)
            if (state.bfs[i].controller == null && unitsAt(i).isEmpty) i,
        ];
        if (open.isEmpty) break;
        final to = open.length == 1 ? open.first : open[ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Move your units to which open battlefield?', labels: [for (final i in open) nameOf(state.bfs[i].obj)], source: ctx.source)).first];
        final mine = units(player: p);
        if (mine.isEmpty) break;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Move which units to ${nameOf(state.bfs[to].obj)}?', options: mine, min: 0, max: mine.length, source: ctx.source));
        if (pick.isNotEmpty) _moveUnits(pick, to, p);
      case RevealHiddenDamage(:final n, :final target):
        final deck = state.player(p).deck;
        final top = deck.take(n).toList();
        if (top.isEmpty) break;
        final hidden = top.where((id) => parsed(id).has(Kw.hidden)).length;
        log('${playerName(p)} reveals ${top.map(nameOf).join(', ')}: $hidden with Hidden.', player: p, kind: 'info');
        for (final id in _resolveTarget(target, ctx)) {
          _hDeal(id, hidden, ctx);
        }
        for (final id in top) {
          deck.remove(id);
        }
        _recycleCards(p, top);
      case HiddenFromTrash(:final n):
        final pl = state.player(p);
        final options = [for (final id in pl.trash) if (parsed(id).has(Kw.hidden)) id];
        if (options.isEmpty) break;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Return up to $n cards with Hidden from your trash to your hand', options: options, min: 0, max: n < options.length ? n : options.length, source: ctx.source));
        for (final id in pick) {
          pl.trash.remove(id);
          state.obj(id).zone = Zone.hand;
          pl.hand.add(id);
        }
        if (pick.isNotEmpty) log('${playerName(p)} returns ${pick.map(nameOf).join(', ')} to hand.', player: p, kind: 'draw');
      case FreeHide():
        state.marks['t:freeHide:$p'] = 1;
      case PlayHiddenHere():
        final pl = state.player(p);
        final options = [
          for (final id in pl.hand)
            if (parsed(id).has(Kw.hidden) && parsed(id).supported && (card(id).type != CardType.spell || _hHasTargets([for (final a in parsed(id).abilities) if (a is SpellBody) ...a.effects], p, id))) id,
        ];
        if (options.isEmpty) break;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Play a card with Hidden from your hand here, free', options: options, min: 0, max: 1, source: ctx.source));
        if (pick.isNotEmpty) _hPlayFree(p, pick.first, ctx.loc, fromZone: Zone.hand);
      case OpponentPlaysUnit(:final bf):
        final r = _resolveTarget(bf, ctx);
        if (r.isEmpty) break;
        final opp = state.other(p);
        final hand = state.player(opp).hand;
        log('${playerName(opp)} reveals their hand: ${hand.isEmpty ? 'nothing' : hand.map(nameOf).join(', ')}.', player: opp, kind: 'info');
        final options = [for (final id in hand) if (card(id).type == CardType.unit && parsed(id).supported) id];
        if (options.isEmpty) break;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose a unit from their hand for them to play there', options: options, min: 0, max: 1, source: ctx.source));
        if (pick.isEmpty) break;
        _hPlayFree(opp, pick.first, _bfIndex(r.first), fromZone: Zone.hand);
        if (isUnit(pick.first)) _resolve(Stun(EventUnit()), _Ctx(controller: p, source: ctx.source, loc: ctx.loc, targets: ctx.targets, event: pick.first));
      case EnterReadyThisTurn():
        state.marks['t:readyEnter:$p'] = 1;
      case BuffBonusThisTurn():
        state.marks['t:buffBonus:$p'] = 1;
      case DoubleDamage(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          state.marks['t:double:$id'] = 1;
        }
      case CopyMe(:final n):
        final src = state.objOrNull(ctx.source);
        if (src == null || src.zone != Zone.board) break;
        for (var i = 0; i < n; i++) {
          final id = _newObj(src.card, p, Zone.board);
          state.marks['copy:$id'] = 1;
          _enterBoard(id, p, src.loc, ready: false);
        }
        log('${playerName(p)} plays $n Reflections of ${nameOf(ctx.source)}.', player: p, kind: 'play');
      case FetchToHand(:final tag):
        final pl = state.player(p);
        final options = [
          if (pl.champion != null && card(pl.champion!).hasTag(tag) && card(pl.champion!).type == CardType.unit) pl.champion!,
          for (final u in state.objects.values)
            if (u.zone == Zone.board && u.owner == p && card(u.id).type == CardType.unit && card(u.id).hasTag(tag)) u.id,
        ];
        if (options.isEmpty) break;
        final id = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Put a $tag unit into your hand', options: options, source: ctx.source)).first;
        if (pl.champion == id) {
          pl.champion = null;
          state.obj(id).zone = Zone.hand;
          pl.hand.add(id);
        } else {
          _leaveBoard(id, toHand: true);
        }
        log('${playerName(p)} puts ${nameOf(id)} into their hand.', player: p, card: id, kind: 'move');
      case ReturnOwn(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          final o = state.obj(id);
          log('${nameOf(id)} returns to its owner’s hand.', player: p, card: id, kind: 'move');
          if (o.zone == Zone.facedown) {
            o
              ..reset()
              ..zone = Zone.hand;
            state.player(o.owner).hand.add(id);
          } else {
            _leaveBoard(id, toHand: true);
          }
        }
      case DealMarked(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          _hDeal(id, state.obj(id).damage, ctx);
        }
      case MayPay(:final cost, :final effects):
        if (!canPay(p, cost.energy, cost.power)) break;
        if (!askYesNo(p, '${nameOf(ctx.source)}: pay ${cost.describe()} to ${effects.map(describeEffect).join(', ')}?', source: ctx.source)) break;
        _pay(p, cost.energy, cost.power);
        for (final x in effects) {
          _resolve(x, ctx);
        }
    }
  }

  /// [p] plays [id] (from [fromZone]) by an effect, ignoring its cost: a unit to [loc] (gear to
  /// base), a spell onto the chain with its choices made now.
  void _hPlayFree(int p, ObjId id, int loc, {required Zone fromZone}) {
    final pl = state.player(state.obj(id).owner);
    pl.hand.remove(id);
    final c = card(id);
    state.marks.remove('t:fd:$id');
    state.player(p).playedThisTurn++;
    if (c.type == CardType.spell) {
      final effects = [for (final a in parsed(id).abilities) if (a is SpellBody) ...a.effects];
      final targets = _chooseTargets(effects, p, id, base, optional: true);
      state.obj(id)
        ..zone = Zone.chain
        ..controller = p;
      log('${playerName(p)} plays ${c.name}.', player: p, card: id, kind: 'play');
      _pushChain(ChainItem(id: state.nextChainId++, source: id, card: c.key, ability: -1, controller: p, targets: targets));
      return;
    }
    final passives = [for (final a in parsed(id).abilities) if (a is Static) a.passive];
    _enterBoard(id, p, c.type == CardType.gear ? base : loc, ready: c.type == CardType.gear ? !passives.any((x) => x is EntersExhausted) : passives.any((x) => x is EntersReady));
    log('${playerName(p)} plays ${c.name}${loc == base ? '' : ' to ${locName(loc, p)}'}.', player: p, card: id, kind: 'play');
    _firePlayed(id);
    if (c.type == CardType.unit) _fire(On.youPlayUnit, player: p);
  }

  bool _hCond(HCond c, _Ctx ctx) {
    switch (c) {
      case FromHand():
        return !_hMarked('t:fd:${ctx.source}');
      case PaidExtra():
        return _hMarked('t:paid:${ctx.source}');
      case AloneAtOrigin(:final slot):
        final id = slot < ctx.targets.length ? ctx.targets[slot] : -1;
        final from = id < 0 ? null : _hs.origins[id];
        if (from == null || from == base) return false;
        final there = unitsAt(from);
        return there.length == 1 && state.obj(there.first).controller != ctx.controller;
      case EnemyAloneHere():
        if (ctx.loc == base) return false;
        final there = unitsAt(ctx.loc);
        return there.where((u) => state.obj(u).controller != ctx.controller).length == 1;
    }
  }

  // -------------------------------------------------------------------------------------------
  // Passives: Might, keywords, combat damage, readying, death
  // -------------------------------------------------------------------------------------------

  /// Might from this file's passives and marks (added to the printed Might, CR 143.2.a).
  int _hMight(ObjId id) {
    final o = state.obj(id);
    var m = 0;
    if (o.buffed && _hMarked('t:buffBonus:${o.controller}')) m += 1;
    for (final a in parsed(id).abilities) {
      if (a is! Static) continue;
      switch (a.passive) {
        case MightWhileStunnedEnemy(:final n):
          if (unitsAt(o.loc).any((u) => state.obj(u).controller != o.controller && state.obj(u).stunned && (o.loc != base))) m += n;
        case MightPerNamesake():
          m += unitsAt(o.loc, player: o.controller).where((u) => u != id && card(u).name == card(id).name).length;
        default:
          break;
      }
    }
    return m;
  }

  /// Keywords from this file's passives.
  int _hKw(ObjId id, Kw k) {
    final o = state.obj(id);
    if (o.zone != Zone.board) return 0;
    var n = 0;
    for (final a in parsed(id).abilities) {
      if (a is Static && a.passive is KwWithOnePartner) {
        final x = a.passive as KwWithOnePartner;
        if (x.kw == k && o.loc != base && unitsAt(o.loc, player: o.controller).where((u) => u != id).length == 1) n += x.n;
      }
    }
    return n;
  }

  /// "Enemy units here with less Might than me don't deal combat damage."
  bool _hNoCombatDamage(ObjId u) {
    final o = state.obj(u);
    for (final (src, passive) in _hPassivesOf(state.other(o.controller))) {
      if (passive is SilenceWeakerHere && state.obj(src).zone == Zone.board && state.obj(src).loc == o.loc && might(u) < might(src)) return true;
    }
    return false;
  }

  /// "I can't be readied."
  bool _hCantReady(ObjId id) => state.obj(id).zone == Zone.board && _hHas(id, (x) => x is CantBeReadied);

  /// "Friendly units enter ready this turn."
  bool _hEntersReady(int controller, ObjId id) => card(id).type == CardType.unit && _hMarked('t:readyEnter:$controller');

  /// A copy made by "They become copies of me" stops existing when it leaves the board, like a
  /// token (CR 186.1).
  bool _hIsCopy(ObjId id) => state.marks.remove('copy:$id') != null;

  /// "The next time a friendly unit would die, kill this instead": true if [id] was saved (CR
  /// 369.1: healed, exhausted and recalled).
  bool _hSaved(ObjId id) {
    final o = state.obj(id);
    if (o.zone != Zone.board || !isUnit(id)) return false;
    for (final (src, passive) in _hPassivesOf(o.controller)) {
      if (passive is! SavesFromDeath || state.obj(src).zone != Zone.board) continue;
      log('${nameOf(src)} is killed instead of ${nameOf(id)}, which is recalled.', player: o.controller, card: src, kind: 'die');
      _kill(src);
      o
        ..damage = 0
        ..exhausted = true
        ..loc = base;
      return true;
    }
    return false;
  }

  /// A unit is about to die: "when an enemy unit dies" for its controller's opponent.
  void _hOnDeath(ObjId id) {
    if (!isUnit(id)) return;
    _fire(On.enemyUnitDies, player: state.other(state.obj(id).controller), event: id);
  }

  /// [p] scored: "when an opponent scores" for the other player.
  void _hScored(int p) => _fire(On.opponentScores, player: state.other(p));

  /// May trigger [index] of [src] go on the chain now (its "on your turn", "while I'm at a
  /// battlefield", "once each turn" conditions)?
  bool _hTriggerOk(ObjId src, int index, int controller) {
    final abs = parsed(src).abilities;
    if (index < 0 || index >= abs.length) return true;
    final a = abs[index];
    if (a is! Triggered || a.on is! HWhen) return true;
    final w = a.on as HWhen;
    final o = state.obj(src);
    if (w.yourTurn && state.active != controller) return false;
    if (w.toBattlefield && o.loc == base) return false;
    if (w.whileAtBattlefield && (o.zone != Zone.board || o.loc == base)) return false;
    if (w.oncePerTurn) {
      if (o.usedThisTurn.contains(index)) return false;
      o.usedThisTurn.add(index);
    }
    return true;
  }

  /// End of turn (CR 317.2): control taken "until end of turn" returns and the unit is recalled;
  /// this turn's marks end.
  void _hEndOfTurn() {
    final keys = state.marks.keys.toList()..sortStable((a, b) => a.compareTo(b));
    for (final k in keys) {
      if (!k.startsWith('t:steal:')) continue;
      final id = int.parse(k.substring(8));
      final o = state.objOrNull(id);
      if (o != null && o.zone == Zone.board) {
        o
          ..controller = state.marks[k]!
          ..loc = base;
        log('${playerName(o.controller)} regains ${nameOf(id)}, recalled to base.', player: o.controller, card: id, kind: 'move');
      }
    }
    state.marks.removeWhere((k, _) => k.startsWith('t:'));
  }

  /// Where a spell played from facedown plays its tokens: that battlefield (CR 811.1.d.5).
  int? _hTokenLoc(_Ctx ctx) => state.marks['t:fd:${ctx.source}'];
}
