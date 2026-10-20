/// A connected unit and the modules in its layout: identity, status,
/// joystick, stop and stored poses.
///
/// Ported from `edelkrone/api/{device,move,poses,status,info,capability}.py`.
/// Scope is what this app's rig uses — heads and sliders, alone or joined —
/// so the dolly paths, the tripod and the focus motor's own controls are not
/// carried across. The focus GATE is: a head that reports a focus motor
/// refuses motion until the lens has been learned, exactly as the SDK does,
/// because a pose on such a head includes the focus position.
///
/// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
library;

import 'dart:async';
import 'dart:math' as math;

import '../devices/registry.dart';
import '../log.dart';
import '../motion/pose.dart';
import '../protocol/generated/head_module.dart';
import '../protocol/generated/moco.dart';
import '../protocol/generated/slide_module.dart';
import '../session/command_set.dart';
import '../session/core.dart';
import '../session/session.dart';
import '../session/state.dart';

/// A refusal or fault surfaced to the app, with the SDK's reason code.
class EdelkroneError implements Exception {
  EdelkroneError(this.reason, this.message, {this.cause});
  final String reason;
  final String message;
  final Object? cause;

  @override
  String toString() => '$reason: $message';
}

enum Capability { position, storedPose, manualDrive, focus, settings, tripodLevel }

Set<Capability> capabilitiesOf(DeviceFamily family) => switch (family) {
      DeviceFamily.headModule => {
          Capability.manualDrive,
          Capability.storedPose,
          Capability.settings,
          Capability.position,
          Capability.focus,
        },
      DeviceFamily.slideModule || DeviceFamily.jib => {
          Capability.manualDrive,
          Capability.storedPose,
          Capability.settings,
          Capability.position,
        },
      DeviceFamily.dolly => {Capability.manualDrive, Capability.settings},
      DeviceFamily.focusPlus => {},
      DeviceFamily.tripod => {Capability.settings, Capability.tripodLevel},
    };

const _head = {RigAxis.pan, RigAxis.tilt};
const _jibArm = {RigAxis.jibPan, RigAxis.jibTilt};

/// The axes each layout can drive or read.
final Map<EdlSetup, Set<RigAxis>?> layoutAxes = {
  EdlSetup.NONE: null,
  EdlSetup.GROUP_MEMBER: null,
  EdlSetup.POSSIBLE_CANBUS_MASTER: null,
  EdlSetup.PAN_ONLY: {RigAxis.pan},
  EdlSetup.TILT_ONLY: {RigAxis.tilt},
  EdlSetup.PAN_TILT: _head,
  EdlSetup.SLIDE_ONLY: {RigAxis.slide},
  EdlSetup.DOLLY_ONLY: {},
  EdlSetup.PAN_AND_SLIDE: {RigAxis.pan, RigAxis.slide},
  EdlSetup.TILT_AND_SLIDE: {RigAxis.tilt, RigAxis.slide},
  EdlSetup.PAN_TILT_AND_SLIDE: {..._head, RigAxis.slide},
  EdlSetup.PAN_AND_DOLLY: {RigAxis.pan},
  EdlSetup.TILT_AND_DOLLY: {RigAxis.tilt},
  EdlSetup.PAN_TILT_AND_DOLLY: _head,
  EdlSetup.PAN_AND_JIB: {RigAxis.pan, RigAxis.slide},
  EdlSetup.TILT_AND_JIB: {RigAxis.tilt, RigAxis.slide},
  EdlSetup.PAN_TILT_AND_JIB: {..._head, RigAxis.slide},
  EdlSetup.JIB_ONLY: {RigAxis.slide},
  EdlSetup.PAN_AND_JIB_PLUS: {RigAxis.pan, ..._jibArm},
  EdlSetup.TILT_AND_JIB_PLUS: {RigAxis.tilt, ..._jibArm},
  EdlSetup.PAN_TILT_AND_JIB_PLUS: {..._head, ..._jibArm},
  EdlSetup.JIB_PLUS_ONLY: _jibArm,
  EdlSetup.FOLLOW_FOCUS_ONLY: {},
  EdlSetup.PAN_TILT_DOLLY_AND_JIB_PLUS: {..._head, ..._jibArm},
  EdlSetup.PAN_TILT_DOLLY_AND_SLIDER: {..._head, RigAxis.slide},
};

