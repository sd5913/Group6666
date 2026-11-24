extends "res://scripts/mechanics/mechanic.gd"
## 大柱子 (level 3's "噔噔"): two lead notes close together (at most TOWER_PAIR_GAP apart), the second higher, from
## phrase TOWER_FROM_PHRASE on, stand as a pair of big pillars in the run (and where there would still be nothing to
## press for longer than TOWER_FILL_GAP, a single one stands on a lead note: on a strong beat if one fits, else on
## another beat, an eighth, a sixteenth): TOWER_H tall, TOWER_W wide, TOWER_GAP apart, in the accent with a bright top. The first stands a
## dash's lunge (player.LUNGE) ahead of where the player is on the first note (as a smash block does): one dash (SHIFT) on
## it smashes the pair, the first as the lunging body reaches it, the second right after (as the body reaches it, or on
## its own note): a big burst, the camera jolting and the visualizer pillars behind swelling with it. Run into without
## a dash, they burst feebly and the streak starts again (not a failure). Planned after the terrace's steps, clear of
## their edges and landings, a beat at least from the next pair; the ground under a pair is flat.

const Draw := preload("res://scripts/view/draw.gd")
const PlayerScript := preload("res://scripts/player.gd")
const VoxelColumn := preload("res://scripts/view/voxel_column.gd")
const VoxelDebris := preload("res://scripts/view/voxel_debris.gd")

var TOWER_FROM_PHRASE := 2     # the first phrase with pillars (the first teaches the plunges and slams)
var TOWER_PAIR_GAP := 0.25     # two lead notes at most this far apart make a pair (seconds),
var TOWER_PAIR_RISING := true  # the second higher (false: any two)
var TOWER_H := 1.8             # a pillar's height (metres),
var TOWER_W := 0.8             # its width along the run,
var TOWER_GAP := 0.3           # and the gap between the two (metres)
var TOWER_WINDOW := 0.16       # dash this close to the first note (seconds)
var TOWER_BURST := 8.0         # how fast the voxels of a smashed pillar fly off (m/s; run into: about half)
var TOWER_SHAKE := 0.25        # camera jolt as a pair is smashed
var TOWER_CLEAR := 0.3         # no pair this close to a terrace step's edge or landing (seconds)
var TOWER_FILL_GAP := 2.4      # where there would be nothing to press for longer than this, a single pillar (seconds)

const TOWER_D := 1.0            # a pillar's depth across the run (metres)
const RUNUP := 0.3              # flat ground before the first note (seconds)
const SWELL_T := 0.35           # how long the visualizer pillars behind swell after a smash (seconds)

var pairs: Array = []           # {t, judged, carried, hit, smashed_t, towers [{t, tb, x, col, cap, done}]}
var _debris: VoxelDebris        # smashed pillars, while their voxels fly
var _cap_mat: StandardMaterial3D


## The tutorial's pair, for a dash at at[0].
func teach(at: Array, _kind := "") -> void:
	_try(at[0], at[0] + TOWER_PAIR_GAP)


func plan_fill() -> void:
	var notes: Array = L.song.notes("lead")
	var first: float = L.phrases[TOWER_FROM_PHRASE - 1] if L.phrases.size() >= TOWER_FROM_PHRASE else 0.0
	for i in notes.size() - 1:
		var n1: Array = notes[i]
		var n2: Array = notes[i + 1]
		if n1[0] >= maxf(first, 0.6) - 0.001 and n2[0] - n1[0] <= TOWER_PAIR_GAP + 0.001 and (n2[2] > n1[2] or not TOWER_PAIR_RISING):
			_try(n1[0], n2[0])
	_fill_climax(notes)
	# where there would be nothing to press for longer than TOWER_FILL_GAP: a single pillar on a lead note, a strong
	# beat's if one fits, else one on another eighth (the one nearest the middle of that stretch)
	var grid: Array = notes.filter(func(n): return n[0] >= first - 0.001)
	var placed := true
	while placed:
		placed = false
		var ts := _inputs_all()
		ts.append(L.data.dur - 0.5)
		var last: float = first
		for t in ts:
			if t - last > TOWER_FILL_GAP:
				var mid: float = (last + t) * 0.5
				var cands: Array = grid.filter(func(n): return n[0] > last + 0.5 and n[0] < t - 0.5)
				cands.sort_custom(func(x, y): return _rank(x[0]) < _rank(y[0]) 					or (_rank(x[0]) == _rank(y[0]) and absf(x[0] - mid) < absf(y[0] - mid)))
				for n in cands:
					if _try(n[0], NAN):
						placed = true
						break
				if not placed:  # none there: one closer to the next press, with less room past it
					for n in grid.filter(func(n): return n[0] >= t - 0.5 and n[0] < t - 0.25):
						if _try(n[0], NAN, 0.1):
							placed = true
							break
				if placed:
					break
			last = maxf(last, t)
	pairs.sort_custom(func(a, b): return a.t < b.t)
	_squeeze_gaps(first)


