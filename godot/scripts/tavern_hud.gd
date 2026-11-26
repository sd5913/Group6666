extends Node2D
## Crisp lettering over the pixel post pass.

const FONT := preload("res://assets/fonts/upheaval/upheavtt.ttf")
const TITLE := "SLIME PUB"

func _draw() -> void:
	_draw_title_plaque()
	var card := PackedVector2Array([Vector2(423, 649), Vector2(857, 649),
		Vector2(846, 697), Vector2(434, 697)])
	draw_colored_polygon(card, Color("#362638"))
	var border := card.duplicate()
	border.append(card[0])
	draw_polyline(border, Color("#9e6770"), 3.0)
	draw_rect(Rect2(451, 662, 378, 24), Color("#563447"))
	_text("CLICK THE RECORD PLAYER", Vector2(451, 679), 26, HORIZONTAL_ALIGNMENT_CENTER, 378)


func _draw_title_plaque() -> void:
	var title_at := Vector2(128, 109)
	var width := ceilf(FONT.get_string_size(TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x)
	var frame := Rect2(103, 70, width + 50, 55)
	_plaque_shape(Rect2(frame.position + Vector2(3, 5), frame.size), 8, Color("#1c101b"))
	_plaque_shape(frame, 8, Color("#301510"))
	_plaque_shape(frame.grow(-3), 6, Color("#875132"))
	draw_rect(Rect2(frame.position + Vector2(10, 3), Vector2(frame.size.x - 20, 2)), Color("#c78651"))
	draw_rect(Rect2(frame.position + Vector2(10, frame.size.y - 6), Vector2(frame.size.x - 20, 3)), Color("#593021"))
	_plaque_shape(frame.grow(-8), 4, Color("#391d17"))
	_plaque_shape(frame.grow(-11), 2, Color("#241514"))
	for i in 7:
		var grain_x := frame.position.x + 13.0 + (frame.size.x - 40.0) * i / 7.0
		draw_rect(Rect2(grain_x, frame.position.y + 6.0 + (i % 2), 9.0 + (i * 5 % 11), 1.0), Color("#a2623e"))
		draw_rect(Rect2(grain_x + 6.0, frame.end.y - 8.0, 6.0 + (i * 7 % 12), 1.0), Color("#6e3926"))
	for x in [frame.position.x + 14.0, frame.end.x - 14.0]:
		for y in [frame.position.y + 13.0, frame.end.y - 13.0]:
			draw_rect(Rect2(x - 3.0, y - 3.0, 6.0, 6.0), Color("#623a21"))
			draw_rect(Rect2(x - 2.0, y - 2.0, 4.0, 3.0), Color("#cc9256"))
	_text(TITLE, title_at, 40, HORIZONTAL_ALIGNMENT_LEFT, 0)


func _plaque_shape(rect: Rect2, cut: float, color: Color) -> void:
	var lo := rect.position
	var hi := rect.end
	draw_colored_polygon(PackedVector2Array([
		Vector2(lo.x + cut, lo.y), Vector2(hi.x - cut, lo.y),
		Vector2(hi.x, lo.y + cut), Vector2(hi.x, hi.y - cut),
		Vector2(hi.x - cut, hi.y), Vector2(lo.x + cut, hi.y),
		Vector2(lo.x, hi.y - cut), Vector2(lo.x, lo.y + cut),
	]), color)


func _text(value: String, pos: Vector2, size: int, align: HorizontalAlignment, width: float) -> void:
	draw_string(FONT, pos + Vector2(3, 3), value, align, width, size, Color("#2a1c32"))
	draw_string(FONT, pos, value, align, width, size, Color("#f9e7c4"))
