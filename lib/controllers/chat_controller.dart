import 'dart:async';
import 'package:get/get.dart';

import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../services/llm_service.dart';
import '../services/chat_storage_service.dart';
import '../services/log_service.dart';
import '../services/pipeline_status_service.dart';
import '../core/engine/inference_worker.dart';
import '../core/memory/memory_service.dart';
import '../core/params/parameters_service.dart';

class ChatController extends GetxController {
  final LlmService _llm = Get.find<LlmService>();
  final ChatStorageService _storage = Get.find<ChatStorageService>();

  LogService? get _log {
    try {
      return Get.find<LogService>();
    } catch (_) {
      return null;
    }
  }

  MemoryService? get _memory {
    try {
      return Get.find<MemoryService>();
    } catch (_) {
      return null;
    }
  }

  ParametersService? get _params {
    try {
      return Get.find<ParametersService>();
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

  final chats = <ChatModel>[].obs;
  final activeChatId = RxnString();
  final isGenerating = false.obs;
  final streamedResponse = ''.obs;
  final temperature = 0.7.obs;
  final systemPrompt = ''.obs;

  StreamSubscription<String>? _genSub;

  @override
  void onInit() {
    super.onInit();
    _loadChats();
    temperature.value = _storage.defaultTemperature;
    systemPrompt.value = _storage.globalSystemPrompt;
  }

  void _loadChats() {
    chats.value = _storage.getAllChats();
  }

  ChatModel? get activeChat {
    if (activeChatId.value == null) return null;
    try {
      return chats.firstWhere((c) => c.id == activeChatId.value);
    } catch (_) {
      return null;
    }
  }

  /// Create a new chat and switch to it.
  void newChat() {
    final chat = ChatModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      systemPrompt: systemPrompt.value,
    );
    chats.insert(0, chat);
    _storage.saveChat(chat);
    activeChatId.value = chat.id;
  }

  /// Switch to an existing chat.
  void switchChat(String id) {
    activeChatId.value = id;
    final chat = activeChat;
    if (chat != null) {
      systemPrompt.value = chat.systemPrompt;
    }
  }

  /// Delete a chat.
  void deleteChat(String id) {
    chats.removeWhere((c) => c.id == id);
    _storage.deleteChat(id);
    if (activeChatId.value == id) {
      activeChatId.value = chats.isNotEmpty ? chats.first.id : null;
    }
  }

  /// Send a user message and stream AI response.
  Future<void> sendMessage(String text, {String? modelFilename}) async {
    if (text.trim().isEmpty) return;
    final chat = activeChat;
    if (chat == null) {
      _log?.warn('sendMessage: no active chat', source: 'Chat');
      return;
    }
    _log?.info(
      'sendMessage: chat=${chat.id} userLen=${text.trim().length} '
      'modelLoaded=${_llm.isLoaded.value} model=${_llm.loadedModelFilename}',
      source: 'Chat',
    );

    // Add user message
    final userMsg = MessageModel(role: MessageRole.user, content: text.trim());
    chat.messages.add(userMsg);
    chat.autoTitle();
    chat.updatedAt = DateTime.now();

    // Lock model to this chat on first message
    if (chat.modelId.isEmpty && modelFilename != null) {
      chat.modelId = modelFilename;
    }

    _storage.saveChat(chat);
    chats.refresh();

    _status?.clearError();

    // ── ERROR MITIGATION: no model loaded ─────────────────────────
    // Don't attempt generation — it would throw a raw "No model loaded"
    // exception — and, critically, don't let that error become an assistant
    // turn that gets remembered and consolidated into a bogus "fact" (which is
    // exactly what used to happen). Surface a clear, actionable notice and stop.
    if (!_llm.isLoaded.value) {
      _status?.fail('No model loaded — open Models and load one to chat.');
      _log?.warn('sendMessage: blocked — no model loaded', source: 'Chat');
      final notice = MessageModel(
        role: MessageRole.assistant,
        content:
            '⚠ No model is loaded. Open the **Models** tab, load a model, then send your message again.',
      );
      chat.messages.add(notice);
      chat.updatedAt = DateTime.now();
      _storage.saveChat(chat);
      chats.refresh();
      // Keep the user's message (it's real input); never remember the notice.
      await _memory?.remember(
          sessionId: chat.id, role: 'user', content: text.trim());
      return;
    }

    // Build message history for LLM
    final history = chat.messages
        .where((m) => !m.isSystem)
        .map((m) => m.toLlamaMessage())
        .toList();

    // ── MEMORY: remembering (recall) before generating ─────────
    _status?.begin(PipelinePhase.recalling, 'searching memory…');
    final baseSystem =
        chat.systemPrompt.isNotEmpty ? chat.systemPrompt : systemPrompt.value;
    // A compact cue from the last few turns so recall tracks what the
    // conversation is *about*, not just the latest sentence.
    final recentContext = _recentContextCue(chat, current: userMsg);
    final recalled = await _memory
            ?.remembering(text.trim(), recentContext: recentContext) ??
        '';
    final lr = _memory?.lastRecall.value;
    if (lr != null && !lr.isEmpty) {
      final mm = lr.meaningMatches;
      _status?.mark(
          'recalled ${lr.injected.length}${mm > 0 ? ' · $mm meaning' : ''}'
          '${lr.embeddingsActive ? ' · idx ${lr.embeddingIndexed}' : ''}');
    } else {
      _status?.mark('no memories matched yet');
    }
    final effectiveSystem =
        recalled.isEmpty ? baseSystem : '$baseSystem\n\n$recalled';

    // ── MEMORY: remember the user turn up front (survives a crash) ──
    await _memory?.remember(
      sessionId: chat.id,
      role: 'user',
      content: text.trim(),
    );

    // Start generation
    isGenerating.value = true;
    streamedResponse.value = '';
    var hadError = false;

    final aiMsg = MessageModel(role: MessageRole.assistant, content: '');
    chat.messages.add(aiMsg);
    chats.refresh();

    _log?.info('sendMessage: history=${history.length} msgs · awaiting stream',
        source: 'Chat');

    try {
      // A live user turn wins over background introspection. If a background
      // consolidation pass is holding the single engine, preempt it and wait
      // for the engine to free up, so this chat turn doesn't collide with a
      // "generation already in progress" error. Best-effort; no-op when idle.
      _status?.begin(PipelinePhase.prompting, 'handing off to the model…');
      try {
        await Get.find<InferenceWorker>().yieldForForeground();
      } catch (_) {}

      // Use the model's own chat template (via llamadart's create()) so it stops
      // cleanly at its real end-of-turn instead of repeating the reply — the
      // hand-rolled template in _buildPrompt only fits Phi-style models.
      // Output budget: user-adjustable ceiling on the reply length
      // (gen.maxTokens). Caps runaway/looping; the model still stops early at
      // its own end-of-turn.
      final maxTokens = _params?.getInt('gen.maxTokens');

      _status?.begin(PipelinePhase.generating, 'generating…',
          progress: (maxTokens != null && maxTokens > 0) ? 0.0 : null);

      final stream = _llm.generateChat(
        messages: history,
        systemPrompt: effectiveSystem,
        temperature: temperature.value,
        maxTokens: maxTokens,
      );

      var tok = 0;
      await for (final token in stream) {
        streamedResponse.value += token;
        aiMsg.content = streamedResponse.value;
        tok++;
        // Live readout: token count, rate, and budget progress — so the wait
        // is visibly producing information instead of stalling.
        _status?.setGeneration(
            tokens: tok, tps: _llm.tokensPerSecond.value, budget: maxTokens);
        // Throttle UI refreshes
        chats.refresh();
      }
      _log?.info('sendMessage: stream complete · responseLen=${aiMsg.content.length}',
          source: 'Chat');
    } catch (e) {
      hadError = true;
      _log?.error('sendMessage: stream error · $e', source: 'Chat');
      final friendly = _friendlyError(e);
      _status?.fail(friendly);
      if (aiMsg.content.isEmpty) {
        aiMsg.content = '⚠ $friendly';
      }
    } finally {
      // Clean up any trailing stop tokens, hallucinated-turn markers, or stray
      // structural HTML — the single shared scrub used by every consumer of a
      // generated turn (chat and debate alike), so cleanup is identical.
      aiMsg.content = LlmService.scrubReply(aiMsg.content);
      isGenerating.value = false;
      streamedResponse.value = '';
      chat.updatedAt = DateTime.now();
      _storage.saveChat(chat);
      chats.refresh();

      // ── MEMORY: remember the assistant turn + opportunistic consolidate ──
      // Never remember an error turn — it must not pollute episodic memory or
      // get consolidated into a "fact". On success, clear the status.
      final mem = _memory;
      if (!hadError && mem != null && aiMsg.content.isNotEmpty) {
        _status?.done('replied · ${aiMsg.content.length} chars');
        await mem.remember(
          sessionId: chat.id,
          role: 'assistant',
          content: aiMsg.content,
        );
        unawaited(mem.maybeConsolidate());
      } else if (!hadError) {
        _status?.done();
      }
      // On error the status strip keeps the red failure message visible.
    }
  }

  /// Map a raw exception to a short, actionable message for the user — so a
  /// failure reads as guidance, not a stack-trace fragment. The raw error still
  /// goes to the log.
  String _friendlyError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('no model')) {
      return 'No model loaded — open Models and load one.';
    }
    if (s.contains('already in progress')) {
      return 'The engine was busy — give it a moment and try again.';
    }
    if (s.contains('memory') ||
        s.contains('alloc') ||
        s.contains('oom') ||
        s.contains('out of memory')) {
      return 'Out of memory — try a smaller model or a lower context window in Settings.';
    }
    if (s.contains('cancel')) {
      return 'Generation was stopped.';
    }
    return 'Generation failed: $e';
  }

  /// Build a compact recall cue from the last few turns (excluding [current],
  /// the message being answered). Keeps the most recent content within a small
  /// character budget so recall reflects the thread's topic, not just the last
  /// sentence — without bloating the tiny context window.
  String _recentContextCue(
    ChatModel chat, {
    required MessageModel current,
    int maxTurns = 4,
    int maxChars = 400,
  }) {
    final prior = chat.messages
        .where((m) => !m.isSystem && !identical(m, current))
        .map((m) => m.content.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (prior.isEmpty) return '';
    final recent =
        prior.length <= maxTurns ? prior : prior.sublist(prior.length - maxTurns);
    final joined = recent.join('\n');
    return joined.length <= maxChars
        ? joined
        : joined.substring(joined.length - maxChars);
  }

  /// Stop current generation.
  void stopGeneration() {
    _llm.stopGeneration();
    isGenerating.value = false;
  }

  /// Update the system prompt for the active chat.
  void updateSystemPrompt(String prompt) {
    systemPrompt.value = prompt;
    final chat = activeChat;
    if (chat != null) {
      chat.systemPrompt = prompt;
      _storage.saveChat(chat);
    }
  }

  /// Set and persist the global system prompt.
  void setGlobalSystemPrompt(String prompt) {
    systemPrompt.value = prompt;
    _storage.globalSystemPrompt = prompt;
  }

  /// Clear global system prompt.
  void clearGlobalSystemPrompt() {
    systemPrompt.value = '';
    _storage.globalSystemPrompt = '';
  }

  void updateTemperature(double temp) {
    temperature.value = temp;
    _storage.defaultTemperature = temp;
  }

  @override
  void onClose() {
    _genSub?.cancel();
    super.onClose();
  }
}
