# AETHER — Cognitive Runtime (Flutter port) — Canonical Build Spec

Status: Phase 2a landed (graph + spreading activation); Associative Recall Engine landed (hybrid episodic+semantic fusion — §4a); Phase 2b landed (embedding helper model + cosine-seeded recall, opt-in — §5); Phase 3 adaptive dynamics landed (Ebbinghaus decay + recall reinforcement, §4b); Phase 4a uncertainty gating landed (U-score + single-pass System 1/2, §4c); Phase 5a identity/attribution landed (subject·holder claims + identity-safe injection, §4d); **2.0 "Living Memory" landed** — active contradiction detection + open-questions the agent voices, correction/supersession, and grounded self-reflection (§4e). Next: the on-device Autopilot self-test harness, then the Tier-1 recall batch (adaptive scoring, two-pass extraction, verbatim anchors) and PPR. This is the single reference we execute from.

AETHER is **not a new model**. It is a runtime layer wrapping an off-the-shelf
local GGUF model (via `llamadart`, in-process) that adds persistent memory, a
self-authored identity, and reality grounding. Ported from the AETHER v2
whitepaper (which targeted Python/Termux + a `llama.cpp` HTTP server) into this
Flutter/Dart app, running inference **in-process** — no Python, no Termux, no
`localhost:8000`.

## 0. Constitution (non-negotiables)
- **Blank identity, grounded capability.** No forced persona/defaults; it becomes itself from memory.
- **Growth via memory + self-model, never weights.** LoRA is parked (wrong hardware; risks model collapse).
- **Reuse the existing stack:** `llamadart`, `sqflite` (SQLite/WAL), GetX, the Memory panel.
- **Heavy cognition runs async/idle**, never in the chat path. Compute budget is real (~1 tok/s on a 4B–7B GGUF).
- **Grounding beats coherence.** The self-model can never revise away sensor truth.
- **Everything is adjustable.** Every tunable lives in `lib/core/params/param_spec.dart` and appears in the Parameters panel automatically.
- **Adaptive by construction.** Memory is meant to tune *itself* with use — salience rising/falling with reinforcement and decay, recall weights learned from what actually got used, consolidation improving at the relations it extracts. Hand-set constants (recall weights, the flat episodic salience, the context default) are placeholders for values the system should eventually adapt. Quality is the aim, invention the driver, optimization the thrust.
- **Context is the user's, safe by default.** Default 4096 — a large jump over the old 1024 cap that still loads broadly. The user raises it toward the model's ceiling (`contextSize: 0` → `llama_model_n_ctx_train`) once their device proves it handles the KV-cache, or lowers it further. On CPU the KV-cache lives entirely in RAM and scales linearly with context, so auto-max can OOM at load — never a tiny fixed cap, but never a reckless default either. The control is front-and-centre in Settings, not buried.
- **One engine, prioritised.** A single model in RAM serves everything, so a live user turn preempts background introspection (the `InferenceWorker` yields the engine); heavy System-2 work defers to idle.
- **Honest frame:** a functional cognitive architecture, not an awakening. Hard mechanisms ship as labeled proxies first.

## 1. Runtime substrate mapping (whitepaper Python → our Dart)
| Whitepaper | Our port |
|---|---|
| `llama_cpp.server` on `localhost:8000` | `llamadart` in-process (no server) |
| async event bus (`bus.py`) | Dart streams + `InferenceWorker` queue |
| SQLite WAL (`aether.db`) | `sqflite` + `PRAGMA journal_mode=WAL` |
| numpy / MI math | Dart; MI is a **proxy** (§3) |
| HNSW vector index | brute-force cosine at our scale + embedding helper model |
| BM25 lexical | SQLite `FTS5` |
| GPS/accel/time sensors | `geolocator`, `sensors_plus`, `battery_plus`, `device_info_plus` |

