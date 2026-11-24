extends "res://scripts/mechanics/mechanic.gd"
## 5-2 矮墙 (level 2's claps): on every clap of the MIDI a wall of square blocks stands in the run, a dash's lunge
## (player.LUNGE) ahead of where the player is on the clap — a dash on the clap meets it at once and smashes through,
## so the hit lands on the note; without one the player runs up against it just after. Louder claps stack more blocks;
## of two claps closer than WALL_MIN_GAP beats only the earlier gets a wall. The walls follow the claps alone: nothing
## fills the quiet stretches. Two beats before the clap a dotted outline shows the wall, blinking on the hi-hat; a beat
## before, its blocks shoot up out of the pillar one after another. The blocks are made of voxels. A wall
## that isn't dashed stops the player (in the air too): a late dash still breaks it (the player then catches up with the
## beat, and the streak starts again), but held up for longer than WALL_HOLD_T the run is lost. Where a plain hop would
## still be in the air when the wall stops the player (or it holds them up), jump does nothing: J is the way through.
## The ground is flat for a while before every wall, so the dash always starts from solid footing.

const Draw := preload("res://scripts/view/draw.gd")
const Tuning := preload("res://scripts/core/tuning.gd")
const PlayerScript := preload("res://scripts/player.gd")
const VoxelColumn := preload("res://scripts/view/voxel_column.gd")
const VoxelDebris := preload("res://scripts/view/voxel_debris.gd")

var WALL_TRACKS := "clap"      # the MIDI tracks whose notes get walls
var WALL_W := 0.5              # wall thickness along the run (metres)
var WALL_BLOCK := 0.35         # height of one block (metres)
var WALL_BLOCKS_MIN := 3       # blocks for the softest clap / the loudest
var WALL_BLOCKS_MAX := 5
var WALL_MIN_GAP := 2.0        # two walls' notes closer than this (beats): only the earlier stays
var WALL_STAGGER := 0.03       # one block pops up this long after the one under it (seconds)
var WALL_WINDOW := 0.16        # dash this close to the note (seconds)
var WALL_HOLD_T := 0.6         # held up by a wall longer than this (seconds), the run is lost
var WALL_CATCHUP_T := 0.3      # nothing else is planned this long past a wall (room to catch up after a late dash)
var WALL_RISE_T := 0.06        # how fast a block shoots up
var WALL_RISE_BEATS := 1.0     # the blocks shoot up this many beats before the note
var WALL_OUTLINE_BEATS := 2.0  # the dotted outline shows this many beats before the note
var WALL_RUNUP := 0.4          # flat ground before the note (seconds)
var WALL_SHAKE := 0.08         # camera jolt as a wall comes up

var WALL_BURST := 6.0          # how fast the voxels of a smashed wall fly off (m/s)

const FACE_GAP := 0.25         # the player stops this far short of touching the wall (see _face)
const WALL_D := 0.72           # wall depth across the run: the player's, so their front faces line up (no overlap held up)

var walls: Array = []           # {t, tb, n, track, x, seg, blocks, dashes, judged, broken, hit, held, ...}
var _dash_mat: StandardMaterial3D
var _debris: VoxelDebris        # smashed walls, while their voxels fly


## Walls on the notes of WALL_TRACKS (clap), with as many blocks as the note is loud, wherever the run is free, first
## come first served: a note closer than WALL_MIN_GAP beats to the wall before it gets none.
func plan_air() -> void:
	var notes := []  # [t, velocity, how loud in its track 0..1, track]
	for track in Tuning.list(WALL_TRACKS):
		var vels: Array = L.song.velocities(track)
		var v_lo: float = vels[0] if not vels.is_empty() else 64.0
		var v_hi: float = vels[-1] if not vels.is_empty() else 127.0
		for n in L.song.notes(track):
			notes.append([n[0], n[3], (n[3] - v_lo) / maxf(1.0, v_hi - v_lo), track])
	notes.sort_custom(func(a, b): return a[0] < b[0])
	for n in notes:
		var t: float = n[0]
		var tb := _wall_t(t)
		var start: float = t - WALL_RUNUP
		var end: float = tb + WALL_CATCHUP_T  # a little room past the wall to catch up after a late dash
		if t < 0.6 or end > L.data.dur - 0.5:
			continue
		if not walls.is_empty() and t - walls[-1].t < WALL_MIN_GAP * L.beat - 0.001:
			continue
		if (L.air_spans + L.busy_spans).any(func(s): return start < s[1] + 0.05 and end > s[0] - 0.05):
			continue
		if L.pits.any(func(p): return p[0] < end + 0.2 and p[1] > start):
			continue
		walls.append({"t": t, "tb": tb, "n": roundi(lerpf(WALL_BLOCKS_MIN, WALL_BLOCKS_MAX, n[2])), "track": n[3],
			"judged": false, "broken": false, "hit": false, "held": 0.0})
		L.busy_spans.append([start, end])


