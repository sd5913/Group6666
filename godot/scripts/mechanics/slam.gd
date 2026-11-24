extends "res://scripts/mechanics/mechanic.gd"
## 5-1 下砸 (level 3's kicks): on every bar's downbeat kick (MIDI) the run-up ends before the beat, and a small pad
## waits far below. Walking off, the player is in the air: pressing S slams it down onto the pad, which squashes and
## bounces it two beats on, onto the next ground. Without the slam the player sails over the pad (or drops onto it too
## late to bounce) and falls. The pad thumps on every kick of the song and glows harder the louder its own kick is.
## Two ways to slam:
##   SLAM_G 0     straight down at SLAM_V, all but at once: press S on the kick
##   SLAM_G > 0   falling at SLAM_G (a heavy, gravity-like drop over a deep gap): press S that long before the kick
##                (about an eighth note) so the player hits the pad on it; it is the hit that is timed against the
##                kick, and the pad only bounces a slam that lands within the window. The run-up ends earlier to match,
##                and the bounce can land on ground SLAM_RISE higher than the run-up — a real launch.
## S on the ground from just before the edge on doesn't become a plain slide: it waits until the player is off.
## A slam can also be come into from the air (add_from_air: a hop string's last flute throws the player up over its pad;
## made for SLAM_G 0): no run-up then, the pit from halfway between.
## The pad's plate is made of voxels: once the player has bounced off it, it crumbles onto its pillar.

const Draw := preload("res://scripts/view/draw.gd")
const Tuning := preload("res://scripts/core/tuning.gd")
const VoxelColumn := preload("res://scripts/view/voxel_column.gd")
const VoxelDebris := preload("res://scripts/view/voxel_debris.gd")

var SLAM_FROM_PHRASE := 1      # the first phrase with slams,
var SLAM_FROM_T := 0.0         # and no slam on a kick before this (seconds)
var SLAM_SKIP_PHRASES := "2"   # and phrases without them
var SLAM_EVERY := 2            # from SLAM_MIX_FROM_PHRASE on, a slam every this many bars (the bars between are
var SLAM_MIX_FROM_PHRASE := 3  # left free); before that, while the slam is being taught, every bar
var SLAM_EDGE_T := 0.2         # the run-up ends this long before the press (seconds)
var SLAM_DROP := 2.4           # the pad sits this far below the run-up (metres)
var SLAM_DROP_MIN := 0.0       # with terraces: the pad sits at least this far below the run-up, however small the step
                               # (a real pit to slam into; the bounce still lands on the step's terrace)
var SLAM_RISE := 0.0           # the bounce lands on ground this much higher than the run-up (metres; 0: as planned)
var SLAM_PAD_T := 0.2         # half the pad's width, in seconds of run (so it is as forgiving at any speed)
var SLAM_V := 80.0             # SLAM_G 0: how fast a slam drives down (m/s): fast enough to hit the pad on the kick
var SLAM_G := 0.0              # > 0: a slam falls at this acceleration instead (m/s²; about 3x GRAVITY)
var SLAM_WINDOW := 0.16        # the press (SLAM_G 0) / the hit on the pad (SLAM_G > 0) this close to the kick (seconds)
var SLAM_EARLY := 0.4          # S this long before the edge already counts (it waits for the player to be off)
var SLAM_BOUNCE_BEATS := 2.0   # the bounce lands this many beats after the kick
var SLAM_SHAKE := 0.18         # camera jolt on the hit (scaled by the kick's loudness)
var SLAM_GLOW_MAX := 1.0       # how hard the pad's plate glows at most (0-1; less: it keeps its colour on a pale sky)
var SLAM_CRUMBLE := 2.5        # how hard the plate falls apart once the player has bounced off it (m/s)
var SLAM_DEBRIS_T := 0.7       # and how soon its voxels are gone (seconds: it has done its job, no heap left lying there)

const PLATE_H := 0.22           # the plate's thickness (metres)
const AIR_DROP := 1.6           # a slam come into from the air: its pad this far under the feet on the kick (metres; a
                                # fall from a run-up edge's speed takes 0.26 s to it: S has its window, the hit is ~20 ms)

var slams: Array = []           # {t, vel, press_t, edge, land, pad_t, seg, slammed, press, bounced, plate, ...}
var _runups: Array = []         # [ta, tb] the slams' own run-ups (another slam's bounce may land on one)
var _debris: VoxelDebris        # plates bounced off, while their voxels fall


## The tutorial's slam, on the kick at[0].
func teach(at: Array, _kind := "") -> void:
	_place([at[0], 0.0, 0.0, 100.0], SLAM_DROP)


