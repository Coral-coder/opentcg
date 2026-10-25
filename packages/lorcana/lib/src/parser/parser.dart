/// Card text → ability IR. A card is supported when every paragraph of its text parses; the
/// paragraphs that don't are recorded, so coverage grows template by template.
library;

import '../cards/card.dart';
import '../cards/classifications.dart';
import '../ir.dart';
import 'text.dart';

part 'zones.dart';
part 'board.dart';
part 'triggers.dart';
part 'statics.dart';
part 'wave2_s3.dart';
part 'wave2_s4.dart';
part 'wave2_s1.dart';
part 'wave2_s2.dart';

class ParsedCard {
  const ParsedCard(this.card, this.abilities, this.unsupported);
  final LCard card;
  final List<Ability> abilities;
  final List<String> unsupported;
  bool get supported => unsupported.isEmpty;
}

/// Bumped whenever parsing could change how a card plays.
const lorcanaEngineVersion = 3;

class LorcanaParser {
  static final Map<String, ParsedCard> _cache = {};

  /// When set, collects what failed to parse ("sentence: …", "trigger: …", "static: …").
  static List<String>? diag;

  static ParsedCard parse(LCard card) => _cache.putIfAbsent(card.fullName, () => _CardParser(card).run());

  static void clearCache() => _cache.clear();

  /// Parses [card] without the cache (which is keyed by name), for comparing two wordings of
  /// the same card.
  static ParsedCard parseUncached(LCard card) => _CardParser(card).run();
}

