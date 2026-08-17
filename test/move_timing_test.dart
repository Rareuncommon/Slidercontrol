/// Duration matching between the two axes.
///
/// The model is the one §7b establishes: the speed field is a period, derived
/// as `320 × 100 / percent`, so a move's duration is proportional to the period
/// and inversely proportional to the percentage.
library;

import 'package:test/test.dart';

import '../lib/control/move_timing.dart';

void main() {
  _headDialTests();

  group('slider timing', () {
    test('learns a rate from an observed move', () {
      // 100,000 counts in 10 s at 50% → 200 counts/sec at 1%.
      final t = SliderTiming.fromObservation(
        counts: 100000,
        duration: const Duration(seconds: 10),
        percent: 50,
      )!;
      expect(t.countsPerSecondPerPercent, closeTo(200, 0.01));
    });

    test('ignores observations too small to mean anything', () {
      // A short hop or a fast blip says more about latency than about speed.
      expect(
        SliderTiming.fromObservation(
            counts: 500,
            duration: const Duration(seconds: 5),
            percent: 50),
        isNull,
      );
      expect(
        SliderTiming.fromObservation(
            counts: 50000,
            duration: const Duration(milliseconds: 100),
            percent: 50),
        isNull,
      );
    });

    test('direction does not matter', () {
      final forward = SliderTiming.fromObservation(
          counts: 80000, duration: const Duration(seconds: 8), percent: 40)!;
      final back = SliderTiming.fromObservation(
          counts: -80000, duration: const Duration(seconds: 8), percent: 40)!;
      expect(forward.countsPerSecondPerPercent,
          closeTo(back.countsPerSecondPerPercent, 1e-9));
    });

    test('solves for the percentage that hits a target duration', () {
      const t = SliderTiming(countsPerSecondPerPercent: 200);
      // 100,000 counts in 5 s needs 20,000 counts/sec → 100%.
      final solved = t.solve(100000, const Duration(seconds: 5));
      expect(solved.percent, closeTo(100, 0.01));
      expect(solved.clamped, isFalse);
      expect(solved.predicted.inMilliseconds, closeTo(5000, 50));
    });

    test('the solved percentage really does reproduce the target', () {
      const t = SliderTiming(countsPerSecondPerPercent: 355);
      for (final counts in [12000, 90000, 240000]) {
        for (final seconds in [2, 6, 15]) {
          final target = Duration(seconds: seconds);
          final solved = t.solve(counts, target);
          if (solved.clamped) continue;
          expect(solved.predicted.inMilliseconds,
              closeTo(target.inMilliseconds, target.inMilliseconds * 0.02),
              reason: '$counts counts in ${seconds}s');
        }
      }
    });

    test('reports when a target is out of reach rather than silently missing it',
        () {
      const t = SliderTiming(countsPerSecondPerPercent: 200);
      // Far too fast: would need well over 100%.
      final tooFast = t.solve(500000, const Duration(seconds: 1));
      expect(tooFast.percent, 100);
      expect(tooFast.clamped, isTrue);
      expect(tooFast.predicted.inSeconds, greaterThan(1));

      // Far too slow: would need under 1%.
      final tooSlow = t.solve(1000, const Duration(seconds: 600));
      expect(tooSlow.percent, 1);
      expect(tooSlow.clamped, isTrue);
    });
  });

  group('head timing', () {
    test('scales duration inversely with percentage, per §7b', () {
      const t = HeadTiming(
        referenceDuration: Duration(seconds: 10),
        referencePercent: 50,
      );
      // Doubling the percentage halves the duration.
      expect(t.durationAt(100).inMilliseconds, closeTo(5000, 10));
      expect(t.durationAt(25).inMilliseconds, closeTo(20000, 20));
    });

    test('solves for a target duration', () {
      const t = HeadTiming(
        referenceDuration: Duration(seconds: 8),
        referencePercent: 40,
      );
      final solved = t.solve(const Duration(seconds: 4));
      expect(solved.percent, closeTo(80, 0.01));
      expect(solved.clamped, isFalse);
      expect(solved.predicted.inMilliseconds, closeTo(4000, 40));
    });

    test('reports an unreachable target', () {
      const t = HeadTiming(
        referenceDuration: Duration(seconds: 60),
        referencePercent: 50,
      );
      final solved = t.solve(const Duration(milliseconds: 500));
      expect(solved.percent, 100);
      expect(solved.clamped, isTrue);
    });

    test('a calibration is tied to the poses it was measured between', () {
      // The head reports no position (§5), so there is no way to know how far
      // apart two poses are — a calibration cannot transfer to a different pair.
      const t = HeadTiming(
        referenceDuration: Duration(seconds: 5),
        referencePercent: 50,
        measuredForSlots: [0, 1],
      );
      expect(t.appliesTo([0, 1]), isTrue);
      expect(t.appliesTo([1, 0]), isTrue, reason: 'order should not matter');
      expect(t.appliesTo([0, 2]), isFalse);
      expect(t.appliesTo([0, 1, 2]), isFalse);
    });
  });

  group('both axes land on the same duration', () {
    test('the solved settings predict equal times', () {
      const slider = SliderTiming(countsPerSecondPerPercent: 300);
      const head = HeadTiming(
        referenceDuration: Duration(seconds: 12),
        referencePercent: 50,
      );
      const target = Duration(seconds: 6);

      final s = slider.solve(120000, target);
      final h = head.solve(target);

      expect(s.clamped, isFalse);
      expect(h.clamped, isFalse);
      expect(
        (s.predicted - h.predicted).inMilliseconds.abs(),
        lessThan(100),
        reason: 'the two axes must be predicted to finish together',
      );
    });
  });

  group('persistence', () {
    test('round-trips', () {
      const t = MoveTiming(
        slider: SliderTiming(countsPerSecondPerPercent: 412.5),
        head: HeadTiming(
          referenceDuration: Duration(milliseconds: 7300),
          referencePercent: 35,
          measuredForSlots: [0, 1],
        ),
        shotSeconds: 8.5,
      );
      final back = MoveTiming.decode(t.encode());
      expect(back.slider!.countsPerSecondPerPercent, closeTo(412.5, 1e-9));
      expect(back.head!.referenceDuration.inMilliseconds, 7300);
      expect(back.head!.referencePercent, 35);
      expect(back.head!.measuredForSlots, [0, 1]);
      expect(back.shotSeconds, 8.5);
      expect(back.matchDurations, isTrue);
    });

    test('a corrupt or empty store gives usable defaults', () {
      for (final raw in [null, '', 'not json', '[]', '{}']) {
        final t = MoveTiming.decode(raw);
        expect(t.sliderCalibrated, isFalse);
        expect(t.headCalibrated, isFalse);
        expect(t.shotSeconds, greaterThan(0));
      }
    });

    test('nonsense calibrations are dropped rather than used', () {
      // A zero or negative rate would divide by zero when solving.
      expect(SliderTiming.fromJson(const {'countsPerSecondPerPercent': 0}),
          isNull);
      expect(SliderTiming.fromJson(const {'countsPerSecondPerPercent': -5}),
          isNull);
      expect(HeadTiming.fromJson(const {'referenceMs': 0, 'referencePercent': 50}),
          isNull);
    });

    test('the shot duration is clamped on load', () {
      final t = MoveTiming.decode('{"shotSeconds": 99999}');
      expect(t.shotSeconds, MoveTiming.maxShotSeconds);
    });
  });
}

