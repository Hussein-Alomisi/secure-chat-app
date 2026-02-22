import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

/// Centralized logger for SecureChat
/// Usage:
///   AppLogger.i('Connected to server');
///   AppLogger.e('Login failed', error: e, stackTrace: st);
///   AppLogger.d('Message sent', tag: 'SOCKET');
class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    level: kReleaseMode ? Level.warning : Level.trace,
    printer: PrettyPrinter(
      methodCount: 1,
      errorMethodCount: 5,
      lineLength: 80,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    output: MultiOutput([
      ConsoleOutput(),
      _FileOutput(), // logs to in-memory buffer
    ]),
  );

  // ── Convenience methods ──────────────────────────────────────────────────

  /// Verbose / trace — very detailed info (disabled in release)
  static void v(String message, {String? tag}) =>
      _logger.t(_format(message, tag));

  /// Debug info
  static void d(String message, {String? tag}) =>
      _logger.d(_format(message, tag));

  /// General info
  static void i(String message, {String? tag}) =>
      _logger.i(_format(message, tag));

  /// Warning
  static void w(String message, {String? tag, Object? error}) =>
      _logger.w(_format(message, tag), error: error);

  /// Error with optional exception and stack trace
  static void e(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _logger.e(_format(message, tag), error: error, stackTrace: stackTrace);

  /// Fatal error
  static void wtf(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.f(message, error: error, stackTrace: stackTrace);

  static String _format(String message, String? tag) =>
      tag != null ? '[$tag] $message' : message;

  /// Get recent log entries (for debug screen)
  static List<String> get recentLogs => _FileOutput._logs.toList();

  /// Clear logs
  static void clearLogs() => _FileOutput._logs.clear();
}

/// In-memory log output — stores last 500 lines for debug screen
class _FileOutput extends LogOutput {
  static final List<String> _logs = [];
  static const int _maxLines = 500;

  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      if (_logs.length >= _maxLines) _logs.removeAt(0);
      _logs.add(line);
    }
  }
}
