// Platform-specific file log sink. On native (dart:io present) this writes to
// disk with an immediate flush per line so logs survive a hard/native crash;
// on the web it is a no-op (no filesystem).
import 'file_log_sink_stub.dart'
    if (dart.library.io) 'file_log_sink_io.dart' as platform;

/// A durable, append-only sink for log lines.
///
/// Implementations must never throw from [writeLine] — logging must not be able
/// to crash the app. Writes flush immediately so that the last line before a
/// native SIGSEGV is still on disk for post-mortem debugging.
abstract class FileLogSink {
  /// Whether lines are actually persisted (false for the web no-op sink).
  bool get isPersistent;

  /// Absolute path of the current session's log file, once opened.
  String? get currentPath;

  /// Opens the log file, rotating the previous session's log aside.
  Future<void> init();

  /// Appends one already-formatted line and flushes. Best-effort, never throws.
  void writeLine(String line);

  /// Reads back the current session's log (empty string if unavailable).
  Future<String> readCurrent();

  /// Reads back the previous session's log (empty string if unavailable).
  Future<String> readPrevious();
}

/// Builds the platform-appropriate [FileLogSink].
FileLogSink createFileLogSink() => platform.createFileLogSink();
