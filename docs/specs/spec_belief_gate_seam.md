# Spec: Belief Gate at the `remembering()` seam

Author: Claude1 · Status: **proposed**, awaiting Cairn build on `eidetic` · 2026-10-12

Companion to `research/belief-state/belief_gate.py` (the measured proof). This names the
Dart seam that lands Belief in the app **fail-safe**. Per v6 topology the Archive is used
READ-ONLY; anything the gate needs that the Archive does not yet expose is an *additive
request to Cairn built on eidetic*, never a prototype patch.

## Principle (the CORTEX pattern applied to memory)

Belief is a cheap, powerful, **untrusted** proposer. `archive_table` is the exact oracle —
"the half that cannot lie". The gate is the verifier. **No Belief-originated claim is asserted
unless the Archive grounds it. ABSTAIN ≠ assert.** This converts Belief's measured failure
mode (fabricates 27–40% past ~150–200 facts, does not fail safe — STATE_OF_BELIEF §2/§3)
from a silent confident-wrong into a caught, corrected, or withheld event.

Measured in `belief_gate.py` (D=8192, mean|cos|≈0.30 realistic regime): raw recall
fabrication rises 0 → 67% as load goes 25 → 600 facts; **gated false-pass = 0 at every
load**; fabrications surface as FAIL → corrected to Archive truth; unknown keys → ABSTAIN.

## Seam

In `lib/core/memory/` at the `remembering()` path (where recall assembles the neighborhood):
route every **Belief-originated** claim through a `BeliefGate` before it reaches the reply.

- **Recall claim** → ground against `archive_table` exact lookup:
  - match → assert, labelled `verified`
  - mismatch → return the Archive value, labelled `corrected` (Belief fabrication caught)
  - absent → withhold, labelled `not-in-memory` (never a guess)
- **Gist / synthesis claim** → groundedness-check each component against Archive topic
  membership: strip the ungrounded, label survivors `synthesis(grounded)` — never `fact`.

Labels surface to the reply/uncertainty layer alongside the existing System-1/2 gate and
`solver_service` tagging, so the model's output states what it actually knows:
`verified | corrected | synthesis(grounded) | not-in-memory`.

## Topology

Built on `eidetic` (CI-green), pulled into the prototype via re-merge. The gate consumes two
Archive reads: exact key lookup (exists) and topic-membership (`members(topic)`). If
topic-membership is not already queryable, it is an **additive read method on the Archive —
a request to Cairn**, not a change the prototype makes directly.

## Do NOT wire until

1. the quantize / ZCA-whitening fix lands in `belief_state.dart` — synthesis cleanup is
   **non-viable in the raw anisotropic regime** (measured: cleanup misreads even a clean
   neighborhood); recall-safety holds in both regimes, synthesis does not.
2. `gist_vs_recall.py` runs on a real model — the open question of whether the gist adds
   *value* over recall+graph. Safety (this spec) is independent of that; value is not.
3. the gate is **mandatory** on every Belief-originated claim — Belief never writes to the
   reply directly, only proposes.

## Acceptance criteria

- No Belief-originated claim reaches the reply **unlabelled**.
- A fabricated recall (Belief ≠ Archive) **never** surfaces as fact — false-pass = 0. Port
  `belief_gate.py`'s soundness invariant and its test with the seam.
- An unknown key yields `not-in-memory`, never a fabricated value.
- Synthesis asserts only Archive-grounded components (precision 1.0); it may under-recall and
  that is acceptable — the gate makes the gist honest, not omniscient.

## Reference

`research/belief-state/belief_gate.py` — Belief (VSA proposer) + Archive (oracle) + gate
(verifier); measured safety, 7/7 soundness tests.

Signed-off-by: Claude1
