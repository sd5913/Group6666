extends "res://scripts/mechanics/mechanic.gd"
## 5-2 撞碎 (level 4's claps): on a clap (MIDI) a block stands on the row the player is running on — on the run below
## or hanging from the row above — a dash's lunge (player.LUNGE) ahead of where the player is on the clap, so a dash
## on the clap meets it at once and the hit lands on the note. Dash (SHIFT) on the clap to smash through; a
## drum roll (2c) is a string of small blocks, one per sixteenth, that one dash on its first note ploughs through (the
## dash can't be used again that soon: player.DASH_CD). A beat before, the block glows on the hi-hat.
## The blocks are made of voxels: smashed, they burst into them, flung on by the dash. Running into it is not a
## failure: it bursts too (more feebly) and the streak starts again. Claps that fire a wall (launch) are left to it, and
## no block stands between a fired wall's clap and its speaker block. With GRID_LOCK the blocks keep the bar's
## pattern (1 flip, 2 smash, 3 nothing, 4 smash or a fired wall): one on beat 2 and one on beat 4, on the clap there
## (else any note on it); a roll only where its first block (the one dashed) is on a beat.

const PlayerScript := preload("res://scripts/player.gd")
const Tuning := preload("res://scripts/core/tuning.gd")
const VoxelColumn := preload("res://scripts/view/voxel_column.gd")
const VoxelDebris := preload("res://scripts/view/voxel_debris.gd")

var SMASH_FROM_PHRASE := 2     # the first phrase with blocks (the first teaches the flips on their own),
var SMASH_SKIP_PHRASES := "3"  # and phrases without them (the fired walls are taught there on their own)
var SMASH_WINDOW := 0.16       # dash this close to the clap (seconds)
var SMASH_W := 0.55            # block width / height (metres); roll blocks are smaller
var SMASH_H := 1.2
var SMASH_ROLL := 0.6          # roll blocks are this much the size of a block
var SMASH_CLEAR := 0.3         # no block this close to a flip (seconds)
var SMASH_BURST := 6.5         # how fast the voxels of a smashed block fly off (m/s; run into: about half)

var blocks: Array = []          # {t, x, top, roll, w, h, judged, hit, col, follow, ...}
var _debris: VoxelDebris        # smashed blocks, while their voxels fly


## The tutorial's block, for a dash at at[0].
func teach(at: Array, _kind := "") -> void:
	var t: float = at[0]
	var tb: float = L.track.t_at(L.track.x_at(t) + L.player_setting("LUNGE") + SMASH_W * 0.5 + PlayerScript.RADIUS)
	blocks.append({"t": t, "tb": tb, "top": false, "roll": false, "w": SMASH_W, "h": SMASH_H, "track": "clap",
		"judged": false, "hit": false, "done": false, "follow": false})
	L.contacts.append(tb)


## Claps (and drum-roll sixteenths) on the row the player is on, clear of flips and fired walls.
func plan_contacts() -> void:
	var first: float = L.phrases[SMASH_FROM_PHRASE - 1] if L.phrases.size() >= SMASH_FROM_PHRASE else 0.0
	var launch = L.mechanic("launch")
	var launches: Array = launch.launches if launch != null else []
	if L.GRID_LOCK != 0:
		var g: float = L.data.first_bar_at
		while g < L.data.dur:
			if L.beat_of(g) in [2, 4] and not launches.any(func(r): return absf(r.t - g) < 0.05):
				var on: Array = L.note_on(g, "clap,kick,hat,bass,lead")
				if not on.is_empty():
					_try(on[0], false, first, on[1])
			g += L.beat
	else:
		for n in L.song.notes("clap"):
			if not launches.any(func(r): return absf(r.t - n[0]) < 0.01):  # the claps that fire a wall are its
				_try(n[0], false, first, "clap")
	for e in L.evs("2c"):
		if not L.grid_ok(e.t):
			continue  # (its first block, the one dashed, off the beat)
		for i in int(e.get("steps", 4)):
			var t: float = e.t + i * L.beat / 4.0
			if L.song.off_by("kick,clap", t) <= 0.01:
				_try(t, true, first, "kick,clap")
	blocks.sort_custom(func(a, b): return a.t < b.t)
	# a roll's blocks come too fast for a dash each: the dash on the first one carries on through the rest (as does any
	# block too soon after another for a second dash)
	var join: float = L.dash_cd() + 0.05
	for i in range(1, blocks.size()):
		var b: Dictionary = blocks[i]
		b.follow = b.top == blocks[i - 1].top and b.t - blocks[i - 1].t < join


