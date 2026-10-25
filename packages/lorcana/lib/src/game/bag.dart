part of 'game.dart';

enum _EvKind {
  played,
  quests,
  challenges,
  isChallenged,
  banished,
  banishedInChallenge,
  banishesInChallenge,
  sings,
  moves,
  dealtDamage,
  readied,
  draw,
  vanish,
  putUnder,
  inked,
  damageRemoved,
  leftPlay,
  returnedToHand,
  songSung,
  sungTogether,
  chosenByOpponent,
  supportChosen,
  inkPaid,
  shiftedOnto,
  discarded,
  discardedCards,
  exerted,
  returnedFromDiscard,
  dealsChallengeDamage,

  /// A card leaves a discard (wave2_s2).
  w2LeftDiscard,
}

/// The event kind each [Happening] waits for.
const _happeningKinds = {
  Happening.inked: _EvKind.inked,
  Happening.damageRemoved: _EvKind.damageRemoved,
  Happening.leftPlay: _EvKind.leftPlay,
  Happening.returnedToHand: _EvKind.returnedToHand,
  Happening.putUnder: _EvKind.putUnder,
  Happening.songSung: _EvKind.songSung,
  Happening.sungTogether: _EvKind.sungTogether,
  Happening.chosenByOpponent: _EvKind.chosenByOpponent,
  Happening.supportChosen: _EvKind.supportChosen,
  Happening.inkPaid: _EvKind.inkPaid,
  Happening.shiftedOnto: _EvKind.shiftedOnto,
  Happening.shifted: _EvKind.played,
  Happening.discarded: _EvKind.discarded,
  Happening.discardedCards: _EvKind.discardedCards,
  Happening.exerted: _EvKind.exerted,
  Happening.returnedFromDiscard: _EvKind.returnedFromDiscard,
  Happening.dealsChallengeDamage: _EvKind.dealsChallengeDamage,
};

/// The choice slot Support's "chosen character" uses, so choosing it can trigger "whenever one
/// of your characters is chosen for Support".
const _supportSlot = 99;

