extends CanvasLayer
## Pixel-art look over the whole run (shaders/pixel_post.gdshader): the 3D view is redrawn in big square art pixels with
## a few colour steps, a dither in the gradients and dark outlines. It sits between the 3D view and the HUD (a higher
## layer), so the HUD text stays sharp. F2 turns it on and off while playing.
## The art-pixel grid is pinned to the run: every frame it is placed where a fixed point in front of the track is on
## screen, as the camera is really drawn that frame (physics interpolation included), so the faces of the pillars and
## the player keep their pixels while the camera scrolls instead of shimmering ("pixel creep"). With a perspective
## camera this is exact only at the anchor's depth; the pillar and player faces are within about 0.5 m of it.

const PostShader := preload("res://shaders/pixel_post.gdshader")
const ANCHOR := Vector3(0.0, 0.0, 0.5)  # the grid is pinned here: level with the front faces of the pillars and player

var PIXEL_ON := true           # the pixel-art look at all
var PIXEL_PIN := true          # pin the art-pixel grid to the run (false: fixed to the screen, so it shimmers)
var PIXEL_ART_H := 270.0       # art pixels from the bottom of the screen to the top (fewer: bigger pixels)
var PIXEL_LEVELS := 16.0       # brightness steps
var PIXEL_CHROMA := 64.0       # steps of each colour axis (more: colours closer to the 3D view)
var PIXEL_DITHER := 0.8        # how strongly gradients are dithered (0: not at all, 1: a full step)
var PIXEL_OUTLINE := 0.4       # how much darker the dark side of an edge gets (0: no outlines)
var PIXEL_EDGE := 0.14         # brightness difference between neighbouring art pixels that counts as an edge
var PIXEL_HIGHLIGHT := 0.0     # how much lighter the light side of an edge gets
var PIXEL_SAT := 1.15          # colour saturation before the steps (1: unchanged)
var PIXEL_CONTRAST := 1.05
var L
var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	layer = 0  # over the 3D view, under the HUD
	_mat = ShaderMaterial.new()
	_mat.shader = PostShader
	_mat.set_shader_parameter("legacy_cave_grade", not L.uses_cave_art)
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if L.dev_on and key != null and key.pressed and not key.echo and key.keycode == KEY_F2:
		PIXEL_ON = not PIXEL_ON


## Every frame (the settings may have been changed by tuning.csv after _ready).
func _process(delta: float) -> void:
	_rect.visible = PIXEL_ON
	if not PIXEL_ON:
		return
	var cam := get_viewport().get_camera_3d()
	_mat.set_shader_parameter("grid", _screen_uv(cam, ANCHOR) if cam != null and PIXEL_PIN else Vector2.ZERO)
	_mat.set_shader_parameter("art_h", PIXEL_ART_H)
	_mat.set_shader_parameter("levels", maxf(2.0, PIXEL_LEVELS))
	_mat.set_shader_parameter("chroma_levels", maxf(2.0, PIXEL_CHROMA))
	_mat.set_shader_parameter("dither", PIXEL_DITHER)
	_mat.set_shader_parameter("outline", PIXEL_OUTLINE)
	_mat.set_shader_parameter("edge", PIXEL_EDGE)
	_mat.set_shader_parameter("highlight", PIXEL_HIGHLIGHT)
	_mat.set_shader_parameter("saturation", PIXEL_SAT)
	_mat.set_shader_parameter("contrast", PIXEL_CONTRAST)


## Where world point p is on screen (0..1, top left 0,0), with the camera where it is drawn this frame.
func _screen_uv(cam: Camera3D, p: Vector3) -> Vector2:
	var v := cam.get_global_transform_interpolated().affine_inverse() * p
	var clip := cam.get_camera_projection() * Vector4(v.x, v.y, v.z, 1.0)
	return Vector2(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5)
