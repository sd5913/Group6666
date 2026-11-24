extends "res://scripts/mechanics/mechanic.gd"
## 4c up-leaps (part of 5-4 琴键台阶): a spring that throws the player up onto the higher key, landing 2 beats later,
## wherever that fits between the other airborne stretches. SPRING_MODE "auto" springs throw by themselves;
## "press" springs only fire on a jump press and have a gap after them; "none": no 4c springs, only the pillars they
## would stand and land on (so the run and the stars there stay as they are), walked over like any others. With terraces
## (scripts/core/terrace.gd) the
## springs are its steps up instead (SPRING_TERRACE_MODE): a beat before the step's note, landing on the higher terrace
## right on it; outside a section's terraces the 4c springs stay.

const Draw := preload("res://scripts/view/draw.gd")

var SPRING_MODE := "auto"      # 4c springs: "auto" throw by themselves; "press" need jump, over a gap; "none": there are none
var SPRING_WINDOW := 0.16      # press springs: input window (seconds)
var SPRING_TERRACE_MODE := "press"  # a terrace's steps up: "auto" or "press" springs

var springs: Array = []         # {t, land_t, used, press, seg, node, fired}
var _pillars_only: Array = []   # SPRING_MODE "none": [t, land] of the 4c springs there would be
var mat: Material


## The tutorial's spring, at at[0], landing at at[1].
func teach(at: Array, _kind := "") -> void:
	springs.append({"t": at[0], "land_t": at[1], "used": false, "press": true, "track": "lead"})
	L.pits.append([at[0] + 0.12, at[1] - L.LAND_EDGE_T])
	L.air_spans.append([at[0], at[1]])


func plan_air() -> void:
	if not L.terrace.is_empty():
		for st in L.terrace.filter(func(st): return st.kind == "spring"):
			var press := SPRING_TERRACE_MODE == "press"
			springs.append({"t": st.t - L.beat, "land_t": st.t, "used": false, "press": press, "track": "lead"})
			if press:
				L.pits.append([st.t - L.beat + 0.12, st.t - L.LAND_EDGE_T])
			L.air_spans.append([st.t - L.beat, st.t])
		return  # (the 4c springs: below, or none with terraces all over)
	_plan_4c()


## With terraces only in some sections, the 4c springs elsewhere go in last, wherever there is room left.
func plan_fill() -> void:
	if not L.terrace_span.is_empty():
		_plan_4c()


func _plan_4c() -> void:
	for e in L.evs("4c"):
		if L.in_terrace(e.t) or L.in_terrace(e.t + 2.0 * L.beat):
			continue
		var ts: float = e.t
		var land: float = ts + 2.0 * L.beat
		var clash: bool = L.in_pit(ts) or L.in_pit(land)
		for s in L.air_spans + L.busy_spans + _pillars_only:
			if land > s[0] - 0.3 and ts < s[1] + 0.3:
				clash = true
		if clash:
			continue
		if SPRING_MODE == "none":
			_pillars_only.append([ts, land])
			continue
		var press := SPRING_MODE == "press"
		springs.append({"t": ts, "land_t": land, "used": false, "press": press})
		if press:
			L.pits.append([ts + 0.12, land - L.LAND_EDGE_T])
		L.air_spans.append([ts, land])


## SPRING_MODE "none": the pillars stay where the springs would be.
func plan_contacts() -> void:
	for p in _pillars_only:
		L.contacts.append(p[0])
		L.contacts.append(p[1])


func solve() -> void:
	for s in springs:
		L.arcs.append(L.arc(s.t, s.land_t, L.plat_h(s.land_t) + L.HALF))


func build() -> void:
	mat = Draw.mat(Color(0.3, 0.85, 0.5))
	for s in springs:
		s.seg = L.seg_at(s.t)
		var c := CylinderMesh.new()
		c.top_radius = 0.3
		c.bottom_radius = 0.42
		c.height = 0.3
		s.node = Draw.mesh(self, c, mat, Vector3(L.track.x_at(s.t), L.plat_h(s.t) + 0.15, 0.0))


## Springs on the melody's up-leaps (a terrace's spring: on the strong note it lands the player on).
func anchors() -> Array:
	return springs.map(func(s): return [s.land_t if s.has("track") else s.t, "lead"])  # (a terrace's: the note it lands on)


