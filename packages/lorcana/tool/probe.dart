/// Parses ability text as a card's and prints the result with diagnostics, for working on the
/// parser: dart run tool/probe.dart "character" "When you play this character, ..." [...]
library;

import 'package:lorcana/lorcana.dart';

void main(List<String> args) {
  final type = CardType.values.byName(args.first);
  var i = 0;
  for (final text in args.skip(1)) {
    LorcanaParser.clearCache();
    LorcanaParser.diag = [];
    final p = LorcanaParser.parse(LCard(fullName: 'Probe - ${i++}', type: type, cost: 3, inkable: true, inks: const [Ink.amber], strength: 2, willpower: 3, lore: 1, text: text));
    print(text);
    for (final a in p.abilities) {
      print('  = ${describeAbility(a)}');
    }
    print(p.supported ? '  SUPPORTED' : '  UNSUPPORTED ${LorcanaParser.diag}');
  }
}
