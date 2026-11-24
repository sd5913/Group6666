extends "res://scripts/mechanics/mechanic.gd"
## 5-1 镜像翻转 (level 4's kicks): two rows of pillars face each other like a mirrored music player — the run below,
## and a row hanging from above whose columns reach down with the music. On a kick (MIDI) the row the player is on
## runs out and the other row begins: press jump on the kick and gravity turns round, carrying the player across.
## The flips follow the song's beat: once a bar (every FLIP_BARS bars, phrase by phrase), on the bar's downbeat itself
## — on its kick, else on any note there (hi-hat, clap, bass, lead) — the rows taking turns; in the climax (6d) every
## half bar, on beat 3 too (FLIP_CLIMAX_HALF). A bar goes: 1 flip, 2 smash, 3 nothing, 4 smash or a fired wall
## (scripts/mechanics/smash.gd, launch.gd). Nothing flips on the level's rest beat (REST_BEAT). Each flip point shows a beam of light between the rows, brightening through the beat
## before; its kind shows in its colour and in its shape: a solid beam on the beat (1a), a double beam for an
## anticipation (1c), a dashed one off the beat (1b). In the groove bars (3a) the hanging columns reach further down
## with the music and glow brighter.
## The hanging columns are made of voxels: once the player has flipped back down and landed, the ones behind it crumble,
## from the side towards the player, and fall into the run (or the gap) below.
## Going up always means it worked: SPACE here never hops. A press with no flip to take just wobbles the jelly; an early
## one waits for the kick and counts as early. A flip that goes flashes its beam wide, throws voxels off and tints the
## player (FLIP_TINT), and landing on the other row swells that row; a kick let pass turns its beam red at once and says
## MISS, before the fall.

const Draw := preload("res://scripts/view/draw.gd")
const VoxelColumn := preload("res://scripts/view/voxel_column.gd")
const VoxelDebris := preload("res://scripts/view/voxel_debris.gd")
const Tuning := preload("res://scripts/core/tuning.gd")
const Spans := preload("res://scripts/core/spans.gd")

var FLIP_BARS := "1"           # a flip every this many bars, phrase by phrase (the last goes on to the end)
var FLIP_CLIMAX_HALF := 1      # in the climax (6d) a flip every half bar: on beat 3 too (1 yes / 0 no)
var FLIP_FROM := 1.0           # no flips before this (seconds)
var FLIP_WINDOW := 0.16        # press jump this close to the kick (seconds)
var FLIP_V := 8.0              # how fast a flip sets off (m/s)
var ROW_GAP := 4.0             # between the two rows' running surfaces (metres)
var FLIP_LATE := 0.3           # the row the player is on runs on this long after the kick (a late press still flips)
var FLIP_EARLY := 0.2          # the other row starts this long before it
var TOP_AMP := 0.35            # how far the hanging columns reach down with the music (metres)
var TOP_LEN := 2.2             # how much of each hanging column shows above its face before it fades into the sky
var FLIP_HUE_1B := 0.0         # flip colours: the accent for 1a, turned this much for 1b / the other way for 1c
var FLIP_HUE_1C := 0.0         # (0: one colour, the kinds told apart by their shape alone)
var TOP_CRUMBLE := 2.0         # how hard a left-behind hanging column falls apart (m/s)
var TOP_SHINE := 0.2           # how much the hanging columns whiten and glow (less: they keep their colour on a pale sky)
var TOP_GRAIN := 0.4           # how much a hanging column's voxels differ in shade from each other
var TOP_BOOST := 1.5           # in the groove bars (3a) the columns reach this much further with the music,
var TOP_BOOST_DIP := 0.2       # and this much lower besides (metres; calm near where the player meets the row)
var FLIP_TINT := 0.16          # a flip tints the player in the accent (0-1; a perfect one takes gold instead)
var FLIP_BURST := 16           # voxels thrown off as it goes (half as many where it lands)
var FLIP_SHAKE := 0.14         # camera jolt as it goes
var FLIP_SWELL := 0.7          # landing, the row swells this far around the player (metres)