/// Events whose card has left play (or never was in it), yet can trigger that card's own
/// "when this character leaves play", "when you discard this card" abilities (CR 7.4.3).
const _selfOutsidePlay = {_EvKind.leftPlay, _EvKind.returnedToHand, _EvKind.discarded, _EvKind.shiftedOnto};

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
    _trackTurn(e);
    _w2Track(e);
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
      // Cards in play, plus the card that just left play (or was discarded, or shifted onto)
      // for its own triggers about that.
      final sources = [...pl.play];
      final leaving = (e.kind == _EvKind.banished || e.kind == _EvKind.banishedInChallenge || _selfOutsidePlay.contains(e.kind)) && e.card != null && s.obj(e.card!).owner == p ? e.card : null;
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
              Triggered(
                'Support',
                const CardEvent(Event.quests),
                May(Modify(Chosen(const Filter(owner: Owner.yours, other: true), slot: _supportSlot), Stat.strength, StatOf(This(), Stat.strength), Lasting.thisTurn)),
              ),
              info,
              i,
            );
            continue;
          }
          if (a is! Triggered || a.fromDiscard) continue;
          if (src == leaving && !pl.play.contains(src) && !_isLeavesTrigger(a.trigger)) continue;
          if (src != leaving && s.obj(src).zone != Place.play) continue;
          if (!_triggerMatches(a.trigger, e, src, p, info: info)) continue;
          if (a.during != null && !_evalCond(a.during!, _Ctx(this, controller: p, source: src))) continue;
          _addToBag(p, src, a, info, i);
        }
      }
    }
    for (final l in List.of(s.lingering)) {
      if (l.delayedEnd) continue;
      if (_triggerMatches(l.ability.trigger, e, l.source, l.controller, floating: true, info: info)) {
        _addToBag(l.controller, l.source, l.ability, info, -1, floating: true);
      }
    }
    _w2EmitGranted(e, info);
  }

  /// Triggers a card can have about its own leaving play, being discarded or shifted onto,
  /// which it uses from outside play (CR 7.4.3).
  bool _isLeavesTrigger(Trigger t) =>
      (t is CardEvent && t.subject == null && (t.event == Event.banished || t.event == Event.banishedInChallenge)) ||
      (t is On && t.self && const {Happening.leftPlay, Happening.returnedToHand, Happening.discarded, Happening.shiftedOnto}.contains(t.what));

  bool _triggerMatches(Trigger t, _Ev e, CardId src, int you, {bool floating = false, EventInfo? info}) {
    bool subject(Filter? f, CardId? id, {Place place = Place.play}) {
      if (id == null) return false;
      if (f == null) return !floating && id == src;
      final o = state.objOrNull(id);
      if (o == null) return false;
      // Cards that left play are matched as they were (their type and owner).
      if (o.zone != Place.play || !state.player(o.owner).play.contains(id)) {
        final c = db[o.card]!;
        if (!f.types.contains(c.type)) return false;
        if (f.owner == Owner.yours && o.owner != you) return false;
        if (f.owner == Owner.opposing && o.owner == you) return false;
        if (f.other && id == src) return false;
        if (f.classes.isNotEmpty && !f.classes.any(c.hasClass)) return false;
        if (f.named != null && !c.names.any((n) => n.toLowerCase() == f.named!.toLowerCase())) return false;
        if (f.withKw != null && !LorcanaParser.parse(c).abilities.any((a) => a is KeywordAbility && a.keyword.kw == f.withKw)) return false;
        return _w2LeftPlayMatches(f, c);
      }
      return matches(f, id, controller: you, source: src);
    }

    /// Whose event it is, relative to the ability's controller.
    bool byOk(Owner by) => switch (by) {
      Owner.yours => e.player == you,
      Owner.opposing => e.player != null && e.player != you,
      Owner.any => true,
    };

    switch (t) {
      case OnPlay():
        return e.kind == _EvKind.played && e.card == src && !floating;
      case CardPlayed(:final filter, :final by, :final nth):
        if (e.kind != _EvKind.played) return false;
        final o = state.obj(e.card!);
        if (by == Owner.yours && o.owner != you) return false;
        if (by == Owner.opposing && o.owner == you) return false;
        if (filter.other && e.card == src) return false;
        final c = db[o.card]!;
        if (!filter.types.contains(c.type)) return false;
        if (filter.song == true && !c.isSong) return false;
        if (filter.song == false && c.isSong) return false;
        if (filter.classes.isNotEmpty && !filter.classes.any(c.hasClass)) return false;
        if (filter.costMax != null && c.cost > filter.costMax!) return false;
        if (filter.withKw != null && !LorcanaParser.parse(c).abilities.any((a) => a is KeywordAbility && a.keyword.kw == filter.withKw)) return false;
        if (filter.named != null && !c.names.any((n) => n.toLowerCase() == filter.named!.toLowerCase())) return false;
        if (!_w2LeftPlayMatches(filter, c)) return false;
        if ((filter.strengthMin != null || filter.strengthMax != null) && o.zone == Place.play) {
          final st = chars(e.card!).strength;
          if (filter.strengthMin != null && st < filter.strengthMin!) return false;
          if (filter.strengthMax != null && st > filter.strengthMax!) return false;
        }
        if (nth > 0 && e.amount != nth) return false;
        return true;
      case On(:final what, :final self, subject: final f, :final by, :final min, :final max, :final nth):
        if (e.kind != _happeningKinds[what]) return false;
        if (what == Happening.shifted && e.other == null) return false;
        if (self ? (floating || e.card != src) : (f != null && !subject(f, e.card))) return false;
        if (!byOk(by)) return false;
        if (nth > 0 && e.amount != nth) return false;
        if (nth == 0 && min > 0 && e.amount < min) return false;
        if (max != null && e.amount > max) return false;
        return true;
      case CardEvent(:final event, subject: final f, :final other, :final where, :final here):
        if (!_cardEventMatches(event, e)) return false;
        if (!subject(f, e.card)) return false;
        if (other != null && !subject(other, e.other)) return false;
        if (where != null && !subject(where, e.card)) return false;
        if (here) {
          final o = state.objOrNull(e.card!);
          final at = o != null && o.zone == Place.play && state.player(o.owner).play.contains(e.card) ? o.at : info?.location;
          if (at != src) return false;
        }
        return true;
      case TurnStep():
        return false;
      case Draws(:final by, :final nth, :final theirTurn):
        if (e.kind != _EvKind.draw || !(by == Owner.yours ? e.player == you : e.player != you)) return false;
        if (nth > 0 && e.amount != nth) return false;
        if (theirTurn && e.player != state.active) return false;
        return true;
      case MovedHere():
        return e.kind == _EvKind.moves && e.other == src && !floating;
      case W2Trigger():
        return _w2TriggerMatches(t, e, src, you);
    }
  }

  bool _cardEventMatches(Event event, _Ev e) {
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
      Event.exerted => _EvKind.exerted,
    };
    if (event == Event.banished) return e.kind == _EvKind.banished || e.kind == _EvKind.banishedInChallenge;
    return kind != null && e.kind == kind;
  }

  /// Exerts a card in play; "whenever … becomes exerted" triggers (CR 5.1.1.2).
  void _exertCard(CardId id) {
    final o = state.obj(id);
    if (o.exerted) return;
    o.exerted = true;
    state.version++;
    _emit(_Ev(kind: _EvKind.exerted, card: id, player: o.owner));
  }

  /// Discards cards from [p]'s hand: one "whenever you discard a card" event per card, then one
  /// "discards 1 or more cards" event for them all.
  void _discardCards(int p, List<CardId> ids) {
    for (final id in ids) {
      _moveTo(id, Place.discard);
      log('${state.player(p).name} discards ${nameOf(id)}.', player: p, card: id);
    }
    for (final id in ids) {
      _emit(_Ev(kind: _EvKind.discarded, card: id, player: p));
    }
    if (ids.isNotEmpty) _emit(_Ev(kind: _EvKind.discardedCards, player: p, amount: ids.length));
  }

  /// A card is put into [p]'s inkwell (any way; CR 7.5): counts it for "the second card you've
  /// put into your inkwell this turn".
  void _inked(int p, CardId id) {
    final pl = state.player(p);
    pl.inkPutThisTurn++;
    _emit(_Ev(kind: _EvKind.inked, card: id, player: p, amount: pl.inkPutThisTurn));
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
          if (t.opponents && q == p) continue;
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
