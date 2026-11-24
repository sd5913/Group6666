extends "res://scripts/mechanics/mechanic.gd"
## 5-2 滑铲 (level 3's claps): on every off-beat clap of the MIDI (a clap that isn't on a kick) a square block hanging
## from the sky slams down right onto the player, leaving only room to slide under. Press S on the clap to slide. Still
## standing while the window is open, the block stops on the player's head and pushes down with them as they duck; only
## once the window is over does a head in its way hit it.
## The melody makes it a curtain: every lead note (SLIDE_FOLLOW_TRACK) in the slide after the clap drops one more,
## narrower block (SLIDE_FOLLOW_W) on its own note over where the player's head is then, up to SLIDE_MAX_BLOCKS in all,
## so a slow melody drops one block and a fast one three or four in a row. It is still one S on the clap: the slide
## lasts until the player is out from under the last block. Once the player is through, the whole curtain lifts away.
## A beat before its note, each block hangs low and pulses on the hi-hat so it is seen coming; louder claps drop wider
## first blocks. The blocks are columns of voxels, each landing with a thud (block_drop). Hitting one is not a failure:
## its lower end bursts into voxels where the player's head hits it (the rest of the column is pulled back up), a dull
## bump, and the streak starts again.
## The slides are planned after the slams and plunges, on flat ground: clear of their run-ups, pits and bounces, and of
## the run-up to a terrace's spring. From the first SLIDE_COMBO_FROM event on (the song getting stronger) a fall and a
## curtain go together first ("落+压"): after each landing (a plunge's, a slam's bounce) the first clap within a beat
## and a half whose first block comes SLIDE_COMBO_FLAT or more after it drops a curtain, so the player slides as soon
## as they are down (a plunge's landing note keeps its moment: the curtain takes the next clap).

const PlayerScript := preload("res://scripts/player.gd")
const VoxelColumn := preload("res://scripts/view/voxel_column.gd")
const VoxelDebris := preload("res://scripts/view/voxel_debris.gd")

var SLIDE_FROM_PHRASE := 2     # the first phrase with slides (the first teaches the slams on their own)
var SLIDE_LEAD := 0.1          # a block comes down this far ahead of the player (seconds of run): over its head
var SLIDE_T := 0.6             # how long a slide lasts at least (seconds)
var SLIDE_WINDOW := 0.16       # press S this close to the clap (seconds)
var SLIDE_EARLY := 0.4         # S this long before the clap already counts: it waits for the clap (no plain slide)
var SLIDE_GAP := 0.25          # room left over a sliding player (metres; the camera looks down on its top, so less doesn't show)
var SLIDE_W_MIN := 0.6         # first block's width for the softest clap / the loudest (metres)
var SLIDE_W_MAX := 1.0
var SLIDE_FOLLOW_TRACK := "lead"  # the notes after the clap that drop more blocks
var SLIDE_FOLLOW_W := 0.4      # their width (metres)
var SLIDE_MAX_BLOCKS := 4      # blocks in a curtain at most (the clap's included)
var SLIDE_SHAKE := 0.1
var SLIDE_BURST := 4.0         # how fast the voxels of a block the player runs into fly off (m/s)
var SLIDE_EVERY_BARS := 2      # with terraces: every this many bars a clap's flat ground is kept for a slide (0: none)
var SLIDE_COMBO_FROM := ""     # from the first event of this branch, a curtain right after each landing first ("": none)
var SLIDE_COMBO_FLAT := 0.3    # at least this much flat run from the landing to the curtain's first block (seconds)

const SLIDE_REACH := 12.0      # how far the hanging column reaches up into the sky
const SLIDE_D := 0.72          # its depth across the run: the player's, so the gap over a ducked head shows from the camera

var blocks: Array = []          # one per clap: {t, judged, hit, passed, clear_t, parts [{t, t_block, w, track, x, seg, col, ...}]}
var _debris: VoxelDebris        # blocks that were run into, while their voxels fly


## The tutorial's curtain: one block, for a slide at at[0].
func teach(at: Array, _kind := "") -> void:
	_add(at[0], 0.5, [at[0] - 0.45, at[0] + SLIDE_LEAD + 0.3], false)


