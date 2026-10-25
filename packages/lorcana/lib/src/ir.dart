/// The ability IR: card text parsed into data the engine executes (CR 6). Each card's abilities
/// are keywords (CR 8), triggered (6.2), activated (6.3) or static (6.4); actions have effects.
library;

import 'cards/card.dart';

part 'ir_zones.dart';
part 'ir_board.dart';
part 'ir_wave2_s3.dart';
part 'ir_wave2_s4.dart';
part 'ir_wave2_s1.dart';

/// Keywords (CR 8.1.1).
enum Kw { alert, bodyguard, boost, challenger, evasive, reckless, resist, rush, shift, singer, singTogether, support, vanish, ward }

/// The +N keywords stack (CR 8.1.2).
const stackingKws = {Kw.challenger, Kw.resist};

class Keyword {
  const Keyword(this.kw, {this.n = 0, this.shiftClass, this.universalShift = false, this.shiftVariant = ShiftVariant.plain, this.shiftDiscard});
  final Kw kw;

  /// Challenger/Resist +N, Singer N, Sing Together N, Boost and Shift costs.
  final int n;

  /// [Classification] Shift (CR 8.10.8.1).
  final String? shiftClass;

  /// Universal Shift (CR 8.10.8.2).
  final bool universalShift;

  /// Duo, Combo, Temporary and Potato Shift (CR 8.10.8.3–8.10.8.6).
  final ShiftVariant shiftVariant;

  /// "Shift: Discard a location card": the alternate cost is discarding instead of ink (CR 8.10.1).
  final ShiftDiscard? shiftDiscard;

  String get key => '${kw.name}$n${shiftClass ?? ''}${universalShift ? 'u' : ''}${shiftVariant == ShiftVariant.plain ? '' : shiftVariant.name}${shiftDiscard == null ? '' : 'd${shiftDiscard!.count}${shiftDiscard!.types.map((t) => t.name).join('+')}${shiftDiscard!.song ? 's' : ''}'}';
}

enum ShiftVariant { plain, duo, combo, temporary, potato }

/// Cards to discard from hand as a Shift cost: [count] cards of [types] (all types when empty),
/// songs only when [song].
class ShiftDiscard {
  const ShiftDiscard(this.count, {this.types = const {}, this.song = false});
  final int count;
  final Set<CardType> types;
  final bool song;
}

enum Stat { strength, willpower, lore }

enum Owner { any, yours, opposing }

/// What a card must be to be selected ("chosen opposing character with 2 {s} or less").
class Filter {
  const Filter({
    this.types = const {CardType.character},
    this.owner = Owner.any,
    this.other = false,
    this.classes = const [],
    this.named,
    this.exerted,
    this.damaged,
    this.costMax,
    this.costMin,
    this.strengthMax,
    this.strengthMin,
    this.withKw,
    this.atLocation,
    this.atThisLocation = false,
    this.atSourcesLocation = false,
    this.song,
    this.notNamed,
    this.ink,
    this.willpowerMin,
    this.hasUnder,
    this.withoutKw,
    this.or,
  });

  final Set<CardType> types;
  final Owner owner;

  /// "Other", "another": not the source (CR 6.1.6).
  final bool other;

  /// Any of these classifications.
  final List<String> classes;
  final String? named;
  final bool? exerted, damaged;
  final int? costMax, costMin, strengthMax, strengthMin;
  final Kw? withKw;
  final bool? atLocation;

  /// "Characters ... while here": at the location that has the ability.
  final bool atThisLocation;

  /// "Characters at that location": at the same location as the card with the ability.
  final bool atSourcesLocation;
  final bool? song;

  /// Is one of [names] the name this filter asks for? "Named Woody or Jessie" takes either.
  bool nameMatches(Iterable<String> names) {
    final want = named!.toLowerCase();
    final alts = want.split(' or ');
    return names.any((n) => n.toLowerCase() == want || alts.contains(n.toLowerCase()));
  }

  /// "Characters not named Mor'du".
  final String? notNamed;

  /// "Steel characters": of this ink (CR 5.2.5; a dual-ink card is both).
  final Ink? ink;

  /// "A character with 4 {w} or more".
  final int? willpowerMin;
  /// "With a card under them" (CR 8.4), "without Evasive", and "or item" (a card matching [or]
  /// matches too: "chosen character with Bodyguard or item").
  final bool? hasUnder;
  final Kw? withoutKw;
  final Filter? or;

