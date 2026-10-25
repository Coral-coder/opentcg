part of 'game.dart';

extension GameTurnActions on Game {
  /// Throws if [move] can't be started now. Nothing changes.
  void _validate(LMove move) {
    final why = whyNot(move);
    if (why != null) throw LorcanaError(why);
  }

  /// Why [move] isn't possible right now, or null if it is.
  String? whyNot(LMove move) {
    final s = state;
    if (s.over) return 'The game is over';
    if (pending != null) return 'Answer the question first';
    if (move is ConcedeMove) return null;
    if (s.phase != Phase.main) return 'Not now';
    if (move.seat != s.active) return 'Not your turn';
    final p = move.seat;
    String? inPlay(CardId id) {
      final o = s.objOrNull(id);
      if (o == null || o.zone != Place.play || o.owner != p) return 'That card isn’t yours in play';
      return null;
    }

    switch (move) {
      case InkMove(:final card):
        final o = s.objOrNull(card);
        if (o == null || o.zone != Place.hand || o.owner != p) return 'That card isn’t in your hand';
        if (!db[o.card]!.inkable) return 'That card has no inkwell symbol';
        if (s.player(p).inkedThisTurn >= _inkAllowance(p)) return 'You’ve already put a card into your inkwell this turn';
        return null;
      case PlayMove():
        return _playProblem(move);
      case QuestMove(:final card):
        final e = inPlay(card);
        if (e != null) return e;
        final c = chars(card);
        if (c.type != CardType.character) return 'Only characters can quest';
        if (!s.obj(card).dry) return '${c.card.name} is still drying (played this turn)';
        if (s.obj(card).exerted) return '${c.card.name} is exerted';
        if (c.has(Kw.reckless)) return '${c.card.name} is Reckless and can’t quest';
        if (c.rules.contains(Rule.cantQuest)) return '${c.card.name} can’t quest';
        return null;
      case ChallengeMove(:final card, :final target):
        return _challengeProblem(p, card, target);
      case MoveMove(:final card, :final location):
        final e = inPlay(card) ?? inPlay(location);
        if (e != null) return e;
        if (chars(card).type != CardType.character) return 'Only characters move to locations';
        if (chars(location).type != CardType.location) return 'That isn’t a location';
        if (s.obj(card).at == location) return 'Already there';
        if (_inkReady(p) < _moveCost(p, card, location)) return 'Not enough ink to move there';
        return null;
      case ActivateMove(:final card, :final index):
        return _activateProblem(p, card, index);
      case EndTurnMove():
        // Reckless (CR 8.7.3): can't end the turn while a ready Reckless character can challenge.
        for (final id in s.player(p).play) {
          final c = chars(id);
          if (!c.has(Kw.reckless) || s.obj(id).exerted || !s.obj(id).dry && !c.has(Kw.rush)) continue;
          for (final t in _challengeTargets(p, id)) {
            if (_challengeProblem(p, id, t) == null) return '${c.card.name} is Reckless: challenge with them before ending the turn';
          }
        }
        // "Must quest if able": a character that can quest has to before the turn ends.
        for (final id in s.player(p).play) {
          if (chars(id).rules.contains(Rule.mustQuest) && whyNot(QuestMove(p, id)) == null) return '${chars(id).card.name} must quest this turn if able';
        }
        return null;
      default:
        return null;
    }
  }

  int _inkAllowance(int p) =>
      1 + _statics().where((e) => e.$2.effect is ExtraInk && e.$3 == p && (e.$2.condition == null || _evalCond(e.$2.condition!, _Ctx(this, controller: p, source: e.$1)))).length;

  int _inkReady(int p) => state.player(p).inkwell.where((id) => !state.obj(id).exerted).length;

  /// Exerts [n] ready ink cards (CR 4.3.2.4).
  void _payInk(int p, int n) {
    if (n <= 0) return;
    if (_inkReady(p) < n) throw LorcanaError('Not enough ink');
    var left = n;
    for (final id in state.player(p).inkwell) {
      if (left == 0) break;
      final o = state.obj(id);
      if (!o.exerted) {
        o.exerted = true;
        left--;
      }
    }
    state.version++;
  }