/// The axes the family's command set can address at all. The SDK finds these
/// by probing its numeric-move builders; these are the results.
Set<RigAxis> _commandAxes(DeviceFamily f) => switch (f) {
      DeviceFamily.headModule => {RigAxis.pan, RigAxis.tilt, RigAxis.slide, RigAxis.jibPan, RigAxis.jibTilt},
      DeviceFamily.slideModule => {RigAxis.slide},
      _ => {},
    };

Set<RigAxis> axesOf(EdelkroneSession session, EdlSetup? layout) {
  final out = _commandAxes(session.family);
  final fitted = layout == null ? null : layoutAxes[layout];
  if (fitted == null) {
    final known = [
      for (final spec in session.device.model.deviceSetups)
        if (layoutAxes[spec.setup] != null) layoutAxes[spec.setup]!,
    ];
    if (known.isEmpty) return out;
    var inter = known.first;
    for (final k in known.skip(1)) {
      inter = inter.intersection(k);
    }
    final union = known.fold<Set<RigAxis>>({}, (a, b) => a.union(b));
    return out.intersection(inter.isNotEmpty ? inter : union);
  }
  return out.intersection(fitted);
}

class Info {
  const Info({
    required this.name,
    required this.mac,
    required this.firmware,
    required this.radioFirmware,
    required this.firmwareOk,
    required this.layout,
    required this.modules,
    required this.axes,
    required this.capabilities,
  });

  final String name;
  final String mac;
  final String firmware;
  final String radioFirmware;
  final bool firmwareOk;
  final EdlSetup? layout;
  final List<String> modules;
  final List<RigAxis> axes;
  final Set<Capability> capabilities;
}

enum ActivityState {
  idle,
  moving,
  transitioning,
  trackingTarget;

  bool get isMoving => this != ActivityState.idle;
}

const _moduleLayoutBodies = ['SLIDE', 'SLIDER', 'DOLLY', 'JIB'];

/// One reading, in degrees, centimetres and percent. A null field means the
/// device has not reported it.
class DeviceStatus {
  const DeviceStatus({
    required this.model,
    this.at,
    this.activity,
    this.pose = RigPose.unknown,
    this.slideFraction,
    this.batteryPercent,
    this.isCalibrated,
    this.hasFocusMotor,
    this.layout,
    this.storedPoseSlots = const [],
    this.modulesResponding,
    this.moveProgress,
    this.positionIsTrusted = false,
    this.hasStatusFrame = false,
    this.tiltDeg,
    this.isLevel,
    this.orientationWarning,
    this.accel,
  });

  final String model;
  final DateTime? at;
  final ActivityState? activity;
  final RigPose pose;
  final double? slideFraction;
  final double? batteryPercent;
  final bool? isCalibrated;
  final bool? hasFocusMotor;
  final EdlSetup? layout;
  final List<int> storedPoseSlots;
  final bool? modulesResponding;

  /// Progress of a planned move, 0–1. Heads report it.
  final double? moveProgress;

  final bool positionIsTrusted;
  final bool hasStatusFrame;
  final double? tiltDeg;
  final bool? isLevel;
  final bool? orientationWarning;
  final (double, double, double)? accel;

  bool get isMoving => activity?.isMoving ?? false;
  bool get isKnown => hasStatusFrame;