  Filter copyWith({
    Set<CardType>? types,
    Owner? owner,
    bool? other,
    List<String>? classes,
    String? named,
    bool? exerted,
    bool? damaged,
    int? costMax,
    int? costMin,
    int? strengthMax,
    int? strengthMin,
    Kw? withKw,
    bool? atLocation,
    bool? atThisLocation,
    bool? atSourcesLocation,
    bool? song,
    String? notNamed,
    Ink? ink,
    int? willpowerMin,
    bool? hasUnder,
    Kw? withoutKw,
    Filter? or,
  }) => Filter(
    types: types ?? this.types,
    owner: owner ?? this.owner,
    other: other ?? this.other,
    classes: classes ?? this.classes,
    named: named ?? this.named,
    exerted: exerted ?? this.exerted,
    damaged: damaged ?? this.damaged,
    costMax: costMax ?? this.costMax,
    costMin: costMin ?? this.costMin,
    strengthMax: strengthMax ?? this.strengthMax,
    strengthMin: strengthMin ?? this.strengthMin,
    withKw: withKw ?? this.withKw,
    atLocation: atLocation ?? this.atLocation,
    atThisLocation: atThisLocation ?? this.atThisLocation,
    atSourcesLocation: atSourcesLocation ?? this.atSourcesLocation,
    song: song ?? this.song,
    notNamed: notNamed ?? this.notNamed,
    ink: ink ?? this.ink,
    willpowerMin: willpowerMin ?? this.willpowerMin,
    hasUnder: hasUnder ?? this.hasUnder,
    withoutKw: withoutKw ?? this.withoutKw,
    or: or ?? this.or,
  );

  String describe() {
    final b = <String>[];
    if (owner == Owner.yours) b.add('your');
    if (owner == Owner.opposing) b.add('opposing');
    if (other) b.add('other');
    if (exerted == true) b.add('exerted');
    if (exerted == false) b.add('ready');
    if (damaged == true) b.add('damaged');
    if (damaged == false) b.add('undamaged');
    if (ink != null) b.add(ink!.label);
    if (classes.isNotEmpty) b.add(classes.join('/'));
    b.add(song == true ? 'song' : types.map((t) => t.name).join('/'));
    if (song == false) b.add('non-song');
    if (named != null) b.add('named $named');
    if (notNamed != null) b.add('not named $notNamed');
    if (costMax != null) b.add('cost≤$costMax');
    if (costMin != null) b.add('cost≥$costMin');
    if (strengthMax != null) b.add('S≤$strengthMax');
    if (strengthMin != null) b.add('S≥$strengthMin');
    if (willpowerMin != null) b.add('W≥$willpowerMin');
    if (withKw != null) b.add('with ${withKw!.name}');
    if (atLocation == true) b.add('at a location');
    if (atThisLocation) b.add('here');
    if (atSourcesLocation) b.add('at its location');
    if (hasUnder == true) b.add('with a card under');
    if (withoutKw != null) b.add('without ${withoutKw!.name}');
    if (or != null) b.add('or ${or!.describe()}');
    return b.join(' ');
  }
}

// ---------------------------------------------------------------------------------------------
// References
// ---------------------------------------------------------------------------------------------

/// Which cards an effect acts on.
sealed class Target {
  const Target();
}

/// The card with the ability ("this character").
class This extends Target {
  const This();
}

/// Chosen as the effect resolves (CR 6.1.3); [upTo] allows fewer, including none.
class Chosen extends Target {
  const Chosen(this.filter, {this.count = 1, this.upTo = false, this.slot = 0, this.word = true});
  final Filter filter;
  final int count;
  final bool upTo;

  /// Said "chosen" (Ward applies, CR 8.15.1); false for "a character" picked by the player.
  final bool word;

  /// Later references in the same ability ("them", "that character") use this slot.
  final int slot;
}

/// Every card matching.
/// Slots from here on remember groups ([AllOf.slot]); lower ones remember chosen cards.
const groupSlots = 100;

class AllOf extends Target {
  const AllOf(this.filter, {this.slot});
  final Filter filter;

  /// Where the cards it found are remembered, so "they" later in the ability means them.
  final int? slot;
}

/// The location [of] is at, or [of] itself if it is a location ("that location").
class LocationOf extends Target {
  const LocationOf(this.of);
  final Target of;
}

/// The card the trigger is about ("that character", "the challenging character").
class EventCard extends Target {
  const EventCard({this.other = false});

