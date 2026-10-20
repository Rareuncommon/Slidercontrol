/// One connection to one unit: commands, replies, polling, layouts and poses.
///
/// Ported from `edelkrone/session/session.py`, for the head and slider
/// families, from threads to the event loop. The rules carried across:
///
///  - **One command in flight.** Each command waits its turn on a FIFO lock;
///    a stop goes to the front ([sendImmediate]).
///  - **A reply is the next frame of the expected type on the same channel.**
///    The waiter is registered before the write, so a fast reply cannot slip
///    past it.
///  - **Polling yields.** The 250 ms status poll skips a tick while a command
///    is in flight, and while the joystick's own answers already carry the
///    status.
///  - **A drop is reported, not repaired.** Polling stops, the waiting
///    command fails with `notConnected`, and nothing reconnects by itself.
///
/// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
library;

// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math' as math;

import '../devices/registry.dart';
import '../log.dart';
import '../protocol/generated/moco.dart';
import '../transport/transport.dart';
import 'command_set.dart';
import 'concurrency.dart';
import 'core.dart';
import 'responses.dart';
import 'state.dart';

const multiModuleSetups = {
  EdlSetup.PAN_AND_SLIDE,
  EdlSetup.TILT_AND_SLIDE,
  EdlSetup.PAN_TILT_AND_SLIDE,
  EdlSetup.PAN_AND_DOLLY,
  EdlSetup.TILT_AND_DOLLY,
  EdlSetup.PAN_TILT_AND_DOLLY,
  EdlSetup.PAN_AND_JIB,
  EdlSetup.TILT_AND_JIB,
  EdlSetup.PAN_TILT_AND_JIB,
  EdlSetup.PAN_AND_JIB_PLUS,
  EdlSetup.TILT_AND_JIB_PLUS,
  EdlSetup.PAN_TILT_AND_JIB_PLUS,
  EdlSetup.PAN_TILT_DOLLY_AND_JIB_PLUS,
  EdlSetup.PAN_TILT_DOLLY_AND_SLIDER,
};

const _settingReplyTimeout = 1.5;
const _settingReadTimeout = 1.0;
const _settingConfirmTimeout = 4.0;

/// The modules a layout's name says it contains, for comparing layouts.
Set<String> layoutBodies(EdlSetup setup) => setup.name
    .replaceAll('_PLUS', 'PLUS')
    .split('_')
    .where((t) => t != 'AND' && t != 'ONLY')
    .map((t) => t.replaceAll('SLIDER', 'SLIDE'))
    .toSet();

bool layoutCovers(EdlSetup reported, EdlSetup expected) => layoutBodies(reported).containsAll(layoutBodies(expected));

enum RigSetupRoute { standalone, wireless, wired }

enum CanbusPairOutcome { connected, failed, timedOut, notAnswered, disconnected }

class CanbusPairResult {
  const CanbusPairResult({required this.outcome, required this.groupId, required this.polls});
  final CanbusPairOutcome outcome;
  final int groupId;
  final int polls;
}

class RigSetupResult {
  const RigSetupResult({
    required this.route,
    required this.groupId,
    required this.setup,
    this.peersAdded = 0,
    this.pairing,
    this.reportedSetup,
  });
  final RigSetupRoute route;
  final int groupId;
  final EdlSetup setup;
  final int peersAdded;
  final CanbusPairResult? pairing;
  final EdlSetup? reportedSetup;

  @override
  String toString() =>
      'RigSetup(${route.name}, ${setup.name}, group 0x${groupId.toRadixString(16)}'
      '${route == RigSetupRoute.wireless ? ', $peersAdded peers' : ''})';
}

class _Waiter {
  _Waiter(this.channel, this.type);
  final Channel channel;
  final int type;
  final completer = Completer<ResponseFrame>();
}

/// Wall-clock and sleep, injectable so tests need not wait on real time.
class SessionClock {
  const SessionClock();
  double now() => _watch.elapsedMicroseconds / 1e6;
  Future<void> sleep(double s) => Future<void>.delayed(seconds(s));
  static final _watch = Stopwatch()..start();
}

