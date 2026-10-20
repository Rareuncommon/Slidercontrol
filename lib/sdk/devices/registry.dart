/// Seen units, and how a set of them resolves into a layout.
///
/// Ported from `edelkrone/devices/{registry,rig}.py`. The resolution rules
/// are the SDK's, including the HeadONE ones that matter for this rig: an
/// upright HeadONE takes the PAN layouts and a tilted one the TILT layouts,
/// read from a bit in its advertisement.
///
/// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
library;

import '../log.dart';
import '../protocol/generated/moco.dart';
import 'model_type.dart';
import 'models.dart' as models;

/// A unit seen advertising.
class EdelkroneDevice {
  EdelkroneDevice({
    required this.id,
    required this.model,
    required this.advData,
    required this.rssi,
    this.setup,
  });

  /// The platform's identifier for the peripheral. On Apple platforms this is
  /// a per-host UUID, not the MAC — which is why the MAC comes from the
  /// advertisement instead.
  final String id;

  final EdelkroneDeviceModel model;
  final LibEdelkroneMocoAdvData advData;
  final int rssi;
  DeviceSetup? setup;

  String get displayName => model.displayName;
  String get mac => macText(advData.mac);
  bool get isTilted => advData.isTilted;
  bool get isCalibrated => !advData.oldSlideModuleConnected;
  String get firmwareVersion => '${advData.deviceFirmwareVersionMajor}.${advData.deviceFirmwareVersionMinor}';
  String get radioVersion => '${advData.esp32FirmwareVersionMajor}.${advData.esp32FirmwareVersionMinor}';

  bool get firmwareOk {
    final mainMin = model.minimumMainVersion;
    final radioMin = model.minimumRadioVersion;
    return (mainMin == null || compareFirmwareVersions(firmwareVersion, mainMin) >= 0) &&
        (radioMin == null || compareFirmwareVersions(radioVersion, radioMin) >= 0);
  }

  EdelkroneDevice withAdv(LibEdelkroneMocoAdvData adv, int newRssi) =>
      EdelkroneDevice(id: id, model: model, advData: adv, rssi: newRssi, setup: setup);

  @override
  bool operator ==(Object other) => other is EdelkroneDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'EdelkroneDevice($displayName $mac ${advData.setup.name} rssi=$rssi)';
}

String macText(List<int> mac) => mac.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');

class DeviceSetup {
  DeviceSetup({required this.masterDevice, required this.setupType, List<EdelkroneDevice>? slaveDevices})
      : slaveDevices = slaveDevices ?? [];

  final EdelkroneDevice masterDevice;
  final EdlSetup setupType;
  final List<EdelkroneDevice> slaveDevices;
}

EdelkroneDeviceModel? identifyEdelkroneDevice(String name) {
  if (name.isEmpty) return null;
  for (final m in [...models.allDevices, ...models.extraDevices]) {
    if (name == m.bleAdvName) return m;
  }
  return null;
}

bool isCanbusMaster(EdelkroneDevice d) =>
    d.advData.setup == EdlSetup.POSSIBLE_CANBUS_MASTER || d.advData.canbusPairingActive;

bool shouldHideFromDeviceScanner(EdelkroneDevice d) =>
    d.advData.setup == EdlSetup.GROUP_MEMBER && d.advData.canbusPairingActive;

const _panRoleSetups = {
  EdlSetup.PAN_ONLY,
  EdlSetup.PAN_TILT,
  EdlSetup.PAN_AND_SLIDE,
  EdlSetup.PAN_AND_DOLLY,
  EdlSetup.PAN_AND_JIB,
  EdlSetup.PAN_AND_JIB_PLUS,
  EdlSetup.PAN_TILT_AND_SLIDE,
  EdlSetup.PAN_TILT_AND_DOLLY,
  EdlSetup.PAN_TILT_AND_JIB,
  EdlSetup.PAN_TILT_AND_JIB_PLUS,
};

const _tiltRoleSetups = {
  EdlSetup.TILT_ONLY,
  EdlSetup.TILT_AND_SLIDE,
  EdlSetup.TILT_AND_DOLLY,
  EdlSetup.TILT_AND_JIB,
  EdlSetup.TILT_AND_JIB_PLUS,
};

bool _anySlaveType(DeviceSetup s, Set<EdlDevice> types) =>
    s.slaveDevices.any((d) => types.contains(d.model.deviceType));

