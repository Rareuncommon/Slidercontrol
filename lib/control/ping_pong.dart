/// Host-supervised ping-pong between two saved poses.
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
/// Pure Dart — it drives an [EkMotionTarget], not a BLE connection, so the
/// timing logic can be tested without hardware.
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

/// Why a leg of the ping-pong ended.
enum _Leg { done, stopped, linkLost, timedOut }

class PingPongStatus {
  final PingPongPhase phase;

  /// The slot most recently commanded.
  final int? slot;

  /// Completed one-way legs, not round trips.
  final int legs;

  final String? error;

  const PingPongStatus({
    required this.phase,
    this.slot,
    this.legs = 0,
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

  /// How long idle must hold before a move counts as finished (§7 says ~0.6 s).
  static const defaultSettle = Duration(milliseconds: 600);

  /// How long to allow between writing a recall and seeing the device report
  /// motion. If it expires without motion the leg is treated as already at its
  /// target rather than as a failure — recalling a pose the carriage is already
  /// sitting at produces no observable movement.
  static const defaultLaunchGrace = Duration(seconds: 3);

  /// Upper bound on a single leg. A full-rail traverse is ~29 s at recall speed
  /// (§6), so this is generous; it exists to stop a wedged device looping
  /// forever, not to time normal moves.
  static const defaultMoveTimeout = Duration(seconds: 90);

  /// Blind leg duration for a device that reports no state — i.e. the head.
  ///
  /// Pure guesswork about the hardware: it has to cover the longest move
  /// between the two poses, and there is no way to measure that from the head
  /// itself. Adjustable from the UI for exactly that reason.
  static const defaultBlindLeg = Duration(seconds: 8);

  /// Pause at each end before starting the next leg. Zero reverses immediately.
  static const defaultDwell = Duration.zero;

  /// How often the supervisor samples device state. Telemetry arrives at about
  /// 3.3 Hz, so this oversamples comfortably.
  static const _tick = Duration(milliseconds: 50);

  final _statuses = StreamController<PingPongStatus>.broadcast();
  Stream<PingPongStatus> get statuses => _statuses.stream;

  PingPongStatus _status = const PingPongStatus(phase: PingPongPhase.stopped);
  PingPongStatus get status => _status;

  bool _running = false;
  Future<void>? _loop;

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
      settle: settle,
      launchGrace: launchGrace,
      moveTimeout: moveTimeout,
      blindLeg: blindLeg,
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
      error: _status.error,
    ));
  }

  Future<void> dispose() async {
    await stop();
    await _statuses.close();
  }

  Future<void> _run({
    required MotionSettings motion,
    required Duration settle,
    required Duration launchGrace,
    required Duration moveTimeout,
    required Duration blindLeg,
    required Duration dwell,
    required int maxLegs,
  }) async {
    var slot = slotA;
    var legs = 0;
    String? error;

    try {
      while (_running) {
        if (!target.snapshot.isReady) {
          error = 'link is not ready';
          break;
        }

        _emit(PingPongStatus(
          phase: PingPongPhase.commanding,
          slot: slot,
          legs: legs,
        ));
        await target.recallPose(slot, settings: motion);

        final result = target.snapshot.reportsMotionState
            ? await _superviseLeg(
                settle: settle,
                launchGrace: launchGrace,
                moveTimeout: moveTimeout,
                slot: slot,
                legs: legs,
              )
            : await _blindLeg(blindLeg, slot: slot, legs: legs);

        if (result != _Leg.done) {
          if (result == _Leg.linkLost) error = 'link lost mid-move';
          if (result == _Leg.timedOut) {
            error = 'move did not complete within '
                '${moveTimeout.inSeconds}s';
          }
          break;
        }

        legs++;
        if (maxLegs > 0 && legs >= maxLegs) break;
        slot = slot == slotA ? slotB : slotA;

        if (dwell > Duration.zero) {
          _emit(PingPongStatus(
            phase: PingPongPhase.dwelling,
            slot: slot,
            legs: legs,
          ));
          if (!await _sleep(dwell)) break;
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
        slot: slot,
        legs: legs,
        error: error,
      ));
    }
  }

  /// Supervision for a device that reports motion state — the slider.
  ///
  /// Waits for the move to begin, then for idle to hold continuously for
  /// [settle]. The hold matters: the state byte can read idle in the gap
  /// between the recall being written and the motor starting, so a bare
  /// "is it idle?" check would call the leg finished immediately.
  Future<_Leg> _superviseLeg({
    required Duration settle,
    required Duration launchGrace,
    required Duration moveTimeout,
    required int slot,
    required int legs,
  }) async {
    final started = DateTime.now();
    var sawMotion = false;
    DateTime? idleSince;

    while (true) {
      await Future<void>.delayed(_tick);
      if (!_running) return _Leg.stopped;

      final s = target.snapshot;
      if (!s.isReady) return _Leg.linkLost;

      final elapsed = DateTime.now().difference(started);
      if (elapsed > moveTimeout) return _Leg.timedOut;

      switch (s.state) {
        case EkState.keyposeMove:
          sawMotion = true;
          idleSince = null;
          _emit(PingPongStatus(
            phase: PingPongPhase.moving,
            slot: slot,
            legs: legs,
          ));

        case EkState.idle:
          // Before motion has been observed, idle only means the command has
          // not taken effect yet. Start the settle clock once motion has been
          // seen, or once the launch grace has expired — the latter covers a
          // recall to a pose the device is already sitting at, which never
          // reports movement at all.
          if (!sawMotion && elapsed < launchGrace) continue;
          idleSince ??= DateTime.now();
          _emit(PingPongStatus(
            phase: PingPongPhase.settling,
            slot: slot,
            legs: legs,
          ));
          if (DateTime.now().difference(idleSince) >= settle) {
            return _Leg.done;
          }

        case EkState.manualJog:
        case EkState.ack:
        case EkState.unknown:
          // Someone else is driving, or a frame we cannot read. Either way the
          // device is not idle, so restart the settle clock rather than count
          // this sample toward completion.
          idleSince = null;
      }
    }
  }

  /// Fallback for a device that reports no usable state — i.e. the HeadONE.
  ///
  /// The head's telemetry carries no state byte and no position (§5), so there
  /// is nothing to supervise. This waits a fixed duration and hopes, which is
  /// strictly worse than the slider's path and is the reason §8 lists head
  /// position reporting as still undecoded.
  ///
  /// The wait is sliced rather than one long delay so [stop] takes effect
  /// promptly instead of after the full leg.
  Future<_Leg> _blindLeg(Duration leg, {required int slot, required int legs}) async {
    final until = DateTime.now().add(leg);
    _emit(PingPongStatus(
      phase: PingPongPhase.timing,
      slot: slot,
      legs: legs,
    ));
    while (DateTime.now().isBefore(until)) {
      await Future<void>.delayed(_tick);
      if (!_running) return _Leg.stopped;
      if (!target.snapshot.isReady) return _Leg.linkLost;
    }
    return _Leg.done;
  }

  /// An interruptible sleep. Returns false if the loop was stopped partway.
  Future<bool> _sleep(Duration d) async {
    final until = DateTime.now().add(d);
    while (DateTime.now().isBefore(until)) {
      await Future<void>.delayed(_tick);
      if (!_running) return false;
    }
    return true;
  }

  void _emit(PingPongStatus s) {
    _status = s;
    if (!_statuses.isClosed) _statuses.add(s);
  }
}
