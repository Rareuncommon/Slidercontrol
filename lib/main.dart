/// Stage 2: transport check.
///
/// This screen is deliberately READ-ONLY — it scans, connects, polls and
/// displays telemetry, and sends no motion command of any kind. It exists to
/// prove the part of the stack that cannot be unit-tested: that the keepalive
/// actually makes a device report, and that the frames parse.
///
/// Jog, poses and ping-pong arrive in the next stages.
library;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble/ek_connection.dart';
import 'ble/ek_permissions.dart';
import 'ble/ek_scanner.dart';
import 'ek_protocol.dart';

void main() {
  runApp(const SlidercontrolApp());
}

class SlidercontrolApp extends StatelessWidget {
  const SlidercontrolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Slidercontrol',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const DeviceListPage(),
    );
  }
}

class DeviceListPage extends StatefulWidget {
  const DeviceListPage({super.key});

  @override
  State<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends State<DeviceListPage>
    with WidgetsBindingObserver {
  final _scanner = EkScanner();
  final _connections = <String, EkConnection>{};

  List<EkDiscovered> _found = const [];
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanner.devices.listen((d) {
      if (mounted) setState(() => _found = d);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Fire-and-forget: dispose() cannot await, but each connection sends its
    // stop before dropping the link.
    for (final c in _connections.values) {
      c.dispose();
    }
    _scanner.dispose();
    super.dispose();
  }

  /// Safety: never leave a motor running because the app went away.
  ///
  /// A device left mid-move keeps executing and holds torque, locking the
  /// carriage (§7). Nothing on this screen commands motion yet, but the hook
  /// belongs here from the start rather than being added once it can bite.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      for (final c in _connections.values) {
        if (c.snapshot.isReady) {
          c.stopMotion().catchError((Object _) {});
        }
      }
    }
  }

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (await FlutterBluePlus.isSupported == false) {
        setState(() => _message = 'Bluetooth is not supported on this device.');
        return;
      }
      final denied = await EkPermissions.request();
      if (denied != null) {
        setState(() => _message = denied);
        return;
      }
      await _scanner.start();
    } catch (e) {
      setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(EkDiscovered d) async {
    final existing = _connections[d.id];
    if (existing != null) {
      await existing.dispose();
      setState(() => _connections.remove(d.id));
      return;
    }

    final conn = EkConnection(
      device: d.device,
      profile: d.profile,
      name: d.advertisedName,
    );
    setState(() => _connections[d.id] = conn);
    conn.snapshots.listen((_) {
      if (mounted) setState(() {});
    });

    try {
      await _scanner.stop();
      await conn.connect();
    } catch (e) {
      if (mounted) setState(() => _message = 'Connect failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Slidercontrol — transport check'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.search),
            tooltip: 'Scan',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_message != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(12),
              child: Text(
                _message!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Read-only. This build sends no motion commands.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _found.isEmpty
                ? const Center(child: Text('No edelkrone devices found yet.\n'
                    'Power the devices on and tap the search icon.',
                    textAlign: TextAlign.center))
                : ListView.builder(
                    itemCount: _found.length,
                    itemBuilder: (_, i) {
                      final d = _found[i];
                      return _DeviceTile(
                        discovered: d,
                        connection: _connections[d.id],
                        onToggle: () => _toggle(d),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.discovered,
    required this.connection,
    required this.onToggle,
  });

  final EkDiscovered discovered;
  final EkConnection? connection;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final snap = connection?.snapshot;
    final connected = snap?.isReady ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(discovered.profile.kind == EkKind.slider
                    ? Icons.linear_scale
                    : Icons.threesixty),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(discovered.advertisedName,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        '${discovered.profile.name} · ${discovered.rssi} dBm',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: onToggle,
                  child: Text(connection == null ? 'Connect' : 'Disconnect'),
                ),
              ],
            ),
            if (snap != null) ...[
              const Divider(),
              _kv('link', snap.link.name),
              _kv('reporting', snap.isReporting ? 'yes' : 'NO — check keepalive'),
              _kv('state', snap.state.name),
              _kv('battery',
                  snap.batteryPercent == null ? '—' : '${snap.batteryPercent}%'),
              _kv(
                'position',
                discovered.profile.kind == EkKind.head
                    ? 'not reported by the head (§5)'
                    : (snap.position?.toString() ?? '—'),
              ),
              _kv('frames', '${snap.framesReceived}'),
              if (snap.checksumFailures > 0)
                _kv('checksum failures', '${snap.checksumFailures}'),
              if (snap.error != null) _kv('error', snap.error!),
            ] else if (connected) ...[
              const Divider(),
              const Text('connecting…'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(k, style: const TextStyle(color: Colors.white54)),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
