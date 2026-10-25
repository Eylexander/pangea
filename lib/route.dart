import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'globe.dart';
import 'store.dart';
import 'ui.dart';
import 'world.dart';

const _fromColor = Color(0xFF2F7BFF);
const _toColor = Color(0xFFE5438A);
const _detour = Color(0xFFF29D0C);

/// A trip between two countries, and how good each stop is.
class Trip {
  Trip(this.from, this.to) : dFrom = World.instance.distances(from), dTo = World.instance.distances(to);

  final Country from, to;
  final Map<Country, int> dFrom, dTo;

  /// Borders to cross on the shortest way.
  int get steps => dFrom[to]!;

  /// 0 on a shortest way, 1 for a one-country detour, more (or null when cut off from both) otherwise.
  int? detour(Country c) {
    final a = dFrom[c], b = dTo[c];
    return a == null || b == null ? null : a + b - steps;
  }

  /// Whether [stops] link [from] to [to] by land.
  bool linked(Iterable<Country> stops) {
    final open = {...stops, to};
    final seen = {from};
    final queue = [from];
    for (var i = 0; i < queue.length; i++) {
      for (final n in World.instance.neighbors(queue[i])) {
        if (n == to) return true;
        if (open.contains(n) && seen.add(n)) queue.add(n);
      }
    }
    return false;
  }

  /// One shortest way, endpoints included.
  List<Country> shortest() {
    final path = [to];
    while (path.last != from) {
      path.add(World.instance.neighbors(path.last).firstWhere((n) => dFrom[n] == dFrom[path.last]! - 1));
    }
    return path.reversed.toList();
  }

  /// Two countries [min]–[max] borders apart, both from [pool]; null when the pool has no such pair.
  static Trip? pick(List<Country> pool, int min, int max, math.Random rnd) {
    final starts = pool.where((c) => c.neighborIds.isNotEmpty).toList()..shuffle(rnd);
    for (final a in starts.take(40)) {
      final d = World.instance.distances(a);
      final ends = pool.where((c) => (d[c] ?? 0) >= min && d[c]! <= max).toList();
      if (ends.isNotEmpty) return Trip(a, ends[rnd.nextInt(ends.length)]);
    }
    return null;
  }
}

/// Road trip: get from one country to another by naming the countries in between.
class RoutePage extends StatefulWidget {
  const RoutePage({super.key, required this.region});
  final Region? region;

  @override
  State<RoutePage> createState() => _RoutePageState();
}

class _RoutePageState extends State<RoutePage> {
  final _difficulty = Store.instance.difficulty;
  final _rnd = math.Random();
  final _globe = GlobalKey<GlobeState>();
  late Trip _trip;
  final _stops = <Country>[];
  var _gaveUp = false, _shake = 0;

  /// Spare guesses on top of the shortest way.
  int get _spare => switch (_difficulty) {
    Difficulty.easy => 6,
    Difficulty.normal => 4,
    Difficulty.hard => 3,
  };
  int get _maxGuesses => _trip.steps - 1 + _spare;
  bool get _solved => _trip.linked(_stops);
  bool get _over => _solved || _gaveUp || _stops.length >= _maxGuesses;

  @override
  void initState() {
    super.initState();
    _newTrip();
  }

  void _newTrip() {
    final (min, max) = switch (_difficulty) {
      Difficulty.easy => (2, 3),
      Difficulty.normal => (3, 5),
      Difficulty.hard => (4, 7),
    };
    // A continent without land routes (Oceania) falls back to the whole world.
    _trip =
        Trip.pick(World.instance.pool(widget.region, _difficulty), min, max, _rnd) ??
        Trip.pick(World.instance.pool(null, _difficulty), min, max, _rnd)!;
    _stops.clear();
    _gaveUp = false;
    _reframe();
  }

  /// Turns the globe onto the trip. Far detours only pull it back while they're the latest name,
  /// so one wild guess doesn't leave the whole trip tiny.
  void _reframe() => WidgetsBinding.instance.addPostFrameCallback(
    (_) => _globe.currentState?.frame([
      _trip.from,
      _trip.to,
      ..._stops.where((c) => (_trip.detour(c) ?? 99) <= 1),
      if (_stops.isNotEmpty) _stops.last,
      if (_over && !_solved) ..._trip.shortest(),
    ], minReach: 0.2),
  );

