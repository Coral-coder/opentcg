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
        if (!s.obj(card).dry && !c.rules.contains(Rule.canQuestWhileDrying)) return '${c.card.name} is still drying (played this turn)';
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
        if (chars(card).rules.contains(Rule.cantMove)) return '${nameOf(card)} can’t move to locations';
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
    _moveTo(id, Place.inkwell, exerted: _inkEntersExerted(p));
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
    cost += _w1CostDelta(p, id);
    return cost < 0 ? 0 : cost;
  }

  Keyword? _shiftOf(CardId id) {
    for (final a in LorcanaParser.parse(db[state.obj(id).card]!).abilities) {
      if (a is KeywordAbility && a.keyword.kw == Kw.shift) return a.keyword;
    }
    return _w1HandShift(id);
  }

  /// Single cards [card] can be shifted onto (CR 8.10.1, 8.10.8.1–8.10.8.2, 8.10.8.4–8.10.8.6).
  /// Duo Shift only goes onto two cards ([duoShiftTargets]).
  List<CardId> shiftTargets(int p, CardId card) {
    final k = _shiftOf(card);
    if (k == null || k.shiftVariant == ShiftVariant.duo) return const [];
    final c = db[state.obj(card).card]!;
    bool named(CardId id) {
      final under = db[state.obj(id).card]!;
      if (under.names.any((n) => c.names.any((m) => m.toLowerCase() == n.toLowerCase()))) return true;
      // "Also counts as being named X for Shift" / "you can shift any character on top" (CR 8.10.1).
      for (final a in LorcanaParser.parse(under).abilities) {
        if (a is Static && a.effect is ShiftName) {
          final n = (a.effect as ShiftName).name;
          if (n == null || c.names.any((m) => m.toLowerCase() == n)) return true;
        }
      }
      return false;
    }
    return [
      for (final id in state.player(p).play)
        if (k.shiftVariant == ShiftVariant.potato
            ? chars(id).type == CardType.item && db[state.obj(id).card]!.names.any((n) => n.toLowerCase() == 'potato')
            : chars(id).type == CardType.character && (k.universalShift || (k.shiftClass != null ? chars(id).classes.any((x) => x.toLowerCase() == k.shiftClass!.toLowerCase()) : named(id))))
          id,
    ];
  }

  /// Pairs of characters a Duo or Combo Shift card can go on top of: each matches a different
  /// one of its names (CR 8.10.8.3–8.10.8.4).
  List<(CardId, CardId)> duoShiftTargets(int p, CardId card) {
    final k = _shiftOf(card);
    if (k == null || (k.shiftVariant != ShiftVariant.duo && k.shiftVariant != ShiftVariant.combo)) return const [];
    final parts = db[state.obj(card).card]!.names.skip(1).map((n) => n.toLowerCase()).toList();
    if (parts.length < 2) return const [];
    final chars0 = [for (final id in state.player(p).play) if (chars(id).type == CardType.character) id];
    Set<int> which(CardId id) => {for (var i = 0; i < parts.length; i++) if (db[state.obj(id).card]!.names.any((n) => n.toLowerCase() == parts[i])) i};
    final out = <(CardId, CardId)>[];
    for (var i = 0; i < chars0.length; i++) {
      for (var j = i + 1; j < chars0.length; j++) {
        final a = which(chars0[i]), b = which(chars0[j]);
        if (a.any((x) => b.any((y) => y != x))) out.add((chars0[i], chars0[j]));
      }
    }
    return out;
  }

  /// Hand cards that can be discarded to pay a "Shift: Discard …" cost (CR 8.10.1).
  List<CardId> _shiftDiscardOptions(int p, CardId card, ShiftDiscard d) => [
    for (final id in state.player(p).hand)
      if (id != card && (d.types.isEmpty || d.types.contains(db[state.obj(id).card]!.type)) && (!d.song || db[state.obj(id).card]!.isSong)) id,
  ];

  /// The cost [singer] counts as for singing (Singer N; CR 8.11).
  int _singCost(CardId singer) {
    final c = chars(singer);
    return (c.has(Kw.singer) ? c.n(Kw.singer) : c.cost) + _w1SingBonus(singer);
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
    final w1 = _w1PlayProblem(p, m.card);
    if (w1 != null) return w1;
    switch (m.mode) {
      case PlayMode.ink:
        if (_inkReady(p) < playCost(p, m.card) && !_w1CanBanishToPlay(p, m.card)) return 'Not enough ink (${playCost(p, m.card)} needed, ${_inkReady(p)} ready)';
        return null;
      case PlayMode.shift:
        final k = _shiftOf(m.card);
        if (k == null) return '${c.name} has no Shift';
        if (m.onto2 != null || k.shiftVariant == ShiftVariant.duo) {
          final pairs = duoShiftTargets(p, m.card);
          if (m.onto == null || m.onto2 == null || !pairs.any((x) => (x.$1 == m.onto && x.$2 == m.onto2) || (x.$1 == m.onto2 && x.$2 == m.onto))) return 'Shift onto two of your characters, each with one of ${c.name}’s names';
        } else if (m.onto == null || !shiftTargets(p, m.card).contains(m.onto)) {
          return k.shiftVariant == ShiftVariant.potato ? 'Shift onto one of your items named Potato' : 'Shift onto one of your characters named ${c.name}';
        }
        final d = k.shiftDiscard;
        if (d != null) {
          if (_shiftDiscardOptions(p, m.card, d).length < d.count) return 'Not enough cards to discard for Shift';
          return null;
        }
        if (_inkReady(p) < _shiftCost(p, m.card, k, m.onto)) return 'Not enough ink to shift';
        return null;
      case PlayMode.sing:
        if (!c.isSong) return 'Only songs can be sung';
        if (m.singers.isEmpty) return 'Choose who sings';
        if (m.singers.toSet().length != m.singers.length) return 'Each singer once';
        for (final id in m.singers) {
          if (!_canExertToPay(p, id)) return '${nameOf(id)} can’t sing now (exerted or still drying)';
          if (chars(id).rules.contains(Rule.cantSing)) return '${nameOf(id)} can’t sing';
        }
        if (m.singers.length == 1 && !chars(m.singers.first).rules.contains(Rule.singsOnlyTogether)) {
          if (_singCost(m.singers.first) >= c.cost) return null;
        }
        final together = LorcanaParser.parse(c).abilities.whereType<KeywordAbility>().where((a) => a.keyword.kw == Kw.singTogether).firstOrNull;
        if (together != null && m.singers.fold<int>(0, (a, id) => a + _singCost(id)) >= together.keyword.n) return null;
        return m.singers.length == 1 ? '${nameOf(m.singers.first)} isn’t costly enough to sing ${c.name}' : 'Not enough total cost to sing together';
    }
  }

  int _shiftCost(int p, CardId card, Keyword k, [CardId? onto]) {
    var cost = k.n;
    for (final r in state.reductions) {
      if (r.player == p && matches(r.filter, card, controller: p, place: Place.hand)) {
        cost -= r.n;
        break;
      }
    }
    cost -= _w1ShiftDiscount(p, card, onto);
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
        if (_w1PayByBanishing(p, id, paid)) {
          paid = 0;
        } else {
          _payInk(p, paid);
        }
      case PlayMode.shift:
        final k = _shiftOf(id)!;
        final d = k.shiftDiscard;
        if (d != null) {
          final opts = _shiftDiscardOptions(p, id, d);
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Discard ${d.count} card${d.count == 1 ? '' : 's'} to shift', options: opts, min: d.count, max: d.count, source: id));
          for (final x in pick) {
            _moveTo(x, Place.discard);
          }
          paid = 0;
        } else {
          paid = _shiftCost(p, id, k, m.onto);
          _payInk(p, paid);
        }
      case PlayMode.sing:
        for (final singer in m.singers) {
          _exertCard(singer);
        }
    }
    // "Whenever you pay N ink or less to play a card" (CR 4.3.2.4).
    if (paid >= 0) _w1Paid(p, id);
    if (paid >= 0) _emit(_Ev(kind: _EvKind.inkPaid, card: id, player: p, amount: paid));
    final ri = s.reductions.indexWhere((r) => r.player == p && matches(r.filter, id, controller: p, place: Place.hand));
    if (ri >= 0) s.reductions.removeAt(ri);
    _enterPlay(p, id, shiftOnto: m.mode == PlayMode.shift ? m.onto : null, shiftOnto2: m.mode == PlayMode.shift ? m.onto2 : null, singers: m.singers, how: m.mode);
    if (m.mode == PlayMode.shift && _shiftOf(id)?.shiftVariant == ShiftVariant.temporary && s.obj(id).zone == Place.play) s.obj(id).temporaryShift = true;
    if (c.type != CardType.action) return;
  }

  /// A card enters play (CR 4.3.3), or an action resolves and goes to the discard.
  void _enterPlay(int p, CardId id, {CardId? shiftOnto, CardId? shiftOnto2, List<CardId> singers = const [], PlayMode how = PlayMode.ink, bool free = false, bool exerted = false}) {
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
      // On top of a non-character (Potato Shift), the character is dry only if that card has
      // been in play since the start of its player's turn (CR 8.10.4.1, 8.10.8.6).
      final underDry = db[under.card]!.type == CardType.character ? under.dry : under.enteredTurn < s.turn;
      var wasExerted = under.exerted, wasDry = underDry, damage = under.damage;
      final at = under.at;
      final stack = [shiftOnto, ...under.underCopy()];
      final pl = s.player(p);
      final pos = pl.play.indexOf(shiftOnto);
      // Duo and Combo Shift onto two characters: exerted if either was, drying if either was
      // (CR 8.10.4.2); both keep their damage (8.10.6).
      if (shiftOnto2 != null) {
        final second = s.obj(shiftOnto2);
        wasExerted = wasExerted || second.exerted;
        wasDry = wasDry && second.dry;
        damage += second.damage;
        stack.addAll([shiftOnto2, ...second.underCopy()]);
        pl.play.remove(shiftOnto2);
        second.under = [];
        for (final q in s.players) {
          for (final other in q.play) {
            if (s.obj(other).at == shiftOnto2) s.obj(other).at = null;
          }
        }
      }
      _moveTo(id, Place.play);
      pl.play.remove(id);
      pl.play[pl.play.contains(shiftOnto) ? pl.play.indexOf(shiftOnto) : pos] = id;
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
    if (_entersExertedByOpponents(p, id)) s.obj(id).exerted = true;
    for (final a in LorcanaParser.parse(c).abilities) {
      if (a is! Static || a.effect is! MayEnterExerted || s.obj(id).exerted) continue;
      final then = (a.effect as MayEnterExerted).then;
      if (askYesNo(p, then == null ? 'Have ${c.name} enter play exerted?' : '${c.name}: enter play exerted to ${_describeEffect(then)}?', source: id)) {
        s.obj(id).exerted = true;
        if (then != null) _resolveEffect(then, _Ctx(this, controller: p, source: id));
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
    state.player(p).questsThisTurn++;
    _emit(_Ev(kind: _EvKind.quests, card: id, player: p));
  }

  // -------------------------------------------------------------------------------------------
  // Challenge (CR 4.6)
  // -------------------------------------------------------------------------------------------

  /// What [attacker] could challenge, before limiters.
  /// Exerted opposing characters, and locations (CR 4.6.4); ready ones too for a character that
  /// "can challenge ready characters".
  List<CardId> _challengeTargets(int p, CardId attacker) {
    final rules = state.objOrNull(attacker)?.zone == Place.play ? chars(attacker).rules : const <Rule>{};
    return [
      for (final q in state.opponents(p))
        for (final id in state.player(q).play)
          if (chars(id).type == CardType.location || (chars(id).type == CardType.character && (state.obj(id).exerted || _mayChallengeReady(rules, id) || _w1ChallengeReady(attacker, id)))) id,
    ];
  }

  /// "Can challenge ready characters" / "ready damaged characters".
  bool _mayChallengeReady(Set<Rule> rules, CardId target) => rules.contains(Rule.canChallengeReady) || (rules.contains(Rule.canChallengeReadyDamaged) && state.obj(target).damage > 0);

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
      if (!d.exerted && !_mayChallengeReady(ac.rules, target) && !_w1ChallengeReady(attacker, target)) return 'Only exerted characters can be challenged';
    } else if (dc.type != CardType.location) {
      return 'Only characters and locations can be challenged';
    }
    if (dc.rules.contains(Rule.cantBeChallenged)) return '${dc.card.name} can’t be challenged';
    final limited = _challengeLimiter(attacker, target);
    if (limited != null) return limited;
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
      _challengePair = (attacker, target);
      final LChars ac, dc;
      try {
        ac = chars(attacker);
        dc = chars(target);
      } finally {
        _challengePair = null;
      }
      // "Deal damage with their {w} instead of their {s}" (Dale).
      int power(LChars x) => x.rules.contains(Rule.dealsWillpowerInChallenges) ? (x.willpower < 0 ? 0 : x.willpower) : x.strengthAtLeast0;
      final toDefender = power(ac) + (ac.has(Kw.challenger) ? ac.n(Kw.challenger) : 0);
      final toAttacker = dc.type == CardType.character ? power(dc) : 0;
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
    final abs = abilitiesOf(id);
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
    final w1 = _w1ActivateProblem(a, o, index, p);
    if (w1 != null) return w1;
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
    final a = abilitiesOf(id)[index];
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
      _emit(_Ev(kind: _EvKind.boosted, card: id, player: p));
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
    _w1PayActivate(a, p, id, index);
    final lki = chars(id);
    if (cost.banishSelf) _banish(id);
    log('${s.player(p).name} uses ${a.text.split(' - ').first.split(':').first} (${lki.card.name}).', player: p, card: id, kind: 'ability');
    _resolveEffect(a.effect, ctx..sourceStrength = lki.strength);
  }
}

