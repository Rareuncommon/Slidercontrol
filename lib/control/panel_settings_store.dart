/// Persistence for [PanelSettings].
///
/// Split from the value class so the settings themselves stay pure Dart and
/// testable without a plugin binding.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'panel_settings.dart';

class PanelSettingsStore {
  /// Settings are per device kind: a sensible speed for the slider is not
  /// necessarily a sensible one for the head, and the head's leg duration has
  /// no slider equivalent at all.
  const PanelSettingsStore(this.deviceKind);

  final String deviceKind;

  String get _key => 'panel_settings_$deviceKind';

  Future<PanelSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key);
      if (raw == null) return const PanelSettings();
      final map = <String, Object?>{};
      for (final entry in raw) {
        final i = entry.indexOf('=');
        if (i <= 0) continue;
        final key = entry.substring(0, i);
        final value = entry.substring(i + 1);
        map[key] = num.tryParse(value);
      }
      return PanelSettings.fromMap(map);
    } catch (_) {
      // Never let a preferences problem stop the app talking to a motor.
      return const PanelSettings();
    }
  }

  Future<void> save(PanelSettings s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _key,
        s.sanitised().toMap().entries.map((e) => '${e.key}=${e.value}').toList(),
      );
    } catch (_) {
      // Losing a preference is not worth surfacing as an error.
    }
  }
}
