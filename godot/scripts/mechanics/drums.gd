extends "res://scripts/mechanics/mechanic.gd"
## 5-1 鼓面弹床 (level 1's kicks): each kick is a drum on top of its own pillar, skin facing up and 35° towards the
## goal, that throws the player on the kick (by itself; with DRUM_PRESS only on a jump press). A gap follows.
## Three modes (A and C sit on the beat-3 kick, so a bar without one falls back to B):
##   B  the bounce lands exactly on the next platform on beat 3
##   A  the next platform is set back by half a beat: the bounce reaches its height on beat 3 and the player has to
##      air-dash there to carry across (no dash, no platform)
##   C  a second drum waits in the gap on beat 3; bouncing again carries the player over beat 4 onto the next drum
## When the next drum comes before beat 3 (crowded kicks), a B drum throws the player straight onto its skin.
## Drums are coloured by kick: on the beat (1a), off the beat (1b), anticipating the bar (1c).

const Draw := preload("res://scripts/view/draw.gd")
const Tuning := preload("res://scripts/core/tuning.gd")
const Spans := preload("res://scripts/core/spans.gd")

var DRUM_PRESS := false        # drums throw only when jump is pressed on the kick (false: by themselves)
var DRUM_CUES := 0             # 1: a drum's (optional) press counts as an input (the tools press it, gaps count it)
var DRUM_KICKS := "1a,1b,1c"   # which kicks become drums, most important first (they win when kicks crowd)
var DRUM_MIN_GAP := 0.0        # beats between two drums at least (closer kicks are skipped)
var DRUM_TEACH := "B,A,C"      # modes taught one per phrase, in this order
var DRUM_MIX := "B,A,C"        # then cycled bar by bar
var DRUM_HALF_T := 0.3         # mechanic pillars cover kick ± this (a run-in pillar, then the drum's own lower one)
var DRUM_WINDOW := 0.18        # input window for drum bounces (seconds)
var DRUM_H := 0.35             # drum pad thickness
var DRUM_TILT := deg_to_rad(35.0)  # drum skins face up and 35° forward, towards the goal they throw the player to
var DRUM_R := 0.8
var EXTRA_DRUM_R := 0.65
var DRUM_COLOR_1A := Color(0.86, 0.24, 0.24)  # rim colours: on-beat, off-beat (1b) and anticipation (1c) drums
var DRUM_COLOR_1B := Color(0.3, 0.45, 0.95)
var DRUM_COLOR_1C := Color(0.95, 0.72, 0.15)
var AIR_DASH_BEATS := 0.5      # mode A: how far (in beats) the next platform is set back

const MODE_NAME := {"B": "Drum B: lands on the platform", "A": "Drum A: needs an air dash", "C": "Drum C: onto the second drum", "C2": "Drum C: on to the next drum"}

var drums: Array = []           # {t, arc_t, land_t, arc_y, mode B / A / C / C2, kind, seg, ...}
var air_dashes: Array = []      # mode A dash points {t, until, used}
const LATE_DASH_T := 0.12       # an air dash later than this after its beat has fallen far enough to need the shorter glide
var _view_i := 0                # the first drum not yet left behind the picture
var mats := {}


# ---------------------------------------------------------------- planning

func plan_air() -> void:
	var kicks := _pick_kicks().filter(func(k): return _room_for(k.t))
	var first_phrase: int = L.phrases.filter(func(p): return kicks.size() > 0 and kicks[0].t >= p - 0.001).size()
	var beat: float = L.beat
	for i in kicks.size():
		var tk: float = kicks[i].t
		var kind: String = kicks[i].branch
		var next: float = kicks[i + 1].t if i + 1 < kicks.size() else INF
		var t3 := tk + 2.0 * beat
		var mode := _drum_mode(tk, first_phrase, i == kicks.size() - 1)
		if mode != "B" and (t3 >= next - 0.3 or not _kick_near(t3)):
			mode = "B"
		if mode == "C" and absf(next - (tk + 4.0 * beat)) > 0.05:
			mode = "B"  # the second bounce has to land on the next bar's drum
		var land := minf(t3, next)
		match mode:
			"A":
				_add_air_dash(tk, t3, kind)
			"C":
				var dc := _drum({"t": tk, "arc_t": t3, "land_t": t3, "mode": "C", "kind": kind})
				var d2 := _drum({"t": t3, "arc_t": next, "land_t": next, "mode": "C2", "extra": true, "kind": kind})
				drums.append(dc)
				drums.append(d2)
				L.pits.append([tk + dc.pad, t3 - d2.pad])
				L.pits.append([t3 + d2.pad, next - DRUM_HALF_T])
				L.air_spans.append([tk, t3])
				L.air_spans.append([t3, next])
			_:
				var db := _drum({"t": tk, "arc_t": land, "land_t": land, "mode": "B", "kind": kind})
				drums.append(db)
				if land >= next - 0.001:  # straight onto the next drum's skin: the gap reaches its pillar
					var pn: float = _drum({"t": next}).pad
					if next - pn > tk + db.pad + 0.05:
						L.pits.append([tk + db.pad, next - pn])
				elif land - tk >= 0.45:
					L.pits.append([tk + db.pad, land - L.LAND_EDGE_T])
				L.air_spans.append([tk, land])
	drums.sort_custom(func(a, b): return a.t < b.t)