class EdelkroneSession {
  EdelkroneSession._({
    required this.device,
    required this.config,
    required DeviceLink link,
    required this.libs,
    required SessionClock clock,
  }) : commands = CommandSet(libs),
       _link = link,
       _codec = FamilyCodec.forFamily(libs.family),
       _clock = clock,
       state = DeviceState.forFamily(libs) {
    _roundTrips = RoundTripMonitor(config);
  }

  final EdelkroneDevice device;
  final SessionConfig config;
  final DeviceLibraries libs;
  final CommandSet commands;
  final DeviceState state;

  final DeviceLink _link;
  final FamilyCodec _codec;
  final SessionClock _clock;
  late final RoundTripMonitor _roundTrips;

  final _stateUpdates = StreamController<DeviceState>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  final _gate = FifoLock();
  _Waiter? _waiter;
  int _inFlight = 0;
  double _lastExchange = 0;
  bool _disposed = false;
  bool _settingsAnswered = true;
  bool _positionReadable = true;

  PeriodicWorker? _statusWorker;
  PeriodicWorker? _positionWorker;
  NudgedWorker? _driveReader;

  bool _manualActive = false;
  double _lastDrive = double.negativeInfinity;
  double _lastDriveAnswer = double.negativeInfinity;
  double _lastPositionRead = double.negativeInfinity;
  int _driveMisses = 0;
  int _readsHeld = 0;

  static Future<EdelkroneSession> open(
    Transport transport,
    EdelkroneDevice device, {
    SessionConfig config = const SessionConfig(),
    SessionClock clock = const SessionClock(),
  }) async {
    final libs = DeviceLibraries.of(device.model);
    DeviceLink? link;
    Object? lastError;
    for (var attempt = 1; attempt <= config.connectAttempts; attempt++) {
      try {
        link = await transport.connect(device);
        break;
      } catch (e) {
        lastError = e;
        EdelkroneLog.warning(
          () => '${device.displayName}: connection attempt $attempt/${config.connectAttempts} failed: $e',
        );
        if (attempt < config.connectAttempts) await clock.sleep(config.connectBackoff);
      }
    }
    if (link == null) {
      throw SessionError(
        SessionFailure.notConnected,
        '${device.displayName}: could not connect in ${config.connectAttempts} attempts',
        cause: lastError,
      );
    }
    try {
      await link.requestLowLatency();
    } catch (_) {
      // Advisory only.
    }
    final s = EdelkroneSession._(device: device, config: config, link: link, libs: libs, clock: clock);
    s._listen();
    EdelkroneLog.info(() => 'session opened: ${device.displayName} (${libs.family.name})');
    return s;
  }

  /// Opens a session over a link that is already up. For tests, and for a
  /// transport that manages its own connection attempts.
  static EdelkroneSession attach(
    DeviceLink link, {
    SessionConfig config = const SessionConfig(),
    SessionClock clock = const SessionClock(),
  }) {
    final s = EdelkroneSession._(
      device: link.device,
      config: config,
      link: link,
      libs: DeviceLibraries.of(link.device.model),
      clock: clock,
    );
    s._listen();
    return s;
  }

  Stream<DeviceState> get stateUpdates => _stateUpdates.stream;
  bool get isConnected => _link.isConnected && !_disposed;
  Stream<bool> get connectionChanges => _link.connectionChanges;
  bool get isBusy => _inFlight > 0;
  DeviceFamily get family => libs.family;
  SessionClock get clock => _clock;

  void assertOpen() => _assertUsable();

  // -- sending ----------------------------------------------------------------

  Future<ResponseFrame?> send(EdelkroneCommand command, {double? timeout}) => _send(command, timeout);

  /// Sends [command] only if [cancelled] is still false when its turn in the
  /// queue comes, and returns whether it was sent. A stop that goes to the
  /// front of the queue therefore also cancels a planned move queued behind
  /// it. An addition to the SDK.
  Future<bool> sendUnlessCancelled(EdelkroneCommand command, bool Function() cancelled) {
    _assertUsable();
    return _serialised(() async {
      if (cancelled()) return false;
      await _exchange(command, null);
      return true;
    });
  }

