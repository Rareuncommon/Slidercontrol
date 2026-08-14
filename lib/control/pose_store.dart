/// Named keypose slots, persisted locally.
///
/// The device stores the poses; this stores what the app knows *about* them —
/// names, when they were saved, and where the slider was at the time.
///
/// Two protocol facts shape all of this (EDELKRONE_PROTOCOL.md §3):
///
///  1. **Poses are volatile.** They survive a BLE disconnect and a client
///     restart, but are lost when the device is powered off. Nothing can read
///     poses back off the device, so after a reconnect the app cannot know
///     whether a slot still holds anything. Slots are therefore marked
///     *unverified* rather than shown as definitely present.
///  2. **Save carries no position.** `07 07 <slot> 00 00 30 39` means "store
///     wherever you are right now". There is no upload-a-position command
///     anywhere in the captures, so a pose cannot be written back — the only
///     way to restore one is to physically move the carriage there and save.
///
/// Pure Dart, so the model and its persistence rules are unit-tested.
library;

import 'dart:convert';

class Pose {
  const Pose({
    required this.slot,
    this.name = '',
    this.counts,
    this.fraction,
    this.savedAt,
    this.savedThisSession = false,
  });

  final int slot;

  /// Free text — "wide", "tight". Empty means unnamed.
  final String name;

  /// Unwrapped slider position at the moment of save. Null for the head, which
  /// reports no position at all (§5), and null for an empty slot.
  ///
  /// Arbitrary per session: meaningful only relative to other poses and to the
  /// current position, unless the app has homed.
  final int? counts;

  /// Position as a fraction of measured travel, recorded only if the rail had
  /// been homed when this pose was saved.
  ///
  /// This is the part that survives a power cycle. Raw counts do not: the
  /// counter restarts arbitrarily, so a stored count means nothing next
  /// session, while a fraction of travel still does.
  final double? fraction;

  final DateTime? savedAt;

  /// True only if this slot was written during the current connection.
  ///
  /// Not persisted. After a reconnect every slot reverts to unverified, because
  /// the device may have been power-cycled in between and there is no way to
  /// ask it.
  final bool savedThisSession;

  bool get isEmpty => savedAt == null;
  bool get isSet => !isEmpty;

  /// Whether the device is known to still hold this pose.
  bool get isVerified => isSet && savedThisSession;

  /// Whether this pose can be re-established after a power cycle.
  bool get isRestorable => fraction != null;

  Pose copyWith({
    String? name,
    int? counts,
    double? fraction,
    DateTime? savedAt,
    bool? savedThisSession,
    bool clearCounts = false,
    bool clearFraction = false,
  }) {
    return Pose(
      slot: slot,
      name: name ?? this.name,
      counts: clearCounts ? null : (counts ?? this.counts),
      fraction: clearFraction ? null : (fraction ?? this.fraction),
      savedAt: savedAt ?? this.savedAt,
      savedThisSession: savedThisSession ?? this.savedThisSession,
    );
  }

  /// An empty slot, keeping the name so clearing does not lose the label.
  Pose cleared() => Pose(slot: slot, name: name);

  Map<String, Object?> toJson() => {
        'slot': slot,
        'name': name,
        'counts': counts,
        'fraction': fraction,
        'savedAt': savedAt?.millisecondsSinceEpoch,
      };

  factory Pose.fromJson(Map<String, Object?> j) {
    final savedAt = j['savedAt'];
    return Pose(
      slot: switch (j['slot']) {
        final int v => v,
        final num v => v.toInt(),
        _ => 0,
      },
      name: j['name'] is String ? j['name']! as String : '',
      counts: switch (j['counts']) {
        final int v => v,
        final num v => v.toInt(),
        _ => null,
      },
      fraction: switch (j['fraction']) {
        final num v when v.isFinite => v.toDouble().clamp(0.0, 1.0),
        _ => null,
      },
      savedAt: savedAt is num
          ? DateTime.fromMillisecondsSinceEpoch(savedAt.toInt())
          : null,
      // Never restored from disk: a loaded pose is by definition from a
      // previous session.
      savedThisSession: false,
    );
  }
}

/// The set of slots for one device.
class PoseSet {
  const PoseSet(this.poses);

  final List<Pose> poses;

  /// Two slots to begin with, matching what the captures cover.
  factory PoseSet.initial() =>
      PoseSet([const Pose(slot: 0), const Pose(slot: 1)]);

  int get length => poses.length;

  Pose? bySlot(int slot) {
    for (final p in poses) {
      if (p.slot == slot) return p;
    }
    return null;
  }

  List<Pose> get saved => poses.where((p) => p.isSet).toList();

  PoseSet _replaced(Pose updated) => PoseSet([
        for (final p in poses) p.slot == updated.slot ? updated : p,
      ]);

  PoseSet withSaved(
    int slot, {
    int? counts,
    double? fraction,
    DateTime? at,
  }) {
    final existing = bySlot(slot);
    if (existing == null) return this;
    return _replaced(existing.copyWith(
      counts: counts,
      fraction: fraction,
      savedAt: at ?? DateTime.now(),
      savedThisSession: true,
      clearCounts: counts == null,
      clearFraction: fraction == null,
    ));
  }

  PoseSet withCleared(int slot) {
    final existing = bySlot(slot);
    if (existing == null) return this;
    return _replaced(existing.cleared());
  }

  PoseSet withName(int slot, String name) {
    final existing = bySlot(slot);
    if (existing == null) return this;
    return _replaced(existing.copyWith(name: name));
  }

  /// Adds the next free slot number.
  ///
  /// Slots beyond 0 and 1 are used because the hardware was confirmed to accept
  /// them. The slot is a single payload byte, so 0–255 is the encoding limit.
  PoseSet withNewSlot() {
    var next = 0;
    final used = poses.map((p) => p.slot).toSet();
    while (used.contains(next)) {
      next++;
    }
    if (next > 255) return this;
    return PoseSet([...poses, Pose(slot: next)]..sort(_bySlot));
  }

  PoseSet withoutSlot(int slot) {
    if (poses.length <= 1) return this;
    return PoseSet(poses.where((p) => p.slot != slot).toList());
  }

  /// Marks every slot unverified — call on (re)connect.
  ///
  /// The device may have been power-cycled since the last session, and there is
  /// no command that reads a pose back, so "saved earlier" cannot be upgraded
  /// to "still there" by anything except saving again.
  PoseSet asUnverified() =>
      PoseSet([for (final p in poses) p.copyWith(savedThisSession: false)]);

  static int _bySlot(Pose a, Pose b) => a.slot.compareTo(b.slot);

  String encode() => jsonEncode([for (final p in poses) p.toJson()]);

  static PoseSet decode(String? raw) {
    if (raw == null || raw.isEmpty) return PoseSet.initial();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return PoseSet.initial();
      final poses = <Pose>[];
      for (final entry in decoded) {
        if (entry is Map<String, Object?>) poses.add(Pose.fromJson(entry));
      }
      if (poses.isEmpty) return PoseSet.initial();
      poses.sort(_bySlot);
      return PoseSet(poses);
    } catch (_) {
      // A corrupt store must not stop the app talking to a motor.
      return PoseSet.initial();
    }
  }
}
