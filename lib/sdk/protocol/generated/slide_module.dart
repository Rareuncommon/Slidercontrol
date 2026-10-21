// GENERATED FILE — do not edit by hand.
//
// Transpiled from the edelkrone Python SDK 0.1.0 (protocol/_generated/slide_module.py) by
// tool/sdk_port/py2dart.py. That file is itself a transliteration of the
// official edelkrone app's Dart protocol library, so this is a round trip back
// to Dart. Verified byte for byte against the Python original by
// test/sdk/codec_vectors_test.dart.
//
// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
//
// ignore_for_file: constant_identifier_names, non_constant_identifier_names, unnecessary_parenthesis, prefer_final_locals, unused_local_variable, prefer_const_constructors, unnecessary_this, prefer_initializing_formals, unused_import, curly_braces_in_flow_control_structures, unnecessary_brace_in_string_interps, dead_code

import 'moco.dart';
import 'slide_module_util.dart';
import '../../log.dart';

int libSlideModuleMinSpeed = 10;

int libSlideModuleMaxSpeed = 1080;

int libSlideModuleMaxPosition = 8000;

enum LibSlideModulePlacementType {
  ON_TRIPOD_MODULE_LEFT_SIDE(0),
  ON_TRIPOD_MODULE_RIGHT_SIDE(1),
  ON_GROUND_MODULE_LEFT_SIDE(2),
  ON_GROUND_MODULE_RIGHT_SIDE(3);

  const LibSlideModulePlacementType(this.value);
  final int value;

  static LibSlideModulePlacementType fromValue(int value) {
    return LibSlideModulePlacementType.values.firstWhere((e) => (e.value == value));
  }
}

enum LibSlideModuleEdlSetup {
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
  GROUP_MEMBER(12);

  const LibSlideModuleEdlSetup(this.value);
  final int value;
}

enum LibSlideModuleSliderBleResponse {
  GUI_RESPONSE(0),
  VERSION(1),
  GENERAL_STATUS(2),
  SLIDER_LOCATIONS_READBACK(3),
  TIMELAPSE_STATUS(4),
  TIMELAPSE_FPS_READBACK(5),
  CONFIGURATION(6),
  SLIDE_POS_UNIQUE_ID_RESPONSE(7),
  STOPMOTION_STATUS_RESPONSE(8),
  NUMERIC_DATA_RESPONSE(9),
  STOPMOTION_SHOT_LIST_RESPONSE(10),
  SDK_REPONSE_UNIVERSAL(24),
  CANBUS_INFO_REPONSE_UNIVERSAL(25),
  NUMERIC_LIMIT_RESPONSE_UNIVERSAL(26);

  const LibSlideModuleSliderBleResponse(this.value);
  final int value;
}

enum LibSlideModuleSliderState {
  IDLE(0),
  SLIDING(2),
  TIMELAPSING(3),
  STOPMOTION_RUNNING(4),
  POSITIONING(5),
  MANUAL_SLIDE(14),
  NUMERIC_MOVE_RUNNING(15);

  const LibSlideModuleSliderState(this.value);
  final int value;

  static LibSlideModuleSliderState fromValue(int value) {
    return LibSlideModuleSliderState.values.firstWhere((e) => (e.value == value));
  }
}

enum LibSlideModuleInclineMode {
  INVALID(0),
  FLAT(1),
  SAFE(2),
  DANGER(3);

  const LibSlideModuleInclineMode(this.value);
  final int value;

  static LibSlideModuleInclineMode fromValue(int value) {
    return LibSlideModuleInclineMode.values.firstWhere((e) => (e.value == value));
  }
}

enum LibSlideModuleParkMode {
  IDLE(0),
  POSITIONING(1),
  PARKED(2);

  const LibSlideModuleParkMode(this.value);
  final int value;

  static LibSlideModuleParkMode fromValue(int value) {
    return LibSlideModuleParkMode.values.firstWhere((e) => (e.value == value));
  }
}

enum LibSlideModuleVerticalModuleMode {
  IDLE(0),
  ACTIVE(1),
  ACTIVE_WARNING(2);

  const LibSlideModuleVerticalModuleMode(this.value);
  final int value;

