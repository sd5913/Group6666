extends CanvasLayer
## 转场: a black iris whose hole is the hero's silhouette. It closes fast onto the hero wherever they stand, bounces once,
## and holds on black with only the hero; under the black the next scene loads and the hero slides to where they stand in
## it; then the hole opens outward from them until the screen is clear. It lives on the tree's root, so it outlives the
## scene it starts in, and it takes every key and click until it is done. `opened` says it has. A hero off the screen is
## taken to be just inside it. On black the iris draws the hero itself, flat: it fades in over the real one before the scene
## changes, its colour changes to the next scene's as it slides, following where the hero stands there as they settle, and
## it fades out over the real one before the hole opens, so neither end of it pops.
## Level entry closes on the incoming player while a still of the outgoing scene covers the load.

const IrisShader := preload("res://shaders/iris.gdshader")
const MenuSettings := preload("res://scripts/core/menu_settings.gd")

const BOUNCE_T := 0.14          # the bounce as it lands on the hero (seconds),
const BOUNCE := 0.22            # how far it opens again (of the hero's size)
const SLIDE_T := 0.3            # the hero sliding to the next scene's spot
const FADE_T := 0.15            # the iris's own hero fading in over the real one, and out again

signal opened

static var current = null       # the iris going on, if any

var settings
var path := ""
var source: Callable            # -> the spot it closes onto
var _mat: ShaderMaterial
var _rect: ColorRect
var _still: TextureRect
var _entering_level := false
var _phase := "close"
var _t := 0.0
var _spot := {}
var _from := {}
var _to := {}
var _start_size := 1.0
var _wait := 0
var _old_scene: Node


## With no source spot, close and open on the destination level's spawn.
static func start(tree: SceneTree, scene_path: String, spot_source := Callable()):
	var iris = load("res://scripts/view/iris.gd").new()
	iris.path = scene_path
	iris.source = spot_source
	iris._entering_level = not spot_source.is_valid()
	current = iris
	tree.root.add_child(iris)
	return iris


func _ready() -> void:
	settings = MenuSettings.read()
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _entering_level and DisplayServer.get_name() != "headless":
		var frame := get_viewport().get_texture().get_image()
		if frame != null and not frame.is_empty():
			_still = TextureRect.new()
			_still.texture = ImageTexture.create_from_image(frame)
			_still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_still.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_still)
			_still.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect = ColorRect.new()
	_mat = ShaderMaterial.new()
	_mat.shader = IrisShader
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_rect)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _entering_level:
		_rect.color = Color.BLACK
		_rect.visible = _still == null
		_next("prepare_level")
		_load_destination.call_deferred("load_level")
		return
	_rect.material = _mat
	_spot = _on_screen(source.call())
	_start_size = _size_to_clear(_spot)
	_apply(_start_size, 0.0)


func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()


## The spot, its middle kept so that the whole hero is inside the window.
func _on_screen(spot: Dictionary) -> Dictionary:
	var w: Vector2 = get_window().size
	var m: Vector2 = spot.half + Vector2(8.0, 8.0) * w.y / 648.0
	var out := spot.duplicate()
	out.center = Vector2(clampf(spot.center.x, m.x, w.x - m.x), clampf(spot.center.y, m.y, w.y - m.y))
	return out


## How big the hole has to be, of the hero's size, to clear the window.
func _size_to_clear(spot: Dictionary) -> float:
	var w: Vector2 = get_window().size
	var c: Vector2 = spot.center
	var far := Vector2(maxf(c.x, w.x - c.x), maxf(c.y, w.y - c.y))
	var margin := 2.0 if _entering_level else 1.25
	return maxf(far.x / spot.half.x, far.y / spot.half.y) * margin


