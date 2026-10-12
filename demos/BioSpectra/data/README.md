# Signal excerpts for the BioSpectra demo

Twenty-second excerpts of PhysioNet records, fetched by HTTP range request
so the demo runs offline and the repo stays small. Both records are WFDB
format 212 (two 12-bit samples packed in three bytes, signals interleaved),
decoded by `ubiospectramain.pas`'s `LoadWFDB212`.

| File | Source | Signals used | fs | Excerpt |
|---|---|---|---|---|
| `100_60s_20s.dat`, `100.hea` | MIT-BIH Arrhythmia Database (`mitdb/1.0.0`), record 100 | MLII (ECG) | 360 Hz | 60 s to 80 s |
| `slp01a_600s_20s.dat`, `slp01a.hea` | MIT-BIH Polysomnographic Database (`slpdb/1.0.0`), record slp01a | BP (invasive arterial), EEG (C4-A1) | 250 Hz | 600 s to 620 s |
| `slp01a_600s_300s.dat` | same record | EEG (C4-A1), for the bispectrum tab only | 250 Hz | 600 s to 900 s |

Byte ranges: record 100 has 2 signals, so 3 bytes per frame - 60 s is
frame 21600, byte 64800, and 20 s is 7200 frames = 21600 bytes. slp01a has
4 signals, 6 bytes per frame - 600 s is frame 150000, byte 900000, and
20 s is 5000 frames = 30000 bytes, and 300 s is 75000 frames = 450000 bytes
(the 300 s file starts at the same byte, so its first 20 s are the 20 s
file exactly). The `.hea` files are the records' complete, unmodified
headers.

Re-fetch with:

    B=https://physionet.org/files
    curl -o 100.hea    $B/mitdb/1.0.0/100.hea
    curl -o slp01a.hea $B/slpdb/1.0.0/slp01a.hea
    curl -r 64800-86399   -o 100_60s_20s.dat    $B/mitdb/1.0.0/100.dat
    curl -r 900000-929999 -o slp01a_600s_20s.dat $B/slpdb/1.0.0/slp01a.dat
    curl -r 900000-1349999 -o slp01a_600s_300s.dat $B/slpdb/1.0.0/slp01a.dat

Both databases are published under the Open Data Commons Attribution
License v1.0. Citations: Moody GB, Mark RG. The impact of the MIT-BIH
Arrhythmia Database. IEEE Eng in Med and Biol 20(3):45-50 (2001).
Ichimaru Y, Moody GB. Development of the polysomnographic database on
CD-ROM. Psychiatry and Clinical Neurosciences 53:175-177 (1999).
Goldberger AL et al. PhysioBank, PhysioToolkit, and PhysioNet.
Circulation 101(23):e215-e220 (2000).

## VitalDB: frontal EEG under anaesthesia and sedation (the "Anaesthesia EEG" and "Anaesthesia bispectrum" tabs)

| File | Contents |
|---|---|
| `vitaldb_655_eeg.csv` | three 20 s excerpts of `BIS/EEG1_WAV` (BIS Vista frontal EEG, uV, 128 Hz) as columns: awake before induction (from 745 s), propofol maintenance (1890 s), burst suppression (8594 s) |
| `vitaldb_655_eeg300.csv` | 300 s of each state for the bispectrum tab, each containing its 20 s excerpt: awake 745-1045 s, propofol 1890-2190 s, burst suppression 8314-8614 s (ending with its excerpt: the recording has a 16 s gap from 8619 s). The awake window avoids 1000-1300 s, which carries ECG artefact (spikes once a second; bicoherence ~0.9 everywhere) |
| `vitaldb_655_trend.csv` | every 10 s over the whole case: BIS, SQI, suppression ratio, propofol and remifentanil effect-site concentrations (Orchestra TCI); BIS/SQI/SR blank while SQI is 0 |
| `vitaldb_655_case.txt` | the case's row of the VitalDB case table (demographics, operation, times) |
| `vitaldb_574_eeg.csv` | the sedated state: one 20 s excerpt of `BIS/EEG1_WAV` from case 574, from 3440 s (SQI 100 %) |
| `vitaldb_574_eeg300.csv` | 300 s of the sedated state, 3300-3600 s, containing that excerpt |
| `vitaldb_574_trend.csv`, `vitaldb_574_case.txt` | case 574's trend and case-table row, as for case 655 |
| `fetch_vitaldb.py` | re-creates all eight files (standard library only) |

