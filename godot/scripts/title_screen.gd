extends Control
## 开始界面: MIDI RUNNER over the nested records (scripts/view/record_view.gd), PRESS [SPACE] TO START under them. SPACE,
## Enter or a click on the prompt start the game: the results so far are forgotten, and the iris closes onto the hero and
## opens on the first level (scripts/view/iris.gd). The last level's song plays quietly meanwhile (TITLE_MUSIC) and the
## records pulse on its beat. MIDI's letters are in the colours of the four inner records, RUNNER in the big one's. Small
## stars twinkle on the background (scripts/view/night_stars.gd).

const Hud := preload("res://scripts/view/hud.gd")
const RecordView := preload("res://scripts/view/record_view.gd")
const KeyLabel := preload("res://scripts/view/key_label.gd")
const Iris := preload("res://scripts/view/iris.gd")
const LevelInfo := preload("res://scripts/core/level_info.gd")
const MenuSettings := preload("res://scripts/core/menu_settings.gd")
const RunState := preload("res://scripts/core/run_state.gd")
const Results := preload("res://scripts/core/results.gd")
const MenuProgress := preload("res://scripts/core/menu_progress.gd")

const NAME := "MIDI RUNNER"
const NAME_SIZE := 120.0        # its letters (canvas units)
const NAME_Y := 46.0            # the middle of its capitals
const PROMPT_SIZE := 40.0
const PROMPT_Y := 604.0
const CAP := 2.0 / 3.0
const WARMED := "WarmedShaders" # the web build: on the tree's root once its loading screen has been (scripts/view/warm_up.gd)
const WARM_LEFTOVERS := 3       # the web build: frames after its loading screen in which a key pressed during it is still let go
const NightStars := preload("res://scripts/view/night_stars.gd")
const STAR_CLEAR := 6.0         # the stars keep this far from the words and the records

var settings
var hud
var record
var _stars
var _music: AudioStreamPlayer
var _name_labels: Array = []
var _press: Label
var _key: Control
var _to: Label
var _beat := 0.5
var _first := 0.0
var _clock := 0.0
var _scale := 0.0
var _started := false
var _prompt_rect := Rect2()
var warming := false            # the web build's loading screen is up (scripts/view/warm_up.gd): no key or click counts


func _ready() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_ICON):  # (Windows: the title bar's and the taskbar's own icons, not the big one scaled down)
		DisplayServer.set_native_icon("res://icon_window.ico")
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
	_stars.count = settings.MENU_STARS
	_stars.light = settings.MENU_STAR_LIGHT
	add_child(_stars)
	move_child(_stars, sky.get_index() + 1)
	if OS.has_feature("web") and not get_tree().root.has_node(WARMED):
		warming = true
		set_process(false)
		var warm_up = load("res://scripts/view/warm_up.gd").new()
		warm_up.kept_name = WARMED
		warm_up.hud = hud
		warm_up.sky = settings.MENU_BG
		warm_up.ink = settings.MENU_INK
		warm_up.build_title = _build
		warm_up.done.connect(_warmed)
		add_child(warm_up)
		return
	_build()
	if _music != null:
		_music.play()


func _build() -> void:
	record = RecordView.new()
	record.hud = hud
	record.sky = settings.MENU_BG
	add_child(record)
	record.setup()
	var infos: Array = LevelInfo.all()
	var last: Dictionary = infos[-1]
	_beat = 60.0 / last.bpm
	_first = last.first_bar_at
	for i in NAME.length():
		var ch := NAME[i]
		var col: Color = infos[i].theme if i < 4 else last.theme  # (MIDI: the inner records; RUNNER: the big one)
		var l := _text(ch, NAME_SIZE, 1, 16)
		l.label_settings.font_color = col
		_name_labels.append(l)
	_press = _text("PRESS", PROMPT_SIZE, 1, 8)
	_to = _text("TO START" if MenuProgress.next_level == 1 else "TO CONTINUE", PROMPT_SIZE, 1, 8)
	for l in [_press, _to]:
		l.label_settings.font_color = settings.MENU_INK
		l.label_settings.outline_color = Color(0, 0, 0, 0)
	_key = KeyLabel.new()
	_key.hud = hud
	_key.key = "SPACE"
	add_child(_key)
	_key.setup(PROMPT_SIZE, 1, 8)
	_layout()
	if settings.TITLE_MUSIC != 0 and last.audio != "" and ResourceLoader.exists(last.audio):
		_music = AudioStreamPlayer.new()
		var stream: AudioStream = load(last.audio).duplicate()  # (looping here only, not when the level plays it)
		stream.set("loop", true)
		_music.stream = stream
		_music.volume_db = settings.TITLE_MUSIC_DB
		add_child(_music)


