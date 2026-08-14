/// One live BLE connection to one edelkrone device.
///
/// Owns the four things EDELKRONE_PROTOCOL.md §9 says a port needs at the
/// transport level: service/characteristic discovery, the 250 ms keepalive,
/// notification parsing with position unwrapping, and serialised writes.
///
/// Motion sequencing (ping-pong, jogging) deliberately lives above this, in the
/// controller — this class knows how to talk to a device, not what to say.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../control/motion_settings.dart';
import '../ek_protocol.dart';
import 'ek_snapshot.dart';

export 'ek_snapshot.dart' show EkLinkState, EkSnapshot, EkMotionTarget;

class EkConnection implements EkMotionTarget {
  EkConnection({
    required this.device,
    required this.profile,
    this.name = '',
    this.autoReconnect = true,
  })
      : _snapshot = EkSnapshot(
          link: EkLinkState.disconnected,
          kind: profile.kind,
        );

  final BluetoothDevice device;
  final EkProfile profile;
  final String name;

  @override
  EkKind get kind => profile.kind;

  final _snapshots = StreamController<EkSnapshot>.broadcast();
  @override
  Stream<EkSnapshot> get snapshots => _snapshots.stream;

  EkSnapshot _snapshot;
  @override
  EkSnapshot get snapshot => _snapshot;

  final _tracker = PositionTracker();

  /// A rolling window of raw notification frames, newest last.
  ///
  /// Kept because §8 still lists undecoded fields — the head's position, the
  /// `70 80` constant, the head goto tail. Seeing the actual bytes a device
  /// sends is how those get closed, and it costs nothing to retain a few
  /// hundred frames.
  final _frameLog = <EkFrameRecord>[];
  static const frameLogLimit = 400;

  List<EkFrameRecord> get frameLog => List.unmodifiable(_frameLog);

  void clearFrameLog() => _frameLog.clear();

  void _record(List<int> frame,
      {required bool outgoing, required bool checksumOk}) {
    _frameLog.add(EkFrameRecord(
      at: DateTime.now(),
      bytes: List.unmodifiable(frame),
      checksumOk: checksumOk,
      outgoing: outgoing,
    ));
    if (_frameLog.length > frameLogLimit) {
      _frameLog.removeRange(0, _frameLog.length - frameLogLimit);
    }
  }

  BluetoothCharacteristic? _write;
  BluetoothCharacteristic? _notify;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _linkSub;
  Timer? _keepalive;
  bool _keepaliveInFlight = false;

  /// True once device.connect() has actually returned.
  ///
  /// `connectionState` pushes an initial value to every new listener, and for a
  /// device we have not connected to yet that value is `disconnected`. Without
  /// this guard that initial event is indistinguishable from a real drop, and
  /// it lands in the middle of connecting — reporting "link dropped" on a link
  /// that is coming up perfectly well.
  bool _linkEstablished = false;

  /// Set by an explicit [disconnect] so a deliberate teardown is not mistaken
  /// for a dropout and reconnected behind the user's back.
  bool _userDisconnected = false;

  /// Reconnect after an unexpected drop.
  ///
  /// This never resumes motion — it restores the link and the keepalive, and
  /// nothing else. That is a safety improvement rather than a risk: if the link
  /// drops while the device is completing a recall, the device keeps going and
  /// holds torque (§7), and until the link is back there is no way to send it a
  /// stop at all.
  final bool autoReconnect;
  static const reconnectAttempts = 5;
  Timer? _reconnectTimer;
  int _reconnectsTried = 0;

  /// Serialises every GATT write. Concurrent writes stall the queue, so each
  /// operation chains onto the previous one. Errors are swallowed from the
  /// chain (but still returned to that operation's caller) so one failed write
  /// cannot poison every write after it.
  Future<void> _writeChain = Future<void>.value();

  bool _disposed = false;

  // -- lifecycle ------------------------------------------------------------

