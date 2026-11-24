extends Node3D
## Training-level runner, built from data/levels/levelN.json: the level's music (events tagged with one of the Theme's
## 6 sub-levels and its branch, the transcribed bass / arp / lead lines, the kicks and the spectrum).
## The player's x is locked to the song clock, so every element sits exactly on its beat; only the inputs (jump, dash,
## down) are up to the player. Inside the song the ground is square pillars that move with the music: every mechanic
## sits on its own pillar (pumping on the bass), and visualizer pillars fill the stretches in between.
##
## This script is the course and the loop: the song clock, the key heights (5-4), the ground everything stands on, the
## perfect-play path, input, failing and winning. Everything else has its own script:
##   mechanics/  one per mechanic; which ones a level has is MECHANICS in config/tuning.csv
##   view/       pillars, the MIDI background, camera and colours, the pixel-art look, HUD, the press prompts, the
##               Tab labels, helpers
##   audio/      generated sound effects
##   core/       tuning.csv, the song's MIDI notes, span helpers
##   tutorial.gd the course before the music on a level entered afresh, with its own clock
## Settings (UPPER_CASE vars here and in those scripts) are filled per level from config/tuning.csv.

const TrackMap := preload("res://scripts/track_map.gd")
const PlayerScript := preload("res://scripts/player.gd")
const PillarShader := preload("res://shaders/pillar.gdshader")
const Tuning := preload("res://scripts/core/tuning.gd")
const Spans := preload("res://scripts/core/spans.gd")
const Terrace := preload("res://scripts/core/terrace.gd")
const IntroPanel := preload("res://scripts/view/intro_panel.gd")
const TitleCard := preload("res://scripts/view/title_card.gd")
const Iris := preload("res://scripts/view/iris.gd")
const Results := preload("res://scripts/core/results.gd")
const MenuSettings := preload("res://scripts/core/menu_settings.gd")
const Song := preload("res://scripts/core/song.gd")
const Draw := preload("res://scripts/view/draw.gd")
const Mechanic := preload("res://scripts/mechanics/mechanic.gd")
const Pillars := preload("res://scripts/view/pillars.gd")
const CameraRig := preload("res://scripts/view/camera_rig.gd")
const Hud := preload("res://scripts/view/hud.gd")
const Dev := preload("res://scripts/core/dev.gd")
const EVENT_LABELS := "res://scripts/view/event_labels.gd"  # (developer only: loaded by path, and left out of the export)
const TUNE_MODE := "res://scripts/view/tune_mode.gd"
const Sfx := preload("res://scripts/audio/sfx.gd")
const MidiBackground := preload("res://scripts/view/midi_background.gd")
const FarWaves := preload("res://scripts/view/far_waves.gd")
const RunState := preload("res://scripts/core/run_state.gd")
const MenuProgress := preload("res://scripts/core/menu_progress.gd")
const LevelInfo := preload("res://scripts/core/level_info.gd")
const PixelPost := preload("res://scripts/view/pixel_post.gd")
const CueText := preload("res://scripts/view/cue_text.gd")
const Tutorial := preload("res://scripts/tutorial.gd")
const MECHANIC_SCRIPTS := {
	"drums": preload("res://scripts/mechanics/drums.gd"),
	"jaws": preload("res://scripts/mechanics/jaws.gd"),
	"springs": preload("res://scripts/mechanics/springs.gd"),
	"stars": preload("res://scripts/mechanics/stars.gd"),
	"glide": preload("res://scripts/mechanics/glide.gd"),
	"steps": preload("res://scripts/mechanics/steps.gd"),
	"walls": preload("res://scripts/mechanics/walls.gd"),
	"slam": preload("res://scripts/mechanics/slam.gd"),
	"plunge": preload("res://scripts/mechanics/plunge.gd"),
	"slide": preload("res://scripts/mechanics/slide.gd"),
	"towers": preload("res://scripts/mechanics/towers.gd"),
	"flip": preload("res://scripts/mechanics/flip.gd"),
	"smash": preload("res://scripts/mechanics/smash.gd"),
	"launch": preload("res://scripts/mechanics/launch.gd"),
	"hops": preload("res://scripts/mechanics/hops.gd"),
}

@export_file("*.json") var level_path := "res://data/levels/level1.json"
@export var base_speed := 6.0
@export var lead_in := 2.0
@export var bar_height := 2.4    # how far a visualizer pillar rises at full volume (metres)
@export var pump_height := 1.0   # how far the pillars under mechanics pump up on the bass (metres)
@export var mech_lift := 0.8     # mechanic pillars start this far above the key height (metres)
@export var theme_color := Color(1.0, 0.5, 0.12)  # this level's colour for every pillar (level 1: orange)

const HALF := 0.7              # capsule centre above the feet
const NONE := -1000.0
const G_DT := 1.0 / 120.0
const BAND_FILTER := [1.0, 4.0, 6.0, 4.0, 1.0] # short symmetric filter: removes one-sample column jerks without moving the beat
const VIEW_BEHIND := 15.0      # the moving parts are updated only from this far behind the player...
const VIEW_AHEAD := 40.0       # ...to this far ahead (well past the edges of the picture)

# ---- settings: the values written here are level 1's; config/tuning.csv overrides them per level
var MECHANICS := "drums,jaws,springs,stars"  # this level's mechanics, in the order they are asked (scripts/mechanics/)
var MECHANIC_SECTIONS := ""    # the final level: which song section each mechanic plays in ("slam=B1,flip=B2"; unlisted: all)
var GRAVITY := 22.0
var JUMP_V := 9.0
var PERFECT := 0.05
var PERFECT_TINT := 0.2        # a perfect tints the whole view this much in gold for a moment (0-1),
var PERFECT_SHAKE := 0.1       # and gives it this small a jolt
var JUMP_BUFFER := 0.18       # a jump pressed this early still counts once it can be used
var EARLY_PRESS := 0.45        # a mechanic's jump (glide, steps, press spring) pressed up to this early waits for its note
var WINDOW := 0.12             # dash window on a clap / an air dash (seconds)
var COYOTE_T := 0.15           # a mechanic's jump still works this long after stepping off an edge (seconds)
var CROUCH_T := 0.45           # S on the ground, away from any mechanic: a plain slide this long (seconds)
var CATCH_UP := 1.0            # held back (a wall, a fired wall): the player runs this much faster than the song until back on its beat
var AUDIO_OFFSET := 0.0        # the speakers / headphones play this much later than the game can tell (seconds): the game runs that far behind the song
var SHOW_TIMING := 0           # the judgement popup also says how early (-) or late (+) the press was, in ms (1 yes / 0
							   # no: the word only); F3 turns it on and off where DEV_KEYS are on (to calibrate AUDIO_OFFSET)
var LIVES := 3                 # lives per level: losing one carries on from the last star passed (the last one: game over)
var RESUME_FREEZE := 2.0       # carrying on: everything stands still this many beats (3, 2) before the count-in's last (1)
var CHECKPOINT_LEAD := 1.0     # a checkpoint is at least this many beats before the next thing to do after it
var CHECKPOINT_MIN_GAIN := 1.0 # a star only saves if it moves the checkpoint on by at least this many beats
var DEV_KEYS := 1              # P (autoplay), T (tune mode), 1-9 (choose a level), Tab (event labels), F3 (timing in ms), F2
							   # (the pixel look) work (0: off); only ever in the editor's binary (core/dev.gd)
var REST_SPANS := ""           # song stretches every mechanic keeps clear of, each with a star (a checkpoint): "26.8-28.5"
var REST_BEAT := 0             # nothing to do on this beat of every bar (+-0.2 s), where the song sinks back (0: none)
var GRID_LOCK := 0             # every press and landing on the beat grid (first_bar_at + n beats, within GRID_TOL): the MIDI
							   # only picks among the notes on it (1 on / 0 off)
const GRID_TOL := 0.010
# 5-4 piano keys
var KEY_STEP := 0.15           # metres per semitone for the piano keys
var KEY_NOTE_MIN := -1.2       # a long note's key height is kept between these (before 4c / 4d move the ground),
var KEY_NOTE_MAX := 2.4
var KEY_MIN := -99.0           # the key height never goes below / above these
var KEY_MAX := 99.0
var RAMP_T := 0.25             # seconds of run on the ramp before a higher key
var DROP := 0.6                # 4d: how far a down-leap drops the ground
var UPLEAP_RISE := 0.0         # 4c: how far an up-leap raises the ground (where its spring lands)
var MAX_SLOPE_DEG := 38.0      # piano-key ramps never get steeper than this
# terraces (scripts/core/terrace.gd): instead of 4a / 4c / 4d, the ground follows the melody's strong notes
var TERRACE_PER_ST := 0.0      # metres per semitone from the lead's median (0: no terraces, the piano keys as above)
var TERRACE_DROP_MAX := 3.6    # a step down is never more than this (metres),
var TERRACE_RISE_MAX := 1.5    # a step up never more than this,
var TERRACE_MIN_STEP := 0.5    # and smaller changes than this are no step at all
var TERRACE_SLAM_MIN := 0.5    # a step down at least this big is a slam where one fits (else a plunge)
var TERRACE_FROM := 2.0        # no step before this (seconds)
var TERRACE_REST := 0.5        # a new terrace is run on at least this long before the next step's run-up (seconds)
var TERRACE_RANGE := 3.0       # a terrace is never more than this above or below where the terraces start (metres)
var TERRACE_SECTIONS := ""     # the song sections with terraces ("B1", "B1+B2"; "": the whole level); elsewhere the keys
var TERRACE_DRUM_BARS := 0     # in those sections, the first this many bars are the drums' (the terraces start after)
var TERRACE_DENSE := ""        # from the first event of this branch ("6a": the song getting stronger) a step can come each
							   # strong beat, not just once a bar ("": never)
