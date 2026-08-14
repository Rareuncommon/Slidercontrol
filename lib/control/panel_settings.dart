/// Everything the device panel remembers between launches.
///
/// Re-dialling speed, settle and dwell on every run is tedious, and on the head
/// the leg duration is a number the user arrives at by watching the hardware —
/// losing it each launch would mean rediscovering it each launch.
///
/// The value class is pure Dart with explicit clamping, so it is unit-tested
/// without a plugin. Persistence lives behind [PanelSettingsStore], which the
/// UI uses and tests do not.
library;

import 'motion_settings.dart';
import 'ping_pong.dart';

class PanelSettings {
  const PanelSettings({
    this.motion = const MotionSettings(),
    this.settleMs = 600,
    this.dwellSeconds = 0,
    this.blindLegSeconds = 8,
    this.maxLegs = 0,
  });

  final MotionSettings motion;
  final double settleMs;
  final double dwellSeconds;
  final double blindLegSeconds;
  final int maxLegs;

  static const settleMin = 200.0;
  static const settleMax = 2000.0;
  static const dwellMin = 0.0;
  static const dwellMax = 30.0;
  static const blindLegMin = 1.0;
  static const blindLegMax = 60.0;

  Duration get settle => Duration(milliseconds: settleMs.round());
  Duration get dwell => Duration(milliseconds: (dwellSeconds * 1000).round());
  Duration get blindLeg =>
      Duration(milliseconds: (blindLegSeconds * 1000).round());

  PanelSettings copyWith({
    MotionSettings? motion,
    double? settleMs,
    double? dwellSeconds,
    double? blindLegSeconds,
    int? maxLegs,
  }) {
    return PanelSettings(
      motion: motion ?? this.motion,
      settleMs: settleMs ?? this.settleMs,
      dwellSeconds: dwellSeconds ?? this.dwellSeconds,
      blindLegSeconds: blindLegSeconds ?? this.blindLegSeconds,
      maxLegs: maxLegs ?? this.maxLegs,
    );
  }

  /// Clamps every field into range.
  ///
  /// Applied when loading, because stored values can be out of range — an older
  /// build with different limits, or a hand-edited preferences file. An
  /// out-of-range speed would reach a motor, so this is not merely tidiness.
  PanelSettings sanitised() {
    return PanelSettings(
      motion: MotionSettings(
        speedPercent: motion.speedPercent.clamp(1.0, 100.0),
        accelPercent: motion.accelPercent.clamp(1.0, 100.0),
      ),
      settleMs: settleMs.clamp(settleMin, settleMax),
      dwellSeconds: dwellSeconds.clamp(dwellMin, dwellMax),
      blindLegSeconds: blindLegSeconds.clamp(blindLegMin, blindLegMax),
      maxLegs: maxLegs < 0 ? 0 : maxLegs,
    );
  }

  Map<String, Object> toMap() => {
        'speedPercent': motion.speedPercent,
        'accelPercent': motion.accelPercent,
        'settleMs': settleMs,
        'dwellSeconds': dwellSeconds,
        'blindLegSeconds': blindLegSeconds,
        'maxLegs': maxLegs,
      };

  /// Rebuilds from stored values, tolerating anything missing or of the wrong
  /// type by falling back to the default for that field.
  factory PanelSettings.fromMap(Map<String, Object?> m) {
    double num_(String key, double fallback) {
      final v = m[key];
      return v is num && v.isFinite ? v.toDouble() : fallback;
    }

    const defaults = PanelSettings();
    return PanelSettings(
      motion: MotionSettings(
        speedPercent: num_('speedPercent', defaults.motion.speedPercent),
        accelPercent: num_('accelPercent', defaults.motion.accelPercent),
      ),
      settleMs: num_('settleMs', defaults.settleMs),
      dwellSeconds: num_('dwellSeconds', defaults.dwellSeconds),
      blindLegSeconds: num_('blindLegSeconds', defaults.blindLegSeconds),
      maxLegs: switch (m['maxLegs']) {
        final int v => v,
        final num v => v.toInt(),
        _ => defaults.maxLegs,
      },
    ).sanitised();
  }

  /// A sanity check that the stored defaults still line up with the controller's
  /// own, so the two cannot drift apart unnoticed.
  static bool get defaultsMatchController =>
      const PanelSettings().settle == PingPongController.defaultSettle &&
      const PanelSettings().blindLeg == PingPongController.defaultBlindLeg;
}
