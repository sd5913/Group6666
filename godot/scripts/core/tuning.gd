extends RefCounted
## config/tuning.csv: one row per setting (key, 说明, 默认, 第 1 关, 第 2 关 ...). An empty level cell falls back to
## 默认, an empty 默认 keeps the value written in the script. "player.X" rows go to the player, "track.X" to the speed
## map; every other key goes to whichever part of the level (level.gd, a mechanic, the look) has a setting by that name.

const PATH := "res://config/tuning.csv"
const BOM := "﻿"


## This level's value of every row that has one, in file order: [[key, text], ...].
static func read(level_no: int) -> Array:
	var out := []
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return out
	var col := -1
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 3 or row[0].strip_edges().trim_prefix(BOM) == "":
			continue
		if col < 0:  # the header row
			col = 2 + level_no if row.size() > 2 + level_no else 2
			continue
		var key := row[0].strip_edges().trim_prefix(BOM)
		if key.begins_with("#"):
			continue
		var v := row[col].strip_edges() if col < row.size() else ""
		if v == "":
			v = row[2].strip_edges()
		if v != "":
			out.append([key, v])
	return out


## The setting a key sets on target ("" if it has none): only variables its script declares (so a typo can't reach an
## engine property like position or visible); NAME_DEG fills NAME, in radians.
static func prop_of(target: Object, key: String) -> String:
	var script: Script = target.get_script()
	if script == null:
		return ""
	if script_has(script, key, false):
		return key
	if key.ends_with("_DEG") and script_has(script, key.trim_suffix("_DEG"), false):
		return key.trim_suffix("_DEG")
	return ""


## Whether a script (used in this level or not) declares the setting a key names (with_deg: NAME_DEG counts for NAME).
static func script_has(script: Script, key: String, with_deg := true) -> bool:
	for p in script.get_script_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and (p.name == key or (with_deg and p.name + "_DEG" == key)):
			return true
	return false


## Set one setting from its text, in the type it already has. False if target has no such setting.
static func apply(target: Object, key: String, v: String) -> bool:
	var prop := prop_of(target, key)
	if prop == "":
		return false
	var deg := prop != key
	match typeof(target.get(prop)):
		TYPE_FLOAT:
			target.set(prop, deg_to_rad(v.to_float()) if deg else v.to_float())
		TYPE_INT:
			target.set(prop, v.to_int())
		TYPE_BOOL:
			target.set(prop, v.to_lower() in ["1", "true", "yes", "on", "是", "开"])
		TYPE_COLOR:
			if Color.html_is_valid(v):
				target.set(prop, Color.html(v))
			else:
				push_warning("tuning.csv: %s = %s is not a colour like #ff8020" % [key, v])
		_:
			target.set(prop, v)
	return true


static func list(csv: String) -> Array:
	return Array(csv.split(",", false)).map(func(s): return s.strip_edges())