## Claps that aren't on a kick, on solid ground clear of the other mechanics (the slams are planned first); then each
## curtain's lead notes, as many as there is room for once every clap has its block.
func plan_air() -> void:
	var vels: Array = L.song.velocities("clap")
	var v_lo: float = vels[0] if not vels.is_empty() else 64.0
	var v_hi: float = vels[-1] if not vels.is_empty() else 127.0
	var vel := {}
	for n in L.song.notes("clap"):
		vel[n[0]] = (n[3] - v_lo) / maxf(1.0, v_hi - v_lo)
	# 落+压 first: a curtain right after each landing from combo_from on
	for land in landings_from(combo_from()):
		var c := combo_clap(land)
		if is_nan(c) or blocks.any(func(b): return absf(b.t - c) < 0.01):
			continue
		var busy: Array = [maxf(c - 0.45, land + 0.02), c + SLIDE_LEAD + 0.3]
		if not _terrace_free(c - 0.1, c + SLIDE_T + 0.1, land) or not _clear(busy, []):
			continue
		_add(c, vel.get(c, 0.5), busy, true)
	for n in L.song.notes("clap"):
		var t: float = n[0]
		if blocks.any(func(b): return absf(b.t - t) < 0.01) or not _takes(t):
			continue
		_add(t, vel[t], [t - 0.45, t + SLIDE_LEAD + 0.3], false)
	blocks.sort_custom(func(a, b): return a.t < b.t)
	for b in blocks:
		var parts: Array = b.parts
		for f in L.song.between(SLIDE_FOLLOW_TRACK, b.t + 0.01, b.t + SLIDE_T - 0.2 + 0.001):
			if parts.size() >= SLIDE_MAX_BLOCKS:
				break
			var last: Dictionary = parts[-1]
			var tb: float = f[0] + SLIDE_LEAD
			if L.track.x_at(tb) - L.track.x_at(last.t_block) < (last.w + SLIDE_FOLLOW_W) * 0.5 + 0.1:
				continue  # too close to the last block to be one of its own
			if not _clear([b.busy[1], tb + 0.3], b.busy) or not _terrace_free(b.busy[1], tb + 0.3):
				break
			parts.append({"t": f[0], "t_block": tb, "w": SLIDE_FOLLOW_W, "track": SLIDE_FOLLOW_TRACK})
			b.busy[1] = tb + 0.3  # (the span in L.busy_spans grows with it)


func _add(t: float, k: float, busy: Array, combo: bool) -> void:
	var parts := [{"t": t, "t_block": t + SLIDE_LEAD, "w": lerpf(SLIDE_W_MIN, SLIDE_W_MAX, k), "track": "clap"}]
	blocks.append({"t": t, "parts": parts, "busy": busy, "hit": false, "judged": false, "passed": false, "combo": combo})
	L.busy_spans.append(busy)


## When the 落+压 combos start (the first SLIDE_COMBO_FROM event; INF: never).
func combo_from() -> float:
	var t := INF
	for e in L.data.events:
		if SLIDE_COMBO_FROM != "" and e.branch == SLIDE_COMBO_FROM:
			t = minf(t, e.t)
	return t


## Every landing from t0 on: a plunge's (on its note), a slam's bounce coming down.
func landings_from(t0: float) -> Array:
	var out := []
	var sl = L.mechanic("slam")
	if sl != null:
		out.append_array(sl.slams.map(func(s): return s.land))
	var pl = L.mechanic("plunge")
	if pl != null:
		out.append_array(pl.plunges.map(func(p): return p.t))
	out = out.filter(func(t): return t >= t0 - 0.001)
	out.sort()
	return out


## The clap a curtain after a landing at `land` comes on: the first within a beat and a half (the claps come a half
## or a whole beat apart) whose first block is SLIDE_COMBO_FLAT or more after the landing (NAN: none).
func combo_clap(land: float) -> float:
	for n in L.song.notes("clap"):
		if n[0] + SLIDE_LEAD >= land + SLIDE_COMBO_FLAT - 0.001 and n[0] <= land + 1.5 * L.beat + 0.02 and L.grid_ok(n[0]) 				and flip_free(n[0]):
			return n[0]
	return NAN


