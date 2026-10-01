import 'dart:async';

import 'package:get/get.dart';

import '../../services/embedding_service.dart';
import '../../services/llm_service.dart';
import '../../services/log_service.dart';
import '../../services/pipeline_status_service.dart';
import '../cognition/attribution.dart';
import '../cognition/uncertainty.dart';
import '../params/parameters_service.dart';
import 'eidetic_memory_engine.dart';
import 'eidetic_store.dart' show tokenizeQuery;
import 'memory_manager.dart';
import 'memory_records.dart';
import 'recall_ranker.dart';

/// Kind of memory operation, for the visible call log.
enum MemoryCallType { recall, remember, consolidate }

/// One recorded memory operation — surfaced in the Memory Panel's Activity tab
/// and in the app log, so every call the app makes is visible.
class MemoryCall {
  final MemoryCallType type;
  final String summary;
  final DateTime at;
  MemoryCall(this.type, this.summary) : at = DateTime.now();
}

/// The single entry point every mode uses to touch memory.
///
/// Each turn performs two explicit, logged calls:
///  * [remembering] (RECALL) — pull relevant long-term facts into context
///    before the model generates.
///  * [rememberTurn] (REMEMBER) — write the turn to the episodic ledger after,
///    then opportunistically run the gated consolidation.
///
/// Both recall and the episodic write are fast local DB operations, so they run
/// every turn without waking the model. Model-based fact extraction stays in
/// the gated [MemoryManager] pass so long-term memory is not poisoned and the
/// GPU is not kept hot — consistent with the offline-memory design.
class MemoryService extends GetxService {
  MemoryService({EideticMemoryEngine? memory, MemoryManager? manager})
      : _memory = memory ?? Get.find<EideticMemoryEngine>(),
        _manager = manager ?? Get.find<MemoryManager>();

  final EideticMemoryEngine _memory;
  final MemoryManager _manager;

  /// Reviewable history of recent memory calls (newest first).
  final recentCalls = <MemoryCall>[].obs;
  static const _maxCalls = 60;

  /// Turns since the last adaptive-decay sweep (Phase 3). Decay is batched
  /// every `decay.applyEveryCycles` turns rather than run each turn — cheaper,
  /// and it's what the "Recompute every N cycles" knob means. Counted in-memory
  /// within a run; it resets on relaunch, so decay is slightly under-applied
  /// right after a cold start (an accepted Phase 3a simplification).
  int _turnsSinceDecay = 0;

  /// Successful consolidations since the agent last reflected on itself (2.0).
  /// Self-reflection is a model pass, so it runs only every N consolidations.
  int _consolidationsSinceReflect = 0;

  /// The most recent recall pass, for the chat UI's "recalled-memory chips" —
  /// what was pulled into context, by source, before the model spoke. Null
  /// until the first recall; carries an empty [RecallResult] when nothing was
  /// recalled (so the UI can hide cleanly).
  final lastRecall = Rxn<RecallResult>();

  /// The most recent turn's uncertainty score (Phase 4), computed from the
  /// recall pass. Drives System 1 vs System 2 gating and is surfaced in
  /// telemetry. Null when uncertainty gating is disabled (`u.enabled` off).
  final lastUncertainty = Rxn<UScore>();

  LogService? get _log {
    try {
      return Get.find<LogService>();
    } catch (_) {
      return null;
    }
  }

  ParametersService? get _params {
    try {
      return Get.find<ParametersService>();
    } catch (_) {
      return null;
    }
  }

  EmbeddingService? get _embeddings {
    try {
      return Get.find<EmbeddingService>();
    } catch (_) {
      return null;
    }
  }

  LlmService? get _llm {
    try {
      return Get.find<LlmService>();
    } catch (_) {
      return null;
    }
  }

  PipelineStatusService? get _status {
    try {
      return Get.find<PipelineStatusService>();
    } catch (_) {
      return null;
    }
  }

  /// True while the chat model is generating. Embedding runs on a *second*
  /// native engine, and loading/running it concurrently with chat generation
  /// crashes the process on-device — so every embedder call is gated on this.
  bool get _chatBusy => _llm?.isGenerating.value ?? false;

