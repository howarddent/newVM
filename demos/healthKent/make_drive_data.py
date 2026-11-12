# This file is part of newVM.
# Copyright (C) 2026 Howard Dent
# SPDX-License-Identifier: GPL-3.0-or-later
# ---------------------------------------------------------------------------
# make_drive_data.py - drive times to Kent and Medway's acute hospitals, for
# healthKent: writes drivedata.inc (per-LSOA minutes and isochrone lines).
#
# Roads: OpenStreetMap (ODbL) via the Overpass API, saved as drive_roads.json:
#   [out:json][timeout:500];way["highway"~"^(motorway|motorway_link|trunk|
#   trunk_link|primary|primary_link|secondary|secondary_link|tertiary|
#   tertiary_link|unclassified|residential|living_street)$"]
#   (50.88,-0.05,51.52,1.48);out body geom qt;
#
# Model: a directed graph on the OSM nodes (one-way streets, roundabouts and
# motorways one way), each edge timed at a free-flow car speed for its road
# class (SPEED, km/h), capped at 95 % of a tagged mph limit; single-carriageway
# trunk roads at most 72 km/h. A point joins the network at its nearest
# non-motorway, non-trunk node of the largest strongly connected component,
# at 20 km/h in a straight line. Times are TO each hospital (Dijkstra on the
# reversed graph). No traffic, junction delays or blue-light driving.
#
# Isochrones: the same times on a 500 m grid, lightly smoothed (3x3 mean over cells near a road) so
# the snapping doesn't make them ragged, contoured at 15, 30, 45 and 60
# minutes (contourpy) and simplified to 60 m; cells off Kent's land (by the
# district rings, as the map) or more than 1.5 km from a road are masked out. The map draws them on land only.
#
# Choices ("domains"): each hospital, the nearer (in time) of William Harvey
# and Kent and Canterbury, and the nearest of all of them.
#
# Usage: python3 make_drive_data.py <drive_roads.json>
# ---------------------------------------------------------------------------
import sys, os, json, math, re
import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra, connected_components
from scipy.spatial import cKDTree
import contourpy

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
from bng import to_bng

SPEED = {'motorway': 105, 'motorway_link': 60, 'trunk': 80, 'trunk_link': 50,
         'primary': 65, 'primary_link': 45, 'secondary': 55, 'secondary_link': 40,
         'tertiary': 48, 'tertiary_link': 35, 'unclassified': 40, 'residential': 28,
         'living_street': 15}
ACCESS_KMH = 20
# the acute hospitals of NHS Kent and Medway (main entrance, approximate:
# a few hundred metres)
HOSPITALS = [
    ('Darent Valley', 'Darent Valley Hospital, Dartford', 51.4363, 0.2549),
    ('Medway Maritime', 'Medway Maritime Hospital, Gillingham', 51.3822, 0.5490),
    ('Maidstone', 'Maidstone Hospital', 51.2768, 0.4808),
    ('Tunbridge Wells', 'Tunbridge Wells Hospital, Pembury', 51.1497, 0.3227),
    ('William Harvey', 'William Harvey Hospital, Ashford', 51.1418, 0.9175),
    ('Kent and Canterbury', 'Kent and Canterbury Hospital, Canterbury', 51.2672, 1.0856),
    ('QEQM', 'Queen Elizabeth the Queen Mother Hospital, Margate', 51.3778, 1.3907),
]
WHH, KCH = 4, 5
LEVELS = [15, 30, 45, 60]
GRID = 500.0
BOX = (535000, 660000, 120000, 190000)   # E0, E1, N0, N1


def kent_arr(name, typ='Single'):
    s = open(os.path.join(here, 'kentdata.inc')).read()
    m = re.search(name + r': array\[0\.\.(\d+)\] of ' + typ + r' = \((.*?)\);', s, re.S)
    return np.array([float(v) for v in m.group(2).replace('\n', ' ').split(',')])


def lsoa_labels():
    return kent_arr('LsoaLabelE'), kent_arr('LsoaLabelN')


