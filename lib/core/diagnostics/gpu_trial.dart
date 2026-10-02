/// Dependency-free value types for the GPU pen-test harness.
///
/// Kept free of any llamadart or Flutter import so both the engine (which runs
/// a trial, `LlmService.runGpuTrial`) and the orchestrator (which records and
/// persists results, `GpuPenTest`) can share them without a circular import.

/// A GPU backend we attempt to get INTO. CPU is not a "trial" — it always
/// works; these are the paths that may or may not engage on a given device.
enum TrialBackend { vulkan, opencl }

extension TrialBackendLabel on TrialBackend {
  String get label => this == TrialBackend.vulkan ? 'vulkan' : 'opencl';
}

/// The raw outcome of a single trial load, as the engine sees it. A hard native
/// crash never produces one of these — it kills the process — so this only
/// distinguishes success from a *catchable* Dart-level failure.
class GpuTrialOutcome {
  final bool ok;
  final double tps;
  final int tokens;
  final int ms;
  final String? error;

  const GpuTrialOutcome({
    required this.ok,
    this.tps = 0.0,
    this.tokens = 0,
    this.ms = 0,
    this.error,
  });
}

/// How a recorded pen-test stage ended. `crashed` is inferred on the NEXT app
/// launch from a write-ahead breadcrumb that never got its completion record.
enum GpuTrialStatus { ok, failed, crashed }

/// A recorded, persistable result of one pen-test stage.
class GpuTrialResult {
  final TrialBackend backend;
  final int layers;
  final GpuTrialStatus status;
  final double tps;
  final int tokens;
  final int ms;
  final String? error;
  final DateTime ts;

  const GpuTrialResult({
    required this.backend,
    required this.layers,
    required this.status,
    this.tps = 0.0,
    this.tokens = 0,
    this.ms = 0,
    this.error,
    required this.ts,
  });

  /// A single monospace log/report line.
  String get line {
    final who = '${backend.label} ×$layers';
    switch (status) {
      case GpuTrialStatus.ok:
        return '✓ $who → GPU engaged · ${tps.toStringAsFixed(2)} t/s '
            '($tokens tok, ${ms}ms)';
      case GpuTrialStatus.failed:
        return '✗ $who → failed to load/run: ${error ?? 'unknown error'}';
      case GpuTrialStatus.crashed:
        return '💥 $who → CRASHED the app (never finished — seen on relaunch)';
    }
  }

  Map<String, dynamic> toMap() => {
        'backend': backend.label,
        'layers': layers,
        'status': status.name,
        'tps': tps,
        'tokens': tokens,
        'ms': ms,
        'error': error,
        'ts': ts.toIso8601String(),
      };

  static GpuTrialResult fromMap(Map<String, dynamic> m) => GpuTrialResult(
        backend: (m['backend'] == 'opencl')
            ? TrialBackend.opencl
            : TrialBackend.vulkan,
        layers: (m['layers'] as num?)?.toInt() ?? 0,
        status: GpuTrialStatus.values.firstWhere(
          (s) => s.name == m['status'],
          orElse: () => GpuTrialStatus.failed,
        ),
        tps: (m['tps'] as num?)?.toDouble() ?? 0.0,
        tokens: (m['tokens'] as num?)?.toInt() ?? 0,
        ms: (m['ms'] as num?)?.toInt() ?? 0,
        error: m['error'] as String?,
        ts: DateTime.tryParse(m['ts'] as String? ?? '') ?? DateTime.now(),
      );
}
