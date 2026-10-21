/// The Flutter-side pieces the pure controller leaves to the app: where pose
/// names are kept, and a buffer the SDK's diagnostic log writes into.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../sdk/log.dart';
import 'rig_controller.dart';

/// Pose names in SharedPreferences, one entry per rig (by the leader's MAC).
class PrefsPoseNameStore implements PoseNameStore {
  static String _key(String rig) => 'pose_names_v2:$rig';

  @override
  Future<Map<int, String>> load(String rigKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(rigKey));
      if (raw == null) return {};
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in m.entries) int.parse(e.key): '${e.value}'};
    } catch (_) {
      // A lost name is a cosmetic loss, never a reason to fail a connect.
      return {};
    }
  }

  @override
  Future<void> save(String rigKey, Map<int, String> names) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(rigKey), jsonEncode({for (final e in names.entries) '${e.key}': e.value}));
    } catch (_) {}
  }
}

/// The last few hundred SDK log lines, for the diagnostics sheet.
class LogBuffer {
  LogBuffer._();
  static final instance = LogBuffer._();

  final lines = <String>[];
  static const _max = 600;

  void install({EdelkroneLogLevel level = EdelkroneLogLevel.debug}) {
    EdelkroneLog.minimumLevel = level;
    EdelkroneLog.sink = (lvl, message) {
      final t = DateTime.now().toIso8601String().substring(11, 23);
      lines.add('$t ${lvl.name.toUpperCase().padRight(7)} $message');
      if (lines.length > _max) lines.removeRange(0, lines.length - _max);
    };
  }

  String get text => lines.join('\n');
}
