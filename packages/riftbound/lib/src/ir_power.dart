part of 'ir.dart';

// Empower (CR 442–443, 827–828), XP (CR 728–733), Hunt (CR 823), Level (CR 824), buffs
// (CR 427, 701–705) and Flow (CR 829): the parts of the IR for them. Shared code reaches these
// through the sealed bases below ([PowerEffect], [PowerCond], [PowerPassive], [PowerAmount]) and
// the optional fields [Gate] (on abilities), [CostPart] (on costs) and [PowerFilter] (on filters).

// ---------------------------------------------------------------------------------------------
// Gates: dependent keywords and "while" conditions on an ability
// ---------------------------------------------------------------------------------------------

/// When an ability of a card is active.
sealed class Gate {
  const Gate();
}

/// "[Empowered][>] …" (CR 828.1.b.1): while the card is Empowered ([times]: "while I'm
/// [Empowered] three times").
class EmpoweredGate extends Gate {
  const EmpoweredGate([this.times = 1]);
  final int times;
}

/// "[Level N][>] …" (CR 824.1.b.1): while the card's controller has N or more XP.
class LevelGate extends Gate {
  const LevelGate(this.n);
  final int n;
}

/// "While I'm buffed, …".
class BuffedGate extends Gate {
  const BuffedGate();
}

/// "If you've gained XP this turn, …" (a passive's condition).
class XpGainedGate extends Gate {
  const XpGainedGate();
}

String describeGate(Gate g) => switch (g) {
      EmpoweredGate(:final times) => times == 0 ? 'not empowered' : (times == 1 ? 'empowered' : 'empowered ×$times'),
      LevelGate(:final n) => 'level $n',
      BuffedGate() => 'buffed',
      XpGainedGate() => 'gained XP this turn',
    };

// ---------------------------------------------------------------------------------------------
// Costs beyond runes (CR 202–205): spending XP or buffs, disempowering, killing, discarding
// ---------------------------------------------------------------------------------------------

sealed class CostPart {
  const CostPart();
}

/// "Spend N XP" (CR 730.2).
class SpendXp extends CostPart {
  const SpendXp(this.n);
  final int n;
}

/// "Spend my buff" (CR 702.2.b): a buff from the source itself.
class SpendMyBuff extends CostPart {
  const SpendMyBuff();
}

/// "Disempower me / this" (CR 443): the source must be Empowered.
class DisempowerMe extends CostPart {
  const DisempowerMe();
}

/// "Kill a friendly unit" (Escaped Grayback's Empower cost).
class KillFriendly extends CostPart {
  const KillFriendly();
}

/// "Discard 1" / "Discard a spell".
class DiscardCost extends CostPart {
  const DiscardCost(this.n, {this.spell = false});
  final int n;
  final bool spell;
}

/// "This ability costs {N} less if you control M or fewer runes" / "… {N} less for each rune you
/// control": Energy off an activated ability's cost (CR 827.1.c.3).
class EnergyLess extends CostPart {
  const EnergyLess(this.n, {this.ifRunesAtMost, this.perRune = false});
  final int n;
  final int? ifRunesAtMost;
  final bool perRune;
}

String describeCostPart(CostPart c) => switch (c) {
      SpendXp(:final n) => 'spend $n XP',
      SpendMyBuff() => 'spend my buff',
      DisempowerMe() => 'disempower me',
      KillFriendly() => 'kill a friendly unit',
      DiscardCost(:final n, :final spell) => spell ? 'discard a spell' : 'discard $n',
      EnergyLess(:final n, :final ifRunesAtMost, :final perRune) => perRune ? '{$n} less per rune' : '{$n} less if ≤$ifRunesAtMost runes',
      RecycleTrash(:final n, :final unit) => 'recycle $n${unit ? ' unit' : ''} from trash',
    };

// ---------------------------------------------------------------------------------------------
// Filters
// ---------------------------------------------------------------------------------------------

/// More conditions on a [Filter].
class PowerFilter {
  const PowerFilter({this.empowered, this.anyType = false, this.legends = false, this.lessMightThanSource = false, this.lessMightThanChosen, this.movedFromOrTo = false, this.atBattlefieldOnly = false, this.withChosen, this.inShowdown = false, this.mightMaxUnlessPaid});
  final bool? empowered;

