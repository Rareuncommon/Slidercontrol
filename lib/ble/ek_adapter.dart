/// Bluetooth adapter readiness.
///
/// CoreBluetooth does not know its own state synchronously. A freshly created
/// CBCentralManager starts in `CBManagerStateUnknown` and transitions to
/// `PoweredOn` (or `Unauthorized`, or `PoweredOff`) a moment later, via a
/// delegate callback. Scanning before that transition throws:
///
///     PlatformException(startScan, bluetooth must be turned on.
///     (CBManagerStateUnknown), null, null)
///
/// — which reads as "Bluetooth is off" but usually means "ask again in a
/// moment". The same callback is what raises the macOS permission prompt, so
/// waiting here is also what gives the user a chance to grant access.
library;

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// What to tell the user, and whether scanning can proceed.
class EkAdapterStatus {
  final BluetoothAdapterState state;

  /// Null when scanning can go ahead.
  final String? problem;

  /// True when the problem is one the OS settings can fix, so the UI can offer
  /// a shortcut there.
  final bool needsSettings;

  const EkAdapterStatus(this.state, {this.problem, this.needsSettings = false});

  bool get canScan => problem == null;
}

class EkAdapter {
  /// Waits for the adapter to report a state it is actually sure about.
  ///
  /// [timeout] only bounds the wait — a timeout is reported as still-unknown
  /// rather than as an error, because the usual cause is a permission prompt
  /// sitting on screen waiting to be answered.
  static Future<EkAdapterStatus> waitUntilReady({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    var state = FlutterBluePlus.adapterStateNow;

    if (state == BluetoothAdapterState.unknown ||
        state == BluetoothAdapterState.turningOn) {
      try {
        state = await FlutterBluePlus.adapterState
            .firstWhere((s) =>
                s != BluetoothAdapterState.unknown &&
                s != BluetoothAdapterState.turningOn)
            .timeout(timeout);
      } on TimeoutException {
        return const EkAdapterStatus(
          BluetoothAdapterState.unknown,
          problem: 'Bluetooth did not report its state. If macOS is asking for '
              'Bluetooth permission, allow it and scan again.',
          needsSettings: true,
        );
      }
    }

    return describe(state);
  }

  static EkAdapterStatus describe(BluetoothAdapterState state) {
    switch (state) {
      case BluetoothAdapterState.on:
        return EkAdapterStatus(state);

      case BluetoothAdapterState.off:
      case BluetoothAdapterState.turningOff:
        return EkAdapterStatus(
          state,
          problem: 'Bluetooth is turned off. Turn it on and scan again.',
        );

      case BluetoothAdapterState.unauthorized:
        return EkAdapterStatus(
          state,
          problem: 'Slidercontrol is not allowed to use Bluetooth. Grant it in '
              'System Settings → Privacy & Security → Bluetooth, then scan '
              'again.',
          needsSettings: true,
        );

      case BluetoothAdapterState.unavailable:
        return EkAdapterStatus(
          state,
          problem: 'This machine has no usable Bluetooth adapter.',
        );

      case BluetoothAdapterState.unknown:
      case BluetoothAdapterState.turningOn:
        return EkAdapterStatus(
          state,
          problem: 'Bluetooth is still starting up. Try again in a moment.',
        );
    }
  }
}
