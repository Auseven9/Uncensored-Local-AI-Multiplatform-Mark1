import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Shared, fully-native sensor sampler for the Monitor tab.
///
/// A single Kotlin [EventChannel] (`aether/stream`) pushes a combined sensor
/// frame ~60×/second: every motion/orientation/environment sensor sampled at
/// the fastest rate the hardware allows, plus derived values (magnitudes, jerk,
/// altitude, fusion states) and per-second system telemetry (CPU, battery,
/// thermal, network, display, audio). There are no Flutter sensor plugins —
/// the native layer is the single source of truth.
///
/// Every value is a genuine hardware reading or an exact derivation of one.
/// Anything the device/OS does not expose is simply absent from the frame, so
/// the UI renders it as "no socket". Nothing is ever simulated.
///
/// For each tile it publishes a formatted display string in [readings], a raw
/// numeric in [nums] (so cards can draw a meter), and a timestamp in [_stamps]
/// (so the UI can verify each sensor is actively operating).
/// Liveness/identity of a single hardware sensor, for the on-card verifier.
class SensorHealth {
  final String name; // vendor model string, e.g. "LSM6DSO Accelerometer"
  final bool present; // hardware exists on this device
  final int ageMs; // ms since the last event (-1 if absent)
  final int accuracy; // -1 unknown, 0 unreliable, 1 low, 2 med, 3 high
  final bool alive; // present and (for streaming sensors) delivering fresh data
  const SensorHealth({
    required this.name,
    required this.present,
    required this.ageMs,
    required this.accuracy,
    required this.alive,
  });
}

class SensorService {
  static const double _radToDeg = 57.2957795131;
  static const EventChannel _stream = EventChannel('aether/stream');

  // Streaming sensors should deliver continuously; on-change ones (light,
  // proximity, pressure, ambient) legitimately go quiet, so they are "alive"
  // whenever present rather than by recency.
  static const Set<String> _streaming = {'accel', 'lin', 'grav', 'gyro', 'mag', 'rot'};
  final Map<String, SensorHealth> health = <String, SensorHealth>{};
  SensorHealth? healthOf(String key) => health[key];

  StreamSubscription<dynamic>? _sub;
  bool _running = false;

  final Map<String, String> _readings = <String, String>{};
  final Map<String, double> _nums = <String, double>{};
  final Map<String, int> _stamps = <String, int>{};

  // Live rotation matrix (9) from the fused rotation vector — drives the 3D
  // orientation phone. Null until the sensor delivers a frame.
  final ValueNotifier<List<double>?> rot = ValueNotifier<List<double>?>(null);

  // Rolling histories for the live graphs (last N samples).
  static const int _histLen = 90;
  final List<double> accelHist = <double>[]; // |a| m/s²
  final List<double> gyroHist = <double>[]; // |ω| °/s
  final List<double> cpuHist = <double>[]; // app CPU %
  final List<double> downHist = <double>[]; // KB/s down
  final List<double> upHist = <double>[]; // KB/s up

  void _push(List<double> buf, double v) {
    buf.add(v);
    if (buf.length > _histLen) buf.removeAt(0);
  }