  // -------------------------------------------------------------------------------------------
  // Ink a card (CR 4.2)
  // -------------------------------------------------------------------------------------------

  void _ink(int p, CardId id) {
    _moveTo(id, Place.inkwell);
    state.player(p).inkedThisTurn++;
    log('${state.player(p).name} puts ${nameOf(id)} into their inkwell.', player: p, card: id, kind: 'ink');
  }

  // -------------------------------------------------------------------------------------------
  // Play a card (CR 4.3)
  // -------------------------------------------------------------------------------------------

  /// The ink cost after payment modifiers (CR 1.5.4, 4.3.6).
  int playCost(int p, CardId id) {
    final c = db[state.obj(id).card]!;
    var cost = c.cost;
    final ctx = _Ctx(this, controller: p, source: id);
    for (final a in LorcanaParser.parse(c).abilities) {
      if (a is Static && a.inHand && a.effect is CostReduction) {
        if (a.condition != null && !_evalCond(a.condition!, ctx)) continue;
        cost -= _evalAmount((a.effect as CostReduction).amount, ctx);
      }
    }
    for (final (src, st, ctl) in _statics()) {
      final e = st.effect;
      if (e is! CostReduction || e.self || ctl != p) continue;
      if (st.condition != null && !_evalCond(st.condition!, _Ctx(this, controller: ctl, source: src))) continue;
      if (!matches(e.filter, id, controller: p, source: src, place: Place.hand)) continue;
      cost -= _evalAmount(e.amount, _Ctx(this, controller: ctl, source: src));
    }
    for (final r in state.reductions) {
      if (r.player == p && matches(r.filter, id, controller: p, place: Place.hand)) {
        cost -= r.n;
        break;
      }
    }
    return cost < 0 ? 0 : cost;
  }

  Keyword? _shiftOf(CardId id) {
    for (final a in LorcanaParser.parse(db[state.obj(id).card]!).abilities) {
      if (a is KeywordAbility && a.keyword.kw == Kw.shift) return a.keyword;
    }
    return null;
  }

  /// Characters [card] can be shifted onto (CR 8.10).
  List<CardId> shiftTargets(int p, CardId card) {
    final k = _shiftOf(card);
    if (k == null) return const [];
    final c = db[state.obj(card).card]!;
    return [
      for (final id in state.player(p).play)
        if (chars(id).type == CardType.character &&
            (k.universalShift || (k.shiftClass != null ? chars(id).classes.any((x) => x.toLowerCase() == k.shiftClass!.toLowerCase()) : db[state.obj(id).card]!.names.any((n) => c.names.contains(n)))))
          id,
    ];
  }

  /// The cost [singer] counts as for singing (Singer N; CR 8.11).
  int _singCost(CardId singer) {
    final c = chars(singer);
    return c.has(Kw.singer) ? c.n(Kw.singer) : c.cost;
  }

  bool _canExertToPay(int p, CardId id) {
    final o = state.obj(id);
    return o.zone == Place.play && o.owner == p && !o.exerted && o.dry && chars(id).type == CardType.character;
  }

