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
      final c = db[s.obj(id).card]!;
      if (c.isSong) {
        for (final singer in pl.play) {
          add(PlayMove(p, id, mode: PlayMode.sing, singers: [singer]));
        }
      }
    }
    for (final id in pl.play) {
      add(QuestMove(p, id));
      for (final t in _challengeTargets(p, id)) {
        add(ChallengeMove(p, id, t));
      }
      final abs = parsed(id).abilities;
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
