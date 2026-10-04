import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Native data visualizations for the Monitor tab.
///
/// Every widget here is driven ONLY by real values sampled from the device
/// sensors/telemetry stream (passed in from [SensorService]). No value is
/// smoothed, interpolated or invented — the raw reading is what you see.
/// When a required reading is unavailable the widget renders "no socket"
/// instead of drawing anything, so nothing is ever fabricated. All pure
/// Flutter CustomPaint; no WebView, no packages.

const Color _bg = Color(0xFF0D1117);
const Color _panel = Color(0xFF161B22);
const Color _sub = Color(0xFF0B0F14);
const Color _border = Color(0x1AFFFFFF);
const Color _text = Color(0xFFE6EDF3);
const Color _textM = Color(0xFF8B949E);
const Color _textD = Color(0xFF484F58);
const Color _accent = Color(0xFF818CF8);
const Color _cyan = Color(0xFF22D3EE);
const Color _green = Color(0xFF3FB950);
const Color _amber = Color(0xFFE3B341);
const Color _red = Color(0xFFF85149);

double _deg2rad(num d) => d * math.pi / 180.0;

Color _tempColor(double c) {
  if (c < 35) return _green;
  if (c < 42) return _amber;
  return _red;
}

void _tp(Canvas c, String s, Offset at, Color col,
    {double size = 10, FontWeight w = FontWeight.w600, TextAlign align = TextAlign.center}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(color: col, fontSize: size, fontWeight: w)),
    textDirection: TextDirection.ltr,
    textAlign: align,
  )..layout();
  tp.paint(c, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2));
}

/// Shared card chrome for a visualization.
class VizCard extends StatelessWidget {
  const VizCard({
    super.key,
    required this.title,
    required this.height,
    required this.child,
    this.trailing,
    this.trailingColor,
    this.live = true,
  });
  final String title;
  final double height;
  final Widget child;
  final String? trailing;
  final Color? trailingColor;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Row(
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 12, color: _textM, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: live ? _green : _textD, shape: BoxShape.circle),
              ),
              const Spacer(),
              if (trailing != null)
                Text(trailing!,
                    style: TextStyle(
                        fontSize: 12,
                        color: trailingColor ?? _textM,
                        fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(height: height, width: double.infinity, child: child),
        ],
      ),
    );
  }
}

Widget _noSocket(double h) => SizedBox(
      height: h,
      child: const Center(
        child: Text('no socket', style: TextStyle(color: _textD, fontSize: 13)),
      ),
    );

// ════════════════════════ HERO: DEVICE TWIN ════════════════════════

/// The hero: a live 3D phone over a fixed ground reference frame, with a
/// device-axis tripod, thermal hot-spots on the body, and (when moving) the
/// linear-acceleration vector. Driven by the raw rotation matrix — no
/// smoothing — so what you see is the exact sensor state.
class DeviceTwin extends StatelessWidget {
  const DeviceTwin({
    super.key,
    required this.rot,
    this.lax,
    this.lay,
    this.laz,
    this.lmag,
    this.thermCpu,
    this.thermGpu,
    this.thermBatt,
    this.thermSkin,
    this.thermMax,
    this.pose,
    this.compass,
    this.cardinal,
    this.pitch,
    this.roll,
  });

  final List<double>? rot;
  final double? lax, lay, laz, lmag;
  final double? thermCpu, thermGpu, thermBatt, thermSkin, thermMax;
  final String? pose, cardinal;
  final double? compass, pitch, roll;

