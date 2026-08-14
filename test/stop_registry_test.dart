/// The stop registry.
///
/// The case that motivated it: writing the stop opcode halts the motor, but if
/// a ping-pong loop is still running it commands the next leg moments later and
/// the device moves again. A stop must tear down the thing issuing commands,
/// not just the motion currently underway.
library;

import 'dart:async';

import 'package:test/test.dart';

import '../lib/ble/ek_snapshot.dart';
import '../lib/control/motion_settings.dart';
import '../lib/control/ping_pong.dart';
import '../lib/control/stop_registry.dart';
import '../lib/ek_protocol.dart';

class RecordingDevice implements EkMotionTarget {
  RecordingDevice(this.kind);

  @override
  final EkKind kind;

  final recalls = <int>[];
  int stops = 0;

  @override
  EkSnapshot get snapshot => EkSnapshot(
        link: EkLinkState.ready,
        kind: kind,
        state: EkState.keyposeMove,
        lastFrameAt: DateTime.now(),
      );

  @override
  Stream<EkSnapshot> get snapshots => const Stream.empty();

  @override
  Future<void> recallPose(int slot, {required MotionSettings settings}) async =>
      recalls.add(slot);

  @override
  Future<void> savePose(int slot) async {}

  @override
  Future<void> setVelocity(int countsPerSec) async {}

  @override
  Future<void> stopMotion() async => stops++;
}

void main() {
  group('registry basics', () {
    test('runs every registered stop', () async {
      final r = StopRegistry();
      var a = 0, b = 0;
      r.register('a', () async => a++);
      r.register('b', () async => b++);

      final failures = await r.stopAll();

      expect(failures, isEmpty);
      expect(a, 1);
      expect(b, 1);
    });

    test('one failing stop does not prevent the others', () async {
      // The case that matters: a second device must not be left running
      // because the first one's write threw.
      final r = StopRegistry();
      var reached = 0;
      r.register('bad', () async => throw StateError('link down'));
      r.register('good', () async => reached++);

      final failures = await r.stopAll();

      expect(reached, 1, reason: 'the good stop must still run');
      expect(failures, hasLength(1));
      expect(failures.single, contains('link down'));
    });

    test('re-registering the same owner replaces rather than accumulates',
        () async {
      final r = StopRegistry();
      var first = 0, second = 0;
      r.register('owner', () async => first++);
      r.register('owner', () async => second++);

      await r.stopAll();

      expect(r.count, 1);
      expect(first, 0);
      expect(second, 1);
    });

    test('unregistered owners are not called', () async {
      final r = StopRegistry();
      var calls = 0;
      r.register('x', () async => calls++);
      r.unregister('x');

      await r.stopAll();

      expect(calls, 0);
      expect(r.hasRegistrations, isFalse);
    });

    test('an action that unregisters itself mid-stop does not break the run',
        () async {
      final r = StopRegistry();
      var other = 0;
      r.register('self', () async => r.unregister('self'));
      r.register('other', () async => other++);

      final failures = await r.stopAll();

      expect(failures, isEmpty);
      expect(other, 1);
    });
  });

  group('stopping a running ping-pong', () {
    test('a registered loop stops issuing recalls, not just the motor',
        () async {
      // Stopping the device alone would be undone by the loop's next leg. This
      // is the bug the registry exists to prevent.
      final d = RecordingDevice(EkKind.slider);
      final pp = PingPongController(target: d);
      final r = StopRegistry();

      unawaited(pp.start(
        motion: const MotionSettings(),
        settle: const Duration(milliseconds: 40),
        launchGrace: const Duration(milliseconds: 80),
      ));
      r.register(pp, pp.stop);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      await r.stopAll();

      expect(pp.isRunning, isFalse);
      expect(d.stops, greaterThan(0));

      final after = d.recalls.length;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(d.recalls.length, after,
          reason: 'no further legs may be commanded after a stop');
    });
  });
}
