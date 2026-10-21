// GENERATED FILE — do not edit by hand.
//
// Transpiled from the edelkrone Python SDK 0.1.0 (protocol/_generated/head_module.py) by
// tool/sdk_port/py2dart.py. That file is itself a transliteration of the
// official edelkrone app's Dart protocol library, so this is a round trip back
// to Dart. Verified byte for byte against the Python original by
// test/sdk/codec_vectors_test.dart.
//
// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
//
// ignore_for_file: constant_identifier_names, non_constant_identifier_names, unnecessary_parenthesis, prefer_final_locals, unused_local_variable, prefer_const_constructors, unnecessary_this, prefer_initializing_formals, unused_import, curly_braces_in_flow_control_structures, unnecessary_brace_in_string_interps, dead_code

import 'moco.dart';
import 'head_module_util.dart';
import '../../log.dart';

double mJiboneSetupAngleDegEstimation = 0.0;

enum LibHeadModuleMk2UiState {
  NONE(0),
  KEYPOSE(1),
  TARGET_MODE(2),
  TARGET_MODE_VISION(3);

  const LibHeadModuleMk2UiState(this.value);
  final int value;

  static LibHeadModuleMk2UiState fromValue(int value) {
    return LibHeadModuleMk2UiState.values.firstWhere((state) => (state.value == value), orElse: () => LibHeadModuleMk2UiState.NONE);
  }
}

enum LibHeadModuleMk2BleResponse {
  GUI_RESPONSE(0),
  HEAD_VERSION(1),
  GENERAL_STATUS(2),
  KEYPOSE_UNIQUE_ID_RESPONSE(3),
  KEYPOSE_MOVE_DURATION(4),
  TARGET_UNIQUE_ID_RESPONSE(5),
  TARGET_TRANSITION_DURATION(6),
  REMOTE_POSITION_MOVE_DURATION(7),
  RECORD_STATUS_RESPONSE(8),
  REMOTE_POSITION_UNIQUE_ID_RESPONSE(9),
  TIMELAPSE_STATUS_RESPONSE(10),
  TIMELAPSE_FPS_RESPONSE(11),
  LENS_LEARNING_STATUS_RESPONSE(12),
  SETTINGS(13),
  STOPMOTION_STATUS_RESPONSE(14),
  MODE360_STATUS_RESPONSE(15),
  REMOTE_FIRMWARE_VERSION_RESPONSE(16),
  REMOTE_DEVICE_TYPE_RESPONSE(17),
  NUMERIC_VALUE_READOUT(18),
  SEQUENCER_STATUS(19),
  STOPMOTION_SHOT_LIST_RESPONSE(20),
  REMOTE_VERSION(21),
  REMOTE_CONTROLLER_VERSION(22),
  API_RESPONSE(23),
  SDK_REPONSE_UNIVERSAL(24),
  CANBUS_INFO_REPONSE_UNIVERSAL(25),
  NUMERIC_LIMIT_RESPONSE_UNIVERSAL(26),
  VISION_MODULE_SETTINGS_DATA(27),
  PHONE_MODE_SETTINGS_DATA(28),
  NUMERIC_VALUE_READOUT_REMOTE_DEVICE(29),
  FOCUS_MODULE_UPDATE(30);

  const LibHeadModuleMk2BleResponse(this.value);
  final int value;
}

enum LibHeadModuleMk2HeadState {
  IDLE(0),
  LENS_LOADING_SEARCH_INFINITY(1),
  LENS_LOADING_SEARCH_MACRO(2),
  TARGET_LOCKED(3),
  TARGET_TRANSITION(4),
  KEYPOSE_MOVING(5),
  TARGET_LEARNING_LASER_ON(6),
  TARGET_LEARNING_LEARN_WITHOUT_FOCUS_NOT_MOVED_ENOUGH(7),
  TARGET_LEARNING_LEARN_WITHOUT_FOCUS_MOVED_ENOUGH(8),
  FOCUS_BACKLASH_CALIBRATION(9),
  BASIC_CALIBRATION_SEARCH_NEGATIVE(10),
  BASIC_CALIBRATION_SEARCH_POSITIVE(11),
  NUMERIC_MOVE_RUNNING(12),
  SEQUENCER_RUNNING(13),
  TARGET_LEARNING_WITHOUT_FOCUS(14);

  const LibHeadModuleMk2HeadState(this.value);
  final int value;

  static LibHeadModuleMk2HeadState fromValue(int value) {
    return LibHeadModuleMk2HeadState.values.firstWhere((state) => (state.value == value), orElse: () => LibHeadModuleMk2HeadState.IDLE);
  }
}

enum LibHeadModuleMk2LensLearningState {
  IDLE(0),
  LOCATING_MACRO(1),
  WAITING_MACRO_CONFIRMATION(2),
  LOCATING_INFINITY(3),
  LOCATING_KEYFRAME(4),
  WAITING_FOR_INFINITY_CONFIRMATION(5),
  WAITING_FOR_DISTANCE(6),
  STOPPING(7);

  const LibHeadModuleMk2LensLearningState(this.value);
  final int value;

  static LibHeadModuleMk2LensLearningState fromValue(int value) {
    return LibHeadModuleMk2LensLearningState.values.firstWhere((state) => (state.value == value), orElse: () => LibHeadModuleMk2LensLearningState.IDLE);
  }
}

enum LibHeadModuleMk2LensModelDataInsertResult {
  INVALID(-1),
  OK(0),
  RANGE_ERROR(1),
  FINISHED(2);

  const LibHeadModuleMk2LensModelDataInsertResult(this.value);
  final int value;

  static LibHeadModuleMk2LensModelDataInsertResult fromValue(int value) {
    return LibHeadModuleMk2LensModelDataInsertResult.values.firstWhere((result) => (result.value == value), orElse: () => LibHeadModuleMk2LensModelDataInsertResult.INVALID);
  }
}

enum LibHeadModuleMk2RemoteDeviceType {
  NONE(0x0),
  SLIDE_MODULE(0x80),
  SLIDE_MODULE_V2(0x81),
  SLIDER_ONE_PRO_V2(0x82),
  DOLLY_PLUS(0x83),
  SLIDER_ONE_V2(0x84),
  DOLLY_PLUS_PRO(0x85),
  DOLLY_ONE(0x86),
  JIB_ONE(0x87),
  SLIDE_MODULE_V3(0x88),
  JIB_ONE_MK2(0x89),
  JIB_ONE_V3(0x8A),
  JIB_PLUS_V3(0x8B),
  DOLLY_ONE_V2(0x8C),
  DOLLY_PLUS_V2(0x8D),
  SLIDER_PLUS_V1(0x8E),
  DOLLY_GO_V1(0x8F);

  const LibHeadModuleMk2RemoteDeviceType(this.value);
  final int value;

  static LibHeadModuleMk2RemoteDeviceType fromValue(int value) {
    return LibHeadModuleMk2RemoteDeviceType.values.firstWhere((type) => (type.value == value), orElse: () => LibHeadModuleMk2RemoteDeviceType.NONE);
  }
}

enum LibHeadModuleMk2StandardCircleType {
  SLIDE(0),
  DOLLY(1),
  CURVE(2),
  CIRCLE360(3),
  INSTANT_PATH(4),
  FREE_PATH(5),
  NONE(6);

  const LibHeadModuleMk2StandardCircleType(this.value);
  final int value;

  static LibHeadModuleMk2StandardCircleType fromValue(int value) {
    return LibHeadModuleMk2StandardCircleType.values.firstWhere((type) => (type.value == value), orElse: () => LibHeadModuleMk2StandardCircleType.SLIDE);
  }
}

enum LibHeadModuleMk2PathCreateState {
  IDLE(0),
  WAIT_FOR_INITAL_ROTATION(1),
  INITIAL_ROTATION_CONFIRMED(2),
  CURVE_MOVING_TO_SECOND_POSE(4),
  CURVE_WAITING_AT_SECOND_POSE(5),
  CURVE_RETURN_TO_INITIAL_POSE(6),
  WAIT_FOR_HEAD_DOLLY_ORIENTATION(7),
  FREE_PATH_WAITING_FOR_POINTS(8),
  FREE_PATH_FINALISE(9);

  const LibHeadModuleMk2PathCreateState(this.value);
  final int value;

  static LibHeadModuleMk2PathCreateState fromValue(int value) {
    return LibHeadModuleMk2PathCreateState.values.firstWhere((state) => (state.value == value), orElse: () => LibHeadModuleMk2PathCreateState.IDLE);
  }
}

enum LibHeadModuleMk2InclineMode {
  INVALID(0),
  FLAT(1),
  SAFE(2),
  DANGER(3);

  const LibHeadModuleMk2InclineMode(this.value);
  final int value;

  static LibHeadModuleMk2InclineMode fromValue(int value) {
    return LibHeadModuleMk2InclineMode.values.firstWhere((mode) => (mode.value == value), orElse: () => LibHeadModuleMk2InclineMode.INVALID);
  }
}

enum LibHeadModuleMk2KroneSCalibration {
  NONE(0),
  BACK(1),
  LEFT(2),
  RIGHT(3);

  const LibHeadModuleMk2KroneSCalibration(this.value);
  final int value;

  static LibHeadModuleMk2KroneSCalibration fromValue(int value) {
    return LibHeadModuleMk2KroneSCalibration.values.firstWhere((calibration) => (calibration.value == value), orElse: () => LibHeadModuleMk2KroneSCalibration.NONE);
  }
}

enum LibHeadModuleMk2ParkMode {
  IDLE(0),
  POSITIONING(1),
  PARKED(2);

  const LibHeadModuleMk2ParkMode(this.value);
  final int value;

  static LibHeadModuleMk2ParkMode fromValue(int value) {
    return LibHeadModuleMk2ParkMode.values.firstWhere((mode) => (mode.value == value), orElse: () => LibHeadModuleMk2ParkMode.IDLE);
  }
}

enum LibHeadModuleMk2VisionModuleIpState {
  DISCONNECTED(0),
  WIFI_CLIENT_CONNECTING(1),
  WIFI_CLIENT_SSI_DNOT_FOUND(2),
  WIFI_CLIENT_PSK_FAILED(3),
  WIFI_CLIENT(4),
  ACCESS_POINT(5);

  const LibHeadModuleMk2VisionModuleIpState(this.value);
  final int value;

  static LibHeadModuleMk2VisionModuleIpState fromValue(int value) {
    return LibHeadModuleMk2VisionModuleIpState.values.firstWhere((state) => (state.value == value), orElse: () => LibHeadModuleMk2VisionModuleIpState.DISCONNECTED);
  }
}

