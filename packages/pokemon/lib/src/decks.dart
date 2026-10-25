/// Deck rules (rulebook: "Building a Deck") and random decks of supported cards for the
/// computer and the chaos harness.
library;

import 'package:tcg_core/tcg_core.dart';

import 'cards/card.dart';
import 'cards/card_db.dart';
import 'parser/parser.dart';

/// Exactly 60 cards; at most 4 with the same name (Basic Energy excepted); at most 1 ACE SPEC;
/// at least 1 Basic Pokémon. Returns the problems (empty if legal).
List<String> validateDeck(PCardDb db, List<String> keys) {
  final out = <String>[];
  if (keys.length != 60) out.add('A deck has exactly 60 cards (this one has ${keys.length})');
  final byName = <String, int>{};
  final names = <String>[];
  var ace = 0, basics = 0;
  for (final k in keys) {
    final c = db[k];
    if (c == null) {
      out.add('Unknown card $k');
      continue;
    }
    if (c.aceSpec) ace++;
    if (c.isBasicPokemon) basics++;
    if (c.basicEnergy) continue;
    if (!byName.containsKey(c.name)) names.add(c.name);
    byName[c.name] = (byName[c.name] ?? 0) + 1;
  }
  for (final n in names) {
    if (byName[n]! > 4) out.add('At most 4 cards named $n (this deck has ${byName[n]})');
  }
  if (ace > 1) out.add('At most 1 ACE SPEC card (this deck has $ace)');
  if (basics == 0) out.add('A deck needs at least 1 Basic Pokémon');
  return out;
}

/// Types a random deck is built around.
const deckTypes = [PType.grass, PType.fire, PType.water, PType.lightning, PType.psychic, PType.fighting, PType.darkness, PType.metal];

/// A legal 60-card deck of fully supported cards: evolution lines of [type] (attacks costing
/// only [type] and Colorless), Trainers, and Basic Energy of [type].
List<String> randomDeck(PCardDb db, PType type, SeededRng rng) {
  bool ok(PCard c) => PokemonParser.parse(c).supported;
  bool fits(PCard c) => c.types.contains(type) && c.attacks.every((a) => a.cost.every((t) => t == type || t == PType.colorless));
  final basics = [for (final c in db.cards) if (c.isBasicPokemon && ok(c) && fits(c) && c.attacks.isNotEmpty) c];
  final energy = db.cards.firstWhere((c) => c.basicEnergy && c.energyType == type);
  final trainers = [for (final c in db.cards) if (c.isTrainer && c.trainer != TrainerKind.stadium && ok(c)) c];
  final deck = <String>[];
  final used = <String>[];
  var aceUsed = false;
  void add(PCard c, int n) {
    if (used.contains(c.name)) return;
    if (c.aceSpec) {
      if (aceUsed) return;
      aceUsed = true;
      n = 1;
    }
    used.add(c.name);
    for (var i = 0; i < n; i++) {
      deck.add(c.key);
    }
  }

  // Four lines: a Basic and whatever supported Pokémon evolve from it.
  for (var line = 0; line < 4 && basics.isNotEmpty; line++) {
    final b = basics[rng.nextInt(basics.length)];
    add(b, 4);
    final s1 = [for (final c in db.cards) if (c.evolvesFrom == b.name && ok(c) && fits(c)) c];
    if (s1.isEmpty) continue;
    final e1 = s1[rng.nextInt(s1.length)];
    add(e1, 3);
    final s2 = [for (final c in db.cards) if (c.evolvesFrom == e1.name && ok(c) && fits(c)) c];
    if (s2.isNotEmpty) add(s2[rng.nextInt(s2.length)], 2);
  }
  if (deck.isEmpty) throw StateError('No supported ${type.label} Basic Pokémon');
  for (var tries = 0; tries < 200 && deck.length < 46 && trainers.isNotEmpty; tries++) {
    final t = trainers[rng.nextInt(trainers.length)];
    final room = 46 - deck.length;
    add(t, room < 3 ? room : 3);
  }
  while (deck.length < 60) {
    deck.add(energy.key);
  }
  return deck;
}
