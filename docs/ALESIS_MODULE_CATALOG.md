# ALESIS — The Module Catalog ("Alesis for Dummies")
### Every piece, named · grouped by what it does · with the wiring so you can draw every connection

> **What this is.** A dictionary of *every module and subsystem* in ALESIS, organized into umbrella
> categories by function. Each entry is a "card" with the same fields, including **who calls it (← In)**
> and **what it calls/writes (→ Out)** — those two lines ARE the arrows you draw on your diagram. Use the
> categories as your columns/swimlanes and the ← / → lines as the connections between cards.
>
> **Status key:** ✅ built & shipped · 🆕 agreed / planned (on the roadmap) · 💡 shelved idea (pinned, not committed)
> **Layer key:** FE = front-end (UI) · BE = back-end (Dart logic) · NATIVE = Kotlin/Android · DATA = storage
>
> Grounded in the source at `3.14.0-beta+33`, schema `v7`, branch `claude/eidetic-local-ai-dojo-shdbx2`.

---

## 0 · The lineage spine (fork → now → planned → shelved)

Read top to bottom; this is the order it actually happened.

```
INHERITED BASE  "Portable AI v2.0.0"  (Apr–May 2026)
  └─ Flutter chat app · LlmService · Local OpenAI API server · settings · model downloader
         │  (the fork + rebrand you started from)
         ▼
THE MIND GRAFTED  "Eidetic Dojo"  (Sep 29 2026 → Oct 1)
  └─ InferenceWorker · GBNF engine · 3-tier SQLite memory · Dojo rooms · logging · health
  └─ then: epistemic graph · meaning/embeddings · decay · uncertainty · attribution · Living Memory 2.0
         ▼
AGENCY + VERDICT  (Oct 1–2)
  └─ v2.1 ease-of-use · v2.2.0 procedural memory + Command Bus (first sockets) · v2.2.1–6 GPU pen-test → "CPU wins"
         ▼
THE SENSES  Monitor tab  v3.0.0 → v3.14.0  (Oct 3–5)
  └─ native sensor suite · platform channels · capability board · live camera   ◀── LAST BUILD PUSHED
         ▼
AGREED / PLANNED  (the road to ALESIS)
  └─ A Archive · B Dreamer · C Senses→Memory · D Sleep daemon · E Self-model · F Inspection · G Rails · H First Boot
  └─ + Integrity panel (owner audit)
         ▼
SHELVED IDEAS  (pinned, not committed)
  └─ SQLCipher encryption · system-audio "hear what I hear" · the Solver (neurosymbolic reasoner) · agency layer
```

---

## How to read a card

```
### <Module name>   <✅/🆕/💡>
- Is:         one plain-English sentence — what it is / does.
- Layer/Where: FE|BE|NATIVE|DATA · the real file or table
- Key bits:   the real classes / methods / APIs / calls inside it
- ← In:       who calls or feeds it   (draw an arrow FROM each of these INTO this card)
- → Out:      what it calls / writes   (draw an arrow FROM this card TO each of these)
- Era:        when it was built in the lineage
```

---

# A · FOUNDATION  (the substrate everything runs on)

### Flutter + Dart ✅
- Is: the app framework + language. All UI and all Dart logic.
- Layer/Where: FE+BE · whole `lib/` tree
- ← In: the OS · → Out: everything
- Era: inherited base

### GetX (dependency injection + routing + state) ✅
- Is: the "wiring harness." Creates each service once and hands the same instance to everyone; also does routing and reactive state.
- Layer/Where: BE · `lib/bindings/app_bindings.dart`, `lib/routes/app_routes.dart`
- Key bits: `Get.put` / `Get.lazyPut` / `Get.find` · `GetxService` · `GetPage`
- ← In: `main.dart` at boot · → Out: instantiates & connects every module in B–I
- Era: inherited base

### llama.cpp via `llamadart ^0.8.24` ✅
- Is: the C++ inference engine (runs GGUF models) + its Dart wrapper. Also provides GBNF grammar support.
- Layer/Where: BE(native lib) · used by `LlmService`, `EmbeddingService`
- Key bits: `LlamaEngine` · `LlamaBackend` · `loadModel()` · `generate()` · `GenerationParams`
- ← In: LlmService, EmbeddingService · → Out: the loaded GGUF model file
- Era: inherited (bumped to 0.8.24 at Eidetic genesis for GBNF)

