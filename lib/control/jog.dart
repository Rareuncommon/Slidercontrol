/// Manual jogging — streamed velocity while a control is held.
///
/// Velocity has to be re-sent at ~100 ms while moving (EDELKRONE_PROTOCOL.md
/// §3, §4), so this owns a repeating timer for as long as the user holds a
/// button.
///
/// This is the one part of the client that streams rather than commanding a
/// self-completing move, and §7 is explicit that streamed velocity keeps
/// running if the host disappears. That is acceptable here only because
/// jogging is a held, attended action: the moment the finger lifts, [stop]
/// runs. Anything unattended goes through a pose recall instead.
///
/// Pure Dart — it drives an [EkMotionTarget], so it is testable without
/// hardware.
library;

import 'dart:async';

import '../ble/ek_snapshot.dart';
import '../ek_protocol.dart';

class JogController {
  JogController({required this.target});

  final EkMotionTarget target;

  Timer? _timer;
  int _velocity = 0;
  bool _sending = false;

  bool get isJogging => _timer != null;
  int get velocity => _velocity;

  /// Begins streaming [countsPerSec] until [stop].
  ///
  /// The first frame goes out immediately rather than waiting a tick, so the
  /// carriage responds to the press without a visible 100 ms delay.
  Future<void> start(int countsPerSec) async {
    _velocity = countsPerSec;
    _timer?.cancel();
    _timer = Timer.periodic(jogPeriod, (_) => _tick());
    await _send(_velocity);
  }

  /// Changes the commanded velocity mid-hold, e.g. because the speed slider
  /// moved. Does nothing if not currently jogging.
  void setVelocity(int countsPerSec) {
    if (_timer == null) return;
    _velocity = countsPerSec;
  }

  /// Stops the motion and the stream.
  ///
  /// Sends velocity zero — which is what stop means for a streamed move (§3) —
  /// and then the explicit stop opcode as a second line of defence. A redundant
  /// stop costs nothing; a missed one leaves the carriage under torque.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _velocity = 0;
    try {
      await target.setVelocity(0);
    } catch (_) {
      // Fall through to the explicit stop regardless.
    }
    try {
      await target.stopMotion();
    } catch (_) {
      // Nothing further this layer can do.
    }
  }

  void _tick() {
    if (_timer == null) return;
    unawaited(_send(_velocity));
  }

  /// Skips a tick if the previous write has not completed, so a slow link
  /// cannot build a backlog of stale velocity frames behind the release.
  Future<void> _send(int v) async {
    if (_sending) return;
    _sending = true;
    try {
      await target.setVelocity(v);
    } catch (_) {
      // A failed velocity frame is not worth tearing the hold down for; the
      // next tick will retry, and release still sends a zero.
    } finally {
      _sending = false;
    }
  }
}
