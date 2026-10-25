import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart';

/// 'en' or 'fr' when chosen in the settings; null follows the phone (French if it's in French, else English).
String? language;
bool get fr => (language ?? PlatformDispatcher.instance.locale.languageCode) == 'fr';
String tr(String en, String french) => fr ? french : en;

/// Which countries come up. Easy: the 70 best known; Normal: 145; Hard: all 197, the obscure ones more often.
enum Difficulty {
  easy('Easy', 'Facile'),
  normal('Normal', 'Normal'),
  hard('Hard', 'Difficile');

  const Difficulty(this.en, this.french);
  final String en, french;
  String get label => tr(en, french);
  int get level => index + 1;
}

enum Region {
  africa('Africa', 'Africa', 'Afrique', Rect.fromLTRB(-20, -36, 55, 38)),
  americas('Americas', 'Americas', 'Amériques', Rect.fromLTRB(-170, -56, -30, 72)),
  asia('Asia', 'Asia', 'Asie', Rect.fromLTRB(25, -11, 150, 56)),
  europe('Europe', 'Europe', 'Europe', Rect.fromLTRB(-12, 35, 32, 62)),
  oceania('Oceania', 'Oceania', 'Océanie', Rect.fromLTRB(110, -48, 180, 10));

  const Region(this.key, this.en, this.french, this.view);

  /// Natural Earth's REGION_UN value.
  final String key;
  final String en, french;

  /// What the map shows first for this region (lon/lat).
  final Rect view;

  /// The whole world doesn't fit a portrait screen; this shows from the Americas' east to India, pinch out for more.
  static const worldView = Rect.fromLTRB(-75, -40, 105, 72);

  String get label => tr(en, french);
  static Region? byKey(String? key) => values.where((r) => r.key == key).firstOrNull;
}

class Country {
  Country.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      quiz = j['q'] == 1,
      iso = j['iso'],
      en = j['en'],
      french = j['fr'],
      capitalEn = j['capEn'] ?? '',
      capitalFr = j['capFr'] ?? '',
      aliases = List<String>.from(j['alias'] ?? const []),
      region = Region.byKey(j['reg']),
      population = j['pop'],
      area = j['area'],
      lon = (j['lx'] as num).toDouble(),
      lat = (j['ly'] as num).toDouble(),
      level = j['lv'] ?? 3,
      neighborIds = List<String>.from(j['nb'] ?? const []),
      mainCount = j['main'],
      polygons = [
        for (final poly in j['p'] as List) [for (final ring in poly as List) _decode(ring as List)],
      ] {
    var (w, s, e, n) = (180.0, 90.0, -180.0, -90.0);
    for (final (k, poly) in polygons.indexed) {
      final r = poly.first;
      for (var i = 0; i < r.length; i += 2) {
        w = math.min(w, r[i]);
        e = math.max(e, r[i]);
        s = math.min(s, r[i + 1]);
        n = math.max(n, r[i + 1]);
      }
      if (k == mainCount - 1) mainBounds = Rect.fromLTRB(w, s, e, n);
    }
    bounds = Rect.fromLTRB(w, s, e, n);
  }

  /// Where to zoom to show the country: its main land, or around its label point when that spans the
  /// antimeridian (Russia, Fiji).
  Rect get view =>
      mainBounds.width < 90 ? mainBounds : Rect.fromCenter(center: Offset(lon, lat), width: 40, height: 24);

  final String id, iso, en, french, capitalEn, capitalFr;
  final bool quiz;
  final List<String> aliases;
  final Region? region;
  final int population, area, mainCount;

  /// 1 well known, 2 less so, 3 obscure (small island states, microstates). See tool/build_world.py.
  final int level;

  /// Countries across a land border.
  final List<String> neighborIds;
  final double lon, lat;

  /// Polygons, each a list of rings (outer first, then holes) as [lon, lat, lon, lat, ...] in degrees.
  final List<List<Float32List>> polygons;
  late final Rect bounds;
  late final Rect mainBounds;

  String get name => tr(en, french);
  String get otherName => tr(french, en);
  String get capital => tr(capitalEn, capitalFr);
  String get flag => String.fromCharCodes(iso.codeUnits.map((c) => 0x1F1E6 + c - 65));

  /// Too small to tap on a world map: drawn with a dot too.
  bool get tiny => area < 3000;

  /// Silhouettes of specks of land (Tuvalu, Monaco…) are unguessable.
  bool get hasShape => area >= 2000;

