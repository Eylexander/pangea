import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'map.dart';
import 'store.dart';
import 'ui.dart';
import 'world.dart';

const maxGuesses = 6;

/// How warm a guess is: 100 % on target, 0 % on the other side of the planet.
int warmth(Country guess, Country target) =>
    guess == target ? 100 : (100 * (1 - haversineKm(guess.lat, guess.lon, target.lat, target.lon) / 20000)).floor();

/// Blue when far, yellow around 1000 km, red when next door. On a log scale: inside Europe every guess is 90 %+
/// warm, so the percentage alone doesn't tell neighbors apart.
Color heat(double km) {
  final t = (1 - math.log(math.max(km, 100) / 100) / math.log(100)).clamp(0.0, 1.0); // 100 km → 1, 10000 km → 0
  return t < 0.5
      ? Color.lerp(const Color(0xFF5B8CFF), const Color(0xFFFFB020), t * 2)!
      : Color.lerp(const Color(0xFFFFB020), const Color(0xFFFF3D3D), t * 2 - 1)!;
}

String arrowEmoji(double bearing) =>
    const ['⬆️', '↗️', '➡️', '↘️', '⬇️', '↙️', '⬅️', '↖️'][((bearing + 22.5) % 360) ~/ 45];

/// The text copied by "Share": no names, only how warm each guess was.
String shareText(int? day, List<Country> guesses, Country target) {
  final won = guesses.isNotEmpty && guesses.last == target;
  final lines = [
    'Pangea ${day == null ? '' : '#$day '}🔮 ${won ? guesses.length : 'X'}/$maxGuesses',
    for (final g in guesses)
      () {
        final w = warmth(g, target);
        final green = w ~/ 20, yellow = w % 20 >= 10 && w < 100 ? 1 : 0;
        final arrow = g == target ? '🎉' : arrowEmoji(bearing(g.lat, g.lon, target.lat, target.lon));
        return '${'🟩' * green}${'🟨' * yellow}${'⬜' * (5 - green - yellow)} $arrow';
      }(),
  ];
  return lines.join('\n');
}

/// Guess the country from its outline in six tries. [day] is the daily challenge; null is free play.
class GuessPage extends StatefulWidget {
  const GuessPage({super.key, this.day});
  final int? day;

  @override
  State<GuessPage> createState() => _GuessPageState();
}