var TERRACE_DENSE_REST := 0.15 # and a new terrace is run on only this long before the next step's run-up (seconds)
var TERRACE_CLIMAX_MULT := 1.3 # in the climax (6d) the terraces stand this many times as far apart
var TERRACE_SLAM_GAP := 0.0    # slams at least this far apart (seconds; the ground between left to slides and the rest)
# the melody's contour (scripts/core/terrace.gd): between the terraces' steps the ground follows the lead's highest note a beat
var CONTOUR_FROM_EVENT := ""   # from the first event of this branch on ("6a"; "": not by event)
var CONTOUR_SECTIONS := ""     # in these song sections ("B1"; "": not by section; both empty: no contour)
var CONTOUR_PER_ST := 0.15     # metres per semitone from the lead's median
var CONTOUR_STEP_MAX := 0.6    # the contour moves at most this much from one beat to the next (metres)
var LAND_EDGE_T := 0.03        # the next platform starts right where a bounce lands
# ground between the mechanics
var CONTACT_R := 0.15          # plain ground this long around every contact point (no bars)
var TAPER := 0.4               # bars calm down over this many seconds as they near a contact point
var TOSS_CALM_T := 0.0         # bars don't toss the player up this long before a contact point
var BAR_MIN_SPAN := 0.9        # the shortest stretch (metres) that still gets visualizer pillars
var MECH_FLOOR := -0.6         # mechanic pillars' key height never counts as lower than this
# the accent: the theme's opposite hue, kept for everything the player plays with
var ACCENT_S := 0.7            # its saturation
var ACCENT_V := 1.0            # and brightness (a deeper one stands out better against a pale, warm sky)
# the press prompts (scripts/view/cue_text.gd)
var CUE_TEXT := 0              # what to press, in words over the judgement popup, popping on the moment (1 on / 0 off)
var CUE_SHOW_BEATS := 1.0      # a prompt fades in this many beats before its moment
var CUE_TEXT_SCALE := 1.2      # its words' size, of the judgement popup's
var TUTORIAL := 1              # a level entered afresh starts with its tutorial, before the music (scripts/tutorial.gd; 1 on / 0 off)
var INTRO_PANEL := 1           # the ready screen shows the families of mechanics in the level, once (1 on / 0 off)
var TITLE_CARD := 1            # entered afresh, after the tutorial's plate (or SPACE, with no tutorial), its title line before the count-in (1 on / 0 off):
var TITLE_IN := 0.12           #   the letter at once, " - SONG" then (seconds),
var TITLE_AUTHOR := 0.24       #   " - AUTHOR" then,
var TITLE_FADE_AT := 1.6       #   held to then, fading out
var TITLE_END := 2.1           #   until then, and the count-in runs
var END_AFTER_WIN := 1.0       # the final level's Clear stays this long, then the iris into the end screen (seconds)
var HINT_SHOW := 4.0           # the input hints stay this long into play (just spawned, or back after a lost life: the
var HINT_FADE := 0.5           #   ready screen and the count-in too), then fade out over this, hidden for the rest of it
var BLOCK_SHINE := 0.35        # small voxel blocks (walls, towers, smash, launch): how much they whiten and glow (jaws: 1)

var data: Dictionary
var song := Song.new()          # the song's MIDI, note by note (every mechanic and the background read it)
var track := TrackMap.new()
var beat := 0.5
var now := 0.0
var state := "ready"            # ready / title / tutorial / countdown / play / fail / win
var tutorial: Tutorial          # this go's tutorial (null: none, the run-up as ever)
var tut_end := -INF             # the tutorial's platform starts here: everything before it is the tutorial's course
var _title_due := false         # entered afresh: SPACE on the ready screen brings the title card first
var _title_card: Control
var _end_left := 0.0            # the final level won in the game itself: how long until the end screen
var t_start := 0.0
var t_end := 0.0
var key_pts: Array = []         # [[t, h]] piano-key height profile, linear between points
var terrace: Array = []         # the terrace's steps {t, from, to, pitch, kind} (TERRACE_PER_ST > 0; else empty)
var terrace_span: Array = []    # [t0, t1] the terraces are in, when only some sections have them (else empty)
var contour: Dictionary = {}    # the melody's contour the terraces walk on (scripts/core/terrace.gd; empty: none)
var contacts: Array = []        # sorted times where something touches the ground (plain ground, no bars)
var air_spans: Array = []       # [ta, tb] stretches the perfect player spends in the air
var busy_spans: Array = []      # [ta, tb] stretches a mechanic has taken on the ground (others keep clear)
var key_contacts: Array = []    # contacts whose key height a mechanic pillar takes (a take-off; else its first contact)
var pump := PackedFloat32Array()   # smoothed bass (0..1) every data.loud_dt: how far mechanic pillars are pumped up
var band_frames: Array = []        # smoothed spectrum for the upper and lower visualizer columns
var mech: Array = []            # mechanic pillars {ta, tb, base, top, ...}: the ground under every contact point
var free_spans: Array = []      # [ta, tb] stretches that get visualizer pillars
var static_spans: Array = []    # [ta, tb] plain ground outside the song (run-up, finish)
var g_t0 := 0.0
var g_baked := PackedFloat32Array()  # final ground height every G_DT
var pits: Array = []            # [[ta, tb]] no ground here
var arcs: Array = []            # perfect-play arcs {ta, tb, ya, vy, g[, hover]} (g: 1 falls down, -1 falls up)
var up_spans: Array = []        # [ta, tb] stretches the perfect player runs upside down (gravity pulling up)
var _mech_ta := PackedFloat64Array()  # start of every mechanic pillar, once they are final (for seg_at)
var phrases: Array = []         # phrase start times
var climax: Array = []          # [[t0, t1]]
var climax_held: Array = []     # [[t0, t1]]: the climax as track.CLIMAX_HOLD holds it (on to the 6e finish); [] without
var climax_slams: Array = []    # the kicks the held climax's hop strings end in a slam on (hops.gd HOPS_CLIMAX)
var _kick_ts := PackedFloat32Array()  # the kicks' times (kick_pulse)
var boosts: Array = []          # 3a boost bars [[t0, t1]]
var mechanics: Array = []       # this level's mechanic nodes, in MECHANICS order
var _window: Array = []         # [t0, t1] while a mechanic that only plays in one section is planning (else empty)
var player: PlayerScript
var pillars: Pillars
var background: MidiBackground
var far_waves: FarWaves           # the three far rhythm-wave rows behind the backdrop
var pixel_post: PixelPost
var cam_rig: CameraRig
var hud: Hud
var dev_on := false             # the developer's keys and tools are here (DEV_KEYS, core/dev.gd)
var event_labels                # (with dev_on only)
var tune                        # 调整模式 (T) (with dev_on only)
var cue_text: CueText           # 按键提示
var sfx: Sfx
var audio: AudioStreamPlayer
var mats := {}
var player_tuning := {}         # "player.X" rows of tuning.csv, applied once the player exists
var streak := 0                 # the score for now: mechanics passed in a row
var best_streak := 0
var stats := {"perfect": 0, "good": 0, "stars": 0}
var jump_press := NONE
var jump_held := false          # jump is being held down (gliding)
var dash_press := NONE
var down_press := NONE
var lag := 0.0                  # how far (metres) the player is behind where the song clock puts it (held back)
var _knock := 0.0               # how much further it is still being knocked back (metres)
var autoplay := false
var _settled := false           # the first step has put everything in place
var lives := 0                  # lives left this go (the tests set 1: the first fail is the end)
var checkpoint := 0.0           # song time a lost life carries on from (0: the start); set by passing a star
var countdown_to := 0.0         # the count-in runs up to this song time, when the music starts
var taken_stars: Array = []     # times of the stars taken this go (carried over a lost life)
var _continuing := false        # a life was lost: the level is about to start again from the checkpoint
var _said_later := ""           # the fail screen's words, and how long until they show (_say_after)
var _say_in := -1.0
var _place_on_ground := false   # carrying on: stand the player on whatever is under it at the first step
var freeze_left := 0.0          # carrying on: seconds the world still stands still before the count-in runs
var rest_spans: Array = []      # [ta, tb] from REST_SPANS
var _input_ts: Array = []       # sorted times of every press the mechanics need (their inputs()), for checkpoints


