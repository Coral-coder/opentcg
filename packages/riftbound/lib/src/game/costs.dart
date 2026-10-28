part of 'game.dart';

/// How a card is being played (CR 349–359, 420.3): from where, and with which costs replaced or
/// ignored; plus the choices made while playing it.
class XPlay {
  XPlay({this.effect = false, this.ignoreEnergy = false, this.ignoreAll = false, this.reduceEnergy = 0, this.forCost, this.toBase = false, this.recycleAfter = false, this.elsewhere = false, this.facedown = -1, this.flowed = false, this.at, this.noExtras = false});

  /// Played as part of an effect: no timing check (CR 420.3).
  final bool effect;
  final bool ignoreEnergy, ignoreAll;

  /// "Reduce its Energy cost by …".
  final int reduceEnergy;

  /// "Play … for {A}": replaces the base cost (CR 356.1.a).
  final (int, List<Domain?>)? forCost;
  final bool toBase;
  final bool recycleAfter;

  /// Played from anywhere other than a player's hand.
  final bool elsewhere;

  /// Played from facedown at this battlefield (CR 811), or -1. Its own cost is ignored
  /// ([ignoreAll], CR 811.1.b); additional costs are still paid.
  final int facedown;

  /// Played from the trash with Flow (CR 829): [forCost] is the Flow cost, and the spell is
  /// banished as it finishes.
  final bool flowed;

  /// A unit played by an effect to this location ("They play that unit to that battlefield").
  final int? at;

  /// "Ignoring any and all costs": no additional or optional costs are offered either.
  final bool noExtras;

  // Decided while playing.
  AltCost? alt;
  final List<(AddCost, List<ObjId>)> paying = [];
  int flags = 0;
  int costRef = -1;
  bool entersReady = false;
  bool ignorePaid = false;
  List<int> targets = const [];

  /// An additional cost was paid ("If you paid the additional cost", CR 356.2).
  bool paidAdditional = false;

  /// "You may play me to its battlefield": where the unit killed for the cost was, or base.
  int killedBf = base;

  /// How many choices the spell makes (for discounts decided by them).
  int slotTotal = 0;

  /// Before targets are chosen: assume the discounts that depend on them (Irelia, Sandswept
  /// Tomb, "if you choose a …") will apply.
  bool optimistic = false;

  /// A battlefield whose [RoostCost] is paid: the unit is played there.
  int roostBf = -1;
  List<Domain?> roostPower = const [];

  /// Optional additional costs chosen so far (Accelerate, Repeat), for discounts (CR 356.4.c).
  final List<(int, List<Domain?>)> optional = [];

  XPlay copy() => XPlay(effect: effect, ignoreEnergy: ignoreEnergy, ignoreAll: ignoreAll, reduceEnergy: reduceEnergy, forCost: forCost, toBase: toBase, recycleAfter: recycleAfter, elsewhere: elsewhere, facedown: facedown, flowed: flowed, at: at, noExtras: noExtras);
}

/// What happened this turn for one player, and effects lasting until its end ("the next spell
/// costs {5} less", spells played, Energy spent on spells, …): kept in [GameState.marks] as
/// "t:x:<player>:<name>", so they end with the turn's other marks.
/// While a spell's targets are chosen: may these choices (by slot) be made? (Only those that
/// leave it affordable.)
final _xAllow = Expando<bool Function(List<int>)>();

class _TurnMarks {
  _TurnMarks(this.marks, this.p);
  final Map<String, int> marks;
  final int p;
  int? operator [](String k) => marks['t:x:$p:$k'];
  void operator []=(String k, int v) => marks['t:x:$p:$k'] = v;
  int? remove(String k) => marks.remove('t:x:$p:$k');
}

/// Additional and alternative costs, cost changes, modes and playing cards from elsewhere.
extension GameCosts on Game {
  _TurnMarks _turn(Player pl) => _TurnMarks(state.marks, state.players.indexOf(pl));

  /// What playing [id] would cost [p] now (Flow from the trash, discounts and increases
  /// included, optional costs not): the first way they can pay, else the first way.
  ({int energy, List<Domain?> power}) playCost(int p, ObjId id) {
    var x = XPlay();
    try {
      x = _xPlayFromMove(p, id);
    } on RiftboundError {
      // Not playable from where it is: what it would cost from hand.
    }
    final t = _xPayable(p, id, x) ?? _xTotals(p, id, x).first;
    return (energy: t.$1, power: t.$2);
  }

  /// Would [p] play [id] from the trash with Flow (CR 829: banished afterwards)?
  bool playsWithFlow(int p, ObjId id) => _flowPlayable(p, id);

  // -------------------------------------------------------------------------------------------
  // Where a card can be played from
  // -------------------------------------------------------------------------------------------

  /// A Play move's card: from hand or the Champion Zone; facedown at a battlefield (CR 811); from
  /// the trash with Flow (CR 829) or an alternative cost that allows it ("You may play me from
  /// your trash for {3}{R}").
  XPlay _xPlayFromMove(int p, ObjId id) {
    final pl = state.player(p);
    final o = state.obj(id);
    if (o.owner == p && (pl.hand.contains(id) || pl.champion == id)) return XPlay();
    if (o.owner == p && o.zone == Zone.facedown) return XPlay(facedown: o.loc, ignoreAll: true);
    final flow = _flowCost(p, id);
    if (flow != null) return XPlay(forCost: (flow.energy, flow.power), elsewhere: true, flowed: true);
    if (o.owner == p && o.zone == Zone.trash && pl.trash.contains(id)) {
      for (final a in parsed(id).abilities) {
        if (a is Static && a.passive is AltCost && (a.passive as AltCost).fromTrash) {
          final alt = a.passive as AltCost;
          if (alt.legion && pl.playedThisTurn < 1) throw RiftboundError('Legion: play another card this turn first');
          return XPlay(forCost: (alt.energy, alt.power), elsewhere: true);
        }
      }
    }
    throw RiftboundError('That card isn’t in your hand');
  }

  /// Cards [seat] may play from the trash (for the list of moves): Flow, or an alternative cost.
  List<ObjId> _xExtraPlayable(int seat) => [
        for (final id in state.player(seat).trash)
          if (_flowPlayable(seat, id) || parsed(id).abilities.any((a) => a is Static && a.passive is AltCost && (a.passive as AltCost).fromTrash)) id,
      ];

  /// Takes a card out of whatever zone it's in (it's being played by [p] as [x]). A Flow spell
  /// is marked to be banished (CR 829.1.b); "When you play a card from anywhere other than your
  /// hand" triggers.
  void _xLeaveOrigin(int p, ObjId id, XPlay x) {
    final o = state.obj(id);
    final pl = state.player(o.owner);
    pl.hand.remove(id);
    pl.trash.remove(id);
    pl.banish.remove(id);
    pl.deck.remove(id);
    if (pl.champion == id) pl.champion = null;
    if (x.flowed) {
      o.pw.flowed = true;
      log('${playerName(p)} plays ${nameOf(id)} from the trash with Flow.', player: p, card: id, kind: 'play');
    }
    if (x.elsewhere) _firePw(On.youPlayNotFromHand, player: p);
  }

  // -------------------------------------------------------------------------------------------
  // Total cost (CR 356)
  // -------------------------------------------------------------------------------------------

  /// Removes up to [n] Power symbols of [d] (null: any symbols, "any" ones first) from [pw].
  void _xLessPower(List<Domain?> pw, Domain? d, int n) {
    for (var i = 0; i < n; i++) {
      if (d != null) {
        final j = pw.indexOf(d);
        if (j < 0) return;
        pw.removeAt(j);
      } else {
        if (pw.isEmpty) return;
        final j = pw.indexOf(null);
        pw.removeAt(j >= 0 ? j : pw.length - 1);
      }
    }
  }

  /// Cost changes from other permanents, legends and battlefields, with their source.
  List<(ObjId, CostMod)> _xCostMods() {
    final out = <(ObjId, CostMod)>[];
    for (final o in state.objects.values) {
      if (o.zone != Zone.board && o.zone != Zone.legend && o.zone != Zone.battlefield) continue;
      for (final a in parsed(o.id).abilities) {
        if (a is Static && a.passive is CostMod) out.add((o.id, a.passive as CostMod));
      }
    }
    return out;
  }

  /// Does a battlefield-based change apply for [p] ("while you control this battlefield")?
  bool _xControls(int p, ObjId bfObj) => state.bfs.any((b) => b.obj == bfObj && b.controller == p);

  int _xBfIndex(ObjId bfObj) => state.bfs.indexWhere((b) => b.obj == bfObj);

  /// What a variable discount counts (CR 356.4.g).
  int _xCount(int p, XPer per, RCard c) {
    final pl = state.player(p);
    return switch (per) {
      XPer.cardsPlayedThisTurn => pl.playedThisTurn,
      XPer.mightyUnits => units(player: p).where((u) => mightUsed(u) >= 5).length,
      XPer.gearYouControl => gearOf(p).length,
      XPer.cardsInTrash => pl.trash.length,
      XPer.sameNameInTrash => pl.trash.where((id) => state.obj(id).card == c.key).length,
      XPer.holdPointsThisTurn => _turn(pl)['holdPts'] ?? 0,
      XPer.friendlyTemporaryUnits => units(player: p).where((u) => hasKw(u, Kw.temporary)).length,
      XPer.highestMight => units(player: p).fold<int>(0, (m, u) => mightUsed(u) > m ? mightUsed(u) : m),
      XPer.tagKinds => 0,
    };
  }

