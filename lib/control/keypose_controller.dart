/// Keyposes across every connected device.
///
/// A keypose here is "slot N on all devices". The official app pairs the units
/// and captures both axes into a single combined keypose, but that path was
/// never captured (§8), so this reproduces the *behaviour* with ordinary,
/// verified per-device save and recall commands rather than the combined one.
///
/// Only the slider contributes a position. The head reports none at all (§5),
/// so a keypose records where the *slider* was and nothing about the head's
/// angle — there is no way to know it and no way to fabricate it that would not
/// silently drift.
library;

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../ble/ek_connection.dart';
import '../ek_protocol.dart';
import 'homing.dart';
import 'motion_settings.dart';
import 'move_timing.dart';
import 'pose_store.dart';
import 'sync_move.dart';

class KeyposeController {
  KeyposeController({required this.devices, required this.settingsFor});

  final List<EkConnection> devices;

  /// Motion settings per device kind, owned by the page.
  final MotionSettings Function(EkKind kind) settingsFor;

  static const _key = 'keyposes_v1';
  static const _timingKey = 'move_timing_v1';
  static const _datumKey = 'rail_datum_v1';

  PoseSet poses = PoseSet.initial();

  /// Set once the slider has been homed this session. Until then, poses record
  /// raw counts only, which are arbitrary and die with the session.
  RailDatum? datum;

  /// Calibration used to make both axes take the same time.
  MoveTiming timing = const MoveTiming();

  EkConnection? get slider {
    for (final d in devices) {
      if (d.kind == EkKind.slider) return d;
    }
    return null;
  }

  int? get sliderPosition => slider?.snapshot.position;

