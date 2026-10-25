"""Builds assets/world.json from Natural Earth (public domain).

    python tool/build_world.py [natural-earth-dir]

The directory must hold ne_10m_admin_0_countries.geojson (downloaded there if missing). Output: one entry per map
unit, quizzable countries first. Rings are simplified, quantized to 0.001 degree and delta-encoded:
[x0, y0, dx1, dy1, ...] in thousandths of a degree (lon, lat).
"""

import json
import math
import os
import sys
import urllib.request

SRC = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries.geojson'
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'world.json')

# Map units that are drawn as part of another country (and answer for it).
MERGE = {'SOL': 'SOM', 'CYN': 'CYP', 'ESB': 'CYP', 'WSB': 'CYP', 'CNM': 'CYP', 'KAB': 'KAZ', 'USG': 'CUB'}
# Non-sovereign units that still count as the country (their sovereign is split into several units).
EXTRA = {'CHN', 'FRA', 'FIN', 'DNK', 'GBR', 'NLD', 'USA', 'AUS', 'NZL', 'ISR', 'KOS', 'PSX'}

# Units that aren't played but that a road trip may cross: Morocco to Mauritania goes through Western Sahara.
PASS_THROUGH = {'SAH'}
# Small but famous: easier than their size suggests.
FAMOUS = {'VAT', 'MCO', 'SGP', 'LUX', 'ISL', 'QAT', 'ISR', 'CHE', 'NLD', 'BEL', 'DNK', 'IRL', 'PRT', 'GRC', 'CUB',
          'JAM', 'NZL', 'KOR', 'PRK', 'TWN', 'AUT', 'CZE', 'HUN', 'MLT', 'CYP', 'LBN', 'KWT', 'ARE', 'PAN', 'CRI', 'HTI',
          'DOM', 'NPL', 'LKA', 'FJI', 'MDV', 'BHS', 'URY', 'JOR', 'PSX', 'BTN', 'SMR', 'AND', 'LIE', 'SWE', 'NOR', 'FIN',
          'THA', 'VNM', 'SAU', 'MAR', 'KEN', 'JPN', 'TUR', 'ZAF', 'PHL'}

