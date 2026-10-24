part of 'game.dart';

enum _EvKind { played, quests, challenges, isChallenged, banished, banishedInChallenge, banishesInChallenge, sings, moves, dealtDamage, readied, draw, vanish, putUnder }

class _Ev {
  _Ev({required this.kind, this.card, this.other, this.player, this.amount = 0, this.info, this.cardType});
  final _EvKind kind;
  final CardId? card, other;
  final int? player;
  final int amount;

  /// Last known information for a card that left play (CR 6.7.7).
  final EventInfo? info;
  final CardType? cardType;
}

extension GameBag on Game {
  /// Finds the triggered abilities [e] meets and adds them to the bag (CR 7.7.3), in turn
  /// order and play order so every device adds them alike.
  void _emit(_Ev e) {
    final s = state;
    final info =
        e.info ??
        EventInfo(
          card: e.card,
          other: e.other,
          player: e.player,
          amount: e.amount,
          strength: e.card != null && s.objOrNull(e.card!)?.zone == Place.play ? chars(e.card!).strength : 0,
          location: e.kind == _EvKind.moves ? e.other : null,
        );
    // Vanish (CR 8.14) is a keyword trigger of its own.
    if (e.kind == _EvKind.vanish) {
      _addToBag(e.player!, e.card!, Triggered('Vanish', const CardEvent(Event.banished), const Banish(This())), info, -1);
      return;
    }
    for (final p in _turnOrder()) {
      final pl = s.player(p);
      // Cards in play, plus the card that just left play for its own leaves-play triggers.
      final sources = [...pl.play];
      final leaving = (e.kind == _EvKind.banished || e.kind == _EvKind.banishedInChallenge) && e.card != null && s.obj(e.card!).owner == p ? e.card : null;
      if (leaving != null && !sources.contains(leaving)) sources.add(leaving);
      for (final src in sources) {
        final abs = LorcanaParser.parse(db[s.obj(src).card]!).abilities;
        for (var i = 0; i < abs.length; i++) {
          final a = abs[i];
          if (a is KeywordAbility && a.keyword.kw == Kw.support && e.kind == _EvKind.quests && e.card == src) {
            // Support (CR 8.13): add this character's strength to another chosen character's.
            _addToBag(
              p,
              src,
              Triggered('Support', const CardEvent(Event.quests), May(Modify(Chosen(const Filter(owner: Owner.yours, other: true)), Stat.strength, StatOf(This(), Stat.strength), Lasting.thisTurn))),
              info,
              i,
            );
            continue;
          }
          if (a is! Triggered || a.fromDiscard) continue;
          if (src == leaving && !_isLeavesTrigger(a.trigger)) continue;
          if (src != leaving && s.obj(src).zone != Place.play) continue;
          if (!_triggerMatches(a.trigger, e, src, p)) continue;
          if (a.during != null && !_evalCond(a.during!, _Ctx(this, controller: p, source: src))) continue;
          _addToBag(p, src, a, info, i);
        }
      }
    }
    for (final l in List.of(s.lingering)) {
      if (l.delayedEnd) continue;
      if (_triggerMatches(l.ability.trigger, e, l.source, l.controller, floating: true)) {
        _addToBag(l.controller, l.source, l.ability, info, -1, floating: true);
      }
    }
  }

  bool _isLeavesTrigger(Trigger t) => t is CardEvent && t.subject == null && (t.event == Event.banished || t.event == Event.banishedInChallenge);

  bool _triggerMatches(Trigger t, _Ev e, CardId src, int you, {bool floating = false}) {
    bool subject(Filter? f, CardId? id, {Place place = Place.play}) {
      if (id == null) return false;
      if (f == null) return !floating && id == src;
      final o = state.objOrNull(id);
      if (o == null) return false;
      // Cards that left play are matched as they were (their type and owner).
      if (o.zone != Place.play) {
        final c = db[o.card]!;
        if (!f.types.contains(c.type)) return false;
        if (f.owner == Owner.yours && o.owner != you) return false;
        if (f.owner == Owner.opposing && o.owner == you) return false;
        if (f.other && id == src) return false;
        if (f.classes.isNotEmpty && !f.classes.any(c.hasClass)) return false;
        return true;
      }
      return matches(f, id, controller: you, source: src);
    }

    switch (t) {
      case OnPlay():
        return e.kind == _EvKind.played && e.card == src && !floating;
      case CardPlayed(:final filter, :final by):
        if (e.kind != _EvKind.played) return false;
        final o = state.obj(e.card!);
        if (by == Owner.yours && o.owner != you) return false;
        if (by == Owner.opposing && o.owner == you) return false;
        if (filter.other && e.card == src) return false;
        final c = db[o.card]!;
        if (!filter.types.contains(c.type)) return false;
        if (filter.song == true && !c.isSong) return false;
        if (filter.classes.isNotEmpty && !filter.classes.any(c.hasClass)) return false;
        if (filter.costMax != null && c.cost > filter.costMax!) return false;
        return true;
      case CardEvent(:final event, subject: final f):
        final kind = switch (event) {
          Event.quests => _EvKind.quests,
          Event.challenges => _EvKind.challenges,
          Event.isChallenged => _EvKind.isChallenged,
          Event.banished => null,
          Event.banishedInChallenge => _EvKind.banishedInChallenge,
          Event.banishesInChallenge => _EvKind.banishesInChallenge,
          Event.sings => _EvKind.sings,
          Event.movesToLocation => _EvKind.moves,
          Event.dealtDamage => _EvKind.dealtDamage,
          Event.readied => _EvKind.readied,
          Event.exerted => null,
        };
        if (event == Event.banished) {
          if (e.kind != _EvKind.banished && e.kind != _EvKind.banishedInChallenge) return false;
        } else if (kind == null || e.kind != kind) {
          return false;
        }
        return subject(f, e.card);
      case TurnStep():
        return false;
      case Draws(:final by):
        return e.kind == _EvKind.draw && (by == Owner.yours ? e.player == you : e.player != you);
      case MovedHere():
        return e.kind == _EvKind.moves && e.other == src && !floating;
    }
  }

