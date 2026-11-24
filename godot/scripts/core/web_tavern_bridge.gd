extends Node
## Connects the web presentation to the native tavern scene. The game owns
## level progress; the browser only shows the home, story and record controls.

const MenuProgress := preload("res://scripts/core/menu_progress.gd")
const LevelInfo := preload("res://scripts/core/level_info.gd")
const TAVERN_PATH := "res://scenes/tavern.tscn"

var _embedded := false
var _open_callback: JavaScriptObject
var _last_tavern_id := 0


func _ready() -> void:
	if not OS.has_feature("web"):
		set_process(false)
		return
	_embedded = bool(JavaScriptBridge.eval("window.parent !== window"))
	if not _embedded:
		set_process(false)
		return
	var preview: Variant = JavaScriptBridge.eval("new URLSearchParams(window.parent.location.search).get('previewAfterLevel')")
	if preview is String and preview.is_valid_int():
		var cleared_level := int(preview)
		if cleared_level >= 1 and cleared_level <= LevelInfo.COUNT:
			MenuProgress.advance_from(cleared_level)
	_open_callback = JavaScriptBridge.create_callback(_open_records)
	JavaScriptBridge.get_interface("window").openTavernRecords = _open_callback


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != TAVERN_PATH:
		return
	if scene.get_instance_id() == _last_tavern_id:
		return
	_last_tavern_id = scene.get_instance_id()
	var message := JSON.stringify({
		"type": "tavern-ready",
		"nextLevel": MenuProgress.next_level,
		"displayLevel": MenuProgress.display_level,
		"chairColor": "#" + MenuProgress.preview_color().to_html(false),
	})
	JavaScriptBridge.eval("window.parent.postMessage(%s, window.location.origin)" % message)


func _open_records(_args: Array) -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path == TAVERN_PATH:
		scene.call("_enter_records")
