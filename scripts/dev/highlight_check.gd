extends Node

## Dev tool: checks a highlights export folder against its own replays, so
## a re-export proves the 2026-11-11 fixes instead of asserting them.
##
##   Godot.exe --headless --path . res://scenes/dev/highlight_check.tscn -- --folder=<export folder> [--cameras]
##
## Per moment (v2 rows only; v1 rows are listed and skipped):
##   - the .replay's frame count is `replay_frames`; the 16:9 and 9:16 .avi
##     headers hold `frames`; `complete` is true exactly when they match;
##   - every event's frame is inside the clip and its kind is a known one;
##   - a goal or behind's `kick_distance` and `facts.distance` are within
##     DISTANCE_TOLERANCE of the ball's horizontal travel from `kick_frame` to
##     `event_frame`, and the kicker is at the ball on `kick_frame` (a kickless
##     score has no kick to check);
##   - generated footage has no human player.
## With --cameras it also replays each clip on a ReplayStage and reports how
## far each camera preset strays: the goal/behind follow point past the goal
## line (bug 2), and the end-on and third-person cameras outside the fence.
## Exits 1 if anything fails. Needs no renderer (--headless is fine).

const DISTANCE_TOLERANCE := 3.0
## How far the kicker may be from the ball on the frame it's kicked.
const KICKER_REACH := 2.5
const KINDS := ["kick", "handball", "mark", "tackle", "bump", "bounce", "goal", "behind", "siren"]

var _failures := 0


func _ready() -> void:
	var folder := ""
	var cameras := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--folder="):
			folder = arg.trim_prefix("--folder=")
		elif arg == "--cameras":
			cameras = true
	var text := FileAccess.get_file_as_string(folder.path_join("moments.json"))
	if text == "":
		push_error("CHECK: no moments.json in '%s'" % folder)
		get_tree().quit(2)
		return
	var doc: Dictionary = JSON.parse_string(text)
	print("CHECK: %s  version %s  footage %s  mode %s  aspect %s" % [folder.get_file(), doc.get("version"),
		doc.get("footage", "-"), (doc.match as Dictionary).get("mode", "-"), (doc.output as Dictionary).get("aspect", "both")])
	var stage: ReplayStage = null
	if cameras:
		stage = ReplayStage.new()
		add_child(stage)
		await get_tree().process_frame
	var full := _check_full_match(folder, doc)
	for row: Dictionary in doc.moments:
		await _check_row(folder, doc, row, stage)
		if full != null:
			_check_in_full(folder, row, full)
	if full != null:
		_check_match_video(folder)
	print("CHECK: %s" % ("all good" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


## The full-match recording (plan phase 1): match.replay reads to the end and
## agrees with match.json and moments.json; events and segments are in range.
## Null when the export has none.
func _check_full_match(folder: String, doc: Dictionary) -> ReplayClip:
	if not doc.has("full_match"):
		print("  full match: not recorded")
		return null
	var info: Dictionary = doc.full_match
	var full := ReplayClip.load_file(folder.path_join(String(info.replay)))
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(String(info.json))))
	var none := {"rank": 0, "type": "full_match"}
	if full == null or meta == null:
		_fail(none, "match.replay or match.json missing")
		return null
	var n := full.frame_count()
	if n != int(meta.frame_count) or n != int(info.frames) or (meta.frame_times as Array).size() != n:
		_fail(none, "frames: replay %d, match.json %d (%d times), moments.json %d" % [n, int(meta.frame_count),
			(meta.frame_times as Array).size(), int(info.frames)])
	var covered := 0
	var last := -1
	for seg: Dictionary in meta.segments:
		if int(seg.from) != last + 1 or int(seg.to) < int(seg.from):
			_fail(none, "segment %s doesn't follow frame %d" % [seg, last])
		last = int(seg.to)
		covered += int(seg.to) - int(seg.from) + 1
	if covered != n:
		_fail(none, "segments cover %d of %d frames" % [covered, n])
	var kinds := {}
	for ev: Dictionary in meta.events:
		if int(ev.frame) < 0 or int(ev.frame) >= n:
			_fail(none, "event out of range %s" % ev)
		kinds[ev.kind] = int(kinds.get(ev.kind, 0)) + 1
	var times: Array = meta.frame_times
	var worst_gap := 0.0
	for i in range(1, times.size()):
		worst_gap = maxf(worst_gap, float(times[i]) - float(times[i - 1]))
	print("  full match: %d frames, %.1f s, %d segments, worst frame gap %.0f ms, %.1f MB, events %s" % [n,
		float(meta.duration_s), (meta.segments as Array).size(), worst_gap * 1000.0,
		FileAccess.get_file_as_bytes(folder.path_join(String(info.replay))).size() / 1048576.0, kinds])
	return full