  /// "Something": a unit or a gear.
  final bool anyType;

  /// Legends too ("a legend, unit, or gear", "something you control").
  final bool legends;

  /// "With less Might than me".
  final bool lessMightThanSource;

  /// "With less Might than it" (the unit chosen in this slot).
  final int? lessMightThanChosen;

  /// "At a battlefield I moved to or from" (a move trigger).
  final bool movedFromOrTo;

  /// "At my battlefield": only while the source is at a battlefield.
  final bool atBattlefieldOnly;

  /// At the same location as the unit chosen in this slot ("they", Shadow Dash).
  final int? withChosen;

  /// "In a showdown": at the battlefield of the showdown going on.
  final bool inShowdown;

  /// "With N {M} or less. If you paid the additional cost, choose any … instead" (Conscription).
  final int? mightMaxUnlessPaid;

  String describe() => [
        if (empowered == true) 'empowered',
        if (empowered == false) 'not empowered',
        if (anyType) '(unit or gear)',
        if (lessMightThanSource) 'M<mine',
        if (lessMightThanChosen != null) 'M<#$lessMightThanChosen',
        if (movedFromOrTo) 'where I moved',
        if (legends) '(or legend)',
        if (atBattlefieldOnly) 'at my battlefield',
        if (withChosen != null) 'with #$withChosen',
        if (inShowdown) 'in a showdown',
        if (mightMaxUnlessPaid != null) 'M<=$mightMaxUnlessPaid unless paid',
      ].join(' ');
}

// ---------------------------------------------------------------------------------------------
// Amounts
// ---------------------------------------------------------------------------------------------

sealed class PowerAmount extends Amount {
  const PowerAmount();
}

/// "For each friendly unit".
class PerFriendlyUnit extends PowerAmount {
  const PerFriendlyUnit();
}

/// "Equal to its Might" (the unit chosen in [slot]).
class ChosenMight extends PowerAmount {
  const ChosenMight(this.slot);
  final int slot;
}

String describeAmount(Amount a) => switch (a) {
      N(:final n) => '$n',
      MyMight() => 'my Might',
      PerFriendlyUnit() => '1 per friendly unit',
      ChosenMight(:final slot) => 'Might of #$slot',
    };

// ---------------------------------------------------------------------------------------------
// Effects
// ---------------------------------------------------------------------------------------------

sealed class PowerEffect extends Effect {
  const PowerEffect();
}

/// The Empower keyword's effect (CR 827.1.c.1): "Empower this. Play only if not Empowered".
class EmpowerMe extends PowerEffect {
  const EmpowerMe();
}

/// "Empower …" / "Disempower …" (CR 442–443) as an instruction. [untilEndOfTurn]: undo it at the
/// end of the turn ("Disempower it at end of turn").
class Empower extends PowerEffect {
  const Empower(this.target, {this.off = false, this.untilEndOfTurn = false});
  final Target target;

  /// Disempower.
  final bool off;
  final bool untilEndOfTurn;
}

/// "Gain N XP" (CR 730.1).
class GainXp extends PowerEffect {
  const GainXp(this.amount);
  final Amount amount;
}

/// "Buff up to N [other] friendly units" — chosen as it resolves.
class BuffUpTo extends PowerEffect {
  const BuffUpTo(this.n, this.filter);
  final int n;
  final Filter filter;
}

/// A cost within instructions (CR 204.3): "[you may] pay {1} / spend 3 XP / spend a buff / kill
/// a gear to [effects]", and "… . If you do, [effects]".
class PayToDo extends PowerEffect {
  const PayToDo(this.pay, this.effects, {this.optional = true});
  final PayKind pay;
  final List<Effect> effects;
  final bool optional;
}

/// What a [PayToDo] costs.
sealed class PayKind {
  const PayKind();
}

class PayRunes extends PayKind {
  const PayRunes(this.energy, this.power, {this.exhaustMe = false});
  final int energy;
  final List<Domain?> power;

  /// "… and exhaust this".
  final bool exhaustMe;
}

/// "You may kill a gear. If you do, …": doing [effect] is the cost (CR 205); it's paid if it did
/// something.
class PayEffect extends PayKind {
  const PayEffect(this.effect);
  final Effect effect;
}

class PayXp extends PayKind {
  const PayXp(this.n);
  final int n;
}

