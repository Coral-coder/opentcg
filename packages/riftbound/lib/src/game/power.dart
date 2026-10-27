part of 'game.dart';

// Empower (CR 442–443, 827–828), XP (CR 728–733), Hunt (CR 823), Level (CR 824), buffs (CR 427,
// 701–705) and Flow (CR 829) in play. Shared engine code reaches these through one-line hooks.

/// [ActivateMove.index] of the ability a battlefield grants its units ("Units here have "{E}: Gain
/// 1 XP."", Gardens of Becoming).
const grantedXpAbility = -10;

/// The chosen targets of the choice or resolution in progress, for filters that compare with an
/// earlier choice ("with less Might than it").
final _powerTargetsOf = Expando<List<int>>();

/// What the additional cost paid for the card being played takes off its cost (Poppy's {3},
/// Kraken Hunter's {O} per buff), until it's paid for.
final _powerPlayDiscount = Expando<({ObjId id, int energy, List<Domain?> power})>();

extension GamePowerRules on Game {
  // -------------------------------------------------------------------------------------------
  // Gates (dependent keywords)
  // -------------------------------------------------------------------------------------------

  /// Is an ability of [src] with [gate] active now?
  bool _gateOk(ObjId src, Gate? gate) {
    if (gate == null) return true;
    final o = state.objOrNull(src);
    if (o == null) return false;
    return switch (gate) {
      EmpoweredGate(:final times) => times == 0 ? o.pw.empowered == 0 : o.pw.empowered >= times,
      LevelGate(:final n) => state.player(o.controller).pw.xp >= n,
      BuffedGate() => o.buffed,
      XpGainedGate() => state.player(o.controller).pw.xpGainedTurn == state.turn,
    };
  }

  /// Statics of [c] (not on the board: a card being played by [p]) that are active.
  Iterable<Passive> _cardPassives(int p, RCard c) sync* {
    for (final a in RiftboundParser.parse(c).abilities) {
      if (a is! Static) continue;
      final g = a.gate;
      if (g == null || (g is LevelGate && state.player(p).pw.xp >= g.n)) yield a.passive;
    }
  }

  // -------------------------------------------------------------------------------------------
  // XP, Empower, buffs
  // -------------------------------------------------------------------------------------------

  /// Gain XP (CR 730.1).
  void gainXp(int p, int n) {
    if (n <= 0) return;
    final pw = state.player(p).pw;
    pw.xp += n;
    pw.xpGainedTurn = state.turn;
    log('${playerName(p)} gains $n XP ($n → ${pw.xp}).', player: p, kind: 'xp', amount: n);
  }

  int _maxEmpowered(ObjId id) {
    var n = 1;
    for (final a in parsed(id).abilities) {
      if (a is Static && a.passive is EmpowerTimes) n = (a.passive as EmpowerTimes).n;
    }
    return n;
  }

  /// Empower [id] (CR 442), by player [by]. False if it can't be (already Empowered, CR 442.1.c).
  bool _empower(ObjId id, int by) {
    final o = state.obj(id);
    if (o.pw.empowered >= _maxEmpowered(id)) return false;
    o.pw.empowered++;
    log('${nameOf(id)} is Empowered${o.pw.empowered > 1 ? ' (×${o.pw.empowered})' : ''}.', player: o.controller, card: id, kind: 'empower');
    // "When I become [Empowered]" (CR 828.1.d) and "When you empower something else".
    final abs = parsed(id).abilities;
    for (var i = 0; i < abs.length; i++) {
      final a = abs[i];
      if (a is Triggered && a.on.on == On.empowered) _queue(id, i, o.controller);
    }
    _firePw(On.youEmpowerOther, player: by, except: id);
    return true;
  }

  /// Disempower [id] (CR 443): one Empowered status off; nothing if it has none.
  bool _disempower(ObjId id) {
    final o = state.obj(id);
    if (o.pw.empowered == 0) return false;
    o.pw.empowered--;
    log('${nameOf(id)} is no longer Empowered.', player: o.controller, card: id, kind: 'empower');
    return true;
  }

  bool _hasManyBuffs(ObjId id) => parsed(id).abilities.any((a) => a is Static && a.passive is ManyBuffs);

  /// Buff [id] (CR 427): a buff counter if it has none (or any number with permission). "When
  /// you buff …" triggers only when a buff was placed (CR 427.1.c).
  void _buffUnit(ObjId id, int p) {
    final o = state.obj(id);
    if (o.buffed) {
      if (!_hasManyBuffs(id)) return;
      o.pw.extraBuffs++;
    } else {
      o.buffed = true;
    }
    log('${nameOf(id)} is buffed.', player: p, card: id, kind: 'buff');
    if (o.controller == p) {
      final abs = parsed(id).abilities;
      for (var i = 0; i < abs.length; i++) {
        final a = abs[i];
        if (a is Triggered && a.on.on == On.buffedMe) _queue(id, i, p, event: id);
      }
      _firePw(On.youBuffFriendly, player: p, event: id);
    }
  }

  int _buffs(ObjId id) {
    final o = state.obj(id);
    return o.buffed ? 1 + o.pw.extraBuffs : 0;
  }

  /// Spend a buff from [id] (CR 702.2.b), by [p]. False if it has none.
  bool _spendBuff(ObjId id, int p) {
    final o = state.obj(id);
    if (!o.buffed || o.controller != p) return false;
    if (o.pw.extraBuffs > 0) {
      o.pw.extraBuffs--;
    } else {
      o.buffed = false;
    }
    log('${playerName(p)} spends ${nameOf(id)}’s buff.', player: p, card: id, kind: 'buff');
    _firePw(On.youSpendBuff, player: p);
    return true;
  }

  /// Triggers [on] of what [player] controls (legend, board, and battlefields for "here"
  /// triggers), skipping [except]; [event] is the unit it's about.
  void _firePw(On on, {required int player, int event = -1, int except = -1, int bf = -2}) {
    final srcs = [?state.player(player).legend, for (final o in _boardOf(player)) o.id];
    for (final s in srcs) {
      if (s == except) continue;
      final abs = parsed(s).abilities;
      for (var i = 0; i < abs.length; i++) {
        final a = abs[i];
        if (a is Triggered && a.on.on == on) _queue(s, i, player, loc: bf, event: event);
      }
    }
  }

  // -------------------------------------------------------------------------------------------
  // Activated abilities: gates, extra costs, cost changes
  // -------------------------------------------------------------------------------------------

  /// Why [a] (ability [index] of [src]) can't be used by [p] now, or null.
  String? _powerActivateProblem(int p, ObjId src, int index, Activated a) {
    if (!_gateOk(src, a.gate)) return 'That ability isn’t active now';
    final o = state.obj(src);
    if (a.effects.any((e) => e is EmpowerMe) && o.pw.empowered >= _maxEmpowered(src)) return '${nameOf(src)} is already Empowered';
    for (final x in a.cost.extra) {
      switch (x) {
        case SpendXp(:final n):
          if (state.player(p).pw.xp < n) return 'Needs $n XP';
        case SpendMyBuff():
          if (!o.buffed) return '${nameOf(src)} has no buff to spend';
        case DisempowerMe():
          if (o.pw.empowered == 0) return '${nameOf(src)} isn’t Empowered';
        case KillFriendly():
          if (units(player: p).isEmpty) return 'No friendly unit to kill';
        case DiscardCost(:final n, :final spell):
          final hand = [for (final h in state.player(p).hand) if (!spell || card(h).type == CardType.spell) h];
          if (hand.length < n) return spell ? 'No spell to discard' : 'Not enough cards to discard';
        case EnergyLess():
          break;
      }
    }
    return null;
  }

