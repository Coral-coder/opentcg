part of 'ir.dart';

/// Wave 2, slice 1 (parser/w2s1.dart, game/w2s1.dart): one-off rules text from Acceleration Gate
/// to Fiora, Peerless. Most cards reuse the families' effects; these are what they lacked.

/// Effects of this slice. [targets] are chosen like the core's ([Choose]) as the effect is
/// played; [picks] are this slice's own choices (game/w2s1.dart, [S1Pick]).
abstract class S1Effect extends Effect {
  const S1Effect();
  List<Target> get targets => const [];
  List<S1Pick> get picks => const [];
  List<List<Effect>> get nested => const [];
  String describe();
}

/// A choice made as the effect is played, kept in target slots [slot] to [slot]+[n]-1.
class S1Pick {
  const S1Pick(this.kind, this.slot, {this.n = 1, this.other = -1});
  final S1PickKind kind;
  final int slot, n;

  /// The slot whose choice this one must differ from ("another friendly unit").
  final int other;
}

enum S1PickKind {
  /// Up to [S1Pick.n] exhausted units, gear and runes (Acceleration Gate).
  readyables,

  /// A friendly unit (another one than slot [S1Pick.other] when set).
  friendlyUnit,

  /// An enemy unit at a battlefield (Crescent Strike: the battlefield goes in the next slot).
  enemyUnitAtBfWithBf,

  /// A friendly unit in combat with an enemy Fury unit or chosen by an enemy Fury spell.
  furyThreatened,

  /// A unit at a battlefield, or a gear (Fading Memories).
  unitAtBfOrGear,

  /// Up to one enemy unit at each location (Elder Dragon): [S1Pick.n] slots.
  enemyPerLocation,

  /// Any unit (Dominus, Dancing Grenade).
  anyUnit,
}

/// "Ready up to N units, gear, and/or runes."
class S1ReadyPicked extends S1Effect {
  const S1ReadyPicked(this.pick);
  final S1Pick pick;
  @override
  List<S1Pick> get picks => [pick];
  @override
  String describe() => 'ready up to ${pick.n} units, gear or runes';
}

/// "Put a card from your hand on the top or bottom of your Main Deck."
class S1HandToDeck extends S1Effect {
  const S1HandToDeck();
  @override
  String describe() => 'put a card from hand on top or bottom of the deck';
}

/// "Pay any amount of Energy to [Add] that much {A}." (a resource ability, CR 337.2)
class S1EnergyToPower extends AddRes {
  const S1EnergyToPower();
}

/// "[Add] {1}. Spend this Energy only during showdowns." Usable only while a showdown is on.
class S1ShowdownEnergy extends AddRes {
  const S1ShowdownEnergy(int n) : super(energy: n);
}

/// Ashe, Focused: an opponent reveals their hand; a card from it is banished until they hold.
class S1BanishUntilHold extends S1Effect {
  const S1BanishUntilHold();
  @override
  String describe() => 'opponent reveals hand; banish a card of it until they hold';
}

/// "Give … [Keyword N]" with no duration: as long as it stays on the board (CR 801.3.a.3).
class S1GiveKw extends S1Effect {
  const S1GiveKw(this.kw, this.n, this.target, {this.pick});
  final Kw kw;
  final int n;
  final Target target;

  /// The object is this slice's choice instead ([target] is then [Chosen] of its slot).
  final S1Pick? pick;
  @override
  List<Target> get targets => pick == null ? [target] : const [];
  @override
  List<S1Pick> get picks => [?pick];
  @override
  String describe() => 'give ${kw.name}${n > 1 ? ' $n' : ''} (lasting)';
}

/// "You may kill N other friendly units and/or gear to [effects]."
class S1KillManyTo extends S1Effect {
  const S1KillManyTo(this.n, this.effects);
  final int n;
  final List<Effect> effects;
  @override
  List<List<Effect>> get nested => [effects];
  @override
  String describe() => 'may kill $n other friendly units/gear to ${effects.map(describeEffect).join(', ')}';
}

/// "Then, choose an opponent. They move a unit they control to the same battlefield." [destSlot]
/// holds the battlefield the first move went to (a [Move]'s destination).
class S1OpponentFollows extends S1Effect {
  const S1OpponentFollows(this.destSlot);
  final int destSlot;
  @override
  String describe() => 'opponent moves a unit of theirs to the same battlefield';
}

