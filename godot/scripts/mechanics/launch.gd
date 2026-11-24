extends "res://scripts/mechanics/mechanic.gd"
## 5-2 发射墙 (level 4's loudest claps): a speaker block set into the row ahead thumps on the kicks (MIDI) as the player
## comes up to it. On the drum note a beat before a loud clap (MIDI velocity at least LAUNCH_VEL) it fires a wall of
## stacked blocks (LAUNCH_BLOCKS high) that slides along the row towards the player at a slow, heavy, steady
## LAUNCH_SPEED, so that on the clap its near face is a dash's lunge (player.LUNGE) ahead of the player, as a level 2
## wall stands: dash (SHIFT) on the clap and the lunging body smashes it, its voxels flying back the way it came and up.
## Without a dash it reaches the player and holds them up, as a wall does, while the window is still open (a dash then
## still smashes it); once the window is over the player is knocked back a little (then catches up with the beat), the
## wall bursts feebly and the streak starts again — not a failure. The speaker stands out of the row like a box while it
## thumps (and flashes, popping out, as it fires), then sinks flush just before the player gets to it, so the player
## runs over it. It is always in the row the player is on at the clap (where that row doesn't reach it, no wall is
## fired): upside down (mirror flip) it is set into the row above and its wall hangs from that row and slides along it.
## The wall's blocks are stacked with dark seams between them, and fading after-images trail it as it slides.

const Draw := preload("res://scripts/view/draw.gd")
const Spans := preload("res://scripts/core/spans.gd")
const PlayerScript := preload("res://scripts/player.gd")
const VoxelColumn := preload("res://scripts/view/voxel_column.gd")
const VoxelDebris := preload("res://scripts/view/voxel_debris.gd")

var LAUNCH_VEL := 104          # claps at least this loud fire a wall (softer ones are smash blocks)
var LAUNCH_FROM_PHRASE := 3    # the first phrase with walls fired
var LAUNCH_WINDOW := 0.16      # dash this close to the clap (seconds)
var LAUNCH_CLEAR := 0.35       # no fired wall this close to a flip (seconds)
var LAUNCH_SPEED := 3.0        # how fast the wall slides along the row towards the player (m/s)
var LAUNCH_SEND_BEATS := 1.0   # the speaker fires the wall this many beats before its clap (on the drum note there)
var LAUNCH_PULSE := "kick"     # before that it thumps on this track's notes
var LAUNCH_SEEN := 2.5         # it thumps from this long before it fires (seconds)
var LAUNCH_BLOCKS := 4         # the wall: this many blocks high,
var LAUNCH_BLOCK := 0.35       # each this high (metres),
var LAUNCH_W := 0.5            # and this thick along the run (metres)
var LAUNCH_KNOCK := 0.6        # run into: knocked back this far along the run (metres)
var LAUNCH_BURST := 6.5        # how fast the voxels of a smashed wall fly off (m/s; run into: about half)

const BLOCK_W := 0.9            # the speaker block along the run (metres)
const BLOCK_OUT := 0.5          # how far it stands out of the row while it thumps (metres)
const FACE_GAP := 0.25          # the player stops this far short of touching the wall (as at a level 2 wall)
const WALL_D := 0.72            # the wall's depth across the run: the player's
const RISE_T := 0.08            # a block of the wall shoots out of the speaker in this long (seconds),
const STAGGER := 0.03           # one after the other
const SEAM := 0.08              # the dark seam between two of the wall's blocks (metres: about two art pixels)
const GHOSTS := [0.35, 0.22, 0.12]  # the after-images trailing the wall: how opaque each is, nearest first,
const GHOST_STEP := 0.3         # and how far apart (metres)

var launches: Array = []        # {t, top, send, send_track, x, T, face_t, pulses, judged, hit, broken, held, near, ...}
var _debris: VoxelDebris        # smashed walls, while their voxels fly
var _plate_mat: StandardMaterial3D   # the speaker's plate,
var _flash_mat: StandardMaterial3D   # and the same flashing as it fires


