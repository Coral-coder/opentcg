import 'dart:math' as math;

import 'package:flutter/material.dart' hide Ink;
import 'package:lorcana/lorcana.dart' show Ink;
import 'package:tcg_app/tcg_app.dart';

import 'lorcana_card.dart';

/// Lorcana's storybook look: midnight blue to violet, gold leaf, starlight. Drawn from scratch
/// (no logos, artwork or trade dress copied); the display face is Cinzel (SIL OFL, fonts/).
const enchantedTheme = GameTheme(
  id: 'enchanted',
  name: 'Enchanted',
  blurb: 'Midnight skies, gold leaf and starlight.',
  chrome: ChromeStyle.classic,
  backdrop: Backdrop.crystal,
  bg: Color(0xFF0A0B24),
  surface: Color(0xFF17183F),
  panel: Color(0xFF1C1B4A),
  text: Color(0xFFF7F1FF),
  muted: Color(0xFFC3BBE6),
  accent: Color(0xFFEBC66F),
  accent2: Color(0xFFB79CFF),
  accent3: Color(0xFF7FDDF0),
  danger: Color(0xFFFF6B83),
  ok: Color(0xFF79F0B4),
  highlight: Color(0xFFFFE592),
  buttonText: Color(0xFF1B1035),
  decor: [Color(0xFFEBC66F), Color(0xFFB79CFF), Color(0xFF7FDDF0)],
  mana: {},
  font: 'Philosopher',
  titleFont: 'Cinzel',
  fallback: ['Georgia', 'serif'],
  radius: 14,
  sound: SoundStyle(wave: 'bell', base: 1046, decay: 0.26),
);

const _gold = [Color(0xFFFFF0B8), Color(0xFFEBC66F), Color(0xFFB8862F), Color(0xFFF3D98A)];

/// Gives [child] the enchanted theme (palette, type and Material widgets). Every Lorcana screen,
/// dialog and sheet is wrapped in one, since each route sits outside the screen that opened it.
class LorcanaScope extends StatelessWidget {
  const LorcanaScope({super.key, required this.child});
  final Widget child;

  static ThemeData? _material;

  static ThemeData get material => _material ??= () {
        final t = enchantedTheme;
        final base = t.material();
        return base.copyWith(
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            foregroundColor: t.accent,
            elevation: 0,
            centerTitle: false,
            titleTextStyle: t.display(22, weight: FontWeight.w700, color: t.accent),
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: const Color(0xFF1E1A50),
            titleTextStyle: t.display(19, weight: FontWeight.w700, color: t.accent),
            contentTextStyle: t.body,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFB8862F), width: 1.5)),
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: Color(0xF2161540),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22)), side: BorderSide(color: Color(0xFFB8862F), width: 1.2)),
          ),
          textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: t.accent, textStyle: t.display(15, weight: FontWeight.w700))),
          chipTheme: ChipThemeData(backgroundColor: const Color(0xFF242063), labelStyle: t.style(13), side: const BorderSide(color: Color(0x55EBC66F))),
          dropdownMenuTheme: DropdownMenuThemeData(textStyle: t.style(14)),
          canvasColor: const Color(0xFF1E1A50),
        );
      }();

  @override
  Widget build(BuildContext context) => ThemeScope(theme: enchantedTheme, child: Theme(data: material, child: child));
}

/// Wraps a route's page in [LorcanaScope], over the night sky unless the page draws its own
/// ([sky] false); the page's Scaffold should then be transparent.
MaterialPageRoute<T> lorcanaRoute<T>(Widget page, {bool sky = true}) => MaterialPageRoute<T>(
      builder: (_) => LorcanaScope(
        child: sky ? ColoredBox(color: enchantedTheme.bg, child: Stack(children: [const Positioned.fill(child: EnchantedBackdrop()), Positioned.fill(child: page)])) : page,
      ),
    );

/// A Lorcana screen: the starry backdrop, a transparent app bar with a gold title, and [body].
class EnchantedScaffold extends StatelessWidget {
  const EnchantedScaffold({super.key, required this.title, required this.body, this.actions = const [], this.bottom});
  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => LorcanaScope(
        child: Scaffold(
          backgroundColor: enchantedTheme.bg,
          appBar: AppBar(title: EnchantedTitle(title, size: 22), actions: actions),
          extendBodyBehindAppBar: false,
          bottomNavigationBar: bottom,
          body: Stack(children: [const Positioned.fill(child: EnchantedBackdrop()), body]),
        ),
      );
}

/// Gold-leaf lettering in the display face.
class EnchantedTitle extends StatelessWidget {
  const EnchantedTitle(this.text, {super.key, this.size = 30, this.decorative = false, this.align});
  final String text;
  final double size;