## Only "press" springs need the jump.
func cues() -> Array:
	return springs.filter(func(s): return s.press).map(func(s): return {"t": s.t, "action": "jump"})


func tips() -> Array:
	return ["[SPACE]\u00a0jump"] if springs.any(func(s): return s.press) else []


## Rides its pillar, squashing on the bass; just fired: squashed flat, springing back.
func update_motion(_delta: float) -> void:
	var bass: float = L.band_avg(L.now, 0, 2)
	for s in springs:
		s.node.position.y = (s.seg.top if not s.seg.is_empty() else L.ground_h(s.t)) + 0.15
		var pop := clampf(1.0 - (L.now - s.get("fired", -INF)) / 0.2, 0.0, 1.0)
		s.node.scale = Vector3(1.0 + 0.3 * pop, (1.0 - 0.45 * bass) * (1.0 - 0.6 * pop), 1.0 + 0.3 * pop)


func autoplay() -> void:
	for s in springs:
		if s.press and not s.used and L.now >= s.t - 0.004 and L.now <= s.t + SPRING_WINDOW and L.jump_press <= L.NONE:
			L.jump_press = L.now


## Press springs fire only on jump; an early press (up to L.EARLY_PRESS, or still kept then) waits for the spring's
## beat.
func jump_claim(press: float) -> int:
	for s in springs:
		if s.press and not s.used and L.press_kept(press) >= s.t - L.EARLY_PRESS and press <= s.t + SPRING_WINDOW:
			if L.now < s.t:
				return WAIT
			_fire(s)
			L.judge_early(press - s.t, SPRING_WINDOW, "Press SPACE as you land on the spring")
			return TAKEN
	return PASS


func hop_blocked() -> bool:
	return springs.any(func(s): return s.press and not s.used and s.t > L.now and s.t - L.now <= SPRING_WINDOW + 0.05)


## Auto springs throw whoever stands on them on their beat.
func after_step(_delta: float) -> void:
	for s in springs:
		if not s.press and not s.used and L.now >= s.t - 0.03 and L.now <= s.t + 0.12 and L.player.grounded:
			var tt: float = maxf(0.25, s.land_t - L.now)
			L.player.jump((L.plat_h(s.land_t) + L.HALF - L.player.global_position.y) / tt + L.GRAVITY * tt * 0.5)
			s.used = true
			s.fired = L.now
			L.sfx.play("spring")


## Throw the player from the spring up to the key it lands on (unless they have already fallen past it).
func _fire(s: Dictionary) -> void:
	s.used = true
	s.fired = L.now
	L.sfx.play("spring")
	if L.player.global_position.y > L.plat_h(s.t) + L.HALF - 0.8:
		var tt: float = maxf(0.2, s.land_t - L.now)
		L.player.jump((L.plat_h(s.land_t) + L.HALF - L.player.global_position.y) / tt + L.GRAVITY * tt * 0.5)


func fail_reason() -> String:
	if springs.any(func(s): return s.press and not s.used and L.now - s.t > 0.0 and L.now - s.t < 1.5):
		return "Missed a jump: press SPACE on the green spring to reach the high platform"
	return ""


## Carrying on from t: the springs before it have fired.
func skip_to(t: float) -> void:
	for s in springs:
		if s.t < t:
			s.used = true


## The intro panel: JUMP.
func panel_caption() -> Dictionary:
	return {"JUMP": "Jump (SPACE) on the note"} if not springs.is_empty() else {}


## The intro panel's drawing: a spring on the ground.
func panel_sprites() -> Array:
	if springs.is_empty():
		return []
	var g := Color(0.3, 0.85, 0.5)  # (its colour: the springs' material)
	return [{"family": "JUMP", "t": springs.map(func(s): return s.t).min(), "palette": {"g": g, "G": g.lightened(0.35), "t": L.theme_color}, "rows": ["............", "............", "..GGGGGGGG..", "....gggg....", "...g....g...", "....gggg....", "...g....g...", "....gggg....", "...g....g...", "..GGGGGGGG..", "tttttttttttt", "tttttttttttt"]}]
