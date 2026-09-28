import 'dart:developer' as developer;

import 'config.dart';

/// Receives SDK log lines. The default logger writes to `dart:developer`
/// under the name `kletso`.
typedef KletsoLogger =
    void Function(
      KletsoLogLevel level,
      String message, {
      Object? error,
      StackTrace? stackTrace,
    });

/// Level-filtered logger used throughout the SDK.
final class KletsoLog {
  /// Creates a log that forwards lines at or above [minimum] to [sink].
  KletsoLog(this.minimum, [KletsoLogger? sink]) : _sink = sink ?? _developer;

  /// Minimum level that is forwarded.
  final KletsoLogLevel minimum;
  final KletsoLogger _sink;

  static void _developer(
    KletsoLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: 'kletso',
      level: switch (level) {
        KletsoLogLevel.debug => 500,
        KletsoLogLevel.info => 800,
        KletsoLogLevel.warning => 900,
        KletsoLogLevel.error => 1000,
        KletsoLogLevel.none => 2000,
      },
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Whether [level] would be forwarded.
  bool enabled(KletsoLogLevel level) =>
      minimum != KletsoLogLevel.none && level.index >= minimum.index;

  /// Logs at debug level.
  void debug(String message) => _log(KletsoLogLevel.debug, message);

  /// Logs at info level.
  void info(String message) => _log(KletsoLogLevel.info, message);

  /// Logs at warning level.
  void warning(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(KletsoLogLevel.warning, message, error, stackTrace);

  /// Logs at error level.
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(KletsoLogLevel.error, message, error, stackTrace);

  void _log(
    KletsoLogLevel level,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (!enabled(level)) return;
    _sink(level, message, error: error, stackTrace: stackTrace);
  }
}
