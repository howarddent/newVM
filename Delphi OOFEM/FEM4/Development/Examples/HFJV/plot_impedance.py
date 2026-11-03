"""Plots the respiratory system's impedance against frequency, from the
CSV files `hfjvrun --zfile=<file>` writes (with --lumped, --box, or the
torso), one curve per file.

Top: resistance, bottom: reactance, both below the jet (Zrs, what the jet
works against) - the upper airway, which the jet bypasses on the way in,
is left out. The bottom axis is in Hz, the top in breaths per minute, and
the user's 200 /min is marked; resonance is where Xrs crosses zero.

Usage: python3 plot_impedance.py <out.png> <label>=<csv> [<label>=<csv> ...]
"""
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

# the reference categorical order, plus a line style for each so identity
# isn't colour alone
COLOURS = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100']
STYLES = ['-', '--', ':', '-.']
INK, MUTED, GRID = '#1f1f1e', '#6b6a64', '#e4e3df'


def main():
    out = sys.argv[1]
    series = []
    for a in sys.argv[2:]:
        label, fn = a.split('=', 1)
        d = np.genfromtxt(fn, delimiter=',', names=True)
        series.append((label, d))

    plt.rcParams.update({'font.size': 10, 'axes.edgecolor': MUTED,
                         'axes.labelcolor': INK, 'xtick.color': MUTED,
                         'ytick.color': MUTED})
    fig, (ar, ax) = plt.subplots(2, 1, figsize=(9, 7), sharex=True)
    for i, (label, d) in enumerate(series):
        # resonance: first upward zero crossing of Xrs
        x = d['Xrs']; f = d['f_Hz']
        k = np.where((x[:-1] < 0) & (x[1:] >= 0))[0]
        fr = None
        if len(k):
            k = k[0]
            fr = f[k] - x[k] * (f[k + 1] - f[k]) / (x[k + 1] - x[k])
            label += ', resonance %.1f Hz (%.0f /min)' % (fr, 60 * fr)
        kw = dict(color=COLOURS[i], ls=STYLES[i], lw=2, label=label)
        ar.plot(d['f_Hz'], d['Rrs'], **kw)
        ax.plot(d['f_Hz'], d['Xrs'], **kw)
        if fr is not None:
            ax.plot(fr, 0, 'o', ms=8, color=COLOURS[i], mec='white', mew=2, zorder=5)

    for a in (ar, ax):
        a.grid(True, color=GRID, lw=0.8)
        a.set_axisbelow(True)
        for s in ('top', 'right'):
            a.spines[s].set_visible(False)
        a.axvline(200 / 60, color=MUTED, lw=1, ls=(0, (2, 2)))
    ax.axhline(0, color=MUTED, lw=1)
    ax.text(200 / 60, 1.4, ' 200 /min', va='top', color=MUTED, fontsize=9)
    # the compliance's -1/(wC) runs off below 1 Hz; the abdomen's effects
    # are in the few tenths around zero
    ax.set_ylim(-3, 1.5)
    ar.set_ylabel('resistance Rrs, cmH2O/(L/s)')
    ax.set_ylabel('reactance Xrs, cmH2O/(L/s)')
    ax.set_xlabel('frequency, Hz')
    ax.set_xlim(0, series[0][1]['f_Hz'].max())
    ar.legend(frameon=False, loc='lower right', fontsize=9)

    top = ar.secondary_xaxis('top', functions=(lambda f: 60 * f, lambda r: r / 60))
    top.set_xlabel('jet rate, breaths per minute')
    top.set_ticks([60, 120, 200, 300, 400, 600, 800, 1000, 1200])

    fig.suptitle('Respiratory impedance below the jet, supine adult male', color=INK)
    fig.text(0.5, 0.005, 'Lung, airways below the jet, chest wall and abdomen. '
             'Dots: resonance (Xrs = 0). Reactance clipped at -3: it falls to -8 at 0.25 Hz.', ha='center', color=MUTED, fontsize=9)
    fig.tight_layout(rect=(0, 0.02, 1, 1))
    fig.savefig(out, dpi=110)
    print('Wrote', out)


if __name__ == '__main__':
    main()
