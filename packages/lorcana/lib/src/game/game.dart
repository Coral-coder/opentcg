/// The Lorcana engine. A match is its seed plus its moves (tcg_core's contract): every device
/// that applies the same moves reaches the same state and fingerprint.
///
/// Decisions work like the Magic engine's: a move runs as a task that may stop to ask a player
/// something ([NeedDecision]); the state as it was before the move is kept, and each answer
/// re-runs the task from there with all answers so far. The table shows the state up to the
/// question.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:tcg_core/tcg_core.dart';

import '../cards/card.dart';
import '../cards/card_db.dart';
import '../ir.dart';
import '../parser/parser.dart';
import 'moves.dart';
import 'state.dart';

part 'chars.dart';
part 'turn_actions.dart';
part 'effects.dart';
part 'bag.dart';
part 'query.dart';
part 'testing.dart';
part 'zones.dart';
part 'board.dart';
part 'statics.dart';
part 'wave2_s3.dart';

class NeedDecision implements Exception {
  NeedDecision(this.decision);
  final Decision decision;
}

class Pending {
  Pending(this.move, this.answers, this.decision, this.snapshot);
  final LMove move;
  final List<List<int>> answers;
  final Decision decision;
  final GameState snapshot;
}

class Game implements TcgMatch {
  Game(this.db, {required List<String> players, required int seed}) : state = GameState(seed, players);

  final LCardDb db;
  GameState state;
  Pending? pending;
  final List<LMove> actions = [];

  // Answers being replayed into the running task, and what the running task tracks between a
  // challenge and the game state check after it. Reset at the start of every run.
  List<List<int>> _answers = const [];
  int _answerIndex = 0;
  final Map<CardId, (CardId, bool)> _lastDamageBy = {};

  /// The challenger and the challenged card while challenge damage is worked out ("while being
  /// challenged"); never set across a decision.
  (CardId, CardId)? _challengePair;

  @override
  List<LMove> get moves => actions;

  @override
  bool get over => state.over;

  @override
  int get turn => state.turn;

  @override
  int? get toAct => state.over ? null : (pending?.decision.player ?? (state.phase == Phase.main ? state.active : null));

  @override
  String get fingerprint {
    final p = pending;
    final d = p == null ? '' : 'pd:${p.decision.digest()}|${p.answers.map((a) => a.join(',')).join(';')}';
    return sha256.convert(utf8.encode('${state.digest()}$d')).toString().substring(0, 24);
  }

  LCard card(CardId id) => db[state.obj(id).card]!;
  ParsedCard parsed(CardId id) => LorcanaParser.parse(card(id));
  String nameOf(CardId id) => state.obj(id).card;

  // -------------------------------------------------------------------------------------------
  // Applying moves
  // -------------------------------------------------------------------------------------------

