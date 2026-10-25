part of 'parser.dart';

/// Effects on cards in decks, hands, discards and inkwells, and on what players know (CR 7):
/// looking at and revealing the top of a deck, naming a card, revealing hands, drawing and
/// discarding variants, the inkwell, cards from the discard, cards under others (Boost), and
/// paying ink as part of an effect. Hooked into [_CardParser.effects], `_span`, `clause` and
/// `condition`.
extension _Zones on _CardParser {
  static const _anyCard = Filter(types: {CardType.character, CardType.action, CardType.item, CardType.location});

  // -------------------------------------------------------------------------------------------
  // Whole effects (modes with a preamble)
  // -------------------------------------------------------------------------------------------

  /// "You may choose one: - A - B", "you may pay 2 ink to choose one: • A • B", "choose one of
  /// the following. If X, choose both instead: - A - B" (CR 6.1.5.2).
  Effect? _zoneEffects(String text, _Ctx ctx) {
    final m = RegExp(r'^(you may )?(?:pay (\d+) ink to )?choose one(?: of the following)?(?:\. if (.+?), choose both instead)?: ?([-•]) (.+)$').firstMatch(text);
    if (m == null) return null;
    final may = m.group(1) != null, pay = m.group(2), both = m.group(3), bullet = m.group(4)!;
    // The plain "choose one: - A. - B." form is the core parser's.
    if (!may && pay == null && both == null && bullet == '-') return null;
    final opts = m.group(5)!.split(bullet == '•' ? RegExp(r'\.? ?• ') : RegExp(r'\.? - ')).map((o) => o.trim().replaceAll(RegExp(r'\.$'), '')).where((o) => o.isNotEmpty).toList();
    if (opts.length < 2) return null;
    final effs = <Effect>[];
    for (final o in opts) {
      final e = effects(o, ctx);
      if (e == null) return null;
      effs.add(e);
    }
    Effect e = ChooseOne(effs, opts);
    if (both != null) {
      final c = condition(both);
      if (c == null) return null;
      e = If(c, Seq(effs), e);
    }
    if (pay != null) e = Seq([PayInk(int.parse(pay)), If(const DidIt(), e)]);
    return may ? May(e) : e;
  }

  // -------------------------------------------------------------------------------------------
  // Templates over several sentences
  // -------------------------------------------------------------------------------------------

  /// The sentence after "look at the top N cards of [who]'s deck": where they go.
  (Effect, int)? _lookTop(int n, Who who, String? next, String? next2) {
    if (next == null) return null;
    if (rx(next, r'put them back on the top of your deck in any order') != null) return (Peek(n, rest: ZoneDest.top), 2);
    // "Put one into your hand and the other on the bottom of your deck", "put 2 into your
    // hand and the rest…", "put one into your inkwell facedown and exerted and the other on
    // the top of your deck".
    final split = rx(next, r"put (one|\d+) (into your hand|on the top of (?:your|their) deck|into your inkwell facedown and exerted) and the (?:other|rest) (on the bottom of (?:your|their) deck|on the bottom|on the top of (?:your|their) deck|into your inkwell facedown and exerted)(?: in any order)?");
    if (split != null) {
      final count = numWord(split[1])!;
      return (Peek(n, who: who, picks: [PeekPick(count: count, optional: false, dest: _dest(split[2])!, exerted: split[2].contains('exerted'))], rest: _dest(split[3])!), 2);
    }
    // "You may put one into your hand. Put the rest on the bottom of your deck in any order."
    final putOne = rx(next, r'(you may )?put (one|\d+) into your hand');
    final rest = next2 == null ? null : _restDest(next2);
    if (putOne != null && rest != null) {
      return (Peek(n, picks: [PeekPick(count: numWord(putOne[2])!, optional: putOne[1].isNotEmpty)], rest: rest), 3);
    }
    // "You may reveal a character card and put it into your hand", "…up to 2 character cards
    // and up to 1 item card and put them into your hand", "…with cost 3 or less and play it
    // for free". Then the rest go somewhere.
    final picks = _revealPicks(next);
    if (picks != null && rest != null) return (Peek(n, picks: picks, rest: rest), 3);
    return null;
  }