## A drum on kick tk needing an air dash on t3 to carry across to the platform set back after it (mode A).
func _add_air_dash(tk: float, t3: float, kind: String) -> void:
	var on: float = t3 + AIR_DASH_BEATS * L.beat  # the set-back platform starts here
	var da := _drum({"t": tk, "arc_t": t3, "land_t": on, "mode": "A", "kind": kind})
	drums.append(da)
	air_dashes.append({"t": t3, "until": on, "used": false})
	L.pits.append([tk + da.pad, on - L.LAND_EDGE_T])
	L.air_spans.append([tk, on])


## The tutorial's drums: "A" on kick at[0], with its air dash two beats on; "B" on kick at[0], landing at at[1].
func teach(at: Array, kind := "") -> void:
	var tk: float = at[0]
	if kind == "A":
		_add_air_dash(tk, tk + 2.0 * L.beat, "1a")
		return
	var db := _drum({"t": tk, "arc_t": at[1], "land_t": at[1], "mode": "B", "kind": "1a"})
	drums.append(db)
	L.pits.append([tk + db.pad, at[1] - L.LAND_EDGE_T])
	L.air_spans.append([tk, at[1]])


## Whether a drum on kick t (its run-in, its own pillar and a bounce two beats on) fits between what the mechanics
## planned before it (in level 1 the drums are planned first, so they always do; in the final level they come after
## the slams keep clear of them).
func _room_for(t: float) -> bool:
	var pad: float = _drum({"t": t}).pad
	var land: float = t + 2.0 * L.beat
	if L.air_spans.any(func(s): return t - pad < s[1] and land > s[0]):
		return false
	if L.busy_spans.any(func(s): return t - 0.05 < s[1] and land > s[0]):
		return false
	return not L.pits.any(func(p): return t - DRUM_HALF_T < p[1] and land > p[0])


## A drum and its pillar point at each other: let go of that when the level goes, so both can be freed.
func _exit_tree() -> void:
	for d in drums:
		d.erase("seg")


## Drums get a long pillar: a run-in, then the drum's own lower one.
func contact_r(t: float) -> float:
	return DRUM_HALF_T if drums.any(func(d): return absf(d.t - t) < 0.001) else -1.0


## Every drum sits on a pillar of its own, sunk by the drum's height so the skin's raised back edge is level with the
## pillar the player runs in from (mode C's second drum gets a small one alone in the gap).
func carve() -> void:
	for d in drums:
		var span := [d.t - d.pad, d.t + d.pad]
		var at: Dictionary = L.seg_at(d.t)
		var base: float = (at.base if not at.is_empty() else maxf(L.ground_h(d.t), L.key_floor(d.t)) + L.mech_lift) - d.back_h
		var kept := []
		for s in L.mech:
			for piece in Spans.subtract([[s.ta, s.tb]], [span]):
				if piece[1] - piece[0] > 0.01:
					var p: Dictionary = s.duplicate()  # keeps an earlier drum's link
					p.ta = piece[0]
					p.tb = piece[1]
					kept.append(p)
		kept.append({"ta": span[0], "tb": span[1], "base": base, "top": base, "drum": d, "by": self})
		L.mech = kept


## A drum's skin, tilted towards the goal: level with the run-in at its back edge, dropping away in front.
func surface(s: Dictionary, top: float, x: float) -> float:
	var d: Dictionary = s.drum
	var u := maxf(-d.r, (x - L.track.x_at(d.t)) / cos(DRUM_TILT))  # along the skin from its centre (at the kick)
	return top + d.skin_c - u * sin(DRUM_TILT) if u <= d.r else top


