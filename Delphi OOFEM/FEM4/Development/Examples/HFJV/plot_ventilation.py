"""Plots minute ventilation against jet rate, from the CSV files
`hfjvrun --vfile=<file>` writes (with --lumped, --box, or the torso), one
curve per file.

Top: minute ventilation VE = f VT, against the jet's own gas per minute
(its flow while open times the fraction of time open) - the rest is
entrained through the upper airway. Bottom: the tidal volume against the
anatomical dead space; once VT falls below VD, bulk flow no longer
reaches the alveoli and gas exchange relies on augmented dispersion, so
VE overstates the useful ventilation there.

Usage: python3 plot_ventilation.py <out.png> <label>=<csv> [<label>=<csv> ...]
       [--setting=<text>]  (subtitle, default '2 bar, I:E 1:1, Biro cannula')
       [--legend=<text>]   (legend title, default 'abdomen')
       The first file sets the dead-space crossing that is shaded.
"""
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

COLOURS = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100']
STYLES = ['-', '--', ':', '-.']
INK, MUTED, GRID = '#1f1f1e', '#6b6a64', '#e4e3df'


def main():
    opts = dict(a[2:].split('=', 1) for a in sys.argv[1:] if a.startswith('--'))
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    out = args[0]
    series = []
    for a in args[1:]:
        label, fn = a.split('=', 1)
        series.append((label, np.genfromtxt(fn, delimiter=',', names=True)))

    plt.rcParams.update({'font.size': 10, 'axes.edgecolor': MUTED,
                         'axes.labelcolor': INK, 'xtick.color': MUTED,
                         'ytick.color': MUTED})
    fig, (av, at) = plt.subplots(2, 1, figsize=(9, 7.5), sharex=True,
                                 gridspec_kw={'height_ratios': [3, 2]})
    for i, (label, d) in enumerate(series):
        r = d['rate_min']
        kw = dict(color=COLOURS[i], ls=STYLES[i], lw=2, label=label)
        av.plot(r, r * d['VT_mL'] / 1000, **kw)
        at.plot(r, d['VT_mL'], **kw)

    d = series[0][1]
    r = d['rate_min']
    jet = r * d['jet_mL'] / 1000          # the same for every abdomen
    av.plot(r, jet, color=MUTED, lw=1.2, ls=(0, (4, 3)))
    av.text(r[-1], jet[-1], 'jet gas alone ', ha='right', va='bottom',
            color=MUTED, fontsize=9)
    vd = d['VD_mL'][0]
    at.axhline(vd, color=MUTED, lw=1.2, ls=(0, (4, 3)))
    at.text(r[-1], vd, 'dead space %.0f mL ' % vd, ha='right', va='bottom',
            color=MUTED, fontsize=9)
    # where the torso's VT crosses the dead space
    vt = d['VT_mL']
    k = np.where((vt[:-1] >= vd) & (vt[1:] < vd))[0]
    if len(k):
        k = k[0]
        rc = r[k] + (vd - vt[k]) * (r[k + 1] - r[k]) / (vt[k + 1] - vt[k])
        for a in (av, at):
            a.axvspan(rc, r[-1], color='#f3f2ee', zorder=0)
        at.text(rc, at.get_ylim()[1] * 0.97, '  VT < dead space', va='top',
                color=MUTED, fontsize=9)

    for a in (av, at):
        a.grid(True, color=GRID, lw=0.8)
        a.set_axisbelow(True)
        for s in ('top', 'right'):
            a.spines[s].set_visible(False)
        a.axvline(200, color=MUTED, lw=1, ls=(0, (2, 2)))
    av.text(200, 2, ' 200 /min', va='bottom', color=MUTED, fontsize=9)
    av.set_ylim(bottom=0)
    at.set_ylim(bottom=0)
    av.set_ylabel('minute ventilation VE = f VT, L/min')
    at.set_ylabel('tidal volume VT, mL')
    at.set_xlabel('jet rate, breaths per minute')
    at.set_xlim(r[0], r[-1])
    av.legend(frameon=False, loc='lower right', fontsize=9, title=opts.get('legend', 'abdomen'),
              title_fontsize=9)

    fig.suptitle('Minute ventilation against jet rate, supine adult male\n'
                 + opts.get('setting', '2 bar, I:E 1:1, Biro cannula'), color=INK)
    fig.tight_layout()
    fig.savefig(out, dpi=110)
    print('Wrote', out)


if __name__ == '__main__':
    main()
