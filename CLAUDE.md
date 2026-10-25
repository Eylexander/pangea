# CLAUDE.md

Pangea: a geography game for Android (Flutter, plus a one-method Kotlin channel for the version). Written for the
user, who likes testing and learning geography. They asked for something fun with a vibrant UI, then (after v1.0.0)
for a modern one: the first look (Lilita One, rainbow map, colored glows) was "fun but not modern", and (after v1.1.0)
for a map that looks like the Earth rather than a map. See Design. English or French: the phone's language, or the
one picked in Settings (`language`/`tr()` in `lib/world.dart`). Offline, no network permission.

## Toolchain

Same as Sablier and LLLearner: Flutter 3.47.7 (`~/SDKs/flutter-3.47.7`), Android SDK in `%LOCALAPPDATA%/Android/Sdk`
(AVD `Medium_Phone_API_36.0`), Android Studio's JDK:

```sh
export PATH=~/SDKs/flutter-3.47.7/bin:$LOCALAPPDATA/Android/Sdk/platform-tools:$PATH \
  ANDROID_HOME=$LOCALAPPDATA/Android/Sdk JAVA_HOME="$LOCALAPPDATA/Programs/Android Studio/jbr"
flutter analyze && flutter test                              # test/world_test.dart: geo math, search, borders, trips
dart format -l 120 lib test                                  # 120-col lines
flutter build apk --debug --target-platform android-x64      # emulator; package com.eylexander.pangea.debug
flutter build apk --release --target-platform android-arm64  # ~19 MB
python tool/build_world.py <dir>                             # assets/world.json (see Data)
python tool/build_earth.py <dir>                             # assets/earth.jpg; needs numpy and Pillow
```

numpy and Pillow aren't installed system-wide: use a throwaway venv (`python -m venv …; pip install numpy pillow`).

## Releasing (same scheme as the other apps of `../fdroid`)

