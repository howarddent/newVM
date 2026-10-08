#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# Generates countydata.inc for the CanterburyRain demo's county rainfall map
# (uCountyRain.pas includes it):
#
#   - the 218 UK "counties and unitary authorities" (ONS, December 2024,
#     ultra-generalised boundaries, British National Grid): names, codes,
#     boundary rings, label points
#   - for each county, the HadUK-Grid 12 km cells whose centres fall inside
#     it (cell index j*NX+i on the Met Office grid). About 50 small areas
#     (London boroughs, small unitary authorities) contain no 12 km cell
#     centre; each of those uses the land cell nearest its ONS label point
#     and is flagged
#   - each county's 1991-2020 average rainfall for every calendar month:
#     the mean of its cells' HadUK-Grid 1991-2020 monthly averages
#   - the HadUK-Grid 12 km grid geometry
#   - Ireland and the Isle of Man (not in the ONS layer) as context rings,
#     converted to BNG with bng.py
#
# At run time the demo downloads the monthly 12 km rainfall grids for the
# last 12 months (Met Office provisional files, netCDF) and averages them
# over these same cell lists, so the totals and the averages use identical
# cells.
#
# Sources (download into one directory first):
#   ctyua.geojson   ONS Open Geography (OGL v3): Counties and Unitary
#     Authorities (December 2024) Boundaries UK BUC, outSR=27700:
#     https://services1.arcgis.com/ESMARspQHYMw9BZ9/arcgis/rest/services/
#       Counties_and_Unitary_Authorities_December_2024_Boundaries_UK_BUC/
#       FeatureServer/0/query?where=1%3D1&outFields=*&outSR=27700&f=geojson
#   normals12.geojson   Met Office (OGL), HadUK-Grid 12 km monthly averages
#     1991-2020, outSR=27700:
#     https://services.arcgis.com/Lq3V5RFuTBC9I7kv/ArcGIS/rest/services/
#       Monthly_Precipitation_Observations_1991_2020_12km/FeatureServer/1/
#       query?where=1%3D1&outFields=*&outSR=27700&f=geojson
#   rain_12km.nc   any HadUK-Grid 12 km monthly rainfall file, for the grid:
#     https://hadleyserver.metoffice.gov.uk/hadobs/hadukgrid/data/2026/
#       rainfall_hadukgrid_uk_12km_mon_202609.nc
#   ne_50m_admin_0_countries.geojson   Natural Earth (public domain)
#
# Needs libnetcdf (ctypes) to read the grid coordinates.
#
# Usage: python3 make_county_data.py <download dir> <natural earth dir>
# ---------------------------------------------------------------------------
import sys, os, json, ctypes
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bng import to_bng

src, nedir = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

# ---- the Met Office grid ----------------------------------------------------
nc = ctypes.CDLL('libnetcdf.so.19')
ncid = ctypes.c_int()
assert nc.nc_open(os.path.join(src, 'rain_12km.nc').encode(), 0, ctypes.byref(ncid)) == 0

def ncvar(name, n):
    vid = ctypes.c_int()
    assert nc.nc_inq_varid(ncid, name.encode(), ctypes.byref(vid)) == 0
    a = (ctypes.c_double * n)()
    assert nc.nc_get_var_double(ncid, vid, a) == 0
    return list(a)

def dimlen(name):
    did, n = ctypes.c_int(), ctypes.c_size_t()
    assert nc.nc_inq_dimid(ncid, name.encode(), ctypes.byref(did)) == 0
    nc.nc_inq_dimlen(ncid, did, ctypes.byref(n))
    return n.value

NX, NY = dimlen('projection_x_coordinate'), dimlen('projection_y_coordinate')
gx, gy = ncvar('projection_x_coordinate', NX), ncvar('projection_y_coordinate', NY)
DX = gx[1] - gx[0]
assert all(abs(gx[i] - gx[0] - i * DX) < 1 for i in range(NX))
assert all(abs(gy[j] - gy[0] - j * DX) < 1 for j in range(NY))

# ---- 1991-2020 normals per land cell ---------------------------------------
normals = {}
for f in json.load(open(os.path.join(src, 'normals12.geojson')))['features']:
    ring = f['geometry']['coordinates'][0][:-1]
    cx = sum(p[0] for p in ring) / len(ring)
    cy = sum(p[1] for p in ring) / len(ring)
    i, j = round((cx - gx[0]) / DX), round((cy - gy[0]) / DX)
    assert abs(gx[i] - cx) < 1 and abs(gy[j] - cy) < 1
    normals[j * NX + i] = [f['properties']['pr' + m] for m in MONTHS]
land = sorted(normals)

# ---- counties ---------------------------------------------------------------
def rings_of(geom):
    polys = geom['coordinates'] if geom['type'] == 'MultiPolygon' else [geom['coordinates']]
    out = []
    for poly in polys:
        for ring in poly:
            out.append(ring[:-1] if ring[0] == ring[-1] else ring)
    return out

def inside(x, y, rings):
    c = False                                   # even-odd: holes work too
    for r in rings:
        n = len(r)
        for k in range(n):
            x1, y1 = r[k]
            x2, y2 = r[(k + 1) % n]
            if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                c = not c
    return c

