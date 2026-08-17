/// Clock-driven ping-pong.
///
/// The properties that matter are the ones the recall-and-watch loop cannot
/// offer: every leg lasts the shot duration, both axes are commanded on the
/// same ticks, and a leg that physically cannot be done that fast is extended
/// rather than allowed to arrive short.
///
/// And the property that matters more than any of them: every exit path stops
/// every device.
library;

import 'dart:async';

import 'package:test/test.dart';

import '../lib/ble/ek_snapshot.dart';
import '../lib/control/leg_supervisor.dart';
import '../lib/control/motion_settings.dart';
import '../lib/control/sync_move.dart';
import '../lib/control/sync_ping_pong.dart';
import '../lib/ek_protocol.dart';

class FakeDevice implements EkMotionTarget {
  FakeDevice(this.kind, {this.position});

  @override
  final EkKind kind;

  int? position;
  bool linkUp = true;

  int stops = 0;
  final recalls = <int>[];
  final velocities = <int>[];
  Object? failNextRecall;

  @override
  EkSnapshot get snapshot => EkSnapshot(
        link: linkUp ? EkLinkState.ready : EkLinkState.disconnected,
        kind: kind,
        position: position,
        lastFrameAt: DateTime.now(),
      );

  @override
  Stream<EkSnapshot> get snapshots => const Stream.empty();

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
  Future<void> savePose(int slot) async {}

  @override
  Future<void> setVelocity(int countsPerSec) async {
    velocities.add(countsPerSec);
    final p = position;
    if (p != null) position = p + (countsPerSec ~/ 20);
  }

  @override
  Future<void> stopMotion() async => stops++;
}

/// A [SyncPingPong] wired to one slider and one head, with the slider steered
/// toward a per-slot target.
({SyncPingPong loop, FakeDevice slider, FakeDevice head, List<int> legSlots})
    buildLoop({
  Duration shot = const Duration(milliseconds: 120),
  Map<int, int> targets = const {0: 5000, 1: 0},
  int maxVelocity = 200000,
}) {
  final slider = FakeDevice(EkKind.slider, position: 0);
  final head = FakeDevice(EkKind.head);
  final legSlots = <int>[];

  final loop = SyncPingPong(
    axesFor: (slot) {
      legSlots.add(slot);
      return [
        SliderSyncAxis(
          target: slider,
          targetCounts: targets[slot] ?? 0,
          maxVelocity: maxVelocity,
        ),
        PoseRecallSyncAxis(
          target: head,
          slot: slot,
          settings: const MotionSettings(),
        ),
      ];
    },
    shot: shot,
    stopAll: () async {
      await slider.stopMotion();
      await head.stopMotion();
      return const <String>[];
    },
  );

  return (loop: loop, slider: slider, head: head, legSlots: legSlots);
}

