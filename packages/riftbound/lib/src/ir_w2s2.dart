part of 'ir.dart';

// Wave 2, slice 2 (parser/w2s2.dart reads text into these; game/w2s2.dart runs them). They
// extend the general grammar's abstract bases (ir_general.dart), so the core's switches route
// them there and game/general.dart hands them to game/w2s2.dart.

abstract class Ws2Effect extends GenEffect {
  const Ws2Effect();
}

abstract class Ws2Cond extends GenCond {
  const Ws2Cond();
}

abstract class Ws2Passive extends GenPassive {
  const Ws2Passive();
}

// ---------------------------------------------------------------------------------------------
// Effects
// ---------------------------------------------------------------------------------------------

/// "You win the game" (Gutter Palace; CR 474 is the usual way, this ends it at once).
class Ws2WinGame extends Ws2Effect {
  const Ws2WinGame();
  @override
  String describe() => 'win the game';
}

/// "Return your Chosen Champion from your trash to your Champion Zone if it is empty" (CR 108.3).
class Ws2ReturnChampion extends Ws2Effect {
  const Ws2ReturnChampion({this.may = false});

  /// "You may": asked only when it can be done.
  final bool may;
  @override
  String describe() => '${may ? 'you may ' : ''}return your Chosen Champion from your trash to the Champion Zone';
}

/// "It gains [Shield 2] this combat": a keyword for the combat in progress (or the next one at
/// the source's battlefield, if none is in progress).
class Ws2GiveKwCombat extends Ws2Effect {
  const Ws2GiveKwCombat(this.kw, this.n, this.target);
  final Kw kw;
  final int n;
  final Target target;
  @override
  String describe() => 'give ${describeTargetGen(target)} ${kw.name}${n > 1 ? ' $n' : ''} this combat';
}

/// "Give a friendly unit my keywords and +{M} equal to my Might this turn" (Kato the Arm).
class Ws2GiveMyKeywords extends Ws2Effect {
  const Ws2GiveMyKeywords(this.target);
  final Target target;
  @override
  List<Target> get targets => [target];
  @override
  String describe() => 'give ${describeTargetGen(target)} my keywords and +my Might this turn';
}

/// Hwei, Brooding Painter: "draw 1, then discard 1. Then, do the following based on the
/// discarded card's type: • Spell - Draw 1. • Gear - Ready up to 2 runes. • Unit - Give me +3
/// {M} this turn."
class Ws2Hwei extends Ws2Effect {
  const Ws2Hwei();
  @override
  String describe() => 'draw 1, discard 1; spell: draw 1 / gear: ready up to 2 runes / unit: +3 Might this turn';
}

/// "[Burn N]. When you burn a unit this way, do this: Give a friendly unit +{M} equal to the
/// burned card's Might this turn." (Forgotten Relic; the "do this" is a reflexive ability, CR
/// 388.4, whose choice is made as it happens.)
class Ws2BurnBoost extends Ws2Effect {
  const Ws2BurnBoost(this.n);
  final int n;
  @override
  String describe() => 'burn $n; for a unit burned: a friendly unit gets +its Might this turn';
}

/// "Move a different unit you control to the location of the unit you exhausted to pay for this
/// ability" (Forgotten Signpost).
class Ws2MoveToPaidLoc extends Ws2Effect {
  const Ws2MoveToPaidLoc(this.target);
  final Target target;
  @override
  List<Target> get targets => [target];
  @override
  String describe() => 'move ${describeTargetGen(target)} to the exhausted unit’s location';
}

/// "Play a unit from hand to a battlefield you control, reducing its cost by {N}" (Here to Help).
class Ws2PlayUnitReduced extends Ws2Effect {
  const Ws2PlayUnitReduced(this.n, {this.may = false});
  final int n;

  /// "You may": declining is offered only when there's a unit to play.
  final bool may;
  @override
  String describe() => '${may ? 'you may ' : ''}play a unit from hand to a battlefield you control for {$n} less';
}

