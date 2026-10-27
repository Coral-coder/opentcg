import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:riftbound/riftbound.dart';
import 'package:tcg_app/tcg_app.dart';

import 'riftbound_card.dart';
import 'riftbound_playable.dart';
import 'riftbound_session.dart';
import 'riftbound_store.dart';
import 'riftbound_theme.dart';

/// The Riftbound table, phone first: the opponent's strip and base on top, the battlefields in
/// the middle (their units above each, yours below), your base, your strip, your hand and the
/// bar with what's happening and what you can do. Everything you can use right now glows; tap
/// it to see its moves, long-press any card to read it.
class RiftboundTable extends StatefulWidget {
  const RiftboundTable({super.key});
  @override
  State<RiftboundTable> createState() => _RiftboundTableState();
}

class _RiftboundTableState extends State<RiftboundTable> {
  bool _dialogOpen = false;

  @override
  Widget build(BuildContext context) {
    final s = RiftboundStore.shared.session;
    if (s == null) return const Scaffold(body: Center(child: Text('No game')));
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final t = GameTheme.of(context);
        _maybeAsk(context, s);
        final g = s.match;
        final me = s.localSeat, opp = s.opponentSeat;
        final acts = RiftboundPlayable.of(g, me);
        final narrow = MediaQuery.of(context).size.width < 600;
        final cw = narrow ? 52.0 : 74.0;
        void onCard(int id) => _cardSheet(context, s, id, acts);
        return Scaffold(
          backgroundColor: t.bg,
          body: Stack(
            children: [
              const Positioned.fill(child: HextechBackdrop()),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      children: [
                        _TopBar(session: s),
                        _PlayerStrip(session: s, player: opp, acts: acts, onCard: onCard),
                        _BaseRow(session: s, player: opp, acts: acts, width: cw, onCard: onCard),
                        Expanded(child: _Battlefields(session: s, acts: acts, width: cw, onCard: onCard)),
                        _BaseRow(session: s, player: me, acts: acts, width: cw, onCard: onCard),
                        _PlayerStrip(session: s, player: me, acts: acts, onCard: onCard),
                        _Hand(session: s, acts: acts, width: narrow ? 66 : 92, onCard: onCard),
                        _ActionBar(session: s, acts: acts, onDecide: () => _ask(context, s)),
                      ],
                    ),
                  ),
                ),
              ),
              if (g.over) _GameOver(session: s, onRematch: () => setState(() {})),
            ],
          ),
        );
      },
    );
  }

  /// Opens the choice dialog when it's the local player's decision.
  void _maybeAsk(BuildContext context, RiftboundSession s) {
    final d = s.match.pending?.decision;
    if (d == null || d.player != s.localSeat || _dialogOpen || s.isLinked && !s.isLocalTurn) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_dialogOpen && s.match.pending?.decision == d) _ask(context, s);
    });
  }

  Future<void> _ask(BuildContext context, RiftboundSession s) async {
    final d = s.match.pending?.decision;
    if (d == null || d.player != s.localSeat || _dialogOpen) return;
    _dialogOpen = true;
    final answer = await showDialog<List<int>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => riftboundScope(RiftboundDecisionDialog(session: s, decision: d)),
    );
    _dialogOpen = false;
    if (answer != null) {
      s.perform(AnswerMove(s.localSeat, answer));
    } else if (mounted) {
      setState(() {}); // "Look at the table": the bar's Choose button reopens it.
    }
  }

  void _cardSheet(BuildContext context, RiftboundSession s, int id, RiftboundPlayable acts) {
    final g = s.match;
    final moves = acts.forObject(id);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: riftboundTheme.surface,
      builder: (sheet) => riftboundScope(
        Builder(
          builder: (sheet) {
            final t = GameTheme.of(sheet);
            final w = math.min(240.0, MediaQuery.of(sheet).size.width * 0.42);
            final buttons = <Widget>[];
            for (final m in moves) {
              buttons.add(_moveButton(sheet, s, m, id));
              // Move together (CR 144.3): every ready unit here that can go there too.
              if (m is MoveUnitsMove) {
                final group = acts.groupFor(g, id, m.to);
                if (group.length > 1) {
                  final total = group.fold<int>(0, (a, u) => a + g.mightUsed(u));
                  buttons.add(_moveButton(sheet, s, MoveUnitsMove(s.localSeat, group, m.to), id, label: 'Move all ${group.length} ready units here to ${g.locName(m.to, s.localSeat)} ($total Might)'));
                }
              }
            }
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.88),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...buttons,
                      if (moves.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_nothingReason(s, g, id), textAlign: TextAlign.center, style: t.style(13, color: t.muted)),
                        ),
                      Wrap(
                        spacing: 14,
                        runSpacing: 10,
                        children: [
                          RiftboundCardView(card: g.card(id), width: w),
                          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 380), child: RiftboundCardText(game: g, id: id)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _moveButton(BuildContext sheet, RiftboundSession s, RMove m, int id, {String? label}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: ThemedButton(
      label ?? moveLabel(s.match, m, s.localSeat),
      icon: switch (m) {
        PlayMove() => Icons.play_arrow,
        ActivateMove() => Icons.bolt,
        MoveUnitsMove() => Icons.directions_run,
        _ => Icons.check,
      },
      onPressed: () {
        Navigator.pop(sheet);
        s.perform(m);
      },
    ),
  );

  static String _nothingReason(RiftboundSession s, Game g, int id) {
    if (g.over) return 'The game is over.';
    if (g.pending != null) return 'A choice is waiting.';
    if (!s.isLocalTurn) return 'Not your move right now.';
    final o = g.state.obj(id);
    if (o.controller != s.localSeat && o.owner != s.localSeat) return 'Your opponent’s card.';
    final c = g.card(id);
    if (!RiftboundParser.parse(c).supported) return 'This card isn’t supported yet.';
    if (o.zone == Zone.hand || o.zone == Zone.champion) {
      if (g.state.chain.isNotEmpty) return 'Only Reactions can be played while a spell or ability is waiting to resolve.';
      if (g.state.showdown != null) return 'Only Action and Reaction cards can be played in a showdown.';
      return 'You can’t pay for this card right now (or it has no target).';
    }
    if (o.zone == Zone.board && g.isUnit(id)) return o.exhausted ? 'Exhausted: it readies at the start of your turn.' : 'It can’t do anything right now.';
    return 'Nothing to do with this card right now.';
  }
}

/// What a move button says.
String moveLabel(Game g, RMove m, int seat) => switch (m) {
  PlayMove(:final card) => 'Play ${g.nameOf(card)}${g.state.obj(card).zone == Zone.trash ? ' from the trash with Flow, then banish it' : ''} (${_cost(g, card, seat)})',
  ActivateMove(:final source, :final index) => _abilityLabel(g, source, index),
  MoveUnitsMove(:final units, :final to) => 'Move ${units.length == 1 ? g.nameOf(units.first) : '${units.length} units'} to ${to == base ? 'your base' : g.locName(to, seat)}',
  PassMove() => 'Pass',
  EndTurnMove() => 'End turn',
  _ => m.toString(),
};

String _cost(Game g, int card, int seat) {
  final c = g.playCost(seat, card);
  final p = c.power.isEmpty ? '' : ' + ${c.power.length} ${c.power.first?.label ?? 'any'} Power';
  return '${c.energy} Energy$p';
}

String _abilityLabel(Game g, int source, int index) {
  if (index == grantedXpAbility) return 'Use ${g.nameOf(source)} [{E}]: gain 1 XP';
  final a = g.parsed(source).abilities[index];
  if (a is! Activated) return 'Use ${g.nameOf(source)}';
  final cost = a.cost.describe();
  return 'Use ${g.nameOf(source)}${cost.isEmpty ? '' : ' [$cost]'}: ${a.effects.map(describeEffect).join(', ')}';
}

/// A card's rules text and, on the board, its state.
class RiftboundCardText extends StatelessWidget {
  const RiftboundCardText({super.key, required this.game, required this.id});
  final Game game;
  final int id;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = game;
    final c = g.card(id);
    final o = g.state.obj(id);
    final p = RiftboundParser.parse(c);
    final type = [if (c.champion) 'Champion', if (c.signature) 'Signature', if (c.token) 'Token', c.type.name[0].toUpperCase() + c.type.name.substring(1)].join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(c.name, style: t.display(20, color: t.accent)),
        Row(
          children: [
            Flexible(child: Text('$type${c.tags.isEmpty ? '' : ' · ${c.tags.join(', ')}'}', style: t.small)),
            const SizedBox(width: 6),
            for (final d in c.domains) DomainPip(d, size: 14),
          ],
        ),
        if (c.isMainDeck) Text('Cost: ${c.energy} Energy${c.power > 0 ? ' + ${c.power} Power' : ''}${c.might != null ? ' · ${c.might} Might' : ''}', style: t.style(13)),
        const SizedBox(height: 6),
        Text(c.text.isEmpty ? '(No rules text.)' : c.text, style: t.style(14, weight: FontWeight.w500)),
        if (!p.supported) ...[
          const SizedBox(height: 6),
          Text('Not supported yet: ${p.unsupported.join(' / ')}', style: t.style(12, color: t.danger)),
        ],
        if ((o.zone == Zone.board || o.zone == Zone.legend) && !g.isUnit(id) && o.pw.empowered > 0) ...[
          const Divider(height: 20),
          Text('Empowered${o.pw.empowered > 1 ? ' ×${o.pw.empowered}' : ''}', style: t.style(14, weight: FontWeight.w800, color: const Color(0xFFB98CFF))),
        ],
        if (o.zone == Zone.trash && c.type == CardType.spell && g.state.player(o.owner).trash.contains(id)) ...[
          const Divider(height: 20),
          Text('In the trash. With Flow it can be played from here (then it is banished).', style: t.style(12, color: t.muted)),
        ],
        if (o.zone == Zone.board && g.isUnit(id)) ...[
          const Divider(height: 20),
          Text('Might now: ${g.might(id)}${o.damage > 0 ? ' · ${o.damage} damage' : ''}', style: t.style(14, weight: FontWeight.w800)),
          Text(
            [if (o.exhausted) 'Exhausted' else 'Ready', if (o.buffed) 'Buffed (+${1 + o.pw.extraBuffs})', if (o.pw.empowered > 0) 'Empowered${o.pw.empowered > 1 ? ' ×${o.pw.empowered}' : ''}', if (o.stunned) 'Stunned', if (o.mightMod != 0) '${o.mightMod > 0 ? '+' : ''}${o.mightMod} Might this turn', 'at ${o.loc == base ? 'base' : g.locName(o.loc, o.controller)}'].join(' · '),
            style: t.style(12, color: t.muted),
          ),
        ],
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.session});
  final RiftboundSession session;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = session.match;
    final st = g.state;
    final me = session.localSeat, opp = session.opponentSeat;
    final title = g.over
        ? 'Game over'
        : (st.phase == Phase.setup || st.turn == 0 ? 'Setting up' : (session.thinking ? '${session.playerNames[opp]} is thinking…' : 'Turn ${st.turn} · ${st.player(st.active).name}'));
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Leave the table',
            icon: Icon(Icons.close, color: t.accent),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.display(18, color: t.accent)),
                Text('First to ${st.victoryScore} · you ${st.player(me).points} — ${st.player(opp).points} ${st.player(opp).name}', style: t.style(11, color: t.muted)),
              ],
            ),
          ),
          IconButton(tooltip: 'Game log', icon: Icon(Icons.receipt_long, color: t.accent), onPressed: () => _showLog(context, g)),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: t.accent),
            onSelected: (v) {
              if (v == 'concede') session.concede();
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'concede', child: Text('Concede'))],
          ),
        ],
      ),
    );
  }

  static void _showLog(BuildContext context, Game g) {
    showModalBottomSheet(
      context: context,
      backgroundColor: riftboundTheme.surface,
      builder: (sheet) => riftboundScope(
        Builder(
          builder: (sheet) {
            final t = GameTheme.of(sheet);
            final log = g.state.log.reversed.take(120).toList();
            return SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [for (final e in log) Text(e.text, style: t.style(13, weight: e.kind == 'turn' ? FontWeight.w800 : FontWeight.w500))],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A player's strip: score gems, runes (ready / on the board, by domain), hand, deck, trash,
/// and their legend and Chosen Champion.
class _PlayerStrip extends StatelessWidget {
  const _PlayerStrip({required this.session, required this.player, required this.acts, required this.onCard});
  final RiftboundSession session;
  final int player;
  final RiftboundPlayable acts;
  final void Function(int) onCard;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = session.match;
    final st = g.state;
    final pl = st.player(player);
    final mine = player == session.localSeat;
    final active = st.active == player && !g.over;
    final ready = pl.runes.where((r) => !st.obj(r).exhausted).length;
    final byDomain = <Domain, int>{};
    for (final r in pl.runes) {
      final d = runeDomain(g.card(r));
      if (d != null) byDomain[d] = (byDomain[d] ?? 0) + 1;
    }
    Widget chip(IconData i, String v, String tip) => Tooltip(
      message: tip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 15, color: t.muted), const SizedBox(width: 2), Text(v, style: t.style(13, weight: FontWeight.w700))]),
      ),
    );
    Widget mini(int id, String tip) => Tooltip(
      message: st.obj(id).pw.empowered > 0 ? '$tip (Empowered)' : tip,
      child: GestureDetector(
        onTap: () => onCard(id),
        onLongPress: () => onCard(id),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _Glow(on: mine && acts.hasAny(id), child: RiftboundCardView(card: g.card(id), width: 28)),
            if (st.obj(id).pw.empowered > 0) const Positioned(right: -5, top: -5, child: _EmpoweredMark(size: 13)),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: HexPanel(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        glow: active ? (mine ? t.accent2 : t.danger) : null,
        child: Row(
          children: [
            if (pl.legend != null) mini(pl.legend!, 'Legend: ${g.nameOf(pl.legend!)}'),
            if (pl.champion != null) ...[const SizedBox(width: 4), mini(pl.champion!, 'Chosen Champion (playable from here): ${g.nameOf(pl.champion!)}')],
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(pl.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.style(13, weight: FontWeight.w800, color: active ? t.accent : t.text)),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: _ScoreGems(points: pl.points, of: st.victoryScore)),
                ],
              ),
            ),
            Flexible(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: 'Runes: $ready ready of ${pl.runes.length}. Exhaust for Energy, recycle for Power.',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.diamond_outlined, size: 15, color: t.accent2),
                          Text(' $ready/${pl.runes.length} ', style: t.style(13, weight: FontWeight.w800, color: t.accent2)),
                          for (final e in byDomain.entries) ...[DomainPip(e.key, size: 13), Text('${e.value} ', style: t.style(11))],
                        ],
                      ),
                    ),
                    Tooltip(
                      message: 'XP: ${pl.pw.xp}. Gained by Hunt and other effects, spent on abilities; [Level N] abilities are active with N XP.',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.auto_awesome, size: 15, color: Color(0xFF6FD3FF)),
                          Text(' ${pl.pw.xp} XP', style: t.style(13, weight: FontWeight.w800, color: const Color(0xFF6FD3FF))),
                        ]),
                      ),
                    ),
                    chip(Icons.style, '${pl.hand.length}', 'Cards in hand'),
                    chip(Icons.layers, '${pl.deck.length}', 'Main Deck'),
                    chip(Icons.delete_outline, '${pl.trash.length}', 'Trash'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The mark of an Empowered card (CR 442): a violet bolt, with a count when Empowered several
/// times.
class _EmpoweredMark extends StatelessWidget {
  const _EmpoweredMark({required this.size, this.times = 1});
  final double size;
  final int times;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return Tooltip(
      message: times > 1 ? 'Empowered ×$times' : 'Empowered',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(color: const Color(0xFF3A2A6E), borderRadius: BorderRadius.circular(size), border: Border.all(color: const Color(0xFFB98CFF))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bolt, size: size, color: const Color(0xFFE2CCFF)),
          if (times > 1) Text('$times', style: t.style(size * 0.7, weight: FontWeight.w900, color: const Color(0xFFE2CCFF))),
        ]),
      ),
    );
  }
}

