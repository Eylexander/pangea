import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pangea/guess.dart';
import 'package:pangea/route.dart';
import 'package:pangea/store.dart';
import 'package:pangea/world.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(World.load);
  Country c(String id) => World.instance.byId[id]!;

  test('197 countries with a flag, a capital and a region', () {
    final w = World.instance;
    expect(w.countries, hasLength(197));
    for (final c in w.countries) {
      expect(c.iso, matches(RegExp(r'^[A-Z]{2}$')), reason: c.id);
      expect(c.capitalEn, isNotEmpty, reason: c.id);
      expect(c.region, isNotNull, reason: c.id);
      expect(c.mainCount, greaterThan(0), reason: c.id);
    }
  });

  test('projection round-trips', () {
    for (final (lon, lat) in [(0.0, 0.0), (2.35, 48.85), (-122.4, 37.8), (151.2, -33.9), (179.0, 70.0)]) {
      final (lon2, lat2) = EqualEarth.unproject(EqualEarth.project(lon, lat));
      expect(lon2, closeTo(lon, 1e-6));
      expect(lat2, closeTo(lat, 1e-6));
    }
  });

  test('points fall in the right country, holes included', () {
    expect(c('FRA').contains(2.35, 48.85), isTrue); // Paris
    expect(c('ITA').contains(12.45, 41.9), isTrue); // Rome
    expect(c('LSO').contains(28.2, -29.5), isTrue);
    expect(c('ZAF').contains(28.2, -29.5), isFalse); // Lesotho is a hole in South Africa
    expect(c('RUS').contains(-175, 66), isTrue); // Chukotka, past the antimeridian
    expect(c('FRA').contains(-53, 4), isTrue); // French Guiana
    expect(c('BRA').contains(2.35, 48.85), isFalse);
  });

  test('distance to a border', () {
    expect(c('FRA').distanceKm(2.35, 48.85), 0);
    // Brussels is about 75 km from the French border.
    expect(c('FRA').distanceKm(4.35, 50.85), inInclusiveRange(40, 110));
    expect(haversineKm(48.85, 2.35, 51.5, -0.12), closeTo(344, 5));
    expect(bearing(48.85, 2.35, 51.5, -0.12), inInclusiveRange(320, 340)); // London is north-west of Paris
  });

  test('search matches both languages, aliases and missing accents', () {
    expect(World.instance.search('allemagne').first.id, 'DEU');
    expect(World.instance.search('germ').first.id, 'DEU');
    expect(World.instance.search('cote d ivoire').first.id, 'CIV');
    expect(World.instance.search('etats').first.id, 'USA');
    expect(World.instance.search('UK').first.id, 'GBR');
    expect(World.instance.search(''), isEmpty);
  });

  test('warmth and the shared text', () {
    expect(warmth(c('FRA'), c('FRA')), 100);
    expect(warmth(c('BEL'), c('FRA')), greaterThan(95));
    expect(warmth(c('NZL'), c('ESP')), lessThan(5));
    final text = shareText(3, [c('BEL'), c('FRA')], c('FRA'));
    expect(text.split('\n'), ['Pangea #3 🔮 2/6', '🟩🟩🟩🟩🟨 ⬇️', '🟩🟩🟩🟩🟩 🎉']);
  });

  test('daily days and countries', () {
    expect(Store.today(DateTime(2026, 1, 1, 23)), 1);
    expect(Store.today(DateTime(2026, 10, 25)), 298);
    expect(Store.dailyCountry(5), Store.dailyCountry(5));
    expect(Store.dailyCountry(5).hasShape, isTrue);
  });

  test('land borders, enclaves and pass-through territories', () {
    expect(c('FRA').neighborIds, containsAll(['ESP', 'BEL', 'BRA'])); // Brazil through French Guiana
    expect(c('LSO').neighborIds, ['ZAF']); // an enclave, a hole in South Africa
    expect(c('MAR').neighborIds, contains('MRT')); // through Western Sahara
    expect(c('JPN').neighborIds, isEmpty);
  });

  test('road trips', () {
    final trip = Trip(c('FRA'), c('POL'));
    expect(trip.steps, 2);
    expect(trip.shortest(), [c('FRA'), c('DEU'), c('POL')]);
    expect(trip.linked([c('DEU')]), isTrue);
    expect(trip.linked([c('BEL')]), isFalse);
    expect(trip.detour(c('DEU')), 0);
    expect(trip.detour(c('BEL')), 1);
    expect(trip.detour(c('JPN')), isNull);
  });

  test('difficulty pools', () {
    final w = World.instance;
    expect(w.pool(null, Difficulty.easy), hasLength(70));
    expect(w.pool(null, Difficulty.normal), hasLength(145));
    expect(w.pool(null, Difficulty.hard), hasLength(197));
    expect(w.pool(Region.oceania, Difficulty.easy).length, greaterThanOrEqualTo(8));
    expect(c('USA').level, 1);
    expect(c('TUV').level, 3);
  });

  test('button text contrasts with light and dark colors', () {
    expect(ThemeData.estimateBrightnessForColor(const Color(0xFFF2F1F7)), Brightness.light); // ink in dark mode
    expect(ThemeData.estimateBrightnessForColor(const Color(0xFF2F7BFF)), Brightness.dark);
  });
}
