/// A Riftbound card as the engine sees it: its printed characteristics (Core Rules 130–176) and
/// its rules text in a normalised form the parser reads.
library;

/// The six domains (CR 134.2), in the order of their shorthand letters R G B O P Y.
enum Domain {
  fury('R', 'Fury'),
  calm('G', 'Calm'),
  mind('B', 'Mind'),
  body('O', 'Body'),
  chaos('P', 'Chaos'),
  order('Y', 'Order');

  const Domain(this.letter, this.label);
  final String letter, label;

  static Domain? byName(String s) {
    for (final d in Domain.values) {
      if (d.label.toLowerCase() == s.toLowerCase() || d.letter == s) return d;
    }
    return null;
  }
}

/// Card types (CR 133). Tokens are units or gear made during play (CR 179).
enum CardType { unit, spell, gear, legend, battlefield, rune }

class Printing {
  const Printing(this.set, this.number, this.image);
  final String set, number, image;
  List<Object> toJson() => [set, number, image];
  static Printing fromJson(List<dynamic> j) => Printing(j[0] as String, j[1] as String, j[2] as String);
}

class RCard {
  const RCard({
    required this.name,
    required this.type,
    this.champion = false,
    this.signature = false,
    this.token = false,
    this.domains = const [],
    this.energy = 0,
    this.power = 0,
    this.might,
    this.tags = const [],
    this.text = '',
    this.printings = const [],
  });

  /// "Short Name, Subtitle" (CR 132.4).
  final String name;
  final CardType type;

  /// Supertypes (CR 133.7).
  final bool champion, signature;
  final bool token;
  final List<Domain> domains;

  /// Energy cost and the number of Power symbols (each one Power of the card's domain, CR 131).
  final int energy, power;
  final int? might;
  final List<String> tags;

  /// Rules text, one ability per line, reminder text removed, symbols as {N} (Energy),
  /// {R}{G}{B}{O}{P}{Y} (Power of a domain), {A} (any Power), {C} (this card's domain),
  /// {M} (Might) and {E} (exhaust).
  final String text;
  final List<Printing> printings;

  String get key => name;
  String get shortName => name.split(', ').first;
  bool hasTag(String t) => tags.any((x) => x.toLowerCase() == t.toLowerCase());
  String? get image => printings.isEmpty ? null : printings.first.image;
  bool get isPermanent => type == CardType.unit || type == CardType.gear;
  bool get isMainDeck => type == CardType.unit || type == CardType.gear || type == CardType.spell;

  Map<String, dynamic> toJson() => {
        'n': name,
        't': type.index,
        if (champion) 'ch': 1,
        if (signature) 'sg': 1,
        if (token) 'tk': 1,
        if (domains.isNotEmpty) 'd': [for (final d in domains) d.index],
        if (energy != 0) 'e': energy,
        if (power != 0) 'p': power,
        if (might != null) 'm': might,
        if (tags.isNotEmpty) 'g': tags,
        if (text.isNotEmpty) 'x': text,
        if (printings.isNotEmpty) 'pr': [for (final p in printings) p.toJson()],
      };

  static RCard fromJson(Map<String, dynamic> j) => RCard(
        name: j['n'] as String,
        type: CardType.values[j['t'] as int],
        champion: j['ch'] == 1,
        signature: j['sg'] == 1,
        token: j['tk'] == 1,
        domains: [for (final d in (j['d'] as List?) ?? const []) Domain.values[d as int]],
        energy: (j['e'] as int?) ?? 0,
        power: (j['p'] as int?) ?? 0,
        might: j['m'] as int?,
        tags: [for (final t in (j['g'] as List?) ?? const []) t as String],
        text: (j['x'] as String?) ?? '',
        printings: [for (final p in (j['pr'] as List?) ?? const []) Printing.fromJson(p as List)],
      );
}