func _ready() -> void:
	Engine.physics_ticks_per_second = 120
	Engine.max_physics_steps_per_frame = 12
	get_tree().physics_interpolation = true  # everything moves at 120 Hz; the screen shows it smoothly at any refresh rate
	_setup_input()
	data = JSON.parse_string(FileAccess.get_file_as_string(level_path))
	_build_band_frames()
	song.load_for(level_path)
	beat = data.beat_sec
	Draw.forget()
	_setup_parts()
	var tutorial_due: bool = RunState.tutorial_due  # (only on the way into a level: not R, not a lost life, not the tools)
	RunState.tutorial_due = false
	if tutorial_due and TUTORIAL != 0 and Tutorial.COURSES.has(int(data.level)):
		tutorial = Tutorial.new()
		tutorial.L = self
		add_child(tutorial)
		tut_end = tutorial.platform_t()
	t_start = tutorial.start_t() if tutorial != null else -lead_in
	t_end = data.dur + 3.0
	track.build(data, base_speed, t_start - 1.0, t_end + 2.0)
	_make_materials()
	_build_profile()
	if tutorial != null:
		_tutorial_ground()
	_build_pump()
	pillars.build_lines()
	if tutorial != null:
		tutorial.plan()
	_plan_course()
	for m in mechanics:
		_in_section(m, m.place)
	pillars.build()
	background.build()
	far_waves.build()
	for m in mechanics:
		m.build()
	if tutorial != null:
		tutorial.build()
	cue_text.build()
	if event_labels != null:
		event_labels.build()
	cam_rig.setup()
	_setup_player()
	hud.setup(_tips())
	_setup_audio()
	now = t_start
	player.global_position = Vector3(track.x_at(now), ground_h(now) + (mech_lift if tutorial != null else 0.0) + HALF + 0.05, 0.0)
	if RunState.level == int(data.level):
		_carry_on()
		return
	RunState.clear()
	Results.begin_attempt()
	lives = LIVES
	if tutorial != null:  # (nothing to press to begin, and the tutorial says it all: no panel)
		RunState.intro_due = false
		if Iris.current != null:
			Iris.current.opened.connect(_begin_tutorial)
		else:
			_begin_tutorial()
		return
	_title_due = TITLE_CARD != 0 and RunState.intro_due
	if INTRO_PANEL != 0 and RunState.intro_due:  # (entered afresh: the panel says it all)
		RunState.intro_due = false
		if Iris.current != null:  # (coming in through the iris: the panel would hide the hero it opens from)
			Iris.current.opened.connect(_show_intro_panel)
		else:
			_show_intro_panel()
		return
	RunState.intro_due = false
	say("Level %d - %s - %s\n%s\n\nPress SPACE to start" % [data.level, data.letter, data.song,
		"Final level" if data.get("final", false) else "Training: Theme %s" % data.section])


func _show_intro_panel() -> void:
	var panel := IntroPanel.new()
	panel.L = self
	panel.hud = hud
	hud.add_child(panel)
	panel.setup()


## Where the hero stands on screen, for the iris (scripts/view/iris.gd): {center, half, corner (window pixels), body, line}.
func iris_spot() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	var p: Vector3 = player.global_position
	var top := cam.unproject_position(p + Vector3.UP * (HALF + 0.05))
	var bottom := cam.unproject_position(p - Vector3.UP * (HALF + 0.05))
	var scale_px: float = hud._px_scale()  # (those are canvas units)
	var half_h: float = absf(bottom.y - top.y) * 0.5 * scale_px
	var body: Color = (player.look._color * 1.25).clamp()  # (it shows brighter than that, lit)
	return {"center": (top + bottom) * 0.5 * scale_px, "half": Vector2(half_h * 0.62, half_h), "corner": half_h * 0.43, "body": body,
		"line": Color.from_hsv(body.h, minf(1.0, body.s * 1.6 + 0.2), 0.32)}


func _show_title_card() -> void:
	state = "title"
	_title_card = TitleCard.new()
	_title_card.L = self
	_title_card.hud = hud
	hud.add_child(_title_card)
	_title_card.setup()


## In through the iris: the tutorial.
func _begin_tutorial() -> void:
	state = "tutorial"


## The title card has run: the count-in.
func title_done() -> void:
	if tutorial != null:
		_count_in_from_plate()
		return
	state = "countdown"
	now = t_start


## The tutorial's plate has been stepped on: a clean score, the title card, and the count-in.
func plate_reached() -> void:
	streak = 0
	best_streak = 0
	stats = {"perfect": 0, "good": 0, "stars": 0}
	Results.begin_attempt()
	if TITLE_CARD != 0:
		_show_title_card()
	else:
		_count_in_from_plate()


## The count-in up to the song: 3, 2 standing on the plate, 1 running.
func _count_in_from_plate() -> void:
	state = "countdown"
	countdown_to = 0.0
	freeze_left = RESUME_FREEZE * beat


## Reloaded after losing a life: everything before the checkpoint is over; the world stands still RESUME_FREEZE beats
## (the count-in's 3, 2), then runs the last beat (1) up to the checkpoint (from the very start if no star was passed).
func _carry_on() -> void:
	lives = RunState.lives
	best_streak = RunState.best_streak
	taken_stars = RunState.stars_taken.duplicate()
	stats.stars = taken_stars.size()
	checkpoint = RunState.resume_t
	Results.rewind_to(checkpoint)
	countdown_to = checkpoint
	for m in mechanics:
		m.skip_to(checkpoint)
	state = "countdown"
	now = checkpoint - beat if checkpoint > 0.0 else t_start
	freeze_left = RESUME_FREEZE * beat
	player.global_position = Vector3(track.x_at(now), plat_h(now) + HALF + 0.05, 0.0)
	_place_on_ground = true  # (the visualizer pillars only have their heights once the first step has run)
	popup(_lives_left(), Color(1.0, 0.75, 0.55))


## Passing the star at song time t: losing a life now carries on from the last moment before it with a beat of plain
## running behind it (room for the count-in). Whether that moved the checkpoint on (no: the star doesn't save).
func set_checkpoint(t: float) -> bool:
	var c := _safe_before(t)
	if saves(c, checkpoint):
		checkpoint = c
		return true
	return false


## Whether a checkpoint at c (NAN: none) saves anything after one at cp: CHECKPOINT_MIN_GAIN beats later at least.
func saves(c: float, cp: float) -> bool:
	return not is_nan(c) and c >= cp + CHECKPOINT_MIN_GAIN * beat - 0.001


## The last moment at or before t with a beat of plain ground behind it: no gap, nothing airborne, gravity pulling
## down, and nothing still to do on the ground there (a stretch a mechanic took that is over before it is fine: that
## mechanic is skipped when carrying on); and CHECKPOINT_LEAD beats before the next thing to do (NAN: none since the
## start).
func _safe_before(t: float) -> float:
	if _input_ts.is_empty():
		for m in mechanics:
			_input_ts.append_array(m.inputs())
		_input_ts.sort()
	var c := t
	while c - beat > 0.0:
		var a := c - beat - 0.1
		var i := _input_ts.bsearch(c + 0.001)
		var next: float = _input_ts[i] if i < _input_ts.size() else INF
		var clear := not (pits + air_spans).any(func(sp): return a < sp[1] and c + 0.05 > sp[0]) \
			and not busy_spans.any(func(sp): return c - 0.05 < sp[1] and c + 0.05 > sp[0]) \
			and next - c >= CHECKPOINT_LEAD * beat - 0.001
		if clear and up_at(a) > 0.0 and up_at((a + c) * 0.5) > 0.0 and up_at(c) > 0.0:
			return c
		c -= 0.02
	return NAN


## Make every part of the level and fill its settings from tuning.csv (the level's own first: MECHANICS says which
## mechanics there are). A key that no part of any level knows gets a warning.
func _setup_parts() -> void:
	var rows := Tuning.read(int(data.level))
	for r in rows:
		Tuning.apply(self, r[0], r[1])
	for id in Tuning.list(MECHANICS):
		if not MECHANIC_SCRIPTS.has(id):
			push_warning("tuning.csv: MECHANICS has no mechanic called %s" % id)
			continue
		var m: Node3D = MECHANIC_SCRIPTS[id].new()
		m.name = id
		mechanics.append(m)
	pillars = Pillars.new()
	background = MidiBackground.new()
	far_waves = FarWaves.new()
	pixel_post = PixelPost.new()
	cam_rig = CameraRig.new()
	hud = Hud.new()
	dev_on = DEV_KEYS != 0 and Dev.on()
	if dev_on:
		event_labels = load(EVENT_LABELS).new()
		tune = load(TUNE_MODE).new()
	cue_text = CueText.new()
	sfx = Sfx.new()
	var parts: Array = [self, pillars, background, far_waves, cam_rig, sfx, pixel_post] + mechanics
	for p in parts.slice(1) + [hud] + ([event_labels, tune] if dev_on else []) + [cue_text]:
		p.L = self
		add_child(p)
	for r in rows:
		var key: String = r[0]
		if key.begins_with("player."):
			player_tuning[key.substr(7)] = r[1]
			continue
		if key.begins_with("track."):
			if not Tuning.apply(track, key.substr(6), r[1]):
				push_warning("tuning.csv: no setting called %s" % key)
			continue
		var known := parts.any(func(p): return Tuning.prop_of(p, key) != "")
		for p in parts:
			if Tuning.apply(p, key, r[1]):
				break
		if not known and not Tuning.script_has(MenuSettings, key) and not MECHANIC_SCRIPTS.values().any(func(s): return Tuning.script_has(s, key)):
			push_warning("tuning.csv: no setting called %s" % key)
	if OS.has_feature("web"):  # (what's measured on Windows is Windows's: the song clock already takes off what the browser reports)
		AUDIO_OFFSET = 0.0


## The mechanic of that name in this level (null if it doesn't have one).
func mechanic(id: String) -> Node:
	for m in mechanics:
		if m.name == id:
			return m
	return null