/// "Spend a buff": from a friendly unit the player chooses.
class PayBuff extends PayKind {
  const PayBuff();
}

/// "Kill a gear" (any gear; the player chooses).
class PayKillGear extends PayKind {
  const PayKillGear();
}

/// "Disempower something you control".
class PayDisempower extends PayKind {
  const PayDisempower();
}

String describePay(PayKind k) => switch (k) {
      PayRunes(:final energy, :final power) => 'pay ${energy > 0 ? '{$energy}' : ''}${power.map((d) => '{${d?.letter ?? 'A'}}').join()}',
      PayXp(:final n) => 'spend $n XP',
      PayBuff() => 'spend a buff',
      PayKillGear() => 'kill a gear',
      PayDisempower() => 'disempower something',
      PayEffect() => 'do it',
    };

/// "[effects]. If [cond], [instead] instead." — one or the other, decided as it resolves.
class InsteadIf extends PowerEffect {
  const InsteadIf(this.cond, this.normal, this.instead);
  final Cond cond;
  final List<Effect> normal, instead;
}

/// "Spend any number of buffs. For each buff spent, [effects]".
class SpendBuffsEach extends PowerEffect {
  const SpendBuffsEach(this.effects);
  final List<Effect> effects;
}

/// "For each friendly unit, you may spend its buff to ready it".
class SpendEachBuffToReady extends PowerEffect {
  const SpendEachBuffToReady();
}

/// "Spend my buff" as an instruction.
class SpendBuffOf extends PowerEffect {
  const SpendBuffOf(this.target);
  final Target target;
}

/// "Banish …" (CR 428).
class Banish extends PowerEffect {
  const Banish(this.target);
  final Target target;
}

/// "Banish a unit from your trash" (CR 428).
class BanishFromTrash extends PowerEffect {
  const BanishFromTrash({this.unitsOnly = true});
  final bool unitsOnly;
}

/// "Burn N" (CR 441), by the controller or ([opponent]) the chosen opponent.
class Burn extends PowerEffect {
  const Burn(this.n, {this.opponent = false});
  final int n;
  final bool opponent;
}

/// "Increase my Might to its Might this turn" (the unit chosen in [slot]).
class MightUpTo extends PowerEffect {
  const MightUpTo(this.slot);
  final int slot;
}

/// "Look at the top N cards of your Main Deck. You may banish a unit or gear from among them and
/// play it, reducing its Energy cost by {E}. Recycle the rest. Then you may do this: Empower it."
class LookBanishPlay extends PowerEffect {
  const LookBanishPlay(this.n, {required this.energyLess, this.empowerAfter = false});
  final int n;
  final int energyLess;
  final bool empowerAfter;
}

/// "Choose a unit": a target for the sentences after it ("it").
class PickIt extends PowerEffect {
  const PickIt(this.target);
  final Target target;
}

/// "Choose a player. They gain control of this and recall it." (Glowstone).
class GiftMe extends PowerEffect {
  const GiftMe();
}

/// "Its base Might becomes N this turn" (the chosen unit): +/- to reach N from its printed Might.
class BaseMightBecomes extends PowerEffect {
  const BaseMightBecomes(this.n, this.target);
  final int n;
  final Target target;
}

/// "When … this turn, [effects]" / "At end of turn, [effects]": a delayed ability (CR 390).
class Delayed extends PowerEffect {
  const Delayed(this.kind, {this.target, this.n = 0});

  /// buffPlayedThisTurn, xpWhenItWins, disempowerAtEnd, empowerAtEnd, nextUnitReadyBuff.
  final String kind;
  final Target? target;
  final int n;
}

/// "Give a spell in your trash [Flow] equal to its cost this turn" (Kennen).
class GrantFlow extends PowerEffect {
  const GrantFlow();
}

/// "Play a 0 {M} Shadow Clone unit token" and other tokens the core list lacks.
class PowerToken extends PowerEffect {
  const PowerToken(this.token, this.count, {this.might = 0, this.toBase = true});
  final String token;
  final int count;
  final int might;
  final bool toBase;
}

/// "Look at the top N cards of your Main Deck. You may choose a [filter] card from among them and
/// draw it. [Recycle / put] the rest [into your trash]."
class LookDraw extends PowerEffect {
  const LookDraw(this.n, {this.unitsOnly = false, this.restToTrash = false, this.reveal = false, this.thenIfTags = const [], this.then = const []});
  final int n;
  final bool unitsOnly, restToTrash, reveal;

