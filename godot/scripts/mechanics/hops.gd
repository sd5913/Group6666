extends "res://scripts/mechanics/mechanic.gd"
## 笛音跳台 (hops: the lead's fast stretches, from the first HOPS_FROM_EVENT event on): where at least HOPS_MIN_NOTES
## lead notes start within two beats, a string of little floating flutes — one a beat, on that beat's first lead note —
## carries the player along in the air, bouncing from one onto the next right on its note (by itself, like level 1's
## drums: SPACE as you land on one only scores). A flat flute on the ground, on the note before, throws the player up
## onto the first; the last throws them back down onto the ground on the next beat's note. Each flute floats
## HOPS_LIFT over the ground, plus HOPS_PITCH a semitone its note stands over the string's lowest (0.6 to 2.4 m over
## it), so the string draws the tune in the air while the ground draws it below (with GRID_LOCK each flute right on its
## beat, on a note there — the lead's, else the drums' or the bass' — still playing the lead's note); SPACE on one, in
## its window, plays its note on a flute (HOPS_SOUND) — pressing on the beat plays the tune — and landing on one
## unpressed only makes a soft muted tick (the bounce comes all the same; no judgement sound either way). Under a
## string the ground keeps still (no visualizer pillars tossing up into the arcs): a
## still pillar a flute, at the ground's height there. A string has at least HOPS_MIN floating flutes and half a second
## of flat ground before it takes off and after it lands; it keeps clear of what is planned before it (the terrace's
## steps, the rests) and comes before the big pillars and the curtains, which keep clear of it.
## With HOPS_CLIMAX, in the held climax (track.CLIMAX_HOLD, from three beats before it to a bar after) the strings come
## first — worked out before the terrace's steps, which keep clear of them — taking an arp note on a beat with nothing
## else on it, and each ends in a slam (scripts/mechanics/slam.gd): its last flute throws the player up, to come down
## over the slam's pad on the kick a beat later, S slamming them onto it (a press that counts, unlike the flutes).

const Draw := preload("res://scripts/view/draw.gd")
const Spans := preload("res://scripts/core/spans.gd")
const PlayerScript := preload("res://scripts/player.gd")

var HOPS_FROM_EVENT := ""      # from the first event of this branch on ("6a"; "": the whole level)
var HOPS_MIN_NOTES := 6        # a fast stretch: at least this many lead notes start within two beats
var HOPS_MIN := 4              # a string has at least this many floating flutes
var HOPS_LIFT := 0.6           # the string's lowest note floats this high over the ground (metres)
var HOPS_PITCH := 0.15         # and every semitone higher this much higher
var HOPS_SOUND := 1            # SPACE on a flute plays its note, landing on it unpressed a soft tick (1 on / 0 off)
var HOPS_WINDOW := 0.18        # SPACE this close to landing on a flute scores (seconds)
var HOPS_CLIMAX := 0           # 1: in the held climax the strings come first and each ends in a slam (0: as anywhere)

const LIFT_MIN := 0.6           # a flute floats at least / at most this high over the ground
const LIFT_MAX := 2.4
const FLAT := 0.5               # flat ground before a string takes off and after it lands (seconds)
const PIPE_L := 1.0             # a flute's length along the run, its radius (metres)
const PIPE_R := 0.17
const TICK_GRACE := 0.03        # a landing unpressed ticks this long after (a press in time still plays the note)

var runs: Array = []            # {pads: [{t, pitch, top, x, ...}] (pads[0] the flute on the ground), land_t, slam (it ends
								#  in a slam on the kick at land_t)}
var _mat: StandardMaterial3D
var _climax = null              # climax_plan()'s strings, once worked out


# ---------------------------------------------------------------- planning

## The tutorial's string: a flute at each of these times, the last time the landing.
func teach(at: Array, _kind := "") -> void:
	var pads := []
	for i in at.size() - 1:
		pads.append([i, [at[i], 0.0, 72.0 + 2.0 * i], "lead"])
	_add(pads, [at.size() - 1, [at[-1], 0.0, 72.0], "lead"])


