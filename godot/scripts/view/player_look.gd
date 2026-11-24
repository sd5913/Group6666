extends Node3D
const DrawParam := preload("res://scripts/view/draw.gd")
## How the player looks: a soft rounded block of jelly (the run's square language) that squashes and wobbles, always
## pivoting on its feet — a quick squash then stretch on take-off, slowly back into shape in the air, a squash and two or
## three settling wobbles on landing (harder after a slam), a lean on a dash, a dip when it starts a slide. Upside down
## (mirror flip) it all turns over with the player. Its colour follows the block under it, mixed with the level's theme
## and kept pale, with a darker rim and outline so it never melts into the pale sky.
## With LOOK_VOXEL the jelly stays as smooth as ever, but voxels like the walls' and pillars'
## (scripts/view/voxel_column.gd, VOX big, in its colour) show in what happens to it. Bits chip off it: off its feet
## landing hard (a slam's more and harder), dropping as it takes off, behind it on a dash, off its front when it runs
## into something — never more than LOOK_CHIPS_MAX at once. Failing, the jelly turns at once into the 4 × 8 × 4 voxels
## of its volume and they burst (shatter); on the level coming back (carrying on, or again), they hang in a tumbling
## cluster above where it stands, then drop together into it, and the smooth jelly takes their place. At both turns
## the voxels stand where the jelly's surface was (its squash, crouch and lean), in its colour, without a flash; every
## voxel (and chip) is a little lighter or darker than its neighbours (VOX_GRAIN).
## Only the look: the player's hit box (player.gd RADIUS / HEIGHT / HALF) never changes shape.
## Its settings are the player's JELLY_* / LOOK_* (player.X rows in config/tuning.csv).

const BodyShader := preload("res://shaders/jelly.gdshader")
const OutlineShader := preload("res://shaders/jelly_outline.gdshader")
const VoxelShader := preload("res://shaders/jaw_voxel.gdshader")
const VoxelColumn := preload("res://scripts/view/voxel_column.gd")

const VOX := 0.175              # a voxel's edge (metres): 4 across, 8 up, 4 deep, the hit box's size
const NX := 4
const NY := 8
const NZ := 4
const CHIP_LIFE := 0.6          # chips, and the voxels of a burst body, shrink away after about this long (seconds)
const BURST_LIFE := 0.8
const REBUILD_T := 0.3          # the voxels fly back together this fast (seconds),
const REBUILD_HOLD := 0.1       # after hanging this long in a cluster
const REBUILD_UP := 1.5         # this far above the body (metres), about REBUILD_SPREAD out from its middle:
const REBUILD_SPREAD := 0.6
const REBUILD_FROM := 0.35      # (where a soft burst floating upwards has them this long after it, played backwards)
const VOX_GRAIN := 0.15         # each voxel (and chip) this much lighter or darker than the colour, at most
const VOX_LIT := 0.7            # how bright the body's voxels are lit, against the shader's flash of 0.6 (measured on
                                # screen, next to the jelly: with this a fresh break comes out as bright as the whole box)
const BOB_HZ := 1.8             # breathing while touching the ground; the feet stay planted
const BOB_AMOUNT := 0.045
const TAKEOFF_WOBBLE_T := 0.52
const TAKEOFF_SQUASH := 0.12
const AIR_STRETCH := 0.34
const LAND_SQUASH_T := 0.22
const LAND_SQUASH := 0.22
const DISPLAY_SQUASH_MIN := -0.34
const DISPLAY_STRETCH_MAX := 0.48
const STREAK_LIFE := 0.28       # take-off / landing streaks, in seconds

static var _last_burst := {}     # the last time the body burst: {msec} — it flies back together when it comes back

