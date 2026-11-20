extends Node
## Gives the web entry screen the ready states of the existing title and level.

var browser: JavaScriptObject
var start_callback: JavaScriptObject
var title_id: int
var start_requested := false
var launching := false
var was_muted := false


func _ready() -> void:
	if not OS.has_feature("web"):
		set_process(false)
		return
	browser = JavaScriptBridge.get_interface("window")
	start_callback = JavaScriptBridge.create_callback(_request_start)
	browser.tavernStart = start_callback
	was_muted = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)


func _request_start(_args: Array) -> void:
	start_requested = true


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	if title_id == 0 and scene.has_method("_warmed") and not scene.get("warming"):
		title_id = scene.get_instance_id()
		browser.tavernNotify("title-ready")

	if start_requested and title_id == scene.get_instance_id():
		start_requested = false
		launching = true
		# Keep the game's run-state reset, intro flags and iris transition.
		scene.call("_start")

	if launching and title_id != scene.get_instance_id():
		set_process(false)
		AudioServer.set_bus_mute(0, was_muted)
		await RenderingServer.frame_post_draw
		browser.tavernNotify("memory-ready")
