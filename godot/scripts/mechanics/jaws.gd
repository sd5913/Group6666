extends "res://scripts/mechanics/mechanic.gd"
## 5-2 合拢方块 (level 1's claps): a pair of jaw columns, one rising from below and one hanging from above the player's
## path, that breathe with the music, slowly close in on the path (leaving just enough room) and slam shut on the clap,
## right behind the player, then burst into the voxels they are made of, with a small jolt. Never a failure: only if
## the player does touch one (jumping up into it, say) are the voxels it hits knocked out with it, and the rest crumbles
## a moment later. A dash within the window adds to the streak.
## Accents (2b) are big, paler jaws with a tighter window; a roll (2c) is a string of small ones.
## In the final level (JAW_TRACKS) they stand on the notes of a MIDI track instead, wherever the player runs on the
## ground clear of the other mechanics; a note too soon after the last for a dash of its own (player.DASH_CD) gets a
## small jaw that the last dash carries through.

const Tuning := preload("res://scripts/core/tuning.gd")
const VoxelColumn := preload("res://scripts/view/voxel_column.gd")
const VoxelDebris := preload("res://scripts/view/voxel_debris.gd")
const PlayerScript := preload("res://scripts/player.gd")

const JAW_REACH := 10.0        # how far each jaw column reaches (up into the sky / down into the abyss)

var JAW_TRACKS := ""           # MIDI tracks whose notes become jaws ("pulse"); empty: the clap events (2a / 2b / 2c)
var BIG_JAWS := true           # 2b accents get big jaws (false: like the others)
var JAW_SKIP_DRUMS := true     # leave out jaws that would stand over a drum
var JAW_W := 0.9               # width along the run: normal, big (2b) and roll (2c) jaws
var JAW_W_BIG := 1.2
var JAW_W_ROLL := 0.6
var JAW_OPEN := 1.3            # half the gap when fully open,
var JAW_CLOSE_T := 1.0         # how long before the clap they start (slowly) closing in on the player's path (seconds),
var JAW_CLEAR := 0.1           # the room they still leave around the passing player,
var JAW_AIR_MARGIN := 0.0      # ...and a little more over a bounce, whose real path wanders a bit,
var JAW_SLAM_T := 0.05         # how fast they slam shut on the clap, right behind the player,
var JAW_LEAD_T := 0.15         # about how far before the clap point they stand (so the player is through on the clap)
var JAW_SHAKE := 0.14          # camera jolt when they meet (normal / big)
var JAW_SHAKE_BIG := 0.2
var BIG_WINDOW := 0.08         # 2b big jaws need a tighter hit (the normal window is the level's WINDOW)
var JAW_BURST := 7.0           # how fast the voxels at the seam fly off when they slam shut (m/s; big jaws: x1.4)
var JAW_DEBRIS_T := 2.2        # seconds until the last voxel of a broken jaw is gone
var JAW_SHINE := 1.0           # how much they whiten and glow as they close in (less keeps a deep colour on a pale sky)

var blocks: Array = []          # {t, y, big, x, w, d, broken, branch, seg, centre, gap, squeeze, bot, top, ...}, by time
var _view_i := 0                # the first jaw not yet left behind the picture
var _check_i := 0               # the first jaw that can still be met or scored
var _debris: VoxelDebris        # broken jaws while their voxels fly
var _taught: Array = []         # the tutorial's jaws: when they close


## The tutorial's jaws, closing at at[0].
func teach(at: Array, _kind := "") -> void:
	_taught.append(at[0])


## Claps keep the ground flat where the player passes between the jaws (they stand just behind the clap point).
func plan_contacts() -> void:
	for t in _taught:
		L.contacts.append(t)
		L.contacts.append(t - JAW_LEAD_T)
	if not JAW_TRACKS.is_empty():
		for t in _track_notes():
			L.contacts.append(t)
			L.contacts.append(t - JAW_LEAD_T)
		return
	for b in ["2a", "2b", "2c"]:
		for e in L.evs(b):
			for i in (int(e.get("steps", 4)) if b == "2c" else 1):
				var tc: float = e.t + i * L.beat / 4.0
				if not L.air_spans.any(func(s): return tc > s[0] and tc < s[1]):
					L.contacts.append(tc)
					L.contacts.append(tc - JAW_LEAD_T)


