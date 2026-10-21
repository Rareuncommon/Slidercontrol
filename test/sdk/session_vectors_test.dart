/// The hand-ported layers against the Python SDK's own versions of them.
///
/// vectors/session_vectors.json.gz was produced by running edelkrone 0.1.0
/// (tool/sdk_port/gen_session_vectors.py). The codec beneath these layers is
/// proven separately by codec_vectors_test.dart; this proves the wiring above
/// it — which builder each command uses, on which channel, expecting which
/// reply; which units form which layout; and what a reading means.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../lib/sdk/api/device.dart';
import '../../lib/sdk/devices/model_type.dart';
import '../../lib/sdk/devices/models.dart' as models;
import '../../lib/sdk/devices/registry.dart';
import '../../lib/sdk/protocol/generated/moco.dart';
import '../../lib/sdk/session/command_set.dart';
import '../../lib/sdk/session/core.dart';
import '../../lib/sdk/session/responses.dart';
import '../../lib/sdk/session/state.dart';

const pool = <String, EdelkroneDeviceModel>{
  'HEAD_ONE': models.headOne,
  'HEAD_ONE_FM': models.headOneFm,
  'SLIDER_PLUS_V1': models.sliderPlusV1,
  'SLIDER_ONE': models.sliderOne,
  'SLIDER_ONE_FM': models.sliderOneFm,
  'SLIDE_MODULE_V3': models.slideModuleV3,
  'HEAD_PLUS_V3': models.headPlusV3,
  'DOLLY_PLUS_V2': models.dollyPlusV2,
  'JIB_PLUS_V3': models.jibPlusV3,
  'HEAD_PLUS_PRO_V3': models.headPlusProV3,
};

double? num_(Object? v) {
  if (v == null) return null;
  if (v is Map) {
    final s = v['f'] as String;
    return s == 'NaN' ? double.nan : double.parse(s);
  }
  return (v as num).toDouble();
}

bool sameNum(Object? want, double? got) {
  final w = num_(want);
  if (w == null || got == null) return w == null && got == null;
  if (w.isNaN) return got.isNaN;
  return w == got;
}

EdelkroneDevice unitOf(Map<String, dynamic> d) {
  final i = d['i'] as int;
  final setup = d['setup'] == null ? EdlSetup.NONE : EdlSetup.values.byName(d['setup'] as String);
  return EdelkroneDevice(
    id: 'dev$i',
    model: pool[d['model']]!,
    advData: LibEdelkroneMocoAdvData(
      mac: [0xC8, 0xF0, 0x9E, 0x10, 0x20, i & 0xFF],
      groupId: (d['group'] as int?) ?? 0xFFFF,
      setup: setup,
      wifiChannel: 0,
      wifiState: EspWifiState.NONE,
      isTilted: d['tilted'] as bool,
      oldSlideModuleConnected: false,
      esp32FirmwareVersionMinor: 34,
      esp32FirmwareVersionMajor: 0,
      deviceFirmwareVersionMinor: 1,
      deviceFirmwareVersionMajor: 1,
      canbusPairingActive: false,
    ),
    rssi: -40 - i,
  );
}

EdelkroneCommand commandOf(CommandSet cs, String fam, String name, List<dynamic> a) {
  switch (name) {
    case 'status_get':
      return cs.statusGet();
    case 'version_get':
      return cs.versionGet();
    case 'settings_get':
      return cs.settingsGet();
    case 'motion_abort':
      return cs.motionAbort();
    case 'remote_version_get':
      return cs.remoteVersionGet();
    case 'keypose_move_duration_get':
      return cs.keyposeMoveDurationGet();
    case 'keypose_store':
      return cs.keyposeStore(a[0] as int);
    case 'keypose_delete':
      return cs.keyposeDelete(a[0] as int);
    case 'numeric_position_read':
      return cs.numericPositionRead(a[0] as int);
    case 'manual_slide':
      return cs.manualSlide(num_(a[0])!);
    case 'manual_pan_tilt':
      return cs.manualPanTilt(num_(a[0])!, num_(a[1])!);
    case 'manual_jib_pan_tilt':
      return cs.manualJibPanTilt(num_(a[0])!, num_(a[1])!);
    case 'buzzer':
      return cs.buzzerMuted(a[0] as bool);
    case 'configuration':
      return cs.configuration(EdlSetup.values.byName(a[0] as String));
    case 'keypose_move':
      final accel = num_(a[4])!;
      return cs.keyposeMove(
        MoveRequest(
          aimIndex: a[0] as int,
          startIndex: a[1] as int,
          loop: a[2] as bool,
          relativeSpeed: num_(a[3])!,
          accelInRatio: accel,
          accelOutRatio: accel,
        ),
      );
    case 'ioctl_status_get':
      return cs.ioctlStatusGet();
    case 'canbus_info_get':
      return cs.canbusInfoGet();
    case 'canbus_auto_pair':
      return cs.canbusAutoPair();
    case 'group_id_self_set':
      return cs.groupIdSelfSet(a[0] as int);
    case 'add_peer':
      return cs.addPeer(
        mac: (a[0] as List).cast<int>(),
        deviceType: EdlDevice.values.byName(a[1] as String),
        groupId: a[2] as int,
      );
  }
  throw ArgumentError(name);
}