  /// Cinzel Decorative, for the big title only.
  final bool decorative;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) {
    final style = enchantedTheme
        .display(size, weight: FontWeight.w700, color: Colors.white)
        .copyWith(fontFamily: decorative ? 'CinzelDecorative' : 'Cinzel', letterSpacing: size > 28 ? 1.5 : 0.5, shadows: [Shadow(color: const Color(0xFFEBC66F).withValues(alpha: 0.55), blurRadius: size * 0.5)]);
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => const LinearGradient(colors: _gold, stops: [0, 0.4, 0.75, 1], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(r),
      child: Text(text, style: style, textAlign: align, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}

/// A night sky that drifts slowly: violet and teal glows, twinkling stars and gold dust. Pure
/// decoration (the engine never sees it), so it may use the clock.
class EnchantedBackdrop extends StatefulWidget {
  const EnchantedBackdrop({super.key, this.animate = true});
  final bool animate;
  @override
  State<EnchantedBackdrop> createState() => _EnchantedBackdropState();
}

class _EnchantedBackdropState extends State<EnchantedBackdrop> with SingleTickerProviderStateMixin {
  // One loop of the sky. Everything in it moves by whole cycles per loop, so the end of a loop
  // matches its start and the sky never jumps.
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 120));

  @override
  void initState() {
    super.initState();
    if (widget.animate && !_disableAnimations) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _SkyPainter(_c), size: Size.infinite)));
}

/// Widget tests can't wait out a repeating animation (pumpAndSettle), so the sky and the
/// pulses hold still under the test binding.
bool _disableAnimationsSet = false;
bool get _disableAnimations => _disableAnimationsSet || WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');

/// Stops the backdrop's animation (for widget tests).
void disableEnchantedAnimations() => _disableAnimationsSet = true;

class _Star {
  _Star(math.Random r)
      : x = r.nextDouble(),
        y = r.nextDouble(),
        size = 0.4 + r.nextDouble() * r.nextDouble() * 2.2,
        phase = r.nextDouble() * math.pi * 2,
        speed = 20 + r.nextInt(40),
        drift = 1 + r.nextInt(2),
        gold = r.nextDouble() < 0.18;
  final double x, y, size, phase;
  /// Twinkles per loop.
  final int speed;

  /// Times the star crosses the sky per loop.
  final int drift;
  final bool gold;
}

final _stars = () {
  final r = math.Random(1928);
  return [for (var i = 0; i < 120; i++) _Star(r)];
}();

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final v = t.value * math.pi * 2;
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(colors: [Color(0xFF070821), Color(0xFF15124A), Color(0xFF2A1659)], stops: [0, 0.55, 1], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(rect));
    void glow(Offset c, double r, Color col) => canvas.drawCircle(c, r, Paint()..shader = RadialGradient(colors: [col, col.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)));
    final m = math.max(size.width, size.height);
    glow(Offset(size.width * (0.2 + 0.05 * math.sin(v)), size.height * 0.25), m * 0.45, const Color(0x337B4DFF));
    glow(Offset(size.width * (0.85 + 0.04 * math.cos(v)), size.height * 0.7), m * 0.5, const Color(0x2633C6E0));
    glow(Offset(size.width * 0.5, size.height * (1.05 + 0.03 * math.sin(v * 2))), m * 0.45, const Color(0x30EBC66F));
    final p = Paint();
    for (final s in _stars) {
      final tw = 0.55 + 0.45 * math.sin(v * s.speed + s.phase);
      final c = Offset(s.x * size.width, (s.y + t.value * s.drift) % 1 * size.height);
      p.color = (s.gold ? const Color(0xFFFFE6A0) : Colors.white).withValues(alpha: (0.25 + 0.6 * tw).clamp(0, 1));
      canvas.drawCircle(c, s.size * (0.8 + 0.3 * tw), p);
      if (s.size > 1.6) {
        // A four-point twinkle on the brightest stars.
        final l = s.size * 3.2 * tw;
        p.strokeWidth = 0.8;
        canvas.drawLine(c - Offset(l, 0), c + Offset(l, 0), p);
        canvas.drawLine(c - Offset(0, l), c + Offset(0, l), p);
      }
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => false;
}

/// A panel framed in gold leaf, with small diamond flourishes at the corners.
class GildedPanel extends StatelessWidget {
  const GildedPanel({super.key, required this.child, this.title, this.padding = const EdgeInsets.all(14), this.glow, this.radius = 16});
  final Widget child;
  final String? title;
  final EdgeInsets padding;

  /// A colored halo (an ink color, or the highlight for "your turn").
  final Color? glow;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = enchantedTheme;
    return CustomPaint(
      foregroundPainter: _FiligreePainter(radius),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(colors: [Color(0xE6221E5C), Color(0xE6151338)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: (glow ?? const Color(0xFF000000)).withValues(alpha: glow == null ? 0.45 : 0.55), blurRadius: glow == null ? 14 : 22, spreadRadius: glow == null ? 0 : 1)],
        ),
        child: title == null
            ? child
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Padding(padding: const EdgeInsets.only(bottom: 8), child: EnchantedTitle(title!, size: 18)),
                DefaultTextStyle(style: t.body, child: child),
              ]),
      ),
    );
  }
}

