/// Adaptive memory dynamics (Phase 3) — the forgetting curve and its inverse.
///
/// This is the tunable heart of "adaptable memory": a two-strength model
/// inspired by Bjork's *new theory of disuse*. Every claim carries two numbers,
/// both already persisted on the semantic_facts row, so Phase 3 needs no schema
/// change:
///
///  * **salience** — *retrieval strength*. Fast-moving: it jumps when a claim is
///    recalled ([reinforcedSalience]) and relaxes toward a floor when it isn't
///    ([decayedSalience]). This is the 25 % term the recall ranker blends in, so
///    moving it genuinely changes what surfaces next time.
///  * **confidence** — *storage strength*. Slow-moving and near-monotonic: each
///    recall nudges it up a little ([reinforcedConfidence]), and it sets the
///    permanence floor ([permanenceFloor]) that salience can never decay below.
///    A claim that keeps proving useful quietly becomes "core" and stops fading.
///
/// Every function here is pure, deterministic, dependency-free, and clamps its
/// output to [0, 1] — so no setting of the `decay.*` parameters can drive a
/// claim's strengths out of range or make recall blow up. The behaviour is
/// shaped entirely by the three knobs the Settings panel already documents:
/// `decay.tauBaseCycles` (τ), `decay.alpha` (reinforcement strength) and
/// `decay.beta` (permanence).
library;

import 'dart:math' as math;

/// Internal scaling constants mapping the user-facing 0..10 `alpha`/`beta`
/// knobs onto the 0..1 strengths. Chosen so the documented defaults behave
/// gently: at the default `alpha = 2` a recall closes ~8 % of salience's gap to
/// 1.0 and accrues ~2 % of confidence's; at the default `beta = 1` a claim's
/// permanence floor is ~10 % of its confidence. Kept here (not as params) so the
/// four decay.* knobs stay the whole tuning surface.
const double _kSalienceBoostPerAlpha = 0.04;
const double _kConfidenceBoostPerAlpha = 0.01;
const double _kFloorPerBeta = 0.10;

double _clamp01(double v) => v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);

/// The permanence floor a claim's [salience] decays *toward* — never past.
///
/// Derived from the claim's [confidence] (its storage strength) scaled by
/// [beta] (`decay.beta`). At `beta = 0` nothing is permanent (floor 0 — pure
/// Ebbinghaus forgetting all the way to zero). At the default `beta = 1` a claim
/// keeps ~10 % of its confidence as a residual pull on recall. At high `beta` a
/// fully-confident ("core") claim stops decaying at all. Clamped to [0, 1].
double permanenceFloor(double confidence, double beta) {
  if (beta <= 0.0) return 0.0;
  return _clamp01((beta * _kFloorPerBeta) * _clamp01(confidence));
}

/// One Ebbinghaus-style forgetting step on a claim's [salience].
///
/// [cyclesElapsed] cycles have passed since decay was last recomputed; [tau]
/// (`decay.tauBaseCycles`) is the forgetting time-constant in those same units.
/// Salience relaxes exponentially from its current value toward [floor]:
///
///   s' = floor + (s - floor) · e^(-cyclesElapsed / tau)
///
/// so after `tau` cycles ~63 % of the distance to the floor is gone. It never
/// drops below [floor], and a claim already at/under the floor is returned
/// unchanged. A non-positive [cyclesElapsed] or [tau] is a no-op (returns the
/// clamped input), which is what lets `decay.tauBaseCycles` be treated as "off"
/// at its extreme without a special case upstream.
double decayedSalience(
  double salience, {
  required double cyclesElapsed,
  required double tau,
  required double floor,
}) {
  final s = _clamp01(salience);
  final fl = _clamp01(floor);
  if (cyclesElapsed <= 0.0 || tau <= 0.0) return s;
  if (s <= fl) return s;
  final factor = math.exp(-cyclesElapsed / tau);
  return _clamp01(fl + (s - fl) * factor);
}

/// Reinforcement of retrieval strength when a claim is actually recalled.
///
/// [salience] jumps a fraction of the remaining distance to 1.0, the fraction
/// set by [alpha] (`decay.alpha`):
///
///   s' = s + (alpha · 0.04) · (1 - s)
///
/// `alpha = 0` ⇒ no reinforcement (recall does not strengthen); the default
/// `alpha = 2` closes ~8 % of the gap per recall; a high `alpha` makes used
/// memories stick hard. Diminishing returns mean a much-recalled claim
/// saturates just under 1.0 rather than pegging on the first hit — so recall
/// order still discriminates among frequently-used claims. Clamped to [0, 1].
double reinforcedSalience(double salience, double alpha) {
  final s = _clamp01(salience);
  if (alpha <= 0.0) return s;
  final boost = _clamp01(alpha * _kSalienceBoostPerAlpha);
  return _clamp01(s + boost * (1.0 - s));
}

/// Slow accrual of storage strength on recall: each successful recall nudges
/// [confidence] up a little, so a claim that keeps earning its place gradually
/// becomes "core" (raising its [permanenceFloor]). Deliberately gentler than
/// the salience bump — storage strength should take sustained use to build:
///
///   c' = c + (alpha · 0.01) · (1 - c)
///
/// `alpha = 0` ⇒ no accrual. Clamped to [0, 1]. This is the only place recall
/// writes confidence; the curator still sets its initial value.
double reinforcedConfidence(double confidence, double alpha) {
  final c = _clamp01(confidence);
  if (alpha <= 0.0) return c;
  final bump = _clamp01(alpha * _kConfidenceBoostPerAlpha);
  return _clamp01(c + bump * (1.0 - c));
}
