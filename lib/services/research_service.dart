import 'package:get/get.dart';

import '../core/engine/inference_worker.dart';
import '../core/research/research_agent.dart';
import '../core/research/research_loop.dart';
import '../core/research/research_records.dart';
import '../core/research/research_store.dart';
import 'llm_service.dart';
import 'log_service.dart';
import 'search_service.dart';

/// Orchestrates the research-agent mode: the user gives a goal and a turn
/// budget (1–100), and this drives the pure [ResearchLoop] over the REAL local
/// LLM (through [InferenceWorker], so it cooperates with the single native
/// engine), the REAL [SearchService] (their own key, any provider), and the
/// REAL on-machine [ResearchStore]. Fetched web text is fenced as untrusted
/// DATA by the loop's injection guard before it reaches the model.
///
/// No fabricated results: if there's no model loaded or no search key, the run
/// refuses with a clear status rather than inventing anything. Reactive state
/// (phase / turn / findings / activity log) is published for the research
/// screen to observe.
class ResearchService extends GetxService {
  ResearchService({
    ResearchStore? store,
    InferenceWorker? worker,
    SearchService? search,
    LlmService? llm,
  })  : _storeOverride = store,
        _workerOverride = worker,
        _searchOverride = search,
        _llmOverride = llm;

  final ResearchStore? _storeOverride;
  final InferenceWorker? _workerOverride;
  final SearchService? _searchOverride;
  final LlmService? _llmOverride;

  late final ResearchStore _store = _storeOverride ?? ResearchStore();
  InferenceWorker get _worker => _workerOverride ?? Get.find<InferenceWorker>();
  SearchService get _search => _searchOverride ?? Get.find<SearchService>();
  LlmService get _llm => _llmOverride ?? Get.find<LlmService>();

  LogService? get _logSvc {
    try {
      return Get.find<LogService>();
    } catch (_) {
      return null;
    }
  }

  // ── Observable state (the research screen binds to these) ────
  final isRunning = false.obs;
  final turnsBudget = 10.obs; // the 1–100 selector's current value
  final currentTurn = 0.obs;
  final findingsCount = 0.obs;
  final phase = ''.obs; // query | search | summarize | store | synthesize | done …
  final statusLine = ''.obs;
  final activity = <String>[].obs; // rolling step log for the UI
  final lastRunId = RxnInt();
  final lastTopicId = RxnInt();

  // ── Live view (watch it research in real time) ──────────────
  final currentQuery = ''.obs; // the query the agent chose this turn
  final currentSources = <String>[].obs; // "title — url" lines pulled this turn
  final liveText = ''.obs; // the summary / synthesis streaming token-by-token
  final liveFindings = <Map<String, String>>[].obs; // findings as they land

  bool _cancel = false;

  Future<void> initialize() => _store.initialize();

  ResearchStore get store => _store;

  void setTurns(int t) => turnsBudget.value = ResearchAgent.clampTurns(t);

  /// Request the current run stop at its next checkpoint.
  void stop() {
    if (isRunning.value) {
      _cancel = true;
      _append('Stopping after the current step…');
    }
  }

