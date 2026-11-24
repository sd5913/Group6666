extends SceneTree
## Render a level on autoplay (in a window, silent, one fixed step per frame) and save pictures:
##   godot --path <project> --screen 1 --fixed-fps 60 --resolution 1920x1080 --script tools/capture.gd -- --level=N --out=<dir> ...
## The window always opens on a secondary screen, never the main one (the user works there): no flag needed; with no
## second screen it says so and quits without capturing. <dir> is made if it isn't there.
##   --times=5,12.5     full frames at these song times
##   --seq=26,28        every frame between these song times (JPEG)
##   --crop=420         also save a square this many pixels around the player (with --seq: only the crop, PNG)
##   --poses            the first moment the player stands on visualizer pillars / a mechanic pillar, in the warm and
##                      in the cool colours (4 frames)
##   --miss=27,45       no autoplay around these song times (-0.25 .. +0.3 s), so the player runs into what is there
##   --hold=20.64       jump held on past these song times (-0.05 .. +0.45 s): a band ending there isn't let go of
##   --let-go=20.79     jump held on up to these song times (from 0.5 s before) and let go right then: a band let go of
##                      late (or early)
##   --early=38.16:0.3  jump pressed this much before these song times (and no autoplay around them): a press that
##                      waits for its note
##   --late=19:0.08:dash  that key (jump, dash or down) pressed this much after these song times (and no autoplay
##                      around them): a late press, judged a moment after its prompt has popped
##   --lives            keep the level's lives: a fail carries on from the last star (the capture follows the reload,
##                      shoots the fail screen once and a frame in each beat of the count-in, and takes --times again from
##                      where the level starts over);
##                      without it the first fail ends the capture
##   --tune=27.5        at this song time go into the tune mode (T), shoot it, and finish
##   --tutorial         the level with its tutorial (scripts/tutorial.gd), played with real key events: each stop shot
##                      while it waits, then pressed; the plate's count-in shot on each beat; autoplay from the song on
##                      (--times may be before the song)
## Winning, the win screen is shot (pass --times past the end to run that far).

const RunState := preload("res://scripts/core/run_state.gd")

var level: Node
var frames := 0
var times: Array = []
var seq := []
var crop := 0
var poses := false
var pose_done := {}
var out_dir := ""
var lv := 1
var last_pose := -INF
var misses: Array = []
var holds: Array = []
var let_go: Array = []
var early: Array = []           # [time, how early, pressed]
var late: Array = []            # [time, how late, key, pressed]
var _pending: Array = []       # [file, sequence]: saved next frame, once the picture shows this moment
var keep_lives := false
var all_times: Array = []
var _shot_fail := false
var _restart_at := -1           # frame to shoot the count-in after a reload
var tune_t := NAN
var _tune_shot := -1            # frame the tune mode's picture is shot (-1: not in it yet)
var _win_shot := -1             # frame the win screen was asked for (-1: not won yet)
var tutorial := false
var _stop_wait := 0
var _stop_was := ""
var _stop_n := 0
var _title_at := -100           # the frame the title card came up on the plate
var _count_at := -1             # the frame the plate's count-in started


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			lv = int(a.substr(8))
		elif a.begins_with("--times="):
			times = Array(a.substr(8).split(",")).map(func(s): return float(s))
		elif a.begins_with("--seq="):
			seq = Array(a.substr(6).split(",")).map(func(s): return float(s))
		elif a.begins_with("--crop="):
			crop = int(a.substr(7))
		elif a == "--poses":
			poses = true
		elif a.begins_with("--miss="):
			misses = Array(a.substr(7).split(",")).map(func(s): return float(s))
		elif a.begins_with("--hold="):
			holds = Array(a.substr(7).split(",")).map(func(s): return float(s))
		elif a.begins_with("--let-go="):
			let_go = Array(a.substr(9).split(",")).map(func(s): return float(s))
		elif a.begins_with("--early="):
			for e in a.substr(8).split(","):
				early.append([float(e.split(":")[0]), float(e.split(":")[1]), false])
		elif a.begins_with("--late="):
			for e in a.substr(7).split(","):
				var p := e.split(":")
				late.append([float(p[0]), float(p[1]), p[2] if p.size() > 2 else "jump", false])
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a == "--lives":
			keep_lives = true
		elif a.begins_with("--tune="):
			tune_t = float(a.substr(7))
		elif a == "--tutorial":
			tutorial = true
	if DisplayServer.get_screen_count() < 2:  # never on the main screen: with no other one, nothing is captured
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
		push_error("NO SECOND SCREEN: not capturing on the main screen")
		print("NO SECOND SCREEN: not capturing on the main screen")
		quit(1)
		return
	_off_main_screen()
	DirAccess.make_dir_recursive_absolute(out_dir)
	RunState.tutorial_due = tutorial
	level = load("res://scenes/level_%d.tscn" % lv).instantiate()
	root.add_child(level)
	current_scene = level  # (so a lost life can reload it)