  (Effect, int)? _zoneSpan(List<String> ss, int i, _Ctx ctx) {
    final s = ss[i];
    String? at(int k) => i + k < ss.length ? ss[i + k] : null;

    // "Look at the top N cards of your deck…" (CR 7.2).
    var m = rx(s, r"(?:you may )?look at the top (\d+) cards of (your|chosen player's) deck( and put them back in any order)?");
    if (m != null) {
      final n = int.parse(m[1]);
      final who = m[2] == 'your' ? Who.you : Who.chosenPlayer;
      if (m[3].isNotEmpty) return (Peek(n, who: who, rest: ZoneDest.top), 1);
      // "You may look at the top 2 cards…": the whole look is optional (CR 6.1.5.1).
      final r = _lookTop(n, who, at(1), at(2));
      return r == null ? null : (s.startsWith('you may ') ? May(r.$1) : r.$1, r.$2);
    }

    // "Look at the top card of your deck. Put it on either the top or the bottom of your deck."
    // "…If it's a puppy character card, you may reveal it and put it into your hand. Otherwise, …"
    m = rx(s, r"(?:you may )?look at the top card of (your|chosen player's|each opponent's) deck");
    if (m != null) {
      final who = m[1] == 'your' ? Who.you : (m[1] == "each opponent's" ? Who.opponents : Who.chosenPlayer);
      final next = at(1);
      if (next != null) {
        final put = rx(next, r'(?:you may )?put it on (?:either )?(?:the )?top (or the bottom of (?:your|their) deck|of (?:your|their) deck or into (?:your|their) discard)');
        if (put != null) return (Peek(1, who: who, rest: put[1].startsWith('or the bottom') ? ZoneDest.topOrBottom : ZoneDest.topOrDiscard), 2);
        final r = _revealFollowUp(ss, i + 1, who: who, reveal: false);
        if (r != null) return (r.$1, 1 + r.$2);
        if (RegExp(r'^(put it|if it|otherwise)').hasMatch(next)) return null;
      }
      // Only looking: the card stays where it is.
      return (Peek(1, who: who, rest: ZoneDest.top), 1);
    }

    // "Name a card, then reveal the top card of your deck. If it's the named card, …"
    m = rx(s, r'name a card, then reveal the top card of your deck');
    if (m != null) {
      final r = _revealFollowUp(ss, i + 1, named: true);
      if (r == null) return null;
      return (Seq([const NameCard(), r.$1]), 1 + r.$2);
    }
    // "Name a card. Return all character cards with that name from your discard to your hand."
    if (s == 'name a card' && at(1) != null) {
      final ret = rx(at(1)!, r'return all (.+?) with that name from your discard to your hand');
      if (ret != null) {
        final f = _zoneFilters(ret[1]);
        if (f == null || f.length != 1) return null;
        return (Seq([const NameCard(), FromDiscard(f.first, all: true, named: true)]), 2);
      }
    }
    // "Reveal the top card of your deck. If it's a X card, put it into your hand. Otherwise, …"
    m = rx(s, r"(you may )?reveal the top card of your deck|(each opponent|chosen opponent|chosen player) reveals the top card of their deck");
    if (m != null) {
      final who = m[2].isEmpty ? Who.you : (m[2] == 'each opponent' ? Who.opponents : (m[2] == 'chosen opponent' ? Who.chosenOpponent : Who.chosenPlayer));
      final r = _revealFollowUp(ss, i + 1, who: who);
      if (r == null) return null;
      final eff = m[1].isNotEmpty ? May(r.$1) : r.$1;
      return (eff, 1 + r.$2);
    }
    // "Each opponent may choose and discard a card. For each opponent who doesn't, you gain 2
    // lore."
    m = rx(s, r'each opponent may choose and discard a card');
    if (m != null && at(1) != null) {
      final lore = rx(at(1)!, r"for each opponent who doesn't, you gain (\d+) lore");
      if (lore != null) return (EachMay(Who.opponents, const Discard(Who.you, Fixed(1)), lorePerRefusal: int.parse(lore[1])), 2);
    }
    return null;
  }

