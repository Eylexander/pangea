import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'world.dart';

/// Everything the game remembers, in SharedPreferences.
class Store extends ChangeNotifier {
  Store(this._p) : _misses = Map<String, int>.from(jsonDecode(_p.getString('misses') ?? '{}'));

  static late Store instance;
  static Future<void> load() async {
    instance = Store(await SharedPreferences.getInstance());
    language = instance.languageSetting;
  }

  final SharedPreferences _p;
  final Map<String, int> _misses;

  Region? get region => Region.byKey(_p.getString('region'));
  set region(Region? r) {
    r == null ? _p.remove('region') : _p.setString('region', r.key);
    notifyListeners();
  }

  // Settings.

  Difficulty get difficulty => Difficulty.values.asNameMap()[_p.getString('difficulty')] ?? Difficulty.normal;
  set difficulty(Difficulty d) {
    _p.setString('difficulty', d.name);
    notifyListeners();
  }

  /// 'system', 'light' or 'dark'.
  String get theme => _p.getString('theme') ?? 'system';
  set theme(String t) {
    _p.setString('theme', t);
    notifyListeners();
  }

  /// 'en', 'fr', or null to follow the phone.
  String? get languageSetting => _p.getString('language');
  set languageSetting(String? l) {
    l == null ? _p.remove('language') : _p.setString('language', l);
    language = l;
    notifyListeners();
  }

  // Records, per game, region and difficulty. Hard plays every country, like v1.0 and v1.1 did: their records keep
  // the old key.
  String _bestKey(String mode, Region? r, Difficulty d) =>
      'best.$mode.${r?.key ?? 'World'}${d == Difficulty.hard ? '' : '.${d.name}'}';

  int best(String mode, Region? r, [Difficulty? d]) => _p.getInt(_bestKey(mode, r, d ?? difficulty)) ?? 0;

  /// Saves a score; true when it beats the record.
  bool submit(String mode, Region? r, Difficulty d, int score) {
    if (score <= best(mode, r, d)) return false;
    _p.setInt(_bestKey(mode, r, d), score);
    notifyListeners();
    return true;
  }

  /// Road trips finished, and finished with the fewest countries possible.
  int get tripsDone => _p.getInt('trips.done') ?? 0;
  int get tripsPerfect => _p.getInt('trips.perfect') ?? 0;
  void tripDone({required bool perfect}) {
    _p.setInt('trips.done', tripsDone + 1);
    if (perfect) _p.setInt('trips.perfect', tripsPerfect + 1);
    notifyListeners();
  }

  /// Forgets scores, found countries, misses and the daily history; keeps the settings.
  Future<void> resetProgress() async {
    for (final k in _p.getKeys().toList()) {
      if (!const {'difficulty', 'theme', 'language', 'region'}.contains(k)) await _p.remove(k);
    }
    _misses.clear();
    notifyListeners();
  }

  /// Countries answered right at least once, in any game.
  Set<String> get known => (_p.getStringList('known') ?? const []).toSet();

  /// Remembers an answer: misses make a country come back more often in that game, until answered right.
  void record(String mode, Country c, bool right) {
    final key = '$mode.${c.id}';
    final n = (_misses[key] ?? 0) + (right ? -1 : 1);
    n <= 0 ? _misses.remove(key) : _misses[key] = math.min(n, 5);
    _p.setString('misses', jsonEncode(_misses));
    if (right && !known.contains(c.id)) {
      _p.setStringList('known', [...known, c.id]);
      notifyListeners();
    }
  }

  /// Picks a country, favoring the ones often missed in [mode] (and on Hard, the obscure ones), skipping [recent].
  Country pick(String mode, List<Country> pool, math.Random rnd, {Iterable<String> recent = const []}) {
    final skip = recent.toSet();
    final options = pool.where((c) => !skip.contains(c.id)).toList();
    final from = options.isEmpty ? pool : options;
    final hard = difficulty == Difficulty.hard;
    final weights = [for (final c in from) (hard && c.level == 3 ? 2 : 1) + 3 * (_misses['$mode.${c.id}'] ?? 0)];
    var x = rnd.nextInt(weights.reduce((a, b) => a + b));
    for (var i = 0; i < from.length; i++) {
      x -= weights[i];
      if (x < 0) return from[i];
    }
    return from.last;
  }

  // Daily mystery country.

  /// Day 1 is 2026-01-01, in the phone's time zone.
  static int today([DateTime? now]) {
    final d = now ?? DateTime.now();
    return DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(2026)).inDays + 1;
  }

  /// The same country for everyone on a given day; the order is shuffled once so neighbors don't follow.
  static Country dailyCountry(int day) {
    final pool = World.instance.countries.where((c) => c.hasShape).toList()..shuffle(math.Random(2026));
    return pool[(day - 1) % pool.length];
  }

  /// Today's guesses so far (country ids).
  List<String> dailyGuesses(int day) {
    final j = jsonDecode(_p.getString('daily') ?? '{}') as Map;
    return j['day'] == day ? List<String>.from(j['guesses']) : [];
  }

  void saveDailyGuesses(int day, List<String> guesses, {bool? won}) {
    _p.setString('daily', jsonEncode({'day': day, 'guesses': guesses}));
    if (won != null) {
      _p.setInt('daily.played', dailyPlayed + 1);
      if (won) {
        _p.setInt('daily.won', dailyWon + 1);
        final streak = (_p.getInt('daily.lastWin') == day - 1 ? _p.getInt('daily.streak') ?? 0 : 0) + 1;
        _p.setInt('daily.streak', streak);
        _p.setInt('daily.lastWin', day);
        if (streak > bestStreak) _p.setInt('daily.bestStreak', streak);
      } else {
        _p.setInt('daily.streak', 0);
      }
    }
    notifyListeners();
  }

  int get dailyPlayed => _p.getInt('daily.played') ?? 0;
  int get dailyWon => _p.getInt('daily.won') ?? 0;
  int get bestStreak => _p.getInt('daily.bestStreak') ?? 0;

  /// Days in a row won, still alive if yesterday was won and today isn't played yet.
  int get streak => (_p.getInt('daily.lastWin') ?? -9) >= today() - 1 ? _p.getInt('daily.streak') ?? 0 : 0;
}
