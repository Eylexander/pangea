import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'map.dart';
import 'world.dart';

/// Colors of the globe: a softly shaded sea, plain land, hairline borders.
class GlobePalette {
  const GlobePalette._(this.seaCenter, this.seaRim, this.land, this.border, this.grid);
  final Color seaCenter, seaRim, land, border, grid;

  static const light = GlobePalette._(
    Color(0xFFEAF1FA),
    Color(0xFFCAD8EA),
    Color(0xFFFFFFFF),
    Color(0xFFB3BFD1),
    Color(0x141F4E8C),
  );
  static const dark = GlobePalette._(
    Color(0xFF1B2642),
    Color(0xFF0E1528),
    Color(0xFF2C3350),
    Color(0xFF4A5577),
    Color(0x10FFFFFF),
  );

  static GlobePalette of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

const _rad = math.pi / 180;

/// A country's rings ready for the orthographic projection: longitude (radians), sin and cos of latitude.
class _Rings {
  _Rings(Country c)
    : rings = [
        for (final poly in c.polygons)
          for (final r in poly) _prepare(r),
      ];
  final List<(Float32List, Float32List, Float32List)> rings;

  static (Float32List, Float32List, Float32List) _prepare(Float32List r) {
    final n = r.length ~/ 2;
    final lam = Float32List(n), sp = Float32List(n), cp = Float32List(n);
    for (var i = 0; i < n; i++) {
      lam[i] = r[2 * i] * _rad;
      final phi = r[2 * i + 1] * _rad;
      sp[i] = math.sin(phi);
      cp[i] = math.cos(phi);
    }
    return (lam, sp, cp);
  }
}

final _rings = <String, _Rings>{};

/// Rough angular radius of a country (radians), to skip the ones on the far side.
final _radius = <String, double>{};
double _angularRadius(Country c) => _radius.putIfAbsent(c.id, () => _rectRadius(c.bounds));

double _rectRadius(Rect b) {
  final w = b.width * math.cos(b.center.dy * _rad), h = b.height;
  return math.min(math.pi, math.sqrt(w * w + h * h) / 2 * _rad + 0.02);
}

/// Where the globe looks (radians) and how close.
class _View {
  const _View(this.lam, this.phi, this.zoom);
  final double lam, phi, zoom;
}

/// A 3D globe (orthographic projection): drag to spin it, pinch to zoom, tap a country.
class Globe extends StatefulWidget {
  const Globe({
    super.key,
    this.fill,
    this.showAll = true,
    this.onTap,
    this.onTapPoint,
    this.marks = const [],
    this.spin = 0,
    this.interactive = true,
    this.look = const (10, 25),
  });

  /// Color of each country. Null: plain land when [showAll], not drawn at all otherwise.
  final Color? Function(Country c)? fill;
  final bool showAll;
  final void Function(Country? c)? onTap;

  /// Where the globe was tapped (lon, lat), for dropping a pin.
  final void Function(double lon, double lat)? onTapPoint;
  final List<MapMark> marks;

  /// Idle rotation in degrees per second (the home card's globe turns on its own).
  final double spin;
  final bool interactive;

  /// First point facing the viewer (lon, lat).
  final (double, double) look;

  @override
  State<Globe> createState() => GlobeState();
}

class GlobeState extends State<Globe> with TickerProviderStateMixin {
  late final _view = ValueNotifier(_View(widget.look.$1 * _rad, widget.look.$2 * _rad, 1));
  late final _ticker = createTicker(_tick);
  late final _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..addListener(_moveStep);
  late final _curve = CurvedAnimation(parent: _move, curve: Curves.easeInOutCubic);
  _View _from = const _View(0, 0, 1), _to = const _View(0, 0, 1);
  Duration _last = Duration.zero;
  var _vLam = 0.0, _vPhi = 0.0, _startZoom = 1.0;
  var _held = false;
  Size _size = Size.zero;
  var _fullHeight = 0.0;

  double get _radiusAt1 => math.min(_size.width, _fullHeight) / 2 * 0.92;

