/// Descriptions of the Empower / XP / buff / Flow IR (ir_power.dart), for describe.dart.
library;

import 'describe.dart';
import 'ir.dart';

String describePower(PowerEffect e) {
  String list(List<Effect> es) => es.map(describeEffect).join(', ');
  return switch (e) {
    EmpowerMe() => 'empower me',
    Empower(:final target, :final off, :final untilEndOfTurn) => '${off ? 'disempower' : 'empower'} ${describeTarget(target)}${untilEndOfTurn ? ' (until end of turn)' : ''}',
    GainXp(:final amount) => 'gain ${describeAmount(amount)} XP',
    BuffUpTo(:final n, :final filter) => 'buff up to $n ${filter.describe()}',
    PayToDo(:final pay, :final effects, :final optional) => '${optional ? 'may ' : ''}${describePay(pay)} to ${list(effects)}',
    InsteadIf(:final cond, :final normal, :final instead) => '${list(normal)}; if ${describeCond(cond)} instead ${list(instead)}',
    SpendBuffsEach(:final effects) => 'spend any buffs: per buff ${list(effects)}',
    SpendEachBuffToReady() => 'spend buffs to ready',
    SpendBuffOf(:final target) => 'spend the buff of ${describeTarget(target)}',
    Banish(:final target) => 'banish ${describeTarget(target)}',
    BanishFromTrash() => 'banish a unit from your trash',
    Burn(:final n, :final opponent) => '${opponent ? 'opponent ' : ''}burn $n',
    LookBanishPlay(:final n, :final energyLess) => 'look at $n, may banish a unit or gear and play it for {$energyLess} less, then may empower it',
    Pick(:final target) => 'choose ${describeTarget(target)}',
    GiftMe() => 'a chosen player takes control of this and recalls it',
    MightUpTo(:final slot) => 'my Might up to #$slot\'s',
    BaseMightBecomes(:final n, :final target) => 'base Might of ${describeTarget(target)} becomes $n',
    Delayed(:final kind, :final n) => 'this turn: $kind${n > 0 ? ' $n' : ''}',
    GrantFlow() => 'give a spell in trash Flow',
    PowerToken(:final token, :final count, :final might) => 'play $count $might-Might $token',
    LookDraw(:final n, :final unitsOnly, :final restToTrash, :final thenIfTags, :final then) =>
      'look at $n, draw ${unitsOnly ? 'a unit' : 'one'}, rest ${restToTrash ? 'to trash' : 'recycled'}${then.isEmpty ? '' : '; if a ${thenIfTags.join('/')}: ${then.map(describeEffect).join(', ')}'}',
    PlayFromTrash(:final opponentsTrash) => 'play a unit from ${opponentsTrash ? 'their' : 'your'} trash free',
    RevealHand(:final payXpDiscard, :final xp) => 'reveal their hand${payXpDiscard > 0 ? ', may spend $payXpDiscard XP to make them discard one' : ''}${xp > 0 ? ', gain $xp XP' : ''}',
    EachKillsOne() => 'each player kills one of their units',
    MoveAny(:final target, :final toBattlefield) => 'move ${describeTarget(target)}${toBattlefield ? ' to a battlefield' : ''}',
    StareDown() => 'move weaker enemy units there to base',
    SplitMightDamage(:final xpPerKill) => 'deal its Might split${xpPerKill > 0 ? ', XP per kill' : ''}',
    OneOf(:final options) => options.map(list).join(' or '),
    Untargetable(:final target) => '${describeTarget(target)} can\'t be chosen by enemies',
    GiveKwAll(:final kw, :final filter) => 'give each ${filter.describe()} ${kw.name}',
    ReadyGear(:final n) => 'ready $n gear',
    GiveMightAll(:final n, :final filter) => 'give each ${filter.describe()} +$n Might',
  };
}