  /// The sentences after "reveal the top card": "if it's a X card, (you may) put it into your
  /// hand / play it for free / put it into your inkwell…", "otherwise, put it on the bottom".
  (Peek, int)? _revealFollowUp(List<String> ss, int j, {Who who = Who.you, bool named = false, bool reveal = true}) {
    if (j >= ss.length) return null;
    final m = RegExp(r"^if (?:it's|that card is) (the named card|(?:a|an) .+?), (they may |you may )?(.+)$").firstMatch(ss[j]);
    if (m == null) return null;
    final what = m.group(1)!;
    final isNamed = what == 'the named card';
    if (isNamed != named) return null;
    List<Filter>? filters;
    if (!isNamed) {
      filters = _zoneFilters(what.replaceFirst(RegExp(r'^an? '), ''));
      if (filters == null) return null;
    }
    final optional = m.group(2) != null;
    final ownerDecides = m.group(2) == 'they may ' || who != Who.you;
    var action = m.group(3)!;
    Effect? then;
    final gain = RegExp(r'^(.+?) (?:and|to) gain (\d+) lore$').firstMatch(action);
    if (gain != null) {
      action = gain.group(1)!;
      then = GainLore(Who.you, Fixed(int.parse(gain.group(2)!)));
    }
    final dest = switch (action) {
      'put it into your hand' || 'put that card into your hand' || 'put it into their hand' || 'reveal it and put it into your hand' => ZoneDest.hand,
      'put it into your inkwell facedown and exerted' => ZoneDest.inkwell,
      _ when RegExp(r'^play (?:it|that character|that item|that card) for free(?: and (?:they|it) enters? play exerted)?$').hasMatch(action) => ZoneDest.play,
      _ => null,
    };
    if (dest == null) return null;
    final exerted = action.contains('exerted');
    var rest = ZoneDest.top;
    var used = 1;
    if (j + 1 < ss.length) {
      final o = RegExp(r'^otherwise, (?:they )?put it (?:on the (top|bottom) of (?:your|their) deck|on either the top or the bottom of your deck|into your discard)$').firstMatch(ss[j + 1]);
      if (o != null) {
        rest = switch (o.group(1)) {
          'top' => ZoneDest.top,
          'bottom' => ZoneDest.bottom,
          _ => ss[j + 1].contains('either') ? ZoneDest.topOrBottom : ZoneDest.discard,
        };
        used = 2;
      } else if (ss[j + 1].startsWith('otherwise')) {
        return null;
      }
    }
    return (
      Peek(1, who: who, reveal: reveal, ownerDecides: ownerDecides, picks: [PeekPick(filters: filters ?? const [], named: isNamed, optional: optional, dest: dest, exerted: exerted, then: then)], rest: rest),
      used,
    );
  }

  /// "you may reveal a X card and put it into your hand", "…up to 2 X cards and up to 1 Y card
  /// and put them into your hand", "…any number of X cards and put them in your hand", "…a X
  /// card with cost 3 or less and play it for free".
  List<PeekPick>? _revealPicks(String s) {
    final m = RegExp(r'^(you (?:may|my) )?reveal (.+?) and (put (?:it|them) (?:into|in) your hand|play it for free)$').firstMatch(s);
    if (m == null) return null;
    final optional = m.group(1) != null;
    final play = m.group(3) == 'play it for free';
    // Several "up to N X card(s)" parts ("up to 2 madrigal character card and up to 1 song card").
    final parts = m.group(2)!.split(RegExp(r' and (?=up to )'));
    final picks = <PeekPick>[];
    for (final part in parts) {
      final q = RegExp(r'^(up to (\d+)|any number of|a|an) (.+)$').firstMatch(part);
      if (q == null) return null;
      final filters = _zoneFilters(q.group(3)!);
      if (filters == null) return null;
      final anyNumber = q.group(1) == 'any number of';
      final count = q.group(2) != null ? int.parse(q.group(2)!) : 1;
      picks.add(PeekPick(filters: filters, count: count, anyNumber: anyNumber, optional: optional || anyNumber || q.group(2) != null, dest: play ? ZoneDest.play : ZoneDest.hand));
    }
    return picks;
  }

