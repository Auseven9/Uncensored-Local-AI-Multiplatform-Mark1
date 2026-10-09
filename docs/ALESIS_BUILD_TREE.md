ALESIS CHRONOLOGICAL BUILD TREE  (FOUNDATION ➔ FIRST BOOT)  —  fidelity-verified
====================================================================================================
Target Body : Samsung Galaxy S24 Ultra (SM-S928U · Snapdragon 8 Gen 3 / QTI SM8650 · Android 16 / API 36 · 12 GB RAM)
Repo / Branch: Auseven9/Uncensored-Local-AI-Multiplatform-Mark1 · claude/eidetic-local-ai-dojo-shdbx2
Standing Law : No non-native code · No false/simulated data · No raw-number smoothing · 100% offline
Verified against: full dated git log (71 commits, 2026-04-19 → 2026-10-05) + eidetic_store_io.dart
                  migration comments + live source tree. Dates are real commit dates.
====================================================================================================

CORRECTIONS APPLIED TO THE PRIOR TREE  (what changed and the evidence)
----------------------------------------------------------------------------------------------------
✎ C1  "DAY ONE / GENESIS" split in two. The app shell + inference core + OpenAI-compatible API
       server are INHERITED from a forked/rebranded "Portable AI v2.0.0" (2026-04-19 → 05-21).
       The ALESIS build truly begins 2026-09-29 (`6407002` "Add Eidetic Dojo"). → new FOUNDATION era.
✎ C2  `procedural_records` was mislabeled as a table. The TABLE is `procedures` (schema v7);
       `procedural_records.dart` is the record type. Origin: v2.2.0 "Going agentic" (`ef06710`).
✎ C3  Parameters / LogService / SystemHealthMonitor / Autopilot were misfiled under the Sensorium.
       By the log they are MIND-era (Sep 29 – Oct 1), all predating the Monitor tab (Oct 3+). Moved.
