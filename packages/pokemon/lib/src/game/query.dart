part of 'game.dart';

extension GameQuery on Game {
  /// Every move the player to act can make now (answers excluded), for the computer player and
  /// the table. Each is checked by trying it on a copy of the state.
  List<PMove> legalMoves() {
    final s = state;
    if (s.over || pending != null || s.phase != Phase.main) return const [];
    final p = s.active;
    final pl = s.player(p);
    final out = <PMove>[];
    void add(PMove m) {
      if (whyNot(m) == null) out.add(m);
    }

    final inPlay = pl.inPlay;
    for (final id in pl.hand) {
      final c = card(id);
      if (c.isBasicPokemon) {
        add(PlayBasicMove(p, id));
      } else if (c.isPokemon) {
        for (final t in inPlay) {
          if (card(t).name == c.evolvesFrom) add(EvolveMove(p, id, t));
        }
      } else if (c.isEnergy) {
        if (!pl.energyAttached) {
          for (final t in inPlay) {
            add(AttachEnergyMove(p, id, t));
          }
        }
      } else if (c.trainer == TrainerKind.tool) {
        for (final t in inPlay) {
          if (s.obj(t).tool == null) add(TrainerMove(p, id, target: t));
        }
      } else {
        add(TrainerMove(p, id));
      }
    }
    if (!pl.retreated) {
      for (final b in pl.bench) {
        add(RetreatMove(p, b));
      }
    }
    for (final id in inPlay) {
      final abs = parsed(id).abilities;
      for (var i = 0; i < abs.length; i++) {
        if (abs[i] is OncePerTurn) add(AbilityMove(p, id, i));
      }
    }
    final a = pl.active;
    if (a != null) {
      for (var i = 0; i < card(a).attacks.length; i++) {
        add(AttackMove(p, i));
      }
    }
    add(EndTurnMove(p));
    return out;
  }

  /// Why [move] can't be made now, or null if it can (tried on a copy, answering every
  /// question with [defaultAnswer]).
  String? whyNot(PMove move) {
    final s = state;
    if (s.over) return 'The game is over';
    if (pending != null) return 'Waiting for a decision';
    if (move is StartMove || move is AnswerMove) return 'Not a turn action';
    if (move is ConcedeMove) return null;
    if (s.phase != Phase.main) return 'The game hasn’t started';
    if (move.seat != s.active) return 'It’s not your turn';
    final probe = Game._probe(this);
    try {
      probe._exec(move);
    } on TcgError catch (e) {
      return e.message;
    }
    return null;
  }

  /// A default answer to [d] (used by legality probes, the computer as a fallback, and tests).
  List<int> defaultAnswer(Decision d) => switch (d.kind) {
        DecisionKind.cards => d.options.take(d.min).toList(),
        DecisionKind.yesNo => const [1],
        DecisionKind.option => const [0],
      };

  /// The types the Energy attached to [id] provides (for the table).
  List<PType> energyOf(CardId id) => [for (final e in state.obj(id).energy) energyProvided(e)];

  /// Whether [id]'s attack [index] has the Energy it needs.
  bool hasEnergyFor(CardId id, int index) => canPay(id, card(id).attacks[index].cost);
}
