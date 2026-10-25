import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'world.dart';

/// Land colors by Natural Earth's MAPCOLOR7 (neighbors never share one).
const _landLight = [
  Color(0xFFFFB4A2), Color(0xFFFFD166), Color(0xFF9BE7C4), Color(0xFFA0C4FF), //
  Color(0xFFCDB4FF), Color(0xFFFFC8DD), Color(0xFFB5E48C),
];
const _landDark = [
  Color(0xFFE76F51), Color(0xFFE9C46A), Color(0xFF2A9D8F), Color(0xFF4D7CFE), //
  Color(0xFF9D4EDD), Color(0xFFEF476F), Color(0xFF76C893),
];

Color landColor(Country c, Brightness b) => (b == Brightness.dark ? _landDark : _landLight)[(c.color - 1) % 7];
Color oceanColor(Brightness b) => b == Brightness.dark ? const Color(0xFF0E1B4D) : const Color(0xFFB9E3FF);

/// A pin or a line drawn over the map (lon/lat).
class MapMark {
  const MapMark.pin(this.lon, this.lat, this.color) : toLon = null, toLat = null;
  const MapMark.line(this.lon, this.lat, double this.toLon, double this.toLat, this.color);
  final double lon, lat;
  final double? toLon, toLat;
  final Color color;
}

/// Maps projected coordinates (EqualEarth) onto the widget, letterboxed.
class _Frame {
  _Frame(this.size) : k = math.min(size.width / EqualEarth.world.width, size.height / EqualEarth.world.height) {
    o = Offset(size.width - EqualEarth.world.width * k, size.height - EqualEarth.world.height * k) / 2;
  }
  final Size size;
  final double k;
  late final Offset o;

  Offset toLocal(Offset projected) => o + (projected - EqualEarth.world.topLeft) * k;
  Offset fromLocal(Offset local) => (local - o) / k + EqualEarth.world.topLeft;
  Rect rectToLocal(Rect projected) => Rect.fromPoints(toLocal(projected.topLeft), toLocal(projected.bottomRight));
}

final _paths = <String, Path>{};

/// The country's outline in projected coordinates, built once.
Path countryPath(Country c) => _paths.putIfAbsent(c.id, () {
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final poly in c.polygons) {
    for (final r in poly) {
      for (var i = 0; i < r.length; i += 2) {
        final p = EqualEarth.project(r[i], r[i + 1]);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
    }
  }
  return path;
});

