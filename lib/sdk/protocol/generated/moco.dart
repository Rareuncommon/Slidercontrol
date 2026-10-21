// GENERATED FILE — do not edit by hand.
//
// Transpiled from the edelkrone Python SDK 0.1.0 (protocol/_generated/moco.py) by
// tool/sdk_port/py2dart.py. That file is itself a transliteration of the
// official edelkrone app's Dart protocol library, so this is a round trip back
// to Dart. Verified byte for byte against the Python original by
// test/sdk/codec_vectors_test.dart.
//
// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
//
// ignore_for_file: constant_identifier_names, non_constant_identifier_names, unnecessary_parenthesis, prefer_final_locals, unused_local_variable, prefer_const_constructors, unnecessary_this, prefer_initializing_formals, unused_import, curly_braces_in_flow_control_structures, unnecessary_brace_in_string_interps, dead_code

enum EdlDevice {
  SLIDE_MODULE(0),
  HEAD_PLUS(1),
  HEAD_PLUS_PRO(2),
  HEAD_ONE(3),
  SURFACE_ONE(4),
  DOLLY_PLUS(5),
  SLIDER_ONE_PRO(6),
  SLIDER_ONE(7),
  DOLLY_ONE(8),
  DOLLY_PLUS_PRO(9),
  JIB_ONE(10),
  CONTROLLER(11),
  SLIDE_MODULE_V3(12),
  PAN_MODULE_FOR_JIB_ONE(13),
  JIB_ONE_MK2(14),
  FOCUS_PLUS_PRO(15),
  HEAD_PLUS_V2(16),
  HEAD_PLUS_PRO_V2(17),
  VISION_MODULE(18),
  DOLLY_ONE_V2(19),
  HEAD_PLUS_V3(20),
  HEAD_PLUS_PRO_V3(21),
  TRIPOD(22),
  JIB_ONE_V3(23),
  JIB_PLUS_V3(24),
  FOCUS_MODULE_V3(25),
  SLIDER_ONE_FM(26),
  DOLLY_PLUS_V2(27),
  SLIDER_PLUS_V1(28),
  LINK_ADAPTER(31),
  GIMBAL_CONTROLLER(32),
  PAN_MODULE_FOR_JIB(33),
  DOLLY_GO_V1(34),
  SLIDE_MODULE_V1(201),
  NONE(0xFF);

  const EdlDevice(this.value);
  final int value;

  static EdlDevice fromValue(int value) {
    return EdlDevice.values.firstWhere((e) => (e.value == value));
  }
}

enum EdlConfig {
  PAN_TILT(0),
  PAN_ONLY(1),
  TILT_ONLY(2),
  DOLLY(3),
  SLIDER(4),
  JIB(5),
  REMOTE_CONTROLLER(6),
  DOESNT_MATTER(7),
  NONE(0xFF);

  const EdlConfig(this.value);
  final int value;

  static EdlConfig fromValue(int value) {
    return EdlConfig.values.firstWhere((e) => (e.value == value));
  }
}

/// Enum representing different device setups
enum EdlSetup {
  NONE(0),
  PAN_ONLY(1),
  TILT_ONLY(2),
  PAN_TILT(3),
  SLIDE_ONLY(4),
  DOLLY_ONLY(5),
  PAN_AND_SLIDE(6),
  TILT_AND_SLIDE(7),
  PAN_AND_DOLLY(8),
  TILT_AND_DOLLY(9),
  PAN_TILT_AND_SLIDE(10),
  PAN_TILT_AND_DOLLY(11),
  GROUP_MEMBER(12),
  PAN_AND_JIB(13),
  TILT_AND_JIB(14),
  PAN_TILT_AND_JIB(15),
  JIB_ONLY(16),
  PAN_AND_JIB_PLUS(17),
  TILT_AND_JIB_PLUS(18),
  PAN_TILT_AND_JIB_PLUS(19),
  JIB_PLUS_ONLY(20),
  FOLLOW_FOCUS_ONLY(21),
  PAN_TILT_DOLLY_AND_JIB_PLUS(28),
  PAN_TILT_DOLLY_AND_SLIDER(29),
  POSSIBLE_CANBUS_MASTER(0x1F),
  BOOTING_UP(0x60),
  FIRMWARE_ERROR(0x70),
  IGNORE(0x7F);

  const EdlSetup(this.value);
  final int value;

  static EdlSetup fromValue(int value) {
    return EdlSetup.values.firstWhere((e) => (e.value == value), orElse: () => EdlSetup.NONE);
  }
}

enum EspWifiState {
  NONE(0),
  BOOTING(1),
  READY_TO_CONNECT(2),
  CONNECTING(3),
  GOT_IP(4),
  CONNECTION_TRIAL_FAILED(5);

  const EspWifiState(this.value);
  final int value;

  static EspWifiState fromValue(int value) {
    return EspWifiState.values.firstWhere((e) => (e.value == value));
  }
}

