import 'dart:math' as math;

import 'package:flutter/material.dart' hide Ink;
import 'package:lorcana/lorcana.dart';
import 'package:tcg_app/tcg_app.dart';

import 'lorcana_card.dart';
import 'lorcana_playable.dart';
import 'lorcana_session.dart';
import 'lorcana_store.dart';
import 'lorcana_theme.dart';

/// The Lorcana table: the opponent's lore and play area on top, yours below, your hand and what
/// to do now at the bottom. Everything you can do this moment glows and carries a badge (worked
/// out from the engine's legal moves); tap a card to do it, long-press to read it.
class LorcanaTable extends StatefulWidget {
  const LorcanaTable({super.key});
  @override
  State<LorcanaTable> createState() => _LorcanaTableState();
}

/// Choosing what a challenge, a move, a song or a shift is aimed at.
class _Aim {
  _Aim(this.source, this.kind, this.targets);
  final CardId source;
  final CardAction kind;
  final Map<CardId, LMove> targets;

  String get prompt => switch (kind) {
        CardAction.challenge => 'Choose an exerted character or location to challenge',
        CardAction.move => 'Choose a location to move to',
        CardAction.sing => 'Choose who sings this song',
        CardAction.shift => 'Choose the character to shift onto',
        _ => 'Choose a target',
      };
}

class _LorcanaTableState extends State<LorcanaTable> {
  bool _dialogOpen = false;
  _Aim? _aim;
  Object? _playableKey;
  Playable? _playable;

  /// What the local player can do now; computed once per change of the match.
  Playable _playableFor(LorcanaSession s) {
    final g = s.match;
    final key = (g.actions.length, s.localSeat, s.resets, s.isLocalTurn, g.pending == null);
    if (key != _playableKey || _playable == null) {
      _playableKey = key;
      _playable = s.isLocalTurn ? playableActions(g, s.localSeat) : Playable.none(s.localSeat);
      if (_aim != null && !_playable!.canAct(_aim!.source)) _aim = null;
    }
    return _playable!;
  }

