extends SceneTree
## Headless playthrough of one level (--level=N). Modes (after `--`):
##   (none)      autoplay: every drum, air dash and jaw on the beat
##   --late      jump 0.15 s after every kick, air-dash 0.08 s late, dash right on the clap
##   --dashonly  never presses jump; only air-dashes (on the beat) — drums should throw by themselves
##   --noinput   presses nothing

var level: Node
var _quit_in := -1            # frames left before quitting (see _finish)
var clock := 0.0
var started := false
var mode := "auto"
var max_lift := 0.0
var max_lift_t := 0.0
var trace_from := INF
var trace_to := -INF
var last_trace := -INF
var trace_dt := 0.05


func _initialize() -> void:
	var lv := 1
	for a in OS.get_cmdline_user_args():
		if a in ["--late", "--early", "--dashonly", "--noinput"]:
			mode = a.substr(2)
		elif a.begins_with("--level="):
			lv = int(a.substr(8))
		elif a.begins_with("--trace="):  # --trace=45.5,47.5: print the player every 0.05 s in that window
			trace_from = float(a.substr(8).split(",")[0])
			trace_to = float(a.substr(8).split(",")[1])
			if a.substr(8).split(",").size() > 2:
				trace_dt = float(a.substr(8).split(",")[2])
	level = load("res://scenes/level_%d.tscn" % lv).instantiate()
	root.add_child(level)


var cue_done := {}
var hold_until := -INF


func _press(action: String) -> void:
	match action:
		"jump":
			level.jump_press = level.now
			level.jump_held = true
		"dash":
			level.press_dash()
		"down":
			level.down_press = level.now


func _list(mech: String, field: String) -> Array:
	var m = level.mechanic(mech)
	return m.get(field) if m != null else []


