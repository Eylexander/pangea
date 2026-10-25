import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'map.dart';
import 'store.dart';
import 'world.dart';

const good = Color(0xFF20C065);
const bad = Color(0xFFFF4D6A);

enum Mode {
  flags('🚩', 'Flags', 'Drapeaux', 'Which country flies this flag?', 'À quel pays est ce drapeau ?', [
    Color(0xFFFF5F6D),
    Color(0xFFFFA14A),
  ]),
  capitals('🏛️', 'Capitals', 'Capitales', 'Find the capital city', 'Trouve la capitale', [
    Color(0xFF7B5CFF),
    Color(0xFFC86BFA),
  ]),
  shapes('🧩', 'Shapes', 'Silhouettes', 'Recognize the outline', 'Reconnais la silhouette', [
    Color(0xFF00B37E),
    Color(0xFF16D9C9),
  ]),
  pin('📍', 'Pin it', 'Épingle', 'Put it on the map', 'Place-le sur la carte', [Color(0xFF2F6BFF), Color(0xFF22C3FF)]),
  daily('🔮', 'Mystery country', 'Pays mystère', 'Six guesses, warmer or colder', 'Six essais, chaud ou froid', [
    Color(0xFFFF3D9A),
    Color(0xFF7B4DFF),
  ]),
  atlas('🧭', 'Atlas', 'Atlas', 'Explore and fill in your world', 'Explore et colorie ton monde', [
    Color(0xFFFFB020),
    Color(0xFFFF6B2C),
  ]);

  const Mode(this.emoji, this.en, this.french, this.hintEn, this.hintFr, this.colors);
  final String emoji, en, french, hintEn, hintFr;
  final List<Color> colors;

  String get title => tr(en, french);
  String get hint => tr(hintEn, hintFr);
  LinearGradient get gradient => LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight);
}

TextStyle display(double size, {Color? color}) =>
    TextStyle(fontFamily: 'Lilita', fontSize: size, height: 1.1, color: color, letterSpacing: 0.3);

String fmtInt(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(fr ? ' ' : ','); // Lilita has no narrow no-break space
    b.write(s[i]);
  }
  return b.toString();
}

String fmtPopulation(int n) {
  String dec(double v) => (v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)).replaceAll('.', fr ? ',' : '.');
  if (n >= 1e9) return '${dec(n / 1e9)} ${tr('billion', 'Md')}';
  if (n >= 1e6) return '${dec(n / 1e6)} ${tr('million', 'M')}';
  return fmtInt(n);
}

String fmtKm(double km) => '${fmtInt(km.round())} km';

/// Shrinks a little while pressed.
class Bouncy extends StatefulWidget {
  const Bouncy({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<Bouncy> createState() => _BouncyState();
}

class _BouncyState extends State<Bouncy> {
  var _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
    onTapCancel: () => setState(() => _down = false),
    onTapUp: (_) => setState(() => _down = false),
    onTap: widget.onTap == null
        ? null
        : () {
            HapticFeedback.selectionClick();
            widget.onTap!();
          },
    child: AnimatedScale(
      scale: _down ? 0.95 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: widget.child,
    ),
  );
}

/// Shakes sideways each time [trigger] changes.
class Shake extends StatefulWidget {
  const Shake({super.key, required this.trigger, required this.child});
  final int trigger;
  final Widget child;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void didUpdateWidget(Shake old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) =>
        Transform.translate(offset: Offset(math.sin(_c.value * math.pi * 6) * 12 * (1 - _c.value), 0), child: child),
    child: widget.child,
  );
}

/// A burst of confetti falling over its parent, once per new [key].
class Confetti extends StatefulWidget {
  const Confetti({super.key});

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();
  final _rnd = math.Random();
  late final _bits = List.generate(90, (_) {
    final colors = [for (final m in Mode.values) ...m.colors];
    return (
      x: _rnd.nextDouble(),
      vx: (_rnd.nextDouble() - 0.5) * 0.6,
      vy: 0.6 + _rnd.nextDouble() * 0.9,
      delay: _rnd.nextDouble() * 0.25,
      spin: (_rnd.nextDouble() - 0.5) * 20,
      size: 6 + _rnd.nextDouble() * 7,
      color: colors[_rnd.nextInt(colors.length)],
    );
  });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(size: Size.infinite, painter: _ConfettiPainter(_bits, _c.value)),
    ),
  );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t);
  final List<({double x, double vx, double vy, double delay, double spin, double size, Color color})> bits;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bits) {
      final u = ((t - b.delay) / (1 - b.delay)).clamp(0.0, 1.0);
      if (u == 0 || u == 1) continue;
      final x = (b.x + b.vx * u) * size.width;
      final y = -20 + (b.vy * u + 0.9 * u * u) * size.height;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(b.spin * u);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * 0.55),
        Paint()..color = b.color.withValues(alpha: u > 0.8 ? (1 - u) * 5 : 1),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.textColor});
  final String text;
  final Color? color, textColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color ?? cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(99)),
      child: Text(
        text,
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: textColor ?? cs.onSurface),
      ),
    );
  }
}