  /// Embed [ids]' claim text and store the vectors (best-effort; skips any that
  /// fail, and never runs while the chat model is generating). Used for
  /// newly-promoted claims and the backfill queue.
  Future<void> _embedAndStore(List<int> ids) async {
    final emb = _embeddings;
    if (emb == null || !emb.isReady.value || ids.isEmpty || _chatBusy) return;
    final facts = await _memory.factsByIds(ids);
    for (final f in facts) {
      // Yield the moment a chat turn begins: the embedder is a second native
      // engine and running it concurrently with chat generation crashes the
      // process. Re-checking each iteration keeps a long backfill cooperative —
      // it stops cleanly and the next idle pass resumes the remainder.
      if (_chatBusy) break;
      final id = f.id;
      if (id == null) continue;
      final v = await emb.embed(f.text);
      if (v != null && v.isNotEmpty) {
        await _memory.storeEmbedding(id, v, model: emb.loadedModelPath.value);
      }
    }
  }

  /// Embed every claim not yet in the meaning index (up to [max] this call), so
  /// meaning-based recall has something to match against. This is what makes
  /// "load the embedder ⇒ my existing memories become searchable by meaning"
  /// actually true — otherwise the index only fills incidentally, on chat
  /// consolidations, and a debate-only or load-late session never indexes its
  /// back catalogue. Best-effort and idle-only (never while the chat model is
  /// generating — a second live engine crashes on-device). Returns how many
  /// claims were newly embedded.
  Future<int> backfillEmbeddings({int max = 500}) async {
    final emb = _embeddings;
    if (emb == null || !emb.isReady.value || _chatBusy) return 0;
    final missing = await _memory.claimsMissingEmbedding(limit: max);
    final ids = missing.map((f) => f.id).whereType<int>().toList();
    if (ids.isEmpty) return 0;
    final before = await _memory.embeddingCount();
    await _embedAndStore(ids);
    final after = await _memory.embeddingCount();
    final added = after - before;
    if (added > 0) {
      _record(MemoryCallType.consolidate,
          'meaning index backfill → +$added embedded ($after total)');
    }
    return added;
  }

  void _record(MemoryCallType type, String summary) {
    recentCalls.insert(0, MemoryCall(type, summary));
    if (recentCalls.length > _maxCalls) {
      recentCalls.removeRange(_maxCalls, recentCalls.length);
    }
    final tag = switch (type) {
      MemoryCallType.recall => '🧠 REMEMBERING',
      MemoryCallType.remember => '💾 REMEMBER',
      MemoryCallType.consolidate => '🧩 CONSOLIDATE',
    };
    _log?.info('$tag · $summary', source: 'Memory');
  }

  static const _memoryEmptyNote =
      'You have a persistent memory across conversations; nothing specific is '
      'recorded for this yet.';

