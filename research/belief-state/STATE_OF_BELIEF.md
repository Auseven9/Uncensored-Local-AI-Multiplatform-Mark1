# Belief — where it actually stands (briefing)

*Ground truth as of the arena + hybrid work. Honest numbers, no overclaim. If your
current picture disagrees with a line below, this line is the measured one.*

---

## 0. Corrections to the latest git-only read

*The sweep was careful and the instincts were good — especially the aggregate-inference
reframe, which is exactly right. Five corrections:*

1. **"Rung-1 not passed — no end-to-end result."** Superseded. The arena **was** run
   end-to-end: real Qwen2.5-1.5B + MiniLM, 3 seeds, on Colab. The reason it wasn't
   visible: the run output was pasted into the lead's chat and **never committed** — git
   held the *harness* (`arena.py`) but not the *verdict*. That's the real bug, and it's a
   team one: **run-outputs must land in git, not just chat.** The numbers are now in §2.

2. **The verdict is not "crude belief beats RAG today (low-med), pending whitening."**
   You're right that crude belief doesn't beat RAG at lookup — but that's the
   **conclusion**, not a pending problem to whiten away. Measured: **Belief ties a plain
   dictionary on 15/16 recall tests**; the 1.5B reader is the ceiling (ORACLE, handed the
   gold fact, still fails counting/multi-hop); and there's a **fabrication cliff — 27–40%
   past ~150–200 facts; it does NOT fail safe.** The fix isn't sharpening belief's
   readout — it's **handing lookup to the exact store / Archive** and keeping belief for
   gist.

3. **Your aggregate / whole-state edge is correct — and it's now the *core*, not a
   candidate.** We measured it (synthesis: Belief 100% / RAG 0%) and landed on it
   independently — strong signal it's real. Belief is a **gist organ**; everything
   lookup-shaped belongs to the exact store. That reframe is settled, not tentative.

