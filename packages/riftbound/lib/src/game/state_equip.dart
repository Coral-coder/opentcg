part of 'state.dart';

/// What an object remembers about Equipment and the cards around them (game/equip.dart).
class EqObj {
  /// The unit this card is Attached to (CR 718), or -1.
  int attachedTo = -1;

  /// The turn it was last attached ("if this was attached to me this turn").
  int attachedTurn = 0;

  /// Control taken "until I leave the board": control returns to the owner when this object
  /// leaves the board (Akshan, Mischievous), or -1.
  int controlUntil = -1;

  /// Units "banished with this" (The Zero Drive).
  List<int> banishedWith = [];

  /// A unit's conquests: the last turn it conquered and how many times that turn.
  int conquerTurn = 0;
  int conquests = 0;

  /// A unit that's a copy of another (Shady Spectacles, CR 446): the copied card, and the
  /// Equipment whose attachment makes it one.
  String copyOf = '';
  int copyVia = -1;

  /// Svellsongur: the card whose text it copied as it attached.
  String textOf = '';

  /// Triggered abilities given "this turn" (Relentless Pursuit): "turn|card|index" (an index into
  /// that card's ParsedCard.extra).
  List<String> grants = [];

  /// The optional additional cost was paid as it was played (Akshan, Mischievous).
  bool paidExtra = false;

  EqObj clone() => EqObj()
    ..attachedTo = attachedTo
    ..attachedTurn = attachedTurn
    ..controlUntil = controlUntil
    ..banishedWith = List.of(banishedWith)
    ..conquerTurn = conquerTurn
    ..conquests = conquests
    ..copyOf = copyOf
    ..copyVia = copyVia
    ..textOf = textOf
    ..grants = List.of(grants)
    ..paidExtra = paidExtra;

  String digest() => '$attachedTo/$attachedTurn/$controlUntil/${banishedWith.join(',')}/$conquerTurn/$conquests/${copyOf.length}:$copyOf/$copyVia/${textOf.length}:$textOf/${grants.join(';')}/$paidExtra';
}

/// Game-wide Equipment bookkeeping.
class EqState {
  /// The turn each player last played an Equipment ("if you've played an Equipment this turn").
  List<int> equipmentPlayed = [0, 0];

  /// The battlefield being conquered from an open state (CR 170.11.c), while it's scored; -1.
  int openConquest = -1;

  /// Excess combat damage each player assigned in the last combat (CR 467.2.c.4), and where/when.
  List<int> excess = [0, 0];
  int excessBf = -1;
  int excessTurn = 0;

  /// Modes chosen this turn by "choose one that hasn't been chosen this turn": "turn:source:mode".
  List<String> modesChosen = [];

  EqState clone() => EqState()
    ..equipmentPlayed = List.of(equipmentPlayed)
    ..openConquest = openConquest
    ..excess = List.of(excess)
    ..excessBf = excessBf
    ..excessTurn = excessTurn
    ..modesChosen = List.of(modesChosen);

  String digest() => '${equipmentPlayed.join(',')}/$openConquest/${excess.join(',')}/$excessBf/$excessTurn/${modesChosen.join(';')}';
}
