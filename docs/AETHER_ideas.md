# AETHER — Idea Pad

A running capture of ideas, outside assessments, and design provocations for
AETHER. This is a scratch/thinking space, **not** the canonical spec — the spec
we execute from is [`AETHER_architecture.md`](AETHER_architecture.md). Entries
here are dated, newest first. External reviews are recorded as *data to weigh*,
not doctrine; where an entry maps onto real build work, it's cross-linked to the
spec's roadmap (§5) or captured directions (§5b).

---

## 2026-10-02 — The dev page is the proving ground; sockets are earned by measurement

**Direction (user):** make the Autopilot/dev screen a real development TOOL page
— build automated tests for everything, organized nicely; and use it to produce
PROOF (readings, numbers) that we can touch each compute backend — "proof of a
socket so we can wire it in for the assistant to actually utilize", chasing
speed + stability because that unlocks higher phases.

**The pattern, named:** a *socket* is earned, not assumed — measure a capability
on real hardware, record the number, then wire the runtime to it. The GPU
socket is the first complete example and the template:

> pen test measures backend×layers → t/s (`GpuPenTest`) → `bestOk` picks the
> device's fastest → Settings "Apply best measured" / "Apply Recommended"
> writes it → the chat engine loads with it. Measured → wired → used.

**Dev page layout (v2.2.4):** two kinds of proof, plus a CI note.
- **Hardware & performance** — systems check, the backend pen test (CPU
  baseline + Vulkan/OpenCL ladder), apply-best, reload-models (trials offload
  the model; one tap re-arms without leaving the page).
- **Memory & cognition** — the real-engine scripted scenarios (need the live
  model + isolated DB).
- **Pure-logic units stay in CI** (command bus, belief math, procedural CRUD,
  dynamics, uncertainty) — fast, deterministic, run every build; not re-run
  on-device. Working agreement: **every new capability ships with its proof**
  — a dev-page scenario if it needs the engine, a CI unit test if it's pure.

**NPU — an honest wall, and a real future socket.** The user wants NPU proof
too. Hard fact: **llama.cpp has no NPU backend** — GGML is CPU/Vulkan/OpenCL
only, so there is nothing to measure through the current engine, and a faked
NPU reading would betray the whole measure-don't-guess ethos. The Hexagon NPU
is reachable only through a *different* runtime: Qualcomm QNN, LiteRT (TFLite)
with the QNN/Hexagon delegate, ONNX Runtime's QNN execution provider, or
MLC — all of which are already forked into this account (`litert-lm`,
`litert`, `litert-lm-native`, `onnxruntime`, `mlc-llm`). So the NPU socket is a
**separate engine integration**, not a backend flag, and it collides with the
single-engine rule: it would be an *alternative* engine (a swap) or a *second,
small* model (a draft model for speculative decoding, or the embedder on the
NPU while the chat model stays on GPU) — never a second full LLM engine
resident alongside llama.cpp. Proof-of-socket = a LiteRT/QNN probe that loads a
tiny model on Hexagon and reports t/s, surfaced on this same dev page next to
the GPU ladder. Substantial native work; its own phase. For now the page says
so plainly instead of pretending.

**Why speed is load-bearing:** the higher phases (the multi-step ReAct loop,
System-2 sub-agents, the live DAG) are impractical at ~1 t/s. Every t/s the
pen test buys back (vulkan ×1 ≈ 2×; a future NPU draft model could be more)
directly widens what the agent can afford to do per turn. Speed is not polish
here — it's the budget the cognition spends.

## 2026-10-02 — GPU verdict: CPU wins. The honest end of the backend chase.

With the probe finally measuring the **real** config (`kv=q8_0, flash=on`,
steady-state 23-token decode), the device gave a clear, humbling answer:

| config (real cfg, steady-state) | t/s |
|---|---|
| **cpu ×0** | **1.75** ← fastest + most stable |
| vulkan ×1 (first run) | 1.70, degrading 1.70→1.50→1.31→1.18 (thermal) |
| opencl ×1 | 1.21 |

**For gemma-3-4b Q4_0 on Adreno 750, the GPU does not beat the CPU.** CPU ties
Vulkan's best single run, and Vulkan *throttles* under back-to-back load while
CPU holds. CPU also has no shader-compile warm-up, no thermal cliff, and no
GPU-driver crash risk. `bestOk` / "Apply best measured" now correctly selects
CPU. The app's original conservative CPU default was right all along.

