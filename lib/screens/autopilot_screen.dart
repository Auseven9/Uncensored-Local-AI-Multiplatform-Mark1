import 'package:flutter/material.dart';

import '../models/autopilot_scenario.dart';
import '../services/autopilot/autopilot_runner.dart';

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
  final List<String> _log = [];
  final ScrollController _logScroll = ScrollController();

  bool _running = false;
  String _currentName = '';
  final List<AutopilotReport> _reports = [];

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }

  void _appendLog(String line) {
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
      _reports.clear();
    });
    for (final s in scenarios) {
      setState(() => _currentName = s.name);
      _appendLog('════ ${s.name} ════');
      final report = await _runner.run(s, onLog: _appendLog);
      setState(() => _reports.add(report));
    }
    setState(() {
      _running = false;
      _currentName = '';
    });
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
