# Changelog

All notable changes to this project will be documented in this file.

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
