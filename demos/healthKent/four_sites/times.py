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

# LSOA -> every candidate site and LSOA -> each hospital, one scenario
import sys, os, numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import make_drive_data as M
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra
from scipy.spatial import cKDTree
sc = int(sys.argv[1])
E, nn, xy, cand, stamp = M.build_graph(os.path.expanduser('~/data/healthKent-src/roads/drive_roads.json'))
sites = cand[M.land_mask(xy[cand, 0:1], xy[cand, 1:2]).ravel()]
tree = cKDTree(xy[cand])
def snap(P):
    dd, k = tree.query(P)
    return cand[k], dd / 1000 / M.ACCESS_KMH * 60
LE, LN = M.lsoa_labels()
ln, la = snap(np.c_[LE, LN])
v = M.scenario_speed(E, sc)
W = E['L'] / 1000 / v * 60
G = coo_matrix((W, (E['R'], E['C'])), shape=(nn, nn)).tocsr()
GT = coo_matrix((W, (E['C'], E['R'])), shape=(nn, nn)).tocsr()
lt = []
for name, full, lat, lon in M.HOSPITALS:
    e, n = M.to_bng(lat, lon)
    s, extra = snap(np.array([[e, n]]))
    lt.append(dijkstra(GT, indices=int(s[0]))[ln] + la + extra[0])
T = np.zeros((len(ln), len(sites)), np.float32)
for b in range(0, len(ln), 64):
    idx = np.arange(b, min(b + 64, len(ln)))
    T[idx] = (dijkstra(G, indices=ln[idx])[:, sites] + la[idx, None])
    print(sc, b, flush=True)
np.save('T%d.npy' % sc, T)
np.savez('meta%d.npz' % sc, hosp=np.array(lt), sites=sites, sxy=xy[sites], LE=LE, LN=LN)
print('done', T.shape, np.isfinite(T).all())
