part of 'game.dart';

/// Rulebook "Your Turn": the actions a player may take, in any order, before attacking.
extension TurnActions on Game {
  CardId _inHand(int p, CardId id) {
    final o = state.objOrNull(id);
    if (o == null || o.owner != p || o.zone != Place.hand) throw PokemonError('That card isn’t in your hand');
    return id;
  }

  CardId _inPlayOf(int p, CardId id) {
    final o = state.objOrNull(id);
    if (o == null || o.owner != p || (o.zone != Place.active && o.zone != Place.bench)) throw PokemonError('That isn’t one of your Pokémon in play');
    return id;
  }

  /// Put a Basic Pokémon onto the Bench (up to 5).
  void _playBasic(int p, CardId id) {
    _inHand(p, id);
    if (!card(id).isBasicPokemon) throw PokemonError('Only Basic Pokémon can be put onto the Bench');
    if (state.player(p).bench.length >= 5) throw PokemonError('Your Bench is full');
    _putIntoPlay(id, p, Place.bench);
    log('${state.player(p).name} puts ${nameOf(id)} onto the Bench.', player: p, card: id, kind: 'play');
  }

  /// Evolve: not during your first turn, and not a Pokémon that came into play or evolved this
  /// turn. Evolving removes Special Conditions and effects of attacks; damage and attached cards
  /// stay.
  void _evolve(int p, CardId id, CardId target) {
    _inHand(p, id);
    _inPlayOf(p, target);
    final c = card(id);
    if (!c.isPokemon || c.stage == Stage.basic) throw PokemonError('${c.name} isn’t an Evolution card');
    if (c.evolvesFrom != card(target).name) throw PokemonError('${c.name} evolves from ${c.evolvesFrom}, not ${card(target).name}');
    if (isFirstTurn(p)) throw PokemonError('You can’t evolve during your first turn');
    final t = state.obj(target);
    if (t.playedTurn == state.turn) throw PokemonError('${nameOf(target)} came into play or evolved this turn');
    final s = state;
    final pl = s.player(p);
    _detach(id);
    final o = s.obj(id);
    o
      ..zone = t.zone
      ..damage = t.damage
      ..energy = List.of(t.energy)
      ..tool = t.tool
      ..under = [...t.under, target]
      ..conds = []
      ..playedTurn = s.turn;
    for (final e in o.energy) {
      s.obj(e).host = id;
    }
    if (o.tool != null) s.obj(o.tool!).host = id;
    for (final u in o.under) {
      s.obj(u)
        ..zone = Place.under
        ..host = id;
    }
    t
      ..energy = []
      ..tool = null
      ..under = []
      ..damage = 0
      ..conds = [];
    if (pl.active == target) {
      pl.active = id;
    } else {
      pl.bench[pl.bench.indexOf(target)] = id;
    }
    s.timed.removeWhere((x) => x.target == target);
    s.version++;
    log('${pl.name} evolves ${card(target).name} into ${c.name}.', player: p, card: id, kind: 'evolve');
  }

  /// Attach 1 Energy card from your hand per turn.
  void _attachEnergy(int p, CardId id, CardId target) {
    _inHand(p, id);
    _inPlayOf(p, target);
    if (!card(id).isEnergy) throw PokemonError('That isn’t an Energy card');
    final pl = state.player(p);
    if (pl.energyAttached) throw PokemonError('You’ve already attached an Energy this turn');
    final pc = parsed(id);
    if (!card(id).basicEnergy && pc.provides == null) throw PokemonError('${nameOf(id)} isn’t supported yet');
    pl.energyAttached = true;
    _attach(id, target);
    log('${pl.name} attaches ${nameOf(id)} to ${nameOf(target)}.', player: p, card: target, kind: 'energy');
  }