## With terraces, the slams are the terrace's slam steps (scripts/core/terrace.gd); else every bar's downbeat kick.
func plan_air() -> void:
	if not L.terrace.is_empty():
		for st in L.terrace.filter(func(st): return st.kind == "slam"):
			_place([st.t, 0.0, 0.0, L.song.nearest("kick", st.t)[3]], maxf(st.from - st.to, SLAM_DROP_MIN))
			if st.has("drop_t"):  # (the run-up's drop down to a dip in the tune: nothing else stands there)
				L.busy_spans.append([st.drop_t - 0.15, st.a])
		return
	var skip := Tuning.list(SLAM_SKIP_PHRASES).map(func(s): return int(s))
	var bar: float = L.data.bar_sec
	for k in L.song.notes("kick"):
		var t: float = k[0]
		var into_bar := fposmod(t - L.data.first_bar_at + 0.02, bar) - 0.02
		if absf(into_bar) > 0.02 or t < SLAM_FROM_T - 0.001:
			continue  # downbeats only
		var phrase: int = L.phrases.filter(func(p): return t >= p - 0.001).size()
		if phrase < SLAM_FROM_PHRASE or phrase in skip:
			continue
		if phrase >= SLAM_MIX_FROM_PHRASE and roundi((t - L.data.first_bar_at) / bar) % maxi(1, SLAM_EVERY) != 0:
			continue
		_add(k)


func plan_fill() -> void:
	slams.sort_custom(func(a, b): return a.t < b.t)


## How long before the kick S is pressed: 0 for a straight slam; falling at SLAM_G, the time it takes to drop the rest
## of `drop` after SLAM_EDGE_T of falling off the edge.
func _fall_t(drop: float) -> float:
	if SLAM_G <= 0.0:
		return 0.0
	var v0: float = L.GRAVITY * SLAM_EDGE_T
	var rest: float = maxf(0.0, drop - 0.5 * L.GRAVITY * SLAM_EDGE_T * SLAM_EDGE_T)
	return (-v0 + sqrt(v0 * v0 + 2.0 * SLAM_G * rest)) / SLAM_G


## Where the run-up of a slam onto a pad `drop` below it, hit at t, ends.
func edge_of(t: float, drop: float) -> float:
	return t - _fall_t(drop) - SLAM_EDGE_T


## A slam on downbeat kick k, if its run-up, drop and bounce fit between what is already planned.
func _add(k: Array) -> void:
	var t: float = k[0]
	var edge := edge_of(t, SLAM_DROP)
	var land: float = t + SLAM_BOUNCE_BEATS * L.beat
	if edge < 0.5 or land > L.data.dur - 0.5:
		return
	var others: Array = L.air_spans + L.busy_spans.filter(func(s): return not _runups.has(s))
	if others.any(func(s): return edge < s[1] + 0.25 and land > s[0] - 0.25):
		return
	# a bounce may come down on the next slam's run-up, if it still leaves about a beat of it before that edge
	if _runups.any(func(s): return edge < s[1] + 0.25 and land > s[1] - 0.45):
		return
	_place(k, SLAM_DROP)


## A slam on kick t the player comes into from the air, thrown off a hop string's last flute at from_t (scripts/
## mechanics/hops.gd) up and over the pad: its pad AIR_DROP under the thrown player's feet on the kick (never above the
## ground the flutes float over), a pit from halfway between, no run-up; hops.gd's solve gives its arcs
## (solve_from_air).
func add_from_air(t: float, from_t: float) -> void:
	var drop: float = SLAM_DROP_MIN if SLAM_DROP_MIN > 0.0 else SLAM_DROP
	var land: float = t + SLAM_BOUNCE_BEATS * L.beat
	slams.append({"t": t, "vel": L.song.nearest("kick", t)[3], "press_t": t - _fall_t(drop), "edge": from_t, "land": land,
		"pad_t": SLAM_PAD_T, "drop": drop, "slammed": false, "bounced": -INF, "missed": false, "from_air": true})
	L.pits.append([(from_t + t) * 0.5, t - SLAM_PAD_T])
	L.pits.append([t + SLAM_PAD_T, land - L.LAND_EDGE_T])
	L.air_spans.append([from_t, land])
	L.contacts.append(t)