const BEAM_FLASH_T := 0.3       # a beam whose flip went flashes wide for this long (seconds); a missed one goes red as long
const MISS_RED := Color(1.0, 0.32, 0.28)
const SWELL_T := 0.3            # how long a row stays swollen after a landing (seconds)

var flips: Array = []           # {t, kind, to_top, T, judged, beam, fired_t, landed, missed_t, ...}
var top_spans: Array = []       # [ta, tb] where the hanging row is there
var top_contacts: Array = []    # times something meets the hanging row (it stays calm around them)
var columns: Array = []         # hanging columns {x, t, base, band, amp, line, stem, cap, bottom}, by x
var _col_xs := PackedFloat32Array()
var _debris: VoxelDebris        # left-behind hanging columns, while their voxels fall
var _crumble_sound_t := -INF    # when the last run of columns letting go was heard (a run is one sound)
var _col_i := 0
var _transit := 0.25
var _taught: Array = []         # the tutorial's flips (an even number: it ends on the run below)


# ---------------------------------------------------------------- planning

## The tutorial's flip, on at[0].
func teach(at: Array, _kind := "") -> void:
	_taught.append({"t": at[0], "kind": "1a", "track": "kick"})


func plan_air() -> void:
	var picked: Array = _taught + _groove()
	if picked.size() % 2 == 1:
		picked.pop_back()  # the goal is on the run below: an even number of flips ends there
	var d: float = ROW_GAP - 2.0 * L.HALF
	_transit = (-FLIP_V + sqrt(FLIP_V * FLIP_V + 2.0 * L.GRAVITY * d)) / L.GRAVITY
	for i in picked.size():
		var f: Dictionary = picked[i]
		f.to_top = i % 2 == 0
		f.T = _transit
		f.judged = false
		flips.append(f)
		L.air_spans.append([f.t, f.t + _transit])
	# the rows: below up to each flip up (and a little after), above from just before it to the next flip down
	for i in range(0, flips.size(), 2):
		var up: Dictionary = flips[i]
		var down: Dictionary = flips[i + 1]
		top_spans.append([up.t - FLIP_EARLY, down.t + FLIP_LATE])
		L.up_spans.append([up.t + _transit, down.t])
		if down.t - FLIP_EARLY > up.t + FLIP_LATE:
			L.pits.append([up.t + FLIP_LATE, down.t - FLIP_EARLY])
		top_contacts.append(up.t + _transit)
		for k in [0.0, 0.25, 0.45]:  # a flat stretch on the row above before the flip down
			top_contacts.append(down.t - k)


## The flips the beat makes: a bar's downbeat (its kick, else any note on it), every FLIP_BARS bars; in the climax
## its beat 3 besides. [{t, kind, track}], in time order.
func _groove() -> Array:
	var every: Array = Array(FLIP_BARS.split(";", false)).map(func(s): return maxi(1, int(s.strip_edges())))
	var bar: float = L.data.bar_sec
	var picked := []
	var b: float = L.data.first_bar_at + ceilf((FLIP_FROM - L.data.first_bar_at) / bar - 0.001) * bar
	var n := 0  # bars since the first one that could flip
	while b <= L.data.dur - 1.5:
		var phrase: int = L.phrases.filter(func(p): return b >= p - 0.001).size()
		var k: int = every[clampi(phrase - 1, 0, every.size() - 1)] if not every.is_empty() else 1
		if n % k == 0:
			var beats := [b]
			if FLIP_CLIMAX_HALF != 0 and L.climax.any(func(c): return b >= c[0] - 0.02 and b < c[1]):
				beats.append(b + 2.0 * L.beat)
			for t in beats:
				var on: Array = L.note_on(t, "kick,hat,clap,bass,lead")
				if not on.is_empty() and on[0] <= L.data.dur - 1.5 and not L.rest_beat(on[0]):
					picked.append({"t": on[0], "kind": _kind(on[0], "1a"), "track": on[1]})
		n += 1
		b += bar
	return picked


