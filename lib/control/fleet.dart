/// Moving several devices together.
///
/// **This is host-side coordination, not the device's own coordinated mode.**
/// EDELKRONE_PROTOCOL.md §8 lists coordinated slider + head moves as undecoded:
/// the official app pairs the two units and captures both axes into a single
/// keypose, and that path was never captured. Nothing here reproduces it.
///
/// What this does instead is issue an ordinary, already-verified pose recall to
/// each device at as near the same instant as separate BLE links allow, then
/// wait for *all* of them before commanding the next leg.
///
/// The practical difference matters and is not hidden: the axes start together
/// but each runs at its own rate, so within a leg they can drift — the slider
/// may arrive well before the head, or the reverse. There is no interpolation
/// between them. What is guaranteed is that they stay in step leg by leg,
/// because no device starts its next leg until every device has finished this
/// one. To make the axes actually arrive together, tune each device's speed
/// until their leg durations match.
library;

import 'dart:async';

import '../ble/ek_snapshot.dart';
import 'leg_supervisor.dart';
import 'motion_settings.dart';

/// One device in the fleet, with its own motion settings — a speed that suits
/// the slider rarely suits the head.
class FleetMember {
  const FleetMember({
    required this.target,
    required this.name,
    required this.motion,
    this.timings = const LegTimings(),
    this.motionFor,
  });

  final EkMotionTarget target;
  final String name;
  final MotionSettings motion;
  final LegTimings timings;

  /// Resolves the motion for a specific slot, overriding [motion].
  ///
  /// Needed because duration matching depends on how far *this* leg travels:
  /// the slider's distance changes from leg to leg, so its speed has to be
  /// re-solved each time if both axes are to finish together.
  final MotionSettings Function(int slot)? motionFor;

  MotionSettings motionForSlot(int slot) => motionFor?.call(slot) ?? motion;
}

class FleetStatus {
  const FleetStatus({
    required this.phase,
    this.slot,
    this.legs = 0,
    this.error,
    this.memberPhases = const {},
  });

  final PingPongPhase phase;
  final int? slot;
  final int legs;
  final String? error;

  /// Per-device phase, so a device lagging the others is visible rather than
  /// hidden behind a single aggregate state.
  final Map<String, PingPongPhase> memberPhases;

  bool get isRunning =>
      phase != PingPongPhase.stopped && phase != PingPongPhase.failed;
}

class FleetPingPong {
  FleetPingPong({
    required this.members,
    this.slotA = 0,
    this.slotB = 1,
  });

  final List<FleetMember> members;
  final int slotA;
  final int slotB;

  final _statuses = StreamController<FleetStatus>.broadcast();
  Stream<FleetStatus> get statuses => _statuses.stream;

  FleetStatus _status = const FleetStatus(phase: PingPongPhase.stopped);
  FleetStatus get status => _status;

  bool _running = false;
  Future<void>? _loop;
  final _phases = <String, PingPongPhase>{};

  bool get isRunning => _running;

  /// Saves every device's *current* position into [slot].
  ///
  /// Each device stores its own axis; there is no combined keypose (§8). Recall
  /// the same slot on all of them to return to this arrangement.
  Future<List<String>> saveAll(int slot) async {
    final failures = <String>[];
    for (final m in members) {
      try {
        await m.target.savePose(slot);
      } catch (e) {
        failures.add('${m.name}: $e');
      }
    }
    return failures;
  }

  /// Recalls [slot] on every device at once, without supervising the move.
  Future<List<String>> recallAll(int slot) async {
    final failures = <String>[];
    await Future.wait(members.map((m) async {
      try {
        await m.target.recallPose(slot, settings: m.motionForSlot(slot));
      } catch (e) {
        failures.add('${m.name}: $e');
      }
    }));
    return failures;
  }

  /// Stops every device. Runs them all even if one throws — a second motor must
  /// not be left running because the first one's write failed.
  Future<List<String>> stopAll() async {
    final failures = <String>[];
    for (final m in members) {
      try {
        await m.target.stopMotion();
      } catch (e) {
        failures.add('${m.name}: $e');
      }
    }
    return failures;
  }

  Future<void> start({
    Duration dwell = Duration.zero,
    int maxLegs = 0,
  }) {
    if (_running) return _loop ?? Future<void>.value();
    if (members.isEmpty) return Future<void>.value();
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
      memberPhases: Map.of(_phases),
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

    final supervisors = <FleetMember, LegSupervisor>{
      for (final m in members)
        m: LegSupervisor(
          target: m.target,
          stillRunning: () => _running,
          onPhase: (phase) {
            _phases[m.name] = phase;
            _emit(FleetStatus(
              phase: _aggregate(),
              slot: slot,
              legs: legs,
              memberPhases: Map.of(_phases),
            ));
          },
        ),
    };

    try {
      while (_running) {
        final notReady =
            members.where((m) => !m.target.snapshot.isReady).map((m) => m.name);
        if (notReady.isNotEmpty) {
          error = 'link is not ready: ${notReady.join(', ')}';
          break;
        }

        // Issue every recall before awaiting any of them, so the axes start as
        // close together as separate BLE links allow.
        await Future.wait(
          supervisors.entries
              .map((e) => e.value.command(slot, e.key.motionForSlot(slot))),
        );

        // Wait for all of them. No device starts its next leg until every
        // device has finished this one.
        final outcomes = await Future.wait(
          supervisors.entries
              .map((e) => e.value.awaitCompletion(e.key.timings)),
        );

        final bad = <String>[];
        var i = 0;
        for (final entry in supervisors.entries) {
          final outcome = outcomes[i++];
          final message = legErrorMessage(outcome, entry.key.timings);
          if (message != null) bad.add('${entry.key.name}: $message');
        }
        if (bad.isNotEmpty) {
          error = bad.join('; ');
          break;
        }
        if (outcomes.any((o) => o == LegOutcome.stopped)) break;

        legs++;
        if (maxLegs > 0 && legs >= maxLegs) break;
        slot = slot == slotA ? slotB : slotA;

        if (dwell > Duration.zero) {
          for (final m in members) {
            _phases[m.name] = PingPongPhase.dwelling;
          }
          _emit(FleetStatus(
            phase: PingPongPhase.dwelling,
            slot: slot,
            legs: legs,
            memberPhases: Map.of(_phases),
          ));
          if (!await supervisors.values.first.sleep(dwell)) break;
        }
      }
    } catch (e) {
      error = '$e';
    } finally {
      _running = false;
      // Always stop every device, on every exit path.
      await stopAll();
      for (final m in members) {
        _phases[m.name] = PingPongPhase.stopped;
      }
      _emit(FleetStatus(
        phase: error == null ? PingPongPhase.stopped : PingPongPhase.failed,
        slot: slot,
        legs: legs,
        error: error,
        memberPhases: Map.of(_phases),
      ));
    }
  }

  /// The least-finished member's phase, so the fleet reads as "still moving"
  /// while any device is.
  PingPongPhase _aggregate() {
    const order = [
      PingPongPhase.commanding,
      PingPongPhase.moving,
      PingPongPhase.timing,
      PingPongPhase.settling,
      PingPongPhase.dwelling,
      PingPongPhase.stopped,
    ];
    PingPongPhase worst = PingPongPhase.stopped;
    for (final p in _phases.values) {
      final a = order.indexOf(p);
      final b = order.indexOf(worst);
      if (a >= 0 && (b < 0 || a < b)) worst = p;
    }
    return worst;
  }

  void _emit(FleetStatus s) {
    _status = s;
    if (!_statuses.isClosed) _statuses.add(s);
  }
}
