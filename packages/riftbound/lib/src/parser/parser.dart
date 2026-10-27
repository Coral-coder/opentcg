/// Reads rules text into abilities (ir.dart). Strict: a line counts only if every word of it is
/// understood; a card is supported only if all its lines are (and its type is playable).
library;

import '../cards/card.dart';
import '../ir.dart';

part 'power.dart';
part 'hidden.dart';

/// Bumped whenever parsing or the engine changes what a saved game would replay to.
const riftboundEngineVersion = 3;

class ParsedCard {
  ParsedCard(this.abilities, this.unsupported);
  final List<Ability> abilities;

  /// Lines (or reasons) the engine can't play yet.
  final List<String> unsupported;
  bool get supported => unsupported.isEmpty;

  int kw(Kw k) {
    var n = 0;
    for (final a in abilities) {
      if (a is KeywordAb && a.kw == k) n += a.n;
    }
    return n;
  }

  bool has(Kw k) => abilities.any((a) => a is KeywordAb && a.kw == k);

  Timing get timing => has(Kw.reaction) ? Timing.reaction : (has(Kw.action) ? Timing.action : Timing.normal);
}

class RiftboundParser {
  static final Map<String, ParsedCard> _cache = {};

  static ParsedCard parse(RCard c) => _cache.putIfAbsent(c.key, () => parseUncached(c));

  static void clearCache() => _cache.clear();

  static ParsedCard parseUncached(RCard c) {
    final abilities = <Ability>[];
    final unsupported = <String>[];
    if (c.type == CardType.rune) return ParsedCard(const [], const []);
    // Target slots are numbered across the whole card.
    final slots = [0];
    for (final line in c.text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final a = _Line(c, slots).parse(line.trim());
      if (a == null) {
        unsupported.add(line.trim());
      } else {
        abilities.addAll(a);
      }
    }
    _powerPost(c, abilities);
    if (c.type == CardType.spell && !abilities.any((a) => a is SpellBody)) {
      if (unsupported.isEmpty) unsupported.add('(a spell with no instructions)');
    }
    return ParsedCard(abilities, unsupported);
  }
}

final _kwNames = {
  'accelerate': Kw.accelerate,
  'action': Kw.action,
  'reaction': Kw.reaction,
  'assault': Kw.assault,
  'shield': Kw.shield,
  'tank': Kw.tank,
  'ganking': Kw.ganking,
  'deflect': Kw.deflect,
  'temporary': Kw.temporary,
  'vision': Kw.vision,
  'backline': Kw.backline,
  'hidden': Kw.hidden,
  'ambush': Kw.ambush,
  'unique': Kw.unique,
};

