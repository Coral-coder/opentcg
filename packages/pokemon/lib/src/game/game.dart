/// The Pokémon TCG engine. A match is its seed plus its moves (tcg_core's contract): every
/// device that applies the same moves reaches the same state and fingerprint.
///
/// Rules follow the official rulebook's structure (sections cited by name: "Setting Up",
/// "Your Turn", "Attacking", "Special Conditions", "Pokémon Checkup", "Winning").
///
/// Decisions work like the other engines': a move runs as a task that may stop to ask a player
/// something ([NeedDecision]); the state before the move is kept, and each answer re-runs the
/// task from there with all answers so far.
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

part 'turn_actions.dart';
part 'effects.dart';
part 'query.dart';
part 'testing.dart';

class NeedDecision implements Exception {
  NeedDecision(this.decision);
  final Decision decision;
}

class Pending {
  Pending(this.move, this.answers, this.decision, this.snapshot);
  final PMove move;
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

  final PCardDb db;
  GameState state;
  Pending? pending;
  final List<PMove> actions = [];

  /// Legality probes answer every question with the default answer.
  bool _probe = false;
  List<List<int>> _answers = const [];
  int _answerIndex = 0;

  @override
  List<PMove> get moves => actions;

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

  PCard card(CardId id) => db[state.obj(id).card]!;
  ParsedCard parsed(CardId id) => PokemonParser.parse(card(id));
  String nameOf(CardId id) => card(id).name;

  // -------------------------------------------------------------------------------------------
  // Applying moves
  // -------------------------------------------------------------------------------------------

  @override
  void apply(covariant PMove move) {
    if (state.over) throw PokemonError('The game is over');
    if (move is ConcedeMove) {
      pending = null;
      state.player(move.seat).lost = true;
      log('${state.player(move.seat).name} concedes.', player: move.seat, kind: 'lose');
      _decideWinner();
      actions.add(move);
      return;
    }
    final p = pending;
    if (p != null) {
      if (move is! AnswerMove) throw PokemonError('Waiting for ${state.player(p.decision.player).name}: ${p.decision.prompt}');
      if (move.seat != p.decision.player) throw PokemonError('That decision belongs to ${state.player(p.decision.player).name}');
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
    if (move is AnswerMove) throw PokemonError('Nothing to answer');
    if (move is StartMove) {
      if (state.phase != Phase.setup || actions.isNotEmpty) throw PokemonError('Already started');
    } else {
      if (state.phase != Phase.main) throw PokemonError('The game hasn’t started');
      if (move.seat != state.active) throw PokemonError('It’s ${state.player(state.active).name}’s turn');
    }
    _run(move, const [], state.clone());
    actions.add(move);
  }

  void _run(PMove move, List<List<int>> answers, GameState snapshot) {
    final before = state;
    state = snapshot.clone();
    _answers = answers;
    _answerIndex = 0;
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
        if (a.length < d.min || a.length > d.max) throw PokemonError('Choose ${d.min == d.max ? d.min : '${d.min}–${d.max}'}');
        if (a.toSet().length != a.length || !a.every(d.options.contains)) throw PokemonError('Not one of the choices');
      case DecisionKind.yesNo:
        if (a.length != 1 || (a[0] != 0 && a[0] != 1)) throw PokemonError('Yes or no');
      case DecisionKind.option:
        if (a.length != 1 || a[0] < 0 || a[0] >= d.labels.length) throw PokemonError('Pick one of the options');
    }
  }

  /// Asks the question, or returns the answer already given when the task is re-run. A choice
  /// with only one possible answer isn't asked.
  List<int> ask(Decision d) {
    if (d.kind == DecisionKind.cards && d.min == d.max && d.options.length == d.min) return List.of(d.options);
    if (d.kind == DecisionKind.cards && d.max == 0) return const [];
    if (_probe) return defaultAnswer(d);
    if (_answerIndex < _answers.length) return _answers[_answerIndex++];
    throw NeedDecision(d);
  }

  bool askYesNo(int player, String prompt, {CardId? source}) => ask(Decision(kind: DecisionKind.yesNo, player: player, prompt: prompt, source: source)).first == 1;

  void _exec(PMove move) {
    switch (move) {
      case StartMove():
        _start(move);
      case PlayBasicMove():
        _playBasic(move.seat, move.card);
      case EvolveMove():
        _evolve(move.seat, move.card, move.target);
      case AttachEnergyMove():
        _attachEnergy(move.seat, move.card, move.target);
      case TrainerMove():
        _trainer(move.seat, move.card, move.target);
      case RetreatMove():
        _retreat(move.seat, move.to);
      case AbilityMove():
        _ability(move.seat, move.card, move.index);
      case AttackMove():
        _attack(move.seat, move.index);
      case EndTurnMove():
        _endTurn();
      case AnswerMove() || ConcedeMove():
        break;
    }
  }

