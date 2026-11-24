extends RefCounted
## Terraces (TERRACE_PER_ST > 0): the ground stands at the height of the melody's strong notes and only changes on
## them, so the run climbs and falls with the tune's big leaps. A strong note is a lead note on a strong beat (beats
## 1 and 3 of a bar, where the kick is, within 20 ms) or the landing note of a leap of 10 semitones or more. Its terrace
## is (pitch - the lead's median) * TERRACE_PER_ST above where the terraces start (never more than TERRACE_RANGE either
## way), a step down never more than TERRACE_DROP_MAX and a step up never more than TERRACE_RISE_MAX.
## The terraces may cover the whole level, or only some of its song sections (TERRACE_SECTIONS): then they start at the
## piano keys' height there and a last step takes the run back to it before the section ends (no cliff left).
## The melody leaps far more often than a run can climb, so there is at most one step a bar (the rest of the bar is
## left to the other mechanics, the big pillars) — from the first TERRACE_DENSE event on (the song getting stronger),
## one each strong beat, with only TERRACE_DENSE_REST of a terrace before the next run-up: the bar's (half-bar's)
## biggest change, a slam before anything else, at least TERRACE_MIN_STEP, where the mechanic that carries the player
## over it has room after the last step (and TERRACE_REST of the new terrace before its own run-up). In the climax (the
## 6d events) the terraces stand TERRACE_CLIMAX_MULT times as far apart, and a slam's bounce lands on the highest
## terrace it can reach there (up to TERRACE_RISE_MAX over its run-up):
##   down, at least TERRACE_SLAM_MIN, after the slams start              slam: the pad dug at least SLAM_DROP_MIN under
##                                                                       the run-up (a real pit), hit on the step's
##                                                                       (low) note; the bounce lands two beats later on
##                                                                       the terrace there (a step up under it goes with
##                                                                       it), never lower than the run-up
##   down, where a slam doesn't fit (and, over a whole level, the first   plunge: walk off the edge, land on the note
##   in phrase 1)
##   up                                                                  spring: a beat before, landing on the note
## Each step is {t, from, to, pitch, kind}; kind "bounce" is a step up a slam's bounce carries the player over.
## With GRID_LOCK every step stands on a beat of the grid: a strong note off it moves to the nearest lead note on one
## within a beat (none there: no step), and a slam is on a kick (S pressed on it) — a leap down off the beat may also
## be slammed on the nearest kick on a beat within a beat of it (its low note still the one slammed onto).
## The melody's contour (CONTOUR_FROM_EVENT / CONTOUR_SECTIONS): from there on the ground between the steps no longer
## stands still but follows the lead's highest note sounding in each beat, (pitch - median) * CONTOUR_PER_ST, moving at most
## CONTOUR_STEP_MAX a beat (a rise as a ramp, a fall as a drop), held flat over every step's run-up and flight, for
## CONTOUR_HOLD after each landing and over the rests (REST_SPANS). The steps go on
## on top of it, landing on the contour's height of their beat: a slam (onto a low note, its pit as deep as ever) bounces
## up onto it — never lower than its run-up (the V's right side at least as high as its left), the contour walking back
## down to the tune from there — a plunge falls onto it, a spring lifts the run onto it (up to TERRACE_RISE_MAX). A
## slam's run-up that would stand over a dip in the tune (a beat of it lower than the run) goes down to that dip first.

const BEAT_TOL := 0.02          # a note this close to a strong beat (or kick) is on it (seconds)
const LEAP := 10                # a leap at least this many semitones makes its landing note strong
const CONTOUR_HOLD := 0.1       # the contour keeps still this long after a landing (seconds)


