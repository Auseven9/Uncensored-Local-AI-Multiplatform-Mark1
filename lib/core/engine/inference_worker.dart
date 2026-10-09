import 'dart:async';

import 'package:get/get.dart';

import '../../services/llm_service.dart';
import '../../services/log_service.dart';

/// Relative priority of an inference request. Lower index = higher priority.
///
/// A live user turn always wins over a debate turn, which wins over a
/// background introspection pass.
enum TaskPriority { userInteraction, debateRoom, backgroundIntrospection }

/// Thrown into a task's future when it is cancelled or preempted before
/// (or during) execution. Background callers treat this as a benign "try
/// again later" signal rather than an error.
class InferenceCancelledException implements Exception {
  final String taskId;
  const InferenceCancelledException(this.taskId);

  @override
  String toString() => 'InferenceCancelledException($taskId)';
}

/// A single unit of work for the [InferenceWorker].
class InferenceTask {
  final String id;
  final List<Map<String, String>> messages;
  final String? systemPrompt;
  final double temperature;
  final TaskPriority priority;

  /// Optional GBNF grammar. When set, the task is generated with
  /// sampler-enforced grammar constraints via [LlmService.generateWithGrammar]
  /// (raw structured output). When null, the task generates through the model's
  /// OWN chat template via [LlmService.generateChat] — the exact path the main
  /// chat uses, so a debate turn is templated and stopped identically to a chat
  /// turn (no second-class hand-rolled prompt for off-chat generation).
  final String? grammar;

  /// Optional output budget (max reply tokens) — the same `gen.maxTokens`
  /// ceiling the chat screen applies. Ignored for grammar tasks. Null falls
  /// back to llamadart's own default.
  final int? maxTokens;

  /// Optional live-token callback, invoked on the main isolate for each
  /// cleaned chunk as it is produced (used by the Arena to stream turns).
  final void Function(String token)? onToken;

  final Completer<String> _completer = Completer<String>();
  int _seq = 0;
  bool _cancelled = false;

  InferenceTask({
    required this.id,
    required this.messages,
    this.systemPrompt,
    this.temperature = 0.7,
    this.priority = TaskPriority.userInteraction,
    this.grammar,
    this.maxTokens,
    this.onToken,
  });

  /// Completes with the full generated text, or errors with
  /// [InferenceCancelledException] / the underlying failure.
  Future<String> get future => _completer.future;
}

/// Priority-serialised inference scheduler layered over [LlmService].
///
/// ### Why this is not a raw-FFI Dart isolate
///
/// The original blueprint proposed a dedicated isolate that owns the native
/// llama.cpp context via raw FFI. This app already delegates all native work
/// to the `llamadart` package through [LlmService], and `llamadart` runs the
/// heavy decode off the UI isolate internally. Introducing a *second* owner of
/// the native context (raw FFI in another isolate) is precisely how you get
/// the double-frees and SIGSEGVs the blueprint set out to prevent. So instead
/// of duplicating engine ownership, this worker provides the property that
/// actually matters for crash-safety: **exactly one generation runs at a
/// time**, ordered by priority, with clean cancellation.
///
/// The scheduler also cooperates with direct callers of [LlmService] (the
/// chat screen streams straight through it): it defers dispatch while a
/// non-worker generation is in flight, so the single-flight invariant holds
/// app-wide, not just within the queue.
class InferenceWorker extends GetxService {
  LlmService get _llm => Get.find<LlmService>();

  LogService? get _log {
    try {
      return Get.find<LogService>();
    } catch (_) {
      return null;
    }
  }

  final _queue = <InferenceTask>[];
  InferenceTask? _running;
  int _seqCounter = 0;
  bool _pumping = false;