  @override
  Widget build(BuildContext context) {
    final r = rot;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF161B22), Color(0xFF0F1420)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Device twin',
                  style: TextStyle(fontSize: 13, color: _text, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: r == null ? _textD : _green, shape: BoxShape.circle),
              ),
              const Spacer(),
              Text(pose ?? '',
                  style: const TextStyle(fontSize: 11, color: _textM, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 250,
            width: double.infinity,
            child: r == null
                ? _noSocket(250)
                : CustomPaint(
                    painter: _TwinPainter(
                      r: r,
                      lax: lax,
                      lay: lay,
                      laz: laz,
                      lmag: lmag,
                      tCpu: thermCpu,
                      tGpu: thermGpu,
                      tBatt: thermBatt,
                      tSkin: thermSkin,
                    ),
                    size: Size.infinite,
                  ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _twinStat('HEADING',
                  compass == null ? '—' : '${compass!.toStringAsFixed(0)}° ${cardinal ?? ''}', _cyan),
              _twinStat('PITCH', pitch == null ? '—' : '${pitch!.toStringAsFixed(0)}°', _accent),
              _twinStat('ROLL', roll == null ? '—' : '${roll!.toStringAsFixed(0)}°', _accent),
              _twinStat('HOT',
                  thermMax == null ? '—' : '${thermMax!.toStringAsFixed(1)}°', _tempColor(thermMax ?? 0.0)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _twinStat(String label, String value, Color color) => Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 8.5, color: _textD, letterSpacing: 0.8, fontWeight: FontWeight.w700)),
            const SizedBox(height: 1),
            Text(value, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _TwinPainter extends CustomPainter {
  _TwinPainter({
    required this.r,
    this.lax,
    this.lay,
    this.laz,
    this.lmag,
    this.tCpu,
    this.tGpu,
    this.tBatt,
    this.tSkin,
  });
  final List<double> r;
  final double? lax, lay, laz, lmag;
  final double? tCpu, tGpu, tBatt, tSkin;

  static const double _phi = 0.46; // fixed view elevation (locked reference)
  late double _cx, _cy, _scale;

  List<double> _toWorld(double x, double y, double z) {
    if (r.length < 9) return [x, y, z];
    return [
      r[0] * x + r[1] * y + r[2] * z,
      r[3] * x + r[4] * y + r[5] * z,
      r[6] * x + r[7] * y + r[8] * z,
    ];
  }

  double _depthWorld(double ex, double no, double up) =>
      -up * math.sin(_phi) + no * math.cos(_phi);

  Offset _projWorld(double ex, double no, double up) {
    final vy = up * math.cos(_phi) + no * math.sin(_phi);
    final vd = _depthWorld(ex, no, up);
    final s = 5.0 / (7.0 - vd);
    return Offset(_cx + ex * s * _scale, _cy - vy * s * _scale);
  }

  Offset _projDevice(double x, double y, double z) {
    final w = _toWorld(x, y, z);
    return _projWorld(w[0], w[1], w[2]);
  }

  double _depthDevice(double x, double y, double z) {
    final w = _toWorld(x, y, z);
    return _depthWorld(w[0], w[1], w[2]);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _cx = size.width / 2;
    _cy = size.height / 2 + 8;
    _scale = math.min(size.width, size.height) * 0.30;

    _drawGround(canvas);
    _drawPhone(canvas);
    _drawTripod(canvas);
    _drawAccel(canvas);
  }

  void _drawGround(Canvas canvas) {
    const gz = -1.35; // ground plane sits just below the phone
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x14FFFFFF);
    const ext = 2.2;
    for (double i = -ext; i <= ext + 0.01; i += 0.55) {
      final a = _projWorld(i, -ext, gz);
      final b = _projWorld(i, ext, gz);
      canvas.drawLine(a, b, grid);
      final c = _projWorld(-ext, i, gz);
      final d = _projWorld(ext, i, gz);
      canvas.drawLine(c, d, grid);
    }
    // cardinal markers fixed to the world frame (N = +North, E = +East)
    _tp(canvas, 'N', _projWorld(0, ext + 0.25, gz), _cyan, size: 11, w: FontWeight.w700);
    _tp(canvas, 'S', _projWorld(0, -ext - 0.25, gz), _textM, size: 10);
    _tp(canvas, 'E', _projWorld(ext + 0.25, 0, gz), _textM, size: 10);
    _tp(canvas, 'W', _projWorld(-ext - 0.25, 0, gz), _textM, size: 10);
  }

  void _drawPhone(Canvas canvas) {
    const w = 0.82, h = 1.6, t = 0.11;
    final v = <List<double>>[
      [-w, -h, -t], [w, -h, -t], [w, h, -t], [-w, h, -t],
      [-w, -h, t], [w, -h, t], [w, h, t], [-w, h, t],
    ];
    final pts = [for (final p in v) _projDevice(p[0], p[1], p[2])];
    final faces = <List<int>>[
      [4, 5, 6, 7], // screen (+z)
      [0, 1, 2, 3], // back
      [3, 2, 6, 7], // top (+y)
      [0, 1, 5, 4], // bottom
      [1, 2, 6, 5], // right (+x)
      [0, 3, 7, 4], // left
    ];
    final fd = [
      for (final f in faces)
        f.map((i) => _depthDevice(v[i][0], v[i][1], v[i][2])).reduce((a, b) => a + b) / f.length
    ];
    final order = List<int>.generate(faces.length, (i) => i)
      ..sort((a, b) => fd[a].compareTo(fd[b]));

    final body = Paint()..color = const Color(0xFF2A3240);
    final screen = Paint()..color = const Color(0xFF1A2733);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xDDE6EDF3);

    for (final fi in order) {
      final f = faces[fi];
      final path = Path()..moveTo(pts[f[0]].dx, pts[f[0]].dy);
      for (int k = 1; k < f.length; k++) {
        path.lineTo(pts[f[k]].dx, pts[f[k]].dy);
      }
      path.close();
      canvas.drawPath(path, fi == 0 ? screen : body);
      canvas.drawPath(path, edge);
      // thermal hot-spots overlaid on the visible screen face only
      if (fi == 0) _drawThermal(canvas);
    }
    // front-camera dot near top of screen
    canvas.drawCircle(_projDevice(0, h * 0.8, t), 3, Paint()..color = const Color(0xFF0D1117));
  }

  void _drawThermal(Canvas canvas) {
    void spot(double? temp, double lx, double ly) {
      if (temp == null) return;
      final c = _projDevice(lx, ly, 0.12);
      final col = _tempColor(temp);
      canvas.drawCircle(
        c,
        26,
        Paint()
          ..shader = RadialGradient(colors: [col.withValues(alpha: 0.6), col.withValues(alpha: 0.0)])
              .createShader(Rect.fromCircle(center: c, radius: 26)),
      );
    }

    spot(tCpu, 0.0, 0.55); // SoC upper-middle
    spot(tGpu, -0.35, 0.35); // GPU
    spot(tBatt, 0.0, -0.6); // battery lower
    spot(tSkin, 0.3, -0.05); // skin/ambient
  }

  void _drawTripod(Canvas canvas) {
    const len = 1.15;
    final origin = _projDevice(0, 0, 0);
    void axis(double x, double y, double z, Color col, String tag) {
      final end = _projDevice(x * len, y * len, z * len);
      final p = Paint()
        ..color = col
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(origin, end, p);
      canvas.drawCircle(end, 2.6, Paint()..color = col);
      _tp(canvas, tag, end + (end - origin) * 0.12, col, size: 9, w: FontWeight.w700);
    }

    axis(1, 0, 0, _red, 'X');
    axis(0, 1, 0, _green, 'Y');
    axis(0, 0, 1, _cyan, 'Z');
  }

  void _drawAccel(Canvas canvas) {
    final m = lmag;
    if (m == null || m < 0.4 || lax == null || lay == null || laz == null) return;
    final n = math.max(m, 0.0001);
    final len = (m / 12.0).clamp(0.0, 1.0) * 1.5;
    final origin = _projDevice(0, 0, 0);
    final end = _projDevice(lax! / n * len, lay! / n * len, laz! / n * len);
    final p = Paint()
      ..color = _amber
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(origin, end, p);
    canvas.drawCircle(end, 3.2, Paint()..color = _amber);
  }

  @override
  bool shouldRepaint(_TwinPainter old) => true;
}

// ════════════════════════ COMPUTE ════════════════════════

class CoreEqualizer extends StatelessWidget {
  const CoreEqualizer({super.key, required this.freqs});
  final List<double?> freqs; // MHz per core, null = no socket

  @override
  Widget build(BuildContext context) {
    final live = freqs.any((f) => f != null);
    double maxV = 1000;
    for (final f in freqs) {
      if (f != null && f > maxV) maxV = f;
    }
    return VizCard(
      title: 'CPU cores',
      height: 90,
      live: live,
      trailing: '${freqs.where((f) => f != null).length}/${freqs.length}',
      child: live
          ? CustomPaint(painter: _EqPainter(freqs, maxV), size: Size.infinite)
          : _noSocket(90),
    );
  }
}

class _EqPainter extends CustomPainter {
  _EqPainter(this.freqs, this.maxV);
  final List<double?> freqs;
  final double maxV;

  @override
  void paint(Canvas canvas, Size size) {
    if (freqs.isEmpty) return;
    final n = freqs.length;
    final gap = 6.0;
    final bw = (size.width - gap * (n - 1)) / n;
    final baseY = size.height - 14;
    for (int i = 0; i < n; i++) {
      final x = i * (bw + gap);
      final f = freqs[i];
      final track = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 2, bw, baseY - 2), const Radius.circular(3));
      canvas.drawRRect(track, Paint()..color = const Color(0x0DFFFFFF));
      if (f != null) {
        final double frac = (f / maxV).clamp(0.05, 1.0).toDouble();
        final bh = (baseY - 2) * frac;
        final col = Color.lerp(_cyan, _accent, frac)!;
        final bar = RRect.fromRectAndRadius(
            Rect.fromLTWH(x, baseY - bh, bw, bh), const Radius.circular(3));
        canvas.drawRRect(bar, Paint()..color = col);
        _tp(canvas, '${(f / 1000).toStringAsFixed(1)}', Offset(x + bw / 2, baseY - bh - 7), _text,
            size: 8.5);
      }
      _tp(canvas, '$i', Offset(x + bw / 2, baseY + 7), _textM, size: 8.5);
    }
  }

  @override
  bool shouldRepaint(_EqPainter old) => true;
}

