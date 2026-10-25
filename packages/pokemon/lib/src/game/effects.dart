part of 'game.dart';

/// Which effects a pass runs: attacks first work out their damage (coin flips, "more damage",
/// "does nothing") and deal it, then do the rest in printed order with the same flips.
enum _Pass { all, pre, post }

class _Ctx {
  _Ctx(this.player, {this.source, this.trainer = false});
  final int player;

  /// The attacking Pokémon, or the one with the Ability.
  final CardId? source;

  /// A Trainer (or Ability) must be able to do what it says; an attack just does what it can.
  final bool trainer;
  int damage = 0;
  bool nothing = false;
  bool noWeakness = false, noResistance = false, ignoreDefender = false;
  bool endTurn = false;
  final List<List<bool>> flips = [];
  int flipRead = 0;
  List<bool> last = const [];
}

extension Effects on Game {
  void _run1(Eff e, _Ctx c) => _exec1(e, c, _Pass.all);

  void _exec1(Eff e, _Ctx c, _Pass pass) {
    final s = state;
    switch (e) {
      case Seq(:final steps):
        for (final x in steps) {
          if (s.over) return;
          _exec1(x, c, pass);
        }
      case Flip(:final n):
        if (pass == _Pass.post) {
          c.last = c.flipRead < c.flips.length ? c.flips[c.flipRead++] : const [];
          return;
        }
        final r = <bool>[];
        if (n == 0) {
          for (var i = 0; i < 50; i++) {
            final h = flip(c.player);
            r.add(h);
            if (!h) break;
          }
        } else {
          for (var i = 0; i < n; i++) {
            r.add(flip(c.player));
          }
        }
        c.flips.add(r);
        c.last = r;
      case IfHeads(:final then):
        if (c.last.isNotEmpty && c.last.first) _exec1(then, c, pass);
      case IfTails(:final then):
        if (c.last.isNotEmpty && !c.last.first) _exec1(then, c, pass);
      case ForEachHeads(:final each):
        final n = c.last.where((h) => h).length;
        for (var i = 0; i < n; i++) {
          _exec1(each, c, pass);
        }
      case IfCheck(:final check, :final then):
        if (_check(check, c)) _exec1(then, c, pass);
      case NoDamage():
        if (pass != _Pass.post) c.nothing = true;
      case DamagePer(:final n, :final per):
        if (pass != _Pass.post) c.damage = n * _count(per, c);
      case MoreDamage(:final n, :final per):
        if (pass != _Pass.post) c.damage += n * (per == null ? 1 : _count(per, c));
      case DamageRules(:final noWeakness, :final noResistance, :final ignoreDefenderEffects):
        if (pass != _Pass.post) {
          c.noWeakness |= noWeakness;
          c.noResistance |= noResistance;
          c.ignoreDefender |= ignoreDefenderEffects;
        }
      case DiscardOppTools():
        if (pass != _Pass.post) {
          final d = s.player(s.opponent(c.player)).active;
          final t = d == null ? null : s.obj(d).tool;
          if (t != null) {
            _moveTo(t, Place.discard);
            log('${nameOf(t)} is discarded.', player: c.player, kind: 'trainer');
          }
        }
      default:
        if (pass == _Pass.pre) return;
        _effect(e, c);
    }
  }

  int _count(Count n, _Ctx c) {
    final s = state;
    final me = s.player(c.player), opp = s.player(s.opponent(c.player));
    switch (n) {
      case Heads():
        return c.last.where((h) => h).length;
      case EnergyOn(:final who, :final type):
        final ids = switch (who) { Who.self => [?c.source], Who.oppActive => [?opp.active], Who.eachOwn => me.inPlay, _ => <CardId>[] };
        var k = 0;
        for (final id in ids) {
          for (final e in s.obj(id).energy) {
            if (type == null || energyProvided(e) == type) k++;
          }
        }
        return k;
      case DamageCountersOn(:final who):
        final id = who == Who.self ? c.source : opp.active;
        return id == null ? 0 : s.obj(id).damage ~/ 10;
      case BenchedCount(:final own, :final opp):
        return (own ? me.bench.length : 0) + (opp ? s.player(s.opponent(c.player)).bench.length : 0);
      case HandCount(:final own):
        return own ? me.hand.length : opp.hand.length;
      case PrizesTaken(:final own):
        return 6 - (own ? me.prizes.length : opp.prizes.length);
      case DiscardCount(:final filter):
        return me.discard.where((id) => filter.matches(card(id))).length;
    }
  }

