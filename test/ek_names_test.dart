/// Device recognition. Pure Dart, so it runs under `dart test` alongside the
/// protocol tests with no Flutter binding and no hardware.
library;

import 'package:test/test.dart';

import '../lib/ble/ek_names.dart';
import '../lib/ek_protocol.dart';

void main() {
  group('recognising edelkrone devices', () {
    test('accepts the two advertised names from the spec', () {
      expect(isEdelkroneName('SldrPlsV1'), isTrue);
      expect(isEdelkroneName('HeadOneFM'), isTrue);
    });

    test('is case-insensitive and tolerates a suffix', () {
      expect(isEdelkroneName('sldrplsv1'), isTrue);
      expect(isEdelkroneName('SLDRPLSV1'), isTrue);
      expect(isEdelkroneName('HeadOneFM-2'), isTrue);
    });

    test('rejects unrelated peripherals', () {
      // The point of this gate. EkProfile.forName would call every one of these
      // a slider, because it defaults to slider for anything without "head".
      for (final name in [
        'AirPods Pro',
        'MX Master 3',
        'Tile',
        '',
        'Slider', // a different manufacturer's slider
        'HeadPhones', // contains "head", but is not a HeadONE
      ]) {
        expect(isEdelkroneName(name), isFalse, reason: 'should reject "$name"');
      }
    });

    test('rejects a null name', () {
      expect(isEdelkroneName(null), isFalse);
    });

    test('recognised names then map to the right profile', () {
      // Recognition and profile selection are two separate steps; this is the
      // handoff between them.
      expect(EkProfile.forName('SldrPlsV1').kind, EkKind.slider);
      expect(EkProfile.forName('HeadOneFM').kind, EkKind.head);
    });
  });
}
