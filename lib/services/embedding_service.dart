import 'dart:async';

import 'package:get/get.dart';
import 'package:llamadart/llamadart.dart';

import 'log_service.dart';

/// Loads a small embedding GGUF as a SECOND, co-resident engine and turns text
/// into vectors for meaning-based recall (Phase 2b).
///
/// Deliberately separate from the chat engine in [LlmService]: an embedding
/// model is small and its forward pass is a single (non-autoregressive) step,
/// so it can stay resident alongside the 4B chat model without paying a
/// model-swap cost per turn. llamadart auto-configures the embedding context
/// for an encoder/embedding model — a plain load followed by [embed] is all it
/// needs (see llamadart's own embedding example).
///
/// Embedding is strictly opt-in and additive: nothing loads until [load] is
/// called with a model path, every failure is swallowed to null, and callers
/// (recall seeding, embed-on-consolidate) fall back to keyword + graph seeding
/// whenever a vector isn't available. So this can only make recall deeper,
/// never break it.
class EmbeddingService extends GetxService {
  LlamaEngine? _engine;
  LlamaBackend? _backend;

  /// True once a model is loaded and ready to embed.
  final isReady = false.obs;

  /// Path of the currently loaded embedding model, or null.
  final loadedModelPath = RxnString();

  /// Last load/embed error surfaced for diagnostics, or null.
  final lastError = RxnString();

  int _dim = 0;

  /// Vector dimension of the loaded model (0 until the first successful embed).
  int get dimensions => _dim;

  LogService? get _log {
    try {
      return Get.find<LogService>();
    } catch (_) {
      return null;
    }
  }

  /// Load the embedding GGUF at [path]. Idempotent: a no-op if the same path is
  /// already loaded. Returns true on success, false on any failure (the service
  /// stays unloaded and recall keeps working without meaning-seeding).
  Future<bool> load(String path) async {
    if (isReady.value && loadedModelPath.value == path) return true;
    await unload();
    try {
      _log?.info('Loading embedding model: $path', source: 'Embed');
      _backend = LlamaBackend();
      _engine = LlamaEngine(_backend!);
      await _engine!.loadModel(
        path,
        // Embedding models are small; a modest context covers any claim/cue and
        // keeps RAM low. CPU keeps the embedder off whatever backend the chat
        // model uses, so the two never contend for the GPU.
        modelParams: const ModelParams(
          contextSize: 2048,
          gpuLayers: 0,
          preferredBackend: GpuBackend.cpu,
        ),
      );
      isReady.value = true;
      loadedModelPath.value = path;
      lastError.value = null;
      _log?.info('Embedding model ready', source: 'Embed');
      return true;
    } catch (e) {
      lastError.value = e.toString();
      _log?.error('Embedding model load failed: $e', source: 'Embed');
      await unload();
      return false;
    }
  }

  /// Embed [text] into a normalized vector, or null when the embedder isn't
  /// ready, the text is empty, or the model fails. Never throws — callers treat
  /// null as "no meaning seed" and fall back to keyword/graph seeding.
  Future<List<double>?> embed(String text) async {
    final engine = _engine;
    if (!isReady.value || engine == null || text.trim().isEmpty) return null;
    try {
      final v = await engine.embed(text, normalize: true);
      if (v.isNotEmpty) _dim = v.length;
      return v;
    } catch (e) {
      _log?.warn('embed failed: $e', source: 'Embed');
      return null;
    }
  }

  /// Release the embedding model and its native resources.
  Future<void> unload() async {
    isReady.value = false;
    loadedModelPath.value = null;
    final e = _engine;
    _engine = null;
    if (e != null) {
      try {
        await e.dispose();
      } catch (_) {}
    }
    _backend = null;
    _dim = 0;
  }

  @override
  void onClose() {
    unawaited(unload());
    super.onClose();
  }
}
