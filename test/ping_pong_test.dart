/// Supervised ping-pong, driven against a fake device.
///
/// Pure Dart, so it runs under `dart test`. The timings are scaled down from
/// the real ones (a 60 ms settle rather than 600 ms) so the suite stays fast;
/// the logic under test is identical.
library;

import 'dart:async';

import 'package:test/test.dart';

import '../lib/ble/ek_snapshot.dart';
import '../lib/control/ping_pong.dart';
import '../lib/ek_protocol.dart';

/// A device that records what it was told and reports whatever state the test
/// sets. Stands in for EkConnection.
class FakeDevice implements EkMotionTarget {
  FakeDevice(this.kind, {EkState state = EkState.idle})
      : _snapshot = EkSnapshot(
          link: EkLinkState.ready,
          kind: kind,
          state: state,
          lastFrameAt: DateTime.now(),
        );

  @override
  final EkKind kind;

  EkSnapshot _snapshot;
  final _controller = StreamController<EkSnapshot>.broadcast();

  final recalls = <int>[];
  int stops = 0;

  /// Set to make the next recall throw.
  Object? failNextRecall;

  @override
  EkSnapshot get snapshot => _snapshot.copyWith(lastFrameAt: DateTime.now());

  @override
  Stream<EkSnapshot> get snapshots => _controller.stream;

  @override
  Future<void> recallPose(int slot, {required MotionParams motion}) async {
    final f = failNextRecall;
    if (f != null) {
      failNextRecall = null;
      throw f;
    }
    recalls.add(slot);
  }

  @override
  Future<void> stopMotion() async => stops++;

  void setState(EkState s) {
    _snapshot = _snapshot.copyWith(state: s, lastFrameAt: DateTime.now());
    _controller.add(_snapshot);
  }

  void dropLink() {
    _snapshot = _snapshot.copyWith(link: EkLinkState.disconnected);
    _controller.add(_snapshot);
  }

  Future<void> close() => _controller.close();
}

/// Drives a fake slider through a realistic move: idle, then moving, then idle.
Future<void> completeAMove(
  FakeDevice d, {
  Duration moving = const Duration(milliseconds: 40),
}) async {
  d.setState(EkState.keyposeMove);
  await Future<void>.delayed(moving);
  d.setState(EkState.idle);
}

