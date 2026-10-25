import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pokemon/pokemon.dart';
import 'package:tcg_app/tcg_app.dart';

import 'pokemon_card.dart';
import 'pokemon_session.dart';
import 'pokemon_store.dart';
import 'pokemon_theme.dart';

/// The Pokémon table: the opponent's Bench and Active Pokémon on top, yours below, then your
/// hand and what you can do. Cards with something to do glow; tap one for its moves and text.
class PokemonTable extends StatefulWidget {
  const PokemonTable({super.key});
  @override
  State<PokemonTable> createState() => _PokemonTableState();
}

class _PokemonTableState extends State<PokemonTable> {
  bool _dialogOpen = false;

  @override
  Widget build(BuildContext context) {
    final s = PokemonStore.shared.session;
    if (s == null) return const Scaffold(body: Center(child: Text('No game')));
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final t = GameTheme.of(context);
        _maybeAsk(context, s);
        final me = s.localSeat, opp = s.opponentSeat;
        final acts = _Actions.of(s);
        void onCard(int id) => _cardSheet(context, s, id, acts);
        return Scaffold(
          backgroundColor: t.bg,
          body: Stack(
            children: [
              const Positioned.fill(child: MeadowBackdrop()),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      children: [
                        _TopBar(session: s),
                        _SideStrip(session: s, player: opp, onCard: onCard),
                        Expanded(
                          child: _Field(session: s, player: opp, top: true, acts: acts, onCard: onCard),
                        ),
                        _MiddleLine(session: s, onCard: onCard),
                        Expanded(
                          child: _Field(session: s, player: me, top: false, acts: acts, onCard: onCard),
                        ),
                        _SideStrip(session: s, player: me, onCard: onCard),
                        _Hand(session: s, acts: acts, onCard: onCard),
                        _ActionBar(session: s, acts: acts, onDecide: () => _ask(context, s), onRetreat: () => _retreatSheet(context, s, acts)),
                      ],
                    ),
                  ),
                ),
              ),
              if (s.state.over) _GameOver(session: s, onRematch: () => setState(() {})),
            ],
          ),
        );
      },
    );
  }

  /// Opens the choice dialog when it's the local player's decision.
  void _maybeAsk(BuildContext context, PokemonSession s) {
    final d = s.match.pending?.decision;
    if (d == null || d.player != s.localSeat || _dialogOpen || s.isLinked && !s.isLocalTurn) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_dialogOpen && s.match.pending?.decision == d) _ask(context, s);
    });
  }

  Future<void> _ask(BuildContext context, PokemonSession s) async {
    final d = s.match.pending?.decision;
    if (d == null || d.player != s.localSeat || _dialogOpen) return;
    _dialogOpen = true;
    final answer = await showDialog<List<int>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => pokemonScope(PokemonDecisionDialog(session: s, decision: d)),
    );
    _dialogOpen = false;
    if (answer != null) {
      s.perform(AnswerMove(s.localSeat, answer));
    } else if (mounted) {
      setState(() {}); // "Look at the table": the bar's Choose button reopens it.
    }
  }

  void _cardSheet(BuildContext context, PokemonSession s, int id, _Actions acts) {
    final g = s.match;
    final moves = acts.forCard(id);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => pokemonScope(
        Builder(
          builder: (sheet) {
            final t = GameTheme.of(sheet);
            final card = g.card(id);
            final o = g.state.obj(id);
            final inPlay = o.zone == Place.active || o.zone == Place.bench;
            final w = math.min(250.0, MediaQuery.of(sheet).size.width * 0.42);
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.88),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final m in moves)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: ThemedButton(
                            _label(g, m, id),
                            icon: _icon(m),
                            onPressed: () {
                              Navigator.pop(sheet);
                              s.perform(m);
                            },
                          ),
                        ),
                      if (moves.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _nothingReason(s, g, id),
                            textAlign: TextAlign.center,
                            style: t.style(13, color: t.muted),
                          ),
                        ),
                      Wrap(
                        spacing: 14,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.start,
                        children: [
                          PokemonCardView(card: card, width: w, large: true),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 380),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PokemonCardText(card: card),
                                if (inPlay) ...[
                                  const Divider(height: 20),
                                  Text('In play: ${g.maxHp(id) - o.damage} of ${g.maxHp(id)} HP left', style: t.style(14, weight: FontWeight.w800)),
                                  if (o.energy.isNotEmpty) Text('Energy: ${[for (final e in o.energy) g.nameOf(e)].join(', ')}', style: t.style(13)),
                                  if (o.tool != null) Text('Tool: ${g.nameOf(o.tool!)}', style: t.style(13)),
                                  if (o.conds.isNotEmpty) Text('Special Conditions: ${o.conds.map(_condLabel).join(', ')}', style: t.style(13, color: t.danger)),
                                  if (o.under.isNotEmpty) Text('Evolved from: ${o.under.map(g.nameOf).join(' → ')}', style: t.small),
                                ],
                              ],
                            ),
                          ),
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

  void _retreatSheet(BuildContext context, PokemonSession s, _Actions acts) {
    final g = s.match;
    final options = [
      for (final m in acts.all)
        if (m is RetreatMove) m,
    ];
    final a = g.state.player(s.localSeat).active;
    showModalBottomSheet(
      context: context,
      builder: (sheet) => pokemonScope(
        Builder(
          builder: (sheet) {
            final t = GameTheme.of(sheet);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Retreat ${a == null ? '' : g.nameOf(a)}: discard ${a == null ? 0 : g.card(a).retreat} Energy and switch in a Benched Pokémon.', style: t.style(14, weight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in options)
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(sheet);
                              s.perform(m);
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PokemonCardView(card: g.card(m.to), width: 90),
                                Text(g.nameOf(m.to), style: t.style(12, weight: FontWeight.w700)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static String _nothingReason(PokemonSession s, Game g, int id) {
    if (g.state.over) return 'The game is over.';
    if (!s.isLocalTurn || g.pending != null) return 'Not your turn to act.';
    final o = g.state.obj(id);
    if (o.owner != s.localSeat) return 'Your opponent’s card.';
    final c = g.card(id);
    if (o.zone == Place.hand) {
      if (c.isEnergy && g.state.player(s.localSeat).energyAttached) return 'You already attached an Energy this turn.';
      if (c.isPokemon && !c.isBasicPokemon) {
        return g.isFirstTurn(s.localSeat) ? 'Pokémon can’t evolve on your first turn.' : 'Nothing in play it can evolve from right now (a Pokémon can’t evolve the turn it was played).';
      }
      if (c.trainer == TrainerKind.supporter && g.state.player(s.localSeat).supporterPlayed) return 'You already played a Supporter this turn.';
      return 'This card can’t be played right now.';
    }
    return 'Nothing to do with this card right now.';
  }
}

/// The local player's legal moves this moment, and which cards they involve (for the glow).
class _Actions {
  _Actions(this.all);
  final List<PMove> all;

  static _Actions of(PokemonSession s) {
    final g = s.match;
    if (!s.isLocalTurn || g.pending != null || g.state.over) return _Actions(const []);
    return _Actions(g.legalMoves());
  }

  /// Cards a move is played from (glow strongly) and the Pokémon it can go to.
  late final Set<int> sources = {
    for (final m in all)
      ?switch (m) {
        PlayBasicMove(:final card) || EvolveMove(:final card) || AttachEnergyMove(:final card) || TrainerMove(:final card) || AbilityMove(:final card) => card,
        _ => null,
      },
  };

  bool canAttack(int index) => all.any((m) => m is AttackMove && m.index == index);
  bool get canRetreat => all.any((m) => m is RetreatMove);

  /// The moves shown on [id]'s sheet.
  List<PMove> forCard(int id) => [
    for (final m in all)
      if (switch (m) {
        PlayBasicMove(:final card) || AbilityMove(:final card) => card == id,
        EvolveMove(:final card, :final target) || AttachEnergyMove(:final card, :final target) => card == id || target == id,
        TrainerMove(:final card, :final target) => card == id || target == id,
        RetreatMove(:final to) => to == id,
        _ => false,
      })
        m,
  ];
}

String _where(Game g, int id) => g.state.obj(id).zone == Place.active ? 'Active' : 'Bench';

String _label(Game g, PMove m, int id) {
  String n(int x) => '${g.nameOf(x)} (${_where(g, x)})';
  return switch (m) {
    PlayBasicMove() => 'Put onto your Bench',
    EvolveMove(:final card, :final target) => card == id ? 'Evolve ${n(target)}' : 'Evolve into ${g.nameOf(card)}',
    AttachEnergyMove(:final card, :final target) => card == id ? 'Attach to ${n(target)}' : 'Attach ${g.nameOf(card)}',
    TrainerMove(:final card, :final target) => target == null ? 'Play ${g.nameOf(card)}' : (card == id ? 'Attach to ${n(target)}' : 'Attach ${g.nameOf(card)}'),
    RetreatMove(:final to) => 'Retreat your Active, switching in ${g.nameOf(to)}',
    AbilityMove(:final card, :final index) => 'Use Ability: ${index < g.card(card).abilities.length ? g.card(card).abilities[index].name : 'Ability'}',
    AttackMove(:final index) => 'Attack: ${g.card(g.state.player(m.seat).active!).attacks[index].name}',
    _ => m.toString(),
  };
}

IconData _icon(PMove m) => switch (m) {
  PlayBasicMove() => Icons.add_circle,
  EvolveMove() => Icons.upgrade,
  AttachEnergyMove() => Icons.bolt,
  TrainerMove() => Icons.backpack,
  RetreatMove() => Icons.swap_vert,
  AbilityMove() => Icons.auto_awesome,
  AttackMove() => Icons.flash_on,
  _ => Icons.touch_app,
};

/// "2 Lightning + 1 Colorless" (or "free").
String _costText(List<PType> cost) {
  if (cost.isEmpty) return 'free';
  final order = <PType>[];
  for (final c in cost) {
    if (!order.contains(c)) order.add(c);
  }
  return [for (final c in order) '${cost.where((x) => x == c).length} ${c.label}'].join(' + ');
}

String _condLabel(Cond c) => switch (c) {
  Cond.asleep => 'Asleep',
  Cond.burned => 'Burned',
  Cond.confused => 'Confused',
  Cond.paralyzed => 'Paralyzed',
  Cond.poisoned => 'Poisoned',
};

String _condIcon(Cond c) => switch (c) {
  Cond.asleep => '💤',
  Cond.burned => '🔥',
  Cond.confused => '💫',
  Cond.paralyzed => '⚡',
  Cond.poisoned => '☠',
};

class _TopBar extends StatelessWidget {
  const _TopBar({required this.session});
  final PokemonSession session;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final st = session.state;
    final status = session.isLinked
        ? '${session.link?.status ?? ''} · turn ${st.turn}'
        : (st.phase == Phase.setup ? 'Setting up' : (session.thinking ? '${session.playerNames[session.opponentSeat]} is thinking…' : 'Turn ${st.turn} · ${st.player(st.active).name}'));
    return Container(
      height: 42,
      color: Colors.white.withValues(alpha: 0.75),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.close), tooltip: 'Leave the table', onPressed: () => Navigator.of(context).maybePop()),
          Expanded(
            child: Text(
              status,
              style: t.style(14, weight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(icon: const Icon(Icons.receipt_long), tooltip: 'Game log', onPressed: () => _showLog(context, st)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'concede') session.concede();
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'concede', child: Text('Concede'))],
          ),
        ],
      ),
    );
  }

  void _showLog(BuildContext context, GameState st) {
    showModalBottomSheet(
      context: context,
      builder: (c) => pokemonScope(
        Builder(
          builder: (c) => ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final e in st.log.reversed.take(300))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(e.text, style: GameTheme.of(c).style(13, weight: FontWeight.w500)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One player's line: Prize cards left, hand, deck and discard (tap it to look through).
class _SideStrip extends StatelessWidget {
  const _SideStrip({required this.session, required this.player, required this.onCard});
  final PokemonSession session;
  final int player;
  final void Function(int id) onCard;

  void _showPile(BuildContext context, Game g, String title, List<int> ids) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => pokemonScope(
        Builder(
          builder: (sheet) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GameTheme.of(sheet).heading),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final id in ids.reversed)
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(sheet);
                            onCard(id);
                          },
                          child: PokemonCardView(card: g.card(id), width: 84),
                        ),
                    ],
                  ),
                ],
              ),
            ),
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
    final turn = g.state.active == player && g.state.phase == Phase.main;
    Widget chip(IconData icon, String n, String tip) => Tooltip(
      message: tip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: t.muted),
            const SizedBox(width: 2),
            Text(n, style: t.style(13, weight: FontWeight.w800)),
          ],
        ),
      ),
    );
    final taken = 6 - p.prizes.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: turn ? t.highlight : Colors.black26, width: turn ? 3 : 1),
      ),
      child: Row(
        children: [
          if (turn) Icon(Icons.play_arrow, size: 18, color: t.highlight),
          Flexible(
            child: Text(
              p.name,
              style: t.style(14, weight: FontWeight.w900),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          // Prize cards: take all six to win.
          Tooltip(
            message: 'Prize cards: $taken of 6 taken. Take all 6 to win.',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 6; i++)
                  Container(
                    width: 11,
                    height: 15,
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(
                      color: i < p.prizes.length ? t.accent2 : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.black54),
                    ),
                  ),
              ],
            ),
          ),
          const Spacer(),
          chip(Icons.style, '${p.hand.length}', 'Hand'),
          chip(Icons.layers, '${p.deck.length}', 'Deck'),
          InkWell(
            onTap: p.discard.isEmpty ? null : () => _showPile(context, g, '${p.name}’s discard pile', p.discard),
            child: chip(Icons.delete_outline, '${p.discard.length}', 'Discard pile (tap to look)'),
          ),
        ],
      ),
    );
  }
}