/// Card Sharp: you and each opponent may play a Gold token; another for you per opponent who did.
class S1GoldForAll extends S1Effect {
  const S1GoldForAll();
  @override
  String describe() => 'you and each opponent may play a Gold; you get one more per opponent who did';
}

/// "Channel N runes exhausted. If you couldn't channel N runes this way, draw M."
class S1ChannelElseDraw extends S1Effect {
  const S1ChannelElseDraw(this.n, this.draw);
  final int n, draw;
  @override
  String describe() => 'channel $n exhausted; if fewer, draw $draw';
}

/// "This turn, increase its Might to the Might of another friendly unit."
class S1RaiseMight extends S1Effect {
  const S1RaiseMight(this.first, this.second);
  final S1Pick first, second;
  @override
  List<S1Pick> get picks => [first, second];
  @override
  String describe() => "raise a friendly unit's Might to another's this turn";
}

/// Crescent Strike: "Deal N to that unit and M to each other enemy unit there."
class S1StrikeThere extends S1Effect {
  const S1StrikeThere(this.pick, this.n, this.others);
  final S1Pick pick;
  final int n, others;
  @override
  List<S1Pick> get picks => [pick];
  @override
  String describe() => 'deal $n to an enemy unit at a battlefield and $others to each other enemy unit there';
}

/// Dancing Grenade: deal N to a unit; its controller may play the spell again for {A}, and then
/// it deals 1 Bonus Damage for each time it has dealt damage this turn.
class S1Grenade extends S1Effect {
  const S1Grenade(this.pick, this.n);
  final S1Pick pick;
  final int n;
  @override
  List<S1Pick> get picks => [pick];
  @override
  String describe() => 'deal $n to a unit; its controller may play this again for {A}';
}

/// Dazzling Aurora: reveal until a unit, play it ignoring its cost, recycle the rest.
class S1RevealPlayUnit extends S1Effect {
  const S1RevealPlayUnit();
  @override
  String describe() => 'reveal until a unit; play it free, recycle the rest';
}

/// Deathgrip: "Kill a friendly unit to give +{M} equal to its Might to another friendly unit this
/// turn."
class S1KillToGive extends S1Effect {
  const S1KillToGive(this.victim, this.receiver);
  final S1Pick victim, receiver;
  @override
  List<S1Pick> get picks => [victim, receiver];
  @override
  String describe() => "kill a friendly unit to give another its Might this turn";
}

/// "Give it +N {M} this turn" for a unit picked by this slice ([Chosen] can't see it ahead).
class S1GiveMightPicked extends S1Effect {
  const S1GiveMightPicked(this.pick, this.n);
  final S1Pick pick;
  final int n;
  @override
  List<S1Pick> get picks => [pick];
  @override
  String describe() => 'give +$n Might this turn';
}

/// "Reveal the top card of your Main Deck. If it's a spell, draw it."
class S1RevealDrawSpell extends S1Effect {
  const S1RevealDrawSpell();
  @override
  String describe() => 'reveal the top card; draw it if a spell';
}

/// Divine Judgment: each player keeps N units, gear, runes and hand cards and recycles the rest.
class S1Judgment extends S1Effect {
  const S1Judgment(this.n);
  final int n;
  @override
  String describe() => 'each player keeps $n units, gear, runes, hand cards; recycle the rest';
}

/// Dominus: "This turn, double a unit's Might and give it "[ability]"."
class S1DoubleAndGrant extends S1Effect {
  const S1DoubleAndGrant(this.pick, this.ability);
  final S1Pick pick;
  final Activated ability;
  @override
  List<S1Pick> get picks => [pick];
  @override
  String describe() => 'double a unit\'s Might and it has "${ability.text}" this turn';
}

/// "Choose an opponent. They score N point(s)."
class S1OpponentScores extends S1Effect {
  const S1OpponentScores(this.n);
  final int n;
  @override
  String describe() => 'an opponent scores $n';
}

/// "Recycle me to [effects]": a unit in its owner's trash (Deathknell) recycles itself first.
class S1RecycleMeTo extends S1Effect {
  const S1RecycleMeTo(this.effects);
  final List<Effect> effects;
  @override
  List<List<Effect>> get nested => [effects];
  @override
  String describe() => 'recycle me to ${effects.map(describeEffect).join(', ')}';
}

/// "Ready your runes."
class S1ReadyRunes extends S1Effect {
  const S1ReadyRunes();
  @override
  String describe() => 'ready your runes';
}

