extends Node3D
## 远处的律动波形: three rows of thin columns far behind the run, each a song's loudness skyline (like a music player's
## bars, but a still shape — that song isn't playing — that scrolls by with the parallax), each in its own level's colour
## (theme_color in tuning.csv): the jam Theme's part this level trains (its colour) nearest, the level before, the level
## after (the first and the last training level take the other end for the one they lack: level 1's level before is
## level 4, level 4's level after is level 1). The final level has no jam row: each training level's whole song stands
## behind the Theme part it trains, shown only around that part.
## Every song is laid along the whole run and repeated past both ends, each row starting at another point of its song.
## The deeper a row, the higher its tops (FAR_TOP_n), so each one shows over the one in front: a column's height is its
## song's loudness there by rank (louder: taller), and it moves with the music the player hears — scaled every frame by
## the live level of one visualizer band (low-mids in the nearest row, mids, then treble in the deepest; neighbouring
## columns take turns, so the row bulges like the run's bars), stretching on the level's kicks (claps where it has
## none). Like the run's pillars a column is lit at the top and dark below, all in its row's aerial haze (FAR_HAZE,
## deeper rows deeper in it; the haze moves brightness and saturation, never the hue): FAR_LIT down from its top its
## level's colour (held to FAR_SAT; saturation gone that far to the sky's but never under FAR_TOP_SAT; as bright as the
## sky, so against the sky only its hue shows — a hue that can't be that bright that saturated up to FAR_TOP_DIM darker
## to the eye, one in the sky's own hue up to FAR_TOP_DIM_MAX to be told from it), then within FAR_DARK_LEN as dark as the floor gone as far to the sky (a deeper row's dark is paler), its
## saturation FAR_MIN_SAT on screen already halfway down: the body carries the colour. It all turns
## with the sky. Behind the deepest row a plate is the end of the haze: at every height what a
## column of that row with its top at the row's middle height would be, so a gap is always the colour of the columns
## beside it. A phrase start and the climax lift a little of the haze off the tops. They stay backdrop: never as strong
## as anything to play.
## Data: data/levels/far_waves.json (tools/far_waves.py), each song's loudness every 1/8 s.

const WaveShader := preload("res://shaders/far_wave.gdshader")
const PlateShader := preload("res://shaders/far_plate.gdshader")
const CameraRig := preload("res://scripts/view/camera_rig.gd")
const Tuning := preload("res://scripts/core/tuning.gd")
const DATA := "res://data/levels/far_waves.json"
const TRAINS := {"intro": 1, "A": 2, "B1": 3, "B2": 4}  # the Theme's parts the training levels stand for
const BANDS := [2, 5, 8]        # each row's lowest band (it uses that one and the next two): low-mids, mids, treble
const GROUP := 5                # columns per bulge: the row's lowest band in the middle, higher ones to the sides
const SKY_GAP := 0.1            # at least this much of the screen's height between the highest tops and the MIDI layers
const SCREEN_SAT := 0.76        # the tonemap and the glow leave about this much of a body's saturation on screen (a bit
                                # less halfway down the turn, brighter there, than at the dark end)

var FAR_ON := true             # the far waves at all
var FAR_Z_NEAR := -26.0        # the nearest row's depth (metres behind the run),
var FAR_Z_STEP := -11.0        # and how much deeper each next row stands
var FAR_PITCH := 0.25          # one column per this much of its song (seconds; the loudness averaged over it)
var FAR_FILL := 0.7            # how much of its place a column fills (the rest: a gap)
var FAR_TOP_0 := "-3.0,-0.6"   # where the nearest row's tops look (the quietest, the loudest; metres above the run's
var FAR_TOP_1 := "-2.0,0.8"    # usual height), the middle row's (and the final level's rows),
var FAR_TOP_2 := "-1.0,2.2"    # and the deepest row's: higher the deeper, so every row shows over the one in front
var FAR_SKEW := 0.6            # a column's place in that range = its loudness rank to this power (below 1: most columns
                               # in the upper part, so a row's middle height stays over the peaks of the row in front)
