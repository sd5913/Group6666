# Midi Runner

A rhythm runner made in Godot 4 for thatgamejam #02.

The web entry adds a home, story, conversation and record picker around the code-drawn Godot tavern. A native Godot run opens directly in that tavern. After levels 1–4, Space returns to the tavern before the next level. After level 5, the results screen returns to the tavern. The stool slime previews the colour of the level that will be played next; after level 5 it returns to level 1 pink. See `../TAVERN_SCENE.md` for implementation details.

## Controls

| Key | Action |
|---|---|
| SPACE (or W / Up) | Jump · hold to ride a ribbon (long note), release at its end · flip between the rows |
| SHIFT (either one) | Dash |
| S (or Down) | Slam (in the air) · slide (on the ground) |
| R | Restart |

**Windows:** turn off the Sticky Keys shortcut (Settings > Accessibility > Keyboard > Sticky keys > turn off "Keyboard shortcut for Sticky keys") or pressing SHIFT five times in a row will pop up a system dialog. On Windows 10: Settings > Ease of Access > Keyboard > Sticky Keys > turn off "Allow the shortcut key to start Sticky Keys".

## Credits

**Font:** Upheaval by Brian Kent (freeware; its readme is kept with it in `assets/fonts/upheaval/`).

**Music:**

- Level 1 — [Tuesday Morning](https://opengameart.org/content/tuesday-morning) by Pro Sensory (OpenGameArt, CC0)
- Level 2 — [Hypnotic Chill](https://opengameart.org/content/hypnotic-chill-extended-4-minute-mix) by The Cynic Project (OpenGameArt, CC0)
- Level 3 — [April's Finale v2 (loop) Electronic](https://opengameart.org/content/aprils-finale-v2-loop-electronic) by Pro Sensory (OpenGameArt, CC0)
- Level 4 — [The Moon Synth](https://opengameart.org/content/the-moon-synth) by Pro Sensory (OpenGameArt, CC0)
- Level 5 — thatgamejam #02 Theme by thatgamejam