func plan_air() -> void:
	var first: float = L.phrases[LAUNCH_FROM_PHRASE - 1] if L.phrases.size() >= LAUNCH_FROM_PHRASE else 0.0
	var flip = L.mechanic("flip")
	for n in L.song.notes("clap"):
		var t: float = n[0]
		if n[3] < LAUNCH_VEL or t < maxf(first, 0.6) - 0.001 or L.rest_beat(t):
			continue
		if L.GRID_LOCK != 0 and (not L.grid_ok(t) or L.beat_of(t) != 4):
			continue  # (the bar's pattern: a fired wall on beat 4)
		# the player stays on this row from a little before the clap until it could have caught up after being held
		var stay: Array = [t - LAUNCH_CLEAR, t + LAUNCH_WINDOW + 0.3]
		if L.air_spans.any(func(s): return stay[0] < s[1] and stay[1] > s[0]):
			continue
		var top: bool = L.up_at(t) < 0.0
		if not top and (L.in_pit(t) or L.in_pit(stay[1])):
			continue
		# the speaker stands where a wall fired on the drum note before the clap, sliding at LAUNCH_SPEED, has its near
		# face a lunge (and the stopping gap) ahead of the player on the clap
		var send: Array = _send(t)
		if "," in send[1]:
			continue  # no drum note to fire it on (as at a section's start)
		var face_t: float = L.track.x_at(t) + L.player_setting("LUNGE") + PlayerScript.RADIUS + FACE_GAP
		var x: float = face_t + LAUNCH_SPEED * (t - send[0]) + LAUNCH_W * 0.5
		var block_t: float = L.track.t_at(x)
		if block_t > L.data.dur - 0.5 or launches.any(func(r): return absf(r.T - block_t) < 0.4):
			continue
		if not _row_there(top, t, block_t, flip):
			continue  # (never on the other row)
		var pulses: Array = L.song.between(LAUNCH_PULSE, send[0] - LAUNCH_SEEN, send[0] - 0.05).map(func(p): return p[0])
		_add(t, top, send, face_t, x, block_t, pulses, stay[1], flip)


## A speaker at x (block_t as a time of run) firing at send[0] a wall to be dashed on t, the row flat for it.
func _add(t: float, top: bool, send: Array, face_t: float, x: float, block_t: float, pulses: Array, stay_to: float, flip) -> void:
	launches.append({"t": t, "top": top, "send": send[0], "send_track": send[1], "x": x, "T": block_t,
		"face_t": face_t, "pulses": pulses, "judged": false, "hit": false, "broken": false, "held": 0.0})
	L.busy_spans.append([t - 0.4, stay_to])
	var flat: Array = [t - 0.2]  # the row is flat from the run-up to the speaker: the wall slides along it
	var k := t
	while k < block_t + 0.1:
		flat.append(k)
		k += 0.1
	if top and flip != null:
		flip.top_contacts.append_array(flat)
	elif not top:
		L.contacts.append_array(flat)


## The tutorial's wall, for a dash at at[0]: thumping for two beats, fired LAUNCH_SEND_BEATS before it.
func teach(at: Array, _kind := "") -> void:
	var t: float = at[0]
	var send: float = t - LAUNCH_SEND_BEATS * L.beat
	var face_t: float = L.track.x_at(t) + L.player_setting("LUNGE") + PlayerScript.RADIUS + FACE_GAP
	var x: float = face_t + LAUNCH_SPEED * (t - send) + LAUNCH_W * 0.5
	_add(t, false, [send, "kick"], face_t, x, L.track.t_at(x), [send - 2.0 * L.beat, send - L.beat], t + LAUNCH_WINDOW + 0.3, null)


## When the wall is fired: on the speaker's own thump (a LAUNCH_PULSE note) nearest to LAUNCH_SEND_BEATS before the
## clap, between two beats and just over half a beat before it; failing that on another drum note there, and failing
## that on the beat itself. [time, its track]
func _send(t: float) -> Array:
	var at: float = t - LAUNCH_SEND_BEATS * L.beat
	for tracks in [[LAUNCH_PULSE], ["kick", "clap", "hat"]]:
		var best := []
		for k in tracks:
			for n in L.song.between(k, t - 2.0 * L.beat, t - 0.6 * L.beat):
				if best.is_empty() or absf(n[0] - at) < absf(best[0] - at):
					best = [n[0], k]
		if not best.is_empty():
			return best
	return [at, "kick,clap,hat"]


## Whether the player's row at the clap (below, or the hanging one above) is there all the way from the clap to past
## the speaker.
func _row_there(top: bool, t: float, block_t: float, flip) -> bool:
	var k := t - 0.2
	while k <= block_t + 0.2:
		if top and (flip == null or not Spans.inside(flip.top_spans, k)):
			return false
		if not top and L.in_pit(k):
			return false
		k += 0.1
	return true


