extends CanvasLayer
## Title, the lives left (a row of little squares under it), streak, centre messages (start / countdown / fail / win),
## the judgement popup, the speed changes on their own line under it (SPEED UP / SLOW DOWN), the input hints and the
## progress bar along the top.
## The lettering is Upheaval (Brian Kent's free pixel font; upheaval.txt stays next to it), drawn without smoothing. Its
## strokes are one screen pixel at FONT_PX, so every label is kept at a whole multiple of that on screen (the HUD is
## scaled with the window: canvas_items stretch), the one nearest its size in the layout, and its outline a whole
## number of pixels too (the canvas itself is snapped so that this can be: _snap_canvas). In the input hints each key in brackets is in its own colour (scripts/view/key_label.gd: the
## tint the intro panel gives it) and the words for what to do in ACTION_COLOR, the same in every level.

const FONT_PATH := "res://assets/fonts/upheaval/upheavtt.ttf"
const FONT_PX := 20             # Upheaval's own size: sharp at 20, 40, 60 ... screen pixels
const CANVAS := Vector2(1152.0, 648.0)  # the layout's canvas: the smallest it gets (_snap_canvas)
const OUTLINE := Color(0, 0, 0, 0.85)  # the judgement popup's and the press prompts' outline
const ACTION_COLOR := Color("#FFA64D")  # the hints' words for what to do (orange: gold, white and red are the judgements', blue, green and violet the keys')
const TITLE_CLEAR := 60.0       # the streak's room from the window's side and its gap from the title (canvas units)
const SMALL_SIZE := 30.0        # a size in the layout under this is the small lettering: the title, the streak, the hints
const KeyLabel := preload("res://scripts/view/key_label.gd")
const Dev := preload("res://scripts/core/dev.gd")

var L
var font: FontFile
var dev: SystemFont
var title: Label
var score: Label
var center: Label
var popup_label: Label
var speed_label: Label          # SPEED UP / SLOW DOWN, a line under the judgement popup (both may show at once)
var speed_left := 0.0
var count: Label
var hint: RichTextLabel
var progress: ColorRect
var bar_bg: ColorRect
var life_fills: Array = []      # one inner square per life: the level's colour while it is left, empty once lost
var life_edges: Array = []
var popup_left := 0.0
var last_mult := 1.0
var _fits: Array = []           # {ls, size (in the layout, canvas units), lo, hi (multiples of FONT_PX), k (now)}
var _scale := 0.0               # screen pixels per canvas unit the sizes are fitted for
var _title_fit := {}
var _score_fit := {}
var _title_full := ""           # the title line,
var _title_short := ""          # without its "(Training: Theme ...)" (see _refit)
var _fit_autoplay := false      # whether "Autoplay" showed by the streak when the title was fitted
var _hint_ls := LabelSettings.new()  # the hints' lettering's size (kept fitted like a label's)
var _hints_plain := ""          # the hints shown, as the mechanics wrote them
var _hints_t := 0.0             # how long this attempt has been in play (a level reloads, and this with it, on a lost life)
var _marks := RegEx.create_from_string("(?i)\\[(SPACE|SHIFT|S)\\]|\\b(dash|jump|slam|slide|flip|hold|release|ride)\\b")


func _enter_tree() -> void:
	_snap_canvas()
	get_window().size_changed.connect(_snap_canvas)


## The players' lettering: the pixel font, unsmoothed.
func font_or_default() -> Font:
	if font == null:
		if ResourceLoader.exists(FONT_PATH):
			font = (load(FONT_PATH) as FontFile).duplicate()
		else:  # not imported yet: read the file directly
			font = FontFile.new()
			font.load_dynamic_font(ProjectSettings.globalize_path(FONT_PATH))
		font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		font.hinting = TextServer.HINTING_NONE
		font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		font.generate_mipmaps = false
	return font


## The developer tools' lettering (the tune mode, the Tab labels: they are in Chinese): a system font.
func dev_font() -> Font:
	if dev == null:
		dev = SystemFont.new()
		dev.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "PingFang SC", "sans-serif"])
	return dev


## Keep the lettering of ls at the whole multiple of FONT_PX on screen nearest `size` (canvas units), from lo to hi
## multiples.
func fit(ls: LabelSettings, size: float, lo: int, hi: int) -> Dictionary:
	var f := {"ls": ls, "size": size, "lo": lo, "hi": hi, "k": lo}
	_fits.append(f)
	_fit(f, _px_scale())
	return f