## Still nothing to press for longer than TOWER_FILL_GAP somewhere after the first phrase (where neither a pillar nor a
## curtain fits on the ground the rest left): a short slide squeezed in there (scripts/mechanics/slide.gd).
func _squeeze_gaps(first: float) -> void:
	var sl = L.mechanic("slide")
	if sl == null:
		return
	var ts := _inputs_all()
	ts.append(L.data.dur - 0.5)
	var last: float = maxf(first, 8.0)
	for t in ts:
		if t > last and t - last > TOWER_FILL_GAP:
			sl.squeeze(last, t)
		last = maxf(last, t)


## In the climax every strong beat has something to do: where nothing is on it or in the two beats it leads (no step,
## press or bounce landing), a single pillar — on its kick, else on the lead note nearest it in those two beats (the
## first that fits). In a climax track.CLIMAX_HOLD holds on to the finish, every beat: where nothing is in it, a single
## pillar on its kick, its clap, else a lead note in it.
func _fill_climax(notes: Array) -> void:
	var held: bool = not L.climax_held.is_empty()
	var span: float = (1.0 if held else 2.0) * L.beat
	for c in (L.climax_held if held else L.climax):
		var b: float = L.data.first_bar_at + ceilf((c[0] - L.data.first_bar_at) / span - 0.01) * span
		while b < c[1] - 0.01:
			var busy: Array = _inputs_all() + L.terrace.map(func(st): return st.t)
			for m in L.mechanics:
				if m.has_method("landings"):
					busy.append_array(m.landings())
			if not busy.any(func(t): return t >= b - 0.15 and t < b + span - 0.02):
				var on: Array = L.song.notes("kick").filter(func(n): return absf(n[0] - b) <= 0.02).map(func(n): return [n[0], "kick"])
				if held:
					on.append_array(L.song.notes("clap").filter(func(n): return absf(n[0] - b) <= 0.02).map(func(n): return [n[0], "clap"]))
				var lead: Array = notes.filter(func(n): return n[0] >= b - 0.02 and n[0] < b + span - 0.25)
				lead.sort_custom(func(x, y): return absf(x[0] - b) < absf(y[0] - b))
				on.append_array(lead.map(func(n): return [n[0], "lead"]))
				for n in on:
					if _try(n[0], NAN, 0.1):
						pairs[-1].track = n[1]
						break
			b += span


## How strong a place in the bar t is: 0 a strong beat (beats 1 and 3), 1 another beat, 2 an eighth, 3 anything else.
func _rank(t: float) -> int:
	for k in 3:
		var step: float = [2.0, 1.0, 0.5][k] * L.beat
		if absf(fposmod(t - L.data.first_bar_at + 0.02, step) - 0.02) <= 0.02:
			return k
	return 3


## Every press the level asks for so far (the other mechanics' and these pillars'), in time order.
func _inputs_all() -> Array:
	var ts: Array = pairs.map(func(p): return p.t)
	for m in L.mechanics:
		if m != self:
			ts.append_array(m.inputs())
	ts.sort()
	return ts


## Where a pillar stands (as a time of run): the first's near face a dash's lunge ahead of the player on its note, the
## second (if there is one) TOWER_GAP past it.
func _tbs(t: float) -> Array:
	var x1: float = L.track.x_at(t) + L.player_setting("LUNGE") + PlayerScript.RADIUS + TOWER_W * 0.5
	return [L.track.t_at(x1), L.track.t_at(x1 + TOWER_W + TOWER_GAP)]


