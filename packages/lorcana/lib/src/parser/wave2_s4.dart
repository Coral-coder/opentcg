part of 'parser.dart';

/// Wave 2, slice 4 (Scrooge … Zipper): templates hooked into the core grammar with one-line
/// calls. Each hook returns null (or false) to let the grammar go on as before.
extension _S4 on _CardParser {
  static const _anyCard = Filter(types: {CardType.character, CardType.action, CardType.item, CardType.location});
  static const _stats = r'(strength|willpower|lore)';

  // -------------------------------------------------------------------------------------------
  // Whole paragraphs
  // -------------------------------------------------------------------------------------------

  /// Triggered-looking paragraphs: "the first time …" (CR 6.2.2), "twice during your turn,
  /// whenever …", "while this character is at a location, whenever …", start-of-turn abilities
  /// that work from the discard (CR 6.1.12), and "once per turn, you may …" (an ability with no
  /// cost, used once a turn).
  List<Ability>? _s4Triggered(String printed, String t) {
    var m = rx(t, r'(during your turn, )?the first time (.+?)( each turn)?, (.+)');
    if (m != null) {
      final head = m[2].startsWith('you ') || m[2].startsWith('a ') || m[2].startsWith('an ') ? 'whenever ${m[2]}' : null;
      if (head == null) return null;
      return _triggered(printed, '${m[1].isEmpty ? 'once per turn' : 'once during your turn'}, $head, ${m[4]}');
    }
    m = rx(t, r'twice during your turn, (.+)');
    if (m != null) {
      final inner = _triggered(printed, 'during your turn, ${m[1]}');
      if (inner == null) return null;
      final key = 900 + abilities.length;
      return [
        for (final a in inner)
          if (a is Triggered) Triggered(a.text, a.trigger, LimitPerTurn(2, key, a.effect), condition: a.condition, during: a.during, oncePerTurn: a.oncePerTurn, fromDiscard: a.fromDiscard) else a,
      ];
    }
    m = rx(t, r'while this character is at a location, ((?:when|whenever) [^,]+), (.+)');
    if (m != null) return _triggered(printed, '${m[1]} while at a location, ${m[2]}');
    m = rx(t, r'at the start of your turn, if this card is in your discard, (.+)');
    if (m != null) {
      final e = effects(m[1], _Ctx());
      if (e == null) return null;
      return [Triggered(printed, const TurnStep(start: true), e, condition: const SourceIn(Place.discard), fromDiscard: true)];
    }
    m = rx(t, r'once per turn, you may (.+)');
    if (m != null && !RegExp(r'^(when|whenever) ').hasMatch(m[1])) {
      final e = effects(m[1], _Ctx());
      if (e == null) return null;
      return [Activated(printed, const Cost(oncePerTurn: true), e)];
    }
    return null;
  }

  /// An action whose first sentence is a cost reduction for itself (CR 4.3.6): "For each
  /// Sorcerer character you have in play, you pay 1 {i} less to play this action. Draw 2 cards."
  List<Ability>? _s4Action(Paragraph p) {
    final ss = _sentences(_lower(p.body));
    if (ss.length < 2 || !RegExp(r'you pay \d+ ink less to play this (?:action|song)').hasMatch(ss.first)) return null;
    final st = _staticEffect(ss.first);
    if (st == null || st.length != 1 || st.first is! CostReduction) return null;
    final e = effects(ss.skip(1).join('. '), _Ctx());
    if (e == null) return null;
    return [Static(p.printed, st.first, inHand: true), ActionEffect(p.printed, e)];
  }

  // -------------------------------------------------------------------------------------------
  // Costs (CR 1.5, 6.3)
  // -------------------------------------------------------------------------------------------

  /// Costs with parts the core cost grammar lacks: "deal 1 damage to this character", "choose
  /// and discard a character card".
  Cost? _s4Cost(String s) {
    final parts = s.split(', ');
    var damage = 0;
    List<Filter>? discards;
    final rest = <String>[];
    for (final part in parts) {
      final p = part.trim();
      final d = rx(p, r'deal (\d+) damage to this character');
      if (d != null) {
        damage = int.parse(d[1]);
        continue;
      }
      final c = rx(p, r'choose and discard (an? .+? card)');
      if (c != null && c[1] != 'a card') {
        final fs = _zoneFilters(c[1]);
        if (fs == null) return null;
        discards = fs;
        continue;
      }
      rest.add(p);
    }
    if (damage == 0 && discards == null) return null;
    final base = rest.isEmpty ? const Cost() : _cost(rest.join(', '));
    if (base == null) return null;
    return Cost(
      exert: base.exert,
      ink: base.ink,
      banishSelf: base.banishSelf,
      discard: base.discard,
      exertOther: base.exertOther,
      banishOther: base.banishOther,
      damageSelf: damage,
      discardFilters: discards,
    );
  }

