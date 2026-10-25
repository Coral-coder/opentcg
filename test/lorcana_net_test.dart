// Lorcana over the lockstep protocol: two devices play a whole match in sync, a crashed device
// picks the match up from its saved log, and a Magic device and a Lorcana device refuse to pair.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lorcana/lorcana.dart';
import 'package:rules/rules.dart' as mtg;
import 'package:tcg_app/tcg_app.dart';
import 'package:tcg_core/tcg_core.dart' show SeededRng;

late LCardDb db;

class MemoryArchive implements MatchArchive {
  final Map<String, Map<String, dynamic>> logs = {};
  @override
  Map<String, dynamic>? load(String key) => logs[key] == null ? null : jsonDecode(jsonEncode(logs[key])) as Map<String, dynamic>;
  @override
  void save(String key, Map<String, dynamic> log) => logs[key] = jsonDecode(jsonEncode(log)) as Map<String, dynamic>;
}

List<List<String>> decks(int seed) {
  final rng = SeededRng(seed);
  return [randomDeck(db, {Ink.amber, Ink.steel}, rng), randomDeck(db, {Ink.ruby, Ink.sapphire}, rng)];
}

Future<void> waitFor(bool Function() done, {Duration limit = const Duration(seconds: 20)}) async {
  final deadline = DateTime.now().add(limit);
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Game gameOf(LockstepMatch m) => m.game! as Game;

/// Both devices take turns: whoever must act moves (a bot picks the move), and the other side
/// waits until it has seen every move before the next one. Returns the number of moves made.
Future<int> playTo(LockstepMatch host, LockstepMatch guest, {int maxMoves = 4000}) async {
  final bots = {host: LorcanaBot(host.localSeat, seed: 11), guest: LorcanaBot(guest.localSeat, seed: 12)};
  var moves = 0;
  while (!gameOf(host).over && moves < maxMoves && host.error == null && guest.error == null) {
    final toAct = gameOf(host).toAct;
    final mover = toAct == host.localSeat ? host : guest;
    final other = mover == host ? guest : host;
    await waitFor(() => mover.actions.length == other.actions.length);
    expect(gameOf(mover).toAct, mover.localSeat, reason: 'the mover sees the same position at move ${mover.actions.length}');
    final move = bots[mover]!.next(gameOf(mover));
    expect(move, isNotNull, reason: 'the bot has a move');
    mover.perform(move!);
    await waitFor(() => other.actions.length == mover.actions.length);
    moves++;
  }
  return moves;
}

void main() {
  setUpAll(() {
    Console.available = false;
    db = LCardDb.fromJson(jsonDecode(File('data/lorcana-cards.json').readAsStringSync()) as Map<String, dynamic>);
  });

  test('two devices play a whole Lorcana match in lockstep, with the same fingerprint', () async {
    final (a, b) = LoopbackTransport.pair();
    final d = decks(5);
    final host = LockstepMatch(transport: a, ruleset: LorcanaRuleset(db), localName: 'Host', localId: 'h', localDeck: d[0], isHost: true, seed: 42);
    final guest = LockstepMatch(transport: b, ruleset: LorcanaRuleset(db), localName: 'Guest', localId: 'g', localDeck: d[1], isHost: false);
    host.begin();
    guest.begin();
    await waitFor(() => host.game != null && guest.game != null);
    expect(host.game, isNotNull);
    expect(guest.game, isNotNull);
    final moves = await playTo(host, guest);
    expect(host.error, isNull);
    expect(guest.error, isNull);
    expect(host.desynced || guest.desynced, isFalse);
    expect(gameOf(host).over, isTrue, reason: 'the match should finish within $moves moves');
    expect(guest.game!.fingerprint, host.game!.fingerprint);
    expect(gameOf(guest).state.winner, gameOf(host).state.winner);
    await host.dispose();
    await guest.dispose();
  });

  test('a device that crashed mid-match picks it up from its saved log', () async {
    final archive = MemoryArchive();
    final (a, b) = LoopbackTransport.pair();
    final d = decks(6);
    final host = LockstepMatch(transport: a, ruleset: LorcanaRuleset(db), localName: 'Host', localId: 'h', localDeck: d[0], isHost: true, seed: 7, matchKey: 'relay:TEST', archive: archive);
    final guest = LockstepMatch(transport: b, ruleset: LorcanaRuleset(db), localName: 'Guest', localId: 'g', localDeck: d[1], isHost: false);
    host.begin();
    guest.begin();
    await waitFor(() => host.game != null && guest.game != null);
    await playTo(host, guest, maxMoves: 40);
    final fp = host.game!.fingerprint;
    final n = host.actions.length;
    await host.dispose();
    await guest.dispose();
    // The host's app restarts: the same key brings the match back with every move.
    final (c, _) = LoopbackTransport.pair();
    final again = LockstepMatch(transport: c, ruleset: LorcanaRuleset(db), localName: 'Host', localId: 'h', localDeck: d[0], isHost: true, matchKey: 'relay:TEST', archive: archive);
    expect(again.game, isNotNull);
    expect(again.actions.length, n);
    expect(again.game!.fingerprint, fp);
    await again.dispose();
  });

  test('a Magic device and a Lorcana device refuse to pair', () async {
    final (a, b) = LoopbackTransport.pair();
    final lorcana = LockstepMatch(transport: a, ruleset: LorcanaRuleset(db), localName: 'Lorcana', localId: 'l', localDeck: decks(1)[0], isHost: true, seed: 1);
    final magic = LockstepMatch(transport: b, ruleset: mtg.MtgRuleset(mtg.CardDatabase(const [])), localName: 'Magic', localId: 'm', localDeck: const ['Forest'], isHost: false);
    lorcana.begin();
    magic.begin();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(lorcana.game, isNull);
    expect(magic.game, isNull);
    expect(lorcana.error, contains('different card game'));
    expect(magic.error, contains('different card game'));
    await lorcana.dispose();
    await magic.dispose();
  });
}
