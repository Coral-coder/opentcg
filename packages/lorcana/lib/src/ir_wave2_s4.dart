part of 'ir.dart';

// ---------------------------------------------------------------------------------------------
// Wave 2, slice 4 (Scrooge … Zipper): effects, amounts, conditions, statics and triggers the
// earlier grammar has no data for. Parsed in parser/wave2_s4.dart, resolved in game/wave2_s4.dart.
// Each class describes itself (describe.dart prints them through [S4Ir.describeWith]).
// ---------------------------------------------------------------------------------------------

/// Printing for the slice's IR: [d] describes nested effects, [f] filters.
abstract interface class S4Ir {
  String describeWith(String Function(Effect) d);
}

sealed class S4Effect extends Effect implements S4Ir {
  const S4Effect();
}

/// "Put a card from the top of your deck facedown under each of your other characters": one
/// card under each matching card while the deck lasts (CR 8.4.2); they're remembered in [slot]
/// ("those characters").
class PutUnderEach extends S4Effect {
  const PutUnderEach(this.filter, this.slot);
  final Filter filter;
  final int slot;
  @override
  String describeWith(String Function(Effect) d) => 'top of deck under each ${filter.describe()} #$slot';
}

/// "The player or players with the most cards in their hands choose and discard N cards."
class DiscardMost extends S4Effect {
  const DiscardMost(this.n);
  final int n;
  @override
  String describeWith(String Function(Effect) d) => 'players with most cards in hand discard $n';
}

/// "Reveal the top card of your deck. If it's a X card, put it into your hand and repeat this
/// effect. Otherwise, put it on either the top or the bottom of your deck."
class RevealRepeat extends S4Effect {
  const RevealRepeat(this.filters);
  final List<Filter> filters;
  @override
  String describeWith(String Function(Effect) d) => 'reveal top until not ${filters.map((f) => f.describe()).join(' or ')} (to hand), last → top or bottom';
}

/// "[Effect] unless their player pays N {i}": the owner of [payerOf] decides (CR 6.1.16).
class UnlessPays extends S4Effect {
  const UnlessPays(this.payerOf, this.ink, this.effect);
  final Target payerOf;
  final int ink;
  final Effect effect;
  @override
  String describeWith(String Function(Effect) d) => '${d(effect)} unless its player pays $ink';
}

/// "Choose and discard a X card [from your hand]": one card matching any of [filters] (any
/// inkable card with [inkable]); its printed lore is kept for "the discarded character's {l}".
class DiscardMatching extends S4Effect {
  const DiscardMatching(this.filters, {this.inkable = false});
  final List<Filter> filters;
  final bool inkable;
  @override
  String describeWith(String Function(Effect) d) => 'discard ${inkable ? 'inkable card' : filters.map((f) => f.describe()).join(' or ')}';
}

/// "Play this character for free [and he enters play exerted]" from wherever it is (CR 6.1.12).
class PlaySelfFree extends S4Effect {
  const PlaySelfFree({this.exerted = false});
  final bool exerted;
  @override
  String describeWith(String Function(Effect) d) => 'play this free${exerted ? ' exerted' : ''}';
}

/// "You may play those characters from your discard for free": the character cards that were
/// under the banished card.
class PlayUnderFromDiscard extends S4Effect {
  const PlayUnderFromDiscard();
  @override
  String describeWith(String Function(Effect) d) => 'play character cards that were under it from discard free';
}

/// "Exert all cards in your inkwell".
class S4ExertInkwell extends S4Effect {
  const S4ExertInkwell();
  @override
  String describeWith(String Function(Effect) d) => 'exert your inkwell';
}

/// Makes the choice for [target] now and notes how many cards were under the chosen card ("if
/// that character had a card under them", asked after it left play).
class ChooseNow extends S4Effect {
  const ChooseNow(this.target);
  final Target target;
  @override
  String describeWith(String Function(Effect) d) => 'choose ${target is Chosen ? (target as Chosen).filter.describe() : 'it'}';
}

/// "You may play or shift a X for free" (CR 6.1.7, 8.10).
class PlayOrShiftFree extends S4Effect {
  const PlayOrShiftFree(this.filter);
  final Filter filter;
  @override
  String describeWith(String Function(Effect) d) => 'play or shift ${filter.describe()} free';
}

