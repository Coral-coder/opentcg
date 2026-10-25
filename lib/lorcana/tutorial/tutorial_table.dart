import 'package:flutter/material.dart' hide Ink;
import 'package:lorcana/lorcana.dart' show LorcanaRuleset;
import 'package:tcg_app/tcg_app.dart';

import '../lorcana_session.dart';
import '../lorcana_store.dart';
import '../lorcana_table.dart';
import '../lorcana_theme.dart';
import 'rules_primer.dart';
import 'tutorial_controller.dart';
import 'tutorial_script.dart';

/// Starts the guided first game on its own session (the saved game, if any, is left alone).
Future<void> openLorcanaTutorial(BuildContext context) async {
  final store = LorcanaStore.shared;
  store.endSession();
  final s = LorcanaSession.local(ruleset: LorcanaRuleset(store.db), mode: SessionMode.solo, playerNames: TutorialScript.names, seed: TutorialScript.seed, decks: TutorialScript.decks);
  s.bots[1] = TutorialOpponent(1);
  s.botDelay = 900;
  store.session = s;
  final controller = TutorialController(s);
  s.perform(TutorialScript.start);
  await Navigator.of(context).push(lorcanaRoute<void>(TutorialTable(controller: controller), sky: false));
  controller.dispose();
  if (store.session == s) store.endSession();
}

/// The real table with the coach docked above it, and the lesson's end.
class TutorialTable extends StatelessWidget {
  const TutorialTable({super.key, required this.controller});
  final TutorialController controller;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return TutorialScope(
      controller: controller,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ColoredBox(
          color: t.bg,
          child: Stack(
            children: [
              Column(
                children: [
                  if (!controller.free && !controller.finished) _CoachPanel(controller: controller),
                  // The coach panel takes the top inset, so the table doesn't add it again.
                  Expanded(
                    child: controller.free ? const LorcanaTable() : MediaQuery.removePadding(context: context, removeTop: true, child: const LorcanaTable()),
                  ),
                ],
              ),
              if (controller.finished && !controller.free) _Finished(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoachPanel extends StatelessWidget {
  const _CoachPanel({required this.controller});
  final TutorialController controller;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final s = controller.step;
    final watching = s.kind == CoachKind.watch;
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Container(
            key: ValueKey(controller.index),
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [t.panel, Color.lerp(t.panel, t.accent, 0.18)!]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.accent, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10)],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: watching ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: t.accent)) : Icon(Icons.auto_awesome, color: t.accent, size: 22),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.title,
                              style: t.style(15, weight: FontWeight.w800, color: t.accent),
                            ),
                          ),
                          Text(controller.progress, style: t.small),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(s.body, style: t.style(13, weight: FontWeight.w500, height: 1.3)),
                      if (s.kind == CoachKind.info)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: ThemedButton('Next', icon: Icons.arrow_forward, expand: false, onPressed: controller.next),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Finished extends StatelessWidget {
  const _Finished({required this.controller});
  final TutorialController controller;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final s = controller.step;
    final me = controller.game.state.player(0);
    return Positioned.fill(
      child: Material(
        color: Colors.black54,
        child: Center(
          // Scrolls on short screens; also lets the panel take only the height it needs.
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GildedPanel(
                  title: s.title,
                  glow: t.accent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(s.body, style: t.body),
                      const SizedBox(height: 8),
                      Text('You have ${me.lore} lore. Keep going to 20, or start a real game with full decks.', style: t.small),
                      const SizedBox(height: 14),
                      ThemedButton('Keep playing this game', icon: Icons.play_arrow, tall: true, onPressed: controller.keepPlaying),
                      const SizedBox(height: 8),
                      ThemedButton('Play a real game', icon: Icons.smart_toy, tall: true, color: t.accent2, onPressed: () => Navigator.of(context).pop()),
                      const SizedBox(height: 8),
                      ThemedButton(
                        'Read the rules',
                        icon: Icons.menu_book,
                        outlined: true,
                        onPressed: () {
                          Navigator.of(context)
                            ..pop()
                            ..push(lorcanaRoute<void>(const LorcanaRulesPrimer()));
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Learn to play": the guided game, the rules primer and the quick reference.
class LorcanaLearnScreen extends StatelessWidget {
  const LorcanaLearnScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Learn to play')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ThemedButton('Guided first game', subtitle: 'Play a real game with a coach: about 5 minutes', tall: true, icon: Icons.school, onPressed: () => openLorcanaTutorial(context)),
              const SizedBox(height: 10),
              ThemedButton(
                'The rules in 9 pages',
                subtitle: 'Swipe through, with real cards',
                tall: true,
                icon: Icons.menu_book,
                color: t.accent2,
                onPressed: () {
                  Navigator.of(context).push(lorcanaRoute<void>(LorcanaRulesPrimer(onGuidedGame: () => openLorcanaTutorial(context))));
                },
              ),
              const SizedBox(height: 18),
              GildedPanel(child: Text('During any game, tap ? at the top of the table for the turn and every keyword.', style: t.small)),
            ],
          ),
        ),
      ),
    );
  }
}