  void _addToBag(int p, CardId src, Triggered a, EventInfo info, int index, {bool floating = false}) {
    state.bag.add(
      BagItem(id: state.nextBagId++, controller: p, source: src, ability: a, event: info, label: a.text.isEmpty ? nameOf(src) : '${nameOf(src)}: ${a.text}', abilityIndex: index, floating: floating),
    );
    state.version++;
  }

  /// "At the start/end of your turn" abilities and delayed ones (CR 3.2.1.4, 3.4.1.1).
  void _turnTriggers({required bool start}) {
    final s = state;
    final p = s.active;
    for (final q in _turnOrder()) {
      final cards = [...s.player(q).play, if (start) ...s.player(q).discard];
      for (final src in cards) {
        final inDiscard = s.obj(src).zone == Place.discard;
        final abs = LorcanaParser.parse(db[s.obj(src).card]!).abilities;
        for (var i = 0; i < abs.length; i++) {
          final a = abs[i];
          if (a is! Triggered || a.trigger is! TurnStep) continue;
          if (a.fromDiscard != inDiscard) continue;
          final t = a.trigger as TurnStep;
          if (t.start != start) continue;
          if (t.yours && q != p) continue;
          if (a.during != null && !_evalCond(a.during!, _Ctx(this, controller: q, source: src))) continue;
          _addToBag(q, src, a, EventInfo(player: p), i);
        }
      }
    }
    if (!start) {
      for (final l in List.of(s.lingering)) {
        if (l.delayedEnd && l.controller == p) {
          s.lingering.remove(l);
          final info = EventInfo(card: l.remembered.isEmpty ? null : l.remembered.first, player: p);
          _addToBag(p, l.source, Triggered('Delayed', const TurnStep(start: false), _remap(l.ability.effect)), info, -1, floating: true);
        }
      }
    }
  }

  /// A delayed effect refers to its remembered card as the event card.
  Effect _remap(Effect e) => switch (e) {
    Banish(target: Remembered()) => const Banish(EventCard()),
    ReturnToHand(target: Remembered()) => const ReturnToHand(EventCard()),
    _ => e,
  };

  /// Resolves the bag (CR 7.7.4): the active player first, then in turn order; each picks which
  /// of their abilities resolves next; a game state check follows each.
  void _resolveBag() {
    final s = state;
    var guard = 0;
    while (s.bag.isNotEmpty && !s.over && guard++ < 500) {
      final current = s.bagTurn ?? s.active;
      int? who;
      for (final p in _turnOrderFrom(current)) {
        if (s.bag.any((b) => b.controller == p)) {
          who = p;
          break;
        }
      }
      if (who == null) break;
      s.bagTurn = who;
      final mine = [
        for (final b in s.bag)
          if (b.controller == who) b,
      ];
      var item = mine.first;
      if (mine.length > 1 && mine.map((b) => b.label).toSet().length > 1) {
        final i = ask(Decision(kind: DecisionKind.option, player: who, prompt: 'Choose which ability resolves next', labels: [for (final b in mine) b.label])).first;
        item = mine[i];
      }
      s.bag.remove(item);
      _resolveBagItem(item);
      _check();
    }
    s.bagTurn = null;
  }

  void _resolveBagItem(BagItem b) {
    final s = state;
    final a = b.ability;
    final src = s.objOrNull(b.source);
    // "Once per turn" (CR 6.1.13.2): this ability, once.
    if (a.oncePerTurn && b.abilityIndex >= 0 && src != null) {
      if (src.usedOn[b.abilityIndex] == s.turn) return;
    }
    final ctx = _Ctx(this, controller: b.controller, source: b.source, event: b.event);
    if (a.condition != null && !_evalCond(a.condition!, ctx)) return;
    if (a.oncePerTurn && b.abilityIndex >= 0 && src != null) src.usedOn[b.abilityIndex] = s.turn;
    if (a.text.isNotEmpty) log('${b.label.split(' - ').first.split(':').first} resolves.', player: b.controller, card: b.source, kind: 'ability');
    _resolveEffect(a.effect, ctx);
  }
}