  @override
  void initState() {
    super.initState();
    _wake();
  }

  /// Frames are only asked for while the globe spins or glides: an idle app must stay idle.
  void _wake() {
    if (!_ticker.isActive && (widget.spin != 0 || _vLam.abs() > 1e-3 || _vPhi.abs() > 1e-3)) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _move.dispose();
    _view.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0 || dt > 0.1 || _held || _move.isAnimating) return;
    final v = _view.value;
    final gliding = _vLam.abs() > 1e-3 || _vPhi.abs() > 1e-3;
    if (!gliding && widget.spin == 0) {
      _ticker.stop();
      return;
    }
    if (gliding) {
      // Fling: glide and slow down.
      _set(v.lam + _vLam * dt, v.phi + _vPhi * dt, v.zoom);
      final k = math.exp(-3 * dt);
      _vLam *= k;
      _vPhi *= k;
    } else if (widget.spin != 0) {
      _set(v.lam + widget.spin * _rad * dt, v.phi, v.zoom);
    }
  }

  void _set(double lam, double phi, double zoom) =>
      _view.value = _View(lam, phi.clamp(-1.35, 1.35), zoom.clamp(1.0, 14.0));

  /// Turns the globe to face (lon, lat) at [zoom].
  void lookAt(double lon, double lat, {double zoom = 1, bool animate = true}) {
    _vLam = _vPhi = 0;
    final from = _view.value;
    // The short way round.
    final dLam = ((lon * _rad - from.lam) + math.pi) % (2 * math.pi) - math.pi;
    final to = _View(from.lam + dLam, lat * _rad, zoom);
    if (!animate) {
      _set(to.lam, to.phi, to.zoom);
      return;
    }
    _from = from;
    _to = to;
    _move.forward(from: 0);
  }

  void _moveStep() {
    final (from, to) = (_from, _to);
    final t = _curve.value;
    // Pull back a little mid-way on long turns, like a camera.
    final travel = math.min(1.0, ((to.lam - from.lam).abs() + (to.phi - from.phi).abs()) / math.pi);
    final dip = math.sin(t * math.pi) * travel * 0.35 * math.min(from.zoom, to.zoom);
    _set(
      from.lam + (to.lam - from.lam) * t,
      from.phi + (to.phi - from.phi) * t,
      from.zoom + (to.zoom - from.zoom) * t - dip,
    );
  }

  /// Turns and zooms so that all [countries] are in view.
  /// [minReach] (radians) keeps some room around small countries, so the globe stays a globe.
  /// [points] (lon, lat) are kept in view too.
  void frame(
    List<Country> countries, {
    List<(double, double)> points = const [],
    bool animate = true,
    double minReach = 0.12,
  }) {
    // Each spot with its size: main landmass only (French Guiana mustn't make France span the Atlantic),
    // and capped (Russia alone would otherwise make "Europe" the whole hemisphere).
    final spots = [
      for (final c in countries) (c.lon, c.lat, math.min(0.2, _rectRadius(c.mainBounds) * 0.7)),
      for (final (lon, lat) in points) (lon, lat, 0.0),
    ];
    if (spots.isEmpty) return;
    var (x, y, z) = (0.0, 0.0, 0.0);
    for (final (lon, lat, _) in spots) {
      final la = lon * _rad, ph = lat * _rad;
      x += math.cos(ph) * math.cos(la);
      y += math.cos(ph) * math.sin(la);
      z += math.sin(ph);
    }
    final lon = math.atan2(y, x), lat = math.atan2(z, math.sqrt(x * x + y * y));
    var reach = 0.0;
    for (final (lo, la, size) in spots) {
      reach = math.max(reach, _angle(lon, lat, lo * _rad, la * _rad) + size);
    }
    reach = math.max(reach, minReach);
    final zoom = reach >= math.pi / 2 ? 1.0 : 0.95 / math.sin(reach);
    lookAt(lon / _rad, lat / _rad, zoom: zoom, animate: animate);
  }

