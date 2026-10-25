/// A readable print of the ability IR (for tools, tests and the card detail view).
library;

import 'ir.dart';

String describeAbility(Ability a) => switch (a) {
  KeywordAbility(:final keyword) => 'KW ${keyword.key}',
  Triggered(:final trigger, :final effect, :final condition, :final during, :final oncePerTurn) =>
    'TRIG ${_trig(trigger)}${during == null ? '' : ' during ${_cond(during)}'}${oncePerTurn ? ' once/turn' : ''}${condition == null ? '' : ' IF ${_cond(condition)}'} → ${describeEffect(effect)}',
  Activated(:final cost, :final effect) => 'ACT [${_cost(cost)}] → ${describeEffect(effect)}',
  Static(:final effect, :final condition, :final inHand) => 'STATIC${inHand ? '(hand)' : ''} ${_static(effect)}${condition == null ? '' : ' while ${_cond(condition)}'}',
  ActionEffect(:final effect) => 'ACTION ${describeEffect(effect)}',
};

String _trig(Trigger t) => switch (t) {
  OnPlay() => 'on play',
  CardPlayed(:final filter, :final by, :final nth) => '${by.name} play ${filter.describe()}${nth > 0 ? ' #$nth this turn' : ''}',
  CardEvent(:final event, :final subject, :final other, :final where, :final here) =>
    '${subject == null ? 'this' : subject.describe()} ${event.name}${other == null ? '' : ' ${other.describe()}'}${where == null ? '' : ' while ${where.describe()}'}${here ? ' here' : ''}',
  TurnStep(:final start, :final yours, :final opponents) => '${start ? 'start' : 'end'} of ${yours ? 'your' : (opponents ? 'each opponent\'s' : 'each')} turn',
  Draws(:final by, :final nth, :final theirTurn) => '${by.name} draw${nth > 0 ? ' #$nth' : ''}${theirTurn ? ' in their turn' : ''}',
  MovedHere() => 'moved here',
  On(:final what, :final self, :final subject, :final by, :final min, :final max, :final nth) =>
    '${what.name}(${self ? 'this' : (subject?.describe() ?? 'any')}${by == Owner.any ? '' : ' by ${by.name}'}${min > 0 ? ' ≥$min' : ''}${max != null ? ' ≤$max' : ''}${nth > 0 ? ' #$nth' : ''})',
};

String _cost(Cost c) => [
  if (c.exert) 'exert',
  if (c.ink > 0) '${c.ink} ink',
  if (c.banishSelf) 'banish this',
  if (c.discard > 0) 'discard ${c.discard}',
  if (c.exertOther != null) 'exert ${c.exertOther!.describe()}',
  if (c.banishOther != null) 'banish ${c.banishOther!.describe()}',
].join(', ');

String _static(StaticEffect e) => switch (e) {
  StaticMod(:final affected, :final stat, :final amount, :final negative) => '${affected?.describe() ?? 'this'} ${negative ? '-' : '+'}${_amt(amount)} ${stat.name}',
  StaticKeyword(:final affected, :final keyword) => '${affected?.describe() ?? 'this'} gains ${keyword.key}',
  StaticRule(:final affected, :final rule) => '${affected?.describe() ?? 'this'} ${rule.name}',
  CostReduction(:final filter, :final amount, :final self) => 'pay ${_amt(amount)} less for ${self ? 'this' : filter.describe()}',
  EntersWith(:final exerted, :final damage) => 'enters${exerted ? ' exerted' : ''}${damage > 0 ? ' with $damage damage' : ''}',
  ExtraInk() => 'extra ink',
  SkipDraw() => 'skip draw',
  CantBeChallengedBy(:final attackers, :final defenders) => '${defenders?.describe() ?? 'this'} can\'t be challenged by ${attackers.describe()}',
  ChallengerMod(:final stat, :final amount, :final negative) => 'challenger ${negative ? '-' : '+'}$amount ${stat.name}',
  OpponentsLoreToWin(:final n) => 'opponents need $n lore',
  OpposingEnterExerted(:final filter) => 'opposing ${filter.describe()} enter exerted',
  OpposingInkExerted() => 'opposing ink enters exerted',
  MayEnterExerted(:final then) => 'may enter exerted${then == null ? '' : ' to ${describeEffect(then)}'}',
  DeckLimit(:final max) => 'deck limit ${max ?? 'any'}',
  ShiftName(:final name) => 'counts as named ${name ?? 'anything'} for Shift',
  S3Static() => e.describe(_s3),
};