var FAR_STILL := 0.45          # a column's height (over its row's lowest top) with its band silent; the rest comes with
                               # the band's live level
var FAR_SAT := 0.5             # a row's colour is never more saturated than this
var FAR_HAZE := "0.35,0.45,0.55"  # the aerial haze, nearest row to deepest: how far each row's colours go to the sky's
                               # (the final level's rows: the middle one)
var FAR_MIN_SAT := 0.35        # a column's body (under its lit top) at least this saturated on screen (still its level's
                               # colour)
var FAR_TOP_SAT := 0.3         # a top keeps at least this much saturation (on screen about 0.12-0.15: its hue holds
                               # through the tonemap and the sky's glow instead of turning the sky's way)
var FAR_TOP_DIM := 0.04        # a top may be this much darker than the sky (relative luminance) to keep that colour
var FAR_TOP_APART := 14.0      # a top at least this different from the sky (CIE76 of the colours as set; on screen about
                               # 0.65 of it): one in the sky's own hue takes more saturation for it,
var FAR_TOP_DIM_MAX := 0.1     # darker for it by up to this much (relative luminance)
var FAR_HUE_NUDGE := ""        # "level:shift,...": the row of that level's song turned this much in hue (apart from
                               # the rows beside it)
var FAR_LIT := 1.5             # a column keeps its colour this far down from its top (metres, as seen at the run's
var FAR_DARK_LEN := 3.0        # depth), then turns into the hazed dark over this far
var FAR_PLATE_Z := -6.0        # the plate behind the deepest row: this much further back
var FAR_LIFT := 0.02           # the tops this much brighter than the sky (0-1; the glow darkens them a little next to
                               # the dark, which can drop them a brightness step of the pixel look)
var FAR_BEAT := 0.12           # on a kick the columns stretch up by this much of their height (over the row's lowest top)
var FAR_PHRASE := 0.2          # a phrase start lifts this much of the haze off the tops for a moment,
var FAR_CLIMAX := 0.2          # the climax this much

var L
var _rows: Array = []           # {mmi, mat, span ([] or [t0, t1]: shown only then), row, middle (its middle top, seen),
                                #  tint, haze}
var _plate_mat: ShaderMaterial
var _deepest := 0               # the deepest row (the plate's)
var _hazes: Array = []          # FAR_HAZE per row
var _beats := PackedFloat64Array()
var _bands := PackedFloat32Array()


func build() -> void:
	if not FAR_ON:
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if data == null:
		push_warning("far waves: no %s (tools/far_waves.py makes it)" % DATA)
		return
	var lv := int(L.data.level)
	var y_ref := 0.0  # the run's usual height (as the MIDI background lays out its layers)
	var n := 0
	var t := 0.0
	while t < L.data.dur:
		y_ref += L.path_y(t)
		n += 1
		t += 0.25
	y_ref /= maxi(1, n)
	var tops: Array = [FAR_TOP_0, FAR_TOP_1, FAR_TOP_2].map(func(s): return Tuning.list(s).map(func(v): return float(v)))
	_hazes = Tuning.list(FAR_HAZE).map(func(v): return float(v))
	var heights := []  # each row's [lowest, middle, highest] top (as seen at the run's depth)
	if lv == 5:
		for s in data.sections:
			if TRAINS.has(s.id):
				heights.append(_build_row(data, _song(data, TRAINS[s.id]), _colour(TRAINS[s.id]), 1, tops[1], y_ref,
					[s.t, s.end_t]))
	else:
		var jam := _song(data, 5)
		for s in data.sections:
			if s.id == L.data.section:
				jam = jam.slice(int(s.t / data.dt), int(s.end_t / data.dt))
		heights.append(_build_row(data, jam, _colour(5), 0, tops[0], y_ref, []))
		var prev := lv - 1 if lv > 1 else 4
		var next := lv + 1 if lv < 4 else 1
		heights.append(_build_row(data, _song(data, prev), _colour(prev), 1, tops[1], y_ref, []))
		heights.append(_build_row(data, _song(data, next), _colour(next), 2, tops[2], y_ref, []))
		for k in range(1, heights.size()):  # a row's peaks under the middle height of the row behind
			if heights[k - 1][2] >= heights[k][1]:
				push_warning("far waves, level %d: row %d's peaks (%.2f m) reach the middle height of row %d (%.2f m)" % [
					lv, k - 1, heights[k - 1][2], k, heights[k][1]])
	_check_sky_gap(heights)
	_build_plate(y_ref)
	var hits: Array = L.song.notes("kick")
	if hits.is_empty():
		hits = L.song.notes("clap")
	for h in hits:
		_beats.append(h[0])