  /// RECALL — the associative recall engine. Builds a compact, budget-capped
  /// block of remembered context to inject before the model answers.
  ///
  /// It fuses candidates from every tier — the semantic claim graph (spreading
  /// activation, scored) and the raw episodic log (keyword search, cross-
  /// session) — deduplicates them, ranks by a blend of relevance × salience ×
  /// recency, and admits the top items until a character budget is spent (the
  /// context window is tiny). [recentContext] enriches the cue so recall tracks
  /// what the conversation is *about*, not just the last sentence. When
  /// `recall.memoryAwareness` is on, a one-line capability note is included so
  /// the model relies on memory instead of confabulating. Embedding-based
  /// (meaning) seeding plugs into this same pipeline in the next phase.
  Future<String> remembering(String query,
      {int k = 8, String recentContext = ''}) async {
    final kk = _params?.getInt('recall.k') ?? k;
    final awareness = _params?.getBool('recall.memoryAwareness') ?? true;
    String emptyResult() => awareness ? _memoryEmptyNote : '';

    if (kk <= 0) {
      _record(
          MemoryCallType.recall, 'query="${_short(query)}" → disabled (k=0)');
      lastRecall.value =
          const RecallResult(injected: [], embeddingsActive: false);
      lastUncertainty.value = null;
      return emptyResult();
    }

    // Cue: current message enriched with a little recent context.
    final cue =
        recentContext.trim().isEmpty ? query : '$query\n${recentContext.trim()}';

    final alpha = _params?.getDouble('spreading.alpha') ?? 0.85;
    final threshold = _params?.getDouble('spreading.threshold') ?? 0.15;
    final maxHops = _params?.getInt('spreading.maxHops') ?? 2;
    final seedK = _params?.getInt('spreading.seedK') ?? 10;
    final epiDepth = _params?.getInt('recall.episodicDepth') ?? 12;
    final charBudget = _params?.getInt('recall.charBudget') ?? 600;
    final wRel = _params?.getDouble('recall.wRelevance') ?? 0.6;
    final wSal = _params?.getDouble('recall.wSalience') ?? 0.25;
    final wRec = _params?.getDouble('recall.wRecency') ?? 0.15;
    final halfLife = _params?.getDouble('recall.recencyHalfLifeHours') ?? 72.0;

    // Meaning-based recall (Phase 2b): embed the cue only when an embedding
    // model has been explicitly loaded (Settings > Meaning-based Memory) and
    // the chat model is idle. The embedder is NEVER auto-loaded on the turn
    // path — spinning up a second native engine mid-turn, concurrently with
    // chat generation, crashes the process on-device. Recall stays on
    // keyword+graph seeding unless a model was loaded from Settings.
    List<double>? cueVec;
    if ((_embeddings?.isReady.value ?? false) && !_chatBusy) {
      cueVec = await _embeddings!.embed(cue);
    }
    final embSeedK = _params?.getInt('embeddings.seedK') ?? 10;
    final embThreshold = _params?.getDouble('embeddings.threshold') ?? 0.3;

    // Which claims were direct meaning matches (embedding nearest neighbours),
    // so recalled chips can show whether embeddings actually contributed.
    // Also capture two diagnostics so "0 meaning" is explainable rather than
    // mysterious: how many claims are actually indexed, and the BEST cosine the
    // cue scored against any of them (regardless of the seed threshold). A top
    // of exactly 0.00 with a non-empty index points at a dimension mismatch
    // (e.g. the embedder was swapped); a low-but-nonzero top means the 0.3
    // threshold is simply higher than this cue's real similarity.
    Set<int> embSeedIds = const {};
    int embIndexed = 0;
    double? embTop;
    if (cueVec != null && cueVec.isNotEmpty) {
      try {
        embIndexed = await _memory.embeddingCount();
        final scored = await _memory.nearestClaimsScored(cueVec,
            k: embSeedK, threshold: 0.0);
        if (scored.isNotEmpty) embTop = scored.first.score;
        embSeedIds =
            scored.where((e) => e.score >= embThreshold).map((e) => e.id).toSet();
      } catch (_) {}
    }

    List<({SemanticFact fact, double score})> semantic;
    List<EpisodicEntry> episodic;
    try {
      semantic = await _memory.recallSemanticScored(cue,
          k: kk,
          alpha: alpha,
          threshold: threshold,
          maxHops: maxHops,
          seedK: seedK,
          queryEmbedding: cueVec,
          embedSeedK: embSeedK,
          embedThreshold: embThreshold);
      episodic = await _memory.searchEpisodic(cue, limit: epiDepth);
    } catch (e) {
      _record(MemoryCallType.recall, 'query="${_short(query)}" → error: $e');
      lastRecall.value =
          const RecallResult(injected: [], embeddingsActive: false);
      lastUncertainty.value = null;
      return emptyResult();
    }

    final now = DateTime.now();
    final cueTokens = tokenizeQuery(cue).toSet();
    final candidates = <RecallCandidate>[];
    for (final s in semantic) {
      candidates.add(RecallCandidate(
        source: RecallSource.semantic,
        text: s.fact.text,
        relevance: s.score.clamp(0.0, 1.0).toDouble(),
        salience: s.fact.salience,
        timestamp: s.fact.createdUtc,
        dedupeKey: normalizeForDedupe(s.fact.text),
        viaEmbedding: s.fact.id != null && embSeedIds.contains(s.fact.id),
        factId: s.fact.id,
        subjectType: s.fact.subjectType,
        holder: s.fact.holder,
      ));
    }
    for (final e in episodic) {
      final text = _clip(e.content, 220);
      candidates.add(RecallCandidate(
        source: RecallSource.episodic,
        text: text,
        relevance: _overlap(cueTokens, e.content),
        salience: 0.4, // raw turns: useful but uncurated
        timestamp: e.timestampUtc,
        dedupeKey: normalizeForDedupe(text),
        // Raw snippets carry no resolved subject — render as neutral context,
        // never as an identity claim about anyone.
        subjectType: SubjectType.unknown,
      ));
    }

    final ranked = fuseAndRank(
      candidates,
      now: now,
      wRelevance: wRel,
      wSalience: wSal,
      wRecency: wRec,
      recencyHalfLifeHours: halfLife,
      charBudget: charBudget,
    ).take(kk).toList();

    // Publish for the recalled-memory chips (visible instantly, before the
    // slow model generates).
    final embOn = cueVec != null;
    final embMatches = ranked.where((c) => c.viaEmbedding).length;
    lastRecall.value = RecallResult(
      injected: ranked,
      embeddingsActive: embOn,
      embeddingIndexed: embIndexed,
      embeddingTop: embTop,
      cue: _short(query),
    );

    // Phase 3 — reinforcement: injecting a claim IS a retrieval event, and
    // retrieval strengthens memory (the testing effect). Fire-and-forget so it
    // never sits on the turn's critical path; it only touches the claims we
    // actually surfaced this turn.
    _reinforceRecalled(ranked);

    // Phase 4 — uncertainty: score how much to trust the fast answer vs. think
    // harder this turn, from how well memory covered it. Published for the
    // System 1/2 gate and telemetry; costs no inference.
    _scoreUncertainty(query, semantic);

    // Diagnostics make "0 meaning" explainable at a glance:
    //   idx N  — claims that actually have an embedding (0 ⇒ nothing indexed yet)
    //   top X  — best cosine the cue scored vs any claim, threshold aside
    //            (0.00 with idx>0 ⇒ dimension mismatch; low ⇒ threshold too high)
    final embInfo = embOn
        ? ' · emb on ($embMatches meaning · idx $embIndexed'
            '${embTop != null ? ' · top ${embTop!.toStringAsFixed(2)}' : ''})'
        : '';
    _record(MemoryCallType.recall,
        'cue="${_short(query)}" → sem ${semantic.length}, epi ${episodic.length}, injected ${ranked.length}$embInfo');

    // Open questions (2.0): surface a noticed contradiction when this turn
    // actually touched the conflicted claims, or when the user asks about the
    // state of memory ("do you have anything unresolved?"). Best-effort.
    var openQ = const <String>[];
    if (_params?.getBool('reconcile.enabled') ?? true) {
      final injectedFactIds =
          ranked.map((c) => c.factId).whereType<int>().toSet();
      final metaQuery = _looksLikeMemoryMetaQuery(query);
      try {
        final all = await _memory.openQuestions(limit: 20);
        openQ = all
            .where((q) => metaQuery || q.claimIds.any(injectedFactIds.contains))
            .take(3)
            .map((q) => q.question)
            .toList();
      } catch (_) {}
    }

    if (ranked.isEmpty && openQ.isEmpty) return emptyResult();

    // Identity-safe rendering (Phase 5) + noticed contradictions (2.0): bucket
    // by subject/holder so a fact about the user can never be read as a fact
    // about the AI itself, and append any open questions to raise.
    return renderMemoryBlock(
      [
        for (final c in ranked)
          MemoryLine(c.text, subjectType: c.subjectType, holder: c.holder),
      ],
      awareness: awareness,
      openQuestions: openQ,
    );
  }