  static double _angle(double lam1, double phi1, double lam2, double phi2) {
    final c = math.sin(phi1) * math.sin(phi2) + math.cos(phi1) * math.cos(phi2) * math.cos(lam2 - lam1);
    return math.acos(c.clamp(-1.0, 1.0));
  }

  /// Screen point → (lon, lat) in degrees, or null off the globe.
  (double, double)? _unproject(Offset p) {
    final v = _view.value;
    final r = _radiusAt1 * v.zoom;
    final x = (p.dx - _size.width / 2) / r, y = -(p.dy - _size.height / 2) / r;
    final rho = math.sqrt(x * x + y * y);
    if (rho > 1) return null;
    if (rho == 0) return (v.lam / _rad, v.phi / _rad);
    final c = math.asin(rho);
    final phi = math.asin(math.cos(c) * math.sin(v.phi) + y * math.sin(c) * math.cos(v.phi) / rho);
    final lam =
        v.lam + math.atan2(x * math.sin(c), rho * math.cos(v.phi) * math.cos(c) - y * math.sin(v.phi) * math.sin(c));
    return (((lam / _rad) + 540) % 360 - 180, phi / _rad);
  }

  void _tap(Offset p) {
    final ll = _unproject(p);
    if (ll == null) return widget.onTap?.call(null);
    final (lon, lat) = ll;
    widget.onTapPoint?.call(lon, lat);
    if (widget.onTap == null) return;
    final world = World.instance;
    for (final c in world.countries) {
      if (c.contains(lon, lat)) return widget.onTap?.call(c);
    }
    // The nearest tiny country within a finger's reach.
    final v = _view.value;
    final r = _radiusAt1 * v.zoom;
    Country? best;
    var bestD = 24.0;
    for (final c in world.countries.where((c) => c.tiny)) {
      final q = _project(v, r, c.lon * _rad, math.sin(c.lat * _rad), math.cos(c.lat * _rad));
      if (q == null) continue;
      final d = (q - p).distance;
      if (d < bestD) (best, bestD) = (c, d);
    }
    widget.onTap?.call(best);
  }

  Offset? _project(_View v, double r, double lam, double sp, double cp) {
    final dl = lam - v.lam;
    final cdl = math.cos(dl);
    if (math.sin(v.phi) * sp + math.cos(v.phi) * cp * cdl < 0) return null;
    final x = cp * math.sin(dl), y = math.cos(v.phi) * sp - math.sin(v.phi) * cp * cdl;
    return Offset(_size.width / 2 + r * x, _size.height / 2 - r * y);
  }

  @override
  Widget build(BuildContext context) {
    final palette = GlobePalette.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        // The keyboard squeezes the globe (Neighbors, Road trip): keep the full height's scale, or it looks zoomed out.
        if (box.maxWidth != _size.width || box.maxHeight > _fullHeight) _fullHeight = box.maxHeight;
        _size = box.biggest;
        // Clipped: zoomed in, the sphere is bigger than the widget.
        final paint = ClipRect(
          child: CustomPaint(
            size: box.biggest,
            painter: _GlobePainter(_view, palette, widget.fill, widget.showAll, widget.marks),
          ),
        );
        if (!widget.interactive) return paint;
        return GestureDetector(
          onTapUp: widget.onTap == null && widget.onTapPoint == null ? null : (d) => _tap(d.localPosition),
          onScaleStart: (_) {
            _held = true;
            _move.stop();
            _vLam = _vPhi = 0;
            _startZoom = _view.value.zoom;
          },
          onScaleUpdate: (d) {
            final v = _view.value;
            final r = _radiusAt1 * v.zoom;
            _set(v.lam - d.focalPointDelta.dx / r, v.phi + d.focalPointDelta.dy / r, _startZoom * d.scale);
          },
          onScaleEnd: (d) {
            _held = false;
            final r = _radiusAt1 * _view.value.zoom;
            _vLam = -d.velocity.pixelsPerSecond.dx / r;
            _vPhi = d.velocity.pixelsPerSecond.dy / r;
            _wake();
          },
          child: paint,
        );
      },
    );
  }
}

