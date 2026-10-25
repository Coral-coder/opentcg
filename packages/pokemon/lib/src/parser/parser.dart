/// Card text → IR. Attack, Ability, Trainer, Tool and Special Energy texts are split into
/// sentences and read with patterns; what isn't understood is recorded per card, and a card is
/// supported only when everything on it is.
library;

import '../cards/card.dart';
import '../ir.dart';

/// Bumped whenever the parser could read the same card differently (peers compare it).
const pokemonEngineVersion = 1;

class ParsedCard {
  ParsedCard(this.card, {required this.attacks, required this.abilities, this.trainer, this.tool, this.provides, required this.unsupported});
  final PCard card;

  /// One per attack, in order; null where the attack's text isn't understood.
  final List<Eff?> attacks;
  final List<AbilityIR?> abilities;
  final Eff? trainer;
  final ToolIR? tool;

  /// What a Special Energy provides.
  final PType? provides;
  final List<String> unsupported;
  bool get supported => unsupported.isEmpty;
}

class PokemonParser {
  static final Map<String, ParsedCard> _cache = {};

  /// When set, collects the sentences that failed (bin/gaps.dart).
  static List<String>? diag;

  static ParsedCard parse(PCard c) => _cache.putIfAbsent(c.key, () => _parse(c));
  static void clearCache() => _cache.clear();

  static ParsedCard _parse(PCard c) {
    final un = <String>[];
    final attacks = <Eff?>[];
    for (final a in c.attacks) {
      final e = attackText(a);
      if (e == null) un.add('${a.name}: ${a.text}');
      attacks.add(e);
    }
    final abilities = <AbilityIR?>[];
    for (final a in c.abilities) {
      final ab = ability(a.text);
      if (ab == null) un.add('${a.name}: ${a.text}');
      abilities.add(ab);
    }
    Eff? trainer;
    ToolIR? tool;
    PType? provides;
    if (c.isTrainer) {
      if (c.trainer == TrainerKind.tool) {
        tool = toolText(c.text);
        if (tool == null) un.add(c.text);
      } else if (c.trainer == TrainerKind.stadium) {
        un.add('Stadium: ${c.text}');
      } else {
        trainer = effects(c.text, trainer: true);
        if (trainer == null) un.add(c.text);
      }
    }
    if (c.isEnergy && !c.basicEnergy) {
      provides = specialEnergy(c.text);
      if (provides == null) un.add(c.text);
    }
    for (final r in c.rules) {
      if (!_knownRule(r)) un.add(r);
    }
    return ParsedCard(c, attacks: attacks, abilities: abilities, trainer: trainer, tool: tool, provides: provides, unsupported: un);
  }

  /// Rule boxes and reminder lines the engine knows by heart.
  static bool _knownRule(String r) {
    final t = r.toLowerCase().replaceAll('’', "'");
    return t.startsWith('pokémon ex rule') ||
        t.startsWith('mega evolution ex rule') ||
        t.startsWith('tera:') ||
        t.startsWith('ace spec') ||
        t.startsWith("you can't have more than 1 ace spec") ||
        // The Tera rule box and the ex / Mega ex rule boxes without their headings.
        t.startsWith('as long as this pokémon is on your bench, prevent all damage done to this pokémon by attacks') ||
        t.startsWith('when your pokémon ex is knocked out, your opponent takes 2 prize cards') ||
        t.startsWith('when your mega evolution pokémon ex is knocked out, your opponent takes 3 prize cards') ||
        t.startsWith('you may play any number of item cards') ||
        t.startsWith('you may play only 1 supporter card') ||
        t.startsWith('you may play only 1 stadium card') ||
        t.startsWith('you may attach any number of pokémon tools') ||
        t.startsWith("attach a pokémon tool to 1 of your pokémon that doesn't already have");
  }

  // -------------------------------------------------------------------------------------------
  // Attacks
  // -------------------------------------------------------------------------------------------

  static Eff? attackText(Attack a) {
    final text = a.text.trim();
    final steps = <Eff>[];
    if (text.isNotEmpty) {
      final e = effects(text);
      if (e == null) return null;
      steps.add(e);
    }
    // "30×" needs something that sets the damage.
    if (a.mod == '×' && !_has(steps, (e) => e is DamagePer)) {
      _fail('× damage without a "for each": ${a.text}');
      return null;
    }
    return Seq(steps);
  }

