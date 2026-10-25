import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'map.dart';
import 'store.dart';
import 'ui.dart';
import 'world.dart';

enum _Stat {
  population,
  area;

  int of(Country c) => this == population ? c.population : c.area;
  String format(Country c) => this == population ? fmtPopulation(c.population) : '${fmtInt(c.area)} km²';
  String get title => this == population ? tr('Population', 'Population') : tr('Area', 'Superficie');
  String get label => this == population ? tr('people', 'habitants') : tr('area', 'de superficie');
  String get more => this == population ? tr('More people', 'Plus peuplé') : tr('Bigger', 'Plus grand');
  String get less => this == population ? tr('Fewer people', 'Moins peuplé') : tr('Smaller', 'Plus petit');
  IconData get icon => this == population ? Icons.groups_rounded : Icons.straighten_rounded;

  /// Each question type has its own color, so a switch from one to the other can't be missed.
  Color get color => this == population ? Mode.higher.color : const Color(0xFF0B9DB8);
}

/// Higher or lower: is the next country more populous (or bigger) than this one? One mistake ends the streak.
class HigherPage extends StatefulWidget {
  const HigherPage({super.key, required this.region});
  final Region? region;

  @override
  State<HigherPage> createState() => _HigherPageState();
}

class _HigherPageState extends State<HigherPage> {
  final _difficulty = Store.instance.difficulty;
  final _rnd = math.Random();
  late final _pool = World.instance.pool(widget.region, _difficulty);
  final _seen = <Country>[];

  late Country _a, _b;
  late _Stat _stat;
  var _streak = 0;
  bool? _right;
  var _over = false, _record = false;
  Timer? _next;

  @override
  void initState() {
    super.initState();
    _a = _pool[_rnd.nextInt(_pool.length)];
    _seen.add(_a);
    _deal();
  }

  @override
  void dispose() {
    _next?.cancel();
    super.dispose();
  }

  /// A new challenger, never a near tie (within 15 %): those are coin flips, not knowledge.
  void _deal() {
    _stat = _Stat.values[_rnd.nextInt(2)];
    final fresh = _pool.where((c) => !_seen.contains(c)).toList()..shuffle(_rnd);
    bool clear(Country c) => (math.log(_stat.of(c) / _stat.of(_a))).abs() > math.log(1.15);
    _b = fresh.firstWhere(clear, orElse: () => fresh.isNotEmpty ? fresh.first : _pool.firstWhere((c) => c != _a));
    _seen.add(_b);
    _right = null;
  }

  void _answer(bool more) {
    if (_right != null) return;
    final right = more == (_stat.of(_b) > _stat.of(_a));
    Store.instance.record(Mode.higher.name, _b, right);
    setState(() => _right = right);
    right ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
    _next = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        if (right) {
          _streak++;
          _a = _b;
          _deal();
        } else {
          _over = true;
          _record = Store.instance.submit(Mode.higher.name, widget.region, _difficulty, _streak);
        }
      });
    });
  }

  void _again() => setState(() {
    _streak = 0;
    _over = _record = false;
    _seen
      ..clear()
      ..add(_a);
    _deal();
  });

  @override
  Widget build(BuildContext context) {
    final where = widget.region?.label ?? tr('World', 'Monde');
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            GameBar(
              title: Mode.higher.title,
              subtitle: '$where · ${_difficulty.label}',
              trailing: _over ? null : Pill('$_streak', icon: Icons.local_fire_department_rounded),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _over
                    ? Results(
                        key: const ValueKey('results'),
                        mode: Mode.higher,
                        title: tr('Streak over', 'Fin de la série'),
                        score: _streak,
                        record: _record,
                        best: Store.instance.best(Mode.higher.name, widget.region, _difficulty),
                        summary: tr(
                          '${_b.name}: ${_stat.format(_b)} · ${_a.name}: ${_stat.format(_a)}',
                          '${_b.name} : ${_stat.format(_b)} · ${_a.name} : ${_stat.format(_a)}',
                        ),
                        mistakes: [_b],
                        onAgain: _again,
                      )
                    : Padding(
                        key: ValueKey(_b.id),
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                        child: Column(
                          children: [
                            Expanded(child: _Card(_a, _stat, revealed: true)),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.fromLTRB(12, 6, 14, 6),
                                    decoration: BoxDecoration(
                                      color: tint(context, _stat.color, 0.16),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(_stat.icon, size: 20, color: _stat.color),
                                        const SizedBox(width: 8),
                                        Text(_stat.title.toUpperCase(), style: display(15, color: _stat.color)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    tr(
                                      _stat == _Stat.population
                                          ? 'Does ${_b.name} have more or fewer people?'
                                          : 'Is ${_b.name} bigger or smaller?',
                                      _stat == _Stat.population
                                          ? '${_b.name} : plus ou moins peuplé ?'
                                          : '${_b.name} : plus grand ou plus petit ?',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: display(17, weight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: _Card(_b, _stat, revealed: _right != null, right: _right, versus: _a),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: BigButton(
                                    _stat.less,
                                    icon: Icons.arrow_downward_rounded,
                                    color: _stat.color,
                                    onTap: _right == null ? () => _answer(false) : null,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: BigButton(
                                    _stat.more,
                                    icon: Icons.arrow_upward_rounded,
                                    color: _stat.color,
                                    onTap: _right == null ? () => _answer(true) : null,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card(this.c, this.stat, {required this.revealed, this.right, this.versus});
  final Country c;
  final _Stat stat;
  final bool revealed;
  final bool? right;
  final Country? versus;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = right == null ? null : (right! ? good : bad);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(16),
      decoration: panel(context, radius: 24, color: color == null ? null : tint(context, color, 0.12), border: color),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(c.flag, style: const TextStyle(fontSize: 40)),
                const SizedBox(height: 6),
                Text(c.name, style: display(24), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                if (revealed)
                  TweenAnimationBuilder(
                    // Counts up when revealed, the suspense part.
                    tween: Tween(begin: versus == null ? 1.0 : 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, _) => Text(
                      t == 1 ? stat.format(c) : _partial(stat, c, t),
                      style: display(22, color: color ?? stat.color),
                    ),
                  )
                else
                  Text('?', style: display(22, color: cs.onSurfaceVariant)),
                Row(
                  children: [
                    Icon(stat.icon, size: 16, color: stat.color),
                    const SizedBox(width: 4),
                    Text(
                      stat.label,
                      style: TextStyle(color: stat.color, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (c.hasShape)
            SizedBox(width: 132, height: 132, child: ShapeView(c, color: cs.onSurface.withValues(alpha: 0.12))),
        ],
      ),
    );
  }

  static String _partial(_Stat stat, Country c, double t) =>
      stat == _Stat.population ? fmtPopulation((c.population * t).round()) : '${fmtInt((c.area * t).round())} km²';
}