extension GameTemporaryShift on Game {
  /// Temporary Shift (CR 8.10.8.5): at the end of its player's turn, a card played with it that's
  /// still in play has all damage removed and goes back to the hand alone; the card under it
  /// stays in play with the stack's state.
  void _endTemporaryShifts(int p) {
    final s = state;
    for (final id in List.of(s.player(p).play)) {
      final o = s.obj(id);
      if (!o.temporaryShift || o.zone != Place.play) continue;
      o.damage = 0;
      final stack = List.of(o.under);
      final pl = s.player(p);
      final pos = pl.play.indexOf(id);
      final exerted = o.exerted, dry = o.dry, at = o.at;
      o.under = [];
      _moveTo(id, Place.hand);
      if (stack.isNotEmpty) {
        final top = s.obj(stack.first);
        top.under = stack.sublist(1);
        top.zone = Place.play;
        top.faceDown = false;
        top.exerted = exerted;
        top.dry = dry;
        top.at = at;
        top.damage = 0;
        pl.play.insert(pos.clamp(0, pl.play.length), stack.first);
      }
      s.version++;
      log('${nameOf(id)} returns to ${pl.name}’s hand (Temporary Shift).', player: p, card: id, kind: 'return');
    }
  }
}

extension on Obj {
  List<CardId> underCopy() => List.of(under);
}
