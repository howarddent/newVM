"""Fetch the two guitar notes for BioSpectra's "Guitar distortion" tab.

Both are single open-G-string (G3, 196 Hz) notes by the same player,
Freesound user SpeedY, released CC0 (public domain):

  clean      sound 8402  "Clean_G_str_pick.wav"     nylon-string guitar, picked
             https://freesound.org/people/SpeedY/sounds/8402/
  distorted  sound 12038 "Dist_sng_G_3rd_str.wav"   electric guitar, distorted
             https://freesound.org/people/SpeedY/sounds/12038/

Freesound's original-file download needs a login, so this takes the public
high-quality Ogg Vorbis previews from cdn.freesound.org instead (44.1 kHz).
Lossy, but the codec's effects are far above the few kHz the demo looks at.

Each note is decoded, mixed to mono, cut to the first 4 s with a 50 ms
cosine fade-out (so playback doesn't end in a click) and written as a
16-bit mono WAV, the only format the demo reads.

Needs numpy and soundfile (libsndfile >= 1.1 decodes Vorbis):
    python -m pip install numpy soundfile
    python fetch_guitar.py          (from this directory)
"""
import io
import os
import urllib.request

import numpy as np
import soundfile as sf

NOTES = [
    ('guitar_clean_G3.wav',     'https://cdn.freesound.org/previews/8/8402_6479-hq.ogg'),
    ('guitar_distorted_G3.wav', 'https://cdn.freesound.org/previews/12/12038_6479-hq.ogg'),
]
DURATION = 4.0   # s
FADE = 0.05      # s

here = os.path.dirname(os.path.abspath(__file__))
for name, url in NOTES:
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    raw = urllib.request.urlopen(req).read()
    x, fs = sf.read(io.BytesIO(raw), dtype='float64')
    if x.ndim > 1:
        x = x.mean(axis=1)
    x = x[:int(DURATION * fs)].copy()
    nf = int(FADE * fs)
    x[-nf:] *= 0.5 * (1 + np.cos(np.pi * np.arange(nf) / nf))
    x = np.clip(x, -1.0, 32767 / 32768)
    sf.write(os.path.join(here, name), x, fs, subtype='PCM_16')
    print('%s: %d Hz, %.2f s, peak %.3f' % (name, fs, len(x) / fs, np.abs(x).max()))
