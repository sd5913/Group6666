extends CanvasLayer
## 按键提示 (the press prompts): what to press, said in big words at the top of the screen, a line over the judgement
## popup and in its lettering: JUMP! / FLIP! / DASH! / SLAM! / SLIDE! with its key under it in brackets, in the key's
## own colours (scripts/view/key_label.gd: [SPACE] cyan-blue, [SHIFT] lime-green, [S] pink-violet, the same in every
## level) and the word in its key's colour, HOLD! on a long note's start and RELEASE! on its end; an optional press (a
## drum, a jaw or a flute that only scores) just its bracketed key, half see-through.
## A prompt fades in CUE_SHOW_BEATS before its moment, small and see-through, grows steadily to full size, and on the
## moment (by the song clock) pops (1.3 times, back over POP_T) at full brightness; it goes the instant the press is
## judged (the judgement popup takes its place), or fades out if nothing is judged soon after. One prompt at a time: the
## next starts once the last needed one has been judged or has popped, and takes its place (an optional prompt holds
## nothing up: a needed one coming takes over even before it pops). Every mechanic says what its prompts are (mechanic.prompts(): its cues). Visual only: nothing here
## touches the play. CUE_TEXT 0 turns it off.

const POP_T := 0.12             # the pop on the moment (seconds),
const WAIT_T := 0.15            # then this long for a judgement
const FADE_T := 0.15            # before fading out over this long
const MATCH := 0.05             # a judgement is the prompt's whose moment is this close to the one pressed for,
const MISS_REACH := 0.7         # a miss the latest prompt's passed within this long
const FROM_SCALE := 0.6         # how big a prompt starts (of its full size),
const FROM_ALPHA := 0.4         # and how solid
const POPUP_SIZE := 34          # the judgement popup's letters (hud.gd), what CUE_TEXT_SCALE is of
const POPUP_TOP := 140.0        # and where it is (below the title row, clear of it even popping)
const GAP_PX := 20.0            # the key ends this many screen pixels over the judgement line (both may show)
const VERBS := {"jump": "JUMP", "dash": "DASH", "down": "SLAM"}
const KEYS := {"jump": "SPACE", "dash": "SHIFT", "down": "S"}
const KeyLabel := preload("res://scripts/view/key_label.gd")

var L
var items: Array = []           # {t, jt (judged then), verb, key, optional, judged_t (INF: not yet)}, in time order
var drawn_now := NAN            # the song time the prompt was last shown at (tools/capture.gd prints it)
var _box: Control
var _word: Label
var _key: Control                # the bracketed key under the word


## Every mechanic's prompts (a held press: one for the press, one for the let-go), and the labels they are shown in.
func build() -> void:
	layer = 5
	if L.CUE_TEXT == 0:
		return
	for m in L.mechanics:
		for c in m.prompts():
			var opt: bool = c.get("optional", false)
			var held: bool = c.has("until")
			items.append({"t": c.t, "jt": c.get("judge_t", c.t), "optional": opt, "key": KEYS[c.action], "judged_t": INF,
				"verb": KEYS[c.action] if opt else ("HOLD" if held else c.get("verb", VERBS[c.action])) + "!"})
			if held:
				items.append({"t": c.until, "jt": c.until, "optional": false, "key": KEYS[c.action], "judged_t": INF,
					"verb": "RELEASE!"})
	# an optional press on the same key at the same moment as a needed one is the same press (level 1: a jaw on an
	# air dash's beat)
	var needed: Array = items.filter(func(n): return not n.optional)
	var same := func(n, m): return m.key == n.key and absf(m.t - n.t) < 0.03
	items = items.filter(func(n): return not n.optional or not needed.any(func(m): return same.call(n, m)))
	items.sort_custom(func(a, b): return a.t < b.t)
	var font: Font = L.hud.font_or_default()
	_box = Control.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_word = _label(font, POPUP_SIZE * L.CUE_TEXT_SCALE, 2, 3)
	_key = KeyLabel.new()
	_key.hud = L.hud
	_key.visible = false
	_box.add_child(_key)
	_key.setup(22.0, 1, 2)


