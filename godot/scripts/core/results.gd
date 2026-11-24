extends RefCounted
## 成绩: each level's result this session, for the end screen. Static so it outlives the levels' reloading; not on disk.
## Separate from RunState, which is cleared on every fresh start: this is forgotten only when START is pressed on the
## start screen. A level won again takes over its own row.
## During a level every judgement is noted with its song time. Losing a life carries on from a checkpoint and plays the
## stretch after it again, so the notes after that checkpoint are dropped; the life itself is counted apart.
## An attempt with autoplay on at any moment (even off again; carrying on after a lost life is the same attempt; the
## developer's only: core/dev.gd) isn't counted: its row just says so ({auto: true}), and it never takes the place of a
## row that was really played.

static var rows := {}           # level number -> {perfect, good, miss, stars, total, best_streak, lives_lost} or {auto}
static var _notes: Array = []   # this attempt at the level: [song time, "perfect" / "good" / "miss"]
static var _lives_lost := 0
static var _auto := false       # autoplay has been on in this attempt


## START on the start screen.
static func reset() -> void:
	rows = {}


## A level entered afresh.
static func begin_attempt() -> void:
	_notes = []
	_lives_lost = 0
	_auto = false


## Autoplay is on.
static func mark_auto() -> void:
	_auto = true


static func note(t: float, kind: String) -> void:
	_notes.append([t, kind])


static func lost_life() -> void:
	_lives_lost += 1


## Carrying on from checkpoint t.
static func rewind_to(t: float) -> void:
	_notes = _notes.filter(func(n): return n[0] < t)


## The level was won.
static func record(level: int, stars: int, total: int, best_streak: int) -> void:
	if _auto:
		if not rows.has(level):
			rows[level] = {"auto": true}
		return
	rows[level] = {"perfect": _count("perfect"), "good": _count("good"), "miss": _count("miss"), "stars": stars,
		"total": total, "best_streak": best_streak, "lives_lost": _lives_lost}


## The rows that count (really played).
static func counted() -> Array:
	return rows.values().filter(func(r): return not r.has("auto"))


static func _count(kind: String) -> int:
	return _notes.filter(func(n): return n[1] == kind).size()


## How well it all went: perfect counts 1, good 0.5, of everything judged (a lost life counts as a miss). 0 if nothing was.
static func accuracy() -> float:
	var score := 0.0
	var judged := 0
	for r in counted():
		score += r.perfect + 0.5 * r.good
		judged += r.perfect + r.good + r.miss + r.lives_lost
	return score / judged if judged > 0 else 0.0
