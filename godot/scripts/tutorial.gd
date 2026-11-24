extends Node3D
## 引导 (the tutorial): a level entered afresh (from the title screen, the level before, a level chosen; not R, not a lost
## life; none in the final level) starts well before its song, in silence, on a short course of the level's own
## mechanics (each mechanic's teach() puts one there). Its clock is this one's: the run slows down on the way to each
## press and stops on it, with the key's sign over the hero and a hand pointing at it (scripts/view/key_sign.gd), until
## that key is pressed; the press then lands right on its moment, so it can't be got wrong and the course can't be
## failed. A long press (a glide) stops again for holding on and for letting go. The course ends on a platform, reached
## by the last mechanic, with a big plate on it: stepping on it the song's title shows (scripts/view/title_card.gd), then
## the count-in runs, 3, 2 standing on it, 1 running, and the song starts. The song part of the level is the same as ever:
## everything here is before tut_end (the platform).

const Draw := preload("res://scripts/view/draw.gd")
const KeySign := preload("res://scripts/view/key_sign.gd")
const PlayerScript := preload("res://scripts/player.gd")

## Each level's course, in beats from the song's start: where it starts, where the platform starts ([beats, and seconds
## more]: right where the last mechanic lands), and its stations [mechanic, its teach()'s times, its kind].
const COURSES := {
	1: {"start": -19.0, "from": [-3.0, -0.03], "stations": [["drums", [-15.0], "A"], ["jaws", [-9.0]], ["drums", [-5.0, -3.0], "B"]]},
	2: {"start": -23.0, "from": [-4.0, 0.25], "stations": [["walls", [-19.0]], ["steps", [-15.0, -13.0]], ["glide", [-8.0, -4.0]]]},
	3: {"start": -27.0, "from": [-3.0, -0.03], "stations": [["slam", [-23.0]], ["slide", [-18.0]], ["towers", [-14.0]], ["hops", [-10.0, -9.0, -8.0]], ["springs", [-4.0, -3.0]]]},
	4: {"start": -19.0, "from": [-3.0, 0.12], "stations": [["smash", [-15.0]], ["launch", [-11.0]], ["flip", [-7.0]], ["flip", [-3.0]]]},
}
const KEYS := {"jump": "SPACE", "dash": "SHIFT", "down": "S"}
const STEP_UP := 1.2            # the platform stands this far above the course (metres)
const PLATE_BEATS := 1.0        # the plate's middle is this many beats before the song starts
const SLOW_T := 0.35            # the run slows down over this much of the way to a press (seconds of its clock), and the key
const MIN_SCALE := 0.15         # counts from there on; it never goes slower than this before it stops
const AT := 0.002               # it stops this long before the press's moment
const SHOW_BEATS := 2.0         # a sign shows this many beats before its press,
const PRESSED_T := 0.18         # and stays this long once pressed (seconds)
const PLATE_L := 3.2            # the plate along the run,
const PLATE_D := 1.5            # across it (on the platform's two metres),
const PLATE_H := 0.34           # how high it stands (metres),
const PLATE_DOWN := 0.04        # and still does once stepped on,
const SINK_T := 0.08            # going down in this long (seconds)

var L
var stops: Array = []           # {t, action, [until], armed (the key is in), sent (the press has been made)}: in order
var plate_t := 0.0
var waiting := ""               # what it has stopped for: "" (it hasn't), an action, "hold", "release"
var _i := 0                     # the stop it is on the way to
var _sign: KeySign
var _last := {}                 # the stop pressed just now, its sign going down (PRESSED_T)
var _last_left := 0.0
var _plate: Node3D
var _plate_mat: StandardMaterial3D
var _plate_y := 0.0
var _stepped := false
var _sink := 0.0
var _time := 0.0


func _course() -> Dictionary:
	return COURSES[int(L.data.level)]


func start_t() -> float:
	return _course().start * L.beat


## Where the platform starts: the course's end (L.tut_end).
func platform_t() -> float:
	return _course().from[0] * L.beat + _course().from[1]


## Every station's mechanic gets its thing, before anything is planned round it.
func plan() -> void:
	plate_t = -PLATE_BEATS * L.beat
	for st in _course().stations:
		L.mechanic(st[0]).teach(st[1].map(func(b): return b * L.beat), st[2] if st.size() > 2 else "")


## The stops are what the mechanics' prompts say; the sign; the plate on its base.
func build() -> void:
	for m in L.mechanics:
		for p in m.prompts():
			if p.t < L.tut_end:
				var s: Dictionary = p.duplicate()
				s.armed = false
				s.sent = false
				stops.append(s)
	stops.sort_custom(func(a, b): return a.t < b.t)
	_sign = KeySign.new()
	_sign.hud = L.hud
	L.hud.add_child(_sign)
	_sign.setup()
	_sign.visible = false
	var x: float = L.track.x_at(plate_t)
	var y: float = L.ground_h(plate_t)
	var base := BoxMesh.new()
	base.size = Vector3(PLATE_L + 0.4, 0.1, PLATE_D + 0.3)
	Draw.mesh(self, base, Draw.mat(Color(0.16, 0.16, 0.2)), Vector3(x, y + 0.05, 0.0))
	var top := BoxMesh.new()
	top.size = Vector3(PLATE_L, PLATE_H, PLATE_D)
	_plate_mat = Draw.mat(L.mats.accent, L.mats.accent, 0.8)
	_plate_y = y + 0.1 + PLATE_H * 0.5
	_plate = Draw.mesh(self, top, _plate_mat, Vector3(x, _plate_y, 0.0))
	var inner := BoxMesh.new()
	inner.size = Vector3(PLATE_L * 0.7, 0.03, PLATE_D * 0.7)
	var pale: Color = L.mats.accent.lightened(0.5)
	Draw.mesh(_plate, inner, Draw.mat(pale, pale, 0.5), Vector3(0.0, PLATE_H * 0.5 + 0.015, 0.0))


