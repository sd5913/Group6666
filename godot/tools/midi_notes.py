"""Write data/levels/levelN_midi.json from each level's transcription MIDI (assets/music/levels/*_transcription.mid):
every note of every track, in song seconds, for the MIDI background (scripts/view/midi_background.gd).
Drums (channel 10) are split by pitch: 35/36 kick, 37-40 clap (snare / clap), 42/44/46 hi-hat; where the drum track
says it has a "pulse" (the Theme's), 37 is that pulse instead.

    python tools/midi_notes.py            (needs mido: pip install mido)
"""
import glob, json, os, re
import mido

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DRUM = {35: "kick", 36: "kick", 37: "clap", 38: "clap", 39: "clap", 40: "clap", 42: "hat", 44: "hat", 46: "hat"}
# where a file's time 0 isn't the audio's: the Theme's MIDI starts at its 3-beat pickup bar, half a second before the audio
OFFSET = {5: -0.5}


def notes_of(path, offset=0.0):
    mid = mido.MidiFile(path)
    tracks = {}
    for tr in mid.tracks:
        name = tr.name.split(" ")[0].lower() if tr.name else ""
        drum = {**DRUM, **({37: "pulse"} if "pulse" in (tr.name or "").lower() else {})}
        t = 0.0
        tempo = 500000
        on = {}
        # tempo lives in track 0; these files keep one tempo, so read it from the merged stream instead
        for msg in mido.merge_tracks([mid.tracks[0], tr]):
            t += mido.tick2second(msg.time, mid.ticks_per_beat, tempo)
            if msg.type == "set_tempo":
                tempo = msg.tempo
            elif msg.type == "note_on" and msg.velocity > 0:
                on[(msg.channel, msg.note)] = (t, msg.velocity)
            elif msg.type in ("note_off", "note_on") and (msg.channel, msg.note) in on:
                t0, vel = on.pop((msg.channel, msg.note))
                key = drum.get(msg.note, "perc") if msg.channel == 9 else name
                if key:
                    tracks.setdefault(key, []).append([round(t0 + offset, 4), round(t - t0, 4), msg.note, vel])
    for v in tracks.values():
        v.sort()
    return tracks


for path in sorted(glob.glob(os.path.join(ROOT, "assets/music/levels/level*_transcription.mid"))):
    n = int(re.search(r"level(\d)", os.path.basename(path)).group(1))
    out = os.path.join(ROOT, "data/levels/level%d_midi.json" % n)
    tracks = notes_of(path, OFFSET.get(n, 0.0))
    json.dump({"source": os.path.relpath(path, ROOT).replace("\\", "/"), "tracks": tracks}, open(out, "w"), separators=(",", ":"))
    print(out, {k: len(v) for k, v in tracks.items()})
