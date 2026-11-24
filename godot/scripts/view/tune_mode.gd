extends Node3D
## 调整模式 (T, from the start screen, the count-in or the run): the song clock stops and is moved by hand — ← → a beat,
## Shift a bar, Ctrl a quarter beat, Home / End to the ends. The player stands where a perfect run is at that moment and
## every mechanic shows that moment. Each star is labelled with its time, its checkpoint (↩) and a green ghost of the
## player where a lost life carries on from; red if it can't save (no plain beat before it), orange if it saves nothing
## new (its checkpoint is less than CHECKPOINT_MIN_GAIN beats after the last one), purple if a mechanic's block hides
## it. N puts a star on the lead note nearest the moment,
## Backspace / Delete removes the nearest one (within a bar), [ ] moves it to the lead note before / after; C copies the
## star times for STAR_T in config/tuning.csv. Enter runs from here, T leaves from where it came in — both the lost-life
## way: the level reloads and carries on from the checkpoint before that moment, the edited stars kept (until R).
## The labels are drawn over the picture (after the pixel look, so they stay readable), each following its star or
## ghost on screen; the lines of text sit on a dark panel at the top or the bottom of the screen, wherever it covers
## less of the player and the stars' labels, so they stay clear.

const RunState := preload("res://scripts/core/run_state.gd")

const GREEN := Color(0.35, 1.0, 0.45)
const RED := Color(1.0, 0.3, 0.3)
const ORANGE := Color(1.0, 0.65, 0.25)
const PURPLE := Color(0.8, 0.45, 1.0)
const TOP_Y := 130.0            # the panel's top under the lives (pixels), with the player in the lower half,
const BOTTOM_Y := 48.0          # or its bottom over the input hints, with the player in the upper half

var L
var entered_t := 0.0
var edited := false
var _marks: Array = []          # label / ghost nodes for the stars
var _tags: Array = []           # [Label, the point it hangs over (world)]
var _spots: Array = []          # every label's and ghost's point (world): what the panel keeps clear of
var _ui: CanvasLayer
var _tag_box: Control
var _panel: PanelContainer
var _at_top := true
var _lines: VBoxContainer
var _info: Label
var _star_line: Label
var _ghost_mat: StandardMaterial3D


func _ready() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	_ui.visible = false
	add_child(_ui)
	_tag_box = Control.new()
	_tag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_tag_box)
	_tag_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", box)
	_ui.add_child(_panel)
	_panel.anchor_left = 0.05
	_panel.anchor_right = 0.95
	_lines = VBoxContainer.new()  # (the lines stacked, however many each wraps into)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_lines)
	_place(true)
	_info = _line(22)
	_star_line = _line(20)
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.albedo_color = Color(GREEN, 0.35)
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _line(size: int) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = L.hud.dev_font()
	ls.font_size = size
	ls.outline_size = 6
	ls.outline_color = Color(0, 0, 0, 0.7)
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # (never wider than the screen)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_child(l)
	return l


func enter() -> void:
	entered_t = L.now
	L.state = "tune"
	L.say("")
	if L.audio.playing:
		L.audio.stream_paused = true
	L.hud.clear_popup()
	_ui.visible = true
	_refresh()


## Every physics step in the tune mode: the player stands on the perfect path at the moment shown.
func step() -> void:
	L.player.position = Vector3(L.track.x_at(L.now), L.path_y(L.now), 0.0)


