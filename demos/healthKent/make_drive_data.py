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
# reversed graph).
#
# Speed scenarios (SCENARIOS), each edge's free-flow speed times a factor:
#   0 free-flow car: the speeds above, no traffic.
#   1 weekday morning peak: PEAK factors by road group and urban/rural.
#     Anchored on DfT's travel time measures for local 'A' roads, year to
#     March 2026: urban 17.6 mph, rural 34.4 mph (all-day, flow-weighted),
#     23.3 mph in the weekday morning peak against 24.6 all day - average
#     speeds including junction delays. The motorway and trunk factors
#     are assumed. The A/B factors (0.61 urban, 0.88 rural) put this
#     model's length-weighted A/B road speeds at 16.6 and 32.4 mph, DfT's
#     all-day 17.6 and 34.4 times the peak's 23.3/24.6. Urban: a tagged limit of 30 mph or less; rural: 40 or
#     more; untagged, the nearest LSOA's density (URBAN_DENSITY).
#   2 blue light: BLUE x the free-flow speed, at most BLUE_CAP_DUAL on
#     motorways and dual trunk roads and BLUE_CAP elsewhere - ambulances
#     are largely exempt from the traffic (Rehn et al., Emerg Med J 2017,
#     London: 46 km/h on blue lights against 20 driving normally; Green
#     Beacon pilot, Rural Remote Health 2020: 1.26x normal driving on
#     rural roads). Traffic is ignored.
# No junction delays beyond those, no turn costs.
#
# Isochrones: the same times on a 500 m grid, lightly smoothed (3x3 mean over cells near a road) so
# the snapping doesn't make them ragged, contoured at 15, 30, 45 and 60
# minutes (contourpy) and simplified to 60 m; cells off Kent's land (by the
# district rings, as the map) or more than 1.5 km from a road are masked out. The map draws them on land only.
#
# Choices ("domains"): each hospital, the nearer (in time) of William Harvey
# and Kent and Canterbury, the nearest of all of them, and the best single
# site (below).
#
# Best single site: for each speed scenario, the network node in Kent and
# Medway (motorways and trunk roads excluded, as for joining points) with the
# lowest admissions-weighted mean drive time from every LSOA - one forward
# Dijkstra per LSOA, about 4 minutes a scenario. The weights are each LSOA's
# expected heart attack and stroke admissions, written by
# `healthKent --events=<file.csv>`. Also written: the outlines of the sites
# within 2 and 5 minutes of the best mean (BEST_ZONES), contoured on the
# same grid as the isochrones.
#
# Usage: python3 make_drive_data.py <drive_roads.json> <events.csv>
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
# road groups for the scenario factors
GROUP = {'motorway': 0, 'motorway_link': 0, 'trunk': 1, 'trunk_link': 1,
         'primary': 2, 'primary_link': 2, 'secondary': 2, 'secondary_link': 2,
         'tertiary': 3, 'tertiary_link': 3, 'unclassified': 3,
         'residential': 4, 'living_street': 4}
