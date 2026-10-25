import 'dart:convert';
import 'dart:io';

import 'package:pokemon/pokemon.dart';

PCardDb? _db;

/// The full card database (built by bin/build_db.dart).
PCardDb get db => _db ??= PCardDb.fromJson(jsonDecode(File('../../data/pokemon-cards.json').readAsStringSync()) as Map<String, dynamic>);

const _g = PType.grass, _f = PType.fire, _w = PType.water, _c = PType.colorless;

/// Small made-up cards for rules tests, so they don't depend on the real card pool. Their
/// texts are real card wordings and go through the parser like any other.
final fixtures = PCardDb([
  const PCard(key: 'T Sprout', name: 'T Sprout', supertype: Supertype.pokemon, stage: Stage.basic, hp: 60, types: [_g], weakness: _f, retreat: 1, attacks: [
    Attack(name: 'Tackle', cost: [_c], damage: 20),
    Attack(name: 'Vine', cost: [_g, _g, _c], damage: 70),
  ]),
  const PCard(key: 'T Bloom', name: 'T Bloom', supertype: Supertype.pokemon, stage: Stage.stage1, evolvesFrom: 'T Sprout', hp: 120, types: [_g], weakness: _f, retreat: 2, attacks: [
    Attack(name: 'Leaf', cost: [_g], damage: 50),
  ]),
  const PCard(key: 'T Ember', name: 'T Ember', supertype: Supertype.pokemon, stage: Stage.basic, hp: 70, types: [_f], weakness: _w, retreat: 1, attacks: [
    Attack(name: 'Burn Up', cost: [_f], damage: 30),
    Attack(name: 'Scorch', cost: [_f], damage: 10, text: "Your opponent's Active Pokémon is now Burned."),
  ]),
  const PCard(key: 'T Puddle', name: 'T Puddle', supertype: Supertype.pokemon, stage: Stage.basic, hp: 90, types: [_w], weakness: PType.lightning, resistance: _g, retreat: 2, attacks: [
    Attack(name: 'Splash', cost: [_w], damage: 10),
  ]),
  const PCard(key: 'T Status', name: 'T Status', supertype: Supertype.pokemon, stage: Stage.basic, hp: 80, types: [_c], retreat: 1, attacks: [
    Attack(name: 'Poison Gas', cost: [_c], damage: 0, text: "Your opponent's Active Pokémon is now Poisoned."),
    Attack(name: 'Lullaby', cost: [_c], damage: 0, text: "Your opponent's Active Pokémon is now Asleep."),
    Attack(name: 'Stun', cost: [_c], damage: 0, text: "Your opponent's Active Pokémon is now Paralyzed."),
    Attack(name: 'Daze', cost: [_c], damage: 0, text: "Your opponent's Active Pokémon is now Confused."),
    Attack(name: 'Spray', cost: [_c], damage: 10, text: "This attack also does 20 damage to each of your opponent's Benched Pokémon. (Don't apply Weakness and Resistance for Benched Pokémon.)"),
  ]),
  const PCard(key: 'T Big ex', name: 'T Big ex', supertype: Supertype.pokemon, stage: Stage.basic, hp: 200, types: [_c], ex: true, retreat: 2, attacks: [
    Attack(name: 'Smash', cost: [_c], damage: 300),
  ], rules: ['Pokémon ex rule: When your Pokémon ex is Knocked Out, your opponent takes 2 Prize cards.']),
  const PCard(key: 'T Mega ex', name: 'T Mega ex', supertype: Supertype.pokemon, stage: Stage.basic, hp: 300, types: [_c], ex: true, mega: true, retreat: 3, attacks: [
    Attack(name: 'Mega Smash', cost: [_c], damage: 400),
  ], rules: ['Mega Evolution ex rule: When your Mega Evolution Pokémon ex is Knocked Out, your opponent takes 3 Prize cards.']),
  const PCard(key: 'T Tera ex', name: 'T Tera ex', supertype: Supertype.pokemon, stage: Stage.basic, hp: 200, types: [_c], ex: true, tera: true, retreat: 2, attacks: [
    Attack(name: 'Crystal', cost: [_c], damage: 30),
  ], rules: [
    'Tera: As long as this Pokémon is on your Bench, prevent all damage done to this Pokémon by attacks (both yours and your opponent\'s).',
    'Pokémon ex rule: When your Pokémon ex is Knocked Out, your opponent takes 2 Prize cards.',
  ]),
  const PCard(key: 'T Researcher', name: 'T Researcher', supertype: Supertype.trainer, trainer: TrainerKind.supporter, text: 'Draw 3 cards.'),
  const PCard(key: 'T Switch', name: 'T Switch', supertype: Supertype.trainer, trainer: TrainerKind.item, text: 'Switch your Active Pokémon with 1 of your Benched Pokémon.'),
  const PCard(key: 'T Cape', name: 'T Cape', supertype: Supertype.trainer, trainer: TrainerKind.tool, text: 'The Pokémon this card is attached to gets +100 HP.'),
  const PCard(key: 'T Stadium', name: 'T Stadium', supertype: Supertype.trainer, trainer: TrainerKind.stadium, text: 'Each player’s Pokémon get +10 HP.'),
  const PCard(key: 'Basic Grass Energy', name: 'Basic Grass Energy', supertype: Supertype.energy, basicEnergy: true),
  const PCard(key: 'Basic Fire Energy', name: 'Basic Fire Energy', supertype: Supertype.energy, basicEnergy: true),
  const PCard(key: 'Basic Water Energy', name: 'Basic Water Energy', supertype: Supertype.energy, basicEnergy: true),
]);

const grassE = 'Basic Grass Energy', fireE = 'Basic Fire Energy', waterE = 'Basic Water Energy';

/// An empty game in player 0's turn 3 (past everyone's first turn), with [deck] Energy in each
/// deck so nobody decks out and 6 Prize cards each.
Game emptyGame({int deck = 10, int active = 0, int turn = 3}) {
  final g = Game(fixtures, players: ['A', 'B'], seed: 1)..startEmpty(active: active, turn: turn);
  for (var p = 0; p < 2; p++) {
    g.fillDeck(p, grassE, deck);
    g.addPrizes(p, grassE, 6);
  }
  return g;
}

/// Answers the pending decision, checking it belongs to [player].
void answer(Game g, List<int> a, {int? player}) {
  final d = g.pending!.decision;
  if (player != null && d.player != player) throw StateError('Decision is for ${d.player}: ${d.prompt}');
  g.apply(AnswerMove(d.player, a));
}

/// Answers every pending decision with its default answer.
void answerAll(Game g) {
  for (var i = 0; i < 100 && g.pending != null; i++) {
    final d = g.pending!.decision;
    g.apply(AnswerMove(d.player, g.defaultAnswer(d)));
  }
}

/// Whether [m] is refused (and leaves the game as it was).
bool illegal(Game g, PMove m) {
  final before = g.fingerprint;
  try {
    g.apply(m);
    return false;
  } on PokemonError {
    if (g.fingerprint != before) throw StateError('A refused move changed the game');
    return true;
  }
}

/// A deck of [n] [pokemon] and Grass Energy for the rest.
List<String> deckOf(String pokemon, {int n = 4}) => [...List.filled(n, pokemon), ...List.filled(60 - n, grassE)];
