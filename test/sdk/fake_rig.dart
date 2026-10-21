/// A simulated HeadONE (V2) leading a SliderPLUS V6, for session tests.
///
/// It answers the way the SDK's code expects the hardware to — reply frames
/// in the real formats, which the verified codec then parses — and moves
/// with deliberately simple physics. It also records every packet written,
/// so a test can assert exactly what went out and in what order.
///
/// Not a model of the motors. A model of the protocol.
library;

import 'dart:async';

import '../../lib/sdk/devices/models.dart' as models;
import '../../lib/sdk/devices/registry.dart';
import '../../lib/sdk/protocol/generated/moco.dart';
import '../../lib/sdk/session/core.dart';
import '../../lib/sdk/transport/transport.dart';

List<int> withChecksum(List<int> v) {
  var sum = 0;
  for (final b in v) {
    sum += b & 0xFF;
  }
  return [...v, (sum >> 8) & 0xFF, sum & 0xFF];
}

List<int> int32(double value, double scale) {
  final x = (value * scale).round().toSigned(32);
  return [(x >> 24) & 0xFF, (x >> 16) & 0xFF, (x >> 8) & 0xFF, x & 0xFF];
}

int s16(List<int> p, int at) => ((p[at] << 8) | p[at + 1]).toSigned(16);

LibEdelkroneMocoAdvData advFor(int last, {EdlSetup setup = EdlSetup.NONE, int group = 0xFFFF, bool tilted = false}) =>
    LibEdelkroneMocoAdvData(
      mac: [0xC8, 0xF0, 0x9E, 0x10, 0x20, last],
      groupId: group,
      setup: setup,
      wifiChannel: 0,
      wifiState: EspWifiState.NONE,
      isTilted: tilted,
      oldSlideModuleConnected: false,
      esp32FirmwareVersionMinor: 34,
      esp32FirmwareVersionMajor: 0,
      deviceFirmwareVersionMinor: 1,
      deviceFirmwareVersionMajor: 1,
      canbusPairingActive: false,
    );

EdelkroneDevice fakeHeadUnit({EdlSetup setup = EdlSetup.NONE, int group = 0xFFFF}) => EdelkroneDevice(
  id: 'head',
  model: models.headOneFm,
  advData: advFor(1, setup: setup, group: group),
  rssi: -40,
);

EdelkroneDevice fakeSliderUnit() =>
    EdelkroneDevice(id: 'slider', model: models.sliderPlusV1, advData: advFor(2), rssi: -45);

class Sent {
  Sent(this.channel, this.bytes);
  final Channel channel;
  final List<int> bytes;
  int get op => bytes[1];
  @override
  String toString() => '${channel.name}:op$op';
}

class FakeHeadLink implements DeviceLink {
  FakeHeadLink({
    EdelkroneDevice? unit,
    EdlSetup configuration = EdlSetup.NONE,
    this.focusMotor = false,
    this.focusSetUp = false,
    this.latency = const Duration(milliseconds: 3),
  }) : device = unit ?? fakeHeadUnit(),
       _configuration = configuration,
       _remoteOk = configuration == EdlSetup.PAN_AND_SLIDE {
    _physics = Timer.periodic(const Duration(milliseconds: 10), (_) => _step());
  }

  @override
  final EdelkroneDevice device;
  final bool focusMotor;

  /// The head knows its focus motor and lens: referenced, ends found.
  final bool focusSetUp;
  final Duration latency;

  final sent = <Sent>[];

  /// Replies stop entirely; writes still succeed. A radio that has gone deaf.
  bool silent = false;

  final _changes = StreamController<bool>.broadcast();
  final _rx = {for (final c in Channel.values) c: StreamController<List<int>>.broadcast()};
  bool _up = true;
  late final Timer _physics;
  final _clock = Stopwatch()..start();

  EdlSetup _configuration;
  bool _remoteOk;
  int _group = 0xFFFF;
  double pan = 0;
  double slide = 10;
  final stored = <int, (double, double)>{};
  int _aim = 0;

  // Joystick.
  double _panSpeed = 0;
  double _slideSpeed = 0;
  int _lastDriveMs = -100000;

  // Planned move.
  bool _moving = false;
  (double, double)? _from;
  (double, double)? _to;
  int _moveStartedMs = 0;
  (int, int)? _loop;
  static const moveMs = 300;

  bool get moving => _moving || _panSpeed != 0 || _slideSpeed != 0;
  EdlSetup get configuration => _configuration;

  List<Sent> ops(int op, {Channel channel = Channel.data}) =>
      sent.where((s) => s.op == op && s.channel == channel).toList();

  void _step() {
    final now = _clock.elapsedMilliseconds;
    if (_panSpeed != 0 || _slideSpeed != 0) {
      // The device carries on at the last speed for 1.5 s, then stops.
      if (now - _lastDriveMs > 1500) {
        _panSpeed = 0;
        _slideSpeed = 0;
      } else {
        pan += _panSpeed * 90 * 0.01;
        slide = (slide + _slideSpeed * 20 * 0.01).clamp(0, 120).toDouble();
      }
    }
    if (_moving) {
      final t = ((now - _moveStartedMs) / moveMs).clamp(0.0, 1.0);
      pan = _from!.$1 + (_to!.$1 - _from!.$1) * t;
      slide = _from!.$2 + (_to!.$2 - _from!.$2) * t;
      if (t >= 1) {
        final loop = _loop;
        if (loop != null) {
          // The device's own ping-pong: on arrival, head for the other end.
          _beginMove(_aim == loop.$1 ? loop.$2 : loop.$1);
          legsCompleted++;
        } else {
          _moving = false;
        }
      }
    }
  }

