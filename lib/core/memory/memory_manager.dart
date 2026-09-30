import 'dart:convert';

import 'package:get/get.dart';

import '../../services/log_service.dart';
import '../engine/inference_worker.dart';
import '../params/parameters_service.dart';
import '../tools/gbnf_tool_engine.dart';
import 'eidetic_memory_engine.dart';
import 'memory_records.dart';

/// Outcome of a consolidation pass. [ran] is false when the gate short-circuits
/// (below threshold, nothing pending, no model, or preempted) — the important
/// case, because it means no inference happened and the model stayed idle.
class ConsolidationResult {
  final bool ran;
  final int considered;
  final int promoted;
  final int deduped;
  final String? note;

  const ConsolidationResult({
    required this.ran,
    this.considered = 0,
    this.promoted = 0,
    this.deduped = 0,
    this.note,
  });

  @override
  String toString() => 'ConsolidationResult(ran=$ran, considered=$considered, '
      'promoted=$promoted, deduped=$deduped${note == null ? '' : ', note=$note'})';
}

/// The gate between short-term (episodic) and long-term (semantic) memory.
///
/// Its whole job is to stop long-term memory from being poisoned by writing
/// every raw thought. It does two things when — and only when — there is real
/// work to do:
///
///  1. **Summarise**: hand the model a batch of recent episodic entries and
///     ask it to condense them into a few durable statements.
///  2. **Curate**: keep only items that read like durable facts, preferences,
///     or rules, then apply Dart-side hard filters (length bounds, batch cap,
///     content-hash dedupe) before anything is written.
///
/// Crucially, [consolidatePending] first does a cheap row-count check that runs
/// **no inference at all**. If there is nothing worth consolidating, the model
/// is never woken — matching the "0% compute at standby" model of offline
/// agents.
class MemoryManager {
  final EideticMemoryEngine memory;
  final InferenceWorker worker;

  /// Minimum unconsolidated episodic rows before a pass will run the model.
  final int minEntriesToConsolidate;

  /// Upper bound on episodic rows fed to a single pass (keeps the prompt small).
  final int maxEntriesPerPass;

  /// Upper bound on facts accepted from a single pass (flood protection).
  final int maxFactsPerPass;

  MemoryManager({
    required this.memory,
    required this.worker,
    this.minEntriesToConsolidate = 6,
    this.maxEntriesPerPass = 40,
    this.maxFactsPerPass = 12,
  });

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

  int get _minEntries =>
      _params?.getInt('consolidate.minEntries') ?? minEntriesToConsolidate;
  int get _maxEntries =>
      _params?.getInt('consolidate.maxEntriesPerPass') ?? maxEntriesPerPass;
  double get _temp => _params?.getDouble('consolidate.temperature') ?? 0.2;

  /// Cheap, inference-free check used by schedulers to decide whether it is
  /// even worth waking the model.
  Future<bool> hasPendingWork() async =>
      (await memory.pendingCount()) >= _minEntries;

  /// Run one gated consolidation pass. See the class doc for the contract.
  Future<ConsolidationResult> consolidatePending({bool force = false}) async {
    final pending = await memory.pendingCount();
    if (!force && pending < _minEntries) {
      return ConsolidationResult(
        ran: false,
        note: 'below threshold ($pending/$_minEntries)',
      );
    }

    final entries = await memory.pendingEpisodic(limit: _maxEntries);
    if (entries.isEmpty) {
      return const ConsolidationResult(ran: false, note: 'nothing pending');
    }

    final String raw;
    try {
      raw = await worker.run(
        id: 'consolidate-${DateTime.now().millisecondsSinceEpoch}',
        systemPrompt: _curationSystemPrompt,
        messages: [
          {'role': 'user', 'content': _buildCurationPrompt(entries)},
        ],
        temperature: _temp,
        priority: TaskPriority.backgroundIntrospection,
        // Sampler-enforced structure: the curator can only emit a JSON object,
        // so parsing below cannot misfire on a grammar-capable backend.
        grammar: GbnfToolEngine.buildJsonObjectGrammar(),
      );
    } on InferenceCancelledException {
      // A higher-priority (user) task preempted us — leave the entries pending
      // so the next idle cycle retries them. Nothing was promoted.
      return const ConsolidationResult(ran: false, note: 'preempted');
    } catch (e) {
      // Most commonly: no model loaded. Don't consume the pending entries.
      _log?.warn('Consolidation skipped: $e', source: 'Memory');
      return ConsolidationResult(ran: false, note: 'error: $e');
    }

    final facts = _parseAndCurate(raw, sourceSessionId: entries.last.sessionId);

    var promoted = 0;
    var deduped = 0;
    for (final fact in facts) {
      final inserted = await memory.rememberFact(fact);
      if (inserted) {
        promoted++;
      } else {
        deduped++;
      }
    }

    // The batch has now been reviewed — mark it consolidated so it is not
    // reprocessed, whether or not it produced new facts.
    final ids = entries.map((e) => e.id).whereType<int>().toList();
    await memory.markConsolidated(ids);

    final result = ConsolidationResult(
      ran: true,
      considered: entries.length,
      promoted: promoted,
      deduped: deduped,
    );
    _log?.info('Consolidation: $result', source: 'Memory');
    return result;
  }

