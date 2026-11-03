"""Animates one steady ventilator cycle of the abdominal wall and diaphragm.

Reads the file `hfjvrun --anim=<file>` writes, and saves an animated GIF:

  left   the abdominal cavity seen from the patient's right, in front and
         above, its moving surfaces pushed out along their normals by the
         displacement (exaggerated) and coloured by it - red out, blue in;
  right  above: the front midline's displacement from xiphoid to pubis,
         now (black) and at every frame of the cycle (grey), which shows
         the wave travelling and its envelope;
         below: the lung volume over the cycle, the jet's on-time shaded.

The mean displacement is not in the file: only the oscillation is shown.

Usage: python3 anim_wall.py <anim file> <out.gif> [--exag=<x>] [--fps=<n>]
       (exag 0 = automatic: the largest displacement drawn as 25 mm)
"""
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation, PillowWriter
from mpl_toolkits.mplot3d.art3d import Poly3DCollection


def read(fn):
    with open(fn) as f:
        head = f.readline().split()
        info = {head[i]: float(head[i + 1]) for i in range(0, len(head), 2)}
        n = int(f.readline().split()[1])
        P = np.array([list(map(float, f.readline().split())) for _ in range(n)])
        m = int(f.readline().split()[1])
        T = np.array([list(map(int, f.readline().split())) for _ in range(m)])
        nm = int(f.readline().split()[1])
        rows = [f.readline().split() for _ in range(nm)]
        node = np.array([int(r[0]) for r in rows])
        clamped = np.array([int(r[1]) for r in rows], bool)
        eta = np.array([list(map(float, r[2:])) for r in rows]) * 1e-6   # m
        vl = np.array(list(map(float, f.readline().split()[1:])))       # mL
    return info, P, T[:, :3], T[:, 3], node, clamped, eta, vl


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = dict(a[2:].split('=') for a in sys.argv[1:] if a.startswith('--'))
    info, P, T, S, node, clamped, eta, vl = read(args[0])
    box = int(info.get('box', 0)) == 1
    nf = eta.shape[1]
    # plotting axes: across, along the body, up
    if box:
        Q = P[:, [1, 0, 2]]
    else:
        Q = P[:, [0, 2, 1]]

    # displacement per mesh node per frame (zero on rigid nodes)
    D = np.zeros((len(P), nf))
    D[node] = eta
    # outward vertex normals, area weighted, from the moving triangles
    tri = Q[T]
    fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    N = np.zeros_like(Q)
    for k in range(3):
        np.add.at(N, T[:, k], fn)
    N /= np.maximum(np.linalg.norm(N, axis=1), 1e-30)[:, None]
    # the axis swap reverses the triangles' orientation, so make sure the
    # normals point out: away from the centroid on average
    c = Q.mean(axis=0)
    if np.mean(np.sum((Q[node] - c) * N[node], axis=1)) < 0:
        N = -N

    emax = np.abs(eta).max()
    exag = float(opts.get('exag', 0)) or 0.025 / emax
    lim = np.abs(eta).max()

    # front midline: wall nodes near x = 0 on the upper half
    wall_nodes = np.unique(T[S == 1].ravel())
    if box:
        sel = wall_nodes[np.abs(Q[wall_nodes, 0] - np.median(Q[:, 0])) < 0.012]
    else:
        sel = wall_nodes[(np.abs(Q[wall_nodes, 0]) < 0.010) &
                         (Q[wall_nodes, 2] > np.median(Q[:, 2]))]
    sel = sel[np.argsort(Q[sel, 1])]
    zm = Q[sel, 1]
    # one value per 5 mm of height, the node nearest the midline
    bins = np.round(zm / 0.005)
    keep = []
    for b in np.unique(bins):
        idx = np.where(bins == b)[0]
        keep.append(idx[np.argmin(np.abs(Q[sel[idx], 0]))])
    sel = sel[keep]
    zm = Q[sel, 1]

    rate = info['rate']; Ti = info['ti']; per = info['period']
    t = np.arange(nf) * per / nf

    fig = plt.figure(figsize=(13, 6.5))
    ax3 = fig.add_axes([0.0, 0.02, 0.56, 0.9], projection='3d')
    axw = fig.add_axes([0.62, 0.55, 0.35, 0.36])
    axv = fig.add_axes([0.62, 0.10, 0.35, 0.30])
    cmap = plt.get_cmap('RdBu_r')
    grey = np.array([0.72, 0.72, 0.72, 1.0])
    L = np.array([0.4, -0.5, 0.8]); L /= np.linalg.norm(L)

    lo, hi = Q.min(axis=0), Q.max(axis=0)
    pad = 0.03

    def colours(d, X):
        tr = X[T]
        nrm = np.cross(tr[:, 1] - tr[:, 0], tr[:, 2] - tr[:, 0])
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1), 1e-30)[:, None]
        sh = 0.55 + 0.45 * np.abs(nrm @ L)
        dt = d[T].mean(axis=1)
        col = cmap(0.5 + 0.5 * dt / lim)
        col[S == 0] = grey
        col[:, :3] *= sh[:, None]
        return col

    def draw(j):
        ax3.cla()
        d = D[:, j]
        X = Q + (exag * d)[:, None] * N
        pc = Poly3DCollection(X[T], facecolors=colours(d, X), edgecolor='none')
        ax3.add_collection3d(pc)
        ax3.set_xlim(lo[0] - pad, hi[0] + pad)
        ax3.set_ylim(lo[1] - pad, hi[1] + pad)
        ax3.set_zlim(lo[2] - pad, hi[2] + pad)
        ax3.set_box_aspect(hi - lo + 2 * pad)
        ax3.view_init(28, -35)
        ax3.set_axis_off()
        jet = 'jet ON' if t[j] < Ti * per else 'jet off'
        ax3.set_title('Abdominal wall and diaphragm, %.0f /min, t = %.0f ms (%s)\n'
                      'displacement x%.0f; red outwards, blue inwards, +-%.1f mm'
                      % (rate, 1000 * t[j], jet, exag, 1000 * lim), fontsize=10)

        axw.cla()
        for k in range(nf):
            axw.plot(zm * 1000, D[sel, k] * 1000, color='0.85', lw=0.8)
        axw.plot(zm * 1000, D[sel, j] * 1000, 'k', lw=2)
        axw.axhline(0, color='0.5', lw=0.6)
        axw.set_xlim(zm.min() * 1000, zm.max() * 1000)
        axw.set_ylim(-1.1 * lim * 1000, 1.1 * lim * 1000)
        if box:
            axw.set_xlabel('distance from the diaphragm end, mm')
        else:
            axw.set_xlabel('height above the perineum, mm   (pubis left, xiphoid right)')
        axw.set_ylabel('outward displacement, mm')
        axw.set_title('Front midline', fontsize=10)

        axv.cla()
        axv.axvspan(0, Ti * per * 1000, color='#ffe9b3')
        axv.plot(t * 1000, vl, 'b')
        axv.plot(t[j] * 1000, vl[j], 'bo')
        axv.set_xlim(0, per * 1000)
        axv.set_xlabel('time in cycle, ms   (shaded: jet on)')
        axv.set_ylabel('lung volume, mL')
        axv.set_title('Lung volume (mean removed)', fontsize=10)
        return []

    anim = FuncAnimation(fig, draw, frames=nf, blit=False)
    anim.save(args[1], writer=PillowWriter(fps=int(opts.get('fps', 12))), dpi=80)
    print('Wrote', args[1], '-', nf, 'frames, exaggeration', round(exag), ', max', round(1000 * emax, 2), 'mm')


if __name__ == '__main__':
    main()