counties = []
for f in json.load(open(os.path.join(src, 'ctyua.geojson')))['features']:
    p = f['properties']
    rings = rings_of(f['geometry'])
    xs = [q[0] for r in rings for q in r]
    ys = [q[1] for r in rings for q in r]
    cells = [c for c in land
             if min(xs) <= gx[c % NX] <= max(xs) and min(ys) <= gy[c // NX] <= max(ys)
             and inside(gx[c % NX], gy[c // NX], rings)]
    single = not cells
    if single:                                  # small area: the nearest land cell to its label point
        cells = [min(land, key=lambda c: (gx[c % NX] - p['BNG_E']) ** 2 + (gy[c // NX] - p['BNG_N']) ** 2)]
    norm = [sum(normals[c][m] for c in cells) / len(cells) for m in range(12)]
    counties.append(dict(name=p['CTYUA24NM'], code=p['CTYUA24CD'], rings=rings,
                         le=p['BNG_E'], ln=p['BNG_N'], cells=cells, single=single, norm=norm))
counties.sort(key=lambda c: c['name'].lower())

# ---- context: Ireland and the Isle of Man ---------------------------------
ctx = []
for f in json.load(open(os.path.join(nedir, 'ne_50m_admin_0_countries.geojson')))['features']:
    if f['properties'].get('ADM0_A3') in ('IRL', 'IMN'):
        for r in rings_of(f['geometry']):
            ctx.append([to_bng(la, lo) for lo, la in r])

# ---- write ------------------------------------------------------------------
def pas(s):
    return "'" + s.replace("'", "''") + "'"

def arr(name, typ, vals, fmt, per=10):
    items = [fmt % v for v in vals]
    lines = [', '.join(items[i:i + per]) for i in range(0, len(items), per)]
    return '  %s: array[0..%d] of %s = (\n    %s\n  );\n' % (name, len(vals) - 1, typ, ',\n    '.join(lines))

ring_first, ring_start, pe, pn = [0], [0], [], []
cell_first, cells = [0], []
for c in counties:
    for r in c['rings']:
        for x, y in r:
            pe.append(x)
            pn.append(y)
        ring_start.append(len(pe))
    ring_first.append(len(ring_start) - 1)
    cells.extend(c['cells'])
    cell_first.append(len(cells))
ctx_start, ce, cn = [0], [], []
for r in ctx:
    for x, y in r:
        ce.append(x)
        cn.append(y)
    ctx_start.append(len(ce))

with open(os.path.join(here, 'countydata.inc'), 'w', encoding='utf-8') as fh:
    fh.write('// Generated by make_county_data.py - do not edit. Boundaries: ONS Counties and\n'
             '// Unitary Authorities (Dec 2024) BUC, OGL v3. Rainfall averages: Met Office\n'
             '// HadUK-Grid 12 km 1991-2020, OGL. Context: Natural Earth (public domain).\n'
             '// All coordinates British National Grid metres.\n')
    fh.write('const\n  CountyCount = %d;\n  CountyRingCount = %d;\n  CountyPointCount = %d;\n'
             % (len(counties), len(ring_start) - 1, len(pe)))
    fh.write('  GridNX = %d;\n  GridNY = %d;\n  GridX0 = %.1f;\n  GridY0 = %.1f;\n  GridDX = %.1f;\n'
             % (NX, NY, gx[0], gy[0], DX))
    fh.write('  CtxRingCount = %d;\n' % len(ctx))
    fh.write(arr('CountyName', 'string', [pas(c['name']) for c in counties], '%s', 4))
    fh.write(arr('CountyCode', 'string', [pas(c['code']) for c in counties], '%s', 6))
    fh.write(arr('CountyLabelE', 'Single', [c['le'] for c in counties], '%.0f'))
    fh.write(arr('CountyLabelN', 'Single', [c['ln'] for c in counties], '%.0f'))
    fh.write(arr('CountySingleCell', 'Boolean', [c['single'] for c in counties], '%s'))
    fh.write(arr('CountyRingFirst', 'Integer', ring_first, '%d'))
    fh.write(arr('CountyRingStart', 'Integer', ring_start, '%d'))
    fh.write(arr('CountyPtE', 'Single', pe, '%.1f'))
    fh.write(arr('CountyPtN', 'Single', pn, '%.1f'))
    fh.write(arr('CountyCellFirst', 'Integer', cell_first, '%d'))
    fh.write(arr('CountyCells', 'Integer', cells, '%d'))
    fh.write('  // county c, calendar month m (1..12): CountyNormal[c * 12 + m - 1], mm\n')
    fh.write(arr('CountyNormal', 'Single', [v for c in counties for v in c['norm']], '%.2f', 12))
    fh.write(arr('CtxRingStart', 'Integer', ctx_start, '%d'))
    fh.write(arr('CtxE', 'Single', ce, '%.0f'))
    fh.write(arr('CtxN', 'Single', cn, '%.0f'))

single = [c['name'] for c in counties if c['single']]
print('%d counties, %d rings, %d points; %d land cells; %d counties on one nearest cell'
      % (len(counties), len(ring_start) - 1, len(pe), len(land), len(single)))
print('annual 1991-2020 average, mm: Kent %.0f, Highland %.0f, Cornwall %.0f'
      % tuple(sum(c['norm']) for n in ('Kent', 'Highland', 'Cornwall') for c in counties if c['name'] == n))
