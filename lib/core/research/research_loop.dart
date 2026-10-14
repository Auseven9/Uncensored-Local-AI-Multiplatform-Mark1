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
/// Carries enough that the UI can show WHAT is being researched live — the
/// query chosen, the sources pulled, and a finding as it lands — not just a
/// status line.
class ResearchProgress {
  final int turn;
  final int turnsBudget;
  final int findings;
  final String phase; // query | search | summarize | store | synthesize | done | error
  final String message;

  /// The query chosen this turn (set from the search phase on).
  final String? query;

  /// Sources pulled this turn, as "title — url" display lines.
  final List<String>? sources;

  /// A finding that just landed (set on the store phase).
  final String? findingTitle;
  final String? findingContent;

  const ResearchProgress({
    required this.turn,
    required this.turnsBudget,
    required this.findings,
    required this.phase,
    required this.message,
    this.query,
    this.sources,
    this.findingTitle,
    this.findingContent,
  });
}

/// The final result of a whole procurement run.
class ResearchOutcome {
  final int turnsUsed;
  final int findings;
  final String status; // done | stopped | error | empty
  final String? error;

  /// The capstone synthesis — the cross-finding, deeper-connections pass.
  final String? synthesis;
  const ResearchOutcome({
    required this.turnsUsed,
    required this.findings,
    required this.status,
    this.error,
    this.synthesis,
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
    int summaryMaxTokens = 768,
    double queryTemperature = 0.5,
    double summaryTemperature = 0.4,
    int snippetCap = 2000,
  }) async {
    final budget = ResearchAgent.clampTurns(turnsBudget);
    final priorQueries = <String>[];
    final coveredTitles = <String>[]; // facets covered, fed back to the planner
    final collected = <ParsedSummary>[]; // for the synthesis pass
    var findings = 0;
    var turnsUsed = 0;

    bool cancelled() => isCancelled?.call() ?? false;
    void emit(
      String phase,
      String message, {
      int turn = 0,
      String? query,
      List<String>? sources,
      String? findingTitle,
      String? findingContent,
    }) =>
        onProgress?.call(ResearchProgress(
          turn: turn,
          turnsBudget: budget,
          findings: findings,
          phase: phase,
          message: message,
          query: query,
          sources: sources,
          findingTitle: findingTitle,
          findingContent: findingContent,
        ));

    String? fatalError;
    var hadErrorStop = false;

    for (var turn = 1; turn <= budget; turn++) {
      if (cancelled()) {
        emit('stopped', 'Stopped at turn $turn.', turn: turn);
        break;
      }

      // 1 — the model picks the next query, from a DIFFERENT angle. If it
      // comes back too similar to a facet already covered, retry (pushing it
      // toward a new facet) a couple of times rather than stopping the whole
      // run on the first near-duplicate.
      emit('query', 'Turn $turn: choosing a fresh angle…', turn: turn);
      var query = '';
      var gotNovel = false;
      String? avoidHint;
      for (var attempt = 0; attempt < 3 && !gotNovel; attempt++) {
        String rawQuery;
        try {
          rawQuery = await think(
            system: ResearchAgent.querySystemPrompt(),
            user: ResearchAgent.queryUserPrompt(
              goal: goal,
              priorQueries: priorQueries,
              coveredTitles: coveredTitles,
              turn: turn,
              budget: budget,
              avoidHint: avoidHint,
            ),
            temperature: queryTemperature + attempt * 0.2, // loosen on retry
            maxTokens: queryMaxTokens,
            taskId: 'research-query-$turn-$attempt',
          );
        } catch (e) {
          fatalError = 'The model failed while choosing a query: $e';
          hadErrorStop = true;
          emit('error', fatalError, turn: turn);
          break;
        }
        final candidate = ResearchAgent.parseQuery(rawQuery);
        if (candidate.isEmpty) {
          avoidHint = 'give an actual search query';
          continue;
        }
        if (ResearchAgent.isNovelAngle(candidate, priorQueries)) {
          query = candidate;
          gotNovel = true;
        } else {
          avoidHint =
              'it overlapped "$candidate" — switch to a clearly different facet';
        }
      }
      if (hadErrorStop) break;
      if (!gotNovel) {
        emit('done',
            'Turn $turn: no genuinely new angle left — wrapping up.',
            turn: turn);
        break;
      }
      priorQueries.add(query);

      // 2 — real web search.
      if (cancelled()) break;
      emit('search', 'Turn $turn: searching “$query”…',
          turn: turn, query: query);
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
      final sourceLines = [
        for (final h in result.hits)
          (h.title.trim().isNotEmpty ? h.title.trim() : h.url) +
              (h.url.trim().isNotEmpty ? ' — ${h.url.trim()}' : ''),
      ];
      if (result.hits.isEmpty) {
        emit('search', 'Turn $turn: no results for “$query”.',
            turn: turn, query: query);
        continue;
      }
      emit('search', 'Turn $turn: ${result.hits.length} results for “$query”.',
          turn: turn, query: query, sources: sourceLines);

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

      // 4 — summarize the fenced data (the caller's think fn streams this live).
      if (cancelled()) break;
      emit('summarize',
          'Turn $turn: reading & summarizing ${result.hits.length} sources…',
          turn: turn, query: query, sources: sourceLines);
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
      var parsed = ResearchAgent.parseSummary(rawSummary, query: query);
      // A title-only or empty reply is a non-finding. Retry once nudging for a
      // real body; if still basically empty, skip rather than store blank.
      if (parsed.content.trim().length < 40) {
        try {
          final retryRaw = await think(
            system: ResearchAgent.summarySystemPrompt(),
            user: '${ResearchAgent.summaryUserPrompt(goal: goal, query: query, fencedBlocks: fenced)}'
                '\n\n(Your previous answer had no body. Write the TITLE line '
                'and then a full paragraph of the actual findings.)',
            temperature: summaryTemperature + 0.1,
            maxTokens: summaryMaxTokens,
            taskId: 'research-summary-$turn-retry',
          );
          final retry = ResearchAgent.parseSummary(retryRaw, query: query);
          if (retry.content.trim().length > parsed.content.trim().length) {
            parsed = retry;
          }
        } catch (_) {/* keep the first attempt */}
      }
      if (parsed.content.trim().length < 15) {
        emit('summarize',
            'Turn $turn: couldn\'t extract a usable summary — skipping.',
            turn: turn, query: query);
        continue; // never store an empty finding
      }
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
      coveredTitles.add(parsed.title);
      emit(
        'store',
        'Turn $turn: stored “${parsed.title}” from ${result.hits.length} '
            'source(s)${injectionSeen ? ' · injection blocked' : ''}.',
        turn: turn,
        query: query,
        sources: sourceLines,
        findingTitle: parsed.title,
        findingContent: content,
      );
    }

    // 6 — synthesis (the capstone): read ALL findings together and surface the
    // deeper, non-obvious connections across them — NOT a recap. Needs at
    // least two findings for there to be anything to connect. Streamed live.
    String? synthesis;
    if (!hadErrorStop && !cancelled() && collected.length >= 2) {
      emit('synthesize',
          'Synthesizing ${collected.length} findings — hunting for deeper '
          'connections…',
          turn: turnsUsed);
      try {
        final raw = await think(
          system: ResearchAgent.synthesisSystemPrompt(),
          user: ResearchAgent.synthesisUserPrompt(
            goal: goal,
            titles: [for (final c in collected) c.title],
            contents: [for (final c in collected) c.content],
          ),
          temperature: 0.5,
          maxTokens: 1024,
          taskId: 'research-synthesis',
        );
        final s = raw.trim();
        if (s.isNotEmpty) synthesis = s;
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
      synthesis: synthesis,
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