  /// The Energy and Power [p] pays for [a] of [src], after "costs {N} less" (CR 827.1.c.3) and
  /// Risen Altar.
  ({int energy, List<Domain?> power}) _activationCost(int p, ObjId src, Activated a) {
    var e = a.cost.energy;
    final power = List<Domain?>.of(a.cost.power);
    for (final x in a.cost.extra) {
      if (x is! EnergyLess) continue;
      final runes = state.player(p).runes.length;
      if (x.perRune) {
        e -= x.n * runes;
      } else if (runes <= x.ifRunesAtMost!) {
        e -= x.n;
      }
    }
    if (a.effects.any((ef) => ef is EmpowerMe) && isUnit(src)) {
      // "[Empower] costs of your units here cost {1} or {A} less": the payer's better option.
      final o = state.obj(src);
      if (o.loc != base && _bfPassives(o.loc).any((x) => x is EmpowerCostLessHere) && state.bfs[o.loc].controller == p) {
        if (e > 0) {
          e -= 1;
        } else if (power.isNotEmpty) {
          power.removeAt(power.lastIndexWhere((d) => d == null) >= 0 ? power.lastIndexWhere((d) => d == null) : power.length - 1);
        }
      }
    }
    return (energy: e < 0 ? 0 : e, power: power);
  }

