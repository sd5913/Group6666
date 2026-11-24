extends RefCounted
## The start screen's, the end screen's and the iris's settings (config/tuning.csv, its 默认 column: they belong to no
## level).

const Tuning := preload("res://scripts/core/tuning.gd")

var MENU_BG := Color("#1A1638")  # the start and end screens' background (and the web build's loading screen's),
var MENU_INK := Color("#F3EEF8")  # and their words
var MENU_STARS := 130           # the little twinkling stars on the start and end screens (0: none),
var MENU_STAR_LIGHT := 1.0      # and how bright the brightest are (0-1)
var TITLE_MUSIC := 1            # the final level's song, quietly, on the start and end screens (1 on / 0 off)
var TITLE_MUSIC_DB := -14.0     # how quietly (dB)
var IRIS_CLOSE := 0.55          # the iris closes onto the hero in this long (seconds),
var IRIS_HOLD := 0.5            # stays black with only the hero this long,
var IRIS_OPEN := 0.75           # and opens from the hero in this long
var RANK_ON := 1                # the end screen's overall rank (1 on / 0 off)
var RANK_S := 0.95              # the least accuracy (perfect 1, good 0.5, of all that was judged) for an S,
var RANK_A := 0.85              # an A,
var RANK_B := 0.7               # a B (under that: a C)


static func read():
	var m = load("res://scripts/core/menu_settings.gd").new()
	for r in Tuning.read(0):
		Tuning.apply(m, r[0], r[1])
	return m
