import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'file_log_sink.dart';

/// Native factory: writes logs to `<documents>/dojo_logs/latest.log`, rotating
/// the prior session to `previous.log`. Each line flushes to disk immediately
/// so a native crash (SIGSEGV) still leaves the last executed step on disk.
FileLogSink createFileLogSink() => _IoFileLogSink();

class _IoFileLogSink implements FileLogSink {
  File? _file;
  String? _currentPath;
  String? _previousPath;

  @override
  bool get isPersistent => _file != null;

  @override
  String? get currentPath => _currentPath;

  @override
  Future<void> init() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'dojo_logs'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final latest = File(p.join(dir.path, 'latest.log'));
      final previous = File(p.join(dir.path, 'previous.log'));

      // Rotate the last session's log aside so a crash log is preserved.
      if (await latest.exists()) {
        try {
          if (await previous.exists()) await previous.delete();
          await latest.rename(previous.path);
        } catch (_) {
          // Non-fatal: fall through and just truncate latest below.
        }
      }
      _previousPath = previous.path;

      final header =
          '=== Eidetic Dojo log · session start ${DateTime.now().toUtc().toIso8601String()} ===\n';
      await latest.writeAsString(header, flush: true);
      _file = latest;
      _currentPath = latest.path;
    } catch (_) {
      // Logging must never break startup; disk sink stays disabled.
      _file = null;
      _currentPath = null;
    }
  }

  @override
  void writeLine(String line) {
    final file = _file;
    if (file == null) return;
    try {
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Never let logging throw.
    }
  }

  @override
  Future<String> readCurrent() async => _safeRead(_currentPath);

  @override
  Future<String> readPrevious() async => _safeRead(_previousPath);

  Future<String> _safeRead(String? path) async {
    if (path == null) return '';
    try {
      final f = File(path);
      if (!await f.exists()) return '';
      return await f.readAsString();
    } catch (_) {
      return '';
    }
  }
}
