part of 'parser.dart';

// General grammar (beyond the core set in parser.dart): noun phrases with tags, domains,
// zones and qualifiers; choices of several objects, battlefields, players and spells; many more
// sentences, conditions, triggers, passives and costs. Each _gen* hook returns null (or false)
// when the text isn't one of its forms, so the core rules still apply.

/// What one line has chosen so far, for later references ("it", "them", "there", "they").
class _GS {
  /// The last object slot chosen, and the one before (for "they deal damage to each other").
  int? last, prev;

  /// The last several-object choice: first slot and size ("them").
  int? manySlot, manyN;

  /// A chosen battlefield's slot ("there").
  int? bfSlot;

  /// The last move's destination slot ("its destination").
  int? destSlot;

  /// The player "they" refer to.
  PRef? they;

  /// The amount paid or counted earlier ("that much").
  bool thatMuch = false;

  /// Inside "Reveal the top card … If it's … Otherwise, …".
  bool revealing = false;

  /// The text talks about excess damage ("that much" is it).
  bool excess = false;

  /// A trigger of this card while it's in the trash ("When you discard me").
  bool fromTrash = false;

  /// "When you play a spell, …" ("you spent" is about that spell).
  bool spellTrig = false;

  /// After "if I am at a battlefield", "there" is my battlefield.
  bool thereIsHere = false;
}

final _lineState = Expando<_GS>();