func _song(data: Dictionary, level: int) -> Array:
	return data.levels[str(level)].loud


## A level's theme_color from tuning.csv, held to FAR_SAT (and turned by FAR_HUE_NUDGE).
func _colour(level: int) -> Color:
	var c := Color(1.0, 1.0, 1.0)
	for r in Tuning.read(level):
		if r[0] == "theme_color":
			c = Color(r[1])
	c.s = minf(c.s, FAR_SAT)
	for n in Tuning.list(FAR_HUE_NUDGE):
		var kv: PackedStringArray = n.split(":")
		if kv.size() == 2 and int(kv[0]) == level:
			c.h = fposmod(c.h + float(kv[1]), 1.0)
	return c


## One row: a column per FAR_PITCH of the song (loudness averaged), at depth row (0 nearest), its tops in the range
## `top` ([quietest, loudest], as seen at the run's depth) by loudness rank, laid along the whole run as the parallax
## shows it there (as the MIDI background's layers: x shifted, sizes scaled with the distance), starting at its own
## point of the song and repeated past both ends so no end is ever on screen. Returns the row's [lowest, middle, highest]
## top as seen at the run's depth.
func _build_row(data: Dictionary, env: Array, colour: Color, row: int, top: Array, y_ref: float, span: Array) -> Array:
	var per := maxi(1, roundi(FAR_PITCH / data.dt))
	var cols := []
	for i in range(0, env.size(), per):
		var part: Array = env.slice(i, i + per)
		cols.append(part.reduce(func(a, b): return a + b, 0.0) / part.size())
	if cols.is_empty():
		return [0.0, 0.0, 0.0]
	var ranked := cols.duplicate()
	ranked.sort()
	var lo: float = top[0]
	var hi: float = top[1]
	var seen := []  # each column's top as seen at the run's depth
	for c in cols:
		var r := ranked.bsearch(c) / maxf(1.0, cols.size() - 1.0)
		seen.append(lo + (hi - lo) * pow(r, FAR_SKEW))
	var z := FAR_Z_NEAR + FAR_Z_STEP * row
	var dist: float = CameraRig.CAM_Z - z
	var scale := dist / CameraRig.CAM_Z
	var eye := y_ref + CameraRig.CAM_UP - (CameraRig.CAM_UP - CameraRig.LOOK_UP) / CameraRig.CAM_Z * dist
	var shift: float = CameraRig.AHEAD - CameraRig.AHEAD / CameraRig.CAM_Z * dist
	var x0: float = L.track.x_at(L.t_start)
	var x1: float = L.track.x_at(L.t_end)
	var step: float = (x1 - x0) / (L.t_end - L.t_start) * FAR_PITCH  # the run's average speed, a column per FAR_PITCH
	var margin: float = tan(deg_to_rad(CameraRig.FOV * 0.5)) * dist * 2.0 + 10.0  # wider than half the screen there
	var count := int((x1 - x0 + 2.0 * margin) / step) + 1
	var bottom: float = L.pillars.ABYSS_Y
	var w := step * FAR_FILL
	var start := roundi(cols.size() * fposmod(_rows.size() * 0.38, 1.0))  # (each row from its own point of its song)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = count
	for i in count:
		var y: float = maxf(eye + (seen[(i + start) % cols.size()] - CameraRig.LOOK_UP) * scale, bottom + 0.5)
		var basis := Basis.from_scale(Vector3(w, y - bottom, w))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x0 - margin + shift + i * step, (y + bottom) * 0.5, z)))
		mm.set_instance_custom_data(i, Color(BANDS[row] + absi(i % GROUP - GROUP / 2), 0.0, 0.0, 0.0))
	var mat := ShaderMaterial.new()
	mat.shader = WaveShader
	mat.set_shader_parameter("lit", FAR_LIT * scale)
	mat.set_shader_parameter("dark_len", FAR_DARK_LEN * scale)
	mat.set_shader_parameter("foot", eye + (lo - CameraRig.LOOK_UP) * scale)
	mat.set_shader_parameter("still", FAR_STILL)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	var mid: Array = seen.duplicate()
	mid.sort()
	_rows.append({"mmi": mmi, "mat": mat, "span": span, "row": row, "middle": mid[mid.size() / 2], "tint": colour,
		"haze": _haze(row)})
	return [lo, mid[mid.size() / 2], mid[-1]]