## The tutorial's wall, for a dash at at[0].
func teach(at: Array, _kind := "") -> void:
	var tb := _wall_t(at[0])
	walls.append({"t": at[0], "tb": tb, "n": WALL_BLOCKS_MAX, "track": "clap", "judged": false, "broken": false, "hit": false,
		"held": 0.0})
	L.busy_spans.append([at[0] - WALL_RUNUP, tb + WALL_CATCHUP_T])


## Where the wall stands for a dash on note t (as a time of run): the place the player stops at (its face) is a dash's
## lunge ahead of where the player is on the note, so the lunging body meets it right after the note; run into without a
## dash, it stops the player a little later, still inside the window.
func _wall_t(t: float) -> float:
	var face: float = L.track.x_at(t) + L.player_setting("LUNGE")
	return L.track.t_at(face + WALL_W * 0.5 + PlayerScript.RADIUS + FACE_GAP)


## Flat ground under the run-up, the dash and the wall.
func plan_contacts() -> void:
	for w in walls:
		for c in [w.t - WALL_RUNUP, w.t - WALL_RUNUP * 0.5, w.t, w.tb]:
			L.contacts.append(c)
		L.key_contacts.append(w.t)


func anchors() -> Array:
	return walls.map(func(w): return [w.t, w.track])


func cues() -> Array:
	return walls.map(func(w): return {"t": w.t, "action": "dash"})


func tips() -> Array:
	if walls.is_empty():
		return []
	return ["[SHIFT]\u00a0dash"]


# ---------------------------------------------------------------- look

## Each wall: its blocks (square, made of voxels, in the accent colour, waiting inside the pillar) and a dotted outline
## of the whole wall.
func build() -> void:
	_dash_mat = Draw.mat(L.mats.accent, L.mats.accent, 1.2)
	_dash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var dash_v := BoxMesh.new()
	dash_v.size = Vector3(0.07, 0.12, 0.07)
	var dash_h := BoxMesh.new()
	dash_h.size = Vector3(0.12, 0.07, 0.07)
	for w in walls:
		w.x = L.track.x_at(w.tb)
		w.seg = L.seg_at(w.tb)
		w.blocks = []
		for i in w.n:  # each block's origin is its top face
			var node := VoxelColumn.make(self, WALL_W, WALL_D, WALL_BLOCK * 0.9, -1, L.GRAVITY)
			node.position = Vector3(w.x, -100.0, 0.0)
			w.blocks.append(node)
		# the outline: dashes up both sides and across the top, a little in front of the run
		w.dashes = []
		var h: float = w.n * WALL_BLOCK
		var steps := maxi(2, roundi(h / 0.2))
		for i in steps:
			for side in [-1.0, 1.0]:
				w.dashes.append([Draw.mesh(self, dash_v, _dash_mat, Vector3.ZERO), Vector3(side * WALL_W * 0.5, (i + 0.5) * h / steps, WALL_D * 0.5 + 0.05)])
		for i in 3:
			w.dashes.append([Draw.mesh(self, dash_h, _dash_mat, Vector3.ZERO), Vector3((i - 1) * WALL_W * 0.4, h, WALL_D * 0.5 + 0.05)])
		for d in w.dashes:
			d[0].visible = false  # (until their wall comes up: update_motion puts them in their place)


