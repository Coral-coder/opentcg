part of 'game.dart';

extension GameQuery on Game {
  /// Every move the player to act can make now (answers excluded), for the computer player and
  /// the table.
  List<LMove> legalMoves() {
    final s = state;
    if (s.over || pending != null || s.phase != Phase.main) return const [];
    final p = s.active;
    final pl = s.player(p);
    final out = <LMove>[];
    void add(LMove m) {
      if (whyNot(m) == null) out.add(m);
    }

    for (final id in pl.hand) {
      add(InkMove(p, id));
      add(PlayMove(p, id));
      for (final onto in shiftTargets(p, id)) {
        add(PlayMove(p, id, mode: PlayMode.shift, onto: onto));
      }
      for (final (a, b) in duoShiftTargets(p, id)) {
        add(PlayMove(p, id, mode: PlayMode.shift, onto: a, onto2: b));
      }
      final c = db[s.obj(id).card]!;
      if (c.isSong) {
        for (final singer in pl.play) {
          add(PlayMove(p, id, mode: PlayMode.sing, singers: [singer]));
        }
        for (final group in _singTogetherGroups(p, id)) {
          add(PlayMove(p, id, mode: PlayMode.sing, singers: group));
        }
      }
    }
    for (final id in _s3InkableFromDiscard(p)) {
      add(InkMove(p, id));
    }
    _s4ExtraPlays(p, add);
    for (final id in pl.play) {
      add(QuestMove(p, id));
      for (final t in _challengeTargets(p, id)) {
        add(ChallengeMove(p, id, t));
      }
      final abs = abilitiesOf(id);
      for (var i = 0; i < abs.length; i++) {
        if (abs[i] is Activated || (abs[i] is KeywordAbility && (abs[i] as KeywordAbility).keyword.kw == Kw.boost)) add(ActivateMove(p, id, i));
      }
      if (chars(id).type == CardType.character) {
        for (final loc in pl.play) {
          if (chars(loc).type == CardType.location) add(MoveMove(p, id, loc));
        }
      }
    }
    add(EndTurnMove(p));
    return out;
  }

  /// Groups of two or more singers for a Sing Together song (CR 8.12): the fewest singers (the
  /// costliest first) and the cheapest ones (the cheapest first) whose total cost reaches N.
  List<List<CardId>> _singTogetherGroups(int p, CardId song) {
    final k = LorcanaParser.parse(db[state.obj(song).card]!).abilities.whereType<KeywordAbility>().where((a) => a.keyword.kw == Kw.singTogether).firstOrNull;
    if (k == null) return const [];
    final able = [
      for (final id in state.player(p).play)
        if (chars(id).type == CardType.character && _canExertToPay(p, id) && !chars(id).rules.contains(Rule.cantSing)) id,
    ];
    final out = <List<CardId>>[];
    for (final desc in [true, false]) {
      final order = List.of(able)..sortStable((a, b) => desc ? _singCost(b) - _singCost(a) : _singCost(a) - _singCost(b));
      final group = <CardId>[];
      var total = 0;
      for (final id in order) {
        if (total >= k.keyword.n) break;
        group.add(id);
        total += _singCost(id);
      }
      if (group.length > 1 && total >= k.keyword.n && !out.any((g) => g.length == group.length && g.every(group.contains))) out.add(group);
    }
    return out;
  }

  /// A default answer to [d] (used by the computer as a fallback and by tests).
  List<int> defaultAnswer(Decision d) => switch (d.kind) {
    DecisionKind.cards => d.options.take(d.min).toList(),
    DecisionKind.yesNo => const [1],
    DecisionKind.option => const [0],
    DecisionKind.order => List.of(d.options),
  };

  /// Ink available now.
  int inkReady(int p) => _inkReady(p);
}
