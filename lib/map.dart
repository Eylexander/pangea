import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'world.dart';

/// A calm two-tone map: neutral land on a soft ocean, hairline borders. Color is kept for what means something
/// (the answer, a pin, the countries found).
class MapPalette {
  const MapPalette._(this.ocean, this.land, this.border, this.territory, this.ink);

  final Color ocean, land, border, territory, ink;

  static const light = MapPalette._(
    Color(0xFFDCE6F2),
    Color(0xFFFFFFFF),
    Color(0xFFBCC7D6),
    Color(0xFFEEF1F6),
    Color(0xFF1A1D29),
  );
  static const dark = MapPalette._(
    Color(0xFF0B0F19),
    Color(0xFF1E2333),
    Color(0xFF363F57),
    Color(0xFF151A27),
    Color(0xFFE9ECF5),
  );

  static MapPalette of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// One color per continent, for the countries found in the Atlas.
Color regionColor(Region? r) => switch (r) {
  Region.africa => const Color(0xFFF29D0C),
  Region.americas => const Color(0xFFFF5B4A),
  Region.asia => const Color(0xFF0FA97A),
  Region.europe => const Color(0xFF2F7BFF),
  Region.oceania => const Color(0xFF7B5CFF),
  null => const Color(0xFF8A8FA3),
};

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

class WorldMap extends StatefulWidget {
  const WorldMap({
    super.key,
    this.fill,
    this.onTap,
    this.marks = const [],
    this.pulse,
    this.pulseColor,
    this.view,
    this.padding = EdgeInsets.zero,
  });

  /// Color of each map unit; null uses the plain land color.
  final Color? Function(Country c)? fill;

  /// Tap position, and the country under it (with some slack for dots of tiny countries).
  final void Function(double lon, double lat, Country? hit)? onTap;
  final List<MapMark> marks;

  /// A country to circle with a pulsing ring (so Malta shows up on a world map).
  final Country? pulse;
  final Color? pulseColor;

  /// First view (lon/lat box); the whole world when null.
  final Rect? view;

  /// Parts of the widget covered by overlays, kept out of [focus].
  final EdgeInsets padding;

  @override
  State<WorldMap> createState() => WorldMapState();
}

class WorldMapState extends State<WorldMap> with TickerProviderStateMixin {
  final _transform = TransformationController();
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
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
    final palette = MapPalette.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final first = _frame == null;
        _frame = _Frame(box.biggest);
        if (first && widget.view != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => focus(widget.view!, animate: false));
        }
        return ColoredBox(
          color: palette.ocean,
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
                  palette: palette,
                  fill: widget.fill,
                  marks: widget.marks,
                  pulseCountry: widget.pulse,
                  pulseColor: widget.pulseColor ?? palette.ink,
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
    required this.palette,
    required this.fill,
    required this.marks,
    required this.pulseCountry,
    required this.pulseColor,
  }) : super(repaint: Listenable.merge([transform, pulse]));

  final _Frame frame;
  final TransformationController transform;
  final Animation<double> pulse;
  final MapPalette palette;
  final Color? Function(Country c)? fill;
  final List<MapMark> marks;
  final Country? pulseCountry;
  final Color pulseColor;

  Color _colorOf(Country c) => fill?.call(c) ?? (c.quiz ? palette.land : palette.territory);

  @override
  void paint(Canvas canvas, Size size) {
    final zoom = transform.value.getMaxScaleOnAxis();
    // One screen pixel, in projected units.
    final px = 1 / (frame.k * zoom);
    canvas.save();
    canvas.translate(frame.o.dx, frame.o.dy);
    canvas.scale(frame.k);
    canvas.translate(-EqualEarth.world.left, -EqualEarth.world.top);

    // Hairline borders, a touch heavier when zoomed in.
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (zoom < 3 ? 0.6 : 0.9) * px
      ..strokeJoin = StrokeJoin.round
      ..color = palette.border;
    final paint = Paint();
    final world = World.instance;
    for (final c in world.units) {
      paint.color = _colorOf(c);
      final path = countryPath(c);
      canvas.drawPath(path, paint);
      canvas.drawPath(path, border);
    }
    // Tiny countries get a dot that stays the same size on screen.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = px
      ..color = palette.border;
    for (final c in world.countries.where((c) => c.tiny)) {
      final p = EqualEarth.project(c.lon, c.lat);
      canvas.drawCircle(p, 3.4 * px, paint..color = _colorOf(c));
      canvas.drawCircle(p, 3.4 * px, ring);
    }

    final target = pulseCountry;
    if (target != null) {
      final p = EqualEarth.project(target.lon, target.lat);
      final t = Curves.easeOut.transform(pulse.value);
      canvas.drawCircle(
        p,
        (8 + 30 * t) * px,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * px
          ..color = pulseColor.withValues(alpha: (1 - t) * 0.9),
      );
    }

    for (final m in marks) {
      final a = EqualEarth.project(m.lon, m.lat);
      if (m.toLon != null) {
        _dashed(canvas, a, EqualEarth.project(m.toLon!, m.toLat!), px, m.color);
      } else {
        _pin(canvas, a, px, m.color);
      }
    }
    canvas.restore();
  }

  void _dashed(Canvas canvas, Offset a, Offset b, double px, Color color) {
    final paint = Paint()
      ..strokeWidth = 2 * px
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.75);
    final len = (b - a).distance, dash = 6 * px;
    if (len == 0) return;
    final dir = (b - a) / len;
    for (var d = 0.0; d < len; d += dash * 2) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, len), paint);
    }
  }

  /// A dot marker: white ring, colored core, a tight shadow to lift it off the map.
  void _pin(Canvas canvas, Offset p, double px, Color color) {
    canvas.drawCircle(
      p.translate(0, px),
      10 * px,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 * px),
    );
    canvas.drawCircle(p, 10 * px, Paint()..color = Colors.white);
    canvas.drawCircle(p, 6.5 * px, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.fill != fill ||
      old.marks != marks ||
      old.palette != palette ||
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

/// A country's silhouette, flat.
class ShapeView extends StatelessWidget {
  const ShapeView(this.country, {super.key, required this.color});

  final Country country;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ShapePainter(country, color), child: const SizedBox.expand());
}

class _ShapePainter extends CustomPainter {
  _ShapePainter(this.country, this.color);

  final Country country;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final src = shapePath(country);
    final b = src.getBounds();
    if (b.width == 0 && b.height == 0) return;
    final s = math.min(size.width / math.max(b.width, 1e-6), size.height / math.max(b.height, 1e-6)) * 0.9;
    final m = Matrix4.identity()
      ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
      ..scaleByDouble(s, s, 1, 1)
      ..translateByDouble(-b.center.dx, -b.center.dy, 0, 1);
    canvas.drawPath(src.transform(m.storage), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ShapePainter old) => old.country != country || old.color != color;
}
