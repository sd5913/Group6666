extends SceneTree
## Play a level on autoplay headless and dump its layout + the player's path to JSON for plotting:
##   godot --headless --path <project> --script dump_layout.gd -- --level=N --out=<file.json>

var level: Node
var clock := 0.0
var started := false
var out_path := ""
var path := []
var jaw_at := {}   # jaw index -> [centre, gap] just before it slams
var last := -INF


func _initialize() -> void:
	var lv := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			lv = int(a.substr(8))
		elif a.begins_with("--out="):
			out_path = a.substr(6)
	level = load("res://scenes/level_%d.tscn" % lv).instantiate()
	root.add_child(level)


func _physics_process(delta: float) -> bool:
	clock += delta
	if not started and clock > 0.3:
		started = true
		level.autoplay = true
		level.state = "countdown"
		level.now = level.t_start
	if started and (level.state == "play" or level.state == "countdown"):
		var p: Vector3 = level.player.global_position
		if level.now - last >= 0.02:
			last = level.now
			path.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
		for i in level.blocks.size():
			var b: Dictionary = level.blocks[i]
			if not jaw_at.has(i) and level.now >= b.t - 0.01:
				jaw_at[i] = [b.centre, b.gap]
	if started and (level.state == "fail" or level.state == "win"):
		_dump()
		return true
	return false


func _dump() -> void:
	var L = level
	var d := {"level": L.data.level, "state": L.state, "theme": L.theme_color.to_html(false), "path": path}
	d.mech = L.mech.map(func(s): return [L.track.x_at(s.ta), L.track.x_at(s.tb), s.base, s.has("drum")])
	d.bars = L.bars.map(func(b): return [b.x, b.r, b.base, b.amp])
	d.pits = L.pits.map(func(p): return [L.track.x_at(p[0]), L.track.x_at(p[1])])
	d.drums = L.drums.map(func(dr): return {"x": L.track.x_at(dr.t), "r": dr.r, "top": dr.seg.base, "skin_c": dr.skin_c,
		"mode": dr.mode, "kind": dr.get("kind", "1a"), "t": dr.t})
	var jaws := []
	for i in L.blocks.size():
		var b: Dictionary = L.blocks[i]
		var cg: Array = jaw_at.get(i, [b.y, b.squeeze])
		jaws.append({"x": b.x, "w": b.w, "c": cg[0], "gap": cg[1], "big": b.big, "t": b.t, "air": b.seg.is_empty()})
	d.jaws = jaws
	d.springs = L.springs.map(func(s): return [L.track.x_at(s.t), L.plat_h(s.t), s.press])
	d.stars = L.stars.map(func(s): return [s.pos.x, s.pos.y])
	d.rings = L.air_dashes.map(func(a): return [L.track.x_at(a.t), L.path_y(a.t)])
	d.boosts = L.boosts.map(func(b): return [L.track.x_at(b[0]), L.track.x_at(b[1])])
	d.shapes = L.shape_changes.map(func(t): return L.track.x_at(t))
	d.goal = L.track.x_at(L.data.dur)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	print("DUMPED %s %s path=%d" % [out_path, L.state, path.size()])
