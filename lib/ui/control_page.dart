/// The one place to be once devices are connected.
///
/// Everything reachable without navigating away: both devices side by side (or
/// stacked on a narrow window), the shared synchronised controls, and STOP ALL
/// pinned to the top.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/ek_connection.dart';
import '../control/fleet.dart';
import '../control/leg_supervisor.dart';
import '../control/panel_settings.dart';
import '../control/panel_settings_store.dart';
import '../control/stop_registry.dart';
import 'device_column.dart';
import 'ui_scale.dart';

/// Below this the columns stack instead of sitting side by side.
const _twoColumnBreakpoint = 900.0;

class ControlPage extends StatefulWidget {
  const ControlPage({super.key, required this.connections});

  final List<EkConnection> connections;

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> with WidgetsBindingObserver {
  final _columnKeys = <String, GlobalKey<DeviceColumnState>>{};
  final _subs = <StreamSubscription<EkSnapshot>>[];

  FleetPingPong? _fleet;
  StreamSubscription<FleetStatus>? _fleetSub;

  /// Shared across devices. Settle is a slider concept but lives here because
  /// it governs the synchronised run as a whole.
  double _settleMs = PanelSettings().settleMs;
  double _dwellSeconds = 0;
  int _fleetMaxLegs = 0;

  final _perKind = <String, PanelSettings>{};
  String? _error;
  bool _busy = false;

  Duration get _settle => Duration(milliseconds: _settleMs.round());
  Duration get _dwell =>
      Duration(milliseconds: (_dwellSeconds * 1000).round());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final c in widget.connections) {
      _columnKeys[c.device.remoteId.str] = GlobalKey<DeviceColumnState>();
      _subs.add(c.snapshots.listen((_) {
        if (mounted) setState(() {});
      }));
    }
    _loadShared();
    StopRegistry.instance.register(this, _stopFleetOnly);
  }

  Future<void> _loadShared() async {
    for (final c in widget.connections) {
      final s = await PanelSettingsStore(c.kind.name).load();
      if (!mounted) return;
      setState(() {
        _perKind[c.kind.name] = s;
        // Settle and dwell are shared; seed them from the first device that has
        // stored values rather than inventing a default.
        _settleMs = s.settleMs;
        if (_dwellSeconds == 0) _dwellSeconds = s.dwellSeconds;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    StopRegistry.instance.unregister(this);
    _fleetSub?.cancel();
    for (final s in _subs) {
      s.cancel();
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

  /// Only the fleet loop — each DeviceColumn registers its own stop separately,
  /// so StopRegistry.stopAll() covers both without this duplicating them.
  Future<void> _stopFleetOnly() async {
    await _fleet?.stop();
    if (mounted) setState(() {});
  }

  void _report(String message) {
    if (mounted) setState(() => _error = message);
  }

  List<EkConnection> get _ready =>
      widget.connections.where((c) => c.snapshot.isReady).toList();

  List<FleetMember> _members() => [
        for (final c in _ready)
          FleetMember(
            target: c,
            name: c.name.isEmpty ? c.profile.name : c.name,
            motion: (_perKind[c.kind.name] ?? const PanelSettings()).motion,
            timings: LegTimings(
              settle: _settle,
              blindLeg:
                  (_perKind[c.kind.name] ?? const PanelSettings()).blindLeg,
            ),
          ),
      ];

  Future<void> _runFleetAction(Future<List<String>> Function() action) async {
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

  Future<void> _toggleFleet() async {
    final fleet = _fleet;
    if (fleet != null && fleet.isRunning) {
      await _stopFleetOnly();
      return;
    }
    // Any individual loop must stop first, or two controllers would command the
    // same device.
    for (final key in _columnKeys.values) {
      final st = key.currentState;
      if (st != null && st.isPingPonging) await st.togglePingPong();
    }

    final next = FleetPingPong(members: _members());
    await _fleetSub?.cancel();
    _fleetSub = next.statuses.listen((_) {
      if (mounted) setState(() {});
    });
    setState(() {
      _fleet = next;
      _error = null;
    });
    unawaited(next
        .start(dwell: _dwell, maxLegs: _fleetMaxLegs)
        .catchError((Object e) => _report('$e')));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controls'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _twoColumnBreakpoint &&
              widget.connections.length > 1;
          return ListView(
            padding: Insets.page,
            children: [
              _stopBar(),
              if (_error != null) ...[
                Gap.md,
                ErrorBanner(_error!,
                    onDismiss: () => setState(() => _error = null)),
              ],
              Gap.lg,
              _shared(),
              Gap.lg,
              if (wide)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final c in widget.connections) ...[
                        Expanded(child: _column(c)),
                        if (c != widget.connections.last) Gap.wMd,
                      ],
                    ],
                  ),
                )
              else
                for (final c in widget.connections) ...[
                  _column(c),
                  Gap.md,
                ],
            ],
          );
        },
      ),
    );
  }

  Widget _column(EkConnection c) => DeviceColumn(
        key: _columnKeys[c.device.remoteId.str],
        connection: c,
        settle: _settle,
        dwell: _dwell,
        onError: _report,
      );

  Widget _stopBar() {
    return SizedBox(
      height: 64,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.red.shade700,
          foregroundColor: Colors.white,
        ),
        onPressed: () async {
          final failures = await StopRegistry.instance.stopAll();
          if (failures.isNotEmpty) _report(failures.join('\n'));
        },
        icon: const Icon(Icons.stop_circle, size: 28),
        label: const Text('STOP ALL  ·  Esc', style: TextStyle(fontSize: 20)),
      ),
    );
  }

  Widget _shared() {
    final fleet = _fleet;
    final running = fleet?.isRunning ?? false;
    final status = fleet?.status;
    final enoughDevices = _ready.length >= 2;

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: Insets.card,
        child: Section(
          title: 'Both devices together',
          note: 'Host-side coordination, not the official app’s paired-keypose '
              'mode — that path was never captured (§8). Each device gets an '
              'ordinary pose recall at the same moment, and none starts its '
              'next leg until all have finished this one.',
          children: [
            const Caution(
              'Within a leg the axes run at their own rates and can drift '
              'apart. To make them arrive together, match their speeds until '
              'the leg durations agree.',
            ),
            Gap.md,
            LabelledSlider(
              label: 'Settle — idle must hold this long before the next leg',
              value: _settleMs,
              min: PanelSettings.settleMin,
              max: PanelSettings.settleMax,
              display: '${_settleMs.round()} ms',
              onChanged:
                  running ? null : (v) => setState(() => _settleMs = v),
            ),
            LabelledSlider(
              label: 'Dwell at each end',
              value: _dwellSeconds,
              min: PanelSettings.dwellMin,
              max: PanelSettings.dwellMax,
              display: _dwellSeconds < 0.5
                  ? 'none — reverse immediately'
                  : '${_dwellSeconds.toStringAsFixed(0)} s',
              onChanged:
                  running ? null : (v) => setState(() => _dwellSeconds = v),
            ),
            Row(
              children: [
                const Text('Stop after'),
                Gap.wSm,
                DropdownButton<int>(
                  value: _fleetMaxLegs,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('unlimited')),
                    DropdownMenuItem(value: 2, child: Text('1 round trip')),
                    DropdownMenuItem(value: 4, child: Text('2 round trips')),
                    DropdownMenuItem(value: 10, child: Text('5 round trips')),
                  ],
                  onChanged: running
                      ? null
                      : (v) => setState(() => _fleetMaxLegs = v ?? 0),
                ),
              ],
            ),
            Gap.sm,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final slot in [0, 1]) ...[
                  OutlinedButton.icon(
                    onPressed: _busy || running || !enoughDevices
                        ? null
                        : () => _runFleetAction(
                            () => FleetPingPong(members: _members())
                                .saveAll(slot)),
                    icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                    label: Text('Save both → $slot'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _busy || running || !enoughDevices
                        ? null
                        : () => _runFleetAction(
                            () => FleetPingPong(members: _members())
                                .recallAll(slot)),
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: Text('Recall both → $slot'),
                  ),
                ],
              ],
            ),
            Gap.sm,
            Row(
              children: [
                FilledButton.icon(
                  onPressed:
                      _busy || !enoughDevices ? null : () => _toggleFleet(),
                  icon: Icon(running ? Icons.stop : Icons.sync_alt),
                  label: Text(running ? 'Stop together' : 'Start together'),
                ),
                Gap.wMd,
                if (status != null && (running || status.legs > 0))
                  Expanded(
                    child: Text(
                      '${status.phase.name} · leg ${status.legs}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            if (!enoughDevices)
              const Caution(
                'Connect both devices to move them together.',
              ),
            if (status?.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(status!.error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}