## Test windows go on another screen than the main one, even without --screen 1.
func _off_main_screen() -> void:
	var main := DisplayServer.get_primary_screen()
	if DisplayServer.window_get_current_screen() != main:
		return
	for s in DisplayServer.get_screen_count():
		if s != main:
			DisplayServer.window_set_current_screen(s)
			return


func _process(_delta: float) -> bool:
	frames += 1
	if current_scene != null and current_scene != level:  # reloaded after a lost life: carry on capturing it
		level = current_scene
		_shot_fail = false
		_restart_at = frames + 4
		if level.is_inside_tree() and not level.data.is_empty():
			times = all_times.filter(func(t): return t >= level.now)
	if frames == 5:
		all_times = times.duplicate()
		if not keep_lives:
			level.lives = 1
		level.autoplay = true
		if not tutorial:
			level.state = "countdown"
			level.now = level.t_start
	if level.state == "play" and level.audio.playing:
		level.audio.stop()  # silent: the clock then runs on the fixed frame rate
	if frames <= 5:
		return false
	if tutorial and level.state == "tutorial":
		level.autoplay = false
		_play_tutorial()
	var holding := holds.any(func(h): return level.now > h - 0.05 and level.now < h + 0.45)
	level.autoplay = not (tutorial and level.state == "tutorial") and not holding and not _letting_go() and not misses.any(func(m): return level.now > m - 0.25 and level.now < m + 0.3) 		and not early.any(func(e): return level.now > e[0] - e[1] - 0.05 and level.now < e[0] + 0.3) 		and not late.any(func(e): return level.now > e[0] - 0.3 and level.now < e[0] + e[1] + 0.05)
	for e in early:
		if not e[2] and level.now >= e[0] - e[1]:
			e[2] = true
			level.jump_press = level.now
	for e in late:
		if not e[3] and level.now >= e[0] + e[1]:
			e[3] = true
			match e[2]:
				"dash":
					level.press_dash()
				"down":
					level.down_press = level.now
				_:
					level.jump_press = level.now
	if holding:
		level.jump_held = true
	if tutorial and level.state == "title" and _title_at < 0:  # the song's name, on the plate, before the count-in
		_title_at = frames
	if tutorial and frames == _title_at + 60:
		_pending.append(["level%d_title" % lv, false])
	if tutorial and level.state == "countdown" and _count_at < 0:
		_count_at = frames
	for k in 3:  # the plate's count-in: 3, 2 standing on it, 1 running
		if tutorial and _count_at >= 0 and frames == _count_at + 8 + roundi(k * level.beat * 60.0):
			_pending.append(["level%d_count%d" % [lv, 3 - k], false])
	# the window's picture is the frame drawn before this step: what was asked for last step is in it now
	for p in _pending:
		_save(p[0], p[1])
	_pending.clear()
	var now: float = level.now
	if keep_lives and level._continuing and not _shot_fail:  # the screen after losing a life
		_shot_fail = true
		_pending.append(["level%d_lost_life_t%05.2f" % [lv, now], false])
	for k in 3:  # the count-in it starts again with: its first beat, its second (both standing still), its third (running)
		if _restart_at >= 0 and frames == _restart_at + roundi(k * level.beat * 60.0):
			_pending.append(["level%d_restart%d_t%05.2f" % [lv, k + 1, now], false])
	if not times.is_empty() and now >= times[0]:
		_pending.append(["level%d_t%05.2f" % [lv, times[0]], false])
		times.pop_front()
	if seq.size() == 2 and now >= seq[0] and now <= seq[1]:
		_pending.append(["level%d_seq_%05.2f" % [lv, now], true])
	if poses and now - last_pose > 0.5 and level.player.grounded and level.state == "play":
		var x: float = level.player.position.x
		var on := "bars" if level.pillars.bar_color(x).a > 0.0 else ("pillar" if not level.seg_at(now).is_empty() else "")
		var warm: bool = level.cam_rig.palette_at(now) == level.cam_rig.WARM
		var key := "%s_%s" % [on, "warm" if warm else "cool"]
		# well into its colour, so the sky and the player have both turned
		if on != "" and not pose_done.has(key) and now > 1.0 and _settled_palette(now):
			pose_done[key] = true
			last_pose = now
			_pending.append(["level%d_pose_%s_t%05.2f" % [lv, key, now], false])
	if not is_nan(tune_t) and _tune_shot < 0 and level.state == "play" and now >= tune_t:
		level.tune.enter()
		_tune_shot = frames + 3  # (its labels drawn first)
	if frames == _tune_shot:
		_pending.append(["level%d_tune_t%05.2f" % [lv, now], false])
	var done: bool = times.is_empty() and (seq.size() < 2 or now > seq[1]) and (not poses or pose_done.size() >= 4)
	if not is_nan(tune_t):
		done = _tune_shot >= 0 and frames > _tune_shot
	if level.state == "win" and _win_shot < 0:  # the win screen, once it is drawn
		_win_shot = frames + 3
	if frames == _win_shot:
		_pending.append(["level%d_win" % lv, false])
	if (done and _pending.is_empty()) or (level.state == "fail" and level.lives <= 0) or (_win_shot >= 0 and frames > _win_shot + 1):
		print("DONE state=%s now=%.2f poses=%s" % [level.state, now, str(pose_done.keys())])
		return true
	return false