### sqflite (SQLite) ✅ · Hive ✅
- Is: the two storage engines. sqflite = the structured memory DB; Hive = fast key-value for chats/settings.
- Layer/Where: DATA · `eidetic_store_io.dart` (sqflite) · `chat_storage_service.dart` (Hive)
- Key bits: `openDatabase` · WAL mode · `Hive.openBox` · type adapters
- ← In: the memory engine (sqflite), ChatStorageService + model_manager (Hive) · → Out: files in app-private storage
- Era: inherited (Hive), Eidetic genesis (sqflite)

### GitHub Actions CI ✅
- Is: the only compiler. Builds the APK, runs analyze + tests + emulator smoke on every push.
- Layer/Where: infra · `.github/workflows/build-apk.yml`
- Key bits: jobs `build` (release arm64) · `test` (analyze+test) · `smoke-test` (x86_64 emulator DB boot)
- ← In: a git push · → Out: the APK artifact + pass/fail
- Era: inherited, hardened at Eidetic genesis

---

# B · INTERFACES  (the doors — front-end + external)

### Chat UI ✅
- Is: the main door — talking to her.
- Layer/Where: FE · `screens/home_screen.dart` (+ `widgets/chat_bubble`, `chat_sidebar`, `typing_indicator`, `pipeline_status_strip`)
- ← In: you · → Out: `chat_controller`
- Era: inherited

### Monitor tab ✅
- Is: the sensor dashboard (the capability board + all live visualizers).
- Layer/Where: FE · `screens/monitor_screen.dart`, `monitor_viz.dart`
- ← In: you · → Out: `SensorService`
- Era: Monitor v3.0→v3.14

### Memory Panel ✅
- Is: view/edit every memory, plus Events + Activity tabs (the future home of the "Self" tab).
- Layer/Where: FE · `features/memory/memory_panel_screen.dart` + `_controller`
- ← In: you · → Out: `MemoryService`, `EideticMemoryEngine`
- Era: Eidetic genesis

### Parameters screen ✅ · Settings ✅ · Models ✅ · Logs ✅ · API-endpoints ✅
- Is: control doors — live tuning / model choice+download / log viewer / local-API controls.
- Layer/Where: FE · `features/params/parameters_screen.dart` · `screens/settings_screen.dart` · `model_library_screen.dart` · `logs_screen.dart` · `api_endpoints_screen.dart`
- ← In: you · → Out: ParametersService / model_manager / LogService / local_api_server_service
- Era: inherited + Phase 0 (params)

### Dojo rooms: Arena + Introspection ✅
- Is: doors for her to talk to *herself* — Arena = two personas debate; Introspection = single-agent self-exam.
- Layer/Where: FE+BE · `features/rooms/arena_controller.dart`, `introspection_controller.dart`, `/arena`, `/introspection`
- ← In: you · → Out: InferenceWorker (at `debateRoom` priority), MemoryService
- Era: Eidetic genesis

### Integrity panel 🆕 · Self tab 🆕
- Is: (planned) owner-only audit of memory edits/deletions · her IDENTITY/BELIEFS/US/DREAMS view.
- Layer/Where: FE · (new, in Memory Panel)
- ← In: you · → Out: the Archive/verify system (Integrity) · self-model views over semantic_facts (Self)
- Era: planned (Phase F/G, Phase E)

---

# C · THE MODELS  (the neural engines — "the LLMs, distinct")

### Chat model (foreground) ✅
- Is: the GGUF model you talk to. System-1. Swappable; one resident at a time.
- Layer/Where: BE · loaded by `LlmService` via llamadart
- ← In: InferenceWorker · → Out: token stream back to chat_controller
- Era: inherited

### Embedding model ✅
- Is: a *separate* small model that turns text into meaning-vectors. Not conversational.
- Layer/Where: BE · `services/embedding_service.dart`
- Key bits: `load(path)` · `embed(text)` → `List<double>` · `unload()` · `isReady` · gated so it NEVER runs while the chat model generates (second engine = crash)
- ← In: MemoryService (recall + consolidation) · → Out: `claim_embeddings` table
- Era: Phase 2b

