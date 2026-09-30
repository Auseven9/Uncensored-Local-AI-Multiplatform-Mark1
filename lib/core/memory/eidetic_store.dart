import 'event_records.dart';
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
  Future<List<EpisodicEntry>> pendingEpisodic({int limit = 200});
  Future<int> pendingCount();
  Future<void> markConsolidated(List<int> ids);

  // ── Semantic (long-term) ───────────────────────────────────
  /// Returns true if the fact was inserted, false if a row with the same
  /// [SemanticFact.dedupeHash] already existed (deduplicated).
  Future<bool> insertFact(SemanticFact fact);
  Future<List<SemanticFact>> searchFacts(String query, {int limit = 8});
  Future<List<SemanticFact>> recentFacts({int limit = 50});
  Future<int> factCount();

  // ── Event log (append-only, grounded) ───────────────────────
  /// Append one immutable, sensor-anchored event. Returns its row id.
  Future<int> appendEvent(AppEvent event);
  Future<List<AppEvent>> recentEvents({int limit = 100});
  Future<int> eventCount();

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
  Future<bool> insertFact(SemanticFact fact) async {
    if (_facts.any((f) => f.dedupeHash == fact.dedupeHash)) return false;
    _facts.add(SemanticFact(
      id: ++_autoId,
      createdUtc: fact.createdUtc,
      category: fact.category,
      text: fact.text,
      sourceSessionId: fact.sourceSessionId,
      confidence: fact.confidence,
      dedupeHash: fact.dedupeHash,
      embedding: fact.embedding,
    ));
    return true;
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
  Future<void> updateFact(int id,
      {String? text, SemanticCategory? category, double? confidence}) async {
    final i = _facts.indexWhere((f) => f.id == id);
    if (i < 0) return;
    final old = _facts[i];
    final newText = text ?? old.text;
    _facts[i] = SemanticFact(
      id: old.id,
      createdUtc: old.createdUtc,
      category: category ?? old.category,
      text: newText,
      sourceSessionId: old.sourceSessionId,
      confidence: confidence ?? old.confidence,
      dedupeHash: text == null ? old.dedupeHash : stableContentHash(newText),
      embedding: old.embedding,
    );
  }

  @override
  Future<void> deleteFact(int id) async =>
      _facts.removeWhere((f) => f.id == id);

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
  }

  @override
  Future<void> close() async {}
}