## A short slide squeezed into a stretch [a, b] with nothing to press for too long (the towers ask, once they are
## planned): on a clap inside it, right after a landing if need be, on flat ground — a plunge's run-up will do, as the
## slide is short (over once the player is out from under its one block) and over before that edge. Whether it fit.
func squeeze(a: float, b: float) -> bool:
	var pl = L.mechanic("plunge")
	var edges: Array = pl.plunges.map(func(p): return p.edge) if pl != null else []
	for n in L.song.notes("clap"):
		var t: float = n[0]
		if t < a + 0.3 or t > b - 0.3 or not L.grid_ok(t) or not flip_free(t) or blocks.any(func(x): return absf(x.t - t) < 0.01):
			continue
		var span := [t - 0.45, t + SLIDE_LEAD + 0.3]
		var in_way := func(s: Array) -> bool:
			if span[0] >= s[1] or span[1] <= s[0]:
				return false
			if s[1] <= t - 0.1 and L.air_spans.has(s):
				return false  # (a landing just before: down and sliding at once)
			return not (edges.any(func(e): return absf(s[1] - e) < 0.001) and t + 0.45 <= s[1] - 0.2)  # (a plunge's run-up)
		if (L.air_spans + L.busy_spans).any(in_way) or L.pits.any(func(p): return p[0] < span[1] and p[1] > maxf(span[0], t - 0.1)):
			continue  # (a pit just landed beyond is behind the player)
		if L.terrace.any(func(st): return st.kind == "spring" and t - 0.45 < st.t + 0.2 and t + 0.45 > st.t - L.beat - 0.45):
			continue
		_add(t, 0.5, span, false)
		blocks[-1].short = true
		blocks.sort_custom(func(x, y): return x.t < y.t)
		return true
	return false


## Whether a clap at t would get a slide with what is planned so far: not on a kick (that is the slam's beat), in its
## phrases (the last bar before the first one already previews it), on solid ground clear of the rest — and of the
## terraces' steps (a spring's run-up and jump, a step's edge).
func _takes(t: float) -> bool:
	var first: float = L.phrases[SLIDE_FROM_PHRASE - 1] - L.data.bar_sec if L.phrases.size() >= SLIDE_FROM_PHRASE else 0.0
	if t < maxf(first, 0.6) - 0.001 or t + SLIDE_LEAD > L.data.dur - 0.5 or not L.grid_ok(t) or not flip_free(t):
		return false
	if not _terrace_free(t - 0.45, t + SLIDE_T + 0.1):  # (flat until the shortest slide is over)
		return false
	return L.song.off_by("kick", t) >= 0.05 and _clear([t - 0.45, t + SLIDE_LEAD + 0.3], [])


## Whether a curtain on a clap at t keeps out of the flips' row hanging above (level.under_top_row): its blocks hang
## over the run from two beats before the clap until the slide and its blocks are over.
func flip_free(t: float) -> bool:
	return not L.under_top_row(t - 2.0 * L.beat, t + SLIDE_LEAD + SLIDE_T + L.beat)


## Whether [a, b] keeps clear of the terraces' steps after `after` (a spring's run-up and jump, a step's edge).
func _terrace_free(a: float, b: float, after := -INF) -> bool:
	return not L.terrace.any(func(st): return st.t > after + 0.01 and a < st.t + 0.2 and b > st.t - L.beat - 0.45)


## Make way for a mechanic planned later that matters more: the slides overlapping [a, b] are dropped
## (as if it had been planned first).
func give_way(a: float, b: float) -> void:
	for blk in blocks.filter(func(blk): return a < blk.busy[1] and b > blk.busy[0]):
		blocks.erase(blk)
		L.busy_spans = L.busy_spans.filter(func(s): return not is_same(s, blk.busy))


## Whether span s is one of the slides' own.
func owns(s: Array) -> bool:
	return blocks.any(func(blk): return is_same(blk.busy, s))


## Whether [a, b] is clear of everything planned so far (but `own`).
func _clear(span: Array, own: Array) -> bool:
	if (L.air_spans + L.busy_spans).any(func(s): return not is_same(s, own) and span[0] < s[1] and span[1] > s[0]):
		return false
	return not L.pits.any(func(p): return p[0] < span[1] and p[1] > span[0])