  Future<void> connect() async {
    if (_disposed) throw StateError('connection disposed');
    _userDisconnected = false;
    _linkEstablished = false;
    _reconnectTimer?.cancel();
    _emit(_snapshot.copyWith(link: EkLinkState.connecting, clearError: true));

    try {
      await _linkSub?.cancel();
      _linkSub = device.connectionState.listen(_onLinkStateChanged);

      // License.nonprofit per the flutter_blue_plus licence terms: personal and
      // nonprofit use. Commercial distribution would need License.commercial.
      await device.connect(license: License.nonprofit);

      // The user may have hit Disconnect while this was in flight — an
      // auto-reconnect attempt races an explicit teardown. Honour the user.
      if (_userDisconnected || _disposed) {
        await _teardown();
        try {
          await device.disconnect();
        } catch (_) {
          // Already gone.
        }
        _emit(_snapshot.copyWith(link: EkLinkState.disconnected));
        return;
      }

      _linkEstablished = true;

      _emit(_snapshot.copyWith(link: EkLinkState.discovering));
      final services = await device.discoverServices();

      final wanted = Guid(profile.serviceUuid);
      BluetoothService? service;
      for (final s in services) {
        if (s.uuid == wanted) {
          service = s;
          break;
        }
      }
      if (service == null) {
        throw StateError(
          'service ${profile.serviceUuid} not found on ${_label()} '
          '(saw: ${services.map((s) => s.uuid.str).join(', ')})',
        );
      }

      final writeUuid = Guid(EkUuids.write);
      final notifyUuid = Guid(EkUuids.notify);
      for (final c in service.characteristics) {
        if (c.uuid == writeUuid) _write = c;
        if (c.uuid == notifyUuid) _notify = c;
      }
      if (_write == null || _notify == null) {
        throw StateError('write/notify characteristics missing on ${_label()}');
      }

      await _notify!.setNotifyValue(true);
      _notifySub = _notify!.onValueReceived.listen(
        _onFrame,
        onError: (Object e) => _emit(_snapshot.copyWith(error: '$e')),
      );

      _tracker.reset();
      _emit(_snapshot.copyWith(
        link: EkLinkState.ready,
        clearError: true,
        clearPosition: true,
      ));

      _reconnectsTried = 0;
      _startKeepalive();
    } catch (e) {
      _emit(_snapshot.copyWith(link: EkLinkState.failed, error: '$e'));
      await _teardown();
      rethrow;
    }
  }

  /// Stops the motor, then drops the link.
  ///
  /// The stop always goes first. A device left mid-move keeps executing and
  /// holds torque, which locks the carriage so it cannot be moved by hand (§7).
  Future<void> disconnect() async {
    _userDisconnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (_write != null && device.isConnected) {
      try {
        await stopMotion();
      } catch (_) {
        // Best effort: if the stop cannot go out there is nothing further this
        // layer can do, and the disconnect must still happen.
      }
    }
    await _teardown();
    try {
      await device.disconnect();
    } catch (_) {
      // Already gone.
    }
    _emit(_snapshot.copyWith(link: EkLinkState.disconnected));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await disconnect();
    await _snapshots.close();
  }

  Future<void> _teardown() async {
    _keepalive?.cancel();
    _keepalive = null;
    _keepaliveInFlight = false;
    _linkEstablished = false;
    await _notifySub?.cancel();
    _notifySub = null;
    await _linkSub?.cancel();
    _linkSub = null;
    _write = null;
    _notify = null;
  }

  void _onLinkStateChanged(BluetoothConnectionState s) {
    if (s != BluetoothConnectionState.disconnected) return;

    // Ignore the initial value pushed to every new listener, and anything that
    // arrives before the connection was ever up. Only a drop from an
    // established link is a drop.
    if (!_linkEstablished) return;

    _linkEstablished = false;
    _keepalive?.cancel();
    _keepalive = null;

    if (_userDisconnected || _disposed) {
      _emit(_snapshot.copyWith(link: EkLinkState.disconnected));
      return;
    }

    if (autoReconnect && _reconnectsTried < reconnectAttempts) {
      _scheduleReconnect();
      return;
    }

    _emit(_snapshot.copyWith(
      link: EkLinkState.disconnected,
      error: 'link dropped',
    ));
  }

