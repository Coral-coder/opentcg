part of 'ir.dart';

// ---------------------------------------------------------------------------------------------
// More effects, conditions, amounts and statics (cards Miracle Candle … Scrooge McDuck): parsed
// in parser/wave2_s3.dart, resolved in game/wave2_s3.dart. Each family is sealed under its own
// base class, so the shared switches need one line each.
// ---------------------------------------------------------------------------------------------

/// How the IR prints (describe.dart passes its own printers in).
class S3Printers {
  const S3Printers(this.eff, this.cond, this.amt, this.tgt);
  final String Function(Effect) eff;
  final String Function(Cond) cond;
  final String Function(Amount) amt;
  final String Function(Target) tgt;
}

sealed class S3Effect extends Effect {
  const S3Effect();
  String describe(S3Printers p);
}

/// "Exert all cards in your inkwell".
class ExertInkwell extends S3Effect {
  const ExertInkwell(this.who);
  final Who who;
  @override
  String describe(S3Printers p) => 'exert inkwell (${who.name})';
}

/// "Return 2 cards at random from your inkwell to your hand".
class InkwellToHand extends S3Effect {
  const InkwellToHand(this.n);
  final int n;
  @override
  String describe(S3Printers p) => '$n random inkwell cards → hand';
}

/// What a "… this way" refers back to (CR 6.1.8): counted while [Tally] resolves.
enum Tallied { movedCharacters, damageRemoved, itemsToDiscard, itemsBanished, loreLostByOpponents }

/// Resolves [effect] and counts what it did, for a later "for each … this way" ([TallyOf]).
class Tally extends S3Effect {
  const Tally(this.effect, this.what);
  final Effect effect;
  final Tallied what;
  @override
  String describe(S3Printers p) => '${p.eff(effect)} [count ${what.name}]';
}

/// Play a card for free (CR 6.1.7) from any of [from]. [slot] remembers it ("they gain Rush");
/// [upToBanishedPlus]: its cost may be at most the cost of the character banished to pay for
/// the ability, plus this much.
class PlayFreeFrom extends S3Effect {
  const PlayFreeFrom(this.filter, {this.from = const [Place.hand], this.slot, this.exerted = false, this.upToBanishedPlus});
  final Filter filter;
  final List<Place> from;
  final int? slot;
  final bool exerted;
  final int? upToBanishedPlus;
  @override
  String describe(S3Printers p) =>
      'play ${filter.describe()}${upToBanishedPlus == null ? '' : ' cost≤banished+$upToBanishedPlus'} free from ${from.map((x) => x.name).join('/')}${exerted ? ' exerted' : ''}${slot == null ? '' : ' #$slot'}';
}

/// "You may play this character from your discard": played paying its cost (CR 4.3).
class PlayPaying extends S3Effect {
  const PlayPaying(this.target);
  final Target target;
  @override
  String describe(S3Printers p) => 'play ${p.tgt(target)} paying its cost';
}

/// "Move 1 damage from each other character to them".
class MoveDamageFromEach extends S3Effect {
  const MoveDamageFromEach(this.to, this.n);
  final Target to;
  final int n;
  @override
  String describe(S3Printers p) => 'move $n damage from each other character → ${p.tgt(to)}';
}

/// "Chosen opponent reveals their hand and discards a non-character card of their choice".
class RevealDiscardOwnChoice extends S3Effect {
  const RevealDiscardOwnChoice(this.who, this.filter);
  final Who who;
  final Filter filter;
  @override
  String describe(S3Printers p) => 'reveal hand (${who.name}), they discard ${filter.describe()} of their choice';
}

/// Effects that wait for something later in the turn, or change a rule for a while.
enum MarkKind {
  /// "Opponents can't play actions until the start of your next turn".
  noActions,

  /// "This turn, you may put an additional card from your hand into your inkwell" (CR 4.2.3).
  extraInk,

  /// "You pay N {i} less for the next character you shift this turn".
  shiftLess,