  static final _metaQueryCue = RegExp(
    r"\b(unresolved|unsure|uncertain|not sure|conflict|contradict|"
    r"contradiction|mixed up|confus|which is right|remember correctly|"
    r"open questions?|get .* (right|wrong)|clarif)\w*",
    caseSensitive: false,
  );

  /// Whether the user is asking about the STATE of memory (so we should surface
  /// open questions regardless of topical match).
  bool _looksLikeMemoryMetaQuery(String q) => _metaQueryCue.hasMatch(q);

  /// Fraction of cue tokens present in [content] (0..1) — episodic relevance.
  double _overlap(Set<String> cueTokens, String content) {
    if (cueTokens.isEmpty) return 0.0;
    final ct = tokenizeQuery(content).toSet();
    if (ct.isEmpty) return 0.0;
    var hit = 0;
    for (final t in cueTokens) {
      if (ct.contains(t)) hit++;
    }
    return (hit / cueTokens.length).clamp(0.0, 1.0).toDouble();
  }

  String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  /// REMEMBER a single entry to episodic memory. Logged as a call.
  Future<int?> remember({
    required String sessionId,
    required String role,
    required String content,
    EpisodicKind kind = EpisodicKind.turn,
  }) async {
    if (content.trim().isEmpty) return null;
    final id = await _memory.record(
        sessionId: sessionId, kind: kind, role: role, content: content);
    _record(MemoryCallType.remember,
        '$role → episodic #$id (${content.length} chars)');
    // Every episodic write is also mirrored to the grounded event log. This is
    // the live chat path (the controller records user and assistant turns
    // through remember), so this is what makes the event log populate at all.
    await _appendMessageEvent(role, content);
    return id;
  }

