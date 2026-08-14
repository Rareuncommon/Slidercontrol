/// One device's controls, as a column inside the control page.
///
/// Was a full screen of its own; it is now a section so both devices are
/// reachable without navigating away. It still owns its own jog and ping-pong
/// controllers and its own StopRegistry registration, so the stop guarantees
/// are unchanged by the move.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/ek_connection.dart';
import '../control/jog.dart';
import '../control/motion_settings.dart';
import '../control/panel_settings.dart';
import '../control/panel_settings_store.dart';
import '../control/ping_pong.dart';
import '../control/stop_registry.dart';
import '../ek_protocol.dart';
import 'frame_inspector.dart';
import 'ui_scale.dart';

class DeviceColumn extends StatefulWidget {
  const DeviceColumn({
    super.key,
    required this.connection,
    required this.settle,
    required this.dwell,
    required this.onError,
  });

  final EkConnection connection;

  /// Shared across devices, owned by the control page.
  final Duration settle;
  final Duration dwell;

  final void Function(String message) onError;

  @override
  State<DeviceColumn> createState() => DeviceColumnState();
}

class DeviceColumnState extends State<DeviceColumn> {
  late final JogController _jog = JogController(target: widget.connection);
  late final PingPongController _pingPong =
      PingPongController(target: widget.connection);

  PanelSettings _panel = const PanelSettings();
  late final PanelSettingsStore _store;

  StreamSubscription<EkSnapshot>? _snapSub;
  StreamSubscription<PingPongStatus>? _ppSub;

  /// Position when this column was built, so travel reads as a delta. The
  /// absolute counter is arbitrary and has no fixed relationship to the rail
  /// (§5), so only differences mean anything.
  int? _positionOrigin;

  EkConnection get _c => widget.connection;
  bool get _isSlider => _c.kind == EkKind.slider;
  MotionSettings get _motion => _panel.motion;

  bool get isPingPonging => _pingPong.isRunning;

  @override
  void initState() {
    super.initState();
    _snapSub = _c.snapshots.listen((_) {
      if (mounted) setState(() {});
    });
    _ppSub = _pingPong.statuses.listen((_) {
      if (mounted) setState(() {});
    });
    // The FULL stop, not just the device write: halting the motor while the
    // ping-pong loop still runs only pauses it — the next leg restarts it.
    StopRegistry.instance.register(this, emergencyStop);

    _store = PanelSettingsStore(_c.kind.name);
    _store.load().then((loaded) {
      if (mounted) setState(() => _panel = loaded);
    });
  }

  @override
  void dispose() {
    StopRegistry.instance.unregister(this);
    _snapSub?.cancel();
    _ppSub?.cancel();
    _jog.stop();
    _pingPong.dispose();
    super.dispose();
  }

  /// Stops everything this column can start.
  Future<void> emergencyStop() async {
    await _jog.stop();
    await _pingPong.stop();
    try {
      await _c.stopMotion();
    } catch (e) {
      widget.onError('$e');
    }
  }

