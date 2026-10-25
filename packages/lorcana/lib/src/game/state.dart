/// Game state: players, cards and their states (CR 5.1), zones (CR 7), the bag (CR 7.7), and
/// the effects that last for a while. Everything here is part of the digest.
library;

import 'package:tcg_core/tcg_core.dart';

import '../ir.dart';

typedef CardId = int;

/// A card in the game (in any zone).
class Obj {
  Obj({required this.id, required this.card, required this.owner, required this.zone});
  final CardId id;
  final String card;
  final int owner;
  Place zone;

  /// Changes every time the card changes zones: it's a new card afterwards (CR 7.1.6).
  int zcc = 0;
  bool exerted = false;
  int damage = 0;

  /// In play since the start of its player's turn (CR 5.1.1.12).
  bool dry = false;

  /// The location this character is at.
  CardId? at;

  /// Cards under this one, top of the stack first (Shift, Boost; CR 5.1.1.5).
  List<CardId> under = [];
  bool faceDown = false;

  /// When it entered its zone (for timestamp order and "played this turn").
  int timestamp = 0;
  int enteredTurn = 0;

  /// Turn on which Boost or a "once per turn" ability was last used, by ability index.
  Map<int, int> usedOn = {};

  /// Played with Temporary Shift: goes back to the hand at the end of its player's turn
  /// (CR 8.10.8.5).
  bool temporaryShift = false;

  Obj clone() => Obj(id: id, card: card, owner: owner, zone: zone)
    ..zcc = zcc
    ..exerted = exerted
    ..damage = damage
    ..dry = dry
    ..at = at
    ..under = List.of(under)
    ..faceDown = faceDown
    ..timestamp = timestamp
    ..enteredTurn = enteredTurn
    ..usedOn = Map.of(usedOn)
    ..temporaryShift = temporaryShift;

  String digest() {
    final used = (usedOn.keys.toList()..sortStable((a, b) => a - b)).map((k) => '$k:${usedOn[k]}').join(',');
    return '$id.$zcc|${card.length}:$card|$owner|${zone.index}|$exerted|$damage|$dry|${at ?? ''}|${under.join(',')}|$faceDown|$timestamp|$enteredTurn|$used${temporaryShift ? '|t' : ''}';
  }
}

class Player {
  Player(this.name);
  final String name;
  List<CardId> deck = []; // index 0 is the top
  List<CardId> hand = [];
  List<CardId> play = [];
  List<CardId> inkwell = [];
  List<CardId> discard = [];
  int lore = 0;
  bool lost = false;
  bool altered = false;

  /// Cards put into the inkwell with the once-per-turn turn action this turn (CR 4.2.3).
  int inkedThisTurn = 0;

  /// Cards drawn this turn, characters of theirs banished this turn (for conditions).
  int drawnThisTurn = 0;

  /// This turn: cards put into their discard, actions they played, quests by their characters.
  int discardedThisTurn = 0, actionsThisTurn = 0, questsThisTurn = 0;

  List<CardId> zone(Place z) => switch (z) {
    Place.deck => deck,
    Place.hand => hand,
    Place.play => play,
    Place.inkwell => inkwell,
    Place.discard => discard,
  };

  Player clone() => Player(name)
    ..deck = List.of(deck)
    ..hand = List.of(hand)
    ..play = List.of(play)
    ..inkwell = List.of(inkwell)
    ..discard = List.of(discard)
    ..lore = lore
    ..lost = lost
    ..altered = altered
    ..inkedThisTurn = inkedThisTurn
    ..drawnThisTurn = drawnThisTurn
    ..discardedThisTurn = discardedThisTurn
    ..actionsThisTurn = actionsThisTurn
    ..questsThisTurn = questsThisTurn;

