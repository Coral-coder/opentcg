/// The state of a match: players, zones, the board, the battlefields, the chain, showdowns and
/// combat, the log. Everything a fingerprint covers is in [GameState.digest].
library;

import 'package:tcg_core/tcg_core.dart';

import '../cards/card.dart';
import '../ir.dart';
import 'state_power.dart';

export 'state_power.dart';

part 'gen_state.dart';

typedef ObjId = int;

/// Zones (CR 105–108). Board objects are in [Zone.board] at a location ([Obj.loc]).
enum Zone {
  mainDeck,
  hand,
  trash,
  banish,
  board,
  champion,
  legend,
  runeDeck,
  runes,
  battlefield,
  chain,
  gone,

  /// A battlefield's Facedown Zone (CR 107.3): [Obj.loc] is the battlefield, [Obj.enteredTurn]
  /// the turn it was hidden.
  facedown,
}

/// [Obj.loc] of a permanent in its controller's base (CR 107.1).
const base = -1;

class Obj {
  Obj({required this.id, required this.card, required this.owner, required this.zone}) : controller = owner;
  final ObjId id;
  final String card;
  final int owner;
  int controller;
  Zone zone;

  /// [base] or a battlefield's index.
  int loc = base;
  bool exhausted = false;
  int damage = 0;
  bool buffed = false;
  bool stunned = false;

  /// +/- Might until end of turn (CR 479.4).
  int mightMod = 0;

  /// Keywords given until end of turn: kw index → value.
  Map<int, int> kwMod = {};
  int enteredTurn = 0;

  /// Activated abilities used this turn (for "Use only once per turn"), by index.
  List<int> usedThisTurn = [];

  /// Empowered, extra buffs, Flow (state_power.dart).
  ObjPower pw = ObjPower();

  Obj clone() => Obj(id: id, card: card, owner: owner, zone: zone)
    ..controller = controller
    ..loc = loc
    ..exhausted = exhausted
    ..damage = damage
    ..buffed = buffed
    ..stunned = stunned
    ..mightMod = mightMod
    ..kwMod = Map.of(kwMod)
    ..enteredTurn = enteredTurn
    ..usedThisTurn = List.of(usedThisTurn)
    ..pw = pw.clone();

  /// Leaving the board (or entering it) makes a new object for rules purposes (CR 124.1).
  void reset() {
    exhausted = false;
    damage = 0;
    buffed = false;
    stunned = false;
    mightMod = 0;
    kwMod = {};
    usedThisTurn = [];
    pw = ObjPower();
    loc = base;
    controller = owner;
  }

  String digest() {
    final kws = kwMod.keys.toList()..sortStable((a, b) => a - b);
    return '$id|${card.length}:$card|$owner|$controller|${zone.index}|$loc|$exhausted|$damage|$buffed|$stunned|$mightMod|${kws.map((k) => '$k=${kwMod[k]}').join(',')}|$enteredTurn|${usedThisTurn.join(',')}|${pw.digest()}';
  }
}

class Player {
  Player(this.name);
  final String name;

  /// Index 0 is the top.
  List<ObjId> deck = [];
  List<ObjId> hand = [];
  List<ObjId> trash = [];
  List<ObjId> banish = [];
  List<ObjId> runeDeck = [];

  /// Runes on the board (in the base).
  List<ObjId> runes = [];
  ObjId? legend;

  /// The Chosen Champion while it's in the Champion Zone (CR 108.3).
  ObjId? champion;
  int points = 0;

  /// The Rune Pool (CR 165): Energy, Power by domain, and Power of any domain.
  int energyPool = 0;
  List<int> powerPool = [0, 0, 0, 0, 0, 0];
  int anyPool = 0;

  /// Cards finalized this turn (Legion, CR 812).
  int playedThisTurn = 0;

  /// Battlefields (indices) scored this turn (CR 472).
  List<int> scored = [];
  bool lost = false;

