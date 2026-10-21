/// The app's one controller: find the rig, join it, drive it, store and
/// recall poses, loop between them, and stop.
///
/// Everything that moves goes through the SDK port's [Device]. Two things
/// this design gets from the SDK that the reverse-engineered app could not
/// have:
///
///  - **Joined, the head plans every move for both axes.** With the slider
///    joined to the HeadONE as a layout, a stored pose holds both axes and
///    the head plans the move "so that all axes arrive at the same time"
///    (SDK §5). Starting and stopping together is the device's job now, not
///    the host's — which is why there is no host-side timing model here.
///  - **The head reports its position.** Pan (or tilt) in degrees, slide in
///    centimetres, read live and per stored slot.
///
/// Pure Dart, so it runs against the simulated rig in the tests.
library;

import 'dart:async';

import '../control/stop_registry.dart';
import '../sdk/api/connect.dart' as sdk;
import '../sdk/api/connect.dart' show Seen, joinableWith, normaliseMac, seenOf;
import '../sdk/api/device.dart';
import '../sdk/devices/registry.dart';
import '../sdk/motion/pose.dart';
import '../sdk/protocol/generated/moco.dart';
import '../sdk/session/core.dart';
import '../sdk/session/session.dart' show EdelkroneSession;
import '../sdk/transport/transport.dart';

/// Where the controller is.
enum RigPhase { idle, scanning, connecting, connected, lost }

/// Names given to pose slots, kept per rig. The device holds the poses
/// themselves; this only remembers what the user called them.
abstract class PoseNameStore {
  Future<Map<int, String>> load(String rigKey);
  Future<void> save(String rigKey, Map<int, String> names);
}

class MemoryPoseNameStore implements PoseNameStore {
  final _data = <String, Map<int, String>>{};
  @override
  Future<Map<int, String>> load(String rigKey) async => Map.of(_data[rigKey] ?? const {});
  @override
  Future<void> save(String rigKey, Map<int, String> names) async => _data[rigKey] = Map.of(names);
}

/// The slots the app offers. The protocol carries 16 on a head, but the SDK
/// notes the firmware decides — a HeadPLUS V3 stores 0 to 11 — and a slider
/// has 12, so 12 is what every unit here can be relied on for.
const poseSlots = 12;

class RigController {
  RigController({required this.transport, StopRegistry? registry, PoseNameStore? names})
    : registry = registry ?? StopRegistry.instance,
      _names = names ?? MemoryPoseNameStore();

  final Transport transport;
  final StopRegistry registry;
  final PoseNameStore _names;

  final _changes = StreamController<void>.broadcast();

  /// Fires whenever anything shown on screen may have changed.
  Stream<void> get changes => _changes.stream;
  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  RigPhase phase = RigPhase.idle;
  String? error;

  // -- finding the rig ----------------------------------------------------------

  List<Seen> seen = const [];
  List<Rig> _rigs = const [];
  StreamSubscription<List<EdelkroneDevice>>? _scanSub;