/// Points as a row of gems out of the Victory Score.
class _ScoreGems extends StatelessWidget {
  const _ScoreGems({required this.points, required this.of});
  final int points, of;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < of; i++)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: i < points ? t.accent : Colors.transparent, border: Border.all(color: t.accent, width: 1)),
              ),
            ),
          ),
        const SizedBox(width: 4),
        Text('$points/$of', style: t.style(11, weight: FontWeight.w800, color: t.accent)),
      ],
    );
  }
}

/// A row of a player's base: units and gear.
class _BaseRow extends StatelessWidget {
  const _BaseRow({required this.session, required this.player, required this.acts, required this.width, required this.onCard});
  final RiftboundSession session;
  final int player;
  final RiftboundPlayable acts;
  final double width;
  final void Function(int) onCard;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = session.match;
    final ids = [
      for (final o in g.state.objects.values)
        if (o.zone == Zone.board && o.controller == player && o.loc == base) o.id,
    ];
    return SizedBox(
      height: width * 1.396 + 10,
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: RotatedBox(quarterTurns: 3, child: Center(child: Text(player == session.localSeat ? 'YOUR BASE' : 'THEIR BASE', style: t.style(9, weight: FontWeight.w800, color: t.muted)))),
          ),
          Expanded(
            child: ids.isEmpty
                ? Center(child: Text('Empty', style: t.style(11, color: t.muted)))
                : ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    children: [for (final id in ids) _Unit(session: session, id: id, acts: acts, width: width, onCard: onCard)],
                  ),
          ),
        ],
      ),
    );
  }
}

