/// The control page: one screen, nothing to scroll.
///
/// Live position, a jog pad per axis, the stored poses as large tiles, the
/// move style, loop, and STOP ALL. Every pose here is stored ON THE HEAD and
/// holds every axis of the layout; recalling one, the head plans the move so
/// all axes arrive together.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/flutter_support.dart';
import '../app/rig_controller.dart';
import '../sdk/motion/pose.dart';
import '../sdk/protocol/generated/moco.dart';
import 'jog_pad.dart';
import 'ui_scale.dart';

class RigPage extends StatefulWidget {
  const RigPage({super.key, required this.controller});
  final RigController controller;

  @override
  State<RigPage> createState() => _RigPageState();
}

class _RigPageState extends State<RigPage> {
  RigController get c => widget.controller;
  late final StreamSubscription<void> _sub;
  Duration _dwell = Duration.zero;

  @override
  void initState() {
    super.initState();
    _sub = c.changes.listen((_) {
      if (!mounted) return;
      if (c.phase == RigPhase.idle) {
        Navigator.of(context).maybePop();
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }

  Future<void> _leave() async {
    await c.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final status = c.status;
    final lost = c.phase == RigPhase.lost;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _StatusStrip(c: c, onLog: _showLog, onLeave: _leave),
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: ErrorBanner(c.error!, onDismiss: c.clearError),
                ),
              if (lost)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: FilledButton.icon(
                    onPressed: c.reconnect,
                    icon: const Icon(Icons.bluetooth_searching),
                    label: const Text('Reconnect'),
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final pads = _Pads(c: c, enabled: !lost && status?.hasFocusMotor != true);
                    final grid = _PoseGrid(c: c, enabled: !lost, columns: box.maxWidth > box.maxHeight * 1.3 ? 3 : 4);
                    // Wide and short — a phone on its side, a laptop window —
                    // puts the pads beside the poses instead of above them.
                    if (box.maxWidth > box.maxHeight * 1.3) {
                      return Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              children: [
                                _Positions(c: c),
                                Expanded(child: pads),
                              ],
                            ),
                          ),
                          Expanded(flex: 6, child: grid),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        _Positions(c: c),
                        Expanded(flex: 4, child: pads),
                        Expanded(flex: 5, child: grid),
                      ],
                    );
                  },
                ),
              ),
              _Style(c: c),
              _Actions(c: c, dwell: _dwell, onDwell: (d) => setState(() => _dwell = d), enabled: !lost),
            ],
          ),
        ),
      ),
    );
  }

  void _showLog() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              ListTile(
                title: const Text('SDK log'),
                subtitle: const Text('What the SDK port did and decided. Paste it when something misbehaves.'),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy',
                  onPressed: () => Clipboard.setData(ClipboardData(text: LogBuffer.instance.text)),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  reverse: true,
                  children: [
                    for (final l in LogBuffer.instance.lines.reversed)
                      Text(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.c, required this.onLog, required this.onLeave});
  final RigController c;
  final VoidCallback onLog;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = c.device;
    final s = c.status;
    final info = d?.info;
    final layout = s?.layout;
    final parts = <String>[
      if (info != null) info.name,
      if (c.modules.isNotEmpty) '+ ${c.modules.join(', ')}',
      if (layout != null && layout != EdlSetup.NONE) layout.name.toLowerCase().replaceAll('_', ' '),
      if (s?.batteryPercent != null) 'battery ${s!.batteryPercent!.round()}%',
      if (c.looping) 'looping' else if (c.moving) 'moving' else if (s?.isMoving == true) 'moving' else 'idle',
    ];
    final warnings = <String>[
      if (info != null && !info.firmwareOk) 'firmware below the SDK minimum — update with the edelkrone app',
      if (s?.modulesResponding == false) 'the slider is not answering the head',
      if (s?.orientationWarning == true) 'orientation warning',
      if (s?.hasFocusMotor == true) 'focus motor fitted: motion refused until the lens is learned (edelkrone app)',
    ];
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      child: Row(
        children: [
          Icon(
            c.phase == RigPhase.lost ? Icons.link_off : Icons.circle,
            size: 10,
            color: c.phase == RigPhase.lost ? Colors.orange : Colors.green,
          ),
          Gap.wSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(parts.join(' · '), style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                if (warnings.isNotEmpty)
                  Text(
                    warnings.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'SDK log',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.receipt_long),
            onPressed: onLog,
          ),
          IconButton(
            tooltip: 'Disconnect (stops first)',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.logout),
            onPressed: onLeave,
          ),
        ],
      ),
    );
  }
}

/// Live position in real units. The slide also gets a track, from the
/// fraction of travel the slider reports once it has referenced itself.
class _Positions extends StatelessWidget {
  const _Positions({required this.c});
  final RigController c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = c.status;
    final pose = s?.pose ?? RigPose.unknown;
    final axes = c.axes;
    String v(RigAxis a) {
      final x = pose[a];
      return x == null ? '—' : a.format(x);
    }

