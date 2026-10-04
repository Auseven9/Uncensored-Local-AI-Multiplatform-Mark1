import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../services/sensor_service.dart';
import 'monitor_viz.dart';

/// Native Monitor — a real Flutter sensor/resource dashboard.
///
/// Each sensor is a parent card showing its headline reading, a liveness dot
/// (green pulsing = operating and fresh, amber = idle, grey = no socket) and a
/// meter. Tap a card to drill into its sub-box of deeper readings — magnitudes,
/// derivations and fusion states computed from the same real hardware stream.
/// Every value is a genuine reading or "no socket"; nothing is simulated.
///
/// Fully native — no WebView, no HTML. Motion carries a live accel/gyro graph
/// and Orientation a hand-drawn 3D phone driven by the device rotation matrix.
class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen>
    with SingleTickerProviderStateMixin {
  static const Color _bg = Color(0xFF0D1117);
  static const Color _panel = Color(0xFF161B22);
  static const Color _sub = Color(0xFF0B0F14);
  static const Color _border = Color(0x1AFFFFFF);
  static const Color _text = Color(0xFFE6EDF3);
  static const Color _textM = Color(0xFF8B949E);
  static const Color _textD = Color(0xFF484F58);
  static const Color _accent = Color(0xFF818CF8);
  static const Color _cyan = Color(0xFF22D3EE);
  static const Color _green = Color(0xFF3FB950);
  static const Color _amber = Color(0xFFE3B341);

  static const int _liveMs = 2500;

  static const List<_Group> _groups = <_Group>[
    _Group('Compute', [
      _Parent('cpuapp', 'CPU', min: 0, max: 100, color: _accent, children: [
        _Tile('cpuapp', 'App load', min: 0, max: 100, color: _accent),
        _Tile('cores', 'Cores'),
        _Tile('uptime', 'Uptime'),
      ]),
      _Parent('ramu', 'Memory', min: 0, max: 100, color: _cyan, children: [
        _Tile('ramu', 'Used', min: 0, max: 100, color: _cyan),
        _Tile('ramfree', 'Free', min: 0, max: 16384, color: _cyan),
        _Tile('dmem', 'Total'),
        _Tile('apppss', 'App PSS', min: 0, max: 1024, color: _cyan),
        _Tile('lowmem', 'Low-mem flag'),
      ]),
      _Parent('storf', 'Storage', min: 0, max: 100, color: _cyan, children: [
        _Tile('storf', 'Used', min: 0, max: 100, color: _cyan),
        _Tile('stort', 'Capacity'),
      ]),
    ]),
    _Group('Power / Thermal', [
      _Parent('batl', 'Battery', min: 0, max: 100, color: _green, children: [
        _Tile('batl', 'Level', min: 0, max: 100, color: _green),
        _Tile('batc', 'Charging', min: 0, max: 1, color: _green),
        _Tile('batt', 'Temp', min: 15, max: 55, color: _amber),
        _Tile('batv', 'Voltage', min: 3.0, max: 4.5, color: _amber),
        _Tile('batcur', 'Current', min: 0, max: 4000, abs: true, color: _amber),
        _Tile('batcuravg', 'Avg current', min: 0, max: 4000, abs: true, color: _amber),
        _Tile('batpower', 'Power', min: 0, max: 30, color: _amber),
        _Tile('bathealth', 'Health'),
        _Tile('battech', 'Chemistry'),
        _Tile('batplug', 'Supply'),
        _Tile('chargecounter', 'Charge', min: 0, max: 6000, color: _green),
        _Tile('chargetime', 'Full in', min: 0, max: 180, color: _green),
        _Tile('batcycles', 'Cycles'),
      ]),
      _Parent('therm', 'Thermal', min: 0, max: 6, color: _amber, children: [
        _Tile('therm', 'Status', min: 0, max: 6, color: _amber),
        _Tile('thermhr', 'Headroom', min: 0, max: 100, color: _amber),
        _Tile('thermmax', 'Hottest zone', min: 0, max: 100, color: _amber),
        _Tile('thermcpu', 'CPU zone', min: 0, max: 100, color: _amber),
        _Tile('thermbatt', 'Battery zone', min: 0, max: 60, color: _amber),
        _Tile('thermskin', 'Skin zone', min: 0, max: 60, color: _amber),
        _Tile('thermgpu', 'GPU zone', min: 0, max: 100, color: _amber),
      ]),
    ]),
    _Group('Motion', [
      _Parent('amag', 'Accelerometer', min: 0, max: 25, color: _accent, sensorKey: 'accel', children: [
        _Tile('ax', 'X', min: 0, max: 20, abs: true, color: _accent),
        _Tile('ay', 'Y', min: 0, max: 20, abs: true, color: _accent),
        _Tile('az', 'Z', min: 0, max: 20, abs: true, color: _accent),
        _Tile('amag', '|a| magnitude', min: 0, max: 25, color: _accent),
        _Tile('lax', 'Linear X', min: 0, max: 15, abs: true, color: _cyan),
        _Tile('lay', 'Linear Y', min: 0, max: 15, abs: true, color: _cyan),
        _Tile('laz', 'Linear Z', min: 0, max: 15, abs: true, color: _cyan),
        _Tile('lmag', 'Linear |a|', min: 0, max: 20, color: _cyan),
        _Tile('grx', 'Gravity X', min: 0, max: 10, abs: true, color: _green),
        _Tile('gry', 'Gravity Y', min: 0, max: 10, abs: true, color: _green),
        _Tile('grz', 'Gravity Z', min: 0, max: 10, abs: true, color: _green),
        _Tile('jerk', 'Jerk', min: 0, max: 50, color: _accent),
        _Tile('incl', 'Inclination', min: 0, max: 180, color: _cyan),
      ]),
      _Parent('gmag', 'Gyroscope', min: 0, max: 720, color: _cyan, sensorKey: 'gyro', children: [
        _Tile('gx', 'X', min: 0, max: 720, abs: true, color: _cyan),
        _Tile('gy', 'Y', min: 0, max: 720, abs: true, color: _cyan),
        _Tile('gz', 'Z', min: 0, max: 720, abs: true, color: _cyan),
        _Tile('gmag', '|ω| magnitude', min: 0, max: 720, color: _cyan),
      ]),
      _Parent('motionstate', 'Motion & impact', sensorKey: 'lin', children: [
        _Tile('motionstate', 'State'),
        _Tile('jolt', 'Jolt (peak)', min: 0, max: 30, color: _accent),
        _Tile('freefall', 'Free-fall'),
        _Tile('shakes', 'Shakes'),
        _Tile('menergy', 'Motion energy', min: 0, max: 10, color: _accent),
        _Tile('vibhz', 'Vibration', min: 0, max: 30, color: _accent),
        _Tile('steps', 'Steps (est)', min: 0, max: 5000, color: _accent),
        _Tile('cadence', 'Cadence (est)', min: 0, max: 200, color: _accent),
      ]),
    ]),
    _Group('Magnetic', [
      _Parent('bmag', 'Magnetometer', min: 0, max: 120, color: _accent, sensorKey: 'mag', children: [
        _Tile('mx', 'X', min: 0, max: 120, abs: true, color: _accent),
        _Tile('my', 'Y', min: 0, max: 120, abs: true, color: _accent),
        _Tile('mz', 'Z', min: 0, max: 120, abs: true, color: _accent),
        _Tile('bmag', 'Field |B|', min: 0, max: 120, color: _accent),
        _Tile('dip', 'Dip angle', min: -90, max: 90, color: _cyan),
        _Tile('geoField', 'Local field (model)', min: 0, max: 120, color: _accent),
        _Tile('magDev', 'Field anomaly Δ', min: 0, max: 50, abs: true, color: _accent),
        _Tile('magDevPct', 'Anomaly %', min: 0, max: 100, color: _accent),
      ]),
    ]),
    _Group('Orientation', [
      _Parent('compass', 'Orientation', min: 0, max: 360, color: _cyan, sensorKey: 'rot', children: [
        _Tile('compass', 'Heading', min: 0, max: 360, color: _cyan),
        _Tile('cardinal', 'Cardinal'),
        _Tile('pitch', 'Pitch (f/b)', min: -180, max: 180, color: _cyan),
        _Tile('roll', 'Roll (l/r)', min: -180, max: 180, color: _cyan),
        _Tile('pose', 'Pose'),
        _Tile('trueHeading', 'True heading', min: 0, max: 360, color: _cyan),
        _Tile('cardinalTrue', 'True cardinal'),
        _Tile('geoDecl', 'Declination (GPS)'),
        _Tile('geoIncl', 'Mag inclination'),
        _Tile('headingTrust', 'Heading trust'),
      ]),
    ]),
    _Group('Environment', [
      _Parent('press', 'Barometer', min: 950, max: 1050, color: _amber, sensorKey: 'press', children: [
        _Tile('press', 'Pressure', min: 950, max: 1050, color: _amber),
        _Tile('alt', 'Altitude', min: -100, max: 3000, color: _amber),
        _Tile('vspeed', 'Vertical speed', min: 0, max: 5, abs: true, color: _amber),
        _Tile('floors', 'Floors climbed', min: 0, max: 50, color: _amber),
        _Tile('ptrend', 'Trend'),
        _Tile('altCal', 'Altitude (GPS-cal)', min: -100, max: 3000, color: _amber),
        _Tile('seaLevel', 'Sea-level QNH', min: 950, max: 1050, color: _amber),
      ]),
      _Parent('lux', 'Optical', min: 0, max: 1000, color: _amber, sensorKey: 'light', children: [
        _Tile('lux', 'Illuminance', min: 0, max: 2000, color: _amber),
        _Tile('lightcat', 'Category'),
        _Tile('prox', 'Proximity', min: 0, max: 1, color: _amber),
        _Tile('cct0', 'Color ch0 (raw)', color: _amber),
        _Tile('cct1', 'Color ch1 (raw)', color: _amber),
        _Tile('lightir', 'IR light (raw)', color: _amber),
      ]),
      _Parent('atemp', 'Ambient', min: 0, max: 50, color: _amber, sensorKey: 'temp', children: [
        _Tile('atemp', 'Temperature', min: 0, max: 50, color: _amber),
        _Tile('humid', 'Humidity', min: 0, max: 100, color: _amber),
        _Tile('hall', 'Hall sensor'),
        _Tile('envContext', 'Context (GNSS×light)'),
      ]),
    ]),
    _Group('Network', [
      _Parent('online', 'Network', min: 0, max: 1, color: _green, children: [
        _Tile('online', 'Reachability', min: 0, max: 1, color: _green),
        _Tile('ntype', 'Transport'),
        _Tile('metered', 'Metered'),
        _Tile('vpn', 'VPN'),
        _Tile('linkdown', 'Link down', min: 0, max: 1000, color: _green),
        _Tile('linkup', 'Link up', min: 0, max: 300, color: _green),
        _Tile('downkbs', 'Throughput ↓', min: 0, max: 5000, color: _cyan),
        _Tile('upkbs', 'Throughput ↑', min: 0, max: 2000, color: _cyan),
        _Tile('rxmb', 'Total ↓'),
        _Tile('txmb', 'Total ↑'),
      ]),
    ]),
    _Group('System', [
      _Parent('refresh', 'Display', min: 0, max: 144, color: _accent, children: [
        _Tile('refresh', 'Refresh rate', min: 0, max: 144, color: _accent),
        _Tile('screen', 'Resolution'),
        _Tile('density', 'Density', min: 0, max: 5, color: _accent),
      ]),
      _Parent('volmedia', 'Audio', min: 0, max: 100, color: _accent, children: [
        _Tile('volmedia', 'Media volume', min: 0, max: 100, color: _accent),
        _Tile('volring', 'Ring volume', min: 0, max: 100, color: _accent),
        _Tile('ringer', 'Ringer mode'),
        _Tile('music', 'Playback'),
      ]),
    ]),
  ];

  // ── Capability registry ──────────────────────────────────────────────
  // Every reachable socket/call/command the AI can use gets a card here — even
  // those with no live value stream yet. The card shows a CAPTURED indicator
  // (real endpoint reachable), the exact endpoint the AI invokes, and an Enable
  // button for any runtime-gated one. Single source → no duplicate cards; these
  // subsystems are distinct from the streaming sensor groups above.
  static const List<_CapGroup> _capGroups = <_CapGroup>[
    _CapGroup('Hearing', [
      _Cap('mic', 'Microphone', 'AudioRecord · 48 kHz PCM',
          perm: SensorService.pMic, capKey: 'mic', detail: 'raw PCM — level, waveform, FFT'),
    ]),
    _CapGroup('Vision', [
      _Cap('cam', 'Cameras', 'Camera2 · openCamera',
          perm: SensorService.pCam, capKey: 'cameraCount', detail: 'live preview · RAW/MANUAL'),
      _Cap('torch', 'Flashlight / torch', 'CameraManager.setTorchMode',
          capKey: 'torch', detail: 'on/off + strength (API 33+)'),
    ]),
    _CapGroup('Location', [
      _Cap('loc', 'Fused location', 'FusedLocationProvider',
          perm: SensorService.pLoc, capKey: 'gps', detail: 'lat/lon/alt · speed · bearing · accuracy'),
      _Cap('gnss', 'GNSS raw', 'GnssMeasurementsEvent',
          perm: SensorService.pLoc, capKey: 'gps', detail: 'per-satellite C/N0 · pseudorange · constellation'),
    ]),
    _CapGroup('Radio & Nearby', [
      _Cap('radar', 'Nearby radar', 'WifiManager.scanResults + BluetoothLeScanner',
          capKey: 'wifi', detail: 'proximity minimap — radius = signal, bearing not sensed'),
      _Cap('wifiscan', 'Wi-Fi scan', 'WifiManager.scanResults',
          perm: SensorService.pWifi, capKey: 'wifi', detail: 'per-AP RSSI · channel · link speed'),
      _Cap('wifirtt', 'Wi-Fi RTT ranging', 'WifiRttManager',
          perm: SensorService.pWifi, capKey: 'wifiRtt', detail: 'fine-timing distance (m)'),
      _Cap('wifiaware', 'Wi-Fi Aware', 'WifiAwareManager',
          perm: SensorService.pWifi, capKey: 'wifiAware', detail: 'NAN peer discovery'),
      _Cap('cell', 'Cellular signal', 'CellInfo / SignalStrength',
          perm: SensorService.pPhone, capKey: 'cell', detail: 'dBm · band · cell id · network type'),
      _Cap('ble', 'BLE scan', 'BluetoothLeScanner',
          perm: SensorService.pBt, capKey: 'ble', detail: 'nearby device RSSI / beacons'),
      _Cap('uwb', 'Ultra-wideband', 'UwbManager',
          perm: SensorService.pUwb, capKey: 'uwb', detail: 'range + angle-of-arrival (needs a peer)'),
      _Cap('nfc', 'NFC', 'NfcAdapter',
          capKey: 'nfc', detail: 'tag read / HCE — toggle NFC on in quick settings'),
    ]),
    _CapGroup('Input', [
      _Cap('spen', 'S-Pen / stylus', 'InputDevice · SOURCE_STYLUS',
          capKey: 'stylus', detail: 'hover · pressure · button'),
      _Cap('touch', 'Touch digitizer', 'MotionEvent', detail: '10-point · pressure · size · tool'),
    ]),
    _CapGroup('Actuators', [
      _Cap('haptic', 'Haptics', 'Vibrator', capKey: 'vibrator', detail: 'amplitude-controlled actuation'),
    ]),
    _CapGroup('Identity', [
      _Cap('finger', 'Fingerprint', 'BiometricPrompt', capKey: 'bioFingerprint', detail: 'auth only — no raw image'),
      _Cap('face', 'Face unlock', 'BiometricPrompt', capKey: 'bioFace', detail: 'auth only'),
    ]),
    _CapGroup('Compute', [
      _Cap('gpu', 'GPU — Vulkan / GLES', 'Vulkan · OpenGL ES', capKey: 'vulkan', detail: 'compute + render'),
      _Cap('npu', 'NPU / DSP', 'NNAPI / TFLite', detail: 'AI accel — drive-only, no utilisation readout'),
    ]),
  ];

  // Runtime permissions the gated cards request, for the Permissions screen.
  static const List<(String, String, String)> _permMeta = <(String, String, String)>[
    (SensorService.pMic, 'Microphone', 'Hearing — mic level, waveform, FFT'),
    (SensorService.pCam, 'Camera', 'Vision — live preview'),
    (SensorService.pLoc, 'Location (precise)', 'GPS + GNSS sky, speed, bearing'),
    (SensorService.pWifi, 'Nearby Wi-Fi', 'Wi-Fi scan · RTT · Aware'),
    (SensorService.pPhone, 'Phone state', 'Cellular signal / band / cell id'),
    (SensorService.pBt, 'Bluetooth scan', 'BLE nearby device RSSI'),
    (SensorService.pUwb, 'Ultra-wideband', 'UWB range + angle'),
    (SensorService.pAct, 'Physical activity', 'Hardware step detector / counter'),
  ];

  SensorService? _svc;
  late final AnimationController _pulse;
  final Set<String> _open = <String>{};

  // Live-capability control state (on-demand streams + actuators).
  bool _micLive = false;
  bool _torchOn = false;
  bool _revealGps = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    try {
      _svc = Get.find<SensorService>();
    } catch (_) {
      _svc = null;
    }
    _svc?.start();
    // Auto-open location once granted so the sky plot fills without a tap.
    _svc?.refreshPerms().then((_) {
      final s = _svc;
      if (s != null && s.granted(SensorService.pLoc)) s.locStart();
      if (s != null && s.granted(SensorService.pBt)) s.bleStart();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  int _state(SensorService s, String id, int now) {
    final t = s.stampOf(id);
    if (t == null) return 0;
    return (now - t) <= _liveMs ? 2 : 1;
  }

  // Per-card liveness proof: a sparkline of the reading's real samples if it is
  // numeric, otherwise a pulse lane that ticks on each state change. This is how
  // every card shows it is genuinely reading values (or pulses), not frozen.
  Widget _liveProof(SensorService s, String id, Color color, int now, {double height = 18}) {
    final h = s.histOf(id);
    if (h != null && h.length >= 2) {
      return MicroSpark(data: h, color: color, height: height);
    }
    final b = s.beatsOf(id);
    if (b != null && b.isNotEmpty) {
      return PulseLane(beats: b, color: color, now: now, height: height);
    }
    return SizedBox(height: height);
  }

  // All tile ids currently on screen (parents' children + dynamic cores).
  List<String> _allIds(SensorService s) {
    final ids = <String>[];
    for (final g in _groups) {
      for (final p in g.parents) {
        for (final t in p.children) {
          ids.add(t.id);
        }
      }
    }
    for (int i = 0; i < s.coreCount; i++) {
      ids.add('core$i');
    }
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    final svc = _svc;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: svc == null
            ? const Center(
                child: Text('Monitor service unavailable',
                    style: TextStyle(color: _textM)))
            : ValueListenableBuilder<int>(
                valueListenable: svc.tick,
                builder: (context, _, __) {
                  final now = DateTime.now().millisecondsSinceEpoch;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
                    children: [
                      _header(svc, now),
                      const SizedBox(height: 14),
                      _gaugeRow(svc),
                      const SizedBox(height: 16),
                      _hero(svc),
                      for (final g in _groups) ..._group(g, svc, now),
                      for (final cg in _capGroups) ..._capSection(cg, svc),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _header(SensorService s, int now) {
    int live = 0, idle = 0, none = 0, total = 0;
    for (final id in _allIds(s)) {
      total++;
      switch (_state(s, id, now)) {
        case 2:
          live++;
        case 1:
          idle++;
        default:
          none++;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Monitor',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _text)),
            const Spacer(),
            _headerActions(s),
          ],
        ),
        const SizedBox(height: 2),
        const Text('Live hardware stream · fully offline · real reading or “no socket”',
            style: TextStyle(fontSize: 12, color: _textM)),
        const SizedBox(height: 10),
        Row(
          children: [
            _chip('$live live', _green),
            const SizedBox(width: 6),
            _chip('$idle idle', _amber),
            const SizedBox(width: 6),
            _chip('$none no socket', _textD),
            const Spacer(),
            Text('$live/$total operating',
                style: const TextStyle(fontSize: 11, color: _textM)),
          ],
        ),
      ],
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withValues(alpha: 0.12), _bg),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      );

  Widget _gaugeRow(SensorService s) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Expanded(child: _ring('CPU', s.cpuPct.value, _accent)),
            const SizedBox(width: 10),
            Expanded(child: _ring('RAM', s.ramPct.value, _cyan)),
            const SizedBox(width: 10),
            Expanded(child: _ring('BATT', s.batteryPct.value?.toDouble(), _green)),
          ],
        ),
      );

  Widget _ring(String label, double? pct, Color color) {
    final frac = pct == null ? 0.0 : (pct.clamp(0, 100) / 100.0);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    value: frac,
                    strokeWidth: 6,
                    backgroundColor: const Color(0x14FFFFFF),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                Text(pct == null ? 'no\nsocket' : '${pct.round()}%',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: pct == null ? 9 : 13,
                        fontWeight: FontWeight.w700,
                        color: pct == null ? _textM : _text)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, letterSpacing: 1.0, color: _textM, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  List<Widget> _group(_Group g, SensorService s, int now) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
        child: Text(g.title.toUpperCase(),
            style: const TextStyle(
                fontSize: 11, letterSpacing: 1.2, color: _textM, fontWeight: FontWeight.w700)),
      ),
      ..._topViz(g.title, s),
      for (final p in g.parents) _parentCard(p, s, now),
      ..._bottomViz(g.title, s),
    ];
  }

  // ── Hero: the device twin, under the gauge rings ──
  Widget _hero(SensorService s) {
    final trueH = s.numOf('trueHeading');
    return DeviceTwin(
      grx: s.numOf('grx'),
      gry: s.numOf('gry'),
      grz: s.numOf('grz'),
      compass: trueH ?? s.numOf('compass'),
      cardinal: trueH != null ? s.readings['cardinalTrue'] : s.readings['cardinal'],
      trueNorth: trueH != null,
      headingDisplay: s.headingDisplay,
      lax: s.numOf('lax'),
      lay: s.numOf('lay'),
      pitch: s.numOf('pitch'),
      roll: s.numOf('roll'),
      pose: s.readings['pose'],
      thermMax: s.numOf('thermmax'),
      badge: _badge(s, 'rot'),
    );
  }

  // ── Sensor verifier badge for a given hardware sensor key ──
  Widget _badge(SensorService s, String key) {
    final h = s.healthOf(key);
    return SensorBadge(
      name: _shortSensor(h?.name ?? ''),
      present: h?.present ?? false,
      alive: h?.alive ?? false,
      accuracy: h?.accuracy ?? -1,
    );
  }

  // Trim vendor sensor names to a compact identifier for the badge.
  static String _shortSensor(String n) {
    if (n.isEmpty) return '';
    var s = n.trim();
    for (final w in const [
      ' Non-wakeup',
      ' Wakeup',
      ' Uncalibrated',
      ' Sensor',
    ]) {
      s = s.replaceAll(w, '');
    }
    return s.length > 22 ? s.substring(0, 22) : s;
  }

  // ── Per-section visualizations above the cards ──
  List<Widget> _topViz(String title, SensorService s) {
    switch (title) {
      case 'Compute':
        return [
          CoreEqualizer(freqs: [for (int i = 0; i < s.coreCount; i++) s.numOf('core$i')]),
          CpuArea(hist: s.cpuHist, now: s.numOf('cpuapp')),
        ];
      case 'Power / Thermal':
        return [
          ThermalPhone(
            cpu: s.numOf('thermcpu'),
            gpu: s.numOf('thermgpu'),
            batt: s.numOf('thermbatt'),
            skin: s.numOf('thermskin'),
            maxz: s.numOf('thermmax'),
          ),
          BatteryFlow(
            level: s.numOf('batl'),
            charging: s.readings['batc'] == 'charging',
            currentMa: s.numOf('batcur'),
            powerW: s.numOf('batpower'),
          ),
        ];
      case 'Motion':
        return [
          ImpactMeter(
            now: s.numOf('lmag'),
            peak: s.numOf('jolt'),
            state: s.readings['motionstate'],
            freefall: s.readings['freefall'] == 'FALLING',
          ),
          _accelGyroGraph(s),
          SpiritLevel(gx: s.numOf('grx'), gy: s.numOf('gry'), gz: s.numOf('grz')),
          GyroRates(x: s.numOf('gx'), y: s.numOf('gy'), z: s.numOf('gz')),
          if (s.events.isNotEmpty)
            EventLamps(lamps: [
              for (final k in const ['tilt', 'sigmotion', 'stepdet'])
                if (s.events[k] != null)
                  EventLampData(k, s.events[k]!.armed, s.events[k]!.count, s.events[k]!.ageMs),
            ]),
        ];
      case 'Orientation':
        final trueH = s.numOf('trueHeading');
        return [
          CompassRose(
            heading: trueH ?? s.numOf('compass'),
            cardinal: trueH != null ? s.readings['cardinalTrue'] : s.readings['cardinal'],
            trueNorth: trueH != null,
            headingDisplay: s.headingDisplay,
          ),
        ];
      case 'Environment':
        return [
          Altimeter(
            alt: s.numOf('altCal') ?? s.numOf('alt'),
            vspeed: s.numOf('vspeed'),
            trend: s.readings['ptrend'],
            calibrated: s.numOf('altCal') != null,
          ),
          LightBar(lux: s.numOf('lux'), cat: s.readings['lightcat']),
        ];
      case 'Network':
        return [
          ThroughputGraph(
            down: s.downHist,
            up: s.upHist,
            downNow: s.numOf('downkbs'),
            upNow: s.numOf('upkbs'),
            rx: s.readings['rxmb'],
            tx: s.readings['txmb'],
          ),
        ];
      case 'System':
        return [
          RefreshTach(hz: s.numOf('refresh')),
          AudioMeter(
            media: s.numOf('volmedia'),
            ring: s.numOf('volring'),
            music: s.readings['music'] == 'playing',
            ringer: s.readings['ringer'],
            route: s.readings['audioout'],
          ),
        ];
      default:
        return const [];
    }
  }

  // ── Header actions: INDEX (catalog) · CHECK (verify) · PERMS (unlock) ──
  Widget _headerActions(SensorService s) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pill(Icons.format_list_numbered_rounded, 'INDEX', _accent, () => _openIndex(s)),
          const SizedBox(width: 6),
          _pill(Icons.verified_outlined, 'CHECK', _green, () => _openCheck(s)),
          const SizedBox(width: 6),
          _pill(Icons.lock_open_rounded, 'PERMS', _amber, () => _openPerms(s)),
        ],
      );

  Widget _pill(IconData icon, String label, Color c, VoidCallback onTap) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: Color.alphaBlend(c.withValues(alpha: 0.14), _bg),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: c.withValues(alpha: 0.5)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 13, color: c),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            ]),
          ),
        ),
      );

  void _openPerms(SensorService s) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        expand: false,
        builder: (ctx, scrollCtl) =>
            _PermsSheet(service: s, permMeta: _permMeta, scrollController: scrollCtl),
      ),
    );
  }

  void _openCheck(SensorService s) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        expand: false,
        builder: (ctx, scrollCtl) => _CheckSheet(
            service: s, capGroups: _capGroups, scrollController: scrollCtl),
      ),
    );
  }

  void _openIndex(SensorService s) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        expand: false,
        builder: (ctx, scrollCtl) =>
            _IndexSheet(service: s, scrollController: scrollCtl),
      ),
    );
  }

  // ── Per-section visualizations below the cards ──
  List<Widget> _bottomViz(String title, SensorService s) {
    if (title == 'Magnetic') {
      return [
        MetalDetector(
            field: s.numOf('bmag'), mx: s.numOf('mx'), my: s.numOf('my'), earthField: s.numOf('geoField')),
      ];
    }
    return const [];
  }

  // ── Capability cards: one per reachable socket/call/command ──
  List<Widget> _capSection(_CapGroup g, SensorService s) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
          child: Text(g.title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11, letterSpacing: 1.2, color: _textM, fontWeight: FontWeight.w700)),
        ),
        for (final c in g.caps) _capCard(c, s),
      ];

  // (label, colour, canEnable) for a capability's current state.
  (String, Color, bool) _capStatus(_Cap c, SensorService s) {
    final present = c.capKey.isEmpty ? true : s.capPresent(c.capKey);
    final gated = c.perm.isNotEmpty;
    final grantedP = !gated || s.granted(c.perm);
    if (!present) return ('SEALED', _textD, false);
    if (gated && !grantedP) return ('ENABLE', _amber, true);
    return ('CAPTURED', _green, false);
  }

  Widget _capCard(_Cap c, SensorService s) {
    final st = _capStatus(c, s);
    final label = st.$1;
    final col = st.$2;
    final canEnable = st.$3;
    var detail = c.detail;
    if (c.id == 'nfc' && label == 'CAPTURED' && s.caps['nfcEnabled'] != true) {
      detail = '$detail · currently off';
    }
    final permShort = c.perm.isEmpty ? '' : c.perm.split('.').last;
    final body = _capBody(c, s);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(c.title,
                    style: const TextStyle(fontSize: 13, color: _text, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              canEnable ? _enableBtn(c, s) : (_capControl(c, s) ?? _statusPill(label, col)),
            ],
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(detail, style: const TextStyle(fontSize: 10.5, color: _textM)),
          ],
          const SizedBox(height: 9),
          Row(
            children: [
              const Icon(Icons.cable_rounded, size: 11, color: _textD),
              const SizedBox(width: 5),
              Expanded(
                child: Text(c.endpoint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9.5, color: _textD, fontWeight: FontWeight.w600)),
              ),
              if (permShort.isNotEmpty)
                Text(permShort,
                    style: const TextStyle(fontSize: 8.5, color: _textD)),
            ],
          ),
          if (body != null) ...[const SizedBox(height: 12), body],
        ],
      ),
    );
  }

  // Interactive control for a live capability (null → show the status pill).
  Widget? _capControl(_Cap c, SensorService s) {
    switch (c.id) {
      case 'mic':
        if (!s.granted(SensorService.pMic)) return null;
        return _toggle('LIVE', _micLive, () async {
          if (_micLive) {
            await s.micStop();
          } else {
            await s.micStart();
          }
          if (mounted) setState(() => _micLive = !_micLive);
        });
      case 'torch':
        return _toggle(_torchOn ? 'ON' : 'OFF', _torchOn, () async {
          final ok = await s.torch(!_torchOn);
          if (mounted) setState(() => _torchOn = ok ? !_torchOn : _torchOn);
        });
      case 'haptic':
        return _tapBtn('BUZZ', _accent, () => s.buzz(30));
      default:
        return null;
    }
  }

  // The live instrument rendered inside a capability card, when streaming.
  Widget? _capBody(_Cap c, SensorService s) {
    switch (c.id) {
      case 'mic':
        if (_micLive && (s.micWave.isNotEmpty || s.micDb != null)) {
          return VuWaveform(wave: s.micWave, db: s.micDb, peak: s.micPeak);
        }
        return null;
      case 'gnss':
        if (!s.granted(SensorService.pLoc)) return null;
        return SkyPlot(
          sats: [for (final x in s.sats) SatDot(x.az, x.el, x.cn0, x.constType.toInt(), x.used)],
          used: s.satUsed,
          seen: s.satSeen,
        );
      case 'loc':
        if (!s.granted(SensorService.pLoc)) return null;
        return _gpsTiles(s);
      case 'cell':
        if (!s.granted(SensorService.pPhone)) return null;
        return CellSignal(
            dbm: s.numOf('cellDbm'), level: s.numOf('cellLevel')?.toInt(), type: s.readings['cellType']);
      case 'wifiscan':
        if (!s.granted(SensorService.pWifi)) return null;
        return WifiSignal(
          rssi: s.numOf('wifiRssi'),
          band: s.readings['wifiBand'],
          speed: s.readings['wifiSpeed'],
          aps: [for (final a in s.wifiAps) SigItem(a.rssi, a.ssid, a.band)],
        );
      case 'ble':
        if (!s.granted(SensorService.pBt)) return null;
        return BleNearby(devices: [for (final d in s.bleDevices) SigItem(d.rssi, d.name, '')]);
      case 'radar':
        return NearbyRadar(dots: [
          for (final a in s.wifiAps) RadarDot(a.rssi, 'wifi', a.ssid),
          for (final d in s.bleDevices) RadarDot(d.rssi, 'ble', d.name.isEmpty ? 'ble' : d.name),
        ]);
      case 'uwb':
        return const UwbIdle();
      case 'nfc':
        return NfcStatus(enabled: s.caps['nfcEnabled'] == true);
      case 'spen':
        if (!s.capPresent('stylus')) return null;
        return const StylusPad();
      case 'touch':
        return const TouchPad();
      default:
        return null;
    }
  }

  Widget _gpsTiles(SensorService s) {
    final lat = s.numOf('lat');
    final lon = s.numOf('lon');
    String coord(double? v) {
      if (v == null) return '—';
      return _revealGps ? v.toStringAsFixed(5) : '${v.toStringAsFixed(2)}•••';
    }

    final tiles = <List<String>>[
      ['Lat', coord(lat)],
      ['Lon', coord(lon)],
      ['Alt', s.readings['gpsAlt'] ?? '—'],
      ['Speed', s.readings['gpsSpeed'] ?? '—'],
      ['Bearing', s.readings['gpsBearing'] ?? '—'],
      ['Accuracy', s.readings['gpsAcc'] ?? '—'],
      ['Sats', '${s.satUsed}/${s.satSeen}'],
      ['Source', s.readings['gpsProvider'] ?? '—'],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, cc) {
          final w = (cc.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in tiles)
              SizedBox(
                width: w,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                  decoration: BoxDecoration(
                    color: _sub,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t[0], style: const TextStyle(fontSize: 9.5, color: _textM)),
                      const SizedBox(height: 2),
                      Text(t[1],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: _text, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
          ]);
        }),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: _tapBtn(_revealGps ? 'HIDE COORDS' : 'REVEAL COORDS', _textM,
              () => setState(() => _revealGps = !_revealGps)),
        ),
      ],
    );
  }

  Widget _toggle(String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Color.alphaBlend((on ? _green : _textM).withValues(alpha: on ? 0.18 : 0.10), _panel),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: (on ? _green : _textM).withValues(alpha: 0.5)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 11, color: on ? _green : _textM),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 9, color: on ? _green : _textM, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
          ]),
        ),
      );

  Widget _tapBtn(String label, Color col, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Color.alphaBlend(col.withValues(alpha: 0.14), _panel),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: col.withValues(alpha: 0.5)),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 9, color: col, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        ),
      );

  Widget _statusPill(String label, Color col) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Color.alphaBlend(col.withValues(alpha: 0.12), _panel),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: col.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(label == 'CAPTURED' ? Icons.check_circle_outline : Icons.block, size: 10, color: col),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 9, color: col, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        ]),
      );

  Widget _enableBtn(_Cap c, SensorService s) => GestureDetector(
        onTap: () async {
          final ok = await s.requestPerm(c.perm);
          if (ok && c.perm == SensorService.pLoc) await s.locStart();
          if (ok && c.perm == SensorService.pBt) await s.bleStart();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ok ? '${c.title}: socket captured' : '${c.title}: permission denied'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _panel,
          ));
          setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: Color.alphaBlend(_amber.withValues(alpha: 0.16), _panel),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: _amber.withValues(alpha: 0.55)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.bolt_rounded, size: 11, color: _amber),
            SizedBox(width: 3),
            Text('ENABLE',
                style: TextStyle(fontSize: 9, color: _amber, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
          ]),
        ),
      );

  Widget _parentCard(_Parent p, SensorService s, int now) {
    final st = _state(s, p.id, now);
    final value = st == 0 ? 'no socket' : (s.readings[p.id] ?? 'no socket');
    final dot = st == 2 ? _green : (st == 1 ? _amber : _textD);
    final open = _open.contains(p.id);

    // dynamic per-core tiles appended to the CPU card
    final children = <_Tile>[
      ...p.children,
      if (p.id == 'cpuapp')
        for (int i = 0; i < s.coreCount; i++)
          _Tile('core$i', 'Core $i', min: 0, max: 3500, color: _accent),
    ];
    int live = 0;
    for (final t in children) {
      if (_state(s, t.id, now) == 2) live++;
    }

    double? frac;
    if (st != 0 && p.max > p.min) {
      final raw = s.numOf(p.id);
      if (raw != null) {
        final v = p.abs ? raw.abs() : raw;
        frac = ((v - p.min) / (p.max - p.min)).clamp(0.0, 1.0);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() {
            if (open) {
              _open.remove(p.id);
            } else {
              _open.add(p.id);
            }
          }),
          child: Container(
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(p.label,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: _textM,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(width: 6),
                                _Dot(color: dot, pulse: st == 2 ? _pulse : null),
                                if (p.sensorKey != null) ...[
                                  const SizedBox(width: 8),
                                  Flexible(child: _badge(s, p.sensorKey!)),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(value,
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: st == 0 ? _textD : _text)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('$live/${children.length}',
                              style: const TextStyle(fontSize: 10, color: _textM)),
                          const SizedBox(height: 4),
                          AnimatedRotation(
                            turns: open ? 0.5 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: const Icon(Icons.keyboard_arrow_down_rounded,
                                size: 20, color: _textM),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                  child: _liveProof(s, p.id, p.color, now),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: frac ?? 0.0,
                      minHeight: 4,
                      backgroundColor: const Color(0x0DFFFFFF),
                      valueColor: AlwaysStoppedAnimation<Color>(
                          frac == null ? const Color(0x00000000) : p.color),
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: open
                      ? _subBox(children, s, now)
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _subBox(List<_Tile> tiles, SensorService s, int now) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _sub,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = (c.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in tiles) SizedBox(width: w, child: _subTile(t, s, now)),
              ],
            );
          },
        ),
      );

  Widget _subTile(_Tile t, SensorService s, int now) {
    final st = _state(s, t.id, now);
    final value = st == 0 ? 'no socket' : (s.readings[t.id] ?? 'no socket');
    final dot = st == 2 ? _green : (st == 1 ? _amber : _textD);
    double? frac;
    if (st != 0 && t.max > t.min) {
      final raw = s.numOf(t.id);
      if (raw != null) {
        final v = t.abs ? raw.abs() : raw;
        frac = ((v - t.min) / (t.max - t.min)).clamp(0.0, 1.0);
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9.5, color: _textM)),
              ),
              _Dot(color: dot, pulse: st == 2 ? _pulse : null),
            ],
          ),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: st == 0 ? _textD : _text)),
          const SizedBox(height: 5),
          _liveProof(s, t.id, t.color, now, height: 13),
          if (frac != null) ...[
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 2,
                backgroundColor: const Color(0x0DFFFFFF),
                valueColor: AlwaysStoppedAnimation<Color>(t.color),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── live accel / gyro graph ──
  Widget _accelGyroGraph(SensorService s) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _graphRow('Accel |a|', s.readings['amag'] ?? 'no socket', s.accelHist, _accent, 25),
            const SizedBox(height: 12),
            _graphRow('Gyro |ω|', s.readings['gmag'] ?? 'no socket', s.gyroHist, _cyan, 360),
          ],
        ),
      );

  Widget _graphRow(String label, String value, List<double> data, Color color, double floor) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 11, color: _textM, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 46,
            width: double.infinity,
            child: CustomPaint(painter: _GraphPainter(List<double>.from(data), color, floor)),
          ),
        ],
      );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.pulse});
  final Color color;
  final AnimationController? pulse;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    final p = pulse;
    if (p == null) return dot;
    return AnimatedBuilder(
      animation: p,
      builder: (context, child) => Opacity(opacity: 0.35 + 0.65 * p.value, child: child),
      child: dot,
    );
  }
}

