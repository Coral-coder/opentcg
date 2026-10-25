/// Pokémon TCG cards: Pokémon, Trainers and Energy, with their printings (images).
library;

/// Pokémon and Energy types.
enum PType {
  grass('Grass'),
  fire('Fire'),
  water('Water'),
  lightning('Lightning'),
  psychic('Psychic'),
  fighting('Fighting'),
  darkness('Darkness'),
  metal('Metal'),
  dragon('Dragon'),
  fairy('Fairy'),
  colorless('Colorless');

  const PType(this.label);
  final String label;

  static PType? byLabel(String s) {
    for (final t in PType.values) {
      if (t.label.toLowerCase() == s.toLowerCase()) return t;
    }
    return null;
  }
}

enum Supertype { pokemon, trainer, energy }

enum Stage { basic, stage1, stage2 }

enum TrainerKind { item, supporter, stadium, tool }

/// One printing of a card: set, number, rarity and image.
class Printing {
  const Printing({required this.set, required this.number, required this.rarity, required this.image});
  final String set, number, rarity, image;
  List<Object> toJson() => [set, number, rarity, image];
  static Printing fromJson(List<dynamic> j) => Printing(set: j[0] as String, number: j[1] as String, rarity: j[2] as String, image: j[3] as String);
}

class Attack {
  const Attack({required this.name, required this.cost, required this.damage, this.mod = '', this.text = ''});
  final String name;
  final List<PType> cost;

  /// The printed damage number (0 if none) and its modifier: '', '+', '×' or '-'.
  final int damage;
  final String mod;
  final String text;

  List<Object> toJson() => [name, [for (final t in cost) t.index], damage, mod, text];
  static Attack fromJson(List<dynamic> j) => Attack(name: j[0] as String, cost: [for (final i in j[1] as List) PType.values[i as int]], damage: j[2] as int, mod: j[3] as String, text: j[4] as String);
}

class PAbility {
  const PAbility({required this.name, required this.text});
  final String name, text;
  List<Object> toJson() => [name, text];
  static PAbility fromJson(List<dynamic> j) => PAbility(name: j[0] as String, text: j[1] as String);
}

/// A card (one functional version; reprints are its printings).
class PCard {
  const PCard({
    required this.key,
    required this.name,
    required this.supertype,
    this.stage,
    this.trainer,
    this.basicEnergy = false,
    this.hp = 0,
    this.types = const [],
    this.evolvesFrom,
    this.abilities = const [],
    this.attacks = const [],
    this.weakness,
    this.resistance,
    this.resistanceAmount = 30,
    this.retreat = 0,
    this.ex = false,
    this.mega = false,
    this.tera = false,
    this.aceSpec = false,
    this.text = '',
    this.rules = const [],
    this.regulation = '',
    this.printings = const [],
  });

  /// Unique in the database: the name, plus the first printing when several cards share it.
  final String key;
  final String name;
  final Supertype supertype;
  final Stage? stage;
  final TrainerKind? trainer;
  final bool basicEnergy;
  final int hp;
  final List<PType> types;
  final String? evolvesFrom;
  final List<PAbility> abilities;
  final List<Attack> attacks;
  final PType? weakness, resistance;
  final int resistanceAmount;
  final int retreat;
  final bool ex, mega, tera, aceSpec;

  /// A Trainer's or Special Energy's effect text.
  final String text;

  /// Other printed rule texts (rule boxes, reminder lines).
  final List<String> rules;
  final String regulation;
  final List<Printing> printings;

  bool get isPokemon => supertype == Supertype.pokemon;
  bool get isTrainer => supertype == Supertype.trainer;
  bool get isEnergy => supertype == Supertype.energy;
  bool get isBasicPokemon => isPokemon && stage == Stage.basic;

  /// Prize cards an opponent takes for Knocking it Out (rule boxes: ex 2, Mega Evolution ex 3).
  int get prizeValue => mega && ex ? 3 : (ex ? 2 : 1);

  /// The type a Basic Energy provides.
  PType? get energyType => basicEnergy ? PType.byLabel(name.replaceAll(' Energy', '').replaceAll('Basic ', '')) : null;

  String get image => printings.isEmpty ? '' : printings.first.image;

  Map<String, dynamic> toJson() => {
        'k': key,
        'n': name,
        's': supertype.index,
        if (stage != null) 'st': stage!.index,
        if (trainer != null) 'tr': trainer!.index,
        if (basicEnergy) 'be': 1,
        if (hp > 0) 'hp': hp,
        if (types.isNotEmpty) 't': [for (final t in types) t.index],
        if (evolvesFrom != null) 'ef': evolvesFrom,
        if (abilities.isNotEmpty) 'ab': [for (final a in abilities) a.toJson()],
        if (attacks.isNotEmpty) 'at': [for (final a in attacks) a.toJson()],
        if (weakness != null) 'w': weakness!.index,
        if (resistance != null) 'r': resistance!.index,
        if (resistance != null && resistanceAmount != 30) 'ra': resistanceAmount,
        if (retreat > 0) 'rc': retreat,
        if (ex) 'ex': 1,
        if (mega) 'mg': 1,
        if (tera) 'te': 1,
        if (aceSpec) 'ace': 1,
        if (text.isNotEmpty) 'x': text,
        if (rules.isNotEmpty) 'ru': rules,
        if (regulation.isNotEmpty) 'rm': regulation,
        'p': [for (final p in printings) p.toJson()],
      };

  static PCard fromJson(Map<String, dynamic> j) => PCard(
        key: j['k'] as String,
        name: j['n'] as String,
        supertype: Supertype.values[j['s'] as int],
        stage: j['st'] == null ? null : Stage.values[j['st'] as int],
        trainer: j['tr'] == null ? null : TrainerKind.values[j['tr'] as int],
        basicEnergy: j['be'] == 1,
        hp: j['hp'] as int? ?? 0,
        types: [for (final i in (j['t'] as List?) ?? const []) PType.values[i as int]],
        evolvesFrom: j['ef'] as String?,
        abilities: [for (final a in (j['ab'] as List?) ?? const []) PAbility.fromJson(a as List)],
        attacks: [for (final a in (j['at'] as List?) ?? const []) Attack.fromJson(a as List)],
        weakness: j['w'] == null ? null : PType.values[j['w'] as int],
        resistance: j['r'] == null ? null : PType.values[j['r'] as int],
        resistanceAmount: j['ra'] as int? ?? 30,
        retreat: j['rc'] as int? ?? 0,
        ex: j['ex'] == 1,
        mega: j['mg'] == 1,
        tera: j['te'] == 1,
        aceSpec: j['ace'] == 1,
        text: j['x'] as String? ?? '',
        rules: [for (final r in (j['ru'] as List?) ?? const []) r as String],
        regulation: j['rm'] as String? ?? '',
        printings: [for (final p in (j['p'] as List?) ?? const []) Printing.fromJson(p as List)],
      );

  @override
  String toString() => key;
}