  /// The other card in the event (the challenged character, the blocker...).
  final bool other;
}

/// An earlier choice in the same ability ("them", "that character", "it").
class Remembered extends Target {
  const Remembered([this.slot = 0]);
  final int slot;
}

enum Who {
  you,
  opponents,
  each,
  chosenOpponent,
  thatPlayer,

  /// Any player, chosen as the effect resolves ("chosen player's deck").
  chosenPlayer,

  /// The challenging character's player ("the challenging player chooses and discards a card").
  challenger,
}

sealed class Amount {
  const Amount();
}

class Fixed extends Amount {
  const Fixed(this.n);
  final int n;
}

/// "For each" (CR 6.1.8): counted once as a non-static effect resolves.
class CountOf extends Amount {
  const CountOf(this.filter, {this.place = Place.play, this.whose = Owner.yours, this.per = 1});
  final Filter filter;
  final Place place;
  final Owner whose;
  final int per;
}

/// A card's characteristic ("equal to their {s}").
class StatOf extends Amount {
  const StatOf(this.target, this.stat);
  final Target target;
  final Stat stat;
}

/// Cards in a hand ("for each card in your opponents' hands").
class HandSize extends Amount {
  const HandSize(this.who, {this.per = 1});
  final Who who;
  final int per;
}

enum Place { deck, hand, play, inkwell, discard }

enum Lasting { thisTurn, untilYourNextTurn, theirNextTurn, permanent }

// ---------------------------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------------------------

sealed class Cond {
  const Cond();
}

enum Cmp { ge, le, eq, gt, lt }

/// "If you have a character named Gaston in play", "2 or more other characters".
class CountCond extends Cond {
  const CountCond(this.filter, this.cmp, this.n, {this.place = Place.play, this.whose = Owner.yours});
  final Filter filter;
  final Cmp cmp;
  final int n;
  final Place place;
  final Owner whose;
}

class SelfState extends Cond {
  const SelfState({this.exerted, this.atLocation, this.damaged});
  final bool? exerted, atLocation, damaged;
}

class YourTurn extends Cond {
  const YourTurn();
}

class HandCond extends Cond {
  const HandCond(this.who, this.cmp, this.n);
  final Who who;
  final Cmp cmp;
  final int n;
}

class LoreCond extends Cond {
  const LoreCond(this.who, this.cmp, this.n);
  final Who who;
  final Cmp cmp;
  final int n;
}

class Not extends Cond {
  const Not(this.c);
  final Cond c;
}

class AllConds extends Cond {
  const AllConds(this.conds);
  final List<Cond> conds;
}

/// "If you do" (CR 6.1.5).
class DidIt extends Cond {
  const DidIt();
}

/// The remembered or event card matches.
class TargetIs extends Cond {
  const TargetIs(this.target, this.filter);
  final Target target;
  final Filter filter;
}

// ---------------------------------------------------------------------------------------------
// Effects
// ---------------------------------------------------------------------------------------------

sealed class Effect {
  const Effect();
}

class Seq extends Effect {
  const Seq(this.steps);
  final List<Effect> steps;
}

/// "You may" (CR 6.1.4).
class May extends Effect {
  const May(this.e);
  final Effect e;
}

class If extends Effect {
  const If(this.cond, this.then, [this.otherwise]);
  final Cond cond;
  final Effect then;
  final Effect? otherwise;
}

/// "[A] or [B]" and "Choose one:" (CR 6.1.5.2).
class ChooseOne extends Effect {
  const ChooseOne(this.options, this.labels);
  final List<Effect> options;
  final List<String> labels;
}

class Draw extends Effect {
  const Draw(this.who, this.amount, {this.untilHandSize = false});
  final Who who;
  final Amount amount;
  final bool untilHandSize;
}

/// "Choose and discard a card" / "discards a card at random".
class Discard extends Effect {
  const Discard(this.who, this.amount, {this.random = false, this.all = false, this.filter});
  final Who who;
  final Amount amount;
  final bool random, all;
  final Filter? filter;
}

class GainLore extends Effect {
  const GainLore(this.who, this.amount);
  final Who who;
  final Amount amount;
}

class LoseLore extends Effect {
  const LoseLore(this.who, this.amount);
  final Who who;
  final Amount amount;
}

class DealDamage extends Effect {
  const DealDamage(this.target, this.amount, {this.put = false});
  final Target target;
  final Amount amount;

