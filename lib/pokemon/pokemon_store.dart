import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pokemon/pokemon.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_app/tcg_app.dart';

import 'pokemon_links.dart';
import 'pokemon_session.dart';

/// Pokémon's card database (bundled with the app), the saved local game and the current
/// session.
class PokemonStore with PokemonLinks {
  PokemonStore._();
  static final shared = PokemonStore._();

  PCardDb? _db;
  PCardDb get db => _db!;
  bool get ready => _db != null;
  PokemonSession? session;
  SharedPreferences? _prefs;
  static const _savedKey = 'pokemon.saved';
  (int, int)? _coverage;

  Future<void> init() async {
    if (_db != null) return;
    final raw = await rootBundle.loadString('data/pokemon-cards.json');
    _db = PCardDb.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    _prefs = await SharedPreferences.getInstance();
    await initLinks(_prefs!);
  }

  /// Supported cards / all cards, for the menu.
  (int, int) get coverage {
    if (_coverage != null) return _coverage!;
    var ok = 0;
    for (final c in db.cards) {
      if (PokemonParser.parse(c).supported) ok++;
    }
    return _coverage = (ok, db.cards.length);
  }

  Map<String, dynamic>? get savedGame {
    final s = _prefs?.getString(_savedKey);
    return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
  }

  PokemonSession newGame({required List<String> names, required List<List<String>> decks, required int seed, required bool hotseat}) {
    final s = PokemonSession.local(ruleset: PokemonRuleset(db), mode: hotseat ? SessionMode.hotseat : SessionMode.solo, playerNames: names, seed: seed, decks: decks);
    _attach(s);
    s.start();
    return s;
  }

  PokemonSession? resume() {
    final saved = savedGame;
    if (saved == null) return null;
    try {
      final s = PokemonSession.local(
        ruleset: PokemonRuleset(db),
        mode: SessionMode.values.byName(saved['mode'] as String),
        playerNames: (saved['names'] as List).cast<String>(),
        seed: saved['seed'] as int,
        decks: [for (final d in saved['decks'] as List) (d as List).cast<String>()],
      );
      _attach(s);
      s.replay([for (final a in saved['actions'] as List) PMove.fromJson((a as Map).cast<String, dynamic>())]);
      return s;
    } catch (_) {
      _prefs?.remove(_savedKey);
      return null;
    }
  }

  void _attach(PokemonSession s) {
    session?.dispose();
    session = s;
    s.onSave = (j) => _prefs?.setString(_savedKey, jsonEncode(j));
    s.onFinished = () => _prefs?.remove(_savedKey);
  }

  /// A match linked to another device (relay code, Wi‑Fi or Bluetooth) becomes the session.
  PokemonSession startLinkedGame(LockstepMatch match) {
    final s = PokemonSession.linked(link: match);
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