  bool _check(Check k, _Ctx c) {
    final s = state;
    final d = s.player(s.opponent(c.player)).active;
    final self = c.source == null ? null : s.obj(c.source!);
    return switch (k) {
      Check.oppActiveIsEx => d != null && card(d).ex,
      Check.oppActiveDamaged => d != null && s.obj(d).damage > 0,
      Check.oppActiveHasCondition => d != null && s.obj(d).conds.isNotEmpty,
      Check.selfDamaged => self != null && self.damage > 0,
      Check.selfHasNoDamage => self != null && self.damage == 0,
      Check.oppActivePoisoned => d != null && s.obj(d).conds.contains(Cond.poisoned),
      Check.oppActiveIsEvolution => d != null && card(d).stage != Stage.basic,
    };
  }

  /// The Pokémon an effect touches; asks when it says "1 of". Empty when there are none (a
  /// Trainer that needs one can't be played).
  List<CardId> _targets(Who who, _Ctx c, String prompt, {bool Function(CardId)? only}) {
    final s = state;
    final me = s.player(c.player), opp = s.player(s.opponent(c.player));
    List<CardId> pick(int chooser, List<CardId> from) {
      final opts = [for (final id in from) if (only == null || only(id)) id];
      if (opts.isEmpty) {
        if (c.trainer) throw PokemonError('There’s no Pokémon to choose');
        return const [];
      }
      return ask(Decision(kind: DecisionKind.cards, player: chooser, prompt: prompt, options: opts, source: c.source));
    }

    return switch (who) {
      Who.self => [?c.source],
      Who.oppActive => [?opp.active],
      Who.ownActive => [?me.active],
      Who.chooseOwn => pick(c.player, me.inPlay),
      Who.chooseOwnBench => pick(c.player, me.bench),
      Who.chooseOpp => pick(c.player, opp.inPlay),
      Who.chooseOppBench => pick(c.player, opp.bench),
      Who.eachOwn => [for (final id in me.inPlay) if (only == null || only(id)) id],
      Who.eachOwnBench => [for (final id in me.bench) if (only == null || only(id)) id],
      Who.eachOpp => List.of(opp.inPlay),
      Who.eachOppBench => List.of(opp.bench),
    };
  }

  bool _protected(CardId id, _Ctx c) =>
      !c.ignoreDefender && state.obj(id).owner != c.player && state.timed.any((t) => t.target == id && t.kind == Lasting.selfPreventAll && t.until >= state.turn);