func _fit(f: Dictionary, s: float) -> void:
	f.k = clampi(roundi(f.size * s / FONT_PX), f.lo, f.hi)
	_set_k(f, f.k, s)


func _set_k(f: Dictionary, k: int, s: float) -> void:
	f.k = k
	f.ls.font_size = maxi(1, roundi(k * FONT_PX / s))
	f.ls.outline_size = outline_for(k, s, f.size < SMALL_SIZE and k > 1)


## An outline of two of the font's pixels, for k multiples of FONT_PX at scale s. The font makes it at the whole screen
## pixels it comes to, rounded down (and with the scale in 64ths), so it is rounded up here: anything less than that loses it
## altogether on a window of another size. Doubled for the small lettering doubled by a big window (`thick`): the same size
## of outline against twice the letter is half as strong as what it has at the editor's window, over the same pale sky.
static func outline_for(k: int, s: float, thick := false) -> int:
	return maxi(1, ceili((4.0 if thick else 2.0) * k / (floorf(s * 64.0) / 64.0)))


## The canvas for this window (a browser's can be any size): a little bigger than the layout's where it must be, so that
## FONT_PX on screen is a whole number of canvas units. Sizes in between (19.5 screen pixels: a font size is a whole number
## of canvas units) break the pixel font's strokes up. At the editor's window, or any of the same shape at a scale that
## divides FONT_PX (1920x1080, 2560x1440), it is the layout's own.
func _snap_canvas() -> void:
	var w: Vector2i = get_window().size
	if w.x <= 0 or w.y <= 0:
		return
	var n: int = ceili(FONT_PX / minf(w.x / CANVAS.x, w.y / CANVAS.y) - 0.0001)
	var want := Vector2i(w.x * n / FONT_PX, roundi(float(w.y * n) / FONT_PX))  # (the width rounded down: the height is what it keeps exactly)
	if get_window().content_scale_size != want:
		get_window().content_scale_size = want
	# (the font is drawn at a size in 64ths of the scale, a hair under FONT_PX, which loses some of its one-pixel strokes: made up here)
	var fit_up: float = FONT_PX / (n * floorf(float(w.y) / want.y * 64.0) / 64.0)
	font_or_default()
	font.set_transform(0, Transform2D.IDENTITY.scaled(Vector2(fit_up, fit_up)))


## Screen pixels per canvas unit.
func _px_scale() -> float:
	var vis: float = get_viewport().get_visible_rect().size.y
	var win: float = get_window().size.y
	return win / vis if vis > 0.0 and win > 0.0 else 1.0


## Every label fitted again for scale s. The title, centred on the window, and the streak on the right the same size:
## while they would run into each other, the title without its "(Training: Theme ...)", then moved left just enough, and
## a size down only if there is no room on its left for that.
func _refit(s: float) -> void:
	_scale = s
	for f in _fits:
		_fit(f, s)
	hint.add_theme_font_size_override("normal_font_size", _hint_ls.font_size)
	hint.add_theme_constant_override("outline_size", _hint_ls.outline_size)
	_fit_autoplay = _autoplay_shows()
	var k: int = mini(_title_fit.k, _score_fit.k)
	while true:
		_set_k(_title_fit, k, s)
		_set_k(_score_fit, k, s)
		title.text = _title_full
		if _title_over() > 0.0:
			title.text = _title_short
		if k <= _title_fit.lo or _title_over() <= _title_spare():
			break
		k -= 1
	title.offset_right = -20.0 - 2.0 * maxf(0.0, _title_over())


## How far the title, centred on the window, would run into the room the streak needs (a long one: two digits);
## negative: it stays clear by that much.
func _title_over() -> float:
	var widest: String = ("Autoplay   " if _autoplay_shows() else "") + "Streak x00   Best x00"
	var w_title: float = font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.label_settings.font_size).x
	var w_score: float = font.get_string_size(widest, HORIZONTAL_ALIGNMENT_LEFT, -1, score.label_settings.font_size).x
	return w_title * 0.5 + w_score - (get_viewport().get_visible_rect().size.x * 0.5 - TITLE_CLEAR)