  static LibSlideModuleVerticalModuleMode fromValue(int value) {
    return LibSlideModuleVerticalModuleMode.values.firstWhere((e) => (e.value == value));
  }
}

class LibSlideModuleTimelapseStatus {
  int pauseFlag = 0;
  int totalPauseSec = 0;
  int startTimeEpoch = 0;
  int postponeTimeSec = 0;
  int shotCounterUntil = 0;
  int shotCounterTotalPlanned = 0;
  int howLongAreWeHereForSec = 0;
  int remainingTimeSec = 0;
}

class LibSlideModuleStopmotionStatus {
  int currentFrame = 0;
  int shotCounterUntil = 0;
  int shotCounterTotalPlanned = 0;
}

class LibSlideModuleSlide {
  int endIndex = 0;
  int startIndex = -1;
  int isLoopEnabled = 0;
  double topSpeedRelative = 0.0;
  double accelRatioAtStart = 0.0;
  double accelRatioAtEnd = 0.0;
  double slideDurationSec = 0.0;
}

class LibSlideModuleStatus {
  int batteryLevel = 0;
  double tempSenseValue = 0.0;
  double positionRelative = 0.0;
  List<int> locationsValid = List<int>.filled(12, 0);
  int isCalibrated = 0;
  int isLoopEnabled = 0;
  double movePercentage = 0.0;
  LibSlideModuleSliderState state = LibSlideModuleSliderState.IDLE;
  LibSlideModulePlacementType placementType = LibSlideModulePlacementType.ON_TRIPOD_MODULE_LEFT_SIDE;
  int remoteModuleConnected = 0;
  int slideStartIndex = 0;
  int sliderEndIndex = 0;
  double moveDurationSec = 0.0;
  int isLocating = 0;
  int motorSlipDetected = 0;
  int stopmotionBusy = 0;
  int isStopmotionRunning = 0;
  int isTimelapseRunning = 0;
  int highPowerSlideEnabled = 0;
  EdlSetup configuration = EdlSetup.NONE;
  int inclineWarning = 0;
  double inclineTiltDeg = 0.0;
  int verticalModuleWarning = 0;
  LibSlideModuleParkMode parkMode = LibSlideModuleParkMode.IDLE;
  LibSlideModuleInclineMode inclineMode = LibSlideModuleInclineMode.INVALID;
  LibSlideModuleVerticalModuleMode verticalModuleMode = LibSlideModuleVerticalModuleMode.IDLE;
  double chainMotionPercentageCompleted = 0.0;
}

class LibSlideModuleSliderVersionData {
  int uniqueIdLow = 0;
  int uniqueIdMid = 0;
  int uniqueIdHigh = 0;
  int hardwareVersionMinor = 0;
  int hardwareVersionMajor = 0;
  int firmwareVersionMinor = 0;
  int firmwareVersionMajor = 0;
}

class LibSlideModuleSettings {
  int isBuzzerMuted = 0;
  int triggerDurationMs = 0;
  int autoPowerOffSec = 0;
  int liveModeEnabled = 0;
}

class LibSlideModule {

  double rawToRelativePosition(int rawPosition) {
    late double rv;
    late double delta;
    rv = 0.0;
    delta = (libSlideModuleMaxPosition).toDouble();
    rv = ((rawPosition).toDouble() / delta);
    return rv;
  }

  int relativeToRawSpeed(double relativeSpeed) {
    late int rv;
    late double deltaMax;
    rv = 0;
    deltaMax = ((libSlideModuleMaxSpeed - libSlideModuleMinSpeed)).toDouble();
    rv = (((relativeSpeed * deltaMax) + libSlideModuleMinSpeed)).toInt();
    return rv;
  }

  int appendChecksum(List<int> ptr, int len) {
    late int checksum;
    checksum = 0;
    for (var i = 0; i < len; i++) {
      checksum = (checksum + ptr[i]);
    }
    LibSlideModuleUtil.put16b(ptr, len, checksum);
    return 0;
  }

