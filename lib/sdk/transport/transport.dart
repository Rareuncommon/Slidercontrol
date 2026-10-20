/// The radio, abstracted: finding units and holding a link to one.
///
/// Ported from `edelkrone/transport/{base,_ble_core}.py`. The SDK's desktop
/// implementation uses `bleak`; `flutter_blue_transport.dart` implements
/// this over flutter_blue_plus, and the tests implement it over nothing.
///
/// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
library;

import 'dart:async';

import '../devices/registry.dart';
import '../log.dart';
import '../protocol/generated/moco.dart';
import '../session/core.dart';

enum TransportFailure {
  permissionDenied,
  adapterUnavailable,
  connectionFailed,
  characteristicNotFound,
  notConnected,
  timeout,
}

class TransportError implements Exception {
  TransportError(this.failure, this.message, {this.cause});
  final TransportFailure failure;
  final String message;
  final Object? cause;

  @override
  String toString() => 'TransportError(${failure.name}): $message${cause == null ? '' : ' -- $cause'}';
}

/// An open link to one unit. In a layout this is the leader; its modules are
/// reached through it.
abstract class DeviceLink {
  EdelkroneDevice get device;
  bool get isConnected;

  /// True when the link comes up, false when it goes down. A drop is reported
  /// here at once; nothing reconnects by itself.
  Stream<bool> get connectionChanges;

  Stream<List<int>> notifications(Channel channel);

  /// Writes one packet, with response, as the SDK does.
  Future<void> write(Channel channel, List<int> packet);

  Future<void> requestLowLatency();
  Future<void> disconnect();
}

abstract class Transport {
  /// The units currently visible, republished as the scan proceeds.
  Stream<List<EdelkroneDevice>> get devices;
  List<EdelkroneDevice> get current;
  bool get isScanning;

  /// The SDK does not request Bluetooth permission; the app must hold it
  /// before calling this.
  Future<void> startScan();
  Future<void> stopScan();
  void clearDevices();
  Future<DeviceLink> connect(EdelkroneDevice device);
  Future<void> dispose();
}

/// The service-data UUID every edelkrone advertisement uses.
const edelkroneAdvServiceUuid = '00000000-0000-1000-8000-00805f9b34fb';
const _advExactBytes = 13;

String uuidSuffix(String uuid) {
  final hexed = uuid.replaceAll('-', '').toLowerCase();
  return hexed.length < 4 ? hexed : hexed.substring(hexed.length - 4);
}

List<int>? serviceAdvData(Map<String, List<int>> serviceData, String serviceUuid) {
  if (serviceData.isEmpty) return null;
  if (serviceUuid.isNotEmpty) {
    final target = serviceUuid.toLowerCase();
    for (final e in serviceData.entries) {
      if (e.key.toLowerCase() == target) return e.value;
    }
    final suffix = uuidSuffix(serviceUuid);
    for (final e in serviceData.entries) {
      if (uuidSuffix(e.key) == suffix) return e.value;
    }
  }
  return serviceData.values.first;
}

bool looksLikeEdelkrone(Map<String, List<int>> serviceData) {
  final target = uuidSuffix(edelkroneAdvServiceUuid);
  return serviceData.entries.any((e) => uuidSuffix(e.key) == target && e.value.length == _advExactBytes);
}

const noSignal = -127;

int smoothRssi(int previous, int reading, double factor) {
  if (reading >= 0) return previous;
  if (previous >= 0 || previous == noSignal) return reading;
  return (factor * reading + (1 - factor) * previous).toInt();
}

/// The list of units in range, built from advertisements. Shared by every
/// transport, so recognition is identical whatever the radio.
class DeviceBook {
  DeviceBook({this.deviceTimeout = 3.0, this.rssiSmoothing = 0.2});

  final double deviceTimeout;
  final double rssiSmoothing;

  final _devices = <EdelkroneDevice>[];
  final _lastSeen = <String, DateTime>{};
  final _list = StreamController<List<EdelkroneDevice>>.broadcast();
  final _unnamed = <String>{};

  Stream<List<EdelkroneDevice>> get devices => _list.stream;
  List<EdelkroneDevice> get current => List.unmodifiable(_devices);

  /// Takes one advertisement. Returns the unit it describes, or null if it
  /// is not an edelkrone unit this SDK knows.
  EdelkroneDevice? ingest({
    required String id,
    required String advertisedName,
    required Map<String, List<int>> serviceData,
    required int rssi,
  }) {
    final model = identifyEdelkroneDevice(advertisedName);
    if (model == null) {
      if (advertisedName.isNotEmpty && looksLikeEdelkrone(serviceData) && _unnamed.add(advertisedName)) {
        EdelkroneLog.warning(() => 'an advertisement shaped like edelkrone\'s carries the name '
            '"$advertisedName", which is not in the device table');
      }
      return null;
    }
    final raw = serviceAdvData(serviceData, model.serviceUuid);
    if (raw == null || raw.isEmpty) return null;
    final LibEdelkroneMocoAdvData adv;
    try {
      adv = EdelkroneMoco.advParse(List<int>.of(raw));
    } catch (e) {
      EdelkroneLog.debug(() => 'unreadable advertisement from $advertisedName: $e');
      return null;
    }
    if (adv.setup == EdlSetup.IGNORE || adv.setup == EdlSetup.BOOTING_UP) return null;

    final i = _devices.indexWhere((d) => _sameMac(d.advData.mac, adv.mac));
    final existing = i < 0 ? null : _devices[i];
    final candidate = EdelkroneDevice(
      id: id,
      model: model,
      advData: adv,
      rssi: existing?.rssi ?? (rssi < 0 ? rssi : noSignal),
    );
    if (shouldHideFromDeviceScanner(candidate)) {
      if (existing != null) {
        _devices.removeAt(i);
        _publish();
      }
      return null;
    }
    _lastSeen[candidate.mac] = DateTime.now();
    if (existing == null) {
      _devices.add(candidate);
      _publish();
      return candidate;
    }
    final updated = existing.withAdv(adv, smoothRssi(existing.rssi, rssi, rssiSmoothing));
    _devices[i] = updated;
    _publish();
    return updated;
  }

  /// Drops units not heard from within [deviceTimeout].
  bool sweep() {
    final now = DateTime.now();
    final before = _devices.length;
    _devices.removeWhere((d) {
      final seen = _lastSeen[d.mac];
      return seen == null || now.difference(seen).inMilliseconds > deviceTimeout * 1000;
    });
    if (_devices.length == before) return false;
    _publish();
    return true;
  }

  void clear() {
    _devices.clear();
    _publish();
  }

  void close() => _list.close();

  void _publish() {
    if (!_list.isClosed) _list.add(List.unmodifiable(_devices));
  }
}

bool _sameMac(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
