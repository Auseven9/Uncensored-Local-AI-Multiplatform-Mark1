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
    void Function(String token)? onToken,
  }) {
    return submit(InferenceTask(
      id: id,
      messages: messages,
      systemPrompt: systemPrompt,
      temperature: temperature,
      priority: priority,
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

  /// Cancel a queued or running task by id. Safe to call for unknown ids.
  void cancel(String taskId) {
    if (_running?.id == taskId) {
      _running!._cancelled = true;
      unawaited(_llm.stopGeneration());
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
    }
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty) {
        // Respect any generation started directly on [LlmService] (chat UI).
        if (_llm.isGenerating.value) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
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
        try {
          if (!_llm.isLoaded.value) {
            throw StateError('No model is loaded. Load a model first.');
          }

          final buffer = StringBuffer();
          final stream = _llm.generate(
            messages: task.messages,
            systemPrompt: task.systemPrompt,
            temperature: task.temperature,
          );

          await for (final chunk in stream) {
            if (task._cancelled) {
              await _llm.stopGeneration();
              break;
            }
            buffer.write(chunk);
            task.onToken?.call(chunk);
          }

          if (task._cancelled) {
            _fail(task, InferenceCancelledException(task.id));
          } else if (!task._completer.isCompleted) {
            task._completer.complete(buffer.toString().trim());
          }
        } catch (e, st) {
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