# id: (English, French), capital (English, French), extra names accepted when typing
COUNTRIES = {
    'AFG': (None, None, 'Kabul', 'Kaboul'),
    'AGO': (None, None, 'Luanda', 'Luanda'),
    'ALB': (None, None, 'Tirana', 'Tirana'),
    'AND': (None, None, 'Andorra la Vella', 'Andorre-la-Vieille'),
    'ARE': (None, None, 'Abu Dhabi', 'Abou Dabi', 'UAE', 'EAU', 'Emirates'),
    'ARG': (None, None, 'Buenos Aires', 'Buenos Aires'),
    'ARM': (None, None, 'Yerevan', 'Erevan'),
    'ATG': (None, None, "Saint John's", "Saint John's"),
    'AUS': (None, None, 'Canberra', 'Canberra'),
    'AUT': (None, None, 'Vienna', 'Vienne'),
    'AZE': (None, None, 'Baku', 'Bakou'),
    'BDI': (None, None, 'Gitega', 'Gitega'),
    'BEL': (None, None, 'Brussels', 'Bruxelles'),
    'BEN': (None, None, 'Porto-Novo', 'Porto-Novo'),
    'BFA': (None, None, 'Ouagadougou', 'Ouagadougou'),
    'BGD': (None, None, 'Dhaka', 'Dacca'),
    'BGR': (None, None, 'Sofia', 'Sofia'),
    'BHR': (None, None, 'Manama', 'Manama'),
    'BHS': ('Bahamas', None, 'Nassau', 'Nassau', 'The Bahamas'),
    'BIH': (None, None, 'Sarajevo', 'Sarajevo', 'Bosnia', 'Bosnie'),
    'BLR': (None, None, 'Minsk', 'Minsk', 'Bélarus'),
    'BLZ': (None, None, 'Belmopan', 'Belmopan'),
    'BOL': (None, None, 'Sucre', 'Sucre'),
    'BRA': (None, None, 'Brasília', 'Brasilia'),
    'BRB': (None, None, 'Bridgetown', 'Bridgetown'),
    'BRN': (None, None, 'Bandar Seri Begawan', 'Bandar Seri Begawan'),
    'BTN': (None, None, 'Thimphu', 'Thimphou'),
    'BWA': (None, None, 'Gaborone', 'Gaborone'),
    'CAF': (None, None, 'Bangui', 'Bangui', 'CAR', 'Centrafrique'),
    'CAN': (None, None, 'Ottawa', 'Ottawa'),
    'CHE': (None, None, 'Bern', 'Berne'),
    'CHL': (None, None, 'Santiago', 'Santiago'),
    'CHN': ('China', 'Chine', 'Beijing', 'Pékin', "People's Republic of China"),
    'CIV': (None, None, 'Yamoussoukro', 'Yamoussoukro', "Côte d'Ivoire"),
    'CMR': (None, None, 'Yaoundé', 'Yaoundé'),
    'COD': ('DR Congo', 'RD Congo', 'Kinshasa', 'Kinshasa', 'Democratic Republic of the Congo',
            'République démocratique du Congo', 'Congo-Kinshasa', 'DRC', 'RDC', 'Zaire'),
    'COG': ('Congo', 'Congo', 'Brazzaville', 'Brazzaville', 'Republic of the Congo', 'République du Congo',
            'Congo-Brazzaville'),
    'COL': (None, None, 'Bogotá', 'Bogota'),
    'COM': (None, None, 'Moroni', 'Moroni'),
    'CPV': (None, None, 'Praia', 'Praia', 'Cabo Verde'),
    'CRI': (None, None, 'San José', 'San José'),
    'CUB': (None, None, 'Havana', 'La Havane'),
    'CYP': (None, None, 'Nicosia', 'Nicosie'),
    'CZE': ('Czechia', None, 'Prague', 'Prague', 'Czech Republic', 'République tchèque'),
    'DEU': (None, None, 'Berlin', 'Berlin'),
    'DJI': (None, None, 'Djibouti', 'Djibouti'),
    'DMA': (None, None, 'Roseau', 'Roseau'),
    'DNK': (None, None, 'Copenhagen', 'Copenhague'),
    'DOM': (None, None, 'Santo Domingo', 'Saint-Domingue'),
    'DZA': (None, None, 'Algiers', 'Alger'),
    'ECU': (None, None, 'Quito', 'Quito'),
    'EGY': (None, None, 'Cairo', 'Le Caire'),
    'ERI': (None, None, 'Asmara', 'Asmara'),
    'ESP': (None, None, 'Madrid', 'Madrid'),
    'EST': (None, None, 'Tallinn', 'Tallinn'),
    'ETH': (None, None, 'Addis Ababa', 'Addis-Abeba'),
    'FIN': (None, None, 'Helsinki', 'Helsinki'),
    'FJI': (None, None, 'Suva', 'Suva'),
    'FRA': (None, None, 'Paris', 'Paris'),
    'FSM': ('Micronesia', 'Micronésie', 'Palikir', 'Palikir', 'Federated States of Micronesia'),
    'GAB': (None, None, 'Libreville', 'Libreville'),
    'GBR': (None, None, 'London', 'Londres', 'UK', 'Great Britain', 'Grande-Bretagne', 'England', 'Angleterre'),
    'GEO': (None, None, 'Tbilisi', 'Tbilissi'),
    'GHA': (None, None, 'Accra', 'Accra'),
    'GIN': (None, None, 'Conakry', 'Conakry'),
    'GMB': ('Gambia', None, 'Banjul', 'Banjul', 'The Gambia'),
    'GNB': (None, None, 'Bissau', 'Bissau'),
    'GNQ': (None, None, 'Malabo', 'Malabo'),
    'GRC': (None, None, 'Athens', 'Athènes'),
    'GRD': (None, None, "St. George's", 'Saint-Georges'),
    'GTM': (None, None, 'Guatemala City', 'Guatemala'),
    'GUY': (None, None, 'Georgetown', 'Georgetown'),
    'HND': (None, None, 'Tegucigalpa', 'Tegucigalpa'),
    'HRV': (None, None, 'Zagreb', 'Zagreb'),
    'HTI': (None, None, 'Port-au-Prince', 'Port-au-Prince'),
    'HUN': (None, None, 'Budapest', 'Budapest'),
    'IDN': (None, None, 'Jakarta', 'Jakarta'),
    'IND': (None, None, 'New Delhi', 'New Delhi'),
    'IRL': (None, None, 'Dublin', 'Dublin'),
    'IRN': (None, None, 'Tehran', 'Téhéran'),
    'IRQ': (None, None, 'Baghdad', 'Bagdad'),
    'ISL': (None, None, 'Reykjavík', 'Reykjavik'),
    'ISR': (None, None, 'Jerusalem', 'Jérusalem'),
    'ITA': (None, None, 'Rome', 'Rome'),
    'JAM': (None, None, 'Kingston', 'Kingston'),
    'JOR': (None, None, 'Amman', 'Amman'),
    'JPN': (None, None, 'Tokyo', 'Tokyo'),
    'KAZ': (None, None, 'Astana', 'Astana'),
    'KEN': (None, None, 'Nairobi', 'Nairobi'),
    'KGZ': (None, None, 'Bishkek', 'Bichkek', 'Kirghizstan'),
    'KHM': (None, None, 'Phnom Penh', 'Phnom Penh'),
    'KIR': (None, None, 'Tarawa', 'Tarawa'),
    'KNA': (None, None, 'Basseterre', 'Basseterre', 'Saint Kitts', 'Saint-Kitts-et-Nevis'),
    'KOR': (None, None, 'Seoul', 'Séoul', 'Korea', 'Corée'),
    'KOS': (None, None, 'Pristina', 'Pristina'),
    'KWT': (None, None, 'Kuwait City', 'Koweït'),
    'LAO': (None, None, 'Vientiane', 'Vientiane'),
    'LBN': (None, None, 'Beirut', 'Beyrouth'),
    'LBR': (None, None, 'Monrovia', 'Monrovia'),
    'LBY': (None, None, 'Tripoli', 'Tripoli'),
    'LCA': (None, None, 'Castries', 'Castries'),
    'LIE': (None, None, 'Vaduz', 'Vaduz'),
    'LKA': (None, None, 'Sri Jayawardenepura Kotte', 'Sri Jayawardenapura Kotte', 'Ceylon', 'Ceylan'),
    'LSO': (None, None, 'Maseru', 'Maseru'),
    'LTU': (None, None, 'Vilnius', 'Vilnius'),
    'LUX': (None, None, 'Luxembourg', 'Luxembourg'),
    'LVA': (None, None, 'Riga', 'Riga'),
    'MAR': (None, None, 'Rabat', 'Rabat'),
    'MCO': (None, None, 'Monaco', 'Monaco'),
    'MDA': (None, None, 'Chișinău', 'Chișinău', 'Moldova'),
    'MDG': (None, None, 'Antananarivo', 'Antananarivo'),
    'MDV': (None, None, 'Malé', 'Malé'),
    'MEX': (None, None, 'Mexico City', 'Mexico'),
    'MHL': (None, None, 'Majuro', 'Majuro'),
    'MKD': (None, None, 'Skopje', 'Skopje', 'Macedonia', 'Macédoine'),
    'MLI': (None, None, 'Bamako', 'Bamako'),
    'MLT': (None, None, 'Valletta', 'La Valette'),
    'MMR': (None, None, 'Naypyidaw', 'Naypyidaw', 'Burma', 'Myanmar'),
    'MNE': (None, None, 'Podgorica', 'Podgorica'),
    'MNG': (None, None, 'Ulaanbaatar', 'Oulan-Bator'),
    'MOZ': (None, None, 'Maputo', 'Maputo'),
    'MRT': (None, None, 'Nouakchott', 'Nouakchott'),
    'MUS': (None, None, 'Port Louis', 'Port-Louis', 'Île Maurice'),
    'MWI': (None, None, 'Lilongwe', 'Lilongwe'),
    'MYS': (None, None, 'Kuala Lumpur', 'Kuala Lumpur'),
    'NAM': (None, None, 'Windhoek', 'Windhoek'),
    'NER': (None, None, 'Niamey', 'Niamey'),
    'NGA': (None, None, 'Abuja', 'Abuja'),
    'NIC': (None, None, 'Managua', 'Managua'),
    'NLD': (None, None, 'Amsterdam', 'Amsterdam', 'Holland', 'Hollande'),
    'NOR': (None, None, 'Oslo', 'Oslo'),
    'NPL': (None, None, 'Kathmandu', 'Katmandou'),
    'NRU': (None, None, 'Yaren', 'Yaren'),
    'NZL': (None, None, 'Wellington', 'Wellington'),
    'OMN': (None, None, 'Muscat', 'Mascate'),
    'PAK': (None, None, 'Islamabad', 'Islamabad'),
    'PAN': (None, None, 'Panama City', 'Panama'),
    'PER': (None, None, 'Lima', 'Lima'),
    'PHL': (None, None, 'Manila', 'Manille'),
    'PLW': (None, None, 'Ngerulmud', 'Ngerulmud'),
    'PNG': (None, None, 'Port Moresby', 'Port Moresby'),
    'POL': (None, None, 'Warsaw', 'Varsovie'),
    'PRK': (None, None, 'Pyongyang', 'Pyongyang'),
    'PRT': (None, None, 'Lisbon', 'Lisbonne'),
    'PRY': (None, None, 'Asunción', 'Asuncion'),
    'PSX': (None, None, 'Ramallah', 'Ramallah'),
    'QAT': (None, None, 'Doha', 'Doha'),
    'ROU': (None, None, 'Bucharest', 'Bucarest'),
    'RUS': (None, None, 'Moscow', 'Moscou'),
    'RWA': (None, None, 'Kigali', 'Kigali'),
    'SAU': (None, None, 'Riyadh', 'Riyad'),
    'SDN': (None, None, 'Khartoum', 'Khartoum'),
    'SDS': (None, None, 'Juba', 'Djouba'),
    'SEN': (None, None, 'Dakar', 'Dakar'),
    'SGP': (None, None, 'Singapore', 'Singapour'),
    'SLB': (None, None, 'Honiara', 'Honiara'),
    'SLE': (None, None, 'Freetown', 'Freetown'),
    'SLV': (None, None, 'San Salvador', 'San Salvador', 'Le Salvador'),
    'SMR': (None, None, 'San Marino', 'Saint-Marin'),
    'SOM': (None, None, 'Mogadishu', 'Mogadiscio'),
    'SRB': (None, None, 'Belgrade', 'Belgrade'),
    'STP': (None, None, 'São Tomé', 'Sao Tomé'),
    'SUR': (None, None, 'Paramaribo', 'Paramaribo'),
    'SVK': (None, None, 'Bratislava', 'Bratislava'),
    'SVN': (None, None, 'Ljubljana', 'Ljubljana'),
    'SWE': (None, None, 'Stockholm', 'Stockholm'),
    'SWZ': (None, None, 'Mbabane', 'Mbabane', 'Swaziland'),
    'SYC': (None, None, 'Victoria', 'Victoria'),
    'SYR': (None, None, 'Damascus', 'Damas'),
    'TCD': (None, None, "N'Djamena", "N'Djaména"),
    'TGO': (None, None, 'Lomé', 'Lomé'),
    'THA': (None, None, 'Bangkok', 'Bangkok'),
    'TJK': (None, None, 'Dushanbe', 'Douchanbé'),
    'TKM': (None, None, 'Ashgabat', 'Achgabat'),
    'TLS': ('Timor-Leste', None, 'Dili', 'Dili', 'East Timor'),
    'TON': (None, None, "Nuku'alofa", "Nuku'alofa"),
    'TTO': (None, None, 'Port of Spain', "Port-d'Espagne"),
    'TUN': (None, None, 'Tunis', 'Tunis'),
    'TUR': (None, None, 'Ankara', 'Ankara', 'Türkiye'),
    'TUV': (None, None, 'Funafuti', 'Funafuti'),
    'TWN': (None, None, 'Taipei', 'Taipei'),
    'TZA': (None, None, 'Dodoma', 'Dodoma'),
    'UGA': (None, None, 'Kampala', 'Kampala'),
    'UKR': (None, None, 'Kyiv', 'Kiev'),
    'URY': (None, None, 'Montevideo', 'Montevideo'),
    'USA': ('United States', None, 'Washington, D.C.', 'Washington', 'USA', 'US', 'United States of America',
            "États-Unis d'Amérique", 'America', 'Amérique'),
    'UZB': (None, None, 'Tashkent', 'Tachkent'),
    'VAT': (None, 'Vatican', 'Vatican City', 'Vatican', 'Holy See', 'Saint-Siège', 'Cité du Vatican'),
    'VCT': (None, None, 'Kingstown', 'Kingstown'),
    'VEN': (None, None, 'Caracas', 'Caracas'),
    'VNM': (None, None, 'Hanoi', 'Hanoï'),
    'VUT': (None, None, 'Port Vila', 'Port-Vila'),
    'WSM': (None, None, 'Apia', 'Apia'),
    'YEM': (None, None, 'Sanaa', 'Sanaa'),
    'ZAF': (None, None, 'Pretoria', 'Pretoria'),
    'ZMB': (None, None, 'Lusaka', 'Lusaka'),
    'ZWE': (None, None, 'Harare', 'Harare'),
}