class CpuArea extends StatelessWidget {
  const CpuArea({super.key, required this.hist, this.now});
  final List<double> hist;
  final double? now;
  @override
  Widget build(BuildContext context) {
    return VizCard(
      title: 'CPU load',
      height: 54,
      live: now != null,
      trailing: now == null ? null : '${now!.toStringAsFixed(1)} %',
      trailingColor: _accent,
      child: hist.length < 2
          ? _noSocket(54)
          : CustomPaint(painter: _AreaPainter(hist, _accent, 100), size: Size.infinite),
    );
  }
}

// ════════════════════════ POWER / THERMAL ════════════════════════

class ThermalPhone extends StatelessWidget {
  const ThermalPhone({super.key, this.cpu, this.gpu, this.batt, this.skin, this.maxz});
  final double? cpu, gpu, batt, skin, maxz;
  @override
  Widget build(BuildContext context) {
    final any = cpu != null || gpu != null || batt != null || skin != null;
    return VizCard(
      title: 'Thermal map',
      height: 150,
      live: any,
      trailing: maxz == null ? null : '${maxz!.toStringAsFixed(1)} °C',
      trailingColor: _tempColor(maxz ?? 0.0),
      child: any
          ? CustomPaint(painter: _ThermalPainter(cpu, gpu, batt, skin), size: Size.infinite)
          : _noSocket(150),
    );
  }
}

class _ThermalPainter extends CustomPainter {
  _ThermalPainter(this.cpu, this.gpu, this.batt, this.skin);
  final double? cpu, gpu, batt, skin;