  ZoneDest? _restDest(String s) {
    final m = rx(s, r'put the rest (on the bottom of your deck|on the top of your deck|into your discard|in your discard)(?: in any order)?');
    if (m == null) return null;
    return m[1].contains('bottom') ? ZoneDest.bottom : (m[1].contains('top') ? ZoneDest.top : ZoneDest.discard);
  }

  ZoneDest? _dest(String s) {
    if (s.contains('hand')) return ZoneDest.hand;
    if (s.contains('inkwell')) return ZoneDest.inkwell;
    if (s.contains('bottom')) return ZoneDest.bottom;
    if (s.contains('top')) return ZoneDest.top;
    if (s.contains('discard')) return ZoneDest.discard;
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Card phrases
  // -------------------------------------------------------------------------------------------

  /// "character card with cost 3 or less", "song card", "non-character card or a character card
  /// named kevin", "princess or queen character card", "card": one or more alternatives (a card
  /// matching any of them).
  List<Filter>? _zoneFilters(String s0) {
    final w2 = _w2ZoneFilters(s0);
    if (w2 != null) return w2;
    var s = s0.trim();
    if (s.startsWith('a ')) s = s.substring(2);
    if (s.startsWith('an ')) s = s.substring(3);
    if (s == 'card' || s == 'cards') return [_anyCard];
    // "character, item, or location card with cost 6 or less": the tail applies to each.
    final list = RegExp(r'^([a-z]+), ([a-z]+),? or ([a-z]+) (cards?.*)$').firstMatch(s);
    if (list != null) {
      final out = <Filter>[];
      for (final w in [list.group(1), list.group(2), list.group(3)]) {
        final f = _oneFilter('$w ${list.group(4)}');
        if (f == null) return null;
        out.add(f);
      }
      return out;
    }
    // "princess or queen character card": classes share the type word.
    final shared = RegExp(r'^([a-z]+) or ([a-z]+) (character|item|location|action) cards?$').firstMatch(s);
    if (shared != null && knownClassifications.contains(shared.group(1)) && knownClassifications.contains(shared.group(2))) {
      final f = filter('${shared.group(1)} ${shared.group(3)}', Owner.any, cardTypes: true);
      final g = filter('${shared.group(2)} ${shared.group(3)}', Owner.any, cardTypes: true);
      if (f == null || g == null) return null;
      return [f, g];
    }
    final out = <Filter>[];
    for (final alt in s.split(RegExp(r' or (?:a |an )?(?=(?:non-)?[a-z\x27 ]*?(?:character|item|location|action|song|card)s?\b)'))) {
      final f = _oneFilter(alt.trim());
      if (f == null) return null;
      out.add(f);
    }
    return out.isEmpty ? null : out;
  }

  Filter? _oneFilter(String s0) {
    var s = s0;
    var notSong = false;
    var nonType = <CardType>{};
    final isnt = RegExp(r"^(.+?) that isn't a song card$").firstMatch(s);
    if (isnt != null) {
      s = isnt.group(1)!;
      notSong = true;
    }
    final non = RegExp(r'^non-(character|item|location|action) cards?$').firstMatch(s);
    if (non != null) {
      nonType = {CardType.values.firstWhere((t) => t.name == non.group(1))};
      return _anyCard.copyWith(types: {for (final t in _anyCard.types) if (!nonType.contains(t)) t});
    }
    // "character card with support": Filter.withKw (checked off the battlefield in game/zones).
    final kw = RegExp(r'^(.+?) with (support|evasive|ward|bodyguard|reckless|rush|challenger|resist|singer|shift|boost)$').firstMatch(s);
    Kw? withKw;
    if (kw != null) {
      s = kw.group(1)!;
      withKw = Kw.values.firstWhere((k) => k.name == kw.group(2));
    }
    var f = filter(_plural(s), Owner.any, cardTypes: true);
    if (f == null) return null;
    if (withKw != null) f = f.copyWith(withKw: withKw);
    if (notSong) f = f.copyWith(song: false);
    return f;
  }

  // -------------------------------------------------------------------------------------------
  // Single clauses
  // -------------------------------------------------------------------------------------------

  /// Tried after the core clauses, so templates they already know keep their meaning.
  Effect? _zoneClause(String c, _Ctx ctx) {
    List<String>? m;
    // Each player deciding for themselves (CR 6.1.4).
    m = rx(c, r'(each player|each opponent) may (draw a card|choose and discard a card)');
    if (m != null) return EachMay(m[1] == 'each player' ? Who.each : Who.opponents, m[2] == 'draw a card' ? const Draw(Who.you, Fixed(1)) : const Discard(Who.you, Fixed(1)));

    // Discarding.
    m = rx(c, r"(?:the challenging player|the challenging character's player) (?:chooses and )?discards (a|one|two|\d+) cards?");
    if (m != null) return Discard(Who.challenger, Fixed(numWord(m[1])!));
    m = rx(c, r"(the challenging character's player|each opponent|chosen opponent|each player) discards all cards in (?:their|his or her) hands?");
    if (m != null) return Discard(m[1].startsWith('the challenging') ? Who.challenger : _who(m[1]), const Fixed(0), all: true);
    if (c == 'discard your hand') return const Discard(Who.you, Fixed(0), all: true);
    m = rx(c, r'discard (a|one|two|\d+) cards? at random');
    if (m != null) return Discard(Who.you, Fixed(numWord(m[1])!), random: true);
    m = rx(c, r'(each player|each opponent|chosen opponent) discards (?:their|his or her) hands? and draws (a|one|two|three|four|five|six|seven|\d+) cards?');
    if (m != null) return Seq([Discard(_who(m[1]), const Fixed(0), all: true), Draw(_who(m[1]), Fixed(numWord(m[2])!))]);

    // Drawing up to a hand size (CR 6.1.8.1).
    m = rx(c, r'draw (?:cards )?until you have (\d+) cards in your hand');
    if (m != null) return Draw(Who.you, Fixed(int.parse(m[1])), untilHandSize: true);
    m = rx(c, r'each player with fewer than (\d+) cards in their hand draws until they have (\d+)');
    if (m != null && m[1] == m[2]) return Draw(Who.each, Fixed(int.parse(m[1])), untilHandSize: true);
    m = rx(c, r'draw cards until you have the same number');
    if (m != null) return const DrawToMatch(Who.chosenOpponent);

    // Hands (CR 7.3).
    m = rx(c, r"(chosen opponent|chosen player|each opponent) reveals (?:their|his or her) hand(?: and discards (?:a|an) (.+?) of your choice)?");
    if (m != null) {
      final who = m[1] == 'chosen player' ? Who.chosenPlayer : _who(m[1]);
      if (m[2].isEmpty) return RevealHand(who);
      final f = _zoneFilters(m[2]);
      if (f == null || f.length != 1) return null;
      return RevealHand(who, discard: f.first);
    }
    m = rx(c, r"look at (chosen opponent's|each opponent's|chosen player's) hand");
    if (m != null) return RevealHand(m[1].startsWith('chosen player') ? Who.chosenPlayer : (m[1].startsWith('each') ? Who.opponents : Who.chosenOpponent));

    // Inkwells (CR 7.5).
    m = rx(c, r'(each player|each opponent|you) puts? the top (\d+|card) cards? of (?:their|your) deck into (?:their|your) inkwell facedown( and exerted)?');
    if (m != null) return InkFromDeck(_who(m[1]), m[2] == 'card' ? 1 : int.parse(m[2]), exerted: m[3].isNotEmpty);
    m = rx(c, r'put the top (\d+) cards of your deck into your inkwell facedown( and exerted)?');
    if (m != null) return InkFromDeck(Who.you, int.parse(m[1]), exerted: m[2].isNotEmpty);

    // Cards under others (Boost, CR 8.4).
    if (c == 'put the top card of your deck facedown under one of your characters or locations with boost') {
      return const PutUnder(Filter(types: {CardType.character, CardType.location}, owner: Owner.yours, withKw: Kw.boost));
    }
    m = rx(c, r'put all cards from under (her|him|them|it|this character|this location) into your hand');
    if (m != null) {
      final t = ref(m[1], ctx);
      if (t == null) return null;
      return UnderTo(t, ZoneDest.hand);
    }
    m = rx(c, r"put all cards from under (chosen .+?) on the bottom of their player's deck in a random order");
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return UnderTo(t, ZoneDest.bottom, random: true);
    }

    // Paying ink as part of an effect ("pay 2 ink to draw a card", CR 6.1.5.1).
    m = rx(c, r'pay (\d+) ink');
    if (m != null) return PayInk(int.parse(m[1]));
    return null;
  }