func _try(t: float, roll: bool, first: float, track: String) -> void:
	# its near side a dash's lunge ahead of where the player is on the clap (tb: where it stands, as a time of run)
	var k0 := SMASH_ROLL if roll else 1.0
	var tb: float = L.track.t_at(L.track.x_at(t) + L.player_setting("LUNGE") + SMASH_W * k0 * 0.5 + PlayerScript.RADIUS)
	if t < maxf(first, 0.6) - 0.001 or tb > L.data.dur - 0.5 or L.rest_beat(t):
		return
	var phrase: int = L.phrases.filter(func(p): return t >= p - 0.001).size()
	if str(phrase) in Tuning.list(SMASH_SKIP_PHRASES):
		return
	# clear of flips (and other airborne stretches) by SMASH_CLEAR either side of the clap, and past the block itself
	var clear_to: float = maxf(tb, t + SMASH_CLEAR) + 0.1
	if L.air_spans.any(func(s): return t - SMASH_CLEAR < s[1] and clear_to > s[0]):
		return
	if blocks.any(func(b): return absf(b.t - t) < 0.06):
		return
	var launch = L.mechanic("launch")
	if launch != null and launch.launches.any(func(r): return t > r.t - 0.45 and tb < r.T + 0.35):
		return  # (in a fired wall's way, or on its speaker)
	var top: bool = L.up_at(tb) < 0.0
	if not top and L.in_pit(tb):
		return
	var k := SMASH_ROLL if roll else 1.0
	blocks.append({"t": t, "tb": tb, "top": top, "roll": roll, "w": SMASH_W * k, "h": SMASH_H * k, "track": track,
		"judged": false, "hit": false, "done": false, "follow": false})
	if top:
		var flip = L.mechanic("flip")
		if flip != null:
			flip.top_contacts.append(tb)
	else:
		L.contacts.append(tb)


func anchors() -> Array:
	return blocks.map(func(b): return [b.t, b.track])


func cues() -> Array:
	return blocks.filter(func(b): return not b.follow).map(func(b): return {"t": b.t, "action": "dash"})


func tips() -> Array:
	return ["[SHIFT]\u00a0dash"] if not blocks.is_empty() else []


# ---------------------------------------------------------------- look

## Each block is a voxel column whose origin is the face it shows the run: the top of a standing one, the underside of
## a hanging one.
func build() -> void:
	for b in blocks:
		b.x = L.track.x_at(b.tb)
		b.col = VoxelColumn.make(self, b.w, 1.2, b.h, 1 if b.top else -1, L.GRAVITY)
		b.col.position = Vector3(b.x, 0.0, 0.0)


## Each block rides the surface it stands on (or hangs from), glowing harder through the beat before its clap.
func update_motion(_delta: float) -> void:
	var now: float = L.now
	var x0: float = L.view_x0()
	var x1: float = L.view_x1()
	for b in blocks:
		if b.done or b.x < x0 or b.x > x1:
			continue
		var lead: float = b.t - now
		var glow := 0.15 + 0.5 * (1.0 - clampf(lead / L.beat, 0.0, 1.0)) if lead > 0.0 else 0.6
		if b.top:
			var roof: float = L.roof_at(b.tb, b.x)
			if roof == INF:
				roof = L.roof_h(b.tb)
			b.face = roof - b.h  # the side the player meets
			b.col.position = Vector3(b.x, roof - b.h, 0.0)
		else:
			var floor_y: float = L.support_at(b.tb, b.x)
			if floor_y == -INF:
				floor_y = L.plat_h(b.tb)
			b.floor = floor_y
			b.col.position = Vector3(b.x, floor_y + b.h, 0.0)
		VoxelColumn.shade(b.col, L.mats.accent, glow, L.BLOCK_SHINE)


# ---------------------------------------------------------------- play

