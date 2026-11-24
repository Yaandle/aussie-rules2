class_name FullMatchCut
extends RefCounted

## Which stretches of a full-match recording make the full-match video, and
## where every recorded frame lands in it (docs/HIGHLIGHTS_FULLGAME_PLAN.md,
## phase 2; the user asked for breaks and dead time cut out, 2026-11-16).
##
## Dead time is read from the recording itself: the match clock (each frame's
## header) stops whenever the ball is dead (a score, out of bounds, a ball-up,
## a free kick being set, the quarter break; full_game.gd stops it in each).
## A stopped clock shorter than HighlightTable.DEAD_MIN stays in. A longer one
## keeps DEAD_KEEP_AFTER seconds from when it stopped (the goal, the whistle)
## and DEAD_KEEP_BEFORE before it starts again (the bounce, the kick-in); the
## rest is cut. Each recording segment (a quarter, or a run between pauses)
## is cut on its own, so nothing ever spans a pause.
##
## The video is an even 30 fps; the recording isn't quite (the recorder
## samples on a timer). Each kept range is resampled by its recorder times:
## video frame j of a range is recorder time t_from + j / fps, which falls
## between two recorded frames (`source_frame` gives the fractional index the
## ReplayStage poses at).

var fps := 30.0
var times := PackedFloat64Array()
## [{from, to, t_from, t_to, quarter, video_from, video_frames}], frames of
## the recording, inclusive, in order.
var keep: Array[Dictionary] = []
var video_frames := 0
## Recording frames never cut, inclusive Vector2i(from, to): each exported
## moment's stretch plus HighlightTable.MOMENT_PROTECT_LEAD/TAIL (2026-11-24:
## a goal's last ~0.9 s fell in a dead-time cut, so highlight.mp4 ended before
## the celebration). Dead time outside them is cut as before.
var protected: Array[Vector2i] = []


## `clip` is the full match (ReplayClip.load_file of match.replay), `doc` its
## match.json.
static func build(clip: ReplayClip, doc: Dictionary, protect: Array[Vector2i] = []) -> FullMatchCut:
	var cut := FullMatchCut.new()
	cut.protected = protect
	cut.fps = float(doc.get("fps", HighlightTable.RECORD_FPS))
	for t in doc.get("frame_times", []):
		cut.times.append(float(t))
	if cut.times.size() != clip.frame_count():
		# No usable times: assume even spacing.
		cut.times.resize(clip.frame_count())
		for i in clip.frame_count():
			cut.times[i] = float(i) / cut.fps
	var segments: Array = doc.get("segments", [])
	if segments.is_empty() and clip.frame_count() > 0:
		segments = [{"from": 0, "to": clip.frame_count() - 1, "quarter": 0}]
	for seg: Dictionary in segments:
		cut._cut_segment(clip, int(seg.from), int(seg.to), int(seg.get("quarter", 0)))
	var at := 0
	for range_ in cut.keep:
		range_["video_from"] = at
		range_["video_frames"] = int(floor((float(range_.t_to) - float(range_.t_from)) * cut.fps)) + 1
		at += int(range_.video_frames)
	cut.video_frames = at
	return cut


func _cut_segment(clip: ReplayClip, from: int, to: int, quarter: int) -> void:
	if to < from:
		return
	# A frame is live when the clock moved since the one before it.
	var live := PackedByteArray()
	live.resize(to - from + 1)
	for i in range(from, to + 1):
		var j := i - from
		if i == from:
			live[j] = 1 if to > from and _clock(clip, from) != _clock(clip, from + 1) else 0
		else:
			live[j] = 1 if _clock(clip, i) != _clock(clip, i - 1) else 0
	var cuts: Array[Vector2i] = []   ## recorder frames to drop, inclusive
	var i := from
	while i <= to:
		if live[i - from] == 1:
			i += 1
			continue
		var s := i
		while i <= to and live[i - from] == 0:
			i += 1
		var e := i - 1
		if times[e] - times[s] < HighlightTable.DEAD_MIN:
			continue
		# Nothing to see before a segment's first bounce or after its siren
		# but the build-up and the aftermath, so only that end is kept.
		var drop_from := times[s] + (HighlightTable.DEAD_KEEP_AFTER if s > from else 0.0)
		var drop_to := times[e] - (HighlightTable.DEAD_KEEP_BEFORE if e < to else 0.0)
		if s == from and e == to:
			continue   # never live: keep it whole rather than lose it
		var a := _first_at_or_after(drop_from, s, e)
		var b := _last_at_or_before(drop_to, s, e)
		if a <= b:
			for piece in _minus_protected(Vector2i(a, b)):
				cuts.append(piece)
	var start := from
	for c in cuts:
		if c.x > start:
			_add_keep(start, c.x - 1, quarter)
		start = c.y + 1
	if start <= to:
		_add_keep(start, to, quarter)


