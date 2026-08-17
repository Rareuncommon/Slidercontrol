/// Synchronised moves: both axes started and stopped from one clock.
///
/// The property that matters is the one the previous, duration-solving approach
/// could not deliver — every axis is commanded on the same tick, from the same
/// normalised time, so they begin and end together by construction rather than
/// by predicting how long each device will take.
///
/// The other property that matters is the safety one: every exit path — normal
/// completion, user stop, lost link, a write that throws, an axis that cannot
/// start at all — neutralises and stops every axis.
library;

import 'dart:async';

import 'package:test/test.dart';

import '../lib/ble/ek_snapshot.dart';
import '../lib/control/motion_settings.dart';
import '../lib/control/sync_move.dart';
import '../lib/ek_protocol.dart';

/// A rail that integrates commanded velocity over wall time.
class FakeRail implements EkMotionTarget {
  FakeRail({int start = 100000, this.reportsPosition = true})
      : _pos = start.toDouble();

  final bool reportsPosition;

  double _pos;
  int _velocity = 0;
  DateTime _last = DateTime.now();
  bool _linkUp = true;

  int stops = 0;
  final velocities = <int>[];

  /// Throws on the setVelocity call with this index, to exercise the failure
  /// path of a write going wrong mid-move.
  int? throwOnCall;

  @override
  EkKind get kind => EkKind.slider;

  void dropLink() => _linkUp = false;

  int get position => _pos.round();

  void _integrate() {
    final now = DateTime.now();
    final dt = now.difference(_last);
    _last = now;
    if (_velocity == 0) return;
    _pos += _velocity * (dt.inMicroseconds / 1e6);
  }

