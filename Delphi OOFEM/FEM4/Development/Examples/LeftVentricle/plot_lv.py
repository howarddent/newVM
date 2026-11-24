#!/usr/bin/env python3
"""Plot one beat written by lvrun --csv: a Wiggers diagram and the
pressure-volume loop.   plot_lv.py beat.csv out.png [title]"""
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = np.genfromtxt(sys.argv[1], delimiter=",", names=True)
t = d["t_s"] * 1000
fig = plt.figure(figsize=(12, 9))
gs = fig.add_gridspec(4, 2, width_ratios=[1.25, 1])
ax = fig.add_subplot(gs[0, 0])
ax.plot(t, d["PLV_mmHg"], "r", label="left ventricle")
ax.plot(t, d["Proot_mmHg"], "k", label="aortic root")
ax.plot(t, d["PLA_mmHg"], "b", label="left atrium")
ax.set_ylabel("pressure (mmHg)"); ax.legend(fontsize=8); ax.grid(alpha=0.3)
ax = fig.add_subplot(gs[1, 0])
ax.plot(t, d["VLV_mL"], "r", label="ventricle")
ax.plot(t, d["VLA_mL"], "b", label="atrium")
ax.set_ylabel("volume (mL)"); ax.legend(fontsize=8); ax.grid(alpha=0.3)
ax = fig.add_subplot(gs[2, 0])
ax.plot(t, d["Qaortic_mL_s"], "k", label="aortic valve")
ax.plot(t, d["Qroot_out_mL_s"], "k--", lw=0.8, label="root outlet")
ax.plot(t, d["Qmitral_mL_s"], "b", label="mitral valve")
ax.set_ylabel("flow (mL/s)"); ax.legend(fontsize=8); ax.grid(alpha=0.3)
ax = fig.add_subplot(gs[3, 0])
ax.plot(t, 2.0 * d["fibre_stretch"], "g")  # ls0 = 2.0 um
ax.set_ylabel("mean sarcomere length (um)", color="g"); ax.grid(alpha=0.3)
ax2 = ax.twinx()
ax2.plot(t, d["active_stress_kPa"], "m")
ax2.set_ylabel("mean active fibre stress (kPa)", color="m")
ax.set_xlabel("time from ventricular depolarisation (ms)")
ax = fig.add_subplot(gs[0:2, 1])
ax.plot(d["VLV_mL"], d["PLV_mmHg"], "r")
ax.set_xlabel("LV volume (mL)"); ax.set_ylabel("LV pressure (mmHg)"); ax.grid(alpha=0.3)
ax.set_title("pressure-volume loop", fontsize=10)
ax = fig.add_subplot(gs[2, 1])
ax.plot(t, d["wall_mm"], "k")
ax.set_ylabel("equatorial wall (mm)"); ax.grid(alpha=0.3)
ax = fig.add_subplot(gs[3, 1])
ax.plot(t, d["twist_deg"] - d["twist_deg"][0], "k", label="apical twist (deg)")
ax.plot(t, 100 * (d["long_axis_mm"] / d["long_axis_mm"][0] - 1), "c", label="long axis change (%)")
ax.legend(fontsize=8); ax.grid(alpha=0.3); ax.set_xlabel("time (ms)")
if len(sys.argv) > 3:
    fig.suptitle(sys.argv[3])
fig.tight_layout()
fig.savefig(sys.argv[2], dpi=110)