var P                           # the player (scripts/player.gd)
var tint_source: Callable       # (x) -> colour of the block under x (alpha 0 over a gap)
var sound: Callable             # (name, power): play a sound (the level's sfx)
var theme := Color(1.0, 0.5, 0.12)
var slime_color := Color("#ed5897")
var _body: ShaderMaterial
var _line: ShaderMaterial
var _s := 0.0                   # squash (-) / stretch (+), and how fast it is changing
var _sv := 0.0
var _display_s := 0.0           # spring, grounded breathing, and short jump/landing poses
var _bob_clock := 0.0
var _bob_weight := 0.0
var _jump_age := INF
var _landing_age := INF
var _landing_strength := 0.0
var _l := 0.0                   # how far the top leans along the run (metres), and how fast it is changing
var _lv := 0.0
var _was_grounded := true
var _last_vy := 0.0
var _last_dash_age := INF
var _was_crouching := false
var _was_reaching := false
var _color := Color.WHITE
var _tint_color := Color.WHITE
var reach := 0.0                # stretch up this far (metres) this step, holding on to something overhead
var lean_to := 0.0              # lean the top this far forwards (metres) this step (riding a glide)
var _ready_color := false
var _up := 1.0                  # which way up the player was last step,
var _turn_from := 0.0           # and the turn it is making since gravity last turned round (about z, towards the camera)
var _turn_to := 0.0
var _turn_age := INF
# the voxels (LOOK_VOXEL)
var _vox: MultiMeshInstance3D
var _body_mm: MultiMesh         # the body's voxels (its own: nothing of it outlives the level)
var _vox_mat: ShaderMaterial
var _chip_mat: ShaderMaterial
var _chips: Array = []          # {mmi, age, n}
var _streaks: Array = []        # brief ground streaks at take-off and landing
var _chip_count := 0
var _burst_age := -1.0          # since the body burst (< 0: whole)
var _rebuild := -1.0            # flying back together: time left (< 0: whole)
var _burst_color := Color.WHITE  # the jelly's colour as it burst
var _burst_basis := Basis()      # and its shape (squash, crouch, lean) then
var _fx := false                # LOOK_VOXEL: the voxel effects
var _mesh: MeshInstance3D       # the smooth jelly
var _last_x := 0.0
var _vx := 0.0


func setup(player: Node3D) -> void:
	P = player
	var mi := MeshInstance3D.new()
	mi.mesh = _rounded_box(Vector3(2.0 * P.RADIUS + 0.02, P.HEIGHT, 2.0 * P.RADIUS + 0.02), 0.17, 12)
	_body = ShaderMaterial.new()
	_body.shader = BodyShader
	_line = ShaderMaterial.new()
	_line.shader = OutlineShader
	_body.next_pass = _line
	for m in [_body, _line]:
		m.set_shader_parameter("feet", -P.HALF)
		m.set_shader_parameter("tall", P.HEIGHT)
	mi.material_override = _body
	add_child(mi)
	_mesh = mi
	_fx = P.LOOK_VOXEL != 0
	if _fx:
		_setup_voxels()


## Knocked (run into a wall, hit by a fired wall): squash by `squash`, and the top lurches on along the run by `lean`
## (negative: back), both as parts of a jump's / a dash's. A hard knock chips its front.
func bump(squash: float, lean: float) -> void:
	var w: float = TAU * P.JELLY_HZ
	_sv -= P.JELLY_JUMP * w * squash
	_lv += P.JELLY_LEAN * w * lean
	if _fx and squash >= 0.8:
		var n := 4 + randi() % 3
		_chips_at(n, func(_i): return Vector3(0.35 + VOX * 0.5, randf_range(0.3, 1.2), randf_range(-0.26, 0.26)),
			Vector3(0.0, 0.7, 0.0), 3.0, Vector3(-2.5, 1.0, 0.0))


## World height of the top of the body as drawn right now: the head (player.head_y()), raised while the jelly is
## stretched.
func top_y() -> float:
	return P.head_y() + P.height * maxf(0.0, _display_s) * P.up