## How far the title, centred on the window, can move left and still be off the window's edge.
func _title_spare() -> float:
	var w_title: float = font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.label_settings.font_size).x
	return (get_viewport().get_visible_rect().size.x - w_title) * 0.5 - 20.0


## "Autoplay" by the streak: the developer's only.
func _autoplay_shows() -> bool:
	return L.autoplay and Dev.on()


## The hints have faded out, for the rest of this attempt.
func hints_gone() -> bool:
	return _hints_t >= L.HINT_SHOW + maxf(0.001, L.HINT_FADE)


## The input hints (mechanic.tips, as they wrote them; none on the win and fail screens).
func set_hints(tips: Array) -> void:
	var plain := "    ".join(tips)
	if plain != _hints_plain:
		_hints_plain = plain
		hint.text = _marked(plain)


## The hints marked up for the label: each key in brackets in its colour, the words for what to do in ACTION_COLOR, both
## with the prompts' darker outline (the orange has to read over level 1's orange pillars).
func _marked(plain: String) -> String:
	var dark: String = "[outline_color=#%s]" % OUTLINE.to_html(true)
	var out := ""
	var at := 0
	for m in _marks.search_all(plain):
		out += plain.substr(at, m.get_start() - at)
		var key: String = m.get_string(1)
		if key != "":
			var c: Array = KeyLabel.colors_of(key)
			out += dark + "[color=#%s][lb]%s[rb][/color][/outline_color]" % [c[0].lerp(c[1], 0.45).to_html(false), key]
		else:
			out += dark + "[color=#%s]%s[/color][/outline_color]" % [ACTION_COLOR.to_html(false), m.get_string(2)]
		at = m.get_end()
	return out + plain.substr(at)


func setup(tips: Array) -> void:
	var d: Dictionary = L.data
	title = _label(22, 1, 2, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP)
	_title_fit = _fits[-1]
	title.label_settings.outline_color = OUTLINE  # (readable over a pale sky, like the popup)
	_title_short = "Level %d - %s - %s" % [d.level, d.letter, d.song]
	_title_full = _title_short + (" (Final)" if d.get("final", false) else " (Training: Theme %s)" % d.section)
	title.text = _title_full
	score = _label(22, 1, 2, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_TOP)
	_score_fit = _fits[-1]
	score.label_settings.outline_color = OUTLINE
	center = _label(40, 2, 3, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	popup_label = _label(34, 2, 3, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP)
	popup_label.offset_top = 140.0  # (below the title row: the press prompts go between them)
	popup_label.label_settings.outline_color = OUTLINE  # (readable over a pale sky too, like the press prompts)
	speed_label = _label(34, 2, 3, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP)
	speed_label.label_settings.outline_color = OUTLINE
	for l in [center, popup_label]:  # a long fail reason / hint wraps within the middle 80 % of the screen
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.anchor_left = 0.1
		l.anchor_right = 0.9
		l.offset_left = 0.0
		l.offset_right = 0.0
	count = _label(84, 3, 6, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP)  # the count-in, above the run (not on it)
	count.offset_top = 200.0
	count.label_settings.outline_color = Color(0, 0, 0, 0.75)
	hint = RichTextLabel.new()
	hint.bbcode_enabled = true
	hint.scroll_active = false
	hint.clip_contents = false
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM  # (however many lines the hints take, up from the bottom)
	hint.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_override("normal_font", font_or_default())
	hint.add_theme_color_override("default_color", Color.WHITE)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	hint.add_theme_constant_override("line_separation", 3)
	add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.offset_left = 20.0
	hint.offset_right = -20.0
	hint.offset_top = 16.0
	hint.offset_bottom = -14.0
	fit(_hint_ls, 22, 1, 2)
	set_hints(tips)
	bar_bg = ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.25)
	bar_bg.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar_bg.offset_bottom = 6.0
	add_child(bar_bg)
	progress = ColorRect.new()
	progress.color = Color(1.0, 0.45, 0.35)
	progress.size = Vector2(0, 6)
	add_child(progress)
	# lives: a dark outlined square each (about five art pixels wide), filled while the life is left, hollow once lost
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	frame.border_color = Color(0.1, 0.1, 0.14, 0.75)
	frame.set_border_width_all(4)
	for i in int(L.LIVES):
		var edge := Panel.new()
		edge.add_theme_stylebox_override("panel", frame)
		edge.position = Vector2(22.0 + i * 30.0, 56.0)
		edge.size = Vector2(22.0, 22.0)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(edge)
		life_edges.append(edge)
		var fill := ColorRect.new()
		fill.position = Vector2(4.0, 4.0)
		fill.size = Vector2(14.0, 14.0)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		edge.add_child(fill)
		life_fills.append(fill)
	_refit(_px_scale())


