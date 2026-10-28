part of 'game.dart';

/// Equipment (CR 150): attaching and detaching (CR 435–436, 716–725), Equip (CR 818), Quick-Draw
/// (CR 819), Weaponmaster (CR 821), Effect Text (CR 136) and Might Bonuses (CR 137), and the
/// cards built around them. The rest of the engine calls in with one-line hooks.
///
/// An attached card stays a gear on the board ([EqObj.attachedTo] names its unit, and its
/// location follows the unit's). Its own rules text is inactive (CR 718.2); its Effect Text is
/// the unit's (CR 718.3): those abilities go on the chain with the unit as their source, the
/// Equipment's card and Effect Text index ([ParsedCard.extra], at 1000 + i), and the Equipment as
/// [ChainItem.via] ("this").
extension GameEquip on Game {
  // -------------------------------------------------------------------------------------------
  // Reading attachments
  // -------------------------------------------------------------------------------------------

  /// The card an object is now: a copy's copied card (CR 446), else its own. A database key.
  String _eqCardKey(ObjId id) {
    final o = state.obj(id);
    return o.eq.copyOf.isEmpty ? o.card : o.eq.copyOf;
  }

  bool isEquipmentObj(ObjId id) {
    final c = card(id);
    return c.type == CardType.gear && c.hasTag('Equipment');
  }

  /// Cards attached to [unit] (CR 719), oldest first.
  List<ObjId> attachedTo(ObjId unit) => [
        for (final o in state.objects.values)
          if (o.zone == Zone.board && o.eq.attachedTo == unit) o.id,
      ];

  /// The unit [id] is attached to, or null.
  ObjId? attachedUnit(ObjId id) {
    final o = state.objOrNull(id);
    if (o == null || o.zone != Zone.board || o.eq.attachedTo < 0) return null;
    final u = state.objOrNull(o.eq.attachedTo);
    return u != null && u.zone == Zone.board ? u.id : null;
  }

  /// Equipped (CR 818.3): one or more Equipment attached.
  bool isEquipped(ObjId unit) => attachedTo(unit).any(isEquipmentObj);

  /// An attached card's printed rules text is inactive (CR 718.2).
  bool _eqInactive(ObjId id) => attachedUnit(id) != null;

  /// Abilities [unit] has from the cards attached to it (CR 435.1.c): the card whose ability list
  /// holds each (for the chain), its index there, the ability, and the attached card ("this").
  List<(String, int, Ability, ObjId)> _eqAppended(ObjId unit) {
    final o = state.objOrNull(unit);
    if (o == null || o.zone != Zone.board || card(unit).type != CardType.unit) return const [];
    final out = <(String, int, Ability, ObjId)>[];
    for (final g in attachedTo(unit)) {
      final key = _eqCardKey(g);
      final p = RiftboundParser.parse(db[key]!);
      // An Equipment's extra abilities are its Effect Text.
      for (var i = 0; i < p.extra.length; i++) {
        out.add((key, 1000 + i, p.extra[i], g));
      }
      // Svellsongur: the unit's text copied into its Effect Text (CR 479.1.d).
      final copied = state.obj(g).eq.textOf;
      if (copied.isNotEmpty) {
        final abs = RiftboundParser.parse(db[copied]!).abilities;
        for (var i = 0; i < abs.length; i++) {
          out.add((copied, i, abs[i], g));
        }
      }
    }
    return out;
  }

  /// Ability [index] of card [c]: its own, or (1000 + i) the ones it gives others.
  Ability _eqAbilityAt(RCard c, int index) {
    final p = RiftboundParser.parse(c);
    return index >= 1000 ? p.extra[index - 1000] : p.abilities[index];
  }

  /// The instructions of abilities the core doesn't know how to read, or null.
  List<Effect>? _eqEffectsOf(Ability a) => switch (a) {
        Static(passive: EqGrantWeaponmaster(:final ability)) => ability.effects,
        Static(passive: EqGrantQuickDraw(:final ability)) => ability.effects,
        _ => null,
      };

  /// Queues [unit]'s abilities from attached cards that pass [test].
  void _eqQueueAppended(ObjId unit, bool Function(Triggered t) test, {int loc = -2, int event = -1}) {
    for (final (key, i, a, via) in _eqAppended(unit)) {
      if (a is Triggered && test(a)) _queue(unit, i, state.obj(unit).controller, loc: loc, event: event, card: key, via: via);
    }
  }

  /// Passive abilities units have from attached cards, with the unit as their source.
  Iterable<(ObjId, Passive)> _eqPassives() sync* {
    // The units something on the board is attached to, found in one pass.
    final carriers = <ObjId>{
      for (final g in state.objects.values)
        if (g.zone == Zone.board && g.eq.attachedTo >= 0) g.eq.attachedTo,
    };
    if (carriers.isEmpty) return;
    for (final o in state.objects.values) {
      if (!carriers.contains(o.id)) continue;
      if (o.zone != Zone.board || o.eq.attachedTo >= 0 || card(o.id).type != CardType.unit) continue;
      for (final (_, _, a, _) in _eqAppended(o.id)) {
        if (a is Static) yield (o.id, a.passive);
      }
    }
  }