  /// "The next character you play this turn enters play exerted and gains Bodyguard until the
  /// start of your next turn".
  nextEntersExertedBodyguard,

  /// "The next time they would be dealt damage they take no damage instead".
  damageShield,

  /// Gained "When this character is banished in a challenge, return this card to your hand".
  returnIfBanishedInChallenge,

  /// "The next time they challenge another character this turn, gain 1 lore".
  loreOnNextChallenge,

  /// "Ready this character after the challenge".
  readyAfterChallenge,

  /// "That character can't ready at the start of their next turn unless they're at a location".
  cantReadyUnlessAtLocation,

  /// "Chosen character counts as having +3 cost to sing songs this turn" (CR 5.4.4).
  singBonus,

  /// "Your characters get +3 {s} while challenging a location this turn".
  challengingLocationBonus,
}

/// Records [kind] for [lasting], on [target] when given.
class Mark extends S3Effect {
  const Mark(this.kind, this.lasting, {this.target, this.amount = 0});
  final MarkKind kind;
  final Lasting lasting;
  final Target? target;
  final int amount;
  @override
  String describe(S3Printers p) => 'mark ${kind.name}${amount == 0 ? '' : ' $amount'}${target == null ? '' : ' on ${p.tgt(target!)}'} (${lasting.name})';
}

/// "They gain Resist +2 during that challenge", "this character takes no damage from the
/// challenge": ends when the challenge does (CR 4.6).
class ForChallenge extends S3Effect {
  const ForChallenge(this.target, {this.keyword, this.rule});
  final Target target;
  final Keyword? keyword;
  final Rule? rule;
  @override
  String describe(S3Printers p) => '${p.tgt(target)} ${keyword?.key ?? rule!.name} (this challenge)';
}

/// "Characters can't challenge until the start of your next turn": every card matching,
/// including ones that enter play later.
class RuleForAll extends S3Effect {
  const RuleForAll(this.filter, this.rule, this.lasting);
  final Filter filter;
  final Rule rule;
  final Lasting lasting;
  @override
  String describe(S3Printers p) => 'all ${filter.describe()} ${rule.name} (${lasting.name})';
}

/// "Put the top card of your deck facedown under this character / them" (CR 8.4.2).
class PutTopUnder extends S3Effect {
  const PutTopUnder(this.target);
  final Target target;
  @override
  String describe(S3Printers p) => 'top of deck under ${p.tgt(target)}';
}

/// "Put this character facedown under one of your characters or locations with Boost".
class PutSelfUnder extends S3Effect {
  const PutSelfUnder(this.filter);
  final Filter filter;
  @override
  String describe(S3Printers p) => 'this under ${filter.describe()}';
}

/// "Look at a number of cards from the top of your deck equal to …": [peek] with [n] cards.
class PeekFor extends S3Effect {
  const PeekFor(this.n, this.peek);
  final Amount n;
  final Peek peek;
  @override
  String describe(S3Printers p) => '${p.eff(peek)} (n = ${p.amt(n)})';
}

/// "They discard until they have 3 cards in their hand" (CR 6.1.8.1).
class DiscardDownTo extends S3Effect {
  const DiscardDownTo(this.who, this.n);
  final Who who;
  final int n;
  @override
  String describe(S3Printers p) => 'discard down to $n (${who.name})';
}

/// "This damage can't be reduced by Resist" (CR 8.8).
class IgnoreResist extends S3Effect {
  const IgnoreResist(this.damage);
  final DealDamage damage;
  @override
  String describe(S3Printers p) => '${p.eff(damage)} ignoring Resist';
}

/// "Deal the same amount of damage to up to 2 other chosen characters": the damage in the event,
/// to characters other than this one and the one it damaged.
class DealSameToOthers extends S3Effect {
  const DealSameToOthers(this.count, {this.upTo = false});
  final int count;
  final bool upTo;
  @override
  String describe(S3Printers p) => 'deal event damage to ${upTo ? 'up to ' : ''}$count other chosen characters';
}

