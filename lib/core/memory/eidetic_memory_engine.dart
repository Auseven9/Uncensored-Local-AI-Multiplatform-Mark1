import 'dart:math';

import 'package:get/get.dart';

import '../../services/log_service.dart';
import 'eidetic_store.dart';
import 'event_records.dart';
import 'memory_records.dart';
import 'spreading_activation.dart';
import 'vector_search.dart';

/// A random, per-launch session id. Groups events produced by one app run so
/// gaps *between* runs are visible in the log.
String _newSessionId() {
  final t = DateTime.now().microsecondsSinceEpoch;
  final r = Random().nextInt(0x7fffffff);
  return '${t.toRadixString(36)}-${r.toRadixString(36)}';
}

/// An item held in the ephemeral working tier (the live context window).
class WorkingMemoryItem {
  final String role;
  final String content;
  final DateTime at;
  WorkingMemoryItem(this.role, this.content) : at = DateTime.now();
}

/// The Eidetic three-tier local memory stack.
///
/// This is the "notebook", deliberately decoupled from the "brain"
/// ([InferenceWorker]). Nothing here keeps the model hot: tiers are plain
/// local storage, and inference happens only when a caller (the memory gate,
/// the arena, a user turn) explicitly asks for it.
///
///  * **Working** — [pushWorking]/[clearWorking]: the active context, held in
///    RAM and wiped when a response completes.
///  * **Episodic** (short-term) — a millisecond-timestamped SQLite ledger of
///    every turn, tool call, tool result, reflection and error.
///  * **Semantic** (long-term) — curated facts/preferences/rules that persist
///    across reboots, written *only* through the gate so the store does not
///    fill with noise ("database poisoning").
///
/// On the web, where sqflite is unavailable, the episodic/semantic tiers fall
/// back to an in-memory store (see [EideticStore.isPersistent]).
class EideticMemoryEngine extends GetxService {
  final EideticStore _store;

  EideticMemoryEngine({EideticStore? store})
      : _store = store ?? createEideticStore();

  bool _initialized = false;

  // ── Grounding clocks (Phase 1) ──────────────────────────────
  // Two independent clocks captured at construction (≈ app launch). Their
  // divergence is the ground-truth temporal signal: see [snapshot].
  final String _sessionId = _newSessionId();
  final Stopwatch _uptime = Stopwatch()..start();
  final DateTime _sessionStartWall = DateTime.now().toUtc();

  /// This app run's session id (stable for the process lifetime).
  String get sessionId => _sessionId;

  /// True once the backing store is open and queryable.
  final isReady = false.obs;

  /// Number of episodic rows not yet consolidated into semantic memory.
  final episodicPending = 0.obs;

  final List<WorkingMemoryItem> _working = [];

  LogService? get _log {
    try {
      return Get.find<LogService>();
    } catch (_) {
      return null;
    }
  }

  /// Idempotent initialisation. Named `init` to match the app's other
  /// services, and safe to call again (subsequent calls are no-ops).
  Future<EideticMemoryEngine> init() async {
    if (_initialized) return this;
    await _store.initialize();
    _initialized = true;
    isReady.value = true;
    await _refreshPending();
    // Mark this launch in the grounded event log (best-effort).
    try {
      await appendEvent(source: 'system', type: 'app_launch', payload: {
        'persistent': _store.isPersistent,
      });
    } catch (_) {}
    _log?.info(
      'Eidetic memory ready (persistent=${_store.isPersistent})',
      source: 'Memory',
    );
    return this;
  }

  // ── Event log (append-only grounded spine) ──────────────────

  /// A fresh grounding snapshot for the current instant. [clockSkewMs] is the
  /// difference between the wall clock now and where the wall clock *would* be
  /// if only monotonic uptime had elapsed since session start — non-zero when
  /// the process was frozen (backgrounded/suspended) or the wall clock jumped.
  SensorAnchor snapshot() {
    final now = DateTime.now().toUtc();
    final mono = _uptime.elapsedMilliseconds;
    final expected = _sessionStartWall.add(Duration(milliseconds: mono));
    final skew = now.difference(expected).inMilliseconds;
    // battery/GPS are captured only once sensor grounding is switched on
    // (`ground.sensorsEnabled`) and a sensor plugin is added; null until then.
    return SensorAnchor(
      wallClockUtc: now,
      monotonicMs: mono,
      sessionId: _sessionId,
      clockSkewMs: skew,
    );
  }

  /// Append one immutable, sensor-anchored event. Returns its row id.
  Future<int> appendEvent({
    required String source,
    required String type,
    Map<String, dynamic> payload = const {},
    List<int> parents = const [],
  }) async {
    await _ensureInit();
    return _store.appendEvent(AppEvent(
      timestampUtc: DateTime.now().toUtc(),
      source: source,
      type: type,
      payload: payload,
      parentEventIds: parents,
      anchor: snapshot(),
    ));
  }

