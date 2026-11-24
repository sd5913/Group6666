extends SceneTree
## Play a level headless pressing every mechanic's cue (mechanic.cues()) off by a fixed amount, and letting go of held
## inputs early, to see where the windows really end:
##   godot --headless --path <project> --script tools/cue_probe.gd -- --level=2 --off=0.17 [--release=0.2]

var level: Node
var _quit_in := -1            # frames left before quitting (see _finish)
var clock := 0.0
var started := false
var off := 0.0
var release := 0.0
var cues: Array = []


func _initialize() -> void:
	var lv := 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			lv = int(a.substr(8))
		elif a.begins_with("--off="):
			off = float(a.substr(6))
		elif a.begins_with("--release="):
			release = float(a.substr(10))
	level = load("res://scenes/level_%d.tscn" % lv).instantiate()
	root.add_child(level)


func _physics_process(delta: float) -> bool:
	if _quit_in >= 0:
		_quit_in -= 1
		if _quit_in == 0:
			quit()
		return false
	clock += delta
	if not started and clock > 0.3:
		started = true
		level.lives = 1  # the first fail is the end (no carrying on from a star in tests)
		level.state = "countdown"
		level.now = level.t_start
		for m in level.mechanics:
			cues.append_array(m.cues())
			for q in m.prompts():  # (a press that is needed without being a cue: level 1's air dashes)
				if not q.get("optional", false) and not cues.any(func(c): return c.action == q.action and absf(c.t - q.t) < 0.01):
					cues.append(q.duplicate())
	if started and (level.state == "play" or level.state == "countdown"):
		var now: float = level.now
		var held := false
		for c in cues:
			var t: float = c.t + off
			if now >= t and not c.get("pressed", false):
				c.pressed = true
				match c.action:
					"jump":
						level.jump_press = now
					"down":
						level.down_press = now
					"dash":
						level.press_dash()
			if c.has("until") and now >= t and now < c.until - release:
				held = true
		level.jump_held = held
	if level.state == "fail" or level.state == "win" or clock > 90.0:
		print("RESULT off=%+.2f release=%.2f %s now=%.2f streak=%d stats=%s" % [off, release, level.state, level.now, level.best_streak, str(level.stats)])
		_finish()
	return false


## Done: let the level's song go and quit a few frames later, once the audio thread has dropped it (quitting at once
## leaves its playback behind, reported as leaked at exit).
func _finish() -> void:
	if _quit_in < 0:
		level.audio.stop()
		_quit_in = 10
