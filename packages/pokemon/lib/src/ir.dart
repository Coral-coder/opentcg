/// What card text means to the engine: effects of attacks, Abilities, Trainers and Tools, as
/// data the engine runs (lib/src/parser turns text into this).
library;

import 'cards/card.dart';

/// Special Conditions (rulebook: "Special Conditions").
enum Cond { asleep, burned, confused, paralyzed, poisoned }

/// Which Pokémon an effect touches.
enum Who {
  /// The Pokémon using the attack or Ability, or holding the Tool.
  self,

  /// Your opponent's Active Pokémon (the Defending Pokémon).
  oppActive,

  /// Your Active Pokémon (Trainers).
  ownActive,

  /// You choose 1 of your Pokémon / Benched Pokémon.
  chooseOwn,
  chooseOwnBench,

  /// You choose 1 of your opponent's Pokémon / Benched Pokémon.
  chooseOpp,
  chooseOppBench,

  /// Each of them.
  eachOwn,
  eachOwnBench,
  eachOpp,
  eachOppBench,
}

/// Quantities ("for each Energy attached to this Pokémon").
sealed class Count {
  const Count();
}

/// Heads from the last flips.
class Heads extends Count {
  const Heads();
}

class EnergyOn extends Count {
  const EnergyOn(this.who, [this.type]);
  final Who who;
  final PType? type;
}

class DamageCountersOn extends Count {
  const DamageCountersOn(this.who);
  final Who who;
}

class BenchedCount extends Count {
  const BenchedCount({required this.own, required this.opp});
  final bool own, opp;
}

class HandCount extends Count {
  const HandCount({required this.own});
  final bool own;
}

class PrizesTaken extends Count {
  const PrizesTaken({required this.own});
  final bool own;
}

class DiscardCount extends Count {
  const DiscardCount(this.filter);
  final CardFilter filter;
}

/// What kind of cards a search or count accepts.
class CardFilter {
  const CardFilter({this.pokemon = false, this.basicPokemon = false, this.evolution = false, this.basicEnergy = false, this.energy = false, this.trainer, this.anyTrainer = false, this.type, this.any = false});
  final bool pokemon, basicPokemon, evolution, basicEnergy, energy, anyTrainer, any;
  final TrainerKind? trainer;
  final PType? type;

  bool matches(PCard c) {
    if (any) return true;
    if (type != null) {
      if (c.isPokemon && !c.types.contains(type)) return false;
      if (c.isEnergy && c.energyType != type) return false;
    }
    if (basicPokemon) return c.isBasicPokemon;
    if (evolution) return c.isPokemon && c.stage != Stage.basic;
    if (pokemon) return c.isPokemon;
    if (basicEnergy) return c.basicEnergy;
    if (energy) return c.isEnergy;
    if (trainer != null) return c.trainer == trainer;
    if (anyTrainer) return c.isTrainer;
    return false;
  }

  @override
  String toString() => [
        if (type != null) type!.label,
        if (basicPokemon) 'Basic Pokémon',
        if (evolution) 'Evolution Pokémon',
        if (pokemon) 'Pokémon',
        if (basicEnergy) 'Basic Energy',
        if (energy) 'Energy',
        if (trainer != null) trainer!.name,
        if (anyTrainer) 'Trainer',
        if (any) 'card',
      ].join(' ');
}

/// Conditions for "If …, …".
enum Check { oppActiveIsEx, oppActiveDamaged, selfDamaged, oppActiveHasCondition, selfHasNoDamage, oppActivePoisoned, oppActiveIsEvolution }

sealed class Eff {
  const Eff();
}

class Seq extends Eff {
  const Seq(this.steps);
  final List<Eff> steps;
}

/// Flip [n] coins (n = 0: until tails). Later effects read the result.
class Flip extends Eff {
  const Flip(this.n);
  final int n;
}

class IfHeads extends Eff {
  const IfHeads(this.then);
  final Eff then;
}

class IfTails extends Eff {
  const IfTails(this.then);
  final Eff then;
}

/// Repeats [each] once per heads ("For each heads, discard an Energy …").
class ForEachHeads extends Eff {
  const ForEachHeads(this.each);
  final Eff each;
}

class IfCheck extends Eff {
  const IfCheck(this.check, this.then);
  final Check check;
  final Eff then;
}

/// "This attack does nothing."
class NoDamage extends Eff {
  const NoDamage();
}

/// The attack's damage becomes [n] × [per] ("does 30 damage for each heads").
class DamagePer extends Eff {
  const DamagePer(this.n, this.per);
  final int n;
  final Count per;
}

/// [n] more (or, negative, less) damage, times [per] when given.
class MoreDamage extends Eff {
  const MoreDamage(this.n, [this.per]);
  final int n;
  final Count? per;
}

/// Damage to other Pokémon than the Defending one (Bench, itself, chosen ones). Benched
/// Pokémon don't apply Weakness and Resistance.
class DamageTo extends Eff {
  const DamageTo(this.n, this.who);
  final int n;
  final Who who;
}

/// Damage counters (not damage: no Weakness, Resistance or effects).
class Counters extends Eff {
  const Counters(this.n, this.who);
  final int n;
  final Who who;
}