  /// How many of [tags] are among [p]'s units.
  int _xTagKinds(int p, List<String> tags) => tags.where((t) => units(player: p).any((u) => card(u).hasTag(t))).length;

  /// Conditions checked as a cost is determined, for [p] playing or controlling [source].
  bool _xCondNow(int p, Cond c, {ObjId? source}) {
    final o = state.other(p);
    return switch (c) {
      ControlBfWithUnits(:final n) => [for (var i = 0; i < state.bfs.length; i++) i].any((i) => state.bfs[i].controller == p && unitsAt(i).length == n),
      OpponentStunned() => units(player: o).any((u) => state.obj(u).stunned),
      EnemyDiedThisTurn() => (_turn(state.player(p))['enemyDied'] ?? 0) > 0,
      SpentOnSpell(:final n) => (_turn(state.player(p))['spellSpent'] ?? 0) >= n,
      AllTags(:final tags) => _xTagKinds(p, tags) == tags.length,
      PowerCond() => _powerCondEval(c, _Ctx(controller: p, source: source ?? -1, loc: source == null ? base : state.obj(source).loc, targets: const [])),
      HCond() => _hCond(c, _Ctx(controller: p, source: source ?? -1, loc: source == null ? base : state.obj(source).loc, targets: const [])),
      _ => false,
    };
  }

  /// The card a spell chose to play (Undying Loyalty), for "if you choose a …".
  ObjId? _xChosenPlay(ObjId id, List<int> targets) {
    for (final a in parsed(id).abilities) {
      if (a is! SpellBody) continue;
      for (final e in a.effects) {
        if (e is PlayFrom && e.slot >= 0 && e.slot < targets.length && targets[e.slot] >= 0) return targets[e.slot];
      }
    }
    return null;
  }

  /// The total costs [p] could pay to play [id] as [x] says, best first (CR 356): base cost
  /// (replaced or ignored), additional costs, increases, discounts. One entry per domain a
  /// multi-domain card's Power could be paid with, and per way to take "{1} or {A} less".
  List<(int, List<Domain?>)> _xTotals(int p, ObjId id, XPlay x, {List<Domain?> mandatory = const []}) {
    final c = card(id);
    final pl = state.player(p);
    final out = <(int, List<Domain?>)>[];
    final doms = c.domains.length > 1 ? c.domains : <Domain?>[c.domains.isEmpty ? null : c.domains.first];
    final mods = _xCostMods();
    final isSpell = c.type == CardType.spell;
    for (final d in doms) {
      for (final preferPower in const [false, true]) {
        // 1. Base cost (CR 356.1).
        int e;
        List<Domain?> pw;
        final fc = x.forCost;
        if (fc != null) {
          e = fc.$1;
          pw = List.of(fc.$2);
        } else if (x.alt != null) {
          e = x.alt!.energy;
          pw = List.of(x.alt!.power);
        } else {
          e = energyCost(p, c);
          pw = List.filled(c.power, d, growable: true);
        }
        if (x.ignoreAll || x.ignorePaid || x.paying.any((q) => q.$1.ignoreCost)) {
          e = 0;
          pw = [];
        }
        if (x.ignoreEnergy || _xFreeGear(p, id, x)) e = 0;
        // "{1} or {A} less" (CR 356.4): Energy, or a Power symbol when [preferPower].
        void orLess(int n, List<Domain?> into, void Function(int) setE, int curE) {
          if (preferPower && into.isNotEmpty) {
            _xLessPower(into, null, 1);
          } else {
            setE(curE - n < 0 ? 0 : curE - n);
          }
        }

        // 2. Additional costs (CR 356.2), each optional one discounted by Ezreal (CR 356.4.c).
        final optional = <(int, List<Domain?>)>[
          ...x.optional,
          for (final (ac, _) in x.paying)
            if (ac.pay == XPay.resources && ac.optional) (ac.energy, ac.power),
          if (x.roostBf >= 0) (0, x.roostPower),
        ];
        for (final (oe, op) in optional) {
          var ce = oe;
          final cp = List.of(op);
          for (final (src, m) in mods) {
            if (m.who == XWho.optionalCosts && state.obj(src).controller == p && state.obj(src).zone != Zone.battlefield) orLess(m.energy, cp, (v) => ce = v, ce);
          }
          e += ce;
          pw.addAll(cp);
        }
        for (final a in parsed(id).abilities) {
          if (a is Static && a.passive is AddCost && (a.passive as AddCost).pay == XPay.resources && !(a.passive as AddCost).optional) {
            e += (a.passive as AddCost).energy;
            pw.addAll((a.passive as AddCost).power);
          }
        }
        pw.addAll(mandatory);
        // 3. Increases (CR 356.3).
        final pm = _powerCostMore(p, c, e, pw);
        e = pm.energy;
        pw = pm.power;
        final more = _turn(pl)['unitsMore'] ?? 0;
        if (more > 0 && c.type == CardType.unit && !c.token) e += more;
        for (final (src, m) in mods) {
          if (!m.more) continue;
          if (m.who == XWho.reactionsInShowdownHere && parsed(id).has(Kw.reaction)) {
            final i = _xBfIndex(src);
            if (i >= 0 && state.showdown?.bf == i) {
              e += m.energy;
              pw.addAll(m.power);
            }
          }
        }
        // 4. Discounts (CR 356.4).
        final pl0 = _powerCostLess(p, c, e, pw, flowed: x.flowed);
        e = pl0.energy;
        pw = pl0.power;
        for (final a in parsed(id).abilities) {
          if (a is! Static || a.passive is! SelfCost) continue;
          final sc = a.passive as SelfCost;
          if (sc.elsewhere && !x.elsewhere) continue;
          if (sc.cond != null && !_xCondNow(p, sc.cond!, source: id)) continue;
          if (sc.choosesTags.isNotEmpty) {
            final chosen = _xChosenPlay(id, x.targets);
            if (chosen == null ? !_xUndecided(x) : !sc.choosesTags.any(card(chosen).hasTag)) continue;
          }
          final k = sc.per == null ? 1 : (sc.per == XPer.tagKinds ? _xTagKinds(p, sc.perTags) : _xCount(p, sc.per!, c));
          if (k <= 0) continue;
          final less = sc.energy * k;
          if (e > sc.min) e = e - less < sc.min ? sc.min : e - less;
          for (final sym in sc.power) {
            _xLessPower(pw, sym, k);
          }
        }
        for (final (ac, objs) in x.paying) {
          if (ac.discount > 0) e -= ac.discount;
          if (ac.discountEach != null) _xLessPower(pw, ac.discountEach, objs.length);
          if (ac.discountByKilled != null && objs.isNotEmpty) {
            final k = card(objs.first);
            e -= k.energy;
            _xLessPower(pw, ac.discountByKilled, k.power);
          }
        }
        if (isSpell && (_turn(pl)['nextSpell'] ?? 0) > 0) e -= _turn(pl)['nextSpell']!;
        if ((_turn(pl)['nextCardE'] ?? 0) > 0) e -= _turn(pl)['nextCardE']!;
        if ((_turn(pl)['nextCardP'] ?? 0) > 0) _xLessPower(pw, null, _turn(pl)['nextCardP']!);
        if (x.reduceEnergy > 0) e -= x.reduceEnergy;
        for (final (src, m) in mods) {
          if (m.more) continue;
          final so = state.obj(src);
          switch (m.who) {
            case XWho.firstGear:
              if (c.type == CardType.gear && !c.token && _xControls(p, src) && (_turn(pl)['gearPlayed'] ?? 0) == 0) e -= m.energy;
            case XWho.spellsWhileAtBattlefield:
              if (isSpell && so.zone == Zone.board && so.controller == p && so.loc != base && e > m.min) e = e - m.energy < m.min ? m.min : e - m.energy;
            case XWho.yourTagged:
              if ((so.zone == Zone.board || so.zone == Zone.legend) && so.controller == p && m.tag != null && c.hasTag(m.tag!) && e > m.min) e = e - m.energy < m.min ? m.min : e - m.energy;
            case XWho.friendlySpellsInCombat:
              if (!isSpell || so.zone != Zone.board || !(isAttacking(src) || isDefending(src))) break;
              if (so.controller == p) {
                if (e > m.min) e = e - m.energy < m.min ? m.min : e - m.energy;
                for (final sym in m.power) {
                  _xLessPower(pw, sym, 1);
                }
              } else {
                // "… and enemy spells cost {1}{A} more" (an increase; CR 356.3).
                e += m.energy;
                pw.addAll(m.power);
              }
            case XWho.spellsChoosingMe:
              if (isSpell && so.zone == Zone.board && so.controller == p && (x.targets.contains(src) || _xUndecided(x))) orLess(m.energy, pw, (v) => e = v, e);
            case XWho.spellsChoosingFriendlyHere:
              final i = _xBfIndex(src);
              final chosenHere = x.targets.any((t) => t >= 0 && state.objOrNull(t)?.zone == Zone.board && isUnit(t) && state.obj(t).loc == i && state.obj(t).controller == p);
              if (isSpell && i >= 0 && (chosenHere || (_xUndecided(x) && unitsAt(i, player: p).isNotEmpty))) {
                for (final sym in m.power) {
                  _xLessPower(pw, sym, 1);
                }
              }
            default:
              break;
          }
        }
        // CR 356.6.
        if (e < 0) e = 0;
        if (!out.any((v) => v.$1 == e && _sameSyms(v.$2, pw))) out.add((e, pw));
      }
    }
    return out;
  }

