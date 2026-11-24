extends Control
## 结束界面, after the final level: the nested records still turning, smaller, beside a table of this session's results
## (scripts/core/results.gd), a row per level with its letter in its colour, and a total. A level not played shows dashes,
## one won with autoplay says AUTO; neither counts. Under it the accuracy (perfect counts 1, good 0.5, of everything
## judged) and a rank from it (RANK_ON, RANK_S, RANK_A, RANK_B), if anything counted. SPACE goes back to the start screen.
## The iris opens here from the small hero. Small stars twinkle on the background (scripts/view/night_stars.gd).

const Hud := preload("res://scripts/view/hud.gd")
const RecordView := preload("res://scripts/view/record_view.gd")
const KeyLabel := preload("res://scripts/view/key_label.gd")
const Iris := preload("res://scripts/view/iris.gd")
const LevelInfo := preload("res://scripts/core/level_info.gd")
const MenuSettings := preload("res://scripts/core/menu_settings.gd")
const Results := preload("res://scripts/core/results.gd")

const GOLD := Color(1.0, 0.82, 0.25)
const RECORD_AT := Vector2(214.0, 324.0)
const RECORD_K := 0.74
const TABLE_MID := 776.0        # the middle of the table
const COLUMNS := [470.0, 680.0, 800.0, 930.0, 1060.0]  # the columns' middles: letter, perfect, good, stars, best streak
const HEADS := ["", "PERFECT", "GOOD", "STARS", "BEST"]
const HEADING_Y := 42.0
const HEAD_Y := 92.0
const FIRST_ROW_Y := 128.0
const ROW := 52.0
const RANK_Y := 510.0
const PROMPT_Y := 604.0
const CAP := 2.0 / 3.0
const NightStars := preload("res://scripts/view/night_stars.gd")
const STAR_CLEAR := 6.0         # the stars keep this far from the words and the records

var settings
var hud
var record
var _stars
var _music: AudioStreamPlayer
var _items: Array = []          # [label or key, x (its middle), y (its capitals' middle)]
var _rule: ColorRect
var _rule_y := 0.0
var _beat := 0.5
var _first := 0.0
var _clock := 0.0
var _scale := 0.0
var _left := false
var _prompt: Array = []         # PRESS, its key, TO RETURN: one line


func _ready() -> void:
	settings = MenuSettings.read()
	var sky := ColorRect.new()
	sky.color = settings.MENU_BG
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud = Hud.new()
	add_child(hud)
	_stars = NightStars.new()
	_stars.hud = hud
	_stars.pattern = 2
	_stars.count = settings.MENU_STARS
	_stars.light = settings.MENU_STAR_LIGHT
	add_child(_stars)
	move_child(_stars, sky.get_index() + 1)
	record = RecordView.new()
	record.hud = hud
	record.sky = settings.MENU_BG
	record.size_k = RECORD_K
	record.center = RECORD_AT
	add_child(record)
	record.setup()
	var infos: Array = LevelInfo.all()
	var last: Dictionary = infos[-1]
	_beat = 60.0 / last.bpm
	_first = last.first_bar_at
	_build(infos)
	_layout()
	if settings.TITLE_MUSIC != 0 and last.audio != "" and ResourceLoader.exists(last.audio):
		_music = AudioStreamPlayer.new()
		var stream: AudioStream = load(last.audio).duplicate()
		stream.set("loop", true)
		_music.stream = stream
		_music.volume_db = settings.TITLE_MUSIC_DB
		add_child(_music)
		_music.play()


func _text(s: String, size: float, x: float, y: float, col: Variant = null, outline := false) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = hud.font_or_default()
	ls.font_color = settings.MENU_INK if col == null else col
	ls.outline_color = hud.OUTLINE if outline else Color(0, 0, 0, 0)
	hud.fit(ls, size, 1, 16)
	l.label_settings = ls
	l.text = s
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	_items.append([l, x, y])
	return l