  /// "Then if you revealed a Bird, Cat, Dog, or Poro, do this: [then]".
  final List<String> thenIfTags;
  final List<Effect> then;
}

/// "Choose a unit in [their / your] trash [with cost limits] and play it [to your base],
/// ignoring its cost."
class PlayFromTrash extends PowerEffect {
  const PlayFromTrash({this.opponentsTrash = false, this.maxEnergy, this.maxPower, this.optional = true});
  final bool opponentsTrash;
  final int? maxEnergy, maxPower;
  final bool optional;
}

/// "Choose an opponent. They reveal their hand." [then]: optional follow-ups handled by kind.
class RevealHand extends PowerEffect {
  const RevealHand({this.payXpDiscard = 0, this.xp = 0});

  /// "You may pay N XP to choose a card from their hand. If you do, they discard that card and
  /// draw 1."
  final int payXpDiscard;

  /// "Gain N XP" afterwards.
  final int xp;
}

/// "Each player must kill one of their units" (Safety Inspector, without its extra cost).
class EachKillsOne extends PowerEffect {
  const EachKillsOne({this.notYouIfPaid = false});

  /// "If you paid my additional cost, you don't kill a unit this way."
  final bool notYouIfPaid;
}

/// "Move [target]" to a destination chosen as it resolves (any location it may go to).
class MoveAny extends PowerEffect {
  const MoveAny(this.target, {this.toBattlefield = false, this.whereYouHaveUnits = false});
  final Target target;

  /// "…, then move it to a battlefield".
  final bool toBattlefield;

  /// "to a battlefield where you have units".
  final bool whereYouHaveUnits;
}

/// "Move all enemy units at that battlefield with less Might than the chosen unit to their base"
/// (Stare Down: [slot] is the friendly unit chosen).
class StareDown extends PowerEffect {
  const StareDown(this.slot);
  final int slot;
}

/// "It deals damage equal to its Might split among enemy units at battlefields. Then for each
/// unit this kills, gain 1 XP." (Alpha Strike).
class SplitMightDamage extends PowerEffect {
  const SplitMightDamage(this.slot, {this.xpPerKill = 0});
  final int slot;
  final int xpPerKill;
}

/// "Draw 1 or buff me" — the controller picks one.
class OneOf extends PowerEffect {
  const OneOf(this.options);
  final List<List<Effect>> options;
}

/// "It can't be chosen by enemy spells and abilities this turn".
class Untargetable extends PowerEffect {
  const Untargetable(this.target);
  final Target target;
}

/// "Give your units here [Ganking] this turn" etc.: a keyword to every unit matching.
class GiveKwAll extends PowerEffect {
  const GiveKwAll(this.kw, this.n, this.filter);
  final Kw kw;
  final int n;
  final Filter filter;
}

/// "Ready N gear" (choose up to N of yours).
class ReadyGear extends PowerEffect {
  const ReadyGear(this.n);
  final int n;
}

/// "They each get +N {M} this turn" (the units counted by an [If]).
class GiveMightAll extends PowerEffect {
  const GiveMightAll(this.n, this.filter);
  final int n;
  final Filter filter;
}

// ---------------------------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------------------------

sealed class PowerCond extends Cond {
  const PowerCond();
}

/// "If I'm / this is / it's [Empowered]" ([slot] -1: the source; else the chosen unit).
class IsEmpowered extends PowerCond {
  const IsEmpowered({this.slot = -1});
  final int slot;
}

/// "If it's your turn".
class YourTurn extends PowerCond {
  const YourTurn();
}

/// "If you control something that's [Empowered]".
class ControlEmpowered extends PowerCond {
  const ControlEmpowered();
}

/// "[Level N]" on a spell's line.
class HasXp extends PowerCond {
  const HasXp(this.n);
  final int n;
}

/// "If you control N or more runes" / "4 or fewer runes".
class RunesCount extends PowerCond {
  const RunesCount(this.n, {this.atLeast = true});
  final int n;
  final bool atLeast;
}

/// "If you control a Poro".
class ControlTag extends PowerCond {
  const ControlTag(this.tag);
  final String tag;
}