const _moreNumbers = {'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'twice': 2};

int? _n(String s) => _num(s) ?? _moreNumbers[s.toLowerCase()];

/// A tag word in the singular ("Mechs" → "Mech").
String _singular(String w) => w.endsWith('s') && !w.endsWith('ss') && w.length > 3 ? w.substring(0, w.length - 1) : w;

/// Effects that only mark text for [_General._genPost] to join with its neighbours.
class _Otherwise extends GenEffect {
  const _Otherwise(this.effects);
  final List<Effect> effects;
  @override
  String describe() => 'otherwise';
}

class _Instead extends GenEffect {
  const _Instead(this.cond, this.effects);
  final Cond cond;
  final List<Effect> effects;
  @override
  String describe() => 'instead';
}

/// "Look at / Reveal the top N cards of your Main Deck" and what follows about them.
class _LookStart extends GenEffect {
  const _LookStart(this.n, {this.reveal = false});
  final int n;
  final bool reveal;
  @override
  String describe() => 'look';
}

class _LookPart extends GenEffect {
  const _LookPart({this.pick = 0, this.may = true, this.filter, this.predict = false});
  final int pick;
  final bool may, predict;
  final Filter? filter;
  @override
  String describe() => 'look part';
}

class _RevealStart extends GenEffect {
  const _RevealStart();
  @override
  String describe() => 'reveal';
}

class _RevealYes extends GenEffect {
  const _RevealYes(this.type);
  final CardType type;
  @override
  String describe() => 'reveal yes';
}

class _RevealNo extends GenEffect {
  const _RevealNo(this.what);
  final RevealDo what;
  @override
  String describe() => 'reveal no';
}

class _HandReveal extends GenEffect {
  const _HandReveal();
  @override
  String describe() => 'they reveal their hand';
}

class _RecycleThatCard extends GenEffect {
  const _RecycleThatCard();
  @override
  String describe() => 'they recycle that card';
}

class _UseOnlyMark extends GenEffect {
  const _UseOnlyMark(this.cond, {this.once = false});
  final Cond cond;
  final bool once;
  @override
  String describe() => 'use only';
}

class _BonusMark extends GenEffect {
  const _BonusMark(this.n);
  final int n;
  @override
  String describe() => 'bonus';
}

class _EachChooseMark extends GenEffect {
  const _EachChooseMark(this.filter);
  final Filter filter;
  @override
  String describe() => 'each player chooses';
}

class _IfCant extends GenEffect {
  const _IfCant(this.draw);
  final int draw;
  @override
  String describe() => "if you can't";
}

class _KillRestMark extends GenEffect {
  const _KillRestMark();
  @override
  String describe() => 'kill the rest';
}

extension _General on _Line {
  _GS get _gs => _lineState[this] ??= _GS();

  bool get _unitOrBf => card.type == CardType.unit || _isBattlefield;

  // -------------------------------------------------------------------------------------------
  // Noun phrases
  // -------------------------------------------------------------------------------------------

  Filter? _genFilter(String p, {required bool plural}) => _np(p, plural: plural);

  /// "enemy Mech units here with 3 {M} or less" → a filter, or null.
  Filter? _np(String p, {bool? plural}) {
    var s = p.trim();
    var side = Side.any;
    var where = Where.anywhere;
    bool? exhausted, buffed, stunned, damaged, mighty, token;
    var attacking = false, defending = false, other = false, lessMight = false, inCombat = false, myBf = false;
    int? mightMax, mightMin, costMax, atSlot;
    Kw? withKw, withoutKw;
    var zone = FZone.board;
    final tags = <String>[];
    String? notTag;
    Domain? domain;
    Set<CardType>? types;
    var gear = false;
    // Trailing qualifiers, outermost first.
    for (var changed = true; changed;) {
      changed = false;
      RegExpMatch? m;
      bool cut(String re) {
        m = RegExp('$re\$').firstMatch(s);
        if (m == null) return false;
        s = s.substring(0, m!.start);
        changed = true;
        return true;
      }

      if (cut(r' (?:each )?with (\d+) \{M\} or (less|more)')) {
        if (m![2] == 'less') {
          mightMax = int.parse(m![1]!);
        } else {
          mightMin = int.parse(m![1]!);
        }
      } else if (cut(r' with less Might than me')) {
        if (card.type != CardType.unit) return null;
        lessMight = true;
      } else if (cut(r' with(out)? \[([A-Za-z]+)\]')) {
        final kw = _kwNames[m![2]!.toLowerCase()];
        if (kw == null) return null;
        if (m![1] != null) {
          withoutKw = kw;
        } else {
          withKw = kw;
        }
      } else if (cut(r' here')) {
        if (!_unitOrBf) return null;
        where = Where.here;
      } else if (cut(r' there')) {
        if (_gs.bfSlot != null) {
          atSlot = _gs.bfSlot;
        } else if (_eventBf || _gs.thereIsHere) {
          where = Where.here;
        } else if (_gs.last != null) {
          atSlot = _gs.last;
        } else {
          return null;
        }
      } else if (cut(r' at (?:a battlefield|battlefields)')) {
        where = Where.battlefield;
      } else if (cut(r' at my battlefield')) {
        if (card.type != CardType.unit) return null;
        myBf = true;
      } else if (cut(r" at (?:its location|its destination|that enemy unit's battlefield|that battlefield)")) {
        if (m![0]!.contains('destination') && _gs.destSlot != null) {
          atSlot = _gs.destSlot;
        } else if (_gs.bfSlot != null) {
          atSlot = _gs.bfSlot;
        } else if (_gs.last != null) {
          atSlot = _gs.last;
        } else if (_eventBf) {
          where = Where.here;
        } else {
          return null;
        }
      } else if (cut(r' in (your|a) base')) {
        if (m![1] == 'your') side = Side.friendly;
        where = Where.base;
      } else if (cut(r' (?:you|they) control')) {
        side = Side.friendly;
      } else if (cut(r' anywhere')) {
        // No restriction.
      } else if (cut(r' in combat')) {
        inCombat = true;
      } else if (cut(r' from (your|their) trash|in your trash')) {
        zone = FZone.trash;
        side = Side.friendly;
      } else if (cut(r' from trashes')) {
        zone = FZone.trash;
      } else if (cut(r" that's exhausted")) {
        exhausted = true;
      }
    }
    final words = s.split(' ');
    if (words.isEmpty) return null;
    // The noun.
    final last = words.removeLast();
    final nounPlural = last.endsWith('s') && last != 'gear';
    switch (last) {
      case 'unit' || 'units':
        types = null;
      case 'gear':
        if (words.length >= 2 && words[words.length - 1] == 'or' && words[words.length - 2] == 'unit') {
          words.removeLast();
          words.removeLast();
          types = {CardType.unit, CardType.gear};
        } else if (words.length >= 2 && (words.last == 'and' || words.last == 'and/or') && (words[words.length - 2] == 'units' || words[words.length - 2] == 'unit')) {
          words.removeLast();
          words.removeLast();
          types = {CardType.unit, CardType.gear};
        } else {
          gear = true;
        }
      case 'card' || 'cards':
        types = {CardType.unit, CardType.gear, CardType.spell};
      case 'spell' || 'spells':
        types = {CardType.spell};
      default:
        // A tag as the noun: "another Dragon", "your Mechs", "a Bird, Cat, Dog, or Poro".
        if (!RegExp(r"^[A-Z][A-Za-z'-]+$").hasMatch(last)) return null;
        final t = nounPlural ? _singular(last) : last;
        if (Domain.byName(t) != null) return null;
        tags.add(t);
        // "Bird, Cat, Dog, or Poro".
        while (words.isNotEmpty && (words.last == 'or' || words.last == 'and')) {
          words.removeLast();
          while (words.isNotEmpty && RegExp(r"^[A-Z][A-Za-z'-]+,$").hasMatch(words.last)) {
            tags.insert(0, words.removeLast().replaceAll(',', ''));
          }
        }
    }
    if (plural != null && types == null && !gear && tags.isEmpty && nounPlural != plural) return null;
    for (final w in words) {
      switch (w) {
        case 'friendly' || 'your':
          side = Side.friendly;
        case 'enemy':
          side = Side.enemy;
        case 'other':
          other = true;
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
        case 'stunned':
          stunned = true;
        case 'damaged':
          damaged = true;
        case 'token':
          token = true;
        case 'non-token':
          token = false;
        case '[Mighty]' || 'Mighty':
          mighty = true;
        default:
          final nm = RegExp(r'^non-([A-Z][a-z]+)$').firstMatch(w);
          if (nm != null) {
            notTag = nm[1];
            continue;
          }
          final d = Domain.byName(w);
          if (d != null && RegExp(r'^[A-Z]').hasMatch(w)) {
            domain = d;
            continue;
          }
          if (RegExp(r"^[A-Z][A-Za-z'-]+$").hasMatch(w)) {
            tags.add(w);
            continue;
          }
          return null;
      }
    }
    if (other && card.type != CardType.unit && card.type != CardType.gear && card.type != CardType.legend) return null;
    if (zone != FZone.board && (exhausted != null || attacking || defending || where != Where.anywhere || buffed != null || stunned != null)) return null;
    if (gear && (attacking || defending || mightMax != null || mightMin != null || buffed != null || stunned != null || mighty != null)) return null;
    String? tag;
    if (tags.length == 1) {
      tag = tags.first;
      tags.clear();
    }
    return Filter(
      side: side,
      where: where,
      gear: gear,
      mightMax: mightMax,
      mightMin: mightMin,
      other: other,
      exhausted: exhausted,
      attacking: attacking,
      defending: defending,
      tag: tag,
      buffed: buffed,
      types: types,
      zone: zone,
      tags: List.unmodifiable(tags),
      domain: domain,
      token: token,
      notTag: notTag,
      stunned: stunned,
      damaged: damaged,
      mighty: mighty,
      withKw: withKw,
      withoutKw: withoutKw,
      costMax: costMax,
      lessMightThanMe: lessMight,
      inCombat: inCombat,
      atSlot: atSlot,
      myBf: myBf,
    );
  }

  // -------------------------------------------------------------------------------------------
  // Targets
  // -------------------------------------------------------------------------------------------

  int _take(int n) {
    final s = _slotCounter[0];
    _slotCounter[0] += n;
    return s;
  }

  Target? _genTarget(String p) {
    p = p.trim();
    if (p == 'it' || p == 'that unit' || p == 'that gear' || p == 'your unit' || p == 'the unit') {
      if (_gs.last != null) return Chosen(_gs.last!);
      return null;
    }
    if (p == 'them' || p == 'those units') {
      if (_gs.manySlot != null) return ChosenAll(_gs.manySlot!, _gs.manyN!);
      if (_gs.last != null && _gs.prev != null) return ChosenAll(_gs.prev!, _gs.last! - _gs.prev! + 1);
      return null;
    }
    if (p == 'that card' || p == 'it') return null;
    if (p == 'me' && card.type == CardType.legend) return const SelfAny();
    if (p == 'me' && card.type == CardType.unit) return const Me();
    if ((p == 'this' || p == 'me') && card.type == CardType.gear) return const Me();
    if (p == 'your legend') return const YourLegend();
    if (p == 'a legend') return ChooseLegend(_take(1));
    var m = RegExp(r"^something (?:else|besides me) that's exhausted$").firstMatch(p);
    if (m != null && card.isPermanent) {
      final slot = _take(1);
      _gs.last = slot;
      return ChooseAnything(slot, exhausted: true, notMe: true);
    }
    // "up to N …", "N … each", "any number of …".
    m = RegExp(r'^up to (two|three|four|five|\d+) (.+)$').firstMatch(p);
    m ??= RegExp(r'^(two|three|four|\d+) (.+?) each$').firstMatch(p);
    final anyN = RegExp(r'^any number of (.+)$').firstMatch(p);
    if (m != null || anyN != null) {
      final max = anyN != null ? 8 : _n(m![1]!);
      if (max == null) return null;
      final exact = m != null && p.endsWith(' each');
      var rest = anyN != null ? anyN[1]! : m![2]!;
      var same = false;
      int? total;
      final sm = RegExp(r'^(.+) at the same location$').firstMatch(rest);
      if (sm != null) {
        same = true;
        rest = sm[1]!;
      }
      final tm = RegExp(r'^(.+?) with (?:the same controller and )?a total Might of (\d+) or less$').firstMatch(rest) ?? RegExp(r'^(.+?) with total Might (\d+) or less$').firstMatch(rest);
      if (tm != null) {
        total = int.parse(tm[2]!);
        rest = tm[1]!;
      }
      var other = false;
      if (rest.startsWith('other ')) {
        other = true;
        rest = rest.substring(6);
      }
      var f = _np(rest, plural: true);
      if (f == null) return null;
      if (other) {
        if (!card.isPermanent && card.type != CardType.legend) return null;
        f = f.copyWith(other: true);
      }
      final slot = _take(max);
      _gs.manySlot = slot;
      _gs.manyN = max;
      return ChooseMany(f, slot: slot, max: max, min: exact ? max : 0, sameLocation: same, totalMightMax: total);
    }
    // "your units", "your other units", "friendly units here", "ALL units at battlefields".
    m = RegExp(
      r'^(?:all |ALL |each )?(your (?:other )?(?:\w+ )?(?:units|[A-Z]\w+s)(?: here| there| at .+)?|(?:other )?(?:friendly |enemy |damaged |stunned )*units(?: .+)?|(?:other )?(?:friendly |enemy )?(?:units|gear) (?:here|there|at .+))$',
    ).firstMatch(p);
    if (m != null && !p.startsWith('a ')) {
      var body = m[1]!;
      var other = false;
      if (body.startsWith('your other ')) {
        other = true;
        body = 'your ${body.substring(11)}';
      } else if (body.startsWith('other ')) {
        other = true;
        body = body.substring(6);
      }
      var f = _np(body, plural: true);
      if (f == null) return null;
      if (other) {
        if (!card.isPermanent && card.type != CardType.legend) return null;
        f = f.copyWith(other: true);
      }
      return Each(f);
    }
    m = RegExp(r'^each (other )?(.+)$').firstMatch(p);
    if (m != null) {
      var f = _np(m[2]!, plural: false);
      if (f == null) return null;
      if (m[1] != null) {
        if (_gs.last != null) {
          // "each other enemy unit there": not the one chosen; handled as "other" than the source.
          return null;
        }
        f = f.copyWith(other: true);
      }
      return Each(f);
    }
    // "a/an/another …" and "up to one …".
    var upTo = false;
    var q = p;
    m = RegExp(r'^up to one (.+)$').firstMatch(q);
    if (m != null) {
      upTo = true;
      q = 'a ${m[1]}';
    }
    m = RegExp(r'^(a|an|another|one) (.+)$').firstMatch(q);
    if (m != null) {
      var f = _np(m[2]!, plural: false);
      if (f == null) return null;
      if (m[1] == 'another' && !card.isPermanent && card.type != CardType.legend) {
        // A spell's "another …": different from what it chose before.
        if (_gs.last == null) return null;
        final slot = _take(1);
        final not = _gs.last!;
        _gs.prev = _gs.last;
        _gs.last = slot;
        return ChooseOther(f, slot: slot, notSlot: not, upTo: upTo);
      }
      if (m[1] == 'another') f = f.copyWith(other: true);
      if (f.other && !card.isPermanent && card.type != CardType.legend) return null;
      final slot = _take(1);
      _gs.prev = _gs.last;
      _gs.last = slot;
      return Choose(f, slot: slot, upTo: upTo);
    }
    return null;
  }

  /// "you", "they", "its controller", "each player", "an opponent" → a player reference.
  PRef? _who(String w) => switch (w) {
    'you' || 'You' => const PYou(),
    'they' || 'They' || 'that player' || 'That player' => _gs.they ?? (_eventPlayer ? const PEvent() : null),
    'its controller' || 'Its controller' || "its owner" || 'Its owner' => _gs.last == null ? null : PControllerOf(Chosen(_gs.last!), owner: w.endsWith('owner')),
    'each player' || 'Each player' => const PEach(),
    'each opponent' || 'Each opponent' || 'opponents' || 'Opponents' => const POpponent(),
    _ => null,
  };

  /// Triggers whose "they" is the player the event is about.
  bool get _eventPlayer => _gs.they is PEvent;

  // -------------------------------------------------------------------------------------------
  // Sentences
  // -------------------------------------------------------------------------------------------

  /// Joins marker effects with their neighbours: "Otherwise, …" after an "If …" becomes its
  /// else-branch; "… instead" replaces the effects before it when its condition holds.
  List<Effect>? _genPost(List<Effect> out) {
    final r = <Effect>[];
    for (var i = 0; i < out.length; i++) {
      final e = out[i];
      if (e is _LookStart) {
        var pick = 0, may = true, predict = false;
        Filter? f;
        var parts = 0;
        while (i + 1 < out.length && out[i + 1] is _LookPart) {
          final p = out[++i] as _LookPart;
          parts++;
          if (p.pick > 0) {
            pick = p.pick;
            may = p.may;
            f = p.filter;
          }
          if (p.predict) predict = true;
        }
        if (parts == 0) return null;
        if (predict) {
          if (pick > 0) return null;
          r.add(Predict(e.n));
        } else {
          r.add(LookTop(e.n, pick: pick, filter: f, mayPick: may, revealed: e.reveal || f != null));
        }
        continue;
      }
      if (e is _RevealStart) {
        if (i + 2 >= out.length || out[i + 1] is! _RevealYes || out[i + 2] is! _Otherwise) return null;
        final yes = out[i + 1] as _RevealYes;
        final no = (out[i + 2] as _Otherwise).effects;
        if (no.length != 1 || no.first is! _RevealNo) return null;
        i += 2;
        r.add(RevealTop(Filter(types: {yes.type}, zone: FZone.hand), RevealDo.hand, (no.first as _RevealNo).what));
        continue;
      }
      if (e is _HandReveal) continue;
      if (e is _IfCant) {
        final prev = r.isEmpty ? null : r.removeLast();
        if (prev is Channel) {
          r.add(ChannelP(prev.n, const PYou(), exhausted: prev.exhausted, elseDraw: e.draw));
          continue;
        }
        if (prev is! ChannelP || prev.elseDraw > 0) return null;
        r.add(ChannelP(prev.n, prev.who, exhausted: prev.exhausted, elseDraw: e.draw));
        continue;
      }
      if (e is _RecycleThatCard) {
        final prev = r.isEmpty ? null : r.removeLast();
        if (prev is! HandPick) return null;
        r.add(HandPick(filter: prev.filter, recycle: true));
        continue;
      }
      if (e is _UseOnlyMark) {
        if (r.isEmpty) return null;
        final body = List<Effect>.of(r);
        r
          ..clear()
          ..add(UseOnly(e.cond, body, once: e.once));
        continue;
      }
      if (e is _BonusMark) {
        if (r.isEmpty) return null;
        r.add(BonusPerName(e.n, [r.removeLast()]));
        continue;
      }
      if (e is _EachChooseMark) {
        if (i + 1 >= out.length || out[i + 1] is! _KillRestMark) return null;
        i++;
        r.add(EachKeep(e.filter));
        continue;
      }
      if (e is _LookPart || e is _RevealYes || e is _RevealNo || e is _KillRestMark) return null;
      if (e is _Otherwise) {
        final prev = r.isEmpty ? null : r.removeLast();
        if (prev is If) {
          r.add(IfElse(prev.cond, prev.effects, e.effects));
        } else if (prev is IfElse && prev.no.isEmpty) {
          r.add(IfElse(prev.cond, prev.yes, e.effects));
        } else {
          return null;
        }
        continue;
      }
      if (e is _Instead) {
        // "If you control 7 or more runes, deal 7 to it instead": replaces the last effect.
        if (r.isEmpty) return null;
        final prev = r.removeLast();
        r.add(IfElse(e.cond, e.effects, [prev]));
        continue;
      }
      r.add(e);
    }
    if (r.any((x) => x is _Otherwise || x is _Instead || x is _LookStart || x is _RevealStart)) return null;
    return r;
  }

  List<Effect>? _genSentence(String s0) {
    final s = s0.trim();
    RegExpMatch? m;
    RegExpMatch? mt(String re) => m = RegExp('^$re\$').firstMatch(s);

    if (s.endsWith('.')) return _sentence(s.substring(0, s.length - 1));
    if (mt(r'Then,? (.+)') != null) return _sentence(_Line._cap(m![1]!));
    // The top of the deck (joined with the sentences after it by _genPost).
    if (mt(r'(Look at|Reveal) the top (\d+|two|three|four|five) cards of your Main Deck') != null) return [_LookStart(_n(m![2]!)!, reveal: m![1] == 'Reveal')];
    if (s == 'Draw one and recycle the other') return [const _LookPart(pick: 1, may: false)];
    if (mt(r'Put (\d+|one) into your hand and recycle the rest') != null) return [_LookPart(pick: _n(m![1]!)!, may: false)];
    if (mt(r'You may reveal an? (unit|gear|spell) from among them and draw it') != null) {
      final type = m![1] == 'unit' ? CardType.unit : (m![1] == 'gear' ? CardType.gear : CardType.spell);
      return [
        _LookPart(
          pick: 1,
          filter: Filter(types: {type}, zone: FZone.hand),
        ),
      ];
    }
    if (mt(r'(?:Then )?[Rr]ecycle the rest') != null) return [const _LookPart()];
    if (s == 'You may recycle one or both of them') return [const _LookPart(predict: true)];
    if (s == "Put those you don't back in any order") return [const _LookPart()];
    if (s == 'Reveal the top card of your Main Deck') {
      _gs.revealing = true;
      return [const _RevealStart()];
    }
    if (_gs.revealing && mt(r"If it's an? (unit|gear|spell), (?:draw it|put it in your hand)") != null) {
      return [_RevealYes(m![1] == 'unit' ? CardType.unit : (m![1] == 'gear' ? CardType.gear : CardType.spell))];
    }
    if (_gs.revealing && s == 'Recycle it') return [const _RevealNo(RevealDo.recycle)];
    if (_gs.revealing && s == 'Put it in your trash and give me +2 {M} this turn' && card.type == CardType.unit) return [const _RevealNo(RevealDo.trashAndMight2)];
    // An opponent's hand.
    if (s == 'They reveal their hand') return [const _HandReveal()];
    if (s == 'Choose a card from it, and they discard that card') return [const HandPick()];
    if (s == 'Choose a non-unit card from it, and recycle that card') {
      return [
        const HandPick(
          filter: Filter(types: {CardType.spell, CardType.gear}, zone: FZone.hand),
          recycle: true,
        ),
      ];
    }
    if (mt(r'They reveal their hand and you choose an? ([A-Z][a-z]+) card from it') != null) {
      final d = Domain.byName(m![1]!);
      if (d == null) return null;
      return [
        HandPick(
          filter: Filter(types: const {CardType.unit, CardType.spell, CardType.gear}, zone: FZone.hand, domain: d),
        ),
      ];
    }
    if (s == 'They recycle that card') return [const _RecycleThatCard()];
    // Activated abilities' restrictions.
    if (s == "Use this ability only while I'm at a battlefield" && card.type == CardType.unit) return [const _UseOnlyMark(SelfCond(SelfKind.atBattlefield))];
    if (s == "Use only if you've chosen an enemy unit this turn and only once each turn") return [const _UseOnlyMark(StatCond(PStat.choseEnemy, CmpOp.ge, 1), once: true)];
    // Spells.
    if (s == 'Banish this' && _isSpell) return [const BanishThis()];
    if (mt(r'This deals (\d+) Bonus Damage for each card with this name in your trash') != null && _isSpell) return [_BonusMark(int.parse(m![1]!))];
    if (mt(r'(?:Deal|deal) (\d+) damage split among any number of (.+)') != null) {
      final f = _np(m![2]!, plural: true);
      return f == null ? null : [DealSplit(int.parse(m![1]!), f)];
    }
    if (s == 'Each player chooses a unit they control') return [const _EachChooseMark(Filter())];
    if (s == 'Kill the rest') return [const _KillRestMark()];
    if (s == 'For each friendly unit, you may spend its buff to ready it') return [const SpendBuffsToReady()];
    if (s == 'Activate the conquer effects of units here' && _isBattlefield) return [const ActivateConquer()];
    if (mt(r'Recycle up to (\d+) cards from trashes') != null) return [RecycleTrashes(int.parse(m![1]!))];
    if (mt(r'Deal its Energy cost as damage to (.+)') != null) {
      final t = _target(m![1]!);
      return t == null ? null : [DealAmt(const DiscardedCost(), t)];
    }
    if (mt(r'Each player discards their hand, then draws (\d+)') != null) return [const DiscardP(0, PEach(), hand: true), DrawAmt(N(int.parse(m![1]!)), who: const PEach())];
    if (mt(r'(?:Give|give) (me|it) \+(\d+) \{M\} this turn and ready (me|it)') != null) {
      final t = _target(m![1]!);
      return t == null ? null : [GiveMight(int.parse(m![2]!), t), Ready(t)];
    }
    if (mt(r'Give (.+?) \+(\d+) \{M\} this turn and \[Stun\] (.+)') != null) {
      final a = _target(m![1]!);
      final b = a == null ? null : _target(m![3]!.replaceFirst(' at its location', ' at its location'));
      return b == null ? null : [GiveMight(int.parse(m![2]!), a!), Stun(b)];
    }
    if (mt(r'An additional \+(\d+) \{M\} this turn if it is the only unit you control there') != null && _gs.last != null) {
      final t = Chosen(_gs.last!);
      return [
        If(AloneCond(t), [GiveMight(int.parse(m![1]!), t)]),
      ];
    }
    if (s == "Return all units and gear to their owners' hands") {
      return [
        const ToHand(Each(Filter(types: {CardType.unit, CardType.gear}))),
      ];
    }
    if (mt(r"(?:Return|return) me to my owner's hand") != null && card.type == CardType.unit) return [const ToHand(Me())];
    if (mt(r'Move (.+?) and ready it') != null) {
      final mv = _move(m![1]!, null);
      if (mv == null || _gs.last == null) return null;
      return [...mv, Ready(Chosen(_gs.last!))];
    }
    if (mt(r'(?:Move|move) (.+?) from here to its base') != null) {
      final t = _target('${m![1]} here');
      return t == null ? null : [ToBase(t)];
    }
    if (mt(r'(?:Move|move) (.+?) from a battlefield to its base') != null) {
      final t = _target('${m![1]} at a battlefield');
      return t == null ? null : [ToBase(t)];
    }
    if (mt(r"Its owner places it on the top or bottom of their Main Deck") != null && _gs.last != null) return [ToDeck(Chosen(_gs.last!))];
    if (s == 'Take control of it and recall it' && _gs.last != null) return [TakeControl(Chosen(_gs.last!))];
    if (mt(r'Banish (a friendly unit), then (?:its owner plays|play) it(?: to (any battlefield|base))?, ignoring its cost') != null) {
      final t = _target(m![1]!);
      if (t == null) return null;
      return [Blink(t, to: m![2] == 'any battlefield' ? Dest.battlefield : (m![2] == 'base' ? Dest.base : Dest.any))];
    }
    if (s == 'Pay any amount of {A} to deal that much damage to all enemy units at a battlefield') {
      final slot = _take(1);
      _gs.bfSlot = slot;
      return [
        ChooseOnly([ChooseBf(slot)]),
        PayTo([DealAmt(const ThatMuch(), Each(Filter(side: Side.enemy, atSlot: slot)))], anyAmount: true, optional: false),
      ];
    }
    if (s == 'Counter a spell if an opponent has played another spell this turn' && _isSpell) {
      return [
        const If(StatCond(PStat.oppSpellsCast, CmpOp.ge, 2), [Counter()]),
      ];
    }
    if (s == "Its controller can't play spells this turn") return [const Delay(DelayKind.noSpells, n: 1)];
    if (s == "Return it to its owner's hand instead of putting it in their trash") return [const CounteredToHand()];
    if (mt(r'(?:You|you) may deal that much to (.+)') != null && _gs.excess) {
      final t = _target(m![1]!);
      return t == null
          ? null
          : [
              May([DealAmt(const PlayerStat(Stat.excess), t)]),
            ];
    }
    if (mt(r'They may (.+)') != null && !m![1]!.startsWith('pay ')) {
      if (_gs.they == null && !_eventPlayer) return null;
      final e = _sentence(_Line._cap(m![1]!.replaceAll('they control', 'you control')));
      return e == null ? null : [May(e)];
    }
    if (mt(r'(?:A|a)t the start of your next Main Phase, (.+)') != null) {
      final e = _sentence(_Line._cap(m![1]!));
      return e == null ? null : [Delay(DelayKind.atNextMain, effects: e)];
    }
    if (mt(r'(.+) at the start of your next Main Phase') != null) {
      final e = _sentence(_Line._cap(m![1]!));
      return e == null ? null : [Delay(DelayKind.atNextMain, effects: e)];
    }
    // "Otherwise, …" and "… instead".
    if (mt(r'Otherwise, (.+)') != null) {
      final e = _sentence(_Line._cap(m![1]!));
      return e == null ? null : [_Otherwise(e)];
    }
    if (mt(r'If (.+?), (.+) instead') != null) {
      final c = _cond(m![1]!);
      if (c != null) {
        final e = _sentence(_Line._cap(m![2]!));
        return e == null ? null : [_Instead(c, e)];
      }
    }
    if (mt(r"If you can't, draw (\d+)") != null) return [_IfCant(int.parse(m![1]!))];
    if (s == 'Play me' && _gs.fromTrash) return [const PlayFrom(SelfAny(), ignoreAll: true)];
    // "Choose …" sentences: the choice only; later sentences use it.
    if (mt(r'Choose an opponent') != null) {
      _gs.they = const POpponent();
      return [const ChooseOnly([])];
    }
    if (mt(r'Choose a player') != null) {
      final slot = _take(1);
      _gs.they = PChosen(slot);
      return [
        ChooseOnly([ChoosePlayer(slot)]),
      ];
    }
    if (mt(r'Choose a battlefield( where you have units)?') != null) {
      final slot = _take(1);
      _gs.bfSlot = slot;
      return [
        ChooseOnly([ChooseBf(slot, withYourUnits: m![1] != null)]),
      ];
    }
    if (mt(r'Choose a battlefield and (.+) there') != null) {
      final slot = _take(1);
      _gs.bfSlot = slot;
      final t = _target('${m![1]} there');
      return t == null
          ? null
          : [
              ChooseOnly([ChooseBf(slot), t]),
            ];
    }
    if (mt(r'Choose (.+?) and (a .+|an .+)') != null && !m![1]!.contains(' and ')) {
      final a = _target(m![1]!);
      final b = a == null ? null : _target(m![2]!);
      return b == null
          ? null
          : [
              ChooseOnly([a!, b]),
            ];
    }
    if (mt(r'Choose (two|2) units') != null) {
      final a = _target('a unit');
      final b = _target('another unit');
      return a == null || b == null
          ? null
          : [
              ChooseOnly([a, b]),
            ];
    }
    if (mt(r'Choose (another .+)') != null) {
      final t = _target(m![1]!);
      return t == null
          ? null
          : [
              ChooseOnly([t]),
            ];
    }
    if (mt(r'Choose (.+)') != null) {
      final t = _target(m![1]!);
      return t == null
          ? null
          : [
              ChooseOnly([t]),
            ];
    }
    // "They deal damage equal to their Mights to each other" (CR 418.6.b.3).
    if (s == 'They deal damage equal to their Mights to each other' || s == 'We deal damage equal to our Mights to each other') {
      if (s.startsWith('We')) {
        if (card.type != CardType.unit || _gs.last == null) return null;
        return [Fight(const Me(), Chosen(_gs.last!))];
      }
      if (_gs.last == null || _gs.prev == null) return null;
      return [Fight(Chosen(_gs.prev!), Chosen(_gs.last!))];
    }
    // Players doing things: "They discard 1", "Its controller draws 2", "Each player draws 4".
    if (mt(r'(They|That player) \[Burn (\d+)\]') != null) {
      final who = _who(m![1]!);
      return who == null ? null : [Mill(int.parse(m![2]!), who: who)];
    }
    if (mt(r"(You|They|Its controller|Its owner|Each player|Each opponent|that player|That player) (draws?|discards?|channels?|scores?|plays?|gains?) (.+)") != null) {
      final who = _who(m![1]!);
      if (who == null) return null;
      final verb = m![2]!.replaceAll(RegExp(r's$'), '');
      final rest = m![3]!;
      switch (verb) {
        case 'draw':
          final n = _n(rest);
          return n == null ? null : [DrawAmt(N(n), who: who)];
        case 'discard':
          if (rest == 'their hand') return [DiscardP(0, who, hand: true)];
          final n = _n(rest);
          return n == null ? null : [DiscardP(n, who)];
        case 'channel':
          final cm = RegExp(r'^(\d+|one|two) runes?( exhausted)?$').firstMatch(rest);
          final n = cm == null ? null : _n(cm[1]!);
          return n == null ? null : [ChannelP(n, who, exhausted: cm![2] != null)];
        case 'score' || 'gain':
          final pm = RegExp(r'^(\d+|one) points?$').firstMatch(rest);
          final n = pm == null ? null : _n(pm[1]!);
          return n == null ? null : [ScoreP(n, who)];
        case 'play':
          final tk = _token(rest);
          return tk == null ? null : [TokenP(tk.$1, tk.$2, who, ready: tk.$3, where: tk.$4)];
      }
      return null;
    }
    // Draws with amounts.
    if (mt(r'Draw (\d+) for each (.+)') != null) {
      final a = _forEach(m![2]!, int.parse(m![1]!));
      return a == null ? null : [DrawAmt(a)];
    }
    if (mt(r'Draw (\d+), then draw (\d+) for each (.+)') != null) {
      final a = _forEach(m![3]!, int.parse(m![2]!), plus: int.parse(m![1]!));
      return a == null ? null : [DrawAmt(a)];
    }
    if (mt(r'Draw (\d+) or channel (\d+) runes? exhausted') != null) {
      return [
        Modes([
          [Draw(int.parse(m![1]!))],
          [Channel(int.parse(m![2]!), exhausted: true)],
        ]),
      ];
    }
    if (mt(r'Draw (\d+) or buff me') != null && card.type == CardType.unit) {
      return [
        Modes([
          [Draw(int.parse(m![1]!))],
          [const Buff(Me())],
        ]),
      ];
    }
    if (mt(r'(?:Channel|channel) (\d+) runes? exhausted and draw (\d+)') != null) return [Channel(int.parse(m![1]!), exhausted: true), Draw(int.parse(m![2]!))];
    if (mt(r'Channel (\d+) runes? exhausted\. If you (?:can.t|couldn.t channel \d+ runes? this way), draw (\d+)') != null) return null;
    // "Discard 1, then draw 1" handled by the core's ", then ".
    // Damage.
    if (mt(r'Deal (\d+) to (.+?) and (\d+) to (each other enemy unit there|all other enemy units here|each other enemy unit here)') != null) {
      final t = _target(m![2]!);
      if (t == null || _gs.last == null) return null;
      final here = m![4]!.endsWith('here');
      final f = Filter(side: Side.enemy, where: here ? Where.here : Where.anywhere, atSlot: here ? null : _gs.bfSlot);
      if (!here && _gs.bfSlot == null) return null;
      if (here && !_unitOrBf) return null;
      return [Deal(N(int.parse(m![1]!)), t), ExceptDeal(int.parse(m![3]!), f, _gs.last!)];
    }
    if (mt(r'Deal (\d+) to (.+?), then deal (\d+) to (up to one other unit|another unit)') != null) {
      final t = _target(m![2]!);
      if (t == null) return null;
      final first = _gs.last;
      final t2 = _target(m![4]!.startsWith('up to') ? 'up to one unit' : 'a unit');
      if (t2 == null || first == null) return null;
      return [Deal(N(int.parse(m![1]!)), t), DealOther(int.parse(m![3]!), t2, first)];
    }
    if (mt(r'Deal (\d+) to each of (up to (?:two|three) .+)') != null) {
      final t = _target(m![2]!);
      return t == null ? null : [Deal(N(int.parse(m![1]!)), t)];
    }
    if (mt(r'Deal (\d+) to (ALL|all) (.+)') != null) {
      final t = _target('all ${m![3]}');
      return t == null ? null : [Deal(N(int.parse(m![1]!)), t)];
    }
    if (mt(r'Deal (\d+) to them') != null) {
      final t = _target('them');
      return t == null ? null : [Deal(N(int.parse(m![1]!)), t)];
    }
    // "Deal damage equal to its Might to …": the spell or ability deals it (CR 418.6.a).
    if (mt(r"(?:Deal|deal) damage equal to its Might to (.+)") != null) {
      if (_gs.last == null) return null;
      final src = Chosen(_gs.last!);
      final t = _target(m![1]!);
      return t == null ? null : [DealAmt(MightOf(src), t)];
    }
    if (mt(r"It deals damage equal to its Might to (.+)") != null) {
      if (_gs.last == null) return null;
      final src = Chosen(_gs.last!);
      final t = _target(m![1]!);
      return t == null ? null : [DealAmt(MightOf(src), t, source: src)];
    }
    if (mt(r"Deal damage equal to my \[Assault\] to (.+)") != null && card.type == CardType.unit) {
      final t = _target(m![1]!);
      return t == null ? null : [DealAmt(const MyAssault(), t, source: const Me())];
    }
    // Might.
    if (mt(r'Give (.+?) \+(\d+) \{M\} this turn for each (.+)') != null) {
      final t = _target(m![1]!);
      final a = t == null ? null : _forEach(m![3]!, int.parse(m![2]!));
      return a == null ? null : [GiveMightAmt(a, t!)];
    }
    if (mt(r'Give (.+?) \+\{M\} equal to (its|my|the burned card.s) Might this turn') != null) {
      return null;
    }
    if (mt(r"Double (.+?)(?:'s)? Might this turn") != null) {
      var tp = m![1]!;
      if (tp == 'my') tp = 'me';
      if (tp.endsWith("'s")) tp = tp.substring(0, tp.length - 2);
      final t = _target(tp);
      return t == null ? null : [DoubleMight(t)];
    }
    if (mt(r'Give (.+?) ([+-])(\d+) \{M\} and (\[.+\]) this turn') != null) {
      final t = _target(m![1]!);
      final kws = _kwList(m![4]!);
      if (t == null || kws == null) return null;
      return [GiveMany(t, might: int.parse(m![3]!) * (m![2] == '-' ? -1 : 1), kws: kws)];
    }
    if (mt(r'Give (.+?) (\[.+\]) this turn') != null && m![2]!.contains('] and [')) {
      final t = _target(m![1]!);
      final kws = _kwList(m![2]!);
      if (t == null || kws == null) return null;
      return [GiveMany(t, kws: kws)];
    }
    if (mt(r'Give (.+?) \+(\d+) \{M\} this turn and (another unit|.+?) -(\d+) \{M\} this turn') != null) {
      final a = _target(m![1]!);
      final b = a == null ? null : _target(m![3]!);
      if (b == null) return null;
      return [GiveMight(int.parse(m![2]!), a!), GiveMight(-int.parse(m![4]!), b)];
    }
    if (mt(r'Give friendly units there \+(\d+) \{M\} this turn and enemy units there -(\d+) \{M\} this turn, to a minimum of (\d+) \{M\}') != null) {
      final a = _target('friendly units there');
      final b = _target('enemy units there');
      if (a == null || b == null) return null;
      return [GiveMight(int.parse(m![1]!), a), GiveMight(-int.parse(m![2]!), b, min: int.parse(m![3]!))];
    }
    if (mt(r'Give (.+?) \[([A-Za-z]+)(?: (\d+))?\]') != null && !s.endsWith('this turn')) {
      // A lasting keyword ("Give it [Temporary]").
      final kw = _kwNames[m![2]!.toLowerCase()];
      final t = _target(m![1]!);
      if (kw == null || t == null) return null;
      if (kw == Kw.temporary) return [GiveKwLasting(kw, t)];
      return null;
    }
    // Moves.
    if (mt(r'Move (.+?) to (?:its|their) base') != null && !m![1]!.contains(' from ')) return null; // the core's
    if (mt(r'Move (up to \w+ .+) to base') != null) {
      final t = _target(m![1]!);
      return t == null ? null : [ToBase(t)];
    }
    if (mt(
          r'Move (.+?) to (a battlefield|any battlefield|a battlefield you control|that battlefield|this battlefield|the same battlefield|a different battlefield|its base|your base|base|there|here|that enemy unit.s battlefield|that unit.s battlefield)',
        ) !=
        null) {
      return _move(m![1]!, m![2]!);
    }
    if (mt(r'(?:Move|move) (.+)') != null && !m![1]!.contains(' to ')) {
      return _move(m![1]!, null);
    }
    // Returns and cards from zones.
    if (mt(r"Return (.+?) to (?:its|their) owners?'s? hands?") != null || mt(r"Return (.+?) to their owners' hands") != null) {
      final tp = m![1]!;
      final both = RegExp(r'^(.+) and (an .+|a .+)$').firstMatch(tp);
      if (both != null) {
        final a = _target(both[1]!);
        final b = a == null ? null : _target(both[2]!);
        return b == null ? null : [ToHand(a!), ToHand(b)];
      }
      if (tp.contains('trash')) {
        final t = _target(tp);
        return t == null ? null : [CardToHand(t)];
      }
      final t = _target(tp.startsWith('all ') || tp.startsWith('up to') || tp.startsWith('any number') ? tp : tp);
      return t == null ? null : [ToHand(t)];
    }
    if (mt(r'Return (.+?) to your hand') != null) {
      final t = _target(m![1]!);
      if (t == null) return null;
      return [CardToHand(t)];
    }
    // Banish, kill variants.
    if (mt(r'Banish (.+)') != null && !m![1]!.contains(',')) {
      if (m![1] == 'this' || m![1] == 'me') return null;
      final t = _target(m![1]!);
      return t == null ? null : [Banish(t)];
    }
    if (mt(r'Kill (.+?) or (.+)') != null && !m![1]!.contains(' and ')) return null;
    // Ready variants.
    if (mt(r'Ready (your|all friendly) units') != null) return [const Ready(Each(Filter(side: Side.friendly)))];
    if (mt(r'Ready or exhaust (a legend)') != null) return [ReadyAny(ChooseLegend(_take(1)), either: true)];
    if (mt(r'Ready (your legend)') != null) return [const ReadyAny(YourLegend())];
    if (mt(r'Ready up to (\d+) (?:friendly )?runes') != null) return [ReadyRunes(int.parse(m![1]!))];
    if (mt(r'Ready (?:up to )?(\d+) units, gear, and/or runes') != null) return null;
    if (mt(r'(?:Ready|ready) (something else that.s exhausted|something besides me that.s exhausted)') != null) {
      final t = _target(m![1]!);
      return t == null ? null : [ReadyAny(t)];
    }
    if (mt(r'Ready me and give me \+(\d+) \{M\} this turn') != null && card.type == CardType.unit) return [const Ready(Me()), GiveMight(int.parse(m![1]!), const Me())];
    // Buffs.
    if (mt(r'Buff me and draw (\d+)') != null && card.type == CardType.unit) return [const Buff(Me()), Draw(int.parse(m![1]!))];
    if (mt(r'Buff me and ready me') != null && card.type == CardType.unit) return [const Buff(Me()), const Ready(Me())];
    if (mt(r'(?:\[Buff\]|Buff) (up to \w+ .+)') != null) {
      final t = _target(m![1]!);
      return t == null ? null : [Buff(t)];
    }
    if (mt(r'Buff all (.+)') != null) {
      final t = _target('all ${m![1]}');
      return t == null ? null : [Buff(t)];
    }
    // Tokens.
    final tk = _tokenSentence(s);
    if (tk != null) return tk;
    // The top of the deck.
    final lt = _lookTop(s);
    if (lt != null) return lt;
    if (mt(r'Put the top (\d+) cards of your Main Deck into your trash') != null) return [Mill(int.parse(m![1]!))];
    if (mt(r'\[Burn (\d+)\]') != null) return [Mill(int.parse(m![1]!))];
    if (mt(r'(?:Recycle|recycle) (\d+) from your trash') != null) return [RecycleTrash(int.parse(m![1]!))];
    if (mt(r'(?:Recycle|recycle) one of your runes') != null) return [const RecycleRune()];
    // Each player…
    if (mt(r'Each player kills one of their (units|gear)') != null) return [EachKills(Filter(gear: m![1] == 'gear'))];
    if (mt(r'Each player chooses a unit they control\. Kill the rest') != null) return null;
    // Play from zones.
    if (mt(r'(?:Play|play) (a unit|a unit from your trash|.+? from your trash), ignoring its (Energy )?cost') != null) {
      final t = _target(m![1]!.contains('trash') ? m![1]! : '${m![1]} from your trash');
      if (t == null || !m![1]!.contains('trash')) return null;
      return [PlayFrom(t, ignoreAll: m![2] == null)];
    }
    // Score and win.
    if (mt(r'(?:You|you) win the game') != null) return [const ScoreP(0, PYou(), win: true)];
    if (mt(r'Take a turn after this one') != null && _isSpell) return [const ExtraTurn()];
    // Counter variants.
    if (_isSpell) {
      if (mt(r'Counter a spell unless its controller pays \{(\d+)\}') != null) return [CounterIt(ChooseSpell(_take(1)), unlessPay: int.parse(m![1]!))];
      if (mt(r'Counter a spell\. Return it to its owner.s hand instead of putting it in their trash') != null) return null;
      if (mt(r'Counter an enemy spell or ability that chooses a friendly unit or gear') != null) return [CounterIt(ChooseSpell(_take(1), enemy: true, abilities: true, choosingFriendly: true))];
      if (mt(r'Counter an enemy spell or ability that chooses it and no other friendly unit') != null && _gs.last != null) {
        return [CounterIt(ChooseSpell(_take(1), enemy: true, abilities: true, choosingSlot: _gs.last))];
      }
    }
    // "Spend any number of buffs" / "For each buff spent, X".
    if (mt(r'Spend any number of buffs') != null) {
      _gs.thatMuch = true;
      return [const SpendBuffs()];
    }
    if (mt(r'For each buff spent, (.+)') != null && _gs.thatMuch) {
      final e = _sentence(_Line._cap(m![1]!));
      return e == null ? null : [Repeat(const ThatMuch(), e)];
    }
    // "You may pay {1} to draw 1", "you may exhaust me to draw 1", "you may kill a gear. If you do, …".
    final pay = _payTo(s);
    if (pay != null) return pay;
    // Delayed effects (this turn).
    final d = _delay(s);
    if (d != null) return d;
    // "X if Y".
    if (mt(r'(.+?) if (.+)') != null && !m![2]!.startsWith('you have ')) {
      final c = _cond(m![2]!);
      final e = c == null ? null : _sentence(m![1]!);
      return e == null ? null : [If(c!, e)];
    }
    return null;
  }

  List<(Kw, int)>? _kwList(String s) {
    final out = <(Kw, int)>[];
    for (final m in RegExp(r'\[([A-Za-z]+)(?: (\d+))?\]').allMatches(s)) {
      final kw = _kwNames[m[1]!.toLowerCase()];
      if (kw == null) return null;
      out.add((kw, int.tryParse(m[2] ?? '') ?? 1));
    }
    final rest = s.replaceAll(RegExp(r'\[[A-Za-z]+(?: \d+)?\]'), '').replaceAll(RegExp(r'(,|and| )'), '');
    if (rest.isNotEmpty || out.isEmpty) return null;
    return out;
  }

  /// "Move X [to Y]" → a move with its destination chosen as it's played.
  List<Effect>? _move(String what, String? to) {
    if (to == null && what.endsWith(' there')) {
      what = what.substring(0, what.length - 6);
      to = 'there';
    }
    final t = _target(what);
    if (t == null) return null;
    final prevDest = _gs.destSlot;
    final slot = _take(1);
    _gs.destSlot = slot;
    // "That battlefield" / "the same battlefield": a chosen battlefield, an earlier move's
    // destination, the battlefield the trigger is about, or where this unit is.
    if (to == 'that battlefield' || to == 'the same battlefield' || to == 'there') {
      if (_gs.bfSlot != null) return [Move(t, Dest.slot, destSlot: slot, refSlot: _gs.bfSlot)];
      if (prevDest != null) return [Move(t, Dest.slot, destSlot: slot, refSlot: prevDest)];
      if (_eventBf) return [Move(t, Dest.event, destSlot: slot)];
      if (card.type == CardType.unit && to != 'there') return [Move(t, Dest.here, destSlot: slot)];
      return null;
    }
    final dest = switch (to) {
      null => Dest.any,
      'a battlefield' || 'any battlefield' => Dest.battlefield,
      'a battlefield you control' => Dest.yourBattlefield,
      'a different battlefield' => Dest.otherBattlefield,
      'its base' || 'your base' || 'base' => Dest.base,
      'here' || 'this battlefield' => Dest.here,
      'there' || 'that battlefield' || 'the same battlefield' => _gs.bfSlot != null || _gs.destSlot != slot ? Dest.slot : (_eventBf ? Dest.event : Dest.slot),
      _ when to.endsWith("unit's battlefield") || to.endsWith('unit’s battlefield') => Dest.slot,
      _ => null,
    };
    if (dest == null) return null;
    if (dest == Dest.here && !_unitOrBf) return null;
    int? ref;
    if (dest == Dest.slot) {
      if (to == 'there' || to == 'that battlefield') {
        if (_gs.bfSlot != null) {
          ref = _gs.bfSlot;
        } else if (_eventBf) {
          return [Move(t, Dest.event, destSlot: slot)];
        } else if (_gs.prev != null) {
          ref = _gs.prev;
        } else {
          return null;
        }
      } else {
        ref = _gs.prev;
        if (ref == null) return null;
      }
    }
    return [Move(t, dest, destSlot: slot, refSlot: ref)];
  }

  /// "for each battlefield you or allies control" → an amount (times [per], plus [plus]).
  Amount? _forEach(String what, int per, {int plus = 0}) {
    switch (what) {
      case 'battlefield you or allies control' || 'battlefield you control':
        return PlayerStat(Stat.battlefields, per: per, plus: plus);
      case 'other battlefield you or allies control' when _isBattlefield:
        // Said by a battlefield you control as it resolves: all but this one.
        return PlayerStat(Stat.battlefields, per: per, plus: plus - per);
      case 'of the following tags among your units - Bird, Cat, Dog, and Poro':
        return PlayerStat(Stat.tagsAmongUnits, per: per, plus: plus);
      case 'of your [Mighty] units':
        return CountOf(
          const Filter(side: Side.friendly, mighty: true),
          per: per,
          plus: plus,
        );
      case 'card in your trash':
        return PlayerStat(Stat.trash, per: per, plus: plus);
    }
    final m = RegExp(r'^(?:of )?(.+?)( there| here)?$').firstMatch(what)!;
    var body = m[1]!;
    if (RegExp(r'^(?:enemy|friendly|buffed friendly|token) unit(?: |$)').hasMatch(body)) {
      body = body.replaceFirst(RegExp(r'unit(?= |$)'), 'units');
    }
    final f = _np('$body${m[2] ?? ''}', plural: true);
    if (f == null) return null;
    return CountOf(f, per: per, plus: plus);
  }

  /// "a 1 {M} Recruit unit token [here]" → (token, count, ready, where).
  (String, int, bool, TokenAt)? _token(String s) {
    final m = RegExp(
      r'^(a|an|one|two|three|four|\d+)( ready)? (?:\{?(\d+)\}?) \{M\} (Recruit|Sprite|Sand Soldier|Mech|Bird|Tentacle) unit tokens?( with \[(?:Temporary|Deflect)\])?( here| to your base| into your base| in your base| at your base| there)?$',
    ).firstMatch(s);
    if (m != null) {
      final count = _n(m[1]!);
      if (count == null) return null;
      const mights = {'Recruit': 1, 'Sprite': 3, 'Sand Soldier': 2, 'Mech': 3, 'Bird': 1, 'Tentacle': 1};
      if (mights[m[4]!] != int.parse(m[3]!)) return null;
      final kw = m[5];
      if (kw != null && !((m[4] == 'Sprite' && kw.contains('Temporary')) || (m[4] == 'Bird' && kw.contains('Deflect')))) return null;
      if (m[4] == 'Bird' && kw == null) return null;
      final where = switch (m[6]) {
        ' here' => TokenAt.here,
        ' there' => TokenAt.there,
        _ => TokenAt.base,
      };
      if (where == TokenAt.here && card.type != CardType.unit) return null;
      return (m[4]!, count, m[2] != null, where);
    }
    final g = RegExp(r'^(a|an|one|two|three|four|\d+) Gold gear tokens?( exhausted)?$').firstMatch(s);
    if (g != null) {
      final count = _n(g[1]!);
      return count == null ? null : ('Gold', count, g[2] == null, TokenAt.base);
    }
    return null;
  }

  List<Effect>? _tokenSentence(String s) {
    final m = RegExp(r'^Play (.+)$').firstMatch(s);
    if (m == null) return null;
    final t = _token(m[1]!);
    if (t == null) return null;
    if (t.$4 == TokenAt.there && !_eventBf) return null;
    return [TokenP(t.$1, t.$2, const PYou(), ready: t.$3, where: t.$4 == TokenAt.there ? TokenAt.event : t.$4)];
  }

  /// "Look at the top N cards of your Main Deck. …" (several sentences, joined by the caller).
  List<Effect>? _lookTop(String s) {
    var m = RegExp(
      r'^Look at the top (\d+|two|three) cards of your Main Deck\. (Draw one and recycle the other|Put (\d+) into your hand and recycle the rest|You may reveal an? (unit|gear|spell) from among them and draw it\. (?:Then )?[Rr]ecycle the rest)$',
    ).firstMatch(s);
    if (m != null) {
      final n = _n(m[1]!)!;
      if (m[2]!.startsWith('Draw one')) return [LookTop(n, pick: 1, mayPick: false)];
      if (m[3] != null) return [LookTop(n, pick: int.parse(m[3]!), mayPick: false)];
      final type = switch (m[4]) {
        'unit' => CardType.unit,
        'gear' => CardType.gear,
        _ => CardType.spell,
      };
      return [
        LookTop(
          n,
          pick: 1,
          filter: Filter(types: {type}, zone: FZone.hand),
          revealed: true,
        ),
      ];
    }
    m = RegExp(r'^Reveal the top card of your Main Deck\. If it.s an? (unit|gear|spell), (draw it|put it in your hand)\. Otherwise, (recycle it|put it in your trash and give me \+2 \{M\} this turn)$')
        .firstMatch(s);
    if (m != null) {
      final type = switch (m[1]) {
        'unit' => CardType.unit,
        'gear' => CardType.gear,
        _ => CardType.spell,
      };
      if (m[3]!.startsWith('put') && card.type != CardType.unit) return null;
      return [
        RevealTop(Filter(types: {type}, zone: FZone.hand), RevealDo.hand, m[3]!.startsWith('recycle') ? RevealDo.recycle : RevealDo.trashAndMight2),
      ];
    }
    return null;
  }

  /// Costs inside instructions: "You may pay {1} to draw 1", "you may exhaust me to draw 1",
  /// "You may pay {A}{A}{A}{A} to score 1 point", "you may kill a unit you control here to draw 1".
  List<Effect>? _payTo(String s) {
    final m = RegExp(r'^(?:You|you|They|they) may (.+?) to (.+)$').firstMatch(s);
    if (m == null) return null;
    final costText = m[1]!;
    final body = _Line._cap(m[2]!);
    final parts = costText.split(RegExp(r',? and |, '));
    var energy = 0;
    final power = <Domain?>[];
    var exhaustMe = false;
    final actions = <CostAction>[];
    for (final part in parts) {
      final pm = RegExp(r'^pay ((?:\{[0-9A-Z]\})+)$').firstMatch(part);
      if (pm != null) {
        for (final x in RegExp(r'\{([0-9A-Z])\}').allMatches(pm[1]!)) {
          final n = int.tryParse(x[1]!);
          if (n != null) {
            energy += n;
          } else if (x[1] == 'A') {
            power.add(null);
          } else if (x[1] == 'C') {
            if (card.domains.length != 1) return null;
            power.add(card.domains.first);
          } else {
            final d = Domain.byName(x[1]!);
            if (d == null) return null;
            power.add(d);
          }
        }
        continue;
      }
      if ((part == 'exhaust me' && card.type != CardType.spell) || (part == 'exhaust this' && card.type == CardType.gear)) {
        exhaustMe = true;
        continue;
      }
      if (part == 'kill me' && card.type == CardType.unit) {
        actions.add(const CostAction(CostKind.killMe));
        continue;
      }
      final dm = RegExp(r'^discard (\d+)$').firstMatch(part);
      if (dm != null) {
        actions.add(CostAction(CostKind.discard, n: int.parse(dm[1]!)));
        continue;
      }
      final bm = RegExp(r'^\[Burn (\d+)\]$').firstMatch(part);
      if (bm != null) {
        actions.add(CostAction(CostKind.burn, n: int.parse(bm[1]!)));
        continue;
      }
      if (part == 'spend a buff') {
        actions.add(const CostAction(CostKind.spendBuff));
        continue;
      }
      final km = RegExp(r'^kill (a .+|an .+|another .+)$').firstMatch(part);
      if (km != null) {
        final f = _np(km[1]!.replaceFirst(RegExp(r'^(a|an|another) '), ''), plural: false);
        if (f == null) return null;
        actions.add(CostAction(CostKind.killOne, filter: km[1]!.startsWith('another') ? f.copyWith(other: true) : f));
        continue;
      }
      return null;
    }
    final e = _sentence(body);
    if (e == null) return null;
    return [PayTo(e, energy: energy, power: power, exhaustMe: exhaustMe, parts: actions)];
  }

  /// "This turn" rules set up by a spell or ability.
  List<Effect>? _delay(String s) {
    RegExpMatch? m;
    RegExpMatch? mt(String re) => m = RegExp('^$re\$').firstMatch(s);
    if (mt(r'When it dies this turn, (.+)') != null && _gs.last != null) {
      final e = _sentence(_Line._cap(m![1]!));
      return e == null ? null : [Delay(DelayKind.whenDies, effects: e, target: Chosen(_gs.last!))];
    }
    if (mt(r'Units you play this turn enter ready') != null) return [const Delay(DelayKind.unitsEnterReady)];
    if (mt(r'The next unit you play this turn enters ready') != null) return [const Delay(DelayKind.nextUnitReady)];
    if (mt(r'When a friendly unit is played this turn, buff it') != null) {
      return [
        const Delay(DelayKind.whenFriendlyPlayed, effects: [Buff(EventUnit())]),
      ];
    }
    if (mt(r'When any unit takes damage this turn, kill it') != null) return [const Delay(DelayKind.killDamaged)];
    if (mt(r'Kill it the next time it takes damage this turn') != null && _gs.last != null) return [Delay(DelayKind.killNextDamage, target: Chosen(_gs.last!))];
    if (mt(r'Prevent the next (\d+) damage that would be dealt to it this turn') != null && _gs.last != null) return [Delay(DelayKind.preventNext, target: Chosen(_gs.last!), n: int.parse(m![1]!))];
    if (mt(r'The next time that unit would be dealt damage this turn, prevent it') != null && _gs.last != null) return [Delay(DelayKind.preventNext, target: Chosen(_gs.last!))];
    if (mt(r'Prevent all spell and ability damage this turn') != null) return [const Delay(DelayKind.preventSpellDamage)];
    if (mt(r'The next time it (?:would die|dies) this turn, (heal it, exhaust it, and recall it|recall it exhausted) instead') != null && _gs.last != null) {
      return [Delay(DelayKind.saveNextDeath, target: Chosen(_gs.last!), n: m![1]!.startsWith('heal') ? 1 : 0)];
    }
    if (mt(r'If it would die this turn, banish it instead') != null && _gs.last != null) return [Delay(DelayKind.banishIfDies, target: Chosen(_gs.last!))];
    if (mt(r'The next spell you play this turn deals (\d+) Bonus Damage') != null) return [Delay(DelayKind.nextSpellBonus, n: int.parse(m![1]!))];
    if (mt(r'Ready (\d+) runes at the end of this turn') != null) {
      return [
        Delay(DelayKind.atEndOfTurn, effects: [ReadyRunes(int.parse(m![1]!))]),
      ];
    }
    if (mt(r'(?:Opponents|opponents) can.t play cards this turn') != null) return [const Delay(DelayKind.noCards)];
    if (mt(r'They can.t move it this turn') != null && _gs.last != null) return [Delay(DelayKind.cantMove, target: Chosen(_gs.last!))];
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Conditions
  // -------------------------------------------------------------------------------------------

  Cond? _genCond(String c0) {
    final c = c0.trim();
    RegExpMatch? m;
    RegExpMatch? mt(String re) => m = RegExp('^$re\$').firstMatch(c);
    CmpOp? op(String w) => switch (w) {
      'or more' || '+' => CmpOp.ge,
      'or fewer' || 'or less' => CmpOp.le,
      _ => null,
    };
    if (mt(r'you control (\d+|one|two|three|four|five|six|seven) or (more|fewer) runes') != null) {
      return StatCond(PStat.runes, m![2] == 'more' ? CmpOp.ge : CmpOp.le, _n(m![1]!)!);
    }
    if (mt(r'you have (\d+)\+ runes') != null) return StatCond(PStat.runes, CmpOp.ge, int.parse(m![1]!));
    if (mt(r'you control (\d+|one|two|three|four) or more (other )?(.+)') != null) {
      final f = _np(m![3]!, plural: true);
      if (f == null) return null;
      final n = _n(m![1]!)!;
      return CountCond(f.copyWith(side: Side.friendly, other: m![2] != null ? true : null), CmpOp.ge, n);
    }
    if (mt(r'you control (a|an|another) (.+)') != null) {
      final f = _np(m![2]!, plural: false);
      if (f == null) return null;
      return CountCond(f.copyWith(side: Side.friendly, other: m![1] == 'another' ? true : null), CmpOp.ge, 1);
    }
    if (mt(r'you have (two|three|one|\d+) or (fewer|more) cards in your hand') != null) return StatCond(PStat.hand, m![2] == 'fewer' ? CmpOp.le : CmpOp.ge, _n(m![1]!)!);
    if (mt(r'it is stunned') != null && _gs.last != null) return ObjCond(Chosen(_gs.last!), const Filter(stunned: true));
    if (mt(r"it.s already stunned") != null && _gs.last != null) return ObjCond(Chosen(_gs.last!), const Filter(stunned: true));
    if (mt(r'it (?:has|had) (\d+) \{M\} or less') != null && _gs.last != null) return ObjCond(Chosen(_gs.last!), Filter(mightMax: int.parse(m![1]!)));
    if (mt(r'it was an? (enemy|friendly) unit') != null && _gs.last != null) return ObjCond(Chosen(_gs.last!), Filter(side: m![1] == 'enemy' ? Side.enemy : Side.friendly));
    if (mt(r'I am at a battlefield') != null && card.type == CardType.unit) {
      _gs.thereIsHere = true;
      return const SelfCond(SelfKind.atBattlefield);
    }
    if (mt(r'I died alone') != null && card.type == CardType.unit) return const SelfCond(SelfKind.alone);
    if (mt(r"I didn't die alone") != null && card.type == CardType.unit) return const SelfCond(SelfKind.alone, negate: true);
    if (mt(r'I was \[Mighty\]') != null && card.type == CardType.unit) return const SelfCond(SelfKind.mighty);
    if (mt(r'you do') != null) return const DidCond(DidKind.paid);
    if (mt(r'this kills it') != null) return const DidCond(DidKind.killed);
    if (mt(r"it.s your Beginning Phase") != null) return const TurnEventCond(TurnEvent.isBeginningPhase);
    if (mt(r'there is exactly one other unit you control here') != null && card.type == CardType.unit) return const SelfCond(SelfKind.exactlyOneOtherHere);
    if (mt(r'you have (\d+)\+ units here') != null && _unitOrBf) return CountCond(const Filter(side: Side.friendly, where: Where.here), CmpOp.ge, int.parse(m![1]!));
    if (mt(r'your other units have total Might (\d+) or more') != null && card.type == CardType.unit) return TotalMightCond(const Filter(side: Side.friendly, other: true), int.parse(m![1]!));
    if (mt(r"there.s an enemy unit alone at that battlefield") != null) return null;
    if (mt(r'you assigned (\d+) or more excess damage(?: to enemy units)?') != null) return CombatCond(excess: int.parse(m![1]!));
    if (mt(r'you spent \{(\d+)\} or more') != null && _gs.spellTrig) return SpentOnSpell(int.parse(m![1]!));
    if (mt(r'there is a ready enemy unit here') != null && _unitOrBf) return const CountCond(Filter(side: Side.enemy, exhausted: false, where: Where.here), CmpOp.ge, 1);
    if (mt(r'you control fewer runes than an opponent') != null) return const StatCond(PStat.fewerRunesThanOpp, CmpOp.ge, 1);
    final o = op('');
    if (o != null) return null;
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Triggers
  // -------------------------------------------------------------------------------------------

  /// Trigger heads beyond the core's. Also sets which "it"/"they" the effect text refers to.
  When? _genWhen(String s) {
    final me = card.type == CardType.unit;
    final perm = card.isPermanent || card.type == CardType.legend;
    final self = card.isPermanent;
    switch (s) {
      case 'At the start of your Beginning Phase' when perm:
        return const When(On.startOfTurn);
      case 'At the start of your Main Phase' when perm:
        return const GenWhen(GEv.startOfMain);
      case "At the start of each player's Beginning Phase" when _isBattlefield:
        _gs.they = const PEvent();
        return const GenWhen(GEv.startOfEachTurn, by: Side.any);
      case "At the start of each player's first Beginning Phase" when _isBattlefield:
        _gs.they = const PEvent();
        return const GenWhen(GEv.startOfEachTurn, by: Side.any, firstOnly: true);
      case 'When you conquer or hold' when perm:
        _eventBf = true;
        return const GenWhen(GEv.conquerOrHold);
      case 'When you or an ally hold' when perm:
        _eventBf = true;
        return const When(On.youHold);
      case 'When you or an ally conquer' when perm:
        _eventBf = true;
        return const When(On.youConquer);
      case 'When I conquer or hold' when me:
        return const GenWhen(GEv.conquerOrHold, self: true);
      case "When I'm played and when I conquer" when me:
        return const GenWhen(GEv.played, self: true, alsoOn: [On.conquer]);
      case 'When you play me or when I hold' when me:
        return const GenWhen(GEv.played, self: true, alsoOn: [On.hold]);
      case 'When you play me or at the start of your Beginning Phase' when me:
        return const GenWhen(GEv.played, self: true, alsoOn: [On.startOfTurn]);
      case 'When you play this or at the start of your Beginning Phase' when card.type == CardType.gear:
        return const GenWhen(GEv.played, self: true, alsoOn: [On.startOfTurn]);
      case 'When you play me or another Dragon' when me:
        return const GenWhen(
          GEv.played,
          filter: Filter(side: Side.friendly, tag: 'Dragon'),
        );
      case 'When you play another unit' when self:
        _eventUnit = true;
        return const GenWhen(GEv.played, filter: Filter(side: Side.friendly, other: true));
      case 'When you play a token unit' when perm:
        _eventUnit = true;
        return const GenWhen(GEv.played, filter: Filter(side: Side.friendly, token: true));
      case 'When you play a gear' when perm:
        return const GenWhen(GEv.played, filter: Filter(side: Side.friendly, gear: true));
      case 'When you play a [Mighty] unit' when perm:
        _eventUnit = true;
        return const GenWhen(GEv.played, filter: Filter(side: Side.friendly, mighty: true));
      case 'When an opponent plays a unit while I\'m at a battlefield' when me:
        _eventUnit = true;
        return const GenWhen(
          GEv.played,
          filter: Filter(side: Side.enemy),
          by: Side.enemy,
          extra: ['meAtBf'],
        );
      case 'When an opponent plays a gear' when perm:
        return const GenWhen(
          GEv.played,
          filter: Filter(side: Side.enemy, gear: true),
          by: Side.enemy,
        );
      case 'When a player plays a unit here' when _isBattlefield:
        _eventUnit = true;
        _gs.they = const PEvent();
        return const GenWhen(
          GEv.played,
          filter: Filter(where: Where.here),
          by: Side.any,
          here: true,
        );
      case 'When you play a unit during a showdown' when perm:
        return const GenWhen(GEv.played, filter: Filter(side: Side.friendly), inShowdown: true);
      case "When you play a card on an opponent's turn" when perm:
        return const GenWhen(GEv.played, filter: Filter(types: {CardType.unit, CardType.gear, CardType.spell}), oppTurn: true);
      case "When you play a spell on an opponent's turn" when perm:
        return const GenWhen(GEv.spellPlayed, oppTurn: true);
      case 'When you play your second card in a turn' when perm:
        return const GenWhen(GEv.played, filter: Filter(types: {CardType.unit, CardType.gear, CardType.spell}), nth: 2);
      case 'When a player plays a spell' when _isBattlefield:
        _gs.they = const PEvent();
        return const GenWhen(GEv.anySpell, by: Side.any);
      case 'When a friendly unit dies' when perm:
        return const GenWhen(GEv.dies, filter: Filter(side: Side.friendly));
      case 'When another friendly unit dies' when self:
        return const GenWhen(GEv.dies, filter: Filter(side: Side.friendly, other: true));
      case 'When a buffed friendly unit dies' when perm:
        return const GenWhen(GEv.dies, filter: Filter(side: Side.friendly, buffed: true));
      case 'When another non-Recruit unit you control dies' when self:
        return const GenWhen(
          GEv.dies,
          filter: Filter(side: Side.friendly, other: true, notTag: 'Recruit'),
        );
      case 'When one or more enemy units die' when perm:
        return const GenWhen(
          GEv.dies,
          filter: Filter(side: Side.enemy),
          extra: ['once'],
        );
      case 'The first time a friendly unit dies each turn' when perm:
        return const GenWhen(GEv.dies, filter: Filter(side: Side.friendly), limit: 1);
      case 'When I die in combat' when me:
        return null;
      case 'When you buff me' when me:
        return const GenWhen(GEv.buffed, self: true);
      case 'When you buff a friendly unit' when perm:
        _eventUnit = true;
        return const GenWhen(GEv.buffed, filter: Filter(side: Side.friendly));
      case 'When I become ready' when me:
        return const GenWhen(GEv.readied, self: true);
      case 'When you ready a friendly unit' when perm:
        _eventUnit = true;
        return const GenWhen(GEv.readied, filter: Filter(side: Side.friendly));
      case 'When you choose or ready me' when me:
        return const GenWhen(GEv.chosen, self: true, extra: ['orReady']);
      case 'When you choose a friendly unit' when perm:
        _eventUnit = true;
        return const GenWhen(GEv.chosen, filter: Filter(side: Side.friendly));
      case 'When you choose me with a spell' when me:
        return const GenWhen(GEv.chosen, self: true, extra: ['spell']);
      case 'When you discard one or more cards' when perm:
        return const GenWhen(GEv.discarded, extra: ['once']);
      case 'When you stun an enemy unit' || 'When you [Stun] an enemy unit at a battlefield' when perm:
        _eventUnit = true;
        return GenWhen(
          GEv.stunned,
          filter: Filter(side: Side.enemy, where: s.contains('battlefield') ? Where.battlefield : Where.anywhere),
        );
      case 'When I move from a battlefield' when me:
        return const GenWhen(GEv.moved, self: true, by: Side.any, extra: ['fromBf']);
      case 'When a unit moves from here' when _isBattlefield:
        _eventUnit = true;
        return const GenWhen(GEv.moved, by: Side.any, extra: ['fromHere']);
      case 'The first time I move each turn' when me:
        return const GenWhen(GEv.moved, self: true, by: Side.any, nth: 1);
      case 'The third time I move in a turn' when me:
        return const GenWhen(GEv.moved, self: true, by: Side.any, nth: 3);
      case 'When you move an enemy unit' when perm:
        _eventUnit = true;
        return const GenWhen(GEv.moved, filter: Filter(side: Side.enemy));
      case 'When you defend here' when _isBattlefield:
        return const GenWhen(GEv.defend, here: true);
      case 'When combat starts here' when _isBattlefield:
        return const GenWhen(GEv.combatHere, by: Side.any, here: true);
      case 'When you draw your second card each turn' when perm:
        return const GenWhen(GEv.drawSecond);
      case 'When you recycle one or more cards' when perm:
        return const GenWhen(GEv.recycled, extra: ['once']);
      case 'When an opponent scores' when perm:
        return const GenWhen(GEv.oppScores, by: Side.enemy);
      case 'When this leaves the board' when card.type == CardType.gear:
        return const GenWhen(GEv.leaves, self: true);
      case 'When you spend a buff' when perm:
        return const GenWhen(GEv.spentBuff);
      case 'When you use an activated ability of a gear' when perm:
        return const GenWhen(GEv.gearAbility);
      case 'When you kill a stunned enemy unit' when perm:
        return const GenWhen(GEv.youKill, filter: Filter(side: Side.enemy, stunned: true));
      case 'When a unit you control becomes [Mighty]' || 'When one of your units becomes [Mighty]' when perm:
        _eventUnit = true;
        return const GenWhen(GEv.becomesMighty, filter: Filter(side: Side.friendly));
      case 'When an opponent moves to a battlefield other than mine' when me:
        return const GenWhen(GEv.oppMoves, by: Side.enemy);
      case 'When a friendly unit attacks or defends alone' when perm:
        _eventUnit = true;
        return const GenWhen(GEv.aloneInCombat);
      case 'When another friendly unit dies' when card.type == CardType.legend:
        return const GenWhen(GEv.dies, filter: Filter(side: Side.friendly));
      case 'When you discard me' when me:
        _gs.fromTrash = true;
        return const GenWhen(GEv.discarded, self: true);
      case 'When you defend at a battlefield' when perm:
        _eventBf = true;
        return const GenWhen(GEv.defendAnywhere);
      case 'When I move from a location' when me:
        _eventBf = true;
        return const GenWhen(GEv.moved, self: true, by: Side.any, extra: ['fromLoc']);
      case 'When you recycle a rune' when perm:
        return const GenWhen(GEv.recycled, extra: ['rune']);
    }
    return null;
  }

  /// Triggered abilities (all of them, so a condition right after the trigger is part of it,
  /// CR 383.2.a.1), the "Nth time" and "once each turn" forms, and heads with commas.
  Ability? _genTriggered(String t, String line) {
    var limit = 0;
    var s = t;
    final once = RegExp(r'^Once each turn, (when .+)$').firstMatch(s);
    if (once != null) {
      limit = 1;
      s = _Line._cap(once[1]!);
    }
    if (!RegExp(r'^(When|At|The (first|third) time) ').hasMatch(s)) return null;
    // "When I conquer after an attack": a conquer that a combat it attacked in caused.
    Cond? extra;
    if (s.startsWith('When I conquer after an attack, ') && card.type == CardType.unit) {
      s = 'When I conquer, ${s.substring(32)}';
      extra = const CombatCond(afterAttack: true);
    }
    if (s.contains('excess damage')) _gs.excess = true;
    // Try each comma as the end of the trigger condition, shortest first.
    for (var i = s.indexOf(', '); i > 0; i = s.indexOf(', ', i + 1)) {
      final head = s.substring(0, i);
      final body = s.substring(i + 2);
      _eventUnit = false;
      _eventBf = false;
      final g0 = _gs.they;
      _gs.spellTrig = head == 'When you play a spell';
      var w = _when(head);
      if (w == null) {
        _gs.they = g0;
        continue;
      }
      if (w is! GenWhen) {
        _eventUnit = w.on == On.enemyAttacksYourBf;
        _eventBf = const {On.youConquer, On.youHold, On.conquerHere, On.holdHere}.contains(w.on) || _eventBf;
      }
      if (limit > 0) {
        if (w is GenWhen) {
          w = GenWhen(
            w.ev,
            filter: w.filter,
            by: w.by,
            self: w.self,
            here: w.here,
            limit: limit,
            nth: w.nth,
            extra: w.extra,
            alsoOn: w.alsoOn,
            firstOnly: w.firstOnly,
            oppTurn: w.oppTurn,
            inShowdown: w.inShowdown,
          );
        } else {
          return null;
        }
      }
      // A condition right after the trigger is part of the trigger condition.
      final cm = RegExp(r'^if (.+?), (.+)$').firstMatch(body);
      if (cm != null) {
        final c = _cond(cm[1]!);
        if (c != null) {
          final e = _effects(_Line._cap(cm[2]!));
          if (e == null) return null;
          return Triggered(line, w, [
            TrigIf(extra == null ? c : AndCond([extra, c]), e),
          ]);
        }
      }
      final e = _effects(_Line._cap(body));
      if (e == null) return null;
      return Triggered(line, w, extra == null ? e : [TrigIf(extra, e)]);
    }
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Whole abilities and passives
  // -------------------------------------------------------------------------------------------

  Ability? _genAbility(String t, String line) {
    if (t == '[Reaction]' && card.isPermanent) return KeywordAb(line, Kw.reaction);
    if (_isSpell && t == "This can't be countered.") return Static(line, const CantBeCountered());
    if (_isSpell && t == "This spell's Energy cost is reduced by the highest Might among units you control.") return Static(line, const SelfCostByMight());
    // "If you control fewer runes than an opponent at the start of your Beginning Phase, give me …":
    // a trigger at the start of the turn with a condition.
    var tm = RegExp(r'^If (.+) at the start of your Beginning Phase, (.+)$').firstMatch(t);
    if (tm != null && (card.isPermanent || card.type == CardType.legend)) {
      final c = tm[1] == 'you control fewer runes than an opponent' ? const StatCond(PStat.fewerRunesThanOpp, CmpOp.ge, 1) : _cond(tm[1]!);
      final e = c == null ? null : _effects(_Line._cap(tm[2]!));
      return e == null ? null : Triggered(line, const When(On.startOfTurn), [TrigIf(c!, e)]);
    }
    // "{E}: [Legion] - …": usable once you've played another card this turn.
    tm = RegExp(r'^([^:]+): \[Legion\] - (.+)$').firstMatch(t);
    if (tm != null && !_isSpell && !_isBattlefield) {
      final cost = _cost(tm[1]!);
      final e = cost == null ? null : _effects(_Line._cap(tm[2]!));
      return e == null ? null : Activated(line, cost!, e, legion: true);
    }
    final kws = _kwList(t);
    if (kws != null && t.contains('], [')) {
      // "[Assault 2], [Shield 2]" on one line.
      if (kws.length != 2) return null;
      return null;
    }
    if (RegExp(r'^(When|At|The (first|third) time|Once each turn, when) ').hasMatch(t)) {
      final a = _genTriggered(t, line);
      if (a != null) return a;
      // Fall through to the core (it records why it can't read it).
      return null;
    }
    return null;
  }

  Passive? _genPassive(String t) {
    RegExpMatch? m;
    RegExpMatch? mt(String re) => m = RegExp('^$re\$').firstMatch(t);
    final me = card.type == CardType.unit;
    if (mt(r'Your units here with less Might than me can.t be chosen by enemy spells and abilities\.') != null && me) {
      return const UntargetableOthers(Filter(side: Side.friendly, where: Where.here, lessMightThanMe: true));
    }
    if (mt(r'While you control (\d+) or more runes, prevent all damage that enemy spells and abilities would deal to me\.') != null && me) {
      return PreventEnemySpellDamage(StatCond(PStat.runes, CmpOp.ge, int.parse(m![1]!)));
    }
    if (mt(r'If you.ve spent at least \{A\}\{A\} this turn, I have \+(\d+) \{M\} and (\[.+\])\.') != null && me) {
      final kws = _kwList(m![2]!);
      return kws == null ? null : SelfBoost(might: N(int.parse(m![1]!)), kws: kws, cond: const StatCond(PStat.powerSpentThisTurn, CmpOp.ge, 2));
    }
    // Anthems: "[Filter] have +N {M} / [Keywords]".
    if (mt(r'(While I.m at a battlefield, )?(Your|your|Other|Friendly|Units|Stunned) (.+?) (?:each )?(?:have|has) (.+?)(, to a minimum of (\d+) \{M\})?( if they didn.t already)?\.') != null) {
      final cond = m![1] == null ? null : (me ? const SelfCond(SelfKind.atBattlefield) : null);
      if (m![1] != null && cond == null) return null;
      var subject = '${m![2]} ${m![3]}';
      var other = false;
      if (subject.startsWith('Other ')) {
        other = true;
        subject = subject.substring(6);
      }
      if (subject.startsWith('Your other ')) {
        other = true;
        subject = 'your ${subject.substring(11)}';
      }
      if (subject.startsWith('your other ')) {
        other = true;
        subject = 'your ${subject.substring(11)}';
      }
      subject = subject.replaceFirst(RegExp(r'^Your '), 'your ').replaceFirst(RegExp(r'^Friendly '), 'friendly ').replaceFirst(RegExp(r'^Stunned '), 'stunned ');
      if (subject == "your Mechs'" || subject.contains("'")) return null;
      var f = _np(subject.startsWith('Units ') ? 'units ${subject.substring(6)}' : subject, plural: true);
      if (f == null) return null;
      if (other) {
        if (!card.isPermanent) return null;
        f = f.copyWith(other: true);
      }
      if (f.side == Side.any && f.where != Where.here && !(_isBattlefield)) return null;
      final what = m![4]!;
      final mm = RegExp(r'^([+-])(\d+) \{M\}$').firstMatch(what);
      if (mm != null) {
        final n = int.parse(mm[2]!) * (mm[1] == '-' ? -1 : 1);
        return GAnthem(f, might: n, cond: cond, mightFloor: m![6] == null ? null : int.parse(m![6]!));
      }
      final kws = _kwList(what);
      if (kws == null) return null;
      return GAnthem(f, kws: kws, cond: cond, ifNotAlready: m![7] != null);
    }
    // Self boosts.
    if (me) {
      if (mt(r'While I.m buffed, I have (?:an additional )?\+(\d+) \{M\}\.') != null) return SelfBoost(might: N(int.parse(m![1]!)), cond: const SelfCond(SelfKind.buffed));
      if (mt(r'While I.m buffed, I have (\[.+\])\.') != null) {
        final kws = _kwList(m![1]!);
        return kws == null ? null : SelfBoost(kws: kws, cond: const SelfCond(SelfKind.buffed));
      }
      if (mt(r'While I.m \[Mighty\], I have (.+)\.') != null) {
        final kws = _kwList(m![1]!);
        return kws == null ? null : SelfBoost(kws: kws, cond: const SelfCond(SelfKind.mighty));
      }
      if (mt(r'I have \+(\d+) \{M\} while I.m attacking with another unit\.') != null) return SelfBoost(might: N(int.parse(m![1]!)), cond: const SelfCond(SelfKind.attackingWithAnother));
      if (mt(r'While I.m attacking or defending alone, I have \+(\d+) \{M\}\.') != null) return SelfBoost(might: N(int.parse(m![1]!)), cond: const SelfCond(SelfKind.attackingOrDefendingAlone));
      if (mt(r'While you have another unit here, I have \+(\d+) \{M\}\.') != null) return SelfBoost(might: N(int.parse(m![1]!)), cond: const SelfCond(SelfKind.anotherHere));
      if (mt(r'While you have (\d+)\+ runes, I have \+(\d+) \{M\}\.') != null) return SelfBoost(might: N(int.parse(m![2]!)), cond: StatCond(PStat.runes, CmpOp.ge, int.parse(m![1]!)));
      if (mt(r'My Might is increased by your points\.') != null) return const SelfBoost(might: PlayerStat(Stat.points));
      if (mt(r'My Might is increased by the number of cards in your trash\.') != null) return const SelfBoost(might: PlayerStat(Stat.trash));
      if (mt(r'I (?:have|get) \+(\d+) \{M\} for each (.+)\.') != null) {
        final a = _forEach(m![2]!, int.parse(m![1]!));
        return a == null ? null : SelfBoost(might: a);
      }
      if (mt(r'I have \[(Assault)\] equal to the number of (.+)\.') != null) {
        final a = _forEach(m![2]!.replaceFirst(RegExp(r'^gear you control$'), 'gear you control'), 1);
        return a == null ? null : SelfBoost(kwAmount: (Kw.assault, a));
      }
      if (mt(r'If you.ve discarded a card this turn, I have (\[.+\])\.') != null) {
        final kws = _kwList(m![1]!);
        return kws == null ? null : SelfBoost(kws: kws, cond: const StatCond(PStat.discardedThisTurn, CmpOp.ge, 1));
      }
      if (mt(r'If you.ve spent \{(\d+)\} or more to play a spell this turn, I have \+(\d+) \{M\}\.') != null) {
        return SelfBoost(might: N(int.parse(m![2]!)), cond: StatCond(PStat.maxSpellSpend, CmpOp.ge, int.parse(m![1]!)));
      }
      // Entering ready.
      if (mt(r'I enter ready if (.+)\.') != null || mt(r'If (.+), I enter ready\.') != null) {
        final c = _readyCond(m![1]!);
        return c == null ? null : EnterReady(cond: c);
      }
      if (t == "I can't be chosen by enemy spells and abilities.") return const Restrict(RKind.untargetable);
      if (t == "I can't be chosen by enemy spells and abilities unless I'm in combat.") return const Restrict(RKind.untargetable, cond: SelfCond(SelfKind.inCombat, negate: true));
      if (t == "I can't move to base.") return const Restrict(RKind.cantMoveToBase);
      if (t == "I can't be readied.") return const Restrict(RKind.cantBeReadied);
      if (t == "I can't be played on your first, second, or third turns.") return const Restrict(RKind.notBeforeTurn4);
      if (t == 'Play me only to a battlefield you conquered this turn.') return const Restrict(RKind.onlyToConquered);
      if (t == "I can be played to a battlefield you're attacking.") return null;
      if (t == 'I can have any number of buffs.') return const Restrict(RKind.manyBuffs);
      if (t == 'Use my abilities only while I\'m at a battlefield.') return const Restrict(RKind.abilitiesOnlyAtBf);
      if (t == 'While I\'m at a battlefield, opponents can\'t score points.') return const Restrict(RKind.oppCantScore);
      if (t == "I don't deal combat damage unless I'm at a battlefield with exactly one other unit you control.") return const Restrict(RKind.noCombatDamageUnless);
      if (t == 'Other friendly units enter ready.') return const EnterReady(others: Filter(side: Side.friendly));
      if (t == 'Your tokens enter ready.') {
        return const EnterReady(
          others: Filter(side: Side.friendly, token: true, types: {CardType.unit, CardType.gear}),
        );
      }
      if (t == 'Your spells and abilities deal 1 Bonus Damage.') return const Restrict(RKind.bonusDamage, n: 1);
      if (t == 'You ignore [Tank] while assigning combat damage here.') return const Restrict(RKind.ignoreTankHere);
      if (t == 'Your [Deathknell] effects trigger an additional time.') return const Restrict(RKind.deathknellTwice);
      if (t == 'Your conquer effects for conquering here trigger an additional time.') return const Restrict(RKind.conquerTwiceHere);
      if (t == 'Your hold effects for holding here trigger an additional time.') return const Restrict(RKind.holdTwiceHere);
      if (t == 'Any amount of your damage is enough to kill enemy units.') return const Restrict(RKind.anyDamageKills);
      if (t == 'Units can\'t move to base.') return const Restrict(RKind.noneMoveToBase);
      if (t == 'While I\'m at a battlefield, spells and abilities can\'t ready enemy units and gear.') return const Restrict(RKind.noReadyEnemies);
      if (t == 'While I\'m at a battlefield, opponents can only play units to their base.') return const Restrict(RKind.oppUnitsOnlyToBase);
      if (mt(r'While I.m at a battlefield, the Energy costs for spells you play is reduced by \{(\d+)\}, to a minimum of \{(\d+)\}\.') != null) {
        return CostReduce(int.parse(m![1]!), int.parse(m![2]!), spells: true, cond: const SelfCond(SelfKind.atBattlefield));
      }
      if (mt(r'Your ([A-Z][a-z]+)s. Energy costs are reduced by \{(\d+)\}, to a minimum of \{(\d+)\}\.') != null) {
        return CostReduce(int.parse(m![2]!), int.parse(m![3]!), filter: Filter(tag: m![1]));
      }
    }
    if (_isBattlefield) {
      if (t == 'Units can\'t move from here to base.') return const Restrict(RKind.noneMoveFromHereToBase);
      if (t == 'Units can\'t be played here.') return const Restrict(RKind.noPlayHere);
      if (t == 'Players can\'t score here until their third turn.') return const Restrict(RKind.noScoreBeforeTurn3);
      if (mt(r'Increase the points needed to win the game by (\d+)\.') != null) return Restrict(RKind.victoryPlus, n: int.parse(m![1]!));
      if (mt(r'While a unit here is defending alone, it has -(\d+) \{M\}\.') != null) return Restrict(RKind.loneDefenderMinus, n: int.parse(m![1]!));
      if (mt(r'Spells and abilities affecting units here each deal (\d+) Bonus Damage\.') != null) return Restrict(RKind.bonusDamageHere, n: int.parse(m![1]!));
    }
    if (card.type == CardType.gear || card.type == CardType.legend) {
      if (t == 'Your spells and abilities deal 1 Bonus Damage.') return const Restrict(RKind.bonusDamage, n: 1);
    }
    return null;
  }

  Cond? _readyCond(String c) {
    RegExpMatch? m;
    RegExpMatch? mt(String re) => m = RegExp('^$re\$').firstMatch(c);
    if (mt(r'you control another ([A-Z][a-z]+)') != null) return CountCond(Filter(side: Side.friendly, other: true, tag: m![1]), CmpOp.ge, 1);
    if (mt(r'you have two or more other units in your base') != null) return const CountCond(Filter(side: Side.friendly, other: true, where: Where.base), CmpOp.ge, 2);
    if (mt(r'you have (two|one) or fewer cards in your hand') != null) return StatCond(PStat.hand, CmpOp.le, _n(m![1]!)!);
    if (mt(r'a unit died this turn') != null) return const TurnEventCond(TurnEvent.unitDied);
    if (mt(r'a friendly unit died during your Beginning Phase this turn') != null) return const TurnEventCond(TurnEvent.friendlyDiedInBeginning);
    if (mt(r'an opponent controls a battlefield') != null) return const StatCond(PStat.oppControlsBattlefield, CmpOp.ge, 1);
    if (mt(r"an opponent.s score is within (\d+) points of the Victory Score") != null) return StatCond(PStat.pointsToWin, CmpOp.le, int.parse(m![1]!), who: const POpponent());
    if (mt(r"your score is not within (\d+) points of the Victory Score") != null) return StatCond(PStat.pointsToWin, CmpOp.gt, int.parse(m![1]!));
    if (mt(r'you have a card with my name in your trash') != null) return const NameInTrash();
    return _cond(c);
  }

  // -------------------------------------------------------------------------------------------
  // Costs
  // -------------------------------------------------------------------------------------------

  bool _genCostPart(String part, List<CostPart> out) {
    RegExpMatch? m;
    RegExpMatch? mt(String re) => m = RegExp('^$re\$').firstMatch(part);
    if (mt(r'Discard (\d+)') != null) {
      out.add(DiscardCost(int.parse(m![1]!)));
      return true;
    }
    if (mt(r'Discard a gear') != null) {
      out.add(const DiscardCost(1, filter: Filter(gear: true, zone: FZone.hand)));
      return true;
    }
    if (mt(r'Recycle (\d+) from your trash') != null) {
      out.add(RecycleTrashCost(int.parse(m![1]!)));
      return true;
    }
    if (mt(r'Recycle a unit from your trash') != null) {
      out.add(
        const RecycleTrashCost(
          1,
          filter: Filter(zone: FZone.trash, side: Side.friendly),
        ),
      );
      return true;
    }
    if (mt(r'Kill a friendly unit or gear') != null) {
      out.add(const KillCost(Filter(side: Side.friendly, types: {CardType.unit, CardType.gear})));
      return true;
    }
    if (mt(r'Spend my buff') != null && card.type == CardType.unit) {
      out.add(const SpendMyBuffCost());
      return true;
    }
    if (mt(r'Exhaust a unit you control') != null) {
      out.add(const ExhaustCost(Filter(side: Side.friendly)));
      return true;
    }
    return false;
  }
}