## The strings: the fast stretches' beats (a beat starting two beats with HOPS_MIN_NOTES lead notes, and the next one),
## each beat's first lead note a flute, cut where what is planned before would be in the way.
func plan_air() -> void:
	var notes: Array = L.song.notes("lead")
	if notes.is_empty():
		return
	var slam = L.mechanic("slam")
	for cs in climax_plan():  # (first: everything after keeps clear of them)
		_add(cs.pads, [], cs.slam_t)
		slam.add_from_air(cs.slam_t, cs.pads[-1][1][0])
	var from := 0.0
	if HOPS_FROM_EVENT != "":
		from = INF
		for e in L.data.events:
			if e.branch == HOPS_FROM_EVENT:
				from = minf(from, e.t)
	var firsts := _firsts(notes, from, "lead,kick,clap,hat,bass")
	var k := 0
	while k < firsts.size():
		# from flute k on the ground: as many floating ones as fit, the beat after the last one's note to land on
		var j := k + 1
		var best := -1
		while j + 1 < firsts.size() and firsts[j + 1][0] == firsts[j][0] + 1 and firsts[j][0] == firsts[j - 1][0] + 1:
			if _fits(firsts[k][1][0], firsts[j + 1][1][0]):
				best = j
			else:
				break
			j += 1
		if best >= 0 and best - k >= HOPS_MIN:
			_add(firsts.slice(k, best + 1), firsts[best + 1])
			k = best + 2
		else:
			k += 1
	runs.sort_custom(func(a, b): return a.pads[0].t < b.pads[0].t)


## The fast stretches' beats from `from` on (a beat starting two beats with HOPS_MIN_NOTES lead notes, and the next
## one), each with its first lead note (with GRID_LOCK: a note right on the beat, on the first of `tracks` that has one,
## still playing the lead's note there), only those in [w0, w1): [[beat index, note [t, -, pitch], track]].
func _firsts(notes: Array, from: float, tracks: String, w0 := -INF, w1 := INF) -> Array:
	var beat: float = L.beat
	var fast := {}
	var i0 := ceili((maxf(from, notes[0][0]) - L.data.first_bar_at) / beat - 0.001)
	var i1 := floori((notes[-1][0] - L.data.first_bar_at) / beat)
	for i in range(i0, i1 + 1):
		var b: float = L.data.first_bar_at + i * beat
		if notes.filter(func(n): return n[0] >= b - 0.02 and n[0] < b + 2.0 * beat - 0.02).size() >= HOPS_MIN_NOTES:
			fast[i] = true
			fast[i + 1] = true
	var firsts := []
	for i in range(i0, i1 + 2):
		var b: float = L.data.first_bar_at + i * beat
		if not fast.has(i) or b < w0 - 0.001 or b >= w1 - 0.001:
			continue
		if L.GRID_LOCK != 0:
			var on: Array = L.note_on(b, tracks)
			if not on.is_empty():
				firsts.append([i, [on[0], 0.0, _pitch_at(notes, on[0])], on[1]])
			continue
		for n in notes:
			if n[0] >= b - 0.02 and n[0] < b + beat - 0.02:
				firsts.append([i, n, "lead"])
				break
	return firsts


## The held climax's strings (HOPS_CLIMAX): over its fast stretches, from three beats before it to a bar after it ends
## (an arp note counting where nothing else is on the beat), as many strings as fit, each ending in a slam on the kick
## a beat after its last flute; the next taking off FLAT after that slam's bounce lands, its slam at least
## TERRACE_SLAM_GAP after the last one; each string as long as that leaves it. Worked out once (the terraces keep clear
## of them before the mechanics plan): [{pads: firsts' entries (the ground one first), slam_t, land_t (the bounce's)}].
func climax_plan() -> Array:
	if _climax != null:
		return _climax
	_climax = []
	var slam = L.mechanic("slam")
	var notes: Array = L.song.notes("lead")
	if HOPS_CLIMAX == 0 or slam == null or notes.is_empty():
		return _climax
	var bounce: float = slam.SLAM_BOUNCE_BEATS * L.beat
	for c in L.climax_held:
		var firsts := _firsts(notes, 0.0, "lead,kick,clap,hat,bass,arp", c[0] - 3.0 * L.beat, c[1] + L.data.bar_sec)
		var run := []
		for f in firsts + [null]:
			if f != null and (run.is_empty() or f[0] == run[-1][0] + 1):
				run.append(f)
				continue
			_climax.append_array(_ending_in_slams(run, bounce))
			run = [f] if f != null else []
	return _climax