  String? _playProblem(PlayMove m) {
    final s = state;
    final p = m.seat;
    final o = s.objOrNull(m.card);
    if (o == null || o.zone != Place.hand || o.owner != p) return 'That card isn’t in your hand';
    final c = db[o.card]!;
    switch (m.mode) {
      case PlayMode.ink:
        if (_inkReady(p) < playCost(p, m.card)) return 'Not enough ink (${playCost(p, m.card)} needed, ${_inkReady(p)} ready)';
        return null;
      case PlayMode.shift:
        final k = _shiftOf(m.card);
        if (k == null) return '${c.name} has no Shift';
        if (m.onto == null || !shiftTargets(p, m.card).contains(m.onto)) return 'Shift onto one of your characters named ${c.name}';
        if (_inkReady(p) < _shiftCost(p, m.card, k)) return 'Not enough ink to shift';
        return null;
      case PlayMode.sing:
        if (!c.isSong) return 'Only songs can be sung';
        if (m.singers.isEmpty) return 'Choose who sings';
        if (m.singers.toSet().length != m.singers.length) return 'Each singer once';
        for (final id in m.singers) {
          if (!_canExertToPay(p, id)) return '${nameOf(id)} can’t sing now (exerted or still drying)';
          if (chars(id).rules.contains(Rule.cantSing)) return '${nameOf(id)} can’t sing';
        }
        if (m.singers.length == 1) {
          if (_singCost(m.singers.first) >= c.cost) return null;
        }
        final together = LorcanaParser.parse(c).abilities.whereType<KeywordAbility>().where((a) => a.keyword.kw == Kw.singTogether).firstOrNull;
        if (together != null && m.singers.fold<int>(0, (a, id) => a + _singCost(id)) >= together.keyword.n) return null;
        return m.singers.length == 1 ? '${nameOf(m.singers.first)} isn’t costly enough to sing ${c.name}' : 'Not enough total cost to sing together';
    }
  }

  int _shiftCost(int p, CardId card, Keyword k) {
    var cost = k.n;
    for (final r in state.reductions) {
      if (r.player == p && matches(r.filter, card, controller: p, place: Place.hand)) {
        cost -= r.n;
        break;
      }
    }
    return cost < 0 ? 0 : cost;
  }

  void _play(PlayMove m) {
    final s = state;
    final p = m.seat;
    final id = m.card;
    final c = db[s.obj(id).card]!;
    // Pay (CR 4.3.2.4); payment modifiers for "the next X" are used up (CR 4.3.6).
    var paid = -1;
    switch (m.mode) {
      case PlayMode.ink:
        paid = playCost(p, id);
        _payInk(p, paid);
      case PlayMode.shift:
        paid = _shiftCost(p, id, _shiftOf(id)!);
        _payInk(p, paid);
      case PlayMode.sing:
        for (final singer in m.singers) {
          _exertCard(singer);
        }
    }
    // "Whenever you pay N ink or less to play a card" (CR 4.3.2.4).
    if (paid >= 0) _emit(_Ev(kind: _EvKind.inkPaid, card: id, player: p, amount: paid));
    final ri = s.reductions.indexWhere((r) => r.player == p && matches(r.filter, id, controller: p, place: Place.hand));
    if (ri >= 0) s.reductions.removeAt(ri);
    _enterPlay(p, id, shiftOnto: m.mode == PlayMode.shift ? m.onto : null, singers: m.singers, how: m.mode);
    if (c.type != CardType.action) return;
  }