class _GuessPageState extends State<GuessPage> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late Country _target;
  late List<Country> _guesses;
  var _shake = 0, _celebrate = false;

  bool get _won => _guesses.isNotEmpty && _guesses.last == _target;
  bool get _over => _won || _guesses.length >= maxGuesses;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _focus.addListener(() => setState(() {}));
    final day = widget.day;
    if (day != null) {
      _target = Store.dailyCountry(day);
      _guesses = [for (final id in Store.instance.dailyGuesses(day)) World.instance.byId[id]!];
    } else {
      _newGame();
    }
  }

  void _newGame() {
    final pool = World.instance.countries.where((c) => c.hasShape).toList();
    _target = Store.instance.pick('guess', pool, math.Random());
    _guesses = [];
    _celebrate = false;
    _input.clear();
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _submit(Country c) {
    if (_over) return;
    if (_guesses.contains(c)) {
      setState(() => _shake++);
      return;
    }
    _input.clear();
    setState(() => _guesses.add(c));
    final day = widget.day;
    if (_over) {
      Store.instance.record('guess', _target, _won);
      _focus.unfocus();
      _celebrate = _won;
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    if (day != null) Store.instance.saveDailyGuesses(day, [for (final g in _guesses) g.id], won: _over ? _won : null);
    // Bring the new row (or the ending card) into view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final day = widget.day;
    final query = _input.text;
    final suggestions = _over
        ? const <Country>[]
        : World.instance.search(query, limit: 12).where((c) => !_guesses.contains(c)).take(5).toList();
    final misses = _guesses.where((g) => g != _target).length;
    final typing = _focus.hasFocus && !_over;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                GameBar(
                  mode: Mode.daily,
                  title: day == null ? tr('Free play', 'Partie libre') : '${Mode.daily.title} #$day',
                  trailing: day == null ? null : Pill('🔥 ${Store.instance.streak}'),
                ),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    children: [
                      Shake(
                        trigger: _shake,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          // Smaller while typing, so the guesses so far stay in view above the keyboard.
                          height: typing ? 130 : 230,
                          decoration: BoxDecoration(
                            gradient: Mode.daily.gradient,
                            borderRadius: BorderRadius.circular(32),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Padding(padding: const EdgeInsets.all(22), child: ShapeView(_target)),
                              ),
                              if (misses >= 3 || _over)
                                Positioned(
                                  left: 14,
                                  bottom: 14,
                                  child: Pill(
                                    '${tr('Hint: ', 'Indice : ')}${_target.region?.emoji} ${_target.region?.label}',
                                    color: Colors.white.withValues(alpha: 0.9),
                                    textColor: Colors.black87,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (var i = 0; i < (typing ? _guesses.length : maxGuesses); i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: i < _guesses.length ? _GuessRow(_guesses[i], _target) : _EmptyRow(i + 1),
                        ),
                      if (_over) ...[const SizedBox(height: 8), _ending(context)],
                    ],
                  ),
                ),
                if (suggestions.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final c in suggestions)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Bouncy(
                              onTap: () => _submit(c),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  gradient: c == suggestions.first ? Mode.daily.gradient : null,
                                  color: cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  '${c.flag}  ${c.name}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: c == suggestions.first ? Colors.white : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (!_over)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (suggestions.isNotEmpty) _submit(suggestions.first);
                        _focus.requestFocus();
                      },
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        hintText: tr(
                          'Guess ${_guesses.length + 1} of $maxGuesses: a country…',
                          'Essai ${_guesses.length + 1} sur $maxGuesses : un pays…',
                        ),
                        prefixIcon: const Icon(Icons.travel_explore_rounded),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (_celebrate) const Positioned.fill(child: Confetti()),
          ],
        ),
      ),
    );
  }

  Widget _ending(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final day = widget.day;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _won
                ? tr('Found in ${_guesses.length}!', 'Trouvé en ${_guesses.length} !')
                : tr('So close… it was', 'Raté… c\'était'),
            textAlign: TextAlign.center,
            style: display(24),
          ),
          const SizedBox(height: 10),
          Bouncy(
            onTap: () => showCountry(context, _target),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_target.flag, style: const TextStyle(fontSize: 44)),
                const SizedBox(width: 12),
                Flexible(child: Text(_target.name, style: display(32))),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          if (day != null) ...[
            const SizedBox(height: 8),
            Text(
              tr(
                'Streak ${Store.instance.streak} 🔥 · best ${Store.instance.bestStreak} · ${Store.instance.dailyWon}/${Store.instance.dailyPlayed} won',
                'Série ${Store.instance.streak} 🔥 · record ${Store.instance.bestStreak} · ${Store.instance.dailyWon}/${Store.instance.dailyPlayed} gagnés',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (day != null) ...[
                Expanded(
                  child: BigButton(
                    tr('Share', 'Partager'),
                    icon: Icons.copy_rounded,
                    colors: Mode.daily.colors,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: shareText(day, _guesses, _target)));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr('Copied, paste it anywhere', 'Copié, colle-le où tu veux'))),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: BigButton(
                  tr('Free play', 'Partie libre'),
                  icon: Icons.shuffle_rounded,
                  colors: day == null ? Mode.daily.colors : Mode.shapes.colors,
                  onTap: () => day == null
                      ? setState(_newGame)
                      : Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const GuessPage())),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GuessRow extends StatelessWidget {
  const _GuessRow(this.guess, this.target);
  final Country guess, target;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final right = guess == target;
    final km = haversineKm(guess.lat, guess.lon, target.lat, target.lon);
    final w = warmth(guess, target);
    final color = heat(km);
    return TweenAnimationBuilder(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(
        scale: 0.8 + 0.2 * t,
        child: Opacity(opacity: t.clamp(0, 1), child: child),
      ),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: right ? good : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Text(guess.flag, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                guess.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: right ? Colors.white : null),
              ),
            ),
            if (!right) ...[
              Text(
                fmtKm(km),
                style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
              Transform.rotate(
                angle: bearing(guess.lat, guess.lon, target.lat, target.lon) * math.pi / 180,
                child: Icon(Icons.arrow_upward_rounded, color: color, size: 24),
              ),
              const SizedBox(width: 8),
            ],
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(color: right ? Colors.white : color, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: Text(right ? '🎉' : '$w%', style: display(16, color: right ? null : Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.n);
  final int n;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant, width: 2),
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: Text('$n', style: display(18, color: cs.outlineVariant)),
    );
  }
}
