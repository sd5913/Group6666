extends Control
## Code-drawn tavern. Choosing the record zooms into the player and lowers its
## arm before entering the next level; cleared levels return here.

const TavernLayer := preload("res://scripts/tavern_layer.gd")
const TavernHud := preload("res://scripts/tavern_hud.gd")
const TavernPost := preload("res://shaders/tavern_post.gdshader")
const MenuProgress := preload("res://scripts/core/menu_progress.gd")
const Results := preload("res://scripts/core/results.gd")
const RunState := preload("res://scripts/core/run_state.gd")
const Iris := preload("res://scripts/view/iris.gd")
const ART_SIZE := Vector2(1280.0, 720.0)
const PLAYER_HIT := Rect2(285.0, 365.0, 179.0, 80.0)
const RECORD_FOCUS := Vector2(375.0, 408.0)
const ARM_PIVOT := Vector2(443.0, 385.0)
const ARM_PARKED := -0.52
const ARM_ON_RECORD := 0.18
const ARM_LIFT := 17.0
const RECORD_ZOOM := 4.2

var _picture: TextureRect
var _hud: Node2D
var _elder: Node2D
var _young: Node2D
var _disc: Node2D
var _glow: Node2D
var _arm: TavernLayer
var _clock := 0.0
var _opening := false
var _offset := Vector2.ZERO
var _art_scale := 1.0
var _zoom_progress := 0.0


func _ready() -> void:
	var file := FileAccess.open("res://data/tavern_commands.json", FileAccess.READ)
	if file == null:
		push_error("Tavern geometry is missing")
		return
	var commands = JSON.parse_string(file.get_as_text())
	if not commands is Array:
		push_error("Tavern geometry is invalid")
		return
	var parts := _find_parts(commands)
	if parts.is_empty():
		push_error("Tavern geometry groups are missing")
		return
	var background := ColorRect.new()
	background.color = Color("#281d32")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var stage := Node2D.new()
	viewport.add_child(stage)
	var base_commands: Array = commands.slice(0, parts.elder)
	base_commands.append(commands[parts.young - 1]) # stool contact shadow
	_add_layer(stage, base_commands)
	_elder = _animated_group(stage, Vector2(551, 413), commands.slice(parts.elder, parts.young - 1))
	_elder.position.y += 12.0 # tuck the lower corners behind the counter
	_young = _animated_group(stage, Vector2(781, 458), commands.slice(parts.young, parts.counter), true)
	_add_layer(stage, commands.slice(parts.counter, parts.player))
	_add_layer(stage, commands.slice(parts.player, parts.disc))
	_glow = _add_layer(stage, [], "glow")
	_disc = _add_layer(stage, [], "record")
	_disc.position = Vector2(375, 392)
	_arm = _add_layer(stage, [], "tonearm") as TavernLayer
	_arm.position = ARM_PIVOT
	_arm.arm_angle = ARM_PARKED
	_add_layer(stage, commands.slice(parts.disc + 5, commands.size()))
	_picture = TextureRect.new()
	_picture.texture = viewport.get_texture()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = TavernPost
	mat.set_shader_parameter("source_texture", viewport.get_texture())
	mat.set_shader_parameter("art_h", 240.0)
	_picture.material = mat
	add_child(_picture)
	_hud = TavernHud.new()
	add_child(_hud)
	resized.connect(_layout)
	_layout()


func _find_parts(commands: Array) -> Dictionary:
	var parts := {}
	for i in commands.size():
		var op: String = commands[i].op
		var args: Array = commands[i].args
		if op == "bartender":
			parts.elder = i
		if op == "slime" and parts.has("elder") and not parts.has("young"):
			parts.young = i
		if parts.has("young") and not parts.has("counter") and op == "shaded_poly" and args[0][0][0] == 219:
			parts.counter = i
		if parts.has("counter") and not parts.has("player") and op == "poly" and args[0][0][0] == 292:
			parts.player = i
		if parts.has("player") and not parts.has("disc") and op == "ellipse" and args[0][0] == 329 and args[0][1] == 375:
			parts.disc = i
	return parts if parts.size() == 5 else {}


