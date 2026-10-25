import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'atlas.dart';
import 'guess.dart';
import 'map.dart';
import 'pin.dart';
import 'route.dart';
import 'rush.dart';
import 'settings.dart';
import 'store.dart';
import 'ui.dart';
import 'world.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Future.wait([World.load(), Store.load(), loadEarth()]);
  runApp(const PangeaApp());
}

/// Neutral surfaces with a violet tint; each game brings its own accent (`Mode.color`).
ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF6C4DFF), brightness: b).copyWith(
    surface: dark ? const Color(0xFF0E0D14) : const Color(0xFFF5F4F9),
    surfaceContainerLowest: dark ? const Color(0xFF17161F) : Colors.white,
    surfaceContainerHighest: dark ? const Color(0xFF24222E) : const Color(0xFFEBE9F1),
    outlineVariant: dark ? const Color(0xFF2B2936) : const Color(0xFFE4E1EB),
    onSurface: dark ? const Color(0xFFF2F1F7) : const Color(0xFF15131D),
    onSurfaceVariant: dark ? const Color(0xFF9C99AB) : const Color(0xFF6A6779),
  );
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'Jakarta',
    scaffoldBackgroundColor: scheme.surface,
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: scheme.surface),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}

class PangeaApp extends StatelessWidget {
  const PangeaApp({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Store.instance,
    builder: (context, _) => MaterialApp(
      title: 'Pangea',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: switch (Store.instance.theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      home: const Home(),
    ),
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
          return SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.only(top: 16, bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 20, right: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text('Pangea', style: display(34))),
                      Pill('${store.streak}', icon: Icons.local_fire_department_rounded),
                      const SizedBox(width: 6),
                      Pill('${store.known.length}/${World.instance.countries.length}', icon: Icons.public_rounded),
                      IconButton(
                        onPressed: () => _go(context, const SettingsPage()),
                        icon: const Icon(Icons.tune_rounded),
                        tooltip: tr('Settings', 'Réglages'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Text(
                    tr('How well do you know the world?', 'Tu connais vraiment le monde ?'),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _DailyCard(onTap: () => _go(context, GuessPage(day: Store.today()))),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                  child: Row(
                    children: [
                      Expanded(child: Text(tr('Play', 'Jouer'), style: display(20))),
                      Segmented(
                        values: Difficulty.values,
                        label: (d) => d.label,
                        selected: store.difficulty,
                        onChanged: (d) => store.difficulty = d,
                      ),
                    ],
                  ),
                ),
                RegionPicker(value: region, onChanged: (r) => store.region = r),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero, // or it adds the system bar's inset
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.02,
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
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _RouteTile(onTap: () => _go(context, RoutePage(region: region))),
                ),
                const SizedBox(height: 12),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final day = Store.today();
    final target = Store.dailyCountry(day);
    final guesses = Store.instance.dailyGuesses(day);
    final won = guesses.isNotEmpty && guesses.last == target.id;
    final done = won || guesses.length >= maxGuesses;
    final now = DateTime.now();
    final left = DateTime(now.year, now.month, now.day + 1).difference(now);
    final next = tr(
      'next in ${left.inHours} h ${left.inMinutes % 60}',
      'suivant dans ${left.inHours} h ${left.inMinutes % 60}',
    );
    final (icon, status) = !done
        ? (
            Icons.play_arrow_rounded,
            guesses.isEmpty
                ? tr('Play', 'Jouer')
                : tr('Continue · ${guesses.length}/$maxGuesses', 'Continuer · ${guesses.length}/$maxGuesses'),
          )
        : won
        ? (Icons.check_rounded, tr('Found in ${guesses.length} · $next', 'Trouvé en ${guesses.length} · $next'))
        : (Icons.close_rounded, tr('Missed · $next', 'Raté · $next'));
    const ink = Color(0xFF17142B);
    final base = dark ? const Color(0xFF1D1934) : ink;
    return Bouncy(
      onTap: onTap,
      child: Container(
        height: 184,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          // A soft light in the corner, in the game's accent.
          gradient: RadialGradient(
            center: const Alignment(0.95, -1),
            radius: 1.3,
            colors: [Color.alphaBlend(Mode.daily.color.withValues(alpha: 0.55), base), base],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: 18,
              top: 22,
              bottom: 22,
              width: 128,
              child: done
                  ? Center(child: Text(target.flag, style: const TextStyle(fontSize: 76)))
                  : ShapeView(target, color: Colors.white.withValues(alpha: 0.92)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 156, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${tr('DAILY', 'DU JOUR')}  ·  #$day',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(Mode.daily.title, style: display(25, color: Colors.white)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Mode.daily.hint,
                    maxLines: 2,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13.5, height: 1.3),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: ink),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, color: ink, fontSize: 13),
                          ),
                        ),
                      ],
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Bouncy(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: panel(context, color: tint(context, mode.color), border: mode.color.withValues(alpha: 0.16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ModeBadge(mode, size: 38),
            const Spacer(),
            Text(mode.title, style: display(18)),
            const SizedBox(height: 3),
            SizedBox(
              height: 34, // two lines, so titles line up whatever the hint's length
              child: Text(
                mode.hint,
                maxLines: 2,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.3, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(best == 0 ? Icons.arrow_forward_rounded : Icons.emoji_events_rounded, size: 16, color: mode.color),
                const SizedBox(width: 5),
                Text(
                  best == 0 ? tr('Start', 'Commencer') : fmtInt(best),
                  style: display(14, color: mode.color, weight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Road trip: wide, with its stats.
class _RouteTile extends StatelessWidget {
  const _RouteTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const mode = Mode.route;
    final store = Store.instance;
    return Bouncy(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: panel(context, color: tint(context, mode.color), border: mode.color.withValues(alpha: 0.16)),
        child: Row(
          children: [
            const ModeBadge(mode, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mode.title, style: display(18)),
                  Text(
                    mode.hint,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            if (store.tripsDone > 0) ...[
              Icon(Icons.emoji_events_rounded, size: 16, color: mode.color),
              const SizedBox(width: 4),
              Text(
                '${store.tripsPerfect}/${store.tripsDone}',
                style: display(14, color: mode.color, weight: FontWeight.w700),
              ),
            ] else
              Icon(Icons.arrow_forward_rounded, size: 18, color: mode.color),
          ],
        ),
      ),
    );
  }
}

class _AtlasTile extends StatelessWidget {
  const _AtlasTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final known = Store.instance.known;
    return Bouncy(
      onTap: onTap,
      child: Container(
        decoration: panel(context),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
              child: Row(
                children: [
                  const ModeBadge(Mode.atlas, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(Mode.atlas.title, style: display(18)),
                        Text(
                          Mode.atlas.hint,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${known.length}/${World.instance.countries.length}',
                    style: display(15, color: cs.onSurfaceVariant, weight: FontWeight.w700),
                  ),
                  Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                ],
              ),
            ),
            SizedBox(
              height: 150,
              child: IgnorePointer(child: WorldMap(fill: (c) => foundFill(c, known), dots: false)),
            ),
          ],
        ),
      ),
    );
  }
}