  /// Pays the parts of [a]'s cost beyond runes and exhausting.
  void _powerPayExtra(int p, ObjId src, Activated a) {
    for (final x in a.cost.extra) {
      switch (x) {
        case SpendXp(:final n):
          state.player(p).pw.xp -= n;
          log('${playerName(p)} spends $n XP.', player: p, kind: 'xp');
        case SpendMyBuff():
          _spendBuff(src, p);
        case DisempowerMe():
          _disempower(src);
        case KillFriendly():
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(src)}: choose a friendly unit to sacrifice', options: units(player: p), source: src));
          log('${nameOf(pick.first)} is killed.', player: p, card: pick.first, kind: 'die');
          _kill(pick.first);
        case DiscardCost(:final n, :final spell):
          final hand = state.player(p).hand;
          final options = [for (final h in hand) if (!spell || card(h).type == CardType.spell) h];
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Discard ${spell ? 'a spell' : '$n'} for ${nameOf(src)}', options: options, min: n, max: n, source: src));
          for (final id in pick) {
            hand.remove(id);
            state.obj(id).zone = Zone.trash;
            state.player(p).trash.add(id);
          }
          log('${playerName(p)} discards ${pick.map(nameOf).join(', ')}.', player: p, kind: 'discard');
        case EnergyLess():
          break;
      }
    }
  }

  /// Uses a battlefield's granted "{E}: Gain 1 XP." on unit [src] (resolves at once).
  void _activateGranted(int p, ObjId src) {
    final o = state.objOrNull(src);
    if (o == null || o.controller != p || !isUnit(src) || o.loc == base || !_bfPassives(o.loc).any((x) => x is GrantXpAbility)) throw RiftboundError('No such ability');
    final t = _timingProblem(p, Timing.normal);
    if (t != null) throw RiftboundError(t);
    if (o.exhausted) throw RiftboundError('${nameOf(src)} is exhausted');
    o.exhausted = true;
    log('${playerName(p)} exhausts ${nameOf(src)} at ${nameOf(state.bfs[o.loc].obj)}.', player: p, card: src, kind: 'ability');
    gainXp(p, 1);
  }

  /// Passives of the battlefield at [bf].
  Iterable<Passive> _bfPassives(int bf) sync* {
    if (bf < 0 || bf >= state.bfs.length) return;
    for (final a in parsed(state.bfs[bf].obj).abilities) {
      if (a is Static) yield a.passive;
    }
  }

  // -------------------------------------------------------------------------------------------
  // Card costs (CR 356) and Flow (CR 829)
  // -------------------------------------------------------------------------------------------

  /// Can [p] play spell [id] from their trash with Flow (or Flow given this turn)?
  bool _flowPlayable(int p, ObjId id) => _flowCost(p, id) != null;

  /// The Flow cost of spell [id] in [p]'s trash, or null.
  ({int energy, List<Domain?> power})? _flowCost(int p, ObjId id) {
    final o = state.objOrNull(id);
    if (o == null || o.zone != Zone.trash || o.owner != p) return null;
    final c = card(id);
    if (c.type != CardType.spell) return null;
    ({int energy, List<Domain?> power})? best;
    for (final a in parsed(id).abilities) {
      if (a is Static && a.passive is Flow) {
        final f = a.passive as Flow;
        best ??= (energy: f.energy, power: f.power);
      }
    }
    if (best == null && o.pw.flowGrantedTurn == state.turn) best = (energy: c.energy, power: _powerOf(c, c.power));
    return best;
  }

  /// The cost [p] pays to play [c] (object [id] if known): Flow from the trash replaces the base
  /// cost; "I cost … less", "This costs … less", spell cost changes, and "to a minimum of".
  ({int energy, List<Domain?> power}) _powerCardCost(int p, RCard c, ObjId? id, int energy, List<Domain?> power0) {
    var e = energy;
    var power = List<Domain?>.of(power0);
    final flow = id == null ? null : _flowCost(p, id);
    if (flow != null) {
      e = flow.energy;
      power = List.of(flow.power);
      // Stargazer: "Spells with [Flow] you play from your trash cost {2} less, to a minimum of {1}".
      for (final (src, pas) in _passives()) {
        if (pas is FlowCostLess && state.obj(src).controller == p) {
          e -= pas.n;
          if (e < pas.minEnergy) e = flow.energy < pas.minEnergy ? flow.energy : pas.minEnergy;
        }
      }
    }
    // The card's own Level / conditional discounts: the largest applies ("… instead").
    var bestE = 0;
    List<Domain?> bestP = const [];
    for (final pas in _cardPassives(p, c)) {
      if (pas is CostLessPower && pas.energy >= bestE) {
        bestE = pas.energy;
        bestP = pas.power;
      }
      if (pas is SpellCostLess && pas.n > bestE && (!pas.ifControlEmpowered || _controlsEmpowered(p))) {
        bestE = pas.n;
        bestP = const [];
      }
    }
    e -= bestE;
    for (final d in bestP) {
      final i = power.indexOf(d);
      if (i >= 0) power.removeAt(i);
    }
    if (c.type == CardType.spell) {
      for (final (src, pas) in _passives()) {
        if (pas is! SpellCostMod) continue;
        final mine = state.obj(src).controller == p;
        if (pas.yours != mine) continue;
        if (pas.energy < 0) {
          final floor = e < pas.minEnergy ? e : pas.minEnergy;
          e += pas.energy;
          if (e < floor) e = floor;
        } else {
          e += pas.energy;
        }
        for (var i = 0; i < pas.power.abs(); i++) {
          if (pas.power > 0) {
            power.add(null);
          } else if (power.isNotEmpty) {
            power.removeAt(power.lastIndexWhere((d) => d == null) >= 0 ? power.lastIndexWhere((d) => d == null) : power.length - 1);
          }
        }
      }
    }
    final dc = _powerPlayDiscount[this];
    if (dc != null && dc.id == id) {
      e -= dc.energy;
      for (final d in dc.power) {
        final i = power.indexOf(d);
        if (i >= 0) power.removeAt(i);
      }
    }
    return (energy: e < 0 ? 0 : e, power: power);
  }

  /// Additional costs paid in XP or buffs (CR 356.3), asked as [id] is played: whether its cost
  /// is then ignored and whether one was paid. A discount it gives applies to the payment after.
  ({bool ignore, bool paid}) _powerExtraCost(int p, ObjId id) {
    _powerPlayDiscount[this] = null;
    for (final a in parsed(id).abilities) {
      if (a is! Static || a.passive is! PowerExtraCost) continue;
      final x = a.passive as PowerExtraCost;
      if (x.xp > 0) {
        final pl = state.player(p);
        if (pl.pw.xp < x.xp || !askYesNo(p, 'Spend ${x.xp} XP as an additional cost to play ${nameOf(id)}?', source: id)) continue;
        pl.pw.xp -= x.xp;
        log('${pl.name} spends ${x.xp} XP to play ${nameOf(id)}.', player: p, card: id, kind: 'xp');
        if (x.energyLess > 0) _powerPlayDiscount[this] = (id: id, energy: x.energyLess, power: const []);
        return (ignore: false, paid: true);
      }
      final c = card(id);
      final per = x.powerPerBuff;
      final max = !x.anyBuffs ? x.buffs : (per == null ? 0 : _powerOf(c, c.power).where((d) => d == per).length);
      var spent = 0;
      while (spent < max) {
        final options = [for (final u in units(player: p)) if (_buffs(u) > 0) u];
        if (options.isEmpty) break;
        // Not optional while the card can't be paid for without it.
        if (per != null) _powerPlayDiscount[this] = (id: id, energy: 0, power: List<Domain?>.filled(spent, per));
        final must = !_canPayCard(p, c, id: id);
        _powerPlayDiscount[this] = null;
        final prompt = per != null ? 'Spend a buff to play ${nameOf(id)} for {${per.letter}} less?${must ? '' : ' (none to stop)'}' : 'Spend a buff to play ${nameOf(id)} without paying its cost?';
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: prompt, options: options, min: must ? 1 : 0, max: 1, source: id));
        if (pick.isEmpty) break;
        _spendBuff(pick.first, p);
        spent++;
      }
      if (spent == 0) continue;
      if (per != null) _powerPlayDiscount[this] = (id: id, energy: 0, power: List<Domain?>.filled(spent, per));
      return (ignore: x.ignoreCost, paid: true);
    }
    return (ignore: false, paid: false);
  }

  /// Could [p] afford [id] by paying its XP or buff additional cost (it's ignored or cheaper)?
  bool _powerExtraMayPay(int p, ObjId id) {
    for (final a in parsed(id).abilities) {
      if (a is! Static || a.passive is! PowerExtraCost) continue;
      final x = a.passive as PowerExtraCost;
      var buffs = 0;
      for (final u in units(player: p)) {
        buffs += _buffs(u);
      }
      if (x.xp > 0 ? state.player(p).pw.xp < x.xp : buffs == 0) continue;
      if (x.ignoreCost) return true;
      final per = x.powerPerBuff;
      _powerPlayDiscount[this] = (id: id, energy: x.energyLess, power: per == null ? const [] : List<Domain?>.filled(buffs, per));
      final ok = _canPayCard(p, card(id), id: id);
      _powerPlayDiscount[this] = null;
      if (ok) return true;
    }
    return false;
  }

  /// Battlefields [p] may also play unit [id] to: occupied ones where an enemy unit is alone, with
  /// "I can be played …" on it or "Friendly units can be played …" on a permanent of theirs.
  Iterable<int> _powerDestinations(int p, ObjId id) sync* {
    bool me(Ability a) => a is Static && a.passive is PlayToLoneEnemy && !(a.passive as PlayToLoneEnemy).friendly;
    final ok = parsed(id).abilities.any(me) || _passives().any((x) => x.$2 is PlayToLoneEnemy && (x.$2 as PlayToLoneEnemy).friendly && state.obj(x.$1).controller == p);
    if (!ok || card(id).type != CardType.unit) return;
    for (var i = 0; i < state.bfs.length; i++) {
      if (unitsAt(i, player: state.other(p)).length == 1) yield i;
    }
  }

  /// What [p] would pay to play card [id] now (the first way they can pay, else the first way):
  /// Flow from the trash and cost changes included.
  ({int energy, List<Domain?> power}) playCost(int p, ObjId id) {
    final c = card(id);
    final costs = _cardCosts(p, c, id, 0, const []);
    return costs.where((x) => canPay(p, x.energy, x.power, forSpell: c.type == CardType.spell)).firstOrNull ?? costs.first;
  }

  bool _canPayReduced(int p, ObjId id, int less) {
    final c = card(id);
    return _cardCosts(p, c, null, 0, const []).any((x) => canPay(p, x.energy - less < 0 ? 0 : x.energy - less, x.power));
  }

  void _payReduced(int p, ObjId id, int less) {
    final c = card(id);
    for (final x in _cardCosts(p, c, null, 0, const [])) {
      final e = x.energy - less < 0 ? 0 : x.energy - less;
      if (canPay(p, e, x.power)) {
        _pay(p, e, x.power);
        return;
      }
    }
  }

  bool _controlsEmpowered(int p) {
    final legend = state.player(p).legend;
    if (legend != null && state.obj(legend).pw.empowered > 0) return true;
    return _boardOf(p).any((o) => o.pw.empowered > 0);
  }

  /// A card about to be played from somewhere other than the hand leaves it: a Flow spell from the
  /// trash is marked to be banished (CR 829.1.b), and "When you play a card from anywhere other than
  /// your hand" triggers.
  void _leaveZoneForPlay(int p, ObjId id) {
    _powerPlayDiscount[this] = null;
    final o = state.obj(id);
    if (o.zone == Zone.trash) {
      state.player(o.owner).trash.remove(id);
      o.pw.flowed = true;
      log('${playerName(p)} plays ${nameOf(id)} from the trash with Flow.', player: p, card: id, kind: 'play');
      _firePw(On.youPlayNotFromHand, player: p);
    }
  }

  /// A finished spell played with Flow is banished instead (CR 829.1.b). True if it was.
  bool _banishFlowed(Obj o) {
    if (!o.pw.flowed) return false;
    o.pw = ObjPower();
    o.zone = Zone.banish;
    state.player(o.owner).banish.add(o.id);
    log('${nameOf(o.id)} is banished.', player: o.owner, card: o.id, kind: 'info');
    _firePw(On.youBanishOwn, player: o.owner);
    return true;
  }

  // -------------------------------------------------------------------------------------------
  // Board: Might, keywords, filters, choices
  // -------------------------------------------------------------------------------------------

  /// Might from extra buffs and this family's passives (CR 703, 828).
  int _powerMight(ObjId id) {
    final o = state.obj(id);
    var m = o.pw.extraBuffs;
    for (final (src, pas) in _passives()) {
      final so = state.obj(src);
      switch (pas) {
        case SelfMight(:final n, :final perEmpowered, :final perBuffedFriendlyHere):
          if (src != id) continue;
          if (perEmpowered) {
            m += n * o.pw.empowered;
          } else if (perBuffedFriendlyHere) {
            if (o.loc == base) continue;
            m += n * [for (final u in unitsAt(o.loc, player: o.controller)) if (state.obj(u).buffed) u].length;
          } else {
            m += n;
          }
        case PowerAnthem(:final n, :final filter, :final kw):
          if (kw == null && matches(filter, id, controller: so.controller, source: src, here: so.loc)) m += n;
        default:
          break;
      }
    }
    return m;
  }

  /// Keyword values from this family's passives; [current] is the value without them.
  int _powerKw(ObjId id, Kw k, int current) {
    var n = 0;
    for (final (src, pas) in _passives()) {
      final so = state.obj(src);
      switch (pas) {
        case SelfKw(:final kw, n: final v):
          if (src == id && kw == k) n += v;
        case PowerAnthem(:final kw, :final filter):
          // "… have [Deflect] if they didn't already": only units without it.
          if (kw == k && current + n == 0 && matches(filter, id, controller: so.controller, source: src, here: so.loc)) n += 1;
        default:
          break;
      }
    }
    return n;
  }

  /// The [PowerFilter] part of a filter.
  bool _powerMatches(PowerFilter pw, ObjId id, {required int controller, ObjId? source, int here = base}) {
    final o = state.obj(id);
    if (pw.empowered != null && (o.pw.empowered > 0) != pw.empowered) return false;
    final src = source == null ? null : state.objOrNull(source);
    if (pw.lessMightThanSource && (src == null || src.zone != Zone.board || mightUsed(id) >= mightUsed(source!))) return false;
    final targets = _powerTargetsOf[this] ?? const <int>[];
    final lc = pw.lessMightThanChosen;
    if (lc != null) {
      final c = lc < targets.length ? targets[lc] : -1;
      if (c < 0 || state.objOrNull(c)?.zone != Zone.board || mightUsed(id) >= mightUsed(c)) return false;
    }
    final wc = pw.withChosen;
    if (wc != null) {
      final c = wc < targets.length ? targets[wc] : -1;
      if (c < 0 || state.objOrNull(c)?.zone != Zone.board || state.obj(c).loc != o.loc) return false;
    }
    if (pw.movedFromOrTo) {
      if (src == null || o.loc == base) return false;
      if (o.loc != src.loc && o.loc != src.pw.movedFrom) return false;
    }
    if (pw.atBattlefieldOnly && (src == null || src.loc == base)) return false;
    if (pw.inShowdown && (state.showdown == null || state.showdown!.bf != o.loc)) return false;
    final mm = pw.mightMaxUnlessPaid;
    if (mm != null && !(source != null && _hMarked('t:paid:$source')) && might(id) > mm) return false;
    return true;
  }

  /// Gangplank, Naval: a stun, -Might or return to hand from a spell or ability that chose [id]
  /// gives it +N Might instead (CR 370). True if replaced.
  bool _harmReplaced(ObjId id, Target target, int by) {
    if (target is! Choose && target is! Chosen) return false;
    for (final a in parsed(id).abilities) {
      if (a is Static && a.passive is ChosenHarmToMight && _gateOk(id, a.gate)) {
        final n = (a.passive as ChosenHarmToMight).n;
        state.obj(id).mightMod += n;
        log('${nameOf(id)} gets +$n Might this turn instead.', player: state.obj(id).controller, card: id, kind: 'buff');
        return true;
      }
    }
    return false;
  }

  bool _melActive(int p) => _passives().any((x) => x.$2 is MelAwakened && state.obj(x.$1).controller == p);

  /// Mel, Newly Awakened: [p]'s spells and abilities can't be countered.
  bool _cantBeCountered(int p) => _melActive(p);

  /// Mel, Newly Awakened: a -Might [p] gives to a unit it chose is 1 more.
  int _extraMinus(int n, Target target, int p) {
    if (n >= 0 || (target is! Choose && target is! Chosen)) return 0;
    var extra = 0;
    for (final (src, pas) in _passives()) {
      if (pas is MelAwakened && state.obj(src).controller == p) extra--;
    }
    return extra;
  }

  /// Can't [id] be chosen by [p]'s spells and abilities?
  bool _unchoosable(ObjId id, int p) {
    final o = state.objOrNull(id);
    if (o == null || o.controller == p) return false;
    return o.pw.untargetableTurn == state.turn;
  }

  /// Does unit [id] entering under [controller] enter ready ("Your units enter ready"; its own
  /// gated "I enter ready")?
  bool _enterReady(int controller, ObjId id) {
    if (card(id).type != CardType.unit) return false;
    for (final a in parsed(id).abilities) {
      if (a is Static && a.gate != null && a.passive is EntersReady && _gateOk(id, a.gate)) return true;
    }
    for (final (src, pas) in _passives()) {
      if (pas is UnitsEnterReady && state.obj(src).controller == controller) return true;
    }
    return false;
  }

  /// Unit [id] can't be dealt damage now ("unless I'm in combat").
  bool _noDamage(ObjId id) {
    for (final a in parsed(id).abilities) {
      if (a is Static && a.passive is NoDamageOutsideCombat && _gateOk(id, a.gate)) {
        final sd = state.showdown;
        if (sd == null || !sd.combat || sd.bf != state.obj(id).loc) return true;
      }
    }
    return false;
  }

  /// Moves this family adds: Flow spells in the trash, battlefield-granted abilities.
  List<RMove> _powerCandidates(int seat) {
    final pl = state.player(seat);
    final out = <RMove>[];
    for (final id in pl.trash) {
      if (_flowPlayable(seat, id)) out.add(PlayMove(seat, id));
    }
    for (final u in units(player: seat)) {
      final o = state.obj(u);
      if (o.loc != base && _bfPassives(o.loc).any((x) => x is GrantXpAbility)) out.add(ActivateMove(seat, u, grantedXpAbility));
    }
    return out;
  }

  // -------------------------------------------------------------------------------------------
  // Events
  // -------------------------------------------------------------------------------------------

  /// Unit [id] was just played by [p]: "When you play another unit", "When a friendly unit is
  /// played this turn", "When a player plays a unit here".
  void _unitPlayed(ObjId id, int p) {
    _firePw(On.youPlayAnotherUnit, player: p, except: id);
    for (final d in state.pw.delayed) {
      if (d.kind == 'buffPlayedThisTurn' && d.controller == p && d.turn == state.turn && isUnit(id)) _buffUnit(id, p);
    }
    // "The next time you play a unit this turn, ready it and [Buff] it" (Nami): once.
    final next = state.pw.delayed.where((d) => d.kind == 'nextUnitReadyBuff' && d.controller == p && d.turn == state.turn).firstOrNull;
    if (next != null && isUnit(id)) {
      state.pw.delayed = [for (final d in state.pw.delayed) if (!identical(d, next)) d];
      state.obj(id).exhausted = false;
      _buffUnit(id, p);
    }
    final loc = state.obj(id).loc;
    if (loc != base) {
      final b = state.bfs[loc].obj;
      final abs = parsed(b).abilities;
      for (var i = 0; i < abs.length; i++) {
        final a = abs[i];
        if (a is Triggered && a.on.on == On.unitPlayedHere) _queue(b, i, p, loc: loc, event: id);
      }
    }
  }

  /// [id] is about to die: "When another friendly unit dies", "When a buffed friendly unit dies".
  void _unitDies(ObjId id) {
    final o = state.obj(id);
    if (card(id).type != CardType.unit) return;
    _firePw(On.anotherFriendlyDies, player: o.controller, except: id, event: id);
    if (o.buffed) _firePw(On.buffedFriendlyDies, player: o.controller, except: id, event: id);
  }

  /// "When a buffed unit you control would die, you may pay {A} and exhaust me to spend its buff
  /// and recall it exhausted instead." (Sett, The Boss). True if [id] was saved.
  bool _savedFromDeath(ObjId id) {
    final o = state.obj(id);
    if (!o.buffed || card(id).type != CardType.unit) return false;
    final legend = state.player(o.controller).legend;
    if (legend == null || state.obj(legend).exhausted) return false;
    if (!parsed(legend).abilities.any((a) => a is Static && a.passive is SaveBuffed)) return false;
    final p = o.controller;
    if (!canPay(p, 0, const [null])) return false;
    if (!askYesNo(p, '${nameOf(legend)}: pay {A} and exhaust it to save ${nameOf(id)} (spend its buff and recall it exhausted)?', source: legend)) return false;
    _pay(p, 0, const [null]);
    state.obj(legend).exhausted = true;
    _spendBuff(id, p);
    o
      ..loc = base
      ..exhausted = true;
    log('${nameOf(id)} is recalled instead of dying.', player: p, card: id, kind: 'move');
    return true;
  }

  /// After a combat at a battlefield: "When a combat that I was in ends" for [inCombat] units
  /// still on the board.
  void _combatEnded(List<ObjId> inCombat) {
    for (final u in inCombat) {
      if (state.obj(u).zone != Zone.board) continue;
      _fireUnit(u, const {On.combatEnds});
    }
  }

  /// Unit [u] won a combat: "When it wins a combat this turn, gain N XP".
  void _unitWon(ObjId u) {
    for (final d in state.pw.delayed) {
      if (d.kind == 'xpWhenItWins' && d.unit == u && d.turn == state.turn) gainXp(d.controller, d.n);
    }
  }

  /// [p] recycled cards from their deck, hand or trash.
  void _recycled(int p) => _firePw(On.youRecycle, player: p);

  /// Cleanup checks of this family (CR 323): "When my Might becomes 10 or more".
  void _powerCleanup() {
    for (final o in state.objects.values.toList()) {
      if (o.zone != Zone.board || card(o.id).type != CardType.unit) continue;
      final abs = parsed(o.id).abilities;
      if (!abs.any((a) => a is Triggered && a.on.on == On.mightTen)) continue;
      final ten = might(o.id) >= 10;
      if (ten && !o.pw.mightTen) {
        for (var i = 0; i < abs.length; i++) {
          final a = abs[i];
          if (a is Triggered && a.on.on == On.mightTen) _queue(o.id, i, o.controller);
        }
      }
      o.pw.mightTen = ten;
    }
  }

  /// "Your conquer effects for conquering here trigger an additional time" (Red Brambleback):
  /// the conquer triggers queued from index [from] are queued again.
  void _conquerAgain(int p, int bf, int from) {
    final twice = unitsAt(bf, player: p).any((u) => parsed(u).abilities.any((a) => a is Static && a.passive is ConquerTwiceHere));
    if (!twice) return;
    final again = state.waiting.sublist(from);
    state.waiting.addAll(again);
  }

  /// The end of the turn: delayed "at end of turn" effects; this turn's delayed abilities end.
  void _powerEndOfTurn() {
    for (final d in state.pw.delayed) {
      if (d.turn != state.turn || d.unit < 0 || state.objOrNull(d.unit)?.zone != Zone.board) continue;
      if (d.kind == 'disempowerAtEnd') _disempower(d.unit);
      if (d.kind == 'empowerAtEnd') _empower(d.unit, d.controller);
    }
    state.pw.delayed = [for (final d in state.pw.delayed) if (d.turn > state.turn) d];
  }

  // -------------------------------------------------------------------------------------------
  // Effects
  // -------------------------------------------------------------------------------------------

  /// Effects inside [e] whose targets are chosen as it's played, or null if [e] has its own.
  List<Effect>? _powerInner(PowerEffect e) => switch (e) {
        PayToDo(:final pay, :final effects) => [if (pay is PayEffect) pay.effect, ...effects],
        InsteadIf(:final normal, :final instead) => [...normal, ...instead],
        SpendBuffsEach(:final effects) => effects,
        OneOf(:final options) => [for (final o in options) ...o],
        _ => null,
      };

  Target? _powerTargetOf(PowerEffect e) => switch (e) {
        Empower(:final target) || Banish(:final target) || MoveAny(:final target) || Untargetable(:final target) || PickIt(:final target) || SpendBuffOf(:final target) || BaseMightBecomes(:final target) => target,
        _ => null,
      };

  int _powerAmount(PowerAmount a, _Ctx ctx) => switch (a) {
        PerFriendlyUnit() => units(player: ctx.controller).length,
        ChosenMight(:final slot) => slot < ctx.targets.length && ctx.targets[slot] >= 0 && state.objOrNull(ctx.targets[slot])?.zone == Zone.board ? mightUsed(ctx.targets[slot]) : 0,
      };

  int _amount(Amount a, _Ctx ctx) => switch (a) {
        N(:final n) => n,
        MyMight() => state.objOrNull(ctx.source)?.zone == Zone.board ? mightUsed(ctx.source) : 0,
        PowerAmount() => _powerAmount(a, ctx),
      };

  ObjId? _chosen(int slot, _Ctx ctx) {
    if (slot < 0 || slot >= ctx.targets.length) return null;
    final id = ctx.targets[slot];
    return id >= 0 && state.objOrNull(id)?.zone == Zone.board ? id : null;
  }

  bool _powerCondEval(PowerCond c, _Ctx ctx) {
    final p = ctx.controller;
    switch (c) {
      case IsEmpowered(:final slot):
        final id = slot < 0 ? ctx.source : _chosen(slot, ctx);
        return id != null && state.objOrNull(id) != null && state.obj(id).pw.empowered > 0;
      case ControlEmpowered():
        return _controlsEmpowered(p);
      case HasXp(:final n):
        return state.player(p).pw.xp >= n;
      case YourTurn():
        return state.active == p;
      case RunesCount(:final n, :final atLeast):
        final r = state.player(p).runes.length;
        return atLeast ? r >= n : r <= n;
      case ControlTag(:final tag):
        return units(player: p).any((u) => card(u).hasTag(tag));
      case OpponentNearVictory(:final n):
        return state.player(state.other(p)).points >= state.victoryScore - n;
      case AtBattlefield():
        final o = state.objOrNull(ctx.source);
        return o != null && o.zone == Zone.board && o.loc != base;
      case ExactlyUnitsWithChosen(:final n, :final slot):
        final id = _chosen(slot, ctx);
        if (id == null || state.obj(id).loc == base) return false;
        return unitsAt(state.obj(id).loc, player: p).length == n;
      case ChosenMightAtMost(:final n, :final slot):
        final id = _chosen(slot, ctx);
        return id != null && mightUsed(id) <= n;
    }
  }

  void _resolveAll(List<Effect> es, _Ctx ctx) {
    for (final x in es) {
      if (state.over) return;
      _resolve(x, ctx);
    }
  }

  /// Resolves [es] choosing their targets now (for instructions that only happen after a choice
  /// made as the ability resolves).
  void _resolveChoosingNow(List<Effect> es, _Ctx ctx) {
    final t = _chooseTargets(es, ctx.controller, ctx.source, ctx.loc, optional: true);
    final merged = List<int>.of(ctx.targets);
    for (var i = 0; i < t.length; i++) {
      while (merged.length <= i) {
        merged.add(-1);
      }
      if (t[i] >= 0) merged[i] = t[i];
    }
    _resolveAll(es, _Ctx(controller: ctx.controller, source: ctx.source, loc: ctx.loc, targets: merged, event: ctx.event));
  }

  String _payLabel(PayKind k) => switch (k) {
        PayRunes(:final energy, :final power, :final exhaustMe) => 'Pay ${energy > 0 ? '{$energy}' : ''}${power.map((d) => '{${d?.letter ?? 'A'}}').join()}${exhaustMe ? ' and exhaust it' : ''}',
        PayXp(:final n) => 'Spend $n XP',
        PayBuff() => 'Spend a buff',
        PayKillGear() => 'Kill a gear',
        PayDisempower() => 'Disempower something you control',
        PayEffect(:final effect) => describeEffect(effect),
      };

  bool _canPayKind(int p, PayKind k, _Ctx ctx) => switch (k) {
        PayRunes(:final energy, :final power, :final exhaustMe) => canPay(p, energy, power) && (!exhaustMe || !(state.objOrNull(ctx.source)?.exhausted ?? true)),
        PayXp(:final n) => state.player(p).pw.xp >= n,
        PayBuff() => units(player: p).any((u) => state.obj(u).buffed),
        PayKillGear() => [...gearOf(0), ...gearOf(1)].isNotEmpty,
        PayDisempower() => _empoweredOf(p).isNotEmpty,
        PayEffect() => true,
      };

  List<ObjId> _empoweredOf(int p) => [
        ?(state.player(p).legend != null && state.obj(state.player(p).legend!).pw.empowered > 0 ? state.player(p).legend : null),
        for (final o in _boardOf(p))
          if (o.pw.empowered > 0) o.id,
      ];

  /// Pays [k]; false if nothing was paid.
  bool _payKind(int p, PayKind k, _Ctx ctx) {
    switch (k) {
      case PayRunes(:final energy, :final power, :final exhaustMe):
        _pay(p, energy, power);
        if (exhaustMe) state.obj(ctx.source).exhausted = true;
        return true;
      case PayXp(:final n):
        state.player(p).pw.xp -= n;
        log('${playerName(p)} spends $n XP.', player: p, kind: 'xp');
        return true;
      case PayBuff():
        final options = [for (final u in units(player: p)) if (state.obj(u).buffed) u];
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: choose a unit whose buff to spend', options: options, source: ctx.source));
        return _spendBuff(pick.first, p);
      case PayKillGear():
        final options = [...gearOf(p), ...gearOf(state.other(p))];
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: choose a gear to kill', options: options, source: ctx.source));
        _kill(pick.first);
        return true;
      case PayDisempower():
        final options = _empoweredOf(p);
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: choose something of yours to disempower', options: options, source: ctx.source));
        return _disempower(pick.first);
      case PayEffect(:final effect):
        return _doCounting(effect, ctx);
    }
  }

  /// Does [e] and says whether it did anything ("If you do", CR 205).
  bool _doCounting(Effect e, _Ctx ctx) {
    switch (e) {
      case Kill(:final target):
        final ids = _resolveTarget(target, ctx);
        for (final id in ids) {
          log('${nameOf(id)} is killed.', player: ctx.controller, card: id, kind: 'die');
          _kill(id);
        }
        return ids.isNotEmpty;
      case BanishFromTrash():
        return _banishFromTrash(ctx.controller, ctx.source);
      default:
        _resolve(e, ctx);
        return true;
    }
  }

  bool _banishFromTrash(int p, ObjId source, {bool unitsOnly = true}) {
    final pl = state.player(p);
    final options = [for (final id in pl.trash) if (!unitsOnly || card(id).type == CardType.unit) id];
    if (options.isEmpty) return false;
    final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: choose a unit in your trash to banish', options: options, source: source));
    final id = pick.first;
    pl.trash.remove(id);
    state.obj(id).zone = Zone.banish;
    pl.banish.add(id);
    log('${playerName(p)} banishes ${nameOf(id)} from the trash.', player: p, card: id, kind: 'info');
    _firePw(On.youBanishOwn, player: p);
    return true;
  }

  /// Banishes permanent [id] (CR 428).
  void _banishPermanent(ObjId id, int by) {
    final o = state.obj(id);
    log('${nameOf(id)} is banished.', player: by, card: id, kind: 'die');
    final owner = o.owner;
    o.reset();
    if (card(id).token) {
      o.zone = Zone.gone;
      return;
    }
    o.zone = Zone.banish;
    state.player(owner).banish.add(id);
    if (owner == by) _firePw(On.youBanishOwn, player: by);
  }

  /// Burn [n] from [p]'s Main Deck (CR 441): burn out and carry on when it runs dry.
  void _burn(int p, int n) {
    final pl = state.player(p);
    var done = 0;
    for (var i = 0; i < n; i++) {
      if (pl.deck.isEmpty) {
        _burnOut(p);
        if (state.over || pl.deck.isEmpty) break;
      }
      final id = pl.deck.removeAt(0);
      state.obj(id).zone = Zone.trash;
      pl.trash.add(id);
      done++;
    }
    log('${pl.name} burns $done.', player: p, kind: 'info', amount: done);
  }

  /// Plays unit [id] (from a trash) for [p], ignoring its cost; to [p]'s base or a battlefield
  /// they control (CR 355.2.a), or [toBase].
  void _playUnitFree(int p, ObjId id, ObjId source, {bool toBase = false}) {
    final o = state.obj(id);
    state.player(o.owner).trash.remove(id);
    var loc = base;
    if (!toBase) {
      final options = [base, for (var i = 0; i < state.bfs.length; i++) if (state.bfs[i].controller == p) i];
      if (options.length > 1) loc = options[ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Play ${nameOf(id)} where?', labels: [for (final l in options) locName(l, p)], source: source)).first];
    }
    final passives = [for (final a in parsed(id).abilities) if (a is Static && a.gate == null) a.passive];
    _enterBoard(id, p, loc, ready: passives.any((x) => x is EntersReady));
    log('${playerName(p)} plays ${nameOf(id)} from a trash.', player: p, card: id, kind: 'play');
    _firePlayed(id);
    _fire(On.youPlayUnit, player: p);
    _unitPlayed(id, p);
    _firePw(On.youPlayNotFromHand, player: p);
  }

  void _resolvePower(PowerEffect e, _Ctx ctx) {
    final p = ctx.controller;
    switch (e) {
      case EmpowerMe():
        if (state.objOrNull(ctx.source) != null) _empower(ctx.source, p);
      case Empower(:final target, :final off, :final untilEndOfTurn):
        final ids = target is Choose && (target.filter.pw?.legends ?? false) ? [if (ctx.targets.length > target.slot && ctx.targets[target.slot] >= 0) ctx.targets[target.slot]] : _resolveTarget(target, ctx);
        for (final id in ids) {
          if (state.objOrNull(id) == null) continue;
          final done = off ? _disempower(id) : _empower(id, p);
          if (done && untilEndOfTurn) state.pw.delayed.add(DelayedPower(off ? 'empowerAtEnd' : 'disempowerAtEnd', controller: p, source: ctx.source, unit: id, turn: state.turn));
        }
      case GainXp(:final amount):
        gainXp(p, _amount(amount, ctx));
      case BuffUpTo(:final n, :final filter):
        final options = matching(filter, controller: p, source: ctx.source, here: ctx.loc);
        if (options.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: choose up to $n units to buff', options: options, min: 0, max: n < options.length ? n : options.length, source: ctx.source));
        for (final id in pick) {
          _buffUnit(id, p);
        }
      case PayToDo(:final pay, :final effects, :final optional):
        if (!_canPayKind(p, pay, ctx)) return;
        if (optional && !askYesNo(p, '${nameOf(ctx.source)}: ${_payLabel(pay)} to ${effects.map(describeEffect).join(', ')}?', source: ctx.source)) return;
        if (!_payKind(p, pay, ctx)) return;
        _resolveAll(effects, ctx);
      case InsteadIf(:final cond, :final normal, :final instead):
        _resolveAll(_cond(cond, ctx) ? instead : normal, ctx);
      case SpendBuffsEach(:final effects):
        final options = [for (final u in units(player: p)) for (var i = 0; i < _buffs(u); i++) u];
        if (options.isEmpty) return;
        final distinct = <int>[];
        for (final u in options) {
          if (!distinct.contains(u)) distinct.add(u);
        }
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: choose units whose buffs to spend', options: distinct, min: 0, max: distinct.length, source: ctx.source));
        for (final u in pick) {
          if (_spendBuff(u, p)) _resolveAll(effects, ctx);
        }
      case SpendEachBuffToReady():
        for (final u in units(player: p)) {
          if (!state.obj(u).buffed) continue;
          if (askYesNo(p, 'Spend ${nameOf(u)}’s buff to ready it?', source: ctx.source) && _spendBuff(u, p)) state.obj(u).exhausted = false;
        }
      case SpendBuffOf(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          _spendBuff(id, p);
        }
      case Banish(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          _banishPermanent(id, p);
        }
      case BanishFromTrash(:final unitsOnly):
        _banishFromTrash(p, ctx.source, unitsOnly: unitsOnly);
      case Burn(:final n, :final opponent):
        _burn(opponent ? state.other(p) : p, n);
      case MightUpTo(:final slot):
        final other = _chosen(slot, ctx);
        final me = state.objOrNull(ctx.source);
        if (other == null || me == null || me.zone != Zone.board) return;
        final diff = might(other) - might(ctx.source);
        if (diff > 0) {
          me.mightMod += diff;
          log('${nameOf(ctx.source)}’s Might rises to ${might(ctx.source)} this turn.', player: p, card: ctx.source, kind: 'buff');
        }
      case BaseMightBecomes(:final n, :final target):
        for (final id in _resolveTarget(target, ctx)) {
          if (!isUnit(id)) continue;
          state.obj(id).mightMod += n - (card(id).might ?? 0);
          log('${nameOf(id)}’s base Might becomes $n this turn.', player: p, card: id, kind: 'buff');
        }
      case Delayed(:final kind, :final target, :final n):
        final unit = target == null ? -1 : (_resolveTarget(target, ctx).firstOrNull ?? -1);
        state.pw.delayed.add(DelayedPower(kind, controller: p, source: ctx.source, unit: unit, n: n, turn: state.turn));
      case GrantFlow():
        final spells = [for (final id in state.player(p).trash) if (card(id).type == CardType.spell) id];
        if (spells.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: give a spell in your trash Flow this turn', options: spells, source: ctx.source));
        state.obj(pick.first).pw.flowGrantedTurn = state.turn;
        log('${nameOf(pick.first)} gains Flow this turn.', player: p, card: pick.first, kind: 'info');
      case PowerToken(:final token, :final count):
        for (var i = 0; i < count; i++) {
          final id = _newObj(token, p, Zone.board);
          _enterBoard(id, p, base, ready: false);
        }
        log('${playerName(p)} plays $count $token token${count == 1 ? '' : 's'}.', player: p, kind: 'play');
      case LookDraw(:final n, :final unitsOnly, :final restToTrash, :final reveal, :final thenIfTags, :final then):
        final deck = state.player(p).deck;
        final top = deck.take(n).toList();
        if (top.isEmpty) return;
        final options = [for (final id in top) if (!unitsOnly || card(id).type == CardType.unit) id];
        final pick = options.isEmpty ? const <int>[] : ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: choose ${unitsOnly ? 'a unit' : 'a card'} to ${reveal ? 'reveal and ' : ''}draw', options: options, min: 0, max: 1, source: ctx.source));
        for (final id in top) {
          deck.remove(id);
        }
        if (pick.isNotEmpty) {
          state.obj(pick.first).zone = Zone.hand;
          state.player(p).hand.add(pick.first);
          log('${playerName(p)} ${reveal ? 'reveals and ' : ''}draws ${reveal ? nameOf(pick.first) : 'a card'}.', player: p, card: reveal ? pick.first : null, kind: 'draw');
        }
        final rest = [for (final id in top) if (!pick.contains(id)) id];
        if (restToTrash) {
          for (final id in rest) {
            state.obj(id).zone = Zone.trash;
            state.player(p).trash.add(id);
          }
        } else if (rest.isNotEmpty) {
          for (final id in rest) {
            state.obj(id).zone = Zone.mainDeck;
            deck.add(id);
          }
          // Recycling them in random order (CR 417.5): shuffle the recycled ones at the bottom.
          final bottom = deck.sublist(deck.length - rest.length);
          state.rng.shuffle(bottom);
          deck.replaceRange(deck.length - rest.length, deck.length, bottom);
          _recycled(p);
        }
        if (pick.isNotEmpty && thenIfTags.isNotEmpty && thenIfTags.any(card(pick.first).hasTag)) _resolveChoosingNow(then, ctx);
      case PlayFromTrash(:final opponentsTrash, :final maxEnergy, :final maxPower):
        final from = opponentsTrash ? state.other(p) : p;
        final options = [
          for (final id in state.player(from).trash)
            if (card(id).type == CardType.unit && (maxEnergy == null || card(id).energy <= maxEnergy) && (maxPower == null || card(id).power <= maxPower)) id,
        ];
        if (options.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: choose a unit in ${opponentsTrash ? 'their' : 'your'} trash to play', options: options, min: 0, max: 1, source: ctx.source));
        if (pick.isEmpty) return;
        _playUnitFree(p, pick.first, ctx.source, toBase: !opponentsTrash);
      case RevealHand(:final payXpDiscard, :final xp):
        final o = state.other(p);
        final hand = state.player(o).hand;
        log('${playerName(o)} reveals their hand: ${hand.isEmpty ? 'nothing' : hand.map(nameOf).join(', ')}.', player: o, kind: 'info');
        if (payXpDiscard > 0 && hand.isNotEmpty && state.player(p).pw.xp >= payXpDiscard && askYesNo(p, 'Spend $payXpDiscard XP to choose a card from ${playerName(o)}’s hand for them to discard?', source: ctx.source)) {
          state.player(p).pw.xp -= payXpDiscard;
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose a card for ${playerName(o)} to discard', options: List.of(hand), source: ctx.source));
          hand.remove(pick.first);
          state.obj(pick.first).zone = Zone.trash;
          state.player(o).trash.add(pick.first);
          log('${playerName(o)} discards ${nameOf(pick.first)} and draws 1.', player: o, kind: 'discard');
          _draw(o, 1);
        }
        gainXp(p, xp);
      case EachKillsOne(:final notYouIfPaid):
        for (var i = 0; i < state.players.length; i++) {
          final q = (p + i) % state.players.length;
          if (notYouIfPaid && q == p && _hMarked('t:paid:${ctx.source}')) continue;
          final mine = units(player: q);
          if (mine.isEmpty) continue;
          final pick = ask(Decision(kind: DecisionKind.cards, player: q, prompt: '${nameOf(ctx.source)}: choose one of your units to sacrifice', options: mine, source: ctx.source));
          log('${nameOf(pick.first)} is killed.', player: q, card: pick.first, kind: 'die');
          _kill(pick.first);
        }
      case MoveAny(:final target, :final toBattlefield, :final whereYouHaveUnits):
        for (final id in _resolveTarget(target, ctx)) {
          if (!isUnit(id)) continue;
          final from = state.obj(id).loc;
          final dests = <int>[
            if (!toBattlefield && !whereYouHaveUnits && from != base) base,
            for (var i = 0; i < state.bfs.length; i++)
              if (i != from && (!whereYouHaveUnits || unitsAt(i, player: p).isNotEmpty)) i,
          ];
          if (dests.isEmpty) continue;
          final to = dests[ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Move ${nameOf(id)} where?', labels: [for (final d in dests) locName(d, state.obj(id).controller)], source: ctx.source)).first];
          _moveUnits([id], to, p);
        }
      case StareDown(:final slot):
        final mine = _chosen(slot, ctx);
        if (mine == null || state.bfs.isEmpty) return;
        final bf = ask(Decision(kind: DecisionKind.option, player: p, prompt: '${nameOf(ctx.source)}: choose a battlefield', labels: [for (final b in state.bfs) nameOf(b.obj)], source: ctx.source)).first;
        final m = mightUsed(mine);
        final weaker = [for (final u in unitsAt(bf, player: state.other(p))) if (mightUsed(u) < m) u];
        if (weaker.isNotEmpty) _moveUnits(weaker, base, p);
      case SplitMightDamage(:final slot, :final xpPerKill):
        final from = _chosen(slot, ctx);
        if (from == null) return;
        final enemies = [for (final u in units(player: state.other(p))) if (state.obj(u).loc != base && !_noDamage(u)) u];
        // The engine splits the damage for the player, killing as many units as it can (as in
        // combat, CR 467.2.c).
        final split = _assign(mightUsed(from), enemies);
        var kills = 0;
        for (final e in split.entries) {
          if (e.value <= 0) continue;
          state.obj(e.key).damage += e.value;
          log('${nameOf(from)} deals ${e.value} to ${nameOf(e.key)}.', player: p, card: e.key, kind: 'damage', amount: e.value);
          if (state.obj(e.key).damage >= might(e.key)) kills++;
        }
        gainXp(p, kills * xpPerKill);
      case OneOf(:final options):
        final a = ask(Decision(kind: DecisionKind.option, player: p, prompt: '${nameOf(ctx.source)}: choose one', labels: [for (final o in options) o.map(describeEffect).join(', ')], source: ctx.source)).first;
        _resolveAll(options[a], ctx);
      case Untargetable(:final target):
        for (final id in _resolveTarget(target, ctx)) {
          state.obj(id).pw.untargetableTurn = state.turn;
        }
      case GiveKwAll(:final kw, :final n, :final filter):
        for (final id in matching(filter, controller: p, source: ctx.source, here: ctx.loc)) {
          final m = state.obj(id).kwMod;
          m[kw.index] = (m[kw.index] ?? 0) + n;
        }
      case ReadyGear(:final n):
        final options = [for (final g in gearOf(p)) if (state.obj(g).exhausted) g];
        if (options.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: choose up to $n gear to ready', options: options, min: 0, max: n < options.length ? n : options.length, source: ctx.source));
        for (final g in pick) {
          state.obj(g).exhausted = false;
        }
      case GiveMightAll(:final n, :final filter):
        _powerTargetsOf[this] = ctx.targets;
        for (final id in matching(filter, controller: p, source: ctx.source, here: ctx.loc)) {
          state.obj(id).mightMod += n;
        }
      case PickIt():
        break;
      case LookBanishPlay(:final n, :final energyLess, :final empowerAfter):
        final deck = state.player(p).deck;
        final top = deck.take(n).toList();
        if (top.isEmpty) return;
        for (final id in top) {
          deck.remove(id);
        }
        // Only what can be paid for (Energy {N} less) can be chosen to play.
        final options = [
          for (final id in top)
            if ((card(id).type == CardType.unit || card(id).type == CardType.gear) && RiftboundParser.parse(card(id)).supported && _canPayReduced(p, id, energyLess)) id,
        ];
        final pick = options.isEmpty ? const <int>[] : ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: choose a unit or gear to banish and play for {$energyLess} less', options: options, min: 0, max: 1, source: ctx.source));
        final rest = [for (final id in top) if (!pick.contains(id)) id];
        for (final id in rest) {
          state.obj(id).zone = Zone.mainDeck;
          deck.add(id);
        }
        if (rest.isNotEmpty) {
          final bottom = deck.sublist(deck.length - rest.length);
          state.rng.shuffle(bottom);
          deck.replaceRange(deck.length - rest.length, deck.length, bottom);
          _recycled(p);
        }
        if (pick.isEmpty) return;
        final id = pick.first;
        // Banished, then played from banishment (CR 428): pay its cost {N} less.
        state.obj(id).zone = Zone.banish;
        state.player(p).banish.add(id);
        _firePw(On.youBanishOwn, player: p);
        _payReduced(p, id, energyLess);
        state.player(p).banish.remove(id);
        var loc = base;
        if (card(id).type == CardType.unit) {
          final locs = [base, for (var i = 0; i < state.bfs.length; i++) if (state.bfs[i].controller == p) i];
          if (locs.length > 1) loc = locs[ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Play ${nameOf(id)} where?', labels: [for (final l in locs) locName(l, p)], source: ctx.source)).first];
        }
        final passives = [for (final a in parsed(id).abilities) if (a is Static && a.gate == null) a.passive];
        final ready = card(id).type == CardType.gear ? !passives.any((x) => x is EntersExhausted) : passives.any((x) => x is EntersReady);
        _enterBoard(id, p, loc, ready: ready);
        state.player(p).playedThisTurn++;
        log('${playerName(p)} plays ${nameOf(id)} from banishment.', player: p, card: id, kind: 'play');
        _firePlayed(id);
        if (card(id).type == CardType.unit) {
          _fire(On.youPlayUnit, player: p);
          _unitPlayed(id, p);
        }
        _firePw(On.youPlayNotFromHand, player: p);
        if (empowerAfter && askYesNo(p, 'Empower ${nameOf(id)}?', source: ctx.source)) _empower(id, p);
      case GiftMe():
        final o = state.objOrNull(ctx.source);
        if (o == null || o.zone != Zone.board) return;
        final to = ask(Decision(kind: DecisionKind.option, player: p, prompt: '${nameOf(ctx.source)}: who gains control of it?', labels: [for (final pl in state.players) pl.name], source: ctx.source)).first;
        o
          ..controller = to
          ..loc = base;
        log('${playerName(to)} gains control of ${nameOf(ctx.source)}.', player: to, card: ctx.source, kind: 'info');
    }
  }
}