  static Float32List _decode(List deltas) {
    final out = Float32List(deltas.length);
    var x = 0, y = 0;
    for (var i = 0; i < deltas.length; i += 2) {
      x += deltas[i] as int;
      y += deltas[i + 1] as int;
      out[i] = x / 1000;
      out[i + 1] = y / 1000;
    }
    return out;
  }

  /// Even-odd test over every ring, so holes (Lesotho in South Africa) are handled.
  bool contains(double lon, double lat) {
    if (!bounds.inflate(0.01).contains(Offset(lon, lat))) return false;
    var inside = false;
    for (final poly in polygons) {
      for (final r in poly) {
        for (var i = 0, j = r.length - 2; i < r.length; j = i, i += 2) {
          final (xi, yi, xj, yj) = (r[i], r[i + 1], r[j], r[j + 1]);
          if ((yi > lat) != (yj > lat) && lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) inside = !inside;
        }
      }
    }
    return inside;
  }

  /// Kilometres from a point to the country's nearest border (0 inside). Measured in a plane tangent at the
  /// point: exact enough nearby, and far away only the order of magnitude matters.
  double distanceKm(double lon, double lat) {
    if (contains(lon, lat)) return 0;
    final k = math.cos(lat * math.pi / 180);
    var best = double.infinity;
    for (final poly in polygons) {
      final r = poly.first;
      for (var i = 0, j = r.length - 2; i < r.length; j = i, i += 2) {
        final ax = _wrap(r[j] - lon) * k, ay = r[j + 1] - lat;
        final bx = _wrap(r[i] - lon) * k, by = r[i + 1] - lat;
        final dx = bx - ax, dy = by - ay;
        final len = dx * dx + dy * dy;
        final t = len == 0 ? 0.0 : ((-ax * dx - ay * dy) / len).clamp(0.0, 1.0);
        final px = ax + t * dx, py = ay + t * dy;
        best = math.min(best, px * px + py * py);
      }
    }
    // A plane is wrong past ~2000 km; the great-circle distance to the label point is the better guess there.
    return math.min(math.sqrt(best) * 111.2, haversineKm(lat, lon, this.lat, this.lon));
  }
}

double _wrap(double dlon) => (dlon + 540) % 360 - 180;

class World {
  World(this.units) : countries = units.where((c) => c.quiz).toList(), byId = {for (final c in units) c.id: c};

  static late World instance;

  /// Every map unit (territories included); [countries] are the 197 that are played.
  final List<Country> units;
  final List<Country> countries;
  final Map<String, Country> byId;

  static Future<void> load() async {
    final json = jsonDecode(await rootBundle.loadString('assets/world.json')) as Map<String, dynamic>;
    instance = World([for (final c in json['countries'] as List) Country.fromJson(c)]);
  }

  List<Country> inRegion(Region? r) => r == null ? countries : countries.where((c) => c.region == r).toList();

  /// The countries a game draws from. Too few for a continent at this level (Oceania on Easy): the next level too.
  List<Country> pool(Region? r, Difficulty d) {
    final all = inRegion(r);
    for (var level = d.level; level <= 3; level++) {
      final p = all.where((c) => c.level <= level).toList();
      if (p.length >= 8 || level == 3) return p;
    }
    return all;
  }

  List<Country> neighbors(Country c) => [for (final id in c.neighborIds) byId[id]!];

  /// Steps from [from] to every country reachable over land.
  Map<Country, int> distances(Country from) {
    final d = {from: 0};
    final queue = [from];
    for (var i = 0; i < queue.length; i++) {
      for (final n in neighbors(queue[i])) {
        if (d.containsKey(n)) continue;
        d[n] = d[queue[i]]! + 1;
        queue.add(n);
      }
    }
    return d;
  }

  /// Countries whose name (either language, or an alias) matches what was typed, best first.
  List<Country> search(String query, {int limit = 6}) {
    final q = normalize(query);
    if (q.isEmpty) return const [];
    int rank(Country c) {
      var best = 99;
      for (final (i, n) in [c.name, c.otherName, ...c.aliases].indexed) {
        final s = normalize(n);
        if (s == q) return 0;
        if (s.startsWith(q)) best = math.min(best, 1 + math.min(i, 2)); // name, then other language, then alias
        if (s.contains(q)) best = math.min(best, 4);
      }
      return best;
    }

    // Ties go to the more populous country: "Ni" is Nigeria before Niue would be.
    final hits = [for (final c in countries) (c, rank(c))].where((h) => h.$2 < 99).toList()
      ..sort((a, b) => a.$2 != b.$2 ? a.$2 - b.$2 : b.$1.population - a.$1.population);
    return [for (final h in hits.take(limit)) h.$1];
  }
}

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a', 'ç': 'c', 'č': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', //
  'ë': 'e', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ú': 'u', 'û': 'u',
  'ü': 'u', 'ù': 'u', 'ș': 's', 'ş': 's', 'ț': 't', 'ý': 'y', 'ÿ': 'y', 'œ': 'oe', 'æ': 'ae',
};

