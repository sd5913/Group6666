# Generating Rhythm Levels from MIDI: Inspiration, How It Works, Process

> This covers only Midi Runner's core mechanism, so it can be reused in other projects. Written 2026-11-19. Every number was checked against the code and `config/tuning.csv`. Sources are given in brackets, relative to the project root.
> For the look (pixel art, colour, models generated in code), see [pixel_art_en.md](pixel_art_en.md).

---

## 1. Inspiration

### 1.1 The problem

How do you let a player **play their way into understanding a song**? Not with the song playing in the background, but with every jump, dash and slam landing on a note that is really in it. After playing, you hear the song again and recognise "that's where I dashed through".

### 1.2 Three core ideas

1. **A runner's x axis is time.** The hero keeps running forward; where the hero is, is where the song is.
2. **The MIDI is the level's blueprint.** Put every note on the track at the moment it sounds: drum hits become mechanics to press, the melody's pitch becomes the ground's height, long notes become things to hold.
3. **The hero is the playhead.** Every note in the background is a small shape that sounds and lights up exactly as the hero passes it (`scripts/view/midi_background.gd:3-4`: "The player is the playhead"). The whole background is a score laid out sideways.

### 1.3 Like learning a piece: practise in sections, then put it together

You usually learn a piece one section at a time, then join them up. The game copies that:

- There is a **target song** (here a song called Theme), split by section: intro, verse A, chorus B1, chorus B2.
- Each section gets a **training level**, but the training level uses **a different song in a similar style**.
- The last level is **the target song itself**, each section using the mechanics of the training level that trained it.

The training levels deliberately don't use the target song's sections. The player should learn **rules** like "clap = dash" and "long note = hold" in other songs, so that on first hearing the target song they can read it on their own by those rules. If the rules transfer, the player has really understood the music.

### 1.4 Visual inspiration

- **A music player's spectrum bars**: the ground is rows of square pillars rising and falling with the music.
- **A piano roll / MIDI editor**: notes are blocks laid out sideways, and their height is their pitch.

See [pixel_art_en.md](pixel_art_en.md).

---

## 2. How it works

### 2.1 Overall structure

```
         offline (Python)                                    at run time (Godot)
audio ──► excerpt, transcribe MIDI ──► note data   levelN_midi.json ──┐
      └─► detect music events ──────► event data  levelN.json ────────┼──► the whole world is generated when ──► runs on
      └─► loudness, spectrum ───────► audio features (same + _rms.json)┤     a level loads (ground, mechanics,    the song clock
                                        config/tuning.csv ─────────────┘     background)                          (judging, speed, visuals)
                                      (every setting per level, edited by hand)
```

There is no hand-placed level scene: `scenes/level_N.tscn` holds one node with `level.gd` on it, naming which data file to read. **A new song = a new set of data.**

### 2.2 The timeline: everything runs on song time

**The song clock** (`scripts/level.gd:1299-1320`):

```
song_time = playback position + time since last mix − output latency
now       = max(now, song_time − AUDIO_OFFSET)     # only moves forward, never jumps back
```

- The playback position alone advances in jumps, so the time since the last mix smooths it, and the sound card's output latency is subtracted.
- `AUDIO_OFFSET` is left for the player to calibrate; the song starts that much early so it is heard on the beat.
- Without a sound card (headless tests), or once the song has ended, `now` advances by frame time instead.

**Time → position** (`scripts/track_map.gd`):

- The hero's x isn't computed as speed × time on the fly; it is looked up in a table: `x = track.x_at(now)`.
- The table is built when a level loads, by integrating the speed in steps of 1/240 s:
  - base speed 6 m/s (`level.gd:64`);
  - louder / softer sections: × / ÷ 1.15, held between 0.75 and 1.5;
  - groove bars: × 1.2; the climax: × 1.25; the ending: easing down to 0.35;
  - all multipliers together are capped at × 1.8; every change eases in over about 0.3 s.