  @override
  Widget build(BuildContext context) {
    final s = LorcanaStore.shared.session;
    if (s == null) return const LorcanaScope(child: Scaffold(body: Center(child: Text('No game'))));
    return LorcanaScope(
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          _maybeAsk(context, s);
          final me = s.localSeat, opp = s.opponentSeat;
          final pl = _playableFor(s);
          final view = _TableView(session: s, playable: pl, aim: _aim, onTap: (id) => _tapCard(context, s, pl, id), onLongPress: (id) => _showCard(context, s, pl, id));
          return Scaffold(
            backgroundColor: enchantedTheme.bg,
            body: Stack(children: [
              const Positioned.fill(child: EnchantedBackdrop()),
              SafeArea(
                child: LayoutBuilder(builder: (context, box) {
                  final cardW = math.min(112.0, math.max(56.0, box.maxWidth / 7.2));
                  final handW = math.min(100.0, math.max(72.0, box.maxWidth / 5.4));
                  return Column(children: [
                    _TopBar(session: s),
                    _PlayerStrip(session: s, player: opp, onCard: (id) => _showCard(context, s, pl, id)),
                    Expanded(child: _PlayArea(view: view, player: opp, cardWidth: cardW)),
                    const _StoryDivider(),
                    Expanded(child: _PlayArea(view: view, player: me, cardWidth: cardW)),
                    _PlayerStrip(session: s, player: me, onCard: (id) => _showCard(context, s, pl, id)),
                    _Hand(view: view, cardWidth: handW),
                    _PromptBar(session: s, playable: pl, aim: _aim, onDecide: () => _ask(context, s), onCancelAim: () => setState(() => _aim = null)),
                  ]);
                }),
              ),
              if (s.state.over) _GameOver(session: s),
            ]),
          );
        },
      ),
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
    final answer = await showDialog<List<int>>(context: context, barrierDismissible: false, builder: (_) => LorcanaScope(child: _DecisionDialog(session: s, decision: d)));
    _dialogOpen = false;
    if (answer != null) s.perform(AnswerMove(s.localSeat, answer));
  }

  void _perform(LorcanaSession s, LMove m) {
    setState(() => _aim = null);
    s.perform(m);
  }

  /// One tap: picks the target of a challenge/move/song/shift being aimed; a character whose
  /// only move is to quest quests; otherwise the card opens with a button for each thing it can
  /// do.
  void _tapCard(BuildContext context, LorcanaSession s, Playable pl, CardId id) {
    final aim = _aim;
    if (aim != null) {
      final m = aim.targets[id];
      if (m != null) return _perform(s, m);
      setState(() => _aim = null);
      if (id == aim.source) return;
    }
    final options = _options(s.match, pl, id);
    final inPlay = s.match.state.obj(id).zone == Place.play && s.match.state.obj(id).owner == s.localSeat;
    // Questing is the one thing a single tap does by itself; an ability, a move or a challenge
    // shows the card first, so nothing costly happens by accident.
    if (options.length == 1 && inPlay && options.single.kind == CardAction.quest) return _choose(s, options.single);
    _showCard(context, s, pl, id);
  }

  void _choose(LorcanaSession s, _Option o) {
    if (o.move != null) return _perform(s, o.move!);
    setState(() => _aim = o.aim);
  }

  /// The things [id] can do, as buttons: one per move, with the moves that need a target folded
  /// into one "Challenge…" that then asks for it.
  List<_Option> _options(Game g, Playable pl, CardId id) {
    final out = <_Option>[];
    final aimed = <CardAction>{};
    for (final m in pl.movesOf(id)) {
      final kind = Playable.actionOf(m);
      final targets = pl.targetsOf(id, kind);
      if (Playable.targetOf(m) != null && targets.length > 1) {
        if (aimed.add(kind)) out.add(_Option(_aimLabel(g, id, kind), kind, aim: _Aim(id, kind, targets)));
      } else {
        out.add(_Option(_label(g, m, id), kind, move: m));
      }
    }
    // The obvious thing first: play, quest, challenge…; ink last (ties keep the engine's order).
    final order = [for (var i = 0; i < out.length; i++) i]..sort((a, b) {
        final k = _order(out[a].kind) - _order(out[b].kind);
        return k != 0 ? k : a - b;
      });
    return [for (final i in order) out[i]];
  }

  static int _order(CardAction a) => switch (a) {
        CardAction.play => 0,
        CardAction.shift => 1,
        CardAction.sing => 2,
        CardAction.quest => 3,
        CardAction.challenge => 4,
        CardAction.move => 5,
        CardAction.ability => 6,
        CardAction.ink => 7,
      };

  static String _aimLabel(Game g, CardId id, CardAction kind) => switch (kind) {
        CardAction.challenge => 'Challenge…',
        CardAction.move => 'Move to a location…',
        CardAction.sing => 'Sing it (choose a singer)…',
        CardAction.shift => 'Shift onto…',
        _ => 'Choose…',
      };

  static String _label(Game g, LMove m, CardId id) {
    String name(int x) => g.card(x).fullName;
    return switch (m) {
      InkMove() => 'Put in your inkwell',
      PlayMove(:final mode, :final onto, :final onto2, :final singers) => switch (mode) {
          PlayMode.ink when g.state.obj(m.card).zone != Place.hand => 'Play ${name(m.card)} (${g.playCost(m.seat, m.card)} ink)',
          PlayMode.ink => 'Play (${g.playCost(m.seat, m.card)} ink)',
          PlayMode.shift when onto2 != null => 'Shift onto ${name(onto!)} and ${name(onto2)}',
          PlayMode.shift when g.state.obj(m.card).zone != Place.hand => 'Shift ${name(m.card)} onto ${name(onto!)}',
          PlayMode.shift => 'Shift onto ${name(onto!)}',
          PlayMode.sing => 'Sing it with ${singers.map(name).join(' and ')} (free)',
        },
      QuestMove(:final card) => 'Quest  +${g.chars(card).loreAtLeast0} lore',
      ChallengeMove(:final target) => 'Challenge ${name(target)}',
      MoveMove(:final location) => 'Move to ${name(location)}',
      ActivateMove(:final card, :final index) => 'Use: ${g.abilitiesOf(card)[index].text}',
      _ => m.toString(),
    };
  }

  /// The card, large, with a button for each thing it can do now.
  void _showCard(BuildContext context, LorcanaSession s, Playable pl, CardId id) {
    final g = s.match;
    final options = _options(g, pl, id);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => LorcanaScope(
        child: Builder(builder: (sheet) {
          final t = GameTheme.of(sheet);
          final size = MediaQuery.of(sheet).size;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: size.height * 0.9),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: t.accent.withValues(alpha: 0.35), blurRadius: 24)]),
                      child: LorcanaCardView(card: g.card(id), width: math.min(250, math.min(size.width * 0.62, size.height * 0.38))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (options.isEmpty)
                    Text(
                      !s.isLocalTurn ? 'Not your turn.' : (g.state.obj(id).owner == s.localSeat ? 'Nothing to do with this card right now.' : 'An opposing card.'),
                      textAlign: TextAlign.center,
                      style: t.style(14, color: t.muted),
                    ),
                  for (final o in options)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: GoldButton(o.label, icon: actionIcon(o.kind), color: o.kind == CardAction.ink ? const Color(0xFF3E6FD8) : null, onPressed: () {
                        Navigator.pop(sheet);
                        _choose(s, o);
                      }),
                    ),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Option {
  _Option(this.label, this.kind, {this.move, this.aim});
  final String label;
  final CardAction kind;
  final LMove? move;
  final _Aim? aim;
}