// Number words.
int? numWord(String s) {
  final t = s.trim();
  final n = int.tryParse(t);
  if (n != null) return n;
  return const {'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10}[t];
}

/// Matches the whole string.
List<String>? rx(String s, String pattern) {
  final m = RegExp('^$pattern\$').firstMatch(s);
  if (m == null) return null;
  return [for (var i = 0; i <= m.groupCount; i++) m.group(i) ?? ''];
}

class _CardParser {
  _CardParser(this.card);
  final LCard card;
  final abilities = <Ability>[];
  final unsupported = <String>[];

  String get selfWord => switch (card.type) {
    CardType.item => 'item',
    CardType.location => 'location',
    _ => 'character',
  };

  ParsedCard run() {
    if (card.type == CardType.location && card.moveCost == null) unsupported.add('Location without a move cost in the data');
    final text = normalizeText(card.text);
    if (card.type == CardType.action && text.isEmpty) unsupported.add('Action without its effect text in the data');
    final paras = _w2Paragraphs(splitParagraphs(text, action: card.type == CardType.action));
    for (final p in paras) {
      List<Ability>? r;
      try {
        r = p.keyword ? _keyword(p.body) : (card.type == CardType.action ? (_w2Action(p) ?? _action(p)) : _paragraph(p));
      } catch (e) {
        r = null;
      }
      // Text that parses to nothing isn't understood either.
      if (r == null || (r.isEmpty && p.body.trim().isNotEmpty)) {
        unsupported.add(p.printed);
      } else {
        abilities.addAll(r);
      }
    }
    return ParsedCard(card, abilities, unsupported);
  }

  // -------------------------------------------------------------------------------------------
  // Keywords (CR 8)
  // -------------------------------------------------------------------------------------------

  List<Ability>? _keyword(String raw) {
    final t = raw.toLowerCase().trim();
    final simple = {'alert': Kw.alert, 'bodyguard': Kw.bodyguard, 'evasive': Kw.evasive, 'reckless': Kw.reckless, 'rush': Kw.rush, 'support': Kw.support, 'vanish': Kw.vanish, 'ward': Kw.ward}[t];
    if (simple != null) return [KeywordAbility(raw, Keyword(simple))];
    var m = rx(t, r'(challenger|resist) ?\+(\d+)');
    if (m != null) return [KeywordAbility(raw, Keyword(m[1] == 'challenger' ? Kw.challenger : Kw.resist, n: int.parse(m[2])))];
    m = rx(t, r'(singer|sing together) (\d+)');
    if (m != null) return [KeywordAbility(raw, Keyword(m[1] == 'singer' ? Kw.singer : Kw.singTogether, n: int.parse(m[2])))];
    m = rx(t, r'boost (\d+) ?\{i\}');
    if (m != null) return [KeywordAbility(raw, Keyword(Kw.boost, n: int.parse(m[1])))];
    final sd = shiftDiscard(t);
    if (sd != null) return [KeywordAbility(raw, Keyword(Kw.shift, shiftDiscard: sd))];
    m = rx(t, r'(?:(.+) )?shift:? (\d+) ?(?:\{i\})?');
    if (m != null) {
      var prefix = m[1];
      final n = int.parse(m[2]);
      if (prefix.isEmpty) return [KeywordAbility(raw, Keyword(Kw.shift, n: n))];
      if (prefix == 'universal') return [KeywordAbility(raw, Keyword(Kw.shift, n: n, universalShift: true))];
      // Duo, Combo, Potato and Temporary Shift (CR 8.10.8.3–8.10.8.6); Temporary combines
      // with [Classification] Shift (8.10.9: "Temporary Red Panda Shift").
      final first = prefix.split(' ').first;
      final variant = switch (first) {
        'duo' => ShiftVariant.duo,
        'combo' => ShiftVariant.combo,
        'temporary' => ShiftVariant.temporary,
        'potato' => ShiftVariant.potato,
        _ => ShiftVariant.plain,
      };
      if (variant != ShiftVariant.plain) {
        prefix = prefix.substring(first.length).trim();
        if (prefix.isNotEmpty && variant != ShiftVariant.temporary) return null;
      }
      return [KeywordAbility(raw, Keyword(Kw.shift, n: n, shiftVariant: variant, shiftClass: prefix.isEmpty ? null : _cap(prefix)))];
    }
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Paragraphs
  // -------------------------------------------------------------------------------------------

  String _lower(String body) {
    var t = body.trim();
    if (t.endsWith('.')) t = t.substring(0, t.length - 1);
    t = t.replaceAll(RegExp(r'\s*\{s\}', caseSensitive: false), ' strength');
    t = t.replaceAll(RegExp(r'\s*\{w\}', caseSensitive: false), ' willpower');
    t = t.replaceAll(RegExp(r'\s*\{l\}', caseSensitive: false), ' lore');
    t = t.replaceAll(RegExp(r'\s*\{i\}', caseSensitive: false), ' ink');
    t = t.replaceAll(RegExp(r'\{e\}', caseSensitive: false), '{e}');
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t.toLowerCase();
  }

  List<Ability>? _action(Paragraph p) {
    final s3 = _s3Action(p);
    if (s3 != null) return s3;
    final s4 = _s4Action(p);
    if (s4 != null) return s4;
    final t = _lower(p.body);
    final w1 = _w1Action(p, t);
    if (w1 != null) return w1;
    final e = effects(t, _Ctx());
    if (e == null) return null;
    return [ActionEffect(p.printed, e)];
  }

  List<Ability>? _paragraph(Paragraph p) {
    final s3 = _s3Paragraph(p);
    if (s3 != null) return s3;
    final t = _lower(p.body);
    final printed = p.printed;
    final w1 = _w1Paragraph(p, t);
    if (w1 != null) return w1;
    final w2 = _w2Paragraph(printed, t);
    if (w2 != null) return w2;
    // Activated: "[Cost] - [Effect]" (CR 6.3.1).
    final dash = t.indexOf(' - ');
    if (dash > 0) {
      final cost = _cost(t.substring(0, dash));
      if (cost != null) {
        final e = effects(t.substring(dash + 3), _Ctx());
        if (e == null) return null;
        return [Activated(printed, cost, e)];
      }
    }
    // Some texts write the cost with a colon: "{e}: Exert chosen character".
    final colon = t.indexOf(': ');
    if (colon > 0) {
      final cost = _cost(t.substring(0, colon));
      if (cost != null) {
        final e = effects(t.substring(colon + 2), _Ctx());
        if (e == null) return null;
        return [Activated(printed, cost, e)];
      }
    }
    final before = LorcanaParser.diag?.length ?? 0;
    final trig = _triggered(printed, t);
    if (trig != null) return trig;
    if (RegExp(r'^(when|whenever|at the (start|end)|once per turn|once during your turn|the first time|during your turn, when)').hasMatch(t)) {
      // Only when nothing more specific (the failing sentence or trigger head) was recorded.
      if ((LorcanaParser.diag?.length ?? 0) == before) LorcanaParser.diag?.add('trigger: ${t.split(',').first}');
      return null;
    }
    final st = _static(printed, t);
    if (st == null) LorcanaParser.diag?.add('static: $t');
    return st;
  }

  Cost? _cost(String s) {
    final s4 = _s4Cost(s);
    if (s4 != null) return s4;
    var exert = false, ink = 0, banishSelf = false, discard = 0;
    Filter? exertOther, banishOther;
    for (final part in s.split(RegExp(r', |(?<!choose) and '))) {
      final p = part.trim();
      if (p == '{e}') {
        exert = true;
        continue;
      }
      var m = rx(p, r'(\d+) ink');
      if (m != null) {
        ink = int.parse(m[1]);
        continue;
      }
      if (rx(p, r'banish this (character|item|location)') != null) {
        banishSelf = true;
        continue;
      }
      if (p == 'choose and discard a card' || p == 'discard a card') {
        discard = 1;
        continue;
      }
      m = rx(p, r'choose and discard (two|\d+) cards');
      if (m != null) {
        discard = numWord(m[1])!;
        continue;
      }
      m = rx(p, r'banish (?:chosen|one of your|a|an) (.+?)(?: of yours)?');
      if (m != null) {
        final f = filter(m[1], Owner.yours);
        if (f == null) return null;
        banishOther = f;
        continue;
      }
      m = rx(p, r'\{e\} (?:one of your|a|an|chosen) (.+?)(?: of yours)?');
      if (m != null) {
        final f = filter(m[1], Owner.yours);
        if (f == null) return null;
        exertOther = f.copyWith(exerted: false);
        continue;
      }
      return null;
    }
    if (!exert && ink == 0 && !banishSelf && discard == 0 && exertOther == null && banishOther == null) return null;
    return Cost(exert: exert, ink: ink, banishSelf: banishSelf, discard: discard, exertOther: exertOther, banishOther: banishOther);
  }

  // -------------------------------------------------------------------------------------------
  // Triggered abilities (CR 6.2)
  // -------------------------------------------------------------------------------------------

  List<Ability>? _triggered(String printed, String t0) {
    final s4 = _s4Triggered(printed, t0);
    if (s4 != null) return s4;
    var t = t0;
    Cond? during;
    var once = false;
    var m = RegExp(r'^(during your turn|once per turn|once during your turn|while this (?:character|item|location) is exerted|during an opponent.s turn), ').firstMatch(t);
    while (m != null) {
      switch (m.group(1)) {
        case 'during your turn':
          during = _and(during, const YourTurn());
        case 'once per turn':
          once = true;
        case 'once during your turn':
          once = true;
          during = _and(during, const YourTurn());
        case final x when x!.startsWith('while'):
          during = _and(during, const SelfState(exerted: true));
        default:
          during = _and(during, const Not(YourTurn()));
      }
      t = t.substring(m.end);
      m = RegExp(r'^(during your turn|once per turn|once during your turn|while this (?:character|item|location) is exerted|during an opponent.s turn), ').firstMatch(t);
    }
    if (!RegExp(r'^(when|whenever|at the (start|end)|the first time)').hasMatch(t)) return null;
    // Split "[Trigger Condition], [Effect]" at the first comma that leaves a known trigger.
    var idx = t.indexOf(', ');
    while (idx > 0) {
      final head = t.substring(0, idx);
      var triggers = _triggerHead(head);
      if (triggers != null) {
        var rest = t.substring(idx + 2);
        (triggers, rest) = _qualifyTrigger(triggers, rest);
        Cond? cond;
        final ifm = RegExp(r'^if (.+?), (.+)$').firstMatch(rest);
        if (ifm != null) {
          final c = condition(ifm.group(1)!);
          if (c != null) {
            cond = c;
            rest = ifm.group(2)!;
          }
        }
        final trs = triggers;
        bool all(Set<Event> evs) => trs.every((tr) => tr.$1 is CardEvent && evs.contains((tr.$1 as CardEvent).event));
        final e = effects(
          rest,
          _Ctx(
            event: true,
            eventOther: triggers.every((tr) => _aboutOtherCard(tr.$1)),
            eventLocation: all(const {Event.movesToLocation}),
            eventChallenged: all(const {Event.isChallenged, Event.banishedInChallenge}) || triggers.every((tr) => _s3Defending(tr.$1)),
          )..s4Challenged = triggers.every((tr) => tr.$1 is CardEvent && (tr.$1 as CardEvent).event == Event.isChallenged),
        );
        if (e == null) return null;
        return [for (final tr in triggers) Triggered(printed, tr.$1, e, condition: cond, during: _and(during, tr.$2), oncePerTurn: once, fromDiscard: tr.$3)];
      }
      idx = t.indexOf(', ', idx + 1);
    }
    return null;
  }

  Cond? _and(Cond? a, Cond? b) => a == null ? b : (b == null ? a : AllConds([a, b]));

  /// "When you play this character", "whenever this character quests"… → triggers, each with an
  /// optional condition checked as it triggers and whether it works from the discard.
  List<(Trigger, Cond?, bool)>? _triggerHead(String h0) {
    var h = h0.trim();
    final s3 = _s3TriggerHead(h);
    if (s3 != null) return s3;
    final w1 = _w1TriggerHead(h);
    if (w1 != null) return w1;
    final more = _moreTriggerHead(h);
    if (more != null) return more;
    // "When you play this character and whenever she quests" (CR 6.2.6).
    final both = RegExp(r'^(when you play this character) and (whenever (?:he|she|they|this character) quests?)$').firstMatch(h);
    if (both != null) {
      return [(const OnPlay(), null, false), (const CardEvent(Event.quests), null, false)];
    }
    if (rx(h, r'when you play this (character|item|location)') != null) return [(const OnPlay(), null, false)];
    var m = rx(
      h,
      r'(?:when|whenever) (this character|he|she|they|one of your (?:other )?(.+?)|an opposing (.+?)|another (.+?)|a (.+?)) (quests|challenges(?: another character| a .+)?|is challenged|is challenged and banished|is banished(?: in a challenge)?|banishes another character in a challenge|sings a song|moves to a location|is dealt damage|exerts?)',
    );
    if (m != null) {
      final subj = m[1];
      Filter? f;
      if (const {'this character', 'he', 'she', 'they'}.contains(subj)) {
        f = null;
      } else if (subj.startsWith('one of your')) {
        final other = subj.contains('other');
        f = filter(_plural(m[2]), Owner.yours)?.copyWith(other: other);
        if (f == null) return null;
      } else if (subj.startsWith('an opposing')) {
        f = filter(m[3], Owner.opposing);
        if (f == null) return null;
      } else if (subj.startsWith('another')) {
        f = filter(m[4], Owner.any)?.copyWith(other: true);
        if (f == null) return null;
      } else {
        f = filter(m[5], Owner.any);
        if (f == null) return null;
      }
      final ev = m[6];
      final event = switch (ev) {
        'quests' => Event.quests,
        'is challenged' => Event.isChallenged,
        'is challenged and banished' => Event.banishedInChallenge,
        'is banished' => Event.banished,
        'is banished in a challenge' => Event.banishedInChallenge,
        'banishes another character in a challenge' => Event.banishesInChallenge,
        'sings a song' => Event.sings,
        'moves to a location' => Event.movesToLocation,
        'is dealt damage' => Event.dealtDamage,
        _ when ev.startsWith('challenges') => Event.challenges,
        _ => null,
      };
      if (event == null) return null;
      if (ev.startsWith('challenges a ')) return null;
      return [(CardEvent(event, subject: f), null, false)];
    }
    m = rx(h, r'whenever (you|an opponent|one of your opponents) plays? (?:a|an|another) (.+)');
    if (m != null) {
      final what = m[2];
      final f = filter(what, Owner.any, cardTypes: true);
      if (f == null) return null;
      return [(CardPlayed(what.startsWith('another') ? f.copyWith(other: true) : f, by: m[1] == 'you' ? Owner.yours : Owner.opposing), null, false)];
    }
    m = rx(h, r'at the (start|end) of (your|each opponent.s|the) turn');
    if (m != null) {
      if (m[2] == "each opponent's") return null;
      return [(TurnStep(start: m[1] == 'start', yours: m[2] == 'your'), null, false)];
    }
    if (h == 'whenever you draw a card') return [(const Draws(Owner.yours), null, false)];
    if (h == 'when you move a character here' || h == 'whenever you move a character here' || h == 'whenever a character moves here') return [(const MovedHere(), null, false)];
    final w2 = _w2TriggerHead(h);
    if (w2 != null) return w2;
    LorcanaParser.diag?.add('trigger: $h');
    return null;
  }

  String _plural(String s) {
    var t = s.trim();
    if (t.endsWith('characters')) t = '${t.substring(0, t.length - 10)}character';
    if (t.endsWith('items')) t = '${t.substring(0, t.length - 5)}item';
    if (t.endsWith('locations')) t = '${t.substring(0, t.length - 9)}location';
    return t;
  }

  // -------------------------------------------------------------------------------------------
  // Static abilities (CR 6.4)
  // -------------------------------------------------------------------------------------------

  List<Ability>? _static(String printed, String t0) {
    final more = _moreStatic(printed, t0) ?? _w2Static(printed, t0);
    if (more != null) return more;
    var t = t0;
    Cond? cond;
    // "While X, Y" / "During your turn, Y" / "Y while X" / "If X, Y".
    final pre = RegExp(r'^(while|if|during your turn|during an opponent.s turn)(?: (.+?))?, (.+)$').firstMatch(t);
    if (pre != null) {
      final w = pre.group(1)!;
      if (w == 'during your turn') {
        cond = const YourTurn();
        t = '${pre.group(2) == null ? '' : '${pre.group(2)}, '}${pre.group(3)}';
      } else if (w.startsWith('during an opponent')) {
        cond = const Not(YourTurn());
        t = '${pre.group(2) == null ? '' : '${pre.group(2)}, '}${pre.group(3)}';
      } else {
        final c = condition(pre.group(2) ?? '');
        if (c == null) return null;
        cond = c;
        t = pre.group(3)!;
      }
    }
    final suf = RegExp(r'^(.+?) (while|if) (.+)$').firstMatch(t);
    if (suf != null && !t.contains(' while here')) {
      final c = condition(suf.group(3)!);
      if (c != null) {
        cond = _and(cond, c);
        t = suf.group(1)!;
      }
    }
    final unless = RegExp(r'^(.+?) unless (.+)$').firstMatch(t);
    if (unless != null) {
      final c = condition(unless.group(2)!);
      if (c == null) return null;
      cond = _and(cond, Not(c));
      t = unless.group(1)!;
    }
    final es = _staticEffect(t);
    if (es == null) return null;
    return [for (final x in es) Static(printed, x, condition: cond, inHand: (x is CostReduction && x.self) || (x is W1Static && x.inHand))];
  }

  List<StaticEffect>? _staticEffect(String t0) {
    final s3 = _s3StaticEffect(t0);
    if (s3 != null) return s3;
    final w1 = _w1StaticEffect(t0);
    if (w1 != null) return w1;
    final more = _moreStaticEffect(t0) ?? _w2StaticEffect(t0);
    if (more != null) return more;
    var t = t0;
    // Self cost reduction (CR 4.3.6): "you pay 2 ink less to play this character".
    var m = rx(t, r'(?:for each (.+?), )?you pay (\d+) ink less to play this (character|item|location|action|song)(?: for each (.+))?');
    if (m != null) {
      Amount a = Fixed(int.parse(m[2]));
      final each = m[1].isNotEmpty ? m[1] : m[4];
      if (each.isNotEmpty) {
        final c = countOf(each);
        if (c == null) return null;
        a = CountOf(c.filter, place: c.place, whose: c.whose, per: int.parse(m[2]));
      }
      return [CostReduction(const Filter(), a, self: true)];
    }
    m = rx(t, r'you pay (\d+) ink less to play (.+)');
    if (m != null) {
      final f = filter(m[2], Owner.yours, cardTypes: true);
      if (f == null) return null;
      return [CostReduction(f, Fixed(int.parse(m[1])))];
    }
    if (rx(t, r'this (character|item|location) enters play exerted') != null) return const [EntersWith(exerted: true)];
    m = rx(t, r'this character enters play with (\d+) damage');
    if (m != null) return [EntersWith(damage: int.parse(m[1]))];
    if (rx(t, r'you may put an additional card from your hand into your inkwell facedown') != null) return const [ExtraInk()];
    if (t == "skip your turn's draw step") return const [SkipDraw()];
    // "[Subject] get(s) +N {stat}" / "gain(s) Kw" / "can't …".
    m = RegExp(r'^(.+?) (gets?|gains?|can.t|can|has|have|count as having) (.+)$').firstMatch(t)?.let((x) => [x.group(0)!, x.group(1)!, x.group(2)!, x.group(3)!]);
    if (m != null) {
      var subj = m[1];
      var here = false;
      var pred = '${m[2]} ${m[3]}';
      if (pred.endsWith(' while here')) {
        here = true;
        pred = pred.substring(0, pred.length - 11);
      }
      Filter? f;
      if (const {'this character', 'this item', 'this location', 'he', 'she', 'they', 'it'}.contains(subj)) {
        f = null;
      } else {
        f = _groupFilter(subj);
        if (f == null) return null;
        if (here) f = f.copyWith(atThisLocation: true);
      }
      final list = <StaticEffect>[];
      for (final part in pred.split(RegExp(r' and (?=(?:gets?|gains?|can) )|, and (?=(?:gets?|gains?|can) )'))) {
        final r = _predicate(part.trim(), f);
        if (r == null) return null;
        list.addAll(r);
      }
      return list;
    }
    return null;
  }

  List<StaticEffect>? _predicate(String p0, Filter? f) {
    final more = _morePredicate(p0, f) ?? _w2Predicate(p0, f);
    if (more != null) return more;
    var p = p0;
    var m = rx(p, r'gets? ([+-])(\d+) (strength|willpower|lore)(?: and ([+-])(\d+) (strength|willpower|lore))?(?: for each (.+))?');
    if (m != null) {
      final out = <StaticEffect>[];
      Amount amt(String n) {
        if (m![7].isEmpty) return Fixed(int.parse(n));
        final c = countOf(m[7]);
        if (c == null) throw const FormatException('count');
        return CountOf(c.filter, place: c.place, whose: c.whose, per: int.parse(n));
      }

      out.add(StaticMod(f, _stat(m[3]), amt(m[2]), negative: m[1] == '-'));
      if (m[4].isNotEmpty) out.add(StaticMod(f, _stat(m[6]), amt(m[5]), negative: m[4] == '-'));
      return out;
    }
    m = rx(p, r'gains? (.+)');
    if (m != null) {
      final kws = _keywordList(m[1]);
      if (kws == null) return null;
      return [for (final k in kws) StaticKeyword(f, k)];
    }
    final rule = switch (p) {
      "can't quest" => Rule.cantQuest,
      "can't challenge" => Rule.cantChallenge,
      "can't be challenged" => Rule.cantBeChallenged,
      "can't ready" => Rule.cantReady,
      "can't {e} to sing songs" || "can't sing songs" => Rule.cantSing,
      _ => null,
    };
    if (rule != null) return [StaticRule(f, rule)];
    return null;
  }

  Stat _stat(String s) => switch (s) {
    'strength' => Stat.strength,
    'willpower' => Stat.willpower,
    _ => Stat.lore,
  };

  /// "Evasive", "Resist +1 and Ward", "Challenger +2".
  List<Keyword>? _keywordList(String s) {
    final out = <Keyword>[];
    for (final part in s.split(RegExp(r', and |, | and '))) {
      final k = _keyword(part.trim());
      if (k == null || k.length != 1) return null;
      out.add((k.first as KeywordAbility).keyword);
    }
    return out;
  }

  // -------------------------------------------------------------------------------------------
  // Conditions
  // -------------------------------------------------------------------------------------------

  Cond? condition(String s0) {
    final s = s0.trim();
    final s3 = _s3Condition(s);
    if (s3 != null) return s3;
    final s4 = _s4Condition(s);
    if (s4 != null) return s4;
    final w1 = _w1Condition(s);
    if (w1 != null) return w1;
    final board = _boardCondition(s);
    if (board != null) return board;
    final more = _moreCondition(s);
    if (more != null) return more;
    if (s == "it's your turn" || s == 'it is your turn') return const YourTurn();
    if (rx(s, r'this (character|item|location) is exerted') != null) return const SelfState(exerted: true);
    if (rx(s, r'this character is at a location') != null) return const SelfState(atLocation: true);
    if (rx(s, r'this character (?:has|is) damaged?(?: on (?:him|her|them|it))?') != null || s == 'this character has damage') return const SelfState(damaged: true);
    if (s == 'you have no cards in your hand') return const HandCond(Who.you, Cmp.eq, 0);
    var m = rx(s, r'you have (\d+) or (more|fewer) cards in your hand');
    if (m != null) return HandCond(Who.you, m[2] == 'more' ? Cmp.ge : Cmp.le, int.parse(m[1]));
    m = rx(s, r'you have (\d+) or more lore');
    if (m != null) return LoreCond(Who.you, Cmp.ge, int.parse(m[1]));
    m = rx(s, r'an opponent has (\d+) or more lore');
    if (m != null) return LoreCond(Who.opponents, Cmp.ge, int.parse(m[1]));
    m = rx(s, r'you have (a|an|another|no|(?:\d+|two|three|four|five) or more(?: other)?) (.+?) in play');
    if (m != null) {
      final q = m[1];
      var what = m[2];
      final other = q == 'another' || q.endsWith('other');
      final f = filter(_plural(what), Owner.yours, cardTypes: true);
      if (f == null) return null;
      final ff = other ? f.copyWith(other: true) : f;
      if (q == 'no') return CountCond(ff, Cmp.eq, 0);
      final n = q.contains(' or more') ? numWord(q.split(' ').first)! : 1;
      return CountCond(ff, Cmp.ge, n);
    }
    m = rx(s, r'you have a character named (.+?) in play');
    if (m != null) return CountCond(Filter(owner: Owner.yours, named: m[1]), Cmp.ge, 1);
    m = rx(s, r'you have (?:a|an) (.+?) in your discard');
    if (m != null) {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      if (f == null) return null;
      return CountCond(f, Cmp.ge, 1, place: Place.discard);
    }
    return _zoneCondition(s) ?? _s4ConditionLast(s) ?? _w2Condition(s);
  }

  // -------------------------------------------------------------------------------------------
  // Effects (CR 6.7)
  // -------------------------------------------------------------------------------------------

  Effect? effects(String text, _Ctx ctx) {
    final w1 = _w1Effects(text, ctx);
    if (w1 != null) return w1;
    final w2 = _w2Effects(text, ctx);
    if (w2 != null) return w2;
    final zone = _zoneEffects(text, ctx);
    if (zone != null) return zone;
    // "Choose one: - A. - B." (CR 6.1.5.2).
    final ch = RegExp(r'^choose one(?: of the following)?: - (.+)$').firstMatch(text);
    if (ch != null) {
      final opts = ch.group(1)!.split(RegExp(r'\.? - '));
      final effs = <Effect>[];
      for (final o in opts) {
        final e = effects(o.trim().replaceAll(RegExp(r'\.$'), ''), ctx);
        if (e == null) return null;
        effs.add(e);
      }
      return ChooseOne(effs, opts);
    }
    final ss = _sentences(text);
    final steps = <Effect>[];
    for (var i = 0; i < ss.length; i++) {
      // Multi-sentence templates first.
      final span = _span(ss, i, ctx);
      if (span != null) {
        steps.add(span.$1);
        i += span.$2 - 1;
        continue;
      }
      var s = ss[i];
      if (s.startsWith('then, ')) s = s.substring(6);
      if (s.startsWith('then ')) s = s.substring(5);
      if (_s3Step(s, steps, ctx)) continue;
      final m = RegExp(r'^if you do, (.+)$').firstMatch(s);
      if (m != null) {
        final e = sentence(m.group(1)!, ctx);
        if (e == null) return _fail(s);
        steps.add(If(const DidIt(), e));
        continue;
      }
      final o = RegExp(r'^otherwise, (.+)$').firstMatch(s);
      if (o != null && steps.isNotEmpty && steps.last is If) {
        final prev = steps.removeLast() as If;
        final e = sentence(o.group(1)!, ctx);
        if (e == null) return _fail(s);
        steps.add(If(prev.cond, prev.then, e));
        continue;
      }
      if (_s4Instead(s, steps, ctx)) continue;
      if (_boardInstead(s, steps, ctx)) continue;
      final e = sentence(s, ctx);
      if (e == null) return _fail(s);
      steps.add(e);
    }
    if (steps.isEmpty) return null;
    return steps.length == 1 ? steps.first : Seq(steps);
  }

  Effect? _fail(String s) {
    LorcanaParser.diag?.add('sentence: $s');
    return null;
  }

  List<String> _sentences(String t) {
    final out = <String>[];
    var depth = 0, start = 0;
    for (var i = 0; i < t.length; i++) {
      final c = t[i];
      if (c == '"') depth = 1 - depth;
      if (c == '.' && depth == 0 && (i + 1 == t.length || t[i + 1] == ' ')) {
        final s = t.substring(start, i).trim();
        if (s.isNotEmpty) out.add(s);
        start = i + 1;
      }
    }
    final s = t.substring(start).trim();
    if (s.isNotEmpty) out.add(s.endsWith('.') ? s.substring(0, s.length - 1) : s);
    return out;
  }

  /// Templates that run over several sentences: look at the top N, reveal and put into hand.
  (Effect, int)? _span(List<String> ss, int i, _Ctx ctx) {
    final s3 = _s3Span(ss, i, ctx);
    if (s3 != null) return s3;
    final s4 = _s4Span(ss, i, ctx);
    if (s4 != null) return s4;
    final zone = _zoneSpan(ss, i, ctx);
    if (zone != null) return zone;
    final s = ss[i];
    var m = rx(s, r'look at the top (\d+) cards of your deck');
    if (m != null && i + 1 < ss.length) {
      final n = int.parse(m[1]);
      final next = ss[i + 1];
      if (rx(next, r'put them back on the top of your deck in any order') != null) return (LookTop(n, reorderOnly: true), 2);
      if (rx(next, r'put one (?:into your hand|on the top of your deck) and the (?:other|rest) on the bottom of your deck(?: in any order)?') != null) {
        final hand = next.contains('into your hand');
        return (
          LookTop(
            n,
            pick: hand ? const Filter(types: {CardType.character, CardType.action, CardType.item, CardType.location}) : null,
            restBottom: true,
            reorderOnly: !hand,
            mustPick: hand,
          ),
          2,
        );
      }
      final pick = rx(next, r'(?:you may )?(?:reveal )?(?:up to (\w+)|(?:a|an)) (.+?) cards? and put (?:it|them) into your hand');
      if (pick != null && i + 2 < ss.length && rx(ss[i + 2], r'put the rest on the (bottom|top) of your deck(?: in any order)?') != null) {
        final f = filter(_plural(pick[2]), Owner.any, cardTypes: true);
        if (f == null) return null;
        final count = pick[1].isEmpty ? 1 : numWord(pick[1])!;
        return (LookTop(n, pick: f, pickCount: count, restBottom: ss[i + 2].contains('bottom'), mustPick: pick[1].isEmpty && !next.startsWith('you may')), 3);
      }
      final pickAny = rx(next, r'put one into your hand and the rest on the bottom of your deck(?: in any order)?');
      if (next == 'put one into your hand and the other into your inkwell facedown and exerted') {
        return (LookTop(n, pick: const Filter(types: {CardType.character, CardType.action, CardType.item, CardType.location}), mustPick: true, restInk: true), 2);
      }
      final one = rx(next, r'(you may )?put one (?:of them )?into your hand');
      if (one != null && i + 2 < ss.length && rx(ss[i + 2], r'put the rest on the (bottom|top) of your deck(?: in any order)?') != null) {
        return (LookTop(n, pick: const Filter(types: {CardType.character, CardType.action, CardType.item, CardType.location}), restBottom: ss[i + 2].contains('bottom'), mustPick: one[1].isEmpty), 3);
      }
      if (pickAny != null) return (LookTop(n, pick: const Filter(types: {CardType.character, CardType.action, CardType.item, CardType.location}), mustPick: true), 2);
    }
    m = rx(s, r'look at the top card of your deck');
    if (m != null && i + 1 < ss.length && rx(ss[i + 1], r'put it on either the top or the bottom of your deck') != null) {
      return (const LookTop(1, reorderOnly: true), 2);
    }
    return _w2Span(ss, i, ctx);
  }

  /// One sentence: "you may", conditions, then clauses joined by "and"/"then".
  Effect? sentence(String s0, _Ctx ctx) {
    var s = s0.trim();
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    // A floating triggered ability (CR 6.2.7.1): "whenever one of your characters quests this
    // turn, gain 1 lore", "this turn, whenever …, …".
    var m = RegExp(r'^((?:when|whenever) .+?) this turn, (.+)$').firstMatch(s) ?? RegExp(r'^this turn, ((?:when|whenever) .+?), (.+)$').firstMatch(s);
    if (m != null) {
      final t = _triggered(s0.trim(), '${m.group(1)}, ${m.group(2)}');
      if (t == null || t.length != 1 || t.first is! Triggered) return null;
      return Floating(t.first as Triggered);
    }
    m = RegExp(r'^you may (.+)$').firstMatch(s);
    if (m != null) {
      final e = _clauses(m.group(1)!, ctx);
      if (e == null) return null;
      return May(e);
    }
    m = RegExp(r'^if (.+?), (.+)$').firstMatch(s);
    if (m != null) {
      final c = condition(m.group(1)!) ?? _ifTarget(m.group(1)!, ctx);
      if (c != null) {
        final e = sentence(m.group(2)!, ctx);
        if (e == null) return null;
        return If(c, e);
      }
    }
    return _clauses(s, ctx);
  }

  Cond? _ifTarget(String s, _Ctx ctx) {
    final s4 = _s4IfTarget(s, ctx);
    if (s4 != null) return s4;
    final w2 = _w2IfTarget(s, ctx);
    if (w2 != null) return w2;
    final m = rx(s, r'(?:a|an) (.+?) (?:is|was) chosen');
    if (m != null) {
      final f = filter(m[1], Owner.any);
      if (f == null) return null;
      return TargetIs(const Remembered(), f);
    }
    return null;
  }

  Effect? _clauses(String s, _Ctx ctx) {
    final whole = clause(s, ctx);
    if (whole != null) return whole;
    for (final sep in const [', then ', ' and then ', ', and ', ' and ', ', ']) {
      var idx = s.indexOf(sep);
      while (idx > 0) {
        final save = ctx.save();
        final a = clause(s.substring(0, idx), ctx);
        if (a != null) {
          var right = s.substring(idx + sep.length);
          // "gain 1 lore and draw a card", "draw a card and gain 1 lore".
          final b = _clauses(right, ctx);
          if (b != null) return Seq([a, b]);
        }
        ctx.restore(save);
        idx = s.indexOf(sep, idx + 1);
      }
    }
    // "X to Y": a sequential effect (CR 6.1.5.1): "banish chosen item of yours to deal 5 damage…".
    final to = RegExp(r'^(.+?) to (draw|deal|gain|return|banish|put|ready|exert|remove|play) (.+)$').firstMatch(s);
    if (to != null) {
      final a = clause(to.group(1)!, ctx);
      if (a != null) {
        final b = _clauses('${to.group(2)} ${to.group(3)}', ctx);
        if (b != null) return Seq([a, If(const DidIt(), b)]);
      }
    }
    return null;
  }

  /// One action.
  Effect? clause(String c0, _Ctx ctx) {
    final c = c0.trim();
    final s3 = _s3Clause(c, ctx);
    if (s3 != null) return s3;
    final s4 = _s4Clause(c, ctx);
    if (s4 != null) return s4;
    final w1 = _w1Clause(c, ctx);
    if (w1 != null) return w1;
    final zone = _zoneFirst(c, ctx);
    if (zone != null) return zone;
    final w2 = _w2Clause(c, ctx);
    if (w2 != null) return w2;
    List<String>? m;
    final board = _boardClause(c, ctx);
    if (board != null) return board;

    // Cards.
    m = rx(c, r'(?:you )?draw (a|an|one|two|three|four|five|\d+) cards?');
    if (m != null) return Draw(Who.you, Fixed(numWord(m[1])!));
    m = rx(c, r'(?:you )?draw a card for each (.+)');
    if (m != null) {
      final a = countOf(m[1]);
      if (a == null) return null;
      return Draw(Who.you, a);
    }
    m = rx(c, r'(each player|each opponent|chosen opponent|that player|its player|their player) draws? (a|one|two|three|\d+) cards?');
    if (m != null) return Draw(_who(m[1]), Fixed(numWord(m[2])!));
    m = rx(c, r'draw cards until you have (\d+|the same number of) cards in your hand');
    if (m != null && m[1] != 'the same number of') return Draw(Who.you, Fixed(int.parse(m[1])), untilHandSize: true);
    m = rx(c, r'(each opponent|chosen opponent|each player|you|that player) (?:chooses? and )?discards? (a|one|two|three|\d+) cards?( at random)?');
    if (m != null) return Discard(_who(m[1]), Fixed(numWord(m[2])!), random: m[3].isNotEmpty);
    m = rx(c, r'choose and discard (a|one|two|\d+) cards?');
    if (m != null) return Discard(Who.you, Fixed(numWord(m[1])!));
    m = rx(c, r'(each opponent|each player|you|chosen opponent) discards? (?:your|their|his or her) hand');
    if (m != null) return Discard(_who(m[1]), const Fixed(0), all: true);

    // Lore (CR 1.11).
    m = rx(c, r'(?:you )?gain (\d+) lore');
    if (m != null) return GainLore(Who.you, Fixed(int.parse(m[1])));
    m = rx(c, r'(?:you )?gain (\d+) lore for each (.+)');
    if (m != null) {
      final a = countOf(m[2], per: int.parse(m[1]));
      if (a == null) return null;
      return GainLore(Who.you, a);
    }
    m = rx(c, r'gain lore equal to (.+?) (strength|willpower|lore)');
    if (m != null) {
      final t = ref(m[1].replaceAll(RegExp(r"'s?$"), ''), ctx);
      if (t == null) return null;
      return GainLore(Who.you, StatOf(t, _stat(m[2])));
    }
    m = rx(c, r'(each opponent|chosen opponent|each player|that player) loses? (\d+) lore');
    if (m != null) return LoseLore(_who(m[1]), Fixed(int.parse(m[2])));

    // Damage (CR 1.9).
    m = rx(c, r'deal (\d+) damage to (.+?)(?: for each (.+))?');
    if (m != null) {
      final t = target(m[2], ctx);
      if (t == null) return null;
      Amount a = Fixed(int.parse(m[1]));
      if (m[3].isNotEmpty) {
        final cnt = countOf(m[3], per: int.parse(m[1]));
        if (cnt == null) return null;
        a = cnt;
      }
      return DealDamage(t, a);
    }
    m = rx(c, r'deal damage to (.+?) equal to (.+?) (strength|willpower|lore)');
    if (m != null) {
      final t = target(m[1], ctx);
      final src = ref(m[2].replaceAll(RegExp(r"'s?$"), ''), ctx);
      if (t == null || src == null) return null;
      return DealDamage(t, StatOf(src, _stat(m[3])));
    }
    m = rx(c, r'(.+?) deals? (\d+) damage to (.+)');
    if (m != null && const {'this character', 'he', 'she', 'they', 'it', 'this item'}.contains(m[1])) {
      final t = target(m[3], ctx);
      if (t == null) return null;
      return DealDamage(t, Fixed(int.parse(m[2])));
    }
    m = rx(c, r'put (\d+|a) damage counters? on (.+)');
    if (m != null) {
      final t = target(m[2], ctx);
      if (t == null) return null;
      return DealDamage(t, Fixed(numWord(m[1])!), put: true);
    }
    m = rx(c, r'remove up to (\d+) damage from (.+)');
    if (m != null) {
      final t = target(m[2], ctx);
      if (t == null) return null;
      return RemoveDamage(t, Fixed(int.parse(m[1])));
    }
    m = rx(c, r'remove all damage from (.+)');
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return RemoveDamage(t, const Fixed(0), all: true);
    }
    m = rx(c, r'move (up to )?(\d+) damage(?: counters?)? from (.+?) to (.+)');
    if (m != null) {
      final a = target(m[3], ctx);
      final b = target(m[4], ctx);
      if (a == null || b == null) return null;
      return MoveDamage(a, b, Fixed(int.parse(m[2])), upTo: m[1].isNotEmpty);
    }

    // Moving cards.
    m = rx(c, r'banish (.+)');
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return Banish(t);
    }
    m = rx(c, r"return (.+?) to (?:their|its|his|her|your|their player's|its player's|his player's|her player's) hand");
    if (m != null && !m[1].contains('from your discard') && !m[1].contains('card from')) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return ReturnToHand(t);
    }
    m = rx(c, r'return (a|an|up to (?:\w+)) (.+?) cards? from your discard to your hand');
    if (m != null) {
      final f = filter(_plural(m[2]), Owner.yours, cardTypes: true);
      if (f == null) return null;
      final up = m[1].startsWith('up to');
      return FromDiscardToHand(f, count: up ? numWord(m[1].substring(6))! : 1, upTo: up);
    }
    m = rx(c, r'return (?:a|an) (.+?) card from your discard to your hand');
    if (m != null) {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      if (f == null) return null;
      return FromDiscardToHand(f);
    }
    m = rx(c, r'exert (.+)');
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return Exert(t);
    }
    m = rx(c, r'ready (.+)');
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return Ready(t);
    }
    m = rx(c, r"shuffle (.+?) into (?:their|its|your|his|her|their player's|its player's) deck");
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return ToDeck(t);
    }
    m = rx(c, r"put (.+?) on the (bottom|top) of (?:their|its|your|his|her|their player's|its player's|their players') decks?(?: in any order)?");
    if (m != null && !m[1].startsWith('the top card')) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return ToDeck(t, bottom: m[2] == 'bottom', top: m[2] == 'top');
    }
    m = rx(c, r'put the top card of your deck into your inkwell facedown( and exerted)?');
    if (m != null) return InkTopOfDeck(Who.you, exerted: m[1].isNotEmpty);
    m = rx(c, r'put a card from your hand into your inkwell facedown( and exerted)?');
    if (m != null) return InkFromHand(exerted: m[1].isNotEmpty);
    m = rx(c, r"put (.+?) into (?:your|their|its|their player's|its player's) inkwell facedown( and exerted)?");
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return ToInkwell(t, exerted: m[2].isNotEmpty);
    }
    m = rx(c, r'put the top (\d+|card) cards? of your deck into your discard');
    if (m != null) return Mill(Who.you, m[1] == 'card' ? 1 : int.parse(m[1]));

    // Costs and free plays.
    m = rx(c, r'you pay (\d+) ink less for the next (.+?) you play this turn');
    if (m != null) {
      final f = filter(m[2], Owner.yours, cardTypes: true);
      if (f == null) return null;
      return NextCostReduction(f, int.parse(m[1]));
    }
    m = rx(c, r'play (?:a|an) (.+?)(?: with cost (\d+) or less)?(?: from your discard)? for free(?:, exerted)?');
    if (m != null) {
      var f = filter(m[1], Owner.yours, cardTypes: true);
      if (f == null) return null;
      if (m[2].isNotEmpty) f = f.copyWith(costMax: int.parse(m[2]));
      return PlayFree(f, from: c.contains('from your discard') ? Place.discard : Place.hand);
    }

    // Characteristic changes for a while (CR 6.6).
    m = RegExp(r'^(.+?) (gets?|gains?|can.t|loses?) (.+?)(?: (this turn|until the start of your next turn|during their next turn|for the rest of this turn))?$')
        .firstMatch(c)
        ?.let((x) => [x.group(0)!, x.group(1)!, x.group(2)!, x.group(3)!, x.group(4) ?? '']);
    if (m != null) {
      final dur = switch (m[4]) {
        'this turn' || 'for the rest of this turn' => Lasting.thisTurn,
        'until the start of your next turn' => Lasting.untilYourNextTurn,
        'during their next turn' => Lasting.theirNextTurn,
        _ => null,
      };
      final pred = '${m[2]} ${m[3]}';
      final t = target(m[1], ctx);
      if (t != null) {
        final e = _timedPredicate(pred, t, dur);
        if (e != null) return e;
      }
    }
    return _zoneClause(c, ctx) ?? _w2ClauseLast(c, ctx);
  }

  Effect? _timedPredicate(String p, Target t, Lasting? dur) {
    var m = rx(p, r'gets? ([+-])(\d+) (strength|willpower|lore)(?: and ([+-])(\d+) (strength|willpower|lore))?');
    if (m != null) {
      if (dur == null) return null;
      final a = Modify(t, _stat(m[3]), Fixed(int.parse(m[2])), dur, negative: m[1] == '-');
      if (m[4].isEmpty) return a;
      return Seq([a, Modify(t, _stat(m[6]), Fixed(int.parse(m[5])), dur, negative: m[4] == '-')]);
    }
    m = rx(p, r'gains? (.+)');
    if (m != null) {
      if (dur == null) return null;
      final kws = _keywordList(m[1]);
      if (kws == null) return null;
      final list = [for (final k in kws) GrantKeyword(t, k, dur)];
      return list.length == 1 ? list.first : Seq(list);
    }
    final rule = switch (p) {
      "can't quest" => Rule.cantQuest,
      "can't challenge" => Rule.cantChallenge,
      "can't be challenged" => Rule.cantBeChallenged,
      "can't ready at the start of their next turn" => Rule.cantReady,
      "can't ready" => Rule.cantReady,
      _ => null,
    };
    if (rule != null) {
      final d = p.contains('start of their next turn') ? Lasting.theirNextTurn : dur;
      if (d == null) return null;
      return GrantRule(t, rule, d);
    }
    return null;
  }

  Who _who(String s) => switch (s) {
    'each opponent' => Who.opponents,
    'chosen opponent' => Who.chosenOpponent,
    'each player' => Who.each,
    'that player' || 'its player' || 'their player' => Who.thatPlayer,
    _ => Who.you,
  };

  // -------------------------------------------------------------------------------------------
  // Card references
  // -------------------------------------------------------------------------------------------

  /// A target phrase: "chosen opposing character with 2 {s} or less", "your characters", "him".
  Target? target(String p0, _Ctx ctx) {
    final p = p0.trim();
    final r = ref(p, ctx);
    if (r != null) return r;
    final s4 = _s4Target(p, ctx);
    if (s4 != null) return s4;
    var m = rx(p, r'(another |up to (\w+) )?chosen (.+)');
    if (m != null) {
      final rest = _plural(m[3]);
      final f = filter(rest, Owner.any, cardTypes: true, chosenPhrase: true);
      if (f == null) return null;
      final count = m[2].isEmpty ? 1 : numWord(m[2])!;
      final slot = ctx.nextSlot++;
      return Chosen(m[1] == 'another ' ? f.copyWith(other: true) : f, count: count, upTo: m[2].isNotEmpty, slot: slot);
    }
    m = rx(p, r'(?:all|each|every) (.+)');
    if (m != null) {
      // "each of your characters" is "your characters".
      final f = _groupFilter(m[1].replaceFirst(RegExp(r'^of (?:the )?'), ''));
      if (f == null) return null;
      return AllOf(f, slot: ctx.group());
    }
    // "A character with cost 2 or less", "one of your characters": picked, not "chosen".
    m = rx(p, r'(?:one of your|another|an|a|one) (.+)');
    if (m != null) {
      var rest = m[1];
      var f = filter(_plural(rest), p.startsWith('one of your') ? Owner.yours : Owner.any, cardTypes: true);
      if (f == null) return null;
      if (p.startsWith('another')) f = f.copyWith(other: true);
      return Chosen(f, slot: ctx.nextSlot++, word: false);
    }
    // A plural group: "your characters", "opposing characters", "characters".
    final head = p.split(RegExp(r' (?:with|named|of yours|at|in) ')).first;
    final g = _groupFilter(p);
    if (g != null && (p.startsWith('your ') || p.startsWith('opposing ') || head.endsWith('characters') || head.endsWith('items') || head.endsWith('locations'))) return AllOf(g, slot: ctx.group());
    return null;
  }

  /// "this character", pronouns, "that character", "the challenging character".
  Target? ref(String p, _Ctx ctx) {
    final s4 = _s4Ref(p, ctx);
    if (s4 != null) return s4;
    if (const {'this character', 'this item', 'this location', 'this card'}.contains(p)) {
      ctx.saidThis = true;
      return const This();
    }
    // Pronouns: the card chosen earlier in the ability, else the card itself (CR 1.4.3.2).
    if (const {'him', 'her', 'them', 'it', 'he', 'she', 'they', 'their', 'his', 'its'}.contains(p)) {
      final plural = const {'them', 'they', 'their'}.contains(p);
      // "Ready all your characters. They can't quest": the group, if nothing was chosen since.
      if (plural && ctx.groupSlot != null && ctx.nextSlot == ctx.slotAtGroup) return Remembered(ctx.groupSlot!);
      if (ctx.nextSlot > 0) return Remembered(ctx.nextSlot - 1);
      // "It" is the item or location itself; on a character it means some other card.
      if ((p == 'it' || p == 'its') && card.type == CardType.character) return null;
      // "Whenever an opposing character is exerted, banish them": the card the trigger is about.
      if (ctx.eventOther && !ctx.saidThis) return const EventCard();
      // "They" is never an item or location itself ("banish this location to … give them Evasive").
      if (plural && card.type != CardType.character) return ctx.eventOther ? const EventCard() : null;
      return const This();
    }
    // "That location": where the character moved to, or where the chosen character is.
    if (p == 'that location') {
      if (ctx.eventLocation) return const EventCard(other: true);
      if (ctx.nextSlot > 0) return LocationOf(Remembered(ctx.nextSlot - 1));
      return null;
    }
    // "That character": the one chosen earlier, else the one the trigger is about.
    if (const {'that character', 'that item', 'the chosen character', 'that card'}.contains(p)) {
      if (ctx.nextSlot > 0) return Remembered(ctx.nextSlot - 1);
      if (ctx.event) return const EventCard();
      return null;
    }
    if (p == 'the challenging character' && ctx.eventChallenged) return const EventCard(other: true);
    if (p == 'the challenging character' || p == 'the challenged character' || p == 'the banished character') return const EventCard();
    return null;
  }

  /// A group: "your other Seven Dwarfs characters", "opposing characters", "characters".
  Filter? _groupFilter(String s0) {
    final more = _moreGroup(s0.trim()) ?? _w2Group(s0.trim());
    if (more != null) return more;
    var s = s0.trim();
    var owner = Owner.any;
    var other = false;
    if (s.startsWith('your ')) {
      owner = Owner.yours;
      s = s.substring(5);
    } else if (s.startsWith('opposing ')) {
      owner = Owner.opposing;
      s = s.substring(9);
    }
    if (s.startsWith('other ')) {
      other = true;
      s = s.substring(6);
    }
    final f = filter(_plural(s), owner, cardTypes: true);
    return f?.copyWith(other: other ? true : null);
  }

  /// "opposing character with 2 {s} or less", "damaged character", "item", "Seven Dwarfs
  /// character", "character card with cost 3 or less", "character of yours".
  Filter? filter(String s0, Owner owner, {bool cardTypes = false, bool chosenPhrase = false}) {
    final s4 = _s4Filter(s0.trim(), owner, cardTypes, chosenPhrase);
    if (s4 != null) return s4;
    final w1 = _w1Filter(s0, owner, cardTypes, chosenPhrase);
    if (w1 != null) return w1;
    final w2 = _w2Filter(s0, owner);
    if (w2 != null) return w2;
    var s = s0.trim();
    var f = Filter(owner: owner);
    // Suffixes.
    while (true) {
      var m = RegExp(r'^(.+?) (?:of yours|you have in play)$').firstMatch(s);
      if (m != null) {
        f = f.copyWith(owner: Owner.yours);
        s = m.group(1)!;
        continue;
      }
      m = RegExp(r'^(.+?) with (\d+) (strength|willpower) or (less|more)$').firstMatch(s);
      if (m != null) {
        final n = int.parse(m.group(2)!);
        if (m.group(3) == 'willpower') {
          if (m.group(4) == 'less') return null;
          f = f.copyWith(willpowerMin: n);
          s = m.group(1)!;
          continue;
        }
        f = m.group(4) == 'less' ? f.copyWith(strengthMax: n) : f.copyWith(strengthMin: n);
        s = m.group(1)!;
        continue;
      }
      m = RegExp(r'^(.+?) with cost (\d+) or (less|more)$').firstMatch(s);
      if (m != null) {
        final n = int.parse(m.group(2)!);
        f = m.group(3) == 'less' ? f.copyWith(costMax: n) : f.copyWith(costMin: n);
        s = m.group(1)!;
        continue;
      }
      m = RegExp(r'^(.+?) not named (.+)$').firstMatch(s);
      if (m != null) {
        f = f.copyWith(notNamed: m.group(2));
        s = m.group(1)!;
        continue;
      }
      m = RegExp(r'^(.+?) named (.+)$').firstMatch(s);
      if (m != null) {
        // A name, not the rest of the sentence ("named Pull the Lever! from your discard on…").
        if (RegExp(r' from (?:your|their) | on the (?:top|bottom) | to put ').hasMatch(m.group(2)!)) return null;
        f = f.copyWith(named: m.group(2));
        s = m.group(1)!;
        continue;
      }
      m = RegExp(r'^(.+?) with (evasive|ward|bodyguard|reckless|rush|support|challenger|resist|singer)$').firstMatch(s);
      if (m != null) {
        f = f.copyWith(withKw: Kw.values.firstWhere((k) => k.name == m!.group(2)));
        s = m.group(1)!;
        continue;
      }
      m = RegExp(r'^(.+?) with no damage$').firstMatch(s);
      if (m != null) {
        f = f.copyWith(damaged: false);
        s = m.group(1)!;
        continue;
      }
      m = RegExp(r'^(.+?) at that location$').firstMatch(s);
      if (m != null) {
        f = f.copyWith(atSourcesLocation: true);
        s = m.group(1)!;
        continue;
      }
      m = RegExp(r'^(.+?) at a location$').firstMatch(s);
      if (m != null) {
        f = f.copyWith(atLocation: true);
        s = m.group(1)!;
        continue;
      }
      m = RegExp(r'^(.+?) in play$').firstMatch(s);
      if (m != null) {
        s = m.group(1)!;
        continue;
      }
      break;
    }
    // Prefix qualifiers.
    final words = s.split(' ');
    var i = 0;
    for (; i < words.length; i++) {
      final w = words[i];
      if (w == 'opposing') {
        f = f.copyWith(owner: Owner.opposing);
      } else if (w == 'exerted') {
        f = f.copyWith(exerted: true);
      } else if (w == 'ready') {
        f = f.copyWith(exerted: false);
      } else if (w == 'damaged') {
        f = f.copyWith(damaged: true);
      } else if (w == 'undamaged') {
        f = f.copyWith(damaged: false);
      } else if (w == 'other' || w == 'another') {
        f = f.copyWith(other: true);
      } else if (w == 'a' || w == 'an' || w == 'one') {
        continue;
      } else {
        break;
      }
    }
    var rest = words.skip(i).join(' ');
    if (rest.endsWith(' card')) rest = rest.substring(0, rest.length - 5);
    if (rest.endsWith(' cards')) rest = rest.substring(0, rest.length - 6);
    // Types: "character", "item", "location", "action", "song", "character or location",
    // "character, item, or location", "card".
    final types = <CardType>{};
    var song = false;
    final classList = _classList(rest);
    if (classList != null) return f.copyWith(types: {classList.$1}, classes: classList.$2);
    final typeWords = rest.split(RegExp(r', or |, | or | and/or '));
    final classWords = <String>[];
    for (final tw in typeWords) {
      final ws = tw.trim().split(' ');
      final last = ws.last;
      final t = switch (last) {
        'character' || 'characters' => CardType.character,
        'item' || 'items' => CardType.item,
        'location' || 'locations' => CardType.location,
        'action' || 'actions' => CardType.action,
        'song' || 'songs' => CardType.action,
        'card' || 'cards' => null,
        _ => null,
      };
      if (last == 'song' || last == 'songs') song = true;
      if (t != null) types.add(t);
      if (t == null && last != 'card' && last != 'cards' && last != '') {
        // A bare classification ("Princess") with no type word: not understood.
        return null;
      }
      final cls = ws.sublist(0, ws.length - 1).join(' ').trim();
      if (cls.isNotEmpty) {
        if (cls == 'action' && t == CardType.action) continue;
        // An ink ("Steel characters", CR 5.2.5).
        if (Ink.parse(cls) != null) {
          f = f.copyWith(ink: Ink.parse(cls));
          continue;
        }
        // Only real classifications ("Seven Dwarfs", "Floodborn"), never leftover text.
        if (!knownClassifications.contains(cls)) return null;
        classWords.add(_cap(cls));
      }
    }
    if (types.isEmpty) {
      if (!cardTypes && !rest.contains('card')) return null;
      types.addAll(const {CardType.character, CardType.action, CardType.item, CardType.location});
    }
    return f.copyWith(types: types, classes: classWords.isEmpty ? null : classWords, song: song ? true : null);
  }

  /// "for each [X]": counts cards ("character you have in play", "card in your hand").
  CountOf? countOf(String s0, {int per = 1}) {
    var s = s0.trim();
    final s3 = _s3CountOf(s, per);
    if (s3 != null) return s3;
    final more = _moreCountOf(s, per);
    if (more != null) return more;
    if (s == 'card in your hand' || s == 'card in your opponents\' hands') return null;
    var whose = Owner.yours;
    var place = Place.play;
    var m = RegExp(r'^(.+?) (?:you have )?in (?:your|play)( discard)?$').firstMatch(s);
    if (s.endsWith(' in your discard')) {
      place = Place.discard;
      s = s.substring(0, s.length - 16);
    } else if (s.endsWith(' you have in play')) {
      s = s.substring(0, s.length - 17);
    } else if (s.endsWith(' in play')) {
      whose = Owner.any;
      s = s.substring(0, s.length - 8);
    } else if (m == null && s.startsWith('opposing ')) {
      whose = Owner.opposing;
    }
    final f = filter(s, s.startsWith('opposing') ? Owner.opposing : (whose == Owner.any ? Owner.any : Owner.yours), cardTypes: true);
    if (f == null) return null;
    return CountOf(f, place: place, whose: f.owner == Owner.opposing ? Owner.opposing : whose, per: per);
  }

  String _cap(String s) => s.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
}

/// Parse context within one ability: remembered choices and whether there's an event card.
class _Ctx {
  _Ctx({this.event = false, this.eventOther = false, this.eventLocation = false, this.eventChallenged = false});
  final bool event;

  /// The trigger is a move, so "that location" is where the character moved to.
  final bool eventLocation;

  /// The trigger is about being challenged, so "the challenging character" is the other card.
  final bool eventChallenged;

  /// Slice 2's name for [eventChallenged].
  bool get challengedEvent => eventChallenged;

  /// The trigger is about another card, so "he", "she", "they" mean that card.
  final bool eventOther;

  /// "This character" came up already, so later pronouns mean it ("ready this character. He
  /// can't quest").
  bool saidThis = false;

  /// The trigger is "is challenged", so "the challenging character" is the other card.
  bool s4Challenged = false;
  int nextSlot = 0;

  /// The last group ("all your characters") and how many choices came before it.
  int? groupSlot;
  int slotAtGroup = 0;
  int _groups = 0;
  int group() {
    slotAtGroup = nextSlot;
    return groupSlot = groupSlots + _groups++;
  }

  int save() => nextSlot;
  void restore(int s) => nextSlot = s;
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