  /// Play a Trainer: Items any number, 1 Supporter per turn (not on the first player's first
  /// turn), 1 Stadium per turn, Pokémon Tools onto a Pokémon without one.
  void _trainer(int p, CardId id, CardId? target) {
    _inHand(p, id);
    final c = card(id);
    if (!c.isTrainer) throw PokemonError('That isn’t a Trainer card');
    final pc = parsed(id);
    if (!pc.supported) throw PokemonError('${c.name} isn’t supported yet');
    final pl = state.player(p);
    switch (c.trainer!) {
      case TrainerKind.supporter:
        if (pl.supporterPlayed) throw PokemonError('You’ve already played a Supporter this turn');
        if (p == state.firstPlayer && state.turn == 1) throw PokemonError('The player going first can’t play a Supporter during their first turn');
      case TrainerKind.stadium:
        if (pl.stadiumPlayed) throw PokemonError('You’ve already played a Stadium this turn');
        final st = state.stadium;
        if (st != null && nameOf(st) == c.name) throw PokemonError('${c.name} is already in play');
      case TrainerKind.tool:
        if (target == null) throw PokemonError('Choose a Pokémon for the Tool');
        _inPlayOf(p, target);
        if (state.obj(target).tool != null) throw PokemonError('${nameOf(target)} already has a Pokémon Tool');
        _attach(id, target);
        log('${pl.name} attaches ${c.name} to ${nameOf(target)}.', player: p, card: target, kind: 'trainer');
        return;
      case TrainerKind.item:
        break;
    }
    log('${pl.name} plays ${c.name}.', player: p, card: id, kind: 'trainer');
    // The card leaves the hand while it resolves, then goes to the discard pile.
    _detach(id);
    state.obj(id).zone = Place.stadium;
    if (c.trainer == TrainerKind.supporter) pl.supporterPlayed = true;
    if (c.trainer == TrainerKind.stadium) {
      pl.stadiumPlayed = true;
      final old = state.stadium;
      if (old != null) {
        state.stadium = null;
        _moveTo(old, Place.discard);
      }
      state.stadium = id;
      return;
    }
    final ctx = _Ctx(p, trainer: true);
    _run1(pc.trainer!, ctx);
    final o = state.obj(id);
    if (o.zone == Place.stadium && state.stadium != id) {
      o.zone = Place.discard;
      pl.discard.add(id);
      state.version++;
    }
    _knockOuts();
    if (ctx.endTurn && !state.over) _endTurn();
  }

  /// Retreat once per turn: discard Energy equal to the Retreat Cost; Asleep or Paralyzed
  /// Pokémon can't. Special Conditions and effects of attacks end.
  void _retreat(int p, CardId to) {
    final pl = state.player(p);
    final a = pl.active;
    if (a == null) throw PokemonError('No Active Pokémon');
    if (!pl.bench.contains(to)) throw PokemonError('Choose one of your Benched Pokémon');
    if (pl.retreated) throw PokemonError('You’ve already retreated this turn');
    final o = state.obj(a);
    if (o.conds.contains(Cond.asleep) || o.conds.contains(Cond.paralyzed)) throw PokemonError('${nameOf(a)} is ${o.conds.contains(Cond.asleep) ? 'Asleep' : 'Paralyzed'} and can’t retreat');
    if (state.timed.any((t) => t.target == a && t.kind == Lasting.defenderCantRetreat && t.until >= state.turn)) throw PokemonError('${nameOf(a)} can’t retreat this turn');
    final cost = retreatCost(a);
    if (o.energy.length < cost) throw PokemonError('${nameOf(a)} needs $cost Energy to retreat');
    final pay = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Discard $cost Energy to retreat', options: List.of(o.energy), min: cost, max: cost, source: a));
    for (final e in pay) {
      _moveTo(e, Place.discard);
    }
    pl.retreated = true;
    _swapActive(p, to);
    log('${pl.name} retreats ${nameOf(a)} for ${nameOf(to)}.', player: p, card: to, kind: 'retreat');
  }

  int retreatCost(CardId id) {
    final tool = state.obj(id).tool;
    if (tool != null && parsed(tool).tool is ToolNoRetreat) return 0;
    return card(id).retreat;
  }

