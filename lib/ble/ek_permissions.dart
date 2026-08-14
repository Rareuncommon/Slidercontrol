/// Runtime permission handling.
///
/// Only Android needs anything at runtime. On iOS and macOS CoreBluetooth
/// raises its own prompt the first time the radio is used, driven by the
/// usage-description string in Info.plist and the Bluetooth entitlement — so
/// there is nothing to request from Dart, and asking would return
/// [PermissionStatus.denied] on platforms where the permission does not exist.
library;

import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart';

class EkPermissions {
  /// Requests everything scanning needs. Returns null on success, or a
  /// human-readable reason on failure.
  ///
  /// `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` exist from Android 12 (API 31).
  /// Below that, a BLE scan is gated on location permission instead. Requesting
  /// all three is harmless: permission_handler reports the ones that do not
  /// apply to the running OS version as granted.
  static Future<String?> request() async {
    if (!Platform.isAndroid) return null;

    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final permanentlyDenied = <String>[];
    final denied = <String>[];

    results.forEach((permission, status) {
      // On Android 12+ the location permission is not required for a scan that
      // declares `neverForLocation`, and on Android 11 and below the bluetooth*
      // permissions do not exist. Either way a refusal of one of the two groups
      // is only fatal if the other group was also refused, which the caller
      // discovers when the scan returns nothing.
      if (status.isPermanentlyDenied) {
        permanentlyDenied.add(_label(permission));
      } else if (!status.isGranted && !status.isLimited) {
        denied.add(_label(permission));
      }
    });

    // Scanning genuinely cannot work without these two on Android 12+.
    final scanBlocked = results[Permission.bluetoothScan]?.isGranted == false &&
        results[Permission.locationWhenInUse]?.isGranted == false;
    final connectBlocked =
        results[Permission.bluetoothConnect]?.isGranted == false;

    if (!scanBlocked && !connectBlocked) return null;

    if (permanentlyDenied.isNotEmpty) {
      return 'Permanently denied: ${permanentlyDenied.join(', ')}. '
          'Enable them in Settings, then try again.';
    }
    return 'Denied: ${denied.join(', ')}. Bluetooth scanning needs these.';
  }

  /// Opens the OS settings page, for the permanently-denied case.
  static Future<bool> openSettings() => openAppSettings();

  static String _label(Permission p) {
    if (p == Permission.bluetoothScan) return 'Bluetooth scan';
    if (p == Permission.bluetoothConnect) return 'Bluetooth connect';
    if (p == Permission.locationWhenInUse) return 'Location';
    return p.toString();
  }
}
