/// The research agent's N-turn procurement loop — pure, with injected deps.
///
/// The loop is the heart of the research mode: prompt → the local LLM picks a
/// search query → real web search → fetched text is fenced as UNTRUSTED DATA
/// and summarized → the summary + its sources are stored → repeat to the turn
/// budget → a final high-level "organize" pass rolls the findings into a topic
/// summary.
///
/// Every outside effect — the LLM, the network, the database — is injected as a
/// function, so the whole control flow (query dedupe, empty-result handling,
/// the injection-guard seam, error stops, budget accounting, cancellation) is
/// exercised in unit tests with no GGUF model and no live search key. The
/// [ResearchService] supplies the real functions.
library;

import 'injection_guard.dart';
import 'research_agent.dart';

/// One web result handed to the loop (provider-agnostic; the service maps
/// `SearchResult` onto this so core stays free of the services layer).
class ResearchHit {
  final String title;
  final String url;
  final String snippet;
  const ResearchHit(
      {required this.title, required this.url, required this.snippet});
}

/// The outcome of one search call inside the loop. Never throws to the loop.
class LoopSearch {
  final bool ok;
  final List<ResearchHit> hits;
  final String? error;
  const LoopSearch(this.ok, this.hits, this.error);
  factory LoopSearch.ok(List<ResearchHit> hits) => LoopSearch(true, hits, null);
  factory LoopSearch.fail(String error) => LoopSearch(false, const [], error);
}

/// A progress event emitted as the loop runs (drives the research screen).
class ResearchProgress {
  final int turn;
  final int turnsBudget;
  final int findings;
  final String phase; // query | search | summarize | store | organize | done | error
  final String message;
  const ResearchProgress({
    required this.turn,
    required this.turnsBudget,
    required this.findings,
    required this.phase,
    required this.message,
  });
}

/// The final result of a whole procurement run.
class ResearchOutcome {
  final int turnsUsed;
  final int findings;
  final String status; // done | stopped | error | empty
  final String? error;
  final String? topicSummary;
  const ResearchOutcome({
    required this.turnsUsed,
    required this.findings,
    required this.status,
    this.error,
    this.topicSummary,
  });
}

typedef ThinkFn = Future<String> Function({
  required String system,
  required String user,
  required double temperature,
  required int maxTokens,
  required String taskId,
});
typedef SearchFn = Future<LoopSearch> Function(String query);
typedef PersistFindingFn = Future<int> Function({
  required String title,
  required String content,
});
typedef PersistSourceFn = Future<void> Function({
  required int findingId,
  required String url,
  required String title,
  required String snippet,
});
typedef ProgressFn = void Function(ResearchProgress progress);

class ResearchLoop {
  const ResearchLoop._();

