import 'package:flutter/material.dart' hide Ink;
import 'package:lorcana/lorcana.dart';
import 'package:tcg_app/tcg_app.dart';

/// Ink colors, for frames and pips.
const inkColors = {
  Ink.amber: Color(0xFFE8B23A),
  Ink.amethyst: Color(0xFF7A4BA8),
  Ink.emerald: Color(0xFF2E9B5A),
  Ink.ruby: Color(0xFFC7313D),
  Ink.sapphire: Color(0xFF2E7BC4),
  Ink.steel: Color(0xFF8A96A3),
};

/// A Lorcana card: its image (shown whole), or a frame drawn from its text while the image loads
/// or when it can't. On the web the image is an HTML element, because the image servers don't
/// allow cross-origin reads (which only a canvas would need).
class LorcanaCardView extends StatelessWidget {
  const LorcanaCardView({super.key, required this.card, this.width = 120});
  final LCard card;
  final double width;

  @override
  Widget build(BuildContext context) {
    final h = width * 7 / 5;
    final url = card.printings.isEmpty ? '' : card.printings.last.image;
    final frame = _TextFrame(card: card, width: width);
    return SizedBox(
      width: width,
      height: h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.06),
        child: url.isEmpty
            ? frame
            : Image.network(
                url,
                fit: BoxFit.contain,
                webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                loadingBuilder: (context, child, progress) => progress == null ? child : frame,
                errorBuilder: (context, e, st) => frame,
              ),
      ),
    );
  }
}

class _TextFrame extends StatelessWidget {
  const _TextFrame({required this.card, required this.width});
  final LCard card;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final ink = card.inks.isEmpty ? const Color(0xFF555555) : inkColors[card.inks.first]!;
    final fs = (width * 0.085).clamp(7.0, 14.0);
    return Container(
      decoration: BoxDecoration(
        color: Color.lerp(ink, Colors.black, 0.55),
        border: Border.all(color: ink, width: width * 0.03),
        borderRadius: BorderRadius.circular(width * 0.06),
      ),
      padding: EdgeInsets.all(width * 0.05),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: fs * 1.8,
            height: fs * 1.8,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: card.inkable ? ink : Colors.black54, border: Border.all(color: Colors.white70)),
            child: Text('${card.cost}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: fs)),
          ),
          const SizedBox(width: 4),
          Expanded(child: Text(card.fullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.style(fs, weight: FontWeight.w800, color: Colors.white))),
        ]),
        const SizedBox(height: 4),
        Expanded(child: Text(card.text, overflow: TextOverflow.fade, style: t.style(fs * 0.85, weight: FontWeight.w500, color: Colors.white70))),
        if (card.strength != null || card.lore != null)
          Text(
            [if (card.strength != null) '${card.strength}⚔', if (card.willpower != null) '${card.willpower}⛨', if (card.lore != null) '${card.lore}◆'].join('  '),
            style: t.style(fs, weight: FontWeight.w900, color: Colors.white),
          ),
      ]),
    );
  }
}