# ---------------------------------------------------------------- input

func _setup_input() -> void:
	_add_action("jump", [KEY_SPACE, KEY_W, KEY_UP])
	_add_action("dash", [KEY_SHIFT])  # (either Shift; J and K no longer)
	_add_action("down", [KEY_S, KEY_DOWN])
	_add_action("restart", [KEY_R])
	_add_action("autoplay", [KEY_P])
	_add_action("labels", [KEY_TAB])


## SHIFT: a dash, unless the last one was too recent (player.DASH_CD).
func press_dash() -> void:
	if player.dash():
		dash_press = now


## The shortest time between two dashes (player.DASH_CD), known before the player exists.
func dash_cd() -> float:
	return float(player_tuning.get("DASH_CD", 0.0))


## A player setting (player.X in tuning.csv, else the player script's own value), known before the player exists.
func player_setting(key: String) -> float:
	if player_tuning.has(key):
		return float(player_tuning[key])
	var p := PlayerScript.new()
	var v: float = p.get(key)
	p.free()
	return v


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.keycode = k
		InputMap.action_add_event(action, ev)


## Load level n's scene (or play this one again if there is no such level): a fresh entry, with its intro panel.
func _go_to_level(n: int) -> void:
	RunState.clear()
	RunState.intro_due = true
	RunState.tutorial_due = true
	var path := "res://scenes/level_%d.tscn" % n
	if ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)
	else:
		get_tree().reload_current_scene()


## On from the win screen: through the iris in the game itself (tools load levels themselves, and go straight on).
func _next_level() -> void:
	var n := int(data.level) + 1
	var path := "res://scenes/level_%d.tscn" % n
	if get_tree().current_scene == self and ResourceLoader.exists(path):
		RunState.clear()
		RunState.intro_due = true
		RunState.tutorial_due = true
		MenuProgress.advance_from(int(data.level))
		Iris.start(get_tree(), "res://scenes/tavern.tscn", iris_spot)
	else:
		_go_to_level(n)


func _unhandled_input(event: InputEvent) -> void:
	if _end_left > 0.0:  # (on its way to the end screen)
		return
	var key := event as InputEventKey
	if state == "tune":  # the tune mode takes every key
		tune.handle(event)
		return
	var dev := dev_on
	if dev and key != null and key.pressed and not key.echo and key.keycode == KEY_T and state in ["ready", "countdown", "play"]:
		tune.enter()
		return
	if dev and key != null and key.pressed and not key.echo and key.keycode >= KEY_1 and key.keycode <= KEY_9:
		_go_to_level(key.keycode - KEY_0)
	elif dev and key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		SHOW_TIMING = 0 if SHOW_TIMING != 0 else 1
		popup("Timing in ms %s" % ("ON" if SHOW_TIMING != 0 else "OFF"), Color.WHITE)
	elif event.is_action_pressed("restart"):
		RunState.clear()
		get_tree().reload_current_scene()
	elif dev and event.is_action_pressed("labels"):
		event_labels.visible = not event_labels.visible
	elif dev and event.is_action_pressed("autoplay"):
		autoplay = not autoplay
		popup("Autoplay ON" if autoplay else "Autoplay OFF", Color.WHITE)
	elif event.is_action_released("jump"):
		jump_held = false
	elif event.is_action_pressed("jump"):
		jump_held = true
		match state:
			"ready":
				if tutorial != null:  # (on its way in: nothing to press yet)
					return
				say("")
				if _title_due:  # (entered afresh: the title card, then the count-in)
					_title_due = false
					_show_title_card()
				else:
					state = "countdown"
					now = t_start
			"title":
				_title_card.skip()
			"tutorial":
				tutorial.pressed("jump")
			"fail":
				if _continuing:
					_continue()  # don't wait: carry on now
				else:
					get_tree().reload_current_scene()
			"win":
				_next_level()
			_:
				jump_press = now
	elif event.is_action_pressed("dash"):
		if state == "play" or state == "countdown":
			press_dash()
		elif state == "tutorial":
			tutorial.pressed("dash")
	elif event.is_action_pressed("down"):
		if state == "play" or state == "countdown":
			down_press = now
		elif state == "tutorial":
			tutorial.pressed("down")


# ---------------------------------------------------------------- the course

func evs(branch: String) -> Array:
	return data.events.filter(func(e): return e.branch == branch and (_window.is_empty() or (e.t >= _window[0] and e.t < _window[1])))


## Run a mechanic's planning step seeing only the events and notes of its own song section (MECHANIC_SECTIONS).
func _in_section(m: Node, step: Callable) -> void:
	_window = section_span(m.name)
	song.window = _window
	step.call()
	_window = []
	song.window = []


## [t0, t1] of the song section(s) a mechanic plays in ([] if it plays throughout).
func section_span(id: String) -> Array:
	for pair in Tuning.list(MECHANIC_SECTIONS):
		var kv: PackedStringArray = pair.split("=")
		if kv.size() != 2 or kv[0].strip_edges() != id:
			continue
		var span := []
		for s in data.get("sections", []):
			if s.id in kv[1].strip_edges().split("+"):
				span = [s.t, s.end_t] if span.is_empty() else [minf(span[0], s.t), maxf(span[1], s.end_t)]
		return span
	return []


func _key_h(midi: float, med: float) -> float:
	return clampf(snappedf((midi - med) * KEY_STEP, 0.15), KEY_NOTE_MIN, KEY_NOTE_MAX)


## 4a long notes set the key height; 4d down-leaps drop it and 4c up-leaps raise it (where their spring lands),
## always between KEY_MIN and KEY_MAX; rises get a short ramp. With terraces, the terrace's steps set it instead.
func _build_profile() -> void:
	if TERRACE_PER_ST > 0.0 and TERRACE_SECTIONS.strip_edges() == "":
		var flat := func(_t): return 0.0
		var first := _hops_room() + _rests()
		terrace = Terrace.plan(self, [], flat, first)
		terrace = Terrace.plan(self, [], flat, _slide_room(terrace) + first)
		key_pts = Terrace.key_points(self, terrace)
		return
	_build_keys()
	if TERRACE_PER_ST > 0.0:
		terrace_span = _sections_span(TERRACE_SECTIONS)
		if not terrace_span.is_empty():
			var base := key_pts.duplicate()
			var base_h := func(t: float) -> float: return Spans.interp(base, t)
			var first := _drum_room() + _hops_room() + _rests()
			terrace = Terrace.plan(self, terrace_span, base_h, first)
			terrace = Terrace.plan(self, terrace_span, base_h, first + _slide_room(terrace))
			key_pts = Terrace.splice(self, base, terrace, terrace_span, base_h)


## Flat ground kept clear of the terraces' steps for the slides (scripts/mechanics/slide.gd): from their combo event on,
## the clap after each landing of the terraces planned without it (`plain`: a slam's bounce, a plunge) for a 落+压
## curtain; before it, every SLIDE_EVERY_BARS-th bar's first clap off the kick (from the bar before the slides' first
## phrase, not in the climax, not where `plain` puts a slam). In their section; the terraces are then planned again
## around it.
func _slide_room(plain: Array) -> Array:
	var sl = mechanic("slide")
	if sl == null:
		return []
	var span := section_span("slide")
	var first: float = phrases[sl.SLIDE_FROM_PHRASE - 1] - data.bar_sec if phrases.size() >= sl.SLIDE_FROM_PHRASE else 0.0
	var slams_at := []
	var slam = mechanic("slam")
	for st in plain.filter(func(st): return st.kind == "slam" and slam != null):
		var drop: float = maxf(st.from - st.to, slam.SLAM_DROP_MIN)
		slams_at.append([slam.edge_of(st.t, drop) - 0.55, st.t + slam.SLAM_BOUNCE_BEATS * beat + 0.05])
	var out := []
	# 落+压: from the slides' SLIDE_COMBO_FROM event on, the clap after each landing of those slams and plunges
	var combo_from: float = sl.combo_from()
	for st in plain:
		var land := INF
		if st.kind == "slam" and slam != null:
			land = st.t + slam.SLAM_BOUNCE_BEATS * beat
		elif st.kind == "plunge":
			land = st.t
		if land >= combo_from - 0.001 and (span.is_empty() or (land >= span[0] and land <= span[1])):
			var c: float = sl.combo_clap(land)
			if not is_nan(c) and not slams_at.any(func(sp): return c - 0.1 < sp[1] and c + sl.SLIDE_T + 0.1 > sp[0]):
				out.append([c - 0.1, c + sl.SLIDE_T + 0.1, 0.0])  # (not in the way of a slam: they keep their places)
	if sl.SLIDE_EVERY_BARS <= 0:
		return out
	var last_bar := -1000
	for n in song.notes("clap"):  # (before it, one every SLIDE_EVERY_BARS bars)
		var t: float = n[0]
		var bar_i := floori((t - data.first_bar_at) / data.bar_sec + 0.001)
		if t < first - 0.001 or t >= combo_from - 0.001 or song.off_by("kick", t) < 0.05 or bar_i - last_bar < sl.SLIDE_EVERY_BARS:
			continue
		if not grid_ok(t) or not sl.flip_free(t):
			continue
		if (not span.is_empty() and (t < span[0] or t > span[1])) or climax.any(func(c): return t > c[0] - 1.0 and t < c[1]):
			continue
		if slams_at.any(func(s): return t - 0.45 < s[1] and t + sl.SLIDE_T + 0.1 > s[0]):
			continue
		out.append([t - 0.45, t + sl.SLIDE_T + 0.1, 0.05])  # (its run-up and the shortest slide; the curtain takes what is left)
		last_bar = bar_i
	return out


