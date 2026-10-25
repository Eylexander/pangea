import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'map.dart';
import 'store.dart';
import 'ui.dart';
import 'world.dart';

/// Close-up: the map starts zoomed in on a bit of a country's border and pulls back step by step.
/// The sooner it's named, the more points.
class CloseupPage extends StatefulWidget {
  const CloseupPage({super.key, required this.region});
  final Region? region;

  @override
  State<CloseupPage> createState() => _CloseupPageState();
}

class _CloseupPageState extends State<CloseupPage> {
  static const rounds = 10, levels = 5;
  static const points = [500, 400, 300, 200, 100];
  final _difficulty = Store.instance.difficulty;
  final _rnd = math.Random();
  final _map = GlobalKey<WorldMapState>();
  late final _pool = World.instance.pool(widget.region, _difficulty).where((c) => c.hasShape).toList();
  final _done = <({Country c, int points})>[];

  late Country _target;
  late List<Country> _options;
  late List<Rect> _steps;
  var _level = 0;
  Country? _picked;
  var _over = false, _record = false;
  Timer? _zoom;

  int get _score => _done.fold(0, (s, r) => s + r.points);

  @override
  void initState() {
    super.initState();
    _ask();
  }

  @override
  void dispose() {
    _zoom?.cancel();
    super.dispose();
  }

  void _ask() {
    _picked = null;
    _level = 0;
    _target = Store.instance.pick(Mode.closeup.name, _pool, _rnd, recent: _done.map((r) => r.c.id));
    final near = World.instance.pool(_target.region, _difficulty).where((c) => c != _target && c.hasShape).toList()
      ..shuffle(_rnd);
    final far = World.instance.countries.where((c) => c != _target && c.hasShape).toList()..shuffle(_rnd);
    _options = ({_target, ...near, ...far}.take(4).toList())..shuffle(_rnd);

    // From a random point on the border to the whole country with its surroundings, on a log scale.
    final ring = _target.polygons.first.first;
    final i = _rnd.nextInt(ring.length ~/ 2) * 2;
    final start = Offset(ring[i], ring[i + 1]);
    final end = _target.view;
    final endSize = end.longestSide * 1.9 + 2;
    final startSize = math.max(0.35, end.longestSide * 0.07);
    _steps = [
      for (var k = 0; k < levels; k++)
        () {
          final t = k / (levels - 1);
          final size = startSize * math.pow(endSize / startSize, t);
          final c = Offset.lerp(start, end.center, t)!;
          return Rect.fromCenter(center: c, width: size, height: size);
        }(),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) => _map.currentState?.focus(_steps[0], animate: false));
    _zoom?.cancel();
    _zoom = Timer.periodic(const Duration(milliseconds: 2400), (t) {
      if (!mounted || _picked != null) return t.cancel();
      if (_level >= levels - 1) return t.cancel();
      setState(() => _level++);
      _map.currentState?.focus(_steps[_level]);
    });
  }

  void _answer(Country c) {
    if (_picked != null) return;
    _zoom?.cancel();
    final right = c == _target;
    Store.instance.record(Mode.closeup.name, _target, right);
    right ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
    setState(() {
      _picked = c;
      _done.add((c: _target, points: right ? points[_level] : 0));
    });
    _map.currentState?.focus(_steps.last);
  }

  void _continue() {
    if (_done.length < rounds) return setState(_ask);
    setState(() {
      _over = true;
      _record = Store.instance.submit(Mode.closeup.name, widget.region, _difficulty, _score);
    });
  }

  void _again() => setState(() {
    _done.clear();
    _over = _record = false;
    _ask();
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final where = widget.region?.label ?? tr('World', 'Monde');
    final accent = Mode.closeup.color;
    if (_over) {
      final right = _done.where((r) => r.points > 0).length;
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              GameBar(title: Mode.closeup.title, subtitle: '$where · ${_difficulty.label}'),
              Expanded(
                child: Results(
                  mode: Mode.closeup,
                  title: tr('All zoomed out', 'Fin du dézoom'),
                  score: _score,
                  record: _record,
                  best: Store.instance.best(Mode.closeup.name, widget.region, _difficulty),
                  summary: tr('$right/$rounds recognized', '$right/$rounds reconnus'),
                  mistakes: [
                    for (final r in _done)
                      if (r.points == 0) r.c,
                  ],
                  onAgain: _again,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final answered = _picked != null;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            GameBar(
              title: Mode.closeup.title,
              subtitle: '${_done.length + (answered ? 0 : 1)}/$rounds · $where · ${_difficulty.label}',
              trailing: Text(fmtInt(_score), style: display(22)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
              child: Row(
                children: [
                  Text(
                    answered
                        ? (_picked == _target
                              ? '+${points[_level]}'
                              : tr('It was ${_target.name}', 'C\'était ${_target.name}'))
                        : tr('Worth ${points[_level]} now', 'Vaut ${points[_level]} maintenant'),
                    style: display(16, color: answered ? (_picked == _target ? good : bad) : cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  // How far it has zoomed out.
                  for (var k = 0; k < levels; k++)
                    Container(
                      width: 18,
                      height: 5,
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: k <= _level ? accent : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                clipBehavior: Clip.antiAlias,
                decoration: panel(context, radius: 24),
                // No zooming out by hand while the question is on.
                child: IgnorePointer(
                  ignoring: !answered,
                  child: WorldMap(
                    key: _map,
                    view: _steps.first,
                    dots: false,
                    fill: (c) => c == _target ? (answered ? (_picked == _target ? good : bad) : accent) : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (!answered)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.9,
                  children: [
                    for (final o in _options)
                      Bouncy(
                        onTap: () => _answer(o),
                        child: Container(
                          decoration: panel(context, radius: 16),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            o.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(_target.flag, style: const TextStyle(fontSize: 34)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_target.name, style: display(20), maxLines: 2)),
                    SizedBox(
                      width: 140,
                      child: BigButton(tr('Next', 'Suivant'), color: accent, onTap: _continue),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}