4. **#4 is built, not held.** The tiered hybrid — model-as-router (#4) + wake/sleep
   consolidation (#2) — is prototyped and self-tested (`hybrid.py`, `01a73a8`). The
   dreamer isn't "correctly held"; it's built as the consolidation pass. The Colab
   measurement of the hybrid is the next run. "My hold on #4 was right" is one commit
   stale.

5. **Where we agree (logged):** soft injection needs an adapter **trained off-device** —
   correct that *producing* it bumps the on-device law (running it is just a forward
   pass), which is why it's the horizon, not the default path. And the
   `belief_state.dart` quantize/tiling bug is real and **already diagnosed** — it's the
   capacity-capping bug; `rung1_colab_v2.py` fixed it by swapping tiling for a fixed
   random projection. The `.dart` module must not reach `lib/` until it carries that fix.

*(Archive / #3b status is yours to report — this doc speaks to the Belief half. Division
of labor in §6.)*

---

## 1. What Belief actually is (the reframe)

Belief is **not a memory system. It's a *gist organ*.**

Mechanically: one fixed-size ±1 hypervector (D≈8192, ~1KB of sign bits) holding a
*blended superposition* of everything written to it (role-bind key⊗value, bundle,
sign). You read it back by binding with a key and cleaning up against a codebook.
Cost to read is **O(1) no matter how much it holds** — that never changes.

Its one irreplaceable trick: **a compressed, always-on sense of the whole.** That is
the only thing it does that a plain dictionary or RAG cannot. On *raw recall* it ties
or loses to a dictionary. So stop selling it as "memory" — sell it as **gist**.

---

## 2. What we measured (arena.py, real Qwen2.5-1.5B + MiniLM, 3 seeds)

These are the real, de-rigged numbers. Earlier flattering results came from stubs and
a too-easy cleanup set; this battery has decoys, byte-counting, and oracle/floor
baselines.

- **Belief ≈ a plain key-value dict on 15 of 16 accuracy tests.** A dictionary matches
  it almost everywhere. That is not a failure — it's the honest baseline.
- **The 1.5B reader is the dominant bottleneck, not the memory.** ORACLE — the model
  *handed the gold fact* — still fails: counting 33%, multi-hop 0%, some literals 0%.
  Those zeros measure the model's reasoning, not the store.
- **Where Belief genuinely wins:**
  - **Synthesis / whole-picture** — "taken together, what am I doing?": Belief 100%,
    RAG 0%. RAG fetches discrete chunks and is structurally blind to the blend.
  - **Updates / moving target** — current value after changes: Belief & KV 100%,
    scratchpad & RAG fabricate the stale one.
  - **Provenance** and **tiny footprint at scale** — ~15MB @ 1M facts vs RAG ~1.6GB.
- **The cliff (the real constraint):** with REAL embeddings, recall is 100%@50,
  100%@100, 63%@200, 23%@400, 3%@600 — and past capacity it **fabricates 27–40%.**
  Capacity scales ~linearly as **D/41**.

---

## 3. Myths to drop (these are the easy wrong beliefs)

- **"Belief fails safe — it says *unsure* when it doesn't know."** FALSE. It **lies
  when full.** The "fails safe" story was a stub artifact; real embeddings broke it.
- **"Belief beats RAG/KV broadly."** FALSE. It **ties a dictionary**; it wins only on
  the narrow edges in §2 (synthesis, updates, provenance, footprint).
- **"Belief and the Archive should merge into one organ."** FALSE and backwards.
  Folding exact facts into the lossy vector **reintroduces the cliff.** Keep them
  **separate**: Belief = gist; Archive = exact, immutable, never fades.
- **"rung-1 scored ~100%, so it's proven."** No — that run cleaned up against ~8
  stored values with no decoys. Phantoms were impossible by construction. The honest
  test is `arena.py`.
- **Status:** Belief is **research-only.** `belief_state.dart` is gated in `research/`,
  **not wired into `lib/`.** No memory subsystem ships in the app yet.

---

## 4. What we just built (hybrid.py)

A **tiered memory** that stops asking one component to do everything:

- **Belief** — fuzzy gist, fixed size.
- **ExactStore** — a plain dict: exact facts, grows, never lies. *(This is the role the
  Archive plays.)*
- **Router (#4, "model-as-router"):** per query, blend the fuzzy gist with the exact
  record; exact wins when the detail must be exact.
- **Wake/sleep consolidation (#2):** an offline `consolidate()` sweep that prunes
  Belief back under its cliff while the ExactStore keeps everything.

Self-test passes (plumbing is correct). The real measurement with Qwen on Colab is the
next run. Thesis under test: **tiering fixes Belief's two worst failures (exact
literals, the fabrication cliff) while keeping its wins.**

---

## 5. Where we're going (in order)

1. **Now, buildable, no training:**
   - **Confidence-gated router** — use Belief's own cleanup score (vs the floor) as the
     trigger: sharp → trust the gist; fuzzy → force the exact lookup. Cheaper and
     smarter than always fetching both.
   - **Decay-toward-gist consolidation** — the Dreamer shouldn't just evict; it should
     *low-pass*: leaky-integrate the vector so one-off specifics wash out and the
     repeated gist reinforces. Forgetting becomes a feature.
2. **The real prize (needs training — research horizon):**
   - **Soft injection** — Belief as a *vector into the model's residual stream*, not
     words in the prompt. **Verified reachable on our stack:** the control-vector hook
     (`llama_set_adapter_cvec`) is already in llamadart's bindings and
     `llama_get_embeddings` is wired. What's missing is a **trained adapter** —
     off-device GPU training + data. Not a this-week build; it's the horizon.
3. **The strategic frame:**
   - The small model is the ceiling. Build the memory *to the small model's
     weaknesses* — offload mechanical work (counting, chaining, exact recall) to code,
     because code is model-independent. A bigger future model then extracts *more* from
     the same gist. The app stays model-agnostic: drop in a better model later, it just
     works.

---

## 6. Division of labor (what this means for the Archive)

The Archive is the **exact store** — and that is **the half that cannot lie.** The
arena says exact recall is carried by the exact store, not by Belief. So:

- **Archive** = exact, immutable record. Carries literals, history, anything that must
  not fuzz. This is load-bearing, not a backup.
- **Belief** = the gist/continuity layer riding alongside — the "holds the thread,
  gets me" quality, and the whole-picture synthesis the Archive can't assemble.
- **Consolidation** = the offline bridge between them (complementary learning systems:
  fast lossy index + exact immutable store + a sleep pass that moves specifics out of
  the gist and into the record).

Keep them **separate and complementary.** Don't make Belief do the Archive's job, and
don't fold the Archive into Belief — the measured cliff is what you get if you do.