  /// The passives on [unit] itself (printed or appended), each with the card that gives it ("this").
  List<(Passive, ObjId)> _eqOwnPassives(ObjId unit) => [
        for (final a in parsed(unit).abilities)
          if (a is Static) (a.passive, unit),
        for (final (_, _, a, via) in _eqAppended(unit))
          if (a is Static) (a.passive, via),
      ];

  /// Passives in effect on the board and legends of [p] (for grants like "Your Sand Soldiers have
  /// [Weaponmaster]").
  List<(ObjId, Passive)> _eqPassivesOf(int p) => [
        for (final (src, x) in _passives())
          if (state.obj(src).controller == p) (src, x),
      ];

  // -------------------------------------------------------------------------------------------
  // Might, keywords, tags (CR 137, 479)
  // -------------------------------------------------------------------------------------------

  /// What attachments and Equipment passives add to [id]'s Might.
  int _eqMight(ObjId id) {
    final o = state.obj(id);
    if (o.zone != Zone.board || card(id).type != CardType.unit) return 0;
    var m = 0;
    final own = _eqOwnPassives(id);
    final double = own.any((x) => x.$1 is EqDoubleBonus);
    // Might Bonuses of attached cards (CR 435.1.d, 479.4.d).
    for (final g in attachedTo(id)) {
      final b = card(g).mightBonus ?? 0;
      m += double ? 2 * b : b;
    }
    for (final (x, via) in own) {
      switch (x) {
        case EqMightPerGear(:final n):
          m += n * gearOf(o.controller).length;
        case EqMightIf(:final n, :final cond):
          if (_eqHolds(cond, id, via)) m += n;
        default:
          break;
      }
    }
    return m;
  }

  bool _eqHolds(EqCond c, ObjId unit, ObjId via) {
    final o = state.obj(unit);
    return switch (c) {
      EqWithOneOther() => o.loc != base && unitsAt(o.loc, player: o.controller).length == 2,
      EqAttachedThisTurn() => state.objOrNull(via)?.eq.attachedTurn == state.turn && attachedUnit(via) == unit,
      EqLevel(:final n) => state.player(o.controller).pw.xp >= n,
      EqDidntConquer() => o.eq.conquerTurn != state.turn,
      _ => false,
    };
  }

  /// Keyword values from attached cards (CR 718.3) and "Your Equipment each give [Assault]".
  int _eqKw(ObjId id, Kw k) {
    final o = state.obj(id);
    if (o.zone != Zone.board || card(id).type != CardType.unit) return 0;
    var n = 0;
    final attached = attachedTo(id);
    if (attached.isEmpty) return 0;
    for (final (_, _, a, _) in _eqAppended(id)) {
      if (a is KeywordAb && a.kw == k) n += a.n;
    }
    for (final (src, x) in _passives()) {
      if (x is EqEquipmentGive && x.kw == k) {
        final ctl = state.obj(src).controller;
        for (final g in attached) {
          if (isEquipmentObj(g) && state.obj(g).controller == ctl) n += x.n;
        }
      }
    }
    return n;
  }

  /// "I am a Mech." from an attached card.
  bool _eqHasTag(ObjId id, String tag) => _ws2HasTag(id, tag) || _eqOwnPassives(id).any((x) => x.$1 is EqHasTag && (x.$1 as EqHasTag).tag.toLowerCase() == tag.toLowerCase());

  /// "I can't be moved by enemy spells and abilities": a move by [mover] that doesn't happen.
  bool _eqUnmovable(ObjId id, int mover) => state.obj(id).controller != mover && _eqOwnPassives(id).any((x) => x.$1 is EqUnmovable);

  // -------------------------------------------------------------------------------------------
  // Attaching and detaching (CR 435, 436)
  // -------------------------------------------------------------------------------------------

