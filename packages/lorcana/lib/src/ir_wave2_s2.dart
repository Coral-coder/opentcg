part of 'ir.dart';

// ---------------------------------------------------------------------------------------------
// Wave 2, slice 2 (Gruesome And Grim … Mirabel Madrigal): parsed in parser/wave2_s2.dart,
// resolved in game/wave2_s2.dart.
// ---------------------------------------------------------------------------------------------

/// Choice slots the engine fills itself, apart from the parser's numbering from 0.
/// The card banished to pay an activated ability's cost ("the banished character").
const w2CostSlot = -1;

/// The characters that sang the song being resolved (CR 5.4.4, 8.12), inside [W2WithSingers].
const w2SingersSlot = -2;

/// The cards a [W2DiscardTrack] discarded ("if an Illusion character card is discarded this way").
const w2DiscardSlot = -3;

/// [amount] of damage a [W2TrackRemoved] removed ("damage removed this way").
const w2RemovedSlot = -4;

/// A [Filter] with conditions [Filter] doesn't have: an ink ("your other Amber characters"),
/// "that have a card under them", "who was challenged this turn", "with cost equal to or less
/// than this character's {s}".
class W2Filter extends Filter {
  const W2Filter({
    super.types,
    super.owner,
    super.other,
    super.classes,
    super.named,
    super.exerted,
    super.damaged,
    super.costMax,
    super.costMin,
    super.strengthMax,
    super.strengthMin,
    super.withKw,
    super.atLocation,
    super.atThisLocation,
    super.atSourcesLocation,
    super.song,
    this.ink,
    this.hasUnder,
    this.challengedThisTurn = false,
    this.costAtMostSourceStrength = false,
  });

  factory W2Filter.of(Filter f, {Ink? ink, bool? hasUnder, bool challengedThisTurn = false, bool costAtMostSourceStrength = false}) => W2Filter(
    types: f.types,
    owner: f.owner,
    other: f.other,
    classes: f.classes,
    named: f.named,
    exerted: f.exerted,
    damaged: f.damaged,
    costMax: f.costMax,
    costMin: f.costMin,
    strengthMax: f.strengthMax,
    strengthMin: f.strengthMin,
    withKw: f.withKw,
    atLocation: f.atLocation,
    atThisLocation: f.atThisLocation,
    atSourcesLocation: f.atSourcesLocation,
    song: f.song,
    ink: ink ?? (f is W2Filter ? f.ink : null),
    hasUnder: hasUnder ?? (f is W2Filter ? f.hasUnder : null),
    challengedThisTurn: challengedThisTurn || (f is W2Filter && f.challengedThisTurn),
    costAtMostSourceStrength: costAtMostSourceStrength || (f is W2Filter && f.costAtMostSourceStrength),
  );

  final Ink? ink;
  final bool? hasUnder;
  final bool challengedThisTurn;

  /// "With cost equal to or less than this character's {s}": the source's current strength.
  final bool costAtMostSourceStrength;

  @override
  W2Filter copyWith({
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
  }) => W2Filter.of(
    super.copyWith(
      types: types,
      owner: owner,
      other: other,
      classes: classes,
      named: named,
      exerted: exerted,
      damaged: damaged,
      costMax: costMax,
      costMin: costMin,
      strengthMax: strengthMax,
      strengthMin: strengthMin,
      withKw: withKw,
      atLocation: atLocation,
      atThisLocation: atThisLocation,
      atSourcesLocation: atSourcesLocation,
      song: song,
    ),
    ink: ink,
    hasUnder: hasUnder,
    challengedThisTurn: challengedThisTurn,
    costAtMostSourceStrength: costAtMostSourceStrength,
  );

  @override
  String describe() => [
    super.describe(),
    if (ink != null) ink!.label,
    if (hasUnder == true) 'with a card under',
    if (challengedThisTurn) 'challenged this turn',
    if (costAtMostSourceStrength) 'cost≤this.S',
  ].join(' ');
}

// ---------------------------------------------------------------------------------------------
// Effects
// ---------------------------------------------------------------------------------------------

sealed class W2Effect extends Effect {
  const W2Effect();
}

