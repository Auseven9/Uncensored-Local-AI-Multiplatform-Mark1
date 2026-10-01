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

  /// Ids of the claims newly inserted this pass (for provenance linking).
  final List<int> promotedFactIds;

  /// Number of relation edges created between this pass's claims.
  final int relationsAdded;
  final String? note;

  const ConsolidationResult({
    required this.ran,
    this.considered = 0,
    this.promoted = 0,
    this.deduped = 0,
    this.promotedFactIds = const [],
    this.relationsAdded = 0,
    this.note,
  });

  @override
  String toString() => 'ConsolidationResult(ran=$ran, considered=$considered, '
      'promoted=$promoted, deduped=$deduped, relations=$relationsAdded'
      '${note == null ? '' : ', note=$note'})';
}

/// Parsed output of one curation pass: the durable facts to store, plus the
/// relations between them (as indices into [facts]).
class _CurationOutput {
  final List<SemanticFact> facts;
  final List<({int from, int to, RelationType type})> relations;
  const _CurationOutput(this.facts, this.relations);
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
        // Output budget — the curation JSON is short; this just bounds runtime
        // if the model rambles after the object.
        maxTokens: 512,
        // NOTE: deliberately NO GBNF grammar here. Grammar-constrained sampling
        // filters the whole vocabulary through the grammar automaton on the CPU
        // at every token — on a 260k-token vocabulary (Gemma) that collapses to
        // ~0.3 tok/s even on GPU, because the sampler, not the matmul, is the
        // bottleneck. We instead ask for JSON in the prompt and extract it
        // tolerantly below (extractJsonObject strips fences/prose and finds the
        // first balanced object), which runs at full chat speed. A rare
        // unparseable reply simply defers the batch (see below), never corrupts.
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

    final curation =
        _parseAndCurate(raw, sourceSessionId: entries.last.sessionId);
    if (curation == null) {
      // The model's reply wasn't parseable JSON. Without a grammar this can
      // happen occasionally; leave the batch PENDING (don't mark it reviewed)
      // so the next pass retries it, rather than silently losing the knowledge.
      _log?.warn('Consolidation: unparseable output, deferring batch',
          source: 'Memory');
      return const ConsolidationResult(ran: false, note: 'unparseable');
    }
    final facts = curation.facts;

    var promoted = 0;
    var deduped = 0;
    final promotedIds = <int>[];
    // facts[] index → the new claim id (only for newly-inserted facts).
    final indexToId = <int, int>{};
    for (var i = 0; i < facts.length; i++) {
      final id = await memory.rememberFact(facts[i]);
      if (id != null) {
        promoted++;
        promotedIds.add(id);
        indexToId[i] = id;
      } else {
        deduped++;
      }
    }

    // Turn the model's relations into edges — but only between claims that were
    // actually inserted this pass (deduped facts have no new id to link).
    var relationsAdded = 0;
    for (final rel in curation.relations) {
      final fromId = indexToId[rel.from];
      final toId = indexToId[rel.to];
      if (fromId == null || toId == null || fromId == toId) continue;
      try {
        await memory.addEdge(
            RelationEdge(fromFact: fromId, toFact: toId, type: rel.type));
        relationsAdded++;
      } catch (_) {
        // A single bad edge must not abort the pass.
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
      promotedFactIds: promotedIds,
      relationsAdded: relationsAdded,
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
      'You never invent information that is not supported by the log. '
      'POINT OF VIEW IS CRITICAL. The log is a conversation between "user" (the '
      'human) and "assistant" (the AI). When the user says "I", "me" or "my", '
      'they mean THEMSELVES — the user, never the AI. When the user says "you" '
      'or "your", they mean the AI. Write every fact in the third person (e.g. '
      '"The user has a girlfriend named Jayden"), never in the second person, '
      'and tag who each fact is about.';

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
          '{"facts": [{"category": "fact|preference|rule|summary", "subject": "<who/what it is about>", "subjectType": "user|self|person|place|thing", "holder": "user|assistant", "text": "<concise third-person statement>", "confidence": 0.0}], "relations": [{"from": 0, "to": 1, "type": "supports|contradicts|causes|part_of|related"}]}')
      ..writeln(
          'Output raw JSON only. No markdown fences, no commentary before or after.')
      ..writeln('Rules:')
      ..writeln('- Keep at most $maxFactsPerPass items; fewer is better.')
      ..writeln(
          '- "subjectType": "user" for facts about the human; "self" ONLY for facts about the AI assistant itself; "person"/"place"/"thing" for others the user mentioned (e.g. a partner, a city).')
      ..writeln(
          '- "holder": "user" when the user stated it (almost always); "assistant" only for the AI\'s own reflection about itself.')
      ..writeln(
          '- "subject": a short label for who/what the fact is about ("the user", "Jayden", "myself").')
      ..writeln(
          '- Write "text" in the third person. Example: user says "my girlfriend is Jayden" -> {"subject":"the user","subjectType":"user","holder":"user","text":"The user has a girlfriend named Jayden"}.')
      ..writeln(
          '- "relations" links facts by their 0-based index in "facts" — use it to connect facts that support, contradict, cause, or are part of one another. Use [] if none.')
      ..writeln('- Omit anything transient, redundant, or uncertain.')
      ..writeln(
          '- If nothing is worth remembering, return {"facts": [], "relations": []}.');
    return buffer.toString();
  }