  /// Attaches [gear] to [unit] (by [by]'s effect). Attaching to a new unit detaches it from the
  /// old one (CR 435.1.f); to its current one, nothing happens (CR 435.1.g); units can't be
  /// attached (CR 435.1.h). Its location becomes the unit's, which isn't a move (CR 435.4).
  void _eqAttach(ObjId gear, ObjId unit, int by) {
    final g = state.objOrNull(gear), u = state.objOrNull(unit);
    if (g == null || u == null || g.zone != Zone.board || u.zone != Zone.board) return;
    if (card(unit).type != CardType.unit || card(gear).type == CardType.unit || gear == unit) return;
    if (g.eq.attachedTo == unit) return;
    if (g.eq.attachedTo >= 0) _eqDetach(gear, quiet: true);
    g.eq
      ..attachedTo = unit
      ..attachedTurn = state.turn;
    g.loc = u.loc;
    log('${nameOf(gear)} is attached to ${nameOf(unit)}.', player: by, card: unit, kind: 'equip');
    // "As this is attached" abilities apply as it attaches (CR 725.1).
    final printed = [for (final a in RiftboundParser.parse(db[_eqCardKey(gear)]!).abilities) if (a is Static) a.passive];
    if (printed.any((x) => x is EqCopyAsAttached)) {
      final others = [for (final x in units(player: g.controller)) if (x != unit) x];
      if (others.isNotEmpty) {
        final pick = ask(Decision(kind: DecisionKind.cards, player: g.controller, prompt: '${nameOf(gear)}: choose a friendly unit for ${nameOf(unit)} to become a copy of', options: others, source: gear)).first;
        final key = _eqCardKey(pick);
        u.eq
          ..copyOf = key
          ..copyVia = gear;
        log('${nameOf(unit)} becomes a copy of $key.', player: g.controller, card: unit, kind: 'equip');
      }
    }
    if (printed.any((x) => x is EqCopyTextAsAttached)) g.eq.textOf = _eqCardKey(unit);
    // "When you attach an Equipment to me" (CR 818.2).
    if (isEquipmentObj(gear) && by == u.controller) {
      final abs = parsed(unit).abilities;
      for (var i = 0; i < abs.length; i++) {
        final a = abs[i];
        if (a is Triggered && a.on is EqWhen && (a.on as EqWhen).event == EqEvent.attachedToMe) _queue(unit, i, u.controller);
      }
      _eqQueueAppended(unit, (t) => t.on is EqWhen && (t.on as EqWhen).event == EqEvent.attachedToMe);
    }
  }

  /// Detaches [gear] (CR 436): it stays where its unit is; a gear left at a battlefield is
  /// recalled in the next cleanup (CR 436.4.a).
  void _eqDetach(ObjId gear, {bool quiet = false}) {
    final g = state.obj(gear);
    final unit = g.eq.attachedTo;
    if (unit < 0) return;
    final u = state.objOrNull(unit);
    if (u != null && u.zone == Zone.board) g.loc = u.loc;
    g.eq
      ..attachedTo = -1
      ..textOf = '';
    if (u != null && u.eq.copyVia == gear) {
      u.eq
        ..copyOf = ''
        ..copyVia = -1;
    }
    if (!quiet) log('${nameOf(gear)} is detached${u == null ? '' : ' from ${nameOf(unit)}'}.', player: g.controller, card: gear, kind: 'equip');
  }

  /// [id] is leaving the board: its attachments detach (CR 719.5), staying where it was (CR
  /// 436.4.b); control taken "until I leave the board" ends.
  void _eqLeaving(ObjId id) {
    final o = state.obj(id);
    if (o.zone != Zone.board) return;
    if (o.eq.attachedTo >= 0) _eqDetach(id, quiet: true);
    for (final g in attachedTo(id)) {
      state.obj(g).loc = o.loc;
      _eqDetach(g);
    }
    for (final x in state.objects.values) {
      if (x.eq.controlUntil == id) {
        x.eq.controlUntil = -1;
        if (x.zone == Zone.board && x.controller != x.owner) {
          x.controller = x.owner;
          log('${playerName(x.owner)} gets ${nameOf(x.id)} back.', player: x.owner, card: x.id, kind: 'info');
        }
      }
    }
  }

  /// Cleanup (CR 323): attachments whose unit is gone detach; attached cards are where their
  /// unit is; unattached gear at a battlefield is recalled (CR 149.3, 459.1). True if anything
  /// was recalled or detached.
  bool _eqCleanup() {
    var changed = false;
    for (final o in state.objects.values) {
      if (o.zone != Zone.board || card(o.id).type == CardType.unit) continue;
      final u = o.eq.attachedTo;
      if (u >= 0) {
        final uo = state.objOrNull(u);
        if (uo != null && uo.zone == Zone.board && card(u).type == CardType.unit) {
          o.loc = uo.loc;
          continue;
        }
        _eqDetach(o.id, quiet: true);
        changed = true;
      }
      if (o.loc != base && card(o.id).type == CardType.gear) {
        o.loc = base;
        log('${nameOf(o.id)} is recalled to base.', player: o.controller, card: o.id, kind: 'move');
        changed = true;
      }
    }
    return changed;
  }

  /// Guardian Angel (a replacement, CR 380): "If I would die, kill [it] instead. Heal me, exhaust
  /// me, and recall me." True if [id]'s death was replaced.
  bool _eqDieInstead(ObjId id) {
    final o = state.objOrNull(id);
    if (o == null || o.zone != Zone.board || card(id).type != CardType.unit) return false;
    for (final (_, _, a, via) in _eqAppended(id)) {
      if (a is! Static || a.passive is! EqDieInstead || state.obj(via).zone != Zone.board) continue;
      log('${nameOf(via)} dies in ${nameOf(id)}’s place.', player: o.controller, card: via, kind: 'die');
      _kill(via);
      o
        ..damage = 0
        ..exhausted = true
        ..loc = base;
      log('${nameOf(id)} is healed, exhausted and recalled.', player: o.controller, card: id, kind: 'move');
      return true;
    }
    return false;
  }