## Each drum throws from its skin's centre; a bounce that ends on another drum (mode C) aims at that drum's skin.
func solve() -> void:
	for d in drums:
		d.arc_y = L.plat_h(d.land_t) + L.HALF
		L.arcs.append(L.arc(d.t, d.arc_t, d.arc_y))
		if d.mode == "A":
			L.arcs.append({"ta": d.arc_t, "tb": d.land_t, "ya": d.arc_y, "vy": 0.0, "hover": true})


## Drum geometry: radius, how far its own pillar reaches either side of the kick (seconds of run, enough for the
## stand under its back), and how high the skin's back edge and centre stand above that pillar's top.
func _drum(fields: Dictionary) -> Dictionary:
	var r := EXTRA_DRUM_R if fields.get("extra", false) else DRUM_R
	fields.r = r
	fields.back_h = 2.0 * r * sin(DRUM_TILT) + DRUM_H * cos(DRUM_TILT)
	fields.skin_c = r * sin(DRUM_TILT) + DRUM_H * cos(DRUM_TILT)
	fields.pad = (r * cos(DRUM_TILT) + DRUM_H * sin(DRUM_TILT) + 0.1) / (L.base_speed * L.track.mult_at(fields.t))
	return fields


func _kick_near(t: float) -> bool:
	return L.data.get("kicks", []).any(func(k): return absf(k.t - t) < 0.06 and k.v >= 0.5)


## Drum modes are taught one per phrase (DRUM_TEACH, e.g. B then A then C), then cycled bar by bar (DRUM_MIX);
## the last drum always lands plainly.
func _drum_mode(tk: float, first_phrase: int, last: bool) -> String:
	if last:
		return "B"
	var teach := Tuning.list(DRUM_TEACH)
	var mix := Tuning.list(DRUM_MIX)
	var phrase: int = L.phrases.filter(func(p): return tk >= p - 0.001).size() - first_phrase
	if phrase < teach.size():
		return teach[phrase]
	if mix.is_empty():
		return "B"
	return mix[int(floor((tk - L.data.first_bar_at) / L.data.bar_sec)) % mix.size()]


## Which kicks become drums: the DRUM_KICKS branches, most important first, each kept only if it is at least
## DRUM_MIN_GAP beats from every drum already kept (so crowded syncopations thin out around the strong beats).
func _pick_kicks() -> Array:
	var picked := []
	for b in Tuning.list(DRUM_KICKS):
		for e in L.evs(b):
			if picked.all(func(k): return absf(k.t - e.t) >= DRUM_MIN_GAP * L.beat - 0.01):
				picked.append({"t": e.t, "branch": b})
	picked.sort_custom(func(a, b): return a.t < b.t)
	return picked


# ---------------------------------------------------------------- look

## Drums (coloured rim, white skin) rest on top of their own pillar, skin facing up and 35° towards the goal: the front
## bottom corner sits on the pillar, a wedge in the pillar's colour props up the back, the skin's centre is at the kick.
## Each drum: its body, the skin on it and the stand under it (an air dash has nothing drawn: the gap and the DASH!
## prompt say it).
func build() -> void:
	mats.drum_1a = Draw.mat(DRUM_COLOR_1A)
	mats.drum_1b = Draw.mat(DRUM_COLOR_1B)
	mats.drum_1c = Draw.mat(DRUM_COLOR_1C)
	mats.skin = Draw.mat(Color(0.98, 0.97, 0.94), Color(1.0, 0.95, 0.85), 0.1)  # flashes on the bass
	var ct := cos(DRUM_TILT)
	var st := sin(DRUM_TILT)
	for d in drums:
		d.seg = L.seg_at(d.t)
		var r: float = d.r
		var body := CylinderMesh.new()
		body.top_radius = r
		body.bottom_radius = r
		body.height = DRUM_H
		d.body = Draw.mesh(self, body, mats.get("drum_" + d.get("kind", "1a"), mats.drum_1a), Vector3(L.track.x_at(d.t), L.plat_h(d.t), 0.0))
		d.body.rotation.z = -DRUM_TILT  # skin turned to face up-forward
		var skin := CylinderMesh.new()
		skin.top_radius = r - 0.08
		skin.bottom_radius = r - 0.08
		skin.height = 0.03
		d.skin = Draw.mesh(d.body, skin, mats.skin, Vector3(0.0, DRUM_H * 0.5 + 0.017, 0.0))  # tilts and swells with the body
		# body centre relative to the kick point on the pillar top: the skin centre (local 0, +H/2) right above the kick,
		# the lowest corner (local +r, -H/2) touching the pillar
		d.x = L.track.x_at(d.t) - DRUM_H * 0.5 * st
		d.lift = r * st + DRUM_H * 0.5 * ct
		# the stand fills the space under the drum's bottom face (kept a hair below it, so the faces don't fight)
		var stand := PrismMesh.new()
		stand.left_to_right = 0.0  # upright side at the back, the slope falling towards the goal
		stand.size = Vector3(2.0 * r * ct, 2.0 * r * st - 0.03, r)
		d.stand = Draw.mesh(self, stand, L.mats.pillar, Vector3(d.x - DRUM_H * 0.5 * st, L.plat_h(d.t), 0.0))


