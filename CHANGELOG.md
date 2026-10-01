# Changelog

All notable changes to this project will be documented in this file.

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
