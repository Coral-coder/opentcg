import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:riftbound/riftbound.dart';
import 'package:tcg_app/tcg_app.dart';
import 'package:tcg_core/tcg_core.dart';

/// Wire version of the room protocol; peers with another refuse to play.
const roomProtocolVersion = 1;

/// A seat at an online table: a person (by device id) or a computer the host runs.
class RoomSeat {
  const RoomSeat({required this.id, required this.name, required this.deck, this.bot = false});
  final String id, name;
  final List<String> deck;
  final bool bot;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'bot': bot};
}

/// Online Riftbound for 2–4 seats (Skirmish, War, Magma Chamber) over any broadcast [Transport]
/// (public Nostr relays with a room code). Every device runs the same deterministic engine.
///
/// The host keeps the order: it seats people as they join (computers fill the rest when it
/// starts), deals, and is the only one that applies moves. A guest sends its move to the host and
/// applies it when the host broadcasts it back, numbered, with the game's fingerprint after it, so
/// every device plays the same moves in the same order and checks it reached the same position.
/// The host also runs the computers. A device that falls behind (or reloads) asks for the moves
/// it's missing; relays keep the room's history, so a game can be picked up later.
///
/// Messages (JSON, all with g, rv, ev and sender):
/// - join {name, deck}: a guest asks for a seat (repeated until it's seated).
/// - lobby {mode, seats, started}: the host's seating.
/// - start {setup}: the deal (seed, names, decks, ids, rules, bots).
/// - move {seq, a, by}: a guest's move for the host.
/// - act {seq, a, by, d}: a move in the game, as the host applied it.
/// - reject {to, msg}: the host refused a guest's move.
/// - need {from}: send me the start and the moves from [from] on.
class RiftboundRoom {
  RiftboundRoom({
    required this.transport,
    required this.ruleset,
    required this.localId,
    required this.localName,
    required this.localDeck,
    required this.isHost,
    RMode mode = RMode.ffa4,
    this.archive,
    this.key,
    this.botDeck,
    this.botDelay = const Duration(milliseconds: 700),
    // A named parameter can't be private; the mode can change in the lobby.
    // ignore: prefer_initializing_formals
  }) : _mode = mode {
    if (isHost) seats.add(RoomSeat(id: localId, name: localName, deck: localDeck));
    _sub = transport.messages.listen(_onMessage, onError: (_) {});
    _stateSub = transport.stateChanges.listen((s) {
      if (s == LinkState.connected) _hello();
    });
    _restore();
  }

  final Transport transport;
  final RiftboundRuleset ruleset;
  final String localId, localName;
  final List<String> localDeck;
  final bool isHost;
  final MatchArchive? archive;

  /// Where this device saves the game (`room:<code>`).
  final String? key;

  /// The deck the host gives a computer in [seat], given the seats so far.
  final List<String> Function(int seat, List<RoomSeat> seats)? botDeck;
  final Duration botDelay;

  RMode _mode;
  RMode get mode => _mode;
  final List<RoomSeat> seats = [];
  Map<String, dynamic>? setup;
  Game? game;
  final List<RMove> actions = [];
  final List<String?> digests = [];
  final List<int> by = [];
  String? error;
  bool desynced = false;

  /// What the last event means, in words, for the lobby or the table.
  String? notice;

  final _events = StreamController<String>.broadcast(); // lobby, start, action, error, desync
  Stream<String> get events => _events.stream;
  late final StreamSubscription<String> _sub;
  late final StreamSubscription<LinkState> _stateSub;
  final Set<String> _seen = {};
  final Map<int, Map<String, dynamic>> _buffered = {};
  final Map<int, RiftboundBot> _bots = {};
  Timer? _joinTimer, _botTimer, _needTimer, _lobbyTimer;
  bool _disposed = false;

  /// This device's seat, or -1 before it's seated.
  int get localSeat => seats.indexWhere((s) => s.id == localId);
  bool get started => game != null;
  bool get seated => localSeat >= 0;

  // -------------------------------------------------------------------------------------------
  // Lobby
  // -------------------------------------------------------------------------------------------

  void _hello() {
    if (isHost) {
      _sendLobby();
    } else if (!started) {
      _requestSeat();
    } else {
      _send({'t': 'need', 'from': actions.length});
    }
  }