enum LibHeadModuleMk2VisionModuleHdmiInState {
  NO_SIGNAL(0),
  RES720P(1),
  RES1080P(2),
  RES_UNSUPPORTED(3);

  const LibHeadModuleMk2VisionModuleHdmiInState(this.value);
  final int value;

  static LibHeadModuleMk2VisionModuleHdmiInState fromValue(int value) {
    return LibHeadModuleMk2VisionModuleHdmiInState.values.firstWhere((state) => (state.value == value), orElse: () => LibHeadModuleMk2VisionModuleHdmiInState.NO_SIGNAL);
  }
}

enum LibHeadModuleMk2VisionModuleTrackerState {
  IDLE(0),
  TRACKING_EASY(1),
  TRACKING_SPECIFIC_TARGET(2),
  TRACKING_SPECIFIC_TARGET_BUT_LOST(3),
  NO_RESPONSE(4),
  TRACKING_ARBITRARY_OBJECT(5),
  TRACKING_EASY_ROBUST(6),
  TRACKING_EASY_ROBUST_BUT_LOST(7),
  TRACKING_EASY_AUTO_RESTART(8),
  TRACKING_EASY_AUTO_RESTART_BUT_LOST(9),
  TRACKING_EASY_AUTO_RESTART_AND_SELECT(10),
  TRACKING_EASY_AUTO_RESTART_AND_SELECT_BUT_LOST(11);

  const LibHeadModuleMk2VisionModuleTrackerState(this.value);
  final int value;

  static LibHeadModuleMk2VisionModuleTrackerState fromValue(int value) {
    return LibHeadModuleMk2VisionModuleTrackerState.values.firstWhere((state) => (state.value == value), orElse: () => LibHeadModuleMk2VisionModuleTrackerState.IDLE);
  }
}

enum LibHeadModuleMk2VisionModuleFaceDetectionState {
  FREE_RUNNING(0),
  LEARNING(1),
  FACE_DETECTION_DOWN(2);

  const LibHeadModuleMk2VisionModuleFaceDetectionState(this.value);
  final int value;

  static LibHeadModuleMk2VisionModuleFaceDetectionState fromValue(int value) {
    return LibHeadModuleMk2VisionModuleFaceDetectionState.values.firstWhere((state) => (state.value == value), orElse: () => LibHeadModuleMk2VisionModuleFaceDetectionState.FREE_RUNNING);
  }
}

enum LibHeadModuleMk2VisionModuleEasyTrackingMode {
  STANDARD(0),
  ROBUST(1),
  AUTO_RESTART(2),
  AUTO_RESTART_AND_SELECT(3);

  const LibHeadModuleMk2VisionModuleEasyTrackingMode(this.value);
  final int value;

  static LibHeadModuleMk2VisionModuleEasyTrackingMode fromValue(int value) {
    return LibHeadModuleMk2VisionModuleEasyTrackingMode.values.firstWhere((mode) => (mode.value == value), orElse: () => LibHeadModuleMk2VisionModuleEasyTrackingMode.STANDARD);
  }
}

class LibHeadModuleMk2VisionModuleFaceDetection {
  double cxRelative = 0.0;
  double cyRelative = 0.0;
  double wRelative = 0.0;
  double hRelative = 0.0;
  int id = -1;
}

enum LibHeadModuleMk2VisionModuleTrackerError {
  NONE(0),
  LOST(1),
  MORE_THAN_ONE_FACE(2),
  ALREADY_TRACKING(3),
  CANNOT_FIND_INDEXED_FACE(4),
  NO_FACE_TO_START(5),
  ZOOM_IN_DETECTED(6),
  ZOOM_OUT_DETECTED(7),
  JUMP_DETECTED(8);

  const LibHeadModuleMk2VisionModuleTrackerError(this.value);
  final int value;

  static LibHeadModuleMk2VisionModuleTrackerError fromValue(int value) {
    return LibHeadModuleMk2VisionModuleTrackerError.values.firstWhere((error) => (error.value == value), orElse: () => LibHeadModuleMk2VisionModuleTrackerError.NONE);
  }
}

enum LibHeadModuleMk2VisionModuleFaceDetectionError {
  NONE(0),
  NOT_ENOUGH_FEATURES(1);

  const LibHeadModuleMk2VisionModuleFaceDetectionError(this.value);
  final int value;

  static LibHeadModuleMk2VisionModuleFaceDetectionError fromValue(int value) {
    return LibHeadModuleMk2VisionModuleFaceDetectionError.values.firstWhere((error) => (error.value == value), orElse: () => LibHeadModuleMk2VisionModuleFaceDetectionError.NONE);
  }
}

enum LibHeadModuleMk2VisionModuleUpdateStatus {
  IDLE(0),
  UPDATING_SYSTEM(1),
  UPDATING_MCU(2),
  FINISHED(3),
  ERROR(4);

  const LibHeadModuleMk2VisionModuleUpdateStatus(this.value);
  final int value;

  static LibHeadModuleMk2VisionModuleUpdateStatus fromValue(int value) {
    return LibHeadModuleMk2VisionModuleUpdateStatus.values.firstWhere((status) => (status.value == value), orElse: () => LibHeadModuleMk2VisionModuleUpdateStatus.IDLE);
  }
}

enum LibHeadModuleMk2VisionModuleCameraPosition {
  VERTICAL(0),
  HORIZONTAL(1);

  const LibHeadModuleMk2VisionModuleCameraPosition(this.value);
  final int value;
}

enum LibHeadModuleMk2TurntableCalibrationCmd {
  FIRST_POSE(0),
  MOVE_BODY(1),
  SECOND_POSE(2);

  const LibHeadModuleMk2TurntableCalibrationCmd(this.value);
  final int value;

  static LibHeadModuleMk2TurntableCalibrationCmd fromValue(int value) {
    return LibHeadModuleMk2TurntableCalibrationCmd.values.firstWhere((cmd) => (cmd.value == value), orElse: () => LibHeadModuleMk2TurntableCalibrationCmd.FIRST_POSE);
  }
}

enum LibHeadModuleMk2TurntableCalibrationT {
  NONE(0),
  PAN_TILT(1),
  TURNTABLE_TILT_FRONT(3),
  TURNTABLE_TILT_BACK(2);

  const LibHeadModuleMk2TurntableCalibrationT(this.value);
  final int value;

  static LibHeadModuleMk2TurntableCalibrationT fromValue(int value) {
    return LibHeadModuleMk2TurntableCalibrationT.values.firstWhere((type) => (type.value == value), orElse: () => LibHeadModuleMk2TurntableCalibrationT.NONE);
  }
}

enum LibHeadModuleMk2GlobalPointLearning {
  METHOD1_POINT1_FIRST_POSE(0),
  METHOD1_POINT1_SECOND_POSE(1),
  METHOD1_MOVE_TURNTABLE(2),
  METHOD1_POINT2_FIRST_POSE(3),
  METHOD1_POINT2_SECOND_POSE(4),
  METHOD2_FIRST_POSE(5),
  METHOD2_SECOND_POSE(6),
  METHOD1_START(7),
  METHOD2_START(8),
  METHOD1_POINT1_LEARN_WITH_LASER(9),
  METHOD1_MOVE_TURNTABLE_LEARN_WITH_LASER(10),
  METHOD1_POINT2_LEARN_WITH_LASER(11),
  METHOD2_LEARN_WITH_LASER(12),
  SKIP(13),
  NONE(14);

  const LibHeadModuleMk2GlobalPointLearning(this.value);
  final int value;

  static LibHeadModuleMk2GlobalPointLearning fromValue(int value) {
    return LibHeadModuleMk2GlobalPointLearning.values.firstWhere((cmd) => (cmd.value == value), orElse: () => LibHeadModuleMk2GlobalPointLearning.NONE);
  }
}

class LibHeadModuleMk2VisionModuleLensCalibrationData {
  double cropFactor = 0.0;
  int fieldOfViewMm = 0;
  int fieldOfViewMinMm = 0;
  int fieldOfViewMaxMm = 0;
}

class LibHeadModuleMk2PhoneModeSettingsData {
  double deadzone = 0.0;
  double trackingSensitivity = 0.0;
}

class LibHeadModuleMk2VisionModuleSettingsData {
  int stmFwVerMinor = 0;
  int stmFwVerMajor = 0;
  int rpiFwVerMinor = 0;
  int rpiFwVerMajor = 0;
  double trackingSensitivity = 0.0;
  double deadzone = 0.0;
  LibHeadModuleMk2VisionModuleEasyTrackingMode easyTrackingMode = LibHeadModuleMk2VisionModuleEasyTrackingMode.STANDARD;
  LibHeadModuleMk2VisionModuleLensCalibrationData lensCalibrationData = LibHeadModuleMk2VisionModuleLensCalibrationData();
}

enum LibHeadModuleMk2VisionModuleFaceSearch {
  INSTANT_LEFT(0),
  INSTANT_RIGHT(1),
  SPECIFIC_FACE(2),
  AUTO_RESTART_AND_SELECT_LEFT(3),
  AUTO_RESTART_AND_SELECT_RIGHT(4),
  STOP(5),
  IDLE(99);

  const LibHeadModuleMk2VisionModuleFaceSearch(this.value);
  final int value;

  static LibHeadModuleMk2VisionModuleFaceSearch fromValue(int value) {
    return LibHeadModuleMk2VisionModuleFaceSearch.values.firstWhere((mode) => (mode.value == value), orElse: () => LibHeadModuleMk2VisionModuleFaceSearch.IDLE);
  }
}