## match_video.json (plan phase 2): kept ranges tile the video, every marker
## and moment lands inside it, and each part file has the frames it claims
## (ffprobe beside ffmpeg for an .mp4, the AVI header for an .avi).
func _check_match_video(folder: String) -> void:
	var path := folder.path_join("match_video.json")
	var none := {"rank": 0, "type": "match_video"}
	if not FileAccess.file_exists(path):
		print("  match video: not rendered")
		return
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var n := int(doc.frames)
	var at := 0
	for r: Dictionary in doc.keep:
		if int(r.video_from) != at:
			_fail(none, "keep range %s starts at video frame %d, not %d" % [r, int(r.video_from), at])
		at += int(r.video_frames)
	if at != n:
		_fail(none, "keep ranges make %d frames, json says %d" % [at, n])
	var cut := 0
	for m: Dictionary in doc.markers:
		if int(m.video_frame) < 0 or int(m.video_frame) >= n:
			_fail(none, "marker out of range %s" % m)
		if m.cut:
			cut += 1
	for m: Dictionary in doc.moments:
		if int(m.video_frame) < int(m.video_from) or int(m.video_frame) > int(m.video_to):
			_fail(none, "moment %s isn't inside its own range" % m)
	var counted := 0
	for part: Dictionary in doc.parts:
		if part.file == null:
			continue   # joined into `video` and deleted
		var frames := _video_frames(folder.path_join(String(part.file)))
		counted += frames
		if frames != int(part.frames):
			_fail(none, "%s has %d frames, json says %d" % [part.file, frames, int(part.frames)])
	if doc.video != null:
		var whole := _video_frames(folder.path_join(String(doc.video)))
		if whole != n:
			_fail(none, "%s has %d frames, json says %d" % [doc.video, whole, n])
	print("  match video: %s, %d frames (%.1f s of %.1f s recorded), %d ranges, %d parts, %d markers (%d in cut time), %d moments, complete %s" % [
		doc.video, n, float(doc.video_s), float(doc.recorded_s), (doc.keep as Array).size(), (doc.parts as Array).size(),
		(doc.markers as Array).size(), cut, (doc.moments as Array).size(), doc.complete])


func _video_frames(path: String) -> int:
	if path.ends_with(".avi"):
		return _avi_frames(path)
	var ffmpeg := HighlightPaths.ffmpeg()
	if ffmpeg == "":
		return -1
	var probe := ffmpeg.get_base_dir().path_join("ffprobe.exe") if ffmpeg != "ffmpeg" else "ffprobe"
	var out: Array = []
	OS.execute(probe, ["-v", "error", "-select_streams", "v:0", "-count_packets", "-show_entries",
		"stream=nb_read_packets", "-of", "csv=p=0", path], out)
	return int(String(out[0]).strip_edges()) if not out.is_empty() else -1


## A moment's clip is the full recording's frames match_from.. byte for byte.
func _check_in_full(folder: String, row: Dictionary, full: ReplayClip) -> void:
	if not row.has("match_from"):
		_fail(row, "no match_from although the match was recorded")
		return
	var clip := ReplayClip.load_file(folder.path_join(String(row.files.replay)))
	var from := int(row.match_from)
	if int(row.match_to) - from + 1 != clip.frame_count():
		_fail(row, "match_from..match_to is %d frames, clip has %d" % [int(row.match_to) - from + 1, clip.frame_count()])
	if int(row.match_frame) - from != int(row.event_frame):
		_fail(row, "match_frame %d - match_from %d isn't event_frame %d" % [int(row.match_frame), from, int(row.event_frame)])
	for k in clip.frame_count():
		if from + k >= full.frame_count() or clip.frames[k] != full.frames[from + k]:
			_fail(row, "clip frame %d differs from full frame %d" % [k, from + k])
			return


func _fail(row: Dictionary, what: String) -> void:
	_failures += 1
	print("  FAIL %02d %s: %s" % [int(row.rank), row.type, what])


