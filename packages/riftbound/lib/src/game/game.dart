/// The Riftbound engine. A match is its seed plus its moves (tcg_core's contract): every device
/// that applies the same moves reaches the same state and fingerprint.
///
/// Rules follow the Riftbound Core Rules (docs/riftbound-core-rules.txt); comments cite them as
/// "CR n". Mode of play: 1v1 Duel (CR 487).
///
/// Decisions work like the other engines': a move runs as a task that may stop to ask a player
/// something ([NeedDecision]); the state before the move is kept, and each answer re-runs the
/// task from there with all answers so far.
///
/// After every move the engine "settles" (CR 333–348, "HOT FEPR"): cleanups, triggered abilities
/// onto the chain, Priority and Focus passing, resolving the chain, opening showdowns and combat,
/// and walking the turn's steps — until a player has something to decide. A player who holds
/// Priority or Focus but can't do anything except pass passes automatically.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:tcg_core/tcg_core.dart';

import '../cards/card.dart';
import '../cards/card_db.dart';
import '../describe.dart';
import '../ir.dart';
import '../parser/parser.dart';
import 'moves.dart';
import 'state.dart';

part 'play.dart';
part 'combat.dart';
part 'costs.dart';
part 'effects.dart';
part 'query.dart';
part 'testing.dart';
part 'power.dart';
part 'hidden.dart';

class NeedDecision implements Exception {
  NeedDecision(this.decision);
  final Decision decision;
}

class Pending {
  Pending(this.move, this.answers, this.decision, this.snapshot);
  final RMove move;
  final List<List<int>> answers;
  final Decision decision;
  final GameState snapshot;
}

class Game implements TcgMatch {
  Game(this.db, {required List<String> players, required int seed}) : state = GameState(seed, players);
  Game._probe(Game g)
      : db = g.db,
        state = g.state.clone(),
        _probe = true;

  final RCardDb db;
  GameState state;
  Pending? pending;
  final List<RMove> actions = [];

  /// Legality probes answer every question with the default answer.
  bool _probe = false;
  List<List<int>> _answers = const [];
  int _answerIndex = 0;

  @override
  List<RMove> get moves => actions;

  @override
  bool get over => state.over;

  @override
  int get turn => state.turn;

  @override
  int? get toAct {
    if (state.over) return null;
    final p = pending;
    if (p != null) return p.decision.player;
    if (state.phase != Phase.main) return null;
    if (state.chain.isNotEmpty) return state.priority;
    final sd = state.showdown;
    if (sd != null) return sd.focus;
    return state.active;
  }

  @override
  String get fingerprint {
    final p = pending;
    final d = p == null ? '' : 'pd:${p.decision.digest()}|${p.answers.map((a) => a.join(',')).join(';')}';
    return sha256.convert(utf8.encode('${state.digest()}$d')).toString().substring(0, 24);
  }

  RCard card(ObjId id) => db[state.obj(id).card]!;
  ParsedCard parsed(ObjId id) => RiftboundParser.parse(card(id));
  String nameOf(ObjId id) => card(id).name;
  String playerName(int p) => state.player(p).name;

  // -------------------------------------------------------------------------------------------
  // Applying moves
  // -------------------------------------------------------------------------------------------

  @override
  void apply(covariant RMove move) {
    if (state.over) throw RiftboundError('The game is over');
    if (move is ConcedeMove) {
      pending = null;
      state.player(move.seat).lost = true;
      log('${playerName(move.seat)} concedes.', player: move.seat, kind: 'lose');
      _win(state.other(move.seat));
      actions.add(move);
      return;
    }
    final p = pending;
    if (p != null) {
      if (move is! AnswerMove) throw RiftboundError('Waiting for ${playerName(p.decision.player)}: ${p.decision.prompt}');
      if (move.seat != p.decision.player) throw RiftboundError('That decision belongs to ${playerName(p.decision.player)}');
      _checkAnswer(p.decision, move.answer);
      final before = state;
      try {
        _run(p.move, [...p.answers, move.answer], p.snapshot);
      } on TcgError {
        state = before;
        pending = p;
        rethrow;
      }
      actions.add(move);
      return;
    }
    if (move is AnswerMove) throw RiftboundError('Nothing to answer');
    if (move is StartMove) {
      if (state.phase != Phase.setup || actions.isNotEmpty) throw RiftboundError('Already started');
    } else {
      if (state.phase != Phase.main) throw RiftboundError('The game hasn’t started');
      if (move.seat != toAct) throw RiftboundError('It isn’t ${playerName(move.seat)}’s move');
    }
    _run(move, const [], state.clone());
    actions.add(move);
  }

