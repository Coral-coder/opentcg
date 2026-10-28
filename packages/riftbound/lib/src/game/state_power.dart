/// State for Empower (CR 442–443, 827–828), XP (CR 728–733), multiple buffs (CR 427.1.b.2) and
/// Flow (CR 829): kept apart from state.dart so that file only holds one field per class for it.
library;

/// Per object.
class ObjPower {
  /// Times Empowered (CR 442.1.a; more than 1 only with permission, CR 442.1.c.1). 0: not.
  int empowered = 0;

  /// Buffs beyond the first, for units allowed to have more than one (CR 427.1.b.2).
  int extraBuffs = 0;

  /// A spell played from the trash with Flow: banished instead of going to the trash (CR 829.1.b).
  bool flowed = false;

  /// Turn on which a spell in a trash was given [Flow] equal to its cost (Kennen), or 0.
  int flowGrantedTurn = 0;

  /// Where a unit was before its last move ("a battlefield I moved to or from").
  int movedFrom = -2;

  /// Turn on which it can't be chosen by enemy spells and abilities, or 0.
  int untargetableTurn = 0;

  /// Its Might is 10 or more (for "When my Might becomes 10 or more").
  bool mightTen = false;

  ObjPower clone() => ObjPower()
    ..empowered = empowered
    ..extraBuffs = extraBuffs
    ..flowed = flowed
    ..flowGrantedTurn = flowGrantedTurn
    ..movedFrom = movedFrom
    ..untargetableTurn = untargetableTurn
    ..mightTen = mightTen;

  String digest() => '$empowered,$extraBuffs,$flowed,$flowGrantedTurn,$movedFrom,$untargetableTurn,$mightTen';
}

/// Per player.
class PlayerPower {
  /// XP (CR 729): public, not a game object, no limit.
  int xp = 0;

  /// Turn on which this player last gained XP ("if you've gained XP this turn"), or 0.
  int xpGainedTurn = 0;

  PlayerPower clone() => PlayerPower()
    ..xp = xp
    ..xpGainedTurn = xpGainedTurn;

  String digest() => '$xp,$xpGainedTurn';
}

/// An effect lasting until the end of the turn that does something when an event happens
/// ("When a friendly unit is played this turn, buff it"; "When it wins a combat this turn, gain 2
/// XP"; "Disempower it at end of turn"): a delayed ability (CR 390).
class DelayedPower {
  DelayedPower(this.kind, {required this.controller, required this.source, this.unit = -1, this.n = 0, required this.turn});

  /// One of the kinds in power.dart's [DelayedKind] names.
  final String kind;
  final int controller;
  final int source;

  /// The unit it's about, or -1.
  final int unit;
  final int n;
  final int turn;

  String digest() => '${kind.length}:$kind,$controller,$source,$unit,$n,$turn';
}

/// Per game.
class GamePower {
  List<DelayedPower> delayed = [];

  GamePower clone() => GamePower()..delayed = List.of(delayed);

  String digest() => delayed.map((d) => d.digest()).join(';');
}