## The steps of level L's terraces, in time order: over `span` ([t0, t1]; [] the whole level), from the height
## base_h(t) gives (the piano keys' there; 0 over a whole level), keeping clear of the `reserved` stretches ([[a, b]]:
## the drums' there). The melody's contour they walk on, if the level has one, is left in L.contour.
static func plan(L, span: Array, base_h: Callable, reserved := []) -> Array:
	var whole := span.is_empty()
	var t0: float = L.TERRACE_FROM if whole else maxf(L.TERRACE_FROM, span[0])
	var t1: float = L.data.dur - 1.5 if whole else minf(span[1], L.data.dur - 1.5)
	var notes: Array = L.song.notes("lead")
	var mine: Array = notes if whole else notes.filter(func(n): return n[0] >= span[0] - 0.001 and n[0] < span[1])
	L.contour = {}
	if mine.is_empty():
		return []
	var mids: Array = mine.map(func(n): return n[2])
	mids.sort()
	var dense_from := INF
	for e in L.data.events:
		if L.TERRACE_DENSE != "" and e.branch == L.TERRACE_DENSE:
			dense_from = minf(dense_from, e.t)
	var ctx := {"L": L, "med": mids[mids.size() / 2], "h0": base_h.call(t0), "slam": L.mechanic("slam"),
		"plunge": L.mechanic("plunge"), "springs": L.mechanic("springs"), "reserved": reserved, "dense_from": dense_from,
		"last_slam": -INF, "fixed_slams": L.climax_slams}
	L.contour = contour(L, t0, t1, ctx.med, ctx.h0)
	var cont: Dictionary = L.contour
	var cands := []
	for i in notes.size():
		var n: Array = notes[i]
		var into: float = fposmod(n[0] - L.data.first_bar_at + BEAT_TOL, 2.0 * L.beat) - BEAT_TOL
		var leap: bool = i > 0 and absf(n[2] - notes[i - 1][2]) >= LEAP
		if absf(into) > BEAT_TOL and not leap:
			continue
		if L.grid_ok(n[0]):
			cands.append(n)
		elif leap:  # (off the beat: the nearest lead note on one, within a beat)
			var on := _on_grid_near(L, notes, n[0])
			if not on.is_empty() and not cands.has(on):
				cands.append(on)
		if leap and L.GRID_LOCK != 0 and L.song.off_by("kick", n[0]) > L.GRID_TOL:
			var k := _kick_near(L, n[0])
			if not is_nan(k):
				cands.append([k, 0.0, n[2], 0, "slam"])  # (only a slam: on the kick, onto this low note)
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var steps := []
	var h: float = ctx.h0
	var plunge_first: bool = whole and L.phrases.size() > 1  # phrase 1's first step down is a plunge (falling is fine)
	var free_from := t0                     # the new terrace is free for the next run-up from here
	var skip_to := -INF                     # (a slam's bounce: the notes under it are its)
	var land := [t0, h]                     # the last landing [t, h]: the contour walks on from there
	var bar: float = L.data.bar_sec
	var b0: float = L.data.first_bar_at + floor((t0 - L.data.first_bar_at) / bar + 0.001) * bar
	while b0 < t1:
		# at most one step a bar (from dense_from: each strong beat), the rest left to the other mechanics: its biggest
		# change that fits, a slam before anything else
		var win: float = bar if b0 < dense_from - BEAT_TOL else 0.5 * bar
		var in_cont: bool = not cont.is_empty() and b0 >= cont.t0 - BEAT_TOL
		var best := {}
		var best_score := -INF
		var teach_plunge: bool = plunge_first and b0 < L.phrases[1] - 0.001
		for c in cands.filter(func(c): return c[0] >= maxf(b0, t0) - BEAT_TOL and c[0] < minf(b0 + win, t1) - BEAT_TOL):
			var only_slam: bool = c.size() > 4
			var step := _step_contour(ctx, c[0], c[2], land, free_from, not teach_plunge, NAN, only_slam) if in_cont \
				else _step(ctx, c[0], c[2], h, _height(ctx, c[2], c[0]), free_from, not teach_plunge, only_slam)
			if step.is_empty() or step.t < skip_to:
				continue
			var score: float = absf(step.to - step.from) + (10.0 if step.kind == "slam" else 0.0)
			if score > best_score:
				best = step
				best_score = score
		b0 += win
		if best.is_empty():
			continue
		if best.kind == "plunge" and teach_plunge:
			plunge_first = false
		var r := _take(ctx, steps, best, cands)
		h = r[0]
		skip_to = r[1]
		free_from = r[2]
		land = [best.land_t, h]
	if not whole:  # back to the piano keys' height before the section ends: its latest strong note that can take it
		var last: Array = cands.filter(func(c): return c[0] >= span[1] - 2.0 * bar and c[0] < span[1] - BEAT_TOL)
		last.reverse()
		for c in last:
			var target: float = base_h.call(c[0])
			var cur: float = walk(L, cont, land[0], land[1], c[0] - CONTOUR_HOLD)[0] if not cont.is_empty() else h
			if absf(target - cur) < L.TERRACE_MIN_STEP:
				break
			var step := _step_contour(ctx, c[0], c[2], land, free_from, false, target) if not cont.is_empty() \
				else _step(ctx, c[0], c[2], h, target, free_from, true)
			if not step.is_empty() and step.t >= skip_to and absf(step.to - target) < 0.001:
				_take(ctx, steps, step, cands)
				break
	return steps