- **Every mechanic is placed at `x_at(note time)`**, so speed changes never break the beat: a faster stretch only spreads the same beats further apart (`track_map.gd:3-4`).

### 2.3 Three layers of music data

**Note layer** (`data/levels/levelN_midi.json`, `scripts/core/song.gd`):

- Every note of every part: `[start s, length s, pitch, velocity]`.
- Drums are split into three parts by General MIDI drum number: 35/36 kick, 37–40 clap / snare, 42/44/46 hi-hat (`tools/midi_notes.py:12`).
- Plus bass, arp (arpeggio) and lead (melody).
- `song.gd` answers queries: the notes within a span of time, the note nearest a moment, how far off it is (`:26-61`). It can also be given a time window, so a mechanic only sees one section's notes (that is how the final level assigns mechanics by section).

**Event layer** (`events` in `data/levels/levelN.json`):

- Each event: `{t, kind: E01–E16, branch: 1a–6e, bar, step}`, where `step` is the 16th note within the bar (0–15).
- Extra fields where needed: beats on long notes and rests, pitch on melody events, the chord's name on chord events, the loudness change (dB) on section events, the length on fills.
- The same file also holds `bpm`, `beat_sec`, `bar_sec`, `first_bar_at` (when the first bar starts), the chord list, the melody / arpeggio / bass notes and the detected kicks.

**Audio feature layer**:

- Loudness: one value every 1/32 s.
- Spectrum: 12 log-spaced bands (50 Hz–10 kHz), one set every 1/32 s (`tools/export_godot.py:30-44`).
- One energy value per bar.
- These mainly drive visuals (spectrum pillars, far waves), and keep sound effects under the music (`levelN_rms.json`).

### 2.4 From 16 music events to 6 sub-levels

**16 kinds of music event** (detected automatically; `design/音乐事件_关卡元素映射表.xlsx`):

| # | Event | How it's detected | Confidence |
|---|---|---|---|
| E01 | pickup / lead-in note | the hit sounding just before the next bar starts | medium |
| E02 | downbeat kick | the kick on beat 1 of each bar | high |
| E03 | syncopated kick | a kick on the half beat (16ths 3, 7, 11, 15) | medium |
| E04 | off-beat clap | the clap or snare on beats 2 and 4 | high |
| E05 | groove bar | a bar with a hit on almost every 8th | medium |
| E06 | rest | at least 1 beat with no new sound | medium |
| E07 | long melody note | a lead note lasting 1.5 beats or more | medium |
| E08 | phrase's highest note | the lead's highest point in each 4 bars | medium |
| E09 | melodic leap | neighbouring notes ≥ 9 semitones apart | low (often octave errors) |
| E10 | fill / roll | 4 or more 16ths in a row with drums | medium |
| E11 | accent | loudness suddenly near its maximum | medium |
| E12 | chord change | the chord's root changes (checked every half bar) | medium |
| E13 | section change | a bar where loudness or the drum kit changes clearly | medium |
| E14 | phrase start | the start of every 4 bars | high |
| E15 | climax | the 2 loudest bars | high |
| E16 | ending | the last bar | high |

**Grouped into 6 = 6 sub-levels**, each split again by "what sounds different" into 22 branches (`design/小关映射表_THAT_v4.xlsx`):

| Sub-level | Contains | Branches |
|---|---|---|
| 1 Kick placement | E01, E02, E03 | 1a downbeat, 1b syncopated, 1c anticipated, 1d opening pickup |
| 2 Claps and hits | E04, E10, E11 | 2a off-beat clap, 2b accent, 2c fill |
| 3 Groove and rests | E05, E06 | 3a groove bar, 3b short rest, 3c long rest |
| 4 Melody line | E07, E08, E09 | 4a long note, 4b highest note, 4c leap up, 4d leap down |
| 5 Chords and phrases | E12, E14 | 5a phrase start, 5b back to the home chord, 5c away from it |
| 6 Section points | E13, E15, E16 | 6a louder, 6b softer, 6c drum pattern change, 6d climax, 6e ending |