class LibHeadModuleMk2Status {
  LibHeadModuleMk2HeadState state = LibHeadModuleMk2HeadState.IDLE;
  List<int> targetValid = List<int>.filled(16, 0);
  List<int> keyposeValid = List<int>.filled(16, 0);
  List<int> remotePosValid = List<int>.filled(16, 0);
  double targetTransitionRatio = 0.0;
  double keyposeMoveRatio = 0.0;
  double remoteMoveRatio = 0.0;
  double keyposeTempMoveDurationSec = 0.0;
  int currentTargetIndex = 0;
  int currentKeyposeAimIndex = 0;
  int currentKeyposeStartIndex = 0;
  int currentRemotePosAimIndex = 0;
  int currentRemotePosStartIndex = 0;
  int haveLaserModule = 0;
  int haveFocusModule = 0;
  int haveFocusPlusPro = 0;
  int haveRemoteModule = 0;
  int headCalibrated = 0;
  int lensCalibrated = 0;
  int recordValid = 0;
  int recordRunning = 0;
  int recordPlaybackRunning = 0;
  int remoteModuleCalibrated = 0;
  int timelapseRunning = 0;
  int stopmotionRunning = 0;
  int stopmotionBusy = 0;
  int headMovedInRecordedState = 0;
  int keyposeInitialLocationOk = 0;
  int batteryLevel = 0;
  int batteryLevelRemote = 0;
  int batteryLevelRemoteFocusPlus = 0;
  int batteryLevelRemoteTiltHeadOne = 0;
  int batteryLevelRemoteDolly = 0;
  int focusAutoCalibTrialCount = 0;
  int remoteModuleIsLocating = 0;
  int mode360Running = 0;
  int mode360Busy = 0;
  int mode360Preview = 0;
  int motorSlipDetected = 0;
  int isFocusWorkAsZoom = 0;
  int remoteModuleFailedToMove = 0;
  int remoteDevicesConnectionOk = 0;
  int focusDirectionCalibrationDone = 0;
  int highPowerModePanTiltEnabled = 0;
  double currentFocusDistanceCm = 0.0;
  int remoteDeviceState = 0;
  int thisIsHeadOneFmSetup = 0;
  LibHeadModuleMk2UiState uiState = LibHeadModuleMk2UiState.NONE;
  EdlSetup configuration = EdlSetup.NONE;
  LibHeadModuleMk2LensLearningState lensLearningState = LibHeadModuleMk2LensLearningState.IDLE;
  int dollyHaveValidPath = 0;
  int dollyPathRecoveryRunning = 0;
  int dollyPathDisturbed = 0;
  LibHeadModuleMk2StandardCircleType dollyPathType = LibHeadModuleMk2StandardCircleType.NONE;
  LibHeadModuleMk2PathCreateState dollyPathCreateState = LibHeadModuleMk2PathCreateState.IDLE;
  LibHeadModuleMk2RemoteDeviceType remoteDeviceType = LibHeadModuleMk2RemoteDeviceType.NONE;
  int dollyHeadOrientationAutoAdjusting = 0;
  int sequencerModeEnabled = 0;
  int dragonframeIsActive = 0;
  int dragonframeVersionMajor = 0;
  int dragonframeVersionMinor = 0;
  int dragonframeVersionPatch = 0;
  int jibOneA0Ind = 0;
  int jibOneHardLimitIsValid = 0;
  double jiboneSetupAngleDeg = 0.0;
  double jiboneSetupAngleDegEstimation = 0.0;
  int inclineWarning = 0;
  LibHeadModuleMk2ParkMode parkMode = LibHeadModuleMk2ParkMode.IDLE;
  LibHeadModuleMk2InclineMode inclineMode = LibHeadModuleMk2InclineMode.INVALID;
  double inclineTiltDeg = 0.0;
  int isSimpleFocusCalibrationDone = 0;
  int isPanModuleConnected = 0;
  int failedToMovePanModule = 0;
  int batteryLevelRemotePanModule = 0;
  int isPhoneModeRunning = 0;
  List<int> visionModuleTargetSlotIsValid = List<int>.filled(3, 0);
  int visionModuleIsConnected = 0;
  int visionModuleIsLensCalibrated = 0;
  int visionModuleIsLimitsCalibrated = 0;
  LibHeadModuleMk2VisionModuleTrackerError visionModuleTrackerError = LibHeadModuleMk2VisionModuleTrackerError.NONE;
  LibHeadModuleMk2VisionModuleFaceDetectionError visionModuleFaceDetectionError = LibHeadModuleMk2VisionModuleFaceDetectionError.NONE;
  LibHeadModuleMk2VisionModuleHdmiInState visionModuleHdmiInState = LibHeadModuleMk2VisionModuleHdmiInState.NO_SIGNAL;
  LibHeadModuleMk2VisionModuleFaceDetectionState visionModuleFaceDetectionState = LibHeadModuleMk2VisionModuleFaceDetectionState.FREE_RUNNING;
  int visionModuleCurrentTargetIndex = 0;
  double visionModuleTrackingRectangleWRelative = 0.0;
  double visionModuleTrackingRectangleCxRelative = 0.0;
  double visionModuleTrackingRectangleCyRelative = 0.0;
  LibHeadModuleMk2VisionModuleIpState visionModuleIpState = LibHeadModuleMk2VisionModuleIpState.DISCONNECTED;
  LibHeadModuleMk2VisionModuleTrackerState visionModuleTrackerState = LibHeadModuleMk2VisionModuleTrackerState.IDLE;
  int visionModuleNumFacesInScene = 0;
  List<LibHeadModuleMk2VisionModuleFaceDetection> visionModuleFaceDetections = List<LibHeadModuleMk2VisionModuleFaceDetection>.generate(3, (_) => LibHeadModuleMk2VisionModuleFaceDetection());
  int visionModuleBatteryLevel = 0;
  int visionModuleWidthPix = 0;
  int visionModuleHeightPix = 0;
  LibHeadModuleMk2VisionModuleFaceSearch visionModuleCurrentFaceSearchMode = LibHeadModuleMk2VisionModuleFaceSearch.IDLE;
  LibHeadModuleMk2VisionModuleEasyTrackingMode visionModuleCurrentEasyTrackingMode = LibHeadModuleMk2VisionModuleEasyTrackingMode.STANDARD;
  LibHeadModuleMk2VisionModuleUpdateStatus visionModuleUpdateStatus = LibHeadModuleMk2VisionModuleUpdateStatus.IDLE;
  int visionModuleIsCameraConnected = 0;
  LibHeadModuleMk2VisionModuleFaceSearch visionModuleFaceSearchCurrentMode = LibHeadModuleMk2VisionModuleFaceSearch.IDLE;
  LibHeadModuleMk2VisionModuleCameraPosition visionModuleCameraPosition = LibHeadModuleMk2VisionModuleCameraPosition.VERTICAL;
  int focusModuleIsBrushlessCalibrated = 0;
  int focusModuleIsBrushlessCalibrationRunning = 0;
  int isTurntableConnected = 0;
  int isTurntableCalibrated = 0;
  LibHeadModuleMk2TurntableCalibrationCmd turntableCalibrationCurrentCmd = LibHeadModuleMk2TurntableCalibrationCmd.FIRST_POSE;
  int isGlobalPointCalibrated = 0;
  LibHeadModuleMk2TurntableCalibrationT headOneTurntableCalibrationState = LibHeadModuleMk2TurntableCalibrationT.NONE;
  LibHeadModuleMk2GlobalPointLearning globalPointCalibrationCurrentCmd = LibHeadModuleMk2GlobalPointLearning.NONE;
  int systemStabilityCheck = 0;
  LibHeadModuleMk2KroneSCalibration kroneSCalibration = LibHeadModuleMk2KroneSCalibration.NONE;
  double chainMotionPercentageCompleted = 0.0;
  List<int> multiPointPositionAssignInd = List<int>.filled(12, -1);
  int isRollConnected = 0;
  double batteryLevelRemoteTurntableHeadOne = 0.0;
  double batteryLevelRemoteRollHeadOne = 0.0;
  int rollAxisIsVerticalModeEnabled = 0;
}

class LibHeadModuleMk2SequenceState {
  int movingTo = 0;
  double subSeqPercentageCompleted = 0.0;
  List<double> motionDurationSec = List<double>.filled(5, 0.0);
  List<double> speed = List<double>.filled(5, 0.0);
  List<int> keyposeSlots = List<int>.filled(6, 0);
  int isAtInitialPosition = 0;
  int isLoopEnabled = 0;
  double accelRatio = 0.0;
}

class LibHeadModuleMk2Settings {
  int isBuzzerMuted = 0;
  int focusBacklashEnc = 0;
  int focusBacklashEpoch = 0;
  int triggerDurationMs = 0;
  int laserXOffsetMm100x = 0;
  int laserZOffsetMm100x = 0;
  int laserXOffsetInd = 0;
  int laserZOffsetInd = 0;
  int autoPowerOffSec = 0;
  double sensorXOffsetInd = 0.0;
  double sensorYOffsetInd = 0.0;
  double sensorZOffsetInd = 0.0;
  double laserZOffsetIndV2 = 0.0;
  int isSystemStabilityEnabled = 0;
  int liveModeEnabled = 0;
}

class LibHeadModuleMk2LensLearningStatus {
  int ind = 0;
  double distCm = 0.0;
  int posEnc = 0;
  double minDistCm = 0.0;
  double maxDistCm = 0.0;
  int travelDistanceEnc = 0;
  LibHeadModuleMk2LensModelDataInsertResult lastInsertResult = LibHeadModuleMk2LensModelDataInsertResult.INVALID;
}

class LibHeadModuleMk2HeadVersionData {
  int uniqueIdLow = 0;
  int uniqueIdMid = 0;
  int uniqueIdHigh = 0;
  int hardwareVersionMinor = 0;
  int hardwareVersionMajor = 0;
  int firmwareVersionMinor = 0;
  int firmwareVersionMajor = 0;
}

class LibHeadModuleMk2KeyposeUniqueID {
  int index = 0;
  int uniqueId = 0;
}

class LibHeadModuleMk2TargetUniqueID {
  int index = 0;
  int uniqueId = 0;
}

class LibHeadModuleMk2RemotePosUniqueID {
  int index = 0;
  int uniqueId = 0;
}

class LibHeadModuleMk2KeyposeMoveCmd {
  int startIndex = 0;
  int aimIndex = 0;
  int isLoopEnabled = 0;
  double relativeSpeed = 0.0;
  double accelInRatio = 0.0;
  double accelOutRatio = 0.0;
  double fixedDurationSec = 0.0;
}

class LibHeadModuleMk2RemotePositionMoveCmd {
  int startIndex = 0;
  int aimIndex = 0;
  int isLoopEnabled = 0;
  double relativeSpeed = 0.0;
  double accelInRatio = 0.0;
  double accelOutRatio = 0.0;
  double fixedDurationSec = 0.0;
}

class LibHeadModuleMk2RecordStatus {
  double currentRecordTimeSec = 0.0;
  double currentPlaybackTimeSec = 0.0;
  int isSuitableForMotionWarper = 0;
}