/// "Search your deck for a X card and reveal it to all players. Put that card into your hand
/// and shuffle your deck."
class SearchDeck extends S4Effect {
  const SearchDeck(this.filters);
  final List<Filter> filters;
  @override
  String describeWith(String Function(Effect) d) => 'search deck for ${filters.map((f) => f.describe()).join(' or ')} → hand, shuffle';
}

/// "Look at the top N cards of your deck. Put any number of them on the top or the bottom of
/// your deck in any order."
class PeekSplit extends S4Effect {
  const PeekSplit(this.n);
  final int n;
  @override
  String describeWith(String Function(Effect) d) => 'look at top $n, any to bottom, rest top';
}

/// "Chosen opponent chooses 3 of their characters and returns one of those cards to their hand,
/// puts one on the bottom of their deck, and puts one on the top of their deck."
class ScatterThree extends S4Effect {
  const ScatterThree();
  @override
  String describeWith(String Function(Effect) d) => 'chosen opponent picks 3 characters: hand, deck bottom, deck top';
}

/// "Each player draws N cards, then discards N cards at random": counts the action cards
/// discarded ("for each action card discarded this way").
class DrawThenDiscardRandom extends S4Effect {
  const DrawThenDiscardRandom(this.who, this.draw, this.discard);
  final Who who;
  final int draw, discard;
  @override
  String describeWith(String Function(Effect) d) => '${who.name} draw $draw then discard $discard at random';
}

/// "Look at the top N cards of your deck. You may reveal an item card and put it into your hand.
/// If that item costs C or less, you may play it for free instead and it enters play exerted.
/// Put the rest on the bottom of your deck in any order."
class PeekItemOrPlay extends S4Effect {
  const PeekItemOrPlay(this.n, this.costMax);
  final int n, costMax;
  @override
  String describeWith(String Function(Effect) d) => 'look at top $n, may take item (cost≤$costMax: may play free exerted), rest bottom';
}

/// "Choose N cards from chosen opponent's discard and put them on the bottom of their deck to
/// gain L lore. If any [Princess] cards were moved this way, gain M lore instead."
class DiscardToBottomForLore extends S4Effect {
  const DiscardToBottomForLore(this.n, this.lore, this.cls, this.loreIf);
  final int n, lore, loreIf;
  final String cls;
  @override
  String describeWith(String Function(Effect) d) => '$n from chosen opponent\'s discard → bottom, gain $lore ($loreIf if $cls)';
}

/// "For each X, you may draw a card": the player picks how many, up to the count.
class MayDrawUpTo extends S4Effect {
  const MayDrawUpTo(this.amount);
  final Amount amount;
  @override
  String describeWith(String Function(Effect) d) => 'may draw up to N';
}

/// "Each opponent loses N lore": the lore actually lost is kept ("the lore lost", "for each 1
/// lore lost this way").
class LoseLoreCounted extends S4Effect {
  const LoseLoreCounted(this.who, this.amount);
  final Who who;
  final Amount amount;
  @override
  String describeWith(String Function(Effect) d) => '${who.name} lose lore (counted)';
}

/// "Your Pirate characters gain "{e} - Banish chosen damaged character" this turn".
class GrantAbilityFor extends S4Effect {
  const GrantAbilityFor(this.target, this.ability, this.duration);
  final Target target;
  final Activated ability;
  final Lasting duration;
  @override
  String describeWith(String Function(Effect) d) => 'grant "${ability.text}" (${duration.name})';
}

/// "Choose a character of yours. While this item is in play, that character gains Evasive."
class GrantWhileInPlay extends S4Effect {
  const GrantWhileInPlay(this.target, this.keyword);
  final Target target;
  final Keyword keyword;
  @override
  String describeWith(String Function(Effect) d) => 'chosen gains ${keyword.key} while this is in play';
}

/// "Move them to another location for free".
class MoveToAnotherLocation extends S4Effect {
  const MoveToAnotherLocation(this.character);
  final Target character;
  @override
  String describeWith(String Function(Effect) d) => 'move to another location free';
}