  void _effect(Eff e, _Ctx c) {
    final s = state;
    final me = s.player(c.player), oppSeat = s.opponent(c.player), opp = s.player(oppSeat);
    switch (e) {
      case DamageTo(:final n, :final who):
        for (final t in _targets(who, c, 'Choose a Pokémon to take $n damage')) {
          _damageTo(c, t, n);
        }
      case Counters(:final n, :final who):
        for (final t in _targets(who, c, 'Choose a Pokémon for $n damage counter${n == 1 ? '' : 's'}')) {
          if (_protected(t, c)) continue;
          s.obj(t).damage += 10 * n;
          log('${nameOf(t)} gets $n damage counter${n == 1 ? '' : 's'}.', player: s.obj(t).owner, card: t, kind: 'damage', amount: 10 * n);
        }
      case Afflict(:final who, :final conds):
        final id = who == Who.self ? c.source : opp.active;
        if (id == null || (who != Who.self && _protected(id, c))) return;
        for (final k in conds) {
          _afflict(id, k);
        }
      case Draw(:final n, :final upTo, :final untilHandSize, :final may):
        var k = untilHandSize ? (n - me.hand.length).clamp(0, n) : n;
        if (k == 0) {
          if (c.trainer && !may) throw PokemonError('You already have $n cards');
          return;
        }
        if (me.deck.isEmpty && c.trainer) throw PokemonError('Your deck is empty');
        if (may && !askYesNo(c.player, 'Draw ${untilHandSize ? 'until you have $n cards' : '$k card${k == 1 ? '' : 's'}'}?', source: c.source)) return;
        if (upTo) {
          k = ask(Decision(kind: DecisionKind.option, player: c.player, prompt: 'Draw how many?', labels: [for (var i = 0; i <= k; i++) 'Draw $i'])).first;
        }
        for (var i = 0; i < k; i++) {
          if (!_draw(c.player)) break;
        }
      case Heal(:final n, :final who, :final all):
        final ts = _targets(who, c, 'Choose a Pokémon to heal', only: (id) => s.obj(id).damage > 0);
        for (final t in ts) {
          final o = s.obj(t);
          final h = all ? o.damage : (n < o.damage ? n : o.damage);
          o.damage -= h;
          if (h > 0) log('${nameOf(t)} heals $h damage.', player: o.owner, card: t, kind: 'heal', amount: h);
        }
      case DiscardEnergy(:final n, :final who, :final type):
        final id = who == Who.self ? c.source : opp.active;
        if (id == null || (who != Who.self && _protected(id, c))) return;
        final o = s.obj(id);
        final opts = [for (final x in o.energy) if (type == null || energyProvided(x) == type) x];
        if (opts.isEmpty) return;
        final k = n < 0 || n >= opts.length ? opts.length : n;
        final pick = k == opts.length ? opts : ask(Decision(kind: DecisionKind.cards, player: c.player, prompt: 'Discard $k Energy from ${nameOf(id)}', options: opts, min: k, max: k, source: c.source));
        for (final x in pick) {
          _moveTo(x, Place.discard);
        }
        log('${pick.length} Energy discarded from ${nameOf(id)}.', player: o.owner, card: id, kind: 'energy', amount: -pick.length);
      case Switch(:final kind):
        _switch(kind, c);
      case Search(:final n, :final filter, :final dest, :final upTo):
        _search(c, n, filter, dest, upTo, fromDiscard: false);
      case AttachFromDiscard(:final n, :final type, :final dest, :final upTo):
        _search(c, n, CardFilter(basicEnergy: true, type: type), dest, upTo, fromDiscard: true);
      case MoveEnergy(:final fromSelf, :final basicOnly):
        final froms = fromSelf ? [?c.source] : [for (final id in me.inPlay) if (s.obj(id).energy.any((x) => !basicOnly || card(x).basicEnergy)) id];
        final from = froms.isEmpty ? null : (froms.length == 1 ? froms.first : ask(Decision(kind: DecisionKind.cards, player: c.player, prompt: 'Move Energy from which Pokémon?', options: froms)).first);
        final targets = [for (final id in fromSelf ? me.bench : me.inPlay) if (id != from) id];
        if (from == null || targets.isEmpty) {
          if (c.trainer) throw PokemonError('No Energy to move');
          return;
        }
        final es = [for (final x in s.obj(from).energy) if (!basicOnly || card(x).basicEnergy) x];
        if (es.isEmpty) {
          if (c.trainer) throw PokemonError('No Energy to move');
          return;
        }
        final energy = ask(Decision(kind: DecisionKind.cards, player: c.player, prompt: 'Move which Energy?', options: es)).first;
        final to = ask(Decision(kind: DecisionKind.cards, player: c.player, prompt: 'Move it to which Pokémon?', options: targets)).first;
        _attach(energy, to);
        log('${nameOf(energy)} moves from ${nameOf(from)} to ${nameOf(to)}.', player: c.player, card: to, kind: 'energy');
      case MillSelf(:final n):
        for (var i = 0; i < n && me.deck.isNotEmpty; i++) {
          _moveTo(me.deck.first, Place.discard);
        }
        log('${me.name} discards the top $n card${n == 1 ? '' : 's'} of their deck.', player: c.player);
      case FromDiscard(:final n, :final filter, :final upTo):
        _search(c, n, filter, Dest.hand, upTo, fromDiscard: true);
      case MillOpponent(:final n):
        for (var i = 0; i < n && opp.deck.isNotEmpty; i++) {
          _moveTo(opp.deck.first, Place.discard);
        }
        log('${opp.name} discards the top $n card${n == 1 ? '' : 's'} of their deck.', player: oppSeat);
      case DiscardRandomFromOppHand(:final n):
        for (var i = 0; i < n && opp.hand.isNotEmpty; i++) {
          final id = opp.hand[s.rng.nextInt(opp.hand.length)];
          _moveTo(id, Place.discard);
          log('${opp.name} discards ${nameOf(id)} at random.', player: oppSeat, card: id);
        }
      case RevealOppHand():
        log('${opp.name} reveals: ${opp.hand.map(nameOf).join(', ')}.', player: oppSeat);
      case ShuffleHandIn(:final each, :final draw):
        for (final p in each ? [c.player, oppSeat] : [c.player]) {
          final pl = s.player(p);
          for (final id in List.of(pl.hand)) {
            _moveTo(id, Place.deck);
          }
          s.rng.shuffle(pl.deck);
          log('${pl.name} shuffles their hand into their deck.', player: p);
          for (var i = 0; i < draw; i++) {
            if (!_draw(p)) break;
          }
        }
      case DiscardHand():
        for (final id in List.of(me.hand)) {
          _moveTo(id, Place.discard);
        }
        log('${me.name} discards their hand.', player: c.player);
      case Lingering(:final kind, :final n):
        final t = s.turn;
        switch (kind) {
          case Lasting.selfCantAttack:
            if (c.source != null) s.timed.add(Timed(kind, c.source!, t + 1, t + 2));
          case Lasting.selfTakesLess || Lasting.selfPreventAll:
            if (c.source != null) s.timed.add(Timed(kind, c.source!, n, t + 1));
          case Lasting.defenderCantRetreat || Lasting.defenderDoesLess:
            final d = opp.active;
            if (d != null && !_protected(d, c)) s.timed.add(Timed(kind, d, n, t + 1));
        }
      case EndTurn():
        c.endTurn = true;
      default:
        break;
    }
    s.version++;
  }

