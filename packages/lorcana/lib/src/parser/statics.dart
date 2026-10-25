part of 'parser.dart';

/// Static abilities, conditions and keyword variants (CR 6.4, 8): kept apart from the trigger and
/// effect grammar in parser.dart.

/// "Shift: Discard a location card" / "Shift: Discard 2 cards" (CR 8.10.1).
ShiftDiscard? shiftDiscard(String t) {
  final m = rx(t, r'shift: discard (an?|\d+) ?([a-z]*) cards?');
  if (m == null) return null;
  final n = numWord(m[1]) ?? 1;
  return switch (m[2]) {
    '' => ShiftDiscard(n),
    'character' => ShiftDiscard(n, types: const {CardType.character}),
    'action' => ShiftDiscard(n, types: const {CardType.action}),
    'item' => ShiftDiscard(n, types: const {CardType.item}),
    'location' => ShiftDiscard(n, types: const {CardType.location}),
    'song' => ShiftDiscard(n, types: const {CardType.action}, song: true),
    _ => null,
  };
}

const _allTypes = {CardType.character, CardType.action, CardType.item, CardType.location};

extension _MoreStatics on _CardParser {
  /// Whole-paragraph static templates the general "[condition,] subject predicate" grammar in
  /// `_static` doesn't cover.
  List<Ability>? _moreStatic(String printed, String t) {
    // Typos in the card data ("you other characters", "you characters with Evasive").
    if (t.startsWith('you other ') || t.startsWith('you characters ')) return _static(printed, 'your ${t.substring(4)}');
    var m = rx(t, r"during (?:opponents' turns|each opponent's turn), (.+)");
    if (m != null) return _static(printed, "during an opponent's turn, ${m[1]}");
    // "During your turn, if no other character has quested this turn, …".
    m = rx(t, r'during your turn, ((?:if|while) .+)');
    if (m != null) return _withCond(_static(printed, m[1]), const YourTurn());
    m = rx(t, r"during an opponent's turn, ((?:if|while) .+)");
    if (m != null) return _withCond(_static(printed, m[1]), const Not(YourTurn()));
    // "Your locations and characters at locations gain Resist +1".
    m = rx(t, r'your locations and characters at locations ((?:gets?|gains?) .+)');
    if (m != null) {
      final a = _predicate(m[1], const Filter(types: {CardType.location}, owner: Owner.yours));
      final b = _predicate(m[1], const Filter(owner: Owner.yours, atLocation: true));
      if (a == null || b == null) return null;
      return [for (final e in [...a, ...b]) Static(printed, e)];
    }
    // CR 4.6.6: damage dealt in a challenge is normally the {s}.
    if (t == 'during challenges, your characters deal damage with their willpower instead of their strength') {
      return [Static(printed, const StaticRule(Filter(owner: Owner.yours), Rule.dealsWillpowerInChallenges))];
    }
    // "For each other character named The Queen you have in play, this character gets +1 {l}".
    m = rx(t, r'for each ([^,]+), (this character gets? [+-]\d+ (?:strength|willpower|lore))');
    if (m != null) return _static(printed, '${m[2]} for each ${m[1]}');
    // "While one of your Knight characters is at a location, that character gains Resist +2".
    m = rx(t, r'while one of (your .+?) is at a location, that character ((?:gets?|gains?) .+)');
    if (m != null) {
      final f = _groupFilter(m[1]);
      if (f == null) return null;
      final es = _predicate(m[2], f.copyWith(atLocation: true));
      if (es == null) return null;
      return [for (final e in es) Static(printed, e)];
    }
    // CR 6.7.9: "This character may enter play exerted [to <effect>]".
    m = rx(t, r'this character may enter play exerted(?: to (.+))?');
    if (m != null) {
      Effect? then;
      if (m[1].isNotEmpty) {
        then = effects(m[1], _Ctx());
        if (then == null) return null;
      }
      return [Static(printed, MayEnterExerted(then))];
    }
    return null;
  }