  bool _sameSyms(List<Domain?> a, List<Domain?> b) => a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  /// "You may play a gear with Energy cost no more than {7} from hand this turn, ignoring its
  /// Energy cost".
  bool _xFreeGear(int p, ObjId id, XPlay x) {
    final c = card(id);
    final free = _turn(state.player(p))['freeGear'] ?? 0;
    return free > 0 && c.type == CardType.gear && c.energy <= free && !x.elsewhere && state.player(p).hand.contains(id);
  }

  (int, List<Domain?>)? _xPayable(int p, ObjId id, XPlay x, {List<Domain?> mandatory = const []}) {
    final spell = card(id).type == CardType.spell;
    for (final t in _xTotals(p, id, x, mandatory: mandatory)) {
      if (canPay(p, t.$1, t.$2, forSpell: spell, forGear: card(id).type == CardType.gear)) return t;
    }
    return null;
  }

  /// Payable if the discounts that depend on the spell's choices apply (decided once it chooses).
  bool _xOptimisticPayable(int p, ObjId id, XPlay x) {
    final total = x.slotTotal;
    x.optimistic = true;
    if (x.slotTotal == 0) x.slotTotal = _xSlotCount([for (final a in parsed(id).abilities) if (a is SpellBody) ...a.effects]);
    final ok = _xPayable(p, id, x) != null;
    x.optimistic = false;
    x.slotTotal = total;
    return ok;
  }

  /// While a spell is choosing: are some of its choices still to be made, so a discount that
  /// depends on them may yet apply?
  bool _xUndecided(XPlay x) => x.optimistic && (x.targets.length < x.slotTotal || x.targets.contains(-1));

  /// Chooses the targets of spell [id] with [choose], offering only those that leave it
  /// affordable (CR 356: discounts that depend on what it chooses are decided as it chooses).
  List<int> _xChooseAffordable(int p, ObjId id, XPlay x, List<int> Function() choose, {required int slots}) {
    final before = _xAllow[this];
    _xAllow[this] = (partial) {
      final saved = (x.targets, x.optimistic, x.slotTotal);
      x
        ..targets = partial
        ..optimistic = true
        ..slotTotal = slots;
      final ok = _xPayable(p, id, x, mandatory: _xDeflect(p, id, partial)) != null;
      x
        ..targets = saved.$1
        ..optimistic = saved.$2
        ..slotTotal = saved.$3;
      return ok;
    };
    try {
      return choose();
    } finally {
      _xAllow[this] = before;
    }
  }

  /// May [id] be chosen for slot [i] (the targets so far being [out])?
  bool _xAllowed(List<int> out, int i, int id) {
    final allow = _xAllow[this];
    if (allow == null) return true;
    final partial = List.of(out);
    while (partial.length <= i) {
      partial.add(-1);
    }
    partial[i] = id;
    return allow(partial);
  }

  /// Deflect (CR 809): a spell or ability of [p]'s choosing an opponent's Deflect object costs
  /// more Power.
  List<Domain?> _xDeflect(int p, ObjId source, List<int> targets) => [
        for (final tg in targets)
          if (tg >= 0 && state.objOrNull(tg)?.zone == Zone.board && state.obj(tg).controller != p && !_xIgnoreDeflect(source, tg))
            for (var i = 0; i < _kw(tg, Kw.deflect); i++) null,
      ];

  /// Could [p] pay for [id] at all (before making choices)? Mandatory additional costs need
  /// something to pay them with; optional ones aren't assumed.
  bool _xCanPay(int p, ObjId id, XPlay x) {
    for (final a in parsed(id).abilities) {
      if (a is Static && a.passive is AddCost) {
        final ac = a.passive as AddCost;
        if (!ac.optional && _xCostObjects(p, id, ac).length < ac.n) return false;
      }
    }
    if (_xPayable(p, id, x) != null) return true;
    // Discounts that depend on what the spell chooses are decided once it has chosen (CR 356):
    // until then, assume they apply.
    if (card(id).type == CardType.spell && _xOptimisticPayable(p, id, x)) return true;
    // Optional costs that make it cheaper, paid in full (Commander Ledros, Brazen Buccaneer).
    final best = <(AddCost, List<ObjId>)>[];
    for (final a in parsed(id).abilities) {
      if (a is! Static || a.passive is! AddCost) continue;
      final ac = a.passive as AddCost;
      if (!ac.optional || !(ac.discount > 0 || ac.discountEach != null || ac.discountByKilled != null || ac.ignoreCost)) continue;
      final objs = _xCostObjects(p, id, ac);
      if (ac.pay == XPay.xp ? state.player(p).pw.xp < ac.n : objs.length < ac.n) continue;
      if (ac.discountByKilled != null) {
        objs.sortStable((a, b) => card(b).energy + card(b).power - card(a).energy - card(a).power);
      }
      best.add((ac, ac.anyNumber ? objs : objs.take(ac.n).toList()));
    }
    if (best.isNotEmpty) {
      x.paying.addAll(best);
      if (best.any((b) => b.$1.ignoreCost)) x.ignorePaid = true;
      final ok = _xPayable(p, id, x) != null;
      x.paying.clear();
      x.ignorePaid = false;
      if (ok) return true;
    }
    // An alternative cost may be cheaper.
    for (final alt in _xAlts(p, id, x)) {
      x.alt = alt;
      final ok = _xPayable(p, id, x) != null;
      x.alt = null;
      if (ok) return true;
    }
    return false;
  }

  List<AltCost> _xAlts(int p, ObjId id, XPlay x) => [
        if (x.forCost == null && !x.ignoreAll)
          for (final a in parsed(id).abilities)
            if (a is Static && a.passive is AltCost && !(a.passive as AltCost).fromTrash && ((a.passive as AltCost).cond == null || _xCondNow(p, (a.passive as AltCost).cond!, source: id))) a.passive as AltCost,
      ];

  // -------------------------------------------------------------------------------------------
  // Choosing costs (CR 355.1.a) and paying them (CR 357)
  // -------------------------------------------------------------------------------------------

  /// What an additional cost could be paid with.
  List<ObjId> _xCostObjects(int p, ObjId id, AddCost ac) {
    final pl = state.player(p);
    return switch (ac.pay) {
      XPay.resources => const [],
      XPay.discard => [for (final h in pl.hand) if (h != id) h],
      XPay.kill => [
          for (final o in _boardOf(p))
            if ((ac.filter.gear ? card(o.id).type == CardType.gear : isUnit(o.id)) && (ac.tags.isEmpty || ac.tags.any(card(o.id).hasTag)) && (!ac.mighty || mightUsed(o.id) >= 5)) o.id,
        ],
      XPay.exhaustUnit => [for (final u in units(player: p)) if (!state.obj(u).exhausted) u],
      XPay.exhaustLegend => [if (pl.legend != null && !state.obj(pl.legend!).exhausted) pl.legend!],
      // One entry per buff (a unit may have more than one, CR 427.1.b.2).
      XPay.spendBuff => [for (final u in units(player: p)) for (var i = 0; i < _buffs(u); i++) u],
      XPay.returnGear => gearOf(p),
      XPay.xp => const [],
    };
  }

  String _xCostVerb(AddCost ac) => switch (ac.pay) {
        XPay.resources => 'pay {${ac.energy}}${ac.power.map((d) => '{${d?.letter ?? 'A'}}').join()}',
        XPay.discard => 'discard ${ac.n}',
        XPay.kill => 'kill ${ac.anyNumber ? 'any number of friendly units' : (ac.filter.gear ? 'a friendly gear' : 'a friendly unit')}',
        XPay.exhaustUnit => 'exhaust a friendly unit',
        XPay.exhaustLegend => 'exhaust your legend',
        XPay.spendBuff => ac.anyNumber ? 'spend any number of buffs' : 'spend a buff',
        XPay.returnGear => 'return a friendly gear to hand',
        XPay.xp => 'spend ${ac.n} XP',
      };