## Claps are jaws on the perfect path; accents make them big.
func place() -> void:
	for t in _taught:
		_add_block(t, false, "2a")
	if not JAW_TRACKS.is_empty():
		var lead_t := -INF
		for t in _track_notes():
			var follow: bool = t - lead_t < L.dash_cd() + 0.05
			var b := _add_block(t, false, "2c" if follow else "2a")
			if not b.is_empty():
				b.track = JAW_TRACKS
				b.follow = follow
				if not follow:
					lead_t = t
		blocks.sort_custom(func(a, b): return a.t < b.t)
		return
	var claps: Array = L.evs("2a")
	var accents: Array = L.evs("2b")
	var drums := _drums()
	for e in claps:
		var big := BIG_JAWS and accents.any(func(a): return absf(a.t - e.t) < 0.07)
		_add_block(e.t, big, "2b" if big else "2a")
	for a in accents:
		if claps.any(func(c): return absf(c.t - a.t) < 0.07):
			continue
		if drums.any(func(d): return absf(d.t - a.t) < 0.1):
			continue
		_add_block(a.t, BIG_JAWS, "2b")
	for e in L.evs("2c"):
		for i in int(e.get("steps", 4)):
			_add_block(e.t + i * L.beat / 4.0, false, "2c")
	blocks.sort_custom(func(a, b): return a.t < b.t)


## The final level's jaw notes: every note of JAW_TRACKS where the player is on the ground as it passes between them
## (from about 0.3 s before the note), and not in the middle of another mechanic's run-up or move.
func _track_notes() -> Array:
	var out := []
	for track in Tuning.list(JAW_TRACKS):
		for n in L.song.notes(track):
			var t: float = n[0]
			if (L.air_spans + L.pits).any(func(s): return t - 0.35 < s[1] and t + 0.05 > s[0]):
				continue
			if L.busy_spans.any(func(s): return t - 0.15 < s[1] and t + 0.05 > s[0]):
				continue
			out.append(t)
	out.sort()
	return out


func _drums() -> Array:
	var m = L.mechanic("drums")
	return m.drums if m != null else []


## A pair of jaws closing on t ({} if none fits there).
func _add_block(t: float, big: bool, branch: String) -> Dictionary:
	var w := JAW_W_ROLL if branch == "2c" else (JAW_W_BIG if big else JAW_W)
	var d := w * 1.5
	# stand just behind the clap point: on the clap the player's capsule has just come out of the gap
	var lead := w * 0.5 + PlayerScript.RADIUS + 0.05
	var v: float = L.base_speed * L.track.mult_at(t)
	var x: float = L.track.x_at(t) - lead
	var t_in := t - 2.0 * lead / v  # the capsule starts to pass between them here
	var col_a := t - (lead + w * 0.5) / v  # the columns' own footprint, in run time
	var col_b := t - (lead - w * 0.5) / v
	if JAW_SKIP_DRUMS and _drums().any(func(dr): return col_a < dr.t + dr.pad and col_b > dr.t - dr.pad):
		return {}  # no jaws standing over a drum
	# jaws on one mechanic pillar close around its (pumping) top; anywhere else they close on the stretch of the
	# perfect path that runs between them, as tight as its rise or fall allows
	var lo := INF
	var hi := -INF
	var airborne := false
	for i in 9:
		var ti := lerpf(t_in, t, i / 8.0)
		lo = minf(lo, L.path_y(ti))
		hi = maxf(hi, L.path_y(ti))
		airborne = airborne or not L.arc_at(ti).is_empty()
	var seg: Dictionary = L.seg_at(t)
	if airborne or seg.is_empty() or not is_same(seg, L.seg_at(t_in)):
		seg = {}
	var y := (lo + hi) * 0.5
	var b := {"t": t, "t_in": t_in, "y": y, "x": x, "w": w, "d": d, "big": big, "broken": false, "credited": false, "branch": branch,
		"centre": y, "gap": JAW_OPEN, "color": L.mats.accent_pale if big else L.mats.accent, "seg": seg,
		"squeeze": L.HALF + JAW_CLEAR + (0.0 if not seg.is_empty() else (hi - lo) * 0.5 + JAW_AIR_MARGIN)}
	b.bot = VoxelColumn.make(self, w, d, JAW_REACH, -1, L.GRAVITY)
	b.top = VoxelColumn.make(self, w, d, JAW_REACH, 1, L.GRAVITY)
	for col in [b.bot, b.top]:
		col.position = Vector3(x, y, 0.0)
	blocks.append(b)
	return b


## Jaws close on claps; accents (2b) are loud hits, often the kick and the clap together (or on JAW_TRACKS notes).
func anchors() -> Array:
	return blocks.map(func(b): return [b.t, b.get("track", "clap" if b.branch != "2b" else "clap,kick")])


