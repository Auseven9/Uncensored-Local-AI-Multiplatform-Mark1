import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/engine/inference_worker.dart';
import '../../core/memory/eidetic_memory_engine.dart';
import '../../core/memory/eidetic_store_io.dart';
import '../../core/memory/memory_records.dart';
import '../../core/memory/memory_manager.dart';
import '../../core/memory/memory_service.dart';
import '../../models/autopilot_scenario.dart';
import '../llm_service.dart';

/// Per-turn performance capture.
class TurnMetric {
  final int index;
  final String user;
  final int replyChars;
  final double tps;
  final int ms;
  const TurnMetric({
    required this.index,
    required this.user,
    required this.replyChars,
    required this.tps,
    required this.ms,
  });
}

/// The outcome of one assertion.
class AssertionResult {
  final AutopilotAssertion assertion;
  final bool passed;
  final String detail;
  const AssertionResult(this.assertion, this.passed, this.detail);
}

/// The full report for one scenario run.
class AutopilotReport {
  final String scenarioName;
  final bool completed;
  final String? error;
  final List<TurnMetric> turns;
  final int consolidationMs;
  final List<AssertionResult> assertions;

  const AutopilotReport({
    required this.scenarioName,
    required this.completed,
    required this.error,
    required this.turns,
    required this.consolidationMs,
    required this.assertions,
  });

  int get passed => assertions.where((a) => a.passed).length;
  int get total => assertions.length;
  bool get allPassed =>
      completed && error == null && total > 0 && passed == total;

  double get avgTps {
    final v = turns.where((t) => t.tps > 0).map((t) => t.tps).toList();
    if (v.isEmpty) return 0;
    return v.reduce((a, b) => a + b) / v.length;
  }

  int get totalMs =>
      turns.fold<int>(0, (s, t) => s + t.ms) + consolidationMs;
}

/// The on-device Autopilot: a headless scenario runner. It drives the REAL
/// inference engine (shared, single-engine), but against an ISOLATED test
/// memory stack (its own `eidetic_autopilot.db` + MemoryService/Manager/Engine)
/// so your real memories are never touched. It feeds scripted user turns,
/// generates replies, forces a consolidation sweep, and asserts against the
/// test SQLite — proving memory behaviour on the real phone/GPU that CI can't.
class AutopilotRunner {
  EideticMemoryEngine? _engine;
  MemoryService? _memory;

  LlmService get _llm => Get.find<LlmService>();

  Future<void> _ensureStack() async {
    if (_engine != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'eidetic_autopilot.db');
    final engine = EideticMemoryEngine(store: SqliteEideticStore(path: path));
    await engine.init();
    // Share the ONE real inference worker so the harness's work is queued on the
    // same engine as everything else.
    final manager = MemoryManager(
      memory: engine,
      worker: Get.find<InferenceWorker>(),
    );
    _engine = engine;
    // autoConsolidate:false is the real serialization guarantee: the service
    // never fires the unawaited opportunistic consolidation (a background model
    // pass) after a turn, so nothing runs on the single native engine while the
    // next turn is generating. The harness instead drives ONE explicit, awaited
    // consolidation per scenario (consolidateNow). That background race — not a
    // threshold — was the "generation already in progress" crash the first run
    // surfaced; each scenario is now a deterministic ingest → consolidate →
    // assert.
    _memory = MemoryService(
        memory: engine, manager: manager, autoConsolidate: false);
  }

  AutopilotReport _errorReport(String name, String error) => AutopilotReport(
        scenarioName: name,
        completed: false,
        error: error,
        turns: const [],
        consolidationMs: 0,
        assertions: const [],
      );