  List<Ability>? _withCond(List<Ability>? list, Cond c) => list == null
      ? null
      : [
          for (final a in list) a is Static ? Static(a.text, a.effect, condition: _and(c, a.condition), inHand: a.inHand) : a,
        ];

  List<StaticEffect>? _moreStaticEffect(String t) {
    // Self cost reductions phrased "you may pay" (and the "you play N {i} less" misprint).
    var m = rx(t, r'you (?:may pay|play) (\d+) ink less to play this (?:character|item|location|action|song)');
    if (m != null) return [CostReduction(const Filter(), Fixed(int.parse(m[1])), self: true)];
    // "You may play this character for free": an alternate cost of nothing, which a player
    // always prefers to the printed one (CR 4.3.6), so it's the whole cost less.
    if (rx(t, r'you (?:may|can) play this (?:character|item|location|action|card) for free') != null) {
      return [CostReduction(const Filter(), Fixed(card.cost), self: true)];
    }
    m = rx(t, r'this character also counts as being named (.+) for shift');
    if (m != null) return [ShiftName(m[1])];
    if (t == 'you can shift any character on top of this character') return const [ShiftName(null)];
    m = rx(t, r'the challenging character gets ([+-])(\d+) (strength|willpower|lore)');
    if (m != null) return [ChallengerMod(_stat(m[3]), int.parse(m[2]), negative: m[1] == '-')];
    m = rx(t, r'opponents need (\d+) lore to win(?: the game)?');
    if (m != null) return [OpponentsLoreToWin(int.parse(m[1]))];
    m = rx(t, r'(opposing .+) enter play exerted');
    if (m != null) {
      final f = _groupFilter(m[1]);
      if (f == null) return null;
      return [OpposingEnterExerted(f)];
    }
    if (t == "cards enter opponents' inkwells exerted") return const [OpposingInkExerted()];
    m = rx(t, r'you may have up to (\d+) copies of .+ in your deck');
    if (m != null) return [DeckLimit(int.parse(m[1]))];
    if (rx(t, r'you may have any number of cards named .+ in your deck') != null) return const [DeckLimit(null)];
    return null;
  }

  List<StaticEffect>? _morePredicate(String p, Filter? f) {
    final rule = switch (p) {
      'can challenge ready characters' => Rule.canChallengeReady,
      'can challenge ready damaged characters' => Rule.canChallengeReadyDamaged,
      "can't move to locations" => Rule.cantMove,
      "can't gain evasive" => Rule.cantGainEvasive,
      "can't sing songs without sing together" => Rule.singsOnlyTogether,
      "can't be dealt damage" => Rule.cantBeDealtDamage,
      "can't exert to sing songs" => Rule.cantSing,
      _ => null,
    };
    if (rule != null) return [StaticRule(f, rule)];
    if (rx(p, r"can quest the turn (?:he|she|they|it)(?:'s| is| are) played") != null) return [StaticRule(f, Rule.canQuestWhileDrying)];
    if (rx(p, r"can't ready at the start of (?:your|their|their players') turns?") != null) return [StaticRule(f, Rule.cantReady)];
    if (p == "can't quest or challenge" || p == "can't challenge or quest") return [StaticRule(f, Rule.cantQuest), StaticRule(f, Rule.cantChallenge)];
    var m = rx(p, r"can't be challenged by (.+)");
    if (m != null) {
      final a = _groupFilter(m[1].replaceAll(' or greater', ' or more'));
      if (a == null) return null;
      return [CantBeChallengedBy(a, defenders: f)];
    }
    m = rx(p, r"can't challenge (this character|your characters)");
    if (m != null && f != null) return [CantBeChallengedBy(f, defenders: m[1] == 'this character' ? null : const Filter(owner: Owner.yours))];
    m = rx(p, r'gains? challenger \+(\d+) strength');
    if (m != null) return [StaticKeyword(f, Keyword(Kw.challenger, n: int.parse(m[1])))];
    m = rx(p, r'gets? ([+-])(\d+) (strength|willpower|lore) for each (?:(\d+) )?damage on (?:him|her|it|them)');
    if (m != null && f == null) return [StaticMod(null, _stat(m[3]), DamageOnSelf(per: m[4].isEmpty ? 1 : int.parse(m[4]), times: int.parse(m[2])), negative: m[1] == '-')];
    m = rx(p, r'gets? ([+-])(\d+) (strength|willpower|lore) for each card under (?:him|her|it|them)');
    if (m != null && f == null) return [StaticMod(null, _stat(m[3]), UnderSelf(times: int.parse(m[2])), negative: m[1] == '-')];
    m = rx(p, r"gets? ([+-])(\d+) (strength|willpower|lore) for each card in (your hand|your opponents' hands|opponents' hands)");
    if (m != null) return [StaticMod(f, _stat(m[3]), HandSize(m[4] == 'your hand' ? Who.you : Who.opponents, per: int.parse(m[2])), negative: m[1] == '-')];
    // "Gets +1 {s}, +1 {w}, and +1 {l}".
    m = rx(p, r'gets? (.+, .+)');
    if (m != null) {
      final out = <StaticEffect>[];
      for (final part in m[1].split(RegExp(r',? and |, '))) {
        final x = rx(part.trim(), r'([+-])(\d+) (strength|willpower|lore)');
        if (x == null) return null;
        out.add(StaticMod(f, _stat(x[3]), Fixed(int.parse(x[2])), negative: x[1] == '-'));
      }
      return out;
    }
    return null;
  }

