"""Plots entrainment against jet frequency, from the CSV files
`hfjvrun --vfile=<file>` writes, one curve per file.

Entrainment is the gas drawn in through the upper airway (and glottis)
each cycle - the inward part of the upper-airway flow; over a cycle more
leaves than enters, since the jet's own gas leaves that way too. Top:
the entrainment rate, the volume per cycle times the frequency, in
L/min. Bottom: the entrainment ratio, entrained over jet gas.

--bench=<L/min> draws the cannula's bench entrainment into open air
(total minus jet flow, while the jet is open) times Ti, the mean over
the cycle with no load against it.

Usage: python3 plot_entrainment.py <out.png> <label>=<csv> [<label>=<csv> ...]
       [--bench=<L/min while open>] [--ti=<fraction>] (0.5)
       [--setting=<text>] [--legend=<text>]
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
    fig, (ae, ar) = plt.subplots(2, 1, figsize=(9, 7.5), sharex=True,
                                 gridspec_kw={'height_ratios': [3, 2]})
    for i, (label, d) in enumerate(series):
        f = d['rate_min'] / 60
        rate = d['rate_min'] * d['entrained_mL'] / 1000      # L/min
        ratio = d['entrained_mL'] / d['jet_mL']
        k = np.argmin(np.abs(d['rate_min'] - 200))
        kw = dict(color=COLOURS[i], ls=STYLES[i], lw=2)
        ae.plot(f, rate, label='%s  (%.1f L/min at 200 /min)' % (label, rate[k]), **kw)
        ar.plot(f, ratio, **kw)

    if 'bench' in opts:
        b = float(opts['bench']) * float(opts.get('ti', 0.5))
        ae.axhline(b, color=MUTED, lw=1.2, ls=(0, (4, 3)))
        ae.text(series[0][1]['rate_min'][-1] / 60, b,
                'bench, open air: %.1f L/min ' % b, ha='right', va='bottom',
                color=MUTED, fontsize=9)

    for a in (ae, ar):
        a.grid(True, color=GRID, lw=0.8)
        a.set_axisbelow(True)
        for s in ('top', 'right'):
            a.spines[s].set_visible(False)
        a.axvline(200 / 60, color=MUTED, lw=1, ls=(0, (2, 2)))
        a.set_ylim(bottom=0)
    ae.text(200 / 60, 0.5, ' 200 /min', va='bottom', color=MUTED, fontsize=9)
    ae.set_ylabel('entrainment rate, L/min')
    ar.set_ylabel('entrained / jet gas')
    ar.set_xlabel('jet frequency, Hz')
    ar.set_xlim(series[0][1]['rate_min'][0] / 60, series[0][1]['rate_min'][-1] / 60)
    ae.legend(frameon=False, loc='lower right', fontsize=9, title=opts.get('legend'),
              title_fontsize=9)
    sec = ae.secondary_xaxis('top', functions=(lambda f: 60 * f, lambda r: r / 60))
    sec.set_xlabel('jet rate, breaths per minute')
    sec.set_ticks([60, 120, 200, 300, 400, 600, 800])

    fig.suptitle('Entrainment against jet frequency, supine adult male\n'
                 + opts.get('setting', '2 bar, I:E 1:1, Biro cannula'), color=INK)
    fig.tight_layout()
    fig.savefig(out, dpi=110)
    print('Wrote', out)


if __name__ == '__main__':
    main()