## A pair on notes t1 and t2 (t2 NAN: a single pillar), if it fits with `after` seconds clear past it: whether it did.
func _try(t1: float, t2: float, after := 0.2) -> bool:
	if not L.grid_ok(t1):
		return false  # (the dash on the first note: on a beat; the second only shows the "噔噔")
	var tbs := _tbs(t1)
	var single := is_nan(t2)
	var a: float = t1 - RUNUP
	var b: float = (tbs[0] if single else tbs[1]) + after
	if L.under_top_row(a, b):
		return false  # (tall: not under the flips' row hanging above)
	if b > L.data.dur - 0.5:
		return false
	# (TOWER_CLEAR from where the player lands to the first note; from where it takes off, only at an edge: the gaps)
	if L.air_spans.any(func(s): return t1 - TOWER_CLEAR < s[1] and b > s[0] - 0.05):
		return false
	if L.busy_spans.any(func(s): return a < s[1] + 0.05 and b > s[0] - 0.05):
		return false
	if L.pits.any(func(p): return t1 - TOWER_CLEAR < p[1] and b > p[0] - TOWER_CLEAR):
		return false
	if pairs.any(func(p): return absf(p.t - t1) < L.beat - 0.001):
		return false
	var towers := [{"t": t1, "tb": tbs[0], "done": false}]
	if not single:
		towers.append({"t": t2, "tb": tbs[1], "done": false})
	pairs.append({"t": t1, "judged": false, "carried": false, "hit": false, "smashed_t": -INF, "towers": towers})
	L.busy_spans.append([a, b])
	return true


## Flat ground from the run-up to past the second pillar.
func plan_contacts() -> void:
	for p in pairs:
		L.contacts.append(p.t - RUNUP)
		L.contacts.append(p.t)
		L.key_contacts.append(p.t)
		for tw in p.towers:
			L.contacts.append(tw.tb)


func anchors() -> Array:
	var out := []
	for p in pairs:
		for tw in p.towers:
			out.append([tw.t, p.get("track", "lead")])
	return out


func cues() -> Array:
	return pairs.map(func(p): return {"t": p.t, "action": "dash"})


func tips() -> Array:
	return ["[SHIFT]\u00a0dash"] if not pairs.is_empty() else []


# ---------------------------------------------------------------- look

## Each pillar a voxel column standing on the ground (its origin its top face) with a bright plate on top.
func build() -> void:
	_cap_mat = Draw.mat(L.mats.accent.lightened(0.5), L.mats.accent.lightened(0.3), 1.2)
	var cap := BoxMesh.new()
	cap.size = Vector3(TOWER_W, 0.12, TOWER_D)
	for p in pairs:
		for tw in p.towers:
			tw.x = L.track.x_at(tw.tb)
			tw.col = VoxelColumn.make(self, TOWER_W, TOWER_D, TOWER_H, -1, L.GRAVITY)
			tw.col.position = Vector3(tw.x, 0.0, 0.0)
			tw.cap = Draw.mesh(self, cap, _cap_mat, Vector3(tw.x, 0.0, 0.0))


## Prepare the swell before the visualizer row draws this frame.
func prepare_bulges() -> void:
	var now: float = L.now
	for p in pairs:
		var age: float = now - p.smashed_t
		if age >= 0.0 and age < SWELL_T:
			var x: float = p.towers[0].x
			L.pillars.bulges.append([x - 2.5, 3.0, 0.7 * (1.0 - age / SWELL_T), false])


## The pillars ride the ground, glowing harder through the beat before the first note.
func update_motion(_delta: float) -> void:
	var now: float = L.now
	var x0: float = L.view_x0()
	var x1: float = L.view_x1()
	for p in pairs:
		var lead: float = p.t - now
		var glow := 0.15 + 0.5 * (1.0 - clampf(lead / L.beat, 0.0, 1.0)) if lead > 0.0 else 0.6
		for tw in p.towers:
			if tw.done or tw.x < x0 or tw.x > x1:
				continue
			var floor_y: float = L.support_at(tw.tb, tw.x)
			if floor_y == -INF:
				floor_y = L.plat_h(tw.tb)
			tw.floor = floor_y
			tw.col.position = Vector3(tw.x, floor_y + TOWER_H, 0.0)
			tw.cap.position = Vector3(tw.x, floor_y + TOWER_H + 0.06, 0.0)
			VoxelColumn.shade(tw.col, L.mats.accent, glow, L.BLOCK_SHINE)


# ---------------------------------------------------------------- play

func autoplay() -> void:
	for p in pairs:
		if not p.judged and L.now >= p.t - 0.004 and L.now <= p.t + 0.05 and L.dash_press < p.t - 0.08:
			L.press_dash()


