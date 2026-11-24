extends RefCounted
## Song time -> distance along the run.
## The player's x is read from this table, so speed changes (5-3 boosts, 5-6 section speeds) never break beat sync:
## a faster stretch only spreads the same beats further apart.

const DT := 1.0 / 240.0
# tunables (config/tuning.csv, as track.X)
var SECTION_STEP := 1.15     # 6a / 6b: one notch faster / slower
var CLIMAX := 1.25           # 6d: the loudest 2 bars
var CLIMAX_HOLD := 0         # 1: the climax speed holds from the 6d event on until the 6e finish (0: just its 2 bars)
var BOOST := 1.2             # 3a: groove bars on a boost lane
var END_SPEED := 0.35        # 6e: ease down to this at the finish
var MAX_MULT := 1.8

var t0 := 0.0
var held: Array = []         # the climax stretches as the speed has them (CLIMAX_HOLD: on to the finish) [[t0, t1]]
var base := 6.0
var xs := PackedFloat32Array()
var ms := PackedFloat32Array()


func build(data: Dictionary, base_speed: float, t_start: float, t_end: float) -> void:
	base = base_speed
	t0 = t_start
	var bar: float = data.bar_sec
	var steps := []      # [t, factor] section speed changes
	var climax := []     # [t0, t1]
	var boosts := []     # [t0, t1]
	var end_t := INF
	for e in data.events:
		match e.branch:
			"6a": steps.append([e.t, SECTION_STEP])
			"6b": steps.append([e.t, 1.0 / SECTION_STEP])
			"6d": climax.append([e.t, e.t + 2.0 * bar])
			"3a": boosts.append([e.t, e.t + bar])
			"6e": end_t = minf(end_t, e.t)
	steps.sort_custom(func(a, b): return a[0] < b[0])
	if CLIMAX_HOLD != 0:
		for c in climax:
			c[1] = maxf(c[1], end_t if end_t > c[0] and end_t < INF else t_end)
	held = climax
	var n := int(ceil((t_end - t_start) / DT)) + 2
	xs.resize(n)
	ms.resize(n)
	var x := 0.0
	var cur := 1.0
	for i in n:
		var t := t_start + i * DT
		var level := 1.0
		for s in steps:
			if t >= s[0]:
				level *= s[1]
		var m := clampf(level, 0.75, 1.5)
		for c in climax:
			if t >= c[0] and t < c[1]:
				m *= CLIMAX
		for b in boosts:
			if t >= b[0] and t < b[1]:
				m *= BOOST
		if t >= end_t:
			m = lerpf(m, END_SPEED, clampf((t - end_t) / bar, 0.0, 1.0))
		m = minf(m, MAX_MULT)
		cur = lerpf(cur, m, 1.0 - exp(-DT * 8.0))  # ease into new speeds over ~0.3 s
		ms[i] = cur
		xs[i] = x
		x += base * cur * DT


func x_at(t: float) -> float:
	var f := (t - t0) / DT
	if f <= 0.0:
		return xs[0] + (t - t0) * base * ms[0]
	var i := int(f)
	if i >= xs.size() - 1:
		return xs[xs.size() - 1] + (t - (t0 + (xs.size() - 1) * DT)) * base * ms[ms.size() - 1]
	return lerpf(xs[i], xs[i + 1], f - i)


## The song time at which the run is at x (the other way round from x_at).
func t_at(x: float) -> float:
	var i := xs.bsearch(x) - 1
	if i < 0:
		return t0 + (x - xs[0]) / (base * ms[0])
	if i >= xs.size() - 1:
		return t0 + (xs.size() - 1) * DT + (x - xs[xs.size() - 1]) / (base * ms[ms.size() - 1])
	return t0 + (i + (x - xs[i]) / maxf(1e-6, xs[i + 1] - xs[i])) * DT


func mult_at(t: float) -> float:
	var i := clampi(int((t - t0) / DT), 0, ms.size() - 1)
	return ms[i]