  void _run(RMove move, List<List<int>> answers, GameState snapshot) {
    final before = state;
    state = snapshot.clone();
    _answers = answers;
    _answerIndex = 0;
    // Legality checks while settling must not see the decision being answered.
    pending = null;
    try {
      _exec(move);
      _settle();
      pending = null;
    } on NeedDecision catch (e) {
      pending = Pending(move, answers, e.decision, snapshot);
    } on TcgError {
      state = before;
      rethrow;
    }
  }

  void _checkAnswer(Decision d, List<int> a) {
    switch (d.kind) {
      case DecisionKind.cards:
        if (a.length < d.min || a.length > d.max) throw RiftboundError('Choose ${d.min == d.max ? d.min : '${d.min}–${d.max}'}');
        if (a.toSet().length != a.length || !a.every(d.options.contains)) throw RiftboundError('Not one of the choices');
      case DecisionKind.yesNo:
        if (a.length != 1 || (a[0] != 0 && a[0] != 1)) throw RiftboundError('Yes or no');
      case DecisionKind.option:
        if (a.length != 1 || a[0] < 0 || a[0] >= d.labels.length) throw RiftboundError('Pick one of the options');
    }
  }

  /// Asks the question, or returns the answer already given when the task is re-run. A choice
  /// with only one possible answer isn't asked.
  List<int> ask(Decision d) {
    if (d.kind == DecisionKind.cards && d.min == d.max && d.options.length == d.min) return List.of(d.options);
    if (d.kind == DecisionKind.cards && d.max == 0) return const [];
    if (d.kind == DecisionKind.option && d.labels.length == 1) return const [0];
    if (_probe) return defaultAnswer(d);
    if (_answerIndex < _answers.length) return _answers[_answerIndex++];
    throw NeedDecision(d);
  }

  bool askYesNo(int player, String prompt, {ObjId? source}) => ask(Decision(kind: DecisionKind.yesNo, player: player, prompt: prompt, source: source)).first == 1;

  /// What a probe (and a player with no opinion) answers.
  static List<int> defaultAnswer(Decision d) => switch (d.kind) {
        DecisionKind.cards => d.options.take(d.min).toList(),
        DecisionKind.yesNo => const [1],
        DecisionKind.option => const [0],
      };

  void _exec(RMove move) {
    switch (move) {
      case StartMove():
        _start(move);
      case PlayMove():
        _playFromHand(move.seat, move.card);
      case ActivateMove():
        _activate(move.seat, move.source, move.index);
      case MoveUnitsMove():
        _standardMove(move.seat, move.units, move.to);
      case HideMove():
        _hide(move.seat, move.card);
      case PassMove():
        _pass(move.seat);
      case EndTurnMove():
        _endTurn(move.seat);
      case AnswerMove() || ConcedeMove():
        break;
    }
  }

  void log(String text, {int? player, ObjId? card, String kind = 'info', int amount = 0}) {
    state.log.add(LogEntry(text, player: player, card: card, kind: kind, amount: amount));
  }

  // -------------------------------------------------------------------------------------------
  // Setup (CR 110–118, 487)
  // -------------------------------------------------------------------------------------------

  ObjId _newObj(String key, int owner, Zone zone) {
    if (db[key] == null) throw RiftboundError('Unknown card: $key');
    final id = state.nextId++;
    state.objects[id] = Obj(id: id, card: key, owner: owner, zone: zone);
    return id;
  }

