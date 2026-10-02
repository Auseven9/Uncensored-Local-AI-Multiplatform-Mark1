import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../controllers/model_controller.dart';
import '../core/diagnostics/gpu_pentest.dart';
import '../core/diagnostics/gpu_trial.dart';
import '../models/autopilot_scenario.dart';
import '../services/autopilot/autopilot_runner.dart';
import '../services/llm_service.dart';

/// Developer self-test harness UI (reached by long-pressing the version text in
/// Settings). Runs scripted scenarios through the REAL engine against an
/// isolated test memory DB, then shows pass/fail + live performance metrics —
/// so each build's memory behaviour is provable on the real phone.
class AutopilotScreen extends StatefulWidget {
  const AutopilotScreen({super.key});

  @override
  State<AutopilotScreen> createState() => _AutopilotScreenState();
}

class _AutopilotScreenState extends State<AutopilotScreen> {
  final AutopilotRunner _runner = AutopilotRunner();
  final List<AutopilotScenario> _scenarios = builtInScenarios();
  final List<String> _log = []; // capped, for the on-screen ListView
  final List<String> _transcript = []; // full, uncapped — what "Copy log" copies
  final ScrollController _logScroll = ScrollController();

  bool _running = false;
  String _currentName = '';
  final List<AutopilotReport> _reports = [];

  // GPU pen-test harness — can this device actually get INTO Vulkan / OpenCL?
  late final GpuPenTest _gpu;
  bool _gpuRunning = false;