  Future<ResponseFrame?> _send(EdelkroneCommand command, double? timeout, {bool first = false}) {
    _assertUsable();
    return _serialised(() => _exchange(command, timeout), first: first);
  }

  /// A setting the device may not acknowledge: read back until it has taken.
  Future<bool> sendSetting(EdelkroneCommand command, {required bool Function(DeviceState) taken}) async {
    final reply = commands.settingsGet().expects;
    final deadline = _clock.now() + _settingConfirmTimeout;
    var answered = false;
    if (_settingsAnswered) {
      try {
        await _send(command.withExpects(reply), _settingReplyTimeout);
        answered = true;
      } on SessionError catch (e) {
        if (e.failure != SessionFailure.timeout || e.cause != null) rethrow;
        _settingsAnswered = false;
      }
    } else {
      await _send(command, null);
    }
    var readBack = !answered;
    while (readBack || !taken(state)) {
      readBack = false;
      final remaining = deadline - _clock.now();
      if (remaining <= 0) return false;
      try {
        await _send(commands.settingsGet(), math.min(_settingReadTimeout, remaining));
      } on SessionError {
        // Try again until the deadline.
      }
    }
    return true;
  }

  /// Puts [command] at the front of the queue. Used by every stop.
  Future<void> sendImmediate(EdelkroneCommand command) {
    EdelkroneLog.info(() => '${command.name}: to the front of the queue');
    return sendDrive(command, first: true);
  }

  Future<void> motionAbort() => sendImmediate(commands.motionAbort());

  Future<ResponseFrame?> _exchange(EdelkroneCommand command, double? override) async {
    if (!isConnected) {
      throw SessionError(SessionFailure.notConnected, '${device.displayName} is not connected', command: command.name);
    }
    final packet = command.encode();
    final expects = command.expects;
    _Waiter? waiter;
    if (expects != null) {
      waiter = _Waiter(command.channel, expects);
      _waiter = waiter;
    }
    final timeout = override ?? _timeoutFor();
    final started = _clock.now();
    try {
      EdelkroneLog.trace(() => '-> ${command.channel.name} ${command.name}: ${_hex(packet)}');
      await _link.write(command.channel, packet);
      if (waiter == null) {
        _lastExchange = _clock.now();
        return null;
      }
      final reply = await waiter.completer.future.timeout(seconds(timeout));
      final elapsed = _clock.now() - started;
      _lastExchange = _clock.now();
      _roundTrips.record(elapsed);
      return reply;
    } on TimeoutException {
      _lastExchange = _clock.now();
      throw SessionError(
        SessionFailure.timeout,
        '${command.channel.name}: no reply within ${(timeout * 1000).round()} ms to type-$expects',
        command: command.name,
      );
    } on TransportError catch (e) {
      throw SessionError(
        e.failure == TransportFailure.timeout ? SessionFailure.timeout : SessionFailure.notConnected,
        e.message,
        command: command.name,
        cause: e,
      );
    } finally {
      if (identical(_waiter, waiter)) _waiter = null;
    }
  }

  double _timeoutFor() {
    final idle = _clock.now() - _lastExchange;
    return _roundTrips.budget(cold: idle > config.coldAfter);
  }

  Future<T> _serialised<T>(Future<T> Function() body, {bool first = false}) async {
    _inFlight++;
    try {
      await _gate.acquire(first: first);
      try {
        return await body();
      } finally {
        _gate.release();
      }
    } finally {
      _inFlight--;
    }
  }

  // -- receiving --------------------------------------------------------------

  void _listen() {
    for (final channel in Channel.values) {
      _subs.add(_link.notifications(channel).listen((data) => _onFrame(channel, data)));
    }
    _subs.add(_link.connectionChanges.listen(_onConnectionChange));
  }

  void _onConnectionChange(bool up) {
    if (up) return;
    EdelkroneLog.info(() => '${device.displayName} dropped');
    unawaited(stopStatusPolling());
    unawaited(stopPositionPolling());
    final w = _waiter;
    if (w != null && !w.completer.isCompleted) {
      w.completer.completeError(
        SessionError(SessionFailure.notConnected, 'the connection dropped while waiting for a reply'),
      );
    }
  }