## `c` with every protected range taken out of it (0, 1 or more pieces).
func _minus_protected(c: Vector2i) -> Array[Vector2i]:
	var pieces: Array[Vector2i] = [c]
	for p in protected:
		var next: Array[Vector2i] = []
		for q in pieces:
			if p.y < q.x or p.x > q.y:
				next.append(q)
				continue
			if p.x > q.x:
				next.append(Vector2i(q.x, p.x - 1))
			if p.y < q.y:
				next.append(Vector2i(p.y + 1, q.y))
		pieces = next
	return pieces


## The protected ranges for `moments` (moments.json rows or Highlights'
## dictionaries: anything with match_from/match_to), padded by
## MOMENT_PROTECT_LEAD before and MOMENT_PROTECT_TAIL after, in frames at `fps`.
static func protect_moments(moments: Array, fps: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lead := roundi(HighlightTable.MOMENT_PROTECT_LEAD * fps)
	var tail := roundi(HighlightTable.MOMENT_PROTECT_TAIL * fps)
	for m: Dictionary in moments:
		if m.has("match_from") and m.has("match_to"):
			out.append(Vector2i(maxi(0, int(m.match_from) - lead), int(m.match_to) + tail))
	return out


func _add_keep(a: int, b: int, quarter: int) -> void:
	keep.append({"from": a, "to": b, "t_from": times[a], "t_to": times[b], "quarter": quarter})


func _first_at_or_after(t: float, s: int, e: int) -> int:
	for i in range(s, e + 1):
		if times[i] >= t:
			return i
	return e + 1


func _last_at_or_before(t: float, s: int, e: int) -> int:
	for i in range(e, s - 1, -1):
		if times[i] <= t:
			return i
	return s - 1


static func _clock(clip: ReplayClip, i: int) -> float:
	return clip.frames[i].decode_float(0)


## The (fractional) recording frame video frame `j` of keep range `r` shows
## (`j` may be fractional too: the Highlights screen plays between frames).
func source_frame(r: Dictionary, j: float) -> float:
	var t := float(r.t_from) + j / fps
	var a := int(r.from)
	var b := int(r.to)
	if t <= times[a]:
		return float(a)
	if t >= times[b]:
		return float(b)
	var i := times.bsearch(t, true) - 1
	i = clampi(i, a, b - 1)
	var span := times[i + 1] - times[i]
	return float(i) + (clampf((t - times[i]) / span, 0.0, 1.0) if span > 0.0 else 0.0)


## Where recording frame `frame` is in the video: {frame, cut}. A frame that
## was cut out maps to the start of the next kept range (`cut` true), or the
## last video frame when nothing follows.
func video_frame(frame: int) -> Dictionary:
	for r in keep:
		if frame < int(r.from):
			return {"frame": int(r.video_from), "cut": true}
		if frame <= int(r.to):
			var j := int(round((times[frame] - float(r.t_from)) * fps))
			return {"frame": int(r.video_from) + clampi(j, 0, int(r.video_frames) - 1), "cut": false}
	return {"frame": maxi(0, video_frames - 1), "cut": true}


## Index into `keep` of the range holding video frame `frame` (clamped).
func range_at(frame: int) -> int:
	for i in keep.size():
		if frame < int(keep[i].video_from) + int(keep[i].video_frames):
			return i
	return keep.size() - 1


## Seconds of recording kept and cut, for the screen and the log.
func summary() -> Dictionary:
	var total := times[times.size() - 1] - times[0] if times.size() > 1 else 0.0
	return {"recorded_s": total, "video_s": float(video_frames) / fps, "ranges": keep.size()}
