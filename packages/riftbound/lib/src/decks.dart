/// Deck rules (CR 101–103, 487.4) and decks built from the cards the engine supports.
library;

import 'package:tcg_core/tcg_core.dart';

import 'cards/card.dart';
import 'cards/card_db.dart';
import 'ir.dart';
import 'parser/parser.dart';

/// A deck's Champion Legend.
RCard? deckLegend(RCardDb db, List<String> keys) {
  for (final k in keys) {
    if (db[k]?.type == CardType.legend) return db[k];
  }
  return null;
}

/// Does [c] fit [legend]'s Domain Identity (CR 103.2.b)?
bool inIdentity(RCard c, RCard legend) => c.domains.every(legend.domains.contains);

/// Problems that make a deck illegal for 1v1 Duel, or that the engine can't play; empty if fine.
List<String> validateDeck(RCardDb db, List<String> keys, {bool supportedOnly = true}) {
  final out = <String>[];
  final legends = [for (final k in keys) if (db[k]?.type == CardType.legend) k];
  if (legends.length != 1) {
    out.add('A deck needs exactly one Champion Legend (it has ${legends.length}).');
    return out;
  }
  final legend = db[legends.first]!;
  final main = [for (final k in keys) if (db[k]?.isMainDeck ?? false) k];
  final runes = [for (final k in keys) if (db[k]?.type == CardType.rune) k];
  final bfs = [for (final k in keys) if (db[k]?.type == CardType.battlefield) k];
  final unknown = [for (final k in keys) if (db[k] == null) k];
  if (unknown.isNotEmpty) out.add('Unknown cards: ${unknown.take(3).join(', ')}');
  final champ = main.where((k) => db[k]!.champion && db[k]!.type == CardType.unit && legend.tags.any(db[k]!.hasTag)).firstOrNull;
  if (champ == null) out.add('A deck needs a Chosen Champion: a champion unit with the tag ${legend.tags.join('/')} (CR 103.3.a).');
  if (main.length < 40) out.add('The Main Deck needs at least 40 cards, Chosen Champion included (it has ${main.length}).');
  final counts = <String, int>{};
  for (final k in main) {
    counts[k] = (counts[k] ?? 0) + 1;
  }
  final over = [for (final e in counts.entries) if (e.value > copyLimit(db[e.key]!)) e.key]..sortStable((a, b) => a.compareTo(b));
  if (over.isNotEmpty) out.add('At most ${copyLimit(db[over.first]!)} cop${copyLimit(db[over.first]!) == 1 ? 'y' : 'ies'} of ${over.first}.');
  final off = [for (final k in counts.keys) if (!inIdentity(db[k]!, legend)) k]..sortStable((a, b) => a.compareTo(b));
  if (off.isNotEmpty) out.add('${off.first} is outside ${legend.name}’s domains.');
  final sig = main.where((k) => db[k]!.signature).toList();
  if (sig.length > 3) out.add('At most 3 Signature cards.');
  if (sig.any((k) => !legend.tags.any(db[k]!.hasTag))) out.add('Signature cards must share the legend’s champion tag.');
  if (runes.length != 12) out.add('The Rune Deck needs exactly 12 runes (it has ${runes.length}).');
  if (runes.any((k) => !inIdentity(db[k]!, legend))) out.add('Runes must be of the legend’s domains.');
  if (bfs.length != 3) out.add('A Duel deck brings 3 battlefields (it has ${bfs.length}).');
  if (bfs.toSet().length != bfs.length) out.add('Battlefields must have different names.');
  if (supportedOnly) {
    final unsupported = [
      for (final k in {...main, ...bfs, legend.key})
        if (db[k] != null && !RiftboundParser.parse(db[k]!).supported) k,
    ]..sortStable((a, b) => a.compareTo(b));
    if (unsupported.isNotEmpty) out.add('${unsupported.first} isn’t supported yet.');
  }
  return out;
}

/// How many copies of [c] a deck may hold: 3 (CR 103.2.c), 1 with [Unique] (CR 825.3.a), any
/// number when the card says so.
int copyLimit(RCard c) {
  final p = RiftboundParser.parse(c);
  if (p.abilities.any((a) => a is Static && a.passive is AnyNumberInDeck)) return 1 << 20;
  return p.has(Kw.unique) ? 1 : 3;
}