## The lead note on a beat of the grid nearest t, within a beat ([] if none).
static func _on_grid_near(L, notes: Array, t: float) -> Array:
	var best := []
	for n in notes:
		if absf(n[0] - t) <= L.beat + 0.001 and L.grid_ok(n[0]) and (best.is_empty() or absf(n[0] - t) < absf(best[0] - t)):
			best = n
	return best


## The kick on a beat of the grid nearest t, within a beat (NAN if none).
static func _kick_near(L, t: float) -> float:
	var best := NAN
	for k in L.song.notes("kick"):
		if absf(k[0] - t) <= L.beat + 0.001 and L.grid_ok(k[0]) and (is_nan(best) or absf(k[0] - t) < absf(best - t)):
			best = k[0]
	return best


## Whether a slam may go on t: on a kick, with GRID_LOCK (S is pressed on the kick); anywhere without.
static func _slam_ok(L, t: float) -> bool:
	return L.GRID_LOCK == 0 or L.song.off_by("kick", t) <= L.GRID_TOL


## Add step to steps (and, for a slam, a step up its bounce carries the player over): [height after, bounce end,
## when the next run-up may start]. The step learns where the run lands after it (land_t, land_h).
static func _take(ctx: Dictionary, steps: Array, step: Dictionary, cands: Array) -> Array:
	var L = ctx.L
	var t: float = step.t
	var end: float = t + ctx.slam.SLAM_BOUNCE_BEATS * L.beat if step.kind == "slam" else t
	if step.kind == "slam":
		ctx.last_slam = t
	steps.append(step)
	var h: float = step.to
	var skip_to := -INF
	if step.kind == "slam" and step.has("land_h"):  # in the contour: the bounce lands on it
		if absf(step.land_h - h) > 0.001:
			steps.append({"t": t + ctx.slam.SLAM_PAD_T + 0.02, "from": h, "to": step.land_h, "pitch": step.pitch, "kind": "bounce"})
		h = step.land_h
		skip_to = end + BEAT_TOL
	elif step.kind == "slam":  # a step up under the bounce: it lands on that terrace ("噔↑"); in the climax the highest
		var up := {}         # one in reach (up to TERRACE_RISE_MAX over the run-up), else the last
		var climax := _in_climax(L, t)
		var top: float = step.from + L.TERRACE_RISE_MAX - h if climax else L.TERRACE_RISE_MAX
		for u in cands:
			if u[0] > t + 0.01 and u[0] <= end + BEAT_TOL:
				var r: float = clampf(_height(ctx, u[2], u[0]) - h, -L.TERRACE_DROP_MAX, top)
				if r >= L.TERRACE_MIN_STEP and (not climax or up.is_empty() or h + r > up.to):
					up = {"t": u[0], "from": h, "to": h + r, "pitch": u[2], "kind": "bounce"}
		# the bounce never comes down lower than it took off: the V's right side at least as high as its left
		var floor_h: float = step.from
		if up.is_empty() and floor_h - h >= L.TERRACE_MIN_STEP:
			up = {"t": t + ctx.slam.SLAM_PAD_T + 0.02, "from": h, "to": floor_h, "pitch": step.pitch, "kind": "bounce"}
		elif not up.is_empty() and up.to < floor_h:
			up.to = floor_h
		if not up.is_empty():
			steps.append(up)
			h = up.to
		skip_to = end + BEAT_TOL
	step.land_t = end
	step.land_h = h
	return [h, skip_to, end + (L.TERRACE_DENSE_REST if t >= ctx.dense_from - BEAT_TOL else L.TERRACE_REST)]