  // -------------------------------------------------------------------------------------------
  // Triggers (CR 6.2.1)
  // -------------------------------------------------------------------------------------------

  _Head? _s4TriggerHead(String h) {
    _Head one(Trigger t) => [(t, null, false)];
    if (rx(h, r'when(?:ever)? you move a character here from (?:a|another) location') != null) return one(const MovedHereFromLocation());
    var m = rx(h, r'whenever you move (?:a|an) (.+?) here');
    if (m != null && m[1] != 'character') {
      final f = filter(m[1], Owner.yours);
      return f == null ? null : one(CardEvent(Event.movesToLocation, subject: f, here: true));
    }
    m = rx(h, r'(?:when|whenever) (?:a|an) (.+?) moves here');
    if (m != null && m[1] != 'character') {
      final f = filter(m[1], Owner.any);
      return f == null ? null : one(CardEvent(Event.movesToLocation, subject: f, here: true));
    }
    m = rx(h, r'whenever you play this character or another (.+)');
    if (m != null) {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      return f == null ? null : [(const OnPlay(), null, false), (CardPlayed(f.copyWith(other: true)), null, false)];
    }
    if (h == "whenever this character is chosen for an action or an item's ability") return one(const ChosenFor({CardType.action, CardType.item}));
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Statics (CR 6.4)
  // -------------------------------------------------------------------------------------------

  List<StaticEffect>? _s4StaticEffect(String t) {
    var m = rx(t, r'(.+?) may move here for free');
    if (m != null) {
      final f = _groupFilter(m[1]);
      return f == null ? null : [MovesHereFree(f)];
    }
    m = rx(t, r'you may exert (\d+|two|three|four|five) (.+?) of yours to play this character for free');
    if (m != null) {
      final f = filter(_plural(m[2]), Owner.yours, cardTypes: true);
      final n = numWord(m[1]);
      return f == null || n == null ? null : [AltCostExert(f, n)];
    }
    m = rx(t, r'you may only have (\d+) copies of .+ in your deck');
    if (m != null) return [DeckLimit(int.parse(m[1]))];
    m = rx(t, r'you may play (.+?) from your discard(\. if you do, they enter play exerted)?');
    if (m != null) {
      final f = _groupFilter(m[1]);
      return f == null ? null : [PlayFromDiscard(f, exerted: m[2].isNotEmpty)];
    }
    m = rx(t, r'you may play (.+?) for free');
    if (m != null && !m[1].startsWith('this ')) {
      final f = _groupFilter(m[1]);
      return f == null ? null : [CostReduction(f.copyWith(owner: Owner.yours), const Fixed(99))];
    }
    m = rx(t, r'you pay (\d+) ink less to play (.+?) using their shift ability');
    if (m != null) {
      final f = _groupFilter(m[2]);
      return f == null ? null : [ShiftCostLess(f, int.parse(m[1]))];
    }
    m = rx(t, r'(.+?) gains? the ([a-z]+) classification');
    if (m != null && knownClassifications.contains(m[2])) {
      final f = _groupFilter(m[1]);
      return f == null ? null : [GainClass(f, _cap(m[2]))];
    }
    if (t == "opponents can't play actions") return const [OpponentsCantPlay(Filter(types: {CardType.action}))];
    if (t == "damage counters can't be removed") return const [NoDamageRemoval()];
    return null;
  }

  /// Predicates: two stats "for each" card under or character here, ink types, Resist "for
  /// each", and granted activated abilities ("gain Ward and "{e}, 1 {i} - …"").
  List<StaticEffect>? _s4Predicate(String p, Filter? f) {
    var m = rx(p, 'gets? ([+-])(\\d+) $_stats(?: and ([+-])(\\d+) $_stats)? for each (.+)');
    if (m != null) {
      Amount? amt(int n) {
        final each = m![7];
        if (each == 'card in your hand') return null;
        if (RegExp(r'^card under (?:him|her|it|them)$').hasMatch(each) && f == null) return UnderSelf(times: n);
        if (each == 'different ink type of characters you have in play') return InkTypes(const Filter(owner: Owner.yours));
        final c = _s4CountOf(each, n);
        return c;
      }

      final a = amt(int.parse(m[2]));
      if (a == null) return null;
      if (a is InkTypes && m[2] != '1') return null;
      final out = <StaticEffect>[StaticMod(f, _stat(m[3]), a, negative: m[1] == '-')];
      if (m[4].isNotEmpty) {
        final b = amt(int.parse(m[5]));
        if (b == null || (b is InkTypes && m[5] != '1')) return null;
        out.add(StaticMod(f, _stat(m[6]), b, negative: m[4] == '-'));
      }
      return out;
    }
    m = rx(p, r'gains? (resist|challenger) \+(\d+) for each (.+)');
    if (m != null) {
      final c = countOf(m[3], per: int.parse(m[2]));
      return c == null ? null : [KeywordPerCount(f, m[1] == 'resist' ? Kw.resist : Kw.challenger, c)];
    }
    m = rx(p, r'gains? (?:(.+?) and )?"(.+)"');
    if (m != null) {
      final ab = _s4QuotedAbility(m[2]);
      if (ab == null) return null;
      final kws = m[1].isEmpty ? const <Keyword>[] : _keywordList(m[1]);
      if (kws == null) return null;
      return [for (final k in kws) StaticKeyword(f, k), GrantAbility(f, ab)];
    }
    return null;
  }

  /// A quoted activated ability ("{e}, 1 ink - deal 2 damage to chosen damaged character").
  Activated? _s4QuotedAbility(String q0) {
    final q = q0.trim();
    final dash = q.indexOf(' - ');
    if (dash < 0) return null;
    final cost = _cost(q.substring(0, dash));
    if (cost == null) return null;
    final e = effects(q.substring(dash + 3), _Ctx());
    if (e == null) return null;
    return Activated(q, cost, e);
  }

  /// "Character here", "character you have here", "card in your hand".
  CountOf? _s4CountOf(String s, int per) {
    if (rx(s, r'characters? here') != null) return CountOf(const Filter(atThisLocation: true), whose: Owner.any, per: per);
    if (rx(s, r'characters? you have here') != null) return CountOf(const Filter(owner: Owner.yours, atThisLocation: true), per: per);
    if (s == 'card in your hand') return CountOf(_anyCard, place: Place.hand, per: per);
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Conditions
  // -------------------------------------------------------------------------------------------

  Cond? _s4Condition(String s) {
    if (s == 'all cards in your inkwell are exerted') return const S4AllInkExerted();
    if (s == 'you played a song this turn') return const TurnStatCond(TurnStat.songsPlayed, Who.you, Cmp.ge, 1);
    var m = rx(s, r'you played (?:a|an) (.+?) this turn');
    if (m != null && m[1] != 'character' && m[1] != 'song') {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      return f == null ? null : PlayedThisTurn(f);
    }
    if (s == 'an opponent has more lore than you') return const S4OpponentMoreLore();
    if (s == 'an opponent has more characters in play than you') return const OpponentMoreCharacters();
    if (s == 'a character sang this song') return const SangThisSong();
    if (rx(s, r'you put a card under (?:him|her|them|it|this character) this turn') != null) return const PutUnderSelfThisTurn();
    m = rx(s, r"(\d+) or more cards have left a player's discard this turn");
    if (m != null) return LeftDiscardThisTurn(int.parse(m[1]));
    m = rx(s, r'you have fewer than (\d+) cards in your hand');
    if (m != null) return HandCond(Who.you, Cmp.lt, int.parse(m[1]));
    if (s == 'an opposing character has damage') return const CountCond(Filter(owner: Owner.opposing, damaged: true), Cmp.ge, 1, whose: Owner.opposing);
    if (s == 'you have a character in play with more strength than each opposing character in play') return const StrongestCond();
    if (s == 'there was an exerted character here') return const ExertedHereWhenBanished();
    if (s == 'any of the cards that were under them are character cards') return const EventUnderHas(Filter());
    m = rx(s, r'the challenging character has (\d+) strength or more');
    if (m != null) return TargetIs(const EventCard(), Filter(strengthMin: int.parse(m[1])));
    m = rx(s, r'the moved character is (?:a|an) (.+)');
    if (m != null) {
      final f = filter(m[1].contains(' ') ? m[1] : '${m[1]} character', Owner.any);
      return f == null ? null : TargetIs(const EventCard(), f);
    }
    return null;
  }

  /// Tried after every other condition: "this character is exerted and you have no cards in
  /// your hand".
  Cond? _s4ConditionLast(String s) {
    final and = s.indexOf(' and ');
    if (and > 0) {
      final a = condition(s.substring(0, and)), b = a == null ? null : condition(s.substring(and + 5));
      if (a != null && b != null) return AllConds([a, b]);
    }
    return null;
  }

  /// Conditions about a card chosen or moved earlier in the same ability.
  Cond? _s4IfTarget(String s, _Ctx ctx) {
    final slot = ctx.nextSlot - 1;
    var m = rx(s, r'you returned (?:a|an) (.+?) this way');
    if (m != null && slot >= 0) {
      final f = filter(m[1], Owner.any);
      return f == null ? null : SlotWas(slot, f);
    }
    m = rx(s, r"(?:they're|he's|she's|they are|he is|she is) (?:a|an) (.+)");
    if (m != null) {
      final t = ref('they', ctx);
      final f = filter(m[1], Owner.any);
      return t == null || f == null ? null : TargetIs(t, f);
    }
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // References and filters
  // -------------------------------------------------------------------------------------------

  Target? _s4Ref(String p, _Ctx ctx) {
    if (const {'those characters', 'the other character'}.contains(p) && ctx.nextSlot > 0) return Remembered(ctx.nextSlot - 1);
    if (p == 'the challenging character' && ctx.s4Challenged) return const EventCard(other: true);
    return null;
  }

  Target? _s4Target(String p, _Ctx ctx) {
    if (p.endsWith(' each') && p.contains('chosen ')) return target(p.substring(0, p.length - 5), ctx);
    var m = rx(p, r'(?:each|all) (opposing |your )?characters? and (?:each )?(?:opposing |your )?locations?');
    if (m != null) return AllOf(Filter(types: const {CardType.character, CardType.location}, owner: _owner(m[1])));
    m = rx(p, r'your characters and locations');
    if (m != null) return const AllOf(Filter(types: {CardType.character, CardType.location}, owner: Owner.yours));
    m = rx(p, r'each (opposing |your )?character with (evasive|ward|bodyguard|rush|reckless|support) and each (?:opposing |your )?location with \2');
    if (m != null) return AllOf(Filter(types: const {CardType.character, CardType.location}, owner: _owner(m[1]), withKw: Kw.values.firstWhere((k) => k.name == m![2])));
    return null;
  }

  Owner _owner(String s) => switch (s.trim()) {
    'opposing' => Owner.opposing,
    'your' => Owner.yours,
    _ => Owner.any,
  };

  /// Filter suffixes: "here", "with a card under them", "without Evasive", "with 0 strength",
  /// "with Bodyguard or item"; and a bare classification ("chosen Villain of yours").
  Filter? _s4Filter(String s, Owner owner, bool cardTypes, bool chosenPhrase) {
    Filter? inner(String x) => filter(x, owner, cardTypes: cardTypes, chosenPhrase: chosenPhrase);
    // "Here" is this location, or on a character the location it's at.
    var m = rx(s, r'(.+?) here');
    if (m != null && !m[1].endsWith(' you have')) return card.type == CardType.location ? inner(m[1])?.copyWith(atThisLocation: true) : inner(m[1])?.copyWith(atSourcesLocation: true);
    m = rx(s, r'(.+?) with a card under (?:them|him|her|it)');
    if (m != null) return inner(m[1])?.copyWith(hasUnder: true);
    m = rx(s, r'(.+?) without (evasive|ward|bodyguard|reckless|rush|support|challenger|resist|singer)');
    if (m != null) return inner(m[1])?.copyWith(withoutKw: Kw.values.firstWhere((k) => k.name == m![2]));
    m = rx(s, r'(.+?) with 0 strength');
    if (m != null) return inner(m[1])?.copyWith(strengthMax: 0);
    m = rx(s, r'(.+? with [a-z]+) or (item|location)');
    if (m != null) {
      final a = inner(m[1]), b = inner(m[2]);
      return a == null || b == null ? null : a.copyWith(or: b);
    }
    m = rx(s, r'([a-z]+)( of yours)?');
    if (m != null && m[1] != 'song' && knownClassifications.contains(m[1])) return inner('${m[1]} character${m[2]}');
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Effects
  // -------------------------------------------------------------------------------------------

  /// "If X, Y instead" where Y names no target ("deal 2 damage instead", "remove up to 4 damage
  /// instead"), and "if that character had a card under them, … instead" (CR 6.5.7).
  bool _s4Instead(String s, List<Effect> steps, _Ctx ctx) {
    final m = RegExp(r'^if (.+?), (.+) instead$').firstMatch(s);
    if (m == null || steps.isEmpty) return false;
    final prev = steps.last;
    final x = m.group(1)!, y = m.group(2)!;
    if (RegExp(r'^that character had a card under (?:them|him|her)$').hasMatch(x)) {
      if (prev is! Seq || prev.steps.length != 2 || prev.steps.first is! Banish || prev.steps.last is! If) return false;
      final ban = prev.steps.first as Banish, then = prev.steps.last as If;
      final e = sentence(y, ctx);
      if (e == null) return false;
      steps.removeLast();
      steps.add(Seq([ChooseNow(ban.target), ban, If(then.cond, If(const NotedCond('under', Cmp.ge, 1), e, then.then))]));
      return true;
    }
    final dmg = rx(y, r'(deal|remove up to) (\d+) damage');
    if (dmg == null) return false;
    final c = condition(x) ?? _ifTarget(x, ctx);
    if (c == null) return false;
    final n = Fixed(int.parse(dmg[2]));
    Effect? swap(Effect e) => switch (e) {
      DealDamage(:final target, :final amount, :final put) when dmg[1] == 'deal' => If(c, DealDamage(target, n, put: put), DealDamage(target, amount, put: put)),
      RemoveDamage(:final target, :final amount) when dmg[1] != 'deal' => If(c, RemoveDamage(target, n), RemoveDamage(target, amount)),
      May(e: final inner) => switch (swap(inner)) {
        null => null,
        final Effect x => May(x),
      },
      _ => null,
    };
    final out = swap(prev);
    if (out == null) return false;
    steps.removeLast();
    steps.add(out);
    return true;
  }

  /// Templates over several sentences.
  (Effect, int)? _s4Span(List<String> ss, int i, _Ctx ctx) {
    final s = ss[i];
    String? at(int k) => i + k < ss.length ? ss[i + k] : null;
    // Sisu.
    if (s == 'reveal the top card of your deck' && at(2) != null) {
      final m = rx(at(1)!, r"if it's (?:a|an) (.+?), put it into your hand and repeat this effect");
      if (m != null && at(2) == 'otherwise, put it on either the top or the bottom of your deck') {
        final fs = _zoneFilters(m[1]);
        return fs == null ? null : (RevealRepeat(fs), 3);
      }
    }
    // The Boss Is On A Roll.
    var m = rx(s, r'look at the top (\d+) cards of your deck');
    if (m != null && at(1) == 'put any number of them on the top or the bottom of your deck in any order') return (PeekSplit(int.parse(m[1])), 2);
    // The Queen - Diviner.
    if (m != null &&
        at(1) == 'you may reveal an item card and put it into your hand' &&
        at(3) == 'put the rest on the bottom of your deck in any order') {
      final c = rx(at(2)!, r'if that item costs (\d+) or less, you may play it for free instead and it enters play exerted');
      if (c != null) return (PeekItemOrPlay(int.parse(m[1]), int.parse(c[1])), 4);
    }
    // Searching (The Glass Slipper, The Islands I Pulled from the Sea, Yzma - On Edge).
    m = rx(s, r'(you may )?search your deck for (.+?)(?:,)? (?:and )?reveal (?:it|that card) to all players(?:, and put it into your hand)?');
    if (m != null) {
      final fs = _zoneFilters(m[2]);
      if (fs == null) return null;
      final next = at(1);
      final into = s.endsWith('put it into your hand');
      final used = into ? (next == 'then, shuffle your deck' ? 2 : 0) : (next == 'put that card into your hand and shuffle your deck' ? 2 : 0);
      if (used == 0) return null;
      final e = SearchDeck(fs);
      return (m[1].isEmpty ? e : May(e), used);
    }
    // The Queen - Jealous Beauty.
    m = rx(s, r"choose (\d+) cards from chosen opponent's discard and put them on the bottom of their deck to gain (\d+) lore");
    if (m != null && at(1) != null) {
      final r = rx(at(1)!, r'if any ([a-z]+) cards were moved this way, gain (\d+) lore instead');
      if (r != null) return (DiscardToBottomForLore(int.parse(m[1]), int.parse(m[2]), _cap(r[1]), int.parse(r[2])), 2);
    }
    // Ursula - Power Hungry.
    m = rx(s, r'each opponent loses (\d+) lore');
    if (m != null && at(1) == 'you may draw a card for each 1 lore lost this way') {
      return (Seq([LoseLoreCounted(Who.opponents, Fixed(int.parse(m[1]))), const May(Draw(Who.you, Noted('lost')))]), 2);
    }
    // Ursula's Trickery.
    if (s == 'each opponent may choose and discard a card' && at(1) == "for each opponent who doesn't, you draw a card") {
      return (const EachMayElse(Who.opponents, Discard(Who.you, Fixed(1)), Draw(Who.you, Fixed(1))), 2);
    }
    // We Know The Way.
    if (s == 'shuffle chosen card from your discard into your deck' &&
        at(1) == 'reveal the top card of your deck' &&
        at(2) == 'if it has the same name as the chosen card, you may play the revealed card for free' &&
        at(3) == 'otherwise, put it into your hand') {
      return (const ShuffleRevealSameName(), 4);
    }
    // Widow Tweed, Wreck-It Ralph - Admiral Underpants.
    m = rx(s, r'return (?:a|an) (.+?) card from your discard to your hand');
    if (m != null && at(1) != null) {
      final r = rx(at(1)!, r'if that (?:character|card) is (named .+?|(?:a|an) .+? card), (.+)');
      final f = filter(m[1], Owner.yours, cardTypes: true);
      if (r != null && f != null) {
        final slot = ctx.nextSlot++;
        final what = r[1].startsWith('named ') ? Filter(types: _anyCard.types, named: r[1].substring(6)) : filter(r[1].replaceFirst(RegExp(r'^an? '), ''), Owner.any, cardTypes: true);
        final then = r[2] == 'you may play him for free' || r[2] == 'you may play her for free' ? May(PlaySlotFree(slot)) : sentence(r[2], ctx);
        if (what == null || then == null) return null;
        return (Seq([ReturnFromDiscardAs(f, slot), If(SlotWas(slot, what), then)]), 2);
      }
    }
    // The Magic Feather.
    m = rx(s, r'choose (?:a|an) (.+)');
    if (m != null && at(1) != null) {
      final r = rx(at(1)!, r'while this item is in play, that character gains (.+)');
      final f = filter(m[1], Owner.any);
      final kws = r == null ? null : _keywordList(r[1]);
      if (f != null && kws != null && kws.length == 1) return (GrantWhileInPlay(Chosen(f, slot: ctx.nextSlot++, word: false), kws.first), 2);
    }
    // Zero to Hero.
    if (s == 'count the number of characters you have in play' && at(1) == 'you pay that amount of ink less for the next character you play this turn') {
      return (const NextCostReductionBy(Filter(owner: Owner.yours), CountOf(Filter(owner: Owner.yours))), 2);
    }
    return null;
  }

  /// Single clauses, tried before the core grammar (whose broader templates would claim some of
  /// these and fail).
  Effect? _s4Clause(String c, _Ctx ctx) {
    List<String>? m;
    // Sequential "[A] to [B]" with verbs the core list lacks (CR 6.1.5.1).
    m = rx(c, r'(.+?) to ((?:discard|pay|move) .+)');
    if (m != null && !m[1].startsWith('move ')) {
      final save = ctx.save();
      final a = clause(m[1], ctx);
      final b = a == null ? null : _clauses(m[2], ctx);
      if (a != null && b != null) return Seq([a, If(const DidIt(), b)]);
      ctx.restore(save);
    }
    // "Ready all other characters here, they can't quest for the rest of this turn": "they" are
    // the readied ones.
    m = rx(c, r"ready (all .+?), they can't quest for the rest of this turn");
    if (m != null) {
      final t = target(m[1], ctx);
      return t is AllOf ? Seq([Ready(t), GrantRule(t, Rule.cantQuest, Lasting.thisTurn)]) : null;
    }
    m = rx(c, r'for the rest of this turn, ((?:when|whenever) .+)');
    if (m != null) return sentence('this turn, ${m[1]}', ctx);
    m = rx(c, r'until the start of your next turn, (.+?) can.t challenge and must quest if able');
    if (m != null) {
      final t = target(m[1], ctx);
      return t == null ? null : Seq([GrantRule(t, Rule.cantChallenge, Lasting.untilYourNextTurn), GrantRule(t, Rule.mustQuest, Lasting.untilYourNextTurn)]);
    }

    // Players.
    if (c == 'each player may reveal a character card from their hand and play it for free') return const EachMay(Who.each, PlayFree(Filter()));
    if (c == 'the player or players with the most cards in their hands choose and discard 2 cards') return const DiscardMost(2);
    m = rx(c, r'chosen player draws (a|one|two|three|four|five|\d+) cards?');
    if (m != null) return Draw(Who.chosenPlayer, Fixed(numWord(m[1])!));
    if (c == 'chosen player draws a card for each different ink type of characters you have in play') return const Draw(Who.chosenPlayer, InkTypes(Filter(owner: Owner.yours)));
    m = rx(c, r'(each opponent|each player|chosen opponent) gains? (\d+) lore');
    if (m != null) return GainLore(_who(m[1]), Fixed(int.parse(m[2])));
    m = rx(c, r'(each opponent|each player|that player) puts? the top card of their deck into their inkwell facedown( and exerted)?');
    if (m != null) return InkFromDeck(_who(m[1]), 1, exerted: m[2].isNotEmpty);
    m = rx(c, r'(each player|each opponent) draws (\d+) cards, then discards (\d+) cards at random');
    if (m != null) return DrawThenDiscardRandom(_who(m[1]), int.parse(m[2]), int.parse(m[3]));
    m = rx(c, r'(each opponent) loses (\d+) lore and you gain lore equal to the lore lost');
    if (m != null) return Seq([LoseLoreCounted(_who(m[1]), Fixed(int.parse(m[2]))), const GainLore(Who.you, Noted('lost'))]);
    if (c == 'chosen opponent chooses 3 of their characters and returns one of those cards to their hand, puts one on the bottom of their deck, and puts one on the top of their deck') {
      return const ScatterThree();
    }

    // Discarding.
    m = rx(c, r'choose and discard (an? .+?)(?: from your hand)?');
    if (m != null && m[1] != 'a card') {
      if (m[1] == 'a card with {iw}') return const DiscardMatching([], inkable: true);
      final fs = _zoneFilters(m[1]);
      if (fs != null) return DiscardMatching(fs);
    }

    // Lore and cards.
    m = rx(c, r'(?:you )?gain lore equal to the number of (.+)');
    if (m != null) {
      final a = countOf(m[1]);
      return a == null ? null : GainLore(Who.you, a);
    }
    if (c == "gain lore equal to the discarded character's lore") return const GainLore(Who.you, Noted('discardedLore'));
    m = rx(c, r'(?:you )?gain (\d+) lore for each (\d+) damage on (?:him|her|them|it|this character)');
    if (m != null) return GainLore(Who.you, DamageOnSelf(per: int.parse(m[2]), times: int.parse(m[1])));
    m = rx(c, r'(?:you )?draw a card for each (.+?), then choose and discard that many cards');
    if (m != null) {
      final a = countOf(m[1]);
      return a == null ? null : Seq([Draw(Who.you, a), Discard(Who.you, a)]);
    }
    m = rx(c, r'for each (.+?), you may draw a card');
    if (m != null) {
      final a = countOf(m[1]);
      return a == null ? null : MayDrawUpTo(a);
    }
    if (c == "draw cards equal to that location's lore" && ctx.nextSlot > 0) return Draw(Who.you, LocationLoreOf(Remembered(ctx.nextSlot - 1)));

    // Damage.
    m = rx(c, r'deal (him|her|them|it) (\d+) damage');
    if (m != null) {
      final t = ref(m[1], ctx);
      return t == null ? null : DealDamage(t, Fixed(int.parse(m[2])));
    }
    m = rx(c, r'choose (?:a|an) (.+?) and deal (\d+) damage to (?:them|him|her|it) for each action card discarded this way');
    if (m != null) {
      final f = filter(m[1], Owner.any);
      return f == null ? null : DealDamage(Chosen(f, slot: ctx.nextSlot++), Noted('actions', per: int.parse(m[2])));
    }
    m = rx(c, r'(.+?) gets? \+(\d+) strength this turn for each (\d+) damage on (?:them|him|her|it)');
    if (m != null && m[2] == '1' && m[3] == '1') {
      final t = target(m[1], ctx);
      if (t is Chosen) return Modify(t, Stat.strength, DamageOn(Remembered(t.slot)), Lasting.thisTurn);
      if (t is This) return const Modify(This(), Stat.strength, DamageOnSelf(), Lasting.thisTurn);
      return null;
    }
    m = rx(c, r'(?:he|she|they|this character) gets? \+ ?strength equal to the strength of (chosen .+?) this turn');
    if (m != null) {
      final t = target(m[1], ctx);
      if (t is! Chosen) return null;
      return Seq([ChooseNow(t), Modify(const This(), Stat.strength, StatOf(Remembered(t.slot), Stat.strength), Lasting.thisTurn)]);
    }
    m = rx(c, 'add (?:his|her|their|its) $_stats to (another chosen .+?)\'s? $_stats this turn');
    if (m != null) {
      final t = target(m[2], ctx);
      return t == null ? null : Modify(t, _stat(m[3]), StatOf(const This(), _stat(m[1])), Lasting.thisTurn);
    }
    m = rx(c, r'(.+?) gets? \+(\d+) strength this turn for each card in your hand');
    if (m != null) {
      final t = target(m[1], ctx);
      return t == null ? null : Modify(t, Stat.strength, CountOf(_anyCard, place: Place.hand, per: int.parse(m[2])), Lasting.thisTurn);
    }

    // "Unless their player pays N {i}" (CR 6.1.16).
    m = rx(c, r'(.+) unless their player pays (\d+) ink');
    if (m != null) {
      final save = ctx.save();
      final e = clause(m[1], ctx);
      if (e == null) {
        ctx.restore(save);
        return null;
      }
      final payer = e is Modify ? e.target : const EventCard();
      return UnlessPays(payer, int.parse(m[2]), e);
    }

    // Exerting and moving.
    m = rx(c, r'\{e\} (chosen .+)');
    if (m != null) {
      final t = target(m[1], ctx);
      if (t is Chosen) return Exert(Chosen(t.filter.copyWith(exerted: false), count: t.count, upTo: t.upTo, slot: t.slot));
    }
    if (c == 'exert all cards in your inkwell') return const S4ExertInkwell();
    m = rx(c, r'move (him|her|them|it) to another location for free');
    if (m != null) {
      final t = ref(m[1], ctx);
      return t == null ? null : MoveToAnotherLocation(t);
    }

    // Zones.
    m = rx(c, r"put (all .+?) into their players' inkwells facedown( and exerted)?");
    if (m != null) {
      final t = target(m[1], ctx);
      return t == null ? null : ToInkwell(t, exerted: m[2].isNotEmpty);
    }
    if (c == 'put any number of cards from under your characters and locations into your inkwell facedown and exerted') return const UnderToInkwell();
    if (c == 'return this card from your discard to your hand') return const ReturnToHand(This());
    m = rx(c, r'put (?:a|an) (.+?) card from your discard under this item faceup');
    if (m != null) {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      return f == null ? null : DiscardUnderThis(f);
    }
    if (c == 'this turn, you may play characters from under this item') return const PlayFromUnderThisTurn();
    m = rx(c, r'put a card from the top of your deck facedown under each of (your other .+|your .+)');
    if (m != null) {
      final f = _groupFilter(m[1]);
      return f == null ? null : PutUnderEach(f, ctx.nextSlot++);
    }

    // Playing for free (CR 6.1.7).
    m = rx(c, r'play this (?:character|card) for free(?: and (?:he|she|they|it) enters? play exerted)?');
    if (m != null) return PlaySelfFree(exerted: c.contains('exerted'));
    if (c == 'play those characters from your discard for free') return const PlayUnderFromDiscard();
    m = rx(c, r'play or shift (?:a|an) (.+?) for free');
    if (m != null) {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      return f == null ? null : PlayOrShiftFree(f);
    }
    if (c == 'play that song again from your discard for free, then put it on the bottom of your deck') return const ReplaySong();
    m = rx(c, r"play (?:a|an) (.+?) with cost equal to or less than the exerted character's cost for free");
    if (m != null && ctx.nextSlot > 0) {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      return f == null ? null : PlayFreeUpToCostOf(f, Remembered(ctx.nextSlot - 1));
    }
    m = rx(c, r'play (?:a|an) character with the same name as (?:that character|him|her|them) for free');
    if (m != null && ctx.nextSlot > 0) return PlaySameNameFree(ctx.nextSlot - 1);
    m = rx(c, r'banish any number of chosen (.+?) with total strength (\d+) or less');
    if (m != null) {
      final f = filter(_plural(m[1]), Owner.any);
      return f == null ? null : BanishTotalStrength(f, int.parse(m[2]));
    }
    if (c == 'banish all characters with strength equal to or less than the strength he had in play') return const BanishUpToEventStrength();
    m = rx(c, r'pay (\d+) ink less for the next (.+?) you play this turn');
    if (m != null) {
      final f = filter(m[2], Owner.yours, cardTypes: true);
      return f == null ? null : NextCostReduction(f, int.parse(m[1]));
    }

    // Granted activated abilities for a while.
    m = rx(c, r'(.+?) gains? "(.+)" (this turn|until the start of your next turn)');
    if (m != null) {
      final t = target(m[1], ctx);
      final ab = _s4QuotedAbility(m[2]);
      if (t == null || ab == null) return null;
      return GrantAbilityFor(t, ab, m[3] == 'this turn' ? Lasting.thisTurn : Lasting.untilYourNextTurn);
    }
    return null;
  }
}
