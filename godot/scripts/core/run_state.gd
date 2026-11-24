extends RefCounted
## What carries over when a level is reloaded to carry on from its last star after losing a life (scripts/level.gd):
## which level, the lives left, the song time to start again from, the stars already taken and the best streak so far;
## and the star times edited in the tune mode (T), until R or another level.
## Static, so it outlives the reload; cleared whenever a level is started afresh (R, choosing a level, the next level).
## intro_due is not cleared: it says whether the level now loading was entered afresh (the game starting, the next
## level, a level chosen) and so shows its intro panel; R and carrying on after a lost life don't set it.

static var level := -1                # the level it belongs to (-1: nothing to carry on)
static var lives := 0
static var resume_t := 0.0            # song time the music starts again from (0: the start, after the count-in)
static var stars_taken: Array = []    # times of the stars already taken
static var best_streak := 0
static var star_t: Array = []         # star times edited in the tune mode (empty: STAR_T / the 4b rule)
static var intro_due := true          # the next level loaded shows its intro panel (scripts/view/intro_panel.gd)
static var tutorial_due := false      # the next level loaded starts with its tutorial (scripts/tutorial.gd): set on the way into
                                      # a level (the game starting, the next level, a level chosen), never by R or a lost life


static func clear() -> void:
	level = -1
	lives = 0
	resume_t = 0.0
	stars_taken = []
	best_streak = 0
	star_t = []