def polygons(geometry):
    return geometry['coordinates'] if geometry['type'] == 'MultiPolygon' else [geometry['coordinates']]


def ring_area(ring):
    """Absolute planar area in square degrees (for ranking rings only)."""
    return abs(sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(ring, ring[1:]))) / 2


def km2(ring):
    """Absolute spherical area in km²."""
    r = 6371.0088
    s = sum(math.radians(x1 - x0) * (2 + math.sin(math.radians(y0)) + math.sin(math.radians(y1)))
            for (x0, y0), (x1, y1) in zip(ring, ring[1:]))
    return abs(s) * r * r / 2


def simplify(points, tol):
    """Douglas-Peucker, iterative."""
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        (ax, ay), (bx, by) = points[a], points[b]
        dx, dy = bx - ax, by - ay
        norm = math.hypot(dx, dy)
        best, idx = 0, -1
        for i in range(a + 1, b):
            px, py = points[i]
            d = abs(dy * (px - ax) - dx * (py - ay)) / norm if norm else math.hypot(px - ax, py - ay)
            if d > best:
                best, idx = d, i
        if best > tol:
            keep[idx] = True
            stack += [(a, idx), (idx, b)]
    return [p for p, k in zip(points, keep) if k]


def encode(ring):
    q = [(round(x * 1000), round(y * 1000)) for x, y in ring]
    out, px, py = [], 0, 0
    for x, y in q:
        if out and (x, y) == (px, py):
            continue
        out += [x - px, y - py]
        px, py = x, y
    return out