/// "Play a character with cost 4 or less for free" (CR 6.1.7), remembering the card in [slot]
/// ("they gain Rush"). [sameNameAsCost]: only cards with the name of the one banished for the
/// cost ("a character with the same name as the banished character"). [bottomAfter]: an action
/// played this way goes to the bottom of the deck instead of the discard (CR 6.1.7).
class W2PlayFree extends W2Effect {
  const W2PlayFree(this.filter, {this.from = Place.hand, this.slot, this.sameNameAsCost = false, this.bottomAfter = false});
  final Filter filter;
  final Place from;
  final int? slot;
  final bool sameNameAsCost;
  final bool bottomAfter;
}

/// "You may play her and she enters play exerted" (from the discard), "you may play it from
/// your discard": the source card is played from [from], paying its costs.
class W2PlayThis extends W2Effect {
  const W2PlayThis({this.from = Place.discard, this.exerted = false});
  final Place from;
  final bool exerted;
}

/// "You may play that character for free": the card remembered in [slot], from where it is.
class W2PlayRemembered extends W2Effect {
  const W2PlayRemembered(this.slot, this.filter);
  final int slot;
  final Filter filter;
}

/// "Reveal the top card of your deck. You may play it as if it were in your hand. Otherwise,
/// put it in your discard."
class W2PlayTop extends W2Effect {
  const W2PlayTop();
}

/// "Each player shuffles their deck and then reveals the top card. Each player who reveals a
/// character card may play that character for free. Otherwise, put the revealed cards on the
/// bottom of their player's deck."
class W2EachRevealPlay extends W2Effect {
  const W2EachRevealPlay(this.filter);
  final Filter filter;
}

/// "You may choose an opposing character": only the choice, for "if you do" and "that
/// character" after it.
class W2Choose extends W2Effect {
  const W2Choose(this.target);
  final Target target;
}

/// "[effect] unless that character's player puts that card on the bottom of their deck": the
/// owner of the card in [slot] decides.
class W2UnlessTuck extends W2Effect {
  const W2UnlessTuck(this.slot, this.effect);
  final int slot;
  final Effect effect;
}

/// "Put all cards from your hand into your inkwell facedown and exerted".
class W2HandToInkwell extends W2Effect {
  const W2HandToInkwell({this.exerted = true});
  final bool exerted;
}

/// "Search your deck for a X card and reveal it to all players. Shuffle your deck and put that
/// card on top of it" ([dest] top), "search your deck for any card, put that card into your
/// hand, then shuffle your deck" ([dest] hand).
class W2SearchDeck extends W2Effect {
  const W2SearchDeck(this.filters, this.dest, {this.reveal = true});
  final List<Filter> filters;
  final ZoneDest dest;
  final bool reveal;
}

/// "Put 2 cards from your hand on the top of your deck in any order", "put a card from your
/// hand on the bottom of your deck".
class W2HandToDeck extends W2Effect {
  const W2HandToDeck(this.n, {this.top = false});
  final int n;
  final bool top;
}

/// "Remove up to 4 damage total from any number of your characters. You gain 1 lore for each 1
/// damage removed this way."
class W2RemoveTotal extends W2Effect {
  const W2RemoveTotal(this.filter, this.n, {this.lorePer = 0});
  final Filter filter;
  final int n;
  final int lorePer;
}

/// "You and another chosen player each draw 2 cards": the other player's part.
class W2OtherPlayerDraws extends W2Effect {
  const W2OtherPlayerDraws(this.n);
  final int n;
}

/// "Each player exerts all the cards in their inkwell".
class W2ExertInkwell extends W2Effect {
  const W2ExertInkwell(this.who);
  final Who who;
}

/// "Each player with more than 3 cards in their inkwell returns cards at random from their
/// inkwell to their hand until they have 3 cards in their inkwell."
class W2TrimInkwell extends W2Effect {
  const W2TrimInkwell(this.who, this.n);
  final Who who;
  final int n;
}

/// "Put the top card of your deck into your discard. If its card type is: - character, A. -
/// action or item, B. - location, C."
class W2MillBranch extends W2Effect {
  const W2MillBranch(this.types, this.branches);
  final List<Set<CardType>> types;
  final List<Effect> branches;
}

/// A discard that remembers the cards in [w2DiscardSlot] ("if an Illusion character card is
/// discarded this way", "if you discarded a Pirate character card").
class W2DiscardTrack extends W2Effect {
  const W2DiscardTrack(this.discard);
  final Discard discard;
}

/// An effect done once for each [times] ("for each of your characters named Maleficent in
/// play, return a chosen …"): each time with its own choices.
class W2Repeat extends W2Effect {
  const W2Repeat(this.times, this.effect);
  final Amount times;
  final Effect effect;
}