## Two beats before the note: the outline, blinking on the hi-hat, and one block peeking out. A beat before: the blocks
## shoot up one after another, overshooting a touch, and glow brighter and brighter up to the note. Holding the player
## up, the wall shudders.
func update_motion(_delta: float) -> void:
	var now: float = L.now
	var x0: float = L.view_x0()
	var x1: float = L.view_x1()
	for w in walls:
		if w.x < x0 or w.x > x1 or w.broken:
			continue
		var base: float = w.seg.top if not w.seg.is_empty() else L.ground_h(w.tb)
		var lead: float = w.t - now
		var rise: float = lead - WALL_RISE_BEATS * L.beat  # time left until the blocks come up
		var show_outline: bool = rise > 0.0 and lead < WALL_OUTLINE_BEATS * L.beat
		var blink := 0.5 + 0.5 * _hat_pulse(now)
		for d in w.dashes:
			d[0].visible = show_outline and (blink > 0.55 or rise < 0.5 * L.beat)
			d[0].position = Vector3(w.x, base, 0.0) + d[1]
		var shudder: float = 0.03 * sin(now * 70.0) if w.held > 0.0 else 0.0
		for i in w.blocks.size():
			var node: GeometryInstance3D = w.blocks[i]
			var slot: float = base + (i + 0.5) * WALL_BLOCK
			var hidden: float = base - WALL_BLOCK * 0.5
			var y := hidden
			if rise > 0.0:
				if i == 0 and lead < WALL_OUTLINE_BEATS * L.beat:  # the bottom block peeks out of the pillar
					y = hidden + 0.12 * (1.0 - clampf(rise / ((WALL_OUTLINE_BEATS - WALL_RISE_BEATS) * L.beat), 0.0, 1.0))
			else:
				var age: float = -rise - i * WALL_STAGGER
				var k := clampf(age / WALL_RISE_T, 0.0, 1.0)
				y = lerpf(hidden, slot, k) + 0.06 * sin(clampf(age / 0.2, 0.0, 1.0) * PI)
				if age >= 0.0 and i == 0 and not w.get("popped", false):
					w.popped = true
					L.cam_rig.jolt(WALL_SHAKE * (0.6 + 0.2 * w.n))
			node.position = Vector3(w.x + shudder, y + WALL_BLOCK * 0.45, 0.0)  # y is the block's middle, the origin its top
			var glow := 0.15
			if rise <= 0.0:  # brightening up to the note, then staying lit while it stands in the way
				glow = 0.2 + 0.5 * (1.0 - clampf(lead / (WALL_RISE_BEATS * L.beat), 0.0, 1.0)) if lead > 0.0 else 0.7
			VoxelColumn.shade(node, L.mats.accent, glow, L.BLOCK_SHINE)


func _hat_pulse(now: float) -> float:
	var hat: Array = L.song.nearest("hat", now)
	if not hat.is_empty() and now >= hat[0] and now - hat[0] < 0.3:
		return exp(-(now - hat[0]) * 8.0)
	return 0.0


# ---------------------------------------------------------------- play

func autoplay() -> void:
	for w in walls:
		if not w.judged and L.now >= w.t - 0.004 and L.now <= w.t + 0.05 and L.dash_press < w.t - 0.08:
			L.press_dash()


## Where a plain hop would still be in the air when the next wall (not dashed through) stops the player — or the wall
## holds them up already — jump doesn't jump (it isn't jumped over: J breaks it, and no unseen face stops the player in
## mid-air): the press is used up with a little shake of the jelly, so the key doesn't feel dead. Anywhere else it is a
## plain hop.
func jump_claim(_press: float) -> int:
	var air: float = 2.0 * L.JUMP_V / L.GRAVITY  # a plain hop's time in the air (on the flat)
	for w in walls:
		if w.broken or w.judged or not w.has("x"):
			continue
		var to_face: float = (_face(w) - L.player.position.x) / (L.base_speed * L.track.mult_at(L.now))
		if w.held > 0.0 or to_face < air:
			L.player.look.bump(0.4, 0.0)
			return TAKEN
		break  # only the next wall matters
	return PASS


## A wall that hasn't been dashed through stops the player at its face.
func stop_x() -> float:
	for w in walls:
		if w.judged or not w.has("x") or L.now < w.t - WALL_RISE_BEATS * L.beat:
			continue
		if L.player.position.x <= _face(w) + 0.01:
			return _face(w)
	return INF


## Where the player's centre stops in front of a wall: short of touching by as much as the camera (ahead and in front)
## sees past the player's far side, so the wall's nearer front face doesn't seem to cut into it.
func _face(w: Dictionary) -> float:
	return w.x - WALL_W * 0.5 - PlayerScript.RADIUS - FACE_GAP


