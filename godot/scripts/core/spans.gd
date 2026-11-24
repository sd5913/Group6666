extends RefCounted
## Time spans [[ta, tb], ...] and piecewise-linear curves [[t, value], ...].


## spans with every hole cut out of them.
static func subtract(spans: Array, holes: Array) -> Array:
	var out := spans.duplicate()
	for h in holes:
		var next := []
		for s in out:
			if h[1] <= s[0] or h[0] >= s[1]:
				next.append(s)
				continue
			if h[0] > s[0]:
				next.append([s[0], h[0]])
			if h[1] < s[1]:
				next.append([h[1], s[1]])
		out = next
	return out


## Strictly inside one of the spans.
static func inside(spans: Array, t: float) -> bool:
	for s in spans:
		if t > s[0] and t < s[1]:
			return true
	return false


static func interp(pts: Array, t: float) -> float:
	if t <= pts[0][0]:
		return pts[0][1]
	for i in range(1, pts.size()):
		if t <= pts[i][0]:
			var a: Array = pts[i - 1]
			var b: Array = pts[i]
			return lerpf(a[1], b[1], (t - a[0]) / maxf(0.0001, b[0] - a[0]))
	return pts[pts.size() - 1][1]