  Future<List<AppEvent>> recentEvents({int limit = 100}) async {
    await _ensureInit();
    return _store.recentEvents(limit: limit);
  }

  Future<int> eventCount() async {
    await _ensureInit();
    return _store.eventCount();
  }

  // ── Epistemic graph + spreading-activation recall (Phase 2) ──

  Future<int> addEdge(RelationEdge edge) async {
    await _ensureInit();
    return _store.addEdge(edge);
  }

  Future<List<RelationEdge>> allEdges() async {
    await _ensureInit();
    return _store.allEdges();
  }

  Future<void> addProvenance(int factId, int eventId) async {
    await _ensureInit();
    await _store.addProvenance(factId, eventId);
  }

  /// Keyword search over the raw episodic log (all sessions), for the hybrid
  /// recall engine's episodic tier.
  Future<List<EpisodicEntry>> searchEpisodic(String query,
      {int limit = 20}) async {
    await _ensureInit();
    return _store.searchEpisodic(query, limit: limit);
  }

  /// Graph-aware recall that keeps each claim's activation score, for the hybrid
  /// recall ranker: keyword hits seed a spreading-activation pass over the
  /// relation edges, so related claims surface even when they don't lexically
  /// match [query]. Returns empty when there are no seeds.
  ///
  /// When [queryEmbedding] is supplied (Phase 2b), the claims whose stored
  /// embeddings are nearest by cosine are unioned into the seed set alongside
  /// the keyword hits — so a claim close in *meaning* seeds activation even
  /// with no lexical overlap. Omitting it leaves recall on pure keyword+graph
  /// seeding, so this is strictly additive.
  Future<List<({SemanticFact fact, double score})>> recallSemanticScored(
    String query, {
    int k = 8,
    double alpha = 0.85,
    double threshold = 0.15,
    int maxHops = 2,
    int seedK = 10,
    List<double>? queryEmbedding,
    int embedSeedK = 10,
    double embedThreshold = 0.0,
  }) async {
    await _ensureInit();
    final seeds = await _store.searchFacts(query, limit: seedK);
    final seedMap = <int, double>{
      for (final f in seeds)
        if (f.id != null) f.id!: 1.0,
    };
    // Meaning-based seeds: union nearest-by-embedding claims into the seeds.
    if (queryEmbedding != null && queryEmbedding.isNotEmpty) {
      final nearIds = await nearestClaimIds(queryEmbedding,
          k: embedSeedK, threshold: embedThreshold);
      for (final id in nearIds) {
        seedMap[id] = 1.0;
      }
    }
    if (seedMap.isEmpty) return const [];

    final edges = await _store.allEdges();
    final result = spreadActivation(
      seeds: seedMap,
      edges: edges,
      alpha: alpha,
      threshold: threshold,
      maxHops: maxHops,
    );
    final ranked = result.ranked();
    if (ranked.isEmpty) return const [];

    final topIds = ranked.take(k).toList();
    final facts = await _store.factsByIds(topIds);
    final byId = {for (final f in facts) f.id: f};
    // Re-apply activation order and drop superseded claims.
    final out = <({SemanticFact fact, double score})>[];
    for (final id in topIds) {
      final f = byId[id];
      if (f != null && f.status != ClaimStatus.superseded) {
        out.add((fact: f, score: result.scores[id] ?? 0.0));
      }
    }
    return out;
  }

  /// Fact-only spreading-activation recall (kept for existing callers/tests).
  Future<List<SemanticFact>> recallByActivation(
    String query, {
    int k = 8,
    double alpha = 0.85,
    double threshold = 0.15,
    int maxHops = 2,
    int seedK = 10,
  }) async {
    final scored = await recallSemanticScored(query,
        k: k,
        alpha: alpha,
        threshold: threshold,
        maxHops: maxHops,
        seedK: seedK);
    return scored.map((e) => e.fact).toList();
  }

  // ── Embeddings (Phase 2b — meaning-based recall) ────────────

  /// Store (or replace) a claim's embedding vector.
  Future<void> storeEmbedding(int factId, List<double> vector,
      {String? model}) async {
    await _ensureInit();
    await _store.upsertEmbedding(factId, vector, model: model);
  }

  /// The [k] claim ids whose stored embeddings are most similar to
  /// [queryVector] by cosine — the meaning-based seeds for recall. Returns
  /// empty when the query is empty or nothing is embedded yet, so callers fall
  /// back cleanly to keyword seeding.
  Future<List<int>> nearestClaimIds(
    List<double> queryVector, {
    int k = 10,
    double threshold = 0.0,
  }) async {
    await _ensureInit();
    if (queryVector.isEmpty) return const [];
    final corpus = await _store.allEmbeddings();
    if (corpus.isEmpty) return const [];
    return nearestByCosine(
      query: queryVector,
      corpus: corpus,
      k: k,
      threshold: threshold,
    ).map((e) => e.id).toList();
  }