## Each drum rides its (pumping) pillar, tilted towards the throw, swelling a little on the bass (the skin you run on
## stays close to the surface the player actually stands on).
func update_motion(_delta: float) -> void:
	var bass: float = L.band_avg(L.now, 0, 2)
	var pumped: float = L.pump_at(L.now) / maxf(0.01, L.pump_height)
	var x0: float = L.view_x0()
	var x1: float = L.view_x1()
	while _view_i < drums.size() and drums[_view_i].x + drums[_view_i].r < x0:
		_view_i += 1
	for i in range(_view_i, drums.size()):
		var d: Dictionary = drums[i]
		if d.x - d.r > x1:
			break
		var top: float = d.seg.top
		var s := 1.0 + 0.12 * bass
		d.body.position = Vector3(d.x, top + d.lift, 0.0)
		d.body.scale = Vector3(s, 1.0 + 0.25 * bass, s)
		d.stand.position.y = top + d.r * sin(DRUM_TILT) - 0.015
		Draw.shade(d.stand, L.theme_color.darkened(d.seg.dark), pumped * 0.7 + (0.5 if d.seg.climax else 0.0), top + d.back_h)
	if mats.has("skin"):
		mats.skin.emission_energy_multiplier = 0.1 + 2.5 * bass


## Drums on kicks (mode C's second drum too: it waits on the beat-3 kick); air dashes on the beat-3 kick.
func anchors() -> Array:
	return drums.map(func(d): return [d.t, "kick"]) + air_dashes.map(func(a): return [a.t, "kick"])


## The drums throw the player by themselves (a press there only scores; with DRUM_PRESS it is needed); the air dashes
## are needed.
func inputs() -> Array:
	return air_dashes.map(func(a): return a.t) + cues().map(func(c): return c.t)


## A jump on every drum, with DRUM_PRESS (needed) or DRUM_CUES (it only scores, but counts as something to press).
func cues() -> Array:
	return drums.map(func(d): return {"t": d.t, "action": "jump"}) if DRUM_PRESS or DRUM_CUES != 0 else []


## Prompts: the air dashes (needed), and a jump on every drum (optional: it only scores, unless DRUM_PRESS).
func prompts() -> Array:
	var out: Array = air_dashes.map(func(a): return {"t": a.t, "action": "dash"})
	for d in drums:
		out.append({"t": d.t, "action": "jump", "optional": not DRUM_PRESS})
	return out


func labels() -> Array:
	return drums.map(func(d): return [MODE_NAME[d.mode], Vector3(L.track.x_at(d.t), L.plat_h(d.t) - 0.6, 0.6)])


func tips() -> Array:
	var out := []
	if not drums.is_empty():
		out.append("[SPACE]\u00a0jump")
	if not air_dashes.is_empty():
		out.append("[SHIFT]\u00a0dash")
	return out


# ---------------------------------------------------------------- play

func autoplay() -> void:
	for d in drums:
		if not d.get("judged", false) and L.now >= d.t - 0.004 and L.now <= d.t + DRUM_WINDOW and L.jump_press <= L.NONE:
			L.jump_press = L.now
	for a in air_dashes:
		if not a.used and L.now >= a.t - 0.004 and L.now <= a.t + 0.05 and L.dash_press < a.t - 0.15:
			L.press_dash()


