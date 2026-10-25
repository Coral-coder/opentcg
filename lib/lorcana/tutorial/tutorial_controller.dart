import 'package:flutter/material.dart' hide Ink;
import 'package:lorcana/lorcana.dart';

import '../lorcana_session.dart';
import 'tutorial_script.dart';

/// Runs the guided game on the real table: which step the player is on, what to point at, and
/// which moves to let through. The table asks [blocked] before each of the player's moves and
/// reports [performed] after; opponent turns ("watch" steps) end on their own.
class TutorialController extends ChangeNotifier {
  TutorialController(this.session) : steps = TutorialScript.steps() {
    session.addListener(_sync);
  }

  final LorcanaSession session;
  final List<CoachStep> steps;
  int index = 0;

  /// After the lesson: the game goes on with no restrictions.
  bool free = false;
  bool _accepted = false;

  CoachStep get step => steps[index];
  Game get game => session.match;
  bool get finished => step.kind == CoachKind.done;

  /// The step number shown to the player (info and watch steps count too).
  String get progress => '${index + 1} / ${steps.length - 1}';

  /// What to point at now: card ids, or [CoachStep.endTurnButton].
  Set<int> get glows {
    if (free || game.pending != null) return const {};
    return step.glow?.call(game) ?? const {};
  }

  /// Said in the choice dialog during this step.
  String? get dialogNote => free ? null : step.dialogNote;

  /// Whether [m] is the move this step waits for (for highlighting buttons).
  bool wants(LMove m) => !free && step.kind == CoachKind.move && (step.accepts?.call(game, m) ?? false);

  /// Null if the player may make [m] now; otherwise a gentle hint saying what to do instead.
  String? blocked(LMove m) {
    _accepted = false;
    if (free || m.seat != session.localSeat || m is ConcedeMove) return null;
    final s = step;
    switch (s.kind) {
      case CoachKind.info:
        return 'Read the tip at the top, then tap Next.';
      case CoachKind.watch:
        return 'It’s their turn: watch what they do.';
      case CoachKind.done:
        return null;
      case CoachKind.move:
        final ok = s.accepts!(game, m);
        if (m is AnswerMove && !s.guardsAnswers) {
          _accepted = ok;
          return null;
        }
        if (!ok) return s.hint ?? 'Do what the tip at the top says.';
        _accepted = true;
        return null;
    }
  }

  /// The move [blocked] let through was made.
  void performed(LMove m) {
    if (_accepted) {
      _accepted = false;
      _advance();
    }
  }

  /// Info steps: the player has read it.
  void next() {
    if (step.kind == CoachKind.info) _advance();
  }

  /// Ends the lesson and lets the game go on (the opponent plays for real once its script ends).
  void keepPlaying() {
    free = true;
    notifyListeners();
  }

  void _advance() {
    if (index < steps.length - 1) index++;
    notifyListeners();
    _sync();
  }

  void _sync() {
    if (free) return;
    final g = game;
    if (step.kind == CoachKind.watch && g.state.active == session.localSeat && g.pending == null && !session.thinking) {
      _advance();
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    session.removeListener(_sync);
    super.dispose();
  }
}

/// Makes the tutorial (if any) reachable from the table's widgets.
class TutorialScope extends InheritedNotifier<TutorialController> {
  const TutorialScope({super.key, required TutorialController controller, required super.child}) : super(notifier: controller);

  static TutorialController? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TutorialScope>()?.notifier;
}

/// A soft golden pulse around [child] while the tutorial points at [id] (or when [on]). Without a
/// tutorial it's just [child].
class TutorialGlow extends StatelessWidget {
  const TutorialGlow({super.key, this.id, this.on = false, this.radius = 8, required this.child});
  final int? id;
  final bool on;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = TutorialScope.maybeOf(context);
    final lit = on || (t != null && id != null && t.glows.contains(id));
    if (!lit) return child;
    return Semantics(container: true, label: 'Highlighted by the tutorial', child: _Pulse(radius: radius, child: child));
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.radius, required this.child});
  final double radius;
  final Widget child;
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final v = Curves.easeInOut.transform(_c.value);
        const gold = Color(0xFFFFD25A);
        final r = BorderRadius.circular(widget.radius);
        // The halo behind the card, the ring on top of it, and a slight lift.
        return Transform.translate(
          offset: Offset(0, -4 * v),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: r,
              boxShadow: [BoxShadow(color: gold.withValues(alpha: 0.55 + 0.4 * v), blurRadius: 10 + 14 * v, spreadRadius: 2 + 3 * v)],
            ),
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(borderRadius: r, border: Border.all(color: gold, width: 3)),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
