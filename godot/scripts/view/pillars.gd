extends Node3D
const DrawParam := preload("res://scripts/view/draw.gd")
## The ground's look (5-3): square pillars in the level's theme colour, like a music player's visualizer.
## Visualizer pillars fill the stretches where nothing touches the ground, each following one spectrum band (within every
## group of BAR_GROUP pillars the low-mids sit in the middle and the treble at the edges, so each group swells like the
## bumps of an audio visualizer). Under every contact point stands a mechanic pillar that pumps on the bass. Also the
## plain run-up / finish ground, the goal gate and the dark floor far below the gaps (every column reaches down to it).

const Draw := preload("res://scripts/view/draw.gd")

const SAMPLE_DT := 0.04        # plain ground mesh resolution (seconds of run)
const DEPTH := 3.0             # plain ground depth

var BAR_PITCH := 1.4           # visualizer pillars: spacing,
var BAR_FILL := 0.8            # how much of the spacing the pillar fills,
var BAR_GROUP := 7             # pillars per bump: low-mids in the middle, treble at the edges
var MECH_DEPTH := 2.0          # mechanic pillars are deeper than the visualizer ones
var BOOST_GLOW := 0.6          # 3a boost bars: how much brighter their pillars glow
var BAR_MEET_MECH := false     # next to a mechanic, bars ease to the height of its pillar (no step up or down onto it)
var CLIMAX_BASS := 1.3         # in a held climax (track.CLIMAX_HOLD) the bass bands' pillars swing this much further,
var CLIMAX_FLASH := 0.6        # and every pillar's top flashes this much brighter on each kick (level.kick_pulse)
var ABYSS_Y := -60.0           # the floor far below the gaps (metres; every column reaches it): never seen from a pit,
                               # where the far waves and the plate behind them show instead

var L
var bars: Array = []            # visualizer bars {x, base, band, amp, top, stem, cap}, sorted by x
var bar_xs := PackedFloat32Array()
var bar_spans: Array = []       # [x0, x1] stretches where the bars are the ground
var lines: Array = []           # bass / arp / lead MIDI lines: {starts, notes, color} — the colour of whatever is playing
var bulges: Array = []          # [x, reach, height, on_top]: swells running along a row this step (a mechanic may add them; visual only)
var _mech_i := 0                # the first mechanic pillar / visualizer bar not yet left behind
var _bar_i := 0


## The transcribed bass, arpeggio and lead lines, so pillars can take the colour of the note being played.
func build_lines() -> void:
	for key in ["bass", "arp", "lead"]:
		var notes: Array = L.data.get(key, [])
		var starts := PackedFloat32Array()
		for n in notes:
			starts.append(n.t)
		var first: float = notes[0].midi if notes.size() > 0 else 60.0
		lines.append({"starts": starts, "notes": notes, "color": L.note_color(first)})


