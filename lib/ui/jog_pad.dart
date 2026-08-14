/// A circular jog pad, in the shape of the official app's PAN / SLIDE controls.
///
/// Horizontal displacement from the centre sets velocity proportionally, so a
/// small nudge creeps and a full push runs at the configured speed. The knob
/// springs back to centre on release.
///
/// Every release path — pointer up, pointer cancel, widget disposal — stops the
/// motor. Jogging streams velocity, and a stream that is not stopped keeps
/// running (§7), so "the finger came off" must always mean "stop".
library;

import 'package:flutter/material.dart';

class JogPad extends StatefulWidget {
  const JogPad({
    super.key,
    required this.label,
    required this.enabled,
    required this.onVelocity,
    required this.onRelease,
    this.disabledNote,
    this.readout,
  });

  final String label;
  final bool enabled;

  /// Called with a -1..1 fraction of full commanded speed while held.
  final void Function(double fraction) onVelocity;

  final VoidCallback onRelease;

  /// Shown in place of the label when the pad cannot be used.
  final String? disabledNote;

  /// What is currently being commanded, shown under the pad. Without this,
  /// resting on the knob and seeing nothing move is indistinguishable from a
  /// broken link — the pad is absolute, so the centre commands zero.
  final String? readout;

  @override
  State<JogPad> createState() => _JogPadState();
}

class _JogPadState extends State<JogPad> {
  double _dx = 0;
  bool _held = false;
  double _radius = 100;

  /// Displacement under this fraction of the radius commands nothing, so
  /// resting a finger on the pad does not creep the carriage.
  static const _deadZone = 0.08;

  void _update(Offset local, Size size) {
    if (!widget.enabled) return;
    _radius = size.width / 2;
    final dx = (local.dx - _radius).clamp(-_radius, _radius);
    setState(() {
      _held = true;
      _dx = dx;
    });
    final fraction = (_dx / _radius).clamp(-1.0, 1.0);
    widget.onVelocity(fraction.abs() < _deadZone ? 0 : fraction);
  }

  void _release() {
    if (!_held) return;
    setState(() {
      _held = false;
      _dx = 0;
    });
    widget.onRelease();
  }

  @override
  void dispose() {
    // Torn down mid-hold must still stop.
    if (_held) widget.onRelease();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.enabled;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        final radius = size / 2;
        final knob = size * 0.28;

        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: Listener(
              onPointerDown: (e) =>
                  _update(e.localPosition, Size(size, size)),
              onPointerMove: (e) =>
                  _update(e.localPosition, Size(size, size)),
              onPointerUp: (_) => _release(),
              onPointerCancel: (_) => _release(),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ring
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: enabled
                            ? scheme.primary.withValues(alpha: 0.5)
                            : scheme.outlineVariant,
                      ),
                      color: enabled
                          ? scheme.primaryContainer.withValues(alpha: 0.35)
                          : scheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                    ),
                  ),
                  // Horizontal axis line — this pad only drives one axis.
                  Container(
                    width: size * 0.82,
                    height: 1,
                    color: enabled
                        ? scheme.primary.withValues(alpha: 0.35)
                        : scheme.outlineVariant,
                  ),
                  // Knob
                  AnimatedPositioned(
                    duration: _held
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    left: radius + _dx.clamp(-(radius - knob / 2),
                            radius - knob / 2) -
                        knob / 2,
                    child: Container(
                      width: knob,
                      height: knob,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: enabled
                            ? (_held ? scheme.primary : scheme.primaryContainer)
                            : scheme.surfaceContainerHighest,
                      ),
                      child: Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                          color: enabled
                              ? (_held
                                  ? scheme.onPrimary
                                  : scheme.onPrimaryContainer)
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: size * 0.1,
                    child: Text(
                      !enabled
                          ? (widget.disabledNote ?? '')
                          : (widget.readout ??
                              'drag left or right'),
                      style: TextStyle(
                        fontSize: 11,
                        color: _held && enabled
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