## A stretch of beats one after another (firsts' entries) cut into strings that each end in a slam: from the end back,
## each as late and short as it can be (so as many fit as can), then each taking off as early as it can.
func _ending_in_slams(run: Array, bounce: float) -> Array:
	var t := func(j: int) -> float: return run[j][1][0]
	var picks := []  # [ground flute, last flute, slam's kick]
	var f := run.size() - 1
	var k_next := INF
	var g_next := INF
	while f >= HOPS_MIN:
		var k: float = t.call(f) + L.beat
		if not L.note_on(k, "kick").is_empty() and k + bounce <= L.data.dur + 0.01 and k + bounce + FLAT <= g_next + 0.001 \
				and k_next - k >= L.TERRACE_SLAM_GAP - 0.001:
			picks.push_front([f - HOPS_MIN, f, k])
			k_next = k
			g_next = t.call(f - HOPS_MIN)
			f -= HOPS_MIN + 1
		else:
			f -= 1
	var out := []
	var earliest := -INF
	for p in picks:
		var g: int = p[0]
		while g > 0 and t.call(g - 1) >= earliest - 0.001:
			g -= 1
		out.append({"pads": run.slice(g, p[1] + 1), "slam_t": p[2], "land_t": p[2] + bounce})
		earliest = p[2] + bounce + FLAT
	return out


## Whether a string taking off at `launch` and landing at `land` fits what is planned so far: in the air in between,
## clear of the air, the gaps, the taken ground and the terrace's steps (run-up to landing); FLAT before and after on
## solid ground — not in the air or over a gap, and not on taken ground unless it is a flat run-up to an edge.
func _fits(launch: float, land: float) -> bool:
	var hit := func(sp: Array, a: float, b: float) -> bool: return a < sp[1] + 0.05 and b > sp[0] - 0.05
	if (L.air_spans + L.busy_spans + L.pits).any(func(sp): return hit.call(sp, launch, land)):
		return false
	if L.terrace.any(func(st): return st.has("land_t") and hit.call([st.get("a", st.t - 1.0), st.land_t], launch, land)):
		return false
	var spring_air: Array = L.terrace.filter(func(st): return st.kind == "spring").map(func(st): return [st.t - L.beat, st.t])
	for m in [[launch - FLAT, launch], [land, land + FLAT]]:
		if (L.air_spans + L.pits + spring_air).any(func(sp): return m[0] < sp[1] and m[1] > sp[0]):
			return false
		for sp in L.busy_spans:  # (a run-up ends where its air starts)
			if m[0] < sp[1] and m[1] > sp[0] and not L.air_spans.any(func(ai): return absf(ai[0] - sp[1]) < 0.01):
				return false
	return true


## The lead's note at t (on the beat, with GRID_LOCK): the one starting there, else the highest sounding, else the
## first starting within the beat after.
func _pitch_at(notes: Array, t: float) -> float:
	var sounding := NAN
	for n in notes:
		if absf(n[0] - t) <= 0.02:
			return n[2]
		if n[0] < t and n[0] + n[1] > t and (is_nan(sounding) or n[2] > sounding):
			sounding = n[2]
	if not is_nan(sounding):
		return sounding
	for n in notes:
		if n[0] > t and n[0] < t + L.beat:
			return n[2]
	return notes[0][2]