IconData actionIcon(CardAction a) => switch (a) {
      CardAction.play => Icons.auto_awesome,
      CardAction.shift => Icons.layers,
      CardAction.sing => Icons.music_note,
      CardAction.ink => Icons.water_drop,
      CardAction.quest => Icons.explore,
      CardAction.challenge => Icons.flash_on,
      CardAction.move => Icons.directions_walk,
      CardAction.ability => Icons.auto_fix_high,
    };

Color actionColor(CardAction a) => switch (a) {
      CardAction.play || CardAction.shift => const Color(0xFFEBC66F),
      CardAction.sing => const Color(0xFFC79BFF),
      CardAction.ink => const Color(0xFF5AA2FF),
      CardAction.quest => const Color(0xFF79F0B4),
      CardAction.challenge => const Color(0xFFFF6B83),
      CardAction.move => const Color(0xFF7FDDF0),
      CardAction.ability => const Color(0xFFFFA45C),
    };

/// What every card on the table needs to draw itself: the session, what can be done, the aim.
class _TableView {
  _TableView({required this.session, required this.playable, required this.aim, required this.onTap, required this.onLongPress});
  final LorcanaSession session;
  final Playable playable;
  final _Aim? aim;
  final void Function(CardId) onTap, onLongPress;

  /// Cards the opponent just used (to flash them, so you can follow the computer's turn).
  late final Set<CardId> justUsed = {
    for (final e in session.recent)
      if (e.card != null && e.player != session.localSeat && e.kind != 'draw') e.card!,
  };
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.session});
  final LorcanaSession session;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final st = session.state;
    final me = st.player(session.localSeat), opp = st.player(session.opponentSeat);
    return SizedBox(
      height: 44,
      child: Row(children: [
        IconButton(icon: Icon(Icons.close, color: t.accent), tooltip: 'Leave the table', onPressed: () => Navigator.of(context).maybePop()),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              session.isLinked ? '${session.link?.status ?? ''} · turn ${st.turn}' : 'Turn ${st.turn}',
              style: t.display(14, weight: FontWeight.w700, color: t.accent),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text('Race to 20 lore · you ${me.lore} — ${opp.lore} ${opp.name}', style: t.style(12, color: t.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        IconButton(icon: Icon(Icons.auto_stories, color: t.accent), tooltip: 'Game log', onPressed: () => _showLog(context, st)),
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
      builder: (c) => LorcanaScope(
        child: Builder(
          builder: (c) => ListView(padding: const EdgeInsets.all(14), children: [
            for (final e in st.log.reversed.take(200)) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(e.text, style: GameTheme.of(c).style(13))),
          ]),
        ),
      ),
    );
  }
}

/// A gold rule between the two halves of the table.
class _StoryDivider extends StatelessWidget {
  const _StoryDivider();
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 14,
        child: CustomPaint(painter: _DividerPainter(), size: const Size(double.infinity, 14)),
      );
}

