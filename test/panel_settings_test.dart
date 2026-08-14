/// Persisted panel settings.
///
/// The value class is pure Dart, so the round-trip and — more importantly — the
/// clamping run under `dart test`. Stored values reach a motor, so a bad one
/// surviving a load is not a cosmetic problem.
library;

import 'package:test/test.dart';

import '../lib/control/motion_settings.dart';
import '../lib/control/panel_settings.dart';
import '../lib/control/ping_pong.dart';

void main() {
  group('round trip', () {
    test('survives toMap/fromMap unchanged', () {
      const s = PanelSettings(
        motion: MotionSettings(speedPercent: 37, accelPercent: 62),
        settleMs: 850,
        dwellSeconds: 4,
        blindLegSeconds: 12,
        maxLegs: 4,
      );

      final back = PanelSettings.fromMap(s.toMap());

      expect(back.motion.speedPercent, 37);
      expect(back.motion.accelPercent, 62);
      expect(back.settleMs, 850);
      expect(back.dwellSeconds, 4);
      expect(back.blindLegSeconds, 12);
      expect(back.maxLegs, 4);
    });

    test('an empty store gives the defaults', () {
      final s = PanelSettings.fromMap(const {});
      expect(s.motion.speedPercent, const PanelSettings().motion.speedPercent);
      expect(s.settleMs, const PanelSettings().settleMs);
      expect(s.maxLegs, 0);
    });

    test('missing or wrongly typed fields fall back per field', () {
      final s = PanelSettings.fromMap(const {
        'speedPercent': 42.0,
        'settleMs': 'not a number',
        'maxLegs': null,
      });
      expect(s.motion.speedPercent, 42);
      expect(s.settleMs, const PanelSettings().settleMs);
      expect(s.maxLegs, 0);
    });
  });

  group('clamping on load', () {
    test('a stored speed outside 1-100 is brought back into range', () {
      final high = PanelSettings.fromMap(const {'speedPercent': 5000.0});
      final low = PanelSettings.fromMap(const {'speedPercent': -20.0});
      expect(high.motion.speedPercent, 100);
      expect(low.motion.speedPercent, 1);
    });

    test('timings are clamped to their slider ranges', () {
      final s = PanelSettings.fromMap(const {
        'settleMs': 999999.0,
        'dwellSeconds': -5.0,
        'blindLegSeconds': 0.0,
      });
      expect(s.settleMs, PanelSettings.settleMax);
      expect(s.dwellSeconds, PanelSettings.dwellMin);
      expect(s.blindLegSeconds, PanelSettings.blindLegMin);
    });

    test('a negative leg limit becomes unlimited rather than nonsense', () {
      expect(PanelSettings.fromMap(const {'maxLegs': -3}).maxLegs, 0);
    });

    test('non-finite stored values are rejected', () {
      final s = PanelSettings.fromMap({
        'speedPercent': double.nan,
        'settleMs': double.infinity,
      });
      expect(s.motion.speedPercent, const PanelSettings().motion.speedPercent);
      expect(s.settleMs, const PanelSettings().settleMs);
    });
  });

  group('durations', () {
    test('convert as the controller expects', () {
      const s = PanelSettings(
        settleMs: 600,
        dwellSeconds: 2.5,
        blindLegSeconds: 8,
      );
      expect(s.settle, const Duration(milliseconds: 600));
      expect(s.dwell, const Duration(milliseconds: 2500));
      expect(s.blindLeg, const Duration(seconds: 8));
    });

    test('the stored defaults match the controller defaults', () {
      // Guards against the two drifting apart: the panel would silently start
      // overriding the spec-derived values with stale ones.
      expect(PanelSettings.defaultsMatchController, isTrue);
      expect(const PanelSettings().settle, PingPongController.defaultSettle);
      expect(const PanelSettings().blindLeg, PingPongController.defaultBlindLeg);
    });
  });
}
