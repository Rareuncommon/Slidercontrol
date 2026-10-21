/// The SDK's [Transport] over flutter_blue_plus, for Android, iOS and macOS.
///
/// The SDK ships a desktop transport over `bleak`; this is the mobile one.
/// Recognition goes through the same [DeviceBook] the SDK uses, so a unit is
/// identified identically whatever the radio.
///
/// Two lessons from this app's earlier BLE layer are kept, because they were
/// learned on this hardware:
///
///  - `connectionState` pushes its current value to every new listener — for
///    a unit not yet connected, that is `disconnected`. Link changes are
///    ignored until `connect()` has returned, or every connect would report a
///    drop.
///  - CoreBluetooth starts in `unknown`; scanning before it settles throws.
library;

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../devices/registry.dart';
import '../session/core.dart';
import 'transport.dart';

class FlutterBlueTransport implements Transport {
  FlutterBlueTransport();

  final _book = DeviceBook();
  final _peripherals = <String, BluetoothDevice>{};
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _sweeper;
  bool _scanning = false;
  final _links = <_Link>[];

  @override
  Stream<List<EdelkroneDevice>> get devices => _book.devices;

  @override
  List<EdelkroneDevice> get current => _book.current;

  @override
  bool get isScanning => _scanning;

  @override
  Future<void> startScan() async {
    if (_scanning) return;
    await _adapterReady();
    _scanning = true;
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
        final serviceData = {
          for (final e in r.advertisementData.serviceData.entries) e.key.str128: List<int>.of(e.value),
        };
        final id = r.device.remoteId.str;
        final seen = _book.ingest(id: id, advertisedName: name, serviceData: serviceData, rssi: r.rssi);
        if (seen != null) _peripherals[id] = r.device;
      }
    });
    _sweeper?.cancel();
    _sweeper = Timer.periodic(const Duration(seconds: 1), (_) => _book.sweep());
    try {
      await FlutterBluePlus.startScan(androidUsesFineLocation: false, continuousUpdates: true);
    } catch (e) {
      _scanning = false;
      throw TransportError(TransportFailure.adapterUnavailable, 'could not start scanning: $e', cause: e);
    }
  }

  Future<void> _adapterReady() async {
    var state = FlutterBluePlus.adapterStateNow;
    if (state == BluetoothAdapterState.unknown || state == BluetoothAdapterState.turningOn) {
      try {
        state = await FlutterBluePlus.adapterState
            .firstWhere((s) => s != BluetoothAdapterState.unknown && s != BluetoothAdapterState.turningOn)
            .timeout(const Duration(seconds: 15));
      } on TimeoutException {
        throw TransportError(
          TransportFailure.permissionDenied,
          'Bluetooth did not report its state. If the system is asking for Bluetooth permission, allow it and try again.',
        );
      }
    }
    switch (state) {
      case BluetoothAdapterState.on:
        return;
      case BluetoothAdapterState.unauthorized:
        throw TransportError(
          TransportFailure.permissionDenied,
          'Bluetooth permission has not been granted to this app.',
        );
      case BluetoothAdapterState.unavailable:
        throw TransportError(TransportFailure.adapterUnavailable, 'This device has no Bluetooth adapter.');
      default:
        throw TransportError(TransportFailure.adapterUnavailable, 'Bluetooth is turned off. Turn it on and try again.');
    }
  }

  @override
  Future<void> stopScan() async {
    _scanning = false;
    _sweeper?.cancel();
    _sweeper = null;
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
  }

  @override
  void clearDevices() => _book.clear();

  @override
  Future<DeviceLink> connect(EdelkroneDevice device) async {
    final peripheral = _peripherals[device.id] ?? BluetoothDevice.fromId(device.id);
    final link = _Link(device, peripheral);
    await link.open();
    _links.add(link);
    return link;
  }

  @override
  Future<void> dispose() async {
    await stopScan();
    for (final l in List.of(_links)) {
      await l.disconnect();
    }
    _links.clear();
    _book.close();
  }
}

class _Link implements DeviceLink {
  _Link(this.device, this._peripheral);

  @override
  final EdelkroneDevice device;
  final BluetoothDevice _peripheral;