  /// "Put N damage counters" (CR 1.9.2.2): not dealt, so Resist doesn't apply.
  final bool put;
}

class RemoveDamage extends Effect {
  const RemoveDamage(this.target, this.amount, {this.all = false});
  final Target target;
  final Amount amount;
  final bool all;
}

class MoveDamage extends Effect {
  const MoveDamage(this.from, this.to, this.amount, {this.upTo = false});
  final Target from, to;
  final Amount amount;

  /// "Move up to N damage": the player picks how many, 0 to N.
  final bool upTo;
}

class Banish extends Effect {
  const Banish(this.target);
  final Target target;
}

class ReturnToHand extends Effect {
  const ReturnToHand(this.target);
  final Target target;
}

class Exert extends Effect {
  const Exert(this.target);
  final Target target;
}

class Ready extends Effect {
  const Ready(this.target);
  final Target target;
}

/// Shuffle into the owner's deck, or put on its top or bottom.
class ToDeck extends Effect {
  const ToDeck(this.target, {this.bottom = false, this.top = false});
  final Target target;
  final bool bottom, top;
}

/// Put into the owner's inkwell (CR 4.2.3.2).
class ToInkwell extends Effect {
  const ToInkwell(this.target, {this.exerted = false});
  final Target target;
  final bool exerted;
}

/// "Put the top card of your deck into your inkwell facedown (and exerted)".
class InkTopOfDeck extends Effect {
  const InkTopOfDeck(this.who, {this.exerted = false});
  final Who who;
  final bool exerted;
}

/// "Put a card from your hand into your inkwell facedown".
class InkFromHand extends Effect {
  const InkFromHand({this.exerted = false});
  final bool exerted;
}

/// Characteristic modifiers for a duration (CR 6.6).
class Modify extends Effect {
  const Modify(this.target, this.stat, this.amount, this.duration, {this.negative = false});
  final Target target;
  final Stat stat;
  final Amount amount;
  final bool negative;
  final Lasting duration;
}

class GrantKeyword extends Effect {
  const GrantKeyword(this.target, this.keyword, this.duration);
  final Target target;
  final Keyword keyword;
  final Lasting duration;
}

/// Restrictions and permissions for a duration ("can't quest during their next turn").
enum Rule {
  cantQuest,
  cantChallenge,
  cantBeChallenged,
  cantReady,
  cantSing,
  mustChallenge,
  takesNoDamageFromChallenges,

  /// "This character must quest if able" (blocks ending the turn while it can).
  mustQuest,

  /// "This character can challenge ready characters" (CR 4.6.4 exception).
  canChallengeReady,

  /// "…can challenge ready damaged characters".
  canChallengeReadyDamaged,

  /// "This character can quest the turn he's played" (CR 5.1.2 exception).
  canQuestWhileDrying,

  /// "This character can't move to locations".
  cantMove,

  /// "This character can't gain Evasive".
  cantGainEvasive,

  /// "This character can't sing songs without Sing Together".
  singsOnlyTogether,

  /// "…can't be dealt damage".
  cantBeDealtDamage,

  /// "During challenges, your characters deal damage with their {w} instead of their {s}".
  dealsWillpowerInChallenges,
}

class GrantRule extends Effect {
  const GrantRule(this.target, this.rule, this.duration);
  final Target target;
  final Rule rule;
  final Lasting duration;
}

/// Return cards from a discard to the hand ("return a character card from your discard to your
/// hand").
class FromDiscardToHand extends Effect {
  const FromDiscardToHand(this.filter, {this.count = 1, this.upTo = false});
  final Filter filter;
  final int count;
  final bool upTo;
}

/// "Look at the top N cards of your deck. You may reveal a X card and put it into your hand. Put
/// the rest on the bottom of your deck in any order."
class LookTop extends Effect {
  const LookTop(this.n, {this.pick, this.pickCount = 1, this.restBottom = true, this.reorderOnly = false, this.mustPick = false, this.restInk = false});
  final int n;

  /// "…and the other into your inkwell facedown and exerted".
  final bool restInk;

  /// "Put one into your hand" (no "you may", no "up to"): a matching card must be taken.
  final bool mustPick;
  final Filter? pick;
  final int pickCount;
  final bool restBottom;

  /// "Put them back on the top of your deck in any order".
  final bool reorderOnly;
}

/// Put the top N cards of a deck into the discard.
class Mill extends Effect {
  const Mill(this.who, this.n);
  final Who who;
  final int n;
}

