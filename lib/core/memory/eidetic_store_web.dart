import 'eidetic_store.dart';

/// Web fallback: sqflite/FFI are unavailable in the browser, so the Eidetic
/// ledger runs in memory. Selected via conditional import from
/// `eidetic_store.dart` when `dart:io` is absent.
EideticStore createEideticStore() => InMemoryEideticStore();
