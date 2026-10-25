import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'atlas.dart';
import 'guess.dart';
import 'map.dart';
import 'pin.dart';
import 'rush.dart';
import 'store.dart';
import 'ui.dart';
import 'world.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Future.wait([World.load(), Store.load()]);
  runApp(const PangeaApp());
}

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6C4DFF),
    brightness: b,
    dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
  ).copyWith(surface: dark ? const Color(0xFF13112B) : const Color(0xFFFAF8FF));
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

class PangeaApp extends StatelessWidget {
  const PangeaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pangea',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const Home(),
  );
}

class Home extends StatelessWidget {
  const Home({super.key});

  void _go(BuildContext context, Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final store = Store.instance;
    return Scaffold(
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final region = store.region;
          final known = store.known.length;
          return SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: ShaderMask(
                          shaderCallback: (r) =>
                              const LinearGradient(colors: [Color(0xFFFF3D9A), Color(0xFF7B4DFF), Color(0xFF22C3FF)])
                                  .createShader(r),
                          child: Text('Pangea', style: display(48, color: Colors.white)),
                        ),
                      ),
                      Pill('🔥 ${store.streak}'),
                      const SizedBox(width: 6),
                      Pill('🌍 $known/${World.instance.countries.length}'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
                  child: Text(
                    tr('How well do you know the world?', 'Tu connais vraiment le monde ?'),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _DailyCard(onTap: () => _go(context, GuessPage(day: Store.today()))),
                ),
                const SizedBox(height: 26),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(tr('Play', 'Jouer'), style: display(26)),
                ),
                RegionPicker(value: region, onChanged: (r) => store.region = r),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.92,
                    children: [
                      for (final m in [Mode.flags, Mode.capitals, Mode.shapes, Mode.pin])
                        _ModeTile(
                          mode: m,
                          best: store.best(m.name, region),
                          onTap: () =>
                              _go(context, m == Mode.pin ? PinPage(region: region) : RushPage(mode: m, region: region)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _AtlasTile(onTap: () => _go(context, const AtlasPage())),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DailyCard extends StatelessWidget {
  const _DailyCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final day = Store.today();
    final target = Store.dailyCountry(day);
    final guesses = Store.instance.dailyGuesses(day);
    final won = guesses.isNotEmpty && guesses.last == target.id;
    final done = won || guesses.length >= maxGuesses;
    final now = DateTime.now();
    final left = DateTime(now.year, now.month, now.day + 1).difference(now);
    final next = tr(
      'next in ${left.inHours} h ${left.inMinutes % 60} min',
      'suivant dans ${left.inHours} h ${left.inMinutes % 60}',
    );
    final status = !done
        ? (guesses.isEmpty
              ? tr('▶  Play today\'s', '▶  Jouer celui du jour')
              : tr('▶  ${guesses.length}/$maxGuesses, keep going', '▶  ${guesses.length}/$maxGuesses, continue'))
        : won
        ? tr('✓ Found in ${guesses.length} · $next', '✓ Trouvé en ${guesses.length} · $next')
        : tr('✗ Missed · $next', '✗ Raté · $next');
    return Bouncy(
      onTap: onTap,
      child: Container(
        height: 176,
        decoration: BoxDecoration(
          gradient: Mode.daily.gradient,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Mode.daily.colors.last.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: 12,
              top: 16,
              bottom: 16,
              width: 130,
              child: done
                  ? Center(child: Text(target.flag, style: const TextStyle(fontSize: 84)))
                  : ShapeView(target, colors: [Colors.white, Colors.white.withValues(alpha: 0.8)]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 146, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${Mode.daily.emoji}  #$day', style: display(18, color: Colors.white70)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(Mode.daily.title, style: display(28, color: Colors.white)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Mode.daily.hint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, height: 1.2),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99)),
                    child: Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, color: Mode.daily.colors.last, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.mode, required this.best, required this.onTap});
  final Mode mode;
  final int best;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Bouncy(
    onTap: onTap,
    child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: mode.gradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: mode.colors.last.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            bottom: -22,
            child: Transform.rotate(
              angle: -0.25,
              child: Opacity(opacity: 0.22, child: Text(mode.emoji, style: const TextStyle(fontSize: 96))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), shape: BoxShape.circle),
                  child: Text(mode.emoji, style: const TextStyle(fontSize: 26)),
                ),
                const Spacer(),
                Text(mode.title, style: display(24, color: Colors.white)),
                const SizedBox(height: 2),
                SizedBox(
                  height: 34, // two lines, so titles line up whatever the hint's length
                  child: Text(
                    mode.hint,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13, height: 1.2),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  best == 0 ? tr('New!', 'À toi de jouer !') : '🏆 ${fmtInt(best)}',
                  style: display(16, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _AtlasTile extends StatelessWidget {
  const _AtlasTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final known = Store.instance.known;
    return Bouncy(
      onTap: onTap,
      child: Container(
        height: 190,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: Mode.atlas.gradient,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(color: Mode.atlas.colors.last.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: Row(
                children: [
                  Text('${Mode.atlas.emoji}  ${Mode.atlas.title}', style: display(24, color: Colors.white)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      Mode.atlas.hint,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
                child: IgnorePointer(child: WorldMap(fill: (c) => knownFill(c, brightness, known))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
