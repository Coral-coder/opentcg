part of 'game.dart';

/// Setting up positions directly, for tests. Not used by normal play.
extension GameTesting on Game {
  /// Starts an empty game in [active]'s turn (no decks dealt, no prizes).
  void startEmpty({int active = 0, int turn = 3, int firstPlayer = 0}) {
    state.phase = Phase.main;
    state.turn = turn;
    state.active = active;
    state.firstPlayer = firstPlayer;
  }

  /// Puts a card into a zone. A Pokémon put into play counts as there since an earlier turn
  /// unless [fresh].
  CardId addCard(String key, int owner, Place zone, {int damage = 0, bool fresh = false}) {
    final c = db[key];
    if (c == null) throw ArgumentError('Unknown card $key');
    final o = Obj(id: state.nextId++, card: c.key, owner: owner, zone: Place.hand);
    state.objects[o.id] = o;
    state.player(owner).hand.add(o.id);
    if (zone == Place.active || zone == Place.bench) {
      _putIntoPlay(o.id, owner, zone);
      o.damage = damage;
      if (!fresh) o.playedTurn = 0;
    } else if (zone != Place.hand) {
      _moveTo(o.id, zone, bottom: true);
    }
    return o.id;
  }

  /// Attaches a new card (Energy or Tool) to [target].
  CardId attachNew(String key, CardId target) {
    final id = addCard(key, state.obj(target).owner, Place.hand);
    _attach(id, target);
    return id;
  }

  /// Adds [n] copies of [key] to [owner]'s deck (at the bottom).
  void fillDeck(int owner, String key, int n) {
    for (var i = 0; i < n; i++) {
      addCard(key, owner, Place.deck);
    }
  }

  void addPrizes(int owner, String key, int n) {
    for (var i = 0; i < n; i++) {
      addCard(key, owner, Place.prize);
    }
  }

  void afflictForTest(CardId id, Cond k) => _afflict(id, k);
  void checkupForTest() => _checkup();
  void knockOutsForTest() => _knockOuts();
}
