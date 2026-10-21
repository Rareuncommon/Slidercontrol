/// One edelkrone product, as the SDK describes it. Ported from
/// `edelkrone/devices/_model_type.py` and `firmware_compat.py`.
///
/// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
library;

import '../protocol/generated/moco.dart';

// ignore_for_file: constant_identifier_names

enum FirmwareType { TYPE1, TYPE2, TYPE3, TYPE4, RADIO }

/// A layout a model can lead: the setup it forms and the units it needs,
/// leader first.
class DeviceSetupSpec {
  const DeviceSetupSpec(this.setup, this.devices);

  final EdlSetup setup;
  final List<EdlDevice> devices;
}

class EdelkroneDeviceModel {
  const EdelkroneDeviceModel({
    required this.bleAdvName,
    required this.displayName,
    required this.deviceType,
    required this.serviceUuid,
    required this.dataWriteUuid,
    required this.dataReadUuid,
    required this.ioctlWriteUuid,
    required this.ioctlReadUuid,
    this.pairableDevices,
    this.deviceLibrary,
    this.deviceFirmwareName,
    this.deviceSetups = const [],
    this.minimumMainVersion,
    this.minimumRadioVersion,
    this.mainFirmwareType,
    this.radioFirmwareType,
    this.bootloaderFirmwareType,
  });

  /// The name the unit advertises, which is how it is recognised.
  final String bleAdvName;

  /// The product name printed on it.
  final String displayName;

  final EdlDevice deviceType;
  final String serviceUuid;
  final String dataWriteUuid;
  final String dataReadUuid;
  final String ioctlWriteUuid;
  final String ioctlReadUuid;
  final List<EdlDevice>? pairableDevices;

  /// Which protocol library drives it: `LibHeadModule`, `LibSlideModule`, ...
  final String? deviceLibrary;

  final String? deviceFirmwareName;
  final List<DeviceSetupSpec> deviceSetups;
  final String? minimumMainVersion;
  final String? minimumRadioVersion;
  final FirmwareType? mainFirmwareType;
  final FirmwareType? radioFirmwareType;
  final FirmwareType? bootloaderFirmwareType;

  @override
  String toString() => 'EdelkroneDeviceModel($displayName)';
}

/// Compares dotted firmware versions numerically; a part that is not a whole
/// number counts as zero, as in the SDK.
int compareFirmwareVersions(String a, String b) {
  int part(String s) => int.tryParse(s.trim()) ?? 0;
  final l = a.split('.').map(part).toList();
  final r = b.split('.').map(part).toList();
  for (var i = 0; i < (l.length > r.length ? l.length : r.length); i++) {
    final x = i < l.length ? l[i] : 0;
    final y = i < r.length ? r[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}
