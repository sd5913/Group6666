extends Control
## 开场机关面板 (INTRO_PANEL): on a level's ready screen, the first time the level is entered (not again after R or a
## lost life), a pixel panel of the six families of mechanics, by what the player does — two rows of three, a 16×16
## icon each, drawn here from the strings below at a whole number of screen pixels a cell (4 at 1080p, 2 at 720p). A
## family the level has (anything of one of its mechanics planned) shows in its key's colour (KEY_OF: DASH the SHIFT
## green; JUMP, RIDE, FLIP the SPACE blue; SLAM, SLIDE the S violet — scripts/view/key_label.gd, as the press prompts
## have them, so the panel teaches the colours), its name under it, its key in brackets in those colours, and what to do
## — the line of the level's first mechanic of the family that has something (mechanic.panel_caption), its key's name
## taken out (the bracketed key says it): level 1's dashes are through closing pillars and across gaps, level 4's smash blocks
## and fired walls. Beside its icon, small drawings of the very objects the level has in the family
## (mechanic.panel_sprites: 12 × 12 art pixels each in their colours here; at most SPRITES_MAX, the ones the player
## meets first, in that order; a whole number of screen pixels an art pixel — 2 at 720p and 1080p, never fewer — with a
## one-pixel dark outline, SPRITE_GAP_PX apart), no words; the icon and they centred in the column together. One it
## hasn't, a grey silhouette with nothing written. PRESS [SPACE] TO START under them; the panel as wide as that takes
## (with its outline no wider than FIT_W of the window: the lines wrap sooner in a small window, where the letters, kept
## at whole multiples of the font's size on screen, take more of it), between the HUD's lives row and its hints (closer
## together, TIGHT, where it hasn't the room there as it is). Filled with
## the level's colour darkened to FILL_V of its brightness, a little see-through (FILL_A); a pixel frame round it in a
## light shade of that colour, as thick as an icon's cell (2 screen pixels at 720p, 4 at 1080p), one of its pixels
## notched off each corner, and as thick a dark outline outside it. When SPACE starts the count-in it fades out over
## FADE_T. Visual only: it touches nothing in the play.

