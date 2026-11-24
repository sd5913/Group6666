extends SceneTree
## Carry on from every star's checkpoint (the lost-life way: the level reloaded with the run state set) and let autoplay
## play the rest; one line per star:
##   godot --headless --fixed-fps 120 --path <project> --script tools/resume_check.gd -- --level=N

const RunState := preload("res://scripts/core/run_state.gd")

var lv := 1
var level: Node
var frames := 0
var checkpoints: Array = []     # [star t, checkpoint]
var i := -1                     # the checkpoint being played (-1: still reading them)
var _quit_in := -1


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			lv = int(a.substr(8))
	RunState.clear()
	level = load("res://scenes/level_%d.tscn" % lv).instantiate()
	root.add_child(level)


func _physics_process(_delta: float) -> bool:
	if _quit_in >= 0:
		_quit_in -= 1
		if _quit_in == 0:
			quit()
		return false
	frames += 1
	if i < 0:
		if frames < 3:
			return false
		var cp := 0.0
		for s in level.mechanic("stars").stars:
			var c: float = level._safe_before(s.t)
			if level.saves(c, cp):  # (only the stars that save)
				checkpoints.append([s.t, c])
				cp = c
		print("STAR_T level %d: %s" % [lv, ",".join(level.mechanic("stars").free_times().map(func(t): return "%.2f" % t))])
		_next()
		return false
	if level.state == "win" or level.state == "fail" or frames > 120 * 90:
		print("RESUME star %.2f from %.2f: %s at %.2f" % [checkpoints[i][0], checkpoints[i][1], level.state, level.now])
		_next()
	return false


## Carry on from the next checkpoint (done when there is none).
func _next() -> void:
	level.audio.stop()
	level.queue_free()
	i += 1
	if i >= checkpoints.size():
		_quit_in = 10  # (once the audio thread has let the stream go)
		return
	RunState.level = lv
	RunState.lives = 1
	RunState.resume_t = checkpoints[i][1]
	RunState.stars_taken = []
	RunState.best_streak = 0
	level = load("res://scenes/level_%d.tscn" % lv).instantiate()
	root.add_child(level)
	level.autoplay = true
	frames = 0
