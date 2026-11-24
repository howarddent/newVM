#!/usr/bin/env python3
"""Plots of aortarun's output.

  plot_aorta.py pulse <beat.csv> <field.txt> <out.png>
      the pressure pulse from the valve to the wrist: waveforms at the
      sites on the way, and pressure against distance and time
  plot_aorta.py sweep <out.png> <label>=<beat.csv> ...
      root, femoral and radial pressure for several aortic elastances
"""
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def load(fn):
    return np.genfromtxt(fn, delimiter=",", names=True)


def fields(fn):
    out = {}
    with open(fn) as f:
        lines = f.read().splitlines()
    i = 0
    while i < len(lines):
        name, nn, nf, dt = lines[i][5:].split(";")
        nf = int(nf)
        x = np.array(lines[i + 1].split(), float)
        p = np.array([l.split() for l in lines[i + 2:i + 2 + nf]], float)
        out[name] = (x, float(dt), p)
        i += 2 + nf
    return out


def foot(t, p):
    """intersecting tangents on the first upstroke"""
    i0 = int(np.argmin(p))
    q = np.roll(p, -i0)
    half = q.min() + 0.5 * (q.max() - q.min())
    n = int(np.argmax(q > half)) + 1
    s = np.diff(q[:n + 1])
    k = int(np.argmax(s))
    dt = t[1] - t[0]
    tf = (i0 + k + 0.5) * dt - (0.5 * (q[k] + q[k + 1]) - q.min()) / (s[k] / dt)
    return tf % (t[-1] - t[0])


def pulse(csv, fld, out):
    d = load(csv)
    t = d["t_s"] * 1000
    sites = [("aortic root", "P_aortic_root", 0.0, "#b2182b"),
             ("aortic arch", "P_aortic_arch", 9.9, "#e08214"),
             ("left subclavian", "P_left_subclavian", 11.6, "#7fbc41"),
             ("left brachial (elbow)", "P_left_brachial_elbow", 55.5, "#2166ac"),
             ("left radial (wrist)", "P_left_radial_wrist", 79.0, "#542788")]
    fig = plt.figure(figsize=(13, 9))
    gs = fig.add_gridspec(2, 2, height_ratios=[1.15, 1])
    ax = fig.add_subplot(gs[0, 0])
    for name, col, dist, c in sites:
        ax.plot(t, d[col], color=c, lw=1.6, label=f"{name}, {dist:.0f} cm")
        tf = foot(d["t_s"], d[col]) * 1000
        ax.plot([tf], [d[col].min()], "v", color=c, ms=6)
    ax.plot(t, d["PLV_mmHg"], color="0.6", lw=1, ls="--", label="left ventricle")
    ax.set_xlabel("time in the cycle, ms"); ax.set_ylabel("pressure, mmHg")
    ax.set_title("Pressure from the valve to the wrist (triangles: foot of the wave)")
    ax.legend(fontsize=8, loc="upper right"); ax.grid(alpha=0.3)

    ax = fig.add_subplot(gs[0, 1])
    ax.plot(t, d["Qvalve_mL_s"], color="k", lw=1.6, label="aortic valve (from the LV model)")
    ax.plot(t, d["Q_thoracic_aorta"], color="#e08214", lw=1.3, label="thoracic aorta")
    ax.plot(t, d["Q_abdominal_aorta"], color="#7fbc41", lw=1.3, label="abdominal aorta")
    ax.plot(t, 10 * d["Q_left_subclavian"], color="#2166ac", lw=1.3, label="left subclavian x 10")
    ax.plot(t, 100 * d["Q_left_radial_wrist"], color="#542788", lw=1.3, label="left radial x 100")
    ax.set_xlabel("time in the cycle, ms"); ax.set_ylabel("flow, mL/s")
    ax.set_title("Flow"); ax.legend(fontsize=8); ax.grid(alpha=0.3)

    f = fields(fld)
    for k, name in enumerate(["valve to left radial", "valve to left common femoral"]):
        x, dt, p = f[name]
        ax = fig.add_subplot(gs[1, k])
        tt = np.arange(p.shape[0]) * dt * 1000
        o = np.argsort(x, kind="stable")
        im = ax.pcolormesh(x[o], tt, p[:, o], cmap="magma", shading="auto")
        fig.colorbar(im, ax=ax, label="mmHg")
        ax.set_xlabel("distance from the valve, cm"); ax.set_ylabel("time in the cycle, ms")
        ax.set_title("Pressure along the path: " + name)
    fig.tight_layout()
    fig.savefig(out, dpi=110)


def sweep(out, pairs):
    cols = ["#2166ac", "#1a9850", "#e08214", "#b2182b", "#542788"]
    fig, ax = plt.subplots(1, 3, figsize=(15, 4.8), sharey=True)
    for k, pr in enumerate(pairs):
        lab, fn = pr.split("=", 1)
        d = load(fn)
        t = d["t_s"] * 1000
        for a, col in zip(ax, ["P_aortic_root", "P_left_common_femoral", "P_left_radial_wrist"]):
            a.plot(t, d[col], color=cols[k % 5], lw=1.5, label=lab)
    for a, ti in zip(ax, ["Aortic root", "Left common femoral", "Left radial (wrist)"]):
        a.set_title(ti); a.set_xlabel("time in the cycle, ms"); a.grid(alpha=0.3)
    ax[0].set_ylabel("pressure, mmHg"); ax[0].legend(title="aortic elastance", fontsize=9)
    fig.tight_layout()
    fig.savefig(out, dpi=110)


if __name__ == "__main__":
    if len(sys.argv) >= 5 and sys.argv[1] == "pulse":
        pulse(sys.argv[2], sys.argv[3], sys.argv[4])
    elif len(sys.argv) >= 4 and sys.argv[1] == "sweep":
        sweep(sys.argv[2], sys.argv[3:])
    else:
        print(__doc__)