const FADE_T := 0.2
const KeyLabel := preload("res://scripts/view/key_label.gd")
const KEY_OF := {"DASH": "SHIFT", "JUMP": "SPACE", "RIDE": "SPACE", "SLAM": "S", "SLIDE": "S", "FLIP": "SPACE"}
const FAMILIES := [
	{"id": "DASH", "icon": [
		"................",
		"................",
		"..........##.###",
		"..........##.###",
		"+...+.....######",
		"++..++....###.##",
		".++..++...###.##",
		"..++..++..######",
		"..++..++..######",
		".++..++...##.###",
		"++..++....##.###",
		"+...+.....######",
		"..........###.##",
		"..........###.##",
		"................",
		"................"]},
	{"id": "JUMP", "icon": [
		".......++.......",
		"......++++......",
		".....++++++.....",
		"....++.++.++....",
		".......++.......",
		".......++.......",
		"................",
		".....######.....",
		"....########....",
		"....##++++##....",
		"....##++++##....",
		"....########....",
		".....######.....",
		"................",
		"################",
		"################"]},
	{"id": "RIDE", "icon": [
		"................",
		"................",
		"......####......",
		".....##++##.....",
		".....#++++#.....",
		".....##++##.....",
		"......####......",
		"................",
		"##............##",
		"####........####",
		"..####....####..",
		"....########....",
		"......####......",
		"................",
		"................",
		"................"]},
	{"id": "SLAM", "icon": [
		"......++++......",
		"......++++......",
		"......++++......",
		"......++++......",
		"...++++++++++...",
		"....++++++++....",
		".....++++++.....",
		"......++++......",
		".......++.......",
		"................",
		"###..........###",
		"###..........###",
		"###.########.###",
		"###.########.###",
		"###..........###",
		"###..........###"]},
	{"id": "SLIDE", "icon": [
		"##..##..##..##..",
		"##..##..##..##..",
		"##..##..##..##..",
		"##..##..##..##..",
		"................",
		"................",
		"................",
		"................",
		"................",
		"..##########....",
		".##++++++++##...",
		".##++++++++##...",
		"..##########....",
		"................",
		"################",
		"################"]},
	{"id": "FLIP", "icon": [
		"....++..........",
		"...++++.........",
		"..++++++........",
		"....++..........",
		"....++..........",
		"....++..........",
		"................",
		"################",
		"################",
		"................",
		"..........++....",
		"..........++....",
		"..........++....",
		"........++++++..",
		".........++++...",
		"..........++...."]},
]
const CAPTION_EMS := 18.0       # a family's line wraps at this many times its letters' size (about 30 letters)
const SPRITES_MAX := 3          # a family's drawings of its objects: at most this many (the first met),
const SPRITE_GAP_PX := 8        # this far apart, and from its icon (screen pixels)
# the panel's padding, the gaps, the room kept clear at the window's sides and round the HUD (canvas units)
const PAD := 24.0
const GAP := 10.0
const ROW_GAP := 26.0
const PRESS_GAP := 10.0         # (and a line's room) over PRESS [SPACE] TO START
const TIGHT := {"pad": 14.0, "row_gap": 12.0, "press_gap": 0.0}  # the same, where the panel hasn't the room as it is
const FIT_W := 0.92             # the panel with its outline: at most this much of the window's width
const HUD_CLEAR := 8.0
const FILL_V := 0.22            # the fill: the level's colour at this much of its brightness,
const FILL_A := 0.92            # this opaque (the scene shows through a little)
const FRAME_LIGHT := 0.55       # the frame: the level's colour lightened this much
const SHADOW := Color(0.5, 0.5, 0.56, 1.0)  # an absent family's silhouette (grey, light enough to show on the fill)

var L
var hud
var present := {}               # family id -> what to do, where the level has one
var _col := 300.0               # a family's column (canvas units)
var _titles: Array = []
var _lines: Array = []
var _caps: Array = []           # each family's bracketed key (shown where the level has it)
var _start: Label               # PRESS ... TO START, round the bracketed SPACE
var _start_end: Label
var _start_cap: Control
var _scale := 0.0               # screen pixels per canvas unit the layout is for
var _cell := 3.0                # an icon cell (canvas units: a whole number of screen pixels)
var _unit := 1.0                # a pixel of the frame (canvas units: an icon's cell)
var _hint_lines := -1           # the HUD's hints' lines the layout kept clear of
var _box := Rect2()
var _icons: Array = []          # each family's icon's top left corner
var _sprites := {}              # family id -> its objects' drawings ({t, rows, palette}), the first met first
var _sprite_at: Array = []      # each family's drawings' row (beside its icon): its top left corner
var _art := 2.0                 # an art pixel of the drawings (canvas units: a whole number of screen pixels)
var _fade := 1.0


func setup() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in L.mechanics:  # (in the level's order: its first mechanic of a family says what to do)
		var caps: Dictionary = m.panel_caption()
		for fam in caps:
			if not present.has(fam):
				present[fam] = caps[fam]
	var all := []
	for m in L.mechanics:
		all.append_array(m.panel_sprites().filter(func(sp): return present.has(sp.family)))
	all.sort_custom(func(a, b): return a.t < b.t)  # (the ones the player meets first)
	for sp in all:
		if _sprites.get(sp.family, []).size() < SPRITES_MAX:
			if not _sprites.has(sp.family):
				_sprites[sp.family] = []
			_sprites[sp.family].append(sp)
	var keys_named := RegEx.create_from_string("\\s*\\((SPACE|SHIFT|S)\\)|\\b(SPACE|SHIFT)\\s+")
	for fam in FAMILIES:
		var title := _text(fam.id, 30.0, 2, 2)
		var line := _text(keys_named.sub(present.get(fam.id, ""), "", true), 12.0)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.modulate = Color(1, 1, 1, 0.85)
		title.visible = present.has(fam.id)
		line.visible = present.has(fam.id)
		title.label_settings.font_color = KeyLabel.colors_of(KEY_OF[fam.id])[0]
		_titles.append(title)
		_lines.append(line)
		_caps.append(_key(KEY_OF[fam.id], 12.0, 1))
		_caps[-1].visible = present.has(fam.id)
	_start = _text("PRESS", 30.0, 2, 2)
	_start_end = _text("TO START", 30.0, 2, 2)
	_start_cap = _key("SPACE", 30.0, 2)
	_layout()


