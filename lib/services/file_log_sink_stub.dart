import 'file_log_sink.dart';

/// Web fallback: no filesystem, so logging to disk is a no-op.
FileLogSink createFileLogSink() => _NoopFileLogSink();

class _NoopFileLogSink implements FileLogSink {
  @override
  bool get isPersistent => false;

  @override
  String? get currentPath => null;

  @override
  Future<void> init() async {}

  @override
  void writeLine(String line) {}

  @override
  Future<String> readCurrent() async => '';

  @override
  Future<String> readPrevious() async => '';
}
