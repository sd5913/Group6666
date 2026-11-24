extends Node
## Sound effects, generated here so the project needs no sound files for them: a small, quiet chiptune set (well under
## the music: the user wants them light), each sound a few voices — a square wave (a 25 % duty, softer than a half one),
## a triangle or noise (8-bit style: a random level held for a while, faster for a brighter hiss; a smashed or crumbling
## thing's noise through a low-pass) — sliding in pitch and fading fast, a few milliseconds in, no long tail.
##   judge_perfect, judge_good, judge_miss   every judgement (level.judge / level.miss), whatever was pressed: two
##                                           notes up like a coin, one note, a low puff; the notes on the level's key
##   star                                    a star taken: three notes up the key's chord
##   shatter      a thing the player smashes (walls, pillars, blocks, launched walls, jaws, a ribbon's end block run
##                into), louder the harder it bursts
##   crumble      a thing falling apart by itself (a ribbon's end block, treads, slam pads, hanging columns)
##   block_drop   a block dropping from the sky over a slide (slam_hit's thump, TRIM_DB quieter)
##   slam_hit, plunge_land, drum_bounce (higher for an off-beat or anticipating drum), spring, flip (sliding up to the
##   top row or down), wall_hold / launch_hit (held up by a wall / hit by a launched wall: in place of judge_miss)
##   flute        SPACE on a hop's flute: its lead note (tone: the MIDI note, equal temperament, A4 = 440 Hz) on a
##                triangle with a breath of noise, 10 ms in, 0.12 s long
##   flute_tick   landing on a flute without SPACE: a soft muted tick (as quiet as a crumble, TRIM_DB under it)
##   3a: a short rising whoosh as the player enters a boost bar.
## They take turns on a few players, so they may overlap; one sound plays at most once in REPEAT_T (a string of things
## crumbling doesn't blur into a roar). Only while the run is on (not in the tune mode).
## However loud their settings, the sounds playing together peak at least SFX_UNDER_DB under the music's loudness right
## then (data/levels/levelN_rms.json, made by tools/music_rms.py: the RMS over half a second around each moment). Half
## of that room is the judgements' and stars', half the other sounds', each half shared by the sounds of its kind still
## sounding (each counted at its peak fading out over its length, as it does), so a judgement always has room however
## much is breaking around it, and a quiet stretch of a song gets quiet sounds. A hop's flute note, playing the tune, has
## a whole room of its own (shared only by the flutes still sounding); whatever plays together never peaks closer than
## UNDER_HARD_DB to the music. Another sound with no room left is
## skipped; a judgement, a star or a flute note never is (a right press, or a star taken, without its sound is worse
## than one a little loud; a string of flutes missing a note has a hole in its tune): it plays as loud as its half
## allows, down to JUDGE_FLOOR_DB.
## A hard limiter on the master bus (LIMIT_DB) keeps the music and the sounds together from clipping.
## record: every sound played is also listed in `played` ([song time, sound, volume dB]) for tools that render them
## offline, and every one skipped (and why) in `skipped`.

