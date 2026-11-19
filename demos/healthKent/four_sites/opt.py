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

# 4 sites each serving ~1/4 of Kent and Medway's population, least total
# population-weighted drive time: existing hospitals (all 35 choices of 4 of 7)
# and any road point (capacitated p-median, location-allocation + swaps)
import sys, os, itertools, numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import make_drive_data as M
from scipy.optimize import milp, LinearConstraint, Bounds
from scipy.sparse import lil_matrix, csr_matrix
sc = int(sys.argv[1]); TOL = float(sys.argv[2]) if len(sys.argv) > 2 else 0.10
pop = M.kent_arr('LsoaPop', 'Integer'); P = pop.sum(); n = len(pop)
m = np.load('meta%d.npz' % sc); H = m['hosp'].T          # n x 7
T = np.load('T%d.npy' % sc, mmap_mode='r'); sxy = m['sxy']
names = [h[0] for h in M.HOSPITALS]
lo, hi = (1 - TOL) * P / 4, (1 + TOL) * P / 4

def allocate(C):
    """C: n x 4 times. Binary assignment, each site's population in [lo, hi]."""
    k = C.shape[1]
    c = (pop[:, None] * C).ravel()
    A1 = csr_matrix((np.ones(n * k), (np.repeat(np.arange(n), k), np.arange(n * k))), shape=(n, n * k))
    A2 = csr_matrix((np.repeat(pop, k), (np.tile(np.arange(k), n), np.arange(n * k))), shape=(k, n * k))
    r = milp(c, constraints=[LinearConstraint(A1, 1, 1), LinearConstraint(A2, lo, hi)],
             integrality=np.ones(n * k), bounds=Bounds(0, 1), options={'time_limit': 60})
    if r.x is None:
        return None, np.inf
    a = r.x.reshape(n, k).argmax(1)
    return a, (pop * C[np.arange(n), a]).sum()

def show(label, C, a, cols):
    tot = (pop * C[np.arange(n), a]).sum()
    print('%s  mean %.2f min' % (label, tot / P))
    for j, nm in enumerate(cols):
        s = a == j
        print('   %-28s pop %7d (%4.1f %%)  mean %5.1f  max %5.1f' % (nm, pop[s].sum(), 100 * pop[s].sum() / P,
              (pop[s] * C[s, j]).sum() / pop[s].sum(), C[s, j].max()))

print('scenario', M.SCENARIOS[sc], 'population', P, 'band', int(lo), int(hi))
res = []
for S in itertools.combinations(range(7), 4):
    C = H[:, S]
    a, tot = allocate(C)
    near = (pop * C.min(1)).sum()
    res.append((tot, near, S, a))
res.sort(key=lambda r: r[0])
print('\nexisting, capacitated (top 6) | unconstrained nearest')
for tot, near, S, a in res[:6]:
    print('  %6.2f  %6.2f  %s' % (tot / P, near / P, ', '.join(names[i] for i in S)))
best_ex = res[0]
show('\nbest existing four, capacitated', H[:, best_ex[2]], best_ex[3], [names[i] for i in best_ex[2]])
un = min(res, key=lambda r: r[1]); C = H[:, un[2]]
show('best existing four, nearest (no capacity)', C, C.argmin(1), [names[i] for i in un[2]])

# ---- free sites --------------------------------------------------------------
Tf = np.asarray(T)                                  # n x S
def one_median(s):
    return int(np.argmin(pop[s] @ Tf[s]))
def solve(start):
    F = list(start)
    last = None
    for it in range(30):
        a, tot = allocate(Tf[:, F])
        G = [one_median(a == j) for j in range(4)]
        if G == F:
            break
        F = G
    return F, a, tot
# starts: the best existing four (snapped), and k-means-like seeds
from scipy.spatial import cKDTree
tr = cKDTree(sxy)
starts = []
for _, _, S, _ in res[:5]:
    hx = [M.to_bng(M.HOSPITALS[i][2], M.HOSPITALS[i][3]) for i in S]
    starts.append([int(tr.query(p)[1]) for p in hx])
rng = np.random.default_rng(1)
for _ in range(10):
    starts.append(list(rng.choice(Tf.shape[1], 4, replace=False)))
best = None
for st in starts:
    F, a, tot = solve(st)
    if best is None or tot < best[2]:
        best = (F, a, tot)
    print('  start -> %.3f' % (tot / P), flush=True)
# swaps: each site against every candidate within 8 km, keep improvements
F, a, tot = best
improved = True
while improved:
    improved = False
    for j in range(4):
        near = tr.query_ball_point(sxy[F[j]], 8000)
        near = rng.choice(near, min(300, len(near)), replace=False)
        for c in near:
            G = F.copy(); G[j] = int(c)
            b, t2 = allocate(Tf[:, G])
            if t2 < tot - 1e-6:
                G2, b2, t3 = solve(G)
                F, a, tot = (G2, b2, t3) if t3 < t2 else (G, b, t2)
                improved = True
                print('  swap -> %.3f' % (tot / P), flush=True)
                break
labels = []
for j in range(4):
    e, nn_ = sxy[F[j]]
    d = [np.hypot(*(np.array(M.to_bng(h[2], h[3])) - (e, nn_))) / 1000 for h in M.HOSPITALS]
    k = int(np.argmin(d))
    labels.append('TQ/TR %.0f %.0f (%.1f km from %s)' % (e, nn_, d[k], names[k]))
show('\nideal four, capacitated', Tf[:, F], a, labels)
# unconstrained p-median from the same sites, for comparison
np.savez('ideal%d_%g.npz' % (sc, TOL), F=F, a=a, xy=sxy[F], ex=np.array(best_ex[2]), exa=best_ex[3])