/// Simple live sparkline for a sensor magnitude history.
class _GraphPainter extends CustomPainter {
  _GraphPainter(this.data, this.color, this.floor);
  final List<double> data;
  final Color color;
  final double floor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0x0DFFFFFF)
      ..strokeWidth = 1;
    for (int i = 0; i <= 2; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (data.length < 2) return;
    double maxV = floor;
    for (final d in data) {
      if (d > maxV) maxV = d;
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = color
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final y = size.height - (data[i] / maxV).clamp(0.0, 1.0) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, line);
    final fill = Paint()..color = color.withValues(alpha: 0.12);
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, fill);
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}

class _Group {
  final String title;
  final List<_Parent> parents;
  const _Group(this.title, this.parents);
}

class _Parent {
  final String id;
  final String label;
  final double min;
  final double max;
  final bool abs;
  final Color color;
  final List<_Tile> children;
  final String? sensorKey; // hardware sensor health key, for the verifier badge
  const _Parent(this.id, this.label,
      {this.min = 0,
      this.max = 0,
      this.abs = false,
      this.color = const Color(0xFF818CF8),
      this.children = const <_Tile>[],
      this.sensorKey});
}

class _Tile {
  final String id;
  final String label;
  final double min;
  final double max;
  final bool abs;
  final Color color;
  const _Tile(this.id, this.label,
      {this.min = 0, this.max = 0, this.abs = false, this.color = const Color(0xFF818CF8)});
}