  factory DeviceStatus.fromState(DeviceState state, {EdlSetup? layout, bool driving = false}) {
    final reading = absoluteReadingOf(state);
    final head = state is HeadModuleState ? state.generalStatus : null;
    final slide = state is SlideModuleState ? state.generalStatus : null;

    ActivityState? activity;
    if (driving) {
      activity = ActivityState.moving;
    } else {
      activity = switch (motionStateOf(state)) {
        null => null,
        MotionState.idle => ActivityState.idle,
        MotionState.moving => ActivityState.moving,
        MotionState.transitioning => ActivityState.transitioning,
        MotionState.targetLocked => ActivityState.trackingTarget,
      };
    }

    double? tilt;
    if (head != null && head.inclineMode != LibHeadModuleMk2InclineMode.INVALID) tilt = head.inclineTiltDeg;
    if (slide != null && slide.inclineMode != LibSlideModuleInclineMode.INVALID) tilt = slide.inclineTiltDeg;

    final reportedLayout = head?.configuration ?? slide?.configuration;
    bool? responding;
    if (head != null && _moduleLayoutBodies.any(head.configuration.name.contains)) {
      responding = head.remoteDevicesConnectionOk == 1;
    }

    final fraction = reading?.slideFraction;
    return DeviceStatus(
      model: state.model.displayName,
      at: state.receivedAt,
      activity: activity,
      pose: reading?.pose ?? RigPose.unknown,
      slideFraction: (fraction == null || fraction < 0 || fraction > 1) ? null : fraction,
      batteryPercent: head?.batteryLevel.toDouble() ?? slide?.batteryLevel.toDouble(),
      isCalibrated: head != null ? head.headCalibrated == 1 : (slide != null ? slide.isCalibrated == 1 : null),
      hasFocusMotor: head == null ? null : head.haveFocusModule == 1,
      layout: layout ?? reportedLayout,
      storedPoseSlots: storedSlots(state, PoseKind.keypose),
      modulesResponding: responding,
      moveProgress: head?.keyposeMoveRatio,
      positionIsTrusted: reading?.trusted ?? false,
      hasStatusFrame: head != null || slide != null,
      tiltDeg: tilt,
      isLevel: tilt == null ? null : tilt.abs() <= 15.0,
      orientationWarning: head != null ? head.inclineWarning == 1 : (slide != null ? slide.inclineWarning == 1 : null),
      accel: state.accelerationMs2,
    );
  }
}

/// Speed and acceleration of a planned move, as fractions of the device's
/// maximum. `acceleration` is the share of the move spent accelerating at the
/// start and decelerating at the end.
class MoveStyle {
  const MoveStyle({this.speed = 0.5, this.acceleration = 0.25, this.loop = false});

  final double speed;
  final double acceleration;
  final bool loop;

  MoveRequest request(int aim, {int? start}) {
    if (!speed.isFinite || speed <= 0 || speed > 1) {
      throw EdelkroneError('bad_argument', 'speed must be above 0 and at most 1, got $speed');
    }
    if (!acceleration.isFinite || acceleration < 0 || acceleration > 1) {
      throw EdelkroneError('bad_argument', 'acceleration must be from 0 to 1, got $acceleration');
    }
    return MoveRequest(
      aimIndex: aim,
      startIndex: start ?? fromCurrentPosition,
      loop: loop,
      relativeSpeed: speed,
      accelInRatio: acceleration,
      accelOutRatio: acceleration,
    );
  }
}

class MoveOutcome {
  const MoveOutcome({required this.accepted, required this.completed, required this.duration, this.reason});

  final bool accepted;
  final bool completed;
  final double duration;

  /// Why the move did not happen or did not finish. Null on success.
  final String? reason;

  bool get isSuccess => accepted && completed;

  @override
  String toString() => isSuccess
      ? 'MoveOutcome(ok, ${(duration * 1000).round()} ms)'
      : 'MoveOutcome(${accepted ? 'timed out' : 'refused'}${reason == null ? '' : ': $reason'})';
}

class Device {
  Device(this.session) : capabilities = capabilitiesOf(session.family) {
    poses = PoseController._(this);
    move = MoveControl._(this);
  }

  final EdelkroneSession session;
  final Set<Capability> capabilities;
  late final PoseController poses;
  late final MoveControl move;

  List<EdelkroneDevice> _modules = [];
  Info? _info;
  Set<String> _held = {};

  List<EdelkroneDevice> get modules => List.unmodifiable(_modules);

  void setModules(List<EdelkroneDevice> modules) {
    _modules = List.of(modules);
    _info = null;
  }

  bool get _layoutIsFixed => session.device.model.deviceSetups.length == 1;

  EdlSetup? get layout {
    final reported = session.reportedSetup;
    if ((reported == null || reported == EdlSetup.NONE) && _layoutIsFixed) {
      return session.device.model.deviceSetups.first.setup;
    }
    return reported;
  }

  Set<RigAxis> drivable() => axesOf(session, layout);

  Info get info => _info ??= Info(
        name: session.device.displayName,
        mac: session.device.mac,
        firmware: session.device.firmwareVersion,
        radioFirmware: session.device.radioVersion,
        firmwareOk: session.device.firmwareOk,
        layout: layout,
        modules: [for (final m in _modules) m.displayName],
        axes: drivable().toList()..sort((a, b) => a.name.compareTo(b.name)),
        capabilities: capabilities,
      );

  DeviceStatus get status => _statusOf(session.state);

  Stream<DeviceStatus> get statusUpdates => session.stateUpdates.map(_statusOf);

