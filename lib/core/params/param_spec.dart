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
  ParamSpec(key: 'gen.temperature', label: 'Temperature', group: 'Generation', type: ParamType.doubleType, def: 0.7, min: 0.0, max: 2.0, help: 'Sampling randomness. Lower (0.2–0.5) = focused, repeatable, more factual; higher (0.8–1.2) = creative, varied, more prone to drift. 0 is greedy (always the top token).'),
  ParamSpec(key: 'gen.topP', label: 'Top-P (nucleus)', group: 'Generation', type: ParamType.doubleType, def: 0.9, min: 0.0, max: 1.0, help: 'Only sample from the smallest set of tokens whose probabilities add up to P. 0.9 keeps the likely 90% and drops the long tail of unlikely words. Lower = safer/tighter, higher (→1.0) = allows rarer words.'),
  ParamSpec(key: 'gen.topK', label: 'Top-K', group: 'Generation', type: ParamType.intType, def: 40, min: 0, max: 200, help: 'Only consider the K most likely next tokens at each step. 40 is a good default; lower = more focused, higher = more variety. 0 disables the K cap (Top-P alone decides).'),
  ParamSpec(key: 'gen.repeatPenalty', label: 'Repeat penalty', group: 'Generation', type: ParamType.doubleType, def: 1.1, min: 0.5, max: 2.0, help: 'Down-weights tokens that already appeared, to curb loops and repetition. 1.0 = off; 1.1 is mild; above ~1.3 can start distorting normal phrasing.'),
  ParamSpec(key: 'gen.maxTokens', label: 'Output budget (max reply tokens)', group: 'Generation', type: ParamType.intType, def: 512, min: 16, max: 8192, help: 'Ceiling on a reply\'s length. The model still stops early at its own end-of-turn; this only caps runaway/looping. On slow on-device inference (~1 tok/s) output length IS the wait — lower it for short, fast replies; raise it for long-form (essays, code).'),

  // ── Recall (associative recall engine) ──────────────────────
  ParamSpec(key: 'recall.k', label: 'Max memories injected (k)', group: 'Recall', type: ParamType.intType, def: 8, min: 0, max: 30, help: 'Upper bound on memories injected per turn (0 disables recall).'),
  ParamSpec(key: 'recall.memoryAwareness', label: 'Tell model it has memory', group: 'Recall', type: ParamType.boolType, def: true, help: 'Inject a one-line note so the model relies on memory instead of guessing. Off = pure blank slate.'),
  ParamSpec(key: 'recall.charBudget', label: 'Injection budget (chars)', group: 'Recall', type: ParamType.intType, def: 600, min: 0, max: 4000, help: 'Character cap on injected memory (protects the small context window).'),
  ParamSpec(key: 'recall.episodicDepth', label: 'Episodic search depth', group: 'Recall', type: ParamType.intType, def: 12, min: 0, max: 100, help: 'How many raw episodic turns to consider as recall candidates.'),
  ParamSpec(key: 'recall.injectConsolidatedEpisodic', label: 'Re-inject consolidated turns', group: 'Recall', type: ParamType.boolType, def: false, help: 'Off (default): once a turn is folded into a clean semantic claim, recall uses that claim rather than re-injecting the raw turn — avoids redundancy and stops the turn\'s original second-person wording ("my girlfriend") leaking back into context. On: also inject the verbatim raw turn, for exact-wording recall.'),
  // ── Belief combination (Phase 4b — Dempster–Shafer) ──────────
  ParamSpec(key: 'ds.enabled', label: 'Auto-resolve conflicts', group: 'Belief', type: ParamType.boolType, def: true, help: 'When two claims pin one slot to different values, fuse their confidences (Dempster–Shafer) and auto-keep a clear winner. Off = always ask you instead (the 2.0 behaviour).'),
  ParamSpec(key: 'ds.minTopBelief', label: 'Min winning belief', group: 'Belief', type: ParamType.doubleType, def: 0.5, min: 0.0, max: 1.0, help: 'The fused belief the leading value must reach before the agent resolves on its own. Lower = resolves more readily; higher = asks more.'),
  ParamSpec(key: 'ds.minMargin', label: 'Min lead over runner-up', group: 'Belief', type: ParamType.doubleType, def: 0.2, min: 0.0, max: 1.0, help: 'How far ahead the winning value must be before auto-resolving. A close call falls back to asking you.'),
  ParamSpec(key: 'ds.maxConflict', label: 'Max conflict to resolve', group: 'Belief', type: ParamType.doubleType, def: 0.6, min: 0.0, max: 1.0, help: 'If the evidence disagrees more than this (Dempster conflict mass K), the agent always asks rather than guessing.'),
  ParamSpec(key: 'recall.wRelevance', label: 'Weight: relevance', group: 'Recall', type: ParamType.doubleType, def: 0.6, min: 0.0, max: 1.0, help: 'How much a memory\'s match to the current topic drives its ranking. The three weights (relevance + salience + recency) are the recall scoring mix — raise this to favour on-topic memories.'),
  ParamSpec(key: 'recall.wSalience', label: 'Weight: salience', group: 'Recall', type: ParamType.doubleType, def: 0.25, min: 0.0, max: 1.0, help: 'How much a memory\'s importance (curated facts score high, raw turns low) drives its ranking. Raise to favour durable facts over passing chatter.'),
  ParamSpec(key: 'recall.wRecency', label: 'Weight: recency', group: 'Recall', type: ParamType.doubleType, def: 0.15, min: 0.0, max: 1.0, help: 'How much "how recently it happened" drives ranking. Raise to lean toward the latest context, lower to treat old and new memories equally.'),
  ParamSpec(key: 'recall.recencyHalfLifeHours', label: 'Recency half-life (h)', group: 'Recall', type: ParamType.doubleType, def: 72.0, min: 1.0, max: 8760.0, help: 'How fast the recency bonus fades: a memory this many hours old counts half as "recent". 72h = a few days; smaller = sharply favour today, larger = recency barely matters.'),
  ParamSpec(key: 'recall.minTokenLen', label: 'Min keyword length', group: 'Recall', type: ParamType.intType, def: 3, min: 1, max: 8, help: 'Shortest word length used as a search keyword, so tiny filler words ("a", "to", "is") don\'t drive recall. 3 drops most stop-words; raise to be stricter.'),

  // ── Embeddings (meaning-based recall, Phase 2b) ─────────────
  ParamSpec(key: 'embeddings.seedK', label: 'Embedding seeds (K)', group: 'Embeddings', type: ParamType.intType, def: 10, min: 1, max: 40, help: 'How many nearest claims by meaning seed recall (in addition to keyword hits).'),
  ParamSpec(key: 'embeddings.threshold', label: 'Similarity floor', group: 'Embeddings', type: ParamType.doubleType, def: 0.3, min: 0.0, max: 1.0, help: 'Minimum cosine similarity for a claim to seed recall.'),
  ParamSpec(key: 'embeddings.backfillPerPass', label: 'Backfill per pass', group: 'Embeddings', type: ParamType.intType, def: 16, min: 0, max: 200, help: 'Existing claims embedded per consolidation pass until all are indexed.'),

  // ── Consolidation gate (episodic → semantic) ────────────────
  ParamSpec(key: 'consolidate.minEntries', label: 'Min pending to run', group: 'Consolidation', type: ParamType.intType, def: 6, min: 1, max: 50, help: 'How many new raw turns must pile up before the model runs a curation pass (episodic → semantic facts). Below this, nothing runs — 0% compute. Lower = consolidate sooner/more often; higher = batch more per pass.'),
  ParamSpec(key: 'consolidate.maxEntriesPerPass', label: 'Max entries per pass', group: 'Consolidation', type: ParamType.intType, def: 40, min: 5, max: 200, help: 'Most raw turns fed to the curator model in one pass. Higher sees more context per pass but makes each pass slower and uses more of the context window.'),
  ParamSpec(key: 'consolidate.maxFactsPerPass', label: 'Max facts per pass', group: 'Consolidation', type: ParamType.intType, def: 12, min: 1, max: 50, help: 'Cap on how many new facts one consolidation can promote, so a single pass can\'t flood long-term memory.'),
  ParamSpec(key: 'consolidate.temperature', label: 'Curator temperature', group: 'Consolidation', type: ParamType.doubleType, def: 0.2, min: 0.0, max: 1.5, help: 'Sampling randomness for the fact-extraction model. Kept low (0.2) so curation is precise and literal rather than creative — raising it risks invented or loose "facts".'),
  ParamSpec(key: 'consolidate.minFactLen', label: 'Min fact length', group: 'Consolidation', type: ParamType.intType, def: 8, min: 1, max: 100, help: 'Shortest allowed stored fact (characters). Filters out fragments too short to be meaningful memories.'),
  ParamSpec(key: 'consolidate.maxFactLen', label: 'Max fact length', group: 'Consolidation', type: ParamType.intType, def: 500, min: 50, max: 2000, help: 'Longest allowed stored fact (characters). Keeps facts atomic and short instead of storing whole paragraphs.'),

  // ── Self-curation (2.0 — contradiction + self-reflection) ────
  ParamSpec(key: 'reconcile.enabled', label: 'Notice contradictions', group: 'Self-curation', type: ParamType.boolType, def: true, help: 'Let the agent detect when two of its memories about the same thing disagree (e.g. two different names for your partner), and either accept your correction ("actually it\'s…") by superseding the old value, or raise it as a question to ask you — instead of silently holding both. Off = conflicting facts are kept without flagging.'),
  ParamSpec(key: 'reflect.enabled', label: 'Self-reflection', group: 'Self-curation', type: ParamType.boolType, def: true, help: 'Let the agent occasionally form its own tentative, humble observations about itself from how it has actually behaved ("I seem to ask a lot of questions"). Grounded in the real log, stored low-confidence, and it fades unless it keeps proving true. Off = the agent forms no self-view. Consistent with blank identity: a self earned from evidence, never a scripted persona.'),
  ParamSpec(key: 'reflect.everyConsolidations', label: 'Reflect every N consolidations', group: 'Self-curation', type: ParamType.intType, def: 3, min: 1, max: 50, help: 'How often self-reflection runs, counted in consolidation passes. Higher = rarer (less background model work); 1 = after every consolidation. Runs only while the chat model is idle.'),

  // ── Spreading activation (graph recall) ─────────────────────
  ParamSpec(key: 'spreading.alpha', label: 'Decay factor (α)', group: 'Spreading activation', type: ParamType.doubleType, def: 0.85, min: 0.0, max: 1.0, help: 'When recall "spreads" from a matched fact to its linked facts, each hop keeps this fraction of the activation. 0.85 lets related facts come along strongly; lower = recall stays tight to direct matches.'),
  ParamSpec(key: 'spreading.threshold', label: 'Activation floor', group: 'Spreading activation', type: ParamType.doubleType, def: 0.15, min: 0.0, max: 1.0, help: 'A linked fact must reach at least this activation to be recalled. Higher = only strongly-connected facts ride along; lower = recall reaches further through the graph.'),
  ParamSpec(key: 'spreading.maxHops', label: 'Max hops', group: 'Spreading activation', type: ParamType.intType, def: 2, min: 1, max: 4, help: 'How many relationship links recall can travel from a matched fact. 2 = facts and their neighbours\' neighbours. More hops = broader, looser associations and a bit more work per recall.'),
  ParamSpec(key: 'spreading.seedK', label: 'Seed count (K)', group: 'Spreading activation', type: ParamType.intType, def: 10, min: 1, max: 20, help: 'How many top matching facts start the spreading-activation walk. More seeds cast a wider net before spreading.'),

  // ── U-Score gating (System 1 vs 2) ──────────────────────────
  ParamSpec(key: 'u.enabled', label: 'Uncertainty gating on', group: 'U-Score gating', type: ParamType.boolType, def: true, help: 'Master switch for System 1/2 gating (Phase 4): each turn is scored for uncertainty, and an uncertain one gets a single-pass "careful mode" (reason step by step, lean on memory, admit when unknown). No extra inference — just a posture change. Off = every turn answered on the fast path.'),
  ParamSpec(key: 'u.threshold', label: 'System-2 threshold (T_ERU)', group: 'U-Score gating', type: ParamType.doubleType, def: 0.65, min: 0.0, max: 1.0, help: 'Uncertainty cut-off for switching from fast intuitive answers (System 1) to careful deliberate reasoning (System 2). When the combined uncertainty score (U) reaches this, the turn "thinks harder". Lower = deliberates more often (more cautious); higher = trusts the fast path more. Watch the live U readout in the status strip to tune it.'),
  ParamSpec(key: 'u.wPrediction', label: 'Weight: prediction error', group: 'U-Score gating', type: ParamType.doubleType, def: 0.25, min: 0.0, max: 1.0, help: 'How much "the input surprised me vs what memory predicted" contributes to U. Grounded from how strongly recall matched this turn. One of five weights blended into U (weight-normalized — they need not sum to 1).'),
  ParamSpec(key: 'u.wContradiction', label: 'Weight: contradiction', group: 'U-Score gating', type: ParamType.doubleType, def: 0.20, min: 0.0, max: 1.0, help: 'How much "this conflicts with what I already hold" raises U. Driven by recalled claims flagged as in an unresolved contradiction — lights up fully once the contradiction-resolution engine (Contradiction resolution group) lands.'),
  ParamSpec(key: 'u.wNovelty', label: 'Weight: novelty', group: 'U-Score gating', type: ParamType.doubleType, def: 0.15, min: 0.0, max: 1.0, help: 'How much "I know little about this topic" raises U. Grounded from how few memories recall found for the query.'),
  ParamSpec(key: 'u.wAmbiguity', label: 'Weight: ambiguity', group: 'U-Score gating', type: ParamType.doubleType, def: 0.15, min: 0.0, max: 1.0, help: 'How much "this could mean several things" raises U. Coarse first pass: estimated from how terse/underspecified the query is (a richer signal comes later).'),
  ParamSpec(key: 'u.wRisk', label: 'Weight: risk', group: 'U-Score gating', type: ParamType.doubleType, def: 0.25, min: 0.0, max: 1.0, help: 'How much "getting this wrong would be costly" raises U, pushing toward careful reasoning on high-stakes inputs. Coarse first pass: a small high-stakes keyword scan (not a safety guarantee) — it only nudges toward more care.'),

  // ── Convergence (bounded System 2) ──────────────────────────
  // NOTE: Phase 4a ships single-pass System-2 (a careful-mode posture). These
  // two knobs govern the MULTI-ROUND convergence loop (re-reason until U drops
  // or the iteration cap is hit), which needs repeated generation and lands in
  // a later increment — so they are defined but not yet active.
  ParamSpec(key: 'conv.maxIterations', label: 'Max deliberation iters', group: 'Convergence', type: ParamType.intType, def: 3, min: 1, max: 10, help: 'When multi-round deliberate reasoning (System 2) kicks in, the hard cap on reasoning rounds before it must answer — so "thinking harder" can\'t loop forever on a slow device. [Upcoming: multi-round System 2.]'),
  ParamSpec(key: 'conv.targetU', label: 'Target U-score', group: 'Convergence', type: ParamType.doubleType, def: 0.35, min: 0.0, max: 1.0, help: 'Multi-round deliberation stops early once uncertainty drops below this — "I\'m confident enough now". Lower = keeps reasoning until very sure (slower); higher = settles sooner. [Upcoming: multi-round System 2.]'),

  // ── Memory decay (Ebbinghaus) ───────────────────────────────
  ParamSpec(key: 'decay.enabled', label: 'Adaptive memory on', group: 'Memory decay', type: ParamType.boolType, def: true, help: 'Master switch for adaptable memory (Phase 3): recalled memories strengthen, unused ones slowly fade toward a permanence floor, so recall tracks what you actually use. Off = every memory keeps the strength it was stored with (no decay, no reinforcement).'),
  ParamSpec(key: 'decay.tauBaseCycles', label: 'Base forgetting rate (cycles)', group: 'Memory decay', type: ParamType.intType, def: 3600, min: 60, max: 100000, help: 'How long an un-reinforced memory takes to fade (Ebbinghaus forgetting curve), counted in turns: after ~this many turns without a recall, a memory loses ~63% of the strength above its floor. Larger = memories linger longer; smaller = forgets faster unless refreshed. This is where "adaptable memory" lives.'),
  ParamSpec(key: 'decay.alpha', label: 'Reinforcement strength (α)', group: 'Memory decay', type: ParamType.doubleType, def: 2.0, min: 0.0, max: 10.0, help: 'How much each recall strengthens a memory (retrieval practice): salience jumps a fraction of the way to full, and a little confidence accrues so repeatedly-useful memories become "core". Higher = used memories stick hard (spaced-repetition effect); 0 = recall doesn\'t reinforce at all.'),
  ParamSpec(key: 'decay.beta', label: 'Permanence floor (β)', group: 'Memory decay', type: ParamType.doubleType, def: 1.0, min: 0.0, max: 10.0, help: 'The minimum strength a memory settles toward instead of ever fully disappearing, scaled by its confidence — how "permanent" core memories become. 0 = everything can fade to nothing (pure Ebbinghaus); high = confident, well-used memories stop decaying entirely.'),
  ParamSpec(key: 'decay.applyEveryCycles', label: 'Recompute every N turns', group: 'Memory decay', type: ParamType.intType, def: 60, min: 1, max: 1000, help: 'How often the forgetting sweep runs, in turns. Less often = cheaper but coarser; more often = finer-grained forgetting at a little more background work. Reinforcement on recall is immediate regardless of this.'),

  // ── Contradiction resolution (Dempster-Shafer) ──────────────
  ParamSpec(key: 'ds.lambda', label: 'Evidence chain decay (λ)', group: 'Contradiction resolution', type: ParamType.doubleType, def: 0.3, min: 0.0, max: 2.0, help: 'When two memories conflict, belief is combined (Dempster–Shafer) along their evidence chains; this sets how fast older evidence loses pull. Higher = recent evidence dominates; lower = long histories still count. [Upcoming: Phase 4.]'),
  ParamSpec(key: 'ds.thetaDominance', label: 'Winner ratio (θ)', group: 'Contradiction resolution', type: ParamType.doubleType, def: 2.0, min: 1.0, max: 10.0, help: 'How much more belief one side of a contradiction needs before it simply wins and overrides the other. 2.0 = twice as supported. Higher = slower to pick a winner (holds both longer). [Upcoming: Phase 4.]'),
  ParamSpec(key: 'ds.gamma', label: 'Hold-in-tension rate (γ)', group: 'Contradiction resolution', type: ParamType.doubleType, def: 0.5, min: 0.0, max: 1.0, help: 'When neither side clearly wins, how readily the pair is marked "unresolved / both held" rather than forced to a decision. [Upcoming: Phase 4.]'),
  ParamSpec(key: 'ds.maxIterations', label: 'Resolution max iters', group: 'Contradiction resolution', type: ParamType.intType, def: 50, min: 1, max: 500, help: 'Safety cap on the belief-combination loop when resolving a web of conflicting memories, so it always terminates. [Upcoming: Phase 4.]'),

  // ── Competence & axioms ─────────────────────────────────────
  ParamSpec(key: 'axiom.threshold', label: 'Axiom confidence gate', group: 'Competence & axioms', type: ParamType.doubleType, def: 0.99, min: 0.5, max: 1.0, help: 'Confidence a belief must reach to be treated as a near-certain "axiom" the model won\'t casually revise. Set very high (0.99) so only rock-solid facts earn that status. [Upcoming: Phase 4.]'),
  ParamSpec(key: 'comp.priorDefault', label: 'Starting competence', group: 'Competence & axioms', type: ParamType.doubleType, def: 0.5, min: 0.0, max: 1.0, help: 'How much the model trusts itself in a brand-new topic before it has evidence either way. 0.5 = neutral. Lower = more humble/cautious on unfamiliar ground. [Upcoming: Phase 4.]'),
  ParamSpec(key: 'comp.fewSampleN', label: 'Experience needed (N)', group: 'Competence & axioms', type: ParamType.intType, def: 10, min: 1, max: 100, help: 'How many examples in a domain are needed before the model stops discounting its own competence there as "too little experience to be sure". [Upcoming: Phase 4.]'),

  // ── Grounding & anti-deception ──────────────────────────────
  ParamSpec(key: 'verify.epsilon', label: 'Max self-change per step (ε)', group: 'Grounding & verification', type: ParamType.doubleType, def: 0.1, min: 0.0, max: 1.0, help: 'How much the model is allowed to shift its own beliefs/behaviour in a single update, so it adapts gradually instead of lurching. Lower = more stable and conservative; higher = changes its mind faster. [Upcoming: Phase 5.]'),
  ParamSpec(key: 'verify.miRatio', label: 'Say-vs-do coherence', group: 'Grounding & verification', type: ParamType.doubleType, def: 0.5, min: 0.0, max: 1.0, help: 'Minimum agreement required between what the model states and what its actions/memory actually show — an anti-self-deception check. Higher = stricter about matching words to behaviour. [Upcoming: Phase 5.]'),
  ParamSpec(key: 'falsify.durationFactor', label: 'Claim-testing slack', group: 'Grounding & verification', type: ParamType.doubleType, def: 1.5, min: 1.0, max: 5.0, help: 'How much extra time/evidence a claim gets before it must be confirmed or dropped — breathing room so testable claims are actually tested, not prematurely trusted. [Upcoming: Phase 5.]'),
  ParamSpec(key: 'ground.sensorsEnabled', label: 'Sensor grounding enabled', group: 'Grounding & verification', type: ParamType.boolType, def: false, help: 'Attach real GPS / time / device state to each event so memories are anchored to what actually happened and when (needs location permission). Off = events are still timestamped, just not location/sensor grounded.'),

  // ── Event log (grounded history) ────────────────────────────
  ParamSpec(key: 'events.enabled', label: 'Record event log', group: 'Event log', type: ParamType.boolType, def: true, help: 'Keep an append-only, time-anchored log of what actually happened (launches, turns, consolidations). This is the ground truth the memory is built on — turning it off blinds the grounded-history and provenance features.'),
  ParamSpec(key: 'events.maxDisplay', label: 'Events shown in panel', group: 'Event log', type: ParamType.intType, def: 100, min: 10, max: 1000, help: 'How many recent events the Memory panel\'s Events tab lists. Display only — it does not delete anything from the log.'),

  // ── Idle autonomous loop ────────────────────────────────────
  ParamSpec(key: 'idle.enabled', label: 'Background introspection', group: 'Idle loop', type: ParamType.boolType, def: false, help: 'Let the app quietly consolidate and tidy memory on its own while idle, instead of only during chat. Off by default (0% background compute). On = the memory keeps maturing between sessions, at some battery cost. [Upcoming: Phase 5.]'),
  ParamSpec(key: 'idle.intervalMinutes', label: 'Check interval (min)', group: 'Idle loop', type: ParamType.intType, def: 10, min: 1, max: 120, help: 'How often the idle loop wakes to check whether there\'s memory work worth doing. Longer = rarer wake-ups, lighter on battery. Each check first does a cheap no-inference test and only wakes the model if there\'s genuinely something to do. [Upcoming: Phase 5.]'),
  ParamSpec(key: 'idle.requiresCharging', label: 'Only while charging', group: 'Idle loop', type: ParamType.boolType, def: true, help: 'Restrict background introspection to when the phone is plugged in, so it never spends battery you need during the day. [Upcoming: Phase 5.]'),
];