/// "You may play that song again from your discard for free. If you do, put that card on the
/// bottom of your deck instead of into your discard" (CR 6.1.11 example).
class ReplaySong extends S4Effect {
  const ReplaySong();
  @override
  String describeWith(String Function(Effect) d) => 'replay sung song from discard free, then deck bottom';
}

/// "Play a song with cost equal to or less than the exerted character's cost for free".
class PlayFreeUpToCostOf extends S4Effect {
  const PlayFreeUpToCostOf(this.filter, this.costOf);
  final Filter filter;
  final Target costOf;
  @override
  String describeWith(String Function(Effect) d) => 'play ${filter.describe()} with cost ≤ that card\'s free';
}

/// "Each opponent may choose and discard a card. For each opponent who doesn't, you draw a
/// card."
class EachMayElse extends S4Effect {
  const EachMayElse(this.who, this.effect, this.perRefusal);
  final Who who;
  final Effect effect, perRefusal;
  @override
  String describeWith(String Function(Effect) d) => 'each ${who.name} may ${d(effect)}; per refusal: ${d(perRefusal)}';
}

/// "You may play a character with the same name as that character for free" ([slot] holds it).
class PlaySameNameFree extends S4Effect {
  const PlaySameNameFree(this.slot);
  final int slot;
  @override
  String describeWith(String Function(Effect) d) => 'play same-named character free';
}

/// "Put any number of cards from under your characters and locations into your inkwell
/// facedown and exerted."
class UnderToInkwell extends S4Effect {
  const UnderToInkwell();
  @override
  String describeWith(String Function(Effect) d) => 'any cards from under yours → inkwell exerted';
}

/// "Shuffle chosen card from your discard into your deck. Reveal the top card of your deck. If
/// it has the same name as the chosen card, you may play the revealed card for free. Otherwise,
/// put it into your hand."
class ShuffleRevealSameName extends S4Effect {
  const ShuffleRevealSameName();
  @override
  String describeWith(String Function(Effect) d) => 'shuffle chosen discard card in, reveal top: same name → may play free, else hand';
}

/// "Return a X card from your discard to your hand", remembering it in [slot] ("if that card
/// is…").
class ReturnFromDiscardAs extends S4Effect {
  const ReturnFromDiscardAs(this.filter, this.slot);
  final Filter filter;
  final int slot;
  @override
  String describeWith(String Function(Effect) d) => 'return ${filter.describe()} from discard #$slot';
}

/// "You may play him for free": the card in [slot], from the hand.
class PlaySlotFree extends S4Effect {
  const PlaySlotFree(this.slot);
  final int slot;
  @override
  String describeWith(String Function(Effect) d) => 'play #$slot free';
}

/// "Banish all characters with {s} equal to or less than the {s} he had in play" (CR 6.7.7).
class BanishUpToEventStrength extends S4Effect {
  const BanishUpToEventStrength();
  @override
  String describeWith(String Function(Effect) d) => 'banish all characters with S ≤ its last strength';
}

/// "You pay that amount of {i} less for the next character you play this turn".
class NextCostReductionBy extends S4Effect {
  const NextCostReductionBy(this.filter, this.amount);
  final Filter filter;
  final Amount amount;
  @override
  String describeWith(String Function(Effect) d) => 'next ${filter.describe()} costs N less';
}

/// At most [n] times a turn ("twice during your turn"), counted per card under [key].
class LimitPerTurn extends S4Effect {
  const LimitPerTurn(this.n, this.key, this.effect);
  final int n, key;
  final Effect effect;
  @override
  String describeWith(String Function(Effect) d) => '≤$n/turn: ${d(effect)}';
}

/// "Put a character card from your discard under this item faceup."
class DiscardUnderThis extends S4Effect {
  const DiscardUnderThis(this.filter);
  final Filter filter;
  @override
  String describeWith(String Function(Effect) d) => '${filter.describe()} from discard under this faceup';
}

/// "This turn, you may play characters from under this item."
class PlayFromUnderThisTurn extends S4Effect {
  const PlayFromUnderThisTurn();
  @override
  String describeWith(String Function(Effect) d) => 'this turn: may play characters from under this';
}