## The final level's jaws each ask for a dash (but a carried one); level 1's are scored when dashed, never needed.
func cues() -> Array:
	if JAW_TRACKS.is_empty():
		return []
	return blocks.filter(func(b): return not b.follow).map(func(b): return {"t": b.t, "action": "dash"})


## Prompts: the final level's jaws (needed); level 1's, scored when dashed, as optional ones.
func prompts() -> Array:
	if not JAW_TRACKS.is_empty():
		return cues()
	return blocks.filter(func(b): return not b.get("follow", false)).map(func(b): return {"t": b.t, "action": "dash",
		"optional": true})


func tips() -> Array:
	if blocks.is_empty():
		return []
	return ["[SHIFT]\u00a0dash"]


## Open, the gap breathes with the mids (jaws in the air bob too); for JAW_CLOSE_T before the clap it closes in
## slowly, down to just the room the player needs; on the clap, with the player through, it slams shut.
func update_motion(_delta: float) -> void:
	var now: float = L.now
	var mid: float = L.band_at(now, 6)
	var player = L.player
	var x0: float = L.view_x0()
	var x1: float = L.view_x1()
	while _view_i < blocks.size() and blocks[_view_i].x + blocks[_view_i].w < x0:
		_view_i += 1
	for i in range(_view_i, blocks.size()):
		var b: Dictionary = blocks[i]
		if b.x - b.w > x1:
			break
		if b.broken:
			continue
		var k := clampf((b.t - now) / JAW_CLOSE_T, 0.0, 1.0)
		if b.seg.is_empty():
			# in the air: once the player is flying towards them, they close on its real path (a late press flies lower)
			var aim := _flight_through(b)
			if not aim.is_empty():
				b.y = lerpf(b.y, aim.c, 0.5)
				b.squeeze = lerpf(b.squeeze, aim.squeeze, 0.5)
		var c: float = b.seg.top + L.HALF if not b.seg.is_empty() else b.y + (mid - 0.5) * 0.3 * k
		var gap: float = lerpf(b.squeeze, maxf(b.squeeze, JAW_OPEN * (0.8 + 0.4 * mid)), k)
		if now > b.t:
			gap = b.squeeze * maxf(0.0, 1.0 - (now - b.t) / JAW_SLAM_T)
		elif absf(player.position.x - b.x) < b.w * 0.5 + PlayerScript.RADIUS + 0.3:
			# never close onto the player: while it passes (late off a drum, say), the gap shifts so it always fits
			var room := maxf(0.0, gap - L.HALF - 0.1)
			var off: float = player.position.y - c
			if absf(off) > room:
				c += off - signf(off) * room
		b.centre = c
		b.gap = gap
		b.bot.position = Vector3(b.x, c - gap, 0.0)  # each column's working end is its origin
		b.top.position = Vector3(b.x, c + gap, 0.0)
		var glow := 0.3 + 0.7 * (1.0 - k)  # brighter as they close
		VoxelColumn.shade(b.bot, b.color, glow, JAW_SHINE)
		VoxelColumn.shade(b.top, b.color, glow, JAW_SHINE)


## Where the player will really pass between airborne jaws b, once it has taken off on the bounce they hang in
## (the throw is known, so the rest of the flight is too): {c, squeeze}, or {} to keep the plan.
func _flight_through(b: Dictionary) -> Dictionary:
	var player = L.player
	var now: float = L.now
	if player.grounded or player.hovering() or now >= b.t:
		return {}
	var a: Dictionary = L.arc_at(b.t)
	if a.is_empty() or a.get("hover", false) or now < a.ta - 0.2:
		return {}
	var lo := INF
	var hi := -INF
	for i in 9:
		var ti: float = lerpf(b.t_in, b.t, i / 8.0)
		if ti < now:
			continue
		var dt := ti - now
		var y: float = player.position.y + player.vy * dt - 0.5 * L.GRAVITY * dt * dt
		lo = minf(lo, y)
		hi = maxf(hi, y)
	if lo == INF:
		return {}
	return {"c": (lo + hi) * 0.5, "squeeze": L.HALF + JAW_CLEAR + (hi - lo) * 0.5 + JAW_AIR_MARGIN}


func autoplay() -> void:
	for b in blocks:
		if not b.broken and not b.get("follow", false) and L.now >= b.t - 0.01 and L.now <= b.t + 0.05 and L.dash_press < b.t - 0.15:
			L.press_dash()


