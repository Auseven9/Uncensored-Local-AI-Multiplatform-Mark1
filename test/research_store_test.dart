import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:portable_ai_flutter/core/research/research_records.dart';
import 'package:portable_ai_flutter/core/research/research_store.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('topics → runs → findings → sources round-trip', () async {
    final store = ResearchStore(path: inMemoryDatabasePath);
    await store.initialize();

    // Topic dedupes by slug; a second upsert of the same name reuses the id.
    final t1 = await store.upsertTopic('Quantum Computing');
    final t2 = await store.upsertTopic('quantum   computing', summary: 'qubits');
    expect(t1, t2, reason: 'same slug should reuse the topic');
    expect(await store.topicCount(), 1);

    final topic = await store.topicById(t1);
    expect(topic!.slug, 'quantum-computing');
    expect(topic.summary, 'qubits'); // summary updated on the second upsert

    // A run.
    final runId = await store.startRun(ResearchRun(
      topicId: t1,
      prompt: 'Find the basics of quantum computing',
      turnsBudget: 10,
      createdUtc: DateTime.now().toUtc().toIso8601String(),
    ));
    await store.finishRun(runId, status: 'done', turnsUsed: 3);
    final runs = await store.runs(topicId: t1);
    expect(runs.single.status, 'done');
    expect(runs.single.turnsUsed, 3);

    // A finding + its sources (provenance).
    final fId = await store.addFinding(ResearchFinding(
      topicId: t1,
      runId: runId,
      title: 'Superposition',
      content: 'A qubit can be in a combination of 0 and 1.',
      createdUtc: DateTime.now().toUtc().toIso8601String(),
    ));
    await store.addSource(ResearchSource(
      findingId: fId,
      url: 'https://example.org/qc',
      title: 'QC intro',
      snippet: 'superposition explained',
      fetchedUtc: DateTime.now().toUtc().toIso8601String(),
    ));

    expect(await store.findingCount(), 1);
    final findings = await store.findings(topicId: t1);
    expect(findings.single.title, 'Superposition');
    final sources = await store.sources(findingId: fId);
    expect(sources.single.url, 'https://example.org/qc');

    await store.clearAll();
    expect(await store.topicCount(), 0);
    expect(await store.findingCount(), 0);

    await store.close();
  });

  test('slugify normalizes names', () {
    expect(ResearchTopic.slugify('Hello, World!'), 'hello-world');
    expect(ResearchTopic.slugify('  AI & ML  '), 'ai-ml');
    expect(ResearchTopic.slugify('***'), 'topic');
  });
}
