import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'eidetic_store.dart';
import 'event_records.dart';
import 'memory_records.dart';

/// Native (dart:io) factory: a SQLite-backed store. Selected via conditional
/// import from `eidetic_store.dart`.
EideticStore createEideticStore() => SqliteEideticStore();

/// SQLite-backed [EideticStore] for Android/iOS/macOS/Linux/Windows.
///
/// On Linux/Windows it initialises the FFI database factory; on the other
/// native platforms sqflite's default plugin factory is used. The database
/// lives next to the app's documents directory as `eidetic_memory_dojo.db`.
class SqliteEideticStore implements EideticStore {
  Database? _db;

  @override
  bool get isPersistent => true;

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('EideticStore.initialize() has not completed.');
    }
    return db;
  }

  @override
  Future<void> initialize() async {
    if (_db != null) return;

    // Desktop platforms need the FFI factory wired up explicitly.
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'eidetic_memory_dojo.db');

    _db = await openDatabase(
      path,
      // v2 adds the append-only, sensor-anchored event_log table (Phase 1).
      version: 2,
      onConfigure: (db) async {
        // Write-Ahead Logging: durable, low-latency appends for the event log.
        await db.execute('PRAGMA journal_mode=WAL;');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Migrations for databases created by an older app version. Runs in order;
  /// each step is idempotent-safe via CREATE TABLE IF NOT EXISTS so a partial
  /// upgrade can be re-applied without error.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createEventLog(db);
    }
  }

  /// The append-only event log (Phase 1 grounding spine). Created for fresh
  /// installs in [_onCreate] and back-filled for upgrades in [_onUpgrade].
  Future<void> _createEventLog(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS event_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp_utc TEXT NOT NULL,
        timestamp_millis INTEGER NOT NULL,
        source TEXT NOT NULL,
        type TEXT NOT NULL,
        payload_json TEXT,
        parent_events_json TEXT,
        sensor_state_json TEXT NOT NULL,
        session_id TEXT NOT NULL,
        monotonic_ms INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_event_session ON event_log(session_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_event_millis ON event_log(timestamp_millis)');
  }

  Future<void> _onCreate(Database db, int version) async {
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
    await db.execute(
        'CREATE INDEX idx_episodic_consolidated ON episodic_log(consolidated)');
    await db.execute(
        'CREATE INDEX idx_episodic_session ON episodic_log(session_id, sequence)');

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
    await db.execute(
        'CREATE INDEX idx_facts_category ON semantic_facts(category)');

    await _createEventLog(db);
  }

  @override
  Future<int> nextSequence(String sessionId) async {
    final rows = await _database.rawQuery(
      'SELECT COALESCE(MAX(sequence), 0) + 1 AS next '
      'FROM episodic_log WHERE session_id = ?',
      [sessionId],
    );
    return (rows.first['next'] as num).toInt();
  }

  @override
  Future<int> insertEpisodic(EpisodicEntry entry) async {
    return _database.insert('episodic_log', entry.toRow());
  }

  @override
  Future<List<EpisodicEntry>> recentEpisodic(
      {String? sessionId, int limit = 50}) async {
    final rows = await _database.query(
      'episodic_log',
      where: sessionId == null ? null : 'session_id = ?',
      whereArgs: sessionId == null ? null : [sessionId],
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(EpisodicEntry.fromRow).toList();
  }

  @override
  Future<List<EpisodicEntry>> pendingEpisodic({int limit = 200}) async {
    final rows = await _database.query(
      'episodic_log',
      where: 'consolidated = 0',
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(EpisodicEntry.fromRow).toList();
  }

  @override
  Future<int> pendingCount() async {
    final rows = await _database
        .rawQuery('SELECT COUNT(*) AS c FROM episodic_log WHERE consolidated = 0');
    return (rows.first['c'] as num).toInt();
  }

  @override
  Future<void> markConsolidated(List<int> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await _database.rawUpdate(
      'UPDATE episodic_log SET consolidated = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  @override
  Future<bool> insertFact(SemanticFact fact) async {
    final id = await _database.insert(
      'semantic_facts',
      fact.toRow(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    // insert() returns 0 when the row was ignored due to the UNIQUE dedupe_hash.
    return id != 0;
  }

  @override
  Future<List<SemanticFact>> searchFacts(String query, {int limit = 8}) async {
    final tokens = tokenizeQuery(query);
    if (tokens.isEmpty) return recentFacts(limit: limit);

    final clause = tokens.map((_) => 'LOWER(text) LIKE ?').join(' OR ');
    final args = tokens.map((t) => '%$t%').toList();
    final rows = await _database.query(
      'semantic_facts',
      where: clause,
      whereArgs: args,
      orderBy: 'confidence DESC, created_utc DESC',
      limit: limit,
    );
    return rows.map(SemanticFact.fromRow).toList();
  }

  @override
  Future<List<SemanticFact>> recentFacts({int limit = 50}) async {
    final rows = await _database.query(
      'semantic_facts',
      orderBy: 'created_utc DESC',
      limit: limit,
    );
    return rows.map(SemanticFact.fromRow).toList();
  }

  @override
  Future<int> factCount() async {
    final rows =
        await _database.rawQuery('SELECT COUNT(*) AS c FROM semantic_facts');
    return (rows.first['c'] as num).toInt();
  }

  @override
  Future<int> appendEvent(AppEvent event) async {
    return _database.insert('event_log', event.toRow());
  }

  @override
  Future<List<AppEvent>> recentEvents({int limit = 100}) async {
    final rows = await _database.query(
      'event_log',
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(AppEvent.fromRow).toList();
  }

  @override
  Future<int> eventCount() async {
    final rows =
        await _database.rawQuery('SELECT COUNT(*) AS c FROM event_log');
    return (rows.first['c'] as num).toInt();
  }

  @override
  Future<void> updateFact(int id,
      {String? text, SemanticCategory? category, double? confidence}) async {
    final values = <String, Object?>{};
    if (text != null) {
      values['text'] = text;
      values['dedupe_hash'] = stableContentHash(text);
    }
    if (category != null) values['category'] = category.name;
    if (confidence != null) values['confidence'] = confidence;
    if (values.isEmpty) return;
    await _database
        .update('semantic_facts', values, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteFact(int id) async {
    await _database.delete('semantic_facts', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> updateEpisodicContent(int id, String content) async {
    await _database.update('episodic_log', {'content': content},
        where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteEpisodic(int id) async {
    await _database.delete('episodic_log', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> clearAll() async {
    await _database.delete('episodic_log');
    await _database.delete('semantic_facts');
    await _database.delete('event_log');
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
