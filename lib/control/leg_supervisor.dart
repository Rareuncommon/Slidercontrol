/// Supervision of a single leg of motion, for one device.
///
/// Extracted so the single-device ping-pong and the multi-device fleet share
/// one implementation. This is the most safety-critical logic in the client —
/// getting "has the move finished?" wrong is what fires the next command into a
/// moving device — so there is exactly one copy of it.
///
/// Pure Dart: it drives an [EkMotionTarget], not a BLE connection.
library;

import 'dart:async';

import '../ble/ek_snapshot.dart';
import '../ek_protocol.dart';
import 'motion_settings.dart';

enum PingPongPhase {
  stopped,

  /// A recall has been written; the device has not yet reported motion.
  commanding,

  /// The device is reporting a keypose move.
  moving,

  /// Motion has ceased; waiting to see idle hold long enough to believe it.
  settling,

  /// Running blind on a timer because the device reports no state (the head).
  timing,

  /// Holding still at one end before starting the next leg.
  dwelling,

  failed,
}

/// Why a leg ended.
enum LegOutcome { done, stopped, linkLost, timedOut }

class LegTimings {
  const LegTimings({
    this.settle = const Duration(milliseconds: 600),
    this.launchGrace = const Duration(seconds: 3),
    this.moveTimeout = const Duration(seconds: 90),
    this.blindLeg = const Duration(seconds: 8),
  });

  /// How long idle must hold before a move counts as finished (§7: ~0.6 s).
  final Duration settle;

  /// How long to allow between writing a recall and seeing motion reported. If
  /// it expires the leg is treated as already at its target rather than as a
  /// failure — recalling a pose the carriage already sits at produces no
  /// observable movement, and without this the loop would hang forever.
  final Duration launchGrace;

  /// Upper bound on one leg. A full-rail traverse is ~29 s at recall speed
  /// (§6), so this is generous; it exists to stop a wedged device looping
  /// forever, not to time normal moves.
  final Duration moveTimeout;

  /// Blind leg duration for a device that reports no state — i.e. the head.
  final Duration blindLeg;
}

class LegSupervisor {
  LegSupervisor({
    required this.target,
    required this.stillRunning,
    this.onPhase,
  });

  final EkMotionTarget target;

  /// Polled so an external stop takes effect promptly, mid-leg.
  final bool Function() stillRunning;

  final void Function(PingPongPhase phase)? onPhase;

  /// How often device state is sampled. Telemetry arrives at about 3.3 Hz, so
  /// this oversamples comfortably.
  static const tick = Duration(milliseconds: 50);

  /// Writes the recall. Kept separate from [awaitCompletion] so a fleet can
  /// issue every device's recall before it starts waiting on any of them.
  Future<void> command(int slot, MotionSettings motion) {
    onPhase?.call(PingPongPhase.commanding);
    return target.recallPose(slot, settings: motion);
  }

  /// Waits for the commanded move to finish.
  Future<LegOutcome> awaitCompletion(LegTimings timings) {
    return target.snapshot.reportsMotionState
        ? _supervise(timings)
        : _blind(timings.blindLeg);
  }

  /// For a device that reports motion state — the slider.
  ///
  /// Waits for the move to begin, then for idle to hold continuously for
  /// [LegTimings.settle]. The hold is the point: the state byte reads idle in
  /// the gap between the recall being written and the motor starting, so a bare
  /// "is it idle?" check would call the leg finished immediately.
  Future<LegOutcome> _supervise(LegTimings timings) async {
    final started = DateTime.now();
    var sawMotion = false;
    DateTime? idleSince;

    while (true) {
      await Future<void>.delayed(tick);
      if (!stillRunning()) return LegOutcome.stopped;

      final s = target.snapshot;
      if (!s.isReady) return LegOutcome.linkLost;

      final elapsed = DateTime.now().difference(started);
      if (elapsed > timings.moveTimeout) return LegOutcome.timedOut;

      switch (s.state) {
        case EkState.keyposeMove:
          sawMotion = true;
          idleSince = null;
          onPhase?.call(PingPongPhase.moving);

        case EkState.idle:
          // Before motion has been observed, idle only means the command has
          // not taken effect yet.
          if (!sawMotion && elapsed < timings.launchGrace) continue;
          idleSince ??= DateTime.now();
          onPhase?.call(PingPongPhase.settling);
          if (DateTime.now().difference(idleSince) >= timings.settle) {
            return LegOutcome.done;
          }

        case EkState.manualJog:
        case EkState.ack:
        case EkState.unknown:
          // Someone else is driving, or a frame we cannot read. Either way the
          // device is not idle, so restart the settle clock.
          idleSince = null;
      }
    }
  }

  /// For a device that reports no usable state — i.e. the HeadONE.
  ///
  /// The head's telemetry carries no state byte and no position (§5), so there
  /// is nothing to supervise. This waits a fixed duration and hopes, which is
  /// strictly worse than the slider's path and is why §8 lists head position
  /// reporting as still undecoded. Sliced so a stop takes effect promptly.
  Future<LegOutcome> _blind(Duration leg) async {
    final until = DateTime.now().add(leg);
    onPhase?.call(PingPongPhase.timing);
    while (DateTime.now().isBefore(until)) {
      await Future<void>.delayed(tick);
      if (!stillRunning()) return LegOutcome.stopped;
      if (!target.snapshot.isReady) return LegOutcome.linkLost;
    }
    return LegOutcome.done;
  }

  /// An interruptible sleep. False if stopped partway.
  Future<bool> sleep(Duration d) async {
    final until = DateTime.now().add(d);
    while (DateTime.now().isBefore(until)) {
      await Future<void>.delayed(tick);
      if (!stillRunning()) return false;
    }
    return true;
  }
}

/// Turns a leg outcome into the message a user should see, or null if fine.
String? legErrorMessage(LegOutcome outcome, LegTimings timings) {
  switch (outcome) {
    case LegOutcome.done:
    case LegOutcome.stopped:
      return null;
    case LegOutcome.linkLost:
      return 'link lost mid-move';
    case LegOutcome.timedOut:
      return 'move did not complete within ${timings.moveTimeout.inSeconds}s';
  }
}
