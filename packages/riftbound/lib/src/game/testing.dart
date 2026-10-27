part of 'game.dart';

/// Building positions directly, for tests and tools (never used by a real match).
extension GameTesting on Game {
  /// An empty main-phase position: two players, [battlefields] battlefields (by name), no cards,
  /// [active]'s turn 1.
  void setUpEmpty({List<String> battlefields = const [], int active = 0}) {
    for (final name in battlefields) {
      final id = _newObj(name, state.bfs.length % 2, Zone.battlefield);
      state.obj(id).loc = state.bfs.length;
      state.bfs.add(Bf(id));
    }
    state
      ..phase = Phase.main
      ..step = Step.main
      ..turn = 1
      ..active = active
      ..firstPlayer = active;
  }

  /// Puts a card somewhere: a hand card, a unit or gear on the board ([loc]), a legend.
  ObjId addCard(String key, int player, {Zone zone = Zone.hand, int loc = base, bool exhausted = false}) {
    final id = _newObj(key, player, zone);
    final pl = state.player(player);
    switch (zone) {
      case Zone.hand:
        pl.hand.add(id);
      case Zone.mainDeck:
        pl.deck.add(id);
      case Zone.trash:
        pl.trash.add(id);
      case Zone.board:
        state.obj(id)
          ..loc = loc
          ..exhausted = exhausted;
      case Zone.legend:
        pl.legend = id;
      case Zone.champion:
        pl.champion = id;
      default:
        break;
    }
    return id;
  }

  /// Gives [player] [n] ready runes of [d] on the board.
  void addRunes(int player, Domain d, int n) {
    for (var i = 0; i < n; i++) {
      final id = _newObj('${d.label} Rune', player, Zone.runes);
      state.player(player).runes.add(id);
    }
  }

  /// Puts [n] cards named [key] on top of [player]'s deck.
  void stackDeck(int player, String key, int n) {
    for (var i = 0; i < n; i++) {
      final id = _newObj(key, player, Zone.mainDeck);
      state.player(player).deck.insert(0, id);
    }
  }

  void setControl(int bf, int? player) => state.bfs[bf].controller = player;

  /// Runs the engine's settling (after building a position by hand).
  void settleForTest() => _settle();
}