enum LibEdelkroneMocoResponse {
  IOCTL_STATUS(0),
  WIFI_INFO_READOUT(1),
  CANBUS_INFO_READOUT(25),
  NUMERIC_LIMIT_READOUT(26);

  const LibEdelkroneMocoResponse(this.value);
  final int value;
}

enum LibEdelkroneMocoCanbusPairState {
  IDLE(0),
  PING_RECEIVED(1),
  CONNECTING(2),
  CONNECTED(3);

  const LibEdelkroneMocoCanbusPairState(this.value);
  final int value;
}

enum LibEdelkroneMocoCanbusPairError {
  NONE(0),
  IMPOSSIBLE_SCENARIO(1),
  DEVICE_FIRMWARE_UPDATE_REQUIRED(2),
  UNKNOWN(3),
  CANT_APPEND_DEVICE(4);

  const LibEdelkroneMocoCanbusPairError(this.value);
  final int value;
}

class LibEdelkroneMocoIoctlStatus {
  LibEdelkroneMocoIoctlStatus({required this.groupId, required this.groupMemberDev, required this.groupMemberConf, required this.autoConnectEnabled, required this.wifiState, required this.wifiChannel, required this.esp32FirmwareVersionMinor, required this.esp32FirmwareVersionMajor});

  int groupId;
  List<EdlDevice> groupMemberDev;
  List<EdlConfig> groupMemberConf;
  bool autoConnectEnabled;
  EspWifiState wifiState;
  int wifiChannel;
  int esp32FirmwareVersionMinor;
  int esp32FirmwareVersionMajor;
}

class LibEdelkroneMocoAdvData {
  LibEdelkroneMocoAdvData({required this.mac, required this.groupId, required this.setup, required this.wifiChannel, required this.wifiState, required this.isTilted, required this.oldSlideModuleConnected, required this.esp32FirmwareVersionMinor, required this.esp32FirmwareVersionMajor, required this.deviceFirmwareVersionMinor, required this.deviceFirmwareVersionMajor, required this.canbusPairingActive});

  List<int> mac;
  int groupId;
  EdlSetup setup;
  int wifiChannel;
  EspWifiState wifiState;
  bool isTilted;
  bool oldSlideModuleConnected;
  int esp32FirmwareVersionMinor;
  int esp32FirmwareVersionMajor;
  int deviceFirmwareVersionMinor;
  int deviceFirmwareVersionMajor;
  bool canbusPairingActive;
}

class LibEdelkroneMocoCanbusInfo {
  LibEdelkroneMocoCanbusInfo({required this.canbusPairState, required this.canbusPairError});

  LibEdelkroneMocoCanbusPairState canbusPairState;
  LibEdelkroneMocoCanbusPairError canbusPairError;
}

void put16b(List<int> ptr, int offset, int val) {
  ptr[offset] = ((val & 0xFF00) >> 8);
  ptr[(offset + 1)] = ((val & 0xFF) >> 0);
}

int make16b(List<int> ptr, int base) {
  return (((ptr[base] << 8) | ptr[(base + 1)]) >>> 0);
}

class EdelkroneMoco {

  static int appendChecksum(List<int> ptr, int len) {
    late int checksum;
    checksum = 0;
    for (var i = 0; i < len; i++) {
      checksum = (checksum + ptr[i]);
    }
    put16b(ptr, len, checksum);
    return 0;
  }

  static int checksumControl(List<int> ptr, int len) {
    late int checksumCalc;
    late int checksumExp;
    if ((len < 2)) {
      return -1;
    }
    checksumCalc = 0;
    checksumExp = 0;
    for (var i = 0; i < (len - 2); i++) {
      checksumCalc = (checksumCalc + ptr[i]);
    }
    checksumExp = make16b(ptr, (len - 2));
    if ((checksumExp == checksumCalc)) {
      return 0;
    } else {
      return 1;
    }
  }

  static int addPeer(List<int> ptr, List<int> ptrLen, List<int> mac, EdlDevice device, EdlConfig config, int groupId) {
    ptr[0] = 12;
    ptr[1] = 1;
    for (var i = 0; i < 6; i++) {
      ptr[(2 + i)] = mac[i];
    }
    ptr[8] = device.value;
    ptr[9] = config.value;
    put16b(ptr, 10, groupId);
    EdelkroneMoco.appendChecksum(ptr, ptr[0]);
    ptrLen[0] = ptr[0];
    return 0;
  }

  int ioctlStatusGet(List<int> ptr, List<int> ptrLen) {
    ptr[0] = 2;
    ptr[1] = 2;
    EdelkroneMoco.appendChecksum(ptr, ptr[0]);
    ptrLen[0] = ptr[0];
    return 0;
  }

