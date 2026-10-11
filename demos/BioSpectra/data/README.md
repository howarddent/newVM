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

## VitalDB: frontal EEG under anaesthesia (the "Anaesthesia EEG" tab)

| File | Contents |
|---|---|
| `vitaldb_655_eeg.csv` | three 20 s excerpts of `BIS/EEG1_WAV` (BIS Vista frontal EEG, uV, 128 Hz) as columns: awake before induction (from 745 s), propofol maintenance (1890 s), burst suppression (8594 s) |
| `vitaldb_655_eeg300.csv` | 300 s of each state for the bispectrum tab, each containing its 20 s excerpt: awake 745-1045 s, propofol 1890-2190 s, burst suppression 8314-8614 s (ending with its excerpt: the recording has a 16 s gap from 8619 s). The awake window avoids 1000-1300 s, which carries ECG artefact (spikes once a second; bicoherence ~0.9 everywhere) |
| `vitaldb_655_trend.csv` | every 10 s over the whole case: BIS, SQI, suppression ratio, propofol and remifentanil effect-site concentrations (Orchestra TCI); BIS/SQI/SR blank while SQI is 0 |
| `vitaldb_655_case.txt` | the case's row of the VitalDB case table (demographics, operation, times) |
| `fetch_vitaldb.py` | re-creates the three files above (standard library only) |

Source: [VitalDB](https://vitaldb.net), case 655 - also published on
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