GROUP_NAME = ['motorway', 'trunk', 'A/B road', 'minor', 'residential']
# weekday morning peak, fraction of free-flow speed: (urban, rural)
PEAK = [(0.80, 0.85), (0.70, 0.85), (0.61, 0.88), (0.65, 0.85), (0.80, 0.90)]
URBAN_DENSITY = 1500          # people per km2, for edges with no speed limit tag
BLUE = 1.25
BLUE_CAP_DUAL = 113           # km/h (70 mph)
BLUE_CAP = 100
SCENARIOS = ['free-flow car', 'weekday morning peak', 'blue light']
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
BEST_ZONES = [2, 5]           # minutes above the best site's mean
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
    idx, xy, R, C, Lm, V, Gp, Urb, Dual, minor = {}, [], [], [], [], [], [], [], [], set()
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
        urb = -1                                  # unknown: decided by density
        if m:
            v = min(v, 0.95 * int(m.group(1)) * 1.609)
            urb = 1 if int(m.group(1)) <= 30 else 0
        dual = hw.startswith('motorway') or (hw.startswith('trunk') and t.get('oneway') == 'yes')
        if hw == 'trunk' and t.get('oneway') != 'yes':
            v = min(v, 72)
        ow, jn = t.get('oneway'), t.get('junction')
        fwd = True
        back = not (ow in ('yes', 'true', '1') or jn in ('roundabout', 'circular') or hw.startswith('motorway'))
        if ow == '-1':
            fwd, back = False, True
        ns = [node(a, g) for a, g in zip(w['nodes'], w['geometry'])]
        for a, b in zip(ns, ns[1:]):
            L = math.dist(xy[a], xy[b])
            for x, y, ok in ((a, b, fwd), (b, a, back)):
                if ok:
                    R.append(x); C.append(y); Lm.append(L); V.append(v)
                    Gp.append(GROUP[hw]); Urb.append(urb); Dual.append(dual)
        if not hw.startswith(('motorway', 'trunk')):
            minor.update(ns)
    n = len(xy)
    xy = np.array(xy)
    E = dict(R=np.array(R), C=np.array(C), L=np.array(Lm), V=np.array(V),
             G=np.array(Gp), U=np.array(Urb), D=np.array(Dual))
    # untagged edges: urban if the nearest LSOA label point's area is dense
    dens = kent_arr('LsoaPop', 'Integer') / kent_arr('LsoaLandKm2')
    LE, LN = lsoa_labels()
    mid = 0.5 * (xy[E['R']] + xy[E['C']])
    _, k = cKDTree(np.c_[LE, LN]).query(mid)
    E['U'] = np.where(E['U'] >= 0, E['U'], (dens[k] >= URBAN_DENSITY).astype(int))
    G = coo_matrix((E['L'], (E['R'], E['C'])), shape=(n, n)).tocsr()
    nc, lab = connected_components(G, directed=True, connection='strong')
    big = np.bincount(lab).argmax()
    cand = np.array([a for a in sorted(minor) if lab[a] == big])
    print('nodes', n, 'edges', len(E['R']), 'joinable', len(cand), 'urban', E['U'].mean())
    return E, n, xy, cand, d.get('osm3s', {}).get('timestamp_osm_base', '')


def scenario_speed(E, sc):
    v = E['V'].astype(float)
    if sc == 1:
        f = np.array(PEAK)[E['G'], 1 - E['U']]
        v = v * f
    elif sc == 2:
        v = np.minimum(v * BLUE, np.where(E['D'], BLUE_CAP_DUAL, BLUE_CAP))
    return v


def report_speeds(E, v, label):
    # length-weighted mean speed by group and urban/rural, mph
    out = []
    for g in range(len(GROUP_NAME)):
        for u, un in ((1, 'urban'), (0, 'rural')):
            m = (E['G'] == g) & (E['U'] == u)
            if m.any():
                out.append('%s %s %.1f' % (GROUP_NAME[g], un, np.sum(E['L'][m]) / np.sum(E['L'][m] / v[m]) / 1.609))
    print(label + ' (mph, length-weighted): ' + '; '.join(out))


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


def read_events(path):
    import csv
    rows = list(csv.DictReader(open(path)))
    w = np.zeros(len(rows))
    for r in rows:
        w[int(r['i'])] = float(r['events'])
    return w


def best_site(E, v, nn, ln, la, w, sites):
    # admissions-weighted mean time from every LSOA to every node
    G = coo_matrix((E['L'] / 1000 / v * 60, (E['R'], E['C'])), shape=(nn, nn)).tocsr()
    S = np.zeros(nn)
    for b in range(0, len(ln), 64):
        idx = np.arange(b, min(b + 64, len(ln)))
        S += w[idx] @ (dijkstra(G, indices=ln[idx]) + la[idx, None])
    mean = S / w.sum()
    k = sites[np.argmin(mean[sites])]
    return k, mean