final Path _graticule = () {
  final path = Path();
  for (var lat = -30; lat <= 60; lat += 30) {
    for (var lon = -180; lon <= 180; lon += 5) {
      final p = EqualEarth.project(lon.toDouble(), lat.toDouble());
      lon == -180 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
  }
  for (var lon = -150; lon <= 150; lon += 30) {
    for (var lat = -58; lat <= 84; lat += 2) {
      final p = EqualEarth.project(lon.toDouble(), lat.toDouble());
      lat == -58 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
  }
  return path;
}();

class WorldMap extends StatefulWidget {
  const WorldMap({
    super.key,
    this.fill,
    this.onTap,
    this.marks = const [],
    this.pulse,
    this.view,
    this.padding = EdgeInsets.zero,
  });

  /// Color of each map unit; null uses the land palette.
  final Color Function(Country c)? fill;

  /// Tap position, and the country under it (with some slack for dots of tiny countries).
  final void Function(double lon, double lat, Country? hit)? onTap;
  final List<MapMark> marks;

  /// A country to circle with a pulsing ring (so Malta shows up on a world map).
  final Country? pulse;

  /// First view (lon/lat box); the whole world when null.
  final Rect? view;

  /// Parts of the widget covered by overlays, kept out of [focus].
  final EdgeInsets padding;

  @override
  State<WorldMap> createState() => WorldMapState();
}

class WorldMapState extends State<WorldMap> with TickerProviderStateMixin {
  final _transform = TransformationController();
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  Animation<Matrix4>? _moveTween;
  _Frame? _frame;

  @override
  void initState() {
    super.initState();
    _move.addListener(() => _transform.value = _moveTween!.value);
    _syncPulse();
  }

  @override
  void didUpdateWidget(WorldMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() => widget.pulse == null ? _pulse.stop() : _pulse.repeat();

  @override
  void dispose() {
    _transform.dispose();
    _pulse.dispose();
    _move.dispose();
    super.dispose();
  }

  /// Zooms onto a lon/lat box.
  void focus(Rect lonLat, {bool animate = true}) {
    final frame = _frame;
    if (frame == null) return;
    final size = frame.size, pad = widget.padding;
    final area = pad.deflateRect(Offset.zero & size);
    final r = frame.rectToLocal(EqualEarth.rect(lonLat));
    final s = math.min(area.width / math.max(r.width, 1), area.height / math.max(r.height, 1)).clamp(1.0, 60.0);
    var tx = area.center.dx - s * r.center.dx, ty = area.center.dy - s * r.center.dy;
    tx = tx.clamp(size.width - s * size.width - pad.right, pad.left);
    ty = ty.clamp(size.height - s * size.height - pad.bottom, pad.top);
    final target = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
    if (!animate) {
      _transform.value = target;
      return;
    }
    _moveTween = Matrix4Tween(
      begin: _transform.value.clone(),
      end: target,
    ).animate(CurvedAnimation(parent: _move, curve: Curves.easeInOutCubic));
    _move.forward(from: 0);
  }

  Country? _hit(double lon, double lat, Offset local) {
    final world = World.instance;
    for (final c in world.countries) {
      if (c.contains(lon, lat)) return c;
    }
    // Nothing under the finger: the nearest dot of a tiny country within reach.
    final zoom = _transform.value.getMaxScaleOnAxis();
    Country? best;
    var bestD = 26.0;
    for (final c in world.countries.where((c) => c.tiny)) {
      final d = (_frame!.toLocal(EqualEarth.project(c.lon, c.lat)) - local).distance * zoom;
      if (d < bestD) (best, bestD) = (c, d);
    }
    if (best != null) return best;
    for (final c in world.units) {
      if (!c.quiz && c.contains(lon, lat)) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return LayoutBuilder(
      builder: (context, box) {
        final first = _frame == null;
        _frame = _Frame(box.biggest);
        if (first && widget.view != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => focus(widget.view!, animate: false));
        }
        return ColoredBox(
          color: oceanColor(brightness),
          child: InteractiveViewer(
            transformationController: _transform,
            maxScale: 60,
            boundaryMargin: const EdgeInsets.all(120),
            child: GestureDetector(
              onTapUp: widget.onTap == null
                  ? null
                  : (d) {
                      final (lon, lat) = EqualEarth.unproject(_frame!.fromLocal(d.localPosition));
                      widget.onTap!(lon, lat, _hit(lon, lat, d.localPosition));
                    },
              child: CustomPaint(
                size: box.biggest,
                painter: _MapPainter(
                  frame: _frame!,
                  transform: _transform,
                  pulse: _pulse,
                  brightness: brightness,
                  fill: widget.fill,
                  marks: widget.marks,
                  pulseCountry: widget.pulse,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.frame,
    required this.transform,
    required this.pulse,
    required this.brightness,
    required this.fill,
    required this.marks,
    required this.pulseCountry,
  }) : super(repaint: Listenable.merge([transform, pulse]));

  final _Frame frame;
  final TransformationController transform;
  final Animation<double> pulse;
  final Brightness brightness;
  final Color Function(Country c)? fill;
  final List<MapMark> marks;
  final Country? pulseCountry;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = brightness == Brightness.dark;
    final zoom = transform.value.getMaxScaleOnAxis();
    // One screen pixel, in projected units.
    final px = 1 / (frame.k * zoom);
    canvas.save();
    canvas.translate(frame.o.dx, frame.o.dy);
    canvas.scale(frame.k);
    canvas.translate(-EqualEarth.world.left, -EqualEarth.world.top);

    canvas.drawPath(
      _graticule,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = px
        ..color = (dark ? Colors.white : const Color(0xFF1F4E8C)).withValues(alpha: 0.12),
    );
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.7, math.min(1.4, zoom / 3)) * px
      ..strokeJoin = StrokeJoin.round
      ..color = dark ? const Color(0xFF0B1338) : Colors.white;
    final paint = Paint();
    final world = World.instance;
    for (final c in world.units) {
      paint.color = fill?.call(c) ?? (c.quiz ? landColor(c, brightness) : _territory(dark));
      final path = countryPath(c);
      canvas.drawPath(path, paint);
      canvas.drawPath(path, border);
    }
    // Tiny countries get a dot that stays the same size on screen.
    for (final c in world.countries.where((c) => c.tiny)) {
      final p = EqualEarth.project(c.lon, c.lat);
      final color = fill?.call(c) ?? landColor(c, brightness);
      canvas.drawCircle(p, 4.5 * px, Paint()..color = border.color);
      canvas.drawCircle(p, 3.2 * px, Paint()..color = color);
    }

    final target = pulseCountry;
    if (target != null) {
      final p = EqualEarth.project(target.lon, target.lat);
      final t = pulse.value;
      canvas.drawCircle(
        p,
        (14 + 30 * t) * px,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * px
          ..color = (dark ? Colors.white : const Color(0xFF1A1446)).withValues(alpha: 1 - t),
      );
    }

    for (final m in marks) {
      final a = EqualEarth.project(m.lon, m.lat);
      if (m.toLon != null) {
        final b = EqualEarth.project(m.toLon!, m.toLat!);
        _dashed(canvas, a, b, px, m.color);
      } else {
        _pin(canvas, a, px, m.color);
      }
    }
    canvas.restore();
  }

  static Color _territory(bool dark) => dark ? const Color(0xFF3A3F66) : const Color(0xFFDCD8E8);

  void _dashed(Canvas canvas, Offset a, Offset b, double px, Color color) {
    final paint = Paint()
      ..strokeWidth = 2.5 * px
      ..strokeCap = StrokeCap.round
      ..color = color;
    final len = (b - a).distance, dash = 8 * px;
    if (len == 0) return;
    final dir = (b - a) / len;
    for (var d = 0.0; d < len; d += dash * 2) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, len), paint);
    }
  }

  void _pin(Canvas canvas, Offset p, double px, Color color) {
    final head = p - Offset(0, 22 * px);
    final body = Path()
      ..moveTo(p.dx, p.dy)
      ..lineTo(head.dx - 7 * px, head.dy + 5 * px)
      ..arcToPoint(head.translate(7 * px, 5 * px), radius: Radius.circular(9 * px), largeArc: true)
      ..close();
    canvas.drawPath(body.shift(Offset(px, 1.5 * px)), Paint()..color = Colors.black26);
    canvas.drawPath(body, Paint()..color = color);
    canvas.drawCircle(head, 3.4 * px, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.fill != fill ||
      old.marks != marks ||
      old.brightness != brightness ||
      old.pulseCountry != pulseCountry ||
      old.frame.size != frame.size;
}

final _shapes = <String, Path>{};

/// The country's main land (big parts and the islands next to them) seen from above, in a local plane.
Path shapePath(Country c) => _shapes.putIfAbsent(c.id, () {
  final k = math.cos(c.lat * math.pi / 180);
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final poly in c.polygons.take(c.mainCount)) {
    for (final r in poly) {
      for (var i = 0; i < r.length; i += 2) {
        final x = ((r[i] - c.lon + 540) % 360 - 180) * k, y = -r[i + 1];
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      path.close();
    }
  }
  return path;
});

/// A country's silhouette, filled with a gradient and a soft glow.
class ShapeView extends StatelessWidget {
  const ShapeView(this.country, {super.key, this.colors = const [Colors.white, Colors.white], this.glow = true});

  final Country country;
  final List<Color> colors;
  final bool glow;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ShapePainter(country, colors, glow), child: const SizedBox.expand());
}

class _ShapePainter extends CustomPainter {
  _ShapePainter(this.country, this.colors, this.glow);

  final Country country;
  final List<Color> colors;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final src = shapePath(country);
    final b = src.getBounds();
    if (b.isEmpty && b.width == 0) return;
    final s = math.min(size.width / math.max(b.width, 1e-6), size.height / math.max(b.height, 1e-6)) * 0.88;
    final m = Matrix4.identity()
      ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
      ..scaleByDouble(s, s, 1, 1)
      ..translateByDouble(-b.center.dx, -b.center.dy, 0, 1);
    final path = src.transform(m.storage);
    final rect = path.getBounds();
    if (glow) {
      canvas.drawPath(
        path.shift(const Offset(0, 6)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
    canvas.drawPath(path, Paint()..shader = LinearGradient(colors: colors).createShader(rect));
  }

  @override
  bool shouldRepaint(_ShapePainter old) => old.country != country || old.colors != colors;
}