const RATE := 22050
const POOL := 8                 # sounds at once at most
const REPEAT_T := 0.06          # the same sound again this soon is skipped
const PEAK := 0.7               # every sound peaks here before its volume (so the dB settings compare them)
const ATTACK := 0.004           # every voice fades in over this long (seconds)
const LIMIT_DB := -1.0          # the master bus's limiter: nothing louder than this gets out
const LIMIT_RELEASE := 0.05     # (seconds)
const JUDGE_FLOOR_DB := -40.0   # a judgement with no room under the music left still plays, this loud
const UNDER_HARD_DB := 6.0      # the sounds playing together never peak closer than this under the music's RMS (dB)
const KIND := {                 # which volume setting each sound goes by
	"judge_perfect": "judge", "judge_good": "judge", "judge_miss": "judge",
	"shatter": "break", "crumble": "crumble",
	"slam_hit": "move", "plunge_land": "move", "drum_bounce": "move", "spring": "move", "flip": "move", "star": "move",
	"block_drop": "move", "flute": "move", "flute_tick": "crumble",
	"wall_hold": "bump", "launch_hit": "bump",
}
const TRIM_DB := {"block_drop": -4.0, "flute": 1.5, "flute_tick": -10.0}  # a sound this much under (over) its kind's setting
const NOTE_NAMES := {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

var BOOST_SOUND_DB := -12.0    # how loud the speed-up whoosh is (-80: off)
var SFX_DB := -18.0            # how loud all the other sounds are (-80: off)
var SFX_JUDGE_DB := 0.0        # judgements, against that
var SFX_BREAK_DB := -2.0       # things smashed
var SFX_CRUMBLE_DB := -10.0    # things falling apart by themselves
var SFX_MOVE_DB := -4.0        # thumps, bounces, springs, flips, stars
var SFX_BUMP_DB := -2.0        # held up by a wall, hit by a fired wall
var SFX_UNDER_DB := 8.0        # a sound peaks at least this far under the music's RMS at that moment (dB)
var SFX_TUTORIAL_DB := -8.0    # in the tutorial, with no music to keep under: this much quieter than usual (dB)
var SFX_ROOT_MIDI := -1        # the judgements' and stars' key note (MIDI note); -1: the level's key

var L
var boost: AudioStreamPlayer
var root := 72                 # the key note the judgements and stars are on (MIDI)
var minor := true
var record := false
var played: Array = []         # (record) [song time, sound key, volume dB]
var skipped: Array = []        # (record) [song time, sound key (and why)]
var sounds := {}               # sound key ("name" or "name:tone") -> AudioStreamWAV
var _next_boost := 0           # the next boost bar whose whoosh hasn't played
var _pool: Array = []
var _turn := 0
var _last := {}                # name -> song time it last played
var _sounding: Array = []      # [song time it starts, ends, its peak (linear), a judgement, a flute] for each sound still playing
var _rms: Array = []           # the music's RMS (dBFS) every _rms_dt seconds
var _rms_dt := 0.03125


func setup() -> void:
	boost = AudioStreamPlayer.new()
	boost.stream = make_whoosh()
	boost.volume_db = BOOST_SOUND_DB
	add_child(boost)
	var key: String = L.data.get("key", "C minor")
	minor = not key.contains("major")
	if SFX_ROOT_MIDI >= 0:
		root = SFX_ROOT_MIDI
	else:  # the key's note, between G4 and F#5
		var pc: int = NOTE_NAMES.get(key.substr(0, 1).to_upper(), 0)
		if key.length() > 1 and key[1] in ["#", "♯"]:
			pc += 1
		elif key.length() > 1 and key[1] in ["b", "♭"]:
			pc -= 1
		root = 67 + posmod(pc - 7, 12)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_limit()
	var rms_path: String = L.level_path.get_basename() + "_rms.json"
	if FileAccess.file_exists(rms_path):
		var r: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(rms_path))
		_rms = r.rms_db
		_rms_dt = r.dt
	for name in KIND:  # (made now, not on the first play)
		_sound(name, 0)
	for t in [["drum_bounce", 1], ["drum_bounce", 2], ["flip", 1]]:
		_sound(t[0], t[1])


## The hard limiter on the master bus (once: the bus outlives the level).
func _limit() -> void:
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			return
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = LIMIT_DB
	lim.release = LIMIT_RELEASE
	AudioServer.add_bus_effect(0, lim)


## Each physics step while playing.
func step() -> void:
	var boosts: Array = L.boosts
	while _next_boost < boosts.size() and L.now >= boosts[_next_boost][0]:
		if L.now - boosts[_next_boost][0] < 0.2 and BOOST_SOUND_DB > -79.0:
			boost.play()
		_next_boost += 1


## Play sound `name` now, `power` as loud (1 as usual; its volume goes with it), `tone` picking a variant (drums: 0 /
## 1 / 2; flip: 0 up, 1 down; flute: the MIDI note).
func play(name: String, power := 1.0, tone := 0) -> void:
	if SFX_DB <= -79.0 or (L.state != "play" and L.state != "tutorial"):
		return
	var now: float = L.now
	var last: float = _last.get(name, -INF)
	if now >= last and now - last < REPEAT_T:
		if record:
			skipped.append([now, _key(name, tone)])
		return
	_last[name] = now
	var db: float = SFX_DB + kind_db(name) + TRIM_DB.get(name, 0.0) + linear_to_db(clampf(power, 0.05, 2.0))
	if L.state == "tutorial":  # (no music yet to keep under)
		db += SFX_TUTORIAL_DB
	elif not _rms.is_empty():  # (all of them together well under the music playing now)
		_sounding = _sounding.filter(func(s): return s[1] > now and s[0] <= now)
		var judge := _first_half(name)
		var flute := name == "flute"
		var music: float = _rms[clampi(roundi(now / _rms_dt), 0, _rms.size() - 1)]
		var room: float = (1.0 if flute else 0.5) * db_to_linear(music - SFX_UNDER_DB)
		var hard: float = db_to_linear(music - UNDER_HARD_DB)
		for s in _sounding:
			var left: float = s[2] * (s[1] - now) / (s[1] - s[0])
			hard -= left
			if s[4] == flute and (flute or s[3] == judge):
				room -= left
		room = minf(room, hard)
		if judge or flute:  # (always heard, however little room)
			db = minf(db, maxf(JUDGE_FLOOR_DB, linear_to_db(maxf(room, 1e-9) / PEAK)))
		elif room < 0.1 * db_to_linear(db) * PEAK:  # (it would hardly be heard)
			if record:
				skipped.append([now, _key(name, tone) + " (no room)"])
			return
		else:
			db = minf(db, linear_to_db(room / PEAK))
	var p: AudioStreamPlayer = _pool[_turn]
	_turn = (_turn + 1) % _pool.size()
	p.stream = _sound(name, tone)
	p.volume_db = db
	p.play()
	_sounding.append([now, now + p.stream.data.size() / 2.0 / RATE, PEAK * db_to_linear(db), _first_half(name), name == "flute"])
	if record:
		played.append([now, _key(name, tone), db])