  // -------------------------------------------------------------------------------------------
  // Equip costs (CR 818.1.c), Weaponmaster (CR 821)
  // -------------------------------------------------------------------------------------------

  /// [equipment]'s Equip ability and its cost when attaching to [unit] (CR 818.1.c.4): the
  /// shared ability cost (game/power.dart, game/costs.dart), then, with [weaponmaster], one
  /// Power of any domain less (a discount, CR 821.1.c.3, 356.4.f). Null if it has none.
  (EqCost, int, List<Domain?>)? _eqEquipCost(ObjId equipment, ObjId unit, {bool weaponmaster = false}) {
    final eq = RiftboundParser.parse(db[_eqCardKey(equipment)]!).abilities.whereType<EqEquip>().firstOrNull;
    if (eq == null) return null;
    final p = state.obj(equipment).controller;
    final c = eq.eqCost;
    final ac = _activationCost(p, equipment, eq);
    var energy = _xAbilityEnergy(p, equipment, eq, ac.energy);
    if (c.lessByTargetMight) energy = energy - mightUsed(unit) < 0 ? 0 : energy - mightUsed(unit);
    final power = List<Domain?>.of(ac.power);
    if (weaponmaster && power.isNotEmpty) power.removeAt(0);
    return (c, energy, power);
  }

  /// Can [p] pay the parts of [c] beyond runes for [src]? (The shared cost parts, CR 202.)
  String? _eqExtraCostProblem(int p, ObjId src, Cost c) => c.extra.isEmpty ? null : _powerActivateProblem(p, src, -1, Activated('', c, const [])) ?? _xCostProblem(p, src, c);

  /// Pays the parts of [c] beyond runes (CR 202): as an activated ability's cost, or ([activated]
  /// false) as Weaponmaster pays an Equip cost, which isn't activating it (CR 821.1.c).
  void _eqPayExtraCost(int p, ObjId src, Cost c, {bool activated = true}) {
    final a = Activated('', c, const []);
    _powerPayExtra(p, src, a);
    if (activated) {
      _xPayCostExtra(p, src, a);
      return;
    }
    for (final part in c.extra) {
      if (part case RecycleTrash(:final n, :final unit)) {
        final options = [for (final id in state.player(p).trash) if (!unit || card(id).type == CardType.unit) id];
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Cost: recycle $n${unit ? ' unit' : ''} from your trash', options: options, min: n, max: n, source: src));
        _recycleCards(p, pick);
        log('${playerName(p)} recycles ${pick.length} from their trash.', player: p, kind: 'info');
      }
    }
  }

  /// Weaponmaster resolves (CR 821.1.c): [p] may choose an Equipment they control and pay its
  /// Equip cost less {A} to attach it to [unit], whatever the Equip ability's timing.
  void _eqWeaponmaster(ObjId unit, int p) {
    final u = state.objOrNull(unit);
    if (u == null || u.zone != Zone.board) return;
    final options = <ObjId>[];
    for (final o in state.objects.values) {
      if (o.zone != Zone.board || o.controller != p || !isEquipmentObj(o.id) || o.eq.attachedTo == unit) continue;
      final cost = _eqEquipCost(o.id, unit, weaponmaster: true);
      if (cost == null || _eqExtraCostProblem(p, o.id, cost.$1) != null || !canPay(p, cost.$2, cost.$3)) continue;
      options.add(o.id);
    }
    if (options.isEmpty) return;
    final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Weaponmaster: choose an Equipment to attach to ${nameOf(unit)} (its Equip cost less one Power)', options: options, min: 0, max: 1, source: unit));
    if (pick.isEmpty) return;
    final cost = _eqEquipCost(pick.first, unit, weaponmaster: true)!;
    _eqPayExtraCost(p, pick.first, cost.$1, activated: false);
    if (!canPay(p, cost.$2, cost.$3)) return;
    _pay(p, cost.$2, cost.$3);
    _eqAttach(pick.first, unit, p);
  }

  // -------------------------------------------------------------------------------------------
  // Activating Equip and other abilities with costs the core doesn't pay (CR 376, 818)
  // -------------------------------------------------------------------------------------------

