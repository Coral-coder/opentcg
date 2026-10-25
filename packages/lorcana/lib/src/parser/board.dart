part of 'parser.dart';

/// Board sentences: damage and banishing by players' own choice, timed grants with several
/// parts, "X or Y" choices, lore races, moving to locations, and conditions about this turn.
extension _Board on _CardParser {
  static const _verbs = r'(?:banish|return|deal|exert|ready|draw|gain|remove|put|move|give)';

  Lasting? _lasting(String s) => switch (s) {
    'this turn' || 'for the rest of this turn' => Lasting.thisTurn,
    'until the start of your next turn' => Lasting.untilYourNextTurn,
    'during their next turn' || 'during its next turn' => Lasting.theirNextTurn,
    _ => null,
  };

  /// One board action, or null to let the general clause grammar try.
  Effect? _boardClause(String c, _Ctx ctx) {
    List<String>? m;

    // "Give chosen character +2 strength this turn": the same as "chosen character gets ..." (CR 6.6).
    m = rx(c, r'give (.+)');
    if (m != null) {
      final words = m[1].split(' ');
      for (var i = 1; i < words.length; i++) {
        final who = words.take(i).join(' '), rest = words.skip(i).join(' ');
        final save = ctx.save();
        final e = RegExp(r'^[+-]\d+ ').hasMatch(rest) ? sentence('$who gets $rest', ctx) : sentence('$who gains $rest', ctx);
        if (e != null) return e;
        ctx.restore(save);
      }
      return null;
    }

    // "At the end of your turn, banish them": a delayed trigger about the chosen card (CR 6.2.7.2).
    m = rx(c, r'at the end of (?:your|the) turn, (banish|exert|return) (?:them|him|her|it|that character)(?: to their players?.? hands?)?');
    if (m != null && ctx.nextSlot > 0) {
      return Delayed(true, switch (m[1]) {
        'banish' => const Banish(EventCard()),
        'exert' => const Exert(EventCard()),
        _ => const ReturnToHand(EventCard()),
      });
    }

    // "{e} one of your characters" as the first half of "X to Y" (CR 6.1.5.1).
    m = rx(c, r'\{e\} (.+)');
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return Exert(t);
    }

    // "Each opponent chooses and banishes one of their characters" (CR 6.1.3: their own pick).
    m = rx(c, r'(each opponent|each player|chosen opponent) chooses and (banish|exert|ready|return)(?:e?s)? one of their (.+?)(?: to their hand)?');
    if (m != null) {
      final f = _ownFilter(m[3]);
      if (f == null) return null;
      final slot = ctx.nextSlot++;
      final r = Remembered(slot);
      final Effect then = switch (m[2]) {
        'banish' => Banish(r),
        'exert' => Exert(r),
        'ready' => Ready(r),
        _ => ReturnToHand(r),
      };
      return PlayerChooses(_who(m[1]), f, slot, then);
    }
    // "Each opponent chooses one of their characters and deals 2 damage to them".
    m = rx(c, r'(each opponent|each player|chosen opponent) chooses one of their (.+?) and (deals? (\d+) damage to (?:them|it)|banish(?:es)? (?:them|it)|exerts? (?:them|it)|returns? (?:them|it) to their hand)');
    if (m != null) {
      final f = _ownFilter(m[2]);
      if (f == null) return null;
      final slot = ctx.nextSlot++;
      final r = Remembered(slot);
      final act = m[3];
      final Effect then = act.startsWith('deal')
          ? DealDamage(r, Fixed(int.parse(m[4])))
          : act.startsWith('banish')
          ? Banish(r)
          : act.startsWith('exert')
          ? Exert(r)
          : ReturnToHand(r);
      return PlayerChooses(_who(m[1]), f, slot, then);
    }

