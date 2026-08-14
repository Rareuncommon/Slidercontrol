/// Multi-device synchronised ping-pong.
///
/// The property that matters: no device starts its next leg until every device
/// has finished this one. Without that the axes drift apart over a long run,
/// and a fast slider would be recalling pose 1 while the head is still moving
/// to pose 0.
library;

import 'dart:async';

import 'package:test/test.dart';

import '../lib/ble/ek_snapshot.dart';
import '../lib/control/fleet.dart';
import '../lib/control/leg_supervisor.dart';
import '../lib/control/motion_settings.dart';
import '../lib/ek_protocol.dart';

class FakeMember implements EkMotionTarget {
  FakeMember(this.kind, {EkState state = EkState.idle})
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
  final saves = <int>[];
  int stops = 0;
  Object? failNextRecall;

  @override
  EkSnapshot get snapshot => _snapshot.copyWith(lastFrameAt: DateTime.now());

  @override
  Stream<EkSnapshot> get snapshots => _controller.stream;

  @override
  Future<void> recallPose(int slot, {required MotionSettings settings}) async {
    final f = failNextRecall;
    if (f != null) {
      failNextRecall = null;
      throw f;
    }
    recalls.add(slot);
  }

  @override
  Future<void> savePose(int slot) async => saves.add(slot);

  @override
  Future<void> setVelocity(int countsPerSec) async {}

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

Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String? describe,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('timed out waiting for ${describe ?? 'condition'}');
}

Future<void> finishMove(FakeMember m) async {
  m.setState(EkState.keyposeMove);
  await Future<void>.delayed(const Duration(milliseconds: 160));
  m.setState(EkState.idle);
}

const fastTimings = LegTimings(
  settle: Duration(milliseconds: 60),
  launchGrace: Duration(milliseconds: 200),
  moveTimeout: Duration(seconds: 5),
  blindLeg: Duration(milliseconds: 100),
);

