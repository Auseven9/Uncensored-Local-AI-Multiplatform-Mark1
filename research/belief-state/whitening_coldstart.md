# Whitening Cold-Start — spec (Cairn's open risk #2)

## The problem
VSA crosstalk is low only when fillers are near-orthogonal. Real LLM embeddings are
anisotropic (mean |cos| ≈ 0.12 in our test); **whitening** decorrelates them
(back to ≈ 0.02). But whitening needs a **covariance matrix `C`** estimated from a
corpus of embeddings, and then `W = C^(-1/2)` (ZCA). Two failures:

1. **Cold start.** A fresh install has ~no embeddings → no reliable `C` → crosstalk
   is *worst exactly when the memory is smallest and every fact matters most.*
2. **Drift.** As the user's topics move, the old `C` goes stale and `W` under-whitens
   the new distribution.

## The fix (three layers)

### 1. Warm start — ship a precomputed `W₀`
Fit `C` **offline** on a large general corpus of the *same embedding model's* outputs
(the exact model ALESIS ships). Bake `W₀` into the app as an asset (~`d²` floats for
embedding-dim `d`≈1–3k → a few MB; or a low-rank factor to shrink it). Day-one
whitening is "good enough," no user data required. **Owner: build-time, shipped.**

### 2. Online covariance — Welford, cheap, always on
Maintain a running mean + covariance incrementally as embeddings arrive
(Welford's algorithm, O(d²) per update, no stored history):
```
count += 1
delta  = x - mean;  mean += delta / count
C     += outer(delta, x - mean)      # accumulate; divide by (count-1) when read
```
This is tiny and continuous. It does NOT refit `W` live (that's the expensive part).

### 3. Periodic refit — the dreamer owns it
`W = C^(-1/2)` (eigendecomp of `C`) is the only costly step. **Assign it to the
dreamer/consolidation daemon**, which already wakes on idle and already touches
embeddings. Refit when EITHER:
- a drift trigger fires: `‖mean_now − mean_at_last_refit‖ > τ` (distribution moved), OR
- `count` has grown by a factor (e.g. ×1.5) since last refit (enough new data).

Blend to avoid jumps: `W_new = (1−β)·W_old + β·C_now^(-1/2)` (β≈0.5), or re-whiten
lazily. Keep `W₀` as the floor so a bad refit can't make it worse.

## Who / when — the answer to Cairn's question
| Layer | Who | When |
|---|---|---|
| `W₀` warm start | build pipeline | shipped in the app |
| running `C` (Welford) | belief-state write path | every embedding, always |
| refit `W = C^(-1/2)` | **the dreamer** | on drift trigger or ×1.5 data growth |

## Honest caveats
- `W` is `d×d` in embedding space (before projecting to hyperdim `D`). For `d`≈2–3k
  that's ~16–36 MB at float32 — fine on disk, do the eigendecomp off the hot path.
- If sign-quantizing embeddings to a **binary** VSA, whiten *before* taking the sign.
- This whole spec is moot if **rung-1 fails** — don't build it until the organ earns in.
