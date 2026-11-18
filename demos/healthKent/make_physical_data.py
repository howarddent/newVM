#!/usr/bin/env python3
# This file is part of newVM.
# Copyright (C) 2026 Howard Dent
# SPDX-License-Identifier: GPL-3.0-or-later
#
# newVM is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your
# option) any later version. It is distributed WITHOUT ANY WARRANTY; see
# the file LICENSE at the top of the repository for details.

# ---------------------------------------------------------------------------
# Generates physicaldata.inc for the healthKent demo's physical map
# (uKentRelief.pas includes it):
#
#   - Height: Ordnance Survey Terrain 50 (OGL), the 50 m ASCII grid (a
#     terrain model: ground, not buildings or trees), averaged 2 x 2 onto a
#     100 m grid over Kent and Medway's district box, in decimetres.
#       https://api.os.uk/downloads/v1/products/Terrain50/downloads
#         ?area=GB&format=ASCII+Grid+and+GML+%28Grid%29&redirect
#       -> terr50_gagg_gb.zip (162 MB; the TQ and TR tiles are used)
#   - Rivers: OpenStreetMap (ODbL) via the Overpass API, waterway = river
#     or canal, converted to BNG with bng.py and simplified:
#       [out:json][timeout:180];(way["waterway"~"^(river|canal)$"]
#       (50.88,-0.05,51.52,1.48););out tags geom;   -> osm_rivers.json
#     (overpass-api.de refuses curl's default user agent: pass -A.)
#
# Usage: python3 make_physical_data.py <physical dir> <healthKent src dir>
#   <physical dir> holds terr50_gagg_gb.zip and osm_rivers.json,
#   <healthKent src dir> lad_bfc.geojson (for the box), as for make_kent_data.py
# ---------------------------------------------------------------------------
import sys, os, json, math, zipfile, io
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bng import to_bng

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

phys, src = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
CELL = 100                 # m
MARGIN = 1000              # m round the districts' box
RIVER_SIMPLIFY_M = 20.0
# drawn heavier: the county's main rivers
MAIN_RIVERS = {'River Medway', 'Medway', 'River Thames', 'Great Stour', 'River Stour',
               'River Rother', 'Darent', 'River Beult', 'River Eden', 'River Teise'}

# ---- the box --------------------------------------------------------------------
lad = json.load(open(os.path.join(src, 'lad_bfc.geojson')))
xs, ys = [], []
for f in lad['features']:
    g = f['geometry']
    polys = g['coordinates'] if g['type'] == 'MultiPolygon' else [g['coordinates']]
    for p in polys:
        for r in p:
            for x, y in r:
                xs.append(x); ys.append(y)
E0 = math.floor((min(xs) - MARGIN) / 1000) * 1000
N0 = math.floor((min(ys) - MARGIN) / 1000) * 1000
E1 = math.ceil((max(xs) + MARGIN) / 1000) * 1000
N1 = math.ceil((max(ys) + MARGIN) / 1000) * 1000
nc, nr = (E1 - E0) // CELL, (N1 - N0) // CELL
print('box E %d..%d N %d..%d, %d x %d cells' % (E0, E1, N0, N1, nc, nr))