## Pressing jump on a drum's kick scores it for the streak; the drum throws by itself, unless DRUM_PRESS makes the
## press the throw (an early press waits for the kick).
func jump_claim(press: float) -> int:
	for d in drums:
		if not d.get("judged", false) and absf(press - d.t) <= DRUM_WINDOW:
			if DRUM_PRESS and L.now < d.t:
				return WAIT
			d.judged = true
			if DRUM_PRESS:
				_throw(d)
			L.judge(press - d.t)
			return TAKEN
	return PASS


func hop_blocked() -> bool:
	for d in drums:
		if not d.get("launched", false) and d.t > L.now and d.t - L.now <= DRUM_WINDOW + 0.05:
			return true
	return false


## The drum's spring throws the player by itself on the kick, off the skin's centre, aimed at where the arc has
## to end (the next platform, the next drum's skin, or level with a set-back platform).
func before_step(_delta: float) -> void:
	if DRUM_PRESS:
		return  # these wait for the jump press (jump_claim)
	for d in drums:
		if not d.get("launched", false) and L.now >= d.t:
			_throw(d)


func _throw(d: Dictionary) -> void:
	d.launched = true
	var p: Vector3 = L.player.global_position
	if p.y > d.seg.top + L.HALF - 0.5:  # still up on the drum's pillar, not fallen past it
		var tt: float = maxf(0.25, d.arc_t - L.now)
		L.player.jump((d.arc_y - p.y) / tt + L.GRAVITY * tt * 0.5)
		L.sfx.play("drum_bounce", 1.0, {"1b": 1, "1c": 2}.get(d.get("kind", "1a"), 0))


## Mode A: a dash in the air around beat 3 carries the player straight across to the set-back platform.
## It doesn't use up the press, so a jaw on the same beat counts too.
func after_step(_delta: float) -> void:
	var win: float = L.WINDOW
	for a in air_dashes:
		if a.used or L.now < a.t - win or L.now > a.until:
			continue
		if L.dash_press >= a.t - win and L.dash_press <= a.t + win and not L.player.grounded:
			a.used = true
			# glide to the platform's height (a press this late is there by the platform's edge, or it'd come in under it)
			var edge: float = a.until - (L.LAND_EDGE_T if L.dash_press - a.t > LATE_DASH_T else 0.0)
			L.player.hover(maxf(0.0, edge - L.now), L.plat_h(a.until) + L.HALF)
			L.judge(L.dash_press - a.t)


## Drums throw by themselves, so falling short almost always means a missed air dash (or, with DRUM_PRESS, jump).
func fail_reason() -> String:
	var now: float = L.now
	if air_dashes.any(func(a): return not a.used and now - a.t > 0.0 and now - a.t < 1.0):
		return "Missed the air dash: dash (SHIFT) on beat 3 to reach the platform"
	if DRUM_PRESS and drums.any(func(d): return not d.get("launched", false) and now - d.t > 0.0 and now - d.t < 1.5):
		return "Missed a jump: these drums only bounce if you press SPACE on the kick"
	return ""


## Carrying on from t: the drums and air dashes before it are over.
func skip_to(t: float) -> void:
	for d in drums:
		if d.t < t:
			d.launched = true
			d.judged = true
	for a in air_dashes:
		if a.t < t:
			a.used = true


## The intro panel: JUMP for the drums, DASH for the air dashes (level 1, where the closing pillars come with them).
func panel_caption() -> Dictionary:
	var out := {}
	if not drums.is_empty():
		out.JUMP = "Jump (SPACE) on the note"
	if not air_dashes.is_empty():
		out.DASH = "Dash (SHIFT) through the closing pillars and across the gaps"
	return out


## The intro panel's drawing: a drum (JUMP; an air dash has nothing drawn to show).
func panel_sprites() -> Array:
	var out := []
	if not drums.is_empty():
		out.append({"family": "JUMP", "t": drums.map(func(d): return d.t).min(), "palette": {"w": Color(0.98, 0.97, 0.94), "D": DRUM_COLOR_1A, "e": DRUM_COLOR_1A.darkened(0.35)},
			"rows": ["............", "............", "..wwwwwwww..", ".wwwwwwwwww.", ".DDDDDDDDDD.", ".DeeDDDDeeD.", ".DDeeDDeeDD.", ".DDDeeeeDDD.", ".DDDDeeDDDD.", ".DDDDDDDDDD.", "..DDDDDDDD..", "............"]})
	return out
