/// Short descriptions of the effects in ir_costs.dart (for describe.dart).
library;

import 'describe.dart';
import 'ir.dart';

String describeXEffect(XEffect e) => switch (e) {
      EachPlayer(:final draw, :final discard) => draw > 0 ? 'each player draws $draw' : 'each player discards $discard',
      Fight(:final a, :final b) => '${describeTarget(a)} and ${describeTarget(b)} deal damage equal to their Mights to each other',
      IfElse(:final cond, :final then, :final otherwise) => 'if ${describeCond(cond)}: ${then.map(describeEffect).join(', ')}; otherwise ${otherwise.map(describeEffect).join(', ')}',
      PlayFrom(:final zone, :final types, :final tags, :final maxEnergy, :final maxPower, :final lessThanPoints, :final maxOfKilled, :final ignoreEnergy, :final ignoreAll, :final toBase, :final recycleAfter) =>
        'play ${types.isEmpty ? 'a card' : types.map((t) => t.name).join('/')}${tags.isEmpty ? '' : ' (${tags.join('/')})'} from ${zone.name}${maxEnergy == null ? '' : ' E≤$maxEnergy'}${maxPower == null ? '' : ' P≤$maxPower'}${lessThanPoints ? ' E<points' : ''}${maxOfKilled ? ' ≤ the killed unit' : ''}${ignoreAll ? ' ignoring its cost' : (ignoreEnergy ? ' ignoring its Energy cost' : '')}${toBase ? ' to base' : ''}${recycleAfter ? ', then recycle it' : ''}',
      RecycleOpponentTrash(:final n) => 'recycle up to $n cards from opponents\' trashes',
      RecycleYourTrash(:final n) => 'recycle $n from your trash',
      MoveToOpenBf() => 'move any number of your units to an open battlefield',
      BanishTrashThen(:final then, :final anyTrash, :final unit) => 'banish a ${unit ? 'unit' : 'card'} from ${anyTrash ? 'any' : 'your'} trash to ${then.map(describeEffect).join(', ')}',
      DefenderKills() => 'the defender kills one of their units here',
      KillThenReplay(:final target, :final maxMight) => 'kill ${describeTarget(target)}; if it had $maxMight Might or less, may play this again from trash',
      KillGearByCost(:final max, :final myMight, :final then) => 'kill a gear with Energy cost ≤ ${myMight ? 'my Might' : '{$max}'}${then.isEmpty ? '' : '; if you do, ${then.map(describeEffect).join(', ')}'}',
      DoThen(:final first, :final then) => '${describeEffect(first)}; if you do, ${then.map(describeEffect).join(', ')}',
      TurnFx(:final fx, :final energy, :final power) => switch (fx) {
          XTurnFx.nextSpellLess => 'your next spell this turn costs {$energy} less',
          XTurnFx.nextCardLess => 'your next card costs {$energy}${'{A}' * power} less',
          XTurnFx.unitsMore => 'your non-token units cost {$energy} more this turn',
          XTurnFx.freeGear => 'you may play a gear with Energy ≤{$energy} from hand this turn ignoring its Energy cost',
          XTurnFx.nextSpellRepeat => 'your next spell this turn gets Repeat equal to its cost',
        },
      CounterByCost(:final maxEnergy, :final maxPower) => 'counter a spell costing ≤{$maxEnergy} and ≤$maxPower Power',
      LookDrawType(:final n, :final type, :final minEnergy) => 'look at the top $n; may reveal a ${type.name}${minEnergy > 0 ? ' with Energy ≥$minEnergy' : ''} and draw it; recycle the rest',
      PlayOpponentsTop() => 'banish the top card of an opponent\'s deck and play it for free',
      BanishTrashUnits() => 'banish all units from your trash',
      RecycleToPlay(:final tag) => 'recycle another friendly unit to play a $tag from your trash, cheaper by its Might',
      ExhaustMeThen(:final then) => 'exhaust me to ${then.map(describeEffect).join(', ')}',
      ReturnMeFromTrash(:final discard) => '${discard > 0 ? 'discard $discard to ' : ''}return this from your trash to your hand',
      PayToPlayMe(:final energy, :final power) => 'pay {$energy}${power.map((d) => '{${d?.letter ?? 'A'}}').join()} to play me from your trash',
      AbilityCostLess(:final n, :final per) => '(costs {$n} less per ${per.name})',
      MightPerTags(:final target, :final n, :final tags) => 'give ${describeTarget(target)} +$n Might this turn per tag among your units of ${tags.join('/')}',
      LookPlay(:final n, :final types, :final reduceEnergy, :final ignoreAll, :final kill, :final mightPlus) =>
        '${kill == null ? '' : 'kill ${describeTarget(kill)}; '}look at the top $n; may banish a ${types.map((t) => t.name).join('/')}${kill == null ? '' : ' with Might up to the killed unit\'s +$mightPlus'} and play it${ignoreAll ? ' ignoring its cost' : ', {$reduceEnergy} less'}; recycle the rest',
      RevealPlay(:final n, :final reduceEnergy) => 'reveal the top $n; may play one {$reduceEnergy} cheaper; draw the rest',
      EachPlayerLookPlay(:final n) => 'each player picks one of their top $n, recycles the rest, and plays it ignoring its Energy cost',
      StealOrCounter(:final maxEnergy, :final power) => 'choose a spell with Energy ≤{$maxEnergy}; pay ${power.map((d) => '{${d?.letter ?? 'A'}}').join()} to take control of it and make new choices, or counter it',
    };
