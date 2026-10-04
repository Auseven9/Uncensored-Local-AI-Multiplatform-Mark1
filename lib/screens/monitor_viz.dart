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
    this.badge,
  });
  final String title;
  final double height;
  final Widget child;
  final Widget? badge;
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
              if (badge != null) ...[const SizedBox(width: 8), badge!],
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

/// On-card verifier: shows the real hardware sensor name, an ARMED indicator,
/// its accuracy, and a LOST flag if a streaming sensor stops delivering.
class SensorBadge extends StatelessWidget {
  const SensorBadge({
    super.key,
    required this.name,
    required this.present,
    required this.alive,
    required this.accuracy,
  });
  final String name;
  final bool present, alive;
  final int accuracy; // -1 unknown, 0 unreliable, 1 low, 2 med, 3 high

  static const List<String> _acc = ['uncal', 'low', 'med', 'high'];

  @override
  Widget build(BuildContext context) {
    final Color c;
    final IconData icon;
    final String label;
    if (!present) {
      c = _textD;
      icon = Icons.do_not_disturb_on_outlined;
      label = 'no sensor';
    } else if (!alive) {
      c = _red;
      icon = Icons.sensors_off;
      label = name.isNotEmpty ? 'LOST · $name' : 'LOST';
    } else {
      c = _green;
      icon = Icons.sensors;
      final a = (accuracy >= 0 && accuracy < 4) ? ' · ${_acc[accuracy]}' : '';
      label = '${name.isNotEmpty ? name : 'ARMED'}$a';
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 168),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.withValues(alpha: 0.10), _panel),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: c),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 8.5, color: c, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════ HERO: DEVICE TWIN ════════════════════════

/// The hero: a top-down "device twin".
///
/// The phone is pinned pointing up and tips in perspective to show its attitude;
/// its tilt is derived directly from the raw GRAVITY vector (the downhill edge
/// drops — physically exact, no Euler sign ambiguity). The compass dial rotates
/// around it with heading (N in red). Live linear-acceleration jitters the phone
/// in its cradle. Grid is the static background. Everything is a real reading,
/// unsmoothed.
class DeviceTwin extends StatelessWidget {
  const DeviceTwin({
    super.key,
    this.grx,
    this.gry,
    this.grz,
    this.compass,
    this.cardinal,
    this.lax,
    this.lay,
    this.pitch,
    this.roll,
    this.pose,
    this.thermMax,
    this.badge,
  });

