extends Node3D
## The hero. The level moves it along x with the song clock and tells it how high the surface under it is; this script
## only does gravity, jumps and standing on (or being lifted by) that surface. Its hit box is a capsule
## (RADIUS / HEIGHT); how it looks — a wobbling jelly block — is scripts/view/player_look.gd.
## Gravity can point up (`up` = -1, mirror flip): everything then happens in the player's own frame, where the
## surface it stands on is "below" — the level hands support heights over in that frame.

const PlayerLook := preload("res://scripts/view/player_look.gd")

const RADIUS := 0.35
const HEIGHT := 1.4        # standing height
const HALF := 0.7          # capsule centre above its feet
const STEP := 0.25         # a support change bigger than this in one step is a new bar, not a moving one
const LEDGE := 0.45        # coming out of a gap more than this below a platform's top hits its side
# tunables (config/tuning.csv, as player.X)
var SNAP := 0.3            # stay glued to a surface that drops less than this in one step
var TOSS := 0.6            # how much of a rising surface's speed is passed on (visualizer bars toss you)
var MAX_TOSS := 5.0        # ...but never faster than this (m/s)
var LUNGE := 0.8           # dash: how far the body shoots ahead (visual only: x stays on the song clock),
var LUNGE_OUT := 0.08      # how fast it gets there,
var LUNGE_BACK := 0.4      # and how long it takes to settle back onto its beat position
var DASH_CD := 0.3         # dash: the shortest time between two dashes (seconds)
var CROUCH_H := 0.7        # slide: how tall the player is while crouched
# the look (scripts/view/player_look.gd)
var JELLY_HZ := 7.0        # how fast the jelly wobbles (per second)
var JELLY_DAMP := 0.22     # how quickly a wobble dies down (0: never, 1: no wobble at all)
var JELLY_LAND := 0.02     # how far a landing squashes it, per m/s of landing speed
var JELLY_JUMP := 0.12     # take-off squash and stretch
var JELLY_LEAN := 0.1      # dash: how far the top lags behind (metres)
var JELLY_MAX := 0.28      # it never squashes or stretches more than this
var LOOK_THEME := 0.45     # colour: how much of the level's theme is mixed into the colour of the block underneath,
var LOOK_PALE := 0.35      # how much paler than that it is,
var LOOK_TINT_T := 0.2     # and how long it takes to take on a new block's colour (seconds)
var LOOK_CONTRAST := 0.25  # it is always at least this much lighter or darker than the block it stands on (0-1)
var LOOK_FLIP_T := 0.3     # mirror flip: how long the block takes to turn over, end over end (seconds)
var LOOK_VOXEL := 1        # voxel effects: chips off the jelly, the jelly bursting into voxels when the run is lost (0: none)
var LOOK_CHIPS_MAX := 60   # never more chips than this flying at once

var gravity := 22.0
var up := 1.0               # 1: gravity pulls down; -1: it pulls up (the player runs upside down)
var vy := 0.0               # vertical speed in the player's own frame (positive: away from what it stands on)
var grounded := false
var air_time := 0.0         # how long since it last stood on something
var height := HEIGHT        # now (crouching makes it smaller; the feet stay put)
var look: PlayerLook
var _last_support := -INF
var _dash_age := INF
var _hover_left := 0.0      # air dash: glide (no gravity) this much longer,
var _hover_y := 0.0         # ...towards this height (world)
var _under_ledge := false   # fell past a platform's edge: keep falling until over a gap again
var _crouch_left := 0.0     # slide: stay crouched this much longer
var _fall_g := 0.0          # slam: falling at this acceleration instead of gravity until it lands (0: not slamming)


func _ready() -> void:
	look = PlayerLook.new()
	look.setup(self)
	add_child(look)


## One physics step: x follows the song clock; support is the height of the surface under the player in its own frame
## (-INF over a gap). can_toss: rising visualizer pillars throw the player a little; pumping platforms just carry them.
func step(delta: float, x_goal: float, support: float, can_toss: bool) -> void:
	position.x = x_goal
	var y := position.y * up
	if _hover_left > 0.0:
		vy = (_hover_y * up - y) / maxf(_hover_left, delta)
		_hover_left -= delta
		if _hover_left <= 0.0:
			vy = 0.0
	else:
		vy -= (_fall_g if _fall_g > 0.0 else gravity) * delta
	position.y = (y + vy * delta) * up
	y = position.y * up  # (stored and read back, so the height is rounded the way the position keeps it)
	var floor_y := support + HALF
	var rise := support - _last_support if _last_support > -INF and support > -INF else 0.0
	var toss := minf(MAX_TOSS, rise / delta * TOSS) if can_toss and rise > 0.0 and rise < STEP else 0.0
	if support == -INF:
		_under_ledge = false
	elif _last_support == -INF and y < floor_y - LEDGE:
		_under_ledge = true  # came out of a gap well below this platform: no climbing onto it
	if _under_ledge:
		grounded = false
	elif y < floor_y:
		# the surface came up under us (or we landed): stand on it, and let rising bars toss us a little
		position.y = floor_y * up
		vy = maxf(vy, toss)
		grounded = true
	elif grounded and vy <= 0.0 and y - floor_y < SNAP:
		position.y = floor_y * up
		vy = 0.0
	else:
		grounded = false
	_last_support = support
	if grounded:
		_fall_g = 0.0
	air_time = 0.0 if grounded else air_time + delta
	_dash_age += delta
	_crouch_left = maxf(0.0, _crouch_left - delta)
	height = move_toward(height, CROUCH_H if _crouch_left > 0.0 else HEIGHT, delta * 12.0)
	look.position.x = _lunge(_dash_age)
	look.update(delta)


## Dash offset: shoot ahead quickly, then ease back onto the beat position.
func _lunge(age: float) -> float:
	if age < LUNGE_OUT:
		return LUNGE * sin(age / LUNGE_OUT * PI * 0.5)
	var back := (age - LUNGE_OUT) / LUNGE_BACK
	return LUNGE * (1.0 - smoothstep(0.0, 1.0, back)) if back < 1.0 else 0.0


## Leave the surface at speed v (in the player's own frame: away from what it stands on).
func jump(v: float) -> void:
	vy = v
	grounded = false
	_fall_g = 0.0


## Slam: from now until it lands, fall at acceleration g instead of gravity (keeping the speed it already has).
func slam(g: float) -> void:
	_fall_g = g
	_hover_left = 0.0


## Dash, unless the last one was less than DASH_CD ago: whether it went.
func dash() -> bool:
	if _dash_age < DASH_CD:
		return false
	_dash_age = 0.0
	return true


## Slide: crouch for this long (the feet stay where they are).
func crouch(seconds: float) -> void:
	_crouch_left = maxf(_crouch_left, seconds)


func crouching() -> bool:
	return _crouch_left > 0.0


## World height of the top of the head (the end away from the surface it stands on).
func head_y() -> float:
	return position.y + (height - HALF) * up


## Mirror flip: gravity turns round and the player heads for the other side at `speed`.
func flip(speed: float) -> void:
	up = -up
	vy = -speed
	grounded = false
	_last_support = -INF
	_under_ledge = false
	_hover_left = 0.0
	_fall_g = 0.0


func hovering() -> bool:
	return _hover_left > 0.0


## Air dash: glide across for `seconds` instead of falling, easing to centre height `target_y`
## (reaches a platform set back by a dash, even from a slightly early or late press).
func hover(seconds: float, target_y: float) -> void:
	_hover_left = seconds
	_hover_y = target_y
	vy = 0.0
	grounded = false
