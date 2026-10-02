import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;

import 'wakelock_service.dart';
import 'chat_storage_service.dart';
import 'log_service.dart';
import 'pipeline_status_service.dart';
import '../core/diagnostics/gpu_trial.dart';

/// Wraps llamadart's LlamaEngine for model loading, generation, and lifecycle.
class LlmService extends GetxService {
  LlamaEngine? _engine;
  LlamaBackend? _backend;

  final isLoaded = false.obs;
  final isGenerating = false.obs;
  final loadedModelPath = ''.obs;
  final tokensPerSecond = 0.0.obs;
  final lastGenerationTokens = 0.obs;
  final lastGenerationSpeed = 0.0.obs;

  // ── Active compute config ──────────────────────────────────
  // The backend + GPU-layer count the CURRENTLY RESIDENT model was actually
  // loaded with — set on a successful load, cleared on teardown. This is the
  // honest answer to "what is the model running on right now", as opposed to
  // probeGpuDeviceLines() which only reports what hardware is AVAILABLE. Empty
  // backend / 0 layers while loaded means CPU inference.
  final activeBackend = ''.obs; // 'cpu' | 'vulkan' | 'opencl' | 'auto'
  final activeGpuLayers = 0.obs;

  // ── Loading progress tracking ──────────────────────────────
  final isLoadingModel = false.obs;
  final loadingProgress = 0.0.obs; // 0.0 to 1.0
  final loadingStatusMsg = ''.obs;
  bool _loadingCancelled = false;

  StreamSubscription? _generateSub;

  String get loadedModelFilename {
    final path = loadedModelPath.value;
    if (path.isEmpty) return '';
    return p.basename(path);
  }

