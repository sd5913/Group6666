extends Control
## 唱片 (the start and end screens): a big record with smaller ones nested inside it, one per level, the first level
## innermost and the last the big one outside, each in its level's colour, the hero standing in the hole in the middle.
## Each record turns at its own speed, the other way from its neighbours; every ALIGN_T seconds they all come round to
## where they started, the inner letters in a row reading T H A T out from the hero. A record's grooves and highlight turn
## with it (shaders/record.gdshader); its letters go round with it but stay upright, on whole screen pixels, in the pixel
## font. The big record's word lies along its ring, letter by letter, so every letter stays on it; it always reads left to
## right or downward (at the two diagonals where that turns round, its H and A change places; its Ts are the same).
## Everything swells a little on the beat (set_pulse).

const RecordShader := preload("res://shaders/record.gdshader")
const LevelInfo := preload("res://scripts/core/level_info.gd")

const RADII := [44.0, 81.0, 118.0, 155.0, 192.0, 232.0]  # the records' edges at full size (canvas units), the hole first
const TURNS := [5, -4, 3, -2, 1]  # turns of each record, the first level's first, every ALIGN_T seconds
const ALIGN_T := 32.0
const START_ANGLE := [0.0, 0.0, 0.0, 0.0, -PI * 0.5]  # (the inner letters in a row; the last level's word at the top)
const HERO_HALF := Vector2(22.0, 35.0)  # the hero's size at full size, as big as it is on the run (canvas units)
const HERO_CORNER := 15.0
const CAP := 2.0 / 3.0          # the capitals' height, of the font's ascent
const LETTER_SIZE := 60.0       # the letters at full size (canvas units),
const WORD_SIZE := 40.0         # the big record's word (60 would poke out of its ring at the diagonals),
const WORD_STEP := deg_to_rad(7.0)  # its letters this far apart along the ring
const SWELL := 0.012            # how much bigger the records are on the beat

var hud                         # the lettering (scripts/view/hud.gd)
var sky := Color.BLACK          # what's behind the records: it shows through the hole in the middle
var center := Vector2(576.0, 324.0)  # the middle of the records (canvas units)
var size_k := 1.0               # how big they are, of full size
var clock := 0.0
var _rect: ColorRect
var _mat: ShaderMaterial
var _labels: Array = []         # each record's letters (the first level's first)
var _pulse := 0.0
var _scale := 1.0
var _body: Color
var _line: Color


func setup() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect = ColorRect.new()
	_mat = ShaderMaterial.new()
	_mat.shader = RecordShader
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var infos: Array = LevelInfo.all()
	var colors := []
	for info in infos:
		colors.append(info.theme)
		var word: bool = info.letter.length() > 1
		var letters := []
		for ch in info.letter:
			var l := Label.new()
			var ls := LabelSettings.new()
			ls.font = hud.font_or_default()
			ls.outline_color = hud.OUTLINE
			hud.fit(ls, (WORD_SIZE if word else LETTER_SIZE) * size_k, 1, 8)
			l.label_settings = ls
			l.text = ch
			l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(l)
			letters.append(l)
		_labels.append(letters)
	_mat.set_shader_parameter("colors", colors)
	_mat.set_shader_parameter("hole", Vector3(sky.r, sky.g, sky.b))
	_body = infos[0].theme.lerp(Color.WHITE, 0.35)
	_line = Color.from_hsv(_body.h, minf(1.0, _body.s * 1.6 + 0.2), 0.32)
	_mat.set_shader_parameter("body", Vector3(_body.r, _body.g, _body.b))
	_mat.set_shader_parameter("line", Vector3(_line.r, _line.g, _line.b))
	_refresh()


## The beat: 1 on it, dying away.
func set_pulse(p: float) -> void:
	_pulse = p


func _process(delta: float) -> void:
	clock += delta
	_refresh()


func _px_scale() -> float:
	return hud._px_scale()


## Where the hero stands now: {center, half, corner (window pixels), body, line}.
func hero_spot() -> Dictionary:
	var s := _px_scale()
	var half: Vector2 = HERO_HALF * size_k * s
	return {"center": _hero_center(s, half), "half": half, "corner": HERO_CORNER * size_k * s, "body": _body, "line": _line}


## (On whole cells, so it stands exactly where the iris's hole is.)
func _hero_center(s: float, _half: Vector2) -> Vector2:
	return (center * s).round()


func _refresh() -> void:
	var s := _px_scale()
	if absf(s - _scale) > 0.001:
		_scale = s
		for f in hud._fits:
			hud._fit(f, s)
	var window: Vector2 = get_window().size
	var cell: float = clampi(floori(window.y / 270.0), 2, 8)
	var swell := 1.0 + SWELL * _pulse
	var radii := []
	for r in RADII:
		radii.append(r * size_k * s * swell)
	var angles := []
	for i in TURNS.size():
		angles.append(START_ANGLE[i] + TAU * TURNS[i] * clock / ALIGN_T)
	_mat.set_shader_parameter("screen", window)
	_mat.set_shader_parameter("center", center * s)
	_mat.set_shader_parameter("cell", cell)
	_mat.set_shader_parameter("u", maxf(1.0, s * size_k))
	_mat.set_shader_parameter("radii", radii)
	_mat.set_shader_parameter("angles", angles)
	_mat.set_shader_parameter("pulse", _pulse)
	var half: Vector2 = HERO_HALF * size_k * s
	# the hero squashes a little on the beat, its feet staying where they are
	var hh := half * Vector2(1.0 - 0.03 * _pulse, 1.0 + 0.04 * _pulse)
	var hc := _hero_center(s, half) + Vector2(0.0, half.y - hh.y)
	_mat.set_shader_parameter("hero_center", hc)
	_mat.set_shader_parameter("hero_half", hh)
	_mat.set_shader_parameter("hero_corner", HERO_CORNER * size_k * s)
	var font: Font = hud.font_or_default()
	for i in _labels.size():
		var mid: float = (RADII[i] + RADII[i + 1]) * 0.5 * size_k * swell
		var letters: Array = _labels[i]
		var n: int = letters.size()
		var back: bool = cos(angles[i]) - sin(angles[i]) < 0.0  # (clockwise is leftwards or upwards there)
		for j in n:
			var slot: float = (n - 1 - j if back else j) - (n - 1) * 0.5
			var th: float = angles[i] + slot * WORD_STEP
			var l: Label = letters[j]
			var fs: int = l.label_settings.font_size
			var w: float = font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x - float(fs) / hud.FONT_PX
			var at: Vector2 = center + Vector2(cos(th), sin(th)) * mid
			var top: float = at.y + font.get_ascent(fs) * CAP * 0.5 - font.get_ascent(fs)
			l.position = (Vector2(at.x - w * 0.5, top) * s).round() / s