/// "Banish any number of chosen opposing characters with total {s} N or less".
class BanishTotalStrength extends S4Effect {
  const BanishTotalStrength(this.filter, this.total);
  final Filter filter;
  final int total;
  @override
  String describeWith(String Function(Effect) d) => 'banish chosen ${filter.describe()} with total S ≤ $total';
}

// ---------------------------------------------------------------------------------------------
// Amounts
// ---------------------------------------------------------------------------------------------

sealed class S4Amount extends Amount implements S4Ir {
  const S4Amount();
}

/// "For each different ink type of characters you have in play" (CR 5.2.5).
class InkTypes extends S4Amount {
  const InkTypes(this.filter);
  final Filter filter;
  @override
  String describeWith(String Function(Effect) d) => '#inks(${filter.describe()})';
}

/// A number the effect noted as it resolved: "lost" (lore lost), "actions" (action cards
/// discarded), "discardedLore" (the discarded character's {l}).
class Noted extends S4Amount {
  const Noted(this.key, {this.per = 1});
  final String key;
  final int per;
  @override
  String describeWith(String Function(Effect) d) => '${per == 1 ? '' : '$per×'}noted($key)';
}

/// "That location's {l}": the lore of the location the remembered character is at.
class LocationLoreOf extends S4Amount {
  const LocationLoreOf(this.character);
  final Target character;
  @override
  String describeWith(String Function(Effect) d) => 'lore of its location';
}

// ---------------------------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------------------------

sealed class S4Cond extends Cond implements S4Ir {
  const S4Cond();
}

/// "While all cards in your inkwell are exerted".
class S4AllInkExerted extends S4Cond {
  const S4AllInkExerted();
  @override
  String describeWith(String Function(Effect) d) => 'all ink exerted';
}

/// The card(s) remembered in [slot] were [filter] as printed, wherever they are now ("if you
/// returned a Hero character this way", "if that character is named Tod").
class SlotWas extends S4Cond {
  const SlotWas(this.slot, this.filter);
  final int slot;
  final Filter filter;
  @override
  String describeWith(String Function(Effect) d) => '#$slot was ${filter.describe()}';
}

/// A number the effect noted ("if that character had a card under them": "under" ≥ 1).
class NotedCond extends S4Cond {
  const NotedCond(this.key, this.cmp, this.n);
  final String key;
  final Cmp cmp;
  final int n;
  @override
  String describeWith(String Function(Effect) d) => 'noted($key) ${cmp.name} $n';
}

/// "If there was an exerted character here" as the location was banished (CR 6.7.7).
class ExertedHereWhenBanished extends S4Cond {
  const ExertedHereWhenBanished();
  @override
  String describeWith(String Function(Effect) d) => 'an exerted character was here';
}

/// "If you played a Hero character this turn".
class PlayedThisTurn extends S4Cond {
  const PlayedThisTurn(this.filter);
  final Filter filter;
  @override
  String describeWith(String Function(Effect) d) => 'played ${filter.describe()} this turn';
}

/// "While an opponent has more lore than you".
class S4OpponentMoreLore extends S4Cond {
  const S4OpponentMoreLore();
  @override
  String describeWith(String Function(Effect) d) => 'an opponent has more lore';
}

/// "If an opponent has more characters in play than you".
class OpponentMoreCharacters extends S4Cond {
  const OpponentMoreCharacters();
  @override
  String describeWith(String Function(Effect) d) => 'an opponent has more characters';
}

/// "If a character sang this song" (CR 5.4.4.2).
class SangThisSong extends S4Cond {
  const SangThisSong();
  @override
  String describeWith(String Function(Effect) d) => 'this song was sung';
}

/// "Unless you put a card under him this turn" (CR 8.4).
class PutUnderSelfThisTurn extends S4Cond {
  const PutUnderSelfThisTurn();
  @override
  String describeWith(String Function(Effect) d) => 'a card was put under this this turn';
}

/// "If 1 or more cards have left a player's discard this turn".
class LeftDiscardThisTurn extends S4Cond {
  const LeftDiscardThisTurn(this.n);
  final int n;
  @override
  String describeWith(String Function(Effect) d) => '≥$n cards left a discard this turn';
}

/// "If this card is in your discard" (CR 6.1.12): checked as the ability resolves (CR 6.2.4).
class SourceIn extends S4Cond {
  const SourceIn(this.place);
  final Place place;
  @override
  String describeWith(String Function(Effect) d) => 'this is in ${place.name}';
}

