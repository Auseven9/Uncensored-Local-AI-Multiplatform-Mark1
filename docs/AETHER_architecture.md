# AETHER — Cognitive Runtime (Flutter port) — Canonical Build Spec

Status: Phase 0 landed. This is the single reference we execute from.

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
1. **Event Log** — append-only: `id, ts, source, type, payload_json, parent_events_json, sensor_state_json`. WAL, never updated/deleted. Upgrades `episodic_log`.
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

## 5. Phased roadmap (each = shippable APK)
- **Phase 0 — Baseline (DONE):** reverted forced persona; blank chats; SQLite WAL; **data-driven Parameters registry + panel** (`recall.*` and `consolidate.*` wired live); this spec.
- **Phase 1 — Grounding + Event Log:** append-only event log + `SensorAnchor` (time/boot/GPS/battery) on every event. (Cheap; the anti-BS spine.)
- **Phase 2 — Epistemic Graph + spreading activation + embedding helper:** claims/edges/provenance + semantic recall.
- **Phase 3 — Self-Schema + competence + Ebbinghaus decay.**
- **Phase 4 — U-score + System 1/2 gating + mutation validator + convergence.**
- **Phase 5 — Behavior Verifier + falsifiability + idle autonomous loop** (charging + idle only).

## 6. Parked / non-goals
LoRA (weights). A second *reasoning* model (RAM). Literal Python/Termux runtime. True continuous processing. Real MI (proxy until proven).

## 7. Parameters
Every knob is registered in `lib/core/params/param_spec.dart`, persisted by
`ParametersService`, and editable in **Settings → Eidetic Dojo → Parameters**.
Parameters for not-yet-shipped subsystems are defined now and take effect as
their phase lands.
