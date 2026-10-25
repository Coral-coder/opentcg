import 'dart:math' as math;

import 'package:flutter/material.dart' hide Ink;
import 'package:lorcana/lorcana.dart';
import 'package:tcg_app/tcg_app.dart';

import 'lorcana_card.dart';
import 'lorcana_session.dart';
import 'lorcana_store.dart';

/// The Lorcana table: the opponent's lore and play area on top, yours below, your hand and what
/// to do now at the bottom. Tap a card for what it can do.
class LorcanaTable extends StatefulWidget {
  const LorcanaTable({super.key});
  @override
  State<LorcanaTable> createState() => _LorcanaTableState();
}

class _LorcanaTableState extends State<LorcanaTable> {
  bool _dialogOpen = false;

  @override
  Widget build(BuildContext context) {
    final s = LorcanaStore.shared.session;
    if (s == null) return const Scaffold(body: Center(child: Text('No game')));
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final t = GameTheme.of(context);
        _maybeAsk(context, s);
        final me = s.localSeat, opp = s.opponentSeat;
        return Scaffold(
          backgroundColor: t.bg,
          body: Stack(children: [
            Positioned.fill(child: TableBackdrop(theme: t)),
            SafeArea(
              child: LayoutBuilder(builder: (context, box) {
                final cardW = math.min(110.0, math.max(54.0, box.maxWidth / 7.5));
                return Column(children: [
                  _TopBar(session: s),
                  _PlayerStrip(session: s, player: opp, onCard: (id) => _cardActions(context, s, id)),
                  Expanded(child: _PlayArea(session: s, player: opp, cardWidth: cardW, onCard: (id) => _cardActions(context, s, id))),
                  const Divider(height: 1),
                  Expanded(child: _PlayArea(session: s, player: me, cardWidth: cardW, onCard: (id) => _cardActions(context, s, id))),
                  _PlayerStrip(session: s, player: me, onCard: (id) => _cardActions(context, s, id)),
                  _Hand(session: s, cardWidth: math.min(96.0, cardW * 0.95), onCard: (id) => _cardActions(context, s, id)),
                  _PromptBar(session: s, onDecide: () => _ask(context, s)),
                ]);
              }),
            ),
            if (s.state.over) _GameOver(session: s),
          ]),
        );
      },
    );
  }

  /// Opens the choice dialog when it's the local player's decision.
  void _maybeAsk(BuildContext context, LorcanaSession s) {
    final d = s.match.pending?.decision;
    if (d == null || d.player != s.localSeat || _dialogOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_dialogOpen && s.match.pending?.decision == d) _ask(context, s);
    });
  }

  Future<void> _ask(BuildContext context, LorcanaSession s) async {
    final d = s.match.pending?.decision;
    if (d == null || d.player != s.localSeat || _dialogOpen) return;
    _dialogOpen = true;
    final answer = await showDialog<List<int>>(context: context, barrierDismissible: false, builder: (_) => _DecisionDialog(session: s, decision: d));
    _dialogOpen = false;
    if (answer != null) s.perform(AnswerMove(s.localSeat, answer));
  }

  void _cardActions(BuildContext context, LorcanaSession s, int id) {
    final g = s.match;
    final moves = s.isLocalTurn && g.pending == null ? [for (final m in g.legalMoves()) if (_mentions(g, m, id)) m] : const <LMove>[];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheet) {
        final t = GameTheme.of(sheet);
        final card = g.card(id);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: LorcanaCardView(card: card, width: math.min(260, MediaQuery.of(sheet).size.width * 0.6))),
              const SizedBox(height: 10),
              if (moves.isEmpty) Text(s.isLocalTurn ? 'Nothing to do with this card right now.' : 'Not your turn.', textAlign: TextAlign.center, style: t.small),
              for (final m in moves)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ThemedButton(_label(g, m, id), onPressed: () {
                    Navigator.pop(sheet);
                    s.perform(m);
                  }),
                ),
            ]),
          ),
        );
      },
    );
  }

  // A card played from a discard or from under another card shows on the card that allows it.
  static bool _mentions(Game g, LMove m, int id) => switch (m) {
        PlayMove(:final card) when g.state.obj(card).zone != Place.hand => g.playEnabler(card) == id,
        InkMove(:final card) || PlayMove(:final card) || QuestMove(:final card) || ActivateMove(:final card) => card == id,
        ChallengeMove(:final card, :final target) => card == id || target == id,
        MoveMove(:final card, :final location) => card == id || location == id,
        _ => false,
      };

  static String _label(Game g, LMove m, int id) {
    String name(int x) => g.card(x).fullName;
    return switch (m) {
      InkMove() => 'Put into your inkwell',
      PlayMove(:final mode, :final onto, :final singers) => switch (mode) {
          PlayMode.ink when g.state.obj(m.card).zone != Place.hand => 'Play ${name(m.card)} (${g.playCost(m.seat, m.card)} ink)',
          PlayMode.ink => 'Play (${g.chars(m.card).cost} ink)',
          PlayMode.shift when g.state.obj(m.card).zone != Place.hand => 'Shift ${name(m.card)} onto ${name(onto!)}',
          PlayMode.shift => 'Shift onto ${name(onto!)}',
          PlayMode.sing => 'Sing it with ${singers.map(name).join(' and ')}',
        },
      QuestMove(:final card) => 'Quest (+${g.chars(card).loreAtLeast0} lore)',
      ChallengeMove(:final card, :final target) => card == id ? 'Challenge ${name(target)}' : 'Challenged by ${name(card)}',
      MoveMove(:final card, :final location) => card == id ? 'Move to ${name(location)}' : 'Move ${name(card)} here',
      ActivateMove(:final card, :final index) => 'Use: ${g.abilitiesOf(card)[index].text}',
      _ => m.toString(),
    };
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.session});
  final LorcanaSession session;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final st = session.state;
    return SizedBox(
      height: 40,
      child: Row(children: [
        IconButton(icon: Icon(Icons.close, color: t.accent), tooltip: 'Leave the table', onPressed: () => Navigator.of(context).maybePop()),
        Expanded(
          child: Text(
            session.isLinked
                ? '${session.link?.status ?? ''} · turn ${st.turn}'
                : (session.thinking ? '${session.playerNames[session.opponentSeat]} is thinking…' : 'Turn ${st.turn} · ${st.player(st.active).name}'),
            style: t.style(13, weight: FontWeight.w700, color: t.muted),
          ),
        ),
        IconButton(icon: Icon(Icons.receipt_long, color: t.accent), tooltip: 'Game log', onPressed: () => _showLog(context, st)),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: t.accent),
          onSelected: (v) {
            if (v == 'concede') session.concede();
          },
          itemBuilder: (_) => const [PopupMenuItem(value: 'concede', child: Text('Concede'))],
        ),
      ]),
    );
  }

  void _showLog(BuildContext context, GameState st) {
    showModalBottomSheet(
      context: context,
      builder: (c) => ListView(padding: const EdgeInsets.all(12), children: [for (final e in st.log.reversed.take(200)) Text(e.text, style: GameTheme.of(c).style(12))]),
    );
  }
}

