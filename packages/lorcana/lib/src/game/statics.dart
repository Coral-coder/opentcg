part of 'game.dart';

/// Static abilities beyond stat changes (CR 6.4): their conditions, challenge limiters, how cards
/// enter play, the lore needed to win, and deck limits.
extension GameStatics on Game {
  bool _cmp(int v, Cmp k, int n) => switch (k) {
    Cmp.ge => v >= n,
    Cmp.le => v <= n,
    Cmp.eq => v == n,
    Cmp.gt => v > n,
    Cmp.lt => v < n,
  };

  bool _evalMoreCond(Cond c, _Ctx ctx) {
    final s = state;
    switch (c) {
      case FirstTurnNotFirstPlayer():
        // The player's first turn: turn 2 for the second player in a two-player game (CR 2.2.1).
        return ctx.controller != s.firstPlayer && s.turn <= s.players.length && s.active == ctx.controller;
      case SelfStat(:final stat, :final cmp, :final n):
        if (s.objOrNull(ctx.source)?.zone != Place.play) return false;
        final ch = chars(ctx.source);
        final v = switch (stat) {
          Stat.strength => ch.strength,
          Stat.willpower => ch.willpower,
          Stat.lore => ch.lore,
        };
        return _cmp(v, cmp, n);
      case SelfHasUnder():
        final o = s.objOrNull(ctx.source);
        return o != null && o.zone == Place.play && o.under.isNotEmpty;
      case AnyWithUnder(:final whose):
        for (var p = 0; p < s.players.length; p++) {
          if (whose == Owner.yours && p != ctx.controller) continue;
          if (whose == Owner.opposing && p == ctx.controller) continue;
          if (s.player(p).play.any((id) => s.obj(id).under.isNotEmpty)) return true;
        }
        return false;
      case InkwellCond(:final who, cmp: final k, :final n):
        return _players(who, ctx).any((p) => _cmp(s.player(p).inkwell.length, k, n));
      case MoreThanEachOpponent(:final place, :final filter):
        int count(int p) => filter == null ? s.player(p).zone(place).length : matching(filter, controller: ctx.controller, source: ctx.source, place: place, whose: p == ctx.controller ? Owner.yours : Owner.opposing).where((id) => s.obj(id).owner == p).length;
        final mine = count(ctx.controller);
        return s.opponents(ctx.controller).where((q) => !s.player(q).lost).every((q) => mine > count(q));
      case BeingChallenged():
        return _challengePair?.$2 == ctx.source;
      case Challenging(:final defender):
        final pair = _challengePair;
        return pair != null && pair.$1 == ctx.source && matches(defender, pair.$2, controller: ctx.controller, source: ctx.source);
      case ThisTurnCond(:final what, cmp: final k, :final n):
        final pl = s.player(ctx.controller);
        final v = switch (what) {
          TurnCount.putIntoDiscard => pl.discardedThisTurn,
          TurnCount.actionsPlayed => pl.actionsThisTurn,
          TurnCount.questedOthers => pl.questsThisTurn,
          TurnCount.discardedByYou => pl.discardedThisTurn,
        };
        return _cmp(v, k, n);
      case BanishedThisTurn(:final filter, :final inChallenge):
        for (final b in s.banishedThisTurn) {
          final parts = b.split('|');
          if (inChallenge && parts[2] != 'c') continue;
          final owner = int.parse(parts[1]);
          if (filter.owner == Owner.yours && owner != ctx.controller) continue;
          if (filter.owner == Owner.opposing && owner == ctx.controller) continue;
          final card = db[parts[0]];
          if (card == null || !filter.types.contains(card.type)) continue;
          if (filter.named != null && !filter.nameMatches(card.names)) continue;
          if (filter.classes.isNotEmpty && !filter.classes.any(card.hasClass)) continue;
          return true;
        }
        return false;
      case S4Cond():
        return _evalS4Cond(c, ctx);
      default:
        return false;
    }
  }

  /// Statics of cards in play whose condition holds now: (source, effect, controller).
  Iterable<(CardId, StaticEffect, int)> _activeStatics() sync* {
    for (final (src, st, ctl) in _statics()) {
      if (st.condition != null && !_evalCond(st.condition!, _Ctx(this, controller: ctl, source: src))) continue;
      yield (src, st.effect, ctl);
    }
  }

  /// Can't [attacker] challenge [target] because of a "can't be challenged by" limiter?
  String? _challengeLimiter(CardId attacker, CardId target) {
    final defender = state.obj(target).owner;
    for (final (src, e, ctl) in _activeStatics()) {
      if (e is! CantBeChallengedBy) continue;
      final protects = e.defenders == null ? src == target : (ctl == defender && matches(e.defenders!, target, controller: ctl, source: src));
      if (!protects) continue;
      if (matches(e.attackers, attacker, controller: ctl, source: src)) return '${nameOf(target)} can’t be challenged by ${nameOf(attacker)}';
    }
    return null;
  }

  /// Lore [p] needs to win (CR 1.11.1; "opponents need 25 lore to win the game").
  int loreToWin(int p) {
    var n = 20;
    for (final (_, e, ctl) in _activeStatics()) {
      if (e is OpponentsLoreToWin && ctl != p && e.n > n) n = e.n;
    }
    return n;
  }

  /// Does an opponent's static make [id], entering [p]'s play, enter exerted?
  bool _entersExertedByOpponents(int p, CardId id) {
    for (final (src, e, ctl) in _activeStatics()) {
      if (e is OpposingEnterExerted && ctl != p && matches(e.filter.copyWith(owner: Owner.any), id, controller: ctl, source: src)) return true;
    }
    return false;
  }

  /// Does an opponent's static make cards enter [p]'s inkwell exerted?
  bool _inkEntersExerted(int p) => _activeStatics().any((x) => x.$2 is OpposingInkExerted && x.$3 != p);

  /// The challenger's change from the challenged card's statics (CR 4.6.6).
  void _applyChallengerMods(CardId id, LChars ch) {
    final c = _challengePair;
    if (c == null || c.$1 != id) return;
    final defender = c.$2;
    final o = state.objOrNull(defender);
    if (o == null || o.zone != Place.play) return;
    for (final a in LorcanaParser.parse(db[o.card]!).abilities) {
      if (a is! Static || a.effect is! ChallengerMod) continue;
      final ctx = _Ctx(this, controller: o.owner, source: defender);
      if (a.condition != null && !_evalCond(a.condition!, ctx)) continue;
      final e = a.effect as ChallengerMod;
      _addStat(ch, e.stat, e.negative ? -e.amount : e.amount);
    }
  }

  /// A condition with a self-stat part, judged against [own] (the values being worked out for
  /// the source itself) when given.
  bool _selfStatHolds(Cond c, CardId src, int ctl, LChars? own) {
    final ctx = _Ctx(this, controller: ctl, source: src);
    if (c is AllConds) return c.conds.every((x) => _selfStatHolds(x, src, ctl, own));
    if (c is SelfStat && own != null) {
      final v = switch (c.stat) {
        Stat.strength => own.strength,
        Stat.willpower => own.willpower,
        Stat.lore => own.lore,
      };
      return _cmp(v, c.cmp, c.n);
    }
    return _evalCond(c, ctx);
  }
}