/// A reachable device capability (socket/call/command the AI can invoke).
class _Cap {
  final String id;
  final String title;
  final String endpoint; // the actual API the AI calls
  final String perm; // runtime permission (Android constant), '' if none
  final String capKey; // native caps presence key, '' = always present
  final String detail;
  const _Cap(this.id, this.title, this.endpoint,
      {this.perm = '', this.capKey = '', this.detail = ''});
}

class _CapGroup {
  final String title;
  final List<_Cap> caps;
  const _CapGroup(this.title, this.caps);
}

/// Full-screen device capability index — every subsystem/API probed for what we
/// can tap and where, with a COPY button that puts the whole catalog on the
/// clipboard.
class _IndexSheet extends StatefulWidget {
  const _IndexSheet({required this.service, required this.scrollController});
  final SensorService service;
  final ScrollController scrollController;

  @override
  State<_IndexSheet> createState() => _IndexSheetState();
}

class _IndexSheetState extends State<_IndexSheet> {
  static const Color _bg = Color(0xFF0D1117);
  static const Color _panel = Color(0xFF161B22);
  static const Color _border = Color(0x1AFFFFFF);
  static const Color _text = Color(0xFFE6EDF3);
  static const Color _textM = Color(0xFF8B949E);
  static const Color _textD = Color(0xFF484F58);
  static const Color _accent = Color(0xFF818CF8);
  static const Color _cyan = Color(0xFF22D3EE);
  static const Color _green = Color(0xFF3FB950);
  static const Color _amber = Color(0xFFE3B341);
  static const Color _red = Color(0xFFF85149);

