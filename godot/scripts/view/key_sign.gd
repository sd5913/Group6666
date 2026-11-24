extends Control
## 按键牌 (the tutorial's sign): the key to press as a solid pixel-art key cap, in that key's own colours (scripts/view/
## key_label.gd), hanging over a point of the screen, with a little white hand beside it that keeps pointing at it; its
## word for a long press (HOLD / RELEASE) over it. Pressed, the cap goes down into its edge. All of it is drawn in whole
## art pixels (the pixel font's own, kept whole on screen like the HUD's lettering).

const KeyLabel := preload("res://scripts/view/key_label.gd")
const LINE := Color("#14142A")  # its outline, and the ink of the key's name
const CAP_SIZE := 30.0          # about this big a lettering (canvas units; then a whole multiple of the font's size)
const PAD_X := 4                # art pixels round the key's name, across,
const PAD_Y := 3                # and up and down,
const EDGE := 3                 # how thick the cap's edge shows under its face
const HAND_GAP := 2             # art pixels between the cap and the hand at its closest
const POKE_HZ := 1.5            # the hand pokes at the key this often,
const POKE := 3                 # this far (the hand's pixels)
const SHAKE_T := 0.25           # a wrong key shakes the sign this long (seconds)
const SHAKE := 2.0              # this far (art pixels)
const HAND := [                 # o outline, W the hand, C the cuff (drawn turned round: pointing left, at the cap)
	"....oooooo......",
	"...oWWWWWWooooo.",
	"oooWWWWWWWWWWWWo",
	"oCCoWWWooooooooo",
	"oCCoWWWWWWWo....",
	"oCCoWWoooooo....",
	"oCCoWWWWWWo.....",
	"oooWWWoooo......",
	"...oWWWWWo......",
	"....ooooo.......",
]

var hud
var key := "SPACE"
var word := ""
var down := false
var at := Vector2.ZERO          # the point it hangs over (canvas units; the middle of the cap's bottom edge)
var under := false              # it hangs under that point instead (the hero upside down)
var _time := 0.0
var _shake := 0.0


func setup() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func shake() -> void:
	_shake = SHAKE_T


func _process(delta: float) -> void:
	_time += delta
	_shake = maxf(0.0, _shake - delta)
	if visible:
		queue_redraw()


func _draw() -> void:
	var s: float = hud._px_scale()
	var k: int = clampi(roundi(CAP_SIZE * s / hud.FONT_PX), 1, 3)
	var u: float = k / s  # an art pixel (canvas units)
	var font: Font = hud.font_or_default()
	var fs: int = maxi(1, roundi(k * hud.FONT_PX / s))
	var cols: Array = KeyLabel.colors_of(key)
	var text_w: int = ceili(font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x / u)
	var text_h: int = ceili(font.get_ascent(fs) * 0.8 / u)  # (the capitals')
	var w: int = text_w + 2 * PAD_X + 2
	var face_h: int = text_h + 2 * PAD_Y
	var h: int = face_h + EDGE + 2
	var o: Vector2 = at - Vector2(w * 0.5, 0.0 if under else float(h)) * u
	if _shake > 0.0:
		o.x += roundf(sin(_shake * 50.0) * SHAKE) * u
	o = (o * s).round() / s  # (on whole screen pixels)
	var box := func(x: int, y: int, bw: int, bh: int, c: Color) -> void:
		draw_rect(Rect2(o + Vector2(x, y) * u, Vector2(bw, bh) * u), c)
	# the outline, its corners cut; the edge under the face; the face, in bands down its colours, its top row lighter
	box.call(1, 0, w - 2, h, LINE)
	box.call(0, 1, w, h - 2, LINE)
	var sunk: int = EDGE - 1 if down else 0
	box.call(1, 1 + face_h, w - 2, EDGE, cols[1].darkened(0.45))
	for i in face_h:
		box.call(1, 1 + sunk + i, w - 2, 1, cols[0].lerp(cols[1], floorf(i * 4.0 / face_h) / 3.0))
	box.call(1, 1 + sunk, w - 2, 1, cols[0].lightened(0.55))
	var base: Vector2 = o + Vector2(1 + PAD_X, 1 + sunk + PAD_Y + text_h) * u
	draw_string(font, base, key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, LINE)
	_draw_hand(o + Vector2(w + HAND_GAP, h * 0.5) * u, k, s, cols[1])
	if word != "":
		var word_w: float = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var y: float = o.y + h * u + font.get_ascent(fs) + 3.0 * u if under else o.y - 3.0 * u
		var pos: Vector2 = (Vector2(o.x + w * 0.5 * u - word_w * 0.5, y) * s).round() / s
		draw_string_outline(font, pos, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(1, roundi(2.0 * k / s)), hud.OUTLINE)
		draw_string(font, pos, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, hud.ACTION_COLOR)


## The hand, its fingertip at the left of `tip` (a little further while it pokes): its pixels a size up from the cap's.
func _draw_hand(tip: Vector2, k: int, s: float, cuff: Color) -> void:
	var hu: float = (k + 1) / s
	var poke: float = floorf((0.5 + 0.5 * sin(_time * TAU * POKE_HZ)) * (POKE + 0.999))
	var cols: int = HAND[0].length()
	var o: Vector2 = tip + Vector2(poke * hu, -HAND.size() * 0.5 * hu)
	o = (o * s).round() / s
	for r in HAND.size():
		var row: String = HAND[r]
		for c in cols:
			var ch: String = row[c]
			if ch == ".":
				continue
			var color: Color = LINE if ch == "o" else (cuff if ch == "C" else Color.WHITE)
			draw_rect(Rect2(o + Vector2(cols - 1 - c, r) * hu, Vector2.ONE * hu), color)