**What killed the hypothesis:** honest measurement. The whole GPU arc
(v2.2.1→2.2.6) was driven by "turn on the GPU for a big speed-up" — my idea —
and the pen test disproved it rather than letting a slower config ship. The GPU
*socket* is proven (we can touch Vulkan/OpenCL and get real numbers); it just
isn't *faster* here. Keep the socket for a future model/quant that might benefit;
stop tuning the backend for this one.

**Revised speed reality + levers (locked):** ceiling ≈ **1.75 t/s on CPU**.
GPU-backend tuning is a dead end for this workload. The only real speed-ups
left are (a) a **smaller/faster model or quant**, or (b) the **NPU** (LiteRT/QNN
— a separate native engine, its own phase). Not the GPU.

**Top of the backlog now (above new features):** the **consolidation OOM**
(stability) — the one real bug the crash log surfaced. After that, the
cognition roadmap (agentic phases, the node viewport) proceeds at the honest
~1.75 t/s budget, with the NPU as the standing bet for a real speed jump.

## 2026-10-02 — The crash log: Vulkan cold-start, probe≠reality, and consolidation OOM

A crash-surviving device log (real multi-turn chat on vulkan ×1) corrected the
rosy pen-test picture and exposed the real stability risk. Four findings:

1. **Vulkan shader cold-start.** First generation after a load = ~89s for 48
   chars; the *next* turn = 3.5s for 59 chars, same prompt length. That cliff is
   the Adreno Vulkan driver compiling compute shaders on first use — a one-time
   cost that was landing on the user's first chat message. Fix (v2.2.6): a
   1-token warm-up in `loadModel` pays it behind the loading screen. Real
   elimination across loads needs a persistent pipeline cache (a llamadart/ggml
   feature — future).
2. **The probe lied because it measured a different config.** `runGpuTrial`
   hardcoded `flash=auto, kv=f16`; the real chat ran `flash=enabled, kv=q8_0`
   (the user picked q8_0 KV to save RAM, which forces flash on). So the probe's
   1.95 t/s was for a config never used. Fixed to read the real settings. Open
   question worth measuring now: is `q8_0` KV actually slower than `f16` here?
   The honest probe can answer it (set kv=f16, re-run, compare) — RAM vs speed.
3. **Warm real-chat speed is ~1 t/s and variable** (turn 2 ~4 t/s, turns 3–4
   ~1, degrading with context length + thermal) — not the ~2 the old probe
   implied. The warm-up fixes the first-turn cliff; the sustained number is what
   it is until a faster quant or the NPU.
4. **Consolidation is the crash.** A session was OS-killed ~72s into a
   consolidation generation (no error line = OOM, not a Dart throw) — the long
   gen on top of the resident 4B + embedder spikes memory. Already capped
   (maxTokens 512), gated, and **resumable** (items marked consolidated only on
   success, so the batch survived and the next session recovered it, `+2
   stored`). Next stability work: shrink consolidation's live memory (smaller
   effective context / tighter input batch), and a crash-loop guard (back off a
   batch that keeps killing the app) so a poison batch can't brick startup.

Cross-link: the GPU socket is proven + wired; these are the follow-through on
making it *stable and honest* in real use. Consolidation OOM is now the top
stability item above new features.

## 2026-10-02 — Challenge the backend trace: measure first, then turn the GPU on

**Direction (user):** "We can challenge that gpu backend trace as well. Always
optimize."

**What investigation turned up (and a correction I owe):** the systems-check
`backend:` line was reporting `probeGpuDeviceLines()` — which lists the GPUs
that *exist*, not the one the model is *using*. So "backend: vulkan · Adreno
750" never meant the model was on the GPU. Meanwhile the real defaults are
`backend_type = 'cpu'` and `gpu_layers = 0` (zero layers offloaded = CPU
inference). Unless the user tapped "Apply Recommended" or hand-set a GPU backend
+ raised the layer slider, **the 4B has very likely been running on the CPU** —
which is the first-order explanation for ~1 tok/s. My earlier "the GPU is
engaged, it's just slow Vulkan" claim was therefore probably wrong; the honest
move is to make the diagnostic report what's *active*, not what's *available*,
and let the next run settle it with data.

**A real bug found alongside it:** `_detectBestConfig()` recommended **OpenCL**
for any ≥8-core SoC — but OpenCL isn't in the shipped native build (the probe
shows no OpenCL device), so "Apply Recommended" was selecting a backend that
silently falls back to CPU.

**Shipped (v2.2.1), cheap + safe + CI-verifiable:**
- Systems-check now prints `compute:` (the backend + GPU layers the resident
  model actually loaded with — tracked in `LlmService.activeBackend/
  activeGpuLayers`) separately from `available GPUs:` (the probe), plus a
  verdict when CPU-bound while a GPU exists. The diagnostic stops lying.
