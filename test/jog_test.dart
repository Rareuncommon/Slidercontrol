/// Manual jogging, driven against a fake device.
///
/// The thing worth testing here is the release path: jogging is the one place
/// the client streams velocity rather than commanding a self-completing move,
/// so a hold that ends without a zero going out leaves the motor running.
library;

import 'dart:async';

import 'package:test/test.dart';

import '../lib/ble/ek_snapshot.dart';
import '../lib/control/jog.dart';
import '../lib/control/motion_settings.dart';
import '../lib/ek_protocol.dart';

class FakeJogDevice implements EkMotionTarget {
  FakeJogDevice(this.kind);

  @override
  final EkKind kind;

  final velocities = <int>[];
  int stops = 0;
  bool failWrites = false;

  @override
  EkSnapshot get snapshot => EkSnapshot(
        link: EkLinkState.ready,
        kind: kind,
        lastFrameAt: DateTime.now(),
      );

  @override
  Stream<EkSnapshot> get snapshots => const Stream.empty();

  @override
  Future<void> recallPose(int slot, {required MotionSettings settings}) async {}

  @override
  Future<void> savePose(int slot) async {}

  @override
  Future<void> setVelocity(int countsPerSec) async {
    if (failWrites) throw StateError('link down');
    velocities.add(countsPerSec);
  }

  @override
  Future<void> stopMotion() async => stops++;
}

void main() {
  group('jogging', () {
    test('sends the first velocity frame immediately, not after a tick',
        () async {
      final d = FakeJogDevice(EkKind.slider);
      final j = JogController(target: d);

      await j.start(12000);
      // jogPeriod is 100 ms; without an immediate first send this would be
      // empty and the carriage would lag the press visibly.
      expect(d.velocities, [12000]);

      await j.stop();
    });

    test('keeps re-sending while held', () async {
      final d = FakeJogDevice(EkKind.slider);
      final j = JogController(target: d);

      await j.start(9000);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await j.stop();

      // ~100 ms cadence over 350 ms: the initial frame plus three ticks.
      expect(d.velocities.length, greaterThanOrEqualTo(3));
      expect(d.velocities.take(3), everyElement(9000));
    });

    test('release sends zero and then an explicit stop', () async {
      final d = FakeJogDevice(EkKind.slider);
      final j = JogController(target: d);

      await j.start(20000);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await j.stop();

      expect(d.velocities.last, 0, reason: 'a hold must end with velocity 0');
      expect(d.stops, 1, reason: 'and with the explicit stop opcode');
      expect(j.isJogging, isFalse);
    });

    test('no further frames go out after release', () async {
      final d = FakeJogDevice(EkKind.slider);
      final j = JogController(target: d);

      await j.start(15000);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await j.stop();

      final count = d.velocities.length;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(d.velocities.length, count);
    });

    test('the stop still goes out when the link is failing writes', () async {
      // The case that matters: if velocity writes are throwing, the release
      // must not give up before the explicit stop.
      final d = FakeJogDevice(EkKind.slider)..failWrites = true;
      final j = JogController(target: d);

      await j.start(20000);
      await j.stop();

      expect(d.stops, 1);
    });

    test('velocity can be changed mid-hold', () async {
      final d = FakeJogDevice(EkKind.slider);
      final j = JogController(target: d);

      await j.start(5000);
      j.setVelocity(25000);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await j.stop();

      expect(d.velocities, contains(25000));
    });

    test('setVelocity does nothing when not jogging', () async {
      final d = FakeJogDevice(EkKind.slider);
      final j = JogController(target: d);

      j.setVelocity(30000);
      expect(d.velocities, isEmpty);
      expect(j.isJogging, isFalse);
    });
  });

  group('speed percentage scales the commanded velocity', () {
    test('jog velocity follows the speed slider, per section 7b', () {
      // Manual jogging has no speed field — the velocity value IS the speed —
      // so the percentage has to be applied host-side.
      expect(const MotionSettings(speedPercent: 100).jogVelocity(), 30500);
      expect(const MotionSettings(speedPercent: 50).jogVelocity(), 15250);
      expect(const MotionSettings(speedPercent: 1).jogVelocity(), 305);
    });

    test('acceleration does not affect jogging', () {
      // The velocity frame has no acceleration slot at all.
      const slow = MotionSettings(speedPercent: 40, accelPercent: 1);
      const fast = MotionSettings(speedPercent: 40, accelPercent: 100);
      expect(slow.jogVelocity(), fast.jogVelocity());
    });
  });

  group('motion settings map onto the captured encoding', () {
    test('both sliders equal reproduces the captured configuration', () {
      const s = MotionSettings(speedPercent: 70, accelPercent: 70);
      expect(s.isCaptureFaithful, isTrue);
      expect(s.speedPair(EkKind.slider), s.accelPair(EkKind.slider));
    });

    test('split sliders are flagged as beyond the captures', () {
      const s = MotionSettings(speedPercent: 70, accelPercent: 20);
      expect(s.isCaptureFaithful, isFalse);
      expect(s.speedPair(EkKind.slider), isNot(s.accelPair(EkKind.slider)));
    });

    test('the pair is a period — higher percent gives a smaller number', () {
      const slow = MotionSettings(speedPercent: 5);
      const fast = MotionSettings(speedPercent: 95);
      expect(slow.speedPair(EkKind.slider),
          greaterThan(fast.speedPair(EkKind.slider)));
    });

    test('extra is derived from the speed percentage', () {
      const a = MotionSettings(speedPercent: 100, accelPercent: 1);
      const b = MotionSettings(speedPercent: 100, accelPercent: 100);
      expect(a.extra(EkKind.slider), b.extra(EkKind.slider));
      expect(a.extra(EkKind.slider), 1080);
      expect(const MotionSettings(speedPercent: 1).extra(EkKind.head), 320000);
    });
  });
}