  // ── Prompt construction ─────────────────────────────────────

  static const _curationSystemPrompt =
      'You are a memory curator for a local AI agent. You read a log of recent '
      'activity and extract only the durable knowledge worth remembering long '
      'term: stable facts, user preferences, and standing rules. You aggressively '
      'discard transient chatter, one-off details, and anything already obvious. '
      'You never invent information that is not supported by the log.';

  String _buildCurationPrompt(List<EpisodicEntry> entries) {
    final buffer = StringBuffer()
      ..writeln('Here is a log of recent activity:')
      ..writeln();
    for (final e in entries) {
      buffer.writeln(
          '- [${e.timestampUtc.toIso8601String()}] (${e.kind.name}/${e.role}) '
          '${_truncate(e.content, 280)}');
    }
    buffer
      ..writeln()
      ..writeln('Extract the durable knowledge worth storing long term.')
      ..writeln('Respond with ONLY a JSON object of this exact shape:')
      ..writeln(
          '{"facts": [{"category": "fact|preference|rule|summary", "text": "<concise statement>", "confidence": 0.0}]}')
      ..writeln('Rules:')
      ..writeln('- Keep at most $maxFactsPerPass items; fewer is better.')
      ..writeln('- Omit anything transient, redundant, or uncertain.')
      ..writeln('- If nothing is worth remembering, return {"facts": []}.');
    return buffer.toString();
  }

  // ── Parsing + curation gate (Dart side) ─────────────────────

  List<SemanticFact> _parseAndCurate(String raw, {required String sourceSessionId}) {
    final jsonText = GbnfToolEngine.extractJsonObject(raw);
    if (jsonText == null) return const [];

    Object? decoded;
    try {
      decoded = json.decode(jsonText);
    } on FormatException {
      return const [];
    }
    if (decoded is! Map) return const [];

    final rawFacts = decoded['facts'];
    if (rawFacts is! List) return const [];

    final maxFacts = _params?.getInt('consolidate.maxFactsPerPass') ?? maxFactsPerPass;
    final minLen = _params?.getInt('consolidate.minFactLen') ?? 8;
    final maxLen = _params?.getInt('consolidate.maxFactLen') ?? 500;

    final now = DateTime.now().toUtc();
    final seen = <String>{};
    final out = <SemanticFact>[];

    for (final item in rawFacts) {
      if (out.length >= maxFacts) break;
      if (item is! Map) continue;

      final text = (item['text'] as Object?)?.toString().trim() ?? '';
      // Hard curation filters: reject noise and over-long dumps.
      if (text.length < minLen || text.length > maxLen) continue;

      final hash = stableContentHash(text);
      if (!seen.add(hash)) continue; // in-batch dedupe

      final category = semanticCategoryFromName(
          (item['category'] as Object?)?.toString() ?? 'fact');

      var confidence = 0.5;
      final rawConf = item['confidence'];
      if (rawConf is num) confidence = rawConf.toDouble();
      confidence = confidence.clamp(0.0, 1.0).toDouble();

      out.add(SemanticFact(
        createdUtc: now,
        category: category,
        text: text,
        sourceSessionId: sourceSessionId,
        confidence: confidence,
        dedupeHash: hash,
      ));
    }
    return out;
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}
