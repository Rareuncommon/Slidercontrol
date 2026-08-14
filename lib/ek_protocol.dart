/// edelkrone BLE protocol — pure Dart, no Flutter or BLE dependency.
///
/// Deliberately free of any I/O so it can be unit-tested against the captured
/// byte sequences without hardware. See EDELKRONE_PROTOCOL.md for the full
/// specification and for what remains undecoded.
library ek_protocol;

import 'dart:typed_data';

// ---------------------------------------------------------------------------
// GATT
// ---------------------------------------------------------------------------

class EkUuids {
  static const serviceSlider = '4baee7eb-2122-4502-98e9-1ee792bd5603';
  static const serviceHead = '4baee7eb-2122-4502-98e9-1ee792bd5594';
  static const write = '5a861ccb-687b-459a-af01-347792f07a0c';
  static const notify = 'c2720639-bdfc-4b8e-896d-b5bea0479976';

  /// Present on both devices but never used by the official app.
  static const writeSecondary = '7da5b2e6-071c-4601-9fde-ecaf291d0a04';
  static const notifySecondary = 'eaa8212a-3551-4e98-adeb-0b68957a215a';
}

/// Poll interval. Nothing is reported without it.
const keepalivePeriod = Duration(milliseconds: 250);

/// Velocity streaming interval while jogging.
const jogPeriod = Duration(milliseconds: 100);

// ---------------------------------------------------------------------------
// Framing
// ---------------------------------------------------------------------------

/// Builds a frame: `[len][opcode][payload][sum16]`.
///
/// `len` counts the bytes before the checksum, including itself and the opcode.
/// The checksum is a big-endian 16-bit sum of every preceding byte.
Uint8List buildFrame(int opcode, [List<int> payload = const []]) {
  final body = <int>[2 + payload.length, opcode, ...payload];
  var sum = 0;
  for (final b in body) {
    sum += b;
  }
  sum &= 0xFFFF;
  return Uint8List.fromList([...body, (sum >> 8) & 0xFF, sum & 0xFF]);
}

/// True if a received frame's trailing checksum matches its contents.
bool verifyChecksum(List<int> frame) {
  if (frame.length < 3) return false;
  var sum = 0;
  for (var i = 0; i < frame.length - 2; i++) {
    sum += frame[i];
  }
  sum &= 0xFFFF;
  final trailer = (frame[frame.length - 2] << 8) | frame[frame.length - 1];
  return sum == trailer;
}

List<int> _i16be(int v) {
  final c = v.clamp(-32768, 32767).toInt();
  final u = c < 0 ? c + 0x10000 : c;
  return [(u >> 8) & 0xFF, u & 0xFF];
}

// ---------------------------------------------------------------------------
// Device profiles
// ---------------------------------------------------------------------------

enum EkKind { slider, head }

/// The opcode set for one device type. Everything else about the protocol is
/// shared, so this is the only thing that varies between the two units.
class EkProfile {
  final EkKind kind;
  final String name;
  final String serviceUuid;
  final int opKeepalive;
  final int opVelocity;
  final int opSave;
  final int opGoto;
  final int opStop;

  /// Bytes appended after the speed/accel pair in a goto frame. Constant in
  /// every captured frame; meaning unknown for the head.
  final List<int> gotoTail;

  /// Where the slot and loop flags sit within the goto payload.
  final bool slotIsLastByte;

  const EkProfile._({
    required this.kind,
    required this.name,
    required this.serviceUuid,
    required this.opKeepalive,
    required this.opVelocity,
    required this.opSave,
    required this.opGoto,
    required this.opStop,
    required this.gotoTail,
    required this.slotIsLastByte,
  });

  static const slider = EkProfile._(
    kind: EkKind.slider,
    name: 'slider',
    serviceUuid: EkUuids.serviceSlider,
    opKeepalive: 0x0F,
    opVelocity: 0x0D,
    opSave: 0x07,
    opGoto: 0x0B,
    opStop: 0x0C,
    gotoTail: [],
    slotIsLastByte: true,
  );

