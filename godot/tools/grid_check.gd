extends SceneTree
## On the beat: how far each required press (its judging moment) and each landing (a slam's hit and its bounce's
## landing, a plunge's, a spring's, a drum's bounce, a hop's flute and its string's landing, a slam run-up's drop) is
## from the nearest beat of the grid (first_bar_at + n * beat), in levels 3, 4 and 5 (5: its B1 and B2 sections).
## Every one of them has to be within GRID_TOL of a beat.
##   godot --headless --path <project> --script tools/grid_check.gd -- [--level=N]   (no --level: 3, 4 and 5 in turn)
## Gated: the required presses and the landings a mechanic sets (a slam's hit and bounce, a plunge, a spring, a drum's
## bounce, a hop's flutes and landing). Listed only: a long note's release, a slam run-up's drop. Plain jumps don't
## count.
## Then each level is played on autoplay and every landing after more than 0.2 s in the air that isn't one of the
## planned ones is listed too ("list"; next to a fired wall: "launch landing") — walking off an edge, a fired wall's —
## and every flip's landing on the other row (however short its flight: the rows stand at different distances).
## Prints a line per moment (GRID ... "gate" / "list"), then per level: presses, gated moments off the grid, the worst.

const GRID_TOL := 0.010

var levels: Array = [3, 4, 5]
var level: Node
var frames := 0
var all_off := 0
var _planned: Array = []        # the planned landings of the level being played (their times)
var _launches: Array = []
var _span := [-INF, INF]
var _was_grounded := true
var _air := 0.0
var _landed: Array = []         # [t, what]
var _started := false
var _up_off := 1.0              # which way up the player took off (and was the step before)
var _last_up := 1.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			levels = [int(a.substr(8))]
	_load()


func _load() -> void:
	level = load("res://scenes/level_%d.tscn" % levels[0]).instantiate()
	root.add_child(level)
	frames = 0
	_started = false
	_landed.clear()
	_air = 0.0


func _physics_process(delta: float) -> bool:
	frames += 1
	if frames == 3:
		_check(level)
		_started = false
		_landed.clear()
		return false
	if frames == 20:  # (the pillars have their heights once the first steps have run)
		level.autoplay = true
		level.lives = 1
		level.state = "countdown"
		level.now = level.t_start
		_started = true
		_was_grounded = true
		return false
	if not _started:
		return false
	var p = level.player
	if not p.grounded:
		if _was_grounded:
			_up_off = _last_up  # (a flip turns gravity round in the step it takes off)
		_air += delta
	elif not _was_grounded:
		var t: float = level.now
		if t >= _span[0] and t < _span[1]:
			if p.up != _up_off:
				_landed.append([t, "flip landing on the other row"])
			elif _air > 0.2 and not _planned.any(func(x): return absf(x - t) < 0.06):
				_landed.append([t, "launch landing" if _launches.any(func(x): return absf(x - t) < 1.0) else "landing (walked off an edge, tossed, ...)"])
		_air = 0.0
	_was_grounded = p.grounded
	_last_up = p.up
	if level.state == "play" or level.state == "countdown":
		return false
	_report_landings(level)
	level.queue_free()
	levels.pop_front()
	if levels.is_empty():
		print("GRID TOTAL off the grid: %d" % all_off)
		quit()
		return true
	_load()
	return false


## The landings played that weren't planned (listed only).
func _report_landings(L) -> void:
	var lv := int(L.data.level)
	var worst := 0.0
	for x in _landed:
		var dev: float = L.grid_off(x[0])
		worst = maxf(worst, absf(dev))
		print("GRID L%d %8.3f %+7.3f list on  %s" % [lv, x[0], dev, x[1]])
	print("GRID L%d played (%s): %d landings besides the planned ones, worst %.0f ms off a beat" % [lv, L.state, _landed.size(), worst * 1000.0])


func _check(L) -> void:
	var lv := int(L.data.level)
	var span := [-INF, INF]
	if lv == 5:
		var b1: Array = L._sections_span("B1")
		var b2: Array = L._sections_span("B2")
		span = [b1[0], b2[1]]
	var moments := []  # [t, what]
	var presses := 0
	for m in L.mechanics:
		for c in m.prompts():
			if c.get("optional", false):
				continue
			var t: float = c.get("judge_t", c.t)
			if t >= span[0] - 0.001 and t < span[1]:
				moments.append([t, "%s press %s" % [m.name, c.action]])
				presses += 1
			if c.has("until") and c.until >= span[0] and c.until < span[1]:
				moments.append([c.until, "%s release" % m.name, false])
		match m.name:
			"slam":
				for s in m.slams:
					moments.append([s.t, "slam hit"])
					moments.append([s.land, "slam bounce lands"])
			"plunge":
				for p in m.plunges:
					moments.append([p.t, "plunge lands"])
			"springs":
				for s in m.springs:
					moments.append([s.get("land_t", s.t + L.beat), "spring lands"])
			"drums":
				for d in m.drums:
					moments.append([d.land_t, "drum bounce lands"])
			"hops":
				for r in m.runs:
					for p in r.pads:
						moments.append([p.t, "hop flute"])
					moments.append([r.land_t, "hop string lands"])
	for st in L.terrace:  # (a slam's run-up dropping to a dip in the tune: where the fall lands)
		if st.has("drop_land"):
			moments.append([st.drop_land, "run-up drop lands", false])
	moments = moments.filter(func(x): return x[0] >= span[0] - 0.001 and x[0] < span[1])
	_span = span
	_planned = moments.filter(func(x): return "lands" in x[1] or "hit" in x[1] or "flute" in x[1]).map(func(x): return x[0])
	var lm = L.mechanic("launch")
	_launches = lm.launches.map(func(r): return r.t) if lm != null else []
	moments.sort_custom(func(a, b): return a[0] < b[0])
	var off := 0
	var worst := 0.0
	var gated := 0
	var listed_worst := 0.0
	for x in moments:
		var n := roundf((x[0] - L.data.first_bar_at) / L.beat)
		var dev: float = x[0] - (L.data.first_bar_at + n * L.beat)
		var gate: bool = x.size() < 3 or x[2]
		var bad := gate and absf(dev) > GRID_TOL
		if gate:
			gated += 1
			worst = maxf(worst, absf(dev))
		else:
			listed_worst = maxf(listed_worst, absf(dev))
		if bad:
			off += 1
		print("GRID L%d %8.3f %+7.3f %s %s %s" % [lv, x[0], dev, "gate" if gate else "list", "OFF" if bad else "on ", x[1]])
	all_off += off
	print("GRID L%d: %d required presses, %d gated moments, %d off the grid (more than %d ms), worst %.0f ms; %d listed only, worst %.0f ms" % [
		lv, presses, gated, off, roundi(GRID_TOL * 1000.0), worst * 1000.0, moments.size() - gated, listed_worst * 1000.0])
