import 'package:flutter/material.dart';

import 'map.dart';
import 'store.dart';
import 'ui.dart';
import 'world.dart';

/// A pale tint where the player hasn't found the country yet, full color once they have. Territories stay gray.
Color knownFill(Country c, Brightness b, Set<String> known) {
  final dark = b == Brightness.dark;
  if (!c.quiz) return dark ? const Color(0xFF3A3F66) : const Color(0xFFDCD8E8);
  if (known.contains(c.id)) return landColor(c, b);
  return Color.lerp(landColor(c, b), dark ? const Color(0xFF1C2050) : Colors.white, 0.75)!;
}

/// The world map to explore: tap a country to learn about it. Countries found in any game are in color.
class AtlasPage extends StatefulWidget {
  const AtlasPage({super.key});

  @override
  State<AtlasPage> createState() => _AtlasPageState();
}

class _AtlasPageState extends State<AtlasPage> {
  final _map = GlobalKey<WorldMapState>();
  late Region? _region = Store.instance.region;
  Country? _selected;

  Rect _viewOf(Region? r) => r?.view ?? Region.worldView;

  Future<void> _open(Country c) async {
    setState(() => _selected = c);
    await showCountry(context, c);
    if (mounted) setState(() => _selected = null);
  }

  Future<void> _search() async {
    final c = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _SearchSheet(),
    );
    if (c == null || !mounted) return;
    final b = c.bounds.width < 90 ? c.bounds : Rect.fromCenter(center: Offset(c.lon, c.lat), width: 40, height: 30);
    _map.currentState?.focus(b.inflate(b.longestSide * 0.3 + 1.5));
    _open(c);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final known = Store.instance.known;
    final pool = World.instance.inRegion(_region);
    final found = pool.where((c) => known.contains(c.id)).length;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: WorldMap(
              key: _map,
              view: _viewOf(_region),
              padding: const EdgeInsets.only(top: 200, left: 12, right: 12, bottom: 24),
              fill: (c) => c == _selected ? Mode.atlas.colors.first : knownFill(c, brightness, known),
              pulse: _selected,
              onTap: (lon, lat, hit) {
                if (hit != null) _open(hit);
              },
            ),
          ),
          // Align fills the Stack like the map does; the card alone would shrink the Stack to its own height.
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                padding: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 6))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GameBar(
                      mode: Mode.atlas,
                      trailing: IconButton.filledTonal(
                        onPressed: _search,
                        icon: const Icon(Icons.search_rounded),
                        tooltip: tr('Find a country', 'Chercher un pays'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text('$found / ${pool.length}', style: display(22)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tr('countries found', 'pays trouvés'),
                                  style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: pool.isEmpty ? 0 : found / pool.length,
                              minHeight: 10,
                              color: Mode.atlas.colors.last,
                              backgroundColor: cs.surfaceContainerHighest,
                            ),
                          ),
                        ],
                      ),
                    ),
                    RegionPicker(
                      value: _region,
                      onChanged: (r) {
                        setState(() => _region = r);
                        _map.currentState?.focus(_viewOf(r));
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet();

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hits = _query.isEmpty
        ? (World.instance.countries.toList()..sort((a, b) => a.name.compareTo(b.name)))
        : World.instance.search(_query, limit: 30);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                autocorrect: false,
                onChanged: (q) => setState(() => _query = q),
                decoration: InputDecoration(
                  hintText: tr('Country name', 'Nom du pays'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final c in hits)
                    ListTile(
                      leading: Text(c.flag, style: const TextStyle(fontSize: 28)),
                      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(c.capital),
                      trailing: Store.instance.known.contains(c.id)
                          ? const Icon(Icons.check_circle, color: good)
                          : null,
                      onTap: () => Navigator.pop(context, c),
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
