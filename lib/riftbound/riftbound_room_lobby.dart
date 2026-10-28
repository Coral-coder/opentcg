import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:riftbound/riftbound.dart';
import 'package:tcg_app/tcg_app.dart';
import 'package:tcg_core/tcg_core.dart' show SeededRng, TcgError;

import 'riftbound_deck_choice.dart';
import 'riftbound_lobbies.dart';
import 'riftbound_room.dart';
import 'riftbound_store.dart';
import 'riftbound_table.dart';
import 'riftbound_theme.dart';

/// Online play for Skirmish, War and 2v2: one person creates a room and shares its code, the
/// others join with it; the host picks the mode, can fill seats with computers, and starts.
/// Messages go through public Nostr relays, so nobody runs a server.
class RiftboundRoomLobby extends StatefulWidget {
  const RiftboundRoomLobby({super.key, required this.deck, required this.mode});
  final RiftboundDeckChoice deck;
  final RMode mode;
  @override
  State<RiftboundRoomLobby> createState() => _RiftboundRoomLobbyState();
}

class _RiftboundRoomLobbyState extends State<RiftboundRoomLobby> {
  final codeController = TextEditingController();
  RiftboundRoom? room;
  RelayTransport? transport;
  String? code;
  String status = '';
  int relaysUp = 0;
  StreamSubscription<String>? sub;
  StreamSubscription<Map<String, bool>>? relaySub;
  bool _opened = false;

  RiftboundStore get store => RiftboundStore.shared;

  @override
  void dispose() {
    sub?.cancel();
    relaySub?.cancel();
    if (store.session?.room != room) room?.dispose();
    codeController.dispose();
    super.dispose();
  }

  /// A computer's deck: a random legend's starter deck, never a teammate's legend (CR 491.8.h).
  List<String> _botDeck(int seat, List<RoomSeat> seats) {
    final db = store.db;
    final mode = room?.mode ?? widget.mode;
    final taken = <String?>{
      if (mode == RMode.teams) ...[
        if (seat >= 2 && seat - 2 < seats.length) deckLegend(db, seats[seat - 2].deck)?.name,
        if (seat + 2 < seats.length) deckLegend(db, seats[seat + 2].deck)?.name,
      ],
    };
    final legends = [for (final n in store.legendNames) if (!taken.contains(n)) db[n]!];
    return buildDeck(db, legends[Random().nextInt(legends.length)]);
  }

  Future<void> open(String c, {required bool host}) async {
    if (c.length < 4) {
      setState(() => status = 'A room code has 6 letters and digits.');
      return;
    }
    await sub?.cancel();
    await relaySub?.cancel();
    if (store.session?.room != room) await room?.dispose();
    final t = RelayTransport(code: 'room-$c', secretKey: store.relayIdentity, relays: store.relays);
    transport = t;
    relaySub = t.relayStatus.listen((m) {
      if (mounted) setState(() => relaysUp = m.values.where((v) => v).length);
    });
    final r = RiftboundRoom(
      transport: t,
      ruleset: RiftboundRuleset(store.db),
      localId: store.deviceId,
      localName: store.playerName,
      localDeck: widget.deck.cards(store, SeededRng(Random().nextInt(1 << 30))),
      isHost: host,
      mode: widget.mode,
      archive: store,
      key: 'room:$c',
      botDeck: _botDeck,
    );
    room = r;
    setState(() {
      code = c;
      status = host ? 'Share the code. Everyone who joins gets a seat; computers fill the rest when you start.' : 'Joining $c…';
    });
    sub = r.events.listen((e) {
      if (!mounted) return;
      if ((e == 'start' || e == 'action') && r.game != null) {
        _openTable(r);
      } else if (e == 'error' || e == 'desync') {
        setState(() => status = r.error ?? 'Something went wrong');
      } else {
        setState(() {
          if (!host && r.seated) status = 'Seated. Waiting for ${r.seats.isEmpty ? 'the host' : r.seats.first.name} to start…';
          if (r.notice != null) status = r.notice!;
        });
      }
    });
    r.begin();
    // A game picked up from this device's saved log opens at once.
    if (r.game != null) _openTable(r);
  }