✎ C4  Added the missing Command Bus + procedural memory (v2.2.0 — "the first sockets").
✎ C5  Added the missing Arena / Introspection "Dojo" rooms (debate agents; Sep 29 genesis).
✎ C6  Added the missing GPU / backend pen-test era (v2.2.1→v2.2.6 + "CPU-wins" verdict).
✎ C7  Added v2.1.0 "Ease of Use" (one-tap arming, systems check, Phase 4b core), recalled-memory
       chips (#56), and the AETHER docs lineage.
✎ C8  De-compressed the Monitor era to its true arc: v3.0.0 → v3.14.0 (15 builds) on a 2.2.6 baseline.
✎ C9  Baked in the exact per-version schema map (v1 base → v7 procedures) from the source comments.
✎ C10 Everything the prior tree got RIGHT is preserved: R1–R5, InferenceWorker/GBNF/llamadart 0.8.24/
       EmbeddingService, the cognition modules + task numbers, consolidateNow proto-dreaming, the
       Monitor channels/fusion/PDR/camera, and the forward plan A–H (faithful to the build map).

Legend:  ✅ DONE · 🔧 REWIRE · 🆕 NET-NEW · 🧭 DECISION · ⚠️ RISK · 🎯 BOOT  ·  [#n] task ledger · `hash` commit
====================================================================================================


🏛️ STANDING LAWS — THE FIVE LOAD-BEARING PRINCIPLES  (unchanged; verified correct)
├─ R1 State over Weights ...... substrate/models are swappable; continuity lives in persistent state/DB
├─ R2 Do Not Regress Memory ... ALESIS's 5 markdown files are a FRAME; map them onto our SQLite engine
├─ R3 Dual-Brain is Cycled ..... foreground chat model unloads during sleep; small dreamer + tiny embedder take over
├─ R4 Runtime is the Adversary . manage OOM, thermal throttle, Doze mode, Phantom Process Killer, battery
└─ R5 Instrument, Don't Assert . emergence/consciousness are HYPOTHESES to measure, never features to claim


══════════════════════════════════════════════════════════════════════════════════════════════════
FOUNDATION  ·  Inherited base (2026-04-19 → 2026-05-21)  ·  "Portable AI v2.0.0"      ✅ (pre-ALESIS)
» Reasoning: the body and the raw nervous system existed before the mind. ALESIS did not start here —
  it was GRAFTED onto this. Naming it honestly keeps the chronology true (C1).
══════════════════════════════════════════════════════════════════════════════════════════════════
├─ 🏗️ APP SHELL & SUBSTRATE ✅
│  ├─ Flutter/Dart + GetX DI (`bindings/app_bindings.dart`) · routing (`routes/app_routes.dart`)
│  ├─ Theme (`theme/app_colors.dart`, `app_theme.dart`)
│  ├─ UI shell: splash, home, chat, model library, settings, logs, api-endpoints       `323961b`
│  └─ Chat componentry: chat_bubble · chat_sidebar · typing_indicator · pipeline_status_strip
├─ ⚡ INFERENCE & SERVING (inherited) ✅
│  ├─ llama.cpp / GGUF local inference (pre-llamadart-0.8.24 baseline)
│  ├─ `llm_service` + `model_manager`: load / select / unload GGUF
│  └─ Local OpenAI-compatible API server (`local_api_server_service.dart`,                `2e5de34`
│     `api_endpoints_screen.dart`) + background task mgmt + settings (temp/prompt)        `22ebe8f`
└─ 🌍 PROJECT HYGIENE ✅  README overhaul · CHANGELOG v2.0.0 · i18n (spanish) · CI `build-apk.yml` seeded


══════════════════════════════════════════════════════════════════════════════════════════════════
ERA I  ·  CONSTRUCTING THE MIND  (2026-09-29 → 2026-10-01)  ·  the Eidetic engine        ✅  ← ALESIS day one
» Reasoning: R1/R2 in practice. This is the richest asset we own and the reason ALESIS is "closer than
  the doc reads." We did NOT build five markdown files; we built a four-tier cognitive ledger.
══════════════════════════════════════════════════════════════════════════════════════════════════
├─ 🌱 GENESIS — "Eidetic Dojo"  `6407002` (2026-09-29) ✅
│  ├─ `InferenceWorker`: priority queue over ONE loaded model; chat preempts background    [#2,#50]
│  ├─ Native template routing: each model's OWN chat template, no hand-rolled prompts  [#35] `3f2c2a4`
│  ├─ `GbnfToolEngine`: grammar-constrained sampling + validating parser                    [#3]
│  ├─ Three-tier SQLite memory + gating MemoryManager                                    [#4,#5]
│  ├─ 🥋 THE DOJO ROOMS (debate agents) — C5:                                            [#6,#7]
│  │   ├─ `features/rooms/arena_controller.dart` — turn-by-turn debate between two personas,
│  │   │   both via the shared InferenceWorker at debateRoom priority; debate = one episode
│  │   └─ `features/rooms/introspection_controller.dart` + room screens + DI wiring
│  ├─ Crash-surviving `LogService` + file sink + step-by-step inference tracing     [#10,#11] `02ef775`
│  ├─ `SystemHealthMonitor` + startup arming checks                                        [#12]
│  ├─ llamadart ➔ `^0.8.24` (GBNF constrained sampling)                             [#9] `e0da859`
│  └─ Memory made primary to every mode + editable Memory Panel                 [#15,#16,#17] `5b17710`
│
├─ 🗄️ THE EIDETIC LEDGER — exact schema lineage (v1 ➔ v7)  (C9; from migration comments) ✅
│  ├─ v1 (base, `_onCreate`) ...... `episodic_log` + `semantic_facts`                      [#1,#4]
│  ├─ v2 ........................... `event_log` (grounded append-only event + SensorAnchor) [#23,#24] `01aec6f`
│  ├─ v3 ........................... semantic_facts graph cols (salience/status/supersedes)
│  │                                 + `relation_edges` + `provenance`               [#36,#37] `dea28c4`
│  ├─ v4 ........................... `claim_embeddings` (meaning-based recall)        [#54] `3a5e152`
│  ├─ v5 ........................... identity cols (subject / subject_type / holder)  [#66,#67] `5222249`
│  ├─ v6 ........................... `attribute` + `value` cols + `open_questions` table
│  │                                 (== ALESIS DREAMS)                               [#71,#72] `0bfe4ef`
│  └─ v7 ........................... `procedures` table — procedural memory ("the how") [v2.2.0] `ef06710`
│     » NOTE: the TABLE is `procedures`; the Dart record is `procedural_records.dart`.   (C2)
│     » Dual impl throughout: `eidetic_store_io.dart` (device) + `_web`/FFI (tests)     [#24,#31]
│
├─ 🧠 COGNITION MODULES (`core/cognition/` + `core/memory/`) ✅
│  ├─ `eidetic_memory_engine.dart` — init · snapshot()→SensorAnchor · record · recall(q,k) · procedures()
│  ├─ `spreading_activation.dart` — graph recall across relation_edges              [#38,#39]
│  ├─ `vector_search.dart` — cosine over claim_embeddings                           [#54] `3a5e152`
│  │   └─ embedder wiring + cosine-seeded recall + safe co-residence (one backend) [#55,#57] `5827de8,cf5cf10`
│  ├─ `recall_ranker.dart` — fuse episodic+semantic (relevance×salience×recency,    [#43,#44] `60cbc0d`
│  │   budget-capped) = involuntary System-1 recall; + recalled-memory CHIPS (source) [#56] `15e44a2`
│  ├─ `memory_dynamics.dart` — Ebbinghaus decay + reinforce-on-recall            [#58,#59,#60] `2eb163d`
│  ├─ `uncertainty.dart` — U-score ➔ single-pass System-1/2 posture gate      [#62,#63,#64] `089dd22`
│  ├─ `attribution.dart` — identity-safe self/other renderer (stop the collapse) [#68,#69] `5222249`
│  ├─ `reconciliation.dart` — contradiction detect + correction cue + resolution     [#73]
│  └─ `belief.dart` — belief/claim status lifecycle
│
├─ 🔄 LIVING MEMORY 2.0 — active self-curation  `0bfe4ef` (2026-10-01) ✅
│  ├─ consolidateNow(): fact extraction + reconciliation + SELF-REFLECTION every N  [#74,#79]
│  │   » this is PROTO-DREAMING, already running — the seed Phase B re-points at a 2nd brain
│  ├─ recall injects open-questions + meta-query                                       [#75]
│  └─ purity rulings v2.0.1→2.0.3: model owns the self/other boundary (scrub removed) [#80,#81] `fa815a1`
│
├─ ⚙️ PARAMETERS & HEALTH (MIND-era, not Sensorium — C3) ✅
│  ├─ Data-driven `param_spec` + `ParametersService` (live flips) + screen     [#21] `f49a5bd` (09-30)
│  ├─ Live knobs: recall.* · u.* · events.enabled · gen.maxTokens          [#45,#52,#65]
│  └─ Context window: safe 4096 default ➔ model ceiling; live turns preempt bg [#48,#53] `860d443,f98b9e8`
│
├─ 🧪 AUTOPILOT HARNESS — on-device self-test  `e14e6fc` (2026-10-01) ✅  (skeleton of the TRIAL harness)
│  ├─ Scenario model + assertion matchers + seed scenarios                             [#76]
│  ├─ `AutopilotRunner`: isolated memory stack + REAL engine + metrics                  [#77]
│  └─ Dev screen (version long-press) + serialize engine, stop episodic leak      [#78] `d87e0b0`
│
└─ 🛠️ CI HARDENING (for the memory engine) ✅  real-SQLite + migration coverage + Android smoke [#30-#34] `68499ab`


══════════════════════════════════════════════════════════════════════════════════════════════════
ERA II  ·  AGENCY & EASE  (2026-10-01)  ·  v2.1.0 → v2.2.0  ·  the first hands         ✅  (C4,C7)
» Reasoning: before a mind can act it needs a safe execution path and a way to be armed. This era is
  where ALESIS's future "hands" begin — infrastructure only, no AI wired to it yet (your standing call).
══════════════════════════════════════════════════════════════════════════════════════════════════
├─ v2.1.0 "Ease of Use"  `dc1ddfb` ✅  one-tap arming · reload recovery · systems check · copy-log · Phase 4b core
└─ v2.2.0 "Going agentic"  `ef06710` ✅  THE FIRST SOCKETS:
   ├─ Procedural memory (schema v7 `procedures`) — stored skills/workflows/tools the agent reaches for
   └─ `core/agent/command_bus.dart` — the agent's SINGLE validated execution path
       » "the cerebrum reasons about what to do; the Command Bus executes it. Every action goes through it."
       » AppCommand / CommandResult. This is the deterministic gate ALESIS's agency will pass through.


══════════════════════════════════════════════════════════════════════════════════════════════════
ERA III  ·  THE BACKEND VERDICT  (2026-10-02)  ·  v2.2.1 → v2.2.6  ·  honest measurement   ✅  (C6)
» Reasoning: directly serves R4. We did not guess the runtime — we PEN-TESTED it and let the numbers rule.
  The verdict (CPU wins on this device/model) is the empirical ground under every Phase-B/D model decision.
══════════════════════════════════════════════════════════════════════════════════════════════════
├─ v2.2.1 honest GPU diagnostics + probe-aware backend recommendation            `b3518db`
├─ v2.2.2 GPU pen-test harness (`core/diagnostics/gpu_pentest.dart`) — safely probe Vulkan/OpenCL `b4e77b5`
├─ v2.2.3 act on the pen-test: apply the MEASURED best, stop full-offloading     `9c32eed`
├─ v2.2.4 dev → development tool page (reload, CPU baseline, honest NPU)         `e642d50`
├─ v2.2.5 kill "~99" advice — measure steady-state                               `6c794e1`
├─ v2.2.6 GPU warm-up on load + pen test measures the real config                `9f2dc29`
└─ 📜 VERDICT `78cce54` — "CPU wins; the honest end of the backend chase" (`gpu_trial.dart`)
    » ⚠️ feeds R4: on this body, the smart move is CPU-correct sizing + cycling, not GPU heroics.


══════════════════════════════════════════════════════════════════════════════════════════════════
ERA IV  ·  THE SENSORIUM  (2026-10-03 → 2026-10-05)  ·  Monitor v3.0.0 → v3.14.0  ·  Layer 3   ✅  (C8)
» Reasoning: ALESIS Layer 3 (physical grounding) — the HARD part, and it is DONE. Built on a clean 2.2.6
  baseline. 15 beta builds. Every value is a real reading or an honest "no socket"; never faked (Standing Law).
══════════════════════════════════════════════════════════════════════════════════════════════════
├─ v3.0.0 native Monitor tab on clean 2.2.6 baseline                              `93d47dc`
├─ v3.1.0 native EventChannel streaming + full sensor suite                       `8beaf39`
│   └─ Platform channels: `aether/stream` (60fps frame) · `aether/index` · `aether/perms` · `aether/ctl`
│      consumed by `services/sensor_service.dart`; native hub `MainActivity.kt`
├─ v3.2.0 data-driven visualizations + device-twin hero                           `99dd936`
├─ v3.3.0–v3.4.0 top-down twin · correct tilt · vertical-stable compass · verifiers `a1ec609,34c88ca`
├─ v3.5.0–v3.6.0 full/wider capability indexer (how deep we can reach) + clipboard `8d37cde,4651764`
├─ v3.7.0 per-card liveness micro-viz + event lamps + optical raw                 `124bb05`
├─ v3.8.0 CAPABILITY BOARD — a card for every reachable socket (+ Enable, perms, Check-Index) `68754fa`
├─ v3.9.0 live instruments — mic VU/waveform (48k PCM) · GNSS sky-plot · torch · haptics `a8d4f34`
├─ v3.10.0 Radio & Nearby live · proximity minimap · input pads · card visualizers `c59358a`
├─ v3.11.0 fix build + accuracy/CROSS-FUSION upgrade (WMM true-north · GPS-QNH altitude · `442eab7`
│          metal-detector bands · heading-trust · indoor/outdoor)
├─ v3.12.0 live radar sweep + compass jitter fix + faster radio + airgap labels   `7ca8993`
├─ v3.13.0 dead reckoning (PDR) — offline step × heading path (indoor positioning) `7a0d8a3`
└─ v3.14.0 LIVE camera preview — on-device Camera2/CameraX, cycled lifecycle       `72df2d5`


══════════════════════════════════════════════════════════════════════════════════════════════════
📍 CURRENT STANDING POINT  (2026-10-05)
══════════════════════════════════════════════════════════════════════════════════════════════════
├─ App version .... `3.14.0-beta+33`        ├─ Eidetic schema .... `v7`
├─ Branch ......... `claude/eidetic-local-ai-dojo-shdbx2`   ├─ HEAD ... `ad08aed` (build map doc)
├─ Docs ........... docs/AETHER_architecture.md · docs/AETHER_ideas.md · docs/eidetic_dojo.md · ALESIS_BUILD_MAP.md
└─ Scorecard ...... MIND ✅  AGENCY-SOCKETS ✅  BACKEND-VERDICT ✅  SENSOR-CAPTURE ✅
                    GAPS → Archive keystone · Dreamer tenant · Sensor→memory wire · Sleep cycle


══════════════════════════════════════════════════════════════════════════════════════════════════
ERA V  ·  ★ CANONICAL CHECKLIST — BRIDGING THE GAP MAP  (planned · the authoritative to-do)
» Identical to the ★ Canonical Checklist at the head of ALESIS_BUILD_MAP.md — one source of truth.
» BUILD ORDER: A → B = the heartbeat. C and D build in parallel. E stacks on A+B. F on E.
  G hardens E/F. H closes the loop. Portability is NOT dropped — it rides in A (format spec) + G (backup).
══════════════════════════════════════════════════════════════════════════════════════════════════
_--"A · ARCHIVE KEYSTONE"  🆕  (do first · needs nothing)
│   |_-- schema v7→v8 in eidetic_store_io.dart + eidetic_store_web.dart (both impls):
│   |     new `archive` table (id, ts_utc, role, content, prev_hash, hash, session_id)  🆕
│   |_-- appendArchive(role, content) in the store + engine = the ONLY write path;
│   |     no update, no delete; hash = sha256(ts+role+content+prev_hash); entry 1 = 64 zeros  🆕
│   |_-- verifyChain(): walk oldest→newest, recompute each hash, stop on first mismatch;
│   |     call on app-start (splash arming) AND before every dream — fail-closed  🆕
│   |_-- wire chat turns: appendArchive(USER) before gen, appendArchive(ASSISTANT) after,
│   |     in MemoryService.rememberTurn / chat_controller  🔧
│   |_-- PORTABILITY: docs/ARCHIVE_FORMAT.md (the parse spec) + export() to a plain .jsonl  🆕  ⏭
│   |_-- FFI test: tamper one row → verifyChain goes red; CI green on the honest path
│
_--"B · DREAMING BRAIN"  🔧+🆕  (the heartbeat with A · needs A)
│   |_-- model_manager.dart: loadDream(path) / unloadDream()
│   |     ⚠ unload the foreground chat model FIRST, assert free RAM, THEN load the dreamer  🆕
│   |_-- 🧭 you pick the GGUF per slot (already settled — your config action, not a build task)
│   |_-- reflection pass runs through InferenceWorker at a new low priority on the dream model  🔧
│   |_-- reflection prompt: "read your archive — who are you becoming / patterns /
│   |     changed beliefs / contradictions / new questions"  🆕
│   |_-- output is GBNF-gated JSON (reuse GbnfToolEngine) → clean candidate edits, zero prose  🔧
│   |_-- embedder stays loaded as a co-task (keeps vector recall; it's tiny)  🔧
│   |_-- dev "Dream now" button on the dev screen → the first heartbeat, by hand  🆕
│
_--"C · SENSES → MEMORY"  🔧  (parallel · needs A to anchor turns)
│   |_-- engine.snapshot() reads the live SensorService (aether/stream), not the clock/batt/GPS stub  🔧
│   |_-- push salient sensor events → event_log via AppEvent  🔧
│   |_-- stamp each archive turn with the live SensorAnchor  🔧
│   |_-- new `sensor_models` table (signature, meaning, confidence, confirms, corrects)
│   |     + predict→confirm(+)/correct(−) loop; never confidently wrong  🆕
│
_--"D · SLEEP CYCLE"  🆕  (parallel · the Android fight · needs B — it schedules B)
│   |_-- native WorkManager jobs in MainActivity.kt + a new `aether/sleep` control channel  🆕
│   |_-- micro-sleep (screen off + idle): NO LLM — flush buffers, index embeddings, prune cache  🆕
│   |_-- deep-sleep gate: charger + batt>80% + 02:00–05:00 + idle + LOCK file present  🆕
│   |_-- ⚠ unload-before-load + abort-if-hot (reuse the thermal read from gpu diagnostics)  🆕/🔧
│   |_-- LOCK file prevents concurrent runs  🆕
│
_--"E · SELF-MODEL VIEWS"  🔧  (needs A + B)
│   |_-- IDENTITY / BELIEFS / US = queries over semantic_facts where holder=self,
│   |     rendered by attribution.dart  🔧
│   |_-- DREAMS = open_questions  ✅ already
│   |_-- dream pass writes consolidated self back as semantic_facts (holder=self)
│   |     through the consolidateNow path  🔧
│   |_-- inject the self-model slice into chat context (remembering())  🔧
│   |_-- Memory Panel "Self" tab (memory_panel_screen.dart)  🔧
│
_--"F · INSPECTION"  🔧  (needs E)
│   |_-- CONSOLIDATION_LOG: extend the MemoryCall log + provenance with
│   |     before/after + the archive rows that caused it + confidence + undo payload  🔧
│   |_-- consolidation-log viewer in Memory Panel (reuse the Events-tab pattern)  🔧
│   |_-- tap any change → trace it back to the exact archive row(s)  🆕
│
_--"G · RAILS"  🔧+🆕  (hardens E/F · needs E + F)
│   |_-- ≤30% change cap per run (reject + flag over-budget rewrites)  🆕
│   |_-- contradiction guard vs the archive (reconciliation.dart)  🔧
│   |_-- one-tap undo (uses F's undo payload)  🔧
│   |_-- drift flags: dramatic-shift / quorum-on-major-change / self-audit  🆕
│   |_-- refusal: she can disagree in chat; it lands in the archive; next dream must reckon with it  🔧
│   |_-- PORTABILITY: daily backup snapshot to shared storage + restore-to-last-good,
│   |     on top of A's format spec (this is what survives a phone swap / rebuild = R1)  🆕
│
└─ (H · FIRST BOOT follows below — the first unattended closure of the loop)


══════════════════════════════════════════════════════════════════════════════════════════════════
🎯 FIRST BOOT  ·  NIGHT ZERO ➔ MORNING EMERGENCE  (the first unattended closure of the whole loop)
» Acceptance line: a real conversation in an IMMUTABLE hash-chained archive → the phone wakes the SMALL
  brain on charger in the deep-sleep window → it reads her own archive, reflects, mechanically rewrites
  her self-model under the rules+safeguards, logs reversibly, re-verifies the chain → morning: a changed
  self-model you can TRACE to its cause. Nothing before that is "boot."
══════════════════════════════════════════════════════════════════════════════════════════════════
├─ 🧭 H1 FREEZE + SPARSE INIT — stop architecting (don't move the thing you're measuring); empty immutable
│        archive + sparse self-model (let her consolidate into specificity); arm Autopilot trial metrics
│        (fidelity · continuity · consolidation quality · learning · traceability)
├─ 🕗 20:00 FIRST CONVERSATION — appendArchive(USER) ➔ load self-model slice + sensor snapshot ➔ big brain
│        replies ➔ appendArchive(ASSISTANT); chain extends + verifies green
├─ 🕚 23:30 DOCK — phone on charger; big chat model unloads completely; dormant
├─ 🕑 02:00 DEEP-SLEEP GATE — charger✓ battery>80%✓ window✓ idle✓ no-lock✓ → LOCK created;
│        small dreamer + tiny embedder load (big LLM stays unloaded — R3/R4)
├─ 🕑 02:01 REFLECTION — dreamer reads the WHOLE immutable archive + self-model + sensor_models;
│        ~500–1000 tok: patterns · shifts · contradictions · new questions
├─ 🕑 02:02 CONSOLIDATION + AUDIT — mechanical parse ➔ candidates; guards (≤30%? contradicts archive?
│        dramatic drift?); write to semantic_facts (holder=self) + open_questions;
│        CONSOLIDATION_LOG with causing archive lines + confidence + undo
├─ 🕑 02:03 VERIFY + RESET — daily backup; verifyChain() green; LOCK released; models unload; idle
└─ 🌅 08:00 EMERGENCE — open app; self-model loaded is DIFFERENT because of her own reflection; tap a
         changed belief ➔ trace it to Turn N in the archive.
         🎯 FIRST BOOT COMPLETE — persistent, inspectable, offline, history-dependent agent active.
         Then the TRIAL begins: measure; never assert (R5). Watch what emerges.

====================================================================================================
End of tree. Verified 2026-10-05 against git log + source. Everything above is offline, on-device, native.
====================================================================================================