  ParseContext get _parseContext {
    final setup = device.setup ?? DeviceSetup(masterDevice: device, setupType: device.advData.setup);
    return ParseContext(libs: libs, hasLiveMode: hasLiveMode(setup));
  }

  bool get supportsLiveMode => _parseContext.hasLiveMode;

  void _onFrame(Channel channel, List<int> data) {
    final frame = ResponseFrame(channel, List<int>.of(data));
    if (!frame.checksumOk) {
      EdelkroneLog.warning(() => '${channel.name}: bad checksum: ${_hex(data)}');
      return;
    }
    ParseOutcome outcome;
    try {
      outcome = channel == Channel.data ? _codec.apply(frame, state, _parseContext) : MocoCodec.apply(frame, state);
    } catch (e) {
      EdelkroneLog.error(() => 'the parser threw on a frame with a valid checksum: $e');
      return;
    }
    if (!outcome.recognised) {
      logUnrecognised(frame, libs.family);
      return;
    }
    if (outcome.applied) {
      state.lastUpdate = _clock.now();
      state.receivedAt = DateTime.now();
      if (!_stateUpdates.isClosed) _stateUpdates.add(state);
    }
    final w = _waiter;
    if (w != null && w.channel == channel && w.type == frame.type && !w.completer.isCompleted) {
      w.completer.complete(frame);
    }
  }

  // -- polling ----------------------------------------------------------------

  void startStatusPolling() {
    _assertUsable();
    unawaited(_statusWorker?.stop());
    _statusWorker = PeriodicWorker('status:${device.mac}', seconds(config.statusInterval), _poll)..start();
  }

  Future<void> stopStatusPolling() async {
    final w = _statusWorker;
    _statusWorker = null;
    await w?.stop();
  }

  Future<void> _poll() async {
    if (_disposed || !isConnected) {
      unawaited(stopStatusPolling());
      return;
    }
    if (isBusy || _stickBringsStatus()) return;
    try {
      await send(commands.statusGet());
    } on SessionError catch (e) {
      if (e.failure == SessionFailure.notConnected) unawaited(stopStatusPolling());
    }
  }

  Future<void> refreshStatus() async {
    await send(commands.statusGet());
  }

  void startPositionPolling({double interval = 0.250}) {
    _assertUsable();
    unawaited(_positionWorker?.stop());
    _positionWorker = PeriodicWorker('position:${device.mac}', seconds(interval), _pollPosition)..start();
  }

  Future<void> stopPositionPolling() async {
    final w = _positionWorker;
    _positionWorker = null;
    await w?.stop();
  }

  Future<void> _pollPosition() async {
    if (_disposed || !isConnected) {
      unawaited(stopPositionPolling());
      return;
    }
    if (isBusy || _readsHeld > 0) return;
    if (_clock.now() - _lastPositionRead < config.drivePositionInterval / 2) return;
    _lastPositionRead = _clock.now();
    try {
      await send(commands.numericPositionRead(CommandSet.currentPositionIndex));
    } on SessionError catch (e) {
      if (e.failure == SessionFailure.notConnected) unawaited(stopPositionPolling());
    }
  }

  // -- driving ----------------------------------------------------------------

  bool get isManualControlActive => _manualActive && _clock.now() - _lastDrive < config.manualHold;

  void setManualControlActive(bool active) {
    _manualActive = active;
    if (active) _lastDrive = _clock.now();
  }

  /// A drive packet. The device answers it with a status frame, which is
  /// waited for — briefly — so the joystick both paces itself and keeps the
  /// status fresh. After [SessionConfig.driveReplyMisses] unanswered drives in
  /// a row, drives go out without waiting.
  Future<void> sendDrive(EdelkroneCommand command, {bool first = false}) async {
    final expects = commands.statusGet().expects;
    if (command.expects != null || !_driveAnswersExpected) {
      await _send(command, null, first: first);
      return;
    }
    try {
      await _send(command.withExpects(expects), config.driveReplyTimeout, first: first);
    } on SessionError catch (e) {
      if (e.failure != SessionFailure.timeout || e.cause != null) rethrow;
      _driveMisses++;
      if (!_driveAnswersExpected) {
        EdelkroneLog.info(
          () =>
              '$_driveMisses drive packets in a row went unanswered; '
              'they are sent without waiting from now on',
        );
      }
      return;
    }
    _driveMisses = 0;
    _lastDriveAnswer = _clock.now();
  }

