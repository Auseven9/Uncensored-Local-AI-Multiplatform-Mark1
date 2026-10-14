import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'research_records.dart';

/// On-machine store for the Research Corpus — the user's web-procured knowledge
/// library. SQLite, separate from `eidetic_memory_dojo.db` (ALESIS's own
/// memory). High-level shape: topics → runs → findings → sources.
///
/// [path] overrides the DB location; production leaves it null (app documents
/// dir / `research_corpus.db`); tests pass a temp file or `inMemoryDatabasePath`
/// so the real open/migrate/query path runs without the path_provider plugin.
class ResearchStore {
  ResearchStore({String? path}) : _pathOverride = path;

  final String? _pathOverride;
  Database? _db;

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('ResearchStore.initialize() has not completed.');
    }
    return db;
  }

  Future<void> initialize() async {
    if (_db != null) return;
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final String path;
    if (_pathOverride != null) {
      path = _pathOverride;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = p.join(dir.path, 'research_corpus.db');
    }
    _db = await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE topics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        slug TEXT NOT NULL UNIQUE,
        summary TEXT NOT NULL DEFAULT '',
        created_utc TEXT NOT NULL,
        updated_utc TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        topic_id INTEGER NOT NULL,
        prompt TEXT NOT NULL,
        turns_budget INTEGER NOT NULL,
        turns_used INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'running',
        created_utc TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE findings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        topic_id INTEGER NOT NULL,
        run_id INTEGER,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        created_utc TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        finding_id INTEGER NOT NULL,
        url TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        snippet TEXT NOT NULL DEFAULT '',
        fetched_utc TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_runs_topic ON runs(topic_id)');
    await db.execute('CREATE INDEX idx_findings_topic ON findings(topic_id)');
    await db.execute('CREATE INDEX idx_sources_finding ON sources(finding_id)');
  }

  String _now() => DateTime.now().toUtc().toIso8601String();

  // ── Topics ──────────────────────────────────────────────────

  /// Create the topic or return the existing one (dedupe by slug); refreshes
  /// `updated_utc`, and `summary` when a non-empty one is supplied. Returns id.
  Future<int> upsertTopic(String name, {String summary = ''}) async {
    final slug = ResearchTopic.slugify(name);
    final now = _now();
    final existing = await _database
        .query('topics', where: 'slug = ?', whereArgs: [slug], limit: 1);
    if (existing.isNotEmpty) {
      final id = (existing.first['id'] as num).toInt();
      await _database.update(
        'topics',
        {
          'updated_utc': now,
          if (summary.trim().isNotEmpty) 'summary': summary,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    return _database.insert('topics', {
      'name': name,
      'slug': slug,
      'summary': summary,
      'created_utc': now,
      'updated_utc': now,
    });
  }

  Future<List<ResearchTopic>> topics({int limit = 200}) async {
    final rows = await _database.query('topics',
        orderBy: 'updated_utc DESC', limit: limit);
    return rows.map(ResearchTopic.fromRow).toList();
  }

  Future<ResearchTopic?> topicById(int id) async {
    final rows =
        await _database.query('topics', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ResearchTopic.fromRow(rows.first);
  }

  // ── Runs ────────────────────────────────────────────────────

  Future<int> startRun(ResearchRun run) async =>
      _database.insert('runs', run.toRow());

  Future<void> finishRun(int id,
      {required String status, required int turnsUsed}) async {
    await _database.update('runs', {'status': status, 'turns_used': turnsUsed},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ResearchRun>> runs({int? topicId, int limit = 100}) async {
    final rows = await _database.query(
      'runs',
      where: topicId == null ? null : 'topic_id = ?',
      whereArgs: topicId == null ? null : [topicId],
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(ResearchRun.fromRow).toList();
  }

  // ── Findings ────────────────────────────────────────────────

  Future<int> addFinding(ResearchFinding f) async =>
      _database.insert('findings', f.toRow());

  Future<List<ResearchFinding>> findings(
      {required int topicId, int limit = 500}) async {
    final rows = await _database.query('findings',
        where: 'topic_id = ?',
        whereArgs: [topicId],
        orderBy: 'id DESC',
        limit: limit);
    return rows.map(ResearchFinding.fromRow).toList();
  }

  // ── Sources ─────────────────────────────────────────────────

  Future<int> addSource(ResearchSource s) async =>
      _database.insert('sources', s.toRow());

  Future<List<ResearchSource>> sources({required int findingId}) async {
    final rows = await _database.query('sources',
        where: 'finding_id = ?', whereArgs: [findingId], orderBy: 'id ASC');
    return rows.map(ResearchSource.fromRow).toList();
  }

  // ── Counts / maintenance ────────────────────────────────────

  Future<int> topicCount() async =>
      (await _database.rawQuery('SELECT COUNT(*) AS c FROM topics'))
          .first['c'] as int;

  Future<int> findingCount() async =>
      (await _database.rawQuery('SELECT COUNT(*) AS c FROM findings'))
          .first['c'] as int;

  Future<void> clearAll() async {
    await _database.delete('sources');
    await _database.delete('findings');
    await _database.delete('runs');
    await _database.delete('topics');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