func build() -> void:
	# visualizer pillars between the mechanics
	for f in L.free_spans:
		_build_bars(f[0], f[1])
	bar_xs.resize(bars.size())
	for i in bars.size():
		bar_xs[i] = bars[i].x
	# one square pillar under every mechanic, in the theme colour: every other phrase a shade darker, the climax glowing
	for s in L.mech:
		var xa: float = L.track.x_at(s.ta)
		var xb: float = L.track.x_at(s.tb)
		s.x = (xa + xb) * 0.5
		s.w = maxf(0.4, xb - xa - 0.12)
		var mid_t: float = (s.ta + s.tb) * 0.5
		s.climax = L.climax.any(func(c): return mid_t >= c[0] and mid_t < c[1])
		s.dark = 0.0 if mid_t < 0.0 or L.phrases.filter(func(p): return mid_t >= p - 0.001).size() % 2 == 1 else 0.35
		s.boost = L.in_boost(mid_t)
		if s.get("tread", false):  # a floating stairs tread: drawn by the steps, no pillar under it
			continue
		s.stem = Draw.mesh(self, L.mats.bar_stem, L.mats.pillar, Vector3(s.x, s.base, 0.0))
		s.cap = Draw.mesh(self, L.mats.bar_cap, L.mats.pillar, Vector3(s.x, s.base, 0.0))
		DrawParam.param(s.cap, "boost", 1.8)
	# plain ground for the run-up and the finish
	for s in L.static_spans:
		_ground_strip(s[0], s[1], _ground_mat(s[0] + 0.001))
	# goal gate
	var gx: float = L.track.x_at(L.data.dur)
	var gh: float = L.ground_h(L.data.dur)
	for z in [-1.3, 1.3]:
		var post := BoxMesh.new()
		post.size = Vector3(0.4, 5.0, 0.4)
		Draw.mesh(self, post, L.mats.goal, Vector3(gx, gh + 2.5, z))
	var top := BoxMesh.new()
	top.size = Vector3(0.6, 0.5, 3.0)
	Draw.mesh(self, top, L.mats.goal, Vector3(gx, gh + 5.0, 0.0))
	# a dark floor far below the gaps, for depth, out to behind the far waves (it fades away before its edge: L.mats.abyss)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(L.track.x_at(L.t_end) - L.track.x_at(L.t_start - 2.0) + 240.0, 120.0)
	var floor := Draw.mesh(self, floor_mesh, L.mats.abyss,
		Vector3((L.track.x_at(L.t_end) + L.track.x_at(L.t_start)) * 0.5, ABYSS_Y, -30.0))
	floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Top of the visualizer pillar under x (-INF where there are none).
func bar_support(x: float) -> float:
	for s in bar_spans:
		if x >= s[0] and x <= s[1]:
			var k := bar_xs.bsearch(x)
			var best := -INF
			for j in [k - 1, k]:  # the capsule straddles at most two bars
				if j >= 0 and j < bars.size() and absf(bars[j].x - x) <= BAR_PITCH:
					best = maxf(best, bars[j].top)
			if best > -INF:
				return best
	return -INF


## The colour the visualizer pillar under x has right now (alpha 0 where there is none).
func bar_color(x: float) -> Color:
	var k := bar_xs.bsearch(x)
	for j in [k - 1, k]:
		if j >= 0 and j < bars.size() and absf(bars[j].x - x) <= bars[j].r + 0.2:
			return bars[j].get("col", L.theme_color)
	return Color(0, 0, 0, 0)


func on_bars(x: float) -> bool:
	return bar_spans.any(func(s): return x >= s[0] and x <= s[1])