## [t0, t1] of the song sections named in `names` ("B1", "B1+B2"; [] if none of them is there).
func _sections_span(names: String) -> Array:
	var span := []
	for s in data.get("sections", []):
		if s.id in names.strip_edges().split("+"):
			span = [s.t, s.end_t] if span.is_empty() else [minf(span[0], s.t), maxf(span[1], s.end_t)]
	return span


## REST_SPANS as [[a, b]] (known before the course is planned).
## The held climax's hop strings (scripts/mechanics/hops.gd HOPS_CLIMAX) come first: the terraces' steps keep clear of
## them, from FLAT before each takes off to TERRACE_REST after its slam's bounce lands; their slams (climax_slams) keep
## the terraces' own slams TERRACE_SLAM_GAP away.
func _hops_room() -> Array:
	var hp = mechanic("hops")
	var out := []
	climax_slams = []
	if hp == null:
		return out
	for cs in hp.climax_plan():
		out.append([cs.pads[0][1][0] - hp.FLAT, cs.land_t + TERRACE_REST, 0.0])
		climax_slams.append(cs.slam_t)
	return out


func _rests() -> Array:
	var out := []
	for sp in Tuning.list(REST_SPANS):
		var ab: PackedStringArray = sp.split("-")
		if ab.size() == 2:
			out.append([float(ab[0]), float(ab[1])])
	return out


## The stretches the drums want in the first TERRACE_DRUM_BARS bars of the terraces' sections (each kick and its bounce
## two beats on), kept clear by the terraces' steps: [[a, b]].
func _drum_room() -> Array:
	var drums = mechanic("drums")
	if drums == null or TERRACE_DRUM_BARS <= 0:
		return []
	_window = section_span("drums")
	song.window = _window
	var kicks: Array = drums._pick_kicks()
	_window = []
	song.window = []
	var until: float = terrace_span[0] + TERRACE_DRUM_BARS * data.bar_sec - 0.01
	return kicks.filter(func(k): return in_terrace(k.t) and k.t < until).map(func(k): return [k.t - drums.DRUM_HALF_T, k.t + 2.0 * beat])


## Whether t is in the stretch only some sections' terraces cover.
func in_terrace(t: float) -> bool:
	return not terrace_span.is_empty() and t >= terrace_span[0] - 0.001 and t <= terrace_span[1] + 0.001


## The tutorial's course: flat, TUTORIAL_STEP below the ground the song starts on (the mechanic pillars' tops, mech_lift
## over the key height, are that much below it), with a straight wall up to its platform at tut_end.
func _tutorial_ground() -> void:
	var h0: float = Spans.interp(key_pts, tut_end)
	var low: float = h0 - Tutorial.STEP_UP - mech_lift
	var kept: Array = key_pts.filter(func(k): return k[0] >= tut_end)
	key_pts = [[t_start - 2.0, low], [tut_end - 0.002, low], [tut_end - 0.001, h0]] + kept


## The lowest key height a mechanic pillar at t counts (MECH_FLOOR; not in the tutorial's course, which is flat anyway).
func key_floor(t: float) -> float:
	return -INF if t < tut_end else MECH_FLOOR


## The piano keys' heights (4a / 4c / 4d, as above).
func _build_keys() -> void:
	var mids: Array = data.lead.map(func(n): return n.midi)
	mids.sort()
	var med: float = mids[mids.size() / 2] if mids.size() > 0 else 72.0
	var keys := []
	for e in evs("4a"):
		keys.append([e.t, _key_h(e.midi, med), "key"])
	for e in evs("4d"):
		keys.append([e.t, 0.0, "drop"])
	if UPLEAP_RISE > 0.0:
		for e in evs("4c"):
			keys.append([e.t + 2.0 * beat, 0.0, "rise"])
	keys.sort_custom(func(a, b): return a[0] < b[0])
	var h := 0.0
	key_pts = [[t_start - 2.0, 0.0]]
	for k in keys:
		var nh: float = k[1]
		if k[2] == "drop":
			nh = h - DROP
		elif k[2] == "rise":
			nh = h + UPLEAP_RISE
		nh = clampf(nh, KEY_MIN, KEY_MAX)
		var last_t: float = key_pts[key_pts.size() - 1][0]
		if nh > h + 0.01:
			key_pts.append([maxf(last_t + 0.002, k[0] - RAMP_T), h])
			key_pts.append([maxf(last_t + 0.004, k[0]), nh])
		elif nh < h - 0.01:
			key_pts.append([maxf(last_t + 0.002, k[0] - 0.001), h])
			key_pts.append([maxf(last_t + 0.003, k[0]), nh])
		h = nh
	key_pts.append([t_end + 10.0, h])


## The bass (bands 0-2) with a soft attack and release, so mechanic pillars pump instead of jumping.
## It comes from the precomputed spectrum, so where a platform will be at any moment is known in advance.
func _build_pump() -> void:
	var frames: Array = data.bands
	var dt: float = data.loud_dt
	var up := 1.0 - exp(-dt / 0.05)
	var down := 1.0 - exp(-dt / 0.2)
	pump.resize(frames.size())
	var v := 0.0
	for i in frames.size():
		var bass: float = (frames[i][0] + frames[i][1] + frames[i][2]) / 3.0
		v = lerpf(v, bass, up if bass > v else down)
		pump[i] = v


## The mechanics say where the player is in the air and what touches the ground; then the ground is planned around
## that and the perfect-play arcs are solved on it.
func _plan_course() -> void:
	for sp in Tuning.list(REST_SPANS):
		var ab: PackedStringArray = sp.split("-")
		if ab.size() == 2:
			rest_spans.append([float(ab[0]), float(ab[1])])
	busy_spans.append_array(rest_spans)  # (taken while the mechanics plan; plain ground once they have)
	for m in mechanics:
		_in_section(m, m.plan_air)
	for m in mechanics:
		_in_section(m, m.plan_fill)
	busy_spans = busy_spans.filter(func(s): return not rest_spans.any(func(r): return is_same(r, s)))
	for s in air_spans:
		contacts.append(s[0])
		contacts.append(s[1])
	for r in rest_spans:  # one flat pillar all along a rest
		for i in int((r[1] - r[0]) / 0.2) + 1:
			contacts.append(r[0] + i * 0.2)
	for m in mechanics:
		_in_section(m, m.plan_contacts)
	contacts.sort()
	_bake_ground()
	_plan_ground()
	for m in mechanics:
		m.solve()
	arcs.sort_custom(func(a, b): return a.ta < b.ta)


## Split the run into visualizer stretches, mechanic pillars and plain ground (needs the contacts).
func _plan_ground() -> void:
	var solid := Spans.subtract([[t_start - 2.0, t_end]], pits)
	# (the tutorial's course stands on pillars like the song's; plain ground from its platform on, or from the very start)
	var silent: Array = [tut_end if tutorial != null else t_start - 2.0, 0.25]
	var music := Spans.subtract(solid, [silent, [data.dur - 0.25, t_end]])
	static_spans = Spans.subtract(solid, music)
	var holes: Array = contacts.map(func(c):
		var r := _contact_r(c)
		return [c - r, c + r])
	for f in Spans.subtract(music, holes):
		if track.x_at(f[1]) - track.x_at(f[0]) >= BAR_MIN_SPAN:
			free_spans.append(f)
	# whatever is left inside the song is a mechanic pillar, flat at the key height of its first contact,
	# raised so it doesn't sit below the lively visualizer pillars around it
	for s in Spans.subtract(music, free_spans):
		var cs: Array = contacts.filter(func(c): return c >= s[0] and c <= s[1])
		var ks: Array = key_contacts.filter(func(c): return c >= s[0] and c <= s[1])
		if not ks.is_empty():
			cs = ks
		var at: float = cs[0] if cs.size() > 0 else (s[0] + s[1]) * 0.5
		var base := maxf(ground_h(at), -INF if in_terrace(at) else key_floor(at)) + mech_lift  # (a terrace goes where it goes)
		mech.append({"ta": s[0], "tb": s[1], "base": base, "top": base})
	if tutorial != null:  # (its platform: one still pillar, level with the plain ground the song starts on, seen like the others)
		var plat: Array = static_spans.pop_front()
		var h: float = ground_h(tutorial.plate_t)
		mech.append({"ta": plat[0], "tb": plat[1], "base": h, "top": h, "still": true, "platform": true})
	for m in mechanics:
		m.carve()
	for m in mechanics:
		m.carve_late()
	mech.sort_custom(func(a, b): return a.ta < b.ta)
	for s in mech:
		_mech_ta.append(s.ta)


func _contact_r(c: float) -> float:
	for m in mechanics:
		var r: float = m.contact_r(c)
		if r >= 0.0:
			return r
	return CONTACT_R


## The mechanic pillar under time t ({} if none); where two touch, the earlier one.
func seg_at(t: float) -> Dictionary:
	if _mech_ta.size() == mech.size() and not mech.is_empty():
		var i := _mech_ta.bsearch(t, false) - 1  # the last pillar starting at or before t
		for j in [i - 1, i]:
			if j >= 0 and t >= mech[j].ta and t <= mech[j].tb:
				return mech[j]
		return {}
	for s in mech:  # still being planned
		if t >= s.ta and t <= s.tb:
			return s
	return {}