const _numbers = {'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5};

int? _num(String s) => int.tryParse(s) ?? _numbers[s.toLowerCase()];

/// Parses one line (one ability) of a card.
class _Line {
  _Line(this.card, this._slotCounter) : _first = _slotCounter[0];
  final RCard card;

  /// The card's slot counter, and the first slot this line used ("it" refers within the line).
  final List<int> _slotCounter;
  final int _first;

  /// The trigger being parsed is about a unit ("it" means that unit).
  bool _eventUnit = false;

  /// The trigger is about a battlefield ("that battlefield").
  bool _eventBf = false;

  bool get _isSpell => card.type == CardType.spell;
  bool get _isBattlefield => card.type == CardType.battlefield;

  List<Ability>? parse(String line) {
    var t = line;
    // Leading keyword tokens: "[Accelerate]", "[Assault 2]", "[Action] Deal 2 to …".
    final out = <Ability>[];
    while (true) {
      final m = RegExp(r'^\[([A-Za-z-]+)(?: (\d+))?\](?!\[>\])\s*').firstMatch(t);
      if (m == null) break;
      final name = m[1]!.toLowerCase();
      final kw = _kwNames[name];
      if (kw == null) break;
      if (!_validKeyword(kw)) return null;
      out.add(KeywordAb(m[0]!.trim(), kw, int.tryParse(m[2] ?? '') ?? 1));
      t = t.substring(m.end);
    }
    if (t.isEmpty) return out;
    final pw = _powerLine(t, line);
    if (pw != null) return [...out, ...pw];
    // "[Repeat] {2}{R}".
    final rep = RegExp(r'^\[Repeat\]\s*((?:\{[0-9A-Z]+\})+)$').firstMatch(t);
    if (rep != null) {
      final cost = _cost(rep[1]!);
      if (cost == null || !_isSpell) return null;
      return [...out, RepeatCost(line, cost)];
    }
    final h = _hLine(t, line);
    if (h != null) return [...out, ...h];
    final a = _ability(t, line);
    if (a == null) return null;
    return [...out, a];
  }

  static String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  bool _validKeyword(Kw kw) => switch (kw) {
        Kw.action => _isSpell,
        // Reaction is on cards of any type (CR 813.1.a); playing a unit with it keeps a unit's
        // places (CR 813.3.a).
        Kw.reaction => _isSpell || card.isPermanent,
        Kw.hidden => card.isMainDeck,
        Kw.ambush => card.type == CardType.unit,
        Kw.unique => card.isMainDeck,
        Kw.accelerate || Kw.assault || Kw.shield || Kw.tank || Kw.ganking || Kw.backline => card.type == CardType.unit,
        Kw.deflect || Kw.temporary || Kw.vision => card.isPermanent,
      };

  Ability? _ability(String t, String line) {
    if (t == 'I must be assigned combat damage last.' && card.type == CardType.unit) return KeywordAb(line, Kw.backline);
    if (_isSpell) {
      final e = _effects(t);
      return e == null ? null : SpellBody(line, e);
    }
    // Deathknell (CR 808) and Legion (CR 812).
    var m = RegExp(r'^\[Deathknell\](?:\[>\]| -)\s*(.+)$').firstMatch(t);
    if (m != null) {
      if (!card.isPermanent) return null;
      final e = _effects(_cap(m[1]!));
      return e == null ? null : Triggered(line, const When(On.die), e);
    }
    m = RegExp(r'^\[Legion\](?:\[>\]| -)\s*(When you play (?:me|this), .+)$').firstMatch(t);
    if (m != null) {
      final a = _ability(m[1]!, line);
      return a is Triggered ? Triggered(line, a.on, a.effects, legion: true) : null;
    }
    // Triggered abilities.
    m = RegExp(r'^(When|At) ([^,]+), (.+)$').firstMatch(t);
    if (m != null) {
      final on = _when('${m[1]} ${m[2]}') ?? _powerWhen('${m[1]} ${m[2]}');
      if (on == null) return null;
      _eventUnit = on.on == On.enemyAttacksYourBf || _PowerLine.eventUnitTrigger(on.on);
      _eventBf = const {On.youConquer, On.youHold, On.conquerHere, On.holdHere}.contains(on.on);
      final e = _effects(_cap(m[3]!));
      return e == null ? null : Triggered(line, on, e);
    }
    // Activated abilities: "{1}, {E}: [Action] - Draw 1." / "[Reaction][>] Kill this, {E}: [Add] {A}."
    m = RegExp(r'^(?:\[(Action|Reaction)\]\[>\] )?([^:]+?): (?:\[(Action|Reaction)\](, \[Legion\])? - )?(.+)$').firstMatch(t);
    if (m != null && !_isBattlefield) {
      final cost = _cost(m[2]!);
      if (cost != null) {
        final timingWord = (m[1] ?? m[3])?.toLowerCase();
        var body = m[5]!;
        var once = false, spellsOnly = false;
        const onceText = ' Use only once per turn.';
        if (body.endsWith(onceText)) {
          once = true;
          body = body.substring(0, body.length - onceText.length);
        }
        const spellsText = ' Use only to play spells.';
        if (body.endsWith(spellsText)) {
          spellsOnly = true;
          body = body.substring(0, body.length - spellsText.length);
        }
        var e = _effects(_cap(body));
        if (e == null) return null;
        if (spellsOnly) {
          if (e.length != 1 || e.first is! AddRes) return null;
          final a = e.first as AddRes;
          e = [AddRes(energy: a.energy, anyPower: a.anyPower, spellsOnly: true)];
        }
        return Activated(line, cost, e, timing: timingWord == 'reaction' ? Timing.reaction : (timingWord == 'action' ? Timing.action : Timing.normal), oncePerTurn: once, legion: m[4] != null);
      }
    }
    final p = _passive(t);
    return p == null ? null : Static(line, p);
  }

  When? _when(String s) {
    final hidden = _hWhen(s);
    if (hidden != null) return hidden;
    final me = card.type == CardType.unit;
    final perm = card.isPermanent;
    return switch (s) {
      'When you play me' when me => const When(On.played),
      'When you play this' when card.type == CardType.gear => const When(On.played),
      'When I attack' when me => const When(On.attack),
      'When I defend' when me => const When(On.defend),
      'When I attack or defend' when me => const When(On.attackOrDefend),
      'When I conquer' when me => const When(On.conquer),
      'When I hold' when me => const When(On.hold),
      'When I move' when me => const When(On.move),
      'When I move to a battlefield' when me => const When(On.move, moveToBattlefield: true),
      'When I win a combat' when me => const When(On.winCombat),
      'When you win a combat' when perm || card.type == CardType.legend => const When(On.youWinCombat),
      'When you conquer' when perm || card.type == CardType.legend => const When(On.youConquer),
      'When you hold' when perm || card.type == CardType.legend => const When(On.youHold),
      'When you conquer here' when _isBattlefield => const When(On.conquerHere),
      'When you hold here' when _isBattlefield => const When(On.holdHere),
      'At the start of your turn' when perm || card.type == CardType.legend => const When(On.startOfTurn),
      'At the end of your turn' when perm || card.type == CardType.legend => const When(On.endOfTurn),
      'When you play a spell' when perm || card.type == CardType.legend => const When(On.youPlaySpell),
      'When you play a unit' when perm || card.type == CardType.legend => const When(On.youPlayUnit),
      'When you stun one or more enemy units' when perm || card.type == CardType.legend => const When(On.youStunEnemy),
      'When an enemy unit attacks a battlefield you control' when perm || card.type == CardType.legend => const When(On.enemyAttacksYourBf),
      'At start of your Beginning Phase' when perm || card.type == CardType.legend => const When(On.startOfTurn),
      _ => null,
    };
  }

  Passive? _passive(String t) {
    final hidden = _hPassive(t);
    if (hidden != null) return hidden;
    if (card.type == CardType.gear && t == 'This enters exhausted.') return const EntersExhausted();
    var lm = RegExp(r'^While a friendly unit defends alone, it gets \+(\d+) \{M\}\.$').firstMatch(t);
    if (lm != null && (card.type == CardType.legend || card.isPermanent)) return DefendsAlone(int.parse(lm[1]!));
    lm = RegExp(r'^Your ([A-Z][a-z]+)s have \[([A-Za-z]+)(?: (\d+))?\]\.$').firstMatch(t);
    if (lm != null && (card.type == CardType.legend || card.isPermanent)) {
      final kw = _kwNames[lm[2]!.toLowerCase()];
      if (kw == null || !const {Kw.shield, Kw.assault, Kw.tank, Kw.ganking, Kw.deflect}.contains(kw)) return null;
      return KwAnthem(kw, int.tryParse(lm[3] ?? '') ?? 1, Filter(side: Side.friendly, tag: lm[1]));
    }
    lm = RegExp(r'^\[Legion\] - I cost \{(\d+)\} less\.$').firstMatch(t);
    if (lm != null && card.isMainDeck) return CostLess(int.parse(lm[1]!), legion: true);
    if (card.type == CardType.unit && t == 'I enter ready.') return const EntersReady();
    if (card.type == CardType.unit && t == "I don't deal combat damage.") return const NoCombatDamage();
    var m = RegExp(r'^Other friendly units( here)? have \+(\d+) \{M\}( here)?\.$').firstMatch(t);
    if (m != null && card.type == CardType.unit) {
      final here = m[1] != null || m[3] != null;
      return Anthem(int.parse(m[2]!), Filter(side: Side.friendly, other: true, where: here ? Where.here : Where.anywhere));
    }
    m = RegExp(r'^Your ([A-Z][a-z]+)s have \+(\d+) \{M\}\.$').firstMatch(t);
    if (m != null && card.isPermanent) return Anthem(int.parse(m[2]!), Filter(side: Side.friendly, tag: m[1]));
    return null;
  }

  /// "{2}{R}, {E}" → a cost; null if any part isn't understood.
  Cost? _cost(String s) {
    var energy = 0;
    final power = <Domain?>[];
    var exhaust = false, killMe = false;
    final extra = <CostPart>[];
    for (final part in s.split(', ')) {
      final x = _powerCostPart(part);
      if (x != null) {
        extra.add(x);
        continue;
      }
      if (part == '{E}') {
        exhaust = true;
        continue;
      }
      if (part == 'Kill this' && card.type == CardType.gear) {
        killMe = true;
        continue;
      }
      if (!RegExp(r'^(\{[0-9A-Z]+\})+$').hasMatch(part)) return null;
      for (final m in RegExp(r'\{([0-9A-Z]+)\}').allMatches(part)) {
        final v = m[1]!;
        final n = int.tryParse(v);
        if (n != null) {
          energy += n;
        } else if (v == 'A') {
          power.add(null);
        } else if (v == 'C') {
          if (card.domains.length != 1) return null;
          power.add(card.domains.first);
        } else {
          final d = Domain.byName(v);
          if (d == null) return null;
          power.add(d);
        }
      }
    }
    return Cost(energy: energy, power: power, exhaust: exhaust, killMe: killMe, extra: extra);
  }

  /// Sentences → effects; null if any sentence isn't understood.
  List<Effect>? _effects(String text) {
    final out = <Effect>[];
    for (final s in _sentences(text)) {
      final e = _sentence(s);
      if (e == null) return null;
      final merged = _powerMerge(out, e);
      if (merged == false) return null;
      if (merged == null) out.addAll(e);
    }
    return out.isEmpty ? null : out;
  }

  static List<String> _sentences(String t) {
    final out = <String>[];
    var start = 0;
    for (var i = 0; i < t.length; i++) {
      if (t[i] == '.' && (i + 1 == t.length || t[i + 1] == ' ' || RegExp(r'[A-Z\[]').hasMatch(t[i + 1]))) {
        out.add(t.substring(start, i).trim());
        start = i + 1;
      }
    }
    if (start < t.length && t.substring(start).trim().isNotEmpty) out.add(t.substring(start).trim());
    return [for (final s in out) if (s.isNotEmpty) s];
  }

  /// One sentence: this family's forms that must come first, the core forms, then this family's
  /// other forms (parser/power.dart).
  List<Effect>? _sentence(String s0) {
    final early = _powerSentenceEarly(s0);
    if (early != null) return early;
    final slot = _slotCounter[0];
    final core = _sentenceCore(s0);
    if (core != null) return core;
    _slotCounter[0] = slot;
    return _powerSentence(s0);
  }

  List<Effect>? _sentenceCore(String s0) {
    var s = s0;
    final hidden = _hSentence(s);
    if (hidden != null) return hidden;
    if (s.startsWith('You may ')) {
      final inner = _sentence('${s[8].toUpperCase()}${s.substring(9)}');
      return inner == null ? null : [May(inner)];
    }
    // "X, then Y" / "X and Y".
    final then = s.indexOf(', then ');
    if (then > 0) {
      final a = _sentence(s.substring(0, then));
      final b = _sentence('${s[then + 7].toUpperCase()}${s.substring(then + 8)}');
      return a == null || b == null ? null : [...a, ...b];
    }
    // "If …, X" / "X if …".
    var m = RegExp(r'^If (.+?), (.+)$').firstMatch(s);
    if (m != null) {
      final c = _cond(m[1]!);
      final e = c == null ? null : _sentence(_cap(m[2]!));
      return e == null ? null : [If(c!, e)];
    }
    m = RegExp(r'^(.+?) if (you have .+)$').firstMatch(s);
    if (m != null) {
      final c = _cond(m[2]!);
      final e = c == null ? null : _sentence(m[1]!);
      return e == null ? null : [If(c!, e)];
    }
    m = RegExp(r'^Ready (\d+) runes$').firstMatch(s);
    if (m != null) return [ReadyRunes(int.parse(m[1]!))];
    m = RegExp(r'^Move (.+) to or from (?:its|their) base$').firstMatch(s);
    if (m != null) {
      final t = _target(m[1]!);
      return t == null ? null : [ToOrFromBase(t)];
    }
    m = RegExp(r'^Give (.+?) -(\d+) \{M\} this turn, to a minimum of (\d+) \{M\}$').firstMatch(s);
    if (m != null) {
      final t = _target(m[1]!);
      return t == null ? null : [GiveMight(-int.parse(m[2]!), t, min: int.parse(m[3]!))];
    }
    m = RegExp(r'^Draw (\d+) and channel (\d+) runes? exhausted$').firstMatch(s);
    if (m != null) return [Draw(int.parse(m[1]!)), Channel(int.parse(m[2]!), exhausted: true)];
    m = RegExp(r'^Draw (\d+)$').firstMatch(s);
    if (m != null) return [Draw(int.parse(m[1]!))];
    m = RegExp(r'^Discard (\d+)$').firstMatch(s);
    if (m != null) return [Discard(int.parse(m[1]!))];
    m = RegExp(r'^Channel (\d+) runes?( exhausted)?$').firstMatch(s);
    if (m != null) return [Channel(int.parse(m[1]!), exhausted: m[2] != null)];
    m = RegExp(r'^(?:You score|Score) (\d+) points?$').firstMatch(s);
    if (m != null) return [GainPoints(int.parse(m[1]!))];
    m = RegExp(r'^\[?Predict(?: (\d+))?\]?$').firstMatch(s);
    if (m != null) return [Predict(int.tryParse(m[1] ?? '') ?? 1)];
    if (s == 'Counter a spell' && _isSpell) return [const Counter()];
    m = RegExp(r'^\[Add\] ((?:\{[0-9A]\})+)$').firstMatch(s);
    if (m != null) {
      var energy = 0, any = 0;
      for (final x in RegExp(r'\{([0-9A])\}').allMatches(m[1]!)) {
        if (x[1] == 'A') {
          any++;
        } else {
          energy += int.parse(x[1]!);
        }
      }
      return [AddRes(energy: energy, anyPower: any)];
    }
    // Damage.
    m = RegExp(r'^Deal (\d+) to (.+)$').firstMatch(s);
    if (m != null) {
      final t = _target(m[2]!);
      return t == null ? null : [Deal(N(int.parse(m[1]!)), t)];
    }
    m = RegExp(r'^Deal damage equal to my Might to (.+)$').firstMatch(s);
    if (m != null && card.type == CardType.unit) {
      final t = _target(m[1]!);
      return t == null ? null : [Deal(const MyMight(), t)];
    }
    // Might and keywords this turn.
    m = RegExp(r'^Give (.+?) ([+-])(\d+) \{M\} this turn$').firstMatch(s);
    if (m != null) {
      final t = _target(m[1]!);
      final n = int.parse(m[3]!) * (m[2] == '-' ? -1 : 1);
      // A decrease without "to a minimum of" can make Might negative; it's treated as 0 (CR 143.2.c).
      return t == null ? null : [GiveMight(n, t)];
    }
    m = RegExp(r'^Give (.+?) \[([A-Za-z]+)(?: (\d+))?\] this turn$').firstMatch(s);
    if (m != null) {
      final kw = _kwNames[m[2]!.toLowerCase()];
      final t = _target(m[1]!);
      if (kw == null || t == null || !const {Kw.assault, Kw.shield, Kw.tank, Kw.ganking, Kw.deflect, Kw.backline}.contains(kw)) return null;
      return [GiveKw(kw, int.tryParse(m[3] ?? '') ?? 1, t)];
    }
    // Single-verb effects on a target.
    m = RegExp(r'^\[?(Buff|Ready|Exhaust|Stun|Kill|Recall|Heal)\]? (.+)$').firstMatch(s);
    if (m != null) {
      final t = _target(m[2]!);
      if (t == null) return null;
      return [
        switch (m[1]!) {
          'Buff' => Buff(t),
          'Ready' => Ready(t),
          'Exhaust' => Exhaust(t),
          'Stun' => Stun(t),
          'Kill' => Kill(t),
          'Recall' => ToBase(t, asMove: false),
          _ => Heal(t),
        },
      ];
    }
    m = RegExp(r"^Move (.+) to (?:its|their) base$").firstMatch(s);
    if (m != null) {
      final t = _target(m[1]!);
      return t == null ? null : [ToBase(t)];
    }
    m = RegExp(r"^Return (.+) to (?:its|their) owner's hand$").firstMatch(s);
    if (m != null) {
      final t = _target(m[1]!);
      return t == null ? null : [ToHand(t)];
    }
    // Tokens (CR 187).
    m = RegExp(r'^Play (a|an|one|two|three|\d+)( ready)? (\d+) \{M\} (Recruit|Sprite|Sand Soldier|Mech|Bird|Tentacle) unit tokens?( with \[Temporary\])?( here| to your base)?$').firstMatch(s);
    if (m != null) {
      final count = _num(m[1]!);
      final token = m[4]!;
      final might = int.parse(m[3]!);
      const mights = {'Recruit': 1, 'Sprite': 3, 'Sand Soldier': 2, 'Mech': 3, 'Bird': 1, 'Tentacle': 1};
      if (count == null || mights[token] != might) return null;
      if (m[5] != null && token != 'Sprite') return null;
      final here = m[6] == ' here';
      if (here && card.type != CardType.unit) return null;
      return [PlayToken(token, count, here: here, ready: m[2] != null)];
    }
    m = RegExp(r'^Play (a|an|one|two|\d+) Gold gear tokens?( exhausted)?$').firstMatch(s);
    if (m != null) {
      final count = _num(m[1]!);
      return count == null ? null : [PlayToken('Gold', count, ready: m[2] == null)];
    }
    return null;
  }

  Cond? _cond(String c) {
    final hidden = _hCond(c);
    if (hidden != null) return hidden;
    if (c == 'you have one or fewer cards in your hand') return const HandAtMost(1);
    final m = RegExp(r'^you have (\d+)\+ units at that battlefield$').firstMatch(c);
    if (m != null && _eventBf) return UnitsThere(int.parse(m[1]!));
    return _powerCond(c);
  }

  /// A target phrase → a target; null if not understood.
  Target? _target(String p) {
    p = p.trim();
    final pw = _powerTarget(p);
    if (pw != null) return pw;
    final hidden = _hTarget(p);
    if (hidden != null) return hidden;
    if (p == 'me' && card.type == CardType.unit) return const Me();
    if (p == 'this' && card.type == CardType.gear) return const Me();
    if (p == 'it' || p == 'that unit') {
      if (_slotCounter[0] > _first) return Chosen(_slotCounter[0] - 1);
      if (_eventUnit) return const EventUnit();
      return null;
    }
    // "all/each … units …" → every matching unit.
    var m = RegExp(r'^(?:all|each) (.+)$').firstMatch(p);
    if (m != null) {
      final f = _filter(m[1]!, plural: true);
      return f == null ? null : Each(f);
    }
    if (RegExp(r'^(friendly|enemy) units( here| at a battlefield)?$').hasMatch(p)) {
      final f = _filter(p, plural: true);
      return f == null ? null : Each(f);
    }
    var upTo = false;
    m = RegExp(r'^up to one (.+)$').firstMatch(p);
    if (m != null) {
      upTo = true;
      p = 'a ${m[1]}';
    }
    m = RegExp(r'^(?:a|an|another) (.+)$').firstMatch(p);
    if (m != null) {
      var f = _filter(m[1]!, plural: false);
      if (f == null) return null;
      if (p.startsWith('another')) f = Filter(side: f.side, where: f.where, gear: f.gear, mightMax: f.mightMax, mightMin: f.mightMin, other: true, exhausted: f.exhausted, attacking: f.attacking, defending: f.defending, tag: f.tag, buffed: f.buffed);
      if (f.other && card.type != CardType.unit) return null;
      return Choose(f, slot: _slotCounter[0]++, upTo: upTo);
    }
    return null;
  }

  /// "enemy unit here with 3 {M} or less" → a filter.
  Filter? _filter(String p, {required bool plural}) {
    var side = Side.any;
    var where = Where.anywhere;
    bool? exhausted, buffed;
    var attacking = false, defending = false, gear = false;
    int? mightMax, mightMin;
    var s = p.trim();
    // Trailing qualifiers.
    var m = RegExp(r' with (\d+) \{M\} or (less|more)$').firstMatch(s);
    if (m != null) {
      if (m[2] == 'less') {
        mightMax = int.parse(m[1]!);
      } else {
        mightMin = int.parse(m[1]!);
      }
      s = s.substring(0, m.start);
    }
    if (s.endsWith(' here')) {
      if (card.type != CardType.unit && !_isBattlefield) return null;
      where = Where.here;
      s = s.substring(0, s.length - 5);
    } else if (s.endsWith(' at a battlefield')) {
      where = Where.battlefield;
      s = s.substring(0, s.length - 17);
    } else if (s.endsWith(' in a base') || s.endsWith(' in your base')) {
      if (s.endsWith(' in your base')) side = Side.friendly;
      where = Where.base;
      s = s.substring(0, s.lastIndexOf(' in '));
    } else if (s.endsWith(' you control')) {
      side = Side.friendly;
      s = s.substring(0, s.length - 12);
    }
    final words = s.split(' ');
    final noun = words.removeLast();
    if (noun == (plural ? 'units' : 'unit')) {
      gear = false;
    } else if (noun == 'gear') {
      gear = true;
    } else {
      return null;
    }
    for (final w in words) {
      switch (w) {
        case 'friendly':
          side = Side.friendly;
        case 'enemy':
          side = Side.enemy;
        case 'exhausted':
          exhausted = true;
        case 'ready':
          exhausted = false;
        case 'attacking':
          attacking = true;
        case 'defending':
          defending = true;
        case 'buffed':
          buffed = true;
        default:
          return null;
      }
    }
    if (gear && (attacking || defending || mightMax != null || mightMin != null || buffed != null)) return null;
    return Filter(side: side, where: where, gear: gear, mightMax: mightMax, mightMin: mightMin, exhausted: exhausted, attacking: attacking, defending: defending, buffed: buffed);
  }
}
