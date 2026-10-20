/// The app's controller against the simulated HeadONE + SliderPLUS.
///
/// What a user does — find the rig, join the slider, jog, save poses, recall
/// them, loop, stop — and the guarantees around it: STOP ALL ends every kind
/// of motion, the loop stays stopped, and disconnecting always stops first.
library;

import 'dart:async';

import 'package:test/test.dart';

import '../../lib/app/rig_controller.dart';
import '../../lib/control/stop_registry.dart';
import '../../lib/sdk/motion/pose.dart';
import '../../lib/sdk/protocol/generated/moco.dart';
import '../../lib/sdk/session/core.dart';
import '../sdk/fake_rig.dart';

const opMove = 7;
const opAbort = 9;
const opPanTilt = 10;

Future<void> until(bool Function() test, {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (!test()) {
    if (DateTime.now().isAfter(end)) throw StateError('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// A controller that has found and joined the rig.
Future<(RigController, FakeHeadLink, StopRegistry)> joined() async {
  final link = FakeHeadLink(unit: fakeHeadUnit(group: 0x0101));
  final head = link.device;
  final slider = fakeSliderUnit();
  final registry = StopRegistry();
  final c = RigController(
    transport: FakeTransport(link, seen: [head, slider]),
    registry: registry,
  );
  await c.startScan();
  await until(() => c.seen.any((s) => s.name == 'HeadONE V2'));
  final target = c.seen.firstWhere((s) => s.name == 'HeadONE V2');
  final join = c.joinable(target);
  expect(join.map((u) => u.displayName), ['SliderPLUS V6'], reason: 'the slider is offered to join the head');
  await c.connect(target, join: join);
  expect(c.phase, RigPhase.connected, reason: '${c.error}');
  return (c, link, registry);
}

void main() {
  test('finding the rig and joining the slider gives one rig with both axes', () async {
    final (c, link, _) = await joined();
    expect(link.configuration, EdlSetup.PAN_AND_SLIDE);
    expect(c.isJoined, isTrue);
    expect(c.axes, {RigAxis.pan, RigAxis.slide});
    await c.disconnect();
  });

  test('a held jog repeats, and releasing it stops the axis at once', () async {
    final (c, link, _) = await joined();
    final from = link.pan;
    c.hold(RigAxis.pan, 0.8);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(link.ops(opPanTilt).length, greaterThanOrEqualTo(3), reason: 'repeated about every 100 ms');
    expect(link.pan, greaterThan(from));
    c.release(RigAxis.pan);
    await until(() => !link.moving);
    final last = link.ops(opPanTilt).last.bytes;
    expect(s16(last, 2), 0, reason: 'the release sends a zero');
    expect(c.jogging, isFalse);
    await c.disconnect();
  });

  test('save two poses, then recall them: both axes go, and the positions are shown', () async {
    final (c, link, _) = await joined();
    link
      ..pan = 5
      ..slide = 20;
    expect(c.nextSlot, 0);
    expect(await c.save(0, name: 'wide'), isTrue);
    link
      ..pan = 70
      ..slide = 90;
    expect(c.nextSlot, 1);
    expect(await c.save(1, name: 'tight'), isTrue);
    expect(c.stored, [0, 1]);
    expect(c.names, {0: 'wide', 1: 'tight'});
    expect(c.poses[0]!.panDeg, closeTo(5, 0.01));
    expect(c.poses[1]!.slideCm, closeTo(90, 0.01));

    final out = await c.recall(0);
    expect(out!.isSuccess, isTrue, reason: '${out.reason}');
    expect(link.pan, closeTo(5, 0.01));
    expect(link.slide, closeTo(20, 0.01));
    await c.disconnect();
  });

  test('saving into a slot that leaves a gap is flagged before it is done', () async {
    final (c, link, _) = await joined();
    await c.save(0);
    expect(c.wouldLeaveGap(1), isFalse);
    expect(c.wouldLeaveGap(3), isTrue);
    await c.disconnect();
  });

  test("the device's own loop runs until STOP ALL, and then stays stopped", () async {
    final (c, link, registry) = await joined();
    await c.save(0);
    link.pan = 45;
    await c.save(1);
    unawaited(c.startLoop(0, 1));
    await until(() => link.legsCompleted >= 2, timeout: const Duration(seconds: 6));
    expect(c.looping, isTrue);
    expect(link.ops(opMove).last.bytes[4], 1, reason: 'one loop command, run by the head');

    final failures = await registry.stopAll();
    expect(failures, isEmpty);
    expect(c.looping, isFalse);
    expect(link.moving, isFalse);
    final legs = link.legsCompleted;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(link.legsCompleted, legs, reason: 'stopped means stopped');
    await c.disconnect();
  });

  test('a loop with a dwell is supervised leg by leg, and STOP ALL ends it too', () async {
    final (c, link, registry) = await joined();
    await c.save(0);
    link.pan = 30;
    await c.save(1);
    final loop = c.startLoop(0, 1, dwell: const Duration(milliseconds: 150));
    await until(() => link.ops(opMove).length >= 3, timeout: const Duration(seconds: 6));
    expect(link.ops(opMove).every((m) => m.bytes[4] == 0), isTrue, reason: 'ordinary recalls, not the device loop');
    await registry.stopAll();
    await loop;
    final moves = link.ops(opMove).length;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(link.ops(opMove).length, moves, reason: 'no leg after the stop');
    await c.disconnect();
  });

  test('jogging takes over from a running loop', () async {
    final (c, link, _) = await joined();
    await c.save(0);
    link.pan = 40;
    await c.save(1);
    unawaited(c.startLoop(0, 1));
    await until(() => link.legsCompleted >= 1, timeout: const Duration(seconds: 6));
    final aborts = link.ops(opAbort).length;
    final slides = link.ops(11).length;
    c.hold(RigAxis.slide, 0.5);
    await until(() => !c.looping);
    await until(() => link.ops(opAbort).length > aborts, timeout: const Duration(seconds: 3));
    // The jog the user asked for starts after the loop has stopped, not
    // swallowed by it.
    await until(() => link.ops(11).skip(slides).any((s) => s16(s.bytes, 2) > 0), timeout: const Duration(seconds: 3));
    final firstJog = link.sent.indexWhere((s) => s.op == 11 && s16(s.bytes, 2) > 0);
    final lastAbortBeforeJog = link.sent.lastIndexWhere((s) => s.op == opAbort, firstJog);
    expect(lastAbortBeforeJog, greaterThanOrEqualTo(0), reason: 'the loop was stopped before the jog began');
    c.release(RigAxis.slide);
    await until(() => !link.moving);
    await c.disconnect();
  });

  test('disconnecting stops first', () async {
    final (c, link, _) = await joined();
    c.hold(RigAxis.pan, 1);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final aborts = link.ops(opAbort).length;
    await c.disconnect();
    expect(link.ops(opAbort).length, greaterThan(aborts));
    expect(c.phase, RigPhase.idle);
  });

  test('a dropped link is reported, local motion stops, and nothing is left registered', () async {
    final (c, link, registry) = await joined();
    c.hold(RigAxis.pan, 0.5);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    link.drop();
    await until(() => c.phase == RigPhase.lost);
    expect(c.error, contains('dropped'));
    expect(c.jogging, isFalse);
    // STOP ALL still runs cleanly against a dead link.
    expect(await registry.stopAll(), isEmpty);
    await c.disconnect();
    expect(registry.hasRegistrations, isFalse);
  });

  test('a link that never answers does not leave the controller hanging', () async {
    final link = FakeHeadLink(unit: fakeHeadUnit(setup: EdlSetup.PAN_AND_SLIDE, group: 1))..silent = true;
    final c = RigController(
      transport: FakeTransport(link, seen: [link.device]),
      registry: StopRegistry(),
    );
    await c.startScan();
    await until(() => c.seen.isNotEmpty);
    await c.connect(c.seen.first);
    expect(c.phase, RigPhase.idle);
    expect(c.error, isNotNull);
    expect(
      link.sent.where((s) => s.channel == Channel.data && s.op == opAbort),
      isNotEmpty,
      reason: 'a failed connect still sends a stop',
    );
  });
}
