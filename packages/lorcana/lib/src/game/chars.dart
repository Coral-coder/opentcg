part of 'game.dart';

/// A card's current characteristics: printed values plus every static ability and timed effect
/// that applies (CR 6.4, 6.6). Modifiers combine with no order (CR 6.6.1.2).
class LChars {
  LChars({required this.card, required this.type, required this.cost, required this.strength, required this.willpower, required this.lore, required this.classes, required this.owner});
  final LCard card;
  final CardType type;
  final int cost;
  int strength, willpower, lore;
  final List<String> classes;
  final int owner;
  final Map<Kw, Keyword> keywords = {};
  final Set<Rule> rules = {};

  bool has(Kw k) => keywords.containsKey(k);
  int n(Kw k) => keywords[k]?.n ?? 0;

  void addKeyword(Keyword k) {
    final cur = keywords[k.kw];
    if (cur == null) {
      keywords[k.kw] = k;
    } else if (stackingKws.contains(k.kw)) {
      // +N keywords stack (CR 8.1.2); others don't.
      keywords[k.kw] = Keyword(k.kw, n: cur.n + k.n);
    }
  }

  /// Negative strength deals no damage and counts as 0 (CR 6.6.2); same for lore (6.6.3).
  int get strengthAtLeast0 => strength < 0 ? 0 : strength;
  int get loreAtLeast0 => lore < 0 ? 0 : lore;
}

extension GameChars on Game {
  static final Set<CardId> _inProgress = {};

  /// The current characteristics of a card in any zone.
  LChars chars(CardId id) {
    final o = state.obj(id);
    final c = db[o.card]!;
    final ch = LChars(card: c, type: c.type, cost: c.cost, strength: c.strength ?? 0, willpower: c.willpower ?? 0, lore: c.lore ?? 0, classes: c.classifications, owner: o.owner);
    for (final a in LorcanaParser.parse(c).abilities) {
      if (a is KeywordAbility) ch.addKeyword(a.keyword);
    }
    if (o.zone != Place.play || !_inProgress.add(id)) return ch;
    try {
      // Statics conditioned on their own card's values ("while this character has 4 {s} or
      // more") are applied after everything else, against the values so far.
      final selfStat = <(CardId, Static, int)>[];
      for (final (src, st, ctl) in _statics()) {
        if (st.condition is SelfStat || (st.condition is AllConds && (st.condition as AllConds).conds.any((c) => c is SelfStat))) {
          selfStat.add((src, st, ctl));
          continue;
        }
        final e = st.effect;
        final Filter? affected = switch (e) {
          StaticMod(:final affected) => affected,
          StaticKeyword(:final affected) => affected,
          StaticRule(:final affected) => affected,
          _ => null,
        };
        final applies = affected == null ? src == id : matches(affected, id, controller: ctl, source: src);
        if (!applies) continue;
        if (e is S4Static) {
          _s4Static(e, st, src, ctl, ch);
          continue;
        }
        if (e is! StaticMod && e is! StaticKeyword && e is! StaticRule) continue;
        if (st.condition != null && !_evalCond(st.condition!, _Ctx(this, controller: ctl, source: src))) continue;
        switch (e) {
          case StaticMod(:final stat, :final amount, :final negative):
            final v = _evalAmount(amount, _Ctx(this, controller: ctl, source: src)) * (negative ? -1 : 1);
            _addStat(ch, stat, v);
          case StaticKeyword(:final keyword):
            ch.addKeyword(keyword);
          case StaticRule(:final rule):
            ch.rules.add(rule);
          default:
        }
      }
      for (final t in state.timed) {
        final applies = t.cards != null ? t.cards!.contains(id) : (t.filter != null && matches(t.filter!, id, controller: t.controller, source: t.source));
        if (!applies || !_s4TimedLive(t)) continue;
        if (t.lasting == Lasting.theirNextTurn && !(t.turn < state.turn && state.active == o.owner)) continue;
        if (t.stat != null) _addStat(ch, t.stat!, t.amount);
        if (t.keyword != null) ch.addKeyword(t.keyword!);
        if (t.rule != null) ch.rules.add(t.rule!);
      }
      for (final (src, st, ctl) in selfStat) {
        final e = st.effect;
        final Filter? affected = switch (e) {
          StaticMod(:final affected) => affected,
          StaticKeyword(:final affected) => affected,
          StaticRule(:final affected) => affected,
          _ => null,
        };
        if (affected == null ? src != id : !matches(affected, id, controller: ctl, source: src)) continue;
        if (!_selfStatHolds(st.condition!, src, ctl, src == id ? ch : null)) continue;
        switch (e) {
          case StaticMod(:final stat, :final amount, :final negative):
            _addStat(ch, stat, _evalAmount(amount, _Ctx(this, controller: ctl, source: src)) * (negative ? -1 : 1));
          case StaticKeyword(:final keyword):
            ch.addKeyword(keyword);
          case StaticRule(:final rule):
            ch.rules.add(rule);
          default:
        }
      }
      _applyChallengerMods(id, ch);
      _s3Chars(id, ch);
      // "This character can't gain Evasive": only a printed Evasive stays.
      if (ch.rules.contains(Rule.cantGainEvasive) && !LorcanaParser.parse(c).abilities.any((a) => a is KeywordAbility && a.keyword.kw == Kw.evasive)) ch.keywords.remove(Kw.evasive);
    } finally {
      _inProgress.remove(id);
    }
    return ch;
  }

