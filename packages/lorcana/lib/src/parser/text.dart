/// Turning a card's printed text into ability paragraphs: joins wrapped lines, drops reminder
/// text (CR 1.1.7) and the song reminder, and splits at keywords and story names (CR 5.2.8).
library;

/// A paragraph of rules text: a keyword, or an ability with its story name.
class Paragraph {
  const Paragraph(this.name, this.body, {this.keyword = false});
  final String name;
  final String body;
  final bool keyword;
  String get printed => name.isEmpty ? body : '$name $body';
}

/// The keyword at the start of [s] (CR 8.1.1), with the rest, or null.
final keywordStart = RegExp(
  r'^(alert|bodyguard|evasive|reckless|rush|support|vanish|ward|challenger ?\+\d+|resist ?\+\d+|singer \d+|sing together \d+|boost \d+ ?\{i\}|shift: discard (?:an? [a-z]+ card|\d+ cards)|(?:(?:temporary|universal|duo|combo|potato) )?(?:[a-z]+(?: [a-z]+)? )?shift:? \d+ ?(?:\{i\})?)(?=$|[\s,.:;])',
  caseSensitive: false,
);

String normalizeText(String raw) {
  var t = raw.replaceAll('\r', '').replaceAll('’', "'").replaceAll('‘', "'").replaceAll('“', '"').replaceAll('”', '"').replaceAll('–', '-').replaceAll('—', '-').replaceAll('…', '...');
  // Some texts carry an escaped newline ("\\n") instead of a real one.
  t = t.replaceAll(r'\n', '\n');
  t = t.replaceAll(RegExp(r'\s*\n\s*'), ' ');
  // "1: {i}" is a misprint of "1 {i}" in a few texts.
  t = t.replaceAllMapped(RegExp(r'\b(\d+): (\{i\})', caseSensitive: false), (m) => '${m[1]} ${m[2]}');
  // Reminder text (CR 1.1.7), innermost first.
  for (var i = 0; i < 3; i++) {
    t = t.replaceAll(RegExp(r'\s*\([^()]*\)'), '');
  }
  // The song rule printed as text (CR 5.4.4.2).
  t = t.replaceAll(RegExp(r'-?\s*A character with cost \d+ or more can \{e\} to sing this song for free\.?', caseSensitive: false), '');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.startsWith('- ')) t = t.substring(2);
  return t;
}

bool _isCapsName(String s) {
  final letters = s.replaceAll(RegExp(r'[^A-Za-z]'), '');
  return letters.length >= 2 && letters == letters.toUpperCase();
}

/// Looks for a story name at the start of [s]: "NAME:", "NAME -", "Title Name:", or a run of
/// capitalized words followed by the ability ("SORRY ABOUT THAT When you play…").
(String, int)? storyName(String s) {
  var m = RegExp(r"^([A-Z0-9][^:]{0,60}?)\s*:\s+").firstMatch(s);
  if (m != null && !RegExp(r'^choose ', caseSensitive: false).hasMatch(m.group(1)!) && !m.group(1)!.contains('{')) {
    // "Good Or Evil - Banish this item: …": the name stops before a cost.
    final cut = m.group(1)!.indexOf(' - ');
    if (cut > 0 && _looksLikeCost(m.group(1)!.substring(cut + 3))) return (m.group(1)!.substring(0, cut), cut + 3);
    return (m.group(1)!, m.end);
  }
  m = RegExp(r"^([A-Z][A-Za-z0-9'!?,.& ]{0,60}?)\s+-\s+").firstMatch(s);
  if (m != null && !_looksLikeCost(m.group(1)!)) {
    // "GOOD OR EVIL Banish this item - …": a capitalized name, then a cost.
    final caps = _capsName.firstMatch(s);
    if (caps != null && _isCapsName(caps.group(1)!) && caps.end < m.group(1)!.length && _looksLikeCost(s.substring(caps.end))) return (caps.group(1)!, caps.end);
    return (m.group(1)!, m.end);
  }
  m = _capsName.firstMatch(s);
  if (m != null && _isCapsName(m.group(1)!)) return (m.group(1)!, m.end);
  return null;
}

final _capsName = RegExp(r"^((?:[A-Z0-9'!?,.&\-]+\s+)*[A-Z0-9'!?,.&\-]*[A-Z][A-Z'!?,.&\-]+)\s+(?=[A-Z][a-z]|\{|\d)");

bool _looksLikeCost(String s) {
  final t = s.toLowerCase();
  return t.startsWith('banish ') || t.startsWith('exert ') || t.startsWith('choose and discard') || t.startsWith('discard ') || t.startsWith('{');
}

/// Splits normalized text into paragraphs. Actions have one effect paragraph (CR 5.4.3).
List<Paragraph> splitParagraphs(String text, {required bool action}) {
  final out = <Paragraph>[];
  var rest = text.trim();
  while (rest.isNotEmpty) {
    final kw = keywordStart.firstMatch(rest);
    if (kw != null) {
      out.add(Paragraph('', kw.group(1)!, keyword: true));
      rest = rest.substring(kw.end).replaceFirst(RegExp(r'^[\s,.;:]+'), '');
      continue;
    }
    var name = '';
    if (!action) {
      final sn = storyName(rest);
      if (sn != null) {
        name = sn.$1.trim();
        rest = rest.substring(sn.$2);
      }
    }
    final end = action ? rest.length : _paragraphEnd(rest);
    out.add(Paragraph(name, rest.substring(0, end).trim()));
    rest = rest.substring(end).trim();
  }
  return out;
}

/// Where the ability starting at [s] ends: before a later keyword or story name that follows
/// the end of a sentence.
int _paragraphEnd(String s) {
  for (final m in RegExp(r'[.!?"]\s+').allMatches(s)) {
    final after = s.substring(m.end);
    if (after.isEmpty) break;
    if (keywordStart.hasMatch(after) && _keywordStandsAlone(after)) return m.end;
    final sn = storyName(after);
    if (sn != null) return m.end;
  }
  return s.length;
}

/// A keyword at a sentence start is a new paragraph unless the sentence goes on ("Ward and
/// Evasive this turn" never starts a sentence in practice, but be careful anyway).
bool _keywordStandsAlone(String s) {
  final m = keywordStart.firstMatch(s)!;
  final after = s.substring(m.end).trimLeft();
  return after.isEmpty || keywordStart.hasMatch(after) || storyName(after) != null || after.startsWith('.');
}