func anchors() -> Array:
	var a := []
	for r in launches:
		a.append([r.t, "clap"])
		a.append([r.send, r.send_track])
	return a


func cues() -> Array:
	return launches.map(func(r): return {"t": r.t, "action": "dash"})


func tips() -> Array:
	return ["[SHIFT]\u00a0dash"] if not launches.is_empty() else []


# ---------------------------------------------------------------- look

## Each speaker: a voxel block set into the row with a plate on its face that thumps; its wall: stacked voxel blocks
## waiting inside it, a dark core behind them (it shows in the seams) and its after-images.
func build() -> void:
	_plate_mat = Draw.mat(Color.from_hsv(L.mats.accent.h, 1.0, L.mats.accent.v))
	_plate_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat = Draw.mat(L.mats.accent.lerp(Color.WHITE, 0.7))
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var core_mat := Draw.mat(L.mats.accent.darkened(0.65))
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ghost_mats := []
	for a in GHOSTS:
		var m := Draw.mat(Color(L.mats.accent, a))
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost_mats.append(m)
	var plate := BoxMesh.new()
	plate.size = Vector3(BLOCK_W * 0.7, 0.08, 1.0)
	var core := BoxMesh.new()
	core.size = Vector3(LAUNCH_W * 0.8, LAUNCH_BLOCKS * LAUNCH_BLOCK - SEAM, WALL_D * 0.8)
	var ghost := BoxMesh.new()
	ghost.size = Vector3(LAUNCH_W, LAUNCH_BLOCKS * LAUNCH_BLOCK - SEAM, WALL_D)
	for r in launches:
		r.col = VoxelColumn.make(self, BLOCK_W, 1.4, 0.6, 1 if r.top else -1, L.GRAVITY)
		r.col.position = Vector3(r.x, 0.0, 0.0)
		r.plate = Draw.mesh(self, plate, _plate_mat, Vector3(r.x, 0.0, 0.0))
		r.near = r.x - LAUNCH_W * 0.5
		r.blocks = []
		for i in LAUNCH_BLOCKS:  # each block's origin is the face away from the row it stands on
			var node := VoxelColumn.make(self, LAUNCH_W, WALL_D, LAUNCH_BLOCK - SEAM, 1 if r.top else -1, L.GRAVITY)
			node.position = Vector3(r.x, -100.0, 0.0)
			r.blocks.append(node)
		r.core = Draw.mesh(self, core, core_mat, Vector3(r.x, -100.0, 0.0))
		r.core.visible = false
		r.ghosts = []
		for m in ghost_mats:
			var g := Draw.mesh(self, ghost, m, Vector3(r.x, -100.0, 0.0))
			g.visible = false
			r.ghosts.append(g)


## The face of the speaker's row at x right now: the run below, or the hanging row above.
func _surface_at(top: bool, x: float) -> float:
	var t: float = L.track.t_at(x)
	if top:
		var roof: float = L.roof_at(t, x)
		roof = roof if roof < INF else L.roof_h(t)
		return roof if roof < INF else NAN
	var y: float = L.support_at(t, x)
	return y if y > -INF else L.plat_h(t)


## Where the wall's near face is right now: in the speaker until it is fired, then sliding towards the player — unless
## it has run into them, where it stays.
func _near(r: Dictionary) -> float:
	return r.near if r.held > 0.0 else near_at(r, L.now)


## Where wall r's near face is at song time t, sliding freely: on the clap a lunge and the stopping gap ahead of the
## player, LAUNCH_SPEED further each second before that, back to the speaker it was fired from.
func near_at(r: Dictionary, t: float) -> float:
	return minf(r.x - LAUNCH_W * 0.5, r.face_t + LAUNCH_SPEED * (r.t - t))