void main() {
  test('alternates between the two slots', () async {
    final f = buildLoop();
    await f.loop.start(maxLegs: 4);

    expect(f.head.recalls, [0, 1, 0, 1]);
    expect(f.loop.status.legs, 4);
    expect(f.loop.status.phase, PingPongPhase.stopped);
    expect(f.loop.status.error, isNull);
  });

  test('commands the head on the same leg the slider is steered on', () async {
    final f = buildLoop();
    await f.loop.start(maxLegs: 2);

    // One recall per leg, and the slider was streamed throughout each.
    expect(f.head.recalls.length, 2);
    expect(f.slider.velocities.length, greaterThan(4));
  });

  test('each leg lasts about the shot duration', () async {
    final f = buildLoop(shot: const Duration(milliseconds: 200));

    final started = DateTime.now();
    await f.loop.start(maxLegs: 2);
    final took = DateTime.now().difference(started);

    expect(took, greaterThanOrEqualTo(const Duration(milliseconds: 380)));
    expect(took, lessThan(const Duration(milliseconds: 1200)));
  });

  test('extends a leg the slider cannot physically manage that fast', () {
    // 60,000 counts at a 9,000 counts/sec ceiling, peaking at twice the
    // average, needs 13.3 s — not the 1 s asked for. Reporting the real figure
    // is the point: a shot that quietly ran long, or arrived short, is worse
    // than one that says so.
    final f = buildLoop(
      shot: const Duration(seconds: 1),
      targets: {0: 60000, 1: 0},
      maxVelocity: 9000,
    );
    expect(f.loop.effectiveLeg(0).inMilliseconds, closeTo(13334, 50));
  });

  test('keeps the shot duration when the move fits inside it', () {
    final f = buildLoop(
      shot: const Duration(seconds: 8),
      targets: {0: 60000, 1: 0},
      maxVelocity: 30000,
    );
    // 60,000 counts at 30,000/sec needs 4 s; 8 s is comfortably enough.
    expect(f.loop.effectiveLeg(0), const Duration(seconds: 8));
  });

  test('dwells between legs', () async {
    final f = buildLoop(shot: const Duration(milliseconds: 100));

    final started = DateTime.now();
    await f.loop.start(maxLegs: 2, dwell: const Duration(milliseconds: 250));
    final took = DateTime.now().difference(started);

    // Two legs plus one dwell between them.
    expect(took, greaterThanOrEqualTo(const Duration(milliseconds: 440)));
  });

  test('a stop mid-run halts and stops every device', () async {
    final f = buildLoop(shot: const Duration(seconds: 5));

    unawaited(f.loop.start());
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await f.loop.stop();

    expect(f.loop.isRunning, isFalse);
    expect(f.slider.stops, greaterThanOrEqualTo(1));
    expect(f.head.stops, greaterThanOrEqualTo(1));
    expect(f.slider.velocities.last, 0);
    expect(f.loop.status.phase, PingPongPhase.stopped);
  });

  test('a dropped link ends the run, reports it, and stops every device',
      () async {
    final f = buildLoop(shot: const Duration(seconds: 5));

    final run = f.loop.start();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    f.head.linkUp = false;
    await run;

    expect(f.loop.status.phase, PingPongPhase.failed);
    expect(f.loop.status.error, contains('link lost'));
    expect(f.slider.stops, greaterThanOrEqualTo(1));
    expect(f.head.stops, greaterThanOrEqualTo(1));
  });

  test('a write that throws ends the run and stops every device', () async {
    final f = buildLoop(shot: const Duration(milliseconds: 300));
    f.head.failNextRecall = StateError('write failed');

    await f.loop.start(maxLegs: 4);

    expect(f.loop.status.phase, PingPongPhase.failed);
    expect(f.loop.status.error, isNotNull);
    expect(f.slider.stops, greaterThanOrEqualTo(1));
    expect(f.head.stops, greaterThanOrEqualTo(1));
  });

  test('no axes to move is reported rather than spun on', () async {
    final loop = SyncPingPong(
      axesFor: (_) => const [],
      shot: const Duration(milliseconds: 100),
      stopAll: () async => const <String>[],
    );

    await loop.start(maxLegs: 4);

    expect(loop.status.phase, PingPongPhase.failed);
    expect(loop.status.error, 'nothing to move');
  });

  test('rebuilds the axes every leg, so the slider re-plans from where it is',
      () async {
    final f = buildLoop();
    await f.loop.start(maxLegs: 3);

    expect(f.legSlots.length, greaterThanOrEqualTo(3));
    expect(f.legSlots.take(3).toList(), [0, 1, 0]);
  });

  test('starting twice does not run two loops', () async {
    final f = buildLoop(shot: const Duration(seconds: 5));

    unawaited(f.loop.start());
    await Future<void>.delayed(const Duration(milliseconds: 60));
    unawaited(f.loop.start());
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await f.loop.stop();

    // One leg was ever commanded, not two overlapping ones.
    expect(f.head.recalls.length, 1);
  });
}
