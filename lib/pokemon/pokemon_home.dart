import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pokemon/pokemon.dart';
import 'package:tcg_app/tcg_app.dart';
import 'package:tcg_core/tcg_core.dart' show SeededRng;

import 'pokemon_cards_screen.dart';
import 'pokemon_deck_choice.dart';
import 'pokemon_lobbies.dart';
import 'pokemon_store.dart';
import 'pokemon_table.dart';
import 'pokemon_theme.dart';

/// Pokémon's menu: play the computer or a friend with starter or random decks of a type, online
/// or nearby, and browse the cards.
class PokemonHome extends StatelessWidget {
  const PokemonHome({super.key});
  @override
  Widget build(BuildContext context) => pokemonScope(const _PokemonHomeBody());
}

class _PokemonHomeBody extends StatefulWidget {
  const _PokemonHomeBody();
  @override
  State<_PokemonHomeBody> createState() => _PokemonHomeBodyState();
}

class _PokemonHomeBodyState extends State<_PokemonHomeBody> {
  final store = PokemonStore.shared;
  PokemonDeckChoice mine = const PokemonDeckChoice.starter(PType.lightning);
  PokemonDeckChoice theirs = const PokemonDeckChoice.starter(PType.fire);
  String? error;

  @override
  void initState() {
    super.initState();
    store
        .init()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((Object e) {
          if (mounted) setState(() => error = '$e');
        });
  }

  void _start({required bool hotseat}) {
    final seed = Random().nextInt(1 << 30);
    final rng = SeededRng(seed);
    final decks = [mine.cards(store, rng), theirs.cards(store, rng)];
    store.newGame(names: hotseat ? const ['Player 1', 'Player 2'] : [store.playerName == 'Player' ? 'Trainer' : store.playerName, 'Computer'], decks: decks, seed: seed, hotseat: hotseat);
    _push(const PokemonTable());
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => pokemonScope(screen))).then((_) {
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
        body: const Stack(
          children: [
            Positioned.fill(child: MeadowBackdrop()),
            Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    }
    final (ok, total) = store.coverage;
    final saved = store.savedGame;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: Text('Pokémon TCG', style: t.display(26, color: Colors.black)),
        backgroundColor: t.accent,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: MeadowBackdrop()),
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
                        if (store.resume() != null) _push(const PokemonTable());
                      },
                    ),
                    const SizedBox(height: 14),
                  ],
                  ThemedPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PokemonDeckChooser(label: 'Your deck', value: mine, onChanged: (c) => setState(() => mine = c)),
                        const SizedBox(height: 14),
                        PokemonDeckChooser(label: 'Opponent’s deck', value: theirs, onChanged: (c) => setState(() => theirs = c)),
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
                    onPressed: () => _push(PokemonRemoteLobby(deck: mine)),
                  ),
                  const SizedBox(height: 10),
                  if (nearbyPlaySupported) ...[
                    ThemedButton(
                      'Play nearby',
                      subtitle: 'Wi‑Fi or Bluetooth',
                      tall: true,
                      icon: Icons.wifi_tethering,
                      color: t.accent2,
                      onPressed: () => _push(PokemonLocalLobby(deck: mine)),
                    ),
                    const SizedBox(height: 10),
                  ],
                  ThemedButton('Two players, one device', tall: true, icon: Icons.people, outlined: true, onPressed: () => _start(hotseat: true)),
                  const SizedBox(height: 10),
                  ThemedButton('Cards', icon: Icons.collections, outlined: true, onPressed: () => _push(const PokemonCardsScreen())),
                  const SizedBox(height: 16),
                  ThemedPanel(
                    child: Text(
                      '$ok of $total Standard cards (regulation marks H–J) fully supported. Decks use only supported cards.\n\n'
                      'How to win: Knock Out your opponent’s Pokémon to take Prize cards. Take all 6, Knock Out their last Pokémon in play, or leave them with no cards to draw.',
                      style: t.style(13, weight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Unofficial fan project. Not produced by, endorsed by, supported by or affiliated with Nintendo, The Pokémon Company, Creatures Inc. or GAME FREAK inc. '
                    'Pokémon and all card names, text and images are © and ™ of their respective owners. Card images are loaded from pokemontcg.io. Free, with no payments.',
                    style: t.style(11, weight: FontWeight.w500, color: Colors.black87),
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
