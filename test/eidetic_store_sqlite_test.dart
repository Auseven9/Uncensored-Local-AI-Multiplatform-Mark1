import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:portable_ai_flutter/core/memory/eidetic_store_io.dart';
import 'package:portable_ai_flutter/core/memory/event_records.dart';
import 'package:portable_ai_flutter/core/memory/memory_records.dart';

/// Exercises the REAL SQLite-backed store (not the in-memory fallback) via the
/// FFI factory, so the open / configure (WAL) / onCreate / onUpgrade / query
/// paths get direct coverage. Note: FFI SQLite is more permissive than
/// Android's SQLite, so this cannot catch Android-JNI-specific issues (that is
/// what the emulator smoke test is for) — but it does guard the schema and the
/// v1->v2 migration in pure Dart.
SensorAnchor _anchor() => SensorAnchor(
      wallClockUtc: DateTime.now().toUtc(),
      monotonicMs: 1234,
      sessionId: 'test-session',
      clockSkewMs: 0,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('eidetic-sqlite-test-');
  });
  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('fresh v2 open creates event_log and round-trips events', () async {
    final store = SqliteEideticStore(path: p.join(tempDir.path, 'fresh.db'));
    await store.initialize();

    final userId = await store.appendEvent(AppEvent(
      timestampUtc: DateTime.now().toUtc(),
      source: 'user',
      type: 'user_message',
      payload: {'preview': 'hi'},
      anchor: _anchor(),
    ));
    await store.appendEvent(AppEvent(
      timestampUtc: DateTime.now().toUtc(),
      source: 'assistant',
      type: 'assistant_message',
      parentEventIds: [userId],
      anchor: _anchor(),
    ));

    expect(await store.eventCount(), 2);
    final events = await store.recentEvents();
    expect(events.first.type, 'assistant_message'); // newest first
    expect(events.first.parentEventIds, [userId]);
    expect(events.first.anchor.sessionId, 'test-session');
    await store.close();
  });

  test('clearAll wipes episodic, semantic and event tables', () async {
    final store = SqliteEideticStore(path: p.join(tempDir.path, 'crud.db'));
    await store.initialize();

    await store.insertEpisodic(EpisodicEntry(
        sessionId: 's',
        timestampUtc: DateTime.now().toUtc(),
        sequence: 1,
        kind: EpisodicKind.turn,
        role: 'user',
        content: 'hello'));
    await store.insertFact(SemanticFact(
        createdUtc: DateTime.now().toUtc(),
        category: SemanticCategory.fact,
        text: 'the sky is blue'));
    await store.appendEvent(AppEvent(
        timestampUtc: DateTime.now().toUtc(),
        source: 'system',
        type: 'app_launch',
        anchor: _anchor()));

    expect(await store.pendingCount(), 1);
    expect(await store.factCount(), 1);
    expect(await store.eventCount(), 1);

    await store.clearAll();
    expect(await store.pendingCount(), 0);
    expect(await store.factCount(), 0);
    expect(await store.eventCount(), 0);
    await store.close();
  });

  test('v1 database upgrades to v2: event_log back-filled, old data kept',
      () async {
    final dbPath = p.join(tempDir.path, 'legacy.db');

    // Simulate an install from the pre-event-log app (schema v1): the two
    // original tables only, no event_log.
    final v1 = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE episodic_log (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id TEXT NOT NULL,
              timestamp_utc TEXT NOT NULL,
              timestamp_millis INTEGER NOT NULL,
              sequence INTEGER NOT NULL,
              kind TEXT NOT NULL,
              role TEXT NOT NULL,
              content TEXT NOT NULL,
              metadata_json TEXT,
              consolidated INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE semantic_facts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              created_utc TEXT NOT NULL,
              category TEXT NOT NULL,
              text TEXT NOT NULL,
              source_session_id TEXT,
              confidence REAL NOT NULL DEFAULT 0.5,
              dedupe_hash TEXT NOT NULL UNIQUE,
              embedding_json TEXT
            )
          ''');
        },
      ),
    );
    // Pre-existing user data that must survive the migration. Insert with the
    // RAW v1 column set — SemanticFact.toRow() now emits the v3 claim columns
    // (salience/status/supersedes) which this old table does not have yet.
    await v1.insert('semantic_facts', {
      'created_utc': DateTime.now().toUtc().toIso8601String(),
      'category': 'fact',
      'text': 'pre-existing fact',
      'source_session_id': null,
      'confidence': 0.5,
      'dedupe_hash': stableContentHash('pre-existing fact'),
      'embedding_json': null,
    });
    await v1.close();

    // Reopen through the store (version 2) — onUpgrade must add event_log.
    final store = SqliteEideticStore(path: dbPath);
    await store.initialize();

    // Old data preserved…
    expect(await store.factCount(), 1);
    // …with the new claim columns back-filled to their defaults.
    final migrated = (await store.recentFacts(limit: 1)).first;
    expect(migrated.salience, 0.5);
    expect(migrated.status, ClaimStatus.active);
    // …and the newly-migrated event log is usable.
    await store.appendEvent(AppEvent(
        timestampUtc: DateTime.now().toUtc(),
        source: 'system',
        type: 'app_launch',
        anchor: _anchor()));
    expect(await store.eventCount(), 1);

    // …and the epistemic-graph tables were created during the v1->v3 upgrade
    // (allEdges would throw if relation_edges did not exist).
    expect(await store.allEdges(), isEmpty);
    final oldFactId = (await store.recentFacts(limit: 1)).first.id!;
    final newFactId = await store.insertFact(SemanticFact(
      createdUtc: DateTime.now().toUtc(),
      category: SemanticCategory.fact,
      text: 'a claim added after migration',
    ));
    await store.addEdge(RelationEdge(
        fromFact: oldFactId, toFact: newFactId!, type: RelationType.supports));
    expect((await store.allEdges()).length, 1);
    await store.close();
  });

  test('epistemic graph: edges + provenance round-trip on a fresh v3 db',
      () async {
    final store = SqliteEideticStore(path: p.join(tempDir.path, 'graph.db'));
    await store.initialize();

    final a = await store.insertFact(SemanticFact(
        createdUtc: DateTime.now().toUtc(),
        category: SemanticCategory.fact,
        text: 'claim A'));
    final b = await store.insertFact(SemanticFact(
        createdUtc: DateTime.now().toUtc(),
        category: SemanticCategory.fact,
        text: 'claim B'));
    expect(a, isNotNull);
    expect(b, isNotNull);

    await store.addEdge(RelationEdge(
        fromFact: a!, toFact: b!, type: RelationType.supports, weight: 0.9));
    await store.addProvenance(a, 42);

    final edges = await store.allEdges();
    expect(edges.length, 1);
    expect(edges.first.fromFact, a);
    expect(edges.first.toFact, b);
    expect(edges.first.type, RelationType.supports);
    expect(edges.first.weight, closeTo(0.9, 1e-9));

    final fetched = await store.factsByIds([a, b]);
    expect(fetched.map((f) => f.id).toSet(), {a, b});
    // New claim columns present with their defaults.
    expect(fetched.first.status, ClaimStatus.active);
    expect(fetched.first.salience, 0.5);
    await store.close();
  });
}
