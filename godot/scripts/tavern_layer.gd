extends Node2D
## Draws the tavern from geometry exported by tools/export_tavern_commands.py.
## Static layers keep their draw commands cached, while the slimes, record,
## tonearm and glow can animate independently.

const RECORD_TILT := 0.38

var kind := "geometry" # geometry / record / glow / tonearm
var commands: Array = []
var young_color := Color("#ed5897")
var spin_angle := 0.0
var arm_angle := 0.0:
	set(value):
		arm_angle = value
		queue_redraw()
var arm_lift := 0.0:
	set(value):
		arm_lift = value
		queue_redraw()
var _slime_textures: Dictionary = {}


func _draw() -> void:
	match kind:
		"record":
			_draw_record()
		"glow":
			_draw_player_glow()
		"tonearm":
			_draw_tonearm()
		_:
			for command in commands:
				_draw_command(command)


func set_young_color(value: Color) -> void:
	young_color = value
	_slime_textures.clear()
	queue_redraw()


func _option(args: Array, kwargs: Dictionary, index: int, key: String, fallback: Variant) -> Variant:
	if args.size() > index and args[index] != null:
		return args[index]
	return kwargs.get(key, fallback)


func _color(value: Variant) -> Color:
	if value is Array:
		return Color8(int(value[0]), int(value[1]), int(value[2]))
	return Color.html(str(value))


