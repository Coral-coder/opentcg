import 'package:lorcana/lorcana.dart';
import 'package:tcg_core/tcg_core.dart' show TcgBot;

/// The guided first game: fixed decks, a fixed seed and starting player, the coach's steps for
/// the player, and the opponent's scripted moves. The engine is deterministic, so the same seed,
/// decks and moves always produce the same game (test/lorcana_tutorial_test.dart plays it through).
class TutorialScript {
  static const seed = 20261025;

  static const stitch = 'Stitch - New Dog';
  static const minnie = 'Minnie Mouse - Beloved Princess';
  static const mickey = 'Mickey Mouse - True Friend';
  static const heal = 'Heal What Has Been Hurt';
  static const goons = "Goons - Maleficent's Underlings";
  static const donald = 'Donald Duck - Boisterous Fowl';
  static const classy = 'Minnie Mouse - Always Classy';

  /// Small decks of plain cards (no abilities but the song), so every lesson shows one rule.
  static const decks = [
    [stitch, stitch, stitch, minnie, minnie, minnie, mickey, mickey, mickey, heal, heal, heal],
    [goons, goons, goons, goons, donald, donald, donald, donald, classy, classy, classy, classy],
  ];

  static const names = ['You', 'Rival'];

  static StartMove get start => const StartMove(decks, firstPlayer: 0);

  /// What the opponent does, turn by turn: (action, card name). 'end' ends its turn.
  static const opponent = <(String, String)>[
    ('ink', ''), ('play', goons), ('end', ''), //
    ('ink', ''), ('quest', goons), ('end', ''),
    ('ink', ''), ('play', donald), ('end', ''),
  ];

  /// The cards the opponent's script still plays, so its inking keeps them.
  static const _opponentNeeds = [goons, donald];