String _cond(Cond c) => switch (c) {
  CountCond(:final filter, :final cmp, :final n, :final place) => 'count(${filter.describe()} in ${place.name}) ${cmp.name} $n',
  SelfState(:final exerted, :final atLocation, :final damaged) => 'this${exerted == true ? ' exerted' : ''}${atLocation == true ? ' at location' : ''}${damaged == true ? ' damaged' : ''}${damaged == false ? ' undamaged' : ''}',
  YourTurn() => 'your turn',
  HandCond(:final who, :final cmp, :final n) => 'hand(${who.name}) ${cmp.name} $n',
  LoreCond(:final who, :final cmp, :final n) => 'lore(${who.name}) ${cmp.name} $n',
  Not(c: final x) => 'not ${_cond(x)}',
  AllConds(:final conds) => conds.map(_cond).join(' and '),
  DidIt() => 'did it',
  TargetIs(:final filter) => 'target is ${filter.describe()}',
  CompareZone(:final who, :final place, :final cmp) => '${place.name}(${who.name}) ${cmp.name} yours',
  HasUnder() => 'card under this',
  TurnStatCond(:final stat, :final who, :final cmp, :final n, :final excludeSource) => '${stat.name}(${who.name}${excludeSource ? ', other' : ''}) ${cmp.name} $n',
  ShiftedCond() => 'played by shift',
  HandCompare(:final chosen) => '${chosen ? 'chosen opponent' : 'an opponent'} has more cards in hand',
  SelfDamage(:final min) => 'this has $min+ damage',
  StrongestCond() => 'you have the strongest character',
  FirstTurnNotFirstPlayer() => 'first turn, second player',
  SelfStat(:final stat, :final cmp, :final n) => 'this.${stat.name} ${cmp.name} $n',
  SelfHasUnder() => 'card under this',
  AnyWithUnder(:final whose) => '${whose.name} card with a card under it',
  InkwellCond(:final who, :final cmp, :final n) => 'inkwell(${who.name}) ${cmp.name} $n',
  MoreThanEachOpponent(:final place, :final filter) => 'more ${filter?.describe() ?? 'cards'} in ${place.name} than each opponent',
  BeingChallenged() => 'being challenged',
  Challenging(:final defender) => 'challenging ${defender.describe()}',
  ThisTurnCond(:final what, :final cmp, :final n) => '${what.name} this turn ${cmp.name} $n',
  BanishedThisTurn(:final filter, :final inChallenge) => '${filter.describe()} banished${inChallenge ? ' in a challenge' : ''} this turn',
  S3Cond() => c.describe(_s3),
};

String _zone(ZoneEffect e) => switch (e) {
  Peek(:final n, :final who, :final picks, :final rest, :final reveal) =>
    '${reveal ? 'reveal' : 'look at'} top $n (${who.name})${picks.map((p) => ', ${p.optional ? 'may ' : ''}take ${p.anyNumber ? 'any' : p.count} ${p.named ? 'named' : (p.filters.isEmpty ? 'card' : p.filters.map((f) => f.describe()).join(' or '))} → ${p.dest.name}${p.exerted ? ' exerted' : ''}${p.then == null ? '' : ' then ${describeEffect(p.then!)}'}').join()}, rest → ${rest.name}',
  NameCard() => 'name a card',
  RevealHand(:final who, :final discard) => 'reveal hand (${who.name})${discard == null ? '' : ', discard ${discard.describe()} of your choice'}',
  EachMay(:final who, :final effect, :final lorePerRefusal) => 'each (${who.name}) may ${describeEffect(effect)}${lorePerRefusal > 0 ? ', +$lorePerRefusal lore per refusal' : ''}',
  InkFromDeck(:final who, :final n, :final exerted) => 'top $n of deck to inkwell${exerted ? ' exerted' : ''} (${who.name})',
  ReadyInkwell(:final who) => 'ready inkwell (${who.name})',
  FromDiscard(:final filter, :final who, :final count, :final upTo, :final all, :final dest, :final named, :final exerted) =>
    '${all ? 'all' : '${upTo ? 'up to ' : ''}$count'} ${named ? 'named ' : ''}${filter.describe()} from discard (${who.name}) → ${dest.name}${exerted ? ' exerted' : ''}',
  PutUnder(:final filter) => 'top of deck under ${filter.describe()}',
  UnderTo(:final target, :final dest, :final random) => 'cards under ${_tgt(target)} → ${dest.name}${random ? ' (random)' : ''}',
  PayInk(:final n) => 'pay $n ink',
  DrawToMatch(:final who) => 'draw to match hand (${who.name})',
};

String _amt(Amount a) => switch (a) {
  Fixed(:final n) => '$n',
  CountOf(:final filter, :final per, :final place) => '$per×#(${filter.describe()} in ${place.name})',
  StatOf(:final target, :final stat) => '${_tgt(target)}.${stat.name}',
  HandSize(:final who, :final per) => '$per×hand(${who.name})',
  DamageOn(:final target) => 'damage on ${_tgt(target)}',
  DamageOnSelf(:final per, :final times) => '$times×(damage on this / $per)',
  UnderSelf(:final times) => '$times×cards under this',
  S3Amount() => a.describe(_s3),
};

