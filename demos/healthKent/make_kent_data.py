#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# Generates kentdata.inc for the healthKent demo (uKentData.pas includes it).
#
# The area is the NHS Kent and Medway Integrated Care Board: Kent County
# Council's twelve districts plus Medway, 1107 LSOAs (2021). Everything is
# compiled in, so the demo needs no network.
#
#   - LSOA (2021) boundaries: ONS BFE V10 (full resolution, extent of the
#     realm, i.e. to mean low water), simplified here (Douglas-Peucker,
#     SIMPLIFY_M). The program draws them only inside the district
#     coastline (below), so the intertidal parts don't show.
#   - District boundaries: ONS LAD (Dec 2024) BFC (clipped to the
#     coastline), simplified the same way. They are the land mask and
#     the district outlines.
#   - Population: ONS mid-2024 LSOA population estimates (Nomis NM_2014_1,
#     released 2025-11-07), all ages, persons.
#   - Land area: ONS Standard Area Measurements 2021, "land count" km2
#     (excludes tidal water and large inland water).
#   - Deprivation: English Indices of Deprivation 2025 (MHCLG), File 7 -
#     IMD and its seven domains: score, national rank (of 33,755) and
#     national decile (1 = most deprived 10 %).
#   - Towns: ONS built-up areas (2022), via the LSOA (2021) -> BUA (2022)
#     best-fit lookup; a town's population is the sum of its LSOAs'
#     mid-2024 estimates, its position their population-weighted mean
#     (LSOA label points). Those over TOWN_MIN are kept.
#   - Roads and rail: OpenStreetMap (ODbL) via the Overpass API -
#     highway = motorway / trunk / primary and railway = rail (no
#     service tracks), converted to BNG with bng.py and simplified.
#
# Sources (download into one directory first; uKentData.pas's Sources table,
# shown on the program's Sources tab, describes each). ONS services are under
# https://services1.arcgis.com/ESMARspQHYMw9BZ9/arcgis/rest/services/
#   icb_lookup.json    LSOA21_SICBL25_ICB25_CAL25_LAD25_EN_LU/FeatureServer/0/query
#                      ?where=ICB25NM LIKE '%Kent%'&outFields=LSOA21CD,LSOA21NM,LAD25CD,
#                      LAD25NM,ICB25NM&resultRecordCount=2000&f=json
#   lsoa_bfe.geojson   LSOA_2021_EW_BFE_V10_RUC/FeatureServer/3/query, those LSOA21CDs
#                      (POST, 300 at a time), outSR=27700, f=geojson
#   lad_bfc.geojson    Local_Authority_Districts_December_2024_Boundaries_UK_BFC/
#                      FeatureServer/0/query, the 13 LAD24CDs, outSR=27700, f=geojson
#   lsoa_bua22.json    LSOA21_BUA22_LAD22_RGN22_EW_LU_v2/FeatureServer/0/query, the
#                      LSOA21CDs (the 'features' list saved)
#   pop2024_lsoa.csv   https://www.nomisweb.co.uk/api/v01/dataset/NM_2014_1.data.csv
#                      ?geography=TYPE151&date=latest&gender=0&c_age=200&measures=20100
#                      &select=date_name,geography_code,geography_name,obs_value
#                      (25,000-row pages: add &recordoffset=25000 and append)
#   sam_lsoa_km.csv    SAM_LSOA_DEC_2021_EW_in_KM.csv from the ONS item
#                      a488cb8fc9a74accb63cb52961e456ef (Standard Area Measurements
#                      for 2021 Statistical Geographies), arcgis.com .../items/<id>/data
#   iod2025_file7.csv  https://www.gov.uk/government/statistics/english-indices-of-
#                      deprivation-2025, File 7 (CSV)
#   osm_routes.json    Overpass API (https://overpass-api.de/api/interpreter):
#                      [out:json][timeout:180];(way["highway"~"^(motorway|trunk|primary)$"]
#                      (50.88,-0.05,51.52,1.48);way["railway"="rail"]["service"!~"."]
#                      ["usage"!~"^(industrial|military|test)$"](50.88,-0.05,51.52,1.48););
#                      out tags geom;
#
# Usage: python3 make_kent_data.py <download dir>
# ---------------------------------------------------------------------------
import sys, os, json, csv, math, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bng import to_bng

src = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
SIMPLIFY_M = 12.0          # LSOA / district boundary tolerance, m
ROUTE_SIMPLIFY_M = 20.0
TOWN_MIN = 50000

def P(name):
    return os.path.join(src, name)

