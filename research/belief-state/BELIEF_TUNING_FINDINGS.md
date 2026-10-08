# Belief — Tuning Findings (team brainstorm + measured result)

## 1. The measured breakthrough (in-session, pure-math decode test)

Does the belief vector return the CURRENT value after a fact changes?

| Mechanism | Current-truth recall |
|---|---|
| baseline decay (α=0.9) | **48%**  ← reproduces the 50/50 continuity tie |
| **active OVERWRITE** (subtract old, add new) | **100%** |
| overwrite + naïve decay | 47%  ← decay breaks the clean cancellation |
| decay, D=8192 | 72% |
| overwrite, D=8192 | 100% |

**The continuity tie was a tuning bug, not a ceiling.** Plain decay only *attenuates*
a superseded value; it lingers and sometimes wins recall. Active overwrite *removes*
it. Caveat: this is the memory decode in isolation (clean random values, no LLM) —
end-to-end gain with real embeddings will be smaller, but the mechanism is proven.
Note the honest subtlety: naïve global decay *after* overwrite breaks the exact
cancellation (47%) — use overwrite without global decay, or decay-aware subtraction.

## 2. Unanimous convergence: active overwrite = reconsolidation

Four independent specialists all named it #1 for continuity:
- **Neuroscience:** reconsolidation — an update re-encodes the trace in place; the
  old value is removed, not stored as a competitor. "The single change that should
  flip continuity toward a win."
- **Physics:** `S ← S − R⊗v_old + R⊗v_new` *zeros* the stale component instead of
  decaying it. Predicted the 48% exactly from `α^gap·v_old + v_new + crosstalk`.
- **Engineering:** "stops stale superposition accumulating — do it regardless."
- **Vector:** graded in-place update folds "what's true now" into the representation.

## 3. The strategic reframe (Vector) — where Belief wins CATEGORICALLY

Stop competing on lookup/continuity (retrieval's home turf — Belief will tie at best).
**RAG's atomic unit is the row; it has no handle for "all of it."** So any answer that
is a *property of the whole memory* — true in aggregate, present in no single row —
is **structurally outside retrieval.** That is Belief's only non-negotiable edge:

> **Aggregate / whole-state inference:** "Taken together, what do my memories imply?"
> The bundle encodes the aggregate directly; RAG fetches top-k rows, none of which
> individually answers, and evidence below the cutoff is invisible.

**The test that proves categorical (not incremental):** store 100+ facts; ask
questions whose answer needs many weakly-related items with NO single supporting row.
Metric: accuracy as fact-count grows while k stays fixed. **Categorical win = Belief
holds steady while RAG collapses** (its evidence falls below the retrieval cutoff).

## 4. Engineering roadmap (ranked; on-device feasible unless noted)

1. **Soft-vector injection** — HIGH / HIGH effort (train adapter off-device). Feed the
   belief vector into the model's hidden state via a small adapter; skip the text
   decode. Removes the one bottleneck RAG doesn't share; lets the model read residual
   signal cleanup would discard. The structural bet to close the lookup gap.
2. **Whitening** — HIGH / LOW. ZCA from a background corpus before binding & cleanup;
   fixes embedding anisotropy that makes cosine cleanup mushy. Cheapest accuracy gain.
   Ship precomputed stats (cold-start); refine online.
3. **Learned query→key** — HIGH / MED. Replace the key-name-matching hack with a
   learned projection (or tiny cross-attention) question→role. Fixes routing.
4. **Active overwrite** — proven (§1). Free rider; fold in regardless.
5. **Resonator / iterative cleanup** — MED. Modern-Hopfield / resonator readout with a
   temperature knob that actively suppresses the runner-up and factors binding
   crosstalk. Read-side sharpening; matters most under heavy load.
6. **Hybrid Belief+RAG** — the pragmatic production answer (Belief for mutable/aggregate
   state, RAG for large static lookup) — but not a crutch to dodge the bottleneck fix.

## 5. v6 — the experiment that proves a win

Ablation ladder on the same set (Qwen-1.5B, architecture fixed):
`crude baseline → +whitening → +learned query→key +overwrite → +soft-injection`
Report lookup AND continuity vs RAG at each rung, plus the **aggregate-inference test**
(§3) with a capacity sweep. **Win criteria:** continuity > RAG by ≥10 pts, lookup ≥ RAG,
AND Belief holds on aggregate-inference where RAG collapses — with soft-injection the
step that crosses the line.

## 6. Honest status
- Overwrite fixing continuity: **proven at the decode level** (48→100%); end-to-end TBD.
- Belief's categorical edge (aggregate inference): **structurally sound (high conf)**;
  that crude Belief beats RAG at it today is **low-med** until whitening + vector readout.
- The thing worth building is not a better lookup table. It's a memory that answers
  questions about itself as a whole — which no retrieval index can.
