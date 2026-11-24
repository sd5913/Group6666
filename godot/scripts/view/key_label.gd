extends Control
## 按键 (a key, as the HUD names it): its name in brackets — [SPACE], [SHIFT], [S] — in the pixel font, filled with its
## own colours (a gradient from its top colour down to its bottom one, shaders/gradient_text.gdshader) and outlined in
## the HUD's dark outline like the rest of its lettering (hud.OUTLINE), no box round it. Every key has its colours, the
## same in every level, so they are learnt (none gold, white or red: those are the judgements'). Sized like a HUD label
## (hud.fit: a whole multiple of FONT_PX on screen); drawn from its top left corner.

const COLORS := {
	"SPACE": [Color("#7FE7FF"), Color("#2F7BFF")],  # cyan to blue
	"SHIFT": [Color("#B6FF6A"), Color("#26B34A")],  # lime to green
	"S": [Color("#FF9AE6"), Color("#B24BFF")],      # pink to violet
}
const GradientText := preload("res://shaders/gradient_text.gdshader")

var key := "SPACE"
var hud
var ls := LabelSettings.new()   # its lettering's size (kept fitted by hud.fit)
var _fill: Control              # the fill, drawn over the outline


## The colours of a key: [top, bottom].
static func colors_of(k: String) -> Array:
	return COLORS.get(k, [Color(0.85, 0.85, 0.85), Color(0.55, 0.55, 0.6)])


## About `size` big (canvas units), at lo to hi multiples of the pixel font's size on screen.
func setup(size: float, lo: int, hi: int) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hud.fit(ls, size, lo, hi)
	_fill = Control.new()
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var m := ShaderMaterial.new()
	m.shader = GradientText
	_fill.material = m
	add_child(_fill)
	_fill.draw.connect(_draw_fill)


func text() -> String:
	return "[%s]" % key


## How big it is drawn now (canvas units).
func text_size() -> Vector2:
	var font: Font = hud.font_or_default()
	return Vector2(font.get_string_size(text(), HORIZONTAL_ALIGNMENT_LEFT, -1, ls.font_size).x + ls.outline_size,
		ls.font_size * 1.2)


func _baseline() -> Vector2:
	var font: Font = hud.font_or_default()
	return Vector2(ls.outline_size * 0.5, roundf(ls.font_size * 0.1) + font.get_ascent(ls.font_size))


func _process(_delta: float) -> void:
	size = text_size()
	_fill.size = size
	queue_redraw()
	_fill.queue_redraw()


func _draw() -> void:
	draw_string_outline(hud.font_or_default(), _baseline(), text(), HORIZONTAL_ALIGNMENT_LEFT, -1, ls.font_size,
		ls.outline_size, hud.OUTLINE)


func _draw_fill() -> void:
	var font: Font = hud.font_or_default()
	var base := _baseline()
	var cols := colors_of(key)
	var m: ShaderMaterial = _fill.material
	m.set_shader_parameter("top", cols[0])
	m.set_shader_parameter("bottom", cols[1])
	m.set_shader_parameter("y0", base.y - font.get_ascent(ls.font_size) * 0.8)  # (from the capitals' tops to the line)
	m.set_shader_parameter("y1", base.y)
	_fill.draw_string(font, base, text(), HORIZONTAL_ALIGNMENT_LEFT, -1, ls.font_size, Color.WHITE)