## A string: its flutes (firsts' entries: the ground one first) and the entry it lands on — or, ending in a slam,
## the slam's kick (the slam itself is slam.gd's).
func _add(pads: Array, land: Array, slam_t := NAN) -> void:
	var lo: float = pads.slice(1).map(func(f): return f[1][2]).min()
	var slam := not is_nan(slam_t)
	var land_t: float = slam_t if slam else land[1][0]
	var run := {"pads": [], "land_t": land_t, "land_track": "kick" if slam else land[2], "lo": lo, "slam": slam}
	for f in pads:
		run.pads.append({"t": f[1][0], "pitch": f[1][2], "track": f[2], "thrown": false, "judged": false, "flash": 0.0})
	runs.append(run)
	L.air_spans.append([run.pads[0].t, land_t])
	L.busy_spans.append([run.pads[0].t - FLAT, run.pads[0].t])
	if not slam:
		L.busy_spans.append([land_t, land_t + FLAT])


## Flat ground where a string takes off and lands, and still ground all along under it (one pillar, carved below); a
## string ending in a slam has that ground up to halfway from its last flute to the slam's pad (the pit from there).
func plan_contacts() -> void:
	for r in runs:
		var t0: float = r.pads[0].t
		var end: float = _ground_end(r)
		for c in [t0 - FLAT, t0 - FLAT * 0.5]:
			L.contacts.append(c)
		for i in int((end - t0) / 0.2) + 1:
			L.contacts.append(t0 + i * 0.2)
		L.key_contacts.append(t0)
		if not r.slam:
			for c in [r.land_t + FLAT * 0.5, r.land_t + FLAT, r.land_t]:
				L.contacts.append(c)
			L.key_contacts.append(r.land_t)


## Where the still ground under a string ends: its landing (a little before), or halfway to its slam's pad.
func _ground_end(r: Dictionary) -> float:
	return (r.pads[-1].t + r.land_t) * 0.5 if r.slam else r.land_t


## Under the floating flutes, a still pillar each (from halfway to the one before to halfway to the next), at the
## ground's height under it: the ground steps with the tune below the string, and keeps out of its arcs.
func carve() -> void:
	for r in runs:
		var n: int = r.pads.size()
		for i in range(1, n):
			var t: float = r.pads[i].t
			var a: float = (r.pads[i - 1].t + t) * 0.5 if i > 1 else r.pads[0].t + 0.2
			var b: float = (t + r.pads[i + 1].t) * 0.5 if i + 1 < n else (_ground_end(r) if r.slam else r.land_t - 0.2)
			var base := _ground(t)
			var kept := []
			for s in L.mech:
				for piece in Spans.subtract([[s.ta, s.tb]], [[a, b]]):
					if piece[1] - piece[0] > 0.01:
						var p: Dictionary = s.duplicate()
						p.ta = piece[0]
						p.tb = piece[1]
						kept.append(p)
			kept.append({"ta": a, "tb": b, "base": base, "top": base, "still": true})
			L.mech = kept


## The flutes' heights over the finished ground, and the arcs from one onto the next.
func solve() -> void:
	for r in runs:
		for i in r.pads.size():
			var p: Dictionary = r.pads[i]
			p.x = L.track.x_at(p.t)
			if i == 0:
				p.top = L.plat_h(p.t)  # (the flute on the ground: the player stands on its pillar)
			else:
				p.top = _flute_top(r, p)
		for i in r.pads.size():
			var p: Dictionary = r.pads[i]
			var nt: float = r.pads[i + 1].t if i + 1 < r.pads.size() else r.land_t
			var ny: float = (r.pads[i + 1].top if i + 1 < r.pads.size() else L.plat_h(r.land_t)) + L.HALF
			if r.slam and i + 1 == r.pads.size():
				ny = throw_y(nt)
				L.mechanic("slam").solve_from_air(nt, ny)
			p.next_t = nt
			p.next_y = ny
			L.arcs.append(L.arc(p.t, nt, ny, p.top + L.HALF))


