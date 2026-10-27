import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:riftbound/riftbound.dart';
import 'package:tcg_app/tcg_app.dart';

import 'riftbound_theme.dart';

/// The file name of [name]'s image in the website's riftbound-images/ folder: FNV-1a (32-bit)
/// of the UTF-8 name, as tool/riftbound_images.py writes it. Kept below 2^53 at every step so
/// the browser build computes the same key.
String riftboundImageKey(String name) {
  var h = 0x811C9DC5;
  for (final b in utf8.encode(name)) {
    h = (h ^ b) % 0x100000000;
    h = ((h & 0xFF) * 0x1000000 + h * 403) % 0x100000000;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// A Riftbound card: its image (shown whole), or a frame drawn from its text while the image
/// loads or when it can't. Battlefields are landscape.
///
/// On the web the image is the site's own copy (riftbound-images/), drawn on the canvas: Riot's
/// image server doesn't allow cross-origin reads, and an HTML image over the canvas costs a
/// full-screen layer each, which runs phones out of memory. Tokens have no image.
class RiftboundCardView extends StatelessWidget {
  const RiftboundCardView({super.key, required this.card, this.width = 110});
  final RCard card;
  final double width;

  bool get landscape => card.type == CardType.battlefield;

  @override
  Widget build(BuildContext context) {
    final h = landscape ? width * 0.716 : width * 1.396;
    final url = card.image ?? '';
    final frame = _TextFrame(card: card, width: width, height: h);
    Widget img;
    if (url.isEmpty || card.token) {
      img = frame;
    } else {
      img = Image.network(
        kIsWeb ? 'riftbound-images/${riftboundImageKey(card.name)}.webp' : url,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) => progress == null ? child : frame,
        errorBuilder: (context, e, st) => frame,
      );
    }
    return Semantics(
      label: card.name,
      image: true,
      child: SizedBox(
        width: width,
        height: h,
        child: ClipRRect(borderRadius: BorderRadius.circular(width * 0.05), child: img),
      ),
    );
  }
}

class _TextFrame extends StatelessWidget {
  const _TextFrame({required this.card, required this.width, required this.height});
  final RCard card;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final c = card.domains.isEmpty ? const Color(0xFF8A97A3) : domainColors[card.domains.first]!;
    final fs = (width * 0.085).clamp(7.0, 13.0);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Color.lerp(c, Colors.black, 0.55)!, const Color(0xFF0A1622)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        border: Border.all(color: const Color(0xFFC8AA6E), width: width * 0.02),
        borderRadius: BorderRadius.circular(width * 0.05),
      ),
      padding: EdgeInsets.all(width * 0.05),
      // Whatever doesn't fit is cut off at the bottom (small cards show little more than a name).
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxHeight: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (card.isMainDeck && !card.token)
                    Container(
                      width: fs * 1.8,
                      height: fs * 1.8,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF081420)),
                      child: Text('${card.energy}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: fs)),
                    ),
                  for (var i = 0; i < card.power; i++) DomainPip(card.domains.isEmpty ? null : card.domains.first, size: fs * 1.3),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(card.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.style(fs, weight: FontWeight.w800, color: Colors.white)),
                  ),
                ],
              ),
              if (card.might != null) Text('${card.might} Might', style: t.style(fs, weight: FontWeight.w900, color: const Color(0xFFC8AA6E))),
              const SizedBox(height: 3),
              Text(card.text, style: t.style(fs * 0.85, weight: FontWeight.w500, color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}