## A dash in the window of the first note smashes the pair: each pillar bursts as the lunging body reaches it (the
## second at the latest on its own note). Without one the player runs into them, counted once the window is over (a
## dash up to its end still smashes them): one miss, each bursting feebly as the player gets to it.
func after_step(_delta: float) -> void:
	var px: float = L.player.position.x
	var body: float = px + L.player.look.position.x  # where the body is drawn, lunging ahead
	for p in pairs:
		if L.now < p.t - TOWER_WINDOW or p.towers.all(func(tw): return tw.done):
			continue
		if not p.judged and absf(L.dash_press - p.t) <= TOWER_WINDOW:
			p.judged = true
			p.carried = true
			L.judge(L.dash_press - p.t)
			L.dash_press = L.NONE
		for k in p.towers.size():
			var tw: Dictionary = p.towers[k]
			if tw.done:
				continue
			var near: float = tw.x - TOWER_W * 0.5 - PlayerScript.RADIUS
			if p.carried:
				if body >= near - 0.05 or (k > 0 and L.now >= tw.t):
					_burst(p, tw, false)
			elif px > near and L.now > p.t + TOWER_WINDOW:
				if not p.judged:
					p.judged = true
					p.hit = true
					L.miss("Hit the tower! Dash (SHIFT) on the first hit")
				_burst(p, tw, true)


## Smashed (or run into): the pillar bursts into its voxels from the side the player comes at, flung on along the run,
## bouncing on the ground it stood on.
func _burst(p: Dictionary, tw: Dictionary, hit: bool) -> void:
	tw.done = true
	tw.cap.visible = false
	var floor_top: float = tw.get("floor", L.plat_h(tw.tb))
	var at := Vector3(tw.x - TOWER_W * 0.5, floor_top + TOWER_H * 0.5, 0.0)
	var run: float = L.base_speed * L.track.mult_at(L.now)
	var seg: Dictionary = L.seg_at(tw.tb)
	var x0: float = L.track.x_at(seg.ta) if not seg.is_empty() else tw.x - 3.0
	var x1: float = L.track.x_at(seg.tb) if not seg.is_empty() else tw.x + 3.0
	VoxelColumn.break_apart(tw.col, at, 0.0, 0.0, TOWER_BURST * (0.5 if hit else 1.0), Vector3(run * 0.6, 2.0, 0.0),
		floor_top, x0, x1)
	if _debris == null:
		_debris = VoxelDebris.new()
		add_child(_debris)
	_debris.add([tw.col])
	if not p.get("sounded", false):  # (one sound for the pair, as loud as both)
		p.sounded = true
		L.sfx.play("shatter", (0.5 if hit else 1.0) * (1.0 + 0.2 * (p.towers.size() - 1)))
	if not hit and p.smashed_t == -INF:
		p.smashed_t = L.now
		L.cam_rig.jolt(TOWER_SHAKE)
	elif hit:
		L.cam_rig.jolt(0.12)


## A pillar stands at its place (its width and a little more around it).
func occupied(t: float) -> bool:
	var x: float = L.track.x_at(t)
	return pairs.any(func(p): return p.towers.any(func(tw): return absf(x - L.track.x_at(tw.tb)) < TOWER_W * 0.5 + 0.5))


## Carrying on from t: the pairs before it are smashed and gone.
func skip_to(t: float) -> void:
	for p in pairs:
		if p.t < t:
			p.judged = true
			for tw in p.towers:
				tw.done = true
				tw.col.visible = false
				tw.cap.visible = false


## The intro panel: DASH.
func panel_caption() -> Dictionary:
	return {"DASH": "Dash (SHIFT) on the beat to smash it"} if not pairs.is_empty() else {}


## The intro panel's drawing: a pair of big pillars, the second higher, bright caps.
func panel_sprites() -> Array:
	if pairs.is_empty():
		return []
	var a: Color = L.mats.accent
	return [{"family": "DASH", "t": pairs.map(func(p): return p.t).min(), "palette": {"a": a, "A": a.lightened(0.5), "t": L.theme_color}, "rows": [".......AAA..", ".......aaa..", ".......aaa..", ".AAA...aaa..", ".aaa...aaa..", ".aaa...aaa..", ".aaa...aaa..", ".aaa...aaa..", ".aaa...aaa..", ".aaa...aaa..", "tttttttttttt", "tttttttttttt"]}]
