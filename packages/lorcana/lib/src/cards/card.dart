/// Lorcana cards (CR 5): one entry per full name, with all its printings.
library;

/// The six ink types (CR 5.2.5).
enum Ink {
  amber('Amber'),
  amethyst('Amethyst'),
  emerald('Emerald'),
  ruby('Ruby'),
  sapphire('Sapphire'),
  steel('Steel');

  const Ink(this.label);
  final String label;

  static Ink? parse(String s) {
    for (final i in Ink.values) {
      if (i.label.toLowerCase() == s.trim().toLowerCase()) return i;
    }
    return null;
  }
}

/// Card types (CR 5.3–5.6). Songs are actions with the Song classification (CR 5.4.4).
enum CardType { character, action, item, location }

/// One printing of a card: set, number, rarity and image.
class Printing {
  const Printing({required this.set, required this.number, required this.rarity, required this.image, this.artist = ''});
  final String set;
  final int number;
  final String rarity;
  final String image;
  final String artist;

  List<Object> toJson() => [set, number, rarity, image, artist];
  static Printing fromJson(List<dynamic> j) => Printing(set: j[0] as String, number: j[1] as int, rarity: j[2] as String, image: j[3] as String, artist: j.length > 4 ? j[4] as String : '');
}

class LCard {
  const LCard({
    required this.fullName,
    required this.type,
    required this.cost,
    required this.inkable,
    required this.inks,
    this.strength,
    this.willpower,
    this.lore,
    this.moveCost,
    this.classifications = const [],
    this.text = '',
    this.printings = const [],
    this.franchise = '',
  });

  /// "Name - Version" (CR 5.3.6.1); actions and items have only a name.
  final String fullName;
  final CardType type;
  final int cost;
  final bool inkable;
  final List<Ink> inks;
  final int? strength, willpower, lore, moveCost;
  final List<String> classifications;
  final String text;
  final List<Printing> printings;
  final String franchise;

  /// The name line without the version (CR 5.2.6).
  String get name {
    final i = fullName.indexOf(' - ');
    return i < 0 ? fullName : fullName.substring(0, i);
  }

  String get version {
    final i = fullName.indexOf(' - ');
    return i < 0 ? '' : fullName.substring(i + 3);
  }

  /// Every name the card has: "Flotsam & Jetsam" is also "Flotsam" and "Jetsam" (CR 5.2.6.1).
  List<String> get names {
    final n = name;
    final amp = RegExp(r' & | ’n‘ | ’n’ | \x27n\x27 ').hasMatch(n) ? n.split(RegExp(r' & | ’n‘ | ’n’ | \x27n\x27 ')) : const <String>[];
    return [n, ...amp];
  }

  bool get isSong => type == CardType.action && classifications.contains('Song');
  bool get isCharacter => type == CardType.character;
  bool hasClass(String c) => classifications.any((x) => x.toLowerCase() == c.toLowerCase());

  String? get image => printings.isEmpty ? null : printings.last.image;

  Map<String, dynamic> toJson() => {
    'n': fullName,
    't': type.index,
    'c': cost,
    if (inkable) 'i': 1,
    'k': [for (final i in inks) i.index],
    if (strength != null) 's': strength,
    if (willpower != null) 'w': willpower,
    if (lore != null) 'l': lore,
    if (moveCost != null) 'm': moveCost,
    if (classifications.isNotEmpty) 'cl': classifications,
    if (text.isNotEmpty) 'x': text,
    if (franchise.isNotEmpty) 'f': franchise,
    'p': [for (final p in printings) p.toJson()],
  };

  static LCard fromJson(Map<String, dynamic> j) => LCard(
    fullName: j['n'] as String,
    type: CardType.values[j['t'] as int],
    cost: j['c'] as int,
    inkable: j['i'] == 1,
    inks: [for (final i in j['k'] as List) Ink.values[i as int]],
    strength: j['s'] as int?,
    willpower: j['w'] as int?,
    lore: j['l'] as int?,
    moveCost: j['m'] as int?,
    classifications: ((j['cl'] as List?) ?? const []).cast<String>(),
    text: (j['x'] as String?) ?? '',
    franchise: (j['f'] as String?) ?? '',
    printings: [for (final p in (j['p'] as List?) ?? const []) Printing.fromJson(p as List)],
  );
}