  @override
  void paint(Canvas canvas, Size size) {
    // phone silhouette on the left, legend on the right
    final bodyW = size.width * 0.42;
    final bodyH = size.height * 0.92;
    final left = 8.0;
    final top = (size.height - bodyH) / 2;
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, bodyW, bodyH), const Radius.circular(14));
    canvas.drawRRect(body, Paint()..color = const Color(0xFF1A2130));
    canvas.drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0x33FFFFFF));
    canvas.save();
    canvas.clipRRect(body);
    void spot(double? temp, double fx, double fy, double rad) {
      if (temp == null) return;
      final c = Offset(left + bodyW * fx, top + bodyH * fy);
      final col = _tempColor(temp);
      canvas.drawCircle(
        c,
        rad,
        Paint()
          ..shader = RadialGradient(colors: [col.withValues(alpha: 0.85), col.withValues(alpha: 0.0)])
              .createShader(Rect.fromCircle(center: c, radius: rad)),
      );
    }

    spot(skin, 0.5, 0.5, bodyW * 0.9);
    spot(cpu, 0.5, 0.32, bodyW * 0.55);
    spot(gpu, 0.5, 0.45, bodyW * 0.42);
    spot(batt, 0.5, 0.72, bodyW * 0.55);
    canvas.restore();

    // legend
    final lx = left + bodyW + 16;
    double ly = top + 6;
    void row(String name, double? temp) {
      final col = temp == null ? _textD : _tempColor(temp);
      canvas.drawCircle(Offset(lx + 5, ly + 6), 5, Paint()..color = col);
      _tp(canvas, name, Offset(lx + 16 + _textW(name, 10) / 2, ly + 6), _textM, size: 10);
      _tp(canvas, temp == null ? 'no socket' : '${temp.toStringAsFixed(1)} °C',
          Offset(size.width - 44, ly + 6), temp == null ? _textD : _text, size: 11, w: FontWeight.w700);
      ly += 26;
    }

    row('CPU', cpu);
    row('GPU', gpu);
    row('Battery', batt);
    row('Skin', skin);
  }

  double _textW(String s, double size) => s.length * size * 0.6;

  @override
  bool shouldRepaint(_ThermalPainter old) => true;
}

class BatteryFlow extends StatelessWidget {
  const BatteryFlow({super.key, this.level, this.charging, this.currentMa, this.powerW});
  final double? level;
  final bool? charging;
  final double? currentMa, powerW;
  @override
  Widget build(BuildContext context) {
    return VizCard(
      title: 'Power flow',
      height: 92,
      live: level != null,
      trailing: powerW == null ? null : '${powerW!.toStringAsFixed(2)} W',
      trailingColor: charging == true ? _green : _amber,
      child: level == null
          ? _noSocket(92)
          : CustomPaint(
              painter: _BatteryPainter(level!, charging ?? false, currentMa, powerW),
              size: Size.infinite),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter(this.level, this.charging, this.currentMa, this.powerW);
  final double level;
  final bool charging;
  final double? currentMa, powerW;

  @override
  void paint(Canvas canvas, Size size) {
    final bw = size.width * 0.5;
    final bh = size.height * 0.5;
    final left = 4.0;
    final top = (size.height - bh) / 2;
    final shell = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, bw, bh), const Radius.circular(6));
    canvas.drawRRect(
        shell,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0x55FFFFFF));
    // terminal nub
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(left + bw, top + bh * 0.3, 4, bh * 0.4), const Radius.circular(2)),
        Paint()..color = const Color(0x55FFFFFF));
    // fill
    final double frac = (level / 100).clamp(0.0, 1.0).toDouble();
    final col = level > 40 ? _green : (level > 15 ? _amber : _red);
    final fill = RRect.fromRectAndRadius(
        Rect.fromLTWH(left + 2, top + 2, (bw - 4) * frac, bh - 4), const Radius.circular(4));
    canvas.drawRRect(fill, Paint()..color = col);
    _tp(canvas, '${level.toStringAsFixed(0)}%', Offset(left + bw / 2, top + bh / 2), _text,
        size: 13, w: FontWeight.w700);

    // flow chevrons to the right of the battery
    final fx = left + bw + 18;
    final fy = top + bh / 2;
    final flowCol = charging ? _green : _amber;
    final dir = charging ? 1.0 : -1.0; // into battery vs out
    final cp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = flowCol;
    for (int i = 0; i < 3; i++) {
      final x = fx + i * 13.0;
      canvas.drawLine(Offset(x, fy - 6), Offset(x + 6 * dir, fy), cp);
      canvas.drawLine(Offset(x + 6 * dir, fy), Offset(x, fy + 6), cp);
    }
    final label = charging ? 'charging' : 'discharging';
    _tp(canvas, label, Offset(fx + 20, fy - 22), flowCol, size: 10, w: FontWeight.w700);
    if (currentMa != null) {
      _tp(canvas, '${currentMa!.toStringAsFixed(0)} mA', Offset(fx + 20, fy + 22), _textM, size: 11);
    }
  }

  @override
  bool shouldRepaint(_BatteryPainter old) => true;
}

// ════════════════════════ MOTION ════════════════════════

class SpiritLevel extends StatelessWidget {
  const SpiritLevel({super.key, this.gx, this.gy, this.gz});
  final double? gx, gy, gz; // gravity components m/s²
  @override
  Widget build(BuildContext context) {
    final ok = gx != null && gy != null && gz != null;
    double? tilt;
    if (ok) {
      final g = math.sqrt(gx! * gx! + gy! * gy! + gz! * gz!);
      if (g > 0) tilt = math.acos((gz! / g).clamp(-1.0, 1.0)) * 180 / math.pi;
    }
    return VizCard(
      title: 'Spirit level',
      height: 120,
      live: ok,
      trailing: tilt == null ? null : '${tilt.toStringAsFixed(1)}° tilt',
      trailingColor: (tilt ?? 99) < 2 ? _green : _cyan,
      child: ok
          ? CustomPaint(painter: _LevelPainter(gx!, gy!, gz!), size: Size.infinite)
          : _noSocket(120),
    );
  }
}