## What the player stands on at x over mechanic pillar s with its top at `top` (a mechanic may shape it, like a drum).
func surface(s: Dictionary, top: float, x: float) -> float:
	return s.by.surface(s, top, x) if s.has("by") else top


## Top of the ground a perfect player stands on at time t: a mechanic pillar (pumping on the bass, unless a mechanic
## made it "still") or the plain run-up / finish ground. Known in advance, so arcs can aim at it.
func plat_h(t: float) -> float:
	var s := seg_at(t)
	if s.is_empty():
		return ground_h(t)
	return surface(s, s.base + (0.0 if s.get("still", false) else pump_at(t)), track.x_at(t))


## Height of whatever the player stands on at song time t and position x right now:
## a gap, a visualizer pillar, a mechanic pillar, or the plain ground outside the song.
func support_at(t: float, x: float) -> float:
	if in_pit(t):
		return -INF
	var bar := pillars.bar_support(x)
	if bar > -INF:
		return bar
	var s := seg_at(t)
	return ground_h(t) if s.is_empty() else surface(s, s.top, x)


## What the player stands on right now at x, in its own frame (upside down: the roof above it, turned over).
func player_support(x: float) -> float:
	var t := now if lag <= 0.0 else track.t_at(x)
	if player.up > 0.0:
		var s := support_at(t, x)
		for m in mechanics:  # (something floating over the ground: the hops' flutes)
			s = maxf(s, m.float_support(t, x))
		return s
	return -roof_at(t, x)


## The song time at which the run is where the player is: now, unless it has been held back.
func player_t() -> float:
	return now if lag <= 0.0 else track.t_at(player.position.x)


## Where the player runs to this step: the song clock's x, unless it is behind (held back or knocked back), when it
## catches up; and never past what a mechanic says stops it (a wall it didn't break).
func _run_x(clock_x: float, delta: float) -> float:
	if _knock > 0.0:  # being knocked back: slide back quickly, then catch up
		var k := _knock if _knock < 0.01 else _knock * (1.0 - exp(-delta / 0.06))
		_knock -= k
		lag += k
	elif lag > 0.0:
		lag = maxf(0.0, lag - CATCH_UP * base_speed * track.mult_at(now) * delta)
	var x := clock_x - lag
	for m in mechanics:
		x = minf(x, m.stop_x())
	lag = clock_x - x
	return x


## Knock the player back along the run (it then catches up with the beat, like after being held up by a wall).
func knock_back(metres: float) -> void:
	_knock += metres


## The underside of whatever is overhead at t and x for a player running upside down (INF: nothing).
func roof_at(t: float, x: float) -> float:
	var r := INF
	for m in mechanics:
		r = minf(r, m.roof_at(t, x))
	return r


## The same for the perfect player, known in advance (like plat_h).
func roof_h(t: float) -> float:
	var r := INF
	for m in mechanics:
		r = minf(r, m.roof_h(t))
	return r


## 1 where the perfect player has gravity pulling down at t, -1 where it runs upside down.
func up_at(t: float) -> float:
	for s in up_spans:
		if t >= s[0] and t < s[1]:
			return -1.0
	return 1.0


## The stretch of the run the moving parts are updated over (x only grows, so they can keep a running index).
func view_x0() -> float:
	return player.position.x - VIEW_BEHIND


func view_x1() -> float:
	return player.position.x + VIEW_AHEAD


## Up to when a jump pressed at `press` has been kept so far (JUMP_BUFFER, while it can't be used yet): a mechanic's
## early-press window (EARLY_PRESS) that opens while it is still kept takes it.
func press_kept(press: float) -> float:
	return minf(now, press + JUMP_BUFFER)


## Whether t may hold a press or a landing: on the beat grid (within GRID_TOL) — anywhere, without GRID_LOCK.
func grid_ok(t: float) -> bool:
	return GRID_LOCK == 0 or absf(grid_off(t)) <= GRID_TOL


## How far t is from the nearest beat of the grid (seconds).
func grid_off(t: float) -> float:
	return t - (data.first_bar_at + roundf((t - data.first_bar_at) / beat) * beat)


## Which beat of its bar the grid beat nearest t is (1 to the bar's beats).
func beat_of(t: float) -> int:
	return posmod(roundi((t - data.first_bar_at) / beat), maxi(1, roundi(data.bar_sec / beat))) + 1


## The first of `tracks` ("lead,kick,...") with a note starting on t (within GRID_TOL): [that note's time, the track]
## ([] if none has, or t is outside the section a mechanic is being planned in).
func note_on(t: float, tracks: String) -> Array:
	if not song.window.is_empty() and (t < song.window[0] - GRID_TOL or t >= song.window[1]):
		return []
	for tr in Tuning.list(tracks):
		var n: Array = song.nearest(tr, t)
		if not n.is_empty() and absf(n[0] - t) <= GRID_TOL:
			return [n[0], tr]
	return []


## Whether [a, b] comes within a beat of the flips' row hanging above (flip.top_spans; scripts/mechanics/flip.gd), or
## into the bar before the flips' section begins (where those rows come in): nothing that hangs or stands tall goes there.
func under_top_row(a: float, b: float) -> bool:
	var fl = mechanic("flip")
	if fl == null:
		return false
	var span: Array = section_span("flip")
	if not span.is_empty() and a < span[1] + beat and b > span[0] - data.bar_sec:
		return true
	return fl.top_spans.any(func(s): return a < s[1] + beat and b > s[0] - beat)


## Whether t is on the bar's rest beat (REST_BEAT), where nothing is placed.
func rest_beat(t: float) -> bool:
	if REST_BEAT <= 0:
		return false
	var into: float = fposmod(t - data.first_bar_at, data.bar_sec)
	return absf(into - (REST_BEAT - 1) * beat) <= 0.2


## Whether a mechanic's jump can take off now: standing, or only just off an edge.
func can_jump() -> bool:
	return player.grounded or player.air_time < COYOTE_T


func in_pit(t: float) -> bool:
	return Spans.inside(pits, t)


func to_next_contact(t: float) -> float:
	var i := contacts.bsearch(t)
	return contacts[i] - t if i < contacts.size() else INF


func nearest_contact(t: float) -> float:
	var best := INF
	for c in contacts:
		if absf(t - c) < absf(t - best):
			best = c
	return best


func dist_to_contact(t: float) -> float:
	var best := INF
	for c in contacts:
		best = minf(best, absf(t - c))
	return best


## Sample the ground once and make sure no climb is steeper than MAX_SLOPE_DEG:
## a rise that would be too steep starts earlier instead (drops stay sharp).
func _bake_ground() -> void:
	g_t0 = t_start - 2.0
	var n := int((t_end + 2.0 - g_t0) / G_DT) + 2
	g_baked.resize(n)
	for i in n:
		g_baked[i] = Spans.interp(key_pts, g_t0 + i * G_DT)
	var k := tan(deg_to_rad(MAX_SLOPE_DEG)) * base_speed * G_DT
	for i in range(n - 2, -1, -1):
		if g_t0 + i * G_DT < tut_end:  # (the front of the tutorial's platform is a wall)
			break
		g_baked[i] = maxf(g_baked[i], g_baked[i + 1] - k * track.mult_at(g_t0 + i * G_DT))


## The key height at t.
func ground_h(t: float) -> float:
	if g_baked.is_empty():
		return Spans.interp(key_pts, t)
	var f: float = (t - g_t0) / G_DT
	var i := clampi(int(f), 0, g_baked.size() - 2)
	return lerpf(g_baked[i], g_baked[i + 1], clampf(f - i, 0.0, 1.0))


func arc_at(t: float) -> Dictionary:
	for a in arcs:
		if t >= a.ta and t <= a.tb:
			return a
	return {}


## Where the capsule centre is at time t when everything is played perfectly.
func path_y(t: float) -> float:
	var a := arc_at(t)
	if a.is_empty():
		return plat_h(t) + HALF if up_at(t) > 0.0 else roof_h(t) - HALF
	if a.get("hover", false):  # (a glide sinks as it goes: "sink" m/s from "sink_t0")
		var sunk: float = a.get("sink", 0.0) * maxf(0.0, t - a.get("sink_t0", a.ta))
		if a.has("yb") and t > a.ramp_from:  # a glide stepping to its next note's height
			return lerpf(a.ya, a.yb, smoothstep(a.ramp_from, a.tb, t)) - sunk
		return a.ya - sunk
	var dt: float = t - a.ta
	return a.ya + a.vy * dt - 0.5 * GRAVITY * a.g * dt * dt


## Ballistic arc from the surface at ta (a drum's skin centre, for a drum) to height yb at tb
## (the landing height is known in advance). ya: start somewhere else; g = -1: gravity pulls up.
func arc(ta: float, tb: float, yb: float, ya := NAN, g := 1.0) -> Dictionary:
	if is_nan(ya):
		ya = plat_h(ta) + HALF
	var tt := tb - ta
	return {"ta": ta, "tb": tb, "ya": ya, "vy": (yb - ya) / tt + GRAVITY * g * tt * 0.5, "g": g}


func in_boost(t: float) -> bool:
	return boosts.any(func(b): return t >= b[0] and t < b[1])


