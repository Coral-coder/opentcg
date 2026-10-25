import 'package:flutter/material.dart' hide Ink;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:lorcana/lorcana.dart';
import 'package:tcg_app/tcg_app.dart';

import 'lorcana_card.dart';
import 'lorcana_cards_screen.dart';
import 'lorcana_decks.dart';
import 'lorcana_store.dart';

/// The saved decks: make a new one, copy a starter deck, import a list; open one to edit it.
class LorcanaDecksScreen extends StatefulWidget {
  const LorcanaDecksScreen({super.key});
  @override
  State<LorcanaDecksScreen> createState() => _LorcanaDecksScreenState();
}

class _LorcanaDecksScreenState extends State<LorcanaDecksScreen> {
  final store = LorcanaStore.shared;

  Future<void> _edit(LorcanaDeck d) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LorcanaDeckEditor(deck: d)));
    if (mounted) setState(() {});
  }

  Future<void> _new() async {
    final name = await askText(context, 'New deck', 'Name', 'My deck');
    if (name == null || !mounted) return;
    await _edit(store.decks.create(name));
  }

  Future<void> _starter() async {
    final pair = await showDialog<Set<Ink>>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('Starter deck'), children: [
        for (final p in allInkPairs()) SimpleDialogOption(onPressed: () => Navigator.pop(c, p), child: Text(inkPairName(p))),
      ]),
    );
    if (pair == null || !mounted) return;
    await _edit(store.decks.create('Starter: ${inkPairName(pair)}', starterDeck(store.db, pair)));
  }

  Future<void> _import() async {
    final text = await askText(context, 'Import a deck list', 'One card per line, like “4 Mickey Mouse - Brave Little Tailor”', '', multiline: true);
    if (text == null || !mounted) return;
    final (cards, errors) = parseDeckList(store.db, text);
    if (cards.isEmpty) {
      _toast(errors.isEmpty ? 'No cards in that list.' : errors.first);
      return;
    }
    final d = store.decks.create('Imported deck', cards);
    if (errors.isNotEmpty) _toast('${errors.length} line(s) skipped: ${errors.first}');
    await _edit(d);
  }

  void _toast(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final decks = store.decks.decks;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Decks'), backgroundColor: t.panel),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Row(children: [
              Expanded(child: ThemedButton('New', icon: Icons.add, onPressed: _new)),
              const SizedBox(width: 8),
              Expanded(child: ThemedButton('Starter', icon: Icons.auto_awesome, outlined: true, onPressed: _starter)),
              const SizedBox(width: 8),
              Expanded(child: ThemedButton('Import', icon: Icons.paste, outlined: true, onPressed: _import)),
            ]),
            const SizedBox(height: 12),
            if (decks.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('No decks yet. Start from a starter deck, import a list, or build one.', style: t.small, textAlign: TextAlign.center)),
            for (final d in decks) _DeckTile(deck: d, onOpen: () => _edit(d), onChanged: () => setState(() {})),
          ]),
        ),
      ),
    );
  }
}