func autoplay() -> void:
	for b in blocks:
		if not b.judged and not b.follow and L.now >= b.t - 0.004 and L.now <= b.t + 0.05 and L.dash_press < b.t - 0.08:
			L.press_dash()


## A dash in a block's window smashes it as the lunging body reaches it (and carries on through the rest of its roll,
## which burst the same way); otherwise the player runs into it — counted once the window is over, so a dash up to its
## end still smashes it.
func after_step(_delta: float) -> void:
	var p: Vector3 = L.player.global_position
	var body: float = p.x + L.player.look.position.x  # where the body is drawn, lunging ahead
	for i in blocks.size():
		var b: Dictionary = blocks[i]
		if b.done or L.now < b.t - SMASH_WINDOW:
			continue
		var near: float = b.x - b.w * 0.5 - PlayerScript.RADIUS
		if absf(L.dash_press - b.t) <= SMASH_WINDOW and not b.judged:
			b.judged = true
			b.carried = true
			L.judge(L.dash_press - b.t)
			L.dash_press = L.NONE  # one dash, one block (or one roll)
			for j in range(i + 1, blocks.size()):
				if not blocks[j].follow:
					break
				blocks[j].judged = true
				blocks[j].carried = true
		if b.get("carried", false):
			if body >= near - 0.05:
				_burst(b, false)
		elif p.x > near and not b.judged and L.now > b.t + SMASH_WINDOW:
			b.hit = true
			b.judged = true
			_burst(b, true)
			L.miss("Hit the block! Dash (SHIFT) on the clap")


## Smashed (or run into): the block bursts into its voxels from the face the player comes at, flung on in the run's
## direction; a standing block's pieces bounce on the ground it stood on, a hanging one's fall away below.
func _burst(b: Dictionary, hit: bool) -> void:
	b.done = true
	var at := Vector3(b.x - b.w * 0.5, L.player.global_position.y, 0.0)
	var run: float = L.base_speed * L.track.mult_at(L.now)
	var power: float = SMASH_BURST * (0.5 if hit else 1.0) * (0.7 if b.roll else 1.0)
	var floor_top := -INF
	var x0 := 0.0
	var x1 := 0.0
	if not b.top and b.has("floor"):
		var seg: Dictionary = L.seg_at(b.tb)
		floor_top = b.floor
		x0 = L.track.x_at(seg.ta) if not seg.is_empty() else b.x - 3.0
		x1 = L.track.x_at(seg.tb) if not seg.is_empty() else b.x + 3.0
	VoxelColumn.break_apart(b.col, at, 0.0, 0.0, power, Vector3(run * 0.5, 1.5, 0.0), floor_top, x0, x1)
	if _debris == null:
		_debris = VoxelDebris.new()
		add_child(_debris)
	_debris.add([b.col])
	L.cam_rig.jolt(0.22 if hit else (0.06 if b.roll else 0.12))
	if not b.follow:  # (a roll's small blocks after the first go with its sound)
		L.sfx.play("shatter", power / SMASH_BURST)


## A block stands at its face's place (a block's width and a little more around it).
func occupied(t: float) -> bool:
	var x: float = L.track.x_at(t)
	return blocks.any(func(b): return absf(x - L.track.x_at(b.tb)) < b.w * 0.5 + 0.5)


## Carrying on from t: the blocks before it are smashed and gone.
func skip_to(t: float) -> void:
	for b in blocks:
		if b.t < t:
			b.judged = true
			b.done = true
			b.col.visible = false


## The intro panel: DASH.
func panel_caption() -> Dictionary:
	return {"DASH": "Dash (SHIFT) on the clap to smash the block"} if not blocks.is_empty() else {}


## The intro panel's drawing: a block, cracking.
func panel_sprites() -> Array:
	if blocks.is_empty():
		return []
	return [{"family": "DASH", "t": blocks.map(func(b): return b.t).min(), "palette": {"a": L.mats.accent, "w": Color.WHITE, "t": L.theme_color}, "rows": ["............", "............", "...aaaaaa...", "...aaaaaa...", "...aaawaa...", "...aawaaa...", "...aaawwa...", "...awaaaa...", "...aaaaaa...", "...aaaaaa...", "tttttttttttt", "tttttttttttt"]}]
