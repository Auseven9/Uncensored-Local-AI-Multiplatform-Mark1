import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/sensor_service.dart';

/// Native Monitor — a real Flutter sensor/resource dashboard. Every tile is a
/// metered card showing a genuine hardware reading or "no socket"; nothing is
/// simulated. A per-sensor dot verifies liveness (green pulsing = operating and
/// fresh, amber = idle, grey = no socket) and a header tallies how many sensors
/// are actually operating. Fully native — no WebView, no HTML.
class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen>
    with SingleTickerProviderStateMixin {
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

  static const int _liveMs = 2500;

  static const List<_Group> _groups = <_Group>[
    _Group('Compute', [
      _Tile('cores', 'CPU cores'),
      _Tile('cpuapp', 'CPU load', min: 0, max: 100, color: _accent),
      _Tile('ramu', 'RAM used', min: 0, max: 100, color: _cyan),
      _Tile('dmem', 'Device RAM'),
      _Tile('storf', 'Storage used', min: 0, max: 100, color: _cyan),
      _Tile('uptime', 'Uptime'),
    ]),
    _Group('Power / Thermal', [
      _Tile('batl', 'Battery', min: 0, max: 100, color: _green),
      _Tile('batc', 'Charging', min: 0, max: 1, color: _green),
      _Tile('batt', 'Batt temp', min: 15, max: 55, color: _amber),
      _Tile('batv', 'Voltage', min: 3.0, max: 4.5, color: _amber),
      _Tile('batcur', 'Current', min: 0, max: 3000, abs: true, color: _amber),
      _Tile('therm', 'Thermal', min: 0, max: 6, color: _amber),
    ]),
    _Group('Motion', [
      _Tile('ax', 'Accel X', min: 0, max: 20, abs: true, color: _accent),
      _Tile('ay', 'Accel Y', min: 0, max: 20, abs: true, color: _accent),
      _Tile('az', 'Accel Z', min: 0, max: 20, abs: true, color: _accent),
      _Tile('gx', 'Gyro X', min: 0, max: 360, abs: true, color: _accent),
      _Tile('gy', 'Gyro Y', min: 0, max: 360, abs: true, color: _accent),
      _Tile('gz', 'Gyro Z', min: 0, max: 360, abs: true, color: _accent),
    ]),
    _Group('Orientation', [
      _Tile('compass', 'Compass', min: 0, max: 360, color: _cyan),
      _Tile('tiltb', 'Tilt f/b', min: -180, max: 180, color: _cyan),
      _Tile('tiltg', 'Tilt l/r', min: -180, max: 180, color: _cyan),
    ]),
    _Group('Environment', [
      _Tile('lux', 'Light', min: 0, max: 1000, color: _amber),
      _Tile('prox', 'Proximity', min: 0, max: 1, color: _amber),
      _Tile('press', 'Pressure', min: 950, max: 1050, color: _amber),
    ]),
    _Group('Network', [
      _Tile('online', 'Connectivity', min: 0, max: 1, color: _green),
      _Tile('ntype', 'Type'),
    ]),
  ];

  SensorService? _svc;
  late final AnimationController _pulse;

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
                      for (final g in _groups) _group(g, svc, now),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _header(SensorService s, int now) {
    int live = 0, idle = 0, none = 0, total = 0;
    for (final g in _groups) {
      for (final t in g.tiles) {
        total++;
        switch (_state(s, t.id, now)) {
          case 2:
            live++;
          case 1:
            idle++;
          default:
            none++;
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Monitor',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _text)),
        const SizedBox(height: 2),
        const Text('Live device sensors · real reading or “no socket”',
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

  Widget _group(_Group g, SensorService s, int now) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
            child: Text(g.title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11, letterSpacing: 1.2, color: _textM, fontWeight: FontWeight.w700)),
          ),
          LayoutBuilder(
            builder: (context, c) {
              final w = (c.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final t in g.tiles) SizedBox(width: w, child: _card(t, s, now)),
                ],
              );
            },
          ),
        ],
      );

  Widget _card(_Tile t, SensorService s, int now) {
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t.label,
                    style: const TextStyle(fontSize: 10.5, color: _textM)),
              ),
              _Dot(color: dot, pulse: st == 2 ? _pulse : null),
            ],
          ),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: st == 0 ? _textD : _text)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac ?? 0.0,
              minHeight: 4,
              backgroundColor: const Color(0x0DFFFFFF),
              valueColor: AlwaysStoppedAnimation<Color>(
                  frac == null ? const Color(0x00000000) : t.color),
            ),
          ),
        ],
      ),
    );
  }
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

class _Group {
  final String title;
  final List<_Tile> tiles;
  const _Group(this.title, this.tiles);
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
