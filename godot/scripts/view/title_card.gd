extends Control
## 标题行 (TITLE_CARD): in a level entered afresh (not after R or a lost life), on stepping on the tutorial's plate (with
## no tutorial, after SPACE on the ready screen), the level's title as one line over a light dim of the scene, the song's
## name itself at the very middle of the window (the line as a whole may sit off to a side; it can cross the player, who
## stays as they are):
## "A - APRIL'S FINALE V2 (LOOP) ELECTRONIC - PRO SENSORY" (the last level "THAT - ..."), the level's letter in its
## colour a size up from the song's name, to its left, the author to its right, all on one baseline, the name and the
## author white, each with the HUD's dark outline. The letter snaps in at once, " - SONG" at TITLE_IN, " - AUTHOR" at
## TITLE_AUTHOR; held, it fades out from TITLE_FADE_AT to TITLE_END and the count-in runs. The world stands still and the
## music waits meanwhile (level state "title"); SPACE skips on to the fade. The song's size is the largest whole multiple
## of the pixel font's (FONT_PX, at most MAX_K of them on screen) at which, with its name in the middle, both sides stay
## MARGIN_PX from the screen's sides; the letter one multiple more, the author one less (one at least). Fitted again when
## the window changes.

const MAX_K := 3                # the song and author at most 3 × 20 = 60 px (the letter 80),
const MARGIN_PX := 40           # the line at least this far from the screen's sides (screen pixels)
const CAP := 2.0 / 3.0          # the capitals' height, of the font's ascent (the name's middle is theirs)
const DIM := Color(0.0, 0.0, 0.0, 0.25)

var L
var hud
var t := 0.0
var _dim: ColorRect
var _letter: Label
var _song: Label                # " - SONG" (it comes in as one piece; the name alone is what stands in the middle)
var _name := ""                 # the song's name, as its label has it
var _author: Label
var _scale := 0.0


func setup() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim = ColorRect.new()
	_dim.color = DIM
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_letter = _text(str(L.data.letter))
	_letter.label_settings.font_color = L.theme_color
	_name = str(L.data.song).to_upper()
	_song = _text(" - " + _name)
	_author = _text(" - " + str(L.data.author))
	_layout()
	_show()


## A label for the line: white, the HUD's dark outline (its size set in _layout).
func _text(s: String) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = hud.font_or_default()
	ls.outline_color = hud.OUTLINE
	l.label_settings = ls
	l.text = s.to_upper()
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _set_k(l: Label, k: int) -> void:
	l.label_settings.font_size = maxi(1, roundi(k * hud.FONT_PX / _scale))
	l.label_settings.outline_size = hud.outline_for(k, _scale)


func _width(l: Label) -> float:
	return hud.font_or_default().get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.label_settings.font_size).x


func _name_width() -> float:
	return hud.font_or_default().get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, _song.label_settings.font_size).x


## The sizes for the window now (see the top of the file): the letter k + 1, the song k, the author k - 1.
func _fit_sizes(vp: Vector2, margin: float) -> void:
	var room: float = vp.x * 0.5 - margin  # (either side of the middle)
	var k := MAX_K
	while true:
		_set_k(_letter, k + 1)
		_set_k(_song, k)
		_set_k(_author, maxi(1, k - 1))
		var half: float = _name_width() * 0.5
		if k <= 1 or (half + (_width(_song) - _name_width()) + _width(_letter) <= room and half + _width(_author) <= room):
			return
		k -= 1


## The line for the window now: the song's name with its middle (its capitals') at the window's, the letter left of it and
## the author right of it, all placed at once (so nothing moves as they snap in), sharing one baseline, every edge on a
## whole screen pixel.
func _layout() -> void:
	_scale = hud._px_scale()
	var snap := func(v: float) -> float: return roundf(v * _scale) / _scale
	var vp := get_viewport().get_visible_rect().size
	_fit_sizes(vp, MARGIN_PX / _scale)
	var font: Font = hud.font_or_default()
	var base: float = snap.call(vp.y * 0.5 + font.get_ascent(_song.label_settings.font_size) * CAP * 0.5)
	var after: float = float(_song.label_settings.font_size) / hud.FONT_PX  # (the empty font pixel after its last letter)
	var x_song: float = snap.call(vp.x * 0.5 - (_name_width() - after) * 0.5 - (_width(_song) - _name_width()))
	var at := {_letter: snap.call(x_song - _width(_letter)), _song: x_song, _author: snap.call(x_song + _width(_song))}
	for l in [_letter, _song, _author]:
		var fs: int = l.label_settings.font_size
		l.position = Vector2(at[l], snap.call(base - font.get_ascent(fs)))
		l.size = Vector2(_width(l) + l.label_settings.outline_size, fs * 1.2)


## SPACE meanwhile: straight on to the fade.
func skip() -> void:
	t = maxf(t, L.TITLE_FADE_AT)
	_show()


func _process(delta: float) -> void:
	if absf(hud._px_scale() - _scale) > 0.001:  # (the window was resized)
		_layout()
	t += delta
	_show()
	if t >= L.TITLE_END:
		L.title_done()
		queue_free()


## The line at time t: the letter, then the song's name, then its author snapping in; all of it fading out at the end.
func _show() -> void:
	_letter.visible = true
	_song.visible = t >= L.TITLE_IN
	_author.visible = t >= L.TITLE_AUTHOR
	modulate.a = 1.0 - clampf((t - L.TITLE_FADE_AT) / maxf(0.001, L.TITLE_END - L.TITLE_FADE_AT), 0.0, 1.0)
