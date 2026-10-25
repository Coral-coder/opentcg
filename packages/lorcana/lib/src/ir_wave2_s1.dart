part of 'ir.dart';

// ---------------------------------------------------------------------------------------------
// Wave 2, slice 1: granted abilities and classifications, searching decks, choices made by
// other players, and the payment and play rules a few cards change. Parsed in
// parser/wave2_s1.dart, resolved in game/wave2_s1.dart.
// ---------------------------------------------------------------------------------------------

/// The ink types as pseudo-classifications ("your other Sapphire characters"): [Filter.classes]
/// entries with this prefix match a card's ink, not its classifications (CR 5.2.5).
const w1InkClass = 'ink:';

/// Something a card has for a while (CR 6.4.2): an ability in quotes ("gain '{e} - Draw a
/// card' this turn"), a keyword, a rule or a classification. With [whileSource] it lasts while
/// its source stays in play ("while this item is in play, that location gains Evasive").
class W1Grant {
  const W1Grant({
    required this.ts,
    required this.controller,
    required this.source,
    required this.sourceZcc,
    required this.lasting,
    required this.turn,
    required this.cards,
    required this.zccs,
    this.whileSource = false,
    this.ability,
    this.keyword,
    this.rule,
    this.cls,
  });
  final int ts, controller, source, sourceZcc;
  final Lasting lasting;
  final int turn;
  final List<int> cards, zccs;
  final bool whileSource;
  final Ability? ability;
  final Keyword? keyword;
  final Rule? rule;
  final String? cls;

  String digest() =>
      '$ts|$controller|$source.$sourceZcc|${lasting.index}|$turn|${cards.join(',')}|${zccs.join(',')}|$whileSource|${ability == null ? '' : '${ability!.text.length}:${ability!.text}'}|${keyword?.key ?? ''}|${rule?.index ?? ''}|${cls ?? ''}';
}

// ---------------------------------------------------------------------------------------------
// Abilities
// ---------------------------------------------------------------------------------------------

/// An activated ability with limits beyond its cost (CR 6.3): "once during your turn, you may
/// …" abilities, and extra costs such as "banish 2 of your items" (CR 4.4).
class W1Activated extends Activated {
  const W1Activated(super.text, super.cost, super.effect, {this.oncePerTurn = false, this.yourTurn = false, this.banish, this.banishCount = 0});
  final bool oncePerTurn, yourTurn;

  /// Banish [banishCount] of your cards matching [banish] as part of the cost.
  final Filter? banish;
  final int banishCount;
}

// ---------------------------------------------------------------------------------------------
// Triggers
// ---------------------------------------------------------------------------------------------

sealed class W1Trigger extends Trigger {
  const W1Trigger();
  String describe();
}

/// "Whenever you use the Boost ability of a character" (CR 8.4).
class W1Boosted extends W1Trigger {
  const W1Boosted();
  @override
  String describe() => 'you boost a character';
}

/// "Whenever one of your characters or locations with a card under them is challenged".
class W1ChallengedWithUnder extends W1Trigger {
  const W1ChallengedWithUnder();
  @override
  String describe() => 'your character/location with a card under it is challenged';
}

// ---------------------------------------------------------------------------------------------
// Amounts
// ---------------------------------------------------------------------------------------------

sealed class W1Amount extends Amount {
  const W1Amount();
  String describe();
}

/// "For each 1 damage removed this way", "that many", "equal to the lore lost this way": what the
/// effect before it counted.
class W1ThisWay extends W1Amount {
  const W1ThisWay({this.per = 1, this.plus = 0});
  final int per, plus;
  @override
  String describe() => '$per×this way${plus > 0 ? '+$plus' : ''}';
}

/// "For each character that sang this song" (CR 5.4.4).
class W1Singers extends W1Amount {
  const W1Singers();
  @override
  String describe() => 'singers';
}

/// "For each card that was under them": the cards under the event card as it left play.
class W1UnderEvent extends W1Amount {
  const W1UnderEvent();
  @override
  String describe() => 'cards that were under the event card';
}

/// "Equal to that location's {l}": the lore of the location this character is at.
class W1LocationLore extends W1Amount {
  const W1LocationLore();
  @override
  String describe() => 'lore of this character\'s location';
}

// ---------------------------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------------------------

sealed class W1Cond extends Cond {
  const W1Cond();
  String describe();
}

