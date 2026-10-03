import 'dart:async';
import 'dart:io' show Platform;

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Shared, fully-native sensor sampler for the Monitor tab. Reads only real
/// on-device data — nothing is ever simulated. A reading that can't be obtained
/// is simply absent, and the UI renders it as "no socket".
///
/// For each tile it publishes a formatted display string in [readings], a raw
/// numeric in [nums] (so cards can draw a meter), and a timestamp in [_stamps]
/// (so the UI can verify each sensor is actively operating). No runtime
/// permissions are required for anything here.
class SensorService {
  static const double _radToDeg = 57.2957795131;
  static const MethodChannel _stats = MethodChannel('aether/stats');

  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];

  final Map<String, String> _readings = <String, String>{};
  final Map<String, double> _nums = <String, double>{};
  final Map<String, int> _stamps = <String, int>{};

  Timer? _pumpFast;
  Timer? _pumpSlow;
  bool _running = false;
  int? _batLevel;
  bool? _charging;

  final ValueNotifier<double?> cpuPct = ValueNotifier<double?>(null);
  final ValueNotifier<double?> ramPct = ValueNotifier<double?>(null);
  final ValueNotifier<int?> batteryPct = ValueNotifier<int?>(null);
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  Map<String, String> get readings => _readings;
  double? numOf(String id) => _nums[id];
  int? stampOf(String id) => _stamps[id];

  void _put(String id, String display, [double? value]) {
    _readings[id] = display;
    _stamps[id] = DateTime.now().millisecondsSinceEpoch;
    if (value != null) _nums[id] = value;
  }

  void start() {
    if (_running) return;
    _running = true;

    try {
      _subs.add(accelerometerEventStream(
              samplingPeriod: SensorInterval.gameInterval)
          .listen((e) {
        _put('ax', '${e.x.toStringAsFixed(2)} m/s²', e.x);
        _put('ay', '${e.y.toStringAsFixed(2)} m/s²', e.y);
        _put('az', '${e.z.toStringAsFixed(2)} m/s²', e.z);
      }, onError: (_) {}));
    } catch (_) {}

    try {
      _subs.add(gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval)
          .listen((e) {
        _put('gx', '${(e.x * _radToDeg).toStringAsFixed(1)} °/s', e.x * _radToDeg);
        _put('gy', '${(e.y * _radToDeg).toStringAsFixed(1)} °/s', e.y * _radToDeg);
        _put('gz', '${(e.z * _radToDeg).toStringAsFixed(1)} °/s', e.z * _radToDeg);
      }, onError: (_) {}));
    } catch (_) {}

    try {
      _subs.add(_connectivity.onConnectivityChanged
          .listen(_applyConnectivity, onError: (_) {}));
      _connectivity.checkConnectivity().then(_applyConnectivity).catchError((_) {});
    } catch (_) {}

    try {
      _subs.add(_battery.onBatteryStateChanged.listen((s) {
        _charging = (s == BatteryState.charging || s == BatteryState.full);
      }, onError: (_) {}));
    } catch (_) {}

    _pumpFast = Timer.periodic(const Duration(milliseconds: 40), (_) async {
      await _pollFast();
      tick.value = tick.value + 1;
    });
    _pumpSlow = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _pollSlow();
      try {
        _batLevel = await _battery.batteryLevel;
        batteryPct.value = _batLevel;
      } catch (_) {}
      if (_batLevel != null) _put('batl', '$_batLevel %', _batLevel!.toDouble());
      if (_charging != null) _put('batc', _charging! ? 'Yes' : 'No', _charging! ? 1 : 0);
    });
  }

  Future<void> _pollFast() async {
    try {
      final res = await _stats.invokeMethod<Map<dynamic, dynamic>>('readFast');
      if (res == null) return;
      final m = res.cast<String, dynamic>();
      _orientation(m);
      _environment(m);
    } catch (_) {}
  }

  Future<void> _pollSlow() async {
    try {
      final res = await _stats.invokeMethod<Map<dynamic, dynamic>>('read');
      if (res == null) return;
      final m = res.cast<String, dynamic>();

      _put('cores', '${Platform.numberOfProcessors}');

      final cpu = _d(m['cpu']);
      if (cpu != null) {
        _put('cpuapp', '${cpu.round()} %', cpu);
        cpuPct.value = cpu;
      }

      final used = _d(m['ramUsedMb']);
      final total = _d(m['ramTotalMb']);
      if (used != null && total != null && total > 0) {
        final pct = used / total * 100.0;
        _put('ramu', '${(used / 1024).toStringAsFixed(1)} GB', pct);
        _put('dmem', '${(total / 1024).toStringAsFixed(0)} GB');
        ramPct.value = pct;
      }

      final thermal = _i(m['thermal']);
      if (thermal != null) _put('therm', _thermalLabel(thermal), thermal.toDouble());

      final tC = _d(m['batteryTempC']);
      if (tC != null) _put('batt', '${tC.toStringAsFixed(1)} °C', tC);
      final mv = _d(m['batteryVoltageMv']);
      if (mv != null) _put('batv', '${(mv / 1000).toStringAsFixed(2)} V', mv / 1000);
      final ua = _d(m['batteryCurrentUa']);
      if (ua != null) _put('batcur', '${(ua / 1000).round()} mA', ua / 1000);

      final freeGb = _d(m['storageFreeGb']);
      final totGb = _d(m['storageTotalGb']);
      if (freeGb != null) {
        final usedPct = (totGb != null && totGb > 0) ? (1 - freeGb / totGb) * 100 : null;
        _put('storf', '${freeGb.toStringAsFixed(0)} GB', usedPct);
      }

      final up = _d(m['uptimeMs']);
      if (up != null) _put('uptime', '${(up / 3600000).toStringAsFixed(1)} h');

      _orientation(m);
      _environment(m);
    } catch (_) {}
  }

  void _orientation(Map<String, dynamic> m) {
    final c = _d(m['compassDeg']);
    if (c != null) _put('compass', '${c.round()} °', c);
    final p = _d(m['pitchDeg']);
    if (p != null) _put('tiltb', '${p.round()} °', p);
    final r = _d(m['rollDeg']);
    if (r != null) _put('tiltg', '${r.round()} °', r);
  }

  void _environment(Map<String, dynamic> m) {
    final lux = _d(m['lightLux']);
    if (lux != null) _put('lux', '${lux.round()} lux', lux);
    final prox = _d(m['proximityCm']);
    if (prox != null) _put('prox', prox < 5 ? 'near' : 'far', prox < 5 ? 1 : 0);
    final press = _d(m['pressureHpa']);
    if (press != null) _put('press', '${press.round()} hPa', press);
  }

  void _applyConnectivity(dynamic result) {
    final List<ConnectivityResult> list;
    if (result is List<ConnectivityResult>) {
      list = result;
    } else if (result is ConnectivityResult) {
      list = <ConnectivityResult>[result];
    } else {
      list = const <ConnectivityResult>[];
    }
    final online = list.isNotEmpty && list.any((r) => r != ConnectivityResult.none);
    _put('online', online ? 'online' : 'offline', online ? 1 : 0);
    if (list.isNotEmpty) {
      final t = list.first;
      _put(
          'ntype',
          switch (t) {
            ConnectivityResult.wifi => 'wifi',
            ConnectivityResult.mobile => 'cellular',
            ConnectivityResult.ethernet => 'ethernet',
            ConnectivityResult.vpn => 'vpn',
            ConnectivityResult.bluetooth => 'bluetooth',
            ConnectivityResult.none => 'none',
            _ => t.name,
          });
    }
  }

  static String _thermalLabel(int s) {
    const labels = ['NONE', 'LIGHT', 'MODERATE', 'SEVERE', 'CRITICAL', 'EMERGENCY', 'SHUTDOWN'];
    return (s >= 0 && s < labels.length) ? labels[s] : 'NONE';
  }

  static double? _d(dynamic v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
  static int? _i(dynamic v) =>
      v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _pumpFast?.cancel();
    _pumpFast = null;
    _pumpSlow?.cancel();
    _pumpSlow = null;
    _running = false;
  }

  void dispose() => stop();
}
