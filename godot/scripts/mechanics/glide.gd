extends "res://scripts/mechanics/mechanic.gd"
## 5-4 滑翔 (level 2's melody, "floating"): every long note of the lead (MIDI, at least GLIDE_MIN_NOTE long and never
## under GLIDE_MIN_BEATS beats) is a ribbon of light high over the abyss, as long as the note. Jump on the note (it
## takes off fast, GLIDE_V, and soars GLIDE_LIFT up) and hold jump: the player lands on the ribbon and rides it, leaning
## forwards, a trail of after-images behind, the camera lifting and widening a little. The ribbon rises
## and falls with the melody (GLIDE_PITCH a semitone from its first note) and sinks steadily as it goes (GLIDE_SINK), so
## the ride is a long slide down. Letting go is judged too: within GLIDE_RELEASE_WINDOW of the note's end it scores (the
## ribbon's last beat turns pale to say so) and the block at the ribbon's end opens up out of the way, lit in the
## judgement's colour, and bursts away above, and the player dives GLIDE_DROP_MIN to GLIDE_DROP_MAX onto the ground
## after it; let go before that and the player drops into the abyss; hold on past it and the player runs into the
## block, which breaks and knocks the player down onto the ground after it (a miss, not a fail). Long notes close
## together make one ribbon that steps from pitch to pitch. While it is held, the arpeggio's notes light up along it.
## Once a ribbon is over it fades away.

const Draw := preload("res://scripts/view/draw.gd")
const VoxelColumn := preload("res://scripts/view/voxel_column.gd")
const VoxelDebris := preload("res://scripts/view/voxel_debris.gd")
const Tuning := preload("res://scripts/core/tuning.gd")
const PlayerScript := preload("res://scripts/player.gd")
const RibbonShader := preload("res://shaders/ribbon.gdshader")

var GLIDE_MIN_NOTE := 0.7      # lead notes at least this long (seconds) become a ribbon,
var GLIDE_SHORT_NOTE := 0.45   # and, where there is still room once everything is planned, notes this long
var GLIDE_FILL_TRACKS := "lead"  # ...from these tracks
var GLIDE_MIN_BEATS := 1.0     # no ribbon is shorter than this many beats
var GLIDE_RUNUP := 0.4         # flat ground before the take-off (seconds)
var GLIDE_CHAIN := 0.7         # notes closer than this (seconds between one's end and the next's start) share a ribbon
var GLIDE_FROM_PHRASE := 2     # the first phrase that has ribbons (the first teaches the walls on their own)
var GLIDE_LIFT := 3.0          # how far above the take-off the player rides the ribbon's start (metres)
var GLIDE_V := 12.0            # how fast the jump onto it takes off (m/s)
var GLIDE_PITCH := 0.35        # a ribbon steps this much per semitone from its first note,
var GLIDE_PITCH_MIN := -2.5    # never lower than this
var GLIDE_PITCH_MAX := 3.0     # or higher than this (metres)
var GLIDE_SINK := 0.5          # riding it, the player sinks this fast (m/s): the ribbon is drawn sinking with it
var GLIDE_RAMP := 0.3          # it eases from one note's height to the next's over at least this long (seconds)
var RIBBON_BODY := 1.0         # how bright the ribbon's body is (less: it stands apart from a pale backdrop)
var GLIDE_REACH := 0.5         # a jump catches the ribbon from this far below it
var GLIDE_WINDOW := 0.18       # jump this close to the note's start (seconds)
var GLIDE_RELEASE_WINDOW := 0.16  # let go this close to the note's end (seconds)
var GLIDE_PAD := 0.14          # the ground runs on this long after the note starts (a late jump still takes off)
var GLIDE_DROP_MIN := 2.0      # the ground after a ribbon is at least this far below the rider's feet at its end,
var GLIDE_DROP_MAX := 4.0      # and at most this far (metres; the dive's length: what the others keep clear)
var GLIDE_GLOW_MAX := 1.0      # the ribbon's glow never goes past this (less: it keeps its colour on a pale sky)
var GLIDE_CRUMBLE := 2.0       # how hard the end block's voxels fall apart once a ribbon is over (m/s)
var GLIDE_LEAN := 0.12         # riding, the jelly leans forwards this far (metres)

