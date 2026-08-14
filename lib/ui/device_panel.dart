/// Controls for one connected device.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/ek_connection.dart';
import '../control/jog.dart';
import '../control/motion_settings.dart';
import '../control/ping_pong.dart';
import '../ek_protocol.dart';
import 'frame_inspector.dart';

class DevicePanel extends StatefulWidget {
  const DevicePanel({super.key, required this.connection});

  final EkConnection connection;

  @override
  State<DevicePanel> createState() => _DevicePanelState();
}

class _DevicePanelState extends State<DevicePanel> with WidgetsBindingObserver {
  late final JogController _jog = JogController(target: widget.connection);
  late final PingPongController _pingPong =
      PingPongController(target: widget.connection);

  MotionSettings _settings = const MotionSettings();

  // Ping-pong tuning. Defaults match the spec (§7 says ~0.6 s of held idle);
  // the blind leg is a guess about the hardware, so it is adjustable.
  double _settleMs = PingPongController.defaultSettle.inMilliseconds.toDouble();
  double _dwellSeconds = 0;
  double _blindLegSeconds =
      PingPongController.defaultBlindLeg.inSeconds.toDouble();
  int _maxLegs = 0;

  /// Position when the panel opened, so travel can be shown as a delta. The
  /// absolute counter is arbitrary and has no fixed relationship to the rail
  /// (§5), so only differences mean anything.
  int? _positionOrigin;
  StreamSubscription<EkSnapshot>? _snapSub;
  StreamSubscription<PingPongStatus>? _ppSub;
  String? _error;