  Cond? _moreCondition(String s) {
    if (s == "this is your first turn and you're not the first player") return const FirstTurnNotFirstPlayer();
    if (rx(s, r'this character has no damage(?: on (?:him|her|them|it))?') != null) return const SelfState(damaged: false);
    if (s == 'it is at a location' || s == "it's at a location") return const SelfState(atLocation: true);
    var m = rx(s, r'this character has (\d+) (strength|willpower|lore) or (more|less)');
    if (m != null) return SelfStat(_stat(m[2]), m[3] == 'more' ? Cmp.ge : Cmp.le, int.parse(m[1]));
    if (s == "there's a card under this character" || rx(s, r'this character has a card under (?:him|her|it|them)') != null) return const SelfHasUnder();
    if (s == 'you have a character or location in play with a card under them') return const AnyWithUnder(Owner.yours);
    m = rx(s, r'you have (\d+) or (more|fewer) cards in your inkwell');
    if (m != null) return InkwellCond(Who.you, m[2] == 'more' ? Cmp.ge : Cmp.le, int.parse(m[1]));
    m = rx(s, r'you have more (items|characters|locations) in play than each (?:opponent|opposing player)');
    if (m != null) return MoreThanEachOpponent(Place.play, Filter(types: {m[1] == 'items' ? CardType.item : (m[1] == 'locations' ? CardType.location : CardType.character)}));
    m = rx(s, r'you have more cards in your (hand|inkwell) than each (?:opponent|opposing player)');
    if (m != null) return MoreThanEachOpponent(m[1] == 'hand' ? Place.hand : Place.inkwell);
    if (s == 'an opponent has no cards in their hand' || s == 'one or more opponents have no cards in their hands') return const HandCond(Who.opponents, Cmp.eq, 0);
    if (s == 'another character in play has damage' || s == 'another character in play is damaged') return const CountCond(Filter(damaged: true, other: true), Cmp.ge, 1, whose: Owner.any);
    if (s == 'you have a character in play with damage' || s == 'you have a damaged character in play') return const CountCond(Filter(damaged: true), Cmp.ge, 1);
    if (s == 'a damaged character is in play') return const CountCond(Filter(damaged: true), Cmp.ge, 1, whose: Owner.any);
    if (s == 'an opposing damaged character is in play') return const CountCond(Filter(damaged: true, owner: Owner.opposing), Cmp.ge, 1, whose: Owner.opposing);
    m = rx(s, r'there are (\d+) or more characters with damage in play');
    if (m != null) return CountCond(const Filter(damaged: true), Cmp.ge, int.parse(m[1]), whose: Owner.any);
    m = rx(s, r'(\d+) or more characters of yours are exerted');
    if (m != null) return CountCond(const Filter(exerted: true, owner: Owner.yours), Cmp.ge, int.parse(m[1]));
    m = rx(s, r'an? (.+?) character is in play');
    if (m != null) {
      final f = filter('${m[1]} character', Owner.any);
      if (f == null) return null;
      return CountCond(f, Cmp.ge, 1, whose: Owner.any);
    }
    // Locations: "if you have a character here", "while you have an exerted character here".
    m = rx(s, r'you have an? (.+?) here');
    if (m != null) {
      final f = filter(m[1], Owner.yours);
      if (f == null) return null;
      return CountCond(f.copyWith(atThisLocation: true), Cmp.ge, 1);
    }
    // "You have 2 or more other characters in play with 5 {s} or more".
    m = rx(s, r'you have (.+?) in play (with .+)');
    if (m != null) return condition('you have ${m[1]} ${m[2]} in play');
    if (s == 'being challenged' || s == 'this character is being challenged') return const BeingChallenged();
    m = rx(s, r'challenging an? (.+)');
    if (m != null) {
      final f = filter(m[1], Owner.any);
      if (f == null) return null;
      return Challenging(f);
    }
    m = rx(s, r'(\d+) or more cards were put into your discard this turn');
    if (m != null) return ThisTurnCond(TurnCount.putIntoDiscard, Cmp.ge, int.parse(m[1]));
    m = rx(s, r"you've played (\d+) or more actions this turn");
    if (m != null) return ThisTurnCond(TurnCount.actionsPlayed, Cmp.ge, int.parse(m[1]));
    if (s == 'no other character has quested this turn') return const ThisTurnCond(TurnCount.questedOthers, Cmp.eq, 0);
    m = rx(s, r'a character named (.+) was banished this turn');
    if (m != null) return BanishedThisTurn(Filter(named: m[1]));
    if (s == 'a character was banished this turn') return const BanishedThisTurn(Filter());
    if (s == 'an opposing character was banished in a challenge this turn') return const BanishedThisTurn(Filter(owner: Owner.opposing), inChallenge: true);
    m = rx(s, r'one of (your .+?) was banished this turn');
    if (m != null) {
      final f = _groupFilter(m[1]);
      if (f == null) return null;
      return BanishedThisTurn(f);
    }
    return null;
  }