  /// Guests ask for a seat until the host seats them (relays may drop a message).
  void _requestSeat() {
    _send({'t': 'join', 'name': localName, 'deck': localDeck});
    _joinTimer?.cancel();
    _joinTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (seated || started || _disposed) {
        _joinTimer?.cancel();
        return;
      }
      _send({'t': 'join', 'name': localName, 'deck': localDeck});
    });
  }

  /// Opens the room: the host announces it, a guest asks for a seat.
  void begin() => _hello();

  /// The host changes the mode before starting (the seats beyond its player count are dropped).
  void setMode(RMode m) {
    if (!isHost || started) return;
    _mode = m;
    while (seats.length > m.players) {
      seats.removeLast();
    }
    _sendLobby();
    _events.add('lobby');
  }

  /// The host adds a computer to the next empty seat.
  void addBot() {
    if (!isHost || started || seats.length >= mode.players) return;
    final deck = botDeck?.call(seats.length, seats) ?? localDeck;
    seats.add(RoomSeat(id: 'bot${seats.length}', name: 'Computer ${seats.where((s) => s.bot).length + 1}', deck: deck, bot: true));
    _sendLobby();
    _events.add('lobby');
  }

  /// The host frees a seat (not its own).
  void removeSeat(int i) {
    if (!isHost || started || i <= 0 || i >= seats.length) return;
    seats.removeAt(i);
    _sendLobby();
    _events.add('lobby');
  }

  /// Why the host can't start yet, or null.
  String? get startProblem {
    if (!isHost) return 'Only the host starts the game';
    if (started) return 'Already started';
    // Teammates may not play the same Champion Legend (CR 491.8.h).
    if (mode == RMode.teams) {
      final filled = _filledSeats();
      for (var p = 0; p + 2 < filled.length; p++) {
        final a = deckLegend(ruleset.db, filled[p].deck)?.name, b = deckLegend(ruleset.db, filled[p + 2].deck)?.name;
        if (a != null && a == b) return '${filled[p].name} and ${filled[p + 2].name} are teammates with the same legend ($a); one should pick another';
      }
    }
    return null;
  }

  List<RoomSeat> _filledSeats() {
    final out = List.of(seats);
    while (out.length < mode.players) {
      final deck = botDeck?.call(out.length, out) ?? localDeck;
      out.add(RoomSeat(id: 'bot${out.length}', name: 'Computer ${out.where((s) => s.bot).length + 1}', deck: deck, bot: true));
    }
    return out;
  }

  /// The host deals: empty seats become computers.
  void start() {
    if (startProblem != null) throw TcgError(startProblem!);
    final filled = _filledSeats();
    seats
      ..clear()
      ..addAll(filled);
    final s = <String, dynamic>{
      'seed': Random.secure().nextInt(1 << 30),
      'names': [for (final x in filled) x.name],
      'decks': [for (final x in filled) x.deck],
      'ids': [for (final x in filled) x.id],
      'bots': [for (var i = 0; i < filled.length; i++) if (filled[i].bot) i],
      'rules': {'mode': mode.id},
    };
    _load(s, const [], const []);
    _hostApply(ruleset.deal([for (final x in filled) x.deck], {'mode': mode.id}), -1);
    _send({'t': 'start', 'setup': s});
    _sendLobby();
    _events.add('start');
  }

  void _sendLobby() {
    if (!isHost) return;
    _send({'t': 'lobby', 'mode': mode.id, 'seats': [for (final s in seats) s.toJson()], 'started': started});
  }

  // -------------------------------------------------------------------------------------------
  // Playing
  // -------------------------------------------------------------------------------------------

  /// A move by the local player: the host applies it; a guest sends it to the host and applies
  /// it when the host broadcasts it back.
  void perform(TcgMove move) {
    final g = game;
    if (g == null) throw TcgError('The game hasn’t started');
    if (move.seat != localSeat && move.seat >= 0) throw TcgError('That move belongs to another player');
    if (isHost) {
      _hostApply(move as RMove, localSeat);
    } else {
      // Checked here first, so an illegal move doesn't make a round trip (answers are checked by
      // the host).
      if (move is! AnswerMove) {
        final why = g.whyNot(move as RMove);
        if (why != null) throw TcgError(why);
      }
      _send({'t': 'move', 'seq': actions.length, 'a': move.toJson(), 'by': localSeat});
      notice = 'Sent to ${seats.isEmpty ? 'the host' : seats.first.name}…';
      _events.add('sent');
    }
  }

  /// Host: applies [move] by seat [seat] (-1 for the deal), records and broadcasts it.
  void _hostApply(RMove move, int seat) {
    final g = game!;
    g.apply(move);
    _record(move, seat, g.fingerprint);
    _send(_actMessage(actions.length - 1));
    _save();
    notice = null;
    _events.add('action');
    _scheduleBots();
  }

  void _record(RMove move, int seat, String? digest) {
    actions.add(move);
    by.add(seat);
    digests.add(digest);
  }

  Map<String, dynamic> _actMessage(int i) => {'t': 'act', 'seq': i, 'a': actions[i].toJson(), 'by': by[i], 'd': digests[i]};

  /// Host: the computers in their seats move, one at a time, at a readable pace.
  void _scheduleBots() {
    if (!isHost || _disposed) return;
    final g = game;
    if (g == null || g.over) return;
    final p = g.toAct;
    if (p == null || !_bots.containsKey(p)) return;
    _botTimer?.cancel();
    _botTimer = Timer(botDelay, () {
      if (_disposed || game == null || game!.over) return;
      final q = game!.toAct;
      if (q == null || !_bots.containsKey(q)) return;
      final before = game!.actions.length;
      try {
        _bots[q]!.step(game!);
      } catch (_) {
        return;
      }
      final after = game!.actions.length;
      for (var i = before; i < after; i++) {
        _record(game!.actions[i], q, i == after - 1 ? game!.fingerprint : null);
        _send(_actMessage(actions.length - 1));
      }
      if (after > before) {
        _save();
        _events.add('action');
      }
      _scheduleBots();
    });
  }

  // -------------------------------------------------------------------------------------------
  // Messages
  // -------------------------------------------------------------------------------------------

  void _send(Map<String, dynamic> m) {
    if (_disposed) return;
    transport.send(jsonEncode({...m, 'g': ruleset.id, 'rv': roomProtocolVersion, 'ev': ruleset.engineVersion, 'sender': localId}));
  }

  void _onMessage(String raw) {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final mid = m['mid'] as String?;
    if (mid != null && !_seen.add(mid)) return;
    if (m['sender'] == localId) return;
    if (m['g'] != ruleset.id) return;
    if (m['rv'] != roomProtocolVersion || m['ev'] != ruleset.engineVersion) {
      if (!started) _fail('Another device in this room runs a different version (${m['rv']}/${m['ev']}, this one $roomProtocolVersion/${ruleset.engineVersion}). Reload both.');
      return;
    }
    final from = m['sender'] as String? ?? '';
    switch (m['t']) {
      case 'join':
        if (isHost) _onJoin(from, m);
      case 'lobby':
        if (!isHost) _onLobby(m);
      case 'start':
        if (!isHost) _onStart(m);
      case 'move':
        if (isHost) _onGuestMove(from, m);
      case 'act':
        if (!isHost) _onAct(m);
      case 'reject':
        if (m['to'] == localId) {
          notice = m['msg'] as String?;
          _events.add('reject');
        }
      case 'need':
        if (isHost) _onNeed(from, m);
    }
  }

  void _onJoin(String id, Map<String, dynamic> m) {
    final i = seats.indexWhere((s) => s.id == id);
    if (started) {
      // A seated player reconnecting gets the game; anyone else is told it's full.
      if (i >= 0) {
        _send({'t': 'start', 'setup': setup});
        for (var k = 0; k < actions.length; k++) {
          _send(_actMessage(k));
        }
      }
      _sendLobby();
      return;
    }
    if (i < 0) {
      if (seats.length >= mode.players) {
        _sendLobby();
        return;
      }
      seats.add(RoomSeat(id: id, name: (m['name'] as String?) ?? 'Player', deck: ((m['deck'] as List?) ?? const []).cast<String>()));
      _events.add('lobby');
    }
    _lobbyTimer?.cancel();
    _lobbyTimer = Timer(const Duration(milliseconds: 200), _sendLobby);
  }

  void _onLobby(Map<String, dynamic> m) {
    _mode = RMode.fromId(m['mode'] as String?);
    seats
      ..clear()
      ..addAll([
        for (final s in (m['seats'] as List).cast<Map<String, dynamic>>())
          RoomSeat(id: s['id'] as String, name: s['name'] as String, deck: const [], bot: s['bot'] as bool? ?? false),
      ]);
    if (m['started'] == true && !started) {
      if (!seated) {
        _fail('This game started without you: every seat was taken.');
        return;
      }
      _send({'t': 'need', 'from': 0});
    }
    if (!started && !seated && seats.length >= mode.players) notice = 'The room is full.';
    _events.add('lobby');
  }

  void _onStart(Map<String, dynamic> m) {
    if (started) return;
    final s = (m['setup'] as Map).cast<String, dynamic>();
    if (!(s['ids'] as List).contains(localId)) {
      _fail('This game started without you: every seat was taken.');
      return;
    }
    _load(s, const [], const []);
    _flush();
    _events.add('start');
    _send({'t': 'need', 'from': actions.length});
  }

  void _onGuestMove(String from, Map<String, dynamic> m) {
    final g = game;
    if (g == null) return;
    final seat = seats.indexWhere((s) => s.id == from);
    final seq = m['seq'] as int;
    if (seat < 0 || m['by'] != seat) return;
    if (seq < actions.length) return; // already handled, or made from an older position
    if (seq > actions.length) return;
    try {
      final move = ruleset.moveFromJson((m['a'] as Map).cast<String, dynamic>());
      if (move.seat != seat) throw TcgError('A move for another seat');
      _hostApply(move, seat);
    } on TcgError catch (e) {
      _send({'t': 'reject', 'to': from, 'msg': e.message});
    } catch (e) {
      _send({'t': 'reject', 'to': from, 'msg': '$e'});
    }
  }

  void _onNeed(String from, Map<String, dynamic> m) {
    if (!started || !seats.any((s) => s.id == from)) return;
    final f = (m['from'] as int?) ?? 0;
    if (f <= 0) _send({'t': 'start', 'setup': setup});
    for (var k = max(0, f); k < actions.length; k++) {
      _send(_actMessage(k));
    }
  }

  void _onAct(Map<String, dynamic> m) {
    final seq = m['seq'] as int;
    if (seq < actions.length) return;
    _buffered[seq] = m;
    _flush();
    if (_buffered.isNotEmpty) {
      _needTimer?.cancel();
      _needTimer = Timer(const Duration(seconds: 2), () => _send({'t': 'need', 'from': actions.length}));
    }
  }

  /// Applies the host's moves in order, checking each fingerprint.
  void _flush() {
    final g = game;
    if (g == null || desynced) return;
    var applied = false;
    while (_buffered.containsKey(actions.length)) {
      final m = _buffered.remove(actions.length)!;
      final move = ruleset.moveFromJson((m['a'] as Map).cast<String, dynamic>());
      try {
        g.apply(move);
      } catch (e) {
        _desync('The host’s move ${actions.length} doesn’t apply here: $e');
        return;
      }
      final d = m['d'] as String?;
      final mine = g.fingerprint;
      _record(move, m['by'] as int? ?? -1, mine);
      applied = true;
      if (d != null && d != mine) {
        _desync('This device worked out move ${actions.length - 1} differently from the host. Make sure everyone runs the latest version.');
        return;
      }
    }
    if (applied) {
      notice = null;
      _save();
      _events.add('action');
    }
  }

  // -------------------------------------------------------------------------------------------
  // Loading and saving
  // -------------------------------------------------------------------------------------------

  /// Deals the game [s] describes and replays [moves].
  void _load(Map<String, dynamic> s, List<RMove> moves, List<int> movers) {
    setup = s;
    _mode = RMode.fromId((s['rules'] as Map?)?['mode'] as String?);
    final names = (s['names'] as List).cast<String>();
    final ids = (s['ids'] as List).cast<String>();
    final bots = ((s['bots'] as List?) ?? const []).cast<int>();
    seats
      ..clear()
      ..addAll([for (var i = 0; i < ids.length; i++) RoomSeat(id: ids[i], name: names[i], deck: const [], bot: bots.contains(i))]);
    final g = Game(ruleset.db, players: names, seed: s['seed'] as int);
    actions.clear();
    digests.clear();
    by.clear();
    for (var i = 0; i < moves.length; i++) {
      g.apply(moves[i]);
      _record(moves[i], i < movers.length ? movers[i] : -1, g.fingerprint);
    }
    game = g;
    _bots.clear();
    if (isHost) {
      for (final b in bots) {
        _bots[b] = RiftboundBot(b, seed: (s['seed'] as int) + b);
      }
    }
  }

  void _restore() {
    final k = key, a = archive;
    if (k == null || a == null) return;
    final log = a.load(k);
    if (log == null) return;
    try {
      final s = (log['setup'] as Map).cast<String, dynamic>();
      if (!(s['ids'] as List).contains(localId)) return;
      final moves = [for (final j in log['moves'] as List) ruleset.moveFromJson((j as Map).cast<String, dynamic>())];
      // The deal is the first move.
      _load(s, moves, (log['by'] as List).cast<int>());
      if (game!.over) {
        game = null;
        setup = null;
        actions.clear();
        digests.clear();
        by.clear();
      } else if (isHost) {
        _scheduleBots();
      }
    } catch (_) {
      game = null;
    }
  }

  void _save() {
    final k = key, a = archive, s = setup;
    if (k == null || a == null || s == null) return;
    a.save(k, {'setup': s, 'moves': [for (final m in actions) m.toJson()], 'by': by, 'date': DateTime.now().toIso8601String()});
  }

  void _fail(String message) {
    error = message;
    _events.add('error');
  }

  void _desync(String message) {
    desynced = true;
    error = message;
    _events.add('desync');
  }

  Future<void> dispose() async {
    _disposed = true;
    _joinTimer?.cancel();
    _botTimer?.cancel();
    _needTimer?.cancel();
    _lobbyTimer?.cancel();
    await _sub.cancel();
    await _stateSub.cancel();
    await transport.close();
    await _events.close();
  }
}