void main() {
  final motion = MotionParams.fromPercent(50, EkKind.slider);
  const settle = Duration(milliseconds: 60);
  const grace = Duration(milliseconds: 200);

  group('supervised ping-pong on the slider', () {
    test('alternates slots, one recall per leg', () async {
      final d = FakeDevice(EkKind.slider);
      final c = PingPongController(target: d);

      unawaited(c.start(motion: motion, settle: settle, launchGrace: grace));

      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await completeAMove(d);
        await Future<void>.delayed(settle + const Duration(milliseconds: 60));
      }
      await c.stop();

      expect(d.recalls.length, greaterThanOrEqualTo(4));
      // Slots must alternate 0,1,0,1… — never the same pose twice running.
      for (var i = 1; i < d.recalls.length; i++) {
        expect(d.recalls[i], isNot(d.recalls[i - 1]),
            reason: 'recalls were ${d.recalls}');
      }
      expect(d.recalls.first, 0);
      await d.close();
    });

    test('does not call a leg finished the instant it sees idle', () async {
      // The state byte reads idle in the gap between the recall being written
      // and the motor starting. A bare "is it idle?" check would advance
      // immediately and fire the next recall on top of a moving device.
      final d = FakeDevice(EkKind.slider, state: EkState.idle);
      final c = PingPongController(target: d);

      unawaited(c.start(motion: motion, settle: settle, launchGrace: grace));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Still idle, well inside the launch grace: exactly one recall so far.
      expect(d.recalls.length, 1);

      await c.stop();
      await d.close();
    });

    test('idle must hold continuously — a flicker back to moving resets it',
        () async {
      final d = FakeDevice(EkKind.slider);
      final c = PingPongController(target: d);

      unawaited(c.start(motion: motion, settle: settle, launchGrace: grace));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      d.setState(EkState.keyposeMove);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Idle for most of the settle window, then moving again.
      d.setState(EkState.idle);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      d.setState(EkState.keyposeMove);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // The settle clock restarted, so the leg has not completed.
      expect(d.recalls.length, 1);

      await c.stop();
      await d.close();
    });

    test('a recall to a pose already reached still completes', () async {
      // The device never reports motion, so only the launch grace expiring
      // lets the leg finish. Without that the loop would hang forever.
      final d = FakeDevice(EkKind.slider, state: EkState.idle);
      final c = PingPongController(target: d);

      unawaited(c.start(motion: motion, settle: settle, launchGrace: grace));
      await Future<void>.delayed(grace + settle + const Duration(milliseconds: 150));
      await c.stop();

      expect(d.recalls.length, greaterThanOrEqualTo(2),
          reason: 'launch grace should let a no-op recall complete');
      await d.close();
    });
  });

  group('stopping', () {
    test('stop() sends the stop command and halts the loop', () async {
      final d = FakeDevice(EkKind.slider);
      final c = PingPongController(target: d);

      unawaited(c.start(motion: motion, settle: settle, launchGrace: grace));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await c.stop();

      expect(d.stops, greaterThan(0));
      expect(c.isRunning, isFalse);

      final after = d.recalls.length;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(d.recalls.length, after, reason: 'no recalls after stop');
      await d.close();
    });

    test('a lost link stops the motor and ends the loop', () async {
      final d = FakeDevice(EkKind.slider);
      final c = PingPongController(target: d);

      final run = c.start(motion: motion, settle: settle, launchGrace: grace);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      d.setState(EkState.keyposeMove);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      d.dropLink();
      await run;

      expect(c.status.phase, PingPongPhase.failed);
      expect(c.status.error, contains('link'));
      expect(d.stops, greaterThan(0),
          reason: 'a stop must go out even when the link drops');
      await d.close();
    });

    test('a throwing recall still stops the motor', () async {
      final d = FakeDevice(EkKind.slider)..failNextRecall = StateError('boom');
      final c = PingPongController(target: d);

      await c.start(motion: motion, settle: settle, launchGrace: grace);

      expect(c.status.phase, PingPongPhase.failed);
      expect(d.stops, greaterThan(0));
      await d.close();
    });

    test('a leg that never finishes times out rather than looping forever',
        () async {
      final d = FakeDevice(EkKind.slider);
      final c = PingPongController(target: d);

      // Stuck reporting motion; it never returns to idle.
      final run = c.start(
        motion: motion,
        settle: settle,
        launchGrace: grace,
        moveTimeout: const Duration(milliseconds: 200),
      );
      d.setState(EkState.keyposeMove);
      await run;

      expect(c.status.phase, PingPongPhase.failed);
      expect(c.status.error, contains('did not complete'));
      expect(d.stops, greaterThan(0));
      await d.close();
    });
  });

  group('the head, which reports no state', () {
    test('falls back to a timed leg instead of hanging', () async {
      // The head's telemetry carries no state byte (§5), so supervision is
      // impossible and the controller runs blind on a timer. This test pins
      // that behaviour so it is a deliberate fallback, not an accident.
      final d = FakeDevice(EkKind.head);
      expect(d.snapshot.reportsMotionState, isFalse);

      final c = PingPongController(target: d);
      unawaited(c.start(
        motion: MotionParams.fromPercent(50, EkKind.head),
        blindLeg: const Duration(milliseconds: 80),
      ));

      await Future<void>.delayed(const Duration(milliseconds: 300));
      await c.stop();

      expect(d.recalls.length, greaterThanOrEqualTo(2));
      for (var i = 1; i < d.recalls.length; i++) {
        expect(d.recalls[i], isNot(d.recalls[i - 1]));
      }
      await d.close();
    });

    test('a blind leg is interruptible partway through', () async {
      final d = FakeDevice(EkKind.head);
      final c = PingPongController(target: d);

      unawaited(c.start(
        motion: MotionParams.fromPercent(50, EkKind.head),
        blindLeg: const Duration(seconds: 30),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final sw = Stopwatch()..start();
      await c.stop();
      sw.stop();

      // Must not wait out the full 30 s leg.
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
      expect(d.stops, greaterThan(0));
      await d.close();
    });
  });

  group('the device loop flag is never used', () {
    test('every leg is an ordinary recall', () async {
      // Section 3: device loop mode stops after roughly one round trip, so the
      // host drives each leg. The controller only ever calls recallPose, which
      // sends loop=false; there is no code path here that sets the loop flag.
      final d = FakeDevice(EkKind.slider);
      final c = PingPongController(target: d);

      unawaited(c.start(motion: motion, settle: settle, launchGrace: grace));
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await completeAMove(d);
        await Future<void>.delayed(settle + const Duration(milliseconds: 60));
      }
      await c.stop();

      // More than one recall means the host is driving the repetition, which is
      // the whole point — a single fired-and-forgotten loop command would show
      // up here as exactly one.
      expect(d.recalls.length, greaterThan(1));
      await d.close();
    });
  });
}