  /// Activates [a] of [src]: [index] is the move's index (for "once per turn"); the chain item
  /// names [cardKey]'s ability [abilityIndex], with [via] as "this".
  void _eqActivate(int p, ObjId src, int index, Activated a, {String? cardKey, int? abilityIndex, int via = -1}) {
    final o = state.obj(src);
    final pl = state.player(p);
    if (a.legion && pl.playedThisTurn < 1) throw RiftboundError('Legion: play another card this turn first');
    final t = _timingProblem(p, a.timing);
    if (t != null) throw RiftboundError(t);
    if (a is EqActivated && a.onlyIfPlayedEquipment && state.eq.equipmentPlayed[p] != state.turn) throw RiftboundError('Use only if you’ve played an Equipment this turn');
    if (a.oncePerTurn && o.usedThisTurn.contains(index)) throw RiftboundError('Only once per turn');
    if (a.cost.exhaust && o.exhausted) throw RiftboundError('${nameOf(src)} is exhausted');
    final c = a.cost;
    final eqc = c is EqCost ? c : null;
    final problem = _eqExtraCostProblem(p, src, c);
    if (problem != null) throw RiftboundError(problem);
    // Choices first (CR 355), then costs (CR 357), worked out as for any activated ability.
    var targets = _chooseTargets(a.effects, p, src, o.loc);
    final ac = _activationCost(p, src, a);
    var energy = _xAbilityEnergy(p, src, a, ac.energy);
    if (eqc != null && eqc.lessByTargetMight && targets.isNotEmpty && targets[0] >= 0) energy = energy - mightUsed(targets[0]) < 0 ? 0 : energy - mightUsed(targets[0]);
    final power = <Domain?>[...ac.power, ..._xDeflect(p, src, targets)];
    final use = payFor(card(src).type);
    if (!canPay(p, energy, power, use: use)) throw RiftboundError('Not enough runes (${c.describe()})');
    _eqPayExtraCost(p, src, c);
    _pay(p, energy, power, use: use);
    if (c.exhaust) o.exhausted = true;
    o.usedThisTurn.add(index);
    final loc = o.loc;
    if (eqc != null && eqc.banishMe) {
      // "Banish this": the cards banished with it go with the ability (The Zero Drive).
      targets = [for (final b in state.objects.values) if (b.zone == Zone.banish && b.banishedBy == src) b.id]..sortStable((x, y) => x.compareTo(y));
      _eqBanish(src);
    }
    log('${playerName(p)} uses ${nameOf(src)}${a is EqEquip ? ' (Equip)' : ''}.', player: p, card: src, kind: 'ability');
    if (card(src).type == CardType.gear) _genEvent(GEv.gearAbility, player: p, obj: src);
    _pushChain(ChainItem(id: state.nextChainId++, source: src, card: cardKey ?? _eqCardKey(src), ability: abilityIndex ?? index, controller: p, targets: targets, loc: loc, via: via));
    if (state.showdown?.focus == p) state.showdown!.focusChain = true;
  }

  /// Activated abilities [src] has from elsewhere, by move index 1000 + k: from attached cards
  /// (a unit), and "friendly legends have …" (a legend).
  List<(String, int, Activated, ObjId)> _eqGrantedActivated(ObjId src) {
    final o = state.objOrNull(src);
    if (o == null) return const [];
    final out = <(String, int, Activated, ObjId)>[];
    if (o.zone == Zone.board) {
      for (final (key, i, a, via) in _eqAppended(src)) {
        if (a is Activated) out.add((key, i, a, via));
      }
    }
    if (o.zone == Zone.legend) {
      for (final b in state.bfs) {
        if (b.controller != o.controller) continue;
        final p = parsed(b.obj);
        for (final a in p.abilities) {
          if (a is Static && a.passive is EqGrantLegends) {
            final g = (a.passive as EqGrantLegends).ability;
            out.add((_eqCardKey(b.obj), 1000 + p.extra.indexOf(g), g, b.obj));
          }
        }
      }
    }
    return out;
  }

  void _eqActivateGranted(int p, ObjId src, int index) {
    final list = _eqGrantedActivated(src);
    final k = index - 1000;
    if (k < 0 || k >= list.length) throw RiftboundError('No such ability');
    final (key, i, a, via) = list[k];
    _eqActivate(p, src, index, a, cardKey: key, abilityIndex: i, via: via);
  }

  /// Candidate moves for abilities from elsewhere.
  List<RMove> _eqCandidates(int seat) {
    final pl = state.player(seat);
    final out = <RMove>[];
    for (final src in [?pl.legend, for (final o in _boardOf(seat)) o.id]) {
      final n = _eqGrantedActivated(src).length;
      for (var k = 0; k < n; k++) {
        out.add(ActivateMove(seat, src, 1000 + k));
      }
    }
    return out;
  }

  /// The ability an [ActivateMove] would use (for the app's labels and the bot).
  Ability? abilityOfMove(ActivateMove m) {
    if (m.index < 0) return null;
    if (m.index >= ws2BorrowBase) return _ws2AbilityOfMove(m);
    if (m.index >= 1000) {
      final list = _eqGrantedActivated(m.source);
      final k = m.index - 1000;
      return k < list.length ? list[k].$3 : null;
    }
    final abs = parsed(m.source).abilities;
    return m.index < abs.length ? abs[m.index] : null;
  }

  // -------------------------------------------------------------------------------------------
  // Playing (Quick-Draw, optional costs, playing from other zones)
  // -------------------------------------------------------------------------------------------