    // Damage amounts.
    m = rx(c, r'deal damage to (.+?) equal to the number of (.+)');
    if (m != null) {
      final t = target(m[1], ctx);
      final a = countOf(m[2].replaceFirstMapped(RegExp(r'^your (.+?)(?: you have)? in play$'), (x) => '${x[1]} you have in play'));
      if (t == null || a == null) return null;
      return DealDamage(t, a);
    }
    m = rx(c, r'deal damage equal to (.+?) (strength|willpower|lore) to (.+)');
    if (m != null) {
      final src = ref(m[1].replaceAll(RegExp(r"'s?$"), ''), ctx);
      final t = target(m[3], ctx);
      if (src == null || t == null) return null;
      return DealDamage(t, StatOf(src, _stat(m[2])));
    }
    m = rx(c, r'deal (\d+) damage each to up to (\w+) chosen (.+)');
    if (m != null) {
      final f = filter(_plural(m[3]), Owner.any, cardTypes: true, chosenPhrase: true);
      final n = numWord(m[2]);
      if (f == null || n == null) return null;
      return DealDamage(Chosen(f, count: n, upTo: true, slot: ctx.nextSlot++), Fixed(int.parse(m[1])));
    }
    m = rx(c, r'remove (\d+) damage each from up to (\w+) chosen (.+)');
    if (m != null) {
      final f = filter(_plural(m[3]), Owner.any, cardTypes: true, chosenPhrase: true);
      final n = numWord(m[2]);
      if (f == null || n == null) return null;
      return RemoveDamage(Chosen(f, count: n, upTo: true, slot: ctx.nextSlot++), Fixed(int.parse(m[1])));
    }
    // "Remove up to 2 damage from any number of chosen characters": from each of them.
    m = rx(c, r'remove up to (\d+) damage from any number of chosen (.+)');
    if (m != null) {
      final f = filter(_plural(m[2]), Owner.any, cardTypes: true, chosenPhrase: true);
      if (f == null) return null;
      return RemoveDamage(Chosen(f, count: 99, upTo: true, slot: ctx.nextSlot++), Fixed(int.parse(m[1])));
    }
    m = rx(c, r'move all damage from (.+?) to (.+)');
    if (m != null) {
      final a = target(m[1], ctx);
      final b = target(m[2], ctx);
      if (a == null || b == null) return null;
      return MoveDamage(a, b, const Fixed(99));
    }