  /// A card enters play (CR 4.3.3), or an action resolves and goes to the discard.
  void _enterPlay(int p, CardId id, {CardId? shiftOnto, List<CardId> singers = const [], PlayMode how = PlayMode.ink, bool free = false, bool exerted = false}) {
    final s = state;
    final c = db[s.obj(id).card]!;
    final verb = switch (how) {
      PlayMode.shift => 'shifts',
      PlayMode.sing => 'sings',
      _ => 'plays',
    };
    final by = how == PlayMode.sing ? ' (${singers.map(nameOf).join(' and ')})' : '';
    log('${s.player(p).name} $verb ${c.fullName}$by.', player: p, card: id, kind: how == PlayMode.sing ? 'sing' : (how == PlayMode.shift ? 'shift' : 'play'));
    if (c.type == CardType.action) {
      _moveTo(id, Place.play);
      final n = ++s.player(p).actionsThisTurn;
      _emit(_Ev(kind: _EvKind.played, card: id, player: p, amount: n));
      for (final singer in singers) {
        _emit(_Ev(kind: _EvKind.sings, card: singer, other: id, player: p));
      }
      if (singers.isNotEmpty) {
        _emit(_Ev(kind: _EvKind.songSung, card: id, player: p));
        // Sing Together (CR 8.12): each singer of a song more than one sang.
        if (singers.length > 1) {
          for (final singer in singers) {
            _emit(_Ev(kind: _EvKind.sungTogether, card: singer, other: id, player: p));
          }
        }
      }
      final eff = LorcanaParser.parse(c).abilities.whereType<ActionEffect>().firstOrNull;
      if (eff != null) {
        _resolveEffect(eff.effect, _Ctx(this, controller: p, source: id, isAction: true));
      }
      if (s.obj(id).zone == Place.play) _moveTo(id, Place.discard);
      return;
    }
    if (shiftOnto != null) {
      final under = s.obj(shiftOnto);
      final wasExerted = under.exerted, wasDry = under.dry, damage = under.damage, at = under.at;
      final stack = [shiftOnto, ...under.underCopy()];
      final pl = s.player(p);
      final pos = pl.play.indexOf(shiftOnto);
      _moveTo(id, Place.play);
      pl.play.remove(id);
      pl.play[pos] = id;
      under.under = [];
      final o = s.obj(id);
      o.under = stack;
      o.exerted = wasExerted;
      o.dry = wasDry;
      o.damage = damage;
      o.at = at;
      for (final u in stack) {
        s.obj(u).zone = Place.play;
      }
    } else {
      _moveTo(id, Place.play);
      final o = s.obj(id);
      o.exerted = exerted;
      // Items and locations aren't drying; characters are (CR 5.1.2).
      o.dry = c.type != CardType.character;
    }
    // Enters-play effects (CR 6.7.9) and Bodyguard (CR 8.3.2).
    for (final a in LorcanaParser.parse(c).abilities) {
      if (a is Static && a.effect is EntersWith) {
        final e = a.effect as EntersWith;
        if (e.exerted) s.obj(id).exerted = true;
        s.obj(id).damage += e.damage;
      }
    }
    if (c.type == CardType.character && chars(id).has(Kw.bodyguard) && !s.obj(id).exerted && shiftOnto == null) {
      if (askYesNo(p, 'Bodyguard: have ${c.name} enter play exerted?', source: id)) s.obj(id).exerted = true;
    }
    s.version++;
    _emit(_Ev(kind: _EvKind.played, card: id, player: p, other: shiftOnto));
    // "When you shift a character on top of this one" (CR 8.10.6).
    if (shiftOnto != null) _emit(_Ev(kind: _EvKind.shiftedOnto, card: shiftOnto, other: id, player: p));
  }

  // -------------------------------------------------------------------------------------------
  // Quest (CR 4.5)
  // -------------------------------------------------------------------------------------------

  void _quest(int p, CardId id) {
    _exertCard(id);
    final lore = chars(id).loreAtLeast0;
    log('${state.player(p).name} quests with ${nameOf(id)}.', player: p, card: id, kind: 'quest', amount: lore);
    _gainLore(p, lore, source: id);
    _emit(_Ev(kind: _EvKind.quests, card: id, player: p));
  }

  // -------------------------------------------------------------------------------------------
  // Challenge (CR 4.6)
  // -------------------------------------------------------------------------------------------

  /// What [attacker] could challenge, before limiters.
  /// Exerted opposing characters, and locations (CR 4.6.4); ready ones too for a character that
  /// "can challenge ready characters".
  List<CardId> _challengeTargets(int p, CardId attacker) {
    final ready = state.objOrNull(attacker)?.zone == Place.play && chars(attacker).rules.contains(Rule.canChallengeReady);
    return [
      for (final q in state.opponents(p))
        for (final id in state.player(q).play)
          if (chars(id).type == CardType.location || (chars(id).type == CardType.character && (state.obj(id).exerted || ready))) id,
    ];
  }