## A slam on kick k onto a pad `drop` below its run-up: its gaps, airborne stretch, run-up and contacts.
func _place(k: Array, drop: float) -> void:
	var t: float = k[0]
	var press_t := t - _fall_t(drop)
	var edge := press_t - SLAM_EDGE_T
	var land: float = t + SLAM_BOUNCE_BEATS * L.beat
	var pad_t: float = SLAM_PAD_T
	slams.append({"t": t, "vel": k[3], "press_t": press_t, "edge": edge, "land": land, "pad_t": pad_t, "drop": drop,
		"slammed": false, "bounced": -INF, "missed": false})
	L.pits.append([edge, t - pad_t])
	L.pits.append([t + pad_t, land - L.LAND_EDGE_T])
	L.air_spans.append([edge, land])
	var runup := [edge - 0.5, edge]
	L.busy_spans.append(runup)
	_runups.append(runup)
	L.contacts.append(t)
	L.contacts.append(edge - 0.25)  # a flat run-up to the edge
	L.contacts.append(edge - 0.45)


## The pad's pillar reaches exactly as wide as the pad.
func contact_r(t: float) -> float:
	for s in slams:
		if absf(s.t - t) < 0.001:
			return s.pad_t
	return -1.0


## The pad's pillar sits its drop (SLAM_DROP; with terraces, its step's) below the run-up it is reached from; with
## SLAM_RISE, the ground the bounce lands on sits that much above it.
func carve() -> void:
	for s in slams:
		var seg: Dictionary = L.seg_at(s.t)
		var ledge: Dictionary = L.seg_at(s.edge - 0.001)
		var from: float = ledge.base if not ledge.is_empty() else maxf(L.ground_h(s.edge), L.key_floor(s.edge)) + L.mech_lift
		if seg.is_empty():
			continue
		seg.base = from - s.drop
		if s.get("from_air", false):  # (under the thrown player, and in a pit under the ground the flutes float over;
			# still, not pumping on the bass: its depth under the player is what keeps the press's window open)
			var ground: float = maxf(L.ground_h(s.edge), -INF if L.in_terrace(s.edge) else L.MECH_FLOOR) + L.mech_lift
			seg.base = minf(L.mechanic("hops").throw_y(s.t) - L.HALF - AIR_DROP, ground - 0.3)
			seg.still = true
		seg.top = seg.base
		seg.by = self
		var landing: Dictionary = L.seg_at(s.land + 0.01)
		if SLAM_RISE > 0.0 and not landing.is_empty() and not is_same(landing, seg):
			landing.base = maxf(landing.base, from + SLAM_RISE)
			landing.top = landing.base


## Off the edge, falling; driven down (straight, or falling at SLAM_G) onto the pad on the kick; bounced up to land two
## beats later.
func solve() -> void:
	for s in slams:
		if s.get("from_air", false):
			continue  # (its throw is hops.gd's, which then asks for the rest: solve_from_air)
		var y_edge: float = L.plat_h(s.edge) + L.HALF
		var fall: float = s.press_t - s.edge
		L.arcs.append({"ta": s.edge, "tb": s.press_t, "ya": y_edge, "vy": 0.0, "g": 1.0})
		_hit_arcs(s, y_edge - 0.5 * L.GRAVITY * fall * fall, -L.GRAVITY * fall)


## The slam come into from the air on kick t: the player at y_press then, thrown there by a hop string's last flute.
func solve_from_air(t: float, y_press: float) -> void:
	for s in slams:
		if s.get("from_air", false) and absf(s.t - t) < 0.001:
			_hit_arcs(s, y_press, -L.GRAVITY * SLAM_EDGE_T)


## From the press on (the player at y_press, falling at vy): driven down (straight, or falling at SLAM_G) onto the pad
## on the kick, then bounced up to land two beats later.
func _hit_arcs(s: Dictionary, y_press: float, vy: float) -> void:
	var pad_y: float = L.plat_h(s.t) + L.HALF
	var hit: float = s.t
	if SLAM_G > 0.0:
		L.arcs.append({"ta": s.press_t, "tb": s.t, "ya": y_press, "vy": vy, "g": SLAM_G / L.GRAVITY})
	else:
		hit = s.t + maxf(0.02, (y_press - pad_y) / SLAM_V)
		L.arcs.append({"ta": s.t, "tb": hit, "ya": y_press, "yb": pad_y, "vy": 0.0, "g": 1.0, "hover": true, "ramp_from": s.t})
	L.arcs.append(L.arc(hit, s.land, L.plat_h(s.land) + L.HALF, pad_y))


## When each bounce comes down (towers count the climax's strong beats a bounce lands on as taken).
func landings() -> Array:
	return slams.map(func(s): return s.land)


## On its kick (a terrace's slam: on its step's low lead note).
func anchors() -> Array:
	return slams.map(func(s): return [s.t, "lead" if not L.terrace.is_empty() and L.GRID_LOCK == 0 else "kick"])


