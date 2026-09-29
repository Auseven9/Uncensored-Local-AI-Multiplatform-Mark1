import 'dart:async';

import 'package:get/get.dart';

import '../../services/log_service.dart';
import 'eidetic_memory_engine.dart';
import 'memory_manager.dart';
import 'memory_records.dart';

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

  LogService? get _log {
    try {
      return Get.find<LogService>();
    } catch (_) {
      return null;
    }
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

  /// RECALL: build a context block of the most relevant remembered facts for
  /// [query]. Returns '' when nothing is relevant. Always logged as a call.
  Future<String> remembering(String query, {int k = 6}) async {
    List<SemanticFact> facts;
    try {
      facts = await _memory.recall(query, k: k);
    } catch (e) {
      _record(MemoryCallType.recall, 'query="${_short(query)}" → error: $e');
      return '';
    }
    _record(MemoryCallType.recall,
        'query="${_short(query)}" → ${facts.length} fact(s)');
    if (facts.isEmpty) return '';
    final buf = StringBuffer('Relevant things you remember about this user:\n');
    for (final f in facts) {
      buf.writeln('- (${f.category.name}) ${f.text}');
    }
    return buf.toString().trim();
  }

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
    return id;
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
    unawaited(_maybeConsolidate());
  }

  /// Public opportunistic-consolidation trigger (gated; no-op when idle).
  Future<void> maybeConsolidate() => _maybeConsolidate();

  Future<void> _maybeConsolidate() async {
    try {
      if (!await _manager.hasPendingWork()) return;
      final result = await _manager.consolidatePending();
      if (result.ran) {
        _record(MemoryCallType.consolidate,
            'reviewed ${result.considered} · +${result.promoted} stored · ${result.deduped} dup');
      }
    } catch (_) {
      // Consolidation is best-effort; never surface as a turn failure.
    }
  }

  String _short(String s) => s.length <= 48 ? s : '${s.substring(0, 48)}…';
}