class LibHeadModuleMk2RemoteVersion {
  int readyFlag = 0;
  int remoteDevice0Type = 0;
  int remoteDevice0HwVerMinor = 0;
  int remoteDevice0HwVerMajor = 0;
  int remoteDevice0FwVerMinor = 0;
  int remoteDevice0FwVerMajor = 0;
  int remoteDevice0UniqueIdLow = 0;
  int remoteDevice0UniqueIdMid = 0;
  int remoteDevice0UniqueIdHigh = 0;
  int remoteDevice1Type = 0;
  int remoteDevice1HwVerMinor = 0;
  int remoteDevice1HwVerMajor = 0;
  int remoteDevice1FwVerMinor = 0;
  int remoteDevice1FwVerMajor = 0;
  int remoteDevice1UniqueIdLow = 0;
  int remoteDevice1UniqueIdMid = 0;
  int remoteDevice1UniqueIdHigh = 0;
  int remoteDevice2Type = 0;
  int remoteDevice2HwVerMinor = 0;
  int remoteDevice2HwVerMajor = 0;
  int remoteDevice2FwVerMinor = 0;
  int remoteDevice2FwVerMajor = 0;
  int remoteDevice2UniqueIdLow = 0;
  int remoteDevice2UniqueIdMid = 0;
  int remoteDevice2UniqueIdHigh = 0;
  int remoteDevice3Type = 0;
  int remoteDevice3HwVerMinor = 0;
  int remoteDevice3HwVerMajor = 0;
  int remoteDevice3FwVerMinor = 0;
  int remoteDevice3FwVerMajor = 0;
  int remoteDevice3UniqueIdLow = 0;
  int remoteDevice3UniqueIdMid = 0;
  int remoteDevice3UniqueIdHigh = 0;
  int remoteDevice4Type = 0;
  int remoteDevice4HwVerMinor = 0;
  int remoteDevice4HwVerMajor = 0;
  int remoteDevice4FwVerMinor = 0;
  int remoteDevice4FwVerMajor = 0;
  int remoteDevice4UniqueIdLow = 0;
  int remoteDevice4UniqueIdMid = 0;
  int remoteDevice4UniqueIdHigh = 0;
}

class LibHeadModuleMk2TimelapseStatus {
  int pauseFlag = 0;
  int totalPauseSec = 0;
  int shotCounterUntil = 0;
  int howLongAreWeHereForSec = 0;
  int shotCounterTotalPlanned = 0;
  int startTimeEpoch = 0;
  int postponeTimeSec = 0;
  int remainingTimeSec = 0;
}

class LibHeadModuleMk2StopmotionStatus {
  int currentFrame = 0;
  int shotCounterUntil = 0;
  int shotCounterTotalPlanned = 0;
}

class LibHeadModuleMk2Mode360Status {
  int isAutomatic = 0;
  int shotCounterUntil = 0;
  int shotCounterTotalPlanned = 0;
  int isVideoTurntableModeEnabled = 0;
  double moveDurationSec = 0.0;
  double moveRatio = 0.0;
}

class LibHeadModuleMk2RemoteFirmwareVersions {
  int remoteHeadOneFirmwareVersionMajor = 0;
  int remoteHeadOneFirmwareVersionMinor = 0;
  int remoteSlideDollyFirmwareVersionMajor = 0;
  int remoteSlideDollyFirmwareVersionMinor = 0;
}

class LibHeadModuleMk2DigitalReadout {
  double panDeg = 0.0;
  double tiltDeg = 0.0;
  double focusCm = 0.0;
  double sliderCm = 0.0;
  double jibPanDeg = 0.0;
  double jibTiltDeg = 0.0;
  double focusPercent = 0.0;
}

enum LibHeadModuleMk2SimpleLensCalibrationCmd {
  FULL(0),
  LEFT(1),
  RIGHT(2);

  const LibHeadModuleMk2SimpleLensCalibrationCmd(this.value);
  final int value;
}

class LibHeadModule {

  int appendChecksum(List<int> ptr, int len) {
    late int checksum;
    checksum = 0;
    for (var i = 0; i < len; i++) {
      checksum = (checksum + (ptr[i] & 0xFF));
    }
    LibHeadModuleUtil.put16b(ptr, len, checksum);
    return 0;
  }

