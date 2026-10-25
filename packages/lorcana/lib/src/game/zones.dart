part of 'game.dart';

/// Resolving the zone effects of ir_zones.dart: the top of decks, naming a card, hands, the
/// inkwell, discards, cards under others and paying ink as part of an effect (CR 7).
extension GameZones on Game {
  void _resolveZone(ZoneEffect e, _Ctx ctx) {
    switch (e) {
      case Peek():
        _peek(e, ctx);
      case NameCard():
        _nameCard(ctx);
      case RevealHand(:final who, :final discard):
        _revealHand(who, discard, ctx);
      case EachMay():
        _eachMay(e, ctx);
      case InkFromDeck(:final who, :final n, :final exerted):
        for (final p in _players(who, ctx)) {
          final pl = state.player(p);
          var k = 0;
          for (; k < n && pl.deck.isNotEmpty; k++) {
            _moveTo(pl.deck.first, Place.inkwell, exerted: exerted);
          }
          if (k > 0) log('${pl.name} puts $k card${k == 1 ? '' : 's'} from their deck into their inkwell.', player: p, kind: 'ink');
        }
        ctx.didIt = true;
      case ReadyInkwell(:final who):
        for (final p in _players(who, ctx)) {
          for (final id in state.player(p).inkwell) {
            state.obj(id).exerted = false;
          }
          log('${state.player(p).name} readies their inkwell.', player: p, kind: 'ready');
        }
        state.version++;
      case FromDiscard():
        _fromDiscard(e, ctx);
      case PutUnder(:final filter):
        _putUnder(filter, ctx);
      case UnderTo(:final target, :final dest, :final random):
        for (final id in _resolveTargets(target, ctx)) {
          final o = state.obj(id);
          final cards = List.of(o.under);
          if (cards.isEmpty) continue;
          o.under = [];
          if (random) state.rng.shuffle(cards);
          for (final u in cards) {
            state.obj(u).zone = Place.play;
            _send(u, dest, state.obj(u).owner, ctx);
          }
          log('The cards under ${nameOf(id)} go to ${dest == ZoneDest.hand ? 'the hand' : 'the bottom of the deck'}.', player: ctx.controller, card: id);
        }
        state.version++;
      case PayInk(:final n):
        if (_inkReady(ctx.controller) >= n) {
          _payInk(ctx.controller, n);
          log('${state.player(ctx.controller).name} pays $n ink.', player: ctx.controller, kind: 'ink');
          ctx.didIt = true;
        } else {
          ctx.didIt = false;
        }
      case DrawToMatch(:final who):
        final target = _players(who, ctx).fold<int>(0, (m, p) => state.player(p).hand.length > m ? state.player(p).hand.length : m);
        final pl = state.player(ctx.controller);
        while (pl.hand.length < target && _draw(ctx.controller)) {}
        ctx.didIt = true;
    }
  }

  bool _evalZoneCond(ZoneCond c, _Ctx ctx) {
    switch (c) {
      case CompareZone(:final who, :final place, :final cmp):
        int count(int p) => state.player(p).zone(place).length;
        final mine = count(ctx.controller);
        return _players(who, ctx).any((p) => switch (cmp) {
          Cmp.gt => count(p) > mine,
          Cmp.ge => count(p) >= mine,
          Cmp.lt => count(p) < mine,
          Cmp.le => count(p) <= mine,
          Cmp.eq => count(p) == mine,
        });
      case HasUnder():
        final o = state.objOrNull(ctx.source);
        return o != null && o.zone == Place.play && o.under.isNotEmpty;
    }
  }

  /// "Chosen player" and "the challenging player" (see [Who]).
  List<int> _zonePlayers(Who w, _Ctx ctx) {
    switch (w) {
      case Who.chosenPlayer:
        final all = [
          for (final q in _turnOrder())
            if (!state.player(q).lost) q,
        ];
        if (all.length <= 1) return all;
        return [ctx.chosenPlayer ??= all[ask(Decision(kind: DecisionKind.option, player: ctx.controller, prompt: 'Choose a player', labels: [for (final q in all) state.player(q).name], source: ctx.source)).first]];
      case Who.challenger:
        final ev = ctx.event;
        final other = ev?.other;
        if (other != null && state.objOrNull(other) != null) return [state.obj(other).owner];
        return const [];
      default:
        return const [];
    }
  }