/// The champion units of [legend] the engine supports, best first.
List<RCard> championsFor(RCardDb db, RCard legend) => [
      for (final c in db.cards)
        if (c.type == CardType.unit && c.champion && legend.tags.any(c.hasTag) && inIdentity(c, legend) && RiftboundParser.parse(c).supported) c,
    ];

/// Supported Main Deck cards a deck with [legend] may use (no Signature cards, no tokens).
List<RCard> poolFor(RCardDb db, RCard legend) => [
      for (final c in db.cards)
        if (c.isMainDeck && !c.token && !c.signature && inIdentity(c, legend) && RiftboundParser.parse(c).supported) c,
    ];

/// Legends a full, supported deck can be built for.
List<RCard> playableLegends(RCardDb db) => [
      for (final c in db.cards)
        if (c.type == CardType.legend && RiftboundParser.parse(c).supported && championsFor(db, c).isNotEmpty && poolFor(db, c).length >= 14 && _supportedBattlefields(db).length >= 3) c,
    ];

List<RCard> _supportedBattlefields(RCardDb db) => [
      for (final c in db.cards)
        if (c.type == CardType.battlefield && RiftboundParser.parse(c).supported) c,
    ];

/// A legal, supported deck for [legend]: its champion, then 3 copies each of a spread of units,
/// spells and gear across the cost curve; 12 runes split between its domains; 3 battlefields.
/// With [rng] the picks are random, otherwise the same every time (a starter deck).
List<String> buildDeck(RCardDb db, RCard legend, {SeededRng? rng}) {
  final champs = championsFor(db, legend);
  if (champs.isEmpty) throw ArgumentError('No supported champion for ${legend.name}');
  final champ = rng == null ? champs.first : champs[rng.nextInt(champs.length)];
  final pool = poolFor(db, legend).where((c) => c.key != champ.key).toList();
  if (rng != null) {
    rng.shuffle(pool);
  } else {
    // A starter: units first, then by a sensible curve (2–5 cost), then name.
    int score(RCard c) => (c.type == CardType.unit ? 0 : (c.type == CardType.spell ? 100 : 200)) + ((c.energy - 3).abs() * 10);
    pool.sortStable((a, b) => score(a) != score(b) ? score(a) - score(b) : a.key.compareTo(b.key));
  }
  // About two thirds units.
  final units = pool.where((c) => c.type == CardType.unit).toList();
  final others = pool.where((c) => c.type != CardType.unit).toList();
  final picks = <RCard>[];
  var u = 0, o = 0;
  // Enough different cards to fill 40 at their copy limits.
  var room = 37;
  while (room > 0 && (u < units.length || o < others.length)) {
    final wantUnit = picks.length % 3 != 2;
    if ((wantUnit && u < units.length) || o >= others.length) {
      picks.add(units[u++]);
    } else {
      picks.add(others[o++]);
    }
    final n = copyLimit(picks.last);
    room -= n < 3 ? n : 3;
  }
  final main = <String>[for (var i = 0; i < 3; i++) champ.key];
  for (final c in picks) {
    final n = copyLimit(c);
    for (var i = 0; i < (n < 3 ? n : 3) && main.length < 40; i++) {
      main.add(c.key);
    }
  }
  final domains = legend.domains.isEmpty ? [Domain.fury] : legend.domains;
  final runes = [for (var i = 0; i < 12; i++) '${domains[i % domains.length].label} Rune'];
  final bfs = _supportedBattlefields(db);
  final chosen = <RCard>[];
  if (rng == null) {
    chosen.addAll(bfs.take(3));
  } else {
    final list = List.of(bfs);
    rng.shuffle(list);
    chosen.addAll(list.take(3));
  }
  return [legend.key, ...main, ...runes, for (final b in chosen) b.key];
}

/// A deck for each playable legend, keyed by the legend's name.
Map<String, List<String>> starterDecks(RCardDb db) => {for (final l in playableLegends(db)) l.key: buildDeck(db, l)};

/// A random supported deck: a random playable legend and random picks.
List<String> randomDeck(RCardDb db, SeededRng rng) {
  final legends = playableLegends(db);
  if (legends.isEmpty) throw StateError('No playable legend');
  return buildDeck(db, legends[rng.nextInt(legends.length)], rng: rng);
}
