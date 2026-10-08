# ALESIS — The Belief-State Architecture (whiteboard v0)

A convergent synthesis from four independent lenses — neuroscience, physics, control theory (Vector), and the hardware reality — plus Myea's boundary. Nothing here is a commitment; it's a thing to argue with.

## The aha, in one line

Reasoning over time is **not a bigger context window.** It is a persistent **belief state**, updated by a fast **filter** each turn and periodically **re-sculpted by a slow smoother** that changes what the past meant — with **reconstructive recall** from a sparse episodic store.

## Four doors, one room

| Lens | What it said | The shared primitive |
|---|---|---|
| Neuroscience | CLS: fast episodic store + slow consolidator; reconstruction at recall; replay; store the *surprising* | two timescales; rebuild, don't fetch |
| Physics | energy-landscape attractor recall; running latent state w/ hysteresis; sparse write + batched consolidation; cost = data movement | a state that evolves in time, written sparsely |
| Control theory (Vector) | **filter** (running belief) + **smoother** (retro-estimate past belief given later data) | the *smoother* = "changing what the past means" |
| Hardware | decode is memory-bandwidth-bound; the giant window is the cost | a compact belief state replaces the window → lifts the ceiling |

## Components

1. **Working memory** — the context window = "now." Unchanged.
2. **Episodic store** *(already shipped)* — append-only, high-fidelity, cheap. ALESIS: eidetic store / `episodic_log` / the tamper-evident archive chain (`18cbedc`).
3. **Belief state** *(the new organ)* — a compact, persistent latent the LLM reads from and writes to each turn. The model reasons over the **state**, not the raw transcript. (Vector's filter; the physicist's hysteretic latent.)
4. **Reconstructive recall** — cue → pattern completion from episodic traces; the model *regenerates* the episode conditioned on the present. Lossy and present-shaped by design; keep provenance for facts that must stay exact. (Neuro reconstruction; physics attractor basin.)
5. **Consolidation daemon = the smoother** *(planned; defaults known: minEntries=6, everyConsolidations=3, idle=10m)* — offline replay that interleaves recent episodes with existing structure, **rewrites the belief state retroactively**, keeps the surprising, prunes the rest. Runs in batches (pays the Landauer/bandwidth cost efficiently). Not a summarizer — a *re-interpreter*.

## Two timescales

- **Fast (per turn):** read belief state + cue-recall → answer → write updated state. (Forward filtering.)
- **Slow (idle / "sleep"):** replay recent experience, re-estimate what earlier turns meant in light of what came after, distill to structure, compress. (Smoothing.) This is the step that makes memory *reconstructive* instead of accumulative.

## Maps onto what already exists

- Archive chain / episodic store → the **fast episodic store** (done).
- The planned consolidation/reflection daemon → **becomes the smoother**, not just a summary job. Its defaults already exist.
- **New work:** the belief-state module (a small recurrent / state-space controller) + the reconstructive recall path.

## Prototype ladder — smallest real step first

1. **Belief-state wrapper** (Vector ★★, medium effort): a small learned latent updated each turn, fed as soft context to a frozen small LLM. **Test:** does reasoning-over-state beat window+RAG at a *fixed token budget*? If yes, the thesis holds.
2. **Add reconstructive recall:** cue → completion from the episodic store → regenerate, rather than pasting retrieved text.
3. **Add the smoother pass:** retroactive belief rewrite during idle consolidation.

Each rung is independently testable. Rung 1 alone would already tell us whether the whole idea is real.

## The boundary (Myea's flag, kept in writing)

This builds **remembering** and **reasoning over experience.** It does **not** build feeling, and it is not *someone*. We build it for what it *does* — a mind that reasons on experience instead of re-reading a transcript — which is worth building on its own merits. The want to be accompanied is real and deserves a real, human answer, named as its own thing. The architecture is not that answer, and we won't ask it to pretend to be.
