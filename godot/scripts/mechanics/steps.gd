extends "res://scripts/mechanics/mechanic.gd"
## 踏板 (level 2's busy arpeggio): where the arpeggio gets dense (STEP_MIN_NOTES notes in a phrase, from
## STEP_FROM_PHRASE on), its notes become stairs of floating treads over a gap. A beat's first arpeggio note is a jump
## (one closer than STEP_SPACING beats to the last one shares that one's tread: about every other beat): jump on it and
## the player makes a real jump (STEP_V up) onto the next tread: every tread STEP_CLIMB_MIN higher than the last,
## whatever the notes, and as much higher again as its note rises over the last one's (STEP_PITCH a semitone), never
## more than STEP_UP up in all. Stairs that would climb past KEY_MAX go down instead: every tread STEP_CLIMB_MIN lower
## than the last, and as much lower again as its note falls, never more than STEP_DOWN down, nor so far that the player
## would still be in the air when a press a whole window early comes for the next note; stairs that fit neither way
## aren't put there at all. They always climb or always go down, never flat. The treads are laid out from that jump:
## the next
## one starts where a jump pressed a whole window early comes down, the one taken off from runs on past a press a whole
## window late. The first jump takes off from a beat of flat ground, the last lands on the ground after the stairs,
## STEP_EXIT_BELOW under the last tread (which keeps still for it, not pumping on the bass; a glide taking off within two beats
## takes off from up there too); a rest of a beat in the arpeggio ends a stairs. A press early
## (L.EARLY_PRESS before the first jump; on the stairs, any time since the last jump) waits for the note; earlier than
## the window, the jump still goes but counts as early (a miss). Missing the jump leaves the gap to cross.
## A tread is a floating block of voxels in the accent colour, its hue leaning with its note's pitch, fading into the
## dark downwards like the pillars, with a bright top edge; the arpeggio's notes are drawn flush on its top and front
## faces, like a piano roll, each lighting up on its note (shaders/tread_notes.gdshader — nothing stands out of it). It
## brightens through the beat before its jump and crumbles once the player has left it.

const Draw := preload("res://scripts/view/draw.gd")
const VoxelColumn := preload("res://scripts/view/voxel_column.gd")
const VoxelDebris := preload("res://scripts/view/voxel_debris.gd")
const Glide := preload("res://scripts/mechanics/glide.gd")
const NotesShader := preload("res://shaders/tread_notes.gdshader")

var STEP_TRACK := "arp"        # the MIDI track the stairs come from
var STEP_MIN_NOTES := 8        # phrases with at least this many of its notes get stairs
var STEP_FROM_PHRASE := 3      # ...from this phrase on
var STEP_SPACING := 1.75       # a beat's first note closer than this many beats to the last jump gets no tread
var STEP_MIN_JUMPS := 3        # a stairs has at least this many jumps (the last one back onto the ground)
var STEP_EXIT_BEATS := 0.75    # flat ground kept clear after the last landing (beats)
var STEP_V := 8.0              # a jump on the stairs takes off this fast (m/s; 8: 1.45 m high, 0.73 s in the air on the flat)
var STEP_PITCH := 0.12         # a tread is this much higher per semitone than the first one (metres)
var STEP_LIFT := 0.3           # the first tread's note sits this far above the run-up (metres)
var STEP_UP := 0.6             # one tread is at most this much higher than the last (what the jump climbs easily),
var STEP_DOWN := 0.9           # and at most this much lower (metres)
var STEP_CLIMB_MIN := 0.3      # and at least this much higher, whatever the notes (metres; 0: they may go down too)
var STEP_EXIT_BELOW := 0.0     # the ground after the stairs is this much below the last tread (metres)
var STEP_WINDOW := 0.16        # jump this close to the note (seconds)
var STEP_GLOW_MAX := 1.0       # the treads' glow never goes past this (less: they keep their colour on a pale sky)
var STEP_CRUMBLE := 2.0        # how hard a tread left behind falls apart (m/s)

const RUNUP_CLEAR := 0.2        # the run-up's last this-long has nothing else on it (a wall may stand before that)
const COYOTE := 0.03            # a tread runs on this long past the latest take-off (seconds)
const TREAD_H := 0.6            # a tread's thickness (metres)
const TREAD_D := 1.0            # its depth across the run (metres)