## The loading screen is gone: the song starts, and the keys count once the ones pressed during it have gone by.
func _warmed() -> void:
	if _music != null:
		_music.play()
	set_process(true)
	for i in WARM_LEFTOVERS:
		await get_tree().process_frame
	warming = false


func _text(s: String, size: float, lo: int, hi: int) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = hud.font_or_default()
	ls.outline_color = hud.OUTLINE
	hud.fit(ls, size, lo, hi)
	l.label_settings = ls
	l.text = s
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _layout() -> void:
	var s: float = hud._px_scale()
	_scale = s
	for f in hud._fits:
		hud._fit(f, s)
	var vp := get_viewport().get_visible_rect().size
	var snap := func(v: float) -> float: return roundf(v * s) / s
	record.center = vp * 0.5
	var font: Font = hud.font_or_default()
	var fs: int = _name_labels[0].label_settings.font_size
	var spacing: float = float(fs) / hud.FONT_PX  # (a pixel of the font between its letters, their outlines touching)
	var w: float = font.get_string_size(NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + spacing * (NAME.length() - 1)
	var x: float = (vp.x - w) * 0.5
	var top: float = snap.call(NAME_Y + font.get_ascent(fs) * CAP * 0.5 - font.get_ascent(fs))
	for i in NAME.length():
		var before: float = font.get_string_size(NAME.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_name_labels[i].position = Vector2(snap.call(x + before + spacing * i), top)
	var pfs: int = _press.label_settings.font_size
	var w1: float = font.get_string_size(_press.text, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs).x
	var w2: float = font.get_string_size(_to.text, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs).x
	var cap: Vector2 = _key.text_size()
	var gap: float = snap.call(pfs * 0.4)
	var px: float = snap.call((vp.x - (w1 + gap + cap.x + gap + w2)) * 0.5)
	var py: float = snap.call(PROMPT_Y + font.get_ascent(pfs) * CAP * 0.5 - font.get_ascent(pfs))
	_press.position = Vector2(px, py)
	_key.position = Vector2(snap.call(px + w1 + gap), py)
	_to.position = Vector2(snap.call(px + w1 + gap + cap.x + gap), py)
	_prompt_rect = Rect2(px, py, w1 + gap + cap.x + gap + w2, pfs * 1.2).grow(10.0)
	var name_box := Rect2(x, top, w, fs * 1.2)
	_stars.scatter([name_box.grow(STAR_CLEAR), _prompt_rect.grow(STAR_CLEAR)], [[record.center, RecordView.RADII[-1] + STAR_CLEAR]])


func _process(delta: float) -> void:
	if absf(hud._px_scale() - _scale) > 0.001:
		_layout()
	_clock += delta
	var t: float = _clock
	if _music != null and _music.playing:
		t = _music.get_playback_position() + AudioServer.get_time_since_last_mix()
	record.set_pulse(exp(-fposmod(t - _first, _beat) * 6.0))


func _input(event: InputEvent) -> void:
	if warming:
		get_viewport().set_input_as_handled()
		return
	if _started and Iris.current != null:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_start()
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and _prompt_rect.has_point(make_input_local(click).position):
		_start()


## The game begins: a fresh set of results, and the iris into the first level.
func _start() -> void:
	_started = true
	get_viewport().set_input_as_handled()
	var level: int = MenuProgress.next_level
	if level == 1:
		Results.reset()
	RunState.clear()
	RunState.intro_due = true
	RunState.tutorial_due = true
	if _music != null:
		create_tween().tween_property(_music, "volume_db", -60.0, settings.IRIS_CLOSE + settings.IRIS_HOLD * 0.5)
	Iris.start(get_tree(), "res://scenes/level_%d.tscn" % level, record.hero_spot)


## Where the iris closes onto.
func iris_spot() -> Dictionary:
	return record.hero_spot()