## The step a strong note at t would make from height h towards `target`, with the mechanic that carries the player
## over it, if that has room after free_from ({} if not, or if the change is too small). slams_ok false: no slam;
## only_slam: nothing else.
static func _step(ctx: Dictionary, t: float, pitch: float, h: float, target: float, free_from: float, slams_ok: bool, only_slam := false) -> Dictionary:
	var L = ctx.L
	var dh: float = clampf(target - h, -L.TERRACE_DROP_MAX, L.TERRACE_RISE_MAX)
	if absf(dh) < L.TERRACE_MIN_STEP:
		return {}
	var step := {"t": t, "from": h, "to": h + dh, "pitch": pitch, "kind": ""}
	var slam = ctx.slam if slams_ok else null
	if dh < 0.0:
		var a: float = slam.edge_of(t, maxf(-dh, slam.SLAM_DROP_MIN)) - 0.5 if slam != null else INF
		if slam != null and _slam_ok(L, t) and -dh >= L.TERRACE_SLAM_MIN and t >= slam.SLAM_FROM_T and a >= free_from \
				and _slam_spaced(ctx, t) and _clear(ctx, a, t + slam.SLAM_BOUNCE_BEATS * L.beat):
			step.kind = "slam"
		elif only_slam:
			return {}
		elif ctx.plunge != null and ctx.plunge.edge_of(t, -dh) - 0.45 >= free_from \
				and _clear(ctx, ctx.plunge.edge_of(t, -dh) - 0.45, t):
			step.kind = "plunge"
	elif not only_slam and ctx.springs != null and t - L.beat - 0.3 >= free_from and _clear(ctx, t - L.beat - 0.3, t):
		step.kind = "spring"
	return step if step.kind != "" else {}


