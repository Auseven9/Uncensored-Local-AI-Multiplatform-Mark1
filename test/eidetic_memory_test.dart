import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/core/engine/inference_worker.dart';
import 'package:portable_ai_flutter/core/memory/eidetic_memory_engine.dart';
import 'package:portable_ai_flutter/core/memory/eidetic_store.dart';
import 'package:portable_ai_flutter/core/memory/memory_manager.dart';
import 'package:portable_ai_flutter/core/memory/memory_records.dart';
import 'package:portable_ai_flutter/core/memory/procedural_records.dart';

void main() {
  group('stableContentHash', () {
    test('is stable across case and whitespace', () {
      expect(
        stableContentHash('The User Prefers   Dark mode'),
        stableContentHash('the user prefers dark mode'),
      );
    });

    test('differs for different content', () {
      expect(
        stableContentHash('likes tea'),
        isNot(stableContentHash('likes coffee')),
      );
    });
  });

  group('EideticMemoryEngine (in-memory store)', () {
    late EideticMemoryEngine engine;

    setUp(() async {
      engine = EideticMemoryEngine(store: InMemoryEideticStore());
      await engine.init();
    });

    test('records episodic entries and tracks pending count', () async {
      await engine.recordTurn('s1', 'user', 'hello');
      await engine.recordTurn('s1', 'assistant', 'hi there');
      expect(await engine.pendingCount(), 2);

      final recent = await engine.recentEpisodic(sessionId: 's1');
      expect(recent.length, 2);
      // Newest first.
      expect(recent.first.content, 'hi there');
    });

    test('sequence increments per session', () async {
      await engine.recordTurn('s1', 'user', 'a');
      await engine.recordTurn('s1', 'user', 'b');
      final pending = await engine.pendingEpisodic();
      expect(pending.map((e) => e.sequence).toList(), [1, 2]);
    });

    test('markConsolidated clears pending', () async {
      await engine.recordTurn('s1', 'user', 'a');
      final pending = await engine.pendingEpisodic();
      await engine.markConsolidated(pending.map((e) => e.id!).toList());
      expect(await engine.pendingCount(), 0);
    });

    test('searchEpisodic can exclude consolidated turns', () async {
      await engine.recordTurn('s1', 'user', 'my girlfriend is Jayden');
      await engine.recordTurn('s1', 'user', 'I like green tea');

      // Before consolidation both raw turns are recall candidates.
      expect((await engine.searchEpisodic('girlfriend tea')).length, 2);

      // Fold the Jayden turn into a semantic claim (mark it reviewed).
      final all = await engine.pendingEpisodic();
      final jayden = all.firstWhere((e) => e.content.contains('Jayden'));
      await engine.markConsolidated([jayden.id!]);

      // Default still returns it (verbatim recall available on request)…
      expect((await engine.searchEpisodic('girlfriend tea')).length, 2);

      // …but excluding consolidated hides the folded turn, so its original
      // second-person wording can't leak back into recall — the clean claim
      // represents it instead.
      final excl = await engine.searchEpisodic('girlfriend tea',
          includeConsolidated: false);
      expect(excl.map((e) => e.content).toList(), ['I like green tea']);
    });

    test('procedural memory: CRUD + use reinforces salience (v7)', () async {
      final id = await engine.addProcedure(ProcedureRecord(
        createdUtc: DateTime.now().toUtc(),
        name: 'get_time',
        kind: ProcedureKind.tool,
        trigger: 'user asks what time it is',
        body: 'return the current local time',
      ));
      expect(id, greaterThan(0));

      final byName = await engine.procedureByName('get_time');
      expect(byName, isNotNull);
      expect(byName!.kind, ProcedureKind.tool);

      // Using a procedure bumps its count and reinforces its salience.
      await engine.recordProcedureUse(id);
      final used = await engine.procedureByName('get_time');
      expect(used!.usageCount, 1);
      expect(used.salience, greaterThan(0.5));
      expect(used.lastUsedUtc, isNotNull);

      // Disabling drops it from the active set.
      await engine.setProcedureStatus(id, ProcedureStatus.disabled);
      final active = await engine.procedures(status: ProcedureStatus.active);
      expect(active.where((p) => p.id == id), isEmpty);

      await engine.deleteProcedure(id);
      expect(await engine.procedureByName('get_time'), isNull);
    });

    test('rememberFact deduplicates by content', () async {
      final now = DateTime.now().toUtc();
      final first = await engine.rememberFact(SemanticFact(
        createdUtc: now,
        category: SemanticCategory.preference,
        text: 'User prefers dark mode',
      ));
      final second = await engine.rememberFact(SemanticFact(
        createdUtc: now,
        category: SemanticCategory.preference,
        text: 'user prefers DARK mode', // same after normalisation
      ));
      expect(first, isNotNull); // inserted → new id
      expect(second, isNull); // deduplicated
      expect(await engine.factCount(), 1);
    });

    test('appends events and reads them back newest-first', () async {
      // init() already recorded one app_launch event.
      final userId = await engine.appendEvent(
          source: 'user', type: 'user_message', payload: {'preview': 'hi'});
      await engine.appendEvent(
          source: 'assistant',
          type: 'assistant_message',
          payload: {'preview': 'hello'},
          parents: [userId]);

      expect(await engine.eventCount(), 3); // launch + user + assistant

      final events = await engine.recentEvents(limit: 10);
      expect(events.first.type, 'assistant_message');
      expect(events.first.parentEventIds, [userId]);
      // Every event carries a grounding anchor from this session.
      expect(events.first.anchor.sessionId, engine.sessionId);
      expect(events.first.anchor.monotonicMs, greaterThanOrEqualTo(0));
    });

    test('clearAll wipes the event log too', () async {
      await engine.appendEvent(source: 'user', type: 'user_message');
      await engine.clearAll();
      expect(await engine.eventCount(), 0);
    });

    test('recallByActivation surfaces related claims via edges', () async {
      final now = DateTime.now().toUtc();
      final a = await engine.rememberFact(SemanticFact(
          createdUtc: now,
          category: SemanticCategory.fact,
          text: 'Alesis runs on llama.cpp'));
      final b = await engine.rememberFact(SemanticFact(
          createdUtc: now,
          category: SemanticCategory.fact,
          text: 'The GGUF model is quantized to Q4'));
      expect(a, isNotNull);
      expect(b, isNotNull);
      // Link them so a query hitting A also surfaces B.
      await engine.addEdge(
          RelationEdge(fromFact: a!, toFact: b!, type: RelationType.related));

      final hits = await engine.recallByActivation('llama',
          k: 8, alpha: 0.85, threshold: 0.15, maxHops: 2, seedK: 10);
      final texts = hits.map((f) => f.text).toList();
      expect(texts.any((t) => t.contains('llama.cpp')), isTrue); // seed A
      expect(texts.any((t) => t.contains('quantized')), isTrue); // via edge B
    });

    test('recall finds facts by keyword', () async {
      final now = DateTime.now().toUtc();
      await engine.rememberFact(SemanticFact(
          createdUtc: now,
          category: SemanticCategory.fact,
          text: 'The project uses Flutter and llamadart'));
      await engine.rememberFact(SemanticFact(
          createdUtc: now,
          category: SemanticCategory.fact,
          text: 'The capital of France is Paris'));

      final hits = await engine.recall('flutter');
      expect(hits.length, 1);
      expect(hits.first.text, contains('Flutter'));
    });

    test('nearestClaimIds seeds by embedding similarity', () async {
      final now = DateTime.now().toUtc();
      final dog = await engine.rememberFact(SemanticFact(
          createdUtc: now, category: SemanticCategory.fact, text: 'has a dog'));
      final cat = await engine.rememberFact(SemanticFact(
          createdUtc: now, category: SemanticCategory.fact, text: 'has a cat'));
      final car = await engine.rememberFact(SemanticFact(
          createdUtc: now, category: SemanticCategory.fact, text: 'drives a car'));

      // Toy 2-D vectors: pets cluster together, the car is off on its own.
      await engine.storeEmbedding(dog!, [1.0, 0.0]);
      await engine.storeEmbedding(cat!, [0.9, 0.1]);
      await engine.storeEmbedding(car!, [0.0, 1.0]);
      expect(await engine.embeddingCount(), 3);

      // A "pet"-like query vector should surface the two pets first.
      final ids = await engine.nearestClaimIds([0.95, 0.05], k: 2);
      expect(ids.toSet(), {dog, cat});

      // Empty query or empty corpus degrades to no seeds (recall falls back).
      expect(await engine.nearestClaimIds(const [], k: 2), isEmpty);
    });

    test('recallSemanticScored seeds by embedding with no keyword overlap',
        () async {
      final now = DateTime.now().toUtc();
      final dog = await engine.rememberFact(SemanticFact(
          createdUtc: now,
          category: SemanticCategory.fact,
          text: 'has a dog named Rex'));
      final other = await engine.rememberFact(SemanticFact(
          createdUtc: now,
          category: SemanticCategory.fact,
          text: 'the capital of France is Paris'));
      await engine.storeEmbedding(dog!, [1.0, 0.0]);
      await engine.storeEmbedding(other!, [0.0, 1.0]);

      // "pet" shares no keyword with either claim, but its embedding is near
      // the dog claim's — meaning-seeding should still surface Rex.
      final hits = await engine.recallSemanticScored('pet',
          queryEmbedding: [0.95, 0.05], embedSeedK: 5, embedThreshold: 0.5);
      expect(hits.map((e) => e.fact.text).any((t) => t.contains('Rex')), isTrue);
    });
  });

  group('MemoryManager gate', () {
    test('does not run inference when below threshold', () async {
      final engine = EideticMemoryEngine(store: InMemoryEideticStore());
      await engine.init();
      final manager = MemoryManager(
        memory: engine,
        worker: InferenceWorker(), // never dispatched below threshold
        minEntriesToConsolidate: 6,
      );

      await engine.recordTurn('s1', 'user', 'a');
      await engine.recordTurn('s1', 'user', 'b');

      expect(await manager.hasPendingWork(), isFalse);
      final result = await manager.consolidatePending();
      expect(result.ran, isFalse);
      expect(result.note, contains('below threshold'));
    });
  });
}
