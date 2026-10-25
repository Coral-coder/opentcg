import 'package:flutter_test/flutter_test.dart';
import 'package:opentcg/lorcana/lorcana_card.dart';

void main() {
  test('image keys match tool/lorcana_images.py', () {
    // Values printed by the Python tool's key().
    expect(lorcanaImageKey('Mickey Mouse - Brave Little Tailor'), 'b7ef05c6');
    expect(lorcanaImageKey('4*Town - Hottest Band of the Year'), 'ddc563e9');
    expect(lorcanaImageKey("Maui's Place of Exile - Hidden Island"), 'b4dc9af0');
    expect(lorcanaImageKey('Pokémon é'), 'edaf0a83');
  });
}