## Each physics step, after the player has moved.
func update(delta: float) -> void:
	var w: float = TAU * P.JELLY_HZ
	var vy: float = P.vy
	_vx = (P.position.x - _last_x) / maxf(delta, 0.001)
	_last_x = P.position.x
	if P.grounded and not _was_grounded:  # landed: squash by how hard, then settle in a few wobbles
		_jump_age = INF
		var impact := maxf(0.0, -_last_vy)
		_landing_age = 0.0
		_landing_strength = clampf(impact / 9.0, 0.35, 1.0)
		_sv -= minf(P.JELLY_MAX, impact * P.JELLY_LAND * 1.55) * w
		_lv += P.JELLY_LEAN * w * 0.65 * clampf(impact / 9.0, 0.0, 1.0)
		_landing_chips(impact)
		_ground_streaks(clampf(impact / 12.0, 0.35, 1.0))
	elif _was_grounded and not P.grounded and vy > 0.5:  # took off: a quick squash, then stretched upwards
		_jump_age = 0.0
		_landing_age = INF
		var k := minf(1.0, vy / 9.0)
		_s = -P.JELLY_JUMP * 0.8 * k
		_sv += P.JELLY_JUMP * w * 1.75 * k
		_lv -= P.JELLY_LEAN * w * 0.55 * k
		_ground_streaks(0.7 + 0.2 * k)
		if _fx:  # (a few bits left behind, dropping where it stood)
			_chips_at(2 + randi() % 3, func(_i): return Vector3(randf_range(-0.3, 0.3), VOX * 0.5, randf_range(-0.26, 0.26)),
				Vector3(0.0, 1.0, 0.0), 0.3, Vector3.ZERO)
	if P.crouching() and not _was_crouching:
		_sv -= P.JELLY_JUMP * w
	if P._dash_age < _last_dash_age:  # dashed: the body shoots ahead, the top lags behind
		_lv -= P.JELLY_LEAN * w
		if _fx:  # (two bits off its back)
			_chips_at(2, func(_i): return Vector3(-0.35 - VOX * 0.5, randf_range(0.4, 1.0), randf_range(-0.2, 0.2)),
				Vector3(0.0, 0.7, 0.0), 0.8, Vector3(-1.5, 0.5, 0.0))
	_last_dash_age = P._dash_age
	# grounded it wobbles; in the air it eases back into shape without wobbling
	var zeta: float = P.JELLY_DAMP if P.grounded else 0.6
	var rest: float = reach / P.HEIGHT
	if rest == 0.0 and _was_reaching:  # let go: spring back with a wobble
		_sv -= P.JELLY_JUMP * w * 0.8
	_was_reaching = rest > 0.0
	reach = 0.0
	_sv += (-w * w * (_s - rest) - 2.0 * zeta * w * _sv) * delta
	_s = clampf(_s + _sv * delta, -P.JELLY_MAX, P.JELLY_MAX)
	_bob_clock += delta
	_bob_weight = move_toward(_bob_weight, 1.0 if P.grounded and not P.crouching() else 0.0, delta * 6.0)
	var takeoff := 0.0
	if _jump_age < TAKEOFF_WOBBLE_T:
		_jump_age += delta
		takeoff = -TAKEOFF_SQUASH * (1.0 - smoothstep(0.01, 0.10, _jump_age))
		takeoff += AIR_STRETCH * smoothstep(0.05, 0.16, _jump_age) * (1.0 - smoothstep(0.30, TAKEOFF_WOBBLE_T, _jump_age))
	var landing := 0.0
	if _landing_age < LAND_SQUASH_T:
		_landing_age += delta
		landing = -LAND_SQUASH * _landing_strength * (1.0 - smoothstep(0.03, LAND_SQUASH_T, _landing_age))
	_display_s = clampf(_s + BOB_AMOUNT * sin(_bob_clock * TAU * BOB_HZ) * _bob_weight + takeoff + landing,
		DISPLAY_SQUASH_MIN, DISPLAY_STRETCH_MAX)
	_lv += (-w * w * (_l - lean_to) - 2.0 * P.JELLY_DAMP * w * _lv) * delta
	_l += _lv * delta
	lean_to = 0.0
	_was_grounded = P.grounded
	_was_crouching = P.crouching()
	_last_vy = vy
	# a mirror flip turns the block over end over end, rolling forwards, until its feet (the pivot) face the other row
	if P.up != _up:
		_up = P.up
		_turn_from = rotation.z
		_turn_to -= PI
		_turn_age = 0.0
	_turn_age += delta
	rotation.z = lerpf(_turn_from, _turn_to, smoothstep(0.0, 1.0, _turn_age / maxf(0.01, P.LOOK_FLIP_T)))
	for m in [_body, _line]:
		m.set_shader_parameter("squash", _display_s)
		m.set_shader_parameter("lean", _l)
		m.set_shader_parameter("crouch", P.height / P.HEIGHT)
	_update_color(delta)