  /// Damage from an attack or effect to [target]. The Defending (Active) Pokémon applies
  /// Weakness (×2) and Resistance; Benched ones don't (rulebook "Attacking").
  int _damageTo(_Ctx c, CardId target, int amount, {bool main = false}) {
    final s = state;
    if (amount <= 0) return 0;
    final o = s.obj(target);
    final atk = c.source;
    var d = amount;
    final isOppActive = o.owner != c.player && s.player(o.owner).active == target;
    if (atk != null && isOppActive) {
      // Before Weakness and Resistance: effects on the attacker, Tools.
      for (final t in s.timed) {
        if (t.target == atk && t.kind == Lasting.defenderDoesLess && t.until >= s.turn) d -= t.n;
      }
      final tool = s.obj(atk).tool;
      if (tool != null) {
        final ti = parsed(tool).tool;
        if (ti is ToolDamage) d += ti.n;
      }
      if (d <= 0) return 0;
      final types = card(atk).types;
      final tc = card(target);
      if (!c.noWeakness && tc.weakness != null && types.contains(tc.weakness)) d *= 2;
      if (!c.noResistance && tc.resistance != null && types.contains(tc.resistance)) d -= tc.resistanceAmount;
    }
    // Effects on the Pokémon taking the damage.
    if (o.owner != c.player && !c.ignoreDefender) {
      if (_protected(target, c)) return 0;
      for (final t in s.timed) {
        if (t.target == target && t.kind == Lasting.selfTakesLess && t.until >= s.turn) d -= t.n;
      }
      for (final ab in parsed(target).abilities) {
        if (ab is TakesLess) d -= ab.n;
      }
      final tool = o.tool;
      if (tool != null) {
        final ti = parsed(tool).tool;
        if (ti is ToolTakesLess) d -= ti.n;
      }
    }
    // Tera: no damage from attacks while Benched.
    if (o.zone == Place.bench && card(target).tera) return 0;
    if (d <= 0) return 0;
    o.damage += d;
    log('${nameOf(target)} takes $d damage.', player: o.owner, card: target, kind: 'damage', amount: d);
    s.version++;
    return d;
  }

  void _afflict(CardId id, Cond k) {
    final o = state.obj(id);
    if (o.zone != Place.active) return;
    // Asleep, Confused and Paralyzed replace each other; Burned and Poisoned add.
    if (k == Cond.asleep || k == Cond.confused || k == Cond.paralyzed) {
      o.conds.removeWhere((x) => x == Cond.asleep || x == Cond.confused || x == Cond.paralyzed);
    }
    if (!o.conds.contains(k)) o.conds.add(k);
    if (k == Cond.paralyzed) o.paralyzedTurn = state.turn;
    log('${nameOf(id)} is now ${k.name[0].toUpperCase()}${k.name.substring(1)}.', player: o.owner, card: id, kind: 'condition');
    state.version++;
  }

