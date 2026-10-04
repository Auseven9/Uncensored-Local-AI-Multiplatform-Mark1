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

/// One entry in the full device sensor inventory (every sensor the HAL exposes,
/// vendor-private included) with its spec and whether we could register it.
class SensorInfo {
  final int type;
  final String name, vendor, stringType, gate;
  final double power, resolution, maxRange;
  final int minDelayUs, reportingMode, ageMs;
  final bool wakeUp, registered;
  const SensorInfo({
    required this.type,
    required this.name,
    required this.vendor,
    required this.stringType,
    required this.power,
    required this.resolution,
    required this.maxRange,
    required this.minDelayUs,
    required this.reportingMode,
    required this.wakeUp,
    required this.registered,
    required this.ageMs,
    required this.gate,
  });

  double get maxHz => minDelayUs > 0 ? 1000000.0 / minDelayUs : 0;
  bool get streaming => registered && ageMs >= 0 && ageMs < 4000;
  String get modeLabel => const ['continuous', 'on-change', 'one-shot', 'special'][
      reportingMode >= 0 && reportingMode < 4 ? reportingMode : 3];

  /// Reachability tier: how deep we actually got.
  String get reach {
    if (streaming) return 'streaming';
    if (registered) return 'armed';
    if (gate.isNotEmpty) return 'needs $gate';
    if (reportingMode == 2) return 'one-shot';
    return 'restricted';
  }
}

/// One capability in the wider device index (an API/subsystem, not just a HAL
/// sensor). status: available | needs-perm | command | sealed | unsupported.
class IndexEntry {
  final String label, status, detail, perm, api;
  const IndexEntry({
    required this.label,
    required this.status,
    required this.detail,
    required this.perm,
    required this.api,
  });
}

class IndexSection {
  final String name;
  final List<IndexEntry> entries;
  const IndexSection({required this.name, required this.entries});
}

/// An event ("fire-and-flash") sensor: tilt, significant-motion, step detector.
/// [armed] = we have a live listener/trigger that can fire it; [count] total
/// fires this session; [ageMs] since the last fire (-1 if never), for the flash.
class EventInfo {
  final bool armed;
  final int count;
  final int ageMs;
  const EventInfo({required this.armed, required this.count, required this.ageMs});
  bool get firedRecently => ageMs >= 0 && ageMs < 700;
}

/// One GNSS satellite from the live sky, for the sky-plot. azimuth/elevation in
/// degrees, C/N0 in dB-Hz (signal strength), constellation type, and whether it
/// is currently used in the position fix. All real, from GnssStatus.
class Sat {
  final double az, el, cn0, constType;
  final bool used;
  const Sat({required this.az, required this.el, required this.cn0, required this.constType, required this.used});
  String get constName {
    switch (constType.toInt()) {
      case 1:
        return 'GPS';
      case 2:
        return 'SBAS';
      case 3:
        return 'GLO';
      case 4:
        return 'QZSS';
      case 5:
        return 'BDS';
      case 6:
        return 'GAL';
      case 7:
        return 'IRNSS';
      default:
        return '?';
    }
  }
}

/// A scanned Wi-Fi access point: RSSI (dBm), frequency (MHz), SSID.
class Ap {
  final int rssi, freq;
  final String ssid;
  const Ap(this.rssi, this.freq, this.ssid);
  String get band => freq >= 5955 ? '6G' : (freq >= 4900 ? '5G' : '2.4G');
}

/// A nearby Bluetooth-LE device: advertised RSSI (dBm) and name (if any).
class BleDev {
  final int rssi;
  final String name;
  const BleDev(this.rssi, this.name);
}

class SensorService {
  static const double _radToDeg = 57.2957795131;
  static const EventChannel _stream = EventChannel('aether/stream');
  static const MethodChannel _index = MethodChannel('aether/index');
  static const MethodChannel _perms = MethodChannel('aether/perms');

  // Runtime permissions each gated capability needs (Android constant strings).
  static const String pMic = 'android.permission.RECORD_AUDIO';
  static const String pCam = 'android.permission.CAMERA';
  static const String pLoc = 'android.permission.ACCESS_FINE_LOCATION';
  static const String pWifi = 'android.permission.NEARBY_WIFI_DEVICES';
  static const String pPhone = 'android.permission.READ_PHONE_STATE';
  static const String pBt = 'android.permission.BLUETOOTH_SCAN';
  static const String pUwb = 'android.permission.UWB_RANGING';
  static const String pAct = 'android.permission.ACTIVITY_RECOGNITION';
  static const List<String> allPerms = [pMic, pCam, pLoc, pWifi, pPhone, pBt, pUwb, pAct];