  void readPositionWhileDriving() {
    if (!_positionReadable || _disposed) return;
    final now = _clock.now();
    if (now - _lastPositionRead < config.drivePositionInterval) return;
    _lastPositionRead = now;
    (_driveReader ??= NudgedWorker('drive-position:${device.mac}', readPosition)).nudge();
  }

  /// Reads the live position. Swallows the failures a read can expect.
  Future<void> readPosition() async {
    if (!_positionReadable || _disposed || _readsHeld > 0) return;
    try {
      await send(commands.numericPositionRead(CommandSet.currentPositionIndex));
    } on SessionError catch (e) {
      if (e.failure == SessionFailure.unsupported) {
        _positionReadable = false;
      } else if (e.failure != SessionFailure.timeout &&
          e.failure != SessionFailure.notConnected &&
          e.failure != SessionFailure.disposed) {
        rethrow;
      }
    }
  }

  Future<T> withPositionReadsHeld<T>(Future<T> Function() body) async {
    _readsHeld++;
    try {
      return await body();
    } finally {
      _readsHeld--;
    }
  }

  bool get _driveAnswersExpected => _driveMisses < config.driveReplyMisses;

  bool _stickBringsStatus() {
    if (_clock.now() - _lastDriveAnswer < config.statusInterval) return true;
    return !_driveAnswersExpected && isManualControlActive;
  }

  Future<void> drivePanTilt(double pan, double tilt) => sendDrive(commands.manualPanTilt(pan, tilt));
  Future<void> driveSlide(double speed) => sendDrive(commands.manualSlide(speed));

  Future<void> refreshIdentity() async {
    await send(commands.versionGet());
    await send(commands.settingsGet());
    if (libs.family == DeviceFamily.headModule) {
      try {
        await send(commands.remoteVersionGet());
      } on SessionError catch (e) {
        EdelkroneLog.debug(() => 'remoteVersionGet: ${e.message}');
      }
    }
  }

  // -- layouts ----------------------------------------------------------------

  EdlSetup? get reportedSetup => reportedSetupOf(state);

  static bool isMultiModule(EdlSetup s) => multiModuleSetups.contains(s);

  Future<CanbusPairResult> pair() async {
    _assertUsable();
    final started = _clock.now();
    final groupId = _newGroupId();
    await send(commands.groupIdSelfSet(groupId));
    await send(commands.canbusAutoPair());
    var polls = 0;
    var unrecognised = 0;
    final deadline = started + config.pairTimeout;
    while (_clock.now() < deadline) {
      if (!isConnected) {
        return CanbusPairResult(outcome: CanbusPairOutcome.disconnected, groupId: groupId, polls: polls);
      }
      polls++;
      try {
        await send(commands.canbusInfoGet(), timeout: config.pairPollTimeout);
        unrecognised = 0;
      } on SessionError catch (e) {
        if (e.failure != SessionFailure.timeout) rethrow;
        unrecognised++;
        if (unrecognised >= config.unrecognisedPollLimit) {
          return CanbusPairResult(outcome: CanbusPairOutcome.notAnswered, groupId: groupId, polls: polls);
        }
      }
      final last = state.canbusInfo;
      if (last != null) {
        if (last.canbusPairError != LibEdelkroneMocoCanbusPairError.NONE) {
          return CanbusPairResult(outcome: CanbusPairOutcome.failed, groupId: groupId, polls: polls);
        }
        if (last.canbusPairState == LibEdelkroneMocoCanbusPairState.CONNECTED) {
          return CanbusPairResult(outcome: CanbusPairOutcome.connected, groupId: groupId, polls: polls);
        }
      }
      await _clock.sleep(config.pairPollInterval);
    }
    return CanbusPairResult(outcome: CanbusPairOutcome.timedOut, groupId: groupId, polls: polls);
  }

