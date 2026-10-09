/// U-score (Phase 4) — the uncertainty signal that gates System 1 (fast,
/// intuitive) against System 2 (slow, deliberate).
///
/// The idea (dual-process cognition): most turns are answered directly, but a
/// turn the system is *uncertain* about should trigger more careful reasoning.
/// The U-score is a single 0..1 number blended from five components, each a
/// distinct reason to be unsure, weighted by the `u.*` parameters:
///
///   U = Σ wᵢ·componentᵢ / Σ wᵢ
///
/// (weight-normalized, so the five `u.w*` knobs can be tuned freely without
/// having to keep them summing to 1). When `U ≥ u.threshold` the turn is gated
/// to System 2.
///
/// Everything here is pure, deterministic and clamped to [0,1] — the *signals*
/// that feed it (how well memory covered the query, how novel it is, …) are
/// computed upstream from the recall pass; this file only defines the blend and
/// the gate so both are unit-testable in isolation.
library;

/// Which reasoning posture a turn is gated to.
enum UMode { system1, system2 }

double _c01(double v) => v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);

/// The five uncertainty components, each 0..1 (0 = no uncertainty from that
/// source, 1 = maximal). See the `u.*` parameter help for the plain-language
/// meaning of each.
class UScoreInputs {
  /// Prediction error — the input is far from what memory would have predicted
  /// (e.g. recall found no strong match). High = "this surprised me".
  final double prediction;

  /// Contradiction — the query touches beliefs that conflict with each other
  /// (claims in an unresolved contradiction). High = "this clashes with what I
  /// already hold".
  final double contradiction;

  /// Novelty — little or nothing in memory is about this at all. High = "I've
  /// never seen anything like this".
  final double novelty;

  /// Ambiguity — the query could mean several things (very short/underspecified,
  /// or several memories compete equally). High = "this could mean many things".
  final double ambiguity;

  /// Risk — getting this wrong would be costly (high-stakes topic). High pushes
  /// toward careful reasoning even when the other signals are calm.
  final double risk;

  const UScoreInputs({
    this.prediction = 0.0,
    this.contradiction = 0.0,
    this.novelty = 0.0,
    this.ambiguity = 0.0,
    this.risk = 0.0,
  });
}

/// The five blend weights (the `u.w*` parameters). Defaults match the registry.
class UScoreWeights {
  final double prediction;
  final double contradiction;
  final double novelty;
  final double ambiguity;
  final double risk;

  const UScoreWeights({
    this.prediction = 0.25,
    this.contradiction = 0.20,
    this.novelty = 0.15,
    this.ambiguity = 0.15,
    this.risk = 0.25,
  });
}

/// A scored turn: the blended value, the components that produced it (for a
/// readable breakdown in telemetry), and the gated reasoning mode.
class UScore {
  final double value;
  final UScoreInputs inputs;
  final UMode mode;
  const UScore(this.value, this.inputs, this.mode);

  /// Compact one-line breakdown for logs/telemetry, e.g.
  /// "U=0.42 → System 1 (pred 0.6 con 0.0 nov 0.3 amb 0.2 risk 0.0)".
  String get breakdown {
    String f(double v) => v.toStringAsFixed(1);
    final m = mode == UMode.system2 ? 'System 2' : 'System 1';
    return 'U=${value.toStringAsFixed(2)} → $m '
        '(pred ${f(inputs.prediction)} con ${f(inputs.contradiction)} '
        'nov ${f(inputs.novelty)} amb ${f(inputs.ambiguity)} '
        'risk ${f(inputs.risk)})';
  }
}

/// The weight-normalized blend of the five components → 0..1. A non-positive
/// total weight yields 0 (no signal ⇒ no uncertainty), so turning every weight
/// off degrades cleanly to "always System 1".
double computeUScore(UScoreInputs i, UScoreWeights w) {
  final wsum =
      w.prediction + w.contradiction + w.novelty + w.ambiguity + w.risk;
  if (wsum <= 0.0) return 0.0;
  final s = w.prediction * _c01(i.prediction) +
      w.contradiction * _c01(i.contradiction) +
      w.novelty * _c01(i.novelty) +
      w.ambiguity * _c01(i.ambiguity) +
      w.risk * _c01(i.risk);
  return _c01(s / wsum);
}

/// Gate a score to a reasoning mode: System 2 once `u ≥ threshold`.
UMode gateMode(double u, double threshold) =>
    _c01(u) >= _c01(threshold) ? UMode.system2 : UMode.system1;

/// Score and gate in one call — the usual entry point.
UScore scoreUncertainty(
  UScoreInputs inputs,
  UScoreWeights weights,
  double threshold,
) {
  final v = computeUScore(inputs, weights);
  return UScore(v, inputs, gateMode(v, threshold));
}

/// The deliberate-reasoning directive prepended to a turn's system prompt when
/// it gates to System 2. A single-pass posture change (no extra inference): it
/// just asks the model to slow down and lean on memory for this one reply. The
/// multi-round convergence loop (`conv.*`) is a later increment.
const String system2Directive =
    '[Careful mode] This request looks uncertain or unfamiliar. Think it '
    'through step by step, rely strictly on the remembered facts above, and if '
    'you do not actually know something, say so plainly rather than guessing.';