class _GlobePainter extends CustomPainter {
  _GlobePainter(this.view, this.palette, this.fill, this.showAll, this.marks) : super(repaint: view);

  final ValueNotifier<_View> view;
  final GlobePalette palette;
  final Color? Function(Country c)? fill;
  final bool showAll;
  final List<MapMark> marks;

  /// Projected ring, reused between rings: x, y, and whether the point faces the viewer.
  static var _xy = Float32List(0);
  static var _front = Uint8List(0);

  @override
  void paint(Canvas canvas, Size size) {
    final v = view.value;
    final center = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 * 0.92 * v.zoom;
    final sinP0 = math.sin(v.phi), cosP0 = math.cos(v.phi);
    // Fewer points when the globe is small on screen.
    final step = r < 160 ? 4 : (r < 420 ? 2 : 1);

    final sphere = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.1,
          colors: [palette.seaCenter, palette.seaRim],
        ).createShader(sphere),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(sphere));

    _graticule(canvas, center, r, v, sinP0, cosP0);

    final fillPaint = Paint();
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = v.zoom > 3 ? 1.0 : 0.7
      ..strokeJoin = StrokeJoin.round
      ..color = palette.border;
    final world = World.instance;
    for (final c in world.units) {
      final color = fill?.call(c) ?? (showAll ? (c.quiz ? palette.land : palette.land.withValues(alpha: 0.6)) : null);
      if (color == null) continue;
      // Skip countries entirely on the far side.
      final dc = sinP0 * math.sin(c.lat * _rad) + cosP0 * math.cos(c.lat * _rad) * math.cos(c.lon * _rad - v.lam);
      if (math.acos(dc.clamp(-1.0, 1.0)) - _angularRadius(c) > math.pi / 2) continue;
      final area = Path()..fillType = PathFillType.evenOdd;
      final lines = Path();
      for (final (lam, sp, cp) in _rings.putIfAbsent(c.id, () => _Rings(c)).rings) {
        final n = lam.length;
        if (_xy.length < n * 2) {
          _xy = Float32List(n * 2);
          _front = Uint8List(n);
        }
        var m = 0, anyFront = false;
        for (var i = 0; i < n; i += (i + step < n ? step : (i == n - 1 ? 1 : n - 1 - i))) {
          final dl = lam[i] - v.lam;
          final cdl = math.cos(dl);
          var x = cp[i] * math.sin(dl), y = cosP0 * sp[i] - sinP0 * cp[i] * cdl;
          final front = sinP0 * sp[i] + cosP0 * cp[i] * cdl >= 0;
          if (!front) {
            // Behind: pushed onto the rim, so the visible part of the shape stays closed.
            final l = math.sqrt(x * x + y * y);
            if (l > 0) (x, y) = (x / l, y / l);
          }
          anyFront |= front;
          _xy[2 * m] = center.dx + r * x;
          _xy[2 * m + 1] = center.dy - r * y;
          _front[m] = front ? 1 : 0;
          m++;
        }
        if (!anyFront || m < 3) continue;
        area.moveTo(_xy[0], _xy[1]);
        for (var k = 1; k < m; k++) {
          area.lineTo(_xy[2 * k], _xy[2 * k + 1]);
        }
        area.close();
        // Borders only between points facing us, or they would run along the rim.
        var pen = false;
        for (var k = 0; k <= m; k++) {
          final i = k % m;
          if (_front[i] == 0) {
            pen = false;
            continue;
          }
          pen ? lines.lineTo(_xy[2 * i], _xy[2 * i + 1]) : lines.moveTo(_xy[2 * i], _xy[2 * i + 1]);
          pen = true;
        }
      }
      canvas.drawPath(area, fillPaint..color = color);
      canvas.drawPath(lines, border);
      // Tiny countries: a dot, so they can be seen and tapped.
      if (c.tiny && c.quiz) {
        final dl = c.lon * _rad - v.lam;
        final sp = math.sin(c.lat * _rad), cp = math.cos(c.lat * _rad);
        if (sinP0 * sp + cosP0 * cp * math.cos(dl) > 0.05) {
          final p = Offset(center.dx + r * cp * math.sin(dl), center.dy - r * (cosP0 * sp - sinP0 * cp * math.cos(dl)));
          canvas.drawCircle(p, 3.6, fillPaint..color = color);
          canvas.drawCircle(p, 3.6, border);
        }
      }
    }
    _marks(canvas, center, r, sinP0, cosP0, v);
    canvas.restore();
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = palette.border.withValues(alpha: 0.7),
    );
  }

  /// Pins, and lines drawn as great-circle arcs (the shortest way on a sphere), on the visible side only.
  void _marks(Canvas canvas, Offset center, double r, double sinP0, double cosP0, _View v) {
    Offset? at(double lon, double lat) {
      final dl = lon * _rad - v.lam, sp = math.sin(lat * _rad), cp = math.cos(lat * _rad);
      final cdl = math.cos(dl);
      if (sinP0 * sp + cosP0 * cp * cdl < 0) return null;
      return Offset(center.dx + r * cp * math.sin(dl), center.dy - r * (cosP0 * sp - sinP0 * cp * cdl));
    }

    for (final m in marks) {
      if (m.toLon == null) {
        final p = at(m.lon, m.lat);
        if (p == null) continue;
        canvas.drawCircle(
          p.translate(0, 1),
          10,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.22)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
        canvas.drawCircle(p, 10, Paint()..color = Colors.white);
        canvas.drawCircle(p, 6.5, Paint()..color = m.color);
        continue;
      }
      Float64List unit(double lon, double lat) => Float64List.fromList([
        math.cos(lat * _rad) * math.cos(lon * _rad),
        math.cos(lat * _rad) * math.sin(lon * _rad),
        math.sin(lat * _rad),
      ]);
      final a = unit(m.lon, m.lat), b = unit(m.toLon!, m.toLat!);
      final w = math.acos((a[0] * b[0] + a[1] * b[1] + a[2] * b[2]).clamp(-1.0, 1.0));
      final path = Path();
      var drawing = false;
      for (var k = 0; k <= 64; k++) {
        final t = k / 64;
        final (ka, kb) = w < 1e-6 ? (1 - t, t) : (math.sin((1 - t) * w) / math.sin(w), math.sin(t * w) / math.sin(w));
        final (x, y, z) = (ka * a[0] + kb * b[0], ka * a[1] + kb * b[1], ka * a[2] + kb * b[2]);
        final p = at(math.atan2(y, x) / _rad, math.atan2(z, math.sqrt(x * x + y * y)) / _rad);
        if (p == null) {
          drawing = false;
          continue;
        }
        drawing ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
        drawing = true;
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = m.color.withValues(alpha: 0.75),
      );
    }
  }

  void _graticule(Canvas canvas, Offset center, double r, _View v, double sinP0, double cosP0) {
    final path = Path();
    void line(Iterable<(double, double)> points) {
      var drawing = false;
      for (final (lon, lat) in points) {
        final dl = lon * _rad - v.lam, sp = math.sin(lat * _rad), cp = math.cos(lat * _rad);
        final cdl = math.cos(dl);
        if (sinP0 * sp + cosP0 * cp * cdl < 0) {
          drawing = false;
          continue;
        }
        final p = Offset(center.dx + r * cp * math.sin(dl), center.dy - r * (cosP0 * sp - sinP0 * cp * cdl));
        drawing ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
        drawing = true;
      }
    }

    for (var lon = -180; lon < 180; lon += 30) {
      line([for (var lat = -80; lat <= 80; lat += 4) (lon.toDouble(), lat.toDouble())]);
    }
    for (var lat = -60; lat <= 60; lat += 30) {
      line([for (var lon = -180; lon <= 180; lon += 4) (lon.toDouble(), lat.toDouble())]);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = palette.grid,
    );
  }

  @override
  bool shouldRepaint(_GlobePainter old) =>
      old.palette != palette || old.fill != fill || old.showAll != showAll || old.view != view || old.marks != marks;
}