  final double? grx, gry, grz, compass, lax, lay, pitch, roll, thermMax;
  final String? cardinal, pose;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final live = grx != null || compass != null;
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
                    color: live ? _green : _textD, shape: BoxShape.circle),
              ),
              if (badge != null) ...[const SizedBox(width: 8), Flexible(child: badge!)],
              const Spacer(),
              Text(pose ?? '',
                  style: const TextStyle(fontSize: 11, color: _textM, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 250,
            width: double.infinity,
            child: !live
                ? _noSocket(250)
                : CustomPaint(
                    painter: _TwinPainter(
                      gvx: grx ?? 0.0,
                      gvy: gry ?? 0.0,
                      gvz: grz ?? 0.0,
                      hasGravity: grx != null,
                      heading: compass,
                      ax: lax ?? 0.0,
                      ay: lay ?? 0.0,
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
    required this.gvx,
    required this.gvy,
    required this.gvz,
    required this.hasGravity,
    required this.heading,
    required this.ax,
    required this.ay,
  });
  final double gvx, gvy, gvz, ax, ay;
  final bool hasGravity;
  final double? heading;

  // top-down perspective camera
  static const double _H = 4.6, _f = 3.0;
  static const double _w = 0.6, _h = 1.05, _th = 0.07; // phone half-dims
  late double _cx, _cy, _pscale, _jx, _jy;

  // Rotation taking the measured gravity direction (which Android reports
  // pointing toward the SKY, +9.81 on Z when flat) to world-up (+Z) — the
  // device's true tilt as a real 3D rotation, yaw-free. Built from gravity, so
  // the slab rotates by the exact physical tilt with no Euler sign ambiguity.
  late double _kx, _ky, _c, _s1;
  late bool _flat, _faceDown;

  void _setupRot() {
    final g = math.sqrt(gvx * gvx + gvy * gvy + gvz * gvz);
    if (!hasGravity || g < 1e-6) {
      _flat = true;
      _faceDown = false;
      return;
    }
    final ux = gvx / g, uy = gvy / g, uz = gvz / g;
    _s1 = math.sqrt(ux * ux + uy * uy); // sin(tilt)
    _c = uz; // cos(tilt)
    _faceDown = uz < 0;
    if (_s1 < 1e-6) {
      _flat = true;
      return;
    }
    _flat = false;
    _kx = uy / _s1; // rotation axis = ĝ × ẑ, normalized
    _ky = -ux / _s1;
  }

  // device-local point → leveled (gravity-aligned, no yaw) coordinates
  List<double> _lvl(double px, double py, double pz) {
    if (_flat) {
      return _faceDown ? [px, -py, -pz] : [px, py, pz];
    }
    // Rodrigues rotation about axis k=(_kx,_ky,0) by the tilt angle
    final kdotp = _kx * px + _ky * py;
    final crx = _ky * pz; // (k × p).x
    final cry = -_kx * pz; // (k × p).y
    final crz = _kx * py - _ky * px; // (k × p).z
    final one = 1 - _c;
    return [
      px * _c + crx * _s1 + _kx * kdotp * one,
      py * _c + cry * _s1 + _ky * kdotp * one,
      pz * _c + crz * _s1,
    ];
  }

  Offset _proj(double px, double py, double pz) {
    final q = _lvl(px, py, pz);
    final s = _f / (_H - q[2]);
    return Offset(_cx + q[0] * s * _pscale + _jx, _cy - q[1] * s * _pscale + _jy);
  }

  double _depth(double px, double py, double pz) => _lvl(px, py, pz)[2];

  @override
  void paint(Canvas canvas, Size size) {
    _cx = size.width / 2;
    _cy = size.height / 2;
    final rad = math.min(size.width, size.height) / 2 - 6;
    _pscale = rad * 0.62;
    // bounce from live linear acceleration (real, unsmoothed)
    _jx = (ax * 1.1).clamp(-6.0, 6.0).toDouble();
    _jy = (-ay * 1.1).clamp(-6.0, 6.0).toDouble();
    _setupRot();

    _drawGrid(canvas, rad);
    _drawDial(canvas, rad);
    _drawPhone(canvas);
  }

  void _drawGrid(Canvas canvas, double rad) {
    final inner = rad * 0.66;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(_cx, _cy), radius: inner)));
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x12FFFFFF);
    const step = 22.0;
    for (double d = -inner; d <= inner; d += step) {
      canvas.drawLine(Offset(_cx + d, _cy - inner), Offset(_cx + d, _cy + inner), grid);
      canvas.drawLine(Offset(_cx - inner, _cy + d), Offset(_cx + inner, _cy + d), grid);
    }
    canvas.restore();
  }

  void _drawDial(Canvas canvas, double rad) {
    final center = Offset(_cx, _cy);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0x33FFFFFF);
    canvas.drawCircle(center, rad, ring);
    canvas.drawCircle(center, rad * 0.84, ring..color = const Color(0x1FFFFFFF));

    final h = heading ?? 0;
    canvas.save();
    canvas.translate(_cx, _cy);
    canvas.rotate(_deg2rad(-h)); // dial rotates so N points to true north
    for (int d = 0; d < 360; d += 15) {
      final a = _deg2rad(d - 90); // 0° (N) at top
      final major = d % 90 == 0;
      final r1 = rad - (major ? 13 : 7);
      canvas.drawLine(
        Offset(math.cos(a) * r1, math.sin(a) * r1),
        Offset(math.cos(a) * rad, math.sin(a) * rad),
        Paint()
          ..color = major ? const Color(0x99FFFFFF) : const Color(0x44FFFFFF)
          ..strokeWidth = major ? 2 : 1,
      );
    }
    const labels = {0: 'N', 90: 'E', 180: 'S', 270: 'W'};
    labels.forEach((d, s) {
      final a = _deg2rad(d - 90);
      final at = Offset(math.cos(a) * (rad - 26), math.sin(a) * (rad - 26));
      _tp(canvas, s, at, s == 'N' ? _red : (heading == null ? _textD : _text),
          size: 13, w: FontWeight.w700);
    });
    canvas.restore();
  }

  void _drawPhone(Canvas canvas) {
    // 8 corners of the real 3D slab in device coordinates
    // (+Z = screen normal, +Y = top/forward edge, +X = right)
    final v = <List<double>>[
      [-_w, -_h, -_th], [_w, -_h, -_th], [_w, _h, -_th], [-_w, _h, -_th],
      [-_w, -_h, _th], [_w, -_h, _th], [_w, _h, _th], [-_w, _h, _th],
    ];
    final pts = [for (final p in v) _proj(p[0], p[1], p[2])];
    final faces = <List<int>>[
      [4, 5, 6, 7], // screen (+z)
      [0, 1, 2, 3], // back (−z)
      [3, 2, 6, 7], // top (+y)
      [0, 1, 5, 4], // bottom (−y)
      [1, 2, 6, 5], // right (+x)
      [0, 3, 7, 4], // left (−x)
    ];
    final fd = [
      for (final f in faces)
        f.map((i) => _depth(v[i][0], v[i][1], v[i][2])).reduce((a, b) => a + b) / f.length
    ];
    final order = List<int>.generate(faces.length, (i) => i)
      ..sort((a, b) => fd[a].compareTo(fd[b])); // far (low) first

    final screenCol = Paint()..color = const Color(0xFF16222C);
    final body = Paint()..color = const Color(0xFF2A3340);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xDDE6EDF3);

    for (final fi in order) {
      final f = faces[fi];
      final path = Path()..moveTo(pts[f[0]].dx, pts[f[0]].dy);
      for (int k = 1; k < f.length; k++) {
        path.lineTo(pts[f[k]].dx, pts[f[k]].dy);
      }
      path.close();
      canvas.drawPath(path, fi == 0 ? screenCol : body);
      canvas.drawPath(path, edge);
      if (fi == 0 && !_faceDown) {
        canvas.drawPath(path, Paint()..color = const Color(0x2222D3EE)); // screen glow
      }
    }

    // front-camera dot on the screen face
    if (!_faceDown) {
      canvas.drawCircle(_proj(0, _h * 0.82, _th), 2.4, Paint()..color = const Color(0xFF0D1117));
    }
    // red forward nose arrow at +Y (marks the phone's top edge)
    final tip = _proj(0, _h + 0.3, _th);
    final bl = _proj(-0.2, _h + 0.04, _th);
    final br = _proj(0.2, _h + 0.04, _th);
    final arrow = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(bl.dx, bl.dy)
      ..lineTo(br.dx, br.dy)
      ..close();
    canvas.drawPath(arrow, Paint()..color = _red);
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
    // concentric stepped rings; inner rings shift toward the downhill side for
    // a parallax "bowl" that tilts with gravity (bubble floats the other way)
    const g2 = 9.81;
    final lowDir = Offset(
        (gx / g2).clamp(-1.0, 1.0).toDouble(), (-gy / g2).clamp(-1.0, 1.0).toDouble());
    final parallax = rad * 0.16;
    const n = 5;
    for (int i = 0; i < n; i++) {
      final rr = rad * (1.0 - i * 0.2);
      final depth = i / (n - 1);
      final rc = Offset(c.dx + lowDir.dx * parallax * depth, c.dy + lowDir.dy * parallax * depth);
      canvas.drawCircle(
          rc,
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = i == 0 ? 1.4 : 1.0
            ..color = Color.fromRGBO(255, 255, 255, 0.05 + 0.03 * (n - i)));
    }
    // center target (true level point, fixed)
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