/// One player's line: lore toward 20, ink, hand, deck and discard (tap it to see the cards, and
/// what can be done with them), and the top of the deck when it's faceup.
class _PlayerStrip extends StatelessWidget {
  const _PlayerStrip({required this.session, required this.player, required this.onCard});
  final LorcanaSession session;
  final int player;
  final void Function(int id) onCard;

  void _showDiscard(BuildContext context, Game g, List<int> ids) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final id in ids.reversed)
              GestureDetector(
                onTap: () {
                  Navigator.pop(sheet);
                  onCard(id);
                },
                child: LorcanaCardView(card: g.card(id), width: 80),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = session.match;
    final p = g.state.player(player);
    final active = g.state.active == player;
    Widget chip(IconData icon, String n, String tip) => Tooltip(
          message: tip,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: t.muted), const SizedBox(width: 2), Text(n, style: t.style(13))]),
          ),
        );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: t.panel.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12), border: Border.all(color: active ? t.accent : Colors.transparent, width: 2)),
      child: Row(children: [
        if (active) Icon(Icons.play_arrow, size: 18, color: t.accent),
        Flexible(child: Text(p.name, style: t.style(14, weight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 10),
        // Lore race to 20 (CR 1.11).
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (c, a) => ScaleTransition(scale: a.drive(Tween(begin: 1.8, end: 1.0)), child: c),
          child: Text('${p.lore}', key: ValueKey(p.lore), style: t.style(22, weight: FontWeight.w900, color: t.accent)),
        ),
        Text(' / 20', style: t.style(12, color: t.muted)),
        const SizedBox(width: 6),
        SizedBox(width: 60, child: LinearProgressIndicator(value: (p.lore / 20).clamp(0, 1), color: t.accent, backgroundColor: t.surface)),
        const Spacer(),
        chip(Icons.water_drop, '${g.inkReady(player)}/${p.inkwell.length}', 'Ink ready / in inkwell'),
        chip(Icons.style, '${p.hand.length}', 'Hand'),
        chip(Icons.layers, '${p.deck.length}', 'Deck'),
        if (p.deck.isNotEmpty && g.topCardFaceUp(player)) chip(Icons.visibility, g.card(p.deck.first).name, 'Top of the deck (faceup)'),
        GestureDetector(onTap: p.discard.isEmpty ? null : () => _showDiscard(context, g, p.discard), child: chip(Icons.delete_outline, '${p.discard.length}', 'Discard')),
      ]),
    );
  }
}