class _DividerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final w = size.width;
    final p = Paint()
      ..shader = const LinearGradient(colors: [Color(0x00EBC66F), Color(0xFFEBC66F), Color(0x00EBC66F)]).createShader(Offset.zero & size)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(w * 0.04, y), Offset(w * 0.96, y), p);
    final c = Offset(w / 2, y);
    final d = Path()
      ..moveTo(c.dx, c.dy - 6)
      ..lineTo(c.dx + 6, c.dy)
      ..lineTo(c.dx, c.dy + 6)
      ..lineTo(c.dx - 6, c.dy)
      ..close();
    canvas.drawPath(d, Paint()..color = const Color(0xFFEBC66F));
    canvas.drawPath(d, Paint()
      ..color = const Color(0xFF1B1035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_DividerPainter old) => false;
}

/// One player's line: lore toward 20 (big), ink, hand, deck and discard (tap it to see the
/// cards), and the top of the deck when it's faceup.
class _PlayerStrip extends StatelessWidget {
  const _PlayerStrip({required this.session, required this.player, required this.onCard});
  final LorcanaSession session;
  final int player;
  final void Function(int id) onCard;

  void _showDiscard(BuildContext context, Game g, List<int> ids) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => LorcanaScope(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final id in ids.reversed)
                GestureDetector(
                  onTap: () {
                    Navigator.pop(sheet);
                    onCard(id);
                  },
                  child: LorcanaCardView(card: g.card(id), width: 84),
                ),
            ]),
          ),
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
    final mine = player == session.localSeat;
    Widget chip(IconData icon, String n, String tip, {Color? color}) => Tooltip(
          message: tip,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: color ?? t.muted), const SizedBox(width: 2), Text(n, style: t.style(13, color: color))]),
          ),
        );
    final ready = g.inkReady(player);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: GildedPanel(
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        glow: active ? (mine ? const Color(0xFFEBC66F) : const Color(0xFFB79CFF)) : null,
        child: Row(children: [
          _LoreGem(lore: p.lore, color: mine ? t.accent : t.accent2),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                if (active) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.auto_awesome, size: 14, color: mine ? t.accent : t.accent2)),
                Flexible(child: Text(mine && p.name != 'You' ? '${p.name} (you)' : p.name, style: t.display(14, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 3),
              _LoreTrack(lore: p.lore, color: mine ? t.accent : t.accent2),
            ]),
          ),
          const SizedBox(width: 6),
          chip(Icons.water_drop, '$ready/${p.inkwell.length}', 'Ink ready / in inkwell', color: ready > 0 ? const Color(0xFF8CC2FF) : null),
          chip(Icons.style, '${p.hand.length}', 'Cards in hand'),
          // "Each player plays with the top card of their deck face up" (Merlin's Cottage).
          chip(Icons.layers, '${p.deck.length}', g.faceUpTop(player) == null ? 'Deck' : 'Deck · top card: ${g.faceUpTop(player)}'),
          if (p.deck.isNotEmpty && g.topCardFaceUp(player)) chip(Icons.visibility, g.card(p.deck.first).name, 'Top of the deck (faceup)'),
          GestureDetector(onTap: p.discard.isEmpty ? null : () => _showDiscard(context, g, p.discard), child: chip(Icons.delete_outline, '${p.discard.length}', 'Discard (tap to look)')),
        ]),
      ),
    );
  }
}

/// The lore count in a faceted gem, popping when it changes.
class _LoreGem extends StatelessWidget {
  const _LoreGem({required this.lore, required this.color});
  final int lore;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return SizedBox(
      width: 42,
      height: 42,
      child: CustomPaint(
        painter: _GemPainter(color),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            transitionBuilder: (c, a) => ScaleTransition(scale: a.drive(Tween(begin: 2.0, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack))), child: c),
            child: Text('$lore', key: ValueKey(lore), style: t.display(19, weight: FontWeight.w800, color: const Color(0xFF1B1035))),
          ),
        ),
      ),
    );
  }
}

class _GemPainter extends CustomPainter {
  _GemPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w, h * 0.38)
      ..lineTo(w * 0.8, h)
      ..lineTo(w * 0.2, h)
      ..lineTo(0, h * 0.38)
      ..close();
    canvas.drawShadow(path, color, 6, false);
    canvas.drawPath(path, Paint()..shader = LinearGradient(colors: [Color.lerp(color, Colors.white, 0.55)!, color, Color.lerp(color, Colors.black, 0.2)!], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(Offset.zero & size));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.8));
  }

  @override
  bool shouldRepaint(_GemPainter old) => old.color != color;
}

