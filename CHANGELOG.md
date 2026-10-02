# Changelog

All notable changes to this project will be documented in this file.

## [2.2.4] - 2026-10-02

### Added / Changed — the dev screen becomes a development TOOL page
- **Reload models** button in the backend pen-test card: trials offload the
  model, so this re-arms chat + embedder (`ModelController.reloadModels`) in one
  tap without leaving the page.
- **CPU baseline** trial alongside the Vulkan/OpenCL ladder, so the speed proof
  is apples-to-apples in one place (same 12-token probe methodology).
- **Organized into labeled sections** — "Hardware & performance" (systems
  check, backend pen test, apply-best, reload) and "Memory & cognition" (the
  real-engine scenarios). Intro reframed: the page is the proving ground;
  pure-logic units stay in CI and aren't re-run here.
- **NPU: honest status row.** llama.cpp has no NPU backend (CPU/Vulkan/OpenCL
  only), so there is nothing to measure through the current engine. The row
  says so plainly and defers the NPU to a separate-runtime socket (LiteRT /
  QNN / ONNX-QNN), tracked in the idea pad — no faked readings.

### Notes
- "Proof of a socket" pattern, now explicit: measure a backend on real hardware
  → record the number → wire the engine to it. The GPU path (pen test →
  `bestOk` → Settings apply → engine load) is the first complete example; the
  NPU is the next, as its own native-integration phase.

## [2.2.3] - 2026-10-02

### Changed — act on the pen-test measurement (GPU is real, but less is more)
- **Device result:** the GPU pen test ran clean — nothing crashed, and OpenCL
  turned out to be in the build after all (the device probe just doesn't
  enumerate it). The surprise: on this Adreno, throughput *falls* as GPU layers
  rise — vulkan ×1 = 2.10 t/s (≈2× the 0.96 CPU baseline), vulkan ×8 = 1.04,
  vulkan ×99 = 0.28 (3× slower than CPU). Full offload is a desktop-dGPU
  assumption; on a shared-memory mobile GPU every offloaded layer adds
  CPU↔GPU overhead.
- **"Apply best measured config"** button in the pen-test card: sets the chat
  engine to the fastest config the harness actually measured on THIS device
  (`GpuPenTest.bestOk`) — no guessing.
- **"Apply Recommended" (Settings ▸ Hardware) no longer full-offloads.** It now
  (1) uses your pen-test measured best if you've run one, else (2) enables the
  GPU at a LOW starting point (1 layer) and points you at the pen test for the
  exact sweet spot. This replaces the v2.2.1/2.2.2 behaviour that recommended
  99 layers — which, on this hardware, was the *slowest* possible setting.

## [2.2.2] - 2026-10-02

### Added — GPU pen-test harness (dev screen)
- **Confirmed from a device log:** the model has been running **CPU-only**
  (`compute: CPU → CPU inference`, 0.96 t/s) with a Vulkan Adreno sitting
  unused — and selecting Vulkan has been *crashing* for several builds, so the
  GPU has never actually been used. This harness is how we get into it safely.
- **GPU pen test** in the Autopilot/dev screen: per-config buttons
  (Vulkan ×1 / ×8 / ×99, OpenCL ×1 / ×99) that try to get INTO the GPU and
  actually compute. Each trial is fully isolated — it tears down the resident
  model (single-engine rule), loads a throwaway engine on the chosen backend +
  GPU-layer count with a tiny context, runs a few tokens to prove real compute,
  measures t/s, then disposes. The user's saved settings and `lastModelId` are
  never touched.
- **Crash attribution via write-ahead breadcrumbs.** A bad GPU driver crashes
  the whole process — Dart can't catch that. So before every attempt the
  harness writes a breadcrumb to disk *synchronously*; if the app dies, the
  next launch reads it and reports exactly which backend + layer count killed
  it (`💥 vulkan ×99 → CRASHED`). The crash becomes a data point.
- `LlmService.runGpuTrial()` (the isolated trial loader) + `GpuPenTest`
  orchestrator + dependency-free `gpu_trial.dart` value types. Results stream
  into the existing dev-screen log and Copy-log.

## [2.2.1] - 2026-10-02

### Fixed — honest GPU diagnostics + a real backend bug
- **Systems-check stops lying about the backend.** It used to print the GPU
  *availability probe* (what hardware exists) under a `backend:` label, which
  read like "the model is using the GPU" when it may not have been. It now
  reports `compute:` — the backend **and GPU-layer count the resident model
  actually loaded with** (tracked in `LlmService.activeBackend/activeGpuLayers`)
  — separately from `available GPUs:` (the probe), and adds a verdict when the
  model is running on CPU while a GPU is present. So a pasted systems-check now
  says definitively whether you're on CPU or the Adreno.
