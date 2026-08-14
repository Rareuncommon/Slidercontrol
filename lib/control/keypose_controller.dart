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
import 'pose_store.dart';

class KeyposeController {
  KeyposeController({required this.devices, required this.settingsFor});

  final List<EkConnection> devices;

  /// Motion settings per device kind, owned by the page.
  final MotionSettings Function(EkKind kind) settingsFor;

  static const _key = 'keyposes_v1';

  PoseSet poses = PoseSet.initial();

  /// Set once the slider has been homed this session. Until then, poses record
  /// raw counts only, which are arbitrary and die with the session.
  RailDatum? datum;

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
    } catch (_) {
      poses = PoseSet.initial();
    }
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
        await d.recallPose(slot, settings: settingsFor(d.kind));
      } catch (e) {
        failures.add('${_name(d)}: $e');
      }
    }));
    return failures;
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