# ---------------------------------------------------------------- the clock

## How far the run goes on this step (0: it stands still). It goes on as ever, and slower nearing a press; right on it, it
## makes the press, once the key has come. On autoplay the mechanics press by themselves: it just runs.
func clock(delta: float) -> float:
	waiting = ""
	if _i >= stops.size():
		var to_plate: float = plate_t - L.now
		if to_plate < 1e-6:
			_step_on()
			L.plate_reached()
			return 0.0
		return minf(delta, to_plate)
	var s: Dictionary = stops[_i]
	if L.autoplay:
		if L.now > s.get("until", s.t) + 0.05:
			_i += 1
		return delta
	if not s.sent:
		var left: float = s.t - AT - L.now
		if left < 1e-6:
			if not s.armed or (s.has("until") and not L.jump_held):  # (a long press: still down as it starts)
				waiting = s.action
				return 0.0
			_send(s)
			if not s.has("until"):
				_i += 1
			return delta
		var k: float = 1.0 if s.armed else clampf(left / SLOW_T, MIN_SCALE, 1.0)
		return minf(delta * k, left)
	var hold_left: float = s.until - AT - L.now
	if hold_left < 1e-6:
		if L.jump_held:
			waiting = "release"
			return 0.0
		_i += 1
		return delta
	if not L.jump_held:
		if hold_left <= 0.1:  # (let go just before its moment: that's near enough)
			_i += 1
			return delta
		waiting = "hold"
		return 0.0
	return minf(delta * clampf(hold_left / SLOW_T, MIN_SCALE, 1.0), hold_left)


func _send(s: Dictionary) -> void:
	s.sent = true
	match s.action:
		"jump":
			L.jump_press = L.now
		"dash":
			L.press_dash()
		"down":
			L.down_press = L.now
	if not s.has("until"):
		_last = s
		_last_left = PRESSED_T


## A key pressed: the one asked for, once the run is slowing for it, is taken; any other only shakes the sign.
func pressed(action: String) -> void:
	if L.autoplay or _i >= stops.size():
		return
	var s: Dictionary = stops[_i]
	if s.sent:
		return
	if action == s.action and L.now >= s.t - SLOW_T:
		s.armed = true
	elif L.now >= s.t - SHOW_BEATS * L.beat:
		_sign.shake()


## After each step in the tutorial: the plate under the hero's front, and no falling for good (nothing here is meant to
## let the hero fall: should it, it is put back on its path).
func after_step() -> void:
	var p = L.player
	if p.position.x + PlayerScript.RADIUS >= L.track.x_at(plate_t) - PLATE_L * 0.5:
		_step_on()
	var t: float = L.player_t()
	var floor_y: float = L.ground_h(t)
	var seg: Dictionary = L.seg_at(t)
	if not seg.is_empty():
		floor_y = minf(floor_y, seg.top)
	if p.up > 0.0 and p.position.y < floor_y + L.HALF - 2.5:
		p.position.y = _hero_y(L.now)
		p.vy = 0.0
		p.reset_physics_interpolation()


## Where the hero's middle is at t, played perfectly: L.path_y, which doesn't know the flat pillars between the stations.
func _hero_y(t: float) -> float:
	if L.arc_at(t).is_empty() and L.seg_at(t).is_empty() and L.up_at(t) > 0.0:
		return L.ground_h(t) + L.mech_lift + L.HALF
	return L.path_y(t)


func _step_on() -> void:
	if _stepped:
		return
	_stepped = true
	_plate_mat.albedo_color = L.mats.accent.darkened(0.3)
	_plate_mat.emission_energy_multiplier = 0.25
	L.sfx.play("slam_hit", 0.7)
	L.pixel_post.pulse(L.mats.accent, 0.25)
	L.cam_rig.jolt(0.12)


# ---------------------------------------------------------------- what shows

func _process(delta: float) -> void:
	_time += delta
	if _plate != null:
		if _stepped:
			_sink = minf(1.0, _sink + delta / SINK_T)
			_plate.position.y = _plate_y - (PLATE_H - PLATE_DOWN) * _sink
		else:
			_plate_mat.emission_energy_multiplier = 0.8 + 0.5 * sin(_time * TAU)
	if _sign != null:
		_update_sign(delta)


## Over the hero at the next stop (in the world: it comes up with the run), from SHOW_BEATS before it; while a long
## press is on, over the hero itself.
func _update_sign(delta: float) -> void:
	_last_left = maxf(0.0, _last_left - delta)
	_sign.visible = false
	if L.state != "tutorial":
		return
	var s: Dictionary = _last if _last_left > 0.0 else {}
	if s.is_empty() and _i < stops.size() and L.now >= stops[_i].t - SHOW_BEATS * L.beat:
		s = stops[_i]
	if s.is_empty():
		return
	var long: bool = s.has("until")
	var up: float = L.up_at(s.t - 0.01)
	var over: Vector3 = Vector3(L.track.x_at(s.t), _hero_y(s.t), 0.0)
	if s.sent and long:
		over = L.player.global_position
		up = L.player.up
	over.y += (L.HALF + 0.35) * up
	_sign.key = KEYS[s.action]
	_sign.at = get_viewport().get_camera_3d().unproject_position(over)
	_sign.under = up < 0.0
	_sign.down = L.jump_held if long else (s.sent or s.armed)
	_sign.word = ""
	if long:
		_sign.word = "RELEASE" if s.sent and L.jump_held and s.until - L.now <= SLOW_T else "HOLD"
	_sign.visible = true
