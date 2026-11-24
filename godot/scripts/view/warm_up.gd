extends CanvasLayer
## The loading screen, in the web build only, the first time the page opens the title (scripts/title_screen.gd starts it). A browser
## builds a shader program the first time it is drawn and the page stands still until it has: a tenth of a second or so for a
## lit material, and one program can't be split. So before the title takes a key every material of the game is drawn once
## here, one step a frame, on a little stage under an opaque loading screen, and the first press has nothing left to wait
## for. The browser keeps what it has built, so on a second open the steps go by a few to the frame and it's over at once.
## Each new kind of material the game gets belongs in _make_steps. Nothing here runs on Windows. (The engine's default
## program of each material, which nothing draws with, costs nothing: see html/head_include in export_presets.cfg.)

const Draw := preload("res://scripts/view/draw.gd")
const CameraRig := preload("res://scripts/view/camera_rig.gd")
const LevelInfo := preload("res://scripts/core/level_info.gd")
const VoxelColumn := preload("res://scripts/view/voxel_column.gd")
const PillarShader := preload("res://shaders/pillar.gdshader")
const NoteShader := preload("res://shaders/midi_note.gdshader")
const WaveShader := preload("res://shaders/far_wave.gdshader")
const PlateShader := preload("res://shaders/far_plate.gdshader")
const RibbonShader := preload("res://shaders/ribbon.gdshader")
const TreadShader := preload("res://shaders/tread_notes.gdshader")
const BodyShader := preload("res://shaders/jelly.gdshader")
const OutlineShader := preload("res://shaders/jelly_outline.gdshader")
const IrisShader := preload("res://shaders/iris.gdshader")
const PostShader := preload("res://shaders/pixel_post.gdshader")

const WORDS := "LOADING"
const WORDS_SIZE := 40.0        # (canvas units; kept on whole multiples of the pixel font's size)
const NOTE := "THE FIRST OPEN TAKES A WHILE"
const NOTE_SIZE := 20.0
const WORDS_Y := 260.0          # the top of its letters
const NOTE_Y := 372.0
const BLOCKS := 20              # the bar: this many blocks, lit one by one, in the colours of the five records,
const BLOCK := 20.0             # this big,
const BLOCK_GAP := 4.0          # with this between them
const BAR_Y := 324.0
const QUICK_FRAME := 0.05       # a lit material's frame shorter than this (seconds): it was already built, so ask for more at a time
const QUICK_STEPS := 4
const LIT := 3                  # a step with a lit material takes about this many times as long as the others
const SETTLE_FRAMES := 2        # frames before the first step (the screen is up) and after the last (it has been drawn)

signal done

var kept_name := ""             # the node on the tree's root that outlives the title: it keeps the shaders alive, and says it's done
var hud
var sky := Color.WHITE
var ink := Color.BLACK
var build_title: Callable
var _steps: Array = []          # [weight, what to do]
var _weight := 0
var _weight_done := 0
var _wait := SETTLE_FRAMES
var _stage: Node3D
var _bits: Control              # the canvas's materials, under the screen
var _kept: Array = []
var _cover: ColorRect
var _words: Label
var _note: Label
var _lit: Array = []
var _scale := 0.0
var _shown := -1
var _slot := 0
var _lit_last := false
var _quick := false


func _ready() -> void:
	layer = 200  # (over the title, and over the iris's 100, which it draws once)
	_bits = Control.new()
	_bits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bits)
	_cover = ColorRect.new()
	_cover.color = sky
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_words = _text(WORDS, WORDS_SIZE, 1, 8)
	_note = _text(NOTE, NOTE_SIZE, 1, 4)
	var themes: Array = LevelInfo.all().map(func(info): return info.theme)
	for i in BLOCKS:
		var unlit := ColorRect.new()
		unlit.color = ink.lerp(sky, 0.85)
		unlit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(unlit)
		var block := ColorRect.new()
		block.color = themes[i * themes.size() / BLOCKS]
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.visible = false
		unlit.add_child(block)
		_lit.append(block)
	_layout()
	_make_steps()