## The same in the melody's contour (L.contour): the run walks on from the last landing `land` ([t, h]) and is held
## flat over the step's run-up (from `a` on). A note at least TERRACE_MIN_STEP under where the run is on it takes it
## down — at least TERRACE_SLAM_MIN, a slam onto the note (its pit dug SLAM_DROP_MIN under the run-up as usual, however
## little the run-up stands over the note), whose bounce lands on the contour two beats later, never lower than the
## run-up nor more than TERRACE_RISE_MAX over it, or else a plunge onto the contour's height of its beat — and one as
## far over it up, a spring onto that height (at most TERRACE_RISE_MAX up). A slam's run-up over a beat of the tune
## lower than the run is run at that beat's height, the run dropping to it (drop_t) early enough to land before the
## run-up. target (not NAN): to that height instead, no slam (back onto the keys).
static func _step_contour(ctx: Dictionary, t: float, pitch: float, land: Array, free_from: float, slams_ok: bool, target := NAN, only_slam := false) -> Dictionary:
	var L = ctx.L
	var cont: Dictionary = L.contour
	var note: float = note_h(L, cont, pitch) if is_nan(target) else target
	var tune: float = melody_h(L, cont, t) if is_nan(target) else target
	var cur: float = walk(L, cont, land[0], land[1], t - CONTOUR_HOLD)[0]
	var slam = ctx.slam if slams_ok and is_nan(target) else null
	if note <= cur - L.TERRACE_MIN_STEP:
		if slam != null and _slam_ok(L, t) and cur - note >= L.TERRACE_SLAM_MIN and t >= slam.SLAM_FROM_T and _slam_spaced(ctx, t):
			var r := _run_up(ctx, land, cur, func(from): return slam.edge_of(t, maxf(from - note, slam.SLAM_DROP_MIN)) - 0.5)
			var a: float = r[0]
			var from: float = r[1]
			var dip := _dip(L, cont, a, a + 0.5)  # (the beats starting on the run-up, up to the edge)
			var drop_t := NAN
			var fall := 0.0
			if dip < from - 0.001:
				fall = sqrt(2.0 * (from - dip) / L.GRAVITY)
				drop_t = maxf(land[0] + CONTOUR_HOLD, a - fall - 0.05)
				if L.GRID_LOCK != 0:  # (landing on a beat: the last one before the run-up the fall can reach; none: no dip)
					var g: float = L.data.first_bar_at + floorf((a - L.data.first_bar_at) / L.beat + 0.001) * L.beat
					drop_t = g - fall if g - fall >= land[0] + CONTOUR_HOLD else NAN
				if not is_nan(drop_t):
					from = dip
				a = slam.edge_of(t, maxf(from - note, slam.SLAM_DROP_MIN)) - 0.5
			var to: float = clampf(note, from - L.TERRACE_DROP_MAX, from - 0.01)
			var end: float = t + slam.SLAM_BOUNCE_BEATS * L.beat
			if a >= free_from and _clear(ctx, a if is_nan(drop_t) else minf(a, drop_t), end):
				var step := {"t": t, "from": from, "to": to, "pitch": pitch, "kind": "slam", "a": a,
					"land_h": clampf(melody_h(L, cont, end), from, from + L.TERRACE_RISE_MAX)}
				if not is_nan(drop_t):
					step.drop_t = drop_t
					step.drop_land = drop_t + fall
				return step
		if ctx.plunge != null and not only_slam:
			var r := _run_up(ctx, land, cur, func(from): return ctx.plunge.edge_of(t, maxf(from - tune, 0.0)) - 0.45)
			var to: float = maxf(tune, r[1] - L.TERRACE_DROP_MAX)
			if r[1] - to >= L.TERRACE_MIN_STEP and r[0] >= free_from and _clear(ctx, r[0], t):
				return {"t": t, "from": r[1], "to": to, "pitch": pitch, "kind": "plunge", "a": r[0]}
	elif note >= cur + L.TERRACE_MIN_STEP and ctx.springs != null and not only_slam:
		var a: float = t - L.beat - 0.3
		var from: float = walk(L, cont, land[0], land[1], a)[0]
		var to: float = minf(tune, from + L.TERRACE_RISE_MAX)
		if to - from >= L.TERRACE_MIN_STEP and a >= free_from and _clear(ctx, a, t):
			return {"t": t, "from": from, "to": to, "pitch": pitch, "kind": "spring", "a": a}
	return {}


## Where a step's run-up starts (a_of: from the height it is run on) and that height, walking on from `land` — the
## run-up's length depends on the drop, so twice over: [a, from].
static func _run_up(ctx: Dictionary, land: Array, cur: float, a_of: Callable) -> Array:
	var L = ctx.L
	var from := cur
	var a: float = a_of.call(from)
	for i in 2:
		from = walk(L, L.contour, land[0], land[1], a)[0]
		a = a_of.call(from)
	return [a, from]


## Whether [a, b] keeps clear of the reserved stretches (with a little room either side: a stretch's own [a, b, room],
## else 0.25 s).
## A slam at t at least TERRACE_SLAM_GAP after the last one; from a slam fixed before the terraces (one a held climax's
## hop string ends in: L.climax_slams) a whole bounce, the edge and TERRACE_SLAM_GAP of ground more.
static func _slam_spaced(ctx: Dictionary, t: float) -> bool:
	var L = ctx.L
	var apart: float = ctx.slam.SLAM_BOUNCE_BEATS * L.beat + ctx.slam.SLAM_EDGE_T + L.TERRACE_SLAM_GAP
	return t - ctx.last_slam >= L.TERRACE_SLAM_GAP and ctx.fixed_slams.all(func(s): return absf(t - s) >= apart)


static func _clear(ctx: Dictionary, a: float, b: float) -> bool:
	return not ctx.reserved.any(func(r): var m: float = r[2] if r.size() > 2 else 0.25; return a < r[1] + m and b > r[0] - m)


