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
