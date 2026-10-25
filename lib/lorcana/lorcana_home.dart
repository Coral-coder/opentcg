import 'dart:math';

import 'package:flutter/material.dart' hide Ink;
import 'package:lorcana/lorcana.dart';
import 'package:tcg_core/tcg_core.dart' show SeededRng;
import 'package:tcg_app/tcg_app.dart';

import 'lorcana_cards_screen.dart';
import 'lorcana_deck_choice.dart';
import 'lorcana_decks_screen.dart';
import 'lorcana_lobbies.dart';
import 'lorcana_store.dart';
import 'lorcana_table.dart';
import 'lorcana_theme.dart';

/// Lorcana's menu: play the computer or a friend on this device with saved, starter or random
/// decks; build decks and browse the cards.
class LorcanaHome extends StatefulWidget {
  const LorcanaHome({super.key});
  @override
  State<LorcanaHome> createState() => _LorcanaHomeState();
}

class _LorcanaHomeState extends State<LorcanaHome> {
  final store = LorcanaStore.shared;
  DeckChoice mine = const DeckChoice.random({Ink.amber, Ink.steel});
  DeckChoice theirs = const DeckChoice.random({Ink.ruby, Ink.sapphire});
  String? error;

  /// The sounds are synthesized once, as chimes (the table's sounds use them).
  static bool _soundReady = false;

  @override
  void initState() {
    super.initState();
    Console.shared.setStyle(enchantedTheme.sound);
    if (!_soundReady && Console.available) {
      _soundReady = true;
      Console.shared.init();
    }
    store.init().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object e) {
      if (mounted) setState(() => error = '$e');
    });
  }

  void _start({required bool hotseat}) {
    final seed = Random().nextInt(1 << 30);
    final rng = SeededRng(seed);
    final a = mine.cards(store, rng), b = theirs.cards(store, rng);
    if (a == null || b == null || mine.problem(store) != null || theirs.problem(store) != null) return;
    final decks = [a, b];
    store.newGame(names: hotseat ? const ['Player 1', 'Player 2'] : const ['You', 'Computer'], decks: decks, seed: seed, hotseat: hotseat);
    _openTable();
  }

  void _push(Widget screen) {
    Navigator.of(context).push(lorcanaRoute<void>(screen)).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openTable() {
    Navigator.of(context).push(lorcanaRoute<void>(const LorcanaTable(), sky: false)).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) => LorcanaScope(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final t = GameTheme.of(context);
    if (error != null) return Scaffold(backgroundColor: t.bg, body: Center(child: Text('Could not load the cards: $error', style: t.body)));
    if (!store.ready) {
      return Scaffold(backgroundColor: t.bg, body: Stack(children: [const Positioned.fill(child: EnchantedBackdrop()), Center(child: CircularProgressIndicator(color: t.accent))]));
    }
    final (ok, total) = store.coverage;
    final saved = store.savedGame;
    final playable = mine.problem(store) == null && theirs.problem(store) == null;
    return Scaffold(
      backgroundColor: t.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(),
      body: Stack(children: [
        const Positioned.fill(child: EnchantedBackdrop()),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                const SizedBox(height: 8),
                const _Crest(),
                const EnchantedTitle('Lorcana', size: 46, decorative: true, align: TextAlign.center),
                const SizedBox(height: 2),
                Text('Ink, quest and challenge — first to 20 lore', textAlign: TextAlign.center, style: t.style(15, weight: FontWeight.w500, color: t.muted)),
                const SizedBox(height: 20),
                if (saved != null) ...[
                  GoldButton('Resume the story', subtitle: 'Turn ${saved['turn'] ?? '?'} · ${(saved['names'] as List).join(' vs ')}', icon: Icons.auto_stories, onPressed: () {
                    if (store.resume() != null) _openTable();
                  }),
                  const SizedBox(height: 16),
                ],
                GildedPanel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    DeckChooser(label: 'Your deck', value: mine, onChanged: (c) => setState(() => mine = c)),
                    const SizedBox(height: 14),
                    DeckChooser(label: 'Opponent’s deck', value: theirs, onChanged: (c) => setState(() => theirs = c)),
                  ]),
                ),
                const SizedBox(height: 18),
                GoldButton('Play the computer', icon: Icons.auto_awesome, pulse: saved == null && playable, onPressed: playable ? () => _start(hotseat: false) : null),
                const SizedBox(height: 10),
                GoldButton('Play online with a code', subtitle: 'Browser or phone, anywhere', icon: Icons.public, color: const Color(0xFF7B5BD6), onPressed: () => _push(LorcanaRemoteLobby(deck: mine))),
                const SizedBox(height: 10),
                if (nearbyPlaySupported) ...[
                  GoldButton('Play nearby', subtitle: 'Wi‑Fi or Bluetooth', icon: Icons.wifi_tethering, color: const Color(0xFF7B5BD6), onPressed: () => _push(LorcanaLocalLobby(deck: mine))),
                  const SizedBox(height: 10),
                ],
                GoldButton('Two players, one device', icon: Icons.people, color: const Color(0xFF3E4C9E), onPressed: playable ? () => _start(hotseat: true) : null),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: GoldButton('Decks', icon: Icons.style, color: const Color(0xFF2E3A80), onPressed: () => _push(const LorcanaDecksScreen()))),
                  const SizedBox(width: 10),
                  Expanded(child: GoldButton('Cards', icon: Icons.collections, color: const Color(0xFF2E3A80), onPressed: () => _push(const LorcanaCardsScreen()))),
                ]),
                const SizedBox(height: 20),
                Text(
                  '$ok of $total cards fully supported.\n'
                  'An unofficial, free fan game. Not affiliated with, endorsed or sponsored by Disney or Ravensburger. Card names, text and images belong to their owners.',
                  textAlign: TextAlign.center,
                  style: t.style(12, weight: FontWeight.w500, color: t.muted),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A small storybook crest above the title: a star over a gold arch.
class _Crest extends StatelessWidget {
  const _Crest();
  @override
  Widget build(BuildContext context) => SizedBox(height: 54, child: CustomPaint(painter: _CrestPainter(), size: const Size(double.infinity, 54)));
}

class _CrestPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.62);
    final gold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFFEBC66F);
    canvas.drawArc(Rect.fromCircle(center: c, radius: 34), pi * 1.08, pi * 0.84, false, gold);
    canvas.drawArc(Rect.fromCircle(center: c, radius: 27), pi * 1.15, pi * 0.7, false, gold..strokeWidth = 0.8);
    final star = Path();
    for (var i = 0; i < 8; i++) {
      final r = i.isEven ? 13.0 : 3.6;
      final a = -pi / 2 + i * pi / 4;
      final p = Offset(size.width / 2 + cos(a) * r, size.height * 0.36 + sin(a) * r);
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    canvas.drawCircle(Offset(size.width / 2, size.height * 0.36), 16, Paint()..shader = RadialGradient(colors: [const Color(0x88FFE592), const Color(0x00FFE592)]).createShader(Rect.fromCircle(center: Offset(size.width / 2, size.height * 0.36), radius: 16)));
    canvas.drawPath(star, Paint()..color = const Color(0xFFFFF0B8));
  }

  @override
  bool shouldRepaint(_CrestPainter old) => false;
}