  void log(String text, {int? player, CardId? card, String kind = 'info', int amount = 0}) {
    state.log.add(LogEntry(text, player: player, card: card, kind: kind, amount: amount));
  }

  /// One coin flip from the match's generator (rulebook: "Flipping Coins").
  bool flip(int player, {String why = ''}) {
    final heads = state.rng.nextInt(2) == 0;
    log('${state.player(player).name} flips a coin${why.isEmpty ? '' : ' ($why)'}: ${heads ? 'heads' : 'tails'}.', player: player, kind: 'coin', amount: heads ? 1 : 0);
    return heads;
  }

  // -------------------------------------------------------------------------------------------
  // Setting Up
  // -------------------------------------------------------------------------------------------

  void _start(StartMove m) {
    final s = state;
    if (m.decks.length != s.players.length) throw PokemonError('One deck per player');
    for (var p = 0; p < s.players.length; p++) {
      var basics = 0;
      for (final key in m.decks[p]) {
        final c = db[key];
        if (c == null) throw PokemonError('Unknown card $key');
        if (c.isBasicPokemon) basics++;
        final o = Obj(id: s.nextId++, card: c.key, owner: p, zone: Place.deck);
        s.objects[o.id] = o;
        s.player(p).deck.add(o.id);
      }
      if (basics == 0) throw PokemonError('${s.player(p).name}’s deck has no Basic Pokémon');
      s.rng.shuffle(s.player(p).deck);
    }
    // Coin flip: the winner chooses who goes first.
    if (m.firstPlayer != null) {
      s.firstPlayer = m.firstPlayer!;
    } else {
      final winner = s.rng.nextInt(2);
      log('${s.player(winner).name} wins the coin flip.', player: winner, kind: 'coin');
      final choice = ask(Decision(kind: DecisionKind.option, player: winner, prompt: 'You won the coin flip: go first or second?', labels: const ['Go first', 'Go second'])).first;
      s.firstPlayer = choice == 0 ? winner : 1 - winner;
    }
    s.active = s.firstPlayer;
    log('${s.player(s.firstPlayer).name} goes first.', player: s.firstPlayer, kind: 'turn');
    // Opening hands; a hand without a Basic Pokémon is shown and shuffled back (mulligan).
    for (var p = 0; p < s.players.length; p++) {
      final pl = s.player(p);
      for (var tries = 0; tries < 60; tries++) {
        for (var i = 0; i < 7; i++) {
          _draw(p, quiet: true);
        }
        if (pl.hand.any((id) => card(id).isBasicPokemon)) break;
        pl.mulligans++;
        log('${pl.name} has no Basic Pokémon: mulligan.', player: p);
        for (final id in List.of(pl.hand)) {
          _moveTo(id, Place.deck);
        }
        s.rng.shuffle(pl.deck);
      }
    }
    // Active and Bench, face down; then 6 Prize cards each.
    for (var i = 0; i < s.players.length; i++) {
      final p = (s.firstPlayer + i) % s.players.length;
      final pl = s.player(p);
      final basics = [for (final id in pl.hand) if (card(id).isBasicPokemon) id];
      final active = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose your Active Pokémon', options: basics)).first;
      _putIntoPlay(active, p, Place.active);
      final rest = [for (final id in pl.hand) if (card(id).isBasicPokemon) id];
      final bench = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Put up to 5 Basic Pokémon on your Bench', options: rest, min: 0, max: rest.length < 5 ? rest.length : 5));
      for (final id in bench) {
        _putIntoPlay(id, p, Place.bench);
      }
    }
    for (var p = 0; p < s.players.length; p++) {
      for (var i = 0; i < 6 && s.player(p).deck.isNotEmpty; i++) {
        _moveTo(s.player(p).deck.first, Place.prize);
      }
    }
    // A player may draw a card for each extra mulligan the opponent took.
    for (var i = 0; i < s.players.length; i++) {
      final p = (s.firstPlayer + i) % s.players.length;
      final extra = s.player(s.opponent(p)).mulligans - s.player(p).mulligans;
      if (extra <= 0) continue;
      final n = ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Your opponent took $extra more mulligan${extra == 1 ? '' : 's'}: draw extra cards?', labels: [for (var k = 0; k <= extra; k++) 'Draw $k'])).first;
      for (var k = 0; k < n; k++) {
        _draw(p);
      }
    }
    for (final pl in s.players) {
      log('${pl.name} reveals ${nameOf(pl.active!)}${pl.bench.isEmpty ? '' : ' and ${pl.bench.length} on the Bench'}.', kind: 'play');
    }
    s.phase = Phase.main;
    s.turn = 1;
    _startTurn();
  }

