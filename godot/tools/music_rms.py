"""The songs' loudness for the sound effects (scripts/audio/sfx.gd keeps every sound well under the music playing then):
for each level, data/levels/levelN_rms.json = the music's RMS in dBFS (both channels) over 0.5 s centred on every 1/32 s.
  python tools/music_rms.py        (needs ffmpeg on the PATH and numpy)"""
import json
import os
import subprocess

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
RATE = 22050
DT = 1.0 / 32.0
WIN = 0.5

for lv in range(1, 10):
    path = os.path.join(PROJECT, "data", "levels", "level%d.json" % lv)
    if not os.path.exists(path):
        continue
    audio = json.load(open(path, encoding="utf-8"))["audio"].replace("res://", PROJECT + "/")
    pcm = subprocess.run(["ffmpeg", "-v", "error", "-i", audio, "-ac", "2", "-ar", str(RATE), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(pcm, dtype=np.float32).astype(np.float64).reshape(-1, 2)
    sq = np.concatenate([[0.0], np.cumsum((x ** 2).mean(axis=1))])  # running sum of the mean square
    half = int(WIN * RATE / 2)
    out = []
    for k in range(int(len(x) / RATE / DT) + 1):
        c = int(k * DT * RATE)
        a, b = max(0, c - half), min(len(x), c + half)
        ms = (sq[b] - sq[a]) / max(1, b - a)
        out.append(round(10.0 * np.log10(max(ms, 1e-12)), 1))
    json.dump({"dt": DT, "win": WIN, "rms_db": out}, open(os.path.join(PROJECT, "data", "levels", "level%d_rms.json" % lv), "w"))
    print("level %d: %d points, %.1f .. %.1f dBFS" % (lv, len(out), min(out), max(out)))