  /// Step 2 of playing [id] (CR 355.1.a): the alternative cost, and which additional costs to
  /// pay and with what.
  void _xChooseCosts(int p, ObjId id, XPlay x) {
    final c = card(id);
    // Alternative costs ("you may play me for {B}").
    for (final alt in _xAlts(p, id, x)) {
      final normal = _xPayable(p, id, x) != null;
      x.alt = alt;
      if (_xPayable(p, id, x) == null) {
        x.alt = null;
        continue;
      }
      if (normal && !askYesNo(p, 'Cost: play ${c.name} for ${alt.energy > 0 ? '{${alt.energy}}' : ''}${alt.power.map((d) => '{${d?.letter ?? 'A'}}').join()} instead?', source: id)) x.alt = null;
      if (x.alt != null) break;
    }
    for (final a in parsed(id).abilities) {
      if (a is! Static || a.passive is! AddCost) continue;
      final ac = a.passive as AddCost;
      if (ac.ifSpellPlayed && (_turn(state.player(p))['spells'] ?? 0) == 0) continue;
      if (ac.pay == XPay.resources && !ac.optional) {
        // Always paid (counted in the total cost).
      } else if (ac.pay == XPay.resources || ac.pay == XPay.xp) {
        if (ac.pay == XPay.xp && state.player(p).pw.xp < ac.n) continue;
        final freeOk = _xPayable(p, id, x) != null || (c.type == CardType.spell && _xOptimisticPayable(p, id, x));
        x.paying.add((ac, const []));
        final withOk = _xPayable(p, id, x) != null || (c.type == CardType.spell && _xOptimisticPayable(p, id, x));
        if (!withOk || (freeOk && !askYesNo(p, 'Cost: ${_xCostVerb(ac)} as an additional cost to ${c.name}?', source: id))) {
          x.paying.removeLast();
          continue;
        }
      } else {
        var options = _xCostObjects(p, id, ac);
        // A cost that makes the card cheaper may be the only way to afford it (CR 357.3): then
        // it must be paid, with enough (or the right) objects.
        final discounts = ac.discount > 0 || ac.discountEach != null || ac.discountByKilled != null || ac.ignoreCost;
        final freeOk = !discounts || _xPayable(p, id, x) != null || (card(id).type == CardType.spell && _xOptimisticPayable(p, id, x));
        List<ObjId> pick;
        if (ac.anyNumber && ac.pay == XPay.spendBuff) {
          // One buff at a time: a unit may have more than one (CR 427.1.b.2).
          final d = ac.discountEach;
          final useful = d == null ? options.length : (c.domains.contains(d) ? c.power : 0);
          final max = useful < options.length ? useful : options.length;
          final picked = <ObjId>[];
          while (picked.length < max) {
            final left = <ObjId>[];
            for (final u in options) {
              if (!left.contains(u) && options.where((v) => v == u).length > picked.where((v) => v == u).length) left.add(u);
            }
            x.paying.add((ac, picked));
            final must = _xPayable(p, id, x) == null;
            x.paying.removeLast();
            if (left.isEmpty) {
              if (must) throw RiftboundError('Not enough runes (${_costLabel(c)})');
              break;
            }
            final a = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Cost: spend a buff to play ${c.name}${d == null ? '' : ' for {${d.letter}} less'}?${must ? '' : ' (none to stop)'}', options: left, min: must ? 1 : 0, max: 1, source: id));
            if (a.isEmpty) break;
            picked.add(a.first);
          }
          if (picked.isEmpty) continue;
          pick = picked;
        } else if (ac.anyNumber) {
          if (options.isEmpty) continue;
          var need = 0;
          if (!freeOk) {
            need = -1;
            for (var k = 1; k <= options.length; k++) {
              x.paying.add((ac, options.take(k).toList()));
              final ok = _xPayable(p, id, x) != null;
              x.paying.removeLast();
              if (ok) {
                need = k;
                break;
              }
            }
            if (need < 0) throw RiftboundError('Not enough runes (${_costLabel(c)})');
          }
          pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Cost: ${_xCostVerb(ac)} for ${c.name}? (each makes it cheaper)', options: options, min: need, max: options.length, source: id));
          if (pick.isEmpty) continue;
        } else {
          options = options.toSet().toList();
          if (!freeOk) {
            options = [
              for (final o in options)
                if (() {
                  x.paying.add((ac, [o]));
                  final ok = _xPayable(p, id, x) != null;
                  x.paying.removeLast();
                  return ok;
                }())
                  o,
            ];
          }
          if (options.length < ac.n) {
            if (ac.optional && freeOk) continue;
            throw RiftboundError(ac.optional ? 'Not enough runes (${_costLabel(c)})' : 'Can’t pay ${c.name}’s additional cost');
          }
          if (ac.optional && freeOk && !askYesNo(p, 'Cost: ${_xCostVerb(ac)} as an additional cost to ${c.name}?', source: id)) continue;
          pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Cost: choose what to ${_xCostVerb(ac).replaceFirst(RegExp(r'^(a|any number of) '), '')} for ${c.name}', options: options, min: ac.n, max: ac.n, source: id));
        }
        x.paying.add((ac, pick));
        if (ac.pay == XPay.kill && pick.isNotEmpty) {
          x.costRef = pick.first;
          if (ac.toItsBattlefield) x.killedBf = state.obj(pick.first).loc;
        }
      }
      x.paidAdditional = true;
      if (ac.optional) x.flags |= PlayFlags.additional;
      if (ac.ignoreCost) x.ignorePaid = true;
      if (ac.entersReady) x.entersReady = true;
    }
    // Dragon Roost: pay {A}{A} more to play a Dragon to that battlefield.
    if (c.type == CardType.unit && !x.toBase) {
      for (var i = 0; i < state.bfs.length; i++) {
        for (final a in parsed(state.bfs[i].obj).abilities) {
          if (a is! Static || a.passive is! RoostCost) continue;
          final r = a.passive as RoostCost;
          if (!c.hasTag(r.tag)) continue;
          x.roostBf = i;
          x.roostPower = r.power;
          if (_xPayable(p, id, x) == null || !askYesNo(p, 'Cost: pay ${r.power.map((d) => '{${d?.letter ?? 'A'}}').join()} to play ${c.name} to ${nameOf(state.bfs[i].obj)}?', source: id)) {
            x.roostBf = -1;
            x.roostPower = const [];
          }
        }
        if (x.roostBf >= 0) break;
      }
    }
    // Self discounts that also make the unit enter ready (Monch).
    for (final a in parsed(id).abilities) {
      if (a is Static && a.passive is SelfCost) {
        final sc = a.passive as SelfCost;
        if (sc.entersReady && (sc.cond == null || _xCondNow(p, sc.cond!, source: id))) x.entersReady = true;
      }
    }
  }

  /// Steps 3–4 (CR 356–357): the total cost, paid with runes; then the other costs. Returns the
  /// Energy paid.
  int _xPay(int p, ObjId id, XPlay x, {List<Domain?> mandatory = const []}) {
    final t = _xPayable(p, id, x, mandatory: mandatory);
    if (t == null) throw RiftboundError('Not enough runes to pay');
    final c = card(id);
    _pay(p, t.$1, t.$2, forSpell: c.type == CardType.spell, forGear: c.type == CardType.gear);
    final pl = state.player(p);
    // Discounts used up.
    if (c.type == CardType.spell) _turn(pl).remove('nextSpell');
    _turn(pl).remove('nextCardE');
    _turn(pl).remove('nextCardP');
    if (_xFreeGear(p, id, x)) _turn(pl).remove('freeGear');
    for (final (ac, objs) in x.paying) {
      for (final o in objs) {
        switch (ac.pay) {
          case XPay.discard:
            pl.hand.remove(o);
            state.obj(o).zone = Zone.trash;
            pl.trash.add(o);
            log('${pl.name} discards ${nameOf(o)}.', player: p, card: o, kind: 'discard');
            _genDiscarded(p, [o]);
          case XPay.kill:
            log('${nameOf(o)} is killed to play ${c.name}.', player: p, card: o, kind: 'die');
            _kill(o);
          case XPay.exhaustUnit || XPay.exhaustLegend:
            state.obj(o).exhausted = true;
          case XPay.spendBuff:
            _spendBuff(o, p);
          case XPay.returnGear:
            log('${nameOf(o)} returns to its owner’s hand.', player: p, card: o, kind: 'move');
            _leaveBoard(o, toHand: true);
          case XPay.resources || XPay.xp:
            break;
        }
      }
      if (ac.pay == XPay.xp) {
        pl.pw.xp -= ac.n;
        log('${pl.name} spends ${ac.n} XP to play ${c.name}.', player: p, card: id, kind: 'xp');
      }
    }
    return t.$1;
  }

  /// After [id] is played (CR 359): what happened this turn, effects waiting for it, and "when
  /// you play" triggers of this file.
  void _xAfterPlay(int p, ObjId id, XPlay x, int spent) {
    final c = card(id);
    final pl = state.player(p);
    if (c.type == CardType.spell) {
      _turn(pl).remove('nextRepeat');
      _turn(pl)['spells'] = (_turn(pl)['spells'] ?? 0) + 1;
      if (spent > (_turn(pl)['spellSpent'] ?? 0)) _turn(pl)['spellSpent'] = spent;
    }
    if (c.type == CardType.gear && !c.token) _turn(pl)['gearPlayed'] = (_turn(pl)['gearPlayed'] ?? 0) + 1;
    // "If you do, draw 1" on an additional cost (CR 359.2.b).
    for (final (ac, _) in x.paying) {
      if (ac.then.isNotEmpty) _resolveEffects(ac.then, _Ctx(controller: p, source: id, loc: state.obj(id).loc, targets: const []));
    }
    if (c.type == CardType.spell) _xFire(XOn.playSpell, p, n: c.energy);
    _xFire(XOn.playCardPower, p, n: c.power);
    if (c.type == CardType.unit || c.type == CardType.gear) _xFire(XOn.playBig, p, n: c.energy);
    if (pl.playedThisTurn == 1) _xFire(XOn.firstCard, p);
  }

  // -------------------------------------------------------------------------------------------
  // Activated abilities
  // -------------------------------------------------------------------------------------------

  /// The Energy an activated ability costs now (Lillia, Piltovan Forge).
  int _xAbilityEnergy(int p, ObjId src, Activated a, int energy) {
    var e = energy;
    for (final x in a.effects) {
      if (x is AbilityCostLess) e -= x.n * _xCount(p, x.per, card(src));
    }
    if (card(src).type == CardType.gear && (_turn(state.player(p))['gearAbilities'] ?? 0) == 0) {
      for (final (s, m) in _xCostMods()) {
        if (m.who == XWho.firstGearAbility && _xControls(p, s)) e -= m.energy;
      }
    }
    return e < 0 ? 0 : e;
  }