class Afflict extends Eff {
  const Afflict(this.who, this.conds);
  final Who who;
  final List<Cond> conds;
}

class Draw extends Eff {
  const Draw(this.n, {this.upTo = false, this.untilHandSize = false, this.may = false});
  final int n;
  final bool upTo, untilHandSize, may;
}

class Heal extends Eff {
  const Heal(this.n, this.who, {this.all = false});
  final int n;
  final Who who;
  final bool all;
}

/// Discards [n] Energy (−1: all) from a Pokémon, optionally of [type].
class DiscardEnergy extends Eff {
  const DiscardEnergy(this.n, this.who, [this.type]);
  final int n;
  final Who who;
  final PType? type;
}

enum SwitchKind {
  /// This Pokémon with 1 of your Benched Pokémon.
  self,

  /// Your Active Pokémon with 1 of your Benched Pokémon (Trainers).
  ownActive,

  /// Your opponent's Active to the Bench; they choose the new one.
  oppOut,

  /// 1 of your opponent's Benched Pokémon into the Active Spot (you choose).
  gust,

  /// "You may switch this Pokémon with 1 of your Benched Pokémon."
  selfMay,
}

class Switch extends Eff {
  const Switch(this.kind);
  final SwitchKind kind;
}

enum Dest { hand, bench, attachSelf, attachBench, attachAny }

/// Search your deck for (up to) [n] cards matching [filter] and put them somewhere; shuffle.
class Search extends Eff {
  const Search(this.n, this.filter, this.dest, {this.upTo = true});
  final int n;
  final CardFilter filter;
  final Dest dest;
  final bool upTo;
}

/// Attach (up to) [n] Basic Energy (of [type]) from your discard pile.
class AttachFromDiscard extends Eff {
  const AttachFromDiscard(this.n, this.type, this.dest, {this.upTo = false});
  final int n;
  final PType? type;
  final Dest dest;
  final bool upTo;
}

class MoveEnergy extends Eff {
  const MoveEnergy({required this.fromSelf, required this.basicOnly});
  final bool fromSelf, basicOnly;
}

class MillOpponent extends Eff {
  const MillOpponent(this.n);
  final int n;
}

/// "Discard the top [n] cards of your deck."
class MillSelf extends Eff {
  const MillSelf(this.n);
  final int n;
}

/// Put (up to) [n] cards matching [filter] from your discard pile into your hand.
class FromDiscard extends Eff {
  const FromDiscard(this.n, this.filter, {this.upTo = false});
  final int n;
  final CardFilter filter;
  final bool upTo;
}

class DiscardRandomFromOppHand extends Eff {
  const DiscardRandomFromOppHand(this.n);
  final int n;
}

class RevealOppHand extends Eff {
  const RevealOppHand();
}

/// Shuffle your hand into your deck (each player: [each]); then draw [draw] (−1: none).
class ShuffleHandIn extends Eff {
  const ShuffleHandIn({this.each = false, this.draw = -1});
  final bool each;
  final int draw;
}

class DiscardHand extends Eff {
  const DiscardHand();
}

class DiscardOppTools extends Eff {
  const DiscardOppTools();
}

/// Lasting effects with a duration.
enum Lasting {
  /// "During your next turn, this Pokémon can't attack."
  selfCantAttack,

  /// "During your opponent's next turn, the Defending Pokémon can't retreat."
  defenderCantRetreat,

  /// "… this Pokémon takes [n] less damage from attacks (after Weakness and Resistance)."
  selfTakesLess,

  /// "… prevent all damage from and effects of attacks done to this Pokémon."
  selfPreventAll,

  /// "… attacks used by the Defending Pokémon do [n] less damage (before W/R)."
  defenderDoesLess,
}

class Lingering extends Eff {
  const Lingering(this.kind, [this.n = 0]);
  final Lasting kind;
  final int n;
}

/// Flags on the attack's damage.
class DamageRules extends Eff {
  const DamageRules({this.noWeakness = false, this.noResistance = false, this.ignoreDefenderEffects = false});
  final bool noWeakness, noResistance, ignoreDefenderEffects;
}

/// Ends the turn (an Ability that says so).
class EndTurn extends Eff {
  const EndTurn();
}

// ---------------------------------------------------------------------------------------------
// Abilities, Tools, Energy
// ---------------------------------------------------------------------------------------------

sealed class AbilityIR {
  const AbilityIR();
}

/// "Once during your turn, you may …" (activated; once per Pokémon per turn).
class OncePerTurn extends AbilityIR {
  const OncePerTurn(this.effect, {this.activeOnly = false});
  final Eff effect;
  final bool activeOnly;
}

/// "This Pokémon takes [n] less damage from attacks (after applying Weakness and Resistance)."
class TakesLess extends AbilityIR {
  const TakesLess(this.n);
  final int n;
}

sealed class ToolIR {
  const ToolIR();
}

class ToolHp extends ToolIR {
  const ToolHp(this.n);
  final int n;
}

class ToolDamage extends ToolIR {
  const ToolDamage(this.n);
  final int n;
}

class ToolNoRetreat extends ToolIR {
  const ToolNoRetreat();
}

class ToolTakesLess extends ToolIR {
  const ToolTakesLess(this.n);
  final int n;
}