const RIBBON_W := 0.6           # the ribbon across the run (metres),
const RIBBON_H := 0.25          # its thickness (its lower edge glows),
const RIBBON_STEP := 0.25       # and how often it is sampled along the run (metres)
const TRAIL := 6                # after-images behind a rider,
const TRAIL_STEPS := 5          # this many physics steps apart
const BLOCK_W := 0.45           # the end block: width along the run,
const BLOCK_H := 1.95           # and height, from the ribbon up past the rider's head (metres)
const BLOCK_BURST := 6.0        # how hard it breaks when it is run into (m/s)
const GATE_T := 0.1             # let go in time, the end block opens up in this long (seconds), its foot this
const GATE_CLEAR := 0.25        # far above the top of a player still riding (metres), then bursts away;
const GATE_GAP := 0.05          # meanwhile it keeps this far ahead of the player's front (pushed along on a late let-go)

var glides: Array = []          # {t0, t_end, segs [{ta, tb, pitch, y}], used, judged, released, dropped, ribbon, block, ...}
var _debris: VoxelDebris        # end blocks broken, while their voxels fall
var _trail: Array = []          # after-images (MeshInstance3D)
var _history: Array = []        # the player's recent positions, newest first
var _dust_mat: StandardMaterial3D


## The tutorial's ribbon, from at[0] to at[1]: its dive comes down on the tutorial's platform, however near that is.
func teach(at: Array, _kind := "") -> void:
	_add([[at[0], at[1] - at[0], 60.0, 100.0]], "lead")
	glides[-1].pit[1] = L.tut_end - 0.001


## The melody's long notes first, before the other mechanics take the room.
func plan_air() -> void:
	_plan_notes("lead", GLIDE_MIN_NOTE, INF)


## Shorter notes fill the quiet stretches still left.
func plan_fill() -> void:
	for track in Tuning.list(GLIDE_FILL_TRACKS):
		_plan_notes(track, GLIDE_SHORT_NOTE, GLIDE_MIN_NOTE if track == "lead" else INF)
	glides.sort_custom(func(a, b): return a.t0 < b.t0)


## How far above the ribbon's first note a note's stretch of it is, by pitch.
func _rel(pitch: float, p0: float) -> float:
	return clampf((pitch - p0) * GLIDE_PITCH, GLIDE_PITCH_MIN, GLIDE_PITCH_MAX)


func _plan_notes(track: String, shortest: float, longest: float) -> void:
	var notes: Array = L.song.notes(track).filter(func(n): return n[1] >= shortest and n[1] < longest)
	var first: float = L.phrases[GLIDE_FROM_PHRASE - 1] if L.phrases.size() >= GLIDE_FROM_PHRASE else 0.0
	var group := []
	for n in notes:
		if n[0] < maxf(first, 0.5) - 0.001 or n[0] + n[1] > L.data.dur - 1.0:
			continue
		if not group.is_empty() and n[0] - (group[-1][0] + group[-1][1]) < GLIDE_CHAIN:
			group.append(n)
			continue
		_add(group, track)
		group = [n]
	_add(group, track)


## Seconds the player takes to dive from the ribbon to the ground after it (at most).
func _fall() -> float:
	return sqrt(2.0 * GLIDE_DROP_MAX / L.GRAVITY)


## Whether a ribbon from t0 to t_end (its run-up before, the dive after letting go on its end) fits between what is
## already planned. (A late let-go, or a knock off the end block, lands up to the window later: on the next one's
## run-up at the latest, which the others keep clear of their gaps.)
func _fits(t0: float, t_end: float) -> bool:
	var last: float = t_end + _fall()
	if (L.air_spans + L.busy_spans).any(func(s): return t0 - GLIDE_RUNUP < s[1] + 0.05 and last > s[0] - 0.05):
		return false
	return not L.pits.any(func(p): return p[0] < t0 and p[1] > t0 - GLIDE_RUNUP)