func _haze(row: int) -> float:
	return clampf(_hazes[mini(row, _hazes.size() - 1)], 0.0, 1.0) if not _hazes.is_empty() else 0.0


## A column's top in the haze: the row's hue (the haze never turns it), its saturation gone `amount` of the way to the
## sky's but never under FAR_TOP_SAT, as bright as the sky (plus FAR_LIFT: on the sky's brightness step, so it is told
## from the sky by its hue only). A hue that can't be that bright at that saturation (blues, purples, pinks: their
## brightest is darker) stays at its brightest and gives up saturation until its luminance is within FAR_TOP_DIM of the
## sky's — as the eye weighs it, so blues and purples, darker to the eye than the pixel look's brightness says, keep
## less — but it never gives up more than it takes to be on the sky's brightness step. A top in the sky's own hue (the
## first level's orange under the warm sky, the fourth's blue under the cool one) would be the sky again: it takes more
## saturation, at its brightest so darker for it, until it is FAR_TOP_APART from the sky's colour, by up to
## FAR_TOP_DIM_MAX darker.
func _top_colour(tint: Color, amount: float, sky: Color) -> Color:
	var s := maxf(lerpf(tint.s, sky.s, amount), FAR_TOP_SAT)
	var y := _brightness(sky) + FAR_LIFT
	if _brightness(Color.from_hsv(tint.h, s, 1.0)) < y:  # (its brightest at that saturation)
		var low := _luminance(sky) - FAR_TOP_DIM
		var a := maxf(0.0, (1.0 - y) / maxf(1.0 - _brightness(Color.from_hsv(tint.h, 1.0, 1.0)), 0.01))  # (on the step)
		if _luminance(Color.from_hsv(tint.h, a, 1.0)) < low:
			s = a
		elif _luminance(Color.from_hsv(tint.h, s, 1.0)) < low:
			var b := s
			for i in 8:  # (the most saturated still that bright: the more saturated, the darker)
				var m := (a + b) * 0.5
				if _luminance(Color.from_hsv(tint.h, m, 1.0)) >= low:
					a = m
				else:
					b = m
			s = a
	if _apart(_bright_as(tint.h, s, y), sky) < FAR_TOP_APART:
		var floor_far := _luminance(sky) - FAR_TOP_DIM_MAX
		var a := s
		var b := 1.0
		for i in 10:  # (as far apart as it needs, as dark as it may: the more saturated, the darker and further apart)
			var m := (a + b) * 0.5
			var c := _bright_as(tint.h, m, y)
			if _luminance(c) >= floor_far and _apart(c, sky) <= FAR_TOP_APART:
				a = m
			else:
				b = m
		s = a
	return _bright_as(tint.h, s, y)


