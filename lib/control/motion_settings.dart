/// Speed and acceleration as the UI exposes them, in percent.
///
/// This is the one place in the client that goes slightly beyond what the
/// captures establish, so it is isolated here and called out rather than
/// spread through the code.
///
/// What EDELKRONE_PROTOCOL.md §7b actually says:
///
///  - The speed/accel pair is a PERIOD (larger is slower), identical on both
///    devices at the same percentage. The `extra` field is device-specific and
///    scales the opposite way.
///  - Only 1% and 100% were measured. Everything between is modelled.
///  - Speed and acceleration were always set TOGETHER in the captures, and the
///    two u16 slots are symmetric in every frame seen — so **which slot is
///    speed and which is acceleration is not established**.
///
/// Independent sliders therefore rest on an assumption: that the first u16 is
/// speed and the second acceleration, and that driving them to different values
/// is meaningful at all. Neither was captured. Setting both to the same value
/// reproduces exactly what the app was observed doing; that is the default.
///
/// The `extra` field is derived from the SPEED percentage. In the captures it
/// tracked a single combined setting, so with the two split there is no
/// evidence for which one should drive it. Speed is the more plausible choice
/// and the more visible one if it is wrong.
///
/// If the hardware disagrees with any of this, the fix belongs in the spec, not
/// in a workaround here.
library;

import '../ek_protocol.dart';

class MotionSettings {
  const MotionSettings({this.speedPercent = 50, this.accelPercent = 50});

  /// 1–100. Drives the speed u16, the `extra` field, and jog velocity.
  final double speedPercent;

  /// 1–100. Drives the acceleration u16 only.
  final double accelPercent;

  /// True when both sliders match, i.e. the configuration the captures cover.
  bool get isCaptureFaithful => speedPercent == accelPercent;

  MotionSettings copyWith({double? speedPercent, double? accelPercent}) =>
      MotionSettings(
        speedPercent: speedPercent ?? this.speedPercent,
        accelPercent: accelPercent ?? this.accelPercent,
      );

  int speedPair(EkKind kind) =>
      MotionParams.fromPercent(speedPercent, kind).pair;

  int accelPair(EkKind kind) =>
      MotionParams.fromPercent(accelPercent, kind).pair;

  int extra(EkKind kind) => MotionParams.fromPercent(speedPercent, kind).extra;

  /// Manual jogging has no speed field — the velocity value *is* the speed
  /// (§7b) — so the speed percentage scales the commanded velocity instead.
  /// Acceleration does not apply: the velocity frame has no slot for it.
  int jogVelocity() => MotionParams.jogVelocityForPercent(speedPercent);
}