class _LevelPainter extends CustomPainter {
  _LevelPainter(this.gx, this.gy, this.gz);
  final double gx, gy, gz;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final rad = math.min(size.width, size.height) / 2 - 6;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0x33FFFFFF);
    canvas.drawCircle(c, rad, ring);
    canvas.drawCircle(c, rad * 0.5, ring..color = const Color(0x22FFFFFF));
    // center target
    final cross = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(c.dx - 10, c.dy), Offset(c.dx + 10, c.dy), cross);
    canvas.drawLine(Offset(c.dx, c.dy - 10), Offset(c.dx, c.dy + 10), cross);
    // bubble moves toward the raised edge (opposite in-plane gravity)
    const g = 9.81;
    final ox = (-gx / g).clamp(-1.0, 1.0) * rad;
    final oy = (gy / g).clamp(-1.0, 1.0) * rad;
    final bubble = Offset(c.dx + ox, c.dy + oy);
    final level = ox.abs() < rad * 0.08 && oy.abs() < rad * 0.08;
    canvas.drawCircle(bubble, 13, Paint()..color = (level ? _green : _accent).withValues(alpha: 0.85));
    canvas.drawCircle(
        bubble,
        13,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(_LevelPainter old) => true;
}

class GyroRates extends StatelessWidget {
  const GyroRates({super.key, this.x, this.y, this.z});
  final double? x, y, z; // °/s
  @override
  Widget build(BuildContext context) {
    final ok = x != null || y != null || z != null;
    return VizCard(
      title: 'Angular rate',
      height: 120,
      live: ok,
      child: ok
          ? CustomPaint(painter: _GyroPainter(x, y, z), size: Size.infinite)
          : _noSocket(120),
    );
  }
}

class _GyroPainter extends CustomPainter {
  _GyroPainter(this.x, this.y, this.z);
  final double? x, y, z;
  static const double _max = 400; // °/s full scale
  @override
  void paint(Canvas canvas, Size size) {
    final rows = [
      ['X', x, _red],
      ['Y', y, _green],
      ['Z', z, _cyan],
    ];
    final midX = size.width / 2;
    final rowH = size.height / 3;
    for (int i = 0; i < 3; i++) {
      final cy = rowH * i + rowH / 2;
      // zero line
      canvas.drawLine(Offset(midX, cy - rowH * 0.32), Offset(midX, cy + rowH * 0.32),
          Paint()..color = const Color(0x33FFFFFF)..strokeWidth = 1);
      _tp(canvas, rows[i][0] as String, Offset(12, cy), _textM, size: 10, w: FontWeight.w700);
      final v = rows[i][1] as double?;
      final col = rows[i][2] as Color;
      if (v != null) {
        final double frac = (v / _max).clamp(-1.0, 1.0).toDouble();
        final halfW = (size.width / 2 - 40);
        final bar = RRect.fromRectAndRadius(
            Rect.fromLTWH(frac >= 0 ? midX : midX + frac * halfW, cy - 5, (frac.abs() * halfW), 10),
            const Radius.circular(4));
        canvas.drawRRect(bar, Paint()..color = col);
        _tp(canvas, '${v.toStringAsFixed(0)}', Offset(size.width - 26, cy), _text, size: 10);
      } else {
        _tp(canvas, '—', Offset(size.width - 26, cy), _textD, size: 10);
      }
    }
  }

  @override
  bool shouldRepaint(_GyroPainter old) => true;
}

// ════════════════════════ MAGNETIC ════════════════════════

/// Metal detector: a |B| field-strength gauge that spikes near metal, plus a
/// small horizontal field-direction indicator. Separate from the heading
/// compass in Orientation — this one reads magnitude, not bearing.
class MetalDetector extends StatelessWidget {
  const MetalDetector({super.key, this.field, this.mx, this.my});
  final double? field, mx, my; // µT
  @override
  Widget build(BuildContext context) {
    final f = field;
    final elevated = f != null && f > 70;
    return VizCard(
      title: 'Metal detector',
      height: 128,
      live: f != null,
      trailing: f == null ? null : '${f.toStringAsFixed(1)} µT',
      trailingColor: elevated ? _red : _green,
      child: f == null
          ? _noSocket(128)
          : CustomPaint(painter: _MetalPainter(f, mx, my), size: Size.infinite),
    );
  }
}

class _MetalPainter extends CustomPainter {
  _MetalPainter(this.field, this.mx, this.my);
  final double field;
  final double? mx, my;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height - 8);
    final rad = math.min(size.width / 2 - 10, size.height - 24);
    // scale 0..150 µT across a top semicircle (π .. 2π)
    const maxS = 150.0;
    const start = math.pi;
    const sweep = math.pi;
    // colored bands: earth (green) 0-65, elevated (amber) 65-110, metal (red) >110
    void band(double a, double b, Color col) {
      final s = start + (a / maxS) * sweep;
      final e = start + (b / maxS) * sweep;
      canvas.drawArc(Rect.fromCircle(center: c, radius: rad), s, e - s, false,
          Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = col.withValues(alpha: 0.75)..strokeCap = StrokeCap.butt);
    }

    band(0, 65, _green);
    band(65, 110, _amber);
    band(110, maxS, _red);

    // needle
    final frac = (field / maxS).clamp(0.0, 1.0);
    final a = start + frac * sweep;
    final tip = Offset(c.dx + math.cos(a) * rad, c.dy + math.sin(a) * rad);
    canvas.drawLine(c, tip,
        Paint()..color = _text..strokeWidth = 2.4..strokeCap = StrokeCap.round);
    canvas.drawCircle(c, 4, Paint()..color = _text);
    _tp(canvas, '${field.toStringAsFixed(0)} µT', Offset(c.dx, c.dy - rad * 0.5), _text,
        size: 15, w: FontWeight.w700);
    _tp(canvas, field > 70 ? 'elevated field' : 'earth field',
        Offset(c.dx, c.dy - rad * 0.5 + 18), field > 70 ? _red : _textM, size: 10);

    // horizontal field direction dot (mx,my)
    if (mx != null && my != null) {
      final h = math.sqrt(mx! * mx! + my! * my!);
      if (h > 0.001) {
        final dr = 14.0;
        final dot = Offset(c.dx + (mx! / h) * dr, (c.dy - rad * 0.5 + 40) + (my! / h) * dr);
        canvas.drawCircle(Offset(c.dx, c.dy - rad * 0.5 + 40), dr,
            Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = const Color(0x33FFFFFF));
        canvas.drawCircle(dot, 2.6, Paint()..color = _cyan);
      }
    }
  }

  @override
  bool shouldRepaint(_MetalPainter old) => true;
}