class _PlayArea extends StatelessWidget {
  const _PlayArea({required this.session, required this.player, required this.cardWidth, required this.onCard});
  final LorcanaSession session;
  final int player;
  final double cardWidth;
  final void Function(int id) onCard;

  @override
  Widget build(BuildContext context) {
    final g = session.match;
    final ids = g.state.player(player).play;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(6),
      child: Center(
        child: Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
          for (final id in ids) _TableCard(key: ValueKey(id), session: session, id: id, width: cardWidth, onTap: () => onCard(id)),
        ]),
      ),
    );
  }
}

/// A card in play: turned sideways when exerted, with damage and a mark while it's drying.
class _TableCard extends StatelessWidget {
  const _TableCard({super.key, required this.session, required this.id, required this.width, required this.onTap});
  final LorcanaSession session;
  final int id;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = session.match;
    final o = g.state.obj(id);
    final c = g.chars(id);
    final h = width * 7 / 5;
    final card = Stack(clipBehavior: Clip.none, children: [
      LorcanaCardView(card: g.card(id), width: width),
      if (o.damage > 0)
        Positioned(
          right: 2,
          top: h * 0.4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: t.danger, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white70)),
            child: Text('${o.damage}', style: t.style(13, weight: FontWeight.w900, color: Colors.white)),
          ),
        ),
      if (c.type == CardType.character && !o.dry)
        Positioned(left: 2, top: 2, child: Tooltip(message: 'Drying: can’t quest or challenge this turn', child: Icon(Icons.water_drop_outlined, size: width * 0.2, color: Colors.white, shadows: const [Shadow(blurRadius: 3)]))),
    ]);
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: o.exerted ? 1 : 0),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, v, child) => SizedBox(
          width: width + (h - width) * v,
          height: h + (width - h) * v,
          child: Center(child: OverflowBox(maxWidth: width, maxHeight: h, child: Transform.rotate(angle: math.pi / 2 * v, child: child))),
        ),
        child: card,
      ),
    );
  }
}

class _Hand extends StatelessWidget {
  const _Hand({required this.session, required this.cardWidth, required this.onCard});
  final LorcanaSession session;
  final double cardWidth;
  final void Function(int id) onCard;

  @override
  Widget build(BuildContext context) {
    final g = session.match;
    final ids = g.state.player(session.localSeat).hand;
    final playable = session.isLocalTurn && g.pending == null ? {for (final m in g.legalMoves()) if (m is PlayMove || m is InkMove) (m as dynamic).card as int} : const <int>{};
    final t = GameTheme.of(context);
    return SizedBox(
      height: cardWidth * 7 / 5 + 10,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), children: [
        for (final id in ids)
          Padding(
            key: ValueKey(id),
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => onCard(id),
              child: DecoratedBox(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), boxShadow: playable.contains(id) ? [BoxShadow(color: t.ok.withValues(alpha: 0.7), blurRadius: 8)] : null),
                child: LorcanaCardView(card: g.card(id), width: cardWidth),
              ),
            ),
          ),
      ]),
    );
  }
}

