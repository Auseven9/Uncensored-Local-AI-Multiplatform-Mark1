import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/engine/inference_worker.dart';
import '../core/memory/eidetic_memory_engine.dart';
import 'llm_service.dart';
import 'log_service.dart';

/// Periodic, low-cost health logging plus one-shot startup "arming checks".
///
/// This does **not** touch the model or run inference — it only reads already
/// observable state (is a model loaded? is the worker busy? how deep is the
/// queue? is memory ready?) and writes a snapshot line to the log every tick.
/// Combined with the crash-surviving file sink, the periodic line plus the
/// step logs make it obvious where and when something stalls or dies.
class SystemHealthMonitor extends GetxService {
  Timer? _timer;
  final DateTime _bootedAt = DateTime.now();
  int _tick = 0;

  LogService? get _log {
    try {
      return Get.find<LogService>();
    } catch (_) {
      return null;
    }
  }

  /// Log the arming checks once, then start the periodic snapshot timer.
  SystemHealthMonitor start({Duration interval = const Duration(seconds: 20)}) {
    armingChecks();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _snapshot());
    _log?.info('Health monitor armed · snapshot every ${interval.inSeconds}s',
        source: 'Health');
    return this;
  }

  /// One-shot readiness report for every subsystem.
  void armingChecks() {
    final log = _log;
    if (log == null) return;
    log.info('──────── ARMING CHECKS ────────', source: 'Health');
    log.info('platform=${defaultTargetPlatform.name} web=$kIsWeb '
        'debug=$kDebugMode', source: 'Health');
    log.info(
        'logging: persistent=${log.isPersistent} path=${log.logFilePath ?? '-'}',
        source: 'Health');

    _check('LlmService', () {
      final s = Get.find<LlmService>();
      final model = s.loadedModelFilename.isEmpty ? '-' : s.loadedModelFilename;
      return 'loaded=${s.isLoaded.value} generating=${s.isGenerating.value} model=$model';
    });
    _check('InferenceWorker', () {
      final w = Get.find<InferenceWorker>();
      return 'busy=${w.isBusy} queue=${w.queueDepth.value}';
    });
    _check('EideticMemory', () {
      final m = Get.find<EideticMemoryEngine>();
      return 'ready=${m.isReady.value} persistent=${m.isPersistent} pending=${m.episodicPending.value}';
    });

    log.info('──────── END ARMING CHECKS ────────', source: 'Health');
  }

  void _check(String name, String Function() probe) {
    final log = _log;
    try {
      log?.info('✓ $name · ${probe()}', source: 'Health');
    } catch (e) {
      log?.warn('✗ $name · unavailable: $e', source: 'Health');
    }
  }

  void _snapshot() {
    _tick++;
    final log = _log;
    if (log == null) return;

    final uptime = DateTime.now().difference(_bootedAt).inSeconds;
    final parts = <String>['#$_tick', 'up=${uptime}s'];

    try {
      final s = Get.find<LlmService>();
      parts
        ..add('model=${s.isLoaded.value ? s.loadedModelFilename : "none"}')
        ..add('gen=${s.isGenerating.value}')
        ..add('tps=${s.tokensPerSecond.value.toStringAsFixed(1)}');
    } catch (_) {}
    try {
      final w = Get.find<InferenceWorker>();
      parts
        ..add('busy=${w.isBusy}')
        ..add('queue=${w.queueDepth.value}')
        ..add('active=${w.activeTaskId.value ?? '-'}');
    } catch (_) {}
    try {
      final m = Get.find<EideticMemoryEngine>();
      parts
        ..add('mem=${m.isReady.value ? 'ready' : 'init'}')
        ..add('pending=${m.episodicPending.value}');
    } catch (_) {}

    log.debug('health ${parts.join(' ')}', source: 'Health');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void onClose() {
    stop();
    super.onClose();
  }
}
