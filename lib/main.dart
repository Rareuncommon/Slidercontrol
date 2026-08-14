/// Slidercontrol — BLE control for edelkrone SliderPLUS v6 and HeadONE.
///
/// See EDELKRONE_PROTOCOL.md for the protocol this speaks, and §8 for what is
/// still undecoded.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble/ek_connection.dart';
import 'ble/ek_permissions.dart';
import 'ble/ek_scanner.dart';
import 'ek_protocol.dart';
import 'ui/device_panel.dart';

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
  final _snapSubs = <String, StreamSubscription<EkSnapshot>>{};

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
    for (final s in _snapSubs.values) {
      s.cancel();
    }
    // Each connection sends its stop before dropping the link.
    for (final c in _connections.values) {
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

  Future<void> _connect(EkDiscovered d) async {
    final conn = EkConnection(
      device: d.device,
      profile: d.profile,
      name: d.advertisedName,
    );
    setState(() => _connections[d.id] = conn);
    _snapSubs[d.id] = conn.snapshots.listen((_) {
      if (mounted) setState(() {});
    });

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
    setState(() {});
    await c?.dispose();
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
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _found.isEmpty
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
                    itemCount: _found.length,
                    itemBuilder: (_, i) {
                      final d = _found[i];
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