# ---------------------------------------------------------------- the music, read back

## Keep single-sample spectrum spikes from making the mirrored pillars twitch.
func _build_band_frames() -> void:
	var raw: Array = data.bands
	band_frames.resize(raw.size())
	if raw.is_empty():
		return
	var last := raw.size() - 1
	for i in raw.size():
		var frame := PackedFloat32Array()
		frame.resize(raw[i].size())
		for band in frame.size():
			var value := 0.0
			for tap in BAND_FILTER.size():
				value += BAND_FILTER[tap] * float(raw[clampi(i + tap - 2, 0, last)][band])
			frame[band] = value / 16.0
		band_frames[i] = frame


## One visualizer band's level (0..1) at song time t; silent outside the music.
func band_at(t: float, band: int) -> float:
	if t <= 0.0 or t >= data.dur:
		return 0.0
	var frames: Array = band_frames if not band_frames.is_empty() else data.bands
	var f: float = t / data.loud_dt
	var i := mini(int(f), frames.size() - 2)
	return lerpf(frames[i][band], frames[i + 1][band], clampf(f - i, 0.0, 1.0))


func band_avg(t: float, lo: int, hi: int) -> float:
	var s := 0.0
	for k in range(lo, hi + 1):
		s += band_at(t, k)
	return s / (hi - lo + 1)


## How far into the held climax t is (climax_held): 1 from its start to the 6e finish, easing back to 0 over the bar
## after it; 0 elsewhere, and in a level that doesn't hold its climax.
func climax_k(t: float) -> float:
	var k := 0.0
	for c in climax_held:
		if t >= c[0]:
			k = maxf(k, 1.0 - clampf((t - c[1]) / data.bar_sec, 0.0, 1.0))
	return k


## The kicks' pulse in the held climax (the camera sinks, the sky and the pillars flash): 1 right on a kick, gone 0.15 s
## after, times climax_k.
func kick_pulse(t: float) -> float:
	var k := climax_k(t)
	var i := _kick_ts.bsearch(t, false) - 1  # (the last kick at or before t)
	if k <= 0.0 or i < 0:
		return 0.0
	return k * pow(maxf(0.0, 1.0 - (t - _kick_ts[i]) / 0.15), 2.0)


func pump_at(t: float) -> float:
	if pump.is_empty() or t <= 0.0 or t >= data.dur:
		return 0.0
	var f: float = t / data.loud_dt
	var i := mini(int(f), pump.size() - 2)
	return lerpf(pump[i], pump[i + 1], clampf(f - i, 0.0, 1.0)) * pump_height


## Colour of a MIDI note, kept inside the level's theme colour: the pitch class (around the circle of fifths)
## nudges the hue a little either way, and higher registers are lighter and softer.
func note_color(midi: float) -> Color:
	var pc := int(midi) % 12
	var nudge := (float((pc * 7) % 12) / 12.0 - 0.5) * 0.12
	var reg := clampf((midi - 36.0) / 54.0, 0.0, 1.0)
	return Color.from_hsv(fposmod(theme_color.h + nudge, 1.0), theme_color.s * lerpf(1.0, 0.7, reg), lerpf(0.85, 1.0, reg))


# ---------------------------------------------------------------- setup

func _make_materials() -> void:
	mats.key_a = Draw.mat(Color(0.95, 0.93, 0.88))
	mats.key_b = Draw.mat(Color(0.28, 0.28, 0.33))
	mats.glow = Draw.mat(Color(1.0, 0.85, 0.5), Color(1.0, 0.6, 0.2), 1.2)
	mats.goal = Draw.mat(Color(0.95, 0.4, 0.6), Color(0.9, 0.3, 0.5), 0.6)
	mats.abyss = Draw.mat(Color(0.12, 0.12, 0.16))
	mats.abyss.disable_receive_shadows = true  # (no pillar shadows on the floor)
	mats.abyss.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA  # far off it fades away: no hard edge
	mats.abyss.distance_fade_min_distance = 110.0
	mats.abyss.distance_fade_max_distance = 70.0
	# pillars: a unit square column scaled every frame, with a glowing cap plate on top (materials are per pillar)
	mats.bar_stem = BoxMesh.new()
	mats.bar_stem.size = Vector3.ONE
	mats.bar_cap = BoxMesh.new()
	mats.bar_cap.size = Vector3(1.0, Draw.CAP_H, 1.0)
	# every column (visualizer, mechanic, jaws, ...) shares the theme-gradient shader; colours are set per instance
	mats.pillar = ShaderMaterial.new()
	mats.pillar.shader = PillarShader
	# mechanics that must stand out against the pillars take the opposite hue of the theme
	var opposite := fposmod(theme_color.h + 0.5, 1.0)
	mats.accent = Color.from_hsv(opposite, ACCENT_S, ACCENT_V)
	mats.accent_pale = Color.from_hsv(opposite, ACCENT_S * 0.5, ACCENT_V)
	mats.accent_frag = Draw.mat(mats.accent, mats.accent, 1.0)
	mats.accent_frag_big = Draw.mat(mats.accent_pale, mats.accent_pale, 1.4)
	# 3a boost bars glow; 5a phrase starts and 6d climax shape how the ground is coloured
	for e in evs("3a"):
		boosts.append([e.t, e.t + data.bar_sec])
	phrases = evs("5a").map(func(e): return e.t)
	for e in evs("6d"):
		climax.append([e.t, e.t + 2.0 * data.bar_sec])
	if track.CLIMAX_HOLD != 0:
		climax_held = track.held.duplicate(true)
	for k in song.notes("kick"):
		_kick_ts.append(k[0])


func _setup_player() -> void:
	player = PlayerScript.new()
	player.gravity = GRAVITY
	for k in player_tuning:
		if not Tuning.apply(player, k, player_tuning[k]):
			push_warning("tuning.csv: no setting called player.%s" % k)
	add_child(player)
	player.look.theme = theme_color
	player.look.slime_color = LevelInfo.slime_color(int(data.level))
	player.look.tint_source = under_color
	player.look.sound = func(name: String, power: float): sfx.play(name, power)


## The colour of the block under x right now (for the player's tint): a visualizer pillar's note colour, a mechanic
## pillar's shade of the theme, the theme on plain ground; alpha 0 over a gap.
func under_color(x: float) -> Color:
	var t := player_t()
	if in_pit(t) or player.up < 0.0:
		return Color(0, 0, 0, 0)
	var bar := pillars.bar_color(x)
	if bar.a > 0.0:
		return bar
	var s := seg_at(t)
	return theme_color.darkened(s.get("dark", 0.0)) if not s.is_empty() else theme_color


func _setup_audio() -> void:
	sfx.setup()
	audio = AudioStreamPlayer.new()
	var path: String = data.audio
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path)
	if stream == null:  # not imported yet: read the file directly
		var file := ProjectSettings.globalize_path(path)
		stream = AudioStreamWAV.load_from_file(file) if path.get_extension() == "wav" else AudioStreamOggVorbis.load_from_file(file)
	audio.stream = stream
	add_child(audio)


# ---------------------------------------------------------------- play loop

func _song_time() -> float:
	return audio.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()


func _physics_process(delta: float) -> void:
	if autoplay and Dev.on():
		Results.mark_auto()
	var step_d := delta  # (how far this step moves the world: in the tutorial, slowed or stopped by its clock)
	if state == "countdown":
		if freeze_left > 0.0:  # carrying on: standing still first
			freeze_left -= delta
		else:
			now += delta
		if now >= countdown_to - AUDIO_OFFSET:  # the song starts that much early, so it is heard on the beat
			audio.play(maxf(0.0, now + AUDIO_OFFSET))
			state = "play"
			say("")
	elif state == "play":
		if audio.playing and DisplayServer.get_name() != "headless":
			now = maxf(now, _song_time() - AUDIO_OFFSET)
		else:  # no audio device (headless tests) or the song has ended
			now += delta
	elif state == "tutorial":
		step_d = tutorial.clock(delta)
		now += step_d
		if state != "tutorial":  # (the plate: the count-in's clock from here on)
			step_d = delta
	pillars.bulges.clear()
	for m in mechanics:
		m.prepare_bulges()
	pillars.update_motion()
	for m in mechanics:
		m.update_motion(step_d)
	if not _settled:  # everything has just been put in place: don't let it slide there from where it was made
		_settled = true
		reset_physics_interpolation()
	var x := track.x_at(now)
	if state == "countdown" or state == "play" or (state == "tutorial" and step_d > 0.0):
		if autoplay:
			for m in mechanics:
				m.autoplay()
		_handle_jump()
		_handle_down()
		for m in mechanics:
			m.before_step(step_d)
		# the bars only toss the player well before a mechanic, so it is met from the height it expects
		var calm := TOSS_CALM_T > 0.0 and to_next_contact(now) < TOSS_CALM_T
		x = _run_x(x, step_d)
		if _place_on_ground:
			_place_on_ground = false
			var under := player_support(x)
			if under > -INF:
				player.position.y = under + HALF
				player.reset_physics_interpolation()
		player.step(step_d, x, player_support(x), pillars.on_bars(x) and not calm and player.up > 0.0)
		for m in mechanics:
			m.after_step(step_d)
		if state == "tutorial":
			tutorial.after_step()
		else:
			_check_fail()
		sfx.step()
		if state == "play" and now >= data.dur + 0.3:
			_win()
	elif state == "ready" or state == "title":
		player.step(delta, x, player_support(x), false)
	elif state == "tutorial":  # (stopped, waiting for the key)
		player.look.update(delta)
	elif state == "tune":
		tune.step()
	cam_rig.update(delta)


