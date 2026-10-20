/// What the session knows about a device, and the questions asked of it.
///
/// Ported from `edelkrone/session/{state,queries}.py`, for the head and
/// slider families.
///
/// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
library;

import '../devices/model_type.dart';
import '../protocol/generated/head_module.dart';
import '../protocol/generated/moco.dart';
import '../protocol/generated/slide_module.dart';
import 'core.dart';

/// A position readout with the slot it describes; 255 is the live position.
class NumericReadout<T> {
  const NumericReadout(this.index, this.value);
  final int index;
  final T value;
}

abstract class DeviceState {
  DeviceState(this.model);

  final EdelkroneDeviceModel model;
  LibEdelkroneMocoCanbusInfo? canbusInfo;
  LibEdelkroneMocoIoctlStatus? ioctlStatus;

  /// Monotonic seconds of the last applied frame, from the session clock.
  double? lastUpdate;

  /// Wall-clock time the last frame arrived.
  DateTime? receivedAt;

  DeviceFamily get family;

  /// Accelerometer, m/s², where the frame carries it.
  (double, double, double)? accelerationMs2;

  static DeviceState forFamily(DeviceLibraries libs) => switch (libs.family) {
    DeviceFamily.headModule => HeadModuleState(libs.model),
    DeviceFamily.slideModule => SlideModuleState(libs.model),
    _ => throw SessionError(SessionFailure.unsupported, '${libs.model.displayName} is not driven by this port'),
  };
}

class HeadModuleState extends DeviceState {
  HeadModuleState(super.model);

  @override
  DeviceFamily get family => DeviceFamily.headModule;

  LibHeadModuleMk2HeadVersionData? version;
  LibHeadModuleMk2Status? generalStatus;
  LibHeadModuleMk2Settings? settings;
  LibHeadModuleMk2KeyposeUniqueID? keyposeUniqueId;
  double? keyposeMoveDurationSec;
  double? remotePositionMoveDurationSec;
  LibHeadModuleMk2RemoteFirmwareVersions? remoteFirmwareVersion;
  LibHeadModuleMk2RemoteDeviceType? remoteDeviceType;
  LibHeadModuleMk2RemoteVersion? remoteVersion;
  int remoteVersionUpdates = 0;

  /// Live position: index 255.
  NumericReadout<LibHeadModuleMk2DigitalReadout>? numericReadout;

  /// A stored slot's position, read back to verify a move against.
  NumericReadout<LibHeadModuleMk2DigitalReadout>? slotReadout;
}

class SlideModuleState extends DeviceState {
  SlideModuleState(super.model);

  @override
  DeviceFamily get family => DeviceFamily.slideModule;

  LibSlideModuleSliderVersionData? version;
  LibSlideModuleStatus? generalStatus;
  LibSlideModuleSettings? settings;
  List<int>? slideLocationUniqueId;
  NumericReadout<double>? numericReadout;
  NumericReadout<double>? slotReadout;
}

enum MotionState {
  idle,
  moving,
  transitioning,
  targetLocked;

  bool get isMoving => this != MotionState.idle;
}

MotionState? motionStateOf(DeviceState state) {
  if (state is HeadModuleState) {
    final s = state.generalStatus;
    if (s == null) return null;
    return switch (s.state) {
      LibHeadModuleMk2HeadState.IDLE => MotionState.idle,
      LibHeadModuleMk2HeadState.TARGET_LOCKED => MotionState.targetLocked,
      LibHeadModuleMk2HeadState.TARGET_TRANSITION => MotionState.transitioning,
      _ => MotionState.moving,
    };
  }
  if (state is SlideModuleState) {
    final s = state.generalStatus;
    if (s == null) return null;
    return s.state == LibSlideModuleSliderState.IDLE ? MotionState.idle : MotionState.moving;
  }
  return null;
}

enum PoseKind { keypose, remotePosition, target }

int slotCount(DeviceState state, PoseKind kind) {
  if (state is HeadModuleState) return 16;
  if (state is SlideModuleState) return kind == PoseKind.keypose ? 12 : 0;
  return 0;
}

List<int> storedSlots(DeviceState state, PoseKind kind) {
  List<int>? flags;
  if (state is HeadModuleState) {
    final s = state.generalStatus;
    if (s != null) {
      flags = switch (kind) {
        PoseKind.keypose => s.keyposeValid,
        PoseKind.remotePosition => s.remotePosValid,
        PoseKind.target => s.targetValid,
      };
    }
  } else if (state is SlideModuleState) {
    if (kind == PoseKind.keypose) flags = state.generalStatus?.locationsValid;
  }
  if (flags == null) return [];
  return [
    for (var i = 0; i < flags.length; i++)
      if (flags[i] != 0) i,
  ];
}

/// The layout the device itself reports.
EdlSetup? reportedSetupOf(DeviceState s) => switch (s) {
  HeadModuleState(:final generalStatus) => generalStatus?.configuration,
  SlideModuleState(:final generalStatus) => generalStatus?.configuration,
  _ => null,
};
