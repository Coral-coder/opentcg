part of 'game.dart';

/// Wave 2, slice 4 (Scrooge … Zipper): resolving the effects, amounts, conditions, statics and
/// triggers of ir_wave2_s4.dart, and the turn-action hooks they need (playing from the discard
/// or from under a card, alternate costs, granted activated abilities, free moves).
extension GameS4 on Game {
  /// `usedOn` keys on a card: when a card was last put under it (key 901); 900 + ability index
  /// holds "twice a turn" counts as turn * 100 + count.
  static const _putUnderKey = 901;

  static bool _classBusy = false;
  static final Map<String, bool> _hasS4Static = {};

  // -------------------------------------------------------------------------------------------
  // Effects
  // -------------------------------------------------------------------------------------------

  void _resolveS4(S4Effect e, _Ctx ctx) {
    final s = state;
    final p = ctx.controller;
    final pl = s.player(p);
    switch (e) {
      case PutUnderEach(:final filter, :final slot):
        final got = <CardId>[];
        for (final host in matching(filter, controller: p, source: ctx.source)) {
          if (pl.deck.isEmpty) break;
          _s4PutUnder(pl.deck.first, host, faceDown: true, by: p);
          got.add(host);
        }
        if (got.isNotEmpty) log('${pl.name} puts a card under each of ${got.length} characters.', player: p, card: ctx.source, kind: 'ability');
        ctx.slots[slot] = got;
        ctx.didIt = got.isNotEmpty;
      case DiscardMost(:final n):
        final live = [
          for (final q in _turnOrder())
            if (!s.player(q).lost) q,
        ];
        final most = live.fold<int>(0, (m, q) => s.player(q).hand.length > m ? s.player(q).hand.length : m);
        if (most == 0) return;
        for (final q in live) {
          final hand = s.player(q).hand;
          if (hand.length != most) continue;
          final k = n < hand.length ? n : hand.length;
          _discardCards(q, ask(Decision(kind: DecisionKind.cards, player: q, prompt: 'Choose $k card${k == 1 ? '' : 's'} to discard', options: List.of(hand), min: k, max: k, source: ctx.source)));
        }
      case RevealRepeat(:final filters):
        for (var guard = 0; guard < 200 && pl.deck.isNotEmpty; guard++) {
          final top = pl.deck.first;
          log('${pl.name} reveals ${nameOf(top)}.', player: p, card: top);
          if (filters.any((f) => _zoneMatches(f, top, ctx, Place.deck))) {
            _send(top, ZoneDest.hand, p, ctx);
            continue;
          }
          _placeRest([top], ZoneDest.topOrBottom, p, p, ctx);
          break;
        }
      case UnlessPays(:final payerOf, :final ink, :final effect):
        final ev = ctx.event;
        final card = payerOf is EventCard ? (payerOf.other ? ev?.other : ev?.card) : null;
        final payer = card != null && s.objOrNull(card) != null ? s.obj(card).owner : null;
        if (payer != null && _inkReady(payer) >= ink && askYesNo(payer, 'Pay $ink ink to stop ${nameOf(ctx.source)}’s effect?', source: ctx.source)) {
          _payInk(payer, ink);
          log('${s.player(payer).name} pays $ink ink.', player: payer, kind: 'ink');
          return;
        }
        _resolveEffect(effect, ctx);
      case DiscardMatching(:final filters, :final inkable):
        final cands = [
          for (final id in pl.hand)
            if (inkable ? db[s.obj(id).card]!.inkable : filters.any((f) => _zoneMatches(f, id, ctx, Place.hand))) id,
        ];
        if (cands.isEmpty) {
          ctx.didIt = false;
          return;
        }
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose a card to discard', options: cands, min: 1, max: 1, source: ctx.source));
        ctx.s4['discardedLore'] = db[s.obj(pick.first).card]!.lore ?? 0;
        _discardCards(p, pick);
        ctx.didIt = true;
      case PlaySelfFree(:final exerted):
        final o = s.objOrNull(ctx.source);
        if (o == null || o.owner != p || (o.zone != Place.discard && o.zone != Place.hand)) {
          ctx.didIt = false;
          return;
        }
        _enterPlay(p, ctx.source, free: true, exerted: exerted);
        ctx.didIt = true;
      case PlayUnderFromDiscard():
        final cands = [
          for (final id in ctx.event?.under ?? const <CardId>[])
            if (s.objOrNull(id)?.zone == Place.discard && s.obj(id).owner == p && db[s.obj(id).card]!.type == CardType.character) id,
        ];
        if (cands.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Play any of them for free', options: cands, min: 0, max: cands.length, source: ctx.source));
        for (final id in pick) {
          if (s.obj(id).zone == Place.discard) _enterPlay(p, id, free: true);
        }
      case ExertInkwell():
        for (final id in pl.inkwell) {
          s.obj(id).exerted = true;
        }
        s.version++;
        log('${pl.name} exerts their inkwell.', player: p, kind: 'exert');
        ctx.didIt = true;
      case ChooseNow(:final target):
        final ids = _resolveTargets(target, ctx);
        ctx.s4['under'] = ids.isEmpty ? 0 : s.obj(ids.first).under.length;
      case PlayOrShiftFree(:final filter):
        final cands = matching(filter, controller: p, source: ctx.source, place: Place.hand, whose: Owner.yours);
        if (cands.isEmpty) return;
        final card = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Play or shift one for free', options: cands, min: 1, max: 1, source: ctx.source)).first;
        final ontos = shiftTargets(p, card);
        var onto = -1;
        if (ontos.isNotEmpty) {
          final i = ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Play ${nameOf(card)} or shift it?', labels: ['Play it', for (final x in ontos) 'Shift onto ${nameOf(x)}'], source: ctx.source)).first;
          if (i > 0) onto = ontos[i - 1];
        }
        if (onto < 0) {
          _enterPlay(p, card, free: true);
        } else {
          _enterPlay(p, card, free: true, shiftOnto: onto, how: PlayMode.shift);
          if (_shiftOf(card)?.shiftVariant == ShiftVariant.temporary && s.obj(card).zone == Place.play) s.obj(card).temporaryShift = true;
        }
        ctx.didIt = true;
      case SearchDeck(:final filters):
        final cands = [
          for (final id in pl.deck)
            if (filters.any((f) => _zoneMatches(f, id, ctx, Place.deck))) id,
        ];
        if (cands.isNotEmpty) {
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Search your deck: choose one', options: cands, min: 1, max: 1, source: ctx.source)).first;
          log('${pl.name} reveals ${nameOf(pick)}.', player: p, card: pick);
          _send(pick, ZoneDest.hand, p, ctx);
        }
        s.rng.shuffle(pl.deck);
        s.version++;
        ctx.didIt = cands.isNotEmpty;
      case PeekSplit(:final n):
        final seen = pl.deck.take(n).toList();
        if (seen.isEmpty) return;
        final bottom = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose any number to put on the bottom of your deck', options: seen, min: 0, max: seen.length, source: ctx.source));
        var top = [
          for (final id in seen)
            if (!bottom.contains(id)) id,
        ];
        var low = List.of(bottom);
        if (top.length > 1) top = ask(Decision(kind: DecisionKind.order, player: p, prompt: 'Order them for the top of the deck (first = top)', options: top, source: ctx.source));
        if (low.length > 1) low = ask(Decision(kind: DecisionKind.order, player: p, prompt: 'Order them for the bottom of the deck (first = highest)', options: low, source: ctx.source));
        for (final id in seen) {
          pl.deck.remove(id);
        }
        pl.deck.insertAll(0, top);
        pl.deck.addAll(low);
        s.version++;
      case ScatterThree():
        final opp = _players(Who.chosenOpponent, ctx).firstOrNull;
        if (opp == null) return;
        final mine = [
          for (final id in s.player(opp).play)
            if (chars(id).type == CardType.character) id,
        ];
        if (mine.isEmpty) return;
        final k = mine.length < 3 ? mine.length : 3;
        var left = ask(Decision(kind: DecisionKind.cards, player: opp, prompt: 'Choose $k of your characters', options: mine, min: k, max: k, source: ctx.source));
        final dests = <(CardId, String)>[];
        for (final where in const ['hand', 'bottom', 'top']) {
          if (left.isEmpty) break;
          final id = left.length == 1
              ? left.first
              : ask(Decision(kind: DecisionKind.cards, player: opp, prompt: where == 'hand' ? 'Choose one to return to your hand' : 'Choose one to put on the $where of your deck', options: left, min: 1, max: 1, source: ctx.source)).first;
          dests.add((id, where));
          left = [
            for (final x in left)
              if (x != id) x,
          ];
        }
        for (final (id, where) in dests) {
          if (s.obj(id).zone != Place.play) continue;
          log('${nameOf(id)} goes to ${s.player(opp).name}’s ${where == 'hand' ? 'hand' : '$where of their deck'}.', card: id, kind: 'return');
          if (where == 'hand') {
            _leavePlay(id, Place.hand);
            _emit(_Ev(kind: _EvKind.returnedToHand, card: id, player: opp));
          } else {
            _leavePlay(id, Place.deck, bottom: where == 'bottom');
          }
        }
      case DrawThenDiscardRandom(:final who, :final draw, :final discard):
        final ps = _players(who, ctx);
        for (final q in ps) {
          for (var i = 0; i < draw; i++) {
            _draw(q);
          }
        }
        var actions = 0;
        for (final q in ps) {
          final copy = List.of(s.player(q).hand);
          final pick = <CardId>[];
          for (var i = 0; i < discard && copy.isNotEmpty; i++) {
            pick.add(copy.removeAt(s.rng.nextInt(copy.length)));
          }
          actions += pick.where((id) => db[s.obj(id).card]!.type == CardType.action).length;
          _discardCards(q, pick);
        }
        ctx.s4['actions'] = (ctx.s4['actions'] ?? 0) + actions;
      case PeekItemOrPlay(:final n, :final costMax):
        final seen = pl.deck.take(n).toList();
        if (seen.isEmpty) return;
        final left = List.of(seen);
        final items = [
          for (final id in seen)
            if (db[s.obj(id).card]!.type == CardType.item) id,
        ];
        if (items.isNotEmpty) {
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'You may reveal an item card and put it into your hand', options: items, min: 0, max: 1, source: ctx.source));
          if (pick.isNotEmpty) {
            final id = pick.first;
            left.remove(id);
            log('${pl.name} reveals ${nameOf(id)}.', player: p, card: id);
            final cheap = db[s.obj(id).card]!.cost <= costMax;
            if (cheap && ask(Decision(kind: DecisionKind.option, player: p, prompt: '${nameOf(id)}: put it into your hand or play it for free (exerted)?', labels: const ['Put it into your hand', 'Play it for free, exerted'], source: ctx.source)).first == 1) {
              _enterPlay(p, id, free: true, exerted: true);
            } else {
              _send(id, ZoneDest.hand, p, ctx);
            }
          }
        }
        _placeRest(left, ZoneDest.bottom, p, p, ctx);
      case DiscardToBottomForLore(:final n, :final lore, :final cls, :final loreIf):
        final opp = _players(Who.chosenOpponent, ctx).firstOrNull;
        if (opp == null) return;
        final cands = List.of(s.player(opp).discard);
        if (cands.isEmpty) return;
        final k = n < cands.length ? n : cands.length;
        var pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose $k cards from ${s.player(opp).name}’s discard', options: cands, min: k, max: k, source: ctx.source));
        if (pick.length > 1) pick = ask(Decision(kind: DecisionKind.order, player: p, prompt: 'Order them for the bottom of the deck', options: pick, source: ctx.source));
        final princess = pick.any((id) => db[s.obj(id).card]!.hasClass(cls));
        for (final id in pick) {
          _moveTo(id, Place.deck, bottom: true);
        }
        log('${pl.name} puts ${pick.length} cards from ${s.player(opp).name}’s discard on the bottom of their deck.', player: p);
        // CR 6.1.5.1: "[A] to [B]" needs all of [A].
        if (pick.length == n) _gainLore(p, princess ? loreIf : lore, source: ctx.source);
      case MayDrawUpTo(:final amount):
        final n = _evalAmount(amount, ctx);
        if (n <= 0) return;
        final labels = [for (var k = n; k >= 0; k--) 'Draw $k'];
        final drawn = n - ask(Decision(kind: DecisionKind.option, player: p, prompt: 'How many cards to draw?', labels: labels, source: ctx.source)).first;
        for (var i = 0; i < drawn; i++) {
          _draw(p);
        }
      case LoseLoreCounted(:final who, :final amount):
        var lost = 0;
        for (final q in _players(who, ctx)) {
          final before = s.player(q).lore;
          _loseLore(q, _evalAmount(amount, ctx));
          lost += before - s.player(q).lore;
        }
        ctx.s4['lost'] = lost;
      case GrantAbilityFor(:final target, :final duration):
        final ids = _resolveTargets(target, ctx);
        if (ids.isEmpty) return;
        s.timed.add(Timed(ts: s.nextTs++, controller: p, source: ctx.source, lasting: duration, turn: s.turn, cards: ids, label: 's4grant'));
        s.version++;
      case GrantWhileInPlay(:final target, :final keyword):
        final src = s.objOrNull(ctx.source);
        if (src == null || src.zone != Place.play) return;
        for (final id in _resolveTargets(target, ctx)) {
          s.timed.add(Timed(ts: s.nextTs++, controller: p, source: ctx.source, lasting: Lasting.permanent, turn: s.turn, cards: [id], keyword: keyword, label: 's4while:${src.zcc}:${s.obj(id).zcc}'));
        }
        s.version++;
      case MoveToAnotherLocation(:final character):
        final ids = _resolveTargets(character, ctx);
        if (ids.isEmpty) return;
        final who = ids.first;
        final owner = s.obj(who).owner;
        final locs = [
          for (final id in s.player(owner).play)
            if (chars(id).type == CardType.location && id != s.obj(who).at) id,
        ];
        if (locs.isEmpty) return;
        final loc = locs.length == 1 ? locs.first : ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose another location', options: locs, min: 1, max: 1, source: ctx.source)).first;
        _moveCharacter(owner, who, loc, pay: false);
        ctx.didIt = true;
      case ReplaySong():
        final song = ctx.event?.other;
        if (song == null || s.objOrNull(song)?.zone != Place.discard || s.obj(song).owner != p) return;
        _s4PlayActionFree(p, song, ctx);
      case PlayFreeUpToCostOf(:final filter, :final costOf):
        final ref = _resolveTargets(costOf, ctx, choose: false);
        if (ref.isEmpty) return;
        final max = db[s.obj(ref.first).card]!.cost;
        final cands = matching(filter.copyWith(costMax: max), controller: p, source: ctx.source, place: Place.hand, whose: Owner.yours);
        if (cands.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Play one for free', options: cands, min: 1, max: 1, source: ctx.source));
        _enterPlay(p, pick.first, free: true);
        ctx.didIt = true;
      case EachMayElse(:final who, :final effect, :final perRefusal):
        var refusals = 0;
        for (final q in _players(who, ctx)) {
          if (effect is Discard && s.player(q).hand.isEmpty) {
            refusals++;
            continue;
          }
          if (askYesNo(q, 'Do you want to: ${_describeEffect(effect)}?', source: ctx.source)) {
            _resolveEffect(effect, _Ctx(this, controller: q, source: ctx.source, event: ctx.event));
          } else {
            refusals++;
          }
        }
        for (var i = 0; i < refusals; i++) {
          _resolveEffect(perRefusal, ctx);
        }
      case PlaySameNameFree(:final slot):
        final names = {
          for (final id in ctx.slots[slot] ?? const <CardId>[]) ...db[s.obj(id).card]!.names.map((x) => x.toLowerCase()),
        };
        final cands = [
          for (final id in pl.hand)
            if (db[s.obj(id).card]!.type == CardType.character && db[s.obj(id).card]!.names.any((x) => names.contains(x.toLowerCase()))) id,
        ];
        if (cands.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Play one for free', options: cands, min: 1, max: 1, source: ctx.source));
        _enterPlay(p, pick.first, free: true);
        ctx.didIt = true;
      case UnderToInkwell():
        final hosts = [
          for (final id in pl.play)
            if (const {CardType.character, CardType.location}.contains(chars(id).type)) id,
        ];
        final cands = [for (final h in hosts) ...s.obj(h).under];
        if (cands.isEmpty) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose any number of cards from under your characters and locations', options: cands, min: 0, max: cands.length, source: ctx.source));
        for (final id in pick) {
          for (final h in hosts) {
            s.obj(h).under.remove(id);
          }
          _moveTo(id, Place.inkwell, exerted: true);
        }
        if (pick.isNotEmpty) log('${pl.name} puts ${pick.length} card${pick.length == 1 ? '' : 's'} into their inkwell.', player: p, kind: 'ink');
      case ShuffleRevealSameName():
        String? name;
        if (pl.discard.isNotEmpty) {
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose a card from your discard to shuffle into your deck', options: List.of(pl.discard), min: 1, max: 1, source: ctx.source)).first;
          name = db[s.obj(pick).card]!.name.toLowerCase();
          _moveTo(pick, Place.deck);
          s.rng.shuffle(pl.deck);
        }
        if (pl.deck.isEmpty) return;
        final top = pl.deck.first;
        log('${pl.name} reveals ${nameOf(top)}.', player: p, card: top);
        if (name != null && db[s.obj(top).card]!.names.any((x) => x.toLowerCase() == name)) {
          if (askYesNo(p, 'Play ${nameOf(top)} for free?', source: ctx.source)) _enterPlay(p, top, free: true);
        } else {
          _send(top, ZoneDest.hand, p, ctx);
        }
      case ReturnFromDiscardAs(:final filter, :final slot):
        final cands = [
          for (final id in pl.discard)
            if (_zoneMatches(filter, id, ctx, Place.discard)) id,
        ];
        if (cands.isEmpty) {
          ctx.didIt = false;
          return;
        }
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Return one from your discard to your hand', options: cands, min: 1, max: 1, source: ctx.source));
        for (final id in pick) {
          _moveTo(id, Place.hand);
          log('${nameOf(id)} returns to ${pl.name}’s hand.', card: id, kind: 'return');
          _emit(_Ev(kind: _EvKind.returnedFromDiscard, card: id, player: p));
        }
        ctx.slots[slot] = pick;
        ctx.didIt = true;
      case PlaySlotFree(:final slot):
        final ids = ctx.slots[slot] ?? const <CardId>[];
        if (ids.isEmpty || s.obj(ids.first).zone != Place.hand || s.obj(ids.first).owner != p) return;
        _enterPlay(p, ids.first, free: true);
        ctx.didIt = true;
      case BanishUpToEventStrength():
        final x = ctx.event?.strength ?? 0;
        final doomed = [
          for (final q in _turnOrder())
            for (final id in s.player(q).play)
              if (chars(id).type == CardType.character && chars(id).strength <= x) id,
        ];
        for (final id in doomed) {
          _banish(id, by: ctx.source);
        }
      case NextCostReductionBy(:final filter, :final amount):
        final n = _evalAmount(amount, ctx);
        if (n > 0) s.reductions.add(NextReduction(p, filter, n, s.turn));
      case LimitPerTurn(:final n, :final key, :final effect):
        final src = s.objOrNull(ctx.source);
        if (src != null) {
          final v = src.usedOn[key] ?? 0;
          final count = v ~/ 100 == s.turn ? v % 100 : 0;
          if (count >= n) return;
          src.usedOn[key] = s.turn * 100 + count + 1;
        }
        _resolveEffect(effect, ctx);
      case DiscardUnderThis(:final filter):
        final cands = [
          for (final id in pl.discard)
            if (_zoneMatches(filter, id, ctx, Place.discard)) id,
        ];
        if (cands.isEmpty || s.objOrNull(ctx.source)?.zone != Place.play) return;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose a card to put under ${nameOf(ctx.source)}', options: cands, min: 1, max: 1, source: ctx.source)).first;
        _s4PutUnder(pick, ctx.source, faceDown: false, by: p);
        log('${nameOf(pick)} goes under ${nameOf(ctx.source)}.', player: p, card: ctx.source, kind: 'ability');
      case PlayFromUnderThisTurn():
        final src = s.objOrNull(ctx.source);
        if (src == null || src.zone != Place.play) return;
        s.timed.add(Timed(ts: s.nextTs++, controller: p, source: ctx.source, lasting: Lasting.thisTurn, turn: s.turn, cards: [ctx.source], label: 's4fromunder:${src.zcc}'));
        s.version++;
      case BanishTotalStrength(:final filter, :final total):
        final chosen = <CardId>[];
        var used = 0;
        while (true) {
          final cands = [
            for (final id in matching(filter, controller: p, source: ctx.source))
              if (!chosen.contains(id) && !(s.obj(id).owner != p && chars(id).has(Kw.ward)) && used + chars(id).strengthAtLeast0 <= total) id,
          ];
          if (cands.isEmpty) break;
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose another to banish (total strength ${total - used} left)', options: cands, min: 0, max: 1, source: ctx.source));
          if (pick.isEmpty) break;
          chosen.add(pick.first);
          used += chars(pick.first).strengthAtLeast0;
        }
        for (final id in chosen) {
          if (s.obj(id).owner != p) _emit(_Ev(kind: _EvKind.chosenByOpponent, card: id, player: p));
          _s4Chosen(id, ctx);
        }
        for (final id in chosen) {
          _banish(id, by: ctx.source);
        }
        ctx.didIt = chosen.isNotEmpty;
    }
  }

  /// Puts [card] (from a deck or a discard) under [host] (CR 8.4.2), faceup or facedown.
  void _s4PutUnder(CardId card, CardId host, {required bool faceDown, required int by}) {
    final s = state;
    final o = s.obj(card);
    if (o.zone == Place.discard) s.leftDiscardThisTurn++;
    s.player(o.owner).zone(o.zone).remove(card);
    o
      ..zone = Place.play
      ..zcc += 1
      ..faceDown = faceDown
      ..exerted = false
      ..damage = 0
      ..at = null
      ..timestamp = s.nextTs++
      ..enteredTurn = s.turn;
    s.obj(host).under.insert(0, card);
    s.version++;
    _emit(_Ev(kind: _EvKind.putUnder, card: host, player: by));
  }

  /// Plays an action for free from where it is, then puts it on the bottom of its owner's deck
  /// instead of into the discard (Ursula - Deceiver of All).
  void _s4PlayActionFree(int p, CardId id, _Ctx ctx) {
    final s = state;
    final c = db[s.obj(id).card]!;
    log('${s.player(p).name} plays ${c.fullName} again.', player: p, card: id, kind: 'play');
    _moveTo(id, Place.play);
    final n = ++s.player(p).actionsThisTurn;
    _emit(_Ev(kind: _EvKind.played, card: id, player: p, amount: n));
    final eff = LorcanaParser.parse(c).abilities.whereType<ActionEffect>().firstOrNull;
    if (eff != null) _resolveEffect(eff.effect, _Ctx(this, controller: p, source: id, isAction: true));
    if (s.obj(id).zone == Place.play) _moveTo(id, Place.deck, bottom: true);
    ctx.didIt = true;
  }

  // -------------------------------------------------------------------------------------------
  // Amounts and conditions
  // -------------------------------------------------------------------------------------------

  int _s4Amount(S4Amount a, _Ctx ctx) {
    switch (a) {
      case InkTypes(:final filter):
        final inks = <Ink>{};
        for (final id in matching(filter, controller: ctx.controller, source: ctx.source, whose: Owner.yours)) {
          inks.addAll(db[state.obj(id).card]!.inks);
        }
        return inks.length;
      case Noted(:final key, :final per):
        return per * (ctx.s4[key] ?? 0);
      case LocationLoreOf(:final character):
        final ids = _resolveTargets(character, ctx, choose: false);
        final at = ids.isEmpty ? null : state.obj(ids.first).at;
        return at == null || state.objOrNull(at)?.zone != Place.play ? 0 : chars(at).loreAtLeast0;
    }
  }

  /// [f] against the printed card, wherever it is (type, owner, name, classifications, cost).
  bool _s4Printed(Filter f, CardId id, int controller) {
    final o = state.objOrNull(id);
    if (o == null) return false;
    final c = db[o.card]!;
    if (!f.types.contains(c.type)) return false;
    if (f.owner == Owner.yours && o.owner != controller) return false;
    if (f.owner == Owner.opposing && o.owner == controller) return false;
    if (f.classes.isNotEmpty && !f.classes.any(c.hasClass)) return false;
    if (f.named != null && !c.names.any((n) => n.toLowerCase() == f.named!.toLowerCase())) return false;
    if (f.costMax != null && c.cost > f.costMax!) return false;
    if (f.costMin != null && c.cost < f.costMin!) return false;
    return true;
  }

  bool _evalS4Cond(S4Cond c, _Ctx ctx) {
    final s = state;
    final p = ctx.controller;
    switch (c) {
      case AllInkExerted():
        return s.player(p).inkwell.every((id) => s.obj(id).exerted);
      case SlotWas(:final slot, :final filter):
        return (ctx.slots[slot] ?? const <CardId>[]).any((id) => _s4Printed(filter, id, p));
      case NotedCond(:final key, :final cmp, :final n):
        return _cmp(ctx.s4[key] ?? 0, cmp, n);
      case ExertedHereWhenBanished():
        return (ctx.event?.hereExerted ?? 0) > 0;
      case PlayedThisTurn(:final filter):
        return s.player(p).playedThisTurn.any((id) => _s4Printed(filter, id, p));
      case OpponentMoreLore():
        return s.opponents(p).any((q) => !s.player(q).lost && s.player(q).lore > s.player(p).lore);
      case OpponentMoreCharacters():
        int count(int q) => s.player(q).play.where((id) => chars(id).type == CardType.character).length;
        return s.opponents(p).any((q) => !s.player(q).lost && count(q) > count(p));
      case SangThisSong():
        return ctx.s4['sung'] == 1;
      case PutUnderSelfThisTurn():
        return s.objOrNull(ctx.source)?.usedOn[_putUnderKey] == s.turn;
      case LeftDiscardThisTurn(:final n):
        return s.leftDiscardThisTurn >= n;
      case SourceIn(:final place):
        return s.objOrNull(ctx.source)?.zone == place;
      case EventUnderHas(:final filter):
        return (ctx.event?.under ?? const <CardId>[]).any((id) => _s4Printed(filter, id, p));
    }
  }

  bool _s4TriggerMatches(S4Trigger t, _Ev e, CardId src, int you, {bool floating = false}) {
    switch (t) {
      case MovedHereFromLocation():
        return !floating && e.kind == _EvKind.moves && e.other == src && e.amount == 1;
      case ChosenFor(:final types):
        if (floating || e.kind != _EvKind.chosen || e.card != src || e.other == null) return false;
        final by = state.objOrNull(e.other!);
        return by != null && types.contains(db[by.card]!.type);
    }
  }

  /// A card was chosen for an action or ability ("whenever this character is chosen for …").
  void _s4Chosen(CardId id, _Ctx ctx) => _emit(_Ev(kind: _EvKind.chosen, card: id, other: ctx.source, player: ctx.controller));

  /// Keeps per-card records from events: a card was put under it this turn.
  void _s4Track(_Ev e) {
    if (e.kind == _EvKind.putUnder && e.card != null) state.objOrNull(e.card!)?.usedOn[_putUnderKey] = state.turn;
  }

  /// Exerted characters at location [id] (for "if there was an exerted character here").
  int _s4ExertedHere(CardId id) {
    var n = 0;
    for (final q in state.players) {
      for (final x in q.play) {
        if (state.obj(x).at == id && state.obj(x).exerted) n++;
      }
    }
    return n;
  }

  // -------------------------------------------------------------------------------------------
  // Statics
  // -------------------------------------------------------------------------------------------

  /// A slice static that changes [ch] (only "gains Resist +1 for each …"); others act elsewhere.
  void _s4Static(S4Static e, Static st, CardId src, int ctl, LChars ch) {
    if (e is! KeywordPerCount) return;
    final ctx = _Ctx(this, controller: ctl, source: src);
    if (st.condition != null && !_evalCond(st.condition!, ctx)) return;
    final n = _evalAmount(e.amount, ctx);
    if (n > 0) ch.addKeyword(Keyword(e.kw, n: n));
  }

  /// Whether a timed effect of the slice still applies: "while this item is in play".
  bool _s4TimedLive(Timed t) {
    if (!t.label.startsWith('s4while:')) return true;
    final parts = t.label.split(':');
    final src = state.objOrNull(t.source);
    final id = t.cards?.firstOrNull;
    return src != null && src.zone == Place.play && '${src.zcc}' == parts[1] && id != null && '${state.obj(id).zcc}' == parts[2];
  }

  /// The slice's statics of cards in play whose condition holds: none (cheaply) unless a card in
  /// play has one.
  Iterable<(CardId, StaticEffect, int)> _s4Statics() {
    var any = false;
    for (final q in state.players) {
      for (final x in q.play) {
        final name = state.obj(x).card;
        if (_hasS4Static.putIfAbsent(name, () => LorcanaParser.parse(db[name]!).abilities.any((a) => a is Static && a.effect is S4Static))) any = true;
      }
    }
    return any ? _activeStatics().where((x) => x.$2 is S4Static) : const [];
  }

  /// "All opposing characters gain the Villain classification".
  bool _s4GainedClass(CardId id, List<String> classes) {
    if (_classBusy) return false;
    _classBusy = true;
    try {
      for (final (src, e, ctl) in _s4Statics()) {
        if (e is! GainClass || !classes.any((c) => c.toLowerCase() == e.cls.toLowerCase())) continue;
        if (matches(e.affected, id, controller: ctl, source: src)) return true;
      }
      return false;
    } finally {
      _classBusy = false;
    }
  }

  /// The slice's filter fields: "with a card under them", "without Evasive".
  bool _s4FilterOk(Filter f, CardId id, Place place) {
    final o = state.obj(id);
    if (f.hasUnder != null && (place == Place.play && o.under.isNotEmpty) != f.hasUnder) return false;
    if (f.withoutKw != null) {
      final has = place == Place.play ? chars(id).has(f.withoutKw!) : LorcanaParser.parse(db[o.card]!).abilities.any((a) => a is KeywordAbility && a.keyword.kw == f.withoutKw);
      if (has) return false;
    }
    return true;
  }

  bool _s4NoDamageRemoval() => _s4Statics().any((x) => x.$2 is NoDamageRemoval);

  /// "Your characters named Robin Hood may move here for free".
  bool _s4MovesFree(CardId character, CardId location) {
    final o = state.obj(location);
    for (final a in LorcanaParser.parse(db[o.card]!).abilities) {
      if (a is! Static || a.effect is! MovesHereFree) continue;
      final ctx = _Ctx(this, controller: o.owner, source: location);
      if (a.condition != null && !_evalCond(a.condition!, ctx)) continue;
      if (matches((a.effect as MovesHereFree).filter, character, controller: o.owner, source: location)) return true;
    }
    return false;
  }

  /// "You pay 1 {i} less to play characters using their Shift ability".
  int _s4ShiftReduction(int p, CardId card) {
    var n = 0;
    for (final (src, e, ctl) in _s4Statics()) {
      if (e is ShiftCostLess && ctl == p && matches(e.filter, card, controller: p, source: src, place: Place.hand)) n += e.n;
    }
    return n;
  }

  // -------------------------------------------------------------------------------------------
  // Playing from elsewhere, alternate costs, "can't play"
  // -------------------------------------------------------------------------------------------

  /// The card [id] is under, if any.
  CardId? _s4HostOf(CardId id) {
    for (final q in state.players) {
      for (final x in q.play) {
        if (state.obj(x).under.contains(id)) return x;
      }
    }
    return null;
  }

  /// Can [p] play [id] from its discard (The Horned King) or from under a card (The Black
  /// Cauldron) now?
  bool _s4PlayableZone(int p, CardId id) {
    final o = state.obj(id);
    if (o.owner != p) return false;
    if (o.zone == Place.discard) {
      return _s4Statics().any((x) => x.$2 is PlayFromDiscard && x.$3 == p && matches((x.$2 as PlayFromDiscard).filter, id, controller: p, source: x.$1, place: Place.discard));
    }
    if (o.zone != Place.play || state.player(p).play.contains(id) || db[o.card]!.type != CardType.character) return false;
    final host = _s4HostOf(id);
    if (host == null) return false;
    final h = state.obj(host);
    return state.timed.any((t) => t.label == 's4fromunder:${h.zcc}' && t.source == host);
  }

  /// Cards [p] may play from somewhere other than the hand, in a fixed order.
  void _s4ExtraPlays(int p, void Function(LMove) add) {
    final ids = <CardId>[
      ...state.player(p).discard,
      for (final h in state.player(p).play) ...state.obj(h).under,
    ];
    for (final id in ids) {
      if (!_s4PlayableZone(p, id)) continue;
      add(PlayMove(p, id));
      for (final onto in shiftTargets(p, id)) {
        add(PlayMove(p, id, mode: PlayMode.shift, onto: onto));
      }
    }
  }

  /// The card that lets [id] be played from where it is (for the table), or null.
  CardId? playEnabler(CardId id) {
    final o = state.obj(id);
    if (o.zone == Place.discard) {
      for (final (src, e, ctl) in _s4Statics()) {
        if (e is PlayFromDiscard && ctl == o.owner) return src;
      }
      return null;
    }
    return o.zone == Place.play && !state.player(o.owner).play.contains(id) ? _s4HostOf(id) : null;
  }

  /// Before a card is played: takes it out from under its host; whether it enters exerted ("if
  /// you do, they enter play exerted").
  bool _s4BeforePlay(PlayMove m) {
    final o = state.obj(m.card);
    if (o.zone == Place.discard) {
      return _s4Statics().any((x) => x.$2 is PlayFromDiscard && x.$3 == m.seat && (x.$2 as PlayFromDiscard).exerted && matches((x.$2 as PlayFromDiscard).filter, m.card, controller: m.seat, source: x.$1, place: Place.discard));
    }
    if (o.zone == Place.play && !state.player(o.owner).play.contains(m.card)) {
      final host = _s4HostOf(m.card);
      if (host != null) state.obj(host).under.remove(m.card);
    }
    return false;
  }

  AltCostExert? _s4AltCost(CardId id) =>
      LorcanaParser.parse(db[state.obj(id).card]!).abilities.whereType<Static>().map((a) => a.effect).whereType<AltCostExert>().firstOrNull;

  List<CardId> _s4AltCostCards(int p, AltCostExert alt) => [
    for (final id in matching(alt.filter, controller: p, whose: Owner.yours))
      if (!state.obj(id).exerted) id,
  ];

  /// The opponent's static that stops [p] playing [id] ("opponents can't play actions"), which
  /// also stops playing it for free by an effect (CR 1.2.2).
  CardId? _s4CantPlayBy(int p, CardId id) {
    for (final (src, e, ctl) in _s4Statics()) {
      if (e is OpponentsCantPlay && ctl != p && _s4Printed(e.filter.copyWith(owner: Owner.any), id, ctl)) return src;
    }
    return null;
  }

  bool _s4CantPlay(int p, CardId id) => _s4CantPlayBy(p, id) != null;

  /// Opponents' "can't play" statics; and the alternate cost when the ink isn't there. Null:
  /// no say; '': playable; else why not.
  String? _s4PlayProblem(PlayMove m) {
    final p = m.seat;
    final c = db[state.obj(m.card).card]!;
    final stop = _s4CantPlayBy(p, m.card);
    if (stop != null) return '${nameOf(stop)}: you can’t play ${c.type.name}s';
    if (m.mode != PlayMode.ink || state.obj(m.card).zone != Place.hand) return null;
    final alt = _s4AltCost(m.card);
    if (alt == null || _inkReady(p) >= playCost(p, m.card)) return null;
    return _s4AltCostCards(p, alt).length >= alt.n ? '' : null;
  }

  /// Pays the alternate cost instead of ink when the player wants to (or must): true if paid.
  bool _s4AltPay(PlayMove m) {
    final p = m.seat;
    final alt = _s4AltCost(m.card);
    if (alt == null || state.obj(m.card).zone != Place.hand) return false;
    final cards = _s4AltCostCards(p, alt);
    if (cards.length < alt.n) return false;
    final must = _inkReady(p) < playCost(p, m.card);
    if (!must && !askYesNo(p, 'Exert ${alt.n} ${alt.filter.describe()}s to play ${nameOf(m.card)} for free?', source: m.card)) return false;
    final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Exert ${alt.n} to pay the cost', options: cards, min: alt.n, max: alt.n, source: m.card));
    for (final id in pick) {
      _exertCard(id);
    }
    return true;
  }

  // -------------------------------------------------------------------------------------------
  // Activated abilities: granted ones and the slice's costs
  // -------------------------------------------------------------------------------------------

  /// A card's abilities: printed, then granted by statics ("characters gain "{e} - draw a card"
  /// while here") and by effects for a while ("… this turn"). Activations index into this list.
  List<Ability> abilitiesOf(CardId id) {
    final printed = parsed(id).abilities;
    if (state.obj(id).zone != Place.play) return printed;
    final out = <Ability>[...printed];
    for (final (src, e, ctl) in _s4Statics()) {
      if (e is GrantAbility && (e.affected == null ? src == id : matches(e.affected!, id, controller: ctl, source: src))) out.add(e.ability);
    }
    for (final t in state.timed) {
      if (t.label != 's4grant' || !(t.cards?.contains(id) ?? false)) continue;
      final ab = _s4GrantedBy(t.source);
      if (ab != null) out.add(ab);
    }
    return out;
  }

  Activated? _s4GrantedBy(CardId source) {
    Activated? find(Effect e) => switch (e) {
      GrantAbilityFor(:final ability) => ability,
      Seq(:final steps) => steps.map(find).whereType<Activated>().firstOrNull,
      May(e: final x) => find(x),
      If(:final then, :final otherwise) => find(then) ?? (otherwise == null ? null : find(otherwise)),
      _ => null,
    };
    final o = state.objOrNull(source);
    if (o == null) return null;
    for (final a in LorcanaParser.parse(db[o.card]!).abilities) {
      final e = switch (a) {
        ActionEffect(:final effect) => effect,
        Triggered(:final effect) => effect,
        Activated(:final effect) => effect,
        _ => null,
      };
      final f = e == null ? null : find(e);
      if (f != null) return f;
    }
    return null;
  }

  String? _s4CostProblem(int p, CardId id, int index, Cost cost) {
    if (cost.oncePerTurn && state.obj(id).usedOn[index] == state.turn) return 'Once per turn';
    final fs = cost.discardFilters;
    if (fs != null && !state.player(p).hand.any((h) => fs.any((f) => _zoneMatches(f, h, _Ctx(this, controller: p, source: id), Place.hand)))) return 'No card to discard for the cost';
    return null;
  }

  void _s4PayCost(int p, CardId id, int index, Cost cost, _Ctx ctx) {
    if (cost.oncePerTurn) state.obj(id).usedOn[index] = state.turn;
    final fs = cost.discardFilters;
    if (fs != null) {
      final cands = [
        for (final h in state.player(p).hand)
          if (fs.any((f) => _zoneMatches(f, h, ctx, Place.hand))) h,
      ];
      final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Discard a card for the cost', options: cands, min: 1, max: 1, source: id));
      ctx.s4['discardedLore'] = db[state.obj(pick.first).card]!.lore ?? 0;
      _discardCards(p, pick);
    }
    if (cost.damageSelf > 0) _dealDamage(id, cost.damageSelf, source: id);
  }
}