  DeviceStatus _statusOf(DeviceState state) {
    final s = DeviceStatus.fromState(state, layout: layout, driving: session.isManualControlActive);
    final kept = {...drivable(), RigAxis.focus};
    final p = s.pose;
    if (RigAxis.values.any((a) => !kept.contains(a) && p[a] != null)) {
      return DeviceStatus(
        model: s.model,
        at: s.at,
        activity: s.activity,
        pose: p.only(kept),
        slideFraction: s.slideFraction,
        batteryPercent: s.batteryPercent,
        isCalibrated: s.isCalibrated,
        hasFocusMotor: s.hasFocusMotor,
        layout: s.layout,
        storedPoseSlots: s.storedPoseSlots,
        modulesResponding: s.modulesResponding,
        moveProgress: s.moveProgress,
        positionIsTrusted: s.positionIsTrusted,
        hasStatusFrame: s.hasStatusFrame,
        tiltDeg: s.tiltDeg,
        isLevel: s.isLevel,
        orientationWarning: s.orientationWarning,
        accel: s.accel,
      );
    }
    return s;
  }

  bool get isConnected => session.isConnected;
  Stream<bool> get connectionChanges => session.connectionChanges;

  /// Identity, position and a reading, now. During joystick control only the
  /// position, since the drives already bring the reading.
  Future<void> refresh() async {
    final read = session.commands.numericPositionRead(CommandSet.currentPositionIndex);
    if (session.isManualControlActive) {
      try {
        await session.send(read);
      } on SessionError {
        // The next drive's answer will do.
      }
      return;
    }
    await session.refreshStatus();
    final moving = motionStateOf(session.state);
    if (moving == null || !moving.isMoving) await session.refreshIdentity();
    try {
      await session.send(read);
    } on SessionError {
      // Status alone is still worth having.
    }
    await session.refreshStatus();
  }

  /// Keeps `status.pose` current. Off by default in the SDK, because it
  /// doubles the radio traffic; this app turns it on.
  Future<void> pollPosition({double? every = 0.250}) async {
    if (every == null) {
      await session.stopPositionPolling();
      return;
    }
    if (!every.isFinite || every <= 0) {
      throw EdelkroneError('bad_argument', 'poll_position(every=$every): the interval must be positive');
    }
    session.startPositionPolling(interval: every);
  }

  void startPolling() => session.startStatusPolling();

  /// Closes the connection. **Does not stop moving equipment** — call
  /// `move.stop()` first, in a `finally`.
  Future<void> disconnect() => session.close();

  // -- the focus gate -----------------------------------------------------------

  bool get _focusFitted {
    final st = session.state;
    return st is HeadModuleState && st.generalStatus?.haveFocusModule == 1;
  }

  void _requireFocusSetupFirst(String command) {
    session.assertOpen();
    if (!_focusFitted) return;
    throw EdelkroneError(
      'needs_focus_setup',
      '${session.device.displayName} reports a focus motor. The SDK refuses $command until the lens '
      'has been learned, because a stored pose on this head includes the focus position and would '
      'otherwise put the ring somewhere unintended. This app does not drive focus: learn the lens in '
      'the edelkrone app, or disconnect the focus motor, then connect again.',
    );
  }

  // -- driving --------------------------------------------------------------------

  Future<void> _drive({double pan = 0, double tilt = 0, double slide = 0, double jibPan = 0, double jibTilt = 0}) async {
    session.assertOpen();
    if (!capabilities.contains(Capability.manualDrive)) {
      throw SessionError(SessionFailure.unsupported, '${session.device.displayName} does not support drive');
    }
    for (final (name, v) in [('pan', pan), ('tilt', tilt), ('slide', slide), ('jib_pan', jibPan), ('jib_tilt', jibTilt)]) {
      if (!v.isFinite) {
        throw EdelkroneError('bad_argument',
            '$name must be a finite number, got $v. A non-finite value would drive the axis at full speed');
      }
    }
    final can = drivable();
    double keep(RigAxis a, double v) => can.contains(a) ? v : 0;
    pan = keep(RigAxis.pan, pan);
    tilt = keep(RigAxis.tilt, tilt);
    slide = keep(RigAxis.slide, slide);
    jibPan = keep(RigAxis.jibPan, jibPan);
    jibTilt = keep(RigAxis.jibTilt, jibTilt);

    final groups = {'pan_tilt': pan != 0 || tilt != 0, 'slide': slide != 0, 'jib': jibPan != 0 || jibTilt != 0};
    final held = {for (final e in groups.entries) if (e.value) e.key};
    final released = _held.difference(held);
    _held = held;

    if (held.isEmpty) {
      if (!session.isConnected) {
        session.setManualControlActive(false);
        throw SessionError(SessionFailure.notConnected, '${session.device.displayName} is not connected', command: 'drive');
      }
      if (released.isNotEmpty) {
        await _letGo(released);
      } else {
        session.setManualControlActive(false);
      }
      return;
    }
    session.setManualControlActive(true);
    for (final g in const ['pan_tilt', 'slide', 'jib']) {
      if (released.contains(g)) await _zero(g);
    }
    if (groups['pan_tilt']!) await session.drivePanTilt(pan, tilt);
    if (groups['slide']!) await session.driveSlide(slide);
    if (groups['jib']!) await session.sendDrive(session.commands.manualJibPanTilt(jibPan, jibTilt));
    session.readPositionWhileDriving();
  }