/// "Play a ready Reflection unit token to your base. It becomes a copy of that unit. Give it
/// [Temporary]." (Mirror Image; CR 187.6, 479.1).
class Ws2Reflection extends Ws2Effect {
  const Ws2Reflection(this.of);
  final Target of;
  @override
  String describe() => 'play a ready Reflection to base as a copy of ${describeTargetGen(of)}, with temporary';
}

/// LeBlanc, Deceiver: "you may discard 1 and exhaust me to play a ready Reflection unit token
/// there. It becomes a copy of another unit there. Give it [Temporary]."
class Ws2Deceiver extends Ws2Effect {
  const Ws2Deceiver();
  @override
  String describe() => 'you may discard 1 and exhaust me: a ready Reflection there, a copy of another unit there, with temporary';
}

/// "Gain control of a spell. You may make new choices for it." (CR 750–755). The spell is chosen
/// as this is played, in target slot [slot] (a chain item id).
class Ws2StealSpell extends Ws2Effect {
  const Ws2StealSpell(this.slot);
  final int slot;
  @override
  String describe() => 'gain control of a spell; you may make new choices for it';
}

/// Party Favors: each other player chooses Cards (you and they each draw 1) or Runes (you and
/// they each channel 1 rune exhausted).
class Ws2PartyFavors extends Ws2Effect {
  const Ws2PartyFavors();
  @override
  String describe() => 'each other player chooses: both draw 1, or both channel 1 rune exhausted';
}

/// King's Edict: each other player, starting with the next, chooses a unit you don't control not
/// yet chosen; kill those units.
class Ws2KingsEdict extends Ws2Effect {
  const Ws2KingsEdict();
  @override
  String describe() => 'each other player chooses a unit you don’t control; kill them';
}

/// Ivern, Green Father: "you may exhaust me to replace that battlefield with a Brush battlefield
/// token" (CR 187.8).
class Ws2ReplaceWithBrush extends Ws2Effect {
  const Ws2ReplaceWithBrush();
  @override
  String describe() => 'you may exhaust me to replace that battlefield with a Brush';
}

/// The Brush token: "you may replace this with the battlefield it replaced".
class Ws2RestoreBf extends Ws2Effect {
  const Ws2RestoreBf();
  @override
  String describe() => 'replace this with the battlefield it replaced';
}

/// Ravenbloom Prefect: "you may banish me to banish it" (the gear just played).
class Ws2BanishMeToBanish extends Ws2Effect {
  const Ws2BanishMeToBanish();
  @override
  String describe() => 'you may banish me to banish it';
}

/// Jhin, Virtuoso: "you may banish it" (the spell just played, now in its trash). Then, "if
/// there are four spells banished with me, put each in its trash, channel 4 runes, and draw 1".
class Ws2Jhin extends Ws2Effect {
  const Ws2Jhin();
  @override
  String describe() => 'you may banish it with me; with four spells banished with me: return them, channel 4, draw 1';
}

/// "[Legion] - Kill it now instead." (Noxian Guillotine): instead of the delayed kill.
class Ws2LegionKillNow extends Ws2Effect {
  const Ws2LegionKillNow(this.target);
  final Target target;
  @override
  String describe() => 'legion: kill ${describeTargetGen(target)} now instead';
}

/// "Pay any amount of {A} to [Add] that much Energy" (Hextech Anomaly). An ability that adds
/// resources (CR 168, 337.2), so it extends [AddRes]; it adds nothing by itself.
class Ws2PowerToEnergy extends AddRes {
  const Ws2PowerToEnergy();
}

/// "[Add] … Spend this only to play spells / to play gear or use gear abilities": what it adds
/// waits in the Rune Pool for that use only (CR 166).
class Ws2RestrictedAdd extends AddRes {
  const Ws2RestrictedAdd({super.energy, super.anyPower, this.gear = false}) : super(spellsOnly: !gear);
  final bool gear;
}