  /// Quick-Draw [id] has from elsewhere ("Each Equipment in your hand has [Quick-Draw]"): the
  /// granting card and its ability's chain index, or null.
  (String, int)? _eqGrantedQuickDraw(int p, ObjId id) {
    if (!isEquipmentObj(id) || parsed(id).abilities.any((a) => a is EqQuickDraw)) return null;
    for (final (src, x) in _eqPassivesOf(p)) {
      if (x is EqGrantQuickDraw) {
        final key = _eqCardKey(src);
        return (key, 1000 + RiftboundParser.parse(db[key]!).extra.indexOf(x.ability));
      }
    }
    return null;
  }

  /// Quick-Draw has Reaction (CR 819.1.b): when [id] can be played.
  Timing? _eqPlayTiming(int p, ObjId id) {
    if (card(id).type != CardType.gear) return null;
    if (parsed(id).abilities.any((a) => a is EqQuickDraw) || _eqGrantedQuickDraw(p, id) != null) return Timing.reaction;
    return null;
  }

  /// After [id] is played: Equipment played this turn, granted Quick-Draw.
  void _eqAfterPlay(int p, ObjId id, {(String, int)? quickDraw}) {
    if (isEquipmentObj(id)) state.eq.equipmentPlayed[p] = state.turn;
    if (quickDraw != null) _queue(id, quickDraw.$2, p, card: quickDraw.$1);
  }

  /// A token was played: "Your Sand Soldiers have [Weaponmaster]".
  void _eqTokenPlayed(ObjId id, int p) {
    for (final (src, x) in _eqPassivesOf(p)) {
      if (x is EqGrantWeaponmaster && card(id).name == x.name) {
        final key = _eqCardKey(src);
        _queue(id, 1000 + RiftboundParser.parse(db[key]!).extra.indexOf(x.ability), p, card: key);
      }
    }
  }

  /// Banishes a permanent or a card in a trash (CR 425).
  void _eqBanish(ObjId id) {
    final o = state.obj(id);
    final pl = state.player(o.owner);
    if (o.zone == Zone.board) {
      _eqLeaving(id);
      o.reset();
    } else if (o.zone == Zone.trash) {
      pl.trash.remove(id);
    } else {
      return;
    }
    if (card(id).token) {
      o.zone = Zone.gone;
      return;
    }
    o.zone = Zone.banish;
    pl.banish.add(id);
    log('${nameOf(id)} is banished.', player: o.owner, card: id, kind: 'info');
  }

  // -------------------------------------------------------------------------------------------
  // Triggers: conquests, holds, combat
  // -------------------------------------------------------------------------------------------

  /// Units at [bf] scoring it for [p]: conquest counts, "the first time I conquer each turn",
  /// "when I conquer an open battlefield", Relentless Pursuit's grant.
  void _eqScored(int p, int bf, bool conquer) {
    if (!conquer) return;
    for (final u in unitsAt(bf, player: p)) {
      final o = state.obj(u);
      o.eq
        ..conquests = o.eq.conquerTurn == state.turn ? o.eq.conquests + 1 : 1
        ..conquerTurn = state.turn;
      bool fires(Triggered t) {
        final on = t.on;
        if (on is! EqWhen) return false;
        return (on.event == EqEvent.firstConquer && o.eq.conquests == 1) || (on.event == EqEvent.conquerOpen && state.eq.openConquest == bf);
      }

      final abs = parsed(u).abilities;
      for (var i = 0; i < abs.length; i++) {
        final a = abs[i];
        if (a is Triggered && fires(a)) _queue(u, i, p, loc: bf);
      }
      _eqQueueAppended(u, fires, loc: bf);
      // "This turn, that unit has "When I conquer, …"".
      for (final g in o.eq.grants) {
        final parts = g.split('|');
        if (int.parse(parts[0]) != state.turn) continue;
        final a = _eqAbilityAt(db[parts[1]]!, int.parse(parts[2]));
        if (a is Triggered && a.on.on == On.conquer) _queue(u, int.parse(parts[2]), p, loc: bf, card: parts[1]);
      }
    }
  }

  /// [u]'s abilities from attached cards for [ons], and Skyfall of Areion ("My hold effects are
  /// also conquer effects, and vice versa"), once per ability.
  void _eqFireUnit(ObjId u, Set<On> ons) {
    final cross = _eqOwnPassives(u).any((x) => x.$1 is EqHoldIsConquer);
    final all = {...ons, if (cross && ons.contains(On.conquer)) On.hold, if (cross && ons.contains(On.hold)) On.conquer};
    final done = <String>[];
    if (all.length > ons.length) {
      final abs = parsed(u).abilities;
      for (var i = 0; i < abs.length; i++) {
        final a = abs[i];
        if (a is Triggered && all.contains(a.on.on)) done.add('$u|${a.text}');
      }
      for (var i = 0; i < abs.length; i++) {
        final a = abs[i];
        if (a is Triggered && all.contains(a.on.on) && !ons.contains(a.on.on) && !abs.any((b) => b is Triggered && ons.contains(b.on.on) && b.text == a.text)) _queue(u, i, state.obj(u).controller);
      }
    }
    for (final (key, i, a, via) in _eqAppended(u)) {
      if (a is! Triggered || !all.contains(a.on.on) || a.on is EqWhen) continue;
      final id = '$via|${a.text}';
      if (done.contains(id)) continue;
      done.add(id);
      _queue(u, i, state.obj(u).controller, card: key, via: via);
    }
  }