## The terrace of a strong note of `pitch` at t (in the climax TERRACE_CLIMAX_MULT times as far from the median).
static func _height(ctx: Dictionary, pitch: float, t: float) -> float:
	var L = ctx.L
	var k: float = L.TERRACE_CLIMAX_MULT if _in_climax(L, t) else 1.0
	return ctx.h0 + clampf((pitch - ctx.med) * L.TERRACE_PER_ST * k, -L.TERRACE_RANGE * k, L.TERRACE_RANGE * k)


static func _in_climax(L, t: float) -> bool:
	var spans: Array = L.climax if L.climax_held.is_empty() else L.climax_held  # (held on to the finish: all of it)
	return spans.any(func(c): return t >= c[0] - BEAT_TOL and t < c[1])


# ---------------------------------------------------------------- the melody's contour

## The melody's contour over the terraces' [t0, t1] ({} if the level has none): from the first CONTOUR_FROM_EVENT
## event, in the CONTOUR_SECTIONS sections. Each beat's height is the lead's highest note sounding or starting in it
## (none: the beat before's) as (pitch - med) * CONTOUR_PER_ST over h0, between KEY_MIN and KEY_MAX.
## {t0, t1, i0 (the first beat's index from the first bar), hs (a height a beat), pitches, med, h0, rests}.
static func contour(L, t0: float, t1: float, med: float, h0: float) -> Dictionary:
	if L.CONTOUR_FROM_EVENT == "" and L.CONTOUR_SECTIONS.strip_edges() == "":
		return {}
	var c0 := t0
	var c1 := t1
	if L.CONTOUR_FROM_EVENT != "":
		var from := INF
		for e in L.data.events:
			if e.branch == L.CONTOUR_FROM_EVENT:
				from = minf(from, e.t)
		c0 = maxf(c0, from)
	if L.CONTOUR_SECTIONS.strip_edges() != "":
		var sp: Array = L._sections_span(L.CONTOUR_SECTIONS)
		if sp.is_empty():
			return {}
		c0 = maxf(c0, sp[0])
		c1 = minf(c1, sp[1])
	if c0 >= c1:
		return {}
	var i0 := ceili((c0 - L.data.first_bar_at) / L.beat - 0.001)
	var notes: Array = L.song.notes("lead")
	var hs := []
	var pitches := []
	var p := NAN
	var i := i0
	while L.data.first_bar_at + i * L.beat < c1 - 0.001:
		var b: float = L.data.first_bar_at + i * L.beat
		var top := NAN
		for n in notes:
			if n[0] < b + L.beat - BEAT_TOL and n[0] + n[1] > b + BEAT_TOL and (is_nan(top) or n[2] > top):
				top = n[2]
		if not is_nan(top):
			p = top  # (no note: the beat before's)
		pitches.append(p)
		hs.append(h0 if is_nan(p) else clampf(h0 + (p - med) * L.CONTOUR_PER_ST, L.KEY_MIN, L.KEY_MAX))
		i += 1
	return {"t0": c0, "t1": c1, "i0": i0, "hs": hs, "pitches": pitches, "med": med, "h0": h0, "rests": L._rests()}


## The contour walked on from a landing at ta (height ha) up to t: on each beat in its range — not within CONTOUR_HOLD
## of the landing, not in a rest — it moves towards that beat's height by at most CONTOUR_STEP_MAX (with GRID_LOCK a
## drop a fall's time before the beat, so the run lands on it). [height at t, the key points of its changes].
static func walk(L, cont: Dictionary, ta: float, ha: float, t: float) -> Array:
	var h := ha
	var pts := []
	if cont.is_empty():
		return [h, pts]
	var i := maxi(cont.i0, ceili((ta + CONTOUR_HOLD - L.data.first_bar_at) / L.beat - 0.001))
	while i - cont.i0 < cont.hs.size():
		var b: float = L.data.first_bar_at + i * L.beat
		if b > t:
			break
		i += 1
		if cont.rests.any(func(r): return b > r[0] - 0.1 and b < r[1] + 0.1):
			continue
		var nh: float = h + clampf(cont.hs[i - 1 - cont.i0] - h, -L.CONTOUR_STEP_MAX, L.CONTOUR_STEP_MAX)
		if absf(nh - h) > 0.001:
			var at := b
			if nh < h and L.GRID_LOCK != 0:
				at = maxf(b - sqrt(2.0 * (h - nh) / L.GRAVITY), ta + 0.02)
				if not pts.is_empty():
					at = maxf(at, pts[-1][0] + 0.004)
			pts.append([at - 0.002, h])
			pts.append([at, nh])
			h = nh
	return [h, pts]