  static const head = EkProfile._(
    kind: EkKind.head,
    name: 'head',
    serviceUuid: EkUuids.serviceHead,
    opKeepalive: 0x01,
    opVelocity: 0x0A,
    opSave: 0x05,
    opGoto: 0x07,
    opStop: 0x09,
    // 00 E6741A FFFFFC18 — identical across every capture. FFFFFC18 reads as
    // signed 32-bit -1000. Purpose unknown.
    gotoTail: [0x00, 0xE6, 0x74, 0x1A, 0xFF, 0xFF, 0xFC, 0x18],
    slotIsLastByte: false,
  );

  /// Pick the profile from an advertised name. Advertised names are
  /// `SldrPlsV1` and `HeadOneFM`.
  static EkProfile forName(String? advertisedName) {
    final n = (advertisedName ?? '').toLowerCase();
    return n.contains('head') ? head : slider;
  }

  // -- frames --------------------------------------------------------------

  Uint8List keepalive() => buildFrame(opKeepalive);

  /// Velocity in encoder counts/sec, roughly 1:1. Full stick is about ±31,900.
  /// Positive moves the slider one way and pans the head right.
  Uint8List velocity(int countsPerSec) {
    final tail = kind == EkKind.slider ? [0x70, 0x80] : [0x00, 0x00];
    return buildFrame(opVelocity, [..._i16be(countsPerSec), ...tail]);
  }

  /// Stores the device's *current* position into a slot. Carries no position.
  /// `0x3039` (12345) is a constant present in every capture.
  Uint8List savePose(int slot) =>
      buildFrame(opSave, [slot, 0x00, 0x00, 0x30, 0x39]);

  /// Recall a pose, or start the device's own loop mode.
  ///
  /// Device loop mode stops after roughly one round trip — for continuous
  /// motion, supervise from the host instead.
  ///
  /// [speed] and [accel] are raw PERIOD values: larger is slower. [extra] is a
  /// device-specific 32-bit field that scales the opposite way. Use
  /// [MotionParams.fromPercent] to derive all three from a percentage.
  Uint8List gotoPose(
    int slot, {
    bool loop = false,
    int speed = MotionParams.capturedDefaultPair,
    int accel = MotionParams.capturedDefaultPair,
    int? extra,
  }) {
    final sp = [(speed >> 8) & 0xFF, speed & 0xFF];
    final ac = [(accel >> 8) & 0xFF, accel & 0xFF];

    if (kind == EkKind.slider) {
      final e = extra ?? MotionParams.sliderCapturedDefaultExtra;
      return buildFrame(opGoto, [
        loop ? 0x01 : 0x00,
        (e >> 24) & 0xFF, (e >> 16) & 0xFF, (e >> 8) & 0xFF, e & 0xFF,
        ...sp, ...ac,
        loop ? 0x00 : 0xFF,
        slot,
      ]);
    }

    final e = extra ?? MotionParams.headCapturedDefaultExtra;
    return buildFrame(opGoto, [
      loop ? 0x00 : 0xFF,
      slot,
      loop ? 0x01 : 0x00,
      ...sp, ...ac,
      (e >> 24) & 0xFF, (e >> 16) & 0xFF, (e >> 8) & 0xFF, e & 0xFF,
      0xFF, 0xFF, 0xFC, 0x18,
    ]);
  }

  Uint8List stop() => buildFrame(opStop);
}

/// Speed and acceleration, as the app encodes them.
///
/// Captured with the app's sliders at 1% and at 100%:
///
///     setting   pair             slider extra   head extra
///     1%        0x7BC3 = 31683   20             320,000
///     100%      0x0140 = 320     1,080          32,000,000
///
/// The pair is a PERIOD — larger is slower — and is identical on both devices
/// at the same percentage. The extra field is device-specific and scales the
/// other way.
///
/// ONLY 1% AND 100% ARE MEASURED. The curve between them is modelled
/// (reciprocal for the pair, linear for the extra) and reproduces both
/// endpoints to within 1%. Treat mid-range values as approximate; pass raw
/// values where exactness matters.
class MotionParams {
  final int pair;
  final int extra;
  const MotionParams(this.pair, this.extra);

  static const capturedDefaultPair = 0x0494;          // whatever the app was set to, ~47%
  static const sliderCapturedDefaultExtra = 0x0203;   // 515
  static const headCapturedDefaultExtra = 0x00E6741A;

