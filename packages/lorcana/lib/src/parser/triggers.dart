part of 'parser.dart';

typedef _Head = List<(Trigger, Cond?, bool)>;

/// Trigger conditions (CR 6.2.1) beyond the basic ones: inkwell, damage removed, cards put
/// under, shifting, discarding, returning to hand, songs, challenges with conditions, "while
/// here" locations and abilities with two triggers ("when you play this character and when he
/// leaves play", CR 6.2.6).
extension _Triggers on _CardParser {
  static const _self = r'this character|this item|this location|he|she|they|it';

  _Head? _moreTriggerHead(String h) {
    final s4 = _s4TriggerHead(h);
    if (s4 != null) return s4;
    // Printed typos.
    final fixed = h
        .replaceFirst(RegExp(r'^whenever your play '), 'whenever you play ')
        .replaceFirst(RegExp(r'^when play '), 'when you play ')
        .replaceFirstMapped(RegExp(r'^(when|whenever) a this '), (m) => '${m[1]} this ')
        .replaceAll(' challenge another', ' challenges another')
        .replaceAllMapped(RegExp(r"\b(he|she|they)'s "), (m) => '${m[1]} is ');
    if (fixed != h) return _quiet(() => _triggerHead(fixed));
    // "... during your turn", "... while this character is exerted": checked as it triggers.
    for (final (suffix, cond) in const [(' during your turn', YourTurn()), (' while this character is exerted', SelfState(exerted: true))]) {
      if (!h.endsWith(suffix)) continue;
      final inner = _quiet(() => _triggerHead(h.substring(0, h.length - suffix.length)));
      return inner == null ? null : [for (final t in inner) (t.$1, _and(t.$2, cond), t.$3)];
    }
    // Two triggers: "when you play this character and whenever she's challenged" (CR 6.2.6).
    final and = RegExp(r'^(.+?) and ((?:when|whenever|at the start|at the end) .+)$').firstMatch(h);
    if (and != null) {
      final a = _quiet(() => _triggerHead(and.group(1)!));
      final b = a == null ? null : _quiet(() => _triggerHead(and.group(2)!));
      if (a != null && b != null) return [...a, ...b];
    }
    return _quiet(() => _plainHead(h));
  }

  /// Runs [f]; when it fails, drops what it recorded in the diagnostics.
  _Head? _quiet(_Head? Function() f) {
    final d = LorcanaParser.diag;
    final n = d?.length ?? 0;
    final r = f();
    if (r == null && d != null && d.length > n) d.removeRange(n, d.length);
    return r;
  }