  int statusGet(List<int> ptr, List<int> len) {
    ptr[0] = 2;
    ptr[1] = 15;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int configurationSet(List<int> ptr, List<int> len, LibSlideModuleEdlSetup configuration) {
    ptr[0] = 3;
    ptr[1] = 201;
    ptr[2] = configuration.index;
    appendChecksum(ptr, ptr[0]);
    len[0] = (len[0] + 2);
    return 0;
  }

  int statusParse(List<int> ptr, LibSlideModuleStatus arg) {
    late double tmp;
    arg.state = LibSlideModuleSliderState.fromValue(ptr[1]);
    arg.batteryLevel = ptr[2];
    arg.remoteModuleConnected = ptr[3];
    arg.placementType = LibSlideModulePlacementType.fromValue(ptr[4]);
    arg.tempSenseValue = (ptr[5]).toDouble();
    arg.movePercentage = (((ptr[6]).toSigned(8)).toDouble() / 100.0);
    arg.locationsValid[0] = (LibSlideModuleUtil.checkBit(ptr[7], 0) ? 1 : 0);
    arg.locationsValid[1] = (LibSlideModuleUtil.checkBit(ptr[7], 1) ? 1 : 0);
    arg.locationsValid[2] = (LibSlideModuleUtil.checkBit(ptr[7], 2) ? 1 : 0);
    arg.isCalibrated = (LibSlideModuleUtil.checkBit(ptr[7], 3) ? 1 : 0);
    arg.isLoopEnabled = (LibSlideModuleUtil.checkBit(ptr[7], 4) ? 1 : 0);
    arg.isLocating = (LibSlideModuleUtil.checkBit(ptr[7], 5) ? 1 : 0);
    arg.isTimelapseRunning = (LibSlideModuleUtil.checkBit(ptr[7], 6) ? 1 : 0);
    arg.highPowerSlideEnabled = (LibSlideModuleUtil.checkBit(ptr[7], 7) ? 1 : 0);
    tmp = (LibSlideModuleUtil.make16b(ptr, 8)).toDouble();
    arg.positionRelative = rawToRelativePosition((tmp).toInt());
    arg.slideStartIndex = ptr[10];
    arg.sliderEndIndex = ptr[11];
    arg.moveDurationSec = ((LibSlideModuleUtil.make16b(ptr, 12)).toDouble() / 10.0);
    arg.configuration = EdlSetup.fromValue(ptr[14]);
    arg.stopmotionBusy = (LibSlideModuleUtil.checkBit(ptr[15], 0) ? 1 : 0);
    arg.isStopmotionRunning = (LibSlideModuleUtil.checkBit(ptr[15], 1) ? 1 : 0);
    arg.inclineWarning = (LibSlideModuleUtil.checkBit(ptr[15], 2) ? 1 : 0);
    arg.verticalModuleWarning = (LibSlideModuleUtil.checkBit(ptr[15], 3) ? 1 : 0);
    arg.verticalModuleMode = LibSlideModuleVerticalModuleMode.fromValue((ptr[15] >> 6));
    arg.motorSlipDetected = ptr[16];
    arg.parkMode = LibSlideModuleParkMode.fromValue(((ptr[17] >> 4) & 0xF));
    arg.inclineMode = LibSlideModuleInclineMode.fromValue((ptr[17] & 0xF));
    arg.inclineTiltDeg = ((LibSlideModuleUtil.make32b(ptr, 18)).toDouble() / 1000.0);
    EdelkroneLog.trace(() => 'Locations valid: ${ptr[19]}');
    arg.locationsValid[3] = (LibSlideModuleUtil.checkBit(ptr[22], 0) ? 1 : 0);
    arg.locationsValid[4] = (LibSlideModuleUtil.checkBit(ptr[22], 1) ? 1 : 0);
    arg.locationsValid[5] = (LibSlideModuleUtil.checkBit(ptr[22], 2) ? 1 : 0);
    arg.locationsValid[6] = (LibSlideModuleUtil.checkBit(ptr[22], 3) ? 1 : 0);
    arg.locationsValid[7] = (LibSlideModuleUtil.checkBit(ptr[22], 4) ? 1 : 0);
    arg.locationsValid[8] = (LibSlideModuleUtil.checkBit(ptr[22], 5) ? 1 : 0);
    arg.locationsValid[9] = (LibSlideModuleUtil.checkBit(ptr[22], 6) ? 1 : 0);
    arg.locationsValid[10] = (LibSlideModuleUtil.checkBit(ptr[22], 7) ? 1 : 0);
    arg.chainMotionPercentageCompleted = ((ptr[23]).toDouble() / 100.0);
    arg.locationsValid[11] = (LibSlideModuleUtil.checkBit(ptr[24], 0) ? 1 : 0);
    return 0;
  }

  int storeLocation(List<int> ptr, List<int> len, int slotIndex, int uniqueId) {
    ptr[0] = 7;
    ptr[1] = 7;
    ptr[2] = slotIndex;
    LibSlideModuleUtil.put32b(ptr, 3, uniqueId);
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int deleteLocation(List<int> ptr, List<int> len, int slotIndex) {
    ptr[0] = 3;
    ptr[1] = 29;
    ptr[2] = slotIndex;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int slide(List<int> ptr, List<int> len, LibSlideModuleSlide arg) {
    late int topSpeedRaw;
    topSpeedRaw = relativeToRawSpeed(arg.topSpeedRelative);
    ptr[0] = 13;
    ptr[1] = 11;
    ptr[2] = arg.isLoopEnabled;
    LibSlideModuleUtil.put32b(ptr, 3, topSpeedRaw);
    LibSlideModuleUtil.put16b(ptr, 7, ((arg.accelRatioAtStart * 32000.0)).toInt());
    LibSlideModuleUtil.put16b(ptr, 9, ((arg.accelRatioAtEnd * 32000.0)).toInt());
    ptr[11] = (arg.startIndex & 0xFF);
    ptr[12] = (arg.endIndex & 0xFF);
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int abortMotion(List<int> ptr, List<int> len) {
    ptr[0] = 2;
    ptr[1] = 12;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int manualSlideFixedReflex(List<int> ptr, List<int> len, double xSpd) {
    late double yKfFixed;
    yKfFixed = 0.9;
    return manualSlide(ptr, len, xSpd, yKfFixed);
  }

  int manualSlide(List<int> ptr, List<int> len, double xSpd, double yKf) {
    ptr[0] = 6;
    ptr[1] = 13;
    LibSlideModuleUtil.put16b(ptr, 2, ((xSpd * 32000.0)).toInt());
    LibSlideModuleUtil.put16b(ptr, 4, ((yKf * 32000.0)).toInt());
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int versionInfoGet(List<int> ptr, List<int> len) {
    ptr[0] = 2;
    ptr[1] = 14;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int versionInfoParse(List<int> ptr, LibSlideModuleSliderVersionData arg) {
    late int hardwareVersion;
    late int firmwareVersion;
    hardwareVersion = ptr[1];
    arg.hardwareVersionMinor = ((hardwareVersion & 0xF) >> 0);
    arg.hardwareVersionMajor = ((hardwareVersion & 0xF0) >> 4);
    firmwareVersion = LibSlideModuleUtil.make16b(ptr, 2);
    arg.firmwareVersionMinor = ((firmwareVersion & 0xFF) >> 0);
    arg.firmwareVersionMajor = ((firmwareVersion & 0xFF00) >> 8);
    arg.uniqueIdLow = LibSlideModuleUtil.make32b(ptr, 4);
    arg.uniqueIdMid = LibSlideModuleUtil.make32b(ptr, 8);
    arg.uniqueIdHigh = LibSlideModuleUtil.make32b(ptr, 12);
    return 0;
  }

  int timelapseStatusParse(List<int> ptr, LibSlideModuleTimelapseStatus arg) {
    arg.shotCounterUntil = LibSlideModuleUtil.makeU24b(ptr, 1);
    arg.howLongAreWeHereForSec = LibSlideModuleUtil.makeU32b(ptr, 4);
    arg.shotCounterTotalPlanned = LibSlideModuleUtil.makeU24b(ptr, 8);
    arg.startTimeEpoch = LibSlideModuleUtil.makeU32b(ptr, 11);
    arg.postponeTimeSec = LibSlideModuleUtil.makeU24b(ptr, 15);
    arg.pauseFlag = ptr[18];
    arg.totalPauseSec = LibSlideModuleUtil.makeU32b(ptr, 19);
    arg.remainingTimeSec = LibSlideModuleUtil.makeU32b(ptr, 23);
    return 0;
  }

  int timelapseFpsParse(List<int> ptr, List<double> fps) {
    fps[0] = ((LibSlideModuleUtil.makeU32b(ptr, 1)).toDouble() / 1000.0);
    return 0;
  }

  int stopmotionStatusParse(List<int> ptr, LibSlideModuleStopmotionStatus arg) {
    arg.shotCounterUntil = LibSlideModuleUtil.makeU24b(ptr, 1);
    arg.shotCounterTotalPlanned = LibSlideModuleUtil.makeU24b(ptr, 4);
    arg.currentFrame = LibSlideModuleUtil.makeU24b(ptr, 7);
    return 0;
  }

  int stopmotionShotListParse(List<int> ptr, List<int> shotList) {
    late int totalShotCount;
    late int shotIndex;
    totalShotCount = LibSlideModuleUtil.make16b(ptr, 1);
    for (var i = 0; i < 175; i++) {
      for (var j = 0; j < 8; j++) {
        shotIndex = ((i * 8) + j);
        if ((shotIndex <= totalShotCount)) {
          shotList[shotIndex] = (((ptr[(i + 3)] & (1 << j)) != 0) ? 1 : 0);
        }
      }
    }
    return 0;
  }

  int settingsBuzzerMutedSet(List<int> ptr, List<int> len, int isBuzzerMuted) {
    ptr[0] = 3;
    ptr[1] = 24;
    ptr[2] = isBuzzerMuted;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int settingsTriggerDurationSet(List<int> ptr, List<int> len, int triggerDurationMs) {
    ptr[0] = 6;
    ptr[1] = 32;
    LibSlideModuleUtil.put32b(ptr, 2, triggerDurationMs);
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int settingsAutoPowerOffSet(List<int> ptr, List<int> len, int autoPowerOffSec) {
    ptr[0] = 6;
    ptr[1] = 51;
    LibSlideModuleUtil.put32b(ptr, 2, autoPowerOffSec);
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int settingsRead(List<int> ptr, List<int> len) {
    ptr[0] = 2;
    ptr[1] = 25;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int settingsParse(List<int> ptr, LibSlideModuleSettings arg, bool hasLiveMode) {
    arg.isBuzzerMuted = ptr[1];
    arg.triggerDurationMs = LibSlideModuleUtil.make32b(ptr, 2);
    arg.autoPowerOffSec = LibSlideModuleUtil.make32b(ptr, 6);
    if (hasLiveMode) {
      arg.liveModeEnabled = ptr[10];
    } else {
      arg.liveModeEnabled = 0;
    }
    return 0;
  }

  int uniqueIdParse(List<int> ptr, List<int> uniqueIdBuff) {
    uniqueIdBuff[0] = LibSlideModuleUtil.make32b(ptr, 1);
    uniqueIdBuff[1] = LibSlideModuleUtil.make32b(ptr, 5);
    uniqueIdBuff[2] = LibSlideModuleUtil.make32b(ptr, 9);
    return 0;
  }

  int highPowerSlideEnable(List<int> ptr, List<int> len, int isEnabled) {
    ptr[0] = 3;
    ptr[1] = 33;
    ptr[2] = isEnabled;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int numericControlRead(List<int> ptr, List<int> len, int ind) {
    ptr[0] = 3;
    ptr[1] = 45;
    ptr[2] = ind;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int numericControlParse(List<int> ptr, List<int> ind, List<double> sliderSetpCm) {
    ind[0] = ptr[1];
    sliderSetpCm[0] = ((LibSlideModuleUtil.make32b(ptr, 2)).toDouble() / 1000.0);
    return 0;
  }

  int numericControlSliderMove(List<int> ptr, List<int> len, double sliderSetpCm) {
    ptr[0] = 6;
    ptr[1] = 42;
    LibSlideModuleUtil.put32b(ptr, 2, ((sliderSetpCm * 1000.0)).toInt());
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int chainModeGoLocation(List<int> ptr, List<int> len, int ind) {
    ptr[0] = 3;
    ptr[1] = 57;
    ptr[2] = ind;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int settingsLiveModeSet(List<int> ptr, List<int> len, int liveModeEnabled) {
    ptr[0] = 4;
    ptr[1] = 140;
    ptr[2] = 0;
    ptr[3] = liveModeEnabled;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }
}
