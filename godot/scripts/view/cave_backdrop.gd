extends MeshInstance3D
## Distant background art for levels 2–5. The playfield draws in front of it.

const BackdropShader := preload("res://shaders/cave_backdrop.gdshader")
const ATLAS_PATH := "res://assets/backgrounds/level_caves.png"
const HAZE := [Color("#123238"), Color("#292039"), Color("#17263a"), Color("#321f30")]

var haze: Color
var _material: ShaderMaterial


func setup(level: int) -> void:
	var index := level - 2
	haze = HAZE[index]
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	position.z = -120.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = BackdropShader
	_material.set_shader_parameter("cave_atlas", load(ATLAS_PATH))
	_material.set_shader_parameter("cave_index", index)
	material_override = _material


func follow(camera_x: float, time: float, beat: float) -> void:
	_material.set_shader_parameter("camera_scroll", camera_x * 0.0019)
	_material.set_shader_parameter("song_time", time)
	_material.set_shader_parameter("resonance", beat)