## The speaker thumps on every pulse (hardest as it fires) and stands out of the row until just before the player gets
## there; the wall shoots out of it, block after block, as it is fired, and slides along the row, brightening up to the
## clap and shuddering while it holds the player up.
func update_motion(_delta: float) -> void:
	var now: float = L.now
	var x0: float = L.view_x0()
	var x1: float = L.view_x1()
	for r in launches:
		if r.x < x0 or r.x - 4.0 > x1:
			continue
		var sgn := -1.0 if r.top else 1.0
		var y: float = _surface_at(r.top, r.x)
		if is_nan(y):
			continue
		var thump := 0.0
		for p in r.pulses:
			if now >= p:
				thump = maxf(thump, 0.6 * exp(-(now - p) * 9.0))
		var flash: float = exp(-(now - r.send) * 8.0) if now >= r.send else 0.0  # firing: it lights up and pops out
		thump = maxf(thump, flash)
		# out of the row while it thumps, then back down to a touch proud of it just before the player gets there
		var out: float = smoothstep(r.send - LAUNCH_SEEN - 0.2, r.send - LAUNCH_SEEN, now) * (1.0 - smoothstep(r.T - 0.5, r.T - 0.25, now))
		var face: float = y + sgn * (0.04 + BLOCK_OUT * out + 0.25 * flash)
		r.col.position = Vector3(r.x, face, 0.0)
		VoxelColumn.shade(r.col, L.mats.accent, minf(1.0, 0.1 + 0.5 * thump + 0.4 * flash), L.BLOCK_SHINE)
		r.plate.position = Vector3(r.x, face + sgn * (0.04 + 0.14 * thump), 0.0)
		r.plate.scale = Vector3.ONE * (1.0 + 0.8 * flash)
		r.plate.material_override = _flash_mat if flash > 0.25 else _plate_mat
		if r.broken:
			continue
		r.near = _near(r)
		var cx: float = r.near + LAUNCH_W * 0.5
		var row: float = _surface_at(r.top, cx)
		if is_nan(row):
			row = y
		var shudder: float = 0.03 * sin(now * 70.0) if r.held > 0.0 else 0.0
		var lead: float = r.t - now
		var glow: float = 0.2 + 0.5 * (1.0 - clampf(lead / (r.t - r.send), 0.0, 1.0)) if lead > 0.0 else 0.7
		for i in r.blocks.size():
			var node: GeometryInstance3D = r.blocks[i]
			var age: float = now - r.send - i * STAGGER
			var k := clampf(age / RISE_T, 0.0, 1.0)  # 0: inside the speaker, 1: out, stacked on the row
			var slot: float = row + sgn * ((i + 1) * LAUNCH_BLOCK - SEAM * 0.5)  # its face away from the row
			var hidden: float = y - sgn * 0.1
			node.position = Vector3(cx + shudder, lerpf(hidden, slot, k) + sgn * 0.06 * sin(clampf(age / 0.2, 0.0, 1.0) * PI), 0.0)
			node.visible = age > 0.0
			VoxelColumn.shade(node, L.mats.accent, glow, L.BLOCK_SHINE)
		# the dark core in the seams, once the whole stack is out; the after-images behind it while it slides
		var out_all: bool = now >= r.send + (r.blocks.size() - 1) * STAGGER + RISE_T
		var mid: float = row + sgn * (LAUNCH_BLOCKS * LAUNCH_BLOCK * 0.5)
		r.core.visible = out_all
		r.core.position = Vector3(cx + shudder, mid, 0.0)
		var travelled: float = r.x - LAUNCH_W * 0.5 - r.near
		for g in r.ghosts.size():
			var back: float = (g + 1) * GHOST_STEP
			r.ghosts[g].visible = out_all and r.held == 0.0 and back <= travelled
			r.ghosts[g].position = Vector3(cx + back, mid, 0.0)


# ---------------------------------------------------------------- play

func autoplay() -> void:
	for r in launches:
		if not r.judged and L.now >= r.t - 0.004 and L.now <= r.t + 0.05 and L.dash_press < r.t - 0.08:
			L.press_dash()


## Where the player's centre stops in front of the wall right now (as at a level 2 wall).
func _stop(r: Dictionary) -> float:
	return _near(r) - PlayerScript.RADIUS - FACE_GAP


## A wall fired at the player that hasn't been dashed through stops them on its row.
func stop_x() -> float:
	for r in launches:
		if r.judged or r.broken or L.now < r.send or (L.player.up < 0.0) != r.top:
			continue
		if L.player.position.x <= _stop(r) + 0.01:
			return _stop(r)
	return INF


