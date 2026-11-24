# tools/

Not part of the game (`.gdignore` keeps Godot from importing or exporting this folder).

| file | what it does |
|---|---|
| `run_tests.sh` | headless playthroughs of every level × play style (auto / late / early / dashonly / noinput), in parallel |
| `autoplay_check.gd` | one headless playthrough: `godot --headless --path . --script tools/autoplay_check.gd -- --level=N [--late\|--early\|--dashonly\|--noinput] [--trace=a,b]` |
| `step_cost.gd` | how long one physics step takes (script only): `... --script tools/step_cost.gd -- --level=N` |
| `capture.gd` | screenshots on autoplay, in a window: `godot --path . --fixed-fps 60 --resolution 1920x1080 --script tools/capture.gd -- --level=N --times=5,12.5 [--every=0.0167 --until=14.5] --out=<dir>` |
| `tutorial_check.gd` | the tutorials before the music, played with real key events, then the song: `godot --headless --fixed-fps 120 --path . --script tools/tutorial_check.gd -- --level=N [--auto\|--eager]`; `capture.gd --tutorial` shoots each of their stops |
| `dump_layout.gd` + `plot_layout.py` | side-view plot of a level's layout and the autoplay path |
| `midi_notes.py` | `data/levels/levelN_midi.json` from the transcription MIDI (needs `mido`) |
| `music_rms.py` | `data/levels/levelN_rms.json`: each song's loudness, which the sound effects keep under (needs ffmpeg and numpy) |
| `export_godot.py` | `data/levels/levelN.json` from the analysis (needs the analysis venv) |

`config/tuning.csv` is edited by hand (in Excel, saved as CSV UTF-8); there is no generator for it any more.