/// Twenty small diamonds, filled up to the lore count (CR 1.11: 20 lore wins).
class _LoreTrack extends StatelessWidget {
  const _LoreTrack({required this.lore, required this.color});
  final int lore;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(height: 9, child: CustomPaint(painter: _TrackPainter(lore.clamp(0, 20), color), size: const Size(double.infinity, 9)));
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.lore, this.color);
  final int lore;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / 20;
    final r = math.min(step * 0.42, size.height / 2);
    for (var i = 0; i < 20; i++) {
      final c = Offset(step * (i + 0.5), size.height / 2);
      final d = Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r * 0.8, c.dy)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - r * 0.8, c.dy)
        ..close();
      canvas.drawPath(d, Paint()..color = i < lore ? color : Colors.white.withValues(alpha: 0.14));
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.lore != lore || old.color != color;
}

class _PlayArea extends StatelessWidget {
  const _PlayArea({required this.view, required this.player, required this.cardWidth});
  final _TableView view;
  final int player;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final g = view.session.match;
    final ids = g.state.player(player).play;
    return LayoutBuilder(builder: (context, box) {
      // A row of cards fits the height, badges included (more rows scroll).
      final w = math.max(44.0, math.min(cardWidth, (box.maxHeight - 18) / (1.4 + 0.1)));
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Center(
          child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final id in ids) _TableCard(key: ValueKey(id), view: view, id: id, width: w),
          ]),
        ),
      );
    });
  }
}

/// How a card on the table or in the hand should look now.
class _Look {
  _Look(this.actions, {required this.dim, required this.target, required this.flash, required this.aiming});
  final Set<CardAction> actions;

  /// It's your turn and this card of yours can't do anything (or something else is being aimed).
  final bool dim;

  /// It can be picked for the challenge, move, song or shift being aimed.
  final CardAction? target;
  final bool flash;

  /// It's the card being aimed from.
  final bool aiming;

  static _Look of(_TableView v, CardId id) {
    final s = v.session;
    final mine = s.match.state.obj(id).owner == s.localSeat;
    final aim = v.aim;
    // While aiming, only the possible targets are marked.
    final actions = aim == null ? v.playable.actionsOf(id) : const <CardAction>{};
    final target = aim != null && aim.targets.containsKey(id) ? aim.kind : null;
    final yourTurn = s.isLocalTurn && s.match.pending == null && !s.match.over;
    final dim = aim != null ? (target == null && aim.source != id) : (yourTurn && mine && actions.isEmpty);
    return _Look(actions, dim: dim, target: target, flash: v.justUsed.contains(id), aiming: aim?.source == id);
  }
}

/// A card's halo, its action badges and the flash when the opponent just used it.
class _CardDress extends StatelessWidget {
  const _CardDress({required this.look, required this.width, required this.child, this.questLore, this.dryMark = false});
  final _Look look;
  final double width;
  final Widget child;
  final int? questLore;
  final bool dryMark;

