extends SceneTree
## How long one physics step of a level takes (GDScript only, headless), on autoplay through the whole song:
##   godot --headless --path <project> --script step_cost.gd -- --level=N

var level: Node
var _quit_in := -1            # frames left before quitting (see _finish)
var clock := 0.0
var started := false
var steps := 0
var total_us := 0
var worst_us := 0
var pillars_us := 0
var mech_us := {}


func _initialize() -> void:
	var lv := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			lv = int(a.substr(8))
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
		level.set_physics_process(false)  # stepped by hand below, so each step can be timed
		level.autoplay = true
		level.lives = 1  # the first fail is the end
		level.state = "countdown"
		level.now = level.t_start
		print("nodes in level: %d  visualizer bars: %d  mechanic pillars: %d" % [_count(level), level.pillars.bars.size(), level.mech.size()])
	if started and (level.state == "play" or level.state == "countdown"):
		var t0 := Time.get_ticks_usec()
		level._physics_process(1.0 / 120.0)
		var dt := Time.get_ticks_usec() - t0
		total_us += dt
		worst_us = maxi(worst_us, dt)
		steps += 1
		# the visual parts on their own
		var t1 := Time.get_ticks_usec()
		level.pillars.update_motion()
		pillars_us += Time.get_ticks_usec() - t1
		for m in level.mechanics:
			var t2 := Time.get_ticks_usec()
			m.update_motion(1.0 / 120.0)
			mech_us[m.name] = mech_us.get(m.name, 0) + Time.get_ticks_usec() - t2
	if started and (level.state == "fail" or level.state == "win"):
		var per := {}
		for k in mech_us:
			per[k] = snappedf(mech_us[k] / float(steps), 0.1)
		print("RESULT %s steps=%d  whole step avg %.1f us worst %d us | pillars.update_motion avg %.1f us | mechanics %s" % [
			level.state, steps, total_us / float(steps), worst_us, pillars_us / float(steps), str(per)])
		_finish()
	return false


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


## Done: let the level's song go and quit a few frames later, once the audio thread has dropped it (quitting at once
## leaves its playback behind, reported as leaked at exit).
func _finish() -> void:
	if _quit_in < 0:
		level.audio.stop()
		_quit_in = 10