  // -------------------------------------------------------------------------------------------
  // Looking at and revealing the top of a deck
  // -------------------------------------------------------------------------------------------

  void _peek(Peek e, _Ctx ctx) {
    var took = false;
    for (final p in _players(e.who, ctx)) {
      final pl = state.player(p);
      final seen = pl.deck.take(e.n).toList();
      if (seen.isEmpty) continue;
      final decider = e.ownerDecides ? p : ctx.controller;
      if (e.reveal) log('${pl.name} reveals ${seen.map(nameOf).join(', ')}.', player: p, card: seen.first);
      final left = List.of(seen);
      for (final pick in e.picks) {
        final cands = [
          for (final id in left)
            if (_pickMatches(pick, id, ctx)) id,
        ];
        if (cands.isEmpty) continue;
        final max = pick.anyNumber ? cands.length : (pick.count < cands.length ? pick.count : cands.length);
        final min = pick.optional ? 0 : max;
        final chosen = ask(Decision(kind: DecisionKind.cards, player: decider, prompt: _pickPrompt(pick, max), options: cands, min: min, max: max, source: ctx.source));
        if (chosen.isEmpty) continue;
        // To the top in the chosen order (the first chosen ends on top).
        for (final id in pick.dest == ZoneDest.top ? chosen.reversed : chosen) {
          left.remove(id);
          _send(id, pick.dest, p, ctx, exerted: pick.exerted);
        }
        took = true;
        if (pick.then != null) _resolveEffect(pick.then!, ctx);
      }
      _placeRest(left, e.rest, p, decider, ctx);
    }
    ctx.didIt = took;
  }

  bool _pickMatches(PeekPick pick, CardId id, _Ctx ctx) {
    if (pick.named) {
      final named = ctx.named;
      return named != null && db[state.obj(id).card]!.names.any((n) => n.toLowerCase() == named.toLowerCase());
    }
    if (pick.filters.isEmpty) return true;
    final place = state.obj(id).zone;
    return pick.filters.any((f) => _zoneMatches(f, id, ctx, place));
  }

  /// [matches] for cards outside play, where keywords come from the printed card.
  bool _zoneMatches(Filter f, CardId id, _Ctx ctx, Place place) {
    if (!matches(f, id, controller: ctx.controller, source: ctx.source, place: place)) return false;
    if (place != Place.play && f.withKw != null) {
      return LorcanaParser.parse(db[state.obj(id).card]!).abilities.any((a) => a is KeywordAbility && a.keyword.kw == f.withKw);
    }
    return true;
  }

  String _pickPrompt(PeekPick pick, int max) {
    final where = switch (pick.dest) {
      ZoneDest.hand => 'into your hand',
      ZoneDest.top => 'on the top of the deck',
      ZoneDest.bottom => 'on the bottom of the deck',
      ZoneDest.inkwell => 'into your inkwell',
      ZoneDest.discard => 'into your discard',
      ZoneDest.play => 'to play for free',
      _ => '',
    };
    return '${pick.optional ? 'Choose up to' : 'Choose'} $max $where';
  }