# ---- Terrain 50, 50 m, onto a fine grid then 2 x 2 means --------------------------
fine = np.full(((N1 - N0) // 50, (E1 - E0) // 50), np.nan)
outer = zipfile.ZipFile(os.path.join(phys, 'terr50_gagg_gb.zip'))
LETTERS = {'tq': (500000, 100000), 'tr': (600000, 100000)}
used = 0
for name in outer.namelist():
    base = os.path.basename(name)
    if not base.endswith('.zip') or base[:2] not in LETTERS:
        continue
    oe, on = LETTERS[base[:2]]
    te, tn = oe + int(base[2]) * 10000, on + int(base[3]) * 10000
    if te + 10000 <= E0 or te >= E1 or tn + 10000 <= N0 or tn >= N1:
        continue
    inner = zipfile.ZipFile(io.BytesIO(outer.read(name)))
    asc = [n for n in inner.namelist() if n.lower().endswith('.asc')][0]
    lines = inner.read(asc).decode().splitlines()
    hdr = {l.split()[0].lower(): float(l.split()[1]) for l in lines[:5]}
    a = np.array([[float(v) for v in l.split()] for l in lines[5:5 + int(hdr['nrows'])]])
    a = a[::-1]                                     # south row first
    x0, y0 = int(hdr['xllcorner']), int(hdr['yllcorner'])
    for j in range(a.shape[0]):
        fy = (y0 + 50 * j - N0) // 50
        if not 0 <= fy < fine.shape[0]:
            continue
        fx0 = (x0 - E0) // 50
        lo, hi = max(0, -fx0), min(a.shape[1], fine.shape[1] - fx0)
        if lo < hi:
            fine[fy, fx0 + lo:fx0 + hi] = a[j, lo:hi]
    used += 1
print('tiles used', used)
fine = np.where(np.isnan(fine), 0.0, fine)
h = fine.reshape(nr, 2, nc, 2).mean(axis=(1, 3))
h = np.clip(h, -10, 3000)
print('height %.1f .. %.1f m' % (h.min(), h.max()))
iy, ix = np.unravel_index(np.argmax(h), h.shape)
print('highest cell centre E %d N %d' % (E0 + CELL * ix + CELL // 2, N0 + CELL * iy + CELL // 2))
dm = np.round(h * 10).astype(int)

# ---- rivers ---------------------------------------------------------------------
osm = json.load(open(os.path.join(phys, 'osm_rivers.json')))
rivers = []
for e in osm['elements']:
    g = e.get('geometry')
    if not g or len(g) < 2:
        continue
    pts = [to_bng(p['lat'], p['lon']) for p in g]
    pts = [(round(x), round(y)) for x, y in dp(pts, RIVER_SIMPLIFY_M)]
    if not any(E0 <= x <= E1 and N0 <= y <= N1 for x, y in pts):
        continue
    name = e['tags'].get('name', '')
    kind = 0 if name in MAIN_RIVERS else 1
    rivers.append((kind, pts))
rivers.sort(key=lambda r: -r[0])        # minor first, main rivers on top
print('rivers', len(rivers), 'points', sum(len(p) for _, p in rivers))

# ---- write ----------------------------------------------------------------------
def arr(name, typ, vals, fmt, per=10):
    items = [fmt % v for v in vals]
    lines = [','.join(items[i:i + per]) for i in range(0, len(items), per)]
    return '  %s: array[0..%d] of %s = (\n    %s\n  );\n' % (name, len(vals) - 1, typ, ',\n    '.join(lines))

rs, re_, rn, rk = [0], [], [], []
for kind, pts in rivers:
    for x, y in pts:
        re_.append(x); rn.append(y)
    rs.append(len(re_)); rk.append(kind)

with open(os.path.join(here, 'physicaldata.inc'), 'w', encoding='utf-8') as fh:
    fh.write('{ Generated by make_physical_data.py - do not edit.\n'
             '  Height: OS Terrain 50 (Ordnance Survey, Open Government Licence),\n'
             '  averaged onto a %d m grid, decimetres, row 0 the southern edge.\n'
             '  Rivers: OpenStreetMap contributors (ODbL), waterway = river or canal. }\n' % CELL)
    fh.write('const\n')
    fh.write('  ReliefE0 = %d;\n  ReliefN0 = %d;\n  ReliefCell = %d;\n' % (E0, N0, CELL))
    fh.write('  ReliefCols = %d;\n  ReliefRows = %d;\n' % (nc, nr))
    fh.write('  RiverCount = %d;\n' % len(rivers))
    fh.write(arr('ReliefDm', 'SmallInt', dm.ravel().tolist(), '%d', 40))
    fh.write(arr('RiverKind', 'Byte', rk, '%d', 40))
    fh.write(arr('RiverStart', 'Integer', rs, '%d', 20))
    fh.write(arr('RiverPtE', 'Single', re_, '%d', 16))
    fh.write(arr('RiverPtN', 'Single', rn, '%d', 16))
print('wrote', os.path.join(here, 'physicaldata.inc'), os.path.getsize(os.path.join(here, 'physicaldata.inc')), 'bytes')