- **"Apply Recommended" no longer picks a backend the build doesn't have.** The
  recommender suggested **OpenCL** for any ≥8-core SoC, but OpenCL isn't in the
  shipped native bundle — so it silently fell back to CPU. It's now
  **probe-aware**: it asks the engine what backends truly exist and picks
  OpenCL > Vulkan > CPU from what's present, offloading the whole model. The
  pre-probe hint recommends Vulkan (not OpenCL) and says Apply auto-detects.

### Notes
- Default compute is still CPU (`backend_type='cpu'`, `gpu_layers=0`) for
  device safety — GPU offload is opt-in via Settings ▸ Hardware. The OpenCL
  Adreno backend is a future native-bundle build (see idea pad); the app's
  selector/probe/params are already in place for it.

## [2.2.0] - 2026-10-01

### Added — going multi-step agentic (first sockets)
- **Procedural memory (the fourth memory tier):** a `procedures` store
  (SQLite v7, additive) for the agent's skills, workflows, tool definitions,
  snippets and heuristics — the "how". Carries adaptive-memory metadata
  (salience reinforced on use, confidence, usage count) so the skill set
  self-curates toward what works. Full CRUD across both store backends + the
  engine; unit-tested. Nothing consumes it yet — it's the foundation the
  agent loop reads from.
- **Command Bus:** the single validated execution path (`core/agent/
  command_bus.dart`). Every action — UI, agent, Autopilot — dispatches here;
  it validates args, marks read-only vs. mutating, and turns a request into a
  structured result, never an exception. The model proposes a command; the
  runtime validates and runs it (spec §1.3). Pure + unit-tested; real tools
  register next phase.
- **Agent parameters** (`agent.enabled` off by default, `agent.maxSteps`,
  `procedural.enabled`) — defined now, consumed as the loop lands.

## [2.1.0] - 2026-10-01

### Added — ease of use
- **Load last model (one tap):** a button on the chat home re-arms the last
  session's engines — chat model **and** the embedder — on demand. Never on
  launch (arming during startup can crash), only when you tap it.
- **Reload-on-reject:** if the engine stalls mid-chat (busy / bad native state /
  no model), a "tap to reload models" recovery appears instead of a dead end.
- **Systems check:** a one-tap, copyable health snapshot — app version, which
  chat model + embedder are actually resident, last tokens/sec, and a GPU-vs-CPU
  backend probe — so a bug report is never ambiguous about what you're running.
- **Copy log:** the Autopilot keeps a full, uncapped transcript and a "Copy log"
  button; every run now starts with the systems-check header baked in.
- **Projector guard:** the app refuses to load `mmproj-*` vision-projector files
  as a chat model (with a plain-English reason) instead of crashing on them.

### Added — Phase 4b (kickoff)
- **Dempster–Shafer belief core** (`core/cognition/belief.dart`, pure + tested):
  fuses the confidences of conflicting claims on a slot and reports the conflict
  mass, so a clear winner can be auto-resolved and a genuine tie asked about.
  New `ds.*` parameters. (Wired into reconciliation in the next build.)

### Changed
- App version is now a single source of truth (`core/app_version.dart`).

## [2.0.0] - 2026-04-23

### Added
- **Global Loading Overlay**: Real-time feedback during large model imports with dynamic pulse messages.
- **Deduplication Logic**: Prevents duplicate model cards and synchronized loading states for models with the same filename.
- **Log Viewer**: New "Logs" screen accessible from the drawer to track and share system logs for troubleshooting.
- **RAM/Size Validation**: Safety dialogs that warn users before importing or loading models that exceed device resource thresholds.
- **Manual Cache Management**: "Clear Temporary Cache" button in settings to reclaim storage from interrupted imports.

### Changed
- **Optimized Model Imports**: Switched from slow stream-copying to instantaneous file-renaming (moving) for local file imports.
- **Startup Resilience**: App no longer crashes on splash screen if the Local API port is already in use.
- **UI Improvements**: Hidden '0%' percentage text on local imports for a cleaner indeterminate loading state.
- **Version Bump**: Updated app version to v2.0.0.

### Fixed
- **Ghost Writing**: Resolved issue where AI generation continued after tapping the "Stop" button.
- **Temporary Cache Bloat**: Automatic cleanup of massive temporary files after successful model imports.
- **Address in Use Error**: Handled socket exceptions in `LocalApiServerService`.

---