class _FiligreePainter extends CustomPainter {
  _FiligreePainter(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final gold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = const LinearGradient(colors: _gold, begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(Offset.zero & size);
    canvas.drawRRect(r.deflate(0.8), gold);
    canvas.drawRRect(r.deflate(4.5), gold..strokeWidth = 0.6);
    final fill = Paint()..color = const Color(0xFFEBC66F);
    for (final c in [Offset(radius * 0.55, radius * 0.55), Offset(size.width - radius * 0.55, radius * 0.55), Offset(radius * 0.55, size.height - radius * 0.55), Offset(size.width - radius * 0.55, size.height - radius * 0.55)]) {
      final d = Path()
        ..moveTo(c.dx, c.dy - 4)
        ..lineTo(c.dx + 3, c.dy)
        ..lineTo(c.dx, c.dy + 4)
        ..lineTo(c.dx - 3, c.dy)
        ..close();
      canvas.drawPath(d, fill);
    }
    // A small crest at the top center.
    if (size.width > 120) {
      final cx = size.width / 2;
      final crest = Path()
        ..moveTo(cx - 14, 0.8)
        ..quadraticBezierTo(cx - 6, 6, cx, 0.8)
        ..quadraticBezierTo(cx + 6, 6, cx + 14, 0.8);
      canvas.drawPath(crest, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFFF3D98A));
      canvas.drawCircle(Offset(cx, 5), 1.8, fill);
    }
  }

  @override
  bool shouldRepaint(_FiligreePainter old) => old.radius != radius;
}

/// A soft splash of ink behind a chip or a deck's colors.
class InkBlot extends StatelessWidget {
  const InkBlot({super.key, required this.inks, this.size = 36});
  final List<Ink> inks;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _SplashPainter([for (final i in inks) inkColors[i]!])));
}

class _SplashPainter extends CustomPainter {
  _SplashPainter(this.colors);
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    for (var k = 0; k < colors.length; k++) {
      final path = Path();
      const n = 11;
      for (var i = 0; i <= n; i++) {
        final a = i / n * math.pi * 2 + k * 0.9;
        final rr = r * (0.62 + 0.22 * math.sin(a * 3 + k) + 0.12 * math.cos(a * 5));
        final pt = c + Offset(math.cos(a), math.sin(a)) * rr * (colors.length > 1 ? 0.85 : 1) + (colors.length > 1 ? Offset(k == 0 ? -r * 0.18 : r * 0.18, 0) : Offset.zero);
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();
      canvas.drawPath(path, Paint()..shader = RadialGradient(colors: [Color.lerp(colors[k], Colors.white, 0.35)!, colors[k], colors[k].withValues(alpha: 0.75)]).createShader(Rect.fromCircle(center: c, radius: r)));
    }
  }

  @override
  bool shouldRepaint(_SplashPainter old) => old.colors.length != colors.length || !Iterable.generate(colors.length).every((i) => old.colors[i] == colors[i]);
}

/// A big gold call-to-action button that can pulse to draw the eye ("End turn" when nothing
/// else is left to do).
class GoldButton extends StatefulWidget {
  const GoldButton(this.label, {super.key, required this.onPressed, this.icon, this.pulse = false, this.subtitle, this.color});
  final String label;
  final String? subtitle;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool pulse;

  /// Instead of gold (e.g. an ink color).
  final Color? color;
  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(GoldButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.pulse && !_disableAnimations) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = enchantedTheme;
    final enabled = widget.onPressed != null;
    final base = widget.color;
    final colors = base == null ? const [Color(0xFFFFE9A8), Color(0xFFE2B657), Color(0xFFB98A33)] : [Color.lerp(base, Colors.white, 0.35)!, base, Color.lerp(base, Colors.black, 0.25)!];
    final fg = base == null || base.computeLuminance() > 0.4 ? const Color(0xFF241536) : Colors.white;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.scale(
        scale: 1 + 0.035 * _c.value,
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: colors[1].withValues(alpha: 0.35 + 0.45 * _c.value), blurRadius: 10 + 16 * _c.value, spreadRadius: 4 * _c.value)]),
          child: child,
        ),
      ),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: widget.subtitle == null ? widget.label : '${widget.label}, ${widget.subtitle}',
          onTap: widget.onPressed,
          excludeSemantics: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: widget.onPressed,
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(colors: colors, begin: Alignment.topCenter, end: Alignment.bottomCenter),
                  border: Border.all(color: const Color(0xFFFFF3C4), width: 1.2),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                  if (widget.icon != null) ...[Icon(widget.icon, color: fg, size: 22), const SizedBox(width: 8)],
                  Flexible(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      FittedBox(fit: BoxFit.scaleDown, child: Text(widget.label, maxLines: 1, style: t.display(17, weight: FontWeight.w700, color: fg))),
                      if (widget.subtitle != null) FittedBox(fit: BoxFit.scaleDown, child: Text(widget.subtitle!, maxLines: 1, style: t.style(12, color: fg.withValues(alpha: 0.8)))),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
