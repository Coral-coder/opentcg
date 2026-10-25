import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pokemon/pokemon.dart';
import 'package:tcg_app/tcg_app.dart';

/// The Pokémon screens' look: bright sky, sunny yellow and bold outlines. Drawn from scratch; no
/// logos, Poké Ball art or official interface assets.
const pokemonTheme = GameTheme(
  id: 'pokemon',
  name: 'Sunny Meadow',
  blurb: 'Bright sky, sunny yellow and bold outlines.',
  chrome: ChromeStyle.comic,
  backdrop: Backdrop.paper,
  bg: Color(0xFF8FD3FF),
  surface: Color(0xFFFFFFFF),
  panel: Color(0xFFFFFDF2),
  text: Color(0xFF15202B),
  muted: Color(0xFF51606E),
  accent: Color(0xFFFFCB05),
  accent2: Color(0xFF2A75BB),
  accent3: Color(0xFFE3350D),
  danger: Color(0xFFE3350D),
  ok: Color(0xFF2FB86E),
  highlight: Color(0xFFFF8A00),
  buttonText: Color(0xFF15202B),
  decor: [Color(0xFFFFCB05), Color(0xFF2A75BB), Color(0xFFE3350D)],
  mana: {},
  brightness: Brightness.light,
  font: 'Roboto',
  titleFont: 'Bangers',
  fallback: ['Arial', 'sans-serif'],
  letterSpacing: 0.2,
  radius: 4,
  sound: SoundStyle(wave: 'triangle', base: 784, decay: 0.09),
);

/// Puts a Pokémon screen under [pokemonTheme] (routes pushed from the game picker don't inherit
/// a theme set on the screen that pushed them).
Widget pokemonScope(Widget child) => ThemeScope(
  theme: pokemonTheme,
  child: Theme(data: _material, child: child),
);

final _material = pokemonTheme.material().copyWith(
  textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: pokemonTheme.accent2)),
  filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: pokemonTheme.accent2, foregroundColor: Colors.white)),
  appBarTheme: AppBarTheme(
    backgroundColor: pokemonTheme.accent,
    foregroundColor: Colors.black,
    titleTextStyle: pokemonTheme.display(24, color: Colors.black),
  ),
);

/// Energy and Pokémon type colors, for pips, frames and chips.
const typeColors = {
  PType.grass: Color(0xFF3DAA4A),
  PType.fire: Color(0xFFE8582A),
  PType.water: Color(0xFF2F8FE0),
  PType.lightning: Color(0xFFF5C800),
  PType.psychic: Color(0xFF9B5BC7),
  PType.fighting: Color(0xFFB8642E),
  PType.darkness: Color(0xFF34404D),
  PType.metal: Color(0xFF8E9AA6),
  PType.dragon: Color(0xFFB59A2B),
  PType.fairy: Color(0xFFE77DB4),
  PType.colorless: Color(0xFFD9D4C7),
};

/// A round Energy pip with the type's initial.
class TypePip extends StatelessWidget {
  const TypePip(this.type, {super.key, this.size = 16});
  final PType type;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = typeColors[type]!;
    return Tooltip(
      message: type.label,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c,
          border: Border.all(color: Colors.black87, width: size > 14 ? 1.5 : 1),
        ),
        child: Text(
          type == PType.colorless ? '★' : type.label[0],
          style: TextStyle(fontSize: size * 0.58, height: 1, fontWeight: FontWeight.w900, color: c.computeLuminance() > 0.5 ? Colors.black87 : Colors.white),
        ),
      ),
    );
  }
}

/// Behind the table and the menus: a sky with soft clouds over a rolling green meadow.
class MeadowBackdrop extends StatelessWidget {
  const MeadowBackdrop({super.key});
  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: CustomPaint(painter: _MeadowPainter(), size: Size.infinite),
  );
}

class _MeadowPainter extends CustomPainter {
  const _MeadowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(colors: [Color(0xFF6EC6FF), Color(0xFFBEE8FF)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(rect));
    // Sun.
    final sun = Offset(size.width * 0.86, size.height * 0.09);
    canvas.drawCircle(sun, 70, Paint()..color = const Color(0x33FFE680));
    canvas.drawCircle(sun, 38, Paint()..color = const Color(0xCCFFE680));
    // Clouds.
    final rng = math.Random(5);
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.8);
    for (var i = 0; i < 6; i++) {
      final c = Offset(rng.nextDouble() * size.width, size.height * (0.05 + 0.4 * rng.nextDouble()));
      final r = 18 + rng.nextDouble() * 22;
      canvas.drawCircle(c, r, cloud);
      canvas.drawCircle(c + Offset(r * 0.9, r * 0.2), r * 0.8, cloud);
      canvas.drawCircle(c + Offset(-r * 0.9, r * 0.25), r * 0.7, cloud);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(c.dx - r * 1.5, c.dy, r * 3.1, r * 0.8), Radius.circular(r * 0.4)), cloud);
    }
    // Meadow hills.
    for (final (y, color) in const [(0.72, Color(0xFF8BD66B)), (0.8, Color(0xFF63C152))]) {
      final path = Path()..moveTo(0, size.height);
      for (var x = 0.0; x <= size.width + 30; x += 30) {
        path.lineTo(x, size.height * y + math.sin(x / 140 + y * 9) * 18);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_MeadowPainter old) => false;
}