  void _switch(SwitchKind kind, _Ctx c) {
    final s = state;
    final me = s.player(c.player), oppSeat = s.opponent(c.player), opp = s.player(oppSeat);
    switch (kind) {
      case SwitchKind.self || SwitchKind.ownActive || SwitchKind.selfMay:
        if (kind != SwitchKind.ownActive && me.active != c.source) return;
        if (kind == SwitchKind.selfMay && (me.bench.isEmpty || !askYesNo(c.player, 'Switch ${nameOf(c.source!)} with a Benched Pokémon?', source: c.source))) return;
        if (me.bench.isEmpty || me.active == null) {
          if (c.trainer) throw PokemonError('You have no Benched Pokémon');
          return;
        }
        final to = ask(Decision(kind: DecisionKind.cards, player: c.player, prompt: 'Switch with which Benched Pokémon?', options: List.of(me.bench), source: c.source)).first;
        final from = me.active!;
        _swapActive(c.player, to);
        log('${me.name} switches ${nameOf(from)} with ${nameOf(to)}.', player: c.player, card: to, kind: 'retreat');
      case SwitchKind.oppOut:
        if (opp.bench.isEmpty || opp.active == null) {
          if (c.trainer) throw PokemonError('Your opponent has no Benched Pokémon');
          return;
        }
        if (_protected(opp.active!, c)) return;
        final to = ask(Decision(kind: DecisionKind.cards, player: oppSeat, prompt: 'Choose your new Active Pokémon', options: List.of(opp.bench))).first;
        _swapActive(oppSeat, to);
        log('${opp.name} switches in ${nameOf(to)}.', player: oppSeat, card: to, kind: 'retreat');
      case SwitchKind.gust:
        if (opp.bench.isEmpty) {
          if (c.trainer) throw PokemonError('Your opponent has no Benched Pokémon');
          return;
        }
        final to = ask(Decision(kind: DecisionKind.cards, player: c.player, prompt: 'Switch in which of your opponent’s Benched Pokémon?', options: List.of(opp.bench))).first;
        _swapActive(oppSeat, to);
        log('${me.name} brings ${nameOf(to)} into the Active Spot.', player: c.player, card: to, kind: 'retreat');
    }
  }

  /// Search the deck (or take from the discard pile) for cards matching [f]: into the hand,
  /// onto the Bench, or attached to Pokémon. A searched deck is shuffled.
  void _search(_Ctx c, int n, CardFilter f, Dest dest, bool upTo, {required bool fromDiscard}) {
    final s = state;
    final me = s.player(c.player);
    final from = fromDiscard ? me.discard : me.deck;
    var matches = [for (final id in from) if (f.matches(card(id))) id];
    var room = n;
    if (dest == Dest.bench) room = (5 - me.bench.length).clamp(0, n);
    if ((dest == Dest.attachBench && me.bench.isEmpty) || (dest == Dest.attachSelf && c.source == null)) room = 0;
    if (fromDiscard && matches.isEmpty && c.trainer) throw PokemonError('Nothing in your discard pile to take');
    if (dest == Dest.bench && room == 0 && c.trainer) throw PokemonError('Your Bench is full');
    final k = matches.length < room ? matches.length : room;
    // Sorted by card, so the list shown doesn't give away the deck's order.
    matches = List.of(matches)..sortStable((a, b) => s.obj(a).card.compareTo(s.obj(b).card));
    final chosen = k == 0 ? const <int>[] : ask(Decision(kind: DecisionKind.cards, player: c.player, prompt: '${fromDiscard ? 'Take' : 'Search your deck for'} ${upTo ? 'up to ' : ''}$k $f', options: matches, min: upTo ? 0 : k, max: k, source: c.source));
    for (final id in chosen) {
      switch (dest) {
        case Dest.hand:
          _moveTo(id, Place.hand);
          log('${me.name} puts ${nameOf(id)} into their hand.', player: c.player, card: id, kind: 'draw');
        case Dest.bench:
          _putIntoPlay(id, c.player, Place.bench);
          log('${me.name} puts ${nameOf(id)} onto the Bench.', player: c.player, card: id, kind: 'play');
        case Dest.attachSelf:
          _attach(id, c.source!);
          log('${nameOf(id)} is attached to ${nameOf(c.source!)}.', player: c.player, card: c.source, kind: 'energy');
        case Dest.attachBench || Dest.attachAny:
          final opts = List.of(dest == Dest.attachBench ? me.bench : me.inPlay);
          final to = ask(Decision(kind: DecisionKind.cards, player: c.player, prompt: 'Attach ${nameOf(id)} to which Pokémon?', options: opts, source: c.source)).first;
          _attach(id, to);
          log('${nameOf(id)} is attached to ${nameOf(to)}.', player: c.player, card: to, kind: 'energy');
      }
    }
    if (!fromDiscard) {
      s.rng.shuffle(me.deck);
      log('${me.name} shuffles their deck.', player: c.player);
    }
  }

  void _resolveAttack(int p, CardId attacker, Attack atk, Eff eff) {
    final c = _Ctx(p, source: attacker)..damage = atk.mod == '×' ? 0 : atk.damage;
    _exec1(eff, c, _Pass.pre);
    if (c.nothing) {
      log('${atk.name} does nothing.', player: p, card: attacker, kind: 'attack');
      return;
    }
    final d = state.player(state.opponent(p)).active;
    if (d != null && c.damage > 0) _damageTo(c, d, c.damage, main: true);
    _exec1(eff, c, _Pass.post);
  }
}