  void _start(StartMove m) {
    if (m.decks.length != state.players.length) throw RiftboundError('One deck per player');
    final chosenBfs = <ObjId>[];
    for (var p = 0; p < m.decks.length; p++) {
      final deck = m.decks[p];
      final legends = [for (final k in deck) if (db[k]?.type == CardType.legend) k];
      if (legends.length != 1) throw RiftboundError('${playerName(p)}’s deck needs exactly one Champion Legend');
      final legend = db[legends.first]!;
      final pl = state.player(p);
      pl.legend = _newObj(legend.key, p, Zone.legend);
      final rest = List.of(deck)..remove(legend.key);
      // The Chosen Champion: a champion unit with the legend's champion tag (CR 103.3.a).
      final champ = rest.where((k) => db[k]?.type == CardType.unit && db[k]!.champion && legend.tags.any(db[k]!.hasTag)).firstOrNull;
      if (champ != null) {
        rest.remove(champ);
        pl.champion = _newObj(champ, p, Zone.champion);
      }
      final bfs = <String>[];
      for (final k in rest) {
        final c = db[k];
        if (c == null) throw RiftboundError('Unknown card: $k');
        switch (c.type) {
          case CardType.battlefield:
            bfs.add(k);
          case CardType.rune:
            pl.runeDeck.add(_newObj(k, p, Zone.runeDeck));
          case CardType.legend:
            break;
          default:
            pl.deck.add(_newObj(k, p, Zone.mainDeck));
        }
      }
      if (bfs.isEmpty) throw RiftboundError('${playerName(p)}’s deck needs a battlefield');
      // Each player randomly selects one of their battlefields (CR 487.5).
      final pick = bfs[state.rng.nextInt(bfs.length)];
      final bfObj = _newObj(pick, p, Zone.battlefield);
      chosenBfs.add(bfObj);
      state.rng.shuffle(pl.deck);
      state.rng.shuffle(pl.runeDeck);
    }
    for (final b in chosenBfs) {
      state.obj(b).loc = state.bfs.length;
      state.bfs.add(Bf(b));
    }
    state.firstPlayer = m.firstPlayer ?? state.rng.nextInt(state.players.length);
    state.phase = Phase.main;
    log('${playerName(state.firstPlayer)} goes first.', player: state.firstPlayer, kind: 'turn');
    for (var p = 0; p < state.players.length; p++) {
      _draw(p, 4);
    }
    // Mulligans in turn order (CR 117): set aside up to two, draw that many, recycle them.
    for (var i = 0; i < state.players.length; i++) {
      final p = (state.firstPlayer + i) % state.players.length;
      final pl = state.player(p);
      final aside = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Mulligan: choose up to 2 cards to replace', options: List.of(pl.hand), min: 0, max: 2));
      if (aside.isEmpty) continue;
      for (final id in aside) {
        pl.hand.remove(id);
      }
      _draw(p, aside.length);
      _recycleCards(p, aside);
      log('${pl.name} replaces ${aside.length} card${aside.length == 1 ? '' : 's'}.', player: p);
    }
    _beginTurn(state.firstPlayer);
  }

  // -------------------------------------------------------------------------------------------
  // The turn (CR 314–317)
  // -------------------------------------------------------------------------------------------

  void _beginTurn(int p) {
    state.turn++;
    state.active = p;
    state.step = Step.beginning;
    log('Turn ${state.turn}: ${playerName(p)}.', player: p, kind: 'turn');
    // Awaken (CR 315.1): ready everything the turn player controls.
    final pl = state.player(p);
    pl.playedThisTurn = 0;
    pl.scored = [];
    for (final o in state.objects.values) {
      if (o.controller == p && (o.zone == Zone.board || o.zone == Zone.runes || o.zone == Zone.legend)) {
        if (!_hCantReady(o.id)) {
          if (o.zone == Zone.board && o.exhausted) _xBecameReady(o.id);
          o.exhausted = false;
        }
        o.usedThisTurn = [];
      }
    }
    // Beginning step (CR 315.2.a): start-of-turn effects; Temporary kills before scoring (CR 816).
    for (final o in _boardOf(p)) {
      if (_kw(o.id, Kw.temporary) > 0) {
        log('${nameOf(o.id)} is Temporary and dies.', player: p, card: o.id, kind: 'die');
        _kill(o.id);
      }
    }
    _fire(On.startOfTurn, player: p);
  }

