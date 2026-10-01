import 'event_records.dart';
import 'memory_dynamics.dart';
import 'memory_records.dart';

// Platform-specific factory. On native (dart:io present) this resolves to the
// SQLite-backed store; on the web it falls back to the in-memory store, which
// keeps the web build free of any sqflite/FFI imports.
import 'eidetic_store_web.dart'
    if (dart.library.io) 'eidetic_store_io.dart' as platform;

/// Persistence contract for the episodic + semantic tiers of Eidetic memory.
///
/// Two implementations exist: a SQLite-backed store for native platforms
/// (see `eidetic_store_io.dart`) and [InMemoryEideticStore] for the web and
/// for unit tests. Keeping this an interface lets the engine and its tests be
/// written once against a single API.
abstract class EideticStore {
  /// Whether writes survive a restart. False for the in-memory fallback.
  bool get isPersistent;

  Future<void> initialize();

  // ── Episodic (short-term) ──────────────────────────────────
  Future<int> nextSequence(String sessionId);
  Future<int> insertEpisodic(EpisodicEntry entry);
  Future<List<EpisodicEntry>> recentEpisodic({String? sessionId, int limit = 50});
  /// Keyword search across the raw episodic log (all sessions), newest first.
  /// Empty/too-short query falls back to the most recent entries.
  Future<List<EpisodicEntry>> searchEpisodic(String query, {int limit = 20});
  Future<List<EpisodicEntry>> pendingEpisodic({int limit = 200});
  Future<int> pendingCount();
  Future<void> markConsolidated(List<int> ids);

  // ── Semantic (long-term) ───────────────────────────────────
  /// Inserts a fact and returns its new row id, or null if a row with the same
  /// [SemanticFact.dedupeHash] already existed (deduplicated).
  Future<int?> insertFact(SemanticFact fact);
  Future<List<SemanticFact>> searchFacts(String query, {int limit = 8});
  Future<List<SemanticFact>> recentFacts({int limit = 50});
  Future<int> factCount();

  // ── Event log (append-only, grounded) ───────────────────────
  /// Append one immutable, sensor-anchored event. Returns its row id.
  Future<int> appendEvent(AppEvent event);
  Future<List<AppEvent>> recentEvents({int limit = 100});
  Future<int> eventCount();

  // ── Epistemic graph (Phase 2) ───────────────────────────────
  /// Add a directed relation edge between two claims. Returns its row id.
  Future<int> addEdge(RelationEdge edge);
  Future<List<RelationEdge>> allEdges();
  /// Record that a claim ([factId]) originated from an event ([eventId]).
  Future<void> addProvenance(int factId, int eventId);
  /// Fetch the claims (facts) with the given ids, in arbitrary order.
  Future<List<SemanticFact>> factsByIds(List<int> ids);

  // ── Embeddings (Phase 2b — meaning-based recall) ────────────
  /// Store (or replace) the embedding [vector] for a claim. [model] records
  /// which embedder produced it, so vectors can be invalidated if it changes.
  Future<void> upsertEmbedding(int factId, List<double> vector, {String? model});

  /// Load every stored claim embedding (id → vector) for brute-force
  /// nearest-neighbour recall. Cheap at this app's scale.
  Future<Map<int, List<double>>> allEmbeddings();

  /// Remove a claim's embedding (kept in step with the claim's own deletion).
  Future<void> deleteEmbedding(int factId);

  // ── Adaptive dynamics (Phase 3 — decay + reinforcement) ─────
  /// Reinforce the given claims after a recall actually used them: bump each
  /// claim's salience (retrieval strength) toward 1.0 and accrue a little
  /// confidence (storage strength), both scaled by [alpha] (`decay.alpha`).
  /// Returns how many claims were updated. A no-op when [ids] is empty or
  /// [alpha] <= 0. See `memory_dynamics.dart` for the exact curves.
  Future<int> reinforceClaims(List<int> ids, {required double alpha});

  /// Apply one Ebbinghaus forgetting step to every non-superseded claim's
  /// salience, relaxing each toward a per-claim permanence floor derived from
  /// its confidence and [beta] (`decay.beta`). [cyclesElapsed] and [tau]
  /// (`decay.tauBaseCycles`) set the rate. Returns how many claims actually
  /// changed. A no-op when [cyclesElapsed] or [tau] is non-positive.
  Future<int> decayAllSalience({
    required double cyclesElapsed,
    required double tau,
    required double beta,
  });