  @override
  Widget build(BuildContext context) {
    final h = width * 7 / 5;
    // Only a card that can do more than go into the inkwell glows; the inkwell has its badge.
    final glows = look.actions.any((a) => a != CardAction.ink);
    final glowColor = look.target != null ? actionColor(look.target!) : (look.aiming ? Colors.white : (glows ? actionColor(_main(look.actions)) : null));
    // On the web the card image is an HTML element: color filters and layers drawn over it
    // don't reliably reach it, but opacity does, so a card with nothing to do fades into the
    // night sky.
    final card = look.dim ? Opacity(opacity: 0.38, child: child) : child;
    final badges = [for (final a in CardAction.values) if (look.actions.contains(a) && look.target == null) a];
    return Stack(clipBehavior: Clip.none, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.07),
          boxShadow: [
            if (glowColor != null) BoxShadow(color: glowColor.withValues(alpha: 0.85), blurRadius: look.target != null ? 16 : 11, spreadRadius: look.target != null ? 3 : 1),
            if (glowColor == null) const BoxShadow(color: Color(0x88000000), blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        child: card,
      ),
      if (look.flash)
        Positioned.fill(
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 1, end: 0),
              duration: const Duration(milliseconds: 1600),
              builder: (context, v, _) => DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(width * 0.07),
                  border: Border.all(color: const Color(0xFFB79CFF).withValues(alpha: v), width: 3),
                  boxShadow: [BoxShadow(color: const Color(0xFFB79CFF).withValues(alpha: 0.9 * v), blurRadius: 22 * v, spreadRadius: 4 * v)],
                ),
              ),
            ),
          ),
        ),
      if (badges.isNotEmpty)
        Positioned(
          left: 0,
          right: 0,
          bottom: -width * 0.08,
          child: Wrap(alignment: WrapAlignment.center, spacing: 2, runSpacing: 2, children: [
            for (final a in badges) _Badge(action: a, size: (width * 0.24).clamp(17.0, 26.0), lore: a == CardAction.quest ? questLore : null),
          ]),
        ),
      if (look.target != null)
        Positioned(
          top: h * 0.32,
          left: 0,
          right: 0,
          child: Center(child: _Badge(action: look.target!, size: (width * 0.36).clamp(24.0, 36.0))),
        ),
      if (dryMark)
        Positioned(
          left: 2,
          top: 2,
          child: Tooltip(
            message: 'Drying: can’t quest or challenge this turn',
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: Color(0xAA1B1035), shape: BoxShape.circle),
              child: Icon(Icons.hourglass_bottom, size: (width * 0.16).clamp(12.0, 18.0), color: const Color(0xFFC3BBE6)),
            ),
          ),
        ),
    ]);
  }

  static CardAction _main(Set<CardAction> a) {
    for (final k in const [CardAction.play, CardAction.shift, CardAction.sing, CardAction.quest, CardAction.challenge, CardAction.ability, CardAction.move, CardAction.ink]) {
      if (a.contains(k)) return k;
    }
    return a.first;
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.action, required this.size, this.lore});
  final CardAction action;
  final double size;
  final int? lore;
  @override
  Widget build(BuildContext context) {
    final c = actionColor(action);
    final label = switch (action) {
      CardAction.play => 'Can be played',
      CardAction.shift => 'Can shift',
      CardAction.sing => 'Can be sung',
      CardAction.ink => 'Can go in your inkwell',
      CardAction.quest => 'Can quest',
      CardAction.challenge => 'Can challenge',
      CardAction.move => 'Can move to a location',
      CardAction.ability => 'Has an ability to use',
    };
    return Tooltip(
      message: label,
      child: Container(
        height: size,
        constraints: BoxConstraints(minWidth: size),
        padding: EdgeInsets.symmetric(horizontal: lore == null ? 0 : size * 0.18),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1035),
          borderRadius: BorderRadius.circular(size / 2),
          border: Border.all(color: c, width: 1.6),
          boxShadow: [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 6)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(actionIcon(action), size: size * 0.62, color: c),
          if (lore != null) Text('+$lore', style: enchantedTheme.style(size * 0.5, weight: FontWeight.w800, color: c)),
        ]),
      ),
    );
  }
}

/// A card in play: turned sideways when exerted, with damage, a mark while it's drying, and its
/// badges.
class _TableCard extends StatelessWidget {
  const _TableCard({super.key, required this.view, required this.id, required this.width});
  final _TableView view;
  final int id;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = view.session.match;
    final o = g.state.obj(id);
    final c = g.chars(id);
    final h = width * 7 / 5;
    final look = _Look.of(view, id);
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
    ]);
    final turned = TweenAnimationBuilder<double>(
      tween: Tween(end: o.exerted ? 1 : 0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => SizedBox(
        width: width + (h - width) * v,
        height: h + (width - h) * v,
        child: Center(child: OverflowBox(maxWidth: width, maxHeight: h, child: Transform.rotate(angle: math.pi / 2 * v, child: child))),
      ),
      child: card,
    );
    return _Hoverable(
      enabled: look.actions.isNotEmpty || look.target != null,
      onTap: () => view.onTap(id),
      onLongPress: () => view.onLongPress(id),
      child: _Arrive(
        child: Padding(
          padding: EdgeInsets.only(bottom: width * 0.08),
          child: _CardDress(look: look, width: o.exerted ? h : width, questLore: c.loreAtLeast0, dryMark: c.type == CardType.character && !o.dry, child: turned),
        ),
      ),
    );
  }
}

