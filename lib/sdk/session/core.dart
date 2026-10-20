/// Commands, reply frames, errors, device families and timing configuration.
///
/// Ported from `edelkrone/session/{command,errors,family,config}.py` and
/// `transport/base.py`. Only the head and slider families have protocol
/// libraries in this port — the HeadONE and SliderPLUS this app drives — so
/// every other family is recognised but reported as unsupported, the same
/// way the SDK reports a family it cannot drive.
///
/// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
library;

import '../devices/model_type.dart';
import '../log.dart';
import '../protocol/generated/head_module.dart';
import '../protocol/generated/moco.dart';
import '../protocol/generated/slide_module.dart';

/// The two GATT write/notify pairs every unit exposes.
enum Channel { data, ioCtrl }

enum SessionFailure {
  notConnected,
  disposed,
  timeout,
  unsupported,
  malformedPacket,
  unexpectedResponse,
  pairingFailed,
  invalidArgument,
}

class SessionError implements Exception {
  SessionError(this.failure, this.message, {this.command, this.cause});

  final SessionFailure failure;
  final String message;
  final String? command;
  final Object? cause;

  @override
  String toString() {
    final where = command == null ? '' : ' [$command]';
    final tail = cause == null ? '' : ' -- $cause';
    return 'SessionError(${failure.name})$where: $message$tail';
  }
}

/// Builds a packet into a zeroed buffer: `ptr` is the buffer, `len[0]` the
/// length the builder reports.
typedef PacketBuilder = void Function(List<int> ptr, List<int> len);

/// One command: how to build it, which channel it goes out on, and which
/// reply type — if any — means it was answered.
class EdelkroneCommand {
  const EdelkroneCommand({
    required this.name,
    required this.channel,
    required this.build,
    this.expects,
    this.bufferSize = 64,
  });

  final String name;
  final Channel channel;
  final PacketBuilder build;

  /// The reply type byte that completes this command, or null for a command
  /// the device does not answer.
  final int? expects;

  final int bufferSize;

  EdelkroneCommand withExpects(int? type) => EdelkroneCommand(
        name: name,
        channel: channel,
        build: build,
        expects: type,
        bufferSize: bufferSize,
      );

  /// The bytes on the wire: `ptr[0]` is the frame length excluding the
  /// two-byte checksum the builder appended after it (§2 of your spec, and
  /// `EdelkroneCommand.encode` in the SDK).
  List<int> encode() {
    final ptr = List<int>.filled(bufferSize, 0);
    final len = [0];
    build(ptr, len);
    final declared = ptr[0];
    final total = declared + 2;
    if (declared <= 0 || total > ptr.length) {
      throw SessionError(
        SessionFailure.malformedPacket,
        'the builder reported ptr[0]=$declared; that needs $total bytes, '
        'the buffer is ${ptr.length} bytes',
        command: name,
      );
    }
    final packet = [for (var i = 0; i < total; i++) ptr[i] & 0xFF];
    if (EdelkroneMoco.checksumControl(packet, packet.length) != 0) {
      EdelkroneLog.warning(() => '$name builds a packet whose checksum does not '
          'verify; sending it anyway (a known pinned-library defect)');
    }
    return packet;
  }

  @override
  String toString() => 'EdelkroneCommand($name)';
}

/// A notification as received. In this direction byte 0 is the reply type,
/// not a length.
class ResponseFrame {
  const ResponseFrame(this.channel, this.data);

  final Channel channel;
  final List<int> data;

  int? get type => data.isEmpty ? null : data[0];

  bool get checksumOk =>
      data.isNotEmpty && EdelkroneMoco.checksumControl(List<int>.of(data), data.length) == 0;

  @override
  String toString() =>
      '${channel.name} type=${type ?? '-'} ${data.length}B ${checksumOk ? 'ok' : 'BAD CHECKSUM'}';
}

enum DeviceFamily { headModule, slideModule, dolly, jib, focusPlus, tripod }

const _familyByLibrary = {
  'LibHeadModule': DeviceFamily.headModule,
  'LibSlideModule': DeviceFamily.slideModule,
  'LibDolly': DeviceFamily.dolly,
  'LibJib': DeviceFamily.jib,
  'LibFocusPlus': DeviceFamily.focusPlus,
  'LibTripod': DeviceFamily.tripod,
};

const _proTypes = {EdlDevice.HEAD_PLUS_PRO, EdlDevice.HEAD_PLUS_PRO_V2, EdlDevice.HEAD_PLUS_PRO_V3};

/// The protocol library for one model.
class DeviceLibraries {
  DeviceLibraries._(this.model, this.family);

