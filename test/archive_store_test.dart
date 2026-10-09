import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:portable_ai_flutter/core/memory/archive_chain.dart';
import 'package:portable_ai_flutter/core/memory/eidetic_store_io.dart';
import 'package:portable_ai_flutter/core/memory/eidetic_memory_engine.dart';

void main() {
  setUpAll(() {
    // The real SQLite open/migrate path, via FFI, with no path_provider plugin.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('archive round-trips through the SQLite store and verifies intact', () async {
    final store = SqliteEideticStore(path: inMemoryDatabasePath);
    await store.initialize();

    expect(await store.archiveCount(), 0);
    expect(await store.archiveTip(), isNull);

    // Build a 3-link chain the way the engine does, off the genesis.
    var prev = kArchiveGenesisHash;
    for (var i = 0; i < 3; i++) {
      final e = nextEntry(
        seq: i,
        prevHash: prev,
        timestampUtc: '2026-10-08T00:0$i:00',
        role: i.isEven ? 'user' : 'assistant',
        content: 'turn $i',
      );
      await store.appendArchiveEntry(e);
      prev = e.hash;
    }

    expect(await store.archiveCount(), 3);
    final tip = await store.archiveTip();
    expect(tip, isNotNull);
    expect(tip!.seq, 2);

    final loaded = await store.loadArchive();
    expect(loaded.length, 3);
    final v = verifyChain(loaded);
    expect(v.ok, true, reason: v.reason);
    expect(v.verified, 3);

    await store.close();
  });

  test('engine.archiveTurn chains + persists; verifyArchive confirms it', () async {
    final engine =
        EideticMemoryEngine(store: SqliteEideticStore(path: inMemoryDatabasePath));
    await engine.init();

    // A fresh archive is vacuously intact and recorded on boot.
    expect(engine.lastArchiveCheck, isNotNull);
    expect(engine.lastArchiveCheck!.ok, true);

    final a = await engine.archiveTurn(role: 'user', content: 'hello');
    expect(a.seq, 0);
    expect(a.prevHash, kArchiveGenesisHash);
    final b = await engine.archiveTurn(role: 'assistant', content: 'hi there');
    expect(b.seq, 1);
    expect(b.prevHash, a.hash); // chained off the previous tip

    expect(await engine.archiveCount(), 2);
    final v = await engine.verifyArchive();
    expect(v.ok, true, reason: v.reason);
    expect(v.verified, 2);
  });
}