func _points(items: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for item in items:
		result.append(Vector2(float(item[0]), float(item[1])))
	return result


func _draw_command(command: Dictionary) -> void:
	var op: String = command.op
	var args: Array = command.args
	var kwargs: Dictionary = command.kwargs
	match op:
		"poly":
			var points := _points(args[0])
			var fill = _option(args, kwargs, 1, "fill", null)
			var outline = _option(args, kwargs, 2, "outline", null)
			var width: float = float(_option(args, kwargs, 3, "width", 2))
			if fill != null:
				draw_colored_polygon(points, _color(fill))
			if outline != null:
				var closed := points.duplicate()
				closed.append(points[0])
				draw_polyline(closed, _color(outline), width)
		"rect":
			var b: Array = args[0]
			var rect := Rect2(float(b[0]), float(b[1]), float(b[2] - b[0] + 1), float(b[3] - b[1] + 1))
			var fill = _option(args, kwargs, 1, "fill", null)
			var outline = _option(args, kwargs, 2, "outline", null)
			var width: float = float(_option(args, kwargs, 3, "width", 2))
			if fill != null:
				draw_rect(rect, _color(fill))
			if outline != null:
				draw_rect(rect, _color(outline), false, width)
		"ellipse":
			var b: Array = args[0]
			var center := Vector2(float(b[0] + b[2]) * 0.5, float(b[1] + b[3]) * 0.5)
			var radii := Vector2(float(b[2] - b[0]) * 0.5, float(b[3] - b[1]) * 0.5)
			var points := PackedVector2Array()
			for i in 49:
				var angle := TAU * float(i) / 48.0
				points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
			var fill = _option(args, kwargs, 1, "fill", null)
			var outline = _option(args, kwargs, 2, "outline", null)
			var width: float = float(_option(args, kwargs, 3, "width", 2))
			if fill != null:
				draw_colored_polygon(points, _color(fill))
			if outline != null:
				draw_polyline(points, _color(outline), width)
		"line":
			draw_polyline(_points(args[0]), _color(args[1]), float(_option(args, kwargs, 2, "width", 2)))
		"shaded_poly":
			_draw_shaded_poly(args, kwargs)
		"glow":
			_draw_glow(args, kwargs)
		"slime":
			_draw_slime(args, kwargs)


func _draw_shaded_poly(args: Array, kwargs: Dictionary) -> void:
	var points := _points(args[0])
	var base := _color(args[1])
	var vertical: float = float(_option(args, kwargs, 2, "vertical", 0.0))
	var horizontal: float = float(_option(args, kwargs, 3, "horizontal", 0.0))
	var warm: float = float(_option(args, kwargs, 4, "warm", 0.0)) / 255.0
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	var colors := PackedColorArray()
	for point in points:
		var u := clampf((point.x - bounds.position.x) / maxf(1.0, bounds.size.x), 0.0, 1.0)
		var v := clampf((point.y - bounds.position.y) / maxf(1.0, bounds.size.y), 0.0, 1.0)
		var brightness := 1.0 + vertical * (0.5 - v) + horizontal * (0.5 - u)
		colors.append(Color(
			clampf(base.r * brightness + warm * (1.0 - v), 0.0, 1.0),
			clampf(base.g * brightness + warm * 0.48 * (1.0 - v), 0.0, 1.0),
			clampf(base.b * brightness - warm * 0.35 * (1.0 - v), 0.0, 1.0)))
	draw_polygon(points, colors)


func _draw_glow(args: Array, kwargs: Dictionary) -> void:
	var center := Vector2(float(args[0]), float(args[1]))
	var radius := Vector2(float(args[2]), float(args[3]))
	var color := _color(args[4])
	var strength: float = float(_option(args, kwargs, 5, "strength", 0.42))
	for ring in range(18, 0, -1):
		var size := float(ring) / 18.0
		var points := PackedVector2Array()
		for i in 49:
			var angle := TAU * float(i) / 48.0
			points.append(center + Vector2(cos(angle) * radius.x * size, sin(angle) * radius.y * size))
		var tint := color
		tint.a = strength * 0.11 * (1.0 - size * size)
		draw_colored_polygon(points, tint)


func _draw_slime(args: Array, kwargs: Dictionary) -> void:
	var box: Array = args[0]
	var elder: bool = bool(_option(args, kwargs, 3, "elder", false))
	var base: Color = _color(args[2]) if elder else young_color
	var key := "%s:%s" % [str(box), base.to_html()]
	if not _slime_textures.has(key):
		_slime_textures[key] = _make_slime_texture(box, float(args[1]), base, elder)
	draw_texture(_slime_textures[key], Vector2(float(box[0]), float(box[1])))
	if elder:
		_draw_elder_uniform()


func _draw_elder_uniform() -> void:
	# Only the shoulders and V collar show above the counter. Leave the beard,
	# glint and every facial feature at their original coordinates.
	draw_colored_polygon(PackedVector2Array([Vector2(468, 382), Vector2(490, 381),
		Vector2(532, 413), Vector2(518, 443), Vector2(459, 443)]), Color("#432a38"))
	draw_colored_polygon(PackedVector2Array([Vector2(604, 380), Vector2(629, 383),
		Vector2(644, 443), Vector2(574, 443), Vector2(561, 413)]), Color("#302735"))
	draw_colored_polygon(PackedVector2Array([Vector2(486, 382), Vector2(496, 383),
		Vector2(532, 410), Vector2(526, 414)]), Color("#e4d7be"))
	draw_colored_polygon(PackedVector2Array([Vector2(595, 382), Vector2(605, 381),
		Vector2(567, 414), Vector2(561, 409)]), Color("#c9c2b3"))
	draw_colored_polygon(PackedVector2Array([Vector2(531, 405), Vector2(548, 409),
		Vector2(555, 410), Vector2(569, 405), Vector2(564, 419), Vector2(550, 415),
		Vector2(536, 419)]), Color("#6d3543"))
	draw_circle(Vector2(550, 412), 4.0, Color("#a3635d"))


func _make_slime_texture(box: Array, radius: float, base: Color, elder: bool) -> ImageTexture:
	var w := int(box[2] - box[0])
	var h := int(box[3] - box[1])
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var hx := float(w) * 0.5
	var edge: Color = Color("#304244") if elder else Color.from_hsv(base.h, minf(1.0, base.s * 0.85), base.v * 0.49)
	for y in h:
		for x in w:
			var yy := float(y + int(box[1]))
			var xx := float(x + int(box[0]))
			var cx := float(box[0] + box[2]) * 0.5
			var crown := float(box[1]) + radius
			var row := clampf((yy - crown) / radius, -1.0, 0.0)
			var side := hx * sqrt(maxf(0.0, 1.0 - row * row))
			if yy >= crown:
				side = hx * (1.0 - 0.055 * (yy - crown) / maxf(1.0, float(box[3]) - crown))
			if not elder:
				var corner := clampf((yy - (float(box[3]) - 14.0)) / 14.0, 0.0, 1.0)
				side -= 7.7 * (1.0 - sqrt(maxf(0.0, 1.0 - corner * corner)))
			var flat_x := clampf(absf(xx - cx) / hx, 0.0, 1.0)
			var top := crown - radius * sqrt(maxf(0.0, 1.0 - flat_x * flat_x))
			var margin := minf(side - absf(xx - cx), minf(yy - top, float(box[3]) - 1.0 - yy))
			if margin < 0.0:
				continue
			var u := (xx - cx) / hx
			var v := (yy - float(box[1])) / maxf(1.0, float(h))
			var nx := clampf(u, -1.0, 1.0)
			var ny := clampf((v - 0.35) * 1.2, -1.0, 1.0)
			var nz := sqrt(maxf(0.04, 1.0 - 0.73 * nx * nx - 0.32 * ny * ny))
			var lambert := maxf(0.0, -0.48 * nx - 0.50 * ny + 0.72 * nz)
			var volume := 0.55 + 0.39 * lambert - 0.20 * clampf((v - 0.64) / 0.36, 0.0, 1.0) if elder else 0.64 + 0.52 * lambert - 0.23 * clampf((v - 0.64) / 0.36, 0.0, 1.0)
			var key_w := 0.27 * 104.0 / float(w)
			var key_h := 0.16 * 85.0 / float(h)
			var key_v := 0.14 if elder else 0.23
			var highlight := exp(-pow((u + 0.38) / key_w, 2.0) - pow((v - key_v) / key_h, 2.0))
			var broad := exp(-pow((u + 0.31) / 0.56, 2.0) - pow((v - 0.37) / 0.55, 2.0))
			var cool := clampf((u - 0.56) / 0.36, 0.0, 1.0) * (1.0 - v * 0.55)
			var shade := 1.0 if elder else 1.0 - 0.17 * clampf((yy - (float(box[3]) - 18.0)) / 9.0, 0.0, 1.0)
			var rim := 0.75 + 0.23 * clampf(margin / 20.0, 0.0, 1.0) if margin < 20.0 else 1.0
			var color := Color(
				(base.r * volume + highlight * (30.0 if elder else 67.0) / 255.0 + broad * (8.0 if elder else 16.0) / 255.0 + cool * 8.0 / 255.0) * shade * rim,
				(base.g * volume + highlight * (27.0 if elder else 51.0) / 255.0 + broad * (5.0 if elder else 9.0) / 255.0 + cool * 24.0 / 255.0) * shade * rim,
				(base.b * volume + highlight * (24.0 if elder else 47.0) / 255.0 + broad * (3.0 if elder else 5.0) / 255.0 + cool * 34.0 / 255.0) * shade * rim)
			if margin <= 4.0:
				color = color * 0.25 + edge * 0.75
			color.a = 1.0
			image.set_pixel(x, y, color.clamp())
	return ImageTexture.create_from_image(image)


func _draw_record() -> void:
	_record_ellipse(46.0, Color("#211d2c"), Color("#876d72"), 4.0)
	for radius in [37.0, 33.0, 29.0]:
		_record_ellipse(radius, Color.TRANSPARENT, Color("#443244"), 1.7)
	_record_ellipse(20.0, Color("#bd5a78"))
	var marker := Vector2(cos(spin_angle) * 14.0, sin(spin_angle) * 5.4)
	draw_circle(marker, 3.4, Color("#f3c49c"))
	_record_ellipse(7.0, Color("#f2b66c"))


func _record_ellipse(radius: float, fill: Color, stroke := Color.TRANSPARENT, width := 1.0) -> void:
	var points := PackedVector2Array()
	for i in 49:
		var angle := TAU * float(i) / 48.0
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius * RECORD_TILT))
	if fill.a > 0.0:
		draw_colored_polygon(points, fill)
	if stroke.a > 0.0:
		draw_polyline(points, stroke, width)