## A dash in the window carries the player through the wall, which bursts as the lunging body reaches it. Without one
## the wall reaches the player and holds them up; a dash still smashes it while the window is open; once it is over
## the player is knocked back and the wall bursts feebly (a miss).
func after_step(delta: float) -> void:
	var p: Vector3 = L.player.global_position
	for r in launches:
		if r.broken or L.now < r.t - LAUNCH_WINDOW:
			continue
		if not r.judged and absf(L.dash_press - r.t) <= LAUNCH_WINDOW:
			r.judged = true
			L.judge(L.dash_press - r.t)
			L.dash_press = L.NONE
		if (L.player.up < 0.0) != r.top:
			continue  # the player is on the other row
		var stop := _stop(r)
		if r.judged and not r.hit:
			if p.x + L.player.look.position.x >= stop - 0.05:  # where the body is drawn, lunging ahead
				_shatter(r, false)
		elif p.x >= stop - 0.001:
			if r.held == 0.0:
				r.near = _near(r)
				L.cam_rig.jolt(0.18)
				L.player.look.bump(1.0, 1.0)  # squashed against it, the top still going
			r.held += delta
			if L.now > r.t + LAUNCH_WINDOW:
				r.judged = true
				r.hit = true
				_shatter(r, true)
				L.knock_back(LAUNCH_KNOCK)
				L.player.jump(3.5)
				L.cam_rig.jolt(0.2)
				L.sfx.play("launch_hit")
				L.miss("Hit by the fired wall! Dash (SHIFT) on the loud clap", false)
		break  # only the next wall matters


## Smashed: the wall bursts into its voxels where the player meets it, flung back the way it came and up; run into, it
## bursts feebly. A standing wall's pieces bounce on the row it stood on, a hanging one's fall away.
func _shatter(r: Dictionary, hit: bool) -> void:
	r.broken = true
	r.core.visible = false
	for g in r.ghosts:
		g.visible = false
	var sgn := -1.0 if r.top else 1.0
	var at := Vector3(r.near, L.player.global_position.y, 0.0)
	var floor_top := -INF
	var xa := 0.0
	var xb := 0.0
	if not r.top:
		var seg: Dictionary = L.seg_at(L.track.t_at(r.near))
		floor_top = _surface_at(false, r.near + LAUNCH_W * 0.5)
		xa = L.track.x_at(seg.ta) if not seg.is_empty() else r.near - 3.0
		xb = L.track.x_at(seg.tb) if not seg.is_empty() else r.near + 3.0
	var power: float = LAUNCH_BURST * (0.5 if hit else 1.0)
	var push := Vector3(LAUNCH_SPEED + 2.0, sgn * 3.0, 0.0) if not hit else Vector3(1.0, sgn * 1.5, 0.0)
	for node in r.blocks:
		VoxelColumn.break_apart(node, at, 0.0, 0.0, power, push, floor_top, xa, xb)
	if _debris == null:
		_debris = VoxelDebris.new()
		add_child(_debris)
	_debris.add(r.blocks)
	if not hit:
		L.cam_rig.jolt(0.16)
		L.sfx.play("shatter")


func fallen() -> bool:
	return false


## The speaker block stands at its place in the row.
func occupied(t: float) -> bool:
	var x: float = L.track.x_at(t)
	return launches.any(func(r): return absf(x - r.x) < BLOCK_W * 0.5 + 0.5)


## Carrying on from t: the walls before it are over.
func skip_to(t: float) -> void:
	for r in launches:
		if r.t < t:
			r.judged = true
			r.broken = true
			for node in r.blocks + r.ghosts + [r.core]:
				node.visible = false


## The intro panel: DASH.
func panel_caption() -> Dictionary:
	return {"DASH": "Dash (SHIFT) on the clap to smash the block / fired wall"} if not launches.is_empty() else {}


## The intro panel's drawing: a fired wall of stacked blocks and the speaker it comes from.
func panel_sprites() -> Array:
	if launches.is_empty():
		return []
	var a: Color = L.mats.accent
	return [{"family": "DASH", "t": launches.map(func(r): return r.t).min(), "palette": {"a": a, "d": a.darkened(0.4), "s": Color.from_hsv(a.h, 1.0, a.v), "k": a.darkened(0.65), "t": L.theme_color},
		"rows": ["............", ".aaa........", ".aaa........", ".ddd........", ".aaa........", ".aaa........", ".ddd...ssss.", ".aaa...skks.", ".aaa...skks.", ".aaa...ssss.", "tttttttttttt", "tttttttttttt"]}]