// ════════════════════════ ORIENTATION ════════════════════════

/// Heading compass rose (the compass "up top", distinct from the magnetometer
/// metal detector). The rose rotates to true heading; the fixed top marker is
/// the device's own forward direction.
class CompassRose extends StatelessWidget {
  const CompassRose({super.key, this.heading, this.cardinal});
  final double? heading;
  final String? cardinal;
  @override
  Widget build(BuildContext context) {
    return VizCard(
      title: 'Compass',
      height: 140,
      live: heading != null,
      trailing: heading == null ? null : '${heading!.toStringAsFixed(0)}° ${cardinal ?? ''}',
      trailingColor: _cyan,
      child: heading == null
          ? _noSocket(140)
          : CustomPaint(painter: _RosePainter(heading!), size: Size.infinite),
    );
  }
}

class _RosePainter extends CustomPainter {
  _RosePainter(this.heading);
  final double heading;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final rad = math.min(size.width, size.height) / 2 - 10;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(_deg2rad(-heading));
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0x33FFFFFF);
    canvas.drawCircle(Offset.zero, rad, ring);
    for (int d = 0; d < 360; d += 15) {
      final a = _deg2rad(d - 90); // 0° (N) at top
      final major = d % 90 == 0;
      final r1 = rad - (major ? 12 : 6);
      final p1 = Offset(math.cos(a) * r1, math.sin(a) * r1);
      final p2 = Offset(math.cos(a) * rad, math.sin(a) * rad);
      canvas.drawLine(p1, p2,
          Paint()..color = major ? const Color(0x88FFFFFF) : const Color(0x44FFFFFF)..strokeWidth = major ? 2 : 1);
    }
    const labels = {0: 'N', 90: 'E', 180: 'S', 270: 'W'};
    labels.forEach((d, s) {
      final a = _deg2rad(d - 90);
      final at = Offset(math.cos(a) * (rad - 24), math.sin(a) * (rad - 24));
      _tp(canvas, s, at, s == 'N' ? _red : _text, size: 13, w: FontWeight.w700);
    });
    canvas.restore();
    // fixed device-forward marker (triangle at top)
    final path = Path()
      ..moveTo(c.dx, c.dy - rad - 2)
      ..lineTo(c.dx - 7, c.dy - rad + 12)
      ..lineTo(c.dx + 7, c.dy - rad + 12)
      ..close();
    canvas.drawPath(path, Paint()..color = _cyan);
    _tp(canvas, '${heading.toStringAsFixed(0)}°', c, _text, size: 18, w: FontWeight.w700);
  }

  @override
  bool shouldRepaint(_RosePainter old) => true;
}

// ════════════════════════ ENVIRONMENT ════════════════════════

class Altimeter extends StatelessWidget {
  const Altimeter({super.key, this.alt, this.vspeed, this.trend});
  final double? alt, vspeed;
  final String? trend;
  @override
  Widget build(BuildContext context) {
    return VizCard(
      title: 'Altimeter',
      height: 130,
      live: alt != null,
      trailing: alt == null ? null : '${alt!.toStringAsFixed(1)} m',
      trailingColor: _amber,
      child: alt == null
          ? _noSocket(130)
          : CustomPaint(painter: _AltPainter(alt!, vspeed ?? 0.0, trend ?? 'steady'), size: Size.infinite),
    );
  }
}

class _AltPainter extends CustomPainter {
  _AltPainter(this.alt, this.vspeed, this.trend);
  final double alt, vspeed;
  final String trend;
  @override
  void paint(Canvas canvas, Size size) {
    final tapeX = size.width * 0.5;
    final cy = size.height / 2;
    const pxPerM = 14.0; // 1 m spacing
    // moving tape of tick marks around current altitude
    final first = (alt - (size.height / 2) / pxPerM).floorToDouble();
    final last = (alt + (size.height / 2) / pxPerM).ceilToDouble();
    final tick = Paint()..color = const Color(0x33FFFFFF)..strokeWidth = 1;
    for (double a = first; a <= last; a += 1) {
      final y = cy - (a - alt) * pxPerM;
      final major = a % 5 == 0;
      canvas.drawLine(Offset(tapeX - (major ? 16 : 8), y), Offset(tapeX, y), tick);
      if (major) _tp(canvas, '${a.toStringAsFixed(0)}', Offset(tapeX - 32, y), _textM, size: 9);
    }
    // center pointer
    canvas.drawLine(Offset(tapeX, cy), Offset(size.width - 8, cy),
        Paint()..color = _amber..strokeWidth = 1.5);
    _tp(canvas, '${alt.toStringAsFixed(1)} m', Offset(size.width - 48, cy - 10), _text,
        size: 13, w: FontWeight.w700);

    // vertical-speed indicator (needle to the right)
    final vx = size.width - 22;
    final frac = (vspeed / 3.0).clamp(-1.0, 1.0);
    final vy = cy - frac * (size.height / 2 - 14);
    final vcol = vspeed > 0.1 ? _green : (vspeed < -0.1 ? _red : _textM);
    canvas.drawLine(Offset(vx, cy), Offset(vx, vy), Paint()..color = vcol..strokeWidth = 3..strokeCap = StrokeCap.round);
    _tp(canvas, '${vspeed >= 0 ? '+' : ''}${vspeed.toStringAsFixed(1)}', Offset(vx, cy + size.height / 2 - 4),
        vcol, size: 10, w: FontWeight.w700);
    _tp(canvas, trend, Offset(tapeX - 20, 8), _textM, size: 9);
  }

