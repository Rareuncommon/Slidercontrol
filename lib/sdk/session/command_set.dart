/// Every command the session sends, for the head and slider families.
///
/// Ported from `edelkrone/session/command_set.py` and `commands/settings.py`.
/// Each command builds its bytes through the generated codec, which is checked
/// byte for byte against the Python SDK.
///
/// Deliberately absent: the numeric "drive to coordinate" moves. The codec has
/// them, but the SDK's 0.1 release does not offer driving to coordinates and
/// says so, so this port does not send them either.
///
/// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
library;

import '../log.dart';
import '../protocol/generated/head_module.dart';
import '../protocol/generated/moco.dart';
import '../protocol/generated/slide_module.dart';
import 'core.dart';

const fromCurrentPosition = -1;

/// A planned move between stored poses.
class MoveRequest {
  const MoveRequest({
    required this.aimIndex,
    this.startIndex = fromCurrentPosition,
    this.loop = false,
    this.relativeSpeed = 0.5,
    this.accelInRatio = 0.25,
    this.accelOutRatio = 0.25,
  });

  final int aimIndex;
  final int startIndex;
  final bool loop;
  final double relativeSpeed;
  final double accelInRatio;
  final double accelOutRatio;

  int get loopFlag => loop ? 1 : 0;
}

/// The SDK's "speed-based duration" sentinel: the device plans the duration
/// from the speed rather than being told one.
const _speedBasedDuration = -1.0;

double _speed(double value, String name) {
  if (value >= -1.0 && value <= 1.0) return value;
  final held = value > 0 ? 1.0 : -1.0;
  EdelkroneLog.warning(
    () =>
        '$name=$value is outside the documented -1..1 and was held '
        'at $held: on the wire an out-of-range fraction overflows a signed '
        '16-bit field and drives the motor backwards.',
  );
  return held;
}

class CommandSet {
  CommandSet(this.libs);

  final DeviceLibraries libs;

  static const defaultUniqueId = 12345;
  static const currentPositionIndex = 255;

  static final _moco = EdelkroneMoco();

  Channel get _mocoChannel => libs.mocoUniversalOnDataChannel ? Channel.data : Channel.ioCtrl;

  bool get _isHead => libs.family == DeviceFamily.headModule;

  SessionError _unsupported(String command) => SessionError(
    SessionFailure.unsupported,
    '$command is not a ${libs.family.name} command (${libs.model.displayName})',
    command: command,
  );

  EdelkroneCommand statusGet() => _isHead
      ? EdelkroneCommand(
          name: 'headModule.statusGet',
          channel: Channel.data,
          build: (p, n) => libs.headModule.statusGet(p, n),
          expects: LibHeadModuleMk2BleResponse.GENERAL_STATUS.value,
        )
      : EdelkroneCommand(
          name: 'slideModule.statusGet',
          channel: Channel.data,
          build: (p, n) => libs.slideModule.statusGet(p, n),
          expects: LibSlideModuleSliderBleResponse.GENERAL_STATUS.value,
        );

  EdelkroneCommand versionGet() => _isHead
      ? EdelkroneCommand(
          name: 'headModule.headVersionGet',
          channel: Channel.data,
          build: (p, n) => libs.headModule.headVersionGet(p, n),
          expects: LibHeadModuleMk2BleResponse.HEAD_VERSION.value,
        )
      : EdelkroneCommand(
          name: 'slideModule.versionInfoGet',
          channel: Channel.data,
          build: (p, n) => libs.slideModule.versionInfoGet(p, n),
          expects: LibSlideModuleSliderBleResponse.VERSION.value,
        );

  EdelkroneCommand settingsGet() => _isHead
      ? EdelkroneCommand(
          name: 'headModule.settingsGet',
          channel: Channel.data,
          build: (p, n) => libs.headModule.settingsGet(p, n),
          expects: LibHeadModuleMk2BleResponse.SETTINGS.value,
        )
      : EdelkroneCommand(
          name: 'slideModule.settingsRead',
          channel: Channel.data,
          build: (p, n) => libs.slideModule.settingsRead(p, n),
          expects: LibSlideModuleSliderBleResponse.CONFIGURATION.value,
        );

