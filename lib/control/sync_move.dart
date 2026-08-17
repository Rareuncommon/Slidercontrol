/// A synchronised move: every axis starts and stops at the same instant.
///
/// **Why this exists, and why solving for speed percentages did not work.**
///
/// The previous attempt commanded each device's own pose recall and tried to
/// pick a speed percentage for each so the two moves would last the same time.
/// That relies on duration being a predictable function of the percentage. It
/// is not, for two independent reasons:
///
///  1. The motor saturates. §6 measures a pose recall at ~16,600 counts/sec at
///     roughly 47%, while full-stick jog is only ~30,500 counts/sec. A model
///     where duration scales as 1/percent would predict ~35,000 counts/sec at
///     100% — past what the motor can do. The relationship has to flatten out
///     somewhere, and nothing in the captures says where.
///  2. The head cannot be measured at all (§5), so even a correct model could
///     never be checked against it.
///
/// So this does not predict durations. It **imposes** one. The host ticks a
/// single clock and drives every axis from it, so the moves begin and end
/// together by construction rather than by calculation. The slider runs closed
/// loop against its position; the head runs open loop, because it reports
/// nothing to close a loop against — but its *duration* is exact either way,
/// since the host decides when to stop sending.
///
/// Motion follows a smoothstep in time, so both axes ease in and out together
/// rather than starting and stopping abruptly.
///
/// **This is streamed velocity, which §7 warns keeps running if the host
/// vanishes.** It is for attended shooting. Every exit path — normal, aborted,
/// link lost, exception — neutralises and stops every axis.
///
/// Pure Dart, so the profile and the synchronisation are tested without
/// hardware.
library;

import 'dart:async';

import '../ble/ek_snapshot.dart';
import '../ek_protocol.dart';
import 'motion_settings.dart';

/// Shape of the move: ramp up, hold, ramp down.
///
/// [ramp] is the fraction of the move spent accelerating, and the same fraction
/// again decelerating — so 0.5 is a move that is pure ramp with no cruise, and
/// 0.05 is one that gets up to speed almost at once and holds it.
///
/// **This is what the acceleration setting drives now.** A pose recall carries
/// an acceleration field in its frame, but a synchronised move does not use
/// pose recalls for the slider — it streams velocity, and a velocity frame has
/// no acceleration slot (§7b). So acceleration has to be expressed in the shape
/// of the velocity the host sends, which is what this does, and it is a more
/// direct control than the field ever was.
const syncRampMin = 0.05;
const syncRampMax = 0.5;

/// Acceleration percentage → ramp fraction. Higher acceleration, shorter ramps.
double syncRampForAccel(double accelPercent) {
  final p = accelPercent.clamp(1.0, 100.0);
  return syncRampMax - (syncRampMax - syncRampMin) * ((p - 1) / 99);
}

double _clampRamp(double r) => r.clamp(syncRampMin, syncRampMax);

