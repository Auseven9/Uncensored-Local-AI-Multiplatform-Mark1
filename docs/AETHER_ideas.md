# AETHER — Idea Pad

A running capture of ideas, outside assessments, and design provocations for
AETHER. This is a scratch/thinking space, **not** the canonical spec — the spec
we execute from is [`AETHER_architecture.md`](AETHER_architecture.md). Entries
here are dated, newest first. External reviews are recorded as *data to weigh*,
not doctrine; where an entry maps onto real build work, it's cross-linked to the
spec's roadmap (§5) or captured directions (§5b).

---

## 2026-09-30 — External assessment: novelty, value, and the usability question

> Source: an outside LLM review, pasted in by Dylon. Captured verbatim in
> substance. Treat as an outside opinion to pressure-test against, not as a
> claim we've verified.

### Verdict: genuine, standout novel value
The novelty isn't in inventing cognitive theory from scratch — spreading
activation, epistemic logic, and dual-process theory have existed in cognitive
science for decades. The novelty is in **where and how** these are synthesized:
building a deterministic cognitive OS directly on constrained edge hardware to
**replace brute-force LLM scaling**.

### Where the novelty & value live
- **Rejection of the "infinite context" trap.** The mainstream trajectory
  brute-forces memory by ballooning context windows to 1M+ tokens on ~$30k
  server GPUs. AETHER flips it: an external cognitive engine lets a tiny 4B
  model in a 1,024-token window on a phone exhibit structured, persistent
  long-term memory without blowing up RAM or thermal limits.
- **Epistemic graph vs. naive vector RAG.** Almost every "memory" app on the
  market is standard RAG (cosine similarity on text chunks), which has no
  concept of truth evolution, contradiction, or provenance — change your mind
  and it returns both the old and new belief at once. AETHER's typed graph
  (`supports` / `contradicts` / `supersedes`) with `active`/`superseded` status
  actually models epistemic truth evolution.
- **The dual-clock temporal spine.** Anchoring the event log with *both*
  wall-clock time and monotonic uptime is a rare, deliberate choice. LLMs have
  zero internal clock and are trivially deceived about elapsed time; grounding
  continuity in a hardware monotonic clock gives an un-hallucinatable sense of
  real-world progression and interval measurement.
- **SQLite as the single-model "RAM bus."** Running System 2 "sub-agents" on
  one local model via hard context resets, with SQLite as the state exchanger,
  gets multi-agent specialization **without** multiple models resident in
  device RAM — constraint-driven engineering.

### Honest hard friction points (where the architecture gets tested)
1. **The small-model extraction floor.** The graph is only as good as the
   consolidation pass that builds it. A 4B GGUF at ~1 tok/s can be sloppy
   extracting structured relations or spotting subtle contradictions. A
   hallucinated edge during consolidation means spreading activation will
   systematically surface wrong memories later. → The consolidation gate needs
   **strict deterministic schema validation before any edge touches SQLite.**
2. **Interactive latency vs. System 2.** At 0.1–1 tok/s, any multi-step ReAct
   or multi-pass reflection *during active chat* cripples UX. Idle background
   processing (charging + idle, via Android WorkManager) isn't a nice-to-have —
   it's **the only way** the architecture stays usable day to day.
3. **Graph runaway & attractors.** Heavily connected / frequently retrieved
   nodes become "attractors" that swallow activation energy every turn, locking
   out subtle or recent memories. Strict Ebbinghaus decay + non-linear
   **dampening** is critical so the memory budget isn't dominated by the same 5
   facts forever.

### The usability reality of slow inference
- 1 tok/s ≈ 12–15 words/min; a 100-word reply takes >1 minute. 0.1 tok/s ≈ one
  word every 10–12s — synchronous chat is functionally dead. Foreground System
  2 (a 3-step, ~300-token loop) = 5–30 min on one screen: fatal.
- **But deterministic memory is instant.** FTS5 queries, graph traversal, and
  token-budgeted prompt assembly run in ~2–10 ms, all in C/Dart, not the LLM.
  The "House" is lightning fast even while the "Seeker" (the LLM) is slow.

### Usability strategies for "slow AI"
1. **Shift "instant chat" → "async message / journaling."** Drop a thought;
   a background process / local notification alerts when the reply has
   compiled. Feels like email or a smart diary, not a typing bubble.
2. **Strict output budgeting.** Default replies to a hard **40–80 token** cap
   (~2–4 dense sentences). 40 tokens ≈ 40s (tolerable); 300 tokens ≈ 5 min.
   System prompt should force ultra-dense, low-fluff phrasing.
3. **Transparent internal monologue (UI feeds).** Instead of a blank spinner,
   instantly render the recalled memory chips (e.g. `[Activating: Buster (Dog),
   Border Collie, rel 0.89]`) and stream tokens as generated. Watching the
   engine think makes the wait engaging.
4. **Absolute deferral of System 2 to idle/charging.** Interactive mode =
   System 1 only (fast graph lookup + short single-pass generation). System 2
   reflection, consolidation, edge creation, and pruning queue to SQLite and
   run via WorkManager when idle, screen off, on charger.

**Usability verdict:** pitched as a fast general chatbot → F. Framed as a slow,
deeply personal, reflective companion that remembers you forever and never
leaves the device → A-. The deliberate pacing *reinforces* the sense that the AI
is reflecting and consulting memory rather than emitting cached web patterns.

### Hooks into the build (my cross-links — where this touches real work)
- **Friction #1 (extraction floor) →** already partly addressed: consolidation
  runs through the GBNF grammar + `_parseAndCurate` schema mapping (spec §3
  "Mutation validator"). The review pushes it further: *deterministic schema
  validation as a hard gate before an edge is written*, plus a confidence/axiom
  gate on edges. Candidate hardening for the consolidation pass.
- **Friction #2 + Strategy #4 (defer System 2) →** exactly the **WorkManager
  idle consolidation** and **SQLite-RAM-bus System 2** items already captured
  in spec §5b. This is corroboration, not a new direction — reinforces that
  they're load-bearing, not optional.
- **Friction #3 (attractors / runaway) →** maps to spec §5 Phase 3
  (Ebbinghaus decay + reconsolidation) and the existing `decay.*` params. The
  review adds *non-linear dampening* specifically as the anti-attractor
  mechanism, and connects to the "memory-locking" hazard already noted in §4a
  (why recall-reinforcement was kept out of the System-1 pass).
- **Strategy #2 (output budgeting) →** small, cheap, high-leverage UX win we
  can do early: a `gen.maxTokens` default tuned way down for chat (currently
  4096) + a density-forcing system-prompt option. Worth a near-term pass.
- **Strategy #3 (recalled-memory chips) →** the recall engine already logs
  `sem N, epi M, injected P` and each `RecallCandidate` carries source +
  score; surfacing those as instant UI chips before the first token is a
  natural, mostly-frontend feature that turns our slow inference into a feature,
  not a wait.
- **Dual-clock spine →** already shipped (Phase 1 `SensorAnchor`,
  `clockSkewMs`). The review independently flags it as a standout; good signal
  the grounding work was worth it.