  /// Walks the steps of the turn while nothing is waiting (CR 305).
  void _advanceStep() {
    final p = state.active;
    switch (state.step) {
      case Step.beginning:
        state.step = Step.scoring;
        // Scoring step (CR 315.2.b): hold every battlefield you control.
        for (var i = 0; i < state.bfs.length; i++) {
          if (state.bfs[i].controller == p) _scoreBf(p, i, conquer: false);
        }
      case Step.scoring:
        state.step = Step.channel;
        // Channel phase (CR 315.3, 487.7): 2 runes; the second player's first turn 3.
        final first = state.turn == 2 && p != state.firstPlayer;
        _channel(p, first ? 3 : 2);
      case Step.channel:
        state.step = Step.draw;
        _draw(p, 1);
      case Step.draw:
        state.step = Step.main;
        // Main phase (CR 316.3): rune pools empty.
        _emptyPools();
      case Step.main:
        break;
      case Step.ending:
        _powerEndOfTurn();
        // Expiration step (CR 317.2): heal, stuns and "this turn" effects end, pools empty.
        _hEndOfTurn();
        for (final o in state.objects.values) {
          if (o.zone == Zone.board) {
            o.damage = 0;
            o.stunned = false;
            o.mightMod = 0;
            o.kwMod = {};
          }
        }
        _emptyPools();
        _beginTurn(state.other(p));
    }
  }

  void _endTurn(int seat) {
    if (seat != state.active || state.step != Step.main || state.chain.isNotEmpty || state.showdown != null) throw RiftboundError('You can only end your turn in your Main Phase with nothing pending');
    log('${playerName(seat)} ends the turn.', player: seat);
    state.step = Step.ending;
    _fire(On.endOfTurn, player: seat);
  }

  void _emptyPools() {
    for (final pl in state.players) {
      pl.energyPool = 0;
      pl.powerPool = [0, 0, 0, 0, 0, 0];
      pl.anyPool = 0;
    }
  }

  void _win(int p) {
    if (state.over) return;
    state.winner = p;
    state.phase = Phase.over;
    state.chain = [];
    state.waiting = [];
    state.showdown = null;
    log('${playerName(p)} wins!', player: p, kind: 'win');
  }

  // -------------------------------------------------------------------------------------------
  // Settling: HOT FEPR (CR 333–348)
  // -------------------------------------------------------------------------------------------

  void _settle() {
    for (var guard = 0; guard < 2000; guard++) {
      if (state.over) return;
      if (_cleanup()) continue;
      if (state.over) return;
      // Triggered abilities waiting go on the chain (CR 382).
      if (state.waiting.isNotEmpty) {
        final t = state.waiting.removeAt(0);
        _finalizeTrigger(t);
        continue;
      }
      if (state.chain.isNotEmpty) {
        final p = state.priority;
        if (_canReact(p)) return;
        _passPriority(p);
        continue;
      }
      final sd = state.showdown;
      if (sd != null) {
        if (sd.focusChain) {
          // The chain the Focus player started has closed: Focus passes (CR 346).
          sd.focusChain = false;
          sd.passes = 0;
          sd.focus = state.other(sd.focus);
          continue;
        }
        if (_canActInShowdown(sd.focus)) return;
        _passFocus(sd.focus);
        continue;
      }
      if (_openStaged()) continue;
      if (state.step == Step.main) return;
      _advanceStep();
    }
    throw RiftboundError('The game could not settle');
  }

  void _pass(int seat) {
    if (state.chain.isNotEmpty) {
      if (seat != state.priority) throw RiftboundError('You don’t have Priority');
      _passPriority(seat);
      return;
    }
    final sd = state.showdown;
    if (sd != null) {
      if (seat != sd.focus) throw RiftboundError('You don’t have Focus');
      _passFocus(seat);
      return;
    }
    throw RiftboundError('Nothing to pass');
  }

  /// CR 338.1.b, 339: when both players pass in sequence, the newest item resolves.
  void _passPriority(int p) {
    state.passes++;
    if (state.passes >= state.players.length) {
      state.passes = 0;
      _resolveTop();
      if (state.chain.isNotEmpty) state.priority = state.chain.last.controller;
    } else {
      state.priority = state.other(p);
    }
  }

  /// CR 347.2: when both players pass Focus in sequence, the showdown ends.
  void _passFocus(int p) {
    final sd = state.showdown!;
    sd.passes++;
    if (sd.passes >= state.players.length) {
      _closeShowdown();
    } else {
      sd.focus = state.other(p);
    }
  }
}