  /// Puts the cards not taken where they go: the bottom or top in an order the player picks, a
  /// choice of top or bottom, the discard or the inkwell.
  void _placeRest(List<CardId> rest, ZoneDest dest, int owner, int decider, _Ctx ctx) {
    if (rest.isEmpty) return;
    final deck = state.player(owner).deck;
    switch (dest) {
      case ZoneDest.top || ZoneDest.bottom:
        final order = rest.length < 2
            ? rest
            : ask(Decision(kind: DecisionKind.order, player: decider, prompt: 'Order them for the ${dest == ZoneDest.top ? 'top' : 'bottom'} of the deck (first = ${dest == ZoneDest.top ? 'top' : 'highest'})', options: rest, source: ctx.source));
        for (final id in order) {
          deck.remove(id);
        }
        if (dest == ZoneDest.top) {
          deck.insertAll(0, order);
        } else {
          deck.addAll(order);
        }
        state.version++;
      case ZoneDest.topOrBottom:
        for (final id in rest) {
          final bottom = ask(Decision(kind: DecisionKind.option, player: decider, prompt: 'Put ${nameOf(id)} on the top or the bottom of the deck?', labels: const ['Top', 'Bottom'], source: ctx.source)).first == 1;
          deck.remove(id);
          if (bottom) {
            deck.add(id);
          } else {
            deck.insert(0, id);
          }
        }
        state.version++;
      case ZoneDest.topOrDiscard:
        for (final id in rest) {
          final discard = ask(Decision(kind: DecisionKind.option, player: decider, prompt: 'Put ${nameOf(id)} on the top of the deck or into the discard?', labels: const ['Top', 'Discard'], source: ctx.source)).first == 1;
          _send(id, discard ? ZoneDest.discard : ZoneDest.top, owner, ctx);
        }
      default:
        for (final id in rest) {
          _send(id, dest, owner, ctx);
        }
    }
  }

  /// Moves one card to [dest] (from the deck, a discard or from under a card).
  void _send(CardId id, ZoneDest dest, int owner, _Ctx ctx, {bool exerted = false}) {
    final pl = state.player(owner);
    switch (dest) {
      case ZoneDest.hand:
        _moveTo(id, Place.hand);
        log('${pl.name} puts ${nameOf(id)} into their hand.', player: owner, card: id, kind: 'draw');
      case ZoneDest.inkwell:
        _moveTo(id, Place.inkwell, exerted: exerted);
        log('${pl.name} puts a card into their inkwell.', player: owner, card: id, kind: 'ink');
      case ZoneDest.discard || ZoneDest.topOrDiscard:
        _moveTo(id, Place.discard);
      case ZoneDest.play:
        _enterPlay(owner, id, free: true, exerted: exerted);
      case ZoneDest.top:
        if (state.obj(id).zone == Place.deck) {
          pl.deck.remove(id);
          pl.deck.insert(0, id);
          state.version++;
        } else {
          _moveTo(id, Place.deck);
        }
      case ZoneDest.bottom || ZoneDest.topOrBottom:
        if (state.obj(id).zone == Place.deck) {
          pl.deck.remove(id);
          pl.deck.add(id);
          state.version++;
        } else {
          _moveTo(id, Place.deck, bottom: true);
        }
      case ZoneDest.shuffle:
        _moveTo(id, Place.deck);
    }
  }

  // -------------------------------------------------------------------------------------------
  // Naming, hands, players deciding
  // -------------------------------------------------------------------------------------------

  /// Names a card; "the named card" later refers back to it (CR 6.1.11). The choices are the names among the controller's own cards: a
  /// name outside them can't matter to "the named card" on their deck or discard.
  void _nameCard(_Ctx ctx) {
    final p = ctx.controller;
    final pl = state.player(p);
    final names = <String>{
      for (final id in [...pl.deck, ...pl.hand, ...pl.discard, ...pl.play]) db[state.obj(id).card]!.name,
    }.toList()
      ..sortStable((a, b) => a.compareTo(b));
    if (names.isEmpty) return;
    final i = ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Name a card', labels: names, source: ctx.source)).first;
    ctx.named = names[i];
    log('${pl.name} names ${names[i]}.', player: p);
  }

  void _revealHand(Who who, Filter? discard, _Ctx ctx) {
    for (final p in _players(who, ctx)) {
      final pl = state.player(p);
      log(pl.hand.isEmpty ? '${pl.name} reveals an empty hand.' : '${pl.name} reveals their hand: ${pl.hand.map(nameOf).join(', ')}.', player: p);
      if (discard == null) continue;
      final cands = [
        for (final id in pl.hand)
          if (_zoneMatches(discard, id, ctx, Place.hand)) id,
      ];
      if (cands.isEmpty) continue;
      final pick = ask(Decision(kind: DecisionKind.cards, player: ctx.controller, prompt: 'Choose a card for ${pl.name} to discard', options: cands, min: 1, max: 1, source: ctx.source));
      for (final id in pick) {
        _moveTo(id, Place.discard);
        log('${pl.name} discards ${nameOf(id)}.', player: p, card: id);
      }
    }
  }