  /// After a generation is cancelled, the native context needs a moment to
  /// actually tear the decode down. Dispatching the next task the instant
  /// [LlmService.isGenerating] flips false (it flips synchronously on
  /// [LlmService.stopGeneration]) can beat the native release and trip
  /// "generation already in progress". So every cancel arms a short settle
  /// window that [_pump] waits out before starting the next task.
  static const _settleAfterCancel = Duration(milliseconds: 250);
  DateTime _settleUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Arm the post-cancel settle window (called from every place that cancels a
  /// running generation).
  void _armSettle() {
    _settleUntil = DateTime.now().add(_settleAfterCancel);
  }

  /// Id of the task currently generating, or null when idle.
  final activeTaskId = RxnString();

  /// Number of tasks waiting to run.
  final queueDepth = 0.obs;

  bool get isBusy => _running != null;

  /// Convenience wrapper: build a task from parts and submit it.
  Future<String> run({
    required String id,
    required List<Map<String, String>> messages,
    String? systemPrompt,
    double temperature = 0.7,
    TaskPriority priority = TaskPriority.userInteraction,
    String? grammar,
    int? maxTokens,
    void Function(String token)? onToken,
  }) {
    return submit(InferenceTask(
      id: id,
      messages: messages,
      systemPrompt: systemPrompt,
      temperature: temperature,
      priority: priority,
      grammar: grammar,
      maxTokens: maxTokens,
      onToken: onToken,
    ));
  }

  /// Enqueue [task]; returns its completion future.
  Future<String> submit(InferenceTask task) {
    task._seq = _seqCounter++;
    _queue.add(task);
    _sortQueue();
    queueDepth.value = _queue.length;
    _maybePreemptFor(task);
    // Kick the pump without awaiting — callers await [task.future] instead.
    unawaited(_pump());
    return task.future;
  }

  /// Make the engine available to a foreground caller that streams straight
  /// through [LlmService] (the chat screen), rather than through this queue.
  ///
  /// A live user turn is the top of the priority order, so it wins over
  /// anything the worker is running — a background consolidation OR a debate
  /// turn. Whatever is generating is cancelled (a background task's entries
  /// stay pending; a debate turn returns empty and the debate moves on), then
  /// this waits until the engine has actually released and the post-cancel
  /// settle window has elapsed, so the direct [LlmService.generateChat] call
  /// that follows cannot collide with a "generation already in progress" error.
  /// Best-effort and safe to call when idle.
  Future<void> yieldForForeground(
      {Duration timeout = const Duration(seconds: 6)}) async {
    final running = _running;
    if (running != null &&
        running.priority != TaskPriority.userInteraction) {
      _log?.info(
        'Yielding engine to foreground: cancelling ${running.priority.name} '
        '${running.id}',
        source: 'Inference',
      );
      running._cancelled = true;
      await _llm.stopGeneration();
      _armSettle();
    }
    // Wait until the background task has fully unwound and the engine is free.
    final deadline = DateTime.now().add(timeout);
    while ((_running != null || _llm.isGenerating.value) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    // Let the native decode finish releasing before the caller starts its own
    // direct generation, so it doesn't collide with a still-unwinding cancel.
    final settleLeft = _settleUntil.difference(DateTime.now());
    if (settleLeft > Duration.zero) {
      await Future<void>.delayed(settleLeft);
    }
  }

  /// Cancel a queued or running task by id. Safe to call for unknown ids.
  void cancel(String taskId) {
    if (_running?.id == taskId) {
      _running!._cancelled = true;
      unawaited(_llm.stopGeneration());
      _armSettle();
    }
    for (final t in _queue) {
      if (t.id == taskId) t._cancelled = true;
    }
  }

  void _sortQueue() {
    _queue.sort((a, b) {
      final byPriority = a.priority.index.compareTo(b.priority.index);
      if (byPriority != 0) return byPriority;
      return a._seq.compareTo(b._seq); // stable FIFO within a priority band
    });
  }

  /// If a strictly higher-priority task arrives while a *background* task is
  /// running, preempt the running one so the newcomer can start promptly.
  void _maybePreemptFor(InferenceTask incoming) {
    final running = _running;
    if (running == null) return;
    final higher = incoming.priority.index < running.priority.index;
    if (higher && running.priority == TaskPriority.backgroundIntrospection) {
      _log?.info(
        'Preempting background task ${running.id} for ${incoming.id}',
        source: 'Inference',
      );
      running._cancelled = true;
      unawaited(_llm.stopGeneration());
      _armSettle();
    }
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty) {
        // Respect any generation started directly on [LlmService] (chat UI),
        // and wait out any post-cancel settle window so a freshly cancelled
        // native decode has fully released before the next task starts (else it
        // trips "generation already in progress").
        if (_llm.isGenerating.value || DateTime.now().isBefore(_settleUntil)) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          continue;
        }

        final task = _queue.removeAt(0);
        queueDepth.value = _queue.length;

        if (task._cancelled) {
          _fail(task, InferenceCancelledException(task.id));
          continue;
        }

        _running = task;
        activeTaskId.value = task.id;
        _log?.info(
          'dispatch: ${task.id} · prio=${task.priority.name} '
          'grammar=${task.grammar != null} queueLeft=${_queue.length}',
          source: 'Inference',
        );
        try {
          if (!_llm.isLoaded.value) {
            throw StateError('No model is loaded. Load a model first.');
          }

          final buffer = StringBuffer();
          final grammar = task.grammar;
          // Non-grammar tasks (debate turns, plain generations, and now
          // memory consolidation) go through the model's OWN chat template —
          // the identical path the chat screen uses — so off-chat generation
          // is never a second-class hand-rolled prompt, and runs at full GPU
          // chat speed. Any task that still opts into a grammar stays on the
          // raw grammar-constrained path so its structured output is preserved
          // verbatim (at the cost of CPU-bound sampler speed on large vocabs).
          final stream = grammar == null
              ? _llm.generateChat(
                  messages: task.messages,
                  systemPrompt: task.systemPrompt,
                  temperature: task.temperature,
                  maxTokens: task.maxTokens,
                )
              : _llm.generateWithGrammar(
                  messages: task.messages,
                  grammar: grammar,
                  systemPrompt: task.systemPrompt,
                  temperature: task.temperature,
                );

          await for (final chunk in stream) {
            if (task._cancelled) {
              await _llm.stopGeneration();
              _armSettle();
              break;
            }
            buffer.write(chunk);
            task.onToken?.call(chunk);
          }

          if (task._cancelled) {
            _log?.warn('cancelled: ${task.id}', source: 'Inference');
            _fail(task, InferenceCancelledException(task.id));
          } else if (!task._completer.isCompleted) {
            _log?.info('done: ${task.id} · chars=${buffer.length}',
                source: 'Inference');
            task._completer.complete(buffer.toString().trim());
          }
        } catch (e, st) {
          _log?.error('task ${task.id} FAILED · $e', source: 'Inference');
          _log?.debug('task ${task.id} stack · $st', source: 'Inference');
          _fail(task, e, st);
        } finally {
          _running = null;
          activeTaskId.value = null;
        }
      }
    } finally {
      _pumping = false;
    }
  }

  void _fail(InferenceTask task, Object error, [StackTrace? st]) {
    if (!task._completer.isCompleted) {
      task._completer.completeError(error, st);
    }
  }

  @override
  void onClose() {
    // Fail anything still queued so awaiters don't hang forever.
    final pending = [..._queue];
    _queue.clear();
    for (final t in pending) {
      _fail(t, const InferenceCancelledException('worker-closed'));
    }
    super.onClose();
  }
}