/// Lower case, no accents, letters and digits only: "Côte d'Ivoire" → "cotedivoire".
String normalize(String s) =>
    s.toLowerCase().split('').map((ch) => _accents[ch] ?? ch).join().replaceAll(RegExp(r'[^a-z0-9]'), '');

double _rad(double d) => d * math.pi / 180;

double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  final h =
      math.pow(math.sin(_rad(lat2 - lat1) / 2), 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.pow(math.sin(_rad(lon2 - lon1) / 2), 2);
  return 2 * 6371 * math.asin(math.sqrt(h.toDouble()));
}

/// Initial compass bearing from point 1 to point 2, in degrees (0 = north, 90 = east).
double bearing(double lat1, double lon1, double lat2, double lon2) {
  final dl = _rad(lon2 - lon1);
  final y = math.sin(dl) * math.cos(_rad(lat2));
  final x = math.cos(_rad(lat1)) * math.sin(_rad(lat2)) - math.sin(_rad(lat1)) * math.cos(_rad(lat2)) * math.cos(dl);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Equal Earth projection (Šavrič, Patterson, Jenny 2018). x right, y down (north up), in sphere radii.
abstract final class EqualEarth {
  static const _a1 = 1.340264, _a2 = -0.081106, _a3 = 0.000893, _a4 = 0.003796;
  static final _m = math.sqrt(3) / 2;

  static Offset project(double lon, double lat) {
    final t = math.asin(_m * math.sin(_rad(lat)));
    final t2 = t * t, t6 = t2 * t2 * t2;
    final x =
        2 * math.sqrt(3) * _rad(lon) * math.cos(t) / (3 * (9 * _a4 * t6 * t2 + 7 * _a3 * t6 + 3 * _a2 * t2 + _a1));
    final y = t * (_a1 + _a2 * t2 + t6 * (_a3 + _a4 * t2));
    return Offset(x, -y);
  }

  /// Inverse of [project]: (lon, lat) in degrees.
  static (double, double) unproject(Offset p) {
    final y = -p.dy;
    var t = y;
    for (var i = 0; i < 12; i++) {
      final t2 = t * t, t6 = t2 * t2 * t2;
      final f = t * (_a1 + _a2 * t2 + t6 * (_a3 + _a4 * t2)) - y;
      final df = _a1 + 3 * _a2 * t2 + t6 * (7 * _a3 + 9 * _a4 * t2);
      t -= f / df;
      if (f.abs() < 1e-9) break;
    }
    final t2 = t * t, t6 = t2 * t2 * t2;
    final lon = p.dx * 3 * (9 * _a4 * t6 * t2 + 7 * _a3 * t6 + 3 * _a2 * t2 + _a1) / (2 * math.sqrt(3) * math.cos(t));
    final lat = math.asin((math.sin(t) / _m).clamp(-1.0, 1.0));
    return (lon * 180 / math.pi, lat * 180 / math.pi);
  }

  /// The part of the world that is drawn (Antarctica left out).
  static final Rect world = Rect.fromLTRB(
    project(-180, 0).dx,
    project(0, 84).dy,
    project(180, 0).dx,
    project(0, -58).dy,
  );

  /// Projected bounds of a lon/lat box (left/right = longitudes, top/bottom = south/north latitudes).
  static Rect rect(Rect box) {
    final lonLat = Rect.fromLTRB(
      box.left.clamp(-180, 180),
      box.top.clamp(-85, 85),
      box.right.clamp(-180, 180),
      box.bottom.clamp(-85, 85),
    );
    final equator = 0.0.clamp(lonLat.top, lonLat.bottom); // the projection is widest there
    final points = [
      for (final lon in [lonLat.left, lonLat.right])
        for (final lat in [lonLat.top, lonLat.bottom, equator]) project(lon, lat),
    ];
    return points.fold(Rect.fromPoints(points.first, points.first), (r, p) => r.expandToInclude(p & Size.zero));
  }
}