  /// XP (state_power.dart).
  PlayerPower pw = PlayerPower();

  Player clone() => Player(name)
    ..deck = List.of(deck)
    ..hand = List.of(hand)
    ..trash = List.of(trash)
    ..banish = List.of(banish)
    ..runeDeck = List.of(runeDeck)
    ..runes = List.of(runes)
    ..legend = legend
    ..champion = champion
    ..points = points
    ..energyPool = energyPool
    ..powerPool = List.of(powerPool)
    ..anyPool = anyPool
    ..playedThisTurn = playedThisTurn
    ..scored = List.of(scored)
    ..lost = lost
    ..pw = pw.clone();

  String digest() =>
      '${name.length}:$name|${deck.join(',')}|${hand.join(',')}|${trash.join(',')}|${banish.join(',')}|${runeDeck.join(',')}|${runes.join(',')}|${legend ?? ''}|${champion ?? ''}|$points|$energyPool|${powerPool.join(',')}|$anyPool|$playedThisTurn|${scored.join(',')}|$lost|${pw.digest()}';
}

/// A battlefield in play (CR 169, 188–190).
class Bf {
  Bf(this.obj);
  final ObjId obj;
  int? controller;

  /// The player who applied the Contested status (CR 190.3).
  int? contestedBy;

  Bf clone() => Bf(obj)
    ..controller = controller
    ..contestedBy = contestedBy;
  String digest() => '$obj|${controller ?? ''}|${contestedBy ?? ''}';
}

/// A spell or ability on the Chain (CR 327).
class ChainItem {
  ChainItem({required this.id, required this.source, required this.card, required this.ability, required this.controller, this.targets = const [], this.repeats = 0, this.loc = base, this.fromTrigger = false, this.legion = false, this.event = -1});
  final int id;

  /// The card (a spell on the chain) or the object whose ability this is.
  final ObjId source;
  final String card;

  /// Index into the source's parsed abilities; -1 for a spell's instructions.
  final int ability;
  final int controller;

  /// Chosen objects by slot (CR 355.5); -1 for "chose nothing".
  final List<int> targets;
  final int repeats;

  /// The source's location as it was put on the chain ("here").
  final int loc;
  final bool fromTrigger;
  final bool legion;

  /// The unit a trigger is about ("it"), or -1.
  final int event;

  bool get isSpell => ability < 0;

  String digest() => '$id|$source|${card.length}:$card|$ability|$controller|${targets.join(',')}|$repeats|$loc|$fromTrigger|$legion|$event';
}

/// A showdown, and the combat it may be part of (CR 341, 461).
class Showdown {
  Showdown({required this.bf, required this.combat, required this.attacker, required this.focus});
  final int bf;
  bool combat;

  /// The player who applied Contested (the attacker in a combat, CR 466.2.c.1).
  final int attacker;
  int focus;

  /// Consecutive passes of Focus (CR 347.2).
  int passes = 0;

  /// The open chain was started by the Focus player's play (Focus passes when it closes, CR 346).
  bool focusChain = false;

  Showdown clone() => Showdown(bf: bf, combat: combat, attacker: attacker, focus: focus)
    ..passes = passes
    ..focusChain = focusChain;
  String digest() => '$bf|$combat|$attacker|$focus|$passes|$focusChain';
}

enum DecisionKind {
  /// Choose cards or objects from [Decision.options].
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
  final ObjId? source;

  String digest() => '${kind.index}|$player|${prompt.length}:$prompt|${options.join(',')}|$min|$max|${labels.join(';')}|${source ?? ''}';
}

class LogEntry {
  const LogEntry(this.text, {this.player, this.card, this.kind = 'info', this.amount = 0});
  final String text;
  final int? player;
  final ObjId? card;

  /// For the table's animations and sounds: turn, draw, play, move, attack, damage, die, conquer,
  /// hold, point, channel, ability, showdown, win, lose, info.
  final String kind;
  final int amount;
}

enum Phase { setup, main, over }

