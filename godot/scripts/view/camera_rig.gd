extends Node3D
## The camera (side view, a little ahead of and above the player, easing vertically, with a jolt for impacts; lifting
## and widening a little while the player rides a glide's ribbon; in a held climax sinking a little on every kick and
## springing back, never zooming), the sky (flashing brighter on those kicks)
## and the light, and 5-5's colours: warm on the home chord, cool elsewhere.

const AHEAD := 4.5             # the camera looks this far ahead of the player,
const CAM_UP := 2.6            # from this far above it,
const LOOK_UP := 0.6           # down at this height above it on the run,
const CAM_Z := 15.0            # from this far in front of the run
const FOV := 50.0              # vertical field of view (degrees)
const GLIDE_UP := 1.0          # riding a glide's ribbon the camera rises this much (metres),
const GLIDE_FOV := 6.0         # widens this much (degrees),
const GLIDE_EASE := 0.3        # easing in and out over this long (seconds)
const WARM := {"bg": Color(0.98, 0.87, 0.74), "amb": Color(1.0, 0.86, 0.72), "sun": Color(1.0, 0.93, 0.82)}
const COOL := {"bg": Color(0.72, 0.81, 0.98), "amb": Color(0.74, 0.82, 1.0), "sun": Color(0.86, 0.92, 1.0)}

var CLIMAX_CAM_PUMP := 0.05    # in a held climax (track.CLIMAX_HOLD) the camera sinks this far on every kick (metres)
var CLIMAX_SKY_PULSE := 0.06   # and the sky flashes this much brighter, both gone 0.15 s later (level.kick_pulse)

var L
var env: Environment
var _sky := Color()             # the sky's colour without the kicks' flash
var sun: DirectionalLight3D
var cam: Camera3D
var cam_y := 2.0
var shake := 0.0
var glide_k := 0.0              # 0..1: how far into the riding view it is
var palette: Array = []         # [[t, tonic]]


func setup() -> void:
	for e in L.data.events:
		if e.branch == "5b" or e.branch == "5c":
			palette.append([e.t, e.branch == "5b"])
	palette.sort_custom(func(a, b): return a[0] < b[0])
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility"  # (there it lifts the whole picture: no threshold)
	var pal := palette_at(0.0)
	env.background_color = pal.bg
	_sky = pal.bg
	env.ambient_light_color = pal.amb
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = FOV
	add_child(cam)
	cam.current = true
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":  # (its depth buffer is coarser: far columns fought in stripes)
		cam.near = 1.0
		cam.far = 800.0


func palette_at(t: float) -> Dictionary:
	var tonic := true
	for p in palette:
		if t >= p[0]:
			tonic = p[1]
		else:
			break
	return WARM if tonic else COOL


func jolt(amount: float) -> void:
	if L.state != "tune":  # (the tune mode only shows moments; nothing hits)
		shake = maxf(shake, amount)


func update(delta: float) -> void:
	var p: Vector3 = L.player.global_position
	p.x += L.lag  # where the song clock is: a player held back (a wall, a fired wall) is seen to fall behind
	cam_y = lerpf(cam_y, L.view_focus().get("y", p.y), 1.0 - exp(-delta * 3.0))
	var off := Vector3.ZERO
	if shake > 0.0:
		shake = maxf(0.0, shake - delta)
		off = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.6
	var glide = L.mechanic("glide")
	glide_k = move_toward(glide_k, 1.0 if glide != null and glide.riding() else 0.0, delta / GLIDE_EASE)
	var lift: float = GLIDE_UP * smoothstep(0.0, 1.0, glide_k)
	var pulse: float = L.kick_pulse(L.now)
	lift -= CLIMAX_CAM_PUMP * pulse  # (the whole view sinks: no tilt, no zoom)
	cam.position = Vector3(p.x + AHEAD, cam_y + CAM_UP + lift, CAM_Z) + off
	cam.look_at(Vector3(p.x + AHEAD, cam_y + LOOK_UP + lift, 0.0) + off)
	cam.fov = FOV + GLIDE_FOV * smoothstep(0.0, 1.0, glide_k)
	var pal := palette_at(L.now)
	var k := 1.0 - exp(-delta * 4.0)
	_sky = _sky.lerp(pal.bg, k)
	var flash: float = CLIMAX_SKY_PULSE * pulse
	env.background_color = Color(minf(1.0, _sky.r + flash), minf(1.0, _sky.g + flash), minf(1.0, _sky.b + flash))
	preload("res://scripts/view/draw.gd").shared_param(L.mats.pillar, "sky", env.background_color)  # hanging columns fade into it
	env.ambient_light_color = env.ambient_light_color.lerp(pal.amb, k)
	sun.light_color = sun.light_color.lerp(pal.sun, k)
