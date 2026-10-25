import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pokemon/pokemon.dart';
import 'package:tcg_app/tcg_app.dart';
import 'package:tcg_core/tcg_core.dart' show SeededRng;

import 'pokemon_deck_choice.dart';
import 'pokemon_store.dart';
import 'pokemon_table.dart';
import 'pokemon_theme.dart';

/// The cards for [choice] (a starter or random deck from the Pokémon menu); random decks
/// draw fresh cards each time.
List<String> pokemonDeckFor(PokemonDeckChoice choice) => choice.cards(PokemonStore.shared, SeededRng(Random().nextInt(1 << 30)));

/// "Your name", as the other player will see it.
class PokemonPlayerNameField extends StatelessWidget {
  const PokemonPlayerNameField({super.key});
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return TextFormField(
      initialValue: PokemonStore.shared.playerName,
      style: t.body,
      decoration: InputDecoration(labelText: 'Your name', filled: true, fillColor: t.panel, border: const OutlineInputBorder(), isDense: true),
      onChanged: PokemonStore.shared.setPlayerName,
    );
  }
}

/// Opens the table for [match], replacing the lobby.
void _openLinked(BuildContext context, LockstepMatch match) {
  PokemonStore.shared.startLinkedGame(match);
  Console.shared.play(Fx.confirm);
  Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => pokemonScope(const PokemonTable())));
}

/// Play online through public relays: share a 6-character code; no account, no server of ours.
class PokemonRemoteLobby extends StatefulWidget {
  const PokemonRemoteLobby({super.key, required this.deck});
  final PokemonDeckChoice deck;
  @override
  State<PokemonRemoteLobby> createState() => _PokemonRemoteLobbyState();
}

class _PokemonRemoteLobbyState extends State<PokemonRemoteLobby> {
  final codeController = TextEditingController();
  String status = '';
  String? hostedCode;
  RelayTransport? transport;
  LockstepMatch? match;
  StreamSubscription<String>? sub;
  StreamSubscription<Map<String, bool>>? relaySub;
  int relaysUp = 0;

  PokemonStore get store => PokemonStore.shared;

  @override
  void dispose() {
    sub?.cancel();
    relaySub?.cancel();
    if (store.session?.link != match) match?.dispose();
    codeController.dispose();
    super.dispose();
  }

  Future<void> forget(String code) async {
    if (transport?.code == code && store.session?.link != match) {
      await sub?.cancel();
      await relaySub?.cancel();
      sub = null;
      relaySub = null;
      await match?.dispose();
      match = null;
      transport = null;
      hostedCode = null;
      relaysUp = 0;
      status = '';
    }
    if (store.session?.link?.matchKey == 'relay:$code') store.endSession();
    await store.forgetRemote(code);
    if (mounted) setState(() {});
  }

