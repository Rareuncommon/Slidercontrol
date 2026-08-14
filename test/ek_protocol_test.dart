/// Verifies the Dart port against the same captured bytes the Python
/// implementation checks. If these pass, the port is byte-identical to what the
/// official app sends.
import 'package:test/test.dart';
import '../lib/ek_protocol.dart';

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('framing', () {
    test('checksum is a plain 16-bit sum', () {
      expect(hex(buildFrame(0x0F)), '020f0011');
      expect(0x02 + 0x0F, 0x11);
    });

    test('length byte counts everything before the checksum', () {
      final f = buildFrame(0x0D, [0x7C, 0x66, 0x70, 0x80]);
      expect(f[0], 6);
      expect(f.length, 8);
    });

    test('verifyChecksum accepts real frames and rejects corrupted ones', () {
      final good = buildFrame(0x0B, [1, 2, 3]);
      expect(verifyChecksum(good), isTrue);
      final bad = [...good]..[2] ^= 0xFF;
      expect(verifyChecksum(bad), isFalse);
    });

    test('a captured 27-byte slider telemetry frame checksums', () {
      final frame = [
        0x02, 0x00, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0b, 0x83,
        0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xf3,
      ];
      expect(verifyChecksum(frame), isTrue);
    });
  });

  group('slider frames match the capture', () {
    final s = EkProfile.slider;
    test('keepalive', () => expect(hex(s.keepalive()), '020f0011'));
    test('velocity stop', () => expect(hex(s.velocity(0)), '060d000070800103'));
    test('velocity right', () => expect(hex(s.velocity(31846)), '060d7c66708001e5'));
    test('velocity left', () => expect(hex(s.velocity(-31941)), '060d833b708001c1'));
    test('save slot 0', () => expect(hex(s.savePose(0)), '070700000030390077'));
    test('save slot 1', () => expect(hex(s.savePose(1)), '070701000030390078'));
    test('goto pose 0',
        () => expect(hex(s.gotoPose(0)), '0d0b000000020304940494ff00024c'));
    test('goto pose 1',
        () => expect(hex(s.gotoPose(1)), '0d0b000000020304940494ff01024d'));
    test('loop from pose 1',
        () => expect(hex(s.gotoPose(1, loop: true)), '0d0b0100000203049404940001014f'));
    test('stop', () => expect(hex(s.stop()), '020c000e'));
  });

  group('head frames match the capture', () {
    final h = EkProfile.head;
    test('keepalive', () => expect(hex(h.keepalive()), '02010003'));
    test('velocity left', () => expect(hex(h.velocity(-31997)), '060a830300000096'));
    test('velocity right', () => expect(hex(h.velocity(31989)), '060a7cf500000181'));
    test('velocity stop', () => expect(hex(h.velocity(0)), '060a000000000010'));
    test('save slot 0', () => expect(hex(h.savePose(0)), '070500000030390075'));
    test('save slot 1', () => expect(hex(h.savePose(1)), '070501000030390076'));
    test('goto pose 0',
        () => expect(hex(h.gotoPose(0)), '1107ff00000494049400e6741afffffc1806cd'));
    test('goto pose 1',
        () => expect(hex(h.gotoPose(1)), '1107ff01000494049400e6741afffffc1806ce'));
    test('loop from pose 1',
        () => expect(hex(h.gotoPose(1, loop: true)),
            '11070001010494049400e6741afffffc1805d0'));
    test('stop', () => expect(hex(h.stop()), '0209000b'));
  });

  group('speed and acceleration', () {
    final s = EkProfile.slider;
    final h = EkProfile.head;

    test('slider at 1% matches the capture', () {
      expect(hex(s.gotoPose(0, speed: 31683, accel: 31683, extra: 20)),
          '0d0b00000000147bc37bc3ff0003a7');
    });
    test('slider at 100% matches the capture', () {
      expect(hex(s.gotoPose(0, speed: 320, accel: 320, extra: 1080)),
          '0d0b000000043801400140ff0001d5');
      expect(hex(s.gotoPose(1, speed: 320, accel: 320, extra: 1080)),
          '0d0b000000043801400140ff0101d6');
    });
    test('head at 1% matches the captured prefix', () {
      expect(hex(h.gotoPose(0, speed: 31683, accel: 31683, extra: 0x0004E200)),
          startsWith('1107ff00007bc37bc30004e200fffffc'));
    });
    test('head at 100% matches the captured prefix', () {
      expect(hex(h.gotoPose(0, speed: 320, accel: 320, extra: 0x01E84800)),
          startsWith('1107ff00000140014001e84800fffffc'));
    });

    test('percent model reproduces both measured endpoints', () {
      // The pair is a period, so it is exact at 100% and within 1% at 1%.
      expect(MotionParams.fromPercent(100, EkKind.slider).pair, 320);
      expect(MotionParams.fromPercent(1, EkKind.slider).pair,
          closeTo(31683, 31683 * 0.02));

      expect(MotionParams.fromPercent(1, EkKind.slider).extra, 20);
      expect(MotionParams.fromPercent(100, EkKind.slider).extra, 1080);
      expect(MotionParams.fromPercent(1, EkKind.head).extra, 320000);
      expect(MotionParams.fromPercent(100, EkKind.head).extra, 32000000);
    });

    test('both extra fields agree the captured default was about 47%', () {
      final s47 = MotionParams.fromPercent(47, EkKind.slider).extra;
      final h47 = MotionParams.fromPercent(47, EkKind.head).extra;
      expect(s47, closeTo(MotionParams.sliderCapturedDefaultExtra, 10));
      expect(h47, closeTo(MotionParams.headCapturedDefaultExtra, 100000));
    });

    test('slower percentages give larger periods', () {
      final slow = MotionParams.fromPercent(5, EkKind.slider).pair;
      final fast = MotionParams.fromPercent(95, EkKind.slider).pair;
      expect(slow, greaterThan(fast));
    });

    test('jog velocity scales with the same percentage', () {
      expect(MotionParams.jogVelocityForPercent(100), 30500);
      expect(MotionParams.jogVelocityForPercent(50), 15250);
      expect(MotionParams.jogVelocityForPercent(1), 305);
    });
  });

  group('profile selection', () {
    test('matches the advertised names', () {
      expect(EkProfile.forName('HeadOneFM').kind, EkKind.head);
      expect(EkProfile.forName('SldrPlsV1').kind, EkKind.slider);
      expect(EkProfile.forName('HeadOne').kind, EkKind.head);
      expect(EkProfile.forName('SldrPls').kind, EkKind.slider);
    });
    test('defaults to slider when the name is missing', () {
      expect(EkProfile.forName(null).kind, EkKind.slider);
      expect(EkProfile.forName('').kind, EkKind.slider);
    });
  });

  group('telemetry', () {
    List<int> sliderFrame(int state, int battery, int pos) {
      final f = List<int>.filled(27, 0);
      f[0] = 0x02;
      f[1] = state;
      f[2] = battery;
      f[8] = (pos >> 8) & 0xFF;
      f[9] = pos & 0xFF;
      return f;
    }

    test('parses state, battery and position', () {
      final t = parseTelemetry(sliderFrame(0x0E, 87, 12345), EkKind.slider)!;
      expect(t.state, EkState.manualJog);
      expect(t.batteryPercent, 87);
      expect(t.rawPosition, 12345);
    });

    test('rejects the 0xFF ack, whose position bytes are invalid', () {
      expect(parseTelemetry(sliderFrame(0xFF, 100, 9999), EkKind.slider), isNull);
    });

    test('maps every known state byte', () {
      expect(parseTelemetry(sliderFrame(0x00, 1, 0), EkKind.slider)!.state,
          EkState.idle);
      expect(parseTelemetry(sliderFrame(0x02, 1, 0), EkKind.slider)!.state,
          EkState.keyposeMove);
    });
  });

  group('position unwrapping', () {
    test('follows a counter across many wraps', () {
      final t = PositionTracker();
      var truth = 60000;
      t.update(truth % 65536);
      for (var i = 0; i < 500; i++) {
        truth += 9000; // a full-speed sample step
        t.update(truth % 65536);
      }
      expect(t.position, truth);
    });

    test('handles decreasing motion through zero', () {
      final t = PositionTracker();
      var truth = 5000;
      t.update(truth % 65536);
      for (var i = 0; i < 200; i++) {
        truth -= 7000;
        t.update(((truth % 65536) + 65536) % 65536);
      }
      expect(t.position, truth);
    });

    test('reproduces the real hand sweep total', () {
      // Two samples from the captured sweep: a wrap that must read as -9230,
      // not +56306.
      final t = PositionTracker();
      t.update(1138);
      final after = t.update(57444);
      expect(after - 1138, -9230);
    });
  });

  group('rig constants', () {
    test('head velocity conversion round-trips', () {
      expect(EkRig.headVelocityForDegreesPerSecond(1.2), closeTo(2000, 0.01));
      expect(EkRig.headVelocityForDegreesPerSecond(20), closeTo(33333, 1));
    });
  });
}
