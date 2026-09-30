import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/core/engine/inference_worker.dart';
import 'package:portable_ai_flutter/core/memory/eidetic_memory_engine.dart';
import 'package:portable_ai_flutter/core/memory/eidetic_store.dart';
import 'package:portable_ai_flutter/core/memory/memory_manager.dart';
import 'package:portable_ai_flutter/core/memory/memory_records.dart';

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