/// Smoothstep, used to round the ends of each ramp so there is no jerk.
double _smoothstep(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Integral of [_smoothstep] from 0 to x. Reaches 0.5 at x = 1.
double _smoothstepArea(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * t - t * t * t * t / 2;
}

/// Unnormalised velocity shape: rounded ramp up, flat, rounded ramp down.
double _shape(double u, double ramp) {
  final t = u.clamp(0.0, 1.0);
  if (t < ramp) return _smoothstep(t / ramp);
  if (t > 1 - ramp) return _smoothstep((1 - t) / ramp);
  return 1;
}

/// Position along the move, 0→1, as a fraction of elapsed time.
double syncProfile(double u, {double ramp = syncRampMax}) {
  final r = _clampRamp(ramp);
  final t = u.clamp(0.0, 1.0);
  // Area under the whole shape, which the profile is normalised by.
  final total = 1 - r;
  if (t < r) return r * _smoothstepArea(t / r) / total;
  if (t > 1 - r) return 1 - r * _smoothstepArea((1 - t) / r) / total;
  return (r / 2 + (t - r)) / total;
}

/// Rate of change of [syncProfile]. Peaks at [syncProfilePeakRate].
double syncProfileRate(double u, {double ramp = syncRampMax}) {
  final r = _clampRamp(ramp);
  return _shape(u, r) / (1 - r);
}

/// Peak of [syncProfileRate], used to normalise a commanded peak velocity.
///
/// A move held at its cruise speed for longer needs a lower peak to cover the
/// same ground in the same time, which is why this depends on the ramp.
double syncProfilePeakRate({double ramp = syncRampMax}) =>
    1 / (1 - _clampRamp(ramp));

enum SyncOutcome { done, stopped, linkLost, failed }

class SyncProgress {
  const SyncProgress({required this.fraction, required this.message});
  final double fraction;
  final String message;
}

/// One device taking part in a synchronised move.
abstract class SyncAxis {
  EkMotionTarget get target;
  String get name;

  /// The shortest duration this axis can complete its move in.
  ///
  /// Asking for less does not make the move faster — it saturates the motor and
  /// the axis arrives short while the others arrive on time, which is the exact
  /// failure this class exists to avoid. Callers should clamp to the largest of
  /// these across the axes; [SyncMove.minimumDuration] does that.
  Duration get minimumDuration;

  /// Captures whatever the axis needs before motion starts. False if it cannot
  /// run — a slider with no position, say.
  bool begin();

  /// Commands this axis for normalised time [u], given the total [duration].
  Future<void> step(double u, Duration duration);

  /// Neutralises the axis. Always called, on every exit path.
  Future<void> end();
}

/// The slider, driven closed loop against its reported position.
class SliderSyncAxis implements SyncAxis {
  SliderSyncAxis({
    required this.target,
    required this.targetCounts,
    this.name = 'slider',
    this.gain = 0.9,
    this.maxVelocity = 18000,
    this.velocitySign = 1,
    this.ramp = syncRampMax,
  });

  @override
  final EkMotionTarget target;

  @override
  final String name;

  /// Where the carriage should end up, in unwrapped counts.
  final int targetCounts;

  /// Correction applied per count of error, on top of the feedforward.
  final double gain;

  final int maxVelocity;

  /// +1 if a positive velocity makes the counter increase.
  final int velocitySign;

  /// Fraction of the move spent accelerating. See [syncRampForAccel].
  final double ramp;

  int _start = 0;
  int get startCounts => _start;

  /// How far this move has to travel, from wherever the carriage is now.
  int get spanCounts {
    final here = target.snapshot.position ?? _start;
    return targetCounts - here;
  }

  /// The profile peaks at [syncProfilePeakRate] times the average speed, so the
  /// shortest honest duration is set by that peak, not by the average.
  @override
  Duration get minimumDuration {
    if (maxVelocity <= 0) return Duration.zero;
    final seconds =
        spanCounts.abs() * syncProfilePeakRate(ramp: ramp) / maxVelocity;
    return Duration(milliseconds: (seconds * 1000).ceil());
  }

  @override
  bool begin() {
    final here = target.snapshot.position;
    if (here == null) return false;
    _start = here;
    return true;
  }

  @override
  Future<void> step(double u, Duration duration) async {
    final span = targetCounts - _start;
    final seconds = duration.inMilliseconds / 1000.0;
    if (seconds <= 0) return;

    // Where the carriage should be right now, and how fast it should be going.
    final want = _start + span * syncProfile(u, ramp: ramp);
    final feedForward = span * syncProfileRate(u, ramp: ramp) / seconds;

    final here = target.snapshot.position;
    final error = here == null ? 0.0 : (want - here);

    final command = (feedForward + error * gain)
        .clamp(-maxVelocity.toDouble(), maxVelocity.toDouble());
    await target.setVelocity((command * velocitySign).round());
  }

  @override
  Future<void> end() async {
    try {
      await target.setVelocity(0);
    } catch (_) {
      // Fall through to the explicit stop.
    }
    try {
      await target.stopMotion();
    } catch (_) {
      // Nothing further this layer can do.
    }
  }
}

/// The head, driven open loop.
///
/// It reports no position and no motion state (§5), so there is nothing to
/// close a loop against. What the host *can* guarantee is the duration: it
/// decides when the last velocity frame goes out. Distance is the part that
/// depends on [peakVelocity], which is why that is the number to tune when the
/// head ends up short or long.
class HeadSyncAxis implements SyncAxis {
  HeadSyncAxis({
    required this.target,
    required this.peakVelocity,
    this.name = 'head',
    this.ramp = syncRampMax,
  });

  @override
  final EkMotionTarget target;

  @override
  final String name;

  /// Signed. Peak counts/sec at the middle of the move.
  final int peakVelocity;

  /// Fraction of the move spent accelerating. See [syncRampForAccel].
  final double ramp;

  /// None. The head is open loop: a shorter move does not fall short of a
  /// target, it simply covers less angle. Only the slider constrains duration.
  @override
  Duration get minimumDuration => Duration.zero;

  @override
  bool begin() => true;

  @override
  Future<void> step(double u, Duration duration) async {
    final shaped =
        syncProfileRate(u, ramp: ramp) / syncProfilePeakRate(ramp: ramp);
    await target.setVelocity((peakVelocity * shaped).round());
  }

  @override
  Future<void> end() async {
    try {
      await target.setVelocity(0);
    } catch (_) {
      // Fall through to the explicit stop.
    }
    try {
      await target.stopMotion();
    } catch (_) {
      // Nothing further this layer can do.
    }
  }
}

/// A device driven by its own pose recall, but started and stopped on the
/// shared clock.
///
/// This is what the head uses, and it is the honest answer to a problem that
/// has no better one: a keypose recall is the only way to send the head to a
/// remembered angle, because the head reports no position (§5) and so the host
/// cannot know which way to turn it or how far. Velocity-driving it, as
/// [HeadSyncAxis] does, requires the caller to supply that distance.
///
/// What the shared clock still buys is the thing that was actually asked for:
/// the recall goes out on the same tick as the first slider command, and the
/// stop goes out on the same tick as the last one. So both axes begin together
/// and end together. In between, the device runs its own profile.
///
/// The consequence, stated plainly: if the shot duration is shorter than the
/// recall really takes, the stop truncates it and the head arrives short.
/// That is the cost of guaranteeing they stop together, and it is why the shot
/// duration wants to be measured against the *slowest* axis.
class PoseRecallSyncAxis implements SyncAxis {
  PoseRecallSyncAxis({
    required this.target,
    required this.slot,
    required this.settings,
    this.name = 'device',
  });

  @override
  final EkMotionTarget target;

  @override
  final String name;

  final int slot;
  final MotionSettings settings;

  bool _issued = false;

  /// Unknown, and unknowable: the device never says how far it has to go.
  @override
  Duration get minimumDuration => Duration.zero;

  @override
  bool begin() {
    _issued = false;
    return true;
  }

  @override
  Future<void> step(double u, Duration duration) async {
    if (_issued) return;
    _issued = true;
    await target.recallPose(slot, settings: settings);
  }

  @override
  Future<void> end() async {
    // Only the stop — no zero-velocity frame. A velocity command aimed at a
    // device that is executing a keypose recall is a different mode of
    // operation (§4), and there is no capture of what mixing them does.
    try {
      await target.stopMotion();
    } catch (_) {
      // Nothing further this layer can do.
    }
  }
}

class SyncMove {
  SyncMove({
    required this.axes,
    required this.stillRunning,
    this.tick = jogPeriod,
    this.onProgress,
  });

  final List<SyncAxis> axes;
  final bool Function() stillRunning;
  final Duration tick;
  final void Function(SyncProgress)? onProgress;

  /// The shortest duration in which every axis can finish.
  ///
  /// Ask for less than this and the slider saturates: it arrives short while
  /// the head arrives on time, which looks exactly like the problem this class
  /// was written to fix. Clamp to it, and say so, rather than letting the move
  /// quietly under-deliver.
  Duration get minimumDuration {
    var worst = Duration.zero;
    for (final a in axes) {
      final d = a.minimumDuration;
      if (d > worst) worst = d;
    }
    return worst;
  }

  /// Runs the move. Every axis is commanded from the same clock on every tick,
  /// so they start and stop together.
  Future<SyncOutcome> run(Duration duration) async {
    if (axes.isEmpty) return SyncOutcome.done;

    for (final a in axes) {
      if (!a.begin()) {
        await _endAll();
        return SyncOutcome.failed;
      }
    }

    final started = DateTime.now();
    var outcome = SyncOutcome.done;

    try {
      while (true) {
        if (!stillRunning()) {
          outcome = SyncOutcome.stopped;
          break;
        }
        for (final a in axes) {
          if (!a.target.snapshot.isReady) {
            outcome = SyncOutcome.linkLost;
            break;
          }
        }
        if (outcome != SyncOutcome.done) break;

        final elapsed = DateTime.now().difference(started);
        final u = duration.inMilliseconds <= 0
            ? 1.0
            : (elapsed.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0);

        // Every axis is commanded before any of them is awaited, so the frames
        // leave together rather than one lagging the other by a write.
        await Future.wait([for (final a in axes) a.step(u, duration)]);
        onProgress?.call(SyncProgress(
          fraction: u,
          message: 'moving ${(u * 100).round()}%',
        ));

        if (u >= 1.0) break;
        await Future<void>.delayed(tick);
      }
    } catch (_) {
      outcome = SyncOutcome.failed;
    } finally {
      await _endAll();
    }
    return outcome;
  }

  Future<void> _endAll() async {
    for (final a in axes) {
      await a.end();
    }
  }
}
