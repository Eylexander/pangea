import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'map.dart';
import 'store.dart';
import 'world.dart';

const good = Color(0xFF16A36A);
const bad = Color(0xFFE5484D);

enum Mode {
  flags(Icons.flag_rounded, 'Flags', 'Drapeaux', 'Which country flies it?', 'À quel pays est-il ?', Color(0xFFFF5B4A)),
  capitals(
    Icons.location_city_rounded,
    'Capitals',
    'Capitales',
    'Name the capital city',
    'Trouve la capitale',
    Color(0xFF7B5CFF),
  ),
  shapes(
    Icons.pentagon_rounded,
    'Shapes',
    'Silhouettes',
    'Know it by its outline',
    'Reconnais la silhouette',
    Color(0xFF0FA97A),
  ),
  route(
    Icons.alt_route_rounded,
    'Road trip',
    'Road trip',
    'Cross borders from A to B',
    'Passe les frontières de A à B',
    Color(0xFF0B9DB8),
  ),
  pin(Icons.place_rounded, 'Pin it', 'Épingle', 'Find it on a blank map', 'Place-le sur la carte', Color(0xFF2F7BFF)),
  daily(
    Icons.auto_awesome_rounded,
    'Mystery country',
    'Pays mystère',
    'Six guesses, warmer or colder',
    'Six essais, chaud ou froid',
    Color(0xFFE5438A),
  ),
  atlas(
    Icons.public_rounded,
    'Atlas',
    'Atlas',
    'Explore and fill in your map',
    'Explore et colorie ta carte',
    Color(0xFFF29D0C),
  );

  const Mode(this.icon, this.en, this.french, this.hintEn, this.hintFr, this.color);
  final IconData icon;
  final String en, french, hintEn, hintFr;
  final Color color;

  String get title => tr(en, french);
  String get hint => tr(hintEn, hintFr);
}

/// Big titles and numbers: extra bold with tight tracking.
TextStyle display(double size, {Color? color, FontWeight weight = FontWeight.w800}) => TextStyle(
  fontSize: size,
  fontWeight: weight,
  height: 1.12,
  letterSpacing: -size * 0.025,
  color: color,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// A card: the raised surface with a hairline border, no shadow.
BoxDecoration panel(BuildContext context, {Color? color, double radius = 22, Color? border}) {
  final cs = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: color ?? cs.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border ?? cs.outlineVariant),
  );
}

/// A card floating over the map: the panel plus a soft, neutral elevation shadow.
BoxDecoration floating(BuildContext context, {double radius = 24}) => panel(context, radius: radius).copyWith(
  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 24, offset: const Offset(0, 8))],
);

/// Text fields: the card surface with a hairline border, accent border when focused.
InputDecoration fieldDecoration(BuildContext context, String hint, IconData icon, {Color? accent}) {
  final cs = Theme.of(context).colorScheme;
  OutlineInputBorder outline(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
    prefixIcon: Icon(icon, color: cs.onSurfaceVariant),
    filled: true,
    fillColor: cs.surfaceContainerLowest,
    enabledBorder: outline(cs.outlineVariant),
    focusedBorder: outline(accent ?? cs.onSurface, 1.5),
  );
}

/// [accent] washed over the card color, for tinted surfaces.
Color tint(BuildContext context, Color accent, [double? amount]) {
  final cs = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return Color.alphaBlend(accent.withValues(alpha: amount ?? (dark ? 0.16 : 0.10)), cs.surfaceContainerLowest);
}

String fmtInt(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(fr ? ' ' : ',');
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
      scale: _down ? 0.97 : 1,
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
  void didUpdateWidget(Shake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger) _c.forward(from: 0);
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
        Transform.translate(offset: Offset(math.sin(_c.value * math.pi * 6) * 10 * (1 - _c.value), 0), child: child),
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
  late final _bits = List.generate(80, (_) {
    return (
      x: _rnd.nextDouble(),
      vx: (_rnd.nextDouble() - 0.5) * 0.6,
      vy: 0.6 + _rnd.nextDouble() * 0.9,
      delay: _rnd.nextDouble() * 0.25,
      spin: (_rnd.nextDouble() - 0.5) * 20,
      size: 6 + _rnd.nextDouble() * 6,
      color: Mode.values[_rnd.nextInt(Mode.values.length)].color,
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
      canvas.save();
      canvas.translate((b.x + b.vx * u) * size.width, -20 + (b.vy * u + 0.9 * u * u) * size.height);
      canvas.rotate(b.spin * u);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * 0.5),
          const Radius.circular(1.5),
        ),
        Paint()..color = b.color.withValues(alpha: u > 0.8 ? (1 - u) * 5 : 1),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// A small rounded label, optionally with an icon.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.icon, this.color, this.textColor, this.border = true});
  final String text;
  final IconData? icon;
  final Color? color, textColor;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = textColor ?? cs.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color ?? cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(99),
        border: border && color == null ? Border.all(color: cs.outlineVariant) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 5)],
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: fg,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded square with an icon in it, the mark of each game.
class ModeBadge extends StatelessWidget {
  const ModeBadge(this.mode, {super.key, this.size = 40});
  final Mode mode;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: mode.color, borderRadius: BorderRadius.circular(size * 0.32)),
    child: Icon(mode.icon, color: Colors.white, size: size * 0.55),
  );
}