String _tgt(Target t) => switch (t) {
  This() => 'this',
  Chosen(:final filter, :final count, :final upTo, :final slot) => 'chosen${upTo ? ' up to' : ''} $count ${filter.describe()} #$slot',
  AllOf(:final filter) => 'all ${filter.describe()}',
  EventCard(:final other) => other ? 'event.other' : 'event card',
  Remembered(:final slot) => 'that #$slot',
  LocationOf(:final of) => 'location of ${_tgt(of)}',
};

const _s3 = S3Printers(describeEffect, _cond, _amt, _tgt);

String describeEffect(Effect e) => switch (e) {
  ZoneEffect() => _zone(e),
  S3Effect() => e.describe(_s3),
  Seq(:final steps) => steps.map(describeEffect).join('; '),
  May(e: final x) => 'MAY(${describeEffect(x)})',
  If(:final cond, :final then, :final otherwise) => 'IF ${_cond(cond)} THEN ${describeEffect(then)}${otherwise == null ? '' : ' ELSE ${describeEffect(otherwise)}'}',
  ChooseOne(:final options) => 'ONE OF {${options.map(describeEffect).join(' | ')}}',
  Draw(:final who, :final amount, :final untilHandSize) => 'draw ${untilHandSize ? 'until hand is ' : ''}${_amt(amount)} (${who.name})',
  Discard(:final who, :final amount, :final random, :final all) => 'discard ${all ? 'all' : _amt(amount)}${random ? ' at random' : ''} (${who.name})',
  GainLore(:final who, :final amount) => 'gain ${_amt(amount)} lore (${who.name})',
  LoseLore(:final who, :final amount) => 'lose ${_amt(amount)} lore (${who.name})',
  DealDamage(:final target, :final amount, :final put) => '${put ? 'put' : 'deal'} ${_amt(amount)} damage to ${_tgt(target)}',
  RemoveDamage(:final target, :final amount, :final all) => 'remove ${all ? 'all' : _amt(amount)} damage from ${_tgt(target)}',
  MoveDamage(:final from, :final to, :final amount, :final upTo) => 'move ${upTo ? 'up to ' : ''}${_amt(amount)} damage ${_tgt(from)} → ${_tgt(to)}',
  Banish(:final target) => 'banish ${_tgt(target)}',
  ReturnToHand(:final target) => 'return ${_tgt(target)} to hand',
  Exert(:final target) => 'exert ${_tgt(target)}',
  Ready(:final target) => 'ready ${_tgt(target)}',
  ToDeck(:final target, :final bottom, :final top) =>
    '${_tgt(target)} to deck${bottom
        ? ' bottom'
        : top
        ? ' top'
        : ' (shuffle)'}',
  ToInkwell(:final target, :final exerted) => '${_tgt(target)} to inkwell${exerted ? ' exerted' : ''}',
  InkTopOfDeck(:final exerted) => 'top of deck to inkwell${exerted ? ' exerted' : ''}',
  InkFromHand(:final exerted) => 'card from hand to inkwell${exerted ? ' exerted' : ''}',
  Modify(:final target, :final stat, :final amount, :final duration, :final negative) => '${_tgt(target)} ${negative ? '-' : '+'}${_amt(amount)} ${stat.name} (${duration.name})',
  GrantKeyword(:final target, :final keyword, :final duration) => '${_tgt(target)} gains ${keyword.key} (${duration.name})',
  GrantRule(:final target, :final rule, :final duration) => '${_tgt(target)} ${rule.name} (${duration.name})',
  FromDiscardToHand(:final filter, :final count, :final upTo) => 'return ${upTo ? 'up to ' : ''}$count ${filter.describe()} from discard',
  LookTop(:final n, :final pick, :final pickCount, :final restBottom, :final reorderOnly) =>
    'look at top $n${reorderOnly ? ', reorder' : ''}${pick == null ? '' : ', take $pickCount ${pick.describe()}'}${restBottom ? ', rest bottom' : ''}',
  Mill(:final who, :final n) => 'mill $n (${who.name})',
  NextCostReduction(:final filter, :final n) => 'next ${filter.describe()} costs $n less',
  PlayFree(:final filter, :final from) => 'play ${filter.describe()} free from ${from.name}',
  Floating(:final ability) => 'this turn: ${describeAbility(ability)}',
  Delayed(:final effect) => 'at end of turn: ${describeEffect(effect)}',
  MoveFree(:final character) => 'move ${_tgt(character)} free',
  PlayerChooses(:final who, :final filter, :final slot, :final then) => '${who.name} each choose own ${filter.describe()} #$slot: ${describeEffect(then)}',
  SameNameAs(:final chosen, :final others, :final into) => 'remember ${others.describe()} sharing a name with ${_tgt(chosen)} as #$into',
  LoseLoreRicher(:final amount) => 'opponents with more lore lose ${_amt(amount)}',
  MoveToLocation(:final characters, :final toEventLocation) => 'move ${characters.map(_tgt).join(' & ')} to ${toEventLocation ? 'that location' : 'a location of yours'} free',
};