  // ── Editing (memory panel) ──────────────────────────────────
  /// Update a fact's fields; recomputes the dedupe hash when [text] changes.
  Future<void> updateFact(int id,
      {String? text, SemanticCategory? category, double? confidence});
  Future<void> deleteFact(int id);
  Future<void> updateEpisodicContent(int id, String content);
  Future<void> deleteEpisodic(int id);

  /// Wipe both tiers (destructive — used by the panel's "clear all").
  Future<void> clearAll();

  Future<void> close();
}

/// Builds the appropriate [EideticStore] for the current platform.
EideticStore createEideticStore() => platform.createEideticStore();

/// Splits [query] into lowercased search tokens (drops very short words).
List<String> tokenizeQuery(String query) {
  return query
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.length > 2)
      .toSet()
      .toList();
}

/// In-memory [EideticStore]. Used on the web (where sqflite is unavailable)
/// and in unit tests. Data lives only for the process lifetime.
class InMemoryEideticStore implements EideticStore {
  final List<EpisodicEntry> _episodic = [];
  final List<SemanticFact> _facts = [];
  final List<AppEvent> _events = [];
  final List<RelationEdge> _edges = [];
  final List<({int factId, int eventId})> _provenance = [];
  final Map<int, List<double>> _embeddings = {};
  int _autoId = 0;

  @override
  bool get isPersistent => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<int> nextSequence(String sessionId) async {
    var max = 0;
    for (final e in _episodic) {
      if (e.sessionId == sessionId && e.sequence > max) max = e.sequence;
    }
    return max + 1;
  }

  @override
  Future<int> insertEpisodic(EpisodicEntry entry) async {
    final id = ++_autoId;
    _episodic.add(EpisodicEntry(
      id: id,
      sessionId: entry.sessionId,
      timestampUtc: entry.timestampUtc,
      sequence: entry.sequence,
      kind: entry.kind,
      role: entry.role,
      content: entry.content,
      metadata: entry.metadata,
      consolidated: entry.consolidated,
    ));
    return id;
  }

  @override
  Future<List<EpisodicEntry>> recentEpisodic(
      {String? sessionId, int limit = 50}) async {
    final rows = _episodic
        .where((e) => sessionId == null || e.sessionId == sessionId)
        .toList()
      ..sort((a, b) => b.id!.compareTo(a.id!));
    return rows.take(limit).toList();
  }

  @override
  Future<List<EpisodicEntry>> searchEpisodic(String query,
      {int limit = 20}) async {
    final tokens = tokenizeQuery(query);
    final rows = [..._episodic]..sort((a, b) => b.id!.compareTo(a.id!));
    if (tokens.isEmpty) return rows.take(limit).toList();
    final matches = rows.where((e) {
      final t = e.content.toLowerCase();
      return tokens.any((tok) => t.contains(tok));
    }).toList();
    return matches.take(limit).toList();
  }

  @override
  Future<List<EpisodicEntry>> pendingEpisodic({int limit = 200}) async {
    final rows = _episodic.where((e) => !e.consolidated).toList()
      ..sort((a, b) => a.id!.compareTo(b.id!));
    return rows.take(limit).toList();
  }

  @override
  Future<int> pendingCount() async =>
      _episodic.where((e) => !e.consolidated).length;

  @override
  Future<void> markConsolidated(List<int> ids) async {
    final set = ids.toSet();
    for (var i = 0; i < _episodic.length; i++) {
      final e = _episodic[i];
      if (e.id != null && set.contains(e.id)) {
        _episodic[i] = EpisodicEntry(
          id: e.id,
          sessionId: e.sessionId,
          timestampUtc: e.timestampUtc,
          sequence: e.sequence,
          kind: e.kind,
          role: e.role,
          content: e.content,
          metadata: e.metadata,
          consolidated: true,
        );
      }
    }
  }

  @override
  Future<int?> insertFact(SemanticFact fact) async {
    if (_facts.any((f) => f.dedupeHash == fact.dedupeHash)) return null;
    final id = ++_autoId;
    _facts.add(fact.copyWith(id: id));
    return id;
  }

  @override
  Future<List<SemanticFact>> searchFacts(String query, {int limit = 8}) async {
    final tokens = tokenizeQuery(query);
    if (tokens.isEmpty) return recentFacts(limit: limit);
    final matches = _facts.where((f) {
      final t = f.text.toLowerCase();
      return tokens.any((tok) => t.contains(tok));
    }).toList()
      ..sort((a, b) {
        final byConf = b.confidence.compareTo(a.confidence);
        if (byConf != 0) return byConf;
        return b.createdUtc.compareTo(a.createdUtc);
      });
    return matches.take(limit).toList();
  }