## A dash in the window carries the player through the wall, which bursts as they reach it. A later one still breaks it
## once the player is up against it (or nearly), but the streak starts again; until then the wall holds them up. Up
## against it while the window is still open, a dash still counts: it is only a miss once the window is over.
func after_step(delta: float) -> void:
	var p: Vector3 = L.player.global_position
	for w in walls:
		if w.broken or not w.has("x") or L.now < w.t - WALL_WINDOW:
			continue
		var face := _face(w)
		if not w.judged and absf(L.dash_press - w.t) <= WALL_WINDOW:
			w.judged = true
			L.judge(L.dash_press - w.t)
			L.dash_press = L.NONE
		elif not w.judged and L.dash_press > w.t + WALL_WINDOW and p.x > face - 0.6:
			w.judged = true
			L.dash_press = L.NONE
			if not w.get("missed", false):
				L.miss("LATE! Dash (SHIFT) on the clap")
		if w.judged and p.x + L.player.look.position.x >= face - 0.05:  # where the body is drawn, lunging ahead
			_shatter(w)
		elif not w.judged and p.x >= face - 0.001:
			if w.held == 0.0:
				w.hit = true
				L.sfx.play("wall_hold")
				L.cam_rig.jolt(0.18)
				L.player.look.bump(1.0, 1.0)  # squashed against it, the top still going
				Draw.burst(self, Vector3(p.x + PlayerScript.RADIUS, p.y - L.HALF + 0.1, 0.3), _dust(), 6, 2.0, 0.1)
			if not w.get("missed", false) and L.now > w.t + WALL_WINDOW:
				w.missed = true
				L.miss("Blocked by the wall! Dash (SHIFT) to smash it", false)
			w.held += delta
		break  # only the next wall matters


func fallen() -> bool:
	return walls.any(func(w): return w.held > WALL_HOLD_T and not w.judged)


var _dust_mat: StandardMaterial3D


## A puff of dust in a pale shade of the theme (not the accent: it isn't something to play with).
func _dust() -> StandardMaterial3D:
	if _dust_mat == null:
		_dust_mat = Draw.mat(L.theme_color.lightened(0.55))
		_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _dust_mat


func fail_reason() -> String:
	return "Held up by the wall: dash (SHIFT) on the clap to smash it" if fallen() else ""


## Smashed: the wall bursts into its voxels where the player meets it, flung on in the run's direction; they bounce on
## the pillar it stood on.
func _shatter(w: Dictionary) -> void:
	w.broken = true
	var p: Vector3 = L.player.global_position
	var at := Vector3(w.x - WALL_W * 0.5, p.y - L.HALF + 0.3, 0.0)
	var run: float = L.base_speed * L.track.mult_at(L.now)
	var floor_top: float = w.seg.top if not w.seg.is_empty() else L.ground_h(w.tb)
	var x0: float = L.track.x_at(w.seg.ta) if not w.seg.is_empty() else w.x - 3.0
	var x1: float = L.track.x_at(w.seg.tb) if not w.seg.is_empty() else w.x + 3.0
	for node in w.blocks:
		VoxelColumn.break_apart(node, at, 0.0, 0.0, WALL_BURST, Vector3(run * 0.9, 2.5, 0.0), floor_top, x0, x1)
	if _debris == null:
		_debris = VoxelDebris.new()
		add_child(_debris)
	_debris.add(w.blocks)
	L.cam_rig.jolt(0.16)
	L.sfx.play("shatter", 0.6 + 0.1 * w.n)


## Carrying on from t: the walls before it are broken and gone.
func skip_to(t: float) -> void:
	for w in walls:
		if w.t < t:
			w.judged = true
			w.broken = true
			for node in w.blocks:
				node.visible = false
			for d in w.dashes:
				d[0].visible = false


## The intro panel: DASH.
func panel_caption() -> Dictionary:
	return {"DASH": "Dash (SHIFT) on the beat to smash it"} if not walls.is_empty() else {}


## The intro panel's drawing: a low wall of voxels on the ground.
func panel_sprites() -> Array:
	if walls.is_empty():
		return []
	var a: Color = L.mats.accent
	return [{"family": "DASH", "t": walls.map(func(w): return w.t).min(), "palette": {"a": a, "A": a.lightened(0.3), "t": L.theme_color}, "rows": ["............", "............", "............", "...aaaaaa...", "...aAaaAa...", "...aaaaaa...", "...aaAaaa...", "...aaaaaa...", "...aAaaaa...", "...aaaaaa...", "tttttttttttt", "tttttttttttt"]}]