/// "If an opponent's score is within N points of the Victory Score".
class OpponentNearVictory extends PowerCond {
  const OpponentNearVictory(this.n);
  final int n;
}

/// "If I am at a battlefield".
class AtBattlefield extends PowerCond {
  const AtBattlefield();
}

/// "If you have exactly N units there" (the battlefield of the unit chosen in [slot]).
class ExactlyUnitsWithChosen extends PowerCond {
  const ExactlyUnitsWithChosen(this.n, this.slot);
  final int n;
  final int slot;
}

/// "If it has N {M} or less" (the unit in [slot]).
class ChosenMightAtMost extends PowerCond {
  const ChosenMightAtMost(this.n, this.slot);
  final int n;
  final int slot;
}

String describePowerCond(PowerCond c) => switch (c) {
      IsEmpowered(:final slot) => slot < 0 ? 'I\'m empowered' : '#$slot empowered',
      ControlEmpowered() => 'you control something empowered',
      YourTurn() => 'it\'s your turn',
      HasXp(:final n) => '$n+ XP',
      RunesCount(:final n, :final atLeast) => '${atLeast ? '≥' : '≤'}$n runes',
      ControlTag(:final tag) => 'you control a $tag',
      OpponentNearVictory(:final n) => 'an opponent within $n of victory',
      EnemyAloneHere() => 'an enemy unit alone here',
      AtBattlefield() => 'I\'m at a battlefield',
      ExactlyUnitsWithChosen(:final n) => 'exactly $n units there',
      ChosenMightAtMost(:final n, :final slot) => '#$slot has ≤$n Might',
    };

// ---------------------------------------------------------------------------------------------
// Passives
// ---------------------------------------------------------------------------------------------

sealed class PowerPassive extends Passive {
  const PowerPassive();
}

/// "I have +N {M}" (gated by a dependent keyword) / "I have an additional +1 {M}".
class SelfMight extends PowerPassive {
  const SelfMight(this.n, {this.perEmpowered = false, this.perBuffedFriendlyHere = false});
  final int n;

  /// "+2 {M} for each time I'm [Empowered]".
  final bool perEmpowered;

  /// "+1 {M} for each buffed friendly unit at my battlefield".
  final bool perBuffedFriendlyHere;
}

/// "I have [Keyword N]" (gated).
class SelfKw extends PowerPassive {
  const SelfKw(this.kw, this.n);
  final Kw kw;
  final int n;
}

/// A [Filter]ed anthem whose filter needs the power extensions ("Your units that are [Empowered]
/// have +2 {M}", "Other buffed friendly units at my battlefield have +2 {M}", "Your units have +1
/// {M}").
class PowerAnthem extends PowerPassive {
  const PowerAnthem(this.n, this.filter, {this.kw});
  final int n;
  final Filter filter;

  /// A keyword instead of Might ("Friendly buffed units have [Deflect] if they didn't already").
  final Kw? kw;
}

/// "Your units enter ready" (a legend's).
class UnitsEnterReady extends PowerPassive {
  const UnitsEnterReady();
}

/// "I cost {N}{X} less" (gated by Level; [instead] replaces lower-Level ones) — Energy and Power.
class CostLessPower extends PowerPassive {
  const CostLessPower(this.energy, this.power);
  final int energy;
  final List<Domain?> power;
}

/// "Your spells cost {1}{A} less, to a minimum of {1}" / "Opponents' spells cost {1} more".
class SpellCostMod extends PowerPassive {
  const SpellCostMod(this.energy, this.power, {required this.yours, this.minEnergy = 0});
  final int energy;

  /// Any-domain Power symbols added (positive) or removed (negative).
  final int power;
  final bool yours;
  final int minEnergy;
}

/// "Spells with [Flow] you play from your trash cost {2} less, to a minimum of {1}".
class FlowCostLess extends PowerPassive {
  const FlowCostLess(this.n, {this.minEnergy = 1});
  final int n;
  final int minEnergy;
}

/// "[Flow] {cost}" (CR 829): may be played from the trash for this cost, then banished.
class Flow extends PowerPassive {
  const Flow(this.energy, this.power);
  final int energy;
  final List<Domain?> power;
}

/// "I can be [Empowered] up to N times" (CR 442.1.c.1).
class EmpowerTimes extends PowerPassive {
  const EmpowerTimes(this.n);
  final int n;
}

