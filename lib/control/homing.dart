/// Homing and closed-loop positioning for the slider.
///
/// Ported from the reference Python (`ek_drive.py`), not reimplemented. Both of
/// the awkward parts exist because simpler versions failed on this hardware:
///
///  - **Stall detection uses net progress over a ~0.5 s window**, not per-tick
///    deltas. Pressed against a stop the encoder dithers by hundreds of counts
///    — belt flex, motor cogging — and that noise exceeds any sensible per-tick
///    threshold. Over half a second it averages out; genuine motion does not
///    (§7).
///  - **A suspected stop is confirmed by backing off and re-approaching.** The
///    SliderPLUS hands the carriage between mechanisms partway along the rail,
///    and during that transition progress pauses convincingly enough to look
///    like an end stop (§7).
///
/// The threshold scales with commanded velocity rather than being a fixed count:
/// at 16k counts/sec the carriage covers ~1600 counts per tick, so a fixed
/// number that works at one speed is meaningless at another.
///
/// **Never for the head.** It has no end stops, and it reports no position at
/// all (§5), so there is nothing to close a loop against. Every entry point
/// here refuses a head target.
///
/// Pure Dart — it drives an [EkMotionTarget], so a simulated rail can exercise
/// the stall detector, the false-stall recovery, the travel budget and the
/// timeout without hardware.
library;

import 'dart:async';
import 'dart:collection';

import '../ble/ek_snapshot.dart';
import '../ek_protocol.dart';

// --- tuning, carried across from ek_drive.py --------------------------------

/// Cover ground at this speed. ~40 s for a 475k-count rail; full motor speed is
/// ~30,500, so this is deliberately conservative.
const homeFastVelocity = 12000;

/// Creep onto the stop on the confirming pass.
const homeSlowVelocity = 3000;

/// Fraction of expected progress below which the carriage counts as stalled.
const stallFraction = 0.30;

/// Seconds of history used to judge progress.
const stallWindow = Duration(milliseconds: 500);

/// Absolute floor, in counts over the whole window.
const stallFloor = 200;

const stallConfirmBackoff = 6000;
const stallConfirmSlack = 2.5;
const stallConfirmTries = 5;

/// Slack over the configured rail length before a pass is abandoned.
const homingBudgetSlack = 1.25;

const homeTimeout = Duration(seconds: 150);

/// Step away from the hard stop once it is found.
const backoffCounts = 3000;

/// Stay this far clear of each end during ordinary moves.
const softMargin = 2000;

const moveGain = 0.9;
const moveMinVelocity = 1200;
const moveMaxVelocity = 18000;
const moveTolerance = 400;
const moveTimeout = Duration(seconds: 60);

/// Time before the motor is expected to have broken loose; stall judgements are
/// suppressed until then.
const _spinUp = Duration(milliseconds: 800);

// --- results ----------------------------------------------------------------

enum HomingStage {
  idle,
  seeking,
  confirming,
  backingOff,
  moving,
  saving,
  complete,
  aborted,
}

class HomingProgress {
  const HomingProgress({
    required this.stage,
    required this.message,
    this.position,
    this.travelled,
    this.fraction,
  });

  final HomingStage stage;
  final String message;
  final int? position;
  final int? travelled;

  /// 0–1 estimate of the whole operation, where one is available.
  final double? fraction;
}

/// What homing established about the rail.
class RailDatum {
  const RailDatum({
    required this.endLo,
    required this.endHi,
    required this.velocitySign,
  });

  /// Unwrapped counts at each mechanical end, in this session's frame.
  final int endLo;
  final int endHi;

  /// +1 if a positive velocity makes the counter increase.
  final int velocitySign;

  int get travel => endHi - endLo;

  int fractionToCounts(double f) =>
      endLo + (travel * f.clamp(0.0, 1.0)).round();

  double countsToFraction(int counts) {
    if (travel <= 0) return 0;
    return ((counts - endLo) / travel).clamp(0.0, 1.0);
  }

  /// Keeps ordinary moves clear of the hard stops.
  int clampSoft(int counts) =>
      counts.clamp(endLo + softMargin, endHi - softMargin);
}

