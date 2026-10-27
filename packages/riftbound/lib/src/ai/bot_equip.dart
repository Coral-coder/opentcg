part of 'bot.dart';

/// The computer and Equipment: it equips its strongest Equipment onto the unit that gains most,
/// and answers the decisions game/equip.dart asks.
extension _BotEquip on RiftboundBot {
  /// An Equip (or other attaching) move worth making now, if any.
  RMove? _equipMove(Game g, List<RMove> legal) {
    ActivateMove? best;
    var bestScore = 0;
    for (final m in legal.whereType<ActivateMove>()) {
      final a = g.abilityOfMove(m);
      if (a is! Activated || !a.effects.any((e) => e is EqAttachMe || e is EqAttachTo)) continue;
      final o = g.state.objOrNull(m.source);
      final score = o != null && g.isEquipmentObj(m.source) ? 10 + (g.card(m.source).mightBonus ?? 0) : 5;
      if (score > bestScore) {
        bestScore = score;
        best = m;
      }
    }
    return best;
  }

  /// Answers to Equipment decisions, or null to answer as usual.
  List<int>? _equipAnswer(Game g, Decision d) {
    final s = g.state;
    final p = d.prompt.toLowerCase();
    int valueOf(ObjId id) => g.isUnit(id) ? g.might(id) * 10 + (s.obj(id).loc == base ? 0 : 5) : (g.card(id).mightBonus ?? 0) * 10 + 3;
    List<int> best(List<int> ids, {bool lowest = false}) {
      if (ids.isEmpty) return d.options.take(d.min).toList();
      final r = List.of(ids)..sortStable((a, b) => lowest ? valueOf(a) - valueOf(b) : valueOf(b) - valueOf(a));
      return [r.first];
    }

    if (d.kind == DecisionKind.cards) {
      final mine = [for (final id in d.options) if (s.objOrNull(id)?.controller == seat) id];
      // Attaching: the strongest Equipment, onto its strongest unit.
      if (p.startsWith('weaponmaster:') || p.contains('equipment to play free') || p.contains('attach one of')) return best(d.options);
      if (p.contains('choose attach this to a friendly unit') || p.contains('choose an equipment')) return best(mine.isEmpty ? d.options : mine);
      // Costs: the least valuable.
      if (p.startsWith('cost: choose a friendly unit to kill')) return best(d.options, lowest: true);
      if (p.startsWith('cost: recycle')) return d.options.take(d.min).toList();
      if (p.contains('to become a copy of')) return best(d.options);
      if (p.contains('a unit to play from your trash')) {
        final r = List.of(d.options)..sortStable((a, b) => g.card(b).energy - g.card(a).energy);
        return [r.first];
      }
    }
    return null;
  }
}