/// One side's Pokémon in play: the Bench away from the middle, the Active Pokémon next to it.
class _Field extends StatelessWidget {
  const _Field({required this.session, required this.player, required this.top, required this.acts, required this.onCard});
  final PokemonSession session;
  final int player;
  final bool top;
  final _Actions acts;
  final void Function(int id) onCard;

  @override
  Widget build(BuildContext context) {
    final g = session.match;
    final p = g.state.player(player);
    final mine = player == session.localSeat;
    final lastCard = session.recent.isEmpty ? null : session.recent.lastWhere((e) => e.card != null, orElse: () => session.recent.last).card;
    return LayoutBuilder(
      builder: (context, box) {
        // Wide screens put the Bench beside the Active Pokémon, so both can be bigger.
        final wide = box.maxWidth >= 700 && box.maxWidth > box.maxHeight * 2.4;
        final activeH = box.maxHeight * (wide ? 0.95 : 0.56), benchH = box.maxHeight * (wide ? 0.78 : 0.4);
        final activeW = math.min(activeH * 63 / 88, 170.0);
        final benchW = math.min(math.min(benchH * 63 / 88, (box.maxWidth - (wide ? activeW + 60 : 40)) / 5.4), 130.0);
        Widget mon(int id, double w) => _InPlay(
          key: ValueKey(id),
          session: session,
          id: id,
          width: w,
          glow: mine && (acts.sources.contains(id) || (g.state.obj(id).zone == Place.active && acts.all.any((m) => m is AttackMove || m is RetreatMove))),
          recent: id == lastCard,
          onTap: () => onCard(id),
        );
        final active = SizedBox(
          height: activeH,
          child: Center(
            child: p.active == null ? _EmptySpot(width: activeW, label: 'Active') : mon(p.active!, activeW),
          ),
        );
        final bench = SizedBox(
          height: benchH,
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final id in p.bench) Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: mon(id, benchW)),
                  for (var i = p.bench.length; i < 5; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _EmptySpot(width: benchW, label: 'Bench'),
                    ),
                ],
              ),
            ),
          ),
        );
        if (wide) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              active,
              const SizedBox(width: 24),
              Flexible(child: bench),
            ],
          );
        }
        return Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: top ? [bench, active] : [active, bench]);
      },
    );
  }
}