func cues() -> Array:
	return slams.map(func(s): return {"t": s.press_t, "action": "down"})


## Prompts: S on the press, judged on the landing.
func prompts() -> Array:
	return slams.map(func(s): return {"t": s.press_t, "action": "down", "judge_t": s.t})


func tips() -> Array:
	if slams.is_empty():
		return []
	return ["[S]\u00a0slam"]


# ---------------------------------------------------------------- look

## A thick plate of voxels in the accent colour on each pad, the target of the slam, and a pixel arrow over it pointing
## down.
func build() -> void:
	var vels: Array = L.song.velocities("kick")
	var cube := BoxMesh.new()
	cube.size = Vector3(0.17, 0.17, 0.17)
	_debris = VoxelDebris.new()
	_debris.life = SLAM_DEBRIS_T
	add_child(_debris)
	for s in slams:
		s.seg = L.seg_at(s.t)
		s.loud = (s.vel - vels[0]) / maxf(1.0, vels[-1] - vels[0]) if not vels.is_empty() else 0.5
		var w := maxf(VoxelColumn.VOXEL, snappedf(1.8 * s.pad_t * L.base_speed * L.track.mult_at(s.t), VoxelColumn.VOXEL))
		s.mat = Draw.mat(L.mats.accent.darkened(0.15), L.mats.accent, 0.3)  # the arrow: glowing in its own hue
		s.plate = VoxelColumn.make(self, w, 1.5, PLATE_H, -1, L.GRAVITY)  # origin: its top face
		s.plate.position = Vector3(L.track.x_at(s.t), 0.0, 0.0)
		s.gone = false
		s.arrow = Node3D.new()
		s.arrow.visible = false  # (until its slam comes up: update_motion puts it in its place)
		add_child(s.arrow)
		# a pixel arrow pointing down: a stem, then the head
		for c in [[0, 4], [0, 3], [-2, 2], [0, 2], [2, 2], [-1, 1], [0, 1], [1, 1], [0, 0]]:
			Draw.mesh(s.arrow, cube, s.mat, Vector3(c[0] * 0.19, c[1] * 0.19, 0.7))


## The plate rides its pillar, thumps on every kick note, and is squashed flat by the slam; once the player has bounced
## off, it crumbles. The arrow over it bobs on the beat for the two beats before the press, and on the press it jabs
## down.
func update_motion(_delta: float) -> void:
	var now: float = L.now
	var x0: float = L.view_x0()
	var x1: float = L.view_x1()
	var kick: Array = L.song.nearest("kick", now)
	var thump: float = exp(-(now - kick[0]) * 9.0) if not kick.is_empty() and now >= kick[0] else 0.0
	for s in slams:
		var x: float = s.plate.position.x
		if x < x0 or x > x1 or s.seg.is_empty():
			continue
		var hit := clampf(1.0 - (now - s.bounced) / 0.35, 0.0, 1.0)
		var soon := 1.0 - clampf((s.t - now) / L.beat, 0.0, 1.0) if now < s.t else 0.0
		var glow: float = 0.3 + 0.5 * soon + 0.3 * thump + 0.6 * hit * (0.5 + 0.5 * s.loud)
		s.mat.emission_energy_multiplier = minf(1.2, glow)
		if not s.gone:
			if s.bounced > -INF and now > s.bounced + 0.15:  # the player is away: it lets go
				_crumble(s)
			else:
				var squash := 1.0 - 0.6 * hit * sin(hit * PI * 0.5) - 0.2 * thump
				s.plate.scale = Vector3(1.0 + 0.25 * hit, squash, 1.0 + 0.15 * hit)
				s.plate.position.y = s.seg.top + PLATE_H * squash  # (the origin is its top face)
				VoxelColumn.shade(s.plate, L.mats.accent.darkened(0.15), minf(SLAM_GLOW_MAX, glow / 1.2), L.BLOCK_SHINE)
		var lead: float = s.press_t - now
		s.arrow.visible = lead > -0.12 and lead < 2.0 * L.beat
		var jab: float = 0.6 * clampf(-lead / 0.12, 0.0, 1.0) if SLAM_G > 0.0 else 0.0
		s.arrow.position = Vector3(x, s.seg.top + 1.0 + 0.15 * absf(sin(PI * now / L.beat)) - jab, 0.0)


