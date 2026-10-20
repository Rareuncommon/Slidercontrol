/// How the ported session behaves on the event loop, against a simulated
/// HeadONE leading a SliderPLUS.
///
/// The vector tests prove WHAT is sent. These prove WHEN and in what order:
/// one command in flight, a stop that overtakes the queue, a reply matched
/// on channel and type, timeouts and drops reported rather than hung on,
/// the layout join, and poses that move both axes and are verified on
/// arrival. Above all: a stop goes out on every exit path.
library;

import 'dart:async';

import 'package:test/test.dart';

import '../../lib/sdk/api/connect.dart';
import '../../lib/sdk/api/device.dart';
import '../../lib/sdk/devices/registry.dart';
import '../../lib/sdk/motion/pose.dart';
import '../../lib/sdk/protocol/generated/moco.dart';
import '../../lib/sdk/session/concurrency.dart';
import '../../lib/sdk/session/core.dart';
import '../../lib/sdk/session/session.dart';
import 'fake_rig.dart';

const opStatus = 1;
const opStore = 5;
const opMove = 7;
const opAbort = 9;
const opPanTilt = 10;
const opSlide = 11;
const opConfig = 201;
const opGroupSet = 9;
const opAddPeer = 1;

/// A HeadONE already joined to its slider, connected and polling.
Future<(Device, FakeHeadLink)> joinedRig({bool focusMotor = false}) async {
  final link = FakeHeadLink(
    unit: fakeHeadUnit(setup: EdlSetup.PAN_AND_SLIDE, group: 0x0101),
    configuration: EdlSetup.PAN_AND_SLIDE,
    focusMotor: focusMotor,
  );
  final head = link.device;
  final rig = Rig(master: head, slaves: [], setup: EdlSetup.PAN_AND_SLIDE, resolved: null);
  final device = await connect(FakeTransport(link), rig);
  await device.pollPosition();
  return (device, link);
}