  _Head? _plainHead(String h) {
    _Head one(Trigger t, [Cond? c]) => [(t, c, false)];

    // Inkwell (CR 4.2, 7.5).
    if (rx(h, r'(?:whenever|when) (?:a card is put into your inkwell|you put a card into your inkwell)') != null) {
      return one(const On(Happening.inked, by: Owner.yours));
    }
    // Damage removed (CR 1.9.2).
    var m = rx(h, r'whenever you remove (?:(\d+) or more )?damage from (one of your characters|a character)');
    if (m != null) {
      return one(
        On(
          Happening.damageRemoved,
          subject: m[2] == 'a character' ? const Filter() : const Filter(owner: Owner.yours),
          by: Owner.yours,
          min: m[1].isEmpty ? 0 : int.parse(m[1]),
        ),
      );
    }
    if (rx(h, r'whenever you ready this character') != null) return one(const CardEvent(Event.readied));
    // Shift (CR 8.10).
    if (rx(h, r'when you (?:play a floodborn character on this card|shift a character on top of (?:this character|him|her|them))') != null) {
      return one(const On(Happening.shiftedOnto, self: true));
    }
    if (h == 'when you shift this character') return one(const On(Happening.shifted, self: true));
    // Playing cards (CR 4.3).
    if (h == "whenever you play an action that isn't a song") return one(const CardPlayed(Filter(types: {CardType.action}, song: false)));
    if (h == 'whenever you play a second action in a turn') return one(const CardPlayed(Filter(types: {CardType.action}), nth: 2));
    if (h == 'whenever another character is played') return one(const CardPlayed(Filter(other: true), by: Owner.any));
    m = rx(h, r'whenever you play this or another (.+)');
    if (m != null) {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      return f == null ? null : one(CardPlayed(f));
    }
    m = rx(h, r'(?:when|whenever) (you|an opponent|one of your opponents) plays? (?:a|an|another) (.+?)( with boost)?');
    if (m != null && (m[3].isNotEmpty || h.startsWith('when '))) {
      var f = filter(m[2], Owner.any, cardTypes: true);
      if (f == null) return null;
      if (m[3].isNotEmpty) f = f.copyWith(withKw: Kw.boost);
      return one(CardPlayed(f, by: m[1] == 'you' ? Owner.yours : Owner.opposing));
    }
    // Cards under (Boost, CR 8.4).
    if (h == 'whenever you put a card under this character') return one(const On(Happening.putUnder, self: true));
    m = rx(h, r'whenever you put a card under one of your (.+)');
    if (m != null) {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      return f == null ? null : one(On(Happening.putUnder, subject: f, by: Owner.yours));
    }
    // Songs (CR 5.4.4, 8.12).
    if (h == 'whenever one or more of your characters sings a song') return one(const On(Happening.songSung, by: Owner.yours));
    // Choosing (CR 6.1.4).
    if (rx(h, r'whenever an opponent chooses this (?:character|item|location) for an action or ability') != null) return one(const On(Happening.chosenByOpponent, self: true));
    if (h == 'whenever one of your characters is chosen for support') return one(const On(Happening.supportChosen, subject: Filter(owner: Owner.yours)));
    // Paying ink (CR 4.3.2.4).
    m = rx(h, r'whenever you pay (\d+) ink or less to play a card');
    if (m != null) return one(On(Happening.inkPaid, by: Owner.yours, max: int.parse(m[1])));
    // Discarding (CR 7.4.5).
    if (h == 'when you discard this card') return one(const On(Happening.discarded, self: true));
    m = rx(h, r'whenever you discard (?:a|an) (.+)');
    if (m != null) {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      return f == null ? null : one(On(Happening.discarded, subject: f, by: Owner.yours));
    }
    m = rx(h, r'whenever (?:your opponents|an opponent) discards? (\d+) or more cards');
    if (m != null) return one(On(Happening.discardedCards, by: Owner.opposing, min: int.parse(m[1])));
    // Discard to hand.
    m = rx(h, r'whenever you return (?:a|an) (.+?) from your discard to your hand');
    if (m != null) {
      final f = filter(m[1], Owner.yours, cardTypes: true);
      return f == null ? null : one(On(Happening.returnedFromDiscard, subject: f, by: Owner.yours));
    }
    // Turn steps (CR 3.4.1.1).
    m = rx(h, r"at the end of each (opponent|player)'s turn");
    if (m != null) return one(TurnStep(start: false, yours: false, opponents: m[1] == 'opponent'));
    if (h == 'whenever an opponent draws a card during their turn') return one(const Draws(Owner.opposing, theirTurn: true));
    // "[Subject] [does something]" (CR 6.2.1).
    // Tries each split into subject and predicate, shortest subject first.
    m = rx(h, r'(?:when|whenever) (.+)');
    if (m == null) return null;
    final words = m[1].split(' ');
    for (var i = 1; i < words.length; i++) {
      final subj = words.take(i).join(' '), pred = words.skip(i).join(' ');
      final named = RegExp(r'^this character or one of your characters named (.+)$').firstMatch(subj);
      if (named != null) {
        final a = _subjectEvent(null, pred);
        final b = _subjectEvent(Filter(owner: Owner.yours, named: named.group(1)), pred);
        if (a != null && b != null) return [...one(a), ...one(b)];
        continue;
      }
      final s = _subject(subj);
      if (s == null) continue;
      final t = _subjectEvent(s.$1, pred);
      if (t != null) return one(t);
    }
    return null;
  }

  /// The card a trigger is about: (null) for this card.
  (Filter?,)? _subject(String s) {
    if (RegExp('^(?:$_self)\$').hasMatch(s)) return (null,);
    var m = RegExp(r'^one of your opponents. (.+)$').firstMatch(s);
    if (m != null) {
      final f = filter(_plural(m.group(1)!), Owner.opposing, cardTypes: true);
      return f == null ? null : (f,);
    }
    m = RegExp(r'^one of your (other )?(.+)$').firstMatch(s);
    if (m != null) {
      final f = filter(_plural(m.group(2)!), Owner.yours, cardTypes: true);
      return f == null ? null : (m.group(1) == null ? f : f.copyWith(other: true),);
    }
    m = RegExp(r'^an opposing (.+)$').firstMatch(s);
    if (m != null) {
      final f = filter(m.group(1)!, Owner.opposing, cardTypes: true);
      return f == null ? null : (f,);
    }
    m = RegExp(r'^another (.+)$').firstMatch(s);
    if (m != null) {
      final f = filter(m.group(1)!, Owner.any, cardTypes: true);
      return f == null ? null : (f.copyWith(other: true),);
    }
    m = RegExp(r'^an? (.+)$').firstMatch(s);
    if (m != null) {
      final f = filter(m.group(1)!, Owner.any, cardTypes: true);
      return f == null ? null : (f,);
    }
    return null;
  }