def bbox(ring, lon0):
    """(west, south, east, north), longitudes shifted to within 180° of lon0 when given."""
    xs = [x if lon0 is None else (x - lon0 + 180) % 360 - 180 + lon0 for x, _ in ring]
    ys = [y for _, y in ring]
    return min(xs), min(ys), max(xs), max(ys)


def gap_km(a, b):
    """Rough distance between two bounding boxes (0 when they overlap)."""
    dx = max(0, b[0] - a[2], a[0] - b[2])
    dy = max(0, b[1] - a[3], a[1] - b[3])
    lat = math.radians(max(abs(a[1]), abs(a[3])) if dy == 0 else (a[1] + a[3]) / 2)
    return 111 * math.hypot(dx * math.cos(lat), dy)


def neighbors(units):
    """Land borders, from the full-resolution outlines: Natural Earth's neighbors share their border vertices."""
    owners = {}
    for uid, u in units.items():
        for ring in (r for poly in u['polys'] for r in poly):  # holes too: Lesotho is South Africa's hole
            for x, y in ring:
                owners.setdefault((round(x, 6), round(y, 6)), set()).add(uid)
    shared = {}
    for ids in owners.values():
        for a in ids:
            for b in ids:
                if a < b:
                    shared[a, b] = shared.get((a, b), 0) + 1
    nb = {uid: set() for uid in units}
    for (a, b), n in shared.items():
        if n >= 2:
            nb[a].add(b)
            nb[b].add(a)
    for hub in PASS_THROUGH:
        for a in nb[hub]:
            nb[a] |= nb[hub] - {a}
    return nb