Future<void> jog(Device d, {double pan = 0, double slide = 0, int ticks = 5}) async {
  for (var i = 0; i < ticks; i++) {
    await d.move.joystick(pan: pan, slide: slide);
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
}

void main() {
  group('the command queue', () {
    test('grants in arrival order, but a stop goes to the front', () async {
      final lock = FifoLock();
      final order = <String>[];
      await lock.acquire();
      final a = lock.acquire().then((_) => order.add('poll-1'));
      final b = lock.acquire().then((_) => order.add('poll-2'));
      final stop = lock.acquire(first: true).then((_) => order.add('STOP'));
      lock.release();
      await stop;
      lock.release();
      await a;
      lock.release();
      await b;
      lock.release();
      expect(order, ['STOP', 'poll-1', 'poll-2']);
    });
  });

  group('replies', () {
    test('a command waits for its reply type, and gets it', () async {
      final link = FakeHeadLink();
      final s = EdelkroneSession.attach(link);
      final reply = await s.send(s.commands.statusGet());
      expect(reply?.type, 2);
      expect(s.state.lastUpdate, isNotNull);
      await s.close();
    });

    test('an unanswered command times out instead of hanging', () async {
      final link = FakeHeadLink()..silent = true;
      final s = EdelkroneSession.attach(link);
      await expectLater(
        s.send(s.commands.statusGet(), timeout: 0.15),
        throwsA(isA<SessionError>().having((e) => e.failure, 'failure', SessionFailure.timeout)),
      );
      await s.close();
    });

    test('a drop while waiting fails the wait at once, as not connected', () async {
      final link = FakeHeadLink()..silent = true;
      final s = EdelkroneSession.attach(link);
      final pending = s.send(s.commands.statusGet(), timeout: 5);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      link.drop();
      await expectLater(
        pending,
        throwsA(isA<SessionError>().having((e) => e.failure, 'failure', SessionFailure.notConnected)),
      );
      await s.close();
    });
  });

  group('joining the slider to the head', () {
    test('goes by radio: keep the group, set the layout, invite the slider by MAC', () async {
      final link = FakeHeadLink(unit: fakeHeadUnit(group: 0x0101));
      final head = link.device;
      final slider = fakeSliderUnit();
      final rig = Rig(master: head, slaves: [], setup: EdlSetup.NONE, resolved: null);

      final device = await connect(FakeTransport(link, seen: [head, slider]), rig, withModules: [slider]);

      final group = link.ops(opGroupSet, channel: Channel.ioCtrl);
      final config = link.ops(opConfig);
      final peer = link.ops(opAddPeer, channel: Channel.ioCtrl);
      expect(group, isNotEmpty);
      expect((group.last.bytes[2] << 8) | group.last.bytes[3], 0x0101, reason: 'an existing group is kept');
      expect(config.single.bytes[2], EdlSetup.PAN_AND_SLIDE.value);
      expect(peer.single.bytes.sublist(2, 8), slider.advData.mac);
      expect(peer.single.bytes[8], EdlDevice.SLIDER_PLUS_V1.value);
      expect(link.sent.indexOf(group.last), lessThan(link.sent.indexOf(config.single)));
      expect(link.sent.indexOf(config.single), lessThan(link.sent.indexOf(peer.single)));

      expect(device.layout, EdlSetup.PAN_AND_SLIDE);
      expect(device.info.axes, [RigAxis.pan, RigAxis.slide]);
      expect(device.status.modulesResponding, isTrue);
      await device.move.stop(settle: 0);
      await device.disconnect();
    });
  });

  group('positions', () {
    test('the head reports its pan angle, and the slider its place, in real units', () async {
      final (d, link) = await joinedRig();
      link
        ..pan = 42.5
        ..slide = 33.25;
      await d.refresh();
      expect(d.status.pose.panDeg, closeTo(42.5, 0.001));
      expect(d.status.pose.slideCm, closeTo(33.25, 0.001));
      expect(d.status.pose.tiltDeg, isNull, reason: 'a pan-and-slide layout has no tilt axis');
      expect(d.status.positionIsTrusted, isTrue);
      await d.move.stop(settle: 0);
      await d.disconnect();
    });
  });

  group('joystick and stop', () {
    test('the joystick drives, and the status keeps up', () async {
      final (d, link) = await joinedRig();
      final before = link.pan;
      await jog(d, pan: 0.5, ticks: 6);
      expect(link.pan, greaterThan(before + 5));
      expect(d.move.isMoving, isTrue);
      await d.move.stop();
      expect(link.moving, isFalse);
      await d.disconnect();
    });

    test('stop zeroes the held axes first, then aborts, then zeroes the rest', () async {
      final (d, link) = await joinedRig();
      await jog(d, pan: 0.6, ticks: 3);
      final mark = link.sent.length;
      await d.move.stop();
      final after = link.sent.sublist(mark).where((s) => s.channel == Channel.data && s.op != opStatus && s.op != 83).toList();
      expect(after.first.op, opPanTilt, reason: 'the held pan/tilt goes to zero first');
      expect(s16(after.first.bytes, 2), 0);
      expect(after[1].op, opAbort, reason: 'then the planned move is aborted');
      expect(after.any((s) => s.op == opSlide && s16(s.bytes, 2) == 0), isTrue, reason: 'then every other axis');
      expect(link.moving, isFalse);
      await d.disconnect();
    });

    test('stop never throws, even with the link already gone', () async {
      final (d, link) = await joinedRig();
      await jog(d, pan: 0.4, ticks: 2);
      link.drop();
      await d.move.stop();
      await d.disconnect();
    });

    test('a stop overtakes the queue of status polls', () async {
      final (d, link) = await joinedRig();
      link.silent = true; // replies stop, so commands back up behind one another
      final polls = [for (var i = 0; i < 4; i++) d.session.send(d.session.commands.statusGet(), timeout: 0.4).catchError((_) => null)];
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final mark = link.sent.length;
      final stopping = d.session.motionAbort();
      await Future.wait(polls);
      await stopping.catchError((_) {});
      final ops = link.sent.sublist(mark).map((s) => s.op).toList();
      expect(ops.indexOf(opAbort), lessThan(ops.indexOf(opStatus) < 0 ? 999 : ops.indexOf(opStatus)),
          reason: 'the abort goes out before the polls that were already waiting');
      await d.disconnect();
    });
  });

  group('stored poses', () {
    test('store two poses and move between them: both axes arrive, and it is verified', () async {
      final (d, link) = await joinedRig();
      link
        ..pan = 0
        ..slide = 10;
      expect(await d.poses.store(0), isTrue);
      link
        ..pan = 60
        ..slide = 80;
      expect(await d.poses.store(1), isTrue);
      expect(d.poses.stored, [0, 1]);

      final there = await d.poses.moveTo(0, style: const MoveStyle(speed: 0.4, acceleration: 0.3));
      expect(there.isSuccess, isTrue, reason: '${there.reason}');
      expect(link.pan, closeTo(0, 0.01));
      expect(link.slide, closeTo(10, 0.01));

      final back = await d.poses.moveTo(1);
      expect(back.isSuccess, isTrue, reason: '${back.reason}');
      expect(link.pan, closeTo(60, 0.01));
      expect(link.slide, closeTo(80, 0.01));
      await d.move.stop(settle: 0);
      await d.disconnect();
    });

    test('the move carries the speed and acceleration it was given', () async {
      final (d, link) = await joinedRig();
      await d.poses.store(0);
      link.pan = 30;
      await d.poses.store(1);
      await d.poses.moveTo(0, style: const MoveStyle(speed: 0.25, acceleration: 0.5));
      final m = link.ops(opMove).last.bytes;
      int u16(int at) => (m[at] << 8) | m[at + 1];
      int u32(int at) => (m[at] << 24) | (m[at + 1] << 16) | (m[at + 2] << 8) | m[at + 3];
      expect(u16(5), (0.5 * 32000).toInt(), reason: 'acceleration in');
      expect(u16(7), (0.5 * 32000).toInt(), reason: 'acceleration out');
      expect(u32(9), (0.25 * 1000 * 32000).toInt(), reason: 'speed');
      await d.move.stop(settle: 0);
      await d.disconnect();
    });

    test('a move to an empty slot is refused with a reason, and nothing moves', () async {
      final (d, link) = await joinedRig();
      final out = await d.poses.moveTo(3);
      expect(out.accepted, isFalse);
      expect(out.reason, contains('slot 3 is empty'));
      expect(link.ops(opMove), isEmpty);
      await d.move.stop(settle: 0);
      await d.disconnect();
    });

    test('a head will not cross an empty slot, and the refusal says so', () async {
      final (d, link) = await joinedRig();
      await d.poses.store(0);
      link.pan = 50;
      await d.poses.store(2);
      await d.poses.moveTo(0);
      final out = await d.poses.moveTo(2);
      expect(out.accepted, isFalse);
      expect(out.reason, contains('slot 1 between pose 0 and pose 2 is empty'));
      await d.move.stop(settle: 0);
      await d.disconnect();
    });

    test("the device's own loop runs back and forth until stopped", () async {
      final (d, link) = await joinedRig();
      await d.poses.store(0);
      link.pan = 40;
      await d.poses.store(1);
      await d.poses.startMoveTo(1, start: 0, style: const MoveStyle(loop: true));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(link.legsCompleted, greaterThanOrEqualTo(2));
      await d.move.stop();
      expect(link.moving, isFalse);
      final legs = link.legsCompleted;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(link.legsCompleted, legs, reason: 'stopped means stopped');
      await d.disconnect();
    });
  });

  group('the focus gate', () {
    test('a head that reports a focus motor refuses motion, and says why', () async {
      final (d, link) = await joinedRig(focusMotor: true);
      expect(
        () => d.move.joystick(pan: 0.3),
        throwsA(isA<EdelkroneError>().having((e) => e.reason, 'reason', 'needs_focus_setup')),
      );
      await expectLater(d.poses.moveTo(0), throwsA(isA<EdelkroneError>()));
      expect(link.ops(opPanTilt), isEmpty);
      // Stopping is always allowed.
      await d.move.stop(settle: 0);
      await d.disconnect();
    });
  });
}