  String? _challengeProblem(int p, CardId attacker, CardId target) {
    final s = state;
    final a = s.objOrNull(attacker), d = s.objOrNull(target);
    if (a == null || a.zone != Place.play || a.owner != p) return 'Choose one of your characters';
    if (d == null || d.zone != Place.play || d.owner == p) return 'Choose an opposing character or location';
    final ac = chars(attacker), dc = chars(target);
    if (ac.type != CardType.character) return 'Only characters can challenge';
    if (a.exerted) return '${ac.card.name} is exerted';
    if (!a.dry && !ac.has(Kw.rush)) return '${ac.card.name} is still drying (Rush lets a character challenge right away)';
    if (ac.rules.contains(Rule.cantChallenge)) return '${ac.card.name} can’t challenge';
    if (dc.type == CardType.character) {
      if (!d.exerted && !ac.rules.contains(Rule.canChallengeReady)) return 'Only exerted characters can be challenged';
    } else if (dc.type != CardType.location) {
      return 'Only characters and locations can be challenged';
    }
    if (dc.rules.contains(Rule.cantBeChallenged)) return '${dc.card.name} can’t be challenged';
    // Evasive (CR 8.6) unless Alert (8.2).
    if (dc.has(Kw.evasive) && !ac.has(Kw.evasive) && !ac.has(Kw.alert)) return '${dc.card.name} is Evasive';
    // Bodyguard (CR 8.3.3): if a Bodyguard could be chosen, one must be.
    if (dc.type == CardType.character && !dc.has(Kw.bodyguard)) {
      for (final other in s.player(d.owner).play) {
        final oc = chars(other);
        if (oc.type == CardType.character &&
            oc.has(Kw.bodyguard) &&
            s.obj(other).exerted &&
            !oc.rules.contains(Rule.cantBeChallenged) &&
            (!oc.has(Kw.evasive) || ac.has(Kw.evasive) || ac.has(Kw.alert))) {
          return '${oc.card.name} has Bodyguard: challenge them first';
        }
      }
    }
    return null;
  }

  void _challenge(int p, CardId attacker, CardId target) {
    final s = state;
    _exertCard(attacker);
    log('${nameOf(attacker)} challenges ${nameOf(target)}.', player: p, card: attacker, kind: 'challenge');
    _emit(_Ev(kind: _EvKind.challenges, card: attacker, other: target, player: p));
    _emit(_Ev(kind: _EvKind.isChallenged, card: target, other: attacker, player: s.obj(target).owner));
    _resolveBag();
    if (s.over) return;
    // Challenge Damage step (CR 4.6.6): both deal damage at once; locations deal none.
    final aStill = s.obj(attacker).zone == Place.play, dStill = s.obj(target).zone == Place.play;
    if (aStill && dStill) {
      final ac = chars(attacker), dc = chars(target);
      final toDefender = ac.strengthAtLeast0 + (ac.has(Kw.challenger) ? ac.n(Kw.challenger) : 0);
      final toAttacker = dc.type == CardType.character ? dc.strengthAtLeast0 : 0;
      final noDamageA = ac.rules.contains(Rule.takesNoDamageFromChallenges);
      final noDamageD = dc.rules.contains(Rule.takesNoDamageFromChallenges);
      _dealDamage(target, noDamageD ? 0 : toDefender, source: attacker, challenge: true);
      _dealDamage(attacker, noDamageA ? 0 : toAttacker, source: target, challenge: true);
    }
    _check();
  }

  // -------------------------------------------------------------------------------------------
  // Move a character to a location (CR 4.7)
  // -------------------------------------------------------------------------------------------

  int _moveCost(int p, CardId character, CardId location) {
    final m = db[state.obj(location).card]!.moveCost ?? 0;
    return m < 0 ? 0 : m;
  }

  void _moveCharacter(int p, CardId character, CardId location, {required bool pay}) {
    if (pay) _payInk(p, _moveCost(p, character, location));
    state.obj(character).at = location;
    state.version++;
    log('${nameOf(character)} moves to ${nameOf(location)}.', player: p, card: character, kind: 'move');
    _emit(_Ev(kind: _EvKind.moves, card: character, other: location, player: p));
  }

  // -------------------------------------------------------------------------------------------
  // Activated abilities and Boost (CR 4.4, 8.4)
  // -------------------------------------------------------------------------------------------

