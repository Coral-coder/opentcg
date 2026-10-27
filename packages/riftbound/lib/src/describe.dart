/// Short descriptions of parsed abilities, for tools, tests and the app's card details.
library;

import 'ir.dart';

String describeTarget(Target t) => switch (t) {
      Me() => 'me',
      Choose(:final filter, :final upTo) => '${upTo ? 'up to one' : 'a'} ${filter.describe()}',
      Chosen() => 'it',
      Each(:final filter) => 'each ${filter.describe()}',
      EventUnit() => 'that unit',
      HTarget() => t.describe(),
    };

String describeEffect(Effect e) => switch (e) {
      Deal(:final amount, :final target) => 'deal ${amount is N ? amount.n : 'my Might'} to ${describeTarget(target)}',
      Draw(:final n) => 'draw $n',
      Discard(:final n) => 'discard $n',
      Buff(:final target) => 'buff ${describeTarget(target)}',
      Ready(:final target) => 'ready ${describeTarget(target)}',
      Exhaust(:final target) => 'exhaust ${describeTarget(target)}',
      Stun(:final target) => 'stun ${describeTarget(target)}',
      Kill(:final target) => 'kill ${describeTarget(target)}',
      GiveMight(:final n, :final target, :final min) => 'give ${describeTarget(target)} ${n >= 0 ? '+' : ''}$n Might this turn${min == null ? '' : ' (min $min)'}',
      GiveKw(:final kw, :final n, :final target) => 'give ${describeTarget(target)} ${kw.name}${n > 1 ? ' $n' : ''} this turn',
      ToBase(:final target, :final asMove) => '${asMove ? 'move' : 'recall'} ${describeTarget(target)} to base',
      ToHand(:final target) => 'return ${describeTarget(target)} to hand',
      Heal(:final target) => 'heal ${describeTarget(target)}',
      Channel(:final n, :final exhausted) => 'channel $n rune${n == 1 ? '' : 's'}${exhausted ? ' exhausted' : ''}',
      PlayToken(:final token, :final count, :final here) => 'play $count $token${here ? ' here' : ''}',
      GainPoints(:final n) => 'gain $n point${n == 1 ? '' : 's'}',
      Predict(:final n) => 'predict $n',
      Counter() => 'counter a spell',
      AddRes(:final energy, :final anyPower, :final spellsOnly) => 'add ${energy > 0 ? '{$energy}' : ''}${'{A}' * anyPower}${spellsOnly ? ' (spells only)' : ''}',
      ReadyRunes(:final n) => 'ready $n runes',
      ToOrFromBase(:final target) => 'move ${describeTarget(target)} to or from base',
      If(:final cond, :final effects) => 'if ${switch (cond) {
          HandAtMost(:final n) => 'hand ≤ $n',
          UnitsThere(:final n) => '$n+ units there',
          HCond() => cond.describe(),
        }}: ${effects.map(describeEffect).join(', ')}',
      May(:final effects) => 'you may ${effects.map(describeEffect).join(', then ')}',
      Modes(:final modes) => 'choose one: ${modes.map((m) => m.map(describeEffect).join(', ')).join(' / ')}',
      HEffect() => e.describe(describeEffect, describeTarget),
    };

String describeAbility(Ability a) => switch (a) {
      KeywordAb(:final kw, :final n) => 'KW ${kw.name}${n > 1 ? ' $n' : ''}',
      Triggered(:final on, :final effects, :final legion) => 'TRIG ${legion ? 'legion ' : ''}${on.on.name}${on.moveToBattlefield ? '(bf)' : ''} → ${effects.map(describeEffect).join('; ')}',
      Activated(:final cost, :final effects, :final timing, :final oncePerTurn, :final legion) =>
        'ACT [${cost.describe()}]${timing == Timing.normal ? '' : ' ${timing.name}'}${legion ? ' legion' : ''}${oncePerTurn ? ' once/turn' : ''} → ${effects.map(describeEffect).join('; ')}',
      SpellBody(:final effects) => 'SPELL → ${effects.map(describeEffect).join('; ')}',
      Static(:final passive) => 'STATIC ${switch (passive) {
          Anthem(:final n, :final filter) => '${filter.describe()} +$n Might',
          EntersReady() => 'enters ready',
          NoCombatDamage() => 'no combat damage',
          DefendsAlone(:final n) => 'a friendly unit defending alone +$n Might',
          KwAnthem(:final kw, :final n, :final filter) => '${filter.describe()} have ${kw.name}${n > 1 ? ' $n' : ''}',
          EntersExhausted() => 'enters exhausted',
          CostLess(:final n, :final legion) => '${legion ? 'legion: ' : ''}costs {$n} less',
          HPassive() => passive.describe(),
        }}',
      RepeatCost(:final cost) => 'REPEAT ${cost.describe()}',
    };