bool isSingleHeadOneLeg(DeviceSetup setup) {
  final masterType = setup.masterDevice.model.deviceType;
  if (masterType != EdlDevice.HEAD_PLUS_V3 && masterType != EdlDevice.HEAD_PLUS_PRO_V3) return true;
  final headOnes = setup.slaveDevices.where((d) => d.model.deviceType == EdlDevice.HEAD_ONE).toList();
  if (headOnes.length != 1) return true;
  final tilted = headOnes[0].isTilted;
  switch (setup.setupType) {
    case EdlSetup.PAN_TILT:
      return tilted;
    case EdlSetup.PAN_TILT_AND_SLIDE:
      if (_anySlaveType(setup, {EdlDevice.SLIDER_ONE_PRO, EdlDevice.SLIDE_MODULE, EdlDevice.SLIDE_MODULE_V3})) {
        return tilted;
      }
    case EdlSetup.PAN_TILT_AND_DOLLY:
      if (_anySlaveType(setup, {EdlDevice.DOLLY_ONE_V2, EdlDevice.DOLLY_PLUS_V2})) return tilted;
    case EdlSetup.PAN_TILT_AND_JIB_PLUS:
      break;
    case EdlSetup.PAN_TILT_DOLLY_AND_JIB_PLUS:
    case EdlSetup.PAN_TILT_DOLLY_AND_SLIDER:
      return tilted;
    default:
      break;
  }
  return true;
}

bool checkDualHeadOneAxis(DeviceSetup setup) {
  final headOnes = [
    if (setup.masterDevice.model.deviceType == EdlDevice.HEAD_ONE) setup.masterDevice,
    ...setup.slaveDevices.where((d) => d.model.deviceType == EdlDevice.HEAD_ONE),
  ];
  if (headOnes.length < 2) return true;
  return headOnes.any((d) => d.isTilted) && headOnes.any((d) => !d.isTilted);
}

/// The layout a set of units forms, or null if the registry lists none.
DeviceSetup? prepareSetup(List<EdelkroneDevice> devices) {
  if (devices.isEmpty) return null;
  final withSetups = devices.where((d) => d.model.deviceSetups.isNotEmpty).toList();
  if (withSetups.isEmpty) return null;
  final currentTypes = devices.map((d) => d.model.deviceType).toList();
  for (final master in withSetups) {
    for (final spec in master.model.deviceSetups) {
      final c = _matchSetup(devices, currentTypes, master, spec);
      if (c != null) return c;
    }
  }
  EdelkroneLog.debug(() => 'no setup matches the given devices');
  return null;
}

DeviceSetup? _matchSetup(
  List<EdelkroneDevice> devices,
  List<EdlDevice> currentTypes,
  EdelkroneDevice master,
  DeviceSetupSpec spec,
) {
  final required = spec.devices;
  if (required.length != devices.length) return null;
  final remaining = [...currentTypes];
  for (final r in required) {
    if (!remaining.remove(r)) return null;
  }
  if (master.model.deviceType == EdlDevice.HEAD_ONE) {
    if (master.isTilted && _panRoleSetups.contains(spec.setup)) return null;
    if (!master.isTilted && _tiltRoleSetups.contains(spec.setup)) return null;
  }
  final slaves = <EdelkroneDevice>[];
  for (final t in required.skip(1)) {
    slaves.add(_pickSlave(devices, master, t, slaves));
  }
  final candidate = DeviceSetup(masterDevice: master, setupType: spec.setup, slaveDevices: slaves);
  if (!checkDualHeadOneAxis(candidate)) return null;
  if (!isSingleHeadOneLeg(candidate)) return null;
  return candidate;
}

EdelkroneDevice _pickSlave(
  List<EdelkroneDevice> devices,
  EdelkroneDevice master,
  EdlDevice type,
  List<EdelkroneDevice> already,
) {
  for (final d in devices) {
    if (d.model.deviceType == type && !already.contains(d) && d != master) return d;
  }
  for (final d in devices) {
    if (d.model.deviceType == type && d != master) return d;
  }
  throw StateError('the layout has no module of type ${type.name}');
}