  // ── Parsing + curation gate (Dart side) ─────────────────────

  /// Parse the curator's reply and apply the Dart-side curation gate.
  ///
  /// Returns `null` for a HARD parse failure (no JSON object found, malformed
  /// JSON, not an object, or missing the `facts` array) — the caller must then
  /// defer the batch (leave it pending) rather than mark it reviewed, so the
  /// knowledge isn't lost. A valid object with an empty `facts` list is NOT a
  /// failure: it means "reviewed, nothing worth promoting", and returns an
  /// empty (non-null) result so the batch is correctly marked consolidated.
  _CurationOutput? _parseAndCurate(String raw,
      {required String sourceSessionId}) {
    final jsonText = GbnfToolEngine.extractJsonObject(raw);
    if (jsonText == null) return null;

    Object? decoded;
    try {
      decoded = json.decode(jsonText);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    final rawFacts = decoded['facts'];
    if (rawFacts is! List) return null;

    final maxFacts = _params?.getInt('consolidate.maxFactsPerPass') ?? maxFactsPerPass;
    final minLen = _params?.getInt('consolidate.minFactLen') ?? 8;
    final maxLen = _params?.getInt('consolidate.maxFactLen') ?? 500;

    final now = DateTime.now().toUtc();
    final seen = <String>{};
    final out = <SemanticFact>[];
    // Model's original fact index → position in the curated `out` list.
    final origToOut = <int, int>{};

    for (var origIdx = 0; origIdx < rawFacts.length; origIdx++) {
      if (out.length >= maxFacts) break;
      final item = rawFacts[origIdx];
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

      // Identity/attribution (Phase 5): who the fact is about, and whose view.
      final subject = (item['subject'] as Object?)?.toString().trim() ?? '';
      final subjectType =
          _subjectTypeLoose((item['subjectType'] as Object?)?.toString());
      final holder =
          _claimHolderLoose((item['holder'] as Object?)?.toString());

      origToOut[origIdx] = out.length;
      out.add(SemanticFact(
        createdUtc: now,
        category: category,
        text: text,
        sourceSessionId: sourceSessionId,
        confidence: confidence,
        dedupeHash: hash,
        subject: subject,
        subjectType: subjectType,
        holder: holder,
      ));
    }

    // Relations reference the model's original fact indices; remap onto `out`
    // and drop any pointing at a fact that was filtered away.
    final relations = <({int from, int to, RelationType type})>[];
    final rawRels = decoded['relations'];
    if (rawRels is List) {
      for (final r in rawRels) {
        if (r is! Map) continue;
        final from = origToOut[(r['from'] as num?)?.toInt()];
        final to = origToOut[(r['to'] as num?)?.toInt()];
        if (from == null || to == null || from == to) continue;
        relations.add((
          from: from,
          to: to,
          type: _relationTypeLoose(
              (r['type'] as Object?)?.toString() ?? 'related'),
        ));
      }
    }

    return _CurationOutput(out, relations);
  }

  /// Tolerant parse of a relation-type string — the model may emit "part_of"
  /// while the enum name is "partOf".
  static RelationType _relationTypeLoose(String s) {
    switch (s.toLowerCase().replaceAll('_', '').trim()) {
      case 'supports':
        return RelationType.supports;
      case 'contradicts':
        return RelationType.contradicts;
      case 'causes':
        return RelationType.causes;
      case 'partof':
        return RelationType.partOf;
      default:
        return RelationType.related;
    }
  }

  /// Tolerant parse of the curator's "subjectType" token onto [SubjectType].
  /// The model may say "self"/"ai"/"assistant" for the agent, "human" for the
  /// user, "people" for a person, etc. Defaults to [SubjectType.user] — the
  /// safe presumption that a fact is about the user, not the AI.
  static SubjectType _subjectTypeLoose(String? s) {
    switch ((s ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')) {
      case 'self':
      case 'selfai':
      case 'ai':
      case 'assistant':
      case 'me':
      case 'myself':
        return SubjectType.selfAI;
      case 'user':
      case 'human':
      case 'you': // the curator addressing the user
        return SubjectType.user;
      case 'person':
      case 'people':
      case 'someone':
        return SubjectType.person;
      case 'place':
      case 'location':
        return SubjectType.place;
      case 'thing':
      case 'object':
      case 'item':
        return SubjectType.thing;
      default:
        return SubjectType.user;
    }
  }

  /// Tolerant parse of the curator's "holder" token onto [ClaimHolder].
  /// Defaults to [ClaimHolder.user] (the user asserted it).
  static ClaimHolder _claimHolderLoose(String? s) {
    switch ((s ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')) {
      case 'assistant':
      case 'ai':
      case 'self':
      case 'me':
        return ClaimHolder.assistant;
      default:
        return ClaimHolder.user;
    }
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}
