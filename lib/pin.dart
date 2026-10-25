import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'map.dart';
import 'store.dart';
import 'ui.dart';
import 'world.dart';

/// Ten countries to place on a blank map. 1000 points inside the border, fewer the farther the pin.
class PinPage extends StatefulWidget {
  const PinPage({super.key, required this.region});
  final Region? region;

  @override
  State<PinPage> createState() => _PinPageState();
}

class _PinPageState extends State<PinPage> {
  static const rounds = 10;
  final _map = GlobalKey<WorldMapState>();
  final _rnd = math.Random();
  late final _pool = World.instance.inRegion(widget.region);
  final _done = <({Country c, double km, int points})>[];

  late Country _target;
  (double, double)? _pin;
  var _revealed = false, _over = false, _record = false;

  Rect get _view => widget.region?.view ?? Region.worldView;
  int get _score => _done.fold(0, (s, r) => s + r.points);

  @override
  void initState() {
    super.initState();
    _target = Store.instance.pick(Mode.pin.name, _pool, _rnd);
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
    _map.currentState?.focus(_view);
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
    final t = _target.bounds.width < 90
        ? _target.bounds
        : Rect.fromCenter(center: Offset(_target.lon, _target.lat), width: 20, height: 20);
    final box = t.expandToInclude(Rect.fromCenter(center: Offset(lon, lat), width: 0, height: 0));
    final margin = math.max(4.0, math.max(box.width, box.height) * 0.25);
    _map.currentState?.focus(box.inflate(margin));
  }

  void _continue() {
    if (_done.length < rounds) return setState(_nextRound);
    setState(() {
      _over = true;
      _record = Store.instance.submit(Mode.pin.name, widget.region, _score);
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
              GameBar(mode: Mode.pin, title: '${Mode.pin.title} · $where'),
              Expanded(
                child: Results(
                  mode: Mode.pin,
                  title: tr('Trip complete!', 'Voyage terminé !'),
                  score: _score,
                  record: _record,
                  best: Store.instance.best(Mode.pin.name, widget.region),
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
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: WorldMap(
              key: _map,
              view: _view,
              padding: const EdgeInsets.only(top: 170, bottom: 150, left: 16, right: 16),
              fill: _revealed
                  ? (c) => c == _target ? good : landColor(c, Theme.of(context).brightness).withValues(alpha: 0.45)
                  : null,
              pulse: _revealed ? _target : null,
              marks: [
                if (pin != null && _revealed) MapMark.line(pin.$1, pin.$2, _target.lon, _target.lat, cs.onSurface),
                if (pin != null) MapMark.pin(pin.$1, pin.$2, Mode.pin.colors.first),
              ],
              onTap: _revealed
                  ? null
                  : (lon, lat, _) {
                      HapticFeedback.selectionClick();
                      setState(() => _pin = (lon, lat));
                    },
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 6))],
                  ),
                  child: Column(
                    children: [
                      GameBar(
                        mode: Mode.pin,
                        title: '${_done.length + (_revealed ? 0 : 1)}/$rounds',
                        trailing: Text(fmtInt(_score), style: display(24)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: Row(
                          children: [
                            Text(_target.flag, style: const TextStyle(fontSize: 40)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tr('Where is', 'Où se trouve'), style: TextStyle(color: cs.onSurfaceVariant)),
                                  Text(_target.name, style: display(28), maxLines: 2, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: last == null
                        ? BigButton(
                            key: const ValueKey('confirm'),
                            pin == null ? tr('Tap the map', 'Touche la carte') : tr('Confirm', 'Valider'),
                            icon: pin == null ? Icons.touch_app_rounded : Icons.check_rounded,
                            colors: Mode.pin.colors,
                            onTap: pin == null ? null : _confirm,
                          )
                        : _Verdict(key: ValueKey(_done.length), km: last.km, points: last.points, onNext: _continue),
                  ),
                ),
              ],
            ),
          ),
        ],
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
    final (emoji, text) = km <= 50
        ? ('🎯', tr('Spot on!', 'En plein dedans !'))
        : km < 500
        ? ('🔥', tr('So close', 'Tout près'))
        : km < 1500
        ? ('🙂', tr('Not bad', 'Pas mal'))
        : ('🧊', tr('Far away', 'Bien loin'));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 40)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: display(22)),
                Text(
                  km <= 50 ? '+${fmtInt(points)}' : '${fmtKm(km)} · +${fmtInt(points)}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 130,
            child: BigButton(tr('Next', 'Suivant'), colors: Mode.pin.colors, onTap: onNext),
          ),
        ],
      ),
    );
  }
}