## The kind of the kick at t, as the song's events have it (else `fallback`).
func _kind(t: float, fallback: String) -> String:
	for kind in ["1a", "1c", "1b"]:
		if L.evs(kind).any(func(e): return absf(e.t - t) <= 0.02):
			return kind
	return fallback


## Flat ground on the run below before every flip up, and where a flip down lands.
func plan_contacts() -> void:
	for f in flips:
		if f.to_top:
			for k in [0.0, 0.25, 0.45]:
				L.contacts.append(f.t - k)
			L.key_contacts.append(f.t)
		else:
			L.contacts.append(f.t + f.T)


## The hanging row's running surface for the perfect player at t (pumping down on the bass, like the run pumps up).
func roof_h(t: float) -> float:
	if not Spans.inside(top_spans, t):
		return INF
	return _top_base(t) - L.pump_at(t)


func _top_base(t: float) -> float:
	var s: Dictionary = L.seg_at(t)
	var below: float = s.base if not s.is_empty() else maxf(L.ground_h(t), L.key_floor(t)) + L.mech_lift
	return below + ROW_GAP


func solve() -> void:
	for f in flips:
		var land: float = f.t + f.T
		if f.to_top:
			L.arcs.append(L.arc(f.t, land, _top_base(land) - L.pump_at(land) - L.HALF, L.plat_h(f.t) + L.HALF, -1.0))
		else:
			L.arcs.append(L.arc(f.t, land, L.plat_h(land) + L.HALF, _top_base(f.t) - L.pump_at(f.t) - L.HALF, 1.0))


func anchors() -> Array:
	return flips.map(func(f): return [f.t, f.get("track", "kick")])


func cues() -> Array:
	return flips.map(func(f): return {"t": f.t, "action": "jump"})


func prompts() -> Array:
	return flips.map(func(f): return {"t": f.t, "action": "jump", "verb": "FLIP"})


func tips() -> Array:
	return ["[SPACE]\u00a0flip"] if not flips.is_empty() else []


## Keep both rows in the picture: look at the middle between them.
func view_focus(_t: float) -> Dictionary:
	if flips.is_empty() or L.now < flips[0].t - 2.0 or L.now > flips[-1].t + 1.0:
		return {}
	var mid: float = maxf(L.ground_h(L.now), L.key_floor(L.now)) + L.mech_lift + ROW_GAP * 0.5
	return {"y": mid - L.cam_rig.LOOK_UP + 0.3}


# ---------------------------------------------------------------- look

func kind_color(kind: String) -> Color:
	var c: Color = L.mats.accent
	match kind:
		"1b":
			c.h = fposmod(c.h + FLIP_HUE_1B, 1.0)
		"1c":
			c.h = fposmod(c.h + FLIP_HUE_1C, 1.0)
	return c


