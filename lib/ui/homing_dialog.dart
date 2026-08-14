/// Homing, and restoring poses after a power cycle.
///
/// Homing deliberately drives the carriage into a mechanical stop, and the
/// slider has no soft limits of its own (§7). So it is always an explicit,
/// confirmed action with visible progress and an abort — never something that
/// happens quietly on connect.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/ek_connection.dart';
import '../control/homing.dart';
import '../control/keypose_controller.dart';
import '../control/stop_registry.dart';
import 'ui_scale.dart';

enum HomingJob { home, restore }

class HomingDialog extends StatefulWidget {
  const HomingDialog({
    super.key,
    required this.slider,
    required this.keyposes,
    required this.job,
  });

  final EkConnection slider;
  final KeyposeController keyposes;
  final HomingJob job;

  @override
  State<HomingDialog> createState() => _HomingDialogState();
}

class _HomingDialogState extends State<HomingDialog> {
  bool _started = false;
  bool _running = false;
  bool _finished = false;
  String? _error;
  final _log = <String>[];

  bool get _isRestore => widget.job == HomingJob.restore;

  @override
  void dispose() {
    _running = false;
    StopRegistry.instance.unregister(this);
    super.dispose();
  }

  void _note(String message) {
    if (!mounted) return;
    setState(() {
      _log.add(message);
      if (_log.length > 40) _log.removeAt(0);
    });
  }

  Future<void> _run() async {
    setState(() {
      _started = true;
      _running = true;
      _error = null;
      _log.clear();
    });
    StopRegistry.instance.register(this, () async => _abort());

    final homing = Homing(
      target: widget.slider,
      stillRunning: () => _running,
      onProgress: (p) => _note(p.message),
    );
    try {
      final datum = await homing.homeBoth();
      await widget.keyposes.setDatum(datum);
      _note('Datum established: ${datum.travel} counts of travel.');

      if (_isRestore) {
        final restorable = widget.keyposes.restorable;
        if (restorable.isEmpty) {
          _note('No poses stored as a fraction of travel, so there is nothing '
              'to restore. Save some now that the rail is homed.');
        }
        for (final pose in restorable) {
          if (!_running) break;
          final target = datum.fractionToCounts(pose.fraction!);
          _note('Restoring slot ${pose.slot} at '
              '${(pose.fraction! * 100).toStringAsFixed(1)}% of travel…');
          final ok = await homing.moveTo(target, datum);
          if (!ok) {
            _note('Could not reach slot ${pose.slot}; skipping.');
            continue;
          }
          await widget.keyposes.save(pose.slot);
          _note('Slot ${pose.slot} re-taught.');
        }
      }

      if (mounted) setState(() => _finished = true);
      _note('Done.');
    } on HomingAborted catch (e) {
      if (mounted) setState(() => _error = e.reason);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _running = false;
      StopRegistry.instance.unregister(this);
      // Whatever happened, leave nothing moving.
      try {
        await widget.slider.stopMotion();
      } catch (_) {
        // Nothing further this layer can do.
      }
      if (mounted) setState(() {});
    }
  }

  void _abort() {
    setState(() => _running = false);
    _note('Aborting…');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(_isRestore ? 'Restore poses' : 'Home the slider'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_started) ...[
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: Insets.card,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber,
                            color: theme.colorScheme.onErrorContainer),
                        Gap.wSm,
                        Expanded(
                          child: Text(
                            'Take the camera off the rig first.\n\n'
                            'Homing drives the carriage into both mechanical '
                            'end stops on purpose — the slider has no soft '
                            'limits of its own (§7).',
                            style: TextStyle(
                                color: theme.colorScheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Gap.md,
                Text(
                  _isRestore
                      ? 'This homes the rail, then drives to each pose stored '
                          'as a fraction of travel and re-saves it. Poses die '
                          'at power-off and the save command carries no '
                          'position (§3), so the only way to restore one is to '
                          'physically move there and save.'
                      : 'This finds both mechanical ends and measures the '
                          'travel between them, which gives poses a datum they '
                          'can be expressed against.',
                  style: theme.textTheme.bodyMedium,
                ),
                Gap.sm,
                Text(
                  'Expect roughly 40–60 seconds, nearly all of it homing. Each '
                  'pass is bounded three ways — stall detection, a travel '
                  'budget, and a timeout — and aborts immediately if the link '
                  'drops.',
                  style: theme.textTheme.bodySmall,
                ),
                if (_isRestore) ...[
                  Gap.sm,
                  Text(
                    '${widget.keyposes.restorable.length} of '
                    '${widget.keyposes.poses.saved.length} saved poses can be '
                    'restored. Only poses saved while homed carry a fraction.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const Caution(
                  'The head is never homed. It has no end stops and reports no '
                  'position (§5), so its poses must be re-taught by hand each '
                  'session.',
                ),
              ] else ...[
                Row(
                  children: [
                    if (_running)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (_running) Gap.wSm,
                    Text(
                      _error != null
                          ? 'Aborted'
                          : _finished
                              ? 'Complete'
                              : 'Working…',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
                Gap.sm,
                Container(
                  height: 220,
                  width: double.infinity,
                  padding: Insets.card,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView(
                    reverse: true,
                    children: [
                      for (final line in _log.reversed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(line,
                              style: theme.textTheme.bodySmall),
                        ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  Gap.sm,
                  ErrorBanner(_error!),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (!_started) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _run,
            child: Text(_isRestore
                ? 'Camera is off — restore'
                : 'Camera is off — home'),
          ),
        ] else if (_running)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: _abort,
            icon: const Icon(Icons.stop_circle),
            label: const Text('Abort'),
          )
        else
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
      ],
    );
  }
}