def land_mask(GE, GN):
    # even-odd over every coastline-clipped district ring, as the map's stencil
    from matplotlib.path import Path
    st = kent_arr('DistrictRingStart', 'Integer').astype(int)
    E, N = kent_arr('DistrictPtE'), kent_arr('DistrictPtN')
    P = np.c_[GE.ravel(), GN.ravel()]
    inside = np.zeros(len(P), bool)
    for r in range(len(st) - 1):
        ring = np.c_[E[st[r]:st[r + 1]], N[st[r]:st[r + 1]]]
        inside ^= Path(ring).contains_points(P)
    return inside.reshape(GE.shape)


def build_graph(path):
    d = json.load(open(path))
    idx, xy, R, C, W, minor = {}, [], [], [], [], set()
    def node(nid, g):
        if nid not in idx:
            idx[nid] = len(xy)
            xy.append(to_bng(g['lat'], g['lon']))
        return idx[nid]
    for w in d['elements']:
        if w['type'] != 'way':
            continue
        t = w.get('tags', {})
        hw = t['highway']
        v = SPEED[hw]
        m = re.match(r'(\d+)\s*mph', t.get('maxspeed', ''))
        if m:
            v = min(v, 0.95 * int(m.group(1)) * 1.609)
        if hw == 'trunk' and t.get('oneway') != 'yes':
            v = min(v, 72)
        ow, jn = t.get('oneway'), t.get('junction')
        fwd = True
        back = not (ow in ('yes', 'true', '1') or jn in ('roundabout', 'circular') or hw.startswith('motorway'))
        if ow == '-1':
            fwd, back = False, True
        ns = [node(a, g) for a, g in zip(w['nodes'], w['geometry'])]
        for a, b in zip(ns, ns[1:]):
            tt = math.dist(xy[a], xy[b]) / 1000 / v * 60
            if fwd:
                R.append(a); C.append(b); W.append(tt)
            if back:
                R.append(b); C.append(a); W.append(tt)
        if not hw.startswith(('motorway', 'trunk')):
            minor.update(ns)
    n = len(xy)
    G = coo_matrix((W, (R, C)), shape=(n, n)).tocsr()
    nc, lab = connected_components(G, directed=True, connection='strong')
    big = np.bincount(lab).argmax()
    cand = np.array([a for a in sorted(minor) if lab[a] == big])
    print('nodes', n, 'edges', len(W), 'joinable', len(cand))
    return G, np.array(xy), cand, d.get('osm3s', {}).get('timestamp_osm_base', '')


def simplify(pts, tol):
    if len(pts) < 3:
        return pts
    a, b = pts[0], pts[-1]
    ab = b - a
    L = np.hypot(*ab)
    if L == 0:
        dd = np.hypot(*(pts - a).T)
    else:
        dd = np.abs(ab[0] * (pts[:, 1] - a[1]) - ab[1] * (pts[:, 0] - a[0])) / L
    k = int(np.argmax(dd))
    if dd[k] <= tol:
        return np.array([a, b])
    return np.vstack([simplify(pts[:k + 1], tol)[:-1], simplify(pts[k:], tol)])