  // -------------------------------------------------------------------------------------------
  // Choosing and resolving
  // -------------------------------------------------------------------------------------------

  /// Conditions an [EqChoose] adds to its filter; [chosen] are the choices so far, by slot.
  bool _eqChoosable(Choose t, ObjId id, List<int> chosen) {
    if (t is! EqChoose) return true;
    if (t.equipped != null && isEquipped(id) != t.equipped) return false;
    if (t.attached != null && (attachedUnit(id) != null) != t.attached) return false;
    final s = t.sameControllerAs;
    if (s >= 0) {
      if (s >= chosen.length || chosen[s] < 0 || state.objOrNull(chosen[s]) == null) return false;
      if (state.obj(id).controller != state.obj(chosen[s]).controller) return false;
    }
    return true;
  }

  /// A mandatory choice of [e] with no target.
  bool _eqMissing(EqEffect e, List<int> targets) {
    for (final t in e.targets) {
      if (t is Choose && !t.upTo && (t.slot >= targets.length || targets[t.slot] < 0)) return true;
    }
    return false;
  }

  List<ObjId> _eqResolveTarget(EqTarget t, _Ctx ctx) => switch (t) {
        EqThis() => ctx.via >= 0 && state.objOrNull(ctx.via)?.zone == Zone.board ? [ctx.via] : const [],
      };

  int _eqAmount(EqAmount a, _Ctx ctx) => switch (a) {
        EqPerEquipment(:final n) => n * attachedTo(ctx.source).where(isEquipmentObj).length,
      };

  bool _eqCond(EqCond c, _Ctx ctx) => switch (c) {
        EqIsEquipment(:final slot) => slot < ctx.targets.length && ctx.targets[slot] >= 0 && state.objOrNull(ctx.targets[slot])?.zone == Zone.board && isEquipmentObj(ctx.targets[slot]),
        _ => state.objOrNull(ctx.source) != null && _eqHolds(c, ctx.source, ctx.via),
      };

  ObjId? _eqOne(Target t, _Ctx ctx) => _resolveTarget(t, ctx).firstOrNull;