  @override
  void apply(covariant LMove move) {
    if (state.over) throw LorcanaError('The game is over');
    if (move is ConcedeMove) {
      _concede(move.seat);
      actions.add(move);
      return;
    }
    final p = pending;
    if (p != null) {
      if (move is! AnswerMove) throw LorcanaError('Waiting for ${state.player(p.decision.player).name}: ${p.decision.prompt}');
      if (move.seat != p.decision.player) throw LorcanaError('That decision belongs to ${state.player(p.decision.player).name}');
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
    if (move is AnswerMove) throw LorcanaError('Nothing to answer');
    if (move is StartMove) {
      if (state.phase != Phase.setup || state.turn != 0 || actions.isNotEmpty) throw LorcanaError('Already started');
    } else {
      if (state.phase != Phase.main) throw LorcanaError('The game hasn’t started');
      if (move.seat != state.active) throw LorcanaError('It’s ${state.player(state.active).name}’s turn');
      _validate(move);
    }
    _run(move, const [], state.clone());
    actions.add(move);
  }

  void _run(LMove move, List<List<int>> answers, GameState snapshot) {
    final before = state;
    state = snapshot.clone();
    _answers = answers;
    _answerIndex = 0;
    _lastDamageBy.clear();
    try {
      _exec(move);
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
        if (a.length < d.min || a.length > d.max) throw LorcanaError('Choose ${d.min == d.max ? d.min : '${d.min}–${d.max}'}');
        if (a.toSet().length != a.length || !a.every(d.options.contains)) throw LorcanaError('Not one of the choices');
      case DecisionKind.yesNo:
        if (a.length != 1 || (a[0] != 0 && a[0] != 1)) throw LorcanaError('Yes or no');
      case DecisionKind.option:
        if (a.length != 1 || a[0] < 0 || a[0] >= d.labels.length) throw LorcanaError('Pick one of the options');
      case DecisionKind.order:
        if (a.length != d.options.length || !a.every(d.options.contains) || a.toSet().length != a.length) throw LorcanaError('Order all of them');
    }
  }

  /// Asks the question, or returns the answer already given when the task is re-run. A choice
  /// with only one possible answer isn't asked.
  List<int> ask(Decision d) {
    if (d.kind == DecisionKind.cards && d.min == d.max && d.options.length == d.min) return List.of(d.options);
    if (d.kind == DecisionKind.cards && d.max == 0) return const [];
    if (d.kind == DecisionKind.order && d.options.length < 2) return List.of(d.options);
    if (_answerIndex < _answers.length) return _answers[_answerIndex++];
    throw NeedDecision(d);
  }

  bool askYesNo(int player, String prompt, {CardId? source}) => ask(Decision(kind: DecisionKind.yesNo, player: player, prompt: prompt, source: source)).first == 1;

  void _exec(LMove move) {
    _s3BeforeAction(move);
    switch (move) {
      case StartMove():
        _start(move);
      case InkMove():
        _ink(move.seat, move.card);
      case PlayMove():
        _play(move);
      case QuestMove():
        _quest(move.seat, move.card);
      case ChallengeMove():
        _challenge(move.seat, move.card, move.target);
      case MoveMove():
        _moveCharacter(move.seat, move.card, move.location, pay: true);
      case ActivateMove():
        _activate(move.seat, move.card, move.index);
      case EndTurnMove():
        _endTurn();
      case AnswerMove() || ConcedeMove():
        break;
    }
    if (!state.over && move is! StartMove && move is! EndTurnMove) _afterTurnAction();
  }

  void _afterTurnAction() {
    _check();
    _resolveBag();
  }

  void log(String text, {int? player, CardId? card, String kind = 'info', int amount = 0}) {
    state.log.add(LogEntry(text, player: player, card: card, kind: kind, amount: amount));
  }

  // -------------------------------------------------------------------------------------------
  // Setup (CR 2.2)
  // -------------------------------------------------------------------------------------------

  void _start(StartMove m) {
    final s = state;
    if (m.decks.length != s.players.length) throw LorcanaError('One deck per player');
    for (var p = 0; p < s.players.length; p++) {
      for (final name in m.decks[p]) {
        final c = db[name];
        if (c == null) throw LorcanaError('Unknown card $name');
        final o = Obj(id: s.nextId++, card: c.fullName, owner: p, zone: Place.deck);
        s.objects[o.id] = o;
        s.player(p).deck.add(o.id);
      }
      s.rng.shuffle(s.player(p).deck);
    }
    // The starting player (CR 2.2.1.1).
    s.firstPlayer = m.firstPlayer ?? s.rng.nextInt(s.players.length);
    s.active = s.firstPlayer;
    log('${s.player(s.firstPlayer).name} goes first.', player: s.firstPlayer, kind: 'turn');
    for (var p = 0; p < s.players.length; p++) {
      for (var i = 0; i < 7; i++) {
        _draw(p, quiet: true);
      }
    }
    // Altering hands, in turn order (CR 2.2.2).
    for (var i = 0; i < s.players.length; i++) {
      final p = (s.firstPlayer + i) % s.players.length;
      final pl = s.player(p);
      final put = ask(
        Decision(
          kind: DecisionKind.cards,
          player: p,
          prompt: 'Alter your hand: choose cards to put on the bottom of your deck (or none to keep)',
          options: List.of(pl.hand),
          min: 0,
          max: pl.hand.length,
        ),
      );
      if (put.isEmpty) continue;
      for (final id in put) {
        _moveTo(id, Place.deck);
      }
      for (var k = 0; k < put.length; k++) {
        _draw(p, quiet: true);
      }
      s.rng.shuffle(pl.deck);
      pl.altered = true;
      log('${pl.name} puts ${put.length} card${put.length == 1 ? '' : 's'} back and draws again.', player: p);
    }
    s.phase = Phase.main;
    s.turn = 1;
    _startTurn();
  }

  void _concede(int seat) {
    pending = null;
    state.player(seat).lost = true;
    log('${state.player(seat).name} concedes.', player: seat, kind: 'lose');
    _checkWinner();
  }

  // -------------------------------------------------------------------------------------------
  // Turn structure (CR 3)
  // -------------------------------------------------------------------------------------------

  void _startTurn() {
    final s = state;
    final p = s.active;
    final pl = s.player(p);
    log('Turn ${s.turn}: ${pl.name}.', player: p, kind: 'turn');
    pl.inkedThisTurn = 0;
    pl.drawnThisTurn = 0;
    for (final q in s.players) {
      q.inkPutThisTurn = 0;
      q.actionsThisTurn = 0;
    }
    s.banishedInChallengeThisTurn = 0;
    _resetTurnRecords();
    s.banishedThisTurn = [];
    for (final q in s.players) {
      q.discardedThisTurn = 0;
      q.actionsThisTurn = 0;
      q.questsThisTurn = 0;
    }
    // Ready (CR 3.2.1): ready everything, end "until the start of your turn" effects.
    s.timed.removeWhere((t) => t.lasting == Lasting.untilYourNextTurn && t.controller == p && t.turn < s.turn);
    final cantReady = <CardId>{
      for (final t in s.timed)
        if (t.rule == Rule.cantReady && t.lasting == Lasting.theirNextTurn && t.turn < s.turn) ...?t.cards,
    };
    final readied = <CardId>[];
    for (final id in [...pl.play, ...pl.inkwell]) {
      final o = s.obj(id);
      if (!o.exerted) continue;
      if (cantReady.contains(id) || chars(id).rules.contains(Rule.cantReady) || _s3CantReady(id)) continue;
      o.exerted = false;
      if (o.zone == Place.play) readied.add(id);
    }
    s.version++;
    // "Whenever you ready this character" triggers in the Ready step too (CR 3.2.1.4).
    for (final id in readied) {
      _emit(_Ev(kind: _EvKind.readied, card: id, player: p));
    }
    _turnTriggers(start: true);
    // Set (CR 3.2.2): characters dry, locations give lore, the bag resolves.
    for (final id in pl.play) {
      s.obj(id).dry = true;
    }
    for (final id in pl.play) {
      final c = chars(id);
      if (c.type == CardType.location && c.lore > 0) {
        _gainLore(p, c.lore, source: id);
      }
    }
    _check();
    _resolveBag();
    if (s.over) return;
    // Draw (CR 3.2.3): the starting player skips their first draw.
    final skip = (s.turn == 1 && p == s.firstPlayer) || _skipsDraw(p);
    if (!skip) _draw(p);
    _check();
    _resolveBag();
  }

  bool _skipsDraw(int p) => _statics().any((e) => e.$2 is SkipDraw && e.$3 == p);

  void _endTurn() {
    final s = state;
    final p = s.active;
    // End-of-turn triggered abilities (CR 3.4.1.1), then "this turn" effects end (3.4.1.2).
    _turnTriggers(start: false);
    _resolveBag();
    if (s.over) return;
    _endTemporaryShifts(p);
    s.timed.removeWhere((t) => t.lasting == Lasting.thisTurn || (t.lasting == Lasting.theirNextTurn && t.turn < s.turn && _ownerOfAffected(t) == p));
    s.reductions.clear();
    s.lingering.removeWhere((l) => !l.delayedEnd);
    s.version++;
    _check();
    // A player whose turn ends with no cards in their deck loses (CR 1.8.1.2).
    if (s.player(p).deck.isEmpty && !s.player(p).lost) {
      s.player(p).lost = true;
      log('${s.player(p).name} ends their turn with no cards in their deck and loses.', player: p, kind: 'lose');
      _checkWinner();
      if (s.over) return;
    }
    var next = (p + 1) % s.players.length;
    while (s.player(next).lost) {
      next = (next + 1) % s.players.length;
    }
    s.active = next;
    s.turn++;
    s.bagTurn = null;
    _startTurn();
  }

  int? _ownerOfAffected(Timed t) {
    final ids = t.cards;
    if (ids == null || ids.isEmpty) return null;
    return state.objOrNull(ids.first)?.owner;
  }

  // -------------------------------------------------------------------------------------------
  // Game state check (CR 1.8)
  // -------------------------------------------------------------------------------------------

  void _check() {
    final s = state;
    for (var loop = 0; loop < 50 && !s.over; loop++) {
      var changed = false;
      for (var p = 0; p < s.players.length; p++) {
        if (s.player(p).lore >= loreToWin(p) && !s.player(p).lost) {
          s.winner = p;
          s.phase = Phase.over;
          log('${s.player(p).name} reaches ${s.player(p).lore} lore and wins!', player: p, kind: 'win');
          pending = null;
          return;
        }
      }
      // Banish characters and locations with damage at or over their willpower, together.
      final doomed = <CardId>[];
      for (final p in _turnOrder()) {
        for (final id in s.player(p).play) {
          final c = chars(id);
          if ((c.type == CardType.character || c.type == CardType.location) && s.obj(id).damage > 0 && s.obj(id).damage >= c.willpower) doomed.add(id);
        }
      }
      if (doomed.isNotEmpty) {
        for (final id in doomed) {
          _banish(id, byDamage: true);
        }
        changed = true;
      }
      if (!changed) break;
    }
  }

  void _checkWinner() {
    final s = state;
    final alive = [
      for (var p = 0; p < s.players.length; p++)
        if (!s.player(p).lost) p,
    ];
    if (alive.length == 1) {
      s.winner = alive.first;
      s.phase = Phase.over;
      log('${s.player(alive.first).name} wins.', player: alive.first, kind: 'win');
    } else if (alive.isEmpty) {
      s.phase = Phase.over;
    }
  }

  /// Players in turn order, starting with the active player.
  List<int> _turnOrder() => [for (var i = 0; i < state.players.length; i++) (state.active + i) % state.players.length];

  // -------------------------------------------------------------------------------------------
  // Zones (CR 7)
  // -------------------------------------------------------------------------------------------

  void _moveTo(CardId id, Place to, {bool bottom = false, bool exerted = false, bool setup = false}) {
    final s = state;
    final o = s.obj(id);
    final from = o.zone;
    final pl = s.player(o.owner);
    pl.zone(from).remove(id);
    // Leaving play: damage, states and gained effects go (CR 7.1.6); the stack goes along
    // (CR 5.1.1.7); characters at a location stay in play (CR 5.6.6).
    if (from == Place.play && to != Place.play) {
      for (final u in List.of(o.under)) {
        final uo = s.obj(u);
        uo.zone = Place.play;
        uo.under = [];
        _moveTo(u, to == Place.inkwell ? Place.discard : to, bottom: bottom);
      }
      o.under = [];
      for (final other in pl.play) {
        if (s.obj(other).at == id) s.obj(other).at = null;
      }
      for (final q in s.players) {
        for (final other in q.play) {
          if (s.obj(other).at == id) s.obj(other).at = null;
        }
      }
    }
    if (to == Place.discard && from != Place.discard) pl.discardedThisTurn++;
    o.zone = to;
    o.zcc++;
    o.temporaryShift = false;
    o.exerted = exerted;
    o.damage = 0;
    o.dry = false;
    o.at = null;
    o.faceDown = to == Place.inkwell || to == Place.deck;
    o.timestamp = s.nextTs++;
    o.enteredTurn = s.turn;
    final list = pl.zone(to);
    if (to == Place.deck && !bottom) {
      list.insert(0, id);
    } else {
      list.add(id);
    }
    s.version++;
    if (to == Place.inkwell && from != Place.inkwell && s.phase == Phase.main && !setup) _inked(o.owner, id);
  }

  bool _draw(int p, {bool quiet = false}) {
    final pl = state.player(p);
    if (pl.deck.isEmpty) return false;
    final id = pl.deck.first;
    _moveTo(id, Place.hand);
    pl.drawnThisTurn++;
    if (!quiet) {
      log('${pl.name} draws a card.', player: p, card: id, kind: 'draw');
      _emit(_Ev(kind: _EvKind.draw, player: p, amount: pl.drawnThisTurn));
    }
    return true;
  }

  void _gainLore(int p, int n, {CardId? source}) {
    if (n <= 0) return;
    state.player(p).lore += n;
    state.version++;
    log('${state.player(p).name} gains $n lore.', player: p, card: source, kind: 'lore', amount: n);
  }

  void _loseLore(int p, int n) {
    final pl = state.player(p);
    final lost = n.clamp(0, pl.lore);
    if (lost == 0) return;
    pl.lore -= lost;
    state.version++;
    log('${pl.name} loses $lost lore.', player: p, kind: 'lore', amount: -lost);
  }
}
