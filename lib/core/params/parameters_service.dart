import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'param_spec.dart';

/// Central, persisted, reactive store for every AETHER parameter.
///
/// Every subsystem reads its knobs from here (`getDouble('spreading.alpha')`
/// etc.). Values are stored as overrides on top of the registry defaults, so a
/// key that has never been changed always resolves to its [ParamSpec.def].
class ParametersService extends GetxService {
  Box get _box => Hive.box('settings');
  static const _storeKey = 'aether_params';

  /// Overridden values only (key → value). Reactive.
  final values = <String, dynamic>{}.obs;

  ParametersService init() {
    final stored = _box.get(_storeKey);
    if (stored is Map) {
      values.assignAll(Map<String, dynamic>.from(stored));
    }
    return this;
  }

  ParamSpec? spec(String key) {
    for (final p in aetherParamRegistry) {
      if (p.key == key) return p;
    }
    return null;
  }

  Object? _raw(String key) {
    if (values.containsKey(key)) return values[key];
    return spec(key)?.def;
  }

  double getDouble(String key) => ((_raw(key) as num?)?.toDouble()) ?? 0.0;
  int getInt(String key) => ((_raw(key) as num?)?.toInt()) ?? 0;
  bool getBool(String key) => (_raw(key) as bool?) ?? false;
  String getString(String key) => _raw(key)?.toString() ?? '';

  bool isOverridden(String key) => values.containsKey(key);

  void set(String key, dynamic value) {
    values[key] = value;
    _persist();
  }

  void reset(String key) {
    if (values.remove(key) != null) _persist();
  }

  void resetAll() {
    values.clear();
    _persist();
  }

  /// Distinct groups in registry order.
  List<String> get groups {
    final seen = <String>[];
    for (final p in aetherParamRegistry) {
      if (!seen.contains(p.group)) seen.add(p.group);
    }
    return seen;
  }

  void _persist() {
    try {
      _box.put(_storeKey, Map<String, dynamic>.from(values));
    } catch (_) {
      // Non-fatal: settings persistence best-effort.
    }
  }
}