var runs: Array = []            # {jumps [{t, pitch, air, edge, front, land, vy, judged, missed}], treads [seg],
								#  top, dir (1: climbing, -1: going down)}
var _debris: VoxelDebris        # treads left behind, while their voxels fall


## The dense phrases (next to each other: one stretch), their notes in strings split at rests of a beat, each
## string's jumps, and as many stairs from them as fit around what is already planned.
func plan_air() -> void:
	var notes: Array = L.song.notes(STEP_TRACK)  # (only its section's, in the final level)
	var ph: Array = L.phrases + [L.data.dur]
	var spans := []
	for i in range(maxi(0, STEP_FROM_PHRASE - 1), ph.size() - 1):
		if notes.filter(func(n): return n[0] >= ph[i] and n[0] < ph[i + 1]).size() < STEP_MIN_NOTES:
			continue
		if not spans.is_empty() and absf(spans[-1][1] - ph[i]) < 0.001:
			spans[-1][1] = ph[i + 1]
		else:
			spans.append([ph[i], ph[i + 1]])
	for sp in spans:
		var string := []
		for n in notes.filter(func(n): return n[0] >= sp[0] and n[0] < sp[1]):
			if n[0] + n[1] > L.data.dur - 1.0:
				continue
			if not string.is_empty() and n[0] - (string[-1][0] + string[-1][1]) >= L.beat - 0.001:
				_fit(_jumps(string))
				string = []
			string.append(n)
		_fit(_jumps(string))
	runs.sort_custom(func(a, b): return a.jumps[0].t < b.jumps[0].t)


## The tutorial's treads: a jump at each of these times, the last back onto the ground.
func teach(at: Array, _kind := "") -> void:
	_add(at.map(func(t): return {"t": t, "pitch": 60.0}), 1)


## A string's jumps: every beat's first note, unless it comes too soon after the last jump (sooner than STEP_SPACING
## beats, or than the longest jump down comes down).
func _jumps(string: Array) -> Array:
	var out := []
	var beat_i := -1
	for n in string:
		var bi := int(floor(n[0] / L.beat + 0.001))
		if bi == beat_i:
			continue
		beat_i = bi
		if out.is_empty() or n[0] - out[-1].t >= maxf(STEP_SPACING * L.beat, _air(-STEP_DOWN) + 0.03) - 0.001:
			out.append({"t": n[0], "pitch": n[2]})
	return out


## Seconds a jump at STEP_V takes to come down dy higher than it took off.
func _air(dy: float) -> float:
	var v := STEP_V
	return (v + sqrt(maxf(0.0, v * v - 2.0 * L.GRAVITY * dy))) / L.GRAVITY


## How high every landing is above the run-up, climbing (dir 1): the first tread STEP_LIFT up (at least
## STEP_CLIMB_MIN), each next one STEP_CLIMB_MIN higher than the last plus its note's rise over the last one's
## (STEP_PITCH a semitone; a fall adds nothing), never more than STEP_UP (or STEP_CLIMB_MIN) up in all. Going down
## (dir -1) the same the other way round (a note's fall adds, a rise doesn't; never more than STEP_DOWN down), and never
## so far down that a jump would still be in the air a window and a little before the next note (_drop_max); where even
## STEP_CLIMB_MIN is too far, [] (no such stairs). Then the ground after the stairs STEP_EXIT_BELOW under the last tread.
## [0 (the run-up), tread 0, ..., the ground]
func _heights(jumps: Array, dir: int) -> Array:
	var out := [0.0]
	var prev := 0.0
	for k in jumps.size() - 1:
		var step: float = maxf(STEP_LIFT, STEP_CLIMB_MIN)
		if k > 0:
			var more: float = maxf(0.0, (jumps[k].pitch - jumps[k - 1].pitch) * STEP_PITCH * dir)
			step = minf(STEP_CLIMB_MIN + more, maxf(STEP_UP if dir > 0 else STEP_DOWN, STEP_CLIMB_MIN))
		if dir < 0:
			step = minf(step, _drop_max(jumps[k + 1].t - jumps[k].t))
			if step < STEP_CLIMB_MIN - 0.001:
				return []
		var y: float = prev + step * dir
		out.append(y)
		prev = y
	out.append(prev - STEP_EXIT_BELOW)
	return out