  Future<void> open(String code, {required bool isHost}) async {
    if (code.length < 4) {
      setState(() => status = 'A match code has 6 letters and digits.');
      return;
    }
    // A match already on the table: go back to it.
    final current = store.session?.link;
    if (current != null && current.matchKey == 'relay:$code' && current.game != null) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => pokemonScope(const PokemonTable())));
      return;
    }
    await sub?.cancel();
    if (store.session?.link != match) await match?.dispose();
    final t = RelayTransport(code: code, secretKey: store.relayIdentity, relays: store.relays);
    transport = t;
    await relaySub?.cancel();
    relaySub = t.relayStatus.listen((m) {
      if (mounted) setState(() => relaysUp = m.values.where((v) => v).length);
    });
    final m = LockstepMatch(
      transport: t,
      ruleset: PokemonRuleset(store.db),
      localName: store.playerName,
      localId: store.deviceId,
      localDeck: pokemonDeckFor(widget.deck),
      isHost: isHost,
      matchKey: 'relay:$code',
      archive: store,
    );
    match = m;
    setState(() {
      hostedCode = isHost ? code : null;
      status = isHost ? 'Share the code. The game starts when your opponent joins.' : 'Joining $code…';
    });
    store.rememberRemoteMatch(code: code, host: isHost);
    sub = m.events.listen((e) {
      if ((e == 'start' || e == 'hello' || e == 'action') && m.game != null) {
        if (store.session?.link == m) return;
        store.rememberRemoteMatch(code: code, host: isHost, opponent: m.remoteName);
        if (mounted) _openLinked(context, m);
      } else if (e == 'error') {
        if (mounted) setState(() => status = m.error ?? 'Link failed');
      } else if (e == 'hello') {
        if (mounted) setState(() => status = 'Linked with ${m.remoteName}…');
      }
    });
    m.begin();
    // A match picked up from this device's saved log opens at once.
    if (m.game != null && mounted) _openLinked(context, m);
  }

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Play Pokémon online')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Play someone anywhere, in a browser or on a phone. Moves travel encrypted through public relays, so nobody runs a server and a match can continue days later.', style: t.body),
              const SizedBox(height: 8),
              const SizedBox(height: 10),
              const PokemonPlayerNameField(),
              const SizedBox(height: 8),
              Text('Your deck: ${widget.deck.label(PokemonStore.shared)}.', style: t.small),
              const SizedBox(height: 12),
              ThemedButton('Create a match code', tall: true, icon: Icons.add, onPressed: () => open(newMatchCode(), isHost: true)),
              if (hostedCode != null) ...[
                const SizedBox(height: 8),
                ThemedPanel(
                  title: 'Match code',
                  color: t.highlight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SelectableText(
                        hostedCode!,
                        style: t.style(40, weight: FontWeight.w900, color: t.accent),
                        textAlign: TextAlign.center,
                      ),
                      ThemedButton(
                        'Copy',
                        icon: Icons.copy,
                        outlined: true,
                        onPressed: () => Clipboard.setData(ClipboardData(text: hostedCode!)),
                      ),
                    ],
                  ),
                ),
              ],
              const ThemedHeader('Join a match'),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: codeController,
                      style: t.style(22, weight: FontWeight.w800),
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(isDense: true, filled: true, fillColor: t.panel, border: const OutlineInputBorder(), hintText: 'CODE'),
                      onSubmitted: (_) => open(codeController.text.trim().toUpperCase(), isHost: false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 100, child: ThemedButton('Join', onPressed: () => open(codeController.text.trim().toUpperCase(), isHost: false))),
                ],
              ),
              if (store.remoteMatches.isNotEmpty) const ThemedHeader('Your matches'),
              for (final m in store.remoteMatches)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: ThemedButton(
                          '${m['code']} · ${m['host'] == true ? 'hosted' : 'joined'}${m['opponent'] != null ? ' · vs ${m['opponent']}' : ''}',
                          outlined: true,
                          onPressed: () => open(m['code'] as String, isHost: m['host'] as bool),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: t.muted),
                        tooltip: 'Remove this match',
                        onPressed: () => forget(m['code'] as String),
                      ),
                    ],
                  ),
                ),
              if (status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('$status${transport != null ? '  ($relaysUp relays connected)' : ''}', style: t.style(14, color: t.highlight)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nearby play on phones: host over Wi‑Fi or Bluetooth, or find a host and join.
class PokemonLocalLobby extends StatefulWidget {
  const PokemonLocalLobby({super.key, required this.deck});
  final PokemonDeckChoice deck;
  @override
  State<PokemonLocalLobby> createState() => _PokemonLocalLobbyState();
}

class _PokemonLocalLobbyState extends State<PokemonLocalLobby> {
  LinkKind kind = LinkKind.lan;
  HostLink? host;
  GuestLink? guest;
  List<PeerInfo> peers = [];
  String status = '';
  bool hosting = false, scanning = false, busy = false;
  final List<StreamSubscription<dynamic>> _subs = [];
  final addressController = TextEditingController();

  PokemonStore get store => PokemonStore.shared;

  @override
  void dispose() {
    _stopAll();
    addressController.dispose();
    super.dispose();
  }

  Future<void> _stopAll() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await host?.stop();
    await guest?.stopScan();
    host = null;
    guest = null;
  }

  Future<void> startHosting() async {
    await _stopAll();
    final h = kind == LinkKind.lan ? LanHost() : BleHost();
    setState(() {
      hosting = true;
      scanning = false;
      status = 'Starting…';
    });
    try {
      await h.start(name: store.playerName, id: store.deviceId);
      host = h;
      _subs.add(h.connections.listen(_onConnected));
      if (h is LanHost) {
        final addresses = await localAddresses();
        final where = addresses.map((a) => h.port == lanGamePort ? a : '$a:${h.port}').join(' or ');
        setState(() => status = 'Hosting on Wi‑Fi as ${store.playerName}. Waiting for a player…${where.isEmpty ? '' : '\nThey can also join by typing: $where'}');
      } else {
        setState(() => status = 'Hosting over Bluetooth as ${store.playerName}. Waiting for a player…');
      }
    } catch (e) {
      setState(() {
        hosting = false;
        status = 'Could not host: $e';
      });
    }
  }

  Future<void> startScanning() async {
    await _stopAll();
    final g = kind == LinkKind.lan ? LanGuest() : BleGuest();
    setState(() {
      scanning = true;
      hosting = false;
      peers = [];
      status = 'Looking for hosts…';
    });
    try {
      await g.startScan();
      guest = g;
      _subs.add(g.peers.listen((p) => setState(() => peers = p)));
    } catch (e) {
      setState(() {
        scanning = false;
        status = 'Could not scan: $e';
      });
    }
  }

  Future<void> join(PeerInfo peer) async {
    final g = guest;
    if (g == null || busy) return;
    setState(() {
      busy = true;
      status = 'Connecting to ${peer.name}…';
    });
    try {
      final t = await g.connect(peer);
      await g.stopScan();
      _begin(t, isHost: false);
    } catch (e) {
      setState(() {
        busy = false;
        status = 'Could not connect: $e';
      });
    }
  }

  Future<void> joinAddress() async {
    final text = addressController.text.trim();
    final parts = text.contains(':') ? text.split(':') : [text, '$lanGamePort'];
    if (parts.length != 2 || parts[0].isEmpty || int.tryParse(parts[1]) == null) {
      setState(() => status = "Type the host's IP address, e.g. 192.168.1.20 (or 192.168.1.20:$lanGamePort)");
      return;
    }
    setState(() {
      busy = true;
      status = 'Connecting to $text…';
    });
    try {
      final t = await LanGuest().connectTo(parts[0], int.parse(parts[1]));
      _begin(t, isHost: false);
    } catch (e) {
      setState(() {
        busy = false;
        status = 'Could not connect: $e';
      });
    }
  }

  void _onConnected(Transport t) {
    setState(() => status = 'A player connected. Linking…');
    _begin(t, isHost: true);
  }

  void _begin(Transport t, {required bool isHost}) {
    final match = LockstepMatch(
      transport: t,
      ruleset: PokemonRuleset(store.db),
      localName: store.playerName,
      localId: store.deviceId,
      localDeck: pokemonDeckFor(widget.deck),
      isHost: isHost,
      archive: store,
    );
    late StreamSubscription<String> sub;
    var opened = false;
    void go() {
      if (opened) return;
      opened = true;
      sub.cancel();
      _subs.remove(sub);
      host?.stop();
      host = null;
      if (mounted) _openLinked(context, match);
    }

    sub = match.events.listen((e) {
      if (e == 'start' || (e == 'hello' && match.game != null)) {
        if (match.game != null) go();
      } else if (e == 'error') {
        setState(() {
          busy = false;
          status = match.error ?? 'Link failed';
        });
      }
    });
    _subs.add(sub);
    match.begin();
    Timer(const Duration(milliseconds: 300), () {
      if (match.game != null && mounted && store.session?.link != match) go();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Play Pokémon nearby')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Both devices on the same Wi‑Fi, or Bluetooth with no network at all. One player hosts, the other joins.', style: t.body),
              const SizedBox(height: 8),
              const SizedBox(height: 10),
              const PokemonPlayerNameField(),
              const SizedBox(height: 8),
              Text('Your deck: ${widget.deck.label(PokemonStore.shared)}.', style: t.small),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ThemedButton('Wi‑Fi', icon: Icons.wifi, outlined: kind != LinkKind.lan, onPressed: () => setState(() => kind = LinkKind.lan)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ThemedButton('Bluetooth', icon: Icons.bluetooth, outlined: kind != LinkKind.bluetooth, onPressed: () => setState(() => kind = LinkKind.bluetooth)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ThemedButton(
                hosting ? 'Hosting… (tap to stop)' : 'Host a game',
                tall: true,
                icon: Icons.cell_tower,
                onPressed: () async {
                  if (hosting) {
                    await _stopAll();
                    setState(() {
                      hosting = false;
                      status = '';
                    });
                  } else {
                    startHosting();
                  }
                },
              ),
              const SizedBox(height: 8),
              ThemedButton(
                scanning ? 'Searching… (tap to stop)' : 'Find hosts nearby',
                tall: true,
                icon: Icons.search,
                color: t.accent2,
                onPressed: () async {
                  if (scanning) {
                    await _stopAll();
                    setState(() {
                      scanning = false;
                      status = '';
                    });
                  } else {
                    startScanning();
                  }
                },
              ),
              for (final p in peers)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ThemedButton('${p.name} · ${p.kind == LinkKind.lan ? p.address : 'Bluetooth'}', icon: Icons.login, onPressed: busy ? null : () => join(p)),
                ),
              if (kind == LinkKind.lan) ...[
                const ThemedHeader('Join by IP address'),
                Text("If the host doesn't show up above, type the address shown on their screen.", style: t.small),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: addressController,
                        style: t.body,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(filled: true, fillColor: t.panel, border: const OutlineInputBorder(), hintText: '192.168.1.20'),
                        onSubmitted: (_) => busy ? null : joinAddress(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 100, child: ThemedButton('Join', onPressed: busy ? null : joinAddress)),
                  ],
                ),
              ],
              if (status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(status, style: t.style(14, color: t.highlight)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whether nearby play (Wi‑Fi sockets, Bluetooth) exists on this platform.
bool get nearbyPlaySupported => !kIsWeb;