  Future<void> startScan() async {
    if (phase == RigPhase.connecting || phase == RigPhase.connected) return;
    error = null;
    phase = RigPhase.scanning;
    _notify();
    await _scanSub?.cancel();
    _scanSub = transport.devices.listen(_onSeen);
    try {
      await transport.startScan();
      _onSeen(transport.current);
    } catch (e) {
      phase = RigPhase.idle;
      error = e is TransportError ? e.message : '$e';
      _notify();
    }
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await transport.stopScan();
    } catch (_) {}
    if (phase == RigPhase.scanning) phase = RigPhase.idle;
    _notify();
  }

  void _onSeen(List<EdelkroneDevice> units) {
    _rigs = groupIntoRigs([...units]..sort((a, b) => b.rssi.compareTo(a.rssi)));
    seen = [for (final r in _rigs) seenOf(r)];
    _notify();
  }

  /// The units the registry says could join [target]'s leader as modules —
  /// for a HeadONE, a SliderPLUS in range that is not in another layout.
  List<EdelkroneDevice> joinable(Seen target) {
    if (EdelkroneSession.isMultiModule(target.rig.master.advData.setup)) return const [];
    return joinableWith(
      target.rig.master,
      _rigs,
    ).where((u) => u.advData.setup == EdlSetup.NONE || u.advData.setup == EdlSetup.SLIDE_ONLY).toList();
  }

  // -- connecting ------------------------------------------------------------------

  Device? device;
  StreamSubscription<DeviceStatus>? _statusSub;
  StreamSubscription<bool>? _linkSub;
  Seen? _target;
  String _rigKey = '';

  DeviceStatus? get status => device?.status;

  /// Connects to [target]'s leader. With [join], the SDK joins those modules
  /// to it first — by radio for a HeadONE and a SliderPLUS — so that every
  /// stored pose holds both axes.
  Future<void> connect(Seen target, {List<EdelkroneDevice> join = const []}) async {
    if (phase == RigPhase.connecting) return;
    await stopScan();
    phase = RigPhase.connecting;
    error = null;
    _target = target;
    _notify();
    try {
      final d = await sdk.connect(transport, target.rig, withModules: join, seenRigs: _rigs);
      device = d;
      _rigKey = d.info.mac;
      names = await _names.load(_rigKey);
      await d.pollPosition(every: 0.25);
      _statusSub = d.statusUpdates.listen((_) => _notify());
      _linkSub = d.connectionChanges.listen((up) {
        if (!up && phase == RigPhase.connected) {
          _stopLocalMotion();
          phase = RigPhase.lost;
          error =
              'The link to ${d.info.name} dropped. Equipment that was mid-move carries on to the end of '
              'that move; a held joystick stops by itself within 1.5 s. Reconnect to take control again.';
          _notify();
        }
      });
      registry.register(this, stopAll);
      phase = RigPhase.connected;
      _notify();
      unawaited(refreshPoses());
    } catch (e) {
      device = null;
      phase = RigPhase.idle;
      error = e is EdelkroneError ? e.message : '$e';
      _notify();
    }
  }

  /// Connects again to the rig that was lost. A layout survives while its
  /// units stay powered, so this does not join anything again.
  Future<void> reconnect() async {
    final t = _target;
    if (t == null) return;
    await _teardown();
    phase = RigPhase.idle;
    await startScan();
    // Give the leader a moment to advertise again.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      final again = seen.where((s) => normaliseMac(s.mac) == normaliseMac(t.mac)).toList();
      if (again.isNotEmpty) {
        await connect(again.first);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    await stopScan();
    error = '${t.name} did not reappear. Is it powered and in range?';
    _notify();
  }

  /// Stops everything, then disconnects. The SDK does NOT stop moving
  /// equipment on disconnect, so this always stops first.
  Future<void> disconnect() async {
    await stopAll();
    await _teardown();
    phase = RigPhase.idle;
    _notify();
  }

  Future<void> _teardown() async {
    registry.unregister(this);
    _stopLocalMotion();
    await _statusSub?.cancel();
    await _linkSub?.cancel();
    _statusSub = null;
    _linkSub = null;
    final d = device;
    device = null;
    poses = {};
    if (d != null) {
      try {
        await d.disconnect();
      } catch (_) {}
    }
  }

  Set<RigAxis> get axes => device?.drivable() ?? const {};
  List<String> get modules => device?.info.modules ?? const [];
  bool get isJoined => modules.isNotEmpty;

  // -- motion settings ------------------------------------------------------------

  /// Fractions of the device's maximum, as the SDK's [MoveStyle] takes them.
  double speed = 0.5;
  double acceleration = 0.25;

  /// Scales the joystick, so a full push is not necessarily full speed.
  double jogSpeed = 0.6;

  MoveStyle get style => MoveStyle(speed: speed.clamp(0.01, 1.0), acceleration: acceleration.clamp(0.0, 1.0));

  // -- joystick ---------------------------------------------------------------------

  final _held = <RigAxis, double>{};
  Timer? _jogTimer;
  bool _jogBusy = false;
  bool _jogDirty = false;

  /// Holds [axis] at [fraction] of the jog speed, −1 to 1. Repeated every
  /// 100 ms while held, as the device requires; released, it stops at once.
  void hold(RigAxis axis, double fraction) {
    if (device == null) return;
    _held[axis] = (fraction * jogSpeed).clamp(-1.0, 1.0);
    if (_loopRunning || moving) {
      // Grabbing the stick during a loop or a recall takes over: stop that
      // first, and only then start jogging with whatever is still held. A
      // stop and a jog racing each other would leave either the jog swallowed
      // or the planned move still running underneath it.
      if (!_handingOver) unawaited(_handOver());
      return;
    }
    if (_handingOver) return;
    _startJog();
  }

  bool _handingOver = false;

  Future<void> _handOver() async {
    _handingOver = true;
    _loopRunning = false;
    try {
      await device?.move.stop(settle: 1.0);
    } finally {
      _handingOver = false;
      moving = false;
    }
    if (jogging) _startJog();
    _notify();
  }

  void _startJog() {
    _jogTimer ??= Timer.periodic(const Duration(milliseconds: 100), (_) => unawaited(_jogTick()));
    unawaited(_jogTick());
  }

  void release(RigAxis axis) {
    _held[axis] = 0;
    if (_handingOver) return; // the hand-over sees nothing held, and does not start
    unawaited(_jogTick());
  }

  bool get jogging => _held.values.any((v) => v != 0);

  Future<void> _jogTick() async {
    final d = device;
    if (d == null) return;
    if (_jogBusy) {
      // A drive is awaiting its answer; send the latest values as soon as it
      // has one, rather than queueing a backlog of stale ones.
      _jogDirty = true;
      return;
    }
    _jogBusy = true;
    try {
      do {
        _jogDirty = false;
        final allZero = !jogging;
        await d.move.joystick(
          pan: _held[RigAxis.pan] ?? 0,
          tilt: _held[RigAxis.tilt] ?? 0,
          slide: _held[RigAxis.slide] ?? 0,
        );
        if (allZero) {
          _jogTimer?.cancel();
          _jogTimer = null;
          _held.clear();
          break;
        }
      } while (_jogDirty);
    } catch (e) {
      _stopLocalMotion();
      error = e is EdelkroneError ? e.message : '$e';
      _notify();
    } finally {
      _jogBusy = false;
    }
  }

  void _stopLocalMotion() {
    _jogTimer?.cancel();
    _jogTimer = null;
    _held.clear();
    _loopRunning = false;
  }

  // -- poses -------------------------------------------------------------------------

  /// What the user called each slot.
  Map<int, String> names = {};

  /// Where each stored pose is, read back from the device.
  Map<int, RigPose> poses = {};

  /// The slots the device reports holding a pose. The device is the truth:
  /// a pose it no longer holds — after a module was switched off, say — is
  /// not shown as if it were still there.
  List<int> get stored => [
    for (final s in status?.storedPoseSlots ?? const <int>[])
      if (s < poseSlots) s,
  ];

  /// Empty slots between stored poses — left by deleting one in the middle.
  /// A head will not move across them, so they are offered for saving into.
  List<int> get gaps {
    final have = stored.toSet();
    if (have.isEmpty) return const [];
    final hi = have.reduce((a, b) => a > b ? a : b);
    return [
      for (var i = 0; i < hi; i++)
        if (!have.contains(i)) i,
    ];
  }

  /// The slot "save" should use: the next one after the last stored, because
  /// a head moves through every slot in between and stops at an empty one.
  int? get nextSlot {
    final have = stored;
    final next = have.isEmpty ? 0 : have.reduce((a, b) => a > b ? a : b) + 1;
    return next < poseSlots ? next : null;
  }

  /// Would saving into [slot] leave an empty slot between poses?
  bool wouldLeaveGap(int slot) {
    final have = {...stored, slot};
    final hi = have.reduce((a, b) => a > b ? a : b);
    for (var i = 0; i < hi; i++) {
      if (!have.contains(i)) return true;
    }
    return false;
  }

  Future<void> refreshPoses() async {
    final d = device;
    if (d == null) return;
    final next = <int, RigPose>{};
    for (final slot in stored) {
      try {
        final p = await d.poses.readPose(slot);
        if (p != null) next[slot] = p;
      } catch (_) {
        // A pose that cannot be read is still stored; it is just not shown.
      }
    }
    poses = next;
    _notify();
  }

  /// Stores where the equipment is now into [slot] — every axis of the
  /// layout — and confirms the device took it.
  Future<bool> save(int slot, {String? name}) async {
    final d = device;
    if (d == null) return false;
    await _stopForAPoseCommand();
    final ok = await _guard(() => d.poses.store(slot));
    if (ok == true) {
      if (name != null && name.trim().isNotEmpty) {
        names[slot] = name.trim();
        await _names.save(_rigKey, names);
      }
      await refreshPoses();
      return true;
    }
    error ??= 'The device did not store slot $slot.${d.poses.layoutNote() == null ? '' : ' ${d.poses.layoutNote()}'}';
    _notify();
    return false;
  }

  Future<void> rename(int slot, String name) async {
    if (name.trim().isEmpty) {
      names.remove(slot);
    } else {
      names[slot] = name.trim();
    }
    await _names.save(_rigKey, names);
    _notify();
  }

  Future<void> clear(int slot) async {
    final d = device;
    if (d == null) return;
    await _stopForAPoseCommand();
    await _guard(() => d.poses.clear(slot));
    names.remove(slot);
    await _names.save(_rigKey, names);
    await refreshPoses();
  }

  bool moving = false;

  /// Moves every axis to the pose in [slot], planned by the head so they all
  /// arrive together, and verifies arrival.
  Future<MoveOutcome?> recall(int slot) async {
    if (device == null) return null;
    final stops = _stops;
    await _stopForAPoseCommand();
    if (_stops != stops) return null; // STOP ALL while the previous motion was being stopped
    return _recall(slot);
  }

  /// The recall itself, without stopping first — the loop calls this between
  /// legs, where "stop first" would stop the loop.
  Future<MoveOutcome?> _recall(int slot) async {
    final d = device;
    if (d == null) return null;
    moving = true;
    activeSlot = slot;
    _notify();
    try {
      final out = await d.poses.moveTo(slot, style: style);
      if (!out.isSuccess && !_stopping) error = out.reason;
      return out;
    } catch (e) {
      error = e is EdelkroneError ? e.message : '$e';
      return null;
    } finally {
      moving = false;
      _notify();
    }
  }

  int? activeSlot;

  // -- the loop ----------------------------------------------------------------------

  bool _loopRunning = false;
  bool get looping => _loopRunning;
  (int, int)? loopEnds;

  /// Ping-pong between the poses in [a] and [b].
  ///
  /// With no [dwell], this is the DEVICE's own loop (`MoveStyle(loop: true)`):
  /// one command, which the head runs until stopped, so nothing depends on
  /// this app staying alive between legs. With a dwell, the app supervises:
  /// each leg is an ordinary verified recall, then a pause.
  ///
  /// Either way the head first goes to [a] so the loop starts from a known
  /// place, and if [a] and [b] are not neighbours the head passes through
  /// every pose stored between them — that is how its keypose sequence works.
  Future<void> startLoop(int a, int b, {Duration dwell = Duration.zero}) async {
    final d = device;
    if (d == null || a == b) return;
    final stops = _stops;
    await _stopForAPoseCommand();
    if (_stops != stops) return;
    _loopRunning = true;
    loopEnds = (a, b);
    error = null;
    _notify();
    final first = await _recall(a);
    if (!_loopRunning) return;
    if (first == null || !first.isSuccess) {
      _loopRunning = false;
      _notify();
      return;
    }
    if (dwell == Duration.zero) {
      final sent = await _guard(
        () => d.poses.startMoveTo(
          b,
          start: a,
          style: MoveStyle(speed: style.speed, acceleration: style.acceleration, loop: true),
        ),
      );
      if (sent != true) _loopRunning = false;
      moving = _loopRunning;
      _notify();
      return;
    }
    var to = b;
    while (_loopRunning) {
      await Future<void>.delayed(dwell);
      if (!_loopRunning) break;
      final out = await _recall(to);
      if (out == null || !out.isSuccess) break;
      to = to == b ? a : b;
    }
    _loopRunning = false;
    _notify();
  }

  Future<void> stopLoop() async {
    if (!_loopRunning) return;
    _loopRunning = false;
    await stopAll();
  }

  // -- stopping ----------------------------------------------------------------------

  bool _stopping = false;

  /// Bumped by STOP ALL. A recall or loop that was waiting for earlier motion
  /// to stop does not go on to start once STOP ALL has been pressed; one
  /// already inside the SDK is cancelled there.
  int _stops = 0;

  /// Stops all motion: the joystick, a recall, and the device's loop. The SDK's
  /// stop goes to the front of the command queue and never throws.
  Future<void> stopAll() async {
    _stops++;
    _stopping = true;
    _stopLocalMotion();
    try {
      await device?.move.stop();
    } finally {
      _stopping = false;
      moving = false;
      _notify();
    }
  }

  /// A pose command while the head is moving would be ignored ("a device in
  /// motion does not start a planned move"), so stop first.
  Future<void> _stopForAPoseCommand() async {
    if (jogging || _loopRunning || (status?.isMoving ?? false)) {
      _stopLocalMotion();
      await device?.move.stop(settle: 1.0);
    }
  }

  Future<T?> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      error = e is EdelkroneError ? e.message : (e is SessionError ? e.message : '$e');
      _notify();
      return null;
    }
  }

  void clearError() {
    error = null;
    _notify();
  }

  Future<void> dispose() async {
    await disconnect();
    await _changes.close();
  }
}