func _text(s: String, size: float, lo: int, hi: int) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = hud.font_or_default()
	ls.font_color = ink
	ls.outline_color = Color(0, 0, 0, 0)  # (the hud's refit puts an outline size back on its labels, and an outline is white unless told otherwise)
	hud.fit(ls, size, lo, hi)
	ls.outline_size = 0
	l.label_settings = ls
	l.text = s
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _layout() -> void:
	_scale = hud._px_scale()
	for f in hud._fits:
		hud._fit(f, _scale)
	_words.label_settings.outline_size = 0
	_note.label_settings.outline_size = 0
	var vp := get_viewport().get_visible_rect().size
	var mid := vp * 0.5 - Vector2(576.0, 324.0)  # (the layout is drawn for 1152x648: a wider window keeps it in the middle)
	var font: Font = hud.font_or_default()
	for pair in [[_words, WORDS_Y], [_note, NOTE_Y]]:
		var l: Label = pair[0]
		var w: float = font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.label_settings.font_size).x
		l.position = _snapped(Vector2((vp.x - w) * 0.5, mid.y + pair[1]))
	var x0 := (vp.x - BLOCKS * BLOCK - (BLOCKS - 1) * BLOCK_GAP) * 0.5
	for i in BLOCKS:
		var block: ColorRect = _lit[i]
		var unlit: ColorRect = block.get_parent()
		unlit.position = _snapped(Vector2(x0 + i * (BLOCK + BLOCK_GAP), mid.y + BAR_Y))
		unlit.size = _snapped(Vector2(BLOCK, BLOCK))
		block.size = unlit.size


func _snapped(v: Vector2) -> Vector2:
	return (v * _scale).round() / _scale


func _process(delta: float) -> void:
	if absf(hud._px_scale() - _scale) > 0.001:
		_layout()
	if _wait > 0:
		_wait -= 1
		if _wait == 0 and _steps.is_empty():
			_finish()
		return
	if _lit_last and delta < QUICK_FRAME:  # (a lit material in no time: the browser has them all already)
		_quick = true
	_lit_last = false
	for i in (QUICK_STEPS if _quick else 1):
		if _steps.is_empty():
			break
		var step: Array = _steps.pop_front()
		step[1].call()
		_weight_done += step[0]
		_lit_last = step[0] == LIT
	_show_progress()
	if _steps.is_empty():
		_wait = SETTLE_FRAMES


func _show_progress() -> void:
	var lit := BLOCKS * _weight_done / maxi(1, _weight)
	if lit != _shown:
		_shown = lit
		for i in BLOCKS:
			_lit[i].visible = i < lit


## Done: only the shaders stay (on the tree's root, so that nothing has to be built twice, between levels neither).
func _finish() -> void:
	var keep := Node.new()
	keep.name = kept_name
	keep.set_meta(&"kept", _kept)
	get_tree().root.add_child(keep)
	done.emit()
	queue_free()