  /// Drive one procurement run. Pure control flow over injected effects.
  static Future<ResearchOutcome> run({
    required String goal,
    required int turnsBudget,
    required ThinkFn think,
    required SearchFn search,
    required PersistFindingFn persistFinding,
    required PersistSourceFn persistSource,
    ProgressFn? onProgress,
    bool Function()? isCancelled,
    int maxResultsPerTurn = 6,
    int queryMaxTokens = 64,
    int summaryMaxTokens = 512,
    double queryTemperature = 0.5,
    double summaryTemperature = 0.4,
    int snippetCap = 2000,
  }) async {
    final budget = ResearchAgent.clampTurns(turnsBudget);
    final seen = <String>{};
    final priorQueries = <String>[];
    final collected = <ParsedSummary>[]; // for the organize pass
    var findings = 0;
    var turnsUsed = 0;

    bool cancelled() => isCancelled?.call() ?? false;
    void emit(String phase, String message, {int turn = 0}) =>
        onProgress?.call(ResearchProgress(
          turn: turn,
          turnsBudget: budget,
          findings: findings,
          phase: phase,
          message: message,
        ));

    String? fatalError;
    var hadErrorStop = false;

    for (var turn = 1; turn <= budget; turn++) {
      if (cancelled()) {
        emit('stopped', 'Stopped at turn $turn.', turn: turn);
        break;
      }

      // 1 — the model picks the next query.
      emit('query', 'Turn $turn: choosing a search query…', turn: turn);
      String rawQuery;
      try {
        rawQuery = await think(
          system: ResearchAgent.querySystemPrompt(),
          user: ResearchAgent.queryUserPrompt(
            goal: goal,
            priorQueries: priorQueries,
            turn: turn,
            budget: budget,
          ),
          temperature: queryTemperature,
          maxTokens: queryMaxTokens,
          taskId: 'research-query-$turn',
        );
      } catch (e) {
        fatalError = 'The model failed while choosing a query: $e';
        hadErrorStop = true;
        emit('error', fatalError, turn: turn);
        break;
      }
      final query = ResearchAgent.parseQuery(rawQuery);
      if (!ResearchAgent.isNovelQuery(query, seen)) {
        // Empty or repeated query → the planner has nothing new; stop cleanly.
        emit('done',
            'Turn $turn: no new query to try — wrapping up.', turn: turn);
        break;
      }
      seen.add(ResearchAgent.normalizeQuery(query));
      priorQueries.add(query);

      // 2 — real web search.
      if (cancelled()) break;
      emit('search', 'Turn $turn: searching “$query”…', turn: turn);
      final LoopSearch result;
      try {
        result = await search(query);
      } catch (e) {
        fatalError = 'Search failed: $e';
        hadErrorStop = true;
        emit('error', fatalError, turn: turn);
        break;
      }
      turnsUsed = turn;
      if (!result.ok) {
        fatalError = result.error ?? 'Search failed.';
        hadErrorStop = true;
        emit('error', 'Turn $turn: ${result.error ?? 'search failed'}.',
            turn: turn);
        break;
      }
      if (result.hits.isEmpty) {
        emit('search', 'Turn $turn: no results for “$query”.', turn: turn);
        continue;
      }

      // 3 — fence each hit as UNTRUSTED DATA (the rogue-prompt guard).
      final fenced = <String>[];
      final sanitizedSources = <ResearchHit>[];
      var injectionSeen = false;
      for (final h in result.hits) {
        final body = h.snippet.trim().isNotEmpty ? h.snippet : h.title;
        final guarded = InjectionGuard.guardForPrompt(body,
            sourceUrl: h.url, maxChars: snippetCap);
        fenced.add(guarded.block);
        if (guarded.guard.injectionDetected) injectionSeen = true;
        sanitizedSources.add(ResearchHit(
          title: h.title,
          url: h.url,
          snippet: guarded.guard.text,
        ));
      }

      // 4 — summarize the fenced data.
      if (cancelled()) break;
      emit('summarize',
          'Turn $turn: summarizing ${result.hits.length} results…', turn: turn);
      String rawSummary;
      try {
        rawSummary = await think(
          system: ResearchAgent.summarySystemPrompt(),
          user: ResearchAgent.summaryUserPrompt(
            goal: goal,
            query: query,
            fencedBlocks: fenced,
          ),
          temperature: summaryTemperature,
          maxTokens: summaryMaxTokens,
          taskId: 'research-summary-$turn',
        );
      } catch (e) {
        // A single bad summary isn't fatal — note it and move on.
        emit('summarize',
            'Turn $turn: summary step failed, skipping ($e).', turn: turn);
        continue;
      }
      final parsed = ResearchAgent.parseSummary(rawSummary, query: query);
      var content = parsed.content;
      if (injectionSeen) {
        content = '$content\n\n⚠ A source attempted prompt injection; its '
            'embedded instructions were ignored and only the factual content '
            'was used.';
      }

      // 5 — store the finding + its sources (provenance kept).
      final int findingId;
      try {
        findingId = await persistFinding(title: parsed.title, content: content);
        for (final s in sanitizedSources) {
          await persistSource(
            findingId: findingId,
            url: s.url,
            title: s.title,
            snippet: s.snippet,
          );
        }
      } catch (e) {
        fatalError = 'Storing the finding failed: $e';
        hadErrorStop = true;
        emit('error', fatalError, turn: turn);
        break;
      }
      findings++;
      collected.add(parsed);
      emit(
          'store',
          'Turn $turn: stored “${parsed.title}” from ${result.hits.length} '
              'source(s)${injectionSeen ? ' · injection blocked' : ''}.',
          turn: turn);
    }

    // 6 — organize: roll the run's findings into a high-level topic summary.
    String? topicSummary;
    if (!hadErrorStop && !cancelled() && collected.isNotEmpty) {
      emit('organize', 'Organizing ${collected.length} findings…',
          turn: turnsUsed);
      try {
        final raw = await think(
          system: ResearchAgent.organizeSystemPrompt(),
          user: ResearchAgent.organizeUserPrompt(
            goal: goal,
            titles: [for (final c in collected) c.title],
            contents: [for (final c in collected) c.content],
          ),
          temperature: 0.4,
          maxTokens: 400,
          taskId: 'research-organize',
        );
        final s = raw.trim();
        if (s.isNotEmpty) topicSummary = s;
      } catch (_) {
        // Non-fatal: the findings are already stored.
      }
    }

    final status = hadErrorStop
        ? 'error'
        : cancelled()
            ? 'stopped'
            : findings == 0
                ? 'empty'
                : 'done';
    emit(status, _finalMessage(status, findings), turn: turnsUsed);
    return ResearchOutcome(
      turnsUsed: turnsUsed,
      findings: findings,
      status: status,
      error: fatalError,
      topicSummary: topicSummary,
    );
  }

  static String _finalMessage(String status, int findings) {
    switch (status) {
      case 'error':
        return 'Run stopped on an error after storing $findings finding(s).';
      case 'stopped':
        return 'Run stopped. Stored $findings finding(s).';
      case 'empty':
        return 'Run finished with no findings stored.';
      default:
        return 'Run complete — stored $findings finding(s).';
    }
  }
}