  /// Joins [rig]'s modules to this unit: the SDK's `setup_rig`. For a
  /// HeadONE and a SliderPLUS that is the wireless route — keep the head's
  /// group, set the layout, invite the slider by MAC — then wait for the
  /// head to report the layout.
  Future<RigSetupResult> setupRig({Rig? rig}) async {
    _assertUsable();
    final slaves = rig?.orderedSlaves ?? const <EdelkroneDevice>[];
    final wired = _needsWiredPairing(device, rig);
    final route = wired ? RigSetupRoute.wired : (slaves.isEmpty ? RigSetupRoute.standalone : RigSetupRoute.wireless);
    EdelkroneLog.info(() => 'setup: ${device.displayName}, ${route.name}, ${slaves.length} modules');

    if (route == RigSetupRoute.standalone) {
      final current = reportedSetup;
      if (current != null && isMultiModule(current)) {
        throw SessionError(
          SessionFailure.unsupported,
          '${device.displayName} is currently running in the ${current.name} layout, but no '
          'modules were given. Connecting to it alone removes it from that layout and leaves '
          'the modules outside.',
          command: 'setupRig',
        );
      }
    }

    final groupId = await _groupFor(route);
    await send(commands.groupIdSelfSet(groupId));

    final fixed = libs.family == DeviceFamily.slideModule ? EdlSetup.SLIDE_ONLY : null;
    var layout = fixed ?? rig?.setup ?? device.advData.setup;
    final defer = isCanbusMaster(device) || (slaves.isNotEmpty && wired);
    if (!defer && layout != EdlSetup.NONE) {
      await send(commands.configuration(layout));
    }

    var peers = 0;
    CanbusPairResult? pairing;
    Future<int> invitePeers() async {
      final peerGroup = device.advData.groupId;
      var named = 0;
      for (final slave in slaves) {
        if (slave.model.deviceType == EdlDevice.PAN_MODULE_FOR_JIB_ONE) continue;
        await send(
          commands.addPeer(
            mac: List<int>.of(slave.advData.mac),
            deviceType: slave.model.deviceType,
            groupId: peerGroup,
          ),
        );
        named++;
      }
      return named;
    }

    if (wired) {
      pairing = await pair();
      if (slaves.isNotEmpty && layout != EdlSetup.NONE) {
        final settled = await adoptReportedSetup(timeout: 10.0);
        if (settled != null && layoutCovers(settled, layout)) {
          layout = settled;
        } else if (settled != layout) {
          await send(commands.configuration(layout));
          peers = await invitePeers();
        }
      }
    } else {
      peers = await invitePeers();
    }

    final reported = await adoptReportedSetup(
      timeout: wired ? 10.0 : 3.0 + 3.0 * peers,
      expect: slaves.isNotEmpty && layout != EdlSetup.NONE ? layout : null,
    );
    final result = RigSetupResult(
      route: route,
      groupId: groupId,
      setup: layout,
      peersAdded: peers,
      pairing: pairing,
      reportedSetup: reported,
    );
    EdelkroneLog.info(() => '$result');
    return result;
  }

  static bool _needsWiredPairing(EdelkroneDevice master, Rig? rig) {
    if (master.advData.setup == EdlSetup.POSSIBLE_CANBUS_MASTER) return true;
    if (rig != null && rig.slaves.isNotEmpty && rig.isRecognised) return false;
    if (isCanbusMaster(master)) return true;
    if (rig == null) return false;
    return rig.slaves.any((d) => d.advData.canbusPairingActive);
  }

  Future<EdlSetup?> adoptReportedSetup({double timeout = 10.0, EdlSetup? expect}) async {
    final deadline = _clock.now() + timeout;
    EdlSetup? seen;
    while (_clock.now() < deadline) {
      // As in the SDK, a status poll that goes unanswered here propagates: a
      // layout being formed over a link that cannot answer a poll is not one
      // to report as formed.
      await refreshStatus();
      final s = reportedSetup;
      if (s != null && s != EdlSetup.NONE && s != EdlSetup.POSSIBLE_CANBUS_MASTER) {
        seen = s;
        if (expect == null || layoutCovers(s, expect)) break;
      }
      await _clock.sleep(0.300);
    }
    if (seen != null) device.setup = DeviceSetup(masterDevice: device, setupType: seen);
    return seen;
  }

