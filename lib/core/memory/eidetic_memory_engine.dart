import 'package:get/get.dart';

import '../../services/log_service.dart';
import 'eidetic_store.dart';
import 'memory_records.dart';

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
    _log?.info(
      'Eidetic memory ready (persistent=${_store.isPersistent})',
      source: 'Memory',
    );
    return this;
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

  /// Persist one durable fact. Returns false if it was deduplicated.
  Future<bool> rememberFact(SemanticFact fact) async {
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