## A label about `size` big (canvas units), at lo to hi multiples of the pixel font's size on screen (hud.fit).
func _label(font: Font, size: float, lo: int, hi: int) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = font
	ls.outline_color = L.hud.OUTLINE  # (the popup's)
	L.hud.fit(ls, size, lo, hi)
	l.label_settings = ls
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	_box.add_child(l)
	return l


## A press was judged just now (err in seconds, early negative), or missed: its prompt goes (the popup takes its place).
## A press is judged as it is made (its prompt's moment at now - err) or, waiting for its note, on the note (at now);
## a miss comes on its moment or a little after it.
func judged(err: float, missed: bool) -> void:
	var now: float = L.now
	var best := {}
	var best_d: float = MISS_REACH if missed else MATCH
	for n in items:
		if n.jt > now + 1.0:
			break
		if n.judged_t < INF or (missed and n.jt > now + MATCH):
			continue
		var d: float = absf(n.jt - now) if missed else minf(absf(n.jt - now), absf(n.jt - (now - err)))
		if d < best_d:
			best = n
			best_d = d
	if not best.is_empty():
		best.judged_t = now


## Each drawn frame: the prompt showing now, how big and how solid.
func update() -> void:
	if _box == null:
		return
	var now: float = L.now
	drawn_now = now
	var show: float = L.CUE_SHOW_BEATS * L.beat
	var tune: bool = L.state == "tune"  # (the clock moved by hand: the prompts as they would be, nothing judged)
	var shown := {}
	var free_from := -INF  # when the needed prompts before let the next one in: judged, or popped
	for n in items:
		var judged_t: float = INF if tune else n.judged_t
		var gone: float = judged_t if judged_t < INF else maxf(n.t + POP_T, n.jt) + WAIT_T + FADE_T
		var start: float = maxf(n.t - show, free_from)
		if not n.optional:
			free_from = maxf(free_from, minf(gone, n.t + POP_T))
		if now < start:
			break
		if now < gone:
			shown = n  # (a later one that has started takes its place)
	var a := 0.0
	var k := 1.0
	if not shown.is_empty():
		if now < shown.t:  # coming: growing and brightening up to the moment
			var u: float = clampf((now - (shown.t - show)) / show, 0.0, 1.0)
			a = lerpf(FROM_ALPHA, 1.0, u)
			k = lerpf(FROM_SCALE, 1.0, u)
		else:  # the moment: a pop, then waiting for the judgement, then fading
			var ph: float = now - shown.t
			a = 1.0 - clampf((now - (maxf(shown.t + POP_T, shown.jt) + WAIT_T)) / FADE_T, 0.0, 1.0)
			k = 1.0 + 0.3 * (1.0 - clampf(ph / POP_T, 0.0, 1.0)) if ph < POP_T else 1.0
		if shown.get("seen", INF) == INF and not tune:
			shown.seen = now  # (when it first showed: tools check it had its whole fade-in)
	_word.visible = not shown.is_empty() and not shown.optional
	_key.visible = not shown.is_empty()
	if shown.is_empty():
		return
	_word.text = shown.verb
	_word.label_settings.font_color = KeyLabel.colors_of(shown.key)[0]  # (the word in its key's colour, the dark outline kept)
	_key.key = shown.key
	# stacked: the word, the key under it, then GAP_PX clear before the judgement line (and the speed line under it)
	var vp: Vector2 = _box.get_viewport_rect().size
	var px: float = 1.0 / L.hud._px_scale()  # (the key stays on whole screen pixels: it never scales)
	var word_h: float = _word.label_settings.font_size * 1.4
	var ks: Vector2 = _key.text_size()
	var key_top: float = roundf((POPUP_TOP - GAP_PX * px - ks.y) / px) * px
	_word.size = Vector2(vp.x, word_h)
	_word.position = Vector2(0.0, key_top - word_h)
	_word.pivot_offset = _word.size * 0.5
	_word.scale = Vector2.ONE * k
	_word.modulate.a = a
	_key.position = Vector2(roundf((vp.x - ks.x) * 0.5 / px) * px, key_top)
	_key.modulate.a = a * (0.5 if shown.optional else 1.0)