/// Region chips: the world or one continent.
class RegionPicker extends StatelessWidget {
  const RegionPicker({super.key, required this.value, required this.onChanged, this.padding = 20});
  final Region? value;
  final ValueChanged<Region?> onChanged;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget chip(Region? r) {
      final on = r == value;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Bouncy(
          onTap: () => onChanged(r),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: on ? cs.onSurface : cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: on ? cs.onSurface : cs.outlineVariant),
            ),
            child: Text(
              r?.label ?? tr('World', 'Monde'),
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: on ? cs.surface : cs.onSurface),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: padding),
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
    Widget fact(IconData icon, String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: panel(context, radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(value, style: display(18, weight: FontWeight.w700)),
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
                if (c.quiz) Text(c.flag, style: const TextStyle(fontSize: 52)),
                if (c.quiz) const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: display(28)),
                      if (c.otherName != c.name)
                        Text(c.otherName, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
                      if (c.quiz) ...[
                        const SizedBox(height: 8),
                        Pill(
                          known ? tr('Found', 'Trouvé') : tr('Not found yet', 'Pas encore trouvé'),
                          icon: known ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          color: known ? tint(context, good, 0.14) : null,
                          textColor: known ? good : cs.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                ),
                if (c.hasShape) SizedBox(width: 80, height: 80, child: ShapeView(c, color: Mode.atlas.color)),
              ],
            ),
            if (c.quiz) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  fact(Icons.location_city_rounded, tr('Capital', 'Capitale'), c.capital),
                  const SizedBox(width: 10),
                  fact(Icons.public_rounded, tr('Region', 'Région'), c.region?.label ?? '—'),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  fact(Icons.groups_rounded, tr('Population', 'Population'), fmtPopulation(c.population)),
                  const SizedBox(width: 10),
                  fact(
                    Icons.straighten_rounded,
                    tr('Area', 'Superficie'),
                    c.area < 1 ? '< 1 km²' : '${fmtInt(c.area)} km²',
                  ),
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

/// The main button: solid accent. Disabled, it turns into a plain gray surface that stays readable over a map.
class BigButton extends StatelessWidget {
  const BigButton(this.label, {super.key, required this.onTap, required this.color, this.icon});
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = onTap != null;
    // Text that contrasts with the button, whatever its color: a light button (the "ink" one in dark mode) gets dark
    // text.
    final light = ThemeData.estimateBrightnessForColor(color) == Brightness.light;
    final fg = !on ? cs.onSurfaceVariant : (light ? const Color(0xFF15131D) : Colors.white);
    return Bouncy(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 56,
        decoration: BoxDecoration(
          color: on ? color : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, color: fg, size: 20), const SizedBox(width: 8)],
            Text(
              label,
              style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 16.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// A square button with an icon, on the card surface.
class IconSquare extends StatelessWidget {
  const IconSquare(this.icon, {super.key, required this.onTap, this.size = 56, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: Bouncy(
      onTap: onTap,
      child: Container(width: size, height: size, decoration: panel(context, radius: 18), child: Icon(icon)),
    ),
  );
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
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(title, textAlign: TextAlign.center, style: display(26)),
            const SizedBox(height: 10),
            TweenAnimationBuilder(
              tween: IntTween(begin: 0, end: score),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text(
                fmtInt(v),
                textAlign: TextAlign.center,
                style: display(80, color: mode.color),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: record
                  ? Pill(
                      tr('New record', 'Nouveau record'),
                      icon: Icons.emoji_events_rounded,
                      color: tint(context, const Color(0xFFF29D0C), 0.18),
                      textColor: const Color(0xFFB86E00),
                    )
                  : Pill('${tr('Best', 'Record')} ${fmtInt(best)}', icon: Icons.emoji_events_outlined),
            ),
            const SizedBox(height: 14),
            Text(
              summary,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: BigButton(
                    tr('Play again', 'Rejouer'),
                    icon: Icons.replay_rounded,
                    onTap: onAgain,
                    color: mode.color,
                  ),
                ),
                const SizedBox(width: 10),
                IconSquare(Icons.home_rounded, tooltip: tr('Home', 'Accueil'), onTap: () => Navigator.pop(context)),
              ],
            ),
            if (mistakes.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text(tr('To review', 'À revoir'), style: display(20)),
              const SizedBox(height: 10),
              Container(
                decoration: panel(context),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, c) in mistakes.indexed) ...[
                      if (i > 0) Divider(height: 1, color: cs.outlineVariant),
                      ListTile(
                        onTap: () => showCountry(context, c),
                        leading: Text(c.flag, style: const TextStyle(fontSize: 28)),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${tr('Capital: ', 'Capitale : ')}${c.capital}'),
                        trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
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
  const GameBar({super.key, this.trailing, required this.title, this.subtitle});
  final Widget? trailing;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.close_rounded),
            tooltip: tr('Quit', 'Quitter'),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: display(19), overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A row of mutually exclusive options; the chosen one is inked.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.values,
    required this.label,
    required this.selected,
    required this.onChanged,
  });
  final List<T> values;
  final String Function(T) label;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: panel(context, radius: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in values)
            Flexible(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(v);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == selected ? cs.onSurface : null,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    label(v),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: v == selected ? cs.surface : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