  static int ioctlStatusParse(List<int> ptr, List<LibEdelkroneMocoIoctlStatus> status) {
    late int firmwareVersion;
    firmwareVersion = make16b(ptr, 10);
    status[0] = LibEdelkroneMocoIoctlStatus(groupId: make16b(ptr, 1), groupMemberDev: <EdlDevice>[EdlDevice.fromValue(ptr[3]), EdlDevice.fromValue(ptr[4])], groupMemberConf: <EdlConfig>[EdlConfig.fromValue(ptr[5]), EdlConfig.fromValue(ptr[6])], wifiState: EspWifiState.fromValue(ptr[7]), wifiChannel: ptr[8], autoConnectEnabled: (ptr[9] != 0), esp32FirmwareVersionMinor: ((firmwareVersion & 0xFF) >> 0), esp32FirmwareVersionMajor: ((firmwareVersion & 0xFF00) >> 8));
    return 0;
  }

  static LibEdelkroneMocoAdvData advParse(List<int> advData) {
    late int rawSetupByte;
    late bool canbusPairingActive;
    late bool oldSlideModuleConnected;
    late int setupValue;
    late EdlSetup setup;
    late bool isTilted;
    late int deviceFirmwareVersionMinor;
    late int esp32FirmwareVersionMinor;
    late int deviceFirmwareVersionMajor;
    late int esp32FirmwareVersionMajor;
    late EspWifiState wifiState;
    late int wifiChannel;
    late List<int> mac;
    late int groupId;
    if ((advData.length < 12)) {
      throw ArgumentError('Advertisement data too short (${advData.length} bytes, need at least 12)');
    }
    rawSetupByte = advData[0];
    canbusPairingActive = ((rawSetupByte & 0x20) != 0);
    oldSlideModuleConnected = ((rawSetupByte & 0x80) != 0);
    setupValue = ((rawSetupByte >= 0x60) ? (rawSetupByte & 0x7F) : (rawSetupByte & 0x1F));
    setup = EdlSetup.fromValue(setupValue);
    isTilted = ((advData[1] & 0x1) != 0);
    deviceFirmwareVersionMinor = ((advData[1] >> 1) & 0x7F);
    esp32FirmwareVersionMinor = advData[2];
    deviceFirmwareVersionMajor = 0;
    esp32FirmwareVersionMajor = 0;
    if ((advData.length > 12)) {
      deviceFirmwareVersionMajor = ((advData[12] & 0xF0) >> 4);
      esp32FirmwareVersionMajor = (advData[12] & 0xF);
    }
    wifiState = EspWifiState.values.firstWhere((e) => (e.value == (advData[3] & 0xF)), orElse: () => EspWifiState.NONE);
    wifiChannel = ((advData[3] & 0xF0) >> 4);
    mac = advData.sublist(4, 10);
    groupId = ((advData[10] << 8) | advData[11]);
    return LibEdelkroneMocoAdvData(mac: mac, groupId: groupId, setup: setup, wifiChannel: wifiChannel, wifiState: wifiState, isTilted: isTilted, oldSlideModuleConnected: oldSlideModuleConnected, esp32FirmwareVersionMinor: esp32FirmwareVersionMinor, esp32FirmwareVersionMajor: esp32FirmwareVersionMajor, deviceFirmwareVersionMinor: deviceFirmwareVersionMinor, deviceFirmwareVersionMajor: deviceFirmwareVersionMajor, canbusPairingActive: canbusPairingActive);
  }

  static int groupIdSelfSet(List<int> ptr, List<int> ptrLen, int groupId) {
    ptr[0] = 4;
    ptr[1] = 9;
    put16b(ptr, 2, groupId);
    EdelkroneMoco.appendChecksum(ptr, ptr[0]);
    ptrLen[0] = (ptrLen[0] + 2);
    return 0;
  }

  int canbusAutoPair(List<int> ptr, List<int> ptrLen) {
    ptrLen[0] = 2;
    ptr[0] = ptrLen[0];
    ptr[1] = 197;
    EdelkroneMoco.appendChecksum(ptr, ptrLen[0]);
    return 0;
  }

  int canbusInfoGet(List<int> ptr, List<int> ptrLen) {
    ptrLen[0] = 2;
    ptr[0] = ptrLen[0];
    ptr[1] = 196;
    EdelkroneMoco.appendChecksum(ptr, ptrLen[0]);
    return 0;
  }

  static LibEdelkroneMocoCanbusInfo canbusInfoParse(List<int> buffer) {
    return LibEdelkroneMocoCanbusInfo(canbusPairState: LibEdelkroneMocoCanbusPairState.values.firstWhere((e) => (e.value == buffer[1]), orElse: () => LibEdelkroneMocoCanbusPairState.IDLE), canbusPairError: LibEdelkroneMocoCanbusPairError.values.firstWhere((e) => (e.value == buffer[2]), orElse: () => LibEdelkroneMocoCanbusPairError.NONE));
  }
}