  Future<void> _zero(String group, {bool first = false}) async {
    final c = session.commands;
    try {
      switch (group) {
        case 'pan_tilt':
          if (session.family == DeviceFamily.headModule) await session.sendDrive(c.manualPanTilt(0, 0), first: first);
        case 'slide':
          await session.sendDrive(c.manualSlide(0), first: first);
        case 'jib':
          if (session.family == DeviceFamily.headModule) await session.sendDrive(c.manualJibPanTilt(0, 0), first: first);
      }
    } on SessionError {
      // A zero that does not get through is followed by the abort.
    }
  }

  Future<void> _release(Set<String> groups) async {
    _held = {};
    session.setManualControlActive(false);
    for (final g in const ['pan_tilt', 'slide', 'jib']) {
      if (groups.contains(g)) await _zero(g, first: true);
    }
  }

  Future<void> _letGo(Set<String> groups) async {
    await _release(groups);
    try {
      await session.readPosition();
    } catch (_) {}
    try {
      await session.sendDrive(session.commands.motionAbort());
    } on SessionError {
      // Nothing more to do; the device also stops 1.5 s after the last drive.
    }
  }

  /// The SDK's stop: zero the held axes first, then abort the planned move,
  /// then zero every other axis, abort again, wait for the device to say it
  /// is stationary, and read where it stopped. Never throws.
  Future<void> _stopDriving({double settle = 2.0}) async {
    final held = _held;
    await _release(held);
    if (held.isNotEmpty) {
      try {
        await session.readPosition();
      } catch (_) {}
    }
    try {
      await session.motionAbort();
    } catch (_) {}
    for (final g in const ['pan_tilt', 'slide', 'jib']) {
      if (!held.contains(g)) await _zero(g);
    }
    try {
      await session.sendDrive(session.commands.motionAbort());
    } catch (_) {}
    if (settle > 0) {
      try {
        await session.waitUntilIdle(timeout: settle, settle: 0);
      } catch (_) {}
    }
    try {
      await session.readPosition();
    } catch (_) {}
  }
}

/// Joystick and stop, reached as `device.move`.
class MoveControl {
  MoveControl._(this._d);
  final Device _d;

  /// Sets a speed per axis, −1 to 1. **Repeat about every 100 ms** while the
  /// equipment is to move: when drives stop arriving the device carries on at
  /// the last speed for 1.5 s and then stops by itself. An axis set back to
  /// zero stops at once.
  Future<void> joystick({double pan = 0, double tilt = 0, double slide = 0, double jibPan = 0, double jibTilt = 0}) {
    _d._requireFocusSetupFirst('move.joystick');
    return _d._drive(pan: pan, tilt: tilt, slide: slide, jibPan: jibPan, jibTilt: jibTilt);
  }

  /// Stops everything: joystick and planned move alike. Goes to the front of
  /// the queue. Never throws, so it belongs in a `finally`.
  Future<void> stop({double settle = 2.0}) => _d._stopDriving(settle: (settle.isFinite && settle >= 0) ? settle : 0);

  bool? get isMoving {
    if (_d.session.isManualControlActive) return true;
    final s = motionStateOf(_d.session.state);
    return s == null ? null : s != MotionState.idle;
  }