  /// Legs the device's own loop has completed.
  int legsCompleted = 0;

  void _beginMove(int aim) {
    _aim = aim;
    _from = (pan, slide);
    _to = stored[aim];
    _moveStartedMs = _clock.elapsedMilliseconds;
    _moving = true;
  }

  @override
  bool get isConnected => _up;

  @override
  Stream<bool> get connectionChanges => _changes.stream;

  @override
  Stream<List<int>> notifications(Channel channel) => _rx[channel]!.stream;

  void drop() {
    if (!_up) return;
    _up = false;
    _changes.add(false);
  }

  void _reply(Channel ch, List<int> payload) {
    if (silent || !_up) return;
    Future<void>.delayed(latency, () {
      final c = _rx[ch]!;
      if (!c.isClosed && _up) c.add(withChecksum(payload));
    });
  }

  List<int> statusPayload() {
    final v = List<int>.filled(136, 0);
    v[0] = 2;
    v[1] = moving ? 5 : 0;
    for (final slot in stored.keys) {
      if (slot < 8) {
        v[2] |= 1 << slot;
      } else {
        v[106] |= 1 << (slot - 8);
      }
    }
    v[3] = 0x1 | (focusMotor ? 0x4 : 0);
    v[4] = _moving ? (((_clock.elapsedMilliseconds - _moveStartedMs) / moveMs).clamp(0, 1) * 100).round() : 0;
    v[6] = _configuration.value;
    v[17] = 12;
    if (focusSetUp) {
      v[31] = 1; // isSimpleFocusCalibrationDone
      v[95] |= 0x1; // focusModuleIsBrushlessCalibrated
    }
    v[36] = _remoteOk ? 0x2 : 0;
    v[109] = _aim;
    return v;
  }

  List<int> numericPayload(int index) {
    final (double p, double s) = index == 255 ? (pan, slide) : (stored[index] ?? (0.0, 0.0));
    return [
      18,
      index,
      ...int32(p, 1000),
      ...int32(-1, 1000),
      ...int32(-1, 1000),
      ...int32(s, 1000),
      ...int32(-1, 1000),
      ...int32(-1, 1000),
      0,
      0,
    ];
  }

  @override
  Future<void> write(Channel channel, List<int> packet) async {
    if (!_up) throw TransportError(TransportFailure.notConnected, 'fake link is down');
    sent.add(Sent(channel, List.of(packet)));
    final op = packet[1];
    if (channel == Channel.ioCtrl) {
      switch (op) {
        case 2: // ioctlStatusGet
          _reply(Channel.ioCtrl, [0, (_group >> 8) & 0xFF, _group & 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 34]);
        case 9: // groupIdSelfSet
          _group = (packet[2] << 8) | packet[3];
        case 1: // addPeer: the slider joins a moment later
          Future<void>.delayed(const Duration(milliseconds: 150), () {
            _remoteOk = true;
            if (_configuration == EdlSetup.NONE) _configuration = EdlSetup.PAN_AND_SLIDE;
          });
      }
      return;
    }
    switch (op) {
      case 1: // statusGet
        _reply(Channel.data, statusPayload());
      case 13: // headVersionGet
        _reply(Channel.data, [1, ...List<int>.filled(20, 0)]);
      case 54: // settingsGet
        _reply(Channel.data, [13, ...List<int>.filled(40, 0)]);
      case 128: // remoteVersionGet
        _reply(Channel.data, [21, ...List<int>.filled(60, 0)]);
      case 83: // numericControlRead
        _reply(Channel.data, numericPayload(packet[2]));
      case 201: // configurationSet
        _configuration = EdlSetup.fromValue(packet[2]);
      case 5: // keyposeStore
        stored[packet[2]] = (pan, slide);
      case 6: // keyposeDelete
        stored.remove(packet[2]);
      case 7: // keyposeMove
        final start = packet[2];
        final aim = packet[3];
        if (_moving || !stored.containsKey(aim)) break;
        _loop = packet[4] == 1 ? (start == 255 ? _aim : start, aim) : null;
        _beginMove(aim);
      case 9: // keyposeAbort
        _moving = false;
        _loop = null;
        _panSpeed = 0;
        _slideSpeed = 0;
      case 10: // manualPanTilt: answered with a status, as the device does
        _panSpeed = s16(packet, 2) / 32000;
        _lastDriveMs = _clock.elapsedMilliseconds;
        _reply(Channel.data, statusPayload());
      case 11: // manualSlide
        _slideSpeed = s16(packet, 2) / 32000;
        _lastDriveMs = _clock.elapsedMilliseconds;
        _reply(Channel.data, statusPayload());
    }
  }

  @override
  Future<void> requestLowLatency() async {}

  @override
  Future<void> disconnect() async {
    _physics.cancel();
    final was = _up;
    _up = false;
    if (was && !_changes.isClosed) _changes.add(false);
  }
}

class FakeTransport implements Transport {
  FakeTransport(this.link, {this.seen = const []});

  final FakeHeadLink link;
  final List<EdelkroneDevice> seen;
  final _devices = StreamController<List<EdelkroneDevice>>.broadcast();

  @override
  Stream<List<EdelkroneDevice>> get devices => _devices.stream;

  @override
  List<EdelkroneDevice> get current => seen;

  @override
  bool get isScanning => false;

  @override
  Future<void> startScan() async => _devices.add(seen);

  @override
  Future<void> stopScan() async {}

  @override
  void clearDevices() {}

  @override
  Future<DeviceLink> connect(EdelkroneDevice device) async => link;

  @override
  Future<void> dispose() async => link.disconnect();
}