## That hue at that saturation as bright as y (the pixel look's brightness), or at its brightest if it can't be.
func _bright_as(h: float, s: float, y: float) -> Color:
	return Color.from_hsv(h, s, minf(1.0, y / maxf(_brightness(Color.from_hsv(h, s, 1.0)), 0.001)))


## A column's dark part in the haze: as dark as the floor gone `amount` of the way to the sky, in the row's hue, as
## saturated as lands FAR_MIN_SAT on screen — as bright whatever the hue (rows of other colours at the same depth equally
## dark: no slits).
func _dark_colour(tint: Color, amount: float, sky: Color, abyss: Color) -> Color:
	var s := minf(1.0, FAR_MIN_SAT / SCREEN_SAT)
	var y := _brightness(abyss.lerp(sky, amount))
	return Color.from_hsv(tint.h, s, minf(1.0, y / _brightness(Color.from_hsv(tint.h, s, 1.0))))


## Brightness as the pixel look steps it (YCoCg Y of the colour on screen).
func _brightness(c: Color) -> float:
	return 0.25 * c.r + 0.5 * c.g + 0.25 * c.b


## Relative luminance (the colour's brightness as the eye weighs it).
func _luminance(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


## How different two colours look (CIE76: their distance in CIELAB, D65 white).
func _apart(a: Color, b: Color) -> float:
	return _lab(a).distance_to(_lab(b))


func _lab(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	var x := _lab_f((0.4124 * l.r + 0.3576 * l.g + 0.1805 * l.b) / 0.95047)
	var y := _lab_f(0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b)
	var z := _lab_f((0.0193 * l.r + 0.1192 * l.g + 0.9505 * l.b) / 1.08883)
	return Vector3(116.0 * y - 16.0, 500.0 * (x - y), 200.0 * (y - z))


func _lab_f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else t / 0.128418 + 4.0 / 29.0


## The plate behind the deepest row, along the whole run: the end of the haze — what a column of that row with its top
## at the row's middle height would be at every height (its colours set in update), seen at the plate's depth.
func _build_plate(y_ref: float) -> void:
	if _rows.is_empty():
		return
	_deepest = _rows.map(func(r): return r.row).max()
	var middle: float = _rows.filter(func(r): return r.row == _deepest).map(func(r): return r.middle).max()
	var z := FAR_Z_NEAR + FAR_Z_STEP * _deepest + FAR_PLATE_Z
	var dist: float = CameraRig.CAM_Z - z
	var scale := dist / CameraRig.CAM_Z
	var eye := y_ref + CameraRig.CAM_UP - (CameraRig.CAM_UP - CameraRig.LOOK_UP) / CameraRig.CAM_Z * dist
	var shift: float = CameraRig.AHEAD - CameraRig.AHEAD / CameraRig.CAM_Z * dist
	var margin: float = tan(deg_to_rad(CameraRig.FOV * 0.5)) * dist * 2.0 + 10.0
	var x0: float = L.track.x_at(L.t_start) - margin + shift
	var x1: float = L.track.x_at(L.t_end) + margin + shift
	var top := eye + (middle - CameraRig.LOOK_UP) * scale
	var bottom: float = L.pillars.ABYSS_Y
	var quad := QuadMesh.new()
	quad.size = Vector2(x1 - x0, top + 1.0 - bottom)
	_plate_mat = ShaderMaterial.new()
	_plate_mat.shader = PlateShader
	_plate_mat.set_shader_parameter("top", top)
	_plate_mat.set_shader_parameter("lit", FAR_LIT * scale)
	_plate_mat.set_shader_parameter("dark_len", FAR_DARK_LEN * scale)
	var plate := MeshInstance3D.new()
	plate.mesh = quad
	plate.material_override = _plate_mat
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.position = Vector3((x0 + x1) * 0.5, (top + 1.0 + bottom) * 0.5, z)
	add_child(plate)


## The MIDI layers stay SKY_GAP of the screen clear of the highest tops (with the kick's stretch), the camera at its
## usual height.
func _check_sky_gap(heights: Array) -> void:
	var peak := -INF
	for hs in heights:
		peak = maxf(peak, hs[2] + FAR_BEAT * (hs[2] - hs[0]))
	var half_h := tan(deg_to_rad(CameraRig.FOV * 0.5)) * CameraRig.CAM_Z  # half the screen's height at the run's depth
	var peak_v := (peak - CameraRig.LOOK_UP) / half_h  # (-1 bottom .. 1 top, as the MIDI layers' v)
	var low_v: float = L.background.lowest_v()
	if low_v - peak_v < 2.0 * SKY_GAP:
		push_warning("far waves, level %d: the highest tops (v %.2f) come within %.2f of the screen's height of the MIDI layers (v %.2f)" % [
			int(L.data.level), peak_v, (low_v - peak_v) * 0.5, low_v])


## Each frame: the visualizer bands' live levels, the kick's stretch, each row's colours in the haze of this sky (a
## phrase start and the climax lifting some of it off the tops) and the plate's (the deepest rows shown, as much as each
## shows); the final level's rows fade in a bar before their part and out a bar after it, into the plate.
func update() -> void:
	if _rows.is_empty():
		return
	var now: float = L.now
	_bands.resize(12)
	for k in mini(12, L.data.bands[0].size()):
		_bands[k] = L.band_at(now, k)
	var i := _beats.bsearch(now, false) - 1
	var beat := FAR_BEAT * exp(-(now - _beats[i]) * 8.0) if i >= 0 and now - _beats[i] < 1.0 else 0.0
	var clear := 0.0
	for p in L.phrases:
		if now >= p and now - p < 1.0:
			clear = maxf(clear, FAR_PHRASE * exp(-(now - p) * 4.0))
	for c in L.climax:
		clear = maxf(clear, FAR_CLIMAX * smoothstep(c[0] - 0.3, c[0], now) * (1.0 - smoothstep(c[1], c[1] + 0.8, now)))
	var bar: float = L.data.bar_sec
	var sky: Color = L.cam_rig.env.background_color
	var abyss: Color = L.mats.abyss.albedo_color
	var shown := []
	var plate_top := Color(0.0, 0.0, 0.0, 0.0)
	var plate_low := Color(0.0, 0.0, 0.0, 0.0)
	for r in _rows:
		var vis := 1.0
		if not r.span.is_empty():
			vis = smoothstep(r.span[0] - bar, r.span[0], now) * (1.0 - smoothstep(r.span[1], r.span[1] + bar, now))
			r.mmi.visible = vis > 0.0
			if vis <= 0.0:
				continue
		var top := _top_colour(r.tint, maxf(0.0, r.haze - clear), sky)
		var low := _dark_colour(r.tint, r.haze, sky, abyss)
		if r.row == _deepest:
			plate_top += Color(top.r, top.g, top.b, 1.0) * vis
			plate_low += Color(low.r, low.g, low.b, 1.0) * vis
		shown.append([r, vis, top, low])
	var neutral := abyss.lerp(sky, _haze(_deepest))
	if plate_low.a > 0.0:
		plate_top /= plate_top.a
		plate_low /= plate_low.a
	else:
		plate_top = sky
		plate_low = neutral
	if _plate_mat != null:
		_plate_mat.set_shader_parameter("top_col", Color(plate_top, 1.0))
		_plate_mat.set_shader_parameter("low_col", Color(plate_low, 1.0))
	for s in shown:
		var r: Dictionary = s[0]
		r.mat.set_shader_parameter("sky", sky)
		r.mat.set_shader_parameter("top_col", s[2])
		r.mat.set_shader_parameter("low_col", s[3])
		r.mat.set_shader_parameter("back_low", plate_low)
		r.mat.set_shader_parameter("bands", _bands)
		r.mat.set_shader_parameter("beat", beat)
		r.mat.set_shader_parameter("vis", s[1])