- "Apply Recommended" is now **probe-aware**: it asks the engine what backends
  truly exist and picks OpenCL > Vulkan > CPU from what's present, offloading
  the whole model. No more recommending a backend the build lacks.

**The OpenCL native track (the deep lever, not yet pulled).** llamadart ships
each platform's native library as a **prebuilt bundle** its build hook downloads
(`hooks.user_defines.llamadart`: a native *tag* / *repository* / *path*, with
`llamadart_native_backends` selecting the variant). There are no `opencl` /
`vulkan` strings in the hook because the backend set is baked into the bundle.
So OpenCL-on-Android means: build an arm64 llama.cpp bundle **with the GGML
OpenCL (Adreno) backend** in `llamadart-native` (using the forked
`opencl-icd-loader` + `opencl-headers`), publish it / point the app's native
user-define at it, and declare `android-arm64: [vulkan, opencl]`. Cross-repo,
device-verified only — but the entire **consumer** side (backend selector, GPU
probe, `preferredBackend`/`gpuLayers` params, the layers slider) is already
built and waiting. On Adreno, OpenCL is frequently 2–3× Vulkan for Q4_0.

**Optimization order (locked):** (1) measure — truthful systems-check ✅;
(2) turn on the GPU that's already there — Vulkan + full offload, one tap, then
reload + paste a systems-check so we see real Adreno t/s; (3) only then weigh
the OpenCL native-bundle build against the measured Vulkan number. Measure,
don't guess.

**Update (v2.2.2) — measurement is in, and it reframes the problem.** The
device systems-check confirmed it: `compute: CPU → CPU inference`, 0.96 t/s,
Vulkan Adreno present but unused. So step (1) did its job — we now *know* it's
CPU-only, not a slow GPU. But step (2) ("just turn Vulkan on") is blocked:
the user reports Vulkan has been **crashing the app for several builds**, which
is why they've stayed on CPU. So the real obstacle isn't *selecting* the GPU —
it's *getting into it without the process dying*. New lever, shipped v2.2.2: a
**GPU pen-test harness** in the dev screen that trial-loads the model on
Vulkan/OpenCL at escalating GPU-layer counts, each attempt isolated and
**write-ahead-breadcrumbed** so a hard native crash (uncatchable in Dart) is
attributed to the exact backend+layers on the next launch. That turns the
crash into a reproducible data point and is the groundwork for either fixing
the Vulkan path or justifying the OpenCL native-bundle build. Revised order:
(1) measure ✅ → (2) **pen-test into the GPU, find the config that survives (or
prove none does)** → (3) fix Vulkan offload or build the OpenCL bundle, guided
by what the pen test shows.

**Update (v2.2.3) — the pen test ran, and it rewrote the plan.** Nothing
crashed. All five configs loaded and computed, and OpenCL turned out to be IN
the build (the device probe simply never enumerates it — a probe bug, not a
missing backend; two of my earlier calls were wrong). The real finding is a
counter-intuitive throughput curve on this Adreno 750 + Q4_0 (12-token probe):

| config       | t/s  |
|--------------|------|
| vulkan ×1    | 2.10 | ← fastest, ~2× the 0.96 CPU baseline
| opencl ×1    | 1.80 |
| opencl ×99   | 1.35 |
| CPU          | 0.96 |
| vulkan ×8    | 1.04 |
| vulkan ×99   | 0.28 | ← slowest, 3× worse than CPU

So **more GPU layers = slower** here. Full offload ("99 layers", the desktop-
dGPU idiom) is the *worst* setting on a shared-memory mobile GPU — every
offloaded layer adds CPU↔GPU sync/dequant cost that outweighs the compute win.
Vulkan is fast at low offload but collapses as layers climb; OpenCL is flatter
but lower-peak. **Measured winner: vulkan ×1.** Consequences shipped v2.2.3:
"Apply best measured" (data-driven, from `GpuPenTest.bestOk`) and an
"Apply Recommended" that starts LOW instead of full-offloading. Open question
to confirm on-device: does vulkan ×1's ~2× hold over a *sustained* real chat
(longer context, growing KV cache), or is it a short-probe artifact? If the
peak stays ~2 t/s, the next real lever for speed isn't layer-count tuning — it's
a faster quant or a properly Adreno-kernelled OpenCL build. Measure, then
decide.

## 2026-10-02 — The glass box: a live node graph for the cerebellum

