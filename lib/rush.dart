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
    _pool = World.instance.inRegion(widget.region).where((c) => mode != Mode.shapes || c.hasShape).toList();
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
    final near = World.instance.inRegion(_target.region).where((c) => c != _target).toList()..shuffle(_rnd);
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
      _record = Store.instance.submit(mode.name, widget.region, _score);
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
              mode: mode,
              title: '${mode.title} · $where',
              trailing: _over ? null : _ScoreBadge(score: _score, multiplier: _multiplier, colors: mode.colors),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: _over
                    ? Results(
                        key: const ValueKey('results'),
                        mode: mode,
                        title: tr("Time's up!", 'Temps écoulé !'),
                        score: _score,
                        record: _record,
                        best: Store.instance.best(mode.name, widget.region),
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('play'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        children: [
          AnimatedBuilder(animation: _clock, builder: (context, _) => _TimeBar(1 - _clock.value)),
          const SizedBox(height: 16),
          Expanded(
            child: Shake(
              trigger: _shake,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, a) => ScaleTransition(
                  scale: Tween(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
                  child: FadeTransition(opacity: a, child: child),
                ),
                child: Container(
                  key: ValueKey(_target.id + _recent.length.toString()),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: mode.gradient,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: mode.colors.last.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: _prompt(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final o in _options)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
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
                surface: cs.surfaceContainerHighest,
              ),
            ),
        ],
      ),
    );
  }

  Widget _prompt() {
    const white = Colors.white;
    switch (mode) {
      case Mode.flags:
        // Emoji flags are bitmaps: past ~120 they only get blurrier.
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(_target.flag, style: const TextStyle(fontSize: 120)),
          ),
        );
      case Mode.shapes:
        return ShapeView(_target);
      default:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(tr('Capital of', 'Capitale de'), style: display(20, color: white.withValues(alpha: 0.85))),
            const SizedBox(height: 8),
            Flexible(
              child: FittedBox(child: Text(_target.flag, style: const TextStyle(fontSize: 72))),
            ),
            const SizedBox(height: 8),
            Text(
              _target.name,
              textAlign: TextAlign.center,
              style: display(36, color: white),
            ),
          ],
        );
    }
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score, required this.multiplier, required this.colors});
  final int score, multiplier;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
        child: multiplier > 1
            ? Container(
                key: ValueKey(multiplier),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('🔥 x$multiplier', style: display(16, color: Colors.white)),
              )
            : const SizedBox.shrink(),
      ),
      TweenAnimationBuilder(
        tween: IntTween(end: score),
        duration: const Duration(milliseconds: 300),
        builder: (context, v, _) => Text(fmtInt(v), style: display(26)),
      ),
    ],
  );
}

/// Time left, from green to red.
class _TimeBar extends StatelessWidget {
  const _TimeBar(this.left);
  final double left;

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(
      bad,
      Color.lerp(const Color(0xFFFFC233), good, ((left - 0.5) * 2).clamp(0, 1)),
      (left * 3).clamp(0, 1),
    )!;
    return Container(
      height: 12,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: left.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99)),
        ),
      ),
    );
  }
}

enum _OptionState { idle, right, wrong, dim }

class _Option extends StatelessWidget {
  const _Option({required this.label, required this.state, required this.onTap, required this.surface});
  final String label;
  final _OptionState state;
  final VoidCallback onTap;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (state) {
      _OptionState.right => (good, Colors.white),
      _OptionState.wrong => (bad, Colors.white),
      _ => (surface, Theme.of(context).colorScheme.onSurface),
    };
    return Bouncy(
      onTap: state == _OptionState.idle ? onTap : null,
      child: AnimatedOpacity(
        opacity: state == _OptionState.dim ? 0.4 : 1,
        duration: const Duration(milliseconds: 200),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minHeight: 58),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
          alignment: Alignment.center,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: fg),
                ),
              ),
              if (state == _OptionState.right) const Icon(Icons.check_circle_rounded, color: Colors.white),
              if (state == _OptionState.wrong) const Icon(Icons.cancel_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