def main(path):
    G, xy, cand, stamp = build_graph(path)
    tree = cKDTree(xy[cand])
    def snap(P):
        dd, k = tree.query(P)
        return cand[k], dd / 1000 / ACCESS_KMH * 60

    LE, LN = lsoa_labels()
    ln, la = snap(np.c_[LE, LN])
    ge = np.arange(BOX[0], BOX[1] + 1, GRID)
    gn = np.arange(BOX[2], BOX[3] + 1, GRID)
    GE, GN = np.meshgrid(ge, gn)
    gnod, gacc = snap(np.c_[GE.ravel(), GN.ravel()])
    # off Kent's land (sea, London, Sussex) or more than 1.5 km from a road:
    # no contours there
    far = (gacc * ACCESS_KMH / 60 > 1.5).reshape(GE.shape) | ~land_mask(GE, GN)

    GT = G.T.tocsr()
    lt, gt = [], []
    for name, full, lat, lon in HOSPITALS:
        e, n = to_bng(lat, lon)
        s, extra = snap(np.array([[e, n]]))
        dist = dijkstra(GT, indices=int(s[0]))
        lt.append(dist[ln] + la + extra[0])
        gt.append((dist[gnod] + gacc + extra[0]).reshape(GE.shape))
        print('%-20s LSOA %.1f..%.1f min' % (name, lt[-1].min(), lt[-1].max()))
    lt = np.array(lt)
    assert np.isfinite(lt).all()
    # the two combined choices
    dom_l = list(lt) + [np.minimum(lt[WHH], lt[KCH]), lt.min(axis=0)]
    dom_g = gt + [np.minimum(gt[WHH], gt[KCH]), np.min(gt, axis=0)]

    iso = []    # (domain, minutes, points)
    for dmn, T in enumerate(dom_g):
        T = np.where(np.isfinite(T), T, 999.0)
        # 3x3 mean over the cells near a road only, so the sea's large
        # access times don't leak into the coast
        ok = (~far).astype(float)
        P = np.pad(np.where(far, 0.0, T), 1)
        Q = np.pad(ok, 1)
        num = sum(P[i:i + T.shape[0], j:j + T.shape[1]] for i in range(3) for j in range(3))
        den = sum(Q[i:i + T.shape[0], j:j + T.shape[1]] for i in range(3) for j in range(3))
        S = np.where(far, 999.0, num / np.maximum(den, 1))
        S = np.ma.masked_array(S, mask=far)
        cg = contourpy.contour_generator(ge, gn, S, corner_mask=True)
        for lev in LEVELS:
            for line in cg.lines(lev):
                pts = simplify(np.asarray(line), 60.0)
                if len(pts) >= 2:
                    iso.append((dmn, lev, pts))
    print('isochrone lines', len(iso), 'points', sum(len(p) for _, _, p in iso))

    out = os.path.join(here, 'drivedata.inc')
    def arr(name, typ, vals, fmt, per=12):
        rows = [', '.join(fmt % v for v in vals[i:i + per]) for i in range(0, len(vals), per)]
        return '  %s: array[0..%d] of %s = (\n    %s\n  );\n' % (name, len(vals) - 1, typ, ',\n    '.join(rows))
    pas = lambda s: "'" + s.replace("'", "''") + "'"
    with open(out, 'w') as fh:
        fh.write('// generated by make_drive_data.py - do not edit\n')
        fh.write('// drive times (minutes, free-flow car) to Kent and Medway''s acute hospitals\n')
        fh.write('// OpenStreetMap (c) OpenStreetMap contributors, ODbL\n')
        fh.write('const\n')
        fh.write('  DriveOsmTimestamp = %s;\n' % pas(stamp))
        fh.write('  HospitalCount = %d;\n' % len(HOSPITALS))
        fh.write('  DriveDomainCount = %d;\n' % len(dom_l))
        fh.write('  DriveHospWHH = %d;\n  DriveHospKCH = %d;\n' % (WHH, KCH))
        fh.write(arr('HospitalShort', 'string', [pas(h[0]) for h in HOSPITALS], '%s', 4))
        fh.write(arr('HospitalName', 'string', [pas(h[1]) for h in HOSPITALS], '%s', 2))
        hb = [to_bng(h[2], h[3]) for h in HOSPITALS]
        fh.write(arr('HospitalE', 'Single', [p[0] for p in hb], '%.0f'))
        fh.write(arr('HospitalN', 'Single', [p[1] for p in hb], '%.0f'))
        # per LSOA, domain-major: [domain * LsoaCount + i]
        fh.write(arr('LsoaDriveMin', 'Single', [float(v) for T in dom_l for v in T], '%.2f'))
        fh.write(arr('IsoDomain', 'Byte', [d for d, _, _ in iso], '%d', 30))
        fh.write(arr('IsoMinutes', 'Byte', [m for _, m, _ in iso], '%d', 30))
        starts = [0]
        for _, _, p in iso:
            starts.append(starts[-1] + len(p))
        fh.write('  IsoCount = %d;\n' % len(iso))
        fh.write(arr('IsoStart', 'Integer', starts, '%d', 16))
        fh.write(arr('IsoPtE', 'Single', [float(q[0]) for _, _, p in iso for q in p], '%.0f'))
        fh.write(arr('IsoPtN', 'Single', [float(q[1]) for _, _, p in iso for q in p], '%.0f'))
    print('wrote', out, os.path.getsize(out), 'bytes')


if __name__ == '__main__':
    main(sys.argv[1])