### Dreamer model 🆕
- Is: (planned) a small GGUF the daemon loads at night to reflect/consolidate. Cycled with the chat model (big one unloads first).
- Layer/Where: BE · loaded via `model_manager.loadDream()`
- ← In: the Sleep daemon · → Out: self-model edits (GBNF JSON) → MemoryService/MemoryManager
- Era: planned (Phase B)

---

# D · INFERENCE INFRASTRUCTURE  (runs & schedules the models)

### InferenceWorker ✅
- Is: the traffic cop. A priority queue in front of the one model engine; chat preempts background work.
- Layer/Where: BE · `core/engine/inference_worker.dart`
- Key bits: `TaskPriority { userInteraction, debateRoom, backgroundIntrospection }` · `submit(InferenceTask)` · `run()` · `cancel()`
- ← In: chat_controller, MemoryManager (consolidation), Dojo rooms, Autopilot · → Out: LlmService
- Era: Eidetic genesis (#2) + concurrency fix (#50)

### LlmService ✅
- Is: the model wrapper — load, generate, pick the right chat template, choose backend.
- Layer/Where: BE · `services/llm_service.dart`
- Key bits: `LlamaEngine(LlamaBackend)` · `loadModel()` · `generate(prompt)`→stream · `generateChat(messages, GenerationParams)` · `generateWithGrammar()` · `activeBackend` (cpu/vulkan/opencl) · template detect (ChatML/Llama/Gemma/Phi/Mistral)
- ← In: InferenceWorker · → Out: llamadart → the model
- Era: inherited + template fix (#35)

### model_manager ✅
- Is: model files — browse, download, select, load/unload into the slot.
- Layer/Where: BE · `services/model_manager.dart` (+ Hive box `models_meta`)
- Key bits: `loadDream()`/`unloadDream()` 🆕 planned
- ← In: Models screen, model_controller · → Out: LlmService, disk
- Era: inherited

---

# E · DETERMINISTIC RAILS  (the clockwork — non-neural, exact, validating)

### GbnfToolEngine ✅  ← *"what GBNF is in with"*
- Is: forces the model's output to match a grammar (clean JSON / valid tool-calls / valid terms), at the sampling level.
- Layer/Where: BE · `core/tools/gbnf_tool_engine.dart`
- Key bits: `buildToolCallGrammar(List<ToolSpec>)` · `ToolCall` parse · `ToolParamType` · `ToolSpec` · `ToolParameter`
- ← In: LlmService (grammar path), the future Dreamer + Solver · → Out: a validated structured object
- Era: Eidetic genesis (#3)

### Command Bus ✅  ← *"what Command Bus is in with"*
- Is: the single validated execution path — the only place any *action* is checked and run ("the hands").
- Layer/Where: BE · `core/agent/command_bus.dart`
- Key bits: `AppCommand` · `CommandResult` · `CommandSpec` · `register()` / `has()` / `spec()`
- ← In: UI, future agent loop, Autopilot · → Out: the registered command's effect
- Era: v2.2.0 "Going agentic"

### Archive + verifyChain 🆕
- Is: (planned) the immutable, SHA256-chained ground-truth record. Append-only; nothing may rewrite it.
- Layer/Where: DATA+BE · new `archive` table (schema v7→v8)
- Key bits: `appendArchive(role,content)` (only writer) · `hash = sha256(ts+role+content+prev_hash)` · `verifyChain()` (fail-closed, on boot + pre-dream)
- ← In: chat_controller (every turn) · → Out: read by the Dreamer; break → blocks the dream + logs to Integrity panel
- Era: planned (Phase A)

### Integrity panel + backup 🆕
- Is: (planned) owner-only log + backup of every detected edit/deletion (chain break OR backup-diff). Stored outside the wipe radius.
- Layer/Where: BE+FE · new
- ← In: verifyChain + archive-vs-backup diff · → Out: your panel (preserves the originals)
- Era: planned (Phase G)

### Dreamer Rails 🆕
- Is: (planned) safety on the nightly self-edits — ≤30% change cap, contradiction-guard vs archive, drift flags, reversible undo.
- Layer/Where: BE · new (uses reconciliation.dart)
- ← In: the Dreamer's candidate edits · → Out: accept / flag / reject before writing the self-model
- Era: planned (Phase G)

### Solver (the reasoner) 💡
- Is: (shelved/agreed-in-principle) a deterministic exact-logic executor — model emits a term via GBNF, Solver evaluates it exactly. True System-2. (The honest version of the "lambda neural net" — no training.) Its own standalone subsystem; owned by none, called by all.
- Layer/Where: BE · new (pure Dart; BigInt for exact math)
- ← In: System-2 gate (uncertainty), reconciliation, the Dreamer · → Out: a verified exact result (+ its derivation, for inspection)
- Era: shelved idea

### SQLCipher encryption 💡
- Is: (shelved) encrypt the whole eidetic DB at rest; portable/openable on PC with passphrase or hex key.
- Layer/Where: DATA · `sqflite_sqlcipher`; key in Android Keystore + passphrase export
- ← In: the DB open path · → Out: an encrypted DB file (safe to back up off-device)
- Era: shelved idea

---

# F · THE MIND / MEMORY  (persistent cognition)

### Eidetic SQLite store ✅  (the database)
- Is: the whole long-term memory — one file, eight tables.
- Layer/Where: DATA · `eidetic_store.dart` + `_io.dart` (device) + `_web.dart` (tests)
- Key bits (tables): `episodic_log` · `semantic_facts` · `claim_embeddings` · `event_log` · `relation_edges` · `provenance` · `open_questions` · `procedures` · migrations v1→v7 · WAL
- Key bits (methods): `insertEpisodic` · `searchEpisodic` · `insertFact` · `searchFacts` · `appendEvent` · `addEdge` · `addProvenance` · `nearestClaimsScored` · `reinforceClaims` · `decayAllSalience`
- ← In: EideticMemoryEngine · → Out: the DB file
- Era: Eidetic genesis → Phases 1–2.0

### EideticMemoryEngine ✅
- Is: the low-level engine over the store + the recall pipeline assembly.
- Layer/Where: BE · `core/memory/eidetic_memory_engine.dart`
- Key bits: `init()` · `snapshot()`→SensorAnchor · `record()` · `recall(q,k)` · `recallSemanticScored()` · `openQuestions()` · `storeEmbedding()` · `claimsMissingEmbedding()`
- ← In: MemoryService, MemoryManager · → Out: the store + cognition modules
- Era: Eidetic genesis

### MemoryService ✅  (the orchestrator — the single door to memory)
- Is: every turn's recall + write + consolidation trigger + the adaptive dynamics.
- Layer/Where: BE · `core/memory/memory_service.dart`
- Key bits: `remembering(query,k,recentContext)` (recall) · `remember()` / `rememberTurn()` (write) · `maybeConsolidate()` / `consolidateNow()` · `backfillEmbeddings()` · publishes `lastRecall`, `lastUncertainty`, `recentCalls`
- ← In: chat_controller, Dojo, Autopilot · → Out: EideticMemoryEngine, MemoryManager, cognition modules, EmbeddingService, ParametersService, PipelineStatusService
- Era: Eidetic genesis → all phases

### MemoryManager ✅  (the consolidation curator)
- Is: the gated model-pass that distills raw turns into facts + relations, reconciles, and self-reflects.
- Layer/Where: BE · `core/memory/memory_manager.dart`
- Key bits: `hasPendingWork()` · `consolidatePending(force)` · `reflectOnSelf()`
- ← In: MemoryService · → Out: InferenceWorker (the model pass), the store (new facts/edges/provenance)
- Era: Eidetic genesis → 2.0

### Cognition modules ✅  (the "thinking" helpers — mostly pure functions)
- `spreading_activation.dart` — graph recall across `relation_edges` → `ActivationResult`
- `vector_search.dart` — brute-force cosine over `claim_embeddings`
- `recall_ranker.dart` — `fuseAndRank` (relevance×salience×recency + dedupe + budget) · `RecallCandidate` · `RecallSource` · `RecallResult`
- `memory_dynamics.dart` — Bjork forgetting curve · `decayAllSalience` · `reinforceClaims`
- `uncertainty.dart` — `scoreUncertainty` → `UScore` (5 inputs) · `UMode { system1, system2 }`
- `attribution.dart` — `renderMemoryBlock` · `MemoryLine` (identity-safe self/other)
- `reconciliation.dart` — `SlotCollision` · `ReconcileAction { supersedeOld, askUser }` (contradiction detect)
- `belief.dart` — Dempster–Shafer resolution · `SlotEvidence` · `BeliefOutcome` · `BeliefVerdict`
- ← In: MemoryService/MemoryManager · → Out: scores/renderings back to recall; the Solver (future) sharpens reconciliation/belief
- Era: Phases 2a–4b, 2.0

### Record types ✅
- Is: the shapes memory stores. `memory_records.dart` (SemanticFact, RelationEdge, EpisodicEntry, enums) · `event_records.dart` (AppEvent, **SensorAnchor**) · `procedural_records.dart` (ProcedureRecord, ProcedureKind)
- Era: Phases 1–2, v2.2.0

### Procedural memory ✅
- Is: the fourth tier — stored skills/workflows/tools the agent reaches for.
- Layer/Where: DATA · `procedures` table + `procedural_records.dart`
- ← In: MemoryManager · → Out: the future agent loop (via Command Bus)
- Era: v2.2.0

### Hive stores ✅  (the app's filing cabinet — distinct from the mind)
- Is: chats, settings, model metadata. Simple key-value; what the chat UI reloads.
- Layer/Where: DATA · `chat_storage_service.dart` · boxes `chats` / `settings` / `models_meta` · adapters ChatModel(0)/MessageRole(1)/MessageModel(2)
- Key bits: `getAllChats` · `getChat(id)` · `saveChat` · `globalSystemPrompt`
- ← In: chat_controller, model_manager, theme/params · → Out: Hive files
- Era: inherited

### sensor_models 🆕 · self-model views 🆕
- Is: (planned) learned sensor patterns w/ confidence · IDENTITY/BELIEFS/US as queries over `semantic_facts (holder=self)`.
- Era: planned (Phase C, Phase E)

---

# G · THE SENSES  (body → data)

### MainActivity.kt (the native sensor hub) ✅
- Is: the one Kotlin file. Reads every sensor + device telemetry, builds a frame ~60 fps, answers index/perms/ctl.
- Layer/Where: NATIVE · `android/.../MainActivity.kt`
- Key bits: `SensorManager.registerListener` (16 types) · `LocationManager.requestLocationUpdates` + `GnssStatus.Callback` · `AudioRecord` · `CameraManager.setTorchMode` · `BluetoothLeScanner.startScan` · `WifiManager` · `TelephonyManager` · `Vibrator.vibrate` · `GeomagneticField` · `frame()` · `buildIndex()` · `buildCaps()`
- ← In: the platform channels · → Out: a frame (and command results) back over the channels
- Era: Monitor v3.0→v3.14

### Platform channels (the bridge) ✅
- Is: the named pipes Dart↔Kotlin talk over.
- Layer/Where: NATIVE↔BE · `aether/stream` (EventChannel) · `aether/index` · `aether/perms` · `aether/ctl` (MethodChannels)
- Key bits: `setStreamHandler` / `setMethodCallHandler` (Kotlin) · `receiveBroadcastStream()` / `invokeMethod()` (Dart)
- ← In: SensorService (Dart) · → Out: MainActivity (Kotlin)
- Era: Monitor v3.1

### SensorService ✅
- Is: consumes `aether/stream`, parses every field into typed reactive state, exposes control calls.
- Layer/Where: BE · `services/sensor_service.dart`
- Key bits: `EventChannel('aether/stream').receiveBroadcastStream().listen` · `micStart/locStart/torch/buzz/pdrReset` via `aether/ctl`
- ← In: Monitor tab · → Out: the channels; (planned) the Senses→Memory wire
- Era: Monitor v3.x

### Senses → Memory wire 🆕 · Audio/music sense 🆕
- Is: (planned) feed live sensor events into `event_log`/`SensorAnchor` · (shelved) MediaSession metadata + AudioPlaybackCapture → taste profile.
- Era: planned (Phase C) · shelved

---

# H · THE DAEMON / LIFECYCLE  (time & autonomy)

### Proto-daemon ✅
- Is: what runs consolidation + self-reflection *today* — opportunistically, on the chat model, gated.
- Layer/Where: BE · `MemoryService.maybeConsolidate/consolidateNow` + `MemoryManager.reflectOnSelf` (every N)
- ← In: `rememberTurn` after each turn · → Out: MemoryManager
- Era: 2.0 / concurrency fix (#79)

### Sleep-cycle daemon 🆕
- Is: (planned) the real background scheduler — a two-tier WorkManager job (cheap idle upkeep; heavy dream only on charger 2–5am). THE alarm clock that fires the Dreamer.
- Layer/Where: NATIVE+BE · WorkManager in MainActivity + new `aether/sleep` channel
- ← In: Android (conditions) · → Out: loads the Dreamer model, runs the dream loop
- Era: planned (Phase D)

---

# I · OBSERVABILITY & CONTROL  (operator insight + config)

### Parameters system ✅
- Is: data-driven live config — every tunable, changeable at runtime, read each turn.
- Layer/Where: BE · `core/params/param_spec.dart`, `parameters_service.dart`
- Key bits: `getInt/getBool/getDouble` · groups `recall.* spreading.* embeddings.* decay.* u.* ds.* reconcile.* reflect.* events.* gen.*`
- ← In: Parameters screen · → Out: read by MemoryService + cognition
- Era: Phase 0 (#21)

### LogService ✅ · SystemHealthMonitor ✅ · PipelineStatusService ✅
- Is: crash-surviving logs to disk · startup arming + runtime checks · live "what's happening now" strip.
- Layer/Where: BE · `services/log_service.dart` (+ `file_log_sink_io`) · `system_health_monitor.dart` · `pipeline_status_service.dart` (PipelinePhase)
- ← In: every module logs here · → Out: `/logs`, the status strip
- Era: Eidetic genesis (#10–12)

### GPU diagnostics ✅
- Is: the pen-test harness that measured "CPU wins" + the verdict.
- Layer/Where: BE · `core/diagnostics/gpu_pentest.dart`, `gpu_trial.dart`
- Era: v2.2.1–2.2.6

### Autopilot ✅
- Is: the on-device self-test — scripted scenarios over the real engine in an isolated memory stack. The skeleton of the future trial harness.
- Layer/Where: BE · `services/autopilot/autopilot_runner.dart` + dev screen
- ← In: dev trigger (long-press version) · → Out: an isolated MemoryService stack + metrics
- Era: Autopilot (#76–78)

---

# J · SHELVED IDEAS  (pinned — not committed)

- **SQLCipher encryption** 💡 — encrypt-at-rest + portable PC-openable DB (see E).
- **System-audio "hear what I hear"** 💡 — MediaSession metadata (backbone) + AudioPlaybackCapture (fallback; DRM apps block it) → music/taste sub-domain of memory (G).
- **The Solver (neurosymbolic reasoner)** 💡 — deterministic exact-logic executor; the honest, training-free version of the "lambda neural net" (see E).
- **Agency layer** 💡 — AccessibilityService (eyes+hands) + AppFunctions + AICore flags; infrastructure-only, no AI wiring until trusted. Would ride the Command Bus.
- **Adaptive bandit scheduler** 💡 · **LoRA/adapter growth** 💡 — post-first-boot daemon upgrades.

---

## Drawing the diagram from this

1. Make one **column (swimlane) per umbrella category A–J**.
2. Drop each **card** as a box in its column, colored by status (✅ green / 🆕 blue / 💡 grey).
3. For every card, draw an **arrow in from each "← In"** and an **arrow out to each "→ Out."** Those two lines are the complete connection set — follow them and you've mapped every wire in ALESIS.
4. The "golden paths" to highlight: **Talk** = Chat UI → chat_controller → MemoryService.remembering → InferenceWorker → LlmService → (reply) → rememberTurn → store. **Sense** = MainActivity → aether/stream → SensorService → Monitor. **Dream (planned)** = Sleep daemon → Dreamer → Archive(read) → Rails/Solver → self-model(write).

*Grounded in the source at 3.14.0-beta+33 · schema v7 · branch claude/eidetic-local-ai-dojo-shdbx2.*