def levels(entries, nb):
    """1 easy, 2 normal, 3 hard: big or populous countries first, small island states last."""
    def score(e):
        s = math.log10(max(e['pop'], 1)) + 0.6 * math.log10(max(e['area'], 1))
        if e['reg'] in ('Europe', 'Americas'):
            s += 0.7
        if not nb[e['id']] and e['area'] < 30000:
            s -= 1.5
        if e['id'] in FAMOUS:
            s += 2
        return s

    ranked = sorted(entries, key=score, reverse=True)
    return {e['id']: 1 if i < 70 else 2 if i < 145 else 3 for i, e in enumerate(ranked)}


def main():
    src_dir = sys.argv[1] if len(sys.argv) > 1 else '.'
    path = os.path.join(src_dir, 'ne_10m_admin_0_countries.geojson')
    if not os.path.exists(path):
        urllib.request.urlretrieve(SRC, path)
    features = json.load(open(path, encoding='utf-8'))['features']

    units = {}
    for f in features:
        p = f['properties']
        uid = MERGE.get(p['ADM0_A3'], p['ADM0_A3'])
        if uid == 'ATA':
            continue
        u = units.setdefault(uid, {'polys': []})
        u['polys'] += polygons(f['geometry'])
        if uid == p['ADM0_A3']:
            u['props'] = p

    out = []
    for uid, u in units.items():
        p = u['props']
        quiz = uid in COUNTRIES and (p['TYPE'] in ('Sovereign country', 'Sovereignty') or uid in EXTRA)
        polys = sorted(u['polys'], key=lambda poly: -ring_area(poly[0]))
        biggest = ring_area(polys[0][0])
        # Silhouettes show the "main" polygons: big ones, or ones close to the biggest's bounding box (Corsica
        # yes, Guiana no). Longitudes are taken around the biggest one so Chukotka stays next to Russia.
        box = bbox(polys[0][0], None)
        lon0 = (box[0] + box[2]) / 2
        extent = max(box[2] - box[0], box[3] - box[1]) * 111
        main = [poly for poly in polys
                if ring_area(poly[0]) >= 0.15 * biggest or gap_km(box, bbox(poly[0], lon0)) < max(300, 0.15 * extent)]
        rest = [poly for poly in polys if poly not in main]
        tol = min(0.03, max(0.002, extent / 111 * 0.004))
        area = sum(km2(poly[0]) - sum(km2(h) for h in poly[1:]) for poly in polys)

        def ring_out(ring, first):
            # Drop specks (a tiny island next to a big country) but never a country's own main ring.
            if not first and ring_area(ring) < min(0.01, 0.01 * biggest):
                return None
            s = simplify(ring, tol)
            return encode(s if len(s) >= 4 else ring)

        enc = []
        for poly in main + rest:
            rings = [r for r in (ring_out(ring, poly is polys[0] and i == 0) for i, ring in enumerate(poly[0:1]))
                     if r]
            if not rings:
                continue
            rings += [r for r in (ring_out(h, False) for h in poly[1:]) if r]
            enc.append(rings)
        main_count = sum(1 for poly in main if ring_out(poly[0], poly is polys[0]))

        entry = {'id': uid, 'q': 1 if quiz else 0, 'iso': p['ISO_A2_EH'], 'en': p['NAME_EN'], 'fr': p['NAME_FR'],
                 'reg': p['REGION_UN'], 'pop': round(p['POP_EST']), 'area': round(area), 'lx': round(p['LABEL_X'], 3),
                 'ly': round(p['LABEL_Y'], 3), 'main': main_count, 'p': enc}
        if quiz:
            en, fr, cap_en, cap_fr, *alias = COUNTRIES[uid]
            entry.update(en=en or p['NAME_EN'], fr=fr or p['NAME_FR'], capEn=cap_en, capFr=cap_fr)
            entry['alias'] = sorted(set(alias + [p['NAME'], p['NAME_EN'], p['NAME_FR']]) - {entry['en'], entry['fr']})
        out.append(entry)

    out.sort(key=lambda e: (-e['q'], e['id']))
    quiz_ids = {e['id'] for e in out if e['q']}
    nb = neighbors(units)
    lv = levels([e for e in out if e['q']], nb)
    for e in out:
        if e['q']:
            e['lv'] = lv[e['id']]
            e['nb'] = sorted(nb[e['id']] & quiz_ids)
    assert quiz_ids == set(COUNTRIES), (quiz_ids ^ set(COUNTRIES))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump({'countries': out}, f, ensure_ascii=False, separators=(',', ':'))
    pts = sum(len(r) // 2 for e in out for poly in e['p'] for r in poly)
    print(f'{len(out)} units, {len(quiz_ids)} countries, {pts} points, {os.path.getsize(OUT) // 1024} KB')


if __name__ == '__main__':
    main()