void main() {
  final data = jsonDecode(
    utf8.decode(gzip.decode(File('test/sdk/vectors/session_vectors.json.gz').readAsBytesSync())),
  ) as Map<String, dynamic>;

  group('commands', () {
    final cases = (data['commands'] as List).cast<Map<String, dynamic>>();
    test('every command this port sends matches the SDK: bytes, channel, reply', () {
      final failures = <String>[];
      for (final c in cases) {
        final fam = c['fam'] as String;
        final cs = CommandSet(DeviceLibraries.of(fam == 'head' ? models.headOneFm : models.sliderPlusV1));
        final cmd = commandOf(cs, fam, c['cmd'] as String, c['args'] as List);
        final bytes = cmd.encode();
        final want = (c['bytes'] as List).cast<int>();
        if (bytes.toString() != want.toString()) failures.add('$fam ${c['cmd']}${c['args']}: bytes $bytes != $want');
        if (cmd.channel.name != c['channel']) {
          failures.add('$fam ${c['cmd']}: channel ${cmd.channel.name} != ${c['channel']}');
        }
        if (cmd.expects != c['expects']) failures.add('$fam ${c['cmd']}: expects ${cmd.expects} != ${c['expects']}');
      }
      expect(failures, isEmpty, reason: failures.take(10).join('\n'));
      expect(cases.length, greaterThan(100));
    });
  });

  group('layouts', () {
    final cases = (data['layouts'] as List).cast<Map<String, dynamic>>();
    test('which units form which layout, and who leads, matches the SDK', () {
      final failures = <String>[];
      for (final c in cases) {
        final units = [for (final u in (c['units'] as List)) unitOf(u as Map<String, dynamic>)];
        final r = prepareSetup(units);
        final want = c['out'] as Map<String, dynamic>?;
        final got = r == null
            ? null
            : {
                'setup': r.setupType.name,
                'master': units.indexOf(r.masterDevice),
                'slaves': [for (final s in r.slaveDevices) units.indexOf(s)],
              };
        if (jsonEncode(got) != jsonEncode(want)) failures.add('${c['units']}: got $got, want $want');
      }
      expect(failures, isEmpty, reason: failures.take(10).join('\n'));
    });

    test('a HeadONE with a SliderPLUS: upright pans, tilted tilts, the head leads', () {
      for (final tilted in [false, true]) {
        final head = unitOf({'i': 0, 'model': 'HEAD_ONE_FM', 'tilted': tilted});
        final slider = unitOf({'i': 1, 'model': 'SLIDER_PLUS_V1', 'tilted': false});
        final r = prepareSetup([head, slider])!;
        expect(r.setupType, tilted ? EdlSetup.TILT_AND_SLIDE : EdlSetup.PAN_AND_SLIDE);
        expect(r.masterDevice, head);
        expect(r.slaveDevices, [slider]);
      }
    });
  });

  group('rigs', () {
    final cases = (data['rigs'] as List).cast<Map<String, dynamic>>();
    test('grouping a scan into rigs matches the SDK', () {
      final failures = <String>[];
      for (final c in cases) {
        final units = [for (final u in (c['units'] as List)) unitOf(u as Map<String, dynamic>)];
        final got = [
          for (final r in groupIntoRigs(units))
            {
              'master': units.indexOf(r.master),
              'slaves': [for (final s in r.slaves) units.indexOf(s)],
              'ordered': [for (final s in r.orderedSlaves) units.indexOf(s)],
              'setup': r.setup.name,
              'recognised': r.isRecognised,
            },
        ];
        if (jsonEncode(got) != jsonEncode(c['out'])) failures.add('${c['units']}:\n got  $got\n want ${c['out']}');
      }
      expect(failures, isEmpty, reason: failures.take(5).join('\n'));
    });
  });

  group('status', () {
    final cases = (data['status'] as List).cast<Map<String, dynamic>>();
    test('what a status frame and a position readout mean matches the SDK', () {
      final failures = <String>[];
      var compared = 0;
      for (final c in cases) {
        final fam = c['fam'] as String;
        final libs = DeviceLibraries.of(fam == 'head' ? models.headOneFm : models.sliderPlusV1);
        final codec = FamilyCodec.forFamily(libs.family);
        final ctx = ParseContext(libs: libs, hasLiveMode: true);
        final state = DeviceState.forFamily(libs);
        final want = c['out'] as Map<String, dynamic>;
        DeviceStatus? s;
        Object? thrown;
        try {
          for (final f in (c['frames'] as List)) {
            codec.apply(ResponseFrame(Channel.data, (f as List).cast<int>()), state, ctx);
          }
          s = DeviceStatus.fromState(state);
        } catch (e) {
          thrown = e;
        }
        if (want.containsKey('throws')) {
          if (thrown == null) failures.add('#${cases.indexOf(c)}: Python threw, Dart did not');
          continue;
        }
        if (thrown != null) {
          failures.add('#${cases.indexOf(c)}: Dart threw $thrown');
          continue;
        }
        compared++;
        final st = s!;
        void check(String what, bool ok, Object? got, Object? exp) {
          if (!ok) failures.add('#${cases.indexOf(c)} $fam $what: got $got, want $exp');
        }

        const activity = {
          'idle': 'idle',
          'moving': 'moving',
          'transitioning': 'transitioning',
          'tracking_target': 'trackingTarget',
        };
        check('activity', st.activity?.name == activity[want['activity']], st.activity, want['activity']);
        final pose = want['pose'] as Map<String, dynamic>;
        check('pan', sameNum(pose['pan_deg'], st.pose.panDeg), st.pose.panDeg, pose['pan_deg']);
        check('tilt', sameNum(pose['tilt_deg'], st.pose.tiltDeg), st.pose.tiltDeg, pose['tilt_deg']);
        check('slide', sameNum(pose['slide_cm'], st.pose.slideCm), st.pose.slideCm, pose['slide_cm']);
        check('focus', sameNum(pose['focus_cm'], st.pose.focusCm), st.pose.focusCm, pose['focus_cm']);
        check('jibPan', sameNum(pose['jib_pan_deg'], st.pose.jibPanDeg), st.pose.jibPanDeg, pose['jib_pan_deg']);
        check('jibTilt', sameNum(pose['jib_tilt_deg'], st.pose.jibTiltDeg), st.pose.jibTiltDeg, pose['jib_tilt_deg']);
        check(
          'slideFraction',
          sameNum(want['slide_fraction'], st.slideFraction),
          st.slideFraction,
          want['slide_fraction'],
        );
        check(
          'battery',
          sameNum(want['battery_percent'], st.batteryPercent),
          st.batteryPercent,
          want['battery_percent'],
        );
        check('calibrated', st.isCalibrated == want['is_calibrated'], st.isCalibrated, want['is_calibrated']);
        check('focusMotor', st.hasFocusMotor == want['has_focus_motor'], st.hasFocusMotor, want['has_focus_motor']);
        check('layout', st.layout?.name.toLowerCase() == want['layout'], st.layout, want['layout']);
        check(
          'slots',
          jsonEncode(st.storedPoseSlots) == jsonEncode(want['stored_pose_slots']),
          st.storedPoseSlots,
          want['stored_pose_slots'],
        );
        check(
          'responding',
          st.modulesResponding == want['modules_responding'],
          st.modulesResponding,
          want['modules_responding'],
        );
        check('progress', sameNum(want['move_progress'], st.moveProgress), st.moveProgress, want['move_progress']);
        check(
          'trusted',
          st.positionIsTrusted == want['position_is_trusted'],
          st.positionIsTrusted,
          want['position_is_trusted'],
        );
        check('frame', st.hasStatusFrame == want['has_status_frame'], st.hasStatusFrame, want['has_status_frame']);
        check('tiltDeg', sameNum(want['tilt_deg'], st.tiltDeg), st.tiltDeg, want['tilt_deg']);
        check('level', st.isLevel == want['is_level'], st.isLevel, want['is_level']);
        check(
          'orientation',
          st.orientationWarning == want['orientation_warning'],
          st.orientationWarning,
          want['orientation_warning'],
        );
        final acc = want['accel'] as List;
        final a = st.accel;
        check('accel', sameNum(acc[0], a?.$1) && sameNum(acc[1], a?.$2) && sameNum(acc[2], a?.$3), a, acc);
      }
      expect(failures, isEmpty, reason: '${failures.length} mismatches; first:\n${failures.take(12).join('\n')}');
      expect(compared, greaterThan(250));
    });
  });
}