func _build(infos: Array) -> void:
	_text("RESULTS", 60.0, TABLE_MID, HEADING_Y, infos[-1].theme, true)
	for c in COLUMNS.size():
		if HEADS[c] != "":
			_text(HEADS[c], 20.0, COLUMNS[c], HEAD_Y)
	var sum := {"perfect": 0, "good": 0, "stars": 0, "total": 0, "best_streak": 0}
	var y := FIRST_ROW_Y
	for info in infos:
		_text(info.letter, 40.0, COLUMNS[0], y, info.theme, true)
		var r = Results.rows.get(info.level)
		var cells := ["-", "-", "-", "-"]
		if r != null and r.has("auto"):
			_text("AUTO", 40.0, (COLUMNS[1] + COLUMNS[-1]) * 0.5, y)
			y += ROW
			continue
		if r != null:
			cells = [str(r.perfect), str(r.good), "%d/%d" % [r.stars, r.total], "x%d" % r.best_streak]
			sum.perfect += r.perfect
			sum.good += r.good
			sum.stars += r.stars
			sum.total += r.total
			sum.best_streak = maxi(sum.best_streak, r.best_streak)
		for c in cells.size():
			_text(cells[c], 40.0, COLUMNS[c + 1], y)
		y += ROW
	_rule = ColorRect.new()
	_rule.color = settings.MENU_INK
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rule)
	_rule_y = y - ROW * 0.5 + 2.0
	y += 6.0
	_text("TOTAL", 40.0, COLUMNS[0], y)
	var totals := ["-", "-", "-", "-"]
	if not Results.counted().is_empty():
		totals = [str(sum.perfect), str(sum.good), "%d/%d" % [sum.stars, sum.total], "x%d" % sum.best_streak]
	for c in totals.size():
		_text(totals[c], 40.0, COLUMNS[c + 1], y)
	if settings.RANK_ON != 0 and not Results.counted().is_empty():
		var acc: float = Results.accuracy()
		# (rounded down, so it never shows the next rank's figure; the sliver: 0.95 * 100 comes out just under 95)
		_text("ACCURACY %d%%" % floori(acc * 100.0 + 0.0001), 40.0, TABLE_MID - 90.0, RANK_Y + 22.0)
		_text("RANK", 40.0, TABLE_MID + 130.0, RANK_Y + 22.0)
		_text(_rank(acc), 120.0, TABLE_MID + 240.0, RANK_Y + 22.0, GOLD, true)
	var press := _text("PRESS", 40.0, 0.0, PROMPT_Y)
	var key := KeyLabel.new()
	key.hud = hud
	key.key = "SPACE"
	add_child(key)
	key.setup(40.0, 1, 8)
	_items.append([key, 0.0, PROMPT_Y])
	var back := _text("TO RETURN", 40.0, 0.0, PROMPT_Y)
	# (laid out as one line, its middle under the table's, in _layout)
	_prompt = [press, key, back]


func _rank(acc: float) -> String:
	if acc >= settings.RANK_S:
		return "S"
	if acc >= settings.RANK_A:
		return "A"
	if acc >= settings.RANK_B:
		return "B"
	return "C"


func _width(l: Label) -> float:
	var fs: int = l.label_settings.font_size
	return hud.font_or_default().get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x - float(fs) / hud.FONT_PX


func _layout() -> void:
	var s: float = hud._px_scale()
	_scale = s
	for f in hud._fits:
		hud._fit(f, s)
	var vp := get_viewport().get_visible_rect().size
	var kx: float = vp.x / 1152.0  # (a wider window: the table keeps its place in it)
	var snap := func(v: float) -> float: return roundf(v * s) / s
	var font: Font = hud.font_or_default()
	record.center = Vector2(RECORD_AT.x * kx, RECORD_AT.y)
	for it in _items:
		var n: Control = it[0]
		if n is Label:
			var fs: int = n.label_settings.font_size
			n.position = Vector2(snap.call(it[1] * kx - _width(n) * 0.5), snap.call(it[2] + font.get_ascent(fs) * CAP * 0.5 - font.get_ascent(fs)))
	var gap := 16.0
	var w0: float = _width(_prompt[0])
	var w1: float = _prompt[1].text_size().x
	var w2: float = _width(_prompt[2])
	var x: float = TABLE_MID * kx - (w0 + gap + w1 + gap + w2) * 0.5
	var fs0: int = _prompt[0].label_settings.font_size
	var y: float = snap.call(PROMPT_Y + font.get_ascent(fs0) * CAP * 0.5 - font.get_ascent(fs0))
	_prompt[0].position = Vector2(snap.call(x), y)
	_prompt[1].position = Vector2(snap.call(x + w0 + gap), y)
	_prompt[2].position = Vector2(snap.call(x + w0 + gap + w1 + gap), y)
	_rule.position = Vector2(snap.call((COLUMNS[0] - 60.0) * kx), snap.call(_rule_y))
	_rule.size = Vector2(snap.call((COLUMNS[-1] - COLUMNS[0] + 120.0) * kx), 2.0 * maxf(1.0, roundf(s)) / s)
	var words := [_rule.get_rect().grow(STAR_CLEAR)]
	for it in _items:
		var n: Control = it[0]
		var box: Vector2 = n.text_size() if n is KeyLabel else n.get_combined_minimum_size()
		words.append(Rect2(n.position, box).grow(STAR_CLEAR))
	_stars.scatter(words, [[record.center, RecordView.RADII[-1] * RECORD_K + STAR_CLEAR]])


func _process(delta: float) -> void:
	if absf(hud._px_scale() - _scale) > 0.001:
		_layout()
	_clock += delta
	var t: float = _clock
	if _music != null and _music.playing:
		t = _music.get_playback_position() + AudioServer.get_time_since_last_mix()
	record.set_pulse(exp(-fposmod(t - _first, _beat) * 6.0))


func _input(event: InputEvent) -> void:
	if _left or Iris.current != null:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_SPACE:
		_left = true
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file("res://scenes/tavern.tscn")


## Where the iris opens from.
func iris_spot() -> Dictionary:
	return record.hero_spot()