## The colour slides towards the block underneath (mixed with the theme, kept pale); over a gap it keeps what it had
## and drifts back to the theme.
func _update_color(delta: float) -> void:
	var under: Color = tint_source.call(P.position.x) if tint_source.is_valid() else Color(0, 0, 0, 0)
	var target := _pale(theme)
	var k := 1.0 - exp(-delta / 1.0)
	if under.a > 0.0:
		target = _apart(_pale(under.lerp(theme, P.LOOK_THEME)), under)
		k = 1.0 - exp(-delta / maxf(0.01, P.LOOK_TINT_T))
	if not _ready_color:
		_tint_color = target
		_ready_color = true
	_tint_color = _tint_color.lerp(target, k)
	var idle := _apart(_pale(theme), theme)
	_color = Color.from_hsv(slime_color.h,
		clampf(slime_color.s * _tint_color.s / maxf(0.01, idle.s), 0.0, 1.0),
		clampf(slime_color.v * _tint_color.v / maxf(0.01, idle.v), 0.0, 1.0))
	_body.set_shader_parameter("body", _color)
	_line.set_shader_parameter("line", Color.from_hsv(_color.h, minf(1.0, _color.s * 1.6 + 0.2), 0.32))


## c, made at least LOOK_CONTRAST lighter or darker than the block it stands on (whichever is nearer), so the two
## never blur together.
func _apart(c: Color, under: Color) -> Color:
	var gap: float = P.LOOK_CONTRAST
	if absf(c.v - under.v) >= gap:
		return c
	var v := under.v - gap if under.v >= 1.0 - gap else under.v + gap
	return Color.from_hsv(c.h, c.s, clampf(v, 0.0, 1.0))


func _pale(c: Color) -> Color:
	var p := c.lerp(Color.WHITE, P.LOOK_PALE)
	return Color.from_hsv(p.h, p.s * 0.85, p.v)


# ---------------------------------------------------------------- the voxels

## The voxels of the jelly's volume, hidden until it bursts (or comes back after bursting), and the chips' look.
func _setup_voxels() -> void:
	_vox_mat = _voxel_material(BURST_LIFE)
	_chip_mat = _voxel_material(CHIP_LIFE)
	_body_mm = _body_mesh()
	_vox = MultiMeshInstance3D.new()
	_vox.multimesh = _body_mm
	_vox.material_override = _vox_mat
	_vox.position = Vector3(0.0, -P.HALF, 0.0)  # (its feet the origin: the pivot)
	_vox.custom_aabb = AABB(Vector3(-8.0, -8.0, -8.0), Vector3(16.0, 18.0, 16.0))
	_vox.visible = false
	add_child(_vox)
	_whole(_vox)
	_last_x = P.position.x
	if not _last_burst.is_empty() and Time.get_ticks_msec() - _last_burst.msec < 20000:
		# back after bursting: a soft burst from the middle of the body that floats up (gravity turned round, no pop)
		# REBUILD_UP in REBUILD_FROM, played backwards — hanging in a cluster above, then dropping together into the
		# body — then the jelly takes over
		_rebuild = REBUILD_T + REBUILD_HOLD
		_vox.visible = true
		_mesh.visible = false
		var m := _voxel_material(10.0)  # (none of them shrinks away)
		m.set_shader_parameter("gravity", -2.0 * REBUILD_UP / (REBUILD_FROM * REBUILD_FROM))
		m.set_shader_parameter("pop", 0.0)
		_vox.material_override = m
		_whole(_vox)  # (with few slots these live in the material, and a new one starts without them)
		DrawParam.param(_vox, "blast", Vector3(0.0, P.HALF, 0.0))
		DrawParam.param(_vox, "hole", 3.0)
		DrawParam.param(_vox, "hold", 0.0)
		DrawParam.param(_vox, "power", (REBUILD_SPREAD - P.RADIUS) / REBUILD_FROM)
		DrawParam.param(_vox, "push", Vector3.ZERO)
		DrawParam.param(_vox, "floor_y", -1000.0)
		DrawParam.param(_vox, "age", REBUILD_FROM)
	_last_burst = {}


