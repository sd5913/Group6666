extends RefCounted
const DrawParam := preload("res://scripts/view/draw.gd")
## Columns and blocks made of voxels — the jaws (level 1), the walls (2), the slide blocks (3), the smash blocks (4):
## each is a MultiMesh of small cubes, built once per size and direction and shared by every column of that kind.
## Its working end (the face the player meets: a jaw's face towards the gap, a wall block's top, a hanging block's
## underside) is the origin, and it reaches `reach` metres away from it, down (dir -1) or up (dir 1). Only what the
## camera can see is filled: the first FULL metres are solid (a dent opens them up), beyond that the front face and
## the two sides.
## Whole and broken are both drawn by shaders/jaw_voxel.gdshader; a mechanic only moves the column, sets its colour
## and glow, breaks it (break_apart) and lets scripts/view/voxel_debris.gd age the pieces.

const VoxelShader := preload("res://shaders/jaw_voxel.gdshader")
const VOXEL := 0.15            # voxel edge (metres): about three art pixels at the run's depth
const FULL := 0.6              # metres from the working end that are solid

static var _meshes := {}
static var _material: ShaderMaterial
static var _stone_materials := {}


## A new column (w along the run, d across it) under parent, sharing its voxels with every column of that size.
static func make(parent: Node, w: float, d: float, reach: float, dir: int, gravity: float,
		cave_level := 0, cave_jaw := false) -> MultiMeshInstance3D:
	var key := "%.3f %.3f %.2f %d" % [w, d, reach, dir]
	if not _meshes.has(key):
		_meshes[key] = _build(w, d, reach, dir)
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = VoxelShader
		_material.set_shader_parameter("voxel", VOXEL)
	var material := _material
	if cave_level > 0:
		var style := Vector2i(cave_level, int(cave_jaw))
		if not _stone_materials.has(style):
			var stone := _material.duplicate() as ShaderMaterial
			stone.set_shader_parameter("cave_level", cave_level)
			stone.set_shader_parameter("cave_jaw", cave_jaw)
			_stone_materials[style] = stone
		material = _stone_materials[style]
	material.set_shader_parameter("gravity", gravity)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _meshes[key]
	mmi.material_override = material
	# room for the debris flying off it
	mmi.custom_aabb = AABB(Vector3(-8.0, -reach - 8.0 if dir < 0 else -8.0, -8.0), Vector3(16.0, reach + 16.0, 16.0))
	parent.add_child(mmi)
	return mmi


## Colour a whole column (glow 0..1). `shine` scales how much it whitens and glows: the jaws keep 1, small blocks
## standing against a pale sky read better with less (their colour stays saturated).
static func shade(col: GeometryInstance3D, tint: Color, glow: float, shine := 1.0) -> void:
	DrawParam.param(col, "tint", tint)
	DrawParam.param(col, "glow", clampf(glow, 0.0, 1.0))
	DrawParam.param(col, "shine", shine)


## Fade a column like the pillars do: full colour for `solid_len` metres from its working end, then over `fade_len`
## into the dark (far_sky 0) or into the sky (far_sky 1, for rows hanging from above; call set_sky every frame then).
static func fade(col: GeometryInstance3D, fade_len: float, solid_len := 0.0, far_sky := 0.0) -> void:
	DrawParam.param(col, "fade_len", fade_len)
	DrawParam.param(col, "solid_len", solid_len)
	DrawParam.param(col, "far_sky", far_sky)


## How much each voxel of a column is lighter or darker than its neighbours (1: as built, 0: smooth). On a far_sky
## column it melts away towards the sky end anyway.
static func grain(col: GeometryInstance3D, amount: float) -> void:
	DrawParam.param(col, "grain", amount)


## The sky colour the far_sky columns fade into (5-5 warm / cool), shared by every voxel column.
static func set_sky(color: Color) -> void:
	if _material != null:
		DrawParam.shared_param(_material, "sky", color)
	for style in _stone_materials:
		if style.y == 0:
			DrawParam.shared_param(_stone_materials[style], "sky", color)


## Break column `col` apart: `at` is where (world), `hole` the radius that goes at once and `hold` how much later the
## rest follows, `power` how hard (m/s), `push` the velocity handed on, `floor_top` / `floor_x0..x1` the ground under
## it (world; floor_top -INF: none).
static func break_apart(col: GeometryInstance3D, at: Vector3, hole: float, hold: float, power: float, push: Vector3,
		floor_top: float, floor_x0: float, floor_x1: float) -> void:
	var o := col.position
	DrawParam.param(col, "age", 0.0)
	DrawParam.param(col, "blast", at - o)
	DrawParam.param(col, "hole", hole)
	DrawParam.param(col, "hold", hold)
	DrawParam.param(col, "power", power)
	DrawParam.param(col, "push", push)
	DrawParam.param(col, "floor_y", floor_top - o.y if floor_top > -INF else -1000.0)
	DrawParam.param(col, "floor_x", Vector2(floor_x0 - o.x, floor_x1 - o.x))
	DrawParam.param(col, "glow", 0.6)  # bright, but still the column's colour


static func _build(w: float, d: float, reach: float, dir: int) -> MultiMesh:
	var nx := maxi(1, roundi(w / VOXEL))
	var nz := maxi(1, roundi(d / VOXEL))
	var ny := maxi(1, roundi(reach / VOXEL))
	var sx := w / nx
	var sy := reach / ny  # a short block keeps its exact height
	var sz := d / nz
	var full := roundi(FULL / sy)
	var cells := []
	for j in ny:
		for i in nx:
			for k in nz:
				# past the solid end only the faces the camera looks at: the front (+z) and the two sides
				if j >= full and k != nz - 1 and i != 0 and i != nx - 1:
					continue
				cells.append(Vector3((i + 0.5) * sx - w * 0.5, dir * (j + 0.5) * sy, (k + 0.5) * sz - d * 0.5))
	var box := BoxMesh.new()
	box.size = Vector3(sx, sy, sz)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = box
	mm.instance_count = cells.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d %d %d %d" % [nx, nz, ny, dir])
	for n in cells.size():
		var c: Vector3 = cells[n]
		mm.set_instance_transform(n, Transform3D(Basis(), c))
		var b := 1.0 + rng.randf_range(-0.14, 0.14)  # each voxel lighter or darker than its neighbours, so the blocks read
		mm.set_instance_color(n, Color(b, b, b))
		mm.set_instance_custom_data(n, Color(c.x, c.y, c.z, rng.randf()))
	return mm