class HomingAborted implements Exception {
  HomingAborted(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

class _StallResult {
  const _StallResult(this.position, this.moved);
  final int position;
  final int moved;
}

// --- the driver -------------------------------------------------------------

class Homing {
  Homing({
    required this.target,
    required this.stillRunning,
    this.onProgress,
    this.tick = jogPeriod,
    this.railTravelCounts = EkRig.sliderTravelCounts,
    this.fastVelocity = homeFastVelocity,
    this.slowVelocity = homeSlowVelocity,
    this.spinUp = _spinUp,
  });

  final EkMotionTarget target;

  /// Polled constantly so a stop takes effect mid-move.
  final bool Function() stillRunning;

  final void Function(HomingProgress)? onProgress;

  /// Velocity streaming interval. Overridable so tests can run faster.
  final Duration tick;

  /// Configured rail length. A default, not a constant — re-measured whenever a
  /// two-end home runs, and overridable for a different rail (§6).
  final int railTravelCounts;

  /// Approach speeds. Overridable so a simulated rail can be exercised quickly;
  /// the defaults are the measured-safe values.
  final int fastVelocity;
  final int slowVelocity;

  /// Stall judgements are suppressed until the motor has had time to break
  /// loose. Overridable for the same reason.
  final Duration spinUp;

  int? _backoffFrom;

  void _emit(HomingStage stage, String message,
      {int? travelled, double? fraction}) {
    onProgress?.call(HomingProgress(
      stage: stage,
      message: message,
      position: target.snapshot.position,
      travelled: travelled,
      fraction: fraction,
    ));
  }

  void _assertSlider() {
    if (target.kind != EkKind.slider) {
      throw HomingAborted(
        'Homing does not apply to the head: it has no end stops and reports no '
        'position (§5). Jog it and save instead.',
      );
    }
  }

  int? get _position => target.snapshot.position;

  /// Drives at [velocity] until the carriage stops making net progress.
  ///
  /// Bounded three ways — the stall detector, a travel budget, and a timeout —
  /// and aborts the instant the link goes, because the device keeps executing
  /// its last velocity command if the host disappears (§7).
  Future<_StallResult> _driveUntilStall(
    int velocity, {
    required Duration timeout,
    required int budget,
  }) async {
    final expectedPerWindow =
        velocity.abs() * (stallWindow.inMilliseconds / 1000.0);
    final threshold = (expectedPerWindow * stallFraction)
        .clamp(stallFloor.toDouble(), double.infinity);

    final history = Queue<({Duration at, int position})>();
    var elapsed = Duration.zero;
    int? startPos;
    var movedTotal = 0;

    try {
      while (elapsed < timeout) {
        if (!stillRunning()) throw HomingAborted('stopped');
        if (!target.snapshot.isReady) {
          throw HomingAborted('BLE link lost mid-move');
        }

        await target.setVelocity(velocity);
        await Future<void>.delayed(tick);
        elapsed += tick;

        final pos = _position;
        if (pos == null) continue;
        startPos ??= pos;
        movedTotal = pos - startPos;

        history.add((at: elapsed, position: pos));
        while (history.isNotEmpty &&
            elapsed - history.first.at > stallWindow) {
          history.removeFirst();
        }

        if (movedTotal.abs() > budget) {
          throw HomingAborted(
            'travel budget exceeded — moved ${movedTotal.abs()} counts past '
            '$budget without reaching a stop. If your rail is longer, raise the '
            'configured travel.',
          );
        }

        // Judge only once the motor has had time to break loose AND the
        // history genuinely spans the full window.
        //
        // Both halves matter. `threshold` is the progress expected over a whole
        // stallWindow, so comparing it against a partially-filled window
        // declares a stall almost immediately — the samples cover less time, so
        // they cover less distance. The reference Python encodes this as
        // `elapsed > max(0.8, STALL_WINDOW * 1.5)`; this is the same rule
        // expressed directly, which keeps it correct if the tick changes.
        final span = elapsed - history.first.at;
        if (elapsed > spinUp &&
            history.length >= 4 &&
            span >= stallWindow * 0.9) {
          final net = (pos - history.first.position).abs();
          if (net < threshold) {
            return _StallResult(pos, movedTotal);
          }
        }
      }
      throw HomingAborted('timed out after ${timeout.inSeconds}s');
    } finally {
      await _neutralise();
    }
  }

  /// Zero velocity, repeated, then the explicit stop.
  Future<void> _neutralise() async {
    try {
      for (var i = 0; i < 3; i++) {
        await target.setVelocity(0);
        await Future<void>.delayed(tick);
      }
      await target.stopMotion();
    } catch (_) {
      // Nothing further this layer can do.
    }
  }

  /// Open-loop nudge for a fixed time, then stop.
  Future<void> _driveFor(int velocity, Duration duration) async {
    final ticks =
        (duration.inMilliseconds / tick.inMilliseconds).ceil().clamp(1, 10000);
    try {
      for (var i = 0; i < ticks; i++) {
        if (!stillRunning()) break;
        await target.setVelocity(velocity);
        await Future<void>.delayed(tick);
      }
    } finally {
      await _neutralise();
    }
  }

  /// Approaches a mechanical stop, confirming that it really is one.
  ///
  /// Fast pass to cover ground, then back off and creep in again. A genuine end
  /// stop reappears at the same place every time; a mechanism transition does
  /// not.
  Future<_StallResult> _seekEnd(
    int direction,
    String label, {
    required int budget,
  }) async {
    _emit(HomingStage.seeking, 'Seeking the $label end…');
    var total = 0;
    var haveCandidate = false;
    var retesting = false;
    _backoffFrom = null;

    for (var attempt = 1; attempt <= stallConfirmTries; attempt++) {
      final velocity =
          direction * (retesting ? slowVelocity : fastVelocity);
      final result = await _driveUntilStall(
        velocity,
        timeout: homeTimeout,
        budget: budget,
      );
      total += result.moved;

      if (haveCandidate) {
        final travelled = _backoffFrom == null
            ? 0
            : (result.position - _backoffFrom!).abs();
        if (travelled > stallConfirmBackoff * stallConfirmSlack) {
          // It drove well past the previous stop, so that was a false stall —
          // the mid-rail mechanism transition, most likely.
          _emit(
            HomingStage.seeking,
            'Attempt $attempt: drove $travelled counts past the previous stop — '
            'false stall, continuing.',
          );
          haveCandidate = false;
          _backoffFrom = null;
          retesting = false;
          continue;
        }
        _emit(
          HomingStage.confirming,
          'Confirmed the $label end at ${result.position}.',
          travelled: total,
        );
        return _StallResult(result.position, total);
      }

      haveCandidate = true;
      _emit(
        HomingStage.backingOff,
        'Possible $label end at ${result.position}; backing off to confirm…',
        travelled: total,
      );
      final backoffTime = Duration(
        milliseconds:
            (stallConfirmBackoff / slowVelocity * 1000).round().clamp(
                  tick.inMilliseconds,
                  30000,
                ),
      );
      await _driveFor(-direction * slowVelocity, backoffTime);
      _backoffFrom = _position;
      retesting = true;
    }

    throw HomingAborted(
      'could not confirm the $label end after $stallConfirmTries attempts',
    );
  }

  /// Touches one end and derives the far end from the configured rail length.
  ///
  /// Half the wear and half the time of a two-end home, and it never drives into
  /// the second stop. Accuracy depends entirely on [railTravelCounts] being
  /// right for this rail.
  Future<RailDatum> homeSingle({int direction = 1}) async {
    _assertSlider();
    final budget = (railTravelCounts * homingBudgetSlack).round();
    final result = await _seekEnd(direction, 'reference', budget: budget);

    final int velocitySign;
    final int towardFar;
    if (result.moved != 0) {
      velocitySign = result.moved > 0 ? 1 : -1;
      towardFar = result.moved > 0 ? -1 : 1;
    } else {
      // Polarity cannot be measured from a zero-length move. Assume, and say so.
      _emit(
        HomingStage.seeking,
        'The carriage never moved — it was already against this end. Velocity '
        'polarity is assumed; verify with a short jog.',
      );
      velocitySign = -1;
      towardFar = 1;
    }

    final far = result.position + towardFar * railTravelCounts;
    final lo = result.position < far ? result.position : far;
    final hi = result.position < far ? far : result.position;
    final datum =
        RailDatum(endLo: lo, endHi: hi, velocitySign: velocitySign);

    _emit(
      HomingStage.moving,
      'Reference end at ${result.position}; stepping clear of the stop.',
    );
    await moveTo(result.position + towardFar * backoffCounts, datum);

    _emit(HomingStage.complete,
        'Homed. Travel configured as ${datum.travel} counts.');
    return datum;
  }

  /// Finds both mechanical ends and measures travel rather than assuming it.
  Future<RailDatum> homeBoth() async {
    _assertSlider();
    final budget = (railTravelCounts * homingBudgetSlack).round();

    final first = await _seekEnd(1, 'first', budget: budget);
    var velocitySign = first.moved != 0 ? (first.moved > 0 ? 1 : -1) : 0;

    // The budget comes from the configured rail length, never from the first
    // pass: that pass only covers the distance from wherever the carriage
    // started to the nearest end, which says nothing about the rail.
    final second = await _seekEnd(-1, 'opposite', budget: budget);
    if (velocitySign == 0 && second.moved != 0) {
      velocitySign = second.moved > 0 ? -1 : 1;
    }
    if (velocitySign == 0) velocitySign = -1;

    final lo =
        first.position < second.position ? first.position : second.position;
    final hi =
        first.position < second.position ? second.position : first.position;
    final travel = hi - lo;

    if (travel < 5 * softMargin) {
      throw HomingAborted(
        'measured travel of only $travel counts looks wrong — check the '
        'carriage was free to move, then re-run.',
      );
    }
    if ((travel - railTravelCounts).abs() > railTravelCounts * 0.25) {
      _emit(
        HomingStage.confirming,
        'Measured travel $travel differs a lot from the configured '
        '$railTravelCounts. One end was probably a false stall — worth '
        're-running before trusting the fractions.',
      );
    }

    final datum = RailDatum(endLo: lo, endHi: hi, velocitySign: velocitySign);
    final pos = _position ?? lo;
    final backOffTarget = (pos - lo) < travel / 2
        ? lo + backoffCounts
        : hi - backoffCounts;
    _emit(HomingStage.moving, 'Travel $travel counts. Stepping clear.');
    await moveTo(backOffTarget, datum);

    _emit(HomingStage.complete, 'Homed. Measured travel $travel counts.');
    return datum;
  }

  /// Closed-loop move to an absolute count.
  ///
  /// The protocol has no go-to-arbitrary-position command — only pose recall —
  /// so the loop is closed host-side against telemetry.
  Future<bool> moveTo(int counts, RailDatum datum) async {
    _assertSlider();
    final goal = datum.clampSoft(counts);
    var elapsed = Duration.zero;
    try {
      while (elapsed < moveTimeout) {
        if (!stillRunning()) return false;
        if (!target.snapshot.isReady) {
          throw HomingAborted('BLE link lost mid-move');
        }

        final pos = _position;
        if (pos == null) {
          await Future<void>.delayed(tick);
          elapsed += tick;
          continue;
        }

        final error = goal - pos;
        if (error.abs() <= moveTolerance) return true;

        final magnitude = (error.abs() * moveGain)
            .clamp(moveMinVelocity.toDouble(), moveMaxVelocity.toDouble());
        final velocity =
            (magnitude * (error > 0 ? 1 : -1) * datum.velocitySign).round();

        await target.setVelocity(velocity);
        await Future<void>.delayed(tick);
        elapsed += tick;
      }
      _emit(HomingStage.aborted,
          'Move timed out ${goal - (_position ?? goal)} counts short.');
      return false;
    } finally {
      await _neutralise();
    }
  }
}