## How far down a jump at STEP_V can go and still be down a window and a little (STEP_WINDOW + COYOTE) before the next
## note, `gap` seconds after its own.
func _drop_max(gap: float) -> float:
	var v := STEP_V
	var g: float = L.GRAVITY
	var air := gap - STEP_WINDOW - COYOTE
	if air * g <= 2.0 * v:
		return -INF
	return ((air * g - v) * (air * g - v) - v * v) / (2.0 * g)


## Where everything of jumps[k] is: the take-off ground ends a window and a little after the note (edge), the next
## tread starts where a jump a window early comes down (front), a jump on the note comes down there a window later.
func _place(jumps: Array, dir: int) -> void:
	var h := _heights(jumps, dir)
	for k in jumps.size():
		var j: Dictionary = jumps[k]
		j.air = _air(h[k + 1] - h[k])
		j.edge = j.t + STEP_WINDOW + COYOTE
		j.front = j.t - STEP_WINDOW + j.air
		j.land = j.t + j.air


## The longest stretches of jumps that fit (at least STEP_MIN_JUMPS each) become stairs: climbing ones if they fit,
## else going down.
func _fit(jumps: Array) -> void:
	var i := 0
	while i < jumps.size():
		var last := -1
		var dir := 1
		for d in [1, -1]:
			for j in range(i + STEP_MIN_JUMPS - 1, jumps.size()):  # a longer stretch only overlaps more
				if not _fits(jumps.slice(i, j + 1), d):
					break
				last = j
			if last >= 0:
				dir = d
				break
		if last >= 0:
			_add(jumps.slice(i, last + 1), dir)
			i = last + 1
		else:
			i += 1


## Whether stairs on these jumps (a beat of flat run-up before, its last RUNUP_CLEAR with nothing else on it;
## STEP_EXIT_BEATS of ground after) fit between what is planned.
func _fits(jumps: Array, dir: int) -> bool:
	var h := _heights(jumps, dir)
	if h.is_empty():
		return false  # (going down, a tread would come too late for the next note)
	_place(jumps, dir)
	var run_up := _run_up(jumps[0].t)
	if run_up + h.max() > L.KEY_MAX + L.mech_lift + 0.001:
		return false  # (it would climb past KEY_MAX: rather down, or no stairs, than flat ones)
	if dir < 0 and run_up + h.min() < L.KEY_MIN + L.mech_lift - 0.001:
		return false  # (nor down past KEY_MIN)
	var a: float = jumps[0].t - L.beat
	var clear: float = jumps[0].t - RUNUP_CLEAR
	var b: float = jumps[-1].land + STEP_EXIT_BEATS * L.beat
	if L.air_spans.any(func(s): return a < s[1] + 0.05 and b > s[0] - 0.05):
		return false
	if L.busy_spans.any(func(s): return clear < s[1] + 0.05 and b > s[0] - 0.05):
		return false
	return not L.pits.any(func(p): return a < p[1] and b > p[0])


## How high stairs taking off at t start (the top of the mechanic pillar there, pumping on the bass as carve finds it;
## on from the last stairs' top if they end just before, as the ground keeps that height for them).
func _run_up(t: float) -> float:
	var base: float = maxf(L.ground_h(t), L.key_floor(t)) + L.mech_lift + L.pump_at(t)
	for r in runs:
		if r.jumps[-1].land < t and t - r.jumps[-1].land < 1.5:
			base = r.top
	return base


func _add(jumps: Array, dir: int) -> void:
	var top: float = _run_up(jumps[0].t) + _heights(jumps, dir)[-1]
	jumps = jumps.map(func(j): return j.duplicate())
	_place(jumps, dir)
	for j in jumps:
		j.judged = false
		j.missed = false
		L.air_spans.append([j.t, j.land])
		L.pits.append([j.edge, j.front])
	for k in jumps.size() - 1:
		L.busy_spans.append([jumps[k].land, jumps[k + 1].t])
	L.busy_spans.append([jumps[0].t - RUNUP_CLEAR, jumps[0].t])
	L.busy_spans.append([jumps[-1].land, jumps[-1].land + STEP_EXIT_BEATS * L.beat])
	runs.append({"jumps": jumps, "treads": [], "top": top, "dir": dir})


