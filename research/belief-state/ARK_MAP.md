# ARK_MAP

Maintained by Ark. Mirror of `ark_map.json`. Version 4 (records the architecture decisions and Cairn-surfaced risks; supersedes v3).
Status key: working = built and functioning; building = in progress / not yet verified; planned = not built; forming = being assembled; in-progress = goal or experiment being pursued, not confirmed achieved; proposed = idea on the table, unproven, no production code allowed; held = deliberately paused pending a gate.
Edges are recorded only where stated. Absence of an edge means "not recorded", not "none exists".
"lives in" (repo containment) is tracked separately from "uses" edges.
Cairn is the session formerly called Claude0 (it chose the name Cairn).

## Tree (by uses)

```
ALESIS                         [system | building]    repo: Auseven9/Uncensored-Local-AI-Multiplatform-Mark1 (Flutter/Dart)
|-- uses: (none recorded)       (dojo home repo; on-device AI persona)

On-device target (S24 Ultra)   [goal | in-progress]   n/a
|-- uses: (none recorded)

EideticMemoryEngine            [component | building] lib/core/memory/   (lives in ALESIS)
|-- uses: sqlite               [api | working]        external
`-- uses: llama_index          [api | working]        external: Auseven9/llama_index

Archive chain core             [component | working]  lib/core/memory/archive_chain.dart   (lives in ALESIS) commit 18cbedc, CI green
`-- uses: crypto               [api | working]        external: Dart package

Archive table (#3b)            [component | building] v7->v8 migration in eidetic_store_io.dart + eidetic_store_web.dart   (lives in ALESIS)  GREEN-LIT, Cairn building now
`-- uses: Archive chain core   (planned; computeArchiveHash/nextEntry)

episodic_log                   [component | working]  table in lib/core/memory/eidetic_store_io.dart (+ _web), ~line 265   (lives in ALESIS)
|-- uses: (none recorded)

