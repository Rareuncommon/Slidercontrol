/// Slidercontrol — BLE control for edelkrone SliderPLUS v6 and HeadONE.
///
/// See EDELKRONE_PROTOCOL.md for the protocol this speaks, and §8 for what is
/// still undecoded.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble/ek_adapter.dart';
import 'ble/ek_connection.dart';
import 'ble/ek_permissions.dart';
import 'ble/ek_scanner.dart';
import 'control/stop_registry.dart';
import 'ek_protocol.dart';
import 'ui/device_panel.dart';
import 'ui/emergency_stop.dart';

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
      builder: (context, child) => EmergencyStopKeys(
        registry: StopRegistry.instance,
        child: child ?? const SizedBox.shrink(),
      ),
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
  final _snapSubs = <String, StreamSubscription<EkSnapshot>>{};

  /// Remembered so a connected device stays in the list.
  ///
  /// A connected BLE peripheral stops advertising, so it does not appear in any
  /// subsequent scan. Without this, rescanning made a connected — possibly
  /// moving — device disappear from the UI along with its disconnect button
  /// and its control panel.
  final _connectedInfo = <String, EkDiscovered>{};

  List<EkDiscovered> _found = const [];

  /// Everything to show: whatever the last scan saw, plus anything connected.
  List<EkDiscovered> get _visible {
    final byId = <String, EkDiscovered>{
      for (final d in _found) d.id: d,
    };
    for (final entry in _connectedInfo.entries) {
      byId.putIfAbsent(entry.key, () => entry.value);
    }
    final out = byId.values.toList()
      ..sort((a, b) => a.advertisedName.compareTo(b.advertisedName));
    return out;
  }
  String? _message;
  bool _needsSettings = false;
  bool _busy = false;

  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  BluetoothAdapterState _adapter = BluetoothAdapterState.unknown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanner.devices.listen((d) {
      if (mounted) setState(() => _found = d);
    });

    // Listening from startup is what triggers CoreBluetooth to initialise, and
    // therefore what raises the macOS Bluetooth permission prompt — before the
    // user presses anything.
    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      if (!mounted) return;
      setState(() {
        _adapter = s;
        // Clear a stale complaint once the adapter is genuinely usable.
        if (s == BluetoothAdapterState.on && _needsSettings) {
          _message = null;
          _needsSettings = false;
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _adapterSub?.cancel();
    for (final s in _snapSubs.values) {
      s.cancel();
    }
    // Each connection sends its stop before dropping the link.
    for (final c in _connections.values) {
      StopRegistry.instance.unregister(c);
      c.dispose();
    }
    _scanner.dispose();
    super.dispose();
  }

  /// Backgrounding the app stops every connected device.
  ///
  /// A device left mid-move keeps executing and holds torque, leaving the
  /// carriage locked and unmovable by hand (§7).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      StopRegistry.instance.stopAll().catchError((Object _) => <String>[]);
    }
  }

  /// permission_handler cannot open settings on every platform, so a failure
  /// falls back to telling the user where to go rather than a dead button.
  Future<void> _openSettings() async {
    final opened = await EkPermissions.openSettings();
    if (!mounted || opened) return;
    setState(() => _message =
        'Could not open Settings automatically. Open System Settings → '
        'Privacy & Security → Bluetooth and enable Slidercontrol, then scan '
        'again.');
  }

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _message = null;
      _needsSettings = false;
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

      // Wait for CoreBluetooth to actually know its own state. Scanning while
      // it is still `unknown` throws "bluetooth must be turned on" even when
      // Bluetooth is on and about to report itself as such.
      final status = await EkAdapter.waitUntilReady();
      if (!mounted) return;
      if (!status.canScan) {
        setState(() {
          _message = status.problem;
          _needsSettings = status.needsSettings;
        });
        return;
      }

      await _scanner.start();
    } catch (e) {
      setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(EkDiscovered d) async {
    final conn = EkConnection(
      device: d.device,
      profile: d.profile,
      name: d.advertisedName,
    );
    setState(() {
      _connections[d.id] = conn;
      _connectedInfo[d.id] = d;
    });
    _snapSubs[d.id] = conn.snapshots.listen((_) {
      if (mounted) setState(() {});
    });
    StopRegistry.instance.register(conn, conn.stopMotion);

    try {
      await _scanner.stop();
      await conn.connect();
    } catch (e) {
      if (mounted) setState(() => _message = 'Connect failed: $e');
    }
  }

  Future<void> _disconnect(String id) async {
    await _snapSubs.remove(id)?.cancel();
    final c = _connections.remove(id);
    if (c != null) StopRegistry.instance.unregister(c);
    setState(() => _connectedInfo.remove(id));
    await c?.dispose();
  }

  /// Stops every connected device at once.
  ///
  /// The button you want when something is moving and you do not want to be
  /// navigating to find the right screen first.
  Future<void> _stopAll() async {
    final n = StopRegistry.instance.count;
    if (n == 0) return;
    final failures = await StopRegistry.instance.stopAll();
    if (!mounted) return;
    setState(() => _message = failures.isEmpty ? null : failures.join('\n'));
    if (failures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stopped')),
      );
    }
  }

  void _open(EkConnection c) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DevicePanel(connection: c)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Slidercontrol'),
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
          // Shown whenever anything is connected at all, including while a
          // link is down and reconnecting. Hiding the stop control exactly when
          // the link is unreliable is the wrong instinct: pressing it then
          // reports why it could not be sent, which beats offering nothing.
          if (_connections.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: SizedBox(
                height: 56,
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _stopAll,
                  icon: const Icon(Icons.stop_circle),
                  label: const Text('STOP ALL  ·  Esc',
                      style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
          if (_message != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  if (_needsSettings)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          FilledButton.tonal(
                            onPressed: _openSettings,
                            child: const Text('Open Settings'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: _busy ? null : _scan,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (_adapter != BluetoothAdapterState.on)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text('Bluetooth: ${_adapter.name}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _visible.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No edelkrone devices found yet.\n'
                        'Power the devices on and tap the search icon.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _visible.length,
                    itemBuilder: (_, i) {
                      final d = _visible[i];
                      final c = _connections[d.id];
                      return _DeviceTile(
                        discovered: d,
                        connection: c,
                        onConnect: () => _connect(d),
                        onDisconnect: () => _disconnect(d.id),
                        onOpen: c != null && c.snapshot.isReady
                            ? () => _open(c)
                            : null,
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
    required this.onConnect,
    required this.onDisconnect,
    required this.onOpen,
  });

  final EkDiscovered discovered;
  final EkConnection? connection;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final s = connection?.snapshot;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onOpen,
        leading: Icon(discovered.profile.kind == EkKind.slider
            ? Icons.linear_scale
            : Icons.threesixty),
        title: Text(discovered.advertisedName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${discovered.profile.name} · ${discovered.rssi} dBm'),
            if (s != null)
              Row(
                children: [
                  Icon(
                    s.isReporting ? Icons.circle : Icons.circle_outlined,
                    size: 10,
                    color: s.isReporting ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Text(s.link.name),
                  if (s.batteryPercent != null) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.battery_full, size: 14),
                    Text('${s.batteryPercent}%'),
                  ],
                ],
              ),
            if (s != null && s.isReady && !s.isReporting)
              Text('no telemetry — check the keepalive',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.orange)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onOpen != null)
              IconButton(
                onPressed: onOpen,
                icon: const Icon(Icons.tune),
                tooltip: 'Controls',
              ),
            FilledButton.tonal(
              onPressed: connection == null ? onConnect : onDisconnect,
              child: Text(connection == null ? 'Connect' : 'Disconnect'),
            ),
          ],
        ),
      ),
    );
  }
}
