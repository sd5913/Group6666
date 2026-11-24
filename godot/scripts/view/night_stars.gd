extends Control
## 夜空 (the start and end screens, behind everything): small stars scattered over the background, on whole screen pixels, each
## twinkling in its own time, in a few steps of brightness like the rest of the pixel art. Most are single dots; a few grow
## a little cross at the top of their twinkle. They keep off the words and the records (scatter's avoid and rings).

const COLORS := [Color("#F3EEF8"), Color("#BFD4FF"), Color("#FFE9B0"), Color("#F7C6E0")]
const WIDTH := 1152.0           # MENU_STARS is for a window this wide (canvas units; its height is always the same)
const ART_PX := 2.0             # a star's pixel (canvas units),
const CROSS_SHARE := 0.1        # this share of the stars grow a cross,
const CROSS_FROM := 0.72        # when this bright,
const BRIGHT_SHARE := 0.4       # this share of the rest get really bright,
const MIN_GAP := 14.0           # no two closer than this,
const TRIES := 40               # (a star gives up after this many tries at a free place)
const STEPS := 5.0              # the steps of brightness,
const FRAME_T := 1.0 / 15.0     # and how often they change (seconds)

var count := 130                # how many stars (MENU_STARS; 0: none)
var light := 1.0                # how bright the brightest are (MENU_STAR_LIGHT, 0-1)
var hud                         # the screen's pixel scale (scripts/view/hud.gd)
var pattern := 1                # which scatter: the same every time on one screen, another on the other
var _stars: Array = []          # {at, color, cross, low, high, rate, phase}
var _avoid: Array = []
var _rings: Array = []
var _vp := Vector2.ZERO
var _clock := 0.0
var _since := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## The stars for the window now: nowhere in the rects of avoid, nor in the rings ([middle, radius]).
func scatter(avoid: Array, rings: Array) -> void:
	_avoid = avoid
	_rings = rings
	_vp = get_viewport_rect().size
	_stars = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pattern)
	for i in int(count * _vp.x / WIDTH):
		var at := _free_place(rng)
		if is_nan(at.x):
			continue
		var cross := rng.randf() < CROSS_SHARE
		var bright := cross or rng.randf() < BRIGHT_SHARE
		_stars.append({"at": at, "color": COLORS[rng.randi() % COLORS.size()], "cross": cross,
			"low": rng.randf_range(0.2, 0.4), "high": rng.randf_range(0.8, 1.0) if bright else rng.randf_range(0.45, 0.7),
			"rate": rng.randf_range(0.15, 0.5), "phase": rng.randf()})
	queue_redraw()


func _free_place(rng: RandomNumberGenerator) -> Vector2:
	for k in TRIES:
		var at := Vector2(rng.randf() * _vp.x, rng.randf() * _vp.y)
		if _avoid.any(func(r): return r.has_point(at)):
			continue
		if _rings.any(func(r): return at.distance_to(r[0]) < r[1]):
			continue
		if _stars.any(func(s): return s.at.distance_to(at) < MIN_GAP):
			continue
		return at
	return Vector2(NAN, NAN)


func _process(delta: float) -> void:
	_clock += delta
	_since += delta
	if not _stars.is_empty() and get_viewport_rect().size != _vp:
		scatter(_avoid, _rings)
	if _since >= FRAME_T:
		_since = 0.0
		queue_redraw()


func _draw() -> void:
	var s: float = hud._px_scale()
	var px: float = maxf(1.0, roundf(ART_PX * s)) / s  # (a whole number of screen pixels)
	var dot := Vector2(px, px)
	for st in _stars:
		var wave: float = 0.5 + 0.5 * sin(TAU * (_clock * st.rate + st.phase))
		wave *= wave  # (dim for longer, bright for a moment)
		var b: float = ceilf(lerpf(st.low, st.high, wave) * STEPS) / STEPS
		var col: Color = st.color
		col.a = b * light
		var at := Vector2(roundf(st.at.x * s), roundf(st.at.y * s)) / s
		draw_rect(Rect2(at, dot), col)
		if st.cross and b >= CROSS_FROM:
			var arm: Color = col
			arm.a *= 0.6
			for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				draw_rect(Rect2(at + d * px, dot), arm)
