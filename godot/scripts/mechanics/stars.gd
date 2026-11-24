extends "res://scripts/mechanics/mechanic.gd"
## 4b (part of 5-4 琴键台阶): a star on each phrase's highest note, right on the perfect path; it pulses on the treble.
## A star that would sit in a mechanic's block (hidden in it) moves on to the next lead note clear of it. STAR_T (or
## the stars edited in the tune mode, RunState.star_t) replaces those with stars at given times, each on the nearest
## lead note. Every rest (REST_SPANS) gets a star on the lead note nearest its middle, whatever the others are.
## Every star is also a checkpoint: once the player is past it (taken or not), losing a life carries on from just
## before it. A green stand under each star says so — a little base on the ground under a star near the run, a small
## plate floating under a star up in the air — the same green in every level; it lights up as the star is passed, if
## that moved the checkpoint on (a star with no plain beat before it since the last one saves nothing: it stays dim).
## Either way, taken or not, it then fades out, gone STAND_FADE seconds after the star was passed (left there it would
## look like something forgotten); carrying on from a checkpoint, those of the stars before it and of the stars already
## taken are gone already.

const Draw := preload("res://scripts/view/draw.gd")
const RunState := preload("res://scripts/core/run_state.gd")
const Tuning := preload("res://scripts/core/tuning.gd")

const STAND_GREEN := Color(0.2, 0.78, 0.32)
const SNAP := 0.25              # a given star time goes to the nearest lead note this close (else any track's)

var STARS := true              # 4b: a star on each phrase's highest key
var STAR_T := ""               # star times instead (seconds, comma separated; empty: 4b), each on the nearest lead note
var STAND_FADE := 0.6          # a star's stand is gone this long after the star was passed (seconds)

var stars: Array = []           # {t, track, rest, pos, node, got, passed, saved, passed_t, spent, stand, stand_mat, on_ground}
var mat: Material


## The edited stars if there are any, else STAR_T, else 4b; and a star in every rest.
func place() -> void:
	mat = Draw.mat(Color(1.0, 0.95, 0.5), Color(1.0, 0.85, 0.2), 0.5 if Draw.few_slots else 2.0)
	if Draw.few_slots:  # (Compatibility lights in two passes that add up after their tone curve: it went white)
		mat.albedo_color = Color(0.7, 0.62, 0.3)
	var given: Array = RunState.star_t.duplicate() if RunState.level == int(L.data.level) else []
	if given.is_empty() and STAR_T != "":
		var vals: Array = Tuning.list(STAR_T)
		for i in vals.size():
			var what := "level %d STAR_T value %d (%s)" % [int(L.data.level), i + 1, vals[i]]
			var t: float = snap(float(vals[i]), what)[0]
			if _occupied(t):  # (left where it was put: the tune mode shows it hidden)
				push_warning("%s: hidden in a mechanic's block at %.2f" % [what, t])
			given.append(t)
	var ts: Array = given if not given.is_empty() \
		else (L.evs("4b") if STARS else []).map(func(e): return _clear_from(e.t))
	_place_times(ts)


## Stars at times ts (already on notes), plus one in every rest that has none of them.
func _place_times(ts: Array) -> void:
	var all: Array = ts.map(func(t): return [t, false])
	for r in L.rest_spans:
		var t := _rest_star(r)
		if not is_nan(t) and not ts.any(func(s): return s >= r[0] and s <= r[1]):
			all.append([t, true])
	all.sort_custom(func(a, b): return a[0] < b[0])
	for e in all:
		var t: float = e[0]
		var pos := Vector3(L.track.x_at(t), L.path_y(t) + 0.2, 0.0)
		var sphere := SphereMesh.new()
		sphere.radius = 0.28
		sphere.height = 0.56
		var node := Draw.mesh(self, sphere, mat, pos)
		var s := {"t": t, "track": snap(t)[1], "rest": e[1], "pos": pos, "node": node, "got": false, "passed": false,
			"saved": false, "passed_t": -INF, "spent": false}
		# its stand: a base on the ground right under it, or (well above the ground) a plate floating under it
		s.on_ground = pos.y - L.plat_h(t) < 1.6
		var box := BoxMesh.new()
		box.size = Vector3(0.62, 0.2, 0.62) if s.on_ground else Vector3(0.56, 0.15, 0.56)
		s.stand_mat = Draw.mat(STAND_GREEN, STAND_GREEN, 0.2)
		s.stand = Draw.mesh(self, box, s.stand_mat, pos)
		stars.append(s)


## The stars again, at times ts (the tune mode's edits; the rests' stars come back by themselves).
func rebuild(ts: Array) -> void:
	for s in stars:
		s.node.queue_free()
		s.stand.queue_free()
	stars = []
	_place_times(ts)


