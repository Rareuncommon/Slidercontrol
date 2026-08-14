/// A keyboard emergency stop, active anywhere in the app.
///
/// On a desktop the mouse may be nowhere near the STOP button when something
/// starts going wrong, and on the panel screen the button can be scrolled out
/// of view. Escape stops everything from any screen, whatever has focus.
///
/// Registered on the raw keyboard rather than through a Shortcuts/Actions tree
/// deliberately: a focused text field or an open menu would swallow a
/// widget-tree shortcut, and those are exactly the moments a stop must still
/// work.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../control/stop_registry.dart';

class EmergencyStopKeys extends StatefulWidget {
  const EmergencyStopKeys({
    super.key,
    required this.child,
    required this.registry,
    this.onStopped,
  });

  final Widget child;
  final StopRegistry registry;

  /// Called after a stop is triggered, so the UI can acknowledge it.
  final void Function(List<String> failures)? onStopped;

  @override
  State<EmergencyStopKeys> createState() => _EmergencyStopKeysState();
}

class _EmergencyStopKeysState extends State<EmergencyStopKeys> {
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (!widget.registry.hasRegistrations) return false;

    // Re-entrancy guard only — never a reason to swallow the key. If a stop is
    // already running, the motor is already being told to stop.
    if (!_stopping) {
      _stopping = true;
      widget.registry.stopAll().then((failures) {
        _stopping = false;
        if (mounted) widget.onStopped?.call(failures);
      }).catchError((Object e) {
        _stopping = false;
        if (mounted) widget.onStopped?.call(['$e']);
      });
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