  List<IndexSection>? _sections;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await widget.service.fetchIndex();
    if (mounted) setState(() => _sections = s);
  }

  Color _statusColor(String st) {
    switch (st) {
      case 'available':
        return _green;
      case 'needs-perm':
        return _amber;
      case 'command':
        return _cyan;
      case 'sealed':
        return _textM;
      default:
        return _red; // unsupported
    }
  }

  int get _count => _sections?.fold<int>(0, (a, s) => a + s.entries.length) ?? 0;
  int get _available =>
      _sections?.fold<int>(0, (a, s) => a + s.entries.where((e) => e.status == 'available').length) ?? 0;

  Future<void> _copy() async {
    final secs = _sections ?? const <IndexSection>[];
    final b = StringBuffer()
      ..writeln('UNCENSORED LOCAL AI — DEVICE CAPABILITY INDEX')
      ..writeln('$_count capabilities across ${secs.length} subsystems');
    for (final s in secs) {
      b.writeln('\n=== ${s.name} (${s.entries.length}) ===');
      for (final e in s.entries) {
        final extra = [
          if (e.detail.isNotEmpty) e.detail,
          if (e.perm.isNotEmpty) 'perm:${e.perm}',
          if (e.api.isNotEmpty) 'api:${e.api}',
        ].join(' · ');
        b.writeln('- [${e.status}] ${e.label}${extra.isNotEmpty ? ' — $extra' : ''}');
      }
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (mounted) {
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final secs = _sections;
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(color: _textD, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
          child: Row(
            children: [
              const Text('Device Index',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _text)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    secs == null ? 'probing…' : '$_count caps · $_available open · ${secs.length} systems',
                    style: const TextStyle(fontSize: 11, color: _textM)),
              ),
              _copyBtn(),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: _textM, size: 22),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            _legend('available', _green),
            _legend('needs-perm', _amber),
            _legend('command', _cyan),
            _legend('sealed', _textM),
            _legend('unsupported', _red),
          ]),
        ),
        Expanded(
          child: secs == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : ListView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
                  children: [for (final sec in secs) ..._sectionWidgets(sec)],
                ),
        ),
      ],
    );
  }

  Widget _copyBtn() => GestureDetector(
        onTap: _copied ? null : _copy,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Color.alphaBlend((_copied ? _green : _accent).withValues(alpha: 0.14), _bg),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: (_copied ? _green : _accent).withValues(alpha: 0.5)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 14, color: _copied ? _green : _accent),
            const SizedBox(width: 5),
            Text(_copied ? 'COPIED' : 'COPY',
                style: TextStyle(
                    fontSize: 11, color: _copied ? _green : _accent, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  List<Widget> _sectionWidgets(IndexSection sec) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
          child: Row(children: [
            Text(sec.name.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11, letterSpacing: 1.1, color: _textM, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text('${sec.entries.length}', style: const TextStyle(fontSize: 10, color: _textD)),
          ]),
        ),
        for (final e in sec.entries) _entryRow(e),
      ];

  Widget _entryRow(IndexEntry e) {
    final c = _statusColor(e.status);
    final sub = [if (e.perm.isNotEmpty) 'perm: ${e.perm}', if (e.api.isNotEmpty) e.api].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 9),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(e.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: _text, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Color.alphaBlend(c.withValues(alpha: 0.12), _panel),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.withValues(alpha: 0.4)),
              ),
              child: Text(e.status,
                  style: TextStyle(fontSize: 8.5, color: c, fontWeight: FontWeight.w700)),
            ),
          ]),
          if (e.detail.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(e.detail, style: const TextStyle(fontSize: 9.5, color: _textM)),
          ],
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9, color: _textD)),
          ],
        ],
      ),
    );
  }

  Widget _legend(String label, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 9, color: c, fontWeight: FontWeight.w600)),
      ]);
}