/// "If a card left a player's discard this turn".
class W1LeftDiscard extends W1Cond {
  const W1LeftDiscard();
  @override
  String describe() => 'a card left a discard this turn';
}

/// "If you discarded a card this turn" (from your hand, CR 7.4.5).
class W1DiscardedThisTurn extends W1Cond {
  const W1DiscardedThisTurn();
  @override
  String describe() => 'you discarded this turn';
}

/// "If you played a Princess character this turn".
class W1PlayedThisTurn extends W1Cond {
  const W1PlayedThisTurn(this.filter);
  final Filter filter;
  @override
  String describe() => 'you played ${filter.describe()} this turn';
}

/// "If you removed damage this way".
class W1DidSome extends W1Cond {
  const W1DidSome();
  @override
  String describe() => 'did some this way';
}

/// "If you have another character with 4 {w} or more in play".
class W1WillpowerCount extends W1Cond {
  const W1WillpowerCount(this.min, {this.other = false});
  final int min;
  final bool other;
  @override
  String describe() => 'you have ${other ? 'another ' : ''}character with W≥$min';
}

// ---------------------------------------------------------------------------------------------
// Static effects
// ---------------------------------------------------------------------------------------------

sealed class W1Static extends StaticEffect {
  const W1Static();
  String describe();

  /// Works from the hand ([Static.inHand]).
  bool get inHand => false;
}

/// "Your characters with Reckless gain '{e} - Gain 1 lore'" (an ability in quotes, CR 6.4).
class W1GrantAbility extends W1Static {
  const W1GrantAbility(this.affected, this.ability);
  final Filter affected;
  final Ability ability;
  @override
  String describe() => '${affected.describe()} gain "${ability.text}"';
}

/// "Your other characters gain the Detective classification".
class W1GrantClass extends W1Static {
  const W1GrantClass(this.affected, this.cls);
  final Filter affected;
  final String cls;
  @override
  String describe() => '${affected.describe()} gain the $cls classification';
}

/// "Your Gargoyle characters lose the Stone by Day ability".
class W1LoseAbility extends W1Static {
  const W1LoseAbility(this.affected, this.name);
  final Filter affected;

  /// The ability's story name, lower case.
  final String name;
  @override
  String describe() => '${affected.describe()} lose $name';
}

/// "Characters count as having +2 cost to sing songs while here" (CR 8.11).
class W1SingCost extends W1Static {
  const W1SingCost(this.affected, this.n);
  final Filter affected;
  final int n;
  @override
  String describe() => '${affected.describe()} sing as +$n cost';
}

/// "Opponents can't choose your items for abilities or effects" (like Ward, CR 8.15).
class W1Unchoosable extends W1Static {
  const W1Unchoosable(this.affected);
  final Filter affected;
  @override
  String describe() => 'opponents can\'t choose ${affected.describe()}';
}

/// "You may banish chosen item of yours to play this character for free" (from the hand; an
/// alternate cost, CR 4.3.2.2).
class W1BanishToPlay extends W1Static {
  const W1BanishToPlay(this.filter);
  final Filter filter;
  @override
  bool get inHand => true;
  @override
  String describe() => 'may banish ${filter.describe()} to play this free';
}

/// "You pay 1 {i} less to shift a character on top of this character".
class W1ShiftOntoDiscount extends W1Static {
  const W1ShiftOntoDiscount(this.n);
  final int n;
  @override
  String describe() => 'shift onto this costs $n less';
}

/// "For each item card in your discard, you pay 1 {i} less to play this character using her
/// Shift ability" (from the hand).
class W1ShiftDiscount extends W1Static {
  const W1ShiftDiscount(this.amount);
  final Amount amount;
  @override
  bool get inHand => true;
  @override
  String describe() => 'shift costs less';
}

/// "If a card left a player's discard this turn, this character gains Shift 0" (from the hand).
class W1HandShift extends W1Static {
  const W1HandShift(this.keyword);
  final Keyword keyword;
  @override
  bool get inHand => true;
  @override
  String describe() => 'gains ${keyword.key} in hand';
}

/// "Whenever one of your other characters would be dealt damage, put that many damage counters
/// on this character instead" (a replacement, CR 6.5).
class W1RedirectDamage extends W1Static {
  const W1RedirectDamage(this.affected);
  final Filter affected;
  @override
  String describe() => 'damage to ${affected.describe()} goes to this';
}

