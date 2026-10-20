/// The SDK's concurrency primitives, moved from threads to the event loop.
///
/// Ported from `edelkrone/_concurrency.py`. The semantics that matter are
/// kept exactly: one command in flight at a time, in arrival order, with a
/// priority path to the FRONT of the queue for stops; periodic work that
/// never overlaps itself; and a coalescing background job.
///
/// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
library;

import 'dart:async';
import 'dart:collection';

import '../log.dart';

const minTickGap = Duration(milliseconds: 5);

Duration seconds(double s) => Duration(microseconds: (s * 1e6).round());

/// One holder at a time, granted in arrival order — except that a request
/// marked `first` goes ahead of everything already waiting. That is how a
/// stop overtakes a queue of status polls.
class FifoLock {
  bool _held = false;
  final _waiters = ListQueue<Completer<void>>();

  bool get isHeld => _held;
  int get waiting => _waiters.length;

  Future<void> acquire({bool first = false}) {
    if (!_held && _waiters.isEmpty) {
      _held = true;
      return Future.value();
    }
    final c = Completer<void>();
    if (first) {
      _waiters.addFirst(c);
    } else {
      _waiters.addLast(c);
    }
    return c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      // Ownership passes straight to the next waiter; the lock never reads
      // as free in between, so nothing can slip in ahead of the queue.
      _waiters.removeFirst().complete();
    } else {
      _held = false;
    }
  }
}

/// Calls [tick] every [interval], never overlapping: waits the interval
/// first, then runs, then waits whatever is left of the next interval (at
/// least [minTickGap]). Stops on the first exception, after logging it.
class PeriodicWorker {
  PeriodicWorker(this.name, this.interval, this.tick);

  final String name;
  final Duration interval;
  final Future<void> Function() tick;

  bool _stopped = false;
  Completer<void>? _wake;
  Future<void>? _loop;

  bool get isRunning => _loop != null && !_stopped;

  void start() {
    if (_loop != null) return;
    _loop = _run();
  }

  Future<void> stop() async {
    _stopped = true;
    final w = _wake;
    if (w != null && !w.isCompleted) w.complete();
    await _loop;
  }

  Future<bool> _wait(Duration d) async {
    if (_stopped) return true;
    final w = _wake = Completer<void>();
    final t = Timer(d, () {
      if (!w.isCompleted) w.complete();
    });
    await w.future;
    t.cancel();
    return _stopped;
  }

  Future<void> _run() async {
    try {
      if (await _wait(interval)) return;
      while (true) {
        final started = DateTime.now();
        await tick();
        final elapsed = DateTime.now().difference(started);
        final left = interval - elapsed;
        if (await _wait(left > minTickGap ? left : minTickGap)) return;
      }
    } catch (e) {
      EdelkroneLog.warning(() => '$name: stopped after an error: $e');
    }
  }
}

/// Runs [job] whenever nudged; nudges that arrive while it runs coalesce into
/// one more run, never a backlog.
class NudgedWorker {
  NudgedWorker(this.name, this.job);

  final String name;
  final Future<void> Function() job;

  bool _running = false;
  bool _wanted = false;
  bool _stopping = false;

  void nudge() {
    if (_stopping) return;
    _wanted = true;
    if (!_running) unawaited(_drain());
  }

  void stop() => _stopping = true;

  Future<void> _drain() async {
    _running = true;
    try {
      while (_wanted && !_stopping) {
        _wanted = false;
        await job();
      }
    } catch (e) {
      EdelkroneLog.warning(() => '$name: stopped after an error: $e');
    } finally {
      _running = false;
    }
  }
}
