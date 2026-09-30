/// Registry of every tunable AETHER parameter.
///
/// This is the single source of truth. Each mechanism reads its values from
/// [ParametersService] by key, and the Parameters panel renders itself from
/// this list — so adding a knob here makes it adjustable in the UI
/// automatically. Parameters whose subsystem hasn't shipped yet are defined
/// anyway (they take effect as each phase lands).
enum ParamType { doubleType, intType, boolType, stringType }

class ParamSpec {
  final String key;
  final String label;
  final String group;
  final ParamType type;
  final Object def;
  final double? min;
  final double? max;
  final String? help;

  const ParamSpec({
    required this.key,
    required this.label,
    required this.group,
    required this.type,
    required this.def,
    this.min,
    this.max,
    this.help,
  });
}

/// All AETHER tunables. Grouped by subsystem.
const List<ParamSpec> aetherParamRegistry = [
  // ── Generation (model sampling) ─────────────────────────────
  ParamSpec(key: 'gen.temperature', label: 'Temperature', group: 'Generation', type: ParamType.doubleType, def: 0.7, min: 0.0, max: 2.0, help: 'Sampling randomness.'),
  ParamSpec(key: 'gen.topP', label: 'Top-P', group: 'Generation', type: ParamType.doubleType, def: 0.9, min: 0.0, max: 1.0),
  ParamSpec(key: 'gen.topK', label: 'Top-K', group: 'Generation', type: ParamType.intType, def: 40, min: 0, max: 200),
  ParamSpec(key: 'gen.repeatPenalty', label: 'Repeat penalty', group: 'Generation', type: ParamType.doubleType, def: 1.1, min: 0.5, max: 2.0),
  ParamSpec(key: 'gen.maxTokens', label: 'Max tokens', group: 'Generation', type: ParamType.intType, def: 4096, min: 64, max: 8192),

  // ── Recall (associative recall engine) ──────────────────────
  ParamSpec(key: 'recall.k', label: 'Max memories injected (k)', group: 'Recall', type: ParamType.intType, def: 8, min: 0, max: 30, help: 'Upper bound on memories injected per turn (0 disables recall).'),
  ParamSpec(key: 'recall.memoryAwareness', label: 'Tell model it has memory', group: 'Recall', type: ParamType.boolType, def: true, help: 'Inject a one-line note so the model relies on memory instead of guessing. Off = pure blank slate.'),
  ParamSpec(key: 'recall.charBudget', label: 'Injection budget (chars)', group: 'Recall', type: ParamType.intType, def: 600, min: 0, max: 4000, help: 'Character cap on injected memory (protects the small context window).'),
  ParamSpec(key: 'recall.episodicDepth', label: 'Episodic search depth', group: 'Recall', type: ParamType.intType, def: 12, min: 0, max: 100, help: 'How many raw episodic turns to consider as recall candidates.'),
  ParamSpec(key: 'recall.wRelevance', label: 'Weight: relevance', group: 'Recall', type: ParamType.doubleType, def: 0.6, min: 0.0, max: 1.0),
  ParamSpec(key: 'recall.wSalience', label: 'Weight: salience', group: 'Recall', type: ParamType.doubleType, def: 0.25, min: 0.0, max: 1.0),
  ParamSpec(key: 'recall.wRecency', label: 'Weight: recency', group: 'Recall', type: ParamType.doubleType, def: 0.15, min: 0.0, max: 1.0),
  ParamSpec(key: 'recall.recencyHalfLifeHours', label: 'Recency half-life (h)', group: 'Recall', type: ParamType.doubleType, def: 72.0, min: 1.0, max: 8760.0),
  ParamSpec(key: 'recall.minTokenLen', label: 'Min keyword length', group: 'Recall', type: ParamType.intType, def: 3, min: 1, max: 8),

  // ── Consolidation gate (episodic → semantic) ────────────────
  ParamSpec(key: 'consolidate.minEntries', label: 'Min pending to run', group: 'Consolidation', type: ParamType.intType, def: 6, min: 1, max: 50, help: 'Below this, no model pass runs (0% compute).'),
  ParamSpec(key: 'consolidate.maxEntriesPerPass', label: 'Max entries per pass', group: 'Consolidation', type: ParamType.intType, def: 40, min: 5, max: 200),
  ParamSpec(key: 'consolidate.maxFactsPerPass', label: 'Max facts per pass', group: 'Consolidation', type: ParamType.intType, def: 12, min: 1, max: 50),
  ParamSpec(key: 'consolidate.temperature', label: 'Curator temperature', group: 'Consolidation', type: ParamType.doubleType, def: 0.2, min: 0.0, max: 1.5),
  ParamSpec(key: 'consolidate.minFactLen', label: 'Min fact length', group: 'Consolidation', type: ParamType.intType, def: 8, min: 1, max: 100),
  ParamSpec(key: 'consolidate.maxFactLen', label: 'Max fact length', group: 'Consolidation', type: ParamType.intType, def: 500, min: 50, max: 2000),

  // ── Spreading activation (graph recall) ─────────────────────
  ParamSpec(key: 'spreading.alpha', label: 'Decay factor (α)', group: 'Spreading activation', type: ParamType.doubleType, def: 0.85, min: 0.0, max: 1.0),
  ParamSpec(key: 'spreading.threshold', label: 'Activation floor', group: 'Spreading activation', type: ParamType.doubleType, def: 0.15, min: 0.0, max: 1.0),
  ParamSpec(key: 'spreading.maxHops', label: 'Max hops', group: 'Spreading activation', type: ParamType.intType, def: 2, min: 1, max: 4),
  ParamSpec(key: 'spreading.seedK', label: 'Seed count (K)', group: 'Spreading activation', type: ParamType.intType, def: 10, min: 1, max: 20),

  // ── U-Score gating (System 1 vs 2) ──────────────────────────
  ParamSpec(key: 'u.threshold', label: 'System-2 threshold (T_ERU)', group: 'U-Score gating', type: ParamType.doubleType, def: 0.65, min: 0.0, max: 1.0, help: 'Above this, escalate to deliberate reasoning.'),
  ParamSpec(key: 'u.wPrediction', label: 'Weight: prediction error', group: 'U-Score gating', type: ParamType.doubleType, def: 0.25, min: 0.0, max: 1.0),
  ParamSpec(key: 'u.wContradiction', label: 'Weight: contradiction', group: 'U-Score gating', type: ParamType.doubleType, def: 0.20, min: 0.0, max: 1.0),
  ParamSpec(key: 'u.wNovelty', label: 'Weight: novelty', group: 'U-Score gating', type: ParamType.doubleType, def: 0.15, min: 0.0, max: 1.0),
  ParamSpec(key: 'u.wAmbiguity', label: 'Weight: ambiguity', group: 'U-Score gating', type: ParamType.doubleType, def: 0.15, min: 0.0, max: 1.0),
  ParamSpec(key: 'u.wRisk', label: 'Weight: risk', group: 'U-Score gating', type: ParamType.doubleType, def: 0.25, min: 0.0, max: 1.0),

  // ── Convergence (bounded System 2) ──────────────────────────
  ParamSpec(key: 'conv.maxIterations', label: 'Max deliberation iters', group: 'Convergence', type: ParamType.intType, def: 3, min: 1, max: 10),
  ParamSpec(key: 'conv.targetU', label: 'Target U-score', group: 'Convergence', type: ParamType.doubleType, def: 0.35, min: 0.0, max: 1.0),

  // ── Memory decay (Ebbinghaus) ───────────────────────────────
  ParamSpec(key: 'decay.tauBaseCycles', label: 'Base decay (cycles)', group: 'Memory decay', type: ParamType.intType, def: 3600, min: 60, max: 100000),
  ParamSpec(key: 'decay.alpha', label: 'Reinforcement multiplier (α)', group: 'Memory decay', type: ParamType.doubleType, def: 2.0, min: 0.0, max: 10.0),
  ParamSpec(key: 'decay.beta', label: 'Asymptotic floor (β)', group: 'Memory decay', type: ParamType.doubleType, def: 1.0, min: 0.0, max: 10.0),
  ParamSpec(key: 'decay.applyEveryCycles', label: 'Apply every N cycles', group: 'Memory decay', type: ParamType.intType, def: 60, min: 1, max: 1000),

  // ── Contradiction resolution (Dempster-Shafer) ──────────────
  ParamSpec(key: 'ds.lambda', label: 'Chain decay (λ)', group: 'Contradiction resolution', type: ParamType.doubleType, def: 0.3, min: 0.0, max: 2.0),
  ParamSpec(key: 'ds.thetaDominance', label: 'Dominance ratio (θ)', group: 'Contradiction resolution', type: ParamType.doubleType, def: 2.0, min: 1.0, max: 10.0),
  ParamSpec(key: 'ds.gamma', label: 'Suspension rate (γ)', group: 'Contradiction resolution', type: ParamType.doubleType, def: 0.5, min: 0.0, max: 1.0),
  ParamSpec(key: 'ds.maxIterations', label: 'Suspension max iters', group: 'Contradiction resolution', type: ParamType.intType, def: 50, min: 1, max: 500),

  // ── Competence & axioms ─────────────────────────────────────
  ParamSpec(key: 'axiom.threshold', label: 'Axiom confidence gate', group: 'Competence & axioms', type: ParamType.doubleType, def: 0.99, min: 0.5, max: 1.0),
  ParamSpec(key: 'comp.priorDefault', label: 'Competence prior', group: 'Competence & axioms', type: ParamType.doubleType, def: 0.5, min: 0.0, max: 1.0),
  ParamSpec(key: 'comp.fewSampleN', label: 'Few-sample penalty N', group: 'Competence & axioms', type: ParamType.intType, def: 10, min: 1, max: 100),

  // ── Grounding & anti-deception ──────────────────────────────
  ParamSpec(key: 'verify.epsilon', label: 'Self-change threshold (ε)', group: 'Grounding & verification', type: ParamType.doubleType, def: 0.1, min: 0.0, max: 1.0),
  ParamSpec(key: 'verify.miRatio', label: 'Behavior-coherence ratio', group: 'Grounding & verification', type: ParamType.doubleType, def: 0.5, min: 0.0, max: 1.0),
  ParamSpec(key: 'falsify.durationFactor', label: 'Falsifiability slack', group: 'Grounding & verification', type: ParamType.doubleType, def: 1.5, min: 1.0, max: 5.0),
  ParamSpec(key: 'ground.sensorsEnabled', label: 'Sensor grounding enabled', group: 'Grounding & verification', type: ParamType.boolType, def: false, help: 'Attach GPS/time/device state to events (needs permission).'),

  // ── Event log (grounded history) ────────────────────────────
  ParamSpec(key: 'events.enabled', label: 'Record event log', group: 'Event log', type: ParamType.boolType, def: true, help: 'Append-only, sensor-anchored log of what actually happened.'),
  ParamSpec(key: 'events.maxDisplay', label: 'Events shown in panel', group: 'Event log', type: ParamType.intType, def: 100, min: 10, max: 1000),

  // ── Idle autonomous loop ────────────────────────────────────
  ParamSpec(key: 'idle.enabled', label: 'Background introspection', group: 'Idle loop', type: ParamType.boolType, def: false),
  ParamSpec(key: 'idle.intervalMinutes', label: 'Check interval (min)', group: 'Idle loop', type: ParamType.intType, def: 10, min: 1, max: 120),
  ParamSpec(key: 'idle.requiresCharging', label: 'Only while charging', group: 'Idle loop', type: ParamType.boolType, def: true),
];
