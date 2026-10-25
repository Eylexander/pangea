import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'map.dart';
import 'store.dart';
import 'ui.dart';
import 'world.dart';

/// 60 seconds of four-choice questions: a flag, a country's capital, or an outline.
/// Every third right answer in a row raises the multiplier (up to x5); a miss costs 3 seconds and the combo.
class RushPage extends StatefulWidget {
  const RushPage({super.key, required this.mode, required this.region});
  final Mode mode;
  final Region? region;

  @override
  State<RushPage> createState() => _RushPageState();
}

class _RushPageState extends State<RushPage> with SingleTickerProviderStateMixin {
  static const seconds = 60, penalty = 3;
  late final _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: seconds),
  );
  final _rnd = math.Random();
  late final List<Country> _pool;
  final _difficulty = Store.instance.difficulty;
  final _recent = <String>[];
  final _mistakes = <Country>[];

  late Country _target;
  late List<Country> _options;
  Country? _picked;
  var _score = 0, _right = 0, _combo = 0, _shake = 0;
  var _over = false, _record = false;
  Timer? _next;

  Mode get mode => widget.mode;
  int get _multiplier => math.min(5, 1 + _combo ~/ 3);

  @override
  void initState() {
    super.initState();
    _pool = World.instance.pool(widget.region, _difficulty).where((c) => mode != Mode.shapes || c.hasShape).toList();
    _clock.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
    _start();
  }

  void _start() {
    _score = _right = _combo = 0;
    _over = _record = false;
    _mistakes.clear();
    _ask();
    _clock.forward(from: 0);
  }

  void _ask() {
    _picked = null;
    _target = Store.instance.pick(mode.name, _pool, _rnd, recent: _recent);
    _recent.add(_target.id);
    if (_recent.length > math.min(15, _pool.length ~/ 2)) _recent.removeAt(0);
    // Wrong options from the same region when possible: Niger vs Nigeria teaches more than Niger vs Japan.
    final near = World.instance.pool(_target.region, _difficulty).where((c) => c != _target).toList()..shuffle(_rnd);
    final far = World.instance.countries.where((c) => c != _target).toList()..shuffle(_rnd);
    final options = <Country>[_target];
    for (final c in [...near, ...far]) {
      if (options.length == 4) break;
      if (mode == Mode.shapes && !c.hasShape) continue;
      if (options.any((o) => o == c || (mode == Mode.capitals && o.capital == c.capital))) continue;
      options.add(c);
    }
    _options = options..shuffle(_rnd);
  }

  void _answer(Country c) {
    if (_picked != null || _over) return;
    final right = c == _target;
    Store.instance.record(mode.name, _target, right);
    setState(() {
      _picked = c;
      if (right) {
        _right++;
        _score += 100 * _multiplier;
        _combo++;
        HapticFeedback.lightImpact();
      } else {
        _combo = 0;
        _shake++;
        if (!_mistakes.contains(_target)) _mistakes.add(_target);
        // Setting the value stops the clock; forward() resumes it for the time left.
        _clock.value = math.min(1, _clock.value + penalty / seconds);
        if (_clock.value < 1) _clock.forward();
        HapticFeedback.heavyImpact();
      }
    });
    _next = Timer(Duration(milliseconds: right ? 450 : 1300), () {
      if (mounted && !_over) setState(_ask);
    });
  }

  void _finish() {
    if (_over) return;
    _next?.cancel();
    setState(() {
      _over = true;
      _record = Store.instance.submit(mode.name, widget.region, _difficulty, _score);
    });
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _next?.cancel();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final where = widget.region?.label ?? tr('World', 'Monde');
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            GameBar(
              title: mode.title,
              subtitle: '$where · ${_difficulty.label}',
              trailing: _over ? null : _ScoreBadge(score: _score, multiplier: _multiplier, color: mode.color),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _over
                    ? Results(
                        key: const ValueKey('results'),
                        mode: mode,
                        title: tr("Time's up", 'Temps écoulé'),
                        score: _score,
                        record: _record,
                        best: Store.instance.best(mode.name, widget.region, _difficulty),
                        summary: tr(
                          '$_right right answers · ${_mistakes.length} to review',
                          '$_right bonnes réponses · ${_mistakes.length} à revoir',
                        ),
                        mistakes: _mistakes,
                        onAgain: () => setState(_start),
                      )
                    : _question(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _question(BuildContext context) {
    return Padding(
      key: const ValueKey('play'),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _clock,
            builder: (context, _) => _TimeBar(1 - _clock.value, color: mode.color),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Shake(
              trigger: _shake,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
                    child: child,
                  ),
                ),
                child: Container(
                  key: ValueKey(_target.id + _recent.length.toString()),
                  width: double.infinity,
                  decoration: panel(context, radius: 28),
                  padding: const EdgeInsets.all(24),
                  child: _prompt(context),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final o in _options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Option(
                label: mode == Mode.capitals ? o.capital : o.name,
                state: _picked == null
                    ? _OptionState.idle
                    : o == _target
                    ? _OptionState.right
                    : o == _picked
                    ? _OptionState.wrong
                    : _OptionState.dim,
                onTap: () => _answer(o),
              ),
            ),
        ],
      ),
    );
  }

  Widget _prompt(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (mode) {
      case Mode.flags:
        // Emoji flags are bitmaps: past ~120 they only get blurrier.
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(_target.flag, style: const TextStyle(fontSize: 116)),
          ),
        );
      case Mode.shapes:
        return Padding(
          padding: const EdgeInsets.all(8),
          child: ShapeView(_target, color: mode.color),
        );
      default:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              tr('Capital of', 'Capitale de'),
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: FittedBox(child: Text(_target.flag, style: const TextStyle(fontSize: 64))),
            ),
            const SizedBox(height: 12),
            Text(_target.name, textAlign: TextAlign.center, style: display(30)),
          ],
        );
    }
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score, required this.multiplier, required this.color});
  final int score, multiplier;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
        child: multiplier > 1
            ? Container(
                key: ValueKey(multiplier),
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.fromLTRB(6, 3, 9, 3),
                decoration: BoxDecoration(color: tint(context, color, 0.16), borderRadius: BorderRadius.circular(99)),
                child: Row(
                  children: [
                    Icon(Icons.bolt_rounded, size: 16, color: color),
                    Text('x$multiplier', style: display(14, color: color)),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      ),
      TweenAnimationBuilder(
        tween: IntTween(end: score),
        duration: const Duration(milliseconds: 300),
        builder: (context, v, _) => Text(fmtInt(v), style: display(22)),
      ),
    ],
  );
}

