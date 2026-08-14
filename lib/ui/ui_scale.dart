/// Shared spacing and type, so the sections of the control page line up.
///
/// The panels previously each invented their own padding and text styles, which
/// made a two-column layout look ragged.
library;

import 'package:flutter/material.dart';

class Gap {
  static const xs = SizedBox(height: 4);
  static const sm = SizedBox(height: 8);
  static const md = SizedBox(height: 16);
  static const lg = SizedBox(height: 24);

  static const wSm = SizedBox(width: 8);
  static const wMd = SizedBox(width: 16);
}

class Insets {
  static const card = EdgeInsets.all(12);
  static const page = EdgeInsets.all(16);
}

/// A titled block. Every section on the control page uses this, so headings,
/// spacing and the optional explanatory note are consistent.
class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.title,
    this.note,
    this.trailing,
    required this.children,
  });

  final String title;

  /// Small print under the heading — used for the protocol §-references and the
  /// honest warnings. Load-bearing, not decoration.
  final String? note;

  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
            ?trailing,
          ],
        ),
        if (note != null) ...[
          Gap.xs,
          Text(note!, style: theme.textTheme.bodySmall),
        ],
        Gap.sm,
        ...children,
      ],
    );
  }
}

/// A labelled slider with its value in the label, disabled rather than hidden
/// when it cannot be changed.
class LabelledSlider extends StatelessWidget {
  const LabelledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label — $display',
            style: Theme.of(context).textTheme.bodySmall),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// An inline warning that must stay visible — protocol limitations, not errors.
class Caution extends StatelessWidget {
  const Caution(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: theme.colorScheme.tertiary),
          Gap.wSm,
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.tertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A failure the user needs to see. Errors used to reach only the console.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key, this.onDismiss});

  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: Insets.card,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline,
                size: 18, color: theme.colorScheme.onErrorContainer),
            Gap.wSm,
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                iconSize: 18,
                onPressed: onDismiss,
                icon: Icon(Icons.close,
                    color: theme.colorScheme.onErrorContainer),
              ),
          ],
        ),
      ),
    );
  }
}