  EdelkroneCommand remoteVersionGet() {
    if (!_isHead) throw _unsupported('remoteVersionGet');
    return EdelkroneCommand(
      name: 'headModule.remoteVersionGet',
      channel: Channel.data,
      build: (p, n) => libs.headModule.remoteVersionGet(p, n),
      expects: LibHeadModuleMk2BleResponse.REMOTE_VERSION.value,
    );
  }

  EdelkroneCommand keyposeStore(int index, {int uniqueId = defaultUniqueId}) => _isHead
      ? EdelkroneCommand(
          name: 'headModule.keyposeStore($index)',
          channel: Channel.data,
          build: (p, n) => libs.headModule.keyposeStore(p, n, index, uniqueId),
        )
      : EdelkroneCommand(
          name: 'slideModule.storeLocation($index)',
          channel: Channel.data,
          build: (p, n) => libs.slideModule.storeLocation(p, n, index, uniqueId),
        );

  EdelkroneCommand keyposeDelete(int index) => _isHead
      ? EdelkroneCommand(
          name: 'headModule.keyposeDelete($index)',
          channel: Channel.data,
          build: (p, n) => libs.headModule.keyposeDelete(p, n, index),
        )
      : EdelkroneCommand(
          name: 'slideModule.deleteLocation($index)',
          channel: Channel.data,
          build: (p, n) => libs.slideModule.deleteLocation(p, n, index),
        );

  EdelkroneCommand keyposeMove(MoveRequest move) {
    if (_isHead) {
      final cmd = LibHeadModuleMk2KeyposeMoveCmd()
        ..startIndex = move.startIndex
        ..aimIndex = move.aimIndex
        ..isLoopEnabled = move.loopFlag
        ..accelInRatio = move.accelInRatio
        ..accelOutRatio = move.accelOutRatio
        ..relativeSpeed = move.relativeSpeed
        ..fixedDurationSec = _speedBasedDuration;
      return EdelkroneCommand(
        name: 'headModule.keyposeMove(->${move.aimIndex})',
        channel: Channel.data,
        build: (p, n) => libs.headModule.keyposeMove(p, n, cmd),
      );
    }
    final cmd = LibSlideModuleSlide()
      ..startIndex = move.startIndex
      ..endIndex = move.aimIndex
      ..isLoopEnabled = move.loopFlag
      ..accelRatioAtStart = move.accelInRatio
      ..accelRatioAtEnd = move.accelOutRatio
      ..topSpeedRelative = move.relativeSpeed;
    return EdelkroneCommand(
      name: 'slideModule.slide(->${move.aimIndex})',
      channel: Channel.data,
      build: (p, n) => libs.slideModule.slide(p, n, cmd),
    );
  }

  EdelkroneCommand motionAbort() => _isHead
      ? EdelkroneCommand(
          name: 'headModule.keyposeAbort',
          channel: Channel.data,
          build: (p, n) => libs.headModule.keyposeAbort(p, n),
        )
      : EdelkroneCommand(
          name: 'slideModule.abortMotion',
          channel: Channel.data,
          build: (p, n) => libs.slideModule.abortMotion(p, n),
        );

  EdelkroneCommand keyposeMoveDurationGet() {
    if (!_isHead) throw _unsupported('keyposeMoveDurationGet');
    return EdelkroneCommand(
      name: 'headModule.keyposeMoveDurationGet',
      channel: Channel.data,
      build: (p, n) => libs.headModule.keyposeMoveDurationGet(p, n),
      expects: LibHeadModuleMk2BleResponse.KEYPOSE_MOVE_DURATION.value,
    );
  }

  EdelkroneCommand numericPositionRead(int index) => _isHead
      ? EdelkroneCommand(
          name: 'headModule.numericControlRead($index)',
          channel: Channel.data,
          build: (p, n) => libs.headModule.numericControlRead(p, n, index),
          expects: LibHeadModuleMk2BleResponse.NUMERIC_VALUE_READOUT.value,
        )
      : EdelkroneCommand(
          name: 'slideModule.numericControlRead($index)',
          channel: Channel.data,
          build: (p, n) => libs.slideModule.numericControlRead(p, n, index),
          expects: LibSlideModuleSliderBleResponse.NUMERIC_DATA_RESPONSE.value,
        );

  EdelkroneCommand manualPanTilt(double pan, double tilt) {
    if (!_isHead) throw _unsupported('manualPanTilt');
    final p0 = _speed(pan, 'pan');
    final t0 = _speed(tilt, 'tilt');
    return EdelkroneCommand(
      name: 'headModule.manualPanTilt',
      channel: Channel.data,
      build: (p, n) => libs.headModule.manualPanTilt(p, n, p0, t0),
    );
  }

