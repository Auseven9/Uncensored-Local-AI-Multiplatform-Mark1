/// Dempster–Shafer belief combination over a contested memory slot (Phase 4b).
///
/// 2.0 "Living Memory" *detects* when two active claims pin one
/// (subject, attribute) slot to different values (`reconciliation.dart`). Phase
/// 4b *resolves* it: each claim is evidence for its value, weighted by the
/// curator's confidence; Dempster's rule of combination fuses that evidence and
/// reports the **conflict mass** K — how much the evidence genuinely disagreed.
/// A clear winner with low conflict is a confident auto-resolve; high conflict
/// (or a close call) is left for the user to settle.
///
/// Everything here is pure and deterministic — contradiction *resolution*, like
/// detection, belongs in code, not a stochastic 4B. The model supplies the
/// structure (value + confidence per claim); this decides. Unit-tested.
library;

/// One claim's evidence for a slot: the [value] it asserts and the belief mass
/// [confidence] (0..1) behind it. The remainder (1 - confidence) is left as
/// ignorance (Θ), so a single low-confidence claim never masquerades as certain.
class SlotEvidence {
  final String value;
  final double confidence;
  const SlotEvidence(this.value, this.confidence);
}

/// The fused belief state of a slot after combining all evidence.
class BeliefOutcome {
  /// Fused singleton belief per value (each is the mass on exactly that value).
  final Map<String, double> belief;

  /// Residual mass on Θ ("unknown") — how much is still undecided.
  final double ignorance;

  /// Aggregate conflict K in [0,1): how strongly the evidence contradicted.
  final double conflict;

  /// Highest-belief value, or null when there was no evidence.
  final String? top;

  /// Belief of [top].
  final double topBelief;

  /// [topBelief] minus the runner-up's belief — how decisively top leads.
  final double margin;

  const BeliefOutcome({
    required this.belief,
    required this.ignorance,
    required this.conflict,
    required this.top,
    required this.topBelief,
    required this.margin,
  });

  @override
  String toString() =>
      'BeliefOutcome(top=$top b=${topBelief.toStringAsFixed(2)} '
      'margin=${margin.toStringAsFixed(2)} K=${conflict.toStringAsFixed(2)})';
}

double _clip01(double v) => v.isNaN ? 0.0 : (v < 0 ? 0.0 : (v > 1 ? 1.0 : v));

/// Fuse all [evidence] on one slot with Dempster's rule of combination.
///
/// Values are compared case-insensitively on their trimmed form (so "Jayden"
/// and "jayden " are the same candidate); the first spelling seen is kept for
/// display. Multiple claims backing the same value reinforce it; claims backing
/// different values generate conflict. Pure.
BeliefOutcome fuseSlotBeliefs(Iterable<SlotEvidence> evidence) {
  // Canonical key -> display spelling.
  final display = <String, String>{};
  // Accumulator BPA: singleton masses by canonical key, plus the Θ mass.
  var acc = <String, double>{};
  var accTheta = 1.0; // vacuous belief
  var noConflictProduct = 1.0; // Π(1 - K_i) across pairwise combinations

  var sawAny = false;
  for (final e in evidence) {
    final key = e.value.trim().toLowerCase();
    if (key.isEmpty) continue;
    sawAny = true;
    display.putIfAbsent(key, () => e.value.trim());
    final m = _clip01(e.confidence);
    final eTheta = 1.0 - m;

    // Pairwise Dempster combination of acc with the single-value BPA {key: m}.
    var kPair = 0.0;
    for (final entry in acc.entries) {
      if (entry.key != key) kPair += entry.value * m; // singleton disagreement
    }
    final next = <String, double>{};
    acc.forEach((v, mass) {
      // v with e's singleton (only reinforces when same key) + v with e's Θ.
      next[v] = mass * (v == key ? m : 0.0) + mass * eTheta;
    });
    // e's singleton with acc's Θ (and with e's own singleton if acc had it).
    next[key] = (next[key] ?? 0.0) + m * accTheta;
    var nextTheta = accTheta * eTheta;

    final denom = 1.0 - kPair;
    if (denom <= 1e-9) {
      // Total conflict — evidence fully contradicts. Keep the accumulator and
      // record maximal conflict; the decision layer will route this to "ask".
      noConflictProduct = 0.0;
      continue;
    }
    next.updateAll((_, mass) => mass / denom);
    nextTheta /= denom;
    acc = next;
    accTheta = nextTheta;
    noConflictProduct *= (1.0 - kPair);
  }

  if (!sawAny) {
    return const BeliefOutcome(
      belief: {},
      ignorance: 1.0,
      conflict: 0.0,
      top: null,
      topBelief: 0.0,
      margin: 0.0,
    );
  }

  // Re-key to display spellings.
  final belief = <String, double>{
    for (final e in acc.entries) (display[e.key] ?? e.key): e.value,
  };
  final sorted = belief.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top = sorted.isNotEmpty ? sorted.first.key : null;
  final topBelief = sorted.isNotEmpty ? sorted.first.value : 0.0;
  final second = sorted.length > 1 ? sorted[1].value : 0.0;

  return BeliefOutcome(
    belief: belief,
    ignorance: _clip01(accTheta),
    conflict: _clip01(1.0 - noConflictProduct),
    top: top,
    topBelief: topBelief,
    margin: topBelief - second,
  );
}

/// What to do with a fused slot.
enum BeliefVerdict {
  /// A confident winner ([BeliefOutcome.top]) — supersede the rest.
  resolve,

  /// Too much conflict or too close — surface an open question for the user.
  ask,

  /// No usable evidence (e.g. everything was empty).
  insufficient,
}

/// Decide a slot from its fused belief. Resolve only when one value both clears
/// [minTopBelief] AND leads the runner-up by [minMargin], with conflict below
/// [maxConflict]; otherwise ask. Thresholds are the `ds.*` parameters.
BeliefVerdict decideSlot(
  BeliefOutcome o, {
  double minTopBelief = 0.5,
  double minMargin = 0.2,
  double maxConflict = 0.6,
}) {
  if (o.top == null) return BeliefVerdict.insufficient;
  if (o.conflict >= maxConflict) return BeliefVerdict.ask;
  if (o.topBelief >= minTopBelief && o.margin >= minMargin) {
    return BeliefVerdict.resolve;
  }
  return BeliefVerdict.ask;
}