## The abyss runs under the whole ribbon and ends where a let-go at the window's earliest lands (the ground is at least
## GLIDE_DROP_MIN below): earlier than that, the player is still over it.
func _add(group: Array, track: String) -> void:
	if group.is_empty():
		return
	var t0: float = group[0][0]
	var t_end: float = group[-1][0] + group[-1][1]
	if t_end - t0 < GLIDE_MIN_BEATS * L.beat - 0.001 or not _fits(t0, t_end):
		return
	var segs: Array = group.map(func(n): return {"ta": n[0], "tb": n[0] + n[1], "pitch": n[2]})
	var pit := [t0 + GLIDE_PAD, t_end - GLIDE_RELEASE_WINDOW + sqrt(2.0 * GLIDE_DROP_MIN / L.GRAVITY) - 0.02]
	var air := [t0, t_end + _fall()]
	var runup := [t0 - GLIDE_RUNUP, t0]
	glides.append({"t0": t0, "t_end": t_end, "segs": segs, "used": false, "judged": false, "released": false,
		"dropped": false, "landed": false, "rel_t": INF, "track": track, "p0": group[0][2], "air": air, "pit": pit,
		"runup": runup})
	L.pits.append(pit)
	L.air_spans.append(air)
	L.busy_spans.append(runup)


## Flat ground under the run-up, at the height of the note's own key; and ground all the way from the gap's end to
## where the latest dive lands (a let-go at the window's end).
func plan_contacts() -> void:
	for g in glides:
		L.contacts.append(g.t0 - GLIDE_RUNUP)
		L.contacts.append(g.t0 - GLIDE_RUNUP * 0.5)
		L.key_contacts.append(g.t0)
		var t: float = g.pit[1] + 0.1
		while t < g.air[1] + GLIDE_RELEASE_WINDOW:
			L.contacts.append(t)
			t += 0.2


## Where a ribbon drops the player, the ground is GLIDE_DROP_MIN to GLIDE_DROP_MAX below the rider's feet at its end,
## keeping still — from the take-off as it finally is (the stairs may have raised it), so once everything else has
## carved.
func carve_late() -> void:
	for g in glides:
		var take_off: float = L.seg_at(g.t0).get("base", L.ground_h(g.t0) + L.mech_lift)
		var end_feet: float = take_off + GLIDE_LIFT + _rel(g.segs[-1].pitch, g.p0) - GLIDE_SINK * (g.t_end - g.t0)
		var t: float = g.pit[1] + 0.01
		while t < g.air[1]:
			var land: Dictionary = L.seg_at(t)
			if land.is_empty():
				t += 0.05
				continue
			if land.get("platform", false):  # (the tutorial's: it stays level with where the song starts)
				break
			land.base = clampf(land.base, end_feet - GLIDE_DROP_MAX, end_feet - GLIDE_DROP_MIN)
			land.top = land.base
			land.still = true  # (no pumping on the bass: the dive stays as deep as planned)
			t = land.tb + 0.01


## The ribbon's heights, now that the take-off ground is known; the perfect path takes off, lands on it, rides it
## (stepping between notes, sinking all along), lets go at its end and dives onto the ground after it.
func solve() -> void:
	for g in glides:
		var y0: float = L.plat_h(g.t0) + L.HALF
		for s in g.segs:
			s.y = y0 + GLIDE_LIFT + _rel(s.pitch, g.p0)
		g.reach_t = g.t0 + _rise_time(GLIDE_LIFT)
		L.arcs.append(L.arc(g.t0, g.reach_t, band_y(g, g.reach_t)))
		var t: float = g.reach_t
		for i in g.segs.size():
			var s: Dictionary = g.segs[i]
			var tb: float = s.tb if i == g.segs.size() - 1 else g.segs[i + 1].ta
			L.arcs.append({"ta": t, "tb": tb, "ya": s.y, "yb": s.y if i == g.segs.size() - 1 else g.segs[i + 1].y,
				"vy": 0.0, "g": 1.0, "hover": true, "ramp_from": _ramp_from(g, i), "sink": GLIDE_SINK, "sink_t0": g.t0})
			t = tb
		var y_end: float = band_y(g, g.t_end)
		var land_y: float = L.plat_h(g.t_end + 0.3) + L.HALF
		g.land_t = g.t_end + sqrt(2.0 * maxf(0.05, y_end - land_y) / L.GRAVITY)
		L.arcs.append(L.arc(g.t_end, g.land_t, L.plat_h(g.land_t) + L.HALF, y_end))