/// The units with a live mode, in which a frame's layout differs.
bool hasLiveMode(DeviceSetup setup) => const [
      models.headPlusV3,
      models.headPlusProV3,
      models.headOneFm,
      models.dollyOneV2,
      models.dollyGo,
      models.dollyPlusV2,
      models.sliderPlusV1,
      models.sliderOneFm,
    ].any((m) => identical(m, setup.masterDevice.model));

/// A unit together with the modules it leads.
class Rig {
  Rig({required this.master, required this.slaves, required this.setup, required this.resolved});

  final EdelkroneDevice master;
  final List<EdelkroneDevice> slaves;
  final EdlSetup setup;
  final DeviceSetup? resolved;

  List<EdelkroneDevice> get devices => [master, ...slaves];
  int get groupId => master.advData.groupId;
  bool get isRecognised => resolved != null;
  List<EdelkroneDevice> get orderedSlaves => resolved?.slaveDevices ?? slaves;

  @override
  String toString() {
    final names = orderedSlaves.map((d) => d.displayName).join(', ');
    return 'Rig(${setup.name}: ${master.displayName}${names.isEmpty ? '' : ' + $names'}'
        '${isRecognised ? '' : ' — no matching setup in the registry'})';
  }
}

const _notALayout = {
  EdlSetup.NONE,
  EdlSetup.GROUP_MEMBER,
  EdlSetup.POSSIBLE_CANBUS_MASTER,
  EdlSetup.BOOTING_UP,
  EdlSetup.FIRMWARE_ERROR,
};

Rig _assemble(EdelkroneDevice master, List<EdelkroneDevice> slaves) {
  final resolved = prepareSetup([master, ...slaves]);
  final advertised = master.advData.setup;
  final setup = !_notALayout.contains(advertised) ? advertised : (resolved?.setupType ?? EdlSetup.NONE);
  return Rig(master: master, slaves: slaves, setup: setup, resolved: resolved);
}

/// Groups seen units into rigs by their advertised group, the way the SDK's
/// discover() does: a group's members are listed under its leader.
List<Rig> groupIntoRigs(Iterable<EdelkroneDevice> devices, {bool hideUnpairedGroupMembers = true}) {
  final byGroup = <int, List<EdelkroneDevice>>{};
  final alone = <EdelkroneDevice>[];
  for (final d in devices) {
    if (hideUnpairedGroupMembers && shouldHideFromDeviceScanner(d)) continue;
    if (d.model.deviceType == EdlDevice.TRIPOD) {
      alone.add(d);
      continue;
    }
    byGroup.putIfAbsent(d.advData.groupId, () => []).add(d);
  }
  final rigs = <Rig>[];
  for (final members in byGroup.values) {
    final masters = members.where((d) => d.advData.setup != EdlSetup.GROUP_MEMBER).toList();
    final groupMembers = members.where((d) => d.advData.setup == EdlSetup.GROUP_MEMBER).toList();
    if (masters.isEmpty) {
      rigs.addAll(groupMembers.map((d) => _assemble(d, [])));
      continue;
    }
    masters.sort((a, b) => b.rssi.compareTo(a.rssi));
    rigs.add(_assemble(masters.first, groupMembers));
    rigs.addAll(masters.skip(1).map((d) => _assemble(d, [])));
  }
  rigs.addAll(alone.map((d) => _assemble(d, [])));
  rigs.sort((a, b) => b.master.rssi.compareTo(a.master.rssi));
  return rigs;
}

/// A rig built from units the user picked to join together.
Rig? rigFromSelection(List<EdelkroneDevice> selected) {
  if (selected.isEmpty) return null;
  var resolved = prepareSetup(selected);
  if (resolved != null && resolved.setupType == EdlSetup.NONE) resolved = null;
  final canbusMasters = selected.where(isCanbusMaster).toList();
  if (canbusMasters.isNotEmpty) {
    final master = canbusMasters.first;
    return Rig(
      master: master,
      slaves: selected.where((d) => d != master).toList(),
      setup: resolved?.setupType ?? master.advData.setup,
      resolved: resolved,
    );
  }
  if (resolved == null) return null;
  final master = selected.firstWhere(
    (d) => identical(d, resolved!.masterDevice) || _sameMac(d.advData.mac, resolved.masterDevice.advData.mac),
    orElse: () => resolved!.masterDevice,
  );
  return Rig(
    master: master,
    slaves: selected.where((d) => d != master).toList(),
    setup: resolved.setupType,
    resolved: resolved,
  );
}

bool _sameMac(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