  final _changes = StreamController<bool>.broadcast();
  final _rx = {for (final c in Channel.values) c: StreamController<List<int>>.broadcast()};
  final _writers = <Channel, BluetoothCharacteristic>{};
  final _subs = <StreamSubscription<Object?>>[];
  bool _established = false;
  bool _up = false;
  Future<void> _writeChain = Future.value();

  @override
  bool get isConnected => _up;

  @override
  Stream<bool> get connectionChanges => _changes.stream;

  @override
  Stream<List<int>> notifications(Channel channel) => _rx[channel]!.stream;

  Future<void> open() async {
    _subs.add(
      _peripheral.connectionState.listen((s) {
        // The initial value pushed to a new listener is not news.
        if (!_established) return;
        final up = s == BluetoothConnectionState.connected;
        if (up == _up) return;
        _up = up;
        if (!_changes.isClosed) _changes.add(up);
      }),
    );
    try {
      // License.nonprofit per the flutter_blue_plus licence terms: personal
      // and nonprofit use. Commercial distribution needs License.commercial.
      await _peripheral.connect(license: License.nonprofit, timeout: const Duration(seconds: 20));
    } catch (e) {
      await _closeStreams();
      throw TransportError(TransportFailure.connectionFailed, '${device.displayName}: $e', cause: e);
    }
    _established = true;
    _up = true;

    final model = device.model;
    final wanted = {
      (Channel.data, true): model.dataWriteUuid,
      (Channel.data, false): model.dataReadUuid,
      (Channel.ioCtrl, true): model.ioctlWriteUuid,
      (Channel.ioCtrl, false): model.ioctlReadUuid,
    };
    try {
      final services = await _peripheral.discoverServices();
      final found = <(Channel, bool), BluetoothCharacteristic>{};
      for (final s in services) {
        for (final c in s.characteristics) {
          for (final e in wanted.entries) {
            if (c.uuid == Guid(e.value)) found[e.key] = c;
          }
        }
      }
      final missing = [
        for (final e in wanted.entries)
          if (!found.containsKey(e.key)) '${e.key.$1.name}/${e.key.$2 ? 'write' : 'read'}(${e.value})',
      ];
      if (missing.isNotEmpty) {
        throw TransportError(
          TransportFailure.characteristicNotFound,
          '${device.displayName} does not expose: ${missing.join(', ')}. The firmware may be outdated',
        );
      }
      for (final ch in Channel.values) {
        _writers[ch] = found[(ch, true)]!;
        final reader = found[(ch, false)]!;
        await reader.setNotifyValue(true);
        _subs.add(
          reader.onValueReceived.listen((v) {
            final c = _rx[ch]!;
            if (!c.isClosed) c.add(List<int>.of(v));
          }),
        );
      }
    } catch (e) {
      await disconnect();
      if (e is TransportError) rethrow;
      throw TransportError(TransportFailure.connectionFailed, '${device.displayName}: $e', cause: e);
    }
    if (!_changes.isClosed) _changes.add(true);
  }

  /// Writes are serialised: a GATT write must finish before the next starts.
  @override
  Future<void> write(Channel channel, List<int> packet) {
    final w = _writers[channel];
    if (w == null || !_up) {
      return Future.error(TransportError(TransportFailure.notConnected, '${device.displayName} is not connected'));
    }
    final next = _writeChain.then((_) async {
      try {
        await w.write(packet, withoutResponse: false);
      } catch (e) {
        throw TransportError(TransportFailure.connectionFailed, 'write failed: $e', cause: e);
      }
    });
    _writeChain = next.catchError((_) {});
    return next;
  }

  @override
  Future<void> requestLowLatency() async {
    try {
      await _peripheral.requestConnectionPriority(connectionPriorityRequest: ConnectionPriority.high);
    } catch (_) {
      // Android only; elsewhere the OS decides.
    }
  }

  @override
  Future<void> disconnect() async {
    final wasUp = _up;
    _up = false;
    _established = false;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    try {
      await _peripheral.disconnect();
    } catch (_) {
      // Already gone.
    }
    if (wasUp && !_changes.isClosed) _changes.add(false);
    await _closeStreams();
  }

  Future<void> _closeStreams() async {
    for (final c in _rx.values) {
      if (!c.isClosed) await c.close();
    }
    if (!_changes.isClosed) await _changes.close();
  }
}