/// "You pay N {i} less for the next X you play this turn" (CR 4.3.6).
class NextCostReduction extends Effect {
  const NextCostReduction(this.filter, this.n);
  final Filter filter;
  final int n;
}

/// "Play a X with cost N or less for free" (CR 6.1.7), from the hand or the discard.
class PlayFree extends Effect {
  const PlayFree(this.filter, {this.from = Place.hand, this.entersExerted = false});
  final Filter filter;
  final Place from;
  final bool entersExerted;
}

/// A floating triggered ability for the rest of the turn (CR 6.2.7.1).
class Floating extends Effect {
  const Floating(this.ability);
  final Triggered ability;
}

/// A delayed triggered ability (CR 6.2.7.2): "at the end of your turn, banish them".
class Delayed extends Effect {
  const Delayed(this.atEndOfTurn, this.effect);
  final bool atEndOfTurn;
  final Effect effect;
}

/// Move a character to a location for free.
class MoveFree extends Effect {
  const MoveFree(this.character, {this.toEventLocation = false});
  final Target character;
  final bool toEventLocation;
}

// ---------------------------------------------------------------------------------------------
// Abilities
// ---------------------------------------------------------------------------------------------

sealed class Ability {
  const Ability(this.text);

  /// The ability as printed (story name included).
  final String text;
}

class KeywordAbility extends Ability {
  const KeywordAbility(super.text, this.keyword);
  final Keyword keyword;
}

sealed class Trigger {
  const Trigger();
}

/// "When you play this character" (CR 4.3.4.1).
class OnPlay extends Trigger {
  const OnPlay();
}

/// "Whenever you play a song", "whenever an opponent plays…": [filter] on the played card.
/// [nth]: only the nth action that player plays this turn ("whenever you play a second action
/// in a turn").
class CardPlayed extends Trigger {
  const CardPlayed(this.filter, {this.by = Owner.yours, this.nth = 0});
  final Filter filter;
  final Owner by;
  final int nth;
}

enum Event { quests, challenges, isChallenged, banished, banishedInChallenge, banishesInChallenge, sings, movesToLocation, dealtDamage, readied, exerted }

/// A card in [subject] does something. [subject] null: this card.
class CardEvent extends Trigger {
  const CardEvent(this.event, {this.subject, this.other, this.where, this.here = false});
  final Event event;
  final Filter? subject;

  /// The other card in the event: the challenged character ("challenges a damaged character").
  final Filter? other;

  /// What the event card must be as the event happens, whoever it is ("quests while at a
  /// location", "quests while he has 5 strength or more").
  final Filter? where;

  /// The event card is at this location ("whenever a character quests while here"), as it was
  /// when the event happened.
  final bool here;
}

/// "At the start of your turn" / "at the end of your turn" (CR 3.2.1.4, 3.4.1.1). [yours]
/// false: every turn, or only opponents' turns with [opponents].
class TurnStep extends Trigger {
  const TurnStep({required this.start, this.yours = true, this.opponents = false});
  final bool start, yours, opponents;
}

/// "Whenever you draw a card", "whenever an opponent draws". [nth]: only the nth card that
/// player draws this turn; [theirTurn]: only during the drawing player's turn.
class Draws extends Trigger {
  const Draws(this.by, {this.nth = 0, this.theirTurn = false});
  final Owner by;
  final int nth;
  final bool theirTurn;
}

/// The further events a triggered ability can wait for (CR 6.2).
enum Happening {
  /// A card is put into a player's inkwell (any way; CR 4.2, 7.5).
  inked,

  /// Damage is removed from a card (the amount removed).
  damageRemoved,

  /// A card leaves play, any way (CR 7.4.3).
  leftPlay,

  /// A card is returned from play to its owner's hand.
  returnedToHand,

  /// A card is put under the event card (Boost, CR 8.4).
  putUnder,

  /// A song is sung, once per song however many sing it.
  songSung,

  /// A character sings a song with Sing Together (CR 8.12).
  sungTogether,

  /// An opponent of the card's owner chooses it for an action or ability.
  chosenByOpponent,

  /// A character is chosen for Support (CR 8.13).
  supportChosen,

  /// A card is played paying ink (the amount paid).
  inkPaid,

  /// A character is shifted onto the event card (CR 8.10).
  shiftedOnto,

  /// The event card is played with Shift.
  shifted,