  int statusGet(List<int> ptr, List<int> len) {
    ptr[0] = 2;
    ptr[1] = 1;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int statusParse(List<int> ptr, LibHeadModuleMk2Status arg) {
    late int baseIndex;
    arg.state = LibHeadModuleMk2HeadState.fromValue(ptr[1]);
    for (var i = 0; i < 8; i++) {
      if (((ptr[2] & (1 << i)) != 0)) {
        arg.targetValid[i] = 1;
        arg.keyposeValid[i] = 1;
      } else {
        arg.targetValid[i] = 0;
        arg.keyposeValid[i] = 0;
      }
    }
    for (var i = 0; i < 8; i++) {
      if (((ptr[106] & (1 << i)) != 0)) {
        arg.targetValid[(i + 8)] = 1;
        arg.keyposeValid[(i + 8)] = 1;
      } else {
        arg.targetValid[(i + 8)] = 0;
        arg.keyposeValid[(i + 8)] = 0;
      }
    }
    arg.headCalibrated = ((ptr[3] & 0x1) >> 0);
    arg.haveLaserModule = ((ptr[3] & 0x2) >> 1);
    arg.haveFocusModule = ((ptr[3] & 0x4) >> 2);
    arg.haveRemoteModule = ((ptr[3] & 0x8) >> 3);
    arg.lensCalibrated = ((ptr[3] & 0x10) >> 4);
    arg.recordRunning = ((ptr[3] & 0x20) >> 5);
    arg.recordPlaybackRunning = ((ptr[3] & 0x40) >> 6);
    arg.recordValid = ((ptr[3] & 0x80) >> 7);
    arg.keyposeMoveRatio = ((ptr[4]).toDouble() / 100.0);
    arg.targetTransitionRatio = ((ptr[4]).toDouble() / 100.0);
    arg.currentTargetIndex = ptr[5];
    arg.currentKeyposeStartIndex = ptr[108];
    arg.currentKeyposeAimIndex = ptr[109];
    arg.configuration = EdlSetup.fromValue(ptr[6]);
    arg.uiState = LibHeadModuleMk2UiState.fromValue((ptr[7] & 0xF));
    arg.batteryLevelRemoteTiltHeadOne = (((((ptr[7] & 0xF0) >> 4) * 100.0) / 15.0)).toInt();
    arg.currentFocusDistanceCm = ((LibHeadModuleUtil.make16b(ptr, 8)).toDouble() / 10.0);
    for (var i = 0; i < 8; i++) {
      if (((ptr[10] & (1 << i)) != 0)) {
        arg.remotePosValid[i] = 1;
      } else {
        arg.remotePosValid[i] = 0;
      }
    }
    for (var i = 0; i < 8; i++) {
      if (((ptr[107] & (1 << i)) != 0)) {
        arg.remotePosValid[(i + 8)] = 1;
      } else {
        arg.remotePosValid[(i + 8)] = 0;
      }
    }
    arg.currentRemotePosStartIndex = ptr[110];
    arg.currentRemotePosAimIndex = ptr[111];
    arg.remoteMoveRatio = (((ptr[12]).toSigned(8)).toDouble() / 100.0);
    arg.remoteMoveRatio = (arg.remoteMoveRatio).abs();
    arg.remoteDeviceState = (ptr[13] & 0x1F);
    arg.motorSlipDetected = (((ptr[13] & 0x80) != 0) ? 1 : 0);
    arg.highPowerModePanTiltEnabled = (((ptr[13] & 0x40) != 0) ? 1 : 0);
    arg.remoteModuleFailedToMove = (((ptr[13] & 0x20) != 0) ? 1 : 0);
    arg.remoteModuleCalibrated = ((ptr[14] & 0x1) >> 0);
    arg.timelapseRunning = ((ptr[14] & 0x2) >> 1);
    arg.keyposeInitialLocationOk = ((ptr[14] & 0x4) >> 2);
    arg.remoteModuleIsLocating = ((ptr[14] & 0x8) >> 3);
    arg.stopmotionRunning = ((ptr[14] & 0x10) >> 4);
    arg.stopmotionBusy = ((ptr[14] & 0x20) >> 5);
    arg.mode360Busy = ((ptr[14] & 0x20) >> 5);
    arg.headMovedInRecordedState = ((ptr[14] & 0x40) >> 6);
    arg.mode360Running = ((ptr[14] & 0x80) >> 7);
    arg.lensLearningState = LibHeadModuleMk2LensLearningState.fromValue(ptr[15]);
    arg.focusAutoCalibTrialCount = ptr[16];
    arg.batteryLevel = ((((ptr[17] & 0xF) * 100.0) / 15.0)).toInt();
    arg.batteryLevelRemote = (((((ptr[17] & 0xF0) >> 4) * 100.0) / 15.0)).toInt();
    arg.dollyHaveValidPath = (((ptr[18] & 0x1) != 0) ? 1 : 0);
    arg.dollyPathRecoveryRunning = (((ptr[18] & 0x2) != 0) ? 1 : 0);
    arg.dollyPathDisturbed = (((ptr[18] & 0x4) != 0) ? 1 : 0);
    arg.dollyHeadOrientationAutoAdjusting = (((ptr[18] & 0x8) != 0) ? 1 : 0);
    arg.sequencerModeEnabled = (((ptr[18] & 0x10) != 0) ? 1 : 0);
    arg.dragonframeIsActive = (((ptr[18] & 0x20) != 0) ? 1 : 0);
    arg.inclineWarning = (((ptr[18] & 0x40) != 0) ? 1 : 0);
    arg.failedToMovePanModule = (((ptr[18] & 0x80) != 0) ? 1 : 0);
    arg.dollyPathType = LibHeadModuleMk2StandardCircleType.fromValue(ptr[19]);
    arg.dollyPathCreateState = LibHeadModuleMk2PathCreateState.fromValue(ptr[20]);
    if ((arg.haveRemoteModule != 0)) {
      arg.remoteDeviceType = LibHeadModuleMk2RemoteDeviceType.fromValue(ptr[21]);
      mRemoteDeviceType = arg.remoteDeviceType;
    } else {
      arg.remoteDeviceType = LibHeadModuleMk2RemoteDeviceType.NONE;
    }
    arg.dragonframeVersionMajor = ptr[22];
    arg.dragonframeVersionMinor = ptr[23];
    arg.dragonframeVersionPatch = ptr[24];
    arg.jiboneSetupAngleDeg = ((LibHeadModuleUtil.make16b(ptr, 25)).toDouble() / 10.0);
    arg.jiboneSetupAngleDegEstimation = ((LibHeadModuleUtil.make16b(ptr, 27)).toDouble() / 10.0);
    arg.parkMode = LibHeadModuleMk2ParkMode.fromValue(ptr[29]);
    arg.inclineMode = LibHeadModuleMk2InclineMode.fromValue(ptr[30]);
    arg.isSimpleFocusCalibrationDone = ptr[31];
    arg.batteryLevelRemotePanModule = ptr[32];
    arg.isPanModuleConnected = ptr[33];
    arg.jibOneHardLimitIsValid = ((ptr[34] & 0x80) >> 7);
    arg.jibOneA0Ind = (ptr[34] & 0x7F);
    arg.batteryLevelRemoteFocusPlus = ptr[35];
    arg.haveFocusPlusPro = (((ptr[36] & 0x1) != 0) ? 1 : 0);
    arg.remoteDevicesConnectionOk = (((ptr[36] & 0x2) != 0) ? 1 : 0);
    arg.focusDirectionCalibrationDone = (((ptr[36] & 0x4) != 0) ? 1 : 0);
    arg.isFocusWorkAsZoom = (((ptr[36] & 0x8) != 0) ? 1 : 0);
    arg.mode360Preview = (((ptr[36] & 0x20) != 0) ? 1 : 0);
    arg.isPhoneModeRunning = (((ptr[36] & 0x40) != 0) ? 1 : 0);
    arg.thisIsHeadOneFmSetup = (((ptr[36] & 0x80) != 0) ? 1 : 0);
    for (var i = 0; i < 3; i++) {
      arg.visionModuleTargetSlotIsValid[i] = (((ptr[37] & (1 << i)) != 0) ? 1 : 0);
    }
    arg.visionModuleIsConnected = (((ptr[37] & 0x8) != 0) ? 1 : 0);
    arg.visionModuleIsLensCalibrated = (((ptr[37] & 0x10) != 0) ? 1 : 0);
    arg.visionModuleIsCameraConnected = (((ptr[37] & 0x20) != 0) ? 1 : 0);
    arg.visionModuleIsLimitsCalibrated = (((ptr[37] & 0x40) != 0) ? 1 : 0);
    arg.visionModuleTrackerError = LibHeadModuleMk2VisionModuleTrackerError.fromValue(ptr[38]);
    arg.visionModuleFaceDetectionError = LibHeadModuleMk2VisionModuleFaceDetectionError.fromValue(ptr[39]);
    arg.visionModuleHdmiInState = LibHeadModuleMk2VisionModuleHdmiInState.fromValue(ptr[40]);
    arg.visionModuleFaceDetectionState = LibHeadModuleMk2VisionModuleFaceDetectionState.fromValue(ptr[41]);
    arg.visionModuleCurrentTargetIndex = ptr[42];
    arg.visionModuleTrackingRectangleWRelative = ((LibHeadModuleUtil.make16b(ptr, 43)).toDouble() / 1000.0);
    arg.visionModuleTrackingRectangleCxRelative = ((LibHeadModuleUtil.make16b(ptr, 45)).toDouble() / 1000.0);
    arg.visionModuleTrackingRectangleCyRelative = ((LibHeadModuleUtil.make16b(ptr, 47)).toDouble() / 1000.0);
    arg.visionModuleIpState = LibHeadModuleMk2VisionModuleIpState.fromValue(ptr[49]);
    arg.visionModuleTrackerState = LibHeadModuleMk2VisionModuleTrackerState.fromValue(ptr[50]);
    arg.visionModuleNumFacesInScene = ptr[51];
    for (var i = 0; i < 3; i++) {
      baseIndex = (52 + (i * 9));
      arg.visionModuleFaceDetections[i].cxRelative = ((LibHeadModuleUtil.make16b(ptr, baseIndex)).toDouble() / 1000.0);
      arg.visionModuleFaceDetections[i].cyRelative = ((LibHeadModuleUtil.make16b(ptr, (baseIndex + 2))).toDouble() / 1000.0);
      arg.visionModuleFaceDetections[i].wRelative = ((LibHeadModuleUtil.make16b(ptr, (baseIndex + 4))).toDouble() / 1000.0);
      arg.visionModuleFaceDetections[i].hRelative = ((LibHeadModuleUtil.make16b(ptr, (baseIndex + 6))).toDouble() / 1000.0);
      arg.visionModuleFaceDetections[i].id = ptr[(baseIndex + 8)];
    }
    arg.visionModuleBatteryLevel = ptr[79];
    arg.visionModuleWidthPix = LibHeadModuleUtil.make32b(ptr, 80);
    arg.visionModuleHeightPix = LibHeadModuleUtil.make32b(ptr, 84);
    arg.visionModuleCurrentEasyTrackingMode = LibHeadModuleMk2VisionModuleEasyTrackingMode.fromValue(ptr[88]);
    arg.visionModuleCurrentFaceSearchMode = LibHeadModuleMk2VisionModuleFaceSearch.fromValue(ptr[89]);
    arg.visionModuleUpdateStatus = LibHeadModuleMk2VisionModuleUpdateStatus.fromValue(ptr[90]);
    arg.inclineTiltDeg = ((LibHeadModuleUtil.make32b(ptr, 91)).toDouble() / 1000.0);
    arg.focusModuleIsBrushlessCalibrated = (((ptr[95] & 0x1) != 0) ? 1 : 0);
    arg.focusModuleIsBrushlessCalibrationRunning = (((ptr[95] & 0x2) != 0) ? 1 : 0);
    arg.isTurntableConnected = (((ptr[95] & 0x4) != 0) ? 1 : 0);
    arg.isTurntableCalibrated = (((ptr[95] & 0x8) != 0) ? 1 : 0);
    arg.turntableCalibrationCurrentCmd = LibHeadModuleMk2TurntableCalibrationCmd.fromValue(((ptr[95] & 0xF0) >> 4));
    arg.isGlobalPointCalibrated = (((ptr[96] & 0x1) != 0) ? 1 : 0);
    arg.systemStabilityCheck = (((ptr[96] & 0x2) != 0) ? 1 : 0);
    arg.headOneTurntableCalibrationState = LibHeadModuleMk2TurntableCalibrationT.fromValue(((ptr[96] & 0xC) >> 2));
    arg.globalPointCalibrationCurrentCmd = LibHeadModuleMk2GlobalPointLearning.fromValue(((ptr[96] & 0xF0) >> 4));
    arg.batteryLevelRemoteDolly = ptr[97];
    arg.kroneSCalibration = LibHeadModuleMk2KroneSCalibration.fromValue(ptr[98]);
    arg.chainMotionPercentageCompleted = ((ptr[99]).toDouble() / 100.0);
    arg.multiPointPositionAssignInd[0] = LibHeadModuleUtil.makeS8b(ptr, 100);
    arg.multiPointPositionAssignInd[1] = LibHeadModuleUtil.makeS8b(ptr, 101);
    arg.multiPointPositionAssignInd[2] = LibHeadModuleUtil.makeS8b(ptr, 102);
    arg.multiPointPositionAssignInd[3] = LibHeadModuleUtil.makeS8b(ptr, 103);
    arg.multiPointPositionAssignInd[4] = LibHeadModuleUtil.makeS8b(ptr, 104);
    arg.multiPointPositionAssignInd[5] = LibHeadModuleUtil.makeS8b(ptr, 105);
    arg.multiPointPositionAssignInd[6] = LibHeadModuleUtil.makeS8b(ptr, 112);
    arg.multiPointPositionAssignInd[7] = LibHeadModuleUtil.makeS8b(ptr, 113);
    arg.multiPointPositionAssignInd[8] = LibHeadModuleUtil.makeS8b(ptr, 114);
    arg.multiPointPositionAssignInd[9] = LibHeadModuleUtil.makeS8b(ptr, 115);
    arg.multiPointPositionAssignInd[10] = LibHeadModuleUtil.makeS8b(ptr, 116);
    arg.multiPointPositionAssignInd[11] = LibHeadModuleUtil.makeS8b(ptr, 117);
    if ((ptr.length > 118)) {
      if (((ptr[118] & 0x1) != 0)) {
        arg.isRollConnected = 1;
      } else {
        arg.isRollConnected = 0;
      }
      arg.rollAxisIsVerticalModeEnabled = (((ptr[118] & 0x2) != 0) ? 1 : 0);
      arg.batteryLevelRemoteTurntableHeadOne = ((((ptr[119] & 0xF) >> 0) * 100.0) / 15.0);
      arg.batteryLevelRemoteRollHeadOne = ((((ptr[119] & 0xF0) >> 4) * 100.0) / 15.0);
    }
    return 0;
  }

  int configurationSet(List<int> ptr, List<int> len, EdlSetup configuration) {
    ptr[0] = 3;
    ptr[1] = 201;
    ptr[2] = configuration.value;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int kroneSCalibration(List<int> ptr, List<int> len, LibHeadModuleMk2KroneSCalibration arg) {
    ptr[0] = 3;
    ptr[1] = 151;
    ptr[2] = arg.value;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int keyposeStore(List<int> ptr, List<int> len, int ind, int uniqueId) {
    ptr[0] = 7;
    ptr[1] = 5;
    ptr[2] = ind;
    LibHeadModuleUtil.put32b(ptr, 3, uniqueId);
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int keyposeDelete(List<int> ptr, List<int> len, int ind) {
    ptr[0] = 3;
    ptr[1] = 6;
    ptr[2] = ind;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int keyposeMove(List<int> ptr, List<int> len, LibHeadModuleMk2KeyposeMoveCmd arg) {
    ptr[0] = 17;
    ptr[1] = 7;
    ptr[2] = ((arg.startIndex == -1) ? 255 : arg.startIndex);
    ptr[3] = arg.aimIndex;
    ptr[4] = arg.isLoopEnabled;
    LibHeadModuleUtil.put16b(ptr, 5, ((arg.accelInRatio * 32000.0)).toInt());
    LibHeadModuleUtil.put16b(ptr, 7, ((arg.accelOutRatio * 32000.0)).toInt());
    LibHeadModuleUtil.put32b(ptr, 9, (((arg.relativeSpeed * 1000.0) * 32000.0)).toInt());
    LibHeadModuleUtil.put32b(ptr, 13, ((arg.fixedDurationSec * 1000.0)).toInt());
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int keyposeUniqueIdParse(List<int> ptr, LibHeadModuleMk2KeyposeUniqueID arg) {
    arg.index = ptr[1];
    arg.uniqueId = LibHeadModuleUtil.make32b(ptr, 2);
    return 0;
  }

  int keyposeAbort(List<int> ptr, List<int> len) {
    ptr[0] = 2;
    ptr[1] = 9;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int manualPanTilt(List<int> ptr, List<int> len, double panSpeedRelative, double tiltSpeedRelative) {
    ptr[0] = 6;
    ptr[1] = 10;
    LibHeadModuleUtil.put16b(ptr, 2, ((panSpeedRelative * 32000.0)).toInt());
    LibHeadModuleUtil.put16b(ptr, 4, ((tiltSpeedRelative * 32000.0)).toInt());
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int manualSlide(List<int> ptr, List<int> len, double slideSpeedRelative) {
    if (((mJiboneSetupAngleDegEstimation >= 0.0) && ((mRemoteDeviceType == LibHeadModuleMk2RemoteDeviceType.JIB_ONE) || (mRemoteDeviceType == LibHeadModuleMk2RemoteDeviceType.JIB_ONE_MK2)))) {
      slideSpeedRelative = (slideSpeedRelative * -1.0);
    }
    ptr[0] = 4;
    ptr[1] = 11;
    LibHeadModuleUtil.put16b(ptr, 2, ((slideSpeedRelative * 32000.0)).toInt());
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int headVersionGet(List<int> ptr, List<int> len) {
    ptr[0] = 2;
    ptr[1] = 13;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int headVersionParse(List<int> ptr, LibHeadModuleMk2HeadVersionData arg) {
    late int hardwareVersion;
    late int firmwareVersion;
    hardwareVersion = ptr[1];
    arg.hardwareVersionMinor = ((hardwareVersion & 0xF) >> 0);
    arg.hardwareVersionMajor = ((hardwareVersion & 0xF0) >> 4);
    firmwareVersion = LibHeadModuleUtil.make16b(ptr, 2);
    arg.firmwareVersionMinor = ((firmwareVersion & 0xFF) >> 0);
    arg.firmwareVersionMajor = ((firmwareVersion & 0xFF00) >> 8);
    arg.uniqueIdLow = LibHeadModuleUtil.make32b(ptr, 4);
    arg.uniqueIdMid = LibHeadModuleUtil.make32b(ptr, 8);
    arg.uniqueIdHigh = LibHeadModuleUtil.make32b(ptr, 12);
    return 0;
  }

  int uiStateChange(List<int> ptr, List<int> len, LibHeadModuleMk2UiState uiState) {
    ptr[0] = 3;
    ptr[1] = 14;
    ptr[2] = uiState.value;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int keyposeMoveDurationGet(List<int> ptr, List<int> len) {
    ptr[0] = 2;
    ptr[1] = 15;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int keyposeMoveDurationParse(List<int> ptr, List<double> keyposeMoveDurationSec) {
    keyposeMoveDurationSec[0] = ((LibHeadModuleUtil.make32b(ptr, 1)).toDouble() / 1000.0);
    return 0;
  }

  int targetUniqueIdParse(List<int> ptr, LibHeadModuleMk2TargetUniqueID arg) {
    arg.index = ptr[1];
    arg.uniqueId = LibHeadModuleUtil.make32b(ptr, 2);
    return 0;
  }

  int targetTransitionDurationParse(List<int> ptr, List<double> targetTransitionDurationSec) {
    targetTransitionDurationSec[0] = ((LibHeadModuleUtil.make32b(ptr, 1)).toDouble() / 1000.0);
    return 0;
  }

  int remotePositionStore(List<int> ptr, List<int> len, int ind, int uniqueId) {
    ptr[0] = 7;
    ptr[1] = 24;
    ptr[2] = ind;
    LibHeadModuleUtil.put32b(ptr, 3, uniqueId);
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int remotePositionMove(List<int> ptr, List<int> len, LibHeadModuleMk2RemotePositionMoveCmd arg) {
    ptr[0] = 17;
    ptr[1] = 25;
    ptr[2] = arg.startIndex;
    ptr[3] = arg.aimIndex;
    ptr[4] = arg.isLoopEnabled;
    LibHeadModuleUtil.put32b(ptr, 5, (((arg.relativeSpeed * 1000.0) * 32000.0)).toInt());
    LibHeadModuleUtil.put16b(ptr, 9, ((arg.accelInRatio * 32000.0)).toInt());
    LibHeadModuleUtil.put16b(ptr, 11, ((arg.accelOutRatio * 32000.0)).toInt());
    LibHeadModuleUtil.put32b(ptr, 13, ((arg.fixedDurationSec * 1000.0)).toInt());
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int remotePositionMoveDurationGet(List<int> ptr, List<int> len) {
    ptr[0] = 2;
    ptr[1] = 26;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int remotePositionMoveDurationParse(List<int> ptr, List<double> remoteMoveDurationSec) {
    remoteMoveDurationSec[0] = ((LibHeadModuleUtil.make32b(ptr, 1)).toDouble() / 1000.0);
    return 0;
  }

  int recordStatusParse(List<int> ptr, LibHeadModuleMk2RecordStatus arg) {
    arg.currentRecordTimeSec = ((LibHeadModuleUtil.make32b(ptr, 1)).toDouble() / 1000.0);
    arg.currentPlaybackTimeSec = ((LibHeadModuleUtil.make32b(ptr, 5)).toDouble() / 1000.0);
    arg.isSuitableForMotionWarper = (ptr[9] & 0xFF);
    return 0;
  }

  int remoteUniqueIdParse(List<int> ptr, LibHeadModuleMk2RemotePosUniqueID arg) {
    arg.index = ptr[1];
    arg.uniqueId = LibHeadModuleUtil.make32b(ptr, 2);
    return 0;
  }

  int remotePositionDelete(List<int> ptr, List<int> len, int ind) {
    ptr[0] = 3;
    ptr[1] = 42;
    ptr[2] = ind;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int stopmotionStatusParse(List<int> ptr, LibHeadModuleMk2StopmotionStatus arg) {
    arg.shotCounterUntil = LibHeadModuleUtil.make32b(ptr, 1);
    arg.shotCounterTotalPlanned = LibHeadModuleUtil.make32b(ptr, 4);
    arg.currentFrame = LibHeadModuleUtil.make32b(ptr, 7);
    return 0;
  }

  int stopmotionShotListParse(List<int> ptr, List<int> shotList) {
    late int totalShotCount;
    late int shotIndex;
    totalShotCount = LibHeadModuleUtil.make16b(ptr, 1);
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

  int timelapseStatusParse(List<int> ptr, LibHeadModuleMk2TimelapseStatus arg) {
    arg.shotCounterUntil = LibHeadModuleUtil.makeU24b(ptr, 1);
    arg.howLongAreWeHereForSec = LibHeadModuleUtil.make32b(ptr, 4);
    arg.shotCounterTotalPlanned = LibHeadModuleUtil.makeU24b(ptr, 8);
    arg.startTimeEpoch = LibHeadModuleUtil.make32b(ptr, 11);
    arg.postponeTimeSec = LibHeadModuleUtil.makeU24b(ptr, 15);
    arg.pauseFlag = ptr[18];
    arg.totalPauseSec = LibHeadModuleUtil.make32b(ptr, 19);
    arg.remainingTimeSec = LibHeadModuleUtil.make32b(ptr, 23);
    return 0;
  }

  int timelapseFpsParse(List<int> ptr, List<double> fps) {
    fps[0] = ((LibHeadModuleUtil.make32b(ptr, 1)).toDouble() / 1000.0);
    return 0;
  }

  int lensLearnStatusGet(List<int> ptr, List<int> len) {
    ptr[0] = 2;
    ptr[1] = 51;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int lensLearnStatusParse(List<int> ptr, LibHeadModuleMk2LensLearningStatus arg) {
    arg.ind = ptr[1];
    arg.posEnc = LibHeadModuleUtil.makeS24b(ptr, 2);
    arg.distCm = ((LibHeadModuleUtil.make16b(ptr, 5)).toDouble() / 10.0);
    arg.minDistCm = ((LibHeadModuleUtil.make16b(ptr, 7)).toDouble() / 10.0);
    arg.maxDistCm = ((LibHeadModuleUtil.make16b(ptr, 9)).toDouble() / 10.0);
    arg.travelDistanceEnc = LibHeadModuleUtil.makeS24b(ptr, 11);
    arg.lastInsertResult = LibHeadModuleMk2LensModelDataInsertResult.fromValue(ptr[14]);
    return 0;
  }

  int settingsGet(List<int> ptr, List<int> len) {
    ptr[0] = 2;
    ptr[1] = 54;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int settingsBuzzerMutedSet(List<int> ptr, List<int> len, int isBuzzerMuted) {
    ptr[0] = 3;
    ptr[1] = 55;
    ptr[2] = isBuzzerMuted;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int settingsTriggerDurationSet(List<int> ptr, List<int> len, int triggerDurationMs) {
    ptr[0] = 4;
    ptr[1] = 56;
    LibHeadModuleUtil.put16b(ptr, 2, triggerDurationMs);
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int settingsParse(List<int> ptr, LibHeadModuleMk2Settings arg, bool isPro, bool hasLiveMode) {
    late double minDist;
    late int minInd;
    late double laserModuleXOffsetMm;
    late double diff;
    late double laserModuleZOffsetMm;
    arg.isBuzzerMuted = ptr[1];
    arg.focusBacklashEnc = LibHeadModuleUtil.make16b(ptr, 2);
    arg.focusBacklashEpoch = LibHeadModuleUtil.make32b(ptr, 4);
    arg.triggerDurationMs = LibHeadModuleUtil.make16b(ptr, 8);
    arg.laserXOffsetMm100x = LibHeadModuleUtil.make16b(ptr, 10);
    arg.laserZOffsetMm100x = LibHeadModuleUtil.make16b(ptr, 12);
    arg.autoPowerOffSec = LibHeadModuleUtil.make32b(ptr, 14);
    arg.sensorXOffsetInd = ((LibHeadModuleUtil.make16b(ptr, 18)).toDouble() / 10.0);
    arg.sensorYOffsetInd = ((LibHeadModuleUtil.make16b(ptr, 20)).toDouble() / 10.0);
    arg.sensorZOffsetInd = ((LibHeadModuleUtil.make16b(ptr, 22)).toDouble() / 10.0);
    arg.laserZOffsetIndV2 = ((LibHeadModuleUtil.make16b(ptr, 24)).toDouble() / 10.0);
    arg.isSystemStabilityEnabled = ptr[26];
    if (hasLiveMode) {
      arg.liveModeEnabled = ptr[32];
    } else {
      arg.liveModeEnabled = 0;
    }
    minDist = 99999999999.0;
    minInd = 0;
    for (var i = 0; i < 16; i++) {
      if ((!isPro && (i >= 10))) {
        continue;
      }
      laserModuleXOffsetMm = (isPro ? (82.9 + (4.62 * i)) : (78.5 + (4.62 * i)));
      diff = ((arg.laserXOffsetMm100x - (laserModuleXOffsetMm * 100.0))).abs();
      if ((diff < minDist)) {
        minDist = diff;
        minInd = i;
      }
    }
    arg.laserXOffsetInd = minInd;
    minDist = 99999999999.0;
    for (var i = 0; i < 14; i++) {
      if ((!isPro && (i >= 10))) {
        continue;
      }
      laserModuleZOffsetMm = (isPro ? (56.7 + (6.7 * (13 - i))) : (46.85 + (6.7 * (9 - i))));
      diff = ((arg.laserZOffsetMm100x - (laserModuleZOffsetMm * 100.0))).abs();
      if ((diff < minDist)) {
        minDist = diff;
        minInd = i;
      }
    }
    arg.laserZOffsetInd = minInd;
    return 0;
  }

  int mode360ParseStatus(List<int> ptr, LibHeadModuleMk2Mode360Status arg) {
    arg.shotCounterUntil = LibHeadModuleUtil.makeU24b(ptr, 1);
    arg.shotCounterTotalPlanned = LibHeadModuleUtil.makeU24b(ptr, 4);
    arg.isAutomatic = ptr[7];
    arg.isVideoTurntableModeEnabled = ptr[8];
    arg.moveDurationSec = (LibHeadModuleUtil.make32b(ptr, 9)).toDouble();
    arg.moveRatio = ((LibHeadModuleUtil.make16b(ptr, 13)).toDouble() / 1000.0);
    return 0;
  }

  int highPowerModePanTiltEnable(List<int> ptr, List<int> len, int isEnabled) {
    ptr[0] = 3;
    ptr[1] = 75;
    ptr[2] = isEnabled;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int slaveFirmwareVersionParse(List<int> ptr, LibHeadModuleMk2RemoteFirmwareVersions slaveFwVersions) {
    slaveFwVersions.remoteHeadOneFirmwareVersionMajor = ptr[3];
    slaveFwVersions.remoteHeadOneFirmwareVersionMinor = ptr[4];
    slaveFwVersions.remoteSlideDollyFirmwareVersionMajor = ptr[1];
    slaveFwVersions.remoteSlideDollyFirmwareVersionMinor = ptr[2];
    return 0;
  }

  LibHeadModuleMk2RemoteDeviceType remoteDeviceTypeParse(List<int> ptr) {
    return LibHeadModuleMk2RemoteDeviceType.fromValue(ptr[1]);
  }

  int dollyFreeMove(List<int> ptr, List<int> len, double angularSpeed, double linearSpeed) {
    ptr[0] = 6;
    ptr[1] = 79;
    LibHeadModuleUtil.put16b(ptr, 2, ((linearSpeed * 32000.0)).toInt());
    LibHeadModuleUtil.put16b(ptr, 4, ((angularSpeed * 32000.0)).toInt());
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int remoteDollyFreeMove(List<int> ptr, List<int> len, double angularSpeed, double linearSpeed) {
    ptr[0] = 7;
    ptr[1] = 214;
    ptr[2] = 1;
    LibHeadModuleUtil.put16b(ptr, 3, ((linearSpeed * 32000.0)).toInt());
    LibHeadModuleUtil.put16b(ptr, 5, ((angularSpeed * 32000.0)).toInt());
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int numericControlRead(List<int> ptr, List<int> len, int keypIndex) {
    ptr[0] = 4;
    ptr[1] = 83;
    ptr[2] = keypIndex;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int numericControlParse(List<int> ptr, List<int> keypIndex, LibHeadModuleMk2DigitalReadout readout) {
    keypIndex[0] = ptr[1];
    readout.panDeg = ((LibHeadModuleUtil.make32b(ptr, 2)).toDouble() / 1000.0);
    readout.tiltDeg = ((LibHeadModuleUtil.make32b(ptr, 6)).toDouble() / 1000.0);
    readout.focusCm = ((LibHeadModuleUtil.make32b(ptr, 10)).toDouble() / 1000.0);
    readout.sliderCm = ((LibHeadModuleUtil.make32b(ptr, 14)).toDouble() / 1000.0);
    readout.jibPanDeg = ((LibHeadModuleUtil.make32b(ptr, 18)).toDouble() / 1000.0);
    readout.jibTiltDeg = ((LibHeadModuleUtil.make32b(ptr, 22)).toDouble() / 1000.0);
    readout.focusPercent = ((LibHeadModuleUtil.make16b(ptr, 26)).toDouble() / 1000.0);
    if (((mJiboneSetupAngleDegEstimation >= 0.0) && ((mRemoteDeviceType == LibHeadModuleMk2RemoteDeviceType.JIB_ONE) || (mRemoteDeviceType == LibHeadModuleMk2RemoteDeviceType.JIB_ONE_MK2)))) {
      readout.sliderCm = (readout.sliderCm * -1.0);
      readout.jibTiltDeg = (readout.jibTiltDeg * -1.0);
    }
    return 0;
  }

  int numericControlPanMove(List<int> ptr, List<int> len, double panDeg) {
    ptr[0] = 7;
    ptr[1] = 85;
    ptr[2] = 0;
    LibHeadModuleUtil.put32b(ptr, 3, ((panDeg * 1000.0)).toInt());
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int numericControlTiltMove(List<int> ptr, List<int> len, double tiltDeg) {
    ptr[0] = 7;
    ptr[1] = 85;
    ptr[2] = 1;
    LibHeadModuleUtil.put32b(ptr, 3, ((tiltDeg * 1000.0)).toInt());
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int numericControlFocusMovePercent(List<int> ptr, List<int> len, double focusPercent) {
    ptr[0] = 7;
    ptr[1] = 85;
    ptr[2] = 7;
    LibHeadModuleUtil.put32b(ptr, 3, ((focusPercent * 1000.0)).toInt());
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int numericControlSliderMove(List<int> ptr, List<int> len, double sliderStepCm) {
    if (((mJiboneSetupAngleDegEstimation >= 0.0) && ((mRemoteDeviceType == LibHeadModuleMk2RemoteDeviceType.JIB_ONE) || (mRemoteDeviceType == LibHeadModuleMk2RemoteDeviceType.JIB_ONE_MK2)))) {
      sliderStepCm = (sliderStepCm * -1.0);
    }
    ptr[0] = 7;
    ptr[1] = 85;
    ptr[2] = 3;
    LibHeadModuleUtil.put32b(ptr, 3, ((sliderStepCm * 1000.0)).toInt());
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int sequencerStatusParse(List<int> ptr, LibHeadModuleMk2SequenceState state) {
    state.movingTo = ptr[1];
    state.subSeqPercentageCompleted = (ptr[2]).toDouble();
    state.motionDurationSec[0] = ((LibHeadModuleUtil.make16b(ptr, 3)).toDouble() / 10.0);
    state.motionDurationSec[1] = ((LibHeadModuleUtil.make16b(ptr, 5)).toDouble() / 10.0);
    state.motionDurationSec[2] = ((LibHeadModuleUtil.make16b(ptr, 7)).toDouble() / 10.0);
    state.motionDurationSec[3] = ((LibHeadModuleUtil.make16b(ptr, 9)).toDouble() / 10.0);
    state.motionDurationSec[4] = ((LibHeadModuleUtil.make16b(ptr, 11)).toDouble() / 10.0);
    state.speed[0] = ((LibHeadModuleUtil.make16b(ptr, 13)).toDouble() / 32000.0);
    state.speed[1] = ((LibHeadModuleUtil.make16b(ptr, 15)).toDouble() / 32000.0);
    state.speed[2] = ((LibHeadModuleUtil.make16b(ptr, 17)).toDouble() / 32000.0);
    state.speed[3] = ((LibHeadModuleUtil.make16b(ptr, 19)).toDouble() / 32000.0);
    state.speed[4] = ((LibHeadModuleUtil.make16b(ptr, 21)).toDouble() / 32000.0);
    state.keyposeSlots[0] = ptr[23];
    state.keyposeSlots[1] = ptr[24];
    state.keyposeSlots[2] = ptr[25];
    state.keyposeSlots[3] = ptr[26];
    state.keyposeSlots[4] = ptr[27];
    state.keyposeSlots[5] = ptr[28];
    state.isAtInitialPosition = ptr[29];
    state.isLoopEnabled = ptr[30];
    state.accelRatio = ((LibHeadModuleUtil.make16b(ptr, 31)).toDouble() / 32000.0);
    state.accelRatio = (state.accelRatio * 2.0);
    return 0;
  }

  int remoteVersionGet(List<int> ptr, List<int> len) {
    ptr[0] = 2;
    ptr[1] = 128;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int remoteVersionParse(List<int> ptr, LibHeadModuleMk2RemoteVersion readout) {
    late int remoteDevice0FirmwareVersion;
    late int remoteDevice0HardwareVersion;
    late int remoteDevice1FirmwareVersion;
    late int remoteDevice1HardwareVersion;
    late int remoteDevice2FirmwareVersion;
    late int remoteDevice2HardwareVersion;
    late int remoteDevice3FirmwareVersion;
    late int remoteDevice3HardwareVersion;
    late int remoteDevice4FirmwareVersion;
    late int remoteDevice4HardwareVersion;
    remoteDevice0FirmwareVersion = 0;
    remoteDevice0HardwareVersion = 0;
    remoteDevice1FirmwareVersion = 0;
    remoteDevice1HardwareVersion = 0;
    remoteDevice2FirmwareVersion = 0;
    remoteDevice2HardwareVersion = 0;
    remoteDevice3FirmwareVersion = 0;
    remoteDevice3HardwareVersion = 0;
    remoteDevice4FirmwareVersion = 0;
    remoteDevice4HardwareVersion = 0;
    readout.readyFlag = ptr[1];
    readout.remoteDevice0Type = ptr[2];
    remoteDevice0HardwareVersion = LibHeadModuleUtil.make16b(ptr, 3);
    readout.remoteDevice0HwVerMinor = ((remoteDevice0HardwareVersion & 0xF) >> 0);
    readout.remoteDevice0HwVerMajor = ((remoteDevice0HardwareVersion & 0xF0) >> 4);
    remoteDevice0FirmwareVersion = LibHeadModuleUtil.make16b(ptr, 5);
    readout.remoteDevice0FwVerMinor = ((remoteDevice0FirmwareVersion & 0xFF) >> 0);
    readout.remoteDevice0FwVerMajor = ((remoteDevice0FirmwareVersion & 0xFF00) >> 8);
    readout.remoteDevice0UniqueIdLow = LibHeadModuleUtil.make32b(ptr, 7);
    readout.remoteDevice0UniqueIdMid = LibHeadModuleUtil.make32b(ptr, 11);
    readout.remoteDevice0UniqueIdHigh = LibHeadModuleUtil.make32b(ptr, 15);
    readout.remoteDevice1Type = ptr[19];
    remoteDevice1HardwareVersion = LibHeadModuleUtil.make16b(ptr, 20);
    readout.remoteDevice1HwVerMinor = ((remoteDevice1HardwareVersion & 0xF) >> 0);
    readout.remoteDevice1HwVerMajor = ((remoteDevice1HardwareVersion & 0xF0) >> 4);
    remoteDevice1FirmwareVersion = LibHeadModuleUtil.make16b(ptr, 22);
    readout.remoteDevice1FwVerMinor = ((remoteDevice1FirmwareVersion & 0xFF) >> 0);
    readout.remoteDevice1FwVerMajor = ((remoteDevice1FirmwareVersion & 0xFF00) >> 8);
    readout.remoteDevice1UniqueIdLow = LibHeadModuleUtil.make32b(ptr, 24);
    readout.remoteDevice1UniqueIdMid = LibHeadModuleUtil.make32b(ptr, 28);
    readout.remoteDevice1UniqueIdHigh = LibHeadModuleUtil.make32b(ptr, 32);
    readout.remoteDevice2Type = ptr[36];
    remoteDevice2HardwareVersion = LibHeadModuleUtil.make16b(ptr, 37);
    readout.remoteDevice2HwVerMinor = ((remoteDevice2HardwareVersion & 0xF) >> 0);
    readout.remoteDevice2HwVerMajor = ((remoteDevice2HardwareVersion & 0xF0) >> 4);
    remoteDevice2FirmwareVersion = LibHeadModuleUtil.make16b(ptr, 39);
    readout.remoteDevice2FwVerMinor = ((remoteDevice2FirmwareVersion & 0xFF) >> 0);
    readout.remoteDevice2FwVerMajor = ((remoteDevice2FirmwareVersion & 0xFF00) >> 8);
    readout.remoteDevice2UniqueIdLow = LibHeadModuleUtil.make32b(ptr, 41);
    readout.remoteDevice2UniqueIdMid = LibHeadModuleUtil.make32b(ptr, 45);
    readout.remoteDevice2UniqueIdHigh = LibHeadModuleUtil.make32b(ptr, 49);
    readout.remoteDevice3Type = ptr[53];
    remoteDevice3HardwareVersion = LibHeadModuleUtil.make16b(ptr, 54);
    readout.remoteDevice3HwVerMinor = ((remoteDevice3HardwareVersion & 0xF) >> 0);
    readout.remoteDevice3HwVerMajor = ((remoteDevice3HardwareVersion & 0xF0) >> 4);
    remoteDevice3FirmwareVersion = LibHeadModuleUtil.make16b(ptr, 56);
    readout.remoteDevice3FwVerMinor = ((remoteDevice3FirmwareVersion & 0xFF) >> 0);
    readout.remoteDevice3FwVerMajor = ((remoteDevice3FirmwareVersion & 0xFF00) >> 8);
    readout.remoteDevice3UniqueIdLow = LibHeadModuleUtil.make32b(ptr, 58);
    readout.remoteDevice3UniqueIdMid = LibHeadModuleUtil.make32b(ptr, 62);
    readout.remoteDevice3UniqueIdHigh = LibHeadModuleUtil.make32b(ptr, 66);
    readout.remoteDevice4Type = ptr[70];
    remoteDevice4HardwareVersion = LibHeadModuleUtil.make16b(ptr, 71);
    readout.remoteDevice4HwVerMinor = ((remoteDevice4HardwareVersion & 0xF) >> 0);
    readout.remoteDevice4HwVerMajor = ((remoteDevice4HardwareVersion & 0xF0) >> 4);
    remoteDevice4FirmwareVersion = LibHeadModuleUtil.make16b(ptr, 73);
    readout.remoteDevice4FwVerMinor = ((remoteDevice4FirmwareVersion & 0xFF) >> 0);
    readout.remoteDevice4FwVerMajor = ((remoteDevice4FirmwareVersion & 0xFF00) >> 8);
    readout.remoteDevice4UniqueIdLow = LibHeadModuleUtil.make32b(ptr, 75);
    readout.remoteDevice4UniqueIdMid = LibHeadModuleUtil.make32b(ptr, 79);
    readout.remoteDevice4UniqueIdHigh = LibHeadModuleUtil.make32b(ptr, 83);
    return 0;
  }

  int addPanModuleToJibOne(List<int> ptr, List<int> len, List<int> panModuleMacAddress, int groupId) {
    ptr[0] = 10;
    ptr[1] = 132;
    for (var i = 0; i < 6; i++) {
      ptr[(2 + i)] = panModuleMacAddress[i];
    }
    LibHeadModuleUtil.put16b(ptr, 8, groupId);
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int manualJibPanTilt(List<int> ptr, List<int> len, double jibPanSpeedRelative, double jibTiltSpeedRelative) {
    if (((mJiboneSetupAngleDegEstimation >= 0.0) && ((mRemoteDeviceType == LibHeadModuleMk2RemoteDeviceType.JIB_ONE) || (mRemoteDeviceType == LibHeadModuleMk2RemoteDeviceType.JIB_ONE_MK2)))) {
      jibTiltSpeedRelative = (jibTiltSpeedRelative * -1.0);
    }
    ptr[0] = 6;
    ptr[1] = 131;
    LibHeadModuleUtil.put16b(ptr, 2, ((jibPanSpeedRelative * 32000.0)).toInt());
    LibHeadModuleUtil.put16b(ptr, 4, ((jibTiltSpeedRelative * 32000.0)).toInt());
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int simpleFocusCalibrationDo(List<int> ptr, List<int> len, LibHeadModuleMk2SimpleLensCalibrationCmd arg) {
    ptr[0] = 3;
    ptr[1] = 113;
    ptr[2] = arg.index;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int simpleFocusCalibrationAbort(List<int> ptr, List<int> len) {
    ptr[0] = 2;
    ptr[1] = 137;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int numericControlJibPlusPanMove(List<int> ptr, List<int> len, double jibPlusPanDeg) {
    ptr[0] = 7;
    ptr[1] = 85;
    ptr[2] = 4;
    LibHeadModuleUtil.put32b(ptr, 3, ((jibPlusPanDeg * 1000.0)).toInt());
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int numericControlJibPlusTiltMove(List<int> ptr, List<int> len, double jibPlusTiltDeg) {
    if (((mJiboneSetupAngleDegEstimation >= 0.0) && ((mRemoteDeviceType == LibHeadModuleMk2RemoteDeviceType.JIB_ONE) || (mRemoteDeviceType == LibHeadModuleMk2RemoteDeviceType.JIB_ONE_MK2)))) {
      jibPlusTiltDeg = (jibPlusTiltDeg * -1.0);
    }
    ptr[0] = 7;
    ptr[1] = 85;
    ptr[2] = 5;
    LibHeadModuleUtil.put32b(ptr, 3, ((jibPlusTiltDeg * 1000.0)).toInt());
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int settingsAutoPowerOffSet(List<int> ptr, List<int> len, int autoPowerOffSec) {
    ptr[0] = 5;
    ptr[1] = 134;
    LibHeadModuleUtil.put32b(ptr, 2, autoPowerOffSec);
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int visionSettingsDataParse(List<int> ptr, LibHeadModuleMk2VisionModuleSettingsData data) {
    data.stmFwVerMinor = ptr[1];
    data.stmFwVerMajor = ptr[2];
    data.rpiFwVerMinor = ptr[3];
    data.rpiFwVerMajor = ptr[4];
    data.trackingSensitivity = ((LibHeadModuleUtil.make16b(ptr, 5)).toDouble() / 1000.0);
    data.lensCalibrationData.fieldOfViewMm = LibHeadModuleUtil.make16b(ptr, 7);
    data.lensCalibrationData.cropFactor = ((LibHeadModuleUtil.make16b(ptr, 9)).toDouble() / 1000.0);
    data.deadzone = ((LibHeadModuleUtil.make16b(ptr, 11)).toDouble() / 1000.0);
    data.easyTrackingMode = LibHeadModuleMk2VisionModuleEasyTrackingMode.fromValue(ptr[13]);
    data.lensCalibrationData.fieldOfViewMinMm = LibHeadModuleUtil.make16b(ptr, 14);
    data.lensCalibrationData.fieldOfViewMaxMm = LibHeadModuleUtil.make16b(ptr, 16);
    return 0;
  }

  int focusFunctionCalibration(List<int> ptr, List<int> len, int isWorkedAsZoom) {
    ptr[0] = 4;
    ptr[1] = 212;
    ptr[2] = 0;
    ptr[3] = isWorkedAsZoom;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int focusModuleStartBrushlessCalibration(List<int> ptr, List<int> len) {
    ptr[0] = 2;
    ptr[1] = 204;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int phoneModeSettingsDataParse(List<int> ptr, LibHeadModuleMk2PhoneModeSettingsData data) {
    data.deadzone = ((LibHeadModuleUtil.make16b(ptr, 1)).toDouble() / 1000.0);
    data.trackingSensitivity = ((LibHeadModuleUtil.make16b(ptr, 3)).toDouble() / 1000.0);
    return 0;
  }

  int remoteDollyManualSlide(List<int> ptr, List<int> len, double slideSpeedRelative) {
    ptr[0] = 5;
    ptr[1] = 214;
    ptr[2] = 0;
    LibHeadModuleUtil.put16b(ptr, 3, ((slideSpeedRelative * 32000.0)).toInt());
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int chainModeGoLocation(List<int> ptr, List<int> len, int index) {
    ptr[0] = 3;
    ptr[1] = 215;
    ptr[2] = index;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }

  int settingsLiveModeSet(List<int> ptr, List<int> len, int liveModeEnabled) {
    ptr[0] = 4;
    ptr[1] = 216;
    ptr[2] = 1;
    ptr[3] = liveModeEnabled;
    appendChecksum(ptr, ptr[0]);
    len[0] = (ptr[0] + 2);
    return 0;
  }
}

LibHeadModuleMk2RemoteDeviceType mRemoteDeviceType = LibHeadModuleMk2RemoteDeviceType.NONE;
