/// Homing, against a simulated rail.
///
/// The two behaviours worth proving are the ones the reference Python had to
/// learn the hard way on this hardware:
///
///  - encoder dither against a hard stop must not defeat stall detection, and
///  - the SliderPLUS's mid-rail mechanism transition must not be mistaken for
///    an end stop.
///
/// Both are simulated here, so the logic is exercised without driving a real
/// carriage into a real stop.
library;

import 'dart:async';

import 'package:test/test.dart';

import '../lib/ble/ek_snapshot.dart';
import '../lib/control/homing.dart';
import '../lib/control/motion_settings.dart';
import '../lib/ek_protocol.dart';

/// A rail that integrates commanded velocity over wall time.
class FakeRail implements EkMotionTarget {
  FakeRail({
    this.lo = 0,
    this.hi = 400000,
    int start = 200000,
    this.stickyAt,
    this.stickyWidth = 8000,
    this.stickyHold = const Duration(milliseconds: 400),
    this.dither = 150,
  })  : _pos = start.toDouble(),
        _stickyLeft = stickyHold;

  final int lo;
  final int hi;

  /// A zone that pauses progress once, then never again — the mid-rail
  /// mechanism transition that imitates an end stop.
  final int? stickyAt;
  final int stickyWidth;
  final Duration stickyHold;

  /// Counts of encoder noise while pressed against a stop. Alternating rather
  /// than random so the tests are deterministic.
  final int dither;

  double _pos;
  int _velocity = 0;
  DateTime _last = DateTime.now();
  Duration _stickyLeft;
  bool _ditherUp = false;
  bool _linkUp = true;

  int stops = 0;
  final velocities = <int>[];

  @override
  EkKind get kind => EkKind.slider;

  void dropLink() => _linkUp = false;

  void _integrate() {
    final now = DateTime.now();
    final dt = now.difference(_last);
    _last = now;
    if (_velocity == 0) return;

    var seconds = dt.inMicroseconds / 1e6;

    // The sticky zone consumes time without producing motion, once.
    if (stickyAt != null && _stickyLeft > Duration.zero) {
      final inZone = (_pos - stickyAt!).abs() < stickyWidth;
      if (inZone) {
        final consumed = dt < _stickyLeft ? dt : _stickyLeft;
        _stickyLeft -= consumed;
        seconds -= consumed.inMicroseconds / 1e6;
        if (seconds <= 0) return;
      }
    }

    _pos += _velocity * seconds;

    // Hard stops: the carriage cannot pass, but the encoder still twitches.
    if (_pos <= lo || _pos >= hi) {
      _pos = _pos <= lo ? lo.toDouble() : hi.toDouble();
      _ditherUp = !_ditherUp;
      _pos += _ditherUp ? dither : -dither;
    }
  }

  @override
  EkSnapshot get snapshot {
    _integrate();
    return EkSnapshot(
      link: _linkUp ? EkLinkState.ready : EkLinkState.disconnected,
      kind: EkKind.slider,
      state: _velocity == 0 ? EkState.idle : EkState.manualJog,
      position: _pos.round(),
      lastFrameAt: DateTime.now(),
    );
  }

  @override
  Stream<EkSnapshot> get snapshots => const Stream.empty();

  @override
  Future<void> recallPose(int slot, {required MotionSettings settings}) async {}

  @override
  Future<void> savePose(int slot) async {}

  @override
  Future<void> setVelocity(int countsPerSec) async {
    _integrate();
    velocities.add(countsPerSec);
    _velocity = countsPerSec;
  }

  @override
  Future<void> stopMotion() async {
    _integrate();
    _velocity = 0;
    stops++;
  }
}

class FakeHead implements EkMotionTarget {
  @override
  EkKind get kind => EkKind.head;
  @override
  EkSnapshot get snapshot =>
      EkSnapshot(link: EkLinkState.ready, kind: EkKind.head,
          lastFrameAt: DateTime.now());
  @override
  Stream<EkSnapshot> get snapshots => const Stream.empty();
  @override
  Future<void> recallPose(int slot, {required MotionSettings settings}) async {}
  @override
  Future<void> savePose(int slot) async {}
  @override
  Future<void> setVelocity(int countsPerSec) async {}
  @override
  Future<void> stopMotion() async {}
}

/// Fast enough to keep the suite quick; the logic is velocity-independent
/// because every threshold scales with the commanded speed.
Homing quickHoming(
  EkMotionTarget target, {
  bool Function()? stillRunning,
  int railTravel = 400000,
  void Function(HomingProgress)? onProgress,
}) {
  return Homing(
    target: target,
    stillRunning: stillRunning ?? () => true,
    onProgress: onProgress,
    tick: const Duration(milliseconds: 10),
    railTravelCounts: railTravel,
    fastVelocity: 400000,
    slowVelocity: 120000,
    spinUp: const Duration(milliseconds: 120),
  );
}

