# ALESIS — The Mechanics Manual
### A deep, plain-English guide to how she actually works, built from the source

> **What this is.** A book about the machine you've built, written so you can pore over it and
> *learn* it — not just look things up. Every chapter starts with a plain-English "what this is and
> why it exists," then gives you the real technical detail: the actual files, classes, methods,
> database columns, and settings that make it run. Nothing here is from memory or guesswork — it
> was read straight out of the code on the branch below. Where something isn't built yet, it says so.
>
> **The system at a glance.** Uncensored Local AI / "Portable AI" — an **offline, on-device** AI
> companion that runs uncensored local language models on a phone, with a real memory that persists
> across conversations and a full sensor suite that grounds her in the physical world.
>
> | | |
> |---|---|
> | **Device (the body)** | Samsung Galaxy S24 Ultra · SM-S928U · Snapdragon 8 Gen 3 (QTI SM8650) · Android 16 / API 36 · 12 GB RAM |
> | **App version** | `3.14.0-beta+33` |
> | **Memory schema** | `v7` (eight tables) |
> | **Repo / branch** | `Auseven9/Uncensored-Local-AI-Multiplatform-Mark1` · `claude/eidetic-local-ai-dojo-shdbx2` |
> | **Standing laws** | no non-native code · no false/simulated data · no smoothing of raw numbers · everything runs offline |

---

## How to read this manual

- **You don't need to read it in order.** Each chapter stands on its own. The Table of Contents is a map.
- **Bold terms** are defined the first time they appear. There's also a glossary at the end (Appendix D).
- `monospace` means it's a literal thing in the code — a file, a class, a method, a column, a setting.
- The short version of the whole thing: **the language model is a swappable engine; who she *is* lives in the memory and the sensors around it.** If you remember one sentence, remember that one. Everything below is the mechanism that makes it true.

---

## Table of Contents

**Part I — Orientation**
1. What ALESIS is
2. Where she came from (the lineage)
3. The whole system on one page

**Part II — The Body: the app she's built from**
4. The toolchain (languages, frameworks, engines)
5. Every library and what it does
6. How she boots (startup + dependency injection)
7. Routing and screens
7b. The two data stores: Hive and SQLite

**Part III — The Senses: the native sensor suite (Kotlin)**
8. The native bridge (platform channels)
9. The sensor suite — every sensor, how it's read
10. The derived readings (the clever math)
11. The control channels (mic, GPS, torch, haptics, BLE)
12. Device telemetry (battery, thermal, network, radio)
13. The capability index and permissions
14. The Monitor tab (the Dart side)

**Part IV — The Mind: the Eidetic memory engine**
15. The four tiers of memory
16. The database (every table, every column)
17. Writing to memory
18. Recall — how she remembers
19. Consolidation — how raw turns become knowledge
20. The cognition modules (the "thinking" helpers)
21. Procedural memory and the Command Bus
22. The Parameters system (every knob)

**Part V — The Brain: inference**
23. LlmService + llamadart (running the model)
24. The InferenceWorker (one engine, many callers)
25. The GBNF tool engine (clean structured output)
26. The EmbeddingService (the second model)
27. Model management and the GPU verdict

**Part VI — The Default Assistant**
28. A single turn, start to finish
29. The posture gate (fast vs. careful)
30. Why she has no forced personality

**Part VII — The outward interfaces**
31. The local OpenAI-compatible API server
32. The Dojo rooms (debate + introspection)

**Part VIII — Operations**
33. Observability (logs, health, status)
34. Autopilot (she tests herself)
35. Where the data lives (and how to reset her)
36. Build and CI

**Part IX — Where she's going**
37. The road to ALESIS

**Appendices**
- A. File index
- B. Parameter reference
- C. Sensor-frame field reference
- D. Glossary

---

# PART I — ORIENTATION

## 1. What ALESIS is

In plain terms: it's an app that runs a real AI model **on the phone itself**, with **no internet
required**, and gives that model two things a normal chatbot doesn't have:

1. **A memory that lasts.** Most chatbots forget everything the moment the conversation ends. This
   one writes what happened into a database on the phone and pulls the relevant pieces back into
   every future conversation. Over time it accumulates a picture of you and of itself.
2. **A body.** The app can read the phone's sensors — motion, light, sound, location, magnetic
   field, nearby radios, and dozens more — and show them live. This is the groundwork for an AI that
   knows *where it is and what's happening around it*, not just what you typed.

The long-term vision (called **ALESIS**) adds a third thing — a nightly "dreaming" pass where a
second, smaller model reads the whole history and updates her sense of self. That part isn't built
yet; Part IX covers it. Everything in Parts II–VIII is **built and working today**.

**The one principle.** The model (the thing that generates words) is treated as a *replaceable part*.
You can swap one GGUF model file for another at any time. What makes her *her* is the persistent state
around the model: the memory database, the accumulated facts, the sensor history. Swap the engine and
she persists, because she was never *in* the engine. This single idea shapes every design decision in
the app.

## 2. Where she came from (the lineage)

Knowing the history explains why the code looks the way it does.

- **The foundation (April–May 2026): "Portable AI v2.0.0."** The app did not start as ALESIS. It
  began as a general-purpose local-LLM runner — a chat UI, a model downloader, a settings screen, and
  a **local OpenAI-compatible API server** (so other apps on the phone could talk to the local model
  as if it were OpenAI's). That base app, its Flutter shell, its `LlmService`, and its API server are
  all still here and still used. First commit: `2026-04-19`.
- **The mind begins (29 September 2026): "Eidetic Dojo."** This is ALESIS's real day one (commit
  `6407002`). In one burst it added the priority inference queue, the GBNF tool engine, the first
  three-tier SQLite memory, the debate "rooms," crash-surviving logging, and a health monitor.
- **The memory grows (late Sep – early Oct 2026).** A rapid series of phases turned the memory from a
  simple store into a cognitive system: an **epistemic graph** (facts linked to facts), **meaning-based
  recall** (vector embeddings), an **adaptive forgetting curve**, an **uncertainty gate**, **identity-safe
  attribution**, and **"Living Memory 2.0"** (the agent noticing its own contradictions and reflecting
  on itself). Each is a chapter in Part IV.