  @override
  EkSnapshot get snapshot {
    _integrate();
    return EkSnapshot(
      link: _linkUp ? EkLinkState.ready : EkLinkState.disconnected,
      kind: EkKind.slider,
      state: _velocity == 0 ? EkState.idle : EkState.manualJog,
      position: reportsPosition ? _pos.round() : null,
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
    if (throwOnCall == velocities.length) {
      throw StateError('write failed');
    }
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

/// A head: accepts velocity, reports nothing back. Exactly what §5 describes.
class FakeHead implements EkMotionTarget {
  bool _linkUp = true;
  int stops = 0;
  final velocities = <int>[];

  @override
  EkKind get kind => EkKind.head;

  void dropLink() => _linkUp = false;

  @override
  EkSnapshot get snapshot => EkSnapshot(
        link: _linkUp ? EkLinkState.ready : EkLinkState.disconnected,
        kind: EkKind.head,
        lastFrameAt: DateTime.now(),
      );

  @override
  Stream<EkSnapshot> get snapshots => const Stream.empty();

  @override
  Future<void> recallPose(int slot, {required MotionSettings settings}) async {}

  @override
  Future<void> savePose(int slot) async {}

  @override
  Future<void> setVelocity(int countsPerSec) async =>
      velocities.add(countsPerSec);

  @override
  Future<void> stopMotion() async => stops++;
}

/// An axis that records what it was asked to do and when, so the tests can
/// prove the two axes really are driven off one clock.
class RecordingAxis implements SyncAxis {
  RecordingAxis(this.name, {required this.target, this.canBegin = true});

  @override
  final String name;

  @override
  final EkMotionTarget target;

  final bool canBegin;

  @override
  Duration get minimumDuration => Duration.zero;

  int begins = 0;
  int ends = 0;
  final steps = <double>[];
  final stepTimes = <DateTime>[];

  @override
  bool begin() {
    begins++;
    return canBegin;
  }

  @override
  Future<void> step(double u, Duration duration) async {
    steps.add(u);
    stepTimes.add(DateTime.now());
  }

  @override
  Future<void> end() async => ends++;
}

void main() {
  group('profile', () {
    test('starts at 0, ends at 1, is halfway at halfway', () {
      expect(syncProfile(0), 0);
      expect(syncProfile(1), 1);
      expect(syncProfile(0.5), closeTo(0.5, 1e-9));
    });

    test('clamps outside 0..1 rather than overshooting', () {
      expect(syncProfile(-1), 0);
      expect(syncProfile(2), 1);
    });

    test('advances monotonically', () {
      var previous = -1.0;
      for (var i = 0; i <= 100; i++) {
        final v = syncProfile(i / 100);
        expect(v, greaterThanOrEqualTo(previous));
        previous = v;
      }
    });

    test('has zero rate at both ends, so nothing jerks', () {
      expect(syncProfileRate(0), 0);
      expect(syncProfileRate(1), 0);
    });

    test('peaks in the middle at the documented rate', () {
      expect(syncProfileRate(0.5), closeTo(syncProfilePeakRate(), 1e-9));
      for (var i = 0; i <= 100; i++) {
        expect(syncProfileRate(i / 100),
            lessThanOrEqualTo(syncProfilePeakRate() + 1e-9));
      }
    });

    test('holds every property at every ramp the accel slider can produce', () {
      for (var percent = 1.0; percent <= 100; percent += 1) {
        final ramp = syncRampForAccel(percent);
        expect(syncProfile(0, ramp: ramp), closeTo(0, 1e-9),
            reason: 'accel $percent');
        expect(syncProfile(1, ramp: ramp), closeTo(1, 1e-9),
            reason: 'accel $percent');
        expect(syncProfile(0.5, ramp: ramp), closeTo(0.5, 1e-9),
            reason: 'accel $percent');
        expect(syncProfileRate(0, ramp: ramp), closeTo(0, 1e-9),
            reason: 'accel $percent');
        expect(syncProfileRate(1, ramp: ramp), closeTo(0, 1e-9),
            reason: 'accel $percent');

        var previous = -1.0;
        for (var i = 0; i <= 200; i++) {
          final v = syncProfile(i / 200, ramp: ramp);
          expect(v, greaterThanOrEqualTo(previous - 1e-9),
              reason: 'accel $percent went backwards');
          previous = v;
        }

        // The rate really is the derivative, at every ramp.
        var area = 0.0;
        const steps = 4000;
        for (var i = 0; i < steps; i++) {
          area += syncProfileRate((i + 0.5) / steps, ramp: ramp) / steps;
        }
        expect(area, closeTo(1.0, 2e-3), reason: 'accel $percent');
      }
    });

    test('more acceleration means a shorter ramp and a lower peak', () {
      final gentle = syncRampForAccel(1);
      final sharp = syncRampForAccel(100);

      expect(gentle, syncRampMax);
      expect(sharp, closeTo(syncRampMin, 1e-9));
      // Short ramps spend longer at cruise, so the peak needed is lower.
      expect(syncProfilePeakRate(ramp: sharp),
          lessThan(syncProfilePeakRate(ramp: gentle)));
    });

    test('a sharp ramp reaches cruise sooner than a gentle one', () {
      final sharp = syncRampForAccel(100);
      final gentle = syncRampForAccel(1);
      // A tenth of the way in, the sharp profile is already at full speed and
      // the gentle one is nowhere near it.
      expect(syncProfileRate(0.1, ramp: sharp),
          closeTo(syncProfilePeakRate(ramp: sharp), 1e-9));
      expect(syncProfileRate(0.1, ramp: gentle),
          lessThan(syncProfilePeakRate(ramp: gentle) * 0.5));
    });

    test('the rate integrates to the profile at the default ramp', () {
      // Sanity check that rate really is the derivative: crude integration
      // over the move should land on 1.
      var area = 0.0;
      const steps = 2000;
      for (var i = 0; i < steps; i++) {
        area += syncProfileRate((i + 0.5) / steps) / steps;
      }
      expect(area, closeTo(1.0, 1e-3));
    });
  });

  group('synchronisation', () {
    test('commands every axis on every tick, at the same normalised time',
        () async {
      final a = RecordingAxis('a', target: FakeRail());
      final b = RecordingAxis('b', target: FakeHead());
      final move = SyncMove(
        axes: [a, b],
        stillRunning: () => true,
        tick: const Duration(milliseconds: 20),
      );

      final outcome = await move.run(const Duration(milliseconds: 300));

      expect(outcome, SyncOutcome.done);
      expect(a.steps.length, b.steps.length);
      expect(a.steps.length, greaterThan(3));
      expect(a.steps, b.steps);
    });

    test('both axes are commanded within a tick of each other, throughout',
        () async {
      final a = RecordingAxis('a', target: FakeRail());
      final b = RecordingAxis('b', target: FakeHead());
      final move = SyncMove(
        axes: [a, b],
        stillRunning: () => true,
        tick: const Duration(milliseconds: 20),
      );

      await move.run(const Duration(milliseconds: 300));

      for (var i = 0; i < a.stepTimes.length; i++) {
        final skew = a.stepTimes[i].difference(b.stepTimes[i]).abs();
        expect(skew, lessThan(const Duration(milliseconds: 20)),
            reason: 'axes drifted apart at tick $i');
      }
    });

    test('starts at 0 and finishes at exactly 1', () async {
      final a = RecordingAxis('a', target: FakeRail());
      final move = SyncMove(
        axes: [a],
        stillRunning: () => true,
        tick: const Duration(milliseconds: 20),
      );

      await move.run(const Duration(milliseconds: 200));

      expect(a.steps.first, closeTo(0.0, 0.15));
      expect(a.steps.last, 1.0);
    });

    test('takes about the duration it was given', () async {
      final a = RecordingAxis('a', target: FakeRail());
      final move = SyncMove(
        axes: [a],
        stillRunning: () => true,
        tick: const Duration(milliseconds: 20),
      );

      final started = DateTime.now();
      await move.run(const Duration(milliseconds: 400));
      final took = DateTime.now().difference(started);

      expect(took, greaterThanOrEqualTo(const Duration(milliseconds: 380)));
      expect(took, lessThan(const Duration(milliseconds: 900)));
    });

    test('a zero duration completes immediately rather than dividing by zero',
        () async {
      final a = RecordingAxis('a', target: FakeRail());
      final move = SyncMove(axes: [a], stillRunning: () => true);

      expect(await move.run(Duration.zero), SyncOutcome.done);
      expect(a.steps, [1.0]);
      expect(a.ends, 1);
    });

    test('no axes is a no-op, not a hang', () async {
      final move = SyncMove(axes: [], stillRunning: () => true);
      expect(await move.run(const Duration(seconds: 10)), SyncOutcome.done);
    });

    test('reports progress as it goes', () async {
      final seen = <double>[];
      final move = SyncMove(
        axes: [RecordingAxis('a', target: FakeRail())],
        stillRunning: () => true,
        tick: const Duration(milliseconds: 20),
        onProgress: (p) => seen.add(p.fraction),
      );

      await move.run(const Duration(milliseconds: 200));

      expect(seen, isNotEmpty);
      expect(seen.last, 1.0);
    });
  });

  group('every exit path stops every axis', () {
    test('normal completion', () async {
      final a = RecordingAxis('a', target: FakeRail());
      final b = RecordingAxis('b', target: FakeHead());
      final move = SyncMove(
        axes: [a, b],
        stillRunning: () => true,
        tick: const Duration(milliseconds: 20),
      );

      expect(await move.run(const Duration(milliseconds: 100)),
          SyncOutcome.done);
      expect(a.ends, 1);
      expect(b.ends, 1);
    });

    test('a stop partway through', () async {
      var running = true;
      final a = RecordingAxis('a', target: FakeRail());
      final b = RecordingAxis('b', target: FakeHead());
      final move = SyncMove(
        axes: [a, b],
        stillRunning: () => running,
        tick: const Duration(milliseconds: 20),
      );

      final run = move.run(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      running = false;

      expect(await run, SyncOutcome.stopped);
      expect(a.ends, 1);
      expect(b.ends, 1);
      // Stopped well before the end, so nothing pretended to finish.
      expect(a.steps.last, lessThan(0.5));
    });

    test('a link that drops mid-move', () async {
      final head = FakeHead();
      final a = RecordingAxis('a', target: FakeRail());
      final b = RecordingAxis('b', target: head);
      final move = SyncMove(
        axes: [a, b],
        stillRunning: () => true,
        tick: const Duration(milliseconds: 20),
      );

      final run = move.run(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      head.dropLink();

      expect(await run, SyncOutcome.linkLost);
      expect(a.ends, 1);
      expect(b.ends, 1);
    });

    test('a write that throws', () async {
      final rail = FakeRail();
      final head = FakeHead();
      final move = SyncMove(
        axes: [
          SliderSyncAxis(target: rail, targetCounts: 200000),
          HeadSyncAxis(target: head, peakVelocity: 4000),
        ],
        stillRunning: () => true,
        tick: const Duration(milliseconds: 20),
      );

      rail.throwOnCall = 2;
      expect(await move.run(const Duration(seconds: 2)), SyncOutcome.failed);

      // Both motors are left neutralised even though one link is misbehaving.
      expect(rail.stops, greaterThanOrEqualTo(1));
      expect(head.stops, greaterThanOrEqualTo(1));
      expect(head.velocities.last, 0);
    });

    test('an axis that cannot start', () async {
      final good = RecordingAxis('good', target: FakeHead());
      final bad = RecordingAxis('bad', target: FakeRail(), canBegin: false);
      final move = SyncMove(axes: [good, bad], stillRunning: () => true);

      expect(await move.run(const Duration(seconds: 1)), SyncOutcome.failed);
      expect(good.steps, isEmpty);
      // Neutralised anyway — an axis that failed to start may still have been
      // left moving by something else.
      expect(good.ends, 1);
      expect(bad.ends, 1);
    });
  });

  group('slider axis', () {
    test('refuses to start without a position to close the loop against', () {
      final axis = SliderSyncAxis(
        target: FakeRail(reportsPosition: false),
        targetCounts: 200000,
      );
      expect(axis.begin(), isFalse);
    });

    test('drives the carriage to its target', () async {
      final rail = FakeRail(start: 100000);
      // At the default ramp the peak is twice the average, so 10,000 counts in
      // 1.2 s peaks at ~16,700 counts/sec — inside the 18,000 ceiling.
      final move = SyncMove(
        axes: [SliderSyncAxis(target: rail, targetCounts: 110000)],
        stillRunning: () => true,
        tick: const Duration(milliseconds: 20),
      );

      expect(await move.run(const Duration(milliseconds: 1200)),
          SyncOutcome.done);
      // Within 1% of a 10,000-count move.
      expect((rail.position - 110000).abs(), lessThan(100));
    });

    test('starts and finishes at a standstill', () async {
      final rail = FakeRail(start: 100000);
      final move = SyncMove(
        axes: [SliderSyncAxis(target: rail, targetCounts: 104000)],
        stillRunning: () => true,
        tick: const Duration(milliseconds: 20),
      );

      await move.run(const Duration(milliseconds: 400));

      expect(rail.velocities.first.abs(), lessThan(3000));
      expect(rail.velocities.last, 0);
    });

    test('reports the shortest duration it can honestly manage', () {
      final axis = SliderSyncAxis(
        target: FakeRail(start: 0),
        targetCounts: 480000,
        maxVelocity: 18000,
      );
      // 480,000 counts peaking at 2x the average needs 53.3 s at 18,000/sec.
      expect(axis.minimumDuration.inMilliseconds, closeTo(53334, 50));
    });

    test('the fleet minimum is the slowest axis, and the head does not vote',
        () {
      final move = SyncMove(
        axes: [
          SliderSyncAxis(
            target: FakeRail(start: 0),
            targetCounts: 120000,
            maxVelocity: 18000,
          ),
          HeadSyncAxis(target: FakeHead(), peakVelocity: 30000),
        ],
        stillRunning: () => true,
      );
      expect(move.minimumDuration.inMilliseconds, closeTo(13334, 50));
    });

    test('never exceeds its velocity ceiling', () async {
      final rail = FakeRail(start: 0);
      final move = SyncMove(
        axes: [
          SliderSyncAxis(
            target: rail,
            targetCounts: 480000,
            maxVelocity: 12000,
          ),
        ],
        stillRunning: () => true,
        tick: const Duration(milliseconds: 20),
      );

      await move.run(const Duration(milliseconds: 300));

      for (final v in rail.velocities) {
        expect(v.abs(), lessThanOrEqualTo(12000));
      }
    });

    test('a negative velocity sign inverts what goes on the wire', () async {
      // A rail whose counter runs backwards relative to commanded velocity;
      // only the sign convention differs, the move is the same.
      final rail = FakeRail(start: 100000);
      final axis = SliderSyncAxis(
        target: rail,
        targetCounts: 140000,
        velocitySign: -1,
      );
      axis.begin();
      await axis.step(0.5, const Duration(seconds: 1));

      expect(rail.velocities.single, lessThan(0));
    });

    test('a move to where it already is commands nothing much', () async {
      final rail = FakeRail(start: 100000);
      final move = SyncMove(
        axes: [SliderSyncAxis(target: rail, targetCounts: 100000)],
        stillRunning: () => true,
        tick: const Duration(milliseconds: 20),
      );

      await move.run(const Duration(milliseconds: 200));

      for (final v in rail.velocities) {
        expect(v.abs(), lessThan(500));
      }
    });
  });

  group('head axis', () {
    test('shapes velocity to the profile and returns to zero', () async {
      final head = FakeHead();
      final move = SyncMove(
        axes: [HeadSyncAxis(target: head, peakVelocity: 6000)],
        stillRunning: () => true,
        tick: const Duration(milliseconds: 20),
      );

      await move.run(const Duration(milliseconds: 400));

      expect(head.velocities.first.abs(), lessThan(1500));
      expect(head.velocities.last, 0);
      expect(head.velocities.map((v) => v.abs()).reduce((a, b) => a > b ? a : b),
          lessThanOrEqualTo(6000));
    });

    test('a negative peak drives the other way', () async {
      final head = FakeHead();
      final axis = HeadSyncAxis(target: head, peakVelocity: -6000);
      axis.begin();
      await axis.step(0.5, const Duration(seconds: 1));

      expect(head.velocities.single, -6000);
    });

    test('needs nothing from the device to start, since it reports nothing',
        () {
      expect(HeadSyncAxis(target: FakeHead(), peakVelocity: 1000).begin(),
          isTrue);
    });
  });
}
