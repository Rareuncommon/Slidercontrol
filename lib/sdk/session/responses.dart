/// Routes each reply frame to its parser and into the device state.
///
/// Ported from `edelkrone/session/responses.py` for the head, slider and
/// moco codecs, including the hand-written extras the SDK applies on top of
/// the generated parsers: the accelerometer block, and the 32-bit focus
/// percentage. Frame types this port does not store are still recognised —
/// which matters, because a waiter completes on a recognised type — but are
/// otherwise ignored rather than guessed at.
///
/// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
library;

import '../log.dart';
import '../protocol/generated/head_module.dart';
import '../protocol/generated/moco.dart';
import '../protocol/generated/slide_module.dart';
import 'core.dart';
import 'state.dart';

const _liveIndex = 255;

class ParseContext {
  const ParseContext({required this.libs, required this.hasLiveMode});
  final DeviceLibraries libs;
  final bool hasLiveMode;
  bool get isPro => libs.isPro;
}

class ParseOutcome {
  const ParseOutcome(this.typeName, {required this.applied});
  const ParseOutcome.stored(String name) : this(name, applied: true);
  const ParseOutcome.ignored(String name) : this(name, applied: false);
  static const unrecognised = ParseOutcome(null, applied: false);

  final String? typeName;
  final bool applied;
  bool get recognised => typeName != null;
}

int _signedBigEndian(List<int> v, int from, int size) {
  var x = 0;
  for (var i = from; i < from + size; i++) {
    x = (x << 8) | (v[i] & 0xFF);
  }
  return x.toSigned(size * 8);
}

const accelHeadOffset = 120;
const accelSlideOffset = 25;

(double, double, double)? accelerationAt(List<int> v, int first) {
  if (v.length < first + 6 + 2) return null;
  return (
    _signedBigEndian(v, first, 2) / 100.0,
    _signedBigEndian(v, first + 2, 2) / 100.0,
    _signedBigEndian(v, first + 4, 2) / 100.0,
  );
}

double _focusPercent(List<int> v, double parsed) {
  if (v.length < 30) return parsed;
  return _signedBigEndian(v, 26, 4) / 1000.0;
}

/// Python's `round(x, 3)` for the slider's readout. The value is a whole
/// number of thousandths divided out, so ties at the fourth decimal do not
/// arise in practice and fixed-point formatting matches.
double _round3(double x) => x.isFinite ? double.parse(x.toStringAsFixed(3)) : x;

abstract class FamilyCodec {
  ParseOutcome apply(ResponseFrame frame, DeviceState state, ParseContext ctx);

  static FamilyCodec forFamily(DeviceFamily family) => switch (family) {
        DeviceFamily.headModule => HeadModuleCodec(),
        DeviceFamily.slideModule => SlideModuleCodec(),
        _ => throw SessionError(SessionFailure.unsupported, 'no codec for ${family.name}'),
      };
}

class HeadModuleCodec implements FamilyCodec {
  static LibHeadModuleMk2BleResponse? _lookup(int t) {
    for (final r in LibHeadModuleMk2BleResponse.values) {
      if (r.value == t) return r;
    }
    return null;
  }

  @override
  ParseOutcome apply(ResponseFrame frame, DeviceState state, ParseContext ctx) {
    final kind = _lookup(frame.type ?? -1);
    if (kind == null) return ParseOutcome.unrecognised;
    final s = state as HeadModuleState;
    final lib = ctx.libs.headModule;
    final v = List<int>.of(frame.data);
    switch (kind) {
      case LibHeadModuleMk2BleResponse.HEAD_VERSION:
        final o = LibHeadModuleMk2HeadVersionData();
        lib.headVersionParse(v, o);
        s.version = o;
      case LibHeadModuleMk2BleResponse.GENERAL_STATUS:
        final o = LibHeadModuleMk2Status();
        lib.statusParse(v, o);
        s.generalStatus = o;
        s.accelerationMs2 = accelerationAt(v, accelHeadOffset);
      case LibHeadModuleMk2BleResponse.KEYPOSE_UNIQUE_ID_RESPONSE:
        final o = LibHeadModuleMk2KeyposeUniqueID();
        lib.keyposeUniqueIdParse(v, o);
        s.keyposeUniqueId = o;
      case LibHeadModuleMk2BleResponse.KEYPOSE_MOVE_DURATION:
        final out = [0.0];
        lib.keyposeMoveDurationParse(v, out);
        s.keyposeMoveDurationSec = out[0];
      case LibHeadModuleMk2BleResponse.REMOTE_POSITION_MOVE_DURATION:
        final out = [0.0];
        lib.remotePositionMoveDurationParse(v, out);
        s.remotePositionMoveDurationSec = out[0];
      case LibHeadModuleMk2BleResponse.SETTINGS:
        final o = LibHeadModuleMk2Settings();
        lib.settingsParse(v, o, ctx.isPro, ctx.hasLiveMode);
        s.settings = o;
      case LibHeadModuleMk2BleResponse.REMOTE_FIRMWARE_VERSION_RESPONSE:
        final o = LibHeadModuleMk2RemoteFirmwareVersions();
        lib.slaveFirmwareVersionParse(v, o);
        s.remoteFirmwareVersion = o;
      case LibHeadModuleMk2BleResponse.REMOTE_DEVICE_TYPE_RESPONSE:
        s.remoteDeviceType = lib.remoteDeviceTypeParse(v);
      case LibHeadModuleMk2BleResponse.NUMERIC_VALUE_READOUT:
        final index = [0, 0, 0];
        final o = LibHeadModuleMk2DigitalReadout();
        lib.numericControlParse(v, index, o);
        o.focusPercent = _focusPercent(v, o.focusPercent);
        if (index[0] == _liveIndex) {
          s.numericReadout = NumericReadout(index[0], o);
        } else {
          s.slotReadout = NumericReadout(index[0], o);
        }
      case LibHeadModuleMk2BleResponse.REMOTE_VERSION:
        final o = LibHeadModuleMk2RemoteVersion();
        lib.remoteVersionParse(v, o);
        s.remoteVersion = o;
        s.remoteVersionUpdates++;
      case LibHeadModuleMk2BleResponse.CANBUS_INFO_REPONSE_UNIVERSAL:
        s.canbusInfo = EdelkroneMoco.canbusInfoParse(v);
      default:
        return ParseOutcome.ignored(kind.name);
    }
    return ParseOutcome.stored(kind.name);
  }
}