  void _openTable(RiftboundRoom r) {
    if (_opened) return;
    _opened = true;
    store.startRoomGame(r);
    Console.shared.play(Fx.confirm);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => riftboundScope(const RiftboundTable())));
  }

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final r = room;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: Text('Online room', style: t.display(20, color: t.accent))),
      body: Stack(
        children: [
          const Positioned.fill(child: HextechBackdrop()),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (r == null) ...[
                    const RiftboundPlayerNameField(),
                    const SizedBox(height: 14),
                    ThemedButton(
                      'Create a room',
                      subtitle: '${widget.mode.label}: you host and start the game',
                      tall: true,
                      icon: Icons.add_circle,
                      onPressed: () => open(newMatchCode(), host: true),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: codeController,
                      textCapitalization: TextCapitalization.characters,
                      style: t.body,
                      decoration: InputDecoration(labelText: 'Room code', filled: true, fillColor: t.panel, border: const OutlineInputBorder()),
                      onSubmitted: (v) => open(v.trim().toUpperCase(), host: false),
                    ),
                    const SizedBox(height: 8),
                    ThemedButton('Join a room', icon: Icons.login, color: t.accent2, onPressed: () => open(codeController.text.trim().toUpperCase(), host: false)),
                  ] else ...[
                    HexPanel(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Semantics(
                                  label: 'Room code ${code ?? ''}',
                                  child: ExcludeSemantics(child: SelectableText(code ?? '', style: t.display(30, color: t.accent))),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Copy the code',
                                icon: Icon(Icons.copy, color: t.accent),
                                onPressed: () => Clipboard.setData(ClipboardData(text: code ?? '')),
                              ),
                            ],
                          ),
                          Text('${r.mode.label} · relays connected: $relaysUp', style: t.style(12, color: t.muted)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (r.isHost && !r.started)
                      RiftboundModePicker(
                        value: r.mode,
                        onChanged: (m) => setState(() => r.setMode(m)),
                      ),
                    const SizedBox(height: 12),
                    _Seats(room: r, onRemove: (i) => setState(() => r.removeSeat(i))),
                    const SizedBox(height: 12),
                    if (r.isHost && !r.started) ...[
                      ThemedButton(
                        'Add a computer',
                        icon: Icons.smart_toy,
                        outlined: true,
                        onPressed: r.seats.length < r.mode.players ? () => setState(r.addBot) : null,
                      ),
                      const SizedBox(height: 8),
                      ThemedButton(
                        'Start the game',
                        subtitle: r.startProblem ?? (r.seats.length < r.mode.players ? 'Computers take the ${r.mode.players - r.seats.length} empty seat${r.mode.players - r.seats.length == 1 ? '' : 's'}' : 'Everyone is seated'),
                        tall: true,
                        icon: Icons.play_arrow,
                        onPressed: r.startProblem != null
                            ? null
                            : () {
                                try {
                                  r.start();
                                } on TcgError catch (e) {
                                  setState(() => status = e.message);
                                }
                              },
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(status, style: t.style(13, weight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Who sits where: in 2v2 seats 1 and 3 are one team, 2 and 4 the other (turn order alternates
/// teams, CR 491.5.c).
class _Seats extends StatelessWidget {
  const _Seats({required this.room, required this.onRemove});
  final RiftboundRoom room;
  final void Function(int) onRemove;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final n = room.mode.players;
    return HexPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Seats', style: t.display(17, color: t.accent)),
          const SizedBox(height: 6),
          for (var i = 0; i < n; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(width: 22, child: Text('${i + 1}', style: t.style(14, weight: FontWeight.w900, color: t.muted))),
                  if (room.mode == RMode.teams)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(i % 2 == 0 ? 'Team A' : 'Team B', style: t.style(11, weight: FontWeight.w800, color: i % 2 == 0 ? t.accent2 : t.danger)),
                    ),
                  Icon(i < room.seats.length ? (room.seats[i].bot ? Icons.smart_toy : Icons.person) : Icons.event_seat_outlined, size: 18, color: t.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      i < room.seats.length ? '${room.seats[i].name}${room.seats[i].id == RiftboundStore.shared.deviceId ? ' (you)' : ''}${i == 0 ? ' · host' : ''}' : 'Empty (a computer if nobody joins)',
                      style: t.style(14, weight: i < room.seats.length ? FontWeight.w700 : FontWeight.w400, color: i < room.seats.length ? t.text : t.muted),
                    ),
                  ),
                  if (room.isHost && !room.started && i > 0 && i < room.seats.length)
                    IconButton(tooltip: 'Free this seat', icon: Icon(Icons.close, size: 18, color: t.muted), onPressed: () => onRemove(i)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
