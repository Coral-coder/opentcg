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
};

String _cond(Cond c) => switch (c) {
  CountCond(:final filter, :final cmp, :final n, :final place) => 'count(${filter.describe()} in ${place.name}) ${cmp.name} $n',
  SelfState(:final exerted, :final atLocation, :final damaged) => 'this${exerted == true ? ' exerted' : ''}${atLocation == true ? ' at location' : ''}${damaged == true ? ' damaged' : ''}',
  YourTurn() => 'your turn',
  HandCond(:final who, :final cmp, :final n) => 'hand(${who.name}) ${cmp.name} $n',
  LoreCond(:final who, :final cmp, :final n) => 'lore(${who.name}) ${cmp.name} $n',
  Not(c: final x) => 'not ${_cond(x)}',
  AllConds(:final conds) => conds.map(_cond).join(' and '),
  DidIt() => 'did it',
  TargetIs(:final filter) => 'target is ${filter.describe()}',
};

String _amt(Amount a) => switch (a) {
  Fixed(:final n) => '$n',
  CountOf(:final filter, :final per, :final place) => '$per×#(${filter.describe()} in ${place.name})',
  StatOf(:final target, :final stat) => '${_tgt(target)}.${stat.name}',
  HandSize(:final who, :final per) => '$per×hand(${who.name})',
};

String _tgt(Target t) => switch (t) {
  This() => 'this',
  Chosen(:final filter, :final count, :final upTo, :final slot) => 'chosen${upTo ? ' up to' : ''} $count ${filter.describe()} #$slot',
  AllOf(:final filter) => 'all ${filter.describe()}',
  EventCard(:final other) => other ? 'event.other' : 'event card',
  Remembered(:final slot) => 'that #$slot',
};

String describeEffect(Effect e) => switch (e) {
  Seq(:final steps) => steps.map(describeEffect).join('; '),
  May(e: final x) => 'MAY(${describeEffect(x)})',
  If(:final cond, :final then, :final otherwise) => 'IF ${_cond(cond)} THEN ${describeEffect(then)}${otherwise == null ? '' : ' ELSE ${describeEffect(otherwise)}'}',
  ChooseOne(:final options) => 'ONE OF {${options.map(describeEffect).join(' | ')}}',
  Draw(:final who, :final amount) => 'draw ${_amt(amount)} (${who.name})',
  Discard(:final who, :final amount, :final random, :final all) => 'discard ${all ? 'all' : _amt(amount)}${random ? ' at random' : ''} (${who.name})',
  GainLore(:final who, :final amount) => 'gain ${_amt(amount)} lore (${who.name})',
  LoseLore(:final who, :final amount) => 'lose ${_amt(amount)} lore (${who.name})',
  DealDamage(:final target, :final amount, :final put) => '${put ? 'put' : 'deal'} ${_amt(amount)} damage to ${_tgt(target)}',
  RemoveDamage(:final target, :final amount, :final all) => 'remove ${all ? 'all' : _amt(amount)} damage from ${_tgt(target)}',
  MoveDamage(:final from, :final to, :final amount) => 'move ${_amt(amount)} damage ${_tgt(from)} → ${_tgt(to)}',
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
  InkFromHand() => 'card from hand to inkwell',
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
};
