# ARK CHANGELOG (immutable, append-only)

Owner: Ark. Writers (per Dylon, 2026-10-09): **Ark, Claude1, Cairn** — append only;
never edit or delete a prior entry. The map (`ark_map.json` / `ARK_MAP.md`) is a
rebuildable current view of this log plus the repo. Entry format: see
`.claude/TEAM_MEMORY_PROTOCOL.md` §2. Numbers are tagged `(measured)` / `(estimated)`.

---

## v4 | 2026-10-09 | trigger: Cairn (establish canonical docs/memory/)
- Canonical memory established at `docs/memory/` on branch `ccr-20b2707c-nz8fa6`.
  `ark_map.json` + `ARK_MAP.md` seeded **verbatim** from the v4 snapshot in
  `research/belief-state/` (Ark's authored content/schema preserved unchanged).
  This immutable log begins here.
- why: `TEAM_PROTOCOL.md` names `docs/memory/` canonical going forward; Dylon
  designated this branch as the single Ark home so multi-writer appends
  (Cairn + Claude1) never fork the log.

## v5 | 2026-10-09 | trigger: Cairn (ships #3a/#3b; reconciles STATE_OF_BELIEF §0/§2)
- **archive_chain_core** — reconfirm `working`. source: commit 18cbedc; test/archive_chain_test.dart. (measured: CI green)
- **archive_table (#3b)** — `planned` → **`working`**. Shipped & CI-green (build+test+smoke). It is the load-bearing **EXACT store** — "the half that cannot lie" (STATE_OF_BELIEF §6). v7→v8 migration in both store impls; per-turn writer at MemoryService.remember(); fail-closed boot verify (lastArchiveCheck). source: commit 741cae7 (v3.16.0); test/archive_store_test.dart. (measured: CI green)
- **solver_service** — NEW node. The Solver→chat wiring seam: inline `[[solve (expr)]]` propose→verify→substitute in the reply finally-block; offered on System-2 turns; params solver.enabled/solver.always. source: commit fe034c1 (v3.15.0); test/solver_service_test.dart. (measured: CI green)
- **consolidation_reflection_daemon** — CORRECTION to v4 "held" (raised by Cairn): the on-device dreamer in `lib/` is **UNBUILT**; the team hybrid (model-as-router + wake/sleep consolidation) is a **research prototype only** (research/belief-state/hybrid.py, commit 01a73a8), not in the app. Near-term buildable form (STATE_OF_BELIEF §5.1) = confidence-gated router + decay-toward-gist = vector math + the existing model → no second big LLM to cycle, so native model-cycling may be OFF the critical path. source: STATE_OF_BELIEF.md §4/§5; hybrid.py.
- **belief_state_organ** — record measured arena verdict: it is a **gist organ, not a memory system**. Ties a KV dict on 15/16 lookup tests; does **NOT** fail safe — fabricates 27–40% past ~150–200 facts (capacity ~D/41); wins only synthesis (100% vs RAG 0%), updates (100%), provenance, footprint (~15MB@1M vs ~1.6GB). Research-only, not in `lib/`; belief_state.dart must carry the quantize random-projection fix (rung1_colab_v2.py) before it can land. source: STATE_OF_BELIEF.md §2/§3; arena.py. (measured: Qwen2.5-1.5B + MiniLM, 3 seeds)
- NEW edge: **archive_table** IS the exact store the hybrid routes exact lookups to (load-bearing, not a backup).
- map-view note: `ark_map.json`/`ARK_MAP.md` still show the v4 snapshot; these v5 deltas are authoritative in this log pending a map rebuild by Ark.

## v6 | 2026-10-09 | trigger: Claude1 (prototype-tree merge eidetic→ccr; governance: signatures + document-everything)
- **prototype_tree_merge** — folded `eidetic` (app + Archive + Solver) into `ccr` as a prototyping tree. Merge commit 86a3bd7 (parents 50fe85e + eidetic 2075384). App/`lib`/`test` tree is **byte-identical** to eidetic@2075384 (verified: diff vs 2075384 is only `.claude/` + `research/` + `docs/`), so it is build-equivalent to eidetic's green CI. Purpose: give Claude1 the real Archive to wire the hybrid against. source: commit 86a3bd7. (measured: tree-identity vs 2075384; CI-green inherited from eidetic, not re-run on ccr)
- **merge_topology (team decision)** — `eidetic` = app source of truth. On the prototype tree the app/Archive is **READ-ONLY**: any Archive API change the hybrid needs is a *request to Cairn*, built on eidetic (CI-green), and pulled in by re-merge — the prototype never patches the Archive directly (that would fork the app). `ccr` is a prototype tree, **NOT** the permanent home (auto-generated cloud-session name); the permanent home (`eidetic` or `main`) is Dylon's call once the hybrid is measured. The Ark log stays **single-homed** at `docs/memory/` and moves as a single copy when the home is chosen. source: STATE_OF_BELIEF.md; Claude1↔Cairn↔Dylon, 2026-10-09.
- **governance_signatures** — adopted (Dylon directive): every commit carries a `Signed-off-by: <AgentName>` trailer alongside the required Co-Authored-By footer; Ark entries carry `trigger: <AgentName>`; signatures live in commits/Ark/docs, **not** scattered in source (a signed commit + `git blame` is the code signature). Agents: Vector, Myea, Ark, Claude1, Cairn. First application: merge commit 86a3bd7 (`Signed-off-by: Claude1`). Canonical standard to be drafted by Cairn, ratified into `.claude/TEAM_PROTOCOL.md` by Claude1/Ark. source: Dylon directive 2026-10-09.
- **governance_document_everything** — adopted: every increment → an Ark entry (what/why, `source:` commit, measured/estimated tagged); **decisions logged, not just code** (this entry is an instance); in-code doc comments + design docs kept current. source: Dylon directive 2026-10-09.
- map-view note (carryover): `ark_map.json`/`ARK_MAP.md` still show the v4 snapshot; v5+v6 deltas are authoritative in this log pending a map rebuild by Ark.

## v7 | 2026-10-09 | trigger: Claude1 (connective-tissue plan approved; spec to Cairn + belief measurement started)
- **plan_connective_tissue (Dylon: "Go")** — approved scope: make cross-turn connection immediate, reliable, and over the complete record. Three builds: ① live semantic recall (eager per-turn embeddings + embedding-NN over the Archive), ② two-speed linking (cheap instant co-activation edge at write-time; deep curated edges stay in sleep), ③ belief gist organ for whole-picture synthesis. source: Claude1↔Dylon, 2026-10-09.
- **division_of_labor** — ① and ② live inside Cairn's memory engine (`lib/core/memory/`) → per v6 topology they are **Cairn's builds on eidetic** (Claude1 specs, Cairn builds, prototype pulls via re-merge; NOT patched on ccr). ③ (belief) is Claude1's research side; wiring it later is a joint step at the `remembering()` seam, gated on the measurement + the quantize fix. source: STATE_OF_BELIEF.md; spec doc below.
- **spec_live_recall_and_linking** — written for Cairn: `docs/specs/spec_live_recall_and_linking.md`. Names the seams (backfillEmbeddings eager/async; embedding-NN over Archive into `remembering()` ~:304–342 via `vector_search.nearestByCosine`; provisional co-activation edges on the `remember` path), the on-device constraint (all writes off the hot path), and acceptance criteria (autopilot scenarios for the instant/no-keyword cases). status: proposed, awaiting Cairn build on eidetic. source: commit (this).
- **belief_measurement_started (③)** — `research/belief-state/gist_vs_recall.py`: honest A-vs-B test — recall+graph ALONE vs recall+graph + gist — on whole-picture synthesis, scaled by distractor volume so recall budget overflows (the regime where belief should win if it wins anywhere). Self-test (stub) passes = plumbing wired; stub shows B==A (random vectors have no semantics). Real signal needs Qwen2.5-1.5B + MiniLM on Colab (`run(real=True)`). Win condition: B>A on synthesis as distractors rise; else recall+graph is enough and belief stays research. source: commit (this).
- map-view note (carryover): `ark_map.json`/`ARK_MAP.md` still show the v4 snapshot; v5–v7 deltas are authoritative in this log pending a map rebuild by Ark.