  /// Procure data for [goal] over [turns] turns (defaults to [turnsBudget]).
  /// Returns the run id, or null if it refused to start. Never throws.
  Future<int?> procure({
    required String goal,
    int? turns,
    String? topicName,
  }) async {
    if (isRunning.value) {
      statusLine.value = 'A research run is already in progress.';
      return null;
    }
    final g = goal.trim();
    if (g.isEmpty) {
      statusLine.value = 'Enter something to research first.';
      return null;
    }
    if (!_llm.isLoaded.value) {
      statusLine.value =
          'Load a model first — research uses your on-device LLM.';
      return null;
    }
    if (!_search.isConfigured) {
      statusLine.value =
          'No search API key — add one in Settings → Web Search.';
      return null;
    }

    final budget = ResearchAgent.clampTurns(turns ?? turnsBudget.value);
    turnsBudget.value = budget;
    _cancel = false;
    isRunning.value = true;
    currentTurn.value = 0;
    findingsCount.value = 0;
    phase.value = '';
    activity.clear();
    currentQuery.value = '';
    currentSources.clear();
    liveText.value = '';
    liveFindings.clear();

    int? runId;
    try {
      final name = (topicName != null && topicName.trim().isNotEmpty)
          ? topicName.trim()
          : ResearchAgent.deriveTopicName(g);
      final topicId = await _store.upsertTopic(name);
      lastTopicId.value = topicId;
      runId = await _store.startRun(ResearchRun(
        topicId: topicId,
        prompt: g,
        turnsBudget: budget,
        createdUtc: _now(),
      ));
      lastRunId.value = runId;
      _append('Research run #$runId started: “$name” · $budget turns.');

      final outcome = await ResearchLoop.run(
        goal: g,
        turnsBudget: budget,
        think: _think,
        search: _searchFn,
        persistFinding: ({required title, required content}) =>
            _store.addFinding(ResearchFinding(
          topicId: topicId,
          runId: runId,
          title: title,
          content: content,
          createdUtc: _now(),
        )),
        persistSource: (
                {required findingId,
                required url,
                required title,
                required snippet}) =>
            _store.addSource(ResearchSource(
          findingId: findingId,
          url: url,
          title: title,
          snippet: snippet,
          fetchedUtc: _now(),
        )),
        onProgress: _onProgress,
        isCancelled: () => _cancel,
      );

      final syn = outcome.synthesis?.trim() ?? '';
      if (syn.isNotEmpty) {
        // The topic's rolling summary reflects the latest synthesis so the
        // Library shows the deeper picture, not just a finding.
        await _store.upsertTopic(name, summary: syn);
      }
      await _store.finishRun(runId,
          status: outcome.status,
          turnsUsed: outcome.turnsUsed,
          synthesis: syn);
      return runId;
    } catch (e) {
      statusLine.value = 'Research failed: $e';
      _logSvc?.error('research run failed: $e', source: 'Research');
      if (runId != null) {
        try {
          await _store.finishRun(runId,
              status: 'error', turnsUsed: currentTurn.value);
        } catch (_) {}
      }
      return runId;
    } finally {
      isRunning.value = false;
      phase.value = '';
      _cancel = false;
    }
  }

  // ── Loop dependency adapters ────────────────────────────────

  Future<String> _think({
    required String system,
    required String user,
    required double temperature,
    required int maxTokens,
    required String taskId,
  }) {
    // Stream the long-form steps (per-turn summary + the final synthesis) into
    // liveText so the UI shows them being written. The short query-planner
    // calls aren't streamed.
    final streaming = taskId.contains('summary') || taskId.contains('synth');
    if (streaming) liveText.value = '';
    return _worker.run(
      id: 'research-${lastRunId.value ?? 0}-$taskId'
          '-${DateTime.now().microsecondsSinceEpoch}',
      messages: [
        {'role': 'user', 'content': user}
      ],
      systemPrompt: system,
      temperature: temperature,
      maxTokens: maxTokens,
      priority: TaskPriority.userInteraction,
      onToken: streaming ? (tok) => liveText.value += tok : null,
    );
  }

  Future<LoopSearch> _searchFn(String query) async {
    final resp = await _search.search(query, maxResults: 6);
    if (!resp.ok) return LoopSearch.fail(resp.error ?? 'search failed');
    return LoopSearch.ok([
      for (final r in resp.results)
        ResearchHit(title: r.title, url: r.url, snippet: r.snippet),
    ]);
  }

  void _onProgress(ResearchProgress p) {
    if (p.turn > 0) currentTurn.value = p.turn;
    findingsCount.value = p.findings;
    phase.value = p.phase;
    statusLine.value = p.message;
    if (p.query != null) currentQuery.value = p.query!;
    if (p.sources != null) currentSources.assignAll(p.sources!);
    if (p.findingTitle != null) {
      liveFindings.add({
        'title': p.findingTitle!,
        'content': p.findingContent ?? '',
      });
      liveText.value = ''; // this summary is now a stored finding card
    }
    _append(p.message);
  }

  // ── Read-through accessors for the research screen ──────────

  Future<List<ResearchTopic>> topics() => _store.topics();
  Future<List<ResearchRun>> runs({int? topicId}) =>
      _store.runs(topicId: topicId);
  Future<List<ResearchFinding>> findings(int topicId) =>
      _store.findings(topicId: topicId);
  Future<List<ResearchSource>> sources(int findingId) =>
      _store.sources(findingId: findingId);
  Future<String?> latestSynthesis(int topicId) =>
      _store.latestSynthesis(topicId);
  Future<int> topicCount() => _store.topicCount();
  Future<int> findingCount() => _store.findingCount();
  Future<void> clearAll() => _store.clearAll();

  // ── internals ───────────────────────────────────────────────

  String _now() => DateTime.now().toUtc().toIso8601String();

  void _append(String line) {
    activity.add(line);
    if (activity.length > 200) {
      activity.removeRange(0, activity.length - 200);
    }
    _logSvc?.info(line, source: 'Research');
  }

  @override
  void onClose() {
    _store.close();
    super.onClose();
  }
}