// ---------------------------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------------------------

/// "If you control a facedown card [at a battlefield]" (CR 107.3: facedown cards are always at
/// a battlefield).
class Ws2ControlsFacedown extends Ws2Cond {
  const Ws2ControlsFacedown();
  @override
  String describe() => 'you control a facedown card';
}

/// "If you have exactly N cards in hand and exactly M units at battlefields".
class Ws2ExactHandUnits extends Ws2Cond {
  const Ws2ExactHandUnits(this.hand, this.units);
  final int hand, units;
  @override
  String describe() => 'hand = $hand and units at battlefields = $units';
}

/// "If your units have all of the following tags among them - Bird, Cat, Dog, and Poro".
class Ws2TagsAmong extends Ws2Cond {
  const Ws2TagsAmong(this.tags);
  final List<String> tags;
  @override
  String describe() => 'your units have ${tags.join('/')} among them';
}

/// "While you control this battlefield".
class Ws2ControlsThisBf extends Ws2Cond {
  const Ws2ControlsThisBf();
  @override
  String describe() => 'you control this battlefield';
}

/// All of [conds].
class Ws2All extends Ws2Cond {
  const Ws2All(this.conds);
  final List<Cond> conds;
  @override
  String describe() => conds.map(describeCondGen).join(' and ');
}

/// The gear that triggered this is the first non-token gear its controller played this turn.
class Ws2FirstGear extends Ws2Cond {
  const Ws2FirstGear();
  @override
  String describe() => 'first non-token gear this turn';
}

// ---------------------------------------------------------------------------------------------
// Passives
// ---------------------------------------------------------------------------------------------

/// Heimerdinger, Inventor: "I have all {E} abilities of all friendly legends, units, and gear."
class Ws2BorrowExhaustAbilities extends Ws2Passive {
  const Ws2BorrowExhaustAbilities();
  @override
  String describe() => 'I have the {E} abilities of friendly legends, units and gear';
}

/// Kayn, Unleashed: "If I have moved twice this turn, I don't take damage."
class Ws2NoDamageMovedTwice extends Ws2Passive {
  const Ws2NoDamageMovedTwice();
  @override
  String describe() => 'no damage once I’ve moved twice this turn';
}

/// LeBlanc, Everywhere At Once: "Your [Temporary] effects at my battlefield don't trigger."
class Ws2NoTemporaryHere extends Ws2Passive {
  const Ws2NoTemporaryHere();
  @override
  String describe() => 'your temporary effects at my battlefield don’t trigger';
}

/// Mageseeker Investigator: opponents pay {A} for each unit beyond the first they move to my
/// battlefield at the same time.
class Ws2MoveTax extends Ws2Passive {
  const Ws2MoveTax();
  @override
  String describe() => 'opponents pay {A} per extra unit moved here together';
}

/// Otterpus: a point from conquering or holding in a player's first or second turn becomes a
/// draw.
class Ws2EarlyScoreDraws extends Ws2Passive {
  const Ws2EarlyScoreDraws();
  @override
  String describe() => 'early score points become draws';
}

/// Ivern, Friend to All: "As you play me, choose Bird, Cat, Dog, or Poro. I gain that tag."
class Ws2ChooseTag extends Ws2Passive {
  const Ws2ChooseTag(this.tags);
  final List<String> tags;
  @override
  String describe() => 'as played: gain one of ${tags.join('/')}';
}

// ---------------------------------------------------------------------------------------------
// Costs
// ---------------------------------------------------------------------------------------------

/// "Exhaust a unit you control" whose location a later instruction uses (Forgotten Signpost);
/// it can't be the unit the ability chose.
class Ws2ExhaustUnitCost extends GenCostPart {
  const Ws2ExhaustUnitCost();
  @override
  String describe() => 'exhaust a unit you control';
}
