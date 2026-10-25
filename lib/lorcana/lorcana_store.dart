import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:lorcana/lorcana.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_app/tcg_app.dart';

import 'lorcana_decks.dart';
import 'lorcana_links.dart';
import 'lorcana_session.dart';

/// Lorcana's card database (bundled with the app), the saved local game and the current session.
class LorcanaStore with LorcanaLinks {
  LorcanaStore._();
  static final shared = LorcanaStore._();

  LCardDb? _db;
  LCardDb get db => _db!;
  bool get ready => _db != null;
  LorcanaSession? session;
  SharedPreferences? _prefs;
  static const _savedKey = 'lorcana.saved';

  /// The player's saved decks.
  final decks = LorcanaDeckBook();

  Future<void> init() async {
    if (_db != null) return;
    final raw = await rootBundle.loadString('data/lorcana-cards.json');
    _db = LCardDb.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    _prefs = await SharedPreferences.getInstance();
    decks.load(_prefs!);
    await initLinks(_prefs!);
  }

  /// Supported cards / all cards, for the menu.
  (int, int) get coverage {
    var ok = 0;
    for (final c in db.cards) {
      if (LorcanaParser.parse(c).supported) ok++;
    }
    return (ok, db.cards.length);
  }

  Map<String, dynamic>? get savedGame {
    final s = _prefs?.getString(_savedKey);
    return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
  }

  LorcanaSession newGame({required List<String> names, required List<List<String>> decks, required int seed, required bool hotseat}) {
    final s = LorcanaSession.local(ruleset: LorcanaRuleset(db), mode: hotseat ? SessionMode.hotseat : SessionMode.solo, playerNames: names, seed: seed, decks: decks);
    _attach(s);
    s.start();
    return s;
  }

  LorcanaSession? resume() {
    final saved = savedGame;
    if (saved == null) return null;
    try {
      final s = LorcanaSession.local(
        ruleset: LorcanaRuleset(db),
        mode: SessionMode.values.byName(saved['mode'] as String),
        playerNames: (saved['names'] as List).cast<String>(),
        seed: saved['seed'] as int,
        decks: [for (final d in saved['decks'] as List) (d as List).cast<String>()],
      );
      _attach(s);
      s.replay([for (final a in saved['actions'] as List) LMove.fromJson((a as Map).cast<String, dynamic>())]);
      return s;
    } catch (_) {
      _prefs?.remove(_savedKey);
      return null;
    }
  }

  void _attach(LorcanaSession s) {
    session?.dispose();
    session = s;
    s.onSave = (j) => _prefs?.setString(_savedKey, jsonEncode(j));
    s.onFinished = () => _prefs?.remove(_savedKey);
  }

  /// A match linked to another device (relay code, Wi‑Fi or Bluetooth) becomes the session.
  LorcanaSession startLinkedGame(LockstepMatch match) {
    final s = LorcanaSession.linked(link: match);
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