  EdelkroneCommand manualJibPanTilt(double pan, double tilt) {
    if (!_isHead) throw _unsupported('manualJibPanTilt');
    final p0 = _speed(pan, 'pan');
    final t0 = _speed(tilt, 'tilt');
    return EdelkroneCommand(
      name: 'headModule.manualJibPanTilt',
      channel: Channel.data,
      build: (p, n) => libs.headModule.manualJibPanTilt(p, n, p0, t0),
    );
  }

  EdelkroneCommand manualSlide(double speed) {
    final s0 = _speed(speed, 'speed');
    return _isHead
        ? EdelkroneCommand(
            name: 'headModule.manualSlide',
            channel: Channel.data,
            build: (p, n) => libs.headModule.manualSlide(p, n, s0),
          )
        : EdelkroneCommand(
            name: 'slideModule.manualSlideFixedReflex',
            channel: Channel.data,
            build: (p, n) => libs.slideModule.manualSlideFixedReflex(p, n, s0),
          );
  }

  /// The layout a head should run, or the fixed one a slider has.
  EdelkroneCommand configuration(EdlSetup setup) {
    if (_isHead) {
      return EdelkroneCommand(
        name: 'headModule.configurationSet(${setup.name})',
        channel: Channel.data,
        build: (p, n) => libs.headModule.configurationSet(p, n, setup),
      );
    }
    final slideSetup = LibSlideModuleEdlSetup.values.firstWhere(
      (c) => c.name == setup.name,
      orElse: () => LibSlideModuleEdlSetup.SLIDE_ONLY,
    );
    return EdelkroneCommand(
      name: 'slideModule.configurationSet(${slideSetup.name})',
      channel: Channel.data,
      build: (p, n) => libs.slideModule.configurationSet(p, n, slideSetup),
    );
  }

  EdelkroneCommand buzzerMuted(bool muted) {
    final flag = muted ? 1 : 0;
    return _isHead
        ? EdelkroneCommand(
            name: 'headModule.settingsBuzzerMutedSet($muted)',
            channel: Channel.data,
            build: (p, n) => libs.headModule.settingsBuzzerMutedSet(p, n, flag),
          )
        : EdelkroneCommand(
            name: 'slideModule.settingsBuzzerMutedSet($muted)',
            channel: Channel.data,
            build: (p, n) => libs.slideModule.settingsBuzzerMutedSet(p, n, flag),
          );
  }

  EdelkroneCommand ioctlStatusGet() => EdelkroneCommand(
    name: 'moco.ioctlStatusGet',
    channel: Channel.ioCtrl,
    build: (p, n) => _moco.ioctlStatusGet(p, n),
    expects: LibEdelkroneMocoResponse.IOCTL_STATUS.value,
  );

  EdelkroneCommand canbusInfoGet() => EdelkroneCommand(
    name: 'moco.canbusInfoGet',
    channel: _mocoChannel,
    build: (p, n) => _moco.canbusInfoGet(p, n),
    expects: LibEdelkroneMocoResponse.CANBUS_INFO_READOUT.value,
  );

  EdelkroneCommand canbusAutoPair() =>
      EdelkroneCommand(name: 'moco.canbusAutoPair', channel: _mocoChannel, build: (p, n) => _moco.canbusAutoPair(p, n));

  /// Invites a module into this unit's group, by radio.
  EdelkroneCommand addPeer({
    required List<int> mac,
    required EdlDevice deviceType,
    required int groupId,
    EdlConfig config = EdlConfig.DOESNT_MATTER,
  }) => EdelkroneCommand(
    name: 'moco.addPeer(${deviceType.name} @ 0x${groupId.toRadixString(16).padLeft(4, '0')})',
    channel: Channel.ioCtrl,
    bufferSize: 32,
    build: (p, n) => EdelkroneMoco.addPeer(p, n, mac, deviceType, config, groupId),
  );

  EdelkroneCommand groupIdSelfSet(int groupId) => EdelkroneCommand(
    name: 'moco.groupIdSelfSet(0x${groupId.toRadixString(16)})',
    channel: Channel.ioCtrl,
    build: (p, n) => EdelkroneMoco.groupIdSelfSet(p, n, groupId),
  );
}