  static List<CoachStep> steps() => [
    CoachStep.move(
      'Welcome to Lorcana',
      'You and your opponent race to 20 lore ◆. In this guided game, do what glows and I’ll explain why; the cards and rules are the real ones. First, each player may put cards from their opening hand on the bottom of the deck and draw new ones. Your hand is good: keep it.',
      accepts: (g, m) => m is AnswerMove && m.answer.isEmpty,
      hint: 'For this lesson, keep your hand: confirm with no cards chosen.',
      guardsAnswers: true,
      dialogNote: 'Welcome! You may swap cards from your opening hand for new ones. This hand is good: choose nothing and tap Confirm to keep it.',
    ),
    _ink(
      'Ink a card',
      'Once per turn you may put a card with the ink swirl around its cost into your inkwell, face down. Ink is what you pay with. Ink the glowing card.',
      needs: const [stitch, minnie, mickey, heal],
    ),
    _play(stitch, 'Play a character', 'Stitch costs 1 ink, the number in the top corner. Tap Stitch and choose Play: his cost is paid by exerting (turning) 1 of your ink.'),
    const CoachStep.info(
      'Characters are drying',
      'Stitch just arrived, so he’s drying (the drop on his card). A character can’t quest, challenge or sing the turn it’s played. Next turn he’s dry and ready to go.',
    ),
    _end('You’ve spent your ink. Tap End turn. Everything of yours readies at the start of your next turn.'),
    const CoachStep.watch('Their turn', 'Watch: your opponent inks a card and plays a character too.'),
    _ink(
      'Your turn again',
      'At the start of your turn your cards ready, and you draw a card (the first player skips that draw on the very first turn). Ink the glowing card: you’ll have 2 ink.',
      needs: const [minnie, mickey, heal],
    ),
    _quest(stitch, 'Quest', 'Questing is how you win: exert a dry character to gain its lore ◆. Stitch has 1 ◆. Tap Stitch and choose Quest.'),
    _play(minnie, 'Play another character', 'You have 2 ink ready. Minnie costs 2: tap her and choose Play.'),
    _end('Tap End turn.'),
    const CoachStep.watch('Their turn', 'Watch: their character quests. Questing exerts it (turns it sideways), and exerted characters can be challenged.'),
    _ink('Ink a card', 'Ink the glowing card: 3 ink this turn.', needs: const [mickey, heal]),
    CoachStep.move(
      'Challenge',
      'Exert a dry character to challenge an exerted opposing one. Each deals damage equal to its strength ⚔, and a character with damage equal to its willpower ⛨ is banished. Minnie (2 ⚔, 3 ⛨) challenges the Goons (2 ⚔, 2 ⛨): tap Minnie and choose Challenge.',
      accepts: (g, m) => m is ChallengeMove && _is(g, m.card, minnie) && _is(g, m.target, goons),
      hint: 'Challenge the exerted Goons with Minnie.',
      glow: (g) => {..._named(g, 0, Place.play, minnie), ..._named(g, 1, Place.play, goons)},
    ),
    const CoachStep.info(
      'Banished',
      'The Goons took 2 damage with 2 willpower, so they’re banished to the discard. Minnie took 2 but has 3 willpower: she stays, and the damage stays on her until it’s removed.',
    ),
    _quest(stitch, 'Quest again', 'Stitch is still ready: quest for another lore.'),
    _play(mickey, 'Play Mickey', 'Mickey costs 3 and has 2 ◆. Tap him and choose Play.'),
    _end('Tap End turn.'),
    const CoachStep.watch('Their turn', 'Watch your opponent play another character.'),
    _ink('Ink a card', 'Ink the glowing card.', needs: const [heal]),
    CoachStep.move(
      'Sing a song',
      'Songs are actions. You can pay their cost in ink, or exert a dry character whose cost is at least the song’s to sing it for free. Mickey costs 3, so he can sing Heal What Has Been Hurt (cost 3). Tap the song and choose “Sing it with Mickey”.',
      accepts: (g, m) => m is PlayMove && m.mode == PlayMode.sing && _is(g, m.card, heal),
      hint: 'Tap Heal What Has Been Hurt and have Mickey sing it.',
      glow: (g) => {..._named(g, 0, Place.hand, heal).take(1)},
    ),
    CoachStep.move(
      'Heal Minnie',
      'The song removes up to 3 damage from a chosen character, then you draw a card. Choose Minnie.',
      accepts: (g, m) => m is AnswerMove,
      dialogNote: 'Tutorial: choose Minnie to heal her.',
    ),
    _quest(minnie, 'Quest with Minnie', 'Minnie is healed and still ready (challenging exerted her last turn, but she readied this turn). Quest with her.'),
    _quest(stitch, 'Quest with Stitch', 'And Stitch too.'),
    _end('That’s a full turn. Tap End turn to finish the lesson.'),
    const CoachStep.done(),
  ];

  static CoachStep _ink(String title, String body, {required List<String> needs}) => CoachStep.move(
    title,
    body,
    accepts: (g, m) => m is InkMove && _spare(g, 0, needs).contains(m.card),
    hint: 'Keep that card, you’ll want it soon. Ink the glowing card instead.',
    glow: (g) => {..._spare(g, 0, needs).take(1)},
  );

  static CoachStep _play(String name, String title, String body) => CoachStep.move(
    title,
    body,
    accepts: (g, m) => m is PlayMove && m.mode == PlayMode.ink && _is(g, m.card, name),
    hint: 'Play ${_short(name)} first.',
    glow: (g) => {..._named(g, 0, Place.hand, name).take(1)},
  );

  static CoachStep _quest(String name, String title, String body) => CoachStep.move(
    title,
    body,
    accepts: (g, m) => m is QuestMove && _is(g, m.card, name),
    hint: 'Quest with ${_short(name)}.',
    glow: (g) => {
      for (final id in _named(g, 0, Place.play, name))
        if (!g.state.obj(id).exerted) id,
    },
  );

  static CoachStep _end(String body) => CoachStep.move('End your turn', body, accepts: (g, m) => m is EndTurnMove, hint: 'Tap End turn.', glow: (g) => const {CoachStep.endTurnButton});

  static String _short(String name) => name.split(' - ').first;

  static bool _is(Game g, int id, String name) => g.state.objOrNull(id)?.card == name;