## Each label over its point on screen; the panel where it covers less of the player and the stars' labels and ghosts
## on screen (the player counts most) — it only moves over when the other place covers strictly less.
func _process(_delta: float) -> void:
	if not _ui.visible:
		return
	var cam: Camera3D = L.cam_rig.cam
	var placed: Array = []  # (a label that would overlap one placed already goes up over it)
	for t in _tags:
		var l: Label = t[0]
		l.visible = not cam.is_position_behind(t[1])
		if not l.visible:
			continue
		var s := l.get_combined_minimum_size()
		var r := Rect2(cam.unproject_position(t[1]) - Vector2(s.x * 0.5, s.y), s)
		var moved := true
		while moved:
			moved = false
			for q in placed:
				if r.intersects(q):
					r.position.y = q.position.y - s.y - 2.0
					moved = true
		placed.append(r)
		l.position = r.position
	var size := get_viewport().get_visible_rect().size
	var h := _panel.size.y
	var top_span := Vector2(TOP_Y, TOP_Y + h)
	var bottom_span := Vector2(size.y - BOTTOM_Y - h, size.y - BOTTOM_Y)
	var covered := [0.0, 0.0]  # at the top, at the bottom
	var things: Array = [[L.player.global_position, 3.0]]
	for p in _spots:
		things.append([p, 1.0])
	for t in things:
		if cam.is_position_behind(t[0]):
			continue
		var p := cam.unproject_position(t[0])
		if p.x < 0.0 or p.x > size.x:
			continue
		for k in 2:
			var span: Vector2 = top_span if k == 0 else bottom_span
			if p.y > span.x - 40.0 and p.y < span.y + 40.0:
				covered[k] += t[1]
	if _at_top and covered[1] < covered[0] or not _at_top and covered[0] < covered[1]:
		_place(not _at_top)


## The panel under the lives (top) or over the input hints.
func _place(top: bool) -> void:
	_at_top = top
	_panel.anchor_top = 0.0 if top else 1.0
	_panel.anchor_bottom = _panel.anchor_top
	_panel.grow_vertical = Control.GROW_DIRECTION_END if top else Control.GROW_DIRECTION_BEGIN
	_panel.offset_top = TOP_Y if top else -BOTTOM_Y
	_panel.offset_bottom = _panel.offset_top


