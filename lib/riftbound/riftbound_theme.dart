import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:riftbound/riftbound.dart';
import 'package:tcg_app/tcg_app.dart';

/// The Riftbound screens' look: deep hextech blue, brushed gold and cyan light. Drawn from
/// scratch; no Riot, League of Legends or Riftbound logos or official interface assets.
const riftboundTheme = GameTheme(
  id: 'riftbound',
  name: 'Hextech',
  blurb: 'Deep blue, brushed gold and cyan light.',
  chrome: ChromeStyle.classic,
  backdrop: Backdrop.starfield,
  bg: Color(0xFF081420),
  surface: Color(0xFF0E2233),
  panel: Color(0xFF102A3D),
  text: Color(0xFFEFE6D2),
  muted: Color(0xFF9DB1BF),
  accent: Color(0xFFC8AA6E),
  accent2: Color(0xFF0AC8B9),
  accent3: Color(0xFF785A28),
  danger: Color(0xFFE5484D),
  ok: Color(0xFF3FC380),
  highlight: Color(0xFF0AC8B9),
  buttonText: Color(0xFF081420),
  decor: [Color(0xFFC8AA6E), Color(0xFF0AC8B9), Color(0xFF785A28)],
  mana: {},
  brightness: Brightness.dark,
  font: 'Roboto',
  titleFont: 'Antonio',
  fallback: ['Arial', 'sans-serif'],
  letterSpacing: 0.3,
  radius: 4,
  sound: SoundStyle(wave: 'square', base: 660, decay: 0.08),
);

/// Puts a Riftbound screen under [riftboundTheme] (routes pushed from the game picker don't
/// inherit a theme set on the screen that pushed them).
Widget riftboundScope(Widget child) => ThemeScope(
  theme: riftboundTheme,
  child: Theme(data: _material, child: child),
);

final _material = riftboundTheme.material().copyWith(
  textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: riftboundTheme.accent2)),
  filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: riftboundTheme.accent, foregroundColor: riftboundTheme.bg)),
  appBarTheme: AppBarTheme(
    backgroundColor: const Color(0xFF0B1B29),
    foregroundColor: riftboundTheme.accent,
    titleTextStyle: riftboundTheme.display(24, color: riftboundTheme.accent),
  ),
  dividerColor: const Color(0x33C8AA6E),
);

/// The six domains' colors (CR 134.2: Fury red, Calm green, Mind blue, Body orange, Chaos
/// purple, Order yellow).
const domainColors = {
  Domain.fury: Color(0xFFE0443C),
  Domain.calm: Color(0xFF3FB96B),
  Domain.mind: Color(0xFF3E8EE0),
  Domain.body: Color(0xFFF08A2E),
  Domain.chaos: Color(0xFF9B5DE0),
  Domain.order: Color(0xFFE8C547),
};

/// A small domain gem with its initial.
class DomainPip extends StatelessWidget {
  const DomainPip(this.domain, {super.key, this.size = 16});
  final Domain? domain;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = domain == null ? const Color(0xFFB8C4CC) : domainColors[domain]!;
    return Tooltip(
      message: domain?.label ?? 'Any domain',
      child: Transform.rotate(
        angle: math.pi / 4,
        child: Container(
          width: size * 0.82,
          height: size * 0.82,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c,
            border: Border.all(color: const Color(0xFF081420), width: 1.2),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Transform.rotate(
            angle: -math.pi / 4,
            child: Text(
              domain?.letter ?? '★',
              style: TextStyle(fontSize: size * 0.48, height: 1, fontWeight: FontWeight.w900, color: c.computeLuminance() > 0.45 ? const Color(0xFF081420) : Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// Behind the table and the menus: deep blue with a faint hex lattice and a soft cyan glow.
/// Still (no animation), so it costs a phone nothing after the first frame.
class HextechBackdrop extends StatelessWidget {
  const HextechBackdrop({super.key});
  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: RepaintBoundary(child: CustomPaint(painter: _HexPainter(), size: Size.infinite)),
  );
}

class _HexPainter extends CustomPainter {
  const _HexPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(colors: [Color(0xFF0B1F31), Color(0xFF061019)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(rect));
    void glow(Offset c, double r, Color col) => canvas.drawCircle(c, r, Paint()..shader = RadialGradient(colors: [col, col.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)));
    final m = math.max(size.width, size.height);
    glow(Offset(size.width * 0.5, size.height * 0.5), m * 0.55, const Color(0x220AC8B9));
    glow(Offset(size.width * 0.1, size.height * 0.05), m * 0.35, const Color(0x18C8AA6E));
    // A hex lattice.
    final line = Paint()
      ..color = const Color(0x14C8AA6E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const r = 28.0;
    final w = math.sqrt(3) * r;
    for (var row = 0; row * r * 1.5 < size.height + r; row++) {
      for (var col = 0; col * w < size.width + w; col++) {
        final cx = col * w + (row.isOdd ? w / 2 : 0);
        final cy = row * r * 1.5;
        final path = Path();
        for (var i = 0; i < 6; i++) {
          final a = math.pi / 6 + i * math.pi / 3;
          final p = Offset(cx + r * math.cos(a), cy + r * math.sin(a));
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        path.close();
        canvas.drawPath(path, line);
      }
    }
  }

  @override
  bool shouldRepaint(_HexPainter old) => false;
}

/// A gold-edged panel for the table's frames.
class HexPanel extends StatelessWidget {
  const HexPanel({super.key, required this.child, this.padding = const EdgeInsets.all(10), this.glow});
  final Widget child;
  final EdgeInsets padding;
  final Color? glow;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xE6102A3D), Color(0xE60A1B2A)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
      border: Border.all(color: glow ?? const Color(0x99C8AA6E), width: glow == null ? 1 : 2),
      borderRadius: BorderRadius.circular(6),
      boxShadow: glow == null ? null : [BoxShadow(color: glow!.withValues(alpha: 0.35), blurRadius: 12)],
    ),
    child: child,
  );
}