**The key principle: the same event becomes the same element in every level.** Every level is made of these 6 sub-levels with matching numbers. What is learned in a training level appears unchanged in the final level.

### 2.5 Mapping rules: parts and events → moves

Besides events, mechanics read each part's notes directly. These are the rules Midi Runner ended up with; the left two columns can be carried straight into another project:

| Music | Suits | In Midi Runner | Source |
|---|---|---|---|
| Kick (the rhythmic backbone, a "downward" feel) | required moves that go down or bounce up | drum trampolines (they bounce you by themselves; pressing only scores); slams (each bar's downbeat); flips (bar downbeats) | `drums.gd`, `slam.gd:58-77`, `flip.gd:98-117` |
| Clap / snare (off-beat, a "push forward" feel) | dashing, breaking, ducking | jaws, walls (3–5 blocks by velocity), slides (claps not on a kick), smash blocks, launched walls (loud claps, velocity ≥ 104) | `jaws.gd:70-100`, `walls.gd:47-71`, `slide.gd:55-89`, `smash.gd:41-70`, `launch.gd:51-80` |
| Hi-hat (too dense) | **no obstacle**, only warnings | wall outlines, slide curtains and smash blocks blink with it | `walls.gd:185-186`, `slide.gd:288-289` |
| Melody pitch | terrain height | 0.15 m per semitone (`KEY_STEP`), around the lead's median note | `level.gd:650-651, 798-799` |
| Long melody notes | hold, let go at the note's end | glide ribbons (notes ≥ 0.7 s) | `glide.gd:89-137` |
| Melodic leaps | drops / springs | a leap down = the ground drops 0.6 m; a leap up = a spring landing 2 beats later | `level.gd:800-810`, `springs.gd:46-65` |
| Phrase's highest note | collectible / checkpoint | a star, which is also a checkpoint | `stars.gd:30-45` |
| Fast melody runs | a string of self-bouncing platforms | flute hops (≥ 6 notes in 2 beats; pressing plays the note on a flute) | `hops.gd:59-120` |
| Arpeggio | stairs | arpeggio stairs (always up or always down, never flat) | `steps.gd:59-100` |
| Groove bar | a short boost | × 1.2 for the bar, pillars glowing | `track_map.gd` |
| Rest | **nothing** | flat ground, a run-up for the next take-off | — |
| Chord (home / away) | colour temperature | the sky turns warm / cool | `camera_rig.gd:33-35, 64-71` |
| Phrase start | teaching pace, ground pattern | one new move per phrase; the ground alternates light and dark | `level.gd:1249`, `pillars.gd:227-235` |
| Section loudness, climax, ending | speed | see 2.2 | `track_map.gd` |
| Spectrum | visuals only | spectrum pillars; mechanic pillars pump with the lows | `pillars.gd`, `level.gd:828-838` |

Unused branches: short / long rests (3b / 3c, which became the "flat ground" rule), the opening pickup (1d) and drum pattern change (6c).

### 2.6 Mechanics are plug-ins

Each kind of mechanic is one script extending the same base class, `scripts/mechanics/mechanic.gd`, overriding only the hooks it uses.

**Called in this order while building** (`mechanic.gd:4-7`):

| Hook | What it does |
|---|---|
| `plan_air` | from timing alone, plan which stretches are in the air and where the pits are |
| `plan_fill` | once every mechanic has planned, fill the room left with lower-priority notes |
| `plan_contacts` | the moments that touch the ground; the ground stays flat around them |
| (the level plans the ground) | melody pitch → key heights, drops, springs |
| `carve` / `carve_late` | cut pits and reshape the ground |
| `solve` | resolve conflicts |
| `place` / `build` | position things and build their models |

**Called every physics step at run time**: `update_motion` → `autoplay` → `jump_claim` / `hop_blocked` → `before_step` → `stop_x` → (the hero moves) → `after_step` → `fallen` / `fail_reason`.

**Every mechanic also answers these**:

- `anchors()`: which note each thing I placed hangs on (for the automated test to check).
- `autoplay()`: how to press on autoplay.
- `teach()`: how to appear once on its own in the tutorial.
- `skip_to(t)`: the state after t, for restarting from a checkpoint.
- `tips()`: the key hints on screen.

**The CSV decides which mechanics a level has**:

- `MECHANICS` lists a level's mechanics, processed in order (tuning.csv:3).
- `MECHANIC_SECTIONS` limits each mechanic to one section in the final level, e.g. `glide=A, slam=B1, flip=B2` (tuning.csv:4).
- A mechanic's settings are the UPPER_CASE variables in its script, which the CSV overrides per level (`scripts/core/tuning.gd`).

A new mechanic = a new script + its name in the CSV + a station in the tutorial.

### 2.7 Making the generated level playable: constraints

Turning notes straight into obstacles is almost never playable. These constraints were found one play test at a time:

| Constraint | Value | Why |
|---|---|---|
| Everything hangs on a real note | within 10 ms, checked by the automated test | the player must trust "what I press is that note" |
| Presses and landings sit on the beat grid | first bar + n beats, ±10 ms (`GRID_LOCK`: the MIDI only picks among notes on the grid) | 16th-note, pickup and half-beat-early presses feel awkward |
| Flat ground before a take-off | at least about 1 beat | every jump starts from solid footing |
| Time between presses | no more than about 2.5 s | the player is never left waiting |
| Minimum gap between mechanics of a kind | e.g. walls at least 2 beats apart | any denser and it's just mashing |
| Terrain changes | at most one terrace step per bar | the melody leaps far more often than a run can climb |
| Follow the music, don't fill it | quiet stretches stay empty | rests are music too |
| Teach one move at a time | one per phrase, then mix | see 2.9 |

### 2.8 Judging

- A press records `now` at that moment; the mechanic computes `error = press time − note time` and hands it to `level.judge()` (`level.gd:1476-1494`).
- |error| ≤ 0.05 s is PERFECT; the rest of the window is GOOD. Most mechanics' windows are ±0.16 s (drums, the glide press and flutes ±0.18).
- **Early presses wait**: a press up to 0.45 s early is held until its note, then judged by how early it really was; earlier than the window shows "EARLY!" and counts as a MISS (`EARLY_PRESS`).
- Jump buffer 0.18 s, coyote time 0.15 s.
- Streak = mechanics passed in a row; a MISS resets it.
- 3 lives; every star is a checkpoint; on a restart the world freezes 2 beats (counting 3, 2), then runs 1 beat back to the checkpoint (`level.gd:378-393`).
- Running into most obstacles is only a MISS, not a failure; the only real failures are falling, being held at a wall for more than 0.6 s, and a few others.

### 2.9 Teaching

- **Each phrase teaches one new move**, then the moves are mixed (for example level 1's three drum types B, A, C, one per phrase, `drums.gd:180`). A new mechanic always first appears on its own.
- **A silent tutorial before the music** (`scripts/tutorial.gd`):
  - the tutorial has its own clock, which slows over 0.35 s and stops wherever a press is needed, waiting for the right key;
  - a key cap with a hand pointing at it appears over the hero 2 beats ahead, and shakes on a wrong key;
  - it **can't be got wrong or failed**, and every press lands PERFECT;
  - only after stepping on a pressure plate do the song's name and the 3-2-1 come, then the music.

### 2.10 Automated checks

| Tool | Checks |
|---|---|
| `tools/autoplay_check.gd` | an autoplay clear; reports anything more than 10 ms off a note |
| `tools/run_tests.sh` | one run in each play style: autoplay, late, early, dash-only, no input |
| `tools/grid_check.gd` | that required presses and landings sit on the beat grid |
| `tools/cue_probe.gd` | when cues appear (±0.15 s) |
| `tools/tutorial_check.gd` | the tutorial with real key events |
| `tools/resume_check.gd` | that play carries on after restarting from each checkpoint |

---

## 3. Process

### 3.1 The steps we went through

For another project, you can follow this order.

**Step 1: take the target song apart.**

- Measure tempo, metre, key, where the first bar starts, sections and chords.
- Transcribe each part to MIDI and line up its time zero with the audio's. The target song's MIDI starts at its pickup bar, 0.5 s before the audio, which the conversion corrects (`tools/midi_notes.py:14`).
- Store the result as analysis data (`analysis/theme_analysis.json`).

**Step 2: find training songs.**

- CC0 only (no credit needed, no Content ID), nothing AI-generated.
- Measure every candidate with the same process used on the target song, then score it (out of 1):

  ```
  similarity = 35% tempo close + 25% drum pattern match + 20% similar timbre + 10% key distance + 10% minor key
  ```

- Then look at **coverage**: of the branches that occur in a section of the target song, how many this candidate has (e.g. 12 / 14).
- We searched three rounds: the first 14 didn't match the style; the closer ones in the second round were mostly registered with Content ID or AI-generated; the third round searched by initials and settled on 4 songs (`assets/music/CANDIDATES.md`).
- A low style score isn't necessarily bad: level 2's song scored only 0.51, but it has no kick at all and plenty of rests and long notes, just like the target song's verse A (which has no kick either).

**Step 3: detect events, count them, find the gaps.**

- Run event detection on the target song and every training song, and count each event and branch per section.
- Make a comparison sheet: a branch that a section of the target song has but the matching training song lacks is marked red, a gap (e.g. a training song with no opening pickup). Either swap the song or train it in another level first.

**Step 4: group, then pick elements.**

- Merge the 16 events into 6 sub-levels and 22 branches.
- Give each branch 3 candidate designs, the first being the recommendation, and choose in the sheet (the sheet went through four versions, v1 to v4).
- This is only a starting point: the elements picked in the sheet grow into other shapes while building (see 3.2).

**Step 5: pick mechanics per level and write the plug-ins.**

- Each level gets its own set of mechanics; the final level combines them by section (2.6).
- Design a new mechanic to the constraints in 2.7 first, then write the plug-in.

**Step 6: generate + check automatically.** Run the tools in 2.10 after every change.

**Step 7: play-test, then change.** What real play tests found is in 3.3.

**Step 8: add the tutorial.** Write a `teach()` for each mechanic and add a station to `Tutorial.COURSES`.

### 3.2 What the elements picked in the sheet became

| Sub-level | Picked in the sheet | What it became |
|---|---|---|
| 1 Kick placement | drum trampoline | drum trampolines (the rim colour tells downbeat, syncopated and anticipated kicks apart), later joined by slams and flips |
| 2 Claps and hits | closing blocks | jaws; the same "clap = dash" rule grew into walls, slides, smash blocks and launched walls |
| 3 Groove and rests | boost lane + long straight | groove bars boost; rests became the "flat ground before a take-off" rule |
| 4 Melody line | piano-key steps | ground height follows the melody; long notes = glide ribbons; arpeggio = stairs; highest note = stars; plus terraces, towers and flute hops |
| 5 Chords and phrases | colour switch + new terrain | chords turn the sky warm or cool; phrases alternate the ground's shade and set the teaching pace |
| 6 Section points | speed changes | speed changes (see 2.2) |

### 3.3 What play tests taught us

| What we found | What it became | The lesson to take away |
|---|---|---|
| "Holding SPACE gets you past everything" | letting go of a glide is judged too (note's end ±0.16 s; letting go early fails) | a hold move needs a meaningful release |
| Many presses were "swallowed" | presses up to 0.45 s early are allowed and wait for the note | players often press before the note; never drop it silently |
| One level was all on the drums; the melody barely registered | terraces, towers and flute hops that follow the lead | every level needs at least one mechanic that follows the melody |
| The "ground ripple" was hard to read | replaced by launched walls: a speaker pushes a wall at you on the kick, you dash through it on the loud clap | a mechanic needs visible cause and effect |
| 16th-note and pickup presses felt awkward | every press and landing locked to the beat | notes can be dense; presses should be sparse and on the beat |
| New players couldn't keep up from the start | a silent tutorial course that can't be failed | learn the moves first, without the music's pressure |
| PERFECT didn't feel good enough | the whole screen flashes 0.2 toward gold, the camera jolts 0.1 | a good judgement deserves full-screen feedback |

### 3.4 Moving it to another project

**Parts you can take as they are:**

| File | What it does |
|---|---|
| `scripts/core/song.gd` | reads the note data, queries notes by time |
| `scripts/track_map.gd` | song time ↔ position on the run; speed changes that keep the beat |
| `scripts/mechanics/mechanic.gd` | the mechanic plug-in base class and its hook order |
| `scripts/core/tuning.gd` | reads the CSV per level and overrides scripts' UPPER_CASE settings |
| `scripts/tutorial.gd` | the tutorial clock: slows and stops at each press |
| `tools/midi_notes.py` | MIDI → per-part note JSON (needs `mido`) |
| `tools/music_rms.py` | loudness JSON (needs ffmpeg and numpy) |

`scripts/level.gd` is large and tightly tied to this game's ground, hero and UI: good for reference, not for moving whole.

**What the repository lacks (honestly):**

- Transcription and event detection were done in an analysis environment outside the project; the scripts that did them aren't in the repository. A new project needs its own transcription (by hand or with a tool) and an event detection script.
- `tools/export_godot.py` imports two modules that aren't in the repository (`variants`, `choices`), so it can't run as it is.
- Since level 1 was lengthened to 48 s, the event data still holds the old 38 s cut, so the current `level1.json` can't be regenerated from the repository.

**Easy mistakes:**

- **The MIDI's time zero isn't necessarily the audio's**; line them up in the conversion (the target song was off by 0.5 s).
- **Drums must be transcribed with General MIDI drum numbers**, or kick / clap / hat won't split correctly.
- **It assumes one tempo for the whole song**: `midi_notes.py` reads a single tempo, and grid locking assumes a fixed BPM and first-bar start. Songs that change tempo need extra handling.
- **Melody detection is the least reliable**: a lead extracted from a mix often has octave errors, so listen through the leap events by hand.
- **The web build's audio clock**: when exporting for the web, `project.godot` needs `driver/output_latency.web=100` and `general/default_playback_type.web=0`, or the clock runs about 1.1 s behind the sound. On the web `AUDIO_OFFSET` is forced to 0, so a Windows calibration doesn't affect it.
- **Keep calibration apart from capture compensation**: when recording with Movie Maker, each song starts 13–22 ms behind the clock. Correct that only in the edit, never in the game's `AUDIO_OFFSET`.

---

## Appendix: Midi Runner's five levels (as an example)

| Level | Trains | Song | BPM / key | Length | Mechanics |
|---|---|---|---|---|---|
| 1 · T | intro | Tuesday Morning | 120, E minor | 48 s | drum trampolines, jaws, stars |
| 2 · H | verse A | Hypnotic Chill | 125, B minor | 48 s | walls, arpeggio stairs, glide ribbons, stars |
| 3 · A | chorus B1 | April's Finale v2 (loop) Electronic | 120, C minor | 48 s | terraces (slam / plunge / spring), slides, towers, flute hops, stars |
| 4 · T | chorus B2 | The Moon Synth | 120, C minor | 48 s | flips, smash blocks, launched walls, stars |
| 5 | the whole song | Theme | 120, F minor | 60 s | A: glide, walls, jaws. B1: slam, plunge, slide, flutes, towers, drums. B2: flip, launched walls, smash. Throughout: stars |

The first four song titles start with T-H-A-T. Keys: SPACE jump / hold to glide / flip, SHIFT dash, S slam / slide.
