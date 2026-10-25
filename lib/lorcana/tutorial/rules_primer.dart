import 'package:flutter/material.dart' hide Ink;
import 'package:tcg_app/tcg_app.dart';

import '../lorcana_card.dart';
import '../lorcana_store.dart';
import 'quick_reference.dart';

/// One page of the primer: a few real cards as the picture, and the rule in plain words.
class _Page {
  const _Page(this.title, this.cards, this.lines);
  final String title;
  final List<String> cards;
  final List<String> lines;
}

const _pages = [
  _Page(
    'Race to 20 lore',
    ['Mickey Mouse - True Friend'],
    ['Each player has a deck of at least 60 cards. The first to 20 lore ◆ wins.', 'You gain lore mostly by questing with your characters. The ◆ on a character is how much lore it gives.'],
  ),
  _Page(
    'Ink pays for everything',
    ['Mickey Mouse - True Friend', 'Simba - Happy-Go-Lucky'],
    [
      'Once per turn, you may put a card from your hand into your inkwell, face down. Only cards with the swirl around their cost can be inked (Mickey can, Simba can’t).',
      'To play a card, exert (turn sideways) that much ink. All your ink readies at the start of your turn.',
    ],
  ),
  _Page(
    'Characters dry first',
    ['Stitch - New Dog'],
    ['A character can’t quest, challenge or sing the turn it’s played: its ink is still drying.', 'From your next turn on, it can do all three. The table shows a drop on characters that are drying.'],
  ),
  _Page(
    'Quest',
    ['Minnie Mouse - Beloved Princess'],
    ['Exert a dry character to quest: you gain its lore ◆.', 'An exerted character stays exerted until your next turn, and exerted characters can be challenged.'],
  ),
  _Page(
    'Challenge',
    ["Goons - Maleficent's Underlings", 'Minnie Mouse - Beloved Princess'],
    [
      'Exert a dry character to challenge an exerted opposing character. Ready characters can’t be challenged.',
      'Each deals damage equal to its strength ⚔. A character with damage equal to its willpower ⛨ is banished. Damage stays until it’s removed.',
    ],
  ),
  _Page(
    'Actions and songs',
    ['Heal What Has Been Hurt', 'Mickey Mouse - True Friend'],
    ['Actions do their thing and go to the discard.', 'Songs are actions you can also sing: exert a dry character whose cost is at least the song’s cost, and play the song for free.'],
  ),
  _Page(
    'Items and locations',
    ['Lantern', 'Pride Lands - Pride Rock'],
    [
      'Items stay in play and give you abilities.',
      'Locations stay in play too. Pay their move cost to move characters there; at the start of your turn each location gives you its ◆. Locations can be challenged, but they never challenge.',
    ],
  ),
  _Page(
    'Keywords',
    ['Peter Pan - Never Landing', 'Goofy - Musketeer'],
    [
      'Keywords are short rules printed on cards: Evasive, Bodyguard, Ward, Rush, Resist, Challenger, Support, Singer, Shift, Reckless and more.',
      'The ? button on the table explains every one of them.',
    ],
  ),
  _Page('Your turn', [], [
    'Ready: your cards ready.  Set: drying ends, locations give lore.  Draw: draw a card (not on the very first turn of the game).',
    'Then, in any order: ink one card, play cards, quest, challenge, move to locations, use abilities. End your turn when you’re done.',
  ]),
];

/// The rules in nine swipeable pages, with real cards as examples.
class LorcanaRulesPrimer extends StatefulWidget {
  const LorcanaRulesPrimer({super.key, this.onGuidedGame});

  /// Shown as a button on the last page.
  final VoidCallback? onGuidedGame;
  @override
  State<LorcanaRulesPrimer> createState() => _LorcanaRulesPrimerState();
}

class _LorcanaRulesPrimerState extends State<LorcanaRulesPrimer> {
  final _pc = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _go(int p) => _pc.animateToPage(p, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final last = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: const Text('How to play'),
        backgroundColor: t.panel,
        actions: [IconButton(icon: const Icon(Icons.help_outline), tooltip: 'Quick reference', onPressed: () => showLorcanaQuickReference(context))],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pc,
                onPageChanged: (p) => setState(() => _page = p),
                children: [for (final p in _pages) _PageView(page: p)],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  GestureDetector(
                    onTap: () => _go(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.all(4),
                      width: i == _page ? 18 : 8,
                      height: 8,
                      decoration: BoxDecoration(color: i == _page ? t.accent : t.muted.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Row(
                children: [
                  if (_page > 0) ...[
                    Expanded(
                      child: ThemedButton('Back', icon: Icons.arrow_back, outlined: true, onPressed: () => _go(_page - 1)),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: 2,
                    child: last
                        ? ThemedButton(
                            widget.onGuidedGame == null ? 'Done' : 'Try the guided game',
                            icon: Icons.school,
                            onPressed: () {
                              Navigator.of(context).pop();
                              widget.onGuidedGame?.call();
                            },
                          )
                        : ThemedButton('Next', icon: Icons.arrow_forward, onPressed: () => _go(_page + 1)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page});
  final _Page page;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final store = LorcanaStore.shared;
    final cards = [
      for (final n in page.cards)
        if (store.ready && store.db[n] != null) store.db[n]!,
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - 48) / (cards.length.clamp(1, 2)) - 8;
        final cardW = w.clamp(90.0, box.maxHeight * 0.42 * 5 / 7).toDouble();
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(page.title, style: t.title, textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  if (cards.isNotEmpty)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final c in cards)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: LorcanaCardView(card: c, width: cardW),
                          ),
                      ],
                    ),
                  if (cards.isNotEmpty) const SizedBox(height: 16),
                  for (final l in page.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(l, style: t.style(16, weight: FontWeight.w500, height: 1.35)),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