## A key in brackets in its colours, about `size` big at k times the pixel font's size on screen.
func _key(key: String, size: float, k: int) -> Control:
	var l := KeyLabel.new()
	l.hud = hud
	l.key = key
	add_child(l)
	l.setup(size, k, k)
	return l


func _text(s: String, size: float, lo := 1, hi := 1) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = hud.font_or_default()
	ls.outline_color = Color(0, 0, 0, 0.0)
	hud.fit(ls, size, lo, hi)
	l.label_settings = ls
	l.text = s
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## Where everything goes for the window's size now: columns as wide as the widest name or line (a long line wraps at
## CAPTION_EMS letters' sizes), centred, every edge on a whole screen pixel.
func _layout() -> void:
	_scale = hud._px_scale()
	var s := _scale
	var snap := func(v: float) -> float: return roundf(v * s) / s
	var cell_px: int = clampi(floori(get_window().size.y / 270.0), 2, 8)  # (4 screen pixels a cell at 1080p, 2 at 720p)
	_cell = cell_px / s
	_unit = _cell
	var icon: float = 16.0 * _cell
	var font: Font = hud.font_or_default()
	var vp := get_viewport().get_visible_rect().size
	var col_max: float = (FIT_W * vp.x - 2.0 * _unit - 2.0 * PAD) / 3.0
	var widest := icon
	var cap_w: float = minf(CAPTION_EMS * _lines[0].label_settings.font_size, col_max - 2.0 * GAP)
	for i in FAMILIES.size():
		widest = maxf(widest, font.get_string_size(_titles[i].text, HORIZONTAL_ALIGNMENT_LEFT, -1, _titles[i].label_settings.font_size).x)
		var w: float = font.get_string_size(_lines[i].text, HORIZONTAL_ALIGNMENT_LEFT, -1, _lines[i].label_settings.font_size).x
		widest = maxf(widest, minf(w, cap_w))
	var th: float = _titles[0].label_settings.font_size * 1.2
	var lh: float = _lines[0].label_settings.font_size * 1.25
	var ch: float = _caps[0].text_size().y
	_art = maxi(2, floori(get_window().size.y / 540.0)) / s  # (2 screen pixels an art pixel at 720p and 1080p)
	for i in FAMILIES.size():  # (the column also as wide as the icon with its drawings beside it)
		var n: int = _sprites.get(FAMILIES[i].id, []).size()
		widest = maxf(widest, icon + n * (12.0 * _art + SPRITE_GAP_PX / s))
	_col = minf(widest + 2.0 * GAP, col_max)
	var lines := [1, 1]  # (each row's lines of what to do, wrapped as wide as the column has them)
	for i in FAMILIES.size():
		var fs: int = _lines[i].label_settings.font_size
		var wrapped: Vector2 = font.get_multiline_string_size(_lines[i].text, HORIZONTAL_ALIGNMENT_LEFT, _col - 2.0 * GAP, fs)
		lines[i / 3] = maxi(lines[i / 3], roundi(wrapped.y / font.get_height(fs)))
	var block := [0.0, 0.0]
	for r in 2:
		block[r] = icon + GAP + th + 6.0 + ch + 8.0 + lines[r] * lh
	var sh: float = _start.label_settings.font_size * 1.2
	# up and down: in the middle of the room between the lives row and the hints (closer together where it hasn't that
	# room as it is); still without it, just under the lives row (over the hints), but in the window
	var top: float = HUD_CLEAR + _unit
	if not hud.life_edges.is_empty():
		top += hud.life_edges[0].position.y + hud.life_edges[0].size.y
	_hint_lines = hud.hint.get_line_count() if hud.hint.visible and hud.hint.text != "" else 0
	var hints_h: float = float(hud.hint.get_content_height()) if _hint_lines > 0 else 0.0
	var bottom: float = vp.y + hud.hint.offset_bottom - hints_h - HUD_CLEAR - _unit
	var gaps := {"pad": PAD, "row_gap": ROW_GAP, "press_gap": PRESS_GAP}
	var size := Vector2.ZERO
	for g in [gaps, TIGHT]:
		gaps = g
		size = Vector2(3.0 * _col + 2.0 * gaps.pad, gaps.pad + block[0] + gaps.row_gap + block[1] + gaps.press_gap + lh + sh + gaps.pad)  # (a line's room over the last one)
		if size.y <= bottom - top:
			break
	var y_at: float = top + (bottom - top - size.y) * 0.5 if bottom - top >= size.y else minf(top, vp.y - _unit - size.y)
	var at := Vector2(snap.call((vp.x - size.x) * 0.5), snap.call(maxf(_unit, y_at)))
	_box = Rect2(at, Vector2(snap.call(size.x), snap.call(size.y)))
	_icons.clear()
	_sprite_at.clear()
	for i in FAMILIES.size():
		var col := i % 3
		var row := i / 3
		var x0: float = at.x + gaps.pad + col * _col
		var y0: float = at.y + gaps.pad + (block[0] + gaps.row_gap if row == 1 else 0.0)
		var n: int = _sprites.get(FAMILIES[i].id, []).size()
		var row_w: float = n * (12.0 * _art + SPRITE_GAP_PX / s)  # (the drawings beside the icon, a gap before each)
		var ix: float = snap.call(x0 + (_col - icon - row_w) * 0.5)
		_icons.append(Vector2(ix, snap.call(y0)))
		_sprite_at.append(Vector2(snap.call(ix + icon + SPRITE_GAP_PX / s), snap.call(y0 + (icon - 12.0 * _art) * 0.5)))
		_titles[i].position = Vector2(x0, snap.call(y0 + icon + GAP))
		_titles[i].size = Vector2(_col, th)
		var cw: float = _caps[i].text_size().x
		_caps[i].position = Vector2(snap.call(x0 + (_col - cw) * 0.5), snap.call(y0 + icon + GAP + th + 6.0))
		_lines[i].position = Vector2(x0 + GAP, snap.call(y0 + icon + GAP + th + 6.0 + ch + 8.0))
		_lines[i].custom_minimum_size = Vector2(_col - 2.0 * GAP, 0.0)  # (wrapping within the column)
		_lines[i].size = Vector2(_col - 2.0 * GAP, lines[row] * lh)

	# PRESS [SPACE] TO START, centred as one line, the bracketed key on the words' line
	var sfs: int = _start.label_settings.font_size
	var w1: float = font.get_string_size(_start.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
	var w2: float = font.get_string_size(_start_end.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
	var cap: Vector2 = _start_cap.text_size()
	var space: float = snap.call(sfs * 0.4)
	var x: float = snap.call(at.x + (size.x - (w1 + space + cap.x + space + w2)) * 0.5)
	var y: float = snap.call(at.y + size.y - gaps.pad - sh)
	for l in [_start, _start_end]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.size = Vector2(maxf(w1, w2) + 4.0, sh)
	_start.position = Vector2(x, y)
	_start_cap.position = Vector2(snap.call(x + w1 + space), y)
	_start_end.position = Vector2(snap.call(x + w1 + space + cap.x + space), y)
	queue_redraw()


func _process(delta: float) -> void:
	var hint_lines: int = hud.hint.get_line_count() if hud.hint.visible and hud.hint.text != "" else 0
	if absf(hud._px_scale() - _scale) > 0.001 or hint_lines != _hint_lines:  # (the window was resized, the hints rewrapped)
		_layout()
	if L.state != "ready":
		_fade -= delta / FADE_T
		modulate.a = clampf(_fade, 0.0, 1.0)
		if _fade <= 0.0:
			queue_free()


## The panel in the level's colour, its frame and the frame's outline (nothing drawn twice: the fill is see-through),
## and the icons cell by cell.
func _draw() -> void:
	var px: float = 1.0 / _scale
	var u: float = _unit
	var p: Vector2 = _box.position
	var w: float = _box.size.x
	var h: float = _box.size.y
	var fill: Color = L.theme_color.darkened(1.0 - FILL_V)
	fill.a = FILL_A
	draw_rect(_box.grow(-u), fill)
	var light: Color = L.theme_color.lightened(FRAME_LIGHT)
	for r in [Rect2(p.x + u, p.y, w - 2.0 * u, u), Rect2(p.x + u, p.y + h - u, w - 2.0 * u, u),
			Rect2(p.x, p.y + u, u, h - 2.0 * u), Rect2(p.x + w - u, p.y + u, u, h - 2.0 * u)]:
		draw_rect(r, light)  # (the frame, its corners notched)
	for r in [Rect2(p.x + u, p.y - u, w - 2.0 * u, u), Rect2(p.x + u, p.y + h, w - 2.0 * u, u),
			Rect2(p.x - u, p.y + u, u, h - 2.0 * u), Rect2(p.x + w, p.y + u, u, h - 2.0 * u),
			Rect2(p.x, p.y, u, u), Rect2(p.x + w - u, p.y, u, u), Rect2(p.x, p.y + h - u, u, u), Rect2(p.x + w - u, p.y + h - u, u, u)]:
		draw_rect(r, hud.OUTLINE)  # (its outline, round the notches)
	for i in FAMILIES.size():
		var lit: bool = present.has(FAMILIES[i].id)
		var rows: Array = FAMILIES[i].icon
		var kc: Array = KeyLabel.colors_of(KEY_OF[FAMILIES[i].id])
		var tint: Color = kc[0].lerp(kc[1], 0.45)  # (its key's colour, between its top and bottom ones)
		for r in 16:
			for c in 16:
				var ch: String = rows[r][c]
				if ch == ".":
					continue
				var col: Color = SHADOW if not lit else (tint if ch == "#" else Color(1, 1, 1))
				draw_rect(Rect2(_icons[i] + Vector2(c, r) * _cell, Vector2(_cell, _cell)), col)
		if lit:
			var at: Vector2 = _sprite_at[i]
			for sp in _sprites.get(FAMILIES[i].id, []):
				_draw_sprite(sp, at, px)
				at.x += 12.0 * _art + SPRITE_GAP_PX * px


## One of a family's drawings, its top left at `at`: a dark pixel round every art pixel of it first (its outline),
## then the art pixels in their colours.
func _draw_sprite(sp: Dictionary, at: Vector2, px: float) -> void:
	var dark: Color = hud.OUTLINE
	for pass_i in 2:
		for r in 12:
			var row: String = sp.rows[r]
			for c in 12:
				var ch: String = row[c]
				if ch == ".":
					continue
				var cell := Rect2(at + Vector2(c, r) * _art, Vector2(_art, _art))
				if pass_i == 0:
					draw_rect(cell.grow(px), dark)
				else:
					draw_rect(cell, sp.palette.get(ch, Color.MAGENTA))
