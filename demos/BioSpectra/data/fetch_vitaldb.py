#!/usr/bin/env python3
"""Re-create the VitalDB files for BioSpectra's anaesthesia EEG tab.

    python3 fetch_vitaldb.py        (writes into the current directory)

Case 655 of VitalDB (Lee H-C et al., Sci Data 9:279, 2022; CC BY 4.0),
fetched from the open VitalDB web API (no login): api.vitaldb.net/cases and
/trks list the cases and each case's track ids, and api.vitaldb.net/<tid>
returns one track as gzipped CSV. Waves come one row per sample on an
implicit 1/fs grid (the Time column is filled only on the first and last
rows); numerics come with their own times. Needs only the standard library.
"""
import csv, gzip, io, math, urllib.request

CASE = '655'
FS = 128                       # BIS Vista EEG
EXCERPTS = [('awake', 745), ('propofol', 1890), ('burst_suppression', 8594)]   # s from case start
LEN = 20                       # s
# 300 s of each state for the bispectrum tab (299 epochs of 2 s at 50 %
# overlap), each containing its 20 s excerpt: awake and propofol start
# with theirs; burst suppression ends with its, since the recording has a
# 16 s gap from 8619 s. The awake window also avoids 1000-1300 s, which
# carries ECG artefact (spikes once a second, bicoherence ~0.9 everywhere).
LONG = [('awake', 745), ('propofol', 1890), ('burst_suppression', 8314)]
LONG_LEN = 300                 # s
TREND_STEP = 10                # s
TREND = [('BIS', 'BIS/BIS'), ('SQI', 'BIS/SQI'), ('SR', 'BIS/SR'),
         ('PPF_CE', 'Orchestra/PPF20_CE'), ('RFTN_CE', 'Orchestra/RFTN20_CE')]
CASE_FIELDS = ['age', 'sex', 'height', 'weight', 'bmi', 'asa', 'department', 'optype', 'dx',
               'opname', 'approach', 'position', 'ane_type', 'casestart', 'caseend',
               'anestart', 'aneend', 'opstart', 'opend']


def get(path):
    d = urllib.request.urlopen('https://api.vitaldb.net/' + path, timeout=600).read()
    try:
        d = gzip.decompress(d)
    except OSError:
        pass
    return d.decode('utf-8-sig')


def numeric(tid):
    out = []
    for row in list(csv.reader(io.StringIO(get(tid))))[1:]:
        if len(row) > 1 and row[0] and row[1]:
            out.append((float(row[0]), float(row[1])))
    return out


def interp(series, t):
    # linear, NaN outside the recorded span
    if not series or t < series[0][0] or t > series[-1][0]:
        return math.nan
    lo, hi = 0, len(series) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if series[mid][0] <= t: lo = mid
        else: hi = mid
    (t0, v0), (t1, v1) = series[lo], series[hi]
    return v0 if t1 == t0 else v0 + (v1 - v0) * (t - t0) / (t1 - t0)


case = [r for r in csv.DictReader(io.StringIO(get('cases'))) if r['caseid'] == CASE][0]
tids = {r['tname']: r['tid'] for r in csv.DictReader(io.StringIO(get('trks'))) if r['caseid'] == CASE}

# EEG excerpts
rows = list(csv.reader(io.StringIO(get(tids['BIS/EEG1_WAV']))))[1:]
eeg = [float(r[1]) if len(r) > 1 and r[1] else math.nan for r in rows]
cols = []
for name, start in EXCERPTS:
    seg = eeg[start * FS:(start + LEN) * FS]
    assert len(seg) == LEN * FS and not any(math.isnan(v) for v in seg), name
    cols.append(seg)
with open('vitaldb_%s_eeg.csv' % CASE, 'w') as f:
    f.write('# VitalDB case %s, track BIS/EEG1_WAV (BIS Vista frontal EEG, uV), %d Hz\n' % (CASE, FS))
    f.write('# %d s excerpts starting at (s from case start): %s\n'
            % (LEN, ', '.join('%s %d' % e for e in EXCERPTS)))
    f.write(','.join(n for n, _ in EXCERPTS) + '\n')
    for i in range(LEN * FS):
        f.write(','.join('%g' % c[i] for c in cols) + '\n')

cols = []
for name, start in LONG:
    seg = eeg[start * FS:(start + LONG_LEN) * FS]
    assert len(seg) == LONG_LEN * FS and not any(math.isnan(v) for v in seg), name
    cols.append(seg)
with open('vitaldb_%s_eeg300.csv' % CASE, 'w') as f:
    f.write('# VitalDB case %s, track BIS/EEG1_WAV (BIS Vista frontal EEG, uV), %d Hz\n' % (CASE, FS))
    f.write('# %d s excerpts starting at (s from case start): %s\n'
            % (LONG_LEN, ', '.join('%s %d' % e for e in LONG)))
    f.write(','.join(n for n, _ in LONG) + '\n')
    for i in range(LONG_LEN * FS):
        f.write(','.join('%g' % c[i] for c in cols) + '\n')

# trend
tr = {k: numeric(tids[t]) for k, t in TREND}
with open('vitaldb_%s_trend.csv' % CASE, 'w') as f:
    f.write('# VitalDB case %s, numerics every %d s (linear interpolation; empty = not recorded)\n'
            % (CASE, TREND_STEP))
    f.write('# BIS, SQI (%) and SR (suppression ratio, %) from the BIS Vista; PPF_CE and RFTN_CE are\n')
    f.write('# the Orchestra TCI pumps\' propofol (ug/ml) and remifentanil (ng/ml) effect-site concentrations;\n')
    f.write('# BIS/SQI/SR are left empty where SQI is 0 (no EEG yet: the monitor reports 0, not "none")\n')
    f.write('time_s,' + ','.join(k for k, _ in TREND) + '\n')
    t = 0
    while t <= float(case['caseend']):
        vals = [interp(tr[k], t) for k, _ in TREND]
        if not vals[1] > 0:          # SQI 0 (or none): no EEG - BIS/SQI/SR mean nothing
            vals[0] = vals[1] = vals[2] = math.nan
        f.write('%d,' % t + ','.join('' if math.isnan(v) else '%.2f' % v for v in vals) + '\n')
        t += TREND_STEP

with open('vitaldb_%s_case.txt' % CASE, 'w') as f:
    f.write('caseid: %s\n' % CASE)
    for k in CASE_FIELDS:
        f.write('%s: %s\n' % (k, case[k]))
print('done')