func _add_layer(parent: Node, items: Array, mode := "geometry") -> Node2D:
	var layer := TavernLayer.new()
	layer.kind = mode
	layer.commands = items
	parent.add_child(layer)
	return layer


func _animated_group(parent: Node2D, pivot: Vector2, items: Array, young := false) -> Node2D:
	var group := Node2D.new()
	group.position = pivot
	parent.add_child(group)
	var layer := TavernLayer.new()
	layer.commands = items
	layer.position = -pivot
	if young:
		layer.set_young_color(MenuProgress.preview_color())
	group.add_child(layer)
	return group


func _layout() -> void:
	if _picture == null or _hud == null:
		return
	var viewport_size := get_viewport_rect().size
	_art_scale = minf(viewport_size.x / ART_SIZE.x, viewport_size.y / ART_SIZE.y)
	_offset = (viewport_size - ART_SIZE * _art_scale) * 0.5
	_picture.size = ART_SIZE * _art_scale
	_apply_camera(viewport_size)
	_hud.position = _offset
	_hud.scale = Vector2.ONE * _art_scale


func _apply_camera(viewport_size: Vector2) -> void:
	var zoom := lerpf(1.0, RECORD_ZOOM, _zoom_progress)
	var focus_start := _offset + RECORD_FOCUS * _art_scale
	var focus_screen := focus_start.lerp(viewport_size * 0.5, _zoom_progress)
	_picture.scale = Vector2.ONE * zoom
	_picture.position = focus_screen - RECORD_FOCUS * _art_scale * zoom


func _set_zoom_progress(value: float) -> void:
	_zoom_progress = value
	_apply_camera(get_viewport_rect().size)


func _process(delta: float) -> void:
	if _elder == null:
		return
	_clock += delta
	var elder_pose := _pose(_clock, 3.3, 0.0, 0.035, 0.045)
	var young_pose := _pose(_clock, 2.7, 0.26, 0.05, 0.06)
	_elder.scale = elder_pose
	_young.scale = young_pose
	_disc.spin_angle = _clock * 1.4
	_disc.queue_redraw()
	_glow.modulate.a = 0.91 + 0.09 * sin(_clock * 2.2)


func _pose(time: float, period: float, phase: float, width: float, height: float) -> Vector2:
	var cycle := fposmod(time / period + phase, 1.0)
	var keys := [[0.0, 0.0], [0.19, 1.0], [0.36, 0.0], [0.59, -1.0], [0.78, 0.0], [1.0, 0.0]]
	var amount := 0.0
	for i in range(keys.size() - 1):
		if cycle <= keys[i + 1][0]:
			var u := clampf((cycle - keys[i][0]) / (keys[i + 1][0] - keys[i][0]), 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			amount = lerpf(keys[i][1], keys[i + 1][1], u)
			break
	return Vector2(1.0 + amount * width, 1.0 - amount * height)


func _input(event: InputEvent) -> void:
	if _opening:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_enter_records()
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var art_pos := (click.position - _offset) / _art_scale
		if PLAYER_HIT.has_point(art_pos):
			_enter_records()


func _enter_records() -> void:
	if _opening:
		return
	_opening = true
	get_viewport().set_input_as_handled()
	create_tween().tween_property(_hud, "modulate:a", 0.0, 0.45)
	var sequence := create_tween()
	sequence.tween_method(_set_zoom_progress, 0.0, 1.0, 1.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	sequence.tween_property(_arm, "arm_lift", ARM_LIFT, 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	sequence.tween_property(_arm, "arm_angle", ARM_ON_RECORD, 0.78).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sequence.tween_property(_arm, "arm_lift", 0.0, 0.54).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sequence.tween_interval(0.24)
	sequence.tween_callback(_launch_level)


func _launch_level() -> void:
	var level: int = MenuProgress.next_level
	if level == 1:
		Results.reset()
	RunState.clear()
	RunState.intro_due = true
	RunState.tutorial_due = true
	Iris.start(get_tree(), "res://scenes/level_%d.tscn" % level)