  /// A card is discarded from a hand.
  discarded,

  /// A player discards one or more cards at once (the number).
  discardedCards,

  /// A card becomes exerted.
  exerted,

  /// A card is returned from a discard to its owner's hand.
  returnedFromDiscard,

  /// The event card deals damage to another character in a challenge (the amount).
  dealsChallengeDamage,
}

/// [what] happens. The event card is this card when [self], else any card matching [subject]
/// (null: any card); [by] is the player the event belongs to (who inked, removed damage,
/// paid, discarded), relative to the ability's controller. [min]/[max] bound the event's
/// amount; [nth] picks the nth such event that player has this turn.
class On extends Trigger {
  const On(this.what, {this.self = false, this.subject, this.by = Owner.any, this.min = 0, this.max, this.nth = 0});
  final Happening what;
  final bool self;
  final Filter? subject;
  final Owner by;
  final int min;
  final int? max;
  final int nth;
}

/// "When you move a character here" (locations).
class MovedHere extends Trigger {
  const MovedHere();
}

class Triggered extends Ability {
  const Triggered(super.text, this.trigger, this.effect, {this.condition, this.during, this.oncePerTurn = false, this.fromDiscard = false});
  final Trigger trigger;
  final Effect effect;

  /// Secondary "if" condition, checked on resolution (CR 6.2.4).
  final Cond? condition;

  /// "During your turn, whenever…" / "while this character is exerted, whenever…": checked when
  /// the condition is met (CR 6.1.13.6).
  final Cond? during;
  final bool oncePerTurn;
  final bool fromDiscard;
}

/// Activated ability costs (CR 4.4).
class Cost {
  const Cost({this.exert = false, this.ink = 0, this.banishSelf = false, this.discard = 0, this.exertOther, this.banishOther, this.damageSelf = 0, this.discardFilters, this.oncePerTurn = false});
  final bool exert;
  final int ink;
  final bool banishSelf;
  final int discard;
  final Filter? exertOther;
  final Filter? banishOther;

  /// "Deal 1 damage to this character", "choose and discard a character card" (any of these
  /// filters), and an ability usable once per turn with no other cost ("once per turn, you may").
  final int damageSelf;
  final List<Filter>? discardFilters;
  final bool oncePerTurn;
}

class Activated extends Ability {
  const Activated(super.text, this.cost, this.effect);
  final Cost cost;
  final Effect effect;
}

/// Static effects of a card in play (CR 6.4.2.3), applied while [condition] holds.
sealed class StaticEffect {
  const StaticEffect();
}

class StaticMod extends StaticEffect {
  const StaticMod(this.affected, this.stat, this.amount, {this.negative = false});

  /// null: this card.
  final Filter? affected;
  final Stat stat;
  final Amount amount;
  final bool negative;
}

class StaticKeyword extends StaticEffect {
  const StaticKeyword(this.affected, this.keyword);
  final Filter? affected;
  final Keyword keyword;
}

class StaticRule extends StaticEffect {
  const StaticRule(this.affected, this.rule);
  final Filter? affected;
  final Rule rule;
}

/// "You pay N {i} less to play this character" (self, from hand; CR 4.3.6) or "...to play
/// Inventor characters" (others, while in play).
class CostReduction extends StaticEffect {
  const CostReduction(this.filter, this.amount, {this.self = false});
  final Filter filter;
  final Amount amount;
  final bool self;
}

/// "This character enters play exerted" / "with N damage" (CR 6.7.9).
class EntersWith extends StaticEffect {
  const EntersWith({this.exerted = false, this.damage = 0});
  final bool exerted;
  final int damage;
}

/// "You may put an additional card from your hand into your inkwell" (CR 4.2.3.1).
class ExtraInk extends StaticEffect {
  const ExtraInk();
}

/// "Skip your turn's Draw step" (CR 6.4.3).
class SkipDraw extends StaticEffect {
  const SkipDraw();
}

class Static extends Ability {
  const Static(super.text, this.effect, {this.condition, this.inHand = false});
  final StaticEffect effect;
  final Cond? condition;

  /// Works from the hand (self cost reductions).
  final bool inHand;
}

/// An action's effect (CR 5.4.3).
class ActionEffect extends Ability {
  const ActionEffect(super.text, this.effect);
  final Effect effect;
}

// ---------------------------------------------------------------------------------------------
// Static abilities: more conditions and effects (parser/statics.dart)
// ---------------------------------------------------------------------------------------------