class SlideModuleCodec implements FamilyCodec {
  static LibSlideModuleSliderBleResponse? _lookup(int t) {
    for (final r in LibSlideModuleSliderBleResponse.values) {
      if (r.value == t) return r;
    }
    return null;
  }

  @override
  ParseOutcome apply(ResponseFrame frame, DeviceState state, ParseContext ctx) {
    final kind = _lookup(frame.type ?? -1);
    if (kind == null) return ParseOutcome.unrecognised;
    final s = state as SlideModuleState;
    final lib = ctx.libs.slideModule;
    final v = List<int>.of(frame.data);
    switch (kind) {
      case LibSlideModuleSliderBleResponse.VERSION:
        final o = LibSlideModuleSliderVersionData();
        lib.versionInfoParse(v, o);
        s.version = o;
      case LibSlideModuleSliderBleResponse.GENERAL_STATUS:
        final o = LibSlideModuleStatus();
        lib.statusParse(v, o);
        s.generalStatus = o;
        s.accelerationMs2 = accelerationAt(v, accelSlideOffset);
      case LibSlideModuleSliderBleResponse.CONFIGURATION:
        final o = LibSlideModuleSettings();
        lib.settingsParse(v, o, ctx.hasLiveMode);
        s.settings = o;
      case LibSlideModuleSliderBleResponse.SLIDE_POS_UNIQUE_ID_RESPONSE:
        final id = [0, 0, 0];
        lib.uniqueIdParse(v, id);
        s.slideLocationUniqueId = id;
      case LibSlideModuleSliderBleResponse.NUMERIC_DATA_RESPONSE:
        final index = [0, 0, 0];
        final setpoint = [0.0, 0.0, 0.0];
        lib.numericControlParse(v, index, setpoint);
        final reading = NumericReadout(index[0], _round3(setpoint[0]));
        if (index[0] == _liveIndex) {
          s.numericReadout = reading;
        } else {
          s.slotReadout = reading;
        }
      case LibSlideModuleSliderBleResponse.CANBUS_INFO_REPONSE_UNIVERSAL:
        s.canbusInfo = EdelkroneMoco.canbusInfoParse(v);
      default:
        return ParseOutcome.ignored(kind.name);
    }
    return ParseOutcome.stored(kind.name);
  }
}

abstract final class MocoCodec {
  static LibEdelkroneMocoResponse? lookup(int t) {
    for (final r in LibEdelkroneMocoResponse.values) {
      if (r.value == t) return r;
    }
    return null;
  }

  static ParseOutcome apply(ResponseFrame frame, DeviceState state) {
    final kind = lookup(frame.type ?? -1);
    if (kind == null) return ParseOutcome.unrecognised;
    final v = List<int>.of(frame.data);
    switch (kind) {
      case LibEdelkroneMocoResponse.IOCTL_STATUS:
        final out = <LibEdelkroneMocoIoctlStatus>[
          LibEdelkroneMocoIoctlStatus(
            groupId: 0,
            groupMemberDev: [EdlDevice.NONE, EdlDevice.NONE],
            groupMemberConf: [EdlConfig.NONE, EdlConfig.NONE],
            autoConnectEnabled: false,
            wifiState: EspWifiState.NONE,
            wifiChannel: 0,
            esp32FirmwareVersionMinor: 0,
            esp32FirmwareVersionMajor: 0,
          ),
        ];
        EdelkroneMoco.ioctlStatusParse(v, out);
        state.ioctlStatus = out[0];
      case LibEdelkroneMocoResponse.CANBUS_INFO_READOUT:
        state.canbusInfo = EdelkroneMoco.canbusInfoParse(v);
      default:
        return ParseOutcome.ignored(kind.name);
    }
    return ParseOutcome.stored(kind.name);
  }
}

void logUnrecognised(ResponseFrame frame, DeviceFamily family) {
  EdelkroneLog.warning(() => '${family.name} device: unrecognised ${frame.channel.name} '
      'frame: type=${frame.type}, ${frame.data.length} bytes; ignored rather than guessed');
}
