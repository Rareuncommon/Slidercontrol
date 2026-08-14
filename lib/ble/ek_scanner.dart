/// Scanning for edelkrone devices.
///
/// Devices are matched on their advertised name. CoreBluetooth (macOS/iOS)
/// hides MAC addresses and hands out per-host UUIDs, so a device identifier
/// obtained on one machine is meaningless on another — the name is the only
/// portable way to recognise a unit. See EDELKRONE_PROTOCOL.md §9.
library;

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ek_protocol.dart';
import 'ek_names.dart';

/// One edelkrone device seen in a scan.
class EkDiscovered {
  final BluetoothDevice device;
  final EkProfile profile;
  final String advertisedName;
  final int rssi;

  const EkDiscovered({
    required this.device,
    required this.profile,
    required this.advertisedName,
    required this.rssi,
  });

  /// Stable within one host, but NOT across hosts on Apple platforms.
  String get id => device.remoteId.str;
}

class EkScanner {
  final _controller = StreamController<List<EkDiscovered>>.broadcast();
  StreamSubscription<List<ScanResult>>? _sub;

  /// The edelkrone devices currently visible, newest scan wins.
  Stream<List<EkDiscovered>> get devices => _controller.stream;

  List<EkDiscovered> _latest = const [];
  List<EkDiscovered> get latest => _latest;

  bool get isScanning => FlutterBluePlus.isScanningNow;

  /// Starts a scan. [timeout] null scans until [stop].
  ///
  /// The scan is unfiltered rather than filtered on the service UUIDs, because
  /// a peripheral is not obliged to put its service UUIDs in the advertisement
  /// and these do not. Filtering by name happens here instead.
  Future<void> start({Duration? timeout = const Duration(seconds: 15)}) async {
    await _sub?.cancel();
    _sub = FlutterBluePlus.scanResults.listen(
      (results) {
        _latest = _recognise(results);
        if (!_controller.isClosed) _controller.add(_latest);
      },
      onError: (Object e) {
        if (!_controller.isClosed) _controller.addError(e);
      },
    );

    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: false,
    );
  }

  Future<void> stop() async {
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  static List<EkDiscovered> _recognise(List<ScanResult> results) {
    final out = <EkDiscovered>[];
    for (final r in results) {
      // advName is what the peripheral put in this advertisement; platformName
      // is the OS's cached name for an already-known device. Prefer the former
      // and fall back to the latter, which matters for a device the host has
      // bonded with before.
      final name = r.advertisementData.advName.isNotEmpty
          ? r.advertisementData.advName
          : r.device.platformName;
      if (!isEdelkroneName(name)) continue;
      out.add(EkDiscovered(
        device: r.device,
        profile: EkProfile.forName(name),
        advertisedName: name,
        rssi: r.rssi,
      ));
    }
    out.sort((a, b) => a.advertisedName.compareTo(b.advertisedName));
    return out;
  }
}