/// "If this is your first turn and you're not the first player" (CR 2.2.1).
class FirstTurnNotFirstPlayer extends Cond {
  const FirstTurnNotFirstPlayer();
}

/// "While this character has N {s} or more": compares the source's own current value.
class SelfStat extends Cond {
  const SelfStat(this.stat, this.cmp, this.n);
  final Stat stat;
  final Cmp cmp;
  final int n;
}

/// "While there's a card under this character" (CR 8.4, 8.10).
class SelfHasUnder extends Cond {
  const SelfHasUnder();
}

/// "While you have a character or location in play with a card under them".
class AnyWithUnder extends Cond {
  const AnyWithUnder(this.whose);
  final Owner whose;
}

/// Cards in a player's inkwell ("while you have 3 or more cards in your inkwell").
class InkwellCond extends Cond {
  const InkwellCond(this.who, this.cmp, this.n);
  final Who who;
  final Cmp cmp;
  final int n;
}

/// "While you have more items in play than each opponent" / "more cards in your inkwell than
/// each opposing player": [filter] on cards in [place] (all cards there when null).
class MoreThanEachOpponent extends Cond {
  const MoreThanEachOpponent(this.place, [this.filter]);
  final Place place;
  final Filter? filter;
}

/// "While being challenged" (CR 4.6): true while the source is the challenged card.
class BeingChallenged extends Cond {
  const BeingChallenged();
}

enum TurnCount { putIntoDiscard, actionsPlayed, questedOthers, discardedByYou }

/// Things counted this turn ("if 2 or more cards were put into your discard this turn").
class ThisTurnCond extends Cond {
  const ThisTurnCond(this.what, this.cmp, this.n);
  final TurnCount what;
  final Cmp cmp;
  final int n;
}

/// "If a character named Buzz Lightyear was banished this turn" / "if an opposing character was
/// banished in a challenge this turn".
class BanishedThisTurn extends Cond {
  const BanishedThisTurn(this.filter, {this.inChallenge = false});
  final Filter filter;
  final bool inChallenge;
}

/// Damage on the source, counted in groups of [per] ("for each 2 damage on him").
class DamageOnSelf extends Amount {
  const DamageOnSelf({this.per = 1, this.times = 1});
  final int per, times;
}

/// Cards under the source ("for each card under him").
class UnderSelf extends Amount {
  const UnderSelf({this.times = 1});
  final int times;
}

/// "Damaged characters can't challenge your characters", "this character can't be challenged by
/// pirate characters": [attackers] can't challenge cards matching [defenders] (null: the source).
class CantBeChallengedBy extends StaticEffect {
  const CantBeChallengedBy(this.attackers, {this.defenders});
  final Filter attackers;
  final Filter? defenders;
}

/// "While this character is being challenged, the challenging character gets -N {s}".
class ChallengerMod extends StaticEffect {
  const ChallengerMod(this.stat, this.amount, {this.negative = false});
  final Stat stat;
  final int amount;
  final bool negative;
}

/// "Opponents need 25 lore to win the game".
class OpponentsLoreToWin extends StaticEffect {
  const OpponentsLoreToWin(this.n);
  final int n;
}

/// "Opposing items enter play exerted", "opposing characters with Rush enter play exerted".
class OpposingEnterExerted extends StaticEffect {
  const OpposingEnterExerted(this.filter);
  final Filter filter;
}

/// "Cards enter opponents' inkwells exerted".
class OpposingInkExerted extends StaticEffect {
  const OpposingInkExerted();
}

/// "This character may enter play exerted [to <effect>]" (CR 6.7.9).
class MayEnterExerted extends StaticEffect {
  const MayEnterExerted([this.then]);
  final Effect? then;
}

/// "You may have up to 99 copies of X in your deck" / "any number of cards named X" (deck
/// building, CR 1.10.1.1 exception); [max] null: any number.
class DeckLimit extends StaticEffect {
  const DeckLimit(this.max);
  final int? max;
}

/// "While challenging a damaged character" (CR 4.6): the source is the challenger and the
/// challenged card matches [defender].
class Challenging extends Cond {
  const Challenging(this.defender);
  final Filter defender;
}

/// "This character also counts as being named King Candy for Shift" (CR 8.10.1); [name] null:
/// "you can shift any character on top of this character".
class ShiftName extends StaticEffect {
  const ShiftName(this.name);
  final String? name;
}