  Future<bool> waitUntilIdle({double timeout = 60.0}) async {
    final deadline = _d.session.clock.now() + timeout;
    var driven = false;
    while (_d.session.isManualControlActive) {
      driven = true;
      final remaining = deadline - _d.session.clock.now();
      if (remaining <= 0) return false;
      await _d.session.clock.sleep(math.min(0.05, remaining));
    }
    final remaining = math.max(0.0, deadline - _d.session.clock.now());
    if (!driven) return _d.session.waitUntilIdle(timeout: remaining);
    final idle = await _d.session.waitUntilIdle(timeout: remaining, settle: 0);
    if (idle) {
      try {
        await _d.session.readPosition();
      } catch (_) {}
    }
    return idle;
  }
}

class _Gap {
  const _Gap(this.error, this.axis);
  final double error;
  final RigAxis axis;
}

const _arrival = {
  RigAxis.pan: 0.25,
  RigAxis.tilt: 0.25,
  RigAxis.slide: 0.25,
  RigAxis.jibPan: 0.4,
  RigAxis.jibTilt: 0.4,
};
const _readNoise = 0.05;

String _unit(RigAxis a) => a == RigAxis.slide ? 'cm' : 'degrees';

_Gap? _worstMiss(RigPose wanted, RigPose landed) {
  _Gap? worst;
  var worstRatio = 1.0;
  for (final e in _arrival.entries) {
    final x = wanted[e.key];
    final y = landed[e.key];
    if (x == null || y == null) continue;
    final gap = (x - y).abs();
    final ratio = gap / e.value;
    if (ratio > worstRatio) {
      worstRatio = ratio;
      worst = _Gap(gap, e.key);
    }
  }
  return worst;
}

bool _allWithin(RigPose a, RigPose b, double limit) {
  for (final axis in _arrival.keys) {
    final x = a[axis];
    final y = b[axis];
    if (x != null && y != null && (x - y).abs() > limit) return false;
  }
  return true;
}

List<String> _lostAxes(RigPose before, RigPose landed) => [
      for (final a in RigAxis.values)
        if (before[a] != null && landed[a] == null) a.name,
    ];

/// Stored poses, reached as `device.poses`. A pose is every axis of the
/// layout, stored in a numbered slot ON THE DEVICE; in a layout the leader
/// plans the move so that **all axes arrive at the same time**.
class PoseController {
  PoseController._(this._d);
  final Device _d;

  EdelkroneSession get _s => _d.session;

  List<int> get stored => _s.storedPoses(PoseKind.keypose);

  void _checkSlot(String command, int value, {String name = 'slot'}) {
    if (!_d.capabilities.contains(Capability.storedPose)) {
      throw SessionError(SessionFailure.unsupported, '${_s.device.displayName} does not store poses', command: command);
    }
    final count = slotCount(_s.state, PoseKind.keypose);
    if (count <= 0) throw SessionError(SessionFailure.unsupported, 'this unit has no pose slots', command: command);
    if (value < 0 || value >= count) {
      throw EdelkroneError('bad_argument', '$command: $name must be from 0 to ${count - 1}, got $value');
    }
  }

  /// Stores the current position and confirms the device took it. False if
  /// it did not — a slot the firmware does not provide, for instance.
  Future<bool> store(int slot) async {
    _d._requireFocusSetupFirst('poses.store');
    _checkSlot('poses.store', slot);
    final ok = await _s.storePose(slot);
    if (!ok) {
      final note = layoutNote();
      if (note != null) EdelkroneLog.warning(() => 'poses.store($slot) was refused: $note');
    }
    return ok;
  }

  Future<void> clear(int slot) async {
    _d._requireFocusSetupFirst('poses.clear');
    _checkSlot('poses.clear', slot);
    await _s.send(_s.commands.keyposeDelete(slot));
    await _s.refreshStatus();
  }

  Future<void> clearAll() async {
    for (final slot in List.of(stored)) {
      await clear(slot);
    }
  }

  /// Why a stored-pose operation failed when the layout changed underneath
  /// it: a module switched off dissolves the layout and deletes its poses.
  String? layoutNote() {
    final then = _d._info?.layout;
    if (then == null) return null;
    final now = _d.layout;
    if (now == then || !EdelkroneSession.isMultiModule(then)) return null;
    return 'the layout changed from ${then.name.toLowerCase()} to ${now == null ? 'none' : now.name.toLowerCase()} '
        'since connecting. A module of the layout was switched off: the device dissolved the layout '
        'and deleted its stored poses. Switch the module on and connect again.';
  }