## The hanging row: square columns side by side wherever it is there, caps facing down; and a beam at every flip point.
func build() -> void:
	var nb: int = L.data.bands[0].size()
	_debris = VoxelDebris.new()
	add_child(_debris)
	for k in top_spans.size():
		var s: Array = top_spans[k]
		var down: Dictionary = flips[2 * k + 1] if 2 * k + 1 < flips.size() else {}
		var leave: float = down.t + down.T if not down.is_empty() else INF  # back down on the run below
		var xa: float = L.track.x_at(s[0])
		var xb: float = L.track.x_at(s[1])
		var n := maxi(1, roundi((xb - xa) / L.pillars.BAR_PITCH))
		var pitch := (xb - xa) / n
		for i in n:
			var t: float = lerpf(s[0], s[1], (i + 0.5) / n)
			var near := INF
			for c in top_contacts:
				near = minf(near, absf(t - c))
			var calm := smoothstep(0.15, 0.55, near)
			var band := clampi(2 + (i % 5) * 2, 0, nb - 1)
			var col := {"x": xa + (i + 0.5) * pitch, "t": t, "w": pitch * 0.82, "base": _top_base(t), "band": band,
				"amp": TOP_AMP * calm, "line": 0 if band < 4 else (1 if band < 8 else 2), "bottom": _top_base(t),
				"leave": leave, "gone": false}
			# a voxel column, its origin the face the player runs on (widths in whole voxels, so they share them)
			var w := maxf(VoxelColumn.VOXEL, snappedf(col.w, VoxelColumn.VOXEL))
			col.vox = VoxelColumn.make(self, w, w, TOP_LEN, 1, L.GRAVITY, int(L.data.level))
			col.vox.position = Vector3(col.x, col.base, 0.0)
			VoxelColumn.fade(col.vox, TOP_LEN, 0.6, 1.0)  # bright at the face, fading up into the sky (not into the dark)
			VoxelColumn.grain(col.vox, TOP_GRAIN)
			columns.append(col)
	columns.sort_custom(func(a, b): return a.x < b.x)
	for c in columns:
		_col_xs.append(c.x)
	for f in flips:
		var m := Draw.mat(kind_color(f.kind), kind_color(f.kind), 1.0)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		f.beam_mat = m
		f.beam = Node3D.new()
		f.beam.position.x = L.track.x_at(f.t)
		add_child(f.beam)
		# built one metre tall around its middle, stretched between the rows every step
		match f.kind:
			"1c":
				for dx in [-0.2, 0.2]:
					_bar(f.beam, m, Vector3(dx, 0.0, 0.0), Vector3(0.17, 1.0, 0.17))
			"1b":
				for i in 5:
					_bar(f.beam, m, Vector3(0.0, -0.4 + i * 0.2, 0.0), Vector3(0.26, 0.11, 0.26))
			_:
				_bar(f.beam, m, Vector3.ZERO, Vector3(0.28, 1.0, 0.28))


## A hanging column the player has left behind (back down on the run below) lets go: it breaks up from its lower edge
## on the player's side and its voxels fall onto the run under it, or into the gap.
func _crumble(c: Dictionary, face: float) -> void:
	c.gone = true
	var floor_y := -INF
	if not L.in_pit(c.t):
		floor_y = L.plat_h(c.t)
	VoxelColumn.break_apart(c.vox, Vector3(c.x + c.w * 0.5, face, 0.0), 0.0, 0.0, TOP_CRUMBLE, Vector3.ZERO, floor_y,
		c.x - 1.5, c.x + 1.5)
	_debris.add([c.vox])
	if L.now - _crumble_sound_t > 0.3 or L.now < _crumble_sound_t:
		L.sfx.play("crumble")
	_crumble_sound_t = L.now


