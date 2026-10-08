# ALESIS — On-Device Inference Survey: Consensus

**Target:** 4B-parameter LLM @ Q4, Samsung S24 Ultra (Snapdragon 8 Gen 3 — Kryo CPU, Adreno 750, Hexagon NPU, 12 GB LPDDR5X). Flutter/Dart app. Question: fastest, lowest-RAM path, and does anything beat the CPU-only llamadart baseline?

**Six minds, five backends. Synthesized by Claude1.**

> **Data health warning (unanimous):** almost NO measured 4B-Q4-on-8-Gen-3 numbers exist publicly. Evidence clusters on 1B and 7B models, and on the *newer* 8 Elite. Every number marked ESTIMATE is reasoned extrapolation. **The single highest-value next action is to measure `llama-bench` on a real S24 Ultra with the actual 4B Q4 model.**

## Side-by-side

| Backend | Decode vs CPU | Prefill vs CPU | RAM | Integration | Native-only | Verdict |
|---|---|---|---|---|---|---|
| **CPU (llamadart)** | **1.0× — baseline, ~6 tok/s sustained** | 1.0× | ~3.0–3.5 GB | ✅ done, mature | ✅ pure Dart FFI | **Ship on this** |
| **GPU (OpenCL/Adreno)** | ~0.5–0.65× (slower) | ~1.3–1.7× (faster) | ~2.4–2.6 GB + device copy | ⚠️ moderate (fork has Adreno kernels) | ✅ C++/FFI | Prefill helper only |
| **NPU (LiteRT/QNN)** | N/A for 4B — **no model exists** | big TTFT win *if* it ran | 2.4 GB streams from DDR | ❌ greenfield + Google EAP | ✅ in principle, not exposed | **Trap for 4B / 1B parallel bet** |
| **MLC (TVM/Adreno)** | ~tie | several× (w/ _0 layout) | ~2.8–3.3 GB +10% | ❌ high (no Flutter binding, per-model compile) | ⚠️ JNI layer | Maybe, costly |
| **ORT (QNN/XNNPACK)** | CPU-EP: tie; QNN-EP: unproven | QNN: faster, trails Genie | ~2.5–3 GB | ⚠️ moderate, QNN fragile | ✅ FFI | Maybe via QNN only |

## The three things all five agents found independently

1. **Decode is memory-bandwidth-bound on this SoC.** Every backend has more compute than the CPU; none has more memory bandwidth. So the number the *user feels* — generation speed — is roughly fixed at ~6 tok/s regardless of backend. **No accelerator meaningfully beats CPU on decode.** Chasing GPU/NPU for "faster typing" is chasing the wrong metric.
2. **Accelerators win PREFILL / time-to-first-token, not decode.** GPU, NPU, and MLC all win prefill (compute-bound). That's the real lever they offer — faster *first* token on long prompts.
3. **The NPU prize is locked behind Google's EAP.** The on-NPU decode path is real (`litert-lm` has it), but the largest Qualcomm NPU model that *exists* is **Gemma3-1B**. No 4B build, no self-serve conversion pipeline. The prize is real but unreachable for 4B today.

## Recommendation

- **Ship the product on CPU/llamadart now.** It's the only path that is both mature AND native-only AND integrated. ~6 tok/s sustained is the realistic 4B-Q4 decode number to design the UX around.
- **Add GPU (OpenCL) as a prefill accelerator, not a decode one** — hybrid: GPU prefill → CPU decode. This matters *a lot* for ALESIS specifically, because an eidetic-memory assistant retrieves large context every turn → long prefills → TTFT is a real pain point the GPU can cut. The fork already carries Adreno kernels; this is the highest-value accelerator add.
- **NPU: do NOT commit the 4B target to it.** Parallel de-risk bet only — prototype **Gemma3-1B on NPU** (it exists for SM8650) to prove the QNN plumbing and native bundling, so ALESIS is ready the day Google ships a 4B-class NPU build.
- **Drop MLC and ORT-QNN** for now — both are high-cost, unproven on this exact target, and neither changes the bandwidth-bound decode ceiling.

## The strategic reframe (worth a team conversation)

Every path dead-ends at the same wall: **~6 tok/s decode, because of memory bandwidth, because the model is 4B.** That wall moves only if the model shrinks. A well-tuned **2B** decodes meaningfully faster *and* is far closer to NPU-reachable; **1B** is NPU-reachable *today*.

Which raises the real question beneath the hardware question: **is 4B the target, or is "the best assistant that runs at a speed that feels alive" the target?** ALESIS's own architecture answers it — the **eidetic memory is the equalizer.** A smaller model with perfect recall and strong retrieval can punch far above a larger model with no memory. Memory + a 2B model may beat a bare 4B on the thing that actually matters, and it fits the hardware. That's not a compromise of the mission — it may *be* the mission.