/// "Opponents can't play actions or items until the start of your next turn".
class W2OpponentsCantPlay extends W2Effect {
  const W2OpponentsCantPlay(this.filter);
  final Filter filter;
}

/// "Your Hero characters gain "Whenever this character challenges…" this turn": a triggered
/// ability granted for a while; [quote] names it among the source card's abilities.
class W2GrantAbility extends W2Effect {
  const W2GrantAbility(this.target, this.quote, this.ability, this.duration);
  final Target target;
  final String quote;
  final Triggered ability;
  final Lasting duration;
}

/// "Give chosen character of yours the Hunny classification until the start of your next turn".
class W2GrantClass extends W2Effect {
  const W2GrantClass(this.target, this.classification, this.duration);
  final Target target;
  final String classification;
  final Lasting duration;
}

/// "This character … loses Reckless this turn".
class W2LoseKeyword extends W2Effect {
  const W2LoseKeyword(this.target, this.kw, this.duration);
  final Target target;
  final Kw kw;
  final Lasting duration;
}

/// "Each opponent can't ready more than 1 of their characters at the start of their next turn".
class W2ReadyLimit extends W2Effect {
  const W2ReadyLimit(this.n);
  final int n;
}

/// "Put the top card of your deck facedown under him" (CR 8.4.2).
class W2PutTopUnder extends W2Effect {
  const W2PutTopUnder(this.target);
  final Target target;
}

/// "Put all cards that were under him under another chosen character or location of yours".
class W2MoveFormerUnder extends W2Effect {
  const W2MoveFormerUnder(this.target);
  final Target target;
}

/// "Draw a card from the bottom of your deck".
class W2DrawBottom extends W2Effect {
  const W2DrawBottom();
}

/// "Shift a character from your discard for free" (CR 8.10).
class W2ShiftFromDiscard extends W2Effect {
  const W2ShiftFromDiscard();
}

/// "Reveal a song card in your hand" (as the first half of "X to Y").
class W2RevealInHand extends W2Effect {
  const W2RevealInHand(this.filter);
  final Filter filter;
}

/// "Each opponent chooses and discards either 2 cards or 1 action card".
class W2DiscardEither extends W2Effect {
  const W2DiscardEither(this.who, this.n, this.alt);
  final Who who;
  final int n;
  final Filter alt;
}

/// "Shuffle a card from any discard into its player's deck".
class W2ShuffleFromAnyDiscard extends W2Effect {
  const W2ShuffleFromAnyDiscard();
}

/// [effect], with the song's singers remembered in [w2SingersSlot] ("ready them").
class W2WithSingers extends W2Effect {
  const W2WithSingers(this.effect);
  final Effect effect;
}

/// Removes damage and remembers how much in [w2RemovedSlot] ("if you removed damage this way").
class W2TrackRemoved extends W2Effect {
  const W2TrackRemoved(this.effect);
  final Effect effect;
}

// ---------------------------------------------------------------------------------------------
// Conditions and amounts
// ---------------------------------------------------------------------------------------------

sealed class W2Cond extends Cond {
  const W2Cond();
}

/// "If 2 or more characters sang this song".
class W2SingersCond extends W2Cond {
  const W2SingersCond(this.n);
  final int n;
}

/// "If you've played a character with cost 5 or more this turn".
class W2PlayedThisTurn extends W2Cond {
  const W2PlayedThisTurn(this.filter);
  final Filter filter;
}

/// "If an opponent has 2 or more ready characters in play": some one opponent has them.
class W2OpponentHas extends W2Cond {
  const W2OpponentHas(this.filter, this.n);
  final Filter filter;
  final int n;
}

/// "If an Illusion character card is discarded this way".
class W2DiscardedIs extends W2Cond {
  const W2DiscardedIs(this.filter);
  final Filter filter;
}

/// "If you removed damage this way".
class W2RemovedAny extends W2Cond {
  const W2RemovedAny();
}

/// "If the banished item is named Maurice's Machine": the card in [slot], wherever it is now.
class W2SlotIs extends W2Cond {
  const W2SlotIs(this.slot, this.filter);
  final int slot;
  final Filter filter;
}

/// "If there's a card under that character".
class W2SlotHasUnder extends W2Cond {
  const W2SlotHasUnder(this.slot);
  final int slot;
}

/// "If you've put a card under her this turn".
class W2PutUnderThisTurn extends W2Cond {
  const W2PutUnderThisTurn();
}