/// Motion & impact — an honest high-energy / jolt instrument. Live linear-accel
/// magnitude fills the bar; a peak-hold tick marks the strongest recent jolt.
/// (This is what the sensor is genuinely good at — not gait classification.)
class ImpactMeter extends StatelessWidget {
  const ImpactMeter({super.key, this.now, this.peak, this.state, this.freefall});
  final double? now, peak;
  final String? state;
  final bool? freefall;
  @override
  Widget build(BuildContext context) {
    final ok = now != null;
    final hot = freefall == true || state == 'impact';
    return VizCard(
      title: 'Motion & impact',
      height: 56,
      live: ok,
      trailing: freefall == true ? 'FREE-FALL' : state,
      trailingColor: hot ? _red : (state == 'still' ? _textM : _cyan),
      child: ok
          ? CustomPaint(painter: _ImpactPainter(now!, peak ?? now!), size: Size.infinite)
          : _noSocket(56),
    );
  }
}

class _ImpactPainter extends CustomPainter {
  _ImpactPainter(this.now, this.peak);
  final double now, peak;
  static const double _max = 30; // m/s² full scale (linear accel)
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - 14;
    final bw = size.width;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, y - 7, bw, 14), const Radius.circular(7)),
        Paint()..color = const Color(0x0DFFFFFF));
    final nf = (now / _max).clamp(0.0, 1.0).toDouble();
    final col = now > 18 ? _red : (now > 6 ? _amber : _cyan);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, y - 7, bw * nf, 14), const Radius.circular(7)),
        Paint()..color = col);
    final pf = (peak / _max).clamp(0.0, 1.0).toDouble();
    final px = bw * pf;
    canvas.drawLine(Offset(px, y - 10), Offset(px, y + 10), Paint()..color = _red..strokeWidth = 2.5);
    _tp(canvas, '${now.toStringAsFixed(1)} m/s²', Offset(40, 8), _textM, size: 9.5);
    _tp(canvas, 'peak ${peak.toStringAsFixed(1)}', Offset(size.width - 46, 8), _red, size: 9.5);
  }

  @override
  bool shouldRepaint(_ImpactPainter old) => true;
}

