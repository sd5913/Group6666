extends RefCounted
## What the menus need to know of each level, read without loading it: its colour (its theme_color row in tuning.csv, what
## the level itself applies), its letter, the beat of its song and its audio file (the head of its data file).

const Tuning := preload("res://scripts/core/tuning.gd")

const COUNT := 5
const FIRST_SLIME_COLOR := Color("#ed5897")

static var _all: Array = []


## [{level, letter, theme, bpm, first_bar_at, audio}], level 1 first.
static func all() -> Array:
	if _all.is_empty():
		for n in range(1, COUNT + 1):
			_all.append(_read(n))
	return _all


static func _read(n: int) -> Dictionary:
	var info := {"level": n, "letter": "?", "theme": Color.WHITE, "bpm": 120.0, "first_bar_at": 0.0, "audio": ""}
	var f := FileAccess.open("res://data/levels/level%d.json" % n, FileAccess.READ)
	if f != null:  # (the head of the file is enough: a level's data is hundreds of kilobytes)
		for i in 20:
			var line := f.get_line().strip_edges().trim_suffix(",")
			var kv := line.split(":", true, 1)
			if kv.size() < 2:
				continue
			var key := kv[0].strip_edges().trim_prefix("\"").trim_suffix("\"")
			var v := kv[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
			match key:
				"letter", "audio":
					info[key] = v
				"bpm", "first_bar_at":
					info[key] = float(v)
	info.theme = _theme(n)
	return info


## The level's theme_color row.
static func _theme(n: int) -> Color:
	for r in Tuning.read(n):
		if r[0] == "theme_color":
			return Color.html(r[1])
	push_warning("tuning.csv: no theme_color for level %d" % n)
	return Color.WHITE


## The colour shared by the level's runner and its preview on the tavern stool.
static func slime_color(n: int) -> Color:
	if n == 1:
		return FIRST_SLIME_COLOR
	var theme := _theme(clampi(n, 1, COUNT))
	var pale := theme.lerp(Color.WHITE, 0.35)
	return Color.from_hsv(pale.h, pale.s * 0.85, pale.v)