/// "Shuffle your deck".
class ShuffleDeck extends S3Effect {
  const ShuffleDeck();
  @override
  String describe(S3Printers p) => 'shuffle deck';
}

/// "Reveal the top card. If it's an action card, you may play it for free. Otherwise, put it on
/// the bottom of your deck, then [otherwise]".
class RevealTopPlay extends S3Effect {
  const RevealTopPlay(this.filter, this.otherwise);
  final Filter filter;
  final Effect otherwise;
  @override
  String describe(S3Printers p) => 'reveal top: if ${filter.describe()} may play free, else bottom then ${p.eff(otherwise)}';
}

/// "Put 2 character cards from your discard on the bottom of your deck", "choose and discard a
/// card" as the first part of "X to Y": done only if all of it can be (CR 6.1.5.1).
class Exactly extends S3Effect {
  const Exactly(this.effect);

  /// A [FromDiscard] or a [Discard].
  final Effect effect;
  @override
  String describe(S3Printers p) => 'exactly: ${p.eff(effect)}';
}

/// "You pay 1 {i} less for the next character you play this turn" for each of [amount].
class NextCostLess extends S3Effect {
  const NextCostLess(this.filter, this.amount);
  final Filter filter;
  final Amount amount;
  @override
  String describe(S3Printers p) => 'next ${filter.describe()} costs ${p.amt(amount)} less';
}

/// An activated ability usable only while [cond] holds ("while you have 3 or more characters
/// here, you may banish this location to …").
class Gated extends S3Effect {
  const Gated(this.cond, this.effect);
  final Cond cond;
  final Effect effect;
  @override
  String describe(S3Printers p) => 'only while ${p.cond(cond)}: ${p.eff(effect)}';
}

/// An activated ability usable once during your turn ("once during your turn, you may pay 2 {i}
/// to …", like Boost, CR 8.4.1).
class OncePerTurn extends S3Effect {
  const OncePerTurn(this.effect);
  final Effect effect;
  @override
  String describe(S3Printers p) => 'once per turn: ${p.eff(effect)}';
}

// ---------------------------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------------------------

sealed class S3Cond extends Cond {
  const S3Cond();
  String describe(S3Printers p);
}

/// "While all cards in your inkwell are exerted".
class AllInkExerted extends S3Cond {
  const AllInkExerted();
  @override
  String describe(S3Printers p) => 'all your ink exerted';
}

/// "If you didn't put any cards into your inkwell this turn".
class InkedThisTurn extends S3Cond {
  const InkedThisTurn(this.cmp, this.n);
  final Cmp cmp;
  final int n;
  @override
  String describe(S3Printers p) => 'inked this turn ${cmp.name} $n';
}

/// "If an opponent has more lore than you".
class OpponentMoreLore extends S3Cond {
  const OpponentMoreLore();
  @override
  String describe(S3Printers p) => 'an opponent has more lore';
}

/// "If you've put a card under one of your characters or locations this turn".
class PutUnderThisTurn extends S3Cond {
  const PutUnderThisTurn();
  @override
  String describe(S3Printers p) => 'you put a card under this turn';
}

/// "When this character challenges and is banished": it's the challenger in the challenge going
/// on.
class AsChallenger extends S3Cond {
  const AsChallenger();
  @override
  String describe(S3Printers p) => 'this is challenging';
}

/// "If an opposing character was damaged this turn".
class OpposingDamagedThisTurn extends S3Cond {
  const OpposingDamagedThisTurn();
  @override
  String describe(S3Printers p) => 'an opposing character was damaged this turn';
}

// ---------------------------------------------------------------------------------------------
// Amounts
// ---------------------------------------------------------------------------------------------

sealed class S3Amount extends Amount {
  const S3Amount();
  String describe(S3Printers p);
}

