# Signal excerpts for the BioSpectra demo

Twenty-second excerpts of PhysioNet records, fetched by HTTP range request
so the demo runs offline and the repo stays small. Both records are WFDB
format 212 (two 12-bit samples packed in three bytes, signals interleaved),
decoded by `ubiospectramain.pas`'s `LoadWFDB212`.

| File | Source | Signals used | fs | Excerpt |
|---|---|---|---|---|
| `100_60s_20s.dat`, `100.hea` | MIT-BIH Arrhythmia Database (`mitdb/1.0.0`), record 100 | MLII (ECG) | 360 Hz | 60 s to 80 s |
| `slp01a_600s_20s.dat`, `slp01a.hea` | MIT-BIH Polysomnographic Database (`slpdb/1.0.0`), record slp01a | BP (invasive arterial), EEG (C4-A1) | 250 Hz | 600 s to 620 s |

Byte ranges: record 100 has 2 signals, so 3 bytes per frame - 60 s is
frame 21600, byte 64800, and 20 s is 7200 frames = 21600 bytes. slp01a has
4 signals, 6 bytes per frame - 600 s is frame 150000, byte 900000, and
20 s is 5000 frames = 30000 bytes. The `.hea` files are the records'
complete, unmodified headers.

Re-fetch with:

    B=https://physionet.org/files
    curl -o 100.hea    $B/mitdb/1.0.0/100.hea
    curl -o slp01a.hea $B/slpdb/1.0.0/slp01a.hea
    curl -r 64800-86399   -o 100_60s_20s.dat    $B/mitdb/1.0.0/100.dat
    curl -r 900000-929999 -o slp01a_600s_20s.dat $B/slpdb/1.0.0/slp01a.dat

Both databases are published under the Open Data Commons Attribution
License v1.0. Citations: Moody GB, Mark RG. The impact of the MIT-BIH
Arrhythmia Database. IEEE Eng in Med and Biol 20(3):45-50 (2001).
Ichimaru Y, Moody GB. Development of the polysomnographic database on
CD-ROM. Psychiatry and Clinical Neurosciences 53:175-177 (1999).
Goldberger AL et al. PhysioBank, PhysioToolkit, and PhysioNet.
Circulation 101(23):e215-e220 (2000).