class _PromptBar extends StatelessWidget {
  const _PromptBar({required this.session, required this.onDecide});
  final LorcanaSession session;
  final VoidCallback onDecide;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = session.match;
    final d = g.pending?.decision;
    String line;
    final buttons = <Widget>[];
    if (g.over) {
      line = 'The game is over.';
    } else if (d != null && d.player == session.localSeat) {
      line = d.prompt;
      buttons.add(Expanded(child: ThemedButton('Choose', icon: Icons.touch_app, tall: true, onPressed: onDecide)));
    } else if (d != null) {
      line = 'Waiting for ${g.state.player(d.player).name}: ${d.prompt}';
    } else if (session.isLocalTurn) {
      line = 'Your turn: ink a card, play cards, quest or challenge. Tap a card to see what it can do.';
      buttons.add(Expanded(child: ThemedButton('End turn', icon: Icons.skip_next, tall: true, onPressed: () => session.perform(EndTurnMove(session.localSeat)))));
    } else {
      line = session.isLinked ? 'Waiting for ${g.state.player(g.state.active).name}…' : '${g.state.player(g.state.active).name}’s turn.';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(color: t.panel.withValues(alpha: 0.95), border: Border(top: BorderSide(color: t.accent, width: 2))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (session.notice != null) Text(session.notice!, style: t.style(12, color: t.highlight)),
        if (session.lastError != null) Text(session.lastError!, style: t.style(13, weight: FontWeight.w700, color: t.danger)),
        Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(line, style: t.style(14, weight: FontWeight.w600), maxLines: 3, overflow: TextOverflow.ellipsis)),
        if (buttons.isNotEmpty) Row(children: buttons),
      ]),
    );
  }
}

/// Answers a decision: pick cards, yes/no, an option, or confirm an order.
class _DecisionDialog extends StatefulWidget {
  const _DecisionDialog({required this.session, required this.decision});
  final LorcanaSession session;
  final Decision decision;
  @override
  State<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends State<_DecisionDialog> {
  final picked = <int>[];

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final d = widget.decision;
    final g = widget.session.match;
    String labelOf(int i, int option) => i < d.labels.length ? d.labels[i] : (g.state.objOrNull(option) != null ? g.card(option).fullName : '$option');
    switch (d.kind) {
      case DecisionKind.yesNo:
        return AlertDialog(title: Text(d.prompt), actions: [
          TextButton(onPressed: () => Navigator.pop(context, const [0]), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, const [1]), child: const Text('Yes')),
        ]);
      case DecisionKind.option:
        return SimpleDialog(title: Text(d.prompt), children: [
          for (var i = 0; i < d.labels.length; i++) SimpleDialogOption(onPressed: () => Navigator.pop(context, [i]), child: Text(d.labels[i])),
        ]);
      case DecisionKind.order:
        return AlertDialog(
          title: Text(d.prompt),
          content: Column(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < d.options.length; i++) Text('${i + 1}. ${labelOf(i, d.options[i])}')]),
          actions: [TextButton(onPressed: () => Navigator.pop(context, List.of(d.options)), child: const Text('OK'))],
        );
      case DecisionKind.cards:
        final ok = picked.length >= d.min && picked.length <= d.max;
        return AlertDialog(
          title: Text(d.prompt),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (var i = 0; i < d.options.length; i++)
                  Builder(builder: (context) {
                    final id = d.options[i];
                    final on = picked.contains(id);
                    final isCard = g.state.objOrNull(id) != null;
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (on) {
                          picked.remove(id);
                        } else {
                          if (picked.length == d.max) picked.removeAt(0);
                          picked.add(id);
                        }
                      }),
                      child: Container(
                        decoration: BoxDecoration(border: Border.all(color: on ? t.highlight : Colors.transparent, width: 3), borderRadius: BorderRadius.circular(8)),
                        child: isCard ? LorcanaCardView(card: g.card(id), width: 96) : Padding(padding: const EdgeInsets.all(12), child: Text(labelOf(i, id))),
                      ),
                    );
                  }),
              ]),
            ),
          ),
          actions: [
            Text('${picked.length} chosen (${d.min == d.max ? d.min : '${d.min}–${d.max}'})', style: t.small),
            TextButton(onPressed: ok ? () => Navigator.pop(context, List.of(picked)) : null, child: const Text('Confirm')),
          ],
        );
    }
  }
}

class _GameOver extends StatelessWidget {
  const _GameOver({required this.session});
  final LorcanaSession session;
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
            child: ThemedPanel(
              title: won ? 'Victory' : (st.winner == null ? 'Draw' : 'Defeat'),
              color: won ? t.ok : t.danger,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text([for (final p in st.players) '${p.name}: ${p.lore} lore'].join('\n'), style: t.body),
                const SizedBox(height: 12),
                ThemedButton('Back', tall: true, onPressed: () {
                  LorcanaStore.shared.endSession();
                  Navigator.of(context).pop();
                }),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