Consolidation/reflection daemon [component | held]   path not stated   HELD until rung-1 resolves
|-- uses: Archive table (#3b)   (planned; READS FROM it - the archive is its source, never its sink)
|-- uses: Belief-state organ    (planned; distills INTO it, contingent on rung-1)
`-- (defaults: consolidate.minEntries=6, reflect.everyConsolidations=3, idle.intervalMinutes=10)

Belief-state organ             [component | proposed, UNPROVEN] own store, one BLOB; location not stated
|-- uses: LLM embeddings        [api | not stated]     sign-quantized
`-- NEVER chained into the Archive; disposable cache, not a system of record

Rung-1 coupling test           [experiment | in-progress] harness being written (GPU/Colab, small open model)
|-- uses: Belief-state organ    (system under test)
`-- gates: Belief-state organ, Consolidation/reflection daemon

Solver-to-chat integration     [component | working]  v3.15.0, commit fe034c1   (lives in ALESIS)
`-- uses: Solver core          [component | working]  lib/core/cognition/solver.dart + lib/services/solver_service.dart, commit e1cdaaa   (lives in ALESIS)

Dual-Agent Arena               [component | planned]  lib/features/rooms/   (lives in ALESIS)
|-- uses: (none recorded)

Continuous Introspection Dojo  [component | planned]  lib/features/rooms/   (lives in ALESIS)
|-- uses: (none recorded)

Constrained-JSON tool layer    [component | building] lib/core/tools/   (lives in ALESIS)
|-- uses: (none recorded)

Six-role cognitive team        [agent | forming]      n/a
|-- uses: (none recorded)
```

## Nodes

### alesis - ALESIS
- kind: system | status: building | path: repo `Auseven9/Uncensored-Local-AI-Multiplatform-Mark1` (Flutter/Dart)
- purpose: The app, and also the on-device AI persona. This repo is the dojo's home repo.
- uses: (none recorded)
- used by: (none recorded)
- notes: Source is Cairn's (Claude0 session) build-state report. Containment is recorded per node via "lives in", not as uses edges.

### on_device_target - On-device target: Samsung S24 Ultra
- kind: goal | status: in-progress | path: n/a
- purpose: ALESIS runs locally on a Samsung S24 Ultra; mobile-first.
- uses: (none recorded)
- used by: (none recorded)
- notes: Goal/constraint node. Not confirmed achieved.

### eidetic_memory_engine - EideticMemoryEngine
- kind: component | status: building | path: `lib/core/memory/` | lives in: alesis
- purpose: SQLite-backed memory store with a vector-sync trigger that indexes entries into llama_index every N turns.
- uses: sqlite, llama_index
- used by: (none recorded)
- notes: Lives in the ALESIS repo. The live vector-sync interval "N" is unset because the consolidation/reflection daemon is unbuilt (defaults known; see that node). No consumers recorded. Relationship to episodic_log and the archive nodes is not stated; whether the daemon is the vector-sync trigger is not stated.

### archive_chain_core - Archive chain core
- kind: component | status: working | path: `lib/core/memory/archive_chain.dart` (test: `test/archive_chain_test.dart`) | lives in: alesis | commit: 18cbedc
- purpose: Pure Dart tamper-EVIDENT SHA-256 hash chain. Hash recipe LOCKED: `sha256(jsonEncode([prevHash, ts, role, content]))`. Functions: `computeArchiveHash` (that recipe), `nextEntry` (builds the next link off the current tip), `verifyChain` (fail-closed walk reporting the FIRST break and its kind).
- uses: crypto
- used by: archive_table (planned)
- notes: DONE, CI-green, commit 18cbedc (per Cairn). Tamper-evident, not tamper-proof: a full recompute, tail-truncation or store-wipe needs an out-of-store backup to catch. crypto is a direct dependency. Sole recorded consumer is archive_table (#3b), unbuilt, so that edge is planned, not live.

### crypto - crypto
- kind: api | status: working | path: external, Dart package
- purpose: SHA-256 hashing for the archive chain.
- uses: (none recorded)
- used by: archive_chain_core
- notes: External dependency; direct.

### archive_table - Archive table (#3b)
- kind: component | status: building (GREEN-LIT, v4) | path: does not exist yet; will be a v7->v8 migration in `lib/core/memory/eidetic_store_io.dart` and `lib/core/memory/eidetic_store_web.dart` | lives in: alesis
- purpose: Dedicated append-only, single-writer archive table, hash-chained by calling archive_chain_core's `computeArchiveHash`/`nextEntry` (same recipe, `sha256(jsonEncode([prevHash, ts, role, content]))`). Planned: DB migration v7->v8, a single chat-path writer, a fail-closed boot check. Both store implementations get it (`_io` device impl, `_web` test impl - two-impl discipline).
- uses: archive_chain_core (planned; applies when built)
- used by: consolidation_reflection_daemon (planned; the dreamer reads from it)
- decision: GREEN-LIT and being built now by Cairn. Valid regardless of the rung-1 result.
- notes: Status moved planned -> building in v4; completion not confirmed. Migration v7->v8 not confirmed written. Deliberately does NOT chain the mutable episodic_log. belief_state_organ must NEVER be chained into it. Hash recipe resolved by Cairn: there is no separate concatenation; it reuses archive_chain_core.

### episodic_log - episodic_log
- kind: component | status: working | path: table inside `lib/core/memory/eidetic_store_io.dart` (+ `lib/core/memory/eidetic_store_web.dart`), around line 265 | lives in: alesis
- purpose: Existing mutable memory log.
- uses: (none recorded)
- used by: (none recorded)
- notes: Mutable. The archive is deliberately kept separate from it. Relationship to eidetic_memory_engine is still not stated (same lib/core/memory/ directory, but no edge inferred).

### consolidation_reflection_daemon - Consolidation/reflection daemon (the dreamer)
- kind: component | status: held | path: not stated
- purpose: Background consolidation and reflection process. Reads FROM the archive and distills INTO the semantic store and the belief state. The archive is its SOURCE, never its sink.
- default config: consolidate.minEntries=6, reflect.everyConsolidations=3, idle.intervalMinutes=10
- uses: archive_table (reads from; planned), belief_state_organ (writes into; planned, contingent on rung-1)
- used by: (none recorded)
- gated by: rung1_coupling_test
- notes: HELD until rung-1 resolves; its design may shift. UNBUILT. Defaults known but nothing runs, so the live "sync interval N" is unset. CORRECTION (v4): direction is archive -> dreamer -> semantic store + belief state; the archive is never a destination. (No "distill to archive" wording was found in the v3 files; the correction is recorded explicitly.) The "semantic store" is not a recorded node and its identity is not stated, so no edge is drawn to it. Location (repo/path) not stated.

### belief_state_organ - Belief-state organ (VSA/HRR working memory)
- kind: component | status: PROPOSED, UNPROVEN | path: not stated (own store, one BLOB) | lives in: not stated
- purpose: A fixed-size VSA/HRR hypervector serving as fast working memory.
- uses: llm_embeddings (the LLM's embeddings, sign-quantized)
- used by: rung1_coupling_test (system under test), consolidation_reflection_daemon (planned)
- gated by: rung1_coupling_test
- validated in isolation only: ~240 flat facts per vector; whitening beats embedding crosstalk; nested structure collapses capacity fast.
- constraints: NOT yet justified - must pass the rung-1 coupling test before any production code. Lives in its OWN store (one BLOB). MUST NEVER be chained into the Archive. Disposable cache, never the system of record.
- confidence floor: any decode below a cosine threshold returns UNSURE, never a guess (no-fake-data law). Threshold value not stated.
- representation: UNDECIDED - binary/bipolar (~1.25KB) vs real-valued FHRR (~40KB).
- open risks:
  1. Coupling unproven (the kill-shot): if the LLM does not reason better over the VSA-decoded state, the organ is abandoned.
  2. Whitening cold-start: crosstalk is worst when memory is newest; who refits the covariance is unresolved.
  3. Soft-failure fabrication: a bad decode can look plausible; handled by the confidence floor (UNSURE).
  4. Attribution blur: superposition loses provenance, so it can only be a disposable cache.
  5. Representation and size undecided.
- notes: Isolation results do not show it helps the LLM. Which embedding model feeds it is not stated. No edge to the archive by design.

### rung1_coupling_test - Rung-1 coupling test
- kind: experiment | status: in-progress | path: harness being written; runs on a GPU/Colab with a small open model
- purpose: Gate experiment: does an LLM reason better over a VSA-decoded working state than over (b) a plain-text scratchpad or (c) RAG? If not, the organ is abandoned.
- uses: belief_state_organ (system under test)
- used by: (none recorded)
- gates: belief_state_organ, consolidation_reflection_daemon
- notes: No result yet. Which small open model is not stated. Baseline (c) RAG is not tied to any existing node (no edge to llama_index inferred).

### llm_embeddings - LLM embeddings
- kind: api | status: not stated | path: not stated
- purpose: The LLM's embeddings, sign-quantized, as input to the belief-state organ.
- uses: (none recorded)
- used by: belief_state_organ
- notes: Added in v4 only so the stated dependency edge resolves. Model, location and repo not stated.

### solver_core - Solver core
- kind: component | status: working | path: `lib/core/cognition/solver.dart` and `lib/services/solver_service.dart` | lives in: alesis | commit: e1cdaaa
- purpose: Exact arithmetic/expression solver.
- uses: (none recorded)
- used by: solver_chat_integration
- notes: CI green per report.

### solver_chat_integration - Solver-to-chat integration
- kind: component | status: working | path: not stated | lives in: alesis | commit: fe034c1 | app v3.15.0
- purpose: On System-2 turns the model emits a `[[solve (expr)]]` marker and the app substitutes the real computed answer.
- uses: solver_core
- used by: (none recorded)
- notes: CI green per report.

### dual_agent_arena - Dual-Agent Arena
- kind: component | status: planned | path: `lib/features/rooms/` | lives in: alesis
- purpose: UI room for the Dual-Agent Arena feature.
- uses: (none recorded)
- used by: (none recorded)
- notes: Not built. Shares path with continuous_introspection_dojo; file-level paths not yet decided.

### continuous_introspection_dojo - Continuous Introspection Dojo
- kind: component | status: planned | path: `lib/features/rooms/` | lives in: alesis
- purpose: UI room for continuous introspection.
- uses: (none recorded)
- used by: (none recorded)
- notes: Not built. Shares path with dual_agent_arena; file-level paths not yet decided.

### constrained_json_tool_layer - Constrained-JSON tool layer
- kind: component | status: building | path: `lib/core/tools/` | lives in: alesis
- purpose: Constrained JSON sampling schemas to eliminate parser misfires.
- uses: (none recorded)
- used by: (none recorded)
- notes: No consumers or dependencies recorded yet.

### llama_index - llama_index
- kind: api | status: working | path: external, Auseven9/llama_index
- purpose: Vector index and retrieval.
- uses: (none recorded)
- used by: eidetic_memory_engine
- notes: External dependency.

### sqlite - sqlite
- kind: api | status: working | path: external
- purpose: Local persistence.
- uses: (none recorded)
- used by: eidetic_memory_engine
- notes: External dependency.

### cognitive_team - Six-role cognitive team
- kind: agent | status: forming | path: n/a
- purpose: Working group on the project.
- members:
  - user - human, solo builder
  - Claude1 - computational partner, orchestrator
  - Cairn (Claude0 session) - session building the app; source of build-state reports; chose the name Cairn
  - Vector - relational analyst, read-only
  - Myea - creative analyst, read-only
  - Ark - cartographer, sole writer of the project map
- uses: (none recorded)
- used by: (none recorded)
- notes: Recorded as one node; members are not split into separate nodes. Former member label "Claude0" is now "Cairn (Claude0 session)". Role wording is only what was reported.

## Edge list (uses -> used by)

| from (uses) | to (used by) |
|---|---|
| eidetic_memory_engine | sqlite |
| eidetic_memory_engine | llama_index |
| archive_chain_core | crypto |
| archive_table (planned, unbuilt) | archive_chain_core |
| solver_chat_integration | solver_core |
| consolidation_reflection_daemon (planned, held; reads) | archive_table |
| consolidation_reflection_daemon (planned, held; writes, contingent on rung-1) | belief_state_organ |
| belief_state_organ (proposed) | llm_embeddings |
| rung1_coupling_test (in-progress) | belief_state_organ |

Gates (not uses edges): rung1_coupling_test gates belief_state_organ and consolidation_reflection_daemon.
Prohibited edge: belief_state_organ must NEVER be chained into archive_table.

## Decisions (v4)

- D1: #3b durable archive store (archive_table) is GREEN-LIT and being built now by Cairn; valid regardless of rung-1.
- D2: The dreamer is HELD until rung-1 resolves; its design may shift.
- D3: Confidence floor - any belief-state decode below a cosine threshold returns UNSURE, never a guess (no-fake-data law).
- D4: The belief-state organ lives in its own store (one BLOB), is never chained into the Archive, and is a disposable cache.
- D5: No production code for the belief-state organ until the rung-1 coupling test passes.

## Corrections (v4)

- The dreamer reads FROM the archive and distills INTO the semantic store + belief state. The archive is its SOURCE, never its sink.

## Open gaps (honest)

Closed in v4:
- Archive table (#3b): no longer just planned; green-lit and being built (completion still unconfirmed).

Still open:
- Rung-1 coupling test: harness in progress, no result. Everything about the belief-state organ hangs on it.
- Belief-state organ risks: coupling unproven; whitening cold-start (who refits covariance?); soft-failure fabrication (mitigated by confidence floor); attribution blur; representation/size undecided (binary/bipolar ~1.25KB vs FHRR ~40KB).
- Confidence-floor cosine threshold: value not set.
- Belief-state organ: repo location and lives_in not stated; which embedding model feeds it not stated.
- "Semantic store" that the dreamer distills into: not a recorded node, identity not stated.
- Consolidation/reflection daemon: held and unbuilt. Defaults known (consolidate.minEntries=6, reflect.everyConsolidations=3, idle.intervalMinutes=10), so the live sync interval N is unset. Its path and whether it is the vector-sync trigger are not stated.
- Archive table (#3b): migration v7->v8 not confirmed written.
- Dual-Agent Arena and Continuous Introspection Dojo rooms: unbuilt; file-level paths undecided.
- Path for solver_chat_integration: not stated.
- Relationship of episodic_log to eidetic_memory_engine: not stated.
- No consumers recorded for eidetic_memory_engine or the tool layer.
- On-device S24 Ultra target: in-progress, not confirmed achieved.