## A floating flute's top: HOPS_LIFT over the ground, and HOPS_PITCH more a semitone its note stands over the string's
## lowest.
func _flute_top(r: Dictionary, p: Dictionary) -> float:
	return _ground(p.t) + clampf(HOPS_LIFT + (p.pitch - r.lo) * HOPS_PITCH, LIFT_MIN, LIFT_MAX)


## Where the last flute of the string ending in a slam on kick t throws the player (their centre, on the kick): up and
## over the slam's pad, coming down no faster than off a run-up's edge (as if walked off SLAM_EDGE_T before), so S has
## its whole window (NAN: no string ends there). The slam's pad is set under it (slam.gd).
func throw_y(t: float) -> float:
	for r in runs:
		if r.slam and absf(r.land_t - t) < 0.001:
			var p: Dictionary = r.pads[-1]
			var tt: float = t - p.t
			return _flute_top(r, p) + L.HALF - L.GRAVITY * L.mechanic("slam").SLAM_EDGE_T * tt + 0.5 * L.GRAVITY * tt * tt
	return NAN


## The ground a flute floats over: the key height where the mechanic pillars stand.
func _ground(t: float) -> float:
	return maxf(L.ground_h(t), -INF if L.in_terrace(t) else L.key_floor(t)) + L.mech_lift


# ---------------------------------------------------------------- look

## Each floating flute: a short pipe across the run in the accent colour, three holes along its top that light up as
## it is landed on; the first lies flat on the ground.
func build() -> void:
	_mat = Draw.mat(L.mats.accent, L.mats.accent, 0.4)
	var pipe := CylinderMesh.new()
	pipe.top_radius = PIPE_R
	pipe.bottom_radius = PIPE_R
	pipe.height = PIPE_L
	var hole := BoxMesh.new()
	hole.size = Vector3(0.09, 0.03, 0.09)
	for r in runs:
		for i in r.pads.size():
			var p: Dictionary = r.pads[i]
			var c := Vector3(p.x, p.top - PIPE_R, 0.0)
			p.node = Draw.mesh(self, pipe, _mat, c)
			p.node.rotation.z = PI * 0.5  # lying along the run
			p.holes = []
			for k in 3:
				var hm := StandardMaterial3D.new()
				hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				hm.albedo_color = L.mats.accent.lightened(0.6)
				p.holes.append(Draw.mesh(self, hole, hm, Vector3(p.x + (k - 1) * 0.28, p.top + 0.005, 0.0)))
				p["hole_mat_%d" % k] = hm
			if L.sfx != null and HOPS_SOUND != 0:
				L.sfx.prime("flute", int(p.pitch))


## A landed flute's holes flash white and fade back.
func update_motion(delta: float) -> void:
	var x0: float = L.view_x0()
	var x1: float = L.view_x1()
	for r in runs:
		for p in r.pads:
			if not p.has("node") or p.x < x0 - 2.0 or p.x > x1:
				continue
			p.flash = maxf(0.0, p.flash - delta * 3.0)
			for k in 3:
				var hm: StandardMaterial3D = p["hole_mat_%d" % k]
				hm.albedo_color = L.mats.accent.lightened(0.6).lerp(Color(1, 1, 1), p.flash)


# ---------------------------------------------------------------- play

## Standing on a floating flute: its top, for a player over it and not below it (a string is only ever landed on from
## above; running underneath, it isn't there) — from just before its moment on: the throws onto it are aimed at that
## moment, and one reaching it near the top of its arc doesn't step onto it early.
func float_support(_t: float, x: float) -> float:
	var feet: float = L.player.position.y - L.HALF
	var best := -INF
	for r in runs:
		if r.pads[0].t > L.now + 1.0 or r.land_t < L.now - 1.0:
			continue
		for i in range(1, r.pads.size()):
			var p: Dictionary = r.pads[i]
			if p.has("x") and L.now >= p.t - 0.02 and absf(x - p.x) <= PIPE_L * 0.5 + PlayerScript.RADIUS * 0.5 					and feet >= p.top - 0.25:
				best = maxf(best, p.top)
	return best