## What the tutorial has stopped for: shot while it waits, then pressed (a long press stays down until it asks to let go).
func _play_tutorial() -> void:
	var tut = level.tutorial
	var w: String = tut.waiting
	if w == "":
		_stop_was = ""
		return
	if w != _stop_was:
		_stop_was = w
		_stop_wait = 0
		_stop_n += 1
	_stop_wait += 1
	if _stop_wait == 20:
		_pending.append(["level%d_stop%d_%s" % [lv, _stop_n, w], false])
	if _stop_wait != 26:
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


func _send(action: String, on: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = on
	level._unhandled_input(ev)


## --let-go on the physics step (a frame is two of them): held up to the time, let go on the first step at or past it.
func _physics_process(_delta: float) -> bool:
	if frames > 5 and is_instance_valid(level) and level.is_inside_tree():
		if _letting_go():
			level.jump_held = true
		elif let_go.any(func(t): return level.now >= t and level.now < t + 0.05):
			level.jump_held = false
	return false


func _letting_go() -> bool:
	return let_go.any(func(t): return level.now > t - 0.5 and level.now < t)


## The palette has been the same for the last 0.6 s.
func _settled_palette(now: float) -> bool:
	return level.cam_rig.palette_at(now) == level.cam_rig.palette_at(now - 0.6)


func _save(file: String, sequence: bool) -> void:
	var img := root.get_texture().get_image()
	if crop > 0:
		var cam: Camera3D = level.cam_rig.cam
		# the camera works in the viewport's own size (stretched to the window), the picture is the window's size
		var c := cam.unproject_position(level.player.global_position) * Vector2(img.get_size()) / root.get_visible_rect().size
		var r := Rect2i(int(c.x) - crop / 2, int(c.y) - crop / 2, crop, crop).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(r).save_png("%s/%s_crop.png" % [out_dir, file])
		if sequence:
			return
	if sequence:
		img.save_jpg("%s/%s.jpg" % [out_dir, file], 0.88)
	else:
		img.save_png("%s/%s.png" % [out_dir, file])
	print("SHOT ", file, "  (prompt shown at song time %.4f)" % level.cue_text.drawn_now)