  String digest() => '${name.length}:$name|${deck.join(',')}|${hand.join(',')}|${play.join(',')}|${inkwell.join(',')}|${discard.join(',')}|$lore|$lost|$altered|$inkedThisTurn|$drawnThisTurn|$discardedThisTurn|$actionsThisTurn|$questsThisTurn';
}

/// What a triggered ability is about (CR 6.2): the card, the other card, the player, an amount,
/// and the card's last known values if it left play (CR 6.7.7).
class EventInfo {
  const EventInfo({this.card, this.other, this.player, this.amount = 0, this.strength = 0, this.location});
  final CardId? card, other;
  final int? player;
  final int amount;
  final int strength;
  final CardId? location;

  String digest() => '${card ?? ''}/${other ?? ''}/${player ?? ''}/$amount/$strength/${location ?? ''}';
}

/// A triggered ability waiting in the bag (CR 7.7).
class BagItem {
  BagItem({required this.id, required this.controller, required this.source, required this.ability, required this.event, required this.label, this.abilityIndex = -1, this.floating = false});
  final int id;
  final int controller;
  final CardId source;
  final Triggered ability;
  final EventInfo event;
  final String label;

  /// Which of the source card's abilities (for "once per turn"); -1 for floating/delayed ones.
  final int abilityIndex;
  final bool floating;

  String digest() => '$id|$controller|$source|${label.length}:$label|${event.digest()}|$abilityIndex|$floating';
}

/// A modification that lasts for a while (CR 6.4.2): to specific cards (applied), or to every
/// card that matches (continuous) when [cards] is null.
class Timed {
  Timed({
    required this.ts,
    required this.controller,
    required this.source,
    required this.lasting,
    required this.turn,
    this.cards,
    this.filter,
    this.stat,
    this.amount = 0,
    this.keyword,
    this.rule,
    this.label = '',
  });
  final int ts;
  final int controller;
  final CardId source;
  final Lasting lasting;

  /// The turn it was created on, and the player whose turn it was.
  final int turn;
  final List<CardId>? cards;
  final Filter? filter;
  final Stat? stat;
  final int amount;
  final Keyword? keyword;
  final Rule? rule;
  final String label;

  String digest() =>
      '$ts|$controller|$source|${lasting.index}|$turn|${cards?.join(',') ?? '*'}|${filter?.describe() ?? ''}|${stat?.index ?? ''}|$amount|${keyword?.key ?? ''}|${rule?.index ?? ''}|${label.length}:$label';
}

/// "You pay N less for the next X you play this turn" (CR 4.3.6).
class NextReduction {
  NextReduction(this.player, this.filter, this.n, this.turn);
  final int player;
  final Filter filter;
  final int n;
  final int turn;
  String digest() => '$player|${filter.describe()}|$n|$turn';
}

/// Floating (CR 6.2.7.1) and delayed (CR 6.2.7.2) triggered abilities.
class Lingering {
  Lingering({required this.id, required this.controller, required this.source, required this.ability, required this.turn, this.delayedEnd = false, this.remembered = const []});
  final int id;
  final int controller;
  final CardId source;
  final Triggered ability;
  final int turn;
  final bool delayedEnd;
  final List<CardId> remembered;
  String digest() => '$id|$controller|$source|${ability.text.length}:${ability.text}|$turn|$delayedEnd|${remembered.join(',')}';
}

enum DecisionKind {
  /// Choose cards from [Decision.options] (targets, discards, cards to keep).
  cards,

  /// Yes (1) or no (0).
  yesNo,

  /// One of [Decision.labels] (0-based).
  option,

  /// Put [Decision.options] in an order (the answer lists them all).
  order,
}

class Decision {
  const Decision({required this.kind, required this.player, required this.prompt, this.options = const [], this.min = 0, this.max = 0, this.labels = const [], this.source});
  final DecisionKind kind;
  final int player;
  final String prompt;
  final List<int> options;
  final int min, max;
  final List<String> labels;
  final CardId? source;