// ════════════════════════ MAGNETIC ════════════════════════

/// Metal detector. The magnetometer reads the ambient magnetic field (µT);
/// ferromagnetic metal and magnets distort it. Tap ZERO to capture the local
/// earth-field baseline, then the gauge shows deviation Δ|B| from that zero —
/// the way a real detector works, far more sensitive than the absolute field.
/// A sensitivity control sets the Δ full-scale. Ferrous only (not aluminium /
/// copper). Values are raw — baseline subtraction is a reference, not smoothing.
class MetalDetector extends StatefulWidget {
  const MetalDetector({super.key, this.field, this.mx, this.my});
  final double? field, mx, my; // µT
  @override
  State<MetalDetector> createState() => _MetalDetectorState();
}

class _MetalDetectorState extends State<MetalDetector> {
  double? _baseline;
  int _sensIndex = 1;
  static const List<double> _scales = [15, 40, 100];

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    final scale = _scales[_sensIndex];
    final delta = (_baseline != null && f != null) ? f - _baseline! : null;
    final elevated =
        delta != null ? delta.abs() > scale * 0.6 : (f != null && f > 70);
    final trailing = _baseline == null
        ? (f == null ? null : '${f.toStringAsFixed(1)} µT')
        : (delta == null ? null : 'Δ ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} µT');
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
              const Text('Metal detector',
                  style: TextStyle(fontSize: 12, color: _textM, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: f == null ? _textD : (elevated ? _red : _green),
                    shape: BoxShape.circle),
              ),
              const Spacer(),
              if (trailing != null)
                Text(trailing,
                    style: TextStyle(
                        fontSize: 12,
                        color: elevated ? _red : _cyan,
                        fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 120,
            width: double.infinity,
            child: f == null
                ? _noSocket(120)
                : CustomPaint(
                    painter: _MetalPainter(f, _baseline, scale, widget.mx, widget.my),
                    size: Size.infinite),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _btn(_baseline == null ? 'ZERO' : 'RE-ZERO', _cyan,
                  () => setState(() => _baseline = widget.field)),
              if (_baseline != null) const SizedBox(width: 8),
              if (_baseline != null)
                _btn('CLEAR', _textM, () => setState(() => _baseline = null)),
              const Spacer(),
              _btn('±${scale.toStringAsFixed(0)} µT', _accent,
                  () => setState(() => _sensIndex = (_sensIndex + 1) % _scales.length)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, Color col, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Color.alphaBlend(col.withValues(alpha: 0.12), _panel),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: col.withValues(alpha: 0.5)),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 11, color: col, fontWeight: FontWeight.w700)),
        ),
      );
}

class _MetalPainter extends CustomPainter {
  _MetalPainter(this.field, this.baseline, this.scale, this.mx, this.my);
  final double field, scale;
  final double? baseline, mx, my;

  void _needle(Canvas canvas, Offset c, double rad, double a, Color col) {
    final tip = Offset(c.dx + math.cos(a) * rad, c.dy + math.sin(a) * rad);
    canvas.drawLine(
        c, tip, Paint()..color = col..strokeWidth = 2.4..strokeCap = StrokeCap.round);
    canvas.drawCircle(c, 4, Paint()..color = col);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height - 18);
    final rad = math.min(size.width / 2 - 10, size.height - 34);
    const start = math.pi, sweep = math.pi;
    final up = start + sweep * 0.5; // straight up = zero deflection