## Everything on the ground moves with the music (each physics step, before the player stands on anything):
## visualizer pillars on their band, nudged towards the colour of their line's note; mechanic pillars pump on the bass;
## the goal glows with the volume. Only what is near the player (L.view_x0 .. view_x1) is moved.
func update_motion() -> void:
	_update_line_colors()
	var p: float = L.pump_at(L.now)
	var pumped := p / maxf(0.01, L.pump_height)
	var x0: float = L.view_x0()
	var x1: float = L.view_x1()
	var bass_k: float = lerpf(1.0, CLIMAX_BASS, L.climax_k(L.now))
	var flash: float = CLIMAX_FLASH * L.kick_pulse(L.now)
	var mech: Array = L.mech
	while _mech_i < mech.size() and mech[_mech_i].x + mech[_mech_i].w * 0.5 < x0:
		_mech_i += 1
	for i in range(_mech_i, mech.size()):
		var s: Dictionary = mech[i]
		if s.x - s.w * 0.5 > x1:
			break
		if s.get("tread", false):  # (a tread doesn't pump)
			continue
		s.top = s.base + (0.0 if s.get("still", false) else p)  # (nor does a pillar a jump is timed to land on)
		var bottom: float = ABYSS_Y
		Draw.place_column(s.stem, s.cap, s.x, bottom, s.top, s.w, MECH_DEPTH)
		var tint: Color = L.theme_color.darkened(s.dark)
		var glow: float = pumped * 0.7 + (0.5 if s.climax else 0.0) + (BOOST_GLOW if s.boost else 0.0) + flash
		Draw.shade(s.stem, tint, glow, s.top)
		Draw.shade(s.cap, tint, glow, s.top)
	while _bar_i < bars.size() and bars[_bar_i].x + bars[_bar_i].r < x0:
		_bar_i += 1
	for i in range(_bar_i, bars.size()):
		var b: Dictionary = bars[i]
		if b.x - b.r > x1:
			break
		var v: float = L.band_at(L.now, b.band)
		var top: float = b.base + v * b.amp * L.bar_height * (bass_k if b.band <= 2 else 1.0)
		if BAR_MEET_MECH and not b.near.is_empty():  # level with the mechanic pillar beside it, free further away
			top = lerpf(b.near.base + p, top, b.calm * b.calm)
		b.top = top
		if not bulges.is_empty():  # drawn swollen; what is stood on (b.top) stays as it is
			top += bulge_at(b.x, false)
		var bottom: float = ABYSS_Y
		Draw.place_column(b.stem, b.cap, b.x, bottom, top, b.r * 2.0, b.r * 2.0)
		var col: Color = lines[b.line].color
		col.h = fposmod(col.h + b.tint, 1.0)
		b.col = col
		var bglow := v + (BOOST_GLOW if b.boost else 0.0) + flash
		Draw.shade(b.stem, col, bglow, top)
		Draw.shade(b.cap, col, bglow, top)
	L.mats.goal.emission_energy_multiplier = 0.4 + 2.0 * L.band_avg(L.now, 0, 11)


## How far a row's columns at x are drawn swollen out this step (on_top: the hanging row).
func bulge_at(x: float, on_top: bool) -> float:
	var h := 0.0
	for b in bulges:
		if b[3] == on_top and absf(x - b[0]) < b[1]:
			h = maxf(h, b[2] * (0.5 + 0.5 * cos(PI * (x - b[0]) / b[1])))
	return h


## Each line's colour slides towards the note sounding now (or the last one, through rests).
func _update_line_colors() -> void:
	for ln in lines:
		var starts: PackedFloat32Array = ln.starts
		if starts.is_empty():
			continue
		var i := starts.bsearch(L.now, true) - 1
		if i >= 0:
			ln.color = (ln.color as Color).lerp(L.note_color(ln.notes[i].midi), 0.25)


## Which MIDI line a spectrum band belongs to: low bands follow the bass, middle the arpeggio, high the lead.
func _line_of_band(band: int) -> int:
	return 0 if band < 4 else (1 if band < 8 else 2)


## A row of visualizer pillars filling ta..tb: square columns rising out of the abyss, each following one
## spectrum band. Pillars near a contact point move less.
func _build_bars(ta: float, tb: float) -> bool:
	var xa: float = L.track.x_at(ta)
	var xb: float = L.track.x_at(tb)
	if xb - xa < L.BAR_MIN_SPAN:
		return false
	var n := maxi(1, roundi((xb - xa) / BAR_PITCH))
	var pitch := (xb - xa) / n
	var r := clampf(pitch * BAR_FILL * 0.5, 0.35, 0.6)  # half the column's width
	bar_spans.append([xa, xb])
	var nb: int = L.data.bands[0].size()
	for i in n:
		var t := lerpf(ta, tb, (i + 0.5) / n)
		var j := i % BAR_GROUP
		# middle pillar: low-mids (punchier than sub-bass), then higher bands towards the edges
		var band := clampi(2 + absi(j - BAR_GROUP / 2) * 2 + floori(i / float(BAR_GROUP)) % 2, 0, nb - 1)
		var x := xa + (i + 0.5) * pitch
		# close to a mechanic: calmer, and starting nearer the raised mechanic pillar so there's no big step
		# (before the song, the tutorial's stretch: silent, level with the mechanic pillars all along)
		var calm := 0.0 if t < L.tut_end else smoothstep(L.CONTACT_R, L.CONTACT_R + L.TAPER, L.dist_to_contact(t))
		var base: float = L.ground_h(t) + L.mech_lift * (1.0 - calm)
		# shared theme-gradient shader; each pillar's colour and glow are set per instance every frame
		var stem := Draw.mesh(self, L.mats.bar_stem, L.mats.pillar, Vector3(x, base, 0.0))
		var cap := Draw.mesh(self, L.mats.bar_cap, L.mats.pillar, Vector3(x, base, 0.0))
		DrawParam.param(cap, "boost", 1.8)
		var bell := 1.0 - pow(absf(j - (BAR_GROUP - 1) * 0.5) / ((BAR_GROUP - 1) * 0.5), 2.0)  # middle pillars tallest
		var amp := lerpf(0.35, 1.0, bell) * lerpf(0.25, 1.0, calm)
		bars.append({"x": x, "r": r, "base": base, "band": band, "amp": amp, "top": base, "stem": stem, "cap": cap, "calm": calm,
			"near": L.seg_at(L.nearest_contact(t)),  # the mechanic pillar this bar leads to (or comes from)
			"line": _line_of_band(band), "tint": (band % 4) * 0.025,  # neighbouring bands drift a little in hue
			"boost": L.in_boost(t)})
	return true