  // Hardware presence/feature facts (from native buildCaps), and live grant
  // status per runtime permission. The capability board reads both to decide
  // each card's CAPTURED / ENABLE / SEALED state — no fabricated availability.
  Map<String, dynamic> caps = <String, dynamic>{};
  final Map<String, bool> permGranted = <String, bool>{};
  bool granted(String perm) => permGranted[perm] == true;

  /// Presence of a capability by its native caps key (bool / count / string).
  bool capPresent(String key) {
    final v = caps[key];
    if (v is bool) return v;
    if (v is num) return v > 0;
    if (v is String) return v.isNotEmpty;
    return false;
  }

  Future<void> refreshCaps() async {
    try {
      final r = await _index.invokeMethod<Map>('caps');
      if (r != null) caps = r.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {}
  }

  Future<void> refreshPerms([List<String>? perms]) async {
    try {
      final r = await _perms.invokeMethod<Map>('status', {'perms': perms ?? allPerms});
      if (r != null) r.forEach((k, v) => permGranted[k.toString()] = v == true);
    } catch (_) {}
  }

  /// Request a single runtime permission; returns true if granted.
  Future<bool> requestPerm(String perm) async {
    try {
      final r = await _perms.invokeMethod<Map>('request', {'perms': [perm]});
      if (r != null) r.forEach((k, v) => permGranted[k.toString()] = v == true);
    } catch (_) {}
    return granted(perm);
  }

  /// Open this app's system settings page (manual permission unlock fallback).
  Future<bool> openAppSettings() async {
    try {
      return (await _perms.invokeMethod<bool>('openSettings')) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── live control channel: start/stop on-demand streams + actuators ──
  static const MethodChannel _ctl = MethodChannel('aether/ctl');
  Future<bool> micStart() async {
    try {
      return (await _ctl.invokeMethod<bool>('micStart')) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> micStop() async {
    try {
      await _ctl.invokeMethod('micStop');
    } catch (_) {}
  }

  Future<bool> locStart() async {
    try {
      return (await _ctl.invokeMethod<bool>('locStart')) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> locStop() async {
    try {
      await _ctl.invokeMethod('locStop');
    } catch (_) {}
  }

  Future<bool> bleStart() async {
    try {
      return (await _ctl.invokeMethod<bool>('bleStart')) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> bleStop() async {
    try {
      await _ctl.invokeMethod('bleStop');
    } catch (_) {}
  }

  Future<bool> torch(bool on) async {
    try {
      return (await _ctl.invokeMethod<bool>('torch', {'on': on})) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> buzz([int ms = 30]) async {
    try {
      await _ctl.invokeMethod('buzz', {'ms': ms});
    } catch (_) {}
  }

  // ── live stream state (mic / GNSS), updated per frame while running ──
  List<double> micWave = const <double>[];
  double? micDb;
  double? micPeak;
  List<Sat> sats = const <Sat>[];
  int satUsed = 0;
  int satSeen = 0;

  // Radio & Nearby (live): scanned Wi-Fi APs + nearby BLE devices.
  List<Ap> wifiAps = const <Ap>[];
  List<BleDev> bleDevices = const <BleDev>[];

  // Display-only smoothed heading (deg) for the twin/compass dials — the raw
  // heading is preserved in readings/sub-tiles; this just makes the dial glide.
  double? headingDisplay;

  /// One-shot probe of every subsystem/API — what we can tap and where.
  Future<List<IndexSection>> fetchIndex() async {
    try {
      final res = await _index.invokeMethod<List<dynamic>>('full');
      if (res == null) return const [];
      final out = <IndexSection>[];
      for (final sec in res) {
        if (sec is! Map) continue;
        final entries = <IndexEntry>[];
        final raw = sec['entries'];
        if (raw is List) {
          for (final e in raw) {
            if (e is Map) {
              entries.add(IndexEntry(
                label: e['label']?.toString() ?? '',
                status: e['status']?.toString() ?? '',
                detail: e['detail']?.toString() ?? '',
                perm: e['perm']?.toString() ?? '',
                api: e['api']?.toString() ?? '',
              ));
            }
          }
        }
        out.add(IndexSection(name: sec['name']?.toString() ?? '', entries: entries));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  // Full device sensor inventory (populated ~1s from the native probe).
  List<SensorInfo> inventory = const <SensorInfo>[];

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

  // Per-reading liveness record, powering the on-card micro-viz. [_hist] is a
  // short ring of recent numeric values (→ a sparkline that moves while the
  // sensor streams); [_beats] is the epoch-ms of each value CHANGE (→ a pulse
  // lane that ticks when a state reading updates). Both are real: the sparkline
  // is the actual samples, the pulses are the actual update times.
  static const int _histCap = 48;
  static const int _beatCap = 32;
  final Map<String, List<double>> _hist = <String, List<double>>{};
  final Map<String, List<int>> _beats = <String, List<int>>{};
  List<double>? histOf(String id) => _hist[id];
  List<int>? beatsOf(String id) => _beats[id];

  // Event sensors (tilt / significant-motion / step) — fire-and-flash lamps.
  final Map<String, EventInfo> events = <String, EventInfo>{};

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
    final changed = _readings[id] != display;
    final now = DateTime.now().millisecondsSinceEpoch;
    _readings[id] = display;
    _stamps[id] = now;
    if (value != null) {
      _nums[id] = value;
      final h = _hist.putIfAbsent(id, () => <double>[]);
      h.add(value);
      if (h.length > _histCap) h.removeAt(0);
    }
    if (changed) {
      final b = _beats.putIfAbsent(id, () => <int>[]);
      b.add(now);
      if (b.length > _beatCap) b.removeAt(0);
    }
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
    // Probe hardware presence + current permission grants for the capability
    // board (fire-and-forget; the board picks up the maps on the next frame).
    refreshCaps();
    refreshPerms();
  }

  /// Re-probe presence + permissions (used by the Check-Index verification).
  Future<void> recheck() async {
    await refreshCaps();
    await refreshPerms();
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
    _d2(m['magDev'], 'magDev', (v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} µT');
    _d2(m['magDevPct'], 'magDevPct', (v) => '${v.toStringAsFixed(0)} %');
    _s(m['headingTrust'], 'headingTrust');

    // ── Orientation (fused rotation vector) ──
    _d2(m['compass'], 'compass', (v) => '${v.toStringAsFixed(1)} °');
    _s(m['cardinal'], 'cardinal');
    _d2(m['pitch'], 'pitch', (v) => '${v.toStringAsFixed(1)} °');
    _d2(m['roll'], 'roll', (v) => '${v.toStringAsFixed(1)} °');
    _s(m['pose'], 'pose');
    // Geomagnetic corrections (from the GPS fix): true heading + local field.
    _d2(m['trueHeading'], 'trueHeading', (v) => '${v.toStringAsFixed(1)} °');
    _s(m['cardinalTrue'], 'cardinalTrue');
    _d2(m['geoDecl'], 'geoDecl', (v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} °');
    _d2(m['geoField'], 'geoField', (v) => '${v.toStringAsFixed(1)} µT');
    _d2(m['geoIncl'], 'geoIncl', (v) => '${v.toStringAsFixed(1)} °');
    // Display-only smoothed heading (shortest-path circular EMA) for the dials.
    final rawHead = _toD(m['trueHeading']) ?? _toD(m['compass']);
    if (rawHead != null) {
      final cur = headingDisplay;
      if (cur == null) {
        headingDisplay = rawHead;
      } else {
        var diff = rawHead - cur;
        while (diff > 180) diff -= 360;
        while (diff < -180) diff += 360;
        headingDisplay = ((cur + diff * 0.18) % 360 + 360) % 360;
      }
    }
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
    // Samsung optical raw channels — genuine sensor outputs, surfaced raw. Units
    // are device-private (not yet verified), so shown as raw, never mislabelled.
    _d2(m['cct0'], 'cct0', (v) => v.toStringAsFixed(1));
    _d2(m['cct1'], 'cct1', (v) => v.toStringAsFixed(1));
    _d2(m['lightir'], 'lightir', (v) => v.toStringAsFixed(1));

    // ── Event sensors (fire-and-flash) ──
    final eraw = m['events'];
    if (eraw is Map) {
      eraw.forEach((k, v) {
        if (v is List && v.length >= 3) {
          events[k.toString()] = EventInfo(
            armed: v[0] == true,
            count: v[1] is num ? (v[1] as num).toInt() : 0,
            ageMs: v[2] is num ? (v[2] as num).toInt() : -1,
          );
        }
      });
    }

    // ── Microphone (live) ──
    final md = _toD(m['micDb']);
    if (md != null) {
      micDb = md;
      micPeak = _toD(m['micPeak']);
      _put('micDb', '${md.toStringAsFixed(1)} dBFS', md);
      final mw = m['micWave'];
      if (mw is List) micWave = mw.map((e) => (e as num).toDouble()).toList(growable: false);
    } else {
      micDb = null;
      micPeak = null;
      micWave = const <double>[];
    }

    // ── Location / GNSS (live) ──
    _d2(m['lat'], 'lat', (v) => v.toStringAsFixed(5));
    _d2(m['lon'], 'lon', (v) => v.toStringAsFixed(5));
    _d2(m['gpsAlt'], 'gpsAlt', (v) => '${v.toStringAsFixed(1)} m');
    _d2(m['gpsSpeed'], 'gpsSpeed', (v) => '${v.toStringAsFixed(1)} m/s');
    _d2(m['gpsBearing'], 'gpsBearing', (v) => '${v.toStringAsFixed(0)} °');
    _d2(m['gpsAcc'], 'gpsAcc', (v) => '± ${v.toStringAsFixed(0)} m');
    _s(m['gpsProvider'], 'gpsProvider');
    final su = _toI(m['satUsed']);
    if (su != null) {
      satUsed = su;
      _put('satUsed', '$su', su.toDouble());
    }
    final ss = _toI(m['satSeen']);
    if (ss != null) {
      satSeen = ss;
      _put('satSeen', '$ss', ss.toDouble());
    }
    final sr = m['sats'];
    if (sr is List) {
      final list = <Sat>[];
      for (final e in sr) {
        if (e is List && e.length >= 5) {
          list.add(Sat(
            az: (e[0] as num).toDouble(),
            el: (e[1] as num).toDouble(),
            cn0: (e[2] as num).toDouble(),
            constType: (e[3] as num).toDouble(),
            used: (e[4] as num) > 0,
          ));
        }
      }
      sats = list;
    } else if (m['satSeen'] == null) {
      sats = const <Sat>[];
      satUsed = 0;
      satSeen = 0;
    }

    // ── Radio & Nearby (live; scans refresh ~1s, so keep last between frames) ──
    _d2(m['wifiRssi'], 'wifiRssi', (v) => '${v.toStringAsFixed(0)} dBm');
    _d2(m['wifiSpeed'], 'wifiSpeed', (v) => '${v.toStringAsFixed(0)} Mbps');
    _s(m['wifiBand'], 'wifiBand');
    _d2(m['cellDbm'], 'cellDbm', (v) => '${v.toStringAsFixed(0)} dBm');
    _int(m['cellLevel'], 'cellLevel', (v) => '$v/4');
    _s(m['cellType'], 'cellType');
    _int(m['bleCount'], 'bleCount', (v) => '$v');
    final ar = m['wifiAps'];
    if (ar is List) {
      final list = <Ap>[];
      for (final e in ar) {
        if (e is List && e.length >= 3) {
          list.add(Ap((e[0] as num).toInt(), (e[1] as num).toInt(), e[2]?.toString() ?? ''));
        }
      }
      wifiAps = list;
    }
    final br = m['bleList'];
    if (br is List) {
      final list = <BleDev>[];
      for (final e in br) {
        if (e is List && e.length >= 2) {
          list.add(BleDev((e[0] as num).toInt(), e[1]?.toString() ?? ''));
        }
      }
      bleDevices = list;
    }

    // ── Fusion / inferred ──
    _s(m['motionstate'], 'motionstate');
    _s(m['envContext'], 'envContext');
    _d2(m['altCal'], 'altCal', (v) => '${v.toStringAsFixed(1)} m');
    _d2(m['seaLevel'], 'seaLevel', (v) => '${v.toStringAsFixed(1)} hPa');
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

    // ── Full sensor inventory ──
    final iraw = m['inventory'];
    if (iraw is List) {
      final list = <SensorInfo>[];
      for (final e in iraw) {
        if (e is List && e.length >= 13) {
          list.add(SensorInfo(
            type: e[0] is num ? (e[0] as num).toInt() : -1,
            name: e[1]?.toString() ?? '',
            vendor: e[2]?.toString() ?? '',
            stringType: e[3]?.toString() ?? '',
            power: e[4] is num ? (e[4] as num).toDouble() : 0,
            resolution: e[5] is num ? (e[5] as num).toDouble() : 0,
            maxRange: e[6] is num ? (e[6] as num).toDouble() : 0,
            minDelayUs: e[7] is num ? (e[7] as num).toInt() : 0,
            reportingMode: e[8] is num ? (e[8] as num).toInt() : 3,
            wakeUp: e[9] == true,
            registered: e[10] == true,
            ageMs: e[11] is num ? (e[11] as num).toInt() : -1,
            gate: e[12]?.toString() ?? '',
          ));
        }
      }
      inventory = list;
    }

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