/// Elder Dragon: "Choose up to one enemy unit at each location. Deal N to them."
class S1DealPerLocation extends S1Effect {
  const S1DealPerLocation(this.pick, this.n);
  final S1Pick pick;
  final int n;
  @override
  List<S1Pick> get picks => [pick];
  @override
  String describe() => 'deal $n to up to one enemy unit at each location';
}

/// Emperor's Dais: "You may pay {N} and return a unit you control here to its owner's hand. If you
/// do, play a [token] unit token here."
class S1PayReturnForToken extends S1Effect {
  const S1PayReturnForToken(this.energy, this.token);
  final int energy;
  final String token;
  @override
  String describe() => 'may pay {$energy} and return a unit here to play a $token here';
}

/// "Banish your hand and trash."
class S1BanishHandAndTrash extends S1Effect {
  const S1BanishHandAndTrash();
  @override
  String describe() => 'banish your hand and trash';
}

/// Fallen Feline: "Name a spell." (CR 762), remembered for its passive.
class S1NameSpell extends S1Effect {
  const S1NameSpell();
  @override
  String describe() => 'name a spell';
}

/// Fiora: "Double my Might this combat."
class S1DoubleThisCombat extends S1Effect {
  const S1DoubleThisCombat();
  @override
  String describe() => 'double my Might this combat';
}

// Conditions.

abstract class S1Cond extends Cond {
  const S1Cond();
  String describe();
}

/// "If you've chosen enemy units and/or gear twice this turn with spells or unit abilities."
class S1ChoseEnemyTwice extends S1Cond {
  const S1ChoseEnemyTwice();
  @override
  String describe() => 'chose enemies twice this turn';
}

/// "One on one" (CR 740.2.b): the source and the enemy unit at its location are both alone.
class S1OneOnOne extends S1Cond {
  const S1OneOnOne();
  @override
  String describe() => 'one on one';
}

// Passives.

abstract class S1Passive extends Passive {
  const S1Passive();
  String describe();
}

/// Altar of Blood: a unit here that would die during combat may be saved for {A}{A}{A}.
class S1CombatSave extends S1Passive {
  const S1CombatSave(this.power);
  final int power;
  @override
  String describe() => 'units here dying in combat may pay ${'{A}' * power} to heal, exhaust and recall';
}

/// Bandle Tree: "You may hide an additional card here."
class S1ExtraHide extends S1Passive {
  const S1ExtraHide();
  @override
  String describe() => 'one more facedown card here';
}

/// Baron Nashor: "As you play me, add the Baron Pit battlefield token … If you do, I enter there."
class S1BaronPit extends S1Passive {
  const S1BaronPit();
  @override
  String describe() => 'adds the Baron Pit as I\'m played and enters there';
}

/// The Baron Pit: "Units can move here from anywhere."
class S1MoveHereFromAnywhere extends S1Passive {
  const S1MoveHereFromAnywhere();
  @override
  String describe() => 'units can move here from anywhere';
}

/// Endless Riches: "Skip your Draw Phase."
class S1SkipDraw extends S1Passive {
  const S1SkipDraw();
  @override
  String describe() => 'skip your Draw Phase';
}

/// Endless Riches: "You may play cards from your trash."
class S1PlayFromTrash extends S1Passive {
  const S1PlayFromTrash();
  @override
  String describe() => 'may play cards from your trash';
}

/// Endless Riches: cards going to your trash from anywhere but your Main Deck are banished.
class S1TrashIsBanish extends S1Passive {
  const S1TrashIsBanish();
  @override
  String describe() => 'cards bound for your trash (not from your deck) are banished';
}

/// Fallen Feline: "While I'm at a battlefield, opponents can't play spells with that name."
class S1NamedSpellBan extends S1Passive {
  const S1NamedSpellBan();
  @override
  String describe() => 'while at a battlefield, opponents can\'t play the named spell';
}

// Triggers.

enum S1Ev {
  /// "When a showdown begins here" (a unit; combat showdowns too, CR 316.8.a).
  showdownHere,

  /// A battlefield's "At the start of your Beginning Phase" (its controller's).
  bfStartOfTurn,

  /// "The first time … each turn" on a core event.
  firstEachTurn,

  /// "When I die in combat".
  dieInCombat,
}

/// A trigger of this slice: a core event ([on]) with an extra test, or its own event.
class S1When extends When {
  const S1When(this.ev, super.on);
  final S1Ev ev;
  String describe() => '${ev.name}(${on.name})';
}