void _headDialTests() {
  group('the head dial', () {
    test('one number at full speed solves every shot duration', () {
      // The head takes half a second flat out. §7b's period model says half
      // the percentage is twice the time, so a 5 s leg wants 10%.
      final t = const MoveTiming(shotSeconds: 5)
          .withHeadAtFullSpeed(const Duration(milliseconds: 500));

      expect(t.headAtFullSpeed, const Duration(milliseconds: 500));
      expect(t.headSolvedPercent, closeTo(10, 0.01));
      expect(t.headTooFastForShot, isFalse);
    });

    test('applies to any pose pair, unlike a stopwatch measurement', () {
      final t = const MoveTiming()
          .withHeadAtFullSpeed(const Duration(milliseconds: 500));
      expect(t.head!.appliesTo([0, 1]), isTrue);
      expect(t.head!.appliesTo([3, 7, 9]), isTrue);
    });

    test('flags a shot the head cannot be slowed enough to fill', () {
      // Flat out it takes 0.5 s, so even 1% only stretches it to 50 s.
      final ok = const MoveTiming(shotSeconds: 50)
          .withHeadAtFullSpeed(const Duration(milliseconds: 500));
      expect(ok.headTooFastForShot, isFalse);

      final tooLong = const MoveTiming(shotSeconds: 90)
          .withHeadAtFullSpeed(const Duration(milliseconds: 500));
      expect(tooLong.headTooFastForShot, isTrue);
    });

    test('survives a round trip through storage', () {
      final t = const MoveTiming(shotSeconds: 8)
          .withHeadAtFullSpeed(const Duration(milliseconds: 1500));
      final back = MoveTiming.decode(t.encode());

      expect(back.headAtFullSpeed, const Duration(milliseconds: 1500));
      expect(back.headSolvedPercent, closeTo(t.headSolvedPercent!, 0.01));
    });

    test('no reference means no solved percentage, rather than a guess', () {
      expect(const MoveTiming().headSolvedPercent, isNull);
      expect(const MoveTiming().headTooFastForShot, isFalse);
    });
  });
}