/// A card arriving on the table grows in.
class _Arrive extends StatelessWidget {
  const _Arrive({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.6, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
        builder: (context, v, child) => Opacity(opacity: ((v - 0.6) / 0.4).clamp(0, 1), child: Transform.scale(scale: v, child: child)),
        child: child,
      );
}

/// Lifts under the mouse when it can do something; taps and long-presses.
class _Hoverable extends StatefulWidget {
  const _Hoverable({required this.child, required this.onTap, required this.onLongPress, this.enabled = true, this.lift = 0});
  final Widget child;
  final VoidCallback onTap, onLongPress;
  final bool enabled;

  /// Raised this much already (playable hand cards).
  final double lift;
  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final up = widget.lift + (_hover && widget.enabled ? 6 : 0);
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTap: widget.onLongPress,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: up),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          builder: (context, v, child) => Transform.translate(offset: Offset(0, -v), child: child),
          child: widget.child,
        ),
      ),
    );
  }
}

class _Hand extends StatelessWidget {
  const _Hand({required this.view, required this.cardWidth});
  final _TableView view;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final s = view.session;
    final g = s.match;
    final ids = g.state.player(s.localSeat).hand;
    final h = cardWidth * 7 / 5;
    return SizedBox(
      height: h + 26 + cardWidth * 0.1,
      child: ListView(scrollDirection: Axis.horizontal, padding: EdgeInsets.fromLTRB(10, 14, 10, 4 + cardWidth * 0.1), children: [
        for (final id in ids)
          Padding(
            key: ValueKey(id),
            padding: const EdgeInsets.only(right: 8),
            child: Builder(builder: (context) {
              final look = _Look.of(view, id);
              final playable = look.actions.any((a) => a != CardAction.ink);
              return _Hoverable(
                enabled: look.actions.isNotEmpty || look.target != null,
                lift: playable ? 10 : 0,
                onTap: () => view.onTap(id),
                onLongPress: () => view.onLongPress(id),
                child: _CardDress(look: look, width: cardWidth, child: LorcanaCardView(card: g.card(id), width: cardWidth)),
              );
            }),
          ),
      ]),
    );
  }
}

class _PromptBar extends StatelessWidget {
  const _PromptBar({required this.session, required this.playable, required this.aim, required this.onDecide, required this.onCancelAim});
  final LorcanaSession session;
  final Playable playable;
  final _Aim? aim;
  final VoidCallback onDecide, onCancelAim;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = session.match;
    final d = g.pending?.decision;
    String line;
    String? detail;
    Widget? button;
    if (g.over) {
      line = 'The story is told.';
    } else if (aim != null) {
      line = aim!.prompt;
      detail = 'The glowing cards can be chosen.';
      button = GoldButton('Cancel', icon: Icons.close, color: const Color(0xFF4A3F8C), onPressed: onCancelAim);
    } else if (d != null && d.player == session.localSeat) {
      line = d.prompt;
      button = GoldButton('Choose', icon: Icons.touch_app, pulse: true, onPressed: onDecide);
    } else if (d != null) {
      line = 'Waiting for ${g.state.player(d.player).name}: ${d.prompt}';
    } else if (session.isLocalTurn) {
      line = 'Your turn';
      detail = playableSummary(playable);
      button = GoldButton('End turn', icon: Icons.nights_stay, pulse: playable.usefulCount == 0, onPressed: () => session.perform(EndTurnMove(session.localSeat)));
    } else {
      line = session.isLinked ? 'Waiting for ${g.state.player(g.state.active).name}…' : (session.thinking ? '${g.state.player(g.state.active).name} is thinking…' : '${g.state.player(g.state.active).name}’s turn');
    }
    final news = _opponentNews(session);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xEE1C1950), Color(0xF2100E30)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        border: Border(top: BorderSide(color: Color(0xFFB8862F), width: 1.4)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (session.notice != null) Text(session.notice!, style: t.style(12, color: t.highlight)),
        if (session.lastError != null) Text(session.lastError!, style: t.style(13, weight: FontWeight.w700, color: t.danger)),
        if (news.isNotEmpty) _News(lines: news, live: !session.isLocalTurn, name: g.state.player(session.opponentSeat).name),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              // The display face (all capitals) only for short lines; prompts read in the body face.
              Text(line, style: line.length <= 28 ? t.display(17, weight: FontWeight.w700, color: session.isLocalTurn ? t.accent : t.text) : t.style(15, weight: FontWeight.w700, color: t.highlight), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (detail != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(detail, style: t.style(13, weight: FontWeight.w500, color: t.muted), maxLines: 3, overflow: TextOverflow.ellipsis)),
            ]),
          ),
          if (button != null) ...[const SizedBox(width: 10), ConstrainedBox(constraints: const BoxConstraints(minWidth: 120, maxWidth: 190), child: button)],
        ]),
      ]),
    );
  }

  /// What the opponent did on their latest turn (or is doing now), newest last.
  static List<LogEntry> _opponentNews(LorcanaSession s) {
    final opp = s.opponentSeat;
    if (s.mode == SessionMode.hotseat) return const [];
    const kinds = {'play', 'quest', 'challenge', 'banish', 'ink', 'move', 'ability', 'sing', 'shift'};
    final out = <LogEntry>[];
    final log = s.state.log;
    for (var i = log.length - 1; i >= 0 && out.length < 4; i--) {
      final e = log[i];
      if (e.kind == 'turn') {
        if (e.player == opp) break;
        continue;
      }
      if (e.player == opp && kinds.contains(e.kind)) out.add(e);
    }
    return out.reversed.toList();
  }
}

