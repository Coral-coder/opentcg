/// Deck building (CR 1.10.1.1): at least 60 cards, at most two ink types, at most 4 of a full
/// name.
library;

import 'package:tcg_core/tcg_core.dart';

import 'cards/card.dart';
import 'cards/card_db.dart';
import 'ir.dart';
import 'parser/parser.dart';

/// Problems with [deck] for Constructed play, empty when it's legal.
List<String> validateDeck(LCardDb db, List<String> deck, {bool supportedOnly = true}) {
  final out = <String>[];
  if (deck.length < 60) out.add('A deck needs at least 60 cards (${deck.length} now).');
  final counts = <String, int>{};
  final inks = <Ink>{};
  final anyInk = w1AnyInkClasses([
    for (final n in deck)
      if (db[n] != null) ...LorcanaParser.parse(db[n]!).abilities,
  ]);
  for (final n in deck) {
    final c = db[n];
    if (c == null) {
      out.add('Unknown card: $n');
      continue;
    }
    counts[c.fullName] = (counts[c.fullName] ?? 0) + 1;
    if (!w1InkExempt(c, anyInk, LorcanaParser.parse(c).abilities)) inks.addAll(c.inks);
    if (supportedOnly && !LorcanaParser.parse(c).supported) out.add('${c.fullName} isn’t fully supported yet.');
  }
  if (inks.length > 2) out.add('At most two ink types (${inks.map((i) => i.label).join(', ')}).');
  final names = counts.keys.toList()..sortStable((a, b) => a.compareTo(b));
  for (final n in names) {
    // "You may have up to 99 copies…" / "any number of cards named…" (CR 1.10.1.1 exception).
    final limit = LorcanaParser.parse(db[n]!).abilities.whereType<Static>().map((a) => a.effect).whereType<DeckLimit>().firstOrNull;
    final max = limit == null ? 4 : limit.max;
    if (max != null && counts[n]! > max) out.add('At most $max copies of $n (${counts[n]}).');
  }
  return out;
}

/// A random legal deck of supported cards in [inks] (seeded), 4 copies of each pick where
/// possible, about two thirds characters.
List<String> randomDeck(LCardDb db, Set<Ink> inks, SeededRng rng, {int size = 60}) {
  final pool = [
    for (final c in db.cards)
      if (c.inks.isNotEmpty && c.inks.every(inks.contains) && LorcanaParser.parse(c).supported) c,
  ];
  final chars = [
    for (final c in pool)
      if (c.type == CardType.character) c,
  ];
  final others = [
    for (final c in pool)
      if (c.type != CardType.character) c,
  ];
  final deck = <String>[];
  void take(List<LCard> from, int n) {
    if (from.isEmpty) return;
    while (n > 0) {
      final c = from[rng.nextInt(from.length)];
      final have = deck.where((x) => x == c.fullName).length;
      // "You may only have 2 copies of The Glass Slipper in your deck".
      final limit = LorcanaParser.parse(c).abilities.whereType<Static>().map((a) => a.effect).whereType<DeckLimit>().firstOrNull?.max;
      final add = ((limit != null && limit < 4 ? limit : 4) - have).clamp(0, n);
      for (var i = 0; i < add; i++) {
        deck.add(c.fullName);
      }
      n -= add;
      if (add == 0 && deck.toSet().length >= from.length) break;
    }
  }

  take(chars, size * 2 ~/ 3);
  take(others, size - deck.length);
  if (deck.length < size) take(chars, size - deck.length);
  return deck;
}

const inkPairs = <String, Set<Ink>>{
  'Amber/Amethyst': {Ink.amber, Ink.amethyst},
  'Amber/Steel': {Ink.amber, Ink.steel},
  'Amethyst/Ruby': {Ink.amethyst, Ink.ruby},
  'Amethyst/Sapphire': {Ink.amethyst, Ink.sapphire},
  'Emerald/Ruby': {Ink.emerald, Ink.ruby},
  'Emerald/Steel': {Ink.emerald, Ink.steel},
  'Ruby/Sapphire': {Ink.ruby, Ink.sapphire},
  'Sapphire/Steel': {Ink.sapphire, Ink.steel},
  'Amber/Emerald': {Ink.amber, Ink.emerald},
  'Amethyst/Steel': {Ink.amethyst, Ink.steel},
};