  /// Backs off 1s, 2s, 4s, 8s, 16s across the attempt budget.
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = Duration(seconds: 1 << _reconnectsTried);
    _reconnectsTried++;
    _emit(_snapshot.copyWith(
      link: EkLinkState.reconnecting,
      error: 'link dropped — reconnecting '
          '($_reconnectsTried/$reconnectAttempts)',
    ));
    _reconnectTimer = Timer(delay, () async {
      if (_disposed || _userDisconnected) return;
      try {
        await connect();
      } catch (_) {
        // connect() has already emitted the failure. If attempts remain, the
        // link-state handler will schedule the next one; otherwise this rests
        // in `failed` and the user reconnects by hand.
        if (!_disposed && !_userDisconnected && _reconnectsTried < reconnectAttempts) {
          _scheduleReconnect();
        }
      }
    });
  }

  // -- keepalive ------------------------------------------------------------

  /// The devices report nothing at all without this. A client that connects,
  /// subscribes and then waits will see exactly one frame and then silence
  /// (§1, §7) — this timer is what makes telemetry exist.
  void _startKeepalive() {
    _keepalive?.cancel();
    _keepalive = Timer.periodic(keepalivePeriod, (_) {
      // Skip rather than queue if the previous poll has not completed, so a
      // slow link cannot build an unbounded backlog of stale keepalives.
      if (_keepaliveInFlight || !device.isConnected) return;
      _keepaliveInFlight = true;
      send(profile.keepalive())
          .catchError((Object _) {})
          .whenComplete(() => _keepaliveInFlight = false);
    });
  }

  // -- writes ---------------------------------------------------------------

  /// Queues a frame. Writes are Write Requests, not Write Without Response,
  /// which is what the official app does (§1).
  Future<void> send(Uint8List frame) {
    final result = _writeChain.then((_) async {
      final ch = _write;
      if (ch == null || !device.isConnected) {
        throw StateError('${_label()} is not connected');
      }
      await ch.write(frame, withoutResponse: false);
      // Logged after the write returns, so the log shows what actually reached
      // the device rather than what was queued.
      _record(frame, outgoing: true, checksumOk: true);
    });
    _writeChain = result.catchError((Object _) {});
    return result;
  }

  @override
  Future<void> stopMotion() => send(profile.stop());

  @override
  Future<void> setVelocity(int countsPerSec) =>
      send(profile.velocity(countsPerSec));

  @override
  Future<void> savePose(int slot) => send(profile.savePose(slot));

  @override
  Future<void> recallPose(int slot, {required MotionSettings settings}) => send(
        profile.gotoPose(
          slot,
          speed: settings.speedPair(kind),
          accel: settings.accelPair(kind),
          extra: settings.extra(kind),
        ),
      );

  // -- telemetry ------------------------------------------------------------

  void _onFrame(List<int> frame) {
    if (frame.isEmpty) return;

    final checksumOk = verifyChecksum(frame);
    _record(frame, outgoing: false, checksumOk: checksumOk);

    var failures = _snapshot.checksumFailures;
    if (!checksumOk) {
      // Counted, not dropped. §2 says the sum-16 rule holds in both directions;
      // if hardware disagrees for some frame type, that is a gap in the spec
      // worth seeing rather than a frame worth silently discarding.
      failures++;
    }

    final t = parseTelemetry(frame, profile.kind);
    if (t == null) {
      // Short frames and the 0xFF ack, whose position bytes are not valid.
      _emit(_snapshot.copyWith(
        framesReceived: _snapshot.framesReceived + 1,
        checksumFailures: failures,
        lastFrameAt: DateTime.now(),
      ));
      return;
    }

    int? position;
    if (profile.kind == EkKind.slider && t.rawPosition != null) {
      position = _tracker.update(t.rawPosition!);
    }

    _emit(_snapshot.copyWith(
      state: t.state,
      batteryPercent: t.batteryPercent,
      position: position,
      framesReceived: _snapshot.framesReceived + 1,
      checksumFailures: failures,
      lastFrameAt: DateTime.now(),
    ));
  }

  void _emit(EkSnapshot s) {
    _snapshot = s;
    if (!_snapshots.isClosed) _snapshots.add(s);
  }

  String _label() => name.isNotEmpty ? name : profile.name;
}
