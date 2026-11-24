extends Node2D
## Crisp lettering and the elder's matched eyebrows, over the pixel post pass.

const FONT := preload("res://assets/fonts/upheaval/upheavtt.ttf")

var elder_scale := Vector2.ONE


func _draw() -> void:
	for x in [496.0, 553.0]:
		var top := Vector2(551.0 + (x - 551.0) * elder_scale.x,
			443.0 + (327.0 - 443.0) * elder_scale.y)
		var bottom := Vector2(551.0 + (x + 3.0 - 551.0) * elder_scale.x,
			443.0 + (336.0 - 443.0) * elder_scale.y)
		draw_rect(Rect2(top, Vector2(28.0 * elder_scale.x, 9.0 * elder_scale.y)), Color("#d8dfce"))
		draw_rect(Rect2(bottom, Vector2(22.0 * elder_scale.x, 3.0)), Color("#66817b"))
	_text("MIDI RUNNER", Vector2(128, 109), 40, HORIZONTAL_ALIGNMENT_LEFT, 0)
	var card := PackedVector2Array([Vector2(423, 649), Vector2(857, 649),
		Vector2(846, 697), Vector2(434, 697)])
	draw_colored_polygon(card, Color("#362638"))
	var border := card.duplicate()
	border.append(card[0])
	draw_polyline(border, Color("#9e6770"), 3.0)
	draw_rect(Rect2(451, 662, 378, 24), Color("#563447"))
	_text("CLICK THE RECORD PLAYER", Vector2(451, 679), 26, HORIZONTAL_ALIGNMENT_CENTER, 378)


func _text(value: String, pos: Vector2, size: int, align: HorizontalAlignment, width: float) -> void:
	draw_string(FONT, pos + Vector2(3, 3), value, align, width, size, Color("#2a1c32"))
	draw_string(FONT, pos, value, align, width, size, Color("#f9e7c4"))
