/// The control page: both devices and their keyposes, all visible at once.
///
/// Deliberately does not scroll. Jog pads at the top, keyposes filling the
/// middle, speed and acceleration along the bottom, and the actions below that
/// — so nothing that can move a motor is ever off-screen.
///
/// The protocol notes and warnings are still here; the long ones sit behind the
/// info buttons rather than being cut, and the ones that change what you should
/// expect stay inline.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/ek_connection.dart';
import '../control/fleet.dart';
import '../control/jog.dart';
import '../control/keypose_controller.dart';
import '../control/leg_supervisor.dart';
import '../control/motion_settings.dart';
import '../control/panel_settings.dart';
import '../control/panel_settings_store.dart';
import '../control/stop_registry.dart';
import '../ek_protocol.dart';
import 'frame_inspector.dart';
import 'homing_dialog.dart';
import 'jog_pad.dart';
import 'keypose_tiles.dart';
import 'ui_scale.dart';

class ControlPage extends StatefulWidget {
  const ControlPage({super.key, required this.connections});

  final List<EkConnection> connections;

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> with WidgetsBindingObserver {
  final _jogs = <String, JogController>{};
  final _settings = <String, PanelSettings>{};
  final _subs = <StreamSubscription<EkSnapshot>>[];

  late final KeyposeController _keyposes;
  FleetPingPong? _fleet;
  StreamSubscription<FleetStatus>? _fleetSub;

  /// Tracks link transitions so poses can be re-marked unverified after a
  /// reconnect — the device may have been power-cycled in between, and nothing
  /// can read a pose back off it (§3).
  final _wasReady = <String, bool>{};

  int? _activeSlot;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    for (final c in widget.connections) {
      _jogs[c.device.remoteId.str] = JogController(target: c);
      _wasReady[c.device.remoteId.str] = c.snapshot.isReady;
      _subs.add(c.snapshots.listen((s) {
        final id = c.device.remoteId.str;
        final wasReady = _wasReady[id] ?? false;
        if (s.isReady && !wasReady) _keyposes.markUnverified();
        _wasReady[id] = s.isReady;
        if (mounted) setState(() {});
      }));
    }

    _keyposes = KeyposeController(
      devices: widget.connections,
      settingsFor: (kind) => _settingsFor(kind).motion,
    );
    _load();

    StopRegistry.instance.register(this, stopEverything);
  }

  Future<void> _load() async {
    for (final c in widget.connections) {
      final s = await PanelSettingsStore(c.kind.name).load();
      if (!mounted) return;
      setState(() => _settings[c.kind.name] = s);
    }
    await _keyposes.load();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    StopRegistry.instance.unregister(this);
    _fleetSub?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    for (final j in _jogs.values) {
      j.stop();
    }
    _fleet?.dispose();
    super.dispose();
  }