## A beat of flat run-up at the take-off's key height; ground for STEP_EXIT_BEATS after the last landing. (The jumps'
## own ends are contacts already: their air spans.)
func plan_contacts() -> void:
	for r in runs:
		var j0: Dictionary = r.jumps[0]
		L.contacts.append(j0.t - L.beat)
		L.contacts.append(j0.t - L.beat * 0.5)
		L.key_contacts.append(j0.t)
		L.contacts.append(r.jumps[-1].land + STEP_EXIT_BEATS * L.beat * 0.5)
		L.contacts.append(r.jumps[-1].land + STEP_EXIT_BEATS * L.beat)
		var g := _next_glide(r)
		var t: float = r.jumps[-1].land
		while not g.is_empty() and t < g.t0:  # one pillar from the stairs' top on to the glide's take-off
			L.contacts.append(t)
			t += 0.2


## The glide taking off within two beats of the stairs' last landing, if there is one ({} if not).
func _next_glide(r: Dictionary) -> Dictionary:
	var glide = L.mechanic("glide")
	if glide == null:
		return {}
	var land: float = r.jumps[-1].land
	for g in glide.glides:
		if g.t0 > land and g.t0 <= land + 2.0 * L.beat:
			return g
	return {}


## A landing on a tread reaches over the whole tread: each tread is one pillar, from gap to gap.
func contact_r(t: float) -> float:
	for r in runs:
		var jumps: Array = r.jumps
		for k in jumps.size() - 1:
			if absf(jumps[k].land - t) < 0.001:
				return maxf(jumps[k].land - jumps[k].front, jumps[k + 1].edge - jumps[k].land) + 0.02
	return -1.0


## The treads' and the ground after the stairs' heights (_heights) above the run-up as it is at the take-off (it pumps
## on the bass); that ground keeps still (the jump onto it is timed to its height).
func carve() -> void:
	for r in runs:
		var jumps: Array = r.jumps
		var h := _heights(jumps, r.dir)
		var run_up: float = L.plat_h(jumps[0].t)
		for k in jumps.size() - 1:
			var seg: Dictionary = L.seg_at(jumps[k].land)
			seg.base = run_up + h[k + 1]
			seg.top = seg.base
			seg.by = self
			seg.tread = true
			r.treads.append(seg)
		var g := _next_glide(r)
		var t: float = jumps[-1].land + 0.01
		while true:  # the ground after the stairs, on to a glide taking off soon after
			var exit: Dictionary = L.seg_at(t)
			if not exit.is_empty():
				exit.base = run_up + h[-1]
				exit.top = exit.base
				exit.still = true
				t = exit.tb + 0.01
			else:
				t += 0.05
			if g.is_empty() or t > g.t0:
				break


## A tread stays where it is (no pumping on the bass) until it is left behind.
func surface(s: Dictionary, _top: float, _x: float) -> float:
	return -INF if s.get("gone", false) else s.base


## The perfect path: a jump on each jump's note from the ground it is on to the next tread (the last: to the ground),
## coming down where STEP_V takes it (its arc's take-off speed comes out as STEP_V).
func solve() -> void:
	for r in runs:
		var jumps: Array = r.jumps
		var y: float = L.plat_h(jumps[0].t) + L.HALF
		for k in jumps.size():
			var j: Dictionary = jumps[k]
			var y_land: float = (r.treads[k].base if k < r.treads.size() else L.plat_h(j.land)) + L.HALF
			var arc: Dictionary = L.arc(j.t, j.land, y_land, y)
			j.vy = arc.vy
			L.arcs.append(arc)
			y = y_land


func anchors() -> Array:
	var out := []
	for r in runs:
		for j in r.jumps:
			out.append([j.t, STEP_TRACK])
	return out


func cues() -> Array:
	var out := []
	for r in runs:
		for j in r.jumps:
			out.append({"t": j.t, "action": "jump"})
	return out


func tips() -> Array:
	if runs.is_empty():
		return []
	return ["[SPACE]\u00a0jump"]


# ---------------------------------------------------------------- look

