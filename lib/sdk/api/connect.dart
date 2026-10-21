/// Finding units, and connecting to one with its modules joined.
///
/// Ported from `edelkrone/api/connect.py`. `connect()` finds the unit, opens a
/// session, reads its identity and a first reading, joins its modules if
/// asked, checks the layout really formed and the modules answer, starts
/// polling, and returns a [Device]. Any step that fails disconnects and says
/// which step it was.
///
/// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
library;

import 'dart:async';

import '../devices/registry.dart';
import '../log.dart';
import '../protocol/generated/moco.dart';
import '../session/core.dart';
import '../session/session.dart';
import '../transport/transport.dart';
import 'device.dart';

const defaultScanSeconds = 8.0;
const defaultConnectTimeout = 20.0;
const _moduleSighting = 3.0;
const _modulesReady = 6.0;

/// A unit found by [discover], listed once together with its modules.
class Seen {
  const Seen({
    required this.name,
    required this.mac,
    required this.signal,
    required this.layout,
    required this.modules,
    required this.recognised,
    required this.drivable,
    required this.rig,
  });

  final String name;
  final String mac;
  final int signal;
  final EdlSetup? layout;
  final List<String> modules;

  /// Whether the SDK supports this combination of units.
  final bool recognised;

  /// Whether this app's port can drive it: heads and sliders.
  final bool drivable;

  final Rig rig;

  @override
  String toString() =>
      '$name $mac ($signal dBm) · ${layout?.name.toLowerCase() ?? 'none'}'
      '${modules.isEmpty ? '' : ' + ${modules.join(', ')}'}';
}

Seen seenOf(Rig rig) {
  final m = rig.master;
  final family = DeviceLibraries.familyOf(m.model);
  return Seen(
    name: m.displayName,
    mac: m.mac,
    signal: m.rssi,
    layout: m.advData.setup,
    modules: [for (final s in rig.orderedSlaves) s.displayName],
    recognised: rig.isRecognised && family != DeviceFamily.focusPlus && m.advData.setup != EdlSetup.FIRMWARE_ERROR,
    drivable:
        DeviceLibraries.isDrivable(m.model) &&
        rig.orderedSlaves.every((s) => DeviceLibraries.familyOf(s.model) != null),
    rig: rig,
  );
}

String _normaliseMac(String t) => t.toUpperCase().replaceAll(RegExp('[^0-9A-F]'), '');

/// Scans until [until] holds or [timeout] passes.
Future<List<Rig>> scan(Transport transport, {required bool Function(List<Rig>) until, required double timeout}) async {
  final seen = <String, EdelkroneDevice>{};
  final sub = transport.devices.listen((list) {
    for (final d in list) {
      seen[d.id] = d;
    }
  });
  try {
    await transport.startScan();
    final deadline = DateTime.now().add(Duration(milliseconds: (timeout * 1000).round()));
    while (true) {
      for (final d in transport.current) {
        seen[d.id] = d;
      }
      final rigs = groupIntoRigs(seen.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)));
      if (until(rigs) || DateTime.now().isAfter(deadline)) return rigs;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  } finally {
    try {
      await transport.stopScan();
    } catch (_) {}
    await sub.cancel();
  }
}

Future<List<Seen>> discover(Transport transport, {double seconds = defaultScanSeconds}) async {
  final rigs = await scan(transport, until: (_) => false, timeout: seconds);
  return [for (final r in rigs) seenOf(r)];
}

/// Connects to the unit [rig] leads. With [withModules] — modules by MAC — the
/// SDK joins them to it first, by radio or cable as the hardware requires.
Future<Device> connect(
  Transport transport,
  Rig rig, {
  List<EdelkroneDevice> withModules = const [],
  List<Rig> seenRigs = const [],
  SessionConfig config = const SessionConfig(),
}) async {
  if (rig.master.advData.setup == EdlSetup.FIRMWARE_ERROR) {
    throw EdelkroneError(
      'wrong_device',
      '${rig.master.displayName} (${rig.master.mac}) reports a firmware error: its main firmware is not '
          'running. Update its firmware with the edelkrone application, then switch it off and on.',
    );
  }
  if (!DeviceLibraries.isDrivable(rig.master.model)) {
    throw EdelkroneError('unsupported', '${rig.master.displayName} is not driven by this app (heads and sliders only)');
  }

  var target = rig;
  if (withModules.isNotEmpty) {
    final built = rigFromSelection([rig.master, ...withModules]);
    if (built == null) {
      throw EdelkroneError(
        'unsupported',
        "the SDK's registry lists no layout for ${[rig.master, ...withModules].map((u) => u.displayName).join(' + ')}; "
            'these parts cannot be joined',
      );
    }
    target = built;
  }

  final EdelkroneSession session;
  try {
    session = await EdelkroneSession.open(transport, target.master, config: config);
  } on SessionError catch (e) {
    throw EdelkroneError(
      'timed_out',
      '${target.master.displayName} (${target.master.mac}) was found but did not accept the connection: '
          '${e.message}. It may be connected to the edelkrone app on a phone; close that connection and try again.',
      cause: e,
    );
  }

  final device = Device(session)..setModules(target.orderedSlaves);
  try {
    await device.refresh();
    final current = session.reportedSetup;
    final alreadyFormed = current != null && EdelkroneSession.isMultiModule(current);
    if (target.orderedSlaves.isNotEmpty && !alreadyFormed) {
      await session.setupRig(rig: target);
    } else if (target.orderedSlaves.isNotEmpty &&
        alreadyFormed &&
        !target.orderedSlaves.every((u) => _layoutHolds(current, u))) {
      throw EdelkroneError(
        'layout_refused',
        '${session.device.displayName} is already driving ${current.name.toLowerCase()} and a connected unit '
            'cannot be re-formed. A unit keeps the layout its modules form while they are switched on: switch '
            'the units off and on so that every part advertises on its own, then join them again.',
      );
    }
    _checkTheLayout(device, session, target, asked: withModules.isNotEmpty);
    await _waitForTheModules(device, session, joined: target.orderedSlaves.isNotEmpty && !alreadyFormed);
    device.startPolling();
  } catch (e) {
    try {
      await device.move.stop(settle: 0);
    } catch (_) {}
    await device.disconnect();
    if (e is EdelkroneError) rethrow;
    throw EdelkroneError('connect_failed', '$e', cause: e);
  }
  return device;
}