  /// Map an episodic role to an event (source, type) pair.
  static (String, String) _eventKindForRole(String role) {
    switch (role) {
      case 'user':
        return ('user', 'user_message');
      case 'assistant':
        return ('assistant', 'assistant_message');
      default:
        return ('system', 'system_message');
    }
  }

  /// Append one message to the grounded, append-only event log (best-effort;
  /// gated by the `events.enabled` parameter). Returns the new event id, or null
  /// if disabled/empty/failed. Never throws — the log is a passive record and
  /// must not fail a turn.
  Future<int?> _appendMessageEvent(String role, String content,
      {List<int> parents = const []}) async {
    if (!(_params?.getBool('events.enabled') ?? true)) return null;
    if (content.trim().isEmpty) return null;
    try {
      final (source, type) = _eventKindForRole(role);
      return await _memory.appendEvent(
        source: source,
        type: type,
        payload: {'chars': content.length, 'preview': _short(content)},
        parents: parents,
      );
    } catch (_) {
      return null;
    }
  }

  /// REMEMBER both sides of a chat turn, then opportunistically consolidate.
  Future<void> rememberTurn({
    required String sessionId,
    required String userText,
    required String aiText,
  }) async {
    int? userId;
    int? aiId;
    if (userText.trim().isNotEmpty) {
      userId = await _memory.record(
          sessionId: sessionId,
          kind: EpisodicKind.turn,
          role: 'user',
          content: userText);
    }
    if (aiText.trim().isNotEmpty) {
      aiId = await _memory.record(
          sessionId: sessionId,
          kind: EpisodicKind.turn,
          role: 'assistant',
          content: aiText);
    }
    _record(MemoryCallType.remember,
        'turn stored → episodic user#${userId ?? '-'} ai#${aiId ?? '-'}');
    // Grounded event log: assistant event links back to the user event.
    final userEv = await _appendMessageEvent('user', userText);
    await _appendMessageEvent('assistant', aiText,
        parents: userEv == null ? const [] : [userEv]);
    unawaited(_maybeConsolidate());
    // Adaptive decay (Phase 3): advance the cadence; sweeps every N turns.
    _maybeDecay();
  }

  /// Public opportunistic-consolidation trigger (gated; no-op when idle).
  Future<void> maybeConsolidate() => _maybeConsolidate();