func handle(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	var stars = L.mechanic("stars")
	var dt := 0.0
	match key.keycode:
		KEY_LEFT, KEY_RIGHT:
			dt = L.data.bar_sec if key.shift_pressed else (L.beat * 0.25 if key.ctrl_pressed else L.beat)
			dt *= -1.0 if key.keycode == KEY_LEFT else 1.0
		KEY_HOME:
			_move_to(L.t_start)
		KEY_END:
			_move_to(L.data.dur)
	if dt != 0.0:
		_move_to(L.now + dt)
	if key.echo or stars == null:
		return
	match key.keycode:
		KEY_N:
			var ts: Array = stars.free_times()
			var t: float = stars.snap(L.now)[0]
			if not ts.any(func(s): return absf(s - t) < 0.01):
				ts.append(t)
				ts.sort()
				_set_stars(ts)
		KEY_BACKSPACE, KEY_DELETE:
			var i := _nearest(stars.free_times())
			if i >= 0:
				var ts: Array = stars.free_times()
				ts.remove_at(i)
				_set_stars(ts)
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			var ts: Array = stars.free_times()
			var i := _nearest(ts)
			if i >= 0:
				var lead: Array = L.song.notes("lead")
				var j := lead.map(func(n): return n[0]).bsearch(ts[i])
				j += -1 if key.keycode == KEY_BRACKETLEFT else (1 if j < lead.size() and absf(lead[j][0] - ts[i]) < 0.01 else 0)
				if j >= 0 and j < lead.size():
					ts[i] = lead[j][0]
					ts.sort()
					_set_stars(ts)
		KEY_C:
			var text := _star_t(stars)
			DisplayServer.clipboard_set(text)
			print("STAR_T level %d: %s" % [int(L.data.level), text])
			L.popup("已复制 STAR_T", Color.WHITE)
		KEY_ENTER, KEY_KP_ENTER:
			_run_from(L.now)
		KEY_T:
			_run_from(entered_t)


func _move_to(t: float) -> void:
	L.now = clampf(t, L.t_start, L.data.dur)
	_refresh()


## The free star (not a rest's) nearest the moment, within a bar (-1: none).
func _nearest(ts: Array) -> int:
	var best := -1
	for i in ts.size():
		if absf(ts[i] - L.now) <= L.data.bar_sec and (best < 0 or absf(ts[i] - L.now) < absf(ts[best] - L.now)):
			best = i
	return best


func _set_stars(ts: Array) -> void:
	L.mechanic("stars").rebuild(ts)
	edited = true
	_refresh()


func _star_t(stars) -> String:
	return ",".join(stars.free_times().map(func(t): return "%.2f" % t))


## Start again from moment t, the way a lost life does (the edited stars kept for the go).
func _run_from(t: float) -> void:
	var stars = L.mechanic("stars")
	if stars != null:
		print("STAR_T level %d: %s" % [int(L.data.level), _star_t(stars)])
		if edited:
			RunState.star_t = stars.free_times()
	var c: float = L._safe_before(t)
	RunState.level = int(L.data.level)
	RunState.lives = maxi(1, L.lives)
	RunState.resume_t = c if not is_nan(c) else 0.0
	RunState.best_streak = L.best_streak
	RunState.stars_taken = stars.stars.filter(func(s): return s.t < t).map(func(s): return s.t) if stars != null else []
	get_tree().reload_current_scene()


## The labels over every star, its checkpoint and the ghost where it carries on; the HUD lines.
func _refresh() -> void:
	for n in _marks:
		n.queue_free()
	_marks = []
	_tags = []
	_spots = []
	var stars = L.mechanic("stars")
	var warnings := []
	var cp := 0.0
	if stars != null:
		for s in stars.stars:
			var c: float = L._safe_before(s.t)
			var col := GREEN
			var note := ""
			if is_nan(c):
				col = RED
				note = "  存不了档"
				warnings.append("★ %.2f 存不了档：前面一拍没有平地" % s.t)
			elif not L.saves(c, cp):
				col = ORANGE
				note = "  不会推进"
				warnings.append("★ %.2f 不会推进存档点（↩ %.2f 比上一个存档点晚不到 %s 拍）" % [s.t, c, str(L.CHECKPOINT_MIN_GAIN)])
			else:
				cp = c
			if stars._occupied(s.t):  # hidden in a mechanic's block (N, [ ] and STAR_T don't step aside as 4b does)
				col = PURPLE if col != RED else col
				note += "  被挡住"
				warnings.append("★ %.2f 被机关的方块挡住了（看不见）：[ ] 挪开" % s.t)
			s.stand_mat.albedo_color = col if col != GREEN else stars.STAND_GREEN
			_label(s.pos + Vector3(0.0, 0.45, 0.0), "★ %.2f%s%s" % [s.t, "（喘息点）" if s.rest else "", note], col, 24)
			if not is_nan(c):
				var at := Vector3(L.track.x_at(c), L.plat_h(c) + L.HALF, 0.0)
				var ghost := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(0.7, 1.4, 0.7)
				ghost.mesh = box
				ghost.material_override = _ghost_mat
				ghost.position = at
				add_child(ghost)
				_marks.append(ghost)
				_spots.append(at)
				_label(at + Vector3(0.0, 0.8, 0.0), "↩ %.2f" % c, col, 20)
	var bar := int(floor(L.now / L.data.bar_sec)) + 1
	var beat_in := int(floor(fposmod(L.now, L.data.bar_sec) / L.beat)) + 1
	_info.text = "调整模式 · 第 %d 小节第 %d 拍 · t %.2f s\n←→ 一拍  ⇧ 小节  ⌃ 1/4 拍 · N 放星  ⌫ 删星  [ ] 挪星 · C 复制 STAR_T\nEnter 从这里跑 · T 退出（从存档点重来）" % [bar, beat_in, L.now]
	var lines := ["STAR_T 现在：%s" % (_star_t(stars) if stars != null else "")]
	if edited:
		lines.append("星表改过了：Enter 试跑会带上（R 会清掉），满意了按 C 复制进 tuning.csv")
	lines.append_array(warnings.slice(0, 3))
	_star_line.text = "\n".join(lines)


## A label (screen pixels high) hanging over point `at`, drawn over the picture (placed every frame in _process).
func _label(at: Vector3, text: String, col: Color, size: int) -> void:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = L.hud.dev_font()
	ls.font_size = size
	ls.font_color = col
	ls.outline_size = 6
	ls.outline_color = Color(0, 0, 0, 0.8)
	l.label_settings = ls
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_box.add_child(l)
	_marks.append(l)
	_tags.append([l, at])
	_spots.append(at)
