import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_app/tcg_app.dart';

/// What Lorcana's linked play keeps on this device: who this device is (shared with the other
/// games: the same device id, relay identity and player name), the relays, the matches made
/// with a code, and every linked match's move log ([MatchArchive], so a crash or a closed app
/// picks the match up where it was).
mixin LorcanaLinks implements MatchArchive {
  SharedPreferences? _linkPrefs;
  String deviceId = '';
  String relayIdentity = '';
  String playerName = 'Player';
  List<String> relays = List.of(defaultRelays);
  List<Map<String, dynamic>> remoteMatches = [];

  static const _remoteKey = 'lorcana.remoteMatches';
  static const _logsKey = 'lorcana.matchLogs';

  Future<void> initLinks(SharedPreferences prefs) async {
    _linkPrefs = prefs;
    deviceId = prefs.getString('deviceId') ?? '';
    if (deviceId.isEmpty) {
      deviceId = newMatchCode(10);
      await prefs.setString('deviceId', deviceId);
    }
    relayIdentity = prefs.getString('relayIdentity') ?? '';
    if (relayIdentity.isEmpty) {
      relayIdentity = newRelayIdentity();
      await prefs.setString('relayIdentity', relayIdentity);
    }
    playerName = prefs.getString('playerName') ?? 'Player';
    relays = prefs.getStringList('relays') ?? List.of(defaultRelays);
    final rm = prefs.getString(_remoteKey);
    if (rm != null) {
      try {
        remoteMatches = (jsonDecode(rm) as List).cast<Map<String, dynamic>>();
      } catch (_) {
        remoteMatches = [];
      }
    }
  }

  /// The name the other player sees (shared with the other games on this device).
  Future<void> setPlayerName(String name) async {
    playerName = name.trim().isEmpty ? 'Player' : name.trim();
    await _linkPrefs?.setString('playerName', playerName);
  }

  Future<void> rememberRemoteMatch({required String code, required bool host, String? opponent}) async {
    remoteMatches.removeWhere((m) => m['code'] == code);
    remoteMatches.insert(0, {'code': code, 'host': host, 'opponent': opponent, 'date': DateTime.now().toIso8601String()});
    if (remoteMatches.length > 20) remoteMatches = remoteMatches.sublist(0, 20);
    await _linkPrefs?.setString(_remoteKey, jsonEncode(remoteMatches));
  }

  Future<void> forgetRemote(String code) async {
    remoteMatches.removeWhere((m) => m['code'] == code);
    await _linkPrefs?.setString(_remoteKey, jsonEncode(remoteMatches));
    await _linkPrefs?.remove('lorcana.match:relay:$code');
  }

  @override
  Map<String, dynamic>? load(String key) {
    final raw = _linkPrefs?.getString('lorcana.match:$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  void save(String key, Map<String, dynamic> log) {
    final p = _linkPrefs;
    if (p == null) return;
    p.setString('lorcana.match:$key', jsonEncode(log));
    final keys = (p.getStringList(_logsKey) ?? [])
      ..remove(key)
      ..insert(0, key);
    for (final old in keys.skip(30)) {
      p.remove('lorcana.match:$old');
    }
    p.setStringList(_logsKey, keys.take(30).toList());
  }
}