## What only needs to change once per drawn frame.
func _process(delta: float) -> void:
	if _end_left > 0.0:
		_end_left -= delta
		if _end_left <= 0.0:
			Iris.start(get_tree(), "res://scenes/results.tscn", iris_spot)
	if _say_in >= 0.0:
		_say_in -= delta
		if _say_in < 0.0 and state == "fail":
			say(_said_later)
	background.update()
	far_waves.update()
	cue_text.update()
	hud.update(delta)
	if state == "win" or state == "fail":  # (nothing to press on these screens: no hints)
		hud.set_hints([])
	elif not MECHANIC_SECTIONS.is_empty() and not hud.hints_gone():
		hud.set_hints(_tips())


## The input hints: every mechanic's; in the final level only those of the section being played, or for the last 2 s
## before the next one starts, only those of the next (the line stays short); and until the first section with a mechanic
## starts (the song opens without one), those of that one, so they are there when the player has just spawned.
func _tips() -> Array:
	var tips := []
	var first := INF
	for m in mechanics:
		var sp := section_span(m.name)
		if not sp.is_empty():
			first = minf(first, sp[0])
	var coming := mechanics.filter(func(m): var sp := section_span(m.name); return not sp.is_empty() and ((now > sp[0] - 2.0 and now < sp[0]) or (now < first and sp[0] == first)))
	for m in mechanics:
		var span := section_span(m.name)
		if span.is_empty() or (m in coming if not coming.is_empty() else (now >= span[0] and now < span[1])):
			for tip in m.tips():
				if tip not in tips:  # (several mechanics are the same key and word)
					tips.append(tip)
	tips.append("R:\u00a0restart")  # (the developer's keys are never listed here)
	return tips


## Where the camera should look instead of at the player (a mechanic may want both its rows in view): {} or {y}.
func view_focus() -> Dictionary:
	for m in mechanics:
		var f: Dictionary = m.view_focus(now)
		if not f.is_empty():
			return f
	return {}


## A mechanic may use the press (or keep it until its beat); otherwise it is an ordinary hop.
func _handle_jump() -> void:
	if jump_press <= NONE:
		return
	for m in mechanics:
		match m.jump_claim(jump_press):
			Mechanic.TAKEN:
				jump_press = NONE
				return
			Mechanic.WAIT:
				return
	if player.grounded and not mechanics.any(func(m): return m.hop_blocked()):
		player.jump(JUMP_V)
		jump_press = NONE
	elif now - jump_press > JUMP_BUFFER:
		jump_press = NONE


## S: a mechanic may use the press (a slam in the air); otherwise, standing, a plain slide (a crouch).
func _handle_down() -> void:
	if down_press <= NONE:
		return
	for m in mechanics:
		match m.down_claim(down_press):
			Mechanic.TAKEN:
				down_press = NONE
				return
			Mechanic.WAIT:
				return
	if player.grounded:
		player.crouch(CROUCH_T)
		down_press = NONE
	elif now - down_press > JUMP_BUFFER:
		down_press = NONE


## Fallen: well below the key height — or, over a mechanic pillar set deeper than that (a slam's pad), below its top.
func _check_fail() -> void:
	var t := player_t()
	var floor_y := ground_h(t)
	var s := seg_at(t)
	if not s.is_empty():
		floor_y = minf(floor_y, s.top)
	var fell := player.up > 0.0 and player.global_position.y < floor_y + HALF - 2.5
	for m in mechanics:
		fell = fell or m.fallen()
	if not fell:
		return
	for m in mechanics:
		var reason: String = m.fail_reason()
		if reason != "":
			_fail(reason)
			return
	_fail("You fell")


## A mechanic was passed: the streak (the score for now) goes up by one.
func judge(err: float, sound := true) -> void:
	cue_text.judged(err, false)
	if sound:  # (a hop's flute is its own sound: no judgement on top of it)
		sfx.play("judge_perfect" if absf(err) <= PERFECT else "judge_good")
	streak += 1
	best_streak = maxi(best_streak, streak)
	# the word only (the streak is up in the corner); how far off the press was (err: seconds, early is negative) too
	# when SHOW_TIMING asks for it
	var e := roundi(err * 1000.0)
	var ms := " %s%d ms" % ["-" if e < 0 else "+", absi(e)] if SHOW_TIMING != 0 else ""
	Results.note(now, "perfect" if absf(err) <= PERFECT else "good")
	if absf(err) <= PERFECT:
		stats.perfect += 1
		popup("PERFECT%s" % ms, Color(1.0, 0.9, 0.35))
		pixel_post.pulse(Color(1.0, 0.9, 0.35), PERFECT_TINT)  # (the whole view, for a moment: the popup's gold)
		cam_rig.jolt(PERFECT_SHAKE)
	else:
		stats.good += 1
		popup("GOOD%s" % ms, Color.WHITE)


## A press that waited for its note (EARLY_PRESS: glide, steps, press springs): within the window it is judged as usual;
## earlier than that the move still happens on the note, but it counts as early — a miss, the streak starts again.
func judge_early(err: float, window: float, hint: String) -> void:
	if err >= -window - 0.0001:
		judge(err)
		return
	var ms := " %d ms" % roundi(-err * 1000.0) if SHOW_TIMING != 0 else ""
	miss("EARLY%s! %s" % [ms, hint])


## A mechanic was missed without failing: the streak starts again (sound false: the mechanic made its own sound). The
## popup says the word only: EARLY! / LATE! where the miss says so (its ms with SHOW_TIMING), else MISS; the whole of
## `text` (what to do instead) goes to the log.
func miss(text: String, sound := true) -> void:
	cue_text.judged(0.0, true)
	if sound:
		sfx.play("judge_miss")
	streak = 0
	Results.note(now, "miss")
	print("MISS t=%.2f %s" % [now, text])
	var timed: bool = text.begins_with("EARLY") or text.begins_with("LATE")
	popup(text.get_slice("!", 0) + "!" if timed else "MISS", Color(1.0, 0.55, 0.5))


func _fail(reason: String) -> void:
	if state != "play" and state != "countdown":
		return
	var burst: bool = player.look.shatter()  # (the body bursts into its voxels: heard now, the words a moment later)
	if burst and DisplayServer.get_name() != "headless":  # (not in a headless test run: it stops right after, and a
		sfx.play("shatter", 1.4)                          # sound still playing then is left behind at exit)
		sfx.play("plunge_land", 1.0)
	state = "fail"
	audio.stop()
	cam_rig.jolt(0.25)
	hud.clear_popup()  # (a miss's hint would argue with the fail's reason)
	print("FAIL t=%.2f %s" % [now, reason])
	Results.lost_life()
	lives -= 1
	if lives > 0:  # carry on from the last star passed, after a moment
		_continuing = true
		RunState.level = int(data.level)
		RunState.lives = lives
		RunState.resume_t = checkpoint
		RunState.stars_taken = taken_stars.duplicate()
		RunState.best_streak = best_streak
		_say_after("Failed\n%s\n\n%s" % [reason, _lives_left()], 0.4 if burst else 0.0)
		get_tree().create_timer(1.4).timeout.connect(_continue)
		return
	RunState.clear()
	_say_after("Failed\n%s\nBest streak x%d\n\nPress SPACE or R to try again" % [reason, best_streak], 0.4 if burst else 0.0)


## The fail screen's words, `delay` seconds on (so the body's burst is seen first), if the run is still lost then
## (counted down in _process: no timer left waiting if the game ends first).
func _say_after(text: String, delay: float) -> void:
	if delay <= 0.0:
		say(text)
		return
	_said_later = text
	_say_in = delay


## Start the level again from the checkpoint (it is reloaded: every mechanic fresh, the run state carried over).
func _continue() -> void:
	if _continuing and is_inside_tree():
		_continuing = false
		get_tree().reload_current_scene()


func _win() -> void:
	state = "win"
	var stars = mechanic("stars")
	var total: int = stars.stars.size() if stars != null else 0
	print("WIN best_streak=%d perfect=%d good=%d stars=%d/%d" % [best_streak, stats.perfect, stats.good, stats.stars, total])
	Results.record(int(data.level), stats.stars, total, best_streak)
	var has_next := ResourceLoader.exists("res://scenes/level_%d.tscn" % (int(data.level) + 1))
	var to_end: bool = data.get("final", false) and get_tree().current_scene == self  # (tools load levels themselves)
	if to_end:
		MenuProgress.advance_from(int(data.level))
	say("Clear!\nBest streak x%d\nPerfect %d   Good %d   Stars %d/%d\n\n%s" % [
		best_streak, stats.perfect, stats.good, stats.stars, total,
		"" if to_end else ("SPACE: tavern, then next level   R: play again" if has_next else "SPACE or R: play again")])
	if to_end:
		_end_left = maxf(0.001, END_AFTER_WIN)


## "2 lives left" (or 1 life).
func _lives_left() -> String:
	return "%d %s left" % [lives, "life" if lives == 1 else "lives"]


func say(text: String) -> void:
	hud.say(text)


func popup(text: String, color: Color) -> void:
	hud.popup(text, color)