def smooth(T, far):
    # 3x3 mean over the cells near a road only, so the sea's large access
    # times don't leak into the coast
    T = np.where(np.isfinite(T), T, 999.0)
    ok = (~far).astype(float)
    P = np.pad(np.where(far, 0.0, T), 1)
    Q = np.pad(ok, 1)
    num = sum(P[i:i + T.shape[0], j:j + T.shape[1]] for i in range(3) for j in range(3))
    den = sum(Q[i:i + T.shape[0], j:j + T.shape[1]] for i in range(3) for j in range(3))
    S = np.where(far, 999.0, num / np.maximum(den, 1))
    return np.ma.masked_array(S, mask=far)


def main(path, events):
    E, nn, xy, cand, stamp = build_graph(path)
    w = read_events(events)
    sites = cand[land_mask(xy[cand, 0:1], xy[cand, 1:2]).ravel()]
    print('events', w.sum(), 'candidate sites', len(sites))
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

    all_l, iso = [], []    # all_l[scenario][domain]; iso (scenario, domain, minutes, points)
    best, zones = [], []   # best (E, N, mean) per scenario; zones (scenario, extra minutes, points)
    for sc, scname in enumerate(SCENARIOS):
        v = scenario_speed(E, sc)
        report_speeds(E, v, scname)
        W = E['L'] / 1000 / v * 60
        GT = coo_matrix((W, (E['C'], E['R'])), shape=(nn, nn)).tocsr()   # reversed
        lt, gt = [], []
        for name, full, lat, lon in HOSPITALS:
            e, n = to_bng(lat, lon)
            s, extra = snap(np.array([[e, n]]))
            dist = dijkstra(GT, indices=int(s[0]))
            lt.append(dist[ln] + la + extra[0])
            gt.append((dist[gnod] + gacc + extra[0]).reshape(GE.shape))
            print('  %-20s LSOA %.1f..%.1f min' % (name, lt[-1].min(), lt[-1].max()))
        lt = np.array(lt)
        assert np.isfinite(lt).all()
        # the best single site
        k, mean = best_site(E, v, nn, ln, la, w, sites)
        best.append((xy[k, 0], xy[k, 1], mean[k]))
        print('  best single site E %.0f N %.0f, mean %.2f min' % best[-1])
        dist = dijkstra(GT, indices=int(k))
        bl = dist[ln] + la
        bg = (dist[gnod] + gacc).reshape(GE.shape)
        cg = contourpy.contour_generator(ge, gn, smooth(mean[gnod].reshape(GE.shape), far), corner_mask=True)
        for extra in BEST_ZONES:
            for line in cg.lines(mean[k] + extra):
                pts = simplify(np.asarray(line), 60.0)
                if len(pts) >= 2:
                    zones.append((sc, extra, pts))
        # the two combined choices, then the best site
        all_l.append(list(lt) + [np.minimum(lt[WHH], lt[KCH]), lt.min(axis=0), bl])
        dom_g = gt + [np.minimum(gt[WHH], gt[KCH]), np.min(gt, axis=0), bg]
        iso += [(sc,) + x for x in isochrones(dom_g, ge, gn, far)]
    print('isochrone lines', len(iso), 'points', sum(len(x[3]) for x in iso))
    write(all_l, iso, best, zones, stamp)


def isochrones(dom_g, ge, gn, far):
    iso = []    # (domain, minutes, points)
    for dmn, T in enumerate(dom_g):
        cg = contourpy.contour_generator(ge, gn, smooth(T, far), corner_mask=True)
        for lev in LEVELS:
            for line in cg.lines(lev):
                pts = simplify(np.asarray(line), 60.0)
                if len(pts) >= 2:
                    iso.append((dmn, lev, pts))
    return iso


