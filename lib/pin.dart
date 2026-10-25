import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'globe.dart';
import 'map.dart';
import 'store.dart';
import 'ui.dart';
import 'world.dart';

/// Ten countries to place on a blank globe. 1000 points inside the border, fewer the farther the pin.
class PinPage extends StatefulWidget {
  const PinPage({super.key, required this.region});
  final Region? region;

  @override
  State<PinPage> createState() => _PinPageState();
}

class _PinPageState extends State<PinPage> {
  static const rounds = 10;
  final _globe = GlobalKey<GlobeState>();
  final _rnd = math.Random();
  final _difficulty = Store.instance.difficulty;
  late final _pool = World.instance.pool(widget.region, _difficulty);
  final _done = <({Country c, double km, int points})>[];

  late Country _target;
  (double, double)? _pin;
  var _revealed = false, _over = false, _record = false;

  int get _score => _done.fold(0, (s, r) => s + r.points);

  @override
  void initState() {
    super.initState();
    _target = Store.instance.pick(Mode.pin.name, _pool, _rnd);
    WidgetsBinding.instance.addPostFrameCallback((_) => _home(animate: false));
  }

  /// Back to the whole region, or the whole globe turned anywhere (never toward the answer).
  void _home({bool animate = true}) {
    final r = widget.region;
    r == null
        ? _globe.currentState?.lookAt(_rnd.nextDouble() * 360 - 180, 20, animate: animate)
        : _globe.currentState?.frame(
            World.instance.inRegion(r).where((c) => c.area > 20000).toList(),
            animate: animate,
          );
  }

  void _again() => setState(() {
    _done.clear();
    _over = _record = false;
    _nextRound();
  });

  void _nextRound() {
    _pin = null;
    _revealed = false;
    _target = Store.instance.pick(Mode.pin.name, _pool, _rnd, recent: _done.map((r) => r.c.id));
    _home();
  }

  void _confirm() {
    final (lon, lat) = _pin!;
    final km = _target.distanceKm(lon, lat);
    final points = km <= 50 ? 1000 : (1000 * math.exp(-km / 800)).round();
    Store.instance.record(Mode.pin.name, _target, km <= 50);
    HapticFeedback.mediumImpact();
    setState(() {
      _revealed = true;
      _done.add((c: _target, km: km, points: points));
    });
    // Show both the pin and the answer.
    _globe.currentState?.frame([_target], points: [(lon, lat)]);
  }

  void _continue() {
    if (_done.length < rounds) return setState(_nextRound);
    setState(() {
      _over = true;
      _record = Store.instance.submit(Mode.pin.name, widget.region, _difficulty, _score);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final where = widget.region?.label ?? tr('World', 'Monde');
    if (_over) {
      final inside = _done.where((r) => r.km <= 50).length;
      final avg = _done.fold(0.0, (s, r) => s + r.km) / _done.length;
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              GameBar(title: Mode.pin.title, subtitle: '$where · ${_difficulty.label}'),
              Expanded(
                child: Results(
                  mode: Mode.pin,
                  title: tr('Trip complete!', 'Voyage terminé !'),
                  score: _score,
                  record: _record,
                  best: Store.instance.best(Mode.pin.name, widget.region, _difficulty),
                  summary: tr(
                    '$inside/$rounds spot on · ${fmtKm(avg)} off on average',
                    '$inside/$rounds en plein dans le mille · ${fmtKm(avg)} d\'écart en moyenne',
                  ),
                  mistakes: [
                    for (final r in _done)
                      if (r.km > 50) r.c,
                  ],
                  onAgain: _again,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final last = _revealed ? _done.last : null;
    final pin = _pin;
    final palette = MapPalette.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              decoration: floating(context),
              child: Column(
                children: [
                  GameBar(
                    title: Mode.pin.title,
                    subtitle: '$where · ${_difficulty.label}',
                    trailing: Text(fmtInt(_score), style: display(22)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                    child: Row(
                      children: [
                        Text(_target.flag, style: const TextStyle(fontSize: 36)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('Where is', 'Où se trouve'),
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              Text(_target.name, style: display(24), maxLines: 2, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // One segment per round: green when spot on, blue when scored, gray when to come.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                    child: Row(
                      children: [
                        for (var i = 0; i < rounds; i++)
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              height: 5,
                              margin: EdgeInsets.only(right: i < rounds - 1 ? 4 : 0),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(99),
                                color: i < _done.length
                                    ? (_done[i].km <= 50 ? good : Mode.pin.color)
                                    : i == _done.length
                                    ? cs.onSurface.withValues(alpha: 0.35)
                                    : cs.surfaceContainerHighest,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Globe(
                key: _globe,
                fill: _revealed ? (c) => c == _target ? good : null : null,
                marks: [
                  if (pin != null && _revealed) MapMark.line(pin.$1, pin.$2, _target.lon, _target.lat, palette.ink),
                  if (pin != null) MapMark.pin(pin.$1, pin.$2, Mode.pin.color),
                ],
                onTapPoint: _revealed
                    ? null
                    : (lon, lat) {
                        HapticFeedback.selectionClick();
                        setState(() => _pin = (lon, lat));
                      },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: last == null
                    ? BigButton(
                        key: const ValueKey('confirm'),
                        pin == null ? tr('Tap the globe', 'Touche le globe') : tr('Confirm', 'Valider'),
                        icon: pin == null ? Icons.touch_app_rounded : Icons.check_rounded,
                        color: Mode.pin.color,
                        onTap: pin == null ? null : _confirm,
                      )
                    : _Verdict(key: ValueKey(_done.length), km: last.km, points: last.points, onNext: _continue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({super.key, required this.km, required this.points, required this.onNext});
  final double km;
  final int points;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color, text) = km <= 50
        ? (Icons.gps_fixed_rounded, good, tr('Spot on', 'En plein dedans'))
        : km < 500
        ? (Icons.near_me_rounded, const Color(0xFFF29D0C), tr('So close', 'Tout près'))
        : km < 1500
        ? (Icons.explore_rounded, Mode.pin.color, tr('Not bad', 'Pas mal'))
        : (Icons.ac_unit_rounded, const Color(0xFF6B7A99), tr('Far away', 'Bien loin'));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: floating(context),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: tint(context, color, 0.16), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: display(19)),
                Text(
                  km <= 50 ? '+${fmtInt(points)}' : '${fmtKm(km)} · +${fmtInt(points)}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 120,
            child: BigButton(tr('Next', 'Suivant'), color: Mode.pin.color, onTap: onNext),
          ),
        ],
      ),
    );
  }
}