    final fraction = s?.slideFraction;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              for (final a in [RigAxis.pan, RigAxis.tilt, RigAxis.slide])
                if (axes.contains(a))
                  Expanded(
                    child: Column(
                      children: [
                        Text(a.label, style: theme.textTheme.labelSmall),
                        Text(
                          v(a),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
          if (axes.contains(RigAxis.slide)) ...[
            Gap.xs,
            _SlideTrack(fraction: fraction, poses: c.poses, calibrated: s?.isCalibrated),
          ],
          if (s?.moveProgress != null && (c.moving || c.looping) && s!.moveProgress! > 0 && s.moveProgress! <= 1)
            LinearProgressIndicator(value: s.moveProgress),
        ],
      ),
    );
  }
}

class _SlideTrack extends StatelessWidget {
  const _SlideTrack({required this.fraction, required this.poses, required this.calibrated});
  final double? fraction;
  final Map<int, RigPose> poses;
  final bool? calibrated;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (fraction == null) {
      return Text(
        calibrated == false ? 'The slider has not referenced its travel yet.' : '',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return SizedBox(
      height: 10,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            Positioned(
              left: (box.maxWidth - 10) * fraction!.clamp(0.0, 1.0),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pads extends StatelessWidget {
  const _Pads({required this.c, required this.enabled});
  final RigController c;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final axes = c.axes;
    final pads = [
      if (axes.contains(RigAxis.pan)) RigAxis.pan,
      if (axes.contains(RigAxis.tilt)) RigAxis.tilt,
      if (axes.contains(RigAxis.slide)) RigAxis.slide,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          for (final a in pads)
            Expanded(
              child: JogPad(
                label: a.label,
                enabled: enabled && c.device != null,
                disabledNote: c.phase == RigPhase.lost ? 'link lost' : 'unavailable',
                readout: c.jogging ? 'driving' : 'hold and drag',
                onVelocity: (f) => c.hold(a, f),
                onRelease: () => c.release(a),
              ),
            ),
        ],
      ),
    );
  }
}

class _PoseGrid extends StatelessWidget {
  const _PoseGrid({required this.c, required this.enabled, this.columns = 4});
  final RigController c;
  final bool enabled;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final stored = c.stored.toSet();
    final next = c.nextSlot;
    final shown = <int>{...stored, ?next}.toList()..sort();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Row(
            children: [
              Text('KEYPOSES', style: Theme.of(context).textTheme.labelSmall),
              Gap.wSm,
              Expanded(
                child: Text(
                  c.isJoined ? 'each holds both axes · tap to go · hold to edit' : 'tap to go · hold to edit',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Gap.xs,
          Expanded(
            child: GridView.count(
              crossAxisCount: columns,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.35,
              children: [
                for (final slot in shown)
                  _PoseTile(
                    slot: slot,
                    name: c.names[slot],
                    pose: c.poses[slot],
                    isStored: stored.contains(slot),
                    active: c.activeSlot == slot && (c.moving || c.looping),
                    loopEnd: c.looping && c.loopEnds != null && (c.loopEnds!.$1 == slot || c.loopEnds!.$2 == slot),
                    enabled: enabled,
                    onTap: () => stored.contains(slot) ? c.recall(slot) : _save(context, slot),
                    onLongPress: stored.contains(slot) ? () => _edit(context, slot) : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context, int slot) async {
    final name = await _askName(context, 'Save the current position as pose ${slot + 1}', '');
    if (name == null) return;
    await c.save(slot, name: name);
  }

  Future<void> _edit(BuildContext context, int slot) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(c.names[slot] ?? 'Pose ${slot + 1}'), subtitle: Text(_describe(c.poses[slot]))),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('Replace with the current position'),
              onTap: () => Navigator.pop(context, 'resave'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete from the head'),
              subtitle: const Text(
                'A head moves through every pose in between and stops at an empty slot, '
                'so deleting one in the middle breaks moves across it.',
              ),
              onTap: () => Navigator.pop(context, 'clear'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'rename':
        final name = await _askName(context, 'Rename pose ${slot + 1}', c.names[slot] ?? '');
        if (name != null) await c.rename(slot, name);
      case 'resave':
        await c.save(slot);
      case 'clear':
        await c.clear(slot);
    }
  }

  Future<String?> _askName(BuildContext context, String title, String initial) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name (optional), e.g. wide'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctl.text), child: const Text('Save')),
        ],
      ),
    );
  }
}

String _describe(RigPose? p) {
  if (p == null) return 'position not read';
  return [
    for (final a in [RigAxis.pan, RigAxis.tilt, RigAxis.slide])
      if (p[a] != null) '${a.label} ${a.format(p[a]!)}',
  ].join(' · ');
}

class _PoseTile extends StatelessWidget {
  const _PoseTile({
    required this.slot,
    required this.name,
    required this.pose,
    required this.isStored,
    required this.active,
    required this.loopEnd,
    required this.enabled,
    required this.onTap,
    this.onLongPress,
  });

  final int slot;
  final String? name;
  final RigPose? pose;
  final bool isStored;
  final bool active;
  final bool loopEnd;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = !isStored
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.35)
        : active
        ? scheme.primary
        : scheme.primaryContainer;
    final fg = !isStored ? scheme.onSurfaceVariant : (active ? scheme.onPrimary : scheme.onPrimaryContainer);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        child: Container(
          decoration: loopEnd
              ? BoxDecoration(
                  border: Border.all(color: scheme.tertiary, width: 2),
                  borderRadius: BorderRadius.circular(10),
                )
              : null,
          padding: const EdgeInsets.all(6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isStored) ...[
                  Text(
                    '${slot + 1}',
                    style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  if (name != null)
                    Text(
                      name!,
                      style: TextStyle(color: fg, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      _describe(pose),
                      style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 9),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ] else ...[
                  Icon(Icons.add, color: fg),
                  Text('save as ${slot + 1}', style: TextStyle(color: fg, fontSize: 11)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Style extends StatelessWidget {
  const _Style({required this.c});
  final RigController c;

  @override
  Widget build(BuildContext context) {
    Widget bar(String label, double value, double min, ValueChanged<double> on, String shown) => Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label · $shown', style: Theme.of(context).textTheme.labelSmall),
          Slider(value: value, min: min, max: 1, onChanged: on),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          bar('SPEED', c.speed, 0.01, (v) {
            c.speed = v;
            c.clearError();
          }, '${(c.speed * 100).round()}%'),
          bar('ACCEL', c.acceleration, 0.0, (v) {
            c.acceleration = v;
            c.clearError();
          }, '${(c.acceleration * 100).round()}% of the move'),
          bar('JOG', c.jogSpeed, 0.05, (v) {
            c.jogSpeed = v;
            c.clearError();
          }, '${(c.jogSpeed * 100).round()}%'),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.c, required this.dwell, required this.onDwell, required this.enabled});
  final RigController c;
  final Duration dwell;
  final ValueChanged<Duration> onDwell;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final stored = c.stored;
    final canLoop = stored.length >= 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: c.looping
                ? FilledButton.tonalIcon(
                    onPressed: c.stopLoop,
                    icon: const Icon(Icons.stop),
                    label: const Text('STOP LOOP'),
                  )
                : FilledButton.tonalIcon(
                    onPressed: enabled && canLoop ? () => _chooseLoop(context) : null,
                    icon: const Icon(Icons.repeat),
                    label: Text(canLoop ? 'LOOP' : 'LOOP · save 2 poses'),
                  ),
          ),
          Gap.wSm,
          Expanded(
            flex: 4,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: c.stopAll,
              icon: const Icon(Icons.stop_circle),
              label: const Text('STOP ALL · Esc', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseLoop(BuildContext context) async {
    final stored = c.stored;
    var a = stored.first;
    var b = stored.last;
    var d = dwell;
    final go = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => SafeArea(
          child: Padding(
            padding: Insets.page,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Loop', style: Theme.of(context).textTheme.titleLarge),
                Gap.sm,
                Row(
                  children: [
                    const Text('Between pose '),
                    DropdownButton<int>(
                      value: a,
                      items: [for (final s in stored) DropdownMenuItem(value: s, child: Text('${s + 1}'))],
                      onChanged: (v) => set(() => a = v!),
                    ),
                    const Text('  and pose '),
                    DropdownButton<int>(
                      value: b,
                      items: [for (final s in stored) DropdownMenuItem(value: s, child: Text('${s + 1}'))],
                      onChanged: (v) => set(() => b = v!),
                    ),
                  ],
                ),
                LabelledSlider(
                  label: 'Pause at each end',
                  value: d.inMilliseconds / 1000,
                  min: 0,
                  max: 10,
                  display: d == Duration.zero ? 'none' : '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s',
                  onChanged: (v) => set(() => d = Duration(milliseconds: (v * 2).round() * 500)),
                ),
                Text(
                  d == Duration.zero
                      ? 'With no pause this is the head\'s own loop: one command it runs until stopped, '
                            'so it does not depend on this app between legs.'
                      : 'With a pause the app runs the loop, one verified recall per leg.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if ((a - b).abs() > 1)
                  Text(
                    'The head passes through every pose stored between ${a + 1} and ${b + 1} on the way.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                Gap.md,
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    Gap.wSm,
                    FilledButton(
                      onPressed: a == b ? null : () => Navigator.pop(context, true),
                      child: const Text('Start'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (go == true) {
      onDwell(d);
      unawaited(c.startLoop(a, b, dwell: d));
    }
  }
}