  /// How many claims currently have an embedding (for diagnostics / backfill).
  Future<int> embeddingCount() async {
    await _ensureInit();
    return (await _store.allEmbeddings()).length;
  }

  /// Fetch claims by id (e.g. to read their text for embedding).
  Future<List<SemanticFact>> factsByIds(List<int> ids) async {
    await _ensureInit();
    return _store.factsByIds(ids);
  }

  /// Claims that don't yet have an embedding — the backfill queue, newest
  /// first, capped at [limit]. Empty once every claim is indexed.
  Future<List<SemanticFact>> claimsMissingEmbedding({int limit = 50}) async {
    await _ensureInit();
    final have = (await _store.allEmbeddings()).keys.toSet();
    final facts = await _store.recentFacts(limit: 1000);
    final missing = <SemanticFact>[];
    for (final f in facts) {
      if (f.id != null && !have.contains(f.id)) {
        missing.add(f);
        if (missing.length >= limit) break;
      }
    }
    return missing;
  }

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  bool get isPersistent => _store.isPersistent;

  // ── Working tier (ephemeral) ────────────────────────────────

  void pushWorking(String role, String content) =>
      _working.add(WorkingMemoryItem(role, content));

  List<WorkingMemoryItem> get working => List.unmodifiable(_working);

  /// Wipe the active context window — called when a response completes.
  void clearWorking() => _working.clear();

  // ── Episodic tier (short-term) ──────────────────────────────

  /// Append one entry to the chronological ledger. Returns its row id.
  Future<int> record({
    required String sessionId,
    required EpisodicKind kind,
    required String role,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    await _ensureInit();
    final sequence = await _store.nextSequence(sessionId);
    final id = await _store.insertEpisodic(EpisodicEntry(
      sessionId: sessionId,
      timestampUtc: DateTime.now().toUtc(),
      sequence: sequence,
      kind: kind,
      role: role,
      content: content,
      metadata: metadata,
    ));
    await _refreshPending();
    return id;
  }

  Future<int> recordTurn(String sessionId, String role, String content) =>
      record(
          sessionId: sessionId,
          kind: EpisodicKind.turn,
          role: role,
          content: content);

  Future<int> recordError(String sessionId, String message) => record(
      sessionId: sessionId,
      kind: EpisodicKind.error,
      role: 'system',
      content: message);

  Future<List<EpisodicEntry>> recentEpisodic(
      {String? sessionId, int limit = 50}) async {
    await _ensureInit();
    return _store.recentEpisodic(sessionId: sessionId, limit: limit);
  }

  Future<List<EpisodicEntry>> pendingEpisodic({int limit = 200}) async {
    await _ensureInit();
    return _store.pendingEpisodic(limit: limit);
  }

  Future<int> pendingCount() async {
    await _ensureInit();
    return _store.pendingCount();
  }

  Future<void> markConsolidated(List<int> ids) async {
    await _ensureInit();
    await _store.markConsolidated(ids);
    await _refreshPending();
  }

  // ── Semantic tier (long-term) ───────────────────────────────

  /// Persist one durable fact. Returns the new claim id, or null if it was
  /// deduplicated against an existing claim.
  Future<int?> rememberFact(SemanticFact fact) async {
    await _ensureInit();
    return _store.insertFact(fact);
  }

  /// Retrieve the [k] most relevant long-term facts for [query]
  /// (keyword-ranked today; cosine-ranked once embeddings are wired).
  Future<List<SemanticFact>> recall(String query, {int k = 8}) async {
    await _ensureInit();
    return _store.searchFacts(query, limit: k);
  }

  Future<List<SemanticFact>> recentFacts({int limit = 50}) async {
    await _ensureInit();
    return _store.recentFacts(limit: limit);
  }

  Future<int> factCount() async {
    await _ensureInit();
    return _store.factCount();
  }

  // ── Editing (memory panel) ──────────────────────────────────

  Future<void> updateFact(int id,
      {String? text, SemanticCategory? category, double? confidence}) async {
    await _ensureInit();
    await _store.updateFact(id,
        text: text, category: category, confidence: confidence);
  }

  Future<void> deleteFact(int id) async {
    await _ensureInit();
    await _store.deleteFact(id);
  }

  Future<void> updateEpisodicContent(int id, String content) async {
    await _ensureInit();
    await _store.updateEpisodicContent(id, content);
  }

  Future<void> deleteEpisodic(int id) async {
    await _ensureInit();
    await _store.deleteEpisodic(id);
    await _refreshPending();
  }

  Future<void> clearAll() async {
    await _ensureInit();
    await _store.clearAll();
    await _refreshPending();
  }

  Future<void> _refreshPending() async {
    episodicPending.value = await _store.pendingCount();
  }

  @override
  void onClose() {
    _store.close();
    super.onClose();
  }
}