func _make_steps() -> void:
	_add(1, build_title)
	_add(1, _make_stage)
	_add(1, _canvas_bits)
	# the plain materials (scripts/view/draw.gd), each drawn on its own and as a MultiMesh (a burst of cubes is one)
	var lit := Draw.mat(Color.WHITE)
	var glowing := Draw.mat(Color.WHITE, Color.WHITE, 1.0)
	var floor_mat := Draw.mat(Color.WHITE)
	floor_mat.disable_receive_shadows = true
	floor_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	floor_mat.distance_fade_min_distance = 110.0
	floor_mat.distance_fade_max_distance = 70.0
	var fading := Draw.mat(Color(1.0, 1.0, 1.0, 0.5), Color.WHITE, 1.0)
	fading.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var flat := Draw.mat(Color.WHITE)
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flat_glow := Draw.mat(Color.WHITE, Color.WHITE, 1.0)
	flat_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var see_through := Draw.mat(Color(1.0, 1.0, 1.0, 0.5))
	see_through.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	see_through.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var beam := Draw.mat(Color(1.0, 1.0, 1.0, 0.5), Color.WHITE, 1.0)
	beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var holes := StandardMaterial3D.new()
	holes.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for m in [lit, glowing, floor_mat, fading]:
		_add(LIT, _both.bind(m, true))
	for m in [flat, flat_glow, see_through, beam, holes]:
		_add(1, _both.bind(m, true))
	# the game's own shaders
	_add(LIT, _column)
	_add(LIT, _both.bind(_with(PillarShader), true))
	var body := _with(BodyShader)
	body.next_pass = _with(OutlineShader)
	_add(LIT, _plain.bind(body, true))
	_add(1, _many.bind(_with(NoteShader), false))
	_add(1, _many.bind(_with(WaveShader), false))
	_add(1, _plain.bind(_with(PlateShader), false))
	_add(1, _plain.bind(_with(RibbonShader), false))
	_add(1, _plain.bind(_with(TreadShader), false))


func _add(weight: int, what: Callable) -> void:
	_steps.append([weight, what])
	_weight += weight


func _with(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


## The same camera, sky and shadowed sun the levels draw with (only their programs are the ones the levels will want).
func _make_stage() -> void:
	_stage = Node3D.new()
	add_child(_stage)
	var rig := CameraRig.new()
	rig.L = {"data": {"events": []}}
	_stage.add_child(rig)
	rig.setup()
	rig.cam.position = Vector3(0.0, 0.0, 15.0)


## The iris and the look over the run; the HUD's sort of lettering and frames. (The title under the screen has the rest.)
func _canvas_bits() -> void:
	for shader in [IrisShader, PostShader]:
		var r := ColorRect.new()
		r.material = _with(shader)
		r.size = Vector2(16.0, 16.0)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bits.add_child(r)
		_kept.append(r.material)
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.add_theme_font_override("normal_font", hud.font_or_default())
	rich.add_theme_constant_override("outline_size", 2)
	rich.add_theme_color_override("font_outline_color", Color.BLACK)
	rich.text = "[outline_color=#000000][color=#ffffff]A[/color][/outline_color]"
	rich.size = Vector2(64.0, 64.0)
	rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bits.add_child(rich)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	frame.set_border_width_all(4)
	var edge := Panel.new()
	edge.add_theme_stylebox_override("panel", frame)
	edge.size = Vector2(22.0, 22.0)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bits.add_child(edge)


func _both(m: Material, shadow: bool) -> void:
	_plain(m, shadow)
	_many(m, shadow)


func _spot(node: GeometryInstance3D, shadow: bool) -> void:
	_slot += 1
	node.position = Vector3(fposmod(_slot * 1.3, 12.0) - 6.0, fposmod(_slot * 0.7, 6.0) - 3.0, 0.0)
	if not shadow:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(node)


func _plain(m: Material, shadow: bool) -> void:
	_kept.append(m)
	var node := MeshInstance3D.new()
	node.mesh = BoxMesh.new()
	node.material_override = m
	_spot(node, shadow)


func _many(m: Material, shadow: bool) -> void:
	_kept.append(m)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D())
	mm.set_instance_color(0, Color.WHITE)
	mm.set_instance_custom_data(0, Color(0.0, 0.0, 0.0, 0.0))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = m
	_spot(node, shadow)


## A jaw, as the levels make them.
func _column() -> void:
	var node: MultiMeshInstance3D = VoxelColumn.make(_stage, 0.6, 0.6, 1.0, 1, 22.0)
	_slot += 1
	node.position = Vector3(fposmod(_slot * 1.3, 12.0) - 6.0, 0.0, 0.0)
	_kept.append(node.material_override)
