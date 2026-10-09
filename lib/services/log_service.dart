import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'file_log_sink.dart';

class LogEntry {
  final DateTime timestamp;
  final String level; // DEBUG, INFO, WARN, ERROR
  final String message;
  final String? source;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.source,
  });

  /// Short form used by the in-app log list (local time, seconds).
  String get formatted {
    final t = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
    final src = source != null ? ' ($source)' : '';
    return '[$t] [$level]$src $message';
  }

  /// Full form written to disk (UTC, millisecond precision) — precise enough to
  /// time the last step before a crash.
  String get fileLine {
    final src = source != null ? ' ($source)' : '';
    return '${timestamp.toUtc().toIso8601String()} [$level]$src $message';
  }
}

/// Central logging with a crash-surviving disk sink.
///
/// Every entry is kept in memory (for the in-app Logs screen) **and** appended
/// to a per-session file that is flushed on each write, so the last steps
/// before a native crash are recoverable. On the next launch the prior
/// session's log is rotated to `previous.log` and can be exported.
class LogService extends GetxService {
  static const int maxLogs = 5000;
  final logs = <LogEntry>[].obs;

  final FileLogSink _sink = createFileLogSink();
  bool _sinkReady = false;
  final List<String> _pending = [];

  LogService init() {
    // Open the disk sink asynchronously; lines logged before it is ready are
    // buffered and flushed once it opens.
    _openSink();
    info('App started', source: 'System');
    return this;
  }

  Future<void> _openSink() async {
    try {
      await _sink.init();
    } catch (_) {
      // ignore — disk logging stays disabled
    }
    _sinkReady = true;
    if (_sink.isPersistent) {
      for (final line in _pending) {
        _sink.writeLine(line);
      }
      _pending.clear();
      info('File logging active: ${_sink.currentPath}', source: 'Log');
    } else {
      _pending.clear();
    }
  }

  bool get isPersistent => _sink.isPersistent;
  String? get logFilePath => _sink.currentPath;

  void debug(String message, {String? source}) =>
      _add('DEBUG', message, source);

  void info(String message, {String? source}) => _add('INFO', message, source);

  void warn(String message, {String? source}) => _add('WARN', message, source);

  void error(String message, {String? source}) =>
      _add('ERROR', message, source);

  void _add(String level, String message, String? source) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      source: source,
    );
    logs.add(entry);
    while (logs.length > maxLogs) {
      logs.removeAt(0);
    }

    final line = entry.fileLine;
    if (_sinkReady) {
      _sink.writeLine(line);
    } else {
      _pending.add(line);
      if (_pending.length > 4000) _pending.removeAt(0);
    }

    // Live console output for `flutter run` / logcat.
    if (kDebugMode) debugPrint(line);
  }

  /// Export the in-memory buffer (current session only).
  String exportAll() {
    final buf = StringBuffer()
      ..writeln('=== Portable AI Logs (in-memory) ===')
      ..writeln('Exported: ${DateTime.now().toIso8601String()}')
      ..writeln('Persistent: $isPersistent  Path: ${logFilePath ?? '-'}')
      ..writeln('Total entries: ${logs.length}')
      ..writeln('');
    for (final entry in logs) {
      buf.writeln(entry.formatted);
    }
    return buf.toString();
  }

  /// Export the on-disk logs, including the previous session — this is the copy
  /// that survives a crash. Falls back to the in-memory buffer on the web.
  Future<String> exportPersisted() async {
    if (!isPersistent) return exportAll();
    final previous = await _sink.readPrevious();
    final current = await _sink.readCurrent();
    final buf = StringBuffer()
      ..writeln('=== Eidetic Dojo persisted logs ===')
      ..writeln('Exported: ${DateTime.now().toIso8601String()}')
      ..writeln('Current log: ${logFilePath ?? '-'}')
      ..writeln('');
    if (previous.trim().isNotEmpty) {
      buf
        ..writeln('----- PREVIOUS SESSION (likely the crash) -----')
        ..writeln(previous)
        ..writeln('----- END PREVIOUS SESSION -----')
        ..writeln('');
    }
    buf
      ..writeln('----- CURRENT SESSION -----')
      ..writeln(current);
    return buf.toString();
  }

  void clear() => logs.clear();
}