  String? _activateProblem(int p, CardId id, int index) {
    final s = state;
    final o = s.objOrNull(id);
    if (o == null || o.zone != Place.play || o.owner != p) return 'That card isn’t yours in play';
    final abs = parsed(id).abilities;
    if (index < 0 || index >= abs.length) return 'No such ability';
    final a = abs[index];
    final c = chars(id);
    if (a is KeywordAbility && a.keyword.kw == Kw.boost) {
      if (o.usedOn[index] == s.turn) return 'Boost once per turn';
      if (s.player(p).deck.isEmpty) return 'No cards in your deck';
      if (_inkReady(p) < a.keyword.n) return 'Not enough ink';
      return null;
    }
    if (a is! Activated) return 'That isn’t an activated ability';
    final cost = a.cost;
    if (cost.exert) {
      if (o.exerted) return '${c.card.name} is exerted';
      if (c.type == CardType.character && !o.dry) return '${c.card.name} is still drying';
    }
    if (_inkReady(p) < cost.ink) return 'Not enough ink';
    if (cost.discard > s.player(p).hand.length) return 'Not enough cards in hand';
    if (cost.exertOther != null &&
        matching(
          cost.exertOther!,
          controller: p,
          source: id,
          whose: Owner.yours,
        ).where((x) => x != id && _canExertToPay(p, x) || (x != id && chars(x).type != CardType.character && !s.obj(x).exerted)).isEmpty) {
      return 'Nothing to exert for the cost';
    }
    if (cost.banishOther != null && matching(cost.banishOther!, controller: p, source: id, whose: Owner.yours).where((x) => x != id).isEmpty) return 'Nothing to banish for the cost';
    return null;
  }

  void _activate(int p, CardId id, int index) {
    final s = state;
    final a = parsed(id).abilities[index];
    final o = s.obj(id);
    if (a is KeywordAbility) {
      // Boost (CR 8.4.1).
      _payInk(p, a.keyword.n);
      o.usedOn[index] = s.turn;
      final top = s.player(p).deck.first;
      _moveTo(top, Place.discard);
      s.player(p).discard.remove(top);
      final t = s.obj(top);
      t.zone = Place.play;
      t.faceDown = true;
      o.under.insert(0, top);
      log('${nameOf(id)} boosts: a card goes facedown under it.', player: p, card: id, kind: 'ability');
      _emit(_Ev(kind: _EvKind.putUnder, card: id, player: p));
      return;
    }
    a as Activated;
    final cost = a.cost;
    final ctx = _Ctx(this, controller: p, source: id);
    if (cost.exert) _exertCard(id);
    _payInk(p, cost.ink);
    if (cost.discard > 0) {
      final pick = ask(
        Decision(
          kind: DecisionKind.cards,
          player: p,
          prompt: 'Discard ${cost.discard} card${cost.discard == 1 ? '' : 's'} for the cost',
          options: List.of(s.player(p).hand),
          min: cost.discard,
          max: cost.discard,
          source: id,
        ),
      );
      _discardCards(p, pick);
    }
    if (cost.exertOther != null) {
      final opts = [
        for (final x in matching(cost.exertOther!, controller: p, source: id, whose: Owner.yours))
          if (x != id && !s.obj(x).exerted && (chars(x).type != CardType.character || s.obj(x).dry)) x,
      ];
      final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Exert one for the cost', options: opts, min: 1, max: 1, source: id));
      _exertCard(pick.first);
    }
    if (cost.banishOther != null) {
      final opts = [
        for (final x in matching(cost.banishOther!, controller: p, source: id, whose: Owner.yours))
          if (x != id) x,
      ];
      final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Banish one for the cost', options: opts, min: 1, max: 1, source: id));
      _banish(pick.first);
    }
    final lki = chars(id);
    if (cost.banishSelf) _banish(id);
    log('${s.player(p).name} uses ${a.text.split(' - ').first.split(':').first} (${lki.card.name}).', player: p, card: id, kind: 'ability');
    _resolveEffect(a.effect, ctx..sourceStrength = lki.strength);
  }
}

extension on Obj {
  List<CardId> underCopy() => List.of(under);
}