Source: [VitalDB](https://vitaldb.net), cases 655 and 574 - also published on
PhysioNet as `vitaldb/1.0.0` - fetched through VitalDB's open web API
(`api.vitaldb.net/cases`, `/trks`, `/<track id>`; no login). Licence
CC BY 4.0. Citation: Lee HC, Park Y, Yoon SB, Yang SM, Park D, Jung CW.
VitalDB, a high-fidelity multi-parameter vital signs database in surgical
patients. Sci Data 9:279 (2022).

How case 655 was chosen (2026-10-11): of VitalDB's general anaesthetics
with the BIS EEG, BIS/SQI and an Orchestra propofol pump, aged 18-65, with
recording begun before the anaesthetic did, the cases were ranked by the
length of awake EEG (BIS > 85, SQI > 50, before the propofol Ce first
exceeds 0.2) and six were scored on the EEG itself - the cleanest awake
20 s (smallest 99th-percentile amplitude) and, in maintenance (BIS 35-55,
SQI > 85, Ce > 2), the strongest 8-14 Hz alpha against 16-24 Hz beta.
Case 655 led on both (21 uV, alpha 14.8 dB over beta) with 15 minutes
awake. It also reached burst suppression later (SR up to 65 %), and the
excerpt is the 20 s of highest suppression ratio with SQI > 70.

How case 574 was chosen (2026-10-11), for a sedated state at BIS 70-90:
VitalDB lists 72 cases as "Sedationalgesia". 50 of them have the raw BIS
EEG and an Orchestra propofol pump. Counting the time each spent at BIS
70-90 with SQI >= 50 while propofol was running gave about 26 hours in
all, with 31 cases holding at least 10 minutes. Case 574 (67-year-old
woman, removal of a peritoneal dialysis catheter) has two hours of it.
From about 1800 s to 5000 s its propofol Ce is held at 1.0 ug/ml and its
remifentanil Ce at 1.0 ng/ml, with BIS 82-86, SQI ~95 % and no volatile
agent or nitrous oxide (Primus MAC and FiN2O both 0). That is sedation
with an opioid, not propofol alone.

Within that stretch, 300 s windows every 150 s were checked for
artefact. Those starting at 2400, 2550, 3000, 3150 and 3600 s each hold a
single huge spike: kurtosis over 1000 and bicoherence ~0.7 everywhere.
3300-3600 s is clean, with kurtosis 3.4 and mean bicoherence 0.053, at
the 1/sqrt(299) = 0.058 bias floor. Its first 20 s had SQI only 60-80 %,
so the 20 s excerpt is taken from 3440 s, where SQI is 100 %. The band
powers and bicoherence were cross-checked in numpy.

## Guitar notes (the "Guitar distortion" tab)

| File | Contents |
|---|---|
| `guitar_clean_G3.wav` | open G string (G3, 196 Hz), picked, clean nylon-string guitar - first 4 s |
| `guitar_distorted_G3.wav` | open G string, electric guitar through heavy distortion - first 4 s |
| `fetch_guitar.py` | re-creates both (needs `numpy` and `soundfile`) |

Both are by the same player, Freesound user
[SpeedY](https://freesound.org/people/SpeedY/), released **CC0** (public
domain): sound [8402](https://freesound.org/people/SpeedY/sounds/8402/)
"Clean_G_str_pick.wav" from the pack *Nylon Guitar Single notes*, and
sound [12038](https://freesound.org/people/SpeedY/sounds/12038/)
"Dist_sng_G_3rd_str.wav" from *Distorted Guitar Single Notes*. Chosen
(2026-10-12) as a matched pair - same string, same pitch, same player -
so the difference between them is mostly the amplification. Not
entirely: the clean note is an acoustic nylon-string guitar and the
distorted one an electric, which is why the tab also offers the clean
note through a linear gain and through a simulated `tanh` overdrive.

Freesound's original-file downloads need a login, so the script takes
the public HQ Ogg Vorbis previews (`cdn.freesound.org/previews/...`,
44.1 kHz), decodes them, keeps the first 4 s with a 50 ms cosine
fade-out and writes 16-bit mono PCM WAV. Checked in numpy: both have
their fundamental at 196 Hz (the distorted note's 2nd and 3rd harmonics
are stronger than it); the clean note decays to 4 % of its peak within
2 s, the distorted one sustains, with 42 % of its power above 1 kHz
against 0.6 %.
