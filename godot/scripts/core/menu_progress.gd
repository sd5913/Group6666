extends RefCounted
## Between-level menu state. The tavern previews the level that will be played next.
## After the final results, a new run starts at level 1 and the stool previews it.

const LevelInfo := preload("res://scripts/core/level_info.gd")

static var next_level := 1
static var display_level := 1


static func advance_from(cleared_level: int) -> void:
	if cleared_level >= LevelInfo.COUNT:
		next_level = 1
		display_level = next_level
	else:
		next_level = cleared_level + 1
		display_level = next_level


static func preview_color() -> Color:
	return LevelInfo.slime_color(next_level)