## The hole `size` times the hero's size, the iris's own hero in it as opaque as `hero`.
func _apply(size: float, hero: float) -> void:
	var window: Vector2 = get_window().size
	_mat.set_shader_parameter("screen", window)
	_mat.set_shader_parameter("cell", float(clampi(floori(window.y / 270.0), 2, 8)))
	_mat.set_shader_parameter("u", window.y / 648.0)
	_mat.set_shader_parameter("center", _spot.center)
	_mat.set_shader_parameter("half_size", _spot.half)
	_mat.set_shader_parameter("corner", _spot.corner)
	_mat.set_shader_parameter("size", size)
	_mat.set_shader_parameter("hero_on", hero)
	_mat.set_shader_parameter("slime", _entering_level)
	var b: Color = _spot.body
	var l: Color = _spot.line
	_mat.set_shader_parameter("body", Vector3(b.r, b.g, b.b))
	_mat.set_shader_parameter("line", Vector3(l.r, l.g, l.b))


func _process(delta: float) -> void:
	_t += delta
	match _phase:
		"load_level":
			if _destination_ready():
				_spot = _destination_spot()
				_start_size = _size_to_clear(_spot)
				_rect.color = Color.WHITE
				_rect.material = _mat
				_rect.show()
				_apply(_start_size, 0.0)
				_next("close")
		"close":
			if _entering_level:
				_spot = _destination_spot()
			elif source.is_valid():
				_spot = _on_screen(source.call())
			var k := clampf(_t / settings.IRIS_CLOSE, 0.0, 1.0)
			_apply(lerpf(_start_size, 1.0, k * k * k), 0.0)
			if k >= 1.0:
				_next("bounce")
		"bounce":
			if _entering_level:
				_spot = _destination_spot()
			var k := clampf(_t / BOUNCE_T, 0.0, 1.0)
			_apply(1.0 + BOUNCE * sin(PI * k), 0.0)
			if k >= 1.0:
				_next("hold")
		"hold":
			if _entering_level:
				_spot = _destination_spot()
			_apply(1.0, clampf(_t / FADE_T, 0.0, 1.0))
			if _t >= maxf(settings.IRIS_HOLD * 0.5, FADE_T):
				if _entering_level:
					if _still != null:
						_still.hide()
						_still.queue_free()
						_still = null
					_next("rest")
				else:
					_from = _spot
					source = Callable()
					_load_destination("load")
		"load":
			_apply(1.0, 1.0)
			if _destination_ready():
				_to = _destination_spot()
				_next("slide")
		"slide":
			_to = _destination_spot()
			var k := clampf(_t / SLIDE_T, 0.0, 1.0)
			var e := smoothstep(0.0, 1.0, k)
			_spot = {"center": _from.center.lerp(_to.center, e), "half": _from.half.lerp(_to.half, e),
				"corner": lerpf(_from.corner, _to.corner, e), "body": _from.body.lerp(_to.body, e), "line": _from.line.lerp(_to.line, e)}
			_apply(1.0, 1.0)
			if k >= 1.0:
				_next("rest")
		"rest":
			_spot = _destination_spot()
			var k := clampf(_t / FADE_T, 0.0, 1.0)
			_apply(1.0, 1.0 - k)
			if k >= 1.0:
				_start_size = _size_to_clear(_spot)
				_next("open")
		"open":
			_spot = _destination_spot()
			var k := clampf(_t / settings.IRIS_OPEN, 0.0, 1.0)
			var clear_size := _size_to_clear(_spot) if _entering_level else _start_size
			_apply(lerpf(1.0, clear_size, k * k * k), 0.0)
			if k >= 1.0:
				current = null
				opened.emit()
				queue_free()


func _load_destination(phase: String) -> void:
	_old_scene = get_tree().current_scene
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("iris: can't go to %s (error %d)" % [path, err])
		current = null
		queue_free()
		return
	_next(phase)


func _destination_ready() -> bool:
	var scene := get_tree().current_scene
	if scene != null and scene != _old_scene and scene.is_inside_tree():
		_wait += 1 # wait for the initial camera and player physics steps
	return _wait >= 3


func _destination_spot() -> Dictionary:
	var scene := get_tree().current_scene
	var method := "spawn_iris_spot" if _entering_level else "iris_spot"
	return _on_screen(scene.call(method)) if scene != null and scene.has_method(method) else _spot


func _next(phase: String) -> void:
	_phase = phase
	_t = 0.0