func _draw_tonearm() -> void:
	# Rotate in the plane of the record before applying the same perspective.
	var path := PackedVector2Array([Vector2.ZERO, Vector2(-19, 18), Vector2(-35, 18)])
	var shadow := PackedVector2Array()
	for i in path.size():
		var p := path[i]
		var flat := Vector2(p.x, p.y / RECORD_TILT).rotated(arm_angle)
		var contact := Vector2(flat.x, flat.y * RECORD_TILT)
		path[i] = contact - Vector2(0.0, arm_lift * float(i) / 2.0)
		shadow.append(contact + Vector2(1.0, 2.0))
	var head := path[-1]
	var head_back := head + (path[-2] - head).normalized() * 9.0
	draw_polyline(shadow, Color(0.08, 0.04, 0.09, 0.38), 8.0)
	draw_polyline(path, Color("#473842"), 10.0)
	draw_polyline(path, Color("#c9b8ac"), 5.0)
	draw_line(head, head_back, Color("#473842"), 11.0)
	draw_line(head, head_back, Color("#efe0c7"), 6.0)
	draw_line(head + Vector2(0, 2), head + Vector2(0, 6), Color("#302432"), 3.0)


func _draw_player_glow() -> void:
	# The case is a cuboid. Follow its actual outer silhouette, one pixel beyond
	# the dark border, so the light sits on the player rather than the record.
	var outline := PackedVector2Array([Vector2(291, 391), Vector2(433, 391), Vector2(458, 408),
		Vector2(458, 439), Vector2(314, 439), Vector2(291, 423), Vector2(291, 391)])
	draw_polyline(outline, Color(1.0, 0.73, 0.26, 0.14), 11.0)
	draw_polyline(outline, Color(1.0, 0.82, 0.42, 0.52), 3.0)