/// "If he had a card under him" (as he left play; CR 6.7.7).
class W2HadUnder extends W2Cond {
  const W2HadUnder();
}

/// "If you discarded a card this turn".
class W2DiscardedThisTurn extends W2Cond {
  const W2DiscardedThisTurn();
}

sealed class W2Amount extends Amount {
  const W2Amount();
}

/// The triggering event's amount: "deal that much damage", "for each 1 damage removed".
class W2EventAmount extends W2Amount {
  const W2EventAmount();
}

/// "The cost of one of your items in play".
class W2CostOf extends W2Amount {
  const W2CostOf(this.target);
  final Target target;
}

/// "For each 1 damage removed this way".
class W2RemovedAmount extends W2Amount {
  const W2RemovedAmount();
}

// ---------------------------------------------------------------------------------------------
// Static abilities
// ---------------------------------------------------------------------------------------------

sealed class W2Static extends StaticEffect {
  const W2Static();
}

/// "All cards in your hand count as having {IW}" (CR 4.2: they can be put into the inkwell).
class W2HandInkable extends W2Static {
  const W2HandInkable();
}

/// "For each location you have in play, this character gains Resist +1": the keyword's N.
class W2KeywordPer extends W2Static {
  const W2KeywordPer(this.kw, this.count);
  final Kw kw;
  final CountOf count;
}

/// "This character can't be dealt damage unless he's being challenged" ([affected] null), "your
/// other Hero characters can't be dealt damage unless they're being challenged".
class W2NoDamageUnlessChallenged extends W2Static {
  const W2NoDamageUnlessChallenged([this.affected]);
  final Filter? affected;
}

/// "The first time this character would take damage, she takes no damage instead" (CR 6.5).
class W2FirstDamagePrevented extends W2Static {
  const W2FirstDamagePrevented();
}

/// "Opponents must choose this character for actions and abilities if able".
class W2MustBeChosen extends W2Static {
  const W2MustBeChosen();
}

/// "Your Pirate characters may move here for free" ([filter]), "you pay 1 {i} less to move your
/// characters to a location" ([less]).
class W2MoveCost extends W2Static {
  const W2MoveCost(this.filter, {this.here = false, this.less = 0});
  final Filter filter;
  final bool here;
  final int less;
}

/// "If an effect would cause you to discard one or more cards, you don't discard".
class W2NoDiscard extends W2Static {
  const W2NoDiscard();
}

/// "You can't lose lore".
class W2NoLoseLore extends W2Static {
  const W2NoLoseLore();
}

/// "You can't play this character" (while its condition holds).
class W2CantPlayThis extends W2Static {
  const W2CantPlayThis();
}

/// "You may put a Toy character card from your discard on the bottom of your deck to play this
/// character for free" (an alternate cost, CR 1.5.5): [count] cards matching [filter] from the
/// discard to the bottom of the deck; for Shift when [shift].
class W2AltCost extends W2Static {
  const W2AltCost(this.filter, this.count, {this.shift = false});
  final Filter filter;
  final int count;
  final bool shift;
}

/// "Each player plays with the top card of their deck face up".
class W2TopCardFaceUp extends W2Static {
  const W2TopCardFaceUp();
}

/// "She gains "Whenever this character is challenged, …"": a granted triggered ability.
class W2StaticTrigger extends W2Static {
  const W2StaticTrigger(this.affected, this.ability);
  final Filter? affected;
  final Triggered ability;
}

/// "You may use this item's Shapeshift ability for free" (CR 6.1.7.1: only {e} is paid).
class W2FreeAbility extends W2Static {
  const W2FreeAbility(this.name);
  final String name;
}

/// "If this character would be banished, put them into your inkwell facedown and exerted
/// instead" (CR 6.5).
class W2BanishToInkwell extends W2Static {
  const W2BanishToInkwell();
}

// ---------------------------------------------------------------------------------------------
// Triggers and abilities
// ---------------------------------------------------------------------------------------------

sealed class W2Trigger extends Trigger {
  const W2Trigger();
}

/// "Whenever a card leaves your discard".
class W2LeavesDiscard extends W2Trigger {
  const W2LeavesDiscard();
}

/// "Whenever another character of yours enters play exerted".
class W2EntersExerted extends W2Trigger {
  const W2EntersExerted(this.subject);
  final Filter subject;
}

/// "Once during your turn, you may pay 1 {i} to …": an activated ability usable once a turn.
class W2OnceActivated extends Activated {
  const W2OnceActivated(super.text, super.cost, super.effect);
}
