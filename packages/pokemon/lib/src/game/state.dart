/// The state of a match: players, zones, Pokémon in play, lasting effects, the log.
library;

import 'package:tcg_core/tcg_core.dart';

import '../ir.dart';

typedef CardId = int;

/// Where a card is (rulebook: "Areas of Play").
enum Place { deck, hand, discard, prize, active, bench, attached, under, stadium }

class Obj {
  Obj({required this.id, required this.card, required this.owner, required this.zone});
  final CardId id;
  final String card;
  final int owner;
  Place zone;

  // A Pokémon in play (the top card of its stack):
  int damage = 0;
  List<Cond> conds = [];
  List<CardId> energy = [];
  CardId? tool;

  /// The Pokémon it evolved from, bottom first.
  List<CardId> under = [];

  /// The turn it came into play or last evolved (can't evolve again that turn).
  int playedTurn = 0;
  int abilityTurn = 0;

  /// The turn it became Paralyzed (it recovers after its owner's next turn).
  int paralyzedTurn = 0;

  /// For an attached card or one under a Pokémon: the Pokémon it belongs to.
  CardId? host;

  Obj clone() => Obj(id: id, card: card, owner: owner, zone: zone)
    ..damage = damage
    ..conds = List.of(conds)
    ..energy = List.of(energy)
    ..tool = tool
    ..under = List.of(under)
    ..playedTurn = playedTurn
    ..abilityTurn = abilityTurn
    ..paralyzedTurn = paralyzedTurn
    ..host = host;

  String digest() => '$id|${card.length}:$card|$owner|${zone.index}|$damage|${conds.map((c) => c.index).join(',')}|${energy.join(',')}|${tool ?? ''}|${under.join(',')}|$playedTurn|$abilityTurn|$paralyzedTurn|${host ?? ''}';
}

class Player {
  Player(this.name);
  final String name;
  List<CardId> deck = []; // index 0 is the top
  List<CardId> hand = [];
  List<CardId> discard = [];
  List<CardId> prizes = [];
  CardId? active;
  List<CardId> bench = [];
  bool lost = false;
  int mulligans = 0;

  // This turn:
  bool energyAttached = false;
  bool supporterPlayed = false;
  bool stadiumPlayed = false;
  bool retreated = false;

  /// Pokémon in play, Active first.
  List<CardId> get inPlay => [?active, ...bench];

  Player clone() => Player(name)
    ..deck = List.of(deck)
    ..hand = List.of(hand)
    ..discard = List.of(discard)
    ..prizes = List.of(prizes)
    ..active = active
    ..bench = List.of(bench)
    ..lost = lost
    ..mulligans = mulligans
    ..energyAttached = energyAttached
    ..supporterPlayed = supporterPlayed
    ..stadiumPlayed = stadiumPlayed
    ..retreated = retreated;

  String digest() => '${name.length}:$name|${deck.join(',')}|${hand.join(',')}|${discard.join(',')}|${prizes.join(',')}|${active ?? ''}|${bench.join(',')}|$lost|$mulligans|$energyAttached|$supporterPlayed|$stadiumPlayed|$retreated';
}

/// A lasting effect from an attack, on one Pokémon, until the end of turn [until].
class Timed {
  Timed(this.kind, this.target, this.n, this.until);
  final Lasting kind;
  final CardId target;
  final int n;
  final int until;
  String digest() => '${kind.index}:$target:$n:$until';
}

enum DecisionKind {
  /// Choose cards or Pokémon from [Decision.options].
  cards,
  yesNo,

  /// One of [Decision.labels].
  option,
}

class Decision {
  const Decision({required this.kind, required this.player, required this.prompt, this.options = const [], this.min = 1, this.max = 1, this.labels = const [], this.source});
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

  /// For the table's animations and sounds: turn, draw, play, evolve, energy, trainer, retreat,
  /// ability, attack, damage, heal, condition, ko, prize, coin, win, lose, info.
  final String kind;
  final int amount;
}

enum Phase { setup, main, over }

class GameState {
  GameState(this.seed, List<String> names) : rng = SeededRng(seed), players = [for (final n in names) Player(n)];
  GameState._(this.seed, this.rng, this.players);

  final int seed;
  SeededRng rng;
  List<Player> players;
  final Map<CardId, Obj> objects = {};
  int nextId = 1;
  int turn = 0;
  int active = 0;
  int firstPlayer = 0;
  Phase phase = Phase.setup;
  int? winner;
  CardId? stadium;
  List<Timed> timed = [];
  int version = 0;
  List<LogEntry> log = [];

  bool get over => phase == Phase.over;
  Player player(int p) => players[p];
  Obj obj(CardId id) => objects[id]!;
  Obj? objOrNull(CardId id) => objects[id];
  int opponent(int p) => (p + 1) % players.length;

  GameState clone() {
    final s = GameState._(seed, SeededRng.fromState(rng.state), [for (final p in players) p.clone()])
      ..nextId = nextId
      ..turn = turn
      ..active = active
      ..firstPlayer = firstPlayer
      ..phase = phase
      ..winner = winner
      ..stadium = stadium
      ..timed = List.of(timed)
      ..version = version
      ..log = List.of(log);
    for (final e in objects.entries) {
      s.objects[e.key] = e.value.clone();
    }
    return s;
  }

  String digest() {
    final b = StringBuffer('pkm1|$seed|${rng.state}|$nextId|$turn|$active|$firstPlayer|${phase.index}|${winner ?? ''}|${stadium ?? ''}\n');
    for (final p in players) {
      b.writeln(p.digest());
    }
    final ids = objects.keys.toList()..sortStable((a, b) => a - b);
    for (final id in ids) {
      b.writeln(objects[id]!.digest());
    }
    b.writeln(timed.map((t) => t.digest()).join(';'));
    return b.toString();
  }
}

class PokemonError extends TcgError {
  PokemonError(super.message);
}