  void _submit(Country c) {
    if (_over) return;
    if (c == _trip.from || c == _trip.to || _stops.contains(c)) {
      setState(() => _shake++);
      return;
    }
    setState(() => _stops.add(c));
    final onWay = _trip.detour(c) == 0;
    if (onWay) Store.instance.record('route', c, true);
    if (_solved) {
      Store.instance.tripDone(perfect: _stops.length == _trip.steps - 1);
      FocusScope.of(context).unfocus();
      HapticFeedback.heavyImpact();
    } else {
      onWay ? HapticFeedback.lightImpact() : HapticFeedback.selectionClick();
      if (_over) FocusScope.of(context).unfocus();
    }
    _reframe();
  }

  Color _colorOf(Country c) => switch (_trip.detour(c)) {
    0 => good,
    1 => _detour,
    _ => bad,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final where = widget.region?.label ?? tr('World', 'Monde');
    final between = _trip.steps - 1;
    final route = _over && !_solved ? _trip.shortest() : const <Country>[];
    final typing = !_over && MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                GameBar(
                  title: Mode.route.title,
                  subtitle: '$where · ${_difficulty.label}',
                  trailing: Pill('${_stops.length}/$_maxGuesses', icon: Icons.signpost_rounded),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Shake(
                    trigger: _shake,
                    child: Row(
                      children: [
                        Expanded(child: _End(_trip.from, _fromColor, tr('From', 'De'))),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward_rounded, color: cs.onSurfaceVariant),
                        ),
                        Expanded(child: _End(_trip.to, _toColor, tr('To', 'À'))),
                      ],
                    ),
                  ),
                ),
                if (!typing)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text(
                      tr(
                        'Name the countries in between, by land. The shortest way crosses $between.',
                        'Nomme les pays entre les deux, par la terre. Le plus court en traverse $between.',
                      ),
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                // Only the trip's countries are on the globe: each one named appears there.
                Expanded(
                  child: Globe(
                    key: _globe,
                    showAll: false,
                    look: (_trip.from.lon + 140, 15),
                    fill: (c) => c == _trip.from
                        ? _fromColor
                        : c == _trip.to
                        ? _toColor
                        : _stops.contains(c)
                        ? _colorOf(c)
                        : route.contains(c)
                        ? cs.onSurfaceVariant.withValues(alpha: 0.55)
                        : null,
                  ),
                ),
                if (_stops.isNotEmpty)
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      reverse: true, // newest first
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final c in _stops.reversed)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Pill(
                              '${c.flag}  ${c.name}',
                              color: tint(context, _colorOf(c), 0.16),
                              textColor: _colorOf(c),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (_over)
                  _ending(context, route)
                else
                  CountryInput(
                    onPick: _submit,
                    accent: Mode.route.color,
                    hint: tr('A country on the way', 'Un pays sur le chemin'),
                    exclude: {_trip.from, _trip.to, ..._stops},
                    trailing: IconSquare(
                      Icons.flag_outlined,
                      tooltip: tr('Give up', 'Abandonner'),
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        setState(() => _gaveUp = true);
                        _reframe();
                      },
                    ),
                  ),
              ],
            ),
            if (_solved) Positioned.fill(child: Confetti(key: ValueKey(_trip))),
          ],
        ),
      ),
    );
  }

  Widget _ending(BuildContext context, List<Country> route) {
    final cs = Theme.of(context).colorScheme;
    final perfect = _solved && _stops.length == _trip.steps - 1;
    final title = _solved
        ? (perfect
              ? tr('Perfect trip!', 'Trajet parfait !')
              : tr('Made it with ${_stops.length} stops', 'Arrivé en ${_stops.length} étapes'))
        : tr('One shortest way', 'Un des chemins les plus courts');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: panel(context, radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: display(20)),
          const SizedBox(height: 4),
          Text(
            _solved
                ? tr('The shortest way crosses ${_trip.steps - 1}.', 'Le plus court en traverse ${_trip.steps - 1}.')
                : route.map((c) => c.name).join(' → '),
            style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: BigButton(
                  tr('New trip', 'Autre trajet'),
                  icon: Icons.alt_route_rounded,
                  color: Mode.route.color,
                  onTap: () => setState(_newTrip),
                ),
              ),
              const SizedBox(width: 10),
              IconSquare(Icons.home_rounded, tooltip: tr('Home', 'Accueil'), onTap: () => Navigator.pop(context)),
            ],
          ),
        ],
      ),
    );
  }
}

/// One end of the trip: a colored dot, a label, the flag and the name.
class _End extends StatelessWidget {
  const _End(this.c, this.color, this.label);
  final Country c;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: panel(context, radius: 18),
      child: Row(
        children: [
          Text(c.flag, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
