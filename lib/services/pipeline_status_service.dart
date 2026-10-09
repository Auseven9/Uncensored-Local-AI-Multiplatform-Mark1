import 'package:get/get.dart';

import 'log_service.dart';

/// Every distinct thing the system can be doing, in the order a turn tends to
/// move through them. [idle] means nothing is in flight; [error] means the last
/// operation failed and the message is worth showing until the next one starts.
enum PipelinePhase {
  idle,
  arming, // a native engine is being created / about to spin up
  loading, // a model is loading into memory (has a % progress)
  recalling, // searching memory for relevant context
  embedding, // running the embedder (indexing or cue vector)
  prompting, // building the prompt / handing off to the engine
  generating, // the model is producing tokens
  consolidating, // curating episodic turns into semantic facts
  error,
}

extension PipelinePhaseLabel on PipelinePhase {
  /// Short human label for the status strip.
  String get label {
    switch (this) {
      case PipelinePhase.idle:
        return 'Idle';
      case PipelinePhase.arming:
        return 'Arming engine';
      case PipelinePhase.loading:
        return 'Loading model';
      case PipelinePhase.recalling:
        return 'Searching memory';
      case PipelinePhase.embedding:
        return 'Embedding';
      case PipelinePhase.prompting:
        return 'Preparing';
      case PipelinePhase.generating:
        return 'Generating';
      case PipelinePhase.consolidating:
        return 'Consolidating memory';
      case PipelinePhase.error:
        return 'Error';
    }
  }
}

/// One breadcrumb in the activity trail — a step that happened, with the
/// elapsed offset (ms) from when the current run of work began.
class PipelineStep {
  final PipelinePhase phase;
  final String text;
  final int atMs; // wall-clock epoch ms
  final int offsetMs; // ms since the active run began
  const PipelineStep(this.phase, this.text, this.atMs, this.offsetMs);
}

/// A single reactive source of truth for "what is the system doing right now",
/// published to by every layer (chat turn, model load, memory recall/embedding,
/// consolidation) and rendered live in the chat's status strip. The point is
/// that on a 0.1 tok/s device the wait should still be *informative* — the user
/// sees each step, a ticking timer, and generation progress, so waiting feels
/// like receiving information rather than staring at nothing.
///
/// Everything here is cheap observable state; it never touches the engine.
class PipelineStatusService extends GetxService {
  LogService? get _log {
    try {
      return Get.find<LogService>();
    } catch (_) {
      return null;
    }
  }

  /// The current phase. [PipelinePhase.idle] hides the strip.
  final phase = PipelinePhase.idle.obs;

  /// Human detail for the current phase (e.g. "recalled 3 · 2 meaning").
  final detail = ''.obs;

  /// Epoch ms when the current run of work began (0 while idle). Drives the
  /// elapsed timer in the UI.
  final activeSinceMs = 0.obs;

  /// 0..1 for a determinate bar (model load %, tokens/budget), or null for an
  /// indeterminate bar (we don't know how long this phase takes).
  final progress = Rxn<double>();

  /// Tokens produced so far this generation, and the live rate.
  final tokens = 0.obs;
  final tps = 0.0.obs;

  /// Most-recent-first breadcrumb trail, capped so it never grows unbounded.
  final steps = <PipelineStep>[].obs;
  static const _maxSteps = 40;

  bool get isActive => phase.value != PipelinePhase.idle;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  int _offset() {
    final since = activeSinceMs.value;
    if (since == 0) return 0;
    return _now - since;
  }

  void _crumb(PipelinePhase p, String text) {
    steps.insert(0, PipelineStep(p, text, _now, _offset()));
    if (steps.length > _maxSteps) {
      steps.removeRange(_maxSteps, steps.length);
    }
  }

  /// Enter [p] with [detail]. Starts the run clock if we were idle. Optional
  /// [progress] seeds a determinate bar; omit for indeterminate.
  void begin(PipelinePhase p, String detail, {double? progress}) {
    if (activeSinceMs.value == 0 || phase.value == PipelinePhase.error) {
      activeSinceMs.value = _now;
    }
    phase.value = p;
    this.detail.value = detail;
    this.progress.value = progress;
    if (p != PipelinePhase.generating) {
      // Generation manages its own token/tps counters; other phases reset them.
      tokens.value = 0;
      tps.value = 0.0;
    }
    _crumb(p, detail);
    _log?.info('▶ ${p.label}${detail.isEmpty ? '' : ' · $detail'}',
        source: 'Pipeline');
  }

  /// Record a step within the current phase (a probe firing), without changing
  /// the phase. Shows as the new detail line and a breadcrumb.
  void mark(String text, {double? progress}) {
    detail.value = text;
    if (progress != null) this.progress.value = progress;
    _crumb(phase.value, text);
    _log?.info('· $text', source: 'Pipeline');
  }

  /// Update the determinate bar (e.g. model-load %).
  void setProgress(double? value) => progress.value = value;

  /// Update the live generation counters and the tokens/budget bar.
  void setGeneration({required int tokens, required double tps, int? budget}) {
    this.tokens.value = tokens;
    this.tps.value = tps;
    if (budget != null && budget > 0) {
      progress.value = (tokens / budget).clamp(0.0, 1.0);
    }
  }

  /// Finish the current run — back to idle, strip hides.
  void done([String? detail]) {
    if (detail != null && detail.isNotEmpty) {
      _crumb(phase.value, detail);
      _log?.info('✓ $detail', source: 'Pipeline');
    }
    phase.value = PipelinePhase.idle;
    this.detail.value = '';
    progress.value = null;
    activeSinceMs.value = 0;
    tokens.value = 0;
    tps.value = 0.0;
  }

  /// Surface a failure — the strip turns red and holds the message until the
  /// next [begin]. Logged as an error so it lands in the crash-surviving sink.
  void fail(String detail) {
    phase.value = PipelinePhase.error;
    this.detail.value = detail;
    progress.value = null;
    _crumb(PipelinePhase.error, detail);
    _log?.error('✗ $detail', source: 'Pipeline');
  }

  /// Clear an error back to idle (e.g. the user starts a new action).
  void clearError() {
    if (phase.value == PipelinePhase.error) done();
  }
}

/// Format an elapsed duration compactly for the status timer: "0.8s", "12.3s",
/// "1:05", "12:07". Pure and unit-tested.
String formatElapsed(Duration d) {
  final totalMs = d.inMilliseconds;
  if (totalMs < 0) return '0.0s';
  if (totalMs < 60000) {
    return '${(totalMs / 1000).toStringAsFixed(1)}s';
  }
  final totalSeconds = totalMs ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
