import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:riftbound/riftbound.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_app/tcg_app.dart';

import 'riftbound_links.dart';
import 'riftbound_session.dart';

/// Riftbound's card database (bundled with the app), the saved local game and the current
/// session.
class RiftboundStore with RiftboundLinks {
  RiftboundStore._();
  static final shared = RiftboundStore._();

  RCardDb? _db;
  RCardDb get db => _db!;
  bool get ready => _db != null;
  RiftboundSession? session;
  SharedPreferences? _prefs;
  static const _savedKey = 'riftbound.saved';
  (int, int)? _coverage;

  Future<void> init() async {
    if (_db != null) return;
    final raw = await rootBundle.loadString('data/riftbound-cards.json');
    _db = RCardDb.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    _prefs = await SharedPreferences.getInstance();
    await initLinks(_prefs!);
  }

  List<String>? _legends;

  /// Legends with a full, supported deck (computed once).
  List<String> get legendNames => _legends ??= [for (final l in playableLegends(db)) l.name];

  /// Supported cards / all cards, for the menu.
  (int, int) get coverage {
    if (_coverage != null) return _coverage!;
    var ok = 0;
    for (final c in db.cards) {
      if (RiftboundParser.parse(c).supported) ok++;
    }
    return _coverage = (ok, db.cards.length);
  }

  Map<String, dynamic>? get savedGame {
    final s = _prefs?.getString(_savedKey);
    return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
  }

  RiftboundSession newGame({required List<String> names, required List<List<String>> decks, required int seed, required bool hotseat}) {
    final s = RiftboundSession.local(ruleset: RiftboundRuleset(db), mode: hotseat ? SessionMode.hotseat : SessionMode.solo, playerNames: names, seed: seed, decks: decks);
    _attach(s);
    s.start();
    return s;
  }

  RiftboundSession? resume() {
    final saved = savedGame;
    if (saved == null) return null;
    try {
      final s = RiftboundSession.local(
        ruleset: RiftboundRuleset(db),
        mode: SessionMode.values.byName(saved['mode'] as String),
        playerNames: (saved['names'] as List).cast<String>(),
        seed: saved['seed'] as int,
        decks: [for (final d in saved['decks'] as List) (d as List).cast<String>()],
      );
      _attach(s);
      s.replay([for (final a in saved['actions'] as List) RMove.fromJson((a as Map).cast<String, dynamic>())]);
      return s;
    } catch (_) {
      _prefs?.remove(_savedKey);
      return null;
    }
  }

  void _attach(RiftboundSession s) {
    session?.dispose();
    session = s;
    s.onSave = (j) => _prefs?.setString(_savedKey, jsonEncode(j));
    s.onFinished = () => _prefs?.remove(_savedKey);
  }

  /// A match linked to another device (relay code, Wi‑Fi or Bluetooth) becomes the session.
  RiftboundSession startLinkedGame(LockstepMatch match) {
    final s = RiftboundSession.linked(link: match);
    session?.dispose();
    session = s;
    return s;
  }

  void endSession() {
    final s = session;
    session = null;
    s?.dispose();
    s?.link?.dispose();
  }
}
