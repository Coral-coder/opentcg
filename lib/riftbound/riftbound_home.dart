import 'dart:math';

import 'package:flutter/material.dart';
import 'package:tcg_app/tcg_app.dart';
import 'package:tcg_core/tcg_core.dart' show SeededRng;

import 'riftbound_cards_screen.dart';
import 'riftbound_deck_choice.dart';
import 'riftbound_lobbies.dart';
import 'riftbound_store.dart';
import 'riftbound_table.dart';
import 'riftbound_theme.dart';

/// Riftbound's menu: play the computer or a friend with a legend's starter deck or random
/// picks, online or nearby, and browse the cards.
class RiftboundHome extends StatelessWidget {
  const RiftboundHome({super.key});
  @override
  Widget build(BuildContext context) => riftboundScope(const _RiftboundHomeBody());
}

class _RiftboundHomeBody extends StatefulWidget {
  const _RiftboundHomeBody();
  @override
  State<_RiftboundHomeBody> createState() => _RiftboundHomeBodyState();
}

class _RiftboundHomeBodyState extends State<_RiftboundHomeBody> {
  final store = RiftboundStore.shared;
  RiftboundDeckChoice mine = const RiftboundDeckChoice.starter(null);
  RiftboundDeckChoice theirs = const RiftboundDeckChoice.random(null);
  String? error;

  @override
  void initState() {
    super.initState();
    store
        .init()
        .then((_) {
          if (!mounted) return;
          setState(() {
            // Default to the first two legends with starter decks.
            final names = store.legendNames;
            if (mine.legend == null && names.isNotEmpty) mine = RiftboundDeckChoice.starter(names.first);
            if (theirs.legend == null && names.length > 1) theirs = RiftboundDeckChoice.starter(names[1]);
          });
        })
        .catchError((Object e) {
          if (mounted) setState(() => error = '$e');
        });
  }

  void _start({required bool hotseat}) {
    final seed = Random().nextInt(1 << 30);
    final rng = SeededRng(seed);
    final decks = [mine.cards(store, rng), theirs.cards(store, rng)];
    store.newGame(names: hotseat ? const ['Player 1', 'Player 2'] : [store.playerName == 'Player' ? 'You' : store.playerName, 'Computer'], decks: decks, seed: seed, hotseat: hotseat);
    _push(const RiftboundTable());
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => riftboundScope(screen))).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    if (error != null) return Scaffold(body: Center(child: Text('Could not load the cards: $error')));
    if (!store.ready) {
      return Scaffold(
        backgroundColor: t.bg,
        body: const Stack(children: [Positioned.fill(child: HextechBackdrop()), Center(child: CircularProgressIndicator())]),
      );
    }
    final (ok, total) = store.coverage;
    final saved = store.savedGame;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: Text('RIFTBOUND', style: t.display(26, color: t.accent))),
      body: Stack(
        children: [
          const Positioned.fill(child: HextechBackdrop()),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (saved != null) ...[
                    ThemedButton(
                      'Resume game',
                      subtitle: 'Turn ${saved['turn'] ?? '?'} · ${(saved['names'] as List).join(' vs ')}',
                      tall: true,
                      icon: Icons.play_circle,
                      color: t.ok,
                      onPressed: () {
                        if (store.resume() != null) _push(const RiftboundTable());
                      },
                    ),
                    const SizedBox(height: 14),
                  ],
                  HexPanel(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RiftboundDeckChooser(label: 'Your deck', value: mine, onChanged: (c) => setState(() => mine = c)),
                        const SizedBox(height: 14),
                        RiftboundDeckChooser(label: 'Opponent’s deck', value: theirs, onChanged: (c) => setState(() => theirs = c)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ThemedButton('Play the computer', tall: true, icon: Icons.smart_toy, onPressed: () => _start(hotseat: false)),
                  const SizedBox(height: 10),
                  ThemedButton(
                    'Play online with a code',
                    subtitle: 'Browser or phone, anywhere',
                    tall: true,
                    icon: Icons.public,
                    color: t.accent2,
                    onPressed: () => _push(RiftboundRemoteLobby(deck: mine)),
                  ),
                  const SizedBox(height: 10),
                  if (nearbyPlaySupported) ...[
                    ThemedButton(
                      'Play nearby',
                      subtitle: 'Wi‑Fi or Bluetooth',
                      tall: true,
                      icon: Icons.wifi_tethering,
                      color: t.accent2,
                      onPressed: () => _push(RiftboundLocalLobby(deck: mine)),
                    ),
                    const SizedBox(height: 10),
                  ],
                  ThemedButton('Two players, one device', tall: true, icon: Icons.people, outlined: true, onPressed: () => _start(hotseat: true)),
                  const SizedBox(height: 10),
                  ThemedButton('Cards', icon: Icons.collections, outlined: true, onPressed: () => _push(const RiftboundCardsScreen())),
                  const SizedBox(height: 16),
                  HexPanel(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '$ok of $total cards fully supported; decks use only those (${store.legendNames.length} legends have full decks).\n\n'
                      'How to win: score 8 points. Send units to the two battlefields: take one (conquer) and you score; hold it at the start of your turn and you score again. '
                      'Each turn you channel two runes: exhaust them for Energy, recycle them for Power. Fights happen when units meet at a battlefield.',
                      style: t.style(13, weight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Unofficial fan project. Not endorsed by Riot Games; made under Riot Games’ “Legal Jibber Jabber” policy using assets owned by Riot Games. '
                    'Riot Games, Riftbound, League of Legends and all card names, text and images are trademarks or © of Riot Games, Inc. '
                    'Card data from Riftcodex (unofficial). Free, with no payments.',
                    style: t.style(11, weight: FontWeight.w500, color: t.muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
