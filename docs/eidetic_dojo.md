# Eidetic Local AI Dojo — engine, memory, and rooms

This document describes the Eidetic Dojo layer added under `lib/core/` and
`lib/features/rooms/`, how it maps to the original blueprint, where it
deliberately diverges, and how it was (and was not) verified.

## What was built

```
lib/core/
  engine/
    inference_worker.dart      Priority-serialised inference scheduler over LlmService
  tools/
    gbnf_tool_engine.dart      GBNF grammar synthesis + strict tool-call parsing
  memory/
    memory_records.dart        EpisodicEntry, SemanticFact, deterministic dedupe hash
    eidetic_store.dart         Store interface + in-memory impl + platform factory
    eidetic_store_io.dart      SQLite-backed store (native; FFI on Linux/Windows)
    eidetic_store_web.dart     Web fallback (in-memory)
    eidetic_memory_engine.dart Three-tier orchestrator (working / episodic / semantic)
    memory_manager.dart        The gate: summarise + curate, with a 0%-compute idle path
lib/features/rooms/
  arena_controller.dart        Dual-agent debate loop
  arena_screen.dart            Debate UI
  introspection_controller.dart  Gated, on-demand consolidation (idle by default)
  introspection_screen.dart    Introspection UI
```

Wiring: services/controllers are registered in `lib/bindings/app_bindings.dart`,
routes in `lib/routes/app_routes.dart` (`/arena`, `/introspection`), the memory
engine is initialised in `splash_screen.dart`, and both rooms are reachable from
the **Eidetic Dojo** section of Settings.

## Architecture

The brain (inference) and the notebook (memory) are decoupled. Inference runs
only when something explicitly asks for it; memory is plain local storage.

- **InferenceWorker** guarantees exactly one generation at a time, ordered by
  `TaskPriority` (`userInteraction` > `debateRoom` > `backgroundIntrospection`),
  with cancellation and preemption of background work by user work. It also
  defers while a direct `LlmService` generation (the chat screen) is in flight,
  so the single-flight invariant holds app-wide.

- **Three-tier memory** (per the continuous-offline-memory model):
  - *Working* — ephemeral RAM context, wiped when a response completes.
  - *Episodic* — a millisecond-timestamped SQLite ledger of every turn, tool
    call/result, reflection, and error.
  - *Semantic* — durable, curated facts/preferences/rules that survive reboots.

- **MemoryManager (the gate)** promotes episodic → semantic. It first does a
  cheap row-count check that runs **no inference**; only above a threshold does
  it wake the model for a single summarise-and-curate pass. Dart-side hard
  filters (length bounds, per-pass cap) plus a content-hash `UNIQUE` constraint
  prevent "database poisoning" from repeated or noisy writes.

## Deviations from the blueprint (and why)

The blueprint was followed in intent; these specifics were changed because the
literal version does not compile against this app or contradicts the
offline-memory design.

| Blueprint | What we did | Why |
|---|---|---|
| `llamadart` / `llamadart_native` as `path:` deps | Bumped the published `llamadart` to `^0.8.24` | Still pub.dev (native backends via the existing `hooks: user_defines` block, no separate package); 0.8.x adds the grammar-constrained sampling this layer now uses. |
| Raw FFI (`llama_init_from_file`, `native_llama_decode`) in a dedicated isolate | Priority scheduler over the existing `LlmService`/`llamadart` | `llamadart` already owns the native context off the UI isolate. A second owner via raw FFI is what *causes* the double-frees/SIGSEGVs the blueprint aimed to prevent. |
| `llama_index:` path dependency | Not added | `Auseven9/llama_index` is the **Python** framework; it cannot be a Flutter dependency. Semantic retrieval is provided directly by the SQLite tier. |
| `mcp_dart: ^0.1.0`, `Mutex` from `package:async` | Not added / not used | `mcp_dart` was unverifiable here and `Mutex` is not in `package:async`; the scheduler needs neither. |
| `sqflite` only | `sqflite` + `sqflite_common_ffi` behind a `dart.library.io` boundary, with an in-memory web fallback | Plain `sqflite` does not cover Linux/Windows/web; the conditional import keeps the web build free of FFI. |
| Introspection = `Timer.periodic(5m)` running inference forever | Idle by default; scheduled mode only wakes the model when `hasPendingWork()` is true | Matches "run the model only when there's actual work"; avoids keeping the neural net hot. |
| Per-turn writes to the vector store | Gated summarise + curate + dedupe | Prevents database poisoning. |

## GBNF constrained sampling (enabled)

With `llamadart ^0.8.24`, grammar-constrained sampling is wired end-to-end:

- `GbnfToolEngine.buildToolCallGrammar(tools)` / `buildJsonObjectGrammar()`
  produce real llama.cpp GBNF grammars (tool names constrained to the exact
  registered set).
- `LlmService.generateWithGrammar(...)` passes a grammar through
  `GenerationParams.grammar`, so the sampler can only emit conforming tokens.
- `InferenceWorker` carries an optional `grammar` per task, and
  `MemoryManager` uses `buildJsonObjectGrammar()` for its consolidation pass —
  the curator can only emit a JSON object, so promotion cannot misfire on a
  grammar-capable backend.

`GbnfToolEngine.parseToolCall` still runs as defence in depth, and remains the
sole guard on backends that cannot enforce grammars (e.g. some web/LiteRT
paths). Grammar constraints require a grammar-capable backend; the native
llama.cpp backends used on mobile/desktop support them, so a
`generateWithGrammar` call may throw `LlamaUnsupportedException` on a backend
that does not — `MemoryManager` treats that as a benign skipped pass.

Semantic retrieval has a parallel upgrade still open: `SemanticFact.embedding`
and the store already carry an optional vector column, so cosine ranking can
replace keyword search once embeddings are wired (llamadart exposes embeddings
from 0.9.0).

## Verification status

**This was written in an environment with no Dart/Flutter toolchain**, so it
could not be compiled or run here. Before merging, run locally:

```bash
flutter pub get
flutter analyze
flutter test            # includes test/gbnf_tool_engine_test.dart and
                        # test/eidetic_memory_test.dart (pure-Dart, no model)
```

The pure-Dart units (grammar synthesis, JSON extraction/validation, the memory
store, dedupe hashing, and the gate's idle path) are covered by the new tests
and rely only on stable APIs. The Flutter screens and DI wiring follow the
existing screens' patterns but are the parts most worth an `analyze` pass.