  static const pairAt1 = 31683;
  static const pairAt100 = 320;
  static const sliderExtraAt1 = 20;
  static const sliderExtraAt100 = 1080;
  static const headExtraPerPercent = 320000;

  factory MotionParams.fromPercent(double percent, EkKind kind) {
    final p = percent.clamp(1.0, 100.0);
    final pair = (pairAt100 * 100.0 / p).round();
    final extra = kind == EkKind.head
        ? (headExtraPerPercent * p).round()
        : (sliderExtraAt1 + (sliderExtraAt100 - sliderExtraAt1) * (p - 1) / 99)
            .round();
    return MotionParams(pair, extra);
  }

  /// Manual jogging has no speed field of its own — the velocity value *is* the
  /// speed. To make the app's speed control apply to manual movement too, scale
  /// the commanded velocity by the same percentage.
  static int jogVelocityForPercent(double percent, {int maxCounts = 30500}) =>
      (maxCounts * percent.clamp(1.0, 100.0) / 100).round();
}

// ---------------------------------------------------------------------------
// Telemetry
// ---------------------------------------------------------------------------

enum EkState { idle, keyposeMove, manualJog, ack, unknown }

EkState _stateFromByte(int b) {
  switch (b) {
    case 0x00:
      return EkState.idle;
    case 0x02:
      return EkState.keyposeMove;
    case 0x0E:
      return EkState.manualJog;
    case 0xFF:
      return EkState.ack;
    default:
      return EkState.unknown;
  }
}

class EkTelemetry {
  final EkState state;
  final int? batteryPercent;
  final int? rawPosition;

  const EkTelemetry({required this.state, this.batteryPercent, this.rawPosition});
}

/// Parses a notification frame. Returns null for frames that carry no usable
/// state — including the `0xFF` ack, whose position bytes are NOT valid.
EkTelemetry? parseTelemetry(List<int> frame, EkKind kind) {
  if (frame.length < 10) return null;

  if (kind == EkKind.head) {
    // The head's 122-byte frame is static: no live position anywhere in it.
    // Battery sits at byte 89.
    if (frame.length < 90) return null;
    return EkTelemetry(state: EkState.unknown, batteryPercent: frame[89]);
  }

  final state = _stateFromByte(frame[1]);
  if (state == EkState.ack) return null;
  return EkTelemetry(
    state: state,
    batteryPercent: frame[2],
    rawPosition: (frame[8] << 8) | frame[9],
  );
}

/// Unwraps the slider's 16-bit position counter into a continuous value.
///
/// The counter wraps every 65,536 counts. Telemetry arrives at ~3.3 Hz and the
/// carriage moves at most ~9,000 counts per sample under power, so a jump
/// larger than half the range is always a wrap rather than real motion.
class PositionTracker {
  int? _lastRaw;
  int _unwrapped = 0;

  int? get position => _lastRaw == null ? null : _unwrapped;

  void reset() {
    _lastRaw = null;
    _unwrapped = 0;
  }

  int update(int raw) {
    if (_lastRaw == null) {
      _unwrapped = raw;
    } else {
      var d = raw - _lastRaw!;
      if (d > 32768) {
        d -= 65536;
      } else if (d < -32768) {
        d += 65536;
      }
      _unwrapped += d;
    }
    _lastRaw = raw;
    return _unwrapped;
  }
}

// ---------------------------------------------------------------------------
// Measured constants for the reference rig
// ---------------------------------------------------------------------------

class EkRig {
  /// Powered end-to-end measurement. A hand-pushed measurement gave 475,458;
  /// the motor presses slightly further into the stops.
  static const sliderTravelCounts = 481000;

  /// Full-stick speed, counts/sec.
  static const sliderMaxCountsPerSec = 30500;

  /// Pose recalls run slower than a full-stick jog at the default speed/accel.
  static const sliderRecallCountsPerSec = 16600;

  /// Head rotation: about 1.2°/sec at velocity 2000.
  static const headDegreesPerSecondAt2000 = 1.2;

  static double headVelocityForDegreesPerSecond(double degPerSec) =>
      degPerSec / headDegreesPerSecondAt2000 * 2000;
}
