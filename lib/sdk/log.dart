/// Diagnostic log for the SDK port, mirroring `edelkrone.EdelkroneLog`.
///
/// Off by default, as in the Python SDK. Messages are passed as closures so
/// that nothing is formatted unless a sink is listening.
library;

enum EdelkroneLogLevel { TRACE, DEBUG, INFO, WARNING, ERROR }

typedef EdelkroneLogSink = void Function(EdelkroneLogLevel level, String message);

abstract final class EdelkroneLog {
  static EdelkroneLogSink? sink;
  static EdelkroneLogLevel minimumLevel = EdelkroneLogLevel.INFO;

  static bool isEnabled(EdelkroneLogLevel level) =>
      sink != null && level.index >= minimumLevel.index;

  static void _emit(EdelkroneLogLevel level, String Function() message) {
    final s = sink;
    if (s == null || level.index < minimumLevel.index) return;
    try {
      s(level, message());
    } catch (_) {
      // A sink must not take the session down with it.
    }
  }

  static void trace(String Function() message) => _emit(EdelkroneLogLevel.TRACE, message);
  static void debug(String Function() message) => _emit(EdelkroneLogLevel.DEBUG, message);
  static void info(String Function() message) => _emit(EdelkroneLogLevel.INFO, message);
  static void warning(String Function() message) => _emit(EdelkroneLogLevel.WARNING, message);
  static void error(String Function() message) => _emit(EdelkroneLogLevel.ERROR, message);
}