  // Gauge rings.
  final ValueNotifier<double?> cpuPct = ValueNotifier<double?>(null);
  final ValueNotifier<double?> ramPct = ValueNotifier<double?>(null);
  final ValueNotifier<int?> batteryPct = ValueNotifier<int?>(null);
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  int coreCount = Platform.numberOfProcessors;

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
      _sub = _stream.receiveBroadcastStream().listen(
        (dynamic frame) {
          if (frame is Map) _apply(frame.cast<dynamic, dynamic>());
          tick.value = tick.value + 1;
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {
      _running = false;
    }
  }

  void _apply(Map<dynamic, dynamic> raw) {
    final m = <String, dynamic>{};
    raw.forEach((k, v) => m[k.toString()] = v);

    // ── Motion: accelerometer ──
    _d2(m['ax'], 'ax', (v) => '${v.toStringAsFixed(3)} m/s²');
    _d2(m['ay'], 'ay', (v) => '${v.toStringAsFixed(3)} m/s²');
    _d2(m['az'], 'az', (v) => '${v.toStringAsFixed(3)} m/s²');
    _d2(m['amag'], 'amag', (v) => '${v.toStringAsFixed(3)} m/s²');
    _d2(m['jerk'], 'jerk', (v) => '${v.toStringAsFixed(2)} m/s³');
    _d2(m['lax'], 'lax', (v) => '${v.toStringAsFixed(3)} m/s²');
    _d2(m['lay'], 'lay', (v) => '${v.toStringAsFixed(3)} m/s²');
    _d2(m['laz'], 'laz', (v) => '${v.toStringAsFixed(3)} m/s²');
    _d2(m['lmag'], 'lmag', (v) => '${v.toStringAsFixed(3)} m/s²');
    _d2(m['grx'], 'grx', (v) => '${v.toStringAsFixed(3)} m/s²');
    _d2(m['gry'], 'gry', (v) => '${v.toStringAsFixed(3)} m/s²');
    _d2(m['grz'], 'grz', (v) => '${v.toStringAsFixed(3)} m/s²');
    _d2(m['incl'], 'incl', (v) => '${v.toStringAsFixed(1)} °');
    _d2(m['menergy'], 'menergy', (v) => v.toStringAsFixed(2));

    // ── Motion: gyroscope (native rad/s → °/s) ──
    _deg(m['gx'], 'gx');
    _deg(m['gy'], 'gy');
    _deg(m['gz'], 'gz');
    _deg(m['gmag'], 'gmag');

    // ── Magnetometer ──
    _d2(m['mx'], 'mx', (v) => '${v.toStringAsFixed(1)} µT');
    _d2(m['my'], 'my', (v) => '${v.toStringAsFixed(1)} µT');
    _d2(m['mz'], 'mz', (v) => '${v.toStringAsFixed(1)} µT');
    _d2(m['bmag'], 'bmag', (v) => '${v.toStringAsFixed(1)} µT');
    _d2(m['dip'], 'dip', (v) => '${v.toStringAsFixed(1)} °');

    // ── Orientation (fused rotation vector) ──
    _d2(m['compass'], 'compass', (v) => '${v.toStringAsFixed(1)} °');
    _s(m['cardinal'], 'cardinal');
    _d2(m['pitch'], 'pitch', (v) => '${v.toStringAsFixed(1)} °');
    _d2(m['roll'], 'roll', (v) => '${v.toStringAsFixed(1)} °');
    _s(m['pose'], 'pose');
    final r = m['rot'];
    if (r is List && r.length == 9) {
      rot.value = r.map((e) => (e as num).toDouble()).toList(growable: false);
    }

    // ── Environment ──
    _d2(m['lux'], 'lux', (v) => '${v.toStringAsFixed(0)} lux');
    _s(m['lightcat'], 'lightcat');
    final prox = _toD(m['prox']);
    if (prox != null) _put('prox', prox < 5 ? 'near' : 'far', prox < 5 ? 1 : 0);
    _d2(m['press'], 'press', (v) => '${v.toStringAsFixed(2)} hPa');
    _d2(m['alt'], 'alt', (v) => '${v.toStringAsFixed(1)} m');
    _d2(m['vspeed'], 'vspeed', (v) => '${v.toStringAsFixed(2)} m/s');
    _d2(m['floors'], 'floors', (v) => v.toStringAsFixed(1));
    _s(m['ptrend'], 'ptrend');
    _d2(m['atemp'], 'atemp', (v) => '${v.toStringAsFixed(1)} °C');
    _d2(m['humid'], 'humid', (v) => '${v.toStringAsFixed(0)} %');
    _s(m['hall'], 'hall');

    // ── Fusion / inferred ──
    _s(m['motionstate'], 'motionstate');
    _int(m['steps'], 'steps', (v) => '$v steps');
    _int(m['cadence'], 'cadence', (v) => '$v /min');
    _int(m['shakes'], 'shakes', (v) => '$v');
    _b(m['freefall'], 'freefall', 'FALLING', 'no');
    _d2(m['vibhz'], 'vibhz', (v) => '${v.toStringAsFixed(1)} Hz');
    _d2(m['jolt'], 'jolt', (v) => '${v.toStringAsFixed(1)} m/s²');

    // ── Compute ──
    final cpu = _toD(m['appcpu']);
    if (cpu != null) {
      _put('cpuapp', '${cpu.toStringAsFixed(1)} %', cpu);
      cpuPct.value = cpu;
      _push(cpuHist, cpu);
    }
    final cores = _toI(m['cores']);
    if (cores != null) {
      coreCount = cores;
      _put('cores', '$cores');
    }
    final cf = m['corefreq'];
    if (cf is List) {
      for (int i = 0; i < cf.length; i++) {
        final v = cf[i];
        final mhz = v is num ? v.toInt() : -1;
        if (mhz >= 0) {
          final ghz = mhz / 1000.0;
          _put('core$i', '${ghz.toStringAsFixed(2)} GHz', mhz.toDouble());
        }
      }
    }
    final used = _toD(m['ramused']);
    final total = _toD(m['ramtotal']);
    final avail = _toD(m['ramavail']);
    if (used != null && total != null && total > 0) {
      final pct = used / total * 100.0;
      _put('ramu', '${(used / 1024).toStringAsFixed(2)} GB', pct);
      ramPct.value = pct;
    }
    if (total != null) _put('dmem', '${(total / 1024).toStringAsFixed(1)} GB');
    if (avail != null) _put('ramfree', '${(avail / 1024).toStringAsFixed(2)} GB', avail);
    _b(m['lowmem'], 'lowmem', 'LOW', 'ok');
    _d2(m['apppss'], 'apppss', (v) => '${v.toStringAsFixed(0)} MB');
    final sf = _toD(m['storfree']);
    final stt = _toD(m['stortotal']);
    if (sf != null) {
      final usedPct = (stt != null && stt > 0) ? (1 - sf / stt) * 100 : null;
      _put('storf', '${sf.toStringAsFixed(1)} GB free', usedPct ?? 0);
    }
    if (stt != null) _put('stort', '${stt.toStringAsFixed(0)} GB');
    final up = _toD(m['uptime']);
    if (up != null) _put('uptime', _dur(up));

    // ── Power / thermal ──
    final bp = _toI(m['batpct']);
    if (bp != null) {
      _put('batl', '$bp %', bp.toDouble());
      batteryPct.value = bp;
    }
    _b(m['batcharging'], 'batc', 'charging', 'no');
    _d2(m['battemp'], 'batt', (v) => '${v.toStringAsFixed(1)} °C');
    _d2(m['batvolt'], 'batv', (v) => '${v.toStringAsFixed(3)} V');
    final cur = _toD(m['batcur']);
    if (cur != null) _put('batcur', '${(cur / 1000).toStringAsFixed(0)} mA', (cur / 1000).abs());
    final cavg = _toD(m['batcuravg']);
    if (cavg != null) _put('batcuravg', '${(cavg / 1000).toStringAsFixed(0)} mA', (cavg / 1000).abs());
    _d2(m['batpower'], 'batpower', (v) => '${v.toStringAsFixed(3)} W');
    _s(m['bathealth'], 'bathealth');
    _s(m['battech'], 'battech');
    _s(m['batplug'], 'batplug');
    _d2(m['chargecounter'], 'chargecounter', (v) => '${v.toStringAsFixed(0)} mAh');
    _d2(m['chargetime'], 'chargetime', (v) => '${v.toStringAsFixed(0)} min');
    _int(m['batcycles'], 'batcycles', (v) => '$v');
    final therm = _toI(m['thermstatus']);
    if (therm != null) _put('therm', _thermalLabel(therm), therm.toDouble());
    _d2(m['thermheadroom'], 'thermhr', (v) => '${(v * 100).toStringAsFixed(0)} %');
    _d2(m['thermmax'], 'thermmax', (v) => '${v.toStringAsFixed(1)} °C');
    _d2(m['thermcpu'], 'thermcpu', (v) => '${v.toStringAsFixed(1)} °C');
    _d2(m['thermbatt'], 'thermbatt', (v) => '${v.toStringAsFixed(1)} °C');
    _d2(m['thermskin'], 'thermskin', (v) => '${v.toStringAsFixed(1)} °C');
    _d2(m['thermgpu'], 'thermgpu', (v) => '${v.toStringAsFixed(1)} °C');

    // ── Network ──
    _b(m['online'], 'online', 'online', 'offline');
    _s(m['nettype'], 'ntype');
    _b(m['metered'], 'metered', 'metered', 'unmetered');
    _b(m['vpn'], 'vpn', 'active', 'off');
    _int(m['linkdown'], 'linkdown', (v) => '${(v / 1000).toStringAsFixed(0)} Mbps');
    _int(m['linkup'], 'linkup', (v) => '${(v / 1000).toStringAsFixed(0)} Mbps');
    final dn = _toD(m['downkbs']);
    if (dn != null) {
      _put('downkbs', '${dn.toStringAsFixed(1)} KB/s', dn);
      _push(downHist, dn);
    }
    final upk = _toD(m['upkbs']);
    if (upk != null) {
      _put('upkbs', '${upk.toStringAsFixed(1)} KB/s', upk);
      _push(upHist, upk);
    }
    _d2(m['rxmb'], 'rxmb', (v) => '${v.toStringAsFixed(1)} MB');
    _d2(m['txmb'], 'txmb', (v) => '${v.toStringAsFixed(1)} MB');

    // ── Display / audio ──
    _d2(m['refresh'], 'refresh', (v) => '${v.toStringAsFixed(0)} Hz');
    final sw = _toI(m['screenw']);
    final sh = _toI(m['screenh']);
    if (sw != null && sh != null) _put('screen', '$sw×$sh');
    _d2(m['density'], 'density', (v) => '${v.toStringAsFixed(1)}×');
    _d2(m['volmedia'], 'volmedia', (v) => '${v.toStringAsFixed(0)} %');
    _d2(m['volring'], 'volring', (v) => '${v.toStringAsFixed(0)} %');
    _s(m['ringer'], 'ringer');
    _b(m['musicactive'], 'music', 'playing', 'idle');
    _s(m['audioout'], 'audioout');

    // ── Sensor health verifier ──
    final sraw = m['sensors'];
    if (sraw is Map) {
      sraw.forEach((k, v) {
        if (v is List && v.length >= 4) {
          final key = k.toString();
          final present = v[1] == true;
          final age = v[2] is num ? (v[2] as num).toInt() : -1;
          final streaming = _streaming.contains(key);
          health[key] = SensorHealth(
            name: v[0]?.toString() ?? '',
            present: present,
            ageMs: age,
            accuracy: v[3] is num ? (v[3] as num).toInt() : -1,
            alive: present && (streaming ? (age >= 0 && age < 4000) : true),
          );
        }
      });
    }

    // ── Live graph histories ──
    final am = _toD(m['amag']);
    if (am != null) {
      accelHist.add(am);
      if (accelHist.length > _histLen) accelHist.removeAt(0);
    }
    final gm = _toD(m['gmag']);
    if (gm != null) {
      gyroHist.add(gm * _radToDeg);
      if (gyroHist.length > _histLen) gyroHist.removeAt(0);
    }
  }

  // ── typed put helpers ──
  void _d2(dynamic v, String id, String Function(double) fmt) {
    final d = _toD(v);
    if (d != null) _put(id, fmt(d), d);
  }

  void _deg(dynamic v, String id) {
    final d = _toD(v);
    if (d != null) {
      final deg = d * _radToDeg;
      _put(id, '${deg.toStringAsFixed(2)} °/s', deg);
    }
  }

  void _int(dynamic v, String id, String Function(int) fmt) {
    final i = _toI(v);
    if (i != null) _put(id, fmt(i), i.toDouble());
  }

  void _s(dynamic v, String id) {
    if (v is String && v.isNotEmpty) _put(id, v);
  }

  void _b(dynamic v, String id, String t, String f) {
    if (v is bool) _put(id, v ? t : f, v ? 1 : 0);
  }

  String _dur(double ms) {
    final s = ms / 1000;
    final h = s ~/ 3600;
    final mn = (s % 3600) ~/ 60;
    if (h > 0) return '${h}h ${mn}m';
    return '${mn}m';
  }

  static String _thermalLabel(int s) {
    const labels = ['none', 'light', 'moderate', 'severe', 'critical', 'emergency', 'shutdown'];
    return (s >= 0 && s < labels.length) ? labels[s] : 'none';
  }

  static double? _toD(dynamic v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
  static int? _toI(dynamic v) =>
      v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);

  void stop() {
    _sub?.cancel();
    _sub = null;
    _running = false;
  }

  void dispose() => stop();
}