  // -------------------------------------------------------------------------------------------
  // Turns
  // -------------------------------------------------------------------------------------------

  /// Whether it's [p]'s first turn (no evolving; the player going first also can't attack or
  /// play a Supporter).
  bool isFirstTurn(int p) => p == state.firstPlayer ? state.turn == 1 : state.turn == 2;

  void _startTurn() {
    final s = state;
    final p = s.active;
    final pl = s.player(p);
    pl.energyAttached = false;
    pl.supporterPlayed = false;
    pl.stadiumPlayed = false;
    pl.retreated = false;
    log('Turn ${s.turn}: ${pl.name}.', player: p, kind: 'turn');
    // Draw a card; a player who can't loses (rulebook: "Winning").
    if (pl.deck.isEmpty) {
      pl.lost = true;
      log('${pl.name} can’t draw a card at the start of the turn and loses.', player: p, kind: 'lose');
      _decideWinner();
      return;
    }
    _draw(p);
    s.version++;
  }

  void _endTurn() {
    final s = state;
    final p = s.active;
    log('${s.player(p).name} ends the turn.', player: p);
    _checkup();
    if (s.over) return;
    // Lasting effects that end with this turn.
    s.timed.removeWhere((t) => t.until <= s.turn);
    s.active = s.opponent(p);
    s.turn++;
    _startTurn();
  }

  /// Pokémon Checkup, between turns: Poisoned, Burned, Asleep, Paralyzed; then Knock Outs.
  void _checkup() {
    final s = state;
    for (final p in _turnOrder()) {
      final id = s.player(p).active;
      if (id == null) continue;
      final o = s.obj(id);
      if (o.conds.contains(Cond.poisoned)) {
        o.damage += 10;
        log('${nameOf(id)} is Poisoned: 1 damage counter.', player: p, card: id, kind: 'damage', amount: 10);
      }
      if (o.conds.contains(Cond.burned)) {
        o.damage += 20;
        log('${nameOf(id)} is Burned: 2 damage counters.', player: p, card: id, kind: 'damage', amount: 20);
        if (flip(p, why: 'Burned')) {
          o.conds.remove(Cond.burned);
          log('${nameOf(id)} is no longer Burned.', player: p, card: id, kind: 'condition');
        }
      }
      if (o.conds.contains(Cond.asleep) && flip(p, why: 'Asleep')) {
        o.conds.remove(Cond.asleep);
        log('${nameOf(id)} wakes up.', player: p, card: id, kind: 'condition');
      }
      // Paralyzed recovers after its owner's next turn.
      if (o.conds.contains(Cond.paralyzed) && s.active == p && o.paralyzedTurn < s.turn) {
        o.conds.remove(Cond.paralyzed);
        log('${nameOf(id)} is no longer Paralyzed.', player: p, card: id, kind: 'condition');
      }
    }
    s.version++;
    _knockOuts();
  }

  List<int> _turnOrder() => [for (var i = 0; i < state.players.length; i++) (state.active + i) % state.players.length];

  // -------------------------------------------------------------------------------------------
  // Knock Outs, Prize cards, winning
  // -------------------------------------------------------------------------------------------

  int maxHp(CardId id) {
    var hp = card(id).hp;
    final tool = state.obj(id).tool;
    if (tool != null) {
      final t = parsed(tool).tool;
      if (t is ToolHp) hp += t.n;
    }
    return hp;
  }

  /// Knocks Out every Pokémon with damage at or over its HP; the opponents take Prize cards;
  /// players with no Active Pokémon promote one from the Bench; checks who wins.
  void _knockOuts() {
    final s = state;
    for (var loop = 0; loop < 20 && !s.over; loop++) {
      final ko = <CardId>[
        for (final p in _turnOrder())
          for (final id in s.player(p).inPlay)
            if (s.obj(id).damage >= maxHp(id)) id,
      ];
      if (ko.isEmpty) break;
      for (final id in ko) {
        final owner = s.obj(id).owner;
        final taker = s.opponent(owner);
        final value = card(id).prizeValue;
        log('${nameOf(id)} is Knocked Out.', player: owner, card: id, kind: 'ko');
        _discardStack(id);
        final tp = s.player(taker);
        var took = 0;
        for (var i = 0; i < value && tp.prizes.isNotEmpty; i++) {
          _moveTo(tp.prizes.first, Place.hand);
          took++;
        }
        if (took > 0) log('${tp.name} takes $took Prize card${took == 1 ? '' : 's'}.', player: taker, kind: 'prize', amount: took);
      }
      _decideWinner();
      if (s.over) return;
      // A player without an Active Pokémon promotes one; the player not taking the turn first.
      for (final p in _turnOrder().reversed) {
        final pl = s.player(p);
        if (pl.active == null && pl.bench.isNotEmpty) {
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose your new Active Pokémon', options: List.of(pl.bench))).first;
          pl.bench.remove(pick);
          pl.active = pick;
          s.obj(pick).zone = Place.active;
          log('${pl.name} sends out ${nameOf(pick)}.', player: p, card: pick, kind: 'play');
        }
      }
    }
  }