  EkConnection get _c => widget.connection;
  bool get _isSlider => _c.kind == EkKind.slider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _snapSub = _c.snapshots.listen((_) {
      if (mounted) setState(() {});
    });
    _ppSub = _pingPong.statuses.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Leaving this screen must not leave anything moving.
    _snapSub?.cancel();
    _ppSub?.cancel();
    _jog.stop();
    _pingPong.dispose();
    super.dispose();
  }

  /// Backgrounding the app stops everything. A device left mid-move holds
  /// torque and locks the carriage (§7).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _emergencyStop();
    }
  }

  Future<void> _emergencyStop() async {
    await _jog.stop();
    await _pingPong.stop();
    try {
      await _c.stopMotion();
    } catch (e) {
      _report('$e');
    }
  }

  void _report(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      _report('$e');
    }
  }

  Future<void> _startJog(int sign) async {
    if (_pingPong.isRunning) return;
    await _guard(() => _jog.start(sign * _settings.jogVelocity()));
  }

  Future<void> _endJog() => _guard(_jog.stop);

  Future<void> _togglePingPong() async {
    if (_pingPong.isRunning) {
      await _guard(_pingPong.stop);
      return;
    }
    await _guard(_jog.stop);
    // Not awaited: the loop runs until stopped.
    unawaited(_pingPong
        .start(
      motion: _settings,
      settle: Duration(milliseconds: _settleMs.round()),
      dwell: Duration(milliseconds: (_dwellSeconds * 1000).round()),
      blindLeg: Duration(milliseconds: (_blindLegSeconds * 1000).round()),
      maxLegs: _maxLegs,
    )
        .catchError((Object e) {
      _report('$e');
    }));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = _c.snapshot;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_c.name.isEmpty ? _c.profile.name : _c.name),
        actions: [
          IconButton(
            tooltip: 'Raw frames',
            icon: const Icon(Icons.data_object),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FrameInspector(connection: _c),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _status(s, theme),
          const SizedBox(height: 16),
          _stopButton(),
          const SizedBox(height: 24),
          _speedControls(),
          const SizedBox(height: 24),
          _jogControls(),
          const SizedBox(height: 24),
          _poseControls(),
          const SizedBox(height: 24),
          _pingPongControls(),
          if (_error != null) ...[
            const SizedBox(height: 24),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _status(EkSnapshot s, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(s.isReporting ? Icons.circle : Icons.circle_outlined,
                    size: 12,
                    color: s.isReporting ? Colors.green : Colors.orange),
                const SizedBox(width: 8),
                Text(s.link.name, style: theme.textTheme.titleMedium),
                const Spacer(),
                if (s.batteryPercent != null) ...[
                  const Icon(Icons.battery_full, size: 18),
                  const SizedBox(width: 4),
                  Text('${s.batteryPercent}%'),
                ],
              ],
            ),
            if (!s.isReporting)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'No telemetry. Nothing is reported without the 250 ms poll.',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            const Divider(),
            Text('state: ${s.state.name}'),
            if (_isSlider) ...[
              Text('position: ${s.position?.toString() ?? '—'} counts'),
              if (s.position != null && _positionOrigin != null)
                Text(
                  'travelled: ${s.position! - _positionOrigin!} counts '
                  '(${((s.position! - _positionOrigin!).abs() / EkRig.sliderTravelCounts * 100).toStringAsFixed(1)}% of rail)',
                  style: theme.textTheme.bodySmall,
                ),
              Row(
                children: [
                  TextButton(
                    onPressed: s.position == null
                        ? null
                        : () => setState(() => _positionOrigin = s.position),
                    child: const Text('Zero here'),
                  ),
                  Text(
                    'Absolute counts are arbitrary (§5); only deltas mean '
                    'anything.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ] else
              Text(
                'position: not reported by the head (§5)',
                style: theme.textTheme.bodySmall,
              ),
            if (s.checksumFailures > 0)
              Text('checksum failures: ${s.checksumFailures}',
                  style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      ),
    );
  }

  Widget _stopButton() {
    return SizedBox(
      height: 64,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.red.shade700,
          foregroundColor: Colors.white,
        ),
        onPressed: () => _guard(_emergencyStop),
        icon: const Icon(Icons.stop_circle, size: 28),
        label: const Text('STOP', style: TextStyle(fontSize: 20)),
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label — $display',
            style: Theme.of(context).textTheme.bodySmall),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: _pingPong.isRunning ? null : onChanged,
        ),
      ],
    );
  }

  Widget _speedControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Speed  ${_settings.speedPercent.round()}%'),
        Slider(
          value: _settings.speedPercent,
          min: 1,
          max: 100,
          onChanged: (v) {
            setState(() => _settings = _settings.copyWith(speedPercent: v));
            // Takes effect immediately if a jog is in progress.
            _jog.setVelocity(_settings.jogVelocity());
          },
        ),
        Text('Acceleration  ${_settings.accelPercent.round()}%'),
        Slider(
          value: _settings.accelPercent,
          min: 1,
          max: 100,
          onChanged: (v) =>
              setState(() => _settings = _settings.copyWith(accelPercent: v)),
        ),
        if (!_settings.isCaptureFaithful)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Speed and acceleration were only ever captured set together, and '
              'the two fields are symmetric in every captured frame — which one '
              'is which is unverified (§7b). Matching values reproduce the '
              'captured behaviour exactly.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.orange,
                  ),
            ),
          ),
        Text(
          'Speed also scales manual jogging: jogging has no speed field, so the '
          'velocity itself is scaled (§7b). Acceleration does not apply to it.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _jogControls() {
    final blocked = _pingPong.isRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Jog — hold to move',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _HoldButton(
                icon: Icons.fast_rewind,
                label: _isSlider ? 'Left' : 'Pan left',
                enabled: !blocked,
                onDown: () => _startJog(-1),
                onUp: _endJog,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _HoldButton(
                icon: Icons.fast_forward,
                label: _isSlider ? 'Right' : 'Pan right',
                enabled: !blocked,
                onDown: () => _startJog(1),
                onUp: _endJog,
              ),
            ),
          ],
        ),
        if (blocked)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Stop the ping-pong first.',
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _poseControls() {
    final blocked = _pingPong.isRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Poses', style: Theme.of(context).textTheme.titleMedium),
        Text(
          'Save stores the position the device is at right now. Poses survive a '
          'reconnect but are lost at power-off (§3).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final slot in [0, 1])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 70, child: Text('Slot $slot')),
                OutlinedButton.icon(
                  onPressed:
                      blocked ? null : () => _guard(() => _c.savePose(slot)),
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('Save'),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: blocked
                      ? null
                      : () => _guard(
                            () => _c.recallPose(slot, settings: _settings),
                          ),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Recall'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _pingPongControls() {
    final st = _pingPong.status;
    final running = _pingPong.isRunning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ping-pong', style: Theme.of(context).textTheme.titleMedium),
        Text(
          _isSlider
              ? 'Supervised from the host: recall, wait for idle to hold, then '
                  'recall the other. The device’s own loop mode stops after '
                  'about one round trip (§3).'
              : 'The head reports no motion state (§5), so each leg runs blind '
                  'on a fixed timer rather than waiting for the move to finish. '
                  'Watch it.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (_isSlider)
          _slider(
            label: 'Settle — idle must hold this long before the next leg',
            value: _settleMs,
            min: 200,
            max: 2000,
            display: '${_settleMs.round()} ms',
            onChanged: (v) => setState(() => _settleMs = v),
          )
        else
          _slider(
            label: 'Leg duration — how long to wait, since the head reports '
                'nothing to wait on',
            value: _blindLegSeconds,
            min: 1,
            max: 60,
            display: '${_blindLegSeconds.toStringAsFixed(0)} s',
            onChanged: (v) => setState(() => _blindLegSeconds = v),
          ),
        _slider(
          label: 'Dwell at each end',
          value: _dwellSeconds,
          min: 0,
          max: 30,
          display: _dwellSeconds < 0.5
              ? 'none — reverse immediately'
              : '${_dwellSeconds.toStringAsFixed(0)} s',
          onChanged: (v) => setState(() => _dwellSeconds = v),
        ),
        Row(
          children: [
            const Text('Stop after'),
            const SizedBox(width: 12),
            DropdownButton<int>(
              value: _maxLegs,
              items: const [
                DropdownMenuItem(value: 0, child: Text('unlimited')),
                DropdownMenuItem(value: 2, child: Text('1 round trip')),
                DropdownMenuItem(value: 4, child: Text('2 round trips')),
                DropdownMenuItem(value: 10, child: Text('5 round trips')),
                DropdownMenuItem(value: 20, child: Text('10 round trips')),
              ],
              onChanged: _pingPong.isRunning
                  ? null
                  : (v) => setState(() => _maxLegs = v ?? 0),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () => _togglePingPong(),
              icon: Icon(running ? Icons.stop : Icons.repeat),
              label: Text(running ? 'Stop ping-pong' : 'Start ping-pong'),
            ),
            const SizedBox(width: 16),
            if (running || st.legs > 0)
              Text('${st.phase.name} · ${st.legs} legs'),
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
/// Release is wired to pointer-up AND pointer-cancel: a cancel arrives when the
/// gesture is interrupted (a scroll takes over, the window loses focus), and
/// treating that as anything other than a release would leave the motor
/// running with no finger on the button.
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
        height: 72,
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