  /// Tried before the core clauses: their broader "ready …" and "put … on the bottom of …"
  /// templates would claim these and then fail on the target.
  Effect? _zoneFirst(String c, _Ctx ctx) {
    List<String>? m;
    if (c == 'ready all cards in your inkwell') return const ReadyInkwell(Who.you);

    // Discards (CR 7.6).
    m = rx(c, r"(?:return|put) (all|a|an|another|up to \w+|\w+) (.+?) from (your|chosen player's|their) discard (?:to|into|on) (your hand|their hand|your inkwell facedown and exerted|your inkwell facedown|the bottom of (?:your|their) deck|the top of (?:your|their) deck)(?: in any order)?");
    if (m != null) {
      final q = m[1];
      final other = q == 'another';
      final all = q == 'all';
      final upTo = q.startsWith('up to');
      final count = all ? 0 : (upTo ? numWord(q.substring(6)) : (numWord(q) ?? (other ? 1 : null)));
      if (!all && count == null) return null;
      final fs = _zoneFilters(m[2]);
      if (fs == null || fs.length != 1) return null;
      final who = m[3] == 'your' ? Who.you : Who.chosenPlayer;
      final dest = _dest(m[4])!;
      return FromDiscard(other ? fs.first.copyWith(other: true) : fs.first, who: who, all: all, count: count ?? 0, upTo: upTo, dest: dest, exerted: m[4].contains('exerted'));
    }
    m = rx(c, r'(each player shuffles|shuffle) all (.+?) from (?:their|your) discard into (?:their|your) deck');
    if (m != null) {
      final fs = _zoneFilters(m[2]);
      if (fs == null || fs.length != 1) return null;
      return FromDiscard(fs.first, who: m[1] == 'shuffle' ? Who.you : Who.each, all: true, dest: ZoneDest.shuffle);
    }
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Conditions
  // -------------------------------------------------------------------------------------------

  Cond? _zoneCondition(String s) {
    var m = rx(s, r'(an opponent|chosen opponent|each opponent) has more cards in (?:their|his or her) (hand|inkwell) than you');
    if (m != null) return CompareZone(m[1] == 'chosen opponent' ? Who.chosenOpponent : Who.opponents, m[2] == 'hand' ? Place.hand : Place.inkwell, Cmp.gt);
    if (rx(s, r"there's a card under (?:this character|this location|her|him|it|them)") != null) return const HasUnder();
    m = rx(s, r'you have (\d+) or more (.+?) in your discard');
    if (m != null) {
      final fs = _zoneFilters(m[2]);
      if (fs == null || fs.length != 1) return null;
      return CountCond(fs.first, Cmp.ge, int.parse(m[1]), place: Place.discard);
    }
    return null;
  }
}