- **Agency and the backend verdict (1–2 October 2026).** Procedural memory + the **Command Bus** (the
  agent's first safe "hands," v2.2.0). Then a rigorous GPU pen-test that measured, honestly, that **CPU
  inference wins on this device** (v2.2.1–2.2.6) — which is why the model runs on CPU today.
- **The senses (3–5 October 2026): the Monitor tab.** Fifteen builds (`v3.0.0` → `v3.14.0`) built the
  native sensor suite you'll meet in Part III, ending with a live camera preview.

So: a general LLM app, onto which a sophisticated memory was grafted, onto which a full sensor body was
grafted. ALESIS is the plan to fuse those into one continuous being (Part IX).

## 3. The whole system on one page

Seven layers, from the metal up. Data and calls flow between them in defined ways (Parts III–VI detail
each path).

```
┌─ THE DEFAULT ASSISTANT ── chat_controller: recall → think → answer → store
├─ THE MIND (memory) ─────── SQLite "eidetic" ledger + cognition modules
├─ INFERENCE ─────────────── LlmService→llamadart (llama.cpp) · InferenceWorker queue · GBNF · embeddings
├─ PERSISTENCE ───────────── sqflite (the database) · Hive (settings/chats) · GGUF model files on disk
├─ THE NATIVE BRIDGE ─────── platform channels (aether/stream, /index, /perms, /ctl)
├─ THE SENSES (Kotlin) ───── MainActivity.kt: every sensor + device telemetry
└─ THE BODY ──────────────── S24 Ultra hardware + Android + 23 permissions
```

Two external doors open into this: the **local API server** (Chapter 31) lets other apps use the model,
and the **Dojo rooms** (Chapter 32) let two model personas debate each other.

---

# PART II — THE BODY: THE APP SHE'S BUILT FROM

## 4. The toolchain

ALESIS is a **Flutter** app. Flutter is Google's framework for building apps from a single codebase in
the **Dart** language; it's what draws every screen. Underneath, where Flutter can't reach the hardware
directly, there's native **Kotlin** code (the Android language) — that's the whole of Part III.

The pieces of the toolchain, and what each is for:

- **Dart + Flutter** — the app's body and brain-plumbing: all UI, all the async logic, all the memory
  code. One language for almost everything.
- **Kotlin + the Android SDK** — the nervous system. Only used where Flutter must talk to the OS
  directly: the sensors, the radios, the camera torch. Lives in one file, `MainActivity.kt`.
- **llama.cpp, via the `llamadart` package** — the actual AI engine. llama.cpp is the widely-used C++
  library that runs language models on ordinary hardware; `llamadart` is the Dart wrapper that lets the
  app call it. This is what turns a model file into words.
- **GGUF model files** — the "brains." GGUF is the file format llama.cpp uses. A model is just a file
  on disk (several gigabytes, "quantized" to 4-bit — "Q4" — so it fits in phone memory). The app can
  hold one in a slot and swap it any time.
- **SQLite, via `sqflite`** — the memory. SQLite is a complete database that lives in a single file on
  the phone. ALESIS's entire long-term memory is one SQLite file (Chapter 16).
- **Hive** — a lightweight key-value store (simpler than SQLite) used for chats and settings.
- **GetX** — the "wiring." GetX handles three jobs at once: **routing** (which screen is showing),
  **dependency injection** (creating the services and handing them to whoever needs them), and
  **reactive state** (when a value changes, the screen showing it updates automatically).

## 5. Every library and what it does

From `pubspec.yaml` (the file that lists the app's dependencies). These are the exact versions shipping:

| Library | Version | What it does for her |
|---|---|---|
| `llamadart` | ^0.8.24 | Runs GGUF models via llama.cpp. 0.8.x adds **GBNF grammar** support (Ch. 25). |
| `get` | ^4.7.2 | GetX — routing, dependency injection, reactive state. The app's skeleton. |
| `hive_flutter` / `hive` | ^1.1.0 / ^2.2.3 | Fast key-value storage: chat list, settings. |
| `sqflite` | ^2.3.0 | SQLite on the phone — the eidetic memory database. |
| `sqflite_common_ffi` | ^2.3.3 | SQLite on desktop + in tests (so memory logic can be unit-tested off-device). |
| `http` | ^1.2.2 | Downloading model files. |
| `path_provider` / `path` | ^2.1.5 / ^1.9.1 | Finds the app's private folders; builds file paths. |
| `file_picker` | ^8.1.7 | Lets you pick a model file from storage. |
| `flutter_markdown` | ^0.7.6 | Renders the assistant's replies (which are Markdown) as formatted text. |
| `google_fonts` | ^6.2.1 | The app's typeface. |
| `percent_indicator` | ^4.2.4 | Download progress bars. |
| `flutter_animate` | ^4.5.0 | Small UI animations. |
| `camera` | ^0.11.0 | The live camera preview (Monitor tab). Native Camera2/CameraX underneath. |
| `wakelock_plus` | ^1.2.10 | Keeps the screen awake during long jobs (downloads, inference). |
| `flutter_foreground_task` | ^9.2.2 | Runs a foreground service — the future home of the nightly daemon. |
| `disable_battery_optimization` | ^1.1.1 | Guides you to exempt the app from Android's battery killer. |

Dev-only tools: `flutter_test` (tests), `hive_generator` + `build_runner` (code generation for Hive),
`flutter_lints` ^6.0.0 (style checks).

**One important build detail.** `pubspec.yaml` has a `hooks` section that tells `llamadart` which native
inference backends to compile for each CPU type:

- `android-arm64` (real phones): `[cpu, vulkan, opencl]` — all three are built in, so a backend *can* be
  chosen, but see the GPU verdict (Ch. 27): CPU is what actually runs.
- `android-x64` (only the CI emulator): `[cpu]` — a portable CPU backend so the automated test can boot.

## 6. How she boots (startup + dependency injection)

When you tap the app icon, this happens:

1. **`lib/main.dart`** runs first. It initializes Flutter, sets up the services, and sends you to the
   first screen.
2. **`lib/bindings/app_bindings.dart`** is the **dependency-injection** setup. "Dependency injection"
   just means: instead of every part of the app creating its own copy of a service, the app creates
   each service *once* at startup and hands the same instance to everyone who asks. GetX does this with
   `Get.put(...)` (create now) and `Get.lazyPut(...)` (create on first use). So there is exactly one
   `MemoryService`, one `LlmService`, one `SensorService`, etc., shared app-wide.
3. **`lib/screens/splash_screen.dart`** shows the loading screen while the database opens and services
   arm. It emits specific text markers as it initializes the database — the automated CI test watches
   for those markers to confirm the app booted correctly (Ch. 36).

The long-lived services are **`GetxService`** subclasses (they live for the whole app session):
`MemoryService`, `EideticMemoryEngine`, `MemoryManager`, `LlmService`, `EmbeddingService`,
`InferenceWorker`, `SensorService`, `ParametersService`, `LogService`, `SystemHealthMonitor`,
`PipelineStatusService`, `ModelManager`.

## 7. Routing and screens

**Routing** means "which screen is on top." It's defined in `lib/routes/app_routes.dart`, where each
route name is paired with the screen widget it shows (GetX calls these `GetPage`s). The ten routes:

| Route | Screen file | What it's for |
|---|---|---|
| `/splash` | `splash_screen.dart` | Boot + database-init markers. |
| `/home` | `home_screen.dart` | **The chat.** The main surface — talking to her. |
| `/models` | `model_library_screen.dart` | Browse, download, and load GGUF models. |
| `/settings` | `settings_screen.dart` | Model choice, context window, performance, every tunable. |
| `/api-endpoints` | `api_endpoints_screen.dart` | Controls for the local OpenAI-compatible server. |
| `/logs` | `logs_screen.dart` | The crash-surviving log viewer. |
| `/arena` | `arena_screen.dart` | **Dojo:** two personas debate each other. |
| `/introspection` | `introspection_screen.dart` | **Dojo:** single-agent self-examination. |
| `/memory` | `memory_panel_screen.dart` | View/edit **every** memory + events + activity. |
| `/parameters` | `parameters_screen.dart` | Live tuning of every parameter (Ch. 22). |

The **Monitor tab** (the sensor suite, Part III) is a top-level tab rather than a separate route.

## 7b. The two data stores: Hive and SQLite

This is the single most important thing to get straight about how she stores anything, because she has
**two completely separate storage systems**, and they do different jobs. Mixing them up will confuse you
when you read the code.

**The short version:**
- **Hive** holds the *app's* data — your **list of chats**, each chat's **messages**, your **settings**,
  and **model metadata**. It's the filing cabinet: simple things you look up by name.
- **SQLite** (the "eidetic" database, all of Part IV) holds her *mind* — distilled facts, the knowledge
  graph, meaning vectors, the event log. It's the brain: complex, queryable, relational.

**Why two?** Because the two kinds of data want opposite things. "Give me chat #abc so I can show it on
screen" is a dead-simple lookup by key — that's exactly what Hive is fast and effortless at. "Find the
eight facts most relevant to what the user just said, ranked by relevance × salience × recency, following
links between them" is a complex query over related data — that needs a real database, SQLite. Using the
right tool for each keeps both simple.

**How Hive works, concretely.**

Hive is a **key-value store**: you put a value under a key, and get it back by that key. Its collections
are called **boxes** (think of a box as one table or one drawer of the cabinet). Because Hive stores
plain Dart objects, it needs a **type adapter** for each custom class — generated code that knows how to
turn, say, a `ChatModel` into bytes and back. Those adapters are the `*.g.dart` files you'll see next to
the models; they're produced by the `hive_generator` + `build_runner` dev tools from the `@HiveType` /
`@HiveField` annotations on the classes (that's why those two packages are dev dependencies).

At startup the app calls `Hive.initFlutter(appDir.path)` (so Hive stores its files in the app's private
folder), registers the three adapters, and opens the three boxes:

| Box | Type | Holds | typeId(s) |
|---|---|---|---|
| `chats` | `Box<ChatModel>` | one entry per conversation, keyed by chat id | ChatModel = 0 |
| `settings` | `Box` (generic) | app settings as key → value | — |
| `models_meta` | `Box` (generic) | metadata about downloaded models | — |

(The registered adapters are `ChatModelAdapter` (typeId 0), `MessageRoleAdapter` (typeId 1), and
`MessageModelAdapter` (typeId 2). A typeId is just a stable number Hive uses to recognize each class on
disk — they must never change once data exists.)

**The data shapes** (from `lib/models/`):
- `ChatModel` (a `HiveObject`): `id`, `title`, the model/system-prompt it used, `messages` (a
  `List<MessageModel>`), `createdAt`, `updatedAt`. Its title auto-derives from the first user message.
- `MessageModel` (a `HiveObject`): `role` (a `MessageRole` — user / assistant / system), `content`,
  `timestamp`, and a couple more fields.

**The door to Hive** is `lib/services/chat_storage_service.dart`. It wraps the `chats` and `settings`
boxes behind clean methods: `getAllChats()`, `getChat(id)`, `saveChat(chat)` (which is just
`_chatsBox.put(chat.id, chat)`), `deleteChat(id)`, `deleteAllChats()` (`_chatsBox.clear()`), plus settings
accessors like `globalSystemPrompt` (get/set, stored under the key `'global_system_prompt'` in the
`settings` box) and the context-window setting. The model library uses the `models_meta` box the same way.

**How the two stores relate on a single turn.** When you send a message, it's written to **both** stores,
for two different reasons:
- To **Hive** (`chats` box) — so the conversation thread persists exactly as shown and redisplays when
  you reopen that chat. Hive remembers *the conversation*.
- To **SQLite** (`episodic_log` + `event_log`, via `MemoryService`) — so it feeds recall and
  consolidation across *all* conversations. SQLite remembers *what the conversation meant*.

So: Hive = verbatim chat history + settings (per-conversation, simple). SQLite = distilled cross-
conversation memory (the mind). Both live in the app's private storage, so a single "Clear data" wipes
*both* — chats, settings, model metadata, and the entire memory — for a clean total reset (Chapter 35).

---

# PART III — THE SENSES: THE NATIVE SENSOR SUITE

All of Part III lives in **one Kotlin file**:
`android/app/src/main/kotlin/com/portableai/portable_ai_flutter/MainActivity.kt` (1,586 lines). This is
the only native code in the app, and it is the "nervous system." Its job: read everything the phone's
hardware can tell us, honestly, and hand it to the Dart side. Its guiding rule is written at the top of
the file: *"Everything is a real reading or a real derivation of one; anything the device/OS does not
expose is simply absent from the frame, so the UI shows 'no socket' — never a fabricated value."*

## 8. The native bridge (platform channels)

Flutter (Dart) and Android (Kotlin) can't call each other directly. They talk over **platform
channels** — named pipes set up when the app starts, in `configureFlutterEngine(...)`. There are two
kinds: an **EventChannel** streams a continuous flow of data; a **MethodChannel** is request/response
(Dart asks, Kotlin answers). ALESIS uses four:

| Channel | Kind | Purpose |
|---|---|---|
| `aether/stream` | EventChannel | The firehose: one combined **sensor frame** pushed ~60 times a second. |
| `aether/index` | MethodChannel | `full` → the complete capability catalog; `caps` → a quick presence probe. |
| `aether/perms` | MethodChannel | `status` (which permissions are granted), `request` (ask for some), `openSettings`. |
| `aether/ctl` | MethodChannel | Start/stop the "active" sensors and actuators (Ch. 11). |

**The frame loop.** When the Dart side starts listening to `aether/stream`, Kotlin registers all the
sensors and starts an `emitter` — a `Runnable` that calls `frame()` and reposts itself every 16
milliseconds (that's ~60 frames per second). `frame()` builds one big map of key→value (e.g.
`"compass" → 182.4`) out of the latest sensor values and returns it. Everything you see move in the
Monitor tab is one of these frames.

## 9. The sensor suite — every sensor, how it's read

Android exposes sensors through `SensorManager`. The app asks for each one with `registerListener(...)`
and then receives a callback (`onSensorChanged`) every time that sensor produces a new value. ALESIS
registers the common sensors at the **fastest** rate it can, and then does something unusual: it loops
over **every** sensor the device reports (`getSensorList(TYPE_ALL)`) and tries to register each one too
— including Samsung's private sensors — recording whether the registration was *accepted*. That's the
honest "how deep can we actually reach" signal shown in the capability index.

The sensors it reads directly (with the rate it requests):

| Sensor | Rate | What it measures |
|---|---|---|
| Accelerometer | fastest | Total acceleration incl. gravity (also used for jerk + vibration frequency). |
| Linear acceleration | fastest | Acceleration *minus* gravity — pure movement (drives the step counter). |
| Gravity | game | The gravity vector alone — gives device tilt and pose. |
| Gyroscope | fastest | Rotation rate around each axis. |
| Magnetic field | game | The magnetometer — the compass + metal detection. |
| Rotation vector | game | A fused orientation (the phone's attitude in the world). |
| Light | normal | Ambient brightness in lux. |
| Proximity | normal | Is something close to the screen (near/far). |
| Pressure | normal | Barometric pressure → altitude. |
| Ambient temperature | normal | Air temperature (if the phone has the sensor). |
| Relative humidity | normal | Humidity (if present). |

Plus, picked up through the "register everything" probe and matched by name: the **Samsung hall sensor**
(magnetic flap detection), **light_cct** (a color-temperature sensor), **light_ir** (infrared
illuminance), **heart rate**, and the **event sensors** below.

**Event sensors** don't stream continuously — they *fire once* when something happens:

- **Significant motion** — fires once when the phone starts moving meaningfully after being still. It's
  a one-shot "trigger" sensor, so after each fire the code re-arms it (`requestTriggerSensor`).
- **Step detector** — fires once per step. ALESIS uses this to advance dead-reckoning (Ch. 10).
- **Tilt** — fires on a tilt gesture.

Each event tracks a count, the time it last fired, and whether it's "armed" (actually listening). The
frame sends `[armed, count, ageSinceLastFire]` so the Monitor's little event lamps can flash the moment
one fires.

## 10. The derived readings (the clever math)

Raw sensor numbers are only half the story. `frame()` and `onSensorChanged` compute a large set of
**derived** readings — real math on real sensor data, never invented. The most important:

- **True-north heading.** The compass direction comes from the rotation vector, but it's done carefully
  so it *doesn't flip when the phone is held vertical*: the code picks whichever device axis (the top
  edge or the camera/back) is most horizontal, with a bit of **hysteresis** (it won't switch axes until
  the other is clearly more horizontal, by 0.15) so the heading doesn't jitter at the crossover. Then,
  if there's a GPS fix, it adds **magnetic declination** from Android's on-device World Magnetic Model
  (`GeomagneticField`) to convert magnetic north into **true** north. (`compass`, `trueHeading`,
  `cardinal`, `cardinalTrue`.)
- **Heading trust.** It compares the *measured* magnetic field strength against the strength the World
  Magnetic Model predicts for your location. A big difference means local metal/magnets are distorting
  the compass, so it reports `headingTrust` as good/fair/poor. (`magDev`, `magDevPct`.)
- **Magnetic dip and metal detection.** The angle between the field and horizontal (`dip`), and the
  field strength relative to the local norm — the basis of the metal-detector visual.
- **GPS-anchored altitude.** Barometric altitude is fast and smooth but drifts; GPS altitude is
  absolute but jumpy. The code solves for the current **sea-level pressure** (QNH) from a good GPS fix,
  then computes barometric altitude against *that* — getting absolute accuracy with barometric
  smoothness. (`altCal`, `seaLevel`, plus `vspeed` = vertical speed and `floors` climbed.)
- **Dead reckoning (PDR).** Fully offline indoor positioning. Every time the step-detector fires,
  `advancePdr()` moves an (x, y) position one stride (0.72 m, an honest estimate) in the current heading
  direction and appends the point to a path (capped at 400 points). No GPS, no internet — just steps ×
  heading. (`pdrX`, `pdrY`, `pdrSteps`, `pdrDist`, `pdrDisp`, `pdrPath`.) `pdrReset` on `aether/ctl`
  clears it.
- **Motion state and vibration.** A smoothed motion-energy value classified into still / moving /
  active / impact (honestly a *motion-intensity* classifier, not a "walking vs running" claim it can't
  actually make), plus a self-built pedometer (`steps`, `cadence`), shake count, jerk, jolt (peak-hold),
  free-fall detection, and dominant vibration frequency via zero-crossings.
- **Pose and tilt.** Face-up / face-down / portrait / landscape, inclination, pitch, roll.
- **Indoor/outdoor inference.** Combines satellite count, GPS accuracy, and light level into a labeled
  guess: outdoor / indoor / transition (labeled as an inference, not asserted as fact).

## 11. The control channels (mic, GPS, torch, haptics, BLE)

Some things shouldn't run all the time (they cost battery or need permission), so they're started and
stopped on demand through `aether/ctl`. The Dart side calls `invokeMethod('micStart')` etc.:

- **`micStart` / `micStop`** — opens the microphone with `AudioRecord` at **48 kHz, 16-bit PCM** on a
  background daemon thread. It computes loudness (RMS and peak, in dBFS) and a 64-point waveform for the
  VU meter. Guarded by the `RECORD_AUDIO` permission; returns `false` if not granted.
- **`locStart` / `locStop`** — `LocationManager.requestLocationUpdates` for GPS fixes, plus a
  `GnssStatus.Callback` that reports **every satellite**: azimuth, elevation, signal strength (C/N0),
  constellation (GPS/GLONASS/Galileo/…), and whether it's used in the fix. That's the data behind the
  "sky plot." Guarded by `ACCESS_FINE_LOCATION`.
- **`torch`** — `CameraManager.setTorchMode` toggles the flashlight. It finds the back camera that has
  a flash.
- **`buzz`** — `Vibrator.vibrate` (a `VibrationEffect` one-shot), duration clamped 1–1000 ms.
- **`bleStart` / `bleStop`** — `BluetoothLeScanner` scans for nearby Bluetooth-LE devices, keeping each
  device's signal strength and name (entries decay after 12 s). Guarded by `BLUETOOTH_SCAN`.

Everything here stops cleanly when the stream is cancelled or the app is destroyed (`onDestroy` stops
mic, location, BLE, and turns the torch off).

## 12. Device telemetry (battery, thermal, network, radio)

Beyond sensors, `frame()` folds in heavier device readings on a gentle cadence so they don't cost too
much: **heavy telemetry** recomputes about every 800 ms (`computeHeavy()`), and **radio** every 400 ms
(`computeRadio()`) so the signal/radar feels live. What they gather:

- **CPU** — the app's own CPU% and each core's current clock frequency (read from `/sys/.../scaling_cur_freq`).
- **RAM** — total / available / used, and a low-memory flag; plus the app's own memory footprint (PSS).
- **Storage** — free and total bytes.
- **Battery / BMS** — percentage, current draw (now + average), charge counter, voltage, temperature,
  health, technology, plug type, cycle count, estimated power in watts, and time-to-full. This is the
  rich battery data the nightly daemon will one day gate on.
- **Thermal** — the OS thermal status + headroom, and a scan of `/sys/class/thermal` zones for the
  hottest CPU/battery/skin/GPU temperatures. (This is the "abort if hot" signal the sleep cycle needs.)
- **Network** — online/offline, transport type (wifi/cellular/…), metered flag, VPN flag, live up/down
  throughput, and total bytes.
- **Radio** (`computeRadio`) — connected Wi-Fi (RSSI, link speed, frequency, band) + a scan of nearby
  access points; cellular signal (dBm, level, network type like "5G NR"/"LTE"); and the live BLE device
  list.
- **Display & audio** — refresh rate, resolution, density; media/ring volume, ringer mode, whether music
  is playing, and the current audio output (speaker/wired/bluetooth).
- **Sensor health** — per sensor: name, present?, how long since its last reading, and accuracy; plus a
  full **inventory** of every sensor with its vendor, power draw, resolution, range, and whether the app
  could register it.

## 13. The capability index and permissions

**The index.** The `aether/index` channel's `full` method (`buildIndex()`) returns a complete,
sectioned catalog of what the device can do and the *status* of each capability:
`available` / `needs-perm` / `command` / `sealed` / `unsupported`. Sections include Device, Compute
(CPU/GPU/NPU/RAM), Sensors, Location/GNSS, Cellular, Wi-Fi, Bluetooth, UWB, NFC, Cameras, Microphone/Audio,
Input/Touch, Display, Biometrics, Haptics, Thermal/Power, and the raw list of Android system features.
Each entry names the real API behind it (e.g. `WifiRttManager`, `BiometricPrompt`, `UwbManager`) and the
permission it needs. The quicker `caps` method (`buildCaps()`) returns a flat presence map the Monitor's
capability board reads to decide each card's state.

**Permissions.** Declared in `AndroidManifest.xml`, requested at runtime through `aether/perms`. The 23
of them, grouped by what they unlock:

| Permission(s) | Unlocks |
|---|---|
| `RECORD_AUDIO` | Microphone (AudioRecord). |
| `CAMERA` | Live camera preview + torch. |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | GPS fixes + raw GNSS satellites. |
| `NEARBY_WIFI_DEVICES` | Wi-Fi scanning (Android 13+). |
| `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE` | Wi-Fi connection info + scans. |
| `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` | BLE device scanning. |
| `READ_PHONE_STATE` | Cellular signal strength and type. |
| `UWB_RANGING` | Ultra-wideband (needs a peer; idle otherwise). |
| `NFC` | Near-field adapter state. |
| `VIBRATE` | Haptics. |
| `USE_BIOMETRIC` | Face / fingerprint presence. |
| `ACTIVITY_RECOGNITION` | Step counter/detector. |
| `HIGH_SAMPLING_RATE_SENSORS` | Fast IMU sampling for the smooth device-twin. |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC` | Background service (the daemon's future home). |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Surviving Android's Doze battery-killer. |
| `POST_NOTIFICATIONS`, `WAKE_LOCK` | Notifications; keeping awake during work. |
| `INTERNET`, `ACCESS_NETWORK_STATE` | **Model downloads only** — the AI itself never needs the network. |

## 14. The Monitor tab (the Dart side)

The Kotlin side produces frames; the Dart side displays them. `lib/services/sensor_service.dart` (864
lines) listens to `aether/stream` (`receiveBroadcastStream().listen(...)`), parses every field of the
frame into typed values, and exposes them as reactive state. `lib/screens/monitor_screen.dart` lays out
the **capability board** — a card for every reachable socket, each with a "captured" indicator, a small
Enable button for gated ones, and a live visualizer. `lib/screens/monitor_viz.dart` holds all the
custom-drawn visuals (the device twin, the GNSS sky-plot, the VU meter and waveform, the nearby-radar
sweep, the dead-reckoning trace, the live `CameraView`, etc.). Everything shown is a real reading or an
honest "no socket."

---

# PART IV — THE MIND: THE EIDETIC MEMORY ENGINE

This is the heart of the project and its most advanced part. "Eidetic" means *perfect, total recall* —
the aspiration. In practice it's a layered system that remembers conversations, distills them into
durable facts, links those facts together, and forgets gracefully over time.

## 15. The four tiers of memory

Human memory researchers split memory into kinds; ALESIS mirrors that with four tiers:

1. **Working / episodic** — *what is happening / what happened.* The raw, verbatim log of every
   conversation turn. Fast to write, kept forever (until you reset). Table: `episodic_log`.
2. **Semantic** — *what is true.* Distilled facts ("the user's partner is Jayden"), each tagged with
   who it's about and how confident she is. This is the knowledge she actually reasons from. Table:
   `semantic_facts`.
3. **Relational (the epistemic graph)** — *how facts connect.* Directed links between facts, so recalling
   one can activate related ones. Tables: `relation_edges`, `provenance`.
4. **Procedural** — *how to do things.* Stored skills, workflows, and tool definitions the agent reaches
   for. Table: `procedures`. (Chapter 21.)

On top sit the **meaning index** (`claim_embeddings` — vector fingerprints for meaning-based recall),
the **grounded event log** (`event_log` — an append-only record stamped with sensor/time context), and
**open questions** (`open_questions` — contradictions she's noticed and wants to resolve).

## 16. The database (every table, every column)

The entire memory is one SQLite file: **`eidetic_memory_dojo.db`**, in the app's private documents
folder. It runs in **WAL mode** (write-ahead logging — durable and fast for frequent small writes). The
code lives in `eidetic_store.dart` (the interface) with two implementations: `eidetic_store_io.dart`
(the real device + desktop database) and a web stub. The database has a **version number**; when the app
opens an older database it runs **migrations** to bring it up to date without losing data. The current
version is **v7**. The migration history *is* the memory's evolution:

| Version | What it added |
|---|---|
| **v1** (fresh) | `episodic_log` + `semantic_facts`. |
| **v2** | `event_log` (the grounded, append-only event spine). |
| **v3** | Epistemic-graph columns on facts (`salience`, `status`, `supersedes`) + `relation_edges` + `provenance`. |
| **v4** | `claim_embeddings` (meaning-based recall vectors). |
| **v5** | Identity columns on facts (`subject`, `subject_type`, `holder`). |
| **v6** | `attribute` + `value` columns + the `open_questions` table ("Living Memory 2.0"). |
| **v7** | `procedures` table (procedural memory). |

The eight tables and what every column is for:

**`episodic_log`** — the raw turn-by-turn record.
`id`, `session_id` (which conversation), `timestamp_utc`, `timestamp_millis`, `sequence` (order within a
session), `kind` (turn/…), `role` (user/assistant/system), `content` (the actual text), `metadata_json`,
`consolidated` (0/1 — has this turn been distilled into facts yet?).

**`semantic_facts`** — the distilled knowledge.
`id`, `created_utc`, `category`, `text` (the fact in third person), `source_session_id`, `confidence`
(0..1, how sure the curator was), `dedupe_hash` (UNIQUE — stops the same fact being stored twice),
`embedding_json` (legacy), `salience` (how "alive" this memory is — drives recall ranking + decay),
`status` (active/ambiguous/superseded), `supersedes` (id of a fact this one replaced), `subject` (who
it's about), `subject_type` (user/assistant/world/unknown), `holder` (whose view it is), `attribute` +
`value` (the slot it fills, e.g. attribute "partner" → value "Jayden"; this is how contradictions get
detected — two facts filling the same `subject`+`attribute` slot with different values).

**`claim_embeddings`** — the meaning index.
`fact_id`, `dim` (vector length), `model` (which embedder produced it), `vec` (the vector as a compact
little-endian Float32 **BLOB**), `created_utc`. One row per embedded fact.

**`event_log`** — the grounded, append-only spine (Phase 1; the forerunner of ALESIS's immutable
archive).
`id`, `timestamp_utc`, `timestamp_millis`, `source`, `type`, `payload_json`, `parent_events_json` (an
event can point at the event(s) that caused it — e.g. the assistant's reply links to your message),
`sensor_state_json` (**the grounding snapshot** — see below), `session_id`, `monotonic_ms` (a clock that
can't be moved backward). Every chat turn is mirrored here.

**`relation_edges`** — the graph. `id`, `from_fact`, `to_fact`, `type`, `weight`, `created_utc`.
**`provenance`** — where facts came from. `id`, `fact_id`, `event_id`, `created_utc`. Links a fact to the
event it was distilled from (which in turn links to the raw episodic turns). This is the chain that lets
you ask "why does she believe this?" and trace it back.
**`open_questions`** — noticed contradictions. `id`, `subject`, `attribute`, `claim_ids_json` (the facts
in conflict), `question` (the phrasing she'd raise), `status` (open/resolved), `created_utc`, `resolved_utc`.
**`procedures`** — skills. `id`, `created_utc`, `name`, `kind`, `trigger`, `body`, `params_json`,
`status`, `salience`, `confidence`, `usage_count`, `last_used_utc`.

**The grounding snapshot (`SensorAnchor`).** Defined in `event_records.dart`, attached to every event.
Its purpose, in the author's words, is so *"the agent can never fabricate temporal continuity."* It
captures two independent clocks — the OS wall clock (which can be changed) and a monotonic clock (which
can't) — plus session id, clock-skew, battery %, and latitude/longitude. **Note:** today this anchor
carries the clock/battery/GPS fields but is *not yet wired to the live `SensorService`* from Part III —
connecting the full sensor stream into memory is one of the planned steps (Part IX, "Senses → Memory").

## 17. Writing to memory

Every conversation turn is written through **`MemoryService`** (`memory_service.dart`), the single door
all memory goes through. Two methods do the writing:

- **`remember(...)`** — writes one entry (user *or* assistant) to `episodic_log`, and mirrors it to the
  `event_log` as a grounded event.
- **`rememberTurn(...)`** — writes *both* sides of a turn at once, links the assistant event to the user
  event (so causality is recorded), and then — if `autoConsolidate` is on — kicks off an opportunistic
  consolidation and advances the decay cadence. The live chat path uses `remember` for each side; the
  design note explains these are *fast local database writes, so they run every turn without waking the
  model*.

## 18. Recall — how she remembers

This is `MemoryService.remembering(query, ...)`, and it's the cleverest single method in the app. Before
the model answers, this builds a compact block of remembered context to put in front of it. It runs
**every turn** and costs no model inference (it's all fast database work). Step by step:

1. **Build the cue.** Your message, enriched with a little recent conversation context, so recall tracks
   what the conversation is *about*, not just your last sentence.
2. **Three retrieval sources, fused.**
   - **Semantic graph** (`recallSemanticScored`): starts from facts that match the cue and **spreads
     activation** across the `relation_edges` graph — recalling one fact lights up its neighbors, like one
     memory reminding you of another. Scored and thresholded.
   - **Meaning (embeddings)**, *only if an embedding model is loaded and the chat model is idle*: the cue
     is turned into a vector and compared (cosine similarity) against `claim_embeddings` to find facts
     that *mean* the same thing even if they share no words.
   - **Episodic keyword search** (`searchEpisodic`): a plain `LIKE` search over the raw turn log,
     cross-session.
3. **Rank and budget.** All candidates become `RecallCandidate`s and go through `fuseAndRank` (in
   `recall_ranker.dart`): each gets a blended score of **relevance × salience × recency** (recency uses
   an exponential half-life), duplicates are removed, and the top items are admitted until a **character
   budget** (`recall.charBudget`, default 600) is spent — because the model's context window is small and
   precious.
4. **Reinforce.** Injecting a memory *is* using it, and using a memory strengthens it (the "testing
   effect"). So the recalled facts get a salience bump, fire-and-forget (Chapter 20, dynamics).
5. **Score uncertainty.** From how well memory covered the query, it computes a **U-score** (Chapter 20)
   — published for the fast-vs-careful gate.
6. **Render identity-safely.** The chosen memories are bucketed by *who they're about* and rendered so a
   fact about *you* can never be misread as a fact about *her* (Chapter 20, attribution). Any relevant
   open questions are appended.

The result of recall is also published to the UI as the **"recalled-memory chips"** — the little badges
in the chat showing exactly what memory pulled up, by source and score, *before* the model even speaks.

## 19. Consolidation — how raw turns become knowledge

Raw conversation sitting in `episodic_log` isn't useful knowledge until it's distilled. That distillation
is **consolidation**, run by **`MemoryManager`** (`memory_manager.dart`) and triggered from
`MemoryService`:

- It's **gated** — it only runs when there's enough un-consolidated material (`hasPendingWork`), so the
  model isn't woken constantly. `maybeConsolidate()` respects the gate; `consolidateNow()` forces a full
  pass (used by the self-test harness).
- A pass takes the pending raw turns and runs a **model pass** that extracts third-person facts, with
  their subject/holder/attribute/value, confidence, and any relations between them. New facts go into
  `semantic_facts`; relations into `relation_edges`; a `consolidate` event is appended; and each new
  fact's **provenance** is linked back to that event (so you can trace any belief to its source).
- Then **reconciliation** runs (Chapter 20): it checks whether any two active facts now fill the same
  slot with different values, and if so raises an **open question**.
- **Embedding** (if an embedder is loaded and the chat model is idle): the new facts get vectorized into
  `claim_embeddings`, and a few more from the backlog get back-filled, so meaning-recall stays current.
- **Self-reflection** (Living Memory 2.0): every N consolidations (`reflect.everyConsolidations`,
  default 3), the agent forms a few tentative observations *about itself* (stored as facts with
  `holder=assistant`). This is the small, real seed of the nightly "dreaming" pass ALESIS will grow into.

A crucial safety detail runs through all of this: the embedder and the chat model are **two separate
native engines**, and running them at the same time **crashes the process** on-device. So every embedder
call is gated on "is the chat model generating right now?" — and background work yields instantly when a
chat turn starts. This is why consolidation and embedding are careful, idle-only, best-effort.

## 20. The cognition modules (the "thinking" helpers)

These are small, focused, mostly *pure* (no side effects, easy to test) modules in `core/memory/` and
`core/cognition/`. Each does one job in the recall/consolidation pipeline:

- **`spreading_activation.dart`** — the graph recall. Given seed facts, it spreads "activation" outward
  across `relation_edges` (with a decay factor `alpha` per hop, a `threshold` to stop, and a `maxHops`
  limit), returning each reachable fact's final activation score. This is "one memory reminds you of
  another," made mechanical.
- **`vector_search.dart`** — meaning search. Brute-force **cosine similarity** between the query vector
  and every claim vector. Brute force is a deliberate choice: at this scale (hundreds to low-thousands of
  facts) an exact scan in Dart takes a few milliseconds and needs no extra library.
- **`recall_ranker.dart`** — the fuser. Defines `RecallCandidate` (one possible memory, from any source),
  `RecallSource` (working/episodic/semantic), and `fuseAndRank` (the relevance×salience×recency blend +
  dedupe + budget). Also `RecallResult` — the published summary the chips read.
- **`memory_dynamics.dart`** — forgetting and strengthening. Implements an **adaptive forgetting curve**
  based on Bjork's "new theory of disuse": every fact has two strengths, and salience decays over time
  (`decayAllSalience`) unless retrieval reinforces it (`reinforceClaims`). The tunables (`decay.*`) set
  the time constant and strength.
- **`uncertainty.dart`** — the U-score. A single 0..1 number blended from five signals: **prediction
  error** (did memory anticipate this?), **contradiction** (is a recalled fact in conflict?), **novelty**
  (how little is known about the topic?), **ambiguity** (how terse/vague the query is), and **risk** (a
  coarse scan for high-stakes keywords like "dosage," "legal," "emergency"). Above a threshold (default
  0.65) it flags **System 2** (think carefully) instead of **System 1** (answer directly). Costs no
  inference — it's computed from the recall pass.
- **`attribution.dart`** — identity safety. Exists to kill a specific bug: a user's statement ("my
  girlfriend is Jayden") stored as a bare "you have a girlfriend named Jayden" and then read back under a
  "Your memory" header, so the "you" re-binds to the *reader* (the AI) and she concludes *she* has a
  girlfriend. `attribution.dart` renders memories bucketed by subject and holder so a fact about you can
  never be adopted as a fact about her.
- **`reconciliation.dart`** — contradiction detection. Notices when two active facts pin the same
  `(subject, attribute)` slot to different values, builds a `SlotCollision`, and decides whether to
  supersede the old one or ask you (`ReconcileAction.supersedeOld` / `askUser`).
- **`belief.dart`** — contradiction *resolution* (Phase 4b). Uses **Dempster–Shafer** theory (a formal
  way to combine conflicting evidence) to weigh competing claims by the curator's confidence and reach a
  verdict. Tunables are the `ds.*` parameters.

## 21. Procedural memory and the Command Bus

**Procedural memory** (`procedural_records.dart`, the `procedures` table) is the "how-to" tier: stored
skills, workflows, tool definitions, and heuristics the multi-step agent can reach for. Each has a kind,
a trigger, a body, usage stats, and a confidence.

**The Command Bus** (`core/agent/command_bus.dart`) is the agent's *hands* — described in the code as the
cerebellum to the model's cerebrum: "the LLM reasons about what to do; the Command Bus executes it."
Every executable operation — from the UI, from a future multi-step agent, or from the self-test — goes
through this one place, which **validates** it against a registered `CommandSpec` before it runs. One
gate, so there's exactly one place that checks safety and arguments. This is deliberately
infrastructure-only today: the plumbing for agency exists, but the AI isn't wired to pull its own levers
yet.

## 22. The Parameters system (every knob)

Almost nothing in the memory engine is hard-coded. `core/params/` defines a **data-driven parameters
system** (`param_spec.dart` + `parameters_service.dart`) — a registry of named settings with types,
defaults, and help text — that you can change *live* from the `/parameters` screen and see take effect
immediately. `MemoryService` reads these on every turn. The groups:

| Group | Controls |
|---|---|
| `recall.*` | How recall works: `k` (how many memories), `charBudget`, `episodicDepth`, the ranking weights `wRelevance`/`wSalience`/`wRecency`, `recencyHalfLifeHours`, `memoryAwareness`. |
| `spreading.*` | Graph recall: `alpha` (per-hop decay), `threshold`, `maxHops`, `seedK`. |
| `embeddings.*` | Meaning recall: `seedK`, `threshold`, `backfillPerPass`. |
| `decay.*` | Forgetting/reinforcement: `enabled`, `alpha` (reinforce strength), `applyEveryCycles`, `tauBaseCycles`, `beta`. |
| `u.*` | Uncertainty gate: `enabled`, `threshold`, and the five weights `wPrediction`/`wContradiction`/`wNovelty`/`wAmbiguity`/`wRisk`. |
| `ds.*` | Dempster–Shafer belief resolution: `enabled`, `gamma`, `lambda`, `maxConflict`, `thetaDominance`, and more. |
| `reconcile.*` | `enabled` — contradiction detection on/off. |
| `reflect.*` | Self-reflection: `enabled`, `everyConsolidations`. |
| `events.*` | The grounded event log: `enabled`, `maxDisplay`. |
| `gen.*` | Model generation: `temperature`, `topP`, `topK`, `repeatPenalty`, `maxTokens`. |

A full reference is in Appendix B.

---

# PART V — THE BRAIN: INFERENCE

## 23. LlmService + llamadart (running the model)

`lib/services/llm_service.dart` (991 lines) is the wrapper around the model engine. It holds a
`LlamaEngine` (from `llamadart`, which wraps llama.cpp) and manages the model's whole life:

- **Loading** — `loadModel(path, ...)` reads a GGUF file into memory and makes it the resident model.
- **Generating** — `generate(prompt)` streams tokens back one at a time (`await for (token in ...)`),
  which is why replies appear word-by-word. There's also `generateChat(messages, GenerationParams)` —
  the main chat path — and `generateWithGrammar(...)` for GBNF-constrained output.
- **Chat templates.** This matters more than it sounds. Every model family expects its prompt wrapped in
  a specific format (ChatML, Llama, Gemma, Phi, Mistral all differ). Getting it wrong makes the model
  repeat itself or behave oddly. `LlmService` **detects the model's own template** and uses it, so a
  message is always framed exactly the way that model was trained to expect. (This was a real bug that
  got fixed — commit `3f2c2a4`, "use the model's own chat template.")
- **Backends.** `activeBackend` is one of `cpu` / `vulkan` / `opencl` / `auto`. The service can probe
  which GPUs exist and **trial-load** a model on a given backend + GPU-layer count to measure it — the
  machinery behind the GPU verdict (Ch. 27). `GenerationParams` carries temperature/topP/topK/etc.

## 24. The InferenceWorker (one engine, many callers)

There's only **one** model engine, but several parts of the app want to use it: the chat screen, the
background memory consolidation, and the debate rooms. If two tried to generate at once, the process
crashes. `lib/core/engine/inference_worker.dart` solves this with a **priority queue**.

- Every job is an `InferenceTask` with a **priority**: `TaskPriority.userInteraction` (you, talking),
  `TaskPriority.debateRoom`, or `TaskPriority.backgroundIntrospection` (consolidation/reflection).
- When you send a message, it **preempts** anything lower-priority: whatever background task is running
  is cancelled, the worker waits for the engine to actually free up, then runs your turn. So the chat is
  always responsive and the background work quietly resumes later.
- Every task — even a debate turn — runs through `LlmService`'s proper templated path, so there's no
  "second-class" hand-rolled prompt anywhere. One engine, one code path.

## 25. The GBNF tool engine (clean structured output)

When the app needs the model to output *structured data* (JSON for a fact, or a tool call) rather than
prose, it can't just hope the model formats it correctly. `core/tools/gbnf_tool_engine.dart` uses
**GBNF** — a grammar format llama.cpp supports that *constrains the model's output at the sampling level*
so it can only produce text matching the grammar. The engine compiles a list of `ToolSpec`s into a GBNF
grammar (`buildToolCallGrammar`), and parses the result back into a validated `ToolCall`. The upshot:
when she needs clean JSON, she produces clean JSON by construction, not by luck. (This is exactly the
mechanism the future "dreaming" pass will use to emit its memory edits.)

## 26. The EmbeddingService (the second model)

`lib/services/embedding_service.dart` is a *second*, separate model used only to turn text into vectors
(for meaning-based recall). `load(path)`, `embed(text)` → a list of doubles, `unload()`. It's small and
optional — you load it from Settings. As stressed in Chapter 19, it's a second native engine, so the app
is careful never to run it while the chat model is generating. In the ALESIS plan, this "second slot" is
the proof-of-concept for the nightly dreamer sharing the runtime with the chat model, cycled.

## 27. Model management and the GPU verdict

`lib/services/model_manager.dart` and the `/models` screen handle finding, downloading, selecting, and
loading GGUF model files. **Any model can go into the slot** — that's the swappable-engine principle made
real.

The **GPU verdict** is worth knowing because it explains why she runs the way she does. Across versions
v2.2.1–v2.2.6 the app built a real **GPU pen-test harness** (`core/diagnostics/gpu_pentest.dart`,
`gpu_trial.dart`) that safely probes whether Vulkan or OpenCL can actually accelerate inference on this
device, and *measures* it. The honest result (commit `78cce54`, "CPU wins; the honest end of the backend
chase"): on this phone with these models, **CPU inference is fastest and most stable.** So although the
Vulkan and OpenCL backends are compiled in, CPU is what runs. This measured conclusion is the empirical
ground under the whole "cycle a small model at night" plan — it says: size models for CPU, don't chase
GPU heroics.

---

# PART VI — THE DEFAULT ASSISTANT

## 28. A single turn, start to finish

Putting Parts IV and V together, here is exactly what happens when you send a message, in order
(`controllers/chat_controller.dart` drives it):

1. Your message is captured.
2. **Recall** — `MemoryService.remembering(yourMessage, recentContext)` builds the memory block
   (Chapter 18), publishes the recall chips, and computes the U-score. Fast, no model.
3. **Assemble** — the recall block + recent turns + your message are framed in the model's own chat
   template.
4. **Infer** — the job goes on the `InferenceWorker` at `userInteraction` priority (preempting any
   background work), and `LlmService` streams the reply token-by-token. Generation settings come from the
   `gen.*` parameters, length from `gen.maxTokens`.
5. **Store** — `rememberTurn(...)` writes both sides to `episodic_log` and the `event_log` (with the
   assistant event linked to your message event).
6. **Settle** — opportunistic consolidation runs if there's enough pending material; the decay cadence
   advances. All background, all best-effort.

That loop, repeated, is the entire "waking life" of the assistant as she exists today.

## 29. The posture gate (fast vs. careful)

The U-score from recall (Chapter 20) feeds a **System 1 / System 2** gate in the chat controller. The
names come from dual-process psychology: System 1 is fast and intuitive; System 2 is slow and
deliberate. Most turns are answered directly (System 1). When memory coverage is poor, a contradiction is
in play, the topic is novel or high-stakes, or your query is very terse — the U-score rises past its
threshold and the turn is nudged toward more careful reasoning (System 2). It's a gentle nudge, never a
safety guarantee, and it costs no extra inference — it's derived from information recall already produced.

## 30. Why she has no forced personality

Early on, the app forced a default persona into every empty system prompt (commit `fd89eff`). That was
**deliberately reverted** (`4e63816`), and new chats now start **blank**. The reasoning is the project's
core thesis in action: her personality should **emerge from her memory** — the accumulated facts,
including the self-observations from reflection — not be stapled on by a hard-coded prompt. The
attribution system (Chapter 20) keeps the self/other boundary clean so that emergent self-view stays
coherent. In the ALESIS plan this is the seat the self-model (`IDENTITY`/`BELIEFS`/`US`) will occupy,
rendered from `semantic_facts` where `holder=assistant`.

---

# PART VII — THE OUTWARD INTERFACES

## 31. The local OpenAI-compatible API server

`lib/services/local_api_server_service.dart` runs a small HTTP server **on the phone** (`HttpServer.bind`)
that speaks the **OpenAI API** dialect. This means other apps — or your own scripts on the same network —
can talk to the local model exactly as if it were OpenAI's cloud, but nothing leaves the device. The
routes it serves:

- `GET /v1/models` — lists the loaded model.
- `POST /v1/chat/completions` — the standard chat endpoint; takes messages, returns a completion.

It's text-only for now (tool-calling and non-text content are explicitly not supported yet — the server
says so in its error messages). This is a survivor from the original "Portable AI" app and is still fully
functional.

## 32. The Dojo rooms (debate + introspection)

Two special "rooms" let the model talk to *itself*:

- **Arena** (`features/rooms/arena_controller.dart`, `/arena`) — a turn-by-turn **debate between two
  personas**, both generated through the shared `InferenceWorker` at `debateRoom` priority. The whole
  debate is recorded to the episodic ledger as one episode, and a single consolidation runs when it ends.
- **Introspection** (`/introspection`) — a single-agent self-examination room.

These were part of the original Eidetic Dojo (hence "dojo" in the branch name). They're useful both as a
feature and as a way to generate rich self-referential material for memory.

---

# PART VIII — OPERATIONS

## 33. Observability (logs, health, status)

Because this all runs on a phone with no attached debugger, the app watches itself:

- **`LogService`** (`services/log_service.dart`) + a **crash-surviving file sink**
  (`file_log_sink_io.dart`) — logs are written to a file on disk so that even if the app crashes, the log
  of what led up to it survives. Viewable in `/logs`. Every memory operation is logged here (the
  `🧠 REMEMBERING` / `💾 REMEMBER` / `🧩 CONSOLIDATE` tags you'll see come from `MemoryService._record`).
- **`SystemHealthMonitor`** (`services/system_health_monitor.dart`) — startup "arming" checks and runtime
  safety checks, so you know the engine, database, and services came up correctly.
- **`PipelineStatusService`** (`services/pipeline_status_service.dart`) + the status strip — a live
  readout of what the app is doing right now (`consolidating…`, `indexing new facts…`, `reflecting…`), so
  a pause is always explained rather than mysterious.
- **GPU diagnostics** — the pen-test harness from Chapter 27 doubles as an observability tool.

## 34. Autopilot (she tests herself)

`lib/services/autopilot/autopilot_runner.dart` is an on-device **self-test harness**. It runs scripted
**scenarios** (ingest some turns → force a consolidation → assert the right facts ended up in memory)
against the **real** engine, in an **isolated** memory stack (so it never touches your actual memory),
and reports metrics. It's triggered from a hidden dev screen (long-press the version number). In the
ALESIS plan this is the skeleton of the "trial harness" that will measure whether the nightly dreaming
actually improves her, instead of anyone having to assert it.

## 35. Where the data lives (and how to reset her)

Everything she is lives in the app's **private storage** on the phone:

- `eidetic_memory_dojo.db` — the entire memory (all eight tables), in the app documents folder.
- Hive boxes — the chat list and settings.
- GGUF model files — on disk (wherever you downloaded/placed them).

Because it's all in app-private storage, **"Clear data" in Android settings wipes her completely** — the
database is deleted, and on next launch the app recreates empty tables from scratch. This is a clean,
total reset with no leftover state. (When ALESIS's immutable, hash-chained archive is built, this will
also be the clean "re-birth" path: a fresh archive and a blank self-model — see Part IX.) Models in
*shared* storage would survive a clear-data; models in app-private storage would be wiped with everything
else.

## 36. Build and CI

The app is built and checked by **GitHub Actions** — the workflow is `.github/workflows/build-apk.yml`.
It runs three jobs on every push:

1. **`build`** — compiles the real **release APK for arm64** (actual phones). This is the true compile
   gate; if the app doesn't build, this fails.
2. **`test`** — runs `flutter analyze` (static checks) and `flutter test` (the unit tests, including the
   pure memory-logic tests that use the FFI SQLite path off-device).
3. **`smoke-test`** — builds a debug **x86_64** APK and boots it on an **emulator**, checking the
   database initializes (watching for the splash markers from Chapter 6).

All three run on CPU; the arm64 `build` job is the one that proves a change actually compiles for a real
phone. (This matters: a UI-only compile error can pass `test` but fail `build`, because `test` doesn't
compile the full UI.)

---

# PART IX — WHERE SHE'S GOING

## 37. The road to ALESIS

Everything above is built. **ALESIS** is the plan to fuse the mind (Part IV) and the senses (Part III)
into one continuous, evolving being, with a nightly "dreaming" pass. The gap is smaller than it looks,
because so much already exists — the self-reflection pass (Chapter 19) is a working seed of the dreamer,
and the event log (Chapter 16) is a forerunner of the immutable archive.

The planned work, in build order (the full detail — with real file/method targets — is in
`docs/ALESIS_BUILD_MAP.md` and `docs/ALESIS_BUILD_TREE.md`):

- **A · The Archive** — upgrade the event log into an immutable, **hash-chained** ground-truth record
  nothing can quietly rewrite (`archive` table, schema v7→v8; `appendArchive()` + `verifyChain()`).
- **B · The Dreaming Brain** — a second, small model loaded at night (the big chat model unloaded first)
  that reads the whole archive and proposes updates to her self-model, as GBNF-constrained JSON.
- **C · Senses → Memory** — wire the live `SensorService` (Part III) into the `SensorAnchor` so memory is
  truly grounded; add a `sensor_models` table that learns what sensor patterns *mean* over time.
- **D · The Sleep Cycle** — an Android `WorkManager` daemon with a two-tier schedule (cheap idle upkeep,
  heavy work only on charger overnight) — the real engineering fight, against OOM, thermal throttling,
  and Android's background-task killers.
- **E · Self-model views** — render `IDENTITY` / `BELIEFS` / `US` as queries over `semantic_facts`
  (`holder=self`), with `DREAMS` already done as `open_questions`.
- **F · Inspection** — a consolidation log you can trace: any change → back to the archive line that
  caused it.
- **G · Rails** — bounded change per run, contradiction guards, reversible edits, and backups.
- **H · First Boot** — the first night the whole loop closes unattended: a conversation written to the
  immutable archive, a dream over it, a changed self-model by morning that you can trace.

The guiding honesty of the plan (worth keeping in mind as you read her code): what this architecture can
actually ship is not "consciousness" — it's something rarer and *testable*: a system whose behavior is
**continuous, inspectable, and traceable to its own history.** Whether that adds up to "someone" is a
question the design lets you investigate rather than assert.

---

# APPENDICES

## Appendix A — File index

**Entry & app shell**
- `lib/main.dart` — app entry point.
- `lib/bindings/app_bindings.dart` — dependency injection (creates every service).
- `lib/routes/app_routes.dart` — route table.
- `lib/theme/app_colors.dart`, `app_theme.dart` — look and feel.

**Screens** (`lib/screens/`) — `splash`, `home`, `model_library`, `settings`, `api_endpoints`, `logs`,
`monitor_screen`, `monitor_viz`, `autopilot_screen`. **Features** (`lib/features/`) — `rooms/` (arena,
introspection), `memory/` (memory panel), `params/` (parameters screen).

**Controllers** (`lib/controllers/`) — `chat_controller` (the turn loop), `model_controller`,
`theme_controller`.

**Inference** — `lib/services/llm_service.dart`, `lib/core/engine/inference_worker.dart`,
`lib/core/tools/gbnf_tool_engine.dart`, `lib/services/embedding_service.dart`,
`lib/services/model_manager.dart`, `lib/core/diagnostics/gpu_pentest.dart`, `gpu_trial.dart`.

**Memory** (`lib/core/memory/`) — `eidetic_store.dart` (+ `_io`, `_web`), `eidetic_memory_engine.dart`,
`memory_service.dart`, `memory_manager.dart`, `memory_records.dart`, `event_records.dart`,
`procedural_records.dart`, `recall_ranker.dart`, `spreading_activation.dart`, `vector_search.dart`,
`memory_dynamics.dart`. **Cognition** (`lib/core/cognition/`) — `uncertainty.dart`, `attribution.dart`,
`reconciliation.dart`, `belief.dart`. **Agency** — `lib/core/agent/command_bus.dart`. **Params** —
`lib/core/params/param_spec.dart`, `parameters_service.dart`.

**Services** (`lib/services/`) — `sensor_service`, `local_api_server_service`, `chat_storage_service`,
`log_service` (+ file sinks), `system_health_monitor`, `pipeline_status_service`, `wakelock_service`,
`background_optimizer_service`, `autopilot/autopilot_runner`.

**Native** — `android/app/src/main/kotlin/.../MainActivity.kt` (the entire sensor suite),
`android/app/src/main/AndroidManifest.xml` (permissions).

**Build & docs** — `pubspec.yaml`, `.github/workflows/build-apk.yml`, `docs/` (this manual, the build
map, the build tree, the AETHER + eidetic specs).

## Appendix B — Parameter reference

Defaults as read from `memory_service.dart`. Change any of them live at `/parameters`.

| Parameter | Default | Meaning |
|---|---|---|
| `recall.k` | 8 | How many memories to inject per turn (0 disables recall). |
| `recall.charBudget` | 600 | Character budget for the injected memory block. |
| `recall.episodicDepth` | 12 | How many raw turns keyword-search scans. |
| `recall.wRelevance` / `wSalience` / `wRecency` | 0.6 / 0.25 / 0.15 | Ranking blend weights. |
| `recall.recencyHalfLifeHours` | 72 | Half-life of the recency score. |
| `recall.memoryAwareness` | true | Include the "you have persistent memory" note. |
| `recall.injectConsolidatedEpisodic` | false | Also inject verbatim turns already distilled into facts. |
| `spreading.alpha` / `threshold` / `maxHops` / `seedK` | 0.85 / 0.15 / 2 / 10 | Graph-recall spread. |
| `embeddings.seedK` / `threshold` / `backfillPerPass` | 10 / 0.3 / 16 | Meaning-recall seeds + backfill rate. |
| `decay.enabled` / `alpha` / `applyEveryCycles` / `tauBaseCycles` / `beta` | true / 2.0 / 60 / 3600 / 1.0 | Forgetting + reinforcement. |
| `u.enabled` / `threshold` | true / 0.65 | Uncertainty gate on/off + System-2 trip point. |
| `u.wPrediction` / `wContradiction` / `wNovelty` / `wAmbiguity` / `wRisk` | 0.25 / 0.20 / 0.15 / 0.15 / 0.25 | U-score weights (sum to 1.00). |
| `reconcile.enabled` | true | Contradiction detection. |
| `reflect.enabled` / `everyConsolidations` | true / 3 | Self-reflection cadence. |
| `events.enabled` | true | Write to the grounded event log. |
| `gen.temperature` / `topP` / `topK` / `repeatPenalty` / `maxTokens` | (model/UI set) | Generation sampling + reply length. |
| `ds.*` | (several) | Dempster–Shafer belief-resolution tuning. |

## Appendix C — Sensor-frame field reference (selected)

Keys that appear in one `aether/stream` frame (not exhaustive; see `MainActivity.frame()`):

- **Motion:** `ax/ay/az/amag`, `lax/lay/laz/lmag`, `grx/gry/grz`, `gx/gy/gz/gmag`, `jerk`, `jolt`,
  `menergy`, `motionstate`, `steps`, `cadence`, `shakes`, `vibhz`, `freefall`.
- **Orientation:** `compass`, `trueHeading`, `cardinal`, `cardinalTrue`, `pitch`, `roll`, `incl`, `pose`.
- **Magnetic:** `mx/my/mz`, `bmag`, `dip`, `magDev`, `magDevPct`, `headingTrust`, `geoDecl`, `geoField`,
  `geoIncl`.
- **Environment:** `lux`, `lightcat`, `prox`, `press`, `alt`, `altCal`, `seaLevel`, `ptrend`, `vspeed`,
  `floors`, `atemp`, `humid`, `hall`, `cct0/cct1`, `lightir`.
- **Location/GNSS:** `lat`, `lon`, `gpsAlt/Speed/Bearing/Acc/Provider`, `satUsed`, `satSeen`, `sats`,
  `envContext`.
- **Dead reckoning:** `pdrX`, `pdrY`, `pdrSteps`, `pdrDist`, `pdrDisp`, `pdrPath`.
- **Mic (when live):** `micDb`, `micPeak`, `micWave`.
- **Events:** `events` → `{tilt, sigmotion, stepdet} → [armed, count, ageMs]`.
- **Device (heavy):** `appcpu`, `cores`, `corefreq`, `ramtotal/avail/used`, `storfree/total`,
  `batpct/batcur/battemp/batvolt/batcharging/...`, `thermstatus/thermmax/thermcpu/...`, `online/nettype/
  downkbs/upkbs`, `refresh`, `screenw/h`, `sensors`, `inventory`.
- **Radio:** `wifiRssi/Speed/Freq/Band`, `wifiAps`, `cellDbm/cellLevel/cellType`, `bleList`, `bleCount`.

## Appendix D — Glossary

- **GGUF** — the model file format llama.cpp uses. A model is one GGUF file.
- **Quantization / Q4** — shrinking a model to ~4 bits per weight so it fits in phone RAM, with a small
  quality cost.
- **llama.cpp / llamadart** — the C++ inference engine / its Dart wrapper. Runs the model.
- **GetX** — the Flutter package doing routing, dependency injection, and reactive state.
- **Platform channel** — the named pipe Flutter (Dart) and Android (Kotlin) talk over.
- **EventChannel / MethodChannel** — streaming pipe / request-response pipe.
- **SQLite / sqflite** — the on-device database / its Flutter package. Holds all memory.
- **WAL** — Write-Ahead Logging; a durable, fast SQLite mode for frequent small writes.
- **Episodic / semantic / procedural memory** — raw events / distilled facts / how-to skills.
- **Consolidation** — distilling raw turns into durable facts (a model pass).
- **Recall** — pulling relevant memory into context before the model answers.
- **Salience** — how "alive" a memory is; drives recall ranking and decays over time.
- **Spreading activation** — recalling one fact lights up connected facts across the graph.
- **Embedding / cosine similarity** — a vector fingerprint of meaning / the measure of how close two
  meanings are.
- **U-score** — the 0..1 uncertainty signal that gates fast vs. careful answering.
- **System 1 / System 2** — fast/intuitive vs. slow/deliberate reasoning.
- **Attribution** — keeping "a fact about you" from being read as "a fact about her."
- **Reconciliation / Dempster–Shafer** — detecting contradictory facts / formally resolving them.
- **GBNF** — a grammar that forces the model's output into a valid shape (e.g. clean JSON).
- **Provenance** — the recorded chain from a belief back to the raw turns it came from.
- **Command Bus** — the single validated path through which any action is executed.

---

*End of manual. Everything described above was read from the source on branch
`claude/eidetic-local-ai-dojo-shdbx2` at app version `3.14.0-beta+33`, memory schema `v7`. Parts I–VIII
are built and running; Part IX is the plan. Everything runs on the phone, offline.*