/// "I can have any number of buffs" (CR 427.1.b.2).
class ManyBuffs extends PowerPassive {
  const ManyBuffs();
}

/// "When a buffed unit you control would die, you may pay {A} and exhaust me to spend its buff and
/// recall it exhausted instead." (Sett, The Boss): a replacement of dying (CR 370).
class SaveBuffed extends PowerPassive {
  const SaveBuffed();
}

/// "Your conquer effects for conquering here trigger an additional time" (Red Brambleback).
class ConquerTwiceHere extends PowerPassive {
  const ConquerTwiceHere();
}

/// "If a spell or ability that chooses me would stun me, give me -{M}, or return me to hand, give me
/// +N {M} instead" (Gangplank, Naval; a replacement effect, CR 370).
class ChosenHarmToMight extends PowerPassive {
  const ChosenHarmToMight(this.n);
  final int n;
}

/// "Your spells and abilities can't be countered. If a spell or ability you control would give -{M}
/// to a unit it chooses, it gives an additional -1 {M}." (Mel, Newly Awakened).
class MelAwakened extends PowerPassive {
  const MelAwakened();
}

/// "Can't be dealt damage unless I'm in combat".
class NoDamageOutsideCombat extends PowerPassive {
  const NoDamageOutsideCombat();
}

/// "Units here have "{E}: Gain 1 XP."" (a battlefield granting an ability).
class GrantXpAbility extends PowerPassive {
  const GrantXpAbility();
}

/// "[Empower] costs of your units here cost {1} or {A} less" (Risen Altar).
class EmpowerCostLessHere extends PowerPassive {
  const EmpowerCostLessHere();
}

/// "I can be played to an occupied battlefield if an enemy unit is alone there"; with [friendly],
/// "Friendly units can be …" (Arachnoid Horror).
class PlayToLoneEnemy extends PowerPassive {
  const PlayToLoneEnemy({this.friendly = false});
  final bool friendly;
}

/// "This costs {N} less" (a spell's, gated by Level or a condition; the largest applies).
class SpellCostLess extends PowerPassive {
  const SpellCostLess(this.n, {this.ifControlEmpowered = false});
  final int n;
  final bool ifControlEmpowered;
}

String describePowerPassive(PowerPassive p) => switch (p) {
      SelfMight(:final n, :final perEmpowered, :final perBuffedFriendlyHere) => '+$n Might${perEmpowered ? ' per empower' : ''}${perBuffedFriendlyHere ? ' per buffed friendly here' : ''}',
      SelfKw(:final kw, :final n) => 'has ${kw.name}${n > 1 ? ' $n' : ''}',
      PowerAnthem(:final n, :final filter, :final kw) => '${filter.describe()} ${kw == null ? '+$n Might' : 'have ${kw.name}'}',
      UnitsEnterReady() => 'your units enter ready',
      CostLessPower(:final energy, :final power) => 'costs {$energy}${power.map((d) => '{${d?.letter ?? 'A'}}').join()} less',
      SpellCostMod(:final energy, :final power, :final yours) => '${yours ? 'your' : 'opponents\''} spells cost ${energy >= 0 ? '+' : ''}$energy${power != 0 ? ' and ${power > 0 ? '+' : ''}$power{A}' : ''}',
      FlowCostLess(:final n) => 'flow from trash costs {$n} less',
      Flow(:final energy, :final power) => 'flow {$energy}${power.map((d) => '{${d?.letter ?? 'A'}}').join()}',
      EmpowerTimes(:final n) => 'empowered up to $n times',
      ManyBuffs() => 'any number of buffs',
      NoDamageOutsideCombat() => 'no damage outside combat',
      PlayToLoneEnemy(:final friendly) => '${friendly ? 'friendly units' : 'I'} may be played where an enemy unit is alone',
      GrantXpAbility() => 'units here: {E}: gain 1 XP',
      EmpowerCostLessHere() => 'empower costs here {1} or {A} less',
      SpellCostLess(:final n) => 'this costs {$n} less',
      ConquerTwiceHere() => 'conquer effects here trigger twice',
      SaveBuffed() => 'may save a buffed unit from dying',
      ChosenHarmToMight(:final n) => 'stun/-Might/bounce choosing me gives +$n Might instead',
      MelAwakened() => 'can\'t be countered; -Might you give is 1 more',
    };
