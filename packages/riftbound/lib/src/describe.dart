/// Short descriptions of parsed abilities, for tools, tests and the app's card details.
library;

import 'describe_costs.dart';
import 'describe_power.dart';
import 'ir.dart';

String describeTarget(Target t) => switch (t) {
      Me() => 'me',
      Choose(:final filter, :final upTo) => '${upTo ? 'up to one' : 'a'} ${filter.describe()}',
      Chosen() => 'it',
      Each(:final filter) => 'each ${filter.describe()}',
      EventUnit() => 'that unit',
      EqTarget() => t.describe(),
      GenTarget() => t.describe(),
      HTarget() => t.describe(),
    };

String describeEffect(Effect e) => switch (e) {
      Deal(:final amount, :final target) => 'deal ${amount is N ? amount.n : (amount is EqAmount ? amount.describe() : 'my Might')} to ${describeTarget(target)}',
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
      AddRes(:final energy, :final anyPower, :final spellsOnly, :final power) => 'add ${energy > 0 ? '{$energy}' : ''}${power.map((d) => '{${d.letter}}').join()}${'{A}' * anyPower}${spellsOnly ? ' (spells only)' : ''}',
      ReadyRunes(:final n) => 'ready $n runes',
      ToOrFromBase(:final target) => 'move ${describeTarget(target)} to or from base',
      If(:final cond, :final effects) => 'if ${describeCond(cond)}: ${effects.map(describeEffect).join(', ')}',
      May(:final effects) => 'you may ${effects.map(describeEffect).join(', then ')}',
      Modes(:final modes, :final distinct, :final perTurn) => 'choose one${distinct ? ' (each different)' : ''}${perTurn ? ' (not chosen this turn)' : ''}: ${modes.map((m) => m.map(describeEffect).join(', ')).join(' / ')}',
      PowerEffect() => describePower(e),
      HEffect() => e.describe(describeEffect, describeTarget),
      EqMayPay(:final cost, :final effects) => 'you may pay ${cost.describe()} to ${effects.map(describeEffect).join(', ')}',
      EqEffect() => e.describe(),
      XEffect() => describeXEffect(e),
      GenEffect() => e.describe(),
      W3Effect() => e.describe(),
    };

String describeCond(Cond c) => switch (c) {
      HandAtMost(:final n) => 'hand ≤ $n',
      UnitsThere(:final n) => '$n+ units there',
      PowerCond() => describePowerCond(c),
      HCond() => c.describe(),
      EqCond() => c.describe(),
      XCond() => describeXCond(c),
      GenCond() => c.describe(),
      W3Cond() => c.describe(),
    };

String describeAbility(Ability a) => switch (a) {
      KeywordAb(:final kw, :final n) => 'KW ${kw.name}${n > 1 ? ' $n' : ''}',
      Triggered(:final on, :final effects, :final legion, :final gate) =>
        'TRIG ${gate == null ? '' : '[${describeGate(gate)}] '}${legion ? 'legion ' : ''}${on is EqWhen ? on.event.name : on is W3When ? on.kind.name : on is GenWhen ? on.describe() : (on is XWhen && on.kind != null ? on.kind!.name : on.on.name)}${on is XWhen && on.n > 0 ? '(${on.n})' : ''}${on.moveToBattlefield ? '(bf)' : ''}${on is XWhen && on.fromTrash ? ' from trash' : ''}${on is XWhen && on.cond != null ? ' if ${describeCond(on.cond!)}' : ''} → ${effects.map(describeEffect).join('; ')}',
      Activated(:final cost, :final effects, :final timing, :final oncePerTurn, :final legion, :final gate) =>
        'ACT ${gate == null ? '' : '[${describeGate(gate)}] '}[${cost.describe()}]${timing == Timing.normal ? '' : ' ${timing.name}'}${legion ? ' legion' : ''}${oncePerTurn ? ' once/turn' : ''} → ${effects.map(describeEffect).join('; ')}',
      SpellBody(:final effects) => 'SPELL → ${effects.map(describeEffect).join('; ')}',
      Static(:final passive, :final gate) => 'STATIC ${gate == null ? '' : '[${describeGate(gate)}] '}${switch (passive) {
          Anthem(:final n, :final filter) => '${filter.describe()} +$n Might',
          EntersReady() => 'enters ready',
          NoCombatDamage() => 'no combat damage',
          DefendsAlone(:final n) => 'a friendly unit defending alone +$n Might',
          KwAnthem(:final kw, :final n, :final filter) => '${filter.describe()} have ${kw.name}${n > 1 ? ' $n' : ''}',
          EntersExhausted() => 'enters exhausted',
          CostLess(:final n, :final legion) => '${legion ? 'legion: ' : ''}costs {$n} less',
          EqPassive() => passive.describe(),
          PowerPassive() => describePowerPassive(passive),
          HPassive() => passive.describe(),
          XPassive() => passive.describe(),
          GenPassive() => passive.describe(),
          W3Passive() => passive.describe(),
        }}',
      RepeatCost(:final cost) => 'REPEAT ${cost.describe()}',
    };
