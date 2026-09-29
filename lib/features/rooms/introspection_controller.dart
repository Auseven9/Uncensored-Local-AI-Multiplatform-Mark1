import 'dart:async';

import 'package:get/get.dart';

import '../../core/memory/eidetic_memory_engine.dart';
import '../../core/memory/memory_manager.dart';

/// Drives the Introspection Dojo: gated, on-demand memory consolidation.
///
/// This deliberately does **not** hold the model in a continuous generation
/// loop. By default it is completely idle (0% compute). Consolidation runs only
/// when explicitly triggered ([runOnce]) or when optional scheduling is enabled
/// ([enableScheduled]) — and even then each tick first does the cheap,
/// inference-free [MemoryManager.hasPendingWork] check and wakes the model only
/// if there is genuinely something to consolidate.
class IntrospectionController extends GetxController {
  IntrospectionController({
    MemoryManager? manager,
    EideticMemoryEngine? memory,
  })  : _manager = manager ?? Get.find<MemoryManager>(),
        _memory = memory ?? Get.find<EideticMemoryEngine>();

  final MemoryManager _manager;
  final EideticMemoryEngine _memory;

  final isRunning = false.obs;
  final scheduledEnabled = false.obs;
  final lastRunAt = Rxn<DateTime>();
  final lastSummary = ''.obs;

  Timer? _timer;

  /// Live count of episodic rows awaiting consolidation.
  RxInt get pendingCount => _memory.episodicPending;

  /// Run a single consolidation pass now. [force] bypasses the pending-count
  /// threshold (but still no-ops when there is truly nothing pending).
  Future<void> runOnce({bool force = false}) async {
    if (isRunning.value) return;
    isRunning.value = true;
    try {
      final result = await _manager.consolidatePending(force: force);
      lastRunAt.value = DateTime.now();
      lastSummary.value = result.ran
          ? 'Reviewed ${result.considered} entries · '
              '+${result.promoted} stored · ${result.deduped} duplicates skipped'
          : 'Idle — ${result.note ?? 'nothing to consolidate'}';
    } finally {
      isRunning.value = false;
    }
  }

  /// Enable a low-frequency background checker. Each tick only runs the model
  /// when [MemoryManager.hasPendingWork] is true, so the GPU stays at rest
  /// during quiet periods. Default interval is intentionally long.
  void enableScheduled({Duration interval = const Duration(minutes: 10)}) {
    _timer?.cancel();
    scheduledEnabled.value = true;
    _timer = Timer.periodic(interval, (_) async {
      if (isRunning.value) return;
      if (await _manager.hasPendingWork()) {
        await runOnce();
      }
    });
  }

  void disableScheduled() {
    _timer?.cancel();
    _timer = null;
    scheduledEnabled.value = false;
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }
}
