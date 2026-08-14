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

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ek_protocol.dart';

enum EkLinkState { disconnected, connecting, discovering, ready, failed }

/// Everything the UI needs to know about a device at one instant.
@immutable
class EkSnapshot {
  final EkLinkState link;
  final EkKind kind;

  /// Motion state from the last usable telemetry frame. The head reports
  /// [EkState.unknown] — its frames carry no state byte we have decoded (§5).
  final EkState state;
  final int? batteryPercent;

  /// Unwrapped, continuous position. Slider only; null for the head, which does
  /// not report position at all (§5).
  ///
  /// The absolute value is arbitrary — it is not preserved across sessions and
  /// has no fixed relationship to any point on the rail.
  final int? position;

  final DateTime? lastFrameAt;
  final int framesReceived;

  /// Frames whose trailing checksum did not match. Surfaced rather than hidden:
  /// a non-zero count here means the framing assumption in §2 does not hold for
  /// some notification the device actually sends, which is worth knowing.
  final int checksumFailures;

  final String? error;

  const EkSnapshot({
    required this.link,
    required this.kind,
    this.state = EkState.unknown,
    this.batteryPercent,
    this.position,
    this.lastFrameAt,
    this.framesReceived = 0,
    this.checksumFailures = 0,
    this.error,
  });

  bool get isReady => link == EkLinkState.ready;

  /// True once telemetry is genuinely flowing. Nothing arrives without the
  /// keepalive, so this is the check that distinguishes "connected" from
  /// "connected and actually polling" (§7).
  bool get isReporting =>
      lastFrameAt != null &&
      DateTime.now().difference(lastFrameAt!) < const Duration(seconds: 3);

  EkSnapshot copyWith({
    EkLinkState? link,
    EkState? state,
    int? batteryPercent,
    int? position,
    DateTime? lastFrameAt,
    int? framesReceived,
    int? checksumFailures,
    String? error,
    bool clearError = false,
    bool clearPosition = false,
  }) {
    return EkSnapshot(
      link: link ?? this.link,
      kind: kind,
      state: state ?? this.state,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      position: clearPosition ? null : (position ?? this.position),
      lastFrameAt: lastFrameAt ?? this.lastFrameAt,
      framesReceived: framesReceived ?? this.framesReceived,
      checksumFailures: checksumFailures ?? this.checksumFailures,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class EkConnection {
  EkConnection({required this.device, required this.profile, this.name = ''})
      : _snapshot = EkSnapshot(
          link: EkLinkState.disconnected,
          kind: profile.kind,
        );

  final BluetoothDevice device;
  final EkProfile profile;
  final String name;

  final _snapshots = StreamController<EkSnapshot>.broadcast();
  Stream<EkSnapshot> get snapshots => _snapshots.stream;

  EkSnapshot _snapshot;
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

  Future<void> stopMotion() => send(profile.stop());

  Future<void> setVelocity(int countsPerSec) =>
      send(profile.velocity(countsPerSec));

  Future<void> savePose(int slot) => send(profile.savePose(slot));

  Future<void> recallPose(int slot, {required MotionParams motion}) => send(
        profile.gotoPose(
          slot,
          speed: motion.pair,
          accel: motion.pair,
          extra: motion.extra,
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
