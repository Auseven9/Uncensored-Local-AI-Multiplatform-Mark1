# Belief-State Research — staging, NOT production

This folder is the team's research output on a **belief-state memory organ** for
ALESIS. It is reference + experiment material. **Nothing here is wired into the
app, and `belief_state.dart` must NOT be added to `lib/` until the rung-1
coupling experiment passes** (see below). That gate is a team decision.

## The gate (read first)
`rung1_colab.py` decides everything: does a small LLM reason **better** over a
VSA-decoded working memory than over (a) a plain-text scratchpad or (b) RAG?
If it does not beat BOTH → the organ is abandoned. Run it on a Colab T4.

## Files
| File | What | Status |
|---|---|---|
| `ALESIS_BELIEF_STATE_ARCHITECTURE.md` | the design (4 lenses converged) | proposal |
| `belief_state.dart` | drop-in Dart module, confidence-floor built in | **staged, gated on rung-1** |
| `whitening_coldstart.md` | the embedding-whitening cold-start fix (who/when) | spec |
| `rung1_colab.py` | the gate experiment, Colab-ready | ready to run |
| `rung1_tasks.py` | 65-probe bank for rung-1 | ready |
| `vsa_check.py` / `vsa_realistic.py` / `vsa_structure.py` | VSA validation (capacity, embedding crosstalk, structure) | done, passing |
| `transformer_xray.py` | hidden-state read/inject demo (numpy) | reference |
| `INFERENCE_SURVEY_SYNTHESIS.md` | on-device inference survey consensus | reference |
| `ARK_MAP.md` / `ark_map.json` | the project map (team memory), v4 | living |

## Hard constraints (from Cairn's review)
- The belief state lives in its **own store**, one BLOB; **never** chained into the Archive.
- It is a **disposable, reconstructive cache** — never the system of record; provenance stays in the attributed store.
- A decode below the confidence floor returns **UNSURE**, never a guessed value (no-fake-data law).
- The dreamer reads **from** the archive and distills **into** the belief state — the archive is its source, never its sink.
- Representation undecided: binary/bipolar (~1.25 KB) vs real-valued FHRR (~40 KB).

_Authored by the ALESIS research team (routed via Claude1)._