  factory DeviceLibraries.of(EdelkroneDeviceModel model) {
    final family = familyOf(model);
    if (family == null) {
      throw SessionError(
        SessionFailure.unsupported,
        'there is no protocol library for ${model.displayName} '
        '(device_library: ${model.deviceLibrary})',
      );
    }
    return DeviceLibraries._(model, family);
  }

  static DeviceFamily? familyOf(EdelkroneDeviceModel model) => _familyByLibrary[model.deviceLibrary];

  /// Whether this port can drive the family at all.
  static bool isDrivable(EdelkroneDeviceModel model) {
    final f = familyOf(model);
    return f == DeviceFamily.headModule || f == DeviceFamily.slideModule;
  }

  final EdelkroneDeviceModel model;
  final DeviceFamily family;

  static final _head = LibHeadModule();
  static final _slide = LibSlideModule();

  LibHeadModule get headModule {
    if (family != DeviceFamily.headModule) throw _wrong('LibHeadModule');
    return _head;
  }

  LibSlideModule get slideModule {
    if (family != DeviceFamily.slideModule) throw _wrong('LibSlideModule');
    return _slide;
  }

  /// Heads and sliders take the universal moco commands on the data channel;
  /// everything else on io-control.
  bool get mocoUniversalOnDataChannel =>
      family == DeviceFamily.headModule || family == DeviceFamily.slideModule;

  bool get isPro => _proTypes.contains(model.deviceType);

  SessionError _wrong(String wanted) => SessionError(
        SessionFailure.unsupported,
        '${model.displayName} is a ${family.name} device; this command wants $wanted',
      );
}

/// Timeouts and polling intervals, in seconds, with the SDK's defaults.
class SessionConfig {
  const SessionConfig({
    this.statusInterval = 0.250,
    this.commandTimeout = 0.800,
    this.coldCommandTimeout = 2.000,
    this.coldAfter = 2.0,
    this.driveReplyTimeout = 0.400,
    this.driveReplyMisses = 3,
    this.drivePositionInterval = 0.150,
    this.manualHold = 1.6,
    this.pairPollInterval = 0.300,
    this.pairTimeout = 30.0,
    this.pairPollTimeout = 1.500,
    this.unrecognisedPollLimit = 3,
    this.connectAttempts = 3,
    this.connectBackoff = 3.0,
    this.adaptiveTimeout = true,
    this.adaptiveFactor = 4.0,
    this.adaptiveMinSamples = 8,
    this.adaptiveWindow = 32,
    this.adaptiveCeiling = 5.0,
  });

  final double statusInterval;
  final double commandTimeout;
  final double coldCommandTimeout;
  final double coldAfter;
  final double driveReplyTimeout;
  final int driveReplyMisses;
  final double drivePositionInterval;

  /// How long joystick control counts as active after the last drive. The
  /// device itself carries on at the last speed for 1.5 s and then stops.
  final double manualHold;

  final double pairPollInterval;
  final double pairTimeout;
  final double pairPollTimeout;
  final int unrecognisedPollLimit;
  final int connectAttempts;
  final double connectBackoff;
  final bool adaptiveTimeout;
  final double adaptiveFactor;
  final int adaptiveMinSamples;
  final int adaptiveWindow;
  final double adaptiveCeiling;
}

/// Widens the reply timeout on a slow link, from the p95 of recent round
/// trips, so a poor radio does not read as an unresponsive device.
class RoundTripMonitor {
  RoundTripMonitor(this._config);

  final SessionConfig _config;
  final List<double> _samples = [];

  void record(double seconds) {
    if (seconds < 0) return;
    _samples.add(seconds);
    final window = _config.adaptiveWindow < 1 ? 1 : _config.adaptiveWindow;
    while (_samples.length > window) {
      _samples.removeAt(0);
    }
  }

  double? get p95 {
    if (_samples.isEmpty) return null;
    final ordered = [..._samples]..sort();
    final i = (ordered.length * 0.95).toInt();
    return ordered[i < ordered.length - 1 ? i : ordered.length - 1];
  }

  double budget({required bool cold}) {
    final base = cold ? _config.coldCommandTimeout : _config.commandTimeout;
    if (!_config.adaptiveTimeout || _samples.length < _config.adaptiveMinSamples) return base;
    final measured = p95;
    if (measured == null) return base;
    final scaled = measured * _config.adaptiveFactor;
    final capped = scaled < _config.adaptiveCeiling ? scaled : _config.adaptiveCeiling;
    return capped > base ? capped : base;
  }
}