  @override
  Future<List<SemanticFact>> recentFacts({int limit = 50}) async {
    final rows = [..._facts]..sort((a, b) => b.createdUtc.compareTo(a.createdUtc));
    return rows.take(limit).toList();
  }

  @override
  Future<int> factCount() async => _facts.length;

  @override
  Future<int> appendEvent(AppEvent event) async {
    final id = ++_autoId;
    _events.add(AppEvent(
      id: id,
      timestampUtc: event.timestampUtc,
      source: event.source,
      type: event.type,
      payload: event.payload,
      parentEventIds: event.parentEventIds,
      anchor: event.anchor,
    ));
    return id;
  }

  @override
  Future<List<AppEvent>> recentEvents({int limit = 100}) async {
    final rows = [..._events]..sort((a, b) => b.id!.compareTo(a.id!));
    return rows.take(limit).toList();
  }

  @override
  Future<int> eventCount() async => _events.length;

  @override
  Future<int> addEdge(RelationEdge edge) async {
    final id = ++_autoId;
    _edges.add(RelationEdge(
      id: id,
      fromFact: edge.fromFact,
      toFact: edge.toFact,
      type: edge.type,
      weight: edge.weight,
      createdUtc: edge.createdUtc,
    ));
    return id;
  }

  @override
  Future<List<RelationEdge>> allEdges() async => List.unmodifiable(_edges);

  @override
  Future<void> addProvenance(int factId, int eventId) async {
    _provenance.add((factId: factId, eventId: eventId));
  }

  @override
  Future<List<SemanticFact>> factsByIds(List<int> ids) async {
    final set = ids.toSet();
    return _facts.where((f) => f.id != null && set.contains(f.id)).toList();
  }

  @override
  Future<void> upsertEmbedding(int factId, List<double> vector,
      {String? model}) async {
    _embeddings[factId] = List<double>.from(vector);
  }

  @override
  Future<Map<int, List<double>>> allEmbeddings() async =>
      {for (final e in _embeddings.entries) e.key: List<double>.from(e.value)};

  @override
  Future<void> deleteEmbedding(int factId) async {
    _embeddings.remove(factId);
  }

  @override
  Future<int> reinforceClaims(List<int> ids, {required double alpha}) async {
    if (ids.isEmpty || alpha <= 0.0) return 0;
    final set = ids.toSet();
    var n = 0;
    for (var i = 0; i < _facts.length; i++) {
      final f = _facts[i];
      if (f.id == null || !set.contains(f.id)) continue;
      _facts[i] = f.copyWith(
        salience: reinforcedSalience(f.salience, alpha),
        confidence: reinforcedConfidence(f.confidence, alpha),
      );
      n++;
    }
    return n;
  }

  @override
  Future<int> decayAllSalience({
    required double cyclesElapsed,
    required double tau,
    required double beta,
  }) async {
    if (cyclesElapsed <= 0.0 || tau <= 0.0) return 0;
    var n = 0;
    for (var i = 0; i < _facts.length; i++) {
      final f = _facts[i];
      if (f.status == ClaimStatus.superseded) continue;
      final floor = permanenceFloor(f.confidence, beta);
      final ns = decayedSalience(f.salience,
          cyclesElapsed: cyclesElapsed, tau: tau, floor: floor);
      if (ns != f.salience) {
        _facts[i] = f.copyWith(salience: ns);
        n++;
      }
    }
    return n;
  }

  @override
  Future<void> updateFact(int id,
      {String? text, SemanticCategory? category, double? confidence}) async {
    final i = _facts.indexWhere((f) => f.id == id);
    if (i < 0) return;
    _facts[i] = _facts[i]
        .copyWith(text: text, category: category, confidence: confidence);
  }

  @override
  Future<void> deleteFact(int id) async {
    _facts.removeWhere((f) => f.id == id);
    _embeddings.remove(id);
  }

  @override
  Future<void> updateEpisodicContent(int id, String content) async {
    final i = _episodic.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final e = _episodic[i];
    _episodic[i] = EpisodicEntry(
      id: e.id,
      sessionId: e.sessionId,
      timestampUtc: e.timestampUtc,
      sequence: e.sequence,
      kind: e.kind,
      role: e.role,
      content: content,
      metadata: e.metadata,
      consolidated: e.consolidated,
    );
  }

  @override
  Future<void> deleteEpisodic(int id) async =>
      _episodic.removeWhere((e) => e.id == id);

  @override
  Future<void> clearAll() async {
    _episodic.clear();
    _facts.clear();
    _events.clear();
    _edges.clear();
    _provenance.clear();
    _embeddings.clear();
  }

  @override
  Future<void> close() async {}
}
