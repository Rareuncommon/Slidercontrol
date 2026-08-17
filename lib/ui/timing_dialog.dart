/// Timing calibration, so both axes take the same time to complete a move.
///
/// The slider can be measured automatically: it reports position, so the app
/// drives a move, watches the counter, and derives counts-per-second.
///
/// The head cannot. It reports no position and no motion state (§5), so nothing
/// about its move is observable — not its speed, not its distance, not even
/// whether it has finished. A human watching it is the only source of truth,
/// which is why this asks you to press a button when it stops.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/ek_connection.dart';
import '../control/keypose_controller.dart';
import '../control/move_timing.dart';
import '../control/stop_registry.dart';
import '../ek_protocol.dart';
import 'ui_scale.dart';

class TimingDialog extends StatefulWidget {
  const TimingDialog({
    super.key,
    required this.keyposes,
    required this.connections,
    required this.slotA,
    required this.slotB,
  });

  final KeyposeController keyposes;
  final List<EkConnection> connections;
  final int slotA;
  final int slotB;

  @override
  State<TimingDialog> createState() => _TimingDialogState();
}

enum _Stage { intro, slider, head, done }

class _TimingDialogState extends State<TimingDialog> {
  _Stage _stage = _Stage.intro;
  String? _error;
  final _log = <String>[];

  Stopwatch? _headClock;
  bool _running = false;

  EkConnection? get _slider {
    for (final c in widget.connections) {
      if (c.kind == EkKind.slider) return c;
    }
    return null;
  }

  EkConnection? get _head {
    for (final c in widget.connections) {
      if (c.kind == EkKind.head) return c;
    }
    return null;
  }

  void _note(String message) {
    if (mounted) setState(() => _log.add(message));
  }

  @override
  void dispose() {
    _running = false;
    StopRegistry.instance.unregister(this);
    super.dispose();
  }

  /// Drives the slider between the two poses and times it against telemetry.
  Future<void> _calibrateSlider() async {
    final slider = _slider;
    if (slider == null) {
      await _startHeadOrFinish();
      return;
    }
    setState(() {
      _stage = _Stage.slider;
      _running = true;
      _error = null;
    });
    StopRegistry.instance.register(this, () async => _abort());

    try {
      final percent = widget.keyposes.settingsFor(EkKind.slider).speedPercent;
      final start = slider.snapshot.position;
      _note('Driving the slider to slot ${widget.slotB} at '
          '${percent.round()}%…');

      final began = DateTime.now();
      await slider.recallPose(widget.slotB,
          settings: widget.keyposes
              .settingsFor(EkKind.slider)
              .copyWith(speedPercent: percent));

      // Wait for the move to finish the same way the ping-pong does: motion,
      // then idle held.
      var sawMotion = false;
      DateTime? idleSince;
      final deadline = began.add(const Duration(seconds: 120));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!_running) throw StateError('cancelled');
        final s = slider.snapshot;
        if (!s.isReady) throw StateError('link lost');
        if (s.state == EkState.keyposeMove) {
          sawMotion = true;
          idleSince = null;
        } else if (s.state == EkState.idle) {
          if (!sawMotion &&
              DateTime.now().difference(began) < const Duration(seconds: 3)) {
            continue;
          }
          idleSince ??= DateTime.now();
          if (DateTime.now().difference(idleSince) >=
              const Duration(milliseconds: 600)) {
            break;
          }
        }
      }