/// A unit or gear on the board: its card, Might, damage, buff and stun, dimmed when exhausted,
/// glowing when it can do something.
class _Unit extends StatelessWidget {
  const _Unit({required this.session, required this.id, required this.acts, required this.width, required this.onCard});
  final RiftboundSession session;
  final int id;
  final RiftboundPlayable acts;
  final double width;
  final void Function(int) onCard;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = session.match;
    final o = g.state.obj(id);
    final unit = g.isUnit(id);
    final m = unit ? g.might(id) : 0;
    final printed = g.card(id).might ?? 0;
    final can = acts.hasAny(id);
    final sd = g.state.showdown;
    final fighting = sd != null && sd.combat && o.loc == sd.bf;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        button: true,
        label: '${g.nameOf(id)}${unit ? ', $m Might' : ''}${o.exhausted ? ', exhausted' : ''}${can ? ', can act' : ''}',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () => onCard(id),
          onLongPress: () => onCard(id),
          child: _Glow(
            on: can,
            color: fighting ? t.danger : t.accent2,
            child: Opacity(
              opacity: o.exhausted ? 0.55 : 1,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  RiftboundCardView(card: g.card(id), width: width),
                  if (unit)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: _Badge(text: '$m', color: m > printed ? t.ok : (m < printed ? t.danger : const Color(0xFF081420)), border: t.accent),
                    ),
                  if (o.damage > 0) Positioned(left: -2, bottom: -2, child: _Badge(text: '-${o.damage}', color: t.danger, border: Colors.white)),
                  if (o.buffed) const Positioned(left: -2, top: -2, child: Icon(Icons.arrow_circle_up, size: 16, color: Color(0xFF3FC380))),
                  if (o.pw.extraBuffs > 0) Positioned(left: 13, top: -3, child: Text('×${1 + o.pw.extraBuffs}', style: t.style(10, weight: FontWeight.w900, color: const Color(0xFF3FC380)))),
                  if (o.pw.empowered > 0) Positioned(left: width / 2 - 8, top: -6, child: _EmpoweredMark(size: 16, times: o.pw.empowered)),
                  if (o.stunned) const Positioned(right: -2, top: -2, child: Icon(Icons.flash_off, size: 16, color: Color(0xFFE5C14A))),
                  if (o.exhausted) Positioned.fill(child: Center(child: Icon(Icons.rotate_90_degrees_ccw, size: width * 0.34, color: Colors.white70))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, required this.border});
  final String text;
  final Color color, border;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(color: color, border: Border.all(color: border, width: 1.2), borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1)),
  );
}

