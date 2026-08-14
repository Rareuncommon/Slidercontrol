/// Keypose tiles, and the slider's position track.
library;

import 'package:flutter/material.dart';

import '../control/pose_store.dart';

/// Big tap-to-recall tiles, with a trailing tile that stores a new keypose.
class KeyposeTiles extends StatelessWidget {
  const KeyposeTiles({
    super.key,
    required this.poses,
    required this.enabled,
    required this.activeSlot,
    required this.onRecall,
    required this.onSaveNew,
    required this.onEdit,
  });

  final PoseSet poses;
  final bool enabled;

  /// The slot most recently commanded, highlighted.
  final int? activeSlot;

  final void Function(int slot) onRecall;
  final VoidCallback onSaveNew;

  /// Long-press / right-click: save over, rename, clear, remove.
  final void Function(int slot) onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        for (final pose in poses.poses)
          Expanded(
            child: _Tile(
              pose: pose,
              active: pose.slot == activeSlot,
              enabled: enabled,
              onTap: pose.isEmpty ? () => onEdit(pose.slot) : () => onRecall(pose.slot),
              onLongPress: () => onEdit(pose.slot),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Material(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: InkWell(
                onTap: enabled ? onSaveNew : null,
                child: Center(
                  child: Icon(Icons.add,
                      size: 36,
                      color: enabled
                          ? scheme.onSurfaceVariant
                          : scheme.outlineVariant),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.pose,
    required this.active,
    required this.enabled,
    required this.onTap,
    required this.onLongPress,
  });

  final Pose pose;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Color background;
    if (pose.isEmpty) {
      background = scheme.surfaceContainerHighest.withValues(alpha: 0.35);
    } else if (active) {
      background = scheme.primary;
    } else {
      background = scheme.primaryContainer;
    }

    final foreground = pose.isEmpty
        ? scheme.onSurfaceVariant
        : (active ? scheme.onPrimary : scheme.onPrimaryContainer);

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: enabled ? background : background.withValues(alpha: 0.4),
        child: InkWell(
          onTap: enabled ? onTap : null,
          onLongPress: enabled ? onLongPress : null,
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pose.name.isNotEmpty ? pose.name : '${pose.slot + 1}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: pose.name.isNotEmpty ? 20 : 34,
                        fontWeight: FontWeight.w500,
                        color: foreground,
                      ),
                    ),
                    if (pose.isEmpty)
                      Text('empty',
                          style: TextStyle(fontSize: 11, color: foreground)),
                  ],
                ),
              ),
              // Unverified: recorded earlier, but the device may have been
              // powered off since and nothing can read a pose back (§3).
              if (pose.isSet && !pose.isVerified)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Tooltip(
                    message: 'Saved in an earlier session. Poses are lost at '
                        'power-off and cannot be read back (§3), so this may no '
                        'longer be on the device.',
                    child: Icon(Icons.help_outline, size: 16, color: foreground),
                  ),
                ),
              if (pose.isRestorable)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Tooltip(
                    message: 'Stored as a fraction of measured travel, so it '
                        'can be re-established after a power cycle.',
                    child: Icon(Icons.anchor, size: 14, color: foreground),
                  ),
                ),
              Positioned(
                top: 6,
                left: 8,
                child: Text('slot ${pose.slot}',
                    style: TextStyle(
                        fontSize: 10,
                        color: foreground.withValues(alpha: 0.7))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The slider's position, with each saved pose marked.
///
/// Deliberately relative. The counter is arbitrary per session and has no fixed
/// relationship to the physical rail (§5) unless the app has homed, so until it
/// has, this shows where the poses sit relative to each other and to the
/// carriage — not where they are on the rail.
class PoseTrack extends StatelessWidget {
  const PoseTrack({
    super.key,
    required this.poses,
    required this.position,
    required this.homed,
    this.endLo,
    this.endHi,
  });

  final PoseSet poses;
  final int? position;
  final bool homed;
  final int? endLo;
  final int? endHi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final marks = <int>[
      for (final p in poses.poses)
        if (p.counts != null) p.counts!,
      ?position,
    ];
    if (marks.isEmpty) {
      return Text(
        'No slider position yet.',
        style: theme.textTheme.bodySmall,
      );
    }

    // Homed: the real rail. Otherwise a window spanning what we have seen, with
    // padding so a mark never sits on the edge.
    late final int lo;
    late final int hi;
    if (homed && endLo != null && endHi != null) {
      lo = endLo!;
      hi = endHi!;
    } else {
      final min = marks.reduce((a, b) => a < b ? a : b);
      final max = marks.reduce((a, b) => a > b ? a : b);
      final pad = ((max - min) * 0.15).round().clamp(500, 1 << 30);
      lo = min - pad;
      hi = max + pad;
    }
    final span = (hi - lo) == 0 ? 1 : (hi - lo);

    double at(int counts) => ((counts - lo) / span).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 30,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return Stack(
                children: [
                  Positioned(
                    top: 14,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  for (final p in poses.poses)
                    if (p.counts != null)
                      Positioned(
                        left: (at(p.counts!) * w).clamp(0.0, w - 2),
                        top: 6,
                        child: Container(
                          width: 2,
                          height: 19,
                          color: scheme.primary,
                        ),
                      ),
                  for (final p in poses.poses)
                    if (p.counts != null)
                      Positioned(
                        left: (at(p.counts!) * w - 6).clamp(0.0, w - 12),
                        top: 0,
                        child: Text(
                          p.name.isNotEmpty ? p.name[0] : '${p.slot + 1}',
                          style: TextStyle(
                              fontSize: 9, color: scheme.primary),
                        ),
                      ),
                  if (position != null)
                    Positioned(
                      left: (at(position!) * w - 5).clamp(0.0, w - 10),
                      top: 9,
                      child: Container(
                        width: 10,
                        height: 13,
                        decoration: BoxDecoration(
                          color: scheme.tertiary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        Text(
          homed
              ? 'Rail position, referenced to the homed datum.'
              : 'Relative only — the counter is arbitrary per session and is '
                  'not tied to the rail until you home (§5).',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