  /// Rulebook "Winning": all Prize cards taken, or the opponent has no Pokémon in play (or
  /// can't draw, checked at the start of a turn). Both at once: a draw (Sudden Death isn't
  /// played).
  void _decideWinner() {
    final s = state;
    final wins = <int>{};
    for (var p = 0; p < s.players.length; p++) {
      final pl = s.player(p);
      if (pl.lost) continue;
      if (pl.prizes.isEmpty && s.phase == Phase.main) wins.add(p);
      final opp = s.player(s.opponent(p));
      if (s.phase == Phase.main && (opp.lost || opp.inPlay.isEmpty)) wins.add(p);
    }
    if (wins.isEmpty) return;
    pending = null;
    s.phase = Phase.over;
    if (wins.length == 1) {
      s.winner = wins.first;
      log('${s.player(wins.first).name} wins!', player: wins.first, kind: 'win');
    } else {
      log('Both players win at the same time: the game is a draw.', kind: 'info');
    }
  }

  // -------------------------------------------------------------------------------------------
  // Zones
  // -------------------------------------------------------------------------------------------

  List<CardId> _zone(Player pl, Place z) => switch (z) {
        Place.deck => pl.deck,
        Place.hand => pl.hand,
        Place.discard => pl.discard,
        Place.prize => pl.prizes,
        Place.bench => pl.bench,
        _ => <CardId>[],
      };

  /// Moves a card between a player's zones (not for Pokémon in play; see [_discardStack]).
  void _moveTo(CardId id, Place to, {bool bottom = false}) {
    final s = state;
    final o = s.obj(id);
    final pl = s.player(o.owner);
    _detach(id);
    o.zone = to;
    o.host = null;
    o.damage = 0;
    o.conds = [];
    o.energy = [];
    o.tool = null;
    o.under = [];
    final list = _zone(pl, to);
    if (to == Place.deck && !bottom) {
      list.insert(0, id);
    } else {
      list.add(id);
    }
    s.version++;
  }

  /// Takes a card out of wherever it is now.
  void _detach(CardId id) {
    final s = state;
    final o = s.obj(id);
    final pl = s.player(o.owner);
    switch (o.zone) {
      case Place.active:
        if (pl.active == id) pl.active = null;
      case Place.attached:
        final h = o.host;
        if (h != null) {
          final ho = s.obj(h);
          ho.energy.remove(id);
          if (ho.tool == id) ho.tool = null;
        }
      case Place.under:
        final h = o.host;
        if (h != null) s.obj(h).under.remove(id);
      case Place.stadium:
        if (s.stadium == id) s.stadium = null;
      default:
        _zone(pl, o.zone).remove(id);
    }
  }

  void _putIntoPlay(CardId id, int p, Place where) {
    final s = state;
    _detach(id);
    final o = s.obj(id);
    o.zone = where;
    o.playedTurn = s.turn;
    if (where == Place.active) {
      s.player(p).active = id;
    } else {
      s.player(p).bench.add(id);
    }
    s.version++;
  }

  /// A Pokémon leaving play goes to its owner's discard pile with everything attached and the
  /// cards under it.
  void _discardStack(CardId id) {
    final s = state;
    final o = s.obj(id);
    final pl = s.player(o.owner);
    final parts = [...o.under, ...o.energy, ?o.tool];
    if (pl.active == id) pl.active = null;
    pl.bench.remove(id);
    s.timed.removeWhere((t) => t.target == id);
    for (final c in parts) {
      final co = s.obj(c);
      co.zone = Place.discard;
      co.host = null;
      s.player(co.owner).discard.add(c);
    }
    o
      ..zone = Place.discard
      ..damage = 0
      ..conds = []
      ..energy = []
      ..tool = null
      ..under = [];
    pl.discard.add(id);
    s.version++;
  }

  bool _draw(int p, {bool quiet = false}) {
    final pl = state.player(p);
    if (pl.deck.isEmpty) return false;
    final id = pl.deck.first;
    _moveTo(id, Place.hand);
    if (!quiet) log('${pl.name} draws a card.', player: p, card: id, kind: 'draw');
    return true;
  }

  void _attach(CardId cardId, CardId target) {
    final s = state;
    _detach(cardId);
    final o = s.obj(cardId);
    o.zone = Place.attached;
    o.host = target;
    if (card(cardId).isEnergy) {
      s.obj(target).energy.add(cardId);
    } else {
      s.obj(target).tool = cardId;
    }
    s.version++;
  }
}