  static bool _has(List<Eff> steps, bool Function(Eff) test) {
    for (final e in steps) {
      if (test(e)) return true;
      if (e is Seq && _has(e.steps, test)) return true;
      if (e is IfHeads && _has([e.then], test)) return true;
      if (e is IfTails && _has([e.then], test)) return true;
      if (e is IfCheck && _has([e.then], test)) return true;
    }
    return false;
  }

  static Eff? _fail(String s) {
    diag?.add(s);
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Effects: sentences
  // -------------------------------------------------------------------------------------------

  /// A text of one or more sentences. [trainer]: written from the player's side ("your Active
  /// Pokémon", no "this Pokémon").
  static Eff? effects(String text, {bool trainer = false}) {
    final ss = sentences(_norm(text));
    final out = <Eff>[];
    for (var i = 0; i < ss.length; i++) {
      var s = ss[i];
      if (_reminders.contains(s)) continue;
      // "Then, shuffle your deck." after a search is part of it.
      if ((s == 'then, shuffle your deck' || s == 'shuffle your deck afterward') && out.isNotEmpty && (out.last is Search)) continue;
      if (s == '(your opponent chooses the new active pokémon.)' || s == 'your opponent chooses the new active pokémon') continue;
      if (s.startsWith('then, ')) s = s.substring(6);
      final e = sentence(s, trainer: trainer);
      if (e == null) return _fail(s);
      out.add(e);
    }
    if (out.isEmpty) return null;
    return out.length == 1 ? out.first : Seq(out);
  }

  static const _reminders = {
    "(don't apply weakness and resistance for benched pokémon.)",
    "don't apply weakness and resistance for benched pokémon",
    '(this includes new pokémon that come into play.)',
    '(you can use more than 1 gx attack in a game.)',
  };

  static String _norm(String t) => t
      .toLowerCase()
      .replaceAll('pokemon', 'pokémon')
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Splits on sentence ends, keeping parenthetical reminders as their own sentences.
  static List<String> sentences(String t) {
    final out = <String>[];
    var start = 0, depth = 0;
    for (var i = 0; i < t.length; i++) {
      final ch = t[i];
      if (ch == '(') depth++;
      if (ch == ')') {
        depth--;
        if (depth == 0) {
          final s = t.substring(start, i + 1).trim();
          if (s.isNotEmpty) out.add(s);
          start = i + 1;
        }
      }
      if (ch == '.' && depth == 0 && (i + 1 == t.length || t[i + 1] == ' ')) {
        final s = t.substring(start, i).trim();
        if (s.isNotEmpty) out.add(s);
        start = i + 1;
      }
    }
    final rest = t.substring(start).trim();
    if (rest.isNotEmpty) out.add(rest.endsWith('.') ? rest.substring(0, rest.length - 1) : rest);
    // A parenthetical opening a sentence: "(… .)" sentences keep the dot inside.
    return [for (final s in out) s.startsWith('(') && !s.endsWith(')') ? '$s)' : s];
  }

  static int? _num(String s) => switch (s) {
        'a' || 'an' || 'one' || '1' => 1,
        'two' => 2,
        'three' => 3,
        'four' => 4,
        'five' => 5,
        'six' => 6,
        _ => int.tryParse(s),
      };

  static List<String>? rx(String s, String pattern) {
    final m = RegExp('^$pattern\$').firstMatch(s);
    if (m == null) return null;
    return [for (var i = 0; i <= m.groupCount; i++) m.group(i) ?? ''];
  }

  static const _types = 'grass|fire|water|lightning|psychic|fighting|darkness|metal|dragon|fairy|colorless';
  static PType? _type(String s) => s.isEmpty ? null : PType.byLabel(s.trim());

  static Cond? _cond(String s) => switch (s.trim()) {
        'asleep' => Cond.asleep,
        'burned' => Cond.burned,
        'confused' => Cond.confused,
        'paralyzed' => Cond.paralyzed,
        'poisoned' => Cond.poisoned,
        _ => null,
      };

  static List<Cond>? _conds(String s) {
    final parts = s.split(RegExp(r', and |, | and '));
    final out = <Cond>[];
    for (final p in parts) {
      final c = _cond(p);
      if (c == null) return null;
      out.add(c);
    }
    return out;
  }

  static Who? _who(String s) => switch (s.trim()) {
        'this pokémon' => Who.self,
        "your opponent's active pokémon" || 'the defending pokémon' => Who.oppActive,
        'your active pokémon' => Who.ownActive,
        '1 of your pokémon' => Who.chooseOwn,
        '1 of your benched pokémon' => Who.chooseOwnBench,
        "1 of your opponent's pokémon" => Who.chooseOpp,
        "1 of your opponent's benched pokémon" => Who.chooseOppBench,
        'each of your pokémon' => Who.eachOwn,
        'each of your benched pokémon' => Who.eachOwnBench,
        "each of your opponent's pokémon" => Who.eachOpp,
        "each of your opponent's benched pokémon" => Who.eachOppBench,
        _ => null,
      };

  static Count? _count(String s) {
    final t = s.trim();
    if (t == 'heads') return const Heads();
    var m = rx(t, r'(?:(' + _types + r') )?energy attached to (this pokémon|your opponent.s active pokémon|all of your pokémon|both active pokémon)');
    if (m != null) {
      final who = switch (m[2]) { 'this pokémon' => Who.self, 'all of your pokémon' => Who.eachOwn, 'both active pokémon' => Who.eachOwn, _ => Who.oppActive };
      if (m[2] == 'both active pokémon') return null;
      return EnergyOn(who, _type(m[1]));
    }
    m = rx(t, r'damage counter on (this pokémon|your opponent.s active pokémon)');
    if (m != null) return DamageCountersOn(m[1] == 'this pokémon' ? Who.self : Who.oppActive);
    if (t == 'of your benched pokémon') return const BenchedCount(own: true, opp: false);
    if (t == "of your opponent's benched pokémon") return const BenchedCount(own: false, opp: true);
    if (t == 'benched pokémon (both yours and your opponent\'s)') return const BenchedCount(own: true, opp: true);
    if (t == 'card in your hand') return const HandCount(own: true);
    if (t == "card in your opponent's hand") return const HandCount(own: false);
    if (t == 'prize card your opponent has taken') return const PrizesTaken(own: false);
    if (t == 'prize card you have taken') return const PrizesTaken(own: true);
    m = rx(t, r'(basic )?(?:(' + _types + r') )?(energy|pokémon) card in your discard pile');
    if (m != null) {
      final type = _type(m[2]);
      return DiscardCount(m[3] == 'energy' ? CardFilter(basicEnergy: m[1].isNotEmpty, energy: m[1].isEmpty, type: type) : CardFilter(pokemon: m[1].isEmpty, basicPokemon: m[1].isNotEmpty, type: type));
    }
    return null;
  }

  /// "basic pokémon", "basic grass energy cards", "a supporter card", "evolution pokémon"…
  static CardFilter? _filter(String s) {
    var t = s.trim().replaceAll(RegExp(r' cards?$'), '');
    if (t.endsWith('s') && !t.endsWith('ss')) t = t.substring(0, t.length - 1);
    if (t == 'basic pokémon') return const CardFilter(basicPokemon: true);
    if (t == 'pokémon') return const CardFilter(pokemon: true);
    if (t == 'evolution pokémon') return const CardFilter(evolution: true);
    if (t == 'basic energy') return const CardFilter(basicEnergy: true);
    if (t == 'energy') return const CardFilter(energy: true);
    if (t == 'trainer') return const CardFilter(anyTrainer: true);
    if (t == 'supporter') return const CardFilter(trainer: TrainerKind.supporter);
    if (t == 'item') return const CardFilter(trainer: TrainerKind.item);
    if (t == 'pokémon tool') return const CardFilter(trainer: TrainerKind.tool);
    if (t == 'stadium') return const CardFilter(trainer: TrainerKind.stadium);
    var m = rx(t, r'basic (' + _types + r') energy');
    if (m != null) return CardFilter(basicEnergy: true, type: _type(m[1]));
    m = rx(t, r'basic (' + _types + r') pokémon');
    if (m != null) return CardFilter(basicPokemon: true, type: _type(m[1]));
    m = rx(t, r'(' + _types + r') pokémon');
    if (m != null) return CardFilter(pokemon: true, type: _type(m[1]));
    m = rx(t, r'(' + _types + r') energy');
    if (m != null) return CardFilter(energy: true, type: _type(m[1]));
    return null;
  }

  static Eff? sentence(String s, {bool trainer = false}) {
    final t = s.trim().replaceAll(RegExp(r'\.$'), '');
    List<String>? m;

    // Coins.
    if (t == 'flip a coin') return const Flip(1);
    m = rx(t, r'flip (\w+) coins');
    if (m != null) return Flip(_num(m[1]) ?? 0);
    if (t == 'flip a coin until you get tails') return const Flip(0);
    m = rx(t, r'if heads, (.+)');
    if (m != null) {
      final e = _clauses(m[1], trainer: trainer);
      return e == null ? null : IfHeads(e);
    }
    m = rx(t, r'if tails, (.+)');
    if (m != null) {
      final e = _clauses(m[1], trainer: trainer);
      return e == null ? null : IfTails(e);
    }
    m = rx(t, r'for each heads, (.+)');
    if (m != null) {
      final e = _clauses(m[1], trainer: trainer);
      return e == null ? null : ForEachHeads(e);
    }
    m = rx(t, r'flip a coin\. if heads, (.+)');
    if (m != null) {
      final e = _clauses(m[1], trainer: trainer);
      return e == null ? null : Seq([const Flip(1), IfHeads(e)]);
    }

    // Conditional damage.
    m = rx(t, r"if your opponent's active pokémon is a pokémon ex, (.+)");
    if (m != null) {
      final e = _clauses(m[1], trainer: trainer);
      return e == null ? null : IfCheck(Check.oppActiveIsEx, e);
    }
    m = rx(t, r"if your opponent's active pokémon (?:already )?has any damage counters on it, (.+)");
    if (m != null) {
      final e = _clauses(m[1], trainer: trainer);
      return e == null ? null : IfCheck(Check.oppActiveDamaged, e);
    }
    m = rx(t, r'if this pokémon has any damage counters on it, (.+)');
    if (m != null) {
      final e = _clauses(m[1], trainer: trainer);
      return e == null ? null : IfCheck(Check.selfDamaged, e);
    }
    m = rx(t, r'if this pokémon has no damage counters on it, (.+)');
    if (m != null) {
      final e = _clauses(m[1], trainer: trainer);
      return e == null ? null : IfCheck(Check.selfHasNoDamage, e);
    }
    m = rx(t, r"if your opponent's active pokémon is poisoned, (.+)");
    if (m != null) {
      final e = _clauses(m[1], trainer: trainer);
      return e == null ? null : IfCheck(Check.oppActivePoisoned, e);
    }
    m = rx(t, r"if your opponent's active pokémon is an evolution pokémon, (.+)");
    if (m != null) {
      final e = _clauses(m[1], trainer: trainer);
      return e == null ? null : IfCheck(Check.oppActiveIsEvolution, e);
    }
    m = rx(t, r"if your opponent's active pokémon is affected by a special condition, (.+)");
    if (m != null) {
      final e = _clauses(m[1], trainer: trainer);
      return e == null ? null : IfCheck(Check.oppActiveHasCondition, e);
    }
    return _clauses(t, trainer: trainer);
  }

  /// One clause, or clauses joined by ", and" / " and ".
  static Eff? _clauses(String s, {bool trainer = false}) {
    final whole = _clause(s, trainer: trainer);
    if (whole != null) return whole;
    for (final sep in const [', and ', ' and ', ', then ']) {
      final i = s.indexOf(sep);
      if (i > 0) {
        final a = _clause(s.substring(0, i), trainer: trainer);
        final b = _clauses(s.substring(i + sep.length), trainer: trainer);
        if (a != null && b != null) return Seq([a, b]);
      }
    }
    return null;
  }

  static Eff? _clause(String s, {bool trainer = false}) {
    final t = s.trim().replaceAll(RegExp(r'\.$'), '');
    List<String>? m;

    // Damage.
    if (t == 'this attack does nothing') return const NoDamage();
    m = rx(t, r'this attack does (\d+) more damage');
    if (m != null) return MoreDamage(int.parse(m[1]));
    m = rx(t, r'this attack does (\d+) more damage for each (.+)');
    if (m != null) {
      final c = _count(m[2]);
      return c == null ? null : MoreDamage(int.parse(m[1]), c);
    }
    m = rx(t, r'this attack does (\d+) less damage for each (.+)');
    if (m != null) {
      final c = _count(m[2]);
      return c == null ? null : MoreDamage(-int.parse(m[1]), c);
    }
    m = rx(t, r'this attack does (\d+) damage for each (.+)');
    if (m != null) {
      final c = _count(m[2]);
      return c == null ? null : DamagePer(int.parse(m[1]), c);
    }
    m = rx(t, r'this pokémon also does (\d+) damage to itself');
    if (m != null) return DamageTo(int.parse(m[1]), Who.self);
    m = rx(t, r'this attack (?:also )?does (\d+) damage to (.+)');
    if (m != null) {
      final who = _who(m[2]);
      if (who == null || who == Who.self) return null;
      return DamageTo(int.parse(m[1]), who);
    }
    m = rx(t, r'put (\d+|a|an|\w+) damage counters? on (.+)');
    if (m != null) {
      final n = _num(m[1]);
      final who = _who(m[2]);
      if (n == null || who == null) return null;
      return Counters(n, who);
    }
    if (t == "this attack's damage isn't affected by weakness or resistance" || t == "this attack's damage isn't affected by weakness and resistance") return const DamageRules(noWeakness: true, noResistance: true);
    if (t == "this attack's damage isn't affected by resistance") return const DamageRules(noResistance: true);
    if (t == "this attack's damage isn't affected by weakness") return const DamageRules(noWeakness: true);
    if (t == "this attack's damage isn't affected by any effects on your opponent's active pokémon") return const DamageRules(ignoreDefenderEffects: true);
    if (t == "before doing damage, discard all pokémon tools from your opponent's active pokémon") return const DiscardOppTools();

    // Special Conditions.
    m = rx(t, r"(your opponent's active pokémon|the defending pokémon|this pokémon) is now (.+)");
    if (m != null) {
      final cs = _conds(m[2]);
      if (cs == null) return null;
      return Afflict(m[1] == 'this pokémon' ? Who.self : Who.oppActive, cs);
    }

    // Cards.
    if (t == 'draw a card') return const Draw(1);
    m = rx(t, r'draw (\w+) cards');
    if (m != null && _num(m[1]) != null) return Draw(_num(m[1])!);
    m = rx(t, r'(you may )?draw cards until you have (\d+) cards in your hand');
    if (m != null) return Draw(int.parse(m[2]), untilHandSize: true, may: m[1].isNotEmpty);
    m = rx(t, r'you may draw (\w+) cards?');
    if (m != null && _num(m[1]) != null) return Draw(_num(m[1])!, may: true);
    m = rx(t, r'draw up to (\w+) cards');
    if (m != null && _num(m[1]) != null) return Draw(_num(m[1])!, upTo: true);
    m = rx(t, r'discard the top (?:(\w+) cards|card) of your opponent.s deck');
    if (m != null) return MillOpponent(m[1].isEmpty ? 1 : (_num(m[1]) ?? 1));
    m = rx(t, r'discard the top (?:(\w+) cards|card) of your deck');
    if (m != null && (m[1].isEmpty || _num(m[1]) != null)) return MillSelf(m[1].isEmpty ? 1 : _num(m[1])!);
    m = rx(t, r'put (up to )?(\w+) (.+?) from your discard pile into your hand');
    if (m != null) {
      final n = _num(m[2]);
      final f = _filter(m[3]);
      if (n == null || f == null) return null;
      return FromDiscard(n, f, upTo: m[1].isNotEmpty);
    }
    if (t == "discard a random card from your opponent's hand") return const DiscardRandomFromOppHand(1);
    if (t == 'your opponent reveals their hand') return const RevealOppHand();
    if (t == 'shuffle your hand into your deck') return const ShuffleHandIn();
    m = rx(t, r'shuffle your hand into your deck\. then, draw (\w+) cards');
    if (m != null) return ShuffleHandIn(draw: _num(m[1]) ?? 0);
    m = rx(t, r'each player shuffles their hand into their deck(?: and draws (\w+) cards)?');
    if (m != null) return ShuffleHandIn(each: true, draw: m[1].isEmpty ? -1 : (_num(m[1]) ?? 0));
    if (t == 'discard your hand') return const DiscardHand();
    m = rx(t, r'discard your hand and draw (\w+) cards');
    if (m != null && _num(m[1]) != null) return Seq([const DiscardHand(), Draw(_num(m[1])!)]);

    // Healing.
    m = rx(t, r'heal (\d+) damage from (.+)');
    if (m != null) {
      final who = _who(m[2]);
      if (who == null) return null;
      return Heal(int.parse(m[1]), who);
    }
    m = rx(t, r'heal all damage from (.+)');
    if (m != null) {
      final who = _who(m[1]);
      if (who == null) return null;
      return Heal(0, who, all: true);
    }

    // Energy.
    m = rx(t, r'discard (all|an|a|\w+) (?:(' + _types + r') )?energy (?:cards? )?from (this pokémon|your opponent.s active pokémon|the defending pokémon)');
    if (m != null) {
      final n = m[1] == 'all' ? -1 : _num(m[1]);
      if (n == null) return null;
      return DiscardEnergy(n, m[3] == 'this pokémon' ? Who.self : Who.oppActive, _type(m[2]));
    }
    m = rx(t, r'search your deck for up to (\w+) basic (?:(' + _types + r') )?energy cards? and attach (?:them|it) to (this pokémon|your benched pokémon in any way you like|your pokémon in any way you like|1 of your benched pokémon|1 of your pokémon)');
    if (m != null) {
      final n = _num(m[1]);
      if (n == null) return null;
      final dest = switch (m[3]) { 'this pokémon' => Dest.attachSelf, 'your benched pokémon in any way you like' || '1 of your benched pokémon' => Dest.attachBench, _ => Dest.attachAny };
      if (dest == Dest.attachSelf && trainer) return null;
      return Search(n, CardFilter(basicEnergy: true, type: _type(m[2])), dest);
    }
    m = rx(t, r'search your deck for (?:a|an) basic (?:(' + _types + r') )?energy card and attach it to (this pokémon|1 of your benched pokémon|1 of your pokémon)');
    if (m != null) {
      final dest = switch (m[2]) { 'this pokémon' => Dest.attachSelf, '1 of your benched pokémon' => Dest.attachBench, _ => Dest.attachAny };
      if (dest == Dest.attachSelf && trainer) return null;
      return Search(1, CardFilter(basicEnergy: true, type: _type(m[1])), dest, upTo: false);
    }
    m = rx(t, r'attach (?:up to )?(\w+) basic (?:(' + _types + r') )?energy cards? from your discard pile to (this pokémon|1 of your benched pokémon|1 of your pokémon|your pokémon in any way you like|your benched pokémon in any way you like)');
    if (m != null) {
      final n = _num(m[1]);
      if (n == null) return null;
      final dest = switch (m[3]) { 'this pokémon' => Dest.attachSelf, '1 of your benched pokémon' || 'your benched pokémon in any way you like' => Dest.attachBench, _ => Dest.attachAny };
      if (dest == Dest.attachSelf && trainer) return null;
      return AttachFromDiscard(n, _type(m[2]), dest, upTo: t.contains('up to'));
    }
    if (t == 'move an energy from this pokémon to 1 of your benched pokémon') return const MoveEnergy(fromSelf: true, basicOnly: false);
    if (t == 'move a basic energy from 1 of your pokémon to another of your pokémon') return const MoveEnergy(fromSelf: false, basicOnly: true);

    // Search.
    m = rx(t, r'search your deck for (up to )?(\w+) (.+?)(?:, reveal (?:them|it),)? and put (?:them|it) (into your hand|onto your bench)(?:\. then, shuffle your deck)?');
    if (m != null) {
      final n = _num(m[2]);
      final f = _filter(m[3]);
      if (n == null || f == null) return null;
      final dest = m[4] == 'into your hand' ? Dest.hand : Dest.bench;
      if (dest == Dest.bench && !f.basicPokemon) return null;
      return Search(n, f, dest, upTo: m[1].isNotEmpty);
    }

    // Switching.
    m = rx(t, r'switch this pokémon with (?:1|one) of your benched pokémon');
    if (m != null) return const Switch(SwitchKind.self);
    if (t == 'you may switch this pokémon with 1 of your benched pokémon') return const Switch(SwitchKind.selfMay);
    if (t == 'switch your active pokémon with 1 of your benched pokémon') return const Switch(SwitchKind.ownActive);
    if (t == "switch out your opponent's active pokémon to the bench" || t == "switch out your opponent's active pokémon to the bench. (your opponent chooses the new active pokémon.)") return const Switch(SwitchKind.oppOut);
    if (t == "switch in 1 of your opponent's benched pokémon to the active spot") return const Switch(SwitchKind.gust);

    // Lasting effects.
    if (t == "during your next turn, this pokémon can't attack" || t == "during your next turn, this pokémon can't use attacks") return const Lingering(Lasting.selfCantAttack);
    if (t == "during your opponent's next turn, the defending pokémon can't retreat" || t == "during your opponent's next turn, that pokémon can't retreat") return const Lingering(Lasting.defenderCantRetreat);
    m = rx(t, r"during your opponent's next turn, this pokémon takes (\d+) less damage from attacks(?: \(after applying weakness and resistance\))?");
    if (m != null) return Lingering(Lasting.selfTakesLess, int.parse(m[1]));
    if (t == "during your opponent's next turn, prevent all damage from and effects of attacks done to this pokémon" || t == "during your opponent's next turn, prevent all damage done to this pokémon by attacks") return const Lingering(Lasting.selfPreventAll);
    m = rx(t, r"during your opponent's next turn, attacks used by the defending pokémon do (\d+) less damage(?: \(before applying weakness and resistance\))?");
    if (m != null) return Lingering(Lasting.defenderDoesLess, int.parse(m[1]));
    if (t == 'your turn ends' || t == 'if you use this ability, your turn ends') return const EndTurn();
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Abilities, Tools, Special Energy
  // -------------------------------------------------------------------------------------------

  static AbilityIR? ability(String text) {
    final t = _norm(text);
    var m = rx(t, r'once during your turn, (?:if this pokémon is in the active spot, )?you may (.+)');
    if (m != null) {
      final e = effects(m[1]);
      if (e == null) return null;
      return OncePerTurn(e, activeOnly: t.contains('if this pokémon is in the active spot'));
    }
    m = rx(t, r'this pokémon takes (\d+) less damage from attacks(?: \(after applying weakness and resistance\))?\.?');
    if (m != null) return TakesLess(int.parse(m[1]));
    _fail('ability: $t');
    return null;
  }

  static ToolIR? toolText(String text) {
    final t = _norm(text).replaceAll(RegExp(r'\.$'), '');
    var m = rx(t, r'the pokémon this card is attached to gets \+(\d+) hp');
    if (m != null) return ToolHp(int.parse(m[1]));
    m = rx(t, r"(?:the )?attacks (?:used by|of) the pokémon this card is attached to do (\d+) more damage to your opponent's active pokémon(?: \(before applying weakness and resistance\))?");
    if (m != null) return ToolDamage(int.parse(m[1]));
    if (t == 'the pokémon this card is attached to has no retreat cost') return const ToolNoRetreat();
    m = rx(t, r'the pokémon this card is attached to takes (\d+) less damage from attacks from your opponent.s pokémon(?: \(after applying weakness and resistance\))?');
    if (m != null) return ToolTakesLess(int.parse(m[1]));
    _fail('tool: $t');
    return null;
  }

  static PType? specialEnergy(String text) {
    final t = _norm(text).replaceAll(RegExp(r'\.$'), '');
    final m = rx(t, r'as long as this card is attached to a pokémon, it provides (' + _types + r') energy');
    if (m != null) return _type(m[1]);
    _fail('energy: $t');
    return null;
  }
}
