"""Write data/levels/level5.json, the final level (the jam's Theme), in the same form as levels 1-4:
- music events with their sub-level branch: the 第 5 关 事件 sheet of design/小关映射表_THAT_v4.xlsx
- sections, chords, lead / arp / bass lines and kicks: analysis/theme_analysis.json
- loudness and the 12 visualizer bands (every 1/32 s): the audio itself, worked out like the training levels'

    python tools/export_theme.py        (needs openpyxl, numpy, librosa)
Times are the audio's own seconds; the Theme's 3-beat pickup bar starts half a second before the audio does.
"""
import json, os, re, warnings
import numpy as np, librosa, openpyxl

warnings.filterwarnings("ignore")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO = "assets/music/levels/level5_theme.ogg"
OUT = os.path.join(ROOT, "data/levels/level5.json")
PC = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8,
      "A": 9, "A#": 10, "Bb": 10, "B": 11}


def midi_of(name):
    return PC[re.match(r"[A-G][#b]?", name).group(0)] + 12 * (int(re.search(r"-?\d+$", name).group(0)) + 1)


a = json.load(open(os.path.join(ROOT, "analysis/theme_analysis.json"), encoding="utf-8"))
meta = a["meta"]
root = PC[meta["key"].split()[0]]
dur = float(meta["duration"])
bar = float(meta["bar_sec"])

# ---- events, with their branch, from the design workbook
wb = openpyxl.load_workbook(os.path.join(ROOT, "design/小关映射表_THAT_v4.xlsx"), read_only=True, data_only=True)
rows = [r for r in wb["第 5 关 事件"].iter_rows(values_only=True)]
events = []
for r in rows:
    if not isinstance(r[0], (int, float)) or not r[5]:
        continue
    t, bar_no, _beat, cell, _sub, branch, kind, _what, detail, _section = r[:10]
    ev = {"t": round(max(0.0, float(t)), 3), "kind": kind, "branch": branch.split()[0], "bar": int(bar_no), "step": int(cell) - 1}
    for part in re.split(r"[，,]", detail or ""):
        if "=" not in part:
            continue
        k, v = [s.strip() for s in part.split("=", 1)]
        if k in ("beats", "steps", "change"):
            ev[k] = float(re.sub(r"[^0-9.+-]", "", v)) if k != "steps" else int(v)
        elif k in ("note", "frm", "to", "chord", "src"):
            ev[k] = v
    if "note" in ev:
        ev["midi"] = midi_of(ev["note"])
    if "to" in ev:
        ev["to_midi"] = midi_of(ev["to"])
    events.append(ev)
events.sort(key=lambda e: e["t"])

# ---- the music's lines, chords and kicks from the analysis
line = lambda name: [{"t": round(n["t"], 3), "dur": round(n["dur"], 3), "midi": n["midi"]} for n in a[name] if n["t"] >= 0]
chords = [{"t": round(max(0.0, c["t"]), 3), "chord": c["chord"],
           "tonic": PC[re.match(r"[A-G][#b]?", c["chord"]).group(0)] == root} for c in a["chords"]]
kicks = [{"t": round(d["t"], 3), "step": d["step"], "v": d["v"]} for d in a["drums"] if d["type"] == "kick"]
sections = [{"id": s["id"], "t": max(0.0, s["t"]), "end_t": s["end_t"]} for s in a["sections"]]

# ---- loudness and visualizer bands from the audio (the same recipe as the training levels)
y, sr = librosa.load(os.path.join(ROOT, AUDIO), sr=22050, mono=True)
db = 20 * np.log10(librosa.feature.rms(y=y, frame_length=2048, hop_length=256)[0] + 1e-6)
fr = sr / 256
ref = np.percentile(db, 98)
bars = int(np.ceil((dur - meta["first_downbeat"]) / bar)) + 1
energy = []
for b in range(bars):
    t0 = max(0.0, meta["first_downbeat"] + (b - 1) * bar)
    t1 = min(len(y) / sr, t0 + bar)
    if t1 > t0:
        energy.append(round(float(max(0.0, min(1.0, (db[int(t0 * fr):int(t1 * fr)].mean() - ref + 30) / 30))), 3))
LOUD_DT = 1.0 / 32.0
sm = np.convolve(db, np.ones(max(1, int(0.12 * fr))) / max(1, int(0.12 * fr)), mode="same")
lo_db, hi_db = np.percentile(sm, 5), np.percentile(sm, 98)
ts = np.arange(0.0, dur, LOUD_DT)
loud = [round(float(np.clip((np.interp(t * fr, np.arange(len(sm)), sm) - lo_db) / max(1e-6, hi_db - lo_db), 0.0, 1.0)), 3) for t in ts]
NB = 12
S = np.abs(librosa.stft(y, n_fft=2048, hop_length=256))
freqs = librosa.fft_frequencies(sr=sr, n_fft=2048)
edges = np.geomspace(50.0, 10000.0, NB + 1)
rel = np.exp(-(256 / sr) / 0.12)
band_rows = []
for i in range(NB):
    sel = (freqs >= edges[i]) & (freqs < edges[i + 1])
    bdb = 20 * np.log10(S[sel].mean(0) + 1e-6)
    lo_b, hi_b = np.percentile(bdb, 10), np.percentile(bdb, 97)
    v = np.clip((bdb - lo_b) / max(1e-6, hi_b - lo_b), 0.0, 1.0)
    for k in range(1, len(v)):
        v[k] = max(v[k], v[k - 1] * rel)
    band_rows.append(np.interp(ts * fr, np.arange(len(v)), v))
bands = [[round(float(band_rows[i][k]), 2) for i in range(NB)] for k in range(len(ts))]

out = {"level": 5, "letter": "THAT", "song": "thatgamejam #02 Theme", "author": "thatgamejam", "section": "全曲",
       "final": True, "key": meta["key"], "bpm": meta["bpm"], "beat_sec": meta["beat_sec"], "bar_sec": bar,
       "first_bar_at": meta["first_downbeat"], "bars": bars, "dur": dur, "audio": "res://" + AUDIO,
       "energy": energy, "loud_dt": LOUD_DT, "loud": loud, "bands": bands, "events": events, "chords": chords,
       "lead": line("lead"), "arp": line("arp"), "bass": line("bass"), "kicks": kicks, "sections": sections}
json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("saved", OUT, "events", len(events), "lead", len(out["lead"]), "chords", len(chords), "kicks", len(kicks), "sections",
      [(s["id"], s["t"], s["end_t"]) for s in sections])