func _voxel_material(life: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = VoxelShader
	m.set_shader_parameter("voxel", VOX)
	m.set_shader_parameter("gravity", P.gravity)
	m.set_shader_parameter("life", life)
	m.set_shader_parameter("crumble", 0.0)  # (every voxel goes at once)
	m.set_shader_parameter("keep", 10.0)
	return m


## A voxel thing whole, in the body's colour, evenly lit (no pillar fade along it).
func _whole(mmi: GeometryInstance3D) -> void:
	DrawParam.param(mmi, "tint", _color)
	DrawParam.param(mmi, "glow", 0.0)
	DrawParam.param(mmi, "shine", 0.35)
	DrawParam.param(mmi, "fade_len", 100.0)
	DrawParam.param(mmi, "grain", 1.0)
	DrawParam.param(mmi, "age", -1.0)


## The jelly's squash / stretch, crouch and lean (shaders/jelly.gdshaderinc) as one shape for the body's voxels about
## its feet: as tall, as wide as the jelly is half way up, the lean a straight slant to the top.
func _jelly_basis() -> Basis:
	var sy: float = P.height / P.HEIGHT * (1.0 + _display_s)
	var sx: float = lerpf(1.0, 1.0 / sqrt(maxf(0.2, 1.0 + _display_s)), 0.675)
	return Basis(Vector3(sx, 0.0, 0.0), Vector3(_l / P.HEIGHT, sy, 0.0), Vector3(0.0, 0.0, sx))


## The voxel shader lights up a fresh break (0.6 of its colour glowing, gone over its first 0.12 s): the body's voxels
## take that much off their colour then (age: the shader's), so the jelly turning into them, or back, doesn't flash.
## (Whole, in the same light, they come out as bright as the jelly: nothing else is added or taken away.)
static func _unflash(c: Color, age: float) -> Color:
	var flash := 1.0 - smoothstep(0.0, 0.12, age) if age > 0.0 else 0.0
	var k := VOX_LIT / (VOX_LIT + 0.6 * flash)
	var lin := c.srgb_to_linear()
	return Color(lin.r * k, lin.g * k, lin.b * k, c.a).linear_to_srgb()


## The body's voxels, layer by layer from the feet up (so showing the first ones only takes the top away), each a
## little lighter or darker than its neighbours.
static func _body_mesh() -> MultiMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * VOX
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = box
	mm.instance_count = NX * NY * NZ
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var n := 0
	for j in NY:
		for i in NX:
			for k in NZ:
				var c := Vector3((i + 0.5) * VOX - NX * VOX * 0.5, (j + 0.5) * VOX, (k + 0.5) * VOX - NZ * VOX * 0.5)
				mm.set_instance_transform(n, Transform3D(Basis(), c))
				var b := 1.0 + rng.randf_range(-VOX_GRAIN, VOX_GRAIN)
				mm.set_instance_color(n, Color(b, b, b))
				mm.set_instance_custom_data(n, Color(c.x, c.y, c.z, rng.randf()))
				n += 1
	return mm


## n chips off the body (where: index -> place in the body, feet at the origin), flying from `from` (body space) at
## `power` m/s with `push` handed on, onto the ground under the feet; none past LOOK_CHIPS_MAX.
func _chips_at(n: int, where: Callable, from: Vector3, power: float, push: Vector3) -> void:
	n = mini(n, P.LOOK_CHIPS_MAX - _chip_count)
	if n <= 0 or _burst_age >= 0.0 or not is_inside_tree():
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE * VOX
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = box
	mm.instance_count = n
	for i in n:
		var c: Vector3 = where.call(i)
		mm.set_instance_transform(i, Transform3D(Basis(), c))
		var b := 1.0 + randf_range(-VOX_GRAIN, VOX_GRAIN)
		mm.set_instance_color(i, Color(b, b, b))
		mm.set_instance_custom_data(i, Color(c.x, c.y, c.z, randf()))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _chip_mat
	mmi.custom_aabb = AABB(Vector3(-6.0, -6.0, -6.0), Vector3(12.0, 12.0, 12.0))
	P.get_parent().add_child(mmi)
	var feet: Vector3 = P.global_position - Vector3(0.0, P.HALF * P.up, 0.0)
	mmi.global_position = feet if P.up > 0.0 else P.global_position - Vector3(0.0, P.HALF, 0.0)
	_whole(mmi)
	DrawParam.param(mmi, "age", 0.0)
	DrawParam.param(mmi, "blast", from)
	DrawParam.param(mmi, "hole", 3.0)
	DrawParam.param(mmi, "hold", 0.0)
	DrawParam.param(mmi, "power", power)
	DrawParam.param(mmi, "push", push)
	DrawParam.param(mmi, "floor_y", 0.0 if P.up > 0.0 else -1000.0)  # (the ground under its feet)
	DrawParam.param(mmi, "floor_x", Vector2(-3.0, 3.0))
	_chips.append({"mmi": mmi, "age": 0.0, "n": n, "color": _color})
	_chip_count += n


## Landing hard enough (LOOK chips from 4 m/s): bits off the edges of its feet, out to the sides, bouncing once on the
## ground — more the harder it came down; a slam's landing (from 15 m/s) far more and harder.
func _landing_chips(speed: float) -> void:
	if not _fx or speed < 4.0:
		return
	var slam := speed >= 15.0
	var n: int = (12 + randi() % 5) if slam else roundi(lerpf(3.0, 8.0, clampf((speed - 4.0) / 8.0, 0.0, 1.0)))
	_chips_at(n, func(i): return Vector3((0.35 + VOX * 0.5) * (1.0 if i % 2 == 0 else -1.0), VOX * 0.5,
		randf_range(-0.26, 0.26)), Vector3(0.0, -0.3, 0.0), 6.5 if slam else lerpf(2.0, 3.5, clampf((speed - 4.0) / 8.0, 0.0, 1.0)),
		Vector3(_vx * 0.2, 0.0, 0.0))
	if sound.is_valid():
		sound.call("crumble", 0.9 if slam else 0.45)


## Two short colour-matched lines spread from the feet on take-off and landing.
## They live in the level rather than on the player, so the jump leaves them behind.
func _ground_streaks(strength: float) -> void:
	if not is_inside_tree() or _burst_age >= 0.0:
		return
	var color := _color if _ready_color else slime_color
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color.lightened(0.4)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12 + 0.07 * strength, 0.035, 0.035)
	var feet: Vector3 = P.global_position - Vector3(0.0, P.HALF * P.up, 0.0)
	var lanes := 2 if strength >= 0.65 else 1
	for side in [-1.0, 1.0]:
		for lane in lanes:
			var mark := MeshInstance3D.new()
			mark.mesh = mesh
			mark.material_override = material
			mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			P.get_parent().add_child(mark)
			var origin := feet + Vector3(side * (0.22 + 0.1 * lane), 0.07 * P.up, 0.72 + 0.02 * lane)
			mark.global_position = origin
			_streaks.append({"node": mark, "origin": origin, "side": side, "up": P.up,
				"speed": 0.8 + 0.55 * strength + 0.2 * lane, "age": 0.0})