  Future<void> _maybeConsolidate() async {
    try {
      if (!await _manager.hasPendingWork()) return;
      _status?.begin(PipelinePhase.consolidating, 'curating memories…');
      final result = await _manager.consolidatePending();
      if (result.ran) {
        _record(MemoryCallType.consolidate,
            'reviewed ${result.considered} · +${result.promoted} stored · ${result.deduped} dup · ${result.relationsAdded} links');
        _status?.mark(
            'consolidated · +${result.promoted} facts · ${result.relationsAdded} links');
        if (_params?.getBool('events.enabled') ?? true) {
          try {
            final eventId = await _memory.appendEvent(
              source: 'memory',
              type: 'consolidate',
              payload: {
                'considered': result.considered,
                'promoted': result.promoted,
                'deduped': result.deduped,
                'relations': result.relationsAdded,
              },
            );
            // Provenance: link each new claim to the consolidation event it came
            // from, which in turn links back to the episodic batch.
            for (final factId in result.promotedFactIds) {
              await _memory.addProvenance(factId, eventId);
            }
          } catch (_) {}
        }
        // Meaning index (Phase 2b): embed the new claims, then chip away at the
        // backfill so recall's embedding seeds stay current. Best-effort; runs
        // only when an embedder is loaded AND the chat model is idle (never
        // concurrently with generation — that crashes the second engine).
        if ((_embeddings?.isReady.value ?? false) && !_chatBusy) {
          try {
            _status?.begin(PipelinePhase.embedding, 'indexing new facts…');
            await _embedAndStore(result.promotedFactIds);
            final perPass = _params?.getInt('embeddings.backfillPerPass') ?? 16;
            if (perPass > 0) {
              final missing =
                  await _memory.claimsMissingEmbedding(limit: perPass);
              await _embedAndStore(
                  missing.map((f) => f.id).whereType<int>().toList());
            }
            _status?.mark('meaning index updated');
          } catch (_) {}
        }

        // Self-reflection (2.0): every N consolidations, the agent forms a few
        // tentative observations about itself (the holder=assistant self-view).
        // Best-effort, idle-only (it's a model pass), gated by reflect.enabled.
        if ((_params?.getBool('reflect.enabled') ?? true) && !_chatBusy) {
          _consolidationsSinceReflect++;
          final every = _params?.getInt('reflect.everyConsolidations') ?? 3;
          if (every > 0 && _consolidationsSinceReflect >= every) {
            _consolidationsSinceReflect = 0;
            try {
              _status?.begin(PipelinePhase.consolidating, 'reflecting…');
              final n = await _manager.reflectOnSelf();
              if (n > 0) {
                _record(MemoryCallType.consolidate,
                    'self-reflection · +$n observation(s) about myself');
              }
            } catch (_) {}
          }
        }
      }
      _finishStatus();
    } catch (_) {
      // Consolidation is best-effort; never surface as a turn failure.
      _finishStatus();
    }
  }

  // ── Uncertainty / System 1–2 gating (Phase 4) ───────────────

  /// Compute this turn's U-score from the recall pass and publish it. Pure
  /// proxy signals (no extra inference): how strongly memory matched the query
  /// (prediction), how little is known about the topic (novelty), how
  /// terse/underspecified the query is (ambiguity, coarse), whether any
  /// recalled claim is in an unresolved contradiction, and a coarse risk
  /// keyword scan. Gated by `u.enabled`. See `cognition/uncertainty.dart`.
  void _scoreUncertainty(
      String query, List<({SemanticFact fact, double score})> semantic) {
    if (!(_params?.getBool('u.enabled') ?? true)) {
      lastUncertainty.value = null;
      return;
    }

    // Prediction error: strongest semantic match this turn (1 ⇒ nothing close
    // — the input wasn't anticipated by anything in memory).
    final topRel = semantic.isEmpty
        ? 0.0
        : semantic
            .map((s) => s.score)
            .reduce((a, b) => a > b ? a : b)
            .clamp(0.0, 1.0)
            .toDouble();
    final prediction = 1.0 - topRel;

    // Novelty: how little the topic is represented in memory at all.
    final novelty = semantic.isEmpty ? 1.0 : 1.0 / (1.0 + semantic.length);

    // Ambiguity (coarse): a terse/underspecified query could mean many things.
    final tokenCount = tokenizeQuery(query).length;
    final ambiguity = (1.0 - tokenCount / 6.0).clamp(0.0, 1.0).toDouble();

    // Contradiction: fraction of recalled claims flagged as in an unresolved
    // contradiction. ~0 until the Dempster–Shafer resolution engine (ds.*)
    // starts marking claims ambiguous — the signal is wired now, ready for it.
    var contradiction = 0.0;
    if (semantic.isNotEmpty) {
      final amb =
          semantic.where((s) => s.fact.status == ClaimStatus.ambiguous).length;
      contradiction = (amb / semantic.length).clamp(0.0, 1.0).toDouble();
    }

    final weights = UScoreWeights(
      prediction: _params?.getDouble('u.wPrediction') ?? 0.25,
      contradiction: _params?.getDouble('u.wContradiction') ?? 0.20,
      novelty: _params?.getDouble('u.wNovelty') ?? 0.15,
      ambiguity: _params?.getDouble('u.wAmbiguity') ?? 0.15,
      risk: _params?.getDouble('u.wRisk') ?? 0.25,
    );
    final threshold = _params?.getDouble('u.threshold') ?? 0.65;

    final score = scoreUncertainty(
      UScoreInputs(
        prediction: prediction,
        contradiction: contradiction,
        novelty: novelty,
        ambiguity: ambiguity,
        risk: _riskProxy(query),
      ),
      weights,
      threshold,
    );
    lastUncertainty.value = score;
    _record(MemoryCallType.recall, score.breakdown);
  }