# ---- geometry helpers ---------------------------------------------------------
def dp(pts, tol):
    """Douglas-Peucker on an open polyline"""
    if len(pts) < 3:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = pts[a]
        bx, by = pts[b]
        dx, dy = bx - ax, by - ay
        L = math.hypot(dx, dy)
        dmax, imax = -1.0, -1
        for i in range(a + 1, b):
            px, py = pts[i]
            d = abs(dy * (px - ax) - dx * (py - ay)) / L if L > 0 else math.hypot(px - ax, py - ay)
            if d > dmax:
                dmax, imax = d, i
        if dmax > tol:
            keep[imax] = True
            stack += [(a, imax), (imax, b)]
    return [p for p, k in zip(pts, keep) if k]

def simplify_ring(r, tol):
    """closed ring (no repeated end point): split at the vertex farthest
    from the first, simplify the two halves"""
    if len(r) < 8:
        return r
    x0, y0 = r[0]
    far = max(range(len(r)), key=lambda i: (r[i][0] - x0) ** 2 + (r[i][1] - y0) ** 2)
    a = dp(r[:far + 1], tol)
    b = dp(r[far:] + [r[0]], tol)
    out = a[:-1] + b[:-1]
    return out if len(out) >= 3 else r

def rings_of(geom):
    polys = geom['coordinates'] if geom['type'] == 'MultiPolygon' else [geom['coordinates']]
    out = []
    for poly in polys:
        for ring in poly:
            out.append(ring[:-1] if ring[0] == ring[-1] else ring)
    return out

def ring_area(r):
    return 0.5 * abs(sum(r[i][0] * r[(i + 1) % len(r)][1] - r[(i + 1) % len(r)][0] * r[i][1]
                         for i in range(len(r))))

def inside(x, y, rings):
    c = False
    for r in rings:
        n = len(r)
        for k in range(n):
            x1, y1 = r[k]
            x2, y2 = r[(k + 1) % n]
            if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                c = not c
    return c

# ---- LSOAs ----------------------------------------------------------------------
lookup = {f['attributes']['LSOA21CD']: f['attributes'] for f in json.load(open(P('icb_lookup.json')))['features']}
lads = sorted({(a['LAD25CD'], a['LAD25NM']) for a in lookup.values()}, key=lambda t: t[1])
lad_index = {c: i for i, (c, _) in enumerate(lads)}

pop = {}
with open(P('pop2024_lsoa.csv'), encoding='utf-8') as fh:
    r = csv.DictReader(fh)
    for row in r:
        if row['GEOGRAPHY_CODE'] in lookup:
            pop[row['GEOGRAPHY_CODE']] = int(row['OBS_VALUE'])
            pop_year = row['DATE_NAME']
land = {}
with open(P('sam_lsoa_km.csv'), encoding='utf-8-sig') as fh:
    for row in csv.DictReader(fh):
        if row['LSOA21CD'] in lookup:
            land[row['LSOA21CD']] = float(row['Land Count (Area in KM2)'])

# IoD 2025: (score, rank, decile) for IMD and the seven domains, by column
DOMAINS = [('Index of Multiple Deprivation', 4), ('Income', 7), ('Employment', 10),
           ('Education, skills and training', 13), ('Health deprivation and disability', 16),
           ('Crime', 19), ('Barriers to housing and services', 22), ('Living environment', 25)]
iod = {}
with open(P('iod2025_file7.csv'), encoding='utf-8-sig') as fh:
    r = csv.reader(fh)
    next(r)
    for row in r:
        if row[0] in lookup:
            iod[row[0]] = [(float(row[c]), int(row[c + 1]), int(row[c + 2])) for _, c in DOMAINS]

bua = {f['attributes']['LSOA21CD']: (f['attributes']['BUA22CD'], f['attributes']['BUA22NM'])
       for f in json.load(open(P('lsoa_bua22.json')))}

lsoas = []
for f in json.load(open(P('lsoa_bfe.geojson')))['features']:
    p = f['properties']
    c = p['LSOA21CD']
    rings = [simplify_ring(r, SIMPLIFY_M) for r in rings_of(f['geometry'])]
    rings = [r for r in rings if ring_area(r) > 400 or len(rings) == 1]     # drop specks < 20 m square
    lsoas.append(dict(code=c, name=p['LSOA21NM'], lad=lad_index[lookup[c]['LAD25CD']],
                      e=p['BNG_E'], n=p['BNG_N'], pop=pop[c], land=land[c], iod=iod[c],
                      bua=bua.get(c, ('', ''))[1] or '', rings=rings))
lsoas.sort(key=lambda l: l['code'])
assert len(lsoas) == 1107 and all(len(l['iod']) == len(DOMAINS) for l in lsoas)

