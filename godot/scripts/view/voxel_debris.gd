extends Node
const DrawParam := preload("res://scripts/view/draw.gd")
## The broken voxel columns of one mechanic (scripts/view/voxel_column.gd) while their pieces fly: each drawn frame it
## hands them their age (on the frame clock, not the song's, so they keep falling after a fail too) and hides them
## once the last piece is gone.

var life := 2.2                 # seconds until the last piece of a broken column is gone

const SHRUNK_AT := 1.7          # the age by which even the slowest voxel has shrunk away (shaders/jaw_voxel.gdshader)
const HURRY_T := 0.25           # a life shorter than that: over its last this many seconds the age runs on to there,
                                # so the pieces shrink away where they are and don't vanish all at once

var _flying: Array = []         # {cols, age}


## Columns that have just been broken (break_apart) together.
func add(cols: Array) -> void:
	_flying.append({"cols": cols, "age": 0.0})


func _process(delta: float) -> void:
	for i in range(_flying.size() - 1, -1, -1):
		var f: Dictionary = _flying[i]
		f.age += delta
		var age: float = f.age
		if life < SHRUNK_AT and age > life - HURRY_T:
			age = lerpf(age, SHRUNK_AT, (age - life + HURRY_T) / HURRY_T)
		for col in f.cols:
			DrawParam.param(col, "age", age)
			col.visible = f.age < life
		if f.age >= life:
			_flying.remove_at(i)