class _EmptySpot extends StatelessWidget {
  const _EmptySpot({required this.width, required this.label});
  final double width;
  final String label;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return Container(
      width: width,
      height: width * 88 / 63,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(width * 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2),
      ),
      child: Text(
        label,
        style: t.style(width > 80 ? 13 : 10, weight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

/// A Pokémon in play: its card, HP left, Energy, Tool and Special Conditions.
class _InPlay extends StatelessWidget {
  const _InPlay({super.key, required this.session, required this.id, required this.width, required this.glow, required this.recent, required this.onTap});
  final PokemonSession session;
  final int id;
  final double width;
  final bool glow, recent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = session.match;
    final o = g.state.obj(id);
    final max = g.maxHp(id);
    final left = (max - o.damage).clamp(0, max);
    final h = width * 88 / 63;
    final small = width < 80;
    final energy = g.energyOf(id);
    // During setup the other player's Pokémon are face down.
    final hidden = g.state.phase == Phase.setup && o.owner != session.localSeat;
    return GestureDetector(
      onTap: hidden ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.07),
          border: Border.all(color: glow ? t.ok : (recent ? t.highlight : Colors.transparent), width: 3),
          boxShadow: [
            if (glow) BoxShadow(color: t.ok.withValues(alpha: 0.8), blurRadius: 12),
            if (recent && !glow) BoxShadow(color: t.highlight.withValues(alpha: 0.8), blurRadius: 12),
          ],
        ),
        child: SizedBox(
          width: width,
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // During setup the other player's Pokémon are face down.
              if (hidden)
                PokemonCardBack(width: width)
              else
                Semantics(
                  button: true,
                  label: '${o.zone == Place.active ? 'Active' : 'Bench'}: ${g.nameOf(id)}, $left of $max HP${glow ? ' (has moves)' : ''}',
                  excludeSemantics: true,
                  child: PokemonCardView(card: g.card(id), width: width),
                ),
              if (!hidden)
                // HP left.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(width * 0.05)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (energy.isNotEmpty || o.tool != null)
                          Wrap(
                            spacing: 1,
                            runSpacing: 1,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final e in energy) TypePip(e, size: small ? 11 : 15),
                              if (o.tool != null)
                                Tooltip(
                                  message: g.nameOf(o.tool!),
                                  child: Icon(Icons.build_circle, size: small ? 12 : 16, color: Colors.amberAccent),
                                ),
                            ],
                          ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: max == 0 ? 0 : left / max,
                            minHeight: small ? 3 : 5,
                            color: left * 4 <= max ? t.danger : (left * 2 <= max ? t.highlight : t.ok),
                            backgroundColor: Colors.white24,
                          ),
                        ),
                        Text(
                          '$left/$max HP',
                          style: TextStyle(fontSize: small ? 9 : 12, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              if (o.damage > 0)
                Positioned(
                  right: -4,
                  top: h * 0.22,
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(o.damage),
                    tween: Tween(begin: 1.8, end: 1),
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.elasticOut,
                    builder: (context, v, child) => Transform.scale(scale: v, child: child),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: small ? 4 : 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: t.danger,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(
                        '${o.damage}',
                        style: TextStyle(fontSize: small ? 10 : 14, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              if (o.conds.isNotEmpty)
                Positioned(
                  left: 2,
                  top: h * 0.2,
                  child: Column(
                    children: [
                      for (final c in o.conds)
                        Tooltip(
                          message: _condLabel(c),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 2),
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: t.danger, width: 1.5),
                            ),
                            child: Text(_condIcon(c), style: TextStyle(fontSize: small ? 9 : 13)),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Between the two sides: the Stadium in play and what just happened (the computer's moves,
/// coin flips, damage).
class _MiddleLine extends StatelessWidget {
  const _MiddleLine({required this.session, required this.onCard});
  final PokemonSession session;
  final void Function(int id) onCard;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = session.match;
    final stadium = g.state.stadium;
    final recent = session.recent.length > 4 ? session.recent.sublist(session.recent.length - 4) : session.recent;
    final coin = recent.lastWhere((e) => e.kind == 'coin' && e.text.contains('flips a coin'), orElse: () => const LogEntry(''));
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black26),
      ),
      child: Row(
        children: [
          if (stadium != null) ...[
            InkWell(
              onTap: () => onCard(stadium),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.stadium, size: 18),
                  const SizedBox(width: 3),
                  Text(g.nameOf(stadium), style: t.style(12, weight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(width: 10),
          ],
          if (coin.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TweenAnimationBuilder<double>(
                key: ValueKey('${g.state.log.length}'),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                builder: (context, v, child) => Transform(alignment: Alignment.center, transform: Matrix4.rotationY(math.pi * 4 * (1 - v)), child: child),
                child: Tooltip(
                  message: coin.text,
                  child: CircleAvatar(
                    radius: 13,
                    backgroundColor: coin.amount == 1 ? t.accent : const Color(0xFFB0B8C0),
                    child: Text(
                      coin.amount == 1 ? 'H' : 'T',
                      style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: recent.isEmpty
                ? Text('Tap a glowing card to play it.', style: t.style(12, color: t.muted))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in recent)
                        Text(
                          e.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.style(12, weight: e.kind == 'ko' || e.kind == 'prize' || e.kind == 'attack' ? FontWeight.w900 : FontWeight.w600, color: e.kind == 'ko' ? t.danger : null),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Hand extends StatelessWidget {
  const _Hand({required this.session, required this.acts, required this.onCard});
  final PokemonSession session;
  final _Actions acts;
  final void Function(int id) onCard;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = session.match;
    final ids = g.state.player(session.localSeat).hand;
    final w = math.min(92.0, math.max(60.0, MediaQuery.of(context).size.width / 7.2));
    // Playable cards first, so what can be done now is in view.
    final ordered = [...ids.where(acts.sources.contains), ...ids.where((id) => !acts.sources.contains(id))];
    return SizedBox(
      height: w * 88 / 63 + 14,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        children: [
          for (final id in ordered)
            Padding(
              key: ValueKey(id),
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => onCard(id),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: acts.all.isEmpty || acts.sources.contains(id) ? 1 : 0.55,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: acts.sources.contains(id) ? t.ok : Colors.transparent, width: 3),
                      boxShadow: acts.sources.contains(id) ? [BoxShadow(color: t.ok.withValues(alpha: 0.8), blurRadius: 10)] : null,
                    ),
                    child: Semantics(
                      button: true,
                      label: 'Hand: ${g.nameOf(id)}${acts.sources.contains(id) ? ' (playable)' : ''}',
                      excludeSemantics: true,
                      child: PokemonCardView(card: g.card(id), width: w),
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

/// What to do now: the decision to answer, or the Active Pokémon's attacks (with damage and
/// whether there's Energy for them), Retreat and End turn.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.session, required this.acts, required this.onDecide, required this.onRetreat});
  final PokemonSession session;
  final _Actions acts;
  final VoidCallback onDecide, onRetreat;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final g = session.match;
    final st = g.state;
    final d = g.pending?.decision;
    String line;
    final buttons = <Widget>[];
    if (g.over) {
      line = 'The game is over.';
    } else if (d != null && d.player == session.localSeat) {
      line = d.prompt;
      buttons.add(
        Expanded(
          child: ThemedButton('Choose', icon: Icons.touch_app, tall: true, onPressed: onDecide),
        ),
      );
    } else if (d != null) {
      line = 'Waiting for ${st.player(d.player).name}: ${d.prompt}';
    } else if (session.isLocalTurn) {
      final me = st.player(session.localSeat);
      final glowing = acts.sources.length;
      line = glowing == 0
          ? 'Nothing else to play. Attack or end your turn.'
          : 'Your turn: $glowing card${glowing == 1 ? '' : 's'} glow${glowing == 1 ? 's' : ''} — tap one to play it.${me.energyAttached ? '' : ' You can still attach an Energy.'}';
      final a = me.active;
      if (a != null) {
        final atks = g.card(a).attacks;
        for (var i = 0; i < atks.length; i++) {
          final at = atks[i];
          final ok = acts.canAttack(i);
          buttons.add(
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ThemedButton(
                  '${at.name}${at.damage > 0 ? ' ${at.damage}${at.mod}' : ''}',
                  subtitle: ok ? _costText(at.cost) : (g.hasEnergyFor(a, i) ? 'can’t attack now' : 'needs ${_costText(at.cost)}'),
                  color: ok ? t.accent3 : null,
                  icon: Icons.flash_on,
                  onPressed: ok ? () => session.perform(AttackMove(session.localSeat, i)) : null,
                ),
              ),
            ),
          );
        }
      }
      if (acts.canRetreat) {
        buttons.add(
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ThemedButton('Retreat', icon: Icons.swap_vert, outlined: true, expand: false, onPressed: onRetreat),
          ),
        );
      }
      buttons.add(ThemedButton('End turn', icon: Icons.skip_next, color: t.accent2, expand: false, onPressed: () => session.perform(EndTurnMove(session.localSeat))));
    } else {
      line = st.phase == Phase.setup ? 'Setting up…' : (session.isLinked ? 'Waiting for ${st.player(st.active).name}…' : '${st.player(st.active).name}’s turn…');
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: t.panel.withValues(alpha: 0.96),
        border: const Border(top: BorderSide(color: Colors.black, width: 3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (session.notice != null) Text(session.notice!, style: t.style(12, color: t.accent2)),
          if (session.lastError != null)
            Text(
              session.lastError!,
              style: t.style(13, weight: FontWeight.w800, color: t.danger),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              line,
              style: t.style(14, weight: FontWeight.w700),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (buttons.isNotEmpty) Row(children: buttons),
        ],
      ),
    );
  }
}

/// Answers a decision: pick cards (tap to choose, long-press to read one), yes/no or an option.
class PokemonDecisionDialog extends StatefulWidget {
  const PokemonDecisionDialog({super.key, required this.session, required this.decision});
  final PokemonSession session;
  final Decision decision;
  @override
  State<PokemonDecisionDialog> createState() => _PokemonDecisionDialogState();
}

class _PokemonDecisionDialogState extends State<PokemonDecisionDialog> {
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
        Text(d.prompt, style: t.heading),
      ],
    );
    final look = TextButton(onPressed: () => Navigator.pop(context), child: const Text('Look at the table'));
    switch (d.kind) {
      case DecisionKind.yesNo:
        return AlertDialog(
          title: title,
          actions: [
            look,
            TextButton(onPressed: () => Navigator.pop(context, const [0]), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.pop(context, const [1]), child: const Text('Yes')),
          ],
        );
      case DecisionKind.option:
        return AlertDialog(
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
          title: title,
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < d.options.length; i++)
                    Builder(
                      builder: (context) {
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
                          onLongPress: isCard
                              ? () => showDialog<void>(
                                  context: context,
                                  builder: (c) => pokemonScope(
                                    Dialog(
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: SingleChildScrollView(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              PokemonCardView(card: g.card(id), width: 240, large: true),
                                              const SizedBox(height: 8),
                                              PokemonCardText(card: g.card(id)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : null,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: on ? t.highlight : Colors.transparent, width: 4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isCard)
                                  Semantics(
                                    button: true,
                                    label: 'Option: ${g.nameOf(id)}',
                                    excludeSemantics: true,
                                    child: PokemonCardView(card: g.card(id), width: 96),
                                  )
                                else
                                  Padding(padding: const EdgeInsets.all(12), child: Text(i < d.labels.length ? d.labels[i] : '$id')),
                                if (isCard && (g.state.obj(id).zone == Place.active || g.state.obj(id).zone == Place.bench)) Text(_where(g, id), style: t.style(11, color: t.muted)),
                                if (on) Icon(Icons.check_circle, color: t.highlight, size: 18),
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
  final PokemonSession session;
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
            child: IntrinsicHeight(
              child: ThemedPanel(
                title: won ? 'You win!' : (st.winner == null ? 'Draw' : 'You lose'),
                color: won ? t.ok : t.danger,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(won ? Icons.emoji_events : Icons.sentiment_dissatisfied, size: 56, color: won ? t.accent : t.muted),
                    Text([for (final p in st.players) '${p.name}: ${6 - p.prizes.length} of 6 Prize cards'].join('\n'), style: t.body),
                    const SizedBox(height: 12),
                    if (!session.isLinked) ...[
                      ThemedButton(
                        'Rematch',
                        icon: Icons.replay,
                        tall: true,
                        color: t.ok,
                        onPressed: () {
                          PokemonStore.shared.newGame(
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
                        PokemonStore.shared.endSession();
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