    if (baseline == null) {
      // absolute mode: 0..150 µT with earth/elevated/metal bands
      const maxS = 150.0;
      void band(double a, double b, Color col) {
        final s = start + (a / maxS) * sweep;
        final e = start + (b / maxS) * sweep;
        canvas.drawArc(Rect.fromCircle(center: c, radius: rad), s, e - s, false,
            Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = col.withValues(alpha: 0.7));
      }

      band(0, 65, _green);
      band(65, 110, _amber);
      band(110, maxS, _red);
      final frac = (field / maxS).clamp(0.0, 1.0).toDouble();
      _needle(canvas, c, rad, start + frac * sweep, _text);
      _tp(canvas, '${field.toStringAsFixed(0)} µT', Offset(c.dx, c.dy - rad * 0.45), _text,
          size: 15, w: FontWeight.w700);
      _tp(canvas, 'tap ZERO to calibrate', Offset(c.dx, c.dy - rad * 0.45 + 18), _textM, size: 10);
      return;
    }

    // deviation mode: Δ|B| centered, ±scale full-deflection
    final delta = field - baseline!;
    final frac = (delta / scale).clamp(-1.0, 1.0).toDouble();
    final mag = delta.abs();
    final defCol = mag > scale * 0.6 ? _red : (mag > scale * 0.25 ? _amber : _green);
    canvas.drawArc(Rect.fromCircle(center: c, radius: rad), start, sweep, false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = const Color(0x22FFFFFF));
    canvas.drawArc(Rect.fromCircle(center: c, radius: rad), up, frac * sweep * 0.5, false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = defCol..strokeCap = StrokeCap.round);
    // zero tick at top
    canvas.drawLine(
        Offset(c.dx + math.cos(up) * (rad - 12), c.dy + math.sin(up) * (rad - 12)),
        Offset(c.dx + math.cos(up) * rad, c.dy + math.sin(up) * rad),
        Paint()..color = _textM..strokeWidth = 1.5);
    _needle(canvas, c, rad, up + frac * sweep * 0.5, _text);
    _tp(canvas, 'Δ ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} µT',
        Offset(c.dx, c.dy - rad * 0.45), defCol, size: 15, w: FontWeight.w700);
    _tp(canvas, mag > scale * 0.6 ? 'METAL' : (mag > scale * 0.25 ? 'near' : 'clear'),
        Offset(c.dx, c.dy - rad * 0.45 + 18), mag > scale * 0.6 ? _red : _textM,
        size: 10, w: FontWeight.w700);
    // proximity bar
    final pf = (mag / scale).clamp(0.0, 1.0).toDouble();
    final bw = size.width * 0.6;
    final bx = c.dx - bw / 2;
    final by = size.height - 4.0;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(bx, by - 4, bw, 5), const Radius.circular(3)),
        Paint()..color = const Color(0x0DFFFFFF));
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(bx, by - 4, bw * pf, 5), const Radius.circular(3)),
        Paint()..color = defCol);
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

// ════════════════════════ ON-CARD LIVENESS MICRO-VIZ ════════════════════════

/// Tiny auto-scaled sparkline of a reading's recent real samples. Its only job
/// is to prove the sensor is live and ticking: the line moves while values
/// stream, and it flattens (but still draws) when a reading holds steady.
class MicroSpark extends StatelessWidget {
  const MicroSpark({super.key, required this.data, required this.color, this.height = 20});
  final List<double> data;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: data.length < 2
            ? const SizedBox.expand()
            : CustomPaint(painter: _MicroSparkPainter(List<double>.of(data), color)),
      );
}

class _MicroSparkPainter extends CustomPainter {
  _MicroSparkPainter(this.data, this.color);
  final List<double> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    double lo = data.first, hi = data.first;
    for (final d in data) {
      if (d < lo) lo = d;
      if (d > hi) hi = d;
    }
    final double span = (hi - lo).abs();
    final bool flat = span < 1e-9;
    final double usable = size.height - 3;

    double yAt(double v) {
      final double n = flat ? 0.5 : ((v - lo) / span).clamp(0.0, 1.0).toDouble();
      return size.height - n * usable - 1.5;
    }