/// A cyan glow for things the local player can use right now.
class _Glow extends StatelessWidget {
  const _Glow({required this.on, required this.child, this.color});
  final bool on;
  final Widget child;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    if (!on) return child;
    final c = color ?? GameTheme.of(context).accent2;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c, width: 2),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 10, spreadRadius: 1)],
      ),
      child: child,
    );
  }
}

/// The battlefields side by side: who controls each, the units of each player there, and any
/// showdown or combat going on.
class _Battlefields extends StatelessWidget {
  const _Battlefields({required this.session, required this.acts, required this.width, required this.onCard});
  final RiftboundSession session;
  final RiftboundPlayable acts;
  final double width;
  final void Function(int) onCard;
  @override
  Widget build(BuildContext context) {
    final g = session.match;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < g.state.bfs.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _Battlefield(session: session, index: i, acts: acts, width: width, onCard: onCard),
            ),
          ),
      ],
    );
  }
}

class _Battlefield extends StatelessWidget {
  const _Battlefield({required this.session, required this.index, required this.acts, required this.width, required this.onCard});
  final RiftboundSession session;
  final int index;
  final RiftboundPlayable acts;
  final double width;
  final void Function(int) onCard;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = session.match;
    final st = g.state;
    final b = st.bfs[index];
    final me = session.localSeat, opp = session.opponentSeat;
    final sd = st.showdown;
    final here = sd != null && sd.bf == index;
    final owner = b.controller;
    final color = owner == null ? const Color(0x66C8AA6E) : (owner == me ? t.accent2 : t.danger);
    final status = here
        ? (sd.combat ? 'COMBAT' : 'SHOWDOWN')
        : (b.contestedBy != null ? 'CONTESTED' : (owner == null ? 'Uncontrolled' : (owner == me ? 'You control it' : '${st.player(owner).name} controls it')));
    Widget units(int p) {
      final ids = g.unitsAt(index, player: p);
      if (ids.isEmpty) return SizedBox(height: width * 0.5);
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 2,
        runSpacing: 4,
        children: [for (final id in ids) _Unit(session: session, id: id, acts: acts, width: width, onCard: onCard)],
      );
    }

    return HexPanel(
      padding: const EdgeInsets.all(4),
      glow: here ? (sd.combat ? t.danger : t.accent2) : (owner == null ? null : color),
      // The battlefield shrinks to leave room for a row of units on each side, so the whole
      // zone shows without scrolling (it still scrolls when many units crowd in). A wide, short
      // zone puts the battlefield beside its units instead.
      child: LayoutBuilder(
        builder: (context, c) {
          Widget card(double w) => GestureDetector(
            onTap: () => onCard(b.obj),
            onLongPress: () => onCard(b.obj),
            child: RiftboundCardView(card: g.card(b.obj), width: w),
          );
          final label = Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(status, textAlign: TextAlign.center, style: t.style(11, weight: FontWeight.w800, color: here ? (sd.combat ? t.danger : t.accent2) : color)),
          );
          final unitRow = width * 1.396 + 8;
          final fit = (c.maxHeight - 8 - 2 * unitRow - 24) / 0.716;
          if (fit < 140 && c.maxWidth > 420) {
            return Row(
              children: [
                card(math.min(math.min(220.0, c.maxWidth * 0.4), (c.maxHeight - 8) / 0.716)),
                const SizedBox(width: 6),
                Expanded(
                  child: SingleChildScrollView(child: Column(children: [units(opp), label, units(me)])),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              children: [
                units(opp),
                const SizedBox(height: 4),
                card(math.max(60.0, math.min(math.min(c.maxWidth, 220.0), fit))),
                label,
                units(me),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The local player's hand; playable cards rise and glow.
class _Hand extends StatelessWidget {
  const _Hand({required this.session, required this.acts, required this.width, required this.onCard});
  final RiftboundSession session;
  final RiftboundPlayable acts;
  final double width;
  final void Function(int) onCard;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = session.match;
    final hand = g.state.player(session.localSeat).hand;
    // Spells that can be played from the trash now (Flow) sit after the hand, marked.
    final fromTrash = [for (final id in g.state.player(session.localSeat).trash) if (acts.canPlay(id)) id];
    final ids = [...hand, ...fromTrash];
    final h = width * 1.396 + 14;
    return SizedBox(
      height: h,
      child: ids.isEmpty
          ? Center(child: Text('No cards in hand', style: t.style(12, color: t.muted)))
          : ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final id in ids)
                  Padding(
                    padding: EdgeInsets.only(right: 4, top: acts.canPlay(id) ? 0 : 8, bottom: acts.canPlay(id) ? 8 : 0),
                    child: Semantics(
                      button: true,
                      label: '${g.nameOf(id)}${acts.canPlay(id) ? ', playable' : ''}${fromTrash.contains(id) ? ' from the trash (Flow)' : ''}',
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: () => onCard(id),
                        onLongPress: () => onCard(id),
                        child: Opacity(
                          opacity: acts.canPlay(id) || acts.all.isEmpty ? 1 : 0.5,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _Glow(on: acts.canPlay(id), child: RiftboundCardView(card: g.card(id), width: width)),
                              if (fromTrash.contains(id))
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: -2,
                                  child: Center(child: _Badge(text: 'FLOW · trash', color: const Color(0xFF3A2A6E), border: const Color(0xFFB98CFF))),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// What's happening (the computer's last moves, a showdown, a choice) and the buttons for what
/// to do: choose, pass, end turn.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.session, required this.acts, required this.onDecide});
  final RiftboundSession session;
  final RiftboundPlayable acts;
  final VoidCallback onDecide;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = session.match;
    final st = g.state;
    final me = session.localSeat;
    final d = g.pending?.decision;
    String line;
    final buttons = <Widget>[];
    if (g.over) {
      line = 'The game is over.';
    } else if (d != null && d.player == me) {
      line = d.prompt;
      buttons.add(ThemedButton('Choose', icon: Icons.touch_app, expand: false, color: t.accent2, onPressed: onDecide));
    } else if (d != null) {
      line = '${st.player(d.player).name} is choosing: ${d.prompt}';
    } else if (session.isLocalTurn) {
      final sd = st.showdown;
      if (st.chain.isNotEmpty) {
        final top = st.chain.last;
        line = 'Respond to ${g.nameOf(top.source)}? You can play a Reaction, or pass to let it resolve.';
      } else if (sd != null) {
        line = '${sd.combat ? 'Combat' : 'Showdown'} at ${g.nameOf(st.bfs[sd.bf].obj)}: you have Focus. Play an Action or Reaction, or pass.';
      } else {
        line = 'Your turn · ${playableSummary(g, me, acts)}';
      }
      if (acts.canPass) buttons.add(ThemedButton('Pass', icon: Icons.redo, expand: false, color: t.accent2, onPressed: () => session.perform(PassMove(me))));
      if (acts.canEndTurn) {
        final nothingLeft = acts.all.every((m) => m is EndTurnMove);
        buttons.add(_Pulse(on: nothingLeft, child: ThemedButton('End turn', icon: Icons.skip_next, expand: false, color: nothingLeft ? t.accent : t.accent2, onPressed: () => session.perform(EndTurnMove(me)))));
      }
    } else {
      line = session.thinking ? '${st.player(session.opponentSeat).name} is thinking…' : 'Waiting for ${st.player(session.opponentSeat).name}…';
    }
    final recent = [for (final e in session.recent) if (e.player != me || e.kind == 'conquer' || e.kind == 'hold' || e.kind == 'die') e].reversed.take(3).toList().reversed.toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: const BoxDecoration(
        color: Color(0xF00A1826),
        border: Border(top: BorderSide(color: Color(0x99C8AA6E))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (recent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(recent.map((e) => '• ${e.text}').join('\n'), maxLines: 3, overflow: TextOverflow.ellipsis, style: t.style(11, color: t.muted)),
            ),
          if (session.lastError != null) Text(session.lastError!, style: t.style(12, color: t.danger)),
          Row(
            children: [
              Expanded(child: Text(line, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.style(13, weight: FontWeight.w700))),
              for (final b in buttons) Padding(padding: const EdgeInsets.only(left: 6), child: b),
            ],
          ),
        ],
      ),
    );
  }
}

/// Gently pulses its child (the End turn button once nothing else is left).
class _Pulse extends StatefulWidget {
  const _Pulse({required this.on, required this.child});
  final bool on;
  final Widget child;
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didUpdateWidget(covariant _Pulse old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    // Held still under widget tests, which can't wait out a repeating animation.
    final testing = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (widget.on && !testing) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.on ? ScaleTransition(scale: Tween(begin: 1.0, end: 1.06).animate(_c), child: widget.child) : widget.child;
}

/// Answers a decision: pick cards (tap to choose, long-press to read one), yes/no or an option.
class RiftboundDecisionDialog extends StatefulWidget {
  const RiftboundDecisionDialog({super.key, required this.session, required this.decision});
  final RiftboundSession session;
  final Decision decision;
  @override
  State<RiftboundDecisionDialog> createState() => _RiftboundDecisionDialogState();
}

class _RiftboundDecisionDialogState extends State<RiftboundDecisionDialog> {
  final picked = <int>[];

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final d = widget.decision;
    final g = widget.session.match;
    final source = d.source == null || g.state.objOrNull(d.source!) == null ? null : g.nameOf(d.source!);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (source != null) Text(source, style: t.style(13, color: t.muted)),
        Text(d.prompt, style: t.display(19, color: t.accent)),
      ],
    );
    final look = TextButton(onPressed: () => Navigator.pop(context), child: const Text('Look at the table'));
    switch (d.kind) {
      case DecisionKind.yesNo:
        return AlertDialog(
          backgroundColor: riftboundTheme.surface,
          title: title,
          actions: [
            look,
            TextButton(onPressed: () => Navigator.pop(context, const [0]), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.pop(context, const [1]), child: const Text('Yes')),
          ],
        );
      case DecisionKind.option:
        return AlertDialog(
          backgroundColor: riftboundTheme.surface,
          title: title,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < d.labels.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ThemedButton(d.labels[i], onPressed: () => Navigator.pop(context, [i])),
                ),
            ],
          ),
          actions: [look],
        );
      case DecisionKind.cards:
        final ok = picked.length >= d.min && picked.length <= d.max;
        return AlertDialog(
          backgroundColor: riftboundTheme.surface,
          title: title,
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in d.options)
                    Builder(
                      builder: (context) {
                        final on = picked.contains(id);
                        final o = g.state.objOrNull(id);
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (on) {
                              picked.remove(id);
                            } else {
                              if (picked.length == d.max) picked.removeAt(0);
                              picked.add(id);
                            }
                          }),
                          onLongPress: () => showDialog<void>(
                            context: context,
                            builder: (c) => riftboundScope(
                              Dialog(
                                backgroundColor: riftboundTheme.surface,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [RiftboundCardView(card: g.card(id), width: 240), const SizedBox(height: 8), RiftboundCardText(game: g, id: id)],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: on ? t.accent2 : Colors.transparent, width: 3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Semantics(button: true, label: 'Option: ${g.nameOf(id)}', excludeSemantics: true, child: RiftboundCardView(card: g.card(id), width: 92)),
                                if (o != null && o.zone == Zone.board)
                                  Text(
                                    '${o.controller == widget.session.localSeat ? 'Yours' : 'Theirs'} · ${o.loc == base ? 'base' : g.locName(o.loc, o.controller)}',
                                    style: t.style(10, color: t.muted),
                                  ),
                                if (on) Icon(Icons.check_circle, color: t.accent2, size: 18),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            look,
            Text('${picked.length} chosen (${d.min == d.max ? d.min : '${d.min}–${d.max}'})', style: t.small),
            FilledButton(onPressed: ok ? () => Navigator.pop(context, List.of(picked)) : null, child: const Text('Confirm')),
          ],
        );
    }
  }
}

class _GameOver extends StatelessWidget {
  const _GameOver({required this.session, required this.onRematch});
  final RiftboundSession session;
  final VoidCallback onRematch;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final st = session.state;
    final won = st.winner == session.localSeat;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: HexPanel(
              glow: won ? t.accent : t.danger,
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(won ? 'Victory' : 'Defeat', textAlign: TextAlign.center, style: t.display(34, color: won ? t.accent : t.danger)),
                  const SizedBox(height: 8),
                  Text([for (final p in st.players) '${p.name}: ${p.points} points'].join('\n'), textAlign: TextAlign.center, style: t.style(15)),
                  const SizedBox(height: 14),
                  if (!session.isLinked) ...[
                    ThemedButton(
                      'Rematch',
                      icon: Icons.replay,
                      tall: true,
                      color: t.accent,
                      onPressed: () {
                        RiftboundStore.shared.newGame(
                          names: List.of(session.playerNames),
                          decks: [for (final d in session.decks) List.of(d)],
                          seed: math.Random().nextInt(1 << 30),
                          hotseat: session.mode == SessionMode.hotseat,
                        );
                        onRematch();
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  ThemedButton(
                    'Back',
                    tall: true,
                    outlined: true,
                    onPressed: () {
                      RiftboundStore.shared.endSession();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