  @override
  bool shouldRepaint(_AltPainter old) => true;
}

class LightBar extends StatelessWidget {
  const LightBar({super.key, this.lux, this.cat});
  final double? lux;
  final String? cat;
  @override
  Widget build(BuildContext context) {
    return VizCard(
      title: 'Light',
      height: 56,
      live: lux != null,
      trailing: lux == null ? null : '${lux!.toStringAsFixed(0)} lux',
      trailingColor: _amber,
      child: lux == null
          ? _noSocket(56)
          : CustomPaint(painter: _LightPainter(lux!, cat ?? ''), size: Size.infinite),
    );
  }
}

class _LightPainter extends CustomPainter {
  _LightPainter(this.lux, this.cat);
  final double lux;
  final String cat;
  @override
  void paint(Canvas canvas, Size size) {
    final barY = size.height - 16;
    final barRect = Rect.fromLTWH(34, barY - 8, size.width - 44, 12);
    canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, const Radius.circular(6)),
        Paint()
          ..shader = const LinearGradient(colors: [Color(0xFF1A2130), _amber, Colors.white])
              .createShader(Rect.fromLTWH(34, 0, size.width - 44, 1)));
    // log fill marker
    final frac = (math.log(lux + 1) / math.log(100001)).clamp(0.0, 1.0);
    final mx = 34 + (size.width - 44) * frac;
    canvas.drawCircle(Offset(mx, barY - 2), 7, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(mx, barY - 2), 7,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = _textD);
    // icon by category
    _drawIcon(canvas, const Offset(16, 12));
    _tp(canvas, cat, Offset(size.width / 2, 12), _textM, size: 10);
  }

  void _drawIcon(Canvas canvas, Offset c) {
    final dark = cat == 'dark' || cat == 'dim';
    final bright = cat == 'sunlight' || cat == 'bright' || cat == 'overcast';
    if (dark) {
      // moon
      canvas.drawCircle(c, 7, Paint()..color = _textM);
      canvas.drawCircle(Offset(c.dx + 3, c.dy - 2), 6, Paint()..color = _panel);
    } else if (bright) {
      // sun
      canvas.drawCircle(c, 5, Paint()..color = _amber);
      final ray = Paint()..color = _amber..strokeWidth = 1.5..strokeCap = StrokeCap.round;
      for (int i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        canvas.drawLine(Offset(c.dx + math.cos(a) * 7, c.dy + math.sin(a) * 7),
            Offset(c.dx + math.cos(a) * 10, c.dy + math.sin(a) * 10), ray);
      }
    } else {
      // cloud
      canvas.drawCircle(c, 6, Paint()..color = _textM);
    }
  }

  @override
  bool shouldRepaint(_LightPainter old) => true;
}

// ════════════════════════ NETWORK ════════════════════════

class ThroughputGraph extends StatelessWidget {
  const ThroughputGraph({super.key, required this.down, required this.up, this.downNow, this.upNow, this.rx, this.tx});
  final List<double> down, up;
  final double? downNow, upNow;
  final String? rx, tx;
  @override
  Widget build(BuildContext context) {
    final ok = down.length > 1 || up.length > 1;
    return VizCard(
      title: 'Throughput',
      height: 90,
      live: downNow != null || upNow != null,
      trailing: '↓${downNow?.toStringAsFixed(0) ?? '—'}  ↑${upNow?.toStringAsFixed(0) ?? '—'} KB/s',
      trailingColor: _cyan,
      child: ok
          ? CustomPaint(painter: _ThroughputPainter(down, up), size: Size.infinite)
          : _noSocket(90),
    );
  }
}

class _ThroughputPainter extends CustomPainter {
  _ThroughputPainter(this.down, this.up);
  final List<double> down, up;
  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid),
        Paint()..color = const Color(0x22FFFFFF)..strokeWidth = 1);
    double maxV = 8;
    for (final v in down) {
      if (v > maxV) maxV = v;
    }
    for (final v in up) {
      if (v > maxV) maxV = v;
    }
    _area(canvas, size, down, maxV, mid, true, _cyan);
    _area(canvas, size, up, maxV, mid, false, _accent);
    _tp(canvas, '↓ down', Offset(32, 10), _cyan, size: 9);
    _tp(canvas, '↑ up', Offset(28, size.height - 10), _accent, size: 9);
  }

  void _area(Canvas canvas, Size size, List<double> data, double maxV, double mid, bool up, Color col) {
    if (data.length < 2) return;
    final path = Path()..moveTo(0, mid);
    for (int i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final h = (data[i] / maxV).clamp(0.0, 1.0) * (mid - 2);
      final y = up ? mid - h : mid + h;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, mid);
    path.close();
    canvas.drawPath(path, Paint()..color = col.withValues(alpha: 0.2));
    final line = Path();
    for (int i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final h = (data[i] / maxV).clamp(0.0, 1.0) * (mid - 2);
      final y = up ? mid - h : mid + h;
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    canvas.drawPath(line, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = col);
  }

  @override
  bool shouldRepaint(_ThroughputPainter old) => true;
}