    final line = Path();
    for (int i = 0; i < data.length; i++) {
      final double x = size.width * i / (data.length - 1);
      final double y = yAt(data[i]);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeJoin = StrokeJoin.round
          ..color = color);
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawCircle(Offset(size.width - 1.5, yAt(data.last)), 1.8, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MicroSparkPainter old) => true;
}

/// Pulse lane for state readings (strings/booleans). Each real update time is a
/// tick that marches left over a window, brightest when freshest — so you can
/// see the reading pulse as it changes, not just a static label.
class PulseLane extends StatelessWidget {
  const PulseLane({
    super.key,
    required this.beats,
    required this.color,
    required this.now,
    this.height = 20,
    this.windowMs = 3000,
  });
  final List<int> beats;
  final Color color;
  final int now;
  final double height;
  final int windowMs;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _PulsePainter(List<int>.of(beats), color, now, windowMs)),
      );
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.beats, this.color, this.now, this.windowMs);
  final List<int> beats;
  final Color color;
  final int now;
  final int windowMs;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1),
        Paint()..color = const Color(0x0DFFFFFF)..strokeWidth = 1);
    for (final b in beats) {
      final int age = now - b;
      if (age < 0 || age > windowMs) continue;
      final double frac = 1 - age / windowMs;
      final double x = size.width * frac;
      canvas.drawLine(
          Offset(x, size.height),
          Offset(x, 2),
          Paint()
            ..color = color.withValues(alpha: (0.25 + 0.6 * frac).clamp(0.0, 1.0).toDouble())
            ..strokeWidth = 1.6);
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => true;
}

// ════════════════════════ EVENT LAMPS ════════════════════════

/// One fire-and-flash event sensor, for the [EventLamps] row.
class EventLampData {
  final String label;
  final bool armed;
  final int count;
  final int ageMs;
  const EventLampData(this.label, this.armed, this.count, this.ageMs);
}

/// A row of lamps for the device's event sensors. A lamp glows on each fire
/// (real trigger), shows its running count, and reports honestly when a sensor
/// is present but can't fire without a permission.
class EventLamps extends StatelessWidget {
  const EventLamps({super.key, required this.lamps});
  final List<EventLampData> lamps;

  static const Map<String, String> _names = {
    'tilt': 'Tilt',
    'sigmotion': 'Sig-motion',
    'stepdet': 'Step',
  };

  @override
  Widget build(BuildContext context) {
    final armed = lamps.where((l) => l.armed).length;
    return VizCard(
      title: 'Event sensors',
      height: 62,
      live: armed > 0,
      trailing: '$armed/${lamps.length} armed',
      child: Row(children: [for (final l in lamps) Expanded(child: _lamp(l))]),
    );
  }

  Widget _lamp(EventLampData l) {
    final bool fired = l.ageMs >= 0 && l.ageMs < 700;
    final Color c = !l.armed ? _textD : (fired ? _amber : _green);
    final String sub = l.armed
        ? '${l.count}'
        : (l.label == 'stepdet' ? 'needs perm' : 'waiting');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fired ? c : c.withValues(alpha: 0.16),
            border: Border.all(color: c, width: 1.3),
            boxShadow: fired ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 8)] : null,
          ),
        ),
        const SizedBox(height: 5),
        Text(_names[l.label] ?? l.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 8.5, color: _textM, fontWeight: FontWeight.w600)),
        Text(sub, style: TextStyle(fontSize: 8, color: c, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ════════════════════════ HEARING: MIC VU + WAVEFORM ════════════════════════

/// Live microphone: scrolling waveform (real PCM, downsampled) over a VU meter
/// (RMS dBFS with a peak-hold tick). Driven only when the mic socket is open.
class VuWaveform extends StatelessWidget {
  const VuWaveform({super.key, required this.wave, this.db, this.peak, this.height = 100});
  final List<double> wave;
  final double? db, peak;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _VuPainter(List<double>.of(wave), db, peak)),
      );
}