## The run is lost: the jelly turns into the voxels of its volume and they burst where it is, flung on with the
## player's speed and up a little, falling onto the ground under it (or into the gap). Whether it did (no LOOK_VOXEL:
## the jelly just stays).
func shatter() -> bool:
	if not _fx or _burst_age >= 0.0:
		return false
	_mesh.visible = false
	_vox.visible = true
	var world: Node = P.get_parent()
	var bottom: Vector3 = Vector3(P.global_position.x, P.global_position.y - P.HALF, 0.0)
	# shaped as the jelly was (upright; upside down just as it stands), easing back to the voxels' own shape as they fly
	_burst_basis = _jelly_basis() if P.up > 0.0 else Basis()
	_burst_color = _color
	remove_child(_vox)
	world.add_child(_vox)
	_vox.global_transform = Transform3D(_burst_basis, bottom)  # (upright again: the pieces fall down whichever way it stood)
	var push := Vector3(_vx, P.vy * P.up, 0.0) + Vector3(0.0, 2.5, 0.0)
	var floor_top: float = P._last_support if P._last_support > -INF and P.up > 0.0 else -INF
	VoxelColumn.break_apart(_vox, bottom + Vector3(0.0, P.HALF, 0.0), 3.0, 0.0, 3.0, push, floor_top, bottom.x - 4.0, bottom.x + 4.0)
	DrawParam.param(_vox, "shine", 0.35)
	DrawParam.param(_vox, "glow", 0.0)  # (a column's break glows: the body keeps its colour)
	DrawParam.param(_vox, "tint", _burst_color)
	_burst_age = 0.0
	_last_burst = {"msec": Time.get_ticks_msec()}
	return true


