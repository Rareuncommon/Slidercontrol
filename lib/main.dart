/// Slidercontrol — a HeadONE and SliderPLUS controller, built on a Dart port
/// of edelkrone's own Python SDK (lib/sdk).
///
/// This page finds the rig. Joining the slider to the head is offered here,
/// because joined, the head plans every stored-pose move for both axes.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'app/flutter_support.dart';
import 'app/permissions.dart';
import 'app/rig_controller.dart';
import 'control/stop_registry.dart';
import 'sdk/api/connect.dart' show Seen;
import 'sdk/devices/registry.dart';
import 'sdk/protocol/generated/moco.dart';
import 'sdk/transport/flutter_blue_transport.dart';
import 'ui/emergency_stop.dart';
import 'ui/rig_page.dart';
import 'ui/ui_scale.dart';

void main() {
  LogBuffer.instance.install();
  runApp(const SlidercontrolApp());
}

class SlidercontrolApp extends StatefulWidget {
  const SlidercontrolApp({super.key});

  @override
  State<SlidercontrolApp> createState() => _SlidercontrolAppState();
}

class _SlidercontrolAppState extends State<SlidercontrolApp> with WidgetsBindingObserver {
  late final RigController controller = RigController(transport: FlutterBlueTransport(), names: PrefsPoseNameStore());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(controller.dispose());
    super.dispose();
  }

  /// Backgrounding stops everything. The SDK does not stop moving equipment on
  /// its own, and a held joystick would otherwise run on for 1.5 s.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      unawaited(StopRegistry.instance.stopAll());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Slidercontrol',
      theme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
      builder: (context, child) =>
          EmergencyStopKeys(registry: StopRegistry.instance, child: child ?? const SizedBox.shrink()),
      home: ScanPage(controller: controller),
    );
  }
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.controller});
  final RigController controller;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  RigController get c => widget.controller;
  late final StreamSubscription<void> _sub;
  String? _permissionProblem;

  @override
  void initState() {
    super.initState();
    _sub = c.changes.listen((_) {
      if (!mounted) return;
      setState(() {});
      if (c.phase == RigPhase.connected && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RigPage(controller: c))).then((_) {
          if (mounted) unawaited(_scan());
        });
      }
    });
    unawaited(_scan());
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }

  Future<void> _scan() async {
    final problem = await EkPermissions.request();
    if (!mounted) return;
    setState(() => _permissionProblem = problem);
    if (problem != null) return;
    await c.startScan();
  }

  Future<void> _choose(Seen s) async {
    if (!s.drivable) {
      _snack('${s.name} is not something this app drives — it controls heads and sliders.');
      return;
    }
    if (!s.recognised) {
      _snack('The SDK does not recognise this combination of units.');
      return;
    }
    final offer = c.joinable(s);
    var join = <EdelkroneDevice>[...offer];
    final go = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: Insets.page,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name, style: Theme.of(context).textTheme.titleLarge),
                Text('${s.mac} · ${_layoutLabel(s.layout)}${s.modules.isEmpty ? '' : ' with ${s.modules.join(', ')}'}'),
                Gap.md,
                if (offer.isNotEmpty) ...[
                  for (final u in offer)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: join.contains(u),
                      onChanged: (v) => setSheet(() => v == true ? join.add(u) : join.remove(u)),
                      title: Text('Join the ${u.displayName} to it'),
                      subtitle: Text(
                        '${u.mac}. Joined, the head plans every stored-pose move for both axes, so they '
                        'start and arrive together. The layout lasts until a unit is switched off.',
                      ),
                    ),
                  const Caution(
                    'Joining can only be undone by switching the units off and on. A module already in '
                    'another layout will not join a new one.',
                  ),
                ] else if (s.modules.isNotEmpty)
                  Text('Already joined with ${s.modules.join(', ')}.'),
                Gap.md,
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    Gap.wSm,
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Connect')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (go == true) await c.connect(s, join: join);
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scanning = c.phase == RigPhase.scanning;
    final connecting = c.phase == RigPhase.connecting;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Slidercontrol'),
        actions: [
          IconButton(
            tooltip: scanning ? 'Stop scanning' : 'Scan',
            icon: Icon(scanning ? Icons.stop_circle_outlined : Icons.refresh),
            onPressed: connecting ? null : () => scanning ? c.stopScan() : _scan(),
          ),
        ],
      ),
      body: ListView(
        padding: Insets.page,
        children: [
          if (_permissionProblem != null)
            ErrorBanner(_permissionProblem!, onDismiss: () => setState(() => _permissionProblem = null)),
          if (c.error != null) ErrorBanner(c.error!, onDismiss: c.clearError),
          if (connecting)
            const ListTile(
              leading: CircularProgressIndicator(),
              title: Text('Connecting…'),
              subtitle: Text('Reading the identity, joining modules if asked, and waiting for them to answer.'),
            ),
          if (c.seen.isEmpty && !connecting)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  if (scanning) const CircularProgressIndicator(),
                  Gap.md,
                  Text(
                    scanning ? 'Looking for edelkrone units…' : 'Nothing found yet.',
                    style: theme.textTheme.titleMedium,
                  ),
                  Gap.sm,
                  const Text(
                    'Switch the head and slider on. A unit connected to the edelkrone app on a phone will not '
                    'accept a second connection — close that first.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          for (final s in c.seen)
            Card(
              child: ListTile(
                enabled: !connecting,
                leading: Icon(s.modules.isNotEmpty || c.joinable(s).isNotEmpty ? Icons.videocam : Icons.linear_scale),
                title: Text(s.name),
                subtitle: Text(
                  [
                    s.mac,
                    _layoutLabel(s.layout),
                    if (s.modules.isNotEmpty) 'with ${s.modules.join(', ')}',
                    if (!s.drivable) 'not driven by this app',
                    if (s.layout == EdlSetup.GROUP_MEMBER) 'module of a layout — connect to its head',
                  ].join(' · '),
                ),
                trailing: Text('${s.signal} dBm', style: theme.textTheme.bodySmall),
                onTap: connecting ? null : () => _choose(s),
              ),
            ),
          Gap.lg,
          const Caution(
            'Take the camera off the rig the first time you try anything that moves. The app stops '
            'everything when it goes to the background, on Escape, and on STOP ALL.',
          ),
        ],
      ),
    );
  }
}

String _layoutLabel(EdlSetup? s) => switch (s) {
  null || EdlSetup.NONE => 'on its own',
  EdlSetup.PAN_AND_SLIDE => 'pan and slide',
  EdlSetup.TILT_AND_SLIDE => 'tilt and slide',
  EdlSetup.SLIDE_ONLY => 'slider on its own',
  EdlSetup.GROUP_MEMBER => 'in a layout',
  _ => s.name.toLowerCase().replaceAll('_', ' '),
};