## Whether sound `name` shares the judgements' half of the room under the music (and is never skipped for want of it).
func _first_half(name: String) -> bool:
	return KIND[name] == "judge" or name == "star"


## Sound `name`'s volume setting (dB, against SFX_DB).
func kind_db(name: String) -> float:
	return {"judge": SFX_JUDGE_DB, "break": SFX_BREAK_DB, "crumble": SFX_CRUMBLE_DB, "move": SFX_MOVE_DB,
		"bump": SFX_BUMP_DB}[KIND[name]]


func _key(name: String, tone: int) -> String:
	return name if tone == 0 else "%s:%d" % [name, tone]


## Make sound `name` (variant `tone`) now, before it is first played.
func prime(name: String, tone := 0) -> void:
	_sound(name, tone)


func _sound(name: String, tone: int) -> AudioStreamWAV:
	var key := _key(name, tone)
	if not sounds.has(key):
		sounds[key] = render(_voices(name, tone))
	return sounds[key]


## Pitch (Hz) of MIDI note m.
static func hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


## One voice: `wave` ("square", "tri" or "noise") from `at` for `dur` seconds, sliding from f0 to f1 (Hz; noise: how
## often its level changes), `vol` loud, fading as (1 - u)^decay; a square's duty; lp: a one-pole low-pass (0 none, 0.5
## takes about half the highs off); attack: how long it fades in (seconds).
static func v(wave: String, at: float, dur: float, f0: float, f1: float, vol: float, decay := 1.0, duty := 0.25,
		lp := 0.0, attack := ATTACK) -> Dictionary:
	return {"wave": wave, "at": at, "dur": dur, "f0": f0, "f1": f1, "vol": vol, "decay": decay, "duty": duty, "lp": lp,
		"attack": attack}