  /// The Active Pokémon goes to the Bench (losing Special Conditions and effects of attacks) and
  /// [to] becomes Active.
  void _swapActive(int p, CardId to) {
    final s = state;
    final pl = s.player(p);
    final a = pl.active;
    pl.bench.remove(to);
    if (a != null) {
      pl.bench.add(a);
      final ao = s.obj(a);
      ao
        ..zone = Place.bench
        ..conds = [];
      s.timed.removeWhere((t) => t.target == a);
    }
    pl.active = to;
    s.obj(to).zone = Place.active;
    s.version++;
  }

  void _ability(int p, CardId id, int index) {
    _inPlayOf(p, id);
    final abs = parsed(id).abilities;
    if (index < 0 || index >= abs.length) throw PokemonError('No such Ability');
    final ab = abs[index];
    if (ab is! OncePerTurn) throw PokemonError(ab == null ? 'That Ability isn’t supported yet' : 'That Ability works on its own');
    final o = state.obj(id);
    if (o.abilityTurn == state.turn) throw PokemonError('${nameOf(id)} has already used ${card(id).abilities[index].name} this turn');
    if (ab.activeOnly && state.player(p).active != id) throw PokemonError('${nameOf(id)} must be in the Active Spot');
    o.abilityTurn = state.turn;
    log('${nameOf(id)} uses ${card(id).abilities[index].name}.', player: p, card: id, kind: 'ability');
    final ctx = _Ctx(p, source: id, trainer: true);
    _run1(ab.effect, ctx);
    _knockOuts();
    if (ctx.endTurn && !state.over) _endTurn();
  }

  /// Rulebook "Attacking": check Energy, Special Conditions (Confused flips), apply the
  /// attack, Knock Outs, then the turn ends.
  void _attack(int p, int index) {
    final pl = state.player(p);
    final a = pl.active;
    if (a == null) throw PokemonError('No Active Pokémon');
    if (p == state.firstPlayer && state.turn == 1) throw PokemonError('The player going first can’t attack during their first turn');
    final c = card(a);
    if (index < 0 || index >= c.attacks.length) throw PokemonError('No such attack');
    final eff = parsed(a).attacks[index];
    if (eff == null) throw PokemonError('${c.attacks[index].name} isn’t supported yet');
    final o = state.obj(a);
    if (o.conds.contains(Cond.asleep)) throw PokemonError('${c.name} is Asleep');
    if (o.conds.contains(Cond.paralyzed)) throw PokemonError('${c.name} is Paralyzed');
    if (state.timed.any((t) => t.target == a && t.kind == Lasting.selfCantAttack && t.until >= state.turn && t.n <= state.turn)) throw PokemonError('${c.name} can’t attack this turn');
    if (!canPay(a, c.attacks[index].cost)) throw PokemonError('${c.name} doesn’t have the Energy for ${c.attacks[index].name}');
    final atk = c.attacks[index];
    log('${c.name} uses ${atk.name}.', player: p, card: a, kind: 'attack');
    if (o.conds.contains(Cond.confused) && !flip(p, why: 'Confused')) {
      o.damage += 30;
      log('${c.name} is Confused and hurts itself: 3 damage counters.', player: p, card: a, kind: 'damage', amount: 30);
    } else {
      _resolveAttack(p, a, atk, eff);
    }
    _knockOuts();
    if (!state.over) _endTurn();
  }

  /// Whether the Energy attached to [id] pays [cost] (specific types first, then Colorless).
  bool canPay(CardId id, List<PType> cost) {
    final have = <PType?>[for (final e in state.obj(id).energy) energyProvided(e)];
    for (final t in cost) {
      if (t == PType.colorless) continue;
      final i = have.indexOf(t);
      if (i < 0) return false;
      have.removeAt(i);
    }
    final colorless = cost.where((t) => t == PType.colorless).length;
    return have.length >= colorless;
  }

  /// The type an attached Energy card provides (Colorless for unknown Special Energy).
  PType energyProvided(CardId e) {
    final c = card(e);
    if (c.basicEnergy) return c.energyType ?? PType.colorless;
    return parsed(e).provides ?? PType.colorless;
  }
}