func plan_contacts() -> void:
	for b in blocks:
		for c in [b.t - 0.4, b.t - 0.2, b.t]:  # flat ground for the run-up and the slide
			L.contacts.append(c)
		for p in b.parts:
			L.contacts.append(p.t_block)
		L.key_contacts.append(b.t)


func anchors() -> Array:
	var out := []
	for b in blocks:
		for p in b.parts:
			out.append([p.t, p.track])
	return out


func cues() -> Array:
	return blocks.map(func(b): return {"t": b.t, "action": "down"})


## SLIDE! on the clap (S as for a slam, so its own word).
func prompts() -> Array:
	return blocks.map(func(b): return {"t": b.t, "action": "down", "verb": "SLIDE"})


func tips() -> Array:
	return ["[S]\u00a0slide"] if not blocks.is_empty() else []


# ---------------------------------------------------------------- look

## Square columns of voxels hanging from the sky, glowing hardest at their lower ends (their origins). The slide has
## to last until the player's back is out from under the last one.
func build() -> void:
	for b in blocks:
		for p in b.parts:
			p.x = L.track.x_at(p.t_block)
			p.seg = L.seg_at(p.t_block)
			p.col = VoxelColumn.make(self, p.w, SLIDE_D, SLIDE_REACH, 1, L.GRAVITY)
			p.col.position = Vector3(p.x, 0.0, 0.0)
			p.hit = false
			p.passed = false
		var last: Dictionary = b.parts[-1]
		b.clear_t = L.track.t_at(last.x + last.w * 0.5 + PlayerScript.RADIUS)


## Waiting high up, pulsing on the hi-hat and lowering a little in the beat before its note; on its note a block slams
## down to just over a sliding player's head (overshooting a touch); once the player is through the last one, the
## curtain lifts away.
func update_motion(_delta: float) -> void:
	var now: float = L.now
	var x0: float = L.view_x0()
	var x1: float = L.view_x1()
	for b in blocks:
		var lift_t: float = b.parts[-1].t_block + 0.3
		for p in b.parts:
			if p.x < x0 or p.x > x1 or p.hit:
				continue
			var floor_y: float = p.seg.top if not p.seg.is_empty() else L.ground_h(p.t_block)
			var low: float = floor_y + L.player.CROUCH_H + SLIDE_GAP
			var high: float = floor_y + 3.4
			var bottom := high
			var glow := 0.2
			var lead: float = p.t - now
			if lead > 0.0:
				var soon := 1.0 - clampf(lead / L.beat, 0.0, 1.0)
				bottom = high - 0.6 * soon * soon
				glow = 0.15 + 0.35 * soon + 0.15 * _hat_pulse(now)
			else:
				var age := -lead
				bottom = lerpf(high - 0.6, low, clampf(age / 0.06, 0.0, 1.0)) - 0.08 * sin(clampf(age / 0.2, 0.0, 1.0) * PI)
				if now > lift_t:  # through: lift away
					bottom = lerpf(low, high + 1.0, clampf((now - lift_t) / 0.4, 0.0, 1.0))
				glow = 0.5 - 0.3 * clampf(age / 0.6, 0.0, 1.0)
				if not p.get("dropped", false):
					p.dropped = true
					var first := is_same(p, b.parts[0])
					L.cam_rig.jolt(SLIDE_SHAKE * (1.0 if first else 0.5))
					L.sfx.play("block_drop", 1.0 if first else 0.6)
				if _waits_on_head(b, p):  # comes to rest just over the head as drawn (a gap shows it missed), and goes down with it
					bottom = maxf(bottom, L.player.look.top_y() + SLIDE_GAP)
			p.bottom = bottom
			p.col.position = Vector3(p.x, bottom, 0.0)
			VoxelColumn.shade(p.col, L.mats.accent, glow, L.BLOCK_SHINE)


func _hat_pulse(now: float) -> float:
	var hat: Array = L.song.nearest("hat", now)
	if not hat.is_empty() and now >= hat[0] and now - hat[0] < 0.3:
		return exp(-(now - hat[0]) * 8.0)
	return 0.0


# ---------------------------------------------------------------- play

func autoplay() -> void:
	for b in blocks:
		if not b.judged and L.now >= b.t - 0.004 and L.now <= b.t + SLIDE_WINDOW and L.down_press <= L.NONE:
			L.down_press = L.now