/// Permissions screen — every runtime permission a gated socket needs, its live
/// grant status, a one-tap request, and how to unlock it manually if Android
/// has stopped re-prompting. Requests go through the native bridge, no plugin.
class _PermsSheet extends StatefulWidget {
  const _PermsSheet({required this.service, required this.permMeta, required this.scrollController});
  final SensorService service;
  final List<(String, String, String)> permMeta;
  final ScrollController scrollController;
  @override
  State<_PermsSheet> createState() => _PermsSheetState();
}

class _PermsSheetState extends State<_PermsSheet> {
  static const Color _bg = Color(0xFF0D1117);
  static const Color _panel = Color(0xFF161B22);
  static const Color _border = Color(0x1AFFFFFF);
  static const Color _text = Color(0xFFE6EDF3);
  static const Color _textM = Color(0xFF8B949E);
  static const Color _textD = Color(0xFF484F58);
  static const Color _green = Color(0xFF3FB950);
  static const Color _amber = Color(0xFFE3B341);
  static const Color _accent = Color(0xFF818CF8);

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.service.refreshPerms().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _request(String perm) async {
    setState(() => _busy = true);
    final ok = await widget.service.requestPerm(perm);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Granted' : 'Denied — try Open App Settings below'),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      backgroundColor: _panel,
    ));
  }

  Future<void> _requestAll() async {
    setState(() => _busy = true);
    for (final p in widget.permMeta) {
      if (!widget.service.granted(p.$1)) await widget.service.requestPerm(p.$1);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final granted = widget.permMeta.where((p) => widget.service.granted(p.$1)).length;
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(width: 38, height: 4, decoration: BoxDecoration(color: _textD, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
          child: Row(children: [
            const Text('Permissions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _text)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('$granted/${widget.permMeta.length} granted',
                  style: const TextStyle(fontSize: 11, color: _textM)),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: _textM, size: 22),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            _btn('Request all', _accent, _busy ? null : _requestAll),
            const SizedBox(width: 8),
            _btn('Open App Settings', _textM, () => widget.service.openAppSettings()),
          ]),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
            children: [
              for (final p in widget.permMeta) _permRow(p),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('How to unlock', style: TextStyle(fontSize: 12, color: _text, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
                  Text('1 · Tap a permission\'s Request to prompt the system dialog, then Allow.\n'
                      '2 · Android stops re-prompting after two denials. If Request does nothing, tap '
                      'Open App Settings → Permissions and enable it there.\n'
                      '3 · Nearby Wi-Fi, Bluetooth and Precise location may each ask once; grant all for '
                      'the Radio & Nearby cards.\n'
                      '4 · Nothing streams until you grant it — a denied socket just stays dark, never faked.',
                      style: TextStyle(fontSize: 10.5, color: _textM, height: 1.5)),
                ]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _permRow((String, String, String) p) {
    final ok = widget.service.granted(p.$1);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.$2, style: const TextStyle(fontSize: 13, color: _text, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(p.$3, style: const TextStyle(fontSize: 10, color: _textM)),
          ]),
        ),
        const SizedBox(width: 8),
        ok
            ? Row(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.check_circle, size: 14, color: _green),
                SizedBox(width: 4),
                Text('granted', style: TextStyle(fontSize: 11, color: _green, fontWeight: FontWeight.w700)),
              ])
            : _btn('Request', _amber, _busy ? null : () => _request(p.$1)),
      ]),
    );
  }

  Widget _btn(String label, Color col, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Color.alphaBlend(col.withValues(alpha: onTap == null ? 0.05 : 0.14), _bg),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: col.withValues(alpha: onTap == null ? 0.2 : 0.5)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11, color: onTap == null ? _textD : col, fontWeight: FontWeight.w700)),
        ),
      );
}