## The lowest height of the contour's beats starting in (a, b] (INF: none starts there).
static func _dip(L, cont: Dictionary, a: float, b: float) -> float:
	var lo := INF
	var i := ceili((a - L.data.first_bar_at) / L.beat + 0.001)
	while L.data.first_bar_at + i * L.beat <= b:
		var j: int = i - cont.i0
		if j >= 0 and j < cont.hs.size():
			lo = minf(lo, cont.hs[j])
		i += 1
	return lo


## The contour's height for the beat t is in (outside it: the nearest beat's).
static func melody_h(L, cont: Dictionary, t: float) -> float:
	var j := clampi(floori((t - L.data.first_bar_at) / L.beat + 0.001) - cont.i0, 0, cont.hs.size() - 1)
	return cont.hs[j]


## A note's own height on the contour's scale.
static func note_h(L, cont: Dictionary, pitch: float) -> float:
	return clampf(cont.h0 + (pitch - cont.med) * L.CONTOUR_PER_ST, L.KEY_MIN, L.KEY_MAX)


# ---------------------------------------------------------------- key points

## The key heights a whole level's steps make: flat between them, changing right on each step's note — in the
## melody's contour (L.contour) walking with it between a landing and the next run-up.
static func key_points(L, steps: Array) -> Array:
	var pts := [[L.t_start - 2.0, 0.0]]
	var land := [-INF, 0.0]
	for s in steps:
		_walk_into(L, land, s, pts)
		if s.has("land_t"):
			land = [s.land_t, s.land_h]
	var w := walk(L, L.contour, land[0], land[1], INF)
	pts.append_array(w[1])
	pts.append([L.t_end + 10.0, w[0] if not L.contour.is_empty() else (steps[-1].to if not steps.is_empty() else 0.0)])
	return pts


## A step's key points: in the contour, first its walk from the last landing up to the step's run-up (or to where it
## drops to the run-up's dip in the tune).
static func _walk_into(L, land: Array, s: Dictionary, pts: Array) -> void:
	if s.has("a"):
		var until: float = s.get("drop_t", s.a)
		var w := walk(L, L.contour, land[0], land[1], until)
		pts.append_array(w[1])
		if absf(w[0] - s.from) > 0.001:
			var t1: float = maxf(until - 0.002, pts[-1][0] + 0.0005)
			pts.append([t1, w[0]])
			pts.append([maxf(until, t1 + 0.0005), s.from])
	pts.append([s.t - 0.002, s.from])
	pts.append([s.t, s.to])


## The piano keys' heights `base` with the terraces over `span` in place of them: from the section's start, the steps,
## and after the last one back on the keys (it went back to their height).
static func splice(L, base: Array, steps: Array, span: Array, base_h: Callable) -> Array:
	var resume: float = steps[-1].t if not steps.is_empty() else span[0]
	var pts: Array = base.filter(func(p): return p[0] < span[0] - 0.003)
	pts.append([span[0] - 0.002, base_h.call(span[0])])
	var land := [-INF, base_h.call(span[0])]
	for s in steps:
		_walk_into(L, land, s, pts)
		if s.has("land_t"):
			land = [s.land_t, s.land_h]
	if steps.is_empty() or absf(steps[-1].to - base_h.call(resume)) > 0.001:
		resume = span[1]  # (no step back: the keys take over at the section's end)
		var w := walk(L, L.contour, land[0], land[1], resume - CONTOUR_HOLD)
		pts.append_array(w[1])
		pts.append([resume - 0.002, w[0] if not L.contour.is_empty() else (steps[-1].to if not steps.is_empty() else base_h.call(span[0]))])
		pts.append([resume, base_h.call(resume)])
	pts.append_array(base.filter(func(p): return p[0] > resume + 0.001))
	return pts
