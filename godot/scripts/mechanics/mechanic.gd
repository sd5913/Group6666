extends Node3D
## Base of every mechanic in scripts/mechanics/. The level calls these hooks in this order; a mechanic only overrides
## what it uses. Which mechanics a level has is MECHANICS in config/tuning.csv (their order is the order they're asked).
##   building:      plan_air -> plan_fill -> plan_contacts -> (the level plans the ground) -> carve -> carve_late
##                  -> solve -> place -> build
##   physics step:  prepare_bulges -> update_motion -> autoplay -> jump_claim / hop_blocked -> before_step -> stop_x -> (the player
##                  moves) -> after_step -> fallen / fail_reason
## A mechanic's settings are its UPPER_CASE vars, filled from config/tuning.csv like the level's own.

enum { PASS, TAKEN, WAIT }  # answers to jump_claim

var L  # the level (scripts/level.gd)


## The tutorial (scripts/tutorial.gd), before anything is planned: one of this mechanic's things before the song starts, at
## these song times (what they are is the mechanic's; `kind` picks one of its sorts).
func teach(_at: Array, _kind := "") -> void:
	pass


## Airborne stretches (append to L.air_spans) and gaps (L.pits), planned from timing alone.
func plan_air() -> void:
	pass


## A second pass once every mechanic has planned: fill the room that is left (lower-priority notes).
func plan_fill() -> void:
	pass


## Times something touches the ground (L.contacts): the ground stays flat around them.
func plan_contacts() -> void:
	pass


## How far the mechanic pillar reaches either side of contact t, if this mechanic wants it different (else -1).
func contact_r(_t: float) -> float:
	return -1.0


## Reshape the mechanic pillars (L.mech) once they are planned.
func carve() -> void:
	pass


## Reshape what depends on the heights the other mechanics carved (they have all carved now).
func carve_late() -> void:
	pass


## The surface over a mechanic pillar this mechanic made (its seg has "by": self).
func surface(_seg: Dictionary, top: float, _x: float) -> float:
	return top


## Perfect-play arcs (L.arcs), now that the ground is final.
func solve() -> void:
	pass


## Things placed on the perfect path (it is known now).
func place() -> void:
	pass


func build() -> void:
	pass


## Ground and roof bulges must be ready before either row updates its geometry.
func prepare_bulges() -> void:
	pass


## Visuals that move with the music; runs every physics step before the player stands on anything.
func update_motion(_delta: float) -> void:
	pass


## P: press the inputs this mechanic needs, on the beat.
func autoplay() -> void:
	pass


## The inputs this mechanic asks for, for tests that press them early or late: [{t, action, until}] (action "jump",
## "dash" or "down"; until: hold it down to then).
func cues() -> Array:
	return []


## A jump was pressed at `press` (maybe a little earlier): TAKEN uses it up, WAIT keeps it for later, PASS ignores it.
func jump_claim(_press: float) -> int:
	return PASS


## True while a press is about to be needed here, so jump is not spent on a plain hop.
func hop_blocked() -> bool:
	return false


## S (down) was pressed at `press`: TAKEN uses it up, WAIT keeps it for later, PASS ignores it.
func down_claim(_press: float) -> int:
	return PASS


func before_step(_delta: float) -> void:
	pass


## The furthest the player may get along the run this step (a wall it hasn't broken), INF if nothing stops it.
func stop_x() -> float:
	return INF


func after_step(_delta: float) -> void:
	pass


## Something floating the player can stand on at t and x right now, over the ground (its top; -INF: nothing).
func float_support(_t: float, _x: float) -> float:
	return -INF


## Upside-down running: the underside of what this mechanic has overhead at t and x right now (INF: nothing), and
## the same for the perfect player, known in advance.
func roof_at(_t: float, _x: float) -> float:
	return INF


func roof_h(_t: float) -> float:
	return INF


## Where the camera should look at time t instead of at the player ({} to leave it): {"y": height}.
func view_focus(_t: float) -> Dictionary:
	return {}


## Every object this mechanic placed, with the MIDI track(s) whose note it stands on: [[t, "kick"], [t, "clap,kick"]].
## tools/autoplay_check.gd reports any that is more than 10 ms off a note.
func anchors() -> Array:
	return []


## Song times of the presses this mechanic needs (not the ones that only score, like a drum's extra bounce): what a
## checkpoint keeps its distance from, and what the tools count as inputs. The cues', unless a mechanic says otherwise.
func inputs() -> Array:
	return cues().map(func(c): return c.t)


## The press prompts this mechanic shows (scripts/view/cue_text.gd): [{t, action, until, optional, judge_t, verb}] —
## its cues, unless it has presses that aren't cues, cues that are only optional (shown smaller, just the key), cues
## judged later than pressed (judge_t) or its own word for the press (verb: "FLIP").
func prompts() -> Array:
	return cues()


## Carrying on from song time t (after losing a life the level is reloaded and starts there): everything of this
## mechanic before t is over — done, not scored, out of sight — so it doesn't act on a player that never met it.
func skip_to(_t: float) -> void:
	pass


## Whether one of this mechanic's blocks stands where the run is at song time t (a star there would be hidden in it).
func occupied(_t: float) -> bool:
	return false


## Lost in a way the level's own fall check can't see (falling up, say).
func fallen() -> bool:
	return false


## Why the player fell, if it was this mechanic's doing ("" if not).
func fail_reason() -> String:
	return ""


## HUD lines explaining this mechanic's input: each key in brackets ([SPACE], [SHIFT], [S]), right before the word for
## what it does; the HUD colours both (hud.set_hints).
func tips() -> Array:
	return []


## The intro panel's little drawings (scripts/view/intro_panel.gd) of this mechanic's objects in the level, in their
## colours here, where it has something planned: [{family, t (when the first of them is met), rows: 12 strings of 12
## art pixels ("." clear), palette: {letter: colour}}] ([]: nothing, or no family).
func panel_sprites() -> Array:
	return []


## The intro panel's line (scripts/view/intro_panel.gd) for each family of mechanics this one belongs to, where the
## level has something of it: {family: what to do} ({}: nothing, or no family — a plunge needs no key).
func panel_caption() -> Dictionary:
	return {}


## Extra Tab-overlay labels: [[text, position]].
func labels() -> Array:
	return []