/// The amount in the triggering event ("the same amount of damage", "for each card discarded").
class EventAmount extends S3Amount {
  const EventAmount();
  @override
  String describe(S3Printers p) => 'event amount';
}

/// "…, to a maximum of 6 lore".
class Capped extends S3Amount {
  const Capped(this.amount, this.max);
  final Amount amount;
  final int max;
  @override
  String describe(S3Printers p) => 'min(${p.amt(amount)}, $max)';
}

/// "For each … this way" ([Tally]).
class TallyOf extends S3Amount {
  const TallyOf(this.what, {this.per = 1});
  final Tallied what;
  final int per;
  @override
  String describe(S3Printers p) => '$per×${what.name}';
}

/// "For each 1 damage on opposing characters".
class DamageOnAll extends S3Amount {
  const DamageOnAll(this.filter, {this.per = 1});
  final Filter filter;
  final int per;
  @override
  String describe(S3Printers p) => '$per×damage on ${filter.describe()}';
}

/// "For each opposing character banished in a challenge this turn".
class BanishedInChallengeCount extends S3Amount {
  const BanishedInChallengeCount(this.whose, {this.per = 1});
  final Owner whose;
  final int per;
  @override
  String describe(S3Printers p) => '$per×${whose.name} banished in a challenge this turn';
}

/// "The {s} of chosen Ally character of yours": chooses if not chosen yet.
class StatOfChosen extends S3Amount {
  const StatOfChosen(this.target, this.stat);
  final Target target;
  final Stat stat;
  @override
  String describe(S3Printers p) => '${p.tgt(target)}.${stat.name}';
}

// ---------------------------------------------------------------------------------------------
// Static effects
// ---------------------------------------------------------------------------------------------

sealed class S3Static extends StaticEffect {
  const S3Static();
  String describe(S3Printers p);
}

/// "You can ink cards from your discard" (CR 4.2).
class InkFromDiscard extends S3Static {
  const InkFromDiscard();
  @override
  String describe(S3Printers p) => 'ink from discard';
}

/// "You can't play this character unless …" (in hand).
class CantPlayUnless extends S3Static {
  const CantPlayUnless(this.cond);
  final Cond cond;
  @override
  String describe(S3Printers p) => 'can\'t be played unless ${p.cond(cond)}';
}

/// "Your characters named Stitch count as having +1 cost to sing songs" (CR 5.4.4).
class SingCost extends S3Static {
  const SingCost(this.filter, this.n);
  final Filter filter;
  final int n;
  @override
  String describe(S3Printers p) => '${filter.describe()} +$n cost to sing';
}

/// Moving characters (CR 4.7): "your Toy characters can move here for free", "you pay 2 {i} less
/// to move a character of yours here", "once during your turn, you may pay 1 {i} less to move
/// this character to a location". [filter] null: the source itself; [here]: only moving to the
/// source.
class MoveCost extends S3Static {
  const MoveCost({this.filter, this.here = false, this.free = false, this.less = 0, this.once = false});
  final Filter? filter;
  final bool here, free;
  final int less;
  final bool once;
  @override
  String describe(S3Printers p) => '${filter?.describe() ?? 'this'} move${here ? ' here' : ''} ${free ? 'free' : '$less less'}${once ? ' once/turn' : ''}';
}

/// "Each turn, only one character can challenge".
class OneChallengerPerTurn extends S3Static {
  const OneChallengerPerTurn();
  @override
  String describe(S3Printers p) => 'one challenger per turn';
}

/// "This character can't quest or challenge unless you pay 1 {i}".
class PayToQuestOrChallenge extends S3Static {
  const PayToQuestOrChallenge(this.n);
  final int n;
  @override
  String describe(S3Printers p) => 'pay $n to quest or challenge';
}

/// "Each opponent plays with the top card of their deck faceup".
class TopCardFaceUp extends S3Static {
  const TopCardFaceUp();
  @override
  String describe(S3Printers p) => 'opponents\' top card faceup';
}