  String? _xCostProblem(int p, ObjId src, Cost cost) {
    for (final part in cost.extra) {
      if (part case RecycleTrash(:final n, :final unit)) {
        final have = state.player(p).trash.where((id) => !unit || card(id).type == CardType.unit).length;
        if (have < n) return 'Not enough cards in your trash';
      }
    }
    return null;
  }

  void _xPayCostExtra(int p, ObjId src, Activated a) {
    for (final part in a.cost.extra) {
      if (part case RecycleTrash(:final n, :final unit)) {
        final options = [for (final id in state.player(p).trash) if (!unit || card(id).type == CardType.unit) id];
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Cost: recycle $n${unit ? ' unit' : ''} from your trash', options: options, min: n, max: n, source: src));
        _recycleCards(p, pick);
        log('${playerName(p)} recycles ${pick.length} from their trash.', player: p, kind: 'info');
      }
    }
    if (card(src).type == CardType.gear) _turn(state.player(p))['gearAbilities'] = (_turn(state.player(p))['gearAbilities'] ?? 0) + 1;
    // "When you play an activated ability with Energy cost {7} or more" checks its base cost (CR 206.1).
    _xFire(XOn.playBig, p, n: a.cost.energy);
  }

  // -------------------------------------------------------------------------------------------
  // Triggers
  // -------------------------------------------------------------------------------------------

  /// Queues "when you …" abilities of this file's events for [p] (permanents, legend, and cards
  /// in the trash that trigger from there).
  void _xFire(XOn kind, int p, {int n = 0}) {
    final srcs = [?state.player(p).legend, for (final o in _boardOf(p)) o.id, ...state.player(p).trash];
    for (final s in srcs) {
      final abs = parsed(s).abilities;
      for (var i = 0; i < abs.length; i++) {
        final a = abs[i];
        if (a is! Triggered || a.on is! XWhen) continue;
        final w = a.on as XWhen;
        if (w.kind != kind || !_xZoneOk(s, w)) continue;
        if (w.n > 0 && n < w.n) continue;
        _queue(s, i, p);
      }
    }
  }

  /// Is [src] where its trigger works (the trash for "from trash" ones, else the board/legend)?
  bool _xZoneOk(ObjId src, When w) {
    final inTrash = state.obj(src).zone == Zone.trash;
    return w is XWhen && w.fromTrash ? inTrash : !inTrash;
  }

  /// Cards in [p]'s trash with abilities that trigger from there.
  List<ObjId> _xTrashTriggerCards(int p) => [
        for (final id in state.player(p).trash)
          if (parsed(id).abilities.any((a) => a is Triggered && a.on is XWhen && (a.on as XWhen).fromTrash)) id,
      ];

  /// Does a waiting trigger's condition still hold (CR 383.2.a.1)?
  bool _xTriggerOk(ChainItem t) {
    final a = _eqAbilityAt(db[t.card]!, t.ability);
    if (a is! Triggered || a.on is! XWhen) return true;
    final w = a.on as XWhen;
    if (w.fromTrash && state.obj(t.source).zone != Zone.trash) return false;
    return w.cond == null || _xCondNow(t.controller, w.cond!, source: t.source);
  }

  /// "When I become ready".
  void _xBecameReady(ObjId id) {
    if (state.obj(id).zone != Zone.board) return;
    final abs = parsed(id).abilities;
    for (var i = 0; i < abs.length; i++) {
      final a = abs[i];
      if (a is Triggered && a.on is XWhen && (a.on as XWhen).kind == XOn.becomeReady) _queue(id, i, state.obj(id).controller);
    }
  }

  /// A permanent is about to be killed: "an enemy unit has died this turn", and "when you kill
  /// a unit with a spell" (CR 429.5).
  void _xOnKill(Obj o) {
    if (card(o.id).type != CardType.unit) return;
    for (var q = 0; q < state.players.length; q++) {
      final t = _turn(state.player(q));
      if (q != o.controller) t['enemyDied'] = 1;
      if (t['resolving'] == 1 || t.remove('dmg:${o.id}') != null) _xFire(XOn.killWithSpell, q);
    }
  }

  /// Damage dealt by a spell as it resolves (for kills in the cleanup that follows, CR 429.5.c).
  void _xDamaged(int p, ObjId id) {
    if (_turn(state.player(p))['resolving'] == 1) _turn(state.player(p))['dmg:$id'] = 1;
  }

  /// The cleanup after a spell is done: its damage no longer kills "with a spell".
  void _xAfterCleanup() {
    for (var p = 0; p < state.players.length; p++) {
      state.marks.removeWhere((k, _) => k.startsWith('t:x:$p:dmg:'));
    }
  }

  /// A point from holding a battlefield (Needlessly Large Yordle).
  void _xHeld(int p) => _turn(state.player(p))['holdPts'] = (_turn(state.player(p))['holdPts'] ?? 0) + 1;

  // -------------------------------------------------------------------------------------------
  // Spells resolving
  // -------------------------------------------------------------------------------------------

  void _xBeforeSpell(ChainItem item) => _turn(state.player(item.controller))['resolving'] = 1;

  /// A spell finished resolving. Returns true if it went somewhere other than the trash.
  bool _xSpellDone(ChainItem item) {
    final pl = state.player(item.controller);
    _turn(pl).remove('resolving');
    final o = state.obj(item.source);
    if (item.paid & PlayFlags.recycleAfter != 0 && o.zone == Zone.chain) {
      o.zone = Zone.trash;
      state.player(o.owner).trash.add(o.id);
      _recycleCards(o.owner, [o.id]);
      log('${nameOf(o.id)} is recycled.', player: item.controller, card: o.id, kind: 'info');
      return true;
    }
    return false;
  }

  /// "Then, if it had 3 {M} or less, you may play this from your trash for {A}" — once the spell
  /// is in the trash (the reflexive trigger of CR 388.4, done at once).
  void _xAfterSpellTrashed(ChainItem item) {
    final pl = state.player(item.controller);
    if (_turn(pl)['replay'] != item.source) return;
    _turn(pl).remove('replay');
    final id = item.source;
    final o = state.obj(id);
    if (o.zone != Zone.trash || o.owner != item.controller) return;
    final r = _turn(pl).remove('replayPower') ?? 1;
    final via = XPlay(effect: true, forCost: (0, List<Domain?>.filled(r, null)), elsewhere: true);
    if (!_xCanPlayNow(item.controller, id, via)) return;
    if (!askYesNo(item.controller, 'Play ${nameOf(id)} again from your trash for ${'{A}' * r}?', source: id)) return;
    _playFromHand(item.controller, id, via: via);
  }

  // -------------------------------------------------------------------------------------------
  // Modes and choices
  // -------------------------------------------------------------------------------------------

  /// Which modes of [m] may be chosen now; asks for one. -1 if none can be.
  int _xChooseMode(Modes m, int p, ObjId source, int loc, List<int> used, {required bool optional}) {
    final allowed = <int>[];
    for (var i = 0; i < m.modes.length; i++) {
      if (m.distinct && used.contains(i)) continue;
      if (m.perTurn && state.objOrNull(source) != null && state.obj(source).usedThisTurn.contains(-1 - i)) continue;
      if (!optional && !_xModePossible(m.modes[i], p, source, loc)) continue;
      allowed.add(i);
    }
    if (allowed.isEmpty) return -1;
    final a = ask(Decision(kind: DecisionKind.option, player: p, prompt: '${nameOf(source)}: choose a mode', labels: [for (final i in allowed) _cap(m.modes[i].map(describeEffect).join(', then '))], source: source));
    final i = allowed[a.first];
    if (m.perTurn && state.objOrNull(source) != null) state.obj(source).usedThisTurn.add(-1 - i);
    return i;
  }

  static String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// Could a mode be played: do its mandatory choices have options (CR 355.8)?
  bool _xModePossible(List<Effect> es, int p, ObjId source, int loc) {
    for (final e in es) {
      if (e is May) continue;
      if (e is Counter && !state.chain.any((it) => it.isSpell && it.source != source)) return false;
      final t = _targetOf(e);
      if (t is Choose && !t.upTo && matching(t.filter, controller: p, source: source, here: loc).isEmpty) return false;
      if (e is Fight && units().length < 2) return false;
    }
    return true;
  }