  static const noGroup = 0xFFFF;

  /// A module only joins a group while it has none, so an existing group is
  /// kept: a new id would leave the modules already in it behind.
  Future<int> _groupFor(RigSetupRoute route) async {
    if (route == RigSetupRoute.wired) return _newGroupId();
    try {
      await send(commands.ioctlStatusGet());
      final st = state.ioctlStatus;
      if (st != null && st.groupId != noGroup) return st.groupId;
    } on SessionError {
      // Fall back to the advertised group.
    }
    final advertised = device.advData.groupId;
    if (advertised != noGroup) return advertised;
    return _newGroupId();
  }

  int _newGroupId() => DateTime.now().millisecondsSinceEpoch & 0xFFFF;

  // -- poses ------------------------------------------------------------------

  MotionState? get motionState => motionStateOf(state);
  bool get isMoving => motionState?.isMoving ?? false;
  List<int> storedPoses(PoseKind kind) => storedSlots(state, kind);

  /// Stores the current position in [index] and confirms it from the next
  /// readings; a slot that holds a pose is emptied first, so the confirmation
  /// is of the new one.
  Future<bool> storePose(
    int index, {
    PoseKind kind = PoseKind.keypose,
    int uniqueId = CommandSet.defaultUniqueId,
  }) async {
    _assertUsable();
    if (kind != PoseKind.keypose) {
      throw SessionError(SessionFailure.unsupported, 'only keyposes are stored by this port', command: 'storePose');
    }
    try {
      await refreshStatus();
    } on SessionError catch (e) {
      if (e.failure != SessionFailure.timeout) rethrow;
    }
    if (storedPoses(kind).contains(index)) {
      await send(commands.keyposeDelete(index));
      for (var i = 0; i < 5; i++) {
        await _clock.sleep(0.150);
        await refreshStatus();
        if (!storedPoses(kind).contains(index)) break;
      }
    }
    await send(commands.keyposeStore(index, uniqueId: uniqueId));
    for (var i = 0; i < 5; i++) {
      await _clock.sleep(0.150);
      await refreshStatus();
      if (storedPoses(kind).contains(index)) return true;
    }
    return false;
  }

  /// Polls until [test] holds or [timeout] passes. Refresh failures are
  /// absorbed: a missed reply is retried, not fatal.
  Future<bool> waitForState(bool Function(DeviceState) test, {double timeout = 30.0, double interval = 0.200}) async {
    final deadline = _clock.now() + timeout;
    while (true) {
      if (test(state)) return true;
      try {
        await refreshStatus();
      } catch (_) {}
      if (test(state)) return true;
      if (_clock.now() >= deadline) return false;
      await _clock.sleep(math.min(interval, math.max(0.0, deadline - _clock.now())));
    }
  }

  /// Waits for motion to start (up to [settle]), then for idle.
  Future<bool> waitUntilIdle({double timeout = 60.0, double settle = 1.0}) async {
    bool moving(DeviceState s) => motionStateOf(s)?.isMoving ?? false;
    final deadline = _clock.now() + timeout;
    if (settle > 0) {
      final started = await waitForState(moving, timeout: math.min(settle, timeout), interval: 0.1);
      if (!started) return true;
    }
    return waitForState((s) => !moving(s), timeout: math.max(0.0, deadline - _clock.now()));
  }

  // -- lifecycle --------------------------------------------------------------

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    _driveReader?.stop();
    _driveReader = null;
    await stopStatusPolling();
    await stopPositionPolling();
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.completer.isCompleted) {
      w.completer.completeError(SessionError(SessionFailure.disposed, 'session closed'));
    }
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _link.disconnect();
    await _stateUpdates.close();
    EdelkroneLog.info(() => 'session closed: ${device.displayName}');
  }

  void _assertUsable() {
    if (_disposed) {
      throw SessionError(SessionFailure.disposed, 'the ${device.displayName} session is closed');
    }
  }

  @override
  String toString() =>
      'EdelkroneSession(${device.displayName}, ${libs.family.name}, ${isConnected ? 'connected' : 'disconnected'})';
}

String _hex(List<int> data) => data.map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0')).join(' ');