func say(text: String) -> void:
	center.text = text


func popup(text: String, color: Color) -> void:
	popup_label.text = text
	popup_label.modulate = color
	popup_left = 0.6


func clear_popup() -> void:
	popup_left = 0.0
	popup_label.text = ""


## A speed change, on its line under the judgement popup.
func speed(text: String, color: Color) -> void:
	speed_label.text = text
	speed_label.modulate = color
	speed_left = 0.6


func update(delta: float) -> void:
	var s := _px_scale()
	if absf(s - _scale) > 0.001 or _autoplay_shows() != _fit_autoplay:  # (the window was resized, or Autoplay shows now)
		_refit(s)
	if L.state == "play":
		_hints_t += delta
	hint.modulate.a = 1.0 - clampf((_hints_t - L.HINT_SHOW) / maxf(0.001, L.HINT_FADE), 0.0, 1.0)
	score.text = "%sStreak x%d   Best x%d" % ["Autoplay   " if _autoplay_shows() else "", L.streak, L.best_streak]
	# (the title card and the tutorial alone: no top bar, no hints)
	var bare: bool = L.state == "title" or L.state == "tutorial" or (L.state == "ready" and L.tutorial != null)
	for c in [title, score, hint, progress, bar_bg, speed_label] + life_edges:
		c.visible = not bare
	if L.state == "countdown":  # (carrying on, the beats it stands still count too: 3, 2 while still, 1 running)
		var n := int(ceil((L.countdown_to - L.now + L.freeze_left) / L.beat - 0.001))
		say("")
		count.text = str(n) if n > 0 and n <= 3 else ""  # (a longer run-up just runs: it is always 3, 2, 1)
	else:
		count.text = ""
	for i in life_fills.size():
		life_fills[i].color = L.theme_color if i < L.lives else Color(0.0, 0.0, 0.0, 0.0)
	var vp := get_viewport().get_visible_rect().size
	progress.size = Vector2(vp.x * clampf(L.now / L.data.dur, 0.0, 1.0), 6.0)
	if popup_left > 0.0:
		popup_left -= delta
		popup_label.modulate.a = clampf(popup_left / 0.25, 0.0, 1.0)
	speed_left = maxf(0.0, speed_left - delta)
	speed_label.modulate.a = clampf(speed_left / 0.25, 0.0, 1.0)
	# (under the judgement line, a clear 20 screen pixels below it)
	speed_label.offset_top = popup_label.offset_top + popup_label.label_settings.font_size * 1.2 + 20.0 / s
	# 5-6: tell the player when the section speed changes: up (a boost bar starting too), and down only where the song
	# really calms (6b / 6e), not where a boost bar ends and the run goes back to its speed
	if L.state == "play":
		var m: float = L.track.mult_at(L.now)
		if m > last_mult + 0.08:
			speed("SPEED UP >>", Color(0.6, 1.0, 0.7))
			last_mult = m
		elif m < last_mult - 0.08:
			var now: float = L.now
			if L.data.events.any(func(e): return e.branch in ["6b", "6e"] and absf(e.t - now) <= 0.5):
				speed("SLOW DOWN <<", Color(0.7, 0.85, 1.0))
			last_mult = m


## A label for text about `size` big in the layout (canvas units), kept at lo to hi multiples of FONT_PX on screen.
func _label(size: int, lo: int, hi: int, h: HorizontalAlignment, v: VerticalAlignment) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = font_or_default()
	ls.outline_color = Color(0, 0, 0, 0.55)
	fit(ls, size, lo, hi)
	l.label_settings = ls
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # (the font's pixels stay whole pixels)
	l.horizontal_alignment = h
	l.vertical_alignment = v
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.offset_left = 20.0
	l.offset_right = -20.0
	l.offset_top = 16.0
	l.offset_bottom = -14.0
	return l
