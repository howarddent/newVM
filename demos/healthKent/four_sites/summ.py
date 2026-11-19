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

import sys, os, re, numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import make_drive_data as M
s = open('/home/howard/newVM/demos/healthKent/kentdata.inc').read()
def names(n):
    m = re.search(n + r': array\[0\.\.\d+\] of string = \((.*?)\);', s, re.S)
    return re.findall(r"'((?:[^']|'')*)'", m.group(1))
TN = names('TownName') + names('SmallTownName')
TE = np.r_[M.kent_arr('TownE'), M.kent_arr('SmallTownE')]
TNn = np.r_[M.kent_arr('TownN'), M.kent_arr('SmallTownN')]
def near(e, n):
    d = np.hypot(TE - e, TNn - n); k = d.argmin()
    return '%s %.1f km' % (TN[k].split(',')[0], d[k] / 1000)
def gr(e, n):
    return '%s %05d %05d' % ('TQ' if e < 600000 else 'TR', e % 100000, n % 100000)
pop = M.kent_arr('LsoaPop', 'Integer'); P = pop.sum()
T = [np.load('T%d.npy' % k, mmap_mode='r') for k in range(3)]
H = [np.load('meta%d.npz' % k)['hosp'].T for k in range(3)]
sites = np.load('meta0.npz')['sxy']
for f in sys.argv[1:]:
    z = np.load(f); F, a = z['F'], z['a']
    print(f)
    for j in range(4):
        e, n = z['xy'][j]; sel = a == j
        print('  %s (%s)  pop %d  ' % (gr(e, n), near(e, n), pop[sel].sum()) +
              ' / '.join('%.1f' % ((pop[sel] * T[k][sel, F[j]]).sum() / pop[sel].sum()) for k in range(3)))
    print('  overall, same allocation: ' + ' / '.join('%.2f' % ((pop * np.asarray(T[k][:, F])[np.arange(len(a)), a]).sum() / P) for k in range(3)))
    ex, exa = z['ex'], z['exa']
    print('  existing', [M.HOSPITALS[i][0] for i in ex], ' / '.join('%.2f' % ((pop * H[k][:, ex][np.arange(len(a)), exa]).sum() / P) for k in range(3)))