/// "If any of the cards that were under them are character cards" (the banished card's stack).
class EventUnderHas extends S4Cond {
  const EventUnderHas(this.filter);
  final Filter filter;
  @override
  String describeWith(String Function(Effect) d) => 'a ${filter.describe()} was under it';
}

// ---------------------------------------------------------------------------------------------
// Static abilities
// ---------------------------------------------------------------------------------------------

sealed class S4Static extends StaticEffect implements S4Ir {
  const S4Static();
}

/// "This character gains Resist +1 for each other Knight character you have in play".
class KeywordPerCount extends S4Static {
  const KeywordPerCount(this.affected, this.kw, this.amount);
  final Filter? affected;
  final Kw kw;
  final Amount amount;
  @override
  String describeWith(String Function(Effect) d) => '${affected?.describe() ?? 'this'} gains ${kw.name} +N';
}

/// "Your characters named Robin Hood may move here for free" (CR 4.7).
class MovesHereFree extends S4Static {
  const MovesHereFree(this.filter);
  final Filter filter;
  @override
  String describeWith(String Function(Effect) d) => '${filter.describe()} move here free';
}

/// "Characters gain "{e} - Draw a card" while here": an activated ability granted to [affected].
class GrantAbility extends S4Static {
  const GrantAbility(this.affected, this.ability);
  final Filter? affected;
  final Activated ability;
  @override
  String describeWith(String Function(Effect) d) => '${affected?.describe() ?? 'this'} gains "${ability.text}"';
}

/// "Opponents can't play actions".
class OpponentsCantPlay extends S4Static {
  const OpponentsCantPlay(this.filter);
  final Filter filter;
  @override
  String describeWith(String Function(Effect) d) => 'opponents can\'t play ${filter.describe()}';
}

/// "All opposing characters gain the Villain classification" (CR 5.2.7).
class GainClass extends S4Static {
  const GainClass(this.affected, this.cls);
  final Filter affected;
  final String cls;
  @override
  String describeWith(String Function(Effect) d) => '${affected.describe()} gain class $cls';
}

/// "Damage counters can't be removed."
class NoDamageRemoval extends S4Static {
  const NoDamageRemoval();
  @override
  String describeWith(String Function(Effect) d) => 'damage can\'t be removed';
}

/// "You pay 1 {i} less to play characters using their Shift ability" (CR 8.10).
class ShiftCostLess extends S4Static {
  const ShiftCostLess(this.filter, this.n);
  final Filter filter;
  final int n;
  @override
  String describeWith(String Function(Effect) d) => 'shift ${filter.describe()} for $n less';
}

/// "You may play characters from your discard. If you do, they enter play exerted."
class PlayFromDiscard extends S4Static {
  const PlayFromDiscard(this.filter, {this.exerted = false});
  final Filter filter;
  final bool exerted;
  @override
  String describeWith(String Function(Effect) d) => 'may play ${filter.describe()} from discard${exerted ? ' (enter exerted)' : ''}';
}

/// "You may exert 4 items of yours to play this character for free": an alternate cost
/// (CR 1.5.4) that works from the hand.
class AltCostExert extends S4Static {
  const AltCostExert(this.filter, this.n);
  final Filter filter;
  final int n;
  @override
  String describeWith(String Function(Effect) d) => 'alt cost: exert $n ${filter.describe()}';
}

// ---------------------------------------------------------------------------------------------
// Triggers
// ---------------------------------------------------------------------------------------------

sealed class S4Trigger extends Trigger implements S4Ir {
  const S4Trigger();
}

/// "When you move a character here from another location" (CR 4.7.2).
class MovedHereFromLocation extends S4Trigger {
  const MovedHereFromLocation();
  @override
  String describeWith(String Function(Effect) d) => 'character moved here from a location';
}

/// "Whenever this character is chosen for an action or an item's ability" (by any player).
class ChosenFor extends S4Trigger {
  const ChosenFor(this.types);
  final Set<CardType> types;
  @override
  String describeWith(String Function(Effect) d) => 'this chosen for ${types.map((t) => t.name).join('/')}';
}