  void _update(PanelSettings next) {
    setState(() => _panel = next);
    _store.save(next);
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      widget.onError('${_label()}: $e');
    }
  }

  Future<void> _startJog(int sign) async {
    if (_pingPong.isRunning || !_c.snapshot.isReady) return;
    await _guard(() => _jog.start(sign * _motion.jogVelocity()));
  }

  Future<void> _endJog() => _guard(_jog.stop);

  /// Started by the control page too, for the synchronised run.
  Future<void> togglePingPong() async {
    if (_pingPong.isRunning) {
      await _guard(_pingPong.stop);
      return;
    }
    await _guard(_jog.stop);
    unawaited(_pingPong
        .start(
      motion: _panel.motion,
      settle: widget.settle,
      dwell: widget.dwell,
      blindLeg: _panel.blindLeg,
      maxLegs: _panel.maxLegs,
    )
        .catchError((Object e) => widget.onError('${_label()}: $e')));
    if (mounted) setState(() {});
  }

  String _label() => _c.name.isEmpty ? _c.profile.name : _c.name;

  @override
  Widget build(BuildContext context) {
    final s = _c.snapshot;
    final theme = Theme.of(context);
    // Controls stay present and disabled rather than disappearing, so the
    // layout does not jump when a link drops.
    final live = s.isReady;
    final blocked = _pingPong.isRunning;

    return Card(
      child: Padding(
        padding: Insets.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(s, theme),
            const Divider(height: 24),
            _statusLines(s, theme),
            Gap.lg,
            _speed(live),
            Gap.lg,
            _jogControls(live && !blocked),
            Gap.lg,
            _poses(live && !blocked),
            Gap.lg,
            _pingPongSection(live),
          ],
        ),
      ),
    );
  }

  Widget _header(EkSnapshot s, ThemeData theme) {
    return Row(
      children: [
        Icon(_isSlider ? Icons.linear_scale : Icons.threesixty),
        Gap.wSm,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_label(), style: theme.textTheme.titleMedium),
              Row(
                children: [
                  Icon(
                    s.isReporting ? Icons.circle : Icons.circle_outlined,
                    size: 10,
                    color: s.isReporting ? Colors.green : Colors.orange,
                  ),
                  Gap.wSm,
                  Text(s.link.name, style: theme.textTheme.bodySmall),
                  if (s.batteryPercent != null) ...[
                    Gap.wMd,
                    const Icon(Icons.battery_full, size: 14),
                    Text('${s.batteryPercent}%',
                        style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Raw frames',
          icon: const Icon(Icons.data_object, size: 20),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => FrameInspector(connection: _c),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusLines(EkSnapshot s, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!s.isReporting && s.isReady)
          const Caution(
            'No telemetry. Nothing is reported without the 250 ms poll (§7).',
          ),
        Text('state: ${s.state.name}', style: theme.textTheme.bodySmall),
        if (_isSlider) ...[
          Text('position: ${s.position?.toString() ?? '—'} counts',
              style: theme.textTheme.bodySmall),
          if (s.position != null && _positionOrigin != null)
            Text(
              'travelled ${s.position! - _positionOrigin!} counts '
              '(${((s.position! - _positionOrigin!).abs() / EkRig.sliderTravelCounts * 100).toStringAsFixed(1)}% of rail)',
              style: theme.textTheme.bodySmall,
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: s.position == null
                  ? null
                  : () => setState(() => _positionOrigin = s.position),
              child: const Text('Zero here'),
            ),
          ),
          const Caution(
            'Counts are arbitrary per session and have no fixed relationship '
            'to the rail (§5). Only differences mean anything.',
          ),
        ] else
          const Caution(
            'The head reports no position and no motion state (§5). Its 122-byte '
            'frame is static — nothing changes during a commanded move.',
          ),
        if (s.checksumFailures > 0)
          Text('checksum failures: ${s.checksumFailures}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error)),
      ],
    );
  }

  Widget _speed(bool live) {
    return Section(
      title: 'Speed',
      children: [
        LabelledSlider(
          label: 'Speed',
          value: _motion.speedPercent,
          min: 1,
          max: 100,
          display: '${_motion.speedPercent.round()}%',
          onChanged: !live
              ? null
              : (v) {
                  _update(_panel.copyWith(
                      motion: _motion.copyWith(speedPercent: v)));
                  _jog.setVelocity(_panel.motion.jogVelocity());
                },
        ),
        LabelledSlider(
          label: 'Acceleration',
          value: _motion.accelPercent,
          min: 1,
          max: 100,
          display: '${_motion.accelPercent.round()}%',
          onChanged: !live
              ? null
              : (v) => _update(
                  _panel.copyWith(motion: _motion.copyWith(accelPercent: v))),
        ),
        if (!_motion.isCaptureFaithful)
          const Caution(
            'Speed and acceleration were only ever captured set together, and '
            'the two fields are symmetric in every captured frame — which is '
            'which is unverified (§7b). Matching values reproduce the captured '
            'behaviour exactly.',
          ),
        const Caution(
          'Speed also scales jogging: jogging has no speed field, so the '
          'velocity itself is scaled (§7b). Acceleration does not apply to it.',
        ),
      ],
    );
  }

  Widget _jogControls(bool enabled) {
    return Section(
      title: 'Jog',
      note: 'Hold to move.',
      children: [
        Row(
          children: [
            Expanded(
              child: _HoldButton(
                icon: Icons.fast_rewind,
                label: _isSlider ? 'Left' : 'Pan left',
                enabled: enabled,
                onDown: () => _startJog(-1),
                onUp: _endJog,
              ),
            ),
            Gap.wSm,
            Expanded(
              child: _HoldButton(
                icon: Icons.fast_forward,
                label: _isSlider ? 'Right' : 'Pan right',
                enabled: enabled,
                onDown: () => _startJog(1),
                onUp: _endJog,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _poses(bool enabled) {
    return Section(
      title: 'Poses',
      note: 'Save stores the position the device is at right now. Poses survive '
          'a reconnect but are lost at power-off (§3).',
      children: [
        for (final slot in [0, 1])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 60, child: Text('Slot $slot')),
                OutlinedButton.icon(
                  onPressed:
                      enabled ? () => _guard(() => _c.savePose(slot)) : null,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                  label: const Text('Save'),
                ),
                Gap.wSm,
                FilledButton.tonalIcon(
                  onPressed: enabled
                      ? () => _guard(
                          () => _c.recallPose(slot, settings: _panel.motion))
                      : null,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Recall'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _pingPongSection(bool live) {
    final st = _pingPong.status;
    final running = _pingPong.isRunning;

    return Section(
      title: 'Ping-pong',
      note: _isSlider
          ? 'Supervised: recall, wait for idle to hold, then recall the other. '
              'The device’s own loop mode stops after about one round trip (§3).'
          : 'The head reports no motion state (§5), so each leg runs blind on a '
              'fixed timer rather than waiting for the move to finish. Watch it.',
      children: [
        if (!_isSlider)
          LabelledSlider(
            label: 'Leg duration',
            value: _panel.blindLegSeconds,
            min: PanelSettings.blindLegMin,
            max: PanelSettings.blindLegMax,
            display: '${_panel.blindLegSeconds.toStringAsFixed(0)} s',
            onChanged: running || !live
                ? null
                : (v) => _update(_panel.copyWith(blindLegSeconds: v)),
          ),
        Row(
          children: [
            const Text('Stop after'),
            Gap.wSm,
            DropdownButton<int>(
              value: _panel.maxLegs,
              items: const [
                DropdownMenuItem(value: 0, child: Text('unlimited')),
                DropdownMenuItem(value: 2, child: Text('1 round trip')),
                DropdownMenuItem(value: 4, child: Text('2 round trips')),
                DropdownMenuItem(value: 10, child: Text('5 round trips')),
              ],
              onChanged: running || !live
                  ? null
                  : (v) => _update(_panel.copyWith(maxLegs: v ?? 0)),
            ),
          ],
        ),
        Gap.sm,
        Row(
          children: [
            FilledButton.icon(
              onPressed: live ? togglePingPong : null,
              icon: Icon(running ? Icons.stop : Icons.repeat),
              label: Text(running ? 'Stop' : 'Start'),
            ),
            Gap.wMd,
            if (running || st.legs > 0)
              Expanded(
                child: Text(
                  '${st.phase.name} · leg ${st.legs}'
                  '${st.lastLeg != null ? ' · last ${(st.lastLeg!.inMilliseconds / 1000).toStringAsFixed(1)}s' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
        if (st.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(st.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }
}

/// A button that reports press and release, for hold-to-move.
///
/// Release is wired to pointer-cancel as well as pointer-up: a cancel arrives
/// when the gesture is interrupted, and treating that as anything other than a
/// release would leave the motor running with no finger on the button.
class _HoldButton extends StatefulWidget {
  const _HoldButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onDown,
    required this.onUp,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final Future<void> Function() onDown;
  final Future<void> Function() onUp;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  bool _held = false;

  void _down() {
    if (!widget.enabled || _held) return;
    setState(() => _held = true);
    widget.onDown();
  }

  void _up() {
    if (!_held) return;
    setState(() => _held = false);
    widget.onUp();
  }

  @override
  void dispose() {
    // A widget torn down mid-hold must still release.
    if (_held) widget.onUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Listener(
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: !widget.enabled
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
              : _held
                  ? scheme.primary
                  : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon,
                color: _held ? scheme.onPrimary : scheme.onSurfaceVariant),
            Text(widget.label,
                style: TextStyle(
                  color: _held ? scheme.onPrimary : scheme.onSurfaceVariant,
                )),
          ],
        ),
      ),
    );
  }
}