## Seconds the jump onto a ribbon (GLIDE_V) takes to rise h.
func _rise_time(h: float) -> float:
	var v: float = GLIDE_V
	var d: float = v * v - 2.0 * L.GRAVITY * h
	return (v - sqrt(maxf(0.0, d))) / L.GRAVITY


## The rider's centre height on ribbon g at time t (easing between its notes over GLIDE_RAMP at least, the last note's
## height after its end; sinking GLIDE_SINK a second from the note's start).
func band_y(g: Dictionary, t: float) -> float:
	var segs: Array = g.segs
	var y: float = segs[-1].y
	for i in segs.size():
		var s: Dictionary = segs[i]
		if i == segs.size() - 1:
			y = s.y
			break
		var r0 := _ramp_from(g, i)
		if t < r0:
			y = s.y
			break
		if t < segs[i + 1].ta:
			y = lerpf(s.y, segs[i + 1].y, smoothstep(r0, segs[i + 1].ta, t))
			break
	return y - GLIDE_SINK * maxf(0.0, t - g.t0)


## When ribbon g starts easing from note i's height to the next note's: at the note's end, or earlier, so the ease takes
## GLIDE_RAMP at least (never before the note starts).
func _ramp_from(g: Dictionary, i: int) -> float:
	var s: Dictionary = g.segs[i]
	if i == g.segs.size() - 1:
		return s.tb
	return maxf(s.ta, minf(s.tb, g.segs[i + 1].ta - GLIDE_RAMP))


## Whether the player is riding a ribbon right now (for the camera).
func riding() -> bool:
	return glides.any(func(g): return g.used and not g.released)


func anchors() -> Array:
	var out := []
	for g in glides:
		for s in g.segs:
			out.append([s.ta, g.track])
	return out


func cues() -> Array:
	return glides.map(func(g): return {"t": g.t0, "action": "jump", "until": g.t_end})


func tips() -> Array:
	if glides.is_empty():
		return []
	return ["[SPACE]\u00a0hold, release"]


# ---------------------------------------------------------------- look

