extends RefCounted
## The song's MIDI, note by note (data/levels/levelN_midi.json, made by tools/midi_notes.py from the transcription):
## tracks kick, clap, hat (the drum kit split by sound), bass, arp, lead. Every mechanic and the background take their
## notes from here, so everything in a level stands on a real note. A note is [start s, length s, pitch, velocity].
## Drum velocities vary (accents are loud notes); bass / arp / lead have one velocity each, so for those only pitch and
## length carry meaning.

var tracks := {}
var _starts := {}               # track -> PackedFloat64Array of start times
var window: Array = []          # [t0, t1]: notes() and between() only give notes starting in it (a mechanic's section)


func load_for(level_path: String) -> void:
	var path := level_path.get_basename() + "_midi.json"
	if not FileAccess.file_exists(path):
		push_warning("no MIDI notes at %s (run tools/midi_notes.py)" % path)
		return
	tracks = JSON.parse_string(FileAccess.get_file_as_string(path)).tracks
	for k in tracks:
		var s := PackedFloat64Array()
		for n in tracks[k]:
			s.append(n[0])
		_starts[k] = s


func notes(track: String) -> Array:
	if not window.is_empty():
		return between(track, window[0], window[1])
	return tracks.get(track, [])


## Notes of a track starting in [t0, t1).
func between(track: String, t0: float, t1: float) -> Array:
	if not _starts.has(track):
		return []
	var s: PackedFloat64Array = _starts[track]
	if not window.is_empty():
		t0 = maxf(t0, window[0])
		t1 = minf(t1, window[1])
	return tracks[track].slice(s.bsearch(t0), s.bsearch(t1))


## The note of a track whose start is closest to t ([] if the track is empty).
func nearest(track: String, t: float) -> Array:
	if not _starts.has(track) or _starts[track].is_empty():
		return []
	var s: PackedFloat64Array = _starts[track]
	var i := s.bsearch(t)
	if i >= s.size() or (i > 0 and t - s[i - 1] < s[i] - t):
		i -= 1
	return tracks[track][i]


## How far t is from the nearest note start of any of the given tracks (comma separated).
func off_by(track_list: String, t: float) -> float:
	var best := INF
	for k in track_list.split(","):
		var n := nearest(k.strip_edges(), t)
		if not n.is_empty():
			best = minf(best, absf(n[0] - t))
	return best


## Velocities of a track, lowest to highest (to tell accents from the rest).
func velocities(track: String) -> Array:
	var v := notes(track).map(func(n): return n[3])
	v.sort()
	return v