  Future<void> _refreshForAPrecondition() async {
    try {
      await _s.refreshStatus();
    } on SessionError catch (e) {
      if (e.failure != SessionFailure.timeout) rethrow;
    }
  }

  String? _emptySlotReason(int slot, int? start) {
    for (final (which, number) in [('slot', slot), ('start slot', start)]) {
      if (number != null && !stored.contains(number)) {
        final note = layoutNote();
        return '$which $number is empty${note == null ? '' : ': $note'}';
      }
    }
    return _gapReason(slot, start);
  }

  /// A head moves from pose to pose through every slot in between and will
  /// not arrive across an empty one.
  String? _gapReason(int slot, int? start) {
    if (_s.family != DeviceFamily.headModule) return null;
    final st = _s.state;
    final at = st is HeadModuleState ? st.generalStatus?.currentKeyposeAimIndex : null;
    final have = stored.toSet();
    final legs = <(int, int)>[];
    final origin = (at != null && have.contains(at)) ? at : null;
    if (start != null) {
      if (origin != null && origin != start) legs.add((origin, start));
      legs.add((start, slot));
    } else if (origin != null && origin != slot) {
      legs.add((origin, slot));
    }
    for (final (a, b) in legs) {
      final lo = math.min(a, b);
      final hi = math.max(a, b);
      final empty = [for (var i = lo + 1; i < hi; i++) if (!have.contains(i)) i];
      if (empty.isNotEmpty) {
        final plural = empty.length > 1;
        return 'slot${plural ? 's' : ''} ${empty.join(', ')} between pose $a and pose $b '
            '${plural ? 'are' : 'is'} empty. A head moves from pose to pose through every slot in between '
            'and does not arrive across an empty one: store poses in consecutive slots, each in a different place';
      }
    }
    return null;
  }

  List<int> _via(int slot, int? start) {
    if (_s.family != DeviceFamily.headModule) return [];
    final st = _s.state;
    final at = st is HeadModuleState ? st.generalStatus?.currentKeyposeAimIndex : null;
    final origin = start ?? at;
    final have = stored.toSet();
    if (origin == null || !have.contains(origin) || origin == slot) return [];
    final step = slot > origin ? 1 : -1;
    return [for (var i = origin + step; i != slot; i += step) if (have.contains(i)) i];
  }

  Future<RigPose?> _poseInSlot(int slot) async {
    try {
      await _s.send(_s.commands.numericPositionRead(slot));
    } on SessionError {
      return null;
    }
    final st = _s.state;
    if (st is SlideModuleState) {
      final r = st.slotReadout;
      if (r == null || r.index != slot) return null;
      return RigPose(slideCm: r.value);
    }
    if (st is! HeadModuleState) return null;
    final r = st.slotReadout;
    if (r == null || r.index != slot) return null;
    final v = r.value;
    final jibbed = headHasJib(st.generalStatus);
    final focused = st.generalStatus == null ? null : st.generalStatus!.haveFocusModule == 1;
    return RigPose.fromRaw(
      panDeg: v.panDeg,
      tiltDeg: v.tiltDeg,
      slideCm: v.sliderCm,
      focusCm: focused == false ? null : v.focusCm,
      jibPanDeg: jibbed == false ? null : v.jibPanDeg,
      jibTiltDeg: jibbed == false ? null : v.jibTiltDeg,
    );
  }

  Future<RigPose?> _livePose() async {
    try {
      await _s.send(_s.commands.numericPositionRead(CommandSet.currentPositionIndex));
    } on SessionError {
      return null;
    }
    await _s.refreshStatus();
    final r = absoluteReadingOf(_s.state);
    if (r == null || r.pose.isEmpty) return null;
    return r.pose;
  }