# ---- districts --------------------------------------------------------------------
lad_rings = {}
for f in json.load(open(P('lad_bfc.geojson')))['features']:
    rs = [simplify_ring(r, SIMPLIFY_M) for r in rings_of(f['geometry'])]
    lad_rings[f['properties']['LAD24CD']] = [r for r in rs if ring_area(r) > 2500]   # islets < 50 m square
assert set(lad_rings) == set(c for c, _ in lads)

# ---- towns: built-up areas -----------------------------------------------------
towns = {}
for l in lsoas:
    if l['bua']:
        t = towns.setdefault(l['bua'], [0, 0.0, 0.0, 0])
        t[0] += l['pop']; t[1] += l['pop'] * l['e']; t[2] += l['pop'] * l['n']; t[3] += 1
towns = sorted(((re.sub(r' \(.*\)$', '', nm), t[0], t[1] / t[0], t[2] / t[0], t[3]) for nm, t in towns.items() if t[0] > TOWN_MIN),
               key=lambda t: -t[1])

# ---- roads and rail -------------------------------------------------------------
# coarse land mask (1 km cells) from heavily simplified district rings, to
# drop routes that never come near the area; the program clips exactly
coarse = [simplify_ring(r, 300) for rs in lad_rings.values() for r in rs]
xs = [q[0] for r in coarse for q in r]; ys = [q[1] for r in coarse for q in r]
gx0, gy0 = min(xs) - 2000, min(ys) - 2000
nx, ny = int((max(xs) - gx0) / 1000) + 3, int((max(ys) - gy0) / 1000) + 3
mask = [[inside(gx0 + (i + 0.5) * 1000, gy0 + (j + 0.5) * 1000, coarse) for i in range(nx)] for j in range(ny)]
def near(x, y):
    i, j = int((x - gx0) / 1000), int((y - gy0) / 1000)
    return any(0 <= j + b < ny and 0 <= i + a < nx and mask[j + b][i + a]
               for a in (-1, 0, 1) for b in (-1, 0, 1))

ROUTE_KIND = {'motorway': 0, 'trunk': 1, 'primary': 2}       # 3 = rail
osm = json.load(open(P('osm_routes.json')))
osm_stamp = osm['osm3s']['timestamp_osm_base']
routes = []
for w in osm['elements']:
    t = w['tags']
    kind = 3 if t.get('railway') == 'rail' else ROUTE_KIND.get(t.get('highway'))
    if kind is None or 'geometry' not in w:
        continue
    pts = [to_bng(g['lat'], g['lon']) for g in w['geometry']]
    if not any(near(x, y) for x, y in pts):
        continue
    pts = dp(pts, ROUTE_SIMPLIFY_M)
    routes.append((kind, t.get('ref', ''), pts))
routes.sort(key=lambda r: -r[0])        # rail and minor first, motorways drawn last (on top)

# ---- write -------------------------------------------------------------------------
def pas(s):
    return "'" + s.replace("'", "''") + "'"

def arr(name, typ, vals, fmt, per=10):
    items = [fmt % v for v in vals]
    lines = [', '.join(items[i:i + per]) for i in range(0, len(items), per)]
    return '  %s: array[0..%d] of %s = (\n    %s\n  );\n' % (name, len(vals) - 1, typ, ',\n    '.join(lines))

ring_first, ring_start, pe, pn = [0], [0], [], []
for l in lsoas:
    for r in l['rings']:
        for x, y in r:
            pe.append(x); pn.append(y)
        ring_start.append(len(pe))
    ring_first.append(len(ring_start) - 1)
lring_first, lring_start, le, ln = [0], [0], [], []
for c, _ in lads:
    for r in lad_rings[c]:
        for x, y in r:
            le.append(x); ln.append(y)
        lring_start.append(len(le))
    lring_first.append(len(lring_start) - 1)
rt_start, rt_kind, rt_ref, re_, rn = [0], [], [], [], []
for kind, ref, pts in routes:
    for x, y in pts:
        re_.append(x); rn.append(y)
    rt_start.append(len(re_)); rt_kind.append(kind); rt_ref.append(ref)