/// "You can have other Hunny characters in your deck regardless of ink type" (CR 1.10.1.1).
class W1InkException extends W1Static {
  const W1InkException(this.cls);
  final String cls;
  @override
  String describe() => 'any-ink $cls characters in the deck';
}

/// The classifications a deck's "regardless of ink type" abilities free, lower case.
Set<String> w1AnyInkClasses(Iterable<Ability> deckAbilities) => {
  for (final a in deckAbilities)
    if (a is Static && a.effect is W1InkException) (a.effect as W1InkException).cls,
};

/// Does [c] not count toward the deck's ink types (CR 1.10.1.1)? "Other" characters only: not a
/// card with the ability itself.
bool w1InkExempt(LCard c, Set<String> classes, List<Ability> own) =>
    classes.isNotEmpty && c.type == CardType.character && classes.any(c.hasClass) && !own.any((a) => a is Static && a.effect is W1InkException);

/// "This character can challenge ready Villain characters" (CR 4.6.4 exception).
class W1ChallengeReady extends W1Static {
  const W1ChallengeReady(this.defenders);
  final Filter defenders;
  @override
  String describe() => 'can challenge ready ${defenders.describe()}';
}

/// "Your other Ruby characters with 7 {s} or more get +1 {l}": judged on the final {s}.
class W1ModIfStrength extends W1Static {
  const W1ModIfStrength(this.affected, this.min, this.stat, this.n);
  final Filter affected;
  final int min;
  final Stat stat;
  final int n;
  @override
  String describe() => '${affected.describe()} with S≥$min +$n ${stat.name}';
}

/// "Your characters' {s} can't be reduced below their printed value".
class W1StrengthFloor extends W1Static {
  const W1StrengthFloor(this.affected);
  final Filter affected;
  @override
  String describe() => '${affected.describe()} S never below printed';
}

/// "You can't play this action unless…" (from the hand; the [Static.condition] must hold).
class W1PlayOnlyIf extends W1Static {
  const W1PlayOnlyIf();
  @override
  bool get inHand => true;
  @override
  String describe() => 'can only be played when the condition holds';
}

/// "Opponents can't play actions with cost 4 or more".
class W1OpponentsCantPlay extends W1Static {
  const W1OpponentsCantPlay(this.filter);
  final Filter filter;
  @override
  String describe() => 'opponents can\'t play ${filter.describe()}';
}

/// "Each player pays 2 {i} more to play actions or items" (CR 4.3.6; not when singing).
class W1CostIncrease extends W1Static {
  const W1CostIncrease(this.filter, this.n);
  final Filter filter;
  final int n;
  @override
  String describe() => 'everyone pays $n more for ${filter.describe()}';
}

/// "Once during your turn, you pay 1 {i} less for the next character you play this turn".
class W1FirstDiscount extends W1Static {
  const W1FirstDiscount(this.filter, this.n);
  final Filter filter;
  final int n;
  @override
  String describe() => 'once a turn, next ${filter.describe()} costs $n less';
}

// ---------------------------------------------------------------------------------------------
// Effects
// ---------------------------------------------------------------------------------------------

sealed class W1Effect extends Effect {
  const W1Effect();
  String describe();
}

/// "Put any number of cards from your hand on the bottom of your deck in any order. If you do,
/// draw that number of cards plus [plus]."
class W1HandToBottom extends W1Effect {
  const W1HandToBottom({this.all = false, this.drawPlus});
  final bool all;
  final int? drawPlus;
  @override
  String describe() => '${all ? 'all' : 'any number of'} cards from hand to deck bottom${drawPlus == null ? '' : ', draw that many +$drawPlus'}';
}

/// "Ready those characters": the characters that sang the song.
class W1ReadySingers extends W1Effect {
  const W1ReadySingers();
  @override
  String describe() => 'ready the singers';
}

enum W1SearchDest { hand, topAfterShuffle }

/// "Search your deck for a X card and reveal that card to all players" (CR 7.2): then into the
/// hand (and shuffle) or, after shuffling, on top.
class W1Search extends W1Effect {
  const W1Search(this.filters, this.dest, {this.shuffle = true});
  final List<Filter> filters;
  final W1SearchDest dest;
  final bool shuffle;
  @override
  String describe() => 'search deck for ${filters.map((f) => f.describe()).join(' or ')} → ${dest.name}${shuffle ? ', shuffle' : ''}';
}