  /// Moves to the pose in [slot] and waits until the equipment is stationary.
  /// With [verify], reads the stored pose and where the equipment landed, and
  /// reports success only if every axis of the layout arrived — within 0.25°
  /// on the head and 0.25 cm on the slider. A refusal is returned, not thrown.
  Future<MoveOutcome> moveTo(
    int slot, {
    MoveStyle style = const MoveStyle(),
    int? start,
    double timeout = 60.0,
    bool verify = true,
  }) async {
    _d._requireFocusSetupFirst('poses.move_to');
    if (!timeout.isFinite || timeout <= 0) {
      throw EdelkroneError('bad_argument', 'timeout must be a positive number of seconds, got $timeout');
    }
    _checkSlot('poses.move_to', slot);
    if (start != null) _checkSlot('poses.move_to', start, name: 'start');
    if (style.loop) {
      throw EdelkroneError('bad_argument',
          'a loop does not finish, so move_to() cannot wait for it. Start it with startMoveTo and end it with move.stop()');
    }
    final request = style.request(slot, start: start);
    final started = _s.clock.now();
    await _refreshForAPrecondition();
    final refusal = _emptySlotReason(slot, start);
    if (refusal != null) return MoveOutcome(accepted: false, completed: false, duration: 0, reason: refusal);

    final wasBusy = motionStateOf(_s.state) == MotionState.moving;
    final via = _via(slot, start);
    RigPose? wanted;
    RigPose? before;
    if (verify) {
      wanted = await _poseInSlot(slot);
      before = await _livePose();
    }
    await _s.send(_s.commands.keyposeMove(request));
    final done = await _s.waitUntilIdle(timeout: timeout);
    final elapsed = _s.clock.now() - started;
    if (!done) {
      return MoveOutcome(accepted: true, completed: false, duration: elapsed, reason: 'still moving after ${timeout.toInt()} s');
    }
    if (wanted == null) return MoveOutcome(accepted: true, completed: true, duration: elapsed);
    var landed = await _livePose();
    if (landed == null) return MoveOutcome(accepted: true, completed: true, duration: elapsed);

    final lost = before == null ? <String>[] : _lostAxes(before, landed);
    if (lost.isNotEmpty) {
      return MoveOutcome(
        accepted: true,
        completed: false,
        duration: elapsed,
        reason: 'the ${lost.join(', ')} axis left the layout during the move: before $before, after $landed. '
            'The module carrying it is no longer responding, so that axis was not moved to the pose.',
      );
    }
    final judged = _d.drivable();
    wanted = wanted.only(judged);
    landed = landed.only(judged);
    before = before?.only(judged);
    final missed = _worstMiss(wanted, landed);
    if (missed == null) return MoveOutcome(accepted: true, completed: true, duration: elapsed);

    if (before != null && _allWithin(before, landed, _readNoise)) {
      final shortMove = missed.axis == RigAxis.slide
          ? 'A planned slider move shorter than about 1 cm may not start.'
          : 'A planned move shorter than about 3 degrees may not start.';
      return MoveOutcome(
        accepted: true,
        completed: false,
        duration: elapsed,
        reason: 'the equipment did not move: it was ${missed.error.toStringAsFixed(2)} ${_unit(missed.axis)} from the '
            'pose on the ${missed.axis.name} axis and the device did not start the planned move. $shortMove',
      );
    }
    final busyNote = wasBusy
        ? ' When the move was sent, the device was already reporting motion, and a device in motion does not '
            'start a planned move. Call move.stop() first.'
        : '';
    final viaNote = via.isEmpty
        ? ''
        : ' The head passed through the pose${via.length > 1 ? 's' : ''} in slot${via.length > 1 ? 's' : ''} '
            '${via.join(', ')} on the way; it stops at two consecutive poses stored in the same place.';
    return MoveOutcome(
      accepted: true,
      completed: false,
      duration: elapsed,
      reason: 'the device reported idle but the equipment is off by ${missed.error.toStringAsFixed(2)} '
          '${_unit(missed.axis)} on the ${missed.axis.name} axis: pose $wanted, position $landed. '
          '${before != null ? 'The equipment moved but stopped short of the pose: the move was stopped, for example by move.stop(), or did not finish.' : 'The move may not have started.'}'
          '$busyNote$viaNote',
    );
  }

  /// Sends the move and returns at once. With `MoveStyle(loop: true)` and a
  /// [start] slot, the device runs back and forth between the two poses until
  /// `move.stop()` — the ping-pong is the DEVICE's, not the app's.
  Future<void> startMoveTo(int slot, {MoveStyle style = const MoveStyle(), int? start}) async {
    _d._requireFocusSetupFirst('poses.start_move_to');
    _checkSlot('poses.start_move_to', slot);
    if (start != null) _checkSlot('poses.start_move_to', start, name: 'start');
    final request = style.request(slot, start: start);
    await _refreshForAPrecondition();
    final refusal = _emptySlotReason(slot, start);
    if (refusal != null) throw EdelkroneError('bad_argument', refusal);
    await _s.send(_s.commands.keyposeMove(request));
  }
}