## Each sound's voices.
func _voices(name: String, tone: int) -> Array:
	var third := 3 if minor else 4
	match name:
		"judge_perfect":  # the fifth, then the key note above it
			return [v("square", 0.0, 0.06, hz(root + 7), hz(root + 7), 0.5, 0.5),
				v("square", 0.055, 0.12, hz(root + 12), hz(root + 12), 0.5, 1.8)]
		"judge_good":
			return [v("square", 0.0, 0.08, hz(root + 7), hz(root + 7), 0.5, 1.4)]
		"judge_miss":  # a low puff
			return [v("noise", 0.0, 0.12, 1500.0, 500.0, 0.6, 2.0, 0.25, 0.5), v("square", 0.0, 0.09, 110.0, 65.0, 0.3, 1.8)]
		"star":  # up the key's chord, an octave up
			return [v("square", 0.0, 0.07, hz(root + 12), hz(root + 12), 0.45, 0.8),
				v("square", 0.06, 0.07, hz(root + 12 + third), hz(root + 12 + third), 0.45, 0.8),
				v("square", 0.12, 0.09, hz(root + 19), hz(root + 19), 0.45, 1.8)]
		"shatter":  # a crunchy burst over a low drop
			return [v("noise", 0.0, 0.24, 9000.0, 2500.0, 0.75, 2.6, 0.25, 0.5),
				v("noise", 0.0, 0.1, 2500.0, 700.0, 0.4, 1.5, 0.25, 0.5), v("square", 0.0, 0.13, 160.0, 50.0, 0.35, 1.5)]
		"crumble":  # a light trickle of grit
			return [v("noise", 0.0, 0.14, 11025.0, 6000.0, 0.6, 2.8, 0.25, 0.5),
				v("noise", 0.04, 0.1, 7000.0, 4000.0, 0.35, 2.4, 0.25, 0.5)]
		"slam_hit", "block_drop":  # a deep thump with a low square on it
			return [v("tri", 0.0, 0.16, 150.0, 45.0, 0.9, 1.6), v("square", 0.0, 0.07, hz(root - 24), hz(root - 24), 0.25, 1.5),
				v("noise", 0.0, 0.05, 2000.0, 500.0, 0.3, 2.0, 0.25, 0.5)]
		"plunge_land":
			return [v("tri", 0.0, 0.1, 120.0, 50.0, 0.85, 1.6), v("noise", 0.0, 0.04, 1500.0, 400.0, 0.3, 2.0, 0.25, 0.5)]
		"drum_bounce":  # a little upward blip, higher for the off-beat (1) and anticipating (2) drums
			var m: float = root - 12 + [0, 5, 7][clampi(tone, 0, 2)]
			return [v("square", 0.0, 0.09, hz(m), hz(m + 12), 0.3, 1.2), v("tri", 0.0, 0.09, hz(m - 12), hz(m - 12), 0.5, 1.2)]
		"spring":  # boing
			return [v("square", 0.0, 0.16, 200.0, 800.0, 0.3, 1.0), v("tri", 0.0, 0.16, 100.0, 400.0, 0.4, 1.0)]
		"flip":  # a whoosh sliding up to the top row (tone 0) or down (1)
			var up := tone == 0
			return [v("square", 0.0, 0.13, 300.0 if up else 1200.0, 1200.0 if up else 300.0, 0.22, 1.0),
				v("noise", 0.0, 0.13, 3000.0 if up else 9000.0, 9000.0 if up else 3000.0, 0.25, 1.2, 0.25, 0.5)]
		"wall_hold":  # a dull bump
			return [v("noise", 0.0, 0.15, 800.0, 200.0, 0.6, 2.0, 0.25, 0.5), v("tri", 0.0, 0.15, 90.0, 40.0, 0.8, 1.6)]
		"launch_hit":
			return [v("noise", 0.0, 0.16, 900.0, 200.0, 0.65, 2.0, 0.25, 0.5), v("tri", 0.0, 0.16, 100.0, 40.0, 0.8, 1.6),
				v("square", 0.0, 0.1, 70.0, 40.0, 0.25, 1.5)]
		"flute_tick":  # a muted click: a short low-passed tap of noise on a soft little thump
			return [v("noise", 0.0, 0.035, 3000.0, 1500.0, 0.5, 2.5, 0.25, 0.6), v("tri", 0.0, 0.03, 300.0, 200.0, 0.3, 2.0)]
		"flute":  # the note on a triangle, a breath of air with it
			return [v("tri", 0.0, 0.12, hz(tone), hz(tone), 0.85, 0.7, 0.25, 0.0, 0.01),
				v("noise", 0.0, 0.12, 6000.0, 4000.0, 0.1, 1.0, 0.25, 0.6, 0.01)]
	return []


## The voices mixed into a 22050 Hz 16-bit sound, peaking at PEAK.
static func render(voices: Array) -> AudioStreamWAV:
	var length := 0.0
	for vo in voices:
		length = maxf(length, vo.at + vo.dur)
	var n := int(RATE * length) + 1
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for vo in voices:
		var i0 := int(vo.at * RATE)
		var m := int(vo.dur * RATE)
		var phase := 0.0
		var held := rng.randf_range(-1.0, 1.0)
		var low := 0.0  # (the low-pass's state)
		var ratio: float = vo.f1 / vo.f0
		for j in m:
			var i := i0 + j
			if i >= n:
				break
			var u := float(j) / m
			phase += vo.f0 * pow(ratio, u) / RATE  # (a slide even in pitch)
			var s := 0.0
			match vo.wave:
				"square":
					s = 1.0 if fposmod(phase, 1.0) < vo.duty else -1.0
				"tri":
					s = 1.0 - 4.0 * absf(fposmod(phase, 1.0) - 0.5)
				"noise":
					if phase >= 1.0:
						phase -= floorf(phase)
						held = rng.randf_range(-1.0, 1.0)
					s = held
			if vo.lp > 0.0:
				low += (1.0 - vo.lp) * (s - low)
				s = low
			var env: float = minf(minf(1.0, j / (vo.attack * RATE)), (m - j) / (0.003 * RATE)) * pow(1.0 - u, vo.decay)
			out[i] += s * vo.vol * env
	var top := 0.0
	for x in out:
		top = maxf(top, absf(x))
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	var k: float = PEAK / maxf(top, 0.001)
	for i in n:
		pcm.encode_s16(i * 2, int(clampf(out[i] * k, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = pcm
	return wav


static func make_whoosh() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.45)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var phase := 0.0
	var noise := 0.0
	for i in n:
		var u := float(i) / n
		var env := minf(1.0, u * 6.0) * pow(1.0 - u, 1.5)  # quick swell, long fade
		phase += TAU * lerpf(220.0, 900.0, u * u) / rate
		noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.1 + 0.5 * u)  # air that brightens as it rises
		pcm.encode_s16(i * 2, int(clampf((0.4 * sin(phase) + 0.6 * noise) * env, -1.0, 1.0) * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = pcm
	return wav