def write(all_l, iso, best, zones, stamp):
    out = os.path.join(here, 'drivedata.inc')
    def arr(name, typ, vals, fmt, per=12):
        rows = [', '.join(fmt % v for v in vals[i:i + per]) for i in range(0, len(vals), per)]
        return '  %s: array[0..%d] of %s = (\n    %s\n  );\n' % (name, len(vals) - 1, typ, ',\n    '.join(rows))
    pas = lambda s: "'" + s.replace("'", "''") + "'"
    with open(out, 'w') as fh:
        fh.write('// generated by make_drive_data.py - do not edit\n')
        fh.write('// drive times (minutes) to Kent and Medway''s acute hospitals, three speed scenarios\n')
        fh.write('// OpenStreetMap (c) OpenStreetMap contributors, ODbL\n')
        fh.write('const\n')
        fh.write('  DriveOsmTimestamp = %s;\n' % pas(stamp))
        fh.write('  HospitalCount = %d;\n' % len(HOSPITALS))
        fh.write('  DriveDomainCount = %d;\n' % len(all_l[0]))
        fh.write('  DriveScenarioCount = %d;\n' % len(SCENARIOS))
        fh.write('  DriveHospWHH = %d;\n  DriveHospKCH = %d;\n' % (WHH, KCH))
        fh.write('  DriveNearestDomain = %d;\n  DriveBestDomain = %d;\n' % (len(HOSPITALS) + 1, len(HOSPITALS) + 2))
        fh.write(arr('DriveScenarioName', 'string', [pas(x) for x in SCENARIOS], '%s', 3))
        fh.write(arr('HospitalShort', 'string', [pas(h[0]) for h in HOSPITALS], '%s', 4))
        fh.write(arr('HospitalName', 'string', [pas(h[1]) for h in HOSPITALS], '%s', 2))
        hb = [to_bng(h[2], h[3]) for h in HOSPITALS]
        fh.write(arr('HospitalE', 'Single', [p[0] for p in hb], '%.0f'))
        fh.write(arr('HospitalN', 'Single', [p[1] for p in hb], '%.0f'))
        # per LSOA: [(scenario * DriveDomainCount + domain) * LsoaCount + i]
        fh.write(arr('LsoaDriveMin', 'Single', [float(v) for dl in all_l for T in dl for v in T], '%.2f'))
        fh.write(arr('IsoScenario', 'Byte', [x[0] for x in iso], '%d', 30))
        fh.write(arr('IsoDomain', 'Byte', [x[1] for x in iso], '%d', 30))
        fh.write(arr('IsoMinutes', 'Byte', [x[2] for x in iso], '%d', 30))
        starts = [0]
        for x in iso:
            starts.append(starts[-1] + len(x[3]))
        fh.write('  IsoCount = %d;\n' % len(iso))
        fh.write(arr('IsoStart', 'Integer', starts, '%d', 16))
        fh.write(arr('IsoPtE', 'Single', [float(q[0]) for x in iso for q in x[3]], '%.0f'))
        fh.write(arr('IsoPtN', 'Single', [float(q[1]) for x in iso for q in x[3]], '%.0f'))
        # best single site per scenario, and the zones within BEST_ZONES minutes of it
        fh.write(arr('BestSiteE', 'Single', [b[0] for b in best], '%.0f'))
        fh.write(arr('BestSiteN', 'Single', [b[1] for b in best], '%.0f'))
        fh.write(arr('BestSiteMean', 'Single', [b[2] for b in best], '%.2f'))
        fh.write('  BestZoneCount = %d;\n' % len(zones))
        fh.write(arr('BestZoneScenario', 'Byte', [z[0] for z in zones], '%d', 30))
        fh.write(arr('BestZoneExtra', 'Byte', [z[1] for z in zones], '%d', 30))
        zs = [0]
        for z in zones:
            zs.append(zs[-1] + len(z[2]))
        fh.write(arr('BestZoneStart', 'Integer', zs, '%d', 16))
        fh.write(arr('BestZonePtE', 'Single', [float(q[0]) for z in zones for q in z[2]], '%.0f'))
        fh.write(arr('BestZonePtN', 'Single', [float(q[1]) for z in zones for q in z[2]], '%.0f'))
    print('wrote', out, os.path.getsize(out), 'bytes')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
