/// Ping-pong where every leg is a synchronised move.
///
/// This exists alongside [FleetPingPong] rather than replacing it, because the
/// two supervise motion in genuinely different ways and neither is right for
/// every case:
///
///  - [FleetPingPong] commands each device's own pose recall and then *watches*
///    for it to finish. It works with no calibration at all and needs nothing
///    from the host mid-move, so a stalled app cannot leave a motor streaming.
///    What it cannot do is make the axes arrive together — each runs at its own
///    rate, and the slider routinely beats the head to the end by seconds.
///  - This class *imposes* the leg duration from a host clock. Both axes are
///    commanded on the same tick and stopped on the same tick, so they begin and
///    end together by construction. That is what makes the shot look right, and
///    it is the reason the previous attempt — solving each device's speed
///    percentage so the durations would match — could not work: duration is not
///    a predictable function of the percentage once the motor saturates, and
///    the head cannot be measured at all (§5).
///
/// The cost is that a leg is only as reliable as the host: the slider is
/// velocity-streamed, which §7 warns keeps running if the host vanishes. That
/// is acceptable for attended shooting and is why every exit path here stops
/// every device.
library;

import 'dart:async';

import 'fleet.dart';
import 'leg_supervisor.dart';
import 'sync_move.dart';

class SyncPingPong {
  SyncPingPong({
    required this.axesFor,
    required this.shot,
    required this.stopAll,
    this.slotA = 0,
    this.slotB = 1,
  });

  /// Builds the axes for a leg to [slot]. Rebuilt every leg because the
  /// slider's starting point — and therefore its whole velocity profile —
  /// depends on where the carriage actually is now.
  final List<SyncAxis> Function(int slot) axesFor;

  /// How long each leg should take. Extended, never shortened, if an axis
  /// physically cannot cover the distance in that time.
  final Duration shot;

  /// Stops every device. Called on every exit path, including the ones where a
  /// [SyncMove] has already stopped its own axes — a redundant stop costs one
  /// frame, a missed one costs a running motor.
  final Future<List<String>> Function() stopAll;

  final int slotA;
  final int slotB;

  final _statuses = StreamController<FleetStatus>.broadcast();
  Stream<FleetStatus> get statuses => _statuses.stream;

  FleetStatus _status = const FleetStatus(phase: PingPongPhase.stopped);
  FleetStatus get status => _status;

  bool _running = false;
  Future<void>? _loop;

  bool get isRunning => _running;

  /// The duration a leg to [slot] will actually take, once clamped up to what
  /// the hardware can manage. The UI shows this so a shot duration that is
  /// quietly being overridden is visible rather than surprising.
  Duration effectiveLeg(int slot) {
    final move = SyncMove(axes: axesFor(slot), stillRunning: () => true);
    final min = move.minimumDuration;
    return min > shot ? min : shot;
  }

  Future<void> start({Duration dwell = Duration.zero, int maxLegs = 0}) {
    if (_running) return _loop ?? Future<void>.value();
    _running = true;
    _loop = _run(dwell: dwell, maxLegs: maxLegs);
    return _loop!;
  }

  Future<void> stop() async {
    _running = false;
    await _loop;
    await stopAll();
    _emit(FleetStatus(
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

  Future<void> _run({required Duration dwell, required int maxLegs}) async {
    var slot = slotA;
    var legs = 0;
    String? error;

    try {
      while (_running) {
        final axes = axesFor(slot);
        if (axes.isEmpty) {
          error = 'nothing to move';
          break;
        }

        final move = SyncMove(
          axes: axes,
          stillRunning: () => _running,
          onProgress: (p) => _emit(FleetStatus(
            phase: PingPongPhase.moving,
            slot: slot,
            legs: legs,
          )),
        );

        final min = move.minimumDuration;
        final outcome = await move.run(min > shot ? min : shot);

        switch (outcome) {
          case SyncOutcome.stopped:
            return;
          case SyncOutcome.linkLost:
            error = 'link lost mid-move';
          case SyncOutcome.failed:
            error = 'a device would not take the command';
          case SyncOutcome.done:
            break;
        }
        if (error != null) break;

        legs++;
        if (maxLegs > 0 && legs >= maxLegs) break;
        slot = slot == slotA ? slotB : slotA;

        if (dwell > Duration.zero) {
          _emit(FleetStatus(
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
      await stopAll();
      _emit(FleetStatus(
        phase: error == null ? PingPongPhase.stopped : PingPongPhase.failed,
        slot: slot,
        legs: legs,
        error: error,
      ));
    }
  }

  /// An interruptible sleep, so a stop lands promptly during a dwell.
  Future<bool> _sleep(Duration d) async {
    final until = DateTime.now().add(d);
    while (DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!_running) return false;
    }
    return true;
  }

  void _emit(FleetStatus s) {
    _status = s;
    if (!_statuses.isClosed) _statuses.add(s);
  }
}
