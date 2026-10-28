part of 'bot.dart';

/// The computer and wave 2, slice 1's decisions (game/w2s1.dart): keep its best when told to
/// keep a few, give up its least valuable, ready everything of its own it may.
extension _BotS1 on RiftboundBot {
  List<int>? _s1Answer(Game g, Decision d) {
    if (d.kind != DecisionKind.cards) return null;
    final p = d.prompt;
    final s = g.state;
    int value(ObjId id) {
      final o = s.objOrNull(id);
      if (o == null) return 0;
      if (o.zone == Zone.board && g.isUnit(id)) return g.might(id) * 10;
      return g.card(id).energy + g.card(id).power;
    }

    List<ObjId> ranked({required bool best}) => List.of(d.options)..sortStable((a, b) => best ? value(b) - value(a) : value(a) - value(b));
    // Divine Judgment: keep the best.
    if (p.startsWith('Choose ') && p.endsWith(' to keep')) return ranked(best: true).take(d.min).toList();
    // Returning a unit as a cost: the least valuable.
    if (p.startsWith('Choose a unit to return')) return ranked(best: false).take(1).toList();
    // Acceleration Gate: ready as many of its own as it may.
    if (p.contains('to ready')) {
      final mine = [for (final id in d.options) if (s.objOrNull(id)?.controller == seat) id];
      return mine.take(d.max).toList();
    }
    return null;
  }
}