/// A few lines on what the opponent did, so the computer's turn can be followed.
class _News extends StatelessWidget {
  const _News({required this.lines, required this.live, required this.name});
  final List<LogEntry> lines;
  final bool live;
  final String name;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: const Color(0x33B79CFF), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0x66B79CFF))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(live ? '$name is playing:' : '$name’s last turn:', style: t.style(12, weight: FontWeight.w700, color: t.accent2)),
          for (final e in lines)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text('• ${e.text}', key: ValueKey(e.text), style: t.style(12, color: t.text), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ]),
      ),
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
    final source = d.source == null || g.state.objOrNull(d.source!) == null ? null : g.card(d.source!);
    final title = Row(children: [
      if (source != null) Padding(padding: const EdgeInsets.only(right: 10), child: LorcanaCardView(card: source, width: 46)),
      Expanded(child: Text(d.prompt, style: t.style(17, weight: FontWeight.w700, color: t.highlight))),
    ]);
    switch (d.kind) {
      case DecisionKind.yesNo:
        return AlertDialog(title: title, actions: [
          TextButton(onPressed: () => Navigator.pop(context, const [0]), child: const Text('No')),
          SizedBox(width: 120, child: GoldButton('Yes', onPressed: () => Navigator.pop(context, const [1]))),
        ]);
      case DecisionKind.option:
        return AlertDialog(
          title: title,
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < d.labels.length; i++) Padding(padding: const EdgeInsets.only(top: 8), child: GoldButton(d.labels[i], onPressed: () => Navigator.pop(context, [i]))),
          ]),
        );
      case DecisionKind.order:
        return AlertDialog(
          title: title,
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [for (var i = 0; i < d.options.length; i++) Text('${i + 1}. ${labelOf(i, d.options[i])}', style: t.body)]),
          actions: [SizedBox(width: 120, child: GoldButton('OK', onPressed: () => Navigator.pop(context, List.of(d.options))))],
        );
      case DecisionKind.cards:
        final ok = picked.length >= d.min && picked.length <= d.max;
        return AlertDialog(
          title: title,
          content: SizedBox(
            width: 540,
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
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          border: Border.all(color: on ? t.highlight : Colors.transparent, width: 3),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: on ? [BoxShadow(color: t.highlight.withValues(alpha: 0.6), blurRadius: 12)] : null,
                        ),
                        child: isCard ? LorcanaCardView(card: g.card(id), width: 96) : Padding(padding: const EdgeInsets.all(12), child: Text(labelOf(i, id), style: t.body)),
                      ),
                    );
                  }),
              ]),
            ),
          ),
          actions: [
            Text('${picked.length} chosen (${d.min == d.max ? d.min : '${d.min}–${d.max}'})', style: t.small),
            SizedBox(width: 130, child: GoldButton('Confirm', onPressed: ok ? () => Navigator.pop(context, List.of(picked)) : null)),
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
            child: GildedPanel(
              glow: won ? t.accent : t.accent2,
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                EnchantedTitle(won ? 'Victory!' : (st.winner == null ? 'A draw' : 'The story ends'), size: 30, align: TextAlign.center),
                const SizedBox(height: 10),
                Text([for (final p in st.players) '${p.name}: ${p.lore} lore'].join('\n'), style: t.body, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                GoldButton('Back', onPressed: () {
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