    // Lore (CR 1.11).
    m = rx(c, r'(?:you )?gain lore equal to the (lore|strength|willpower) of (.+)');
    if (m != null) {
      final t = target(m[2], ctx);
      if (t == null) return null;
      return GainLore(Who.you, StatOf(t, _stat(m[1])));
    }
    m = rx(c, r"(?:you )?gain lore equal to (.+?)'s? (lore|strength|willpower)");
    if (m != null) {
      final t = ref(m[1], ctx) ?? target(m[1], ctx);
      if (t == null) return null;
      return GainLore(Who.you, StatOf(t, _stat(m[2])));
    }
    m = rx(c, r'(?:you )?gain lore equal to the damage on (.+)');
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return GainLore(Who.you, DamageOn(t));
    }
    m = rx(c, r'draw cards equal to the damage on (.+)');
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return Draw(Who.you, DamageOn(t));
    }
    m = rx(c, r"(?:its|their|that) player gains (\d+) lore");
    if (m != null) return GainLore(Who.thatPlayer, Fixed(int.parse(m[1])));
    m = rx(c, r'each opponent with more lore than you loses (\d+) lore');
    if (m != null) return LoseLoreRicher(Fixed(int.parse(m[1])));
    m = rx(c, r'each player draws (\w+) cards? and gains (\d+) lore');
    if (m != null) {
      final n = numWord(m[1]);
      if (n == null) return null;
      return Seq([Draw(Who.each, Fixed(n)), GainLore(Who.each, Fixed(int.parse(m[2])))]);
    }

    // Returning everything ("return all opposing characters to their player's hands").
    m = rx(c, r"return (all .+?) to their players?'? hands");
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return ReturnToHand(t);
    }

    // "Exert chosen opposing character and all other opposing characters with the same name".
    m = rx(c, r'(banish|exert|ready|return) (chosen .+?) and all other (.+?) with the same name(?: to their players?.? hands?)?');
    if (m != null) {
      final t = target(m[2], ctx);
      final f = filter(m[3], m[3].startsWith('opposing') ? Owner.opposing : Owner.any);
      if (t is! Chosen || f == null) return null;
      final into = ctx.nextSlot++;
      final verb = m[1];
      Effect act(Target x) => switch (verb) {
        'banish' => Banish(x),
        'exert' => Exert(x),
        'ready' => Ready(x),
        _ => ReturnToHand(x),
      };
      return Seq([SameNameAs(t, f, into), act(Remembered(t.slot)), act(Remembered(into))]);
    }

    // Moving to locations for free (CR 4.7).
    m = rx(c, r'move up to (\w+) (?:of your characters|characters of yours) to the same location for free');
    if (m != null) {
      final n = numWord(m[1]);
      if (n == null) return null;
      return MoveToLocation([Chosen(const Filter(owner: Owner.yours), count: n, upTo: true, slot: ctx.nextSlot++, word: false)]);
    }
    m = rx(c, r'move any number of (your characters|your other characters) to the same location for free');
    if (m != null) {
      final f = filter(m[1].substring(5), Owner.yours);
      if (f == null) return null;
      return MoveToLocation([Chosen(f, count: 99, upTo: true, slot: ctx.nextSlot++, word: false)]);
    }
    m = rx(c, r'move (.+?) and (.+?) to the same location for free');
    if (m != null) {
      final a = target(m[1], ctx);
      final b = target(m[2], ctx);
      if (a == null || b == null) return null;
      return MoveToLocation([a, b]);
    }
    m = rx(c, r'move (.+?) to (one of your locations|a location|that location|this location) for free');
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return MoveToLocation([t], toEventLocation: m[2] == 'that location' || m[2] == 'this location');
    }
    m = rx(c, r'(they|he|she|this character) may move (?:to a location|there) for free');
    if (m != null) {
      final t = ref(m[1], ctx) ?? (m[1] == 'this character' ? const This() : null);
      if (t == null) return null;
      return May(MoveToLocation([t], toEventLocation: c.contains('there')));
    }

    // Restrictions and permissions for a while (CR 6.6).
    m = rx(c, r"(.+?) can't quest or challenge (for the rest of this turn|this turn|during their next turn)");
    if (m != null) {
      final t = target(m[1], ctx);
      final d = _lasting(m[2]);
      if (t == null || d == null) return null;
      return Seq([GrantRule(t, Rule.cantQuest, d), GrantRule(t, Rule.cantChallenge, d)]);
    }
    m = rx(c, r"(.+?) can't challenge and must quest (?:during their next turn if able|if able during their next turn)");
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return Seq([GrantRule(t, Rule.cantChallenge, Lasting.theirNextTurn), GrantRule(t, Rule.mustQuest, Lasting.theirNextTurn)]);
    }
    m = rx(c, r"(.+?) can't ready at the start of (?:its|their|his|her) next turn");
    if (m != null) {
      final t = target(m[1], ctx);
      if (t == null) return null;
      return GrantRule(t, Rule.cantReady, Lasting.theirNextTurn);
    }
    m = rx(c, r'(.+?) (?:may|can) challenge ready characters (this turn)');
    if (m != null) {
      final t = target(m[1], ctx);
      if (t != null) return GrantRule(t, Rule.canChallengeReady, Lasting.thisTurn);
    }

    // Several timed changes sharing one duration: "chosen character gets +2 lore and gains
    // Support this turn", "gains Challenger +2 and Resist +2 and can challenge ready characters".
    m = RegExp(r'^(.+?) ((?:gets?|gains?) .+?) (this turn|for the rest of this turn|until the start of your next turn)$').firstMatch(c)?.let((x) => [x.group(0)!, x.group(1)!, x.group(2)!, x.group(3)!]);
    if (m != null && RegExp(r' and (?:gets?|gains?|can) ').hasMatch(m[2])) {
      final d = _lasting(m[3])!;
      final save = ctx.save();
      final t = target(m[1], ctx);
      if (t != null) {
        final steps = <Effect>[];
        var ok = true;
        for (final part in m[2].split(RegExp(r' and (?=(?:gets?|gains?|can) )'))) {
          final p = part.trim();
          Effect? e;
          if (p == 'can challenge ready characters') {
            e = GrantRule(t, Rule.canChallengeReady, d);
          } else {
            e = _timedPredicate(p, t, d);
          }
          if (e == null) {
            ok = false;
            break;
          }
          steps.add(e);
        }
        if (ok) return Seq(steps);
      }
      ctx.restore(save);
    }
    // "Chosen character gets +1 strength this turn for each character you have in play".
    m = rx(c, r'(.+?) gets? \+(\d+) (strength|willpower|lore) (this turn|until the start of your next turn) for each (.+)');
    if (m != null) {
      final t = target(m[1], ctx);
      final a = countOf(m[5], per: int.parse(m[2]));
      if (t == null || a == null) return null;
      return Modify(t, _stat(m[3]), a, _lasting(m[4])!);
    }
    // "They gain Rush" with no duration: for as long as the card stays in play.
    m = rx(c, r'(they|he|she|it) gains? (.+?)(?: and gets? \+(\d+) (strength|willpower|lore) this turn)?');
    if (m != null) {
      final t = ref(m[1], ctx);
      final kws = _keywordList(m[2]);
      // On an action "they" must be a card chosen earlier, never the action itself.
      if (t == null || kws == null || (t is This && card.type == CardType.action)) return null;
      final steps = <Effect>[for (final k in kws) GrantKeyword(t, k, m[3].isEmpty ? Lasting.permanent : Lasting.thisTurn)];
      if (m[3].isNotEmpty) steps.add(Modify(t, _stat(m[4]), Fixed(int.parse(m[3])), Lasting.thisTurn));
      return steps.length == 1 ? steps.first : Seq(steps);
    }

    // "Banish her or return another chosen character of yours to your hand" (CR 6.1.5.2).
    final or = RegExp(' or (?=$_verbs )').allMatches(c).toList();
    for (final o in or) {
      final left = c.substring(0, o.start), right = c.substring(o.end);
      final save = ctx.save();
      final a = clause(left, ctx);
      if (a != null) {
        final b = clause(right, ctx);
        if (b != null) return ChooseOne([a, b], [left, right]);
      }
      ctx.restore(save);
    }
    return null;
  }

  /// "Characters", "ready characters", "items": a filter for a player's own cards.
  Filter? _ownFilter(String s) => filter(_plural(s), Owner.any, cardTypes: true);

  /// Conditions about the board and this turn.
  Cond? _boardCondition(String s) {
    List<String>? m;
    if (rx(s, r'you played another character this turn') != null) return const TurnStatCond(TurnStat.charactersPlayed, Who.you, Cmp.ge, 1, excludeSource: true);
    if (rx(s, r'you played a character this turn') != null) return const TurnStatCond(TurnStat.charactersPlayed, Who.you, Cmp.ge, 1);
    m = rx(s, r"you've played (\d+) or more cards this turn");
    if (m != null) return TurnStatCond(TurnStat.cardsPlayed, Who.you, Cmp.ge, int.parse(m[1]));
    if (rx(s, r"you didn't play a song this turn") != null) return const TurnStatCond(TurnStat.songsPlayed, Who.you, Cmp.eq, 0);
    if (rx(s, r'you used shift to play (?:him|her|them|it)') != null) return const ShiftedCond();
    if (rx(s, r'one of your characters was damaged this turn') != null) return const TurnStatCond(TurnStat.damaged, Who.you, Cmp.ge, 1);
    if (rx(s, r'a character was banished in a challenge this turn') != null) return const TurnStatCond(TurnStat.banishedInChallenge, Who.each, Cmp.ge, 1);
    if (rx(s, r'an opposing character was banished in a challenge this turn') != null) return const TurnStatCond(TurnStat.banishedInChallenge, Who.opponents, Cmp.ge, 1);
    if (rx(s, r'a character was banished this turn') != null) return const TurnStatCond(TurnStat.banished, Who.each, Cmp.ge, 1);
    if (rx(s, r'a character of yours quested this turn') != null) return const TurnStatCond(TurnStat.quested, Who.you, Cmp.ge, 1);
    if (rx(s, r'none of your characters challenged this turn') != null) return const TurnStatCond(TurnStat.challenged, Who.you, Cmp.eq, 0);
    if (rx(s, r"it's the second challenge this turn") != null) return const TurnStatCond(TurnStat.challenged, Who.you, Cmp.eq, 2);
    if (rx(s, r'you removed damage from a character this turn') != null) return const TurnStatCond(TurnStat.removedDamage, Who.you, Cmp.ge, 1);
    m = rx(s, r'you removed (\d+) or more damage from one of your characters this turn');
    if (m != null) return TurnStatCond(TurnStat.removedDamage, Who.you, Cmp.ge, int.parse(m[1]));
    if (rx(s, r'(?:an|chosen) opponent has more cards in their hand than you') != null) return HandCompare(chosen: s.startsWith('chosen'));
    if (rx(s, r'(?:this character|he|she) has no damage') != null) return const SelfState(damaged: false);
    m = rx(s, r'this character has (\d+) or more damage');
    if (m != null) return SelfDamage(int.parse(m[1]));
    if (rx(s, r'you have a character in play with more strength than each opposing character') != null) return const StrongestCond();
    // "An opponent has an item in play", "an opponent has an exerted character in play".
    m = rx(s, r'an opponent has (?:a|an) (.+?) in play');
    if (m != null) {
      final f = filter(m[1], Owner.opposing, cardTypes: true);
      if (f == null) return null;
      return CountCond(f.copyWith(owner: Owner.opposing), Cmp.ge, 1, whose: Owner.opposing);
    }
    // "A princess or queen character is in play".
    m = rx(s, r'(?:a|an) (.+?) is in play');
    if (m != null) {
      final f = filter(m[1], Owner.any, cardTypes: true);
      if (f == null) return null;
      return CountCond(f, Cmp.ge, 1, whose: Owner.any);
    }
    // "You have any characters in play with 3 strength or more".
    m = rx(s, r'you have any (.+?) in play with (\d+) strength or more');
    if (m != null) {
      final f = filter(_plural(m[1]), Owner.yours, cardTypes: true);
      if (f == null) return null;
      return CountCond(f.copyWith(strengthMin: int.parse(m[2])), Cmp.ge, 1);
    }
    // "You have characters named Dewey and Louie in play".
    m = rx(s, r'you have characters named (.+?) and (.+?) in play');
    if (m != null) return AllConds([CountCond(Filter(named: m[1]), Cmp.ge, 1), CountCond(Filter(named: m[2]), Cmp.ge, 1)]);
    // "The chosen character is named Pain", "a character named Darkwing Duck is chosen".
    m = rx(s, r'the chosen character is named (.+)');
    if (m != null) return TargetIs(const Remembered(), Filter(named: m[1]));
    m = rx(s, r'a character named (.+?) is chosen');
    if (m != null) return TargetIs(const Remembered(), Filter(named: m[1]));
    return null;
  }

  /// "If X, Y instead" (CR 6.5.7): replaces the effect of the sentence before when X holds.
  bool _boardInstead(String s, List<Effect> steps, _Ctx ctx) {
    // "If a Hero character is chosen, they can also challenge ready characters this turn".
    final also = RegExp(r'^if (?:a|an) (.+?) is chosen, (?:they|he|she|it) (?:can also|also|can) (.+)$').firstMatch(s);
    final chosenBefore = steps.isEmpty ? null : _chosenTarget(steps.last);
    if (also != null && chosenBefore != null && ctx.nextSlot > 0) {
      final f = filter(also.group(1)!, Owner.any);
      final e = sentence('they can ${also.group(2)!}', ctx) ?? sentence('they ${also.group(2)!}', ctx);
      if (f != null && e != null) {
        steps.add(If(TargetIs(chosenBefore, f), e));
        return true;
      }
    }
    final m = RegExp(r'^if (.+?), (.+) instead$').firstMatch(s);
    if (m == null || steps.isEmpty) return false;
    final c = condition(m.group(1)!) ?? _ifTarget(m.group(1)!, ctx);
    if (c == null) return false;
    final prev = steps.last;
    var e = sentence(m.group(2)!, ctx);
    // "They get +4 strength instead": the duration is the replaced effect's.
    if (e == null && prev is Modify) {
      final d = switch (prev.duration) {
        Lasting.thisTurn => ' this turn',
        Lasting.untilYourNextTurn => ' until the start of your next turn',
        _ => '',
      };
      if (d.isNotEmpty) e = sentence('${m.group(2)!}$d', ctx);
    }
    // "Remove up to 3 damage instead", "deal 3 damage instead": to the same chosen card.
    if (e == null && _chosenTarget(prev) != null) {
      final save = ctx.save();
      e = sentence('${m.group(2)!} ${prev is RemoveDamage ? 'from' : 'to'} chosen character', ctx);
      if (e == null) ctx.restore(save);
    }
    if (e == null) return false;
    steps.removeLast();
    // "If a Villain character is chosen": the choice is made first, then checked (CR 6.1.3).
    final chosen = _chosenTarget(prev);
    final cond = c is TargetIs && chosen != null ? TargetIs(chosen, c.filter) : c;
    steps.add(If(cond, _reuseChosen(e, prev), prev));
    return true;
  }

  /// "Remove up to 3 damage instead": the replacement acts on the card the first effect chose.
  Effect _reuseChosen(Effect e, Effect prev) {
    final slot = _chosenSlot(prev);
    if (slot == null) return e;
    return switch (e) {
      Modify(:final target, :final stat, :final amount, :final duration, :final negative) when target is Chosen => Modify(Remembered(slot), stat, amount, duration, negative: negative),
      RemoveDamage(:final target, :final amount, :final all) when target is Chosen => RemoveDamage(Remembered(slot), amount, all: all),
      DealDamage(:final target, :final amount, :final put) when target is Chosen => DealDamage(Remembered(slot), amount, put: put),
      _ => e,
    };
  }

  int? _chosenSlot(Effect e) => _chosenTarget(e)?.slot;

  Chosen? _chosenTarget(Effect e) => switch (e) {
    Modify(:final target) when target is Chosen => target,
    RemoveDamage(:final target) when target is Chosen => target,
    DealDamage(:final target) when target is Chosen => target,
    GrantKeyword(:final target) when target is Chosen => target,
    GrantRule(:final target) when target is Chosen => target,
    Seq(:final steps) when steps.isNotEmpty => _chosenTarget(steps.first),
    _ => null,
  };
}