## Each flute throws the player on to the next (the last onto the ground) by itself on its note, if they are on it:
## its note if SPACE came for it already (early in its window); else, unless SPACE comes within TICK_GRACE (it plays the
## note then), a soft tick.
func before_step(_delta: float) -> void:
	var pos: Vector3 = L.player.global_position
	for r in runs:
		for i in r.pads.size():
			var p: Dictionary = r.pads[i]
			if L.now >= p.get("tick_at", INF):
				p.tick_at = INF
				L.sfx.play("flute_tick")
			if p.thrown or L.now < p.t or not p.has("top"):
				continue
			p.thrown = true
			if absf(pos.y - (p.top + L.HALF)) < 0.5 and absf(pos.x - p.x) < PIPE_L:
				var tt: float = maxf(0.2, p.next_t - L.now)
				L.player.jump((p.next_y - pos.y) / tt + L.GRAVITY * tt * 0.5)
				p.flash = 1.0
				if HOPS_SOUND != 0:
					if p.judged:
						L.sfx.play("flute", 1.0, int(p.pitch))
					else:
						p.tick_at = L.now + TICK_GRACE


func autoplay() -> void:
	for r in runs:
		for p in r.pads:
			if not p.judged and L.now >= p.t - 0.004 and L.now <= p.t + HOPS_WINDOW and L.jump_press <= L.NONE:
				L.jump_press = L.now


## SPACE on a flute's note (as the player lands on it) scores and plays its note — on the bounce, or now if it has
## bounced already — without a judgement sound (the flute's note is the sound of it); the flutes throw by themselves.
func jump_claim(press: float) -> int:
	for r in runs:
		for p in r.pads:
			if not p.judged and absf(press - p.t) <= HOPS_WINDOW:
				p.judged = true
				L.judge(press - p.t, false)
				if p.thrown and HOPS_SOUND != 0:  # (late: it has bounced; its tick, if not ticked yet, is the note now)
					p.tick_at = INF
					L.sfx.play("flute", 1.0, int(p.pitch))
				return TAKEN
	return PASS


func hop_blocked() -> bool:
	for r in runs:
		for p in r.pads:
			if not p.thrown and p.t > L.now and p.t - L.now <= HOPS_WINDOW + 0.05:
				return true
	return false


## Every flute stands on its lead note, and so does the landing.
func anchors() -> Array:
	var out := []
	for r in runs:
		for p in r.pads:
			out.append([p.t, p.get("track", "lead")])
		out.append([r.land_t, r.get("land_track", "lead")])
	return out


## A press on every flute (it only scores, but counts as something to press).
func cues() -> Array:
	var out := []
	for r in runs:
		for p in r.pads:
			out.append({"t": p.t, "action": "jump"})
	return out


func prompts() -> Array:
	return cues().map(func(c): c.optional = true; return c)


func tips() -> Array:
	return ["[SPACE]\u00a0jump"] if not runs.is_empty() else []


## Carrying on from t: the strings before it are over.
func skip_to(t: float) -> void:
	for r in runs:
		for p in r.pads:
			if p.t < t:
				p.thrown = true
				p.judged = true


## The intro panel: JUMP.
func panel_caption() -> Dictionary:
	return {"JUMP": "Jump (SPACE) on the note"} if not runs.is_empty() else {}


## The intro panel's drawing: a flute lying across the run, its three holes lit.
func panel_sprites() -> Array:
	if runs.is_empty():
		return []
	var a: Color = L.mats.accent
	return [{"family": "JUMP", "t": runs.map(func(r): return r.pads[0].t).min(), "palette": {"a": a, "h": a.lightened(0.6)}, "rows": ["............", "............", "............", "............", "............", ".aaaaaaaaaa.", "aahaaahaaaha", "aaaaaaaaaaaa", ".aaaaaaaaaa.", "............", "............", "............"]}]
