import 'package:flutter/material.dart';
import 'package:mtg_ui/mtg_ui.dart';
import 'package:tcg_app/tcg_app.dart';

import 'lorcana/lorcana_home.dart';
import 'pokemon/pokemon_home.dart';
import 'riftbound/riftbound_home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OpenTcgApp());
}

/// One card game in the picker.
class GameEntry {
  const GameEntry({required this.id, required this.name, required this.blurb, required this.colors, this.open});
  final String id, name, blurb;
  final List<Color> colors;

  /// Opens the game's own app, or null while it isn't playable yet.
  final Widget Function()? open;
}

final games = <GameEntry>[
  GameEntry(
    id: 'mtg',
    name: 'Magic: The Gathering',
    blurb: 'Every card from Scryfall, the Comprehensive Rules, themes per set.',
    colors: const [Color(0xFFD9A441), Color(0xFF8C6239)],
    open: () => const OpenMtgApp(),
  ),
  GameEntry(
    id: 'lorcana',
    name: 'Disney Lorcana',
    blurb: 'Ink, quest and challenge: first to 20 lore, against the computer or a friend.',
    colors: const [Color(0xFF6A4FB3), Color(0xFF2E6FB8)],
    open: () => const LorcanaHome(),
  ),
  GameEntry(
    id: 'pokemon',
    name: 'Pokémon TCG',
    blurb: 'Attach Energy, evolve and attack: take all 6 Prize cards, against the computer or a friend.',
    colors: const [Color(0xFFFFCB05), Color(0xFF2A75BB)],
    open: () => const PokemonHome(),
  ),
  GameEntry(
    id: 'riftbound',
    name: 'Riftbound',
    blurb: 'Channel runes, send champions to the battlefields and score 8 points, against the computer or a friend.',
    colors: const [Color(0xFFC8AA6E), Color(0xFF0B3A50)],
    open: () => const RiftboundHome(),
  ),
];

class OpenTcgApp extends StatelessWidget {
  const OpenTcgApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Themes.classic;
    return ThemeScope(
      theme: theme,
      child: MaterialApp(
        title: 'OpenTCG',
        theme: theme.material(),
        debugShowCheckedModeBanner: false,
        home: const GamePicker(),
      ),
    );
  }
}

class GamePicker extends StatelessWidget {
  const GamePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(children: [
        Positioned.fill(child: TableBackdrop(theme: t)),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                const SizedBox(height: 32),
                Text('OpenTCG', textAlign: TextAlign.center, style: t.display(56, weight: FontWeight.w900, color: t.accent)),
                const SizedBox(height: 6),
                Text('Pick a game', textAlign: TextAlign.center, style: t.style(16, weight: FontWeight.w600, color: t.muted)),
                const SizedBox(height: 28),
                for (final g in games) ...[_GameTile(entry: g), const SizedBox(height: 14)],
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.entry});
  final GameEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final open = entry.open;
    return Opacity(
      opacity: open == null ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: open == null
              ? null
              : () {
                  Console.shared.play(Fx.confirm);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => open()));
                },
          child: Ink(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(colors: [for (final c in entry.colors) c.withValues(alpha: 0.85)]),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.name, style: t.display(24, weight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 4),
              Text(open == null ? '${entry.blurb} Coming soon.' : entry.blurb, style: t.style(14, weight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.9))),
            ]),
          ),
        ),
      ),
    );
  }
}
