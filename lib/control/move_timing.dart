/// Making both axes take the same time to complete a move.
///
/// The model comes from EDELKRONE_PROTOCOL.md §7b: the speed/accel field is a
/// PERIOD, not a speed — larger means slower — and it is derived from the
/// percentage as `pair = 320 × 100 / percent`. A move's duration is therefore
/// proportional to the period, and so inversely proportional to the percentage:
///
///     duration × percent = constant, for a given move
///
/// That single relationship is all the timing solver needs, and it is the same
/// relationship for both devices, because §7b establishes the pair as
/// device-independent.
///
/// **The asymmetry that matters.** The slider reports position, so its move can
/// be measured automatically and the model generalises across any pair of
/// poses: rate is counts per second per percent, and duration is distance over
/// rate. The head reports neither position nor motion state (§5), so nothing
/// about its move can be observed — not its speed, not its distance, not even
/// whether it has finished. Its calibration has to come from a human timing one
/// move, and it is only valid for the pose pair it was measured on.
///
/// Decoding the 16-byte `0x05` frame §5 suspects carries head progress would
/// remove that limitation entirely. Until then, a timed observation is the only
/// honest source.
///
/// Pure Dart, so the solver is unit-tested.
library;

import 'dart:convert';

/// A solved motion setting, and whether the target was actually reachable.
class SolvedMove {
  const SolvedMove({
    required this.percent,
    required this.predicted,
    required this.clamped,
  });

  /// Speed percentage to command, always within 1–100.
  final double percent;

  /// What that percentage is predicted to produce.
  final Duration predicted;

  /// True when the requested duration needed a percentage outside 1–100, so
  /// the move will NOT take the requested time. Surfaced rather than hidden —
  /// silently producing a different duration is what ruins a shot.
  final bool clamped;
}

double _clampPercent(double p) => p.clamp(1.0, 100.0);

/// What the slider has been observed to do.
///
/// Rate scales with the percentage, so one observation generalises to any
/// distance and any speed.
class SliderTiming {
  const SliderTiming({required this.countsPerSecondPerPercent});

  /// Counts per second at 1%. §6 measured ~16,600 counts/sec at the app's
  /// default (~47%), which is the seed used until a real move is observed.
  final double countsPerSecondPerPercent;

  static const seeded = SliderTiming(countsPerSecondPerPercent: 16600 / 47);

  /// Learns from a completed move. Returns null if the observation is too small
  /// to be meaningful — a few hundred counts or a fraction of a second says
  /// more about latency than about speed.
  static SliderTiming? fromObservation({
    required int counts,
    required Duration duration,
    required double percent,
  }) {
    final seconds = duration.inMilliseconds / 1000.0;
    final distance = counts.abs();
    if (distance < 2000 || seconds < 0.4 || percent < 1) return null;
    final rate = distance / seconds / percent;
    if (!rate.isFinite || rate <= 0) return null;
    return SliderTiming(countsPerSecondPerPercent: rate);
  }

  Duration durationFor(int counts, double percent) {
    final rate = countsPerSecondPerPercent * _clampPercent(percent);
    if (rate <= 0) return Duration.zero;
    return Duration(milliseconds: (counts.abs() / rate * 1000).round());
  }

  SolvedMove solve(int counts, Duration target) {
    final seconds = target.inMilliseconds / 1000.0;
    if (seconds <= 0 || counts.abs() == 0) {
      return SolvedMove(
        percent: 100,
        predicted: durationFor(counts, 100),
        clamped: true,
      );
    }
    final wanted = counts.abs() / seconds / countsPerSecondPerPercent;
    final percent = _clampPercent(wanted);
    return SolvedMove(
      percent: percent,
      predicted: durationFor(counts, percent),
      // A hair of tolerance, so floating point alone never reports a clamp.
      clamped: (wanted - percent).abs() > 0.01,
    );
  }

  Map<String, Object?> toJson() =>
      {'countsPerSecondPerPercent': countsPerSecondPerPercent};