void main() {
  group('synchronised legs', () {
    test('commands every device on each leg', () async {
      final slider = FakeMember(EkKind.slider);
      final head = FakeMember(EkKind.head);
      final fleet = FleetPingPong(members: [
        FleetMember(
            target: slider,
            name: 'slider',
            motion: const MotionSettings(),
            timings: fastTimings),
        FleetMember(
            target: head,
            name: 'head',
            motion: const MotionSettings(),
            timings: fastTimings),
      ]);

      unawaited(fleet.start());

      for (var leg = 0; leg < 3; leg++) {
        await waitFor(() => slider.recalls.length > leg,
            describe: 'slider recall ${leg + 1}');
        await finishMove(slider);
        await waitFor(() => slider.recalls.length > leg + 1 || leg == 2,
            timeout: const Duration(seconds: 3),
            describe: 'next leg or end');
      }
      await fleet.stop();

      expect(slider.recalls.length, greaterThanOrEqualTo(3));
      expect(head.recalls.length, slider.recalls.length,
          reason: 'both axes must be commanded the same number of times');
      await slider.close();
      await head.close();
    });

    test('a fast device waits for a slow one before the next leg', () async {
      // The whole point of the fleet. The slider finishes its move quickly; the
      // head runs a blind timer. The slider must not start leg 2 until the
      // head's leg 1 is done.
      final slider = FakeMember(EkKind.slider);
      final head = FakeMember(EkKind.head);
      final fleet = FleetPingPong(members: [
        FleetMember(
          target: slider,
          name: 'slider',
          motion: const MotionSettings(),
          timings: fastTimings,
        ),
        FleetMember(
          target: head,
          name: 'head',
          motion: const MotionSettings(),
          // A deliberately long blind leg.
          timings: const LegTimings(blindLeg: Duration(milliseconds: 700)),
        ),
      ]);

      unawaited(fleet.start());

      await waitFor(() => slider.recalls.isNotEmpty);
      await finishMove(slider);
      // Slider is done and settled well inside the head's 700 ms leg.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(slider.recalls.length, 1,
          reason: 'slider must wait for the head before its second leg');

      await waitFor(() => slider.recalls.length > 1,
          timeout: const Duration(seconds: 3),
          describe: 'the head to finish its leg');

      await fleet.stop();
      await slider.close();
      await head.close();
    });

    test('slots alternate together, never opposed', () async {
      final a = FakeMember(EkKind.head);
      final b = FakeMember(EkKind.head);
      final fleet = FleetPingPong(members: [
        FleetMember(
            target: a,
            name: 'a',
            motion: const MotionSettings(),
            timings: fastTimings),
        FleetMember(
            target: b,
            name: 'b',
            motion: const MotionSettings(),
            timings: fastTimings),
      ]);

      unawaited(fleet.start());
      await waitFor(() => a.recalls.length >= 4,
          timeout: const Duration(seconds: 5), describe: '4 legs');
      await fleet.stop();

      // Both devices must be on the same slot at every step — one axis at pose
      // 0 while the other is at pose 1 is a broken shot.
      final n = a.recalls.length < b.recalls.length
          ? a.recalls.length
          : b.recalls.length;
      for (var i = 0; i < n; i++) {
        expect(a.recalls[i], b.recalls[i], reason: 'leg $i diverged');
      }
      for (var i = 1; i < n; i++) {
        expect(a.recalls[i], isNot(a.recalls[i - 1]));
      }
      await a.close();
      await b.close();
    });
  });

  group('stopping', () {
    test('stop halts both and stops both motors', () async {
      final a = FakeMember(EkKind.head);
      final b = FakeMember(EkKind.head);
      final fleet = FleetPingPong(members: [
        FleetMember(
            target: a,
            name: 'a',
            motion: const MotionSettings(),
            timings: fastTimings),
        FleetMember(
            target: b,
            name: 'b',
            motion: const MotionSettings(),
            timings: fastTimings),
      ]);

      unawaited(fleet.start());
      await waitFor(() => a.recalls.isNotEmpty);
      await fleet.stop();

      expect(fleet.isRunning, isFalse);
      expect(a.stops, greaterThan(0));
      expect(b.stops, greaterThan(0));

      final aAfter = a.recalls.length;
      final bAfter = b.recalls.length;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(a.recalls.length, aAfter);
      expect(b.recalls.length, bAfter);
      await a.close();
      await b.close();
    });

    test('one device losing its link stops the whole fleet', () async {
      // Continuing with one axis while the other has stopped would ruin the
      // shot and leave the dropped device wherever it stalled.
      final slider = FakeMember(EkKind.slider);
      final head = FakeMember(EkKind.head);
      final fleet = FleetPingPong(members: [
        FleetMember(
            target: slider,
            name: 'slider',
            motion: const MotionSettings(),
            timings: fastTimings),
        FleetMember(
            target: head,
            name: 'head',
            motion: const MotionSettings(),
            timings: fastTimings),
      ]);

      final run = fleet.start();
      await waitFor(() => slider.recalls.isNotEmpty);
      slider.setState(EkState.keyposeMove);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      slider.dropLink();
      await run;

      expect(fleet.status.phase, PingPongPhase.failed);
      expect(fleet.status.error, contains('slider'));
      expect(head.stops, greaterThan(0),
          reason: 'the healthy device must be stopped too');
      await slider.close();
      await head.close();
    });

    test('a throwing recall stops every device', () async {
      final a = FakeMember(EkKind.head)..failNextRecall = StateError('boom');
      final b = FakeMember(EkKind.head);
      final fleet = FleetPingPong(members: [
        FleetMember(
            target: a,
            name: 'a',
            motion: const MotionSettings(),
            timings: fastTimings),
        FleetMember(
            target: b,
            name: 'b',
            motion: const MotionSettings(),
            timings: fastTimings),
      ]);

      await fleet.start();

      expect(fleet.status.phase, PingPongPhase.failed);
      expect(a.stops, greaterThan(0));
      expect(b.stops, greaterThan(0));
      await a.close();
      await b.close();
    });

    test('a leg limit ends cleanly rather than as a failure', () async {
      final a = FakeMember(EkKind.head);
      final b = FakeMember(EkKind.head);
      final fleet = FleetPingPong(members: [
        FleetMember(
            target: a,
            name: 'a',
            motion: const MotionSettings(),
            timings: fastTimings),
        FleetMember(
            target: b,
            name: 'b',
            motion: const MotionSettings(),
            timings: fastTimings),
      ]);

      await fleet.start(maxLegs: 2);

      expect(a.recalls.length, 2);
      expect(b.recalls.length, 2);
      expect(fleet.status.phase, PingPongPhase.stopped);
      expect(fleet.status.error, isNull);
      await a.close();
      await b.close();
    });
  });

  group('one-shot fleet commands', () {
    test('saveAll stores the slot on every device', () async {
      final a = FakeMember(EkKind.slider);
      final b = FakeMember(EkKind.head);
      final fleet = FleetPingPong(members: [
        FleetMember(target: a, name: 'a', motion: const MotionSettings()),
        FleetMember(target: b, name: 'b', motion: const MotionSettings()),
      ]);

      final failures = await fleet.saveAll(1);

      expect(failures, isEmpty);
      expect(a.saves, [1]);
      expect(b.saves, [1]);
    });

    test('recallAll reports which device failed without skipping the others',
        () async {
      final a = FakeMember(EkKind.slider)..failNextRecall = StateError('nope');
      final b = FakeMember(EkKind.head);
      final fleet = FleetPingPong(members: [
        FleetMember(target: a, name: 'slider', motion: const MotionSettings()),
        FleetMember(target: b, name: 'head', motion: const MotionSettings()),
      ]);

      final failures = await fleet.recallAll(0);

      expect(failures, hasLength(1));
      expect(failures.single, contains('slider'));
      expect(b.recalls, [0], reason: 'the healthy device still got its recall');
    });
  });
}
