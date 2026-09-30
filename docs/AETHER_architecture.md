# AETHER — Cognitive Runtime (Flutter port) — Canonical Build Spec

Status: Phase 2a landed (graph + spreading activation); Associative Recall Engine landed (hybrid episodic+semantic fusion — §4a); Phase 2b landed (embedding helper model + cosine-seeded recall, opt-in — §5). Next: Phase 3 (adaptive dynamics — decay/reinforcement). This is the single reference we execute from.

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

**Deliberately rejected / deferred here:** cryptic micro-syntax injection (unreadable to a 4B model — density without comprehension is a loss); recall-reinforcement inside this System-1 pass (a memory surfacing must not itself bump the memory's strength, or hot memories lock in and drown recall — "memory-locking"; reinforcement belongs to the deliberate/decay phase). Embedding-based (meaning) seeding plugs into this exact pipeline in 2b — it only changes how the semantic tier is *seeded* (cosine instead of keyword), not the fusion/ranking spine.

## 5. Phased roadmap (each = shippable APK)
- **Phase 0 — Baseline (DONE):** reverted forced persona; blank chats; SQLite WAL; **data-driven Parameters registry + panel** (`recall.*` and `consolidate.*` wired live); this spec.
- **Phase 1 — Grounding + Event Log (DONE):** append-only `event_log` table (SQLite v2 migration, WAL) written through `EideticMemoryEngine.appendEvent`; every episodic write (the live chat path) and each app launch and consolidation is mirrored to it. Each event carries a `SensorAnchor`. **As-built:** the anchor is built from two independent, dependency-free clocks — wall clock + monotonic process uptime — plus a per-launch `sessionId`; their divergence (`clockSkewMs`) is the ground-truth signal that detects sleep/suspend/clock-jumps and gaps between launches. `batteryPercent`/`latitude`/`longitude` are reserved nullable fields, captured only once `ground.sensorsEnabled` is on and a sensor plugin is added — never faked. Causal `parentEventIds` are threaded in the paired `rememberTurn` path; the two-call chat path leaves them empty (events stay time/session-ordered). Visible in the Memory panel's **Events** tab; tunable via the **Event log** parameter group.
- **Phase 2a — Epistemic Graph + spreading activation (DONE):** `semantic_facts` upgraded into claim nodes (salience/status/supersedes) with `relation_edges` and `provenance` tables (SQLite v2→v3 migration, additive ALTER — no data loss). Consolidation now emits typed relations (supports/contradicts/causes/part_of/related) between the facts it extracts, and links each new claim to its consolidation event (provenance). Recall is now **spreading activation** (`spreading.*` params): keyword hits seed activation that flows across edges (bidirectional, α-decayed, ≤maxHops), so related claims surface even without lexical overlap. Degrades to plain keyword recall when the graph has no edges yet. Pure activation function is unit-tested; store + migration covered by FFI tests.
- **Phase 2b — Embedding helper model (LANDED):** a small embedding GGUF loads as a *second, co-resident* engine (`EmbeddingService`, CPU, opt-in) — llamadart auto-configures the embedding context, so a plain load + `embed()` is all it takes. Claims are embedded on consolidation (plus an idle backfill of older claims) into a `claim_embeddings` table (SQLite v3→v4, Float32 BLOBs); recall embeds the cue and unions the nearest claims by cosine (`nearestByCosine`, brute-force) into the spreading-activation seed set alongside keyword hits. Strictly additive: with no model loaded, recall stays on keyword+graph seeding, so it can only deepen recall, never break it. Vector math + migration are unit-tested; the model wiring is gated behind the on-device RAM headroom (the embedder is small but co-residency competes with the chat model's KV-cache). Tunable via the **Embeddings** parameter group; selected/toggled in **Settings → Meaning-based Memory**.
- **Phase 3 — Self-Schema + competence + Ebbinghaus decay.**
- **Phase 4 — U-score + System 1/2 gating + mutation validator + convergence.**
- **Phase 5 — Behavior Verifier + falsifiability + idle autonomous loop** (charging + idle only).

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