func _check_row(folder: String, doc: Dictionary, row: Dictionary, stage: ReplayStage) -> void:
	var files: Dictionary = row.files
	var clip := ReplayClip.load_file(folder.path_join(String(files.replay)))
	if clip == null:
		_fail(row, "replay missing")
		return
	if not row.has("events"):
		print("  %02d %s (v1 row: fields not checked)" % [int(row.rank), row.type])
		if stage != null:
			_check_cameras(row, clip, stage)
		return
	var summary := "%02d %-9s %-9s frames %d/%d" % [int(row.rank), row.type, row.camera, int(row.frames), int(row.replay_frames)]
	if clip.frame_count() != int(row.replay_frames):
		_fail(row, "replay has %d frames, row says %d" % [clip.frame_count(), int(row.replay_frames)])
	var complete := true
	for key: String in ["landscape", "portrait"]:
		if not files.has(key):
			continue
		var avi := _avi_frames(folder.path_join(String(files[key])))
		if avi != int(row.frames):
			_fail(row, "%s has %d frames, row says %d" % [key, avi, int(row.frames)])
		complete = complete and avi == clip.frame_count()
	if complete != bool(row.complete):
		_fail(row, "complete is %s but the video %s the replay" % [row.complete, "matches" if complete else "is shorter than"])
	for ev: Dictionary in row.events:
		if int(ev.frame) < 0 or int(ev.frame) >= clip.frame_count() or not KINDS.has(String(ev.kind)):
			_fail(row, "bad event %s" % ev)
	if String(doc.get("footage", "")) == "generated":
		for p: Dictionary in row.players:
			if bool(p.human):
				_fail(row, "generated footage has a human player (%s)" % p.name)
	if row.type == "goal" or row.type == "behind":
		if row.get("kick_frame") == null:
			summary += "  (no kick)"
		else:
			var from := clip.ball_position(int(row.kick_frame))
			var to := clip.ball_position(int(row.event_frame))
			var travel := Vector2(to.x - from.x, to.z - from.z).length()
			summary += "  kick %s %.1f m, travel %.1f m, facts %.1f m" % [row.kicker, float(row.kick_distance), travel,
				float((row.facts as Dictionary).distance)]
			# The kicker has to be at the ball when it leaves the boot.
			var at_ball := INF
			for b in (clip.meta.bodies as Array).size():
				var body: Dictionary = clip.meta.bodies[b]
				if body.kind == "player" and String(body.name) == String(row.kicker):
					var q := clip.body_position(int(row.kick_frame), b)
					at_ball = Vector2(q.x - from.x, q.z - from.z).length()
			if at_ball > KICKER_REACH:
				_fail(row, "%s is %.1f m from the ball on its kick frame" % [row.kicker, at_ball])
			for pair: Array in [["kick_distance", float(row.kick_distance)], ["facts.distance", float((row.facts as Dictionary).distance)]]:
				if absf(float(pair[1]) - travel) > DISTANCE_TOLERANCE:
					_fail(row, "%s %.1f vs the ball's travel %.1f" % [pair[0], float(pair[1]), travel])
	print("  " + summary)
	if stage != null:
		_check_cameras(row, clip, stage)


## Reads dwTotalFrames out of an AVI's main header.
func _avi_frames(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	file.seek(48)
	var n := file.get_32()
	file.close()
	return int(n)


func _check_cameras(row: Dictionary, clip: ReplayClip, stage: ReplayStage) -> void:
	stage.load_clip(clip)
	var direction := 1.0 if float(clip.meta.get("attack_dir", 1.0)) >= 0.0 else -1.0
	var line := stage._field.goal_line_x(int(direction))
	var camera := Camera3D.new()
	stage.add_child(camera)
	var report := "      cameras:"
	for preset: String in ReplayStage.CAMERA_PRESETS:
		var worst_out := 0.0
		var worst_focus := -INF
		var ball_past := -INF
		for i in clip.frame_count():
			var t := float(i) / clip.fps()
			stage.apply(t)
			stage.frame_camera(camera, preset, false, t, 1.0 / clip.fps(), i == 0)
			var p := camera.global_position
			var k := sqrt(p.x * p.x / pow(Tuning.FIELD_HALF_LENGTH + ReplayStage.END_FENCE_MARGIN, 2.0)
				+ p.z * p.z / pow(Tuning.FIELD_HALF_WIDTH + ReplayStage.END_FENCE_MARGIN, 2.0))
			worst_out = maxf(worst_out, k)
			worst_focus = maxf(worst_focus, direction * (stage.focus_point().x - line))
			ball_past = maxf(ball_past, direction * (clip.ball_position(i).x - line))
		report += "  %s fence %.2f focus %+.1f m past the line (ball %+.1f);" % [preset, worst_out, worst_focus, ball_past]
		if row.type == "goal" or row.type == "behind":
			if worst_focus > ReplayStage.FOLLOW_PAST_GOAL + 1.0:
				_fail(row, "%s camera follows %.1f m past the goal line" % [preset, worst_focus])
		if (preset == "end" or preset == "third") and worst_out > 1.01:
			_fail(row, "%s camera leaves the fence (%.2f of the oval)" % [preset, worst_out])
	camera.queue_free()
	print(report)