  /// What the subject does: "challenges a damaged character", "quests while here"…
  Trigger? _subjectEvent(Filter? f, String p0) {
    var p = p0;
    var here = false;
    Filter? where;
    if (p.endsWith(' while here')) {
      here = true;
      p = p.substring(0, p.length - 11);
    }
    if (p.endsWith(' while at a location')) {
      where = const Filter(atLocation: true);
      p = p.substring(0, p.length - 20);
    }
    final strong = RegExp(r'^(.+) while (?:he|she|they) (?:has|have) (\d+) strength or more$').firstMatch(p);
    if (strong != null) {
      where = Filter(strengthMin: int.parse(strong.group(2)!));
      p = strong.group(1)!;
    }
    final self = f == null;
    final happening = switch (p) {
      'leaves play' => Happening.leftPlay,
      'deals damage to another character in a challenge' => Happening.dealsChallengeDamage,
      'sings a song with sing together' => Happening.sungTogether,
      _ when RegExp(r'^is returned to (?:your|their) hand(?: from play)?$').hasMatch(p) => Happening.returnedToHand,
      _ => null,
    };
    if (happening != null) {
      if (here || where != null) return null;
      return On(happening, self: self, subject: f);
    }
    final event = switch (p) {
      'quests' => Event.quests,
      'is challenged' => Event.isChallenged,
      'is challenged and banished' || 'is banished in a challenge' => Event.banishedInChallenge,
      'is banished' => Event.banished,
      'banishes another character in a challenge' || 'banishes a character in a challenge' => Event.banishesInChallenge,
      'sings a song' => Event.sings,
      'moves to a location' => Event.movesToLocation,
      'is dealt damage' || 'is damaged' => Event.dealtDamage,
      'exerts' || 'is exerted' || 'becomes exerted' => Event.exerted,
      'challenges' || 'challenges another character' || 'challenges a character' => Event.challenges,
      _ => null,
    };
    if (event != null) return CardEvent(event, subject: f, where: where, here: here);
    // "challenges a damaged character", "challenges another character with 2 strength or less".
    final ch = RegExp(r'^challenges (?:a|an|another) (.+)$').firstMatch(p);
    if (ch != null) {
      final o = filter(ch.group(1)!, Owner.any);
      if (o == null) return null;
      return CardEvent(Event.challenges, subject: f, other: o, where: where, here: here);
    }
    return null;
  }

  /// "…, if it's the second card you've put into your inkwell this turn, …": a qualifier on
  /// when the trigger happens rather than a condition on resolving it.
  (_Head, String) _qualifyTrigger(_Head triggers, String rest) {
    final m = RegExp(r"^if it's the second card (you've put into your inkwell|they've drawn) this turn, (.+)$").firstMatch(rest);
    if (m == null || triggers.length != 1) return (triggers, rest);
    final (t, c, d) = triggers.single;
    final q = switch (t) {
      On(what: Happening.inked, :final by) when m.group(1)!.startsWith('you') => On(Happening.inked, by: by, nth: 2),
      Draws(:final by, :final theirTurn) when m.group(1)!.startsWith('they') => Draws(by, nth: 2, theirTurn: theirTurn),
      _ => null,
    };
    if (q == null) return (triggers, rest);
    return ([(q, c, d)], m.group(2)!);
  }

  /// Whether a trigger is about a card other than this one ("whenever one of your characters
  /// quests", "whenever you play a character"), which its pronouns then refer to.
  bool _aboutOtherCard(Trigger t) => switch (t) {
    CardEvent(:final subject) => subject != null,
    On(:final self, :final subject) => !self && subject != null,
    CardPlayed(:final filter) => !filter.types.contains(CardType.action),
    _ => false,
  };
}
