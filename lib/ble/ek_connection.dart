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
  EkConnection({required this.device, required this.profile, this.name = ''})
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

  BluetoothCharacteristic? _write;
  BluetoothCharacteristic? _notify;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _linkSub;
  Timer? _keepalive;
  bool _keepaliveInFlight = false;

  /// Serialises every GATT write. Concurrent writes stall the queue, so each
  /// operation chains onto the previous one. Errors are swallowed from the
  /// chain (but still returned to that operation's caller) so one failed write
  /// cannot poison every write after it.
  Future<void> _writeChain = Future<void>.value();

  bool _disposed = false;

  // -- lifecycle ------------------------------------------------------------

  Future<void> connect() async {
    if (_disposed) throw StateError('connection disposed');
    _emit(_snapshot.copyWith(link: EkLinkState.connecting, clearError: true));

    try {
      await _linkSub?.cancel();
      _linkSub = device.connectionState.listen(_onLinkStateChanged);

      // License.nonprofit per the flutter_blue_plus licence terms: personal and
      // nonprofit use. Commercial distribution would need License.commercial.
      await device.connect(license: License.nonprofit);

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
    await disconnect();
    await _snapshots.close();
  }

  Future<void> _teardown() async {
    _keepalive?.cancel();
    _keepalive = null;
    _keepaliveInFlight = false;
    await _notifySub?.cancel();
    _notifySub = null;
    await _linkSub?.cancel();
    _linkSub = null;
    _write = null;
    _notify = null;
  }

  void _onLinkStateChanged(BluetoothConnectionState s) {
    if (s == BluetoothConnectionState.disconnected &&
        _snapshot.link != EkLinkState.disconnected) {
      _keepalive?.cancel();
      _keepalive = null;
      _emit(_snapshot.copyWith(
        link: EkLinkState.disconnected,
        error: 'link dropped',
      ));
    }
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

    var failures = _snapshot.checksumFailures;
    if (!verifyChecksum(frame)) {
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