with open(os.path.join(here, 'kentdata.inc'), 'w', encoding='utf-8') as fh:
    fh.write('// Generated by make_kent_data.py - do not edit. Kent and Medway (NHS Kent and\n'
             '// Medway ICB area). Coordinates British National Grid metres. Sources: see\n'
             '// the script header and uKentData.pas.\n')
    fh.write('const\n  LsoaCount = %d;\n  LsoaRingCount = %d;\n  LsoaPointCount = %d;\n'
             % (len(lsoas), len(ring_start) - 1, len(pe)))
    fh.write('  DistrictCount = %d;\n  DistrictRingCount = %d;\n' % (len(lads), len(lring_start) - 1))
    fh.write('  DomainCount = %d;\n  TownCount = %d;\n  RouteCount = %d;\n' % (len(DOMAINS), len(towns), len(routes)))
    fh.write('  PopulationYear = %s;\n  OsmTimestamp = %s;\n  TownMinPopulation = %d;\n'
             % (pas('mid-' + pop_year), pas(osm_stamp), TOWN_MIN))
    fh.write(arr('DistrictCode', 'string', [pas(c) for c, _ in lads], '%s', 6))
    fh.write(arr('DistrictName', 'string', [pas(n) for _, n in lads], '%s', 4))
    fh.write(arr('DomainName', 'string', [pas(d) for d, _ in DOMAINS], '%s', 2))
    fh.write(arr('LsoaCode', 'string', [pas(l['code']) for l in lsoas], '%s', 6))
    fh.write(arr('LsoaName', 'string', [pas(l['name']) for l in lsoas], '%s', 5))
    fh.write(arr('LsoaBUA', 'string', [pas(l['bua']) for l in lsoas], '%s', 5))
    fh.write(arr('LsoaDistrict', 'Integer', [l['lad'] for l in lsoas], '%d', 20))
    fh.write(arr('LsoaPop', 'Integer', [l['pop'] for l in lsoas], '%d', 12))
    fh.write(arr('LsoaLandKm2', 'Single', [l['land'] for l in lsoas], '%.4f', 10))
    fh.write(arr('LsoaLabelE', 'Single', [l['e'] for l in lsoas], '%.0f', 12))
    fh.write(arr('LsoaLabelN', 'Single', [l['n'] for l in lsoas], '%.0f', 12))
    fh.write('  // LSOA i, domain d (0 = IMD): Lsoa...[i * DomainCount + d]\n')
    fh.write(arr('LsoaScore', 'Single', [s for l in lsoas for s, _, _ in l['iod']], '%.3f', 8))
    fh.write(arr('LsoaRank', 'Integer', [k for l in lsoas for _, k, _ in l['iod']], '%d', 8))
    fh.write(arr('LsoaDecile', 'Byte', [d for l in lsoas for _, _, d in l['iod']], '%d', 16))
    fh.write(arr('LsoaRingFirst', 'Integer', ring_first, '%d', 12))
    fh.write(arr('LsoaRingStart', 'Integer', ring_start, '%d', 12))
    fh.write(arr('LsoaPtE', 'Single', pe, '%.1f', 10))
    fh.write(arr('LsoaPtN', 'Single', pn, '%.1f', 10))
    fh.write(arr('DistrictRingFirst', 'Integer', lring_first, '%d', 12))
    fh.write(arr('DistrictRingStart', 'Integer', lring_start, '%d', 12))
    fh.write(arr('DistrictPtE', 'Single', le, '%.1f', 10))
    fh.write(arr('DistrictPtN', 'Single', ln, '%.1f', 10))
    fh.write(arr('TownName', 'string', [pas(t[0]) for t in towns], '%s', 4))
    fh.write(arr('TownPop', 'Integer', [t[1] for t in towns], '%d', 10))
    fh.write(arr('TownLsoas', 'Integer', [t[4] for t in towns], '%d', 10))
    fh.write(arr('TownE', 'Single', [t[2] for t in towns], '%.0f', 10))
    fh.write(arr('TownN', 'Single', [t[3] for t in towns], '%.0f', 10))
    fh.write('  // 0 motorway, 1 trunk road, 2 primary A road, 3 railway\n')
    fh.write(arr('RouteKind', 'Byte', rt_kind, '%d', 30))
    fh.write(arr('RouteRef', 'string', [pas(s) for s in rt_ref], '%s', 8))
    fh.write(arr('RouteStart', 'Integer', rt_start, '%d', 12))
    fh.write(arr('RoutePtE', 'Single', re_, '%.0f', 12))
    fh.write(arr('RoutePtN', 'Single', rn, '%.0f', 12))

tot = sum(l['pop'] for l in lsoas)
print('%d LSOAs, %d rings, %d points; %d districts, %d rings, %d points' %
      (len(lsoas), len(ring_start) - 1, len(pe), len(lads), len(lring_start) - 1, len(le)))
print('population %s %d; land %.1f km2' % (pop_year, tot, sum(l['land'] for l in lsoas)))
print('%d routes, %d points; OSM %s' % (len(routes), len(re_), osm_stamp))
for t in towns:
    print('  %-28s %7d  (%d LSOAs)' % (t[0], t[1], t[4]))
print('barycentre E %.0f N %.0f' % (sum(l['pop'] * l['e'] for l in lsoas) / tot, sum(l['pop'] * l['n'] for l in lsoas) / tot))
