part of 'game.dart';

/// Setting up positions directly, for tests. Not used by normal play.
extension GameTesting on Game {
  /// Starts an empty game at [active]'s main phase (no decks dealt, no mulligans).
  void startEmpty({int active = 0, int turn = 2}) {
    state.phase = Phase.main;
    state.turn = turn;
    state.active = active;
    state.firstPlayer = 0;
  }

  /// Puts a card into a zone. In play it's dry (played on an earlier turn) unless [drying].
  CardId addCard(String name, int owner, Place zone, {bool drying = false, bool exerted = false, int damage = 0}) {
    final c = db[name];
    if (c == null) throw ArgumentError('Unknown card $name');
    final o = Obj(id: state.nextId++, card: c.fullName, owner: owner, zone: Place.hand);
    state.objects[o.id] = o;
    state.player(owner).hand.add(o.id);
    _moveTo(o.id, zone);
    if (zone == Place.play) {
      o.dry = !drying && c.type == CardType.character || c.type != CardType.character;
      o.exerted = exerted;
      o.damage = damage;
      o.enteredTurn = drying ? state.turn : 0;
    }
    if (zone == Place.inkwell) o.exerted = exerted;
    return o.id;
  }

  /// Adds [n] ready ink cards for [owner].
  void addInk(int owner, int n, {String card = ''}) {
    final name = card.isNotEmpty ? card : db.cards.firstWhere((c) => c.inkable).fullName;
    for (var i = 0; i < n; i++) {
      addCard(name, owner, Place.inkwell);
    }
  }

  void moveToForTest(CardId id, Place to) => _moveTo(id, to);

  /// Settles after manual setup: game state check and the bag.
  void settle() {
    _check();
    _resolveBag();
  }
}
