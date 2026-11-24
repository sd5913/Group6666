extends Node3D
## Tab: every music event written above its spot, coloured by sub-level, plus whatever the mechanics want to label.

const BRANCH_NAME := {
	"1a": "强拍底鼓", "1b": "切分底鼓", "1c": "抢拍底鼓", "1d": "开头弱起",
	"2a": "反拍拍手", "2b": "重音", "2c": "加花连击",
	"3a": "律动小节", "3b": "短留白", "3c": "长留白",
	"4a": "旋律长音", "4b": "乐句最高音", "4c": "向上大跳", "4d": "向下大跳",
	"5a": "乐句起点", "5b": "回到主和弦", "5c": "离开主和弦",
	"6a": "段落变强", "6b": "段落变弱", "6c": "换鼓型", "6d": "高潮", "6e": "结尾",
}
const SUB_COLOR := {
	"1": Color(0.89, 0.29, 0.28), "2": Color(0.85, 0.56, 0.0), "3": Color(0.11, 0.69, 0.48),
	"4": Color(0.16, 0.47, 0.84), "5": Color(0.38, 0.31, 0.84), "6": Color(0.75, 0.25, 0.56),
}

var L


func build() -> void:
	visible = false
	var stack := {}
	for e in L.data.events:
		var key := "%.2f" % e.t
		var k: int = stack.get(key, 0)
		stack[key] = k + 1
		_label("%s %s" % [e.branch, BRANCH_NAME.get(e.branch, "")], 40, SUB_COLOR[e.branch.substr(0, 1)],
			Vector3(L.track.x_at(e.t), L.path_y(e.t) + 1.4 + 0.32 * k, 0.6))
	for m in L.mechanics:
		for item in m.labels():
			_label(item[0], 36, item[2] if item.size() > 2 else SUB_COLOR["1"], item[1])


func _label(text: String, size: int, color: Color, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = L.hud.dev_font()
	l.font_size = size
	l.pixel_size = 0.005
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = color
	l.outline_size = 10
	l.position = pos
	add_child(l)