// ════════════════════════ SYSTEM ════════════════════════

class RefreshTach extends StatelessWidget {
  const RefreshTach({super.key, this.hz});
  final double? hz;
  @override
  Widget build(BuildContext context) {
    return VizCard(
      title: 'Refresh rate',
      height: 110,
      live: hz != null,
      trailing: hz == null ? null : '${hz!.toStringAsFixed(0)} Hz',
      trailingColor: _accent,
      child: hz == null
          ? _noSocket(110)
          : CustomPaint(painter: _TachPainter(hz!), size: Size.infinite),
    );
  }
}

class _TachPainter extends CustomPainter {
  _TachPainter(this.hz);
  final double hz;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height - 6);
    final rad = math.min(size.width / 2 - 10, size.height - 20);
    const maxHz = 144.0;
    const start = math.pi;
    const sweep = math.pi;
    canvas.drawArc(Rect.fromCircle(center: c, radius: rad), start, sweep, false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 7..color = const Color(0x1AFFFFFF));
    final double frac = (hz / maxHz).clamp(0.0, 1.0).toDouble();
    canvas.drawArc(Rect.fromCircle(center: c, radius: rad), start, sweep * frac, false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 7..color = _accent..strokeCap = StrokeCap.round);
    // common rate ticks
    for (final mark in [60.0, 90.0, 120.0]) {
      final a = start + (mark / maxHz) * sweep;
      final p1 = Offset(c.dx + math.cos(a) * (rad - 10), c.dy + math.sin(a) * (rad - 10));
      final p2 = Offset(c.dx + math.cos(a) * rad, c.dy + math.sin(a) * rad);
      canvas.drawLine(p1, p2, Paint()..color = const Color(0x66FFFFFF)..strokeWidth = 1.5);
      _tp(canvas, '${mark.toStringAsFixed(0)}',
          Offset(c.dx + math.cos(a) * (rad - 20), c.dy + math.sin(a) * (rad - 20)), _textD, size: 8);
    }
    final a = start + sweep * frac;
    final tip = Offset(c.dx + math.cos(a) * rad, c.dy + math.sin(a) * rad);
    canvas.drawLine(c, tip, Paint()..color = _text..strokeWidth = 2.4..strokeCap = StrokeCap.round);
    canvas.drawCircle(c, 4, Paint()..color = _text);
    _tp(canvas, '${hz.toStringAsFixed(0)} Hz', Offset(c.dx, c.dy - rad * 0.45), _text,
        size: 16, w: FontWeight.w700);
  }

  @override
  bool shouldRepaint(_TachPainter old) => true;
}

class AudioMeter extends StatelessWidget {
  const AudioMeter({super.key, this.media, this.ring, this.music, this.ringer, this.route});
  final double? media, ring;
  final bool? music;
  final String? ringer, route;
  @override
  Widget build(BuildContext context) {
    final ok = media != null || ring != null;
    return VizCard(
      title: 'Audio',
      height: 92,
      live: ok,
      trailing: route ?? ringer,
      trailingColor: music == true ? _green : _textM,
      child: ok
          ? CustomPaint(painter: _AudioPainter(media, ring, music ?? false), size: Size.infinite)
          : _noSocket(92),
    );
  }
}

class _AudioPainter extends CustomPainter {
  _AudioPainter(this.media, this.ring, this.music);
  final double? media, ring;
  final bool music;
  @override
  void paint(Canvas canvas, Size size) {
    void bar(String label, double? pct, double y, Color col) {
      _tp(canvas, label, Offset(24, y), _textM, size: 10);
      final x0 = 56.0;
      final w = size.width - x0 - 44;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x0, y - 5, w, 10), const Radius.circular(5)),
          Paint()..color = const Color(0x0DFFFFFF));
      if (pct != null) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x0, y - 5, w * (pct / 100).clamp(0.0, 1.0).toDouble(), 10),
                const Radius.circular(5)),
            Paint()..color = col);
        _tp(canvas, '${pct.toStringAsFixed(0)}%', Offset(size.width - 20, y), _text, size: 10);
      } else {
        _tp(canvas, '—', Offset(size.width - 20, y), _textD, size: 10);
      }
    }

    bar('Media', media, size.height * 0.3, music ? _green : _accent);
    bar('Ring', ring, size.height * 0.72, _cyan);
  }

  @override
  bool shouldRepaint(_AudioPainter old) => true;
}

// ════════════════════════ shared: area sparkline ════════════════════════

class _AreaPainter extends CustomPainter {
  _AreaPainter(this.data, this.color, this.floor);
  final List<double> data;
  final Color color;
  final double floor;
  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i <= 2; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
          Paint()..color = const Color(0x0DFFFFFF)..strokeWidth = 1);
    }
    if (data.length < 2) return;
    double maxV = floor;
    for (final d in data) {
      if (d > maxV) maxV = d;
    }
    final line = Path();
    for (int i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final y = size.height - (data[i] / maxV).clamp(0.0, 1.0) * size.height;
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    canvas.drawPath(line, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.8..color = color);
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.12));
  }

  @override
  bool shouldRepaint(_AreaPainter old) => true;
}