/// "Shuffle your deck".
class W1Shuffle extends W1Effect {
  const W1Shuffle();
  @override
  String describe() => 'shuffle deck';
}

/// "Choose a character": the choice, for "they" and "that character" later (CR 6.1.3).
class W1Pick extends W1Effect {
  const W1Pick(this.target);
  final Chosen target;
  @override
  String describe() => 'choose ${target.filter.describe()} #${target.slot}';
}

/// "Gain lore equal to the {l} of a character card in your discard. If you do, put that card on
/// the bottom of your deck."
class W1LoreFromDiscard extends W1Effect {
  const W1LoreFromDiscard(this.filter);
  final Filter filter;
  @override
  String describe() => 'gain the lore of a ${filter.describe()} in discard, it goes to deck bottom';
}

/// "Reveal a number of cards from the top of your deck equal to [amount]. Put all revealed X
/// cards into your hand. Put the rest on the bottom of your deck in any order."
class W1RevealTake extends W1Effect {
  const W1RevealTake(this.amount, this.take);
  final Amount amount;
  final Filter take;
  @override
  String describe() => 'reveal top N, take all ${take.describe()}, rest bottom';
}

/// "Play a character with the same name as this character for free" (from the hand).
class W1PlaySameName extends W1Effect {
  const W1PlaySameName();
  @override
  String describe() => 'play a character with the same name free';
}

/// "Choose any number of players. They discard their hands and draw 3 cards each."
class W1RefreshPlayers extends W1Effect {
  const W1RefreshPlayers(this.n);
  final int n;
  @override
  String describe() => 'chosen players discard hands, draw $n';
}

/// "Play another character with the same cost or less for free": no more than the card in
/// [slot] costs.
class W1PlayFreeCostOf extends W1Effect {
  const W1PlayFreeCostOf(this.slot);
  final int slot;
  @override
  String describe() => 'play another character with cost ≤ #$slot free';
}

/// A grant for a while: an ability in quotes, a keyword, a rule or a classification.
class W1GrantTimed extends W1Effect {
  const W1GrantTimed(this.target, this.lasting, {this.ability, this.keyword, this.rule, this.cls, this.whileSource = false});
  final Target target;
  final Lasting lasting;
  final Ability? ability;
  final Keyword? keyword;
  final Rule? rule;
  final String? cls;
  final bool whileSource;
  @override
  String describe() => 'grant ${ability != null ? '"${ability!.text}"' : keyword?.key ?? rule?.name ?? '$cls classification'} (${whileSource ? 'while this is in play' : lasting.name})';
}

/// "Move all damage counters from all other characters to that character".
class W1MoveAllDamageTo extends W1Effect {
  const W1MoveAllDamageTo(this.target);
  final Target target;
  @override
  String describe() => 'move all damage from other characters to the target';
}

/// "Move chosen character from here to another location for free".
class W1MoveFromHere extends W1Effect {
  const W1MoveFromHere();
  @override
  String describe() => 'move a character from here to another location free';
}

/// "That player may play a character from their discard for free", "you may play a location
/// from your hand or discard with cost 4 or less for free".
class W1PlayFreeFrom extends W1Effect {
  const W1PlayFreeFrom(this.who, this.filter, this.from, {this.optional = true});
  final Who who;
  final Filter filter;
  final List<Place> from;
  final bool optional;
  @override
  String describe() => '${who.name} ${optional ? 'may ' : ''}play ${filter.describe()} free from ${from.map((p) => p.name).join('/')}';
}

/// "Return a character card with 4 {w} or more from your discard to your hand".
class W1ReturnByWillpower extends W1Effect {
  const W1ReturnByWillpower(this.min);
  final int min;
  @override
  String describe() => 'return a character with W≥$min from discard';
}

/// "Each player reveals the top card of their deck. Draw a card for each different ink symbol on
/// cards revealed this way."
class W1InkSymbols extends W1Effect {
  const W1InkSymbols();
  @override
  String describe() => 'each reveals top card, draw per ink';
}

/// "Chosen opponent chooses YES! or NO!": like "choose one", but that player chooses
/// (CR 6.1.5.2); the options act as yours, "they" being that player.
class W1OpponentChooses extends W1Effect {
  const W1OpponentChooses(this.options, this.labels);
  final List<Effect> options;
  final List<String> labels;
  @override
  String describe() => 'chosen opponent picks one';
}