/// Steps of a turn (CR 314–317) the engine walks through.
enum Step { beginning, scoring, channel, draw, main, ending }

class GameState {
  GameState(this.seed, List<String> names) : rng = SeededRng(seed), players = [for (final n in names) Player(n)];
  GameState._(this.seed, this.rng, this.players);

  final int seed;
  SeededRng rng;
  List<Player> players;
  final Map<ObjId, Obj> objects = {};
  int nextId = 1;
  int turn = 0;
  int active = 0;
  int firstPlayer = 0;
  Phase phase = Phase.setup;
  Step step = Step.beginning;
  int? winner;
  int victoryScore = 8;
  List<Bf> bfs = [];

  /// Bottom first; the last item resolves first (CR 340.1).
  List<ChainItem> chain = [];
  int nextChainId = 1;

  /// The player with Priority while the chain exists (CR 312), and consecutive passes.
  int priority = 0;
  int passes = 0;
  Showdown? showdown;

  /// Triggered abilities waiting to be put on the chain (CR 382), in order.
  List<ChainItem> waiting = [];

  /// Small facts effects leave behind, by name ("readyEnter:0" = player 0's units enter ready
  /// this turn). Looked up by key; the digest lists them sorted.
  Map<String, int> marks = {};
  final List<LogEntry> log = [];

  /// The general effects' bookkeeping (gen_state.dart).
  GenState gen = GenState();
  /// Delayed effects of Empower/XP/buff cards (state_power.dart).
  GamePower pw = GamePower();

  bool get over => phase == Phase.over;
  Player player(int i) => players[i];
  Obj obj(ObjId id) => objects[id]!;
  Obj? objOrNull(ObjId id) => objects[id];
  int other(int p) => 1 - p;

  GameState clone() {
    final s = GameState._(seed, SeededRng.fromState(rng.state), [for (final p in players) p.clone()]);
    for (final e in objects.entries) {
      s.objects[e.key] = e.value.clone();
    }
    s
      ..nextId = nextId
      ..turn = turn
      ..active = active
      ..firstPlayer = firstPlayer
      ..phase = phase
      ..step = step
      ..winner = winner
      ..victoryScore = victoryScore
      ..bfs = [for (final b in bfs) b.clone()]
      ..chain = List.of(chain)
      ..nextChainId = nextChainId
      ..priority = priority
      ..passes = passes
      ..showdown = showdown?.clone()
      ..waiting = List.of(waiting)
      ..pw = pw.clone()
      ..marks = Map.of(marks)
      ..gen = gen.clone();
    s.log.addAll(log);
    return s;
  }

  String digest() {
    final b = StringBuffer()
      ..write('rb1|$seed|${rng.state}|$nextId|$turn|$active|$firstPlayer|${phase.index}|${step.index}|${winner ?? ''}|$victoryScore|')
      ..write('${bfs.map((x) => x.digest()).join(';')}|')
      ..write('${chain.map((c) => c.digest()).join(';')}|$nextChainId|$priority|$passes|${showdown?.digest() ?? ''}|')
      ..write('${waiting.map((c) => c.digest()).join(';')}|${pw.digest()}|${gen.digest()}|')
      ..write('${(marks.keys.toList()..sortStable((a, b) => a.compareTo(b))).map((k) => '$k=${marks[k]}').join(',')}|');
    for (final p in players) {
      b.write('${p.digest()}#');
    }
    final ids = objects.keys.toList()..sortStable((a, b) => a - b);
    for (final id in ids) {
      b.write('${objects[id]!.digest()};');
    }
    b.write('log${log.length}');
    return b.toString();
  }
}

/// Domains a rune makes Power of.
Domain? runeDomain(RCard c) => c.type == CardType.rune && c.domains.isNotEmpty ? c.domains.first : null;

/// Keyword lookup helper for describe/tests.
String kwLabel(Kw k) => '${k.name[0].toUpperCase()}${k.name.substring(1)}';