func _ground_mat(t: float) -> Material:
	for c in L.climax:
		if t >= c[0] and t < c[1]:
			return L.mats.glow
	var n := 0
	for p in L.phrases:
		if t >= p - 0.001:
			n += 1
	return L.mats.key_a if n % 2 == 1 else L.mats.key_b


## Extrude the key profile between ta and tb into a solid strip (top, front, back, end caps).
## It is visual only: the player stands on the level's support_at(), not on physics shapes.
func _ground_strip(ta: float, tb: float, material: Material) -> void:
	# a regular grid plus every key point, so steps stay crisp
	var ts := [ta, tb]
	var t := ta + SAMPLE_DT
	while t < tb:
		ts.append(t)
		t += SAMPLE_DT
	for k in L.key_pts:
		if k[0] > ta and k[0] < tb:
			ts.append(k[0])
	ts.sort()
	var xs := PackedFloat32Array()
	var hs := PackedFloat32Array()
	var last := -INF
	for tt in ts:
		if tt - last < 0.0005:
			continue
		last = tt
		xs.append(L.track.x_at(tt))
		hs.append(L.ground_h(clampf(tt, ta + 0.0005, tb - 0.0005)))
	if xs.size() < 2:
		return
	var bottom := ABYSS_Y  # (down to the floor: its foot never shows from a gap)
	var z := DEPTH * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in xs.size() - 1:
		var a := Vector3(xs[i], hs[i], z)
		var b := Vector3(xs[i + 1], hs[i + 1], z)
		var c := Vector3(xs[i], hs[i], -z)
		var d := Vector3(xs[i + 1], hs[i + 1], -z)
		Draw.quad(st, a, b, d, c, Vector3(-(hs[i + 1] - hs[i]), xs[i + 1] - xs[i], 0.0).normalized())
		Draw.quad(st, Vector3(xs[i], bottom, z), Vector3(xs[i + 1], bottom, z), b, a, Vector3(0, 0, 1))
		Draw.quad(st, c, d, Vector3(xs[i + 1], bottom, -z), Vector3(xs[i], bottom, -z), Vector3(0, 0, -1))
	var n := xs.size() - 1
	Draw.quad(st, Vector3(xs[0], bottom, -z), Vector3(xs[0], bottom, z), Vector3(xs[0], hs[0], z), Vector3(xs[0], hs[0], -z), Vector3(-1, 0, 0))
	Draw.quad(st, Vector3(xs[n], bottom, z), Vector3(xs[n], bottom, -z), Vector3(xs[n], hs[n], -z), Vector3(xs[n], hs[n], z), Vector3(1, 0, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	add_child(mi)