void main() {
  group('the head is never homed', () {
    test('homeSingle refuses a head target', () async {
      final h = quickHoming(FakeHead());
      await expectLater(
        h.homeSingle(),
        throwsA(isA<HomingAborted>().having(
            (e) => e.reason, 'reason', contains('does not apply to the head'))),
      );
    });

    test('moveTo refuses a head target', () async {
      final h = quickHoming(FakeHead());
      await expectLater(
        h.moveTo(0, const RailDatum(endLo: 0, endHi: 1000, velocitySign: 1)),
        throwsA(isA<HomingAborted>()),
      );
    });
  });

  group('finding an end', () {
    test('stops at the mechanical end despite encoder dither', () async {
      // A fixed per-tick threshold would be defeated by the dither; net
      // progress over the window is not.
      final rail = FakeRail(lo: 0, hi: 400000, start: 380000, dither: 150);
      final h = quickHoming(rail);

      final datum = await h.homeSingle();

      expect(datum.travel, 400000);
      // Landed on the high end, within dither plus the settling tolerance.
      expect(datum.endHi, closeTo(400000, 3000));
      expect(rail.stops, greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('velocity zero is always sent before the stop', () async {
      final rail = FakeRail(lo: 0, hi: 400000, start: 390000);
      final h = quickHoming(rail);
      await h.homeSingle();

      expect(rail.velocities.last, 0,
          reason: 'the carriage must be neutralised, not just stopped');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a mid-rail false stall is not mistaken for an end', () async {
      // The SliderPLUS pauses during its mechanism transition. Backing off and
      // re-approaching is what tells the two apart.
      final rail = FakeRail(
        lo: 0,
        hi: 400000,
        start: 100000,
        stickyAt: 200000,
        stickyHold: const Duration(milliseconds: 400),
      );
      var sawFalseStall = false;
      final h = quickHoming(
        rail,
        onProgress: (p) {
          if (p.message.contains('false stall')) sawFalseStall = true;
        },
      );

      final datum = await h.homeSingle();

      expect(sawFalseStall, isTrue,
          reason: 'the sticky zone should be recognised and driven through');
      // It must have carried on to the real end, not stopped at the sticky zone.
      expect(datum.endHi, greaterThan(350000));
    }, timeout: const Timeout(Duration(seconds: 90)));
  });

  group('bounds', () {
    test('a rail longer than configured aborts on the travel budget', () async {
      // Configured for 20k but actually 400k: it must give up rather than grind
      // along forever.
      final rail = FakeRail(lo: 0, hi: 400000, start: 0);
      final h = quickHoming(rail, railTravel: 20000);

      await expectLater(
        h.homeSingle(),
        throwsA(isA<HomingAborted>()
            .having((e) => e.reason, 'reason', contains('travel budget'))),
      );
      expect(rail.stops, greaterThan(0),
          reason: 'an abort must still stop the motor');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a dropped link aborts immediately and stops the motor', () async {
      final rail = FakeRail(lo: 0, hi: 400000, start: 100000);
      final h = quickHoming(rail);

      final run = h.homeSingle();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      rail.dropLink();

      await expectLater(
        run,
        throwsA(isA<HomingAborted>()
            .having((e) => e.reason, 'reason', contains('link'))),
      );
      expect(rail.stops, greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a stop request aborts mid-pass', () async {
      final rail = FakeRail(lo: 0, hi: 400000, start: 100000);
      var running = true;
      final h = quickHoming(rail, stillRunning: () => running);

      final run = h.homeSingle();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      running = false;

      await expectLater(run, throwsA(isA<HomingAborted>()));
      final after = rail.velocities.length;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(rail.velocities.length, after,
          reason: 'nothing may be commanded after an abort');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('closed-loop moves', () {
    test('converges on a target within tolerance', () async {
      final rail = FakeRail(lo: 0, hi: 400000, start: 100000);
      final h = quickHoming(rail);
      const datum = RailDatum(endLo: 0, endHi: 400000, velocitySign: 1);

      final ok = await h.moveTo(250000, datum);

      expect(ok, isTrue);
      expect(rail.snapshot.position, closeTo(250000, moveTolerance * 2));
      expect(rail.velocities.last, 0);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('respects the soft margin rather than driving into a stop', () async {
      final rail = FakeRail(lo: 0, hi: 400000, start: 100000);
      final h = quickHoming(rail);
      const datum = RailDatum(endLo: 0, endHi: 400000, velocitySign: 1);

      await h.moveTo(-50000, datum);

      expect(rail.snapshot.position, greaterThanOrEqualTo(softMargin - 1000));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('travel fractions', () {
    test('round-trip between counts and fractions', () {
      const datum =
          RailDatum(endLo: 1000, endHi: 481000, velocitySign: -1);
      expect(datum.travel, 480000);
      expect(datum.fractionToCounts(0), 1000);
      expect(datum.fractionToCounts(1), 481000);
      expect(datum.fractionToCounts(0.5), 241000);
      expect(datum.countsToFraction(241000), closeTo(0.5, 0.001));
    });

    test('fractions are clamped, so a stale value cannot aim off the rail', () {
      const datum = RailDatum(endLo: 0, endHi: 100000, velocitySign: 1);
      expect(datum.fractionToCounts(5.0), 100000);
      expect(datum.fractionToCounts(-2.0), 0);
      expect(datum.countsToFraction(999999), 1.0);
    });

    test('soft clamping keeps a target clear of both ends', () {
      const datum = RailDatum(endLo: 0, endHi: 100000, velocitySign: 1);
      expect(datum.clampSoft(0), softMargin);
      expect(datum.clampSoft(100000), 100000 - softMargin);
      expect(datum.clampSoft(50000), 50000);
    });
  });
}
