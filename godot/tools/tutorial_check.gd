extends SceneTree
## The tutorials (scripts/tutorial.gd), played with real key events only when one has stopped for them, then the song on
## autoplay:
##   godot --headless --fixed-fps 120 --path <project> --script tools/tutorial_check.gd -- --level=N [--auto] [--eager]
##   --auto    the tutorial on autoplay as well
##   --eager   every key also pressed early and wrong on the way (it must not hurt)
## One TUT line per stop, then TUT_RESULT: the course must end on the plate, right way up, with a clean score, and the
## song must start at 0 with the same mechanics as a level without a tutorial (t >= 0 of every mechanic's cues).

const RunState := preload("res://scripts/core/run_state.gd")

var lv := 1
var auto := false
var eager := false
var level: Node
var _plain: Node
var plain_cues: Array = []
var frames := 0
var _wait := 0
var _last_wait := ""
var _state := ""
var _errors: Array = []
var _quit_in := -1
var _pressed_early := {}
var _let_go := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			lv = int(a.substr(8))
		elif a == "--auto":
			auto = true
		elif a == "--eager":
			eager = true
	RunState.clear()
	_plain = load("res://scenes/level_%d.tscn" % lv).instantiate()
	root.add_child(_plain)


## The level without a tutorial has been read: now the one with it.
func _start() -> void:
	plain_cues = _song_cues(_plain)
	root.remove_child(_plain)
	_plain.free()
	RunState.clear()
	RunState.tutorial_due = true
	level = load("res://scenes/level_%d.tscn" % lv).instantiate()
	root.add_child(level)
	current_scene = level
	level.lives = 1
	level.autoplay = auto
	if level.tutorial == null:
		print("TUT_RESULT level %d: no tutorial" % lv)
		_quit_in = 5


func _song_cues(l: Node) -> Array:
	var out := []
	for m in l.mechanics:
		for c in m.cues():
			if c.t >= 0.0:
				out.append("%s %.4f %s" % [m.name, c.t, c.action])
	out.sort()
	return out


func _send(action: String, on: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = on
	level._unhandled_input(ev)


func _physics_process(_delta: float) -> bool:
	if _quit_in >= 0:
		_quit_in -= 1
		if _quit_in == 0:
			quit()
		return false
	frames += 1
	if frames < 3:
		return false
	if frames == 3:
		_start()
		return false
	if _quit_in >= 0:
		return false
	if level.state != _state:
		_state = level.state
		print("TUT state %s at now=%.3f up=%.0f y=%.3f streak=%d perfect=%d" % [_state, level.now, level.player.up, level.player.position.y, level.streak, level.stats.perfect])
		if _state == "countdown":
			if level.player.up < 0.0:
				_errors.append("on the plate upside down")
			if absf(level.now - level.tutorial.plate_t) > 0.02:
				_errors.append("the count-in started at %.3f" % level.now)
			if level.streak != 0 or level.stats.perfect != 0:
				_errors.append("the score isn't clean")
			if level.tutorial._i < level.tutorial.stops.size():
				_errors.append("stops left over")
		elif _state == "play":
			if absf(level.now) > 0.02:
				_errors.append("the song started at %.3f" % level.now)
			level.autoplay = true
	if level.state == "title":
		level.title_done()
		level._title_card.queue_free()
		return false
	if level.state == "tutorial":
		_play_tutorial()
	elif level.state == "win" or level.state == "fail" or frames > 120 * 200:
		var cues := _song_cues(level)
		if cues != plain_cues:
			for i in mini(cues.size(), plain_cues.size()):
				if cues[i] != plain_cues[i]:
					_errors.append("song cue differs: %s / %s" % [cues[i], plain_cues[i]])
					break
			_errors.append("song cues: %d, without a tutorial %d" % [cues.size(), plain_cues.size()])
		if level.state != "win":
			_errors.append("ended %s at %.2f" % [level.state, level.now])
		print("TUT_RESULT level %d%s: %s  state=%s t=%.2f perfect=%d good=%d stars=%d stops=%d %s" % [lv, " auto" if auto else (" eager" if eager else ""),
			"OK" if _errors.is_empty() else "BAD", level.state, level.now, level.stats.perfect, level.stats.good, level.stats.stars, level.tutorial.stops.size(), str(_errors)])
		level.audio.stop()
		_quit_in = 10
	return false


## Press what it has stopped for, a moment after it stopped; a long press stays down until it asks to let go.
func _play_tutorial() -> void:
	var tut = level.tutorial
	if eager and tut._i < tut.stops.size():
		var s: Dictionary = tut.stops[tut._i]
		var key: int = tut._i
		if not _pressed_early.has(key) and level.now > s.t - 0.6:
			_pressed_early[key] = true
			for a in ["jump", "dash", "down"]:  # (all three, too early)
				_send(a, true)
				_send(a, false)
		if s.sent and s.has("until") and not _let_go and level.now > s.t + 0.5:  # (let go in the middle of a long press)
			_let_go = true
			_send("jump", false)
	var w: String = tut.waiting
	if w == "":
		_wait = 0
		_last_wait = ""
		return
	if w != _last_wait:
		_last_wait = w
		_wait = 0
		var i: int = mini(tut._i, tut.stops.size() - 1)
		print("TUT stop %d %s at t=%.3f wants %s  y=%.3f up=%.0f" % [tut._i, tut.stops[i].action, level.now, w, level.player.position.y, level.player.up])
	_wait += 1
	if eager and _wait == 6 and w == "jump" and tut.stops[tut._i].has("until"):  # (a long press only tapped: it waits on)
		_send("jump", true)
		_send("jump", false)
	if _wait != 12:
		return
	match w:
		"release":
			_send("jump", false)
		"hold":
			_send("jump", true)
		_:
			_send(w, true)
			if not tut.stops[tut._i].has("until"):
				_send(w, false)
