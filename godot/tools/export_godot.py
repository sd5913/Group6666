"""Export one level's music events (tagged with sub-level branches) to a compact JSON the Godot level builder reads."""
import sys, os, re, json, numpy as np, librosa, warnings
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from variants import PC, MIDI
from choices import ELEMENT, BRANCH_OPTS
warnings.filterwarnings("ignore")

SRC, LV, OUT = sys.argv[1], int(sys.argv[2]), sys.argv[3]
PROJ = "C:/Users/admin/Documents/thatgamejam/"
AUDIO = {1: "assets/music/levels/level1_intro_oga_tuesday_morning.ogg", 2: "assets/music/levels/level2_A_oga_hypnotic_chill.ogg",
         3: "assets/music/levels/level3_B1_oga_aprils_finale_electronic.ogg", 4: "assets/music/levels/level4_B2_oga_the_moon_synth.ogg"}
l = next(x for x in json.load(open(SRC, encoding="utf-8")) if x["level"] == LV)
root = PC[l["key"].split()[0]]
beat = l["bar_sec"] / 4
# per-bar loudness (0..1), used for the gentle rise / fall of long straights
y, sr = librosa.load(PROJ + AUDIO[LV], sr=22050, mono=True)
db = 20 * np.log10(librosa.feature.rms(y=y, frame_length=2048, hop_length=256)[0] + 1e-6); fr = sr / 256; ref = np.percentile(db, 98)
energy = []
for b in range(l["bars"]):
    a = max(0.0, l["first_bar_at"] + b * l["bar_sec"]); e = min(len(y) / sr, a + l["bar_sec"])
    if e > a:
        energy.append(round(float(max(0.0, min(1.0, (db[int(a * fr):int(e * fr)].mean() - ref + 30) / 30))), 3))
# fine loudness curve (0..1 every 1/32 s, lightly smoothed) for the ground that follows the volume
LOUD_DT = 1.0 / 32.0
sm = np.convolve(db, np.ones(max(1, int(0.12 * fr))) / max(1, int(0.12 * fr)), mode="same")
lo_db, hi_db = np.percentile(sm, 5), np.percentile(sm, 98)
ts = np.arange(0.0, l["dur"], LOUD_DT)
loud = [round(float(np.clip((np.interp(t * fr, np.arange(len(sm)), sm) - lo_db) / max(1e-6, hi_db - lo_db), 0.0, 1.0)), 3) for t in ts]
# visualizer bands: NB log-spaced bands, each normalised to 0..1, fast attack / slow release, every 1/32 s
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
KEEP = ("beats", "note", "frm", "to", "chord", "change", "bars", "steps")
events = []
for e in l["events"]:
    ev = dict(t=round(max(0.0, e["t"]), 3), kind=e["kind"], branch=e["branch"], bar=e["bar"], step=e["step"])
    ev.update({k: e[k] for k in KEEP if k in e})
    for k in ("note", "to"):  # melody heights need numbers, not note names
        if k in e:
            ev["midi" if k == "note" else "to_midi"] = MIDI(e[k])
    events.append(ev)
chords = [dict(t=round(max(0.0, c["t"]), 3), chord=c["chord"], tonic=PC[re.match(r"[A-G][#b]?", c["chord"]).group(0)] == root) for c in l["chords"]]
line = lambda name: [dict(t=round(n["t"], 3), dur=round(n["len"] * l["step_sec"], 3), midi=n["midi"]) for n in l["notes"][name] if n["t"] >= 0]
lead, arp, bass = line("lead"), line("arp"), line("bass")
# every detected kick (not only the ones that became events), so drum modes can lean on the beat-3 kick
kicks = [dict(t=round(h["t"], 3), step=h["r"] % 16, v=h["v"]) for h in l["drums"] if h["type"] == "kick" and h["r"] >= 0]
out = dict(level=LV, letter=l["letter"], song=l["song"], author=l["author"], section=l["section"], key=l["key"],
           bpm=l["bpm"], beat_sec=round(beat, 5), bar_sec=l["bar_sec"], first_bar_at=l["first_bar_at"], bars=l["bars"], dur=l["dur"],
           audio="res://" + AUDIO[LV], energy=energy, loud_dt=LOUD_DT, loud=loud, bands=bands, events=events, chords=chords, lead=lead, arp=arp, bass=bass, kicks=kicks,
           elements={k: v[0] for k, v in ELEMENT.items()}, branch_choice={k: v[0] for k, v in BRANCH_OPTS.items()})
os.makedirs(os.path.dirname(OUT), exist_ok=True)
json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("saved", OUT, "events", len(events), "lead", len(lead), "chords", len(chords), "bars", l["bars"], "beat", beat)
# timeline for designing the builder rules
from collections import defaultdict
row = defaultdict(list)
for e in events:
    row[e["bar"]].append(f"{e['branch']}@{e['step']}" + (f"({e.get('beats')})" if e["branch"] in ("3b", "3c", "4a") else ""))
for b in sorted(row):
    print(f"bar {b:2d} e={energy[b - 1] if b - 1 < len(energy) else '-':<5} " + " ".join(sorted(row[b], key=lambda s: int(s.split('@')[1].split('(')[0]))))