func _physics_process(delta: float) -> bool:
	if _quit_in >= 0:
		_quit_in -= 1
		if _quit_in == 0:
			quit()
		return false
	clock += delta
	if clock > 120.0:  # something is broken (script errors every step): give up
		print("RESULT stuck")
		quit()
		return true
	if not started and clock > 0.3:
		started = true
		level.autoplay = mode == "auto"
		level.lives = 1  # the first fail is the end (no carrying on from a star in tests)
		level.state = "countdown"
		level.now = level.t_start
		print("drum modes: %s" % " ".join(_list("drums", "drums").map(func(d): return "%s@%.1f" % [d.mode, d.t])))
		print("air dashes at %s" % str(_list("drums", "air_dashes").map(func(a): return snappedf(a.t, 0.1))))
		var all_cues := []
		for m in level.mechanics:  # (a mechanic that lists no cues may still need presses: its inputs())
			var cs: Array = m.cues()
			all_cues.append_array(cs if not cs.is_empty() else m.inputs().map(func(t): return {"t": t}))
		all_cues.sort_custom(func(a, b): return a.t < b.t)
		var gaps := []
		var free_from := 0.0
		for c in all_cues:
			if c.t - free_from > 2.5:
				gaps.append("%.1f-%.1f" % [free_from, c.t])
			free_from = maxf(free_from, c.get("until", c.t))
		if level.data.dur - free_from > 2.5:
			gaps.append("%.1f-end" % free_from)
		print("inputs %d, stretches over 2.5 s with nothing to press: %s" % [all_cues.size(), " ".join(gaps) if gaps.size() > 0 else "none"])
		for m in level.mechanics:
			var cs: Array = m.cues()
			if not cs.is_empty():
				print("cues %s: %d at %s" % [m.name, cs.size(), str(cs.map(func(c): return snappedf(c.t, 0.01)))])
		# every object a mechanic placed has to stand on a MIDI note of its track
		for m in level.mechanics:
			var anchors: Array = m.anchors()
			var off := anchors.filter(func(a): return level.song.off_by(a[1], a[0]) > 0.010)
			print("MIDI %s: %d objects, %d more than 10 ms off a note%s" % [m.name, anchors.size(), off.size(),
				(": " + " ".join(off.slice(0, 12).map(func(a): return "%.2f(%s %+.0fms)" % [a[0], a[1], 1000.0 * level.song.off_by(a[1], a[0])]))) if off.size() > 0 else ""])
		print("springs %s at %s; jaws %d; key height %.2f..%.2f" % [(level.mechanic("springs").SPRING_MODE if level.mechanic("springs") else "-"), str(_list("springs", "springs").map(func(s): return snappedf(s.t, 0.01))),
			_list("jaws", "blocks").size(), level.key_pts.map(func(k): return k[1]).min(), level.key_pts.map(func(k): return k[1]).max()])
		for d0 in _list("drums", "drums").slice(0, 2) + _list("drums", "drums").filter(func(d): return d.mode == "C2").slice(0, 1):
			var s0: Dictionary = level.seg_at(d0.t)
			var run_in: Dictionary = level.seg_at(s0.ta - 0.01)
			var xk: float = level.track.x_at(d0.t)
			print("%s drum @%.2f: own pillar x %.2f..%.2f top %.2f | run-in top %s | skin back/centre/front %.2f / %.2f / %.2f | support behind back edge %.2f" % [
				d0.mode, d0.t, level.track.x_at(s0.ta), level.track.x_at(s0.tb), s0.base,
				"%.2f" % run_in.base if not run_in.is_empty() else "none (gap)",
				level.surface(s0, s0.base, xk - d0.r * cos(level.mechanic("drums").DRUM_TILT)), level.surface(s0, s0.base, xk),
				level.surface(s0, s0.base, xk + d0.r * cos(level.mechanic("drums").DRUM_TILT)), level.surface(s0, s0.base, level.track.x_at(s0.ta) + 0.05)])
	if started and (level.state == "play" or level.state == "countdown"):
		if mode == "late":
			for d in _list("drums", "drums"):
				if not d.get("judged", false) and level.now >= d.t + 0.15 and level.now < d.t + 0.17:
					level.jump_press = level.now
			for b in _list("jaws", "blocks"):
				if not b.broken and level.now >= b.t and level.now < b.t + 0.02 and level.dash_press < b.t - 0.15:
					level.dash_press = level.now
		if mode == "early":  # every jump 0.12 s early, dashes 0.08 s early
			for d in _list("drums", "drums"):
				if not d.get("judged", false) and level.now >= d.t - 0.12 and level.now < d.t - 0.10:
					level.jump_press = level.now
			for a in _list("drums", "air_dashes"):
				if not a.used and level.now >= a.t - 0.08 and level.now < a.t - 0.06:
					level.dash_press = level.now
			for b in _list("jaws", "blocks"):
				if not b.broken and level.now >= b.t - 0.08 and level.now < b.t - 0.06 and level.dash_press < b.t - 0.15:
					level.dash_press = level.now
		if mode == "dashonly":  # "never jumps" except where a spring needs it, on the beat
			for s in _list("springs", "springs"):
				if s.press and not s.used and level.now >= s.t and level.now < s.t + 0.02:
					level.jump_press = level.now
		if mode == "late" or mode == "dashonly":
			var off := 0.08 if mode == "late" else 0.0
			for a in _list("drums", "air_dashes"):
				if not a.used and level.now >= a.t + off and level.now < a.t + off + 0.02:
					level.dash_press = level.now
		# mechanics that list their inputs (cues): pressed 0.12 s late / early, held as long as asked
		if mode == "late" or mode == "early":
			var off := 0.12 if mode == "late" else -0.12
			for m in level.mechanics:
				for c in m.cues():
					var key := "%s@%.3f" % [m.name, c.t]
					if not cue_done.has(key) and level.now >= c.t + off:
						cue_done[key] = true
						_press(c.action)
						if c.has("until"):
							hold_until = maxf(hold_until, c.until + off)
			if level.jump_held and level.now >= hold_until:
				level.jump_held = false
		if mode == "dashonly":
			for m in level.mechanics:
				for c in m.cues():
					var key := "%s@%.3f" % [m.name, c.t]
					if c.action == "dash" and not cue_done.has(key) and level.now >= c.t:
						cue_done[key] = true
						_press("dash")
		if level.now >= trace_from and level.now <= trace_to and level.now - last_trace >= trace_dt:
			last_trace = level.now
			var pp: Vector3 = level.player.global_position
			var near: Array = _list("jaws", "blocks").filter(func(b): return absf(b.t - level.now) < 0.4 and not b.broken).map(
				func(b): return "jaw%.2f c=%.2f g=%.2f dx=%.2f" % [b.t, b.centre, b.gap, pp.x - b.x])
			print("  trace t=%.3f y=%.2f vy=%.2f path=%.2f plat=%.2f support=%.2f grounded=%s %s" % [
				level.now, pp.y, level.player.vy, level.path_y(level.now), level.plat_h(level.now), level.support_at(level.now, pp.x),
				level.player.grounded, " ".join(near)])
		var lift: float = level.player.global_position.y - (level.ground_h(level.now) + 0.7)
		if lift > max_lift:
			max_lift = lift
			max_lift_t = level.now
		# every jaw that catches the player: where it stood, how it closed, where the player was
		for b in _list("jaws", "blocks"):
			if b.get("dented", false) and not b.get("reported", false):
				b.reported = true
				var py: float = level.player.global_position.y
				print("  dent t=%.2f now=%.2f big=%s seg=%s squeeze=%.2f centre=%.2f gap=%.2f player_y=%.2f path_y=%.2f dx=%.2f on_bars=%s" % [
					b.t, level.now, b.big, not b.seg.is_empty(), b.squeeze, b.centre, b.gap, py, level.path_y(level.now),
					level.player.global_position.x - b.x, level.pillars.on_bars(level.player.global_position.x)])
	if level.state == "fail" or level.state == "win" or clock > level.data.dur + 12.0:
		var dented: Array = _list("jaws", "blocks").filter(func(b): return b.get("dented", false))
		print("jaws: %d slammed shut behind the player, %d touched (dented) at %s; squeeze half-gaps %s" % [
			_list("jaws", "blocks").filter(func(b): return b.broken and not b.get("dented", false)).size(), dented.size(),
			str(dented.map(func(b): return snappedf(b.t, 0.01))), str(_list("jaws", "blocks").slice(0, 6).map(func(b): return snappedf(b.squeeze, 0.01)))])
		var g = level.mechanic("glide")
		if g != null:
			print("glides: %s" % " ".join(g.glides.map(func(x): return "%.2f[%s%s]" % [x.t0, "J" if x.judged else "-", "G" if x.used else "-"])))
		var sl = level.mechanic("slam")
		if sl != null:
			print("slams: %s" % " ".join(sl.slams.map(func(x): return "%.2f[%s%s]" % [x.t, "S" if x.slammed else "-", "B" if x.bounced > -INF else "-"])))
		var fl = level.mechanic("flip")
		if fl != null:
			print("flips: %d, flipped %d" % [fl.flips.size(), fl.flips.filter(func(x): return x.judged).size()])
		var sm = level.mechanic("smash")
		if sm != null:
			print("smash: %d, smashed %d, run into %d" % [sm.blocks.size(), sm.blocks.filter(func(x): return x.judged and not x.hit).size(), sm.blocks.filter(func(x): return x.hit).size()])
		var lc = level.mechanic("launch")
		if lc != null:
			print("launches: %s" % " ".join(lc.launches.map(func(x): return "%.2f[%s%s]" % [x.t, "J" if x.judged else "-", "X" if x.hit else "ok"])))
		var tw = level.mechanic("towers")
		if tw != null:
			print("towers: %s" % " ".join(tw.pairs.map(func(x): return "%.2f[%s%s]" % [x.t, "J" if x.judged else "-", "X" if x.hit else "ok"])))
		var pl = level.mechanic("plunge")
		if pl != null:
			print("plunges: %s" % " ".join(pl.plunges.map(func(x): return "%.2f[%s]" % [x.t, ("%+.0fms" % (1000.0 * (x.landed_t - x.t))) if x.has("landed_t") else "-"])))
		var w = level.mechanic("walls")
		if w != null:
			print("walls: %s" % " ".join(w.walls.map(func(x): return "%.2f[%s%s]" % [x.t, "J" if x.judged else "-", "X" if x.hit else "ok"])))
		print("RESULT %s now=%.2f best_streak=%d stats=%s max_lift_above_key=%.2f at t=%.2f" % [level.state, level.now, level.best_streak, str(level.stats), max_lift, max_lift_t])
		_finish()
	return false


## Done: let the level's song go and quit a few frames later, once the audio thread has dropped it (quitting at once
## leaves its playback behind, reported as leaked at exit).
func _finish() -> void:
	if _quit_in < 0:
		level.audio.stop()
		_quit_in = 10
