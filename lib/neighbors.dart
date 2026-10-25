import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'globe.dart';
import 'store.dart';
import 'ui.dart';
import 'world.dart';

/// Neighbors: a country alone on the globe; name every country it borders. Three wrong names end the round.
class NeighborsPage extends StatefulWidget {
  const NeighborsPage({super.key, required this.region});
  final Region? region;

  @override
  State<NeighborsPage> createState() => _NeighborsPageState();
}

class _NeighborsPageState extends State<NeighborsPage> {
  static const rounds = 5, strikes = 3;
  final _difficulty = Store.instance.difficulty;
  final _rnd = math.Random();
  final _globe = GlobalKey<GlobeState>();
  late final List<Country> _pool;

  final _played = <Country>[];
  final _found = <Country>{}, _wrong = <Country>{};
  final _missed = <Country>[];
  late Country _country;
  var _score = 0, _foundTotal = 0, _askedTotal = 0, _shake = 0;
  var _roundOver = false, _over = false, _record = false;

  List<Country> get _neighbors => World.instance.neighbors(_country);
  Color get _accent => Mode.neighbors.color;

  /// The country itself: blue, apart from the green of the right answers.
  static const _center = Color(0xFF2F7BFF);

  @override
  void initState() {
    super.initState();
    bool fits(Country c) => c.neighborIds.length >= 2;
    final pool = World.instance.pool(widget.region, _difficulty).where(fits).toList();
    _pool = pool.length >= rounds ? pool : World.instance.pool(null, _difficulty).where(fits).toList();
    _next();
  }

  void _next() {
    _country = Store.instance.pick(Mode.neighbors.name, _pool, _rnd, recent: _played.map((c) => c.id));
    _played.add(_country);
    _found.clear();
    _wrong.clear();
    _roundOver = false;
    _frame();
  }

  void _frame() => WidgetsBinding.instance.addPostFrameCallback(
    // Room around the country from the start, for its neighbors to appear in.
    (_) => _globe.currentState?.frame([_country, ..._found, ..._wrong, if (_roundOver) ..._neighbors], minReach: 0.45),
  );

  void _pick(Country c) {
    if (_roundOver) return;
    if (c == _country || _found.contains(c) || _wrong.contains(c)) {
      setState(() => _shake++);
      return;
    }
    final right = _neighbors.contains(c);
    setState(() {
      if (right) {
        _found.add(c);
        _score += 100;
        Store.instance.record(Mode.neighbors.name, c, true);
        HapticFeedback.lightImpact();
      } else {
        _wrong.add(c);
        HapticFeedback.heavyImpact();
      }
      if (_found.length == _neighbors.length || _wrong.length >= strikes) _endRound();
    });
    _frame();
  }

  void _endRound() {
    _roundOver = true;
    final perfect = _found.length == _neighbors.length;
    if (perfect) _score += 200;
    Store.instance.record(Mode.neighbors.name, _country, perfect);
    _foundTotal += _found.length;
    _askedTotal += _neighbors.length;
    _missed.addAll(_neighbors.where((n) => !_found.contains(n)));
    FocusScope.of(context).unfocus();
  }

  void _continue() {
    if (_played.length < rounds) return setState(_next);
    setState(() {
      _over = true;
      _record = Store.instance.submit(Mode.neighbors.name, widget.region, _difficulty, _score);
    });
  }

  void _again() => setState(() {
    _played.clear();
    _missed.clear();
    _score = _foundTotal = _askedTotal = 0;
    _over = _record = false;
    _next();
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final where = widget.region?.label ?? tr('World', 'Monde');
    if (_over) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              GameBar(title: Mode.neighbors.title, subtitle: '$where · ${_difficulty.label}'),
              Expanded(
                child: Results(
                  mode: Mode.neighbors,
                  title: tr('Borders crossed', 'Frontières passées'),
                  score: _score,
                  record: _record,
                  best: Store.instance.best(Mode.neighbors.name, widget.region, _difficulty),
                  summary: tr(
                    '$_foundTotal of $_askedTotal neighbors found',
                    '$_foundTotal voisins trouvés sur $_askedTotal',
                  ),
                  mistakes: _missed.toSet().toList(),
                  onAgain: _again,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final total = _neighbors.length;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            GameBar(
              title: Mode.neighbors.title,
              subtitle: '${_played.length}/$rounds · $where · ${_difficulty.label}',
              trailing: Text(fmtInt(_score), style: display(22)),
            ),
            Shake(
              trigger: _shake,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: panel(context, radius: 20),
                child: Row(
                  children: [
                    Text(_country.flag, style: const TextStyle(fontSize: 34)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('Countries bordering', 'Les voisins de'),
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          Text(_country.name, style: display(22), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${_found.length}/$total', style: display(20, color: _accent)),
                        Row(
                          children: [
                            for (var i = 0; i < strikes; i++)
                              Icon(
                                i < strikes - _wrong.length ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                size: 16,
                                color: bad,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Only the country and the names said so far are on the globe.
            Expanded(
              child: Globe(
                key: _globe,
                showAll: false,
                look: (_country.lon - 120, 20),
                fill: (c) => c == _country
                    ? _center
                    : _found.contains(c)
                    ? good
                    : _wrong.contains(c)
                    ? bad
                    : _roundOver && _neighbors.contains(c)
                    ? cs.onSurfaceVariant.withValues(alpha: 0.55)
                    : null,
              ),
            ),
            if (_found.isNotEmpty || _wrong.isNotEmpty)
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final c in [..._found, ..._wrong])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Pill(
                          '${c.flag}  ${c.name}',
                          color: tint(context, _found.contains(c) ? good : bad, 0.16),
                          textColor: _found.contains(c) ? good : bad,
                        ),
                      ),
                  ],
                ),
              ),
            if (_roundOver)
              _roundEnd(context)
            else
              CountryInput(
                onPick: _pick,
                accent: _accent,
                hint: tr('A neighbor', 'Un voisin'),
                exclude: {_country, ..._found, ..._wrong},
              ),
          ],
        ),
      ),
    );
  }

  Widget _roundEnd(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final missing = _neighbors.where((n) => !_found.contains(n)).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: panel(context, radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            missing.isEmpty ? tr('All of them!', 'Tous trouvés !') : tr('You missed', 'Il manquait'),
            style: display(19),
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              missing.map((c) => '${c.flag} ${c.name}').join('   '),
              style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 14),
          BigButton(
            _played.length < rounds ? tr('Next country', 'Pays suivant') : tr('See my score', 'Voir mon score'),
            icon: Icons.arrow_forward_rounded,
            color: _accent,
            onTap: _continue,
          ),
        ],
      ),
    );
  }
}