## On the frame clock (so the pieces keep flying after a fail): the chips and a burst body age, and a body coming back
## flies back together.
func _process(delta: float) -> void:
	for i in range(_streaks.size() - 1, -1, -1):
		var streak: Dictionary = _streaks[i]
		streak.age += delta
		var mark: MeshInstance3D = streak.node
		if streak.age >= STREAK_LIFE:
			mark.queue_free()
			_streaks.remove_at(i)
			continue
		var phase: float = streak.age / STREAK_LIFE
		mark.global_position = streak.origin + Vector3(
			streak.side * streak.speed * streak.age,
			streak.up * 0.12 * phase * (1.0 - phase), 0.0)
		mark.scale = Vector3(1.0 + 0.7 * phase, maxf(0.04, 1.0 - phase), 1.0)
	for i in range(_chips.size() - 1, -1, -1):
		var c: Dictionary = _chips[i]
		c.age += delta
		DrawParam.param(c.mmi, "age", c.age)
		if c.age < 0.15:  # (in the body's colour from the start: the shader's flash taken off)
			DrawParam.param(c.mmi, "tint", _unflash(c.color, c.age))
		if c.age > CHIP_LIFE * 1.4:
			c.mmi.queue_free()
			_chip_count -= c.n
			_chips.remove_at(i)
	if _burst_age >= 0.0:
		_burst_age += delta
		DrawParam.param(_vox, "age", _burst_age)
		DrawParam.param(_vox, "tint", _unflash(_burst_color, _burst_age))
		var k := smoothstep(0.0, 0.15, _burst_age)
		_vox.basis = Basis(_burst_basis.x.lerp(Vector3.RIGHT, k), _burst_basis.y.lerp(Vector3.UP, k),
			_burst_basis.z.lerp(Vector3.BACK, k))
		_vox.visible = _burst_age < BURST_LIFE * 1.4
	if _rebuild >= 0.0:
		_rebuild -= delta
		var age: float = REBUILD_FROM * minf(_rebuild / REBUILD_T, 1.0)
		DrawParam.param(_vox, "age", age if _rebuild > 0.0 else -1.0)
		DrawParam.param(_vox, "tint", _unflash(_color, age))
		_vox.transform = Transform3D(_jelly_basis(), Vector3(0.0, -P.HALF, 0.0))  # (shaped as the jelly is: it takes over)
		_vox.visible = _ready_color  # (not before the jelly has its colour)
		if _rebuild <= 0.0:  # together again: the smooth jelly takes over
			_rebuild = -1.0
			_vox.visible = false
			_vox.material_override = _vox_mat
			_whole(_vox)
			_mesh.visible = true


## The chips (they are the level's children) go with the player.
func _exit_tree() -> void:
	for streak in _streaks:
		if is_instance_valid(streak.node):
			streak.node.queue_free()
	_streaks.clear()
	for c in _chips:
		if is_instance_valid(c.mmi):
			c.mmi.queue_free()
	_chips.clear()


## A box with rounded edges and corners: every face a grid of n × n squares, each point pushed out from the inner box
## (the box shrunk by r) along its own direction by r, so faces stay flat and edges and corners turn round.
static func _rounded_box(size: Vector3, r: float, n: int) -> ArrayMesh:
	var h := size * 0.5
	var inner := h - Vector3.ONE * r
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var nrm := Vector3.ZERO
			nrm[axis] = sgn
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = 1.0
			var grid := []
			for i in n + 1:
				for j in n + 1:
					var c := nrm * h[axis] + u * h[(axis + 1) % 3] * (2.0 * i / n - 1.0) + v * h[(axis + 2) % 3] * (2.0 * j / n - 1.0)
					var ci := c.clamp(-inner, inner)
					var dn := (c - ci).normalized()
					grid.append([ci + dn * r, dn])
			for i in n:
				for j in n:
					var a: Array = grid[i * (n + 1) + j]
					var b: Array = grid[(i + 1) * (n + 1) + j]
					var c: Array = grid[(i + 1) * (n + 1) + j + 1]
					var d: Array = grid[i * (n + 1) + j + 1]
					for tri in [[a, b, c], [a, c, d]]:
						var p0: Vector3 = tri[0][0]
						var p1: Vector3 = tri[1][0]
						var p2: Vector3 = tri[2][0]
						# Godot draws clockwise triangles (seen from outside) as front faces
						if (p1 - p0).cross(p2 - p0).dot(nrm) > 0.0:
							tri = [tri[0], tri[2], tri[1]]
						for vtx in tri:
							st.set_normal(vtx[1])
							st.add_vertex(vtx[0])
	return st.commit()