  String digest() => '${kind.index}|$player|${prompt.length}:$prompt|${options.join(',')}|$min|$max|${labels.join(';')}|${source ?? ''}';
}

class LogEntry {
  const LogEntry(this.text, {this.player, this.card, this.kind = 'info', this.amount = 0});
  final String text;
  final int? player;
  final CardId? card;

  /// ink, play, shift, sing, quest, challenge, damage, banish, lore, draw, move, ability, turn,
  /// ready, exert, return, win, lose, info.
  final String kind;
  final int amount;
}

enum Phase { setup, main, over }

class GameState {
  GameState(this.seed, List<String> names) : rng = SeededRng(seed), players = [for (final n in names) Player(n)];

  final int seed;
  SeededRng rng;
  List<Player> players;
  Map<CardId, Obj> objects = {};
  int nextId = 1;
  int nextTs = 1;
  int turn = 0;
  int active = 0;
  int firstPlayer = 0;
  Phase phase = Phase.setup;
  int? winner;
  List<BagItem> bag = [];
  int nextBagId = 1;

  /// Who resolved from the bag last (CR 7.7.4.3).
  int? bagTurn;
  List<Timed> timed = [];
  List<NextReduction> reductions = [];
  List<Lingering> lingering = [];

  /// Opposing characters banished in a challenge this turn, and characters banished this turn.
  int banishedInChallengeThisTurn = 0;

  /// Cards banished this turn as "fullName|owner|c" (c: in a challenge), for conditions.
  List<String> banishedThisTurn = [];
  int version = 0;
  List<LogEntry> log = [];

  bool get over => phase == Phase.over;
  Player player(int p) => players[p];
  Obj obj(CardId id) => objects[id]!;
  Obj? objOrNull(CardId id) => objects[id];

  /// Opponents of [p], in turn order after p.
  List<int> opponents(int p) => [for (var i = 1; i < players.length; i++) (p + i) % players.length];

  GameState clone() {
    final s = GameState._(seed)
      ..rng = SeededRng.fromState(rng.state)
      ..players = [for (final p in players) p.clone()]
      ..objects = {for (final e in objects.entries) e.key: e.value.clone()}
      ..nextId = nextId
      ..nextTs = nextTs
      ..turn = turn
      ..active = active
      ..firstPlayer = firstPlayer
      ..phase = phase
      ..winner = winner
      ..bag = List.of(bag)
      ..nextBagId = nextBagId
      ..bagTurn = bagTurn
      ..timed = List.of(timed)
      ..reductions = List.of(reductions)
      ..lingering = List.of(lingering)
      ..banishedInChallengeThisTurn = banishedInChallengeThisTurn
      ..banishedThisTurn = List.of(banishedThisTurn)
      ..version = version + 1
      ..log = List.of(log);
    return s;
  }

  GameState._(this.seed) : rng = SeededRng(seed), players = [];

  /// Canonical text of everything that matters for the rules.
  String digest() {
    final b = StringBuffer('l1|$seed|${rng.state}|$nextId|$nextTs|$turn|$active|$firstPlayer|${phase.index}|${winner ?? ''}|$nextBagId|${bagTurn ?? ''}|$banishedInChallengeThisTurn|${banishedThisTurn.map((x) => '${x.length}:$x').join(',')}\n');
    for (final p in players) {
      b.writeln(p.digest());
    }
    final ids = objects.keys.toList()..sortStable((a, b) => a - b);
    for (final id in ids) {
      b.writeln(objects[id]!.digest());
    }
    for (final i in bag) {
      b.writeln('bag:${i.digest()}');
    }
    for (final t in timed) {
      b.writeln('t:${t.digest()}');
    }
    for (final r in reductions) {
      b.writeln('r:${r.digest()}');
    }
    for (final l in lingering) {
      b.writeln('ling:${l.digest()}');
    }
    return b.toString();
  }
}

class LorcanaError extends TcgError {
  LorcanaError(super.message);
}
