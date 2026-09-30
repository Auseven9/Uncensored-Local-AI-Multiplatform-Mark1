import 'dart:async';

import 'package:get/get.dart';

import '../../services/log_service.dart';
import '../params/parameters_service.dart';
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

  ParametersService? get _params {
    try {
      return Get.find<ParametersService>();
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

  /// RECALL: build a context block of remembered facts to inject before the
  /// model answers. Always logged as a call.
  ///
  /// Keyword hits for [query] come first, then the block is topped up with the
  /// most recent facts. This is deliberate: keyword search cannot bridge
  /// phrasing (a third-person fact "Alesis runs on llama.cpp" never lexically
  /// matches "what do you remember?"), so without a top-up the model would get
  /// no memory at all for most questions. Real relevance ranking arrives with
  /// embeddings; until then, surfacing memory beats surfacing nothing.
  Future<String> remembering(String query, {int k = 8}) async {
    final kk = _params?.getInt('recall.k') ?? k;
    if (kk <= 0) {
      _record(MemoryCallType.recall, 'query="${_short(query)}" → disabled (k=0)');
      return '';
    }
    final topUp = _params?.getBool('recall.topUpRecent') ?? true;

    List<SemanticFact> hits;
    List<SemanticFact> recent;
    try {
      hits = await _memory.recall(query, k: kk);
      recent =
          topUp ? await _memory.recentFacts(limit: kk * 2) : <SemanticFact>[];
    } catch (e) {
      _record(MemoryCallType.recall, 'query="${_short(query)}" → error: $e');
      return '';
    }

    final seen = <String>{};
    final merged = <SemanticFact>[];
    for (final f in [...hits, ...recent]) {
      final key = f.id?.toString() ?? f.dedupeHash;
      if (seen.add(key)) merged.add(f);
      if (merged.length >= kk) break;
    }

    _record(MemoryCallType.recall,
        'query="${_short(query)}" → keyword ${hits.length}, injected ${merged.length}');

    if (merged.isEmpty) return '';
    final buf = StringBuffer(
        'Things you remember (your long-term memory — treat as true):\n');
    for (final f in merged) {
      buf.writeln('- ${f.text}');
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
        if (_params?.getBool('events.enabled') ?? true) {
          try {
            await _memory.appendEvent(
              source: 'memory',
              type: 'consolidate',
              payload: {
                'considered': result.considered,
                'promoted': result.promoted,
                'deduped': result.deduped,
              },
            );
          } catch (_) {}
        }
      }
    } catch (_) {
      // Consolidation is best-effort; never surface as a turn failure.
    }
  }

  String _short(String s) => s.length <= 48 ? s : '${s.substring(0, 48)}…';
}
