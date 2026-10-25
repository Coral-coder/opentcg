part of 'game.dart';

/// Board effects (players choosing their own cards, lore races, moving to locations) and the
/// "this turn" record behind conditions like "if you played another character this turn".
extension GameBoard on Game {
  /// Keeps each player's record of the turn from the events (called for every event).
  void _trackTurn(_Ev e) {
    final s = state;
    void add(int? p, TurnStat st) {
      if (p == null || p < 0 || p >= s.players.length) return;
      s.player(p).turnStats[st.index]++;
    }

    switch (e.kind) {
      case _EvKind.played:
        final p = e.player;
        final id = e.card;
        if (p == null || id == null) return;
        add(p, TurnStat.cardsPlayed);
        final c = db[s.obj(id).card]!;
        if (c.type == CardType.character) {
          add(p, TurnStat.charactersPlayed);
          s.player(p).playedThisTurn.add(id);
        }
        if (c.isSong) add(p, TurnStat.songsPlayed);
        // Played by Shift (CR 8.10): the event names the card it went on top of.
        if (e.other != null && c.type == CardType.character) s.obj(id).shiftedZcc = s.obj(id).zcc;
      case _EvKind.quests:
        add(e.player, TurnStat.quested);
      case _EvKind.challenges:
        add(e.player, TurnStat.challenged);
      case _EvKind.dealtDamage:
        add(e.player, TurnStat.damaged);
      case _EvKind.banished:
        if (e.cardType == CardType.character) add(e.player, TurnStat.banished);
      case _EvKind.banishedInChallenge:
        if (e.cardType == CardType.character) {
          add(e.player, TurnStat.banished);
          add(e.player, TurnStat.banishedInChallenge);
        }
      default:
    }
  }

  /// A new turn: everyone's "this turn" record starts over.
  void _resetTurnRecords() {
    for (final p in state.players) {
      p.turnStats = List.filled(TurnStat.values.length, 0);
      p.playedThisTurn = [];
    }
  }

  void _noteDamageRemoved(CardId id, int n) {
    if (n <= 0) return;
    state.player(state.obj(id).owner).turnStats[TurnStat.removedDamage.index] += n;
  }

  int _boardAmount(Amount a, _Ctx ctx) => switch (a) {
    DamageOn(:final target) => () {
      final ids = _resolveTargets(target, ctx, choose: true);
      return ids.isEmpty ? 0 : state.obj(ids.first).damage;
    }(),
    _ => 0,
  };

  bool _evalBoardCond(Cond c, _Ctx ctx) {
    bool cmp(int v, Cmp k, int n) => switch (k) {
      Cmp.ge => v >= n,
      Cmp.le => v <= n,
      Cmp.eq => v == n,
      Cmp.gt => v > n,
      Cmp.lt => v < n,
    };
    switch (c) {
      case TurnStatCond(:final stat, :final who, cmp: final k, :final n, :final excludeSource):
        return _players(who, ctx).any((p) {
          var v = state.player(p).turnStats[stat.index];
          if (excludeSource && stat == TurnStat.charactersPlayed) {
            v = state.player(p).playedThisTurn.where((id) => id != ctx.source).length;
          }
          return cmp(v, k, n);
        });
      case ShiftedCond():
        final o = state.objOrNull(ctx.source);
        return o != null && o.zone == Place.play && o.shiftedZcc == o.zcc;
      case HandCompare(:final chosen):
        final mine = state.player(ctx.controller).hand.length;
        return _players(chosen ? Who.chosenOpponent : Who.opponents, ctx).any((p) => state.player(p).hand.length > mine);
      case SelfDamage(:final min):
        final o = state.objOrNull(ctx.source);
        return o != null && o.zone == Place.play && o.damage >= min;
      case StrongestCond():
        final mine = matching(const Filter(), controller: ctx.controller, whose: Owner.yours);
        final theirs = matching(const Filter(owner: Owner.opposing), controller: ctx.controller);
        final best = theirs.fold<int>(-1 << 30, (m, id) => chars(id).strength > m ? chars(id).strength : m);
        return mine.any((id) => chars(id).strength > best);
      default:
        return false;
    }
  }

  void _resolveBoard(Effect e, _Ctx ctx) {
    switch (e) {
      case SameNameAs(:final chosen, :final others, :final into):
        final picked = _resolveTargets(chosen, ctx);
        final names = {for (final id in picked) ...db[state.obj(id).card]!.names.map((n) => n.toLowerCase())};
        ctx.slots[into] = [
          for (final id in matching(others, controller: ctx.controller, source: ctx.source))
            if (!picked.contains(id) && db[state.obj(id).card]!.names.any((n) => names.contains(n.toLowerCase()))) id,
        ];
      case PlayerChooses(:final who, :final filter, :final slot, :final then):
        for (final p in _players(who, ctx)) {
          final cands = [
            for (final id in matching(filter, controller: ctx.controller, source: ctx.source))
              if (state.obj(id).owner == p) id,
          ];
          if (cands.isEmpty) continue;
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose one of your ${filter.describe()}', options: cands, min: 1, max: 1, source: ctx.source));
          ctx.slots[slot] = pick;
          _resolveEffect(then, ctx);
        }
        ctx.didIt = true;
      case LoseLoreRicher(:final amount):
        final mine = state.player(ctx.controller).lore;
        for (final p in _players(Who.opponents, ctx)) {
          if (state.player(p).lore > mine) _loseLore(p, _evalAmount(amount, ctx));
        }
      case MoveToLocation(:final characters, :final toEventLocation):
        final movers = <CardId>[];
        for (final t in characters) {
          for (final id in _resolveTargets(t, ctx)) {
            if (chars(id).type == CardType.character && !movers.contains(id)) movers.add(id);
          }
        }
        if (movers.isEmpty) return;
        CardId? loc;
        if (toEventLocation) {
          loc = ctx.event?.location;
          if (loc == null && ctx.event?.card != null && state.objOrNull(ctx.event!.card!)?.zone == Place.play && chars(ctx.event!.card!).type == CardType.location) loc = ctx.event!.card;
        } else {
          final locs = matching(const Filter(types: {CardType.location}), controller: ctx.controller, whose: Owner.yours);
          if (locs.isEmpty) return;
          loc = locs.length == 1 ? locs.first : ask(Decision(kind: DecisionKind.cards, player: ctx.controller, prompt: 'Choose one of your locations', options: locs, min: 1, max: 1, source: ctx.source)).first;
        }
        if (loc == null || state.objOrNull(loc)?.zone != Place.play) return;
        for (final id in movers) {
          if (state.obj(id).at != loc) _moveCharacter(state.obj(id).owner, id, loc, pay: false);
        }
        ctx.didIt = true;
      default:
    }
  }
}
