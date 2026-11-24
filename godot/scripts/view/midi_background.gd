extends Node3D
## The background: every note of the song's MIDI (data/levels/levelN_midi.json, made by tools/midi_notes.py from the
## transcription) as a small shape, one kind per track, in layers behind the run like a parallax backdrop.
## The player is the playhead: each note lies where it passes the player on screen at the moment it sounds, and
## flashes and swells as it plays. Nearer layers (the melody) scroll faster than far ones (the bass), and deeper
## layers fade into the sky — and, further back still (BG_FAR), into an aerial haze (paler, greyer: haze_at) — so the
## backdrop never competes with the run. They sit high in the sky (BG_LIFT, BG_SPAN),
## clear above the far rhythm waves. One MultiMesh per track.

const NoteShader := preload("res://shaders/midi_note.gdshader")
const CameraRig := preload("res://scripts/view/camera_rig.gd")

# each track's shape and layer: z = depth (metres behind the run), v = where on screen its lowest and highest notes
# sit (-1 bottom .. 1 top; the top of the screen stays clear for the HUD), size = how big it looks (metres, as if it
# stood on the run), hue = shift from the theme (kept near it: the opposite hue is for what the player deals with).
# Drums keep glowing a little longer after their hit.
const LAYERS := [
	{"track": "lead", "shape": "ring", "z": -7.0, "v": [0.3, 0.6], "size": 0.55, "hue": 0.0, "spin": 0.0, "wobble": 0.45},
	{"track": "arp", "shape": "ball", "z": -13.0, "v": [0.1, 0.46], "size": 0.36, "hue": 0.06, "spin": 0.0, "wobble": 0.0},
	{"track": "hat", "shape": "cube", "z": -19.0, "v": [0.58, 0.58], "size": 0.34, "hue": 0.15, "spin": 2.4, "wobble": 0.6},
	{"track": "clap", "shape": "tetra", "z": -19.0, "v": [0.47, 0.47], "size": 0.55, "hue": -0.12, "spin": 1.5, "wobble": 0.4},
	{"track": "kick", "shape": "octa", "z": -19.0, "v": [0.36, 0.36], "size": 0.8, "hue": 0.08, "spin": 0.7, "wobble": 0.25},
	{"track": "bass", "shape": "pill", "z": -30.0, "v": [-0.06, 0.16], "size": 0.6, "hue": -0.06, "spin": 0.0, "wobble": 0.0},
]

var BG_ON := true              # the MIDI background at all
var BG_FADE := 0.8             # how far the deepest layer fades into the sky (0: not at all, 1: gone)
var BG_SIZE := 1.0             # every shape bigger / smaller
var BG_FLASH := 1.0            # how strongly a note shows as it sounds (deeper, fuller colour, bigger)
var BG_CLIMAX := 0.8           # 6d climax: how much clearer and livelier every layer gets
var BG_PHRASE := 0.6           # 5a: how hard every layer pulses at the start of each phrase
var BG_HIT_SAT := 0.6          # how saturated a sounding note gets (kept below the mechanics' accent colour)
var BG_DENSE := 2.0            # a layer with more notes per second than this fades further into the sky,
var BG_DENSE_FADE := 0.15      # by this much per extra note per second,
var BG_DENSE_MAX := 0.5        # but no more than this
var BG_FAR := 1.5              # every layer this many times further back than its z (the parallax slower, sizes kept)
var BG_LIFT := 0.6             # every layer's v moved up by this much (screen: -1 bottom .. 1 top) ...
var BG_SPAN := 0.45            # ... after its v is scaled by this (1: spread as laid out; less: packed higher in the sky)
var BG_HAZE := 0.3             # aerial haze: how far the deepest things fade into the sky and lose colour (haze_at)

const HAZE_NEAR := 20.0         # no haze this close to the camera (metres), full BG_HAZE this far
const HAZE_FAR := 60.0

var L
var _mats: Array = []
var _lowest := INF              # the lowest bottom of any layer's shapes on screen (v)
var _sections: Array = []       # [t, brightness step] from 6a (louder) / 6b (softer)