## Each ribbon: a strip sampled along its path (the rider's feet), the arpeggio's notes drawn into it (its shader);
## a block past its end, its bottom level with the ribbon's surface and nothing between, where a rider still holding on
## runs into it. One set of after-images for whoever rides.
func build() -> void:
	_debris = VoxelDebris.new()
	add_child(_debris)
	for g in glides:
		var ta: float = g.reach_t - 0.12  # (it comes in softly where the rider catches it)
		var xa: float = L.track.x_at(ta)
		var xb: float = L.track.x_at(g.t_end)
		g.ribbon_mat = ShaderMaterial.new()
		g.ribbon_mat.shader = RibbonShader
		g.ribbon_mat.set_shader_parameter("color", Color(L.mats.accent, 0.85))
		g.ribbon_mat.set_shader_parameter("body", RIBBON_BODY)
		g.ribbon_mat.set_shader_parameter("warn_u", L.track.x_at(g.t_end - L.beat) - xa)
		g.ribbon = MeshInstance3D.new()
		g.ribbon.mesh = _strip(g, xa, xb)
		g.ribbon.material_override = g.ribbon_mat
		g.ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g.ribbon)
		_set_notes(g.ribbon_mat, L.song.between("arp", g.reach_t, g.t_end), xa)
		# the end block: its face where the player's front is a step after the window's end (a let-go right at its end
		# still opens it in time), from the ribbon's surface up past the head (nothing under it, nothing back to the
		# ribbon)
		var y_end: float = band_y(g, g.t_end)
		var face: float = L.track.x_at(_arrive(g)) + PlayerScript.RADIUS
		g.block = VoxelColumn.make(self, BLOCK_W, 1.0, BLOCK_H, 1, L.GRAVITY)  # origin: its underside
		g.block_y = y_end - L.HALF
		g.block.position = Vector3(face + BLOCK_W * 0.5, g.block_y, 0.0)
	var ghost := CapsuleMesh.new()
	ghost.radius = PlayerScript.RADIUS * 0.9
	ghost.height = PlayerScript.HEIGHT * 0.9
	for i in TRAIL:
		var m := Draw.mat(Color(L.theme_color.lightened(0.1), 0.5 * (1.0 - float(i) / TRAIL)))
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var node := Draw.mesh(self, ghost, m, Vector3.ZERO)
		node.visible = false
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trail.append(node)


## The notes a ribbon's (or a tread's) shader draws into it (shaders/note_marks.gdshaderinc): each one's stretch, metres
## along from xa (0.9 of the note, at least 0.15 m), and its time; at most 48.
static func notes_to(mat: ShaderMaterial, notes: Array, xa: float, x_at: Callable) -> void:
	var u0 := PackedFloat32Array()
	var u1 := PackedFloat32Array()
	var ts := PackedFloat32Array()
	for n in notes.slice(0, 48):
		var x: float = x_at.call(n[0])
		u0.append(x - xa)
		u1.append(x - xa + maxf(0.15, x_at.call(n[0] + n[1]) - x) * 0.9)
		ts.append(n[0])
	var k := u0.size()
	u0.resize(48)
	u1.resize(48)
	ts.resize(48)
	mat.set_shader_parameter("note_u0", u0)
	mat.set_shader_parameter("note_u1", u1)
	mat.set_shader_parameter("note_t", ts)
	mat.set_shader_parameter("notes", k)


func _set_notes(mat: ShaderMaterial, notes: Array, xa: float) -> void:
	notes_to(mat, notes, xa, L.track.x_at)