/// Check-Index — re-probes presence + permissions and verifies every channel's
/// state (CAPTURED / ENABLE / SEALED) plus the streaming sensors' armed/lost
/// health, so you can confirm at a glance that the sockets are actually open.
class _CheckSheet extends StatefulWidget {
  const _CheckSheet({required this.service, required this.capGroups, required this.scrollController});
  final SensorService service;
  final List<_CapGroup> capGroups;
  final ScrollController scrollController;
  @override
  State<_CheckSheet> createState() => _CheckSheetState();
}

class _CheckSheetState extends State<_CheckSheet> {
  static const Color _panel = Color(0xFF161B22);
  static const Color _border = Color(0x1AFFFFFF);
  static const Color _text = Color(0xFFE6EDF3);
  static const Color _textM = Color(0xFF8B949E);
  static const Color _textD = Color(0xFF484F58);
  static const Color _green = Color(0xFF3FB950);
  static const Color _amber = Color(0xFFE3B341);
  static const Color _red = Color(0xFFF85149);

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _loading = true);
    await widget.service.recheck();
    if (mounted) setState(() => _loading = false);
  }

  (String, Color) _status(_Cap c) {
    final s = widget.service;
    final present = c.capKey.isEmpty ? true : s.capPresent(c.capKey);
    final gated = c.perm.isNotEmpty;
    final grantedP = !gated || s.granted(c.perm);
    if (!present) return ('SEALED', _textD);
    if (gated && !grantedP) return ('ENABLE', _amber);
    return ('CAPTURED', _green);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    int captured = 0, enable = 0, sealed = 0, total = 0;
    for (final g in widget.capGroups) {
      for (final c in g.caps) {
        total++;
        switch (_status(c).$1) {
          case 'CAPTURED':
            captured++;
          case 'ENABLE':
            enable++;
          default:
            sealed++;
        }
      }
    }
    final sensors = s.health.values.where((h) => h.present).toList();
    final armed = sensors.where((h) => h.alive).length;
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(width: 38, height: 4, decoration: BoxDecoration(color: _textD, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
          child: Row(children: [
            const Text('Channel check', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _text)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  _loading ? 'verifying…' : '$captured captured · $enable to enable · $armed/${sensors.length} sensors armed',
                  style: const TextStyle(fontSize: 11, color: _textM)),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: _textM, size: 20),
              onPressed: _loading ? null : _run,
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: _textM, size: 22),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ]),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
            children: [
              _sectionLabel('STREAMING SENSORS'),
              for (final h in sensors)
                _row(_sensorShort(h.name), h.alive ? 'ARMED' : 'LOST', h.alive ? _green : _red),
              for (final g in widget.capGroups) ...[
                _sectionLabel(g.title.toUpperCase()),
                for (final c in g.caps)
                  () {
                    final st = _status(c);
                    return _row(c.title, st.$1, st.$2, endpoint: c.endpoint);
                  }(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _sensorShort(String n) {
    if (n.isEmpty) return 'sensor';
    final t = n.replaceAll(' Non-wakeup', '').replaceAll(' Wakeup', '');
    return t.length > 26 ? t.substring(0, 26) : t;
  }

  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
        child: Text(s,
            style: const TextStyle(fontSize: 10, letterSpacing: 1.1, color: _textM, fontWeight: FontWeight.w700)),
      );

  Widget _row(String name, String status, Color col, {String endpoint = ''}) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: _text, fontWeight: FontWeight.w600)),
              if (endpoint.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(endpoint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: _textD)),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Color.alphaBlend(col.withValues(alpha: 0.12), _panel),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: col.withValues(alpha: 0.4)),
            ),
            child: Text(status, style: TextStyle(fontSize: 8.5, color: col, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}