class _DeckTile extends StatelessWidget {
  const _DeckTile({required this.deck, required this.onOpen, required this.onChanged});
  final LorcanaDeck deck;
  final VoidCallback onOpen, onChanged;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final store = LorcanaStore.shared;
    final problems = validateDeck(store.db, deck.cards);
    final inks = deckInks(store.db, deck.cards);
    return Card(
      color: t.panel,
      child: ListTile(
        onTap: onOpen,
        leading: Row(mainAxisSize: MainAxisSize.min, children: [for (final i in inks) Padding(padding: const EdgeInsets.only(right: 2), child: CircleAvatar(radius: 7, backgroundColor: inkColors[i]))]),
        title: Text(deck.name, style: t.style(15, weight: FontWeight.w700)),
        subtitle: Text('${deck.cards.length} cards · ${problems.isEmpty ? 'ready to play' : problems.first}', style: t.style(12, color: problems.isEmpty ? t.ok : t.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'rename':
                final n = await askText(context, 'Rename deck', 'Name', deck.name);
                if (n != null) {
                  deck.name = n;
                  store.decks.save();
                }
              case 'duplicate':
                store.decks.duplicate(deck);
              case 'export':
                if (context.mounted) await showExport(context, deck);
              case 'delete':
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(title: Text('Delete “${deck.name}”?'), actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                  ]),
                );
                if (ok == true) store.decks.delete(deck);
            }
            onChanged();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
            PopupMenuItem(value: 'export', child: Text('Export list')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

/// Edits one deck: counts with +/−, curve, ink split, inkable count, and what makes it illegal.
class LorcanaDeckEditor extends StatefulWidget {
  const LorcanaDeckEditor({super.key, required this.deck});
  final LorcanaDeck deck;
  @override
  State<LorcanaDeckEditor> createState() => _LorcanaDeckEditorState();
}

class _LorcanaDeckEditorState extends State<LorcanaDeckEditor> {
  final store = LorcanaStore.shared;
  LorcanaDeck get deck => widget.deck;

  void _set(String name, int n) {
    setState(() => deck.setCount(name, n.clamp(0, 4)));
    store.decks.save();
  }

  Future<void> _add() async {
    final inks = deckInks(store.db, deck.cards).toSet();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LorcanaCardsScreen(
        title: 'Add cards',
        initial: CardQuery(inks: inks.length == 2 ? inks : null, supportedOnly: true),
        onPick: (c) {
          final n = deck.count(c.fullName);
          if (n < 4) _set(c.fullName, n + 1);
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(duration: const Duration(milliseconds: 900), content: Text('${c.fullName}: ${deck.count(c.fullName)} in the deck')));
        },
      ),
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final db = store.db;
    final problems = validateDeck(db, deck.cards);
    final counts = deck.counts;
    final names = counts.keys.toList()
      ..sort((a, b) {
        final ca = db[a]?.cost ?? 99, cb = db[b]?.cost ?? 99;
        return ca != cb ? ca - cb : a.compareTo(b);
      });
    final curve = List<int>.filled(10, 0);
    final inkSplit = <Ink, int>{};
    var inkable = 0;
    for (final n in deck.cards) {
      final c = db[n];
      if (c == null) continue;
      curve[c.cost.clamp(0, 9)]++;
      if (c.inkable) inkable++;
      for (final i in c.inks) {
        inkSplit[i] = (inkSplit[i] ?? 0) + 1;
      }
    }
    final peak = curve.fold<int>(1, (a, b) => b > a ? b : a);
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: Text(deck.name),
        backgroundColor: t.panel,
        actions: [IconButton(icon: const Icon(Icons.ios_share), tooltip: 'Export list', onPressed: () => showExport(context, deck))],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add cards')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
            ThemedPanel(
              title: problems.isEmpty ? 'Legal: ${deck.cards.length} cards' : '${deck.cards.length} cards: not legal yet',
              color: problems.isEmpty ? t.ok : t.danger,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final p in problems.take(6)) Text('• $p', style: t.style(13, color: t.danger)),
                if (problems.length > 6) Text('…and ${problems.length - 6} more', style: t.small),
                const SizedBox(height: 6),
                Text(
                  [
                    for (final i in Ink.values)
                      if (inkSplit[i] != null) '${i.label} ${inkSplit[i]}',
                    'Inkable $inkable of ${deck.cards.length}',
                  ].join(' · '),
                  style: t.small,
                ),
                const SizedBox(height: 8),
                // Cost curve.
                SizedBox(
                  height: 70,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (var c = 0; c < 10; c++)
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          Text('${curve[c]}', style: t.style(10, color: t.muted)),
                          Container(height: 40 * curve[c] / peak, margin: const EdgeInsets.symmetric(horizontal: 2), color: t.accent),
                          Text(c == 9 ? '9+' : '$c', style: t.style(10, weight: FontWeight.w700)),
                        ]),
                      ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            for (final n in names) _CardRow(name: n, count: counts[n]!, onSet: (v) => _set(n, v)),
          ]),
        ),
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.name, required this.count, required this.onSet});
  final String name;
  final int count;
  final void Function(int) onSet;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final c = LorcanaStore.shared.db[name];
    final supported = c != null && LorcanaParser.parse(c).supported;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: c == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LorcanaCardDetail(card: c))),
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: c == null || c.inks.isEmpty ? Colors.grey : inkColors[c.inks.first],
        child: Text('${c?.cost ?? '?'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ),
      title: Text(name, style: t.style(14, weight: FontWeight.w600, color: supported ? t.text : t.danger), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: supported ? null : Text('Not supported yet', style: t.style(11, color: t.danger)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: const Icon(Icons.remove_circle_outline), tooltip: 'One fewer', onPressed: () => onSet(count - 1)),
        Text('$count', style: t.style(16, weight: FontWeight.w900)),
        IconButton(icon: const Icon(Icons.add_circle_outline), tooltip: 'One more', onPressed: count >= 4 ? null : () => onSet(count + 1)),
      ]),
    );
  }
}

/// Shows the deck as text, with a button to copy it.
Future<void> showExport(BuildContext context, LorcanaDeck deck) {
  final text = formatDeckList(LorcanaStore.shared.db, deck.cards);
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(deck.name),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: SelectableText(text))),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            Navigator.pop(c);
          },
          child: const Text('Copy'),
        ),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
      ],
    ),
  );
}

/// Asks for a line (or block) of text.
Future<String?> askText(BuildContext context, String title, String label, String initial, {bool multiline = false}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(controller: ctl, autofocus: true, minLines: multiline ? 6 : 1, maxLines: multiline ? 14 : 1, decoration: InputDecoration(labelText: label, alignLabelWithHint: true)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(c, ctl.text.trim().isEmpty && !multiline ? null : ctl.text), child: const Text('OK')),
      ],
    ),
  );
}