## Ribbon g as a strip from xa to xb: its top at the rider's feet, RIBBON_H thick, RIBBON_W across, sampled every
## RIBBON_STEP; UV.x is metres along it, COLOR.r 1 along its lower edge (it glows there) and 0 along its top.
func _strip(g: Dictionary, xa: float, xb: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := maxi(2, ceili((xb - xa) / RIBBON_STEP) + 1)
	var pts := []
	for i in n:
		var x: float = lerpf(xa, xb, float(i) / (n - 1))
		pts.append(Vector2(x, band_y(g, L.track.t_at(x)) - L.HALF))
	var hz := RIBBON_W * 0.5
	for i in n - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ua: float = a.x - xa
		var ub: float = b.x - xa
		# top, front (towards the camera), bottom, back
		for f in [[0.0, hz, 0.0, -hz], [0.0, hz, -RIBBON_H, hz], [-RIBBON_H, hz, -RIBBON_H, -hz], [0.0, -hz, -RIBBON_H, -hz]]:
			var v := [Vector3(a.x, a.y + f[0], f[1]), Vector3(b.x, b.y + f[0], f[1]),
				Vector3(b.x, b.y + f[2], f[3]), Vector3(a.x, a.y + f[2], f[3])]
			var uv := [Vector2(ua, 0.0), Vector2(ub, 0.0), Vector2(ub, 1.0), Vector2(ua, 1.0)]
			var low := [f[0] < 0.0, f[0] < 0.0, f[2] < 0.0, f[2] < 0.0]
			var top: float = 1.0 if f[0] == 0.0 and f[2] == 0.0 else 0.0  # (the faces the notes are drawn into)
			var front: float = 1.0 if f[1] > 0.0 and f[3] > 0.0 else 0.0
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(Color(1.0 if low[k] else 0.0, top, front))
				st.set_uv(uv[k])
				st.add_vertex(v[k])
	return st.commit()


## The ribbon brightens through the half beat before its note and while it is ridden; its arpeggio's notes light up
## on their notes (its shader); through its last beat that stretch turns pale and the end block lights up: let go now. Once it is over
## (let go, run through or fallen from), it fades away and the end block crumbles. Whoever rides leans forwards, with
## after-images behind.
func update_motion(_delta: float) -> void:
	var now: float = L.now
	var x0: float = L.view_x0()
	var x1: float = L.view_x1()
	var bass: float = L.band_avg(now, 0, 2)
	var pale := 0.3 * clampf((1.0 - GLIDE_GLOW_MAX) / 0.45, 0.0, 1.0)
	for g in glides:
		if L.track.x_at(g.t_end + GLIDE_RELEASE_WINDOW) + 3.0 < x0 or L.track.x_at(g.t0) > x1:
			continue
		var ask := smoothstep(g.t0 - 0.5 * L.beat, g.t0, now) if now < g.t0 else exp(-(now - g.t0) * 6.0)
		var warn := 0.0 if g.released else smoothstep(g.t_end - 1.5 * L.beat, g.t_end - L.beat, now)
		var over: float = minf(g.t_end, g.rel_t) if g.released else g.t_end + GLIDE_RELEASE_WINDOW
		var riding_k: float = 1.0 if g.used and not g.released else 0.0
		g.ribbon_mat.set_shader_parameter("glow", minf(GLIDE_GLOW_MAX, 0.2 + 0.2 * bass + 0.8 * ask + 0.3 * riding_k))
		g.ribbon_mat.set_shader_parameter("warn", warn)
		g.ribbon_mat.set_shader_parameter("fade", 1.0 - clampf((now - over - 0.05) / 0.4, 0.0, 1.0))
		g.ribbon_mat.set_shader_parameter("now", now)
		if g.get("block_gone", false):
			continue
		if g.has("open_t"):  # let go in time: the gate opens, up out of the way, lit in the judgement's colour
			var k := clampf((now - g.open_t) / GATE_T, 0.0, 1.0)
			g.block.position.y = g.block_y + (2.0 * L.HALF + GATE_CLEAR) * smoothstep(0.0, 1.0, k)
			_keep_ahead(g)
			VoxelColumn.shade(g.block, g.open_col, 1.0, L.BLOCK_SHINE)
			if k >= 1.0:
				_burst_open(g)
		elif now > over + 0.02 + (0.1 if not g.released else 0.0):
			_break_block(g, Vector3(0.0, 0.5, 0.0), GLIDE_CRUMBLE, 0.0)
			L.sfx.play("crumble")
		else:
			VoxelColumn.shade(g.block, L.mats.accent.lerp(Color.WHITE, pale * warn),
				minf(GLIDE_GLOW_MAX, 0.15 + 0.2 * bass + 0.8 * warn), L.BLOCK_SHINE)
	_update_rider()


## The rider's after-images (where it was a few steps ago, fading).
func _update_rider() -> void:
	var p: Vector3 = L.player.global_position
	_history.push_front(p)
	if _history.size() > TRAIL * TRAIL_STEPS + 1:
		_history.pop_back()
	var on := riding()
	for i in TRAIL:
		var k: int = (i + 1) * TRAIL_STEPS
		_trail[i].visible = on and k < _history.size()
		if _trail[i].visible:
			_trail[i].position = _history[k]
	if on:
		L.player.look.lean_to = GLIDE_LEAN


## The end block goes, its voxels flying at `power` (m/s) with `push` handed on, a `hole` that wide going at once:
## crumbling gently once the ribbon is over, bursting away above once it has opened, burst on along the run when it is
## run into.
func _break_block(g: Dictionary, push: Vector3, power: float, hole: float) -> void:
	g.block_gone = true
	var col: GeometryInstance3D = g.block
	VoxelColumn.break_apart(col, col.position + Vector3(-BLOCK_W * 0.5, L.HALF + 0.1, 0.0), hole, 0.0, power, push, -INF,
		0.0, 0.0)
	_debris.add([col])


# ---------------------------------------------------------------- play

## Takes off on the note, holds on to its end and lets go right on it.
func autoplay() -> void:
	for g in glides:
		if not g.judged and L.now >= g.t0 - 0.004 and L.now <= g.t0 + GLIDE_WINDOW and L.jump_press <= L.NONE:
			L.jump_press = L.now
		if L.now >= g.t0 - 0.004 and L.now < g.t_end - 0.004:
			L.jump_held = true
		elif L.now >= g.t_end - 0.004 and L.now < g.t_end + 0.05:
			L.jump_held = false


## A jump on a long note's start takes off for its ribbon. An early press (up to L.EARLY_PRESS, or still kept then)
## waits for the note, also while the player can't take off yet (earlier than the window it counts as early: a miss);
## it is only given up once the window is over.
func jump_claim(press: float) -> int:
	for g in glides:
		if g.judged or L.press_kept(press) < g.t0 - L.EARLY_PRESS or press > g.t0 + GLIDE_WINDOW:
			continue
		if L.now < g.t0 - 0.06 or not L.can_jump():
			return WAIT if L.now <= g.t0 + GLIDE_WINDOW else PASS
		g.judged = true
		L.player.jump(GLIDE_V)
		L.judge_early(press - g.t0, GLIDE_WINDOW, "Press SPACE when the long note starts")
		return TAKEN
	return PASS


func hop_blocked() -> bool:
	return glides.any(func(g): return not g.judged and g.t0 > L.now and g.t0 - L.now <= GLIDE_WINDOW + 0.05)


## Holding jump within reach of a ribbon keeps the player riding it, up to the window's end. Letting go of a ribbon
## ridden is judged on its note's end; holding on past the window runs the player into the end block.
func before_step(_delta: float) -> void:
	var p: Vector3 = L.player.global_position
	for g in glides:
		if L.now < g.t0 or g.released:
			continue
		if g.used:
			if not L.jump_held:
				_let_go(g)
				continue
			if L.now > g.t_end + GLIDE_RELEASE_WINDOW:
				_run_into_block(g)
				continue
		elif L.now > g.t_end:
			continue
		var y: float = band_y(g, L.now)
		if L.jump_held and not L.player.grounded and p.y >= minf(y, band_y(g, L.now - 0.1)) - GLIDE_REACH:
			L.player.hover(0.06, y)
			g.used = true


## Landed after a ribbon: a puff of dust and a jolt as deep as the dive (the jelly squashes by itself).
func after_step(_delta: float) -> void:
	for g in glides:
		if g.landed or not g.released or L.now < g.rel_t + 0.05 or not L.player.grounded:
			continue
		g.landed = true
		if _dust_mat == null:
			_dust_mat = Draw.mat(L.theme_color.lightened(0.55))
			_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var pos: Vector3 = L.player.global_position
		Draw.burst(self, Vector3(pos.x, pos.y - L.HALF + 0.05, 0.3), _dust_mat, 10, 3.0, 0.12)
		L.cam_rig.jolt(clampf(0.04 * (band_y(g, g.rel_t) - pos.y), 0.08, 0.2))


## Let go of ribbon g now: on its end (within the window) it scores and the end block opens; before that the player
## drops into the abyss.
func _let_go(g: Dictionary) -> void:
	g.released = true
	g.rel_t = L.now
	L.player.slam(0.0)  # (no riding on for the rest of the last hover: it drops at once)
	var err: float = L.now - g.t_end
	if err < -GLIDE_RELEASE_WINDOW:
		g.dropped = true
	else:
		L.judge(err)
		g.open_t = L.now
		g.open_col = Color(1.0, 0.9, 0.35) if absf(err) <= L.PERFECT else Color.WHITE  # (the popup's colours)
		_keep_ahead(g)


## Let go late, the player gets to the opening gate before it is up: it is pushed along ahead of them, off its stub —
## ahead of where they are after this physics step (they move on after the mechanics).
func _keep_ahead(g: Dictionary) -> void:
	var step := 1.0 / Engine.physics_ticks_per_second
	var front: float = L.player.position.x + L.track.x_at(L.now) - L.track.x_at(L.now - step) + PlayerScript.RADIUS
	var ahead: float = front + GATE_GAP + BLOCK_W * 0.5
	if ahead > g.block.position.x:
		g.block.position.x = ahead


## When the player's front gets to ribbon g's end block: a physics step after the release window's end.
func _arrive(g: Dictionary) -> float:
	return g.t_end + GLIDE_RELEASE_WINDOW + 1.0 / Engine.physics_ticks_per_second


## An opened end block bursts away forward and up, ahead of and above the player diving below.
func _burst_open(g: Dictionary) -> void:
	var v: float = L.track.x_at(L.now + 0.5) - L.track.x_at(L.now - 0.5)
	_break_block(g, Vector3(v + 3.0, 2.5, 0.0), GLIDE_CRUMBLE * 1.5, 0.0)
	L.sfx.play("crumble")


## Still holding on past the window: the player runs into the end block, which breaks; knocked down onto the ground
## after it, the streak is lost but the run goes on.
func _run_into_block(g: Dictionary) -> void:
	g.released = true
	g.rel_t = L.now
	L.player.slam(0.0)
	L.player.vy = -3.0
	L.player.look.bump(0.6, -0.5)
	Draw.burst(L, g.block.position + Vector3(0.0, L.HALF, 0.0), L.mats.accent_frag, 10)
	_break_block(g, Vector3(L.track.x_at(L.now + 0.5) - L.track.x_at(L.now - 0.5), 0.5, 0.0), BLOCK_BURST, BLOCK_W)
	L.cam_rig.jolt(0.15)
	L.sfx.play("shatter")
	L.miss("Hit the gate! Release SPACE when the ribbon ends")


## Let go too early: down in the abyss, below where the ground after the ribbon could have caught it.
func fallen() -> bool:
	for g in glides:
		if g.dropped and L.now < g.pit[1] + 0.6 and L.player.global_position.y < band_y(g, g.rel_t) - (GLIDE_DROP_MAX + 0.5):
			return true
	return false


func fail_reason() -> String:
	for g in glides:  # a fall into the ribbon's own abyss (not one well after it)
		if L.now > g.t0 and L.now < g.t_end + 0.8:
			if g.dropped:
				return "Released too early: hold SPACE to ride the ribbon, release when it ends"
			return "Missed the ribbon: press SPACE when the long note starts, hold it, release at the end"
	return ""


## Carrying on from t: the ribbons before it are over and gone.
func skip_to(t: float) -> void:
	for g in glides:
		if g.t_end < t:
			g.judged = true
			g.used = true
			g.released = true
			g.landed = true
			g.rel_t = g.t_end
			g.block_gone = true
			g.block.visible = false
			g.ribbon.visible = false


## The intro panel: RIDE.
func panel_caption() -> Dictionary:
	return {"RIDE": "Hold SPACE to ride, release at the end"} if not glides.is_empty() else {}


## The intro panel's drawing: a ribbon sloping down to the block at its end (nothing between).
func panel_sprites() -> Array:
	if glides.is_empty():
		return []
	var a: Color = L.mats.accent
	return [{"family": "RIDE", "t": glides.map(func(g): return g.t0).min(), "palette": {"a": a, "d": a.darkened(0.25)}, "rows": ["............", ".........dd.", "aa.......dd.", "aaaa.....dd.", "..aaaa...dd.", "....aaaa.dd.", "......aa.dd.", "............", "............", "............", "............", "............"]}]
