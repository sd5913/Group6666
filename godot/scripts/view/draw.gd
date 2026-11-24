extends RefCounted
## Small drawing helpers shared by the pillars and every mechanic.

const CAP_H := 0.1             # glowing cap plate on every column

## Compatibility's shaders reach only 256 slots of per-object data, 16 objects' worth (desktop GL reads past them, WebGL doesn't):
## there every object has its own copy of its material instead.
static var few_slots: bool = RenderingServer.get_current_rendering_method() == "gl_compatibility"
static var _copies := {}        # shared material -> weak references to its copies
static var _shared_now := {}    # shared material -> {what was last set on it and all its copies}


## A level is starting: let go of the last one's materials, which these two would otherwise keep alive.
static func forget() -> void:
	_copies.clear()
	_shared_now.clear()


## One object's own value of a shader parameter.
static func param(node: GeometryInstance3D, what: StringName, value: Variant) -> void:
	if not few_slots:
		node.set_instance_shader_parameter(what, value)
		return
	var m: ShaderMaterial = node.material_override
	if not node.has_meta(&"own_material") or node.get_meta(&"own_material") != m:
		var shared := m
		m = shared.duplicate()
		node.material_override = m
		node.set_meta(&"own_material", m)
		if not _copies.has(shared):
			_copies[shared] = []
		_copies[shared].append(weakref(m))
	m.set_shader_parameter(what, value)


## A shader parameter of a material many objects share.
static func shared_param(shared: ShaderMaterial, what: StringName, value: Variant) -> void:
	if not few_slots:
		shared.set_shader_parameter(what, value)
		return
	var now: Dictionary = _shared_now.get_or_add(shared, {})
	if now.get(what) == value:
		return
	now[what] = value
	shared.set_shader_parameter(what, value)
	var list: Array = _copies.get(shared, [])
	for i in range(list.size() - 1, -1, -1):
		var m: ShaderMaterial = list[i].get_ref()
		if m == null:
			list.remove_at(i)
		else:
			m.set_shader_parameter(what, value)


static func mat(albedo: Color, emission := Color.BLACK, energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED  # the extruded ground is built without caring about winding
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


static func mesh(parent: Node, m: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	return mi


## Paint one column (stem or cap) through the shared pillar shader.
static func shade(node: GeometryInstance3D, tint: Color, glow: float, edge: float) -> void:
	param(node, "tint", tint)
	param(node, "glow", clampf(glow, 0.0, 1.0))
	param(node, "edge_y", edge)


## Square column from lo to hi with its glowing cap at the top (or at the bottom for hanging columns).
## The stem stops where the cap starts, so no two faces share a plane (that flickered before).
static func place_column(stem: Node3D, cap: Node3D, x: float, lo: float, hi: float, w: float, d: float, cap_on_top := true) -> void:
	var stem_lo := lo if cap_on_top else lo + CAP_H
	var stem_hi := hi - CAP_H if cap_on_top else hi
	stem.position = Vector3(x, (stem_lo + stem_hi) * 0.5, 0.0)
	stem.scale = Vector3(w, maxf(0.01, stem_hi - stem_lo), d)
	cap.position = Vector3(x, hi - CAP_H * 0.5 if cap_on_top else lo + CAP_H * 0.5, 0.0)
	cap.scale = Vector3(w + 0.06, 1.0, d + 0.06)


static func quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, normal: Vector3) -> void:
	for p in [p0, p1, p2, p0, p2, p3]:
		st.set_normal(normal)
		st.add_vertex(p)


## A one-shot spray of little cubes.
static func burst(parent: Node, pos: Vector3, material: Material, amount: int, speed := 5.0, size := 0.18) -> void:
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size, size, size)
	p.mesh = bm
	p.material_override = material
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.7
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.6
	p.initial_velocity_max = speed * 1.4
	p.gravity = Vector3(0, -18, 0)
	p.position = pos
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