  void _eqResolve(EqEffect e, _Ctx ctx) {
    final p = ctx.controller;
    switch (e) {
      case EqAttachMe(:final unit):
        final g = state.objOrNull(ctx.source);
        if (g == null || g.zone != Zone.board || g.controller != p) return;
        final u = _eqOne(unit, ctx);
        if (u != null && state.obj(u).controller == p) _eqAttach(ctx.source, u, p);
      case EqWeaponmasterAttach():
        _eqWeaponmaster(ctx.source, p);
      case EqAttachTo(:final equipment, :final unit):
        final g = _eqOne(equipment, ctx), u = _eqOne(unit, ctx);
        if (g != null && u != null) _eqAttach(g, u, p);
      case EqAttachOrDetach(:final unit, :final equipment):
        final g = _eqOne(equipment, ctx), u = _eqOne(unit, ctx);
        if (g == null || u == null) return;
        if (attachedUnit(g) == u) {
          final a = ask(Decision(kind: DecisionKind.option, player: p, prompt: '${nameOf(g)} is attached to ${nameOf(u)}', labels: const ['Leave it attached', 'Detach it'], source: ctx.source));
          if (a.first == 1) _eqDetach(g);
        } else {
          _eqAttach(g, u, p);
        }
      case EqDetach(:final equipment):
        for (final g in _resolveTarget(equipment, ctx)) {
          if (attachedUnit(g) != null) _eqDetach(g);
        }
      case EqDetachFrom(:final unit):
        final u = _eqOne(unit, ctx);
        if (u == null) return;
        final eqs = attachedTo(u).where(isEquipmentObj).toList();
        if (eqs.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose an Equipment to detach from ${nameOf(u)}', options: eqs, source: ctx.source));
        _eqDetach(pick.first);
      case EqChooseOnly():
        break;
      case EqTakeGear(:final gear):
        final g = _eqOne(gear, ctx);
        final src = state.objOrNull(ctx.source);
        if (g == null || src == null || src.zone != Zone.board) return;
        final go = state.obj(g);
        if (attachedUnit(g) != null) _eqDetach(g, quiet: true);
        go
          ..controller = p
          ..loc = base
          ..eq.controlUntil = ctx.source;
        log('${playerName(p)} takes ${nameOf(g)} until ${nameOf(ctx.source)} leaves the board.', player: p, card: g, kind: 'move');
        if (isEquipmentObj(g)) _eqAttach(g, ctx.source, p);
      case EqUnitDeals(:final unit, :final victim):
        final u = _eqOne(unit, ctx), v = _eqOne(victim, ctx);
        if (u == null || v == null || !isUnit(v)) return;
        final n = mightUsed(u);
        state.obj(v).damage += n;
        log('${nameOf(u)} deals $n to ${nameOf(v)}.', player: p, card: v, kind: 'damage', amount: n);
      case EqTokensPerEquipment(:final token, :final ready):
        final count = [for (final g in gearOf(p)) if (isEquipmentObj(g)) g].length;
        final made = <ObjId>[];
        for (var i = 0; i < count; i++) {
          final id = _newObj(token, p, Zone.board);
          _enterBoard(id, p, base, ready: false);
          made.add(id);
        }
        if (count > 0) log('${playerName(p)} plays $count $token token${count == 1 ? '' : 's'}.', player: p, kind: 'play');
        for (final id in made.take(ready)) {
          state.obj(id).exhausted = false;
        }
        for (final id in made) {
          _eqTokenPlayed(id, p);
        }
      case EqSwapWith(:final unit):
        final me = state.objOrNull(ctx.source);
        final it = _eqOne(unit, ctx);
        if (me == null || me.zone != Zone.board || it == null || it == ctx.source) return;
        final mine = me.loc, theirs = state.obj(it).loc;
        if (mine == theirs) return;
        _moveUnits([ctx.source], theirs, p);
        _moveUnits([it], mine, p);
      case EqTakeOneEquipment(:final unit):
        final it = _eqOne(unit, ctx);
        final me = state.objOrNull(ctx.source);
        if (it == null || me == null || me.zone != Zone.board) return;
        final eqs = attachedTo(it).where(isEquipmentObj).toList();
        if (eqs.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: '${nameOf(ctx.source)}: you may attach one of ${nameOf(it)}’s Equipment to it', options: eqs, min: 0, max: 1, source: ctx.source));
        if (pick.isNotEmpty) _eqAttach(pick.first, ctx.source, p);
      case EqMove(:final unit):
        final u = _eqOne(unit, ctx);
        if (u == null || !isUnit(u) || _eqUnmovable(u, p)) return;
        final here = state.obj(u).loc;
        final to = [for (final l in [base, for (var i = 0; i < state.bfs.length; i++) i]) if (l != here) l];
        if (to.isEmpty) return;
        final a = ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Move ${nameOf(u)} where?', labels: [for (final l in to) locName(l, state.obj(u).controller)], source: ctx.source));
        _moveUnits([u], to[a.first], p);
      case EqGrantThisTurn(:final unit, :final ability):
        final u = _eqOne(unit, ctx);
        if (u == null) return;
        final key = _eqCardKey(ctx.source);
        final i = RiftboundParser.parse(db[key]!).extra.indexOf(ability);
        if (i < 0) return;
        state.obj(u).eq.grants.add('${state.turn}|$key|${1000 + i}');
        log('${nameOf(u)} has “${ability.text}” this turn.', player: p, card: u, kind: 'buff');
      case EqMayPay(:final cost, :final effects):
        if (!canPay(p, cost.energy, cost.power)) return;
        if (!askYesNo(p, '${nameOf(ctx.source)}: pay ${cost.describe()} to ${effects.map(describeEffect).join(', ')}?', source: ctx.source)) return;
        _pay(p, cost.energy, cost.power);
        for (final x in effects) {
          _resolve(x, ctx);
        }
      case EqPlayFromTrash():
        final options = [
          for (final id in state.player(p).trash)
            if (card(id).type == CardType.unit && _xCanPlayNow(p, id, XPlay(effect: true, elsewhere: true))) id,
        ];
        if (options.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose a unit to play from your trash (paying its cost)', options: options, source: ctx.source));
        _xPlayAsEffect(p, pick.first, XPlay(effect: true, elsewhere: true));
      case EqPlayEquipmentFree(:final maxEnergy):
        final options = [
          for (final id in state.player(p).hand)
            if (isEquipmentObj(id) && card(id).energy <= maxEnergy && _xCanPlayNow(p, id, XPlay(effect: true, ignoreAll: true))) id,
        ];
        if (options.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose an Equipment to play free and attach to ${nameOf(ctx.source)}', options: options, source: ctx.source)).first;
        _xPlayAsEffect(p, pick, XPlay(effect: true, ignoreAll: true));
        final me = state.objOrNull(ctx.source);
        if (me != null && me.zone == Zone.board) _eqAttach(pick, ctx.source, p);
      case EqBanishMe():
        final me = state.objOrNull(ctx.source);
        if (me == null || me.zone != Zone.trash) return;
        _eqBanish(ctx.source);
        final via = state.objOrNull(ctx.via);
        if (via != null && via.zone == Zone.board) state.obj(ctx.source).banishedBy = ctx.via;
      case EqPlayBanishedWith():
        for (final id in ctx.targets) {
          if (state.objOrNull(id)?.zone == Zone.banish && card(id).type == CardType.unit) _xPlayAsEffect(p, id, XPlay(effect: true, ignoreAll: true, elsewhere: true));
        }
    }
  }
}