/// Time left: a thin bar in the game's color, red for the last quarter, and the seconds.
class _TimeBar extends StatelessWidget {
  const _TimeBar(this.left, {required this.color});
  final double left;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = left < 0.25 ? bad : color;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: left.clamp(0.0, 1.0),
              minHeight: 6,
              color: c,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 34,
          child: Text(
            '${(left * _RushPageState.seconds).ceil()}s',
            textAlign: TextAlign.end,
            style: display(14, color: left < 0.25 ? bad : cs.onSurfaceVariant, weight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

enum _OptionState { idle, right, wrong, dim }

class _Option extends StatelessWidget {
  const _Option({required this.label, required this.state, required this.onTap});
  final String label;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, border, fg, icon) = switch (state) {
      _OptionState.right => (tint(context, good, 0.14), good, good, Icons.check_circle_rounded),
      _OptionState.wrong => (tint(context, bad, 0.14), bad, bad, Icons.cancel_rounded),
      _ => (cs.surfaceContainerLowest, cs.outlineVariant, cs.onSurface, null),
    };
    return Bouncy(
      onTap: state == _OptionState.idle ? onTap : null,
      child: AnimatedOpacity(
        opacity: state == _OptionState.dim ? 0.45 : 1,
        duration: const Duration(milliseconds: 180),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 56),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border, width: icon == null ? 1 : 1.5),
          ),
          alignment: Alignment.center,
          child: Row(
            children: [
              const SizedBox(width: 24),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: fg),
                ),
              ),
              SizedBox(width: 24, child: icon == null ? null : Icon(icon, color: fg, size: 22)),
            ],
          ),
        ),
      ),
    );
  }
}