  /// Each player decides for themselves (CR 6.1.4); the effect is theirs.
  void _eachMay(EachMay e, _Ctx ctx) {
    var refusals = 0;
    for (final p in _players(e.who, ctx)) {
      final inner = e.effect;
      // Can't discard from an empty hand: that's not doing it.
      if (inner is Discard && state.player(p).hand.isEmpty) {
        refusals++;
        continue;
      }
      final sub = _Ctx(this, controller: p, source: ctx.source, event: ctx.event);
      if (askYesNo(p, 'Do you want to: ${_describeEffect(inner)}?', source: ctx.source)) {
        _resolveEffect(inner, sub);
      } else {
        refusals++;
      }
    }
    if (e.lorePerRefusal > 0 && refusals > 0) _gainLore(ctx.controller, refusals * e.lorePerRefusal, source: ctx.source);
  }

  // -------------------------------------------------------------------------------------------
  // Discards and cards under others
  // -------------------------------------------------------------------------------------------

  void _fromDiscard(FromDiscard e, _Ctx ctx) {
    var moved = false;
    for (final p in _players(e.who, ctx)) {
      final pl = state.player(p);
      final cands = [
        for (final id in pl.discard)
          if (_zoneMatches(e.filter, id, ctx, Place.discard) && (!e.named || (ctx.named != null && db[state.obj(id).card]!.names.any((n) => n.toLowerCase() == ctx.named!.toLowerCase())))) id,
      ];
      if (cands.isEmpty) continue;
      List<CardId> pick;
      if (e.all) {
        pick = cands;
      } else {
        final max = e.count < cands.length ? e.count : cands.length;
        pick = ask(Decision(kind: DecisionKind.cards, player: ctx.controller, prompt: 'Choose ${e.upTo ? 'up to ' : ''}$max from ${p == ctx.controller ? 'your' : '${pl.name}\'s'} discard', options: cands, min: e.upTo ? 0 : max, max: max, source: ctx.source));
      }
      if (pick.isEmpty) continue;
      if (e.dest == ZoneDest.bottom && pick.length > 1) {
        pick = ask(Decision(kind: DecisionKind.order, player: ctx.controller, prompt: 'Order them for the bottom of the deck', options: pick, source: ctx.source));
      }
      for (final id in pick) {
        _send(id, e.dest, p, ctx, exerted: e.exerted);
      }
      if (e.dest == ZoneDest.shuffle) state.rng.shuffle(pl.deck);
      log('${pl.name} moves ${pick.length} card${pick.length == 1 ? '' : 's'} from their discard.', player: p);
      moved = true;
    }
    ctx.didIt = moved;
  }

  /// "Put the top card of your deck facedown under one of your characters or locations with
  /// Boost" (CR 8.4.2).
  void _putUnder(Filter f, _Ctx ctx) {
    final p = ctx.controller;
    final pl = state.player(p);
    if (pl.deck.isEmpty) return;
    final cands = matching(f, controller: p, source: ctx.source);
    if (cands.isEmpty) return;
    final host = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose one to put the card under', options: cands, min: 1, max: 1, source: ctx.source)).first;
    final top = pl.deck.first;
    _moveTo(top, Place.discard);
    pl.discard.remove(top);
    final t = state.obj(top);
    t.zone = Place.play;
    t.faceDown = true;
    state.obj(host).under.insert(0, top);
    state.version++;
    log('A card goes facedown under ${nameOf(host)}.', player: p, card: host, kind: 'ability');
    _emit(_Ev(kind: _EvKind.putUnder, card: host, player: p));
    ctx.didIt = true;
  }
}