func build() -> void:
	if not BG_ON:
		return
	# the camera follows the player up and down; lay the layers out around its usual height
	var y_ref := 0.0
	var n := 0
	var t := 0.0
	while t < L.data.dur:
		y_ref += L.path_y(t)
		n += 1
		t += 0.25
	y_ref /= maxi(1, n)
	for e in L.data.events:
		if e.branch == "6a" or e.branch == "6b":
			_sections.append([e.t, 1.0 if e.branch == "6a" else -1.0])
	_sections.sort_custom(func(a, b): return a[0] < b[0])
	for layer in LAYERS:
		var notes: Array = L.song.notes(layer.track)
		if not notes.is_empty():
			_build_layer(layer, notes, y_ref)


## How far something this far from the camera (metres) is hazed: mixed into the sky and robbed of colour (0..BG_HAZE).
func haze_at(dist: float) -> float:
	return BG_HAZE * clampf((dist - HAZE_NEAR) / (HAZE_FAR - HAZE_NEAR), 0.0, 1.0)


## The lowest bottom of the layers' shapes on screen (v: -1 bottom .. 1 top; INF: no layers).
func lowest_v() -> float:
	return _lowest


func _build_layer(layer: Dictionary, notes: Array, y_ref: float) -> void:
	var lo := INF
	var hi := -INF
	for nt in notes:
		lo = minf(lo, nt[2])
		hi = maxf(hi, nt[2])
	var z: float = layer.z * BG_FAR
	var dist: float = CameraRig.CAM_Z - z
	var vs: Array = layer.v.map(func(v): return BG_LIFT + v * BG_SPAN)
	var h := haze_at(dist)
	var half_h := tan(deg_to_rad(CameraRig.FOV * 0.5)) * dist
	var eye := y_ref + CameraRig.CAM_UP - (CameraRig.CAM_UP - CameraRig.LOOK_UP) / CameraRig.CAM_Z * dist  # view centre here
	var shift: float = CameraRig.AHEAD - CameraRig.AHEAD / CameraRig.CAM_Z * dist  # on screen, the player's x at this depth
	var unit: float = layer.size * BG_SIZE * dist / CameraRig.CAM_Z
	# (its biggest shape, swollen on a hit, as a share of the screen's half height)
	_lowest = minf(_lowest, vs[0] - 0.5 * layer.size * BG_SIZE * 1.15 * 1.3 / (half_h / dist * CameraRig.CAM_Z))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _shape(layer.shape)
	mm.instance_count = notes.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(layer.track)
	for i in notes.size():
		var nt: Array = notes[i]
		var t0: float = nt[0]
		var t1: float = t0 + nt[1]
		var vel: float = nt[3] / 127.0
		var v: float = lerpf(vs[0], vs[1], (nt[2] - lo) / (hi - lo)) if hi > lo else vs[0]
		var size := unit * lerpf(0.75, 1.15, vel)
		var x: float = L.track.x_at(t0) + shift
		var basis := Basis.from_scale(Vector3.ONE * size)
		match layer.shape:
			"ring":  # facing the camera
				basis = Basis(Vector3.RIGHT, PI * 0.5) * basis
			"pill":  # a piano-roll bar along the run, as long as the note
				var length: float = maxf(L.track.x_at(t1) - L.track.x_at(t0), size)
				x += length * 0.5
				basis = Basis(Vector3.BACK, PI * 0.5) * Basis.from_scale(Vector3(size, length * 0.5, size))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, eye + v * half_h, z)))
		var c: Color = L.note_color(nt[2])
		c.h = fposmod(c.h + layer.hue, 1.0)
		c.s *= 1.0 - h
		mm.set_instance_color(i, c)
		mm.set_instance_custom_data(i, Color(t0, t1, rng.randf(), vel))
	var mat := ShaderMaterial.new()
	mat.shader = NoteShader
	var busy: float = clampf((notes.size() / L.data.dur - BG_DENSE) * BG_DENSE_FADE, 0.0, BG_DENSE_MAX)
	# (the fade with depth as laid out, from the layer's own z; moved further back it fades on into the haze)
	var fade := minf(1.0, BG_FADE * clampf((CameraRig.CAM_Z - layer.z - 18.0) / 27.0, 0.2, 1.0) + busy)
	mat.set_shader_parameter("fade", fade + (1.0 - fade) * h)
	mat.set_shader_parameter("hit_sat", BG_HIT_SAT * (1.0 - h))
	mat.set_shader_parameter("spin", layer.spin)
	mat.set_shader_parameter("wobble", layer.wobble)
	mat.set_shader_parameter("flash", BG_FLASH)
	var drum: bool = layer.track in ["kick", "clap", "hat"]
	mat.set_shader_parameter("swell", 0.15 if layer.shape == "pill" else (0.25 if drum else 0.45))
	mat.set_shader_parameter("decay", 8.0 if drum else 6.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_mats.append(mat)


## Each frame: the song clock, the sky colour (5-5 warm / cool) and the song's big moments for every layer:
## the climax (6d) makes them clearer and livelier, louder / softer sections (6a / 6b) a step brighter / dimmer,
## and every phrase start (5a) is a pulse through all of them.
func update() -> void:
	var now: float = L.now
	var climax := 0.0
	for c in L.climax:
		climax = maxf(climax, smoothstep(c[0] - 0.3, c[0], now) * (1.0 - smoothstep(c[1], c[1] + 0.8, now)))
	var level := 0.0
	for s in _sections:
		if now >= s[0]:
			level += s[1]
	var pulse := 0.0
	for p in L.phrases:
		if now >= p and now - p < 1.0:
			pulse = exp(-(now - p) * 4.0)
	for m in _mats:
		m.set_shader_parameter("now", now)
		m.set_shader_parameter("sky", L.cam_rig.env.background_color)
		m.set_shader_parameter("energy", clampf(BG_CLIMAX * climax + 0.15 * level, -0.3, 1.0))
		m.set_shader_parameter("pulse", BG_PHRASE * pulse)


func _shape(kind: String) -> Mesh:
	match kind:
		"ring":
			var m := TorusMesh.new()
			m.inner_radius = 0.34
			m.outer_radius = 0.5
			m.rings = 24
			m.ring_segments = 8
			return m
		"ball":
			var m := SphereMesh.new()
			m.radius = 0.5
			m.height = 1.0
			m.radial_segments = 10
			m.rings = 6
			return m
		"cube":
			var m := BoxMesh.new()
			m.size = Vector3.ONE * 0.8
			return m
		"pill":
			var m := CapsuleMesh.new()
			m.radius = 0.5
			m.height = 2.0
			m.radial_segments = 12
			m.rings = 4
			return m
		"tetra":
			return _solid([Vector3(0, 0.6, 0), Vector3(-0.55, -0.35, 0.32), Vector3(0.55, -0.35, 0.32), Vector3(0, -0.35, -0.64)],
				[[0, 1, 2], [0, 2, 3], [0, 3, 1], [1, 3, 2]])
		_:  # octahedron
			return _solid([Vector3(0, 0.6, 0), Vector3(0, -0.6, 0), Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0), Vector3(0, 0, 0.5), Vector3(0, 0, -0.5)],
				[[0, 4, 2], [0, 2, 5], [0, 5, 3], [0, 3, 4], [1, 2, 4], [1, 5, 2], [1, 3, 5], [1, 4, 3]])


## A flat-shaded solid from its corners and triangles (normals point away from its centre).
func _solid(pts: Array, faces: Array) -> ArrayMesh:
	var centre := Vector3.ZERO
	for p in pts:
		centre += p / pts.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a: Vector3 = pts[f[0]]
		var b: Vector3 = pts[f[1]]
		var c: Vector3 = pts[f[2]]
		var nrm := (b - a).cross(c - a).normalized()
		if nrm.dot((a + b + c) / 3.0 - centre) < 0.0:
			nrm = -nrm
		for p in [a, b, c]:
			st.set_normal(nrm)
			st.add_vertex(p)
	return st.commit()