/// Region chips: the world or one continent.
class RegionPicker extends StatelessWidget {
  const RegionPicker({super.key, required this.value, required this.onChanged});
  final Region? value;
  final ValueChanged<Region?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget chip(Region? r) {
      final on = r == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Bouncy(
          onTap: () => onChanged(r),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: on ? cs.onSurface : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '${r?.emoji ?? '🗺️'}  ${r?.label ?? tr('World', 'Monde')}',
              style: TextStyle(fontWeight: FontWeight.w800, color: on ? cs.surface : cs.onSurface),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [chip(null), for (final r in Region.values) chip(r)]),
    );
  }
}

/// Everything about one country, for learning: flag, names, capital, figures, outline.
Future<void> showCountry(BuildContext context, Country c) => showModalBottomSheet(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => CountryCard(c),
);

class CountryCard extends StatelessWidget {
  const CountryCard(this.c, {super.key});
  final Country c;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final known = Store.instance.known.contains(c.id);
    Widget fact(String emoji, String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$emoji  $label', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(value, style: display(18)),
          ],
        ),
      ),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(c.quiz ? c.flag : '🏳️', style: const TextStyle(fontSize: 64)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: display(30)),
                      if (c.otherName != c.name)
                        Text(c.otherName, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
                      const SizedBox(height: 6),
                      if (c.quiz)
                        Pill(
                          known ? tr('✓ Known', '✓ Connu') : tr('Not found yet', 'Pas encore trouvé'),
                          color: known ? good.withValues(alpha: 0.18) : null,
                          textColor: known ? good : null,
                        ),
                    ],
                  ),
                ),
                if (c.hasShape)
                  SizedBox(width: 84, height: 84, child: ShapeView(c, colors: Mode.atlas.colors, glow: false)),
              ],
            ),
            if (c.quiz) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  fact('🏛️', tr('Capital', 'Capitale'), c.capital),
                  const SizedBox(width: 10),
                  fact(c.region?.emoji ?? '🌐', tr('Region', 'Région'), c.region?.label ?? '—'),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  fact('👥', tr('Population', 'Population'), fmtPopulation(c.population)),
                  const SizedBox(width: 10),
                  fact('📐', tr('Area', 'Superficie'), c.area < 1 ? '< 1 km²' : '${fmtInt(c.area)} km²'),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  tr('A territory, not part of the game.', 'Un territoire, hors du jeu.'),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A big gradient button.
class BigButton extends StatelessWidget {
  const BigButton(this.label, {super.key, required this.onTap, required this.colors, this.icon});
  final String label;
  final VoidCallback? onTap;
  final List<Color> colors;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // Disabled: solid and readable, even floating over the map.
    final cs = Theme.of(context).colorScheme;
    final on = onTap != null;
    final fg = on ? Colors.white : cs.onSurfaceVariant;
    return Bouncy(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 58,
        decoration: BoxDecoration(
          gradient: on ? LinearGradient(colors: colors) : null,
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: on ? colors.last.withValues(alpha: 0.35) : Colors.black26,
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, color: fg), const SizedBox(width: 8)],
            Text(label, style: display(22, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// End of a game: score, record, and the countries to review.
class Results extends StatelessWidget {
  const Results({
    super.key,
    required this.mode,
    required this.title,
    required this.score,
    required this.record,
    required this.best,
    required this.summary,
    required this.mistakes,
    required this.onAgain,
  });

  final Mode mode;
  final String title, summary;
  final int score, best;
  final bool record;
  final List<Country> mistakes;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text(title, textAlign: TextAlign.center, style: display(30)),
            const SizedBox(height: 16),
            TweenAnimationBuilder(
              tween: IntTween(begin: 0, end: score),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => ShaderMask(
                shaderCallback: (r) => mode.gradient.createShader(r),
                child: Text(
                  fmtInt(v),
                  textAlign: TextAlign.center,
                  style: display(84, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: record
                  ? Pill(
                      tr('🏆 New record!', '🏆 Nouveau record !'),
                      color: const Color(0xFFFFD34D),
                      textColor: Colors.black,
                    )
                  : Pill('${tr('Record', 'Record')} ${fmtInt(best)}'),
            ),
            const SizedBox(height: 12),
            Text(
              summary,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: BigButton(
                    tr('Again', 'Rejouer'),
                    icon: Icons.replay_rounded,
                    onTap: onAgain,
                    colors: mode.colors,
                  ),
                ),
                const SizedBox(width: 12),
                Bouncy(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    height: 58,
                    width: 58,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.home_rounded),
                  ),
                ),
              ],
            ),
            if (mistakes.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text(tr('To review', 'À revoir'), style: display(22)),
              const SizedBox(height: 8),
              for (final c in mistakes)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  color: cs.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: ListTile(
                    onTap: () => showCountry(context, c),
                    leading: Text(c.flag, style: const TextStyle(fontSize: 32)),
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${tr('Capital: ', 'Capitale : ')}${c.capital}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
                ),
            ],
          ],
        ),
        if (record) const Positioned.fill(child: Confetti()),
      ],
    );
  }
}

/// Close button + title used at the top of every game.
class GameBar extends StatelessWidget {
  const GameBar({super.key, required this.mode, this.trailing, this.title});
  final Mode mode;
  final Widget? trailing;
  final String? title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.close_rounded),
          tooltip: tr('Quit', 'Quitter'),
        ),
        Text(mode.emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title ?? mode.title, style: display(22), overflow: TextOverflow.ellipsis),
        ),
        ?trailing,
      ],
    ),
  );
}