  static List<int> _named(Game g, int seat, Place zone, String name) {
    final p = g.state.player(seat);
    final ids = switch (zone) {
      Place.hand => p.hand,
      Place.play => p.play,
      _ => const <int>[],
    };
    return [
      for (final id in ids)
        if (g.state.obj(id).card == name) id,
    ];
  }

  /// Hand cards that can be inked without losing one the lessons still need.
  static List<int> _spare(Game g, int seat, List<String> needs) {
    final hand = g.state.player(seat).hand;
    final count = <String, int>{};
    for (final id in hand) {
      count.update(g.state.obj(id).card, (n) => n + 1, ifAbsent: () => 1);
    }
    return [
      for (final id in hand)
        if (g.card(id).inkable && count[g.state.obj(id).card]! > (needs.contains(g.state.obj(id).card) ? 1 : 0)) id,
    ];
  }
}

enum CoachKind { info, move, watch, done }

/// One thing the coach says, and (for a move step) which move it waits for.
class CoachStep {
  const CoachStep.info(this.title, this.body) : kind = CoachKind.info, accepts = null, hint = null, glow = null, guardsAnswers = false, dialogNote = null;
  const CoachStep.watch(this.title, this.body) : kind = CoachKind.watch, accepts = null, hint = null, glow = null, guardsAnswers = false, dialogNote = null;
  const CoachStep.done()
    : kind = CoachKind.done,
      title = 'You’ve learned the basics',
      body = 'Inking, playing characters, drying, questing, challenging and singing: that’s most of Lorcana.',
      accepts = null,
      hint = null,
      glow = null,
      guardsAnswers = false,
      dialogNote = null;
  const CoachStep.move(this.title, this.body, {required this.accepts, this.hint, this.glow, this.guardsAnswers = false, this.dialogNote}) : kind = CoachKind.move;

  /// The id [glow] uses for the End turn button.
  static const endTurnButton = -2;

  final CoachKind kind;
  final String title, body;
  final bool Function(Game g, LMove m)? accepts;

  /// Said when the player tries another move.
  final String? hint;

  /// The cards (and buttons) to point at.
  final Set<int> Function(Game g)? glow;

  /// Whether answers to decisions must match [accepts] too (otherwise any answer is fine).
  final bool guardsAnswers;

  /// Shown in the choice dialog during this step.
  final String? dialogNote;
}

/// Plays the opponent's side of [TutorialScript.opponent], one move per step, then (if the game
/// goes on) hands over to the real computer player.
class TutorialOpponent implements TcgBot {
  TutorialOpponent(this.seat, {this.script = TutorialScript.opponent});
  final int seat;
  final List<(String, String)> script;
  int _next = 0;
  final _fallback = LorcanaBot(1, seed: TutorialScript.seed);

  bool get finished => _next >= script.length;

  @override
  bool step(covariant Game g) {
    final s = g.state;
    if (s.over) return false;
    final d = g.pending?.decision;
    if (d != null) {
      if (d.player != seat) return false;
      g.apply(AnswerMove(seat, d.min == 0 && d.kind == DecisionKind.cards ? const [] : g.defaultAnswer(d)));
      return true;
    }
    if (s.active != seat || s.phase != Phase.main) return false;
    if (finished) return _fallback.step(g);
    final (what, name) = script[_next++];
    final legal = g.legalMoves();
    LMove? pick;
    switch (what) {
      case 'ink':
        final spare = TutorialScript._spare(g, seat, TutorialScript._opponentNeeds);
        pick = legal.whereType<InkMove>().where((m) => spare.contains(m.card)).firstOrNull;
      case 'play':
        pick = legal.whereType<PlayMove>().where((m) => m.mode == PlayMode.ink && g.state.obj(m.card).card == name).firstOrNull;
      case 'quest':
        pick = legal.whereType<QuestMove>().where((m) => g.state.obj(m.card).card == name).firstOrNull;
      case 'end':
        pick = EndTurnMove(seat);
    }
    if (pick == null) {
      // Off script (shouldn't happen with the fixed seed): skip to this turn's end.
      while (_next < script.length && script[_next].$1 != 'end') {
        _next++;
      }
      return true;
    }
    g.apply(pick);
    return true;
  }
}