  /// A few high-stakes topics that justify extra care. A deliberate coarse
  /// first pass — NOT a safety guarantee — it only nudges the turn toward
  /// careful reasoning, which is always harmless.
  static const _riskKeywords = <String>[
    'suicide', 'overdose', 'dose', 'dosage', 'medication', 'poison',
    'allergic', 'bleeding', 'emergency', 'lawsuit', 'legal', 'contract',
    'diagnosis', 'symptom',
  ];

  /// Coarse risk proxy: 0.6 if the query mentions a high-stakes topic, else 0.
  double _riskProxy(String query) {
    final q = query.toLowerCase();
    for (final k in _riskKeywords) {
      if (q.contains(k)) return 0.6;
    }
    return 0.0;
  }

  // ── Adaptive dynamics (Phase 3 — decay + reinforcement) ─────

  /// Reinforce the claims this recall actually injected. Best-effort and
  /// fire-and-forget (a fast local batch update, no model). Gated by
  /// `decay.enabled`; `decay.alpha` sets the strength (0 ⇒ no reinforcement).
  void _reinforceRecalled(List<RecallCandidate> injected) {
    if (!(_params?.getBool('decay.enabled') ?? true)) return;
    final alpha = _params?.getDouble('decay.alpha') ?? 2.0;
    if (alpha <= 0) return;
    final ids = injected
        .where((c) => c.source == RecallSource.semantic && c.factId != null)
        .map((c) => c.factId!)
        .toList();
    if (ids.isEmpty) return;
    unawaited(() async {
      try {
        final n = await _memory.reinforceClaims(ids, alpha: alpha);
        if (n > 0) {
          _record(MemoryCallType.recall,
              'reinforced $n recalled ${n == 1 ? 'memory' : 'memories'}');
        }
      } catch (_) {}
    }());
  }

  /// Advance the decay cadence by one turn and, once `decay.applyEveryCycles`
  /// turns have elapsed, fire one forgetting sweep across memory so recall
  /// order tracks what's actually used over time. Fire-and-forget: a fast local
  /// batch update that never blocks the turn.
  void _maybeDecay() {
    if (!(_params?.getBool('decay.enabled') ?? true)) return;
    final everyN = _params?.getInt('decay.applyEveryCycles') ?? 60;
    if (everyN <= 0) return;
    _turnsSinceDecay++;
    if (_turnsSinceDecay < everyN) return;
    final elapsed = _turnsSinceDecay;
    _turnsSinceDecay = 0;
    final tau = (_params?.getInt('decay.tauBaseCycles') ?? 3600).toDouble();
    final beta = _params?.getDouble('decay.beta') ?? 1.0;
    unawaited(() async {
      try {
        final n = await _memory.decayAllSalience(
            cyclesElapsed: elapsed.toDouble(), tau: tau, beta: beta);
        if (n > 0) {
          _record(MemoryCallType.consolidate,
              'decay sweep · faded $n ${n == 1 ? 'memory' : 'memories'} (every $everyN turns, τ=${tau.toStringAsFixed(0)})');
        }
      } catch (_) {}
    }());
  }

  /// Clear the status back to idle, but only if this background pass still owns
  /// it (phase is consolidating/embedding). A live chat turn that started
  /// meanwhile has taken the status over — never clobber it.
  void _finishStatus() {
    final s = _status;
    if (s == null) return;
    if (s.phase.value == PipelinePhase.consolidating ||
        s.phase.value == PipelinePhase.embedding) {
      s.done();
    }
  }

  String _short(String s) => s.length <= 48 ? s : '${s.substring(0, 48)}…';
}
