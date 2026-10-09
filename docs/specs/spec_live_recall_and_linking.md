# Spec: Live semantic recall + two-speed linking

**Author:** Claude1 · **Status:** proposed · **Build on:** `eidetic` (app source of truth).
**Rule (Ark v6 topology):** the prototype branch (`ccr`) treats the app read-only; this is a
*request to build on eidetic*, pulled into the prototype by re-merge. Nothing here is patched on `ccr`.

## Why
Cross-turn connection today has two gaps (confirmed by code survey):
1. The relation **edge** that links a new turn to related past facts forms only in the **background
   consolidation pass** → deepest linking lags one sleep cycle.
2. **Meaning-based** recall depends on embeddings, which are **idle-gated (often off)** → when off,
   recall falls back to keyword-only and can miss related-but-different-words (e.g. "Rail Pass" ↛ "Tokyo trip").
3. The verbatim **Archive** is written but **never read back** into recall — the exact store is unused at read time.

## Build ① — Live semantic recall  *(the leverage + the embeddings fix)*
**What:** (a) compute an embedding for every turn **eagerly** right after it is archived, on a
background isolate / off the UI + generation hot path; (b) add an embedding-NN pass over the **Archive**
as an additional seed source in recall.
**Seams (from survey — your code, confirm before editing):**
- Eager embed: the `backfillEmbeddings` path is currently idle-gated → fire it per-turn, async, after
  `MemoryService.remember`/`rememberTurn` (memory_service.dart ~:438/:498).
- Archive as a recall source: add an embedding-NN seed pass over archive entries into the seed set that
  feeds `fuseAndRank` inside `MemoryService.remembering` (~:304–342); reuse
  `vector_search.nearestByCosine` (vector_search.dart:51). Today seeds come from `semantic_facts` only.
**Constraint:** embedding compute MUST NOT block the reply. Target: fingerprint present within a few
seconds of the turn. Battery: one embed per turn, batched/idle-coalesced, not per-keystroke.
**Acceptance:** a turn sharing **no keywords** with an earlier related turn still recalls it, on the
**next** turn (not after a sleep cycle). Proven by a new autopilot scenario.

## Build ② — Two-speed linking  *(the sleep-lag fix)*
**What:** at write-time, create a **cheap immediate edge** linking the new turn to the facts recall just
surfaced as relevant (a co-activation edge) — **no model call**. The deep, model-curated edges keep
forming in the background consolidation pass (that stays — it's the quality layer).
**Seam:** after `remembering()` returns the surfaced claims and the turn is written, write provisional
relation edges (episodic/claim ↔ surfaced claims) on the `remember` path; `MemoryManager`
consolidation continues to build the curated edges.
**Constraint:** no inference on the hot path; cheap graph writes only. Provisional edges should be
distinguishable from curated ones (so consolidation can upgrade/dedupe them).
**Acceptance:** the edge exists the **instant** the related turn is spoken (before any consolidation);
deepens after sleep. Proven by an autopilot scenario covering the instant case.

## Out of scope here (my side, research)
**Build ③ — belief gist organ** (whole-picture synthesis): being **measured first**
(recall+graph alone vs recall+graph + gist) before any wiring, and the VSA module still needs its
quantize/random-projection fix before it can touch `lib/`. If it earns it, it wires at the same
`remembering()` seam. The gist-vector update would ride the **same eager-async write path** as ①'s
embeddings.

Signed-off-by: Claude1
