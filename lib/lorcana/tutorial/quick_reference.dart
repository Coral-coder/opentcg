import 'package:flutter/material.dart' hide Ink;
import 'package:tcg_app/tcg_app.dart';

import '../lorcana_theme.dart';

/// The keywords, in a few words each (what the full rules say, plainly).
const lorcanaKeywords = <(String, String)>[
  ('Bodyguard', 'May enter play exerted. While it’s in play, an opponent who challenges one of your characters must challenge a Bodyguard if they can.'),
  ('Challenger +N', 'Gets +N ⚔ while it’s challenging (not when it’s challenged).'),
  ('Evasive', 'Can be challenged only by characters with Evasive.'),
  ('Reckless', 'Can’t quest. You can’t end your turn while it’s ready and able to challenge.'),
  ('Resist +N', 'Damage dealt to it is reduced by N.'),
  ('Rush', 'Can challenge the turn it’s played. It still can’t quest or sing that turn.'),
  ('Shift N', 'Pay N ink to play it on top of your character with the same name. It keeps that character’s damage and state: if the card below was dry, it can quest right away.'),
  ('Singer N', 'Counts as cost N when singing songs.'),
  ('Support', 'When it quests, you may add its ⚔ to another chosen character’s ⚔ this turn.'),
  ('Ward', 'Opponents can’t choose it for their effects (they can still challenge it).'),
  ('Alert', 'Can challenge characters with Evasive.'),
  ('Boost N', 'Once during your turn, pay N ink to put the top card of your deck facedown under it.'),
];

/// The turn, in order.
const lorcanaTurn = <(String, String)>[
  ('Ready', 'Your exerted cards ready.'),
  ('Set', 'Your characters are no longer drying; your locations give you their lore ◆.'),
  ('Draw', 'Draw a card. The first player skips this on the very first turn.'),
  ('Main', 'In any order, as often as you can: put one card a turn into your inkwell; play cards by exerting ink; quest; challenge; move characters to locations; use abilities. Then end your turn.'),
];

/// Opens the quick reference over the table.
void showLorcanaQuickReference(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => const LorcanaScope(child: FractionallySizedBox(heightFactor: 0.85, child: LorcanaQuickReference())),
  );
}

/// The turn's structure, how to win, challenging, and the keyword glossary, on one page.
class LorcanaQuickReference extends StatelessWidget {
  const LorcanaQuickReference({super.key});

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    Widget row(String a, String b) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$a  ',
              style: t.style(14, weight: FontWeight.w800, color: t.accent),
            ),
            TextSpan(
              text: b,
              style: t.style(14, weight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text('Quick reference', style: t.title),
          const SizedBox(height: 6),
          Text('First to 20 lore ◆ wins.', style: t.body),
          const SizedBox(height: 14),
          Text('Your turn', style: t.heading),
          const SizedBox(height: 6),
          for (final (a, b) in lorcanaTurn) row(a, b),
          const SizedBox(height: 8),
          Text('Characters', style: t.heading),
          const SizedBox(height: 6),
          row('Drying', 'A character can’t quest, challenge or sing the turn it’s played.'),
          row('Quest', 'Exert it to gain its lore ◆.'),
          row('Challenge', 'Exert it to fight an exerted opposing character (or a location). Both deal damage equal to their ⚔; damage equal to ⛨ banishes.'),
          row('Sing', 'Exert a character whose cost is at least a song’s cost to play the song for free.'),
          const SizedBox(height: 8),
          Text('Keywords', style: t.heading),
          const SizedBox(height: 6),
          for (final (a, b) in lorcanaKeywords) row(a, b),
        ],
      ),
    );
  }
}