- Package `com.eylexander.pangea`, GitHub `Eylexander/pangea`, listing in
  `../fdroid/metadata/com.eylexander.pangea/{en-US,fr-FR}/`. Push a `v*` tag: `.github/workflows/release.yml` calls
  the shared `Eylexander/fdroid/.github/workflows/flutter-apk.yml` (versionCode = run number, so keep the file's name).
- **Release notes are written by hand**, the user asked for releases that read as human-made: short, plain, first
  person, no emoji headers or "What's Changed" lists. The shared workflow generates notes; replace them right after
  with `gh release edit vX.Y.Z -R Eylexander/pangea --notes-file …`. The F-Droid listing also keeps a changelog per
  version, same tone (`../fdroid/metadata/com.eylexander.pangea/<locale>/changelogs/<versionCode>.txt`, versionCode
  = the release run's number: v1.0.0 = 1, v1.1.0 = 2, v1.2.0 = 3), but F-Droid clients don't show them for this
  repo; see `../fdroid/CLAUDE.md`.
- Keep `version:` in pubspec.yaml in step with the tag (CI overrides it, but debug builds show it in Settings).
- Release key: `.secrets/` (git-ignored), the shared key, SHA-256 `db171ead…`. CI gets it from the
  `RELEASE_KEYSTORE_BASE64` / `RELEASE_KEYSTORE_PASS` secrets. Never regenerate or lose it.
- Launcher icon: adaptive vector only (`res/drawable/ic_launcher_*.xml`: a globe with a yellow pin on a
  pink-violet-blue gradient), same paths in `tool/icon.svg` for the store PNG. minSdk 26 because there is no PNG
  fallback. `rsvg-convert` isn't installed here: render the SVG with the `@resvg/resvg-js` npm package.

## Data

`tool/build_world.py` → `assets/world.json` (700 KB):

- Natural Earth 10m admin-0 countries (public domain). 250 map units; 197 are played (`q: 1`): UN members plus
  Vatican, Palestine, Kosovo, Taiwan. Somaliland and Northern Cyprus are merged into Somalia and Cyprus (`MERGE`).
  Territories (Greenland, Puerto Rico…) can't be answered. Antarctica is left out.
- Names: Natural Earth's `NAME_EN`/`NAME_FR`, with overrides and typing aliases in `COUNTRIES` (the script asserts
  that table has exactly the played countries). Capitals in both languages are hand-written there.
- Rings are Douglas-Peucker simplified (tolerance scales with the country's size), quantized to 0.001° and
  delta-encoded. Specks of islands next to big countries are dropped. Polygons are sorted so the first `main` are the
  silhouette: the biggest one plus those big or close to it (Corsica in, French Guiana out; longitudes taken around
  the biggest so Chukotka stays with Russia).
- `nb`: land neighbors, from the full-resolution outlines (neighbors share border vertices; holes count, so Lesotho
  borders South Africa). Western Sahara isn't played but is crossed (`PASS_THROUGH`): Morocco borders Mauritania.
  French Guiana makes France border Brazil and Suriname; Ceuta and Melilla make Spain border Morocco.
- `lv`: difficulty level. Score = log10(population) + 0.6·log10(area), +0.7 in Europe and the Americas, −1.5 for small
  island states, +2 for the `FAMOUS` list. Top 70 = 1 (Easy), next 75 = 2 (Normal), last 52 = 3 (Hard only).
- `area` is computed (km²), `pop` is Natural Earth's estimate, `lx/ly` its label point: used for distances and
  directions in the mystery game, and for the rings of tiny countries.

`tool/build_earth.py` → `assets/earth.jpg` (4096×1791, 900 KB): NASA Blue Marble Next Generation, July 2004, with
topography and bathymetry (public domain), reprojected to Equal Earth over exactly `EqualEarth.world` (84 N to
58 S). Corners outside the Earth are the app's space color `#070B14`. July: the least snow where most countries are.

## Architecture (`lib/`)

| File | Role |
| --- | --- |
| `world.dart` | `Country` (decoding, point-in-polygon with holes, distance to border, `view`, `level`, neighbors), `World` (load, search, `pool(region, difficulty)`, `distances`), `Region`, `Difficulty`, `EqualEarth` projection and its inverse, haversine/bearing, `tr()` |
| `store.dart` | `Store` (SharedPreferences): settings (difficulty, theme, language), records per game, region and difficulty, "known" countries, misses per game (weights the picks), daily guesses and streak, road trip stats, `resetProgress` |
| `map.dart` | `loadEarth`, `MapPalette`, `regionColor`, `answer`, `WorldMap` (InteractiveViewer + painter over the Earth texture, animated `focus` re-applied when the map is resized, tap hit test with slack for tiny countries' rings, dot pins, dashed lines, pulse ring), `ShapeView` |
| `ui.dart` | Design tokens and widgets: `Mode` (icon, names, accent), `display()`, `panel()`, `floating()`, `tint()`, `fieldDecoration()`, `Bouncy`, `Shake`, `Confetti`, `Pill`, `ModeBadge`, `RegionPicker`, `Segmented`, `CountryCard`, `BigButton`, `IconSquare`, `Results`, `GameBar`, number formats |
| `main.dart` | Theme (neutral surfaces, Plus Jakarta Sans; theme mode from Settings), home: daily hero card, difficulty, region chips, mode tiles, Road trip and Atlas cards |
| `rush.dart` | Flags / Capitals / Shapes: 60 s, four choices from the same region, x1–x5 combo, −3 s per miss |
| `pin.dart` | Ten countries on the Earth: 1000 points within 50 km, else `1000·e^(−km/800)` |
| `guess.dart` | Mystery country (daily or free play): six guesses, km + arrow + warmth %, region hint after 3 misses, share text |
| `route.dart` | Road trip: `Trip` (BFS distances, `detour`, `linked`, `shortest`, `pick`) and its page |
| `atlas.dart` | Explorable Earth with found countries tinted by continent, search sheet, country cards |
| `settings.dart` | Difficulty, language, theme, progress and reset, version (channel `pangea/app` in `MainActivity.kt`), credits |

- Difficulty: Easy plays level 1, Normal ≤ 2, Hard everything with level 3 picked twice as often. A continent with
  fewer than 8 countries at a level (Oceania on Easy) gets the next level too. Road trips: 2–3 / 3–5 / 4–7 borders,
  with 6 / 4 / 3 spare guesses. A continent without land routes falls back to the world.
- Records are stored per difficulty; Hard keeps the v1.0/v1.1 keys (`best.<mode>.<region>`) since those games
  played every country.
- The daily country is the same for everyone and ignores difficulty: day 1 = 2026-01-01 (local date), countries with
  an area ≥ 2000 km² shuffled once with `Random(2026)`. Changing that pool or seed changes every future day.
- Flags are emoji (Noto Color Emoji on Android): no flag assets. They're bitmaps, so keep them ≤ ~120 px.
- Guess rows are colored by distance on a log scale (`heat`; inside Europe every guess is 90 %+ warm, so the
  percentage alone doesn't tell neighbors apart).
- `Country.view` is where to zoom for a country: its main land (Portugal without the Azores).
- Stacks with a full-screen map and a floating card: wrap the card in `Align`, or the Stack shrinks to the card.
- `WorldMap.focus` skips maps squeezed by the keyboard and remembers the box; it's applied again (immediately,
  stopping any animation) when the map's size changes. A running animation planned for the old size used to land
  after the resize and leave the map showing space beyond the pole.

## Design

- Font: Plus Jakarta Sans, static weights 400–800 (`assets/fonts/`, OFL). Titles and numbers go through `display()`:
  ExtraBold, tight negative tracking, tabular figures. No display/cartoon font.
- Surfaces are neutral (theme in `main.dart`): cards are `surfaceContainerLowest` with a hairline `outlineVariant`
  border (`panel()`). No colored shadows or glows anywhere; only cards floating over a map get a soft neutral shadow
  (`floating()`).
- Each game has one accent (`Mode.color`), used for its icon badge, tinted tile (`tint()`), timer, buttons and
  silhouettes. `BigButton` picks dark or white text from its color's brightness (the ink button is light in dark
  mode). No gradients except the daily hero card's soft corner light. Icons are Material rounded icons; emoji are
  only flags (and the share text).
- Maps show the Earth (same in light and dark themes) with thin white borders. Color means something, as
  translucent fills: the answer (yellow `answer`, readable on land and sea), the pin (accent dot with a white ring),
  road trip ends (blue, pink) and stops (green / amber / red), found countries in the Atlas (one color per continent,
  `regionColor`, with a legend). Tiny countries get a white ring (not on the home preview).
- Answers: outlined option cards that turn into a green or red tint with a matching border and icon.

## Status (2026-10-25)

v1.0.0 (versionCode 1) and v1.1.0 (2) are released and listed in the F-Droid repo.

v1.2.0 verified on the API 36 emulator (debug, dark mode, English and French): home with difficulty and Road trip,
Road trip (detour colors, perfect trip, keyboard open and closed), Settings (language switch applies at once,
version shown), Free play button readable in dark mode, Pin it and the Atlas on the Earth. Earlier versions
verified everything else (rushes, results, mystery country, light mode). Not checked: a real phone (Earth texture
memory and map performance on low-end devices), the share text pasted in another app, the themed icon.

## Emulator gotcha

After the keyboard had been used and the APK reinstalled, the whole app sometimes shows grayed out (window
composited half transparent over the wallpaper) until the emulator is rebooted. Settings and the launcher look
normal. It isn't the app: same APK, fine after `adb reboot`.

## Ideas

Sounds, a borders mode ("which countries touch X?"), capitals on the map, more languages, a 3D globe for the Atlas.