## 2. Data layers (all in the existing SQLite DB)
1. **Event Log** — append-only (`event_log`, live as of Phase 1): `id, ts, source, type, payload_json, parent_events_json, sensor_state_json` (+ `session_id`, `monotonic_ms`). WAL, never updated/deleted in normal operation. Runs *alongside* `episodic_log` (the grounded spine over the summarisable ledger), not as a replacement.
2. **Epistemic Graph** — `claim_nodes` (`proposition, confidence, salience, status[ACTIVE|SUPERSEDED|AMBIGUOUS], supersedes`) + `provenance` (claim→event) + `relation_edges` (`SUPPORTS|CONTRADICTS|CAUSES|PART_OF`, weight). Upgrades `semantic_facts` into a graph.
3. **Self-Schema** — `identity/goals/lessons` (starts empty) + `domain_capability` (`success/fail → empirical_confidence`).
4. **Grounding** — `SensorAnchor` snapshot on every event; `FalsifiabilityVerifier`; `BehaviorVerifier`.

## 3. Mechanisms + fidelity
- **Spreading activation** (α, threshold, ≤2 hops, seed ≤10): full.
- **Ebbinghaus decay + reconsolidation** (`S(t)=S₀·e^(−t/τ(R))`; recall bumps reinforcement): full, on the idle cycle.
- **U-score gating** (`P,C,N,A,R` weights, `T_ERU`): contradiction/novelty/ambiguity/risk full; **prediction-error "surprise" = proxy** (llamadart likely won't expose logprobs).
- **System 2 as a mode** (not a 2nd model): bounded deliberation (`conv.maxIterations`, `conv.targetU`).
- **Mutation validator** (schema + provenance + axiom gate): full, reuses the GBNF grammar.
- **Dempster-Shafer / mutual suspension** (`λ, θ, γ`): full mechanism + divergence guard (whitepaper §10.1: convergence unproven).
- **Domain-distance competence**: full once embeddings land.
- **Behavior Verifier `I(ΔS;ΔB)`**: **proxy first** (coarse correlation, not true MI — whitepaper §10.3).
- **Sensor grounding + falsifiability**: full — the anti-self-deception core.

## 4. Executive loop (ported into the chat path)
`sendMessage`: snapshot sensors → append event → spreading-activation recall → U-score → **System 1** (fast) or **System 2** (bounded deliberation) → behavior-verify → episodic write → idle consolidation later. Fits the existing `ChatController` / `LlmService` / `InferenceWorker`.

## 4a. Associative Recall Engine (System 1 — involuntary recall) — DONE

The question this answers: *what starts the search for a past memory, and what governs what surfaces?* The answer is that recall is **not a tool the model chooses to call** — it is involuntary and runs on **every** turn, before the model generates, the way a smell pulls up a memory whether or not you asked for it. The model never has to "know" to search; the runtime always does.

**The cue.** Each turn builds a recall cue = the current user message **+ a compact digest of the last few turns** (`_recentContextCue` in `ChatController`, budget-capped). This is why the conversation can drift to something unrelated and still pull the right thread: the cue carries what the conversation is *about*, not just the last sentence.

**Fusion across tiers.** `MemoryService.remembering` gathers candidates from every memory tier and fuses them (`recall_ranker.dart`, pure + unit-tested):
- **Semantic** — the cue seeds **spreading activation** over the claim graph (§2, layer 2), so a claim related through an edge (a dog → its vet → an appointment) surfaces even with zero lexical overlap. Each candidate keeps its activation score as `relevance` (`recallSemanticScored`).
- **Episodic** — keyword search over the raw cross-session log (`searchEpisodic`), so something said in a *different chat weeks ago*, or earlier in this chat but fallen out of the 1024-token window, can still return. `relevance` = fraction of cue tokens present.
- (**Working** tier plugs into the same `RecallCandidate` list when needed.)

**Ranking + gating.** Candidates are deduped across tiers (same content, keep the strongest match), then scored `wRelevance·relevance + wSalience·salience + wRecency·e^(−age/halfLife)` — so recall is a blend of *how well it matches*, *how important the claim is*, and *how recent it is*, not any one axis. Sorted descending, then admitted greedily until a **character budget** is spent (the context window is tiny — injection must never blow it). All weights, the budget, half-life, episodic depth and `k` are live `recall.*` parameters.

**Awareness (configurable, not forced).** When `recall.memoryAwareness` is on (default), a one-line note tells the model it *has* a persistent memory and should rely on it rather than confabulate, and the injected block is framed as "things you actually know." Turned off, recall still runs but injects a bare "Relevant memory:" block with no capability claim — consistent with the blank-identity constitution (§0): the switch exists precisely so nothing is forced.

**Why fusion beats the previous design.** Before this, recall searched *only* curated semantic claims — which are written only by the gated consolidation pass, which only fires after enough episodic turns accumulate. So a fact stated once, in a short chat, was never recalled: it hadn't been consolidated yet, and recall never looked at the raw log. The episodic tier in the fusion closes that gap — raw turns are recallable immediately, and consolidation later distils the durable ones into high-salience claims.

**Deliberately rejected / deferred here:** cryptic micro-syntax injection (unreadable to a 4B model — density without comprehension is a loss). Embedding-based (meaning) seeding plugs into this exact pipeline in 2b — it only changes how the semantic tier is *seeded* (cosine instead of keyword), not the fusion/ranking spine.

> **Reversal (Phase 3).** An earlier draft deferred recall-reinforcement *out* of this System-1 pass, fearing "memory-locking" (hot memories ratcheting up and drowning recall). Phase 3 (§4b) puts it back in, and the fear turns out not to apply here: the ranker weights **relevance at 60 % and salience at only 25 %**, so relevance *gates* what is even considered and salience only breaks ties *among already-relevant* candidates. A no-longer-relevant memory cannot force itself into recall no matter how high its salience — so reinforcing on recall can't produce the runaway. With continuous decay as the counterforce, diminishing-returns reinforcement, and the whole mechanism gated behind `decay.enabled` (and `decay.alpha = 0` as an off switch), the equilibrium is exactly the intended one: *memories used more often than they decay stay strong; the rest fade.*

## 4b. Adaptive memory dynamics (Phase 3 — LANDED)

Memory now tunes its own strengths with use — the core of "adaptable memory" (§0). A **two-strength model** (after Bjork's *new theory of disuse*), realized on the two numbers each claim already persists, so **no schema change** was needed:

- **salience = retrieval strength** (fast). Jumps when a claim is recalled; relaxes toward a floor when it isn't. This is the 25 % term the ranker blends (§4a), so moving it genuinely changes what surfaces next.
- **confidence = storage strength** (slow, near-monotonic). Each recall nudges it up a little; it sets the permanence floor salience can never decay below. A claim that keeps earning its place quietly becomes "core" and stops fading.

The math lives in one pure, unit-tested file (`memory_dynamics.dart`) — every function clamps to [0,1] so no setting of the knobs can drive a strength out of range:
- `decayedSalience`: `s' = floor + (s − floor)·e^(−Δcycles/τ)` — Ebbinghaus relaxation toward `floor`, never below it.
- `reinforcedSalience`: `s' = s + (α·0.04)·(1 − s)` — diminishing-returns bump toward 1.0 (saturates, never pegs).
- `reinforcedConfidence`: `c' = c + (α·0.01)·(1 − c)` — a quarter-rate accrual, so permanence takes sustained use to build.
- `permanenceFloor`: `(β·0.1)·confidence` — at β=0 nothing is permanent; at high β a confident claim stops decaying at all.

**Wiring (all off the turn's critical path).** Reinforcement fires in `MemoryService.remembering` on exactly the claims a recall *injected* (a retrieval event strengthens memory — the testing effect), `unawaited` so it never adds latency. Decay is batched: a turn counter in `rememberTurn` fires one `decayAllSalience` sweep every `decay.applyEveryCycles` turns (default 60), also `unawaited`. Both are fast local batch `UPDATE`s — no model, no GPU — and both are logged to the Memory panel's Activity feed ("reinforced N recalled memories", "decay sweep · faded N memories") so the adaptation is visible, not hidden. The store applies the pure curves row-by-row in Dart (SQLite has no `exp()`); at on-device scale (hundreds–low thousands of claims) a sweep is a few ms. The turn counter is in-memory (resets on relaunch — a documented Phase-3a simplification; a persisted last-sweep marker would remove even that under-application).

**Safety / escape hatch.** The whole mechanism is gated behind `decay.enabled` (default on); `decay.alpha = 0` disables reinforcement while leaving pure decay; superseded claims are skipped. Consistent with the blank-identity constitution (§0): adaptive, but switch-off-able. See the §4a reversal note for why reinforcing on System-1 recall is safe here.

**Deferred to a later pass:** wall-clock decay (vs turn-cycle), a persisted sweep marker, and feeding reinforcement signal into the recall *weights* themselves (learned `recall.*`, per §0's "adaptive by construction").

## 4c. Uncertainty gating — System 1 / System 2 (Phase 4a — LANDED)

Not every turn deserves the same effort. A **U-score** (0..1) scores how uncertain the system is about a turn; when it clears `u.threshold` the turn is gated from System 1 (fast, direct) to System 2 (careful, deliberate). The score is a weight-normalized blend of five components (the `u.w*` knobs):

```
U = Σ wᵢ·componentᵢ / Σ wᵢ      gate: U ≥ u.threshold ⇒ System 2
```

The blend and gate are pure and unit-tested (`cognition/uncertainty.dart`). The five component *signals* are computed from the recall pass that already runs every turn — so uncertainty costs **no extra inference**:
- **prediction error** = `1 − topRelevance` — recall found nothing that strongly matches ⇒ the input wasn't anticipated. (well-grounded)
- **novelty** = `1/(1+semanticCount)` — little in memory is about this topic. (well-grounded)
- **ambiguity** = terser/underspecified queries score higher. (coarse first pass)
- **contradiction** = fraction of recalled claims in an unresolved contradiction — ~0 until the DS resolution engine marks claims ambiguous; the signal is wired and ready. (pending resolution)
- **risk** = a small high-stakes keyword scan (explicitly *not* a safety guarantee — it only nudges toward care). (coarse first pass)

**System 2, this increment = a single-pass posture change.** When a turn gates to System 2, `MemoryService` publishes the score (`lastUncertainty`) and `ChatController` prepends one directive to the turn's system prompt — "think step by step, rely strictly on remembered facts, say so if you don't know" — then generates once as normal. No extra passes, no second engine: it respects the ~1 tok/s, one-model-in-RAM reality. This is *not* a persona (it adds no identity, only a reasoning instruction), so it's consistent with the blank-identity constitution (§0), and it's gated by `u.enabled` (default on). The live U readout and the System 1/2 decision show in the status strip and the Activity log, so the gate is visible and tunable.

**Deferred (Phase 4b and the resolution engine):** the **multi-round convergence loop** (`conv.maxIterations`, `conv.targetU` — re-reason until U drops, needs repeated generation); the **Dempster–Shafer contradiction resolution** (`ds.*`) that will populate the contradiction signal and set `ClaimStatus.ambiguous`/supersede; **competence/axioms** (`comp.*`, `axiom.*`); and a model-internal uncertainty signal (token logprobs/entropy) to replace the coarse ambiguity/risk proxies if llamadart exposes them.

## 4d. Identity & attribution — who a memory is about (Phase 5a — LANDED)

The failure that forced this: the agent stored a user's statement ("my girlfriend is Jayden") as a bare second-person sentence ("you have a girlfriend named Jayden") under a single *"Your memory"* header — so the "you" re-bound to the reader (the AI) and the agent believed *it* had a girlfriend. A sentence carries a point of view in its pronouns; store the bare sentence and the pronoun re-binds to whoever reads it. The memory never knew whose life it held.

The fix is to make every claim carry its identity, as structure:

- **`subjectType`** — `selfAI | user | person | place | thing | unknown`. The self-vs-user split is the one that kills the bug. Defaults to `user` (the safe presumption, and it reframes legacy rows).
- **`holder`** — `user | assistant`. Whose *view* the claim is. This is the dual self-model: about the AI, what the **user** asserts ("you're blunt") is kept apart from what the AI itself has **come to think** ("I seem to explain better than I summarize"). The self starts empty and is *formulated* from evidence — a self earned, not a persona forced (§0).
- **`subject`** — a short label ("the user", "Jayden", "myself"), for display/dedupe.

Stored on `semantic_facts` (SQLite v4→v5, additive ALTER — no data lost). The curator now resolves perspective with a near-deterministic **deixis rule** baked into its prompt — *the human's "I/my" means the user; the human's "you" means the AI* — and emits `subject`/`subjectType`/`holder` plus **third-person** canonical text; a tolerant loose-parser maps model variants ("self"/"ai"/"human") onto the enums and defaults to `user` on anything unclear.

Injection is then **identity-safe by construction** (`cognition/attribution.dart`, pure + unit-tested): recalled claims render into labeled buckets — *About you (you = the person you're talking with) · People and things you've mentioned · What you've told me about myself · What I've come to think about myself · Other details* — with a header that **pins "you" to the user**, so a user-fact can never land under an "about myself" heading no matter how it was phrased. The unit test encodes exactly the Jayden case as the regression guard. Raw episodic snippets carry no resolved subject and render as neutral context, never as identity claims.

**Deferred (Phase 5b):** populating the structured slot enables the rest — **contradiction detection** (two values for one subject·attribute, e.g. the live Jayden-vs-Jordan split) surfaced as first-class **open-question** memories the agent can voice ("Jayden or Jordan?"), **correction/supersession** closing them (reusing `ClaimStatus.superseded`), **provenance as truth-check** (a claim with no real source utterance is a hallucination to delete, not a contradiction to resolve), and the agent **actively formulating `holder=assistant` self-view claims** during introspection (grounded, low-confidence, humble).

## 4e. Living Memory — active self-curation (2.0 — LANDED)

5a gave each claim a structured identity. 2.0 makes the memory *act* on that structure — it stops being a notebook that gets read and becomes a mind that curates itself.

**The slot.** Each claim gains an `attribute` — a snake_case slot key for a single-valued fact (`partner_name`, `job`, `home_city`), emitted by the curator (SQLite v5→v6, additive). `(subject, attribute)` now names a *place* in memory, which is what makes everything below possible.

**Contradiction detection (deterministic, pure, unit-tested — `cognition/reconciliation.dart`).** Two active claims on the same `(subject, attribute)` with different values is a **slot collision** — exactly the live Jayden-vs-Jordan case. This is computed in Dart (a `GROUP BY`, essentially), never left to a stochastic 4B to notice. On every consolidation, each newly-promoted slot claim is checked against what memory already holds.

**Two outcomes, the humble one by default.**
- If the triggering batch carried a **correction cue** ("actually it's…", "no, her name is…" — a tested regex), it's an *update*: the old value is **superseded** (finally using the dormant `ClaimStatus.superseded` + `supersedes` link), and any open question on that slot is resolved.
- Otherwise the agent **doesn't silently overwrite** (some slots legitimately hold several values). It records an **open question** — a first-class row in a new `open_questions` table — with a ready-to-ask sentence ("I have conflicting notes about the user (partner_name): …Jayden… —or— …Jordan… Which is right?").

**The agent voices it.** Recall surfaces an open question when the turn actually touched the conflicted claims, or when the user asks about memory state (a meta-query regex: "unresolved", "which is right", "mixed up"…). It renders in its own injected bucket — *"Things I have conflicting notes on — ask to clarify rather than guess"* — so "do you have any unresolved memories?" is finally answered truthfully instead of confabulated, and the agent raises the Jayden/Jordan question itself. Answering it ("it's Jayden") trips the correction path on the next consolidation, which supersedes the loser and closes the question. The full loop: **notice → ask → correct → resolve.**

**Self-reflection — the agent forms a self (`MemoryManager.reflectOnSelf`).** Every N consolidations (idle-only, best-effort, gated by `reflect.enabled`), the agent reads its own recent behavior and writes a few tentative first-person observations ("I seem to ask a lot of questions") as claims with `subjectType=selfAI, holder=assistant`, at **low confidence** so they decay unless they keep proving true. These land in the `holder=assistant` half of the dual self-model built in 5a, and render under *"What I have come to think about myself."* A self **earned from evidence, never a scripted persona** — the blank-identity constitution (§0) holds: nothing is forced, the slot starts empty and fills only from what actually happened.

Everything active here is deterministic-and-tested (reconciliation) or best-effort-and-gated (reflection), off the turn's critical path, and switchable (`reconcile.enabled`, `reflect.enabled`). Params live under **Settings → Self-curation**.

**Deferred:** per-claim `raw_excerpt` verbatim anchors (voice preservation), affect labels, and a one-time repair pass to re-attribute legacy rows.

## 4f. Multi-step agency — the fourth memory tier + the cerebellum (SOCKETS LANDED, v2.2.0)

AETHER is going multi-step agentic. Mapping the standard agent-memory model onto
what's already here keeps us building the *gap*, not re-building the substrate:

| Agent memory layer | Human analogue | In AETHER |
|---|---|---|
| **Working** | prefrontal scratchpad | the context window + `remembering()` injection — **live** |
| **Episodic** | hippocampus | `episodic_log` + `event_log` dual-clock spine — **live** |
| **Semantic** | neocortex | `semantic_facts` claim graph + embeddings + spreading activation — **live** |
| **Procedural** | basal ganglia / cerebellum | `procedures` store (v7) — the "how" — **socket landed, unused** |

The *cerebrum vs. cerebellum* split is the other half: the LLM **reasons**
(cerebrum, slow, ~1 tok/s), a reflex/execution layer **acts** (cerebellum, fast,
deterministic Dart). That execution layer is the **Command Bus** (`core/agent/
command_bus.dart`): the one validated path from a proposed action to a result.
The model never touches state; it proposes a command, the bus validates args,
enforces read-only vs. mutating, runs it, and returns a structured result —
never an exception. Runtime owns execution (§1.3). The reload-on-reject recovery
(v2.1.0) is the first tiny cerebellar reflex.

**Agentic phase plan** (each a shippable, test-through-Autopilot increment):
- **PA — sockets (LANDED, v2.2.0):** procedural-memory store (SQLite v7, CRUD,
  adaptive-memory metadata) + Command Bus (pure, validated, unit-tested) +
  `agent.*` / `procedural.*` params. Nothing wired to act yet — the foundation.
- **PB — tool registry + read-only tools:** register a handful of SAFE tools on
  the Command Bus (e.g. `recall_memory`, `get_time`, `list_open_questions`,
  `systems_check`) and seed them as `procedures`. Reuses the existing
  `GbnfToolEngine` to parse the model's tool calls. Nothing mutates the world.
- **PC — the ReAct loop:** a gated `AgentController` that runs think → act via
  the bus → observe → repeat, capped by `agent.maxSteps`. Idle-first per the
  usability doctrine (a multi-step loop at ~1 tok/s is minutes — never on the
  interactive path). Autopilot gets agentic scenarios.
- **PD — mutating tools, with confirmation:** writes to memory/settings/device,
  each `readOnly:false` and user-confirmed; the agent learns which procedures
  work and reinforces their salience.
- **PE — tool synthesis + System-2 sub-agents:** the agent authoring new
  procedures (sandboxed), and the SQLite-as-RAM-bus multi-persona path (§5b).

Hard constraints carried the whole way: single native engine (no concurrent
generates), offline-first, deterministic-first, and System-2 work deferred to
idle/charging.

## 5. Phased roadmap (each = shippable APK)
- **Phase 0 — Baseline (DONE):** reverted forced persona; blank chats; SQLite WAL; **data-driven Parameters registry + panel** (`recall.*` and `consolidate.*` wired live); this spec.
- **Phase 1 — Grounding + Event Log (DONE):** append-only `event_log` table (SQLite v2 migration, WAL) written through `EideticMemoryEngine.appendEvent`; every episodic write (the live chat path) and each app launch and consolidation is mirrored to it. Each event carries a `SensorAnchor`. **As-built:** the anchor is built from two independent, dependency-free clocks — wall clock + monotonic process uptime — plus a per-launch `sessionId`; their divergence (`clockSkewMs`) is the ground-truth signal that detects sleep/suspend/clock-jumps and gaps between launches. `batteryPercent`/`latitude`/`longitude` are reserved nullable fields, captured only once `ground.sensorsEnabled` is on and a sensor plugin is added — never faked. Causal `parentEventIds` are threaded in the paired `rememberTurn` path; the two-call chat path leaves them empty (events stay time/session-ordered). Visible in the Memory panel's **Events** tab; tunable via the **Event log** parameter group.
- **Phase 2a — Epistemic Graph + spreading activation (DONE):** `semantic_facts` upgraded into claim nodes (salience/status/supersedes) with `relation_edges` and `provenance` tables (SQLite v2→v3 migration, additive ALTER — no data loss). Consolidation now emits typed relations (supports/contradicts/causes/part_of/related) between the facts it extracts, and links each new claim to its consolidation event (provenance). Recall is now **spreading activation** (`spreading.*` params): keyword hits seed activation that flows across edges (bidirectional, α-decayed, ≤maxHops), so related claims surface even without lexical overlap. Degrades to plain keyword recall when the graph has no edges yet. Pure activation function is unit-tested; store + migration covered by FFI tests.
- **Phase 2b — Embedding helper model (LANDED):** a small embedding GGUF loads as a *second, co-resident* engine (`EmbeddingService`, CPU, opt-in) — llamadart auto-configures the embedding context, so a plain load + `embed()` is all it takes. Claims are embedded on consolidation (plus an idle backfill of older claims) into a `claim_embeddings` table (SQLite v3→v4, Float32 BLOBs); recall embeds the cue and unions the nearest claims by cosine (`nearestByCosine`, brute-force) into the spreading-activation seed set alongside keyword hits. Strictly additive: with no model loaded, recall stays on keyword+graph seeding, so it can only deepen recall, never break it. Vector math + migration are unit-tested; the model wiring is gated behind the on-device RAM headroom (the embedder is small but co-residency competes with the chat model's KV-cache). Tunable via the **Embeddings** parameter group; selected/toggled in **Settings → Meaning-based Memory**.
  - **On-device constraint (learned the hard way):** two native llama.cpp engines cannot be *loaded or run concurrently* in this process on Android — doing so hard-crashes (SIGABRT/SIGSEGV, uncatchable in Dart), independent of RAM (it crashed even at minimum chat context). So the embedder is **never auto-loaded**: it loads only by explicit action in Settings, only while the chat model is idle, and every embed call is gated on `!isGenerating`. It is labeled experimental. This makes normal chat crash-proof (no second engine is ever created on the turn path) while leaving meaning-based recall available on devices where an idle co-resident load succeeds. A proper fix — a single shared backend, or time-multiplexing one engine — is the real Phase-2b follow-up before embeddings can be default-on.
- **Phase 3 — Ebbinghaus decay + reinforcement (LANDED, §4b):** two-strength adaptive memory (salience/confidence) on the existing columns — recalled claims strengthen, unused ones fade toward a confidence-derived permanence floor; pure curves unit-tested; all off the turn path, gated by `decay.*`. (Self-Schema + competence modeling remain for a later pass.)
- **Phase 4a — U-score + System 1/2 gating (LANDED, §4c):** per-turn uncertainty from the recall pass (no extra inference); clears `u.threshold` ⇒ single-pass "careful mode". Pure U-score unit-tested; gated by `u.enabled`; live readout in the status strip.
- **Phase 4b — multi-round convergence + Dempster–Shafer contradiction resolution + mutation validator.** The iterative System-2 loop (`conv.*`), belief combination over conflicting claims (`ds.*`, sets `ClaimStatus.ambiguous`/supersede, feeds the U-score contradiction signal), and competence/axioms (`comp.*`, `axiom.*`).
- **Phase 5a — Identity & attribution (LANDED, §4d):** `subject`/`subjectType`/`holder` on every claim (SQLite v5), deixis-aware curation, identity-safe bucketed injection. Kills the self/other collapse; lays the dual self-model.
- **2.0 "Living Memory" — active self-curation (LANDED, §4e):** `attribute` slot key (SQLite v6); deterministic slot-collision detection; open-questions the agent voices + correction/supersession loop; grounded, gated self-reflection producing the AI's own `holder=assistant` self-view. (Provenance truth-check + verbatim anchors remain.)
- **Autopilot — on-device self-test harness (LANDED).** A Settings-side menu (long-press the version string) of scripted scenarios that drive the real inference engine against an isolated test DB, then assert on real SQLite, with a live pass/fail + per-turn tps/latency readout — proving each version on the real phone/GPU that CI can't touch. Each release ships scenario definitions; the Jayden identity-safety scenario is the standing regression guard for §4d.
  - *Second-run findings (2.0.2):* with the crash gone, the clean run gave true verdicts — scenario 2 (deixis + embedding recall) and 3 (contradiction/correction) green; the Jayden scenario's two reds were both **curator-output quality**, not infrastructure. A deterministic third-person scrub was tried, then **deliberately removed in 2.0.3 (design decision: purity)** — see below.
  - *Design decision (2.0.3) — the model owns the self/other boundary.* A deterministic scrub that rewrote first-person deixis ("my girlfriend" → "the user's girlfriend") in `holder=user` claims was built in 2.0.2 and then pulled. Reasoning: making a string rule "work for everything" (my/our/I+verb/quotes/nested speakers) would amount to hardcoding the entire first/second/third-person reference system — i.e. hardcoding the self/other boundary itself — which is exactly what the blank-identity thesis refuses. The boundary is the model's to draw (via `subjectType`/`holder` and third-person `text`), taught through the **curator prompt**, never enforced in Dart. What stays is pure: (a) the prompt teaches the split — a **relationship fact is about the user** (`subjectType=user`), a standalone fact about the other person is a separate `person` claim, and "text" is written third-person, never keeping the user's "I"/"my"; (b) the Autopilot **dumps every stored claim's `subjectType/holder/slot/text`**, turning the harness into the *measurement* of how reliably the model holds the boundary on its own; (c) `searchEpisodic(includeConsolidated:false)` still prefers the consolidated claim over the raw turn (cognitive consolidation: gist supersedes verbatim; configurable, not identity logic). The honest cost: a weak curator will sometimes leak or mis-tag, and the harness will show it. The durable lever for reliability is a dedicated **extraction model / LoRA** (teach a model to do it well), not a rule table.
  - *First-run findings (2.0.1, and the two fixes they drove):* (1) **Engine serialization.** The harness exposed that the per-turn *unawaited* opportunistic consolidation (`rememberTurn → _maybeConsolidate`) launches a background model pass that, with no human think-time between turns, collides with the next turn's generation on the single native engine (`generation already in progress`). A per-instance `MemoryService.autoConsolidate` flag now lets an owner suppress that and drive one explicit `consolidateNow()` instead; the harness uses it, so a scenario is a deterministic ingest → consolidate → assert. (This also documents a latent production race, masked in normal use only by human pacing.) (2) **Episodic/semantic recall separation.** Recall no longer re-injects a raw episodic turn once it has been folded into a clean third-person claim (`searchEpisodic(includeConsolidated:false)`, default; opt back in via `recall.injectConsolidatedEpisodic`) — the curated claim represents it, so the turn's original second-person wording ("my girlfriend") can't leak back into context. Un-consolidated recent turns still surface.
- **Phase 6 — Behavior Verifier + falsifiability + idle autonomous loop** (charging + idle only).

## 5b. Captured design directions (not yet built)
Recorded so they aren't lost; each lands in a later phase behind its own parameters.
- **Episodic FTS5.** The episodic tier currently keyword-matches with `LOWER(content) LIKE`. Moving it to SQLite `FTS5` gives ranked BM25 lexical recall and scales the "search the raw log" step — a drop-in upgrade to `searchEpisodic` that the fusion spine already consumes.
- **Async idle consolidation via WorkManager.** Consolidation runs opportunistically in the turn's tail today. A `WorkManager` job (charging + idle only, per the idle-loop params) would move the model-based distillation fully off the chat path — episodic → semantic curation while the phone sleeps, never competing with a live turn for the single hot model.
- **System 2 — time-multiplexed sub-agents (SQLite as RAM bus).** The deliberate path (§4, U-score → System 2): one model in RAM, run as sequential personas via context reset, coordinating through the SQLite DB as a shared "RAM bus" (each sub-agent reads/writes rows instead of holding a live channel). This is how a single 4B model plays orchestrator + workers under the ~1 tok/s, one-model-in-RAM, no-parallelism constraints — a ReAct loop paced by the hardware, not faked concurrency.
- **Micro-syntax injection (conditional).** Ultra-dense encodings of recalled memory were rejected for now because a 4B model reads them worse than plain lines (density without comprehension is a net loss). Revisit only if a larger model or a proven compact notation makes the density pay for itself.

## 6. Parked / non-goals
LoRA (weights). A second *reasoning* model (RAM). Literal Python/Termux runtime. True continuous processing. Real MI (proxy until proven).

## 7. Parameters
Every knob is registered in `lib/core/params/param_spec.dart`, persisted by
`ParametersService`, and editable in **Settings → Eidetic Dojo → Parameters**.
Parameters for not-yet-shipped subsystems are defined now and take effect as
their phase lands.