  String get publicModelId {
    final filename = loadedModelFilename;
    if (filename.isEmpty) return 'local';
    final stem = filename.toLowerCase().endsWith('.gguf')
        ? filename.substring(0, filename.length - 5)
        : p.basenameWithoutExtension(filename);
    return stem
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  LogService? get _log {
    try {
      return Get.find<LogService>();
    } catch (_) {
      return null;
    }
  }

  PipelineStatusService? get _status {
    try {
      return Get.find<PipelineStatusService>();
    } catch (_) {
      return null;
    }
  }

  /// Default decode thread count when the user hasn't set one: pin to the
  /// big-core cluster and leave the OS + efficiency cores free. 6 on an 8-core
  /// SoC (Snapdragon 8 Gen 3 = 1 Prime + 5 Performance + 2 Efficiency; using 6
  /// skips the two slow efficiency cores), 4 on a 6-core, auto below that.
  int get _autoThreads {
    final n = Platform.numberOfProcessors;
    if (n >= 8) return 6;
    if (n > 4) return 4;
    return 0;
  }

  /// Enumerate the GPU-class devices this device actually exposes, probing the
  /// Vulkan and OpenCL backend modules. This is a device query only — it loads
  /// the backend .so to ask "what GPUs are here?", it does NOT load a model or
  /// run inference — so it's the safe way to find out whether GPU offload is
  /// even available on this phone before committing to it. Returns one
  /// human-readable line per device, e.g. "opencl · Adreno (TM) 750 · 11.5 GB".
  /// Empty means only CPU is available on this device/build. Refused while a
  /// generation is in flight.
  Future<List<String>> probeGpuDeviceLines() async {
    if (isGenerating.value) {
      throw StateError('The engine is busy generating — try again when idle.');
    }
    const probe = [GpuBackend.vulkan, GpuBackend.opencl];

    List<GpuDeviceInfo> devices = const [];
    final existing = _engine;
    if (existing != null) {
      _log?.info('Probing GPU devices on the loaded engine…', source: 'LLM');
      devices = await existing.listGpuDevices(probeBackends: probe);
    } else {
      _log?.info('Probing GPU devices on a throwaway engine…', source: 'LLM');
      LlamaEngine? temp;
      try {
        temp = LlamaEngine(LlamaBackend());
        devices = await temp.listGpuDevices(probeBackends: probe);
      } finally {
        try {
          await temp?.dispose();
        } catch (_) {}
      }
    }

    final lines = <String>[];
    for (final d in devices) {
      final gb = d.memoryTotalBytes > 0
          ? ' · ${(d.memoryTotalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
          : '';
      final name = d.description.isNotEmpty ? d.description : d.name;
      lines.add('${d.backend.name} · $name$gb');
    }
    _log?.info('GPU probe → ${lines.isEmpty ? 'CPU only' : lines.join(' | ')}',
        source: 'LLM');
    return lines;
  }

  /// Initialize the service.
  Future<LlmService> init() async {
    // Backend is created fresh per loadModel() call — no init needed here
    return this;
  }

  /// Cancel an in-progress model load.
  void cancelLoading() {
    _loadingCancelled = true;
  }

  /// Trial-load [modelPath] on a specific [backend] + [gpuLayers] to find out
  /// whether this device can actually get INTO the GPU and compute — WITHOUT
  /// disturbing the user's saved settings or their resident model's config.
  ///
  /// Only one native engine may be resident, so this tears down any loaded
  /// model first, loads a throwaway engine with a small context, runs a few
  /// tokens to confirm real compute (a load can succeed while decode crashes),
  /// measures throughput, then disposes. The caller is left with NO model
  /// loaded — re-arm to chat again.
  ///
  /// Dart-level failures (backend missing, allocation refused) are caught and
  /// returned as `ok: false`. A hard native crash inside a GPU driver CANNOT be
  /// caught here — it kills the process — which is why the pen-test harness
  /// write-ahead-logs each attempt to disk before calling this.
  Future<GpuTrialOutcome> runGpuTrial({
    required String modelPath,
    required GpuBackend backend,
    required int gpuLayers,
    int contextSize = 256,
    int probeTokens = 12,
  }) async {
    if (isGenerating.value) {
      return const GpuTrialOutcome(ok: false, error: 'engine is busy generating');
    }
    if (!await File(modelPath).exists()) {
      return GpuTrialOutcome(ok: false, error: 'model file not found: $modelPath');
    }
    // Enforce the single-engine rule: fully release the resident model first.
    await _fullTeardown();
    await Future.delayed(const Duration(milliseconds: 300));

    LlamaBackend? backendObj;
    LlamaEngine? engine;
    final sw = Stopwatch();
    try {
      backendObj = LlamaBackend();
      engine = LlamaEngine(backendObj);
      final params = ModelParams(
        contextSize: contextSize,
        gpuLayers: gpuLayers,
        preferredBackend: backend,
        numberOfThreads: _autoThreads,
        numberOfThreadsBatch: _autoThreads,
        flashAttention: FlashAttention.auto,
        cacheTypeK: KvCacheType.f16,
        cacheTypeV: KvCacheType.f16,
        batchSize: 0,
        microBatchSize: 0,
      );
      _log?.info(
          'GPU trial: ${backend.name} @ $gpuLayers layers (ctx $contextSize) — loading…',
          source: 'LLM');
      await engine.loadModel(modelPath, modelParams: params);

      // Prove it actually computes — a load can succeed but decode can
      // crash/stall on a bad driver path.
      var tokens = 0;
      sw.start();
      await for (final _ in engine.generate('Hello').take(probeTokens)) {
        tokens++;
      }
      sw.stop();
      final secs = sw.elapsedMilliseconds / 1000.0;
      final tps = (tokens > 0 && secs > 0) ? tokens / secs : 0.0;
      _log?.info(
          'GPU trial OK: ${backend.name} @ $gpuLayers → $tokens tok, '
          '${tps.toStringAsFixed(2)} t/s',
          source: 'LLM');
      return GpuTrialOutcome(
          ok: true, tps: tps, tokens: tokens, ms: sw.elapsedMilliseconds);
    } catch (e) {
      _log?.error('GPU trial FAILED: ${backend.name} @ $gpuLayers → $e',
          source: 'LLM');
      return GpuTrialOutcome(ok: false, error: e.toString());
    } finally {
      try {
        await engine?.dispose();
      } catch (_) {}
      engine = null;
      backendObj = null;
      _engine = null;
      _backend = null;
      isLoaded.value = false;
      loadedModelPath.value = '';
      activeBackend.value = '';
      activeGpuLayers.value = 0;
    }
  }

  /// Load a GGUF model from [path] with progress tracking.
  Future<void> loadModel(String path) async {
    LogService? log;
    try { log = Get.find<LogService>(); } catch (_) {}

    // Verify file exists first
    final file = File(path);
    if (!await file.exists()) {
      log?.error('Model file not found: $path', source: 'LLM');
      throw Exception('Model file not found: $path');
    }

    final filename = p.basename(path);
    log?.info('Loading model: $filename', source: 'LLM');
    _status?.begin(PipelinePhase.arming, 'arming engine for $filename…');

    _loadingCancelled = false;
    isLoadingModel.value = true;
    loadingProgress.value = 0.0;
    loadingStatusMsg.value = 'Preparing...';

    // Enable wake lock during model loading (heavy memory operation)
    WakelockService? wakelockService;
    try {
      wakelockService = Get.find<WakelockService>();
    } catch (_) {}

    // Unload previous if any — MUST fully tear down engine + backend
    if (_engine != null || isLoaded.value) {
      loadingStatusMsg.value = 'Unloading previous model...';
      loadingProgress.value = 0.05;
      await _fullTeardown();
      // Give native side time to release resources
      await Future.delayed(const Duration(milliseconds: 500));
      if (_loadingCancelled) {
        _resetLoadingState();
        return;
      }
    }

    // Fresh backend + engine for every load — prevents stale native state
    // Wrapped in try-catch to handle SELinux crashes on Android where
    // ggml_backend_load_all() attempts to scan '/' which is denied.
    try {
      _status?.mark('creating native backend + engine…');
      _backend = LlamaBackend();
      _engine = LlamaEngine(_backend!);
      _status?.mark('native engine armed');
    } catch (e) {
      _backend = null;
      _engine = null;
      _status?.fail('Engine init failed — device compatibility issue.');
      _resetLoadingState();
      log?.error('Engine init failed: $e', source: 'LLM');
      throw Exception(
        'Failed to initialize AI engine. '
        'This may be a device compatibility issue. '
        'Error: $e',
      );
    }

    try {
      loadingStatusMsg.value = 'Loading into memory...';
      loadingProgress.value = 0.1;

      // Get file size for display
      final fileSize = await file.length();
      final sizeGb = (fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1);
      loadingStatusMsg.value = 'Loading $sizeGb GB into memory...';
      _status?.begin(PipelinePhase.loading, 'loading $sizeGb GB into memory…',
          progress: loadingProgress.value);

      // Start a timer to animate progress while loading
      Timer? progressTimer;
      progressTimer = Timer.periodic(const Duration(milliseconds: 300), (
        timer,
      ) {
        if (_loadingCancelled) {
          timer.cancel();
          return;
        }
        // Gradually increase progress (asymptotic approach to 0.95)
        final current = loadingProgress.value;
        if (current < 0.95) {
          loadingProgress.value = current + (0.95 - current) * 0.04;
        }
        _status?.setProgress(loadingProgress.value);
      });

      if (_loadingCancelled) {
        progressTimer.cancel();
        await _fullTeardown();
        _resetLoadingState();
        return;
      }

      // Map the string backend to GpuBackend enum
      final storage = Get.find<ChatStorageService>();

      // Context window (tokens). User-configurable; 0 = auto, which llamadart
      // resolves to the model's own trained maximum (llama_model_n_ctx_train)
      // — i.e. the model's ceiling. This is deliberately NOT capped to an
      // arbitrary small value: a model that comfortably runs at tens of
      // thousands of tokens should get that context (a tiny window truncates
      // replies and overflows the consolidation prompt). Users lower it in
      // Settings if they need to cut RAM/KV-cache use on a constrained device.
      final contextSize = storage.contextSize;
      GpuBackend parsedBackend;
      switch (storage.backendType) {
        case 'auto':
          parsedBackend = GpuBackend.auto;
          break;
        case 'vulkan':
          parsedBackend = GpuBackend.vulkan;
          break;
        case 'opencl':
          parsedBackend = GpuBackend.opencl;
          break;
        default:
          parsedBackend = GpuBackend.cpu;
      }

      // Read gpu layers
      final userGpuLayers = storage.gpuLayers;

      // ── Performance tuning (llamadart 0.8.24 ModelParams) ──────────────
      // Threads: pin decode to the big-core cluster (Prime + Performance),
      // skipping the slow efficiency cores. User value wins; else a big-core
      // estimate (6 on an 8-core SoC, leaving 2 for the OS).
      final threads =
          storage.cpuThreads > 0 ? storage.cpuThreads : _autoThreads;

      // Flash attention (tiles attention → fewer RAM round-trips → faster TTFT).
      FlashAttention parsedFlash;
      switch (storage.flashAttention) {
        case 'on':
          parsedFlash = FlashAttention.enabled;
          break;
        case 'off':
          parsedFlash = FlashAttention.disabled;
          break;
        default:
          parsedFlash = FlashAttention.auto;
      }

      // KV-cache quantization (q8_0 ≈ ½ KV RAM bandwidth; q4_0 ≈ ¼).
      KvCacheType parsedKv;
      switch (storage.kvCacheType) {
        case 'q8_0':
          parsedKv = KvCacheType.q8_0;
          break;
        case 'q4_0':
          parsedKv = KvCacheType.q4_0;
          break;
        default:
          parsedKv = KvCacheType.f16;
      }
      // Safety: a quantized KV cache requires flash attention. If the user
      // quantized KV but forced flash off, promote to auto rather than letting
      // llamadart throw on load.
      if (parsedKv != KvCacheType.f16 &&
          parsedFlash == FlashAttention.disabled) {
        parsedFlash = FlashAttention.auto;
      }

      final params = ModelParams(
        contextSize: contextSize,
        gpuLayers: userGpuLayers,
        preferredBackend: parsedBackend,
        numberOfThreads: threads,
        numberOfThreadsBatch: threads,
        flashAttention: parsedFlash,
        cacheTypeK: parsedKv,
        cacheTypeV: parsedKv,
        // 0 (or negative) → llamadart's automatic batch sizing.
        batchSize: storage.batchSize,
        microBatchSize: storage.microBatchSize,
      );

      log?.info(
          'Backend=$parsedBackend, GPU layers=$userGpuLayers, ctx=${contextSize == 0 ? 'auto(model max)' : contextSize}, threads=$threads, flashAttn=${parsedFlash.name}, kv=${parsedKv.name}, batch=${storage.batchSize == 0 ? 'auto' : storage.batchSize}/${storage.microBatchSize == 0 ? 'auto' : storage.microBatchSize}',
          source: 'LLM');

      log?.info('invoking native engine.loadModel() …', source: 'LLM');
      await _engine!.loadModel(path, modelParams: params);
      log?.info('native engine.loadModel() returned OK', source: 'LLM');

      // Record the compute config this resident model actually loaded with, so
      // the systems check can report what we're RUNNING ON — not just what GPU
      // hardware exists. (backend=cpu or layers=0 ⇒ CPU inference.)
      activeBackend.value = parsedBackend.name;
      activeGpuLayers.value = userGpuLayers;

      // Report the context window actually in effect. When contextSize is 0
      // (auto), llamadart resolves it to the model's trained maximum, so this
      // is the honest number the session is running with — surfaced for the
      // logs the user debugs from.
      try {
        final effectiveCtx = await _engine!.getContextSize();
        log?.info(
            'Context window in effect: $effectiveCtx tokens${contextSize == 0 ? ' (auto — model maximum)' : ''}',
            source: 'LLM');
      } catch (_) {}
      progressTimer.cancel();

      if (_loadingCancelled) {
        // User cancelled while loading — full cleanup
        await _fullTeardown();
        _resetLoadingState();
        return;
      }

      loadingProgress.value = 1.0;
      loadingStatusMsg.value = 'Ready!';
      isLoaded.value = true;
      loadedModelPath.value = path;
      _status?.done('model ready · $filename');
      log?.info('Model loaded successfully: $filename', source: 'LLM');

      // Enable wake lock for inference on mobile (keeps app from being killed)
      final modelName = p.basenameWithoutExtension(path);
      await wakelockService?.enableForInference(modelName: modelName);

      // Brief delay to show 100%
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      isLoaded.value = false;
      loadedModelPath.value = '';
      await _fullTeardown();
      final low = e.toString().toLowerCase();
      _status?.fail(
          (Platform.isAndroid && (low.contains('memory') || low.contains('alloc')))
              ? 'Not enough RAM — try a smaller model.'
              : 'Model load failed.');
      log?.error('Model load failed: $e', source: 'LLM');

      // Provide a clearer error message for common Android failures
      if (Platform.isAndroid) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('memory') || errStr.contains('alloc')) {
          throw Exception(
            'Not enough RAM to load this model. '
            'Try a smaller model (e.g. Gemma 2 2B at 1.6 GB).',
          );
        }
      }
      rethrow;
    } finally {
      _resetLoadingState();
    }
  }

  void _resetLoadingState() {
    isLoadingModel.value = false;
    loadingProgress.value = 0.0;
    loadingStatusMsg.value = '';
    _loadingCancelled = false;
  }

  /// Tokens/patterns the model may emit that should be stripped from output.
  /// Covers ChatML, Llama, Gemma, Phi, Mistral, and other common formats.
  static final _stopPatterns = RegExp(
    r'<\|end\|>'
    r'|<\|eot_id\|>'
    r'|<\|endoftext\|>'
    r'|<\|im_end\|>'
    r'|<\|im_start\|>'
    r'|<end_of_turn>'
    r'|<start_of_turn>'
    r'|<\|assistant\|>'
    r'|<\|user\|>'
    r'|<\|system\|>'
    r'|<\|pad\|>'
    r'|</s>'
    r'|<s>'
    r'|\[INST\]'
    r'|\[/INST\]'
    r'|\[end\]',
  );

  /// Pattern that signals the model is hallucinating a new user turn — stop immediately.
  static final _userTurnPattern = RegExp(
    r'<\|user\|>|<\|im_start\|>\s*user|<start_of_turn>\s*user|\[INST\]',
  );

  /// Synchronously claim the single native engine for exactly one generation.
  ///
  /// Because a Dart isolate is single-threaded, the check-and-set here is
  /// atomic: no `await` sits between reading [isGenerating] and setting it, so
  /// two callers can never both pass this guard. This is the invariant the
  /// public generation methods depend on. It must run *synchronously at call
  /// time*, not lazily inside an `async*` body — an `async*` body does not run
  /// until its stream is listened to, which opened a race where two lazily
  /// started streams each saw `isGenerating == false` before either set it
  /// true. That race is exactly the "generation already in progress" crash seen
  /// when a debate turn (worker) and a chat turn (direct) — or a debate turn and
  /// a background consolidation handoff — reached the engine at once. So the
  /// public methods are thin *synchronous* wrappers that call this first and
  /// then return the streaming body.
  void _beginGeneration() {
    if (_engine == null || !isLoaded.value) {
      throw StateError('No model loaded. Call loadModel() first.');
    }
    if (isGenerating.value) {
      throw StateError('Another generation is already in progress.');
    }
    isGenerating.value = true;
  }

  /// Strip control/stop tokens and stray structural HTML tags a chat template
  /// may bleed into a reply. Shared by every consumer of a generated turn (the
  /// chat screen and the debate room) so cleanup is identical everywhere —
  /// there is no "worse" path for text produced off the main chat.
  static String scrubReply(String s) => s
      .replaceAll(_stopPatterns, '')
      // Stray structural HTML some chat templates bleed into the reply (e.g. a
      // lone </blockquote>). The chat view renders markdown, not HTML, so these
      // are template artifacts, never intended output.
      .replaceAll(
        RegExp(r'</?(?:blockquote|p|div|span|br|hr)\s*/?>',
            caseSensitive: false),
        '',
      )
      .trim();

  /// Generate a streaming response.
  /// [messages] is a list of {role, content} maps.
  /// [systemPrompt] is prepended as a system message.
  /// Returns a Stream of String tokens.
  Stream<String> generate({
    required List<Map<String, String>> messages,
    String? systemPrompt,
    double temperature = 0.7,
  }) {
    _beginGeneration();
    return _generateBody(
      messages: messages,
      systemPrompt: systemPrompt,
      temperature: temperature,
    );
  }

  Stream<String> _generateBody({
    required List<Map<String, String>> messages,
    String? systemPrompt,
    double temperature = 0.7,
  }) async* {
    tokensPerSecond.value = 0.0;
    final stopwatch = Stopwatch()..start();
    int tokenCount = 0;

    // Buffer to detect multi-token stop sequences
    String buffer = '';

    _log?.info(
      'generate: start · msgs=${messages.length} sysPromptLen=${systemPrompt?.length ?? 0} temp=$temperature model=$loadedModelFilename',
      source: 'LLM',
    );

    try {
      // Build the full prompt from messages
      final prompt = _buildPrompt(messages, systemPrompt);
      _log?.debug('generate: prompt built · chars=${prompt.length}',
          source: 'LLM');
      _log?.info('generate: invoking native engine.generate() …',
          source: 'LLM');

      await for (final token in _engine!.generate(prompt)) {
        if (tokenCount == 0) {
          _log?.info('generate: first token received', source: 'LLM');
        }
        tokenCount++;
        if (tokenCount % 64 == 0) {
          _log?.debug('generate: streamed $tokenCount tokens', source: 'LLM');
        }
        if (stopwatch.elapsedMilliseconds > 0) {
          tokensPerSecond.value =
              tokenCount / (stopwatch.elapsedMilliseconds / 1000);
        }

        // Accumulate into buffer for stop-pattern detection
        buffer += token;

        // Check if model is hallucinating a user turn — stop immediately
        if (_userTurnPattern.hasMatch(buffer)) {
          final cleaned = buffer
              .replaceAll(_stopPatterns, '')
              .replaceAll(_userTurnPattern, '')
              .trim();
          if (cleaned.isNotEmpty) {
            yield cleaned;
          }
          break;
        }

        // Check if buffer contains any stop pattern
        if (_stopPatterns.hasMatch(buffer)) {
          // Yield everything before the stop pattern, then stop
          final cleaned = buffer.replaceAll(_stopPatterns, '').trim();
          if (cleaned.isNotEmpty) {
            yield cleaned;
          }
          break;
        }

        // If buffer is getting long enough that we know it's safe, flush it
        // Keep last 30 chars to detect split stop sequences
        if (buffer.length > 40) {
          final safe = buffer.substring(0, buffer.length - 30);
          buffer = buffer.substring(buffer.length - 30);
          yield safe;
        }
      }

      // Flush any remaining buffer (cleaning all control patterns)
      if (buffer.isNotEmpty) {
        final cleaned = buffer
            .replaceAll(_stopPatterns, '')
            .replaceAll(_userTurnPattern, '')
            .trim();
        if (cleaned.isNotEmpty) {
          yield cleaned;
        }
      }
    } catch (e, st) {
      _log?.error('generate: FAILED after $tokenCount tokens · $e',
          source: 'LLM');
      _log?.debug('generate: stack · $st', source: 'LLM');
      rethrow;
    } finally {
      stopwatch.stop();
      lastGenerationTokens.value = tokenCount;
      lastGenerationSpeed.value = tokensPerSecond.value;
      isGenerating.value = false;
      _log?.info(
        'generate: end · tokens=$tokenCount tps=${tokensPerSecond.value.toStringAsFixed(1)}',
        source: 'LLM',
      );
    }
  }

  /// Generate a chat completion using llamadart's chat-template API.
  Stream<String> generateChatCompletion({
    required List<LlamaChatMessage> messages,
    GenerationParams params = const GenerationParams(),
  }) {
    _beginGeneration();
    return _generateChatCompletionBody(messages: messages, params: params);
  }

  Stream<String> _generateChatCompletionBody({
    required List<LlamaChatMessage> messages,
    GenerationParams params = const GenerationParams(),
  }) async* {
    tokensPerSecond.value = 0.0;
    final stopwatch = Stopwatch()..start();
    int tokenCount = 0;

    try {
      await for (final chunk in _engine!.create(
        messages,
        params: params,
        toolChoice: ToolChoice.none,
      )) {
        final choice = chunk.choices.isNotEmpty ? chunk.choices.first : null;
        final content = choice?.delta.content;
        if (content == null || content.isEmpty) continue;

        tokenCount++;
        if (stopwatch.elapsedMilliseconds > 0) {
          tokensPerSecond.value =
              tokenCount / (stopwatch.elapsedMilliseconds / 1000);
        }
        yield content;
      }
    } finally {
      stopwatch.stop();
      lastGenerationTokens.value = tokenCount;
      lastGenerationSpeed.value = tokensPerSecond.value;
      isGenerating.value = false;
    }
  }

  /// Generate a chat reply using the MODEL'S OWN chat template (read from the
  /// GGUF metadata by llama.cpp), instead of the hand-rolled Phi-style format in
  /// [_buildPrompt].
  ///
  /// This is the correct path for real chat: [_buildPrompt] hardcodes
  /// `<|user|>`/`<|assistant|>`/`<|end|>` for every model, so a model whose real
  /// template differs (Gemma's `<start_of_turn>`, Llama-3's headers, …) never
  /// sees its true end-of-turn token, doesn't stop, and repeats itself. Routing
  /// through [generateChatCompletion] lets llama.cpp apply the model's own
  /// template and stop cleanly for any family.
  Stream<String> generateChat({
    required List<Map<String, String>> messages,
    String? systemPrompt,
    double temperature = 0.7,
    int? maxTokens,
  }) {
    final chat = <LlamaChatMessage>[
      if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
        LlamaChatMessage(role: 'system', content: systemPrompt),
      for (final m in messages)
        LlamaChatMessage(
          role: m['role'] ?? 'user',
          content: m['content'] ?? '',
        ),
    ];
    // Opt-in n-gram self-speculative decoding: drafts candidate tokens from the
    // prompt/history (no draft model, no extra RAM) for a speedup on repetitive
    // or structured output. Off unless enabled in Settings.
    SpeculativeDecodingConfig? spec;
    try {
      if (Get.find<ChatStorageService>().speculativeNgram) {
        spec = const SpeculativeDecodingConfig.ngramSimple();
      }
    } catch (_) {}

    // maxTokens is the user's adjustable output budget (gen.maxTokens). It caps
    // reply length; the model still stops early at its own end-of-turn. Null
    // falls back to llamadart's own default.
    final budget = (maxTokens != null && maxTokens > 0) ? maxTokens : 4096;
    return generateChatCompletion(
      messages: chat,
      params: GenerationParams(
        temp: temperature,
        maxTokens: budget,
        speculativeDecodingConfig: spec,
      ),
    );
  }

  /// Generate a response whose tokens are constrained by a GBNF [grammar].
  ///
  /// The grammar is enforced by the sampler (llamadart >= 0.8), so output
  /// structurally conforms to it — e.g. valid tool-call JSON or a single JSON
  /// object. Requires a grammar-capable backend; the native llama.cpp backends
  /// used on mobile/desktop support it. Tokens are streamed raw (no stop-token
  /// scrubbing) so the structured payload is preserved for the caller to parse.
  Stream<String> generateWithGrammar({
    required List<Map<String, String>> messages,
    required String grammar,
    String? systemPrompt,
    double temperature = 0.7,
    String grammarRoot = 'root',
  }) {
    _beginGeneration();
    return _generateWithGrammarBody(
      messages: messages,
      grammar: grammar,
      systemPrompt: systemPrompt,
      temperature: temperature,
      grammarRoot: grammarRoot,
    );
  }

  Stream<String> _generateWithGrammarBody({
    required List<Map<String, String>> messages,
    required String grammar,
    String? systemPrompt,
    double temperature = 0.7,
    String grammarRoot = 'root',
  }) async* {
    tokensPerSecond.value = 0.0;
    final stopwatch = Stopwatch()..start();
    int tokenCount = 0;

    _log?.info(
      'generateWithGrammar: start · msgs=${messages.length} grammarLen=${grammar.length} root=$grammarRoot temp=$temperature model=$loadedModelFilename',
      source: 'LLM',
    );

    try {
      final prompt = _buildPrompt(messages, systemPrompt);
      final params = GenerationParams(
        temp: temperature,
        grammar: grammar,
        grammarRoot: grammarRoot,
      );
      _log?.debug('generateWithGrammar: prompt built · chars=${prompt.length}',
          source: 'LLM');
      _log?.info(
          'generateWithGrammar: invoking native engine.generate(grammar) …',
          source: 'LLM');

      await for (final token in _engine!.generate(prompt, params: params)) {
        if (tokenCount == 0) {
          _log?.info('generateWithGrammar: first token received',
              source: 'LLM');
        }
        tokenCount++;
        if (stopwatch.elapsedMilliseconds > 0) {
          tokensPerSecond.value =
              tokenCount / (stopwatch.elapsedMilliseconds / 1000);
        }
        yield token;
      }
    } catch (e, st) {
      _log?.error(
          'generateWithGrammar: FAILED after $tokenCount tokens · $e',
          source: 'LLM');
      _log?.debug('generateWithGrammar: stack · $st', source: 'LLM');
      rethrow;
    } finally {
      stopwatch.stop();
      lastGenerationTokens.value = tokenCount;
      lastGenerationSpeed.value = tokensPerSecond.value;
      isGenerating.value = false;
      _log?.info(
        'generateWithGrammar: end · tokens=$tokenCount tps=${tokensPerSecond.value.toStringAsFixed(1)}',
        source: 'LLM',
      );
    }
  }

  Future<int> countTokens(String text) async {
    if (_engine == null || !isLoaded.value) return 0;
    try {
      return await _engine!.getTokenCount(text);
    } catch (_) {
      return 0;
    }
  }

  /// Stop ongoing generation.
  Future<void> stopGeneration() async {
    _generateSub?.cancel();
    _generateSub = null;
    _engine?.cancelGeneration();
    isGenerating.value = false;
  }

  /// Full native teardown — dispose engine AND backend to prevent stale state.
  Future<void> _fullTeardown() async {
    if (_engine != null) {
      try {
        await _engine!.dispose();
      } catch (_) {
        // Engine may already be in broken state — ignore
      }
      _engine = null;
    }
    // Also destroy the backend — it can't be reused after engine disposal
    _backend = null;
    isLoaded.value = false;
    loadedModelPath.value = '';
    tokensPerSecond.value = 0.0;
    activeBackend.value = '';
    activeGpuLayers.value = 0;
  }

  /// Unload the current model and free memory.
  Future<void> unloadModel() async {
    await _fullTeardown();

    // Disable wake lock when model is unloaded
    try {
      final wakelockService = Get.find<WakelockService>();
      await wakelockService.disable();
    } catch (_) {}
  }

  /// Build a single prompt string from chat messages.
  String _buildPrompt(
    List<Map<String, String>> messages,
    String? systemPrompt,
  ) {
    final buffer = StringBuffer();

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer.writeln('<|system|>');
      buffer.writeln(systemPrompt);
      buffer.writeln('<|end|>');
    }

    for (final msg in messages) {
      final role = msg['role'] ?? 'user';
      final content = msg['content'] ?? '';
      buffer.writeln('<|$role|>');
      buffer.writeln(content);
      buffer.writeln('<|end|>');
    }

    buffer.writeln('<|assistant|>');
    return buffer.toString();
  }

  @override
  void onClose() {
    unloadModel();
    super.onClose();
  }
}