  @override
  void initState() {
    super.initState();
    _gpu = GpuPenTest(Get.find<LlmService>());
    _loadGpuCrashBreadcrumb();
  }

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }

  /// On open, surface any GPU trial that never finished last time — i.e. a
  /// config that hard-crashed the app. This is the whole point of the
  /// write-ahead breadcrumb: a crash becomes an attributable data point.
  Future<void> _loadGpuCrashBreadcrumb() async {
    String? note;
    try {
      note = await _gpu.loadAndReconcile();
    } catch (_) {
      note = null;
    }
    if (!mounted || note == null) return;
    _appendLog('⚠ last GPU pen-test did not finish — it crashed the app:');
    _appendLog('  $note');
  }

  /// Run one isolated GPU trial. Captures the resident model's path first
  /// (the trial unloads it), write-ahead-logs the attempt, then reports.
  Future<void> _gpuStage(TrialBackend backend, int layers) async {
    if (_gpuRunning || _running) return;
    final path = Get.find<LlmService>().loadedModelPath.value;
    if (path.isEmpty) {
      _toast('Load a model first — the trial reloads it on the GPU');
      return;
    }
    setState(() => _gpuRunning = true);
    _appendLog('▶ GPU pen-test: ${backend.label} ×$layers — unloading model, '
        'trying GPU load (may crash if the driver is bad)…');
    try {
      final r = await _gpu.runStage(
        backend: backend,
        layers: layers,
        modelPath: path,
      );
      _appendLog(r.line);
      if (r.status == GpuTrialStatus.ok) {
        _appendLog('  → GPU works here. Set backend=${backend.label}, '
            'GPU layers=$layers in Settings ▸ Hardware, then reload.');
      }
      _appendLog('  (model is now unloaded — re-arm it from the chat home)');
    } catch (e) {
      _appendLog('✗ pen-test error: $e');
    } finally {
      if (mounted) setState(() => _gpuRunning = false);
    }
  }

  Widget _gpuBtn(String label, TrialBackend backend, int layers) =>
      OutlinedButton(
        onPressed: (_gpuRunning || _running) ? null : () => _gpuStage(backend, layers),
        child: Text(label),
      );

  void _appendLog(String line) {
    _transcript.add(line); // full record, never truncated
    setState(() {
      _log.add(line);
      if (_log.length > 300) _log.removeRange(0, _log.length - 300);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _run(List<AutopilotScenario> scenarios) async {
    if (_running) return;
    setState(() {
      _running = true;
      _log.clear();
      _transcript.clear();
      _reports.clear();
    });
    // Self-identifying header: exactly which app version, model, embedder and
    // GPU/CPU backend produced these results — so a pasted log is unambiguous.
    await _emitSystemsHeader();
    for (final s in scenarios) {
      setState(() => _currentName = s.name);
      _appendLog('════ ${s.name} ════');
      final report = await _runner.run(s, onLog: _appendLog);
      setState(() => _reports.add(report));
    }
    _appendLog('════ done · ${_reports.where((r) => r.allPassed).length}/'
        '${_reports.length} scenarios green ════');
    setState(() {
      _running = false;
      _currentName = '';
    });
  }

  Future<void> _emitSystemsHeader() async {
    try {
      final report = await Get.find<ModelController>().systemsReport();
      for (final l in report.split('\n')) {
        _appendLog(l);
      }
    } catch (e) {
      _appendLog('systems check unavailable: $e');
    }
  }

  /// One-tap health snapshot: appends it to the log AND copies it to the
  /// clipboard, so you can paste "exactly what I'm running" without a full run.
  Future<void> _systemsCheck() async {
    String report;
    try {
      report = await Get.find<ModelController>().systemsReport();
    } catch (e) {
      report = 'systems check failed: $e';
    }
    setState(() {
      _log.clear();
      _transcript.clear();
    });
    for (final l in report.split('\n')) {
      _appendLog(l);
    }
    await Clipboard.setData(ClipboardData(text: report));
    _toast('Systems check copied');
  }

  void _copyLog() {
    final text = _transcript.join('\n');
    if (text.isEmpty) {
      _toast('Nothing to copy yet — run a scenario first');
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    _toast('Log copied (${_transcript.length} lines)');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Autopilot · self-test'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('On-device self-test',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Runs scripted conversations through the REAL model against '
                    'an isolated test database (your real memories are never '
                    'touched), then checks what survived. Load a model first. '
                    'Each turn is a real generation, so a scenario takes real '
                    'time (~seconds/turn).',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _running ? null : () => _run(_scenarios),
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(_running
                ? 'Running: $_currentName'
                : 'Run all (${_scenarios.length})'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _running ? null : _systemsCheck,
                  icon: const Icon(Icons.monitor_heart_outlined, size: 18),
                  label: const Text('Systems check'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copyLog,
                  icon: const Icon(Icons.copy_all_rounded, size: 18),
                  label: const Text('Copy log'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // GPU pen test
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GPU pen test (Vulkan / OpenCL)',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Tries to get INTO the GPU and actually compute, one config '
                    'at a time. Each test UNLOADS your model and attempts a '
                    'throwaway load on the chosen backend + layer count, then '
                    'runs a few tokens — results go to the log below. If the app '
                    'vanishes, that config crashed the driver; reopen this screen '
                    'and the crash is recorded at the top of the log. Start low '
                    '(×1) and climb. Load a model first.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _gpuBtn('Vulkan ×1', TrialBackend.vulkan, 1),
                      _gpuBtn('Vulkan ×8', TrialBackend.vulkan, 8),
                      _gpuBtn('Vulkan ×99', TrialBackend.vulkan, 99),
                      _gpuBtn('OpenCL ×1', TrialBackend.opencl, 1),
                      _gpuBtn('OpenCL ×99', TrialBackend.opencl, 99),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _gpuRunning
                        ? null
                        : () async {
                            await _gpu.clear();
                            _appendLog('— GPU pen-test history cleared —');
                          },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Clear GPU history'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Scenarios
          ..._scenarios.map((s) => Card(
                child: ListTile(
                  title: Text(s.name),
                  subtitle: Text(
                    '${s.turns.length} turns · ${s.assertions.length} assertions'
                    '${s.description.isEmpty ? '' : '\n${s.description}'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  isThreeLine: s.description.isNotEmpty,
                  trailing: IconButton(
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: _running ? null : () => _run([s]),
                  ),
                ),
              )),

          // Reports
          if (_reports.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Results', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._reports.map((r) => _reportCard(context, r)),
          ],

          // Live log
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Log', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Container(
              height: 240,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Scrollbar(
                controller: _logScroll,
                child: ListView.builder(
                  controller: _logScroll,
                  itemCount: _log.length,
                  itemBuilder: (_, i) => Text(
                    _log[i],
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11, height: 1.35),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _reportCard(BuildContext context, AutopilotReport r) {
    final theme = Theme.of(context);
    final ok = r.allPassed;
    final color = r.error != null
        ? Colors.orange
        : (ok ? Colors.green : Colors.red);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                    r.error != null
                        ? Icons.error_outline
                        : (ok ? Icons.check_circle : Icons.cancel),
                    color: color,
                    size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r.scenarioName,
                      style: theme.textTheme.titleSmall),
                ),
                Text(
                  r.error != null ? 'ERROR' : '${r.passed}/${r.total}',
                  style: theme.textTheme.titleSmall?.copyWith(color: color),
                ),
              ],
            ),
            if (r.error != null) ...[
              const SizedBox(height: 6),
              Text(r.error!, style: theme.textTheme.bodySmall),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'avg ${r.avgTps.toStringAsFixed(1)} t/s · '
                'turns ${r.totalMs - r.consolidationMs}ms · '
                'consolidation ${r.consolidationMs}ms',
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              ...r.assertions.map((a) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(a.passed ? Icons.check : Icons.close,
                            size: 15,
                            color: a.passed ? Colors.green : Colors.red),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('${a.assertion.label} — ${a.detail}',
                              style: theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}
