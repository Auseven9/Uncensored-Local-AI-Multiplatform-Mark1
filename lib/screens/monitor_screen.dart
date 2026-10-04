import 'package:flutter/material.dart';
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
      _Parent('amag', 'Accelerometer', min: 0, max: 25, color: _accent, children: [
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
      _Parent('gmag', 'Gyroscope', min: 0, max: 720, color: _cyan, children: [
        _Tile('gx', 'X', min: 0, max: 720, abs: true, color: _cyan),
        _Tile('gy', 'Y', min: 0, max: 720, abs: true, color: _cyan),
        _Tile('gz', 'Z', min: 0, max: 720, abs: true, color: _cyan),
        _Tile('gmag', '|ω| magnitude', min: 0, max: 720, color: _cyan),
      ]),
      _Parent('motionstate', 'Motion & impact', children: [
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
      _Parent('bmag', 'Magnetometer', min: 0, max: 120, color: _accent, children: [
        _Tile('mx', 'X', min: 0, max: 120, abs: true, color: _accent),
        _Tile('my', 'Y', min: 0, max: 120, abs: true, color: _accent),
        _Tile('mz', 'Z', min: 0, max: 120, abs: true, color: _accent),
        _Tile('bmag', 'Field |B|', min: 0, max: 120, color: _accent),
        _Tile('dip', 'Dip angle', min: -90, max: 90, color: _cyan),
      ]),
    ]),
    _Group('Orientation', [
      _Parent('compass', 'Orientation', min: 0, max: 360, color: _cyan, children: [
        _Tile('compass', 'Heading', min: 0, max: 360, color: _cyan),
        _Tile('cardinal', 'Cardinal'),
        _Tile('pitch', 'Pitch (f/b)', min: -180, max: 180, color: _cyan),
        _Tile('roll', 'Roll (l/r)', min: -180, max: 180, color: _cyan),
        _Tile('pose', 'Pose'),
      ]),
    ]),
    _Group('Environment', [
      _Parent('press', 'Barometer', min: 950, max: 1050, color: _amber, children: [
        _Tile('press', 'Pressure', min: 950, max: 1050, color: _amber),
        _Tile('alt', 'Altitude', min: -100, max: 3000, color: _amber),
        _Tile('vspeed', 'Vertical speed', min: 0, max: 5, abs: true, color: _amber),
        _Tile('floors', 'Floors climbed', min: 0, max: 50, color: _amber),
        _Tile('ptrend', 'Trend'),
      ]),
      _Parent('lux', 'Optical', min: 0, max: 1000, color: _amber, children: [
        _Tile('lux', 'Illuminance', min: 0, max: 2000, color: _amber),
        _Tile('lightcat', 'Category'),
        _Tile('prox', 'Proximity', min: 0, max: 1, color: _amber),
      ]),
      _Parent('atemp', 'Ambient', min: 0, max: 50, color: _amber, children: [
        _Tile('atemp', 'Temperature', min: 0, max: 50, color: _amber),
        _Tile('humid', 'Humidity', min: 0, max: 100, color: _amber),
        _Tile('hall', 'Hall sensor'),
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

  SensorService? _svc;
  late final AnimationController _pulse;
  final Set<String> _open = <String>{};

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
        const Text('Monitor',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _text)),
        const SizedBox(height: 2),
        const Text('Live hardware stream · real reading or “no socket”',
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
  Widget _hero(SensorService s) => DeviceTwin(
        grx: s.numOf('grx'),
        gry: s.numOf('gry'),
        grz: s.numOf('grz'),
        compass: s.numOf('compass'),
        cardinal: s.readings['cardinal'],
        lax: s.numOf('lax'),
        lay: s.numOf('lay'),
        pitch: s.numOf('pitch'),
        roll: s.numOf('roll'),
        pose: s.readings['pose'],
        thermMax: s.numOf('thermmax'),
      );

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
        ];
      case 'Orientation':
        return [
          CompassRose(heading: s.numOf('compass'), cardinal: s.readings['cardinal']),
        ];
      case 'Environment':
        return [
          Altimeter(alt: s.numOf('alt'), vspeed: s.numOf('vspeed'), trend: s.readings['ptrend']),
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

  // ── Per-section visualizations below the cards ──
  List<Widget> _bottomViz(String title, SensorService s) {
    if (title == 'Magnetic') {
      return [
        MetalDetector(field: s.numOf('bmag'), mx: s.numOf('mx'), my: s.numOf('my')),
      ];
    }
    return const [];
  }

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
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: frac ?? 0.0,
              minHeight: 3,
              backgroundColor: const Color(0x0DFFFFFF),
              valueColor: AlwaysStoppedAnimation<Color>(
                  frac == null ? const Color(0x00000000) : t.color),
            ),
          ),
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
  const _Parent(this.id, this.label,
      {this.min = 0,
      this.max = 0,
      this.abs = false,
      this.color = const Color(0xFF818CF8),
      this.children = const <_Tile>[]});
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
