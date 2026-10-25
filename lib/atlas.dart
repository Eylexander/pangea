import 'package:flutter/material.dart';

import 'map.dart';
import 'store.dart';
import 'ui.dart';
import 'world.dart';

/// Countries found in any game take their continent's color; the others stay plain land.
Color? foundFill(Country c, Set<String> known) =>
    known.contains(c.id) ? regionColor(c.region).withValues(alpha: 0.62) : null;

/// The world map to explore: tap a country to learn about it.
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
    final b = c.view;
    _map.currentState?.focus(b.inflate(b.longestSide * 0.3 + 1.5));
    _open(c);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final palette = MapPalette.of(context);
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
              padding: const EdgeInsets.only(top: 200, left: 12, right: 12, bottom: 70),
              fill: (c) => c == _selected ? palette.ink.withValues(alpha: 0.7) : foundFill(c, known),
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
                decoration: floating(context),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GameBar(
                      title: Mode.atlas.title,
                      subtitle: tr(
                        '$found of ${pool.length} countries found',
                        '$found pays trouvés sur ${pool.length}',
                      ),
                      trailing: IconSquare(
                        Icons.search_rounded,
                        size: 44,
                        tooltip: tr('Find a country', 'Chercher un pays'),
                        onTap: _search,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 2, 18, 14),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: pool.isEmpty ? 0 : found / pool.length,
                          minHeight: 6,
                          color: _region == null ? cs.onSurface : regionColor(_region),
                          backgroundColor: cs.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    RegionPicker(
                      value: _region,
                      padding: 14,
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
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: floating(context, radius: 99),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final r in Region.values) ...[
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(color: regionColor(r), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        Text(r.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        if (r != Region.values.last) const SizedBox(width: 12),
                      ],
                    ],
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
    final known = Store.instance.known;
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
                decoration: fieldDecoration(context, tr('Country name', 'Nom du pays'), Icons.search_rounded),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final c in hits)
                    ListTile(
                      leading: Text(c.flag, style: const TextStyle(fontSize: 26)),
                      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(c.capital, style: TextStyle(color: cs.onSurfaceVariant)),
                      trailing: known.contains(c.id)
                          ? Icon(Icons.check_circle_rounded, color: regionColor(c.region))
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
