"""Plots the mean subglottic (tracheal) pressure against jet frequency, from
the CSV files `hfjvrun --vfile=<file>` writes, one curve per file.

The subglottic pressure is p_t, the tracheal node where the jet enters,
below the glottis. Its mean is what the jet's gas needs to get out
through the glottis and upper airway: with a linear upper airway it is
R_ua times the mean jet flow at every frequency, while a turbulent
loss makes it depend on how the flow is spread over the cycle.

The bottom axis is in Hz, the top in breaths per minute; 200 /min is
marked.

Usage: python3 plot_pressure.py <out.png> <label>=<csv> [<label>=<csv> ...]
       [--setting=<text>]  (subtitle, default '2 bar, I:E 1:1, Biro cannula')
       [--legend=<text>]   (legend title)
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
    fig, ax = plt.subplots(figsize=(9, 5.5))
    top = 0
    for i, (label, d) in enumerate(series):
        f = d['rate_min'] / 60
        p = d['Ptmean']
        k = np.argmin(np.abs(d['rate_min'] - 200))
        ax.plot(f, p, color=COLOURS[i], ls=STYLES[i], lw=2,
                label='%s  (%.2f at 200 /min)' % (label, p[k]))
        top = max(top, p.max())

    ax.grid(True, color=GRID, lw=0.8)
    ax.set_axisbelow(True)
    for s in ('top', 'right'):
        ax.spines[s].set_visible(False)
    ax.axvline(200 / 60, color=MUTED, lw=1, ls=(0, (2, 2)))
    ax.text(200 / 60, 0.05, ' 200 /min', va='bottom', color=MUTED, fontsize=9)
    ax.set_ylim(0, 1.25 * top)
    ax.set_xlim(series[0][1]['rate_min'][0] / 60, series[0][1]['rate_min'][-1] / 60)
    ax.set_xlabel('jet frequency, Hz')
    ax.set_ylabel('mean subglottic pressure, cmH2O')
    ax.legend(frameon=False, loc='lower right', fontsize=9, title=opts.get('legend'),
              title_fontsize=9)
    sec = ax.secondary_xaxis('top', functions=(lambda f: 60 * f, lambda r: r / 60))
    sec.set_xlabel('jet rate, breaths per minute')
    sec.set_ticks([60, 120, 200, 300, 400, 600, 800])

    fig.suptitle('Mean subglottic airway pressure against jet frequency, supine adult male\n'
                 + opts.get('setting', '2 bar, I:E 1:1, Biro cannula'), color=INK)
    fig.tight_layout()
    fig.savefig(out, dpi=110)
    print('Wrote', out)


if __name__ == '__main__':
    main()
