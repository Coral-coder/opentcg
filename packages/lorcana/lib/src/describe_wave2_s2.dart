part of 'describe.dart';

// Readable prints of the wave 2, slice 2 IR (ir_wave2_s2.dart).

String _w2Trig(W2Trigger t) => switch (t) {
  W2LeavesDiscard() => 'card leaves your discard',
  W2EntersExerted(:final subject) => '${subject.describe()} enters play exerted',
};

String _w2Static(W2Static e) => switch (e) {
  W2HandInkable() => 'cards in your hand are inkable',
  W2KeywordPer(:final kw, :final count) => 'this gains ${kw.name} +${_amt(count)}',
  W2NoDamageUnlessChallenged(:final affected) => '${affected?.describe() ?? 'this'} can\'t be dealt damage unless being challenged',
  W2FirstDamagePrevented() => 'first damage each turn prevented',
  W2MustBeChosen() => 'opponents must choose this',
  W2MoveCost(:final filter, :final here, :final less) => here ? '${filter.describe()} move here free' : 'moving ${filter.describe()} costs $less less',
  W2NoDiscard() => 'effects can\'t make you discard',
  W2NoLoseLore() => 'you can\'t lose lore',
  W2CantPlayThis() => 'can\'t be played',
  W2AltCost(:final filter, :final count, :final shift) => 'alternate cost: $count ${filter.describe()} from discard to deck bottom to ${shift ? 'shift' : 'play'} free',
  W2TopCardFaceUp() => 'top cards of decks face up',
  W2StaticTrigger(:final affected, :final ability) => '${affected?.describe() ?? 'this'} has "${describeAbility(ability)}"',
  W2FreeAbility(:final name) => '$name ability for free',
  W2BanishToInkwell() => 'banished → inkwell exerted instead',
};

String _w2Cond(W2Cond c) => switch (c) {
  W2SingersCond(:final n) => '$n+ singers',
  W2PlayedThisTurn(:final filter) => 'played ${filter.describe()} this turn',
  W2OpponentHas(:final filter, :final n) => 'an opponent has $n+ ${filter.describe()}',
  W2DiscardedIs(:final filter) => 'discarded ${filter.describe()}',
  W2RemovedAny() => 'removed damage',
  W2SlotIs(:final slot, :final filter) => '#$slot is ${filter.describe()}',
  W2SlotHasUnder(:final slot) => 'card under #$slot',
  W2PutUnderThisTurn() => 'put a card under this this turn',
  W2HadUnder() => 'had a card under it',
  W2DiscardedThisTurn() => 'you discarded this turn',
};

String _w2Amt(W2Amount a) => switch (a) {
  W2EventAmount() => 'event amount',
  W2CostOf(:final target) => 'cost of ${_tgt(target)}',
  W2RemovedAmount() => 'damage removed',
};

String _w2Effect(W2Effect e) => switch (e) {
  W2PlayFree(:final filter, :final from, :final slot, :final sameNameAsCost, :final bottomAfter) =>
    'play ${filter.describe()}${sameNameAsCost ? ' named as the cost' : ''} free from ${from.name}${slot == null ? '' : ' #$slot'}${bottomAfter ? ', then to deck bottom' : ''}',
  W2PlayThis(:final from, :final exerted) => 'play this from ${from.name}${exerted ? ' exerted' : ''}',
  W2PlayRemembered(:final slot) => 'play #$slot free',
  W2PlayTop() => 'reveal top, may play it, else discard',
  W2EachRevealPlay(:final filter) => 'each player shuffles, reveals top, may play ${filter.describe()} free, else bottom',
  W2Choose(:final target) => 'choose ${_tgt(target)}',
  W2UnlessTuck(:final slot, :final effect) => '${describeEffect(effect)} unless #$slot\'s player puts it on the bottom',
  W2HandToInkwell(:final exerted) => 'hand to inkwell${exerted ? ' exerted' : ''}',
  W2SearchDeck(:final filters, :final dest) => 'search deck for ${filters.map((f) => f.describe()).join(' or ')} → ${dest.name}',
  W2HandToDeck(:final n, :final top) => '$n from hand to deck ${top ? 'top' : 'bottom'}',
  W2RemoveTotal(:final filter, :final n) => 'remove up to $n damage total from ${filter.describe()}',
  W2OtherPlayerDraws(:final n) => 'another chosen player draws $n',
  W2ExertInkwell(:final who) => 'exert inkwell (${who.name})',
  W2TrimInkwell(:final who, :final n) => 'inkwell down to $n at random → hand (${who.name})',
  W2MillBranch(:final types, :final branches) => 'mill 1: ${[for (var i = 0; i < types.length; i++) '${types[i].map((t) => t.name).join('/')} → ${describeEffect(branches[i])}'].join(' | ')}',
  W2DiscardTrack(:final discard) => describeEffect(discard),
  W2Repeat(:final times, :final effect) => '${_amt(times)}× (${describeEffect(effect)})',
  W2OpponentsCantPlay(:final filter) => 'opponents can\'t play ${filter.describe()} until your next turn',
  W2GrantAbility(:final target, :final ability, :final duration) => '${_tgt(target)} gains "${describeAbility(ability)}" (${duration.name})',
  W2GrantClass(:final target, :final classification, :final duration) => '${_tgt(target)} gains $classification (${duration.name})',
  W2LoseKeyword(:final target, :final kw, :final duration) => '${_tgt(target)} loses ${kw.name} (${duration.name})',
  W2ReadyLimit(:final n) => 'opponents ready at most $n characters next turn',
  W2PutTopUnder(:final target) => 'top of deck under ${_tgt(target)}',
  W2MoveFormerUnder(:final target) => 'cards that were under this → under ${_tgt(target)}',
  W2DrawBottom() => 'draw from the bottom',
  W2ShiftFromDiscard() => 'shift a character from discard free',
  W2RevealInHand(:final filter) => 'reveal ${filter.describe()} in hand',
  W2DiscardEither(:final who, :final n, :final alt) => 'discard $n or 1 ${alt.describe()} (${who.name})',
  W2ShuffleFromAnyDiscard() => 'shuffle a card from any discard into its deck',
  W2TrackRemoved(:final effect) => describeEffect(effect),
  W2WithSingers(:final effect) => describeEffect(effect),
};