  static SliderTiming? fromJson(Map<String, Object?> j) {
    final v = j['countsPerSecondPerPercent'];
    if (v is! num || !v.isFinite || v <= 0) return null;
    return SliderTiming(countsPerSecondPerPercent: v.toDouble());
  }
}

/// What the head has been observed to do, for one pair of poses.
///
/// Tied to the poses it was measured on, because the head gives no way to know
/// how far apart they are. Changing a pose invalidates it, and the UI says so.
class HeadTiming {
  const HeadTiming({
    required this.referenceDuration,
    required this.referencePercent,
    this.measuredForSlots = const [],
  });

  final Duration referenceDuration;
  final double referencePercent;

  /// The slots this was timed between, so a changed pose can invalidate it.
  final List<int> measuredForSlots;

  Duration durationAt(double percent) {
    final p = _clampPercent(percent);
    final ms = referenceDuration.inMilliseconds * referencePercent / p;
    return Duration(milliseconds: ms.round());
  }

  SolvedMove solve(Duration target) {
    final ms = target.inMilliseconds;
    if (ms <= 0) {
      return SolvedMove(
          percent: 100, predicted: durationAt(100), clamped: true);
    }
    final wanted =
        referenceDuration.inMilliseconds * referencePercent / ms;
    final percent = _clampPercent(wanted);
    return SolvedMove(
      percent: percent,
      predicted: durationAt(percent),
      clamped: (wanted - percent).abs() > 0.01,
    );
  }

  bool appliesTo(List<int> slots) {
    if (measuredForSlots.isEmpty) return true;
    final a = [...measuredForSlots]..sort();
    final b = [...slots]..sort();
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Map<String, Object?> toJson() => {
        'referenceMs': referenceDuration.inMilliseconds,
        'referencePercent': referencePercent,
        'slots': measuredForSlots,
      };

  static HeadTiming? fromJson(Map<String, Object?> j) {
    final ms = j['referenceMs'];
    final p = j['referencePercent'];
    if (ms is! num || ms <= 0 || p is! num || p < 1) return null;
    final slots = <int>[];
    final raw = j['slots'];
    if (raw is List) {
      for (final s in raw) {
        if (s is num) slots.add(s.toInt());
      }
    }
    return HeadTiming(
      referenceDuration: Duration(milliseconds: ms.toInt()),
      referencePercent: p.toDouble(),
      measuredForSlots: slots,
    );
  }
}

/// Both calibrations plus the shot duration they are solved against.
class MoveTiming {
  const MoveTiming({
    this.slider,
    this.head,
    this.shotSeconds = 5.0,
    this.matchDurations = true,
    this.headDelaySeconds = 0.0,
  });

  final SliderTiming? slider;
  final HeadTiming? head;

  /// How long each leg should take, end to end.
  final double shotSeconds;

  /// When false, each device just uses its own speed setting and the durations
  /// are whatever they are.
  final bool matchDurations;

  /// How long to hold the head's recall back after the leg begins.
  ///
  /// Both axes are commanded on the same tick, but the slider's streamed
  /// profile starts at zero velocity and takes its ramp to become visible,
  /// while the head's recall runs the device's own much shorter acceleration.
  /// Commanded together, the head is seen to move first. The difference is a
  /// property of the device's internal profile, which was never captured, so it
  /// cannot be computed — only dialled out by watching.
  ///
  /// The wait is taken off the head's solved duration, so it still arrives with
  /// the slider rather than finishing late.
  final double headDelaySeconds;

  static const maxHeadDelaySeconds = 2.0;

  Duration get headDelay => Duration(
      milliseconds:
          (headDelaySeconds.clamp(0.0, maxHeadDelaySeconds) * 1000).round());

  /// The duration the head's recall is solved against: the leg, less whatever
  /// it spends waiting to start.
  Duration get headSolveTarget {
    final left = shot - headDelay;
    return left < const Duration(milliseconds: 100)
        ? const Duration(milliseconds: 100)
        : left;
  }

  static const minShotSeconds = 0.5;
  static const maxShotSeconds = 120.0;