  void _addStat(LChars ch, Stat s, int v) {
    switch (s) {
      case Stat.strength:
        ch.strength += v;
      case Stat.willpower:
        ch.willpower += v;
      case Stat.lore:
        ch.lore += v;
    }
  }

  /// Static abilities of cards in play, in timestamp order: (source, ability, controller).
  List<(CardId, Static, int)> _statics() {
    final out = <(CardId, Static, int, int)>[];
    for (var p = 0; p < state.players.length; p++) {
      for (final id in state.player(p).play) {
        final o = state.obj(id);
        for (final a in LorcanaParser.parse(db[o.card]!).abilities) {
          if (a is Static && !a.inHand) out.add((id, a, p, o.timestamp));
        }
      }
    }
    out.sortStable((a, b) => a.$4 - b.$4);
    return [for (final x in out) (x.$1, x.$2, x.$3)];
  }

  /// Does [id] match [f], from the point of view of [controller] and the [source] card?
  bool matches(Filter f, CardId id, {required int controller, CardId? source, Place place = Place.play}) {
    final o = state.objOrNull(id);
    if (o == null || o.zone != place) return false;
    if (f.or != null && matches(f.or!, id, controller: controller, source: source, place: place)) return true;
    final c = db[o.card]!;
    if (!f.types.contains(c.type)) return false;
    if (f.song != null && c.isSong != f.song) return false;
    if (f.owner == Owner.yours && o.owner != controller) return false;
    if (f.owner == Owner.opposing && o.owner == controller) return false;
    if (f.other && id == source) return false;
    if (f.classes.isNotEmpty && !f.classes.any(c.hasClass) && !_s4GainedClass(id, f.classes)) return false;
    if (f.named != null && !f.nameMatches(c.names)) return false;
    if (f.notNamed != null && c.names.any((n) => n.toLowerCase() == f.notNamed!.toLowerCase())) return false;
    if (f.ink != null && !c.inks.contains(f.ink)) return false;
    if (f.costMax != null && c.cost > f.costMax!) return false;
    if (f.costMin != null && c.cost < f.costMin!) return false;
    if ((f.hasUnder != null || f.withoutKw != null) && !_s4FilterOk(f, id, place)) return false;
    if (place == Place.play) {
      if (f.exerted != null && o.exerted != f.exerted) return false;
      if (f.damaged != null && (o.damage > 0) != f.damaged) return false;
      if (f.atLocation != null && (o.at != null) != f.atLocation) return false;
      if (f.atThisLocation && (source == null || o.at != source)) return false;
      if (f.atSourcesLocation && (source == null || o.at == null || o.at != state.objOrNull(source)?.at)) return false;
      if (f.strengthMax != null || f.strengthMin != null || f.withKw != null || f.willpowerMin != null) {
        final ch = chars(id);
        if (f.strengthMax != null && ch.strength > f.strengthMax!) return false;
        if (f.strengthMin != null && ch.strength < f.strengthMin!) return false;
        if (f.willpowerMin != null && ch.willpower < f.willpowerMin!) return false;
        if (f.withKw != null && !ch.has(f.withKw!)) return false;
      }
    } else {
      if (f.strengthMax != null && (c.strength ?? 0) > f.strengthMax!) return false;
      if (f.strengthMin != null && (c.strength ?? 0) < f.strengthMin!) return false;
      if (f.willpowerMin != null && (c.willpower ?? 0) < f.willpowerMin!) return false;
    }
    return true;
  }

  /// Cards in [place] of the players [whose] (relative to [controller]) that match.
  List<CardId> matching(Filter f, {required int controller, CardId? source, Place place = Place.play, Owner whose = Owner.any}) {
    final out = <CardId>[];
    for (final p in _turnOrderFrom(controller)) {
      if (whose == Owner.yours && p != controller) continue;
      if (whose == Owner.opposing && p == controller) continue;
      for (final id in state.player(p).zone(place)) {
        if (matches(f, id, controller: controller, source: source, place: place)) out.add(id);
      }
    }
    return out;
  }

  List<int> _turnOrderFrom(int p) => [for (var i = 0; i < state.players.length; i++) (p + i) % state.players.length];
}
