/// The ability IR: card text parsed into data the engine executes (CR 6). Each card's abilities
/// are keywords (CR 8), triggered (6.2), activated (6.3) or static (6.4); actions have effects.
library;

import 'cards/card.dart';

/// Keywords (CR 8.1.1).
enum Kw { alert, bodyguard, boost, challenger, evasive, reckless, resist, rush, shift, singer, singTogether, support, vanish, ward }

/// The +N keywords stack (CR 8.1.2).
const stackingKws = {Kw.challenger, Kw.resist};

class Keyword {
  const Keyword(this.kw, {this.n = 0, this.shiftClass, this.universalShift = false});
  final Kw kw;

  /// Challenger/Resist +N, Singer N, Sing Together N, Boost and Shift costs.
  final int n;

  /// [Classification] Shift (CR 8.10.8.1).
  final String? shiftClass;

  /// Universal Shift (CR 8.10.8.2).
  final bool universalShift;

  String get key => '${kw.name}$n${shiftClass ?? ''}${universalShift ? 'u' : ''}';
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
  );

  String describe() {
    final b = <String>[];
    if (owner == Owner.yours) b.add('your');
    if (owner == Owner.opposing) b.add('opposing');
    if (other) b.add('other');
    if (exerted == true) b.add('exerted');
    if (exerted == false) b.add('ready');
    if (damaged == true) b.add('damaged');
    if (classes.isNotEmpty) b.add(classes.join('/'));
    b.add(types.map((t) => t.name).join('/'));
    if (named != null) b.add('named $named');
    if (costMax != null) b.add('cost≤$costMax');
    if (costMin != null) b.add('cost≥$costMin');
    if (strengthMax != null) b.add('S≤$strengthMax');
    if (strengthMin != null) b.add('S≥$strengthMin');
    if (withKw != null) b.add('with ${withKw!.name}');
    if (atLocation == true) b.add('at a location');
    if (atThisLocation) b.add('here');
    if (atSourcesLocation) b.add('at its location');
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
class AllOf extends Target {
  const AllOf(this.filter);
  final Filter filter;
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

enum Who { you, opponents, each, chosenOpponent, thatPlayer }

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
  const MoveDamage(this.from, this.to, this.amount);
  final Target from, to;
  final Amount amount;
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
enum Rule { cantQuest, cantChallenge, cantBeChallenged, cantReady, cantSing, mustChallenge, takesNoDamageFromChallenges }

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
  const LookTop(this.n, {this.pick, this.pickCount = 1, this.restBottom = true, this.reorderOnly = false});
  final int n;
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
class CardPlayed extends Trigger {
  const CardPlayed(this.filter, {this.by = Owner.yours});
  final Filter filter;
  final Owner by;
}

enum Event { quests, challenges, isChallenged, banished, banishedInChallenge, banishesInChallenge, sings, movesToLocation, dealtDamage, readied, exerted }

/// A card in [subject] does something. [subject] null: this card.
class CardEvent extends Trigger {
  const CardEvent(this.event, {this.subject});
  final Event event;
  final Filter? subject;
}

/// "At the start of your turn" / "at the end of your turn" (CR 3.2.1.4, 3.4.1.1).
class TurnStep extends Trigger {
  const TurnStep({required this.start, this.yours = true});
  final bool start, yours;
}

/// "Whenever you draw a card", "whenever an opponent draws".
class Draws extends Trigger {
  const Draws(this.by);
  final Owner by;
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
  const Cost({this.exert = false, this.ink = 0, this.banishSelf = false, this.discard = 0, this.exertOther, this.banishOther});
  final bool exert;
  final int ink;
  final bool banishSelf;
  final int discard;
  final Filter? exertOther;
  final Filter? banishOther;
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