  Duration get shot =>
      Duration(milliseconds: (shotSeconds.clamp(minShotSeconds, maxShotSeconds) * 1000).round());

  bool get sliderCalibrated => slider != null;
  bool get headCalibrated => head != null;

  /// The head's leg duration normalised to 100% speed.
  ///
  /// One number, and the only one the head needs: how long it takes flat out
  /// between the poses you are shooting. Everything else follows from §7b's
  /// period model — at half the percentage it takes twice as long. Slowing a
  /// move down is the safe direction for that model; it is speeding one up that
  /// runs into the motor's ceiling, and the head is only ever slowed here.
  Duration? get headAtFullSpeed {
    final h = head;
    if (h == null) return null;
    return Duration(
      milliseconds:
          (h.referenceDuration.inMilliseconds * h.referencePercent / 100)
              .round(),
    );
  }

  /// Sets [headAtFullSpeed], keeping it applicable to every pose pair.
  ///
  /// Deliberately not tied to specific slots, unlike a stopwatch measurement:
  /// this is a dial you turn until the head keeps up, not a claim about a
  /// distance the device never reported.
  MoveTiming withHeadAtFullSpeed(Duration d) => MoveTiming(
        slider: slider,
        head: HeadTiming(referenceDuration: d, referencePercent: 100),
        shotSeconds: shotSeconds,
        matchDurations: matchDurations,
        headDelaySeconds: headDelaySeconds,
      );

  /// The speed percentage the head will be commanded at for a [shot]-long leg,
  /// or null if there is no reference yet. Shown in the UI so the dial is not
  /// operating blind.
  double? get headSolvedPercent => head?.solve(headSolveTarget).percent;

  /// True when the head cannot be slowed enough to fill the shot — its solved
  /// percentage would fall below 1. The move will finish early no matter what.
  bool get headTooFastForShot {
    final h = head;
    if (h == null || shot.inMilliseconds <= 0) return false;
    // Below 1% there is nowhere left to go, so the head arrives early whatever
    // is commanded.
    return h.referenceDuration.inMilliseconds * h.referencePercent /
            headSolveTarget.inMilliseconds <
        1;
  }

  static const minHeadReferenceSeconds = 0.2;
  static const maxHeadReferenceSeconds = 20.0;

  MoveTiming copyWith({
    SliderTiming? slider,
    HeadTiming? head,
    double? shotSeconds,
    bool? matchDurations,
    double? headDelaySeconds,
    bool clearHead = false,
  }) =>
      MoveTiming(
        slider: slider ?? this.slider,
        head: clearHead ? null : (head ?? this.head),
        shotSeconds: shotSeconds ?? this.shotSeconds,
        matchDurations: matchDurations ?? this.matchDurations,
        headDelaySeconds: headDelaySeconds ?? this.headDelaySeconds,
      );

  String encode() => jsonEncode({
        'slider': slider?.toJson(),
        'head': head?.toJson(),
        'shotSeconds': shotSeconds,
        'matchDurations': matchDurations,
        'headDelaySeconds': headDelaySeconds,
      });

  static MoveTiming decode(String? raw) {
    if (raw == null || raw.isEmpty) return const MoveTiming();
    try {
      final j = jsonDecode(raw);
      if (j is! Map<String, Object?>) return const MoveTiming();
      final s = j['slider'];
      final h = j['head'];
      final shot = j['shotSeconds'];
      return MoveTiming(
        slider: s is Map<String, Object?> ? SliderTiming.fromJson(s) : null,
        head: h is Map<String, Object?> ? HeadTiming.fromJson(h) : null,
        shotSeconds: shot is num && shot.isFinite
            ? shot.toDouble().clamp(minShotSeconds, maxShotSeconds)
            : 5.0,
        matchDurations: j['matchDurations'] is bool
            ? j['matchDurations']! as bool
            : true,
        headDelaySeconds: j['headDelaySeconds'] is num
            ? (j['headDelaySeconds']! as num)
                .toDouble()
                .clamp(0.0, maxHeadDelaySeconds)
            : 0.0,
      );
    } catch (_) {
      return const MoveTiming();
    }
  }
}
