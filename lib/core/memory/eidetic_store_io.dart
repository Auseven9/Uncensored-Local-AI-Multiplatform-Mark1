import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'eidetic_store.dart';
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
      version: 1,
      onCreate: _onCreate,
    );
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
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
