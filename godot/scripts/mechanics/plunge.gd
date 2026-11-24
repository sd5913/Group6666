extends "res://scripts/mechanics/mechanic.gd"
## 下坠 (level 3's terrace steps down that aren't slams, scripts/core/terrace.gd): nothing to press. The run breaks off
## just as far before the step's note as falling the step's height takes, so the player walks off the edge, drops onto
## the lower terrace and lands right on that note: squashed by the landing, a puff of dust, the camera jolting as hard
## as the drop is deep. Both ledges keep still (no pumping on the bass), so the fall takes exactly as long as planned.
## Nothing marks the ledge landed on: there is nothing to press (the accent is only for what the player plays with).

const Draw := preload("res://scripts/view/draw.gd")
const PlayerScript := preload("res://scripts/player.gd")

var PLUNGE_SHAKE := 0.06       # camera jolt on landing, per metre of drop

const RUNUP := 0.45             # flat ground before the edge (seconds)
const STEP := 1.0 / 120.0       # the physics step: the fall is planned the way the player falls, step by step

var plunges: Array = []         # {t, edge, h, pitch, landed}
var _dust_mat: StandardMaterial3D


## Where the run breaks off for a drop of h landing at t: falling step by step from standing, the player has dropped
## g/2 (tau^2 + tau STEP) after tau.
func edge_of(t: float, h: float) -> float:
	return t - (-STEP + sqrt(STEP * STEP + 8.0 * h / L.GRAVITY)) * 0.5


func plan_air() -> void:
	for st in L.terrace.filter(func(st): return st.kind == "plunge"):
		var edge := edge_of(st.t, st.from - st.to)
		plunges.append({"t": st.t, "edge": edge, "h": st.from - st.to, "pitch": st.pitch, "landed": false})
		L.pits.append([edge, st.t - 0.02])
		L.air_spans.append([edge, st.t])
		L.busy_spans.append([edge - RUNUP, edge])


## Flat ground before the edge and where the player lands.
func plan_contacts() -> void:
	for p in plunges:
		L.contacts.append(p.edge - RUNUP)
		L.contacts.append(p.edge - 0.25)
		L.contacts.append(p.t)
		L.key_contacts.append(p.t)


## Both ledges keep still: the fall is timed to their heights.
func carve() -> void:
	for p in plunges:
		for t in [p.edge - 0.01, p.t + 0.01]:
			var seg: Dictionary = L.seg_at(t)
			if not seg.is_empty():
				seg.still = true


## The perfect path: off the edge at rest, falling onto the lower terrace on the note.
func solve() -> void:
	for p in plunges:
		L.arcs.append({"ta": p.edge, "tb": p.t, "ya": L.plat_h(p.edge - 0.01) + L.HALF, "vy": 0.0, "g": 1.0})


func anchors() -> Array:
	return plunges.map(func(p): return [p.t, "lead"])


## Landed: dust and a jolt as deep as the drop (the jelly squashes by itself, as hard as it lands).
func after_step(_delta: float) -> void:
	for p in plunges:
		if p.landed or L.now < p.edge or not L.player.grounded:
			continue
		p.landed = true
		p.landed_t = L.now
		L.sfx.play("plunge_land")
		if _dust_mat == null:
			_dust_mat = Draw.mat(L.theme_color.lightened(0.55))
			_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var pos: Vector3 = L.player.global_position
		Draw.burst(self, Vector3(pos.x, pos.y - L.HALF + 0.05, 0.3), _dust_mat, 8, 2.5, 0.12)
		L.cam_rig.jolt(minf(0.3, PLUNGE_SHAKE * p.h))


## Carrying on from t: the plunges before it are over.
func skip_to(t: float) -> void:
	for p in plunges:
		if p.t < t:
			p.landed = true