/// "Choose and discard any number of cards, then draw that many cards."
class W1DiscardAny extends W1Effect {
  const W1DiscardAny({this.filter, this.thenDraw = false});
  final Filter? filter;
  final bool thenDraw;
  @override
  String describe() => 'discard any number of ${filter?.describe() ?? 'cards'}${thenDraw ? ', draw that many' : ''}';
}

/// "Banish one of your characters with Reckless to banish chosen character with less {s} than
/// that character".
class W1BanishWeaker extends W1Effect {
  const W1BanishWeaker(this.own, this.target);
  final Filter own, target;
  @override
  String describe() => 'banish your ${own.describe()} to banish a weaker ${target.describe()}';
}

/// "For each opposing player, you may choose a character of theirs. They can't ready at the
/// start of their next turn."
class W1EachOpponentPick extends W1Effect {
  const W1EachOpponentPick(this.filter, this.rule);
  final Filter filter;
  final Rule rule;
  @override
  String describe() => 'per opponent, may choose ${filter.describe()}: ${rule.name}';
}

/// "Each player chooses 2 of their characters and puts them into their inkwell facedown and
/// exerted."
class W1EachChoosesN extends W1Effect {
  const W1EachChoosesN(this.who, this.filter, this.n, this.slot, this.then);
  final Who who;
  final Filter filter;
  final int n, slot;
  final Effect then;
  @override
  String describe() => '${who.name} each choose $n own ${filter.describe()} #$slot';
}

/// "Move 1 damage counter from each damaged character you have in play to chosen opposing
/// character" (counted for "this way").
class W1MoveDamageEach extends W1Effect {
  const W1MoveDamageEach(this.from, this.to, this.n);
  final Filter from;
  final Target to;
  final int n;
  @override
  String describe() => 'move $n damage from each ${from.describe()} to the target';
}

/// "All opponents lose 1 lore and you gain lore equal to the lore lost this way."
class W1StealLore extends W1Effect {
  const W1StealLore(this.n);
  final int n;
  @override
  String describe() => 'opponents lose $n lore, you gain it';
}

/// "Reveal cards from the top of your deck until you reveal a X card. Put that card into your
/// hand and shuffle the rest into your deck."
class W1RevealUntil extends W1Effect {
  const W1RevealUntil(this.filter);
  final Filter filter;
  @override
  String describe() => 'reveal until ${filter.describe()}, take it, shuffle the rest';
}

/// "The player or players with the most cards in their hand chooses and discards a card."
class W1MostCardsDiscard extends W1Effect {
  const W1MostCardsDiscard(this.n);
  final int n;
  @override
  String describe() => 'player(s) with the most cards discard $n';
}

/// "Characters can't exert to sing songs until the start of your next turn": every card that
/// matches, now or later (a continuous effect, CR 6.4.2).
class W1RuleForAll extends W1Effect {
  const W1RuleForAll(this.filter, this.rule, this.lasting);
  final Filter filter;
  final Rule rule;
  final Lasting lasting;
  @override
  String describe() => 'all ${filter.describe()} ${rule.name} (${lasting.name})';
}

/// "They choose and discard cards until they have 2. If they have fewer than 2 cards in their
/// hand, they draw until they have 2" (the turn's player).
class W1HandToSize extends W1Effect {
  const W1HandToSize(this.n);
  final int n;
  @override
  String describe() => 'that player discards or draws to $n cards';
}

/// "Ready each character you removed damage from this way."
class W1ReadyHealed extends W1Effect {
  const W1ReadyHealed();
  @override
  String describe() => 'ready each character healed this way';
}

/// "Put the top card of your deck under them facedown" (CR 8.4.2).
class W1TopUnder extends W1Effect {
  const W1TopUnder(this.target);
  final Target target;
  @override
  String describe() => 'top of deck under the target';
}

/// [inner] (cards from your discard), counted for "this way" by how many left the discard.
class W1Counted extends W1Effect {
  const W1Counted(this.inner);
  final Effect inner;
  @override
  String describe() => 'counted: cards that leave the discard';
}

/// "Reveal the top card of your deck. If you do, you may play it. Otherwise, put it into your
/// discard. (You pay all costs.)"
class W1RevealMayPlay extends W1Effect {
  const W1RevealMayPlay();
  @override
  String describe() => 'reveal top card, may play it paying its cost, else discard it';
}