func _bar(parent: Node3D, m: Material, pos: Vector3, size: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	Draw.mesh(parent, box, m, pos)


## Prepare landing swells before either the floor or hanging row moves this frame.
func prepare_bulges() -> void:
	for f in flips:
		if not f.get("landed", false):
			continue
		var age: float = L.now - f.land_t
		if age >= 0.0 and age < SWELL_T:
			L.pillars.bulges.append([f.land_x + 2.0 * age / SWELL_T, 3.5,
				FLIP_SWELL * (1.0 - age / SWELL_T), f.to_top])


## Hanging columns reach down on their band and pump with the bass (and crumble once left behind for good); beams
## brighten through the beat before their kick and flash as it lands.
func update_motion(_delta: float) -> void:
	var now: float = L.now
	VoxelColumn.set_sky(L.cam_rig.env.background_color)  # the columns fade up into it
	var p: float = L.pump_at(now)
	var x0: float = L.view_x0()
	var x1: float = L.view_x1()
	while _col_i < columns.size() and columns[_col_i].x + columns[_col_i].w < x0:
		_col_i += 1
	for i in range(_col_i, columns.size()):
		var c: Dictionary = columns[i]
		if c.x - c.w > x1:
			break
		var v: float = L.band_at(now, c.band)
		var boost: float = 1.0 if L.in_boost(c.t) else 0.0  # a groove bar: further down (calm where the row is met)
		var calm: float = c.amp / maxf(0.001, TOP_AMP)
		c.bottom = c.base - p - v * c.amp * lerpf(1.0, TOP_BOOST, boost) - TOP_BOOST_DIP * boost * calm
		if c.gone:
			continue
		var face: float = c.bottom - (L.pillars.bulge_at(c.x, true) if not L.pillars.bulges.is_empty() else 0.0)
		c.vox.position = Vector3(c.x, face, 0.0)
		VoxelColumn.shade(c.vox, L.pillars.lines[c.line].color, minf(1.0, v * 0.8 * (1.0 + 0.5 * boost)), TOP_SHINE)
		# from the one nearest the player back, the further behind the later
		if now > c.leave + maxf(0.0, L.track.x_at(c.leave) - c.x) / 25.0 and c.x + c.w < L.player.position.x:
			_crumble(c, face)
	for f in flips:
		_swell(f)
		var x: float = f.beam.position.x
		if x < x0 or x > x1:
			continue
		var lo: float = L.plat_h(f.t)
		var hi: float = _top_base(f.t) - p
		var lead: float = f.t - now
		var a := 0.0
		var wide := 1.0 + (0.6 if lead <= 0.0 else 0.0)
		var col: Color = kind_color(f.kind)
		if f.has("fired_t"):  # it went: a wide white flash, narrowing back to the beam
			var k := clampf((now - f.fired_t) / BEAM_FLASH_T, 0.0, 1.0)
			a = 1.0 - k
			wide = lerpf(6.0, 1.0, sqrt(k))
			col = col.lerp(Color.WHITE, 0.7 * (1.0 - k))
		elif f.has("missed_t"):  # let pass: red, closing up
			var k := clampf((now - f.missed_t) / BEAM_FLASH_T, 0.0, 1.0)
			a = 1.0 - k
			wide = 1.6 * (1.0 - k)
			col = MISS_RED
		elif lead > 0.0 and lead < 2.0 * L.beat:  # shows for the two beats before its kick, firming up
			a = 0.45 + 0.55 * (1.0 - lead / (2.0 * L.beat))
		elif lead <= 0.0 and lead > -0.4:
			a = 1.0 + lead * 2.0
		f.beam.visible = a > 0.01
		f.beam.position = Vector3(x, (lo + hi) * 0.5, -0.3)
		f.beam.scale = Vector3(wide, maxf(0.1, hi - lo), 1.0)
		col.a = clampf(a, 0.0, 1.0)
		f.beam_mat.albedo_color = col
		f.beam_mat.emission = col


## The hanging row's surface under x right now (INF where it isn't there).
func roof_at(t: float, x: float) -> float:
	if not Spans.inside(top_spans, t) or columns.is_empty():
		return INF
	var k := _col_xs.bsearch(x)
	var best := INF
	for j in [k - 1, k]:
		if j >= 0 and j < columns.size() and absf(columns[j].x - x) <= columns[j].w:
			best = minf(best, columns[j].bottom)
	return best if best < INF else _top_base(t) - L.pump_at(t)


# ---------------------------------------------------------------- play

func autoplay() -> void:
	for f in flips:
		if not f.judged and L.now >= f.t - 0.004 and L.now <= f.t + FLIP_WINDOW and L.jump_press <= L.NONE:
			L.jump_press = L.now


## Jump on a flip's kick turns gravity round. An early press (up to L.EARLY_PRESS, or still kept then) waits for the kick;
## earlier than the window it counts as early (a miss), and the flip still goes. With no flip to take, in the flips'
## section, the press does nothing but wobble the jelly: no hop that would look like a flip.
func jump_claim(press: float) -> int:
	for f in flips:
		if f.judged or f.has("missed_t") or L.press_kept(press) < f.t - L.EARLY_PRESS or press > f.t + FLIP_WINDOW:
			continue
		if L.player.up != (1.0 if f.to_top else -1.0):
			continue
		if L.now < f.t - 0.03:
			return WAIT
		f.judged = true
		L.player.flip(FLIP_V)
		L.sfx.play("flip", 1.0, 0 if f.to_top else 1)
		_went(f)
		L.judge_early(press - f.t, FLIP_WINDOW, "Press SPACE on the kick")
		return TAKEN
	var span: Array = L.section_span(name)
	if flips.is_empty() or (not span.is_empty() and (L.now < span[0] or L.now >= span[1])):
		return PASS
	L.player.look.bump(0.4, 0.0)
	L.sfx.play("judge_miss", 0.4)
	return TAKEN


## A flip goes: its beam flashes, voxels fly off the row, the jelly stretches and changes tint, and the view jolts.
func _went(f: Dictionary) -> void:
	f.fired_t = L.now
	var p: Vector3 = L.player.global_position
	Draw.burst(L, p + Vector3.UP * L.HALF * L.player.up, L.mats.accent_frag, FLIP_BURST, 8.0, 0.16)  # (it has just turned over)
	L.player.look.bump(-1.2, 0.0)
	L.cam_rig.jolt(FLIP_SHAKE)
	L.player.look.pulse(L.mats.accent, FLIP_TINT, L.PULSE_T)


## Landed on the other row: voxels fly off it and it swells around the player for a moment.
func _swell(f: Dictionary) -> void:
	if not f.has("fired_t") or L.now > f.fired_t + 2.0:
		return
	if not f.get("landed", false):
		if not L.player.grounded or L.now <= f.fired_t:
			return
		f.landed = true
		f.land_t = L.now
		f.land_x = L.player.position.x
		Draw.burst(L, L.player.global_position - Vector3.UP * L.HALF * L.player.up, L.mats.accent_frag, FLIP_BURST / 2, 5.0, 0.14)
		L.sfx.play("plunge_land", 0.5)
		L.cam_rig.jolt(FLIP_SHAKE * 0.6)


## A kick let pass: its beam goes red and the popup says so at once, before the fall does.
func after_step(_delta: float) -> void:
	for f in flips:
		if f.judged or f.has("missed_t") or L.now <= f.t + FLIP_WINDOW:
			continue
		f.missed_t = L.now
		L.player.look.bump(0.8, -0.3)
		L.miss("Missed a flip! Press SPACE on the kick at the light beam")


func hop_blocked() -> bool:
	return flips.any(func(f): return not f.judged and f.t > L.now and f.t - L.now <= FLIP_WINDOW + 0.05)


## Upside down, falling "up" past the hanging row is falling.
func fallen() -> bool:
	if L.player.up > 0.0:
		return false
	var top: float = _top_base(L.now) - L.HALF
	return L.player.global_position.y > top + 2.5


func fail_reason() -> String:
	for f in flips:
		if not f.judged and L.now > f.t and L.now < f.t + 2.0:
			return "Flip: press SPACE on the kick at the light beam to switch rows"
	return ""


## Carrying on from t: the flips before it are over, and the hanging columns left behind by then are gone.
func skip_to(t: float) -> void:
	for f in flips:
		if f.t < t:
			f.judged = true
			f.landed = true
	for c in columns:
		if c.leave < t:
			c.gone = true
			c.vox.visible = false


## The intro panel: FLIP.
func panel_caption() -> Dictionary:
	return {"FLIP": "Jump (SPACE) at the beam to flip rows"} if not flips.is_empty() else {}


## The intro panel's drawing: the two rows and a flip's beam between them.
func panel_sprites() -> Array:
	if flips.is_empty():
		return []
	return [{"family": "FLIP", "t": flips.map(func(f): return f.t).min(), "palette": {"b": kind_color(flips[0].kind), "t": L.theme_color}, "rows": ["tttttttttttt", "tttttttttttt", ".....bb.....", "....bbbb....", ".....bb.....", ".....bb.....", ".....bb.....", ".....bb.....", "....bbbb....", ".....bb.....", "tttttttttttt", "tttttttttttt"]}]