func after_step(_delta: float) -> void:
	var p: Vector3 = L.player.global_position
	var now: float = L.now
	# a jaw a second behind has long been scored or not, and has slammed shut
	while _check_i < blocks.size() and blocks[_check_i].t < now - 1.0 and blocks[_check_i].broken:
		_check_i += 1
	for i in range(_check_i, blocks.size()):
		var b: Dictionary = blocks[i]
		var win: float = BIG_WINDOW if b.big else L.WINDOW
		if now < b.t - JAW_CLOSE_T:
			break
		var dashed: bool = L.dash_press >= b.t - win and L.dash_press <= b.t + win
		if now >= b.t - win and dashed and not b.credited and absf(p.y - b.centre) < 2.2:
			b.credited = true
			L.judge(L.dash_press - b.t)
			L.dash_press = L.NONE
		if b.broken:
			continue
		# a drop of a step or so (walking off a drum's edge) is made room for next frame; only a real hit dents them
		if absf(p.x - b.x) < b.w * 0.5 + PlayerScript.RADIUS and absf(p.y - b.centre) > b.gap - L.HALF + 0.45:
			_dent(b)
		elif now >= b.t + JAW_SLAM_T:
			_vanish(b)


## The jaws have met behind the player: they burst at the seam into their voxels, which fly apart and fall (bouncing on
## the pillar under them), the columns crumbling away from the seam; the camera gives a small jolt.
func _vanish(b: Dictionary) -> void:
	b.broken = true
	var power := JAW_BURST * (1.4 if b.big else (0.75 if b.branch == "2c" else 1.0))
	_break(b, Vector3(b.x, b.centre, 0.0), 0.0, 0.0, power, Vector3(-0.5, 0.0, 0.0))  # left behind as the run goes on
	L.cam_rig.jolt(JAW_SHAKE_BIG if b.big else JAW_SHAKE)
	L.sfx.play("shatter", power / JAW_BURST)


## The player meets the jaws: the voxels where its block hits are knocked out and carried along with it, and a moment
## later the rest of both columns crumbles.
func _dent(b: Dictionary) -> void:
	b.broken = true
	b.dented = true
	var p: Vector3 = L.player.global_position
	var run: float = L.base_speed * L.track.mult_at(L.now)
	_break(b, Vector3(b.x, p.y, 0.0), PlayerScript.RADIUS + PlayerScript.HEIGHT * 0.5, 0.3, JAW_BURST * 0.5,
		Vector3(run * 0.35, L.player.vy * 0.5, 0.0))
	L.sfx.play("shatter", 0.5)
	if b.big:
		L.cam_rig.jolt(0.3)


func _break(b: Dictionary, at: Vector3, hole: float, hold: float, power: float, push: Vector3) -> void:
	var floor_top := -INF
	var x0 := 0.0
	var x1 := 0.0
	if not b.seg.is_empty():  # the pillar under them catches the voxels that land on it
		floor_top = b.seg.top
		x0 = L.track.x_at(b.seg.ta)
		x1 = L.track.x_at(b.seg.tb)
	for col in [b.bot, b.top]:
		VoxelColumn.break_apart(col, at, hole, hold, power, push, floor_top, x0, x1)
	if _debris == null:
		_debris = VoxelDebris.new()
		add_child(_debris)
	_debris.life = JAW_DEBRIS_T
	_debris.add([b.bot, b.top])


## Carrying on from t: the jaws before it have long shut.
func skip_to(t: float) -> void:
	for b in blocks:
		if b.t < t:
			b.broken = true
			b.credited = true
			b.bot.visible = false
			b.top.visible = false


## The intro panel: DASH.
func panel_caption() -> Dictionary:
	return {"DASH": "Dash (SHIFT) through the closing pillars"} if not blocks.is_empty() else {}


## The intro panel's drawing: two jaws closing on each other.
func panel_sprites() -> Array:
	if blocks.is_empty():
		return []
	var a: Color = L.mats.accent
	return [{"family": "DASH", "t": blocks.map(func(b): return b.t).min(), "palette": {"a": a, "A": a.lightened(0.35), "w": Color.WHITE}, "rows": ["..aaaaaaaa..", "..aaaaaaaa..", "..aaaaaaaa..", "..AAAAAAAA..", "....w..w....", ".....ww.....", ".....ww.....", "....w..w....", "..AAAAAAAA..", "..aaaaaaaa..", "..aaaaaaaa..", "..aaaaaaaa.."]}]