  Filter? _moreGroup(String s) {
    var m = rx(s, r'(?:each|all) (.+)');
    if (m != null) return _groupFilter(m[1]);
    m = rx(s, r'(.+) at locations');
    if (m != null) return _groupFilter(m[1])?.copyWith(atLocation: true);
    return null;
  }

  CountOf? _moreCountOf(String s, int per) {
    if (s == 'card in your inkwell') return CountOf(const Filter(types: _allTypes), place: Place.inkwell, per: per);
    if (rx(s, r'exerted character (?:opponents|opposing players) have in play') != null) {
      return CountOf(const Filter(exerted: true, owner: Owner.opposing), whose: Owner.opposing, per: per);
    }
    return null;
  }

  /// "Prince, Princess, King, and Queen character", "Prince or King character".
  (CardType, List<String>)? _classList(String s) {
    final m = RegExp(r'^(.+) (character|item|location)s?$').firstMatch(s);
    if (m == null) return null;
    final words = [for (final w in m.group(1)!.split(RegExp(r',? and |,? or |, '))) w.trim()];
    if (words.length < 2 || !words.every(knownClassifications.contains)) return null;
    final type = switch (m.group(2)) {
      'item' => CardType.item,
      'location' => CardType.location,
      _ => CardType.character,
    };
    return (type, [for (final w in words) _cap(w)]);
  }
}
