/// Raw notification frames, as received.
///
/// This is a reverse-engineering tool, not a user feature. EDELKRONE_PROTOCOL.md
/// §8 still lists undecoded fields — head position above all — and the way to
/// close those is to watch the actual bytes while doing something to the device.
///
/// Nothing here interprets anything beyond what §2 and §5 already establish.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ble/ek_connection.dart';
import '../ble/ek_snapshot.dart';
import '../ek_protocol.dart';

class FrameInspector extends StatefulWidget {
  const FrameInspector({super.key, required this.connection});

  final EkConnection connection;

  @override
  State<FrameInspector> createState() => _FrameInspectorState();
}

class _FrameInspectorState extends State<FrameInspector> {
  bool _onlyUnrecognised = false;

  /// Frame shapes the spec already accounts for: the 27-byte slider telemetry
  /// and the 122-byte head telemetry (§5). Anything else is more interesting.
  bool _isRoutine(EkFrameRecord f) {
    if (f.outgoing) {
      // The 250 ms keepalive is the bulk of the traffic and never interesting.
      // Everything else the app writes — velocity, save, recall, stop — is.
      return f.bytes.length == 4 &&
          (f.bytes[1] == 0x0F || f.bytes[1] == 0x01);
    }
    if (widget.connection.kind == EkKind.slider) {
      return f.bytes.length == 27 && f.messageType == 0x02;
    }
    return f.bytes.length == 122 && f.messageType == 0x02;
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.connection.frameLog.reversed.toList();
    final shown = _onlyUnrecognised ? all.where((f) => !_isRoutine(f)).toList() : all;

    // A histogram of what has actually arrived, which is usually the first
    // useful thing when a device sends something unexpected.
    final byShape = <String, int>{};
    for (final f in all) {
      final key = '${f.outgoing ? 'TX' : 'RX'} '
          '0x${f.messageType.toRadixString(16).padLeft(2, '0')} · '
          '${f.bytes.length} bytes';
      byShape[key] = (byShape[key] ?? 0) + 1;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Raw frames'),
        actions: [
          IconButton(
            tooltip: 'Copy all as text',
            icon: const Icon(Icons.copy_all),
            onPressed: shown.isEmpty
                ? null
                : () {
                    final text = shown.reversed
                        .map((f) => f.toLogLine())
                        .join('\n');
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${shown.length} frames copied')),
                    );
                  },
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(widget.connection.clearFrameLog),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Newest first. Keeps the last '
                  '${EkConnection.frameLogLimit} frames.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final e in byShape.entries)
                      Chip(
                        label: Text('${e.key}  ×${e.value}'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _onlyUnrecognised,
                  onChanged: (v) => setState(() => _onlyUnrecognised = v),
                  title: const Text('Only the interesting frames'),
                  subtitle: Text(
                    'Hides the routine telemetry and the 250 ms keepalive, '
                    'leaving the commands the app writes — velocity, save, '
                    'recall, stop — and anything received that the spec does '
                    'not describe.'
                    '${widget.connection.kind == EkKind.head ? ' A 16-byte frame with byte 1 = 0x05 is the one §5 suspects carries head progress.' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: Text('No frames.'))
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (_, i) {
                      final f = shown[i];
                      return _FrameTile(
                        frame: f,
                        routine: _isRoutine(f),
                        kind: widget.connection.kind,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FrameTile extends StatelessWidget {
  const _FrameTile({
    required this.frame,
    required this.routine,
    required this.kind,
  });

  final EkFrameRecord frame;
  final bool routine;
  final EkKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      onTap: () {
        Clipboard.setData(ClipboardData(text: frame.hex));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Frame copied')),
        );
      },
      title: Row(
        children: [
          Container(
            width: 26,
            padding: const EdgeInsets.symmetric(vertical: 1),
            margin: const EdgeInsets.only(right: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: frame.outgoing
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(frame.outgoing ? 'TX' : 'RX',
                style: const TextStyle(fontSize: 9)),
          ),
          Expanded(
            child: Text(
              frame.hex,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Text(frame.timestamp, style: theme.textTheme.bodySmall),
          const SizedBox(width: 12),
          Text('${frame.bytes.length} bytes',
              style: theme.textTheme.bodySmall),
          if (!routine) ...[
            const SizedBox(width: 12),
            Text('unrecognised shape',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.tertiary)),
          ],
          if (!frame.checksumOk) ...[
            const SizedBox(width: 12),
            Text('checksum mismatch',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