## Bounced off: the plate crumbles from the middle of its top, its voxels popping up a little and falling back onto the
## pillar.
func _crumble(s: Dictionary) -> void:
	s.gone = true
	var x0: float = L.track.x_at(s.seg.ta)
	var x1: float = L.track.x_at(s.seg.tb)
	VoxelColumn.break_apart(s.plate, s.plate.position, 0.0, 0.0, SLAM_CRUMBLE, Vector3(0.0, 1.5, 0.0), s.seg.top, x0, x1)
	_debris.add([s.plate])
	L.sfx.play("crumble")


# ---------------------------------------------------------------- play

func autoplay() -> void:
	for s in slams:
		if not s.slammed and L.now >= s.press_t - 0.004 and L.now <= s.press_t + SLAM_WINDOW and L.down_press <= L.NONE:
			L.down_press = L.now


## S from just before the edge to the end of the window: a slam once the player is in the air (a straight slam also
## waits for the kick); on the ground it waits, so it never turns into a plain slide. Over a shallow drop the player may
## already be down on the pad: S there within the window bounces straight away.
func down_claim(press: float) -> int:
	for s in slams:
		if s.slammed or press < s.edge - SLAM_EARLY or press > maxf(s.press_t, s.t) + SLAM_WINDOW:
			continue
		if L.player.grounded and is_same(L.seg_at(L.player_t()), s.seg) and L.now <= s.t + SLAM_WINDOW:
			s.slammed = true  # (a shallow drop: already down on the pad, the slam is the press itself)
			s.press = press
			return TAKEN
		if L.player.grounded or (SLAM_G <= 0.0 and L.now < s.t - 0.03):
			return WAIT if L.now <= s.press_t + SLAM_WINDOW else PASS
		s.slammed = true
		s.press = press
		if SLAM_G > 0.0:
			L.player.slam(SLAM_G)
		else:
			L.player.jump(-SLAM_V)
		return TAKEN
	return PASS


## Down on the pad: a slam bounces towards the landing two beats on — falling at SLAM_G only if it hit the pad within
## the window of the kick; anything else lies there and the run carries the player off into the gap.
func after_step(_delta: float) -> void:
	for s in slams:
		if s.bounced > -INF or s.missed or not L.player.grounded:
			continue
		if not is_same(L.seg_at(L.player_t()), s.seg):
			continue
		var on_time: bool = absf(L.now - s.t) <= SLAM_WINDOW
		if not s.slammed:  # down on the pad without one: S may still come within the window
			s.missed = L.now > s.t + SLAM_WINDOW
			continue
		if SLAM_G > 0.0 and not on_time:
			s.missed = true
			continue
		var tt: float = maxf(0.25, s.land - L.now)
		var y: float = L.player.global_position.y
		L.player.jump((L.plat_h(s.land) + L.HALF - y) / tt + L.GRAVITY * tt * 0.5)
		s.bounced = L.now
		L.sfx.play("slam_hit")
		L.judge(L.now - s.t if SLAM_G > 0.0 else s.press - s.t)
		L.cam_rig.jolt(SLAM_SHAKE * (0.6 + 0.6 * s.loud))
		Draw.burst(L, Vector3(s.plate.position.x, s.seg.top + 0.2, 0.0), L.mats.accent_frag, 10)


func fail_reason() -> String:
	for s in slams:
		if s.bounced == -INF and L.now > s.edge and L.now < s.land + 1.0:
			if s.get("from_air", false):
				return "Slam: off the last flute, press S on the kick to bounce off the pad"
			if SLAM_G > 0.0:
				return "Slam: off the edge, press S half a beat early so you hit the pad on the kick"
			return "Slam: off the edge, press S on the kick to bounce off the pad"
	return ""


## Carrying on from t: the slams before it are over (their plates gone).
func skip_to(t: float) -> void:
	for s in slams:
		if s.t < t:
			s.slammed = true
			s.bounced = s.t
			s.gone = true
			s.plate.visible = false


## The intro panel: SLAM.
func panel_caption() -> Dictionary:
	return {"SLAM": "Walk off, slam (S) onto the pad on the kick"} if not slams.is_empty() else {}


## The intro panel's drawing: the arrow pointing down at the pad.
func panel_sprites() -> Array:
	if slams.is_empty():
		return []
	var a: Color = L.mats.accent
	return [{"family": "SLAM", "t": slams.map(func(s): return s.t).min(), "palette": {"a": a, "d": a.darkened(0.15), "t": L.theme_color}, "rows": ["....aaaa....", "....aaaa....", "....aaaa....", "..aaaaaaaa..", "...aaaaaa...", "....aaaa....", ".....aa.....", "............", "............", "..dddddddd..", "..dddddddd..", "..tttttttt.."]}]
