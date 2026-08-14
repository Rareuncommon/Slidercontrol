/// A single place that knows how to stop everything.
///
/// Stopping a *device* is not the same as stopping the *client*. Writing the
/// stop opcode halts the motor, but if a ping-pong loop is still running it
/// will command the next leg a moment later and the device starts moving again.
/// A stop that can be undone half a second later by the app's own state machine
/// is not a stop.
///
/// So anything capable of commanding motion registers here, and every stop
/// path — the STOP ALL button, the keyboard shortcut, app backgrounding — goes
/// through [stopAll], which tears down the controllers *and* writes the stop.
///
/// Pure Dart, so it is testable without hardware.
library;

import 'dart:async';

typedef StopAction = Future<void> Function();

class StopRegistry {
  StopRegistry();

  /// The instance the app uses. Injectable for tests.
  static final StopRegistry instance = StopRegistry();

  final _actions = <Object, StopAction>{};

  /// Anything that can start motion registers a way to stop it.
  ///
  /// Keyed by owner so a screen re-registering replaces its own entry rather
  /// than accumulating stale closures.
  void register(Object owner, StopAction stop) => _actions[owner] = stop;

  void unregister(Object owner) => _actions.remove(owner);

  bool get hasRegistrations => _actions.isNotEmpty;

  int get count => _actions.length;

  /// Runs every registered stop. Returns the failures, empty on success.
  ///
  /// Every action runs even if an earlier one throws: a stop that gives up
  /// partway is how a second device gets left running.
  Future<List<String>> stopAll() async {
    final failures = <String>[];
    // Snapshot first — an action may unregister itself while running.
    for (final entry in _actions.entries.toList()) {
      try {
        await entry.value();
      } catch (e) {
        failures.add('$e');
      }
    }
    return failures;
  }
}
