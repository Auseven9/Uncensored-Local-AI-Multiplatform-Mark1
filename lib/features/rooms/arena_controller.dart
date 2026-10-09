import 'package:get/get.dart';

import '../../core/engine/inference_worker.dart';
import '../../core/memory/eidetic_memory_engine.dart';
import '../../core/memory/memory_manager.dart';
import '../../core/memory/memory_records.dart';
import '../../core/memory/memory_service.dart';
import '../../core/params/parameters_service.dart';
import '../../services/llm_service.dart';

/// One completed turn in a debate.
class ArenaTurn {
  final int round;
  final String agent; // 'Agent A' | 'Agent B'
  final String text;
  ArenaTurn({required this.round, required this.agent, required this.text});
}

/// Drives a turn-by-turn debate between two personas, each generated through
/// the shared [InferenceWorker] at [TaskPriority.debateRoom] priority — so a
/// live user chat always takes precedence. Every turn is written to the
/// episodic ledger, and a single gated consolidation runs when the debate ends.
class ArenaController extends GetxController {
  ArenaController({
    InferenceWorker? worker,
    EideticMemoryEngine? memory,
    MemoryManager? manager,
  })  : _worker = worker ?? Get.find<InferenceWorker>(),
        _memory = memory ?? Get.find<EideticMemoryEngine>(),
        _manager = manager ?? Get.find<MemoryManager>();

  final InferenceWorker _worker;
  final EideticMemoryEngine _memory;
  final MemoryManager _manager;

  /// The full memory orchestrator — used so a debate agent recalls the same
  /// memory a chat turn would for the topic. Best-effort: a debate still runs
  /// when it isn't registered.
  MemoryService? get _memoryService {
    try {
      return Get.find<MemoryService>();
    } catch (_) {
      return null;
    }
  }

  /// User-tunable parameters (shared with the chat), read for the output budget.
  ParametersService? get _params {
    try {
      return Get.find<ParametersService>();
    } catch (_) {
      return null;
    }
  }

  final transcript = <ArenaTurn>[].obs;
  final isRunning = false.obs;
  final currentRound = 0.obs;
  final currentAgent = ''.obs;
  final liveText = ''.obs;
  final statusMessage = ''.obs;

  bool _cancelled = false;
  String? _activeTaskId;

  static const _proponentPersona =
      'You are Agent A, the Proponent. Argue clearly and persuasively in favour '
      'of the position. Address the latest counter-argument directly. Keep it to '
      'a few tight paragraphs.';

  static const _opponentPersona =
      'You are Agent B, the Opponent. Rebut the latest argument with clear '
      'reasoning and concrete counter-points. Keep it to a few tight paragraphs.';

  /// Run a debate of [rounds] rounds (each round = one A turn + one B turn).
  Future<void> runDebate({
    required String sessionId,
    required String topic,
    int rounds = 3,
  }) async {
    if (isRunning.value) return;
    _cancelled = false;
    isRunning.value = true;
    transcript.clear();
    statusMessage.value = 'Debating: $topic';

    await _memory.recordTurn(sessionId, 'moderator', 'Debate topic: $topic');

    var context = 'The topic of debate is: "$topic".';
    try {
      for (var round = 1; round <= rounds && !_cancelled; round++) {
        currentRound.value = round;

        final argA = await _generate(
          sessionId: sessionId,
          taskId: 'arena-$sessionId-$round-A',
          agent: 'Agent A',
          persona: _proponentPersona,
          topic: topic,
          context:
              '$context\n\nProvide Agent A\'s argument for round $round:',
        );
        if (_cancelled) break;
        context =
            'Agent A argued:\n$argA\n\nNow rebut this as Agent B.';

        final argB = await _generate(
          sessionId: sessionId,
          taskId: 'arena-$sessionId-$round-B',
          agent: 'Agent B',
          persona: _opponentPersona,
          topic: topic,
          context: context,
        );
        if (_cancelled) break;
        context =
            'Agent B rebutted:\n$argB\n\nRespond to this as Agent A in the next round.';
      }

      if (!_cancelled) {
        statusMessage.value = 'Debate complete — consolidating memory…';
        final result = await _manager.consolidatePending();
        statusMessage.value = result.ran
            ? 'Done. Stored ${result.promoted} new insight(s).'
            : 'Done.';
      } else {
        statusMessage.value = 'Debate stopped.';
      }
    } finally {
      isRunning.value = false;
      currentAgent.value = '';
      liveText.value = '';
      _activeTaskId = null;
    }
  }

  Future<String> _generate({
    required String sessionId,
    required String taskId,
    required String agent,
    required String persona,
    required String topic,
    required String context,
  }) async {
    currentAgent.value = agent;
    liveText.value = '';
    _activeTaskId = taskId;

    try {
      // ── Parity with the main chat ──────────────────────────────────────
      // The debate agent is the SAME model with the SAME capabilities as the
      // chat: it recalls relevant memory for the subject, honours the output
      // budget, generates through the model's own chat template (via the
      // worker), and its reply is scrubbed identically. There is no
      // second-class path for agents.

      // Recall the same memory a chat turn would for this subject, and inject
      // it into the agent's system prompt. Best-effort and null-safe.
      var systemPrompt = persona;
      try {
        final recalled = await _memoryService
                ?.remembering(topic, recentContext: context) ??
            '';
        if (recalled.isNotEmpty) {
          systemPrompt = '$persona\n\n$recalled';
        }
      } catch (_) {
        // Recall must never break a debate — fall back to the bare persona.
      }

      // Same adjustable output budget (gen.maxTokens) the chat screen applies.
      final maxTokens = _params?.getInt('gen.maxTokens');

      final raw = await _worker.run(
        id: taskId,
        systemPrompt: systemPrompt,
        messages: [
          {'role': 'user', 'content': context},
        ],
        temperature: 0.8,
        priority: TaskPriority.debateRoom,
        maxTokens: maxTokens,
        onToken: (t) => liveText.value += t,
      );

      // Identical cleanup to the chat's finally block — no stray template
      // tokens or structural HTML in a recorded turn.
      final text = LlmService.scrubReply(raw);

      transcript.add(ArenaTurn(round: currentRound.value, agent: agent, text: text));
      await _memory.record(
        sessionId: sessionId,
        kind: EpisodicKind.turn,
        role: agent == 'Agent A' ? 'agent_a' : 'agent_b',
        content: text,
      );
      return text;
    } on InferenceCancelledException {
      return '';
    } catch (e) {
      await _memory.recordError(sessionId, '$agent generation failed: $e');
      statusMessage.value = 'Error: $e';
      _cancelled = true;
      return '';
    }
  }

  /// Stop an in-progress debate as soon as the current token stream yields.
  void stop() {
    _cancelled = true;
    final id = _activeTaskId;
    if (id != null) _worker.cancel(id);
  }

  @override
  void onClose() {
    stop();
    super.onClose();
  }
}
