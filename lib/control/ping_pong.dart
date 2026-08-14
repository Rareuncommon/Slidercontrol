/// Host-supervised ping-pong between two saved poses, on one device.
///
/// EDELKRONE_PROTOCOL.md §3 and §7: the device's own loop mode stops after
/// roughly one round trip, so continuous motion has to be driven from the host —
/// recall a pose, wait for the move to finish, recall the other one, repeat.
/// This controller never sends the loop flag; every leg is an ordinary recall.
///
/// Pose recalls are used rather than streamed velocity deliberately (§7): a
/// recall is a single command the device completes on its own, so a dropped
/// link ends with the device stopped. Streamed velocity keeps running if the
/// host disappears.
///
/// The per-leg supervision lives in [LegSupervisor], shared with the fleet.
library;

import 'dart:async';

import '../ble/ek_snapshot.dart';
import 'leg_supervisor.dart';
import 'motion_settings.dart';

export 'leg_supervisor.dart' show PingPongPhase, LegOutcome, LegTimings;

class PingPongStatus {
  final PingPongPhase phase;

  /// The slot most recently commanded.
  final int? slot;

  /// Completed one-way legs, not round trips.
  final int legs;

  /// How long the last completed leg took. Null until one finishes.
  ///
  /// Worth showing: on the head it is the only feedback there is that the
  /// blind-leg timer is anywhere near the real move duration, and on the slider
  /// it makes a speed change legible.
  final Duration? lastLeg;

  final String? error;

  const PingPongStatus({
    required this.phase,
    this.slot,
    this.legs = 0,
    this.lastLeg,
    this.error,
  });

  bool get isRunning =>
      phase != PingPongPhase.stopped && phase != PingPongPhase.failed;
}

class PingPongController {
  PingPongController({
    required this.target,
    this.slotA = 0,
    this.slotB = 1,
  });

  final EkMotionTarget target;
  final int slotA;
  final int slotB;

  static const defaultSettle = Duration(milliseconds: 600);
  static const defaultLaunchGrace = Duration(seconds: 3);
  static const defaultMoveTimeout = Duration(seconds: 90);

  /// Blind leg duration for a device that reports no state — i.e. the head.
  ///
  /// Guesswork about hardware that tells us nothing, which is why the UI makes
  /// it adjustable.
  static const defaultBlindLeg = Duration(seconds: 8);

  /// Pause at each end before the next leg. Zero reverses immediately.
  static const defaultDwell = Duration.zero;

  final _statuses = StreamController<PingPongStatus>.broadcast();
  Stream<PingPongStatus> get statuses => _statuses.stream;

  PingPongStatus _status = const PingPongStatus(phase: PingPongPhase.stopped);
  PingPongStatus get status => _status;

  bool _running = false;
  Future<void>? _loop;
  int _slot = 0;
  int _legs = 0;
  Duration? _lastLeg;

  bool get isRunning => _running;

  /// Starts the loop. Returns once the loop has *finished* — call without
  /// awaiting to run it in the background, then use [stop].
  Future<void> start({
    required MotionSettings motion,
    Duration settle = defaultSettle,
    Duration launchGrace = defaultLaunchGrace,
    Duration moveTimeout = defaultMoveTimeout,
    Duration blindLeg = defaultBlindLeg,
    Duration dwell = defaultDwell,
    int maxLegs = 0,
  }) {
    if (_running) return _loop ?? Future<void>.value();
    _running = true;
    _loop = _run(
      motion: motion,
      timings: LegTimings(
        settle: settle,
        launchGrace: launchGrace,
        moveTimeout: moveTimeout,
        blindLeg: blindLeg,
      ),
      dwell: dwell,
      maxLegs: maxLegs,
    );
    return _loop!;
  }

  /// Stops the loop and the motor. Safe to call when not running.
  Future<void> stop() async {
    _running = false;
    await _loop;
    // Unconditional, even if the loop already sent one: a redundant stop is
    // harmless, a missed one leaves the carriage locked under torque (§7).
    try {
      await target.stopMotion();
    } catch (_) {
      // Nothing further this layer can do.
    }
    _emit(PingPongStatus(
      phase: PingPongPhase.stopped,
      slot: _status.slot,
      legs: _status.legs,
      lastLeg: _status.lastLeg,
      error: _status.error,
    ));
  }

  Future<void> dispose() async {
    await stop();
    await _statuses.close();
  }

  Future<void> _run({
    required MotionSettings motion,
    required LegTimings timings,
    required Duration dwell,
    required int maxLegs,
  }) async {
    _slot = slotA;
    _legs = 0;
    String? error;

    final supervisor = LegSupervisor(
      target: target,
      stillRunning: () => _running,
      onPhase: (phase) => _emit(PingPongStatus(
        phase: phase,
        slot: _slot,
        legs: _legs,
        lastLeg: _lastLeg,
      )),
    );

    try {
      while (_running) {
        if (!target.snapshot.isReady) {
          error = 'link is not ready';
          break;
        }

        final legStarted = DateTime.now();
        await supervisor.command(_slot, motion);
        final outcome = await supervisor.awaitCompletion(timings);

        if (outcome != LegOutcome.done) {
          error = legErrorMessage(outcome, timings);
          break;
        }

        _lastLeg = DateTime.now().difference(legStarted);
        _legs++;
        if (maxLegs > 0 && _legs >= maxLegs) break;
        _slot = _slot == slotA ? slotB : slotA;

        if (dwell > Duration.zero) {
          _emit(PingPongStatus(
            phase: PingPongPhase.dwelling,
            slot: _slot,
            legs: _legs,
            lastLeg: _lastLeg,
          ));
          if (!await supervisor.sleep(dwell)) break;
        }
      }
    } catch (e) {
      error = '$e';
    } finally {
      _running = false;
      // Always stop, on every exit path — normal, error, or abort.
      try {
        await target.stopMotion();
      } catch (_) {
        // Best effort.
      }
      _emit(PingPongStatus(
        phase: error == null ? PingPongPhase.stopped : PingPongPhase.failed,
        slot: _slot,
        legs: _legs,
        lastLeg: _lastLeg,
        error: error,
      ));
    }
  }

  void _emit(PingPongStatus s) {
    _status = s;
    if (!_statuses.isClosed) _statuses.add(s);
  }
}