  bool get isHomed => datum != null;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Always unverified on load: the device may have been power-cycled since,
      // and nothing can read a pose back off it (§3).
      poses = PoseSet.decode(prefs.getString(_key)).asUnverified();
      timing = MoveTiming.decode(prefs.getString(_timingKey));
      _loadDatum(prefs.getStringList(_datumKey));
    } catch (_) {
      poses = PoseSet.initial();
      timing = const MoveTiming();
    }
  }

  /// Restores a datum from a previous run.
  ///
  /// The carriage is assumed not to have moved while the app was closed, so a
  /// datum survives a restart and is only replaced by homing again. That
  /// assumption is safe as long as the DEVICE stayed powered: the position
  /// counter restarts at an arbitrary value on power-up (§5), which would make
  /// a stored datum point at the wrong part of the rail.
  ///
  /// So the stored datum is checked against the live counter, and discarded if
  /// the carriage now reads somewhere the rail does not reach. That catches a
  /// power cycle without needing the device to tell us about one.
  void _loadDatum(List<String>? raw) {
    _unconfirmedDatum = raw;
    _applyStoredDatum();
  }

  /// A stored datum that has not yet been checked against the live counter.
  ///
  /// At load time telemetry has usually not arrived, so there is no position to
  /// check against and the datum is adopted provisionally. It stays here until
  /// a real position confirms or refutes it.
  List<String>? _unconfirmedDatum;

  /// Re-checks a restored datum once telemetry is flowing.
  ///
  /// Returns true if this call is what discovered the counter had been reset,
  /// so the caller can say so exactly once.
  bool revalidateDatum() {
    if (_unconfirmedDatum == null || sliderPosition == null) return false;
    final wasStale = datumStale;
    _applyStoredDatum();
    return datumStale && !wasStale;
  }

  void _applyStoredDatum() {
    final raw = _unconfirmedDatum;
    if (raw == null || raw.length < 3) return;
    final lo = int.tryParse(raw[0]);
    final hi = int.tryParse(raw[1]);
    final sign = int.tryParse(raw[2]);
    if (lo == null || hi == null || sign == null || hi <= lo) {
      _unconfirmedDatum = null;
      return;
    }

    final here = sliderPosition;
    if (here != null) {
      // One rail length of slack either side: enough for the counter to sit a
      // little outside the measured ends, nowhere near enough to hide a reset.
      final span = hi - lo;
      _unconfirmedDatum = null;
      if (here < lo - span || here > hi + span) {
        datum = null;
        datumStale = true;
        unawaited(_persistDatum());
        return;
      }
    }
    datum = RailDatum(endLo: lo, endHi: hi, velocitySign: sign);
  }

  /// True when a stored datum was discarded because the counter had clearly
  /// been reset — the device was power-cycled, so the rail must be re-homed.
  bool datumStale = false;

  /// True only when the current datum was measured by touching a real end stop
  /// during this run of the app.
  ///
  /// A remembered datum is good enough for the things that stay bounded by live
  /// telemetry — showing where a pose sits, steering a synced move — but it is
  /// worth distinguishing before anything drives the carriage on its authority.
  /// The position counter restarts at an arbitrary value on power-up (§5), and
  /// the range check that guards a remembered datum can only catch a reset that
  /// lands well outside the rail, not one that happens to land inside it.
  bool datumMeasuredThisSession = false;

  /// True when the datum came from a previous run and has not been re-measured.
  bool get datumIsRemembered => datum != null && !datumMeasuredThisSession;

  Future<void> _persistDatum() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final d = datum;
      if (d == null) {
        await prefs.remove(_datumKey);
        return;
      }
      await prefs.setStringList(_datumKey,
          ['${d.endLo}', '${d.endHi}', '${d.velocitySign}']);
    } catch (_) {
      // Losing the datum costs a re-home, not a failed command.
    }
  }

  Future<void> saveTiming(MoveTiming next) async {
    timing = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_timingKey, next.encode());
    } catch (_) {
      // Losing a calibration is not worth failing a motion command over.
    }
  }

  /// The motion settings to command for a recall of [slot] on [kind].
  ///
  /// With duration matching on, each axis is solved so that its move takes the
  /// configured shot duration — which is what makes them finish together. The
  /// acceleration percentage is carried across unchanged, since only the speed
  /// field governs how long the move takes.
  ///
  /// Falls back to the manual setting whenever the necessary calibration is
  /// missing, rather than pretending to a precision it does not have.
  MotionSettings solvedFor(EkKind kind, int slot) {
    final manual = settingsFor(kind);
    if (!timing.matchDurations) return manual;

    final solved = solveMove(kind, slot);
    if (solved == null) return manual;
    return manual.copyWith(speedPercent: solved.percent);
  }

  /// The solved move for [kind] to [slot], or null when it cannot be computed.
  SolvedMove? solveMove(EkKind kind, int slot) {
    if (kind == EkKind.slider) {
      final t = timing.slider;
      final here = sliderPosition;
      final target = poses.bySlot(slot)?.counts;
      if (t == null || here == null || target == null) return null;
      return t.solve(target - here, timing.shot);
    }

    final h = timing.head;
    if (h == null) return null;
    // The calibration is only valid for the poses it was timed between (§5).
    if (!h.appliesTo(poses.saved.map((p) => p.slot).toList())) return null;
    // Solved against the time left after the head's start delay, so holding it
    // back does not also make it finish late.
    return h.solve(timing.headSolveTarget);
  }

  /// Learns the slider's rate from a completed move, so later moves can be
  /// solved for a duration. Returns true if the observation was usable.
  Future<bool> learnSliderMove({
    required int counts,
    required Duration duration,
    required double percent,
  }) async {
    final learned = SliderTiming.fromObservation(
      counts: counts,
      duration: duration,
      percent: percent,
    );
    if (learned == null) return false;
    await saveTiming(timing.copyWith(slider: learned));
    return true;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, poses.encode());
    } catch (_) {
      // Losing a preference is not worth failing a motion command over.
    }
  }

  /// Saves the current position of every device into [slot].
  ///
  /// The frame carries no position — it means "store wherever you are right
  /// now" (§3) — so this is only ever a snapshot of the present.
  Future<List<String>> save(int slot) async {
    final failures = <String>[];
    for (final d in devices) {
      try {
        await d.savePose(slot);
      } catch (e) {
        failures.add('${_name(d)}: $e');
      }
    }

    final counts = sliderPosition;
    poses = poses.withSaved(
      slot,
      counts: counts,
      // Only meaningful once homed; a fraction is what survives a power cycle.
      fraction: (counts != null && datum != null)
          ? datum!.countsToFraction(counts)
          : null,
    );
    await _persist();
    return failures;
  }

  Future<List<String>> recall(int slot) async {
    final failures = <String>[];
    await Future.wait(devices.map((d) async {
      try {
        await d.recallPose(slot, settings: solvedFor(d.kind, slot));
      } catch (e) {
        failures.add('${_name(d)}: $e');
      }
    }));
    return failures;
  }

  /// Where the carriage should end up for [slot], in this session's counts.
  ///
  /// A fraction of measured travel is preferred over stored raw counts whenever
  /// both exist: the fraction is the part that stays true across a power cycle,
  /// while raw counts are only meaningful within the session that recorded them
  /// (§5).
  int? sliderTargetFor(int slot) {
    final pose = poses.bySlot(slot);
    if (pose == null) return null;
    final d = datum;
    final f = pose.fraction;
    if (d != null && f != null) return d.clampSoft(d.fractionToCounts(f));
    return pose.counts;
  }

  /// Whether a synchronised leg to [slot] is possible.
  ///
  /// It needs a slider position to close the loop against and a target to close
  /// it toward. Without both, the only honest option is an ordinary recall on
  /// every device, with no duration guarantee.
  bool canSync(int slot) =>
      slider != null &&
      sliderPosition != null &&
      sliderTargetFor(slot) != null;

  /// The axes for one synchronised leg to [slot].
  ///
  /// Rebuilt for every leg, because the slider's velocity profile is computed
  /// from wherever the carriage is *now*, not from where it was when the loop
  /// started.
  ///
  /// The slider is velocity-driven closed loop. Every other device — in
  /// practice the head — gets its own pose recall, started and stopped on the
  /// same clock, because nothing here can know how far its axis has to travel
  /// (§5).
  List<SyncAxis> syncAxesFor(int slot) {
    final axes = <SyncAxis>[];
    for (final d in devices) {
      if (!d.snapshot.isReady) continue;
      final manual = settingsFor(d.kind);
      final ramp = syncRampForAccel(manual.accelPercent);
      final target = d.kind == EkKind.slider ? sliderTargetFor(slot) : null;
      if (d.kind == EkKind.slider &&
          target != null &&
          d.snapshot.position != null) {
        axes.add(SliderSyncAxis(
          target: d,
          targetCounts: target,
          name: _name(d),
          velocitySign: datum?.velocitySign ?? 1,
          // The Speed slider sets the ceiling, exactly as it does for jogging —
          // it is the same streamed-velocity command underneath (§4).
          maxVelocity: manual.jogVelocity(),
          ramp: ramp,
        ));
      } else {
        axes.add(PoseRecallSyncAxis(
          target: d,
          slot: slot,
          // Solved, not manual. A recall issued at the manual speed finishes
          // whenever it finishes — for the head that is about a second — and
          // then sits still for the rest of the leg while the slider is still
          // moving. Starting and stopping together is not worth much if one
          // axis spends most of the shot stationary.
          settings: solvedFor(d.kind, slot),
          name: _name(d),
          startDelay: d.kind == EkKind.head ? timing.headDelay : Duration.zero,
        ));
      }
    }
    return axes;
  }

  /// Recalls [slot] with both axes moving on one clock.
  ///
  /// Returns null on success, or the reason it did not complete. Falls back to
  /// nothing: callers check [canSync] first and use [recall] otherwise, so a
  /// missing calibration degrades to an ordinary recall rather than to a move
  /// that claims a duration it cannot keep.
  Future<String?> recallSynced(
    int slot, {
    required bool Function() stillRunning,
    void Function(SyncProgress)? onProgress,
  }) async {
    final move = SyncMove(
      axes: syncAxesFor(slot),
      stillRunning: stillRunning,
      onProgress: onProgress,
    );
    final min = move.minimumDuration;
    final want = timing.shot;
    switch (await move.run(min > want ? min : want)) {
      case SyncOutcome.done:
      case SyncOutcome.stopped:
        return null;
      case SyncOutcome.linkLost:
        return 'link lost mid-move';
      case SyncOutcome.failed:
        return 'a device would not take the command';
    }
  }

  /// How long a synchronised leg to [slot] will really take.
  ///
  /// Equal to the shot duration unless the slider physically cannot cover the
  /// distance that fast, in which case the move is extended rather than being
  /// allowed to arrive short.
  Duration effectiveLeg(int slot) {
    final min =
        SyncMove(axes: syncAxesFor(slot), stillRunning: () => true)
            .minimumDuration;
    final want = timing.shot;
    return min > want ? min : want;
  }

  /// Forgets the app's record of a slot.
  ///
  /// There is no clear-a-pose command in the captures, so the device keeps
  /// whatever it had. This only clears what the app knows — which is why the UI
  /// asks first.
  Future<void> clear(int slot) async {
    poses = poses.withCleared(slot);
    await _persist();
  }

  Future<void> rename(int slot, String name) async {
    poses = poses.withName(slot, name);
    await _persist();
  }

  Future<int?> addSlot() async {
    final before = poses.poses.map((p) => p.slot).toSet();
    poses = poses.withNewSlot();
    await _persist();
    for (final p in poses.poses) {
      if (!before.contains(p.slot)) return p.slot;
    }
    return null;
  }

  Future<void> removeSlot(int slot) async {
    poses = poses.withoutSlot(slot);
    await _persist();
  }

  void markUnverified() {
    poses = poses.asUnverified();
  }

  /// Records the datum and converts any pose saved this session into a
  /// fraction, so it becomes restorable.
  Future<void> setDatum(RailDatum d) async {
    datum = d;
    datumStale = false;
    datumMeasuredThisSession = true;
    // A freshly measured datum outranks anything stored from a previous run.
    _unconfirmedDatum = null;
    await _persistDatum();
    poses = PoseSet([
      for (final p in poses.poses)
        p.counts != null && p.fraction == null
            ? p.copyWith(fraction: d.countsToFraction(p.counts!))
            : p,
    ]);
    await _persist();
  }

  /// Poses that can be re-established after a power cycle.
  List<Pose> get restorable =>
      poses.poses.where((p) => p.isRestorable).toList();

  String _name(EkConnection d) => d.name.isEmpty ? d.profile.name : d.name;
}
