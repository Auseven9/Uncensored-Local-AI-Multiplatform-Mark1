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
      expect(first, isTrue);
      expect(second, isFalse);
      expect(await engine.factCount(), 1);
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