## S near a clap, on the ground: slide, until the player is out from under the curtain's last block. A press up to
## SLIDE_EARLY before it waits for the clap (and is scored by how early it was) instead of becoming a plain slide that
## ends too soon.
func down_claim(press: float) -> int:
	for b in blocks:
		if not b.judged and press >= b.t - SLIDE_EARLY and press <= b.t + SLIDE_WINDOW:
			if L.now < b.t - 0.05 or not L.can_jump():
				return WAIT if L.now <= b.t + SLIDE_WINDOW else PASS
			b.judged = true
			L.player.crouch(maxf(0.2 if b.get("short", false) else SLIDE_T, b.clear_t + 0.05 - L.now))
			L.judge(press - b.t)
			return TAKEN
	return PASS


## Whether block p of curtain b, come down, waits on the head of the player under it: while the clap's window is open,
## or while the player is ducking (or sliding) under it.
func _waits_on_head(b: Dictionary, p: Dictionary) -> bool:
	if absf(L.player.global_position.x - p.x) >= p.w * 0.5 + PlayerScript.RADIUS:
		return false
	return L.now <= b.t + SLIDE_WINDOW or L.player.crouching()


## Under a block, once it no longer waits on the head, the player's head has to stay below its bottom.
func after_step(_delta: float) -> void:
	var pos: Vector3 = L.player.global_position
	for b in blocks:
		if b.passed or L.now < b.t:
			continue
		for p in b.parts:
			if p.hit or p.passed or L.now < p.t:
				continue
			if absf(pos.x - p.x) < p.w * 0.5 + PlayerScript.RADIUS:
				if not _waits_on_head(b, p) and L.player.head_y() > p.get("bottom", INF) + 0.05:
					_shatter(b, p)
			elif pos.x > p.x:
				p.passed = true
		b.passed = b.parts.all(func(p): return p.hit or p.passed)


## Run into: the block's lower end bursts into voxels where the player's head hits it, knocked on and up; they fall
## onto the pillar under it. The first block of a curtain run into costs the streak (with a bump, not the miss sound).
func _shatter(b: Dictionary, p: Dictionary) -> void:
	p.hit = true
	var at := Vector3(p.x - p.w * 0.5, L.player.head_y(), 0.0)
	var run: float = L.base_speed * L.track.mult_at(L.now)
	var floor_top: float = p.seg.top if not p.seg.is_empty() else L.ground_h(p.t_block)
	var x0: float = L.track.x_at(p.seg.ta) if not p.seg.is_empty() else p.x - 3.0
	var x1: float = L.track.x_at(p.seg.tb) if not p.seg.is_empty() else p.x + 3.0
	VoxelColumn.break_apart(p.col, at, 0.0, 0.0, SLIDE_BURST, Vector3(run * 0.6, 2.0, 0.0), floor_top, x0, x1)
	if _debris == null:
		_debris = VoxelDebris.new()
		add_child(_debris)
	_debris.add([p.col])
	L.cam_rig.jolt(0.22)
	if not b.hit:
		b.hit = true
		L.sfx.play("wall_hold")
		L.player.look.bump(0.9, -0.4)  # (knocked by it: squashed, bits off its front)
		L.miss("Hit a block! Slide (S) on the clap", false)


## Carrying on from t: the slides before it are over.
func skip_to(t: float) -> void:
	for b in blocks:
		if b.t < t:
			b.judged = true
			b.passed = true


## The intro panel: SLIDE.
func panel_caption() -> Dictionary:
	return {"SLIDE": "Slide (S) under the dropping blocks"} if not blocks.is_empty() else {}


## The intro panel's drawing: blocks hanging down over the run.
func panel_sprites() -> Array:
	if blocks.is_empty():
		return []
	return [{"family": "SLIDE", "t": blocks.map(func(b): return b.t).min(), "palette": {"a": L.mats.accent, "t": L.theme_color}, "rows": ["aaaaaaaaaaaa", "aaaaaaaaaaaa", "aa.aaa.aaa.a", "aa.aaa..aa.a", "a..aa...a...", "a...a.......", "............", "............", "............", "............", "tttttttttttt", "tttttttttttt"]}]
