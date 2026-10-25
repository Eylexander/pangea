# CLAUDE.md

Pangea: a geography game for Android (Flutter only, no native code). Written for the user, who likes testing and
learning geography; they asked for something fun with a vibrant UI. English or French, picked from the phone's
language (`fr`/`tr()` in `lib/world.dart`). Offline, no network permission.

## Toolchain

Same as Sablier and LLLearner: Flutter 3.47.7 (`~/SDKs/flutter-3.47.7`), Android SDK in `%LOCALAPPDATA%/Android/Sdk`
(AVD `Medium_Phone_API_36.0`), Android Studio's JDK:

```sh
export PATH=~/SDKs/flutter-3.47.7/bin:$LOCALAPPDATA/Android/Sdk/platform-tools:$PATH \
  ANDROID_HOME=$LOCALAPPDATA/Android/Sdk JAVA_HOME="$LOCALAPPDATA/Programs/Android Studio/jbr"
flutter analyze && flutter test                              # test/world_test.dart: geo math, search, daily
dart format -l 120 lib test                                  # 120-col lines
flutter build apk --debug --target-platform android-x64      # emulator; package com.eylexander.pangea.debug
flutter build apk --release --target-platform android-arm64  # ~17.5 MB
python tool/build_world.py <dir>                             # regenerates assets/world.json (see Data)
```

## Releasing (same scheme as the other apps of `../fdroid`)

- Package `com.eylexander.pangea`, GitHub `Eylexander/pangea`, listing in
  `../fdroid/metadata/com.eylexander.pangea/{en-US,fr-FR}/`. Push a `v*` tag: `.github/workflows/release.yml` calls
  the shared `Eylexander/fdroid/.github/workflows/flutter-apk.yml` (versionCode = run number, so keep the file's name).
- Release key: `.secrets/` (git-ignored), the shared key, SHA-256 `db171ead…`. CI gets it from the
  `RELEASE_KEYSTORE_BASE64` / `RELEASE_KEYSTORE_PASS` secrets. Never regenerate or lose it.
- Launcher icon: adaptive vector only (`res/drawable/ic_launcher_*.xml`: a globe with a yellow pin on the title's
  pink-violet-blue gradient), same paths in `tool/icon.svg` for the store PNG. minSdk 26 because there is no PNG
  fallback. `rsvg-convert` isn't installed here: render the SVG with the `@resvg/resvg-js` npm package.

## Data (`tool/build_world.py` → `assets/world.json`, 700 KB)

- Natural Earth 10m admin-0 countries (public domain). 250 map units; 197 are played (`q: 1`): UN members plus
  Vatican, Palestine, Kosovo, Taiwan. Somaliland and Northern Cyprus are merged into Somalia and Cyprus (`MERGE`).
  Territories (Greenland, Puerto Rico…) are drawn gray and can't be answered. Antarctica is left out.
- Names: Natural Earth's `NAME_EN`/`NAME_FR`, with overrides and typing aliases in `COUNTRIES` (the script asserts
  that table has exactly the played countries). Capitals in both languages are hand-written there (Natural Earth's
  have no French names).
- Rings are Douglas-Peucker simplified (tolerance scales with the country's size), quantized to 0.001° and
  delta-encoded. Specks of islands next to big countries are dropped. Polygons are sorted so the first `main` are the
  silhouette: the biggest one plus those big or close to it (Corsica in, French Guiana out; longitudes taken around
  the biggest so Chukotka stays with Russia).
- `area` is computed (km²), `pop` is Natural Earth's estimate, `lx/ly` its label point: used for distances and
  directions in the mystery game, and for the dots of tiny countries.

## Architecture (`lib/`)

| File | Role |
| --- | --- |
| `world.dart` | `Country` (decoding, point-in-polygon with holes, distance to border), `World` (load, search), `Region`, `EqualEarth` projection and its inverse, haversine/bearing, `tr()` |
| `store.dart` | `Store` (SharedPreferences): records per game and region, "known" countries, misses per game (weights the picks), daily guesses and streak |
| `map.dart` | `WorldMap` (InteractiveViewer + painter, animated `focus`, tap hit test with slack for tiny countries' dots, pins, dashed lines, pulse ring), `ShapeView` (silhouette) |
| `ui.dart` | `Mode` (each game's emoji, names, gradient), `Bouncy`, `Shake`, `Confetti`, `Pill`, `RegionPicker`, `CountryCard`, `BigButton`, `Results`, number formats |
| `main.dart` | Theme (seed violet, vibrant variant), home: daily card, region chips, mode tiles, Atlas tile |
| `rush.dart` | Flags / Capitals / Shapes: 60 s, four choices from the same region, x1–x5 combo, −3 s per miss |
| `pin.dart` | Ten countries on a blank map: 1000 points within 50 km, else `1000·e^(−km/800)` |
| `guess.dart` | Mystery country (daily or free play): six guesses, km + arrow + warmth %, region hint after 3 misses, share text |
| `atlas.dart` | Explorable map colored by what's been found, search sheet, country cards |

- The daily country is the same for everyone: day 1 = 2026-01-01 (local date), countries with an area ≥ 2000 km²
  shuffled once with `Random(2026)`. Changing that pool or seed changes every future day.
- Flags are emoji (Noto Color Emoji on Android): no flag assets. They're bitmaps, so keep them ≤ ~120 px.
- Colors: map land by Natural Earth's `MAPCOLOR7` (`landColor`), guess rows by distance on a log scale (`heat`;
  inside Europe every guess is 90 %+ warm, so the percentage alone doesn't tell neighbors apart).
- Stacks with a full-screen map and a floating card: wrap the card in `Align`, or the Stack shrinks to the card.

## Status (2026-10-25)

Verified on the API 36 emulator (debug, light and dark, English and French): home, Flags and Capitals rushes
(penalty, results with record and review list), Shapes, Pin it (world and Europe, a microstate found by its dot),
the mystery country (suggestions, rows, hint, win with confetti and streak), the Atlas (tap → card), Pin it's end
screen. The release APK
builds and is signed with `db171ead…`. Not checked: the share text pasted in another app,
a real phone (performance of the 87k-point map on low-end devices), the themed icon on a launcher.

## Emulator gotcha

After the keyboard had been used and the APK reinstalled, the whole app once showed grayed out (window composited
half transparent over the wallpaper) until the emulator was rebooted. Settings and the launcher looked normal. It
wasn't the app: same APK, fine after `adb reboot`.

## Ideas

Sounds, borders mode ("which countries touch X?"), capitals on the map, Travle-style routes, more languages.
