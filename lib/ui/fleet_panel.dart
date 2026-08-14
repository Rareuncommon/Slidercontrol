/// Moving several devices together.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/ek_connection.dart';
import '../control/fleet.dart';
import '../control/leg_supervisor.dart';
import '../control/panel_settings.dart';
import '../control/panel_settings_store.dart';
import '../control/stop_registry.dart';

class FleetPanel extends StatefulWidget {
  const FleetPanel({super.key, required this.connections});

  final List<EkConnection> connections;

  @override
  State<FleetPanel> createState() => _FleetPanelState();
}

class _FleetPanelState extends State<FleetPanel> with WidgetsBindingObserver {
  FleetPingPong? _fleet;
  StreamSubscription<FleetStatus>? _statusSub;
  final _subs = <StreamSubscription<EkSnapshot>>[];

  /// Per-device settings, reused from each device's own panel so speed tuning
  /// done there carries over here.
  final _settings = <String, PanelSettings>{};

  double _dwellSeconds = 0;
  int _maxLegs = 0;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final c in widget.connections) {
      _subs.add(c.snapshots.listen((_) {
        if (mounted) setState(() {});
      }));
    }
    _loadSettings();
    StopRegistry.instance.register(this, _stopFleet);
  }

  Future<void> _loadSettings() async {
    for (final c in widget.connections) {
      final s = await PanelSettingsStore(c.kind.name).load();
      if (!mounted) return;
      setState(() => _settings[c.kind.name] = s);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    StopRegistry.instance.unregister(this);
    _statusSub?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _fleet?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _stopFleet();
    }
  }

  List<FleetMember> _members() {
    return [
      for (final c in widget.connections)
        FleetMember(
          target: c,
          name: c.name.isEmpty ? c.profile.name : c.name,
          motion: (_settings[c.kind.name] ?? const PanelSettings()).motion,
          timings: LegTimings(
            settle: (_settings[c.kind.name] ?? const PanelSettings()).settle,
            blindLeg:
                (_settings[c.kind.name] ?? const PanelSettings()).blindLeg,
          ),
        ),
    ];
  }

  Future<void> _stopFleet() async {
    await _fleet?.stop();
    // Belt and braces: stop each device directly too, in case the fleet was
    // never started but something else left a device moving.
    for (final c in widget.connections) {
      try {
        await c.stopMotion();
      } catch (_) {
        // Reported by whichever path is watching; nothing more to do here.
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<List<String>> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final failures = await action();
      if (mounted) {
        setState(() => _error = failures.isEmpty ? null : failures.join('\n'));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle() async {
    final fleet = _fleet;
    if (fleet != null && fleet.isRunning) {
      await _stopFleet();
      return;
    }

    final next = FleetPingPong(members: _members());
    await _statusSub?.cancel();
    _statusSub = next.statuses.listen((_) {
      if (mounted) setState(() {});
    });
    setState(() {
      _fleet = next;
      _error = null;
    });

    unawaited(next
        .start(
      dwell: Duration(milliseconds: (_dwellSeconds * 1000).round()),
      maxLegs: _maxLegs,
    )
        .catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    }));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _fleet?.status;
    final running = _fleet?.isRunning ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Move together')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Host-side coordination',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'This is not the official app’s paired-keypose mode — that '
                    'path was never captured (§8). Each device gets an ordinary '
                    'pose recall at the same moment, and no device starts its '
                    'next leg until every device has finished this one.\n\n'
                    'Within a leg the axes run at their own rates and can '
                    'drift apart. To make them arrive together, tune each '
                    'device’s speed on its own panel until the leg durations '
                    'match.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 64,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => StopRegistry.instance.stopAll(),
              icon: const Icon(Icons.stop_circle, size: 28),
              label: const Text('STOP  ·  Esc',
                  style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(height: 24),
          Text('Devices', style: theme.textTheme.titleMedium),
          for (final c in widget.connections)
            ListTile(
              dense: true,
              leading: Icon(c.snapshot.isReady
                  ? Icons.check_circle_outline
                  : Icons.error_outline),
              title: Text(c.name.isEmpty ? c.profile.name : c.name),
              subtitle: Text(
                '${c.snapshot.link.name} · '
                'speed ${(_settings[c.kind.name] ?? const PanelSettings()).motion.speedPercent.round()}%'
                '${status?.memberPhases[c.name] != null ? ' · ${status!.memberPhases[c.name]!.name}' : ''}',
              ),
            ),
          const SizedBox(height: 24),
          Text('Poses', style: theme.textTheme.titleMedium),
          Text(
            'Each device stores its own axis in the slot; there is no combined '
            'keypose. Recall the same slot on all of them to return to this '
            'arrangement.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final slot in [0, 1])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(width: 70, child: Text('Slot $slot')),
                  OutlinedButton.icon(
                    onPressed: _busy || running
                        ? null
                        : () => _run(() => FleetPingPong(members: _members())
                            .saveAll(slot)),
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text('Save both'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: _busy || running
                        ? null
                        : () => _run(() => FleetPingPong(members: _members())
                            .recallAll(slot)),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Recall both'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Text('Synchronised ping-pong', style: theme.textTheme.titleMedium),
          Text('Dwell at each end — '
              '${_dwellSeconds < 0.5 ? 'none' : '${_dwellSeconds.toStringAsFixed(0)} s'}',
              style: theme.textTheme.bodySmall),
          Slider(
            value: _dwellSeconds,
            min: 0,
            max: 30,
            onChanged:
                running ? null : (v) => setState(() => _dwellSeconds = v),
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
                ],
                onChanged:
                    running ? null : (v) => setState(() => _maxLegs = v ?? 0),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _toggle,
                icon: Icon(running ? Icons.stop : Icons.repeat),
                label: Text(running ? 'Stop' : 'Start together'),
              ),
              const SizedBox(width: 16),
              if (status != null && (running || status.legs > 0))
                Text('${status.phase.name} · ${status.legs} legs'),
            ],
          ),
          if (status?.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(status!.error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!,
                    style: TextStyle(
                        color: theme.colorScheme.onErrorContainer)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
