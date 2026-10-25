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
  // Deep enough tones to read as text on a light tint.
  return t < 0.5
      ? Color.lerp(const Color(0xFF3B74E8), const Color(0xFFE38A00), t * 2)!
      : Color.lerp(const Color(0xFFE38A00), const Color(0xFFE5484D), t * 2 - 1)!;
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
    final typing = !_over && MediaQuery.viewInsetsOf(context).bottom > 0; // keyboard up
    const accent = Color(0xFFE5438A);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                GameBar(
                  title: day == null ? tr('Free play', 'Partie libre') : Mode.daily.title,
                  subtitle: day == null ? Mode.daily.title : '${tr('Daily', 'Du jour')} · #$day',
                  trailing: day == null
                      ? null
                      : Pill('${Store.instance.streak}', icon: Icons.local_fire_department_rounded),
                ),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                    children: [
                      Shake(
                        trigger: _shake,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          // Smaller while typing, so the guesses so far stay in view above the keyboard.
                          height: typing ? 130 : 220,
                          decoration: panel(context, radius: 28),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.all(26),
                                  child: ShapeView(_target, color: accent),
                                ),
                              ),
                              if (misses >= 3 || _over)
                                Positioned(
                                  left: 12,
                                  bottom: 12,
                                  child: Pill(
                                    '${tr('Hint: ', 'Indice : ')}${_target.region?.label}',
                                    icon: Icons.lightbulb_rounded,
                                    color: tint(context, accent, 0.14),
                                    textColor: accent,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (var i = 0; i < (typing ? _guesses.length : maxGuesses); i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: i < _guesses.length ? _GuessRow(_guesses[i], _target) : _EmptyRow(i + 1),
                        ),
                      if (_over) ...[const SizedBox(height: 6), _ending(context)],
                    ],
                  ),
                ),
                if (suggestions.isNotEmpty)
                  SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final c in suggestions)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Bouncy(
                              onTap: () => _submit(c),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                alignment: Alignment.center,
                                decoration: c == suggestions.first
                                    ? BoxDecoration(color: accent, borderRadius: BorderRadius.circular(99))
                                    : panel(context, radius: 99),
                                child: Text(
                                  '${c.flag}  ${c.name}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5,
                                    color: c == suggestions.first ? Colors.white : cs.onSurface,
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
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
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
                      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
                      decoration: fieldDecoration(
                        context,
                        tr(
                          'Guess ${_guesses.length + 1} of $maxGuesses: a country',
                          'Essai ${_guesses.length + 1} sur $maxGuesses : un pays',
                        ),
                        Icons.search_rounded,
                        accent: accent,
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
    final store = Store.instance;
    Widget stat(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(value, style: display(22)),
          Text(
            label,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: panel(context, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _won ? tr('Found in ${_guesses.length}', 'Trouvé en ${_guesses.length}') : tr('It was', 'C\'était'),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Bouncy(
            onTap: () => showCountry(context, _target),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_target.flag, style: const TextStyle(fontSize: 36)),
                const SizedBox(width: 10),
                Flexible(child: Text(_target.name, style: display(26))),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
          if (day != null) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: cs.outlineVariant),
            const SizedBox(height: 14),
            Row(
              children: [
                stat('${store.streak}', tr('Streak', 'Série')),
                stat('${store.bestStreak}', tr('Best', 'Record')),
                stat('${store.dailyWon}/${store.dailyPlayed}', tr('Won', 'Gagnés')),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (day != null) ...[
                Expanded(
                  child: BigButton(
                    tr('Share', 'Partager'),
                    icon: Icons.ios_share_rounded,
                    color: Mode.daily.color,
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
                  color: cs.onSurface,
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
    final color = right ? good : heat(km);
    return TweenAnimationBuilder(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: Container(
        height: 52,
        padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
        decoration: right
            ? panel(context, radius: 16, color: tint(context, good, 0.12), border: good)
            : panel(context, radius: 16),
        child: Row(
          children: [
            Text(guess.flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                guess.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: right ? good : null),
              ),
            ),
            if (!right) ...[
              Text(
                fmtKm(km),
                style: display(13.5, color: cs.onSurfaceVariant, weight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Transform.rotate(
                angle: bearing(guess.lat, guess.lon, target.lat, target.lon) * math.pi / 180,
                child: Icon(Icons.arrow_upward_rounded, color: color, size: 20),
              ),
              const SizedBox(width: 6),
            ],
            Container(
              width: 54,
              height: 38,
              decoration: BoxDecoration(color: tint(context, color, 0.16), borderRadius: BorderRadius.circular(11)),
              alignment: Alignment.center,
              child: right
                  ? const Icon(Icons.check_rounded, color: good)
                  : Text('$w%', style: display(14, color: color)),
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
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Text(
        '$n',
        style: display(15, color: cs.onSurfaceVariant.withValues(alpha: 0.6), weight: FontWeight.w700),
      ),
    );
  }
}