  /// The choices this file's effects make as they're played (CR 355.5).
  void _xChooseFor(XEffect e, int p, ObjId source, int loc, bool optional, void Function(int, int) set, void Function(Effect, Choose, List<int>) choose, void Function(List<Effect>) walk, List<int> Function() chosen, bool Function(int, int) ok) {
    switch (e) {
      case Fight(:final a, :final b):
        if (a is Choose) choose(e, a, const []);
        if (b is Choose) choose(e, b, [if (a is Choose) ...chosen()]);
      case IfElse(:final then, :final otherwise):
        walk(then);
        walk(otherwise);
      case MightPerTags(:final target) || KillThenReplay(:final target):
        if (target is Choose) choose(e, target, const []);
      case LookPlay(:final kill):
        if (kill is Choose) choose(const Kill(Me()), kill, const []);
      case DoThen(:final first, :final then):
        walk([first]);
        walk(then);
      case BanishTrashThen(:final then):
        walk(then);
      case ExhaustMeThen(:final then):
        walk(then);
      case KillGearByCost(:final slot, :final max, :final myMight, :final then):
        final limit = myMight ? (state.objOrNull(source)?.zone == Zone.board ? mightUsed(source) : 0) : max;
        final options = [for (final o in state.objects.values) if (o.zone == Zone.board && card(o.id).type == CardType.gear && card(o.id).energy <= limit) o.id];
        if (options.isEmpty) {
          set(slot, -1);
        } else {
          set(slot, ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: choose a gear to kill', options: options, source: source)).first);
        }
        walk(then);
      case RecycleToPlay(:final slot):
        final options = [for (final u in units(player: p)) if (u != source) u];
        if (options.isEmpty) {
          set(slot, -1);
        } else {
          set(slot, ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: choose a unit to recycle', options: options, source: source)).first);
        }
      case PlayFrom(:final slot) when slot >= 0:
        final options = [for (final id in _xPlayCandidates(e, p, source, const _Ctx0())) if (ok(slot, id)) id];
        if (options.isEmpty) {
          set(slot, -1);
        } else {
          set(slot, ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: choose a card to play', options: options, source: source)).first);
        }
      case StealOrCounter(:final maxEnergy):
        final spells = [for (final it in state.chain) if (it.isSpell && it.source != source && db[it.card]!.energy <= maxEnergy) it.source];
        if (spells.isEmpty) {
          if (optional) return;
          throw RiftboundError('No spell to choose');
        }
        set(0, ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(source)}: choose a spell', options: spells, source: source)).first);
      case CounterByCost(:final maxEnergy, :final maxPower):
        final spells = [
          for (final it in state.chain)
            if (it.isSpell && it.source != source && db[it.card]!.energy <= maxEnergy && db[it.card]!.power <= maxPower) it.source,
        ];
        if (spells.isEmpty) {
          if (optional) return;
          throw RiftboundError('No spell it can counter');
        }
        set(0, ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Counter which spell?', options: spells, source: source)).first);
      default:
        break;
    }
  }

  /// Slots used by [effects] (a [Repeat] makes each execution's choices in its own range).
  int _xSlotCount(List<Effect> effects) {
    var n = 0;
    void use(int s) {
      if (s + 1 > n) n = s + 1;
    }

    void walk(List<Effect> es) {
      for (final e in es) {
        switch (e) {
          case May(:final effects) || If(:final effects):
            walk(effects);
          case Modes(:final modes, :final slot):
            if (slot >= 0) use(slot);
            for (final m in modes) {
              walk(m);
            }
          case Counter() || CounterByCost() || StealOrCounter():
            use(0);
          case Fight(:final a, :final b):
            if (a is Choose) use(a.slot);
            if (b is Choose) use(b.slot);
          case MightPerTags(target: final Choose t) || LookPlay(kill: final Choose t) || KillThenReplay(target: final Choose t):
            use(t.slot);
          case IfElse(:final then, :final otherwise):
            walk(then);
            walk(otherwise);
          case DoThen(:final first, :final then):
            walk([first]);
            walk(then);
          case BanishTrashThen(:final then) || ExhaustMeThen(:final then):
            walk(then);
          case KillGearByCost(:final slot, :final then):
            use(slot);
            walk(then);
          case RecycleToPlay(:final slot):
            use(slot);
          case PlayFrom(:final slot):
            if (slot >= 0) use(slot);
          case HEffect():
            for (final t in e.choices) {
              switch (t) {
                case Choose(:final slot) || ChooseBf(:final slot) || ChooseRel(:final slot) || ChooseOwnCard(:final slot):
                  use(slot);
                default:
                  break;
              }
            }
            walk(e.nested);
          case PowerEffect() when _powerInner(e) != null:
            final t = _targetOf(e);
            if (t is Choose) use(t.slot);
            walk(_powerInner(e)!);
          default:
            final t = _targetOf(e);
            if (t is Choose) use(t.slot);
        }
      }
    }

    walk(effects);
    return n;
  }

  /// The targets of execution [r] of a repeated item.
  List<int> _xSlice(List<int> targets, int r, int per) => [for (var i = 0; i < per; i++) r * per + i < targets.length ? targets[r * per + i] : -1];

  // -------------------------------------------------------------------------------------------
  // Playing cards as an effect (CR 420.3)
  // -------------------------------------------------------------------------------------------

  /// Would playing [id] as [via] work now? (Tried on a copy, with default answers.)
  bool _xCanPlayNow(int p, ObjId id, XPlay via) {
    final c = card(id);
    if (!c.isMainDeck || !RiftboundParser.parse(c).supported) return false;
    final g = Game._probe(this);
    try {
      g._playFromHand(p, id, via: via.copy());
      return true;
    } on TcgError {
      return false;
    } on NeedDecision {
      return true;
    }
  }

  XPlay _xVia(PlayFrom e, ObjId id, {int reduce = 0}) => XPlay(effect: true, ignoreEnergy: e.ignoreEnergy, ignoreAll: e.ignoreAll, toBase: e.toBase, recycleAfter: e.recycleAfter, reduceEnergy: reduce, elsewhere: e.zone != XZone.hand);

  /// Cards [e] could play now.
  List<ObjId> _xPlayCandidates(PlayFrom e, int p, ObjId source, _Ctx0 ctx) {
    final pl = state.player(p);
    final pool = switch (e.zone) {
      XZone.trash => pl.trash,
      XZone.hand => pl.hand,
      XZone.bannedByMe => [for (final o in state.objects.values) if (o.zone == Zone.banish && o.banishedBy == source) o.id],
    };
    final killed = ctx.costRef >= 0 ? card(ctx.costRef) : null;
    return [
      for (final id in pool)
        if (_xPlayMatches(e, p, id, killed) && _xCanPlayNow(p, id, _xVia(e, id))) id,
    ];
  }

  bool _xPlayMatches(PlayFrom e, int p, ObjId id, RCard? killed) {
    final c = card(id);
    if (e.types.isNotEmpty && !e.types.contains(c.type)) return false;
    if (e.tags.isNotEmpty && !e.tags.any(c.hasTag)) return false;
    if (e.maxEnergy != null && c.energy > e.maxEnergy!) return false;
    if (e.maxPower != null && c.power > e.maxPower!) return false;
    if (e.lessThanPoints && c.energy >= state.player(p).points) return false;
    if (e.maxOfKilled && (killed == null || c.energy > killed.energy || c.power > killed.power)) return false;
    return true;
  }

  /// Plays [id] as part of [e]'s resolution, with [p] in control.
  void _xPlayAsEffect(int p, ObjId id, XPlay via) {
    if (!_xCanPlayNow(p, id, via)) return;
    _playFromHand(p, id, via: via);
  }

  /// Reveals [id] from its owner's deck: "As I'm revealed from your deck, [Add] {2}."
  void _xRevealed(ObjId id) {
    final o = state.obj(id);
    for (final a in parsed(id).abilities) {
      if (a is Static && a.passive is RevealAdd) {
        state.player(o.owner).energyPool += (a.passive as RevealAdd).energy;
        log('${nameOf(id)} is revealed: ${playerName(o.owner)} adds {${(a.passive as RevealAdd).energy}}.', player: o.owner, card: id, kind: 'info');
      }
    }
  }

  // -------------------------------------------------------------------------------------------
  // Resolving this file's effects
  // -------------------------------------------------------------------------------------------

  void _xResolve(XEffect e, _Ctx ctx) {
    final p = ctx.controller;
    switch (e) {
      case EachPlayer(:final draw, :final discard):
        for (var i = 0; i < state.players.length; i++) {
          final q = (p + i) % state.players.length;
          if (draw > 0) _draw(q, draw);
          if (discard > 0) {
            final hand = state.player(q).hand;
            if (hand.isEmpty) continue;
            final k = discard < hand.length ? discard : hand.length;
            final pick = ask(Decision(kind: DecisionKind.cards, player: q, prompt: 'Discard $k', options: List.of(hand), min: k, max: k, source: ctx.source));
            for (final id in pick) {
              hand.remove(id);
              state.obj(id).zone = Zone.trash;
              state.player(q).trash.add(id);
            }
            log('${playerName(q)} discards ${pick.map(nameOf).join(', ')}.', player: q, kind: 'discard');
          }
        }
      case Fight(:final a, :final b):
        final x = _resolveTarget(a, ctx).where(isUnit).firstOrNull;
        final y = _resolveTarget(b, ctx).where(isUnit).firstOrNull;
        if (x == null || y == null) return;
        final mx = mightUsed(x), my = mightUsed(y);
        final dy = _genDeal(y, mx, ctx, byUnit: x);
        final dx = _genDeal(x, my, ctx, byUnit: y);
        _xDamaged(p, x);
        _xDamaged(p, y);
        log('${nameOf(x)} and ${nameOf(y)} deal $dy and $dx to each other.', player: p, card: x, kind: 'damage', amount: dy);
      case IfElse(:final cond, :final then, :final otherwise):
        for (final x in _cond(cond, ctx) ? then : otherwise) {
          _resolve(x, ctx);
        }
      case PlayFrom(:final slot):
        final ObjId? id;
        if (slot >= 0) {
          id = slot < ctx.targets.length && ctx.targets[slot] >= 0 ? ctx.targets[slot] : null;
          if (id == null || !_xPlayMatches(e, p, id, null) || state.obj(id).zone != (e.zone == XZone.hand ? Zone.hand : Zone.trash)) return;
        } else {
          final options = _xPlayCandidates(e, p, ctx.source, _Ctx0(costRef: ctx.costRef));
          if (options.isEmpty) return;
          id = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Play which card? (${nameOf(ctx.source)})', options: options, source: ctx.source)).first;
        }
        _xPlayAsEffect(p, id, _xVia(e, id));
      case RecycleOpponentTrash(:final n):
        final options = [for (var q = 0; q < state.players.length; q++) if (q != p) ...state.player(q).trash];
        if (options.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose up to $n cards in opponents’ trashes to recycle', options: options, min: 0, max: n < options.length ? n : options.length, source: ctx.source));
        for (var q = 0; q < state.players.length; q++) {
          final mine = [for (final id in pick) if (state.obj(id).owner == q) id];
          if (mine.isNotEmpty) _recycleCards(q, mine);
        }
        if (pick.isNotEmpty) log('${playerName(p)} recycles ${pick.length} card${pick.length == 1 ? '' : 's'} from opponents’ trashes.', player: p, kind: 'info');
      case RecycleYourTrash(:final n):
        final trash = state.player(p).trash;
        if (trash.isEmpty) return;
        final k = n < trash.length ? n : trash.length;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Recycle $k from your trash', options: List.of(trash), min: k, max: k, source: ctx.source));
        _recycleCards(p, pick);
        log('${playerName(p)} recycles $k from their trash.', player: p, kind: 'info');
      case MoveToOpenBf():
        final open = [for (var i = 0; i < state.bfs.length; i++) if (state.bfs[i].controller == null && unitsAt(i).isEmpty) i];
        final mine = units(player: p);
        if (open.isEmpty || mine.isEmpty) return;
        final to = open[ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Move units to which open battlefield?', labels: [for (final i in open) nameOf(state.bfs[i].obj)], source: ctx.source)).first];
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose units to move to ${nameOf(state.bfs[to].obj)}', options: mine, min: 0, max: mine.length, source: ctx.source));
        if (pick.isNotEmpty) _moveUnits(pick, to, p);
      case BanishTrashThen(:final then, :final anyTrash, :final unit):
        final options = [
          for (var q = 0; q < state.players.length; q++)
            if (anyTrash || q == p)
              for (final id in state.player(q).trash)
                if (!unit || card(id).type == CardType.unit) id,
        ];
        if (options.isEmpty) return;
        final id = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Banish a ${unit ? 'unit' : 'card'} from ${anyTrash ? 'a' : 'your'} trash', options: options, source: ctx.source)).first;
        _xBanish(id, ctx.source);
        for (final x in then) {
          _resolve(x, ctx);
        }
      case DefenderKills():
        final def = state.other(p);
        final here = ctx.loc;
        if (here < 0) return;
        final theirs = unitsAt(here, player: def);
        if (theirs.isEmpty) return;
        final id = ask(Decision(kind: DecisionKind.cards, player: def, prompt: 'Kill one of your units here (${nameOf(ctx.source)})', options: theirs, source: ctx.source)).first;
        log('${nameOf(id)} is killed.', player: def, card: id, kind: 'die');
        _kill(id);
      case KillThenReplay(:final target, :final maxMight, :final power):
        for (final id in _resolveTarget(target, ctx)) {
          final m = isUnit(id) ? mightUsed(id) : maxMight + 1;
          log('${nameOf(id)} is killed.', player: p, card: id, kind: 'die');
          _kill(id);
          if (m <= maxMight) {
            _turn(state.player(p))['replay'] = ctx.source;
            _turn(state.player(p))['replayPower'] = power.length;
          }
        }
      case KillGearByCost(:final slot, :final max, :final myMight, :final then):
        final id = slot < ctx.targets.length ? ctx.targets[slot] : -1;
        if (id < 0 || state.objOrNull(id)?.zone != Zone.board || card(id).type != CardType.gear) return;
        final limit = myMight ? (state.objOrNull(ctx.source)?.zone == Zone.board ? mightUsed(ctx.source) : 0) : max;
        if (card(id).energy > limit) return;
        log('${nameOf(id)} is killed.', player: p, card: id, kind: 'die');
        _kill(id);
        for (final x in then) {
          _resolve(x, ctx);
        }
      case DoThen(:final first, :final then):
        final t = _targetOf(first);
        if (t != null && _resolveTarget(t, ctx).isEmpty) return;
        _resolve(first, ctx);
        for (final x in then) {
          _resolve(x, ctx);
        }
      case TurnFx(:final fx, :final energy, :final power):
        final t = _turn(state.player(p));
        switch (fx) {
          case XTurnFx.nextSpellLess:
            t['nextSpell'] = (t['nextSpell'] ?? 0) + energy;
          case XTurnFx.nextCardLess:
            t['nextCardE'] = (t['nextCardE'] ?? 0) + energy;
            if (power > 0) t['nextCardP'] = (t['nextCardP'] ?? 0) + power;
          case XTurnFx.unitsMore:
            t['unitsMore'] = (t['unitsMore'] ?? 0) + energy;
          case XTurnFx.freeGear:
            if (energy > (t['freeGear'] ?? 0)) t['freeGear'] = energy;
          case XTurnFx.nextSpellRepeat:
            t['nextRepeat'] = 1;
        }
        log('${nameOf(ctx.source)}: ${describeEffect(e)}.', player: p, card: ctx.source, kind: 'info');
      case CounterByCost():
        _resolve(const Counter(), ctx);
      case LookDrawType(:final n, :final type, :final minEnergy):
        final deck = state.player(p).deck;
        final top = _xSeeMe(p, deck.take(n).toList());
        if (top.isEmpty) return;
        final ok = [for (final id in top) if (card(id).type == type && card(id).energy >= minEnergy) id];
        final pick = ok.isEmpty ? const <int>[] : ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Reveal a ${type.name} to draw? (${nameOf(ctx.source)})', options: ok, min: 0, max: 1, source: ctx.source));
        for (final id in pick) {
          _xRevealed(id);
          deck.remove(id);
          state.obj(id).zone = Zone.hand;
          state.player(p).hand.add(id);
          log('${playerName(p)} reveals and draws ${nameOf(id)}.', player: p, card: id, kind: 'draw');
        }
        final rest = [for (final id in top) if (!pick.contains(id)) id];
        for (final id in rest) {
          deck.remove(id);
        }
        _recycleCards(p, rest);
      case PlayOpponentsTop():
        final q = state.other(p);
        final deck = state.player(q).deck;
        if (deck.isEmpty) return;
        final id = deck.first;
        _xRevealed(id);
        log('${playerName(q)} reveals ${nameOf(id)}.', player: q, card: id, kind: 'info');
        _xBanish(id, ctx.source);
        _xPlayAsEffect(p, id, XPlay(effect: true, ignoreAll: true, elsewhere: true));
      case BanishTrashUnits():
        for (final id in [for (final id in state.player(p).trash) if (card(id).type == CardType.unit) id]) {
          _xBanish(id, ctx.source);
        }
      case RecycleToPlay(:final slot, :final tag):
        final u = slot < ctx.targets.length ? ctx.targets[slot] : -1;
        if (u < 0 || !isUnit(u) || state.obj(u).controller != p) return;
        final m = mightUsed(u);
        // Recycle the unit from the board (CR 417): to the bottom of its owner's Main Deck.
        final owner = state.obj(u).owner;
        final token = card(u).token;
        _leaveBoard(u, toHand: false);
        state.player(owner).trash.remove(u);
        if (!token) _recycleCards(owner, [u]);
        log('${nameOf(u)} is recycled.', player: p, card: u, kind: 'move');
        final options = [
          for (final id in state.player(p).trash)
            if (card(id).type == CardType.unit && card(id).hasTag(tag) && _xCanPlayNow(p, id, XPlay(effect: true, reduceEnergy: m, elsewhere: true))) id,
        ];
        if (options.isEmpty) return;
        final id = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Play which $tag from your trash?', options: options, source: ctx.source)).first;
        _xPlayAsEffect(p, id, XPlay(effect: true, reduceEnergy: m, elsewhere: true));
      case ExhaustMeThen(:final then):
        final o = state.objOrNull(ctx.source);
        if (o == null || o.exhausted) return;
        o.exhausted = true;
        for (final x in then) {
          _resolve(x, ctx);
        }
      case ReturnMeFromTrash(:final discard):
        final o = state.obj(ctx.source);
        final pl = state.player(o.owner);
        if (o.zone != Zone.trash || pl.hand.length < discard) return;
        if (discard > 0) {
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Discard $discard', options: List.of(pl.hand), min: discard, max: discard, source: ctx.source));
          for (final id in pick) {
            pl.hand.remove(id);
            state.obj(id).zone = Zone.trash;
            pl.trash.add(id);
          }
        }
        pl.trash.remove(o.id);
        o.zone = Zone.hand;
        pl.hand.add(o.id);
        log('${nameOf(o.id)} returns to ${pl.name}’s hand.', player: p, card: o.id, kind: 'move');
      case PayToPlayMe(:final energy, :final power):
        final o = state.obj(ctx.source);
        if (o.zone != Zone.trash) return;
        _xPlayAsEffect(p, o.id, XPlay(effect: true, forCost: (energy, power), elsewhere: true));
      case AbilityCostLess():
        break;
      case MightPerTags(:final target, :final n, :final tags):
        final k = _xTagKinds(p, tags) * n;
        for (final id in _resolveTarget(target, ctx)) {
          if (!isUnit(id) || k == 0) continue;
          state.obj(id).mightMod += k;
          log('${nameOf(id)} gets +$k Might this turn.', player: p, card: id, kind: 'buff');
        }
      case LookPlay(:final n, :final types, :final reduceEnergy, :final ignoreAll, :final kill, :final mightPlus):
        int? killedMight;
        if (kill != null) {
          for (final id in _resolveTarget(kill, ctx)) {
            killedMight = isUnit(id) ? mightUsed(id) : 0;
            log('${nameOf(id)} is killed.', player: p, card: id, kind: 'die');
            _kill(id);
          }
        }
        final deck = state.player(p).deck;
        final top = _xSeeMe(p, deck.take(n).toList());
        final via = XPlay(effect: true, reduceEnergy: reduceEnergy, ignoreAll: ignoreAll, elsewhere: true);
        final ok = [
          for (final id in top)
            if (types.contains(card(id).type) && (kill == null || (killedMight != null && (card(id).might ?? 0) <= killedMight + mightPlus)) && _xCanPlayNow(p, id, via)) id,
        ];
        final pick = ok.isEmpty ? const <int>[] : ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Play which card? (banish it, then play it)', options: ok, min: 0, max: 1, source: ctx.source));
        final rest = [for (final id in top) if (!pick.contains(id)) id];
        for (final id in rest) {
          deck.remove(id);
        }
        for (final id in pick) {
          _xBanish(id, ctx.source);
          _xPlayAsEffect(p, id, via);
        }
        _recycleCards(p, rest);
      case RevealPlay(:final n, :final reduceEnergy):
        final deck = state.player(p).deck;
        final top = deck.take(n).toList();
        for (final id in top) {
          _xRevealed(id);
        }
        final seen = _xSeeMe(p, top);
        final via = XPlay(effect: true, reduceEnergy: reduceEnergy, elsewhere: true);
        final ok = [for (final id in seen) if (_xCanPlayNow(p, id, via)) id];
        final pick = ok.isEmpty ? const <int>[] : ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Play which card? (the rest are drawn)', options: ok, min: 0, max: 1, source: ctx.source));
        for (final id in pick) {
          _xPlayAsEffect(p, id, via);
        }
        for (final id in seen) {
          if (pick.contains(id) || !deck.contains(id)) continue;
          deck.remove(id);
          state.obj(id).zone = Zone.hand;
          state.player(p).hand.add(id);
        }
        log('${playerName(p)} draws the rest.', player: p, kind: 'draw');
      case EachPlayerLookPlay(:final n):
        final chosen = <int, ObjId>{};
        for (var i = 0; i < state.players.length; i++) {
          final q = (p + i) % state.players.length;
          final deck = state.player(q).deck;
          final top = deck.take(n).toList();
          if (top.isEmpty) continue;
          final via = XPlay(effect: true, ignoreEnergy: true, elsewhere: true);
          final ok = [for (final id in top) if (_xCanPlayNow(q, id, via)) id];
          final pick = ask(Decision(kind: DecisionKind.cards, player: q, prompt: 'Play which card? (${nameOf(ctx.source)}; the rest are recycled)', options: ok.isEmpty ? top : ok, source: ctx.source));
          final rest = [for (final id in top) if (!pick.contains(id)) id];
          for (final id in rest) {
            deck.remove(id);
          }
          _recycleCards(q, rest);
          chosen[q] = pick.first;
        }
        // "Starting with the next player" (CR 101's turn order).
        for (var i = 1; i <= state.players.length; i++) {
          final q = (p + i) % state.players.length;
          final id = chosen[q];
          if (id == null || !state.player(q).deck.contains(id)) continue;
          _xPlayAsEffect(q, id, XPlay(effect: true, ignoreEnergy: true, elsewhere: true));
        }
      case StealOrCounter(:final energy, :final power):
        if (ctx.targets.isEmpty) return;
        final i = state.chain.indexWhere((it) => it.isSpell && it.source == ctx.targets[0]);
        if (i < 0) return;
        final it = state.chain[i];
        if (canPay(p, energy, power, forSpell: true) && askYesNo(p, 'Pay ${'{$energy}' * (energy > 0 ? 1 : 0)}${power.map((d) => '{${d?.letter ?? 'A'}}').join()} to take control of ${nameOf(it.source)}?', source: ctx.source)) {
          _pay(p, energy, power, forSpell: true);
          var targets = it.targets;
          // New choices (CR 750–755): all of them remade, or none if there are no legal ones.
          if (askYesNo(p, 'Make new choices for ${nameOf(it.source)}?', source: ctx.source)) {
            final effects = [for (final a in RiftboundParser.parse(db[it.card]!).abilities) if (a is SpellBody) ...a.effects];
            try {
              targets = _chooseTargets(effects, p, it.source, it.loc, repeats: it.repeats);
            } on RiftboundError {
              targets = it.targets;
            }
          }
          state.chain[i] = ChainItem(id: it.id, source: it.source, card: it.card, ability: it.ability, controller: p, targets: targets, repeats: it.repeats, loc: it.loc, fromTrigger: it.fromTrigger, legion: it.legion, event: it.event, paid: it.paid, costRef: it.costRef);
          log('${playerName(p)} takes control of ${nameOf(it.source)}.', player: p, card: it.source, kind: 'info');
          return;
        }
        _resolve(const Counter(), ctx);
    }
  }

  void _xBanish(ObjId id, ObjId by) {
    final o = state.obj(id);
    final pl = state.player(o.owner);
    pl.trash.remove(id);
    pl.deck.remove(id);
    pl.hand.remove(id);
    o
      ..zone = Zone.banish
      ..banishedBy = by;
    pl.banish.add(id);
    log('${nameOf(id)} is banished.', player: o.owner, card: id, kind: 'info');
  }

  /// "My Might is increased by …" (CR 479.4).
  int _xMight(ObjId id) {
    var m = 0;
    for (final a in parsed(id).abilities) {
      if (a is Static && a.passive is XMight) {
        final x = a.passive as XMight;
        final p = state.obj(id).controller;
        if (x.perTrashCard) m += state.player(p).trash.length;
        if (x.cond != null && _xCondNow(p, x.cond!, source: id)) m += x.n;
      }
    }
    return m;
  }

  /// "Friendly units played from anywhere other than a player's hand have [Accelerate]."
  bool _xGrantsAccelerate(int p, XPlay x) =>
      x.elsewhere && _boardOf(p).any((o) => parsed(o.id).abilities.any((a) => a is Static && a.passive is ElsewhereAccelerate));

  /// "Give the next spell you play this turn [Repeat] equal to its cost": offers that Repeat for
  /// spell [id] as it's played; true if it's paid.
  bool _xGrantedRepeat(int p, ObjId id, XPlay x) {
    final c = card(id);
    if (c.type != CardType.spell || (_turn(state.player(p))['nextRepeat'] ?? 0) == 0) return false;
    final cost = Cost(energy: c.energy, power: List<Domain?>.filled(c.power, c.domains.isEmpty ? null : c.domains.first));
    x.optional.add((_xRepeatEnergy(p, cost), cost.power));
    if (_xPayable(p, id, x) != null && askYesNo(p, 'Pay ${cost.describe()} to Repeat ${c.name}?', source: id)) return true;
    x.optional.removeLast();
    return false;
  }

  /// Is Deflect ignored for [source] choosing [target] (Decree of Insight, Heisho)?
  bool _xIgnoreDeflect(ObjId source, ObjId target) {
    if (state.objOrNull(source) != null && parsed(source).abilities.any((a) => a is Static && a.passive is IgnoreDeflect && !(a.passive as IgnoreDeflect).here)) return true;
    final t = state.objOrNull(target);
    if (t == null || t.zone != Zone.board || t.loc < 0 || t.loc >= state.bfs.length) return false;
    return parsed(state.bfs[t.loc].obj).abilities.any((a) => a is Static && a.passive is IgnoreDeflect && (a.passive as IgnoreDeflect).here);
  }

  /// "When you look at cards from the top of your deck and see me, you may play me for {A}."
  /// Returns the cards of [looked] still in the deck afterwards.
  List<ObjId> _xSeeMe(int p, List<ObjId> looked) {
    final out = <ObjId>[];
    for (final id in looked) {
      SeeMePlay? see;
      for (final a in parsed(id).abilities) {
        if (a is Static && a.passive is SeeMePlay) see = a.passive as SeeMePlay;
      }
      if (see != null && state.obj(id).owner == p) {
        final via = XPlay(effect: true, forCost: (see.energy, see.power), elsewhere: true);
        if (_xCanPlayNow(p, id, via) && askYesNo(p, 'You see ${nameOf(id)}: play it for ${see.energy > 0 ? '{${see.energy}}' : ''}${see.power.map((d) => '{${d?.letter ?? 'A'}}').join()}?', source: id)) {
          _playFromHand(p, id, via: via);
          continue;
        }
      }
      out.add(id);
    }
    return out;
  }

  /// Marai Spire: friendly [Repeat] costs cost {1} less.
  int _xRepeatEnergy(int p, Cost c) {
    var e = c.energy;
    for (final (s, m) in _xCostMods()) {
      if (m.who == XWho.repeatCosts && _xControls(p, s)) e -= m.energy;
    }
    return e < 0 ? 0 : e;
  }
}

/// The context a play candidate list needs (the killed unit of an additional cost).
class _Ctx0 {
  const _Ctx0({this.costRef = -1});
  final int costRef;
}