      final took = DateTime.now().difference(began);
      final end = slider.snapshot.position;
      if (start == null || end == null) {
        _note('The slider reported no position, so it cannot be calibrated.');
      } else {
        final ok = await widget.keyposes.learnSliderMove(
          counts: end - start,
          duration: took,
          percent: percent,
        );
        if (ok) {
          _note('Slider: ${(end - start).abs()} counts in '
              '${(took.inMilliseconds / 1000).toStringAsFixed(1)} s at '
              '${percent.round()}%.');
        } else {
          _note('That move was too short to calibrate from. Move the poses '
              'further apart and try again.');
        }
      }
    } catch (e) {
      _error = '$e';
    } finally {
      _running = false;
      StopRegistry.instance.unregister(this);
      try {
        await slider.stopMotion();
      } catch (_) {
        // Nothing further this layer can do.
      }
    }
    await _startHeadOrFinish();
  }

  Future<void> _startHeadOrFinish() async {
    final head = _head;
    if (head == null || _error != null) {
      if (mounted) setState(() => _stage = _Stage.done);
      return;
    }
    setState(() {
      _stage = _Stage.head;
      _running = true;
    });
    StopRegistry.instance.register(this, () async => _abort());
    try {
      _note('Panning the head to slot ${widget.slotA}. Press the button the '
          'moment it stops.');
      _headClock = Stopwatch()..start();
      await head.recallPose(widget.slotA,
          settings: widget.keyposes.settingsFor(EkKind.head));
    } catch (e) {
      setState(() {
        _error = '$e';
        _stage = _Stage.done;
      });
    }
  }

  Future<void> _headStopped() async {
    final clock = _headClock;
    if (clock == null) return;
    clock.stop();
    _running = false;
    StopRegistry.instance.unregister(this);

    final percent = widget.keyposes.settingsFor(EkKind.head).speedPercent;
    final timing = HeadTiming(
      referenceDuration: clock.elapsed,
      referencePercent: percent,
      measuredForSlots:
          widget.keyposes.poses.saved.map((p) => p.slot).toList(),
    );
    await widget.keyposes
        .saveTiming(widget.keyposes.timing.copyWith(head: timing));
    _note('Head: ${(clock.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s '
        'at ${percent.round()}%.');
    try {
      await _head?.stopMotion();
    } catch (_) {
      // Nothing further this layer can do.
    }
    if (mounted) setState(() => _stage = _Stage.done);
  }

  void _abort() {
    _running = false;
    _headClock?.stop();
    if (mounted) {
      setState(() {
        _error = 'Cancelled.';
        _stage = _Stage.done;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timing = widget.keyposes.timing;

    return AlertDialog(
      title: const Text('Match the two axes'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_stage == _Stage.intro) ...[
                Text(
                  'To make both axes finish together, the app needs to know how '
                  'fast each one actually moves between your poses. It measures '
                  'one move on each.',
                  style: theme.textTheme.bodyMedium,
                ),
                Gap.md,
                Text('The slider is measured automatically from its position '
                    'counter.', style: theme.textTheme.bodySmall),
                const Caution(
                  'The head cannot be measured. It reports no position and no '
                  'motion state (§5), so nothing about its move is observable — '
                  'not even whether it has finished. You will be asked to press '
                  'a button the moment it stops; that timing is the only honest '
                  'source. Decoding the 16-byte 0x05 frame §5 suspects carries '
                  'head progress would remove the need.',
                ),
                Gap.sm,
                const Caution(
                  'The head calibration is only valid for the poses it was '
                  'timed between — there is no way to know how far apart two '
                  'head poses are, so changing one invalidates it.',
                ),
                Gap.md,
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: Insets.card,
                    child: Text(
                      'Both devices will move. Take the camera off the rig.',
                      style: TextStyle(
                          color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ),
              ] else ...[
                if (_stage == _Stage.head)
                  Text(
                    'Watch the head. Press the button the moment it stops '
                    'moving.',
                    style: theme.textTheme.titleMedium,
                  ),
                Gap.sm,
                for (final line in _log)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(line, style: theme.textTheme.bodySmall),
                  ),
                if (_stage == _Stage.slider) ...[
                  Gap.sm,
                  const LinearProgressIndicator(),
                ],
                if (_stage == _Stage.done) ...[
                  Gap.md,
                  Text(
                    timing.sliderCalibrated && timing.headCalibrated
                        ? 'Both axes calibrated. Recalls and ping-pong will now '
                            'solve each speed so the moves take the shot '
                            'duration.'
                        : 'Calibration incomplete — uncalibrated axes keep '
                            'using their manual speed.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
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
        if (_stage == _Stage.intro) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _calibrateSlider,
            child: const Text('Camera is off — measure'),
          ),
        ] else if (_stage == _Stage.head)
          FilledButton.icon(
            onPressed: _headStopped,
            icon: const Icon(Icons.timer_outlined),
            label: const Text('It stopped'),
          )
        else if (_stage == _Stage.done)
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          )
        else
          TextButton(onPressed: _abort, child: const Text('Cancel')),
      ],
    );
  }
}