Set<String> _layoutModuleBodies(EdlSetup? layout) => layout == null
    ? {}
    : layout.name
          .replaceAll('_PLUS', 'PLUS')
          .split('_')
          .where((t) => !const {'AND', 'ONLY', 'PAN', 'TILT'}.contains(t))
          .map((t) => t.replaceAll('SLIDER', 'SLIDE'))
          .toSet();

String? _moduleBody(EdelkroneDevice unit) => switch (DeviceLibraries.familyOf(unit.model)) {
  DeviceFamily.slideModule => 'SLIDE',
  DeviceFamily.dolly => 'DOLLY',
  DeviceFamily.jib => 'JIB',
  _ => null,
};

bool _layoutHolds(EdlSetup? layout, EdelkroneDevice unit) {
  final body = _moduleBody(unit);
  return body == null || _layoutModuleBodies(layout).any((b) => b.startsWith(body));
}

void _checkTheLayout(Device device, EdelkroneSession session, Rig rig, {required bool asked}) {
  if (rig.orderedSlaves.isEmpty) return;
  final reported = session.reportedSetup;
  final held = rig.orderedSlaves.where((u) => _layoutHolds(reported, u)).toList();
  final leftOut = rig.orderedSlaves.where((u) => !held.contains(u)).toList();
  if (asked && leftOut.isNotEmpty) {
    throw EdelkroneError(
      'layout_refused',
      '${session.device.displayName} reports the ${reported?.name.toLowerCase() ?? 'none'} layout: '
          '${leftOut.map((u) => u.displayName).join(' + ')} was not joined. A module that already belongs to another '
          'layout does not join a new one: power the units off and on so that every part advertises on its own, '
          'then join them again.',
    );
  }
  device.setModules(held);
}

Future<void> _waitForTheModules(Device device, EdelkroneSession session, {required bool joined}) async {
  if (device.status.modulesResponding != false) return;
  final ready = await session.waitForState(
    (_) => device.status.modulesResponding != false,
    timeout: _modulesReady,
    interval: 0.3,
  );
  if (ready && device.status.modulesResponding == null) {
    throw EdelkroneError(
      'layout_refused',
      "${session.device.displayName}'s layout dissolved while connecting: its modules did not answer. A module "
          'that still belongs to an earlier layout does not join a new one: switch all the units off and on, then '
          'connect again.',
    );
  }
  if (!ready) {
    if (joined) {
      throw EdelkroneError(
        'layout_refused',
        '${session.device.displayName} took the layout but its modules did not answer within '
            '${_modulesReady.toInt()} s, so the layout will dissolve. Switch the modules off and on, then connect again.',
      );
    }
    EdelkroneLog.warning(
      () =>
          '${session.device.displayName}: the modules did not report answering within '
          '${_modulesReady.toInt()} s; their axes may be missing from status.pose',
    );
    return;
  }
  try {
    await session.readPosition();
  } catch (_) {}
}

/// The units in [rigs] that could join [leader] as modules, according to the
/// registry. Used to offer the user the slider when they pick the head.
List<EdelkroneDevice> joinableWith(EdelkroneDevice leader, List<Rig> rigs) {
  final candidates = <EdelkroneDevice>[];
  for (final r in rigs) {
    for (final u in r.devices) {
      if (u == leader) continue;
      if (rigFromSelection([leader, u])?.master == leader) candidates.add(u);
    }
  }
  return candidates;
}

/// True when [scan] has seen everything [connect] needs before it is worth
/// stopping: a leader whose advertised layout names more modules than are in
/// sight is given a few seconds for them to appear.
bool rigLooksComplete(Rig rig, {DateTime? firstSighting}) {
  final s = rig.master.advData.setup;
  if (!EdelkroneSession.isMultiModule(s)) return true;
  final need = _layoutModuleBodies(s).length;
  if (rig.orderedSlaves.length >= need) return true;
  final since = firstSighting;
  return since != null && DateTime.now().difference(since).inMilliseconds > _moduleSighting * 1000;
}

String normaliseMac(String text) => _normaliseMac(text);