**Direction (user):** visualize the agent's execution as an interactive node
editor / live DAG — watch payloads traverse nodes and wires as the agent
reasons and acts, and be able to *sever a wire* to halt a runaway reflex loop.
Explicit, locked requirement: **"We want to see all active branches."** When
work fans out, the viewport shows the whole active frontier — not a single
"primary path."

**Honest grounding against the single-engine constraint (§0.3, §5b).** AETHER
runs one native LLM engine at ~1 tok/s. That rules out parallel *reasoning*:
there is no "three model calls at once." The true topology of the agent DAG is
therefore:

> a **sequential reasoning spine** — one cerebrum (LLM) node active at a time —
> where each step may **fan out to parallel deterministic tool nodes** (the
> Command-Bus handlers: recall, get-time, read open-questions — fast Dart, no
> model) that rejoin before the next reasoning step.

So the genuine parallelism lives in the **cerebellum** (the deterministic tool
fan-out), not the cerebrum. "Show all active branches" is exactly right, and
it's the tool fan-out that makes it meaningful: auto-fit the full active
sub-graph, light-trace every in-flight edge. The viewport must never imply the
engine is reasoning in parallel — that would sell a lie the hardware can't tell.

**Decisions locked:**
- **Show all active branches / auto-fit.** The viewport frames the entire
  active frontier and scales to fit; no hidden branches, no privileged path.
- **Sever = cancel.** Snipping a wire maps onto the real preemption we already
  have (InferenceWorker cancel / command cancellation) — a true manual override
  that stops an in-flight step before it executes, not a cosmetic cut.
- **It renders a trace; it does not drive.** The viewport is a read-out of an
  execution trace the agent loop *emits*. The loop (runtime) stays the single
  source of truth; the graph is a window, never a second controller.

**Honest sequencing.** You cannot visualize a DAG that isn't executing yet. The
nodes only exist once there are tools (PB) and a loop that runs them (PC). So:

1. **PB** — register the first read-only tools on the Command Bus (the nodes).
2. **PC** — the gated ReAct loop that runs them, emitting a structured trace
   (reasoning spine + tool fan-out + per-node status: pending / running / ok /
   failed / severed). The trace model is the data contract the viewport reads.
3. **Viewport** — render that trace live: all active branches, payload traces,
   sever-to-cancel, plus the consolidation trace (Working Memory → Knowledge
   Graph). Built incrementally with the user's eyes — it's the single largest
   custom UI in the app and lands piece by piece, not blind in one shot.

Cross-link: spec §4f agentic phase plan (PA landed → PB → PC → PD → PE). The
viewport is a consumer of the PC trace; file it as the visualization layer that
rides on top of PC, not a prerequisite for it.

## 2026-09-30 — Working principle: build from the pad, and make the memory itself adaptive

Set by Dylon: *"we should be implementing from the idea pad on our way up the
phases. It's okay to adapt. Actually adaptability should be built into the
memory. Quality is the aim, invention is the driver and optimization is the
thrust."*

Two commitments, both now standing:

1. **The pad feeds the phases directly.** It isn't a someday-list. Each phase
   pulls the relevant friction points / strategies from it and adapts them to
   what the device actually does. First proof, shipped today: the context
   window is no longer hard-capped (it defaults to the model's full trained
   ceiling, user-lowerable) and background consolidation now *yields the single
   engine to a live user turn* instead of colliding with it. Both came straight
   out of Friction #2 (interactive latency vs System 2) and Strategy #4 (defer
   System 2 to idle) in the entry below — a ~1 tok/s model cannot let a minutes-
   long background pass hold the one engine while the user is trying to talk.

2. **Adaptability is a property of the memory, not a feature bolted on.** The
   system should tune *itself* with use rather than relying on hand-set
   constants forever:
   - Salience that rises with reinforcement and falls with disuse (Ebbinghaus,
     spec §5 Phase 3) — the flat `0.4` I assigned raw episodic turns, and the
     hand-set recall weights (`wRelevance`/`wSalience`/`wRecency`), are
     explicitly *placeholders* for values the engine should eventually learn
     from which recalls actually got used.
   - Consolidation that learns which relation types it gets right (feeds the
     extraction-floor problem below), and prunes/dampens attractors so the same
     few facts don't dominate the budget (Friction #3).
   - The recall ranker exposing *why* each item surfaced (source + score),
     so the system — and later the user — can see and correct its own choices.

   The through-line: quality is the aim, invention drives, optimization is the
   thrust. Build it so it moves *itself* toward better recall.

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