## Each tread a block of voxels hanging from its top face, fading into the dark downwards, with a bright edge along
## the top; on its top and front faces, flush, every note of the arpeggio over it (cut to the tread).
func build() -> void:
	_debris = VoxelDebris.new()
	add_child(_debris)
	var edge_mesh := BoxMesh.new()
	edge_mesh.size = Vector3(1.0, 0.06, TREAD_D + 0.04)
	for r in runs:
		var notes: Array = L.song.between(STEP_TRACK, r.jumps[0].t - 0.01, r.jumps[-1].t + 0.01)
		for k in r.treads.size():
			var seg: Dictionary = r.treads[k]
			var w := _vox(L.track.x_at(seg.tb) - L.track.x_at(seg.ta))
			var xa: float = (L.track.x_at(seg.ta) + L.track.x_at(seg.tb) - w) * 0.5
			var xb: float = xa + w
			var tint := _tint(r.jumps[k].pitch)
			var slab := VoxelColumn.make(self, w, TREAD_D, TREAD_H, -1, L.GRAVITY, int(L.data.level))  # origin: its top face
			slab.position = Vector3((xa + xb) * 0.5, seg.base, 0.0)
			VoxelColumn.fade(slab, TREAD_H, TREAD_H * 0.25)
			var edge_mat := Draw.mat(tint.lightened(0.55), tint.lightened(0.3), 0.6)
			var edge := Draw.mesh(self, edge_mesh, edge_mat, Vector3((xa + xb) * 0.5, seg.base - 0.02, 0.0))
			edge.scale.x = w
			var marks := ShaderMaterial.new()
			marks.shader = NotesShader
			marks.set_shader_parameter("color", tint)
			var on: Array = notes.filter(func(n): return L.track.x_at(n[0]) < xb - 0.1 and L.track.x_at(n[0] + n[1]) > xa + 0.1)
			Glide.notes_to(marks, on, xa, L.track.x_at)
			var skin := MeshInstance3D.new()
			skin.mesh = _skin(w, seg.base)
			skin.position.x = xa
			skin.material_override = marks
			skin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(skin)
			seg.look = {"slab": slab, "edge": edge, "edge_mat": edge_mat, "tint": tint, "xa": xa, "xb": xb, "skin": skin,
				"marks": marks}