  /// Backgrounding stops everything. A device left mid-move holds torque and
  /// locks the carriage (§7).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      StopRegistry.instance.stopAll();
    }
  }

  /// Everything this page can start.
  Future<void> stopEverything() async {
    for (final j in _jogs.values) {
      await j.stop();
    }
    await _fleet?.stop();
    for (final c in widget.connections) {
      try {
        await c.stopMotion();
      } catch (e) {
        _report('$e');
      }
    }
    if (mounted) setState(() {});
  }

  PanelSettings _settingsFor(EkKind kind) =>
      _settings[kind.name] ?? const PanelSettings();

  void _report(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _guard(Future<List<String>> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final failures = await action();
      if (mounted && failures.isNotEmpty) {
        setState(() => _error = failures.join('\n'));
      }
    } catch (e) {
      _report('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<EkConnection> get _ready =>
      widget.connections.where((c) => c.snapshot.isReady).toList();

  EkConnection? get _slider {
    for (final c in widget.connections) {
      if (c.kind == EkKind.slider) return c;
    }
    return null;
  }

  bool get _fleetRunning => _fleet?.isRunning ?? false;

  // -- speed ---------------------------------------------------------------

  /// The bottom bars drive every connected device, matching the official app's
  /// single pair. Per-device values still exist and are reachable in Settings,
  /// which is what you need when matching leg durations between the two axes.
  double get _speed => _settingsFor(EkKind.slider).motion.speedPercent;
  double get _accel => _settingsFor(EkKind.slider).motion.accelPercent;

  void _setSpeed(double v) => _setMotion((m) => m.copyWith(speedPercent: v));
  void _setAccel(double v) => _setMotion((m) => m.copyWith(accelPercent: v));

  void _setMotion(MotionSettings Function(MotionSettings) f) {
    setState(() {
      for (final c in widget.connections) {
        final current = _settingsFor(c.kind);
        _settings[c.kind.name] = current.copyWith(motion: f(current.motion));
      }
    });
    for (final c in widget.connections) {
      PanelSettingsStore(c.kind.name).save(_settingsFor(c.kind));
      // Applies immediately if that pad is being held.
      _jogs[c.device.remoteId.str]?.setVelocity(
        _settingsFor(c.kind).motion.jogVelocity(),
      );
    }
  }

  // -- keyposes ------------------------------------------------------------

  Future<void> _recall(int slot) async {
    setState(() => _activeSlot = slot);
    await _guard(() => _keyposes.recall(slot));
  }

  Future<void> _saveNew() async {
    final slot = await _keyposes.addSlot();
    if (slot == null) return;
    await _guard(() => _keyposes.save(slot));
    if (mounted) setState(() {});
  }

  Future<void> _editPose(int slot) async {
    final pose = _keyposes.poses.bySlot(slot);
    if (pose == null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(pose.name.isEmpty
                  ? 'Slot ${pose.slot}'
                  : '${pose.name} · slot ${pose.slot}'),
              subtitle: Text(pose.isEmpty
                  ? 'Empty'
                  : pose.isVerified
                      ? 'Saved this session'
                      : 'Saved earlier — may no longer be on the device (§3)'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: const Text('Save here'),
              subtitle: const Text('Stores the current position of every device'),
              onTap: () => Navigator.pop(context, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            if (pose.isSet)
              ListTile(
                leading: const Icon(Icons.backspace_outlined),
                title: const Text('Clear'),
                onTap: () => Navigator.pop(context, 'clear'),
              ),
            if (_keyposes.poses.length > 1)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove slot'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'save':
        await _guard(() => _keyposes.save(slot));
      case 'rename':
        await _rename(slot, pose.name);
      case 'clear':
        await _confirmClear(slot);
      case 'remove':
        await _keyposes.removeSlot(slot);
    }
    if (mounted) setState(() {});
  }

  Future<void> _rename(int slot, String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name this keypose'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'wide, tight, …'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (name != null) await _keyposes.rename(slot, name.trim());
  }

  /// The only destructive action, so the only one that asks.
  Future<void> _confirmClear(int slot) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear slot $slot?'),
        content: const Text(
          'This forgets what the app knows about the slot. There is no '
          'clear-a-pose command in the protocol, so the device keeps whatever '
          'it had until something overwrites it.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) await _keyposes.clear(slot);
  }

  // -- ping-pong -----------------------------------------------------------

  Future<void> _togglePingPong() async {
    if (_fleetRunning) {
      await _fleet?.stop();
      if (mounted) setState(() {});
      return;
    }

    final saved = _keyposes.poses.saved;
    if (saved.length < 2) {
      _report('Save at least two keyposes before running a ping-pong.');
      return;
    }

    final next = FleetPingPong(
      members: [
        for (final c in _ready)
          FleetMember(
            target: c,
            name: c.name.isEmpty ? c.profile.name : c.name,
            motion: _settingsFor(c.kind).motion,
            timings: LegTimings(
              settle: _settingsFor(c.kind).settle,
              blindLeg: _settingsFor(c.kind).blindLeg,
            ),
          ),
      ],
      slotA: saved.first.slot,
      slotB: saved[1].slot,
    );
    await _fleetSub?.cancel();
    _fleetSub = next.statuses.listen((s) {
      if (mounted) setState(() => _activeSlot = s.slot);
    });
    setState(() {
      _fleet = next;
      _error = null;
    });
    unawaited(next
        .start(
          dwell: _settingsFor(EkKind.slider).dwell,
          maxLegs: _settingsFor(EkKind.slider).maxLegs,
        )
        .catchError((Object e) => _report('$e')));
    if (mounted) setState(() {});
  }

  // -- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _statusStrip(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: ErrorBanner(_error!,
                    onDismiss: () => setState(() => _error = null)),
              ),
            Expanded(flex: 5, child: _pads()),
            _track(),
            Expanded(flex: 5, child: _keyposeArea()),
            _speedBars(),
            _actions(),
          ],
        ),
      ),
    );
  }

  Widget _statusStrip() {
    final theme = Theme.of(context);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        children: [
          for (final c in widget.connections) ...[
            Icon(
              c.snapshot.isReporting ? Icons.circle : Icons.circle_outlined,
              size: 9,
              color: c.snapshot.isReporting ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 4),
            Text(
              '${c.kind == EkKind.slider ? 'S' : 'P'}: '
              '${c.snapshot.batteryPercent != null ? '${c.snapshot.batteryPercent}%' : '—'}',
              style: theme.textTheme.bodySmall,
            ),
            Gap.wMd,
          ],
          Text(
            _fleetRunning
                ? '${_fleet!.status.phase.name} · leg ${_fleet!.status.legs}'
                : (_slider?.snapshot.state.name ?? 'idle'),
            style: theme.textTheme.bodySmall,
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Protocol notes',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.info_outline),
            onPressed: _showNotes,
          ),
          IconButton(
            tooltip: 'Settings',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.tune),
            onPressed: _showSettings,
          ),
          IconButton(
            tooltip: 'Device list',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.list),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _pads() {
    return Row(
      children: [
        for (final c in widget.connections)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: JogPad(
                label: c.kind == EkKind.slider ? 'SLIDE' : 'PAN',
                enabled: c.snapshot.isReady && !_fleetRunning,
                disabledNote:
                    _fleetRunning ? 'ping-pong running' : 'not connected',
                onVelocity: (fraction) {
                  final jog = _jogs[c.device.remoteId.str];
                  final full = _settingsFor(c.kind).motion.jogVelocity();
                  final v = (full * fraction).round();
                  if (jog == null) return;
                  if (jog.isJogging) {
                    jog.setVelocity(v);
                  } else {
                    jog.start(v).catchError((Object e) => _report('$e'));
                  }
                },
                onRelease: () => _jogs[c.device.remoteId.str]
                    ?.stop()
                    .catchError((Object e) => _report('$e')),
              ),
            ),
          ),
      ],
    );
  }

  Widget _track() {
    final slider = _slider;
    if (slider == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: PoseTrack(
        poses: _keyposes.poses,
        position: slider.snapshot.position,
        homed: _keyposes.isHomed,
        endLo: _keyposes.datum?.endLo,
        endHi: _keyposes.datum?.endHi,
      ),
    );
  }

  Widget _keyposeArea() {
    final hasHead =
        widget.connections.any((c) => c.kind == EkKind.head);
    return Column(
      children: [
        Expanded(
          child: KeyposeTiles(
            poses: _keyposes.poses,
            enabled: _ready.isNotEmpty && !_busy && !_fleetRunning,
            activeSlot: _activeSlot,
            onRecall: _recall,
            onSaveNew: _saveNew,
            onEdit: _editPose,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Text(
            hasHead
                ? 'Tap to recall on every device · long-press to edit. Poses die '
                    'at power-off (§3); the head stores no position, so its '
                    'angle must be re-taught by hand each session (§5).'
                : 'Tap to recall · long-press to edit. Poses die at power-off '
                    '(§3) and cannot be read back, so slots saved earlier are '
                    'marked unverified.',
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _speedBars() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: _Bar(
              label: 'Accel',
              value: _accel,
              onChanged: _fleetRunning ? null : _setAccel,
            ),
          ),
          Gap.wSm,
          Expanded(
            child: _Bar(
              label: 'Speed',
              value: _speed,
              onChanged: _fleetRunning ? null : _setSpeed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    final theme = Theme.of(context);
    final canHome = _slider != null && _slider!.snapshot.isReady;

    return Container(
      height: 62,
      margin: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          _Action(
            label: _fleetRunning ? 'STOP\nPING-PONG' : 'PING\nPONG',
            active: _fleetRunning,
            onTap: _ready.isEmpty ? null : _togglePingPong,
          ),
          _Action(
            label: 'HOME\nSLIDER',
            onTap: canHome && !_fleetRunning
                ? () => _openHoming(HomingJob.home)
                : null,
          ),
          _Action(
            label: 'RESTORE\nPOSES',
            onTap: canHome && !_fleetRunning
                ? () => _openHoming(HomingJob.restore)
                : null,
          ),
          Expanded(
            flex: 2,
            child: Material(
              color: Colors.red.shade700,
              child: InkWell(
                onTap: () async {
                  final failures = await StopRegistry.instance.stopAll();
                  if (failures.isNotEmpty) _report(failures.join('\n'));
                },
                child: Center(
                  child: Text(
                    'STOP ALL  ·  Esc',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openHoming(HomingJob job) async {
    final slider = _slider;
    if (slider == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => HomingDialog(
        slider: slider,
        keyposes: _keyposes,
        job: job,
      ),
    );
    if (mounted) setState(() {});
  }

  void _showNotes() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('What this app can and cannot do'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                _Note('Poses are volatile (§3)',
                    'They survive a reconnect but are lost at power-off, and '
                        'nothing reads them back off the device. Slots saved in '
                        'an earlier session are marked unverified rather than '
                        'shown as definitely present.'),
                _Note('Save carries no position (§3)',
                    'The save frame means "store wherever you are right now". '
                        'There is no upload-a-position command anywhere in the '
                        'captures, so the only way to restore a pose is to move '
                        'there physically and save — which is what Restore does '
                        'for the slider.'),
                _Note('The head reports nothing (§5)',
                    'No position and no motion state. Its ping-pong legs run '
                        'blind on a timer, and its poses must be re-taught by '
                        'hand each session. Jogging it open-loop for a stored '
                        'duration would drift with battery and load, silently, '
                        'so the app does not pretend otherwise.'),
                _Note('Slider counts are arbitrary (§5)',
                    'The counter restarts at an arbitrary value each session '
                        'and has no fixed relationship to the rail. Homing is '
                        'what gives it a datum; until then the track is '
                        'relative only.'),
                _Note('Speed and acceleration (§7b)',
                    'Only 1% and 100% were ever measured; everything between is '
                        'modelled. The two fields are symmetric in every '
                        'captured frame and were always set together, so which '
                        'is which is unverified.'),
                _Note('Moving together is host-side (§8)',
                    'The official app pairs the units into one combined '
                        'keypose; that path was never captured. Here each '
                        'device gets an ordinary recall at the same moment and '
                        'none starts its next leg until all have finished, so '
                        'the axes stay in step leg by leg but can drift within '
                        'a leg.'),
                _Note('The head is never homed',
                    'It has no end stops. Homing applies to the slider only.'),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          void update(EkKind kind, PanelSettings next) {
            setState(() => _settings[kind.name] = next);
            setSheet(() {});
            PanelSettingsStore(kind.name).save(next);
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: Insets.page,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Settings',
                      style: Theme.of(context).textTheme.titleLarge),
                  Gap.md,
                  for (final c in widget.connections) ...[
                    Text(c.name.isEmpty ? c.profile.name : c.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    LabelledSlider(
                      label: 'Speed',
                      value: _settingsFor(c.kind).motion.speedPercent,
                      min: 1,
                      max: 100,
                      display:
                          '${_settingsFor(c.kind).motion.speedPercent.round()}%',
                      onChanged: (v) => update(
                        c.kind,
                        _settingsFor(c.kind).copyWith(
                          motion: _settingsFor(c.kind)
                              .motion
                              .copyWith(speedPercent: v),
                        ),
                      ),
                    ),
                    if (c.kind == EkKind.slider)
                      LabelledSlider(
                        label: 'Settle — idle must hold this long',
                        value: _settingsFor(c.kind).settleMs,
                        min: PanelSettings.settleMin,
                        max: PanelSettings.settleMax,
                        display:
                            '${_settingsFor(c.kind).settleMs.round()} ms',
                        onChanged: (v) => update(c.kind,
                            _settingsFor(c.kind).copyWith(settleMs: v)),
                      )
                    else
                      LabelledSlider(
                        label: 'Leg duration — the head reports nothing to '
                            'wait on (§5)',
                        value: _settingsFor(c.kind).blindLegSeconds,
                        min: PanelSettings.blindLegMin,
                        max: PanelSettings.blindLegMax,
                        display:
                            '${_settingsFor(c.kind).blindLegSeconds.toStringAsFixed(0)} s',
                        onChanged: (v) => update(c.kind,
                            _settingsFor(c.kind).copyWith(blindLegSeconds: v)),
                      ),
                    TextButton.icon(
                      icon: const Icon(Icons.data_object, size: 18),
                      label: const Text('Raw frames'),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.of(this.context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => FrameInspector(connection: c),
                          ),
                        );
                      },
                    ),
                    const Divider(),
                  ],
                  LabelledSlider(
                    label: 'Dwell at each end',
                    value: _settingsFor(EkKind.slider).dwellSeconds,
                    min: PanelSettings.dwellMin,
                    max: PanelSettings.dwellMax,
                    display: _settingsFor(EkKind.slider).dwellSeconds < 0.5
                        ? 'none'
                        : '${_settingsFor(EkKind.slider).dwellSeconds.toStringAsFixed(0)} s',
                    onChanged: (v) {
                      for (final c in widget.connections) {
                        update(c.kind,
                            _settingsFor(c.kind).copyWith(dwellSeconds: v));
                      }
                    },
                  ),
                  const Caution(
                    'Matching the two axes so they arrive together means '
                    'tuning each speed until their leg durations agree — the '
                    'per-device sliders above are for that.',
                  ),
                  Gap.md,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value, required this.onChanged});

  final String label;
  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 6),
            child: Slider(
              value: value.clamp(1, 100),
              min: 1,
              max: 100,
              onChanged: onChanged,
            ),
          ),
        ),
        Container(
          width: 44,
          alignment: Alignment.center,
          child: Text('${value.round()}%',
              style: TextStyle(fontSize: 12, color: scheme.primary)),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.onTap, this.active = false});

  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: active
            ? scheme.primary
            : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                letterSpacing: 0.6,
                color: onTap == null
                    ? scheme.outline
                    : (active ? scheme.onPrimary : scheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          Text(body, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