class _VuPainter extends CustomPainter {
  _VuPainter(this.wave, this.db, this.peak);
  final List<double> wave;
  final double? db, peak;
  double _n(double d) => ((d + 60) / 60).clamp(0.0, 1.0).toDouble();
  @override
  void paint(Canvas canvas, Size size) {
    final double waveH = size.height - 26;
    final double midY = waveH / 2;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY),
        Paint()..color = const Color(0x14FFFFFF)..strokeWidth = 1);
    if (wave.length >= 2) {
      final path = Path();
      for (int i = 0; i < wave.length; i++) {
        final double x = size.width * i / (wave.length - 1);
        final double y = midY - wave[i].clamp(-1.0, 1.0).toDouble() * (midY - 2);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeJoin = StrokeJoin.round
            ..color = _green);
    } else {
      _tp(canvas, 'tap LIVE to open the mic', Offset(size.width / 2, midY), _textD, size: 11);
    }
    final double by = size.height - 9.0;
    final double bw = size.width;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, by - 7, bw, 14), const Radius.circular(7)),
        Paint()..color = const Color(0x0DFFFFFF));
    final d = db;
    if (d != null) {
      final double f = _n(d);
      final Color col = d > -6 ? _red : (d > -20 ? _amber : _green);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(0, by - 7, bw * f, 14), const Radius.circular(7)),
          Paint()..color = col);
      final p = peak;
      if (p != null) {
        final double px = (bw * _n(p)).clamp(0.0, bw).toDouble();
        canvas.drawLine(Offset(px, by - 9), Offset(px, by + 9), Paint()..color = _red..strokeWidth = 2);
      }
      _tp(canvas, '${d.toStringAsFixed(0)} dBFS', Offset(42, by), _text, size: 9.5, w: FontWeight.w700);
    }
  }

  @override
  bool shouldRepaint(_VuPainter old) => true;
}

// ════════════════════════ LOCATION: GNSS SKY PLOT ════════════════════════

/// One satellite for the sky plot: azimuth/elevation (deg), C/N0 (dB-Hz),
/// constellation type, and whether used in the fix.
class SatDot {
  final double az, el, cn0;
  final int constType;
  final bool used;
  const SatDot(this.az, this.el, this.cn0, this.constType, this.used);
}

/// Polar sky plot of the live GNSS constellation — zenith at centre, horizon at
/// the rim, azimuth clockwise from N. Dot colour is real signal strength (C/N0);
/// filled = used in the position fix, ring = visible but unused.
class SkyPlot extends StatelessWidget {
  const SkyPlot({super.key, required this.sats, this.used = 0, this.seen = 0, this.height = 230});
  final List<SatDot> sats;
  final int used, seen;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _SkyPainter(sats, used, seen)),
      );
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.sats, this.used, this.seen);
  final List<SatDot> sats;
  final int used, seen;
  Color _cn0Color(double c) {
    if (c >= 35) return _green;
    if (c >= 25) return _amber;
    if (c > 0) return _red;
    return _textD;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2 + 4);
    final double r = math.min(size.width, size.height) / 2 - 16;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x33FFFFFF);
    for (final frac in const [1.0, 0.6667, 0.3333]) {
      canvas.drawCircle(c, r * frac, ring);
    }
    final axis = Paint()..color = const Color(0x1AFFFFFF)..strokeWidth = 1;
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), axis);
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), axis);
    const cardinals = <List<Object>>[
      [0, 'N'],
      [90, 'E'],
      [180, 'S'],
      [270, 'W'],
    ];
    for (final e in cardinals) {
      final a = _deg2rad((e[0] as int) - 90);
      final at = Offset(c.dx + math.cos(a) * (r + 9), c.dy + math.sin(a) * (r + 9));
      _tp(canvas, e[1] as String, at, (e[0] as int) == 0 ? _red : _textM, size: 10, w: FontWeight.w700);
    }
    for (final s in sats) {
      final double rr = ((90 - s.el) / 90).clamp(0.0, 1.0).toDouble() * r;
      final a = _deg2rad(s.az - 90);
      final p = Offset(c.dx + math.cos(a) * rr, c.dy + math.sin(a) * rr);
      final col = _cn0Color(s.cn0);
      if (s.used) {
        canvas.drawCircle(p, 4.2, Paint()..color = col);
        canvas.drawCircle(
            p,
            4.2,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = Colors.white.withValues(alpha: 0.8));
      } else {
        canvas.drawCircle(
            p,
            3.4,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..color = col);
      }
    }
    _tp(canvas, '$used used · $seen in view', Offset(size.width / 2, 8), _textM, size: 10, w: FontWeight.w700);
    if (sats.isEmpty) {
      _tp(canvas, 'acquiring sky… (go near a window)', c, _textD, size: 11);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => true;
}