## A tread's skin for its notes, lying flush on its top face (COLOR.g) and front face (COLOR.b): UV.x metres along it,
## UV.y across the top (front to back) and down the front.
func _skin(w: float, top: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hz := TREAD_D * 0.5 + 0.003
	var y := top + 0.003
	var quads := [
		[[Vector3(0.0, y, hz), Vector3(w, y, hz), Vector3(w, y, -hz), Vector3(0.0, y, -hz)], Color(0.0, 1.0, 0.0)],
		[[Vector3(0.0, y, hz), Vector3(w, y, hz), Vector3(w, y - TREAD_H, hz), Vector3(0.0, y - TREAD_H, hz)], Color(0.0, 0.0, 1.0)]]
	for q in quads:
		var v: Array = q[0]
		var uv := [Vector2(0.0, 0.0), Vector2(w, 0.0), Vector2(w, 1.0), Vector2(0.0, 1.0)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(q[1])
			st.set_uv(uv[k])
			st.add_vertex(v[k])
	return st.commit()


## A width rounded to whole voxels (so treads of about the same length share their voxels).
func _vox(w: float) -> float:
	return maxf(VoxelColumn.VOXEL, snappedf(w, VoxelColumn.VOXEL))


## A tread's colour: the accent, its hue leaning with the note's pitch class (round the circle of fifths, like the
## notes in the background) — further than the glide's note marks ever do, so the two don't read as one.
func _tint(pitch: float) -> Color:
	var c: Color = L.mats.accent
	var pc := int(pitch) % 12
	c.h = fposmod(c.h + (float((pc * 7) % 12) / 12.0 - 0.5) * 0.2, 1.0)
	return c


## A tread brightens through the beat before the jump onto it, peaking on that jump's note; its notes light up on
## their notes (its skin's shader). Once the player is past it, it crumbles from its back end.
func update_motion(_delta: float) -> void:
	var now: float = L.now
	var x0: float = L.view_x0()
	var x1: float = L.view_x1()
	var px: float = L.player.position.x
	var bass: float = L.band_avg(now, 0, 2)
	for r in runs:
		for k in r.treads.size():
			var seg: Dictionary = r.treads[k]
			var look: Dictionary = seg.look
			if seg.get("gone", false) or look.xb < x0 or look.xa > x1:
				continue
			if px > look.xb + 0.5:
				_crumble(seg)
				continue
			var t: float = r.jumps[k].t
			var ask := smoothstep(t - L.beat, t, now) if now < t else exp(-(now - t) * 5.0)
			var glow := minf(STEP_GLOW_MAX, 0.15 + 0.15 * bass + 0.85 * ask)
			VoxelColumn.shade(look.slab, look.tint, glow, L.BLOCK_SHINE)
			look.edge_mat.emission_energy_multiplier = 0.6 + 2.0 * ask
			look.marks.set_shader_parameter("now", now)


## A tread left behind: its voxels fall apart from its back end, its edge and notes go with it.
func _crumble(seg: Dictionary) -> void:
	var look: Dictionary = seg.look
	seg.gone = true
	VoxelColumn.break_apart(look.slab, Vector3(look.xa, seg.base, 0.0), 0.0, 0.0, STEP_CRUMBLE, Vector3(-1.0, 0.5, 0.0),
		-INF, 0.0, 0.0)
	_debris.add([look.slab])
	L.sfx.play("crumble")
	look.edge.visible = false
	look.skin.visible = false


# ---------------------------------------------------------------- play

func autoplay() -> void:
	for r in runs:
		for j in r.jumps:
			if not j.judged and L.now >= j.t - 0.004 and L.now <= j.t + STEP_WINDOW and L.jump_press <= L.NONE:
				L.jump_press = L.now


## A jump on its note jumps onto the next tread. An early press waits for the note, also while the player is still in
## the air from the last jump: up to L.EARLY_PRESS early (or still kept then) for the first jump, and on the stairs any
## press since the last jump (none is lost there); it is only given up once the window is over.
func jump_claim(press: float) -> int:
	for r in runs:
		var jumps: Array = r.jumps
		for k in jumps.size():
			var j: Dictionary = jumps[k]
			if j.judged or j.missed or press > j.t + STEP_WINDOW:
				continue
			if k == 0 and L.press_kept(press) < j.t - L.EARLY_PRESS:
				break  # before these stairs
			if L.now < j.t - 0.06 or not L.can_jump():
				return WAIT if L.now <= j.t + STEP_WINDOW else PASS
			j.judged = true
			L.player.jump(STEP_V)
			L.judge_early(press - j.t, STEP_WINDOW, "Press SPACE when the tread is brightest")
			return TAKEN
	return PASS


## No plain hops on the stairs (one would sail over the treads), nor just before a jump.
func hop_blocked() -> bool:
	for r in runs:
		if L.now > r.jumps[0].t - STEP_WINDOW - 0.05 and L.now < r.jumps[-1].land:
			return true
	return false


## Expire the input window. The landing surface stays available until the player has passed it.
func before_step(_delta: float) -> void:
	for r in runs:
		for j in r.jumps:
			if not j.judged and not j.missed and L.now > j.t + STEP_WINDOW + 0.01:
				j.missed = true


func fail_reason() -> String:
	for r in runs:
		if L.now > r.jumps[0].t - 0.2 and L.now < r.jumps[-1].land + 0.8:
			return "Treads: jump (SPACE) to the next tread when it is brightest"
	return ""


## Carrying on from t: the stairs before it are over and gone.
func skip_to(t: float) -> void:
	for r in runs:
		for k in r.jumps.size():
			if r.jumps[k].t < t:
				r.jumps[k].judged = true
				if k < r.treads.size() and r.treads[k].tb < t:
					var seg: Dictionary = r.treads[k]
					var look: Dictionary = seg.look
					seg.gone = true
					look.slab.visible = false
					look.edge.visible = false
					look.skin.visible = false


## The intro panel: JUMP.
func panel_caption() -> Dictionary:
	return {"JUMP": "Jump (SPACE) on the note"} if not runs.is_empty() else {}


## The intro panel's drawing: two treads stepping up, their bright top edges.
func panel_sprites() -> Array:
	if runs.is_empty():
		return []
	var a: Color = L.mats.accent
	return [{"family": "JUMP", "t": runs.map(func(r): return r.jumps[0].t).min(), "palette": {"a": a, "A": a.lightened(0.55), "d": a.darkened(0.45)}, "rows": ["............", "............", ".......AAAAA", ".......aaaaa", ".......ddddd", "............", "AAAAA.......", "aaaaa.......", "ddddd.......", "............", "............", "............"]}]
