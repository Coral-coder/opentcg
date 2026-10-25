part of 'ir.dart';

// ---------------------------------------------------------------------------------------------
// Effects on cards in the deck, hand, discard and inkwell, and on what players know (CR 7).
// Parsed in parser/zones.dart, resolved in game/zones.dart.
// ---------------------------------------------------------------------------------------------

/// Where a card goes.
enum ZoneDest {
  hand,
  top,
  bottom,

  /// The player picks top or bottom ("put it on either the top or the bottom of your deck").
  topOrBottom,

  /// The player picks the top of the deck or the discard ("put it on top of their deck or into
  /// their discard").
  topOrDiscard,
  inkwell,
  discard,

  /// Played for free (CR 6.1.7).
  play,

  /// Shuffled into the deck.
  shuffle,
}

sealed class ZoneEffect extends Effect {
  const ZoneEffect();
}

/// One part of sorting cards looked at: which, how many, where they go, and what follows.
class PeekPick {
  const PeekPick({this.filters = const [], this.count = 1, this.anyNumber = false, this.optional = true, this.dest = ZoneDest.hand, this.exerted = false, this.named = false, this.then});

  /// A card matching any of these; empty: any card.
  final List<Filter> filters;
  final int count;
  final bool anyNumber;

  /// "You may reveal…": fewer (none) may be taken.
  final bool optional;
  final ZoneDest dest;

  /// Enters play (or the inkwell) exerted.
  final bool exerted;

  /// "If it's the named card" (after [NameCard]).
  final bool named;

  /// What happens if a card was taken ("put it into your hand and gain 2 lore").
  final Effect? then;
}

/// Look at or reveal the top [n] cards of a deck and sort them (CR 7.2): [picks] in order, then
/// the rest to [rest]. "Reveal the top card. If it's a X card, put it into your hand. Otherwise,
/// put it on the bottom" is a one-card peek with one pick.
class Peek extends ZoneEffect {
  const Peek(this.n, {this.who = Who.you, this.picks = const [], this.rest = ZoneDest.bottom, this.ownerDecides = false, this.reveal = false});
  final int n;

  /// Whose deck.
  final Who who;
  final List<PeekPick> picks;
  final ZoneDest rest;

  /// "They may put it into their hand": the deck's owner decides, not the controller.
  final bool ownerDecides;

  /// Revealed to all players (logged), not just looked at.
  final bool reveal;
}

/// "Name a card": remembered for "the named card" later in the effect.
class NameCard extends ZoneEffect {
  const NameCard();
}

/// "Chosen opponent reveals their hand" / "look at each opponent's hand", optionally followed by
/// "and discards a [filter] card of your choice".
class RevealHand extends ZoneEffect {
  const RevealHand(this.who, {this.discard});
  final Who who;
  final Filter? discard;
}

/// "Each player may draw a card", "each opponent may choose and discard a card": each player
/// decides, and [effect] happens as theirs. With [lorePerRefusal], you gain that much lore for
/// each one who doesn't ("for each opponent who doesn't, you gain 2 lore").
class EachMay extends ZoneEffect {
  const EachMay(this.who, this.effect, {this.lorePerRefusal = 0});
  final Who who;
  final Effect effect;
  final int lorePerRefusal;
}

/// Put the top [n] cards of each [who]'s deck into their inkwell facedown.
class InkFromDeck extends ZoneEffect {
  const InkFromDeck(this.who, this.n, {this.exerted = false});
  final Who who;
  final int n;
  final bool exerted;
}

/// "Ready all cards in your inkwell".
class ReadyInkwell extends ZoneEffect {
  const ReadyInkwell(this.who);
  final Who who;
}

/// Cards from a discard to the hand, the deck or the inkwell. [all] takes every match; else the
/// controller picks [count] (or up to it). [named]: only cards with the named name.
class FromDiscard extends ZoneEffect {
  const FromDiscard(this.filter, {this.who = Who.you, this.count = 1, this.upTo = false, this.all = false, this.dest = ZoneDest.hand, this.exerted = false, this.named = false});
  final Filter filter;
  final Who who;
  final int count;
  final bool upTo, all;
  final ZoneDest dest;
  final bool exerted;
  final bool named;
}

/// "Put the top card of your deck facedown under one of your characters or locations with
/// Boost" (CR 8.4.2).
class PutUnder extends ZoneEffect {
  const PutUnder(this.filter);
  final Filter filter;
}

/// The cards under [target] go to [dest] ("put all cards from under her into your hand").
class UnderTo extends ZoneEffect {
  const UnderTo(this.target, this.dest, {this.random = false});
  final Target target;
  final ZoneDest dest;
  final bool random;
}

/// "Pay N {i}" as part of an effect ("you may pay 2 {i} to draw a card"): pays if it can, and
/// "if you do" follows whether it did (CR 6.1.5.1).
class PayInk extends ZoneEffect {
  const PayInk(this.n);
  final int n;
}

/// "Draw cards until you have the same number as [who]" (CR 6.1.8.1).
class DrawToMatch extends ZoneEffect {
  const DrawToMatch(this.who);
  final Who who;
}

// ---------------------------------------------------------------------------------------------
// Conditions about zones
// ---------------------------------------------------------------------------------------------

sealed class ZoneCond extends Cond {
  const ZoneCond();
}

/// "If an opponent has more cards in their hand than you" (any of [who] compared with you).
class CompareZone extends ZoneCond {
  const CompareZone(this.who, this.place, this.cmp);
  final Who who;
  final Place place;
  final Cmp cmp;
}

/// "If there's a card under this character".
class HasUnder extends ZoneCond {
  const HasUnder();
}