  /// Run [scenario] end-to-end. [onLog] receives live progress lines.
  Future<AutopilotReport> run(
    AutopilotScenario scenario, {
    void Function(String line)? onLog,
    int maxTokens = 256,
  }) async {
    void log(String m) => onLog?.call(m);

    if (!_llm.isLoaded.value) {
      return _errorReport(
          scenario.name, 'No model loaded — load a model first, then run.');
    }
    try {
      await _ensureStack();
    } catch (e) {
      return _errorReport(scenario.name, 'Could not open test database: $e');
    }

    final engine = _engine!;
    final memory = _memory!;

    // Fresh slate in the ISOLATED test DB (never your real memory).
    await engine.clearAll();
    log('Reset isolated test memory. Model: ${_llm.loadedModelFilename}');

    const sessionId = 'autopilot';
    final history = <Map<String, String>>[];
    final turns = <TurnMetric>[];

    for (var i = 0; i < scenario.turns.length; i++) {
      final user = scenario.turns[i];
      log('▶ turn ${i + 1}/${scenario.turns.length}: "$user"');

      // Recall (against the test engine).
      final recent = history.length >= 2
          ? history
              .sublist(history.length - 2)
              .map((m) => m['content'])
              .join('\n')
          : '';
      var system = '';
      try {
        system = await memory.remembering(user, recentContext: recent);
      } catch (e) {
        log('  ⚠ recall error: $e');
      }

      history.add({'role': 'user', 'content': user});

      // A live turn must own the engine — preempt/settle any background task.
      try {
        await Get.find<InferenceWorker>().yieldForForeground();
      } catch (_) {}

      final sw = Stopwatch()..start();
      final buf = StringBuffer();
      try {
        await for (final tok in _llm.generateChat(
          messages: history,
          systemPrompt: system.isEmpty ? null : system,
          temperature: 0.7,
          maxTokens: maxTokens,
        )) {
          buf.write(tok);
        }
      } catch (e) {
        log('  ⚠ generation error: $e');
      }
      sw.stop();

      final reply = LlmService.scrubReply(buf.toString());
      history.add({'role': 'assistant', 'content': reply});
      final tps = _llm.tokensPerSecond.value;
      turns.add(TurnMetric(
        index: i,
        user: user,
        replyChars: reply.length,
        tps: tps,
        ms: sw.elapsedMilliseconds,
      ));
      log('  ↳ ${reply.length} chars · ${tps.toStringAsFixed(1)} t/s · ${sw.elapsedMilliseconds}ms');

      // Write the turn to the TEST episodic ledger.
      try {
        await memory.rememberTurn(
            sessionId: sessionId, userText: user, aiText: reply);
      } catch (e) {
        log('  ⚠ remember error: $e');
      }
    }

    // Force the consolidation sweep (extraction + reconciliation).
    var consolidationMs = 0;
    if (scenario.forceConsolidation) {
      log('⏳ forcing consolidation…');
      final sw = Stopwatch()..start();
      try {
        // Full production pipeline (extract + reconcile, then best-effort embed
        // + reflect), forced past the pending-count gate and fully awaited.
        final r = await memory.consolidateNow();
        log('  ↳ $r');
      } catch (e) {
        log('  ⚠ consolidation error: $e');
      }
      sw.stop();
      consolidationMs = sw.elapsedMilliseconds;
    }

    // Evaluate assertions against the test SQLite.
    log('🔎 evaluating ${scenario.assertions.length} assertions…');
    final facts = await engine.recentFacts(limit: 500);
    final active = facts.where((f) => f.status == ClaimStatus.active).toList();
    log('  (${active.length} active claims in test memory)');
    // Dump each stored claim's structure so a red assertion is explainable at a
    // glance (which subjectType/holder, what slot, what text) instead of guessed.
    for (final f in active) {
      final slot = f.attribute.isNotEmpty ? ' ${f.attribute}=${f.value}' : '';
      log('   • [${f.subjectType.name}/${f.holder.name}] "${f.subject}"$slot :: ${f.text}');
    }

    final results = <AssertionResult>[];
    for (final a in scenario.assertions) {
      bool passed;
      String detail;
      if (a.kind == AssertionKind.claimExists) {
        passed = anyClaimMatches(active, a);
        detail = passed ? 'found' : 'no matching claim';
      } else if (a.kind == AssertionKind.claimAbsent) {
        passed = !anyClaimMatches(active, a);
        detail = passed ? 'correctly absent' : 'UNEXPECTED matching claim';
      } else {
        // recallContains / recallExcludes
        var inj = '';
        try {
          inj = await memory.remembering(a.prompt ?? '');
        } catch (_) {}
        final has = recallTextContains(inj, a.expect ?? '');
        passed = a.kind == AssertionKind.recallContains ? has : !has;
        detail = passed
            ? 'ok'
            : (a.kind == AssertionKind.recallContains
                ? 'not injected'
                : 'leaked into recall');
      }
      results.add(AssertionResult(a, passed, detail));
      log('  ${passed ? '✓' : '✗'} ${a.label} — $detail');
    }

    final report = AutopilotReport(
      scenarioName: scenario.name,
      completed: true,
      error: null,
      turns: turns,
      consolidationMs: consolidationMs,
      assertions: results,
    );
    log('— ${report.passed}/${report.total} assertions passed · '
        'avg ${report.avgTps.toStringAsFixed(1)} t/s · ${report.totalMs}ms —');
    return report;
  }
}