## The times of the stars that aren't a rest's (what STAR_T holds).
func free_times() -> Array:
	return stars.filter(func(s): return not s.rest).map(func(s): return s.t)


## The note a star given at t goes on: [time, track] — the nearest lead note within SNAP, else the nearest note of any
## track (with a warning naming `what`, if given).
func snap(t: float, what := "") -> Array:
	var n: Array = L.song.nearest("lead", t)
	if not n.is_empty() and absf(n[0] - t) <= SNAP:
		return [n[0], "lead"]
	var best := [t, "lead"]
	var off := INF
	for track in L.song.tracks:
		var m: Array = L.song.nearest(track, t)
		if not m.is_empty() and absf(m[0] - t) < off:
			off = absf(m[0] - t)
			best = [m[0], track]
	if what != "":
		push_warning("%s: no lead note within %.2f s, on the nearest %s note (%.2f) instead" % [what, SNAP, best[1], best[0]])
	return best


## t, or — where a mechanic's block stands there — the next lead note (within two bars) clear of every block.
func _clear_from(t: float) -> float:
	if not _occupied(t):
		return t
	for n in L.song.notes("lead"):
		if n[0] > t and n[0] < t + 2.0 * L.data.bar_sec and not _occupied(n[0]):
			return n[0]
	return t


func _occupied(t: float) -> bool:
	return L.mechanics.any(func(m): return m != self and m.occupied(t))


## The lead note nearest the middle of rest r, a beat in at least (room for the run-up to its checkpoint).
func _rest_star(r: Array) -> float:
	var mid: float = (r[0] + r[1]) * 0.5
	var best := NAN
	for n in L.song.notes("lead"):
		if n[0] >= r[0] + L.beat and n[0] <= r[1] and (is_nan(best) or absf(n[0] - mid) < absf(best - mid)):
			best = n[0]
	if is_nan(best):
		push_warning("level %d: no lead note in the rest %.2f-%.2f for its star" % [int(L.data.level), r[0], r[1]])
	return best


## Stars on the phrase's highest melody note (or the next one clear of a block / one in a rest / a given one's).
func anchors() -> Array:
	return stars.map(func(s): return [s.t, s.track])


## The star pulses on the treble and turns; its stand rides the ground under it (or floats under it), flashes as the
## star is passed, if that saved, and fades out. (By the clock: moved back before the star was passed, it is there again.)
func update_motion(delta: float) -> void:
	var treble: float = L.band_at(L.now, 10)
	for s in stars:
		if not s.got:
			s.node.scale = Vector3.ONE * (1.0 + 0.5 * treble)
			s.node.position.y = s.pos.y + 0.15 * treble
			s.node.rotate_y(delta * 3.0)
		var age: float = L.now - s.passed_t if s.passed else -1.0
		s.stand.visible = age < STAND_FADE and not s.spent
		if not s.stand.visible:
			continue
		var y: float = L.plat_h(s.t) + 0.1 if s.on_ground else s.pos.y - 0.45
		s.stand.position = Vector3(s.pos.x, y, 0.0)
		s.stand_mat.emission_energy_multiplier = (0.6 + 2.5 * exp(-age * 4.0)) if s.saved and age >= 0.0 else 0.2
		s.stand_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if age > 0.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
		s.stand_mat.albedo_color.a = 1.0 - pow(clampf(age / STAND_FADE, 0.0, 1.0), 2.0)


## Generous vertically: the visualizer bars may have lifted the player a little. Past a star: a checkpoint (maybe).
func after_step(_delta: float) -> void:
	for s in stars:
		if not s.passed and L.player.position.x >= s.pos.x:
			s.passed = true
			s.passed_t = L.now
			s.saved = L.set_checkpoint(s.t)
		if not s.got and absf(L.now - s.t) < 0.2 and absf(L.player.global_position.y - s.pos.y) < 1.8:
			s.got = true
			s.node.visible = false
			L.stats.stars += 1
			L.taken_stars.append(s.t)
			Draw.burst(L, s.pos, mat, 10)
			L.sfx.play("star")
			L.hud.popup("STAR %d/%d" % [L.stats.stars, stars.size()], Color(1.0, 0.92, 0.4))


## Carrying on from t: the stars taken before stay taken, their stands gone even with t before them (a stand with no star
## on it is just a green thing in the way), and those before t are passed, long enough ago for their stands to be gone
## already.
func skip_to(t: float) -> void:
	var cp := 0.0
	for s in stars:
		if L.taken_stars.any(func(tt): return absf(tt - s.t) < 0.001):
			s.got = true
			s.spent = true
			s.node.visible = false
		if s.t < t:
			s.passed = true
			s.passed_t = s.t - STAND_FADE
			var c: float = L._safe_before(s.t)
			s.saved = L.saves(c, cp)
			if s.saved:
				cp = c
