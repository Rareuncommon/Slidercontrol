/// Device state and the interface a motion controller drives.
///
/// Pure Dart, with no BLE or Flutter import, for one specific reason: it lets
/// the supervised ping-pong in EDELKRONE_PROTOCOL.md §7 be unit-tested against
/// a fake device under `dart test`. That timing logic is the part of the client
/// most likely to leave a motor running, and it is testable only if it depends
/// on an abstraction rather than on a live GATT connection.
library;

import '../control/motion_settings.dart';
import '../ek_protocol.dart';

enum EkLinkState { disconnected, connecting, discovering, ready, failed }

/// Everything the UI needs to know about a device at one instant.
class EkSnapshot {
  final EkLinkState link;
  final EkKind kind;

  /// Motion state from the last usable telemetry frame.
  ///
  /// The head always reports [EkState.unknown]: its 122-byte frame carries no
  /// state byte we have decoded (§5). Anything that needs to know whether a
  /// move has finished can only do so for the slider.
  final EkState state;

  final int? batteryPercent;

  /// Unwrapped, continuous position. Slider only; null for the head, which does
  /// not report position at all (§5).
  ///
  /// The absolute value is arbitrary — it is not preserved across sessions and
  /// has no fixed relationship to any physical point on the rail.
  final int? position;

  final DateTime? lastFrameAt;
  final int framesReceived;

  /// Frames whose trailing checksum did not match. Surfaced rather than hidden:
  /// a non-zero count means the framing rule in §2 does not hold for some
  /// notification the hardware actually sends, which is worth knowing.
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
  /// keepalive, so this distinguishes "connected" from "connected and actually
  /// being polled" (§1, §7).
  bool get isReporting =>
      lastFrameAt != null &&
      DateTime.now().difference(lastFrameAt!) < const Duration(seconds: 3);

  /// Whether this device can report that a commanded move has finished.
  ///
  /// False for the head. Supervision has to fall back to a timer there, because
  /// the device tells us nothing (§5, §8).
  bool get reportsMotionState => kind == EkKind.slider;

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

/// The subset of a device a motion controller needs.
///
/// [EkConnection] implements this over BLE; tests implement it over nothing.
abstract class EkMotionTarget {
  EkKind get kind;
  EkSnapshot get snapshot;
  Stream<EkSnapshot> get snapshots;

  Future<void> recallPose(int slot, {required MotionSettings settings});
  Future<void> savePose(int slot);

  /// Velocity in encoder counts/sec. Zero means stop.
  Future<void> setVelocity(int countsPerSec);

  Future<void> stopMotion();
}

/// One raw notification frame, as received.
///
/// Retained verbatim — no interpretation — so undecoded messages can be read
/// off the wire. EDELKRONE_PROTOCOL.md §8 still lists several.
class EkFrameRecord {
  final DateTime at;
  final List<int> bytes;
  final bool checksumOk;

  const EkFrameRecord({
    required this.at,
    required this.bytes,
    required this.checksumOk,
  });

  /// Message type — the first byte. Not a length, in this direction (§2).
  int get messageType => bytes.isEmpty ? -1 : bytes[0];

  String get hex =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  String get timestamp {
    final t = at;
    final ms = t.millisecond.toString().padLeft(3, '0');
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.$ms';
  }

  /// A line suited to pasting into a protocol note or a diff against a capture.
  String toLogLine() =>
      '$timestamp  len=${bytes.length.toString().padLeft(3)}  '
      'type=0x${messageType.toRadixString(16).padLeft(2, '0')}  '
      '${checksumOk ? '   ' : 'BAD'}  $hex';
}
