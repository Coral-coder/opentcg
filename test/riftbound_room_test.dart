// Online Riftbound for more than two seats (lib/riftbound/riftbound_room.dart): a host and two
// guests on an in-memory broadcast channel play a whole War game (one seat a computer), and
// every device ends on the same fingerprint.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentcg/riftbound/riftbound_room.dart';
import 'package:riftbound/riftbound.dart';
import 'package:tcg_app/tcg_app.dart';
import 'package:tcg_core/tcg_core.dart';

/// Everyone on the channel hears every message but their own, with a message id (like relays).
class Hub {
  final List<HubTransport> members = [];
  var _n = 0;
  HubTransport join() {
    final t = HubTransport(this);
    members.add(t);
    return t;
  }

  void post(HubTransport from, String m) {
    final j = jsonDecode(m) as Map<String, dynamic>;
    j['mid'] = 'm${_n++}';
    final out = jsonEncode(j);
    for (final t in members) {
      if (t != from && t.state == LinkState.connected) scheduleMicrotask(() => t._in.add(out));
    }
  }
}

class HubTransport implements Transport {
  HubTransport(this.hub);
  final Hub hub;
  final _in = StreamController<String>.broadcast();
  final _state = StreamController<LinkState>.broadcast();
  LinkState _current = LinkState.connected;
  @override
  LinkKind get kind => LinkKind.relay;
  @override
  Stream<String> get messages => _in.stream;
  @override
  Stream<LinkState> get stateChanges => _state.stream;
  @override
  LinkState get state => _current;
  @override
  Future<void> send(String message) async => hub.post(this, message);
  @override
  Future<void> close() async {
    _current = LinkState.closed;
  }
}

Future<void> idle([int ms = 5]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  final db = RCardDb.fromJson(jsonDecode(File('data/riftbound-cards.json').readAsStringSync()) as Map<String, dynamic>);
  final ruleset = RiftboundRuleset(db);
  final legends = playableLegends(db);

  RiftboundRoom room(Hub hub, String id, {required bool host, int legend = 0}) => RiftboundRoom(
        transport: hub.join(),
        ruleset: ruleset,
        localId: id,
        localName: id,
        localDeck: buildDeck(db, legends[legend]),
        isHost: host,
        mode: RMode.ffa4,
        botDeck: (seat, seats) => buildDeck(db, legends[(seat + 5) % legends.length]),
        botDelay: Duration.zero,
      );

  test('a host and two guests are seated, a computer fills the fourth seat, and all play a War game to the same end', () async {
    final hub = Hub();
    final host = room(hub, 'host', host: true);
    final a = room(hub, 'alice', host: false, legend: 1);
    final b = room(hub, 'bob', host: false, legend: 2);
    host.begin();
    a.begin();
    b.begin();
    // The host batches lobby updates (200 ms).
    await idle(400);
    expect(host.seats.map((s) => s.id), ['host', 'alice', 'bob']);
    expect(a.seats.map((s) => s.id), ['host', 'alice', 'bob'], reason: 'guests see the lobby');
    expect(a.localSeat, 1);
    expect(b.localSeat, 2);

    host.start();
    await idle(50);
    expect(a.started && b.started, isTrue);
    expect(host.seats[3].bot, isTrue);
    expect((host.game!).state.mode, RMode.ffa4);

    // People play with the computer player's logic, through their own device.
    final players = {0: host, 1: a, 2: b};
    final brains = {for (final p in players.keys) p: RiftboundBot(p, seed: 40 + p)};
    for (var step = 0; step < 20000; step++) {
      final g = host.game!;
      if (g.over) break;
      final p = g.toAct;
      final r = players[p];
      if (r != null && r.game!.actions.length == host.actions.length) {
        final m = brains[p]!.next(r.game!);
        if (m != null) {
          try {
            r.perform(m);
          } on TcgError {
            final fallback = r.game!.pending != null
                ? AnswerMove(p!, Game.defaultAnswer(r.game!.pending!.decision))
                : r.game!.legalMoves(p!).firstWhere((x) => x is PassMove || x is EndTurnMove);
            r.perform(fallback);
          }
        }
      }
      await idle(1);
    }
    await idle(50);
    final g = host.game!;
    expect(g.over, isTrue, reason: 'finished on turn ${g.state.turn}');
    expect(a.game!.fingerprint, g.fingerprint);
    expect(b.game!.fingerprint, g.fingerprint);
    expect(a.actions.length, host.actions.length);
    expect(a.desynced || b.desynced, isFalse);
    await host.dispose();
    await a.dispose();
    await b.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a guest that joins late, after the start, is told every seat was taken', () async {
    final hub = Hub();
    final host = room(hub, 'host', host: true);
    host.begin();
    host.start();
    await idle(20);
    final late = room(hub, 'late', host: false, legend: 3);
    late.begin();
    await idle(400);
    expect(late.started, isFalse);
    expect(late.error, contains('without you'));
    await host.dispose();
    await late.dispose();
  });

  test('a guest’s illegal move is refused by the host and changes nothing', () async {
    final hub = Hub();
    final host = room(hub, 'host', host: true);
    final a = room(hub, 'alice', host: false, legend: 1);
    host.begin();
    a.begin();
    await idle(30);
    host.start();
    await idle(30);
    // It isn't Alice's move (the mulligans go in turn order from the first player).
    final before = host.actions.length;
    expect(() => a.perform(EndTurnMove(a.localSeat)), throwsA(isA<TcgError>()));
    await idle(30);
    expect(host.actions.length, before);
    await host.dispose();
    await a.dispose();
  });

  test('2v2: teammates with the same legend can’t start (CR 491.8.h)', () async {
    final hub = Hub();
    final host = RiftboundRoom(
      transport: hub.join(),
      ruleset: ruleset,
      localId: 'host',
      localName: 'host',
      localDeck: buildDeck(db, legends[0]),
      isHost: true,
      mode: RMode.teams,
      botDeck: (seat, seats) => buildDeck(db, legends[0]),
    );
    host.addBot();
    host.addBot();
    expect(host.startProblem, contains('same legend'));
    await host.dispose();
  });
}
